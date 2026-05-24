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
# La cutscene concreta se define sobreescribiendo get_commands().
#
# Ejemplo:
#
# func get_commands() -> Array:
#     return [
#         {"type": "camera_zoom", "value": 28.0, "duration": 0.45},
#         {"type": "say", "speaker": "Rick", "text": "Texto..."},
#         {"type": "walk_player_to_marker", "marker_path": ^"CutsceneTarget"},
#         {"type": "camera_restore", "duration": 0.45}
#     ]
# =========================================================


# =========================================================
# CONFIGURACIÓN: DIRECTOR
# =========================================================

# Director de cutscenes.
# Podés asignarlo desde el Inspector.
#
# Si lo dejás vacío, busca por grupo "cutscene_director".
@export var director_path: NodePath
@export var director_group: StringName = &"cutscene_director"


# =========================================================
# CONFIGURACIÓN: PLAYER
# =========================================================

# Player a controlar.
# Podés asignarlo desde el Inspector.
#
# Si lo dejás vacío:
# - en modo trigger usa el body que entró
# - en modo autorun busca por grupo "player"
@export var player_path: NodePath
@export var player_group: StringName = &"player"


# =========================================================
# CONFIGURACIÓN: DISPARO
# =========================================================

# Dispara la cutscene automáticamente al cargar la escena.
@export var play_on_ready: bool = false

# Cantidad de frames a esperar antes del autorun.
#
# Esto evita problemas típicos al cargar escena:
# - cámara todavía no activa
# - HUD todavía no listo
# - Player todavía acomodándose
@export_range(0, 10, 1) var ready_delay_frames: int = 2

# Si este script está puesto en un Area3D,
# puede dispararse cuando entra el Player.
@export var trigger_on_body_entered: bool = true

# Si está activo, el evento solo se puede ejecutar una vez.
@export var trigger_once: bool = true

# Acción opcional de debug.
# Si existe en Input Map, dispara la cutscene manualmente.
@export var debug_action: StringName = &"debug_cutscene"

# Debug.
@export var print_debug: bool = true


# =========================================================
# ESTADO INTERNO
# =========================================================

var _is_running: bool = false
var _already_used: bool = false


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
	# Pero como la clase base es Node, no podemos hacer:
	#   self is Area3D
	#
	# Entonces detectamos dinámicamente si este nodo tiene
	# la señal "body_entered", que es lo que necesitamos.
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

	# Si hay player configurado por path, solo ese body puede disparar.
	if configured_player != null:
		return body == configured_player

	# Si no hay path, usamos grupo.
	if player_group != &"" and body.is_in_group(player_group):
		return true

	# Fallback: aceptamos un body que parezca Player.
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


# =========================================================
# COMANDOS
# =========================================================

func get_commands() -> Array:
	# Esta función se sobreescribe en cada cutscene concreta.
	#
	# Ejemplo:
	#
	# func get_commands() -> Array:
	#     return [
	#         {"type": "camera_zoom", "value": 28.0, "duration": 0.45},
	#         {"type": "say", "speaker": "Gaucho", "text": "La noche está rara."},
	#         {"type": "camera_restore", "duration": 0.45}
	#     ]
	return []


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
