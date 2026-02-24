extends Control
class_name WindIndicator

@onready var arrow_sprite: TextureRect = $ClipRect/ArrowSprite
@onready var clip_rect: Control = $ClipRect

# Half of the total width (200 / 2)
const CENTER_X: float = 100.0

func set_wind(wind_value: float) -> void:
	if not is_instance_valid(clip_rect) or not is_instance_valid(arrow_sprite):
		return
		
	var abs_wind = abs(wind_value)
	var raw_fill = abs_wind * CENTER_X # Value between 0.0 and 100.0
	
	# --- ROUND TO NEAREST 10 ---
	# Dividing by 10, rounding, then multiplying by 10 
	# turns 41.3 -> 40, and 46.8 -> 50.
	var fill_width: int = int(round(raw_fill / 10.0) * 10.0)
	
	if wind_value >= 0:
		# RIGHT
		clip_rect.position.x = CENTER_X
		clip_rect.size.x = fill_width
		
		# Keep arrow texture pinned to the absolute center of the bar
		arrow_sprite.position.x = -CENTER_X
		arrow_sprite.flip_h = false
	else:
		# LEFT
		clip_rect.position.x = CENTER_X - fill_width
		clip_rect.size.x = fill_width
		
		# Keep arrow texture pinned so center of texture meets center of bar
		arrow_sprite.position.x = -(CENTER_X - fill_width)
		arrow_sprite.flip_h = true
