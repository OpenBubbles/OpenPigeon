extends Control

@onready var send_button: Button = %SendButton
@onready var text_box: TextEdit = %TextBox
@onready var questions_scroll: ScrollContainer = %QuestionsScroll
@onready var questions_container: CenterContainer = %QuestionsContainer
@onready var questions_list: VBoxContainer = %QuestionsList
@onready var question_mark_filler: RichTextLabel		= %QuestionMark
@onready var wait_for_label: Label = %WaitForLabel
@onready var dot_timer: Timer = %DotTimer
@onready var player_avatar_display: Control		= %PlayerAvatarDisplay
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

var my_uuid: String = ""

const OpponentAvatarScene: PackedScene = preload("res://global/avatar_textures/AvatarThumbnail.tscn")
const AvatarWinAnimScene: PackedScene = preload("res://global/avatar_textures/avatar_win_anim.tscn")
const MUSIC_STREAM := preload("res://global/audio/20questions.ogg")
var _opponent_avatar_data: Dictionary = {}

var is_my_turn: bool = false
var mediaPlugin = null
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
var BASE_WAIT_TEXT := ""
var dot_count := 0
var _waiting_active := false
var spectator_mode: bool = false

var _input_lifted := false
var _input_orig_preset := -1
var _input_orig_position := Vector2.ZERO
var _kb_open := false
var _kb_last_h := 0


func _ready() -> void:
	var appPlugin = Engine.get_singleton("AppPlugin")
	
	if Engine.has_singleton("OpenPigeonMedia"):
		mediaPlugin = Engine.get_singleton("OpenPigeonMedia")
		print("OpenPigeonMedia plugin is available")
	else:
		print("OpenPigeonMedia plugin is not available")

	_start_music()
	
	if appPlugin and appPlugin.has_method("getSenderUUID"):
		my_uuid = String(appPlugin.getSenderUUID() or "")
	else:
		my_uuid = ""
	if is_instance_valid(send_button):
		send_button.pressed.connect(_on_send_pressed)

	if appPlugin:
		print("App plugin is available")
		appPlugin.connect("set_game_data", _set_game_data)
		my_uuid = appPlugin.getSenderUUID()
		appPlugin.onReady()
	else:
		print("App plugin is not available")
		my_uuid = "0a602920-2033-469d-aab8-5e832c5d4f6a"
		_set_game_data('{"player":"2","game":"questions","questions":"[Is it a fruit?^&*1^&*1|][Is it an Apple?^&*2^&*2|][Is it a Pear?^&*3^&*0]","game_name":"20 Questions","id":"TEST123","answer":"Pear","num":"1"}')

	_update_ui_interactivity()
	
	if is_instance_valid(questions_scroll):
		if is_instance_valid(questions_scroll.get_v_scroll_bar()):
			questions_scroll.get_v_scroll_bar().visible = false
		if is_instance_valid(questions_scroll.get_h_scroll_bar()):
			questions_scroll.get_h_scroll_bar().visible = false
	if is_instance_valid(dot_timer) and not dot_timer.timeout.is_connected(_on_dot_timer_timeout):
		dot_timer.timeout.connect(_on_dot_timer_timeout)
	if is_instance_valid(questions_list):
		questions_list.resized.connect(_on_questions_resized)
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
		overlay_yes.pressed.connect(func(): _overlay_click(1))
	if is_instance_valid(overlay_no):
		overlay_no.pressed.connect(func(): _overlay_click(2))
	if is_instance_valid(overlay_some):
		overlay_some.pressed.connect(func(): _overlay_click(3))
	if is_instance_valid(overlay_correct):
		overlay_correct.visible = true
		overlay_correct.disabled = false
		overlay_correct.mouse_filter = Control.MOUSE_FILTER_STOP
		overlay_correct.pressed.connect(func(): _overlay_click(4))

	if is_instance_valid(text_box):
		if not text_box.focus_entered.is_connected(_on_text_focus_entered):
			text_box.focus_entered.connect(_on_text_focus_entered)
		if not text_box.focus_exited.is_connected(_on_text_focus_exited):
			text_box.focus_exited.connect(_on_text_focus_exited)
		if not text_box.text_changed.is_connected(_on_text_changed_sanitize):
			text_box.text_changed.connect(_on_text_changed_sanitize)
	var vbar := questions_scroll.get_v_scroll_bar()
	if vbar:
		vbar.visible = false
		vbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	await get_tree().process_frame
	call_deferred("_maybe_show_answer_popup")
	_make_scrollbars_invisible()
	if (not is_my_turn) and (not game_over) and (not _waiting_active):
		_start_waiting()
	elif is_my_turn and (not game_over):
		_stop_waiting()
		
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
	print("Text Focus Entered")
	questions_container.visible = false
	
