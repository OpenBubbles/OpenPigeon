extends BaseGame3D
class_name DartsGame

const MUSIC_STREAM := preload("res://global/audio/darts.ogg")

@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var winner_label: Label = %WinLossLabel
@onready var bust_label: Label = %BustLabel
@onready var sent_label: Label = %SentLabel
@onready var you_score_label: Label = %PlayerScoreLabel
@onready var opp_score_label: Label = %OpponentScoreLabel
@onready var main_overlay: Control = %MainOverlay
@onready var spectator_label: Label = %SpecLabel

var main_dart: Dart

var darts: Array[Dart] = []
var current_dart: Dart
var num_shots: int = 0
var replay_played: bool = false
var sent_tween: Tween
var is_my_turn: bool = false
var player: int = -1
var mode: int = -1
var replay: String = ""

var my_moves: Array[Array]

var p1_pre_score: int = 0
var p2_pre_score: int = 0
var p1_score: int = 0
var p2_score: int = 0
var redemption_active: bool = false
var redemption_darts_allowed: int = 0
var game_over: bool = false


const RESULT_NONE := 0
const RESULT_WIN := 1
const RESULT_LOSS := -1
const RESULT_DRAW := 2

var match_result: int = RESULT_NONE

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
func _get_dev_data() -> String:
	return '{ "isYourTurn": true, "player": "1", "replay": "state:101,10|move:0,0.103483,0.142005,2,2,0|move:0,-0.343160,0.606544,9,9,0|move:0,0.128320,0.867287,0,0,0|state:90,10", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player1": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player2": "", "id": "dev", "ios": "16.3.1", "num": "2", "game": "darts", "mode": "101", "tver": "5", "build": "56", "version": "0" }'
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Darts"

func _on_game_ready():
	main_dart = get_node("dart")
	
func _set_game_data(new_replay: String):
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: " + str(parsed))
	is_my_turn = parsed["isYourTurn"]
	player = int(parsed["player"])
	replay = parsed["replay"] if "replay" in parsed else ""
	mode = int(parsed["mode"])
	var opponent_avatar_key = ""
	var p1_id: String = parsed.get("player1", "")
	var p2_id: String = parsed.get("player2", "")
	spectator_mode = my_uuid != "" and p1_id != "" and p2_id != "" and my_uuid != p1_id and my_uuid != p2_id
	if is_instance_valid(spectator_label):
		spectator_label.visible = spectator_mode
	if is_my_turn and not spectator_mode:
		player = 2 if player == 1 else 1
	elif spectator_mode:
		player = 1

	if player == 1 or spectator_mode:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"

	if opponent_avatar_key != "" and parsed.has(opponent_avatar_key):
		var avatar_string = parsed[opponent_avatar_key]
		var opponent_data = GameUtils._parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
	if spectator_mode and parsed.has("avatar1"):
		var p1_data = GameUtils._parse_avatar_string(parsed["avatar1"])
		if is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", p1_data)

	print("YOU ARE PLAYER: " + str(player))

	stop_waiting_animation()
	redemption_active = false
	redemption_darts_allowed = 0
	replay_played = false
	game_over = false
	match_result = RESULT_NONE
	reset_game_board()
	winner_label.visible = false

	if parsed.has("winner") and parsed["winner"] != null and parsed["winner"] != "":
		var parts := str(parsed["winner"]).split("|", false)
		var result_code := RESULT_NONE
		if parts.size() >= 2:
			var winner_val: int = int(parts[1])
			if winner_val == 0:
				result_code = RESULT_DRAW
			elif parts[0] == my_uuid:
				result_code = RESULT_WIN if winner_val == 1 else RESULT_LOSS
			else:
				result_code = RESULT_WIN if winner_val == -1 else RESULT_LOSS
		if not replay.is_empty():
			await play_replay(replay)
		_show_result(result_code)
		return

	if replay.is_empty():
		p1_pre_score = mode
		p2_pre_score = mode
		set_score(1, mode)
		set_score(2, mode)
	_process_game_state()
	
func _get_turn_dart_limit() -> int:
	if redemption_active:
		return redemption_darts_allowed
	return 3

