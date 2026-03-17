extends Node2D
class_name PowerIndicator

@export var max_length: float = 250.0
@export var base_width: float = 2.0
@export var head_width: float = 14.0
@export var head_length: float = 30.0

@export var visual_scale: float = 20.0 

var current_power: float = 0.5

func set_power(p: float) -> void:
	current_power = clamp(p, 0.0, 1.0)
	queue_redraw()

func get_tip_global_position() -> Vector2:
	var length: float = max_length * current_power
	if length < head_length:
		length = head_length
	
	var local_x: float = length * visual_scale
	return to_global(Vector2(local_x, 0))

func _draw() -> void:
	if current_power <= 0.01:
		return

	var length: float = max_length * current_power
	if length < head_length:
		length = head_length

	var s_len = length * visual_scale
	var s_base = base_width * visual_scale
	var s_h_wid = head_width * visual_scale
	var s_h_len = head_length * visual_scale

	var points := PackedVector2Array([
		Vector2(0, -s_base * 0.5),           # Bottom of base
		Vector2(s_len - s_h_len, -s_base * 0.5), # Base meets head
		Vector2(s_len, 0.0),                # Tip
		Vector2(s_len - s_h_len, s_base * 0.5),  # Base meets head (other side)
		Vector2(0, s_base * 0.5)            # Top of base
	])

	# Define colors for the gradient fade
	var color_start := Color(1, 1, 1, 0) # Transparent at barrel
	var color_mid   := Color(1, 1, 1, 0.7)
	var color_tip   := Color(1, 1, 1, 1) # Solid white at tip

	var colors := PackedColorArray([
		color_start,
		color_mid,
		color_tip,
		color_mid,
		color_start
	])

	draw_polygon(points, colors)
