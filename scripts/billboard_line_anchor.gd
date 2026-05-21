extends Node3D
class_name BillboardLineAnchoredSpriteVisual

# =========================================================
# BillboardLineAnchoredSpriteVisual
# ---------------------------------------------------------
# Visual billboard robusto para armas 2.5D.
#
# Este nodo:
# - se posiciona en un anchor global, por ejemplo Weapon/Grip;
# - dibuja una línea debug desde ese anchor hasta el mouse;
# - rota el Sprite2D interno del SubViewport usando esa misma línea;
# - mantiene el Sprite3D con Y-Billboard + Shaded.
#
# La línea es la fuente de verdad.
# El facón visual siempre apunta en la misma dirección que la línea.
#
# Importante:
# - Este nodo NO debería heredar rotaciones raras del arma real.
# - Por eso usamos top_level = true.
# - La posición global se actualiza desde WeaponComponent.
# =========================================================


# =========================================================
# REFERENCIAS
# =========================================================

# Cámara opcional.
# Si queda vacía, usa la cámara activa del viewport.
@export var camera_3d: Camera3D

# Sprite3D visible en el mundo.
# Este Sprite3D mantiene Y-Billboard + Shaded.
@export var sprite_3d: Sprite3D

# SubViewport que genera la textura dinámica.
@export var sub_viewport: SubViewport

# Sprite2D que rota dentro del SubViewport.
@export var sprite_2d: Sprite2D

# Textura original del facón.
@export var source_texture: Texture2D

# Línea debug en pantalla.
# Idealmente un Line2D dentro de un CanvasLayer.
@export var debug_line: Line2D


# =========================================================
# CONFIGURACIÓN VISUAL
# =========================================================

# Mostrar/ocultar línea debug.
@export var debug_line_enabled: bool = true

# Corrige la orientación según cómo esté dibujado el PNG.
#
# Si el facón en el PNG apunta a la derecha, suele ser 0.
# Si apunta arriba/abajo/izquierda, usar 90, -90 o 180.
@export var angle_offset_degrees: float = 0.0

# Tamaño del Sprite3D en el mundo.
@export var sprite_3d_pixel_size: float = 0.01

# Tamaño del PNG dentro del SubViewport.
@export var sprite_2d_scale: float = 1.0

# Punto de pivote dentro del PNG, en píxeles.
#
# Para el facón, debería ser el mango o el punto exacto donde querés
# que empiece la línea.
#
# Si queda en Vector2.ZERO, usa el centro de la textura.
#
# Ejemplo:
# - textura 128x64, mango a la izquierda:
#   texture_pivot_px = Vector2(10, 32)
@export var texture_pivot_px: Vector2 = Vector2.ZERO

# Ajuste SOLO durante ataque.
# Mueve el facón hacia adelante siguiendo la dirección Grip → Tip.
# Positivo = más lejos de la mano.
# Negativo = más cerca de la mano.
@export var attack_forward_offset_world: float = 0.0

# Ajuste vertical SOLO durante ataque.
# Positivo = más arriba.
# Negativo = más abajo.
@export var attack_height_offset_world: float = 0.0

# =========================================================
# AUTO RESIZE DEL SUBVIEWPORT
# =========================================================

# Agranda automáticamente el SubViewport para que el PNG no se corte
# aunque el pivote esté cerca de un borde.
@export var auto_resize_viewport_to_fit_pivot: bool = true

# Padding extra alrededor del sprite dentro del SubViewport.
# Subir este valor si todavía se corta al rotar.
@export var viewport_padding_px: int = 32

# Tamaño mínimo del SubViewport.
# Evita que texturas chicas generen viewports demasiado pequeños.
@export var viewport_min_size: Vector2i = Vector2i(128, 128)


# =========================================================
# LÍNEA DEBUG / AIM
# =========================================================

# Estilo visual de la línea debug.
@export var debug_line_width: float = 2.0
@export var debug_line_color: Color = Color(1.0, 0.1, 0.1, 0.85)


# =========================================================
# ESTADO INTERNO
# =========================================================

# Última dirección válida en pantalla.
# Se usa cuando el mouse está demasiado cerca del Grip.
var last_screen_dir: Vector2 = Vector2.RIGHT
var has_last_screen_dir: bool = false


# =========================================================
# SWING VISUAL EXTRA DE ATAQUE
# =========================================================

# Activa un pequeño swing visual encima de la dirección real Grip → Tip.
@export var attack_extra_swing_enabled: bool = true

# Amplitud del swing visual extra.
# Valores buenos: 8 a 18 grados.
@export var attack_extra_swing_angle_deg: float = 12.0

# Si está en true, el swing extra vuelve a cero al terminar.
@export var attack_extra_swing_return_to_zero: bool = true

