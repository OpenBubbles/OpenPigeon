extends Control

@onready var intro_screen: Control = %IntroScreen
@onready var game_screen: Control = %GameScreen
@onready var score_screen: Control = %ScoreScreen
@onready var words_screen: Control = %WordsScreen
@onready var start_button: Button = %StartButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var dot_timer: Timer = %DotTimer
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
const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const MUSIC_STREAM := preload("res://global/audio/wordbites.ogg")
const DICT_PATH := "res://global/gp_wg_en2.txt"

class TrieNode:
	var children: Dictionary = {}
	var is_word: bool = false

var _dictionary_trie_root: TrieNode = null

var _tear_rng := RandomNumberGenerator.new()

var screens: Array[Control] = []
var current_screen: int = 0
var sent_label_tween: Tween
var dot_count := 0
var spectator_mode := false
const BASE_WAIT_TEXT := "WAITING FOR OPPONENT"
var appPlugin: Object = null
var has_connected := false
var my_id := ""
var game_id := ""
var winner = null
var mediaPlugin = null
var game_over := false
var game_ended := false
var win_loss_state = ""
var my_player := 0           # 0 spectator, 1 black, 2 white
var p1_score_s = ""
var p2_score_s = ""
var possible_word_count: int = 0
var _possible_words_cache: Array = []
var _words_cache_ready := false
var _words_loading_overlay: Control = null
var _words_loading_tween: Tween = null
var my_has_data := false

var _words_scroll_container: ScrollContainer = null
var _words_pointer_down := false
var _words_is_dragging := false
var _words_last_drag_pos := Vector2.ZERO
const WORDS_DRAG_THRESHOLD := 8.0

func _ready() -> void:
	if not start_button.pressed.is_connected(_on_start_button_pressed):
		start_button.pressed.connect(_on_start_button_pressed)
	if not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)

	if not game_screen.time_up.is_connected(_on_game_time_up):
		game_screen.time_up.connect(_on_game_time_up)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	if not view_words_button.pressed.is_connected(_on_view_words_pressed):
		view_words_button.pressed.connect(_on_view_words_pressed)
	
	if is_instance_valid(full_word_list):
		full_word_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var grandparent := full_word_list.get_parent().get_parent()
		if grandparent is ScrollContainer:
			_words_scroll_container = grandparent as ScrollContainer
			if not _words_scroll_container.gui_input.is_connected(_on_words_list_scroll_gui_input):
				_words_scroll_container.gui_input.connect(_on_words_list_scroll_gui_input)
	
	appPlugin = Engine.get_singleton("AppPlugin")
	
	if Engine.has_singleton("OpenPigeonMedia"):
		mediaPlugin = Engine.get_singleton("OpenPigeonMedia")
		print("OpenPigeonMedia plugin is available")
	else:
		print("OpenPigeonMedia plugin is not available")

	_start_music()
	
	if appPlugin:
		if not has_connected:
			appPlugin.connect("set_game_data", Callable(self, "_set_game_data"))
			has_connected = true
			appPlugin.call("onReady")
	else:
		#var dev := '{"isYourTurn": true,"player":"2","level":"2|3|5|GO&2|0|7|UB&1|0|4|RE&2|0|1|ST&1|6|4|BI&0|5|7|N&0|3|3|M&0|3|1|L&0|2|8|C&0|7|6|D&0|6|1|P","score1":"4100","words1":"5","words_list1":"LOSERS|LOSER|LOSE|LOSS|SOS","score2":"4000","words2":"4","words_list2":"LOSERS|LOSER|LOSE|LOSS","id":"dev"}'
		#var dev := '{"isYourTurn": true,"player":"2","level":"2|3|5|GO&2|0|7|UB&1|0|4|RE&2|0|1|ST&1|6|4|BI&0|5|7|N&0|3|3|M&0|3|1|L&0|2|8|C&0|7|6|D&0|6|1|P", "avatar1":"body,3|eyes,6|mouth,3|acc,0|wins,0|bg_color,0.933333,0.407843,0.647059|body_color,0.968627,0.811765,0.333333|glasses,0|stache,0|backdrop,0|hair,0|clothes,2|hair_color,0.505882,0.725490,0.254902|clothes_color,0.686657,0.686657,0.686657", "avatar2":"body,3|eyes,6|mouth,3|acc,0|wins,0|bg_color,0.933333,0.407843,0.647059|body_color,0.968627,0.811765,0.333333|glasses,0|stache,0|backdrop,0|hair,0|clothes,2|hair_color,0.505882,0.725490,0.254902|clothes_color,0.686657,0.686657,0.686657","score1":"4100","words1":"5","words_list1":"LOSERS|LOSER|LOSE|LOSS|SOS","score2":"4000","words2":"4","words_list2":"LOSERS|LOSER|LOSE|LOSS","id":"dev"}'
		var dev := '{"sender":"BB938756-D694-4421-9642-82CB312C13B0nbdTdV","version":"5","tver":"5","ios":"26.4","caption":"Lets play Word Bites!","id":"DlPri7dhRO5Nb3a2","player":"2","player2":"BB938756-D694-4421-9642-82CB312C13B0nbdTdV","letters":"AAA","lang":"en","mode":"1","level":"1|0|0|NG&1|6|4|RO&2|2|3|NY&2|0|3|FU&1|6|8|TE&0|6|6|U&0|6|0|I&0|4|1|U&0|0|8|L&0|3|6|K&0|7|2|P","avatar2":"body,2|eyes,0|mouth,3|acc,0|wins,0|bg_color,0.291679,0.246671,0.464589|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,3|clothes,1|hair_color,0.000000,0.000000,0.000000|clothes_color,0.922711,0.395143,0.779568","game":"wordbites","game_name":"Word Bites","num":"1","build":"LR5rAXhOt"}'
		await get_tree().process_frame
		_set_game_data(dev)

	_apply_score_box_style(main_score_box)
	_apply_score_box_style(player_score_box)
	_apply_score_box_style(opp_score_box)
	
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

