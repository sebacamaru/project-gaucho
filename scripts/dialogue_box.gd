extends Control
class_name DialogueBox

# =========================================================
# DIALOGUE BOX
# =========================================================
#
# Caja de diálogo para cutscenes.
#
# Maneja:
# - mostrar nombre del hablante
# - mostrar texto con efecto typewriter
# - completar texto al apretar tecla / click
# - avanzar cuando el texto ya terminó
# - indicador animado de avance con puntitos
# - fade in / fade out suave
# - force_close robusto para skip completo de cutscene
# - pausas internas dentro del texto mediante tags:
#
#   [pause]
#   [pause=0.5]
#   [p]
#   [p=0.5]
#
# Ejemplo:
#
# "¿Me escuchá’? [pause=0.45] Todo tranquilo por acá… [pause=0.65] no veo nada raro."
#
# El tag NO se muestra en pantalla.
# Solo agrega una pausa durante el typewriter.
#
# Estructura esperada:
#
# DialogueBox
# ├── MarginContainer
# │   └── PanelContainer
# │       └── MarginContainer
# │           └── VBoxContainer
# │               ├── SpeakerLabel
# │               └── TextLabel
# └── Dots
#
# TextLabel puede ser:
# - Label
# - RichTextLabel
#
# Dots debe ser:
# - Label
# =========================================================


# =========================================================
# CONFIGURACIÓN: NODOS
# =========================================================

@export var speaker_label_path: NodePath = ^"MarginContainer/PanelContainer/MarginContainer/VBoxContainer/SpeakerLabel"
@export var text_label_path: NodePath = ^"MarginContainer/PanelContainer/MarginContainer/VBoxContainer/TextLabel"

# Label que aparece cuando el texto terminó.
# Sirve como indicador visual de "tocá para avanzar".
@export var dots_label_path: NodePath = ^"Dots"


# =========================================================
# CONFIGURACIÓN: TEXTO
# =========================================================

# Caracteres por segundo del typewriter.
# Más alto = texto más rápido.
@export var chars_per_second: float = 42.0

# Pausa default cuando usás [pause] o [p] sin valor.
@export_range(0.0, 5.0, 0.01) var default_inline_pause_seconds: float = 0.45

# Multiplicador global de pausas internas.
#
# 1.0 = normal
# 0.5 = pausas más cortas
# 2.0 = pausas más largas
@export_range(0.0, 5.0, 0.01) var inline_pause_scale: float = 1.0

# Acciones que sirven para avanzar diálogo.
#
# Ojo:
# No conviene poner ui_cancel acá, porque ui_cancel lo usa
# el CutsceneDirector para skip completo.
@export var advance_actions: Array[StringName] = [
	&"ui_accept",
	&"ui_select",
	&"facon"
]

# Si está activo, click izquierdo también avanza.
@export var advance_with_mouse_click: bool = true


# =========================================================
# CONFIGURACIÓN: INDICADOR DE AVANCE
# =========================================================
#
# El indicador aparece cuando el typewriter terminó y el diálogo
# está esperando input.
#
# Hace loop:
# .
# ..
# ...
# =========================================================

# Si está activo, muestra el indicador al terminar cada línea.
@export var show_advance_dots: bool = true

# Frames del loop.
@export var advance_dots_frames: Array[String] = [
	"",
	".",
	"..",
	"..."
]

# Tiempo entre cada frame del loop de puntitos.
@export_range(0.05, 2.0, 0.01) var advance_dots_step_seconds: float = 0.35

# Fade in del indicador.
@export_range(0.0, 2.0, 0.01) var advance_dots_fade_in_duration: float = 0.18

# Fade out del indicador.
@export_range(0.0, 2.0, 0.01) var advance_dots_fade_out_duration: float = 0.08


# =========================================================
# CONFIGURACIÓN: FADE
# =========================================================

@export var fade_in_duration: float = 0.15
@export var fade_out_duration: float = 0.12

@export var fade_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var fade_ease: Tween.EaseType = Tween.EASE_OUT


# =========================================================
# REFERENCIAS
# =========================================================

@onready var speaker_label: Label = get_node_or_null(speaker_label_path) as Label
@onready var text_label: Node = get_node_or_null(text_label_path)

@onready var dots_label: Label = get_node_or_null(dots_label_path) as Label


# =========================================================
# ESTADO INTERNO
# =========================================================

var _full_text: String = ""

var _is_open: bool = false
var _is_typing: bool = false
var _is_waiting_for_advance: bool = false
var _skip_typewriter_requested: bool = false

