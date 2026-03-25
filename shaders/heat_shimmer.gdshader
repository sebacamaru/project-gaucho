shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;

uniform float time_scale : hint_range(0.1, 4.0) = 1.4;
uniform float intensity : hint_range(0.0, 1.0) = 0.22;
uniform vec4 shimmer_color : source_color = vec4(1.0, 0.65, 0.2, 1.0);

void fragment() {
	float t = TIME * time_scale;
	vec2 uv = UV;

	float wave1 = sin(uv.x * 11.0 + t * 2.2) * 0.5 + 0.5;
	float wave2 = sin(uv.x * 7.0  - t * 1.5 + 1.8) * 0.5 + 0.5;
	float wave  = (wave1 + wave2) * 0.5;

	float shape_x  = pow(1.0 - abs(uv.x - 0.5) * 2.0, 1.4);
	float fade_bot = smoothstep(0.0, 0.25, uv.y);
	float fade_top = smoothstep(1.0, 0.55, uv.y);

	float alpha = shape_x * fade_bot * fade_top * wave * intensity;

	ALBEDO = shimmer_color.rgb;
	ALPHA  = clamp(alpha, 0.0, 1.0);
}
