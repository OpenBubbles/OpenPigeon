extends Control

@onready var grid = $MainVBoxContainer/GameAreaCenterContainer/BoardVBoxContainer/BorderPanelContainer/GridContainer
@onready var color_selector: HBoxContainer = $MainVBoxContainer/ColorSelectorContainer
@onready var left_bg: ColorRect = $MainVBoxContainer/TopInfoHBoxContainer/ScoreMarginContainer/LeftPlayer/LeftBG
@onready var right_bg: ColorRect = $MainVBoxContainer/TopInfoHBoxContainer/ScoreMarginContainer/RightPlayer/RightBG
@onready var left_score_label: Label = $MainVBoxContainer/TopInfoHBoxContainer/ScoreMarginContainer/LeftPlayer/LeftScore
@onready var right_score_label: Label = $MainVBoxContainer/TopInfoHBoxContainer/ScoreMarginContainer/RightPlayer/RightScore
@onready var sent_label: Label = $MainVBoxContainer/GameAreaCenterContainer/SentLabel
@onready var waiting_label: Label = $WaitingContainer/WaitForOpponentLabel
@onready var waiting_blur: ColorRect = $WaitBlur
@onready var dot_timer: Timer = $DotTimer
@onready var win_loss_label = $MainVBoxContainer/GameAreaCenterContainer/WinLossLabel
@onready var rules_button = $MainVBoxContainer/BottomItemHBoxContainer/MarginContainer/RulesButton
@onready var settings_button = $MainVBoxContainer/BottomItemHBoxContainer/MarginContainer/SettingsButton

const COLORS = [0, 1, 2, 3, 4, 5]  # Red, Green, Yellow, Blue, Purple, Black
const BOARD_WIDTH = 8  # For the number of columns
const BOARD_HEIGHT = 7 # For the number of rows

const COLOR_MAP = {
	0: Color(0.92, 0.13, 0.432), # Red
	1: Color(0.45, 0.75, 0.29),  # Green
	2: Color(0.96, 0.85, 0.13),  # Yellow
	3: Color(0.2, 0.55, 0.81),   # Blue
	4: Color(0.35, 0.25, 0.53),  # Purple
	5: Color(0.25, 0.25, 0.25)   # Black
}

# New constants for waiting animation
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
const RULES_POPUP_SCENE = preload("res://reversi/RulesPopup.tscn")

var board: Array = []
var color_board: Array = []
#var used_colors := []
var tween: Tween # Used for color selector animation

var game_ended = false
var game_over = false
var has_connected: bool = false
var is_my_turn: bool = false

var left_start := Vector2i(0, BOARD_HEIGHT - 1)
var right_start := Vector2i(BOARD_WIDTH - 1, 0)
var left_color: int
var right_color: int
var my_count: int
var op_count: int

var pre_board_data: Array = []
var post_board_data: Array = []
var my_moves: Array = []
var my_player: String = "1"

# New member variables for sent/waiting animation
var sent_tween: Tween # Tween for the "Sent" label
var dot_count = 0 # For the "Waiting..." dots animation

func _ready():
	randomize()
	print("Scene ready!")
	setup_color_selector()
	setup_board_structure()
	generate_filler_colors(0x210)
	apply_colors_to_cells()
	#print ("67 Update Selectors")
	#update_color_selector_states()

	var ui = get_score_elements()
	print("72 ", ui)
	
	#if my_player == "1":
	if is_instance_valid(ui.my_color_rect):
		ui.my_color_rect.color = COLOR_MAP.get(ui.my_color, Color.GRAY)
	if is_instance_valid(ui.opponent_color_rect):
		ui.opponent_color_rect.color = COLOR_MAP.get(ui.opponent_color, Color.GRAY)

	ui.my_score_label.text = str(get_connected_cells(ui.my_start, ui.my_color).size())
	ui.opponent_score_label.text = str(get_connected_cells(ui.opponent_start, ui.opponent_color).size())
	#else:
		#if is_instance_valid(ui.my_color_rect):
			#ui.my_color_rect.color = COLOR_MAP.get(ui.opponent_color, Color.GRAY)
		#if is_instance_valid(ui.opponent_color_rect):
			#ui.opponent_color_rect.color = COLOR_MAP.get(ui.my_color, Color.GRAY)
#
		#used_colors.append(ui.my_color)
		#used_colors.append(ui.opponent_color)
