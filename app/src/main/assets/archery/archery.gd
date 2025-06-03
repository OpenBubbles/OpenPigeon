extends Node3D
class_name ArcheryGame

@export var sensitivity: float = 1.5
@export var damping_factor: float = 0.9 
@export var max_speed: float = 1000.0 

@export var target: Target
@export var arrow: Arrow
@export var camera: Camera3D
@export var aim_cursor: Sprite2D
@export var aim_progress_bar: TextureProgressBar
@export var score_box: ArcheryScoreBox
@export var winner_label: PopupLabel
@export var waiting_label: Panel
@export var wind_panel: WindPanel

var num: int
var isTurn: bool
var player: int
var seed: int
var replay: Dictionary = {}
var my_uuid: String = ""

var appPlugin = null
var num_shots: int = 0
var aim_tween: Tween = null
var shots: Array[Arrow] = []
var moves: Array[Vector3] = []
var current_arrow: Arrow = null
var played_replay: bool = false
var send_winner: String = ""

var current_wind_angle: Vector2
var current_wind_power: float

var winner = ""

func _ready() -> void:
	appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("App plugin is available")
		appPlugin.connect("set_game_data", _set_game_data)
		my_uuid = appPlugin.getSenderUUID()
		appPlugin.onReady()
	else:
		print("App plugin is not available")
		my_uuid = "0a602920-2033-469d-aab8-5e832c5d4f6a"
		#_set_game_data('{"isYourTurn":true,"num":"3","player":"2","seed":"1909419073","replay":"state:1,28,0,0,0|move:1,0.036382,1.430337,-14.397592|move:1,0.033652,1.405363,-14.397592|move:1,-0.079288,1.372874,-14.397592|state:1,28,30,0,1"}')
		_set_game_data('{ "isYourTurn": true, "player": "2", "replay": "state:2,0,0,1,1|move:0,2.433302,4.115979,-19.019581|move:0,1.885665,4.547050,-19.018667|move:0,1.404883,4.726025,-19.029633|state:2,0,0,0,1", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,0|mouth,0|acc,0|wins,0|bg_color,0.900000,0.900000,0.900000|body_color,0.000000,1.000000,0.000000|glasses,0|stache,0|backdrop,0|hair,3|clothes,2|hair_color,0.431373,0.254902,0.121569|clothes_color,0.438450,0.340784,0.366469", "player1": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player2": "ca4f9573-85a1-47a6-adcf-fd8d61680e9d", "id": "6gt6WvSteSKHYrKr\n", "ios": "16.3.1", "num": "3", "game": "archery", "seed": "247149971", "tver": "5", "build": "d4yGowcTuIW9i", "version": "0" }')
	
func check_winner() -> bool:
	print(score_box.set_num)
	print(score_box.you_set_wins)
	print(score_box.opp_set_wins)
	
	if score_box.set_num == 3 && score_box.you_set_wins == score_box.opp_set_wins:
		send_winner = my_uuid+"|0"
		winner_label.show_label("Draw!")
		return true
	elif score_box.you_set_wins == score_box.opp_set_wins:
		return false
	elif score_box.you_set_wins == 2:
		send_winner = my_uuid+"|1"
		winner_label.show_label("You Win!")
		return true
	elif score_box.opp_set_wins == 2:
		send_winner = my_uuid+"|-1"
		winner_label.show_label("You Lose.")
		return true
	return false
	
