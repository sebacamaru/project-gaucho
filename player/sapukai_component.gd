extends Node
class_name SapukaiComponent

# =========================================================
# SAPUKAI / FURIA
# =========================================================
#
# Este componente maneja el sistema base de Sapukai.
#
# En esta versión:
# - puede estar bloqueado o desbloqueado
# - junta furia al recibir daño
# - junta furia al hacer daño (menos que al recibir)
# - permite activarse manualmente cuando la barra está llena
# - drena la barra mientras está activo
# - emite señales para UI / FX / sonido
#
# IMPORTANTE:
# Este componente NO aplica por sí mismo buffs de combate.
# Solo maneja:
# - el recurso "furia"
# - el estado activo / inactivo
# - el estado bloqueado / desbloqueado
# =========================================================


# =========================================================
# SEÑALES
# =========================================================

# Se emite cada vez que cambia la furia actual.
# Ideal para actualizar una barra en la UI.
signal fury_changed(current: float, max: float)

# Se emite al entrar en modo Sapukai.
signal sapukai_started()

# Se emite cuando Sapukai termina por quedarse sin furia
# o cuando se desactiva manualmente.
signal sapukai_ended()


# =========================================================
# CONFIGURACIÓN
# =========================================================

# Indica si Sapukai arranca ya aprendido.
# Para gameplay normal probablemente quieras false.
# Para testing rápido podés poner true.
@export var starts_unlocked: bool = false

# Con cuánto arranca la barra de furia.
# Útil para testing, balance o perks futuros.
# Solo se aplica si Sapukai está desbloqueado.
@export var starting_fury: float = 100.0

# Valor máximo de la barra de furia.
@export var max_fury: float = 100.0

# Cuánta furia se gana por cada punto de daño recibido.
# Ejemplo:
# si amount = 2 y fury_gain_taken = 18,
# se suman 36 puntos de furia.
@export var fury_gain_taken: float = 18.0

# Cuánta furia se gana por cada punto de daño infligido.
# Normalmente debería ser bastante menor que fury_gain_taken
# para que Sapukai premie la agresividad, pero sin cargarse demasiado fácil.
@export var fury_gain_dealt: float = 6.0

# Cuánta furia se consume por segundo mientras Sapukai está activo.
@export var drain_per_second: float = 40.0

# Multiplicador de velocidad de movimiento mientras Sapukai está activo.
@export var move_speed_mult: float = 1.8


# =========================================================
# ESTADO INTERNO
# =========================================================

# Furia actual acumulada.
var current_fury: float = 0.0

# Indica si Sapukai está activo.
var is_active: bool = false

# Indica si la skill ya fue aprendida / desbloqueada.
# Mientras sea false:
# - no acumula furia
# - no puede activarse
# - la barra debería quedar vacía
var is_unlocked: bool = false


func _ready() -> void:
	# Inicializamos el estado de desbloqueo desde el export.
	is_unlocked = starts_unlocked

	# Si arranca desbloqueado, respetamos la furia inicial.
	# Si no, arranca completamente vacío.
	if is_unlocked:
		current_fury = clamp(starting_fury, 0.0, max_fury)
	else:
		current_fury = 0.0

	# Emitimos el estado inicial para que la UI arranque sincronizada.
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

func unlock() -> void:
	# Desbloquea Sapukai si todavía no estaba aprendido.
	if is_unlocked:
		return

	is_unlocked = true

	# Al desbloquear, dejamos la furia en el valor inicial configurado.
	current_fury = clamp(starting_fury, 0.0, max_fury)

	# Nos aseguramos de arrancar en modo inactivo.
	is_active = false

	# Notificamos a la UI.
	fury_changed.emit(current_fury, max_fury)


func get_move_speed_mult() -> float:
	# Solo da bonus de movimiento si Sapukai está realmente activo.
	if is_active:
		return move_speed_mult
	return 1.0


func add_fury_from_damage_taken(amount: int) -> void:
	# Si la skill todavía no fue aprendida, no acumulamos nada.
	if not is_unlocked:
		return

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


func add_fury_from_damage_dealt(amount: int) -> void:
	# Si la skill todavía no fue aprendida, no acumulamos nada.
	if not is_unlocked:
		return

	# No sumar si el daño es inválido.
	if amount <= 0:
		return

	# Mientras Sapukai está activo, en esta versión
	# NO seguimos acumulando furia.
	if is_active:
		return

	current_fury = clamp(
		current_fury + float(amount) * fury_gain_dealt,
		0.0,
		max_fury
	)

	fury_changed.emit(current_fury, max_fury)


func try_activate() -> bool:
	# No activar si la skill todavía no fue aprendida.
	if not is_unlocked:
		return false

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
	# Resetea completamente la barra.
	# No cambia si está desbloqueado o no.
	current_fury = 0.0
	is_active = false
	fury_changed.emit(current_fury, max_fury)


func is_full() -> bool:
	return current_fury >= max_fury


func get_fury_percent() -> float:
	if max_fury <= 0.0:
		return 0.0
	return current_fury / max_fury
