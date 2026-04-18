extends CharacterBody3D

# =========================
# CONFIGURACIÓN GENERAL
# =========================

@export var max_hp: int = 10
@export var speed: float = 6.0

# Qué tan rápido se frena el knockback
@export var knockback_drag: float = 18.0

# =========================
# NODOS / COMPONENTES
# =========================

# Luz de lámpara
@onready var weapon_light: OmniLight3D = $LightPivot/OmniLight3D

# Sistema de progreso
@onready var progress: PlayerProgress = $PlayerProgress

# Componente de armas
@onready var weapon_component: WeaponComponent = $WeaponComponent

# Efecto visual del dash
@onready var dash_smear: Sprite3D = $DashSmear

# Habilidad Sapukai
@onready var sapukai: SapukaiComponent = $SapukaiComponent

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
# HABILIDADES
# =========================

@onready var dash_skill: DashSkill = $DashSkill
@onready var stamina: StaminaComponent = $StaminaComponent

var is_dashing: bool = false
var dash_velocity: Vector3 = Vector3.ZERO
var dash_timer: float = 0.0
var last_input_dir: Vector2 = Vector2.DOWN

# =========================
# NODOS DE ESCENA
# =========================

@onready var camera: Camera3D = get_viewport().get_camera_3d()
@onready var sprites: Node3D = $Sprites
@onready var anim_sprite: AnimatedSprite3D = $Sprites/AnimatedSprite3D
@onready var cursor: Node3D = $Cursor
@onready var sapukai_sprite: Sprite3D = $Sprites/SapukaiSprite3D

# Nodo raíz visual del arma.
# La lógica del arma vive en WeaponComponent, pero este nodo sigue
# perteneciendo visualmente al player.
@onready var weapon_pivot: Node3D = $Weapon

# Sprite de luz falsa de la lámpara
@onready var light_sprite: Sprite3D = $Sprites/LampPivot/LightSprite3D

# =========================
# ESTADO INTERNO
# =========================

# Puntos de vida actuales
var hp: int = 10

# Estado de muerte
var is_dead := false

# Dirección actual de apuntado
var aim_angle := 0.0
var aim_dir := Vector3.ZERO

# Knockback acumulado
var knockback_velocity: Vector3 = Vector3.ZERO

# Referencia opcional a efectos de pantalla
var screen_fx: Node = null

# Tweens del dash smear
var dash_smear_tween: Tween
var dash_smear_spawn_timer: float = 0.0

# Intervalo de spawn entre ghosts del dash
@export var dash_smear_spawn_interval: float = 0.03

# =========================
# SEÑALES
# =========================

# Señal para avisar de que el HP cambió
signal hp_changed(current_hp: int, max_hp: int)

# Señal cuando usa una skill / arma
signal skill_used(slot_name: String)

func _ready() -> void:
	# Skills / progreso
	progress.skill_unlocked.connect(_on_skill_unlocked)

	# Vida inicial
	hp = max_hp
	hp_changed.emit(hp, max_hp)

	# Buscar una referencia opcional al nodo de efectos de pantalla
	screen_fx = get_tree().get_first_node_in_group("screen_fx")

	# Guardar la rotación base de la lámpara
	lamp_base_rotation = light_sprite.rotation

	# Arranca en idle
	anim_sprite.play("Idle")
	
	# Sapukai
	sapukai.sapukai_started.connect(_on_sapukai_started)
	sapukai.sapukai_ended.connect(_on_sapukai_ended)