func _maybe_start_redemption_from_replay() -> bool:
	if spectator_mode or player != 2 or replay == null or replay.is_empty():
		return false

	var parsed := parse_replay(replay)
	if not parsed.has("pre_state") or not parsed.has("post_state"):
		return false

	var pre_state: Array = parsed["pre_state"]
	var post_state: Array = parsed["post_state"]
	if pre_state.size() < 2 or post_state.size() < 2:
		return false

	if not (int(pre_state[0]) != 0 and int(post_state[0]) == 0):
		return false

	redemption_active = true
	redemption_darts_allowed = 3
	return true

func _process_game_state():
	if is_my_turn:
		stop_waiting_animation()
		if replay != null and not replay.is_empty() and not replay_played:
			await play_replay(replay)

			var started_redemption := _maybe_start_redemption_from_replay()
			if started_redemption:
				reset_game_board()
				replay_played = true
			else:
				var won_after_replay := check_win()
				if won_after_replay:
					return
				reset_game_board()
				replay_played = true

		var turn_limit := _get_turn_dart_limit()
		if num_shots < turn_limit:
			var player_dart = spawn_dart(true)
			player_dart.on_hit_board.connect(func(score):
				var move_arr = [0, player_dart.position.x, player_dart.position.y]
				move_arr.append_array(score)
				my_moves.append(move_arr)
				dec_score(player, score[0])

				if get_score(player) < 0:
					bust_label.visible = true
					var old_score = mode
					if replay != null and not replay.is_empty():
						var score_idx = 0 if player == 1 else 1
						old_score = parse_replay(replay)["post_state"][score_idx]
					await get_tree().create_timer(1).timeout
					bust_label.visible = false
					set_score(player, old_score)
					num_shots = _get_turn_dart_limit()

				if get_score(player) == 0:
					num_shots = _get_turn_dart_limit()

				_process_game_state()
			)
		else:
			send_replay()
	else:
		if replay != null and not replay.is_empty():
			var parsed := parse_replay(replay)
			var post_state = parsed["post_state"]
			set_score(1, post_state[0])
			set_score(2, post_state[1])

			var won_waiting := check_win()
			if won_waiting:
				return

		if not game_over and not spectator_mode:
			start_waiting_animation()
		else:
			stop_waiting_animation()

func _show_result(result_code: int) -> void:
	match_result = result_code
	game_over = result_code != RESULT_NONE

	if result_code == RESULT_NONE:
		return

	is_my_turn = false
	stop_waiting_animation()

	if not is_instance_valid(winner_label):
		return

	winner_label.visible = true

	match result_code:
		RESULT_WIN:
			winner_label.text = "YOU WIN!"
			winner_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			if is_instance_valid(player_avatar_display):
				GameUtils._show_win_burst(player_avatar_display)

		RESULT_LOSS:
			winner_label.text = "YOU LOSE"
			winner_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			if is_instance_valid(opp_avatar_display):
				GameUtils._show_win_burst(opp_avatar_display)

		RESULT_DRAW:
			winner_label.text = "DRAW!"
			winner_label.add_theme_color_override("font_color", Color(1, 1, 1))
			
func check_win() -> bool: 
	if redemption_active:
		return false

	var my_score := get_score(player)
	var opp_score := get_score(1 if player == 2 else 2)

	if replay != null and not replay.is_empty():
		var parsed := parse_replay(replay)
		if parsed.has("pre_state") and parsed.has("post_state"):
			var pre_state: Array = parsed["pre_state"]
			var post_state: Array = parsed["post_state"]
			if pre_state.size() >= 2 and post_state.size() >= 2:
				var p1_pre := int(pre_state[0])
				var p1_post := int(post_state[0])
				var p2_post := int(post_state[1])

				if p1_pre > 0 and p1_post == 0 and p2_post > 0:
					return false

				if p1_pre == 0 and p1_post == 0:
					if p2_post == 0:
						_show_result(RESULT_DRAW)
					elif player == 1:
						_show_result(RESULT_WIN)
					else:
						_show_result(RESULT_LOSS)
					return true

	if my_score == 0:
		_show_result(RESULT_WIN)
		return true

	if opp_score == 0:
		_show_result(RESULT_LOSS)
		return true

	return false

