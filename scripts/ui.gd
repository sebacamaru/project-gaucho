extends Control

# -----------------------------------------------------------------------------
# Referencias a nodos UI
# -----------------------------------------------------------------------------

@onready var boss_timer_label: Label = $TopUI/TopCenterContainer/BossTimerLabel

@onready var exp_bar: TextureProgressBar = $TopUI/ExpBar
@onready var exp_flash: ColorRect = $TopUI/ExpFlash

@onready var level_label: Label = $BottomRightUI/Container/Nivel/LevelCounter
@onready var demons_label: Label = $BottomRightUI/Container/Demonios/DemonsCounter
@onready var score_label: Label = $BottomRightUI/Container/Puntos/PointsCounter

@onready var health_bar: TextureProgressBar = $BottomCenterUI/HealthBar
@onready var stamina_bar: TextureProgressBar = $BottomCenterUI/StaminaBar

@onready var skill_1: Control = $BottomLeftUI/SkillsContainer/Skill1
@onready var skill_2: Control = $BottomLeftUI/SkillsContainer/Skill2
@onready var skill_3: Control = $BottomLeftUI/SkillsContainer/Skill3
@onready var skill_4: Control = $BottomLeftUI/SkillsContainer/Skill4

@onready var level_indicator: Control = $BottomRightUI/Container/Nivel

# Busca al player por grupo para no depender de un path fijo en la escena.
@onready var player = get_tree().get_first_node_in_group("player")

# -----------------------------------------------------------------------------
# Tweens
# -----------------------------------------------------------------------------

var stamina_tween: Tween

# -----------------------------------------------------------------------------
# Estado interno
# -----------------------------------------------------------------------------

# Tiempo restante hasta que aparezca el jefe.
var boss_time_left: float = 328.0

# Tween usado para animar el llenado suave de la barra de experiencia.
# Lo guardamos para poder cortar el tween anterior si entra XP de nuevo enseguida.
var exp_tween: Tween
var squish_tween: Tween

# -----------------------------------------------------------------------------
# Ciclo de vida
# -----------------------------------------------------------------------------

func _ready() -> void:
	# Cursor
	var cursor = load("res://ui/cursor.png")
	Input.set_custom_mouse_cursor(cursor, Input.CURSOR_ARROW, Vector2(8, 8))
	
	# Inicializa el timer visual del jefe.
	update_boss_timer()

	if not player:
		return

	# Vida
	player.hp_changed.connect(_on_player_hp_changed)
	_on_player_hp_changed(player.hp, player.max_hp)
	
	# Estamina
	if player.stamina and player.stamina.has_signal("changed"):
		player.stamina.changed.connect(_on_player_stamina_changed)
		_on_player_stamina_changed(
			player.stamina.current_stamina,
			player.stamina.max_stamina
		)

	# Skills
	player.skill_used.connect(_on_player_skill_used)
	player.progress.skill_unlocked.connect(_on_player_skill_unlocked)
	_refresh_skill_ui()

	# Experiencia
	if player.progress.has_signal("xp_changed"):
		player.progress.xp_changed.connect(_on_player_exp_changed)
		_on_player_exp_changed(
			player.progress.current_xp,
			player.progress.get_xp_to_next_level(),
			player.progress.level
		)

	# Level up
	if player.progress.has_signal("level_up"):
		player.progress.level_up.connect(_on_player_level_up)
	
	# Nueva kill
	if player.progress.has_signal("demons_killed_changed"):
		player.progress.demons_killed_changed.connect(_on_demons_killed_changed)
		_on_demons_killed_changed(player.progress.demons_killed)
	
	# Suma puntos
	if player.progress.has_signal("score_changed"):
		player.progress.score_changed.connect(_on_score_changed)
		_on_score_changed(player.progress.score)

func _process(delta: float) -> void:
	# Cuenta regresiva del boss.
	if boss_time_left > 0.0:
		boss_time_left -= delta
		if boss_time_left < 0.0:
			boss_time_left = 0.0

	update_boss_timer()

# -----------------------------------------------------------------------------
# Boss timer
# -----------------------------------------------------------------------------

func update_boss_timer() -> void:
	var total_seconds: int = int(ceil(boss_time_left))
	var minutes: int = floori(total_seconds / 60.0)
	var seconds: int = total_seconds % 60

	boss_timer_label.text = "Jefe en %d:%02d" % [minutes, seconds]

# -----------------------------------------------------------------------------
# Player HP
# -----------------------------------------------------------------------------

