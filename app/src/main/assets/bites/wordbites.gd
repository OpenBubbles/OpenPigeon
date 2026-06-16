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

const LETTER_BG: Texture2D = preload("res://anagrams/letter_bg.png")
const MUSIC_STREAM := preload("res://global/audio/wordbites.ogg")
const DICT_PATH := "res://global/gp_wg_en2.txt"

class TrieNode:
	var children: Dictionary = {}
	var is_word: bool = false

var _dictionary_trie_root: TrieNode = null

var _tear_rng := RandomNumberGenerator.new()
var found_word_keys: Dictionary = {}
var screens: Array[Control] = []
var current_screen: int = 0
var sent_label_tween: Tween
var game_id := ""
var winner = null
var game_over := false
var game_ended := false
var win_loss_state = ""
var p1_score_s = ""
var p2_score_s = ""
var player
var possible_word_count: int = 0
var possible_words_count_label: Label = null
var _possible_words_cache: Array = []
var _words_cache_ready := false
var _words_computing := false
var _cached_possible_level := ""
var _words_compute_level := ""
var _words_loading_overlay: Control = null
var _words_loading_tween: Tween = null
var my_has_data := false

var _words_scroll_container: ScrollContainer = null
var _words_pointer_down := false
var _words_is_dragging := false
var _words_last_drag_pos := Vector2.ZERO

var _word_popup_pointer_down := false
var _word_popup_dragging := false
var _word_popup_last_pos := Vector2.ZERO

const WORDS_DRAG_THRESHOLD := 8.0

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
const LOG_TAG := "WordBites"
var DEBUG_WORDBITES := false

func dbg(msg: String) -> void:
	if DEBUG_WORDBITES:
		OpLog.d(LOG_TAG, msg)
	
func _get_dev_data() -> String:
	return '{"sender":"BB938756-D694-4421-9642-82CB312C13B0nbdTdV","version":"5","tver":"5","ios":"26.4","caption":"Lets play Word Bites!","id":"DlPri7dhRO5Nb3a2","player":"2","player2":"BB938756-D694-4421-9642-82CB312C13B0nbdTdV","letters":"AAA","lang":"en","mode":"1","level":"1|0|0|NG&1|6|4|RO&2|2|3|NY&2|0|3|FU&1|6|8|TE&0|6|6|U&0|6|0|I&0|4|1|U&0|0|8|L&0|3|6|K&0|7|2|P","avatar2":"body,2|eyes,0|mouth,3|acc,0|wins,0|bg_color,0.291679,0.246671,0.464589|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,3|clothes,1|hair_color,0.000000,0.000000,0.000000|clothes_color,0.922711,0.395143,0.779568","game":"wordbites","game_name":"Word Bites","num":"1","build":"LR5rAXhOt"}'
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Wordbites"
	
func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Word Bites[/b][/font_size]

