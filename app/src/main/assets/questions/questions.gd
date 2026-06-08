extends BaseGame

@onready var send_button: Button = %SendButton
@onready var text_box: TextEdit = %TextBox
@onready var questions_scroll: ScrollContainer = %QuestionsScroll
@onready var questions_container: CenterContainer = %QuestionsContainer
@onready var questions_list: VBoxContainer = %QuestionsList
@onready var question_mark_filler: RichTextLabel = %QuestionMark
@onready var wait_for_label: Label = %WaitForLabel
@onready var player_avatar_display: Control = %PlayerAvatarDisplay
@onready var _desc_rich: RichTextLabel = %Description
@onready var bottom_items: VBoxContainer = %BottomItems
@onready var overlay: PanelContainer = %AnswerOverlay
@onready var overlay_num: RichTextLabel = %QuestionNumber
@onready var overlay_text: RichTextLabel = %QuestionText
@onready var overlay_yes: Button = %YesButton
@onready var overlay_no: Button = %NoButton
@onready var overlay_some: Button = %SometimesButton
@onready var overlay_correct: Button = %CorrectButton
@onready var questions_text_container: PanelContainer = %QuestionsTextContainer
@onready var win_loss_label: Label = %WinLossLabel
@onready var sent_label: Label = %SentLabel

const OpponentAvatarScene: PackedScene = preload("res://global/avatar_textures/AvatarThumbnail.tscn")
const MUSIC_STREAM := preload("res://global/audio/20questions.ogg")
const LOG_TAG := "Questions"
var _opponent_avatar_data: Dictionary = {}
var _answer_avatar_data: Dictionary = {}
var _my_avatar_string: String = ""
var _avatar1_raw: String = ""
var _avatar2_raw: String = ""

var sent_tween: Tween
var _sent_animation_active: bool = false

var is_my_turn: bool = false
var server_player_hint: int = 0
var i_am_player: int = 1
var secret_answer: String = ""
var winner: int = 0	# 1 = Player 1 wins, -1 = Player 2 wins, 0 = undecided
var questions: Array[Dictionary] = []    # [{text:String, idx:int, resp:int}]
var game_id: String = ""
var last_raw_payload: Dictionary = {}
var game_over: bool = false
const MAX_QUESTIONS := 20
var _scroll_tween: Tween = null
var _overlay_idx: int = -1
var _waiting_active := false
var _questions_wait_text: String = "Waiting"
var _kb_open := false
var _kb_last_h := 0
var _player1_id: String = ""
var _player2_id: String = ""
var _local_player_id: String = ""

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
func _get_dev_data() -> String:
	return '{"player":"2","game":"questions","questions":"[Is it a fruit?^&*1^&*1|][Is it an Apple?^&*2^&*2|][Is it a Pear?^&*3^&*0]","game_name":"20 Questions","id":"TEST123","answer":"Pear","num":"1","isYourTurn":true,"player1":"TEST_P1","player2":"TEST_P2"}'
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "20 Questions"
	
func _get_rules_text() -> String:
	return """
[font_size={32px}][b]20 Questions[/b][/font_size]

[font_size={24px}][b]Goal[/b][/font_size]
[font_size={18px}]
Player 1 tries to guess Player 2's secret answer in 20 questions or less.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• Player 2 secretly chooses an answer.
• Player 1 asks yes-or-no style questions.
• Player 2 answers Yes, No, Sometimes, or You've Guessed It.
• If Player 1 guesses correctly, Player 1 wins.
• If Player 1 reaches 20 questions without guessing correctly, Player 2 wins.
[/font_size]
"""

func _on_game_ready() -> void:
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		_my_avatar_string = player_avatar_display.get_avatar_data_string()

	if is_instance_valid(send_button):
		if not send_button.pressed.is_connected(_on_send_pressed):
			send_button.pressed.connect(_on_send_pressed)

	if is_instance_valid(questions_scroll):
		if is_instance_valid(questions_scroll.get_v_scroll_bar()):
			questions_scroll.get_v_scroll_bar().visible = false
		if is_instance_valid(questions_scroll.get_h_scroll_bar()):
			questions_scroll.get_h_scroll_bar().visible = false

	if is_instance_valid(questions_list):
		if not questions_list.resized.is_connected(_on_questions_resized):
			questions_list.resized.connect(_on_questions_resized)

		if not questions_list.child_entered_tree.is_connected(_on_questions_child_entered):
			questions_list.child_entered_tree.connect(_on_questions_child_entered)

		var sep := questions_list.get_theme_constant("separation", "VBoxContainer")
		if sep == 0:
			sep = 12
		questions_list.add_theme_constant_override("separation", sep * 2)

	if is_instance_valid(overlay):
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
		overlay.z_index = 1000

	if is_instance_valid(overlay_yes):
		if not overlay_yes.pressed.is_connected(func(): _overlay_click(1)):
			overlay_yes.pressed.connect(func(): _overlay_click(1))

	if is_instance_valid(overlay_no):
		if not overlay_no.pressed.is_connected(func(): _overlay_click(2)):
			overlay_no.pressed.connect(func(): _overlay_click(2))

	if is_instance_valid(overlay_some):
		if not overlay_some.pressed.is_connected(func(): _overlay_click(3)):
			overlay_some.pressed.connect(func(): _overlay_click(3))

	if is_instance_valid(overlay_correct):
		overlay_correct.visible = true
		overlay_correct.disabled = false
		overlay_correct.mouse_filter = Control.MOUSE_FILTER_STOP

		if not overlay_correct.pressed.is_connected(func(): _overlay_click(4)):
			overlay_correct.pressed.connect(func(): _overlay_click(4))

	if is_instance_valid(text_box):
		if not text_box.focus_entered.is_connected(_on_text_focus_entered):
			text_box.focus_entered.connect(_on_text_focus_entered)

		if not text_box.focus_exited.is_connected(_on_text_focus_exited):
			text_box.focus_exited.connect(_on_text_focus_exited)

		if not text_box.text_changed.is_connected(_on_text_changed_sanitize):
			text_box.text_changed.connect(_on_text_changed_sanitize)

	if is_instance_valid(questions_scroll):
		var vbar := questions_scroll.get_v_scroll_bar()
		if vbar:
			vbar.visible = false
			vbar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	await get_tree().process_frame

	_make_scrollbars_invisible()
	_update_ui_interactivity()
	call_deferred("_maybe_show_answer_popup")
	
