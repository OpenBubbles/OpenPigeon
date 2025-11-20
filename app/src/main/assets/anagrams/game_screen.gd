extends Control
signal time_up

const LETTER_BG: Texture2D = preload("res://anagrams/letter_bg.png")
const LETTER_VOID: Texture2D = preload("res://anagrams/letter_void.png")
const LETTER_PLACEHOLDER: Texture2D = preload("res://anagrams/placeholder.png")
const DICT_PATH := "res://global/gp_wg_en2.txt"

const TOTAL_TIME_SEC := 60

@export var letters: String = "ABCDEF"
@onready var picked_row: HBoxContainer = %VoidBox
@onready var shuffle_button: TextureButton = %ShuffleButton
@onready var letter_row: HBoxContainer = %LetterBox
@onready var enter_button: Button = %EnterButton
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

var selected_indices: Array[int] = []
var source_buttons: Array[BaseButton] = []
var picked_buttons: Array[BaseButton] = []

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

var tile_size: Vector2 = Vector2.ZERO
var remaining_time: int = TOTAL_TIME_SEC


func _ready() -> void:
	main_vbox.add_theme_constant_override("separation", 24)
	letter_row.add_theme_constant_override("separation", 8)
	picked_row.add_theme_constant_override("separation", 8)

	resized.connect(_on_resized)
	
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
	if not enter_button.pressed.is_connected(_on_enter_pressed):
		enter_button.pressed.connect(_on_enter_pressed)
	if not shuffle_button.pressed.is_connected(_on_shuffle_pressed):
		shuffle_button.pressed.connect(_on_shuffle_pressed)

	
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

	_create_source_buttons()
	_create_picked_slots()

	await get_tree().process_frame
	_update_tile_sizes()
	_update_ui()
	score = 0
	displayed_score = 0
	word_count = 0
	used_words.clear()
	word_history.clear()
	_update_word_score_labels()
	_compute_max_orders()
	seen_orders.clear()
	_register_current_order()

	remaining_time = TOTAL_TIME_SEC
	_update_timer_label()

	game_timer.stop()
	game_timer.start()

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

	var used_all_letters := (word.length() == letters.length())

	_show_word_feedback("%s +%d" % [word, points], true, used_all_letters)
	
