shader_type canvas_item;

/// =========================================================
/// POST PROCESO RETRO + RADIAL BLUR
/// =========================================================
/// Uso recomendado:
/// 1. CanvasLayer arriba de todo, por ejemplo layer = 128.
/// 2. Dentro, un ColorRect fullscreen.
/// 3. ShaderMaterial con este shader.
/// 4. Controlar radial_strength desde código para activar el blur radial.
/// =========================================================


// =========================================================
// TEXTURA DE PANTALLA
// =========================================================

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;


// =========================================================
// RADIAL BLUR
// =========================================================

/// Fuerza del blur radial.
/// 0.0 = apagado.
/// 0.02 / 0.04 = valores razonables.
/// 0.08+ = bastante fuerte.
uniform float radial_strength : hint_range(0.0, 0.1, 0.001) = 0.0;

/// Centro del efecto en UV.
/// vec2(0.5, 0.5) = centro de pantalla.
uniform vec2 radial_center = vec2(0.5, 0.5);

/// Radio nítido alrededor del centro.
uniform float radial_focus_radius : hint_range(0.0, 0.5, 0.005) = 0.15;

/// Suavidad entre zona nítida y zona con blur.
uniform float radial_focus_softness : hint_range(0.0, 0.3, 0.005) = 0.1;

/// Oscurecimiento de bordes.
uniform float radial_darkness : hint_range(0.0, 1.0, 0.01) = 0.0;

/// Radio nítido para el oscurecimiento.
uniform float radial_darkness_radius : hint_range(0.0, 0.5, 0.005) = 0.15;

/// Suavidad del borde oscuro.
uniform float radial_darkness_softness : hint_range(0.0, 0.3, 0.005) = 0.1;

/// Cantidad de muestras del radial blur.
/// Más alto = mejor calidad, más caro.
/// Para web/mobile probar 6 a 10.
/// Para desktop 12 está bien.
uniform int radial_samples : hint_range(4, 32, 1) = 12;


// =========================================================
// RETRO / SUAVIZADO
// =========================================================

/// Suavizado general.
/// 0.0 = imagen cruda.
/// 0.6 = valor suave.
/// 1.0+ = más lavado.
uniform float soft_amount : hint_range(0.0, 2.0) = 0.6;

/// Saturación general.
uniform float saturation : hint_range(0.0, 2.0) = 0.9;

/// Contraste general.
uniform float contrast : hint_range(0.5, 2.0) = 1.08;

/// Brillo general.
uniform float brightness : hint_range(0.5, 1.5) = 1.0;

/// Temperatura.
/// Positivo = más cálido.
/// Negativo = más frío.
uniform float warmth : hint_range(-1.0, 1.0) = 0.08;


// =========================================================
// CONTROL RGB
// =========================================================

uniform float red_mul   : hint_range(0.0, 2.0) = 1.0;
uniform float green_mul : hint_range(0.0, 2.0) = 1.0;
uniform float blue_mul  : hint_range(0.0, 2.0) = 1.0;

uniform float red_add   : hint_range(-0.5, 0.5) = 0.0;
uniform float green_add : hint_range(-0.5, 0.5) = 0.0;
uniform float blue_add  : hint_range(-0.5, 0.5) = 0.0;


// =========================================================
// DITHER / POSTERIZE
// =========================================================

/// 0.0 = sin posterize.
/// 4.0 / 8.0 / 16.0 = valores útiles.
uniform float posterize_levels : hint_range(0.0, 32.0) = 0.0;

/// Intensidad del dithering.
uniform float dither_amount : hint_range(0.0, 0.2) = 0.02;

/// Resolución virtual del dithering.
/// Para look retro: 320x180, 400x225, etc.
uniform vec2 dither_resolution = vec2(320.0, 180.0);


// =========================================================
// FUNCIONES AUXILIARES
// =========================================================

float get_bayer_4x4(vec2 pos) {
	int x = int(mod(pos.x, 4.0));
	int y = int(mod(pos.y, 4.0));
	int index = x + y * 4;

	float[16] matrix = float[](
		0.0,  8.0,  2.0, 10.0,
		12.0, 4.0, 14.0,  6.0,
		3.0, 11.0,  1.0,  9.0,
		15.0, 7.0, 13.0,  5.0
	);

	return matrix[index] / 16.0;
}


