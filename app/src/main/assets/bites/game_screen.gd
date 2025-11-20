extends Control
signal time_up

const LETTER_BG: Texture2D = preload("res://anagrams/letter_bg.png")
const LETTER_VOID: Texture2D = preload("res://anagrams/letter_void.png")
const LETTER_PLACEHOLDER: Texture2D = preload("res://anagrams/placeholder.png")
const DICT_PATH := "res://global/gp_wg_en2.txt"

const TOTAL_TIME_SEC := 80

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
	_update_ui()
	score = 0
	displayed_score = 0
	word_count = 0
	used_words.clear()
	word_history.clear()
	_update_word_score_labels()
	_compute_max_orders()
	seen_orders.clear()

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

func get_final_score() -> int:
	return score

func get_word_count() -> int:
	return word_count

func get_word_history() -> Array:
	return word_history.duplicate(true)

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

	for i in source_buttons.size():
		var src_btn := source_buttons[i] as TextureButton
		var label := src_btn.get_child(0) as Label

		var in_use := i in selected_indices

		if in_use:
			src_btn.texture_normal = LETTER_PLACEHOLDER
			label.text = ""
			src_btn.disabled = true
		else:
			src_btn.texture_normal = LETTER_BG
			label.text = letters[i]
			src_btn.disabled = false

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
