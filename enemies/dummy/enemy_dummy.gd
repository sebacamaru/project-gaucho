extends Node3D

# =========================================================
# Enemy Controller
# - IA de persecución usando NavigationAgent3D
# - esquiva obstáculos mediante NavigationMesh
# - variación de persecución con offset alrededor del jugador
# - velocidad individual aleatoria por enemigo
# - ataque con anticipación y salto
# - barra de vida animada
# - feedback visual al recibir daño
# - visibilidad mínima en runtime mediante shader
# - dissolve al morir
# - inmovilización indefinida por boleadoras
# - soporte para enemigos voladores con vaivén visual
# =========================================================

const ENEMY_DISSOLVE_SHADER = preload("res://shaders/enemy_dissolve.gdshader")
const ENEMY_VISIBILITY_SHADER = preload("res://shaders/enemy.gdshader")

enum State {
	CHASE,
	ATTACK,
	DEAD
}

signal died


# =========================================================
# STATS / CONFIG GENERAL
# =========================================================

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


# =========================================================
# NAVIGATION / IA
# =========================================================

# Activa/desactiva el uso de NavigationAgent3D.
# Si lo desactivás, el enemigo vuelve a perseguir en línea recta.
@export var use_navigation: bool = true

# Cada cuánto recalcula el destino hacia el jugador.
# No conviene hacerlo todos los frames porque queda más caro y más robótico.
@export var repath_interval: float = 0.45

# Radio alrededor del jugador al que el enemigo intenta acercarse.
# Esto hace que no todos apunten exactamente al centro del jugador.
# Si querés que vayan directo al jugador, ponelo en 0.
@export var chase_offset_radius: float = 0.0

# Cada cuánto cambia el punto alrededor del jugador.
# Más bajo = enemigos más inquietos.
# Más alto = enemigos más decididos.
@export var chase_offset_change_interval: float = 2.5

# Distancia mínima al siguiente punto del path.
# Si está muy bajo pueden temblar; si está muy alto pueden cortar esquinas.
@export var navigation_path_desired_distance: float = 0.85

# Distancia a la que el NavigationAgent considera que llegó al objetivo.
@export var navigation_target_desired_distance: float = 0.9

# Radio usado por el NavigationAgent.
# No reemplaza una colisión física real, pero ayuda al cálculo de navegación.
@export var navigation_agent_radius: float = 0.35

# Si más adelante activás avoidance entre enemigos, este valor ya queda preparado.
@export var navigation_agent_height: float = 1.2


# =========================================================
# SPEED VARIATION
# =========================================================

# Variación plana de velocidad.
# Ejemplo:
# move_speed = 2.0
# speed_variation = 0.2
# Resultado posible: entre 1.8 y 2.2
@export var speed_variation: float = 0.2

# Velocidad real que usa ESTE enemigo.
# Se calcula una sola vez en _ready().
var current_move_speed: float = 0.0


# =========================================================
# FLYING TYPE / HOVER VISUAL
# =========================================================

# Si está activo, el enemigo hace un vaivén vertical infinito.
#
# IMPORTANTE:
# Esto NO mueve el nodo Enemy real.
# Solo mueve $Visual.
#
# De esa manera:
# - no se rompe el NavigationAgent3D
# - no se alteran las colisiones
# - no cambia el rango de ataque
# - no se ensucia el pathfinding
@export var is_flying_type: bool = false

# Altura máxima del vaivén visual.
# 0.15 a 0.30 suele quedar bien para sprites 2.5D.
@export var flying_hover_amplitude: float = 0.22

# Velocidad del vaivén.
# Más alto = flota más rápido.
@export var flying_hover_speed: float = 2.4

# Si está activo, cada enemigo recibe un desfase aleatorio.
# Sirve para que 5 pájaros no suban y bajen todos perfectamente sincronizados.
@export var flying_random_phase: bool = true

# Tiempo interno del vaivén.
var flying_hover_time: float = 0.0

# Desfase individual del vaivén.
var flying_hover_phase: float = 0.0

# Posición original de $Visual.
# El hover siempre se calcula desde esta posición base.
var visual_root_base_position: Vector3 = Vector3.ZERO


