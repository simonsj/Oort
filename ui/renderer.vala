using GL;
using Vector;
using Math;

[Compact]
public class Oort.ShipGfxClass {
	public static ShipGfxClass fighter;
	public static ShipGfxClass ion_cannon_frigate;
	public static ShipGfxClass assault_frigate;
	public static ShipGfxClass carrier;
	public static ShipGfxClass missile;
	public static ShipGfxClass torpedo;
	public static ShipGfxClass unknown;
	
	public static void init() {
		fighter = new ShipGfxClass();
		ion_cannon_frigate = new ShipGfxClass();
		assault_frigate = new ShipGfxClass();
		carrier = new ShipGfxClass();
		missile = new ShipGfxClass();
		torpedo = new ShipGfxClass();
		unknown = new ShipGfxClass();
	}

	public static unowned ShipGfxClass lookup(string name)
	{
		switch (name) {
			case "fighter": return fighter;
			case "ion_cannon_frigate": return ion_cannon_frigate;
			case "assault_frigate": return assault_frigate;
			case "carrier": return carrier;
			case "missile": return missile;
			case "torpedo": return torpedo;
			default: return unknown;
		}
	}
}

namespace Oort {
	class Renderer {
		public bool render_all_debug_lines = false;
		public int screen_width = 640;
		public int screen_height = 480;

		// time in seconds for a smooth scale
		private const double SMOOTH_SCALE_TIME = 0.20f;
		// here 32 is num ticks per second
		private const int SMOOTH_SCALE_STEPS = (int) (SMOOTH_SCALE_TIME * 32);

		public struct ViewScale {
			public double pre_target;
			public double current;
			public double target;
			public int num_steps;
			public int current_step;
		}
		public ViewScale view_scale;

		public Vec2 view_pos;
		public unowned Ship picked = null;
		public Game game;
		public bool render_explosion_rays = false;
		public bool follow_picked = false;

		Rand prng;
		Texture ion_beam_tex;
		Texture laser_beam_tex;

		public static void static_init() {
			if (GLEW.init()) {
				error("GLEW initialization failed");
			}
			ShipGfxClass.init();
			Oort.Ship.gfx_create_cb = on_ship_created;

			/*
			print("Vendor: %s\n", glGetString(GL_VENDOR));
			print("Renderer: %s\n", glGetString(GL_RENDERER));
			print("GL Version: %s\n", glGetString(GL_VERSION));
			//print("GLSL Version: %s\n", glGetString(GL_SHADING_LANGUAGE_VERSION));
			print("Extensions:\n%s\n", glGetString(GL_EXTENSIONS));
			*/
		}

		public Renderer(Game game, double initial_view_scale) {
			this.game = game;
			view_scale.current = initial_view_scale;
			view_scale.target = initial_view_scale;
			prng = new Rand();
			view_pos = vec2(0,0);

			ion_beam_tex = new IonBeamTexture();
			laser_beam_tex = new LaserBeamTexture();
		}

		public void init() {
			glClearColor(0.0f, 0.0f, 0.03f, 0.0f);
			glShadeModel(GL_SMOOTH);
			glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
			glEnable(GL_BLEND);
			glEnable(GL_LINE_SMOOTH);
			glEnable(GL_POINT_SMOOTH);
			glLineWidth(1.2f);
		}

		public void render() {
			prng.set_seed(0); // XXX tick seed

			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
			glLoadIdentity();

			if (follow_picked && picked != null) {
				view_pos = picked.physics.p;
			}

			foreach (unowned Ship s in game.all_ships) {
				render_ship(s);
			}

			foreach (unowned Bullet b in game.all_bullets) {
				render_bullet(b);
			}

			foreach (unowned Beam b in game.all_beams) {
				render_beam(b);
			}

			render_particles();
			
			if (picked != null) {
				render_picked_info(picked);
			}
		}

