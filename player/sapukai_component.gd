extends Node
class_name SapukaiComponent

# =========================================================
# SAPUKAI / FURIA
# =========================================================
#
# Este componente maneja el sistema base de Sapukai.
#
# En esta primera versión:
# - junta furia al recibir daño
# - permite activarse manualmente cuando la barra está llena
# - drena la barra mientras está activo
# - emite señales para que después puedas conectar UI / FX / sonido
#
# IMPORTANTE:
# Esta fase NO modifica todavía armas, daño ni velocidad del facón.
# Solo resuelve el "núcleo" del sistema.
# =========================================================


# =========================================================
# SEÑALES
# =========================================================

# Se emite cada vez que cambia la furia actual.
# Ideal para actualizar una barra en la UI.
signal fury_changed(current: float, max: float)

# Se emite al entrar en modo Sapukai.
signal sapukai_started()

# Se emite cuando Sapukai termina por quedarse sin furia.
signal sapukai_ended()


# =========================================================
# CONFIGURACIÓN
# =========================================================

# Valor máximo de la barra de furia.
@export var max_fury: float = 100.0

# Cuánta furia se gana por cada punto de daño recibido.
# Ejemplo:
# si amount = 2 y fury_gain_taken = 18,
# se suman 36 puntos de furia.
@export var fury_gain_taken: float = 18.0

# Cuánta furia se consume por segundo mientras Sapukai está activo.
@export var drain_per_second: float = 40.0


# =========================================================
# ESTADO INTERNO
# =========================================================

# Furia actual acumulada.
var current_fury: float = 0.0

# Indica si Sapukai está activo.
var is_active: bool = false


func _ready() -> void:
	# Emitimos el estado inicial por si la UI se conecta temprano
	# o si querés que la barra arranque correctamente sincronizada.
	fury_changed.emit(current_fury, max_fury)


func _process(delta: float) -> void:
	# Si Sapukai no está activo, no hay drenado.
	if not is_active:
		return

	# Consumimos furia con el paso del tiempo.
	current_fury -= drain_per_second * delta

	# Si se vació la barra, terminamos el modo Sapukai.
	if current_fury <= 0.0:
		current_fury = 0.0
		is_active = false

		# Primero avisamos el valor final,
		# después avisamos que el modo terminó.
		fury_changed.emit(current_fury, max_fury)
		sapukai_ended.emit()
		return

	# Mientras siga activo, seguimos notificando el valor actual.
	fury_changed.emit(current_fury, max_fury)


# =========================================================
# API PÚBLICA
# =========================================================

func add_fury_from_damage_taken(amount: int) -> void:
	# No sumar si el daño es inválido.
	if amount <= 0:
		return

	# Mientras Sapukai está activo, en esta versión
	# NO seguimos acumulando furia.
	if is_active:
		return

	current_fury = clamp(
		current_fury + float(amount) * fury_gain_taken,
		0.0,
		max_fury
	)

	fury_changed.emit(current_fury, max_fury)


func try_activate() -> bool:
	# No activar si ya está activo.
	if is_active:
		return false

	# Solo se puede activar con la barra llena.
	if current_fury < max_fury:
		return false

	is_active = true
	sapukai_started.emit()
	fury_changed.emit(current_fury, max_fury)
	return true


func deactivate() -> void:
	# Método opcional por si más adelante querés cancelarlo
	# manualmente desde otro sistema.
	if not is_active:
		return

	is_active = false
	sapukai_ended.emit()
	fury_changed.emit(current_fury, max_fury)


func reset_fury() -> void:
	# Resetea completamente el sistema.
	current_fury = 0.0
	is_active = false
	fury_changed.emit(current_fury, max_fury)


func is_full() -> bool:
	return current_fury >= max_fury


func get_fury_percent() -> float:
	if max_fury <= 0.0:
		return 0.0
	return current_fury / max_fury
