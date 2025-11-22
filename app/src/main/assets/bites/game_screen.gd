extends Control
signal time_up

const LETTER_BG: Texture2D = preload("res://anagrams/letter_bg.png")
const DICT_PATH := "res://global/gp_wg_en2.txt"
const TOTAL_TIME_SEC := 80
const TILE_MARGIN := Vector2(2.0, 2.0)
const BOARD_COLS := 8
const BOARD_ROWS := 9

@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: Control = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var background: TextureRect = %Background
@onready var win_loss_label: Label = %WinLossLabel
@onready var spec_label: Label = %SpecLabel
@onready var main_vbox: VBoxContainer = %VBoxContainer
@onready var timer_label: RichTextLabel = %Timer
@onready var game_timer: Timer = %GameTimer
@onready var score_label: Label = %ScoreLabel
@onready var words_label: Label = %WordsLabel
@onready var board_panel: PanelContainer = %BoardPanel
@onready var board_grid: GridContainer = %BoardGrid

var selected_indices: Array[int] = []
var word_dict: Dictionary = {}
var used_words: Dictionary = {}
var rng := RandomNumberGenerator.new()
var seen_orders: Dictionary = {}
var current_order_key: String = ""
var max_orders: int = 0
var word_history: Array = []
var score: int = 0
var displayed_score: int = 0
var word_count: int = 0
var _pieces: Array = []

var tile_size: Vector2 = Vector2.ZERO
var remaining_time: int = TOTAL_TIME_SEC
var board_cell_size: Vector2 = Vector2.ZERO
var board_occupied: Array = []	# [row][col] -> tile Control or null

var tile_layer: Control = null
var tiles: Array[Control] = []

var _drag_tile: Control = null
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	main_vbox.add_theme_constant_override("separation", 24)
	
	_load_dictionary()
	score = 0
	displayed_score = 0
	word_count = 0
	_update_word_score_labels()
	rng.randomize()

	remaining_time = TOTAL_TIME_SEC
	_update_timer_label()

	game_timer.wait_time = 1.0
	game_timer.one_shot = false
	if not game_timer.timeout.is_connected(_on_game_timer_timeout):
		game_timer.timeout.connect(_on_game_timer_timeout)
	
	await get_tree().process_frame
	_init_board()


func _load_dictionary() -> void:
	word_dict.clear()
	var f := FileAccess.open(DICT_PATH, FileAccess.READ)
	if f == null:
		push_error("Could not open dictionary file: %s" % DICT_PATH)
		return

	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty():
			continue
		word_dict[line.to_upper()] = true

	f.close()


func _update_word_score_labels() -> void:
	if words_label:
		words_label.text = "WORDS: %d" % word_count
	if score_label:
		score_label.text = "SCORE: %04d" % displayed_score


func start_game() -> void:
	selected_indices.clear()

	await get_tree().process_frame
	score = 0
	displayed_score = 0
	word_count = 0
	used_words.clear()
	word_history.clear()
	_update_word_score_labels()
	seen_orders.clear()

	remaining_time = TOTAL_TIME_SEC
	_update_timer_label()

	game_timer.stop()
	game_timer.start()
	
	_reset_board_state(false)


func _set_displayed_score(value: float) -> void:
	displayed_score = int(round(value))
	_update_word_score_labels()


func _add_score(points: int, word: String) -> void:
	if points <= 0:
		return

	word_count += 1
	word_history.append({
		"word": word,
		"points": points
	})
	_update_word_score_labels()

	var start := displayed_score
	var target := displayed_score + points
	score = target

	var tween := create_tween()
	tween.tween_method(
		_set_displayed_score,
		start,
		target,
		0.4
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _apply_rainbow_flash(label: CanvasItem, total_time: float, cycles: int = 1) -> void:
	var colors: Array[Color] = [
		Color(1, 1, 1),
		Color(1, 0, 0),
		Color(1, 1, 0),
		Color(0, 1, 0),
		Color(0, 0, 1),
		Color(0.6, 0, 0.6),
		Color(1, 0, 1)
	]

	if colors.is_empty():
		return

	cycles = max(cycles, 1)

	var steps: int = colors.size()
	var total_steps: int = steps * cycles

	var step_time: float = total_time / float(total_steps)

	var tween := create_tween()
	tween.set_parallel(false)

	var base_alpha := label.self_modulate.a

	for i in total_steps:
		var c: Color = colors[i % steps]
		var target := Color(c.r, c.g, c.b, base_alpha)

		tween.tween_property(
			label,
			"self_modulate",
			target,
			step_time
		).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)

