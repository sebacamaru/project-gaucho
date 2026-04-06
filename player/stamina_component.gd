extends Node
class_name StaminaComponent

# =========================================================
# SIGNALS
# =========================================================

# Se emite cada vez que cambia la stamina actual.
# Útil para actualizar la barra en UI.
signal changed(current: float, max_value: float)

# Se emite cuando la stamina vuelve a llenarse por completo.
signal became_full()

# Se emite cuando la stamina se vacía.
signal emptied()

# =========================================================
# CONFIGURACIÓN BASE
# =========================================================

# Valor máximo de la barra.
@export var max_stamina: float = 100.0

# Velocidad de recarga por defecto.
# Se usa:
# - al iniciar el juego
# - como fallback si no se configuró otra al vaciar la barra
@export var base_recharge_rate: float = 40.0

# Delay por defecto antes de empezar a recargar.
# También funciona como fallback.
@export var base_recovery_delay: float = 0.0

# =========================================================
# ESTADO INTERNO
# =========================================================

# Valor actual de stamina.
var current_stamina: float = 0.0

# Velocidad de recarga actualmente activa.
# Este valor lo puede cambiar cada acción
# (facón, dash, shotgun, etc.).
var current_recharge_rate: float = 0.0

# Tiempo restante antes de que la barra pueda empezar a recargarse.
var recovery_delay_timer: float = 0.0

# Cache para detectar el momento exacto en el que la barra
# vuelve a llenarse, sin emitir la señal múltiples veces.
var _was_full: bool = false


func _ready() -> void:
	# Arranca llena.
	current_stamina = max_stamina

	# Arranca usando la velocidad base.
	current_recharge_rate = base_recharge_rate

	_was_full = true
	changed.emit(current_stamina, max_stamina)


func _process(delta: float) -> void:
	# Si todavía estamos dentro del delay de recuperación,
	# descontamos tiempo y no recargamos.
	if recovery_delay_timer > 0.0:
		recovery_delay_timer = max(recovery_delay_timer - delta, 0.0)
		return

	# Si ya está llena, no hacemos nada.
	if current_stamina >= max_stamina:
		return

	# Recarga usando la velocidad actualmente configurada.
	current_stamina = min(
		current_stamina + current_recharge_rate * delta,
		max_stamina
	)

	changed.emit(current_stamina, max_stamina)

	# Detectar el momento en el que vuelve a estar full.
	if not _was_full and is_full():
		_was_full = true
		became_full.emit()


# =========================================================
# CONSULTAS
# =========================================================

func is_full() -> bool:
	# Tolerancia pequeña para evitar problemas de flotantes.
	return current_stamina >= max_stamina - 0.001


func can_use_full_action() -> bool:
	# En este diseño, las acciones importantes solo se pueden usar
	# cuando la barra está completamente llena.
	return is_full()


func has_enough(amount: float) -> bool:
	# Helper genérico por si más adelante querés usar
	# costos parciales.
	return current_stamina >= amount


func get_fill_ratio() -> float:
	if max_stamina <= 0.0:
		return 0.0

	return current_stamina / max_stamina


func get_current_recharge_rate() -> float:
	return current_recharge_rate


func get_recovery_delay_left() -> float:
	return recovery_delay_timer


# =========================================================
# CONSUMO
# =========================================================

# Método genérico para consumo parcial.
# Hoy puede no usarse si todas las acciones vacían el 100%,
# pero lo dejamos porque puede servir para futuras skills.
func consume(amount: float) -> bool:
	if current_stamina < amount:
		return false

	current_stamina -= amount
	current_stamina = max(current_stamina, 0.0)

	# Como ya no está llena, reseteamos el cache.
	_was_full = false
	changed.emit(current_stamina, max_stamina)

	if current_stamina <= 0.0:
		emptied.emit()

	return true


# Vacía toda la barra usando la configuración base
# de recarga y delay.
func empty() -> void:
	empty_and_configure_recovery(base_recharge_rate, base_recovery_delay)


# Vacía toda la barra y además define cómo se recuperará
# después de esa acción.
#
# Ejemplos:
# - facón   -> recarga rápida, delay 0
# - dash    -> recarga media, delay corto
# - shotgun -> recarga lenta, delay más largo
func empty_and_configure_recovery(new_recharge_rate: float, new_delay: float) -> void:
	current_stamina = 0.0

	# Nunca permitimos una velocidad menor a 1 para evitar
	# casos raros o configuraciones inválidas.
	current_recharge_rate = max(1.0, new_recharge_rate)

	# Delay mínimo 0.
	recovery_delay_timer = max(0.0, new_delay)

	_was_full = false
	changed.emit(current_stamina, max_stamina)
	emptied.emit()


# =========================================================
# CONFIGURACIÓN / CONTROL
# =========================================================

func set_recharge_rate(value: float) -> void:
	current_recharge_rate = max(1.0, value)


func set_base_recharge_rate(value: float) -> void:
	base_recharge_rate = max(1.0, value)


func set_recovery_delay(value: float) -> void:
	recovery_delay_timer = max(0.0, value)


func reset_recovery_to_base() -> void:
	# Vuelve la configuración actual a la base por defecto.
	current_recharge_rate = base_recharge_rate
	recovery_delay_timer = base_recovery_delay


func fill_to_max() -> void:
	current_stamina = max_stamina
	_was_full = true
	changed.emit(current_stamina, max_stamina)
	became_full.emit()