func _get_s(parsed_dict: Dictionary, key: String, def: String = "") -> String:
	if not parsed_dict.has(key):
		return def
	var v: Variant = parsed_dict[key]
	if typeof(v) == TYPE_ARRAY and v.size() > 0:
		return str(v[0])
	return str(v)

func _on_text_focus_entered() -> void:
	if game_over:
		return
	OpLog.d(LOG_TAG, "text_focus_entered")
	questions_container.visible = false

func _on_text_focus_exited() -> void:
	OpLog.d(LOG_TAG, "text_focus_exited")
	questions_container.visible = true

func _flash_textbox_red() -> void:
	if not is_instance_valid(text_box):
		return
	var t := create_tween()
	text_box.modulate = Color(1, 0.6, 0.6, 1)
	t.tween_property(text_box, "modulate", Color(1, 1, 1, 1), 0.25).set_delay(0.15)

func _sanitize_input(raw: String, final_pass: bool = false) -> String:
	var s := raw
	s = s.replace("\r", " ").replace("\n", " ")

	if final_pass:
		var re := RegEx.new()
		re.compile("[ ]+")
		s = re.sub(s, " ", true)
		s = s.strip_edges()

	s = s.replace("^&*", "⋆")
	s = s.replace("|", "¦")
	s = s.replace("[", "⟦")
	s = s.replace("]", "⟧")
	s = s.replace("<", "‹").replace(">", "›")
	s = s.replace("[/","⟦/")
	s = s.replace("\\", "⧵")

	var MAX := 140
	if s.length() > MAX:
		s = s.substr(0, MAX)
		if final_pass:
			s = s.strip_edges()

	return s
	
func _on_text_changed_sanitize() -> void:
	if not is_instance_valid(text_box):
		return
	var caret := text_box.get_caret_column()
	var cleaned := _sanitize_input(text_box.text)
	if cleaned != text_box.text:
		text_box.text = cleaned
		text_box.set_caret_column(min(caret, cleaned.length()))

func _get_b(parsed_dict: Dictionary, key: String, def: bool = false) -> bool:
	if not parsed_dict.has(key):
		return def
	var v: Variant = parsed_dict[key]
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) == TYPE_ARRAY and v.size() > 0:
		return str(v[0]).to_lower() == "true"
	return str(v).to_lower() == "true"
	
func _process(_delta: float) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	var h := DisplayServer.virtual_keyboard_get_height()
	if h != _kb_last_h:
		_kb_last_h = h
		var now_open := h > 0
		if now_open != _kb_open:
			_kb_open = now_open
			if _kb_open:
				_on_keyboard_open(h)
			else:
				_on_keyboard_closed()
				