func _flash_word_highlight(row: int, col: int, length: int, horizontal: bool) -> void:
	var origin_cell := Vector2i(col, row)
	var span: Vector2i = Vector2i(length, 1) if horizontal else Vector2i(1, length)
	var highlight_color := Color(1, 1, 1, 0.5)

	for row_offset in range(span.y):
		for col_offset in range(span.x):
			var cx := origin_cell.x + col_offset
			var cy := origin_cell.y + row_offset
			_set_highlight_for_span_cell(cx, cy, origin_cell, span, highlight_color)

	await get_tree().create_timer(0.6).timeout

	for row_offset in range(span.y):
		for col_offset in range(span.x):
			var cx := origin_cell.x + col_offset
			var cy := origin_cell.y + row_offset

			var idx := _cell_index(cx, cy)
			if idx < 0 or idx >= board_grid.get_child_count():
				continue

			var cell := board_grid.get_child(idx) as Control
			var highlight := cell.get_node_or_null("Highlight") as PanelContainer
			if highlight:
				var sb := highlight.get_theme_stylebox("panel") as StyleBoxFlat
				if sb:
					var c := sb.bg_color
					c.a = 0.0
					sb.bg_color = c

func _get_order_key_from_tiles(tile_buttons: Array) -> String:
	var key := ""
	for btn in tile_buttons:
		if btn.get_child_count() > 0 and btn.get_child(0) is Label:
			var lbl := btn.get_child(0) as Label
			key += lbl.text
	return key