func _on_text_focus_exited() -> void:
	print("Text Focus Exited")
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
	var parsed_v: Variant = JSON.parse_string(data_json)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		printerr("Bad game data JSON")
		return
	var parsed: Dictionary = parsed_v
	last_raw_payload = parsed.duplicate(true)
	print("RAW DATA:", parsed)
	is_my_turn = _get_b(parsed, "isYourTurn", false)
	server_player_hint = int(_get_s(parsed, "player", "1"))
	secret_answer = _get_s(parsed, "answer", secret_answer)
	game_id = _get_s(parsed, "id", game_id)

	var player1: String = _get_s(parsed, "player1", "")
	var player2: String = _get_s(parsed, "player2", "")

	spectator_mode = false

	if player1 != "" or player2 != "":
		if my_uuid == player1:
			i_am_player = 1
		elif my_uuid == player2:
			i_am_player = 2
		else:
			spectator_mode = true
			i_am_player = 1
	else:
		i_am_player = 2 if server_player_hint == 1 else 1
		
	var opponent_avatar_key := "avatar2" if i_am_player == 1 else "avatar1"
	print("opponent_avatar_key")
	if parsed.has(opponent_avatar_key):
		var avatar_string := _get_s(parsed, opponent_avatar_key, "")
		_opponent_avatar_data = _parse_avatar_string(avatar_string)
	else:
		_opponent_avatar_data = _parse_avatar_string("")

	questions.clear()
	if parsed.has("questions"):
		var raw: Variant = parsed["questions"]
		var joined: String = ""
		if typeof(raw) == TYPE_ARRAY and raw.size() > 0:
			joined = str(raw[0])
		elif typeof(raw) == TYPE_STRING:
			joined = str(raw)

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
					questions.append({ "text": chunk, "idx": questions.size() + 1, "resp": 0 })

	if parsed.has("response") and questions.size() > 0:
		var resp_txt: String = _get_s(parsed, "response", "")
		questions[-1]["response_text"] = resp_txt
			
	dbg("set_game_data: is_my_turn=%s, server_player_hint=%s, i_am_player(pre)=%s" % [str(is_my_turn), str(server_player_hint), str(i_am_player)])
	dbg("set_game_data: parsed questions count=%d" % questions.size())
	if questions.size() > 0:
		var u := 0
		for q in questions:
			if int(q.get("resp", 0)) == 0:
				u += 1
		if u == 0 and i_am_player == 1:
			is_my_turn = true
		elif u != 0 and i_am_player == 2:
			is_my_turn = true
		else:
			is_my_turn = false
			
		dbg("set_game_data: unanswered=%d" % u)
	dbg("set_game_data: secret_answer='%s', game_over=%s" % [secret_answer, str(game_over)])
	_renumber_from_one()
	_evaluate_game_over_and_winner()
	if parsed.has("winner"):
		var winner_parts := _get_s(parsed, "winner", "").split("|", false)
		if winner_parts.size() >= 2:
			var winner_sender := String(winner_parts[0])
			var win_loss_state := int(winner_parts[1])

			game_over = true

			if win_loss_state == 0:
				winner = 0
			elif winner_sender == player1:
				winner = 1 if win_loss_state == 1 else -1
			elif winner_sender == player2:
				winner = -1 if win_loss_state == 1 else 1
	_update_upcoming_input_chip_color()
	if (not is_my_turn) and (not game_over) and (not _waiting_active):
		_start_waiting()
	elif is_my_turn and (not game_over):
		_stop_waiting()
		
	_replay_from_state()
	_render_all_questions()
	_update_ui_interactivity()
	_update_description_fill()
	_maybe_show_answer_popup()
	
