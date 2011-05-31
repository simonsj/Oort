using Gtk;
using Gdk;
using Lua;
using Oort;

uint32 opt_seed;

const OptionEntry[] options = {
	{ "seed", 's', 0, OptionArg.INT, ref opt_seed, "Random number generator seed", null },
	{ null }
};

namespace Oort {
	class MenuBuilder : GLib.Object {
		public delegate void MenuAction();
		public void leaf(MenuShell parent, string label, MenuAction action, MainWindow.BindMenuItemUpdater? updater = null) {
			var item = new MenuItem.with_mnemonic(label);
			parent.append(item);
			item.activate.connect((widget) => action());

			if (updater != null) {
				updater(item);
			}
		}

		public delegate void MenuBuilder(MenuShell parent);
		public void menu(MenuShell parent, string label, MenuBuilder builder) {
			var item = new MenuItem.with_mnemonic(label);
			var menu = new Menu();
			item.set_submenu(menu);
			parent.append(item);
			builder(menu);
		}
	}

	class MainWindow : Gtk.Window {
		public bool paused;

		private DrawingArea drawing_area;
		private bool single_step = false;
		private bool show_fps = false;
		private bool battle_view = false;

		private const double ZOOM_RATIO = 1.2f;
		private bool smooth_zoom = true;

		private unowned Team winner = null;
		private Renderer renderer;
		private Mutex tick_lock;
		private unowned Thread<void*> ticker;
		private bool shutting_down = false;
		private Game game;

		private string current_scenario;
		private string[] current_ais;

		public void set_current_game(string? scenario, string[]? ais) {
			current_scenario = scenario;
			current_ais = ais;
			update_reload();
		}

		public bool reload_ok() {
			return ((current_scenario != null) && (current_ais != null));

		}

		private long frame_usecs = 0;
		private long sample_usecs = 0;

		enum GameState {
			DEMO,
			RUNNING,
			FINISHED,
		}

		private GameState game_state;

		public MainWindow() throws ThreadError {
			this.title = "Oort";
			this.destroy.connect(shutdown);
			set_reallocate_redraws(true);

			this.tick_lock = new Mutex();

			var vbox = new VBox(false, 0);
			vbox.pack_start(make_menubar(), false, false, 0);
			vbox.pack_start(make_drawing_area(), true, true, 0);
			add(vbox);
			show_all();
		}


		// Type for menu item updaters
		public delegate void UpdateMenuItem();

		// Type for binding menu item updaters
		public delegate void BindMenuItemUpdater(MenuItem item);

		// MenuItem updaters
		private UpdateMenuItem update_noop = (() => { });

		public UpdateMenuItem update_reload = update_noop;
		public void set_update_reload(MenuItem item) {
			this.update_reload = (() => { item.sensitive = this.reload_ok(); });
			this.update_reload();
		}

		public UpdateMenuItem update_explosions = update_noop;
		public void set_update_explosions(MenuItem item) {
			this.update_explosions = (() => {
				if (this.renderer == null) return;

				if (this.renderer.render_explosion_rays) {
					item.set_label("_Explosions Off");
				} else {
					item.set_label("_Explosions On");
				}
			});
			this.update_explosions();
		}

		public UpdateMenuItem update_battle_view = update_noop;
		public void set_update_battle_view(MenuItem item) {
			this.update_battle_view = (() => {
				if (this.renderer == null) return;

				if (this.battle_view) {
					item.set_label("_Battle mode Off");
				} else {
					item.set_label("_Battle mode On");
				}
			});
			this.update_battle_view();
		}

		public UpdateMenuItem update_smooth_zoom = update_noop;
		public void set_update_smooth_zoom(MenuItem item) {
			this.update_smooth_zoom = (() => {
				if (this.smooth_zoom) {
					item.set_label("S_mooth zoom Off");
				} else {
					item.set_label("S_mooth zoom On");
				}
			});
			this.update_smooth_zoom();
		}

