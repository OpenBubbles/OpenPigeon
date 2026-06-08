extends BaseGame

@onready var intro_screen: Control = %IntroScreen
@onready var game_screen: Control = %GameScreen
@onready var score_screen: Control = %ScoreScreen
@onready var words_screen: Control = %WordsScreen
@onready var start_button: Button = %StartButton
@onready var sent_label: Label = %SentLabel
@onready var win_loss_label: Label = %WinLossLabel
@onready var main_score_box: PanelContainer = %MainScoreBoxContainer
@onready var player_score_box: PanelContainer = %PlayerScoreBoxContainer
@onready var opp_score_box: PanelContainer = %OppScoreBoxContainer
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var player_score_avatar_display = %PlayerScoreAvatarDisplay
@onready var player_word_list: VBoxContainer = %PlayerWordList
@onready var player_words_label: Label = %PlayerWordsLabel
@onready var player_score_label: Label = %PlayerScoreLabel
@onready var opp_word_list: VBoxContainer = %OppWordList
@onready var opp_words_label: Label = %OppWordsLabel
@onready var opp_score_label: Label = %OppScoreLabel
@onready var view_words_button: Button = %ViewWords
@onready var full_word_list: VBoxContainer = %FullWordList
@onready var back_button: TextureButton = %BackButton
@onready var words_scroll: ScrollContainer = %VScrollBar

const LETTER_BG: Texture2D = preload("res://anagrams/letter_bg.png")
const DICT_PATH := "res://global/gp_wg_en2.txt"
const MUSIC_STREAM := preload("res://global/audio/anagrams.ogg")

var _tear_rng := RandomNumberGenerator.new()

var screens: Array[Control] = []
var current_screen: int = 0
var sent_label_tween: Tween
var has_connected := false
var my_id := ""
var game_id := ""
var is_my_turn = false
var winner = null
var game_over := false
var game_ended := false
var win_loss_state = ""
var my_player := 0           # 0 spectator, 1 black, 2 white
var p1_score_s = ""
var p2_score_s = ""
var _all_words_cache: Array = []
var my_has_data := false
var _dict_words: Array[String] = []
var _dict_loaded := false
var _words_scroll: ScrollContainer = null
var _is_dragging_words := false
var _last_drag_pos := Vector2.ZERO

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
const LOG_TAG := "Anagrams"
var DEBUG_ANAGRAMS := false

func dbg(msg: String) -> void:
	if DEBUG_ANAGRAMS:
		OpLog.d(LOG_TAG, msg)
	
func _get_dev_data() -> String:
	return '{"isYourTurn": true,"player":"2","letters":"ANAGRAM","score1":"4100","words1":"5","words_list1":"LOSERS|LOSER|LOSE|LOSS|SOS","score2":"4000","words2":"4","words_list2":"LOSERS|LOSER|LOSE|LOSS","id":"dev"}'

func _on_game_ready() -> void:
	if not start_button.pressed.is_connected(_on_start_button_pressed):
		start_button.pressed.connect(_on_start_button_pressed)
	if not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)

	if not game_screen.time_up.is_connected(_on_game_time_up):
		game_screen.time_up.connect(_on_game_time_up)
	if not view_words_button.pressed.is_connected(_on_view_words_pressed):
		view_words_button.pressed.connect(_on_view_words_pressed)
	if is_instance_valid(full_word_list):
		full_word_list.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var parent := full_word_list.get_parent()
		if parent is ScrollContainer:
			_words_scroll = parent
			_words_scroll.drag_to_scroll = true
			_words_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
			if not _words_scroll.gui_input.is_connected(_on_words_scroll_gui_input):
				_words_scroll.gui_input.connect(_on_words_scroll_gui_input)
		else:
			OpLog.w(LOG_TAG, "full_word_list_parent_not_scroll_container drag_scroll_disabled")
	if is_instance_valid(words_scroll):
		words_scroll.drag_to_scroll = true
		words_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	if is_instance_valid(words_screen):
		words_screen.mouse_filter = Control.MOUSE_FILTER_STOP
		if not words_screen.gui_input.is_connected(_on_words_scroll_gui_input):
			words_screen.gui_input.connect(_on_words_scroll_gui_input)
	_apply_score_box_style(main_score_box)
	_apply_score_box_style(player_score_box)
	_apply_score_box_style(opp_score_box)

	_sync_waiting_animation()
	
	OpLog.i(LOG_TAG, [
		"game_ready letters=", game_screen.letters if is_instance_valid(game_screen) else "",
		" dict_path=", DICT_PATH
	])
	