vec3 apply_contrast(vec3 color, float amount) {
	return (color - 0.5) * amount + 0.5;
}


vec3 apply_saturation(vec3 color, float amount) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	return mix(vec3(luma), color, amount);
}


vec3 apply_warmth(vec3 color, float amount) {
	color.r += amount * 0.06;
	color.b -= amount * 0.06;
	return color;
}


vec3 apply_posterize(vec3 color, float levels) {
	if (levels <= 1.0) {
		return color;
	}

	return floor(color * levels) / levels;
}


/// Lee la pantalla aplicando radial blur y darkness.
/// Esta función es la base visual sobre la que después se aplica el look retro.
vec3 sample_radial_screen(vec2 uv) {
	uv = clamp(uv, vec2(0.0), vec2(1.0));

	vec2 dir = uv - radial_center;
	float dist = length(dir);

	vec4 color = vec4(0.0);
	float total_weight = 0.0;

	// Si el blur está apagado, hacemos una sola lectura.
	// El darkness igual puede aplicarse más abajo.
	if (radial_strength <= 0.0001) {
		color = texture(screen_texture, uv);
		total_weight = 1.0;
	} else {
		float edge = radial_focus_radius + max(radial_focus_softness, 0.001);
		float blur = smoothstep(radial_focus_radius, edge, dist) * radial_strength;

		int count = clamp(radial_samples, 4, 32);

		for (int i = 0; i < 32; i++) {
			if (i >= count) {
				break;
			}

			float denom = max(float(count - 1), 1.0);

			// t va de -0.5 a +0.5.
			float t = (float(i) / denom) - 0.5;

			// Peso triangular para evitar demasiado ghosting.
			float weight = 1.0 - abs(t) * 1.5;
			weight = max(weight, 0.05);

			vec2 sample_uv = clamp(uv + dir * t * blur, vec2(0.0), vec2(1.0));

			color += texture(screen_texture, sample_uv) * weight;
			total_weight += weight;
		}
	}

	color /= max(total_weight, 0.0001);

	// Darkness radial independiente del blur.
	float dark_edge = radial_darkness_radius + max(radial_darkness_softness, 0.001);
	float dark = smoothstep(radial_darkness_radius, dark_edge, dist) * radial_darkness;

	color.rgb *= 1.0 - dark;

	return color.rgb;
}


// =========================================================
// FRAGMENT PRINCIPAL
// =========================================================

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel_size = SCREEN_PIXEL_SIZE;

	// Primero tomamos la imagen ya afectada por radial blur.
	// Esto evita tener dos ColorRect peleándose por screen_texture.
	vec3 center_color = sample_radial_screen(uv);

	vec3 up    = sample_radial_screen(uv + vec2(0.0, -pixel_size.y));
	vec3 down  = sample_radial_screen(uv + vec2(0.0,  pixel_size.y));
	vec3 left  = sample_radial_screen(uv + vec2(-pixel_size.x, 0.0));
	vec3 right = sample_radial_screen(uv + vec2( pixel_size.x, 0.0));

	// Suavizado retro.
	vec3 blurred = (center_color * 4.0 + up + down + left + right) / 8.0;
	vec3 color = mix(center_color, blurred, soft_amount * 0.35);

	// Color grading retro.
	color = apply_saturation(color, saturation);
	color = apply_contrast(color, contrast);
	color *= brightness;
	color = apply_warmth(color, warmth);

	// Dithering Bayer.
	if (dither_amount > 0.0) {
		vec2 dither_uv = floor(uv * dither_resolution);
		float noise = get_bayer_4x4(dither_uv) - 0.5;
		color += noise * dither_amount;
	}

	// Posterize.
	if (posterize_levels > 1.0) {
		color = apply_posterize(color, posterize_levels);
	}

	// Ajuste RGB final.
	color *= vec3(red_mul, green_mul, blue_mul);
	color += vec3(red_add, green_add, blue_add);

	color = clamp(color, 0.0, 1.0);

	COLOR = vec4(color, 1.0);
}