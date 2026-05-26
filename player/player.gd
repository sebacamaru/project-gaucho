extends CharacterBody3D

# =========================================================
# PLAYER
# =========================================================
#
# Player principal del juego.
#
# En esta versión tiene dos grandes modos:
#
# 1) Gameplay mode:
#    - Movimiento normal
#    - Armas
#    - Lámpara
#    - Dash
#    - Sapukai
#    - Input de combate
#
# 2) Cutscene mode:
#    - Se bloquea el input de gameplay.
#    - Se cancelan acciones activas de combate.
#    - Por defecto se usa el visual de Gameplay para la cutscene.
#    - Se ocultan solo nodos problemáticos: armas, cursor, dash smear, etc.
#    - Se mantiene visible el cuerpo del player, lámpara y luces.
#    - Opcionalmente se puede volver al modo viejo usando Cutscene/AnimatedSprite3D.
#
# Estructura esperada:
#
# Player
# ├── CollisionShape3D
# ├── ShadowBlob
# ├── Camera
# ├── Gameplay
# │   ├── Sprites
# │   ├── Weapon
# │   ├── LightPivot
# │   ├── DashSmear
# │   └── ...
# ├── Cutscene
# │   └── AnimatedSprite3D
# └── Components
#     ├── PlayerProgress
#     ├── WeaponComponent
#     ├── DashSkill
#     ├── StaminaComponent
#     └── SapukaiComponent
# =========================================================


# =========================================================
# CONFIGURACIÓN GENERAL
# =========================================================

@export var max_hp: int = 10
@export var speed: float = 6.0

# Qué tan rápido se frena el knockback.
@export var knockback_drag: float = 18.0


# =========================================================
# CUTSCENE MODE
# =========================================================
#
# Este bloque permite que el Player pueda entrar y salir
# de cutscenes sin mezclar input de combate, armas, dash, etc.
# =========================================================

# Nodo raíz de todo lo jugable/visual del player.
@onready var gameplay_root: Node3D = $Gameplay

# Nodo raíz de todo lo usado exclusivamente en cutscenes.
# Ahora queda como alternativa opcional.
@onready var cutscene_root: Node3D = $Cutscene

# Sprite simple para cutscenes.
# Se usa solamente si use_gameplay_visuals_in_cutscene = false.
@onready var cutscene_anim_sprite: AnimatedSprite3D = get_node_or_null("Cutscene/AnimatedSprite3D")

# True cuando el player está siendo controlado por una cutscene.
var is_cutscene_mode: bool = false

# Input general del gameplay.
# En cutscene se pone en false.
var input_enabled: bool = true

# Movimiento simple para cutscenes.
var cutscene_is_walking: bool = false
var cutscene_walk_target: Vector3 = Vector3.ZERO
var cutscene_walk_speed: float = 2.5

# Distancia mínima para considerar que llegó al destino.
@export var cutscene_arrive_distance: float = 0.08

# Señal útil para poder hacer:
# await player.cutscene_walk_to(marker.global_position)
signal cutscene_walk_finished


# =========================================================
# CUTSCENE VISUAL MODE
# =========================================================
#
# Hay dos estrategias posibles:
#
# A) use_gameplay_visuals_in_cutscene = true
#    - Se mantiene visible Gameplay.
#    - Se usa el AnimatedSprite3D real del jugador.
#    - Se mantiene lámpara/luz.
#    - Se ocultan solo armas, cursor, dash smear, etc.
#
# B) use_gameplay_visuals_in_cutscene = false
#    - Se oculta Gameplay entero.
#    - Se muestra Cutscene/AnimatedSprite3D.
#    - Es el comportamiento viejo.
#
# Para Gualiche conviene A, porque la lámpara está integrada
# al visual real del player.
# =========================================================

@export var use_gameplay_visuals_in_cutscene: bool = true

# Nodos de Gameplay que se ocultan mientras corre una cutscene.
#
# Importante:
# Estos paths son relativos al Player.
#
# Podés agregar/quitar desde el Inspector sin tocar código.
@export var gameplay_nodes_to_hide_in_cutscene: Array[NodePath] = [
	^"Gameplay/Weapon",
	^"Gameplay/AimDebugLayer",
	^"Gameplay/DashSmear",
	^"Gameplay/Trail",
	^"Gameplay/Sprites/ShotgunPivot",
	^"Gameplay/Sprites/SapukaiSprite3D"
]

# Guarda la visibilidad original de cada nodo ocultado durante cutscene.
# Así al salir restauramos exactamente como estaba.
var _cutscene_hidden_gameplay_nodes_state: Dictionary = {}

