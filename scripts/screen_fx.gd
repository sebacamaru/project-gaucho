extends Node

@onready var camera: Camera3D = get_tree().get_first_node_in_group("camera")
@onready var flash_rect: ColorRect = $CanvasLayer/DamageRect

var shake_strength: float = 0.0
var shake_fade: float = 20.0
var shake_offset: Vector3 = Vector3.ZERO
var camera_base_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	flash_rect.color.a = 0.0
	
	if is_instance_valid(camera):
		camera_base_position = camera.position

func _process(delta: float) -> void:
	update_shake(delta)
	
	if is_instance_valid(camera):
		camera.position = camera_base_position + shake_offset

func update_shake(delta: float) -> void:
	if shake_strength > 0.01:
		shake_offset = Vector3(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength),
			0.0
		)
		shake_strength = move_toward(shake_strength, 0.0, shake_fade * delta)
	else:
		shake_offset = Vector3.ZERO

func play_damage_feedback() -> void:
	play_shake(0.3, 4)
	play_flash(Color(1.0, 0.0, 0.059, 0.153), 0.16, 0.22)

func play_shake(strength: float, fade: float = 20.0) -> void:
	shake_strength = max(shake_strength, strength)
	shake_fade = fade

func play_flash(color: Color, fade_in: float = 0.04, fade_out: float = 0.10) -> void:
	flash_rect.color = Color(color.r, color.g, color.b, 0.0)
	
	var tween := create_tween()
	tween.tween_property(flash_rect, "color:a", color.a, fade_in)
	tween.tween_property(flash_rect, "color:a", 0.0, fade_out)
