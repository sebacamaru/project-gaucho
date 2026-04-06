extends Node3D

# =========================================================
# Enemy Controller
# - IA básica de persecución
# - ataque con anticipación y salto
# - barra de vida animada
# - feedback visual al recibir daño
# - visibilidad mínima en runtime mediante shader
# - dissolve al morir
# =========================================================

const ENEMY_DISSOLVE_SHADER = preload("res://shaders/enemy_dissolve.gdshader")
const ENEMY_VISIBILITY_SHADER = preload("res://shaders/enemy.gdshader")

enum State {
	CHASE,
	ATTACK,
	DEAD
}

@export var max_hp: int = 3
@export var move_speed: float = 1.8
@export var attack_range: float = 1.2
@export var attack_damage: int = 1
@export var attack_cooldown: float = 0.8
@export var knockback_force: float = 7
@export var can_chase: bool = true
@export var exp_reward: int = 260
@export var points_reward: int = exp_reward * 10

@export_range(0.0, 1.0, 0.01) var min_visibility: float = 0.2
@export_range(0.0, 1.0, 0.01) var alpha_cutoff: float = 0.1

var hp: int
var state := State.CHASE
var player: Node3D = null
var is_dying := false
var can_attack := true

@onready var visual_root = $Visual
# Root principal para movimientos de ataque / squash
@onready var sprites_root = $Visual/SpritesRoot
# Offset secundario exclusivo para hit reactions
@onready var hit_offset = $Visual/SpritesRoot/HitOffset
# Sprites reales
@onready var sprite = $Visual/SpritesRoot/HitOffset/AnimatedSprite3D
@onready var aura_sprite = $Visual/SpritesRoot/HitOffset/AuraSprite3D
@onready var hurtbox = $Hurtbox

@onready var hp_bar_root = $HealthBar
@onready var hp_bar_fill_pivot = $HealthBar/FillPivot
@onready var hp_bar_background = $HealthBar/Background
@onready var hp_bar_fill = $HealthBar/FillPivot/Fill

@export var hit_stun_duration: float = 0.2
@export var hit_hop_height: float = 0.4
@export var hit_hop_duration: float = 0.1

var sprite_material: ShaderMaterial = null
var hit_tween: Tween
var hp_bar_tween: Tween
var hp_bar_version := 0
var hp_bar_alpha := 0.0
var is_hit_stunned := false
var hit_reaction_tween: Tween
var hit_stun_version := 0

func _ready() -> void:
	hp = max_hp

	initialize_health_bar()
	cache_player_reference()
	duplicate_aura_material()

	# En editor: sprite normal, sin shader
	if Engine.is_editor_hint():
		sprite.material_override = null
		return

	setup_runtime_sprite_material()

	# Esperar 1 frame ayuda a que AnimatedSprite3D ya tenga
	# animación/frame válidos al sincronizar la textura.
	call_deferred("_finish_runtime_setup")


func _finish_runtime_setup() -> void:
	ensure_valid_animation()

	setup_sprite_shader_sync()
	_on_frame_changed()


func _process(delta: float) -> void:
	if is_dying:
		return

	# Refresco defensivo: si por alguna razón el shader arrancó
	# sin textura, intentamos cargarla.
	if not Engine.is_editor_hint() and sprite_material != null:
		var tex = sprite_material.get_shader_parameter("albedo_texture")
		if tex == null:
			_on_frame_changed()

	if not is_instance_valid(player):
		cache_player_reference()
		return

	match state:
		State.CHASE:
			update_facing()
			if can_chase and not is_hit_stunned:
				update_chase(delta)
		State.ATTACK:
			pass
		State.DEAD:
			pass


# =========================================================
# Setup
# =========================================================
func initialize_health_bar() -> void:
	hp_bar_root.visible = true
	set_hp_bar_alpha(0.0)
	update_hp_bar_smooth(1.0)


func cache_player_reference() -> void:
	player = get_tree().get_first_node_in_group("player")


func duplicate_aura_material() -> void:
	var aura_mat: Material = aura_sprite.material_override
	if aura_mat != null:
		aura_sprite.material_override = aura_mat.duplicate()


func setup_runtime_sprite_material() -> void:
	sprite_material = ShaderMaterial.new()
	sprite_material.shader = ENEMY_VISIBILITY_SHADER
	sprite_material.set_shader_parameter("min_visibility", min_visibility)
	sprite_material.set_shader_parameter("alpha_cutoff", alpha_cutoff)
	sprite.material_override = sprite_material