var attack_extra_swing_active: bool = false
var attack_extra_swing_start_msec: int = 0
var attack_extra_swing_duration: float = 0.25
var attack_extra_swing_sign: float = 1.0


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	# El visual queda independiente de las rotaciones del arma real.
	# Lo posicionamos manualmente usando global_position.
	top_level = true

	if sprite_3d == null:
		push_warning("Falta asignar sprite_3d.")
		return

	if sub_viewport == null:
		push_warning("Falta asignar sub_viewport.")
		return

	if sprite_2d == null:
		push_warning("Falta asignar sprite_2d.")
		return

	if source_texture == null:
		push_warning("Falta asignar source_texture.")
		return

	# -----------------------------------------------------
	# Datos base de textura / pivote
	# -----------------------------------------------------
	var texture_size: Vector2 = source_texture.get_size()
	var pivot_px: Vector2 = _resolve_texture_pivot(texture_size)

	# -----------------------------------------------------
	# SubViewport
	# -----------------------------------------------------
	sub_viewport.transparent_bg = true
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Auto-resize antes de centrar el Sprite2D.
	if auto_resize_viewport_to_fit_pivot:
		_resize_sub_viewport_to_fit_pivot(texture_size, pivot_px)

	# -----------------------------------------------------
	# Sprite3D visible
	# -----------------------------------------------------
	# El Sprite3D muestra la textura generada por el SubViewport.
	sprite_3d.texture = sub_viewport.get_texture()

	# Conserva comportamiento de sprite 3D iluminado.
	sprite_3d.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite_3d.shaded = true
	sprite_3d.transparent = true
	sprite_3d.double_sided = true
	sprite_3d.pixel_size = sprite_3d_pixel_size

	# El Sprite3D no debería estar desplazado.
	# El anclaje lo maneja este Node3D con global_position.
	sprite_3d.position = Vector3.ZERO

	# -----------------------------------------------------
	# Sprite2D interno
	# -----------------------------------------------------
	sprite_2d.texture = source_texture
	sprite_2d.centered = true

	# El centro del SubViewport es el punto de rotación.
	sprite_2d.position = Vector2(sub_viewport.size) * 0.5

	# Escala visual dentro del viewport.
	sprite_2d.scale = Vector2.ONE * sprite_2d_scale

	# Movemos el dibujo para que el pivote elegido del PNG
	# quede justo en el centro del SubViewport.
	#
	# Para el facón, ese pivote debería ser el mango.
	sprite_2d.offset = (texture_size * 0.5) - pivot_px

	# -----------------------------------------------------
	# Línea debug
	# -----------------------------------------------------
	if debug_line != null:
		debug_line.width = debug_line_width
		debug_line.default_color = debug_line_color
		debug_line.visible = debug_line_enabled
		debug_line.points = PackedVector2Array()

	_apply_screen_angle(0.0)


# =========================================================
# API PÚBLICA
# =========================================================

func look_from_anchor_to_mouse(anchor_global: Vector3) -> void:
	var cam := _get_camera()

	if cam == null:
		_hide_debug_line()
		return

	if cam.is_position_behind(anchor_global):
		_hide_debug_line()
		return

	# El visual del facón nace desde el Grip.
	global_position = anchor_global

	var anchor_screen: Vector2 = cam.unproject_position(anchor_global)
	var mouse_screen: Vector2 = get_viewport().get_mouse_position()

	_apply_screen_line(anchor_screen, mouse_screen)


func clear_debug_line() -> void:
	_hide_debug_line()


# =========================================================
# PIVOTE / VIEWPORT
# =========================================================

func _resolve_texture_pivot(texture_size: Vector2) -> Vector2:
	# Si no configuraste texture_pivot_px, usamos el centro del PNG.
	if texture_pivot_px == Vector2.ZERO:
		return texture_size * 0.5

	return texture_pivot_px


func _resize_sub_viewport_to_fit_pivot(texture_size: Vector2, pivot_px: Vector2) -> void:
	# -----------------------------------------------------
	# Auto-resize robusto
	# -----------------------------------------------------
	# Queremos que el PNG no se corte al rotar alrededor del pivote.
	#
	# Para eso calculamos la distancia máxima desde el pivote
	# hasta cualquiera de las 4 esquinas de la textura.
	#
	# Esa distancia es el radio mínimo del círculo que contiene
	# toda la textura al rotar.
	#
	# Luego hacemos un SubViewport cuadrado de:
	# radio * 2 + padding
	# -----------------------------------------------------

	var scaled_texture_size: Vector2 = texture_size * sprite_2d_scale
	var scaled_pivot_px: Vector2 = pivot_px * sprite_2d_scale

	var corners: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(scaled_texture_size.x, 0.0),
		Vector2(0.0, scaled_texture_size.y),
		Vector2(scaled_texture_size.x, scaled_texture_size.y)
	]

	var max_radius: float = 0.0

	for corner in corners:
		var dist: float = corner.distance_to(scaled_pivot_px)
		max_radius = max(max_radius, dist)

	var final_size: int = int(ceil(max_radius * 2.0)) + viewport_padding_px * 2

	final_size = max(final_size, viewport_min_size.x)
	final_size = max(final_size, viewport_min_size.y)

	sub_viewport.size = Vector2i(final_size, final_size)


