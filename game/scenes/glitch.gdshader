shader_type canvas_item;

// Full-screen glitch (pixi-filters GlitchFilter): slice the screen into horizontal
// bands and offset each by a seeded random amount, with a chromatic (RGB) split.
// Reads the back-buffer (a BackBufferCopy populates it). `seed` is driven live by
// globalEffects[0].filterConfig (move-quantized, deterministic); TIME adds a
// continuous flicker on top (presentation-only — does not affect engine state).

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float slices = 10.0;
uniform float offset_px = 15.0;
uniform float direction_deg = 0.0;
uniform float seed = 0.0;
uniform vec2 screen_size = vec2(360.0, 780.0);
uniform float flicker = 14.0;   // glitch re-randomizes this many times per second

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float ang = radians(direction_deg);
	vec2 dir = vec2(cos(ang), sin(ang));
	float band = floor(uv.y * slices);
	// Per-tick base: the engine seed shifts it per move, TIME flickers it per ~1/flicker s.
	float base = seed * 0.001 + floor(TIME * flicker) * 7.13;
	float r = hash(band * 12.9898 + base);
	float active = step(0.35, hash(band * 3.71 + base * 1.7));   // ~65% of bands shift each tick
	float shift = (r * 2.0 - 1.0) * (offset_px / screen_size.x) * active;
	vec2 disp = dir * shift;
	float ca = offset_px * 0.5 / screen_size.x * active;         // chromatic split on shifted bands
	vec4 col;
	col.r = texture(screen, uv + disp + vec2(ca, 0.0)).r;
	col.g = texture(screen, uv + disp).g;
	col.b = texture(screen, uv + disp - vec2(ca, 0.0)).b;
	col.a = 1.0;
	COLOR = col;
}
