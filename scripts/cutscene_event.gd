extends Node
class_name CutsceneEvent

# =========================================================
# CUTSCENE EVENT
# =========================================================
#
# Evento genérico de cutscene.
#
# Puede funcionar de dos maneras:
#
# 1) Como trigger:
#    - Se lo podés poner a un Area3D.
#    - Si trigger_on_body_entered está activo,
#      dispara la cutscene cuando entra el Player.
#
# 2) Como autorun:
#    - Se lo podés poner a un Node común.
#    - Si play_on_ready está activo,
#      dispara la cutscene al cargar la escena.
#
# Además, soporta follow-up cutscene:
# - una cutscene puede disparar otra después de X segundos
# - ese tiempo cuenta solo como gameplay libre
# - no cuenta si el árbol está pausado
# - no cuenta si otra cutscene está corriendo
#
# La cutscene concreta se define sobreescribiendo get_commands().
# =========================================================


# =========================================================
# CONFIGURACIÓN: DIRECTOR
# =========================================================

@export var director_path: NodePath
@export var director_group: StringName = &"cutscene_director"


# =========================================================
# CONFIGURACIÓN: PLAYER
# =========================================================

@export var player_path: NodePath
@export var player_group: StringName = &"player"


# =========================================================
# CONFIGURACIÓN: DISPARO
# =========================================================

@export var play_on_ready: bool = false
@export_range(0, 10, 1) var ready_delay_frames: int = 2

@export var trigger_on_body_entered: bool = true
@export var trigger_once: bool = true

@export var debug_action: StringName = &"debug_cutscene"
@export var print_debug: bool = true


# =========================================================
# CONFIGURACIÓN: FOLLOW-UP CUTSCENE
# =========================================================
#
# Permite encadenar otra cutscene después de que esta termine.
#
# Ejemplo:
#
# IntroCutscene termina
# → el jugador queda libre
# → pasan 30 segundos de gameplay real
# → se dispara SecondRadioCutscene
#
# Esto sirve para evitar repetir el mismo override en cada cutscene.
# =========================================================

# Si está activo, al terminar esta cutscene dispara otra.
@export var play_follow_up_cutscene: bool = false

# Cutscene siguiente.
#
# Debe ser otro nodo que extienda CutsceneEvent
# o al menos tenga run_cutscene().
#
# Ejemplo si ambos son hijos de Main:
#   ^"../SecondRadioCutscene"
@export var follow_up_cutscene_path: NodePath

# Tiempo de gameplay libre antes de disparar la follow-up.
@export_range(0.0, 600.0, 0.1) var follow_up_delay_seconds: float = 30.0

# Si está activo, la follow-up solo se dispara si esta cutscene
# terminó normalmente.
#
# Si el jugador skipea/cancela, no se dispara.
@export var follow_up_only_if_completed: bool = true

# Si está activo, el delay solo cuenta cuando:
# - el juego no está pausado
# - no hay otra cutscene corriendo
#
# Recomendado dejarlo activo.
@export var follow_up_counts_only_gameplay_time: bool = true

# Si está activo, le pasa el mismo player a la follow-up.
@export var pass_player_to_follow_up: bool = true


# =========================================================
# ESTADO INTERNO
# =========================================================

var _is_running: bool = false
var _already_used: bool = false
var _follow_up_running: bool = false


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	_connect_area_trigger_if_possible()

	var has_debug_action := debug_action != &"" and InputMap.has_action(debug_action)
	set_process_unhandled_input(has_debug_action)

	if play_on_ready:
		call_deferred("_play_on_ready_deferred")


func _connect_area_trigger_if_possible() -> void:
	if not trigger_on_body_entered:
		return

	# CutsceneEvent extiende Node para poder usarse tanto en:
	# - un Node común con play_on_ready
	# - un Area3D como trigger
	#
	# Como la clase base es Node, no casteamos a Area3D.
	# Detectamos dinámicamente si existe la señal body_entered.
	if not has_signal("body_entered"):
		return

	var callable := Callable(self, "_on_body_entered")

	if not is_connected("body_entered", callable):
		connect("body_entered", callable)


# =========================================================
# AUTORUN
# =========================================================

func _play_on_ready_deferred() -> void:
	for i in range(ready_delay_frames):
		await get_tree().process_frame

	await run_cutscene()


# =========================================================
# INPUT DEBUG
# =========================================================

func _unhandled_input(event: InputEvent) -> void:
	if debug_action == &"":
		return

	if not InputMap.has_action(debug_action):
		return

	if event.is_action_pressed(debug_action):
		get_viewport().set_input_as_handled()
		run_cutscene()


