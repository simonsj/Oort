namespace Oort {
	[CCode (cheader_filename = "particle.h")]
	public enum ParticleType {
		[CCode (cname = "PARTICLE_HIT")]
		HIT,
		[CCode (cname = "PARTICLE_PLASMA")]
		PLASMA,
		[CCode (cname = "PARTICLE_ENGINE")]
		ENGINE,
		[CCode (cname = "PARTICLE_EXPLOSION")]
		EXPLOSION,
	}

	[CCode (cname = "struct particle", destroy_function = "", cheader_filename = "particle.h")]
	[Compact]
	public class Particle {
		public Vector.Vec2 p;
		public Vector.Vec2 v;
		public uint16 ticks_left;
		public ParticleType type;

		[CCode (cname = "MAX_PARTICLES")]
		public static int MAX;

		[CCode (cname = "particles")]
		public static Particle array[];

		[CCode (cname = "particle_get")]
		public static unowned Particle get(int i);

		[CCode (cname = "particle_create")]
		public static void create(ParticleType type, Vector.Vec2 p, Vector.Vec2 v, uint16 lifetime);
		[CCode (cname = "particle_shower")]
		public static void shower(ParticleType type,
		                          Vector.Vec2 p0, Vector.Vec2 v0, Vector.Vec2 v,
		                          double s_max, uint16 life_min, uint16 life_max,
		                          uint16 count);
		[CCode (cname = "particle_tick")]
		public static void tick();
	}
}
