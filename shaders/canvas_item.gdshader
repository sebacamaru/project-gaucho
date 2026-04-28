shader_type canvas_item;

uniform vec2 player_screen_uv = vec2(0.5, 0.5);

uniform float clear_radius = 0.18;
uniform float clear_softness = 0.12;

uniform float fog_alpha = 0.16;
uniform float noise_scale = 0.03;
uniform float noise_speed = 0.015;

// Posición de la cámara en coordenadas de mundo (o equivalente 2D del plano)
uniform vec2 camera_world_offset = vec2(0.0, 0.0);

// Tamaño visible del mundo en pantalla.
// Ejemplo: si tu cámara ve aprox 24 unidades de ancho y 13.5 de alto,
// este valor debe representar eso en el mismo espacio que camera_world_offset.
uniform vec2 visible_world_size = vec2(20.0, 12.0);

uniform vec4 fog_color : source_color = vec4(0.72, 0.72, 0.78, 1.0);


float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(a, b, u.x)
		+ (c - a) * u.y * (1.0 - u.x)
		+ (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;

	for (int i = 0; i < 4; i++) {
		value += noise(p) * amp;
		p *= 2.0;
		amp *= 0.5;
	}

	return value;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Convertimos cada píxel de pantalla a una posición continua dentro del mundo.
	// Esto deja el patrón "pegado" al escenario en vez de pegado a la pantalla.
	vec2 world_pos = camera_world_offset + uv * visible_world_size;

	// Escala del ruido
	vec2 noise_uv = world_pos * noise_scale;

	// Movimiento muy sutil de la niebla
	noise_uv += vec2(TIME * noise_speed, TIME * noise_speed * 0.6);

	float n = fbm(noise_uv);
	float fog_variation = smoothstep(0.35, 0.8, n);

	float dist_to_player = distance(uv, player_screen_uv);
	float radial_mask = smoothstep(clear_radius, clear_radius + clear_softness, dist_to_player);

	float final_alpha = fog_alpha * fog_variation * radial_mask;

	COLOR = vec4(fog_color.rgb, final_alpha);
}