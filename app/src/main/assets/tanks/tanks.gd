extends Node2D
class_name Tank

@onready var body: Sprite2D = %Body
@onready var barrel_pivot: Node2D = %BarrelPivot
@onready var barrel_sprite: Sprite2D = %Barrel
@onready var barrel_tip: Node2D = %BarrelTip
@onready var power_indicator: PowerIndicator = %PowerIndicator

@export var player_color: Color = Color(0.2, 0.55, 0.81, 1.0)

# Display-space clamp: 0 (right) .. 180 (left), upper arc
@export var min_display_deg: float = 0.0
@export var max_display_deg: float = 180.0

@export var art_zero_offset_deg: float = 0.0

var _display_deg: float = 0.0

func _ready() -> void:
	set_player_color(player_color)
	set_barrel_display_deg(0.0)

func set_player_color(c: Color) -> void:
	player_color = c
	if is_instance_valid(body):
		body.modulate = c
	if is_instance_valid(barrel_sprite):
		barrel_sprite.modulate = c

func set_power_visibility(is_visible: bool) -> void:
	if is_instance_valid(power_indicator):
		power_indicator.visible = is_visible
		
func set_power(power_val: float) -> void:
	if is_instance_valid(power_indicator):
		power_indicator.set_power(power_val)

func set_barrel_display_deg(display_deg: float) -> void:
	_display_deg = clamp(display_deg, min_display_deg, max_display_deg)

	barrel_pivot.rotation_degrees = (-_display_deg) + art_zero_offset_deg

func get_barrel_display_deg() -> float:
	return _display_deg
	
func get_indicator_tip_global() -> Vector2:
	var pi = power_indicator as PowerIndicator
	
	if is_instance_valid(pi) and pi.current_power > 0.01:
		return pi.get_tip_global_position()
		
	if is_instance_valid(barrel_tip):
		return barrel_tip.global_position
	return barrel_pivot.global_position

func get_barrel_tip_global() -> Vector2:
	if is_instance_valid(barrel_tip):
		return barrel_tip.global_position
	return barrel_pivot.global_position

func get_bottom_offset_px() -> float:
	if not is_instance_valid(body) or body.texture == null:
		return 0.0

	var tex_h: float = float(body.texture.get_height())
	var eff_scale_y: float = scale.y * body.scale.y
	var h: float = tex_h * eff_scale_y

	if body.centered:
		return h * 0.5
	return h
