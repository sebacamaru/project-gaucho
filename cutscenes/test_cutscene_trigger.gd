extends CutsceneEvent
class_name DashTutorialCutscene

# =========================================================
# DASH TUTORIAL CUTSCENE
# =========================================================
#
# Cutscene concreta.
#
# Este script ya no tiene helpers, no busca director,
# no valida métodos, no maneja skip, no restaura HUD.
#
# Solo define comandos.
# =========================================================

func get_commands() -> Array:
	return [
		{
			"type": "player_face_direction",
			"direction": "right"
		},
		{
			"type": "camera_zoom",
			"value": 28.0,
			"duration": 0.45
		},
		{
			"type": "say",
			"speaker": "Rick",
			"text": "Permite hacer un dash para escapar de los enemigos rápidamente."
		},
		{
			"type": "walk_player_to_marker",
			"marker_path": ^"CutsceneTarget",
			"speed": 2.5
		},
		{
			"type": "wait",
			"seconds": 0.35
		},
		{
			"type": "player_face_direction",
			"direction": "left"
		},
		{
			"type": "wait",
			"seconds": 0.35
		},
		{
			"type": "player_face_direction",
			"direction": "right"
		},
		{
			"type": "camera_restore",
			"duration": 0.45
		}
	]
