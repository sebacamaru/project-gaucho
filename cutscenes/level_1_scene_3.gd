extends CutsceneEvent
class_name ThirdRadioCutscene

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
			"type": "say",
			"speaker": "Diego",
			"text": "¡Está como rabioso,[p] todo loco,[p] lo tuve que matar![p] ¡Vienen más!"
		},
		{
			"type": "wait",
			"seconds": 0.45
		},
		{
			"type": "say",
			"speaker": "Luisón",
			"text": "Aguanta chamigo,[p] que en breve estoy con vos ahi."
		},
		{
			"type": "wait",
			"seconds": 0.45
		},
		{
			"type": "say",
			"speaker": "Diego",
			"text": "Estoy rodeado de animales."
		},
		{
			"type": "wait",
			"seconds": 0.35
		},
		{
			"type": "say",
			"speaker": "Luisón",
			"text": "¡Rajá ya!"
		},
		{
			"type": "camera_restore",
			"duration": 0.45
		},
		{
			"type": "start_survivor_level",
			"duration": 666.0
		}
	]
