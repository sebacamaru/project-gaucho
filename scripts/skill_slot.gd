extends Control

var squish_tween: Tween
var is_unlocked: bool = false

func _ready() -> void:
	_update_pivot()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_pivot()

func _update_pivot() -> void:
	pivot_offset = size * 0.5

func play_use_squish() -> void:
	if squish_tween and squish_tween.is_valid():
		squish_tween.kill()

	scale = Vector2.ONE

	squish_tween = create_tween()
	squish_tween.set_trans(Tween.TRANS_QUAD)
	squish_tween.set_ease(Tween.EASE_OUT)

	squish_tween.tween_property(self, "scale", Vector2(0.88, 1.08), 0.045)
	squish_tween.tween_property(self, "scale", Vector2(1.04, 0.96), 0.05)
	squish_tween.tween_property(self, "scale", Vector2.ONE, 0.08)

func set_unlocked(unlocked: bool) -> void:
	is_unlocked = unlocked
	visible = is_unlocked