		void triangle_fractal(int depth) {
			double alt = 0.8660254;

			if (depth > 1) {
				glBegin(GL_LINES);
				glVertex3d(alt, 0, 0);
				glVertex3d(3*alt/4, -0.125, 0);
				glVertex3d(alt/4, -0.375, 0);
				glVertex3d(0, -0.5, 0);
				glVertex3d(alt, 0, 0);
				glVertex3d(3*alt/4, 0.125, 0);
				glVertex3d(alt/4, 0.375, 0);
				glVertex3d(0, 0.5, 0);
				glEnd();

				glPushMatrix();
				glScaled(0.5, 0.5, 0.5);
				glRotated(60, 0, 0, 1);
				glTranslated(alt, -0.5, 0);
				triangle_fractal(depth-1);
				glPopMatrix();

				glPushMatrix();
				glScaled(0.5, 0.5, 0.5);
				glRotated(-60, 0, 0, 1);
				glTranslated(alt, 0.5, 0);
				triangle_fractal(depth-1);
				glPopMatrix();
			} else {
				glBegin(GL_LINE_STRIP);
				glVertex3d(0, -0.5, 0);
				glVertex3d(alt, 0, 0);
				glVertex3d(0, 0.5, 0);
				glEnd();
			}
		}

		void render_carrier(Ship s) {
			int depth = int.min(int.max((int)Math.log2(view_scale.current*100), 2), 8);
			GLUtil.color32(s.team.color | 0xEE);
			glPushMatrix();
			glScaled(1.0, 0.7, 0.3);
			glPushMatrix();
			glScaled(0.5, 0.3, 0.5);
			GLUtil.render_circle(5);
			glPopMatrix();
			triangle_fractal(depth);
			glPushMatrix();
			glRotated(180, 0, 0, 1);
			triangle_fractal(depth);
			glPopMatrix();
			glPopMatrix();
		}

		void render_fighter(Ship s) {
			GLUtil.color32(s.team.color | 0xAA);
			glBegin(GL_LINE_LOOP);
			glVertex3d(-0.70, -0.71, 0);
			glVertex3d(-0.70, 0.71, 0);
			glVertex3d(1, 0, 0);
			glEnd();
		}

		void render_ion_cannon_frigate(Ship s) {
			GLUtil.color32(s.team.color | 0xBB);
			glBegin(GL_LINE_LOOP);
			glVertex3d(-0.80, -0.3, 0);
			glVertex3d(-0.80, 0.3, 0);
			glVertex3d(0.95, 0.2, 0);
			glVertex3d(0.95, 0.08, 0);
			glVertex3d(0.7, 0.08, 0);
			glVertex3d(0.7, -0.08, 0);
			glVertex3d(0.95, -0.08, 0);
			glVertex3d(0.95, -0.2, 0);
			glEnd();
		}

		void render_assault_frigate(Ship s) {
			GLUtil.color32(s.team.color | 0xBB);
			glBegin(GL_LINE_LOOP);
			glVertex3d(-0.80, -0.4, 0);
			glVertex3d(-0.80, 0.4, 0);
			glVertex3d(0.0, 0.2, 0);
			glVertex3d(0.0, 0.4, 0);
			glVertex3d(0.95, 0.2, 0);
			glVertex3d(0.95, -0.2, 0);
			glVertex3d(0.0, -0.4, 0);
			glVertex3d(0.0, -0.2, 0);
			glEnd();
		}

		void render_torpedo(Ship s) {
			GLUtil.color32((uint32)0x88888800 | 0x55);
			GLUtil.render_circle(5);
		}

		void render_missile(Ship s) {
			GLUtil.color32((uint32)0x88888800 | 0x55);
			glBegin(GL_LINES);
			glVertex3d(-0.70, -0.71, 0);
			glVertex3d(-0.2, 0, 0);
			glVertex3d(-0.70, 0.71, 0);
			glVertex3d(-0.2, 0, 0);
			glVertex3d(-0.2, 0, 0);
			glVertex3d(1, 0, 0);
			glEnd();
		}

		void render_unknown(Ship s) {
			GLUtil.color32((uint32)0x88888800 | 0x55);
			GLUtil.render_circle(8);
		}

