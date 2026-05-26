extends CutsceneEvent
class_name SecondRadioCutscene

# =========================================================
# CUTSCENE
# =========================================================

# =========================================================
# CONFIGURACIÓN: ENEMIGO
# =========================================================

# Escena del enemigo a instanciar.
# Arrastrá acá tu Enemy.tscn desde el Inspector.
@export var enemy_scene: PackedScene

# Nodo padre donde se agregan enemigos.
#
# Si SecondRadioCutscene es hijo de Main:
# ../Enemies
#
# Si no existe, usa el padre de esta cutscene como fallback.
@export var enemies_parent_path: NodePath = ^"../Enemies"

# Si está activo, el enemigo queda visible apenas aparece.
@export var enemy_visible_on_spawn: bool = true

# Si está activo, el enemigo empieza con can_chase = true apenas aparece.
#
# Si está apagado:
# - aparece quieto durante la cutscene
# - se activa después del camera_restore / final de cutscene
@export var enemy_can_chase_on_spawn: bool = true

# Si está activo, igual forzamos can_chase = true cuando termina la cutscene.
#
# Recomendado dejarlo activo.
# Si enemy_can_chase_on_spawn ya era true, no cambia nada.
@export var activate_enemy_after_cutscene: bool = true


# =========================================================
# CONFIGURACIÓN: SPAWN DINÁMICO
# =========================================================

# Si está activo, calcula el spawn relativo al jugador.
#
# Recomendado para encuentros narrativos:
# el enemigo aparece cerca del jugador aunque el player
# no esté exactamente en un punto fijo del mapa.
@export var use_dynamic_enemy_spawn: bool = true

# Distancia desde el jugador donde aparece el enemigo.
@export_range(0.5, 40.0, 0.1) var dynamic_enemy_spawn_distance: float = 8.0

# Altura extra del spawn.
#
# Normalmente dejalo en 0.
# Si el enemigo aparece medio enterrado o muy abajo, podés subirlo un poco.
@export var dynamic_enemy_spawn_y_offset: float = 0.0

# Modo de aparición relativo al jugador.
#
# random_ring:
# - aparece en un punto random alrededor del jugador.
#
# left/right/front/back:
# - aparece en una dirección fija del mundo.
#
# player_left/player_right:
# - intenta usar el flip visual del player para elegir lado.
@export_enum(
	"random_ring",
	"left",
	"right",
	"front",
	"back",
	"player_left",
	"player_right"
) var dynamic_enemy_spawn_mode: String = "random_ring"

# Si usás random_ring, podés limitar el arco.
#
# 360 = puede aparecer desde cualquier lado.
# 120 = aparece dentro de un arco más cerrado.
#
# En esta versión el arco limitado está centrado hacia la derecha del mundo.
@export_range(1.0, 360.0, 1.0) var dynamic_enemy_spawn_random_arc_degrees: float = 360.0


# =========================================================
# CONFIGURACIÓN: SAFE SPAWN / NAVMESH
# =========================================================
#
# Esto reduce mucho la chance de que el enemigo aparezca:
# - dentro de una pared
# - fuera del navmesh
# - en un punto desconectado del jugador
# - demasiado lejos del punto deseado
# =========================================================

# Si está activo, el spawn dinámico se valida usando NavigationServer3D.
@export var use_navmesh_safe_spawn: bool = true

# Cantidad de intentos para encontrar un punto válido.
# Más intentos = más robusto, pero un poco más caro.
@export_range(1, 64, 1) var safe_spawn_attempts: int = 16

# Distancia máxima permitida entre el punto random deseado
# y el punto más cercano encontrado en el navmesh.
#
# Si el navmesh más cercano está muy lejos, probablemente
# el punto cayó en una zona mala.
@export_range(0.1, 10.0, 0.1) var max_navmesh_snap_distance: float = 2.0

# Distancia mínima al jugador después de proyectar al navmesh.
#
# Esto evita que el navmesh snap acerque demasiado el enemigo.
@export_range(0.1, 20.0, 0.1) var safe_spawn_min_distance_to_player: float = 3.0

# Si está activo, se imprime info de cada spawn validado.
@export var debug_safe_spawn: bool = false