func _process_game_state() -> void:
	if isTurn == false:
		waiting_label.visible = true
		return
		
	waiting_label.visible = false
	if replay.is_empty() == false and played_replay == false:
		await play_replay()
		score_box.set_you_score(replay["post_state"][1 if player == 1 else 2])
		score_box.set_opp_score(replay["post_state"][2 if player == 1 else 1])
		score_box.set_you_set_wins(replay["post_state"][3 if player == 1 else 4])
		score_box.set_opp_set_wins(replay["post_state"][4 if player == 1 else 3])
		if (num - 1) % 2 == 0:
			if check_winner(): return
			score_box.set_you_score(0)
			score_box.set_opp_score(0)
			update_set_number(replay["post_state"][0] + 1)
		
	if num_shots < 3:
		calc_wind()
		current_arrow = arrow.spawn()
	else:
		if num % 2 == 0:
			if score_box.opp_score > score_box.you_score:
				score_box.set_opp_set_wins(score_box.opp_set_wins + 1)
			elif score_box.you_score > score_box.opp_score:
				score_box.set_you_set_wins(score_box.you_set_wins + 1)
			elif score_box.you_score == score_box.opp_score:
				score_box.set_opp_set_wins(score_box.opp_set_wins + 1)
				score_box.set_you_set_wins(score_box.you_set_wins + 1)
			check_winner()
			
		if appPlugin:
			appPlugin.updateGameData(export_replay())
		else:
			print("No app plugin! " + export_replay())
			
		if winner_label.visible == false:
			waiting_label.visible = true
	
func export_replay() -> String:
	var replay_str = str("state:1,0,0,0,0|")
	if replay.is_empty() == false:
		var state = replay["post_state"]
		if (num - 1) % 2 != 0:
			replay_str = str("state:",state[0],",",state[1],",",state[2],",",state[3],",",state[4],"|")
		else:
			replay_str = str("state:",score_box.set_num,",0,0,",state[3],",",state[4],"|")
	
	for move in moves:
		replay_str += str("move:1,","%0.6f" % move.x,",","%0.6f" % move.y,",","%0.6f" % (int(target.position.z) - 0.397593),"|")
		
	var p1_score = score_box.you_score if player == 1 else score_box.opp_score
	var p2_score = score_box.you_score if player == 2 else score_box.opp_score
	var p1_set_score = score_box.you_set_wins if player == 1 else score_box.opp_set_wins
	var p2_set_score = score_box.you_set_wins if player == 2 else score_box.opp_set_wins
	replay_str += str("state:",score_box.set_num,",",p1_score,",",p2_score,",",p1_set_score,",",p2_set_score)
	
	var replay_dict = {"replay": replay_str}
	if send_winner.is_empty() == false:
		replay_dict["winner"] = send_winner
	return JSON.stringify(replay_dict)
	
func calc_wind() -> void:
	var rng = RandomNumberGenerator.new()
	rng.set_seed(seed)
	
	print("shot number: ", num_shots)
	
	for i in range(0, score_box.set_num):
		rng.randf()
	
	if num_shots > 0:
		if num_shots == 1:
			rng.randf()
		elif num_shots == 2:
			rng.randf()
			rng.randf()
	
	var power: float 
	var angle: float
	
	if score_box.set_num == 1:
		if num_shots == 0:
			power = rng.randf_range(0.5, 0.8)
		elif num_shots == 1:
			power = rng.randf_range(1.0, 1.5)
		elif num_shots == 2:
			power = rng.randf_range(1.5, 3.0)
	elif score_box.set_num == 2:
		power = rng.randf_range(1.5, 3.0)
	elif score_box.set_num == 3:
		power = rng.randf_range(2.0, 4.0)
			
	angle = rng.randf_range(0.0, 360.0);
	
	wind_panel.set_wind_power(power)
	wind_panel.set_wind_angle(angle)
	current_wind_angle = Vector2.UP.rotated(deg_to_rad(angle))
	current_wind_angle.y = -current_wind_angle.y
	current_wind_power = power
	
	print("wind angle: " + str(angle) + " - " + str(current_wind_angle))
	print("wind vector: " + str(power))
	
	
func update_set_number(set_num: int) -> void:
	if set_num == 1:
		target.position.z = -14.433
	elif set_num == 2:
		target.position.z = -20.433
	elif set_num == 3:
		target.position.z = -26.433
	score_box.update_set_number(set_num)
	
