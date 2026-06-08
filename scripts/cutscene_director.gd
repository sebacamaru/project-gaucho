extends Node
class_name CutsceneDirector

# =========================================================
# CUTSCENE DIRECTOR
# =========================================================
#
# Coordina cutscenes simples.
#
# Actualmente maneja:
# - iniciar / terminar cutscene
# - poner al Player en modo cutscene
# - mover al Player hasta una posición
# - esperar X segundos
# - ocultar / restaurar HUD
# - fade out / fade in suave del HUD
# - zoom smooth de cámara
# - restauración de cámara
# - diálogos mediante DialogueBox
# - skip / cancelación completa de cutscene
#
# Importante:
# En tu escena conviene ocultar solo:
#   HUD/CanvasLayer/UI
#   HUD/CanvasLayer/LevelUpPanel
#
# NO conviene ocultar todo HUD/CanvasLayer porque ahí también
# viven FX como FogOverlay, RetroShader, DamageRect, SapukaiEffect, etc.
#
# El DialogueBox debería estar fuera de UI, por ejemplo:
#
# HUD
# └── CanvasLayer
#     ├── FX
#     ├── UI
#     ├── LevelUpPanel
#     └── DialogueBox

# =========================================================
# COMANDOS DISPONIBLES:
# =========================================================

# {"type": "camera_zoom", "value": 28.0, "duration": 0.45}
# {"type": "camera_restore", "duration": 0.45}
# {"type": "say", "speaker": "Rick", "text": "Texto del diálogo.", "close_after": true}
# {"type": "say_many", "lines": [{"speaker": "Rick", "text": "Primera línea."}, {"speaker": "Gaucho", "text": "Segunda línea."}]}
# {"type": "wait", "seconds": 0.5}
# {"type": "walk_player_to_marker", "marker_path": ^"CutsceneTarget", "speed": 2.5}
# {"type": "walk_player_to_marker", "marker": $CutsceneTarget, "speed": 2.5}
# {"type": "walk_player_to_position", "position": Vector3(4.0, 0.0, 8.0), "speed": 2.5}
# {"type": "player_anim", "anim": "Idle"}
# {"type": "play_player_anim", "animation": "Walk"}
# {"type": "player_face_direction", "direction": "left"}
# {"type": "face_player_direction", "direction": Vector3.RIGHT}
# "type": "close_dialogue"}
# "type": "start_survivor_level"}
# {"type": "play_sound", "sound_path": "res://sounds/radio_estatica.ogg"}
# {"type": "play_sound", "stream": preload("res://sounds/aullido.ogg"), "volume_db": -4.0, "wait_for_finish": true}
# {"type": "play_sound", "sound_path": "res://sounds/golpe.ogg", "volume_pct": 70}
# {"type": "play_loop", "id": "ambiente", "sound_path": "res://sounds/viento.ogg", "volume_db": -8.0, "fade_in": 1.5}
# {"type": "set_loop_volume", "id": "ambiente", "volume_pct": 100, "fade": 0.8}
# {"type": "stop_loop", "id": "ambiente", "fade_out": 1.0}
#
# Volumen: todos los comandos de audio aceptan volume_db (decibeles, 0 = original)
# o, como alternativa, volume_pct (porcentaje lineal: 100 = original, 50 ≈ mitad, 200 = doble).

# =========================================================
# CONFIGURACIÓN: PLAYER
# =========================================================

@export var player_path: NodePath
@export var player_group: StringName = &"player"

# Si está activo, evita que se dispare otra cutscene mientras hay una corriendo.
@export var prevent_overlap: bool = true

# Debug.
@export var print_debug: bool = true


# =========================================================
# CONFIGURACIÓN: HUD
# =========================================================

# Si está activo, el director oculta HUD al hacer begin()
# y lo restaura al hacer end() o cancel().
@export var auto_hide_hud: bool = true

# Si está activo, el HUD se oculta/muestra con fade suave.
# Si está apagado, vuelve al comportamiento instantáneo.
@export var use_hud_fade: bool = true

# Duración del fade out al empezar la cutscene.
@export_range(0.0, 2.0, 0.01) var hud_fade_out_duration: float = 0.25

# Duración del fade in al terminar la cutscene.
@export_range(0.0, 2.0, 0.01) var hud_fade_in_duration: float = 0.25

# Tipo de transición del tween.
@export var hud_fade_trans: Tween.TransitionType = Tween.TRANS_SINE

# Tipo de easing del tween.
@export var hud_fade_ease: Tween.EaseType = Tween.EASE_OUT

# Nodos específicos del HUD que queremos ocultar.
#
# En tu caso, desde un CutsceneDirector que está como hermano de HUD,
# los paths recomendados serían:
#
#   ../HUD/CanvasLayer/UI
#   ../HUD/CanvasLayer/LevelUpPanel
#
# Podés asignarlos desde el Inspector.
@export var hud_nodes_to_hide: Array[NodePath] = []

# Grupo opcional.
# Si agregás nodos al grupo "cutscene_hud", también los oculta/restaura.
@export var hud_group: StringName = &"cutscene_hud"


# =========================================================
# CONFIGURACIÓN: CÁMARA
# =========================================================

# Cámara usada para cutscenes.
# Podés asignarla a mano desde el Inspector.
@export var camera_path: NodePath

# Si camera_path está vacío, busca una cámara en este grupo.
# En tu caso tu Camera3D ya está en el grupo "camera".
@export var camera_group: StringName = &"camera"

# Si está activo, al iniciar la cutscene guarda los valores originales
# de la cámara para poder restaurarlos después.
@export var auto_store_camera_state: bool = true

# Duración default para zooms de cámara.
@export_range(0.0, 3.0, 0.01) var camera_default_zoom_duration: float = 0.45

# Transición del tween de cámara.
@export var camera_zoom_trans: Tween.TransitionType = Tween.TRANS_SINE

# Ease del tween de cámara.
@export var camera_zoom_ease: Tween.EaseType = Tween.EASE_OUT


# =========================================================
# CONFIGURACIÓN: DIÁLOGOS
# =========================================================

# DialogueBox usado por las cutscenes.
# Podés asignarlo a mano desde el Inspector.
#
# Path recomendado si el CutsceneDirector está como hermano de HUD:
#   ../HUD/CanvasLayer/DialogueBox
@export var dialogue_box_path: NodePath

# Si dialogue_box_path está vacío, intenta encontrarlo por grupo.
# Recomendado: poner el DialogueBox en el grupo "dialogue_box".
@export var dialogue_box_group: StringName = &"dialogue_box"

# Si está activo, el director intenta cerrar el DialogueBox al terminar
# o cancelar una cutscene, por seguridad.
@export var auto_close_dialogue_on_end: bool = true


