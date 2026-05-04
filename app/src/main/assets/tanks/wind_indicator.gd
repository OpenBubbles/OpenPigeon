extends Control
class_name WindIndicator

@onready var arrow_sprite: TextureRect = $ClipRect/ArrowSprite
@onready var clip_rect: Control = $ClipRect

const IOS_WIND_VISUAL_SCALE := 0.892857

const CENTER_X: float = 100.0

func set_wind(wind_value: float) -> void:
	if not is_instance_valid(clip_rect) or not is_instance_valid(arrow_sprite):
		return
		
	var abs_wind: float = abs(wind_value)
	var raw_fill: float = abs_wind * CENTER_X * IOS_WIND_VISUAL_SCALE
	var fill_width: float = clampf(raw_fill, 0.0, CENTER_X)
	
	if wind_value >= 0:
		clip_rect.position.x = CENTER_X
		clip_rect.size.x = fill_width
		
		arrow_sprite.position.x = -CENTER_X
		arrow_sprite.flip_h = false
	else:
		clip_rect.position.x = CENTER_X - fill_width
		clip_rect.size.x = fill_width
		
		arrow_sprite.position.x = -(CENTER_X - fill_width)
		arrow_sprite.flip_h = true