# =========================================================
# CONFIGURACIÓN: SPAWN POR MARKER / FALLBACK
# =========================================================
#
# Estos se usan si:
# - use_dynamic_enemy_spawn = false
# - o no se pudo resolver el player
# - o no se encontró un punto seguro en navmesh
# =========================================================

# Marker manual donde aparece el enemigo.
#
# Puede ser hijo de esta cutscene:
#
# SecondRadioCutscene
# └── EnemySpawnMarker
@export var enemy_spawn_marker_path: NodePath = ^"EnemySpawnMarker"

# Fallback si no encuentra marker.
# Spawnea relativo al jugador.
@export var enemy_spawn_fallback_offset: Vector3 = Vector3(3.0, 0.0, 2.0)


# =========================================================
# CONFIGURACIÓN: TERCERA CUTSCENE
# =========================================================

# Cutscene que se dispara cuando muere este enemigo.
@export var third_cutscene_path: NodePath = ^"../ThirdRadioCutscene"


# =========================================================
# ESTADO INTERNO
# =========================================================

# Evita disparar la tercera cutscene más de una vez.
var _third_cutscene_started: bool = false

# Referencia al enemigo creado.
var _encounter_enemy: Node3D = null


# =========================================================
# RUN CUTSCENE CUSTOM
# =========================================================

func run_cutscene(player_override: Node = null) -> void:
	# ---------------------------------------------------------
	# Guardas base copiadas del flujo normal de CutsceneEvent
	# ---------------------------------------------------------
	if _is_running:
		return

	if trigger_once and _already_used:
		return

	var director := _resolve_director()

	if director == null:
		push_warning("%s: no se encontró CutsceneDirector." % name)
		return

	if not director.has_method("run_commands"):
		push_warning("%s: el director no tiene run_commands()." % name)
		return

	var player := player_override

	if player == null:
		player = _get_configured_player()

	_is_running = true
	_already_used = true

	if print_debug:
		print("SecondRadioCutscene: start")

	# ---------------------------------------------------------
	# 1) Primera parte de la cutscene
	# ---------------------------------------------------------
	# auto_begin = true
	# auto_end = false
	#
	# Esto inicia la cutscene pero NO la termina todavía,
	# porque necesitamos spawnear el enemigo antes del camera_restore.
	var completed_before_spawn_result: Variant = await director.run_commands(
		player,
		get_commands_before_enemy_spawn(),
		self,
		true,
		false
	)

	var completed_before_spawn: bool = bool(completed_before_spawn_result)

	if not completed_before_spawn:
		_is_running = false
		return

	# ---------------------------------------------------------
	# 2) Spawn del enemigo
	# ---------------------------------------------------------
	_spawn_encounter_enemy(player)

	# ---------------------------------------------------------
	# 3) Segunda parte de la cutscene
	# ---------------------------------------------------------
	# auto_begin = false
	# auto_end = true
	#
	# No vuelve a iniciar cutscene porque ya está activa.
	# Al terminar camera_restore, el director hace end()
	# y libera al jugador.
	var completed_after_spawn_result: Variant = await director.run_commands(
		player,
		get_commands_after_enemy_spawn(),
		self,
		false,
		true
	)

	var completed_after_spawn: bool = bool(completed_after_spawn_result)

	_is_running = false

	if print_debug:
		print("SecondRadioCutscene: finished completed=", completed_after_spawn)

	# Si la cutscene fue cancelada/skipeada después de spawnear,
	# activamos al enemigo igual para que no quede congelado.
	if not completed_after_spawn:
		if activate_enemy_after_cutscene:
			_activate_encounter_enemy()
		return

	# ---------------------------------------------------------
	# 4) Activación post-cutscene
	# ---------------------------------------------------------
	# Esto ocurre después de que CutsceneDirector hizo end(),
	# por lo tanto el jugador ya está libre.
	if activate_enemy_after_cutscene:
		_activate_encounter_enemy()


# =========================================================
# COMANDOS: ANTES DEL ENEMIGO
# =========================================================