func play_replay() -> void:
	var cam_tween = create_tween()
	cam_tween.set_loops(1)
	cam_tween.tween_property(camera, "position:z", target.position.z + 4.75, 0.5).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(0.5).timeout
	
	var replay_arrows = []
	for move in replay["moves"]:
		var replay_pos = Vector3(move[1], move[2], move[3])
		replay_arrows.append(arrow.spawn())
		replay_arrows[-1].shoot(replay_pos, func(): 
			var arrow_score = target.calc_score(replay_arrows[-1])
			if len(replay_arrows) == 3:
				var opp_post_score = replay["post_state"][2 if player == 1 else 1]
				score_box.set_opp_score(opp_post_score)
			else:
				add_score(target.calc_score(replay_arrows[-1]), false)
		)
		await get_tree().create_timer(2).timeout
	
	var _tween = create_tween()
	_tween.set_loops(1)
	_tween.tween_property(camera, "position", Vector3(0, 1.718, 1.616), 0.5).set_trans(Tween.TRANS_SINE)
	
	for arrow in replay_arrows:
		if is_instance_valid(arrow):
			arrow.queue_free()
	
	replay_arrows = []
	
	while _tween.is_running():
		await get_tree().create_timer(0.1).timeout
	played_replay = true
	print("replay finished")
	
func parse_replay(replay_str: String) -> Dictionary:
	var result = {'moves': []}
	var replay_split = replay_str.split('|')
	for elem in replay_split:
		if elem.begins_with("state:"):
			var state_name = "post_state" if "pre_state" in result else "pre_state"
			result[state_name] = convert_to_int_arr(elem.split(':')[1])
		elif elem.begins_with("move:"):
			result['moves'].append(convert_to_float_arr(elem.split(':')[1]))	
	return result
	
func _set_game_data(new_replay: String) -> void:
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: " + str(parsed))
	
	isTurn = parsed["isYourTurn"]
	player = int(parsed["player"])
	seed = int(parsed["seed"])
	num = int(parsed["num"])
		
	if isTurn:
		player = 2 if player == 1 else 1
	
	if "replay" in parsed and parsed["replay"].is_empty() != true:
		replay = parse_replay(parsed["replay"])
		update_set_number(replay["pre_state"][0])
		score_box.set_you_score(replay["pre_state"][1 if player == 1 else 2])
		score_box.set_opp_score(replay["pre_state"][2 if player == 1 else 1])
		score_box.set_you_set_wins(replay["pre_state"][3 if player == 1 else 4])
		score_box.set_opp_set_wins(replay["pre_state"][4 if player == 1 else 3])
	
	for arrow in shots:
		arrow.queue_free()
		
	moves = []
	num_shots = 0
	played_replay = false
	
	print("YOU ARE PLAYER " + str(player))	
	_process_game_state()
	
func add_score(score: int, you: bool = true) -> void:
	if you == false:
		score_box.set_opp_score(score_box.opp_score + score)
	else:
		score_box.set_you_score(score_box.you_score + score)
	
var aim_cursor_velocity: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var initial_pos: Vector2 = Vector2.ZERO
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == 1 and current_arrow != null:
			if event.pressed:
				reset_aim_tween()
				aim_cursor.position = Vector2(300, 500)
				aim_cursor.visible = true
				is_dragging = true
				initial_pos = event.position
				camera_zoom(41.5)
				start_aim_timer()
				print("started dragging")
			elif is_dragging:
				shoot_dart()
				print("stopped dragging")
	elif event is InputEventMouseMotion:
		if is_dragging:
			var delta_finger_pos: Vector2 = event.position - initial_pos
			var desired_velocity = delta_finger_pos * sensitivity # Divide by delta time to get velocity per second
			
			get_tree().create_timer(0.2).timeout.connect(func():
				aim_cursor_velocity = desired_velocity
				if aim_cursor_velocity.length() > max_speed:
					aim_cursor_velocity = aim_cursor_velocity.normalized() * max_speed
			)

