extends Area3D
class_name BoleadoraProjectile

# =========================================================
# Boleadora Projectile
# - viaja en línea recta
# - desaparece al recorrer demasiada distancia
# - puede impactar bodies o areas
# - ignora al lanzador
# - si golpea un enemigo, lo inmoviliza
# =========================================================

@export var speed: float = 12.0
@export var max_distance: float = 18.0

# Dirección normalizada de viaje
var direction: Vector3 = Vector3.ZERO

# Posición inicial, usada para calcular distancia recorrida
var start_position: Vector3 = Vector3.ZERO

# Evita múltiples impactos
var has_hit: bool = false

# Nodo que disparó la boleadora
var shooter: Node = null

var source_weapon: WeaponComponent = null

func _ready() -> void:
	# Detecta colisión contra cuerpos físicos
	body_entered.connect(_on_body_entered)

	# Detecta colisión contra áreas, por ejemplo Hurtbox
	area_entered.connect(_on_area_entered)


# =========================================================
# Inicialización
# =========================================================
func setup(spawn_position: Vector3, launch_direction: Vector3, owner_node: Node = null, weapon: WeaponComponent = null) -> void:
	global_position = spawn_position
	start_position = spawn_position
	direction = launch_direction.normalized()
	shooter = owner_node
	source_weapon = weapon

	if direction.length_squared() > 0.0001:
		look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	if has_hit:
		return

	global_position += direction * speed * delta

	if global_position.distance_to(start_position) >= max_distance:
		queue_free()


# =========================================================
# Impacto con PhysicsBody3D
# =========================================================
func _on_body_entered(body: Node) -> void:
	if has_hit:
		return

	# Ignoramos al lanzador
	if body == shooter:
		return

	has_hit = true

	if body.is_in_group("enemy") and body.has_method("apply_boleadora_root"):
		body.apply_boleadora_root()

	queue_free()


# =========================================================
# Impacto con Area3D
# =========================================================
func _on_area_entered(area: Area3D) -> void:
	if has_hit:
		return

	# Si por alguna razón el área pertenece al shooter, la ignoramos
	if area == shooter:
		return

	# Caso típico:
	# el proyectil toca el Hurtbox del enemigo,
	# así que subimos al padre para encontrar el Enemy real.
	var target: Node = area.get_parent()

	if target.is_in_group("enemy") and target.has_method("apply_boleadora_root"):
		target.apply_boleadora_root()

		if source_weapon != null:
			source_weapon.register_boleadora_target(target)

		has_hit = true
		queue_free()