func _sync_waiting_animation() -> void:
	if spectator_mode or game_over:
		stop_waiting_animation()
	elif my_has_data or not is_my_turn:
		start_waiting_animation()
	else:
		stop_waiting_animation()
	
func _on_words_scroll_gui_input(event: InputEvent) -> void:
	if _words_scroll == null:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_words_scroll.scroll_vertical -= 90
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_words_scroll.scroll_vertical += 90
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging_words = true
				_last_drag_pos = event.position
				_words_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
			else:
				_is_dragging_words = false
				_words_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
			get_viewport().set_input_as_handled()
			return

	elif event is InputEventMouseMotion and _is_dragging_words:
		_words_scroll.scroll_vertical -= int(event.relative.y)
		get_viewport().set_input_as_handled()
		return

	elif event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging_words = true
			_last_drag_pos = event.position
		else:
			_is_dragging_words = false
		get_viewport().set_input_as_handled()
		return

	elif event is InputEventScreenDrag and _is_dragging_words:
		_words_scroll.scroll_vertical -= int(event.relative.y)
		get_viewport().set_input_as_handled()
		return

func _set_game_data(raw_text: String) -> void:
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", raw_text])

	var res: Variant = JSON.parse_string(raw_text)
	var my_score: int = 0
	var my_words: int = 0
	var my_wordlist_s: String = ""
	var opp_score: int = 0
	var opp_words: int = 0
	var opp_wordlist_s: String = ""

	if typeof(res) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, [
			"set_game_data_parse_failed type=", typeof(res),
			" raw=", raw_text
		])
		return

	var d: Dictionary = res

	game_id = _get_first(d, "id", game_id)
	my_id = _get_first(d, "myPlayerId", my_id)

	if my_id == "":
		my_id = my_uuid

	var p1_id: String = _get_first(d, "player1", "")
	var p2_id: String = _get_first(d, "player2", "")
	var sender_s: String = _get_first(d, "player", "1")
	var letters_from_data: String = _get_first(d, "letters", "")

	OpLog.i(LOG_TAG, [
		"set_game_data_fields game_id=", game_id,
		" my_id=", my_id,
		" my_uuid=", my_uuid,
		" player1=", p1_id,
		" player2=", p2_id,
		" sender_player=", sender_s,
		" letters_len=", letters_from_data.length(),
		" keys=", d.keys()
	])

	if letters_from_data != "":
		game_screen.letters = letters_from_data
		_all_words_cache.clear()
		OpLog.i(LOG_TAG, ["letters_loaded letters=", letters_from_data])

	p1_score_s = _get_first(d, "score1", "")
	var p1_words_s: String = _get_first(d, "words1", "")
	var p1_wordlist_s: String = _get_first(d, "words_list1", "")

	p2_score_s = _get_first(d, "score2", "")
	var p2_words_s: String = _get_first(d, "words2", "")
	var p2_wordlist_s: String = _get_first(d, "words_list2", "")

	var p1_score: int = int(p1_score_s) if p1_score_s != "" else 0
	var p1_words: int = int(p1_words_s) if p1_words_s != "" else 0
	var p2_score: int = int(p2_score_s) if p2_score_s != "" else 0
	var p2_words: int = int(p2_words_s) if p2_words_s != "" else 0

	OpLog.i(LOG_TAG, [
		"score_fields p1_score=", p1_score_s,
		" p1_words=", p1_words_s,
		" p1_wordlist_len=", p1_wordlist_s.length(),
		" p2_score=", p2_score_s,
		" p2_words=", p2_words_s,
		" p2_wordlist_len=", p2_wordlist_s.length()
	])

	var is_your_turn = bool(res.get("isYourTurn", false))
	is_my_turn = is_your_turn

	var opponent_avatar_key := ""
	winner = _get_first(d, "winner", "")

	if winner != "":
		OpLog.event(LOG_TAG, ["winner_payload_present payload=", winner])

	var sender_player: int = clampi(int(sender_s), 1, 2)
	my_has_data = false

	var resolution_reason := ""

	if (p1_id != "" or p2_id != "") and my_id != "":
		if my_id == p1_id:
			my_player = 1
			opponent_avatar_key = "avatar2"
			my_has_data = (p1_wordlist_s != "" or p1_words_s != "" or p1_score_s != "")
			spectator_mode = false
			resolution_reason = "my_id_matches_player1"
		elif my_id == p2_id:
			my_player = 2
			opponent_avatar_key = "avatar1"
			my_has_data = (p2_wordlist_s != "" or p2_words_s != "" or p2_score_s != "")
			spectator_mode = false
			resolution_reason = "my_id_matches_player2"
		elif p1_id == "":
			my_player = 1
			opponent_avatar_key = "avatar2"
			my_has_data = (p1_wordlist_s != "" or p1_words_s != "" or p1_score_s != "")
			spectator_mode = false
			resolution_reason = "open_player1_slot"
		elif p2_id == "":
			my_player = 2
			opponent_avatar_key = "avatar1"
			my_has_data = (p2_wordlist_s != "" or p2_words_s != "" or p2_score_s != "")
			spectator_mode = false
			resolution_reason = "open_player2_slot"
		else:
			my_player = 0
			spectator_mode = true
			resolution_reason = "spectator_both_ids_filled"
	else:
		if my_player == 0:
			my_player = 1 if sender_player == 2 else 2
			spectator_mode = false
			resolution_reason = "no_ids_use_sender_inverse"
		else:
			spectator_mode = false
			resolution_reason = "no_ids_keep_existing_player"

	if not spectator_mode:
		is_my_turn = not my_has_data
		my_score = 0
		my_words = 0
		my_wordlist_s = ""
		opp_score = 0
		opp_words = 0
		opp_wordlist_s = ""

	OpLog.i(LOG_TAG, [
		"resolved_player my_player=", my_player,
		" spectator=", spectator_mode,
		" is_your_turn=", is_your_turn,
		" is_my_turn=", is_my_turn,
		" my_has_data=", my_has_data,
		" reason=", resolution_reason,
		" opponent_avatar_key=", opponent_avatar_key
	])

	if spectator_mode:
		is_my_turn = false
		OpLog.i(LOG_TAG, "spectator_mode_active")

		if res.has("avatar1"):
			var av1 = GameUtils._parse_avatar_string(res["avatar1"])
			player_avatar_display.call_deferred("update_avatar_from_data", av1)
			player_score_avatar_display.call_deferred("update_avatar_from_data", av1)

		if res.has("avatar2"):
			var av2 = GameUtils._parse_avatar_string(res["avatar2"])
			opp_avatar_display.call_deferred("update_avatar_from_data", av2)

		var p1_entries := _build_word_entries_from_string(p1_wordlist_s)
		_populate_scoreboard(true, p1_entries, p1_words, p1_score)

		var p2_entries := _build_word_entries_from_string(p2_wordlist_s)
		_populate_scoreboard(false, p2_entries, p2_words, p2_score)

		OpLog.i(LOG_TAG, [
			"spectator_scoreboard_loaded p1_entries=", p1_entries.size(),
			" p2_entries=", p2_entries.size()
		])

	if my_player == 1:
		my_score = p1_score
		my_words = p1_words
		my_wordlist_s = p1_wordlist_s
		opp_score = p2_score
		opp_words = p2_words
		opp_wordlist_s = p2_wordlist_s
	elif my_player == 2:
		my_score = p2_score
		my_words = p2_words
		my_wordlist_s = p2_wordlist_s
		opp_score = p1_score
		opp_words = p1_words
		opp_wordlist_s = p1_wordlist_s

	if my_wordlist_s != "":
		var my_entries := _build_word_entries_from_string(my_wordlist_s)
		_populate_scoreboard(true, my_entries, my_words, my_score)
		OpLog.i(LOG_TAG, ["my_scoreboard_loaded entries=", my_entries.size(), " score=", my_score])

	if opp_wordlist_s != "":
		var opp_entries := _build_word_entries_from_string(opp_wordlist_s)
		_populate_scoreboard(false, opp_entries, opp_words, opp_score)
		OpLog.i(LOG_TAG, ["opp_scoreboard_loaded entries=", opp_entries.size(), " score=", opp_score])

	if opponent_avatar_key != "" and res.has(opponent_avatar_key):
		var avatar_string = res[opponent_avatar_key]
		var opponent_data = GameUtils._parse_avatar_string(avatar_string)

		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	game_ended = await check_win()

	OpLog.i(LOG_TAG, [
		"set_game_data_check_win game_ended=", game_ended,
		" game_over=", game_over,
		" winner=", winner,
		" win_loss_state=", win_loss_state
	])

	_init_screens()
	_sync_waiting_animation()

	OpLog.i(LOG_TAG, [
		"set_game_data_done current_screen=", current_screen,
		" my_player=", my_player,
		" spectator=", spectator_mode,
		" my_has_data=", my_has_data,
		" is_my_turn=", is_my_turn,
		" game_over=", game_over
	])

