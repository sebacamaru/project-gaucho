extends Node3D

const ENEMY_DISSOLVE_SHADER = preload("res://shaders/enemy_dissolve.gdshader")

@export var max_hp: int = 4
var hp: int
var is_dying := false

@onready var sprite      = $Sprites/Sprite3D
@onready var aura_sprite = $Sprites/AuraSprite3D
@onready var hurtbox     = $Hurtbox

func _ready() -> void:
	hp = max_hp

func take_damage(amount: int) -> void:
	if is_dying:
		return
	
	hp -= amount
	print("Enemy hit! Damage:", amount, " HP:", hp)
	flash_hit()
	
	if hp <= 0:
		die()

func flash_hit() -> void:
	sprite.modulate = Color(0.904, 0.481, 0.447, 1.0)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(sprite) and not is_dying:
		sprite.modulate = Color(1, 1, 1, 1)

func die() -> void:
	is_dying = true
	hurtbox.monitoring = false

	var mat := ShaderMaterial.new()
	mat.shader = ENEMY_DISSOLVE_SHADER
	mat.set_shader_parameter("texture_albedo", sprite.texture)
	mat.set_shader_parameter("dissolve_amount", 0.0)
	sprite.material_override = mat
	sprite.modulate = Color(1, 1, 1, 1)

	var tween = create_tween()
	tween.set_parallel(true)

	# Sprite principal
	tween.tween_method(
		func(v: float): mat.set_shader_parameter("dissolve_amount", v),
		0.0, 1.0, 0.4
	)

	# Aura: fade de global_alpha
	var aura_mat := aura_sprite.material_override as ShaderMaterial
	if aura_mat:
		var start_alpha: float = aura_mat.get_shader_parameter("global_alpha")
		tween.tween_method(
			func(v: float): aura_mat.set_shader_parameter("global_alpha", v),
			start_alpha, 0.0, 0.4
		)

	await tween.finished
	queue_free()
