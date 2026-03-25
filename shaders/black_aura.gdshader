shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

/// Color del aura (negro / morado oscuro)
uniform vec4 aura_color : source_color = vec4(0.03, 0.0, 0.06, 1.0);

/// Velocidad de la animación de fuego
uniform float flame_speed : hint_range(0.5, 10.0, 0.1) = 15.0;

/// Intensidad de la distorsión (qué tanto ondean las llamas)
uniform float flame_distortion : hint_range(0.0, 0.30, 0.005) = 0.18;

/// Cuánto se erosionan los bordes superiores (punta de llama)
uniform float flame_tip_sharpness : hint_range(0.0, 6.0, 0.05) = 5.0;

/// Controla la forma del borde interno (mayor = más pegado al sprite)
uniform float edge_power : hint_range(0.01, 3.0, 0.01) = 0.1;

/// Intensidad interna del efecto (afecta qué tan "lleno" se ve el aura)
uniform float aura_opacity : hint_range(0.0, 3.0, 0.01) = 1.92;

/// Transparencia global — baja esto para hacer el aura más translúcida
uniform float global_alpha : hint_range(0.0, 1.0, 0.01) = 0.1;

/// Gradiente de fade en los bordes de la textura — oculta cortes de animación
/// (0 = sin fade, 0.3 = fade amplio)
uniform float edge_fade : hint_range(0.0, 0.4, 0.01) = 0.5;

/// Textura del sprite (sólo se usa el canal alpha)
uniform sampler2D texture_albedo : hint_default_black;

void fragment() {
	float t = TIME * flame_speed;
	vec2 uv = UV;

	// ── Distorsión tipo llama ────────────────────────────────────────────────
	// Capa 1: ondas verticales — movimiento lateral de las llamas
	float dx = sin(UV.y * 8.0 + t * 1.1) * flame_distortion
	         + cos(UV.y * 5.3 - t * 0.75) * flame_distortion * 0.55;

	// Capa 2: turbulencia menor para romper la periodicidad
	float dy = sin(UV.x * 7.2 + t * 0.85) * flame_distortion * 0.45
	         + cos(UV.x * 4.8 - t * 1.3) * flame_distortion * 0.3;

	uv.x += dx;
	uv.y += dy;

	float alpha = texture(texture_albedo, uv).a;

	// ── Erosión superior (llamas que suben) ──────────────────────────────────
	// UV.y = 0 es la parte superior del sprite → más erosión arriba
	float up = pow(1.0 - UV.y, 1.6);
	float flicker = sin(UV.x * 16.0 + t * 3.1) * 0.5 + 0.5;
	float erosion = up * flicker * flame_tip_sharpness * 0.55;

	// ── Burbujeo ─────────────────────────────────────────────────────────────
	float bubble = sin(UV.x * 13.0 + t * 2.2) * cos(UV.y * 11.0 - t * 1.9) * 0.17;

	// ── Alpha interno ────────────────────────────────────────────────────────
	float raw = alpha - erosion + bubble;
	float final_alpha = pow(max(raw, 0.0), edge_power) * aura_opacity;

	// ── Gradiente de bordes (UV sin distorsionar) ────────────────────────────
	// Usa las coordenadas UV originales para que el fade sea siempre estable,
	// independientemente de la distorsión de la animación.
	float fade_x = smoothstep(0.0, edge_fade, UV.x) * smoothstep(1.0, 1.0 - edge_fade, UV.x);
	float fade_y = smoothstep(0.0, edge_fade, UV.y) * smoothstep(1.0, 1.0 - edge_fade, UV.y);
	final_alpha *= fade_x * fade_y;

	// ── Transparencia global + emisión pulsante ──────────────────────────────
	float pulse = sin(t * 0.45) * 0.09 + 0.91;

	ALBEDO = aura_color.rgb;
	EMISSION = aura_color.rgb * pulse * 0.7;
	ALPHA = clamp(final_alpha * global_alpha, 0.0, 1.0);
}