func get_commands_before_enemy_spawn() -> Array:
	return [
		{
			"type": "wait",
			"seconds": 1.30
		},
		{
			"type": "camera_zoom",
			"value": 28.0,
			"duration": 0.45
		},
		{
			"type": "player_face_direction",
			"direction": "right"
		},
		{
			"type": "say",
			"speaker": "Diego",
			"text": "Mm...[p] ya no es el viento.[p] Lo escucho otra vez."
		},
		{
			"type": "wait",
			"seconds": 0.45
		},
		{
			"type": "say",
			"speaker": "Luisón",
			"text": "Chamigo no tenga miedo.[p] ¿Que e’ lo que ves?"
		},
		{
			"type": "wait",
			"seconds": 1.00
		},
		{
			"type": "say",
			"speaker": "Diego",
			"text": "Es...[p] una mujer.[p] Está llorando.[p] No logro ubicar de dónde viene,[p] pero sé que viene de lejos."
		},
		{
			"type": "wait",
			"seconds": 0.45
		},
		{
			"type": "say",
			"speaker": "Luisón",
			"text": "Chamigo tranquilo.[p] Trata de quedarte por ai’,[p] escondido."
		},
		{
			"type": "wait",
			"seconds": 1.45
		},
		{
			"type": "say",
			"speaker": "Diego",
			"text": "No me des bola hermano...[p] es solo un animal que se acerca,[p] estoy\nimaginándome todo."
		}
	]


# =========================================================
# COMANDOS: DESPUÉS DEL ENEMIGO
# =========================================================

func get_commands_after_enemy_spawn() -> Array:
	return [
		{
			"type": "camera_restore",
			"duration": 0.45
		}
	]


# =========================================================
# SPAWN / ACTIVACIÓN DEL ENEMIGO
# =========================================================

func _spawn_encounter_enemy(player: Node = null) -> void:
	if enemy_scene == null:
		push_warning("%s: enemy_scene no está asignado." % name)
		return

	var enemy_instance := enemy_scene.instantiate() as Node3D

	if enemy_instance == null:
		push_warning("%s: enemy_scene no instancia un Node3D." % name)
		return

	var parent := _resolve_enemies_parent()

	if parent == null:
		push_warning("%s: no se encontró enemies_parent_path." % name)
		enemy_instance.queue_free()
		return

	parent.add_child(enemy_instance)

	_encounter_enemy = enemy_instance

	# Posición de aparición.
	enemy_instance.global_position = _get_enemy_spawn_position(player)

	# Visibilidad inicial.
	enemy_instance.visible = enemy_visible_on_spawn

	# Persecución inicial.
	_set_enemy_can_chase(enemy_instance, enemy_can_chase_on_spawn)

	# Conectamos muerte para disparar ThirdRadioCutscene.
	if enemy_instance.has_signal("died"):
		enemy_instance.connect(
			"died",
			Callable(self, "_on_encounter_enemy_died").bind(enemy_instance),
			CONNECT_ONE_SHOT
		)
	else:
		push_warning("%s: el enemigo no tiene señal died." % name)

	if print_debug:
		print("SecondRadioCutscene: enemigo spawneado en ", enemy_instance.global_position)


func _activate_encounter_enemy() -> void:
	if _encounter_enemy == null:
		return

	if not is_instance_valid(_encounter_enemy):
		return

	_set_enemy_can_chase(_encounter_enemy, true)

	if print_debug:
		print("SecondRadioCutscene: enemigo activado")


func _set_enemy_can_chase(enemy: Node, value: bool) -> void:
	if enemy == null:
		return

	if not is_instance_valid(enemy):
		return

	if _object_has_property(enemy, "can_chase"):
		enemy.set("can_chase", value)
	else:
		push_warning("%s: el enemigo no tiene propiedad can_chase." % name)


func _resolve_enemies_parent() -> Node:
	if enemies_parent_path != NodePath():
		var parent := get_node_or_null(enemies_parent_path)

		if parent != null:
			return parent

	# Fallback: si no existe Enemies, usa el padre de esta cutscene.
	return get_parent()


# =========================================================
# SPAWN POSITION
# =========================================================