#
		#ui.my_score_label.text = str(get_connected_cells(ui.opponent_start, ui.opponent_color).size())
		#ui.opponent_score_label.text = str(get_connected_cells(ui.my_start, ui.my_color).size())
	
	setup_tween() # For color selector animation
	show_color_selector()

	# Connect the dot_timer timeout signal
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	else:
		print("Warning: dot_timer is not valid.")

	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("AppPlugin Available")
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
	else:
		_set_game_data('{ "isYourTurn": true, "player": "2", "seed": "1796765200", "replay": "board:5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4,5,5,5,5,4,5,4,4,5,5,5,5,4,4,4,4,5,4,5,5,4,4,4,4,4,5,5,4,4,4,4,4,4,4,4,4,4,4,4,4|move:2|board:1,2,2,2,2,2,2,2,2,2,2,2,2,4,4,4,2,2,2,2,4,4,4,4,2,2,2,2,4,4,4,4,2,2,2,2,4,4,4,4,4,2,2,4,4,4,4,4,4,4,4,4,4,4,4,4", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player1": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player2": "f7898779-d537-4b0f-8c51-d604e934e2fb", "id": "lfH52rteC7dc 4J7\n", "ios": "16.3.1", "num": "2", "game": "darts", "mode": "101", "tver": "5", "build": "56", "version": "0" }')		
		update_color_selector_states()
		print("No AppPlugin Available, Setting Debug Data")
		
	left_color = get_color_from_position(left_start)
	right_color = get_color_from_position(right_start)
	
	print("64 Update Selectors. Left Color is ",left_color," Right Color is ",right_color)
		
	if rules_button:
		rules_button.pressed.connect(on_rules_button_pressed)
	if settings_button:
		settings_button.pressed.connect(on_settings_button_pressed)
		
func get_score_elements() -> Dictionary:
	print("110: ", my_player)
	if my_player == "1":
		return {
			"my_color_rect": left_bg,
			"opponent_color_rect": right_bg,
			"my_score_label": left_score_label,
			"opponent_score_label": right_score_label,
			"my_start": right_start,
			"opponent_start": left_start,
			"my_color": right_color,
			"opponent_color": left_color
		}
	else:
		return {
			"my_color_rect": left_bg,
			"opponent_color_rect": right_bg,
			"my_score_label": left_score_label,
			"opponent_score_label": right_score_label,
			"my_start": left_start,
			"opponent_start": right_start,
			"my_color": left_color,
			"opponent_color": right_color
		}

func generate_gamepigeon_board(seed_val: int) -> Array:
	var result := []
	var rng = RandomNumberGenerator.new()
	rng.seed = int(seed_val)

	for y in range(BOARD_HEIGHT):
		result.append([])
		for x in range(BOARD_WIDTH):
			var forbidden := []
			if x > 0:
				forbidden.append(result[y][x - 1])
			if y > 0:
				forbidden.append(result[y - 1][x])

			var options := COLORS.filter(func(c): return not forbidden.has(c))
			if options.is_empty():
				print("Retrying board gen due to no valid options")
				return generate_gamepigeon_board(seed_val + 1)

			var chosen = options[rng.randi_range(0, options.size() - 1)]
			result[y].append(chosen)

	return result

func generate_filler_colors(seed_val: int = -1):
	if seed_val >= 0:
		color_board = generate_gamepigeon_board(seed_val)
		return

	color_board.clear()
	for y in range(BOARD_HEIGHT):
		color_board.append([])
		for x in range(BOARD_WIDTH):
			var forbidden_colors = []
			if x > 0:
				forbidden_colors.append(color_board[y][x - 1])
			if y > 0:
				forbidden_colors.append(color_board[y - 1][x])

			var options = COLORS.filter(func(c): return not forbidden_colors.has(c))
			if options.is_empty():
				generate_filler_colors()
				return

			var chosen = options[randi() % options.size()]
			color_board[y].append(chosen)

func apply_colors_to_cells():
	var display_board = color_board
	# flip only for Player 1
	print("184: ", my_player)
	if my_player == "1":
		display_board = get_flipped_board(color_board)

	for y in range(BOARD_HEIGHT):
		for x in range(BOARD_WIDTH):
			var cell = board[y][x]
			var idx  = display_board[y][x]
			var c    = COLOR_MAP.get(idx, Color.GRAY)
			var bg   = cell.find_child("Btn_Color", true)
			if bg and bg.has_method("set_modulate"):
				bg.set_modulate(c)
	# (highlight mask update remains unchanged)

