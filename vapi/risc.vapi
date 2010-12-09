[CCode (cheader_filename = "renderer.h")]
[CCode (cheader_filename = "game.h")]
[CCode (cheader_filename = "particle.h")]
[CCode (cheader_filename = "glutil.h")]
[CCode (cheader_filename = "util.h")]
[CCode (cheader_filename = "team.h")]
[CCode (cheader_filename = "physics.h")]
[CCode (cheader_filename = "bullet.h")]

namespace RISC {
	[CCode (cname = "all_bullets")]
	public GLib.List<Bullet> all_bullets;

	namespace GL13 {
    [CCode (cname = "init_gl13")]
    public void init();
    [CCode (cname = "reset_gl13")]
    public void reset();
    [CCode (cname = "render_gl13")]
    public void render(bool paused, bool render_all_debug_lines);
    [CCode (cname = "reshape_gl13")]
    public void reshape(int x, int y);
		[CCode (cname = "glutil_vprintf")]
		public void vprintf(int x, int y, string fmt, va_list ap);
		[CCode (cname = "glColor32")]
		void glColor32(uint32 c);
		[CCode (cname = "zoom")]
		public int zoom(int x, int y, double force);
		[CCode (cname = "pick")]
		public void pick(int x, int y);
    [CCode (cname = "emit_particles")]
    public void emit_particles();
	}

		[CCode (cname = "game_init")]
		public int game_init(int seed, string scenario, string[] ais);
		[CCode (cname = "game_purge")]
		public void game_purge();
		[CCode (cname = "game_tick")]
		public void game_tick(double tick_length);
		[CCode (cname = "game_shutdown")]
		public void game_shutdown();

		[CCode (cname = "particle_tick")]
		public void particle_tick();

		[CCode (cname = "screenshot")]
		public void screenshot(string filename);
		
		[CCode (cname = "find_data_dir")]
		public bool find_data_dir();
		[CCode (cname = "data_path")]
		public string data_path(string subpath);

    [CCode (cname = "struct team", destroy_function = "")]
		[Compact]
		public class Team {
			public uint32 color;
			public string name;
			public string filename;
			public int ships;
		}

    [CCode (cname = "struct physics", destroy_function = "")]
		[Compact]
		public class Physics {
			public Vector.Vec2 p;
			public Vector.Vec2 p0;
			public Vector.Vec2 v;
			public Vector.Vec2 thrust;
			public double a;
			public double av;
			public double r;
			public double m;
		}

    [CCode (cname = "struct bullet", destroy_function = "")]
		[Compact]
		public class Bullet {
			public Physics physics;
			public Team team;
			public double ttl;
			public int dead;
			public int type;
		}

		[CCode (cname = "game_check_victory")]
		public unowned Team game_check_victory();
}