# Si está activo, al usar visuales de Gameplay en cutscene,
# NO se hace fade in del Gameplay completo al volver.
#
# Esto evita que el cuerpo/lámpara/luz hagan un fade raro,
# porque en este modo nunca desaparecieron.
@export var disable_full_gameplay_fade_when_using_gameplay_visuals: bool = true


# =========================================================
# CUTSCENE → GAMEPLAY FADE
# =========================================================
#
# Cuando el player sale de cutscene, el nodo Gameplay puede volver
# con un fade in suave.
#
# Esto tiene más sentido cuando use_gameplay_visuals_in_cutscene = false,
# porque en ese caso Gameplay realmente estuvo oculto completo.
#
# Si use_gameplay_visuals_in_cutscene = true, por defecto NO aplicamos
# el fade completo, porque el cuerpo/lámpara ya estaban visibles.
# =========================================================

@export var use_gameplay_fade_in: bool = true
@export_range(0.0, 2.0, 0.01) var gameplay_fade_in_duration: float = 0.25

@export var gameplay_fade_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var gameplay_fade_ease: Tween.EaseType = Tween.EASE_OUT

var _gameplay_fade_tween: Tween = null

# Estado original de cada nodo fadeado.
# Guardamos alpha original o energía original para restaurar exacto.
var _gameplay_fade_original_state: Dictionary = {}

# Si está activo, los AnimatedSprite3D no participan del fade in de Gameplay.
# Útil para que el cuerpo del player aparezca instantáneo.
@export var exclude_animated_sprites_from_gameplay_fade: bool = true

# Grupo opcional para excluir nodos puntuales del fade.
# Podés poner cualquier nodo en el grupo "no_gameplay_fade".
@export var gameplay_fade_excluded_group: StringName = &"no_gameplay_fade"


# =========================================================
# NODOS / COMPONENTES
# =========================================================

# Luz de lámpara.
@onready var weapon_light: OmniLight3D = $Gameplay/LightPivot/OmniLight3D

# Sistema de progreso.
@onready var progress: PlayerProgress = $Components/PlayerProgress

# Componente de armas.
@onready var weapon_component: WeaponComponent = $Components/WeaponComponent

# Efecto visual del dash.
@onready var dash_smear: Sprite3D = $Gameplay/DashSmear

# Habilidad Sapukai.
@onready var sapukai: SapukaiComponent = $Components/SapukaiComponent


# =========================================================
# BALANCEO DE LÁMPARA
# =========================================================

# Tiempo acumulado para la oscilación.
var lamp_swing_time := 0.0

# Rotación base de la lámpara al iniciar.
var lamp_base_rotation: Vector3

# Ángulo máximo del balanceo en grados.
@export var lamp_swing_angle_deg: float = 24.0

# Velocidad del balanceo.
@export var lamp_swing_speed: float = 10.0

# Qué tan rápido vuelve al centro cuando deja de moverse.
@export var lamp_return_speed: float = 8.0

var lamp_current_angle_rad: float = 0.0
var lamp_base_angle_rad: float = 0.0


# =========================================================
# HABILIDADES
# =========================================================

@onready var dash_skill: DashSkill = $Components/DashSkill
@onready var stamina: StaminaComponent = $Components/StaminaComponent

var is_dashing: bool = false
var dash_velocity: Vector3 = Vector3.ZERO
var dash_timer: float = 0.0
var last_input_dir: Vector2 = Vector2.DOWN


# =========================================================
# NODOS DE ESCENA
# =========================================================

@onready var camera: Camera3D = get_viewport().get_camera_3d()
@onready var sprites: Node3D = $Gameplay/Sprites
@onready var anim_sprite: AnimatedSprite3D = $Gameplay/Sprites/AnimatedSprite3D
@onready var cursor: Node3D = $Gameplay/AimDebugLayer/Cursor
@onready var sapukai_sprite: Sprite3D = $Gameplay/Sprites/SapukaiSprite3D

# Nodo raíz visual del arma.
# La lógica del arma vive en WeaponComponent, pero este nodo sigue
# perteneciendo visualmente al player.
@onready var weapon_pivot: Node3D = $Gameplay/Weapon

# Sprite de luz falsa de la lámpara.
@onready var lamp_visual: Node3D = $Gameplay/Sprites/LampPivot
@onready var light_sprite: Sprite3D = $Gameplay/Sprites/LampPivot/LightSprite3D


# =========================================================
# ESTADO INTERNO
# =========================================================

# Puntos de vida actuales.
var hp: int = 10