# =========================================================
# CONFIGURACIÓN: SKIP
# =========================================================

# Permite saltear/cancelar la cutscene completa con input.
@export var allow_skip: bool = true

# Acciones que cancelan la cutscene.
#
# Recomendación:
# - ui_cancel suele ser Escape.
# - skip_cutscene podés crearla vos en Input Map.
#
# Evitamos usar ui_accept porque el DialogueBox lo usa para avanzar texto.
@export var skip_actions: Array[StringName] = [
	&"ui_cancel",
	&"skip_cutscene"
]

# Si se cancela la cutscene, restaura la cámara instantáneamente.
@export var restore_camera_on_cancel: bool = true


# =========================================================
# CONFIGURACIÓN: SURVIVOR MODE
# =========================================================

@export var survivor_manager_path: NodePath
@export var survivor_manager_group: StringName = &"survivor_mode_manager"


# =========================================================
# ESTADO INTERNO
# =========================================================

var is_running: bool = false
var current_player: Node = null

# Cámara actual usada por la cutscene.
var current_camera: Camera3D = null

# DialogueBox actual usado por la cutscene.
var current_dialogue_box: Node = null

# True cuando el usuario pidió saltear/cancelar la cutscene.
var _skip_requested: bool = false

# Loops de audio de fondo activos (música/ambiente del nivel).
#
# Mapea id (String) -> AudioStreamPlayer.
#
# Estos players viven como hijos del director, NO se limpian al terminar
# una cutscene ni con el skip, así que persisten todo el nivel hasta que
# alguien llame stop_loop.
var _active_loops: Dictionary = {}

# Guarda el estado original de cada nodo del HUD.
#
# Guardamos:
# - visible original
# - alpha original
#
# Esto evita bugs tipo:
# - LevelUpPanel estaba oculto antes de la cutscene y aparece al terminar.
# - Algún nodo tenía alpha distinto de 1 y queda mal restaurado.
var _stored_hud_state: Dictionary = {}

# Tween actual del fade del HUD.
# Lo guardamos para poder cancelarlo si hace falta.
var _hud_fade_tween: Tween = null

# Estado original de la cámara para restaurar al final.
#
# Guardamos:
# - projection
# - fov
# - size
var _stored_camera_state: Dictionary = {}

# Tween actual de cámara.
var _camera_tween: Tween = null

# Señal interna para destrabar waits de cámara si el tween se corta por skip.
var _camera_action_waiting: bool = false


# =========================================================
# SEÑALES
# =========================================================

signal cutscene_started
signal cutscene_finished
signal cutscene_skip_requested
signal camera_action_completed


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	# Nos agregamos a un grupo para que otros nodos puedan encontrar
	# al director sin tener que asignar path manualmente.
	add_to_group("cutscene_director")

	# Solo procesamos input de skip mientras hay una cutscene activa.
	set_process_unhandled_input(false)


# =========================================================
# API PRINCIPAL
# =========================================================

func begin(player_override: Node = null) -> bool:
	# Si ya hay una cutscene corriendo, evitamos superponer otra.
	if is_running and prevent_overlap:
		if print_debug:
			print("CutsceneDirector: ya hay una cutscene corriendo.")
		return false

	var player := player_override

	if player == null:
		player = _resolve_player()

	if player == null:
		push_warning("CutsceneDirector: no se encontró Player.")
		return false

	if not player.has_method("set_cutscene_mode"):
		push_warning("CutsceneDirector: el Player no tiene set_cutscene_mode().")
		return false

	current_player = player
	is_running = true
	_skip_requested = false

	# Activamos input de skip solo durante cutscene.
	if allow_skip:
		set_process_unhandled_input(true)

	# Resolución/guardado de cámara.
	current_camera = _resolve_camera()

	if auto_store_camera_state:
		_store_camera_state()

	# Resolución del DialogueBox.
	# No es obligatorio tenerlo para todas las cutscenes.
	current_dialogue_box = _resolve_dialogue_box()

	# Ocultamos HUD antes de activar el modo cutscene.
	#
	# Con fade, esto arranca el tween.
	# No esperamos a que termine para que la cutscene pueda empezar fluida.
	if auto_hide_hud:
		hide_hud()

	# Activamos modo cutscene en el player.
	current_player.set_cutscene_mode(true)

	cutscene_started.emit()

	if print_debug:
		print("CutsceneDirector: begin")

	return true


func end() -> void:
	# Dejamos de escuchar input de skip.
	set_process_unhandled_input(false)

	# Cerramos el diálogo por seguridad.
	# Normalmente cada say() ya cierra si close_after = true,
	# pero esto evita que quede abierto si alguna línea usó close_after = false.
	if auto_close_dialogue_on_end:
		_force_close_dialogue_box()

	# Restauramos Player.
	if current_player != null and current_player.has_method("set_cutscene_mode"):
		current_player.set_cutscene_mode(false)

	current_player = null
	is_running = false

	# Restauramos HUD al estado que tenía antes de la cutscene.
	#
	# Con fade, esto arranca el fade in.
	if auto_hide_hud:
		show_hud()

	# Limpiamos referencias.
	#
	# Nota:
	# La cámara se restaura llamando explícitamente a camera_restore()
	# antes de end(), así cada cutscene controla cuándo volver.
	current_camera = null
	current_dialogue_box = null
	_stored_camera_state.clear()

	cutscene_finished.emit()

	if print_debug:
		print("CutsceneDirector: end")


func cancel(mark_as_skipped: bool = true) -> void:
	# Cancelación completa de cutscene.
	#
	# Debe dejar sano:
	# - Player
	# - DialogueBox
	# - cámara
	# - HUD
	# - awaits pendientes
	if mark_as_skipped:
		_skip_requested = true

	# Dejamos de escuchar input de skip.
	set_process_unhandled_input(false)

	# Frenamos al Player como actor de cutscene.
	if current_player != null:
		if current_player.has_method("cutscene_stop_walk"):
			current_player.cutscene_stop_walk()

		if current_player.has_method("set_cutscene_mode"):
			current_player.set_cutscene_mode(false)

	current_player = null
	is_running = false

	# Cerramos diálogo instantáneo para que no quede colgado.
	_force_close_dialogue_box()

	# Cortamos tween de cámara si había uno activo.
	_kill_camera_tween()

	# Restauramos cámara instantáneamente si hay estado guardado.
	if restore_camera_on_cancel:
		_restore_camera_instant()

	# Aunque se cancele, restauramos el HUD.
	if auto_hide_hud:
		show_hud()

	current_camera = null
	current_dialogue_box = null
	_stored_camera_state.clear()

	cutscene_finished.emit()

	if print_debug:
		print("CutsceneDirector: cancel")


