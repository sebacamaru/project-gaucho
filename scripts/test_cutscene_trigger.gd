extends Area3D
class_name TestCutsceneTrigger

# =========================================================
# TEST CUTSCENE TRIGGER
# =========================================================
#
# Trigger de prueba para cutscenes.
#
# Flujo:
# - El Player entra en el Area3D.
# - El trigger busca el CutsceneDirector.
# - El director inicia la cutscene.
# - Se hace zoom de cámara.
# - Se muestra un diálogo opcional.
# - El Player camina hasta CutsceneTarget.
# - Espera un instante.
# - La cámara vuelve a su estado original.
# - El director termina la cutscene.
#
# Además:
# - Si el jugador saltea la cutscene desde el CutsceneDirector,
#   este trigger detecta el skip después de cada await y corta
#   la secuencia para que no siga ejecutando pasos viejos.
#
# Este script sigue siendo de prueba, pero ya representa
# bastante bien una cutscene simple real.
# =========================================================


# =========================================================
# CONFIGURACIÓN: REFERENCIAS
# =========================================================

# Director de cutscenes.
# Podés asignarlo desde el Inspector.
#
# Si lo dejás vacío, busca un nodo en el grupo "cutscene_director".
@export var director_path: NodePath

# Player a controlar.
# Podés asignarlo desde el Inspector.
#
# Si lo dejás vacío:
# - intenta usar el body que entró al área
# - o deja que el director busque por grupo "player".
@export var player_path: NodePath

# Marker al que va a caminar el player.
# Por defecto busca un hijo llamado "CutsceneTarget".
@export var target_marker_path: NodePath = ^"CutsceneTarget"


# =========================================================
# CONFIGURACIÓN: MOVIMIENTO
# =========================================================

# Velocidad del player durante la caminata de cutscene.
@export var walk_speed: float = 2.5

# Tiempo de espera al llegar.
@export var wait_after_arrival: float = 0.35


# =========================================================
# CONFIGURACIÓN: CÁMARA
# =========================================================

# Activa/desactiva el zoom de cámara para esta cutscene.
@export var use_camera_zoom: bool = true

# Valor objetivo del zoom.
#
# Si tu cámara es Perspective:
# - esto es FOV.
# - menor FOV = más zoom in.
# - valores recomendados: 45.0, 40.0, 35.0.
#
# Si tu cámara es Orthogonal:
# - esto es Size.
# - menor Size = más zoom in.
@export var camera_zoom_value: float = 28.0

# Duración del zoom in.
@export_range(0.0, 3.0, 0.01) var camera_zoom_duration: float = 0.45

# Duración del zoom out / restore.
@export_range(0.0, 3.0, 0.01) var camera_restore_duration: float = 0.45


# =========================================================
# CONFIGURACIÓN: DIÁLOGO DE PRUEBA
# =========================================================

# Activa/desactiva el diálogo dentro de esta cutscene de prueba.
@export var use_dialogue: bool = true

# Nombre del hablante.
@export var dialogue_speaker: String = "Rick"

# Texto del diálogo.
@export_multiline var dialogue_text: String = "Permite hacer un dash para escapar de los enemigos rápidamente. Esto ya está pasando por el CutsceneDirector."


# =========================================================
# CONFIGURACIÓN: TRIGGER
# =========================================================

# Si está activo, el trigger solo se puede usar una vez.
@export var trigger_once: bool = true

# Si está activo, la cutscene se dispara al entrar al Area3D.
@export var trigger_on_enter: bool = true

# Acción opcional de debug.
# Si existe en Input Map, podés disparar la cutscene con esa acción.
@export var debug_action: StringName = &"debug_cutscene"


# =========================================================
# ESTADO INTERNO
# =========================================================

var _is_running: bool = false
var _already_used: bool = false


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	body_entered.connect(_on_body_entered)

	var has_debug_action := debug_action != &"" and InputMap.has_action(debug_action)
	set_process_unhandled_input(has_debug_action)


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
	if not trigger_on_enter:
		return

	if _is_running:
		return

	if trigger_once and _already_used:
		return

	# Si player_path está configurado, solo aceptamos ese player.
	var configured_player := _get_configured_player()

	if configured_player != null:
		if body != configured_player:
			return

		run_cutscene(configured_player)
		return

	# Si no configuramos player_path, aceptamos bodies con API de cutscene.
	if body.has_method("set_cutscene_mode") and body.has_method("cutscene_walk_to"):
		run_cutscene(body)


# =========================================================
# CUTSCENE PRINCIPAL
# =========================================================

