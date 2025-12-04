extends Node2D

class_name BattleGround

@export var columns: int = 8
@export var rows: int = 6
@export var rect_size: Vector2 = Vector2(512, 384)
@export var grid_color: Color = Color(1, 1, 1, 0.2)

signal is_valid(valid: bool)
var has_conflict = false
var placing_items = false
var can_attack = false

func set_grid_tint(color: Color) -> void:
	grid_color = color
	queue_redraw()

func set_attack():
	can_attack = true
	for ship in ships:
		ship.visible = ship.is_sunk()
	
var ship_grid: Array[Patrolboat] = []
var grid_state: Array[GridState] = []
var ships: Array[Patrolboat] = []
var bullets: Array[bool] = []
var ship_part: Array[int] = []


enum GridState {
	NONE,
	CONFLICT,
}

func clear_battleground():
	for child in get_children():
		remove_child(child)
	if target != null:
		target.visible = false
		add_child(target)
	ship_grid.clear()
	grid_state.clear()
	ship_part.clear()
	bullets.clear()
	ships.clear()
	for c in range(columns):
		for r in range(rows):
			ship_grid.append(null)
			grid_state.append(GridState.NONE)
			bullets.append(false)
			ship_part.append(0)
	
	targeting_grid = Vector2(-1, -1)
	if target != null:
		target.visible = false

func _ready() -> void:
	clear_battleground()

func is_empty() -> bool:
	return get_children().is_empty()
	
func encode_ships() -> String:
	return "|".join(ships.map(func(ship): return ship.encode_state()))
	
func encode_bullets() -> String:
	return ",".join(bullets.map(func(bullet): return '1' if bullet else '0'))

func from_bullets(b: String):
	bullets.assign(Array(b.split(",")).map(func(bullet): return bullet == '1'))
	for x in range(columns):
		for y in range(rows):
			var fire_index = y * columns + x
			if not bullets[fire_index]:
				continue
			mark(Vector2(x, y), BattlegroundMarker.MarkerMode.MISSED)

@export var ship_class: PackedScene
@export var marker: PackedScene
func from_encoded(encoded: String):
	clear_battleground()
	if encoded.is_empty():
		print("[FROM_ENCODED] Empty encoded string, nothing to place")
		return
	
	print("[FROM_ENCODED] Applying encoded layout: ", encoded)
	for encodedShip in encoded.split('|'):
		if encodedShip.is_empty():
			continue
		print("[FROM_ENCODED]  -> ship: ", encodedShip)
		var ship = ship_class.instantiate() as Patrolboat
		add_child(ship)
		ship.decode_ship(encodedShip, self)
		ships.append(ship)

func grid_to_coord(gridpos: Vector2) -> Vector2:
	var cell_width: float = rect_size.x / columns
	var cell_height: float = rect_size.y / rows
	return Vector2(gridpos.x * cell_width, gridpos.y * cell_height)


func coord_to_grid(coord: Vector2) -> Vector2:
	var cell_width: float = rect_size.x / columns
	var cell_height: float = rect_size.y / rows
	var i: Vector2 = coord / Vector2(cell_width, cell_height)
	return i.floor()

func _draw():
	if columns <= 0 or rows <= 0:
		return

	var cell_width = rect_size.x / columns
	var cell_height = rect_size.y / rows

	for x in range(columns + 1):
		var xpos = x * cell_width
		draw_line(Vector2(xpos, 0), Vector2(xpos, rect_size.y), grid_color, 2.0)

	for y in range(rows + 1):
		var ypos = y * cell_height
		draw_line(Vector2(0, ypos), Vector2(rect_size.x, ypos), grid_color, 2.0)

	draw_rect(Rect2(Vector2.ZERO, rect_size), grid_color, false)
	
	for x in range(columns):
		for y in range(rows):
			var state = grid_state[y * columns + x]
			if state == GridState.CONFLICT:
				draw_rect(Rect2(grid_to_coord(Vector2(x, y)), Vector2(cell_width, cell_height)), Color.RED)

func get_grid_neighbours(x: int, y: int) -> Array[Vector2]:
	var neighbours: Array[Vector2] = []
	if y > 0:
		neighbours.append(Vector2(x, y - 1))
		if x > 0:
			neighbours.append(Vector2(x - 1, y - 1))
		if x != columns - 1:
			neighbours.append(Vector2(x + 1, y - 1))
	if x > 0:
		neighbours.append(Vector2(x - 1, y))
	if x != columns - 1:
		neighbours.append(Vector2(x + 1, y))
	if y != rows - 1:
		neighbours.append(Vector2(x, y + 1))
		if x > 0:
			neighbours.append(Vector2(x - 1, y + 1))
		if x != columns - 1:
			neighbours.append(Vector2(x + 1, y + 1))
	return neighbours

