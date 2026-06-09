shader_type canvas_item;

// Soft outer glow for MSDF-font Labels (pixi-filters GlowFilter on tile numbers).
// Reads the multichannel signed distance field, renders the crisp glyph in the
// Label's font color (COLOR = font_color * modulate), and adds a gradient halo in
// glow_color that fades outward from the glyph edge. Requires the font imported
// with multichannel_signed_distance_field = on. Glow extent is bounded by the
// font's msdf_pixel_range.

uniform vec4 glow_color : source_color = vec4(0.706, 0.0, 1.0, 1.0);
uniform float glow_width = 0.30;     // 0..0.5 — how far the halo reaches past the edge
uniform float glow_intensity = 1.0;

float median3(float r, float g, float b) {
	return max(min(r, g), min(max(r, g), b));
}

void fragment() {
	vec3 m = texture(TEXTURE, UV).rgb;
	float sd = median3(m.r, m.g, m.b);                    // ~0.5 at the glyph edge
	float aa = fwidth(sd);
	float glyph = smoothstep(0.5 - aa, 0.5 + aa, sd);     // crisp fill mask
	float halo = clamp(smoothstep(0.5 - glow_width, 0.5, sd) * glow_intensity, 0.0, 1.0);
	vec3 col = mix(glow_color.rgb, COLOR.rgb, glyph);     // glow behind, fill on top
	float a = max(glyph * COLOR.a, halo * glow_color.a);
	COLOR = vec4(col, a);
}
