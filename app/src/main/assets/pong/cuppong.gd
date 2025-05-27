extends Node3D
class_name PongGame

var REPLAY_FRAME_DURATION: float = 0.03
var CHARMAP = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789~!@*()_+-.';"
var CHARMAP_LEN = len(CHARMAP)

var appPlugin: Object
var screen_size: Vector2
var has_connected: bool = false
var waiting_label: Panel
var balls_back_label: PopupLabel
var redemption_label: PopupLabel
var overtime_label: PopupLabel
var winner_label: PopupLabel

var camera: Camera3D
var ball: RigidBody3D
var my_cups: Cups
var replay_cups: Cups
var current_ball: PongBall

var start_replay_boards: String = "0,1,2,3,4,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9"

var replay_ball_start_pos: Vector3 = Vector3(0, -0.574, -0.80)
var player_ball_start_pos: Vector3 = Vector3(0, -0.574, -1.202)

var num_balls: int = 2
var throws: Array[Dictionary] = []
var redemption: bool = false
var played_replay: bool = false
var lost: bool = false

var player: int
var is_my_turn: int
var replay_string: String
var mode: String
var winner: String = ""

var my_uuid: String = ""

func _ready():
	winner_label = get_node("SubViewportContainer/SubViewport/winnerLabel")
	waiting_label = get_node("SubViewportContainer/SubViewport/waitingLabel")
	balls_back_label = get_node("SubViewportContainer/SubViewport/ballsBackLabel")
	redemption_label = get_node("SubViewportContainer/SubViewport/redemptionLabel")
	overtime_label = get_node("SubViewportContainer/SubViewport/overtimeLabel")
	screen_size = get_viewport().get_visible_rect().size
	my_cups = get_node("cups2")
	replay_cups = get_node("cups1")
	camera = get_node("Camera3D")
	ball = get_node("ball")
	appPlugin = Engine.get_singleton("AppPlugin")
	
	if appPlugin:
		if not has_connected:
			print("App plugin is available")
			appPlugin.connect("set_game_data", _set_game_data)
			my_uuid = appPlugin.getSenderUUID()
			has_connected = true
			appPlugin.onReady()
	else:
		print("App plugin is not available")
		#board:0,1,2,3,4,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9|move:K;AEDSK;AEDSLaC~DgLbFdCRLdHdCgLeI~BSLfKFBhLgL7ATLhM\'AiLiN zULjO0zkLlPtyWLmPTymLnP5xZLoP1xpLpPJw2LqPbwsLrOCv5LsNNvwLuMJu9LvLruALwJ7t(LxIltFLyGys-LzEwsKL9CIskL;BAsGLRA_suL1A siL*A_sgL;A_sgMdA_siMgA_skMiA_skMiA_skMiA_sk2&25|move:K;AEDSK-DgC K_FtCAK(HsB5K!JbBoK9KRAUK7L AdK4NgzJK2Ocy(K0O5yyKYPxx4KVPVxoKTP5wVKRP0wfKOPGvMKMO.u.KKOwuEKINFt!KFMAtwKDLhs3KBJUspKzH\'rWKxGjriKuEfqQKsB~qcJ(A(qaJ)BjqmKeBnqsKnBeqqKuA_qpKxA_qmKyA_qlKyA_qlKyA_ql6&24,28|move:K;AEDSK\'B9DyK-EjC*K_GpCGK)IhB\'K*J5BNK!LrBgK9MLAWK8NPApK6ODz4K4PdzyK2PKy*K1P2yHKZP5ybKXPTxRKWPsxlKUOYw1KSN_wwKRM-v@KPL7vGKNKGvbKMI*uSKKHkunKIFot4KHDetzLSB8tnK5BotALtA-tALoA-tELkA_tGLiA_tILhA_tJLhA_tJLhA_tJ0&24|move:K;AEDSK(C(DdK6FhCMKZHhB;KSI*BJKLKIA-KEL9AGKxNaz)KpN.zDKiO1y*KbPuyBJ_PUx@J9P5xAJ2P1w!JWPIwzJPPav~JIOAvzJBNLu~JuMHuzJnLpt~JhJ4tAJaIis!I)GvsBI8Esr*ITEvrOIAFHrxIgGErgH9Hlq!HPH0qUHwIeqDHcIoqmG5Ikp-GMH*p1GtHFpKGaG4puF3F)pdFKE!o9FrDSoSE\'CloCE1ALolEJyXn EqwUn1D\'uDnLD1r\'nv&24|board:1,3,4,5,7,8,9&0,1,2,3,4,5,6,7,8,9
		_set_game_data('{"isYourTurn":true,"skip_score1":"0","skip_score2":"0","player":"1","replay":"board:0,1,3,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9|move:K;AEDSLaDmDeLcFACRLdHyCjLeJgBXLgKVBpLhL;A3LiNjAvLjOez9LlO7zBLmPyy_LnPWyILoP5ybLqP0xQLrPFxjLsO-wYLtOtwrLvNCv6LwMxvALxLdu)LyJQuJLzH)udLBGdtTLCD;tnK\'C;tHLgC9tALsCYtxLhCItZK;CstFK*B7tsK(ButuK;A_tFLeA_tOLhA_tOLhA_tNLhA_tN0&24,27,31|move:K;AEDSK-C-DhK)FlCVK@HkCmK9I_B0K6KLBsK3L@A6K0NcAyKXN;z@KVO2zFKSPvy.KPPVyMKMP5yeKJP1xTKGPIxmKDO;w1KBOzwvKyNJv~KvMFvDKsLmu.KpJ1uMKnIfugKkGrtWKhEotqKgDhtHKgC uxKgCPvnKhB;wcKhBqw(KhAsx3KhBoyQKhB3zCKiCgAoKiCqBaKiCmB8KiB(CTKiBGDEKjA5EqKjA3E;KjBpF4&24,29,38|board:1,3,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9","score1":"0","score2":"0","num":"2","game":"beer","mode":"n","seed":"-1429210425","round":"1","seed2":"0"}')

