shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2D albedo_texture : source_color;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);

	ALBEDO = tex.rgb;
	EMISSION = tex.rgb * 0.4;
	ALPHA = tex.a;
}