func setup_board_structure():
	if not grid:
		return

	board.clear()
	grid.columns = BOARD_WIDTH

	for y in range(BOARD_HEIGHT):
		board.append([])
		for x in range(BOARD_WIDTH):
			var cell_scene = preload("res://fill/Cell.tscn")
			var cell = cell_scene.instantiate()
			if cell:
				grid.add_child(cell)
				board[y].append(cell)
				cell.set_meta("pos", Vector2i(x, y))

				var highlight = cell.find_child("Highlight")
				if highlight and highlight is TextureRect:
					highlight.texture = create_radial_gradient_texture(64)
					highlight.visible = false
			else:
				board[y].append(null)

func setup_color_selector():
	if not color_selector:
		print("237 not color selector!")
		return

	for i in COLORS:
		var outer_container := Control.new()
		outer_container.name = "Wrapper_%d" % i
		outer_container.custom_minimum_size = Vector2(64, 64)
		outer_container.size_flags_horizontal = Control.SIZE_FILL
		outer_container.size_flags_vertical = Control.SIZE_FILL
		print("setting up button ", i)
		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var btn := Button.new()
		btn.name = "Color_%d" % i
		btn.custom_minimum_size = Vector2(64, 64)
		btn.pivot_offset = btn.custom_minimum_size / 2.0
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.connect("pressed", _on_color_selection_made.bind(i))

		var rect := ColorRect.new()
		rect.color = COLOR_MAP[i]
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		btn.add_child(rect)
		center.add_child(btn)
		outer_container.add_child(center)
		color_selector.add_child(outer_container)

	#update_color_selector_states()
	#print("270 Update Color Selector States")

func update_color_selector_states():
	var claimed_colors := [left_color, right_color]
	print("271 Update Selectors. Left Color is ",left_color," Right Color is ",right_color)
	for i in COLORS:
		var container = color_selector.get_node_or_null("Wrapper_%d" % i)
		if not container:
			print("277 Negative")
			continue

		var btn = container.find_child("Color_%d" % i, true, false)
		if not btn:
			print("283 negative")
			continue

		# If the color is either the left or right background color
		if i == left_color or i == right_color:
			btn.disabled = false # Enable them so they can be clicked if needed
			btn.scale = Vector2(0.5, 0.5) # Set a specific size for active background colors
			btn.mouse_filter = Control.MOUSE_FILTER_STOP # Allow interaction
			print("Already used ", i)
		elif claimed_colors.has(i): # If it's a "claimed" color but not the active one
			btn.disabled = true
			btn.scale = Vector2(0.3, 0.3)
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			print("claimed color ", i, " but not active one")
		else: # All other available colors
			btn.disabled = false
			btn.scale = Vector2(1, 1)
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			print("available colors ", i)