		private MenuBar make_menubar() {
			var menubar = new MenuBar();
			var b = new MenuBuilder();

			b.menu(menubar, "_Game", parent => {
				b.leaf(parent, "_Load", load_game);
				b.leaf(parent, "_Reload", reload_game, this.set_update_reload);
				b.leaf(parent, "_Stop", start_demo_game);
				b.leaf(parent, "_Pause", toggle_paused);
				b.leaf(parent, "_Single step", do_single_step);
				b.leaf(parent, "_Quit", shutdown);
			});

			b.menu(menubar, "_View", parent => {
				b.leaf(parent, "Zoom _in", menu_zoom_in);
				b.leaf(parent, "Zoom _out", menu_zoom_out);
				b.leaf(parent, "_Screenshot", show_screenshot_dialog);
				b.leaf(parent, "All _debug lines", toggle_render_all_debug_lines);
				b.leaf(parent, "_Framerate", toggle_show_fps);
				b.leaf(parent, "Follo_w ship", toggle_follow_picked);
				b.leaf(parent, "_Control ship", toggle_control_picked);
				b.leaf(parent, "_Explosions On", toggle_render_explosions, this.set_update_explosions);
				b.leaf(parent, "_Battle mode On", toggle_battle_view, this.set_update_battle_view);
				b.leaf(parent, "S_mooth zoom On", toggle_smooth_zoom, this.set_update_smooth_zoom);
			});

			b.menu(menubar, "_Help", parent => {
				b.leaf(parent, "_About", show_about);
			});

			return menubar;
		}

		private DrawingArea make_drawing_area() {
			drawing_area = new DrawingArea();
			drawing_area.set_size_request(1024, 768);

			var glconfig = new GLConfig.by_mode(GLConfigMode.RGBA | GLConfigMode.DOUBLE);
			WidgetGL.set_gl_capability(drawing_area, glconfig, null, true, GLRenderType.RGBA_TYPE);

			drawing_area.add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
			drawing_area.realize.connect(on_realize_event);
			drawing_area.configure_event.connect(on_configure_event);
			drawing_area.expose_event.connect(on_expose_event);
			key_press_event.connect(on_key_press_event);
			key_release_event.connect(on_key_release_event);
			drawing_area.button_press_event.connect(on_button_press_event);
			drawing_area.scroll_event.connect(on_scroll_event);

			return drawing_area;
		}

		public void load_game() {
			var scenario_chooser = new FileChooserDialog("Select scenario", this, Gtk.FileChooserAction.OPEN,
			                                             Gtk.Stock.OK, Gtk.ResponseType.ACCEPT,
			                                             Gtk.Stock.CANCEL, Gtk.ResponseType.REJECT);
			scenario_chooser.set_current_folder(data_path("scenarios"));
			try {
				scenario_chooser.add_shortcut_folder(data_path("scenarios"));
			} catch (GLib.Error e) {}
			scenario_chooser.response.connect( (response_id) => {
				if (response_id == Gtk.ResponseType.ACCEPT) {
					var fname = scenario_chooser.get_filename();
					configure_scenario(fname);
				}
				scenario_chooser.destroy();
			});
			scenario_chooser.show();
		}

		public void reload_game() {
			if (reload_ok()) {
				ParsedScenario scn;
				try {
					print("Reloading current scenario ----\n");
					scn = Scenario.parse(this.current_scenario);
					start_game_int(opt_seed, scn, this.current_ais);
				} catch (Error e) {
					print("Failed to reload game: %s\n", e.message);
				}
			}
		}

		public void show_screenshot_dialog() {
			var saved_paused = paused;
			paused = true;
			var chooser = new FileChooserDialog("Save screenshot", this, Gtk.FileChooserAction.SAVE,
			                                    Gtk.Stock.OK, Gtk.ResponseType.ACCEPT,
			                                    Gtk.Stock.CANCEL, Gtk.ResponseType.REJECT);
			chooser.set_current_name("screenshot.tga");
			chooser.response.connect( (response_id) => {
				if (response_id == Gtk.ResponseType.ACCEPT) {
					screenshot(chooser.get_filename());
				}
				chooser.destroy();
				paused = saved_paused;
			});
			chooser.show();
		}