func _evaluate_game_over_and_winner() -> void:
	var was_over := game_over

	var any_correct := false
	var answered := 0
	for q in questions:
		var r := int(q.get("resp", 0))
		if r > 0:
			answered += 1
		if r == 4:
			any_correct = true

	if game_over:
		pass
	elif any_correct:
		game_over = true
		winner = 1
		print("[20Q] GAME OVER: Player 1 wins (guessed correctly).")
	elif answered >= MAX_QUESTIONS:
		game_over = true
		winner = -1
		print("[20Q] GAME OVER: Player 2 wins (no correct guess in 20).")
	else:
		game_over = false
		winner = 0
		
	if game_over:
		_stop_waiting()
		_hide_answer_overlay()

		if is_instance_valid(bottom_items):
			bottom_items.visible = false
		if is_instance_valid(text_box):
			text_box.editable = false
		if is_instance_valid(send_button):
			send_button.disabled = true

		if is_instance_valid(win_loss_label):
			if winner == 0:
				win_loss_label.text = "DRAW!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
			else:
				var you_win := false

				if i_am_player == 1 and winner == 1:
					you_win = true
				elif i_am_player == 2 and winner == -1:
					you_win = true

				if you_win:
					win_loss_label.text = "YOU WIN!"
					win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
				else:
					if i_am_player != 1 and i_am_player != 2:
						win_loss_label.text = "Player 1 Wins!" if winner == 1 else "Player 2 Wins!"
						win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
					else:
						win_loss_label.text = "YOU LOSE"
						win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

			win_loss_label.visible = true

			if not was_over:
				await get_tree().process_frame
				win_loss_label.scale = Vector2.ZERO
				win_loss_label.pivot_offset = win_loss_label.size / 2.0

				var tween_in := create_tween()
				tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			else:
				win_loss_label.scale = Vector2.ONE
	
func _question_color_for_index(idx: int) -> Color:
	var deg := (360.0 / 20.0) * float(idx)
	var h := fposmod(deg / 360.0, 1.0)
	return Color.from_hsv(h, 0.70, 0.95, 1.0)

func _update_upcoming_input_chip_color() -> void:
	if not is_instance_valid(questions_text_container):
		print("NO TEXT CONTINER")
		return
	var next_number := questions.size() + 1
	var c := _question_color_for_index(next_number)
	print("Next Color: ", c)

	var sb := questions_text_container.get_theme_stylebox("panel")
	print("SB: ", sb)
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

