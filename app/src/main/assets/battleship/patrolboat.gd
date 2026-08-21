extends Sprite2D

class_name Patrolboat

const LOG_TAG := "Patrolboat"
const DEBUG_PATROLBOAT := false

func dbg(parts: Variant) -> void:
	if DEBUG_PATROLBOAT:
		OpLog.d(LOG_TAG, parts)

@export var textures: Array[Texture2D]
var this_battleground: BattleGround = null
var my_len: int = 0
var is_horizontal = false
var rot: int = 0
var current_grid_pos = Vector2(-1, -1)
var parts_destroyed: Array[bool] = []
var canBeMoved = false
var _base_modulate: Color = Color.WHITE
var _base_modulate_captured: bool = false

func set_conflict(active: bool) -> void:
	if not _base_modulate_captured:
		_base_modulate = modulate
		_base_modulate_captured = true

	modulate = (_base_modulate * Color(1.0, 0.45, 0.45)) if active else _base_modulate

func _rot_angle() -> float:
	match rot:
		0:
			return -PI / 2
		2:
			return PI / 2
		3:
			return PI
	return 0.0

func decode_ship(encodedShip: String, battleground: BattleGround):
	this_battleground = battleground
	var start = Vector2(0, 0)
	var raw_num_string = ""
	rot = 0

	for attribute in encodedShip.split('&'):
		var name = attribute.split(':', true, 1)
		if name[0] == "pos":
			var coords = name[1].split(",")
			start = Vector2(int(coords[0]), int(coords[1]))
		if name[0] == "rot":
			rot = posmod(int(name[1]), 4)
		if name[0] == "num":
			raw_num_string = name[1]

	var parts_array: Array = []
	if raw_num_string != "":
		parts_array = Array(raw_num_string.split(","))

	var length = parts_array.size()
	is_horizontal = rot == 1 or rot == 3

	if rot == 0 or rot == 3:
		parts_array.reverse()

	if length > 0:
		parts_destroyed.assign(parts_array.map(func(n): return n == '1'))

	set_len(length)
	start.y = (battleground.rows - 1) - start.y

	if rot == 0:
		start.y -= (length - 1)
	elif rot == 3:
		start.x -= (length - 1)

	set_grid_position(start, is_horizontal)

	for i in range(length):
		if not parts_destroyed[i]:
			continue
		this_battleground.mark(index_to_grid(i), BattlegroundMarker.MarkerMode.ELIMINATED)

func fits_board(pos: Vector2, horizontal: bool) -> bool:
	for i in range(my_len):
		var this_pos := pos + (Vector2(i, 0) if horizontal else Vector2(0, i))

		if this_pos.x < 0 or this_pos.x >= this_battleground.columns:
			return false

		if this_pos.y < 0 or this_pos.y >= this_battleground.rows:
			return false

	return true

func is_sunk() -> bool:
	return parts_destroyed.all(func(p): return p)

func outline():
	for i in range(my_len):
		var thisPos = index_to_grid(i)
		for neighbor in this_battleground.get_grid_neighbours(thisPos.x, thisPos.y):
			this_battleground.fire(neighbor)

func index_to_grid(i: int) -> Vector2:
	var thisPos = current_grid_pos
	if is_horizontal:
		thisPos += Vector2(i, 0)
	else:
		thisPos += Vector2(0, i)
	return thisPos

func set_grid_position(pos: Vector2, horizontal: bool) -> bool:
	if not fits_board(pos, horizontal):
		return false

	is_horizontal = horizontal
	current_grid_pos = pos
	rotation = _rot_angle()

	var half_len = my_len / float(2)
	position = this_battleground.grid_to_coord(pos + (Vector2(half_len, 0.5) if is_horizontal else Vector2(0.5, half_len)))

	this_battleground.update_grid_states()
	return true

func encode_state() -> String:
	var anchor: Vector2 = current_grid_pos
	var parts: Array = parts_destroyed.duplicate()

	if rot == 0:
		anchor.y += my_len - 1
	elif rot == 3:
		anchor.x += my_len - 1

	if rot == 0 or rot == 3:
		parts.reverse()

	return "pos:%d,%d&num:%s&rot:%d" % [
		int(anchor.x),
		int(anchor.y),
		",".join(PackedStringArray(parts.map(func(n): return '1' if n else '0'))),
		rot
	]

var is_dragging = false
var start_offset = Vector2(0, 0)
var down_frame = 0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if not event.pressed and event.button_index == 1 and is_dragging:
			is_dragging = false
			var delta = Time.get_ticks_msec() - down_frame
			if delta < 200:
				set_grid_rotation(rot + 1)
			dbg(["drag_end pos=", current_grid_pos, " horizontal=", is_horizontal])
	elif event is InputEventMouseMotion and is_dragging:
		var pos = this_battleground.to_local(event.position)
		set_grid_position(this_battleground.coord_to_grid(pos) - start_offset, is_horizontal)

func set_grid_rotation(new_rot: int) -> void:
	new_rot = posmod(new_rot, 4)

	var horizontal := new_rot == 1 or new_rot == 3
	var top_left: Vector2 = current_grid_pos

	if horizontal != is_horizontal:
		var shift: float = floor(my_len / 2.0)
		top_left += Vector2(-shift, shift) if horizontal else Vector2(shift, -shift)

	var previous_rot := rot
	rot = new_rot

	if not set_grid_position(top_left, horizontal):
		rot = previous_rot

func set_len(len: int):
	texture = textures[len-1]
	my_len = len
	var collision = get_node("Area2D/CollisionShape2D") as CollisionShape2D
	var shape = (collision.shape as RectangleShape2D).duplicate()
	shape.size = texture.get_size() * scale
	collision.shape = shape


func _on_area_2d_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and canBeMoved:
		if event.pressed and event.button_index == 1:
			is_dragging = true
			var pos = this_battleground.to_local(event.position)
			start_offset = this_battleground.coord_to_grid(pos) - current_grid_pos
			down_frame = Time.get_ticks_msec()
			dbg(["drag_start pos=", current_grid_pos, " horizontal=", is_horizontal])