# =========================================================
# HIT REACTION
# =========================================================

@export var hit_stun_duration: float = 0.2
@export var hit_hop_height: float = 0.4
@export var hit_hop_duration: float = 0.1


# =========================================================
# STATE
# =========================================================

var hp: int
var state := State.CHASE
var player: Node3D = null
var is_dying := false
var can_attack := true

var sprite_material: ShaderMaterial = null
var hit_tween: Tween
var hp_bar_tween: Tween
var hp_bar_version := 0
var hp_bar_alpha := 0.0
var is_hit_stunned := false
var hit_reaction_tween: Tween
var hit_stun_version := 0

# Timers internos de navegación.
var repath_timer: float = 0.0
var chase_offset_timer: float = 0.0

# Offset actual alrededor del jugador.
# Sirve para que cada enemigo no vaya siempre al mismo punto exacto.
var current_chase_offset: Vector3 = Vector3.ZERO


# =========================================================
# BOLEADORAS / ROOT
# =========================================================

# Indica si el enemigo quedó atrapado por boleadoras.
# Mientras esto sea true:
# - no puede perseguir
# - no puede iniciar ataques
# - queda inmovilizado indefinidamente
var is_boleadora_rooted: bool = false


# =========================================================
# NODE REFERENCES
# =========================================================

@onready var visual_root = $Visual

# Root principal para movimientos de ataque / squash.
@onready var sprites_root = $Visual/SpritesRoot

# Offset secundario exclusivo para hit reactions.
@onready var hit_offset = $Visual/SpritesRoot/HitOffset

# Sprites reales.
@onready var sprite = $Visual/SpritesRoot/HitOffset/AnimatedSprite3D
@onready var aura_sprite = $Visual/SpritesRoot/HitOffset/AuraSprite3D
@onready var root_effect_sprite: Sprite3D = $Visual/SpritesRoot/HitOffset/RootEffectSprite3D
@onready var hurtbox = $Hurtbox

@onready var hp_bar_root = $HealthBar
@onready var hp_bar_fill_pivot = $HealthBar/FillPivot
@onready var hp_bar_background = $HealthBar/Background
@onready var hp_bar_fill = $HealthBar/FillPivot/Fill

# IMPORTANTE:
# Este nodo tiene que existir como hijo directo del enemigo:
# Enemy
# └── NavigationAgent3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D


# =========================================================
# READY / PROCESS
# =========================================================

func _ready() -> void:
	hp = max_hp

	# Calcula una velocidad única para este enemigo.
	# Esto evita que todos los enemigos caminen exactamente igual.
	roll_move_speed()

	# Prepara el sistema visual de flotación.
	# Aunque is_flying_type esté apagado, guardamos la posición base.
	setup_flying_hover()

	root_effect_sprite.visible = false

	initialize_health_bar()
	cache_player_reference()
	duplicate_aura_material()
	setup_navigation_agent()

	# Hacemos que el primer cálculo de path ocurra enseguida.
	repath_timer = 0.0
	chase_offset_timer = 0.0

	# En editor: sprite normal, sin shader.
	if Engine.is_editor_hint():
		sprite.material_override = null
		return

	setup_runtime_sprite_material()

	# Esperar 1 frame ayuda a que AnimatedSprite3D ya tenga
	# animación/frame válidos al sincronizar la textura.
	call_deferred("_finish_runtime_setup")


func roll_move_speed() -> void:
	var min_speed := move_speed - speed_variation
	var max_speed := move_speed + speed_variation

	# Evitamos velocidades negativas o absurdamente bajas.
	min_speed = maxf(0.1, min_speed)

	current_move_speed = randf_range(min_speed, max_speed)


func _finish_runtime_setup() -> void:
	ensure_valid_animation()

	setup_sprite_shader_sync()
	_on_frame_changed()


func _process(delta: float) -> void:
	if is_dying:
		return

	# El hover es solo visual y se calcula en _process,
	# porque no necesita física ni navegación.
	update_flying_hover(delta)

	# Refresco defensivo:
	# si por alguna razón el shader arrancó sin textura,
	# intentamos cargarla de nuevo.
	if not Engine.is_editor_hint() and sprite_material != null:
		var tex = sprite_material.get_shader_parameter("albedo_texture")
		if tex == null:
			_on_frame_changed()


