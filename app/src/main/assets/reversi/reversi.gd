extends Control

@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_count_label = %PlayerCountLabel
@onready var opp_count_label = %OppCountLabel
@onready var grid = %GridContainer
@onready var send_button = %SendButton
@onready var sent_label = %SentLabel
@onready var waiting_label = %WaitForOpponentLabel
@onready var waiting_blur = %WaitBlur
@onready var win_loss_label = %WinLossLabel
@onready var dot_timer = %DotTimer
@onready var replay_button = %ReplayButton
@onready var rules_button = %RulesButton
@onready var settings_button = %SettingsButton
@onready var spec_label = %SpecLabel

const BOARD_SIZE = 8

var board = []
var game_settings_category: String
var player_symbol = ""
var game_over = false
var has_connected: bool = false
var is_your_turn: bool = false
var is_my_turn: bool = false
var spectator_mode: bool = false
var player: int = -1
var avatar_key = 0
var replay_val
var replay_symbol
var replay: String = ""
var replay_played: bool = false
var my_player
var player_val
var my_moves: Array[Array]
var pre_board_data: Array[int] = []
var post_board_data: Array[int] = []
var win_loss_state = ""
var white_score = 0
var black_score = 0
var preview_flips_active = false

const STAR_POINTS = [
Vector2i(2, 2),
Vector2i(2, 6),
Vector2i(5, 2),
Vector2i(5, 6),
]

var temp_piece_active = false
var temp_piece_x = -1
var temp_piece_y = -1

var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
var button_tween: Tween
var sent_tween: Tween
var send_button_target_y_position = -1
const BUTTON_OFFSCREEN_OFFSET = 100
const RULES_POPUP_SCENE = preload("res://reversi/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://settings_popup.tscn")
const STAR_POINT_SCENE = preload("res://reversi/StarPoint.tscn")
const AvatarWinAnimScene := preload("res://avatar_textures/avatar_win_anim.tscn")

func _ready():
	post_board_data.resize(64)
	post_board_data.fill(0)

	setup_board_structure()
	
	call_deferred("place_star_points")

	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("AppPlugin Available")
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
	else:
		_set_game_data('{ "isYourTurn": true, "player": "1", "replay": "board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,0,0,2,0,2,2,2,2,0,0,1,2,1,1,1,1,1,0,0,0,2,2,0,0,0,0,0,0,0,2,0,0,0,0|move:0,3,1|board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,2,2,2,0,0,1,0,2,2,2,2,0,0,1,2,1,1,1,1,1,0,0,0,2,2,0,0,0,0,0,0,0,2,0,0,0,0", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player1": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player2": "f7898779-d537-4b0f-8c51-d604e934e2fb", "id": "lfH52rteC7dc 4J7\n", "ios": "16.3.1", "num": "2", "game": "darts", "mode": "101", "tver": "5", "build": "56", "version": "0" }')
		#_set_game_data('{ "isYourTurn": true, "player": "1", "replay": "board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,1,0,0,0,0,0,0,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0|move:3,1,2|board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,1,0,0,0,0,0,0,1,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player1": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player2": "f7898779-d537-4b0f-8c51-d604e934e2fb", "id": "lfH52rteC7dc 4J7\n", "ios": "16.3.1", "num": "2", "game": "darts", "mode": "101", "tver": "5", "build": "56", "version": "0" }')
		print("No AppPlugin Available, Setting Debug Data")
		
	setup_ui_elements_style_and_signals()
	setup_score_labels()
	setup_sent_label()

	call_deferred("calculate_button_target_position")
	send_button.visible = false
	
	if rules_button:
		rules_button.pressed.connect(on_rules_button_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)

func setup_board_structure():
	if not grid:
		return

	board.clear()

	for y in range(BOARD_SIZE):
		board.append([])
		for x in range(BOARD_SIZE):
			var cell_scene = preload("res://reversi/Cell.tscn")
			var cell = cell_scene.instantiate()
			if cell:
				grid.add_child(cell)
				board[y].append(cell)
				cell.set_meta("pos", Vector2i(x, y))
				cell.pressed.connect(on_cell_pressed.bind(x, y))
				
				var highlight = cell.find_child("Highlight")
				if highlight and highlight is TextureRect:
					highlight.texture = create_radial_gradient_texture(64)
					highlight.visible = false
				var temp_label = cell.find_child("TempPieceLabel")
				if temp_label:
					temp_label.visible = false
			else:
				board[y].append(null)
	dot_timer.timeout.connect(_on_dot_timer_timeout)

func calculate_button_target_position():
	var grid_global_bottom_y = grid.get_global_position().y + grid.size.y
	var main_vbox_global_position = $MainVBoxContainer.get_global_position().y
	send_button_target_y_position = grid_global_bottom_y - main_vbox_global_position + 60
	
	var offscreen_bottom_y = $MainVBoxContainer.size.y + BUTTON_OFFSCREEN_OFFSET
	send_button.position.y = offscreen_bottom_y