		public void show_about() {
			var w = new AboutDialog();
			w.transient_for = this;
			w.authors = { "Rich Lane", null };
			w.version = Config.VERSION;
			w.response.connect( (response_id) => { w.destroy(); });
			w.show();
		}

		const int million = 1000*1000;
		private void *run() {
			long usecs_target = (long) (million*Game.TICK_LENGTH);
			TimeVal last = TimeVal();
			TimeVal sample = last;
			while (true) {
				if (shutting_down) break;
				tick_lock.lock();
				tick();
				tick_lock.unlock();
				TimeVal now = TimeVal();
				frame_usecs = (7*frame_usecs + (now.tv_sec-last.tv_sec)*million + (now.tv_usec - last.tv_usec))/8;
				sample_usecs = (7*sample_usecs + (now.tv_sec-sample.tv_sec)*million + (now.tv_usec - sample.tv_usec))/8;
				sample = TimeVal();
				long usecs = (now.tv_sec-last.tv_sec)*million + (now.tv_usec - last.tv_usec);
				Thread.usleep(long.max(usecs_target - usecs, 1000));
				last = TimeVal();
			}
			return null;
		}

		private bool tick() {
			if (game != null) {
				if (!paused) {
					game.purge();
					game.tick();
					Particle.tick();

					if (renderer != null) {
						if (this.battle_view) {
							//renderer.zoom(320, 240, 1.0f);
						}
						renderer.tick();
					}

					if (game_state == GameState.RUNNING) {
						winner = game.check_victory();
						if (winner != null) {
							game_state = GameState.FINISHED;
						}
					}
				}

				if (renderer != null) {
					renderer.tick_zoom();
				}
			}
	
			if (single_step) {
				paused = true;
				single_step = false;
			}

			Timeout.add(0, trigger_redraw);

			return true;
		}

		private bool trigger_redraw() {
			var window = drawing_area.window;
			window.invalidate_rect((Rectangle)drawing_area.allocation, false);
			return false;
		}

		/* Widget is resized */
		private bool on_configure_event(Widget widget, EventConfigure event) {
			GLContext glcontext = WidgetGL.get_gl_context(widget);
			GLDrawable gldrawable = WidgetGL.get_gl_drawable(widget);

			if (!gldrawable.gl_begin(glcontext))
				return false;

			if (renderer != null) {
				renderer.reshape(widget.allocation.width, widget.allocation.height);
			}

			gldrawable.gl_end();
			return true;
		}

		/* Widget is asked to paint itself */
		private bool on_expose_event(Widget widget, EventExpose event) {
			GLContext glcontext = WidgetGL.get_gl_context(widget);
			GLDrawable gldrawable = WidgetGL.get_gl_drawable(widget);

			var rect = drawing_area.allocation;

			if (renderer == null) return true;

			if (!gldrawable.gl_begin(glcontext))
				return false;

			if (!tick_lock.trylock()) return true;

			if (battle_view) {
				// Update renderer.zoom?
			}

			renderer.render();
			
			Oort.GLUtil.color32((uint32)0xFFFFFFAA);

			if (show_fps && frame_usecs != 0 && sample_usecs != 0) {
				Oort.GLUtil.printf(rect.width-9*9, rect.height-15, "FPS: %.1f", (1000*1000.0)/sample_usecs);
				Oort.GLUtil.printf(rect.width-15*9, rect.height-25, "Max FPS: %.1f", (1000*1000.0)/frame_usecs);
			}

			switch (game_state) {
			case GameState.DEMO:
				Oort.GLUtil.printf(rect.width/2-12*9, rect.height-50, "Click Game/Load to begin");
				break;
			case GameState.RUNNING:
				break;
			case GameState.FINISHED:
				Oort.GLUtil.printf(rect.width/2-4*20, rect.height-50, "%s is victorious", winner.name);
				break;
			}

			gldrawable.swap_buffers();

			gldrawable.gl_end();

			tick_lock.unlock();
			return true;
		}

