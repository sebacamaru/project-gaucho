extends Node
class_name WeaponComponent

# Este componente centraliza la lógica de combate del player.
#
# Diseño actual:
# - Facón:
#   - ataque primario
#   - NO usa stamina
#   - tiene cooldown propio
#
# - Escopeta:
#   - ataque secundario en 2 fases
#   - mantener botón derecho = apuntar
#   - soltar botón derecho = consumir stamina y disparar
#
# Objetivos de esta versión:
# - que el facón siga siendo rápido y divertido
# - que dash / escopeta no bloqueen el facón por culpa de la stamina
# - mantener la escopeta como ataque más pesado y comprometido

signal attack_started(weapon_name: String)
signal attack_finished(weapon_name: String)

# =========================================================
# CONFIGURACIÓN GENERAL
# =========================================================

@export var trail_max_points: int = 8
@export var facon_level: int = 1
@export var shotgun_unlocked: bool = false
@export var boleadoras_unlocked: bool = false

# =========================================================
# ESTADO INTERNO
# =========================================================

# Indica si hay una acción ofensiva real en ejecución.
# Ejemplo:
# - swing del facón
# - secuencia de disparo de la escopeta
var is_attacking: bool = false

# Indica si la escopeta está en modo apuntado.
# Mientras esto sea true:
# - la escopeta frontal está visible
# - sigue al mouse
# - todavía no consumió stamina
var is_shotgun_aiming: bool = false

# Cooldown propio del facón.
# Es independiente de la stamina.
var facon_cooldown_timer: float = 0.0

var attack_tween: Tween = null
var grip_tween: Tween = null

var trail_points: Array[Vector2] = []

var grip_base_position: Vector3
var grip_base_rotation: Vector3

# Pose global temporal de la escopeta en la espalda.
# La usamos como punto inicial / final visual.
var shotgun_back_global_transform: Transform3D

# Datos del golpe actualmente activo del facón.
# El hitbox melee consulta estos valores.
var current_attack_damage: int = 0
var current_attack_knockback: float = 0.0

# =========================================================
# STATS BASE DEL FACÓN
# =========================================================

# Nota:
# Sacamos todo lo relacionado a stamina.
# El facón ahora se regula con cooldown propio.
var facon_base_stats := {
	"damage": 1,
	"knockback": 4.5,
	"swing_arc_deg": 180.0,
	"swing_duration": 0.40,
	"return_duration": 0.04,
	"weapon_radius": 1.0,
	"grip_attack_offset_z": 1.0,
	"grip_push_duration": 0.08,
	"grip_return_duration": 0.10,
	"hitbox_start_delay": 0.05,
	"hitbox_active_time": 0.10,

	# Cooldown posterior al ataque.
	# Empieza cuando termina el facón.
	"cooldown": 0.10,
}

# =========================================================
# STATS BASE DE LA ESCOPETA
# =========================================================

var shotgun_base_stats := {
	"damage": 2,
	"knockback": 6.5,
	"stamina_recharge_rate": 122.0,
	"stamina_recovery_delay": 0.60,
	"range": 5.0,
	"cone_angle_deg": 55.0,
	"windup": 0.08,
	"draw_duration": 0.18,
	"holster_duration": 0.18,
}

# =========================================================
# REFERENCIAS
# =========================================================

@onready var player := get_parent()
@onready var camera: Camera3D = player.get_viewport().get_camera_3d()

@onready var weapon_pivot: Node3D = player.get_node("Weapon")
@onready var weapon_grip: Node3D = player.get_node("Weapon/Grip")

@onready var facon_sprite: Sprite3D = player.get_node("Weapon/Grip/FaconSprite3D")
@onready var shotgun_front_sprite: Sprite3D = player.get_node("Weapon/Grip/ShotgunSprite3D")

@onready var shotgun_back_pivot: Node3D = player.get_node("Sprites/ShotgunPivot")
@onready var shotgun_back_sprite: Sprite3D = player.get_node("Sprites/ShotgunPivot/ShotgunSprite3D")

@onready var shotgun_muzzle: Marker3D = player.get_node("Weapon/Grip/Muzzle")
@onready var weapon_tip: Marker3D = player.get_node("Weapon/Grip/Tip")
@onready var attack_hitbox: Area3D = player.get_node("Weapon/Grip/AttackHitbox")

