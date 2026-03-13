extends Node2D
class_name TanksTerrain

var ground: Polygon2D
var edge: Line2D
var tower_root: Node2D
var tower: Sprite2D

@export var base_y_ratio: float = 0.70
@export var height_px: float = 120.0

@export var transition_width: float = 160.0
@export var transition_segments: int = 28

@export var log_k: float = 22.0
@export var transition_steepness: float = 1.35

@export var edge_enabled: bool = true

@export var tower_y_offset: float = 0.0
@export var tower_edge_pad: float = 0.0
@export var mirror_tower_with_terrain: bool = false

var flipped: bool = false

var _vp_size: Vector2 = Vector2.ZERO
var world_width: float = 1024.0
var world_height: float = 576.0
var base_y: float = 380.0

const BOARD_X_MIN := -187.0
const BOARD_X_MAX := 187.0
const BOARD_X_WIDTH := BOARD_X_MAX - BOARD_X_MIN

@export var tower_width_units: float = 70.0

var _trans_left: float = 0.0
var _trans_right: float = 0.0
var _y_high: float = 0.0
var _y_low: float = 0.0

func _ready() -> void:
	ground = get_node_or_null("Ground") as Polygon2D
	edge = get_node_or_null("Edge") as Line2D
	tower_root = get_node_or_null("TowerRoot") as Node2D
	if is_instance_valid(tower_root):
		tower = tower_root.get_node_or_null("Tower") as Sprite2D

	_apply_viewport()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_rebuild()

func _on_viewport_size_changed() -> void:
	_apply_viewport()
	_rebuild()

func apply_board(height_value_px: float, flip_view: bool) -> void:
	height_px = height_value_px
	_apply_viewport()
	_rebuild()

func _apply_viewport() -> void:
	var vr := get_viewport().get_visible_rect()
	_vp_size = vr.size
	world_width = _vp_size.x
	world_height = _vp_size.y
	position = Vector2.ZERO
	base_y = world_height * base_y_ratio

func _rebuild() -> void:
	if not is_instance_valid(ground):
		return

	var y_low: float = base_y
	var y_high: float = base_y - height_px

	var left_x: float = 0.0
	var right_x: float = world_width

	var tower_center_x: float = world_width * 0.5

	_apply_tower_scale()

	var tower_half_w: float = 60.0
	if is_instance_valid(tower) and tower.texture != null:
		tower_half_w = (float(tower.texture.get_width()) * abs(tower.scale.x)) * 0.5

	var tower_left_edge_x: float = tower_center_x - tower_half_w - tower_edge_pad

	var trans_right: float = tower_left_edge_x
	var trans_left: float = trans_right - transition_width

	var min_x: float = 2.0
	var max_x: float = world_width - 2.0
	trans_right = clamp(trans_right, min_x + transition_width, max_x)
	trans_left = trans_right - transition_width

	_trans_left = trans_left
	_trans_right = trans_right
	_y_high = y_high
	_y_low = y_low

	var top: PackedVector2Array = PackedVector2Array()
	top.append(Vector2(left_x, y_low))
	top.append(Vector2(trans_left, y_low))

	var k: float = max(log_k, 0.001)
	var denom: float = log(1.0 + k)

	for i in range(transition_segments + 1):
		var t: float = float(i) / float(transition_segments)
		var x: float = lerp(trans_left, trans_right, t)

		var tr: float = 1.0 - t
		var u: float = log(1.0 + k * tr) / denom
		u = 1.0 - u

		if transition_steepness != 1.0:
			u = pow(u, transition_steepness)

		var f: float = u * u * (3.0 - 2.0 * u)
		var y: float = lerp(y_low, y_high, f)
		top.append(Vector2(x, y))

	top.append(Vector2(right_x, y_high))

	var poly: PackedVector2Array = PackedVector2Array()
	for p in top:
		poly.append(p)
	poly.append(Vector2(right_x, world_height))
	poly.append(Vector2(left_x, world_height))

	ground.polygon = poly

	if is_instance_valid(edge):
		edge.visible = edge_enabled
		if edge_enabled:
			edge.points = top

	_place_tower_centered(tower_center_x, y_high)
	print("Tower target width px: ", get_tower_target_width_px(), " | actual: ", get_tower_width_px(), " | pixels/unit: ", get_pixels_per_board_unit())

func _place_tower_centered(tower_center_x: float, y_high: float) -> void:
	if not is_instance_valid(tower_root) or not is_instance_valid(tower):
		return

	var tx: float = tower_center_x
	if flipped and mirror_tower_with_terrain:
		tx = world_width - tx

	tower_root.position = Vector2(tx, y_high + tower_y_offset)

	if tower.texture != null:
		var w: float = float(tower.texture.get_width()) * tower.scale.x
		var h: float = float(tower.texture.get_height()) * tower.scale.y
		tower.position = Vector2(-w * 0.5, -h)
	else:
		tower.position = Vector2.ZERO

func get_world_width() -> float:
	return world_width

func get_surface_y_at_screen_x(x: float) -> float:
	# SCREEN X in the currently-built terrain (after any mirroring already applied)
	return _surface_y_at_x(x)

func _surface_y_at_x(x: float) -> float:
	if x <= _trans_left:
		return _y_low
	if x >= _trans_right:
		return _y_high

	var t: float = (x - _trans_left) / max(_trans_right - _trans_left, 0.001)
	t = clamp(t, 0.0, 1.0)

	var k: float = max(log_k, 0.001)
	var denom: float = log(1.0 + k)

	var tr: float = 1.0 - t
	var u: float = log(1.0 + k * tr) / denom
	u = 1.0 - u

	if transition_steepness != 1.0:
		u = pow(u, transition_steepness)

	var f: float = u * u * (3.0 - 2.0 * u)
	return lerp(_y_low, _y_high, f)

func _mirror_pts(pts: PackedVector2Array, w: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(w - p.x, p.y))
	return out

func get_pixels_per_board_unit() -> float:
	return world_width / BOARD_X_WIDTH

func get_tower_target_width_px() -> float:
	return tower_width_units * get_pixels_per_board_unit()

func _apply_tower_scale() -> void:
	if not is_instance_valid(tower) or tower.texture == null:
		return
	
	var tex_w: float = float(tower.texture.get_width())
	if tex_w <= 0.0:
		return
	
	var sign_x: float = -1.0 if tower.scale.x < 0.0 else 1.0
	var sign_y: float = -1.0 if tower.scale.y < 0.0 else 1.0
	var uniform_scale: float = get_tower_target_width_px() / tex_w
	
	tower.scale = Vector2(sign_x * uniform_scale, sign_y * uniform_scale)

func get_tower_width_px() -> float:
	if not is_instance_valid(tower) or tower.texture == null:
		return 0.0
	
	return float(tower.texture.get_width()) * abs(tower.scale.x)