func _show_word_feedback(
	text: String,
	is_correct: bool,
	used_all_letters: bool = false,
	start_pos: Vector2 = Vector2(-1, -1)
) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 24)

	label.custom_minimum_size = Vector2(32.0, 32.0)

	if is_correct:
		label.modulate = Color(1.0, 1.0, 1.0, 0.95)
	else:
		label.modulate = Color(1.0, 0.1, 0.1, 0.95)

	label.self_modulate = Color(1, 1, 1, 1)

	label.top_level = true
	label.z_as_relative = false
	label.z_index = 200

	add_child(label)

	var origin_pos := start_pos
	if origin_pos == Vector2(-1, -1):
		origin_pos = Vector2(324.0, 800.0)

	var label_size := label.get_minimum_size()
	var margin := 8.0
	var container_rect: Rect2
	if is_instance_valid(board_panel):
		container_rect = board_panel.get_global_rect()
	else:
		container_rect = get_viewport().get_visible_rect()

	var min_x := container_rect.position.x + margin
	var max_x := container_rect.position.x + container_rect.size.x - margin - label_size.x

	if max_x < min_x:
		origin_pos.x = container_rect.position.x + margin
	else:
		origin_pos.x = clamp(origin_pos.x, min_x, max_x)

	label.global_position = origin_pos

	var end_pos := origin_pos + Vector2(0.0, -160.0)
	var move_duration := 5.0
	var fade_duration := 2.0
	var tween := create_tween()
	tween.tween_property(
		label,
		"global_position",
		end_pos,
		move_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	tween.parallel().tween_property(
		label,
		"modulate:a",
		0.0,
		fade_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if is_correct and used_all_letters:
		_apply_rainbow_flash(label, fade_duration, 20)

	await tween.finished
	label.queue_free()

func _get_word_score(wlen: int) -> int:
	if wlen == 3:
		return 100
	elif wlen == 4:
		return 400
	elif wlen == 5:
		return 1200
	elif wlen == 6:
		return 1400
	elif wlen == 7:
		return 1800
	elif wlen == 8:
		return 2200
	elif wlen == 9:
		return 2600
	return 0

func _score_board_word(word: String, start_pos: Vector2 = Vector2(-1, -1)) -> void:
	var points: int = _get_word_score(word.length())
	if points <= 0:
		return

	word_count += 1
	word_history.append({
		"word": word,
		"points": points
	})

	var start: int = displayed_score
	var target: int = displayed_score + points
	score = target

	_update_word_score_labels()

	var tween := create_tween()
	tween.tween_method(
		_set_displayed_score,
		start,
		target,
		0.4
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var popup_text := "%s +%d" % [word, points]
	_show_word_feedback(popup_text, true, false, start_pos)

func _scan_board_for_words() -> void:
	var grid := _build_letter_grid()
	if grid.is_empty():
		return
	
	# --- horizontal scan ---
	for row in BOARD_ROWS:
		var run: String = ""
		var start_col: int = 0
		
		for col in range(BOARD_COLS + 1):
			var ch: String = ""
			if col < BOARD_COLS:
				ch = String((grid[row] as Array)[col])
			
			if ch != "":
				if run.is_empty():
					start_col = col
				run += ch
			else:
				if run.length() >= 3:
					_process_found_word_with_fx(run, row, start_col, true)
				run = ""
	
	# --- vertical scan ---
	for col in BOARD_COLS:
		var run: String = ""
		var start_row: int = 0
		
		for row in range(BOARD_ROWS + 1):
			var ch: String = ""
			if row < BOARD_ROWS:
				ch = String((grid[row] as Array)[col])
			
			if ch != "":
				if run.is_empty():
					start_row = row
				run += ch
			else:
				if run.length() >= 3:
					_process_found_word_with_fx(run, start_row, col, false)
				run = ""

func _reset_selection_back_to_source() -> void:
	selected_indices.clear()

func _process_found_word_with_fx(raw_word: String, row: int, col: int, horizontal: bool) -> void:
	var word := raw_word.to_upper()
	if not word_dict.has(word):
		return

	var orient := "H" if horizontal else "V"
	var key := "%s_%d_%d_%s" % [orient, row, col, word]

	if used_words.has(key):
		return

	used_words[key] = true

	var length := word.length()

	_flash_word_highlight(row, col, length, horizontal)

	var start_pos := _word_center_position(row, col, length, horizontal)

	_score_board_word(word, start_pos)

func get_final_score() -> int:
	return score


func get_word_count() -> int:
	return word_count


func get_word_history() -> Array:
	return word_history.duplicate(true)

func _on_game_timer_timeout() -> void:
	if remaining_time > 0:
		remaining_time -= 1
		_update_timer_label()

		if remaining_time <= 0:
			game_timer.stop()
			_on_time_up()

func _update_timer_label() -> void:
	var mins := int(floor(float(remaining_time) / 60.0))
	var secs := remaining_time % 60
	timer_label.text = "[font_size={24px}]%02d:%02d[/font_size]" % [mins, secs]

func _on_time_up() -> void:
	emit_signal("time_up")

func _debug_print_order(label: String, tile_buttons: Array, key: String) -> void:
	var letters_str := ""
	for btn in tile_buttons:
		if btn.get_child_count() > 0 and btn.get_child(0) is Label:
			var lbl := btn.get_child(0) as Label
			letters_str += lbl.text

	var keys: Array[String] = []
	for k in seen_orders.keys():
		keys.append(k)

	print("--- ", label, " ---")
	print("  key: ", key)
	print("  visual letters: ", letters_str)
	print("  seen_orders.size(): ", seen_orders.size())
	print("  seen keys: ", keys)

func _init_board() -> void:
	if not is_instance_valid(board_grid):
		return
	
	board_grid.add_theme_constant_override("h_separation", 0)
	board_grid.add_theme_constant_override("v_separation", 0)

	var empty_panel := StyleBoxFlat.new()
	empty_panel.bg_color = Color(0, 0, 0, 0)
	board_grid.add_theme_stylebox_override("panel", empty_panel)

	if tile_layer == null:
		tile_layer = Control.new()
		tile_layer.name = "TileLayer"
		board_panel.add_child(tile_layer)
		tile_layer.z_as_relative = false
		tile_layer.z_index = 10
	
	for child in board_grid.get_children():
		if child.is_in_group("board_cell"):
			child.queue_free()
	
	var grid_size := board_grid.size
	if grid_size == Vector2.ZERO:
		grid_size = Vector2(512, 576)
	
	board_cell_size = Vector2(
		grid_size.x / float(BOARD_COLS),
		grid_size.y / float(BOARD_ROWS)
	)
	
	board_occupied.clear()
	for r in BOARD_ROWS:
		var row: Array = []
		for c in BOARD_COLS:
			row.append(null)
		board_occupied.append(row)
	
	for r in BOARD_ROWS:
		for c in BOARD_COLS:
			var cell := PanelContainer.new()
			cell.name = "Cell_%d_%d" % [c, r]
			cell.add_to_group("board_cell")
			cell.custom_minimum_size = board_cell_size
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.size_flags_vertical = Control.SIZE_EXPAND_FILL

			var cell_bg := StyleBoxFlat.new()
			cell_bg.bg_color = Color(0, 0, 0, 0)
			cell_bg.border_width_left = 0
			cell_bg.border_width_top = 0
			cell_bg.border_width_right = 0
			cell_bg.border_width_bottom = 0
			cell.add_theme_stylebox_override("panel", cell_bg)

			var highlight := PanelContainer.new()
			highlight.name = "Highlight"
			highlight.anchor_left = 0.0
			highlight.anchor_top = 0.0
			highlight.anchor_right = 1.0
			highlight.anchor_bottom = 1.0
			highlight.offset_left = 0.0
			highlight.offset_top = 0.0
			highlight.offset_right = 0.0
			highlight.offset_bottom = 0.0
			highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE

			highlight.z_as_relative = false
			highlight.z_index = 20

			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.0)
			sb.corner_radius_top_left = 6
			sb.corner_radius_top_right = 6
			sb.corner_radius_bottom_left = 6
			sb.corner_radius_bottom_right = 6
			highlight.add_theme_stylebox_override("panel", sb)

			cell.add_child(highlight)
			board_grid.add_child(cell)

func _clear_tiles() -> void:
	for t in tiles:
		if is_instance_valid(t):
			t.queue_free()
	tiles.clear()

func _reset_board_state(clear_tiles: bool = true) -> void:
	_clear_all_highlights()
	
	if clear_tiles:
		if not board_occupied.is_empty():
			for r in BOARD_ROWS:
				for c in BOARD_COLS:
					board_occupied[r][c] = null
		_clear_tiles()
	else:
		if not board_occupied.is_empty():
			for r in BOARD_ROWS:
				for c in BOARD_COLS:
					board_occupied[r][c] = null
		
		for tile in tiles:
			if not is_instance_valid(tile):
				continue
			if not tile.has_meta("cell"):
				continue
			
			var origin_val: Variant = tile.get_meta("cell")
			if typeof(origin_val) != TYPE_VECTOR2I:
				continue
			var origin_cell: Vector2i = origin_val as Vector2i
			var span: Vector2i = _tile_span_in_cells(tile)
			
			for row_offset in range(span.y):
				for col_offset in range(span.x):
					var cx: int = origin_cell.x + col_offset
					var cy: int = origin_cell.y + row_offset
					if cx < 0 or cx >= BOARD_COLS or cy < 0 or cy >= BOARD_ROWS:
						continue
					board_occupied[cy][cx] = tile

func _create_piece_tile(run: String, dir: int) -> TextureButton:
	var run_len := run.length()
	if run_len <= 0:
		run_len = 1
	
	var span := Vector2i(1, 1)
	match dir:
		1: # horizontal
			span = Vector2i(run_len, 1)
		2: # vertical
			span = Vector2i(1, run_len)
		_: # single
			span = Vector2i(1, 1)
	
	var btn := TextureButton.new()
	btn.texture_normal = LETTER_BG
	btn.texture_pressed = LETTER_BG
	btn.texture_hover = LETTER_BG
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	btn.custom_minimum_size = Vector2(
		board_cell_size.x * float(span.x),
		board_cell_size.y * float(span.y)
	)
	btn.size = btn.custom_minimum_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.z_index = 10
	
	var lbl := Label.new()
	lbl.text = run
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0
	lbl.anchor_top = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_left = 0.0
	lbl.offset_top = 0.0
	lbl.offset_right = 0.0
	lbl.offset_bottom = 0.0
	btn.add_child(lbl)
	
	btn.gui_input.connect(func(event: InputEvent) -> void:
		_on_tile_gui_input(event, btn)
	)
	
	return btn

func _rect_for_span(origin_cell: Vector2i, span: Vector2i) -> Rect2:
	var top_left := _cell_top_left_global(origin_cell)
	var rect_size := Vector2(
		span.x * board_cell_size.x,
		span.y * board_cell_size.y
	)
	return Rect2(top_left, rect_size)

func _rect_overlap_area(a: Rect2, b: Rect2) -> float:
	var intersect := a.intersection(b)
	if intersect == Rect2():
		return 0.0
	return intersect.size.x * intersect.size.y

func _cell_top_left_global(cell: Vector2i) -> Vector2:
	var origin := board_grid.global_position
	return origin + Vector2(
		cell.x * board_cell_size.x,
		cell.y * board_cell_size.y
	)
	
func _set_highlight_for_span_cell(col: int, row: int, origin: Vector2i, span: Vector2i, color: Color) -> void:
	if col < 0 or col >= BOARD_COLS or row < 0 or row >= BOARD_ROWS:
		return
	
	var idx := _cell_index(col, row)
	if idx < 0 or idx >= board_grid.get_child_count():
		return
	
	var cell := board_grid.get_child(idx) as Control
	var highlight := cell.get_node_or_null("Highlight") as PanelContainer
	if highlight == null:
		return
	
	var sb := highlight.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	
	var rel_x := col - origin.x
	var rel_y := row - origin.y
	
	var is_single := (span.x == 1 and span.y == 1)
	var tl := 0
	var top_right := 0
	var bl := 0
	var br := 0
	
	if is_single:
		tl = 6
		top_right = 6
		bl = 6
		br = 6
	elif span.y == 1:
		if rel_x == 0:
			tl = 6
			bl = 6
		elif rel_x == span.x - 1:
			top_right = 6
			br = 6
	elif span.x == 1:
		if rel_y == 0:
			tl = 6
			top_right = 6
		elif rel_y == span.y - 1:
			bl = 6
			br = 6
	
	sb.bg_color = color
	sb.corner_radius_top_left = tl
	sb.corner_radius_top_right = top_right
	sb.corner_radius_bottom_left = bl
	sb.corner_radius_bottom_right = br

func _tile_span_in_cells(tile: Control) -> Vector2i:
	var dir: int = 0
	if tile.has_meta("dir"):
		dir = int(tile.get_meta("dir"))
	
	var length: int = 1
	if tile.has_meta("len"):
		length = int(tile.get_meta("len"))
	
	match dir:
		1:
			return Vector2i(length, 1)  # horizontal
		2:
			return Vector2i(1, length)  # vertical
		_:
			return Vector2i(1, 1)
			
func _best_origin_cell_for_tile(tile: Control) -> Vector2i:
	var span: Vector2i = _tile_span_in_cells(tile)
	var tile_rect: Rect2 = Rect2(tile.global_position, tile.size)

	var best_cell: Vector2i = Vector2i(-1, -1)
	var best_score: float = 0.0

	for row in BOARD_ROWS:
		for col in BOARD_COLS:
			var origin_cell: Vector2i = Vector2i(col, row)
			if origin_cell.x + span.x > BOARD_COLS or origin_cell.y + span.y > BOARD_ROWS:
				continue

			var cell_rect: Rect2 = _rect_for_span(origin_cell, span)
			var overlap_area: float = _rect_overlap_area(tile_rect, cell_rect)
			var overlap_score: float = overlap_area / cell_rect.get_area()

			if overlap_score > best_score:
				best_score = overlap_score
				best_cell = origin_cell

	if best_score <= 0.0:
		return Vector2i(-1, -1)

	return best_cell

func _origin_cell_from_global_pos(global_pos: Vector2) -> Vector2i:
	if not is_instance_valid(board_grid):
		return Vector2i(-1, -1)
	
	var origin := board_grid.global_position
	var local := global_pos - origin
	
	var col := int(floor(local.x / board_cell_size.x))
	var row := int(floor(local.y / board_cell_size.y))
	
	if col < 0 or col >= BOARD_COLS or row < 0 or row >= BOARD_ROWS:
		return Vector2i(-1, -1)
	return Vector2i(col, row)
	
func _word_center_position(row: int, col: int, length: int, horizontal: bool) -> Vector2:
	var start_cell := Vector2i(col, row)
	var end_cell := Vector2i(col + length - 1, row) if horizontal else Vector2i(col, row + length - 1)
	var start_pos := _cell_center_global(start_cell)
	var end_pos := _cell_center_global(end_cell)
	return (start_pos + end_pos) * 0.5

func _on_tile_gui_input(event: InputEvent, tile: Control) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_tile = tile
				_drag_offset = tile.global_position - mb.global_position
				tile.z_as_relative = false
				tile.z_index = 100
			else:
				if _drag_tile == tile:
					var prev_cell: Vector2i = tile.get_meta("cell") if tile.has_meta("cell") else Vector2i(-1, -1)
					var snapped_cell := snap_tile_to_board(tile)
					if snapped_cell.x == -1 and prev_cell.x != -1:
						var center := _cell_center_global(prev_cell)
						tile.global_position = center - tile.size * 0.5
					else:
						tile.set_meta("cell", snapped_cell)
					
					tile.z_as_relative = false
					tile.z_index = 10
					
					_drag_tile = null
					_clear_all_highlights()
					
					_scan_board_for_words()
	elif event is InputEventMouseMotion and _drag_tile == tile:
		var mm := event as InputEventMouseMotion
		tile.global_position = mm.global_position + _drag_offset
		_update_drag_preview(tile)
	
func _create_letter_tile(run: String, dir: int) -> TextureButton:
	var btn := TextureButton.new()
	btn.texture_normal = LETTER_BG
	btn.texture_pressed = LETTER_BG
	btn.texture_hover = LETTER_BG
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	btn.focus_mode = Control.FOCUS_NONE
	btn.z_as_relative = false
	btn.z_index = 10

	var length: int = run.length()
	if length <= 0:
		length = 1

	var span: Vector2i
	match dir:
		1:	# horizontal
			span = Vector2i(length, 1)
		2:	# vertical
			span = Vector2i(1, length)
		_:
			span = Vector2i(1, 1)

	var span_pixels := Vector2(
		board_cell_size.x * span.x,
		board_cell_size.y * span.y
	)

	var final_size := span_pixels - TILE_MARGIN * 2.0
	if final_size.x < 1.0:
		final_size.x = 1.0
	if final_size.y < 1.0:
		final_size.y = 1.0

	btn.custom_minimum_size = final_size
	btn.size = final_size

	var per_cell_min_dim: float = min(board_cell_size.x, board_cell_size.y)
	var font_size: int = int(per_cell_min_dim * 0.6)

	for i in range(length):
		var ch: String = run[i]
		var lbl := Label.new()
		lbl.text = ch
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0, 0, 0, 0.8))
		lbl.self_modulate = Color(1, 1, 1, 1)

		lbl.add_theme_font_size_override("font_size", font_size)

		match dir:
			1:	# horizontal: split along X
				var left: float = float(i) / float(length)
				var right: float = float(i + 1) / float(length)
				lbl.anchor_left = left
				lbl.anchor_right = right
				lbl.anchor_top = 0.0
				lbl.anchor_bottom = 1.0
			2:	# vertical: split along Y
				var top: float = float(i) / float(length)
				var bottom: float = float(i + 1) / float(length)
				lbl.anchor_left = 0.0
				lbl.anchor_right = 1.0
				lbl.anchor_top = top
				lbl.anchor_bottom = bottom
			_:	# 1×1
				lbl.anchor_left = 0.0
				lbl.anchor_right = 1.0
				lbl.anchor_top = 0.0
				lbl.anchor_bottom = 1.0

		lbl.offset_left = 0.0
		lbl.offset_top = 0.0
		lbl.offset_right = 0.0
		lbl.offset_bottom = 0.0

		btn.add_child(lbl)

	btn.set_meta("dir", dir)
	btn.set_meta("len", length)
	btn.set_meta("letters", run)

	btn.gui_input.connect(func(event: InputEvent) -> void:
		_on_tile_gui_input(event, btn)
	)

	return btn