func _on_player_hp_changed(current_hp: int, max_hp: int) -> void:
	health_bar.min_value = 0
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	
# -----------------------------------------------------------------------------
# Player Stammina
# -----------------------------------------------------------------------------

func _on_player_stamina_changed(current: float, max_value: float) -> void:
	stamina_bar.min_value = 0
	stamina_bar.max_value = max(max_value, 1.0)

	if stamina_tween and stamina_tween.is_valid():
		stamina_tween.kill()

	var duration := 0.10 if current < stamina_bar.value else 0.16

	stamina_tween = create_tween()
	stamina_tween.set_trans(Tween.TRANS_CUBIC)
	stamina_tween.set_ease(Tween.EASE_OUT)
	stamina_tween.tween_property(stamina_bar, "value", current, duration)
	
# -----------------------------------------------------------------------------
# Player EXP / Level
# -----------------------------------------------------------------------------

func _on_player_exp_changed(current_exp: int, exp_to_next: int, level: int) -> void:
	# Actualiza rango de la barra según la XP necesaria para el próximo nivel.
	exp_bar.min_value = 0
	exp_bar.max_value = max(exp_to_next, 1)

	# Refresca el texto de nivel.
	level_label.text = "%d" % level

	# Si había una animación previa de XP, la cortamos para evitar
	# que se acumulen tweens y la barra quede rara visualmente.
	if exp_tween and exp_tween.is_valid():
		exp_tween.kill()

	# Anima el valor de la barra suavemente hasta la XP actual.
	exp_tween = create_tween()
	exp_tween.set_trans(Tween.TRANS_CUBIC)
	exp_tween.set_ease(Tween.EASE_OUT)
	exp_tween.tween_property(exp_bar, "value", current_exp, 0.25)

	# Feedback visual extra al ganar experiencia.
	_play_exp_gain_feedback()

func _on_player_level_up(new_level: int) -> void:
	# Pequeño golpe visual extra cuando sube de nivel.
	var tween := create_tween()

	exp_bar.scale = Vector2(1.05, 1.15)

	tween.tween_property(exp_bar, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

	level_label.text = str(new_level)

	if squish_tween and squish_tween.is_valid():
		squish_tween.kill()

	scale = Vector2.ONE
	
	# Efecto squish 
	squish_tween = create_tween()
	squish_tween.set_trans(Tween.TRANS_QUAD)
	squish_tween.set_ease(Tween.EASE_OUT)
	squish_tween.tween_property(level_indicator, "scale", Vector2(0.88, 1.08), 0.045)
	squish_tween.tween_property(level_indicator, "scale", Vector2(1.04, 0.96), 0.05)
	squish_tween.tween_property(level_indicator, "scale", Vector2.ONE, 0.08)

func _play_exp_gain_feedback() -> void:
	# Hace un pequeño pulse de la barra y un flash encima.
	var tween := create_tween()

	exp_bar.scale = Vector2(1.02, 1.08)
	exp_flash.modulate.a = 0.3

	tween.parallel().tween_property(exp_bar, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)

	tween.parallel().tween_property(exp_flash, "modulate:a", 0.0, 0.28)

func _on_demons_killed_changed(total: int) -> void:
	demons_label.text = str(total)

func _on_score_changed(new_score: int) -> void:
	score_label.text = str(new_score).pad_zeros(9)

# -----------------------------------------------------------------------------
# Skills
# -----------------------------------------------------------------------------

func _on_player_skill_unlocked(slot_name: String) -> void:
	# Activa visualmente el slot correspondiente cuando el player lo desbloquea.
	match slot_name:
		"skill_2":
			skill_2.set_unlocked(true)
		"skill_3":
			skill_3.set_unlocked(true)
			stamina_bar.visible = true
		"skill_4":
			skill_4.set_unlocked(true)

func _on_player_skill_used(slot_name: String) -> void:
	# Reproduce un pequeño squash en el slot cuando se usa una skill.
	match slot_name:
		"skill_1":
			skill_1.play_use_squish()
		"skill_2":
			skill_2.play_use_squish()
		"skill_3":
			skill_3.play_use_squish()
		"skill_4":
			skill_4.play_use_squish()

func _refresh_skill_ui() -> void:
	# Sincroniza el estado visual de skills ya desbloqueadas al iniciar la escena.
	skill_2.set_unlocked(player.progress.unlocked_skills.get("skill_2", false))
	skill_3.set_unlocked(player.progress.unlocked_skills.get("skill_3", false))
	skill_4.set_unlocked(player.progress.unlocked_skills.get("skill_4", false))
	stamina_bar.visible = player.progress.unlocked_skills.get("skill_3", false)
