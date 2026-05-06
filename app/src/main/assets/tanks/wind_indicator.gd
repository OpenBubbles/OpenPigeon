extends Control
class_name WindIndicator

@onready var arrow_sprite: TextureRect = %ArrowSprite
@onready var wind_background: TextureRect = %WindBG
@onready var clip_rect: Control = %ClipRect

func _ready() -> void:
	resized.connect(func(): set_wind(_last_wind))
	if is_instance_valid(wind_background):
		wind_background.resized.connect(func(): set_wind(_last_wind))

var _last_wind: float = 0.0

func set_wind(wind_value: float) -> void:
	_last_wind = wind_value
	if not (is_instance_valid(clip_rect) and is_instance_valid(arrow_sprite) and is_instance_valid(wind_background)):
		return

	var bg_left: float = wind_background.position.x
	var bg_top: float = wind_background.position.y
	var bg_w: float = wind_background.size.x
	var bg_h: float = wind_background.size.y
	var bg_center_x: float = bg_left + bg_w * 0.5
	var bg_center_y: float = bg_top + bg_h * 0.5

	var half_w: float = bg_w * 0.5

	var w: float = clampf(wind_value, -1.0, 1.0)
	var fill_width: float = clampf(absf(w) * half_w, 0.0, half_w)

	clip_rect.size = Vector2(fill_width, bg_h)
	clip_rect.position.y = bg_center_y - bg_h * 0.5
	if w >= 0.0:
		clip_rect.position.x = bg_center_x
	else:
		clip_rect.position.x = bg_center_x - fill_width

	arrow_sprite.size = Vector2(bg_w, bg_h)
	arrow_sprite.position.x = bg_center_x - clip_rect.position.x - half_w
	arrow_sprite.position.y = 0.0
	arrow_sprite.flip_h = false
