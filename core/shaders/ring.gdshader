shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

// Expanding shockwave ring on the ground. progress 0 -> 1 grows the ring and fades it out.
uniform vec4 tint : source_color = vec4(1.0);
uniform float progress = 0.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float radius = mix(0.15, 0.95, progress);
	float width = mix(0.18, 0.04, progress);
	float ring = 1.0 - smoothstep(0.0, width, abs(r - radius));
	ALBEDO = tint.rgb;
	ALPHA = ring * (1.0 - progress) * tint.a;
}
