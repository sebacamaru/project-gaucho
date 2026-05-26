extends Node
class_name SurvivorModeManager

# =========================================================
# SURVIVOR MODE MANAGER
# =========================================================
#
# Maneja el estado general del modo survivor:
# - iniciar nivel
# - timer de cuenta regresiva
# - mostrar TopUI
# - mostrar BottomRightUI
# - acumular nivel / demonios / puntos entre niveles
#
# Importante:
# Este script NO reemplaza al LevelUpManager.
#
# LevelUpManager:
# - se ocupa de upgrades y panel de subida de nivel.
#
# SurvivorModeManager:
# - se ocupa del flujo de partida survivor.
# - guarda datos acumulados de la run.
# =========================================================

@export var debug_survivor_timer: bool = true

# =========================================================
# CONFIGURACIÓN: LEVEL
# =========================================================

# Duración default de cada nivel survivor.
# 666 segundos = 11:06.
@export var level_duration_seconds: float = 666.0


# =========================================================
# CONFIGURACIÓN: UI
# =========================================================
#
# Este script está pensado para estar como hijo de:
#
# HUD/CanvasLayer/SurvivorModeManager
#
# Por eso los paths default apuntan a:
#
# ../UI/TopUI
# ../UI/TopUI/TopCenterContainer/BossTimerLabel
# ../UI/BottomRightUI
# ../UI/BottomRightUI/Container/Nivel
# ../UI/BottomRightUI/Container/demonios
# ../UI/BottomRightUI/Container/puntos
# =========================================================

@export var top_ui_path: NodePath = ^"../HUD/CanvasLayer/UI/TopUI"
@export var bottom_right_ui_path: NodePath = ^"../HUD/CanvasLayer/UI/BottomRightUI"

@export var boss_timer_label_path: NodePath = ^"../HUD/CanvasLayer/UI/TopUI/TopCenterContainer/BossTimerLabel"

@export var level_label_path: NodePath = ^"../HUD/CanvasLayer/UI/BottomRightUI/Container/Nivel"
@export var demons_label_path: NodePath = ^"../HUD/CanvasLayer/UI/BottomRightUI/Container/demonios"
@export var points_label_path: NodePath = ^"../HUD/CanvasLayer/UI/BottomRightUI/Container/puntos"

# Texto antes del timer.
# Ejemplo final: "Jefe en 11:06"
@export var boss_timer_prefix: String = "Jefe en "

# Si está activo, oculta estas UI al arrancar la escena.
# Después start_level() las muestra.
@export var hide_ui_on_ready: bool = true


# =========================================================
# REFERENCIAS UI
# =========================================================

@onready var top_ui: CanvasItem = get_node_or_null(top_ui_path) as CanvasItem
@onready var bottom_right_ui: CanvasItem = get_node_or_null(bottom_right_ui_path) as CanvasItem

@onready var boss_timer_label: Label = get_node_or_null(boss_timer_label_path) as Label

@onready var level_label: Label = get_node_or_null(level_label_path) as Label
@onready var demons_label: Label = get_node_or_null(demons_label_path) as Label
@onready var points_label: Label = get_node_or_null(points_label_path) as Label


# =========================================================
# ESTADO DE RUN
# =========================================================
#
# Estos datos se acumulan durante la partida.
# No se resetean en cada start_level().
# =========================================================

var is_run_active: bool = false
var is_level_active: bool = false

var current_level: int = 0
var total_demons: int = 0
var total_points: int = 0

# Tiempo restante del nivel actual, en segundos.
var level_time_remaining: float = 0.0


# =========================================================
# SEÑALES
# =========================================================

signal run_started
signal run_finished

signal level_started(level: int, duration_seconds: float)
signal level_finished(level: int, reason: String)

signal survivor_stats_changed(level: int, demons: int, points: int)
signal level_timer_changed(seconds_remaining: float)


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	add_to_group("survivor_mode_manager")

	if debug_survivor_timer:
		print("")
		print("========== DEBUG SURVIVOR READY ==========")
		print("SurvivorModeManager path: ", get_path())
		print("level_duration_seconds export: ", level_duration_seconds)
		print("boss_timer_label_path: ", boss_timer_label_path)
		print("boss_timer_label encontrado: ", boss_timer_label)
		if boss_timer_label != null:
			print("boss_timer_label path real: ", boss_timer_label.get_path())
		print("==========================================")
		print("")

	if hide_ui_on_ready:
		_set_survivor_ui_visible(false)

	_update_all_ui()


# =========================================================
# PROCESS
# =========================================================

func _process(delta: float) -> void:
	if not is_level_active:
		return

	level_time_remaining -= delta

	if level_time_remaining <= 0.0:
		level_time_remaining = 0.0
		_update_timer_ui()
		finish_level("timer_finished")
		return

	_update_timer_ui()
	level_timer_changed.emit(level_time_remaining)


# =========================================================
# API PRINCIPAL
# =========================================================

