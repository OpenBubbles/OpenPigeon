extends Node3D
class_name DartsGame

const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")

@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var settings_button: Button = %SettingsButton
@onready var winner_label: Label = %WinLossLabel
@onready var waiting_label: Label = %waitingLabel
@onready var bust_label: Label = %BustLabel
@onready var sent_label: Label = %SentLabel
@onready var you_score_label: Label = %PlayerScoreLabel
@onready var opp_score_label: Label = %OpponentScoreLabel
@onready var waiting_blur: ColorRect = %WaitBlur
@onready var main_overlay: Control = %MainOverlay
@onready var dot_timer: Timer = %DotTimer
@onready var spectator_label: Label = %SpecLabel

var main_dart: Dart

var darts: Array[Dart] = []
var current_dart: Dart
var num_shots: int = 0
var replay_played: bool = false
var game_settings_category: String = ""
var _settings_open: bool = false
var sent_tween: Tween
var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"

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
var spectator_mode: bool = false
var redemption_active: bool = false
var redemption_darts_allowed: int = 0

func _ready():
	main_dart = get_node("dart")
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		if not has_connected:
			print("App plugin is available")
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
	else:
		print("App plugin is not available")
		_set_game_data('{ "isYourTurn": true, "player": "1", "replay": "state:101,10|move:0,0.103483,0.142005,2,2,0|move:0,-0.343160,0.606544,9,9,0|move:0,0.128320,0.867287,0,0,0|state:90,10", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player1": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player2": "", "id": "lfH52rteC7dc 4J7\n", "ios": "16.3.1", "num": "2", "game": "darts", "mode": "101", "tver": "5", "build": "56", "version": "0" }')
		
		
