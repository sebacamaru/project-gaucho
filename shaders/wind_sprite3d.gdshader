shader_type spatial;

/*
	Shader reutilizable de viento para Sprite3D.

	Deforma los vértices del sprite:
	- base casi fija
	- parte superior con más movimiento
	- variación automática por posición en el mundo
*/

render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_lambert, specular_disabled;


// Textura del sprite.
// Tenés que asignarle la misma textura que usa el Sprite3D.
uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;

// Tinte general.
uniform vec4 tint : source_color = vec4(1.0);


// =========================================================
// CONFIGURACIÓN DEL VIENTO
// =========================================================

uniform float wind_strength : hint_range(0.0, 0.20, 0.001) = 0.025;
uniform float wind_speed : hint_range(0.0, 8.0, 0.01) = 1.6;
uniform float wind_frequency : hint_range(0.0, 20.0, 0.01) = 5.0;

uniform float root_lock : hint_range(0.0, 0.9, 0.01) = 0.20;
uniform float bend_power : hint_range(0.2, 5.0, 0.01) = 1.8;

uniform float secondary_wave_amount : hint_range(0.0, 1.0, 0.01) = 0.25;

uniform float alpha_discard : hint_range(0.0, 1.0, 0.001) = 0.02;


// =========================================================
// HELPERS
// =========================================================

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


// =========================================================
// VERTEX
// =========================================================

void vertex() {
	// En Sprite3D:
	// UV.y = 0 arriba
	// UV.y = 1 abajo
	//
	// Entonces:
	// height = 0 en la base
	// height = 1 en la punta
	float height = 1.0 - UV.y;

	// Máscara para fijar la base.
	float bend_mask = smoothstep(root_lock, 1.0, height);
	bend_mask = pow(bend_mask, bend_power);

	// Variación por posición en el mundo.
	// Esto evita que todos los arbustos se muevan exactamente igual.
	vec2 world_xz = MODEL_MATRIX[3].xz;
	float seed = hash21(floor(world_xz)) * 6.28318;

	// Onda principal.
	float wave_a = sin(
		TIME * wind_speed
		+ seed
		+ height * wind_frequency
	);

	// Onda secundaria.
	float wave_b = sin(
		TIME * wind_speed * 1.73
		+ seed * 1.31
		+ height * wind_frequency * 0.55
	);

	float final_wave = mix(wave_a, wave_b, secondary_wave_amount);

	// Movimiento horizontal local.ast sstt
	VERTEX.x += final_wave * wind_strength * bend_mask;
}


// =========================================================
// FRAGMENT
// =========================================================

void fragment() {
	vec4 tex = texture(sprite_texture, UV) * tint;

	if (tex.a <= alpha_discard) {
		discard;
	}

	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}