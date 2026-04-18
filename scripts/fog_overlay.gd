extends ColorRect

@export var player_path: NodePath

@onready var player: Node3D = get_node(player_path)

var camera: Camera3D


func _ready() -> void:
	camera = get_viewport().get_camera_3d()


func _process(_delta: float) -> void:
	if player == null or camera == null:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	# ---------------------------------------------------------
	# 1) PASAMOS LA POSICIÓN DEL JUGADOR EN PANTALLA
	#    Esto sirve para que el hueco limpio quede donde está él.
	# ---------------------------------------------------------
	var screen_pos: Vector2 = camera.unproject_position(player.global_position)

	var uv := Vector2(
		screen_pos.x / viewport_size.x,
		screen_pos.y / viewport_size.y
	)

	material.set_shader_parameter("player_screen_uv", uv)

	# ---------------------------------------------------------
	# 2) PASAMOS UN OFFSET BASADO EN LA CÁMARA EN EL MUNDO
	#    Esto hace que el patrón de niebla no quede pegado
	#    a la pantalla, sino que parezca más anclado al mapa.
	# ---------------------------------------------------------
	var cam_pos := camera.global_position
	var cam_offset := Vector2(cam_pos.x, cam_pos.z)

	material.set_shader_parameter("camera_world_offset", cam_offset)