var my_player
func _set_game_data(new_replay: String):
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: " + str(parsed))
	
	is_my_turn = parsed["isYourTurn"]
	player = int(parsed["player"])
	replay = parsed["replay"] if "replay" in parsed else ""
	mode = int(parsed["mode"])
	var opponent_avatar_key = ""
	my_player = parsed.get("myPlayerId", null)
	var p1_id: String = parsed.get("player1", "")
	var p2_id: String = parsed.get("player2", "")
	spectator_mode = my_player != "" and p1_id != "" and p2_id != "" and my_player != p1_id and my_player != p2_id
	if is_instance_valid(spectator_label):
		spectator_label.visible = spectator_mode
	if is_my_turn and not spectator_mode:
		player = 2 if player == 1 else 1
	elif spectator_mode: player = 1
		
	if player == 1 or spectator_mode:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"
	
	if opponent_avatar_key != "" and parsed.has(opponent_avatar_key):
		var avatar_string = parsed[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
	if spectator_mode:
		var p1_data = _parse_avatar_string(parsed["avatar1"])
		if is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", p1_data)
	
	print("YOU ARE PLAYER: " + str(player))
	
	if replay.is_empty():
		p1_pre_score = mode
		p2_pre_score = mode
		set_score(1, mode)
		set_score(2, mode)
	redemption_active = false
	redemption_darts_allowed = 0
	replay_played = false
	reset_game_board()
	_process_game_state()
	
func _get_turn_dart_limit() -> int:
	if redemption_active:
		return redemption_darts_allowed
	return 3

func _maybe_start_redemption_from_replay() -> bool:
	if spectator_mode:
		return false
	if player != 2:
		return false
	if replay == null or replay.is_empty():
		return false

	var parsed := parse_replay(replay)
	if not parsed.has("pre_state") or not parsed.has("post_state"):
		return false

	var pre_state: Array = parsed["pre_state"]
	var post_state: Array = parsed["post_state"]

	if pre_state.size() < 2 or post_state.size() < 2:
		return false

	var p1_was_not_zero: bool = int(pre_state[0]) != 0
	var p1_is_zero_now: bool = int(post_state[0]) == 0
	if not (p1_was_not_zero and p1_is_zero_now):
		return false

	var darts_used: int = 0
	if parsed.has("moves"):
		darts_used = (parsed["moves"] as Array).size()

	if darts_used <= 0:
		return false

	redemption_active = true
	redemption_darts_allowed = darts_used
	print("REDEMPTION ENABLED: player 2 gets ", redemption_darts_allowed, " dart(s)")
	return true

func _process_game_state():
	if is_my_turn:
		stop_waiting_animation()
		if replay != null and not replay.is_empty() and not replay_played:
			await play_replay(replay)

			if _maybe_start_redemption_from_replay():
				reset_game_board()
				replay_played = true
			else:
				if check_win():
					return
				reset_game_board()
				replay_played = true
			
		if num_shots < _get_turn_dart_limit():
			var player_dart = spawn_dart(true)
			print("NEW DART: " + str(player_dart))
			player_dart.on_hit_board.connect(func(score):
				print("SCORED: " + str(score))
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
				print(my_moves)
				_process_game_state()
			)
		else:
			send_replay()
			if check_win():
				return
	else:
		if replay != null and not replay.is_empty():
			var post_state = parse_replay(replay)["post_state"]
			set_score(1, post_state[0])
			set_score(2, post_state[1])
			if check_win():
				return
				
		start_waiting_animation()

var didIWin = false
func check_win() -> bool:
	# Special redemption rule:
	# If player 1 has reached 0 and the local player is player 2, allow
	# player 2 one answering turn with the same number of darts player 1 used.
	if redemption_active and player == 2 and get_score(1) == 0:
		if get_score(2) == 0:
			redemption_active = false
			redemption_darts_allowed = 0
			winner_label.text = "YOU WIN!"
			winner_label.visible = true
			winner_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			if is_instance_valid(player_avatar_display):
				_show_win_burst(player_avatar_display)
			didIWin = true
			return true

		if my_moves.size() < redemption_darts_allowed:
			print("check_win: redemption still in progress ", my_moves.size(), "/", redemption_darts_allowed)
			return false

		redemption_active = false
		redemption_darts_allowed = 0
		winner_label.text = "YOU LOSE"
		winner_label.visible = true
		winner_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
		if is_instance_valid(opp_avatar_display):
			_show_win_burst(opp_avatar_display)
		didIWin = false
		return true

	if get_score(player) == 0:
		winner_label.text = "YOU WIN!"
		winner_label.visible = true
		winner_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		if is_instance_valid(player_avatar_display):
			_show_win_burst(player_avatar_display)
		didIWin = true
		return true
	elif get_score(1 if player == 2 else 2) == 0:
		winner_label.text = "YOU LOSE"
		winner_label.visible = true
		winner_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
		if is_instance_valid(opp_avatar_display):
			_show_win_burst(opp_avatar_display)
		didIWin = false
		return true
	return false
	
func send_replay():
	var moves_str = ""
	for move in my_moves:
		moves_str += "move:" + str(int(move[0])) + "," + str("%0.6f" % move[1]) + "," + str("%0.6f" % move[2]) + "," + str(int(move[3])) + "," + str(int(move[4])) + "," + str(int(move[5])) + "|"
	
	var result = {
		"replay": "state:" + str(p1_pre_score) + "," + str(p2_pre_score) + "|" + moves_str + "state:" + str(p1_score) + "," + str(p2_score)
	}
	
	if check_win():
		result["winner"] = my_player + "|" + ("1" if didIWin else "-1")
	else:
		play_sent_animation()
	var avatar_key := ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		result[avatar_key] = player_avatar_display.get_avatar_data_string()
	var game_data = JSON.stringify(result)
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

func set_score(player: int, score: int) -> void:
	if player == 1:
		p1_score = score
	elif player == 2:
		p2_score = score
	else:
		return

	var score_text := str(score)

	if self.player == player:
		if is_instance_valid(you_score_label):
			you_score_label.text = score_text
		else:
			print("WARN: you_score_label is null; cannot set score to ", score_text)
	else:
		if is_instance_valid(opp_score_label):
			opp_score_label.text = score_text
		else:
			print("WARN: opp_score_label is null; cannot set score to ", score_text)
		
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
			start_waiting_animation()
	)
	
func _on_dot_timer_timeout():
	if not is_instance_valid(waiting_label):
		print("Warning: waiting_label is not valid in _on_dot_timer_timeout.")
		return
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots

func start_waiting_animation():
	if not is_instance_valid(waiting_label) or not is_instance_valid(waiting_blur) or not is_instance_valid(dot_timer):
		print("Warning: Waiting animation nodes are not valid.")
		return
	if spectator_mode:
		return

	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true
	waiting_blur.visible = true

	waiting_label.modulate.a = 0.0
	waiting_blur.modulate.a = 0.0

	var tween_wait_in = create_tween().set_parallel(true)
	tween_wait_in.tween_property(waiting_label, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_property(waiting_blur, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_callback(func():
		dot_timer.start()
	)

func stop_waiting_animation():
	if is_instance_valid(dot_timer):
		dot_timer.stop()
	if is_instance_valid(waiting_label):
		waiting_label.visible = false
		waiting_label.modulate.a = 1.0
	if is_instance_valid(waiting_blur):
		waiting_blur.visible = false
		waiting_blur.modulate.a = 1.0

func _parse_avatar_string(data_string: String) -> Dictionary:
	var hair_map: Array     = AvatarThumbnail.avatar_hair_regions.keys()
	var body_map: Array     = AvatarThumbnail.avatar_fshape_regions.keys()
	var eyes_map: Array     = AvatarThumbnail.avatar_eyes_regions.keys()
	var mouth_map: Array    = AvatarThumbnail.avatar_mouth_regions.keys()
	var clothing_map: Array = AvatarThumbnail.avatar_clothing_regions.keys()
	var backdrop_map: Array = ["Plain"]
	backdrop_map.append_array(AvatarThumbnail.avatar_background_regions.keys())

	var data: Dictionary = {
		"fshape_style":   body_map[0]     if body_map.size()     > 0 else "Default",
		"hair_style":     hair_map[0]     if hair_map.size()     > 0 else "hair1",
		"eyes_style":     eyes_map[0]     if eyes_map.size()     > 0 else "eyes1",
		"mouth_style":    mouth_map[0]    if mouth_map.size()    > 0 else "mouth1",
		"clothing_style": clothing_map[0] if clothing_map.size() > 0 else "clothing1",
		"bg_style":       "Plain",
		"fshape_color":   Color(0.88, 0.67, 0.41),
		"hair_color":     Color(0.17, 0.14, 0.17),
		"clothing_color": Color(0.63, 0.24, 0.24),
		"bg_color":       Color(0.31, 0.36, 0.54),
	}

	if data_string.is_empty():
		return data

	var read_color = func(vals: Array) -> Color:
		if vals.size() >= 3:
			return Color(vals[0].to_float(), vals[1].to_float(), vals[2].to_float())
		return Color.WHITE

	for part in data_string.split("|", false):
		var key_value := part.split(",", false)
		if key_value.size() < 2:
			continue
		var key := key_value[0]

		match key:
			"fshape", "body":
				var i := key_value[1].to_int()
				if i >= 0 and i < body_map.size():
					data["fshape_style"] = String(body_map[i])

			"fshape_color", "body_color":
				data["fshape_color"] = read_color.call(key_value.slice(1))

			"hair":
				var i := key_value[1].to_int()
				if i >= 0 and i < hair_map.size():
					data["hair_style"] = String(hair_map[i])

			"hair_color":
				data["hair_color"] = read_color.call(key_value.slice(1))

			"eyes":
				var i := key_value[1].to_int()
				if i >= 0 and i < eyes_map.size():
					data["eyes_style"] = String(eyes_map[i])

			"mouth":
				var i := key_value[1].to_int()
				if i >= 0 and i < mouth_map.size():
					data["mouth_style"] = String(mouth_map[i])

			"clothes":
				var i := key_value[1].to_int()
				if i >= 0 and i < clothing_map.size():
					data["clothing_style"] = String(clothing_map[i])

			"clothes_color":
				data["clothing_color"] = read_color.call(key_value.slice(1))

			"bg_color":
				data["bg_color"] = read_color.call(key_value.slice(1))

			"backdrop":
				var i := key_value[1].to_int()
				if i >= 0 and i < backdrop_map.size():
					data["bg_style"] = String(backdrop_map[i])
			_:
				pass
	return data
	
func _ensure_avatar_wrapper(avatar: Control) -> Control:
	var parent: Node = avatar.get_parent()
	if parent == null:
		return null

	if parent is Control and not (parent is Container):
		return parent as Control

	var wrapper: Control = Control.new()
	wrapper.name = "%s_Wrap" % avatar.name
	wrapper.size_flags_horizontal = avatar.size_flags_horizontal
	wrapper.size_flags_vertical = avatar.size_flags_vertical
	wrapper.custom_minimum_size = avatar.get_combined_minimum_size()

	var idx: int = avatar.get_index()
	parent.add_child(wrapper)
	parent.move_child(wrapper, idx)

	avatar.reparent(wrapper)
	avatar.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar.offset_left = 0.0
	avatar.offset_top = 0.0
	avatar.offset_right = 0.0
	avatar.offset_bottom = 0.0

	avatar.item_rect_changed.connect(func():
		if is_instance_valid(wrapper):
			wrapper.custom_minimum_size = avatar.get_combined_minimum_size()
	)

	return wrapper

func _show_win_burst(avatar: Control) -> void:
	var wrapper: Control = _ensure_avatar_wrapper(avatar)
	if not is_instance_valid(wrapper):
		return

	var existing: Node = wrapper.get_node_or_null("AvatarWinAnim")
	if existing != null:
		return

	var anim_instance: Control = AvatarWinAnimScene.instantiate() as Control
	anim_instance.name = "AvatarWinAnim"
	wrapper.add_child(anim_instance)

	var avatar_idx: int = avatar.get_index()
	wrapper.move_child(anim_instance, avatar_idx)

	anim_instance.z_as_relative = false
	avatar.z_as_relative = false
	anim_instance.z_index = 0
	avatar.z_index = max(avatar.z_index, 1)

	anim_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	anim_instance.offset_left = -52.0
	anim_instance.offset_right = 52.0
	anim_instance.offset_top = -43.0
	anim_instance.offset_bottom = 43.0

	(anim_instance as Node).call("set_color", Color(1.0, 0.84, 0.0))
	(anim_instance as Node).call("play", 0.05)


func _on_settings_button_pressed() -> void:
	if not is_instance_valid(settings_button):
		return
	if _settings_open:
		return
	_settings_open = true
	settings_button.pivot_offset = settings_button.size / 2.0
	var tween := create_tween()
	tween.tween_property(settings_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(settings_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var popup_instance := SETTINGS_POPUP_SCENE.instantiate()
	var settings_popup_script := popup_instance as SettingsPopup

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup_instance)
	popup_instance.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)

	settings_popup_script.setup_popup(dim)

	#var volume_setting_hbox := HBoxContainer.new()
	#volume_setting_hbox.add_child(Label.new())
	#(volume_setting_hbox.get_child(0) as Label).text = "Game Volume:"
	#(volume_setting_hbox.get_child(0) as Label).set_h_size_flags(Control.SIZE_EXPAND_FILL)
#
	#var volume_slider := HSlider.new()
	#volume_slider.min_value = 0.0
	#volume_slider.max_value = 1.0
	#volume_slider.step = 0.05
	#var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	#volume_slider.value = saved_volume
	#volume_slider.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	#volume_slider.value_changed.connect(func(value):
		#AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))
		#SettingsManager.set_setting(game_settings_category, "master_volume", value)
	#)
	#volume_setting_hbox.add_child(volume_slider)
	#settings_popup_script.add_custom_setting(volume_setting_hbox)
#
	#var toggle_debug_checkbox := CheckBox.new()
	#toggle_debug_checkbox.text = "Show Debug Info"
	#var saved_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	#toggle_debug_checkbox.button_pressed = saved_debug_info
	#toggle_debug_checkbox.pressed.connect(func():
		#SettingsManager.set_setting(game_settings_category, "show_debug_info", toggle_debug_checkbox.button_pressed)
	#)
	#settings_popup_script.add_custom_setting(toggle_debug_checkbox)

	var custom_settings_title := popup_instance.find_child("CustomSettingsTitleLabel", true)
	if custom_settings_title and custom_settings_title is Label and settings_popup_script.custom_settings_container.get_child_count() > 0:
		(custom_settings_title as Label).visible = true
	elif custom_settings_title and custom_settings_title is Label:
		(custom_settings_title as Label).visible = false

	settings_popup_script.closed.connect(func():
		_settings_open = false
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
		if is_instance_valid(dim):
			dim.queue_free()
	)
	settings_popup_script.settings_theme_selected.connect(_on_theme_changed)

	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await get_tree().process_frame

	var viewport_size := get_viewport().get_visible_rect().size
	var desired_width := viewport_size.x * 0.95
	var desired_height: float = popup_instance.get_combined_minimum_size().y
	popup_instance.size = Vector2(desired_width, desired_height)
	popup_instance.position = Vector2((viewport_size.x - desired_width) / 2, viewport_size.y)

	var bottom_offset := 50
	var target_y_position := viewport_size.y - desired_height - bottom_offset
	var target_position := Vector2((viewport_size.x - desired_width) / 2, target_y_position)

	var popup_tween := create_tween()
	popup_tween.tween_property(popup_instance, "position", target_position, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	popup_instance.grab_focus()

func _on_theme_changed(_new_theme_name: String) -> void:
	pass

func _load_game_specific_settings() -> void:
	var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	print("Loaded game-specific settings for ", game_settings_category, ": volume=", saved_volume, " debug=", show_debug_info)