func _physics_process(delta: float) -> void:
	if is_dying:
		return

	if not is_instance_valid(player):
		cache_player_reference()
		return

	match state:
		State.CHASE:
			update_facing()

			# Solo perseguimos si:
			# - el enemigo puede perseguir
			# - no está en hit stun
			# - no quedó atrapado por boleadoras
			if can_chase and not is_hit_stunned and not is_boleadora_rooted:
				update_chase(delta)

		State.ATTACK:
			# Si quedó boleado en medio de otro flujo,
			# lo forzamos de nuevo a estado chase.
			if is_boleadora_rooted:
				state = State.CHASE

		State.DEAD:
			pass


# =========================================================
# SETUP
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


func setup_navigation_agent() -> void:
	if nav_agent == null:
		return

	nav_agent.path_desired_distance = navigation_path_desired_distance
	nav_agent.target_desired_distance = navigation_target_desired_distance
	nav_agent.radius = navigation_agent_radius
	nav_agent.height = navigation_agent_height
	nav_agent.max_speed = current_move_speed

	# En este sistema lo movemos nosotros manualmente,
	# así que por ahora dejamos avoidance apagado.
	nav_agent.avoidance_enabled = false

	# Importante para 2.5D:
	# evitamos offsets raros de altura en el path.
	nav_agent.path_height_offset = 0.0


func ensure_valid_animation() -> void:
	if sprite.sprite_frames == null:
		return

	if sprite.animation == StringName():
		var names: PackedStringArray = sprite.sprite_frames.get_animation_names()
		if names.size() > 0:
			sprite.animation = names[0]

	# Si no está reproduciendo nada, al menos dejamos un frame válido.
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
# FLYING TYPE / HOVER VISUAL
# =========================================================

func setup_flying_hover() -> void:
	if visual_root == null:
		return

	# Guardamos la posición original del nodo Visual.
	# El vaivén siempre parte desde esta posición.
	visual_root_base_position = visual_root.position

	# Esto evita que todos los enemigos voladores floten sincronizados.
	if flying_random_phase:
		flying_hover_phase = randf_range(0.0, TAU)
	else:
		flying_hover_phase = 0.0


func update_flying_hover(delta: float) -> void:
	if visual_root == null:
		return

	# Si no es volador, nos aseguramos de que vuelva a su posición base.
	# Esto ayuda si activás/desactivás el flag durante pruebas.
	if not is_flying_type:
		visual_root.position = visual_root_base_position
		return

	flying_hover_time += delta * flying_hover_speed

	# Movimiento senoidal simple:
	# sube y baja suavemente de forma infinita.
	var hover_offset := sin(flying_hover_time + flying_hover_phase) * flying_hover_amplitude

	# Solo tocamos Y del nodo Visual.
	# El Enemy real queda quieto en su altura de navegación.
	visual_root.position.y = visual_root_base_position.y + hover_offset


# =========================================================
# AI / MOVEMENT
# =========================================================

func update_chase(delta: float) -> void:
	if not is_instance_valid(player):
		return

	var to_player := get_flat_vector_to_player()
	var distance := to_player.length()

	# Si está lo suficientemente cerca, intenta atacar.
	if distance <= attack_range:
		if can_attack and not is_boleadora_rooted:
			start_attack()
		return

	# Si por algún motivo querés probar sin navmesh,
	# podés desactivar use_navigation desde el inspector.
	if not use_navigation:
		update_direct_chase(delta)
		return

	update_navigation_chase(delta)