# Pausas internas del typewriter.
#
# Key:
# - cantidad de caracteres visibles donde se dispara la pausa.
#
# Value:
# - segundos de pausa.
#
# Ejemplo:
# Texto limpio: "Hola mundo"
# Pausa después de "Hola":
# _typewriter_pauses[4] = 0.5
var _typewriter_pauses: Dictionary = {}

# True cuando force_close() fue llamado.
# Sirve para cortar awaits internos sin dejar la caja colgada.
var _force_close_requested: bool = false

var _fade_tween: Tween = null
var _fade_waiting: bool = false

# Tween del indicador de avance.
var _dots_tween: Tween = null

# Controla si el loop de puntitos está activo.
var _dots_loop_active: bool = false

# Evita crear dos loops al mismo tiempo.
var _dots_loop_running: bool = false


# =========================================================
# SEÑALES
# =========================================================

signal advance_requested
signal fade_action_completed


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	# Arranca oculto.
	visible = false
	modulate.a = 0.0

	# Queremos capturar input solo mientras el diálogo está activo.
	set_process_unhandled_input(false)

	# El root del DialogueBox debe frenar el mouse cuando está visible.
	# Así el click no pasa al gameplay.
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Muchos hijos UI, como PanelContainer / MarginContainer,
	# pueden interceptar el mouse.
	#
	# Los ponemos en PASS para que el click pueda llegar al root DialogueBox
	# y activar _gui_input().
	_set_children_mouse_filter_to_pass(self)

	# Estado inicial del indicador de avance.
	_setup_advance_dots()

	_clear_text()


# =========================================================
# INPUT
# =========================================================

func _unhandled_input(event: InputEvent) -> void:
	# Captura inputs que no fueron consumidos por la UI.
	#
	# Esto sirve para:
	# - teclado
	# - acciones tipo ui_accept
	# - clicks que no caen encima de un Control que los consuma

	if not visible:
		return

	if _is_advance_event(event):
		get_viewport().set_input_as_handled()
		_request_advance()


func _gui_input(event: InputEvent) -> void:
	# Captura input específico de UI.
	#
	# En Godot, cuando clickeás sobre un Control,
	# el evento suele pasar por _gui_input()
	# antes que por _unhandled_input().
	#
	# Por eso agregamos este método:
	# - click sobre la caja de diálogo completa texto
	# - click sobre la caja de diálogo avanza/cierra
	#
	# accept_event() evita que el click pase al gameplay.

	if not visible:
		return

	if _is_advance_event(event):
		accept_event()
		_request_advance()


func _is_advance_event(event: InputEvent) -> bool:
	# ---------------------------------------------------------
	# Teclado / acciones
	# ---------------------------------------------------------
	for action in advance_actions:
		if action == &"":
			continue

		if InputMap.has_action(action) and event.is_action_pressed(action):
			return true

	# ---------------------------------------------------------
	# Mouse
	# ---------------------------------------------------------
	if advance_with_mouse_click:
		var mouse_event := event as InputEventMouseButton

		if mouse_event != null:
			if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
				return true

	return false


func _request_advance() -> void:
	# Si el texto todavía está tipeando, el primer input lo completa.
	#
	# Esto también corta una pausa inline en progreso.
	if _is_typing:
		_skip_typewriter_requested = true
		return

	# Si el texto ya terminó, el siguiente input avanza/cierra.
	if _is_waiting_for_advance:
		_is_waiting_for_advance = false

		# Ocultamos el indicador apenas el jugador avanza.
		_hide_advance_dots(true)

		advance_requested.emit()


# =========================================================
# API PÚBLICA
# =========================================================

func say(speaker: String, text: String, close_after: bool = true) -> void:
	# Muestra una línea de diálogo completa:
	# - abre la caja
	# - tipea el texto
	# - muestra indicador de avance
	# - espera input
	# - opcionalmente cierra la caja
	#
	# Esta función está preparada para que force_close()
	# pueda cortarla sin dejar awaits colgados.

	_force_close_requested = false

	await open_box()

	if _force_close_requested:
		return

	_set_speaker(speaker)
	await _type_text(text)

	if _force_close_requested:
		return

	# El texto ya terminó: mostramos el indicador.
	_show_advance_dots()

	_is_waiting_for_advance = true
	await advance_requested

	if _force_close_requested:
		return

	if close_after:
		await close_box()


func open_box() -> void:
	if _is_open:
		return

	_force_close_requested = false
	_is_open = true
	visible = true

	# Activamos input global mientras el diálogo está abierto.
	set_process_unhandled_input(true)

	await _fade_to(1.0, fade_in_duration)


