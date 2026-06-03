extends Node3D
class_name ActionButton3D

signal clicked(button: ActionButton3D)

enum ButtonKind { SHOOT, MOVE }
enum Lane { LEFT, CENTER, RIGHT }

@export var kind: ButtonKind = ButtonKind.SHOOT
@export var lane: Lane = Lane.CENTER
@export var move_tex_1x: Texture2D
@export var move_tex_2x: Texture2D
@export var press_scale: float = 0.92
@export var hover_scale: float = 1.08
@export var shoot_pulse_amount: float = 0.10
@export var shoot_pulse_speed: float = 3.0
@export var shoot_rot_deg_per_sec: float = 90.0
@export var move_bounce_amount: float = 0.35
@export var move_bounce_speed: float = 3.2

@onready var _sprite: Sprite3D = $Sprite3D
@onready var _area: Area3D = $Area3D

var _base_pos: Vector3
var _base_scale: Vector3
var _t: float = 0.0
var _pressed: bool = false
var _hovered: bool = false
var _tw: Tween
var _player_lane: Lane = Lane.CENTER
var _click_enabled: bool = true

const MOVE_RULES := {
	Lane.LEFT: {
		Lane.LEFT:	{ "hide": true,  "flip": false, "dist": 0 },
		Lane.CENTER:{ "hide": false, "flip": true,  "dist": 1 },
		Lane.RIGHT:	{ "hide": false, "flip": true,  "dist": 2 },
	},
	Lane.CENTER: {
		Lane.LEFT:	{ "hide": false, "flip": false, "dist": 1 },
		Lane.CENTER:{ "hide": true,  "flip": false, "dist": 0 },
		Lane.RIGHT:	{ "hide": false, "flip": true,  "dist": 1 },
	},
	Lane.RIGHT: {
		Lane.LEFT:	{ "hide": false, "flip": false, "dist": 2 },
		Lane.CENTER:{ "hide": false, "flip": false, "dist": 1 }, 
		Lane.RIGHT:	{ "hide": true,  "flip": false, "dist": 0 },
	},
}

func _ready() -> void:
	_base_pos = _sprite.position
	_base_scale = _sprite.scale
	_base_scale.x = abs(_base_scale.x)
	_sprite.scale.x = abs(_sprite.scale.x)

	_area.input_ray_pickable = true
	_area.mouse_entered.connect(_on_mouse_entered)
	_area.mouse_exited.connect(_on_mouse_exited)
	_area.input_event.connect(_on_area_input_event)

	if kind == ButtonKind.SHOOT:
		_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED

	_apply_move_visuals()

func set_player_lane(v: Lane) -> void:
	_player_lane = v
	_apply_move_visuals()

func _process(delta: float) -> void:
	if not visible:
		return

	_t += delta

	if kind == ButtonKind.SHOOT:
		_update_shoot_anim(delta)
	else:
		_update_move_anim(delta)

func _update_shoot_anim(delta: float) -> void:
	var rot = deg_to_rad(shoot_rot_deg_per_sec) * delta
	_sprite.rotation.z += rot

	if _pressed:
		return

	var pulse = 1.0 + sin(_t * shoot_pulse_speed) * shoot_pulse_amount
	_sprite.scale = _base_scale * pulse
	
func set_click_enabled(v: bool) -> void:
	_click_enabled = v
	if is_instance_valid(_area):
		_area.input_ray_pickable = v

	if not v:
		_hovered = false
		_pressed = false
		_sprite.scale = _base_scale

func _update_move_anim(_delta: float) -> void:
	var y = sin(_t * move_bounce_speed) * move_bounce_amount
	_sprite.position = _base_pos + Vector3(0.0, y, 0.0)

func _apply_move_visuals() -> void:
	if kind != ButtonKind.MOVE:
		return

	var rules_for_lane = MOVE_RULES.get(_player_lane, null)
	if rules_for_lane == null:
		return

	var r = rules_for_lane.get(lane, null)
	if r == null:
		return

	visible = not bool(r.get("hide", false))
	if not visible:
		return

	var dist: int = int(r.get("dist", 0))
	var flip: bool = r.get("flip", false) == true

	if _player_lane == Lane.LEFT and lane == Lane.CENTER:
		flip = true

	_sprite.flip_h = flip

	var s := _sprite.scale
	s.x = abs(s.x)
	_sprite.scale = s

	if dist <= 1:
		if move_tex_1x != null:
			_sprite.texture = move_tex_1x
	else:
		if move_tex_2x != null:
			_sprite.texture = move_tex_2x

func _on_mouse_entered() -> void:
	_hovered = true
	if _pressed:
		return
	_tween_scale(_base_scale * hover_scale, 0.08)

func _on_mouse_exited() -> void:
	_hovered = false
	if _pressed:
		return
	_tween_scale(_base_scale, 0.08)

func _on_area_input_event(_camera: Camera3D, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if not _click_enabled:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_press()
		else:
			_release(true)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press()
		else:
			_release(true)

func _press() -> void:
	if _pressed:
		return
	_pressed = true
	_tween_scale(_base_scale * press_scale, 0.06)

func _release(emit_click: bool) -> void:
	if not _pressed:
		return

	_pressed = false

	if _hovered:
		_tween_scale(_base_scale * hover_scale, 0.08)
	else:
		_tween_scale(_base_scale, 0.08)

	if emit_click:
		call_deferred("emit_signal", "clicked", self)

func _tween_scale(target: Vector3, time: float) -> void:
	if not is_instance_valid(_sprite):
		return

	target.x = abs(target.x)

	if _tw and _tw.is_valid():
		_tw.kill()

	if time <= 0.0:
		_sprite.scale = target
		return

	_tw = create_tween()
	_tw.tween_property(_sprite, "scale", target, time)
