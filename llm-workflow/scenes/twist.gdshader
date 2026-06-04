shader_type canvas_item;

// Black-hole swirl (pixi-filters TwistFilter on the overlay). Rotates the texture's
// UVs around the center by an angle that's strongest at the center and fades to 0 at
// `radius`, so the overlay art spirals like a vortex. Self-animated via TIME, so a
// single shared material can drive every black-hole overlay (HIGH quality only).

uniform float speed = 1.4;     // swirl rate (rad/s at the center)
uniform float radius = 0.5;    // twist falloff radius (UV units; 0.5 ~ the whole rect)

void fragment() {
	vec2 c = UV - vec2(0.5);
	float d = length(c);
	float t = smoothstep(radius, 0.0, d);   // more twist toward the center
	float a = TIME * speed * t;
	float s = sin(a);
	float co = cos(a);
	vec2 uv = vec2(c.x * co - c.y * s, c.x * s + c.y * co) + vec2(0.5);
	COLOR = texture(TEXTURE, uv);
}
