extends Node
class_name PlayerProgress

# -----------------------------------------------------------------------------
# Señales
# -----------------------------------------------------------------------------

signal xp_changed(current_xp: int, xp_to_next: int, level: int)
signal level_changed(new_level: int)
signal level_up(new_level: int)

signal score_changed(new_score: int)
signal demons_killed_changed(total: int)

signal skill_unlocked(slot_name: String)

# -----------------------------------------------------------------------------
# Configuración de progresión
# -----------------------------------------------------------------------------

@export var level: int = 1
@export var current_xp: int = 0
@export var base_xp: int = 100
@export var xp_growth: float = 1.35
@export var max_level: int = 99

var unlocked_skills := {
	"skill_2": false,
	"skill_3": false,
	"skill_4": false
}

# -----------------------------------------------------------------------------
# Estadísticas de la partida
# -----------------------------------------------------------------------------

var score: int = 0
var demons_killed: int = 0

# -----------------------------------------------------------------------------
# Ciclo de vida
# -----------------------------------------------------------------------------

func _ready() -> void:
	_emit_progress()
	_emit_score()
	_emit_kills()

# -----------------------------------------------------------------------------
# Experiencia y nivel
# -----------------------------------------------------------------------------

func add_xp(amount: int) -> void:
	if amount <= 0:
		return

	if level >= max_level:
		return

	current_xp += amount

	while level < max_level and current_xp >= get_xp_to_next_level():
		current_xp -= get_xp_to_next_level()
		level += 1
		
		# Testing
		if level == 2:
			unlock_skill("skill_3")

		level_changed.emit(level)
		level_up.emit(level)

	if level >= max_level:
		current_xp = 0

	_emit_progress()

func get_xp_to_next_level() -> int:
	if level >= max_level:
		return 0

	return int(round(base_xp * pow(xp_growth, level - 1)))

func get_xp_ratio() -> float:
	var needed := get_xp_to_next_level()
	if needed <= 0:
		return 1.0

	return clamp(float(current_xp) / float(needed), 0.0, 1.0)

func _emit_progress() -> void:
	xp_changed.emit(current_xp, get_xp_to_next_level(), level)

func unlock_skill(slot_name: String) -> void:
	if not unlocked_skills.has(slot_name):
		return
	
	if unlocked_skills[slot_name]:
		return
	
	unlocked_skills[slot_name] = true
	skill_unlocked.emit(slot_name)

# -----------------------------------------------------------------------------
# Score
# -----------------------------------------------------------------------------

func add_score(amount: int) -> void:
	if amount <= 0:
		return

	score += amount
	_emit_score()

func _emit_score() -> void:
	score_changed.emit(score)

# -----------------------------------------------------------------------------
# Kills
# -----------------------------------------------------------------------------

func add_kill(points_reward: int = 0) -> void:
	demons_killed += 1
	_emit_kills()

	if points_reward > 0:
		add_score(points_reward)

func _emit_kills() -> void:
	demons_killed_changed.emit(demons_killed)

# -----------------------------------------------------------------------------
# Recompensas de enemigo
# -----------------------------------------------------------------------------

func register_enemy_kill(xp_reward: int, score_reward: int = 0) -> void:
	# Punto único de entrada para registrar una muerte de enemigo.
	# Así evitás repartir esta lógica por varios scripts.
	add_kill(score_reward)
	add_xp(xp_reward)