[font_size={24px}][b]Goal[/b][/font_size]
[font_size={18px}]
Find as many valid words as possible before time runs out.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• Use the available letter pieces to build words.
• Longer words are worth more points.
• When the timer ends, your score and word list are sent.
• Once both players finish, the higher score wins.
[/font_size]
"""

func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	if is_instance_valid(start_button):
		if not start_button.pressed.is_connected(_on_start_button_pressed):
			start_button.pressed.connect(_on_start_button_pressed)

	if is_instance_valid(back_button):
		if not back_button.pressed.is_connected(_on_back_button_pressed):
			back_button.pressed.connect(_on_back_button_pressed)

	if is_instance_valid(game_screen):
		if not game_screen.time_up.is_connected(_on_game_time_up):
			game_screen.time_up.connect(_on_game_time_up)

	if is_instance_valid(view_words_button):
		if not view_words_button.pressed.is_connected(_on_view_words_pressed):
			view_words_button.pressed.connect(_on_view_words_pressed)

	if is_instance_valid(full_word_list):
		full_word_list.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var parent := full_word_list.get_parent()
		var grandparent := parent.get_parent() if parent != null else null

		if grandparent is ScrollContainer:
			_words_scroll_container = grandparent as ScrollContainer

	_apply_score_box_style(main_score_box)
	_apply_score_box_style(player_score_box)
	_apply_score_box_style(opp_score_box)

	_ensure_possible_words_count_label()
	_update_possible_words_count_label()

func _set_game_data(raw_text: String) -> void:
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", raw_text])

	var res: Variant = JSON.parse_string(raw_text)
	if typeof(res) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, [
			"set_game_data_parse_failed type=", typeof(res),
			" raw=", raw_text
		])
		return

	var d: Dictionary = res

	game_over = false
	game_ended = false
	win_loss_state = ""
	winner = ""
	my_has_data = false

	stop_waiting_animation()

	if is_instance_valid(win_loss_label):
		win_loss_label.visible = false
		win_loss_label.text = ""
		win_loss_label.scale = Vector2.ONE
		win_loss_label.modulate.a = 1.0

	game_id = _get_first(d, "id", game_id)

	var p1_id: String = _get_first(d, "player1", "")
	var p2_id: String = _get_first(d, "player2", "")
	var sender_s: String = _get_first(d, "player", "1")
	var level_s: String = _get_first(d, "level", "")
	var winner_payload: String = _get_first(d, "winner", "")
	var sender_player: int = clampi(int(sender_s), 1, 2)

	OpLog.i(LOG_TAG, [
		"set_game_data_fields game_id=", game_id,
		" my_uuid=", my_uuid,
		" player1=", p1_id,
		" player2=", p2_id,
		" sender_player=", sender_player,
		" level_len=", level_s.length(),
		" has_winner=", winner_payload != "",
		" keys=", d.keys()
	])

	if level_s != "":
		if game_screen.has_method("load_level"):
			var level_changed: bool = level_s != _cached_possible_level

			game_screen.load_level(level_s)

			OpLog.i(LOG_TAG, [
				"level_loaded len=", level_s.length(),
				" changed=", level_changed
			])

			if level_changed:
				_cached_possible_level = level_s
				_words_cache_ready = false
				_possible_words_cache.clear()

				if not _words_computing:
					call_deferred("_begin_background_word_precompute")
		else:
			OpLog.w(LOG_TAG, "game_screen_missing_load_level")

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

	var opponent_avatar_key := ""

	if my_uuid != "":
		if p1_id != "" and my_uuid == p1_id:
			player = 1
			spectator_mode = false
			opponent_avatar_key = "avatar2" if p2_id != "" else ""

		elif p2_id != "" and my_uuid == p2_id:
			player = 2
			spectator_mode = false
			opponent_avatar_key = "avatar1" if p1_id != "" else ""

		elif p1_id == "" and p2_id != "":
			player = 1
			spectator_mode = false
			opponent_avatar_key = "avatar2"

		elif p2_id == "" and p1_id != "":
			player = 2
			spectator_mode = false
			opponent_avatar_key = "avatar1"

		elif p1_id != "" and p2_id != "":
			player = 0
			spectator_mode = true

		else:
			player = 1 if sender_player == 2 else 2
			spectator_mode = false
			opponent_avatar_key = "avatar1" if player == 2 else "avatar2"
	else:
		player = 1 if sender_player == 2 else 2
		spectator_mode = false
		opponent_avatar_key = "avatar1" if player == 2 else "avatar2"

	if not spectator_mode:
		if player == 1:
			my_has_data = p1_score_s != "" or p1_words_s != "" or p1_wordlist_s != ""
		elif player == 2:
			my_has_data = p2_score_s != "" or p2_words_s != "" or p2_wordlist_s != ""

	OpLog.i(LOG_TAG, [
		"resolved_player player=", player,
		" spectator=", spectator_mode,
		" my_has_data=", my_has_data,
		" opponent_avatar_key=", opponent_avatar_key
	])

	if spectator_mode:
		OpLog.i(LOG_TAG, "spectator_mode_enabled")

		if d.has("avatar1"):
			var av1 = GameUtils._parse_avatar_string(d["avatar1"])
			if is_instance_valid(player_avatar_display):
				player_avatar_display.call_deferred("update_avatar_from_data", av1)
			if is_instance_valid(player_score_avatar_display):
				player_score_avatar_display.call_deferred("update_avatar_from_data", av1)

		if d.has("avatar2"):
			var av2 = GameUtils._parse_avatar_string(d["avatar2"])
			if is_instance_valid(opp_avatar_display):
				opp_avatar_display.call_deferred("update_avatar_from_data", av2)

		var p1_entries := _build_word_entries_from_string(p1_wordlist_s)
		_populate_scoreboard(true, p1_entries, p1_words, p1_score)

		var p2_entries := _build_word_entries_from_string(p2_wordlist_s)
		_populate_scoreboard(false, p2_entries, p2_words, p2_score)

		OpLog.i(LOG_TAG, [
			"spectator_scoreboard_loaded p1_entries=", p1_entries.size(),
			" p2_entries=", p2_entries.size()
		])
	else:
		var my_score: int = 0
		var my_words: int = 0
		var my_wordlist_s: String = ""
		var opp_score: int = 0
		var opp_words: int = 0
		var opp_wordlist_s: String = ""

		if player == 1:
			my_score = p1_score
			my_words = p1_words
			my_wordlist_s = p1_wordlist_s
			opp_score = p2_score
			opp_words = p2_words
			opp_wordlist_s = p2_wordlist_s
		elif player == 2:
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

	if opponent_avatar_key != "" and d.has(opponent_avatar_key):
		var avatar_string = d[opponent_avatar_key]
		var opponent_data = GameUtils._parse_avatar_string(avatar_string)

		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	if winner_payload != "":
		OpLog.event(LOG_TAG, ["winner_payload_received payload=", winner_payload])
		_apply_winner_payload(winner_payload, p1_id, p2_id)
	else:
		game_ended = check_win()

	_init_screens()

	if game_over:
		stop_waiting_animation()
	elif my_has_data:
		start_waiting_animation()
	else:
		stop_waiting_animation()

	OpLog.i(LOG_TAG, [
		"set_game_data_done player=", player,
		" spectator=", spectator_mode,
		" my_has_data=", my_has_data,
		" game_over=", game_over,
		" game_ended=", game_ended,
		" winner=", winner
	])

func _is_piece_horizontal_idx(idx: int, orientations: Array) -> bool:
	if idx < 0 or idx >= orientations.size():
		return false
	var o: Variant = orientations[idx]
	match typeof(o):
		TYPE_BOOL:
			return bool(o)
		TYPE_INT:
			return int(o) == 1
		TYPE_STRING:
			var s := String(o).strip_edges().to_upper()
			if s == "H" or s == "HOR" or s == "HORIZONTAL":
				return true
			if s == "V" or s == "VER" or s == "VERTICAL":
				return false
			if s == "1":
				return true
			if s == "2" or s == "0":
				return false
			return false

		_:
			return false
			
func _word_respects_orientation(word: String, piece_runs: Array[String]) -> bool:
	var orientations: Array = []
	if game_screen and game_screen.has_method("get_letter_piece_orientations"):
		orientations = game_screen.get_letter_piece_orientations()
	if orientations.size() != piece_runs.size():
		return true

	var w := word.to_upper()
	return _can_form_with_orientation(w, piece_runs, orientations, true) \
		or _can_form_with_orientation(w, piece_runs, orientations, false)

func _can_form_with_orientation(
	word: String,
	piece_runs: Array[String],
	orientations: Array,
	want_horizontal: bool
) -> bool:
	var n: int = piece_runs.size()
	if n == 0:
		return false

	var wlen := word.length()
	if want_horizontal and wlen > 8:
		return false
	if (not want_horizontal) and wlen > 9:
		return false

	var runs_upper: Array[String] = []
	runs_upper.resize(n)
	for i in range(n):
		runs_upper[i] = String(piece_runs[i]).to_upper()

	var memo: Dictionary = {}
	var word_upper := word.to_upper()

	return _can_form_with_orientation_dfs(
		word_upper,
		runs_upper,
		orientations,
		want_horizontal,
		0,
		0,
		memo
	)
	
func _can_form_with_orientation_dfs(
	word: String,
	runs_upper: Array[String],
	orientations: Array,
	want_horizontal: bool,
	pos: int,
	used_mask: int,
	memo: Dictionary
) -> bool:
	var n: int = runs_upper.size()

	if pos == word.length():
		return true

	var hv := "H" if want_horizontal else "V"
	var key := "%d|%d|%s" % [pos, used_mask, hv]
	if memo.has(key):
		return false

	var remaining: int = word.length() - pos
	if remaining <= 0:
		return true

	var target_char: String = word[pos]

	for i in range(n):
		var bit: int = 1 << i
		if (used_mask & bit) != 0:
			continue

		var run_str: String = runs_upper[i]
		var is_h: bool = _is_piece_horizontal_idx(i, orientations)
		var aligned: bool = (want_horizontal and is_h) or (not want_horizontal and not is_h)

		if aligned and run_str.length() > 1:
			var blen: int = run_str.length()
			if pos + blen <= word.length() and word.substr(pos, blen) == run_str:
				if _can_form_with_orientation_dfs(
					word,
					runs_upper,
					orientations,
					want_horizontal,
					pos + blen,
					used_mask | bit,
					memo
				):
					return true

	for i in range(n):
		var bit2: int = 1 << i
		if (used_mask & bit2) != 0:
			continue

		var run2: String = runs_upper[i]
		var is_h2: bool = _is_piece_horizontal_idx(i, orientations)
		var aligned2: bool = (want_horizontal and is_h2) or (not want_horizontal and not is_h2)

		if aligned2 and run2.length() > 1:
			continue

		var can_supply_char := false

		if run2.length() == 1:
			can_supply_char = (run2[0] == target_char)
		else:
			for k in range(run2.length()):
				if run2[k] == target_char:
					can_supply_char = true
					break

		if can_supply_char:
			if _can_form_with_orientation_dfs(
				word,
				runs_upper,
				orientations,
				want_horizontal,
				pos + 1,
				used_mask | bit2,
				memo
			):
				return true

	memo[key] = true
	return false
	
func _input(event: InputEvent) -> void:
	if current_screen != 3:
		return

	if not is_instance_valid(words_screen) or not words_screen.visible:
		return

	_on_words_list_scroll_gui_input(event)

func _on_words_list_scroll_gui_input(event: InputEvent) -> void:
	if _words_scroll_container == null:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_words_pointer_down = true
			_words_is_dragging = false
			_words_last_drag_pos = touch.position
		else:
			_words_pointer_down = false
			_words_is_dragging = false
		return

	if event is InputEventScreenDrag and _words_pointer_down:
		var drag := event as InputEventScreenDrag

		if not _words_is_dragging:
			if drag.position.distance_to(_words_last_drag_pos) >= WORDS_DRAG_THRESHOLD:
				_words_is_dragging = true

		if _words_is_dragging:
			_words_scroll_container.scroll_vertical -= int(drag.relative.y)
			_update_active_word_popup_position()

		_words_last_drag_pos = drag.position
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_words_scroll_container.scroll_vertical -= 48
			_update_active_word_popup_position()
			return

		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_words_scroll_container.scroll_vertical += 48
			_update_active_word_popup_position()
			return

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_words_pointer_down = true
				_words_is_dragging = false
				_words_last_drag_pos = mb.position
			else:
				_words_pointer_down = false
				_words_is_dragging = false
		return

	if event is InputEventMouseMotion and _words_pointer_down:
		var mm := event as InputEventMouseMotion

		if not _words_is_dragging:
			if mm.position.distance_to(_words_last_drag_pos) >= WORDS_DRAG_THRESHOLD:
				_words_is_dragging = true

		if _words_is_dragging:
			_words_scroll_container.scroll_vertical -= int(mm.relative.y)
			_update_active_word_popup_position()

		_words_last_drag_pos = mm.position

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

func _word_entry_less(a: Dictionary, b: Dictionary) -> bool:
	var pa: int = int(a.get("points", 0))
	var pb: int = int(b.get("points", 0))
	if pa != pb:
		return pa > pb
	
	var wa: String = String(a.get("word", ""))
	var wb: String = String(b.get("word", ""))
	return wa < wb
	
func _ensure_possible_words_count_label() -> void:
	if is_instance_valid(possible_words_count_label):
		return

	if not is_instance_valid(words_screen):
		return

	var title_label: Label = null
	var labels := words_screen.find_children("*", "Label", true, false)

	for node in labels:
		var lbl := node as Label
		if lbl != null and lbl.text.strip_edges().to_upper() == "POSSIBLE WORDS":
			title_label = lbl
			break

	if title_label == null:
		OpLog.w(LOG_TAG, "possible_words_title_label_not_found")
		return

	possible_words_count_label = Label.new()
	possible_words_count_label.name = "PossibleWordsCountLabel"
	possible_words_count_label.text = "Words: 0"
	possible_words_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	possible_words_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	possible_words_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	possible_words_count_label.add_theme_font_size_override("font_size", 18)

	var parent := title_label.get_parent()

	if parent is BoxContainer:
		var title_index := title_label.get_index()
		parent.add_child(possible_words_count_label)
		parent.move_child(possible_words_count_label, title_index + 1)
	else:
		title_label.add_child(possible_words_count_label)
		possible_words_count_label.anchor_left = 0.0
		possible_words_count_label.anchor_right = 1.0
		possible_words_count_label.anchor_top = 1.0
		possible_words_count_label.anchor_bottom = 1.0
		possible_words_count_label.offset_left = 0.0
		possible_words_count_label.offset_right = 0.0
		possible_words_count_label.offset_top = 2.0
		possible_words_count_label.offset_bottom = 26.0


func _update_possible_words_count_label() -> void:
	_ensure_possible_words_count_label()

	if not is_instance_valid(possible_words_count_label):
		return

	possible_words_count_label.text = "Words: %d" % possible_word_count

func _populate_full_word_list_from_cache() -> void:
	for child in full_word_list.get_children():
		child.queue_free()

	if not _words_cache_ready:
		_show_words_loading()
		await _compute_words_async()

	var found_words: Dictionary = {}
	if is_instance_valid(game_screen) and game_screen.has_method("get_word_history"):
		for entry in game_screen.get_word_history():
			if entry is Dictionary and entry.has("word"):
				var wstr: String = String(entry["word"]).strip_edges().to_upper()
				found_words[wstr] = true

	possible_word_count = _possible_words_cache.size()
	_update_possible_words_count_label()

	if is_instance_valid(view_words_button):
		view_words_button.text = "VIEW ALL WORDS"

	var added: int = 0
	for entry in _possible_words_cache:
		var word: String = String(entry["word"])
		var points: int = int(entry["points"])
		var was_found: bool = found_words.has(word)

		_add_word_row_with_highlight(word, points, was_found)

		added += 1
		if added % WORDS_LIST_ROW_BATCH_SIZE == 0:
			await get_tree().process_frame

	_hide_words_loading()

func _add_word_row_with_highlight(word: String, points: int, was_found: bool) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var word_panel := PanelContainer.new()
	word_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	word_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	word_panel.set_meta("word", word)

	var word_panel_style := StyleBoxFlat.new()
	word_panel_style.bg_color = Color(0.97, 0.78, 0.54)
	if was_found:
		word_panel_style.bg_color = Color(1.0, 0.86, 0.40)

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

	word_panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				var old_overlay := get_node_or_null("WordPopupOverlay")
				if old_overlay and old_overlay.has_meta("word") and String(old_overlay.get_meta("word")) == word:
					return

				_show_word_popup(word, word_panel)
	)

	full_word_list.add_child(row)
	
func _position_word_popup(overlay: Control, clamp_y: bool) -> Vector2:
	if not is_instance_valid(overlay):
		return Vector2.ZERO

	var popup := overlay.get_node_or_null("WordPopup") as Control
	var pointer := overlay.get_node_or_null("Pointer") as Control
	var close_btn := overlay.get_node_or_null("CloseButton") as Control

	if not is_instance_valid(popup) or not is_instance_valid(pointer) or not is_instance_valid(close_btn):
		return Vector2.ZERO

	var anchor: Control = null
	if overlay.has_meta("anchor"):
		var anchor_var: Variant = overlay.get_meta("anchor")
		if anchor_var is Control:
			anchor = anchor_var as Control

	if not is_instance_valid(anchor) or not anchor.is_inside_tree():
		overlay.queue_free()
		return Vector2.ZERO

	var anchor_rect: Rect2 = anchor.get_global_rect()
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var margin: float = 12.0
	var popup_rect: Rect2 = popup.get_global_rect()
	var popup_size: Vector2 = popup_rect.size

	var open_on_left: bool = false
	var right_space: float = viewport_rect.size.x - (anchor_rect.end.x + margin)
	if popup_size.x > right_space:
		open_on_left = true

	var target_x: float = (
		anchor_rect.position.x - margin - popup_size.x
		if open_on_left
		else anchor_rect.end.x + margin
	)

	var target_y: float = anchor_rect.position.y + anchor_rect.size.y * 0.5 - popup_size.y * 0.5
	var target_pos: Vector2 = Vector2(target_x, target_y)

	target_pos.x = clamp(
		target_pos.x,
		float(viewport_rect.position.x + margin),
		float(viewport_rect.position.x + viewport_rect.size.x - margin - popup_size.x)
	)

	if clamp_y:
		target_pos.y = clamp(
			target_pos.y,
			float(viewport_rect.position.y + margin),
			float(viewport_rect.position.y + viewport_rect.size.y - margin - popup_size.y)
		)

	popup.global_position = target_pos

	var ptr_size: Vector2 = pointer.custom_minimum_size
	var popup_is_right: bool = popup.global_position.x >= anchor_rect.position.x
	var pointer_x: float

	if popup_is_right:
		pointer_x = popup.global_position.x - ptr_size.x * 0.5
	else:
		pointer_x = popup.global_position.x + popup_size.x - ptr_size.x * 0.5

	pointer.global_position = Vector2(
		pointer_x,
		anchor_rect.position.y + anchor_rect.size.y * 0.5 - ptr_size.y * 0.5
	)

	close_btn.global_position = popup.global_position + Vector2(
		popup_size.x - close_btn.custom_minimum_size.x * 0.5,
		-close_btn.custom_minimum_size.y * 0.5
	)

	return target_pos

func _update_active_word_popup_position() -> void:
	var overlay := get_node_or_null("WordPopupOverlay") as Control
	if is_instance_valid(overlay):
		_position_word_popup(overlay, false)

func _handle_word_popup_click(overlay: Control, click_pos: Vector2) -> void:
	if not is_instance_valid(overlay):
		return

	var popup := overlay.get_node_or_null("WordPopup") as Control
	if is_instance_valid(popup) and popup.get_global_rect().has_point(click_pos):
		return

	var clicked_word := ""
	var clicked_panel: Control = null

	for row in full_word_list.get_children():
		if row is HBoxContainer:
			for child in row.get_children():
				if child is PanelContainer and child.has_meta("word"):
					var r := (child as Control).get_global_rect()
					if r.has_point(click_pos):
						clicked_word = String(child.get_meta("word"))
						clicked_panel = child
						break
			if clicked_panel:
				break

	_dismiss_word_popup(overlay)

	if clicked_panel and clicked_word != "":
		_show_word_popup(clicked_word, clicked_panel)
		
func _on_word_popup_close_pressed(overlay_id: int) -> void:
	var overlay := instance_from_id(overlay_id) as Control
	if is_instance_valid(overlay):
		_dismiss_word_popup(overlay)


func _on_word_popup_overlay_gui_input(event: InputEvent, overlay_id: int) -> void:
	var overlay := instance_from_id(overlay_id) as Control
	if not is_instance_valid(overlay):
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_word_popup_pointer_down = true
				_word_popup_dragging = false
				_word_popup_last_pos = mb.position
			else:
				var was_dragging: bool = _word_popup_dragging

				_word_popup_pointer_down = false
				_word_popup_dragging = false

				if not was_dragging:
					_handle_word_popup_click(overlay, mb.position)

		return

	if event is InputEventMouseMotion and _word_popup_pointer_down:
		var mm := event as InputEventMouseMotion

		if not _word_popup_dragging:
			if mm.position.distance_to(_word_popup_last_pos) >= WORDS_DRAG_THRESHOLD:
				_word_popup_dragging = true

		_word_popup_last_pos = mm.position
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch

		if touch.pressed:
			_word_popup_pointer_down = true
			_word_popup_dragging = false
			_word_popup_last_pos = touch.position
		else:
			var was_touch_dragging: bool = _word_popup_dragging

			_word_popup_pointer_down = false
			_word_popup_dragging = false

			if not was_touch_dragging:
				_handle_word_popup_click(overlay, touch.position)

		return

	if event is InputEventScreenDrag and _word_popup_pointer_down:
		var drag := event as InputEventScreenDrag

		if not _word_popup_dragging:
			if drag.position.distance_to(_word_popup_last_pos) >= WORDS_DRAG_THRESHOLD:
				_word_popup_dragging = true

		_word_popup_last_pos = drag.position

func _show_word_popup(word: String, anchor: Control) -> void:
	var old_overlay := get_node_or_null("WordPopupOverlay")
	if old_overlay:
		old_overlay.queue_free()
	
	var overlay := Control.new()
	overlay.name = "WordPopupOverlay"
	overlay.top_level = true
	overlay.z_as_relative = false
	overlay.z_index = 400
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	overlay.set_meta("anchor", anchor)
	overlay.set_meta("word", word)

	var popup := PanelContainer.new()
	popup.name = "WordPopup"
	popup.z_as_relative = false
	popup.z_index = 500

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.98)
	sb.corner_radius_top_left = 24
	sb.corner_radius_top_right = 24
	sb.corner_radius_bottom_left = 24
	sb.corner_radius_bottom_right = 24
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	sb.set_content_margin(SIDE_LEFT, 16.0)
	sb.set_content_margin(SIDE_RIGHT, 16.0)
	sb.set_content_margin(SIDE_TOP, 16.0)
	sb.set_content_margin(SIDE_BOTTOM, 16.0)
	popup.add_theme_stylebox_override("panel", sb)
	popup.custom_minimum_size = Vector2(140, 0)
	overlay.add_child(popup)

	var piece_runs: Array[String] = []
	if game_screen and game_screen.has_method("get_letter_pieces"):
		piece_runs = game_screen.get_letter_pieces()
	else:
		var letters_str := String(game_screen.letters).to_upper()
		for c in letters_str:
			piece_runs.append(String(c))

	var orientations: Array = []
	if game_screen and game_screen.has_method("get_letter_piece_orientations"):
		orientations = game_screen.get_letter_piece_orientations()

	var seg_data: Dictionary = _build_visual_segments_for_word(
		word,
		piece_runs,
		orientations
	)

	var show_horizontal: bool = true
	var pieces_to_show: Array = []

	if seg_data.is_empty():
		show_horizontal = true
	else:
		show_horizontal = bool(seg_data.get("horizontal", true))
		if seg_data.has("pieces"):
			pieces_to_show = seg_data["pieces"]

	var letters_canvas := Control.new()
	letters_canvas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	letters_canvas.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	popup.add_child(center)
	center.add_child(letters_canvas)

	var letter_size := 44.0
	var separation := 6.0
	var tiles: Array[Dictionary] = []

	if pieces_to_show.is_empty():
		var w_upper := word.to_upper()
		for c in w_upper:
			var tile := _create_run_tile(String(c), true, [])
			letters_canvas.add_child(tile)
			tiles.append({
				"tile": tile,
				"is_horizontal_piece": true,
				"run": String(c),
				"used_idx": 0
			})
	else:
		for p in pieces_to_show:
			if not (p is Dictionary and p.has("piece_idx")):
				continue

			var piece_idx: int = int(p["piece_idx"])
			if piece_idx < 0 or piece_idx >= piece_runs.size():
				continue

			var full_piece := String(piece_runs[piece_idx]).to_upper()
			if full_piece == "":
				continue

			var used_indices: Array = []
			var used_idx := 0
			if p.has("used_letters"):
				used_indices = p["used_letters"]
				if used_indices.size() > 0:
					used_idx = int(used_indices[0])

			var is_h_piece := false
			if orientations.size() == piece_runs.size():
				is_h_piece = _is_piece_horizontal_idx(piece_idx, orientations)

			var tile := _create_run_tile(full_piece, is_h_piece, used_indices)
			letters_canvas.add_child(tile)

			tiles.append({
				"tile": tile,
				"is_horizontal_piece": is_h_piece,
				"run": full_piece,
				"used_idx": used_idx
			})

	var max_piece_width := 0.0
	var max_piece_height := 0.0

	for t in tiles:
		var tile: Control = t["tile"]
		var is_h_piece: bool = bool(t["is_horizontal_piece"])
		var run: String = t["run"]
		var run_len := run.length()

		var w := letter_size * (run_len if is_h_piece else 1)
		var h := letter_size * (1 if is_h_piece or run_len == 1 else run_len)

		tile.size = Vector2(w, h)
		tile.custom_minimum_size = tile.size

		max_piece_width = max(max_piece_width, w)
		max_piece_height = max(max_piece_height, h)

	if show_horizontal:
		var total_width := 0.0
		for t in tiles:
			var tile: Control = t["tile"]
			total_width += tile.size.x
		if tiles.size() > 1:
			total_width += separation * float(tiles.size() - 1)

		var total_height := max_piece_height + letter_size
		letters_canvas.custom_minimum_size = Vector2(total_width, total_height)
		letters_canvas.size = letters_canvas.custom_minimum_size

		var baseline_y := total_height * 0.5

		var x_accum := 0.0
		for i in range(tiles.size()):
			var t := tiles[i]
			var tile: Control = t["tile"]
			var is_h_piece: bool = bool(t["is_horizontal_piece"])
			var run: String = t["run"]
			var run_len := run.length()
			var used_idx := int(t["used_idx"])

			var w := tile.size.x
			var h := tile.size.y

			var used_center_y := 0.0
			if run_len <= 1 or is_h_piece:
				used_center_y = h * 0.5
			else:
				used_center_y = (float(used_idx) + 0.5) * (h / float(run_len))

			var tile_y := baseline_y - used_center_y
			tile.position = Vector2(x_accum, tile_y)

			x_accum += w + separation
	else:
		var total_height := 0.0
		for t in tiles:
			var tile: Control = t["tile"]
			total_height += tile.size.y
		if tiles.size() > 1:
			total_height += separation * float(tiles.size() - 1)

		var total_width := max_piece_width + letter_size
		letters_canvas.custom_minimum_size = Vector2(total_width, total_height)
		letters_canvas.size = letters_canvas.custom_minimum_size

		var baseline_x := total_width * 0.5

		var y_accum := 0.0
		for i in range(tiles.size()):
			var t := tiles[i]
			var tile: Control = t["tile"]
			var is_h_piece: bool = bool(t["is_horizontal_piece"])
			var run: String = t["run"]
			var run_len := run.length()
			var used_idx := int(t["used_idx"])

			var w := tile.size.x
			var h := tile.size.y

			var used_center_x := 0.0
			if run_len <= 1 or not is_h_piece:
				used_center_x = w * 0.5
			else:
				used_center_x = (float(used_idx) + 0.5) * (w / float(run_len))

			var tile_x := baseline_x - used_center_x
			tile.position = Vector2(tile_x, y_accum)

			y_accum += h + separation

	var pointer := ColorRect.new()
	pointer.name = "Pointer"
	pointer.color = sb.bg_color
	pointer.custom_minimum_size = Vector2(18, 18)
	pointer.size = pointer.custom_minimum_size
	pointer.rotation = deg_to_rad(45.0)
	pointer.z_as_relative = false
	pointer.z_index = 499
	overlay.add_child(pointer)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.flat = false
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.z_as_relative = false
	close_btn.z_index = 501
	close_btn.add_theme_color_override("font_color", Color(0, 0, 0))

	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(1, 1, 1)
	close_style.corner_radius_top_left = 14
	close_style.corner_radius_top_right = 14
	close_style.corner_radius_bottom_left = 14
	close_style.corner_radius_bottom_right = 14
	close_style.shadow_color = Color(0, 0, 0, 0.25)
	close_style.shadow_size = 4
	close_style.shadow_offset = Vector2(0, 2)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_stylebox_override("hover", close_style)
	close_btn.add_theme_stylebox_override("pressed", close_style)
	overlay.add_child(close_btn)

	var overlay_id: int = overlay.get_instance_id()
	close_btn.pressed.connect(_on_word_popup_close_pressed.bind(overlay_id))

	overlay.gui_input.connect(_on_word_popup_overlay_gui_input.bind(overlay_id))

	popup.modulate.a = 0.0

	await get_tree().process_frame
	await get_tree().process_frame

	var popup_rect: Rect2 = popup.get_global_rect()

	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var margin: float = 12.0
	var max_width: float = float(viewport_rect.size.x) - margin * 2.0
	var max_height: float = float(viewport_rect.size.y) - margin * 2.0

	if popup_rect.size.x > max_width or popup_rect.size.y > max_height:
		var sx: float = max_width / popup_rect.size.x
		var sy: float = max_height / popup_rect.size.y
		var scale_factor: float = clamp(min(sx, sy), 0.5, 1.0)
		letters_canvas.scale = Vector2(scale_factor, scale_factor)
		await get_tree().process_frame

	var target_pos: Vector2 = _position_word_popup(overlay, true)

	var tween := create_tween()
	popup.modulate.a = 0.0

	var start_pos: Vector2 = target_pos + Vector2(0, 8.0)
	popup.global_position = start_pos

	tween.tween_property(popup, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(popup, "global_position", target_pos, 0.15) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
func _show_words_loading() -> void:
	_hide_words_loading()

	if not is_instance_valid(self):
		return

	_words_loading_overlay = Control.new()
	_words_loading_overlay.name = "WordsLoadingOverlay"
	_words_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_words_loading_overlay.z_as_relative = false
	_words_loading_overlay.z_index = 1000
	_words_loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_words_loading_overlay)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.35)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_words_loading_overlay.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_words_loading_overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	var tile_wrap := Control.new()
	tile_wrap.custom_minimum_size = Vector2(64, 64)
	tile_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tile_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_child(tile_wrap)

	var tile := TextureRect.new()
	tile.texture = LETTER_BG
	tile.expand = true
	tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tile.set_anchors_preset(Control.PRESET_FULL_RECT)
	tile_wrap.add_child(tile)

	var letter_lbl := Label.new()
	letter_lbl.text = "O"
	letter_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter_lbl.add_theme_font_size_override("font_size", 30)
	letter_lbl.add_theme_color_override("font_color", Color(0, 0, 0))
	letter_lbl.anchor_left = 0.0
	letter_lbl.anchor_top = 0.0
	letter_lbl.anchor_right = 1.0
	letter_lbl.anchor_bottom = 1.0
	letter_lbl.offset_left = 0.0
	letter_lbl.offset_top = 0.0
	letter_lbl.offset_right = 0.0
	letter_lbl.offset_bottom = 0.0
	tile_wrap.add_child(letter_lbl)

	var caption := Label.new()
	caption.text = "Finding words..."
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 18)
	vbox.add_child(caption)

	letter_lbl.modulate.a = 1.0
	_words_loading_tween = create_tween()
	_words_loading_tween.set_loops()
	_words_loading_tween.tween_property(letter_lbl, "modulate:a", 0.2, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_words_loading_tween.tween_property(letter_lbl, "modulate:a", 1.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _hide_words_loading() -> void:
	if _words_loading_tween and _words_loading_tween.is_running():
		_words_loading_tween.kill()
	_words_loading_tween = null

	if is_instance_valid(_words_loading_overlay):
		_words_loading_overlay.queue_free()
	_words_loading_overlay = null
	
func _dismiss_word_popup(overlay: Control) -> void:
	if not is_instance_valid(overlay):
		return

	_word_popup_pointer_down = false
	_word_popup_dragging = false
	overlay.queue_free()

func _on_start_button_pressed() -> void:
	await _switch_to_screen(1)      # GameScreen
	game_screen.start_game()
	
func _on_back_button_pressed() -> void:
	await _switch_to_screen(2)      # ScoreScreen
	
func _on_view_words_pressed() -> void:
	await _switch_to_screen(3) # View Words Screen
	await _populate_full_word_list_from_cache()
	
func _load_words_async() -> void:
	full_word_list.queue_free_children()
	_compute_words_async()
	
func _init_dictionary_trie() -> void:
	if _dictionary_trie_root != null: return
	
	_dictionary_trie_root = TrieNode.new()
	var f := FileAccess.open(DICT_PATH, FileAccess.READ)
	if f == null:
		OpLog.e(LOG_TAG, ["dictionary_trie_open_failed path=", DICT_PATH])
		push_error("Could not open dictionary for Trie: %s" % DICT_PATH)
		return

	while not f.eof_reached():
		var line := f.get_line().strip_edges().to_upper()
		if line.length() < 3: continue 
		
		var node := _dictionary_trie_root
		for i in line.length():
			var char_str := line[i]
			if not node.children.has(char_str):
				node.children[char_str] = TrieNode.new()
			node = node.children[char_str]
		node.is_word = true
		
func _find_candidates_via_trie(piece_runs: Array[String]) -> Array[String]:
	var results: Array[String] = []
	if _dictionary_trie_root == null:
		_init_dictionary_trie()

	if piece_runs.is_empty():
		return results

	var letter_counts: Dictionary = {}
	var total_letters := 0

	for run in piece_runs:
		var r_upper := run.to_upper()
		for i in range(r_upper.length()):
			var ch := r_upper[i]
			letter_counts[ch] = int(letter_counts.get(ch, 0)) + 1
			total_letters += 1

	var max_len: int = int(min(total_letters, 9))

	_trie_dfs_letters(_dictionary_trie_root, letter_counts, "", results, max_len)
	return results
	
func _trie_dfs_letters(
	node: TrieNode,
	letter_counts: Dictionary,
	current_word: String,
	results: Array[String],
	max_len: int
) -> void:
	if node.is_word and current_word.length() >= 3:
		results.append(current_word)

	if current_word.length() >= max_len:
		return

	for key in letter_counts.keys():
		var remaining: int = int(letter_counts[key])
		if remaining <= 0:
			continue

		var ch_str := String(key)
		if ch_str.length() != 1:
			continue

		if not node.children.has(ch_str):
			continue

		var next_node: TrieNode = node.children[ch_str] as TrieNode

		letter_counts[key] = remaining - 1
		_trie_dfs_letters(next_node, letter_counts, current_word + ch_str, results, max_len)
		letter_counts[key] = remaining
		
const WORDS_COMPUTE_BUDGET_MS := 12
const WORDS_COMPUTE_BATCH_SIZE := 250
const WORDS_LIST_ROW_BATCH_SIZE := 40

func _init_dictionary_trie_async() -> void:
	if _dictionary_trie_root != null:
		return

	var root := TrieNode.new()
	var f := FileAccess.open(DICT_PATH, FileAccess.READ)
	if f == null:
		OpLog.e(LOG_TAG, ["dictionary_trie_open_failed path=", DICT_PATH])
		_dictionary_trie_root = root
		return

	var slice_start := Time.get_ticks_msec()
	while not f.eof_reached():
		var line := f.get_line().strip_edges().to_upper()
		if line.length() >= 3:
			var node := root
			for i in line.length():
				var char_str := line[i]
				if not node.children.has(char_str):
					node.children[char_str] = TrieNode.new()
				node = node.children[char_str]
			node.is_word = true

		if Time.get_ticks_msec() - slice_start >= WORDS_COMPUTE_BUDGET_MS:
			await get_tree().process_frame
			slice_start = Time.get_ticks_msec()

	_dictionary_trie_root = root

func _can_form_with_orientation_fast(
	word_upper: String,
	runs_upper: Array[String],
	orientations: Array,
	want_horizontal: bool
) -> bool:
	var n: int = runs_upper.size()
	if n == 0:
		return false

	var wlen := word_upper.length()
	if want_horizontal and wlen > 8:
		return false
	if (not want_horizontal) and wlen > 9:
		return false

	var memo: Dictionary = {}
	return _can_form_with_orientation_dfs(
		word_upper, runs_upper, orientations, want_horizontal, 0, 0, memo
	)

func _begin_background_word_precompute() -> void:
	if _cached_possible_level == "" or _words_cache_ready or _words_computing:
		return

	await get_tree().process_frame
	await get_tree().process_frame

	if _cached_possible_level == "" or _words_cache_ready or _words_computing:
		return

	await _compute_words_async()

func _compute_words_async() -> void:
	if _words_computing:
		while _words_computing:
			await get_tree().process_frame
		return

	if _words_cache_ready:
		return

	_words_computing = true
	_words_cache_ready = false
	_words_compute_level = _cached_possible_level
	_possible_words_cache.clear()

	var started_at: int = Time.get_ticks_msec()

	await _init_dictionary_trie_async()

	if _words_compute_level != _cached_possible_level:
		_words_computing = false
		_words_cache_ready = false
		_possible_words_cache.clear()
		call_deferred("_begin_background_word_precompute")
		return

	await get_tree().process_frame

	var piece_runs: Array[String] = []
	if game_screen and game_screen.has_method("get_letter_pieces"):
		piece_runs = game_screen.get_letter_pieces()
	else:
		var letters_str: String = String(game_screen.letters).to_upper().strip_edges()
		for c in letters_str:
			piece_runs.append(String(c))

	if piece_runs.is_empty():
		_words_cache_ready = true
		_words_computing = false
		return

	var orientations: Array = []
	if game_screen and game_screen.has_method("get_letter_piece_orientations"):
		orientations = game_screen.get_letter_piece_orientations()

	var runs_upper: Array[String] = []
	runs_upper.resize(piece_runs.size())

	for i in range(piece_runs.size()):
		runs_upper[i] = String(piece_runs[i]).strip_edges().to_upper()

	var has_orientation_data: bool = orientations.size() == runs_upper.size()
	var candidates: Array[String] = _find_candidates_via_trie(piece_runs)
	var seen_possible: Dictionary = {}
	var checked: int = 0

	for w in candidates:
		var w_str: String = String(w).strip_edges().to_upper()
		var wlen: int = w_str.length()

		if wlen >= 3 and wlen <= 9 and not seen_possible.has(w_str):
			var fits: bool = true

			if has_orientation_data:
				fits = _can_form_with_orientation_fast(w_str, runs_upper, orientations, true) \
					or _can_form_with_orientation_fast(w_str, runs_upper, orientations, false)

			if fits:
				var pts: int = _compute_word_score(wlen)
				if pts > 0:
					seen_possible[w_str] = true
					_possible_words_cache.append({
						"word": w_str,
						"points": pts
					})

		checked += 1

		if checked % WORDS_COMPUTE_BATCH_SIZE == 0:
			if _words_compute_level != _cached_possible_level:
				_words_computing = false
				_words_cache_ready = false
				_possible_words_cache.clear()
				call_deferred("_begin_background_word_precompute")
				return

			await get_tree().process_frame

	_possible_words_cache.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var pa: int = int(a["points"])
			var pb: int = int(b["points"])

			if pa == pb:
				return String(a["word"]) < String(b["word"])

			return pa > pb
	)

	possible_word_count = _possible_words_cache.size()
	_update_possible_words_count_label()

	_words_cache_ready = true
	_words_computing = false

	OpLog.event(LOG_TAG, [
		"possible_words_computed candidates=", candidates.size(),
		" possible=", _possible_words_cache.size(),
		" elapsed_ms=", Time.get_ticks_msec() - started_at
	])

func _add_word_row(word: String, points: int) -> void:
	_add_word_row_with_highlight(word, points, false)
	possible_word_count += 1
	if is_instance_valid(view_words_button):
		view_words_button.text = "VIEW ALL WORDS"

func _compute_word_score(wlen: int) -> int:
	if wlen == 3:
		return 100
	elif wlen == 4:
		return 400
	elif wlen == 5:
		return 800
	elif wlen == 6:
		return 1400
	elif wlen == 7:
		return 1800
	elif wlen == 8:
		return 2200
	elif wlen == 9:
		return 2600
	return 0

func _create_run_tile(run: String, is_horizontal_piece: bool, used_letter_indices: Array = []) -> Control:
	run = run.to_upper()

	var used_set: Dictionary = {}
	for idx in used_letter_indices:
		used_set[int(idx)] = true

	var tile := TextureButton.new()
	tile.texture_normal = LETTER_BG
	tile.texture_pressed = LETTER_BG
	tile.texture_hover = LETTER_BG
	tile.ignore_texture_size = true
	tile.stretch_mode = TextureButton.STRETCH_SCALE
	tile.focus_mode = Control.FOCUS_NONE
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var letter_size := 44.0
	var font_size := 26

	if run.length() == 1:
		tile.custom_minimum_size = Vector2(letter_size, letter_size)
		tile.size = tile.custom_minimum_size

		var lbl := Label.new()
		lbl.text = run
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", font_size)

		var used := used_set.has(0) or used_set.is_empty()
		var color := Color(0, 0, 0) if used else Color(0, 0, 0, 0.35)
		lbl.add_theme_color_override("font_color", color)

		lbl.anchor_left = 0.0
		lbl.anchor_top = 0.0
		lbl.anchor_right = 1.0
		lbl.anchor_bottom = 1.0
		lbl.offset_left = 0.0
		lbl.offset_top = 0.0
		lbl.offset_right = 0.0
		lbl.offset_bottom = 0.0
		tile.add_child(lbl)
	else:
		if is_horizontal_piece:
			tile.custom_minimum_size = Vector2(letter_size * run.length(), letter_size)
			tile.size = tile.custom_minimum_size

			var hbox := HBoxContainer.new()
			hbox.anchor_left = 0.0
			hbox.anchor_top = 0.0
			hbox.anchor_right = 1.0
			hbox.anchor_bottom = 1.0
			hbox.offset_left = 0.0
			hbox.offset_top = 0.0
			hbox.offset_right = 0.0
			hbox.offset_bottom = 0.0
			hbox.alignment = BoxContainer.ALIGNMENT_CENTER
			hbox.add_theme_constant_override("separation", 0)
			tile.add_child(hbox)

			for i in run.length():
				var ch := String(run[i])
				var lbl_h := Label.new()
				lbl_h.text = ch
				lbl_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl_h.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				lbl_h.add_theme_font_size_override("font_size", font_size)

				var used := used_set.is_empty() or used_set.has(i)
				var color := Color(0, 0, 0) if used else Color(0, 0, 0, 0.35)
				lbl_h.add_theme_color_override("font_color", color)

				lbl_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hbox.add_child(lbl_h)
		else:
			tile.custom_minimum_size = Vector2(letter_size, letter_size * run.length())
			tile.size = tile.custom_minimum_size

			var vbox := VBoxContainer.new()
			vbox.anchor_left = 0.0
			vbox.anchor_top = 0.0
			vbox.anchor_right = 1.0
			vbox.anchor_bottom = 1.0
			vbox.offset_left = 0.0
			vbox.offset_top = 0.0
			vbox.offset_right = 0.0
			vbox.offset_bottom = 0.0
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.add_theme_constant_override("separation", 0)
			tile.add_child(vbox)

			for i in run.length():
				var ch2 := String(run[i])
				var lbl_v := Label.new()
				lbl_v.text = ch2
				lbl_v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl_v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				lbl_v.add_theme_font_size_override("font_size", font_size)

				var used := used_set.is_empty() or used_set.has(i)
				var color := Color(0, 0, 0) if used else Color(0, 0, 0, 0.35)
				lbl_v.add_theme_color_override("font_color", color)

				lbl_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
				vbox.add_child(lbl_v)

	return tile

func _build_visual_segments_for_word(
	word: String,
	piece_runs: Array[String],
	orientations: Array
) -> Dictionary:
	var result: Dictionary = {}
	var n: int = piece_runs.size()
	if n == 0:
		return result

	var word_u := word.to_upper()
	var word_len: int = word_u.length()

	if word_len > 9:
		return result

	var runs_upper: Array[String] = []
	runs_upper.resize(n)
	for i in range(n):
		runs_upper[i] = String(piece_runs[i]).to_upper()

	var memo: Dictionary = {}
	var path: Array = []
	var final_horizontal := true

	var can_horiz := word_len <= 8
	var can_vert := word_len <= 9
	var ok := false

	if can_horiz:
		ok = _build_segments_dfs(
			word_u,
			runs_upper,
			orientations,
			true,
			0,
			0,
			memo,
			path
		)
		if ok:
			final_horizontal = true

	if not ok and can_vert:
		memo.clear()
		path.clear()
		ok = _build_segments_dfs(
			word_u,
			runs_upper,
			orientations,
			false,
			0,
			0,
			memo,
			path
		)
		if ok:
			final_horizontal = false

	if not ok:
		return result

	if path.size() != word_len:
		return result

	var piece_info: Dictionary = {}
	for pos in range(word_len):
		var entry : Dictionary = path[pos]
		if not (entry is Dictionary and entry.has("piece_idx") and entry.has("letter_idx")):
			continue

		var pi := int(entry["piece_idx"])
		var li := int(entry["letter_idx"])

		if not piece_info.has(pi):
			piece_info[pi] = {
				"piece_idx": pi,
				"first_pos": pos,
				"used_letters": [li]
			}
		else:
			var d: Dictionary = piece_info[pi]
			d["first_pos"] = min(int(d["first_pos"]), pos)
			var used := d["used_letters"] as Array
			if not used.has(li):
				used.append(li)
			d["used_letters"] = used

	var pieces_used: Array = []
	for pi in piece_info.keys():
		pieces_used.append(piece_info[pi])
	pieces_used.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["first_pos"]) < int(b["first_pos"])
	)

	result["horizontal"] = final_horizontal
	result["pieces"] = pieces_used
	return result

func _build_segments_dfs(
	word: String,
	runs_upper: Array[String],
	orientations: Array,
	want_horizontal: bool,
	pos: int,
	used_mask: int,
	memo: Dictionary,
	path: Array
) -> bool:
	var word_len := word.length()
	var n := runs_upper.size()

	if pos == word_len:
		return true

	var hv := "H" if want_horizontal else "V"
	var key := "%d|%d|%s" % [pos, used_mask, hv]
	if memo.has(key):
		return false

	var target := word[pos]

	for i in range(n):
		var bit := 1 << i
		if used_mask & bit != 0:
			continue

		var run := runs_upper[i]
		var is_h := _is_piece_horizontal_idx(i, orientations)
		var aligned := (want_horizontal and is_h) or (not want_horizontal and not is_h)

		if aligned and run.length() > 1:
			var blen := run.length()
			if pos + blen <= word_len and word.substr(pos, blen) == run:
				var old := path.size()
				for j in range(blen):
					path.append({
						"piece_idx": i,
						"letter_idx": j
					})

				if _build_segments_dfs(
					word, runs_upper, orientations, want_horizontal,
					pos + blen, used_mask | bit, memo, path
				):
					return true

				path.resize(old)
	for i in range(n):
		var bit2 := 1 << i
		if used_mask & bit2 != 0:
			continue

		var run2 := runs_upper[i]
		var is_h2 := _is_piece_horizontal_idx(i, orientations)
		var aligned2 := (want_horizontal and is_h2) or (not want_horizontal and not is_h2)

		if aligned2 and run2.length() > 1:
			continue

		var letter_idx := -1
		if run2.length() == 1:
			if run2[0] == target:
				letter_idx = 0
		else:
			for k in range(run2.length()):
				if run2[k] == target:
					letter_idx = k
					break

		if letter_idx == -1:
			continue

		path.append({
			"piece_idx": i,
			"letter_idx": letter_idx
		})

		if _build_segments_dfs(
			word, runs_upper, orientations, want_horizontal,
			pos + 1, used_mask | bit2, memo, path
		):
			return true

		path.pop_back()

	memo[key] = true
	return false

func _build_word_entries_from_string(words_s: String) -> Array:
	var result: Array = []
	var seen_words: Dictionary = {}

	if words_s == "":
		return result

	var parts: PackedStringArray = words_s.split("|", false)
	for w_raw in parts:
		var word_key: String = String(w_raw).strip_edges().to_upper()

		if word_key == "" or seen_words.has(word_key):
			continue

		seen_words[word_key] = true

		var pts: int = _compute_word_score(word_key.length())
		result.append({
			"word": word_key,
			"points": pts
		})

	return result

func _on_game_time_up() -> void:
	OpLog.event(LOG_TAG, [
		"time_up player=", player,
		" spectator=", spectator_mode,
		" current_score=", game_screen.get_final_score() if is_instance_valid(game_screen) else -1,
		" word_count=", game_screen.get_word_count() if is_instance_valid(game_screen) else -1
	])

	_populate_scoreboard(true)
	await send_game()
	await _switch_to_screen(2)

func send_game() -> void:
	await get_tree().process_frame

	if spectator_mode:
		OpLog.w(LOG_TAG, "send_game_blocked spectator=true")
		return

	var history: Array = game_screen.get_word_history()
	var seen_words: Dictionary = {}
	var word_strings: Array[String] = []
	var final_score: int = 0

	for entry in history:
		if not (entry is Dictionary):
			continue

		var e: Dictionary = entry
		if not e.has("word"):
			continue

		var word_key: String = String(e["word"]).strip_edges().to_upper()

		if word_key == "" or seen_words.has(word_key):
			OpLog.i(LOG_TAG, ["duplicate_word_rejected_on_send word=", word_key])
			continue

		seen_words[word_key] = true
		word_strings.append(word_key)

		if e.has("points"):
			final_score += int(e["points"])
		else:
			final_score += _compute_word_score(word_key.length())

	var total_words: int = word_strings.size()
	var words_joined: String = "|".join(word_strings)

	var score_key := "score1" if player == 1 else "score2"
	var words_key := "words1" if player == 1 else "words2"
	var words_list_key := "words_list1" if player == 1 else "words_list2"

	if player == 1:
		p1_score_s = str(final_score)
	else:
		p2_score_s = str(final_score)

	var payload: Dictionary = {}

	payload[score_key] = str(final_score)
	payload[words_key] = str(total_words)
	payload[words_list_key] = words_joined

	var avatar_key := "avatar1" if player == 1 else "avatar2"
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	game_ended = check_win()

	if game_ended and win_loss_state != "":
		payload["winner"] = my_uuid + "|" + win_loss_state
		OpLog.event(LOG_TAG, [
			"send_game_winner winner=", payload["winner"],
			" win_loss_state=", win_loss_state
		])

	var json := JSON.stringify(payload)

	OpLog.event(LOG_TAG, [
		"send_game_out player=", player,
		" final_score=", final_score,
		" total_words=", total_words,
		" word_list_len=", words_joined.length(),
		" game_ended=", game_ended,
		" game_over=", game_over,
		" has_winner=", payload.has("winner"),
		" raw=", json
	])

	send_game_data(json)

	if game_over:
		stop_waiting_animation()
	else:
		play_sent_animation()

func _show_result_from_state(state: String, spectator_winner_player: int = 0) -> void:
	game_over = true
	game_ended = true
	win_loss_state = state

	stop_waiting_animation()

	if is_instance_valid(view_words_button):
		view_words_button.visible = true

	if state == "0":
		winner = "0"
	elif spectator_mode:
		winner = "1" if spectator_winner_player == 1 else "-1"
	elif state == "1":
		winner = "1" if player == 1 else "-1"
	else:
		winner = "-1" if player == 1 else "1"

	if not is_instance_valid(win_loss_label):
		return

	if state == "0":
		win_loss_label.text = "DRAW!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
	elif spectator_mode:
		var player_num := spectator_winner_player

		if player_num == 0:
			player_num = 1 if state == "1" else 2

		win_loss_label.text = "Player %d Wins!" % player_num
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

		var winning_avatar: Control = player_score_avatar_display if player_num == 1 else opp_avatar_display
		if is_instance_valid(winning_avatar):
			GameUtils._show_win_burst(winning_avatar)
	elif state == "1":
		win_loss_label.text = "YOU WIN!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

		if is_instance_valid(player_score_avatar_display):
			GameUtils._show_win_burst(player_score_avatar_display)
	else:
		win_loss_label.text = "YOU LOSE"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

		if is_instance_valid(opp_avatar_display):
			GameUtils._show_win_burst(opp_avatar_display)

	OpLog.event(LOG_TAG, [
		"show_result state=", state,
		" spectator_winner_player=", spectator_winner_player,
		" player=", player,
		" spectator=", spectator_mode,
		" winner=", winner,
		" text=", win_loss_label.text,
		" p1_score=", p1_score_s,
		" p2_score=", p2_score_s
	])

	win_loss_label.visible = true
	win_loss_label.modulate.a = 1.0
	win_loss_label.scale = Vector2.ZERO

	await get_tree().process_frame

	win_loss_label.pivot_offset = win_loss_label.size / 2

	var tween_in := create_tween()
	tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _apply_winner_payload(winner_payload: String, p1_id: String = "", p2_id: String = "") -> void:
	OpLog.event(LOG_TAG, [
		"apply_winner_payload payload=", winner_payload,
		" p1=", p1_id,
		" p2=", p2_id,
		" my_uuid=", my_uuid,
		" spectator=", spectator_mode
	])

	var parts := winner_payload.split("|", false)

	if parts.size() < 2:
		OpLog.w(LOG_TAG, ["bad_winner_payload payload=", winner_payload])
		return

	var sender_uuid := String(parts[0])
	var sender_state := String(parts[1])

	if sender_state == "0":
		_show_result_from_state("0")
		return

	var local_state := sender_state
	var winning_player := 0

	if spectator_mode:
		var sender_player := 0

		if sender_uuid == p1_id:
			sender_player = 1
		elif sender_uuid == p2_id:
			sender_player = 2

		winning_player = sender_player

		if sender_state == "-1":
			winning_player = 2 if sender_player == 1 else 1

		local_state = "1" if winning_player == 1 else "-1"
	else:
		if sender_uuid != my_uuid:
			local_state = "-1" if sender_state == "1" else "1"

	OpLog.i(LOG_TAG, [
		"winner_resolved sender_uuid=", sender_uuid,
		" sender_state=", sender_state,
		" local_state=", local_state,
		" winning_player=", winning_player
	])

	_show_result_from_state(local_state, winning_player)

func check_win() -> bool:
	if game_over:
		return true

	OpLog.d(LOG_TAG, [
		"check_win p1_score=", p1_score_s,
		" p2_score=", p2_score_s,
		" player=", player,
		" spectator=", spectator_mode
	])

	if p1_score_s == "" or p2_score_s == "":
		return false

	var p1_score := p1_score_s.to_int()
	var p2_score := p2_score_s.to_int()

	OpLog.event(LOG_TAG, [
		"both_scores_available p1_score=", p1_score,
		" p2_score=", p2_score
	])

	if p1_score > p2_score:
		OpLog.event(LOG_TAG, "game_finished winner_player=1")
		_show_result_from_state("1" if player == 1 else "-1", 1)
	elif p2_score > p1_score:
		OpLog.event(LOG_TAG, "game_finished winner_player=2")
		_show_result_from_state("1" if player == 2 else "-1", 2)
	else:
		OpLog.event(LOG_TAG, "game_finished draw")
		_show_result_from_state("0")

	return true

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		OpLog.w(LOG_TAG, "sent_animation_missing_label")
		return

	if game_over or spectator_mode:
		OpLog.d(LOG_TAG, [
			"sent_animation_skipped game_over=", game_over,
			" spectator=", spectator_mode
		])
		stop_waiting_animation()
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

		if not game_over and not spectator_mode:
			start_waiting_animation()
		else:
			stop_waiting_animation()
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

	if is_player and word_entries.is_empty():
		var raw_words: Array = game_screen.get_word_history()
		var seen_words: Dictionary = {}
		var deduped_words: Array = []
		var deduped_score: int = 0

		for entry in raw_words:
			if not (entry is Dictionary):
				continue

			var e: Dictionary = entry
			if not e.has("word"):
				continue

			var word_key: String = String(e["word"]).strip_edges().to_upper()

			if word_key == "" or seen_words.has(word_key):
				OpLog.i(LOG_TAG, ["duplicate_word_rejected_on_scoreboard word=", word_key])
				continue

			seen_words[word_key] = true

			var points: int = int(e["points"]) if e.has("points") else _compute_word_score(word_key.length())
			deduped_score += points

			deduped_words.append({
				"word": word_key,
				"points": points
			})

		words = deduped_words
		total_words = deduped_words.size()
		final_score = deduped_score
	else:
		words = word_entries

		if total_words_override >= 0:
			total_words = total_words_override
		else:
			total_words = words.size()

		if final_score_override >= 0:
			final_score = final_score_override
		else:
			var sum: int = 0
			var seen_loaded_words: Dictionary = {}

			for entry in words:
				if not (entry is Dictionary):
					continue

				var e2: Dictionary = entry
				if not e2.has("word"):
					continue

				var word_key2: String = String(e2["word"]).strip_edges().to_upper()
				if word_key2 == "" or seen_loaded_words.has(word_key2):
					continue

				seen_loaded_words[word_key2] = true
				sum += int(e2["points"]) if e2.has("points") else _compute_word_score(word_key2.length())

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
		word_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	
	if is_player:
		if player == 1:
			p1_score_s = str(final_score)
		elif player == 2:
			p2_score_s = str(final_score)