func _on_keyboard_open(_height: int) -> void:
	if is_instance_valid(questions_container):
		questions_container.visible = false

	if i_am_player == 1 and is_instance_valid(bottom_items):
		bottom_items.set_anchors_preset(Control.PRESET_TOP_WIDE)
		var target_y := 8.0 + (_desc_rich.get_rect().size.y if is_instance_valid(_desc_rich) else 32.0)
		var t := create_tween()
		t.tween_property(bottom_items, "position:y", target_y, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_keyboard_closed() -> void:
	if is_instance_valid(questions_container):
		questions_container.visible = true
	if is_instance_valid(bottom_items):
		bottom_items.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		var t := create_tween()
		t.tween_property(bottom_items, "position:y", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	
func _set_game_data(data_json: String) -> void:
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", data_json])

	var parsed_v: Variant = JSON.parse_string(data_json)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, ["set_game_data_parse_failed raw=", data_json])
		return

	var parsed: Dictionary = parsed_v
	last_raw_payload = parsed.duplicate(true)

	game_over = false
	winner = 0
	spectator_mode = false
	stop_waiting_animation()

	if is_instance_valid(win_loss_label):
		win_loss_label.visible = false
		win_loss_label.text = ""
		win_loss_label.scale = Vector2.ONE

	is_my_turn = _get_b(parsed, "isYourTurn", false)
	server_player_hint = int(_get_s(parsed, "player", "1"))
	secret_answer = _get_s(parsed, "answer", secret_answer)
	game_id = _get_s(parsed, "id", game_id)

	var player1: String = _get_s(parsed, "player1", "")
	var player2: String = _get_s(parsed, "player2", "")
	var incoming_my_id: String = _get_s(parsed, "myPlayerId", "")

	if my_uuid == "" and incoming_my_id != "":
		my_uuid = incoming_my_id

	_local_player_id = my_uuid if my_uuid != "" else incoming_my_id
	_player1_id = player1
	_player2_id = player2

	OpLog.i(LOG_TAG, [
		"set_game_data_ids my_uuid=", my_uuid,
		" incoming_my_id=", incoming_my_id,
		" player1=", _player1_id,
		" player2=", _player2_id,
		" isYourTurn=", is_my_turn,
		" server_player_hint=", server_player_hint,
		" game_id=", game_id
	])

	spectator_mode = false

	if _local_player_id != "":
		if _player1_id != "" and _local_player_id == _player1_id:
			i_am_player = 1
		elif _player2_id != "" and _local_player_id == _player2_id:
			i_am_player = 2
		elif _player1_id == "" and _player2_id == "":
			i_am_player = 2 if server_player_hint == 1 else 1

			if i_am_player == 1:
				_player1_id = _local_player_id
			else:
				_player2_id = _local_player_id
		elif _player1_id == "":
			i_am_player = 1
			_player1_id = _local_player_id
		elif _player2_id == "":
			i_am_player = 2
			_player2_id = _local_player_id
		else:
			spectator_mode = true
			i_am_player = 1
	else:
		i_am_player = 2 if server_player_hint == 1 else 1

	OpLog.i(LOG_TAG, [
		"resolved_player i_am_player=", i_am_player,
		" spectator=", spectator_mode,
		" local_player_id=", _local_player_id,
		" player1=", _player1_id,
		" player2=", _player2_id,
		" turn_before_question_logic=", is_my_turn
	])

	_set_wait_base_text()
	_update_description_fill()

	var avatar1_string := _get_s(parsed, "avatar1", "")
	var avatar2_string := _get_s(parsed, "avatar2", "")

	if avatar1_string != "":
		_avatar1_raw = avatar1_string

	if avatar2_string != "":
		_avatar2_raw = avatar2_string

	_opponent_avatar_data = GameUtils._parse_avatar_string(_avatar1_raw)
	_answer_avatar_data = GameUtils._parse_avatar_string(_avatar2_raw)

	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("update_avatar_from_data"):
		player_avatar_display.call_deferred("update_avatar_from_data", _answer_avatar_data)

	questions.clear()

	if parsed.has("questions"):
		var raw: Variant = parsed["questions"]
		var joined: String = ""

		if typeof(raw) == TYPE_ARRAY and raw.size() > 0:
			joined = str(raw[0])
		elif typeof(raw) == TYPE_STRING:
			joined = str(raw)

		OpLog.d(LOG_TAG, [
			"questions_field len=", joined.length(),
			" type=", typeof(raw)
		])

		if joined != "":
			var cleaned: String = joined.replace("['", "").replace("']", "")
			cleaned = cleaned.replace("[", "").replace("]", "")

			var chunks: PackedStringArray = cleaned.split("|", false)

			for chunk in chunks:
				var parts: PackedStringArray = chunk.split("^&*", false)

				if parts.size() >= 3:
					var q_text: String = parts[0]
					var q_idx: int = int(parts[1])
					var q_resp: int = int(parts[2])
					questions.append({ "text": q_text, "idx": q_idx, "resp": q_resp })
				elif chunk.strip_edges() != "":
					OpLog.w(LOG_TAG, ["questions_parse_fallback chunk=", chunk])
					questions.append({ "text": chunk, "idx": questions.size() + 1, "resp": 0 })

	if parsed.has("response") and questions.size() > 0:
		var resp_txt: String = _get_s(parsed, "response", "")
		questions[-1]["response_text"] = resp_txt

	var unanswered := 0

	if questions.size() > 0:
		for q in questions:
			if int(q.get("resp", 0)) == 0:
				unanswered += 1

		if unanswered == 0 and i_am_player == 1:
			is_my_turn = true
		elif unanswered != 0 and i_am_player == 2:
			is_my_turn = true
		else:
			is_my_turn = false

	OpLog.i(LOG_TAG, [
		"questions_loaded count=", questions.size(),
		" unanswered=", unanswered,
		" i_am_player=", i_am_player,
		" final_is_my_turn=", is_my_turn,
		" game_over=", game_over
	])

	_renumber_from_one()

	if parsed.has("winner") and _get_s(parsed, "winner", "") != "":
		var winner_payload := _get_s(parsed, "winner", "")
		OpLog.event(LOG_TAG, ["winner_payload_received payload=", winner_payload])
		_apply_winner_payload(winner_payload, player1, player2)
	else:
		check_win()

	_update_upcoming_input_chip_color()
	_replay_from_state()
	_render_all_questions()
	_update_ui_interactivity()

	if game_over:
		stop_waiting_animation()
	elif not is_my_turn:
		_set_wait_base_text()
		start_waiting_animation()
	else:
		stop_waiting_animation()
		_maybe_show_answer_popup()

func _show_result_from_state(state: String, spectator_winner_player: int = 0) -> void:
	game_over = true
	is_my_turn = false

	stop_waiting_animation()
	_hide_answer_overlay()

	if is_instance_valid(bottom_items):
		bottom_items.visible = false

	if is_instance_valid(text_box):
		text_box.editable = false

	if is_instance_valid(send_button):
		send_button.disabled = true

	if state == "0":
		winner = 0
	elif spectator_mode:
		winner = 1 if spectator_winner_player == 1 else -1
	elif state == "1":
		winner = 1 if i_am_player == 1 else -1
	else:
		winner = -1 if i_am_player == 1 else 1

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
	elif state == "1":
		win_loss_label.text = "YOU WIN!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

		if is_instance_valid(player_avatar_display):
			GameUtils._show_win_burst(player_avatar_display)
	else:
		win_loss_label.text = "YOU LOSE"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

		if is_instance_valid(player_avatar_display):
			GameUtils._show_win_burst(player_avatar_display)

	win_loss_label.visible = true
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2.0

	var tween_in := create_tween()
	tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _apply_winner_payload(winner_payload: String, player1_id: String = "", player2_id: String = "") -> void:
	OpLog.event(LOG_TAG, [
		"apply_winner_payload payload=", winner_payload,
		" player1=", player1_id,
		" player2=", player2_id,
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

		if sender_uuid == player1_id:
			sender_player = 1
		elif sender_uuid == player2_id:
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

	var any_correct := false
	var answered := 0

	for q in questions:
		var r := int(q.get("resp", 0))

		if r > 0:
			answered += 1

		if r == 4:
			any_correct = true

	OpLog.d(LOG_TAG, [
		"check_win answered=", answered,
		" qcount=", questions.size(),
		" any_correct=", any_correct,
		" max=", MAX_QUESTIONS,
		" i_am_player=", i_am_player,
		" spectator=", spectator_mode
	])

	if any_correct:
		OpLog.event(LOG_TAG, "game_over player1_wins guessed_correctly")

		if spectator_mode:
			_show_result_from_state("1", 1)
		else:
			_show_result_from_state("1" if i_am_player == 1 else "-1")

		return true

	if answered >= MAX_QUESTIONS:
		OpLog.event(LOG_TAG, "game_over player2_wins max_questions_reached")

		if spectator_mode:
			_show_result_from_state("-1", 2)
		else:
			_show_result_from_state("1" if i_am_player == 2 else "-1")

		return true

	game_over = false
	winner = 0
	return false

func _question_color_for_index(idx: int) -> Color:
	var deg := (360.0 / 20.0) * float(idx)
	var h := fposmod(deg / 360.0, 1.0)
	return Color.from_hsv(h, 0.70, 0.95, 1.0)

func _update_upcoming_input_chip_color() -> void:
	if not is_instance_valid(questions_text_container):
		OpLog.w(LOG_TAG, "update_chip_color_missing_container")
		return
	var next_number := questions.size() + 1
	var c := _question_color_for_index(next_number)
	var sb := questions_text_container.get_theme_stylebox("panel")
	OpLog.d(LOG_TAG, ["update_chip_color next_number=", next_number, " color=", c])
	var sbf := sb as StyleBoxFlat
	if sbf:
		sbf.bg_color = c
	else:
		var newsb := StyleBoxFlat.new()
		newsb.bg_color = c
		newsb.corner_radius_top_left = 12
		newsb.corner_radius_top_right = 12
		newsb.corner_radius_bottom_left = 12
		newsb.corner_radius_bottom_right = 12
		newsb.content_margin_left = 12
		newsb.content_margin_right = 12
		newsb.content_margin_top = 10
		newsb.content_margin_bottom = 10
		questions_text_container.add_theme_stylebox_override("panel", newsb)

	questions_text_container.queue_redraw()

func _make_scrollbars_invisible() -> void:
	if not is_instance_valid(questions_scroll):
		return
	var sb_trans := StyleBoxFlat.new()
	sb_trans.bg_color = Color(1,1,1,0)
	sb_trans.draw_center = true
	sb_trans.content_margin_left = 0
	sb_trans.content_margin_right = 0
	sb_trans.content_margin_top = 0
	sb_trans.content_margin_bottom = 0

	var vbar := questions_scroll.get_v_scroll_bar()
	if vbar:
		vbar.add_theme_stylebox_override("scroll", sb_trans)
		vbar.add_theme_stylebox_override("grabber", sb_trans)
		vbar.add_theme_stylebox_override("grabber_highlight", sb_trans)
		vbar.add_theme_stylebox_override("grabber_pressed", sb_trans)
		vbar.self_modulate.a = 0.0
		vbar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbar := questions_scroll.get_h_scroll_bar()
	if hbar:
		hbar.add_theme_stylebox_override("scroll", sb_trans)
		hbar.add_theme_stylebox_override("grabber", sb_trans)
		hbar.add_theme_stylebox_override("grabber_highlight", sb_trans)
		hbar.add_theme_stylebox_override("grabber_pressed", sb_trans)
		hbar.self_modulate.a = 0.0
		hbar.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _replay_from_state() -> void:
	OpLog.d(LOG_TAG, [
		"replay_state i_am_player=", i_am_player,
		" is_my_turn=", is_my_turn,
		" answer=", secret_answer,
		" qcount=", questions.size()
	])

	for q in questions:
		OpLog.d(LOG_TAG, [
			"replay_question idx=", q.get("idx", -1),
			" text=", q.get("text", ""),
			" resp=", int(q.get("resp", 0))
		])

func _on_send_pressed() -> void:
	if spectator_mode or game_over or (not is_my_turn) or (not is_instance_valid(text_box)):
		OpLog.w(LOG_TAG, [
			"send_pressed_blocked spectator=", spectator_mode,
			" game_over=", game_over,
			" is_my_turn=", is_my_turn,
			" text_box_valid=", is_instance_valid(text_box)
		])
		return

	var raw := text_box.text
	var cleaned := _sanitize_input(raw, true)

	if cleaned == "":
		OpLog.w(LOG_TAG, ["empty_question_blocked raw_len=", raw.length()])
		_flash_textbox_red()
		_on_text_focus_exited()
		return

	var text_to_send := cleaned

	if not text_to_send.ends_with("?"):
		text_to_send += "?"

	var next_idx: int = (int(questions[-1]["idx"]) + 1) if questions.size() > 0 else 1
	var resp_code: int = 0

	questions.append({ "text": text_to_send, "idx": next_idx, "resp": resp_code })

	OpLog.event(LOG_TAG, [
		"question_added idx=", next_idx,
		" text=", text_to_send,
		" qcount=", questions.size(),
		" i_am_player=", i_am_player
	])

	check_win()
	_render_all_questions()
	_update_upcoming_input_chip_color()
	_smooth_scroll_to_bottom()

	if i_am_player == 1:
		var asked_count := questions.size()

		if asked_count >= MAX_QUESTIONS:
			check_win()
			_update_ui_interactivity()
			OpLog.event(LOG_TAG, [
				"max_questions_reached asked_count=", asked_count,
				" game_over=", game_over,
				" winner=", winner
			])

	send_game()

	text_box.text = ""
	DisplayServer.virtual_keyboard_hide()
	_on_text_focus_exited()

	if game_over:
		stop_waiting_animation()

	_update_description_fill()

func _apply_answer_code_to_idx(target_idx: int, code: int) -> void:
	if game_over or i_am_player != 2 or questions.size() == 0:
		OpLog.w(LOG_TAG, [
			"answer_blocked idx=", target_idx,
			" code=", code,
			" game_over=", game_over,
			" i_am_player=", i_am_player,
			" qcount=", questions.size()
		])
		return

	var found := false

	for i in range(questions.size()):
		if int(questions[i].get("idx", -1)) == target_idx and int(questions[i].get("resp", 0)) == 0:
			questions[i]["resp"] = code
			found = true
			break

	if not found:
		OpLog.w(LOG_TAG, [
			"answer_not_found_or_already_answered idx=", target_idx,
			" code=", code
		])
		return

	OpLog.event(LOG_TAG, [
		"answer_applied idx=", target_idx,
		" code=", code,
		" text=", _response_text(code),
		" qcount=", questions.size()
	])

	_render_all_questions()
	check_win()

	if code == 4:
		OpLog.event(LOG_TAG, [
			"guessed_it_selected idx=", target_idx,
			" game_over=", game_over,
			" winner=", winner
		])

	send_game()
	_update_ui_interactivity()

	if game_over:
		_hide_answer_overlay()
		stop_waiting_animation()

	dbg("apply_idx: target_idx=%d code=%d i_am_player=%d game_over=%s qcount=%d" % [target_idx, code, i_am_player, str(game_over), questions.size()])

func _apply_answer_code_to_pending(code: int) -> void:
	if game_over or i_am_player != 2 or questions.size() == 0:
		return
	for q in questions:
		if int(q.get("resp", 0)) == 0:
			var idx := int(q.get("idx", -1))
			if idx != -1:
				_apply_answer_code_to_idx(idx, code)
			return

func send_game() -> void:
	if spectator_mode:
		OpLog.w(LOG_TAG, "send_game_blocked spectator=true")
		return

	if _local_player_id == "":
		_local_player_id = my_uuid

	if _player1_id == "" and i_am_player == 1 and _local_player_id != "":
		_player1_id = _local_player_id

	if _player2_id == "" and i_am_player == 2 and _local_player_id != "":
		_player2_id = _local_player_id

	var chunks: Array[String] = []

	for q in questions:
		var server_idx := int(q["idx"]) - 1
		var c := "%s^&*%d^&*%d" % [str(q["text"]), server_idx, int(q["resp"])]
		chunks.append(c)

	var questions_field := "|][".join(chunks)

	var payload: Dictionary = {
		"game": "questions",
		"id": game_id,
		"player": str(i_am_player),
		"questions": questions_field
	}

	if _player1_id != "":
		payload["player1"] = _player1_id

	if _player2_id != "":
		payload["player2"] = _player2_id

	if i_am_player == 1 and questions.size() > 0:
		var latest_question: String = str(questions[-1].get("text", "")).strip_edges()

		if latest_question != "":
			payload["description"] = latest_question
			OpLog.d(LOG_TAG, ["description_set latest_question=", latest_question])

	var my_avatar := _my_avatar_string

	if my_avatar == "" and is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		my_avatar = player_avatar_display.get_avatar_data_string()

	if i_am_player == 2:
		if my_avatar != "":
			payload["avatar2"] = my_avatar
		if _avatar1_raw != "":
			payload["avatar1"] = _avatar1_raw
	else:
		if my_avatar != "":
			payload["avatar1"] = my_avatar
		if _avatar2_raw != "":
			payload["avatar2"] = _avatar2_raw

	check_win()

	if game_over:
		var outgoing_state := "0"

		if winner == 1:
			outgoing_state = "1" if i_am_player == 1 else "-1"
		elif winner == -1:
			outgoing_state = "1" if i_am_player == 2 else "-1"

		var sender_id := _local_player_id if _local_player_id != "" else my_uuid
		payload["winner"] = sender_id + "|" + outgoing_state

		OpLog.event(LOG_TAG, [
			"send_game_winner winner=", payload["winner"],
			" local_winner=", winner,
			" i_am_player=", i_am_player
		])

	var json := JSON.stringify(payload)

	OpLog.event(LOG_TAG, [
		"send_game_out qcount=", questions.size(),
		" unanswered=", _count_unanswered(),
		" i_am_player=", i_am_player,
		" is_my_turn=", is_my_turn,
		" game_over=", game_over,
		" has_winner=", payload.has("winner"),
		" has_description=", payload.has("description"),
		" raw=", json
	])

	send_game_data(json)

	if game_over:
		stop_waiting_animation()
	else:
		is_my_turn = false
		play_sent_animation()
		_update_ui_interactivity()

func _update_ui_interactivity() -> void:
	var enable_input := (is_my_turn and not game_over and i_am_player == 1 and not spectator_mode)

	if is_instance_valid(send_button):
		send_button.disabled = not enable_input
	if is_instance_valid(text_box):
		text_box.editable = enable_input

	if is_instance_valid(bottom_items):
		bottom_items.visible = (i_am_player == 1) and (not spectator_mode) and (not game_over) and (not _waiting_active)

	dbg("ui: enable_input=%s, i_am_player=%d, is_my_turn=%s, game_over=%s" % [str(is_my_turn and not game_over and i_am_player == 1), i_am_player, str(is_my_turn), str(game_over)])
	if is_instance_valid(bottom_items):
		dbg("ui: bottom_items.visible=%s" % str(bottom_items.visible))

	var should_wait := (not game_over) and (not is_my_turn) and (not _sent_animation_active)

	if should_wait and not _waiting_active:
		_set_wait_base_text()
		start_waiting_animation()
	elif (not should_wait) and _waiting_active:
		stop_waiting_animation()

func _render_all_questions() -> void:
	if not is_instance_valid(questions_list):
		return
	dbg("render: rebuilding list; questions=%d" % questions.size())
	for c in questions_list.get_children():
		c.queue_free()
	var sorted: Array[Dictionary] = []
	for q in questions:
		sorted.append(q)
	var cmp := func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["idx"]) < int(b["idx"])
	sorted.sort_custom(cmp)
	var latest_idx := 0
	if sorted.size() > 0:
		latest_idx = int(sorted[-1]["idx"])
	var hasquestions = false
	for q in sorted:
		hasquestions = true
		var row := _make_question_row(q, int(q["idx"]) == latest_idx)
		questions_list.add_child(row)
	
	if hasquestions == true:
		question_mark_filler.visible = false	

	if is_instance_valid(questions_scroll):
		await get_tree().process_frame
		_smooth_scroll_to_bottom()
	_update_upcoming_input_chip_color()
	dbg("render: finished; latest_idx=%d" % latest_idx)
	
func _smooth_scroll_to_bottom() -> void:
	if not is_instance_valid(questions_scroll):
		return
	var bar := questions_scroll.get_v_scroll_bar()
	if bar == null:
		return
	await get_tree().process_frame
	var target: float = bar.max_value
	if _scroll_tween and _scroll_tween.is_running():
		_scroll_tween.stop()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(questions_scroll, "scroll_vertical", target, 0.25)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
func _on_questions_resized() -> void:
	_smooth_scroll_to_bottom()

func _on_questions_child_entered(_node: Node) -> void:
	_smooth_scroll_to_bottom()

func _make_question_row(q: Dictionary, is_latest: bool) -> HBoxContainer:
	var idx := int(q["idx"])
	var col := _question_color_for_index(idx)
	var resp_code := int(q.get("resp", 0))

	dbg("row_build idx=%d latest=%s resp=%d" % [idx, str(is_latest), resp_code])

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 72)
	row.add_theme_constant_override("separation", 12)

	var left_holder := Control.new()
	left_holder.name = "LeftHolder"
	left_holder.custom_minimum_size = Vector2(72, 56)
	left_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var left_stack := Control.new()
	left_stack.name = "LeftStack"
	left_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_stack.set_anchors_preset(Control.PRESET_FULL_RECT, false)
	left_stack.offset_left = 0
	left_stack.offset_right = 0
	left_stack.offset_top = 0
	left_stack.offset_bottom = 0
	left_stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left_holder.add_child(left_stack)
	row.add_child(left_holder)

	if is_latest and OpponentAvatarScene != null:
		dbg("row_avatar creating latest_idx=%d" % idx)
		var opp_inst := OpponentAvatarScene.instantiate()
		dbg("row_avatar instantiated type=%s" % opp_inst.get_class())

		if opp_inst is Control:
			opp_inst.name = "OpponentAvatar"
			opp_inst.set_anchors_preset(Control.PRESET_FULL_RECT, false)
			opp_inst.offset_left = 24
			opp_inst.offset_right = 0
			opp_inst.offset_top = 15
			opp_inst.offset_bottom = 0
			opp_inst.custom_minimum_size = Vector2(72, 56)
			opp_inst.mouse_filter = Control.MOUSE_FILTER_IGNORE
			left_stack.add_child(opp_inst)
			opp_inst.scale = Vector2(0.75, 0.75)
			dbg("row_avatar added left_stack_size=%s" % str(left_stack.get_rect().size))

			if _opponent_avatar_data.is_empty():
				OpLog.w(LOG_TAG, "row_avatar_data_empty_using_defaults")
				_opponent_avatar_data = GameUtils._parse_avatar_string("")
			else:
				dbg("row_avatar using_provided_avatar_data")

			if opp_inst.has_method("update_avatar_from_data"):
				dbg("row_avatar calling_update_avatar_from_data")
				opp_inst.call_deferred("update_avatar_from_data", _opponent_avatar_data)
			else:
				OpLog.w(LOG_TAG, [
					"row_avatar_missing_update_method node=", opp_inst,
					" script=", opp_inst.get_script()
				])
		else:
			OpLog.w(LOG_TAG, ["row_avatar_instance_not_control got=", opp_inst])
	else:
		dbg("row_history_question_mark is_latest=%s" % str(is_latest))
		var qmark := Label.new()
		qmark.name = "HistoryQuestionMark"
		qmark.text = "?"
		qmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qmark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		qmark.add_theme_font_size_override("font_size", 48)
		qmark.add_theme_color_override("font_color", col)
		qmark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qmark.size_flags_vertical = Control.SIZE_EXPAND_FILL
		qmark.set_anchors_preset(Control.PRESET_FULL_RECT)
		left_stack.add_child(qmark)
		
	var card := PanelContainer.new()
	card.name = "QuestionCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 56)

	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)

	var inner := HBoxContainer.new()
	inner.name = "Inner"
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	card.add_child(inner)

	var num_lbl := Label.new()
	num_lbl.name = "IdxLabel"
	num_lbl.text = str(idx) + "."
	num_lbl.add_theme_color_override("font_color", Color.BLACK)
	num_lbl.add_theme_font_size_override("font_size", 22)
	num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num_lbl.custom_minimum_size = Vector2(36, 0)
	inner.add_child(num_lbl)

	var q_lbl := Label.new()
	q_lbl.name = "TextLabel"
	q_lbl.text = str(q["text"])
	q_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_lbl.add_theme_color_override("font_color", Color.BLACK)
	q_lbl.add_theme_font_size_override("font_size", 20)
	inner.add_child(q_lbl)

	if resp_code > 0:
		var chip := _make_response_chip(resp_code)
		inner.add_child(chip)

	row.add_child(card)
	call_deferred("_debug_print_row_layout", row)
	return row