func send_replay():
	var moves_str = ""
	for move in my_moves:
		moves_str += "move:" + str(int(move[0])) + "," + str("%0.6f" % move[1]) + "," + str("%0.6f" % move[2]) + "," + str(int(move[3])) + "," + str(int(move[4])) + "," + str(int(move[5])) + "|"

	var replay_out: String = "state:" + str(p1_pre_score) + "," + str(p2_pre_score) + "|" + moves_str + "state:" + str(p1_score) + "," + str(p2_score)

	var result = {
		"replay": replay_out
	}

	var p1_out := p1_score
	var p2_out := p2_score
	var turn_ended_game := false
	match_result = RESULT_NONE

	if redemption_active and player == 2:
		if p2_out == 0:
			_show_result(RESULT_DRAW)
		else:
			_show_result(RESULT_LOSS)
		turn_ended_game = true
	elif player == 2 and p2_out == 0:
		_show_result(RESULT_WIN)
		turn_ended_game = true
	elif player == 1 and p1_out == 0:
		turn_ended_game = false
	else:
		turn_ended_game = false

	if turn_ended_game:
		var winner_value := ""
		match match_result:
			RESULT_WIN:
				winner_value = "1"
			RESULT_LOSS:
				winner_value = "-1"
			RESULT_DRAW:
				winner_value = "0"

		if winner_value != "":
			result["winner"] = my_uuid + "|" + winner_value
	else:
		is_my_turn = false
		play_sent_animation()

	var avatar_key := ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		result[avatar_key] = player_avatar_display.get_avatar_data_string()

	var game_data = JSON.stringify(result)
	send_game_data(game_data)
	
func play_replay(replay_str: String):
	var parsed = parse_replay(replay_str)
	var other_player = 1 if player == 2 else 2

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
		if get_score(other_player) < 0:
			bust_label.visible = true
			await get_tree().create_timer(1).timeout
			bust_label.visible = false

	set_score(1, parsed["post_state"][0])
	set_score(2, parsed["post_state"][1])

	if player == 1:
		p2_pre_score = parsed["post_state"][1]
	elif player == 2:
		p1_pre_score = parsed["post_state"][0]

func parse_replay(replay_str: String) -> Dictionary:
	var result = {"moves": []}
	for elem in replay_str.split("|"):
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

func set_score(target_player: int, score: int) -> void:
	if target_player == 1:
		p1_score = score
	elif target_player == 2:
		p2_score = score
	else:
		return

	var score_text := str(score)

	if self.player == target_player:
		if is_instance_valid(you_score_label):
			you_score_label.text = score_text
		else:
			print("WARN: you_score_label is null; cannot set score to ", score_text)
	else:
		if is_instance_valid(opp_score_label):
			opp_score_label.text = score_text
		else:
			print("WARN: opp_score_label is null; cannot set score to ", score_text)
			
func dec_score(target_player: int, score: int):
	if target_player == 1:
		set_score(1, p1_score - score)
	elif target_player == 2:
		set_score(2, p2_score - score)

func get_score(target_player: int) -> int:
	if target_player == 1:
		return p1_score
	elif target_player == 2:
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
func _unhandled_input(event: InputEvent) -> void:
	if _settings_open or spectator_mode:
		return
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
const rect_min_y = 100.0
const rect_max_y = 550.0
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

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		print("Warning: sent_label is not valid for play_sent_animation.")
		return

	if sent_tween and sent_tween.is_running():
		sent_tween.kill()

	sent_tween = create_tween().set_parallel(false)

	sent_label.text = "Sent"
	sent_label.visible = true
	sent_label.modulate.a = 0.0
	sent_label.scale = Vector2.ONE
	sent_label.pivot_offset = sent_label.get_size() / 2.0

	sent_tween.tween_property(sent_label, "modulate:a", 1.0, 0.3)
	sent_tween.tween_interval(0.6)
	sent_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.text = "Sent ✔"
	)
	sent_tween.tween_interval(2.0)
	sent_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)
	sent_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0

		if not game_over and not spectator_mode and not is_my_turn:
			start_waiting_animation()
		else:
			stop_waiting_animation()
	)
