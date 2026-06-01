extends BaseGame

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
@onready var win_loss_label: Label = %WinLossLabel
@onready var spec_label: Label = %SpecLabel
@onready var you_label: Label = %YouLabel

const COLORS = [0, 1, 2, 3, 4, 5]
const BOARD_WIDTH = 8
const BOARD_HEIGHT = 7

const COLOR_MAP = {
	0: Color(0.92, 0.13, 0.432), # Red
	1: Color(0.45, 0.75, 0.29),  # Green
	2: Color(0.96, 0.85, 0.13),  # Yellow
	3: Color(0.2, 0.55, 0.81),   # Blue
	4: Color(0.35, 0.25, 0.53),  # Purple
	5: Color(0.25, 0.25, 0.25)   # Black
}

const MUSIC_STREAM := preload("res://global/audio/fill.ogg")

var board: Array = []
var color_board: Array = []
var tween: Tween

var game_ended = false
var game_over = false
var win_loss_state = ""
var has_connected: bool = false
var is_your_turn: bool = false
var is_my_turn: bool = false
var avatar_key = 0

var left_start: Vector2i
var right_start: Vector2i
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
	
	if Engine.has_singleton("OpenPigeonMedia"):
		mediaPlugin = Engine.get_singleton("OpenPigeonMedia")
		print("OpenPigeonMedia plugin is available")
	else:
		print("OpenPigeonMedia plugin is not available")

	_start_music()
	
	if appPlugin:
		print("AppPlugin Available")
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
	else:
		#call_deferred("_set_game_data", '{ "isYourTurn": true, "player": "2", "seed": "1796765200", "replay": "board:4,5,3,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,3,3,3,3,3,4,3,3,3,3,3,3,3,4,3,3,3,3,3,3,3|move:5|board:5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,3,5,5,5,5,3,3,3,3,3,5,3,3,3,3,3,3,3,5,3,3,3,3,3,3,3", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player2": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player1": "f7898779-d537-4b0f-8c51-d604e2fb", "id": "lfH52rteC7dc 4J7\n", "ios": "16.3.1", "num": "2", "game": "darts", "mode": "101", "tver": "5", "build": "56", "version": "0" }')
		call_deferred("_set_game_data", '{ "isYourTurn": true, "player": "2", "seed": "0", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player2": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "id": "lfH52rteC7dc 4J7\n", "ios": "16.3.1", "num": "2", "game": "darts", "mode": "101", "tver": "5", "build": "56", "version": "0" }')
		
	if rules_button:
		rules_button.pressed.connect(_on_rules_button_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)
		
var music_player: AudioStreamPlayer = null

func _start_music() -> void:
	if mediaPlugin and not mediaPlugin.isMusicEnabled():
		return

	if music_player == null:
		music_player = AudioStreamPlayer.new()
		music_player.name = "MusicPlayer"
		music_player.stream = MUSIC_STREAM
		music_player.volume_db = -4.0
		add_child(music_player)

	if not music_player.playing:
		music_player.play()
		
func _stop_music() -> void:
	if music_player:
		music_player.stop()
	
func _exit_tree() -> void:
	_stop_music()

func _update_start_positions() -> void:
	if player == 2:
		left_start = Vector2i(BOARD_WIDTH - 1, BOARD_HEIGHT - 1)
		right_start = Vector2i(0, 0)
	else:
		left_start = Vector2i(0, 0)
		right_start = Vector2i(BOARD_WIDTH - 1, BOARD_HEIGHT - 1)
		
func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color(0.08, 0.08, 0.08) if is_dark else Color("#e5e5e5")

const FILLER_NUM_PIECES := 6
const FILLER_POLISH_ITERATIONS := 15

const _DRAND48_A: int = 0x5DEECE66D
const _DRAND48_C: int = 0xB
const _DRAND48_MASK: int = (1 << 48) - 1
const _DRAND48_M24: int = (1 << 24) - 1
const _DRAND48_DENOM: float = 281474976710656.0

var _drand48_state: int = 0

func _filler_srand48(seed_val: int) -> void:
	var s32: int = seed_val & 0xFFFFFFFF
	_drand48_state = ((s32 << 16) | 0x330E) & _DRAND48_MASK

func _filler_drand48() -> float:
	var a_hi: int = _DRAND48_A >> 24
	var a_lo: int = _DRAND48_A & _DRAND48_M24
	var x_hi: int = (_drand48_state >> 24) & _DRAND48_M24
	var x_lo: int = _drand48_state & _DRAND48_M24

	var low: int = (a_lo * x_lo) + _DRAND48_C
	var new_lo: int = low & _DRAND48_M24
	var carry: int = low >> 24

	var new_hi: int = (a_hi * x_lo + a_lo * x_hi + carry) & _DRAND48_M24

	_drand48_state = ((new_hi << 24) | new_lo) & _DRAND48_MASK
	return float(_drand48_state) / _DRAND48_DENOM