func _build_letter_grid() -> Array:
	var grid: Array = []
	
	for r in BOARD_ROWS:
		var row: Array[String] = []
		for c in BOARD_COLS:
			row.append("")
		grid.append(row)
	
	for tile in tiles:
		if not is_instance_valid(tile):
			continue
		if not tile.has_meta("cell"):
			continue
		var origin_val: Variant = tile.get_meta("cell")
		if typeof(origin_val) != TYPE_VECTOR2I:
			continue
		var origin_cell: Vector2i = origin_val as Vector2i
		var letters_val: Variant = tile.get_meta("letters") if tile.has_meta("letters") else ""
		var run: String = String(letters_val)
		if run.is_empty():
			continue

		var dir_val: Variant = tile.get_meta("dir") if tile.has_meta("dir") else 0
		var dir: int = int(dir_val)

		if tile.has_meta("dir"):
			dir = int(tile.get_meta("dir"))
		
		var length: int = run.length()
		for i in range(length):
			var col: int = origin_cell.x
			var row: int = origin_cell.y
			
			if dir == 1:
				# horizontal
				col = origin_cell.x + i
			elif dir == 2:
				# vertical
				row = origin_cell.y + i
			
			if col < 0 or col >= BOARD_COLS or row < 0 or row >= BOARD_ROWS:
				continue
			
			var ch: String = run[i]
			grid[row][col] = ch
	
	return grid
	
