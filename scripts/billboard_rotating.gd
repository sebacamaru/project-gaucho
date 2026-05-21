extends Node3D
class_name BillboardRotatingSpriteVisual

# =========================================================
# BillboardRotatingSpriteVisual
# ---------------------------------------------------------
# Permite usar un Sprite3D con Y-Billboard + Shaded normal,
# pero rotando visualmente su textura en 2D mediante SubViewport.
#
# Esto sirve para casos donde:
# - querés que el Sprite3D reciba luces correctamente;
# - querés usar Y-Billboard;
# - pero también necesitás rotar visualmente la imagen.
#
# La rotación NO ocurre en el Sprite3D.
# La rotación ocurre en un Sprite2D dentro de un SubViewport.
#
# Modos:
# - NONE: no rota.
# - MOUSE: apunta hacia el mouse en pantalla.
# - MANUAL: otro script le pasa el ángulo manualmente.
# =========================================================


enum RotationMode {
	NONE,
	MOUSE,
	MANUAL
}


# =========================================================
# CONFIGURACIÓN GENERAL
# =========================================================

@export var rotation_mode: RotationMode = RotationMode.MOUSE

# Cámara opcional.
# Si queda vacía, usa la cámara activa del viewport.
@export var camera_3d: Camera3D

# Sprite3D visible en el mundo.
# Este es el que mantiene Y-Billboard + Shaded.
@export var sprite_3d: Sprite3D

# Viewport que genera la textura dinámica.
@export var sub_viewport: SubViewport

# Sprite2D que rota dentro del SubViewport.
@export var sprite_2d: Sprite2D

# Textura original.
# Ejemplo: res://sprites/facon.png o res://sprites/lamparas.png
@export var source_texture: Texture2D

# Corrige la orientación según cómo esté dibujado el sprite.
# Si la textura ya apunta a la derecha, normalmente es 0.
# Si apunta hacia arriba, suele ser 90 o -90.
@export var angle_offset_degrees: float = 0.0

# Tamaño del Sprite3D en el mundo.
@export var sprite_3d_pixel_size: float = 0.01

# Tamaño de la imagen dentro del SubViewport.
@export var sprite_2d_scale: float = 1.0


# =========================================================
# PIVOTE VISUAL
# =========================================================

# Punto de pivote dentro de la textura original, en píxeles.
# Se mide desde la esquina superior izquierda del PNG.
#
# Para un facón apuntando a la derecha, suele estar cerca del mango.
# Ejemplo textura 128x128:
# texture_pivot_px = Vector2(25, 64)
#
# Si queda en Vector2.ZERO, usa el centro de la textura.
@export var texture_pivot_px: Vector2 = Vector2.ZERO


# =========================================================
# ROTACIÓN POR MOUSE
# =========================================================

# Zona muerta en píxeles alrededor del pivote.
# Si el mouse está demasiado cerca, no recalculamos el ángulo.
# Esto evita que el arma gire sobre sí misma cuando el mouse está
# encima del personaje o muy cerca del punto de origen.
@export var mouse_deadzone_px: float = 28.0

# Velocidad de suavizado al seguir el mouse.
# Más alto = más rápido / más rígido.
# Más bajo = más suave / más pesado.
@export var rotation_smooth_speed: float = 18.0


# =========================================================
# ESTADO INTERNO
# =========================================================

# Ángulo usado en modo MANUAL.
var manual_angle_rad: float = 0.0

# Último ángulo visual válido usado en modo MOUSE.
var current_visual_angle_rad: float = 0.0

# Sirve para saber si ya tenemos un ángulo válido.
# Al principio no conviene suavizar desde 0 porque puede pegar un tirón.
var has_valid_mouse_angle: bool = false


# =========================================================
# READY
# =========================================================

func _ready() -> void:
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
	# Configuración del SubViewport
	# -----------------------------------------------------
	# Fondo transparente para que el Sprite3D no tenga un cuadrado visible.
	sub_viewport.transparent_bg = true

	# Siempre actualiza la textura del viewport.
	# Necesario porque el Sprite2D interno va rotando.
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# -----------------------------------------------------
	# Configuración del Sprite3D visible
	# -----------------------------------------------------
	# El Sprite3D muestra la textura generada por el SubViewport.
	sprite_3d.texture = sub_viewport.get_texture()

	# Mantiene el comportamiento normal del Sprite3D.
	# Esto permite que el Shaded siga funcionando como corresponde.
	sprite_3d.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite_3d.shaded = true
	sprite_3d.transparent = true
	sprite_3d.double_sided = true
	sprite_3d.pixel_size = sprite_3d_pixel_size

	# -----------------------------------------------------
	# Configuración del Sprite2D interno
	# -----------------------------------------------------
	sprite_2d.texture = source_texture
	sprite_2d.centered = true

	# El origen del Sprite2D queda en el centro del SubViewport.
	# Ese origen es el punto real de rotación.
	sprite_2d.position = Vector2(sub_viewport.size) * 0.5

	# Escala visual dentro del SubViewport.
	sprite_2d.scale = Vector2.ONE * sprite_2d_scale

	# -----------------------------------------------------
	# Ajuste de pivote
	# -----------------------------------------------------
	# Si no configuraste texture_pivot_px, usamos el centro normal.
	var texture_size: Vector2 = source_texture.get_size()
	var pivot_px: Vector2 = texture_size * 0.5

	if texture_pivot_px != Vector2.ZERO:
		pivot_px = texture_pivot_px

	# Movemos el dibujo para que el punto elegido de la textura
	# quede justo sobre el origen del Sprite2D.
	#
	# Así rota desde el mango/pivote en vez de rotar desde el centro.
	sprite_2d.offset = (texture_size * 0.5) - pivot_px

	# Aplicamos una rotación inicial limpia.
	_apply_visual_angle(0.0)