func _apply_rainbow_flash(label: CanvasItem, total_time: float, cycles: int = 1) -> void:
	var colors: Array[Color] = [
		Color(1, 1, 1),      # white
		Color(1, 0, 0),      # red
		Color(1, 1, 0),      # yellow
		Color(0, 1, 0),      # green
		Color(0, 0, 1),      # blue
		Color(0.6, 0, 0.6),  # purple
		Color(1, 0, 1)       # pink
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

func _flash_void_row_invalid() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(1, 0, 0, 0.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.top_level = true
	overlay.size = picked_row.size
	overlay.global_position = picked_row.global_position
	add_child(overlay)

	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.35, 0.12)
	tween.tween_property(overlay, "color:a", 0.0, 0.12)
	tween.finished.connect(func():
		overlay.queue_free()
	)
	
func _compute_max_orders() -> void:
	max_orders = 1
	for i in letters.length():
		max_orders *= (i + 1)
	
func _get_order_key_from_tiles(tiles: Array) -> String:
	var key := ""
	for btn in tiles:
		if btn.get_child_count() > 0 and btn.get_child(0) is Label:
			var lbl := btn.get_child(0) as Label
			key += lbl.text
	return key

func _register_current_order() -> void:
	var tiles: Array = []
	for child in letter_row.get_children():
		var btn := _get_source_tile_from_child(child)
		if btn != null and btn in source_buttons:
			tiles.append(btn)

	var key := _get_order_key_from_tiles(tiles)
	if key != "":
		seen_orders[key] = true
		current_order_key = key
		_debug_print_order("REGISTER INITIAL ORDER", tiles, key)

func _shuffle_letters_string(s: String) -> String:
	var chars: Array = s.split("")
	chars.shuffle()
	return "".join(chars)

func _on_shuffle_pressed() -> void:
	if selected_indices.size() > 0:
		_reset_selection_back_to_source()

	if max_orders > 0 and seen_orders.size() >= max_orders:
		seen_orders.clear()

	var tiles: Array = []
	for child in letter_row.get_children():
		var btn := _get_source_tile_from_child(child)
		if btn != null and btn in source_buttons:
			tiles.append(btn)

	if tiles.is_empty():
		return

	var original_pos: Dictionary = {}
	for btn in tiles:
		var wrapper := _get_wrapper_for_button(btn)
		original_pos[btn] = wrapper.global_position

	var attempts := 0
	var key := ""
	var starting_key := current_order_key

	while true:
		for i in range(tiles.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = tiles[i]
			tiles[i] = tiles[j]
			tiles[j] = tmp

		key = _get_order_key_from_tiles(tiles)
		attempts += 1

		_debug_print_order("SHUFFLE CANDIDATE (attempt %d" % attempts + ")", tiles, key)

		if key != starting_key and not seen_orders.has(key):
			break

		if attempts > 32:
			print(">>> Resetting seen_orders after too many duplicate shuffles")
			seen_orders.clear()
			break

	for i in tiles.size():
		var wrapper := _get_wrapper_for_button(tiles[i])
		letter_row.move_child(wrapper, i)

	await get_tree().process_frame

	var target_pos: Dictionary = {}
	for btn in tiles:
		var wrapper := _get_wrapper_for_button(btn)
		target_pos[btn] = wrapper.global_position

	var ghosts: Array[Dictionary] = []
	for btn in tiles:
		var old_mod: Color = btn.modulate
		var faded_mod: Color = old_mod
		faded_mod.a = 0.0
		btn.modulate = faded_mod

		var ghost := TextureButton.new()
		ghost.texture_normal = LETTER_BG
		ghost.stretch_mode = TextureButton.STRETCH_SCALE
		ghost.ignore_texture_size = true
		ghost.focus_mode = Control.FOCUS_NONE
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.top_level = true
		ghost.size = tile_size
		ghost.custom_minimum_size = tile_size
		ghost.global_position = original_pos[btn]

		if btn.get_child_count() > 0 and btn.get_child(0) is Label:
			var src_lbl := btn.get_child(0) as Label
			var lbl := Label.new()
			lbl.text = src_lbl.text
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
			lbl.add_theme_font_size_override("font_size", int(tile_size.y * 0.6))
			lbl.add_theme_color_override("font_color", Color(0, 0, 0, 0.5))
			ghost.add_child(lbl)

		add_child(ghost)

		ghosts.append({
			"ghost": ghost,
			"btn": btn,
			"old_modulate": old_mod
		})

	var tween := create_tween()
	for pair in ghosts:
		var g: TextureButton = pair["ghost"]
		var b: TextureButton = pair["btn"]
		tween.parallel().tween_property(
			g,
			"global_position",
			target_pos[b],
			0.18
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	await tween.finished

	for pair in ghosts:
		var g: TextureButton = pair["ghost"]
		var b: TextureButton = pair["btn"]
		var old_mod: Color = pair["old_modulate"]

		if is_instance_valid(g):
			g.queue_free()
		if is_instance_valid(b):
			b.modulate = old_mod

	if key != "":
		seen_orders[key] = true
		current_order_key = key
		_debug_print_order("APPLIED SHUFFLE", tiles, key)

func _set_tile_shadow(btn: TextureButton, enabled: bool) -> void:
	if btn == null:
		return

	var wrapper := _get_wrapper_for_button(btn)
	if wrapper == btn:
		return

	var sb := wrapper.get_theme_stylebox("panel", "")
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		if enabled:
			flat.shadow_color.a = 0.35
			flat.shadow_size = 6
		else:
			flat.shadow_color.a = 0.0
			flat.shadow_size = 0
		wrapper.add_theme_stylebox_override("panel", flat)

func _show_word_feedback(text: String, is_correct: bool, used_all_letters: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 24)

	label.custom_minimum_size = Vector2(picked_row.size.x, 32.0)

	if is_correct:
		label.modulate = Color(1.0, 1.0, 1.0, 0.95)
	else:
		label.modulate = Color(1.0, 0.1, 0.1, 0.95)

	label.self_modulate = Color(1, 1, 1, 1)

	add_child(label)

	var start_pos := picked_row.global_position + Vector2(0.0, picked_row.size.y - 46.0)
	label.global_position = start_pos

	var end_pos := start_pos + Vector2(0.0, -160.0)

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

func _reset_selection_back_to_source() -> void:
	selected_indices.clear()
	_update_ui()

func _on_resized() -> void:
	_update_tile_sizes()

func get_final_score() -> int:
	return score

func get_word_count() -> int:
	return word_count

func get_word_history() -> Array:
	return word_history.duplicate(true)

func _create_source_buttons() -> void:
	for child in letter_row.get_children():
		child.queue_free()

	source_buttons.clear()
	source_buttons.resize(letters.length())

	var order: Array[int] = []
	for i in letters.length():
		order.append(i)
	order.shuffle()

	for idx in order:
		var wrapper := PanelContainer.new()
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.0)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		wrapper.add_theme_stylebox_override("panel", sb)

		var tile := TextureButton.new()
		tile.name = "Tile"
		tile.texture_normal = LETTER_BG
		tile.stretch_mode = TextureButton.STRETCH_SCALE
		tile.focus_mode = Control.FOCUS_NONE
		tile.ignore_texture_size = true
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile.set_anchors_preset(Control.PRESET_FULL_RECT)

		var label := Label.new()
		label.text = letters[idx]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.anchor_left = 0.0
		label.anchor_top = 0.0
		label.anchor_right = 1.0
		label.anchor_bottom = 1.0
		label.offset_left = 0.0
		label.offset_top = 0.0
		label.offset_right = 0.0
		label.offset_bottom = 0.0
		label.add_theme_color_override("font_color", Color(0, 0, 0, 0.5))

		tile.add_child(label)
		tile.pressed.connect(_on_source_letter_pressed.bind(idx))

		wrapper.add_child(tile)
		letter_row.add_child(wrapper)

		source_buttons[idx] = tile

func _get_wrapper_for_button(btn: BaseButton) -> Control:
	var parent := btn.get_parent()
	if parent is Control:
		return parent
	return btn


func _get_source_tile_from_child(node: Node) -> TextureButton:
	if node is TextureButton:
		return node
	if node is Control and node.get_child_count() > 0 and node.get_child(0) is TextureButton:
		return node.get_child(0) as TextureButton
	return null

func _create_picked_slots() -> void:
	for child in picked_row.get_children():
		child.queue_free()

	picked_buttons.clear()

	for i in letters.length():
		var wrapper := PanelContainer.new()
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.0)
		sb.shadow_color = Color(0, 0, 0, 0.0)
		sb.shadow_size = 0
		sb.shadow_offset = Vector2(0, 3)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		wrapper.add_theme_stylebox_override("panel", sb)

		var tile := TextureButton.new()
		tile.name = "Tile"
		tile.texture_normal = LETTER_VOID
		tile.stretch_mode = TextureButton.STRETCH_SCALE
		tile.focus_mode = Control.FOCUS_NONE
		tile.ignore_texture_size = true
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile.set_anchors_preset(Control.PRESET_FULL_RECT)

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.anchor_left = 0.0
		label.anchor_top = 0.0
		label.anchor_right = 1.0
		label.anchor_bottom = 1.0
		label.offset_left = 0.0
		label.offset_top = 0.0
		label.offset_right = 0.0
		label.offset_bottom = 0.0
		label.add_theme_color_override("font_color", Color(0, 0, 0, 0.5))

		tile.add_child(label)
		tile.disabled = true
		tile.pressed.connect(_on_picked_slot_pressed.bind(i))

		wrapper.add_child(tile)
		picked_row.add_child(wrapper)
		picked_buttons.append(tile)

func _update_tile_sizes() -> void:
	var count: int = letters.length()
	if count <= 0:
		return

	var total_width: float = letter_row.size.x
	if total_width <= 0.0:
		return

	var separation: float = float(letter_row.get_theme_constant("separation", "HBoxContainer"))
	var spacing_count: int = max(count - 1, 0)
	var total_spacing: float = separation * float(spacing_count)
	var side: float = max((total_width - total_spacing) / float(count), 16.0)

	side = min(side, 96.0)
	tile_size = Vector2(side, side)

	for btn in source_buttons:
		if btn == null:
			continue
		var wrapper := _get_wrapper_for_button(btn)
		wrapper.custom_minimum_size = tile_size
		btn.custom_minimum_size = tile_size

	for btn in picked_buttons:
		if btn == null:
			continue
		var wrapper := _get_wrapper_for_button(btn)
		wrapper.custom_minimum_size = tile_size
		btn.custom_minimum_size = tile_size

	var font_size := int(tile_size.y * 0.6)
	for btn in source_buttons:
		if btn == null:
			continue
		var label := btn.get_child(0) as Label
		label.add_theme_font_size_override("font_size", font_size)
	for btn in picked_buttons:
		if btn == null:
			continue
		var label := btn.get_child(0) as Label
		label.add_theme_font_size_override("font_size", font_size)

func _on_source_letter_pressed(letter_index: int) -> void:
	if letter_index in selected_indices:
		return
	if selected_indices.size() >= letters.length():
		return

	var source_btn := source_buttons[letter_index]
	var target_index := selected_indices.size()
	var target_btn := picked_buttons[target_index]

	await _animate_letter_move(source_btn, target_btn, letters[letter_index])

	selected_indices.append(letter_index)
	_update_ui()

func _on_enter_pressed() -> void:
	if selected_indices.size() < 3:
		return

	var word := ""
	for idx in selected_indices:
		word += letters[idx]
	var upper := word.to_upper()

	if not word_dict.has(upper):
		_flash_void_row_invalid()
		_show_word_feedback("%s (Not in the vocabulary)" % upper, false)
		_reset_selection_back_to_source()
		return

	if used_words.has(upper):
		_flash_void_row_invalid()
		_show_word_feedback("%s (Already Used)" % upper, false)
		_reset_selection_back_to_source()
		return

	var gained := _get_word_score(upper.length())
	if gained <= 0:
		_reset_selection_back_to_source()
		return

	used_words[upper] = true
	_add_score(gained, upper)
	_reset_selection_back_to_source()

func _get_word_score(wlen: int) -> int:
	if wlen == 3:
		return 100
	elif wlen == 4:
		return 400
	elif wlen == 5:
		return 1200
	elif wlen == 6:
		return 2000
	elif wlen == 7:
		return 3000
	return 0

func _on_picked_slot_pressed(slot_index: int) -> void:
	if slot_index >= selected_indices.size():
		return

	var letter_index := selected_indices[slot_index]
	var source_btn := source_buttons[letter_index]
	var picked_btn := picked_buttons[slot_index]

	await _animate_letter_move(picked_btn, source_btn, letters[letter_index])

	selected_indices.remove_at(slot_index)
	_update_ui()

func _animate_letter_move(from_btn: Control, to_btn: Control, letter: String) -> void:
	var from_button := from_btn as BaseButton
	var to_button := to_btn as BaseButton

	var from_wrapper := _get_wrapper_for_button(from_button)
	var to_wrapper := _get_wrapper_for_button(to_button)

	var original_texture: Texture2D = LETTER_BG
	if from_button is TextureButton:
		var tb := from_button as TextureButton
		original_texture = tb.texture_normal

		if from_button in source_buttons:
			tb.texture_normal = LETTER_PLACEHOLDER
		elif from_button in picked_buttons:
			tb.texture_normal = LETTER_VOID

		_set_tile_shadow(tb, false)

	if from_button.get_child_count() > 0 and from_button.get_child(0) is Label:
		var from_label := from_button.get_child(0) as Label
		from_label.text = ""

	if from_button is BaseButton:
		from_button.disabled = true

	var ghost_wrapper := Control.new()
	ghost_wrapper.top_level = true
	ghost_wrapper.size = tile_size
	ghost_wrapper.custom_minimum_size = tile_size
	ghost_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ghost_wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ghost_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost_wrapper.global_position = from_wrapper.global_position
	add_child(ghost_wrapper)

	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.3)
	shadow.anchor_left = 0.0
	shadow.anchor_top = 0.0
	shadow.anchor_right = 1.0
	shadow.anchor_bottom = 1.0
	shadow.offset_left = 0.0
	shadow.offset_top = 3.0
	shadow.offset_right = 0.0
	shadow.offset_bottom = 3.0
	ghost_wrapper.add_child(shadow)

	var ghost := TextureRect.new()
	ghost.texture = original_texture
	ghost.stretch_mode = TextureRect.STRETCH_SCALE
	ghost.ignore_texture_size = true
	ghost.anchor_left = 0.0
	ghost.anchor_top = 0.0
	ghost.anchor_right = 1.0
	ghost.anchor_bottom = 1.0
	ghost.offset_left = 0.0
	ghost.offset_top = 0.0
	ghost.offset_right = 0.0
	ghost.offset_bottom = 0.0
	ghost_wrapper.add_child(ghost)

	var label := Label.new()
	label.text = letter
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 0.0
	label.offset_top = 0.0
	label.offset_right = 0.0
	label.offset_bottom = 0.0

	var font_size := int(tile_size.y * 0.6)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0, 0, 0, 0.5))

	ghost_wrapper.add_child(label)

	var tween := create_tween()
	tween.tween_property(
		ghost_wrapper,
		"global_position",
		to_wrapper.global_position,
		0.15
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	await tween.finished
	ghost_wrapper.queue_free()

func _update_ui() -> void:
	for i in picked_buttons.size():
		var btn := picked_buttons[i] as TextureButton
		var label := btn.get_child(0) as Label

		var occupied := i < selected_indices.size()
		if occupied:
			var letter_index := selected_indices[i]
			btn.texture_normal = LETTER_BG
			label.text = letters[letter_index]
			btn.disabled = false
		else:
			btn.texture_normal = LETTER_VOID
			label.text = ""
			btn.disabled = true

		_set_tile_shadow(btn, occupied)

	for i in source_buttons.size():
		var src_btn := source_buttons[i] as TextureButton
		var label := src_btn.get_child(0) as Label

		var in_use := i in selected_indices

		if in_use:
			src_btn.texture_normal = LETTER_PLACEHOLDER
			label.text = ""
			src_btn.disabled = true
			_set_tile_shadow(src_btn, false)
		else:
			src_btn.texture_normal = LETTER_BG
			label.text = letters[i]
			src_btn.disabled = false
			_set_tile_shadow(src_btn, true)

	var can_submit := selected_indices.size() >= 3
	enter_button.disabled = not can_submit
	enter_button.self_modulate.a = 1.0 if can_submit else 0.3

func _on_game_timer_timeout() -> void:
	if remaining_time > 0:
		remaining_time -= 1
		_update_timer_label()

		if remaining_time <= 0:
			game_timer.stop()
			_on_time_up()


func _update_timer_label() -> void:
	var mins := remaining_time / 60
	var secs := remaining_time % 60
	timer_label.text = "[font_size={24px}]%02d:%02d[/font_size]" % [mins, secs]


func _on_time_up() -> void:
	for btn in source_buttons:
		btn.disabled = true
	for btn in picked_buttons:
		btn.disabled = true

	enter_button.disabled = true
	enter_button.self_modulate.a = 0.3

	emit_signal("time_up")

func _debug_print_order(label: String, tiles: Array, key: String) -> void:
	var letters_str := ""
	for btn in tiles:
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