# =========================================================
# SKIP / CANCELACIÓN
# =========================================================

func _unhandled_input(event: InputEvent) -> void:
	if not is_running:
		return

	if not allow_skip:
		return

	if _is_skip_event(event):
		get_viewport().set_input_as_handled()
		request_skip()


func _is_skip_event(event: InputEvent) -> bool:
	for action in skip_actions:
		if action == &"":
			continue

		if not InputMap.has_action(action):
			continue

		if event.is_action_pressed(action):
			return true

	return false


func request_skip() -> void:
	# Evita procesar skip dos veces.
	if _skip_requested:
		return

	if not is_running:
		return

	_skip_requested = true
	cutscene_skip_requested.emit()

	if print_debug:
		print("CutsceneDirector: skip solicitado")

	cancel(true)


func was_skip_requested() -> bool:
	return _skip_requested


# =========================================================
# ACCIONES DE CUTSCENE: PLAYER
# =========================================================

func walk_player_to(target_position: Vector3, walk_speed: float = 2.5) -> void:
	if _skip_requested:
		return

	if not _has_valid_running_player():
		return

	if not current_player.has_method("cutscene_walk_to"):
		push_warning("CutsceneDirector: el Player no tiene cutscene_walk_to().")
		return

	await current_player.cutscene_walk_to(target_position, walk_speed)


func player_play_anim(anim_name: String) -> void:
	if _skip_requested:
		return

	if not _has_valid_running_player():
		return

	if current_player.has_method("cutscene_play_anim"):
		current_player.cutscene_play_anim(anim_name)


func player_face_direction(direction: Vector3) -> void:
	if _skip_requested:
		return

	if not _has_valid_running_player():
		return

	if current_player.has_method("cutscene_face_direction"):
		current_player.cutscene_face_direction(direction)


func wait_seconds(seconds: float) -> void:
	# Wait cancelable.
	# Evitamos create_timer().timeout porque si se pide skip,
	# queremos poder cortar inmediatamente en el próximo frame.
	if seconds <= 0.0:
		return

	var elapsed := 0.0

	while elapsed < seconds:
		if _skip_requested:
			return

		if not is_running:
			return

		await get_tree().process_frame
		elapsed += get_process_delta_time()


# =========================================================
# ACCIONES DE CUTSCENE: COMANDOS
# =========================================================
#
# Este bloque permite ejecutar cutscenes como una lista de comandos.
#
# Ejemplo:
#
# await director.run_commands(player, [
#	{"type": "camera_zoom", "value": 28.0, "duration": 0.45},
#	{"type": "say", "speaker": "Rick", "text": "Texto..."},
#	{"type": "walk_player_to_marker", "marker": $CutsceneTarget, "speed": 2.5},
#	{"type": "wait", "seconds": 0.35},
#	{"type": "camera_restore", "duration": 0.45}
# ], self)
#
# La idea:
# - El director hace begin()
# - Ejecuta cada comando
# - Si hay skip/cancel, corta
# - Si todo terminó bien, hace end()
# =========================================================

func run_commands(
	player_override: Node,
	commands: Array,
	command_owner: Node = null,
	auto_begin: bool = true,
	auto_end: bool = true
) -> bool:
	if commands.is_empty():
		push_warning("CutsceneDirector: run_commands() recibió una lista vacía.")
		return false

	# ---------------------------------------------------------
	# Inicio automático de cutscene
	# ---------------------------------------------------------
	if auto_begin:
		var started: bool = begin(player_override)

		if not started:
			return false

		# Esperamos un frame para que Godot actualice:
		# - visibilidad del HUD
		# - modo cutscene del player
		# - cámara activa
		# - DialogueBox
		await get_tree().process_frame

	# ---------------------------------------------------------
	# Ejecución de comandos
	# ---------------------------------------------------------
	for command in commands:
		if _commands_should_abort():
			return false

		await _run_cutscene_command(command, command_owner)

		if _commands_should_abort():
			return false

	# ---------------------------------------------------------
	# Fin automático
	# ---------------------------------------------------------
	if auto_end and is_running:
		end()

	return true


func _run_cutscene_command(command_data: Variant, command_owner: Node = null) -> void:
	if typeof(command_data) != TYPE_DICTIONARY:
		push_warning("CutsceneDirector: comando inválido. Se esperaba Dictionary.")
		return

	var command: Dictionary = command_data
	var type: String = str(command.get("type", "")).strip_edges().to_lower()

	match type:
		"camera_zoom":
			await _command_camera_zoom(command)

		"camera_restore":
			await _command_camera_restore(command)

		"say":
			await _command_say(command)

		"say_many":
			await _command_say_many(command)

		"wait":
			await _command_wait(command)

		"walk_player_to_marker":
			await _command_walk_player_to_marker(command, command_owner)

		"walk_player_to_position":
			await _command_walk_player_to_position(command)

		"player_anim", "play_player_anim":
			_command_player_anim(command)

		"player_face_direction", "face_player_direction":
			_command_player_face_direction(command)

		"close_dialogue":
			await close_dialogue()
			
		"start_survivor_level":
			_command_start_survivor_level(command)

		"play_sound", "sound":
			await _command_play_sound(command)

		"play_loop":
			await _command_play_loop(command)

		"set_loop_volume":
			_command_set_loop_volume(command)

		"stop_loop":
			_command_stop_loop(command)

		_:
			push_warning("CutsceneDirector: tipo de comando desconocido: %s" % type)


func _commands_should_abort() -> bool:
	# Si tu director tiene skip completo implementado,
	# usamos was_skip_requested().
	if has_method("was_skip_requested"):
		var skipped: bool = bool(call("was_skip_requested"))

		if skipped:
			return true

	# Si el director dejó de correr, asumimos que fue cancelado
	# o terminado externamente.
	if not is_running:
		return true

	return false


# =========================================================
# COMMAND: CAMERA ZOOM
# =========================================================

func _command_camera_zoom(command: Dictionary) -> void:
	var zoom_value := _command_get_float(command, ["value", "zoom_value", "fov", "size"], 28.0)
	var duration := _command_get_float(command, ["duration", "time"], -1.0)

	await camera_zoom_to(zoom_value, duration)


# =========================================================
# COMMAND: CAMERA RESTORE
# =========================================================

func _command_camera_restore(command: Dictionary) -> void:
	var duration := _command_get_float(command, ["duration", "time"], -1.0)

	await camera_restore(duration)


# =========================================================
# COMMAND: SAY
# =========================================================

func _command_say(command: Dictionary) -> void:
	var speaker := str(command.get("speaker", ""))
	var text := str(command.get("text", ""))
	var close_after: bool = bool(command.get("close_after", true))

	if text.strip_edges() == "":
		return

	await say(speaker, text, close_after)