# =========================================================
# PROCESS
# =========================================================

func _process(delta: float) -> void:
	match rotation_mode:
		RotationMode.NONE:
			_apply_visual_angle(0.0)

		RotationMode.MOUSE:
			_update_mouse_rotation(delta)

		RotationMode.MANUAL:
			_apply_visual_angle(manual_angle_rad)


# =========================================================
# API PÚBLICA PARA MODO MANUAL
# =========================================================

func set_manual_angle_radians(angle_rad: float) -> void:
	manual_angle_rad = angle_rad

	if rotation_mode == RotationMode.MANUAL:
		_apply_visual_angle(manual_angle_rad)


func set_manual_angle_degrees(angle_deg: float) -> void:
	set_manual_angle_radians(deg_to_rad(angle_deg))


func set_manual_angle_from_world_direction(origin_global: Vector3, direction_global: Vector3) -> void:
	var cam: Camera3D = camera_3d

	if cam == null:
		cam = get_viewport().get_camera_3d()

	if cam == null:
		return

	if direction_global.length_squared() < 0.001:
		return

	var dir_world: Vector3 = direction_global.normalized()

	# Convertimos una dirección 3D estable a dirección 2D en pantalla.
	# Esto es más robusto que calcular "mouse - pivote",
	# porque no se vuelve loco cuando el mouse está cerca del arma.
	var screen_a: Vector2 = cam.unproject_position(origin_global)
	var screen_b: Vector2 = cam.unproject_position(origin_global + dir_world)

	var screen_dir: Vector2 = screen_b - screen_a

	if screen_dir.length_squared() < 1.0:
		return

	var angle_rad: float = atan2(screen_dir.y, screen_dir.x)

	set_manual_angle_radians(angle_rad)


# =========================================================
# ROTACIÓN POR MOUSE
# =========================================================

func _update_mouse_rotation(delta: float) -> void:
	var cam: Camera3D = camera_3d

	# Si no asignaste cámara manualmente, usa la cámara activa del viewport.
	if cam == null:
		cam = get_viewport().get_camera_3d()

	if cam == null:
		return

	if sprite_3d == null or sprite_2d == null:
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()

	# Convertimos la posición 3D del sprite a coordenadas de pantalla.
	var sprite_screen_pos: Vector2 = cam.unproject_position(sprite_3d.global_position)

	# Dirección desde el sprite hacia el mouse en pantalla.
	var dir: Vector2 = mouse_pos - sprite_screen_pos

	# Distancia en píxeles entre el mouse y el pivote visual.
	var distance_px: float = dir.length()

	# -----------------------------------------------------
	# Zona muerta
	# -----------------------------------------------------
	# Si el mouse está muy cerca del pivote, la dirección se vuelve
	# demasiado inestable. Cualquier movimiento mínimo cambia mucho
	# el ángulo, por eso el facón gira sobre sí mismo.
	#
	# En ese caso, mantenemos el último ángulo válido.
	# -----------------------------------------------------
	if distance_px < mouse_deadzone_px:
		if has_valid_mouse_angle:
			_apply_visual_angle(current_visual_angle_rad)

		return

	# Calculamos el ángulo hacia el mouse.
	var target_angle_rad: float = atan2(dir.y, dir.x)

	# Primera vez: saltamos directo al ángulo correcto.
	# Esto evita que arranque interpolando desde 0 y pegue un giro raro.
	if not has_valid_mouse_angle:
		current_visual_angle_rad = target_angle_rad
		has_valid_mouse_angle = true
	else:
		# Suavizado angular.
		current_visual_angle_rad = lerp_angle(
			current_visual_angle_rad,
			target_angle_rad,
			rotation_smooth_speed * delta
		)

	_apply_visual_angle(current_visual_angle_rad)


# =========================================================
# APLICACIÓN FINAL DE ROTACIÓN
# =========================================================

func _apply_visual_angle(angle_rad: float) -> void:
	if sprite_2d == null:
		return

	# Aplicamos la rotación al Sprite2D interno.
	# El Sprite3D no rota visualmente; sigue usando billboard.
	sprite_2d.rotation = angle_rad + deg_to_rad(angle_offset_degrees)