func close_box() -> void:
	if not _is_open:
		return

	_is_open = false
	_is_typing = false
	_is_waiting_for_advance = false
	_skip_typewriter_requested = false
	_typewriter_pauses.clear()

	# Apagamos el indicador antes de cerrar la caja.
	_hide_advance_dots(false)

	await _fade_to(0.0, fade_out_duration)

	if _force_close_requested:
		return

	visible = false
	set_process_unhandled_input(false)
	_clear_text()


func force_close() -> void:
	# Cierre instantáneo.
	# Útil para skip completo de cutscene.
	#
	# Además de ocultar el nodo, destraba:
	# - await open_box()
	# - await close_box()
	# - await advance_requested
	# - typewriter en progreso
	# - pausa inline en progreso
	# - indicador de avance en loop

	_force_close_requested = true

	var was_waiting := _is_waiting_for_advance
	var was_typing := _is_typing

	# Cortar fade pendiente y destrabar su await.
	_kill_fade_tween()

	# Cortar puntitos.
	_hide_advance_dots(false)

	_is_open = false
	_is_typing = false
	_is_waiting_for_advance = false
	_skip_typewriter_requested = true
	_typewriter_pauses.clear()

	visible = false
	modulate.a = 0.0
	set_process_unhandled_input(false)
	_clear_text()

	# Si el DialogueBox estaba esperando input, destrabamos:
	#
	# await advance_requested
	#
	# También emitimos si estaba tipeando; no siempre hay alguien
	# esperando todavía, pero no hace daño.
	if was_waiting or was_typing:
		advance_requested.emit()


func complete_current_text() -> void:
	# Completa el typewriter desde afuera.
	# También corta cualquier pausa inline activa.
	_skip_typewriter_requested = true


# =========================================================
# TYPEWRITER
# =========================================================

func _type_text(text: String) -> void:
	# Arranca una nueva línea, así que ocultamos el indicador
	# de avance de la línea anterior.
	_hide_advance_dots(false)

	# Antes de tipear, parseamos tags inline.
	#
	# Ejemplo de entrada:
	# "Hola [pause=0.5] mundo"
	#
	# Resultado:
	# _full_text = "Hola  mundo"
	# _typewriter_pauses = {5: 0.5}

	var parsed_text := _parse_pause_tags(text)

	_full_text = str(parsed_text.get("text", ""))
	_typewriter_pauses = parsed_text.get("pauses", {})

	_skip_typewriter_requested = false
	_is_typing = true

	_set_text_full(_full_text)
	_set_visible_characters(0)

	if chars_per_second <= 0.0:
		_set_visible_characters(_get_text_length(_full_text))
		_is_typing = false
		_skip_typewriter_requested = false
		return

	var total_chars := _get_text_length(_full_text)
	var current_chars := 0
	var delay := 1.0 / chars_per_second

	# Soporte para pausa al inicio del texto:
	# "[pause=0.5] Hola"
	if _typewriter_pauses.has(0):
		var initial_pause := float(_typewriter_pauses[0]) * inline_pause_scale
		await _wait_typewriter_seconds(initial_pause)

	while current_chars < total_chars:
		if _skip_typewriter_requested:
			break

		if _force_close_requested:
			return

		if not _is_open:
			return

		current_chars += 1
		_set_visible_characters(current_chars)

		# Si hay una pausa justo después de este carácter,
		# esperamos antes de seguir mostrando el próximo.
		if _typewriter_pauses.has(current_chars):
			var pause_seconds := float(_typewriter_pauses[current_chars]) * inline_pause_scale

			if pause_seconds > 0.0:
				await _wait_typewriter_seconds(pause_seconds)

		if _skip_typewriter_requested:
			break

		if _force_close_requested:
			return

		if not _is_open:
			return

		await _wait_typewriter_seconds(delay)

	# Si se cerró por skip durante el último await,
	# no intentamos tocar más la UI.
	if _force_close_requested:
		return

	if not _is_open:
		return

	# Aseguramos que al final quede todo visible.
	_set_visible_characters(total_chars)

	_is_typing = false
	_skip_typewriter_requested = false