@onready var trail: Line2D = player.get_node("Trail")
@onready var anim_sprite: AnimatedSprite3D = player.get_node("Sprites/AnimatedSprite3D")
@onready var muzzle_flash: Sprite3D = player.get_node("Weapon/Grip/Muzzle/MuzzleFlash")
@onready var muzzle_flash_light: OmniLight3D = player.get_node("Weapon/Grip/Muzzle/MuzzleFlashLight")
@onready var muzzle_smoke: Sprite3D = player.get_node("Weapon/Grip/Muzzle/MuzzleSmoke")
@onready var shotgun_preview: ShotgunPreview = player.get_node("ShotgunPreview")


func _ready() -> void:
	if muzzle_flash_light:
		muzzle_flash_light.light_energy = 0.0

	# Configuramos el preview visual de la escopeta
	# usando los mismos stats reales del arma.
	if shotgun_preview:
		var shotgun_stats := get_shotgun_stats()
		shotgun_preview.configure(
			float(shotgun_stats["range"]),
			float(shotgun_stats["cone_angle_deg"])
		)

	grip_base_position = weapon_grip.position
	grip_base_rotation = weapon_grip.rotation

	show_facon_visual()
	update_shotgun_back_visual()


func _physics_process(delta: float) -> void:
	# Cooldown propio del facón.
	if facon_cooldown_timer > 0.0:
		facon_cooldown_timer = max(facon_cooldown_timer - delta, 0.0)

	# Solo el facón usa trail.
	if is_attacking and current_attack_damage > 0:
		update_trail()

	# Mientras estamos apuntando con la escopeta,
	# actualizamos la pose continuamente para que siga al mouse.
	if is_shotgun_aiming:
		update_shotgun_aim_pose()
		update_shotgun_preview()


# =========================================================
# VALIDACIONES DE USO
# =========================================================

# Chequeo específico del facón.
# No depende de stamina.
func can_start_facon_attack() -> bool:
	if is_attacking:
		return false

	if is_shotgun_aiming:
		return false

	if facon_cooldown_timer > 0.0:
		return false

	if player.is_dead:
		return false

	return true


# Chequeo específico de la escopeta.
# La escopeta sí sigue atada a la stamina.
func can_start_shotgun_action() -> bool:
	if is_attacking:
		return false

	if is_shotgun_aiming:
		return false

	if player.is_dead:
		return false

	return true


# =========================================================
# FACÓN
# =========================================================

func try_primary_attack() -> bool:
	# El facón ya no usa stamina.
	if not can_start_facon_attack():
		return false

	start_facon_attack()
	return true


func get_facon_stats() -> Dictionary:
	var stats: Dictionary = facon_base_stats.duplicate()

	match facon_level:
		1:
			pass
		2:
			stats["damage"] += 1
		3:
			stats["damage"] += 1
			stats["cooldown"] = 0.08
		4:
			stats["swing_arc_deg"] += 20.0
		5:
			stats["damage"] += 2
			stats["knockback"] += 0.5
			stats["cooldown"] = 0.06

	return stats