		void render_ship(Ship s) {
			var sp = S(s.physics.p);
			double angle = s.physics.h;
			double scale = view_scale.current * s.class.radius;

			glPushMatrix();
			glTranslated(sp.x, sp.y, 0);
			glScaled(scale, scale, scale);
			glRotated(Util.rad2deg(angle), 0, 0, 1);

			// XXX move into class
			if (s.class.name == "carrier") {
				render_carrier(s);
			} else if (s.class.name == "fighter") {
				render_fighter(s);
			} else if (s.class.name == "ion_cannon_frigate") {
				render_ion_cannon_frigate(s);
			} else if (s.class.name == "assault_frigate") {
				render_assault_frigate(s);
			} else if (s.class.name == "missile") {
				render_missile(s);
			} else if (s.class.name == "torpedo") {
				render_torpedo(s);
			} else {
				render_unknown(s);
			}

			glPopMatrix();

			int tail_alpha_max = (s.class.name.contains("missile") || s.class.name.contains("torpedo")) ? 16 : 64;
			glBegin(GL_LINE_STRIP);
			GLUtil.color32(s.team.color | tail_alpha_max);
			glVertex3d(sp.x, sp.y, 0);
			int i;
			for (i = 0; i < Ship.TAIL_SEGMENTS-1; i++) {
				int j = s.tail_head - i - 1;
				if (j < 0) j += Ship.TAIL_SEGMENTS;
				Vec2 sp2 = S(s.tail[j]);
				if (isnan(sp2.x) != 0)
					break;
				uint32 color = s.team.color | (tail_alpha_max-(tail_alpha_max/Ship.TAIL_SEGMENTS)*i);

				GLUtil.color32(color);
				glVertex3d(sp2.x, sp2.y, 0);
			}
			glEnd();

			if (s == picked) {
				GLUtil.color32((uint32)0xCCCCCCAA);
				glPushMatrix();
				glTranslated(sp.x, sp.y, 0);
				glScaled(scale, scale, scale);
				GLUtil.render_circle(64);
				glPopMatrix();

				GLUtil.color32((uint32)0xCCCCCC77);
				glPushMatrix();
				glTranslated(sp.x, sp.y, 0);
				glScaled(view_scale.current, view_scale.current, view_scale.current);
				glRotated(Util.rad2deg(s.physics.h), 0, 0, 1);
				glBegin(GL_LINES);
				glVertex3d(0, 0, 0);
				glVertex3d(s.physics.acc.x, s.physics.acc.y, 0);
				glEnd();
				glPopMatrix();

				GLUtil.color32((uint32)0x49D5CEAA);
				glBegin(GL_LINE_STRIP);
				glVertex3d(sp.x, sp.y, 0);
				Physics q = s.physics.copy();
				for (double j = 0; j < 1/Game.TICK_LENGTH; j++) {
					q.tick_one();
					Vec2 sp2 = S(q.p);
					glVertex3d(sp2.x, sp2.y, 0);
				}
				glEnd();
			}

			if (s == picked || render_all_debug_lines) {
				GLUtil.color32((uint32)0x49D5CEAA);
				glBegin(GL_LINES);
				for (int j = 0; j < s.debug.num_lines; j++) {
					Vec2 sa = S(s.debug.lines[j].a);
					Vec2 sb = S(s.debug.lines[j].b);
					glVertex3d(sa.x, sa.y, 0);
					glVertex3d(sb.x, sb.y, 0);
				}
				glEnd();
			}

			// XXX move
			if (s == picked && s.dead) {
				picked = null;
			}
		}

		private void render_bullet(Bullet b) {
			Oort.GLUtil.color32((uint32)0xFFFFFFAA);

			if (b.dead) return;

			if (b.type == Oort.BulletType.SLUG) {
				var dp = b.physics.v.scale(1.0/64);
				var offset = b.physics.v.scale(prng.next_double()/64);
				var p1 = b.physics.p.add(offset);
				var p2 = b.physics.p.add(offset).add(dp);
				var sp1 = S(p1);
				var sp2 = S(p2);

				glBegin(GL_LINE_STRIP);
				Oort.GLUtil.color32(0x44444455);
				glVertex3d(sp1.x, sp1.y, 0);
				Oort.GLUtil.color32(0x444444FF);
				glVertex3d(sp2.x, sp2.y, 0);
				glEnd();
			} else if (b.type == Oort.BulletType.REFUEL) {
				double scale = view_scale.current * b.physics.r;
				var sp = S(b.physics.p);
				GLUtil.color32((uint32)0x777777AA);
				glPushMatrix();
				glTranslated(sp.x, sp.y, 0);
				glScaled(scale, scale, scale);
				GLUtil.render_circle(20);
				glPopMatrix();
			} else if (render_explosion_rays && b.type == Oort.BulletType.EXPLOSION) {
				var dp = b.physics.v.scale(Game.TICK_LENGTH);
				var sp1 = S(b.physics.p);
				var sp2 = S(b.physics.p.add(dp));

				glBegin(GL_LINE_STRIP);
				Oort.GLUtil.color32(0xFFFFFF33u);
				glVertex3d(sp1.x, sp1.y, 0);
				Oort.GLUtil.color32(0xFFFFFF22u);
				glVertex3d(sp2.x, sp2.y, 0);
				glEnd();
			}
		}