func _process(delta: float) -> void:
	if not is_dragging:
		aim_cursor_velocity *= pow(damping_factor, delta)
		
	aim_cursor.position += aim_cursor_velocity * delta
	
	var viewport_size = get_viewport().get_visible_rect().size
	position.x = clampf(position.x, 0, viewport_size.x)
	position.y = clampf(position.y, 0, viewport_size.y)
	
func camera_zoom(val: float) -> void:
	var _tween = create_tween()
	_tween.set_loops(1)
	_tween.tween_property(camera, "fov", val, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.play()

func calc_shot_pos() -> Vector3:
	print(aim_cursor.position)
	var ray_origin: Vector3 = camera.project_ray_origin(aim_cursor.position)
	var ray_normal: Vector3 = camera.project_ray_normal(aim_cursor.position)
	
	if abs(ray_normal.z) < 0.0001:
		printerr("Ray is parallel to the target plane!!!")
		return Vector3()
	
	var t: float = ((target.position.z + 0.296) - ray_origin.z) / ray_normal.z
	var target_3d_position: Vector3 = ray_origin + ray_normal * t
	
	print("Projected 3D position: ", target_3d_position)
	return target_3d_position

func cam_follow_dart(shot_pos: Vector3) -> void:
	var _tween = create_tween()
	_tween.set_loops(1)
	_tween.connect("finished", func():
		add_score(target.calc_score(shots[-1]))
	)
	_tween.parallel().tween_property(camera, "position:z", target.position.z + 4.75, 0.5).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(camera, "position:x", shot_pos.x, 0.5).set_trans(Tween.TRANS_SINE)
		
func cam_reset_pos() -> void:
	var _tween = create_tween()
	_tween.set_loops(1)
	_tween.tween_property(camera, "position", Vector3(0, 1.718, 1.616), 0.5).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(0.5).timeout
	
func start_aim_timer() -> void:
	await get_tree().create_timer(3).timeout
	aim_progress_bar.visible = true
	aim_tween = create_tween()
	aim_tween.set_loops(1)
	aim_tween.tween_property(aim_progress_bar, "value", 100.0, 5).set_trans(Tween.TRANS_LINEAR)
	aim_tween.connect("finished", func():
		aim_tween = null
		if aim_cursor.visible == true:
			shoot_dart()
	)
	
func shoot_dart() -> void:
	is_dragging = false
	aim_progress_bar.visible = false
	aim_cursor.visible = false
	aim_cursor_velocity = Vector2.ZERO
	
	var shot_pos = calc_shot_pos()
	print("initial shot pos: " + str(shot_pos))
	
	var flight_time = (0.15 * score_box.set_num) if score_box.set_num > 1 else 0.50
	var wind_displacement: Vector2 = current_wind_angle * flight_time * (current_wind_power*0.25)
	print("wind displacement: " + str(wind_displacement))
	
	var shot_pos_2d = Vector2(shot_pos.x, shot_pos.y) + wind_displacement
	shot_pos = Vector3(shot_pos_2d.x, shot_pos_2d.y, shot_pos.z)
	print("new shot pos: " + str(shot_pos))
	
	current_arrow.shoot(shot_pos, func():
		num_shots += 1
		await get_tree().create_timer(1).timeout
		cam_reset_pos()
		_process_game_state()
	)
	camera.fov = 60
	cam_follow_dart(shot_pos)
	shots.append(current_arrow)
	moves.append(shot_pos)
	current_arrow = null
	
func reset_aim_tween() -> void:
	aim_progress_bar.value = 0
	aim_progress_bar.visible = false
	if aim_tween != null:
		aim_tween.stop()
		aim_tween = null
		
func convert_to_int_arr(str: String) -> Array[int]:
	var result: Array[int] = []
	if len(str) > 0:
		for elem in str.split(','):
			result.append(int(elem))
	return result
	
func convert_to_float_arr(str: String) -> Array[float]:
	var result: Array[float] = []
	if len(str) > 0:
		for elem in str.split(','):
			result.append(float(elem))
	return result