# Estado de muerte.
var is_dead := false

# Dirección actual de apuntado.
var aim_angle := 0.0
var aim_dir := Vector3.ZERO

# Knockback acumulado.
var knockback_velocity: Vector3 = Vector3.ZERO

# Referencia opcional a efectos de pantalla.
var screen_fx: Node = null

# Tweens del dash smear.
var dash_smear_tween: Tween
var dash_smear_spawn_timer: float = 0.0

# Intervalo de spawn entre ghosts del dash.
@export var dash_smear_spawn_interval: float = 0.03


# =========================================================
# AIM / MOUSE
# =========================================================

# Distancia mínima en mundo desde el player hasta el mouse
# para aceptar una nueva dirección de apuntado.
# Si el mouse está más cerca que esto, mantenemos el último aim estable.
@export var aim_deadzone_world: float = 0.35

# Distancia un poco mayor para volver a activar el aim.
# Esto evita parpadeos entrando/saliendo justo del borde.
@export var aim_resume_world: float = 0.45

var is_mouse_inside_aim_deadzone: bool = false

@export var aim_deadzone_screen_px: float = 70.0


# =========================================================
# SEÑALES
# =========================================================

# Señal para avisar de que el HP cambió.
signal hp_changed(current_hp: int, max_hp: int)

# Señal cuando usa una skill / arma.
signal skill_used(slot_name: String)


# =========================================================
# READY
# =========================================================

func _ready() -> void:
	# Skills / progreso.
	progress.skill_unlocked.connect(_on_skill_unlocked)

	# Vida inicial.
	hp = max_hp
	hp_changed.emit(hp, max_hp)

	# Buscar una referencia opcional al nodo de efectos de pantalla.
	screen_fx = get_tree().get_first_node_in_group("screen_fx")

	# Guardar la rotación base de la lámpara.
	lamp_base_rotation = light_sprite.rotation

	# Arranca en idle.
	anim_sprite.play("Idle")

	# Sapukai.
	sapukai.sapukai_started.connect(_on_sapukai_started)
	sapukai.sapukai_ended.connect(_on_sapukai_ended)

	# Estado visual inicial:
	# gameplay prendido, cutscene apagado.
	#
	# Usamos force = true para aplicar visibilidad aunque
	# is_cutscene_mode ya esté en false.
	set_cutscene_mode(false, true)


# =========================================================
# PHYSICS PROCESS
# =========================================================

func _physics_process(delta: float) -> void:
	# Si está muerto, no puede moverse ni atacar.
	if is_dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	if Input.is_action_just_pressed("debug_cutscene"):
		set_cutscene_mode(not is_cutscene_mode)

	# ---------------------------------------------------------
	# MODO CUTSCENE
	# ---------------------------------------------------------
	# En cutscene no procesamos input de gameplay:
	# - no dash
	# - no ataque
	# - no armas
	# - no lámpara interactiva con mouse
	# - no cursor/aim
	#
	# Solo procesamos movimiento simple de actor, si lo hubiera.
	# ---------------------------------------------------------
	if is_cutscene_mode:
		_physics_process_cutscene(delta)
		return

	# Si por algún motivo el input está deshabilitado,
	# frenamos el player y evitamos cualquier acción.
	if not input_enabled:
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
		# VELOCIDAD DE MOVIMIENTO
		# =========================================================
		var move_speed: float = speed

		if sapukai != null:
			move_speed *= sapukai.get_move_speed_mult()

		var move_velocity := dir * move_speed

		# Se suma el knockback al movimiento manual.
		velocity = move_velocity + knockback_velocity
		move_and_slide()

	# Rotación / balanceo de la lámpara.
	update_lamp_swing(delta, input_dir)

	# El knockback se frena gradualmente.
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, knockback_drag * delta)

	# =========================
	# INPUT DE ATAQUE
	# =========================
	if Input.is_action_just_pressed("facon") and not is_dashing:
		weapon_component.try_primary_attack()

	if Input.is_action_just_pressed("escopeta"):
		weapon_component.try_start_shotgun_aim()

	if Input.is_action_just_released("escopeta"):
		weapon_component.release_shotgun()

	if Input.is_action_just_pressed("boleadoras"):
		weapon_component.try_start_boleadoras_aim()

	if Input.is_action_just_released("boleadoras"):
		weapon_component.release_boleadoras()

	if Input.is_action_just_pressed("sapukai"):
		sapukai.try_activate()

	# =========================
	# VISUAL DEL ARMA
	# =========================
	weapon_component.update_weapon_idle()

	# =========================
	# ANIMACIÓN DEL PERSONAJE
	# =========================
	if not weapon_component.is_attacking and not is_dashing:
		update_animation(input_dir)


