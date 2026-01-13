extends Control

@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var grid = %GridContainer
@onready var background = %Background
@onready var color_selector: HBoxContainer = %ColorSelectorContainer
@onready var left_bg: ColorRect = %LeftBG
@onready var right_bg: ColorRect = %RightBG
@onready var left_score_label: Label = %LeftScore
@onready var right_score_label: Label = %RightScore
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: ColorRect = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var win_loss_label: Label = %WinLossLabel
@onready var rules_button: Button = %RulesButton
@onready var settings_button: Button = %SettingsButton
@onready var spec_label: Label = %SpecLabel
@onready var you_label: Label = %YouLabel

const COLORS = [0, 1, 2, 3, 4, 5]
const BOARD_WIDTH = 8
const BOARD_HEIGHT = 7

var game_settings_category: String

const COLOR_MAP = {
	0: Color(0.92, 0.13, 0.432), # Red
	1: Color(0.45, 0.75, 0.29),  # Green
	2: Color(0.96, 0.85, 0.13),  # Yellow
	3: Color(0.2, 0.55, 0.81),   # Blue
	4: Color(0.35, 0.25, 0.53),  # Purple
	5: Color(0.25, 0.25, 0.25)   # Black
}

const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
const RULES_POPUP_SCENE = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")
const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")

var board: Array = []
var color_board: Array = []
var tween: Tween

var game_ended = false
var game_over = false
var win_loss_state = ""
var has_connected: bool = false
var is_your_turn: bool = false
var is_my_turn: bool = false
var spectator_mode: bool = false
var avatar_key = 0

var left_start := Vector2i(0, BOARD_HEIGHT - 1)
var right_start := Vector2i(BOARD_WIDTH - 1, 0)
var left_color: int
var right_color: int
var my_count: int
var op_count: int

var pre_board_data: Array = []
var post_board_data: Array = []
var my_moves: Array = []
var my_player
var my_player_id
var player = 1
var sent_tween: Tween
var dot_count = 0

func _ready():
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)
	
	randomize()
	print("Scene ready!")
	setup_color_selector()
	init_color_selector_collapsed()
	setup_board_structure()

	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)

	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("AppPlugin Available")
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
	else:
		call_deferred("_set_game_data", '{ "isYourTurn": true, "player": "2", "seed": "1796765200", "replay": "board:4,5,3,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,3,3,3,3,3,4,3,3,3,3,3,3,3,4,3,3,3,3,3,3,3|move:5|board:5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,3,5,5,5,5,3,3,3,3,3,5,3,3,3,3,3,3,3,5,3,3,3,3,3,3,3", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player2": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player1": "f7898779-d537-4b0f-8c51-d604e2fb", "id": "lfH52rteC7dc 4J7\n", "ios": "16.3.1", "num": "2", "game": "darts", "mode": "101", "tver": "5", "build": "56", "version": "0" }')
		#call_deferred("_set_game_data", '{ "isYourTurn": true, "player": "2", "seed": "1796765200", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player2": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "id": "lfH52rteC7dc 4J7\n", "ios": "16.3.1", "num": "2", "game": "darts", "mode": "101", "tver": "5", "build": "56", "version": "0" }')
		
	if rules_button:
		rules_button.pressed.connect(on_rules_button_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)
		
func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color(0.08, 0.08, 0.08) if is_dark else Color("#e5e5e5")

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
	else:
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
	print("184 player num: ", player)

	for y in range(BOARD_HEIGHT):
		for x in range(BOARD_WIDTH):
			var cell = board[y][x]
			if not is_instance_valid(cell): continue
			
			var idx = display_board[y][x]
			var c = COLOR_MAP.get(idx, Color.GRAY)
			var bg = cell.find_child("Btn_Color", true)
			if bg:
				bg.modulate = c

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