		private void on_realize_event(Widget widget) {
			GLContext glcontext = WidgetGL.get_gl_context(widget);
			GLDrawable gldrawable = WidgetGL.get_gl_drawable(widget);

			if (!gldrawable.gl_begin(glcontext))
				return;

			Renderer.static_init();

			gldrawable.gl_end();
		}

		private bool on_key_press_event(Widget widget, EventKey event) {
			int x, y;
			get_pointer(out x, out y);
			string key = Gdk.keyval_name(event.keyval);

			switch (key) {
				case "z":
					if (smooth_zoom) {
						renderer.zoom_smooth(x, y, ZOOM_RATIO);
					} else {
						renderer.zoom(x, y, ZOOM_RATIO);
					}
					break;
				case "x":
					if (smooth_zoom) {
						renderer.zoom_smooth(x, y, 1.0/ZOOM_RATIO);
					} else {
						renderer.zoom(x, y, 1.0/ZOOM_RATIO);
					}
					break;
				case "space":
					toggle_paused();
					break;
				case "s":
				case "Return":
					do_single_step();
					break;
				case "Escape":
					shutdown();
					break;
				case "y":
					toggle_render_all_debug_lines();
					break;
				case "p":
					show_screenshot_dialog();
					break;
				case "f":
					toggle_show_fps();
					break;
				case "o":
					toggle_control_picked();
					break;
				case "v":
					toggle_follow_picked();
					break;
				case "b":
					toggle_battle_view();
					break;
				case "F5":
					reload_game();
					break;
				default:
					if (renderer.picked != null && renderer.picked.controlled) {
						tick_lock.lock();
						renderer.picked.control(key, true);
						tick_lock.unlock();
					} else {
						stdout.printf("Unknown keypress: \"%s\"\n", key);
					}
					break;
			}

			return true;
		}

		private void toggle_paused() {
			paused = !paused;
		}

		private void do_single_step() {
			paused = false;
			single_step = true;
		}

		private void toggle_render_all_debug_lines() {
			renderer.render_all_debug_lines = !renderer.render_all_debug_lines;
		}

		private void toggle_show_fps() {
			show_fps = !show_fps;
		}

		private void toggle_follow_picked() {
			if (renderer.picked != null) {
				renderer.follow_picked = !renderer.follow_picked;
			}
		}

		private void toggle_control_picked() {
			if (renderer.picked != null) {
				if (!renderer.picked.controlled) {
					renderer.picked.control_begin();
				} else {
					renderer.picked.control_end();
				}
			}
		}

		private void toggle_render_explosions() {
			if (renderer == null) return;
			renderer.render_explosion_rays = !renderer.render_explosion_rays;
			this.update_explosions();
		}

		private void toggle_battle_view() {
			this.battle_view = !this.battle_view;
			this.update_battle_view();
		}

		private void toggle_smooth_zoom() {
			this.smooth_zoom = !this.smooth_zoom;
			this.update_smooth_zoom();
		}

		private void menu_zoom_in() {
			renderer.zoom(drawing_area.allocation.width/2, drawing_area.allocation.height/2, 2);
		}

		private void menu_zoom_out() {
			renderer.zoom(drawing_area.allocation.width/2, drawing_area.allocation.height/2, 0.5);
		}

		private bool on_key_release_event(Widget widget, EventKey event) {
			int x, y;
			get_pointer(out x, out y);
			string key = Gdk.keyval_name(event.keyval);

			if (renderer == null) return true;

			if (renderer.picked != null && renderer.picked.controlled) {
				renderer.picked.control(key, false);
			}

			switch (key) {
				case "z":
				case "x":
					renderer.zoom(x, y, 1.0f); // stop
					break;
				default:
					break;
			}

			return true;
		}

		private void shutdown() {
			stop_game();
			Gtk.main_quit();
		}

		private bool on_button_press_event(Widget widget, EventButton event) {
			int x, y;
			widget.get_pointer(out x, out y);

			switch (event.button) {
				case 1:
					renderer.follow_picked = false;
					tick_lock.lock();
					renderer.pick(x,y);
					tick_lock.unlock();
					break;
				default:
					break;
			}

			return true;
		}

