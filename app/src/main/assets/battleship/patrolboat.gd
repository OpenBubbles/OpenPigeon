extends Sprite2D

class_name Patrolboat

@export var textures: Array[Texture2D]
var this_battleground: BattleGround = null
var my_len = 0
var is_horizontal = false
var current_grid_pos = Vector2(-1, -1)
var parts_destroyed: Array[bool] = []
var canBeMoved = false

func decode_ship(encodedShip: String, battleground: BattleGround):
	this_battleground = battleground
	var start = Vector2(0, 0)
	var length = 0
	for attribute in encodedShip.split('&'):
		var name = attribute.split(':', true, 1)
		if name[0] == "pos":
			var coords = name[1].split(",")
			start = Vector2(int(coords[0]), int(coords[1]))
		if name[0] == "rot":
			if name[1] == "1":
				is_horizontal = true
		if name[0] == "num":
			var parts = name[1].split(",")
			parts_destroyed.assign(Array(parts).map(func(n): return n == '1'))
			length = len(parts)
	
	set_len(length)
	set_grid_position(start, is_horizontal)
	if not is_horizontal:
		rotate(-PI / 2)
	for i in range(length):
		if not parts_destroyed[i]:
			continue
		var grid = index_to_grid(i)
		this_battleground.mark(grid, BattlegroundMarker.MarkerMode.ELIMINATED)

func validate_position(pos: Vector2, horizontal: bool) -> bool:
	for i in range(my_len):
		var thisPos = pos
		if horizontal:
			thisPos += Vector2(i, 0)
		else:
			thisPos += Vector2(0, i)
		
		if thisPos.x >= this_battleground.columns or thisPos.x < 0:
			print("rejecting OOB")
			return false
		
		if thisPos.y < 0 or thisPos.y >= this_battleground.rows:
			print("rejecting OOB y")
			return false
			
		var idx = thisPos.y * this_battleground.columns + thisPos.x
		if this_battleground.ship_grid[idx] != null and this_battleground.ship_grid[idx] != self:
			print("rejecting")
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

func set_grid_position(pos: Vector2, horizontal: bool):
	if !validate_position(pos, horizontal):
		return
	
	if current_grid_pos != Vector2(-1, -1):
		for i in range(my_len):
			var thisPos = index_to_grid(i)
			var idx = thisPos.y * this_battleground.columns + thisPos.x
			assert(this_battleground.ship_grid[idx] == self)
			this_battleground.ship_grid[idx] = null
			this_battleground.ship_part[idx] = 0
	
	for i in range(my_len):
		var thisPos = pos
		if horizontal:
			thisPos += Vector2(i, 0)
		else:
			thisPos += Vector2(0, i)
		var idx = thisPos.y * this_battleground.columns + thisPos.x
		this_battleground.ship_grid[idx] = self
		this_battleground.ship_part[idx] = i
	
	if is_horizontal and not horizontal:
		rotate(-PI / 2)
	if not is_horizontal and horizontal:
		rotate(PI / 2)
	is_horizontal = horizontal
	
	this_battleground.update_grid_states()
	
	current_grid_pos = pos
	var half_len = my_len / float(2)
	position = this_battleground.grid_to_coord(pos + (Vector2(half_len, 0.5) if is_horizontal else Vector2(0.5, half_len)))
	

func encode_state() -> String:
	return ("pos:" + str(int(current_grid_pos.x)) + "," + str(int(current_grid_pos.y)) + "&num:" + 
		",".join(parts_destroyed.map(func(n): return '1' if n else '0')) + "&rot:" + ('1' if is_horizontal else '0'))

var is_dragging = false
var start_offset = Vector2(0, 0)
var down_frame = 0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if not event.pressed and event.button_index == 1 and is_dragging:
			is_dragging = false
			var delta = Time.get_ticks_msec() - down_frame
			if delta < 200:
				set_grid_rotation(!is_horizontal)
			print("not dragging")
	elif event is InputEventMouseMotion and is_dragging:
		var pos = event.position - this_battleground.get_transform().get_origin()
		set_grid_position(this_battleground.coord_to_grid(pos) - start_offset, is_horizontal)

func set_grid_rotation(horizontal: bool):
	var half_len = floor(my_len / float(2))
	
	var offset = Vector2(0, 0)
	
	if horizontal != is_horizontal:
		if horizontal:
			offset = Vector2(-half_len, half_len)
		else:
			offset = Vector2(half_len, -half_len)
	
	set_grid_position(current_grid_pos + offset, horizontal)


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
			var pos = event.position - this_battleground.get_transform().get_origin()
			start_offset = this_battleground.coord_to_grid(pos) - current_grid_pos
			down_frame = Time.get_ticks_msec()
			print("Dragging")
