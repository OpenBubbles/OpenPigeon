extends Control
class_name WindArrow

# Visual Settings
const MIN_LENGTH_PCT: float = 0.3 # Minimum length at 0 wind strength
const MAX_LENGTH_PCT: float = 0.9 # Maximum length (relative to container size)
const SHAFT_WIDTH_START: float = 6.0
const SHAFT_WIDTH_END: float = 3.0
const HEAD_WIDTH: float = 14.0
const HEAD_LENGTH: float = 18.0

# State variables
var angle_deg: float = 0.0
var strength_t: float = 0.0
var arrow_color: Color = Color.WHITE

# Animation state
var pulse_scale: float = 1.0 # Modifies the length dynamically
var pulse_tween: Tween = null

func _ready() -> void:
	# Ensure we start with a default visual state
	queue_redraw()

func set_arrow(angle_degrees: float, t: float, color: Color) -> void:
	# Store the angle exactly as passed in
	angle_deg = -angle_degrees - 90
	strength_t = clamp(t, 0.0, 1.0)
	arrow_color = color
	
	_start_breathing_animation()
	queue_redraw()

func _start_breathing_animation() -> void:
	# Kill existing tween to restart the rhythm
	if pulse_tween and pulse_tween.is_running():
		pulse_tween.kill()
	
	pulse_tween = create_tween()
	pulse_tween.set_loops() # Infinite loop
	
	pulse_tween.tween_method(_set_pulse_scale, 1.0, 2.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pulse_tween.tween_method(_set_pulse_scale, 2.0, 0.75, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _set_pulse_scale(val: float) -> void:
	pulse_scale = val
	queue_redraw()

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return

	var center: Vector2 = size * 0.5
	var max_radius: float = min(size.x, size.y) * 0.5

	# Our input convention:
	#   0°   = bottom
	#   90°  = left
	#   180° = top
	#   270° = right
	# The base arrow points RIGHT, so rotate by (angle_deg + 90)
	var angle_rad: float = deg_to_rad(angle_deg + 90.0)

	# --- Calculate Lengths ---
	var target_len_pct: float = lerp(MIN_LENGTH_PCT, MAX_LENGTH_PCT, strength_t)
	var current_len_px: float = (max_radius * target_len_pct) * pulse_scale
	current_len_px = min(current_len_px, max_radius - 2.0)

	var actual_head_len = min(HEAD_LENGTH, current_len_px * 0.4)
	var shaft_len = current_len_px - actual_head_len

	var tail_w = SHAFT_WIDTH_START * (0.5 + 0.5 * strength_t)
	var neck_w = SHAFT_WIDTH_END * (0.5 + 0.5 * strength_t)
	var head_w = HEAD_WIDTH * (0.8 + 0.2 * strength_t)

	var p_tail_top		= Vector2(0, -tail_w / 2.0)
	var p_neck_top		= Vector2(shaft_len, -neck_w / 2.0)
	var p_head_left		= Vector2(shaft_len, -head_w / 2.0)
	var p_tip			= Vector2(current_len_px, 0)
	var p_head_right	= Vector2(shaft_len, head_w / 2.0)
	var p_neck_bot		= Vector2(shaft_len, neck_w / 2.0)
	var p_tail_bot		= Vector2(0, tail_w / 2.0)

	var points = PackedVector2Array([
		p_tail_top,
		p_neck_top,
		p_head_left,
		p_tip,
		p_head_right,
		p_neck_bot,
		p_tail_bot
	])

	var rotated_points = PackedVector2Array()
	for p in points:
		var rotated_p = p.rotated(angle_rad)
		rotated_points.append(center + rotated_p)

	draw_colored_polygon(rotated_points, arrow_color)
	draw_polyline(rotated_points, arrow_color.darkened(0.3), 1.0, true)
