using Oort;

uint32 opt_seed;
int opt_max_ticks;

const OptionEntry[] options = {
	{ "seed", 's', 0, OptionArg.INT, ref opt_seed, "Random number generator seed", null },
	{ "max-ticks", 0, 0, OptionArg.INT, ref opt_max_ticks, "Exit after given number of ticks", null },
	{ null }
};

int main(string[] args) {
	GLib.Intl.setlocale(LocaleCategory.ALL, "C");
	GLib.Environment.set_application_name(Config.PACKAGE_NAME);

	Paths.init(args[0]);
	stderr.printf("using data from %s\n", Oort.Paths.resource_dir.get_path());

	opt_seed = 0;
	opt_max_ticks = -1;

	var optctx = new OptionContext("");
	optctx.add_main_entries(options, null);
	try {
		optctx.parse(ref args);
	} catch (OptionError e) {
		stderr.printf("%s\n", e.message);
		return 1;
	}

	if (!Thread.supported()) {
		stderr.printf("Cannot run without thread support.\n");
		return 1;
	}

	if (!ShipClass.load(data_path("ships.lua"))) {
		stderr.printf("Failed to load ship classes.\n");
		return 1;
	}

	if (args.length < 2) {
		stderr.printf("Scenario argument required.\n");
		return 1;
	}

	var scenario_filename = args[1];
	var ai_filenames = args[2:(args.length)];

	ParsedScenario scn;
	try {
		scn = Scenario.parse(scenario_filename);
	} catch (Error e) {
		error("Failed to parse scenario: %s", e.message);
	}

	if (ai_filenames.length != scn.user_teams.length()) {
		stderr.printf("expected %u AIs, got %d.\n", scn.user_teams.length(), ai_filenames.length);
		return 1;
	}

	Game game;
	try {
		game = new Game(opt_seed, scn, ai_filenames);
	} catch (Error e) {
		error("Game initialization failed: %s", e.message);
	}

	TimeVal last_sample_time = TimeVal();
	int sample_ticks = 0;
	bool callgrind_collection_started = false;

	while (true) {
		TimeVal now = TimeVal();
		long usecs = (now.tv_sec-last_sample_time.tv_sec)*(1000*1000) + (now.tv_usec - last_sample_time.tv_usec);
		if (usecs > 1000*1000) {
			stderr.printf("%g FPS\n", (1000.0*1000*sample_ticks/usecs));
			sample_ticks = 0;
			last_sample_time = now;
		}

		if (opt_max_ticks >= 0 && game.ticks >= opt_max_ticks) {
			stderr.printf("exiting after %d ticks\n", game.ticks);
			break;
		}

		if (game.ticks == 10) {
			callgrind_collection_started = true;
		}

		if (callgrind_collection_started) {
			Util.toggle_callgrind_collection();
		}

		game.tick();
		game.purge();

		if (callgrind_collection_started) {
			Util.toggle_callgrind_collection();
		}

		unowned Team winner = game.check_victory();
		if (winner != null) {
			stderr.printf("Team '%s' (%s) is victorious in %0.2f seconds\n", winner.name, winner.filename, game.ticks*Game.TICK_LENGTH);
			stdout.printf(@"$(winner.filename)\t$(opt_seed)\t$(winner.id)\t$(winner.name)\t$(game.ticks*Game.TICK_LENGTH)\n");
			break;
		}

		sample_ticks++;
	}

	return 0;
}