func _parse_pause_tags(raw_text: String) -> Dictionary:
	# Convierte tags de pausa en datos internos del typewriter.
	#
	# Tags soportados:
	#
	# [pause]
	# [pause=0.5]
	# [p]
	# [p=0.5]
	#
	# El tag no se muestra en pantalla.
	#
	# Ejemplo:
	#
	# "Hola [pause=0.5] mundo"
	#
	# Devuelve:
	#
	# {
	#   "text": "Hola  mundo",
	#   "pauses": {
	#       5: 0.5
	#   }
	# }
	#
	# Nota:
	# Si tenés dos pausas en el mismo punto, se suman.

	var clean_text := ""
	var pauses: Dictionary = {}

	var i := 0

	while i < raw_text.length():
		var current_char := raw_text.substr(i, 1)

		if current_char == "[":
			var close_index := raw_text.find("]", i)

			if close_index != -1:
				var tag := raw_text.substr(i + 1, close_index - i - 1).strip_edges().to_lower()
				var pause_seconds := _parse_pause_tag_seconds(tag)

				# pause_seconds >= 0 significa:
				# "sí, era un tag de pausa válido".
				if pause_seconds >= 0.0:
					var pause_at_char := clean_text.length()

					pauses[pause_at_char] = float(pauses.get(pause_at_char, 0.0)) + pause_seconds

					i = close_index + 1
					continue

		clean_text += current_char
		i += 1

	return {
		"text": clean_text,
		"pauses": pauses
	}


func _parse_pause_tag_seconds(tag: String) -> float:
	# Devuelve:
	# - segundos de pausa si el tag es válido
	# - -1.0 si no era un tag de pausa
	#
	# Ejemplos:
	#
	# "pause"      => default_inline_pause_seconds
	# "p"          => default_inline_pause_seconds
	# "pause=0.5" => 0.5
	# "p=0.5"     => 0.5

	if tag == "pause" or tag == "p":
		return default_inline_pause_seconds

	if tag.begins_with("pause="):
		var raw_value := tag.substr("pause=".length())
		return max(float(raw_value), 0.0)

	if tag.begins_with("p="):
		var raw_value := tag.substr("p=".length())
		return max(float(raw_value), 0.0)

	return -1.0


func _wait_typewriter_seconds(seconds: float) -> void:
	# Wait cancelable para typewriter y pausas inline.
	#
	# Lo usamos en vez de:
	#
	# await get_tree().create_timer(seconds).timeout
	#
	# porque necesitamos que:
	# - force_close()
	# - complete_current_text()
	# - click para completar texto
	#
	# puedan cortar la espera casi instantáneamente.

	if seconds <= 0.0:
		return

	var elapsed := 0.0

	while elapsed < seconds:
		if _force_close_requested:
			return

		if _skip_typewriter_requested:
			return

		if not _is_open:
			return

		await get_tree().process_frame
		elapsed += get_process_delta_time()


# =========================================================
# TEXT HELPERS
# =========================================================

func _set_speaker(speaker: String) -> void:
	if speaker_label == null:
		return

	var clean_speaker := speaker.strip_edges()

	speaker_label.text = clean_speaker
	speaker_label.visible = clean_speaker != ""


func _clear_text() -> void:
	if speaker_label != null:
		speaker_label.text = ""

	if text_label == null:
		return

	if text_label is RichTextLabel:
		var rich := text_label as RichTextLabel
		rich.text = ""
		rich.visible_characters = 0
		return

	if text_label is Label:
		var label := text_label as Label
		label.text = ""
		return


func _set_text_full(text: String) -> void:
	if text_label == null:
		return

	if text_label is RichTextLabel:
		var rich := text_label as RichTextLabel
		rich.text = text
		rich.visible_characters = 0
		return

	if text_label is Label:
		var label := text_label as Label
		label.text = ""
		return


func _set_visible_characters(amount: int) -> void:
	if text_label == null:
		return

	if text_label is RichTextLabel:
		var rich := text_label as RichTextLabel
		rich.visible_characters = amount
		return

	if text_label is Label:
		var label := text_label as Label
		label.text = _full_text.substr(0, amount)
		return


func _get_text_length(text: String) -> int:
	return text.length()


# =========================================================
# ADVANCE DOTS
# =========================================================

func _setup_advance_dots() -> void:
	# Estado inicial del indicador de avance.
	#
	# Arranca oculto y transparente.
	# Se muestra recién cuando el texto terminó de escribirse.

	if dots_label == null:
		return

	dots_label.visible = false
	dots_label.modulate.a = 0.0

	if advance_dots_frames.is_empty():
		advance_dots_frames = [
			".",
			"..",
			"..."
		]

	dots_label.text = advance_dots_frames[0]


