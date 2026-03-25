shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;

uniform float intensity : hint_range(0.0, 2.0) = 0.9;
uniform vec4 color_hot : source_color = vec4(1.0, 0.80, 0.25, 1.0);
uniform vec4 color_edge : source_color = vec4(0.9, 0.25, 0.03, 0.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	float alpha = pow(clamp(1.0 - dist, 0.0, 1.0), 2.2);
	vec4 col = mix(color_edge, color_hot, clamp(1.0 - dist * 1.1, 0.0, 1.0));
	ALBEDO = col.rgb * intensity;
	ALPHA = alpha * col.a;
}