		private void render_beam(Beam b) {
			Oort.GLUtil.color32((uint32)0xFFFFFFAA);
			Texture tex = null;
			var offset = 0.0;
			var sp = S(b.p);
			var angle = b.a;
			var length = b.length;
			var width = b.width/2;

			if (b.graphics == Oort.BeamGraphics.ION) {
				tex = ion_beam_tex;
				offset = 0.7*40;
			} else if (b.graphics == Oort.BeamGraphics.LASER) {
				tex = laser_beam_tex;
			}

			glPushMatrix();
			glTranslated(sp.x, sp.y, 0);
			glRotated(Util.rad2deg(angle), 0, 0, 1);
			glScaled(view_scale.current, view_scale.current, view_scale.current);
			glEnable(GL_TEXTURE_2D);
			glBlendFunc(GL_ONE, GL_ONE);
			tex.bind();
			glBegin(GL_QUADS);
			Oort.GLUtil.color32(0x6464FFAA);
			glTexCoord2f(0, 0);
			glVertex3d(offset, width, 0);
			glTexCoord2f(1.0f, 0);
			glVertex3d(offset, -width, 0);
			glTexCoord2f(1.0f, 1.0f);
			glVertex3d(length, -width, 0);
			glTexCoord2f(0, 1.0f);
			glVertex3d(length, width, 0);
			glEnd();
			glBindTexture(GL_TEXTURE_2D, 0);
			glDisable(GL_TEXTURE_2D);
			glPopMatrix();
			glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
		}

		private void render_particles() {
			for (int i = 0; i < Particle.MAX; i++) {
				unowned Particle c = Particle.get(i);
				if (c.ticks_left == 0) continue;
				Vec2 p = S(c.p);
				if (c.type == ParticleType.HIT) {
					glPointSize((float)(0.3*c.ticks_left*view_scale.current/32));
					glColor4ub(255, 200, 200, c.ticks_left*8);
				} else if (c.type == ParticleType.PLASMA) {
					glPointSize((float)(0.15*c.ticks_left*view_scale.current/32));
					glColor4ub(255, 0, 0, c.ticks_left*32);
				} else if (c.type == ParticleType.ENGINE) {
					glPointSize((float)(0.1*c.ticks_left*view_scale.current/32));
					glColor4ub(255, 217, 43, 10 + c.ticks_left*5);
				} else if (c.type == ParticleType.EXPLOSION) {
					var s = c.v.abs();
					glPointSize((float)((0.05 + 0.05*c.ticks_left)*view_scale.current/32));
					GLubyte r = 255;
					GLubyte g = (GLubyte)(255*double.min(1.0, 0.0625*s+c.ticks_left*0.1));
					GLubyte b = 50;
					GLubyte a = 10 + c.ticks_left*20;
					glColor4ub(r, g, b, a);
				}
				glBegin(GL_POINTS);
				glVertex3d(p.x, p.y, 0);
				glEnd();
			}
		}

		private string fmt(double v, string unit) {
			var i = 0;
			var sign = v < 0 ? -1 : 1;
			var prefixes = " kMGTPEZY";
			for (i = 0; i < prefixes.length && sign*v >= 1000; i++) {
				v /= 1000;
			}
			if (sign*v < 1e-9) {
				v = 0;
			}
			var prefix = i == 0 ? "" : "%c".printf((int)prefixes[i]);
			return "%0.3g %s%s".printf(v, prefix, unit);
		}