func update_navigation_chase(delta: float) -> void:
	if nav_agent == null:
		return

	repath_timer -= delta
	chase_offset_timer -= delta

	# Cada tanto cambiamos el offset.
	# Para debug, si chase_offset_radius está en 0, esto no afecta nada.
	if chase_offset_timer <= 0.0:
		chase_offset_timer = chase_offset_change_interval
		pick_new_chase_offset()

	# Recalculamos el target cada cierto tiempo, no todos los frames.
	if repath_timer <= 0.0:
		repath_timer = repath_interval
		update_navigation_target()

	# Pedimos el próximo punto del path.
	var next_position := nav_agent.get_next_path_position()

	# Movimiento plano X/Z.
	var direction := next_position - global_position
	direction.y = 0.0

	# ---------------------------------------------------------
	# FIX ANTI-TEMBLEQUE
	# ---------------------------------------------------------
	# Si el próximo punto está demasiado cerca en X/Z, no intentamos
	# corregir milimétricamente. Eso suele causar vibración.
	#
	# En vez de eso, usamos una dirección suave hacia el jugador
	# SOLO como fallback momentáneo.
	# El path sigue estando controlado por el NavigationAgent.
	# ---------------------------------------------------------
	if direction.length() < 0.25:
		direction = get_flat_vector_to_player()

		# Si incluso hacia el jugador no hay dirección útil, no hacemos nada.
		if direction.length() < 0.25:
			return

	direction = direction.normalized()

	# Usamos current_move_speed, no move_speed,
	# para respetar la variación individual de velocidad.
	global_position += direction * current_move_speed * delta


func update_direct_chase(delta: float) -> void:
	# Modo viejo / fallback:
	# persigue al jugador en línea recta.
	# Ojo: esto atraviesa obstáculos porque no usa navmesh.
	var direction := get_flat_vector_to_player()

	if direction.length() < 0.05:
		return

	direction = direction.normalized()

	# Usamos current_move_speed también en modo directo.
	global_position += direction * current_move_speed * delta


func update_navigation_target() -> void:
	if not is_instance_valid(player):
		return

	# El destino real no es siempre el centro del jugador.
	# Sumamos un pequeño offset para que los enemigos rodeen un poco.
	var target_position := player.global_position + current_chase_offset

	# Mantenemos la altura del jugador/terreno coherente.
	# El NavigationAgent después proyecta esto sobre el navmesh.
	nav_agent.target_position = target_position


func pick_new_chase_offset() -> void:
	if chase_offset_radius <= 0.0:
		current_chase_offset = Vector3.ZERO
		return

	var angle := randf_range(0.0, TAU)

	current_chase_offset = Vector3(
		cos(angle) * chase_offset_radius,
		0.0,
		sin(angle) * chase_offset_radius
	)


func get_flat_vector_to_player() -> Vector3:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	return to_player


# =========================================================
# ATTACK
# =========================================================

func start_attack() -> void:
	# No puede atacar si:
	# - se está muriendo
	# - está en cooldown de ataque
	# - quedó inmovilizado por boleadoras
	if is_dying or not can_attack or is_boleadora_rooted:
		return

	state = State.ATTACK
	can_attack = false

	var direction := get_flat_vector_to_player()

	if direction.length() > 0.001:
		direction = direction.normalized()
	else:
		direction = Vector3.ZERO

	var tween := create_tween()
	tween.set_parallel(false)

	# Anticipación / estiramiento.
	tween.tween_property(sprites_root, "scale", Vector3(0.90, 1.10, 1.0), 0.08)

	# Saltito hacia el jugador.
	# Esto mueve SpritesRoot, no Visual.
	# Por eso puede convivir bien con el hover del Flying Type.
	tween.tween_property(
		sprites_root,
		"position",
		Vector3(direction.x * 0.38, 0.38, direction.z * 0.38),
		0.08
	)

	# Squash de impacto.
	tween.parallel().tween_property(sprites_root, "scale", Vector3(1.28, 0.92, 1.0), 0.08)

	apply_attack_damage()

	# Vuelta a la pose normal.
	tween.tween_property(sprites_root, "position", Vector3.ZERO, 0.10)
	tween.parallel().tween_property(sprites_root, "scale", Vector3.ONE, 0.10)

	await tween.finished

	if is_dying:
		return

	# Si quedó boleado durante o después del ataque,
	# no reactivamos el ataque.
	if is_boleadora_rooted:
		state = State.CHASE
		return

	await get_tree().create_timer(attack_cooldown).timeout

	if is_dying:
		return

	# Si quedó boleado durante el cooldown,
	# tampoco puede volver a atacar.
	if is_boleadora_rooted:
		state = State.CHASE
		return

	can_attack = true
	state = State.CHASE


