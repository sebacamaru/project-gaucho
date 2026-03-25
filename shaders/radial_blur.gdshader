shader_type canvas_item;

/// === BLUR RADIAL CONFIGURABLE ===
/// Uso como post-proceso:
///   1. Agregar CanvasLayer (layer = 128 o similar) en la escena raíz.
///   2. Dentro del CanvasLayer, agregar un ColorRect (tamaño = pantalla completa).
///   3. En el ColorRect: Material > New ShaderMaterial > Shader = este archivo.
///   4. Controlar `strength` desde código para activar/desactivar el efecto.
///
/// Uso sobre un sprite:
///   En el Sprite2D/AnimatedSprite2D: Material > New ShaderMaterial > Shader = este archivo.
///   En ese caso, SCREEN_UV se reemplaza por UV y screen_texture por TEXTURE.

// --- Parámetros del efecto ---

/// Fuerza del blur (0.0 = sin efecto, 0.05 = fuerte)
uniform float strength : hint_range(0.0, 0.1, 0.001) = 0.0;

/// Centro del efecto en coordenadas UV (vec2(0.5, 0.5) = centro de pantalla)
uniform vec2 center = vec2(0.5, 0.5);

/// Radio de zona nítida alrededor del centro (en UV, 0.0 = blur desde el centro)
uniform float focus_radius : hint_range(0.0, 0.5, 0.005) = 0.15;

/// Suavidad del borde entre zona nítida y blur (0.0 = corte abrupto)
uniform float focus_softness : hint_range(0.0, 0.3, 0.005) = 0.1;

/// Oscurecimiento de bordes (0.0 = sin efecto, 1.0 = bordes negros)
uniform float darkness : hint_range(0.0, 1.0, 0.01) = 0.0;

/// Radio de zona nítida para el oscurecimiento (independiente del blur)
uniform float darkness_radius : hint_range(0.0, 0.5, 0.005) = 0.15;

/// Suavidad del borde del oscurecimiento
uniform float darkness_softness : hint_range(0.0, 0.3, 0.005) = 0.1;

/// Número de muestras: más muestras = más calidad, más costo de GPU
uniform int samples : hint_range(4, 32, 1) = 12;

/// Textura de pantalla (para uso como post-proceso sobre ColorRect)
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - center;
	float dist = length(dir);

	// Transición suave entre zona nítida y blur
	float edge = focus_radius + max(focus_softness, 0.001);
	float blur = smoothstep(focus_radius, edge, dist) * strength;

	vec4 color = vec4(0.0);
	float total_weight = 0.0;

	for (int i = 0; i < samples; i++) {
		// t va de -0.5 a +0.5 centrado en 0
		float t = (float(i) / float(samples - 1)) - 0.5;

		// Peso triangular: las muestras del centro tienen más peso (menos ghosting)
		float weight = 1.0 - abs(t) * 1.5;
		weight = max(weight, 0.05);

		// Sin blur (blur < 0.0001): dir * t * blur ≈ 0, todas las muestras caen en uv
		vec2 sample_uv = clamp(uv + dir * t * blur, vec2(0.0), vec2(1.0));
		color += texture(screen_texture, sample_uv) * weight;
		total_weight += weight;
	}

	COLOR = color / total_weight;
	float dark_edge = darkness_radius + max(darkness_softness, 0.001);
	float dark = smoothstep(darkness_radius, dark_edge, dist) * darkness;
	COLOR.rgb *= (1.0 - dark);
}