# =========================================================
# AREA TRIGGER
# =========================================================

func _on_body_entered(body: Node3D) -> void:
	if not trigger_on_body_entered:
		return

	if not _body_can_trigger(body):
		return

	run_cutscene(body)


func _body_can_trigger(body: Node3D) -> bool:
	if body == null:
		return false

	var configured_player := _get_configured_player()

	if configured_player != null:
		return body == configured_player

	if player_group != &"" and body.is_in_group(player_group):
		return true

	return body.has_method("set_cutscene_mode") and body.has_method("cutscene_walk_to")


# =========================================================
# CUTSCENE PRINCIPAL
# =========================================================

func run_cutscene(player_override: Node = null) -> void:
	if _is_running:
		return

	if trigger_once and _already_used:
		return

	var director := _resolve_director()

	if director == null:
		push_warning("%s: no se encontró CutsceneDirector." % name)
		return

	if not director.has_method("run_commands"):
		push_warning("%s: el director no tiene run_commands()." % name)
		return

	var commands := get_commands()

	if commands.is_empty():
		push_warning("%s: get_commands() devolvió una lista vacía." % name)
		return

	var player := player_override

	if player == null:
		player = _get_configured_player()

	_is_running = true
	_already_used = true

	if print_debug:
		print("CutsceneEvent: start ", name)

	var completed: bool = await director.run_commands(player, commands, self)

	_is_running = false

	if print_debug:
		print("CutsceneEvent: finished ", name, " completed=", completed)

	# ---------------------------------------------------------
	# FOLLOW-UP CUTSCENE
	# ---------------------------------------------------------
	# Importante:
	# Esto corre después de que director.run_commands() terminó.
	# Si auto_end estaba activo, el Director ya liberó al player.
	# Por eso el delay cuenta como gameplay real.
	# ---------------------------------------------------------
	if _should_play_follow_up(completed):
		await _run_follow_up_flow(player)


# =========================================================
# COMANDOS
# =========================================================

func get_commands() -> Array:
	return []


# =========================================================
# FOLLOW-UP CUTSCENE
# =========================================================

func _should_play_follow_up(completed: bool) -> bool:
	if not play_follow_up_cutscene:
		return false

	if _follow_up_running:
		return false

	if follow_up_cutscene_path == NodePath():
		return false

	if follow_up_only_if_completed and not completed:
		return false

	return true


func _run_follow_up_flow(player: Node = null) -> void:
	_follow_up_running = true

	if follow_up_delay_seconds > 0.0:
		await _wait_before_follow_up(follow_up_delay_seconds)

	var follow_up := get_node_or_null(follow_up_cutscene_path)

	if follow_up == null:
		push_warning("%s: no se encontró la follow-up cutscene." % name)
		_follow_up_running = false
		return

	if not follow_up.has_method("run_cutscene"):
		push_warning("%s: la follow-up cutscene no tiene run_cutscene()." % name)
		_follow_up_running = false
		return

	if print_debug:
		print("CutsceneEvent: follow-up start ", name, " -> ", follow_up.name)

	if pass_player_to_follow_up:
		await follow_up.run_cutscene(player)
	else:
		await follow_up.run_cutscene()

	_follow_up_running = false


func _wait_before_follow_up(seconds: float) -> void:
	if seconds <= 0.0:
		return

	var elapsed := 0.0

	while elapsed < seconds:
		await get_tree().process_frame

		if follow_up_counts_only_gameplay_time:
			if get_tree().paused:
				continue

			if _is_any_cutscene_running():
				continue

		elapsed += get_process_delta_time()


func _is_any_cutscene_running() -> bool:
	var director := get_tree().get_first_node_in_group("cutscene_director")

	if director == null:
		return false

	if "is_running" in director:
		return bool(director.is_running)

	return false


# =========================================================
# HELPERS
# =========================================================

func _resolve_director() -> Node:
	if director_path != NodePath():
		var director_from_path := get_node_or_null(director_path)

		if director_from_path != null:
			return director_from_path

	if director_group != &"":
		var grouped_director := get_tree().get_first_node_in_group(director_group)

		if grouped_director != null:
			return grouped_director

	return null


func _get_configured_player() -> Node:
	if player_path != NodePath():
		var player_from_path := get_node_or_null(player_path)

		if player_from_path != null:
			return player_from_path

	if player_group != &"":
		var grouped_player := get_tree().get_first_node_in_group(player_group)

		if grouped_player != null:
			return grouped_player

	return null