func start_facon_attack() -> void:
	var stats := get_facon_stats()

	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()

	if grip_tween and grip_tween.is_valid():
		grip_tween.kill()

	clear_trail()
	is_attacking = true

	current_attack_damage = int(stats["damage"])
	current_attack_knockback = float(stats["knockback"])

	player.skill_used.emit("skill_1")
	attack_started.emit("facon")

	# Visual frontal del facón
	show_facon_visual()

	# Pequeño empuje hacia adelante del grip.
	grip_tween = create_tween()
	grip_tween.set_trans(Tween.TRANS_QUAD)
	grip_tween.set_ease(Tween.EASE_OUT)
	grip_tween.tween_property(
		weapon_grip,
		"position",
		grip_base_position + Vector3(0.0, 0.0, float(stats["grip_attack_offset_z"])),
		float(stats["grip_push_duration"])
	)

	anim_sprite.play("Attack")

	var attack_base_angle: float = player.aim_angle
	var aim_dir: Vector3 = player.aim_dir

	var half_arc: float = deg_to_rad(float(stats["swing_arc_deg"])) * 0.5
	var start_angle: float
	var end_angle: float

	# Elegimos lado del swing según hacia dónde mira el jugador.
	var swing_side := -1.0 if aim_dir.x >= 0.0 else 1.0

	if swing_side > 0.0:
		start_angle = attack_base_angle - half_arc
		end_angle = attack_base_angle + half_arc
	else:
		start_angle = attack_base_angle + half_arc
		end_angle = attack_base_angle - half_arc

	update_weapon_swing(start_angle, float(stats["weapon_radius"]))

	var tween := create_tween()
	attack_tween = tween

	# Ida del golpe.
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(angle: float) -> void:
			update_weapon_swing(angle, float(stats["weapon_radius"])),
		start_angle,
		end_angle,
		float(stats["swing_duration"])
	)

	# Vuelta rápida.
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_method(
		func(angle: float) -> void:
			update_weapon_swing(angle, float(stats["weapon_radius"])),
		end_angle,
		attack_base_angle,
		float(stats["return_duration"])
	)

	# Activamos hitbox en la ventana útil del golpe.
	await get_tree().create_timer(float(stats["hitbox_start_delay"])).timeout
	if player.is_dead:
		_finish_attack_state()
		return

	attack_hitbox.begin_attack()

	await get_tree().create_timer(float(stats["hitbox_active_time"])).timeout
	if player.is_dead:
		attack_hitbox.end_attack()
		_finish_attack_state()
		return

	attack_hitbox.end_attack()

	await tween.finished

	if player.is_dead:
		_finish_attack_state()
		return

	clear_trail()

	# Volvemos el grip a su pose base.
	if grip_tween and grip_tween.is_valid():
		grip_tween.kill()

	grip_tween = create_tween()
	grip_tween.set_trans(Tween.TRANS_QUAD)
	grip_tween.set_ease(Tween.EASE_OUT)
	grip_tween.tween_property(
		weapon_grip,
		"position",
		grip_base_position,
		float(stats["grip_return_duration"])
	)

	_finish_attack_state()

	# Recién al terminar, arrancamos el cooldown propio del facón.
	facon_cooldown_timer = float(stats["cooldown"])

	attack_finished.emit("facon")


# =========================================================
# ESCOPETA
# =========================================================

func get_shotgun_stats() -> Dictionary:
	var stats: Dictionary = shotgun_base_stats.duplicate()
	return stats


# Se llama cuando APRETÁS click derecho.
# Entra en modo apuntado, pero todavía no gasta stamina.
func try_start_shotgun_aim() -> bool:
	if not shotgun_unlocked:
		return false

	if not can_start_shotgun_action():
		return false

	# Para empezar a apuntar exigimos stamina llena,
	# pero todavía no consumimos nada.
	if player.stamina == null or not player.stamina.is_full():
		return false

	start_shotgun_aim()
	return true


func start_shotgun_aim() -> void:
	if shotgun_preview:
		shotgun_preview.visible = true

	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()

	if grip_tween and grip_tween.is_valid():
		grip_tween.kill()

	clear_trail()

	is_shotgun_aiming = true
	current_attack_damage = 0
	current_attack_knockback = 0.0

	shotgun_back_global_transform = shotgun_back_pivot.global_transform

	# Mostramos escopeta frontal y ocultamos la de la espalda.
	show_shotgun_front_visual()
	update_shotgun_front_flip()

	# La escopeta frontal nace exactamente desde la pose de la espalda.
	weapon_grip.global_position = shotgun_back_pivot.global_position
	weapon_grip.rotation = get_shotgun_side_rotation()

	anim_sprite.play("Attack")

	await animate_shotgun_draw(
		player.aim_angle,
		float(get_shotgun_stats()["draw_duration"])
	)

	if player.is_dead:
		cancel_shotgun_aim()
		return


# Mientras mantenés apretado, la escopeta acompaña el mouse.
func update_shotgun_aim_pose() -> void:
	if not is_shotgun_aiming:
		return

	weapon_pivot.rotation.y = player.aim_angle
	update_shotgun_front_flip()

	# Pose frontal estable mientras apuntás.
	weapon_grip.position = grip_base_position + Vector3(0.0, 0.02, 0.10)
	weapon_grip.rotation = Vector3.ZERO


