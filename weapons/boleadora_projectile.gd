extends Area3D
class_name BoleadoraProjectile

# =========================================================
# Boleadora Projectile
# - viaja en línea recta
# - desaparece al recorrer demasiada distancia
# - puede impactar bodies o areas
# - ignora al lanzador
# - si golpea un enemigo, lo inmoviliza
# - rota visualmente el sprite mientras viaja
# =========================================================


# =========================================================
# CONFIGURACIÓN GENERAL
# =========================================================

@export var speed: float = 12.0
@export var max_distance: float = 18.0


# =========================================================
# CONFIGURACIÓN VISUAL
# =========================================================

# Nodo visual que queremos rotar.
# Normalmente sería un Sprite3D hijo del proyectil.
#
# Estructura esperada:
# BoleadoraProjectile
# ├── CollisionShape3D
# └── Sprite3D
#
# Si tu Sprite3D tiene otro nombre, podés cambiarlo desde el Inspector.
@export var visual_path: NodePath = ^"Sprite3D"

# Velocidad de giro en grados por segundo.
# 360 = una vuelta completa por segundo.
# 720 = dos vueltas por segundo.
@export var spin_speed_degrees: float = 720.0

# Referencia al nodo visual.
@onready var visual_node: Node3D = get_node_or_null(visual_path) as Node3D


# =========================================================
# ESTADO INTERNO
# =========================================================

# Dirección normalizada de viaje.
var direction: Vector3 = Vector3.ZERO

# Posición inicial, usada para calcular distancia recorrida.
var start_position: Vector3 = Vector3.ZERO

# Evita múltiples impactos.
var has_hit: bool = false

# Nodo que disparó la boleadora.
var shooter: Node = null

# Arma que disparó la boleadora.
# La usamos para registrar enemigos atrapados.
var source_weapon: WeaponComponent = null


func _ready() -> void:
	# Detecta colisión contra cuerpos físicos.
	body_entered.connect(_on_body_entered)

	# Detecta colisión contra áreas, por ejemplo Hurtbox.
	area_entered.connect(_on_area_entered)


# =========================================================
# Inicialización
# =========================================================

func setup(
	spawn_position: Vector3,
	launch_direction: Vector3,
	owner_node: Node = null,
	weapon: WeaponComponent = null
) -> void:
	global_position = spawn_position
	start_position = spawn_position
	direction = launch_direction.normalized()
	shooter = owner_node
	source_weapon = weapon

	# Orientamos el proyectil hacia la dirección de lanzamiento.
	if direction.length_squared() > 0.0001:
		look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	if has_hit:
		return

	# Rotamos solamente el sprite visual.
	# No rotamos el Area3D entero para no afectar la colisión.
	_rotate_visual(delta)

	# Movimiento recto.
	global_position += direction * speed * delta

	# Si recorrió demasiada distancia, desaparece.
	if global_position.distance_to(start_position) >= max_distance:
		queue_free()


# =========================================================
# Rotación visual
# =========================================================

func _rotate_visual(delta: float) -> void:
	if visual_node == null:
		return

	if is_zero_approx(spin_speed_degrees):
		return

	# Rotamos sobre el eje Z local del sprite.
	# Esto genera el efecto de "girar sobre sí mismo", como una moneda/plano 2D.
	visual_node.rotation_degrees.z = wrapf(
		visual_node.rotation_degrees.z + spin_speed_degrees * delta,
		0.0,
		360.0
	)


# =========================================================
# Impacto con PhysicsBody3D
# =========================================================

func _on_body_entered(body: Node) -> void:
	if has_hit:
		return

	# Ignoramos al lanzador.
	if body == shooter:
		return

	has_hit = true

	if body.is_in_group("enemy") and body.has_method("apply_boleadora_root"):
		body.apply_boleadora_root()

		if source_weapon != null:
			source_weapon.register_boleadora_target(body)

	queue_free()


# =========================================================
# Impacto con Area3D
# =========================================================

func _on_area_entered(area: Area3D) -> void:
	if has_hit:
		return

	# Si por alguna razón el área pertenece al shooter, la ignoramos.
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