func update_color_selector_states():
	
	print("271 Update Selectors. Left Color is ",left_color," Right Color is ",right_color)
	for i in COLORS:
		var container = color_selector.get_node_or_null("Wrapper_%d" % i)
		if not container:
			continue

		var btn = container.find_child("Color_%d" % i, true, false)
		if not btn:
			continue

		if i == left_color or i == right_color:
			btn.disabled = true
			btn.scale = Vector2(0.5, 0.5)
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			btn.disabled = false
			btn.scale = Vector2(1, 1)
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			
func update_ui_from_board_state():
	var my_start = left_start
	var opponent_start = right_start
	var my_current_color = get_color_from_position(my_start)
	var opponent_current_color = get_color_from_position(opponent_start)
	my_count = get_connected_cells(my_start, my_current_color).size()
	op_count = get_connected_cells(opponent_start, opponent_current_color).size()
	left_color = my_current_color
	right_color = opponent_current_color
	
	left_score_label.text = str(my_count)
	right_score_label.text = str(op_count)
	left_bg.color = COLOR_MAP.get(left_color, Color.GRAY)
	right_bg.color = COLOR_MAP.get(right_color, Color.GRAY)
	
	update_color_selector_states()
	print("253 UI Updated! Left Score (Me): %d, Right Score (Opp): %d" % [my_count, op_count])
			
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

			# --- Skin color (accept both) ---
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

func _on_color_selection_made(selected_color_index: int):
	stop_pulsing_all_cells()
	if not is_my_turn or game_over:
		return
	if [left_color, right_color].has(selected_color_index):
		return
	pre_board_data = get_current_board_as_array(player)
	var connected = get_connected_cells(left_start, left_color)
	var border = get_border_cells(connected)
	var added = []
	var seen = {}
	for pos in border:
		for neighbor in get_neighbors(pos):
			if seen.has(neighbor): continue
			seen[neighbor] = true
			if not connected.has(neighbor) and color_board[neighbor.y][neighbor.x] == selected_color_index:
				added += get_connected_cells(neighbor, selected_color_index)

	var all_cells_to_change = connected.duplicate()
	for pos in added:
		if not all_cells_to_change.has(pos):
			all_cells_to_change.append(pos)
			
	for pos in all_cells_to_change:
		color_board[pos.y][pos.x] = selected_color_index
	await play_move_animation(left_start)

	update_ui_from_board_state()
	hide_color_selector()
	post_board_data = get_current_board_as_array(player)
	var moves_str := "move:%d" % selected_color_index
	var pre_str = ",".join(Array(pre_board_data).map(func(i): return str(i)))
	var post_str = ",".join(Array(post_board_data).map(func(i): return str(i)))
	var result = {"replay": "board:%s|%s|board:%s" % [pre_str, moves_str, post_str]}
	
	avatar_key = "avatar" + str(player)
	if player != 0 and is_instance_valid(player_avatar_display):
		var avatar_string = player_avatar_display.get_avatar_data_string()
		result[avatar_key] = avatar_string
	print(result)
	game_ended = await check_win()
	if game_ended:
		print("Check Win 773 my_player: ", my_player_id, " win_loss_state: ", win_loss_state)
		if win_loss_state != "":
			result["winner"] = my_player_id + "|" + win_loss_state
	var app = Engine.get_singleton("AppPlugin")
	if app:
		app.updateGameData(JSON.stringify(result))
	else:
		print("AppPlugin is null. Cannot send game data.")

	is_my_turn = false
	
	if not game_ended:
		play_sent_animation()
	else:
		stop_waiting_animation()
		
