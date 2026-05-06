extends Control
class_name WindIndicator

@onready var arrow_sprite: TextureRect = %ArrowSprite
@onready var wind_background: TextureRect = %WindBG
@onready var clip_rect: Control = %ClipRect

const IOS_WIND_VISUAL_SCALE := 0.892857

const CENTER_X: float = 100.0

func set_wind(wind_value: float) -> void:
	if not is_instance_valid(clip_rect) or not is_instance_valid(arrow_sprite) or not is_instance_valid(wind_background):
		return

	var bg_center_x: float = wind_background.position.x + wind_background.size.x * 0.5
	var bg_center_y: float = wind_background.position.y + wind_background.size.y * 0.5

	var abs_wind: float = abs(wind_value)
	var fill_width: float = clampf(abs_wind * CENTER_X * IOS_WIND_VISUAL_SCALE, 0.0, CENTER_X)

	clip_rect.size.x = fill_width
	clip_rect.size.y = wind_background.size.y
	clip_rect.position.y = bg_center_y - clip_rect.size.y * 0.5

	if wind_value >= 0:
		clip_rect.position.x = bg_center_x
		arrow_sprite.flip_h = false
		arrow_sprite.position.x = -fill_width
	else:
		clip_rect.position.x = bg_center_x - fill_width
		arrow_sprite.flip_h = true
		arrow_sprite.position.x = 0.0

	arrow_sprite.position.y = clip_rect.size.y * 0.5 - arrow_sprite.size.y * 0.5