func _debug_print_row_layout(row: HBoxContainer) -> void:
	if not is_instance_valid(row):
		return

	var left_stack := row.get_node_or_null("LeftHolder/LeftStack") as Control
	var avatar := left_stack.get_node_or_null("OpponentAvatar") if left_stack else null

	dbg("row_layout row_size=%s left_stack_size=%s" % [
		str(row.get_rect().size),
		str(left_stack.get_rect().size if left_stack else Vector2.ZERO)
	])

	if avatar:
		var avatar_control := avatar as Control
		dbg("row_layout avatar_rect=%s anchors=(%s,%s,%s,%s)" % [
			str(avatar_control.get_rect()),
			str(avatar_control.anchor_left),
			str(avatar_control.anchor_top),
			str(avatar_control.anchor_right),
			str(avatar_control.anchor_bottom)
		])

func _make_response_chip(code: int) -> Control:
	var txt := _response_text(code)
	var col := _response_color(code)

	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(110, 36)

	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	holder.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 16)
	if code == 2:
		lbl.add_theme_color_override("font_color", Color(1,1,1,1))
	holder.add_child(lbl)

	return holder
			
func _on_inline_answer_pressed(q_idx: int, code: int) -> void:
	_apply_answer_code_to_idx(q_idx, code)
	