func start_pulsing_my_cells():
	print("--- DEBUG: Attempting to start pulse animation. ---")
	
	var my_start_pos = left_start
	var my_color = get_color_from_position(my_start_pos)
	print("Player's corner color identified as: ", my_color)
	
	var my_cells = get_connected_cells(my_start_pos, my_color)
	print("Found %d connected cells to animate." % my_cells.size())
	
	if my_cells.is_empty():
		print("DEBUG: No cells found to animate. Aborting.")
		return

	var success_count = 0
	for cell_pos in my_cells:
		var cell_node = board[cell_pos.y][cell_pos.x]
		if is_instance_valid(cell_node):
			var anim_player = cell_node.get_node_or_null("HighlightAnim")
			if is_instance_valid(anim_player):
				anim_player.play("pulse")
				success_count += 1
			else:
				print("-> ERROR: Cell at %s is MISSING its AnimationPlayer node." % str(cell_pos))
		else:
			print("-> WARNING: Cell node at %s is not valid." % str(cell_pos))
			
	print("--- DEBUG: Pulse animation process finished. Played on %d/%d cells. ---" % [success_count, my_cells.size()])

func stop_pulsing_all_cells():
	for y in range(BOARD_HEIGHT):
		for x in range(BOARD_WIDTH):
			var cell_node = board[y][x]
			if is_instance_valid(cell_node):
				var anim_player = cell_node.get_node_or_null("HighlightAnim")
				if is_instance_valid(anim_player):
					anim_player.seek(0, true)
					anim_player.stop()
				
				var highlight = cell_node.find_child("Highlight", true)
				if is_instance_valid(highlight):
					highlight.visible = false
		