func update_shotgun_preview() -> void:
	if shotgun_preview == null or not is_shotgun_aiming:
		return

	shotgun_preview.global_position = player.global_position + Vector3(0.0, 0.03, 0.0)
	shotgun_preview.rotation.y = player.aim_angle


# Se llama cuando SOLTÁS click derecho.
# Acá recién consumimos stamina y hacemos el disparo.
func release_shotgun() -> void:
	if shotgun_preview:
		shotgun_preview.visible = false

	if not is_shotgun_aiming:
		return

	var stats := get_shotgun_stats()

	# Validamos de nuevo la stamina al soltar.
	if player.stamina == null or not player.stamina.is_full():
		cancel_shotgun_aim()
		return

	player.stamina.empty_and_configure_recovery(
		float(stats["stamina_recharge_rate"]),
		float(stats["stamina_recovery_delay"])
	)

	is_shotgun_aiming = false
	is_attacking = true

	player.skill_used.emit("shotgun")
	attack_started.emit("shotgun")

	await get_tree().create_timer(float(stats["windup"])).timeout
	if player.is_dead:
		_restore_after_shotgun_cancel()
		return

	fire_shotgun_blast(stats)
	play_muzzle_flash()
	play_muzzle_flash_light()
	play_muzzle_smoke()
	play_shotgun_recoil()

	var backward := -get_shotgun_forward_dir()
	if player.has_method("apply_shotgun_recoil"):
		player.apply_shotgun_recoil(backward, 4.8)

	await get_tree().create_timer(0.10).timeout
	await animate_shotgun_holster(float(stats["holster_duration"]))

	weapon_grip.position = grip_base_position
	weapon_grip.rotation = grip_base_rotation

	show_facon_visual()

	fade_sprite_alpha(
		facon_sprite,
		0.0,
		1.0,
		0.06
	)

	_finish_attack_state()
	attack_finished.emit("shotgun")


func cancel_shotgun_aim() -> void:
	if not is_shotgun_aiming:
		return

	if shotgun_preview:
		shotgun_preview.visible = false

	is_shotgun_aiming = false
	weapon_grip.position = grip_base_position
	weapon_grip.rotation = grip_base_rotation
	show_facon_visual()


func learn_shotgun() -> void:
	shotgun_unlocked = true
	update_shotgun_back_visual()


# Animación de sacar la escopeta hacia el frente.
func animate_shotgun_draw(target_angle: float, duration: float) -> void:
	weapon_pivot.rotation.y = target_angle

	var tween := create_tween()
	grip_tween = tween

	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		weapon_grip,
		"position",
		grip_base_position + Vector3(0.0, 0.02, 0.10),
		duration
	)

	tween.tween_property(
		weapon_grip,
		"rotation",
		Vector3(0.0, 0.0, 0.0),
		duration
	)

	await tween.finished


func play_shotgun_recoil() -> void:
	grip_tween = create_tween()
	grip_tween.set_trans(Tween.TRANS_QUAD)
	grip_tween.set_ease(Tween.EASE_OUT)

	grip_tween.tween_property(
		weapon_grip,
		"position",
		grip_base_position + Vector3(0.0, 0.02, -0.18),
		0.04
	)

	grip_tween.tween_property(
		weapon_grip,
		"position",
		grip_base_position + Vector3(0.0, 0.02, 0.08),
		0.08
	)


func animate_shotgun_holster(duration: float) -> void:
	var start_global_pos: Vector3 = weapon_grip.global_position
	var start_rotation: Vector3 = weapon_grip.rotation
	var holster_rotation := get_shotgun_side_rotation()

	var tween := create_tween()
	grip_tween = tween

	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)

	var update_holster := func(t: float) -> void:
		var current_back_pos: Vector3 = shotgun_back_pivot.global_position
		weapon_grip.global_position = start_global_pos.lerp(current_back_pos, t)

		weapon_grip.rotation.x = lerp_angle(start_rotation.x, holster_rotation.x, t)
		weapon_grip.rotation.y = lerp_angle(start_rotation.y, holster_rotation.y, t)
		weapon_grip.rotation.z = lerp_angle(start_rotation.z, holster_rotation.z, t)

	tween.tween_method(update_holster, 0.0, 1.0, duration)

	await tween.finished

	weapon_grip.position = grip_base_position
	weapon_grip.rotation = grip_base_rotation