func _show_advance_dots() -> void:
	if not show_advance_dots:
		return

	if dots_label == null:
		return

	if advance_dots_frames.is_empty():
		return

	_kill_dots_tween()

	_dots_loop_active = true

	dots_label.visible = true
	dots_label.text = advance_dots_frames[0]

	# Fade in.
	if advance_dots_fade_in_duration <= 0.0:
		dots_label.modulate.a = 1.0
	else:
		dots_label.modulate.a = 0.0

		_dots_tween = create_tween()
		_dots_tween.set_trans(Tween.TRANS_SINE)
		_dots_tween.set_ease(Tween.EASE_OUT)
		_dots_tween.tween_property(
			dots_label,
			"modulate:a",
			1.0,
			advance_dots_fade_in_duration
		)

	# Arrancamos loop si no está corriendo.
	_start_advance_dots_loop()


func _hide_advance_dots(animate: bool = true) -> void:
	_dots_loop_active = false

	if dots_label == null:
		return

	_kill_dots_tween()

	if not animate or advance_dots_fade_out_duration <= 0.0:
		dots_label.visible = false
		dots_label.modulate.a = 0.0
		return

	_dots_tween = create_tween()
	_dots_tween.set_trans(Tween.TRANS_SINE)
	_dots_tween.set_ease(Tween.EASE_OUT)
	_dots_tween.tween_property(
		dots_label,
		"modulate:a",
		0.0,
		advance_dots_fade_out_duration
	)

	_dots_tween.finished.connect(_on_advance_dots_fade_out_finished)


func _on_advance_dots_fade_out_finished() -> void:
	if dots_label == null:
		return

	if _dots_loop_active:
		return

	dots_label.visible = false
	dots_label.modulate.a = 0.0


func _start_advance_dots_loop() -> void:
	# Llamamos una función con await sin awaitarla.
	# Eso deja corriendo la corrutina del loop internamente.
	_run_advance_dots_loop()


func _run_advance_dots_loop() -> void:
	if _dots_loop_running:
		return

	if dots_label == null:
		return

	_dots_loop_running = true

	var frame_index := 0

	while _dots_loop_active:
		if dots_label == null:
			break

		if advance_dots_frames.is_empty():
			break

		dots_label.text = advance_dots_frames[frame_index % advance_dots_frames.size()]
		frame_index += 1

		await _wait_dots_seconds(advance_dots_step_seconds)

	_dots_loop_running = false


func _wait_dots_seconds(seconds: float) -> void:
	if seconds <= 0.0:
		return

	var elapsed := 0.0

	while elapsed < seconds:
		if not _dots_loop_active:
			return

		if _force_close_requested:
			return

		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _kill_dots_tween() -> void:
	if _dots_tween != null and _dots_tween.is_valid():
		_dots_tween.kill()

	_dots_tween = null


# =========================================================
# MOUSE FILTER HELPERS
# =========================================================

func _set_children_mouse_filter_to_pass(root: Node) -> void:
	# Muchos nodos UI como PanelContainer, MarginContainer, VBoxContainer,
	# Labels, etc. pueden capturar eventos de mouse.
	#
	# Si un hijo consume el click, el DialogueBox raíz no recibe _gui_input().
	#
	# Dejamos los hijos en MOUSE_FILTER_PASS para que:
	# - puedan seguir existiendo normalmente
	# - el evento pueda subir hasta el DialogueBox root
	# - el root pueda llamar accept_event()
	#
	# No cambiamos el mouse_filter del root acá.
	# El root queda en MOUSE_FILTER_STOP.

	if root == null:
		return

	for child in root.get_children():
		if child is Control:
			var control := child as Control
			control.mouse_filter = Control.MOUSE_FILTER_PASS

		_set_children_mouse_filter_to_pass(child)


# =========================================================
# FADE
# =========================================================

func _fade_to(target_alpha: float, duration: float) -> void:
	# Fade robusto:
	# si force_close() mata el tween, emitimos fade_action_completed
	# para que el await no quede colgado.

	_kill_fade_tween()

	if _force_close_requested:
		return

	if duration <= 0.0:
		modulate.a = target_alpha
		return

	_fade_waiting = true
	_fade_tween = create_tween()
	_fade_tween.set_trans(fade_trans)
	_fade_tween.set_ease(fade_ease)
	_fade_tween.finished.connect(_finish_fade_action)
	_fade_tween.tween_property(self, "modulate:a", target_alpha, duration)

	await fade_action_completed

	if _force_close_requested:
		return

	modulate.a = target_alpha
	_fade_tween = null


func _finish_fade_action() -> void:
	if not _fade_waiting:
		return

	_fade_waiting = false
	fade_action_completed.emit()


func _kill_fade_tween() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = null

	# Si había una función esperando fade_action_completed,
	# la destrabamos.
	if _fade_waiting:
		_finish_fade_action()