		private void render_picked_info(Ship s) {
			int x = 15;
			int dy = 12;
			int y = 22+11*dy;
			var rv = s.physics.v.rotate(-s.physics.h);
			GLUtil.color32((uint32)0xAAFFFFAA);
			GLUtil.printf(x, y-0*dy, "%s %.8x %s", s.class.name, s.api_id, s.controlled ? "(player controlled)" : "");
			GLUtil.printf(x, y-1*dy, "hull: %s", fmt(s.hull,"J"));
			GLUtil.printf(x, y-2*dy, "position: (%s, %s)", fmt(s.physics.p.x,"m"), fmt(s.physics.p.y,"m"));
			GLUtil.printf(x, y-3*dy, "heading: %s", fmt(s.physics.h,"rad"));
			GLUtil.printf(x, y-4*dy, "velocity: (%s, %s) rel=(%s, %s)",
			                         fmt(s.physics.v.x,"m/s"), fmt(s.physics.v.y,"m/s"),
			                         fmt(rv.x,"m/s"), fmt(rv.y,"m/s"));
			GLUtil.printf(x, y-5*dy, "angular velocity: %s", fmt(s.physics.w,"rad/s"));
			GLUtil.printf(x, y-6*dy, "acceleration:");
			GLUtil.printf(x, y-7*dy, " main: %s", fmt(s.physics.acc.x,"m/s\xFD"));
			GLUtil.printf(x, y-8*dy, " lateral: %s", fmt(s.physics.acc.y,"m/s\xFD"));
			GLUtil.printf(x, y-9*dy, " angular: %s", fmt(s.physics.wa,"rad/s\xFD"));
			GLUtil.printf(x, y-10*dy, "energy: %s", fmt(s.get_energy(),"J"));
			GLUtil.printf(x, y-11*dy, "reaction mass: %s", fmt(s.get_reaction_mass()*1000,"g"));
		}

		public void reshape(int width, int height) {
			screen_width = width;
			screen_height = height;
			glViewport (0, 0, (GLsizei)width, (GLsizei)height);
			glMatrixMode (GL_PROJECTION);
			glLoadIdentity ();
			glOrtho(0.0f, width, height, 0.0f, -1.0f, 1.0f);
			glMatrixMode (GL_MODELVIEW);
			glLoadIdentity ();
		}

		public void tick_zoom() {
			if (view_scale.current != view_scale.target) {
				if (view_scale.current_step == (view_scale.num_steps - 1)) {
					view_scale.current = view_scale.target;
				} else {
					double delta = (view_scale.target - view_scale.pre_target);
					double this_step = ((delta / view_scale.num_steps) * view_scale.current_step);
					view_scale.current = (this_step + view_scale.pre_target);
					view_scale.current_step = view_scale.current_step + 1;
				}
			}
		}

		public void tick() {
			foreach (unowned Bullet b in game.all_bullets) {
				if (b.dead) continue;
				if (b.type == BulletType.PLASMA) {
					Particle.shower(ParticleType.PLASMA, b.physics.p, vec2(0,0), b.physics.v.scale(1.0/63),
							            double.min(b.physics.m/5,0.1)*80, 3, 4, 6);
				} else if (b.type == BulletType.EXPLOSION) {
					if (prng.next_double() < 0.1) {
						Particle.shower(ParticleType.EXPLOSION, b.physics.p, vec2(0,0), b.physics.v.scale(Game.TICK_LENGTH).scale(0.001), 8, 5, 17, 6);
					}
				}
			}

			foreach (unowned BulletHit hit in game.bullet_hits) {
				var n = uint16.max((uint16)(hit.e/10000),1);
				Particle.shower(ParticleType.HIT, hit.cp, hit.s.physics.v.scale(Game.TICK_LENGTH), vec2(0,0), 8, 1, 20, n);
			}

			foreach (unowned BeamHit hit in game.beam_hits) {
				var n = uint16.max((uint16)(hit.e/500),1);
				Particle.shower(ParticleType.HIT, hit.cp, hit.s.physics.v.scale(Game.TICK_LENGTH), vec2(0,0), 8, 1, 20, n);
			}

			foreach (unowned Ship s in game.all_ships) {
				if (s.physics.acc.abs() != 0) {
					var vec_main = vec2(-s.physics.acc.x, 0).rotate(s.physics.h).scale(s.physics.m/1000);
					var vec_lateral = vec2(0, -s.physics.acc.y).rotate(s.physics.h).scale(s.physics.m/1000);
					Particle.shower(ParticleType.ENGINE, s.physics.p, s.physics.v.scale(Game.TICK_LENGTH), vec_main.scale(Game.TICK_LENGTH), 1, 2, 4, 8);
					Particle.shower(ParticleType.ENGINE, s.physics.p, s.physics.v.scale(Game.TICK_LENGTH), vec_lateral.scale(Game.TICK_LENGTH), 1, 2, 4, 8);
				}
			}
		}

