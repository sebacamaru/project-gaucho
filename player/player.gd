extends CharacterBody3D

# =========================
# CONFIGURACIÓN GENERAL
# =========================

@export var hp: float = 10
@export var speed: float = 6.0

# Distancia base del arma respecto al cuerpo
@export var weapon_radius: float = 1.0

# Ángulo total del slash
@export var swing_arc_deg: float = 180.0

# Duración de la parte principal del ataque
@export var swing_duration: float = 0.4

# Tiempo de regreso del arma a la posición de reposo
@export var return_duration: float = swing_duration / 10.0

# Qué tan rápido se frena el knockback
@export var knockback_drag: float = 18.0

# Cantidad máxima de puntos del trail del arma
@export var trail_max_points := 8

# Cuánto avanza el grip hacia adelante durante el ataque
@export var grip_attack_offset_z: float = 1

# Duración del tween que empuja el grip hacia adelante
@export var grip_push_duration: float = 0.08

# Duración del tween que devuelve el grip a su lugar
@export var grip_return_duration: float = 0.10

# Luz de lámpara
@onready var weapon_light: OmniLight3D = $LightPivot/OmniLight3D

# =========================
# BALANCEO DE LÁMPARA
# =========================

# Tiempo acumulado para la oscilación
var lamp_swing_time := 0.0

# Rotación base de la lámpara al iniciar
var lamp_base_rotation: Vector3

# Ángulo máximo del balanceo en grados
@export var lamp_swing_angle_deg: float = 24.0

# Velocidad del balanceo
@export var lamp_swing_speed: float = 10.0

# Qué tan rápido vuelve al centro cuando deja de moverse
@export var lamp_return_speed: float = 8.0


# =========================
# NODOS
# =========================

@onready var camera: Camera3D = get_viewport().get_camera_3d()
@onready var sprites: Node3D = $Sprites
@onready var anim_sprite: AnimatedSprite3D = $Sprites/AnimatedSprite3D
@onready var cursor: Node3D = $Cursor

@onready var weapon_pivot: Node3D = $Weapon
@onready var weapon_grip: Node3D = $Weapon/Grip
@onready var weapon_sprite: Sprite3D = $Weapon/Grip/Sprite3D
@onready var weapon_tip: Marker3D = $Weapon/Grip/Tip
@onready var trail: Line2D = $Trail
@onready var attack_hitbox: Area3D = $Weapon/Grip/AttackHitbox
@onready var light_sprite: Sprite3D = $Sprites/LampPivot/LightSprite3D


# =========================
# ESTADO INTERNO
# =========================

# Puntos 2D usados para dibujar el trail del arma
var trail_points := []

# Estado del ataque
var is_attacking := false

# Estado de muerte
var is_dead := false

# Dirección actual de apuntado
var aim_angle := 0.0
var attack_base_angle := 0.0
var swing_side := 1.0
var aim_dir := Vector3.ZERO

# Tween actual del swing del ataque
var attack_tween: Tween = null

# Tween usado para empujar/devolver el grip
var grip_tween: Tween = null

# Knockback acumulado
var knockback_velocity: Vector3 = Vector3.ZERO

# Referencia opcional a efectos de pantalla
var screen_fx: Node = null

# Posición original del grip.
# La guardamos para poder volver exactamente al lugar correcto.
var grip_base_position: Vector3


func _ready() -> void:
	# Buscar una referencia opcional al nodo de efectos de pantalla
	screen_fx = get_tree().get_first_node_in_group("screen_fx")

	# Guardar la posición base del grip al iniciar
	grip_base_position = weapon_grip.position
	
	# Guardar la posición de la rotación de la lámpara
	lamp_base_rotation = light_sprite.rotation


func _physics_process(delta: float) -> void:
	# Si está muerto, no puede moverse ni atacar
	if is_dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# =========================
	# MOVIMIENTO
	# =========================
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var dir := Vector3(input_dir.x, 0.0, input_dir.y)
	var move_velocity := dir * speed

	# Se suma el knockback al movimiento manual
	velocity = move_velocity + knockback_velocity
	move_and_slide()
	
	# Rotación de la lámpara
	update_lamp_swing(delta, input_dir)

	# El knockback se frena gradualmente
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, knockback_drag * delta)

	# Actualizar dirección hacia el mouse
	update_cursor()
	update_pivot_light()

	# Input de ataque
	if Input.is_action_just_pressed("attack"):
		start_attack()

	# Actualizar visual del arma según el estado
	if is_attacking:
		update_trail()
		update_weapon_attack()
	else:
		update_weapon_idle()

	# Si no está atacando, usar animación de caminar/idle
	if not is_attacking:
		update_animation(input_dir)