# =========================================================
# CUTSCENE MODE API
# =========================================================

func set_cutscene_mode(enabled: bool, force: bool = false) -> void:
	# Si ya está en ese estado y no estamos forzando,
	# no hacemos nada.
	if is_cutscene_mode == enabled and not force:
		return

	is_cutscene_mode = enabled
	input_enabled = not enabled

	if enabled:
		_enter_cutscene_mode()
	else:
		_exit_cutscene_mode()


func _enter_cutscene_mode() -> void:
	# ---------------------------------------------------------
	# Cancelar acciones de gameplay
	# ---------------------------------------------------------
	_cancel_gameplay_actions_for_cutscene()

	# ---------------------------------------------------------
	# Visual de cutscene
	# ---------------------------------------------------------
	if use_gameplay_visuals_in_cutscene:
		# Usamos el visual real del gameplay:
		# cuerpo, lámpara y luces quedan visibles.
		if gameplay_root != null:
			gameplay_root.visible = true

		# Ocultamos solo nodos de combate/aim/debug.
		_hide_gameplay_nodes_for_cutscene()

		# Apagamos el actor alternativo de cutscene para que no haya doble sprite.
		if cutscene_root != null:
			cutscene_root.visible = false
			_set_process_tree(cutscene_root, false)

		# Animación inicial usando el sprite real.
		cutscene_play_anim("Idle")
	else:
		# Comportamiento viejo:
		# ocultar Gameplay completo y usar Cutscene/AnimatedSprite3D.
		if gameplay_root != null:
			gameplay_root.visible = false
			_set_process_tree(gameplay_root, false)

		if cutscene_root != null:
			cutscene_root.visible = true
			_set_process_tree(cutscene_root, true)

		if cutscene_anim_sprite != null:
			cutscene_anim_sprite.visible = true

			if cutscene_anim_sprite.sprite_frames != null and cutscene_anim_sprite.sprite_frames.has_animation("Idle"):
				cutscene_anim_sprite.play("Idle")

	print("Player entró en modo cutscene")


func _exit_cutscene_mode() -> void:
	# Cortamos cualquier caminata de cutscene pendiente.
	cutscene_is_walking = false
	cutscene_walk_target = global_position

	# Frenamos movimiento residual.
	velocity = Vector3.ZERO

	if use_gameplay_visuals_in_cutscene:
		# Restauramos nodos ocultos de Gameplay.
		if gameplay_root != null:
			gameplay_root.visible = true

		_restore_gameplay_nodes_after_cutscene()

		# Mantenemos apagado el actor alternativo.
		if cutscene_root != null:
			cutscene_root.visible = false
			_set_process_tree(cutscene_root, false)
	else:
		# Comportamiento viejo:
		# apagamos actor de cutscene y restauramos gameplay entero.
		if cutscene_root != null:
			cutscene_root.visible = false
			_set_process_tree(cutscene_root, false)

		if gameplay_root != null:
			gameplay_root.visible = true
			_set_process_tree(gameplay_root, true)

	# Fade opcional al volver.
	#
	# Si estamos usando visuales de Gameplay durante cutscene,
	# por defecto NO fadeamos todo Gameplay, porque ya estaba visible.
	var should_fade_gameplay := use_gameplay_fade_in

	if use_gameplay_visuals_in_cutscene and disable_full_gameplay_fade_when_using_gameplay_visuals:
		should_fade_gameplay = false

	if should_fade_gameplay:
		_start_gameplay_fade_in()

	# Restauramos animación base del gameplay.
	if anim_sprite != null and not is_dead:
		anim_sprite.play("Idle")

	print("Player salió de modo cutscene")


func _cancel_gameplay_actions_for_cutscene() -> void:
	# Frenar dash.
	is_dashing = false
	dash_velocity = Vector3.ZERO
	dash_timer = 0.0
	dash_smear_spawn_timer = 0.0

	# Frenar movimiento físico.
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO

	# Apagar dash smear si quedó visible.
	if dash_smear_tween and dash_smear_tween.is_valid():
		dash_smear_tween.kill()

	if dash_smear != null:
		dash_smear.visible = false
		dash_smear.top_level = false

	# Cancelar visuales/estado de armas si el componente existe.
	if weapon_component != null:
		if weapon_component.has_method("cancel_attack_visuals"):
			weapon_component.cancel_attack_visuals()

		if weapon_component.has_method("release_shotgun"):
			weapon_component.release_shotgun()

		if weapon_component.has_method("release_boleadoras"):
			weapon_component.release_boleadoras()