func run_cutscene(player_override: Node = null) -> void:
	if _is_running:
		return

	if trigger_once and _already_used:
		return

	var director := _resolve_director()
	var target_marker := _get_target_marker()
	var player := player_override

	if player == null:
		player = _get_configured_player()

	if director == null:
		push_warning("TestCutsceneTrigger: no se encontró CutsceneDirector.")
		return

	if target_marker == null:
		push_warning("TestCutsceneTrigger: no se encontró CutsceneTarget.")
		return

	if not director.has_method("begin"):
		push_warning("TestCutsceneTrigger: el director no tiene begin().")
		return

	if not director.has_method("walk_player_to"):
		push_warning("TestCutsceneTrigger: el director no tiene walk_player_to().")
		return

	if not director.has_method("wait_seconds"):
		push_warning("TestCutsceneTrigger: el director no tiene wait_seconds().")
		return

	if not director.has_method("end"):
		push_warning("TestCutsceneTrigger: el director no tiene end().")
		return

	if use_camera_zoom:
		if not director.has_method("camera_zoom_to"):
			push_warning("TestCutsceneTrigger: el director no tiene camera_zoom_to().")
			return

		if not director.has_method("camera_restore"):
			push_warning("TestCutsceneTrigger: el director no tiene camera_restore().")
			return

	if use_dialogue:
		if not director.has_method("say"):
			push_warning("TestCutsceneTrigger: el director no tiene say().")
			return

	_is_running = true
	_already_used = true

	# ---------------------------------------------------------
	# Inicio
	# ---------------------------------------------------------
	var started: bool = director.begin(player)

	if not started:
		_is_running = false
		_already_used = false
		return

	# Esperamos un frame para que Godot actualice visibilidad/procesos.
	await get_tree().process_frame

	if _should_abort_cutscene(director):
		_is_running = false
		return

	# ---------------------------------------------------------
	# Zoom in de cámara
	# ---------------------------------------------------------
	if use_camera_zoom:
		await director.camera_zoom_to(camera_zoom_value, camera_zoom_duration)

		if _should_abort_cutscene(director):
			_is_running = false
			return

	# ---------------------------------------------------------
	# Diálogo de prueba
	# ---------------------------------------------------------
	if use_dialogue and dialogue_text.strip_edges() != "":
		await director.say(dialogue_speaker, dialogue_text)

		if _should_abort_cutscene(director):
			_is_running = false
			return

	# ---------------------------------------------------------
	# Movimiento del actor
	# ---------------------------------------------------------
	await director.walk_player_to(target_marker.global_position, walk_speed)

	if _should_abort_cutscene(director):
		_is_running = false
		return

	# ---------------------------------------------------------
	# Pausa breve al llegar
	# ---------------------------------------------------------
	await director.wait_seconds(wait_after_arrival)

	if _should_abort_cutscene(director):
		_is_running = false
		return

	# ---------------------------------------------------------
	# Restaurar cámara
	# ---------------------------------------------------------
	if use_camera_zoom:
		await director.camera_restore(camera_restore_duration)

		if _should_abort_cutscene(director):
			_is_running = false
			return

	# ---------------------------------------------------------
	# Fin
	# ---------------------------------------------------------
	director.end()

	_is_running = false


# =========================================================
# HELPERS
# =========================================================

func _resolve_director() -> Node:
	# 1) Buscar por path configurado.
	if director_path != NodePath():
		var director_from_path := get_node_or_null(director_path)

		if director_from_path != null:
			return director_from_path

	# 2) Buscar por grupo.
	var grouped_director := get_tree().get_first_node_in_group("cutscene_director")

	if grouped_director != null:
		return grouped_director

	return null


func _get_configured_player() -> Node:
	if player_path == NodePath():
		return null

	return get_node_or_null(player_path)


func _get_target_marker() -> Marker3D:
	if target_marker_path == NodePath():
		return null

	return get_node_or_null(target_marker_path) as Marker3D


func _should_abort_cutscene(director: Node) -> bool:
	# Se usa después de cada await.
	#
	# Si durante ese await el jugador pidió skip, el director ya hizo
	# cancel(), restauró HUD/cámara/player/dialogue, y este trigger
	# tiene que dejar de ejecutar pasos viejos.
	if director == null:
		return true

	if director.has_method("was_skip_requested") and director.was_skip_requested():
		return true

	# El director tiene una variable pública is_running.
	# Si ya no está corriendo, significa que fue cancelado o terminado.
	if director.get("is_running") == false:
		return true

	return false