func update_cursor() -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	# Intersectar el rayo del mouse con un plano horizontal
	# a la altura actual del player
	var plane = Plane(Vector3.UP, global_position.y)
	var hit = plane.intersects_ray(ray_origin, ray_dir)

	if hit:
		var dir = hit - global_position
		dir.y = 0.0

		# Evitar normalizar vectores casi nulos
		if dir.length_squared() > 0.0001:
			aim_dir = dir.normalized()
			aim_angle = atan2(dir.x, dir.z)
			cursor.rotation.y = aim_angle
			handle_flip(dir)


func handle_flip(dir: Vector3) -> void:
	# El personaje se espeja según mire a izquierda o derecha
	var facing_left = dir.x < 0.0
	sprites.scale.x = 1.0 if facing_left else -1.0
	anim_sprite.flip_h = facing_left


func apply_knockback(dir: Vector3, force: float = 4.5) -> void:
	# Si está muerto, ignoramos knockback nuevo
	if is_dead:
		return

	dir.y = 0.0

	if dir.length_squared() <= 0.0001:
		return

	knockback_velocity = dir.normalized() * force


func update_weapon_idle() -> void:
	# En reposo, el arma acompaña la dirección del cursor
	weapon_pivot.rotation.y = aim_angle
	weapon_sprite.position = Vector3(0.0, 0.0, weapon_radius)


func start_attack() -> void:
	# No permitir atacar si está muerto
	if is_dead:
		return

	# Si había un tween de swing anterior, cancelarlo
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()

	# Si había un tween del grip anterior, cancelarlo
	if grip_tween and grip_tween.is_valid():
		grip_tween.kill()

	clear_trail()

	is_attacking = true
	attack_base_angle = aim_angle

	# Empujar el grip hacia adelante con un tween corto.
	# Esto le da al ataque una sensación de "avance" o "peso".
	grip_tween = create_tween()
	grip_tween.set_trans(Tween.TRANS_QUAD)
	grip_tween.set_ease(Tween.EASE_OUT)
	grip_tween.tween_property(
		weapon_grip,
		"position",
		grip_base_position + Vector3(0.0, 0.0, grip_attack_offset_z),
		grip_push_duration
	)

	# Reproducir animación de ataque
	anim_sprite.play("Attack")

	var half_arc = deg_to_rad(swing_arc_deg) * 0.5
	var start_angle: float
	var end_angle: float

	# Elegir sentido del swing según hacia qué lado apunta
	swing_side = -1.0 if aim_dir.x >= 0.0 else 1.0

	if swing_side > 0.0:
		start_angle = attack_base_angle - half_arc
		end_angle = attack_base_angle + half_arc
	else:
		start_angle = attack_base_angle + half_arc
		end_angle = attack_base_angle - half_arc

	# Colocar el arma en el inicio del swing
	update_weapon_swing(start_angle)

	var tween = create_tween()
	attack_tween = tween

	# Ida del slash
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_method(update_weapon_swing, start_angle, end_angle, swing_duration)

	# Vuelta al centro
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_method(update_weapon_swing, end_angle, attack_base_angle, return_duration)

	# Activar hitbox un poco después de iniciar el swing
	await get_tree().create_timer(0.05).timeout
	if is_dead:
		return
	attack_hitbox.begin_attack()

	# Desactivar hitbox un rato después
	await get_tree().create_timer(0.1).timeout
	if is_dead:
		return
	attack_hitbox.end_attack()

	# Esperar a que termine el swing completo
	await tween.finished

	# Si murió durante el ataque, cortar acá
	if is_dead:
		return

	clear_trail()
	is_attacking = false

	# Devolver el grip suavemente a su posición original
	if grip_tween and grip_tween.is_valid():
		grip_tween.kill()

	grip_tween = create_tween()
	grip_tween.set_trans(Tween.TRANS_QUAD)
	grip_tween.set_ease(Tween.EASE_OUT)
	grip_tween.tween_property(
		weapon_grip,
		"position",
		grip_base_position,
		grip_return_duration
	)