		private bool on_scroll_event(Widget widget, EventScroll event) {
			int x, y;
			get_pointer(out x, out y);

			if (event.direction == Gdk.ScrollDirection.UP) {
				if (smooth_zoom) {
					renderer.zoom_smooth(x, y, 1.1);
				} else {
					renderer.zoom(x, y, 1.1);
				}
			} else if (event.direction == Gdk.ScrollDirection.DOWN) {
				if (smooth_zoom) {
					renderer.zoom_smooth(x, y, 1.0/1.1);
				} else {
					renderer.zoom(x, y, 1.0/1.1);
				}
			}

			return true;
		}

		public void start_game(uint32 seed, ParsedScenario scn, string[] ais) {
			try {
				start_game_int(seed, scn, ais);
			} catch (Error e) {
				warning("Game initialization failed: %s", e.message);
				start_demo_game();
			}
		}

		public void start_game_int(uint32 seed, ParsedScenario scn, string[] ais) throws FileError, ScenarioLoadError, ThreadError {
			if (game != null) stop_game();
			game = new Game(seed, scn, ais);
			set_current_game(scn.filename, ais);
			start_renderer(game, scn.initial_view_scale);

			stdout.printf("Game running (scenario: %s, seed: %u, ais: ",
			              scn.filename, seed);
			for (int i = 0; i < this.current_ais.length; i++) {
				stdout.printf("%s%s",
				              this.current_ais[i],
				              ((i != (this.current_ais.length - 1)) ? ", " : ""));
			}
			stdout.printf(")\n");

			game_state = GameState.RUNNING;
			ticker = Thread.create<void*>(this.run, true);
		}

		public void stop_game() {
			shutting_down = true;
			ticker.join();
			ticker = null;
			shutting_down = false;
			game = null;
			renderer = null;
		}

		public void start_renderer(Game game, double initial_view_scale) {
			renderer = new Renderer(game, initial_view_scale);
			GLContext glcontext = WidgetGL.get_gl_context(drawing_area);
			GLDrawable gldrawable = WidgetGL.get_gl_drawable(drawing_area);

			if (!gldrawable.gl_begin(glcontext))
				error("failed to get GL context");

			renderer.init();
			renderer.reshape(drawing_area.allocation.width, drawing_area.allocation.height);

			gldrawable.gl_end();

			this.update_explosions();
		}

		public void start_demo_game() {
			try {
				var scn = Scenario.parse(data_path("scenarios/demo1.json"));
				start_game_int(42, scn, { });
				game_state = GameState.DEMO;
			} catch (Error e) {
				error("Demo initialization failed: %s", e.message);
			}
		}

		public void configure_scenario(string scenario_filename) {
			try {
				var scn = Scenario.parse(scenario_filename);
				var w = new NewGameWindow(scn);
				w.transient_for = this;
				w.start_game.connect(start_game);
				w.show();
			} catch (Error e) {
				var w = new MessageDialog(this, DialogFlags.MODAL, MessageType.ERROR, ButtonsType.OK,
				                          "Failed to parse scenario: %s", e.message);
				w.response.connect((src,id) => { src.destroy(); });
				w.show();
			}
		}
	}

	class NewGameWindow : Gtk.Dialog {
		private ParsedScenario scn;

		private Widget ok_button;
		private Entry seed_entry;
		private FileChooserButton[] ai_choosers;