func setup_ui_elements_style_and_signals():
	if send_button:
		send_button.pressed.connect(on_send_button_pressed)
		send_button.text = "Send"
		var button_style_normal = StyleBoxFlat.new()
		button_style_normal.bg_color = Color("#2148af")
		button_style_normal.corner_radius_top_left = 8
		button_style_normal.corner_radius_top_right = 8
		button_style_normal.corner_radius_bottom_left = 8
		button_style_normal.corner_radius_bottom_right = 8
		button_style_normal.set_border_width_all(2)
		button_style_normal.border_color = Color("#42A5F5")

		var button_style_hover = StyleBoxFlat.new()
		button_style_hover.bg_color = Color("#283593")
		button_style_hover.corner_radius_top_left = 8
		button_style_hover.corner_radius_top_right = 8
		button_style_hover.corner_radius_bottom_left = 8
		button_style_hover.corner_radius_bottom_right = 8
		button_style_hover.set_border_width_all(2)
		button_style_hover.border_color = Color("#64B5F6")

		send_button.add_theme_stylebox_override("normal", button_style_normal)
		send_button.add_theme_stylebox_override("hover", button_style_hover)
		send_button.add_theme_font_override("font", SystemFont.new())
		send_button.add_theme_color_override("font_color", Color.WHITE)
		send_button.add_theme_font_size_override("font_size", 24)
		send_button.set_custom_minimum_size(Vector2(180, 50))
		send_button.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		send_button.set_v_size_flags(Control.SIZE_SHRINK_BEGIN)

	if player_count_label:
		var player_score_style = StyleBoxFlat.new()
		player_score_style.bg_color = Color.BLACK
		player_score_style.set_border_width_all(2)
		player_score_style.border_color = Color.GRAY
		player_count_label.add_theme_stylebox_override("normal", player_score_style)
		player_count_label.add_theme_color_override("font_color", Color.WHITE)
		player_count_label.add_theme_font_size_override("font_size", 24)
		player_count_label.set_custom_minimum_size(Vector2(100, 40))
		player_count_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
		player_count_label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		player_count_label.set_h_size_flags(Control.SIZE_SHRINK_CENTER)

	if opp_count_label:
		var opp_score_style = StyleBoxFlat.new()
		opp_score_style.bg_color = Color.WHITE
		opp_score_style.set_border_width_all(2)
		opp_score_style.border_color = Color.DARK_GRAY
		opp_count_label.add_theme_stylebox_override("normal", opp_score_style)
		opp_count_label.add_theme_color_override("font_color", Color.BLACK)
		opp_count_label.add_theme_font_size_override("font_size", 24)
		opp_count_label.set_custom_minimum_size(Vector2(100, 40))
		opp_count_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
		opp_count_label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		opp_count_label.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
				
func setup_score_labels():
	if player_count_label:
		var player_score_style = StyleBoxFlat.new()
		if player == 1:
			player_score_style.bg_color = Color.BLACK
		else:
			player_score_style.bg_color = Color.WHITE
		player_score_style.set_border_width_all(2)
		player_score_style.border_color = Color.GRAY
		player_count_label.add_theme_stylebox_override("normal", player_score_style)
		if player == 1:
			player_count_label.add_theme_color_override("font_color", Color.WHITE)
		else:
			player_count_label.add_theme_color_override("font_color", Color.BLACK)
		player_count_label.add_theme_font_size_override("font_size", 24)
		player_count_label.set_custom_minimum_size(Vector2(100, 40))
		player_count_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
		player_count_label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		player_count_label.set_h_size_flags(Control.SIZE_SHRINK_CENTER)

	if opp_count_label:
		var opp_score_style = StyleBoxFlat.new()
		if player == 1:
			opp_score_style.bg_color = Color.WHITE
		else:
			opp_score_style.bg_color = Color.BLACK
		opp_score_style.set_border_width_all(2)
		opp_score_style.border_color = Color.DARK_GRAY
		opp_count_label.add_theme_stylebox_override("normal", opp_score_style)
		if player == 1:
			opp_count_label.add_theme_color_override("font_color", Color.BLACK)
		else:
			opp_count_label.add_theme_color_override("font_color", Color.WHITE)
		opp_count_label.add_theme_font_size_override("font_size", 24)
		opp_count_label.set_custom_minimum_size(Vector2(100, 40))
		opp_count_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
		opp_count_label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		opp_count_label.set_h_size_flags(Control.SIZE_SHRINK_CENTER)

func setup_sent_label():
	if sent_label:
		sent_label.visible = false
		sent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sent_label.add_theme_color_override("font_color", Color.WHITE)
		sent_label.add_theme_font_size_override("font_size", 22)

func initialize_board_pieces():
	print("initial pre_board", pre_board_data)
	print("initial post_board", post_board_data)
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			set_piece(x, y, "", true)

	var center = BOARD_SIZE / 2
	set_piece(center - 1, center -1, "⚫", true)
	set_piece(center, center, "⚫", true)
	set_piece(center - 1, center, "⚪", true)
	set_piece(center, center -1, "⚪", true)

