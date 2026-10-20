shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Gate panel: translucent tinted pane with bright frame and a rising shimmer.
uniform vec4 tint : source_color = vec4(0.25, 0.65, 1.0, 1.0);
uniform float flash = 0.0;
uniform float alpha_mul = 1.0;

void fragment() {
	vec2 d = abs(UV - 0.5);
	float edge = max(smoothstep(0.43, 0.49, d.x), smoothstep(0.45, 0.495, d.y));
	float shimmer = 0.5 + 0.5 * sin(UV.y * 9.0 + TIME * 4.0 + UV.x * 3.0);
	vec3 c = tint.rgb * (0.75 + 0.35 * shimmer) + vec3(edge * 0.7);
	c = mix(c, vec3(1.0), flash);
	ALBEDO = c;
	ALPHA = clamp((0.34 + 0.6 * edge + 0.1 * shimmer + flash * 0.6) * alpha_mul, 0.0, 1.0);
}