func _set_process_tree(root: Node, enabled: bool) -> void:
	# Activa/desactiva process en un subárbol.
	#
	# Ojo:
	# En el modo nuevo de cutscene no apagamos Gameplay entero,
	# porque usamos su AnimatedSprite3D real.
	if root == null:
		return

	root.set_process(enabled)
	root.set_physics_process(enabled)
	root.set_process_input(enabled)
	root.set_process_unhandled_input(enabled)

	for child in root.get_children():
		_set_process_tree(child, enabled)


# =========================================================
# CUTSCENE GAMEPLAY NODE HIDING
# =========================================================
#
# En el modo nuevo no ocultamos Gameplay entero.
# Solo ocultamos nodos puntuales: Weapon, AimDebugLayer, DashSmear, etc.
# =========================================================

func _hide_gameplay_nodes_for_cutscene() -> void:
	_cutscene_hidden_gameplay_nodes_state.clear()

	for path in gameplay_nodes_to_hide_in_cutscene:
		if path == NodePath():
			continue

		var node := get_node_or_null(path)

		if node == null:
			continue

		if not is_instance_valid(node):
			continue

		if _cutscene_hidden_gameplay_nodes_state.has(node):
			continue

		_cutscene_hidden_gameplay_nodes_state[node] = _get_node_visible_generic(node)
		_set_node_visible_generic(node, false)


func _restore_gameplay_nodes_after_cutscene() -> void:
	for node in _cutscene_hidden_gameplay_nodes_state.keys():
		if node == null:
			continue

		if not is_instance_valid(node):
			continue

		var was_visible: bool = bool(_cutscene_hidden_gameplay_nodes_state[node])
		_set_node_visible_generic(node, was_visible)

	_cutscene_hidden_gameplay_nodes_state.clear()


func _get_node_visible_generic(node: Node) -> bool:
	if node == null:
		return false

	if _node_has_property(node, "visible"):
		return bool(node.get("visible"))

	return true


func _set_node_visible_generic(node: Node, visible_value: bool) -> void:
	if node == null:
		return

	if _node_has_property(node, "visible"):
		node.set("visible", visible_value)


# =========================================================
# CUTSCENE MOVEMENT
# =========================================================
#
# Helpers simples para que el CutsceneDirector pueda decir:
#
# await player.cutscene_walk_to(marker.global_position)
# player.cutscene_play_anim("Talk")
# player.cutscene_face_direction(Vector3.LEFT)
# =========================================================

func _physics_process_cutscene(delta: float) -> void:
	var lamp_input_dir := Vector2.ZERO

	if cutscene_is_walking:
		var to_target := cutscene_walk_target - global_position
		to_target.y = 0.0

		var distance := to_target.length()

		if distance <= cutscene_arrive_distance:
			# Llegamos al destino.
			global_position.x = cutscene_walk_target.x
			global_position.z = cutscene_walk_target.z

			velocity = Vector3.ZERO
			cutscene_is_walking = false

			cutscene_play_anim("Idle")
			cutscene_walk_finished.emit()

			if use_gameplay_visuals_in_cutscene:
				update_lamp_swing(delta, Vector2.ZERO)

			return

		var dir := to_target.normalized()

		velocity = dir * cutscene_walk_speed
		move_and_slide()

		cutscene_face_direction(dir)
		cutscene_play_anim("Walk")

		lamp_input_dir = Vector2(dir.x, dir.z)
	else:
		velocity = Vector3.ZERO
		move_and_slide()
		cutscene_play_anim("Idle")

	# Si usamos el visual de gameplay durante cutscene,
	# permitimos un balanceo suave de lámpara durante caminata.
	if use_gameplay_visuals_in_cutscene:
		update_lamp_swing(delta, lamp_input_dir)


func cutscene_walk_to(target_position: Vector3, walk_speed: float = 2.5) -> void:
	# Si alguien llama esto desde afuera y todavía no estamos en cutscene,
	# entramos automáticamente al modo cutscene.
	if not is_cutscene_mode:
		set_cutscene_mode(true)

	cutscene_walk_target = target_position
	cutscene_walk_speed = walk_speed

	var flat_to_target := cutscene_walk_target - global_position
	flat_to_target.y = 0.0

	if flat_to_target.length() <= cutscene_arrive_distance:
		global_position.x = cutscene_walk_target.x
		global_position.z = cutscene_walk_target.z
		velocity = Vector3.ZERO
		cutscene_play_anim("Idle")
		return

	cutscene_is_walking = true
	cutscene_face_direction(flat_to_target.normalized())
	cutscene_play_anim("Walk")

	await cutscene_walk_finished