func ensure_valid_animation() -> void:
	if sprite.sprite_frames == null:
		return

	if sprite.animation == StringName():
		var names: PackedStringArray = sprite.sprite_frames.get_animation_names()
		if names.size() > 0:
			sprite.animation = names[0]

	# Si no está reproduciendo nada, al menos dejamos un frame válido
	if sprite.frame < 0:
		sprite.frame = 0


func setup_sprite_shader_sync() -> void:
	if not sprite.frame_changed.is_connected(_on_frame_changed):
		sprite.frame_changed.connect(_on_frame_changed)


func _on_frame_changed() -> void:
	if sprite_material == null:
		return
	if sprite.sprite_frames == null:
		return
	if sprite.animation == StringName():
		return
	if not sprite.sprite_frames.has_animation(sprite.animation):
		return

	var frame_count: int = sprite.sprite_frames.get_frame_count(sprite.animation)
	if frame_count <= 0:
		return

	var safe_frame := clampi(sprite.frame, 0, frame_count - 1)

	var frame_texture: Texture2D = sprite.sprite_frames.get_frame_texture(
		sprite.animation,
		safe_frame
	)

	if frame_texture == null:
		return

	sprite_material.set_shader_parameter("albedo_texture", frame_texture)


# =========================================================
# AI / Movement
# =========================================================
func update_chase(delta: float) -> void:
	var to_player := player.global_position - global_position
	var distance := to_player.length()

	if distance <= attack_range:
		if can_attack:
			start_attack()
		return

	var direction := to_player.normalized()
	global_position += direction * move_speed * delta


func start_attack() -> void:
	if is_dying or not can_attack:
		return

	state = State.ATTACK
	can_attack = false

	var direction := player.global_position - global_position
	direction.y = 0.0

	if direction.length() > 0.001:
		direction = direction.normalized()
	else:
		direction = Vector3.ZERO

	var tween := create_tween()
	tween.set_parallel(false)

	tween.tween_property(sprites_root, "scale", Vector3(0.90, 1.10, 1.0), 0.08)
	tween.tween_property(sprites_root, "position", Vector3(direction.x * 0.38, 0.38, direction.z * 0.38), 0.08)
	tween.parallel().tween_property(sprites_root, "scale", Vector3(1.28, 0.92, 1.0), 0.08)

	apply_attack_damage()

	tween.tween_property(sprites_root, "position", Vector3.ZERO, 0.10)
	tween.parallel().tween_property(sprites_root, "scale", Vector3.ONE, 0.10)

	await tween.finished

	if is_dying:
		return

	await get_tree().create_timer(attack_cooldown).timeout

	if is_dying:
		return

	can_attack = true
	state = State.CHASE


func apply_attack_damage() -> void:
	if not is_instance_valid(player):
		return

	var to_player := player.global_position - global_position
	to_player.y = 0.0

	if to_player.length() <= attack_range + 0.15:
		if player.has_method("take_damage"):
			player.take_damage(attack_damage)

		if player.has_method("apply_knockback"):
			player.apply_knockback(to_player.normalized(), knockback_force)


# =========================================================
# Damage
# =========================================================
func take_damage(amount: int) -> void:
	if is_dying:
		return

	hp -= amount

	flash_hit()
	shake_hit()
	play_hit_reaction()
	show_hp_bar()

	if hp <= 0:
		die()


func flash_hit() -> void:
	sprite.modulate = Color.BLACK
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(sprite) and not is_dying:
		sprite.modulate = Color.WHITE


# =========================================================
# Shake visual al recibir daño
# Solo mueve HitOffset para no interferir con ataques
# =========================================================
func shake_hit() -> void:
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()

	hit_offset.position = Vector3.ZERO
	hit_offset.scale = Vector3.ONE

	hit_tween = create_tween()
	hit_tween.set_parallel(false)

	var strength: float = 0.16

	# Primer impacto
	hit_tween.tween_property(
		hit_offset,
		"scale",
		Vector3(1.08, 0.92, 1.0),
		0.04
	)

	hit_tween.parallel().tween_property(
		hit_offset,
		"position:x",
		-strength,
		0.03
	)

	# Rebote
	hit_tween.tween_property(
		hit_offset,
		"scale",
		Vector3(0.96, 1.04, 1.0),
		0.04
	)

	hit_tween.parallel().tween_property(
		hit_offset,
		"position:x",
		strength,
		0.03
	)

	# Vuelta a reposo
	hit_tween.tween_property(
		hit_offset,
		"scale",
		Vector3.ONE,
		0.05
	)

	hit_tween.parallel().tween_property(
		hit_offset,
		"position",
		Vector3.ZERO,
		0.05
	)


