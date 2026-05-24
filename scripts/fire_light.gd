extends OmniLight3D

@export var flicker_min: float = 1.3
@export var flicker_max: float = 2.2
@export var noise_speed: float = 1.8
@export var color_warm: Color = Color(1.0, 0.55, 0.15)
@export var color_cool: Color = Color(1.0, 0.42, 0.10)

var _noise: FastNoiseLite
var _noise_offset: float

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 0.35
	_noise.fractal_octaves = 2
	_noise_offset = randf_range(0.0, 100.0)  # instancias independientes

func _process(_delta: float) -> void:
	var t: float = (Time.get_ticks_msec() / 1000.0) * noise_speed + _noise_offset
	var n: float = _noise.get_noise_1d(t) * 0.5 + 0.5  # remap 0..1
	light_energy = lerpf(flicker_min, flicker_max, n)
	light_color = color_warm.lerp(color_cool, n * 0.25)