func set_piece(x: int, y: int, symbol: String, instant: bool = false) -> void:
	if not is_in_bounds(Vector2i(x, y)):
		return

	if y >= board.size() or board[y] == null:
		return

	if x >= board[y].size() or board[y][x] == null:
		return

	var cell = board[y][x]
	
	if cell:
		var label = cell.find_child("Label")
		if label:
			label.text = symbol

		if not instant and cell.has_method("flip_to"):
			cell.flip_to(symbol)
		elif not cell.has_method("flip_to"):
			pass
	else:
		pass

func get_piece(x: int, y: int) -> String:
	if not is_in_bounds(Vector2i(x, y)):
		return ""

	if y >= board.size() or board[y] == null:
		return ""
	
	if x >= board[y].size() or board[y][x] == null:
		return ""

	var cell = board[y][x]
	
	if cell:
		var label = cell.find_child("Label")
		if label:
			return label.text
		else:
			return ""
	else:
		return ""

func place_star_points():
	var star_layer = $MainVBoxContainer/GameAreaCenterContainer/StarPointLayer
	for child in star_layer.get_children():
		child.queue_free()

	for pos in STAR_POINTS:
		var star = STAR_POINT_SCENE.instantiate()
		var cell = board[pos.y][pos.x]
		if not cell:
			continue

		var cell_global_pos = cell.get_global_position()
		var star_layer_global_pos = star_layer.get_global_position()
		var relative_pos = cell_global_pos - star_layer_global_pos

		var cell_size = cell.get_size()
		var star_size = star.get_size()

		var offset = Vector2(-8, -7)
		if pos.x >= BOARD_SIZE / 2:
			offset = Vector2(cell_size.x - star_size.x + 8, -7)

		star.position = relative_pos + offset
		star_layer.add_child(star)

func update_piece_counts() -> Dictionary:
	print("Update Piece Counts Called!")
	var white_count = 0
	var black_count = 0

	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			match get_piece(x, y):
				"⚪": white_count += 1
				"⚫": black_count += 1

	if temp_piece_active:
		if player_symbol == "⚪":
			white_count += 1
		elif player_symbol == "⚫":
			black_count += 1

	if player == 1:
		opp_count_label.text = str(white_count)
		player_count_label.text = str(black_count)
	else:
		opp_count_label.text = str(black_count)
		player_count_label.text = str(white_count)
	white_score = white_count
	black_score = black_count

	print("White Count:", white_count, "Black Count:", black_count)
	return {"white": white_count, "black": black_count}

func highlight_valid_moves():
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var cell = board[y][x]
			var highlight = cell.find_child("Highlight")
			if highlight:
				highlight.visible = replay_played and not game_over and is_valid_move(x, y, player_symbol)
	
	if temp_piece_active and temp_piece_x != -1 and is_my_turn:
		var cell = board[temp_piece_y][temp_piece_x]
		var highlight = cell.find_child("Highlight")
		if highlight:
			highlight.visible = false
		place_temp_piece_visual(temp_piece_x, temp_piece_y, player_symbol)

func _set_game_data(new_game_data_json: String):
	var parsed_data = JSON.parse_string(new_game_data_json)
	if parsed_data is Dictionary:
		
		var player_num_array = int(parsed_data.get("player", -1))
		player_val = 1 if player_num_array == 2 and is_my_turn else 2
		var sender_id = parsed_data.get("sender", "")
		var player1_id = parsed_data.get("player1", "")
		var player2_id = parsed_data.get("player2", "")
		var my_player = parsed_data.get("myPlayerId", "")
		var opponent_avatar_key = ""
		my_player  = parsed_data.get("myPlayerId", my_player)
		is_your_turn = parsed_data.get("isYourTurn", false)
		if (my_player == player1_id or my_player == player2_id or player1_id == ""):
			if is_your_turn:
				is_my_turn = true	
		else:
			spectator_mode = true
			print("Spectator Mode Enabled!")
			spec_label.visible = true
			player = 1
			print("199 Setting Player to ", player)
			
		if player_val == 1:
			player_symbol = "⚫"
		elif player_val == 2:
			player_symbol = "⚪"
		else:
			player_symbol = "⚫"
			
		print("My Device ID (my_player): ", my_player)
		print("My Numerical Player (player_val): ", player_val)
		print("My Player Symbol: ", player_symbol)
		
		if my_player != "" and player1_id != "" and player2_id != "":
			if my_player == player1_id:
				opponent_avatar_key = "avatar2"
				print("Opp is avatar2")
			elif my_player == player2_id:
				opponent_avatar_key = "avatar1"
				print("Opp is avatar1")
		
		if opponent_avatar_key != "" and parsed_data.has(opponent_avatar_key):
			var avatar_string = parsed_data[opponent_avatar_key]
			var opponent_data = _parse_avatar_string(avatar_string)
			if is_instance_valid(opp_avatar_display):
				opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

		replay = parsed_data.get("replay", "")
		
		replay_played = false
		my_moves.clear()

		if replay.is_empty():
			initialize_board_pieces()
			pre_board_data = get_current_board_as_array()
		else:
			var temp_parsed_replay = parse_replay(replay)
			if "post_board" in temp_parsed_replay and temp_parsed_replay["post_board"] is Array:
				pre_board_data = temp_parsed_replay["post_board"]
			elif "pre_board" in temp_parsed_replay and temp_parsed_replay["pre_board"] is Array:
				pre_board_data = temp_parsed_replay["pre_board"]
			else:
				pre_board_data.clear()
				pre_board_data.resize(BOARD_SIZE * BOARD_SIZE)
				pre_board_data.fill(0)
			
			process_game_state()
			print("403 Updating Piece Counts")
			update_piece_counts()

			if not is_my_turn and not game_over:
				start_waiting_animation()
			else:
				stop_waiting_animation()
	else:
		print("Parsed Data is not dictionary")
		initialize_board_pieces()
		update_piece_counts()
		highlight_valid_moves()
		