func _filler_rand_piece() -> int:
	return int(floor(_filler_drand48() * float(FILLER_NUM_PIECES)))

func _filler_iterate_check(b: Array, i: int, j: int, c: int, temp_array: Array) -> void:
	if i < 0 or i >= BOARD_HEIGHT or j < 0 or j >= BOARD_WIDTH:
		return
	for pt in temp_array:
		if pt[0] == i and pt[1] == j:
			return
	if b[i][j] != c:
		return
	temp_array.append([i, j])
	if j >= 1:
		_filler_iterate_check(b, i, j - 1, c, temp_array)
	if j + 1 < BOARD_WIDTH:
		_filler_iterate_check(b, i, j + 1, c, temp_array)
	if i >= 1:
		_filler_iterate_check(b, i - 1, j, c, temp_array)
	if i + 1 < BOARD_HEIGHT:
		_filler_iterate_check(b, i + 1, j, c, temp_array)

func generate_gamepigeon_board(seed_val: int) -> Array:
	_filler_srand48(seed_val)

	var b: Array = []
	for i in range(BOARD_HEIGHT):
		var row: Array = []
		for j in range(BOARD_WIDTH):
			row.append(_filler_rand_piece())
		b.append(row)

	var pmask: Array = []
	for i in range(BOARD_HEIGHT):
		var mrow: Array = []
		for j in range(BOARD_WIDTH):
			mrow.append(false)
		pmask.append(mrow)
	pmask[0][0] = true
	pmask[1][0] = true
	pmask[0][1] = true
	pmask[BOARD_HEIGHT - 1][BOARD_WIDTH - 1] = true  # (6,7)
	pmask[BOARD_HEIGHT - 1][BOARD_WIDTH - 2] = true  # (6,6)
	pmask[BOARD_HEIGHT - 2][BOARD_WIDTH - 1] = true  # (5,7)

	while true:
		b[0][0] = _filler_rand_piece()
		b[0][1] = _filler_rand_piece()
		b[1][0] = _filler_rand_piece()
		var a: int = b[0][0]
		var bb: int = b[0][1]
		var cc: int = b[1][0]
		if a != bb and a != cc and bb != cc:
			break

	while true:
		b[BOARD_HEIGHT - 1][BOARD_WIDTH - 1] = _filler_rand_piece()
		b[BOARD_HEIGHT - 1][BOARD_WIDTH - 2] = _filler_rand_piece()
		b[BOARD_HEIGHT - 2][BOARD_WIDTH - 1] = _filler_rand_piece()
		var a2: int = b[BOARD_HEIGHT - 1][BOARD_WIDTH - 1]
		var b2: int = b[BOARD_HEIGHT - 1][BOARD_WIDTH - 2]
		var c2: int = b[BOARD_HEIGHT - 2][BOARD_WIDTH - 1]
		if a2 != b2 and a2 != c2 and b2 != c2:
			break

	for _iter in range(FILLER_POLISH_ITERATIONS):
		for i in range(BOARD_HEIGHT):
			for j in range(BOARD_WIDTH):
				var temp_array: Array = []
				_filler_iterate_check(b, i, j, b[i][j], temp_array)
				if temp_array.size() >= 2:
					for pt in temp_array:
						var pr: int = pt[0]
						var pc: int = pt[1]
						if not pmask[pr][pc]:
							b[pr][pc] = _filler_rand_piece()

	return b
	
const _NO_SEED_SENTINEL: int = -9223372036854775808

func generate_filler_colors(seed_val: int = _NO_SEED_SENTINEL):
	if seed_val != _NO_SEED_SENTINEL:
		# Real seed
		color_board = generate_gamepigeon_board(seed_val)
	else:
		# Fallback
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
	for y in range(BOARD_HEIGHT):
		for x in range(BOARD_WIDTH):
			var cell = board[y][x]
			if not is_instance_valid(cell):
				continue

			var bg = cell.find_child("Btn_Color", true)
			if bg:
				bg.modulate = COLOR_MAP.get(color_board[y][x], Color.GRAY)