func _get_enemy_spawn_position(player: Node = null) -> Vector3:
	# ---------------------------------------------------------
	# 1) Spawn dinámico relativo al jugador
	# ---------------------------------------------------------
	if use_dynamic_enemy_spawn:
		var player_node := _get_player_as_node3d(player)

		if player_node != null:
			if use_navmesh_safe_spawn:
				# Esta función puede devolver:
				# - Vector3 si encontró un punto válido
				# - null si no encontró nada bueno
				#
				# Por eso NO podemos tiparla como Vector3 directamente.
				var safe_position: Variant = _get_safe_dynamic_spawn_position(player_node)

				if safe_position is Vector3:
					return safe_position

			# Si no encontró punto seguro en navmesh,
			# usamos el spawn dinámico común.
			return _get_dynamic_spawn_position_around_player(player_node)

	# ---------------------------------------------------------
	# 2) Spawn por Marker3D
	# ---------------------------------------------------------
	var marker := get_node_or_null(enemy_spawn_marker_path) as Node3D

	if marker != null:
		return marker.global_position

	# ---------------------------------------------------------
	# 3) Fallback relativo al player
	# ---------------------------------------------------------
	var fallback_player := _get_player_as_node3d(player)

	if fallback_player != null:
		return fallback_player.global_position + enemy_spawn_fallback_offset

	# ---------------------------------------------------------
	# 4) Fallback absoluto
	# ---------------------------------------------------------
	return enemy_spawn_fallback_offset


func _get_player_as_node3d(player: Node = null) -> Node3D:
	# Devuelve el player como Node3D, venga de:
	# - player_override
	# - player configurado en CutsceneEvent
	# - grupo "player"

	if player != null and player is Node3D:
		return player as Node3D

	var configured_player := _get_configured_player()

	if configured_player != null and configured_player is Node3D:
		return configured_player as Node3D

	return null


func _get_dynamic_spawn_position_around_player(player_node: Node3D) -> Vector3:
	# Calcula una posición alrededor del jugador.
	#
	# Usa X/Z para mantenerlo en plano 2.5D.
	# La Y se toma desde el jugador + offset configurable.

	var direction := _get_dynamic_spawn_direction(player_node)

	if direction.length_squared() <= 0.0001:
		direction = Vector3.RIGHT

	direction.y = 0.0
	direction = direction.normalized()

	var result := player_node.global_position
	result += direction * dynamic_enemy_spawn_distance
	result.y += dynamic_enemy_spawn_y_offset

	return result


func _get_safe_dynamic_spawn_position(player_node: Node3D) -> Variant:
	# Busca un punto dinámico alrededor del jugador, pero validado
	# contra el NavigationMesh.
	#
	# Devuelve:
	# - Vector3 si encontró un punto bueno.
	# - null si no encontró nada válido.
	#
	# Pasos por intento:
	# 1) Genera una dirección alrededor del player.
	# 2) Calcula raw_position.
	# 3) Busca el punto más cercano del navmesh.
	# 4) Rechaza si el snap fue demasiado grande.
	# 5) Rechaza si quedó demasiado cerca del player.
	# 6) Pide un path hacia el jugador.
	# 7) Si hay path útil, usa ese punto.

	var navigation_map: RID = player_node.get_world_3d().navigation_map

	if not navigation_map.is_valid():
		return null

	var player_position := player_node.global_position

	for attempt in range(safe_spawn_attempts):
		var direction := _get_dynamic_spawn_direction(player_node)

		if direction.length_squared() <= 0.0001:
			direction = Vector3.RIGHT

		direction.y = 0.0
		direction = direction.normalized()

		var raw_position := player_position + direction * dynamic_enemy_spawn_distance
		raw_position.y += dynamic_enemy_spawn_y_offset

		var nav_position: Vector3 = NavigationServer3D.map_get_closest_point(
			navigation_map,
			raw_position
		)

		var snap_distance: float = raw_position.distance_to(nav_position)

		if snap_distance > max_navmesh_snap_distance:
			if debug_safe_spawn:
				print("Safe spawn intento ", attempt, " rechazado: snap_distance=", snap_distance)
			continue

		var flat_to_player := player_position - nav_position
		flat_to_player.y = 0.0

		if flat_to_player.length() < safe_spawn_min_distance_to_player:
			if debug_safe_spawn:
				print("Safe spawn intento ", attempt, " rechazado: demasiado cerca del player.")
			continue

		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			navigation_map,
			nav_position,
			player_position,
			true
		)

		if path.size() < 2:
			if debug_safe_spawn:
				print("Safe spawn intento ", attempt, " rechazado: sin path útil.")
			continue

		nav_position.y += dynamic_enemy_spawn_y_offset

		if debug_safe_spawn:
			print("Safe spawn válido en intento ", attempt, ": ", nav_position)

		return nav_position

	if debug_safe_spawn:
		print("Safe spawn falló: usando fallback dinámico.")

	return null


