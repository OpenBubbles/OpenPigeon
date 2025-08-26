extends Control

@onready var paper: PanelContainer = %Paper
@onready var grid: Control = %DotsGrid
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var rules_button: Button     = %RulesButton
@onready var settings_button: Button = %SettingsButton
@onready var send_button: Button = %SendButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: Control = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var background: ColorRect = %Background
@onready var win_loss_label: Label = %WinLossLabel
@onready var player_score_label: Label = %PlayerScore
@onready var opp_score_label: Label = %OppScore
@onready var player_color_icon: TextureRect = %PlayerColor
@onready var opp_color_icon: TextureRect = %OppColor
@onready var player_marker: TextureRect = %PlayerMarker
@onready var opp_marker: TextureRect = %OppMarker
@onready var you_label: Label = %YouLabel


const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const RULES_POPUP_SCENE = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")

var sent_tween: Tween
var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"

var has_connected: bool = false
var _turn_steps: Array = []
var game_settings_category: String = ""
var player: int = 1
var turn_owner: int = 1
var winner_id: String = "-1"
var is_your_turn: bool = false
var is_my_turn: bool = false : set = _set_is_my_turn
var spectator_mode: bool = false
var pre_board_str: String = ""
var post_board_str_from_opponent: String = ""
var opponent_post_lines: Array = []
var opponent_post_squares: Array = []
var game_ended = false
var game_over = false
var win_loss_state = ""
var my_score
var opp_score
var my_id: String

var prev_lines_cache: Array = []
var last_replay_sent: String = ""

var send_button_home: Vector2 = Vector2.ZERO

@export var board_size: int = 4 : set = set_board_size # 4, 5, or 6
var blue_marker_tex: Texture2D = preload("res://dots/blue_marker.png")
var red_marker_tex: Texture2D = preload("res://dots/red_marker.png")