		public NewGameWindow(ParsedScenario scn) {
			this.scn = scn;
			this.title = "Load Game";
			this.has_separator = false;
			this.border_width = 5;
			set_default_size(350, 100);

			this.vbox.spacing = 10;

			var metadata_str = "Name: %s\nDescription: %s\n".printf(scn.name, scn.description);
			var metadata_label = new Label(metadata_str);
			this.vbox.pack_start(metadata_label, false, false, 0);

			this.vbox.pack_start(new Label("AIs:"), false, false, 0);
			this.ai_choosers = new FileChooserButton[4];
			var i = 0;
			foreach (ParsedTeam pteam in this.scn.user_teams) {
				var chooser_hbox = new Gtk.HBox(false, 5);
				var color = Gdk.Color() { red=pteam.color_red<<8, green=pteam.color_green<<8, blue=pteam.color_blue<<8 };
				var color_button = new Gtk.ColorButton.with_color(color);
				color_button.sensitive = false;
				chooser_hbox.pack_start(color_button, false, false, 0);
				chooser_hbox.pack_start(new Label(pteam.name + ":"), false, false, 0);
				var chooser = new FileChooserButton("AI", Gtk.FileChooserAction.OPEN);
				chooser.file_set.connect(on_ai_change);
				chooser.set_current_folder(data_path("examples"));
				try {
					chooser.add_shortcut_folder(data_path("examples"));
				} catch (GLib.Error e) {}
				this.ai_choosers[i++] = chooser;
				chooser_hbox.pack_start(chooser, true, true, 3);
				this.vbox.pack_start(chooser_hbox, false, false, 0);
			}

			var seed_hbox = new Gtk.HBox(false, 5);
			seed_hbox.pack_start(new Label("Seed:"));
			this.seed_entry = new Gtk.Entry();
			this.seed_entry.text = Random.int_range(0,1000).to_string();
			seed_hbox.pack_start(seed_entry, false, false, 0);
			this.vbox.pack_start(seed_hbox, false, false, 0);

			add_button(Gtk.Stock.CLOSE, ResponseType.CLOSE);
			this.ok_button = add_button(Gtk.Stock.OK, ResponseType.APPLY);
			this.ok_button.sensitive = 0 == this.scn.user_teams.length();

			this.response.connect(on_response);

			show_all();
		}

		private void on_ai_change() {
			var cnt = 0;
			var j = 0;
			for (j = 0; j < this.scn.user_teams.length(); j++) {
				if (ai_choosers[j].get_filename() != null) {
					cnt++;
				}
			}
			this.ok_button.sensitive = cnt == this.scn.user_teams.length();
		}

		private void on_response (Dialog source, int response_id) {
			switch (response_id) {
			case ResponseType.APPLY:
				var n = this.scn.user_teams.length();
				var ais = new string[n];
				for (var i = 0; i < n; i++) {
					ais[i] = ai_choosers[i].get_filename();
				}
				start_game(int.parse(seed_entry.text), scn, ais);
				destroy();
				break;
			case ResponseType.CLOSE:
				destroy();
				break;
			}
		}

		public signal void start_game(uint32 seed, ParsedScenario scn, string[] ais);
	}
}

int main(string[] args) {
	GLib.Intl.setlocale(LocaleCategory.ALL, "C");
	GLib.Environment.set_application_name(Config.PACKAGE_NAME);

	Paths.init(args[0]);
	print("using data from %s\n", Paths.resource_dir.get_path());

	try {
		Gtk.init_with_args(ref args, "[scenario [ai...]]", options, null);
	} catch (Error e) {
		print("%s\n", e.message);
		return 1;
	}

	Gtk.gl_init(ref args);

	if (!Thread.supported ()) {
		print("Cannot run without thread support.\n");
		return 1;
	}

	if (!ShipClass.load(data_path("ships.lua"))) {
		print("Failed to load ship classes.\n");
		return 1;
	}

	MainWindow mainwin;
	try {
		mainwin = new MainWindow();
	} catch (ThreadError e) {
		print("%s\n", e.message);
		return 1;
	}

	if (args.length <= 1) {
		mainwin.start_demo_game();
	} else {
		var scenario_filename = args[1];
		var ai_filenames = args[2:(args.length)];

		ParsedScenario scn;
		try {
			scn = Scenario.parse(scenario_filename);
		} catch (Error e) {
			print("Failed to parse scenario: %s\n", e.message);
			return 1;
		}

		try {
			mainwin.start_game_int(opt_seed, scn, ai_filenames);
		} catch (Error e) {
			print("Failed to start game: %s\n", e.message);
			return 1;
		}
	}

	Gtk.main();

	return 0;
}