func apply_attack_damage() -> void:
	if not is_instance_valid(player):
		return

	var to_player := get_flat_vector_to_player()

	if to_player.length() <= attack_range + 0.15:
		if player.has_method("take_damage"):
			player.take_damage(attack_damage)

		if player.has_method("apply_knockback"):
			player.apply_knockback(to_player.normalized(), knockback_force)


# =========================================================
# DAMAGE
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
# BOLEADORAS
# =========================================================

# Inmovilización indefinida.
# En esta fase no tiene duración: el enemigo queda quieto hasta morir.
func apply_boleadora_root() -> void:
	if is_dying:
		return

	# Si ya estaba atrapado, no hacemos nada.
	if is_boleadora_rooted:
		return

	is_boleadora_rooted = true

	# Frenamos cualquier posibilidad de iniciar ataque.
	can_attack = false
	state = State.CHASE

	# Mandamos el target del nav agent a la posición actual
	# para que no siga intentando caminar hacia un path viejo.
	if nav_agent != null:
		nav_agent.target_position = global_position

	# Si justo había alguna animación/tween de hit o ataque,
	# la cortamos para dejar una pose limpia.
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()

	# También podemos cortar la hit reaction si querés una inmovilización
	# más "seca" y estable visualmente.
	if hit_reaction_tween and hit_reaction_tween.is_valid():
		hit_reaction_tween.kill()

	# Dejamos el enemigo en una pose neutral.
	#
	# Ojo:
	# NO tocamos visual_root.position porque eso cortaría el hover.
	# Si el enemigo es volador, puede seguir flotando visualmente incluso atrapado.
	sprites_root.position = Vector3.ZERO
	sprites_root.scale = Vector3.ONE
	hit_offset.position = Vector3.ZERO
	hit_offset.scale = Vector3.ONE

	# Sprite de estado "atrapado".
	root_effect_sprite.visible = true


# =========================================================
# SHAKE VISUAL AL RECIBIR DAÑO
# Solo mueve HitOffset para no interferir con ataques.
# =========================================================

func shake_hit() -> void:
	if hit_tween and hit_tween.is_valid():
		hit_tween.kill()

	hit_offset.position = Vector3.ZERO
	hit_offset.scale = Vector3.ONE

	hit_tween = create_tween()
	hit_tween.set_parallel(false)

	var strength: float = 0.16

	# Primer impacto.
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

	# Rebote.
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

	# Vuelta a reposo.
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
# DEATH
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
		0.0,
		1.0,
		0.8
	)

	var aura_mat := aura_sprite.material_override as ShaderMaterial
	if aura_mat:
		var start_alpha: float = aura_mat.get_shader_parameter("global_alpha")

		tween.tween_method(
			func(v: float): aura_mat.set_shader_parameter("global_alpha", v),
			start_alpha,
			0.0,
			0.4
		)

	died.emit()
	root_effect_sprite.visible = false

	await tween.finished

	queue_free()


func fade_out_hp_bar() -> void:
	if hp_bar_tween and hp_bar_tween.is_valid():
		hp_bar_tween.kill()

	hp_bar_tween = create_tween()
	hp_bar_tween.tween_method(set_hp_bar_alpha, hp_bar_alpha, 0.0, 0.25)


# =========================================================
# HEALTH BAR
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
# FACING
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
# PEQUEÑO SALTO AL SER GOLPEADO
# Pausa la movilidad por unos milisegundos.
# =========================================================

func play_hit_reaction() -> void:
	hit_stun_version += 1
	var my_version: int = hit_stun_version

	is_hit_stunned = true

	if hit_reaction_tween and hit_reaction_tween.is_valid():
		hit_reaction_tween.kill()

	var base_y: float = hit_offset.position.y

	hit_reaction_tween = create_tween()

	# Subida rápida.
	hit_reaction_tween.tween_property(
		hit_offset,
		"position:y",
		base_y + hit_hop_height,
		hit_hop_duration * 0.45
	)

	# Bajada.
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
