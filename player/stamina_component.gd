extends Node
class_name StaminaComponent

signal changed(current: float, max_value: float)
signal became_full()
signal emptied()

@export var max_stamina: float = 100.0
@export var recharge_rate: float = 40.0

var current_stamina: float = 0.0
var _was_full: bool = false

func _ready() -> void:
	current_stamina = max_stamina
	_was_full = true
	changed.emit(current_stamina, max_stamina)

func _process(delta: float) -> void:
	if current_stamina < max_stamina:
		current_stamina = min(current_stamina + recharge_rate * delta, max_stamina)
		changed.emit(current_stamina, max_stamina)

		if not _was_full and is_full():
			_was_full = true
			became_full.emit()

func is_full() -> bool:
	return current_stamina >= max_stamina - 0.001

func empty() -> void:
	current_stamina = 0.0
	_was_full = false
	changed.emit(current_stamina, max_stamina)
	emptied.emit()

func set_recharge_rate(value: float) -> void:
	recharge_rate = max(1.0, value)