		public Vec2 center() {
			return vec2(screen_width/2, screen_height/2);
		}

		public Vec2 S(Vec2 p) {
			return p.sub(view_pos).scale(view_scale.current).add(center());
		}

		public Vec2 W(Vec2 o) {
			return o.sub(center()).scale(1/view_scale.current).add(view_pos);
		}

		// XXX find ship with minimum distance, allow 5 px error
		public void pick(int x, int y) {
			Vec2 p = W(vec2(x, y));
			picked = null;
			double min_dist = 10/view_scale.current;
			foreach (unowned Ship s in game.all_ships) {
				var dist = s.physics.p.distance(p);
				if (!s.dead && ((dist < min_dist) || (picked == null && dist < s.physics.r))) {
					picked = s;
					if (dist < min_dist) min_dist = dist;
				}
			}
		}

		// XXX const
		double zoom_force = 0.1;
		double min_view_scale = 0.05;
		double max_view_scale = 6.0;

		private void zoom_update_view_pos(int x, int y) {
			if (view_scale.current != min_view_scale && view_scale.current != max_view_scale) {
				view_pos = view_pos.scale(1-zoom_force).add(W(vec2(x,y)).scale(zoom_force));
			}
		}

		// x: x position of mouse pointer on-screen
		// y: y position of mouse pointer on-screen
		// f: a zoom factor, in percentage, so (1.0f == 100%) (would have no effect)
		public void zoom(int x, int y, double f) {
			zoom_update_view_pos(x, y);
			view_scale.current *= f;
			view_scale.current = double.min(double.max(view_scale.current, min_view_scale), max_view_scale);
			view_scale.target = view_scale.current;
		}

		// x: x position of mouse pointer on-screen
		// y: y position of mouse pointer on-screen
		// f: a zoom factor, in percentage, so (1.0f == 100%) (would have no effect)
		//
		// The zoom factor is set to view_scale.target, and the
		// actual view_scale.current is updated every tick()
		// accordingly.
		public void zoom_smooth(int x, int y, double f) {
			zoom_update_view_pos(x, y);

			view_scale.pre_target = view_scale.current;
			view_scale.num_steps = SMOOTH_SCALE_STEPS;
			view_scale.current_step = 1;

			view_scale.target *= f;
			view_scale.target = double.min(double.max(view_scale.target, min_view_scale), max_view_scale);
		}

		static void on_ship_created(Ship s)
		{
			s.gfx.class = ShipGfxClass.lookup(s.class.name);
		}
	}

	namespace GLUtil {
		public void printf(int x, int y, string fmt, ...) {
			va_list ap = va_list();
			var str = fmt.vprintf(ap);
			write(x, y, str);
		}

		public void write(int x, int y, string str)
		{
			assert(font != null);
			if (GLEW.ARB_window_pos) {
				GLEW.glWindowPos2i(x, y);
				glPixelStorei(GL_UNPACK_ALIGNMENT, 1); 
				unowned uint8 *data = str.data;

				for (int i = 0; data[i] != 0; i++) {
					glBitmap(8, 8, 4, 4, 9, 0, (GLubyte*)font + 8*data[i]);
				}
			}
		}

		public void color32(uint32 c) {
			GLubyte r = (GLubyte) ((c >> 24) & 0xFF);
			GLubyte g = (GLubyte) ((c >> 16) & 0xFF);
			GLubyte b = (GLubyte) ((c >> 8) & 0xFF);
			GLubyte a = (GLubyte) (c & 0xFF);
			glColor4ub(r, g, b, a);
		}

		public void render_circle(int n)
		{
			double da = 2*Math.PI/n, a = 0;
			int i;

			glBegin(GL_LINE_LOOP);
			for (i = 0; i < n; i++) {
				a += da;
				glVertex3d(cos(a), sin(a), 0);
			}
			glEnd();
		}
	}

	public double normalize_angle(double a)
	{
		if (a < -PI) a += 2*PI;
		if (a > PI) a -= 2*PI;
		return a;
	}
}