func update_weapon_attack() -> void:
	# El tween del swing ya se encarga del movimiento principal del arma.
	# Esta función queda libre para sumar después:
	# - partículas
	# - brillo
	# - smear
	# - rotación extra del sprite
	pass


func update_weapon_swing(angle: float) -> void:
	# El pivot rota alrededor del player y el sprite se mantiene a una
	# distancia fija definida por weapon_radius
	weapon_pivot.rotation.y = angle
	weapon_sprite.position = Vector3(0.0, 0.0, weapon_radius)


func update_animation(input_dir: Vector2) -> void:
	# No tocar animaciones de locomoción si está muerto
	if is_dead:
		return

	if input_dir.length() > 0.0:
		if anim_sprite.animation != "Walk":
			anim_sprite.play("Walk")
	else:
		if anim_sprite.animation != "Idle":
			anim_sprite.play("Idle")


func get_weapon_tip_position() -> Vector3:
	return weapon_tip.global_transform.origin


func update_trail() -> void:
	var pos3d = get_weapon_tip_position()

	# Si el tip del arma está detrás de la cámara, no dibujar trail
	if camera.is_position_behind(pos3d):
		return

	var pos2d = camera.unproject_position(pos3d)
	trail_points.push_front(pos2d)

	if trail_points.size() > trail_max_points:
		trail_points.pop_back()

	trail.points = PackedVector2Array(trail_points)


func clear_trail() -> void:
	trail_points.clear()
	trail.points = PackedVector2Array()


func die() -> void:
	# Evitar ejecutar la muerte más de una vez
	if is_dead:
		return

	is_dead = true
	is_attacking = false

	# Frenar completamente el movimiento
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO

	# Limpiar efectos visuales del ataque
	clear_trail()

	# Cancelar tween del swing si seguía activo
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()

	# Cancelar tween del grip si seguía activo
	if grip_tween and grip_tween.is_valid():
		grip_tween.kill()

	# Asegurarnos de que el grip vuelva a su posición base
	# por si murió en medio del ataque
	weapon_grip.position = grip_base_position

	# Apagar hitbox por seguridad
	if attack_hitbox.has_method("end_attack"):
		attack_hitbox.end_attack()

	# Ocultar el arma completa al morir
	weapon_pivot.visible = false
	
	# Ocultar lámpara al morir
	light_sprite.visible = false

	# Opcional: ocultar el cursor para que no siga "apuntando"
	cursor.visible = false

	# Reproducir animación de muerte
	anim_sprite.play("Died")


func take_damage(amount: int) -> void:
	# Si ya está muerto, ignorar daño
	if is_dead:
		return

	hp -= amount

	# Reintentar encontrar screen_fx si se perdió la referencia
	if not is_instance_valid(screen_fx):
		screen_fx = get_tree().get_first_node_in_group("screen_fx")

	# Reproducir feedback visual si existe
	if screen_fx and screen_fx.has_method("play_damage_feedback"):
		screen_fx.play_damage_feedback()

	print("HP:", hp)

	# Si la vida llegó a 0 o menos, morir
	if hp <= 0:
		die()

func update_pivot_light() -> void:
	# Mueve la luz de la lámpara junto con la posición del mouse
	var offset := Vector3(0.0, 0.8, weapon_radius)
	offset = offset.rotated(Vector3.UP, aim_angle)
	weapon_light.position = offset

func update_lamp_swing(delta: float, input_dir: Vector2) -> void:
	# Si está muerto, que vuelva a la posición normal
	if is_dead:
		
		rotation = light_sprite.rotation.lerp(lamp_base_rotation, lamp_return_speed * delta)
		return

	# Si el player se está moviendo, aplicamos balanceo
	if input_dir.length() > 0.0:
		lamp_swing_time += delta * lamp_swing_speed
		# Balanceo con seno
		var swing_angle_rad = deg_to_rad(lamp_swing_angle_deg) * sin(lamp_swing_time)
		# Partimos de la rotación base
		var target_rotation = lamp_base_rotation
		# Balancear en Z
		target_rotation.z += swing_angle_rad
		# Interpolación suave para evitar rigidez
		light_sprite.rotation = light_sprite.rotation.lerp(target_rotation, 10.0 * delta)
	else:
		# Si no se mueve, volver suavemente al centro
		light_sprite.rotation = light_sprite.rotation.lerp(lamp_base_rotation, lamp_return_speed * delta)