func start_run(initial_level: int = 1) -> void:
	# Arranca una run nueva desde cero.
	#
	# Esto SÍ resetea acumulados:
	# - nivel
	# - demonios
	# - puntos
	#
	# Usalo cuando empieza una partida nueva.

	is_run_active = true
	is_level_active = false

	current_level = max(initial_level - 1, 0)
	total_demons = 0
	total_points = 0
	level_time_remaining = 0.0

	_set_survivor_ui_visible(true)
	_update_all_ui()

	run_started.emit()
	survivor_stats_changed.emit(current_level, total_demons, total_points)

	start_level()


func start_level(duration_seconds: float = -1.0) -> void:
	if debug_survivor_timer:
		print("")
		print("========== DEBUG SURVIVOR START_LEVEL ==========")
		print("SurvivorModeManager path: ", get_path())
		print("duration_seconds recibido: ", duration_seconds)
		print("level_duration_seconds export: ", level_duration_seconds)
		print("level_time_remaining ANTES: ", level_time_remaining)
		print("is_level_active ANTES: ", is_level_active)
		print("===============================================")
		print("")

	if not is_run_active:
		is_run_active = true
		run_started.emit()

	var final_duration: float = level_duration_seconds

	if duration_seconds >= 0.0:
		final_duration = duration_seconds

	level_time_remaining = final_duration
	is_level_active = true

	_set_survivor_ui_visible(true)
	_update_all_ui()

	if debug_survivor_timer:
		print("")
		print("========== DEBUG SURVIVOR START_LEVEL RESULT ==========")
		print("final_duration usado: ", final_duration)
		print("level_time_remaining DESPUÉS: ", level_time_remaining)
		print("timer label text: ", boss_timer_label.text if boss_timer_label != null else "<sin label>")
		print("timer esperado: ", _format_seconds_as_minutes(int(ceil(final_duration))))
		print("=======================================================")
		print("")

	# Ojo: si sacaste level del signal, cambiá también la señal.
	level_started.emit(final_duration)
	survivor_stats_changed.emit(current_level, total_demons, total_points)


func finish_level(reason: String = "completed") -> void:
	# Termina el nivel actual.
	#
	# No oculta la UI ni resetea acumulados.
	# Así podés mostrar transición, level up, recompensas, etc.

	if not is_level_active:
		return

	is_level_active = false
	level_time_remaining = 0.0

	_update_timer_ui()

	level_finished.emit(current_level, reason)


func finish_run() -> void:
	# Termina toda la run.
	#
	# Acá sí apagamos el estado general.
	# Podés decidir si ocultar o no la UI.

	is_level_active = false
	is_run_active = false
	level_time_remaining = 0.0

	_update_all_ui()
	run_finished.emit()


func hide_survivor_ui() -> void:
	_set_survivor_ui_visible(false)


func show_survivor_ui() -> void:
	_set_survivor_ui_visible(true)
	_update_all_ui()


# =========================================================
# API: ACUMULADOS
# =========================================================

func add_demon_kill(amount: int = 1, points_per_demon: int = 0) -> void:
	# Llamar cuando muere un enemigo/demonio.
	#
	# Ejemplo:
	# survivor_mode_manager.add_demon_kill(1, 10)

	if amount <= 0:
		return

	total_demons += amount

	if points_per_demon != 0:
		total_points += amount * points_per_demon

	_update_stats_ui()
	survivor_stats_changed.emit(current_level, total_demons, total_points)


func add_points(amount: int) -> void:
	# Suma puntos sin tocar demonios.
	#
	# Ejemplo:
	# survivor_mode_manager.add_points(50)

	if amount == 0:
		return

	total_points += amount

	_update_stats_ui()
	survivor_stats_changed.emit(current_level, total_demons, total_points)


func set_points(value: int) -> void:
	total_points = max(value, 0)

	_update_stats_ui()
	survivor_stats_changed.emit(current_level, total_demons, total_points)


func set_demons(value: int) -> void:
	total_demons = max(value, 0)

	_update_stats_ui()
	survivor_stats_changed.emit(current_level, total_demons, total_points)


# =========================================================
# UI
# =========================================================

func _set_survivor_ui_visible(value: bool) -> void:
	if top_ui != null:
		top_ui.visible = value

	if bottom_right_ui != null:
		bottom_right_ui.visible = value


func _update_all_ui() -> void:
	_update_timer_ui()
	_update_stats_ui()


func _update_timer_ui() -> void:
	if boss_timer_label == null:
		return

	var display_seconds := int(ceil(max(level_time_remaining, 0.0)))
	boss_timer_label.text = boss_timer_prefix + _format_seconds_as_minutes(display_seconds)


func _update_stats_ui() -> void:
	if level_label != null:
		level_label.text = str(current_level)

	if demons_label != null:
		demons_label.text = str(total_demons)

	if points_label != null:
		points_label.text = _format_points(total_points)


# =========================================================
# FORMAT HELPERS
# =========================================================

func _format_seconds_as_minutes(total_seconds: int) -> String:
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60

	return "%d:%02d" % [minutes, seconds]


func _format_points(value: int) -> String:
	# Si querés que se vea como 00000089.
	return "%08d" % max(value, 0)