func _scroll_to_bottom_smooth() -> void:
	if not is_instance_valid(questions_scroll):
		return
	var vbar := questions_scroll.get_v_scroll_bar()
	if not vbar:
		return
	var target := vbar.max_value
	var t := create_tween()
	t.tween_property(questions_scroll, "scroll_vertical", target, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _replay_from_state() -> void:
	print("==== Replay 20Q ====")
	print("I am P", i_am_player, " | turn=", is_my_turn, " | answer='", secret_answer, "'")
	for q in questions:
		print("#", q["idx"], "  ", q["text"], "  resp=", int(q["resp"]))
	print("====================")

func _on_send_pressed() -> void:
	if spectator_mode or game_over or (not is_my_turn) or (not is_instance_valid(text_box)):
		return

	var raw := text_box.text
	var cleaned := _sanitize_input(raw, true)

	if cleaned == "":
		_flash_textbox_red()
		_on_text_focus_exited()
		return

	var is_guess_correct: bool = (i_am_player == 1) and (cleaned.to_lower() == secret_answer.strip_edges().to_lower())

	var text_to_send := cleaned
	if not is_guess_correct and not text_to_send.ends_with("?"):
		text_to_send += "?"

	var next_idx: int = (int(questions[-1]["idx"]) + 1) if questions.size() > 0 else 1
	var resp_code: int = 4 if is_guess_correct else 0

	questions.append({ "text": text_to_send, "idx": next_idx, "resp": resp_code })
	_evaluate_game_over_and_winner()
	_render_all_questions()
	_update_upcoming_input_chip_color()
	_smooth_scroll_to_bottom()

	if i_am_player == 1 and not is_guess_correct:
		var asked_count := questions.size()
		if asked_count >= MAX_QUESTIONS:
			_evaluate_game_over_and_winner()
			_update_ui_interactivity()
			print("P1 reached 20 questions without correct guess. You lose.")

	_send_game(text_to_send, next_idx, resp_code)
	text_box.text = ""
	DisplayServer.virtual_keyboard_hide()
	_on_text_focus_exited()
	_start_waiting()
	_update_description_fill()

func _on_answer_yes() -> void:
	_apply_answer_code_to_pending(1)

func _on_answer_no() -> void:
	_apply_answer_code_to_pending(2)

func _on_answer_sometimes() -> void:
	_apply_answer_code_to_pending(3)

func _on_answer_correct() -> void:
	if questions.size() == 0:
		return
	var last: Dictionary = questions[-1]
	if int(last["resp"]) != 0:
		return
	var txt: String = str(last["text"]).to_lower()
	var target: String = secret_answer.strip_edges().to_lower()
	var code: int = 4 if txt.find(target) != -1 else 1
	_apply_answer_code_to_pending(code)

func _apply_answer_code_to_idx(target_idx: int, code: int) -> void:
	if game_over or i_am_player != 2 or questions.size() == 0:
		return

	var found := false
	for i in range(questions.size()):
		if int(questions[i].get("idx", -1)) == target_idx and int(questions[i].get("resp", 0)) == 0:
			questions[i]["resp"] = code
			found = true
			break
	if not found:
		dbg("apply_idx: NOT FOUND or already answered")
		return

	_render_all_questions()
	_evaluate_game_over_and_winner()

	if code == 4:
		dbg("apply_idx: guessed-it selected; game_over=%s winner=%d before send" % [str(game_over), winner])

	dbg("apply_idx: updated; calling _send_full_state & _maybe_show_answer_popup")
	_send_full_state()
	_update_ui_interactivity()

	if not game_over:
		_maybe_show_answer_popup()
		_start_waiting()
	else:
		_hide_answer_overlay()
		_stop_waiting()
	
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

func _send_game(text: String, q_idx: int, resp_code: int) -> void:
	var chunks: Array[String] = []
	for q in questions:
		var server_idx := int(q["idx"]) - 1
		var c := "%s^&*%d^&*%d" % [str(q["text"]), server_idx, int(q["resp"])]
		chunks.append(c)

	var questions_field := "|][".join(chunks)

	var payload: Dictionary = {
		"game": "questions",
		"id": game_id,
		"questions": questions_field
	}
	
	var avatar_key := ("avatar1" if i_am_player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	for q in questions:
		if int(q.get("resp", 0)) == 4:
			game_over = true
			winner = 1
			break

	if game_over:
		var win_loss_state := "0"

		if winner == 0:
			win_loss_state = "0"
		elif (i_am_player == 1 and winner == 1) or (i_am_player == 2 and winner == -1):
			win_loss_state = "1"
		else:
			win_loss_state = "-1"

		payload["winner"] = my_uuid + "|" + win_loss_state

	var json := JSON.stringify(payload)
	print("Sending: ", json)
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(json)
	else:
		print("No app plugin (local test).")

func _send_full_state() -> void:
	_send_game("", 0, 0)

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

	var should_wait := (not game_over) and (not is_my_turn)
	if should_wait and not _waiting_active:
		_start_waiting()
	elif (not should_wait) and _waiting_active:
		_stop_waiting()

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

	print("[20Q][row] build idx=", idx, " latest=", is_latest, " resp=", resp_code)

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
		print("[20Q][row] Will show opponent avatar. PackedScene ok? ", OpponentAvatarScene != null)
		var opp_inst := OpponentAvatarScene.instantiate()
		print("[20Q][row] Instantiated avatar. Type=", opp_inst.get_class())

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
			print("[20Q][row] Avatar added as child. left_stack size=", left_stack.get_rect().size)

			if _opponent_avatar_data.is_empty():
				print("[20Q][row] _opponent_avatar_data empty. Using defaults.")
				_opponent_avatar_data = _parse_avatar_string("")
			else:
				print("[20Q][row] Using provided avatar data: ", _opponent_avatar_data)

			if opp_inst.has_method("update_avatar_from_data"):
				print("[20Q][row] Calling update_avatar_from_data on avatar...")
				opp_inst.call_deferred("update_avatar_from_data", _opponent_avatar_data)
			else:
				print("[20Q][row][WARN] Avatar root lacks 'update_avatar_from_data'. Node=", opp_inst, " Script=", opp_inst.get_script())
		else:
			print("[20Q][row][WARN] Avatar instance is not Control. Got: ", opp_inst)
	else:
		print("[20Q][row] Showing history '?' instead of avatar (is_latest=", is_latest, ")")
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
	var avatar := left_stack.get_node_or_null("OpponentAvatar")
	print("[20Q][rowdbg] row size=", row.get_rect().size, " left_stack size=", (left_stack.get_rect().size if left_stack else Vector2.ZERO))
	if avatar:
		print("[20Q][rowdbg] avatar rect=", (avatar as Control).get_rect(), " anchors=FULL? (", (avatar as Control).anchor_left, ",", (avatar as Control).anchor_top, ",", (avatar as Control).anchor_right, ",", (avatar as Control).anchor_bottom, ")")
	
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
	
func _lift_input_row(up: bool) -> void:
	if not is_instance_valid(bottom_items):
		return

	if is_instance_valid(bottom_items.get_tree()):
		for t in get_tree().get_processed_tweens():
			if t.is_running() and t.get_target() == bottom_items:
				t.stop()

	if up and not _input_lifted:
		_input_lifted = true
		_input_orig_position = bottom_items.position

		bottom_items.set_anchors_preset(Control.PRESET_TOP_WIDE, false)
		bottom_items.offset_left = 0
		bottom_items.offset_right = 0
		bottom_items.offset_top = 0
		bottom_items.offset_bottom = 0
		bottom_items.position = Vector2(bottom_items.position.x, 0)

		var header_h := 0.0
		if is_instance_valid(_desc_rich):
			header_h = _desc_rich.get_rect().size.y
		var target_y := 8.0 + header_h

		var t := create_tween()
		t.tween_property(bottom_items, "position:y", target_y, 0.18)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	elif (not up) and _input_lifted:
		_input_lifted = false
		var t := create_tween()
		t.tween_property(bottom_items, "position:y", 0.0, 0.12)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await t.finished

		bottom_items.set_anchors_preset(Control.PRESET_BOTTOM_WIDE, false)
		bottom_items.offset_left = 0
		bottom_items.offset_right = 0
		bottom_items.offset_top = 0
		bottom_items.offset_bottom = 0
		bottom_items.position = Vector2.ZERO

func _show_win_burst(avatar: Control) -> void:
	if not is_instance_valid(avatar):
		print("[20Q][win-burst][ERR] avatar invalid")
		return
	var parent := avatar.get_parent()
	if not is_instance_valid(parent):
		print("[20Q][win-burst][ERR] avatar has no parent")
		return

	var burst_name := "AvatarWinAnim_" + str(avatar.get_instance_id())
	if parent.get_node_or_null(burst_name) != null:
		print("[20Q][win-burst] animation already present for this avatar")
		return

	if AvatarWinAnimScene == null:
		print("[20Q][win-burst][ERR] AvatarWinAnimScene preload is null!")
		return

	var anim_instance := AvatarWinAnimScene.instantiate() as Control
	if not is_instance_valid(anim_instance):
		print("[20Q][win-burst][ERR] could not instance AvatarWinAnimScene")
		return
	anim_instance.name = burst_name
	parent.add_child(anim_instance)
	parent.move_child(anim_instance, avatar.get_index())

	anim_instance.anchor_left   = avatar.anchor_left
	anim_instance.anchor_top    = avatar.anchor_top
	anim_instance.anchor_right  = avatar.anchor_right
	anim_instance.anchor_bottom = avatar.anchor_bottom
	anim_instance.offset_left   = avatar.offset_left - 52.0
	anim_instance.offset_right  = avatar.offset_right + 52.0
	anim_instance.offset_top    = avatar.offset_top - 43.0
	anim_instance.offset_bottom = avatar.offset_bottom + 43.0

	anim_instance.z_as_relative = avatar.z_as_relative
	avatar.z_as_relative        = avatar.z_as_relative
	anim_instance.z_index       = avatar.z_index - 1
	avatar.z_index              = max(avatar.z_index, 1)

	parent.visible = true
	avatar.visible = true

	if anim_instance.has_method("set_color"):
		anim_instance.call("set_color", Color(1.0, 0.84, 0.0))  # gold
	if anim_instance.has_method("play"):
		anim_instance.call("play", 0.05)

	print("[20Q][win-burst] burst added as sibling and playing behind avatar")

func _make_inline_btn(caption: String, bg: Color, fg: Color, q_idx: int, code: int) -> Button:
	var b := Button.new()
	var sb_b := StyleBoxFlat.new()
	sb_b.bg_color = bg
	sb_b.corner_radius_top_left = 8
	sb_b.corner_radius_top_right = 8
	sb_b.corner_radius_bottom_left = 8
	sb_b.corner_radius_bottom_right = 8
	sb_b.content_margin_left = 10
	sb_b.content_margin_right = 10
	sb_b.content_margin_top = 8
	sb_b.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", sb_b)
	b.add_theme_stylebox_override("hover", sb_b)
	b.add_theme_stylebox_override("pressed", sb_b)
	b.add_theme_stylebox_override("disabled", sb_b)
	b.add_theme_color_override("font_color", fg)
	b.text = caption
	b.pressed.connect(Callable(self, "_on_inline_answer_pressed").bind(q_idx, code))
	return b

func _make_response_pill(code: int) -> Control:
	var txt := _response_text(code)
	var col := _response_color(code)

	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(110, 40)

	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	holder.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 18)
	holder.add_child(lbl)

	return holder

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

func _style_button_bg(btn: Button, bg: Color, font_col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_color_override("font_color", font_col)

func _pending_unanswered_question() -> Dictionary:
	for q in questions:
		if int(q.get("resp", 0)) == 0:
			dbg("pending: next unanswered idx=%d text='%s'" % [int(q.get("idx", -1)), str(q.get("text", ""))])
			return q
	dbg("pending: none")
	return {}

func _maybe_show_answer_popup() -> void:
	_dbg("maybe_overlay: enter p=%d turn=%s game_over=%s unanswered=%d" % [
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
		_dbg("overlay: was supposed to be visible; forcing show/front")
		overlay.visible = true
		overlay.move_to_front()
		overlay.z_index = 1000
	
func _overlay_click(code: int) -> void:
	_dbg("overlay: click code=%d on idx=%d" % [code, _overlay_idx])
	if _overlay_idx == -1:
		_hide_answer_overlay()
		return

	var clicked_idx := _overlay_idx
	_apply_answer_code_to_idx(clicked_idx, code)
	_hide_answer_overlay()

	if code == 4:
		_stop_waiting()
		_update_ui_interactivity()
		return

	if not game_over and i_am_player == 2 and is_my_turn:
		_maybe_show_answer_popup()

func _on_overlay_btn_pressed(code: int) -> void:
	_apply_answer_code_to_pending(code)

func _make_overlay_btn(caption: String, bg: Color, fg: Color, code: int) -> Button:
	var b := Button.new()
	b.text = caption
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", s)
	b.add_theme_stylebox_override("pressed", s)
	b.add_theme_stylebox_override("disabled", s)
	b.add_theme_color_override("font_color", fg)
	b.pressed.connect(Callable(self, "_on_overlay_btn_pressed").bind(code))
	return b

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
		_dbg("overlay: node missing; cannot show")
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
	print("VISIBLE OVERLAY")
	overlay.move_to_front()
	var vp_w := get_viewport_rect().size.x
	var card := overlay.get_node_or_null("Card") as Control
	var target := card if card else overlay

	target.set_anchors_preset(Control.PRESET_CENTER)
	target.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	target.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	target.custom_minimum_size.x = vp_w * 0.8


	var r := overlay.get_global_rect()
	_dbg("overlay: SHOW idx=%d text='%s' unanswered=%d turn=%s p=%d rect=(%.1f,%.1f,%.1f,%.1f) visible=%s z=%d top_level=%s" % [
		idx, text, _count_unanswered(), str(is_my_turn), i_am_player,
		r.position.x, r.position.y, r.size.x, r.size.y,
		str(overlay.visible), overlay.z_index, str(overlay.top_level)
	])

func _hide_answer_overlay() -> void:
	if is_instance_valid(overlay):
		overlay.visible = false
	_dbg("overlay: HIDE")
	
func _dbg(msg: String) -> void:
	print("[20Q] ", msg)

func _update_description_fill() -> void:
	if not is_instance_valid(_desc_rich):
		return

	_desc_rich.bbcode_enabled = true

	if spectator_mode:
		var guide := "[font_size=18]You are watching this game.[/font_size]"
		_desc_rich.parse_bbcode(guide)
		_desc_rich.visible = true
	elif i_am_player == 2:
		var your_word := "[font_size=20]Your word:[/font_size]\n"
		var the_word  := "[font_size=34][b]%s[/b][/font_size]" % secret_answer
		_desc_rich.parse_bbcode(your_word + the_word)
		_desc_rich.visible = true
	else:
		var guide := "[font_size=18]Your goal is to guess the answer in 20 questions or less.[/font_size]"
		_desc_rich.parse_bbcode(guide)
		_desc_rich.visible = true

var DEBUG_20Q := true

func dbg(msg: String) -> void:
	if DEBUG_20Q:
		print("[20Q] ", msg)

func _on_dot_timer_timeout() -> void:
	if not is_instance_valid(wait_for_label):
		print("Warning: wait_for_label is not valid in _on_dot_timer_timeout.")
		return
	dot_count = (dot_count % 3) + 1
	var dots := ""
	for i in range(dot_count):
		dots += "."
	wait_for_label.text = BASE_WAIT_TEXT + dots

func _set_wait_base_text() -> void:
	BASE_WAIT_TEXT = "Waiting for an answer" if i_am_player == 1 else "Waiting for a question"

func _start_waiting() -> void:
	if spectator_mode or game_over:
		return
	print("START WAITING")
	_set_wait_base_text()
	if is_instance_valid(wait_for_label):
		wait_for_label.text = BASE_WAIT_TEXT
		wait_for_label.visible = true
	dot_count = 0
	if is_instance_valid(dot_timer):
		if not dot_timer.is_stopped():
			dot_timer.stop()
		dot_timer.start()

	_waiting_active = true
	print("WAITING ACTIVE: ", _waiting_active)
	if i_am_player == 1 and is_instance_valid(bottom_items):
		bottom_items.visible = false

func _stop_waiting() -> void:
	print("STOP WAITING")
	if not _waiting_active:
		print("no waiting active")
		return

	if is_instance_valid(wait_for_label):
		wait_for_label.visible = false
	if is_instance_valid(dot_timer):
		dot_timer.stop()

	_waiting_active = false
	if i_am_player == 1 and is_instance_valid(bottom_items):
		bottom_items.visible = true

func _renumber_from_one() -> void:
	if questions.is_empty():
		return
	var arr := questions.duplicate()
	arr.sort_custom(func(a, b): return int(a["idx"]) < int(b["idx"]))
	for i in arr.size():
		arr[i]["idx"] = i + 1
	questions = arr