func setup_board_structure():
	if not grid:
		return

	board.clear()
	grid.columns = BOARD_WIDTH

	for y in range(BOARD_HEIGHT):
		board.append([])
		for x in range(BOARD_WIDTH):
			board[y].append(null)

	for y in range(BOARD_HEIGHT - 1, -1, -1):
		for x in range(BOARD_WIDTH):
			var cell_scene = preload("res://fill/Cell.tscn")
			var cell = cell_scene.instantiate()
			if cell:
				grid.add_child(cell)
				board[y][x] = cell
				cell.set_meta("pos", Vector2i(x, y))

				var highlight = cell.find_child("Highlight")
				if highlight and highlight is TextureRect:
					highlight.texture = create_radial_gradient_texture(64)
					highlight.visible = false
					
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
	
	left_score_label.text = "%02d" % my_count
	right_score_label.text = "%02d" % op_count
	left_bg.color = COLOR_MAP.get(left_color, Color.GRAY)
	right_bg.color = COLOR_MAP.get(right_color, Color.GRAY)
	
	left_score_label.add_theme_color_override(
		"font_color",
		_get_score_text_color(left_color)
	)

	right_score_label.add_theme_color_override(
		"font_color",
		_get_score_text_color(right_color)
	)
	
	update_color_selector_states()
	print("253 UI Updated! Left Score (Me): %d, Right Score (Opp): %d" % [my_count, op_count])
	
func _get_score_text_color(bg_color_index: int) -> Color:
	if bg_color_index == 1 or bg_color_index == 20: # Yellow
		return Color(0.2, 0.2, 0.2) # dark gray
	return Color.WHITE
			
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
	
func _apply_visual_board_transform() -> void:
	if not is_instance_valid(grid):
		return

	await get_tree().process_frame
	grid.pivot_offset = grid.size / 2.0
	grid.rotation_degrees = 180.0 if player == 2 else 0.0

func _set_game_data(new_game_data_json: String):
	var parsed = JSON.parse_string(new_game_data_json)
	print("RAW INCOMING DATA: ", parsed)
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
		you_label.text = ""
		spec_label.show()
		player = 1
		
	_update_start_positions()
	
	if opponent_avatar_key != "" and data.has(opponent_avatar_key):
		var avatar_string = data[opponent_avatar_key]
		var opponent_data = GameUtils._parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
	
	if replay_str != "":
		print("Replaying Board")
		await parse_replay_string(replay_str, is_my_turn)
	else:
		print("New Board Generation")
		if data.has("seed") and str(data["seed"]).is_valid_int():
			print("Seed from JSON: ", data.get("seed", "MISSING"), " (type: ", typeof(data.get("seed", null)), ")")
			generate_filler_colors(int(data["seed"]))
		else:
			print("Seed from JSON: ", data.get("seed", "MISSING"), " (type: ", typeof(data.get("seed", null)), ")")
			generate_filler_colors()
		apply_colors_to_cells()
		await _apply_visual_board_transform()
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
		
	print("PLAYER DEBUG → player:", player, 
	  "| my_player_id:", my_player_id, 
	  "| player1_id:", player1_id, 
	  "| player2_id:", player2_id,
	  "| is_my_turn:", is_my_turn,
	  "| spectator:", spectator_mode)
		
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

	var board_part: String = parts[0] if play_animation else parts[2]
	if not board_part.begins_with("board:"):
		return

	var vals = board_part.substr(6).split(",")
	color_board.clear()

	for y in range(BOARD_HEIGHT):
		color_board.append([])
		for x in range(BOARD_WIDTH):
			var flat_i := y * BOARD_WIDTH + x
			color_board[y].append(int(vals[flat_i]) if flat_i < vals.size() and vals[flat_i] != "" else 0)

	apply_colors_to_cells()
	await _apply_visual_board_transform()
	update_ui_from_board_state()

	if play_animation:
		await play_move_animation(right_start)
		if parts[2].begins_with("board:"):
			vals = parts[2].substr(6).split(",")
			color_board.clear()

			for y in range(BOARD_HEIGHT):
				color_board.append([])
				for x in range(BOARD_WIDTH):
					var flat_i := y * BOARD_WIDTH + x
					color_board[y].append(int(vals[flat_i]) if flat_i < vals.size() and vals[flat_i] != "" else 0)

			apply_colors_to_cells()
			await _apply_visual_board_transform()
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
	for y in range(BOARD_HEIGHT):
		for x in range(BOARD_WIDTH):
			flat_board.append(color_board[y][x])

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
			GameUtils._show_win_burst(player_avatar_display)
			if not spectator_mode:
				win_loss_label.text = "YOU WIN!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			else:
				win_loss_label.text = "Player 1 Wins!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			win_loss_state = "1"
		elif op_count > my_count:
			print("-> FINAL TALLY: YOU LOSE")
			GameUtils._show_win_burst(opp_avatar_display)
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
	
func _get_rules_text() -> String:
	return """
[font_size={18px}]
1. Each player is assigned a corner tile at the start of the game.
2. Players take turns filling their tiles with one of 6 colors in an attempt to capture adjacent tiles of the same color.
3. You are not allowed to change the color of your tiles into the color of your opponents tiles.
4. The game ends when there are no more tiles to occupy
[/font_size]
"""