# =========================================================
# COMMAND: SAY MANY
# =========================================================

func _command_say_many(command: Dictionary) -> void:
	var lines: Array = command.get("lines", [])

	if lines.is_empty():
		return

	await say_many(lines)


# =========================================================
# COMMAND: WAIT
# =========================================================

func _command_wait(command: Dictionary) -> void:
	var seconds := _command_get_float(command, ["seconds", "duration", "time"], 0.0)

	if seconds <= 0.0:
		return

	await wait_seconds(seconds)


# =========================================================
# COMMAND: WALK PLAYER TO MARKER
# =========================================================

func _command_walk_player_to_marker(command: Dictionary, command_owner: Node = null) -> void:
	var target_node := _command_resolve_node3d(command, command_owner)

	if target_node == null:
		push_warning("CutsceneDirector: walk_player_to_marker no encontró target.")
		return

	var walk_speed := _command_get_float(command, ["speed", "walk_speed"], 2.5)

	await walk_player_to(target_node.global_position, walk_speed)


# =========================================================
# COMMAND: WALK PLAYER TO POSITION
# =========================================================

func _command_walk_player_to_position(command: Dictionary) -> void:
	var position_value = command.get("position", null)

	if not (position_value is Vector3):
		push_warning("CutsceneDirector: walk_player_to_position necesita position: Vector3.")
		return

	var walk_speed := _command_get_float(command, ["speed", "walk_speed"], 2.5)

	await walk_player_to(position_value, walk_speed)


# =========================================================
# COMMAND: PLAYER ANIM
# =========================================================

func _command_player_anim(command: Dictionary) -> void:
	var anim_name := str(command.get("anim", command.get("animation", ""))).strip_edges()

	if anim_name == "":
		return

	player_play_anim(anim_name)


# =========================================================
# COMMAND: PLAYER FACE DIRECTION
# =========================================================

func _command_player_face_direction(command: Dictionary) -> void:
	var direction_value = command.get("direction", Vector3.ZERO)
	var direction := _command_parse_direction(direction_value)

	if direction.length_squared() <= 0.0001:
		return

	player_face_direction(direction)


# =========================================================
# COMMAND: START SURVIVOR MODE
# =========================================================

func _command_start_survivor_level(command: Dictionary) -> void:
	var survivor_manager := _resolve_survivor_manager()

	if survivor_manager == null:
		push_warning("CutsceneDirector: no se encontró SurvivorModeManager.")
		return

	if not survivor_manager.has_method("start_level"):
		push_warning("CutsceneDirector: SurvivorModeManager no tiene start_level().")
		return

	var duration: float = float(command.get("duration", -1.0))

	print("")
	print("========== DEBUG START SURVIVOR LEVEL ==========")
	print("CutsceneDirector path: ", get_path())
	print("Command recibido: ", command)
	print("Duration leído del command: ", duration)
	print("SurvivorManager encontrado: ", survivor_manager.get_path())
	print("SurvivorManager script: ", survivor_manager.get_script())
	print("================================================")
	print("")

	# IMPORTANTE:
	# Como sacaste level del SurvivorModeManager,
	# ahora llamamos SOLO con duration.
	survivor_manager.start_level(duration)


func _resolve_survivor_manager() -> Node:
	if survivor_manager_path != NodePath():
		var manager_from_path := get_node_or_null(survivor_manager_path)

		if manager_from_path != null:
			return manager_from_path

	if survivor_manager_group != &"":
		var grouped_manager := get_tree().get_first_node_in_group(survivor_manager_group)

		if grouped_manager != null:
			return grouped_manager

	return null


# =========================================================
# COMMAND: PLAY SOUND
# =========================================================

# Reproduce un sonido durante la cutscene. Acepta un AudioStream precargado
# (stream/sound) o una ruta res:// (stream_path/sound_path/path). El volumen
# se setea con volume_db o volume_pct (porcentaje, ver _command_get_volume_db).
# Si wait_for_finish es true, la cutscene espera (cancelable) a que termine.
func _command_play_sound(command: Dictionary) -> void:
	if _skip_requested:
		return

	var stream := _command_resolve_audio_stream(command)

	if stream == null:
		push_warning("CutsceneDirector: play_sound no pudo resolver el stream.")
		return

	var volume_db := _command_get_volume_db(command, 0.0)
	var pitch := _command_get_float(command, ["pitch", "pitch_scale"], 1.0)
	var bus := str(command.get("bus", "Master"))
	var wait_for_finish: bool = bool(command.get("wait_for_finish", command.get("wait", false)))

	var sfx := AudioStreamPlayer.new()
	sfx.stream = stream
	sfx.volume_db = volume_db
	sfx.pitch_scale = pitch
	sfx.bus = bus
	sfx.process_mode = Node.PROCESS_MODE_ALWAYS  # suena aunque el árbol se pause
	add_child(sfx)
	sfx.play()

	if not wait_for_finish:
		# Fire-and-forget: se libera solo al terminar.
		sfx.finished.connect(sfx.queue_free)
		return

	# Espera cancelable, mismo patrón que wait_seconds().
	while is_instance_valid(sfx) and sfx.playing:
		if _skip_requested or not is_running:
			break

		await get_tree().process_frame

	if is_instance_valid(sfx):
		sfx.stop()
		sfx.queue_free()


# =========================================================
# COMMAND: PLAY LOOP (música / ambiente de nivel)
# =========================================================
#
# A diferencia de play_sound, el loop queda guardado por "id" y persiste
# todo el nivel (sobrevive a cutscenes y al skip). Lo controlás después con
# set_loop_volume y stop_loop usando el mismo id.
#
# Ejemplos:
#
#   # Arrancar ambiente de fondo con fade in de 1.5s
#   {"type": "play_loop", "id": "ambiente", "sound_path": "res://sounds/viento.ogg",
#    "volume_db": -8.0, "fade_in": 1.5}
#
#   # Música con stream precargado, a media potencia (volumen por porcentaje)
#   {"type": "play_loop", "id": "musica", "stream": preload("res://sounds/tema_nivel.ogg"), "volume_pct": 50}
#
#   # Por defecto, si el id ya está sonando NO se reinicia (evita cortes si la
#   # cutscene se re-dispara). Pasá "replace": true para forzar el reemplazo.
#   {"type": "play_loop", "id": "musica", "sound_path": "res://sounds/otro_tema.ogg", "replace": true}

