shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D texture_albedo : source_color, hint_default_white;

/// Brillo (1.0 = normal, >1.0 = más brillante)
uniform float brightness : hint_range(0.5, 3.0, 0.01) = 1.0;

/// Contraste (1.0 = normal, >1.0 = más contraste)
uniform float contrast : hint_range(0.5, 2.5, 0.01) = 1.0;

/// Saturación (1.0 = normal, 0.0 = escala de grises, >1.0 = más vivo)
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.0;

void fragment() {
    vec4 color = texture(texture_albedo, UV);

    // Saturación: interpola entre luminancia y color original
    float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(vec3(lum), color.rgb, saturation);

    // Contraste: escala alrededor del punto medio (0.5)
    color.rgb = (color.rgb - 0.5) * contrast + 0.5;

    // Brillo: multiplicador simple
    color.rgb *= brightness;

    color.rgb = clamp(color.rgb, 0.0, 1.0);

    ALBEDO = color.rgb;
    ALPHA = color.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}