func _restore_after_shotgun_cancel() -> void:
	if shotgun_preview:
		shotgun_preview.visible = false

	is_shotgun_aiming = false
	weapon_grip.position = grip_base_position
	weapon_grip.rotation = grip_base_rotation
	show_facon_visual()
	_finish_attack_state()


func fire_shotgun_blast(stats: Dictionary) -> void:
	var origin: Vector3 = player.global_position + Vector3(0.0, 0.8, 0.0)

	var forward: Vector3 = player.aim_dir
	forward.y = 0.0

	if forward.length_squared() <= 0.0001:
		forward = -player.global_transform.basis.z.normalized()
	else:
		forward = forward.normalized()

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy == null:
			continue

		if not is_instance_valid(enemy):
			continue

		if "is_dying" in enemy and enemy.is_dying:
			continue
		if "is_dead" in enemy and enemy.is_dead:
			continue

		var to_enemy: Vector3 = enemy.global_position - origin
		to_enemy.y = 0.0

		var dist := to_enemy.length()

		if dist <= 0.0001:
			continue

		if dist > float(stats["range"]):
			continue

		var dir := to_enemy.normalized()

		var dot_value: float = clamp(forward.dot(dir), -1.0, 1.0)
		var angle_deg: float = rad_to_deg(acos(dot_value))

		if angle_deg > float(stats["cone_angle_deg"]) * 0.5:
			continue

		var t: float = clamp(dist / float(stats["range"]), 0.0, 1.0)
		var damage_mult: float = lerp(1.0, 0.45, t)
		var final_damage: int = max(1, int(round(float(stats["damage"]) * damage_mult)))

		if enemy.has_method("take_damage"):
			enemy.take_damage(final_damage)

		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(dir, float(stats["knockback"]))


# =========================================================
# VISUAL / APOYO
# =========================================================

func update_weapon_idle() -> void:
	# Si estamos atacando o apuntando con la escopeta,
	# no queremos que el idle pise esa pose.
	if is_attacking or is_shotgun_aiming:
		return

	var facon_stats := get_facon_stats()

	weapon_pivot.rotation.y = player.aim_angle
	facon_sprite.position = Vector3(0.0, 0.0, float(facon_stats["weapon_radius"]))

	shotgun_front_sprite.position = Vector3.ZERO

	weapon_grip.position = grip_base_position
	weapon_grip.rotation = grip_base_rotation

	update_shotgun_back_visual()


func update_weapon_swing(angle: float, radius: float) -> void:
	weapon_pivot.rotation.y = angle
	facon_sprite.position = Vector3(0.0, 0.0, radius)


func get_current_weapon_radius() -> float:
	return float(get_facon_stats()["weapon_radius"])


func level_up_facon() -> void:
	facon_level += 1


func get_current_attack_damage() -> int:
	return current_attack_damage


func get_current_attack_knockback() -> float:
	return current_attack_knockback


func get_current_attack_direction(target_global_position: Vector3) -> Vector3:
	var dir: Vector3 = target_global_position - player.global_position
	dir.y = 0.0

	if dir.length_squared() <= 0.0001:
		if player.aim_dir.length_squared() > 0.0001:
			return player.aim_dir.normalized()
		return -player.global_transform.basis.z.normalized()

	return dir.normalized()


func get_weapon_tip_position() -> Vector3:
	return weapon_tip.global_transform.origin


func update_trail() -> void:
	var pos3d := get_weapon_tip_position()

	if camera.is_position_behind(pos3d):
		return

	var pos2d := camera.unproject_position(pos3d)
	trail_points.push_front(pos2d)

	if trail_points.size() > trail_max_points:
		trail_points.pop_back()

	trail.points = PackedVector2Array(trail_points)


func clear_trail() -> void:
	trail_points.clear()
	trail.points = PackedVector2Array()


func _finish_attack_state() -> void:
	is_attacking = false
	current_attack_damage = 0
	current_attack_knockback = 0.0