func _load_dictionary() -> void:
	if _dict_loaded:
		return

	var f := FileAccess.open(DICT_PATH, FileAccess.READ)
	if f == null:
		OpLog.e(LOG_TAG, ["dictionary_open_failed path=", DICT_PATH])
		push_error("Could not open dictionary file: %s" % DICT_PATH)
		_dict_words = []
		_dict_loaded = true
		return

	var words: Array[String] = []

	while not f.eof_reached():
		var line := f.get_line().strip_edges()

		if line.is_empty():
			continue

		words.append(line.to_upper())

	f.close()

	_dict_words = words
	_dict_loaded = true

	OpLog.i(LOG_TAG, ["dictionary_loaded words=", _dict_words.size()])

func _make_letter_counts(pool: String) -> Dictionary:
	var counts := {}
	for c in pool:
		counts[c] = int(counts.get(c, 0)) + 1
	return counts
		
func _get_first(d: Dictionary, key: String, def: String = "") -> String:
	if not d.has(key):
		return def
	var v: Variant = d[key]
	if typeof(v) == TYPE_STRING:
		return v
	if typeof(v) == TYPE_ARRAY and (v as Array).size() > 0:
		return String((v as Array)[0])
	return def
		
func _apply_score_box_style(box: PanelContainer) -> void:
	if box == null:
		return

	if _tear_rng.seed == 0:
		_tear_rng.randomize()

	var sb := StyleBoxTexture.new()
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE

	sb.set_content_margin(SIDE_LEFT, 16.0)
	sb.set_content_margin(SIDE_RIGHT, 16.0)
	sb.set_content_margin(SIDE_TOP, 12.0)
	sb.set_content_margin(SIDE_BOTTOM, 12.0)

	box.add_theme_stylebox_override("panel", sb)

