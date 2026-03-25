shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D texture_albedo : source_color, hint_default_white;

/// Intensidad del movimiento (0.0 = sin movimiento)
uniform float strength : hint_range(0.0, 0.3, 0.01) = 0.05;

/// Velocidad de oscilación
uniform float speed : hint_range(0.0, 10.0, 0.1) = 2.0;

/// Punto de inicio del movimiento desde la base (0 = base, 1 = punta)
uniform float start_y : hint_range(0.0, 1.0, 0.01) = 0.3;

/// Suavidad de la curva de movimiento
uniform float curve_scale : hint_range(0.5, 3.0, 0.1) = 1.5;

void vertex() {
    // Usa posición X en el mundo para que cada arbusto se mueva desfasado
    float world_x = MODEL_MATRIX[3][0];

    // from_top: 1.0 en la punta del sprite, 0.0 en la base
    float from_top = 1.0 - UV.y;
    float factor = smoothstep(start_y, 1.0, from_top);
    factor = pow(factor, curve_scale);

    float sway = sin(TIME * speed + world_x * 0.5) * strength * factor;
    VERTEX.x += sway;
}

void fragment() {
    vec4 col = texture(texture_albedo, UV);
    ALBEDO = col.rgb;
    ALPHA = col.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