func cancel_attack_visuals() -> void:
	if shotgun_preview:
		shotgun_preview.visible = false

	is_attacking = false
	is_shotgun_aiming = false
	current_attack_damage = 0
	current_attack_knockback = 0.0

	clear_trail()

	if attack_tween and attack_tween.is_valid():
		attack_tween.kill()

	if grip_tween and grip_tween.is_valid():
		grip_tween.kill()

	if attack_hitbox.has_method("end_attack"):
		attack_hitbox.end_attack()

	weapon_grip.position = grip_base_position
	weapon_grip.rotation = grip_base_rotation

	show_facon_visual()


func play_muzzle_flash() -> void:
	if muzzle_flash == null:
		return

	muzzle_flash.visible = true
	muzzle_flash.modulate.a = 1.0
	muzzle_flash.scale = Vector3(0.3, 0.3, 0.3)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		muzzle_flash,
		"modulate:a",
		0.0,
		0.16
	)

	tween.tween_property(
		muzzle_flash,
		"scale",
		Vector3(0.85, 0.85, 0.85),
		1.06
	)

	await tween.finished
	muzzle_flash.visible = false


func play_muzzle_flash_light() -> void:
	if muzzle_flash_light == null:
		return

	muzzle_flash_light.light_energy = randf_range(3.0, 5.4)
	muzzle_flash_light.omni_range = randf_range(3.8, 5.6)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	tween.parallel().tween_property(
		muzzle_flash_light,
		"light_energy",
		0.0,
		0.18
	)

	tween.parallel().tween_property(
		muzzle_flash_light,
		"omni_range",
		1.2,
		0.18
	)


func play_muzzle_smoke() -> void:
	if muzzle_smoke == null or shotgun_muzzle == null:
		return

	var smoke := muzzle_smoke.duplicate()
	get_parent().add_child(smoke)

	smoke.top_level = true
	smoke.visible = true

	var spawn_pos := shotgun_muzzle.global_position
	var forward := -shotgun_muzzle.global_transform.basis.z.normalized()

	spawn_pos += forward * -1.9
	spawn_pos.y += 0.03

	smoke.global_position = spawn_pos
	smoke.global_rotation = shotgun_muzzle.global_rotation

	smoke.modulate = Color(1.0, 1.0, 1.0, 0.55)
	smoke.scale = Vector3(0.22, 0.22, 0.22)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		smoke,
		"modulate:a",
		0.0,
		1.28
	)

	tween.tween_property(
		smoke,
		"scale",
		Vector3(0.65, 0.65, 0.65),
		1.28
	)

	tween.tween_property(
		smoke,
		"global_position",
		smoke.global_position + Vector3(0.0, 0.04, 0.12),
		1.28
	)

	await tween.finished
	smoke.queue_free()


# =========================================================
# HELPERS VISUALES
# =========================================================

# La escopeta de la espalda se ve solo cuando:
# - fue aprendida
# - la escopeta frontal NO está visible
func update_shotgun_back_visual() -> void:
	shotgun_back_pivot.visible = shotgun_unlocked and not shotgun_front_sprite.visible


func show_facon_visual() -> void:
	facon_sprite.visible = true
	facon_sprite.modulate.a = 1.0

	shotgun_front_sprite.visible = false
	shotgun_front_sprite.flip_h = false

	update_shotgun_back_visual()


func show_shotgun_front_visual() -> void:
	facon_sprite.visible = false

	shotgun_front_sprite.visible = true
	shotgun_front_sprite.modulate.a = 1.0

	update_shotgun_back_visual()


func update_shotgun_front_flip() -> void:
	# Si la textura base mira a la izquierda, esta línea está bien.
	# Si en tu asset base mira a la derecha, invertí el operador.
	shotgun_front_sprite.flip_h = player.aim_dir.x <= 0.0


func fade_sprite_alpha(sprite: Sprite3D, from_alpha: float, to_alpha: float, duration: float) -> Tween:
	sprite.modulate.a = from_alpha

	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", to_alpha, duration)
	return tween


func get_shotgun_side_rotation() -> Vector3:
	if player.aim_dir.x < 0.0:
		return Vector3(0.0, deg_to_rad(-90.0), 0.0)
	return Vector3(0.0, deg_to_rad(90.0), 0.0)


func get_shotgun_forward_dir() -> Vector3:
	var forward: Vector3 = player.aim_dir
	forward.y = 0.0

	if forward.length_squared() <= 0.0001:
		forward = -player.global_transform.basis.z.normalized()
	else:
		forward = forward.normalized()

	return forward
