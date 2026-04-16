extends Control
class_name LevelUpPanel

signal option_selected(upgrade_id: String)

# Referencias a nodos principales de la UI
@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel

@onready var button_1: Button = $Panel/VBoxContainer/Options/Button1
@onready var button_2: Button = $Panel/VBoxContainer/Options/Button2
@onready var button_3: Button = $Panel/VBoxContainer/Options/Button3

# Opciones actuales mostradas en el panel
var current_options: Array[Dictionary] = []

# Mientras esté en false, el panel se ve
# pero no permite seleccionar ninguna opción.
# Esto evita clicks accidentales al subir de nivel.
var selection_enabled: bool = false


func _ready() -> void:
	# Permitimos que este panel siga procesando
	# aunque el juego esté pausado.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	# Conectamos los tres botones a su índice correspondiente.
	button_1.pressed.connect(func() -> void: _select_option(0))
	button_2.pressed.connect(func() -> void: _select_option(1))
	button_3.pressed.connect(func() -> void: _select_option(2))

	hide_panel()


func show_options(options: Array[Dictionary], new_level: int) -> void:
	# Guardamos las opciones que llegaron
	current_options = options

	# Importante:
	# al abrir el panel bloqueamos la selección
	# hasta que el jugador suelte el click.
	selection_enabled = false

	# Actualizamos el título
	title_label.text = "¡Subiste a NIVEL %d!" % new_level

	# Configuramos cada botón
	_setup_button(button_1, 0)
	_setup_button(button_2, 1)
	_setup_button(button_3, 2)

	# Mostramos el panel
	show()

	# Deshabilitamos interacción inicial
	_set_buttons_interactable(false)

	# Esperamos a que el input quede limpio
	_enable_selection_when_input_is_released()


func hide_panel() -> void:
	hide()

	# Al cerrar, volvemos a bloquear selección
	selection_enabled = false
	_set_buttons_interactable(false)


func _setup_button(button: Button, index: int) -> void:
	# Si no hay una opción para este índice,
	# ocultamos el botón.
	if index >= current_options.size():
		button.visible = false
		button.disabled = true
		return
	
	var option := current_options[index]

	# Activamos el botón
	button.visible = true
	button.disabled = false
		
	# Referencias internas del botón
	var icon: TextureRect = button.get_node("PanelContainer/MarginContainer/VBoxContainer/Icon")
	var title: Label = button.get_node("PanelContainer/MarginContainer/VBoxContainer/Title")
	var desc: Label = button.get_node("PanelContainer/MarginContainer/VBoxContainer/Description")

	# Cargamos contenido visual
	icon.texture = option.icon
	title.text = option.title
	desc.text = option.description


func _select_option(index: int) -> void:
	# Protección clave:
	# ignoramos cualquier click mientras el panel
	# todavía esté esperando que se libere el input.
	if not selection_enabled:
		return

	# Validación defensiva
	if index < 0 or index >= current_options.size():
		return

	var option := current_options[index]

	# Emitimos la opción elegida
	option_selected.emit(option.id)


func _set_buttons_interactable(enabled: bool) -> void:
	# Protección por si todavía no están listos
	if button_1 == null or button_2 == null or button_3 == null:
		return

	button_1.disabled = not enabled or not button_1.visible
	button_2.disabled = not enabled or not button_2.visible
	button_3.disabled = not enabled or not button_3.visible


func _enable_selection_when_input_is_released() -> void:
	# Lanzamos la espera asincrónica.
	_wait_until_input_is_released()


func _wait_until_input_is_released() -> void:
	# Esperamos al menos 1 frame para evitar
	# que el click anterior se propague.
	await get_tree().process_frame

	# Mientras el click izquierdo siga apretado,
	# seguimos esperando.
	while Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		await get_tree().process_frame

	# Recién cuando se suelta,
	# habilitamos la selección.
	selection_enabled = true
	_set_buttons_interactable(true)