func check_winner() -> bool:
	if not winner.is_empty():
		if winner.split('|')[0] == my_uuid:
			winner_label.show_label("You Lose!")
		else:
			winner_label.show_label("You Win!")
		return true
	return false

func _process_game_state():
	if played_replay == false:
		if not replay_string.is_empty():
			var parsed_replay = parseReplay(replay_string)
			set_boards(parsed_replay)
			if is_my_turn:
				waiting_label.visible = false
				playReplay(parsed_replay)
				return
		else:
			if check_winner(): return
			if is_my_turn:
				waiting_label.visible = false
				camera.position = Vector3(0.0, 1.147, -1.73)
	elif is_my_turn:
		if check_winner(): return
		if len(replay_cups.cups_in_play) == 0:
			redemption_label.popup()
			redemption = true
	
	if check_winner(): return
	
	if is_my_turn:
		current_ball = spawn_ball()
	else:
		waiting_label.visible = true
	
func throw_finished():
	if len(throws) > 0 and len(throws) % 2 == 0:
		if throws[-1]["cup"] > -1 and throws[-2]["cup"] > -1:
			balls_back_label.popup()
			num_balls = 2
			
	if redemption:
		if throws[-1]["cup"] == -1:
			winner_label.show_label("You Lose!")
			num_balls = 0
			lost = true
		elif len(my_cups.cups_in_play) == 0:
			my_cups.reset_cups([0,1,2])
			replay_cups.reset_cups([0,1,2])
			overtime_label.popup()
			await get_tree().create_timer(1.5).timeout
			num_balls = 0
			
	if num_balls > 0:
		current_ball = spawn_ball()
	else:
		if winner_label.visible == false:
			waiting_label.visible = true
		if appPlugin:
			appPlugin.updateGameData(export_replay())
		else:
			print("No app plugin! " + export_replay())
	