func _init_screens() -> void:
	screens = [intro_screen, game_screen, score_screen, words_screen]

	var should_show_intro := not game_over and not spectator_mode and not my_has_data
	current_screen = 0 if should_show_intro else 2

	OpLog.i(LOG_TAG, [
		"init_screens current_screen=", current_screen,
		" should_show_intro=", should_show_intro,
		" game_over=", game_over,
		" spectator=", spectator_mode,
		" my_has_data=", my_has_data
	])

	for i in screens.size():
		var node := screens[i]
		node.visible = (i == current_screen)
		node.position = Vector2.ZERO

func _switch_to_screen(next: int) -> void:
	if next == current_screen:
		return

	var from_node := screens[current_screen]
	var to_node := screens[next]
	var width := size.x
	var dir := 1
	if next < current_screen:
		dir = -1

	to_node.visible = true
	to_node.position = Vector2(width * dir, 0)

	var tween := create_tween()

	tween.tween_property(
		from_node, "position",
		Vector2(-width * dir, 0),
		0.25
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	tween.parallel().tween_property(
		to_node, "position",
		Vector2.ZERO,
		0.25
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished

	from_node.visible = false
	from_node.position = Vector2.ZERO
	current_screen = next
	
func _can_build_word_from_letters(word: String, letter_counts: Dictionary) -> bool:
	var counts := {}
	for k in letter_counts.keys():
		counts[k] = letter_counts[k]

	for c in word:
		if not counts.has(c):
			return false
		counts[c] -= 1
		if counts[c] < 0:
			return false
	return true
	
func _can_build_from_letters(word: String, pool: String) -> bool:
	var pool_counts: Dictionary = {}
	for c in pool:
		pool_counts[c] = int(pool_counts.get(c, 0)) + 1
	
	for c in word:
		if not pool_counts.has(c):
			return false
		var n: int = int(pool_counts[c]) - 1
		if n < 0:
			return false
		pool_counts[c] = n
	
	return true

	
func _word_entry_less(a: Dictionary, b: Dictionary) -> bool:
	var pa: int = int(a.get("points", 0))
	var pb: int = int(b.get("points", 0))
	if pa != pb:
		return pa > pb
	
	var wa: String = String(a.get("word", ""))
	var wb: String = String(b.get("word", ""))
	return wa < wb

func _populate_full_word_list() -> void:
	for child in full_word_list.get_children():
		child.queue_free()

	if _all_words_cache.is_empty():
		OpLog.i(LOG_TAG, "possible_words_cache_empty building")
		_all_words_cache = _build_all_possible_words()

	var all_words := _all_words_cache

	OpLog.i(LOG_TAG, ["possible_words_loaded count=", all_words.size()])

	var word_count := all_words.size()
	if is_instance_valid(view_words_button):
		view_words_button.text = "VIEW ALL WORDS (%d)" % word_count

	for entry in all_words:
		if not (entry is Dictionary) or not entry.has("word") or not entry.has("points"):
			continue

		var word := String(entry["word"])
		var points := int(entry["points"])

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var word_panel := PanelContainer.new()
		word_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		word_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

		var word_panel_style := StyleBoxFlat.new()
		word_panel_style.bg_color = Color(0.97, 0.78, 0.54)
		word_panel_style.corner_radius_top_left = 2
		word_panel_style.corner_radius_top_right = 2
		word_panel_style.corner_radius_bottom_left = 2
		word_panel_style.corner_radius_bottom_right = 2
		word_panel_style.set_content_margin(SIDE_LEFT, 8.0)
		word_panel_style.set_content_margin(SIDE_RIGHT, 8.0)
		word_panel_style.set_content_margin(SIDE_TOP, 2.0)
		word_panel_style.set_content_margin(SIDE_BOTTOM, 2.0)
		word_panel_style.shadow_color = Color(0, 0, 0, 0.25)
		word_panel_style.shadow_size = 4
		word_panel_style.shadow_offset = Vector2(0, 2)
		word_panel.add_theme_stylebox_override("panel", word_panel_style)

		var word_label := Label.new()
		word_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		word_label.text = word
		word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		word_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		word_label.add_theme_color_override("font_color", Color(0, 0, 0))
		word_panel.add_child(word_label)
		row.add_child(word_panel)

		var spacer := Control.new()
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

		var points_label := Label.new()
		points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		points_label.text = str(points)
		points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		points_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(points_label)

		full_word_list.add_child(row)
		
func _build_all_possible_words() -> Array:
	var result: Array = []

	if not is_instance_valid(game_screen):
		return result

	var letters_str: String = String(game_screen.letters).to_upper().strip_edges()
	if letters_str.is_empty():
		return result

	_load_dictionary()

	if _dict_words.is_empty():
		return result

	var rack_counts := _make_letter_counts(letters_str)
	var max_len := letters_str.length()

	for w in _dict_words:
		var wlen := w.length()
		if wlen < 3 or wlen > max_len:
			continue

		if not _can_build_word_from_letters(w, rack_counts):
			continue

		var pts := _compute_word_score(wlen)
		if pts <= 0:
			continue

		result.append({
			"word": w,
			"points": pts
		})

	result.sort_custom(Callable(self, "_word_entry_less"))
	return result

func _on_start_button_pressed() -> void:
	await _switch_to_screen(1)      # GameScreen
	game_screen.start_game()
	
func _on_back_button_pressed() -> void:
	await _switch_to_screen(2)      # ScoreScreen
	
func _on_view_words_pressed() -> void:
	await _switch_to_screen(3)      # View Words Screen

func _compute_word_score(wlen: int) -> int:
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


func _build_word_entries_from_string(words_s: String) -> Array:
	var result: Array = []
	if words_s == "":
		return result

	var parts := words_s.split("|", false)
	for w_raw in parts:
		var w := String(w_raw).strip_edges()
		if w == "":
			continue
		var pts := _compute_word_score(w.length())
		result.append({
			"word": w,
			"points": pts
		})
	return result

func _on_game_time_up() -> void:
	OpLog.event(LOG_TAG, [
		"time_up my_player=", my_player,
		" spectator=", spectator_mode,
		" final_score=", game_screen.get_final_score() if is_instance_valid(game_screen) else -1,
		" word_count=", game_screen.get_word_count() if is_instance_valid(game_screen) else -1
	])

	_populate_scoreboard(true)
	send_game()
	await _switch_to_screen(2)      # ScoreScreen

func send_game() -> void:
	await get_tree().process_frame

	if spectator_mode:
		OpLog.w(LOG_TAG, "send_game_blocked spectator=true")
		return

	var final_score: int = game_screen.get_final_score()
	var total_words: int = game_screen.get_word_count()
	var history: Array = game_screen.get_word_history()

	var word_strings: Array[String] = []

	for entry in history:
		if entry is Dictionary and entry.has("word"):
			word_strings.append(String(entry["word"]))

	var words_joined := "|".join(word_strings)

	var score_key := "score1" if my_player == 1 else "score2"
	var words_key := "words1" if my_player == 1 else "words2"
	var words_list_key := "words_list1" if my_player == 1 else "words_list2"

	var payload: Dictionary = {}

	payload[score_key] = str(final_score)
	payload[words_key] = str(total_words)
	payload[words_list_key] = words_joined

	var avatar_key := ("avatar1" if my_player == 1 else "avatar2")

	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	if game_ended and win_loss_state != "":
		payload["winner"] = my_id + "|" + win_loss_state
		OpLog.event(LOG_TAG, [
			"send_game_winner winner=", payload["winner"],
			" win_loss_state=", win_loss_state
		])

	my_has_data = true
	is_my_turn = false

	var json := JSON.stringify(payload)

	OpLog.event(LOG_TAG, [
		"send_game_out my_player=", my_player,
		" final_score=", final_score,
		" total_words=", total_words,
		" word_list_len=", words_joined.length(),
		" game_ended=", game_ended,
		" game_over=", game_over,
		" has_winner=", payload.has("winner"),
		" raw=", json
	])

	send_game_data(json)

	game_ended = await check_win()

	if not game_ended:
		OpLog.d(LOG_TAG, "send_game_no_win_detected")
	else:
		OpLog.event(LOG_TAG, [
			"send_game_after_check_win game_ended=", game_ended,
			" winner=", winner,
			" win_loss_state=", win_loss_state
		])

	if not game_over:
		play_sent_animation()

func check_win() -> bool:
	OpLog.d(LOG_TAG, [
		"check_win_start game_over=", game_over,
		" p1_score=", p1_score_s,
		" p2_score=", p2_score_s,
		" my_player=", my_player,
		" spectator=", spectator_mode
	])

	if game_over:
		OpLog.d(LOG_TAG, "check_win_skipped already_game_over")
		return false

	if p1_score_s == "" or p2_score_s == "":
		return false

	var p1_has = false
	var p2_has = false

	if p1_score_s.to_int() > p2_score_s.to_int():
		p1_has = true
	elif p1_score_s.to_int() < p2_score_s.to_int():
		p2_has = true
	else:
		p1_has = true
		p2_has = true

	if p1_has and not p2_has:
		winner = "1"
	elif p2_has and not p1_has:
		winner = "-1"
	else:
		winner = "0"

	game_over = true

	OpLog.event(LOG_TAG, [
		"win_condition_met p1_score=", p1_score_s,
		" p2_score=", p2_score_s,
		" winner=", winner
	])

	_populate_full_word_list()
	view_words_button.visible = true

	if winner != "":
		if winner == "0":
			win_loss_label.text = "DRAW!"
			win_loss_state = "0"
			win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
			OpLog.event(LOG_TAG, "final_tally_draw")
		else:
			var you_win: bool = (not spectator_mode) and (
				(my_player == 1 and winner == "1") or
				(my_player == 2 and winner == "-1")
			)

			if you_win:
				GameUtils._show_win_burst(player_score_avatar_display)
				win_loss_label.text = "YOU WIN!"
				win_loss_state = "1"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
				OpLog.event(LOG_TAG, "final_tally_local_win")
			else:
				if spectator_mode:
					GameUtils._show_win_burst(player_score_avatar_display if winner == "1" else opp_avatar_display)
					var displayedwin = "1" if winner == "1" else "2"
					win_loss_label.text = "Player %s Wins!" % displayedwin
					win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
					win_loss_state = "-1"

					OpLog.event(LOG_TAG, [
						"final_tally_spectator displayed_winner=", displayedwin
					])
				else:
					GameUtils._show_win_burst(opp_avatar_display)
					win_loss_label.text = "YOU LOSE"
					win_loss_state = "-1"
					win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
					OpLog.event(LOG_TAG, "final_tally_local_loss")

		OpLog.event(LOG_TAG, [
			"show_result winner=", winner,
			" win_loss_state=", win_loss_state,
			" text=", win_loss_label.text,
			" p1_score=", p1_score_s,
			" p2_score=", p2_score_s,
			" my_player=", my_player,
			" spectator=", spectator_mode
		])

		win_loss_label.visible = true
		await get_tree().process_frame
		win_loss_label.scale = Vector2.ZERO
		win_loss_label.pivot_offset = win_loss_label.size / 2

		var tween_in := create_tween()
		tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

		return true

	return true

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		OpLog.w(LOG_TAG, "sent_animation_missing_label")
		return

	if sent_label_tween and sent_label_tween.is_running():
		sent_label_tween.kill()

	sent_label_tween = create_tween().set_parallel(false)

	sent_label.text = "Sent"
	sent_label.visible = true
	sent_label.modulate.a = 0.0
	sent_label.scale = Vector2.ONE
	sent_label.pivot_offset = sent_label.get_size() / 2.0

	sent_label_tween.tween_property(sent_label, "modulate:a", 1.0, 0.3)
	sent_label_tween.tween_interval(0.6)
	sent_label_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.text = "Sent ✔"
	)
	sent_label_tween.tween_interval(2.0)
	sent_label_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)

	sent_label_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0

		_sync_waiting_animation()
	)