func _response_text(code: int) -> String:
	if code == 1:
		return "Yes"
	elif code == 2:
		return "No"
	elif code == 3:
		return "Sometimes"
	elif code == 4:
		return "You've Guessed It!"
	return ""

func _response_color(code: int) -> Color:
	if code == 1:
		return Color("b3b3b3ff")  # green
	elif code == 2:
		return Color("1a1a1aff")  # dark/black
	elif code == 3:
		return Color("7380b3ff")  # gray/blue
	elif code == 4:
		return Color("f2bf33ff")  # gold
	return Color(0.30, 0.30, 0.30, 1.0)

func _badge_color_for_index(idx: int) -> Color:
	var h := float(max(idx, 1) - 1) / 19.0
	if h >= 1.0:
		h = 0.0
	var s := 0.70
	var v := 0.95
	return Color.from_hsv(h, s, v, 1.0)

func _pending_unanswered_question() -> Dictionary:
	for q in questions:
		if int(q.get("resp", 0)) == 0:
			dbg("pending: next unanswered idx=%d text='%s'" % [int(q.get("idx", -1)), str(q.get("text", ""))])
			return q
	dbg("pending: none")
	return {}

func _maybe_show_answer_popup() -> void:
	dbg("maybe_overlay: enter p=%d turn=%s game_over=%s unanswered=%d" % [
		i_am_player, str(is_my_turn), str(game_over), _count_unanswered()
	])

	if spectator_mode or i_am_player != 2 or not is_my_turn or game_over:
		_hide_answer_overlay()
		return

	var pending := _pending_unanswered_question()
	if pending.is_empty():
		_hide_answer_overlay()
		return

	var idx := int(pending.get("idx", -1))
	var txt := str(pending.get("text", ""))
	var col := _question_color_for_index(idx)

	_show_answer_overlay_for(idx, txt, col)

	if _count_unanswered() > 0 and is_instance_valid(overlay) and not overlay.visible:
		dbg("overlay: was supposed to be visible; forcing show/front")
		overlay.visible = true
		overlay.move_to_front()
		overlay.z_index = 1000
	