func set_boards(parsed_replay: Dictionary):
	var my_board: Array
	var other_board: Array
	if player == 1:
		my_board = parsed_replay["p1_board"]
		other_board = parsed_replay["p2_board"]
	elif player == 2:
		my_board = parsed_replay["p2_board"]
		other_board = parsed_replay["p1_board"]
	my_cups.prev_cups = my_board
	my_cups.set_cups_in_play(my_board)
	replay_cups.set_cups_in_play(other_board)

func _set_game_data(new_replay: String):
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: " + str(parsed))
	
	is_my_turn = parsed["isYourTurn"]
	player = int(parsed["player"])
	replay_string = parsed["replay"] if "replay" in parsed else ""
	mode = parsed["mode"]
	winner = parsed["winner"] if "winner" in parsed else ""

	if is_my_turn:
		player = 2 if player == 1 else 1
		
		
	played_replay = false
	redemption = false
	num_balls = 2
	throws = []
		
	_process_game_state()

func export_board(exp_player: int):
	var board: Array
	if player == exp_player:
		board = my_cups.cups_in_play
	else:
		board = replay_cups.cups_in_play
	
	var result = ""
	for cup_idx in board:
		result += str(cup_idx)+","
	return result.substr(0, len(result)-1)
	
func export_replay() -> String:
	var replay_str = str("board:",start_replay_boards,"|")
	for move in throws:
		replay_str += "move:"+convert_replay(move["poses"])
		if move["cup"] > -1:
			replay_str += str(move["cup"])
		replay_str += "&24|"
	replay_str += str("board:",export_board(1),"&",export_board(2))
	
	var export_data = {"replay": replay_str}
	if lost:
		export_data["winner"] = my_uuid+"|-1"
	return JSON.stringify(export_data)

func convert_replay(poses: Array[Vector3]):
	var result: String = ""
	for pos in poses:
		result += conv(((-pos.x) + 3.0) / 6.0)
		result += conv((pos.y + 2.0) * 0.25)
		result += conv((((2.0 * -1.0 - pos.z) + 0.1) + 4.0) * 0.125)
	return result

func conv(input_float: float) -> String:
	var max_encoded_integer_value = CHARMAP_LEN * CHARMAP_LEN - 1
	var combined_idx_float = input_float * float(max_encoded_integer_value)

	var combined_idx = int(round(combined_idx_float))
	combined_idx = clamp(combined_idx, 0, max_encoded_integer_value)
	
	var first_idx: int = combined_idx / CHARMAP_LEN
	var second_idx: int = combined_idx % CHARMAP_LEN
	var char1: String = CHARMAP[first_idx]
	var char2: String = CHARMAP[second_idx]
	return char1 + char2
	
func convback(str: String) -> float:
	var first_idx = CHARMAP.find(str[0])
	var second_idx = CHARMAP.find(str[1])
	return float(second_idx + first_idx * CHARMAP_LEN) / float(CHARMAP_LEN * CHARMAP_LEN - 1)
	
func spawn_ball(is_replay: bool = false) -> RigidBody3D:
	var new_ball: PongBall = ball.duplicate()
	if is_replay:
		new_ball.position = replay_ball_start_pos
	else:
		new_ball.position = player_ball_start_pos
		new_ball.freeze = false
		new_ball.is_mine = true
		num_balls -= 1
	add_child(new_ball)
	return new_ball
	
func parseReplay(replay: String) -> Dictionary:
	var result = {"moves": []}
	for elem in replay.split("|"):
		var spl = elem.split(":")
		if spl[0] == "board":
			if "p1_board" not in result:
				var boards = spl[1].split("&")
				result["p1_board"] = convert_arr(boards[0])
				result["p2_board"] = convert_arr(boards[1])
			else:
				start_replay_boards = spl[1]
		if spl[0] == "move":
			var move = []
			var move_spl = spl[1].split("&")[0]
			for idx in range(0, len(move_spl), 6):
				if idx+5 < len(move_spl):
					var x = convback(move_spl[idx] + move_spl[idx+1]) * 6.0 - 3.0
					var y = convback(move_spl[idx+2] + move_spl[idx+3]) * 4.0 - 2.0
					var z = convback(move_spl[idx+4] + move_spl[idx+5]) * 8.0 - 4.0
					move.append(Vector3(x, y, z))
			if len(move_spl) % 6 > 0:
				move.append(int(move_spl[-1]))
			result["moves"].append(move)
	return result
	
