shader_type spatial;
render_mode unshaded;

uniform float cells = 8.0;

void fragment() {
	vec2 g = floor(UV * vec2(cells, cells * 0.25));
	ALBEDO = mix(vec3(0.08), vec3(0.95), mod(g.x + g.y, 2.0));
}