# Arranca un loop de fondo identificado por "id". Acepta los mismos parámetros
# de audio que play_sound (stream/sound_path, volume_db, pitch, bus) más
# fade_in (segundos) y replace (bool). Si el id ya existe y replace es false,
# no hace nada para no cortar el audio en curso.
func _command_play_loop(command: Dictionary) -> void:
	var id := str(command.get("id", "default")).strip_edges()

	if id == "":
		push_warning("CutsceneDirector: play_loop necesita un id.")
		return

	var replace: bool = bool(command.get("replace", false))

	# Si ya hay un loop con ese id sonando y no se pidió reemplazar, lo dejamos.
	if _active_loops.has(id) and is_instance_valid(_active_loops[id]):
		if not replace:
			return

		_stop_loop_player(id, 0.0)

	var stream := _command_resolve_audio_stream(command)

	if stream == null:
		push_warning("CutsceneDirector: play_loop no pudo resolver el stream.")
		return

	var volume_db := _command_get_volume_db(command, 0.0)
	var pitch := _command_get_float(command, ["pitch", "pitch_scale"], 1.0)
	var bus := str(command.get("bus", "Master"))
	var fade_in := _command_get_float(command, ["fade_in", "fade"], 0.0)

	# Forzamos loop sobre una COPIA del stream para no mutar el recurso cacheado
	# (que podría usarse en otros sonidos).
	var loop_stream := _make_stream_looping(stream)

	var player := AudioStreamPlayer.new()
	player.stream = loop_stream
	player.pitch_scale = pitch
	player.bus = bus
	player.process_mode = Node.PROCESS_MODE_ALWAYS  # sigue sonando aunque el árbol se pause
	add_child(player)

	_active_loops[id] = player

	if fade_in > 0.0:
		# Arranca en silencio y sube al volumen objetivo.
		player.volume_db = -60.0
		player.play()

		var tween := create_tween()
		tween.tween_property(player, "volume_db", volume_db, fade_in)
	else:
		player.volume_db = volume_db
		player.play()


# =========================================================
# COMMAND: SET LOOP VOLUME
# =========================================================
#
# Cambia el volumen de un loop activo, con fade opcional.
#
# Ejemplos:
#
#   # Subir el ambiente de golpe
#   {"type": "set_loop_volume", "id": "ambiente", "volume_db": 0.0}
#
#   # Bajar la música suavemente en 0.8s
#   {"type": "set_loop_volume", "id": "musica", "volume_db": -12.0, "fade": 0.8}
#
#   # Mismo control pero por porcentaje (25% del volumen original)
#   {"type": "set_loop_volume", "id": "musica", "volume_pct": 25, "fade": 0.8}

# Ajusta el volumen de un loop activo identificado por "id", vía volume_db o
# volume_pct (porcentaje). Si fade > 0, hace la transición con un tween; si no,
# el cambio es instantáneo.
func _command_set_loop_volume(command: Dictionary) -> void:
	var id := str(command.get("id", "default")).strip_edges()

	if not _active_loops.has(id) or not is_instance_valid(_active_loops[id]):
		push_warning("CutsceneDirector: set_loop_volume no encontró el loop '%s'." % id)
		return

	var player: AudioStreamPlayer = _active_loops[id]
	var volume_db := _command_get_volume_db(command, 0.0)
	var fade := _command_get_float(command, ["fade", "duration"], 0.0)

	if fade > 0.0:
		var tween := create_tween()
		tween.tween_property(player, "volume_db", volume_db, fade)
	else:
		player.volume_db = volume_db


# =========================================================
# COMMAND: STOP LOOP
# =========================================================
#
# Para un loop activo, con fade out opcional.
#
# Ejemplos:
#
#   # Cortar el ambiente de una
#   {"type": "stop_loop", "id": "ambiente"}
#
#   # Apagar la música con fade out de 1s
#   {"type": "stop_loop", "id": "musica", "fade_out": 1.0}

# Detiene y libera el loop identificado por "id", con fade out opcional.
func _command_stop_loop(command: Dictionary) -> void:
	var id := str(command.get("id", "default")).strip_edges()
	var fade_out := _command_get_float(command, ["fade_out", "fade", "duration"], 0.0)

	_stop_loop_player(id, fade_out)


# Helper interno: para el player de un loop por id y lo saca del registro.
# Con fade_out > 0 baja el volumen y recién ahí lo libera.
func _stop_loop_player(id: String, fade_out: float) -> void:
	if not _active_loops.has(id):
		return

	var player = _active_loops[id]
	_active_loops.erase(id)

	if not is_instance_valid(player):
		return

	if fade_out > 0.0:
		var tween := create_tween()
		tween.tween_property(player, "volume_db", -60.0, fade_out)
		tween.tween_callback(player.queue_free)
	else:
		player.stop()
		player.queue_free()


# =========================================================
# COMMAND HELPERS
# =========================================================

func _command_get_float(command: Dictionary, keys: Array, default_value: float) -> float:
	for key in keys:
		if command.has(key):
			return float(command[key])

	return default_value


# Resuelve el volumen en dB de un comando de audio. Acepta dos formas:
#   - volume_db / volume: decibeles directos (0 = original, negativos bajan).
#   - volume_pct / volume_percent: porcentaje lineal (100 = volumen original,
#     50 ≈ mitad, 200 = doble). Se convierte a dB con linear_to_db().
# El porcentaje tiene prioridad si está presente. 0% o menos = silencio.
func _command_get_volume_db(command: Dictionary, default_db: float) -> float:
	for key in ["volume_pct", "volume_percent", "volume_percentage"]:
		if command.has(key):
			var pct := float(command[key])
			if pct <= 0.0:
				return -80.0  # silencio

			return linear_to_db(pct / 100.0)

	return _command_get_float(command, ["volume_db", "volume"], default_db)


# Resuelve el AudioStream de un comando play_sound: acepta un recurso ya
# cargado (stream/sound) o una ruta res:// que se carga con load().
func _command_resolve_audio_stream(command: Dictionary) -> AudioStream:
	for key in ["stream", "sound", "audio"]:
		var v = command.get(key, null)
		if v is AudioStream:
			return v

	for key in ["stream_path", "sound_path", "path"]:
		if command.has(key):
			var p := str(command[key]).strip_edges()
			if p != "" and ResourceLoader.exists(p):
				var res = load(p)
				if res is AudioStream:
					return res

	return null