func _on_color_selection_made(selected_color_index: int):
	# Only allow action if it's our turn and game is not over
	if not is_my_turn or game_over:
		print("Not my turn or the game is over, cannot make a move.")
		return
	print("305 Color Selection Called")
	# Capture board state before move
	pre_board_data = get_current_board_as_array()

	# Determine UI and logic refs based on current player
	var ui               = get_score_elements()
	var old_color        = ui.my_color
	var player_start     = ui.my_start
	var player_id_for_move = int(my_player) - 1

	# Prevent selecting a claimed color
	if [left_color, right_color].has(selected_color_index):
		print("Selected color is already claimed by a player.")
		return

	## Update used colors list
	#if used_colors.has(old_color):
		#used_colors.erase(old_color)
	#used_colors.append(selected_color_index)
	#
	#print("Used Colors ",used_colors)

	# Flood-fill logic to determine which cells change
	var connected = get_connected_cells(player_start, old_color)
	var border    = get_border_cells(connected)
	var added     = []
	var seen      = {}
	for pos in border:
		for neighbor in get_neighbors(pos):
			if seen.has(neighbor):
				continue
			seen[neighbor] = true
			if not connected.has(neighbor) and color_board[neighbor.y][neighbor.x] == selected_color_index:
				added += get_connected_cells(neighbor, selected_color_index)

	var new_connected = connected.duplicate()
	if added.size() == 0:
		for pos in new_connected:
			color_board[pos.y][pos.x] = selected_color_index
	else:
		for pos in added:
			if not new_connected.has(pos):
				new_connected.append(pos)
			color_board[pos.y][pos.x] = selected_color_index
		for pos in connected:
			color_board[pos.y][pos.x] = selected_color_index

	apply_colors_to_cells()

	# Update stored corner color
	if my_player == "1":
		left_color = selected_color_index
		right_color = get_color_from_position(left_start)
	else:
		right_color = selected_color_index
		left_color = get_color_from_position(right_start)
		
	print("355 Color index. Left Color is ",left_color," Right Color is ",right_color)

	# Refresh the rect color
	ui.my_color_rect.color = COLOR_MAP[selected_color_index]

	# Recount and update score labels
	var real_my_color = get_color_from_position(ui.my_start)
	var real_op_color = get_color_from_position(ui.opponent_start)
	my_count      = get_connected_cells(ui.my_start, real_my_color).size()
	op_count      = get_connected_cells(ui.opponent_start, real_op_color).size()
	print("378 MY Real COUNT: ",my_count, " OPPONENT Real COUNT: ",op_count)
	ui.my_score_label.text       = str(my_count)
	ui.opponent_score_label.text = str(op_count)

	# Capture board state after move
	post_board_data = get_current_board_as_array()

	# Build replay string
	my_moves.clear()
	my_moves.append(selected_color_index)
	print("386 COLORS: ", my_moves)
	var moves_str := "move:%d" % selected_color_index

	# CSV helpers
	var pre_str := ""
	for i in pre_board_data.size():
		pre_str += str(pre_board_data[i])
		if i < pre_board_data.size() - 1:
			pre_str += ","

	var post_str := ""
	for i in post_board_data.size():
		post_str += str(post_board_data[i])
		if i < post_board_data.size() - 1:
			post_str += ","

	var result = {"replay": "board:%s|%s|board:%s" % [pre_str, moves_str, post_str]}
	print(result)

	# Refresh selector and send data
	update_color_selector_states()
	var app = Engine.get_singleton("AppPlugin")
	if app:
		app.updateGameData(JSON.stringify(result))
	else:
		print("AppPlugin is null. Cannot send game data.")

	# Check for win and play/stop animations
	print("416 checking win")
	game_ended = await check_win()
	if not game_ended:
		play_sent_animation()
		print("418 game not ended")
	else:
		stop_waiting_animation()
		print("421 Game Over")

func get_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	for dir in directions:
		var neighbor = pos + dir
		if neighbor.x >= 0 and neighbor.x < BOARD_WIDTH and neighbor.y >= 0 and neighbor.y < BOARD_HEIGHT:
			neighbors.append(neighbor)
	return neighbors

func get_border_cells(connected: Array[Vector2i]) -> Array[Vector2i]:
	var border: Array[Vector2i] = []
	var seen := {}

	for pos in connected:
		var neighbors := get_neighbors(pos)
		for neighbor in neighbors:
			if not connected.has(neighbor) and not seen.has(neighbor):
				border.append(pos)
				seen[neighbor] = true
				break
	return border

