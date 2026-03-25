extends Area3D

@export var damage := 10

var hit_targets := {}

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func begin_attack() -> void:
	hit_targets.clear()
	$CollisionShape3D.disabled = false

func end_attack() -> void:
	$CollisionShape3D.disabled = true

func _try_hit(target: Node) -> void:
	if target == null:
		return
	
	if hit_targets.has(target):
		return
	
	hit_targets[target] = true
	
	if target.has_method("take_damage"):
		target.take_damage(damage)

func _on_body_entered(body: Node) -> void:
	_try_hit(body)

func _on_area_entered(area: Area3D) -> void:
	if area.has_method("get_hit_owner"):
		_try_hit(area.get_hit_owner())
	elif area.get_parent() != null:
		_try_hit(area.get_parent())