func _overlay_click(code: int) -> void:
	dbg("overlay: click code=%d on idx=%d" % [code, _overlay_idx])
	if _overlay_idx == -1:
		_hide_answer_overlay()
		return

	var clicked_idx := _overlay_idx
	_apply_answer_code_to_idx(clicked_idx, code)
	_hide_answer_overlay()

	if code == 4:
		stop_waiting_animation()
		_update_ui_interactivity()
		return

	if not game_over and i_am_player == 2 and is_my_turn:
		_maybe_show_answer_popup()

func _on_overlay_btn_pressed(code: int) -> void:
	_apply_answer_code_to_pending(code)

func _count_unanswered() -> int:
	var c := 0
	for q in questions:
		if int(q.get("resp", 0)) == 0:
			c += 1
	return c

func _set_overlay_style_color(c: Color) -> void:
	if not is_instance_valid(overlay): return
	var card := overlay.get_node_or_null("Card") as PanelContainer
	var target := card if card else overlay

	var sb: StyleBox = target.get_theme_stylebox("panel")
	var sbf := sb as StyleBoxFlat
	if sbf:
		sbf.bg_color = c
	else:
		var newsb := StyleBoxFlat.new()
		newsb.bg_color = c
		newsb.corner_radius_top_left = 16
		newsb.corner_radius_top_right = 16
		newsb.corner_radius_bottom_left = 16
		newsb.corner_radius_bottom_right = 16
		newsb.content_margin_left = 14
		newsb.content_margin_right = 14
		newsb.content_margin_top = 12
		newsb.content_margin_bottom = 12
		target.add_theme_stylebox_override("panel", newsb)

