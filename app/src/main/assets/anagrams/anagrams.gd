extends Control

@onready var intro_screen: Control = %IntroScreen
@onready var game_screen: Control = %GameScreen
@onready var score_screen: Control = %ScoreScreen
@onready var start_button: Button = %StartButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var dot_timer: Timer = %DotTimer
@onready var main_score_box: PanelContainer = %MainScoreBoxContainer
@onready var player_score_box: PanelContainer = %PlayerScoreBoxContainer
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var player_word_list: VBoxContainer = %PlayerWordList
@onready var player_words_label: Label = %PlayerWordsLabel
@onready var player_score_label: Label = %PlayerScoreLabel
@onready var opp_word_list: VBoxContainer = %OppWordList
@onready var opp_words_label: Label = %OppWordsLabel
@onready var opp_score_label: Label = %OppScoreLabel

const LETTER_BG: Texture2D = preload("res://anagrams/letter_bg.png")
const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")

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
var is_my_turn = false
var winner = null
var game_over := false
var game_ended := false
var win_loss_state = ""
var my_player := 0           # 0 spectator, 1 black, 2 white

func _ready() -> void:
	_init_screens()
	_apply_score_box_style(main_score_box)
	_apply_score_box_style(player_score_box)
	
	if not start_button.pressed.is_connected(_on_start_button_pressed):
		start_button.pressed.connect(_on_start_button_pressed)

	if not game_screen.time_up.is_connected(_on_game_time_up):
		game_screen.time_up.connect(_on_game_time_up)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
		
	appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		if not has_connected:
			appPlugin.connect("set_game_data", Callable(self, "_set_game_data"))
			has_connected = true
			appPlugin.call("onReady")
	else:
		var dev := '{"isYourTurn": true,"player":"2","letters":"OSSLER","score2":"4100","words2":"5","words_list2":"LOSERS|LOSER|LOSE|LOSS|SOS","id":"dev"}'
		await get_tree().process_frame
		_set_game_data(dev)
		
