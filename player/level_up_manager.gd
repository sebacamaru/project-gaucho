extends Node
class_name LevelUpManager

# Maneja el flujo de subida de nivel:
# - escucha el level_up del PlayerProgress
# - genera opciones
# - muestra el panel
# - aplica la mejora elegida

@onready var player = get_parent()
@onready var progress: PlayerProgress = player.get_node("PlayerProgress")
@onready var weapon_component: WeaponComponent = player.get_node("WeaponComponent")
@onready var dash_skill: DashSkill = player.get_node("DashSkill")
@onready var level_up_panel: LevelUpPanel = get_node("../../HUD/CanvasLayer/LevelUpPanel")

const ICON_FACON = preload("res://ui/bg-skill-1.png")
const ICON_SHOTGUN = preload("res://ui/bg-skill-2.png")
const ICON_DASH = preload("res://ui/bg-skill-3.png")
# const ICON_BOLEADORAS = preload("res://ui/bg-skill-4.png")
const ICON_PLACEHOLDER = preload("res://ui/bg-skill-placeholder.png")

var is_choosing_upgrade: bool = false

func _ready() -> void:
	progress.level_up.connect(_on_level_up)
	level_up_panel.option_selected.connect(_on_option_selected)
	level_up_panel.hide_panel()

func _on_level_up(new_level: int) -> void:
	if is_choosing_upgrade:
		return

	is_choosing_upgrade = true
	await _show_level_up_flow(new_level)

func _show_level_up_flow(new_level: int) -> void:
	# Dar tiempo a que la UI del level up se vea
	await get_tree().create_timer(0.35).timeout

	var options: Array[Dictionary]

	# Nivel 2: primera elección fija entre dash / escopeta / boleadoras
	if new_level == 2:
		options = get_first_level_choices()
	else:
		options = build_upgrade_choices()

	level_up_panel.show_options(options, new_level)
	get_tree().paused = true

func build_upgrade_choices() -> Array[Dictionary]:
	var pool := get_available_upgrades()
	pool.shuffle()

	var result: Array[Dictionary] = []
	var count: int = min(3, pool.size())

	for i in range(count):
		result.append(pool[i])

	return result

func make_upgrade_data(id: String) -> Dictionary:
	match id:
		"facon_level_up":
			return {
				"id": id,
				"title": "Facón afilado",
				"description": "Aumenta el nivel del facón.",
				"icon": ICON_FACON
			}

		"learn_dash":
			return {
				"id": id,
				"title": "Dash",
				"description": "Desbloquea un dash rápido para reposicionarte.",
				"icon": ICON_DASH
			}

		"learn_shotgun":
			return {
				"id": id,
				"title": "Escopeta",
				"description": "Dispara múltiples perdigones a corta distancia.",
				"icon": ICON_SHOTGUN
			}

		"learn_boleadoras":
			return {
				"id": id,
				"title": "Boleadoras",
				"description": "Lanza boleadoras para frenar enemigos.",
				"icon": ICON_PLACEHOLDER
			}

		"max_hp_up":
			return {
				"id": id,
				"title": "Más aguante",
				"description": "Aumenta la vida máxima en 1 y te cura 1.",
				"icon": ICON_PLACEHOLDER
			}

		"move_speed_up":
			return {
				"id": id,
				"title": "Botas ligeras",
				"description": "Aumenta la velocidad de movimiento.",
				"icon": ICON_PLACEHOLDER
			}

	push_warning("Upgrade desconocido: %s" % id)
	return {}

func get_first_level_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	# Solo agregamos las que todavía no estén desbloqueadas,
	# por si en algún momento reutilizás esta función.
	if not dash_skill.is_unlocked:
		result.append(make_upgrade_data("learn_dash"))

	if not weapon_component.shotgun_unlocked:
		result.append(make_upgrade_data("learn_shotgun"))

	if not weapon_component.boleadoras_unlocked:
		result.append(make_upgrade_data("learn_boleadoras"))

	return result

func get_available_upgrades() -> Array[Dictionary]:
	var upgrades: Array[Dictionary] = []

	#upgrades.append(make_upgrade_data("facon_level_up"))

	if not dash_skill.is_unlocked:
		upgrades.append(make_upgrade_data("learn_dash"))

	if not weapon_component.shotgun_unlocked:
		upgrades.append(make_upgrade_data("learn_shotgun"))

	if not weapon_component.boleadoras_unlocked:
		upgrades.append(make_upgrade_data("learn_boleadoras"))

	upgrades.append(make_upgrade_data("max_hp_up"))
	upgrades.append(make_upgrade_data("move_speed_up"))

	return upgrades

func _on_option_selected(upgrade_id: String) -> void:
	apply_upgrade(upgrade_id)

	level_up_panel.hide_panel()
	get_tree().paused = false
	is_choosing_upgrade = false

func apply_upgrade(upgrade_id: String) -> void:
	match upgrade_id:
		"facon_level_up":
			print("facon_level_up")
			weapon_component.level_up_facon()

		"learn_dash":
			print("learn_dash")
			player.progress.unlock_skill("dash")

		"learn_shotgun":
			print("learn_shotgun")
			weapon_component.shotgun_unlocked = true
			player.progress.unlock_skill("shotgun")

		"learn_boleadoras":
			print("learn_boleadoras")
			weapon_component.boleadoras_unlocked = true

		"max_hp_up":
			print("max_hp_up")
			player.max_hp += 1
			player.hp = min(player.hp + 1, player.max_hp)
			player.hp_changed.emit(player.hp, player.max_hp)

		"move_speed_up":
			print("move_speed_up")
			player.speed += 0.4