func _show_answer_overlay_for(idx: int, text: String, col: Color) -> void:
	if not is_instance_valid(overlay):
		dbg("overlay: node missing; cannot show")
		return
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 1000
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	_set_overlay_style_color(col)

	if is_instance_valid(overlay_num):
		overlay_num.text = str(idx) + "."
	if is_instance_valid(overlay_text):
		overlay_text.text = text

	_overlay_idx = idx

	for btn in [overlay_yes, overlay_no, overlay_some, overlay_correct]:
		if is_instance_valid(btn):
			btn.visible = true
			btn.disabled = false
			btn.mouse_filter = Control.MOUSE_FILTER_STOP

	overlay.visible = true
	OpLog.event(LOG_TAG, ["answer_overlay_visible idx=", idx, " text=", text])
	overlay.move_to_front()
	var vp_w := get_viewport_rect().size.x
	var card := overlay.get_node_or_null("Card") as Control
	var target := card if card else overlay

	target.set_anchors_preset(Control.PRESET_CENTER)
	target.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	target.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	target.custom_minimum_size.x = vp_w * 0.8


	var r := overlay.get_global_rect()
	dbg("overlay: SHOW idx=%d text='%s' unanswered=%d turn=%s p=%d rect=(%.1f,%.1f,%.1f,%.1f) visible=%s z=%d top_level=%s" % [
		idx, text, _count_unanswered(), str(is_my_turn), i_am_player,
		r.position.x, r.position.y, r.size.x, r.size.y,
		str(overlay.visible), overlay.z_index, str(overlay.top_level)
	])

