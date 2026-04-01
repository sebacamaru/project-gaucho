extends Control

@onready var boss_timer_label: Label = $TopUI/TopCenterContainer/BossTimerLabel
@onready var exp_bar: TextureProgressBar = $TopUI/ExpBar

var boss_time_left: float = 328.0
var current_exp: float = 80.0
var max_exp: float = 100.0

func _ready() -> void:
	exp_bar.max_value = max_exp
	exp_bar.value = current_exp
	update_boss_timer()

func _process(delta: float) -> void:
	if boss_time_left > 0.0:
		boss_time_left -= delta
		if boss_time_left < 0.0:
			boss_time_left = 0.0
	
	update_boss_timer()

func update_boss_timer() -> void:
	var total_seconds: int = int(ceil(boss_time_left))
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	boss_timer_label.text = "Jefe en %d:%02d" % [minutes, seconds]
