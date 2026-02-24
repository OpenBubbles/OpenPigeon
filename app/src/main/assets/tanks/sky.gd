extends CanvasLayer
class_name TanksSky

@onready var bg: ColorRect = %Background
@onready var moon: Sprite2D = %Moon
@onready var c1: Sprite2D = %CloudLayer1
@onready var c2: Sprite2D = %CloudLayer2

var wind: float = 0.0

@export var max_alpha: float = 0.75
@export var density: float = 1.0
@export var spread: float = 1.0

# Speed tuning
@export var base_speed_px: float = 1400.0	# faster (px/sec at wind=1)
@export var min_drift_uv: float = 0.015		# baseline UV/sec drift even if wind=0

@export var layer2_speed_mult: float = 1.6
@export var layer2_alpha_mult: float = 0.7

# Optional smoothing to reduce any wind jitter from data updates
@export var wind_smooth: float = 10.0		# higher = snappier, lower = smoother

# Whip motion
@export var whip_strength: float = 0.035
@export var whip_speed: float = 0.35

var _vp_size: Vector2 = Vector2.ZERO
var _wind_smoothed: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

	layer = -10
	_apply_viewport()
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	_ensure_unique_material(c1)
	_ensure_unique_material(c2)

	_push_all_params()

func _on_viewport_size_changed() -> void:
	_apply_viewport()
	_push_all_params()

func set_wind(w: float) -> void:
	wind = w
	# Do not push immediately, we smooth in _process

func _apply_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return

	_vp_size = vp.get_visible_rect().size

	if is_instance_valid(bg):
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_setup_cloud(c1)
	_setup_cloud(c2)

	if is_instance_valid(moon):
		moon.position = Vector2(_vp_size.x * 0.78, _vp_size.y * 0.18)

func _setup_cloud(s: Sprite2D) -> void:
	if not is_instance_valid(s) or s.texture == null:
		return

	s.centered = false
	s.position = Vector2.ZERO
	s.region_enabled = false

	var tw: float = float(s.texture.get_width())
	var th: float = float(s.texture.get_height())
	if tw <= 0.0 or th <= 0.0:
		return

	# Scale sprite to cover viewport, shader uses SCREEN_UV so pattern will not stretch.
	s.scale = Vector2(_vp_size.x / tw, _vp_size.y / th)

func _ensure_unique_material(s: Sprite2D) -> void:
	if not is_instance_valid(s):
		return
	var sm := s.material as ShaderMaterial
	if sm:
		var dup := sm.duplicate(true) as ShaderMaterial
		dup.resource_local_to_scene = true
		s.material = dup

func _process(delta: float) -> void:
	if _vp_size.x <= 1.0:
		return

	# Smooth wind to remove data jitter
	var a: float = clamp(wind_smooth * delta, 0.0, 1.0)
	_wind_smoothed = lerp(_wind_smoothed, wind, a)

	# Convert px/sec to UV/sec
	var uv_per_sec: float = (_wind_smoothed * base_speed_px) / _vp_size.x

	# Always a baseline drift so you can see motion even with 0 wind
	if abs(uv_per_sec) < min_drift_uv:
		uv_per_sec = (sign(_wind_smoothed) * min_drift_uv) if _wind_smoothed != 0.0 else min_drift_uv

	_set_layer_params(c1, uv_per_sec, density, max_alpha, spread, whip_strength, whip_speed, abs(_wind_smoothed))
	_set_layer_params(c2, uv_per_sec * layer2_speed_mult, density * layer2_alpha_mult, max_alpha, spread * 1.25, whip_strength * 1.2, whip_speed, abs(_wind_smoothed))

func _push_all_params() -> void:
	_set_layer_params(c1, 0.0, density, max_alpha, spread, whip_strength, whip_speed, 0.0)
	_set_layer_params(c2, 0.0, density * layer2_alpha_mult, max_alpha, spread * 1.25, whip_strength * 1.2, whip_speed, 0.0)

func _set_layer_params(s: Sprite2D, uv_speed: float, dens: float, fade_max: float, spr: float, whip_s: float, whip_sp: float, wind_abs: float) -> void:
	if not is_instance_valid(s):
		return

	# Sprite modulate alpha is still allowed, but main fade is shader-based.
	s.modulate.a = clamp(fade_max * dens, 0.0, 1.0)

	var m := s.material as ShaderMaterial
	if m:
		m.set_shader_parameter("uv_speed", uv_speed)
		m.set_shader_parameter("density", dens)
		m.set_shader_parameter("fade_max", fade_max)
		m.set_shader_parameter("spread", spr)
		m.set_shader_parameter("whip_strength", whip_s)
		m.set_shader_parameter("whip_speed", whip_sp)
		m.set_shader_parameter("wind_abs", wind_abs)
