extends MeshInstance3D
class_name Dart
	
var finished: bool = false
var start_pos: Vector3
var end_pos: Vector3
var arc_height: float = 1.5 
var duration: float = 0.65

var is_mine: bool = false
var replay_hit: Array[int] = [] 

var game: DartsGame
var dartboard: Dartboard

signal on_hit_board(score: Array[int])

var _tween: Tween

func _ready() -> void:
	game = get_parent()
	dartboard = get_parent().get_node("dart_board")

func throw(p_end_pos: Vector3):
	start_pos = self.position
	end_pos = p_end_pos

	var control_x = (start_pos.x + end_pos.x) / 2.0
	var control_z = (start_pos.z + end_pos.z) / 2.0
	var control_y = (start_pos.y + end_pos.y) / 2.0 + arc_height
	
	control_y = max(control_y, start_pos.y + 0.5 * arc_height) # Ensure some upward arc
	control_y = max(control_y, end_pos.y + 0.5 * arc_height)  

	var control_pos = Vector3(control_x, control_y, control_z)

	if _tween and _tween.is_valid():
		_tween.kill() 

	_tween = create_tween()
	_tween.set_parallel(false) 
	_tween.set_trans(Tween.TRANS_LINEAR) 
	_tween.set_ease(Tween.EASE_IN_OUT)    

	_tween.tween_method(Callable(self, "_update_dart_position_bezier").bind(start_pos, control_pos, end_pos), 0.0, 1.0, duration)

	_tween.play()

	var previous_pos = start_pos
	var time_step = 0.05
	for i in range(1, int(duration / time_step) + 1):
		var t = min(i * time_step / duration, 1.0)
		var next_pos = _calculate_bezier_point(t, start_pos, control_pos, end_pos)
		_tween.tween_callback(Callable(self, "_orient_dart").bind(next_pos, previous_pos)).set_delay(i * time_step - 0.001)
		previous_pos = next_pos

func _update_dart_position_bezier(t: float, p0: Vector3, p1: Vector3, p2: Vector3):
	self.position = _calculate_bezier_point(t, p0, p1, p2)

func _calculate_bezier_point(t: float, p0: Vector3, p1: Vector3, p2: Vector3) -> Vector3:
	# quadratic bezier curve formula (1-t)^2 * P0 + 2 * (1-t) * t * P1 + t^2 * P2
	var one_minus_t = 1.0 - t
	var pos = (one_minus_t * one_minus_t * p0) + \
			  (2.0 * one_minus_t * t * p1) + \
			  (t * t * p2)
	return pos

func _orient_dart(current_target_pos: Vector3, previous_pos: Vector3):
	if self.position.is_equal_approx(end_pos):
		return
	
	if self.position.is_equal_approx(current_target_pos): 
		if not self.position.is_equal_approx(end_pos):
			look_at(end_pos, Vector3.UP)
		return

	if not previous_pos.is_equal_approx(self.position):
		var direction = (current_target_pos - self.position).normalized()
		if direction.length_squared() > 0.001: # Check for non-zero direction
			look_at(self.position + direction, Vector3.UP)

func _process(delta: float) -> void:
	if not finished and self.position.z <= 0.068:
		var dartboard_local_pos = Vector3(self.position.x, 0.344 - self.position.y, self.position.z)
		var pos_2d = Vector2(dartboard_local_pos.x, dartboard_local_pos.y)
		if is_mine:
			print("dart pos: " + str(pos_2d))
			var score = dartboard.get_score(pos_2d)
			if on_hit_board.has_connections():
				on_hit_board.emit(score)
		else:
			print("replay hit: " + str(replay_hit))
			dartboard.set_replay_highlight(pos_2d, replay_hit[1], replay_hit[2])
		finished = true 