func show_color_selector():
	if not color_selector:
		return

	if not tween or not tween.is_valid():
		setup_tween()

	color_selector.pivot_offset = color_selector.size / 2.0
	color_selector.scale = Vector2(0.0, 0.0)
	color_selector.visible = true

	tween.tween_property(color_selector, "scale", Vector2(1.0, 1.0), 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func setup_tween():
	if tween and tween.is_valid():
		tween.kill()
	tween = create_tween()

func create_radial_gradient_texture(size: int) -> Texture2D:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2, size / 2)
	for y in range(size):
		for x in range(size):
			var dist = center.distance_to(Vector2(x, y)) / (size / 2)
			var alpha = clamp(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	var tex = ImageTexture.create_from_image(img)
	return tex

func _set_game_data(new_game_data_json: String):
	var parsed = JSON.parse_string(new_game_data_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("Failed to parse game data")
		return

	var data: Dictionary = parsed

	# Unwrap fields (they are arrays or primitives)
	var seed_str: String = data.get("seed", "")
	var player_str: String = data.get("player", "")
	var replay_str: String = data.get("replay", "")
	is_my_turn = data.get("isYourTurn", false)

	# Set values
	if seed_str != "":
		var seed: int = int(seed_str)
		print("Parsed seed: ", seed)

	if player_str != "":
		print("483 Is my turn: ",is_my_turn)
		if is_my_turn:
			my_player = "1" if player_str == "2" else "2"
		else:
			my_player = "2" if player_str == "2" else "1"
		print("Parsed player: ", my_player)

	if replay_str != "":
		parse_replay_string(replay_str) # This is where the board is set up and colors/scores updated

	print("Is it my turn? ", is_my_turn)

	if is_my_turn:
		stop_waiting_animation()

	# --- NEW: Call check_win() after the board has been fully set up ---
	print("512 checking win")
	game_ended = await check_win()
	if game_ended:
		stop_waiting_animation()
		game_over = true

	# --- END NEW ---

func parse_replay_string(replay_str: String):
	var parts = replay_str.split("|")
	if parts.size() != 3:
		print("Invalid replay format")
		return

	# --- Load pre-board state ---
	if parts[0].begins_with("board:"):
		var vals = parts[0].substr(6).split(",")
		var flat: Array[int] = []
		for v in vals:
			if v != "":
				flat.append(int(v))
		color_board.clear()
		for y in range(BOARD_HEIGHT):
			color_board.append([])
			for x in range(BOARD_WIDTH):
				var idx    = BOARD_WIDTH - 1 - x
				var flat_i = y * BOARD_WIDTH + idx
				if flat_i < flat.size():
					color_board[y].append(flat[flat_i])
				else:
					color_board[y].append(0)
		apply_colors_to_cells()

	# --- Parse move (logging only) ---
	if parts[1].begins_with("move:"):
		var mp = parts[1].substr(5).split(",")
		if mp.size() == 2:
			print("Move: Color=", mp[0], " Player=", mp[1])

	# --- Load post-board state ---
	if parts[2].begins_with("board:"):
		var vals = parts[2].substr(6).split(",")
		var flat: Array[int] = []
		for v in vals:
			if v != "":
				flat.append(int(v))
		color_board.clear()
		for y in range(BOARD_HEIGHT):
			color_board.append([])
			for x in range(BOARD_WIDTH):
				var idx    = BOARD_WIDTH - 1 - x
				var flat_i = y * BOARD_WIDTH + idx
				if flat_i < flat.size():
					color_board[y].append(flat[flat_i])
				else:
					color_board[y].append(0)
		apply_colors_to_cells()
	# Update stored corner colors
	left_color = get_color_from_position(left_start)
	right_color = get_color_from_position(right_start)
	
	print("554 Update Selectors. Left Color is ",left_color," Right Color is ",right_color)

	# Refresh the rect colors
	var ui = get_score_elements()
	if is_instance_valid(ui.my_color_rect):
		ui.my_color_rect.color       = COLOR_MAP.get(ui.my_color, Color.GRAY)
	if is_instance_valid(ui.opponent_color_rect):
		ui.opponent_color_rect.color = COLOR_MAP.get(ui.opponent_color, Color.GRAY)

	# Recount and update score labels
	my_count = get_connected_cells(ui.my_start, ui.my_color).size()
	op_count = get_connected_cells(ui.opponent_start, ui.opponent_color).size()
	print("587 MY COUNT: ",my_count, " OPPONENT COUNT: ",op_count)
	ui.my_score_label.text       = str(my_count)
	ui.opponent_score_label.text = str(op_count)

	# Rebuild used_colors & selector
	#used_colors.clear()
	#if left_color  != -1:
		#used_colors.append(left_color)
	#if right_color != -1 and right_color != left_color:
		#used_colors.append(right_color)
	update_color_selector_states()
	print("595 checking win")
	game_ended = await check_win()
	if not game_ended and not is_my_turn:
		play_sent_animation()
		print("596 Playing Sent Animation")
	else:
		stop_waiting_animation()
		print("599 Stopping Animation")

func get_color_from_position(pos: Vector2i) -> int:
	if pos.y >= 0 and pos.y < BOARD_HEIGHT and pos.x >= 0 and pos.x < BOARD_WIDTH:
		return color_board[pos.y][pos.x]
	return -1

func get_connected_cells(pos: Vector2i, target_color: int, visited = null) -> Array[Vector2i]:
	# on the very first/top‐level call, visited will be null → replace it
	if visited == null:
		visited = {}

	# Already seen?
	if visited.has(pos):
		return []

	# Out of bounds?
	if pos.x < 0 or pos.x >= BOARD_WIDTH or pos.y < 0 or pos.y >= BOARD_HEIGHT:
		return []

	# Wrong color?
	if color_board[pos.y][pos.x] != target_color:
		return []

	# Mark visited & include this cell
	visited[pos] = true
	var result: Array[Vector2i] = [pos]

	# Recurse in the four cardinal directions
	for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		result += get_connected_cells(pos + dir, target_color, visited)
	print("Connected Cells: ", result.size())
	return result


func get_current_board_as_array() -> Array:
	var flat_board := []
	for y in range(BOARD_HEIGHT):
		for xi in range(BOARD_WIDTH):
			var x = BOARD_WIDTH - 1 - xi
			flat_board.append(color_board[y][x])
	print("Current Board Layout: ", flat_board)
	return flat_board
	
func get_flipped_board(board_to_flip: Array) -> Array:
	var flipped := []
	for y in range(BOARD_HEIGHT):
		flipped.append([])
		for x in range(BOARD_WIDTH):
			# Flipped coordinates: x => (BOARD_WIDTH - 1 - x), y => (BOARD_HEIGHT - 1 - y)
			flipped[y].append(board_to_flip[BOARD_HEIGHT - 1 - y][BOARD_WIDTH - 1 - x])
	return flipped

func check_win() -> bool:
	var ui = get_score_elements()
	print("Checking for win condition...")
	var unique_colors = get_unique_colors_on_board()
	print("Unique colors on board: ", unique_colors)
	# Only consider ending when 2 or fewer colors remain
	if unique_colors.size() > 2:
		return false
	
	# Flood-fill from the two fixed corners
	var covered  = my_count + op_count
	var total    = BOARD_WIDTH * BOARD_HEIGHT
	print("Covered cells: %d/%d" % [covered, total])
	
	# If there's any unreachable island, keep playing
	if covered < total:
		print("Not all cells are reachable yet → game continues")
		return false
	
	# Now it's really over
	var was_over = game_over
	game_over = true
	
	# Determine winner: 0=left, 1=right, -1=tie
	var winner_id = -1
	if my_count  > op_count: winner_id = 0
	elif op_count > my_count: winner_id = 1
	
	# Only animate once
	if not was_over:
		if winner_id == -1:
			win_loss_label.text = "TIE!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
		elif (my_player == "1" and winner_id == 0) or (my_player == "2" and winner_id == 1):
			win_loss_label.text = "YOU WIN!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		else:
			win_loss_label.text = "YOU LOSE"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
		
		win_loss_label.visible = true
		await get_tree().process_frame  # let it layout
		win_loss_label.scale = Vector2.ZERO
		win_loss_label.pivot_offset = win_loss_label.size / 2
		
		# pop in
		var tween_in = create_tween()
		tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		await get_tree().create_timer(3.0).timeout
		
		# fade out
		var tween_out = create_tween()
		tween_out.tween_property(win_loss_label, "modulate:a", 0.0, 0.6) \
				 .set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_LINEAR)
		await tween_out.finished
		
		win_loss_label.visible = false
		win_loss_label.modulate.a = 1.0
	
	print("738 not done yet!")
	return true
	
func get_unique_colors_on_board() -> Array:
	var unique_colors = []
	for y in range(BOARD_HEIGHT):
		for x in range(BOARD_WIDTH):
			var color = color_board[y][x]
			if not unique_colors.has(color):
				unique_colors.append(color)
	return unique_colors

# --- Sent and Waiting Animations ---
func play_sent_animation():
	if not is_instance_valid(sent_label):
		print("Warning: sent_label is not valid for play_sent_animation.")
		return
	if game_over: # Only play if game is not over
		return

	if sent_tween and sent_tween.is_running():
		sent_tween.kill() # Stop any existing sent tween

	sent_tween = create_tween().set_parallel(false)

	sent_label.text = "Sent"
	sent_label.visible = true
	sent_label.modulate.a = 0.0
	sent_label.scale = Vector2.ONE
	sent_label.pivot_offset = sent_label.get_size() / 2.0 # Ensure pivot is centered for scaling

	sent_tween.tween_property(sent_label, "modulate:a", 1.0, 0.3) # Fade in
	sent_tween.tween_interval(0.6) # Hold "Sent" for a bit
	sent_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.text = "Sent ✔" # Change text to checkmark
	)
	sent_tween.tween_interval(2.0) # Hold "Sent ✔" for a bit longer
	sent_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5) # Fade out

	sent_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0 # Reset alpha for next use
			start_waiting_animation() # Start waiting animation after sent disappears
	)