func _physics_process(delta: float) -> void:
	# Si está muerto, no puede moverse ni atacar
	if is_dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# =========================
	# INPUT BASE
	# =========================
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if input_dir.length_squared() > 0.0:
		last_input_dir = input_dir.normalized()

	# Actualizar dirección hacia el mouse primero,
	# así aim_dir ya está fresco tanto para el dash como para las armas.
	update_cursor()
	update_pivot_light()

	# =========================
	# INPUT DASH
	# =========================
	if Input.is_action_just_pressed("dash"):
		var dash_dir := get_dash_direction_to_mouse()
		dash_skill.try_use(self, stamina, dash_dir)

	# =========================
	# MOVIMIENTO / DASH
	# =========================
	if is_dashing:
		dash_timer -= delta
		dash_smear_spawn_timer -= delta

		if dash_smear_spawn_timer <= 0.0:
			dash_smear_spawn_timer = dash_smear_spawn_interval
			spawn_dash_smear_ghost(dash_velocity.normalized())

		velocity = dash_velocity
		move_and_slide()

		if dash_timer <= 0.0:
			is_dashing = false
			dash_velocity = Vector3.ZERO
	else:
		var dir := Vector3(input_dir.x, 0.0, input_dir.y)

		# =========================================================
		# VELOCIDAD DE MOVIMIENTO (incluye Sapukai)
		# =========================================================
		#
		# Partimos de la velocidad base del player.
		var move_speed: float = speed

		# Si Sapukai está activo, aumentamos la velocidad.
		# El multiplicador vive en SapukaiComponent,
		# así mantenemos todo centralizado.
		if sapukai != null:
			move_speed *= sapukai.get_move_speed_mult()

		var move_velocity := dir * move_speed

		# Se suma el knockback al movimiento manual
		velocity = move_velocity + knockback_velocity
		move_and_slide()

	# Rotación / balanceo de la lámpara
	update_lamp_swing(delta, input_dir)

	# El knockback se frena gradualmente
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, knockback_drag * delta)

	# =========================
	# INPUT DE ATAQUE
	# =========================
	# Ataque principal: facón, siempre disponible
	if Input.is_action_just_pressed("facon") and not is_dashing:
		weapon_component.try_primary_attack()

	# Ataque secundario: escopeta, solo si fue aprendida
	# Acá asumimos que shotgun está mapeado al click derecho o tecla secundaria.
	if Input.is_action_just_pressed("escopeta"):
		weapon_component.try_start_shotgun_aim()
	
	if Input.is_action_just_released("escopeta"):
		weapon_component.release_shotgun()
		
	# Ataque terciario: boleadoras
	if Input.is_action_just_pressed("boleadoras"):
		weapon_component.try_start_boleadoras_aim()
	
	if Input.is_action_just_released("boleadoras"):
		weapon_component.release_boleadoras()
	
	# Activar modo Sapukai
	if Input.is_action_just_pressed("sapukai"):
		sapukai.try_activate()

	# =========================
	# VISUAL DEL ARMA
	# =========================
	# Cuando no está atacando, el arma acompaña el cursor.
	# Durante el ataque, el propio WeaponComponent controla el swing.
	weapon_component.update_weapon_idle()

	# =========================
	# ANIMACIÓN DEL PERSONAJE
	# =========================
	# Si no está atacando ni dashing, usar animación de caminar/idle.
	if not weapon_component.is_attacking and not is_dashing:
		update_animation(input_dir)


func start_dash(direction: Vector3, distance: float, duration: float) -> void:
	is_dashing = true
	dash_timer = duration
	dash_smear_spawn_timer = 0.0

	var dash_speed := distance / duration
	dash_velocity = direction * dash_speed

	# Opcional: cancelar knockback al arrancar dash
	knockback_velocity = Vector3.ZERO

	play_dash_smear(direction)


func get_dash_direction(input_dir: Vector2) -> Vector3:
	if input_dir.length_squared() > 0.0:
		last_input_dir = input_dir.normalized()
		return Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	if last_input_dir.length_squared() > 0.0:
		return Vector3(last_input_dir.x, 0.0, last_input_dir.y).normalized()

	return -global_transform.basis.z.normalized()


func get_dash_direction_to_mouse() -> Vector3:
	# aim_dir se actualiza en update_cursor()
	if aim_dir.length_squared() > 0.0001:
		return aim_dir.normalized()
	return Vector3.ZERO


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
	
	if is_sapukai_invulnerable():
		return

	dir.y = 0.0

	if dir.length_squared() <= 0.0001:
		return

	knockback_velocity = dir.normalized() * force


func apply_shotgun_recoil(dir: Vector3, force: float = 3.0) -> void:
	# Si está muerto, ignoramos recoil nuevo
	if is_dead:
		return

	# Si está dashing, mejor no sumar recoil
	# para no mezclar dos impulsos fuertes.
	if is_dashing:
		return

	dir.y = 0.0

	if dir.length_squared() <= 0.0001:
		return

	# En vez de pisar completamente el knockback actual,
	# sumamos un impulso corto.
	knockback_velocity += dir.normalized() * force


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


func die() -> void:
	# Evitar ejecutar la muerte más de una vez
	if is_dead:
		return

	is_dead = true

	# Frenar completamente el movimiento
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO

	# Delegar al componente el apagado visual / lógico del arma
	weapon_component.cancel_attack_visuals()

	# Ocultar el arma completa al morir
	weapon_pivot.visible = false

	# Ocultar lámpara al morir
	light_sprite.visible = false

	# Ocultar cursor para que no siga "apuntando"
	cursor.visible = false

	# Reproducir animación de muerte
	anim_sprite.play("Died")