# Devuelve una COPIA del stream con el loop activado, según su tipo
# (loop_mode en WAV, propiedad loop en Ogg/MP3). Trabajamos sobre una copia
# para no mutar el recurso cacheado, que puede compartirse con otros sonidos.
func _make_stream_looping(stream: AudioStream) -> AudioStream:
	if stream == null:
		return stream

	var copy: AudioStream = stream.duplicate()

	if copy is AudioStreamWAV:
		(copy as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif "loop" in copy:
		copy.set("loop", true)

	return copy


func _command_resolve_node3d(command: Dictionary, command_owner: Node = null) -> Node3D:
	# Formas soportadas:
	#
	# {"marker": $CutsceneTarget}
	# {"target": $CutsceneTarget}
	# {"node": $CutsceneTarget}
	# {"marker_path": ^"CutsceneTarget"}
	# {"target_path": ^"../Markers/Target"}
	#
	# Si usás NodePath, se resuelve relativo al command_owner.
	# En general, command_owner será el CutsceneEvent.

	var node_value = null

	if command.has("marker"):
		node_value = command["marker"]
	elif command.has("target"):
		node_value = command["target"]
	elif command.has("node"):
		node_value = command["node"]

	if node_value is Node3D:
		return node_value

	if node_value is NodePath:
		return _command_get_node3d_from_path(node_value, command_owner)

	if typeof(node_value) == TYPE_STRING:
		return _command_get_node3d_from_path(NodePath(node_value), command_owner)

	var path_value = null

	if command.has("marker_path"):
		path_value = command["marker_path"]
	elif command.has("target_path"):
		path_value = command["target_path"]
	elif command.has("node_path"):
		path_value = command["node_path"]

	if path_value is NodePath:
		return _command_get_node3d_from_path(path_value, command_owner)

	if typeof(path_value) == TYPE_STRING:
		return _command_get_node3d_from_path(NodePath(path_value), command_owner)

	return null


func _command_get_node3d_from_path(path: NodePath, command_owner: Node = null) -> Node3D:
	if path == NodePath():
		return null

	if command_owner != null:
		var node_from_owner := command_owner.get_node_or_null(path) as Node3D

		if node_from_owner != null:
			return node_from_owner

	var node_from_director := get_node_or_null(path) as Node3D

	if node_from_director != null:
		return node_from_director

	return null


func _command_parse_direction(value: Variant) -> Vector3:
	if value is Vector3:
		return value.normalized()

	var text := str(value).strip_edges().to_lower()

	match text:
		"left", "izquierda":
			return Vector3.LEFT
		"right", "derecha":
			return Vector3.RIGHT
		"up", "arriba", "forward":
			return Vector3.FORWARD
		"down", "abajo", "back":
			return Vector3.BACK

	return Vector3.ZERO


# =========================================================
# ACCIONES DE CUTSCENE: DIÁLOGO
# =========================================================

func say(speaker: String, text: String, close_after: bool = true) -> void:
	# Muestra una línea de diálogo usando el DialogueBox.
	#
	# Uso:
	#   await director.say("Gaucho", "La noche está rara...")
	#
	# Si close_after = false, la caja queda abierta para encadenar
	# otra línea sin fade out/in entre medio.
	if _skip_requested:
		return

	if current_dialogue_box == null:
		current_dialogue_box = _resolve_dialogue_box()

	if current_dialogue_box == null:
		push_warning("CutsceneDirector: no se encontró DialogueBox.")
		return

	if not current_dialogue_box.has_method("say"):
		push_warning("CutsceneDirector: DialogueBox no tiene say().")
		return

	await current_dialogue_box.say(speaker, text, close_after)


func say_many(lines: Array) -> void:
	# Permite ejecutar varias líneas seguidas.
	#
	# Formato esperado:
	#
	# [
	#   {"speaker": "Gaucho", "text": "La noche está rara..."},
	#   {"speaker": "Narrador", "text": "El viento se detuvo."}
	# ]
	#
	# Por defecto:
	# - las líneas intermedias NO cierran la caja
	# - la última sí la cierra
	for i in range(lines.size()):
		if _skip_requested:
			return

		var line = lines[i]

		if typeof(line) != TYPE_DICTIONARY:
			continue

		var speaker: String = str(line.get("speaker", ""))
		var text: String = str(line.get("text", ""))
		var is_last := i == lines.size() - 1
		var close_after: bool = line.get("close_after", is_last)

		await say(speaker, text, close_after)


func close_dialogue() -> void:
	# Cierra el DialogueBox de forma animada, si tiene close_box().
	if current_dialogue_box == null:
		current_dialogue_box = _resolve_dialogue_box()

	if current_dialogue_box == null:
		return

	if current_dialogue_box.has_method("close_box"):
		await current_dialogue_box.close_box()
		return

	if current_dialogue_box.has_method("force_close"):
		current_dialogue_box.force_close()


func _force_close_dialogue_box() -> void:
	# Cierre instantáneo.
	# Ideal para end/cancel/skip.
	if current_dialogue_box == null:
		current_dialogue_box = _resolve_dialogue_box()

	if current_dialogue_box == null:
		return

	if current_dialogue_box.has_method("force_close"):
		current_dialogue_box.force_close()
		return

	if current_dialogue_box.has_method("hide"):
		current_dialogue_box.call("hide")


func _resolve_dialogue_box() -> Node:
	# 1) Buscar por path configurado.
	if dialogue_box_path != NodePath():
		var dialogue_from_path := get_node_or_null(dialogue_box_path)

		if dialogue_from_path != null:
			return dialogue_from_path

	# 2) Buscar por grupo.
	if dialogue_box_group != &"":
		var grouped_dialogue := get_tree().get_first_node_in_group(dialogue_box_group)

		if grouped_dialogue != null:
			return grouped_dialogue

	# 3) Fallback específico para tu estructura actual.
	#
	# Esto asume que CutsceneDirector está como hermano de HUD.
	var common_dialogue := get_node_or_null("../HUD/CanvasLayer/DialogueBox")

	if common_dialogue != null:
		return common_dialogue

	return null


# =========================================================
# ACCIONES DE CUTSCENE: CÁMARA
# =========================================================

func camera_zoom_to(target_value: float, duration: float = -1.0) -> void:
	# target_value significa:
	#
	# - Si la cámara está en Perspective:
	#   target_value = FOV.
	#   Menor FOV = más zoom in.
	#
	# - Si la cámara está en Orthogonal:
	#   target_value = Size.
	#   Menor Size = más zoom in.
	if _skip_requested:
		return

	if current_camera == null:
		current_camera = _resolve_camera()

	if current_camera == null:
		push_warning("CutsceneDirector: no se encontró Camera3D.")
		return

	if duration < 0.0:
		duration = camera_default_zoom_duration

	# Si todavía no guardamos estado, lo guardamos acá.
	# Esto hace que camera_zoom_to() funcione incluso si no se llamó begin().
	_store_camera_state()

	_kill_camera_tween()

	# Si duration es 0, aplicamos instantáneo.
	if duration <= 0.0:
		if current_camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			current_camera.size = target_value
		else:
			current_camera.fov = target_value
		return

	_camera_action_waiting = true
	_camera_tween = create_tween()
	_camera_tween.set_trans(camera_zoom_trans)
	_camera_tween.set_ease(camera_zoom_ease)
	_camera_tween.finished.connect(_finish_camera_action)

	if current_camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_camera_tween.tween_property(current_camera, "size", target_value, duration)
	else:
		_camera_tween.tween_property(current_camera, "fov", target_value, duration)

	await camera_action_completed

	if _skip_requested:
		return

	_camera_tween = null


func camera_restore(duration: float = -1.0) -> void:
	if _skip_requested:
		return

	if current_camera == null:
		current_camera = _resolve_camera()

	if current_camera == null:
		return

	if _stored_camera_state.is_empty():
		return

	if duration < 0.0:
		duration = camera_default_zoom_duration

	_kill_camera_tween()

	var original_projection: int = _stored_camera_state.get("projection", current_camera.projection)
	var original_fov: float = _stored_camera_state.get("fov", current_camera.fov)
	var original_size: float = _stored_camera_state.get("size", current_camera.size)

	# Restauramos la proyección original por seguridad.
	current_camera.projection = original_projection

	# Si duration es 0, restauramos instantáneo.
	if duration <= 0.0:
		current_camera.fov = original_fov
		current_camera.size = original_size
		return

	_camera_action_waiting = true
	_camera_tween = create_tween()
	_camera_tween.set_trans(camera_zoom_trans)
	_camera_tween.set_ease(camera_zoom_ease)
	_camera_tween.finished.connect(_finish_camera_action)

	if current_camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_camera_tween.tween_property(current_camera, "size", original_size, duration)
	else:
		_camera_tween.tween_property(current_camera, "fov", original_fov, duration)

	await camera_action_completed

	if _skip_requested:
		return

	_camera_tween = null


func _finish_camera_action() -> void:
	if not _camera_action_waiting:
		return

	_camera_action_waiting = false
	camera_action_completed.emit()


func _store_camera_state() -> void:
	if current_camera == null:
		current_camera = _resolve_camera()

	if current_camera == null:
		return

	# Guardamos solo una vez por cutscene.
	# Así camera_restore() vuelve al valor original real,
	# no al último zoom intermedio.
	if not _stored_camera_state.is_empty():
		return

	_stored_camera_state = {
		"projection": current_camera.projection,
		"fov": current_camera.fov,
		"size": current_camera.size
	}


func _restore_camera_instant() -> void:
	if current_camera == null:
		current_camera = _resolve_camera()

	if current_camera == null:
		return

	if _stored_camera_state.is_empty():
		return

	var original_projection: int = _stored_camera_state.get("projection", current_camera.projection)
	var original_fov: float = _stored_camera_state.get("fov", current_camera.fov)
	var original_size: float = _stored_camera_state.get("size", current_camera.size)

	current_camera.projection = original_projection
	current_camera.fov = original_fov
	current_camera.size = original_size


func _resolve_camera() -> Camera3D:
	# 1) Buscar por path configurado.
	if camera_path != NodePath():
		var camera_from_path := get_node_or_null(camera_path) as Camera3D

		if camera_from_path != null:
			return camera_from_path

	# 2) Buscar por grupo.
	if camera_group != &"":
		var grouped_camera := get_tree().get_first_node_in_group(camera_group) as Camera3D

		if grouped_camera != null:
			return grouped_camera

	# 3) Último fallback: cámara activa del viewport.
	var viewport_camera := get_viewport().get_camera_3d()

	if viewport_camera != null:
		return viewport_camera

	return null


func _kill_camera_tween() -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()

	_camera_tween = null

	# Si había alguien esperando camera_action_completed,
	# lo destrabamos para que el await no quede colgado.
	if _camera_action_waiting:
		_finish_camera_action()


# =========================================================
# HUD
# =========================================================

func hide_hud() -> void:
	var hud_nodes := _resolve_hud_nodes()

	if hud_nodes.is_empty():
		if print_debug:
			print("CutsceneDirector: no hay nodos HUD configurados para ocultar.")
		return

	# Guardamos estado original antes de tocar nada.
	_store_hud_state_if_needed(hud_nodes)

	if use_hud_fade and hud_fade_out_duration > 0.0:
		_fade_hud_to_hidden(hud_nodes)
	else:
		# Modo instantáneo.
		_kill_hud_fade_tween()

		for node in hud_nodes:
			if node == null:
				continue

			if not is_instance_valid(node):
				continue

			_set_node_visible(node, false)

	if print_debug:
		print("CutsceneDirector: HUD ocultando")


func show_hud() -> void:
	# Si no hay estado guardado, no hay nada que restaurar.
	if _stored_hud_state.is_empty():
		return

	var hud_nodes: Array[Node] = []

	for node in _stored_hud_state.keys():
		if node == null:
			continue

		if not is_instance_valid(node):
			continue

		hud_nodes.append(node)

	if use_hud_fade and hud_fade_in_duration > 0.0:
		_fade_hud_to_restored(hud_nodes)
	else:
		# Modo instantáneo.
		_kill_hud_fade_tween()
		_restore_hud_state()

	if print_debug:
		print("CutsceneDirector: HUD restaurando")


func _store_hud_state_if_needed(hud_nodes: Array[Node]) -> void:
	for node in hud_nodes:
		if node == null:
			continue

		if not is_instance_valid(node):
			continue

		# Guardamos solo una vez por cutscene.
		if _stored_hud_state.has(node):
			continue

		_stored_hud_state[node] = {
			"visible": _get_node_visible(node),
			"alpha": _get_node_alpha(node)
		}


func _fade_hud_to_hidden(hud_nodes: Array[Node]) -> void:
	_kill_hud_fade_tween()

	_hud_fade_tween = create_tween()
	_hud_fade_tween.set_parallel(true)
	_hud_fade_tween.set_trans(hud_fade_trans)
	_hud_fade_tween.set_ease(hud_fade_ease)

	var tween_count := 0

	for node in hud_nodes:
		if node == null:
			continue

		if not is_instance_valid(node):
			continue

		var original_state: Dictionary = _stored_hud_state.get(node, {})
		var was_visible: bool = original_state.get("visible", true)

		# Si ya estaba oculto antes de la cutscene, no lo hacemos aparecer
		# para fade out. Queda oculto y después se restaura oculto.
		if not was_visible:
			continue

		# Para poder fadear, tiene que estar visible.
		_set_node_visible(node, true)

		# Si el nodo puede fadearese por alpha, usamos tween.
		if _tween_node_alpha(_hud_fade_tween, node, 0.0, hud_fade_out_duration):
			tween_count += 1
		else:
			# Si no soporta alpha, lo ocultamos instantáneo.
			_set_node_visible(node, false)

	# Si no hubo ningún tween real, cerramos el proceso manualmente.
	if tween_count <= 0:
		_kill_hud_fade_tween()
		_on_hud_fade_out_finished()
		return

	_hud_fade_tween.finished.connect(_on_hud_fade_out_finished)


func _on_hud_fade_out_finished() -> void:
	for node in _stored_hud_state.keys():
		if node == null:
			continue

		if not is_instance_valid(node):
			continue

		var original_state: Dictionary = _stored_hud_state[node]
		var was_visible: bool = original_state.get("visible", true)

		# Solo ocultamos los nodos que estaban visibles.
		# Los que ya estaban ocultos quedan como estaban.
		if was_visible:
			_set_node_visible(node, false)

	_hud_fade_tween = null


func _fade_hud_to_restored(hud_nodes: Array[Node]) -> void:
	_kill_hud_fade_tween()

	_hud_fade_tween = create_tween()
	_hud_fade_tween.set_parallel(true)
	_hud_fade_tween.set_trans(hud_fade_trans)
	_hud_fade_tween.set_ease(hud_fade_ease)

	var tween_count := 0

	for node in hud_nodes:
		if node == null:
			continue

		if not is_instance_valid(node):
			continue

		var original_state: Dictionary = _stored_hud_state.get(node, {})
		var was_visible: bool = original_state.get("visible", true)
		var original_alpha: float = original_state.get("alpha", 1.0)

		# Si antes de la cutscene estaba oculto, no lo mostramos.
		# También restauramos su alpha original por seguridad.
		if not was_visible:
			_set_node_visible(node, false)
			_set_node_alpha(node, original_alpha)
			continue

		# Si estaba visible, lo prendemos transparente y lo fadeamos.
		_set_node_visible(node, true)
		_set_node_alpha(node, 0.0)

		if _tween_node_alpha(_hud_fade_tween, node, original_alpha, hud_fade_in_duration):
			tween_count += 1
		else:
			# Si no soporta alpha, lo restauramos instantáneo.
			_set_node_visible(node, was_visible)
			_set_node_alpha(node, original_alpha)

	# Si no hubo ningún tween real, restauramos manualmente.
	if tween_count <= 0:
		_kill_hud_fade_tween()
		_restore_hud_state()
		return

	_hud_fade_tween.finished.connect(_on_hud_fade_in_finished)


func _on_hud_fade_in_finished() -> void:
	_restore_hud_state()
	_hud_fade_tween = null


func _restore_hud_state() -> void:
	# Restauramos exactamente como estaba antes de la cutscene.
	for node in _stored_hud_state.keys():
		if node == null:
			continue

		if not is_instance_valid(node):
			continue

		var original_state: Dictionary = _stored_hud_state[node]

		var was_visible: bool = original_state.get("visible", true)
		var original_alpha: float = original_state.get("alpha", 1.0)

		_set_node_visible(node, was_visible)
		_set_node_alpha(node, original_alpha)

	_stored_hud_state.clear()


func _kill_hud_fade_tween() -> void:
	if _hud_fade_tween != null and _hud_fade_tween.is_valid():
		_hud_fade_tween.kill()

	_hud_fade_tween = null


# =========================================================
# HELPERS: PLAYER
# =========================================================

func _has_valid_running_player() -> bool:
	if not is_running:
		push_warning("CutsceneDirector: no hay una cutscene activa.")
		return false

	if current_player == null:
		push_warning("CutsceneDirector: no hay Player actual.")
		return false

	return true


func _resolve_player() -> Node:
	# 1) Buscar por path configurado.
	if player_path != NodePath():
		var player_from_path := get_node_or_null(player_path)

		if player_from_path != null:
			return player_from_path

	# 2) Buscar por grupo.
	if player_group != &"":
		var grouped_player := get_tree().get_first_node_in_group(player_group)

		if grouped_player != null:
			return grouped_player

	return null


# =========================================================
# HELPERS: HUD
# =========================================================

func _resolve_hud_nodes() -> Array[Node]:
	var result: Array[Node] = []

	# 1) Nodos configurados manualmente desde el Inspector.
	for path in hud_nodes_to_hide:
		if path == NodePath():
			continue

		var node := get_node_or_null(path)

		if node != null and not result.has(node):
			result.append(node)

	# 2) Nodos por grupo opcional.
	if hud_group != &"":
		for grouped_node in get_tree().get_nodes_in_group(hud_group):
			if grouped_node != null and not result.has(grouped_node):
				result.append(grouped_node)

	# 3) Fallback específico para tu estructura actual.
	#
	# Si no configuraste nada desde el Inspector, intentamos encontrar:
	#   ../HUD/CanvasLayer/UI
	#   ../HUD/CanvasLayer/LevelUpPanel
	#
	# Esto asume que CutsceneDirector está como hermano de HUD.
	if result.is_empty():
		var common_ui := get_node_or_null("../HUD/CanvasLayer/UI")
		var common_level_panel := get_node_or_null("../HUD/CanvasLayer/LevelUpPanel")

		if common_ui != null:
			result.append(common_ui)

		if common_level_panel != null:
			result.append(common_level_panel)

	return result


func _get_node_visible(node: Node) -> bool:
	# Control, Sprite2D, ColorRect, etc.
	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		return canvas_item.visible

	# CanvasLayer también puede ocultarse/mostrarse.
	if node is CanvasLayer:
		var canvas_layer := node as CanvasLayer
		return canvas_layer.visible

	# Si es un Node común sin visible, asumimos true.
	return true


func _set_node_visible(node: Node, visible: bool) -> void:
	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		canvas_item.visible = visible
		return

	if node is CanvasLayer:
		var canvas_layer := node as CanvasLayer
		canvas_layer.visible = visible
		return

	# Fallback para nodos custom que tengan show/hide.
	if visible:
		if node.has_method("show"):
			node.call("show")
	else:
		if node.has_method("hide"):
			node.call("hide")


func _get_node_alpha(node: Node) -> float:
	# La mayoría de nodos UI heredan de CanvasItem:
	# Control, ColorRect, TextureRect, Sprite2D, etc.
	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		return canvas_item.modulate.a

	# CanvasLayer no tiene modulate.
	# Si se configura un CanvasLayer por error, asumimos alpha 1.
	return 1.0


func _set_node_alpha(node: Node, alpha: float) -> void:
	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		var color := canvas_item.modulate
		color.a = alpha
		canvas_item.modulate = color


func _tween_node_alpha(tween: Tween, node: Node, target_alpha: float, duration: float) -> bool:
	# Devuelve true si realmente pudo crear un tween de alpha.
	# Devuelve false si el nodo no soporta modulate.
	if tween == null:
		return false

	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		tween.tween_property(canvas_item, "modulate:a", target_alpha, duration)
		return true

	return false
