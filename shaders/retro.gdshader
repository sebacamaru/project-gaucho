shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// Suavizado
uniform float soft_amount : hint_range(0.0, 2.0) = 0.6;

// Ajustes generales
uniform float saturation : hint_range(0.0, 2.0) = 0.9;
uniform float contrast : hint_range(0.5, 2.0) = 1.08;
uniform float brightness : hint_range(0.5, 1.5) = 1.0;
uniform float warmth : hint_range(-1.0, 1.0) = 0.08;

// Control RGB con sliders
uniform float red_mul   : hint_range(0.0, 2.0) = 1.0;
uniform float green_mul : hint_range(0.0, 2.0) = 1.0;
uniform float blue_mul  : hint_range(0.0, 2.0) = 1.0;

uniform float red_add   : hint_range(-0.5, 0.5) = 0.0;
uniform float green_add : hint_range(-0.5, 0.5) = 0.0;
uniform float blue_add  : hint_range(-0.5, 0.5) = 0.0;

// Retro
uniform float posterize_levels : hint_range(0.0, 32.0) = 0.0;
uniform float dither_amount : hint_range(0.0, 0.2) = 0.02;
uniform vec2 dither_resolution = vec2(320.0, 180.0);

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

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel_size = SCREEN_PIXEL_SIZE;

	vec3 center = texture(screen_texture, uv).rgb;
	vec3 up     = texture(screen_texture, uv + vec2(0.0, -pixel_size.y)).rgb;
	vec3 down   = texture(screen_texture, uv + vec2(0.0,  pixel_size.y)).rgb;
	vec3 left   = texture(screen_texture, uv + vec2(-pixel_size.x, 0.0)).rgb;
	vec3 right  = texture(screen_texture, uv + vec2( pixel_size.x, 0.0)).rgb;

	vec3 blurred = (center * 4.0 + up + down + left + right) / 8.0;
	vec3 color = mix(center, blurred, soft_amount * 0.35);

	color = apply_saturation(color, saturation);
	color = apply_contrast(color, contrast);
	color *= brightness;
	color = apply_warmth(color, warmth);

	if (dither_amount > 0.0) {
		vec2 dither_uv = floor(uv * dither_resolution);
		float noise = get_bayer_4x4(dither_uv) - 0.5;
		color += noise * dither_amount;
	}

	if (posterize_levels > 1.0) {
		color = apply_posterize(color, posterize_levels);
	}

	color *= vec3(red_mul, green_mul, blue_mul);
	color += vec3(red_add, green_add, blue_add);

	color = clamp(color, 0.0, 1.0);
	COLOR = vec4(color, 1.0);
}