func _parse_avatar_string(data_string: String) -> Dictionary:
	var hair_map = ["Spiky", "Long", "Bun", "Bald"]
	var body_map = ["Default", "Smiling", "Winking", "Surprised", "Frowning", "Tongue Out", "Cute"]
	var eyes_map = ["Open", "Closed", "Winking"]
	var mouth_map = ["Plain", "Smile", "Frown"]
	var clothing_map = ["T-Shirt", "Sweater", "Tank Top"]
	var backdrop_map = ["Plain", "Pattern 1", "Pattern 2", "Pattern 3", "Pattern 4", "Pattern 5", "Pattern 6", "Pattern 7", "Pattern 8", "Pattern 9"]

	var data = {}
	var parts = data_string.split("|")
	for part in parts:
		var key_value = part.split(",")
		if key_value.size() < 2:
			continue

		var key = key_value[0]
		var values = key_value.slice(1)

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
				var backdrop_index = int(values[0])
				if backdrop_index >= 0 and backdrop_index < backdrop_map.size():
					data["bg_style"] = backdrop_map[backdrop_index]
			"bg_color", "body_color", "hair_color", "clothes_color":
				if values.size() >= 3:
					var color_key = key.replace("_color", "") + "_color"
					data[color_key] = Color(float(values[0]), float(values[1]), float(values[2]))

	return data
		
func reset_board_to_pre_data():
	for idx in range(BOARD_SIZE * BOARD_SIZE):
		var y = BOARD_SIZE - 1 - int(idx / BOARD_SIZE)
		var x = idx % BOARD_SIZE
		var piece_val = pre_board_data[idx]
		var symbol = ""
		if piece_val == 1:
			symbol = "⚫"
		elif piece_val == 2:
			symbol = "⚪"
		set_piece(x, y, symbol, true)

func process_game_state():
	stop_waiting_animation()

	if not replay.is_empty() and not replay_played:
		await play_replay(replay)
	else:
		print("Replay is empty or replay was already played")
		if not replay.is_empty() and replay_played:
			print("Replayed Already Played")
			pass
		elif not replay.is_empty() and not replay_played:
			for y_godot in range(BOARD_SIZE):
				for x_godot in range(BOARD_SIZE):
					var replay_y = (BOARD_SIZE - 1) - y_godot
					var cell_index = replay_y * BOARD_SIZE + x_godot
					
					if cell_index >= 0 and cell_index < pre_board_data.size():
						var piece_value = pre_board_data[cell_index]
						
						var symbol = ""
						if piece_value == 1:
							symbol = "⚫"
						elif piece_value == 2:
							symbol = "⚪"
						set_piece(x_godot, y_godot, symbol, true)
					else:
						print(str("Error: pre_board_data index out of bounds or size mismatch. Index: ", cell_index, " Size: ", pre_board_data.size()))
	print("453 Call Update Count")
	update_piece_counts()

	if is_my_turn and not game_over:
		highlight_valid_moves()
		send_button.visible = true
	else:
		set_highlight_visibility(false)
		send_button.visible = false

func get_current_board_as_array() -> Array[int]:
	var current_board_array: Array[int] = []
	current_board_array.resize(BOARD_SIZE * BOARD_SIZE)
	current_board_array.fill(0)

	for y_godot in range(BOARD_SIZE):
		for x_godot in range(BOARD_SIZE):
			var replay_y = (BOARD_SIZE - 1) - y_godot
			var cell_index = replay_y * BOARD_SIZE + x_godot
			
			var piece_symbol = get_piece(x_godot, y_godot)

			var piece_value = 0
			if piece_symbol == "⚪":
				piece_value = 2
			elif piece_symbol == "⚫":
				piece_value = 1

			current_board_array[cell_index] = piece_value
	return current_board_array
			