func _populate_scoreboard(
	is_player: bool = true,
	word_entries: Array = [],
	total_words_override: int = -1,
	final_score_override: int = -1
) -> void:
	var target_list: VBoxContainer = player_word_list if is_player else opp_word_list
	var target_words_label: Label = player_words_label if is_player else opp_words_label
	var target_score_label: Label = player_score_label if is_player else opp_score_label
	
	for child in target_list.get_children():
		child.queue_free()

	var words: Array
	var total_words: int
	var final_score: int

	if is_player and word_entries.is_empty() and total_words_override < 0 and final_score_override < 0:
		words = game_screen.get_word_history()
		total_words = game_screen.get_word_count()
		final_score = game_screen.get_final_score()
	else:
		words = word_entries

		if total_words_override >= 0:
			total_words = total_words_override
		else:
			total_words = words.size()

		if final_score_override >= 0:
			final_score = final_score_override
		else:
			var sum := 0
			for entry in words:
				if entry is Dictionary and entry.has("points"):
					sum += int(entry["points"])
			final_score = sum

	for entry in words:
		if not (entry is Dictionary) or not entry.has("word") or not entry.has("points"):
			continue

		var word := String(entry["word"])
		var points := int(entry["points"])

		var row := HBoxContainer.new()

		var word_panel := PanelContainer.new()
		word_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

		var word_panel_style := StyleBoxFlat.new()
		word_panel_style.bg_color = Color(0.97, 0.78, 0.54)
		word_panel_style.corner_radius_top_left = 2
		word_panel_style.corner_radius_top_right = 2
		word_panel_style.corner_radius_bottom_left = 2
		word_panel_style.corner_radius_bottom_right = 2
		word_panel_style.set_content_margin(SIDE_LEFT, 8.0)
		word_panel_style.set_content_margin(SIDE_RIGHT, 8.0)
		word_panel_style.set_content_margin(SIDE_TOP, 2.0)
		word_panel_style.set_content_margin(SIDE_BOTTOM, 2.0)
		word_panel_style.shadow_color = Color(0, 0, 0, 0.25)
		word_panel_style.shadow_size = 4
		word_panel_style.shadow_offset = Vector2(0, 2)
		word_panel.add_theme_stylebox_override("panel", word_panel_style)

		var word_label := Label.new()
		word_label.text = word
		word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		word_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		word_label.add_theme_color_override("font_color", Color(0, 0, 0))
		var base_font := word_label.get_theme_font("font")
		var bold_var := FontVariation.new()
		bold_var.base_font = base_font
		bold_var.variation_embolden = 1.2
		word_label.add_theme_font_size_override("font_size", 18)
		word_label.add_theme_font_override("font", bold_var)
		word_panel.add_child(word_label)
		row.add_child(word_panel)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

		var points_label := Label.new()
		points_label.text = str(points)
		points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		points_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		points_label.add_theme_font_size_override("font_size", 20)
		row.add_child(points_label)

		target_list.add_child(row)

	target_words_label.text = "WORDS: %d" % total_words
	target_score_label.text = "SCORE: %04d" % final_score
	
	if is_player and not spectator_mode:
		if my_player == 1:
			p1_score_s = str(final_score)
		elif my_player == 2:
			p2_score_s = str(final_score)