func playReplay(parsed: Dictionary):
	camera.position = Vector3(0.0, 1.147, -3.486)
	for idx in range(len(parsed["moves"])):
		var move: Array = parsed["moves"][idx]
		await get_tree().create_timer(1).timeout
		
		var new_ball = spawn_ball(true)
		
		var tween = create_tween().set_loops(1)
		
		var move_cleaned: Array = move.duplicate()
		for move_idx in range(1, len(move_cleaned)):
			if move_idx < len(move_cleaned) and move_cleaned[move_idx] is Vector3:
				var move_diff = move_cleaned[move_idx] - move_cleaned[move_idx-1]
				if abs(move_diff.x) > 0.05:
					print("removed " + str(move_diff))
					move_cleaned.remove_at(move_idx)
					move_idx -= 1
					
		new_ball.position = move_cleaned[0]
		var current_pos: Vector3 = new_ball.position
		
		for next_pos in move_cleaned:
			if next_pos is Vector3:
				#next_pos.z += 0.1
				if current_pos.distance_to(next_pos) > 0.5:
					tween.tween_property(new_ball, "linear_velocity", Vector3(0.0, -1, -1), 0.0)
					tween.tween_property(new_ball, "freeze", false, 0.0)
					break
					
				tween.tween_property(
					new_ball, "position", next_pos, REPLAY_FRAME_DURATION
				).from(current_pos).set_trans(Tween.TRANS_SINE)
				current_pos = next_pos
			
		var is_final_move: bool = (idx + 1 == len(parsed["moves"]))
		tween.connect("finished", Callable(self, "_on_replay_finished").bind(new_ball, move, is_final_move))
			
		tween.play()
		await get_tree().create_timer(len(move_cleaned)*REPLAY_FRAME_DURATION).timeout

func _on_replay_finished(new_ball: PongBall, move: Array, final_move: bool):
	if move[-1] is int:
		var hit_cup = move[-1] + 1
		print("replay hit cup ", hit_cup, "!!!")
		replay_cups.remove_cup(hit_cup)
	new_ball.queue_free()
	
	if final_move:
		await get_tree().create_timer(1).timeout
		var cam_tween = create_tween()
		cam_tween.tween_property(
			camera, "position", Vector3(0.0, 1.147, -1.73), 1
		).from(camera.position).set_trans(Tween.TRANS_SINE)
		cam_tween.play()
		played_replay = true
		_process_game_state()
		
func convert_arr(str: String):
	var result = []
	if len(str) > 0:
		for elem in str.split(','):
			result.append(int(elem))
	return result
	
var drag_start_pos = Vector2.ZERO
var dragging = false
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and current_ball != null:
		if event.button_index == 1:
			if event.pressed:
				print("START DRAG: " + str(event.position))
				drag_start_pos = event.position
				dragging = true
			else:
				if dragging:
					print("END DRAG: " + str(event.position))
					var drag_end_pos = event.position
					var delta = drag_end_pos - drag_start_pos
					delta.y = -delta.y
					
					print("X delta: " + str(delta.x) + ", Y delta: " + str(delta.y))
					var delta_lerp = interpolate_delta(delta.x, delta.y)
					print("Delta interpolated: " + str(delta_lerp))
					
					current_ball.throw(delta_lerp.x, delta_lerp.y)
					
					dragging = false

func interpolate_delta(x_delta: float, y_delta: float) -> Vector2:
	var x_lerp = inverse_lerp(-100, 100, x_delta)
	var y_lerp = inverse_lerp(0, screen_size.y/2.625, y_delta)
	return Vector2(lerp(-0.20, 0.20, x_lerp), lerp(0.0, 0.90, y_lerp))