func start_waiting_animation():
	if not is_instance_valid(waiting_label) or not is_instance_valid(waiting_blur) or not is_instance_valid(dot_timer):
		print("Warning: Waiting animation nodes are not valid.")
		return

	dot_count = 0 # Reset dot count
	waiting_label.text = BASE_WAIT_TEXT + "." # Initial text
	waiting_label.visible = true
	waiting_blur.visible = true

	waiting_label.modulate.a = 0.0
	waiting_blur.modulate.a = 0.0

	var tween_wait_in = create_tween().set_parallel(true)
	tween_wait_in.tween_property(waiting_label, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_property(waiting_blur, "modulate:a", 1.0, 0.3)
	# Start dot timer only after fade-in is complete
	tween_wait_in.tween_callback(func():
		dot_timer.start()
	)


func stop_waiting_animation():
	if is_instance_valid(dot_timer):
		dot_timer.stop()
	if is_instance_valid(waiting_label):
		waiting_label.visible = false
		waiting_label.modulate.a = 1.0 # Reset alpha
	if is_instance_valid(waiting_blur):
		waiting_blur.visible = false
		waiting_blur.modulate.a = 1.0 # Reset alpha

func _on_dot_timer_timeout():
	if not is_instance_valid(waiting_label):
		print("Warning: waiting_label is not valid in _on_dot_timer_timeout.")
		return
	dot_count = (dot_count % 3) + 1 # Cycle through 1, 2, 3 dots
	var dots = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots
	
func on_rules_button_pressed():

	var rules_popup_instance = RULES_POPUP_SCENE.instantiate()

	var dim_background = ColorRect.new()
	dim_background.color = Color(0, 0, 0, 0.5)
	dim_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim_background)

	add_child(rules_popup_instance)

	move_child(dim_background, get_child_count() - 2)

	var close_button = rules_popup_instance.get_node("MarginContainer/PanelContainer/VBoxContainer/HeaderMarginContainer/CloseButton")
	if close_button:
		close_button.pressed.connect(func():
			if dim_background.is_inside_tree():
				dim_background.queue_free()
			if rules_popup_instance.is_inside_tree():
				rules_popup_instance.queue_free()
		)
	else:
		print("Close button not found")

	await get_tree().process_frame

	var screen_size = get_viewport_rect().size
	rules_popup_instance.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	rules_popup_instance.set_as_top_level(true)
	rules_popup_instance.visible = true

	rules_popup_instance.size = Vector2(screen_size.x, 10)
	await get_tree().process_frame
	var final_height = rules_popup_instance.get_combined_minimum_size().y
	var center_y = (screen_size.y - final_height) / 2

	rules_popup_instance.position = Vector2(screen_size.x / 2, center_y)
	rules_popup_instance.size = Vector2(0, final_height)

	var tween = create_tween()
	tween.tween_property(rules_popup_instance, "size:x", screen_size.x, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(rules_popup_instance, "position:x", 0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	rules_popup_instance.grab_focus()

func on_settings_button_pressed():
	show_toast_notification("Feature Coming Soon")

func show_toast_notification(message: String, duration: float = 2.0):
	var toast_label = Label.new()
	toast_label.text = message
	toast_label.add_theme_font_size_override("font_size", 28)
	toast_label.add_theme_color_override("font_color", Color.WHITE)
	
	var toast_style = StyleBoxFlat.new()
	toast_style.bg_color = Color(0, 0, 0, 0.7)
	toast_style.corner_radius_bottom_left = 10
	toast_style.corner_radius_bottom_right = 10
	toast_style.corner_radius_top_left = 10
	toast_style.corner_radius_top_right = 10
	toast_style.content_margin_left = 20
	toast_style.content_margin_right = 20
	toast_style.content_margin_top = 10
	toast_style.content_margin_bottom = 10
	toast_label.add_theme_stylebox_override("normal", toast_style)

	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.position.y -= 150
	toast_label.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
	toast_label.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	toast_label.modulate.a = 0.0

	add_child(toast_label)

	var tween = create_tween()
	
	tween.tween_property(toast_label, "modulate:a", 1.0, 0.3)
	tween.tween_interval(duration)
	tween.tween_property(toast_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(toast_label.queue_free)