func check_win() -> bool:
	var current_has_moves = has_any_valid_moves(player_symbol)
	var opponent_player = "⚫" if player_symbol == "⚪" else "⚪"
	var opponent_has_moves = has_any_valid_moves(opponent_player)
	print("Game Over Status: ", game_over)
	print("Our Possible Moves: ", current_has_moves)
	print("Opponent Possible Moves: ", opponent_has_moves)

	if not game_over and not current_has_moves and not opponent_has_moves:
		set_cells_interactable(false)
		print("Valid, player: ", player_val, " White Score: ", white_score, " Black Score: ", black_score)
		if (player_val == 2 and white_score > black_score) or (player_val == 1 and black_score > white_score):
			win_loss_label.text = "YOU WIN!"
			_show_win_burst(player_avatar_display)
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			win_loss_state = "1"
		elif white_score == black_score:
			win_loss_label.text = "TIE!"
			_show_win_burst(opp_avatar_display)
			win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
			win_loss_state = "0"
		else:
			win_loss_label.text = "YOU LOSE"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			win_loss_state = "-1"

		win_loss_label.visible = true

		await get_tree().process_frame

		win_loss_label.scale = Vector2(0, 0)
		win_loss_label.pivot_offset = win_loss_label.size / 2.0

		var tween = create_tween()
		tween.tween_property(win_loss_label, "scale", Vector2(1.0, 1.0), 0.6)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

		game_over = true

		await get_tree().create_timer(3.0).timeout
		var fade_tween = create_tween()
		fade_tween.tween_property(win_loss_label, "modulate:a", 0.0, 0.6)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)
		await fade_tween.finished
		win_loss_label.visible = false
		return true
	else:
		print("Game Over Status: ", game_over)
		print("Our Possible Moves: ", current_has_moves)
		print("Opponent Possible Moves: ", opponent_has_moves)

	return false
	
	
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
	(anim_instance as Node).call("set_rays", 10)
	(anim_instance as Node).call("set_brightness", 1.2)
	(anim_instance as Node).call("play", 0.15)

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
	
func set_cells_interactable(active: bool):
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var cell = board[y][x]
			if cell:
				cell.mouse_filter = Control.MOUSE_FILTER_STOP if not active else Control.MOUSE_FILTER_PASS

func show_replay_button():
	replay_button.text = "Play Again"
	if button_tween and button_tween.is_valid() and button_tween.is_running():
		button_tween.kill()

	replay_button.scale = Vector2(0.0, 0.0)
	replay_button.visible = true
	
	await get_tree().process_frame

	replay_button.pivot_offset = replay_button.size / 2.0

	button_tween = create_tween()
	
	button_tween.tween_property(replay_button, "scale", Vector2(1.0, 1.0), 2.0)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_LINEAR)

	if not replay_button.is_connected("pressed", on_replay_pressed):
		replay_button.pressed.connect(on_replay_pressed)

func on_replay_pressed():
	replay_button.visible = false
	print("NEED TO IMPLEMENT!!!!!")

func has_any_valid_moves(player_to_check: String) -> bool:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if get_piece(x, y) == "" and is_valid_move(x, y, player_to_check):
				return true
	return false

func play_replay(replay_string: String):
	print("Starting play_replay")
	print("Replay String: ", replay_string)

	var parsed = parse_replay(replay_string)
	print("Parsed Replay: ", parsed)

	set_highlight_visibility(false)
	send_button.visible = false

	if "pre_board" in parsed and parsed["pre_board"] is Array:
		print("Parsed contains pre_board data")
		var replay_pre_board_data = parsed["pre_board"]
		print("Replay Pre-Board Data Length: ", replay_pre_board_data.size())

		for y in range(BOARD_SIZE):
			for x in range(BOARD_SIZE):
				set_piece(x, y, "", true)

		if not replay_pre_board_data.is_empty():
			for i in range(replay_pre_board_data.size()):
				var piece_value = replay_pre_board_data[i]
				var replay_x = i % BOARD_SIZE
				var replay_y = i / BOARD_SIZE
				
				var godot_x = replay_x
				var godot_y = (BOARD_SIZE - 1) - replay_y
				
				var symbol = ""
				if piece_value == 2:
					symbol = "⚪"
				elif piece_value == 1:
					symbol = "⚫"

				print("Setting piece at (", godot_x, ",", godot_y, ") with symbol: ", symbol)
				
				if symbol != "":
					set_piece(godot_x, godot_y, symbol, true)
	else:
		print("Parsed has no valid pre_board. Initializing default board.")
		initialize_board_pieces()

	print("617 Call Update Count")
	update_piece_counts()

	if "move" in parsed and parsed["move"] is Array:
		print("Parsed contains move data")
		for move_data in parsed["move"]:
			print("Processing move: ", move_data)
			if move_data is Array and move_data.size() >= 3:
				var col = int(move_data[0])
				var row_from_replay = int(move_data[1])
				replay_val = int(move_data[2])

				var row = (BOARD_SIZE - 1) - row_from_replay

				replay_symbol = ""
				if replay_val == 2:
					replay_symbol = "⚪"
				elif replay_val == 1:
					replay_symbol = "⚫"
				else:
					print("Invalid replay_val: ", replay_val)
					continue
				
				print("Move at col: ", col, ", row: ", row, ", symbol: ", replay_symbol)

				var directions_to_flip = get_flippable_directions(col, row, replay_symbol)
				print("Directions to flip: ", directions_to_flip)

				if not directions_to_flip.is_empty():
					print("Flipping pieces for move")
					flip_pieces(col, row, replay_symbol, directions_to_flip)
					set_piece(col, row, replay_symbol, false)

					await get_tree().create_timer(0.5).timeout

					print("652 Call Update Count")
					update_piece_counts()
				else:
					print("No pieces to flip for this move")
			else:
				print("Invalid move_data format: ", move_data)
	else:
		print("Parsed has no valid moves array")

	replay_played = true
	pre_board_data = get_current_board_as_array()

	print("Replay played, checking turn and game over status")
	if not game_over and is_my_turn:
		print("Highlighting valid moves and showing send button")
		highlight_valid_moves()
		send_button.visible = true
	else:
		print("Game Over State: ", game_over, " | Is My Turn: ", is_my_turn)
		set_highlight_visibility(false)
		send_button.visible = false