func cutscene_stop_walk() -> void:
	# Útil para skip/cancel de cutscene.
	#
	# Además de frenar el movimiento, emitimos cutscene_walk_finished
	# para destrabar cualquier await pendiente en:
	#
	# await player.cutscene_walk_to(...)
	cutscene_is_walking = false
	velocity = Vector3.ZERO
	cutscene_play_anim("Idle")

	cutscene_walk_finished.emit()


func cutscene_play_anim(anim_name: String) -> void:
	# ---------------------------------------------------------
	# Modo nuevo:
	# usar el AnimatedSprite3D real de Gameplay.
	# ---------------------------------------------------------
	if use_gameplay_visuals_in_cutscene:
		if anim_sprite == null:
			return

		if anim_sprite.sprite_frames == null:
			return

		if not anim_sprite.sprite_frames.has_animation(anim_name):
			return

		if anim_sprite.animation != anim_name:
			anim_sprite.play(anim_name)

		return

	# ---------------------------------------------------------
	# Modo viejo:
	# usar Cutscene/AnimatedSprite3D.
	# ---------------------------------------------------------
	if cutscene_anim_sprite == null:
		return

	if cutscene_anim_sprite.sprite_frames == null:
		return

	if not cutscene_anim_sprite.sprite_frames.has_animation(anim_name):
		return

	if cutscene_anim_sprite.animation != anim_name:
		cutscene_anim_sprite.play(anim_name)


func cutscene_face_direction(direction: Vector3) -> void:
	if abs(direction.x) <= 0.01:
		return

	var facing_left := direction.x < 0.0

	# ---------------------------------------------------------
	# Modo nuevo:
	# flip del visual real de Gameplay.
	# ---------------------------------------------------------
	if use_gameplay_visuals_in_cutscene:
		if sprites != null:
			sprites.scale.x = 1.0 if facing_left else -1.0

		if anim_sprite != null:
			anim_sprite.flip_h = facing_left

		return

	# ---------------------------------------------------------
	# Modo viejo:
	# flip del sprite alternativo de Cutscene.
	# ---------------------------------------------------------
	if cutscene_anim_sprite != null:
		cutscene_anim_sprite.flip_h = facing_left


# =========================================================
# GAMEPLAY FADE IN
# =========================================================

func _start_gameplay_fade_in() -> void:
	if gameplay_root == null:
		return

	# Si había un fade anterior, restauramos antes de arrancar otro.
	_kill_gameplay_fade_tween(true)

	if gameplay_fade_in_duration <= 0.0:
		return

	var fade_targets: Array[Node] = []
	_collect_gameplay_fade_targets(gameplay_root, fade_targets)

	if fade_targets.is_empty():
		return

	_gameplay_fade_original_state.clear()

	_gameplay_fade_tween = create_tween()
	_gameplay_fade_tween.set_parallel(true)
	_gameplay_fade_tween.set_trans(gameplay_fade_trans)
	_gameplay_fade_tween.set_ease(gameplay_fade_ease)

	var tween_count := 0

	for node in fade_targets:
		if node == null:
			continue

		if not is_instance_valid(node):
			continue

		# -----------------------------------------------------
		# Nodos visuales con modulate
		# -----------------------------------------------------
		if _node_has_property(node, "modulate"):
			var modulate_value = node.get("modulate")

			if modulate_value is Color:
				var original_color: Color = modulate_value

				_gameplay_fade_original_state[node] = {
					"type": "modulate",
					"color": original_color
				}

				var transparent_color := original_color
				transparent_color.a = 0.0
				node.set("modulate", transparent_color)

				_gameplay_fade_tween.tween_property(
					node,
					"modulate:a",
					original_color.a,
					gameplay_fade_in_duration
				)

				tween_count += 1

		# -----------------------------------------------------
		# Luces 3D
		# -----------------------------------------------------
		elif node is Light3D:
			var light := node as Light3D
			var original_energy := light.light_energy

			_gameplay_fade_original_state[node] = {
				"type": "light",
				"energy": original_energy
			}

			light.light_energy = 0.0

			_gameplay_fade_tween.tween_property(
				light,
				"light_energy",
				original_energy,
				gameplay_fade_in_duration
			)

			tween_count += 1

	if tween_count <= 0:
		_kill_gameplay_fade_tween(false)
		_gameplay_fade_original_state.clear()
		return

	_gameplay_fade_tween.finished.connect(_on_gameplay_fade_in_finished)