func _get_dynamic_spawn_direction(player_node: Node3D) -> Vector3:
	match dynamic_enemy_spawn_mode:
		"left":
			return Vector3.LEFT

		"right":
			return Vector3.RIGHT

		"front":
			return Vector3.FORWARD

		"back":
			return Vector3.BACK

		"player_left":
			return _get_player_visual_side_direction(player_node, true)

		"player_right":
			return _get_player_visual_side_direction(player_node, false)

		"random_ring":
			return _get_random_spawn_ring_direction()

		_:
			return _get_random_spawn_ring_direction()


func _get_random_spawn_ring_direction() -> Vector3:
	# Dirección random alrededor del jugador.
	#
	# Si dynamic_enemy_spawn_random_arc_degrees = 360:
	# - puede aparecer desde cualquier lado.
	#
	# Si lo bajás, por ejemplo a 120:
	# - aparece dentro de un arco más acotado.
	#
	# En esta versión, el arco limitado está centrado hacia la derecha
	# del mundo. Si después querés centrarlo respecto al player/cámara,
	# lo ajustamos.

	var arc_degrees: float = dynamic_enemy_spawn_random_arc_degrees

	if arc_degrees >= 359.0:
		var full_angle: float = randf_range(0.0, TAU)
		return Vector3(cos(full_angle), 0.0, sin(full_angle))

	var arc_radians: float = deg_to_rad(arc_degrees)
	var half_arc: float = arc_radians * 0.5
	var angle: float = randf_range(-half_arc, half_arc)

	return Vector3(cos(angle), 0.0, sin(angle))


func _get_player_visual_side_direction(player_node: Node3D, want_left: bool) -> Vector3:
	# Intenta deducir hacia qué lado visual mira el player.
	#
	# En tu Player, el flip vive en:
	#
	# Gameplay/Sprites.scale.x
	#
	# Según tu lógica:
	# - scale.x = 1.0  => mirando izquierda
	# - scale.x = -1.0 => mirando derecha
	#
	# Si no encuentra el nodo Sprites, cae a izquierda/derecha global.

	var sprites_node := player_node.get_node_or_null("Gameplay/Sprites") as Node3D

	if sprites_node == null:
		return Vector3.LEFT if want_left else Vector3.RIGHT

	var facing_left: bool = sprites_node.scale.x > 0.0

	if want_left:
		return Vector3.LEFT if facing_left else Vector3.RIGHT

	return Vector3.RIGHT if facing_left else Vector3.LEFT


# =========================================================
# MUERTE DEL ENEMIGO → THIRD CUTSCENE
# =========================================================

func _on_encounter_enemy_died(enemy: Node = null) -> void:
	if _third_cutscene_started:
		return

	_third_cutscene_started = true

	# Esperamos un frame para dejar que el flujo de muerte del enemigo
	# procese bien su señal antes de iniciar otra cutscene.
	await get_tree().process_frame

	await _wait_until_no_cutscene_running()

	var third_cutscene := get_node_or_null(third_cutscene_path)

	if third_cutscene == null:
		push_warning("%s: no se encontró ThirdRadioCutscene." % name)
		return

	if not third_cutscene.has_method("run_cutscene"):
		push_warning("%s: ThirdRadioCutscene no tiene run_cutscene()." % name)
		return

	var player := _get_configured_player()

	if print_debug:
		print("SecondRadioCutscene: iniciando ThirdRadioCutscene")

	await third_cutscene.run_cutscene(player)


func _wait_until_no_cutscene_running() -> void:
	while _is_any_cutscene_running():
		await get_tree().process_frame


func _is_any_cutscene_running() -> bool:
	var director := get_tree().get_first_node_in_group("cutscene_director")

	if director == null:
		return false

	if "is_running" in director:
		return bool(director.is_running)

	return false


# =========================================================
# HELPERS
# =========================================================

func _object_has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false

	for property_info in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true

	return false
