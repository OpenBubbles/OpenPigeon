extends Node3D
class_name DartsGame

var main_dart: Dart
var bust_label: Panel
var waiting_label: Panel
var winner_label: Panel
var you_score_label: RichTextLabel
var opp_score_label: RichTextLabel

var darts: Array[Dart] = []
var current_dart: Dart
var num_shots: int = 0
var replay_played: bool = false

var has_connected: bool = false
var is_my_turn: bool = false
var player: int = -1
var mode: int = -1
var replay: String = ""

var my_moves: Array[Array]

var p1_pre_score: int = 0
var p2_pre_score: int = 0
var p1_score: int = 0
var p2_score: int = 0

func _ready():
	main_dart = get_node("dart")
	bust_label = get_node("SubViewportContainer/SubViewport/bustLabel")
	waiting_label = get_node("SubViewportContainer/SubViewport/waitingLabel")
	winner_label = get_node("SubViewportContainer/SubViewport/winnerLabel")
	you_score_label = get_node("SubViewportContainer/SubViewport/YouBox/ScoreLabel")
	opp_score_label = get_node("SubViewportContainer/SubViewport/OpponentBox/ScoreLabel")
	
	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		if not has_connected:
			print("App plugin is available")
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
	else:
		print("App plugin is not available")
		_set_game_data('{ "isYourTurn": true, "player": "1", "replay": "state:101,10|move:0,0.103483,0.142005,2,2,0|move:0,-0.343160,0.606544,9,9,0|move:0,0.128320,0.867287,0,0,0|state:90,10", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player1": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player2": "f7898779-d537-4b0f-8c51-d604e934e2fb", "id": "lfH52rteC7dc 4J7\n", "ios": "16.3.1", "num": "2", "game": "darts", "mode": "101", "tver": "5", "build": "56", "version": "0" }')
		
func _set_game_data(new_replay: String):
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: " + str(parsed))
	
	is_my_turn = parsed["isYourTurn"]
	player = int(parsed["player"])
	replay = parsed["replay"] if "replay" in parsed else ""
	mode = int(parsed["mode"])
	
	if is_my_turn:
		player = 2 if player == 1 else 1
	
	print("YOU ARE PLAYER: " + str(player))
	
	if replay.is_empty():
		p1_pre_score = mode
		p2_pre_score = mode
		set_score(1, mode)
		set_score(2, mode)
	
	replay_played = false
	reset_game_board()
	_process_game_state()

func _process_game_state():
	if is_my_turn:
		waiting_label.visible = false
		if replay != null and not replay.is_empty() and not replay_played:
			await play_replay(replay)
			if check_win():
				return
			reset_game_board()
			replay_played = true
			
		if num_shots < 3:
			var player_dart = spawn_dart(true)
			print("NEW DART: " + str(player_dart))
			player_dart.on_hit_board.connect(func(score):
				print("SCORED: " + str(score))
				var move_arr = [0, player_dart.position.x, player_dart.position.y]
				
				move_arr.append_array(score)
				my_moves.append(move_arr)
				dec_score(player, score[0])
				if get_score(player) < 0: #BUST!
					bust_label.visible = true
					var old_score = mode
					if replay != null and not replay.is_empty():
						var score_idx = 0 if player == 1 else 1
						old_score = parse_replay(replay)["post_state"][score_idx]
					await get_tree().create_timer(1).timeout
					bust_label.visible = false
					set_score(player, old_score)
					num_shots = 3 #skip rest of turn
				if get_score(player) == 0:
					num_shots = 3
				print(my_moves)
				_process_game_state()
			)
		else:
			send_replay()
			if check_win():
				return
			waiting_label.visible = true
	else:
		if replay != null and not replay.is_empty():
			var post_state = parse_replay(replay)["post_state"]
			set_score(1, post_state[0])
			set_score(2, post_state[1])
			if check_win():
				return
				
		waiting_label.visible = true

func check_win() -> bool:
	if get_score(player) == 0:
		winner_label.get_child(0).text = "[center]YOU WIN![/center]"
		winner_label.visible = true
		return true
	elif get_score(1 if player == 2 else 2) == 0:
		winner_label.get_child(0).text = "[center]YOU LOSE[/center]"
		winner_label.visible = true
		return true
	return false

func send_replay():
	var moves_str = ""
	for move in my_moves:
		moves_str += "move:" + str(int(move[0])) + "," + str("%0.6f" % move[1]) + "," + str("%0.6f" % move[2]) + "," + str(int(move[3])) + "," + str(int(move[4])) + "," + str(int(move[5])) + "|"
	
	var game_data = JSON.stringify({
		"replay": "state:" + str(p1_pre_score) + "," + str(p2_pre_score) + "|" + moves_str + "state:" + str(p1_score) + "," + str(p2_score)
	})
	
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(game_data)
	else:
		print("App not connected! " + game_data)