func _hide_answer_overlay() -> void:
	if is_instance_valid(overlay):
		overlay.visible = false
	dbg("overlay: HIDE")
	
func dbg(msg: String) -> void:
	if DEBUG_20Q:
		OpLog.d(LOG_TAG, msg)

func _update_description_fill() -> void:
	if not is_instance_valid(_desc_rich):
		return

	_desc_rich.bbcode_enabled = true
	_desc_rich.text = ""

	if spectator_mode:
		_desc_rich.parse_bbcode("[font_size=18]You are watching this game.[/font_size]")
		_desc_rich.visible = true
		return

	if i_am_player == 2:
		var word_text := secret_answer.strip_edges()

		if word_text == "":
			word_text = "..."

		var your_word := "[font_size=20]Your word:[/font_size]\n"
		var the_word := "[font_size=34][b]%s[/b][/font_size]" % word_text
		_desc_rich.parse_bbcode(your_word + the_word)
		_desc_rich.visible = true
		return

	if i_am_player == 1:
		_desc_rich.parse_bbcode("[font_size=18]Your goal is to guess the answer in 20 questions or less.[/font_size]")
		_desc_rich.visible = true
		return

	_desc_rich.visible = false

var DEBUG_20Q := true

func _set_wait_base_text() -> void:
	_questions_wait_text = "Waiting for an answer" if i_am_player == 1 else "Waiting for a question"

	if is_instance_valid(wait_for_label):
		wait_for_label.text = _questions_wait_text

func _renumber_from_one() -> void:
	if questions.is_empty():
		return
	var arr := questions.duplicate()
	arr.sort_custom(func(a, b): return int(a["idx"]) < int(b["idx"]))
	for i in arr.size():
		arr[i]["idx"] = i + 1
	questions = arr

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		OpLog.w(LOG_TAG, "sent_animation_missing_label")
		_set_wait_base_text()
		start_waiting_animation()
		return

	_sent_animation_active = true
	stop_waiting_animation()

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
		_sent_animation_active = false

		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0

		if not game_over and not spectator_mode and not is_my_turn:
			_set_wait_base_text()
			start_waiting_animation()
		else:
			stop_waiting_animation()
	)