func play_move_animation(start_pos: Vector2i):
	var visual_start_pos = start_pos
	var new_color_idx = get_color_from_position(visual_start_pos)
	var new_color = COLOR_MAP.get(new_color_idx, Color.WHITE)
	
	var cells_to_animate_pos = get_connected_cells_on_display(visual_start_pos, new_color_idx)
	if cells_to_animate_pos.is_empty():
		return

	var animation_tween = create_tween().set_parallel()
	var parent_cell_nodes = []
	var btn_color_nodes = []
	var group_center = Vector2.ZERO
	var original_parent_positions = {}
	var animation_duration = 0.5

	for cell_pos in cells_to_animate_pos:
		var cell_node = board[cell_pos.y][cell_pos.x]
		if is_instance_valid(cell_node):
			var btn_color = cell_node.find_child("Btn_Color", true)
			if is_instance_valid(btn_color):
				parent_cell_nodes.append(cell_node)
				btn_color_nodes.append(btn_color)
				
				original_parent_positions[cell_node] = cell_node.position
				cell_node.z_index = 10
				
				animation_tween.tween_property(btn_color, "modulate", new_color, animation_duration).set_trans(Tween.TRANS_SINE)
				group_center += cell_node.position
	
	if parent_cell_nodes.is_empty(): return
	
	group_center /= parent_cell_nodes.size()
	group_center += board[0][0].size / 2.0
	var max_scale = 1.3
	
	animation_tween.tween_method(
		func(progress): _update_group_transform(progress, btn_color_nodes, parent_cell_nodes, group_center, original_parent_positions, max_scale),
		0.0, 1.0, animation_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	animation_tween.tween_method(
		func(progress): _update_group_transform(progress, btn_color_nodes, parent_cell_nodes, group_center, original_parent_positions, max_scale),
		1.0, 0.0, animation_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await animation_tween.finished

	for i in range(parent_cell_nodes.size()):
		var parent_cell = parent_cell_nodes[i]
		var btn_color = btn_color_nodes[i]
		
		parent_cell.z_index = 0
		btn_color.scale = Vector2.ONE
		btn_color.position = Vector2.ZERO

func _update_group_transform(progress: float, btn_nodes: Array, parent_cells: Array, center: Vector2, original_positions: Dictionary, max_scale: float):
	var current_scale = lerp(1.0, max_scale, progress)
	var gap_compensation = 1.05 
	
	for i in range(btn_nodes.size()):
		var btn_node = btn_nodes[i]
		var parent_cell = parent_cells[i]
		
		var original_pos = original_positions[parent_cell]
		var direction = original_pos - center
		var offset = direction * (current_scale - 1.0)
		btn_node.position = offset
		btn_node.scale = Vector2.ONE * current_scale * gap_compensation

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
	if not is_instance_valid(color_selector):
		return

	update_color_selector_states()

	color_selector.pivot_offset = color_selector.size / 2.0
	color_selector.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if tween and tween.is_running():
		tween.kill()

	tween = create_tween().set_parallel(true)
	tween.tween_property(color_selector, "scale", Vector2.ONE, 0.35)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(color_selector, "modulate:a", 1.0, 0.25)
	tween.tween_callback(func(): color_selector.mouse_filter = Control.MOUSE_FILTER_STOP)

		
func hide_color_selector():
	if not is_instance_valid(color_selector):
		return

	color_selector.pivot_offset = color_selector.size / 2.0
	color_selector.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if tween and tween.is_running():
		tween.kill()

	tween = create_tween().set_parallel(true)
	tween.tween_property(color_selector, "scale", Vector2(0.01, 0.01), 0.25)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(color_selector, "modulate:a", 0.0, 0.2)


func setup_tween():
	if tween and tween.is_valid():
		tween.kill()
	tween = create_tween()

func create_radial_gradient_texture(gradsize: int) -> Texture2D:
	var img = Image.create(gradsize, gradsize, false, Image.FORMAT_RGBA8)
	@warning_ignore("integer_division")
	var center = Vector2(gradsize / 2, gradsize / 2)

	for y in range(gradsize):
		for x in range(gradsize):
			@warning_ignore("integer_division")
			var dist = center.distance_to(Vector2(x, y)) / (gradsize / 2)
			var alpha = clamp(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha))

	var tex = ImageTexture.create_from_image(img)
	return tex

func _set_game_data(new_game_data_json: String):
	var parsed = JSON.parse_string(new_game_data_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	stop_pulsing_all_cells()
	stop_waiting_animation()

	var data: Dictionary = parsed
	is_your_turn = data.get("isYourTurn", false)
	
	var replay_str: String = data.get("replay", "")
	var player1_id: String = data.get("player1", "")
	var player2_id: String = data.get("player2", "")
	my_player_id = data.get("myPlayerId", "")
	var opponent_avatar_key = ""

	if my_player_id == player1_id or my_player_id == player2_id or player1_id == "":
		is_my_turn = is_your_turn
		if my_player_id == player1_id:
			player = 1
			opponent_avatar_key = "avatar2"
		elif my_player_id == player2_id:
			player = 2
			opponent_avatar_key = "avatar1"
		else:
			player = 1
	else:
		spectator_mode = true
		#is_my_turn = is_your_turn
		you_label.text = ""
		spec_label.show()
		player = 1
	
	if opponent_avatar_key != "" and data.has(opponent_avatar_key):
		var avatar_string = data[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
	
	if replay_str != "":
		print("Replaying Board")
		await parse_replay_string(replay_str, is_my_turn)
	else:
		print("New Board Generation")
		generate_filler_colors(int(data.get("seed", -1)))
		apply_colors_to_cells()
		update_ui_from_board_state()
		
	if not spectator_mode and is_my_turn and not game_over:
		call_deferred("show_color_selector")
		
	if is_my_turn:
		start_pulsing_my_cells()
	else:
		start_waiting_animation()

	game_ended = await check_win()
	if game_ended:
		stop_waiting_animation()
		hide_color_selector()
		game_over = true
		
func init_color_selector_collapsed():
	if not is_instance_valid(color_selector):
		return
	color_selector.scale = Vector2(0.01, 0.01)
	color_selector.modulate.a = 0.0
	color_selector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().process_frame
	color_selector.pivot_offset = color_selector.size / 2.0


func parse_replay_string(replay_str: String, play_animation: bool):
	var parts = replay_str.split("|")
	if parts.size() != 3:
		print("Invalid replay format")
		return

	if play_animation and parts[0].begins_with("board:"):
		var vals = parts[0].substr(6).split(",")
		var flat: Array[int] = []
		for v in vals:
			if v != "": flat.append(int(v))
		
		color_board.clear()
		for y in range(BOARD_HEIGHT):
			color_board.append([])
			for x in range(BOARD_WIDTH):
				var row_from_bottom = (BOARD_HEIGHT - 1) - y
				var base_flat_i = row_from_bottom * BOARD_WIDTH + x
				
				var final_flat_i: int
				if player == 2:
					final_flat_i = (flat.size() - 1) - base_flat_i
				else:
					final_flat_i = base_flat_i
					
				color_board[y].append(flat[final_flat_i] if final_flat_i < flat.size() else 0)
		
		apply_colors_to_cells()
		update_ui_from_board_state()

	if parts[2].begins_with("board:"):
		var vals = parts[2].substr(6).split(",")
		var flat: Array[int] = []
		for v in vals:
			if v != "": flat.append(int(v))

		color_board.clear()
		for y in range(BOARD_HEIGHT):
			color_board.append([])
			for x in range(BOARD_WIDTH):
				var row_from_bottom = (BOARD_HEIGHT - 1) - y
				var base_flat_i = row_from_bottom * BOARD_WIDTH + x
				
				var final_flat_i: int
				if player == 2:
					final_flat_i = (flat.size() - 1) - base_flat_i
				else:
					final_flat_i = base_flat_i
				
				color_board[y].append(flat[final_flat_i] if final_flat_i < flat.size() else 0)

	if play_animation:
		var opponent_start_pos = right_start
		await play_move_animation(opponent_start_pos)
		
		update_ui_from_board_state()
	else:
		apply_colors_to_cells()
		update_ui_from_board_state()

func get_color_from_position(pos: Vector2i) -> int:
	if pos.y >= 0 and pos.y < BOARD_HEIGHT and pos.x >= 0 and pos.x < BOARD_WIDTH:
		return color_board[pos.y][pos.x]
	return -1
	
func get_connected_cells_on_display(pos: Vector2i, target_color: int, visited = null) -> Array[Vector2i]:
	
	var display_board = color_board
	if visited == null:
		visited = {}

	if visited.has(pos):
		return []

	if pos.x < 0 or pos.x >= BOARD_WIDTH or pos.y < 0 or pos.y >= BOARD_HEIGHT:
		return []

	if display_board[pos.y][pos.x] != target_color:
		return []

	visited[pos] = true
	var result: Array[Vector2i] = [pos]

	for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		result += get_connected_cells_on_display(pos + dir, target_color, visited)
	return result

func get_connected_cells(pos: Vector2i, target_color: int, visited = null) -> Array[Vector2i]:
	if visited == null:
		visited = {}

	if visited.has(pos):
		return []

	if pos.x < 0 or pos.x >= BOARD_WIDTH or pos.y < 0 or pos.y >= BOARD_HEIGHT:
		return []

	if color_board[pos.y][pos.x] != target_color:
		return []

	visited[pos] = true
	var result: Array[Vector2i] = [pos]

	for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		result += get_connected_cells(pos + dir, target_color, visited)
	return result

func get_current_board_as_array(player_num: int) -> Array:
	var flat_board := []
	for y in range(BOARD_HEIGHT - 1, -1, -1):
		for x in range(BOARD_WIDTH):
			flat_board.append(color_board[y][x])
	if player_num == 2:
		flat_board.reverse()

	print("Current Board Layout Sent: ", flat_board)
	return flat_board

func check_win() -> bool:
	print("--- CHECKING WIN CONDITION ---")
	var unique_colors = get_unique_colors_on_board()
	print("-> Unique colors on board: %s (Count: %d)" % [unique_colors, unique_colors.size()])
	if unique_colors.size() > 2 or my_count + op_count < (BOARD_HEIGHT*BOARD_WIDTH):
		print("-> RESULT: Game Continues. More than 2 colors remain or combined score is too low.")
		return false
	print("-> WIN CONDITION MET: 2 or fewer colors remain.")
	
	var was_over = game_over
	game_over = true
	hide_color_selector()
	if not was_over:
		print("-> Evaluating final scores. My score: %d, Opponent's score: %d" % [my_count, op_count])
		if my_count > op_count:
			print("-> FINAL TALLY: YOU WIN!")
			_show_win_burst(player_avatar_display)
			if not spectator_mode:
				win_loss_label.text = "YOU WIN!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			else:
				win_loss_label.text = "Player 1 Wins!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			win_loss_state = "1"
		elif op_count > my_count:
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
	
func get_unique_colors_on_board() -> Array:
	var unique_colors = []
	for y in range(BOARD_HEIGHT):
		for x in range(BOARD_WIDTH):
			var color = color_board[y][x]
			if not unique_colors.has(color):
				unique_colors.append(color)
	return unique_colors

func play_sent_animation():
	if not is_instance_valid(sent_label):
		print("Warning: sent_label is not valid for play_sent_animation.")
		return
	if game_over:
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
	
func on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return

	rules_button.pivot_offset = rules_button.size / 2.0
	var tween := create_tween()
	tween.tween_property(rules_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(rules_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var popup := RULES_POPUP_SCENE.instantiate() as RulesPopup
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99

	popup.tree_exited.connect(func():
		if is_instance_valid(dim):
			dim.queue_free()
	)

	popup.open("How to Play Filler", _get_rules_text())
	
func _get_rules_text() -> String:
	return """
[font_size={18px}]
1. Each player is assigned a corner tile at the start of the game.
2. Players take turns filling their tiles with one of 6 colors in an attempt to capture adjacent tiles of the same color.
3. You are not allowed to change the color of your tiles into the color of your opponents tiles.
4. The game ends when there are no more tiles to occupy
[/font_size]
"""

func _on_settings_button_pressed() -> void:
	settings_button.pivot_offset = settings_button.size / 2.0
	tween = create_tween()
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

	#var volume_setting_hbox = HBoxContainer.new()
	#volume_setting_hbox.add_child(Label.new())
	#volume_setting_hbox.get_child(0).text = "Game Volume:"
	#volume_setting_hbox.get_child(0).set_h_size_flags(Control.SIZE_EXPAND_FILL)
#
	#var volume_slider = HSlider.new()
	#volume_slider.min_value = 0.0
	#volume_slider.max_value = 1.0
	#volume_slider.step = 0.05
	#
	#var saved_volume = SettingsManager.get_setting(game_settings_category, "master_volume", 0.75)
	#volume_slider.value = saved_volume
#
	#volume_slider.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	#volume_slider.value_changed.connect(func(value):
		#AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))
		#print("Master Volume: ", value)
		#SettingsManager.set_setting(game_settings_category, "master_volume", value)
	#)
	#volume_setting_hbox.add_child(volume_slider)
#
	#settings_popup_script.add_custom_setting(volume_setting_hbox)
	#
	#var toggle_debug_checkbox = CheckBox.new()
	#toggle_debug_checkbox.text = "Show Debug Info"
	#
	#var saved_debug_info = SettingsManager.get_setting(game_settings_category, "show_debug_info", false)
	#toggle_debug_checkbox.button_pressed = saved_debug_info
#
	#toggle_debug_checkbox.pressed.connect(func():
		#print("Debug Info Toggled: ", toggle_debug_checkbox.button_pressed)
		#SettingsManager.set_setting(game_settings_category, "show_debug_info", toggle_debug_checkbox.button_pressed)
	#)
	#settings_popup_script.add_custom_setting(toggle_debug_checkbox)

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
	settings_popup_script.dark_mode_changed.connect(_apply_bg_for_dark)

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