func parse_replay(replay: String) -> Dictionary:
	var result = {"move": []}

	var elements = replay.split("|")

	for i in range(elements.size()):
		var elem = elements[i]
		var spl = elem.split(":")
		
		if spl.size() < 2:
			continue

		var type = spl[0]
		var data_str = spl[1]

		if type == "board":
			var state_key = "pre_board"
			if "pre_board" in result:
				state_key = "post_board"
			
			var board_data: Array[int] = []
			var state_spl = data_str.split(",")

			if not state_spl.is_empty():
				for val_str in state_spl:
					if not val_str.is_empty():
						board_data.append(int(val_str))
					else:
						print("parse_replay: Skipped empty board value string.")
			else:
				print("parse_replay: Board data split was empty.")
			result[state_key] = board_data
			
		elif type == "move":
			var move = []
			var move_spl = data_str.split(",")

			if move_spl.size() >= 3:
				for val in move_spl:
					move.append(float(val))
				result["move"].append(move)
			else:
				print("parse_replay: Move data has less than 3 parts. Skipping.")
		else:
			print("parse_replay: Unknown type: '", type, "'. Skipping.")
	return result
	
func preview_flip_pieces(x: int, y: int, player: String):
	var directions = get_flippable_directions(x, y, player)
	for dir in directions:
		var pos = Vector2i(x, y) + dir
		while is_in_bounds(pos) and get_piece(pos.x, pos.y) != player:
			set_piece(pos.x, pos.y, player, false)
			pos += dir


func on_cell_pressed(x: int, y: int) -> void:
	if not is_my_turn or game_over:
		return

	if temp_piece_active and temp_piece_x == x and temp_piece_y == y:
		return

	if temp_piece_active:
		reset_board_to_pre_data()
		clear_temp_piece_visual()
		temp_piece_active = false
		preview_flips_active = false
		temp_piece_x = -1
		temp_piece_y = -1
		if send_button.visible:
			animate_button_slide_down()
	var current_piece = get_piece(x, y)
	var directions = get_flippable_directions(x, y, player_symbol)
	if current_piece != "" or directions.size() == 0:
		return

	temp_piece_x = x
	temp_piece_y = y
	temp_piece_active = true
	preview_flips_active = true

	place_temp_piece_visual(x, y, player_symbol)
	preview_flip_pieces(x, y, player_symbol)

	update_piece_counts()
	animate_button_slide_up()

func on_send_button_pressed():
	if not temp_piece_active or temp_piece_x == -1:
		return
	reset_board_to_pre_data()
	var directions_to_flip = get_flippable_directions(temp_piece_x, temp_piece_y, player_symbol)
	if directions_to_flip.is_empty():
		clear_temp_piece_visual()
		temp_piece_active = false
		send_button.visible = false
		highlight_valid_moves()
		return
	flip_pieces(temp_piece_x, temp_piece_y, player_symbol, directions_to_flip)
	set_piece(temp_piece_x, temp_piece_y, player_symbol,true)
	print("Pre Avatar Assignment Number: ", player)
	avatar_key = "avatar" + str(player)
	print("Post Avatar Assignment Number: ", avatar_key)
	post_board_data = get_current_board_as_array()
	
	print("Pre board data: ", pre_board_data)
	print("Post board data: ", post_board_data)
	
	
	var move_arr = [int(temp_piece_x), int(7-temp_piece_y), int(player_val)]
	my_moves.append(move_arr)
	
	var moves_str = ""
	for move in my_moves:
		moves_str += "move:" + str(move[0]) + "," + str(move[1]) + "," + str(move[2])	

	var result = {
		"replay": "board:" + ",".join(pre_board_data) + "|" + moves_str + "|" + "board:" + ",".join(post_board_data)
	}
	
	if player != 0 and is_instance_valid(player_avatar_display):
		var avatar_string = player_avatar_display.get_avatar_data_string()
		result[avatar_key] = avatar_string
		print("Adding my avatar data to payload with key '", avatar_key, "'")
	
	
	print("Replay string before JSON encode: ", result["replay"])
	print("Type of replay field: ", typeof(result["replay"]))
	
	if await check_win():
		print("Check Win 773 my_player: ", my_player, " win_loss_state: ", win_loss_state)
		if win_loss_state != "":
			result["winner"] = my_player + "|" + win_loss_state
	else:
		play_sent_animation()
		print("play sent 783 on send button pressed")

	var game_data = JSON.stringify(result)

	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("Attempting to send game data via AppPlugin.")
		print("Game data being sent: " + game_data)
		appPlugin.updateGameData(game_data)
	else:
		print("AppPlugin is null. Cannot send game data.")
	
	clear_temp_piece_visual()
	temp_piece_active = false
	temp_piece_x = -1
	temp_piece_y = -1

	animate_button_slide_down()
	is_my_turn = false

