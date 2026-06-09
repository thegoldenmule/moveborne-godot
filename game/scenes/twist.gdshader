shader_type canvas_item;

// Black-hole swirl (pixi-filters TwistFilter on the overlay). Rotates the texture's
// UVs around the center by an angle that's strongest at the center and fades to 0 at
// `radius`, so the overlay art spirals like a vortex. Self-animated via TIME, so a
// single shared material can drive every black-hole overlay (HIGH quality only).

uniform float rate = 1.2;        // oscillation phase rate, rad/s (TS 0.02/frame * 60fps)
uniform float amplitude = 1.0;   // max twist in radians (TS angle = sin(...) * 1)
uniform float radius = 0.5;      // twist falloff radius (UV units; 0.5 ~ the whole rect)

void fragment() {
	vec2 c = UV - vec2(0.5);
	float d = length(c);
	float t = smoothstep(radius, 0.0, d);   // more twist toward the center
	// Bounded back-and-forth oscillation (matches the TS sin-driven TwistFilter), not
	// an ever-increasing spin — periodically returns to the untwisted base art.
	float a = sin(TIME * rate) * amplitude * t;
	float s = sin(a);
	float co = cos(a);
	vec2 uv = vec2(c.x * co - c.y * s, c.x * s + c.y * co) + vec2(0.5);
	COLOR = texture(TEXTURE, uv);
}