func _on_gameplay_fade_in_finished() -> void:
	# Restauramos exacto por seguridad.
	_restore_gameplay_fade_original_state()

	_gameplay_fade_tween = null
	_gameplay_fade_original_state.clear()


func _kill_gameplay_fade_tween(restore_original_state: bool = false) -> void:
	if _gameplay_fade_tween != null and _gameplay_fade_tween.is_valid():
		_gameplay_fade_tween.kill()

	_gameplay_fade_tween = null

	if restore_original_state:
		_restore_gameplay_fade_original_state()


func _restore_gameplay_fade_original_state() -> void:
	for node in _gameplay_fade_original_state.keys():
		if node == null:
			continue

		if not is_instance_valid(node):
			continue

		var state: Dictionary = _gameplay_fade_original_state[node]
		var state_type: String = str(state.get("type", ""))

		match state_type:
			"modulate":
				var original_color: Color = state.get("color", Color.WHITE)
				node.set("modulate", original_color)

			"light":
				if node is Light3D:
					var light := node as Light3D
					light.light_energy = float(state.get("energy", light.light_energy))


func _collect_gameplay_fade_targets(root: Node, result: Array[Node]) -> void:
	if root == null:
		return

	var skip_this_node := false

	if gameplay_fade_excluded_group != &"" and root.is_in_group(gameplay_fade_excluded_group):
		skip_this_node = true

	if exclude_animated_sprites_from_gameplay_fade and root is AnimatedSprite3D:
		skip_this_node = true

	if not skip_this_node:
		if _node_has_property(root, "modulate"):
			result.append(root)
		elif root is Light3D:
			result.append(root)

	for child in root.get_children():
		_collect_gameplay_fade_targets(child, result)


func _node_has_property(node: Object, property_name: String) -> bool:
	if node == null:
		return false

	for property_info in node.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true

	return false


# =========================================================
# DASH
# =========================================================

func start_dash(direction: Vector3, distance: float, duration: float) -> void:
	# No permitir dash durante cutscene.
	if is_cutscene_mode:
		return

	is_dashing = true
	dash_timer = duration
	dash_smear_spawn_timer = 0.0

	var dash_speed := distance / duration
	dash_velocity = direction * dash_speed

	# Opcional: cancelar knockback al arrancar dash.
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
	# aim_dir se actualiza en update_cursor().
	if aim_dir.length_squared() > 0.0001:
		return aim_dir.normalized()

	return Vector3.ZERO


# =========================================================
# AIM / CURSOR
# =========================================================

func update_cursor() -> void:
	if is_cutscene_mode:
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()

	var player_screen_pos: Vector2 = camera.unproject_position(global_position + Vector3(0.0, 0.8, 0.0))
	var mouse_to_player_px: float = mouse_pos.distance_to(player_screen_pos)

	if mouse_to_player_px < aim_deadzone_screen_px:
		return

	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)

	var plane := Plane(Vector3.UP, global_position.y)
	var hit = plane.intersects_ray(ray_origin, ray_dir)

	if hit == null:
		return

	var dir: Vector3 = hit - global_position
	dir.y = 0.0

	if dir.length_squared() > 0.0001:
		aim_dir = dir.normalized()
		aim_angle = atan2(dir.x, dir.z)
		cursor.rotation.y = aim_angle
		handle_flip(dir)


func handle_flip(dir: Vector3) -> void:
	var facing_left = dir.x < 0.0
	sprites.scale.x = 1.0 if facing_left else -1.0
	anim_sprite.flip_h = facing_left


# =========================================================
# DAMAGE / KNOCKBACK
# =========================================================

func apply_knockback(dir: Vector3, force: float = 4.5) -> void:
	if is_dead:
		return

	if is_cutscene_mode:
		return

	if is_sapukai_invulnerable():
		return

	dir.y = 0.0

	if dir.length_squared() <= 0.0001:
		return

	knockback_velocity = dir.normalized() * force


func apply_shotgun_recoil(dir: Vector3, force: float = 3.0) -> void:
	if is_dead:
		return

	if is_cutscene_mode:
		return

	if is_dashing:
		return

	dir.y = 0.0

	if dir.length_squared() <= 0.0001:
		return

	knockback_velocity += dir.normalized() * force


func take_damage(amount: int) -> void:
	if is_dead:
		return

	if is_cutscene_mode:
		return

	if is_sapukai_invulnerable():
		return

	hp = max(hp - amount, 0)
	hp_changed.emit(hp, max_hp)

	if not is_instance_valid(screen_fx):
		screen_fx = get_tree().get_first_node_in_group("screen_fx")

	if screen_fx and screen_fx.has_method("play_damage_feedback"):
		screen_fx.play_damage_feedback()

	sapukai.add_fury_from_damage_taken(amount)

	if hp <= 0:
		die()