func _set_game_data(raw_text: String) -> void:
	var res: Variant = JSON.parse_string(raw_text)
	if typeof(res) != TYPE_DICTIONARY:
		print("[ANAGRAMS] Bad JSON for _set_game_data")
		return

	var d: Dictionary = res
	print("INCOMING DATA: ", res)

	game_id = _get_first(d, "id", game_id)
	my_id = _get_first(d, "myPlayerId", my_id)

	var p1_id: String = _get_first(d, "player1", "")
	var p2_id: String = _get_first(d, "player2", "")
	var sender_s: String = _get_first(d, "player", "1")
	var level_s: String = _get_first(d, "level", "")

	if level_s != "":
		if game_screen.has_method("load_level"):
			game_screen.load_level(level_s)

	_words_cache_ready = false
	_possible_words_cache.clear()

	p1_score_s = _get_first(d, "score1", "")
	var p1_words_s: String = _get_first(d, "words1", "")
	var p1_wordlist_s: String = _get_first(d, "words_list1", "")

	p2_score_s = _get_first(d, "score2", "")
	var p2_words_s: String = _get_first(d, "words2", "")
	var p2_wordlist_s: String = _get_first(d, "words_list2", "")

	print("P1s Score: ", p1_score_s, " | P2s Score: ", p2_score_s)

	var p1_score: int = int(p1_score_s) if p1_score_s != "" else 0
	var p1_words: int = int(p1_words_s) if p1_words_s != "" else 0
	var p2_score: int = int(p2_score_s) if p2_score_s != "" else 0
	var p2_words: int = int(p2_words_s) if p2_words_s != "" else 0

	var opponent_avatar_key := ""
	winner = _get_first(d, "winner", "")
	stop_waiting()

	var sender_player: int = clampi(int(sender_s), 1, 2)

	# Reset before determining
	my_has_data = false

	if p1_id != "" and p2_id != "" and my_id != "":
		if my_id == p1_id:
			my_player = 1
			opponent_avatar_key = "avatar2"
			spectator_mode = false
			print("SETTING FOR ID PLAYER 1 (my_id matches player1)")
		elif my_id == p2_id:
			my_player = 2
			opponent_avatar_key = "avatar1"
			spectator_mode = false
			print("SETTING FOR ID PLAYER 2 (my_id matches player2)")
		else:
			my_player = 0
			spectator_mode = true
			print("SETTING FOR SPECTATOR (my_id matches neither player1 nor player2)")
	else:
		my_player = 1 if sender_player == 2 else 2
		spectator_mode = false
		opponent_avatar_key = "avatar1" if my_player == 2 else "avatar2"
		print("PARTIAL OR MISSING PLAYER IDS; using sender 'player' field as my slot -> my_player =", my_player)

	# Now determine whether MY side has any data
	if not spectator_mode:
		if my_player == 1:
			my_has_data = (
				p1_score_s != ""
				or p1_words_s != ""
				or p1_wordlist_s != ""
			)
			print("PLAYER 1 DATA CHECK -> score:", p1_score_s, " words:", p1_words_s, " list:", p1_wordlist_s)
		elif my_player == 2:
			my_has_data = (
				p2_score_s != ""
				or p2_words_s != ""
				or p2_wordlist_s != ""
			)
			print("PLAYER 2 DATA CHECK -> score:", p2_score_s, " words:", p2_words_s, " list:", p2_wordlist_s)

	print("my_player =", my_player, " | my_has_data =", my_has_data, " | spectator_mode =", spectator_mode)

	if spectator_mode:
		print("SPECTATOR MODE ACTIVE")
		if res.has("avatar1"):
			var av1 = _parse_avatar_string(res["avatar1"])
			player_avatar_display.call_deferred("update_avatar_from_data", av1)
			player_score_avatar_display.call_deferred("update_avatar_from_data", av1)
		if res.has("avatar2"):
			var av2 = _parse_avatar_string(res["avatar2"])
			opp_avatar_display.call_deferred("update_avatar_from_data", av2)

		var p1_entries := _build_word_entries_from_string(p1_wordlist_s)
		_populate_scoreboard(true, p1_entries, p1_words, p1_score)

		var p2_entries := _build_word_entries_from_string(p2_wordlist_s)
		_populate_scoreboard(false, p2_entries, p2_words, p2_score)

	if not spectator_mode:
		var my_score: int = 0
		var my_words: int = 0
		var my_wordlist_s: String = ""
		var opp_score: int = 0
		var opp_words: int = 0
		var opp_wordlist_s: String = ""

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

		if opp_wordlist_s != "":
			var opp_entries := _build_word_entries_from_string(opp_wordlist_s)
			_populate_scoreboard(false, opp_entries, opp_words, opp_score)

	if opponent_avatar_key != "" and res.has(opponent_avatar_key):
		var avatar_string = res[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	game_ended = await check_win()
	_init_screens()

	if my_has_data and not game_over:
		start_waiting()
	else:
		stop_waiting()
		
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

		_words_last_drag_pos = drag.position
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
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

		_words_last_drag_pos = mm.position

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
	for i in screens.size():
		var node := screens[i]
		if not game_over and not spectator_mode and not my_has_data:
			print("Game Over: ", game_over, " Spectator Mode: ", spectator_mode, " My Has Data: ", my_has_data)
			node.visible = (i == 0)
		else:
			print("Going to Score Screen")
			node.visible = (i == 2)
		node.position = Vector2.ZERO
	current_screen = 0 if not game_over and not spectator_mode and not my_has_data else 2

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

func _populate_full_word_list_from_cache() -> void:
	for child in full_word_list.get_children():
		child.queue_free()

	if not _words_cache_ready:
		_show_words_loading()
		await _compute_words_async()
		_hide_words_loading()

	var found_words: Dictionary = {}
	if is_instance_valid(game_screen) and game_screen.has_method("get_word_history"):
		for entry in game_screen.get_word_history():
			if entry is Dictionary and entry.has("word"):
				var wstr := String(entry["word"]).to_upper()
				found_words[wstr] = true

	possible_word_count = _possible_words_cache.size()

	if is_instance_valid(view_words_button):
		view_words_button.text = "VIEW ALL WORDS"

	for entry in _possible_words_cache:
		var word := String(entry["word"])
		var points := int(entry["points"])
		var was_found := found_words.has(word)
		_add_word_row_with_highlight(word, points, was_found)
		
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
				_show_word_popup(word, word_panel)
	)

	full_word_list.add_child(row)

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

	close_btn.pressed.connect(func() -> void:
		_dismiss_word_popup(overlay)
	)

	overlay.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				var click_pos := mb.position
				var popup_rect := popup.get_global_rect()

				if popup_rect.has_point(click_pos):
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
	)

	popup.modulate.a = 0.0

	await get_tree().process_frame
	await get_tree().process_frame

	var anchor_rect: Rect2 = anchor.get_global_rect()
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var margin: float = 12.0
	var popup_rect: Rect2 = popup.get_global_rect()
	
	# Scale down the content first if the popup is too large for the screen
	var max_width: float = float(viewport_rect.size.x) - margin * 2.0
	var max_height: float = float(viewport_rect.size.y) - margin * 2.0
	if popup_rect.size.x > max_width or popup_rect.size.y > max_height:
		var sx: float = max_width / popup_rect.size.x
		var sy: float = max_height / popup_rect.size.y
		var scale_factor: float = clamp(min(sx, sy), 0.5, 1.0)
		letters_canvas.scale = Vector2(scale_factor, scale_factor)
		await get_tree().process_frame
		popup_rect = popup.get_global_rect()

	# Decide left or right of anchor
	var open_on_left: bool = false
	var right_space: float = viewport_rect.size.x - (anchor_rect.end.x + margin)
	if popup_rect.size.x > right_space:
		open_on_left = true

	var target_x: float = (
		anchor_rect.position.x - margin - popup_rect.size.x
		if open_on_left
		else anchor_rect.end.x + margin
	)
	var target_y: float = (
		anchor_rect.position.y + anchor_rect.size.y * 0.5 - popup_rect.size.y * 0.5
	)

	var target_pos: Vector2 = Vector2(target_x, target_y)
	target_pos.x = clamp(
		target_pos.x,
		float(viewport_rect.position.x + margin),
		float(viewport_rect.position.x + viewport_rect.size.x - margin - popup_rect.size.x)
	)
	target_pos.y = clamp(
		target_pos.y,
		float(viewport_rect.position.y + margin),
		float(viewport_rect.position.y + viewport_rect.size.y - margin - popup_rect.size.y)
	)
	popup.global_position = target_pos

	var ptr_size: Vector2 = pointer.custom_minimum_size
	var popup_is_right: bool = popup.global_position.x >= anchor_rect.position.x
	var pointer_x: float
	if popup_is_right:
		pointer_x = popup.global_position.x - ptr_size.x * 0.5
	else:
		pointer_x = popup.global_position.x + popup_rect.size.x - ptr_size.x * 0.5

	pointer.global_position = Vector2(
		pointer_x,
		anchor_rect.position.y + anchor_rect.size.y * 0.5 - ptr_size.y * 0.5
	)

	close_btn.global_position = popup.global_position + Vector2(
		popup_rect.size.x - close_btn.custom_minimum_size.x * 0.5,
		-close_btn.custom_minimum_size.y * 0.5
	)

	var tween := create_tween()
	popup.modulate.a = 0.0
	var start_pos: Vector2 = popup.global_position + Vector2(0, 8.0)
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
	
	var popup := overlay.get_node_or_null("WordPopup") as Control
	if popup == null:
		overlay.queue_free()
		return
	
	var tween := create_tween()
	var start_pos := popup.global_position
	var end_pos := start_pos + Vector2(0, 8)

	tween.tween_property(popup, "modulate:a", 0.0, 0.12)
	tween.parallel().tween_property(popup, "global_position", end_pos, 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	tween.tween_callback(func() -> void:
		if is_instance_valid(overlay):
			overlay.queue_free()
	)

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
	if node.is_word and current_word.length() >= 3 and not results.has(current_word):
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

func _compute_words_async() -> void:
	_words_cache_ready = false
	_possible_words_cache.clear()
	
	if game_screen and game_screen.word_dict.is_empty():
		game_screen._load_dictionary()
	
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
		return

	var candidates: Array[String] = _find_candidates_via_trie(piece_runs)
	for w in candidates:
		var w_str: String = String(w).to_upper()
		var wlen: int = w_str.length()
		if wlen >= 3 and wlen <= 9:
			if _word_respects_orientation(w_str, piece_runs):
				var pts: int = _compute_word_score(wlen)
				if pts > 0:
					_possible_words_cache.append({"word": w_str, "points": pts})

		await get_tree().process_frame

	_possible_words_cache.sort_custom(
	func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = int(a["points"])
		var pb: int = int(b["points"])
		if pa == pb:
			return String(a["word"]) < String(b["word"])
		return pa > pb
	)
	_words_cache_ready = true

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
	_populate_scoreboard(true)
	send_game()
	await _switch_to_screen(2)      # ScoreScreen
	
func send_game() -> void:
	await get_tree().process_frame
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
	
	var plug := Engine.get_singleton("AppPlugin")
	if plug:
		plug.updateGameData(JSON.stringify(payload))
	else:
		print("AppPlugin is null; cannot send.")
	print("OUTGOING DATA", payload)
	
	game_ended = await check_win()
	if not game_ended:
		print("[SEND] No win detected; clearing preview.")
	else:
		print("[SEND] Game ended with winner=", winner, " win_loss_state=", win_loss_state, " — keeping preview line.")
	
	if not game_over:
		play_sent_animation()
		
func check_win() -> bool:
	print("--- CHECKING WIN CONDITION ---")
	if game_over: return false
	print("P1 Score:", p1_score_s," | P2 Score:", p2_score_s)
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
	view_words_button.visible = true
	if winner != "":
		if winner == "0":
			print("[WIN] FINAL TALLY: DRAW!")
			win_loss_label.text = "DRAW!"
			win_loss_state = "0"
			win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
		else:
			var you_win: bool = (not spectator_mode) and (
				(my_player == 1 and winner == "1") or
				(my_player == 2 and winner == "-1")
			)
			print("[WIN] you_win=", you_win, " spectator_mode=", spectator_mode)

			if you_win:
				_show_win_burst(player_score_avatar_display)
				win_loss_label.text = "YOU WIN!"
				win_loss_state = "1"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			else:
				if spectator_mode:
					_show_win_burst(player_score_avatar_display if winner == "1" else opp_avatar_display)
					var displayedwinner = "1" if winner == "-1" else "2"
					win_loss_label.text = "Player %s Wins!" % displayedwinner
					win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
					win_loss_state = "-1"
				else:
					_show_win_burst(opp_avatar_display)
					win_loss_label.text = "YOU LOSE"
					win_loss_state = "-1"
					win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

		win_loss_label.visible = true
		await get_tree().process_frame
		win_loss_label.scale = Vector2.ZERO
		win_loss_label.pivot_offset = win_loss_label.size / 2
		var tween_in := create_tween()
		tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		return true
	return false
		
func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		print("Warning: sent_label is not valid for play_sent_animation.")
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
			start_waiting()
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
		if my_player == 1:
			p1_score_s = str(final_score)
		elif my_player == 2:
			p2_score_s = str(final_score)

func start_waiting():
	if not (is_instance_valid(waiting_label) and is_instance_valid(dot_timer)): return
	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true;
	waiting_label.modulate.a = 0.0;
	var tw := create_tween().set_parallel(true)
	tw.tween_property(waiting_label,"modulate:a",1.0,0.3)
	tw.tween_callback(func(): dot_timer.start())

func stop_waiting():
	if is_instance_valid(dot_timer): 
		dot_timer.stop()
	if is_instance_valid(waiting_label): 
		waiting_label.visible=false
		waiting_label.modulate.a=1.0

func _on_dot_timer_timeout():
	if not is_instance_valid(waiting_label): return
	dot_count = (dot_count % 3) + 1
	waiting_label.text = BASE_WAIT_TEXT + ".".repeat(dot_count)
