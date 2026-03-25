shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

/// Textura del sprite
uniform sampler2D texture_albedo : source_color, hint_default_white;

/// Progreso del dissolve: 0 = visible, 1 = disuelto
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;

/// Ancho del borde luminoso
uniform float edge_width : hint_range(0.0, 0.25) = 0.09;

/// Color del borde (naranja fuego por defecto)
uniform vec4 edge_color : source_color = vec4(0.933, 0.0, 0.0, 1.0);

/// Intensidad del glow en el borde
uniform float edge_glow : hint_range(0.0, 8.0) = 3.5;

// ── Ruido procedural (sin textura externa) ────────────────────────────────────

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i),                  hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

// 3 octavas de FBM para un patrón de quemado orgánico
float fbm(vec2 p) {
	return vnoise(p)                         * 0.50
	     + vnoise(p * 2.1 + vec2(3.7, 1.9)) * 0.30
	     + vnoise(p * 4.5 + vec2(7.2, 5.3)) * 0.20;
}

// ─────────────────────────────────────────────────────────────────────────────

void fragment() {
	vec4 tex = texture(texture_albedo, UV);

	float n = fbm(UV * 5.0);

	// Píxeles donde n < dissolve_amount se eliminan
	float dissolved = step(n, dissolve_amount);

	// Borde luminoso: píxeles visibles justo en el frente de avance
	float in_edge = (1.0 - dissolved)
	              * (1.0 - smoothstep(0.0, edge_width, n - dissolve_amount));

	ALBEDO   = mix(tex.rgb, edge_color.rgb, in_edge);
	EMISSION = edge_color.rgb * edge_glow * in_edge;
	ALPHA    = tex.a * (1.0 - dissolved);
}