func start_waiting_animation():
	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true
	waiting_blur.visible = true

	waiting_label.modulate.a = 0.0
	waiting_blur.modulate.a = 0.0

	var tween = create_tween().set_parallel(true)
	tween.tween_property(waiting_label, "modulate:a", 1.0, 0.3)
	tween.tween_property(waiting_blur, "modulate:a", 1.0, 0.3)

	dot_timer.start()


func stop_waiting_animation():
	dot_timer.stop()
	waiting_label.visible = false
	waiting_blur.visible = false

func _on_dot_timer_timeout():
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots

func play_sent_animation():
	if sent_label and not game_over:
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
			sent_label.text = "Sent ✔"
		)

		sent_tween.tween_interval(2.0)
		sent_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)

		sent_tween.tween_callback(func():
			sent_label.visible = false
			sent_label.modulate.a = 1.0
			start_waiting_animation()
		)

func animate_button_slide_up():
	if button_tween and button_tween.is_running():
		button_tween.kill()
	
	send_button.visible = true
	button_tween = create_tween()
	button_tween.tween_property(send_button, "position:y", send_button_target_y_position, 0.75)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func animate_button_slide_down():
	if button_tween and button_tween.is_running():
		button_tween.kill()
		
	var offscreen_bottom_y = $MainVBoxContainer.size.y + BUTTON_OFFSCREEN_OFFSET
	
	button_tween = create_tween()
	button_tween.tween_property(send_button, "position:y", offscreen_bottom_y, 0.75)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	button_tween.tween_callback(func():
		send_button.visible = false
		await check_win()
	)

func set_highlight_visibility(visible: bool):
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var cell = board[y][x]
			if cell:
				var highlight = cell.find_child("Highlight")
				if highlight:
					highlight.visible = visible

func place_temp_piece_visual(x: int, y: int, symbol: String):
	if is_in_bounds(Vector2i(x, y)):
		var cell = board[y][x]
		var temp_label = cell.find_child("TempPieceLabel")
		if temp_label:
			temp_label.text = symbol
			temp_label.modulate = Color(1, 1, 1, 0.5)
			temp_label.visible = true

func clear_temp_piece_visual():
	if temp_piece_x != -1 and is_in_bounds(Vector2i(temp_piece_x, temp_piece_y)):
		var cell = board[temp_piece_y][temp_piece_x]
		var temp_label = cell.find_child("TempPieceLabel")
		if temp_label:
			temp_label.visible = false

func has_any_empty_cells() -> bool:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if get_piece(x, y) == "":
				return true
	return false

func handle_turn_transition():
	print("948 Call Update Count")
	update_piece_counts()
	if not has_any_empty_cells():
		highlight_valid_moves()
		return

func is_valid_move(x: int, y: int, player: String) -> bool:
	return get_flippable_directions(x, y, player).size() > 0

func flip_pieces(x: int, y: int, player: String, directions: Array) -> void:
	for dir in directions:
		var pos = Vector2i(x, y) + dir
		while is_in_bounds(pos) and get_piece(pos.x, pos.y) != player:
			set_piece(pos.x, pos.y, player, true)
			pos += dir

func get_flippable_directions(x: int, y: int, player: String) -> Array:
	var opponent = "⚪" if player == "⚫" else "⚫"
	var directions = []
	if get_piece(x, y) != "":
		return directions
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var dir = Vector2i(dx, dy)
			var pos = Vector2i(x + dx, y + dy)
			if not is_in_bounds(pos) or get_piece(pos.x, pos.y) != opponent:
				continue
			pos += dir
			while is_in_bounds(pos):
				var piece = get_piece(pos.x, pos.y)
				if piece == player:
					directions.append(dir)
					break
				elif piece == "":
					break
				pos += dir
	return directions

func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_SIZE and pos.y >= 0 and pos.y < BOARD_SIZE

func create_radial_gradient_texture(size: int = 64) -> Texture2D:
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2, size / 2)
	var max_dist = center.length()
	for y in size:
		for x in size:
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center) / max_dist
			var alpha = clamp(pow(dist,1.5), 0.0, 0.4)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(image)
	
