shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D albedo_texture : source_color;
uniform float min_visibility : hint_range(0.0, 1.0) = 0.2;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.1;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);

	if (tex.a < alpha_cutoff) {
		discard;
	}

	ALBEDO = tex.rgb;
	EMISSION = tex.rgb * min_visibility * vec3(1.1, 0.9, 0.9);
	ALPHA = tex.a;
}