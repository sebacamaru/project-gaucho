extends CutsceneEvent
class_name IntroCutscene

# =========================================================
# CUTSCENE
# =========================================================

func get_commands() -> Array:
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
			"type": "wait",
			"seconds": 1.00
		},
		{
			"type": "walk_player_to_marker",
			"marker_path": ^"CutsceneTarget1",
			"speed": 2.5
		},
		{
			"type": "wait",
			"seconds": 1.00
		},
		{
			"type": "player_face_direction",
			"direction": "left"
		},
		{
			"type": "wait",
			"seconds": 1.30
		},
		{
			"type": "player_face_direction",
			"direction": "right"
		},
		{
			"type": "wait",
			"seconds": 1.30
		},
		{
			"type": "say",
			"speaker": "Diego",
			"text": "¿Me escucha’?[p] Todo tranquilo por acá...[p] no veo nada raro."
		},
		{
			"type": "wait",
			"seconds": 1.00
		},
		{
			"type": "say",
			"speaker": "Luisón",
			"text": "Te copio.[p] Acá tampoco hay movimiento.[p] Demasiado tranquilo comparado\ncon el pueblo,[p] ¿no?"
		},
		{
			"type": "wait",
			"seconds": 0.50
		},
		{
			"type": "player_face_direction",
			"direction": "left"
		},
		{
			"type": "wait",
			"seconds": 1.50
		},
		{
			"type": "say",
			"speaker": "Diego",
			"text": "Sí...[p] el pueblo está vacío,[p] pero...[p] no sé,[p] se siente raro.[p] No me trates de loco,[p] pero me siento un poco nervioso."
		},
		{
			"type": "wait",
			"seconds": 1.40
		},
		{
			"type": "say",
			"speaker": "Luisón",
			"text": "Es psicológico.[p] La noche,[p] la oscuridad nos hace pensar lo que no es."
		},
		{
			"type": "wait",
			"seconds": 2.00
		},
		{
			"type": "player_face_direction",
			"direction": "right"
		},
		{
			"type": "wait",
			"seconds": 1.00
		},
		{
			"type": "player_face_direction",
			"direction": "left"
		},
		{
			"type": "wait",
			"seconds": 0.50
		},
		{
			"type": "player_face_direction",
			"direction": "right"
		},
		{
			"type": "wait",
			"seconds": 0.50
		},
		{
			"type": "say",
			"speaker": "Diego",
			"text": "¿Escuchaste eso?"
		},
		{
			"type": "wait",
			"seconds": 0.40
		},
		{
			"type": "say",
			"speaker": "Luisón",
			"text": "No.[p] ¿Qué cosa?[p] ¿qué pasa por “ai”?"
		},
		{
			"type": "wait",
			"seconds": 1.30
		},
		{
			"type": "say",
			"speaker": "Diego",
			"text": "Como...[p] como un lamento.[p] Muy bajo.[p] Pensé que era el viento,[p] pero..."
		},
		{
			"type": "wait",
			"seconds": 0.40
		},
		{
			"type": "say",
			"speaker": "Luisón",
			"text": "Debe ser el viento,[p] chamigo."
		},
		{
			"type": "wait",
			"seconds": 1.30
		},
		{
			"type": "say",
			"speaker": "Diego",
			"text": "No...[p] esto era...[p] debo estar pensando mal."
		},
		{
			"type": "camera_restore",
			"duration": 0.45
		}
	]