func _set_game_data(raw_text: String) -> void:
	var res: Variant = JSON.parse_string(raw_text)
	if typeof(res) != TYPE_DICTIONARY:
		print("[ANAGRAMS] Bad JSON for _set_game_data")
		return
	var d: Dictionary = res
	print("INCOMING DATA: ", res)

	game_id = _get_first(d, "id", game_id)
	my_id   = _get_first(d, "myPlayerId", my_id)
	var p1_id: String = _get_first(d, "player1", "")
	var p2_id: String = _get_first(d, "player2", "")
	var sender_s: String = _get_first(d, "player", "1")

	# Incoming letters for this round
	var letters_from_data: String = _get_first(d, "letters", "")
	if letters_from_data != "":
		# Update the game_screen’s letters so start_game() uses them
		game_screen.letters = letters_from_data

	# Incoming scores / words (these come in as strings, possibly from arrays)
	var p1_score_s: String = _get_first(d, "score1", "")
	var p1_words_s: String = _get_first(d, "words1", "")
	var p1_wordlist_s: String = _get_first(d, "words_list1", "")
	var p2_score_s: String = _get_first(d, "score2", "")
	var p2_words_s: String = _get_first(d, "words2", "")
	var p2_wordlist_s: String = _get_first(d, "words_list2", "")

	# You can parse these as ints / arrays if needed:
	var p1_score: int = int(p1_score_s) if p1_score_s != "" else 0
	var p1_words: int = int(p1_words_s) if p1_words_s != "" else 0
	var p2_score: int = int(p2_score_s) if p2_score_s != "" else 0
	var p2_words: int = int(p2_words_s) if p2_words_s != "" else 0
	# word lists stay as the pipe-separated strings for now (p1_wordlist_s, p2_wordlist_s)

	var is_your_turn = bool(res.get("isYourTurn", false))
	is_my_turn = is_your_turn
	var opponent_avatar_key := ""
	winner = _get_first(d, "winner", "")
	stop_waiting()

	var sender_player: int = clampi(int(sender_s), 1, 2)
	if p1_id != "" and p2_id != "":
		if my_id != "" and my_id == p1_id:
			my_player = 1
			print("SETTING FOR ID PLAYER 1")
		elif my_id != "" and my_id == p2_id:
			my_player = 2
			print("SETTING FOR ID PLAYER 2")
		else:
			my_player = 0
			print("SETTING FOR ID PLAYER 0")
			spectator_mode = true
	else:
		print("IS MY TURN?: ", is_my_turn, " | SENDER PLAYER: ", sender_player)
		my_player = 1 if ((sender_player == 2 and is_my_turn) or (sender_player == 1 and not is_my_turn)) else 2
		print("ELSE SETTING FOR PLAYER: ", my_player)

	if spectator_mode:
		is_my_turn = false
		print("SPECTATOR MODE ACTIVE")

	if my_player == 1:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"
		
		# If we have opponent results in the payload, populate their scoreboard
	if not spectator_mode:
		var opp_score: int = 0
		var opp_words: int = 0
		var opp_wordlist_s: String = ""

		if my_player == 1:
			# I am player 1, opponent is player 2
			opp_score = p2_score
			opp_words = p2_words
			opp_wordlist_s = p2_wordlist_s
		elif my_player == 2:
			# I am player 2, opponent is player 1
			opp_score = p1_score
			opp_words = p1_words
			opp_wordlist_s = p1_wordlist_s

		if opp_wordlist_s != "":
			var opp_entries := _build_word_entries_from_string(opp_wordlist_s)
			_populate_scoreboard(false, opp_entries, opp_words, opp_score)

	if opponent_avatar_key != "" and res.has(opponent_avatar_key):
		var avatar_string = res[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	if not is_my_turn and not game_over:
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

	# Apply torn-edge shader
	var shader := preload("res://anagrams/torn_panel.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	box.material = mat

	# Add a StyleBoxTexture with tiled letter_bg
	var sb := StyleBoxTexture.new()
	sb.texture = LETTER_BG
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE

	sb.set_content_margin(SIDE_LEFT, 16.0)
	sb.set_content_margin(SIDE_RIGHT, 16.0)
	sb.set_content_margin(SIDE_TOP, 12.0)
	sb.set_content_margin(SIDE_BOTTOM, 12.0)

	box.add_theme_stylebox_override("panel", sb)

func _init_screens() -> void:
	screens = [intro_screen, game_screen, score_screen]
	for i in screens.size():
		var node := screens[i]
		node.visible = (i == 0)
		node.position = Vector2.ZERO
	current_screen = 0


func _switch_to_screen(next: int) -> void:
	if next == current_screen:
		return

	var from_node := screens[current_screen]
	var to_node := screens[next]
	var width := size.x

	to_node.visible = true
	to_node.position = Vector2(width, 0)

	var tween := create_tween()
	tween.tween_property(
		from_node, "position",
		Vector2(-width, 0), 0.25
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	tween.parallel().tween_property(
		to_node, "position",
		Vector2.ZERO, 0.25
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished

	from_node.visible = false
	from_node.position = Vector2.ZERO
	current_screen = next


func _on_start_button_pressed() -> void:
	await _switch_to_screen(1)      # GameScreen
	game_screen.start_game()

func _compute_word_score(len: int) -> int:
	# Mirror game_screen scoring rules
	if len == 3:
		return 100
	elif len == 4:
		return 400
	elif len == 5:
		return 1200
	elif len == game_screen.letters.length():
		return 2000
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
	_populate_scoreboard(true)
	send_game()
	await _switch_to_screen(2)      # ScoreScreen
	
func send_game() -> void:
	await get_tree().process_frame
	
	# Gather results from the game screen
	var final_score: int = game_screen.get_final_score()
	var total_words: int = game_screen.get_word_count()
	var history: Array = game_screen.get_word_history()
	
	var word_strings: Array[String] = []
	for entry in history:
		if entry is Dictionary and entry.has("word"):
			word_strings.append(String(entry["word"]))
	var words_joined := "|".join(word_strings)  # e.g. "LOSERS|LOSER|LOSE|LOSS|SOS"
	
	# Keys depend on which player we are
	var score_key := "score1" if my_player == 1 else "score2"
	var words_key := "words1" if my_player == 1 else "words2"
	var words_list_key := "words_list1" if my_player == 1 else "words_list2"
	
	# Base payload (map/move kept for consistency with other games)
	var payload := {
		"map": "",
		"move": "%d,%d,%d" % [1, 1, my_player]
	}
	
	# Add the results in the expected array-of-string format
	payload[score_key] = [str(final_score)]           # e.g. "4100"
	payload[words_key] = [str(total_words)]           # e.g. "5"
	payload[words_list_key] = [words_joined]          # e.g. "LOSERS|LOSER|LOSE|LOSS|SOS"
	
	# Avatar data
	var avatar_key := ("avatar1" if my_player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()
	
	# Winner info (if you’re setting these elsewhere)
	if game_ended and win_loss_state != "":
		payload["winner"] = my_id + "|" + win_loss_state
	
	var plug := Engine.get_singleton("AppPlugin")
	if plug:
		plug.updateGameData(JSON.stringify(payload))
	else:
		print("AppPlugin is null; cannot send.")
	print("OUTGOING DATA", payload)
	
	is_my_turn = false
	
	if not game_ended:
		print("[SEND] No win detected; clearing preview.")
	else:
		print("[SEND] Game ended with winner=", winner, " win_loss_state=", win_loss_state, " — keeping preview line.")
	
	if not game_over:
		play_sent_animation()
		
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
	# Decide which UI widgets we’re filling
	var target_list: VBoxContainer = player_word_list if is_player else opp_word_list
	var target_words_label: Label = player_words_label if is_player else opp_words_label
	var target_score_label: Label = player_score_label if is_player else opp_score_label

	# Clear previous rows
	for child in target_list.get_children():
		child.queue_free()

	var words: Array
	var total_words: int
	var final_score: int

	if is_player and word_entries.is_empty():
		# Local player – use game_screen data
		words = game_screen.get_word_history()
		total_words = game_screen.get_word_count()
		final_score = game_screen.get_final_score()
	else:
		# Opponent or externally-supplied entries
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

	# One HBox per word: [ Panel(word) | points ]
	for entry in words:
		if not (entry is Dictionary) or not entry.has("word") or not entry.has("points"):
			continue

		var word := String(entry["word"])
		var points := int(entry["points"])

		var row := HBoxContainer.new()

		# Word panel should hug the word, with 2px rounded corners
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
		word_panel.add_theme_stylebox_override("panel", word_panel_style)

		var word_label := Label.new()
		word_label.text = word
		word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		word_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		word_label.add_theme_color_override("font_color", Color(0, 0, 0)) # black text
		word_panel.add_child(word_label)
		row.add_child(word_panel)

		# Flexible spacer between word and points
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

		# Points on the right
		var points_label := Label.new()
		points_label.text = str(points)
		points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		points_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(points_label)

		target_list.add_child(row)

	# Update headline labels at top of the correct scoreboard
	target_words_label.text = "WORDS: %d" % total_words
	target_score_label.text = "SCORE: %04d" % final_score

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
