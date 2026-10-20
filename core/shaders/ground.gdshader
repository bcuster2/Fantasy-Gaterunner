shader_type spatial;

// Track surface: alternating flagstone bands give a strong sense of speed; bright edges mark bounds.
uniform vec4 color_a : source_color = vec4(0.56, 0.47, 0.36, 1.0);
uniform vec4 color_b : source_color = vec4(0.50, 0.42, 0.32, 1.0);
uniform vec4 edge_color : source_color = vec4(0.93, 0.82, 0.55, 1.0);
uniform float band_length = 4.0;
uniform float half_width = 4.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float band = step(0.5, fract(world_pos.z / band_length));
	float tile = step(0.5, fract(world_pos.x / (half_width * 0.5) + band * 0.5));
	vec3 c = mix(color_a.rgb, color_b.rgb, band);
	c *= 0.96 + 0.04 * tile;
	float seam = 1.0 - smoothstep(0.0, 0.04, abs(fract(world_pos.z / band_length) - 0.5) * band_length * 0.25);
	c *= 1.0 - seam * 0.12;
	float edge = smoothstep(half_width - 0.32, half_width - 0.22, abs(world_pos.x));
	ALBEDO = mix(c, edge_color.rgb, edge);
	ROUGHNESS = 0.92;
}