func get_state_for_grid(x: int, y: int) -> GridState:
	var boat = ship_grid[y * columns + x]
	if boat == null:
		return GridState.NONE
	var neighbours: Array[Vector2] = get_grid_neighbours(x, y)
	
	for neighbour in neighbours:
		var other = ship_grid[neighbour.y * columns + neighbour.x]
		if other != boat and other != null:
			return GridState.CONFLICT
	return GridState.NONE

func update_grid_states():
	var changed = false
	var conflict = false
	for x in range(columns):
		for y in range(rows):
			var state = get_state_for_grid(x, y)
			var actualState = grid_state[y * columns + x]
			if actualState != state:
				grid_state[y * columns + x] = state
				changed = true
			if state == GridState.CONFLICT:
				conflict = true
	has_conflict = conflict
	is_valid.emit(not has_conflict)
	if changed:
		queue_redraw()

func set_size(size: int):
	rows = size
	columns = size
	queue_redraw()

var target: BattlegroundMarker = null
var targeting_grid: Vector2 = Vector2(-1, -1)
var _target_tween: Tween
var _rotation_tween: Tween

func fire(at: Vector2) -> bool:
	var fire_index = at.y * columns + at.x
	var hit = ship_grid[fire_index]
	if hit != null:
		if hit.parts_destroyed[ship_part[fire_index]]:
			return true
		hit.parts_destroyed[ship_part[fire_index]] = true
		if hit.is_sunk():
			hit.visible = true
			hit.outline()
	else:
		if bullets[fire_index]:
			return true
		bullets[fire_index] = true
	if target != null:
		target.visible = false
	var marker = BattlegroundMarker.MarkerMode.ELIMINATED if hit != null else BattlegroundMarker.MarkerMode.MISSED
	mark(at, marker)
	return hit != null

func is_over() -> bool:
	return not ships.is_empty() and ships.all(func(ship): return ship.is_sunk())

func mark(coord: Vector2, mark: BattlegroundMarker.MarkerMode):
	var marker = marker.instantiate()
	marker.set_mode(mark)
	marker.position = grid_to_coord(coord + Vector2(0.5, 0.5))
	add_child(marker)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not placing_items and can_attack:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos: Vector2 = to_local(event.position)
			
			var grid: Vector2 = coord_to_grid(local_pos)
			
			if grid.x < 0 or grid.y < 0 or grid.x >= columns or grid.y >= rows:
				return
			
			var idx: int = int(grid.y) * columns + int(grid.x)
			
			if bullets[idx] or (ship_grid[idx] != null and ship_grid[idx].parts_destroyed[ship_part[idx]]):
				return
			
			if target == null:
				target = marker.instantiate()
				target.set_mode(BattlegroundMarker.MarkerMode.TARGET)
				add_child(target)
			
			target.visible = true
			targeting_grid = grid
			target.position = grid_to_coord(grid + Vector2(0.5, 0.5))

			_animate_target_marker()
			
func _animate_target_marker() -> void:
	if target == null:
		return

	# Stop any previous tweens
	if _target_tween and _target_tween.is_running():
		_target_tween.kill()
	if _rotation_tween and _rotation_tween.is_running():
		_rotation_tween.kill()

	target.scale = Vector2.ONE
	# Don't reset rotation here; we want it to keep flowing

	_target_tween = create_tween()
	_target_tween.set_parallel(true)
	_target_tween.set_loops()	# pulse forever

	# --- Slow grow ---
	var grow := _target_tween.tween_property(
		target,
		"scale",
		Vector2(1.18, 1.18),
		0.8
	)
	grow.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# --- Slow shrink ---
	var shrink := _target_tween.tween_property(
		target,
		"scale",
		Vector2.ONE,
		0.8
	).set_delay(0.8)
	shrink.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Start continuous rotation on its own tween
	_start_target_rotation()
	
func _start_target_rotation() -> void:
	if target == null or not is_instance_valid(target):
		return

	if _rotation_tween and _rotation_tween.is_running():
		_rotation_tween.kill()

	var start_deg := target.rotation_degrees

	_rotation_tween = create_tween()
	var spin := _rotation_tween.tween_property(
		target,
		"rotation_degrees",
		start_deg + 360.0,
		3.0		# adjust for slower/faster spin
	)
	spin.set_trans(Tween.TRANS_LINEAR)

	_rotation_tween.tween_callback(func() -> void:
		_start_target_rotation()
	)