func _ready() -> void:
	var sb := StyleBoxFlat.new()
	var is_dark = bool(SettingsManager.get_setting("global", "dark_mode", false))
	print("Dark Mode: ", is_dark)
	_apply_bg_for_dark(is_dark)
	sb.bg_color = Color(1, 1, 1, 1)
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 16
	%Paper.add_theme_stylebox_override("panel", sb)
	set_board_size(board_size)
	resized.connect(_on_resized)
	_on_resized()
	if is_instance_valid(grid):
		grid.connect("turn_changed", Callable(self, "_on_turn"))
		grid.connect("score_changed", Callable(self, "_on_score"))
		grid.connect("game_over", Callable(self, "_on_game_over"))
		if grid.has_signal("line_committed_bl"):
			grid.connect("line_committed_bl", Callable(self, "_on_line_committed_bl"))
		if grid.has_signal("square_completed_bl"):
			grid.connect("square_completed_bl", Callable(self, "_on_square_completed_bl"))
		if grid.has_signal("temp_line_changed"):
			grid.connect("temp_line_changed", Callable(self, "_on_temp_line_changed"))
			print("[Grid] connected temp_line_changed")
		else:
			push_warning("[Grid] temp_line_changed signal missing")

	if is_instance_valid(rules_button):
		rules_button.pressed.connect(on_rules_button_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	if is_instance_valid(send_button):
		send_button.visible = false
		send_button.modulate.a = 0.0
		send_button.scale = Vector2(1.0, 1.0)
		send_button.pressed.connect(_on_send_pressed)
		print("[SendButton] ready; visible=", send_button.visible, " a=", send_button.modulate.a)
	else:
		push_warning("No %SendButton in scene")

	_apply_player_color_icons()
	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin: 
		print("AppPlugin Available")
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
	else:
		print("[DEV] Editor hint active, loading sample game data")
		var dev_data = '{"isYourTurn": true,"size": "4","player": "2","replay": "board:1,0,2,0,3#2,0,1,0,2#1,0,0,0,1#2,2,1,2,2#1,3,0,3,1#2,2,0,2,1#1,1,1,1,2#2,1,0,1,1#1,3,2,3,3#2,1,2,1,3#1,3,1,3,2#2,2,2,2,3#1,1,0,2,0|line:2,1,1,2,1|square:2,1,0|line:2,1,2,2,2|square:2,1,1|line:2,1,3,2,3|square:2,1,2|line:2,2,0,3,0|board:1,0,2,0,3#2,0,1,0,2#1,0,0,0,1#2,2,1,2,2#1,3,0,3,1#2,2,0,2,1#1,1,1,1,2#2,1,0,1,1#1,3,2,3,3#2,1,2,1,3#1,3,1,3,2#2,2,2,2,3#1,1,0,2,0
		2,1,1,2,1#2,1,2,2,2#2,1,3,2,3#2,2,0,3,0#2,1,0#2,1,1#2,1,2","sender":"7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX","version": "5","tver": "5","ios": "18.5","id": "ziadBSjDYgc4ruev","player2": "7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX"}'
		#var dev_data = '{"isYourTurn": true,"size": "6","player": "2","sender":"7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX","version": "5","tver": "5","ios": "18.5","id": "ziadBSjDYgc4ruev","player2": "7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX"}'
		_set_game_data(dev_data)

func _set_game_data(raw_text: String) -> void:
	var res: Dictionary = JSON.parse_string(raw_text)
	if typeof(res) != TYPE_DICTIONARY:
		return
	print("RAW INCOMING DATA: ", res)
	my_id = res.get("myPlayerId", "")
	var p1_id: String = res.get("player1", "")
	var p2_id: String = res.get("player2", "")
	var opponent_avatar_key = ""

	turn_owner = clamp(int(res.get("player", 1)), 1, 2)
	is_your_turn = bool(res.get("isYourTurn", false))

	if my_id != "" and p1_id != "" and p2_id != "":
		player = (1 if my_id == p1_id else (2 if my_id == p2_id else 1))
	else:
		player = (3 - turn_owner) if is_your_turn else turn_owner
		
	if player == 1:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"
		
	if opponent_avatar_key != "" and res.has(opponent_avatar_key):
		var avatar_string = res[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	_apply_player_color_icons()
	is_my_turn = is_your_turn

	board_size = clamp(int(res.get("size", board_size)), 4, 6)
	if is_instance_valid(grid) and grid.has_method("set_grid"):
		grid.call("set_grid", board_size)

	var replay_str: String = String(res.get("replay", ""))
	await _load_pre_state_and_replay(replay_str)

	_apply_turn_state()
	
	game_ended = await check_win()
	if game_ended:
		stop_waiting_animation()
		game_over = true
	if not is_my_turn:
		start_waiting_animation()

func _load_pre_state_and_replay(replay_str: String) -> void:
	var parsed := _parse_replay_dnb(replay_str)
	var pre_lines: Array = parsed.get("pre_lines", [])
	var pre_squares: Array = parsed.get("pre_squares", [])
	var moves: Array = parsed.get("moves", [])

	pre_board_str = parsed.get("pre_board_str", "")
	post_board_str_from_opponent = parsed.get("post_board_str", "")
	opponent_post_lines = parsed.get("post_lines", [])
	opponent_post_squares = parsed.get("post_squares", [])

	if is_instance_valid(grid) and grid.has_method("load_lines_and_squares_state"):
		grid.call("load_lines_and_squares_state", pre_lines, pre_squares)
	if not moves.is_empty() and is_instance_valid(grid) and grid.has_method("replay_line_move"):
		for move in moves:
			await grid.call("replay_line_move", move)
			await get_tree().create_timer(0.7).timeout

	prev_lines_cache = _get_committed_lines()
	if is_instance_valid(player_score_label) and is_instance_valid(opp_score_label):
		if player_score_label.text == "" and opp_score_label.text == "":
			player_score_label.text = "0"
			opp_score_label.text = "0"

func _set_is_my_turn(v: bool) -> void:
	is_my_turn = v
	if v:
		_turn_steps.clear()
	_apply_turn_state()
	
func _apply_turn_state() -> void:
	if is_instance_valid(grid):
		var grid_player := player if is_my_turn else (3 - player)
		grid.set("player", grid_player)
		grid.call_deferred("set_input_enabled", is_my_turn and not spectator_mode)
	if not spectator_mode:
		if is_my_turn: stop_waiting_animation()

func _parse_replay_dnb(raw: String) -> Dictionary:
	var out := {
		"pre_board_str": "", "post_board_str": "", "pre_lines": [], "pre_squares": [], 
		"moves": [], "post_lines": [], "post_squares": []
	}
	if raw.strip_edges() == "": return out
	var parts := raw.split("|")
	var is_first_board := true
	for p in parts:
		if p.begins_with("board:"):
			var b := p.substr(6)
			var br := _parse_board_string(b)
			if is_first_board:
				out["pre_board_str"] = b
				out["pre_lines"] = br["lines"]
				out["pre_squares"] = br["squares"]
				is_first_board = false
			else:
				out["post_board_str"] = b
				out["post_lines"] = br["lines"]
				out["post_squares"] = br["squares"]
		elif p.begins_with("line:"):
			var mv := _csv_to_ints(p.substr(5))
			if mv.size() >= 5: out["moves"].append([mv[0], mv[1], mv[2], mv[3], mv[4]])
	return out

func _parse_board_string(b: String) -> Dictionary:
	var lines: Array = []; var squares: Array = []
	for chunk in b.split("#"):
		var s := chunk.strip_edges()
		if s == "": continue
		var nums := _csv_to_ints(s)
		if nums.size() == 5:
			lines.append([nums[0], nums[1], nums[2], nums[3], nums[4]])
		elif nums.size() == 3:
			squares.append([nums[0], nums[1], nums[2]])
	return { "lines": lines, "squares": squares }

func _csv_to_ints(s: String) -> Array:
	var out: Array = []
	for t in s.split(","):
		var tt := t.strip_edges()
		if tt != "":
			out.append(int(tt))
	return out
func _parse_avatar_string(data_string: String) -> Dictionary:
	var hair_map := ["Spiky", "Long", "Bun", "Bald"]
	var body_map := ["Default", "Smiling", "Winking", "Surprised", "Frowning", "Tongue Out", "Cute"]
	var eyes_map := ["Open", "Closed", "Winking"]
	var mouth_map := ["Plain", "Smile", "Frown"]
	var clothing_map := ["T-Shirt", "Sweater", "Tank Top"]
	var backdrop_map := ["Plain", "Pattern 1", "Pattern 2", "Pattern 3", "Pattern 4", "Pattern 5", "Pattern 6", "Pattern 7", "Pattern 8", "Pattern 9"]

	var data: Dictionary = {}
	var parts := data_string.split("|")
	for part in parts:
		var key_value := part.split(",")
		if key_value.size() < 2:
			continue
		var key := key_value[0]
		var values := key_value.slice(1)
		match key:
			"hair":
				data["hair_style"] = hair_map[int(values[0])]
			"body":
				data["body_style"] = body_map[int(values[0])]
			"eyes":
				data["eyes_style"] = eyes_map[int(values[0])]
			"mouth":
				data["mouth_style"] = mouth_map[int(values[0])]
			"clothes":
				data["clothing_style"] = clothing_map[int(values[0])]
			"backdrop":
				var backdrop_index: int = int(values[0])
				if backdrop_index >= 0 and backdrop_index < backdrop_map.size():
					data["bg_style"] = backdrop_map[backdrop_index]
			"bg_color", "body_color", "hair_color", "clothes_color":
				if values.size() >= 3:
					var color_key := key.replace("_color", "") + "_color"
					data[color_key] = Color(float(values[0]), float(values[1]), float(values[2]))
	return data

func _get_grid_colors() -> Array[Color]:
	var cols: Array[Color] = []
	if is_instance_valid(grid) and grid.has_method("get"):
		var got: Variant = grid.get("p_colors")
		if typeof(got) == TYPE_ARRAY:
			var tmp: Array[Color] = []
			for v in (got as Array):
				if v is Color:
					tmp.append(v)
			cols = tmp
	if cols.size() < 2:
		cols = [Color(0.20, 0.55, 0.81), Color(0.92, 0.13, 0.43)]
	return cols

func _apply_player_color_icons() -> void:
	var cols := _get_grid_colors()
	var my_col: Color = cols[player - 1]
	var opp_col: Color = cols[2 - player]

	if is_instance_valid(player_color_icon):
		player_color_icon.modulate = my_col
	if is_instance_valid(opp_color_icon):
		opp_color_icon.modulate = opp_col

	if is_instance_valid(player_score_label):
		player_score_label.add_theme_color_override("font_color", my_col)
	if is_instance_valid(opp_score_label):
		opp_score_label.add_theme_color_override("font_color", opp_col)

	if is_instance_valid(player_marker):
		player_marker.texture = (blue_marker_tex if player == 1 else red_marker_tex)
	if is_instance_valid(opp_marker):
		opp_marker.texture = (red_marker_tex if player == 1 else blue_marker_tex)

func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		print("Is Dark: ", is_dark)
		background.color = Color("#261a19") if is_dark else Color("#947972")

func _on_resized() -> void:
	var s := get_viewport_rect().size
	var side: float = min(s.x, s.y) * 0.7
	paper.custom_minimum_size = Vector2(side, side)

func set_board_size(n: int) -> void:
	board_size = clamp(n, 4, 6)
	if is_instance_valid(grid) and grid.has_method("set_grid"):
		grid.call("set_grid", board_size)

func _on_turn() -> void:
	pass

func _on_score(p0: int, p1: int) -> void:
	my_score = p0 if player == 1 else p1
	opp_score = p1 if player == 1 else p0
	if is_instance_valid(player_score_label):
		player_score_label.text = str(my_score)
	if is_instance_valid(opp_score_label):
		opp_score_label.text = str(opp_score)
	
	game_ended = await check_win()
	if game_ended:
		stop_waiting_animation()
		game_over = true
		send_game()

func _on_game_over() -> void:
	pass

func _on_temp_line_changed(has_line: bool) -> void:
	if not is_instance_valid(send_button):
		print("[SendButton] missing node")
		return

	var should_show := has_line
	print("[SendButton] temp_line_changed has_line=", has_line, " -> should_show=", should_show)

	send_button.set_as_top_level(true)

	if not send_button.has_meta("home_pos"):
		send_button.set_meta("home_pos", send_button.global_position)
		print("[SendButton] home cached: ", send_button.get_meta("home_pos"))

	if send_button.has_meta("sb_tween"):
		var old_tw: Variant = send_button.get_meta("sb_tween")
		if old_tw is Tween and (old_tw as Tween).is_running():
			(old_tw as Tween).kill()

	var home: Vector2 = send_button.get_meta("home_pos")
	var vp := get_viewport_rect()
	var off_y: float = vp.size.y + send_button.size.y + 30.0
	var start_pos := Vector2(home.x, off_y)
	var is_send_visible = send_button.visible

	if should_show:
		if not is_send_visible:
			send_button.global_position = start_pos
			send_button.visible = true
			send_button.modulate.a = 1.0
		elif send_button.global_position.y > vp.size.y:
			send_button.global_position = start_pos

		var t_in := create_tween()
		send_button.set_meta("sb_tween", t_in)
		print("[SendButton] fly-in from ", send_button.global_position, " to ", home)
		t_in.tween_property(send_button, "global_position", home, 0.35)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		if is_send_visible:
			var end_pos := Vector2(home.x, off_y)
			print("[SendButton] fly-out from ", send_button.global_position, " to ", end_pos)
			var t_out := create_tween()
			send_button.set_meta("sb_tween", t_out)
			t_out.tween_property(send_button, "global_position", end_pos, 0.25)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t_out.tween_callback(func():
				if is_instance_valid(send_button):
					print("[SendButton] hide complete; visible=false")
					send_button.visible = false
			)
		
func _on_send_pressed() -> void:
	print("[SendButton] pressed -> committing temp line and sending")
	var committed: bool = false
	if is_instance_valid(grid) and grid.has_method("commit_temp_line_now"):
		committed = bool(grid.call("commit_temp_line_now"))
	print("[Send] commit_temp_line_now -> ", committed)

	is_my_turn = false
	if is_instance_valid(grid) and grid.has_method("set_input_enabled"):
		grid.call("set_input_enabled", false)

	if is_instance_valid(send_button):
		send_button.visible = false
	
	if has_method("send_game"):
		call_deferred("send_game")
		
func send_game() -> void:
	print("[Send] send_game() called")
	await get_tree().process_frame

	if _turn_steps.is_empty():
		print("[Send] No committed steps this turn; abort")
		return

	var new_lines: Array = []
	var new_squares: Array = []
	for step in _turn_steps:
		if step.has("line"):
			new_lines.append(step["line"])
		if step.has("squares"):
			new_squares.append_array(step["squares"])

	var final_lines: Array = opponent_post_lines.duplicate(true)
	final_lines.append_array(new_lines)

	var final_squares: Array = opponent_post_squares.duplicate(true)
	final_squares.append_array(new_squares)

	var final_pre_board_str: String = post_board_str_from_opponent if post_board_str_from_opponent != "" else pre_board_str

	var final_post_board_str: String = _compose_board_string(final_lines, final_squares)

	var parts: Array[String] = []
	parts.append("board:" + final_pre_board_str)
	for step2 in _turn_steps:
		var mv: Array = step2["line"]
		parts.append("line:%d,%d,%d,%d,%d" % [int(mv[0]), int(mv[1]), int(mv[2]), int(mv[3]), int(mv[4])])
		
		for sq in (step2["squares"] as Array):
			parts.append("square:%d,%d,%d" % [int(sq[0]), int(sq[1]), int(sq[2])])
	parts.append("board:" + final_post_board_str)

	var replay: String = String("|").join(parts)
	last_replay_sent = replay

	var payload: Dictionary = { "replay": replay }
	var avatar_key := ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	game_ended = await check_win()
	if game_ended:
		print("Check Win 773 my_player: ", my_id, " win_loss_state: ", win_loss_state)
		if win_loss_state != "":
			payload["winner"] = my_id + "|" + win_loss_state
	print("[Send] PAYLOAD: ", payload)
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(JSON.stringify(payload))
	else:
		print("AppPlugin is null. Cannot send game data.")

	is_my_turn = false
	if is_instance_valid(grid) and grid.has_method("clear_temp_line"):
		grid.call("clear_temp_line")
	if is_instance_valid(send_button):
		send_button.visible = false
	if not game_over:
		play_sent_animation()

	prev_lines_cache = final_lines
	_turn_steps.clear()
	
func _on_line_committed_bl(p: int, x1: int, y1: int, x2: int, y2: int) -> void:
	var mv := [p, x1, y1, x2, y2]
	for step in _turn_steps:
		if step.has("line") and step["line"] == mv:
			return
	_turn_steps.append({ "line": mv, "squares": [] })

func _on_square_completed_bl(p: int, x_bl: int, y_bl: int) -> void:
	if _turn_steps.size() > 0:
		_turn_steps[_turn_steps.size() - 1]["squares"].append([p, x_bl, y_bl])

func _find_new_moves(current_lines: Array, prev_lines: Array) -> Array:
	var new_moves: Array = []
	var prev_set := _lines_to_set(prev_lines)
	
	for l in current_lines:
		var k := str(l[0]) + ":" + str(l[1]) + "," + str(l[2]) + "," + str(l[3]) + "," + str(l[4])
		if not prev_set.has(k):
			new_moves.append([int(l[0]), int(l[1]), int(l[2]), int(l[3]), int(l[4])])
			
	return new_moves

func _lines_to_set(lines: Array) -> Dictionary:
	var d: Dictionary = {}
	for l in lines:
		if typeof(l) == TYPE_ARRAY and (l as Array).size() >= 5:
			var k := str(l[0]) + ":" + str(l[1]) + "," + str(l[2]) + "," + str(l[3]) + "," + str(l[4])
			d[k] = true
	return d

func _compose_move_string(move: Array) -> String:
	var p := int(move[0]); var x1 := int(move[1]); var y1 := int(move[2]); var x2 := int(move[3]); var y2 := int(move[4])
	return str(p) + "," + str(x1) + "," + str(y1) + "," + str(x2) + "," + str(y2)
	
func _get_committed_lines() -> Array:
	if is_instance_valid(grid) and grid.has_method("get_all_committed_lines"):
		var lines: Variant = grid.call("get_all_committed_lines")
		if typeof(lines) == TYPE_ARRAY:
			return (lines as Array)
	return prev_lines_cache.duplicate(true)

func _compose_board_string(lines: Array, squares: Array = []) -> String:
	var parts: Array[String] = []

	var _ser = func(a: Array) -> String:
		if a.size() == 5:
			return "%d,%d,%d,%d,%d" % [int(a[0]), int(a[1]), int(a[2]), int(a[3]), int(a[4])]
		elif a.size() == 3:
			return "%d,%d,%d" % [int(a[0]), int(a[1]), int(a[2])]
		return ""

	for l in lines:
		if typeof(l) == TYPE_ARRAY and (l as Array).size() == 5:
			var k: String = _ser.call(l)
			if k != "":
				parts.append(k)
	for s in squares:
		if typeof(s) == TYPE_ARRAY and (s as Array).size() == 3:
			var k2: String = _ser.call(s)
			if k2 != "":
				parts.append(k2)
	
	return String("#").join(parts)

func on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return

	rules_button.pivot_offset = rules_button.size / 2.0
	var tween := create_tween()
	tween.tween_property(rules_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(rules_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var popup := RULES_POPUP_SCENE.instantiate()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)
 
	var close_btn := popup.find_child("CloseButton", true, false)
	if close_btn:
		close_btn.pressed.connect(func():
			dim.queue_free()
			popup.queue_free()
		)

	var title_label := popup.find_child("Title", true, false) as Label
	if title_label:
		title_label.text = "How to Play Dots & Boxes"

	var rules_label := popup.find_child("RulesLabel", true, false) as RichTextLabel
	if rules_label:
		rules_label.bbcode_enabled = true
		rules_label.visible = true
		rules_label.fit_content = true
		rules_label.scroll_active = false
		rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rules_label.text = _get_rules_text()

	popup.set_as_top_level(true)
	popup.visible = true
	await get_tree().process_frame

	var viewport_size := get_viewport_rect().size
	var desired_width := viewport_size.x * 0.9
	var desired_height: float = popup.get_combined_minimum_size().y
	popup.size = Vector2(desired_width, desired_height)
	popup.set_pivot_offset(popup.size / 2)
	popup.position = (viewport_size / 2) - (popup.size / 2)
	popup.scale = Vector2.ZERO

	var popup_tween := create_tween()
	popup_tween.tween_property(popup, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	popup.grab_focus()

func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Dots & Boxes[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
• Take turns drawing single lines between adjacent dots.
• Complete the 4th side of a 1×1 box to claim it and score 1 point.
• The player with the most boxes when no lines remain wins.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• On your turn, draw exactly one horizontal or vertical line between two neighboring dots.
• If your line completes a box, that box is marked with an [b]X[/b] in your color and you immediately take another turn.
• If your line does not complete a box, play passes to your opponent.
• Boxes can be claimed in chains: if completing one box lets you complete another, you continue until you draw a line that doesn’t finish a box.
[/font_size]

[font_size={24px}][b]End of Game[/b][/font_size]
[font_size={18px}]
• The game ends when every possible line has been drawn.
• Each claimed box is worth 1 point. Higher total wins.
• Ties are possible.
[/font_size]
"""

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
	
func check_win() -> bool:
	print("--- CHECKING WIN CONDITION ---")
	if my_score + opp_score < (board_size - 1) * (board_size - 1):
		print("-> RESULT: Game Continues. More than 2 colors remain or combined score is too low.")
		return false
	print("-> WIN CONDITION MET: 2 or fewer colors remain.")
	
	var was_over = game_over
	game_over = true
	if not was_over:
		print("-> Evaluating final scores. My score: %d, Opponent's score: %d" % [my_score, opp_score])
		if my_score > opp_score:
			print("-> FINAL TALLY: YOU WIN!")
			_show_win_burst(player_avatar_display)
			if not spectator_mode:
				win_loss_label.text = "YOU WIN!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			else:
				win_loss_label.text = "Player 1 Wins!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			win_loss_state = "1"
		elif opp_score > my_score:
			print("-> FINAL TALLY: YOU LOSE")
			_show_win_burst(opp_avatar_display)
			win_loss_label.text = "YOU LOSE"
			if not spectator_mode:
				win_loss_label.text = "YOU LOSE"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			else:
				win_loss_label.text = "Player 2 Wins!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			win_loss_state = "-1"
		else:
			print("-> FINAL TALLY: TIE!")
			win_loss_label.text = "DRAW!"
			win_loss_state = "0"
			win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))

		win_loss_label.visible = true
		await get_tree().process_frame
		win_loss_label.scale = Vector2.ZERO
		win_loss_label.pivot_offset = win_loss_label.size / 2
		
		var tween_in = create_tween()
		tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	else:
		print("-> Game was already marked as over. No new result displayed.")

	return true
	
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

func _on_dot_timer_timeout():
	if not is_instance_valid(waiting_label):
		print("Warning: waiting_label is not valid in _on_dot_timer_timeout.")
		return
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots

func _on_settings_button_pressed() -> void:
	if not is_instance_valid(settings_button):
		return
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
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
	)
	settings_popup_script.settings_theme_selected.connect(_on_theme_changed)
	settings_popup_script.dark_mode_changed.connect(_apply_bg_for_dark)

	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await get_tree().process_frame

	var viewport_size := get_viewport_rect().size
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

func _on_theme_changed(new_theme_name: String) -> void:
	pass

func _load_game_specific_settings() -> void:
	var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	print("Loaded game-specific settings for ", game_settings_category, ": volume=", saved_volume, " debug=", show_debug_info)