func on_rules_button_pressed():
	rules_button.pivot_offset = rules_button.size / 2.0
	var tween = create_tween()
	tween.tween_property(rules_button, "scale", Vector2(1.3, 1.3), 0.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(rules_button, "scale", Vector2.ONE, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	var rules_popup_instance = RULES_POPUP_SCENE.instantiate()
	var dim_background = ColorRect.new()
	dim_background.color = Color(0, 0, 0, 0.5)
	dim_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(dim_background)
	get_tree().root.add_child(rules_popup_instance)

	var close_button = rules_popup_instance.get_node("MarginContainer/PanelContainer/VBoxContainer/HeaderMarginContainer/CloseButton")
	if close_button:
		close_button.pressed.connect(func():
			if is_instance_valid(dim_background):
				dim_background.queue_free()
			if is_instance_valid(rules_popup_instance):
				rules_popup_instance.queue_free()
		)

	await get_tree().process_frame

	var screen_size = get_viewport_rect().size

	var desired_width = screen_size.x * 0.9
	var desired_height = rules_popup_instance.get_combined_minimum_size().y
	
	rules_popup_instance.size = Vector2(desired_width, desired_height)

	rules_popup_instance.pivot_offset = rules_popup_instance.size / 2

	rules_popup_instance.position = (screen_size - rules_popup_instance.size) / 2

	rules_popup_instance.scale = Vector2.ZERO

	var popup_tween = create_tween()
	popup_tween.tween_property(rules_popup_instance, "scale", Vector2.ONE, 0.4)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	rules_popup_instance.grab_focus()

func _on_settings_button_pressed() -> void:

	settings_button.pivot_offset = settings_button.size / 2.0
	var tween = create_tween()
	tween.tween_property(settings_button, "scale", Vector2(1.3, 1.3), 0.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(settings_button, "scale", Vector2.ONE, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var popup_instance = SETTINGS_POPUP_SCENE.instantiate()
	var settings_popup_script = popup_instance as SettingsPopup
	var root = get_tree().root
	root.add_child(dim)
	root.add_child(popup_instance)

	popup_instance.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)

	settings_popup_script.setup_popup(dim)

	var volume_setting_hbox = HBoxContainer.new()
	volume_setting_hbox.add_child(Label.new())
	volume_setting_hbox.get_child(0).text = "Game Volume:"
	volume_setting_hbox.get_child(0).set_h_size_flags(Control.SIZE_EXPAND_FILL)

	var volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	
	var saved_volume = SettingsManager.get_setting(game_settings_category, "master_volume", 0.75)
	volume_slider.value = saved_volume

	volume_slider.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	volume_slider.value_changed.connect(func(value):
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))
		print("Master Volume: ", value)
		SettingsManager.set_setting(game_settings_category, "master_volume", value)
	)
	volume_setting_hbox.add_child(volume_slider)

	settings_popup_script.add_custom_setting(volume_setting_hbox)
	
	var toggle_debug_checkbox = CheckBox.new()
	toggle_debug_checkbox.text = "Show Debug Info"
	
	var saved_debug_info = SettingsManager.get_setting(game_settings_category, "show_debug_info", false)
	toggle_debug_checkbox.button_pressed = saved_debug_info

	toggle_debug_checkbox.pressed.connect(func():
		print("Debug Info Toggled: ", toggle_debug_checkbox.button_pressed)
		SettingsManager.set_setting(game_settings_category, "show_debug_info", toggle_debug_checkbox.button_pressed)
	)
	settings_popup_script.add_custom_setting(toggle_debug_checkbox)

	var custom_settings_title = popup_instance.find_child("CustomSettingsTitleLabel", true)
	if custom_settings_title and custom_settings_title is Label and settings_popup_script.custom_settings_container.get_child_count() > 0:
		custom_settings_title.visible = true
	else:
		if custom_settings_title and custom_settings_title is Label:
			custom_settings_title.visible = false

	settings_popup_script.closed.connect(func():
		print("Settings popup was closed for game: ", game_settings_category)
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
	)
	settings_popup_script.settings_theme_selected.connect(_on_theme_changed)

	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await get_tree().process_frame

	var viewport_size = get_viewport_rect().size
	var desired_width = viewport_size.x * 0.95
	var desired_height = popup_instance.get_combined_minimum_size().y
	
	popup_instance.size = Vector2(desired_width, desired_height)
	popup_instance.position = Vector2((viewport_size.x - desired_width) / 2, viewport_size.y)
	
	var bottom_offset = 50
	var target_y_position = viewport_size.y - desired_height - bottom_offset
	var target_position = Vector2((viewport_size.x - desired_width) / 2, target_y_position)

	var popup_tween = create_tween()
	popup_tween.tween_property(popup_instance, "position", target_position, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	popup_instance.grab_focus()
	
func _on_theme_changed(new_theme_name: String):
	print("Game scene received theme change: ", new_theme_name)

	pass
	
func _load_game_specific_settings():
	var saved_volume = SettingsManager.get_setting(game_settings_category, "master_volume", 0.75)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))

	var show_debug_info = SettingsManager.get_setting(game_settings_category, "show_debug_info", false)

	
	print("Loaded game-specific settings for ", game_settings_category, ":")
	print("  Master Volume: ", saved_volume)
	print("  Show Debug Info: ", show_debug_info)
