extends Control

@onready var boss_timer_label: Label = $TopUI/TopCenterContainer/BossTimerLabel
@onready var exp_bar: TextureProgressBar = $TopUI/ExpBar
@onready var health_bar: TextureProgressBar = $BottomCenterUI/HealthBar
@onready var player = get_tree().get_first_node_in_group("player")

@onready var skill_1: Control = $BottomLeftUI/SkillsContainer/Skill1
@onready var skill_2: Control = $BottomLeftUI/SkillsContainer/Skill2
@onready var skill_3: Control = $BottomLeftUI/SkillsContainer/Skill3
@onready var skill_4: Control = $BottomLeftUI/SkillsContainer/Skill4

var boss_time_left: float = 328.0
var current_exp: float = 80.0
var max_exp: float = 100.0

func _ready() -> void:
	exp_bar.max_value = max_exp
	exp_bar.value = current_exp
	update_boss_timer()
	if player:
		player.hp_changed.connect(_on_player_hp_changed)
		_on_player_hp_changed(player.hp, player.max_hp)
		player.skill_used.connect(_on_player_skill_used)
		player.skill_unlocked.connect(_on_player_skill_unlocked)
		_refresh_skill_ui()

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

func _on_player_hp_changed(current_hp: int, max_hp: int) -> void:
	health_bar.min_value = 0
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	
func _on_player_skill_unlocked(slot_name: String) -> void:
	match slot_name:
		"skill_2":
			skill_2.set_unlocked(true)
		"skill_3":
			skill_3.set_unlocked(true)
		"skill_3":
			skill_4.set_unlocked(true)
			
func _on_player_skill_used(slot_name: String) -> void:
	match slot_name:
		"skill_1":
			skill_1.play_use_squish()
		"skill_2":
			skill_2.play_use_squish()
		"skill_3":
			skill_3.play_use_squish()
		"skill_4":
			skill_4.play_use_squish()
			
	
func _refresh_skill_ui() -> void:
	skill_2.set_unlocked(player.unlocked_skills.get("skill_2", false))
	skill_3.set_unlocked(player.unlocked_skills.get("skill_3", false))
	skill_4.set_unlocked(player.unlocked_skills.get("skill_4", false))
