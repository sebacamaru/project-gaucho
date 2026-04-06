extends Node
class_name DashSkill

# -----------------------------------------------------------------------------
# Señales
# -----------------------------------------------------------------------------

# Se dispara cuando la skill se aprende por primera vez.
signal unlocked()

# Se dispara cada vez que la skill sube de nivel.
signal upgraded(new_level: int)

# -----------------------------------------------------------------------------
# Configuración
# -----------------------------------------------------------------------------

# Distancia base del dash al nivel 1.
@export var base_distance: float = 3.0

# Cuánto aumenta la distancia por cada nivel adicional.
# Ej:
# lvl 1 = 3.0
# lvl 2 = 3.35
# lvl 3 = 3.7
@export var distance_per_level: float = 0.35

# Duración fija del dash.
# Más bajo = dash más rápido / explosivo.
@export var dash_duration: float = 0.12

# Nombre del slot de UI que representa esta skill.
# Lo dejamos configurable por si después reutilizás este patrón.
@export var slot_name: String = "dash"

@export var stamina_recharge_rate: float = 80.0
@export var stamina_recovery_delay: float = 0.35

# -----------------------------------------------------------------------------
# Estado interno
# -----------------------------------------------------------------------------

# Indica si la skill ya fue aprendida.
var is_unlocked: bool = false

# Nivel actual de la skill.
# 0 = bloqueada
# 1 = aprendida
# 2+ = mejorada
var level: int = 0

# -----------------------------------------------------------------------------
# Progresión
# -----------------------------------------------------------------------------

func learn() -> void:
	# Si ya estaba desbloqueada, en lugar de hacer nada
	# la tratamos como mejora.
	if is_unlocked:
		upgrade()
		return

	is_unlocked = true
	level = 1

	unlocked.emit()


func upgrade() -> void:
	# Si aún no fue aprendida, primero la aprendemos.
	if not is_unlocked:
		learn()
		return

	level += 1
	upgraded.emit(level)


# -----------------------------------------------------------------------------
# Estadísticas
# -----------------------------------------------------------------------------

func get_distance() -> float:
	# Calcula la distancia final según el nivel.
	# Nivel 1 = base_distance
	# Nivel 2+ = aumenta progresivamente
	return base_distance + distance_per_level * float(level - 1)


# -----------------------------------------------------------------------------
# Uso de la skill
# -----------------------------------------------------------------------------

func try_use(player: Node, stamina: StaminaComponent, dash_dir: Vector3) -> bool:
	# La skill debe estar aprendida.
	if not is_unlocked:
		return false

	# La barra de dash / stamina debe estar completamente cargada.
	if stamina == null or not stamina.is_full():
		return false

	# Evita usar dash sin dirección válida.
	if dash_dir.length_squared() <= 0.0001:
		return false

	# Consume toda la barra (cooldown visual).
	stamina.empty_and_configure_recovery(
		stamina_recharge_rate,
		stamina_recovery_delay
	)

	# Ejecuta el dash físico en el player.
	player.start_dash(
		dash_dir.normalized(),
		get_distance(),
		dash_duration
	)

	# Notifica al HUD para animar el slot correspondiente.
	player.skill_used.emit(slot_name)

	return true
