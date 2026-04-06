extends Area3D
class_name AttackHitbox

# Este hitbox ya no define daño fijo propio.
# Su trabajo es:
# - activarse / desactivarse cuando el arma lo indica
# - detectar enemigos válidos
# - evitar pegar múltiples veces al mismo objetivo durante el mismo swing
# - consultar al WeaponComponent cuánto daño y knockback aplicar

# Diccionario de objetivos ya golpeados durante el ataque actual.
# Usamos Dictionary como set simple: target -> true
var hit_targets := {}

# Indica si el golpe está actualmente activo.
# Aunque el CollisionShape se habilite/deshabilite, este flag agrega
# una capa extra de seguridad y deja la intención más clara.
var is_active: bool = false

# Referencia al player dueño del hitbox.
# Jerarquía asumida:
# Player
# ├─ WeaponComponent
# └─ Weapon
#    └─ Grip
#       └─ AttackHitbox
@onready var player: Node = get_parent().get_parent().get_parent()

# Referencia al componente de armas del player.
@onready var weapon_component: WeaponComponent = player.get_node("WeaponComponent")

# Referencia al collision shape del hitbox.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	# Arrancamos desactivados por seguridad.
	collision_shape.disabled = true

	# Detectar tanto cuerpos como áreas.
	# Esto permite compatibilidad con enemigos que entren como body
	# o con hurtboxes / áreas hijas.
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func begin_attack() -> void:
	# Arranca una nueva ventana de daño.
	# Limpiamos objetivos ya golpeados para este swing.
	is_active = true
	hit_targets.clear()
	collision_shape.disabled = false

	# Muy importante:
	# si cuando activamos el ataque ya había enemigos superpuestos,
	# también intentamos golpearlos.
	for body in get_overlapping_bodies():
		_try_hit(body)

	for area in get_overlapping_areas():
		_try_hit_from_area(area)


func end_attack() -> void:
	# Cierra la ventana de daño.
	is_active = false
	collision_shape.disabled = true


func _on_body_entered(body: Node) -> void:
	_try_hit(body)


func _on_area_entered(area: Area3D) -> void:
	_try_hit_from_area(area)


func _try_hit_from_area(area: Area3D) -> void:
	# Si el área expone explícitamente un owner de golpe,
	# lo usamos. Esto es ideal para hurtboxes.
	if area == null:
		return

	if area.has_method("get_hit_owner"):
		_try_hit(area.get_hit_owner())
	elif area.get_parent() != null:
		# Fallback simple: intentar con el padre del área.
		_try_hit(area.get_parent())


func _try_hit(target: Node) -> void:
	if not is_active:
		return

	if target == null:
		return

	# Mantener compatibilidad con tu enfoque actual:
	# solo pegamos a cosas del grupo enemy.
	if not target.is_in_group("enemy"):
		return

	# Evitar múltiples golpes al mismo objetivo durante el mismo swing.
	if hit_targets.has(target):
		return

	hit_targets[target] = true

	# Consultar datos del golpe actual al WeaponComponent.
	var damage: int = weapon_component.get_current_attack_damage()
	var knockback: float = weapon_component.get_current_attack_knockback()
	var hit_dir: Vector3 = weapon_component.get_current_attack_direction(target.global_position)

	# Aplicar daño si el objetivo lo soporta.
	if target.has_method("take_damage"):
		target.take_damage(damage)

	# Aplicar knockback si el objetivo lo soporta.
	if target.has_method("apply_knockback"):
		target.apply_knockback(hit_dir, knockback)
