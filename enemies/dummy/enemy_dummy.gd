extends Node3D

@export var max_hp: int = 30
var hp: int

@onready var sprite = $Sprites/Sprite3D

func _ready() -> void:
	hp = max_hp

func take_damage(amount: int) -> void:
	hp -= amount
	print("Enemy hit! Damage:", amount, " HP:", hp)

	flash_hit()

	if hp <= 0:
		die()

func flash_hit() -> void:
	if sprite is Sprite3D:
		sprite.modulate = Color(1, 0.4, 0.4, 1)
		await get_tree().create_timer(0.08).timeout
		if is_instance_valid(sprite):
			sprite.modulate = Color(1, 1, 1, 1)

func die() -> void:
	print("Enemy died")
	queue_free()
