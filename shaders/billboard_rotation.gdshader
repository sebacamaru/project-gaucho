shader_type spatial;

render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_lambert;

uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform float rotation_angle = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

uniform float ambient_strength = 0.25;
uniform float emission_strength = 0.0;

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);

	float s = sin(rotation_angle);
	float c = cos(rotation_angle);

	vec2 rotated_uv = vec2(
		c * centered_uv.x - s * centered_uv.y,
		s * centered_uv.x + c * centered_uv.y
	) + vec2(0.5);

	if (
		rotated_uv.x < 0.0 || rotated_uv.x > 1.0 ||
		rotated_uv.y < 0.0 || rotated_uv.y > 1.0
	) {
		discard;
	}

	vec4 col = texture(sprite_texture, rotated_uv) * tint;

	ALBEDO = col.rgb;
	ALPHA = col.a;

	// Un poquito de base para que nunca quede negro absoluto.
	EMISSION = col.rgb * emission_strength;

	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// Para sprites/billboards suele convenir una normal "suave",
	// porque si la normal real queda mal orientada, la luz no pega bien.
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);

	// Lambert simple.
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * ndotl;

	// Luz ambiente falsa opcional.
	DIFFUSE_LIGHT += ALBEDO * ambient_strength * ATTENUATION;
}