func die() -> void:
	if is_dead:
		return

	is_dead = true

	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	cutscene_is_walking = false

	if weapon_component != null:
		weapon_component.cancel_attack_visuals()

	if weapon_pivot != null:
		weapon_pivot.visible = false

	if light_sprite != null:
		light_sprite.visible = false

	if cursor != null:
		cursor.visible = false

	if anim_sprite != null:
		anim_sprite.play("Died")


# =========================================================
# ANIMACIÓN GAMEPLAY
# =========================================================

func update_animation(input_dir: Vector2) -> void:
	if is_dead:
		return

	if is_cutscene_mode:
		return

	if input_dir.length() > 0.0:
		if anim_sprite.animation != "Walk":
			anim_sprite.play("Walk")
	else:
		if anim_sprite.animation != "Idle":
			anim_sprite.play("Idle")


# =========================================================
# LÁMPARA
# =========================================================

func update_pivot_light() -> void:
	if is_cutscene_mode:
		return

	var offset := Vector3(0.0, 0.8, weapon_component.get_current_weapon_radius())
	offset = offset.rotated(Vector3.UP, aim_angle)
	weapon_light.position = offset


func update_lamp_swing(delta: float, input_dir: Vector2) -> void:
	if lamp_visual == null:
		return

	# Si estamos en cutscene con el modo viejo, Gameplay está oculto.
	if is_cutscene_mode and not use_gameplay_visuals_in_cutscene:
		return

	if is_dead:
		lamp_current_angle_rad = lerp_angle(
			lamp_current_angle_rad,
			lamp_base_angle_rad,
			lamp_return_speed * delta
		)

		lamp_visual.set_manual_angle_radians(lamp_current_angle_rad)
		return

	if input_dir.length() > 0.0:
		lamp_swing_time += delta * lamp_swing_speed

		var swing_angle_rad := deg_to_rad(lamp_swing_angle_deg) * sin(lamp_swing_time)
		var target_angle := lamp_base_angle_rad + swing_angle_rad

		lamp_current_angle_rad = lerp_angle(
			lamp_current_angle_rad,
			target_angle,
			10.0 * delta
		)

		lamp_visual.set_manual_angle_radians(lamp_current_angle_rad)
	else:
		lamp_current_angle_rad = lerp_angle(
			lamp_current_angle_rad,
			lamp_base_angle_rad,
			lamp_return_speed * delta
		)

		lamp_visual.set_manual_angle_radians(lamp_current_angle_rad)


# =========================================================
# SKILLS / PROGRESO
# =========================================================

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


# =========================================================
# DASH SMEAR
# =========================================================

func play_dash_smear(direction: Vector3) -> void:
	if is_cutscene_mode:
		return

	if dash_smear_tween and dash_smear_tween.is_valid():
		dash_smear_tween.kill()

	var dir := direction.normalized()
	var back_offset := -dir * 0.7

	dash_smear.top_level = true
	dash_smear.visible = true
	dash_smear.modulate.a = 0.45

	dash_smear.global_position = global_position + Vector3(0.0, 0.8, 0.0) + back_offset

	dash_smear.rotation = Vector3.ZERO
	dash_smear.rotation.y = atan2(dir.x, dir.z)

	dash_smear.scale = Vector3(0.8, 1.0, 2.2)

	dash_smear_tween = create_tween()
	dash_smear_tween.parallel().tween_property(dash_smear, "modulate:a", 0.0, 1.12)
	dash_smear_tween.parallel().tween_property(dash_smear, "scale", Vector3(0.4, 1.0, 0.8), 1.12)

	await dash_smear_tween.finished
	dash_smear.visible = false
	dash_smear.top_level = false


func spawn_dash_smear_ghost(direction: Vector3) -> void:
	if is_cutscene_mode:
		return

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


# =========================================================
# SAPUKAI
# =========================================================

func _on_sapukai_started():
	if anim_sprite != null:
		anim_sprite.modulate = Color(0.885, 0.064, 0.413, 1.0)

	if sapukai_sprite != null:
		sapukai_sprite.visible = true


func _on_sapukai_ended():
	if anim_sprite != null:
		anim_sprite.modulate = Color(1, 1, 1)

	if sapukai_sprite != null:
		sapukai_sprite.visible = false


func is_sapukai_invulnerable() -> bool:
	return sapukai != null and sapukai.is_active
