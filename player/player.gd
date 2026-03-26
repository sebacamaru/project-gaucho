extends CharacterBody3D

@export var hp: float = 10
@export var speed: float = 6.0
@export var weapon_radius: float = 1
@export var swing_arc_deg: float = 180.0
@export var swing_duration: float = 0.4
@export var return_duration: float = swing_duration / 10
@export var knockback_drag: float = 18.0

@onready var camera: Camera3D = get_viewport().get_camera_3d()
@onready var sprites: Node3D = $Sprites
@onready var anim_sprite: AnimatedSprite3D = $Sprites/AnimatedSprite3D
@onready var cursor: Node3D = $Cursor

@onready var weapon_pivot: Node3D = $Weapon
@onready var weapon_grip: Node3D = $Weapon/Grip
@onready var weapon_sprite: Sprite3D = $Weapon/Grip/Sprite3D
@onready var weapon_tip: Marker3D = $Weapon/Grip/Tip
@onready var trail: Line2D = $Trail
@onready var attack_hitbox: Area3D = $Weapon/AttackHitbox

var trail_points := []
@export var trail_max_points := 8

var is_attacking := false
var aim_angle := 0.0
var attack_base_angle := 0.0
var swing_side := 1.0
var aim_dir := Vector3.ZERO
var attack_tween: Tween = null
var knockback_velocity: Vector3 = Vector3.ZERO
var screen_fx: Node = null

func _ready() -> void:
	screen_fx = get_tree().get_first_node_in_group("screen_fx")

func _physics_process(delta):
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var dir := Vector3(input_dir.x, 0.0, input_dir.y)
	var move_velocity := dir * speed
	
	velocity = move_velocity + knockback_velocity
	move_and_slide()
	
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, knockback_drag * delta)

	update_cursor()

	if Input.is_action_just_pressed("attack"):
		start_attack()

	if is_attacking:
		update_trail()
		update_weapon_attack()
	else:
		update_weapon_idle()

	if not is_attacking:
		update_animation(input_dir)

func update_cursor():
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	# Plano horizontal a la altura del player
	var plane = Plane(Vector3.UP, global_position.y)
	var hit = plane.intersects_ray(ray_origin, ray_dir)

	if hit:
		var dir = hit - global_position
		dir.y = 0.0

		if dir.length_squared() > 0.0001:
			aim_dir = dir.normalized()
			aim_angle = atan2(dir.x, dir.z)
			cursor.rotation.y = aim_angle
			handle_flip(dir)

func handle_flip(dir: Vector3):
	var facing_left = dir.x < 0.0
	sprites.scale.x = 1.0 if facing_left else -1.0
	anim_sprite.flip_h = facing_left

func apply_knockback(dir: Vector3, force: float = 4.5) -> void:
	dir.y = 0.0
	
	if dir.length_squared() <= 0.0001:
		return
	
	knockback_velocity = dir.normalized() * force

func update_weapon_idle():
	weapon_pivot.rotation.y = aim_angle
	weapon_sprite.position = Vector3(0.0, 0.0, weapon_radius)

func start_attack():
	# Cancelar tween anterior si existe
	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()
	
	clear_trail()
	
	is_attacking = true
	attack_base_angle = aim_angle

	anim_sprite.play("Attack")

	var half_arc = deg_to_rad(swing_arc_deg) * 0.5
	var start_angle: float
	var end_angle: float
	
	# Elegir el sentido según la dirección apuntada
	swing_side = -1.0 if aim_dir.x >= 0.0 else 1.0

	if swing_side > 0.0:
		start_angle = attack_base_angle - half_arc
		end_angle = attack_base_angle + half_arc
	else:
		start_angle = attack_base_angle + half_arc
		end_angle = attack_base_angle - half_arc

	update_weapon_swing(start_angle)
	
	var tween = create_tween()

	# Slash principal
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_method(update_weapon_swing, start_angle, end_angle, swing_duration)
	# Vuelta
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_method(update_weapon_swing, end_angle, attack_base_angle, return_duration)

	# Activación de hitbox
	await get_tree().create_timer(0.05).timeout
	attack_hitbox.begin_attack()

	await get_tree().create_timer(0.1).timeout
	attack_hitbox.end_attack()

	await tween.finished
	
	clear_trail()
	
	is_attacking = false

func update_weapon_attack():
	# Durante el ataque, el tween controla el swing.
	pass

func update_weapon_swing(angle: float):
	weapon_pivot.rotation.y = angle
	weapon_sprite.position = Vector3(0.0, 0.0, weapon_radius)

func update_animation(input_dir: Vector2):
	if input_dir.length() > 0.0:
		if anim_sprite.animation != "Walk":
			anim_sprite.play("Walk")
	else:
		if anim_sprite.animation != "Idle":
			anim_sprite.play("Idle")
			
func get_weapon_tip_position() -> Vector3:
	return weapon_tip.global_transform.origin

func update_trail():
	var pos3d = get_weapon_tip_position()
	if camera.is_position_behind(pos3d):
		return

	var pos2d = camera.unproject_position(pos3d)
	trail_points.push_front(pos2d)

	if trail_points.size() > trail_max_points:
		trail_points.pop_back()

	trail.points = PackedVector2Array(trail_points)

func clear_trail():
	trail_points.clear()
	trail.points = PackedVector2Array()
	
func take_damage(amount: int) -> void:
	hp -= amount
	
	if not is_instance_valid(screen_fx):
		screen_fx = get_tree().get_first_node_in_group("screen_fx")
	
	if screen_fx and screen_fx.has_method("play_damage_feedback"):
		screen_fx.play_damage_feedback()
	
	print("HP:", hp)