func get_letter_pieces() -> Array[String]:
	var pieces: Array[String] = []
	for p in _pieces:
		if not (p is Dictionary):
			continue
		if not p.has("run"):
			continue
		var run := String(p["run"]).strip_edges()
		if run.is_empty():
			continue
		pieces.append(run.to_upper())
	return pieces
	
func get_letter_piece_orientations() -> Array[bool]:
	var orientations: Array[bool] = []
	for p in _pieces:
		if not (p is Dictionary):
			continue
		var dir := int(p.get("dir", 0))
		var is_horizontal := (dir == 1)
		orientations.append(is_horizontal)
	return orientations


func load_level(level_s: String) -> void:

	if level_s.is_empty():
		return

	if not tile_layer:
		_init_board()

	_reset_board_state()
	
	_pieces.clear()

	var _all_letters := ""
	var chunks := level_s.split("&", false)

	for chunk in chunks:
		var part := chunk.strip_edges()
		if part == "":
			continue

		var fields := part.split("|", false)
		if fields.size() < 4:
			continue

		var dir := fields[0].to_int()
		var sx := fields[1].to_int()
		var sy := fields[2].to_int()
		var run := String(fields[3])

		if run.is_empty():
			continue

		_all_letters += run
		
		_pieces.append({
			"run": run.to_upper(),
			"dir": dir
		})

		var tile := _create_letter_tile(run, dir)
		tiles.append(tile)
		tile_layer.add_child(tile)

		var origin_cell := Vector2i(sx, sy)

		var span: Vector2i = _tile_span_in_cells(tile)
		var origin_pos := _cell_top_left_global(origin_cell)
		var tile_size_vec := Vector2(
			span.x * board_cell_size.x,
			span.y * board_cell_size.y
		)
		tile.global_position = origin_pos + (tile_size_vec * 0.5) - (tile.size * 0.5)

		var snapped_cell := snap_tile_to_board(tile)
		if snapped_cell.x != -1:
			tile.set_meta("cell", snapped_cell)

