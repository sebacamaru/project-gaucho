extends ColorRect

# =========================================================
# CONFIG
# =========================================================

@export var base_alpha: float = 0.18
@export var pulse_alpha: float = 0.98
@export var pulse_speed: float = 0.35

# =========================================================
# ESTADO
# =========================================================

var pulse_tween: Tween
var fade_tween: Tween

var is_active: bool = false


func _ready() -> void:
	# Arranca invisible
	modulate.a = 0.0


# =========================================================
# ACTIVAR
# =========================================================

func start_effect() -> void:
	if is_active:
		return

	is_active = true

	# Cortamos tweens anteriores por seguridad
	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()

	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()

	# Arranca el pulse continuo
	_start_pulse()


# =========================================================
# PULSE LOOP
# =========================================================

func _start_pulse() -> void:
	if not is_active:
		return

	pulse_tween = create_tween()
	pulse_tween.set_loops()

	pulse_tween.set_trans(Tween.TRANS_SINE)
	pulse_tween.set_ease(Tween.EASE_IN_OUT)

	# Sube
	pulse_tween.tween_property(
		self,
		"modulate:a",
		pulse_alpha,
		pulse_speed
	)

	# Baja
	pulse_tween.tween_property(
		self,
		"modulate:a",
		base_alpha,
		pulse_speed
	)


# =========================================================
# DESACTIVAR
# =========================================================

func stop_effect() -> void:
	if not is_active:
		return

	is_active = false

	# Cortamos el pulse
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()

	# Fade OUT
	fade_tween = create_tween()
	fade_tween.set_trans(Tween.TRANS_QUAD)
	fade_tween.set_ease(Tween.EASE_OUT)

	fade_tween.tween_property(
		self,
		"modulate:a",
		0.0,
		0.25
	)