func take_damage(amount: int) -> void:
	# Si ya está muerto, ignorar daño
	if is_dead:
		return

	# Durante Sapukai, el gaucho es inmune al daño.
	if is_sapukai_invulnerable():
		return

	hp = max(hp - amount, 0)
	hp_changed.emit(hp, max_hp)

	# Reintentar encontrar screen_fx si se perdió la referencia
	if not is_instance_valid(screen_fx):
		screen_fx = get_tree().get_first_node_in_group("screen_fx")

	# Reproducir feedback visual si existe
	if screen_fx and screen_fx.has_method("play_damage_feedback"):
		screen_fx.play_damage_feedback()
	
	# Aumenta furia al recibir daño (Sapukai)
	sapukai.add_fury_from_damage_taken(amount)

	# Si la vida llegó a 0 o menos, morir
	if hp <= 0:
		die()


func update_pivot_light() -> void:
	# Mueve la luz de la lámpara junto con la posición del mouse.
	# El facón sigue siendo el arma visual base, así que el componente
	# devuelve el radio de reposo correspondiente.
	var offset := Vector3(0.0, 0.8, weapon_component.get_current_weapon_radius())
	offset = offset.rotated(Vector3.UP, aim_angle)
	weapon_light.position = offset


func update_lamp_swing(delta: float, input_dir: Vector2) -> void:
	# Si está muerto, que vuelva a la posición normal
	if is_dead:
		light_sprite.rotation = light_sprite.rotation.lerp(lamp_base_rotation, lamp_return_speed * delta)
		return

	# Si el player se está moviendo, aplicamos balanceo
	if input_dir.length() > 0.0:
		lamp_swing_time += delta * lamp_swing_speed

		# Balanceo con seno
		var swing_angle_rad = deg_to_rad(lamp_swing_angle_deg) * sin(lamp_swing_time)

		# Partimos de la rotación base
		var target_rotation := lamp_base_rotation

		# Balancear en Z
		target_rotation.z += swing_angle_rad

		# Interpolación suave para evitar rigidez
		light_sprite.rotation = light_sprite.rotation.lerp(target_rotation, 10.0 * delta)
	else:
		# Si no se mueve, volver suavemente al centro
		light_sprite.rotation = light_sprite.rotation.lerp(lamp_base_rotation, lamp_return_speed * delta)


func _on_skill_unlocked(slot_name: String) -> void:
	match slot_name:
		"shotgun":
			weapon_component.learn_shotgun()
		"dash":
			dash_skill.learn()
		"boleadoras":
			weapon_component.learn_boleadoras()
		"sapukai":
			sapukai.unlock()


func play_dash_smear(direction: Vector3) -> void:
	if dash_smear_tween and dash_smear_tween.is_valid():
		dash_smear_tween.kill()

	var dir := direction.normalized()
	var back_offset := -dir * 0.7

	dash_smear.top_level = true
	dash_smear.visible = true
	dash_smear.modulate.a = 0.45

	# Posición global, no local
	dash_smear.global_position = global_position + Vector3(0.0, 0.8, 0.0) + back_offset

	# Rotación horizontal según la dirección del dash
	dash_smear.rotation = Vector3.ZERO
	dash_smear.rotation.y = atan2(dir.x, dir.z)

	# Escala tipo estela
	dash_smear.scale = Vector3(0.8, 1.0, 2.2)

	dash_smear_tween = create_tween()
	dash_smear_tween.parallel().tween_property(dash_smear, "modulate:a", 0.0, 1.12)
	dash_smear_tween.parallel().tween_property(dash_smear, "scale", Vector3(0.4, 1.0, 0.8), 1.12)

	await dash_smear_tween.finished
	dash_smear.visible = false
	dash_smear.top_level = false


func spawn_dash_smear_ghost(direction: Vector3) -> void:
	var dir := direction.normalized()
	var back_offset := -dir * 0.7

	var ghost := dash_smear.duplicate()
	get_parent().add_child(ghost)

	ghost.top_level = true
	ghost.visible = true
	ghost.modulate = dash_smear.modulate
	ghost.modulate.a = 0.35

	ghost.global_position = global_position + Vector3(0.0, 0.8, 0.0) + back_offset
	ghost.rotation = Vector3.ZERO
	ghost.rotation.y = atan2(dir.x, dir.z)
	ghost.scale = Vector3(0.8, 1.0, 2.2)

	var tween := create_tween()
	tween.parallel().tween_property(ghost, "modulate:a", 0.0, 0.18)
	tween.parallel().tween_property(ghost, "scale", Vector3(0.4, 1.0, 0.8), 0.18)

	await tween.finished
	ghost.queue_free()


func _on_sapukai_started():
	anim_sprite.modulate = Color(0.885, 0.064, 0.413, 1.0)
	sapukai_sprite.visible = true

func _on_sapukai_ended():
	anim_sprite.modulate = Color(1,1,1)
	sapukai_sprite.visible = false

func is_sapukai_invulnerable() -> bool:
	return sapukai != null and sapukai.is_active