func _cell_index(col: int, row: int) -> int:
	return row * BOARD_COLS + col


func _cell_from_global_pos(global_pos: Vector2) -> Vector2i:
	if not is_instance_valid(board_grid):
		return Vector2i(-1, -1)
	
	var origin := board_grid.global_position
	var local := global_pos - origin
	
	var col := int(floor(local.x / board_cell_size.x))
	var row := int(floor(local.y / board_cell_size.y))
	
	if col < 0 or col >= BOARD_COLS or row < 0 or row >= BOARD_ROWS:
		return Vector2i(-1, -1)
	return Vector2i(col, row)


func _cell_center_global(cell: Vector2i) -> Vector2:
	var origin := board_grid.global_position
	return Vector2(
		origin.x + (cell.x + 0.5) * board_cell_size.x,
		origin.y + (cell.y + 0.5) * board_cell_size.y
	)

func _can_place_tile_at(tile: Control, cell: Vector2i, span: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0:
		return false
	if cell.x + span.x > BOARD_COLS or cell.y + span.y > BOARD_ROWS:
		return false

	for row_offset in range(span.y):
		for col_offset in range(span.x):
			var cx: int = cell.x + col_offset
			var cy: int = cell.y + row_offset

			var occupant: Control = board_occupied[cy][cx]
			if occupant != null and occupant != tile:
				return false

	return true

func snap_tile_to_board(tile: Control) -> Vector2i:
	var origin_cell := _best_origin_cell_for_tile(tile)
	if origin_cell.x == -1:
		return origin_cell

	var span: Vector2i = _tile_span_in_cells(tile)

	var has_conflict := not _can_place_tile_at(tile, origin_cell, span)

	if has_conflict:
		var candidates: Array[Vector2i] = [
			origin_cell + Vector2i(1, 0),
			origin_cell + Vector2i(-1, 0),
			origin_cell + Vector2i(0, 1),
			origin_cell + Vector2i(0, -1)
		]

		var found := false
		for cand in candidates:
			if _can_place_tile_at(tile, cand, span):
				origin_cell = cand
				found = true
				break

		if not found:
			return Vector2i(-1, -1)

	if not board_occupied.is_empty():
		for r in range(BOARD_ROWS):
			for c in range(BOARD_COLS):
				if board_occupied[r][c] == tile:
					board_occupied[r][c] = null

	for row_offset in range(span.y):
		for col_offset in range(span.x):
			var cx: int = origin_cell.x + col_offset
			var cy: int = origin_cell.y + row_offset
			board_occupied[cy][cx] = tile

	var board_origin := board_grid.global_position
	var top_left := board_origin + Vector2(
		float(origin_cell.x) * board_cell_size.x,
		float(origin_cell.y) * board_cell_size.y
	) + TILE_MARGIN

	tile.global_position = top_left

	return origin_cell

func _update_drag_preview(tile: Control) -> void:
	_clear_all_highlights()

	var origin_cell := _best_origin_cell_for_tile(tile)
	if origin_cell.x == -1:
		return

	var span: Vector2i = _tile_span_in_cells(tile)

	for row_offset in range(span.y):
		for col_offset in range(span.x):
			var cx: int = origin_cell.x + col_offset
			var cy: int = origin_cell.y + row_offset

			if cx < 0 or cx >= BOARD_COLS or cy < 0 or cy >= BOARD_ROWS:
				continue

			var occupant: Control = board_occupied[cy][cx]
			var is_conflict := (occupant != null and occupant != tile)

			var color := Color(1, 1, 1, 0.35)
			if is_conflict:
				color = Color(1, 0.2, 0.2, 0.5)

			_set_highlight_for_span_cell(cx, cy, origin_cell, span, color)

func highlight_cell(col: int, row: int, on: bool, color: Color = Color(1, 1, 1, 0.4)) -> void:
	if col < 0 or col >= BOARD_COLS or row < 0 or row >= BOARD_ROWS:
		return
	var idx := _cell_index(col, row)
	if idx < 0 or idx >= board_grid.get_child_count():
		return

	var cell := board_grid.get_child(idx) as Control
	var highlight := cell.get_node_or_null("Highlight") as PanelContainer
	if highlight == null:
		return

	var sb := highlight.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return

	if on:
		var c := color
		sb.bg_color = c
	else:
		var c := sb.bg_color
		c.a = 0.0
		sb.bg_color = c

func _clear_all_highlights() -> void:
	for child in board_grid.get_children():
		var highlight := child.get_node_or_null("Highlight") as PanelContainer
		if highlight:
			var sb := highlight.get_theme_stylebox("panel") as StyleBoxFlat
			if sb:
				var c := sb.bg_color
				c.a = 0.0
				sb.bg_color = c