# =========================================================
# Death
# =========================================================
func die() -> void:
	is_dying = true
	state = State.DEAD
	hurtbox.monitoring = false
	
	if player:
		player.progress.register_enemy_kill(exp_reward, points_reward)
	
	fade_out_hp_bar()
	sprite.stop()

	var current_texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)

	var dissolve_material := ShaderMaterial.new()
	dissolve_material.shader = ENEMY_DISSOLVE_SHADER
	dissolve_material.set_shader_parameter("texture_albedo", current_texture)
	dissolve_material.set_shader_parameter("dissolve_amount", 0.0)

	sprite.material_override = dissolve_material
	sprite.modulate = Color.WHITE

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_method(
		func(v: float): dissolve_material.set_shader_parameter("dissolve_amount", v),
		0.0, 1.0, 0.8
	)

	var aura_mat := aura_sprite.material_override as ShaderMaterial
	if aura_mat:
		var start_alpha: float = aura_mat.get_shader_parameter("global_alpha")
		tween.tween_method(
			func(v: float): aura_mat.set_shader_parameter("global_alpha", v),
			start_alpha, 0.0, 0.4
		)

	await tween.finished
	queue_free()


func fade_out_hp_bar() -> void:
	if hp_bar_tween and hp_bar_tween.is_valid():
		hp_bar_tween.kill()

	hp_bar_tween = create_tween()
	hp_bar_tween.tween_method(set_hp_bar_alpha, hp_bar_alpha, 0.0, 0.25)


# =========================================================
# Health Bar
# =========================================================
func show_hp_bar() -> void:
	hp_bar_version += 1
	var version := hp_bar_version

	update_hp_bar_smooth(clampf(hp / float(max_hp), 0.0, 1.0))

	if hp_bar_tween and hp_bar_tween.is_valid():
		hp_bar_tween.kill()

	hp_bar_root.visible = true

	hp_bar_tween = create_tween()
	hp_bar_tween.tween_method(set_hp_bar_alpha, hp_bar_alpha, 1.0, 0.15)

	await get_tree().create_timer(1.2).timeout

	if version != hp_bar_version or is_dying:
		return

	hp_bar_tween = create_tween()
	hp_bar_tween.tween_method(set_hp_bar_alpha, hp_bar_alpha, 0.0, 0.25)

	await hp_bar_tween.finished

	if version == hp_bar_version and not is_dying:
		hp_bar_root.visible = false


func update_hp_bar_smooth(target_ratio: float) -> void:
	var tween := create_tween()
	tween.tween_property(hp_bar_fill_pivot, "scale:x", target_ratio, 0.15)


func set_hp_bar_alpha(alpha: float) -> void:
	hp_bar_alpha = alpha
	hp_bar_background.modulate.a = alpha
	hp_bar_fill.modulate.a = alpha


# =========================================================
# Facing
# =========================================================
func update_facing() -> void:
	if not is_instance_valid(player):
		return

	var dx := player.global_position.x - global_position.x

	if absf(dx) < 0.01:
		return

	var facing_left := dx < 0.0
	sprite.flip_h = facing_left
	aura_sprite.flip_h = facing_left

# =========================================================
# Pequeño salto al ser golpeado
# Pausa la movilidad por unos milisegundos
# =========================================================
func play_hit_reaction() -> void:
	hit_stun_version += 1
	var my_version: int = hit_stun_version

	is_hit_stunned = true

	if hit_reaction_tween and hit_reaction_tween.is_valid():
		hit_reaction_tween.kill()

	var base_y: float = hit_offset.position.y

	hit_reaction_tween = create_tween()

	# Subida rápida
	hit_reaction_tween.tween_property(
		hit_offset,
		"position:y",
		base_y + hit_hop_height,
		hit_hop_duration * 0.45
	)

	# Bajada
	hit_reaction_tween.tween_property(
		hit_offset,
		"position:y",
		0.0,
		hit_hop_duration * 0.55
	)

	await get_tree().create_timer(hit_stun_duration).timeout

	if is_dying:
		return

	if my_version == hit_stun_version:
		is_hit_stunned = false
