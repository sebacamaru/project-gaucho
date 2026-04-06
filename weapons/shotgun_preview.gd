extends MeshInstance3D
class_name ShotgunPreview

# =========================================================
# CONFIGURACIÓN
# =========================================================

# Alcance máximo visual del preview.
# Idealmente debería coincidir con shotgun_base_stats["range"].
@export var preview_range: float = 5.0

# Apertura total del cono en grados.
# Idealmente debería coincidir con cone_angle_deg.
@export var preview_angle_deg: float = 55.0

# Cantidad de segmentos usados para formar el abanico.
# Más segmentos = borde más suave
# Menos segmentos = menos geometría
@export var segments: int = 24

# Color del preview.
# Alpha bajo para que no tape demasiado la escena.
@export var color: Color = Color(0.984, 0.161, 0.365, 0.122)


func _ready() -> void:
	# El preview nunca debe proyectar sombra.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Construimos el mesh inicial.
	mesh = _build_fan_mesh(
		preview_range,
		preview_angle_deg,
		segments
	)

	# Aplicamos material translúcido.
	material_override = _build_material()

	# Arranca oculto.
	# Solo se muestra al apuntar.
	visible = false


# Permite actualizar el cono en runtime.
# Muy útil si cambia el rango o el ángulo con upgrades.
func configure(range_value: float, angle_value: float) -> void:
	preview_range = range_value
	preview_angle_deg = angle_value

	mesh = _build_fan_mesh(
		preview_range,
		preview_angle_deg,
		segments
	)


# =========================================================
# MATERIAL
# =========================================================

# Material simple, sin iluminación,
# pensado para UI de gameplay.
func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()

	# No recibe luz, mantiene color consistente.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Habilita transparencia por alpha.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Color configurable.
	mat.albedo_color = color

	# Visible desde ambos lados.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Mantiene depth test para que no atraviese todo.
	mat.no_depth_test = false

	return mat


# =========================================================
# CONSTRUCCIÓN DEL MESH
# =========================================================

# Construye una malla tipo abanico sobre el plano XZ.
#
# Visualmente es como una porción de pizza:
# - centro en el origen
# - radio = range
# - apertura = angle_deg
#
# El frente apunta hacia +Z
func _build_fan_mesh(
	range_value: float,
	angle_deg: float,
	segs: int
) -> ArrayMesh:
	var st := SurfaceTool.new()

	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Mitad del ángulo total.
	# Ej: 55° -> 27.5° a cada lado
	var half_angle: float = deg_to_rad(angle_deg) * 0.5

	# Punto central del cono
	var center: Vector3 = Vector3.ZERO

	# Construimos el abanico en segmentos triangulares.
	for i in range(segs):
		# Interpolación normalizada 0 -> 1
		var t0: float = float(i) / float(segs)
		var t1: float = float(i + 1) / float(segs)

		# Ángulos interpolados entre borde izquierdo y derecho
		var a0: float = lerpf(-half_angle, half_angle, t0)
		var a1: float = lerpf(-half_angle, half_angle, t1)

		# Punto del borde izquierdo del segmento
		var p0: Vector3 = Vector3(
			sin(a0) * range_value,
			0.0,
			cos(a0) * range_value
		)

		# Punto del borde derecho del segmento
		var p1: Vector3 = Vector3(
			sin(a1) * range_value,
			0.0,
			cos(a1) * range_value
		)

		# Triángulo: centro -> p0 -> p1
		st.add_vertex(center)
		st.add_vertex(p0)
		st.add_vertex(p1)

	# Convertimos SurfaceTool a mesh real
	var mesh_array: ArrayMesh = st.commit()
	return mesh_array
