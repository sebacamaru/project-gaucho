extends Control
class_name LevelUpPanel

signal option_selected(upgrade_id: String)

@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel

@onready var button_1: Button = $Panel/VBoxContainer/Options/Button1
@onready var button_2: Button = $Panel/VBoxContainer/Options/Button2
@onready var button_3: Button = $Panel/VBoxContainer/Options/Button3

var current_options: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	button_1.pressed.connect(func() -> void: _select_option(0))
	button_2.pressed.connect(func() -> void: _select_option(1))
	button_3.pressed.connect(func() -> void: _select_option(2))

	hide_panel()

func show_options(options: Array[Dictionary], new_level: int) -> void:
	current_options = options

	title_label.text = "¡Subiste a NIVEL %d!" % new_level

	_setup_button(button_1, 0)
	_setup_button(button_2, 1)
	_setup_button(button_3, 2)

	show()

func hide_panel() -> void:
	hide()

func _setup_button(button: Button, index: int) -> void:
	if index >= current_options.size():
		button.visible = false
		button.disabled = true
		return
	
	var option := current_options[index]
	button.visible = true
	button.disabled = false
		
	var icon: TextureRect = button.get_node("PanelContainer/MarginContainer/VBoxContainer/Icon")
	var title: Label = button.get_node("PanelContainer/MarginContainer/VBoxContainer/Title")
	var desc: Label = button.get_node("PanelContainer/MarginContainer/VBoxContainer/Description")

	icon.texture = option.icon
	title.text = option.title
	desc.text = option.description

func _select_option(index: int) -> void:
	if index < 0 or index >= current_options.size():
		return

	var option := current_options[index]
	option_selected.emit(option.id)