func play_replay(replay: String):
	var parsed = parse_replay(replay)
	var other_player = 1 if player == 2 else 2
	print("parsed replay: " + str(parsed))
	
	p1_pre_score = parsed["pre_state"][0]
	p2_pre_score = parsed["pre_state"][1]
	set_score(1, parsed["pre_state"][0])
	set_score(2, parsed["pre_state"][1])
	for move in parsed["moves"]:
		spawn_dart(false)
		var dart_pos = Vector3(move[1], move[2], 0.067)
		if current_dart != null:
			current_dart.throw(dart_pos)
			current_dart.replay_hit = [int(move[3]), int(move[4]), int(move[5])]
		await get_tree().create_timer(1).timeout
		dec_score(other_player, move[3])
		if get_score(other_player) < 0: #BUST!
			bust_label.visible = true
			await get_tree().create_timer(1).timeout
			bust_label.visible = false
	set_score(1, parsed["post_state"][0])
	set_score(2, parsed["post_state"][1])
	if player == 1:
		p2_pre_score = parsed["post_state"][1]
	elif player == 2:
		p1_pre_score = parsed["post_state"][0]

func parse_replay(replay: String) -> Dictionary:
	var result = {"moves": []}
	for elem in replay.split("|"):
		var spl = elem.split(":")
		if spl[0] == "state":
			var state_spl = spl[1].split(",")
			var state_key = "pre_state"
			if "pre_state" in result:
				state_key = "post_state"
			result[state_key] = [int(state_spl[0]), int(state_spl[1])]
		if spl[0] == "move":
			var move = []
			var move_spl = spl[1].split(",")
			for val in move_spl:
				move.append(float(val))
			result["moves"].append(move)
	return result

func set_score(player: int, score: int):
	if player == 1:
		p1_score = score
	elif player == 2:
		p2_score = score
	
	if self.player == player:
		you_score_label.text = str("[center]",score,"[/center]")
	else:
		opp_score_label.text = str("[center]",score,"[/center]")
		
func dec_score(player: int, score: int):
	if player == 1:
		set_score(1, p1_score - score)
	elif player == 2:
		set_score(2, p2_score - score)
		
func get_score(player: int) -> int:
	if player == 1:
		return p1_score
	elif player == 2:
		return p2_score
	return -1

func reset_game_board():
	if current_dart != null:
		current_dart.queue_free()
		current_dart = null
	
	for dart in darts:	
		dart.queue_free()
	
	darts.clear()
	my_moves.clear()
	
	num_shots = 0

func spawn_dart(is_mine: bool) -> Dart:
	var new_dart: Dart = main_dart.duplicate()
	new_dart.is_mine = is_mine
	new_dart.position = Vector3(0.032, -0.816, 1.217)
	add_child(new_dart)
	darts.append(new_dart)
	current_dart = new_dart
	num_shots += 1
	return new_dart
	
var drag_start_pos: Vector2 = Vector2.ZERO
var dragging: bool = false
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and current_dart != null and current_dart.is_mine:
		if event.button_index == 1:
			if event.pressed:
				drag_start_pos = event.position
				dragging = true
			else:
				if dragging:
					var drag_end_pos: Vector2 = event.position
					var delta: Vector2 = drag_end_pos - drag_start_pos
					delta.y = -delta.y

					print("Drag delta: " + str(delta.x, ", ", delta.y))
				
					var shot_coords = calc_shot_coordinates(delta)
					shot_coords.y += 0.344
					
					print("Shot coordinates: " + str(shot_coords))
					
					current_dart.throw(Vector3(shot_coords.x, shot_coords.y, 0.067))
					current_dart = null
					
					dragging = false
					

const rect_min_x = -250.0
const rect_max_x = 250.0
const rect_min_y = 0.0
const rect_max_y = 350.0
const board_radius = 0.535
func calc_shot_coordinates(shot_delta: Vector2) -> Vector2:
	var rect_center_x: float = (rect_min_x + rect_max_x) / 2.0
	var rect_half_width: float = (rect_max_x - rect_min_x) / 2.0
	
	var rect_center_y: float = (rect_min_y + rect_max_y) / 2.0
	var rect_half_height: float = (rect_max_y - rect_min_y) / 2.0

	var norm_x: float
	if rect_half_width == 0.0:
		norm_x = 0.0
	else:
		norm_x = (shot_delta.x - rect_center_x) / rect_half_width

	var norm_y: float
	if rect_half_height == 0.0:
		norm_y = 0.0
	else:
		norm_y = (shot_delta.y - rect_center_y) / rect_half_height

	norm_x = clamp(norm_x, -1.0, 1.0)
	norm_y = clamp(norm_y, -1.0, 1.0)

	var u: float = norm_x
	var v: float = norm_y

	var x_unit_disk: float
	var y_unit_disk: float
	if u == 0.0 and v == 0.0:
		x_unit_disk = 0.0
		y_unit_disk = 0.0
	else:
		var r_map: float
		var phi_map: float 

		if u * u > v * v:
			r_map = u
			phi_map = (PI / 4.0) * (v / u)
		else: 
			r_map = v
			phi_map = (PI / 2.0) - (PI / 4.0) * (u / v)
		
		x_unit_disk = r_map * cos(phi_map)
		y_unit_disk = r_map * sin(phi_map)

	return Vector2(x_unit_disk, y_unit_disk) * board_radius