# =========================================================
# LÍNEA / ROTACIÓN EN PANTALLA
# =========================================================

func _apply_screen_line(anchor_screen: Vector2, target_screen: Vector2) -> void:
	var screen_dir: Vector2 = target_screen - anchor_screen

	last_screen_dir = screen_dir.normalized()

	var final_target_screen: Vector2 = anchor_screen + screen_dir

	# Dibujar línea debug.
	if debug_line != null and debug_line_enabled:
		debug_line.visible = true
		debug_line.points = PackedVector2Array([
			anchor_screen,
			final_target_screen
		])

	var angle_rad: float = atan2(screen_dir.y, screen_dir.x)

	# Durante ataque, sumamos un pequeño swing visual relativo
	# a la dirección real de la línea.
	angle_rad += _get_attack_extra_swing_angle()

	_apply_screen_angle(angle_rad)


func _apply_screen_angle(angle_rad: float) -> void:
	if sprite_2d == null:
		return

	sprite_2d.rotation = angle_rad + deg_to_rad(angle_offset_degrees)


func look_from_anchor_to_world_target(anchor_global: Vector3, target_global: Vector3) -> void:
	var cam := _get_camera()

	if cam == null:
		_hide_debug_line()
		return

	var attack_dir: Vector3 = target_global - anchor_global
	attack_dir.y = 0.0

	if attack_dir.length_squared() <= 0.0001:
		_hide_debug_line()
		return

	attack_dir = attack_dir.normalized()

	# -----------------------------------------------------
	# Offset robusto relativo a la dirección del ataque
	# -----------------------------------------------------
	# En vez de mover en X/Z global, movemos "hacia adelante"
	# según la línea Grip → Tip.
	#
	# Esto funciona igual mirando a derecha, izquierda, arriba o abajo.
	# -----------------------------------------------------
	var directional_offset: Vector3 = attack_dir * attack_forward_offset_world
	var height_offset: Vector3 = Vector3.UP * attack_height_offset_world

	var final_anchor_global: Vector3 = anchor_global + directional_offset + height_offset
	var final_target_global: Vector3 = target_global + directional_offset + height_offset

	if cam.is_position_behind(final_anchor_global):
		_hide_debug_line()
		return

	if cam.is_position_behind(final_target_global):
		_hide_debug_line()
		return

	global_position = final_anchor_global

	var anchor_screen: Vector2 = cam.unproject_position(final_anchor_global)
	var target_screen: Vector2 = cam.unproject_position(final_target_global)

	_apply_screen_line(anchor_screen, target_screen)


func begin_attack_extra_swing(duration: float, direction_sign: float = 1.0) -> void:
	if not attack_extra_swing_enabled:
		return

	attack_extra_swing_active = true
	attack_extra_swing_start_msec = Time.get_ticks_msec()
	attack_extra_swing_duration = max(duration, 0.01)
	attack_extra_swing_sign = sign(direction_sign)

	if attack_extra_swing_sign == 0.0:
		attack_extra_swing_sign = 1.0


func end_attack_extra_swing() -> void:
	attack_extra_swing_active = false


func _get_attack_extra_swing_angle() -> float:
	if not attack_extra_swing_active:
		return 0.0

	var elapsed: float = float(Time.get_ticks_msec() - attack_extra_swing_start_msec) / 1000.0
	var t: float = clamp(elapsed / attack_extra_swing_duration, 0.0, 1.0)

	if t >= 1.0:
		if attack_extra_swing_return_to_zero:
			attack_extra_swing_active = false
		return 0.0

	var amp: float = deg_to_rad(attack_extra_swing_angle_deg)

	# Curva 0 → máximo → 0.
	# Da sensación de latigazo sin quedar torcido al final.
	var wave: float = sin(t * PI)

	return wave * amp * attack_extra_swing_sign
	

# =========================================================
# UTILIDADES
# =========================================================

func _get_camera() -> Camera3D:
	if camera_3d != null:
		return camera_3d

	return get_viewport().get_camera_3d()


func _hide_debug_line() -> void:
	if debug_line == null:
		return

	debug_line.visible = false
	debug_line.points = PackedVector2Array()
