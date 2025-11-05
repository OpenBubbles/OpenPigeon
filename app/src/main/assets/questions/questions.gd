extends Control

@onready var send_button: Button = %SendButton
@onready var text_box: TextEdit = %TextBox
@onready var questions_scroll: ScrollContainer = %QuestionsScroll
@onready var questions_container: Control = %QuestionsContainer
@onready var questions_list: VBoxContainer = %QuestionsList
@onready var question_avatar_scene: Control		= %QuestionAvatarDisplay
@onready var question_mark_filler: RichTextLabel		= %QuestionMark
@onready var wait_for_label : Label = %WaitForLabel
@onready var dot_timer : Timer = %DotTimer
@onready var player_avatar_display	: Control		= %PlayerAvatarDisplay
@onready var _desc_rich: RichTextLabel = %Description
@onready var bottom_items: VBoxContainer = %BottomItems
@onready var overlay				: PanelContainer = %AnswerOverlay
@onready var overlay_num			: RichTextLabel = %QuestionNumber
@onready var overlay_text			: RichTextLabel = %QuestionText
@onready var overlay_yes			: Button = %YesButton
@onready var overlay_no				: Button = %NoButton
@onready var overlay_some			: Button = %SometimesButton
@onready var overlay_correct		: Button = %CorrectButton

var my_uuid: String = ""

const OpponentAvatarScene: PackedScene = preload("res://global/avatar_textures/AvatarThumbnail.tscn")
var _opponent_avatar_data: Dictionary = {}

# ---- Game state ----
var is_my_turn: bool = false
var server_player_hint: int = 0
var i_am_player: int = 1
var secret_answer: String = ""
var questions: Array[Dictionary] = []    # [{text:String, idx:int, resp:int}]
var game_id: String = ""
var last_raw_payload: Dictionary = {}
var game_over: bool = false
const MAX_QUESTIONS := 20
var _scroll_tween: Tween = null
var _overlay_idx: int = -1
var BASE_WAIT_TEXT := ""
var dot_count := 0
const USE_OVERLAY := false	# set true to use overlay instead of PopupPanel
var _waiting_active := false

func _ready() -> void:
	var appPlugin = Engine.get_singleton("AppPlugin")
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
		_set_game_data('{"isYourTurn":true,"player":"1","game":"questions","questions":"[Is the word pee?^&*1^&*3|][A?^&*2^&*1|][B?^&*3^&*0]","game_name":"20 Questions","id":"TEST123","answer":"Poop","num":"1"}')

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
	if is_instance_valid(overlay):
		overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	if is_instance_valid(text_box):
		# Hide the big list while typing so the IME isn't in the way
		if not text_box.focus_entered.is_connected(_on_text_focus_entered):
			text_box.focus_entered.connect(_on_text_focus_entered)
		if not text_box.focus_exited.is_connected(_on_text_focus_exited):
			text_box.focus_exited.connect(_on_text_focus_exited)
		# Live-sanitize as user types (also strips Enters)
		if not text_box.text_changed.is_connected(_on_text_changed_sanitize):
			text_box.text_changed.connect(_on_text_changed_sanitize)

		# NEW: make the existing overlay fill the whole scene and be on top
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
		overlay.z_index = 1000

		# connect buttons
		if is_instance_valid(overlay_yes): overlay_yes.pressed.connect(func(): _overlay_click(1))
		if is_instance_valid(overlay_no): overlay_no.pressed.connect(func(): _overlay_click(2))
		if is_instance_valid(overlay_some): overlay_some.pressed.connect(func(): _overlay_click(3))
		if is_instance_valid(overlay_correct): overlay_correct.pressed.connect(func(): _overlay_click(4))
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

# ---------------------------
# Safe getters for payloads
# ---------------------------
func _get_s(parsed_dict: Dictionary, key: String, def: String = "") -> String:
	if not parsed_dict.has(key):
		return def
	var v: Variant = parsed_dict[key]
	if typeof(v) == TYPE_ARRAY and v.size() > 0:
		return str(v[0])
	return str(v)
	
func _on_text_focus_entered() -> void:
	if is_instance_valid(questions_container):
		questions_container.visible = false

func _on_text_focus_exited() -> void:
	if is_instance_valid(questions_container):
		questions_container.visible = true
		
func _flash_textbox_red() -> void:
	if not is_instance_valid(text_box):
		return
	var t := create_tween()
	# Subtle red tint, then back
	text_box.modulate = Color(1, 0.6, 0.6, 1)
	t.tween_property(text_box, "modulate", Color(1, 1, 1, 1), 0.25).set_delay(0.15)

func _sanitize_input(raw: String) -> String:
	var s := raw
	# Remove newlines first
	s = s.replace("\r", " ").replace("\n", " ")

	# Collapse multiple whitespace to a single space
	var re := RegEx.new()
	re.compile("\\s+")
	s = re.sub(s, " ", true)
	s = s.strip_edges()

	# Neutralize tokens that could break your wire format or UI
	s = s.replace("^&*", "⋆")  # collapse multi-token to a harmless glyph
	s = s.replace("|", "¦")
	s = s.replace("[", "⟦")
	s = s.replace("]", "⟧")
	s = s.replace("<", "‹").replace(">", "›")
	s = s.replace("[/","⟦/")
	s = s.replace("\\", "⧵")

	# Optional length cap
	var MAX := 140
	if s.length() > MAX:
		s = s.substr(0, MAX).strip_edges()

	return s
	
func _on_text_changed_sanitize() -> void:
	if not is_instance_valid(text_box):
		return
	var caret := text_box.get_caret_column()  # best-effort caret preservation
	var cleaned := _sanitize_input(text_box.text)
	if cleaned != text_box.text:
		text_box.text = cleaned
		# keep caret roughly where it was
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

# -------------------------------------------------------
# Incoming data -> parse -> compute role/turn -> replay
# -------------------------------------------------------
func _set_game_data(data_json: String) -> void:
	var parsed_v: Variant = JSON.parse_string(data_json)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		printerr("Bad game data JSON")
		return
	var parsed: Dictionary = parsed_v
	last_raw_payload = parsed.duplicate(true)

	is_my_turn = _get_b(parsed, "isYourTurn", false)
	server_player_hint = int(_get_s(parsed, "player", "1"))
	secret_answer = _get_s(parsed, "answer", secret_answer)
	game_id = _get_s(parsed, "id", game_id)

	var player1: String = _get_s(parsed, "player1", "")
	var player2: String = _get_s(parsed, "player2", "")

	if player1 != "" or player2 != "":
		# If the payload identifies players by UUID, trust that first.
		if my_uuid == player1:
			i_am_player = 1
		elif my_uuid == player2:
			i_am_player = 2
		else:
			# Fallback if our UUID isn't in the payload: use sender-is-player, we’re the opposite.
			i_am_player = 2 if server_player_hint == 1 else 1
	else:
		# No UUIDs: the "player" field means the SENDER of this message.
		# We are the OPPOSITE of that number.
		i_am_player = 2 if server_player_hint == 1 else 1
		
	var opponent_avatar_key := "avatar2" if i_am_player == 1 else "avatar1"

	if parsed.has(opponent_avatar_key):
		var avatar_string := _get_s(parsed, opponent_avatar_key, "")
		_opponent_avatar_data = _parse_avatar_string(avatar_string)
	else:
		# Default/fallback avatar if the key is missing
		_opponent_avatar_data = _parse_avatar_string("")

	# Parse questions in new bracketed format
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

	# Optional legacy "response" text
	if parsed.has("response") and questions.size() > 0:
		var resp_txt: String = _get_s(parsed, "response", "")
		questions[-1]["response_text"] = resp_txt

	# Detect end-state
	game_over = false
	for q in questions:
		if int(q["resp"]) == 4:
			game_over = true
			break
			
	dbg("set_game_data: is_my_turn=%s, server_player_hint=%s, i_am_player(pre)=%s" % [str(is_my_turn), str(server_player_hint), str(i_am_player)])
	dbg("set_game_data: parsed questions count=%d" % questions.size())
	if questions.size() > 0:
		var u := 0
		for q in questions:
			if int(q.get("resp", 0)) == 0:
				u += 1
		dbg("set_game_data: unanswered=%d" % u)
	dbg("set_game_data: secret_answer='%s', game_over=%s" % [secret_answer, str(game_over)])

	if (not is_my_turn) and (not game_over) and (not _waiting_active):
		_start_waiting()
	elif is_my_turn and (not game_over):
		_stop_waiting()
		
	_replay_from_state()
	_render_all_questions()
	_update_ui_interactivity()
	_update_description_fill()
	_maybe_show_answer_popup()
	
# Add near the top (helpers) ---------------------------------------------

func _question_color_for_index(idx: int) -> Color:
	# 1..20 maps around the wheel; 1 and 20 are both 0 deg
	if idx <= 1:
		return Color.from_hsv(0.0, 0.70, 0.95, 1.0)
	var step: float = 1.0 / 19.0
	var h: float = fposmod((idx - 1) * step, 1.0)
	return Color.from_hsv(h, 0.70, 0.95, 1.0)

func _make_scrollbars_invisible() -> void:
	if not is_instance_valid(questions_scroll):
		return
	# Transparent styleboxes for bars
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
	# smooth tween to bottom
	var target := vbar.max_value
	var t := create_tween()
	t.tween_property(questions_scroll, "scroll_vertical", target, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# -------------------------------------------------------
# Rebuild visible/logged state (replace prints with UI)
# -------------------------------------------------------
func _replay_from_state() -> void:
	print("==== Replay 20Q ====")
	print("I am P", i_am_player, " | turn=", is_my_turn, " | answer='", secret_answer, "'")
	for q in questions:
		print("#", q["idx"], "  ", q["text"], "  resp=", int(q["resp"]))
	print("====================")

# -------------------------------------------------------
# Send (Player 1 asks / Player 2 can also send short replies)
# -------------------------------------------------------
func _on_send_pressed() -> void:
	if game_over or (not is_my_turn) or (not is_instance_valid(text_box)):
		return

	var raw := text_box.text
	var cleaned := _sanitize_input(raw)

	if cleaned == "":
		_flash_textbox_red()
		# also ensure the questions list comes back if we were hidden
		_on_text_focus_exited()
		return

	var is_guess_correct: bool = (i_am_player == 1) and (cleaned.to_lower() == secret_answer.strip_edges().to_lower())

	var text_to_send := cleaned
	if not is_guess_correct and not text_to_send.ends_with("?"):
		text_to_send += "?"

	var next_idx: int = (int(questions[-1]["idx"]) + 1) if questions.size() > 0 else 1
	var resp_code: int = 4 if is_guess_correct else 0

	questions.append({ "text": text_to_send, "idx": next_idx, "resp": resp_code })
	_render_all_questions()
	_smooth_scroll_to_bottom()

	if i_am_player == 1 and not is_guess_correct:
		var asked_count := questions.size()
		if asked_count >= MAX_QUESTIONS:
			game_over = true
			_update_ui_interactivity()
			print("P1 reached 20 questions without correct guess. You lose.")

	_send_game(text_to_send, next_idx, resp_code)
	text_box.text = ""
	_on_text_focus_exited()  # restore list if hidden
	_start_waiting()
	_update_description_fill()



# -------------------------------------------------------
# Player 2 answer buttons (hook these to your UI)
# -------------------------------------------------------
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

# --- AUTO-ADVANCE: after answering, immediately show the next unanswered ---
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


	if code == 4:
		game_over = true

	_render_all_questions()
	dbg("apply_idx: updated; calling _send_full_state & _maybe_show_answer_popup")
	_send_full_state()
	_update_ui_interactivity()

	# move on to the next unanswered, or hide if none
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

# -------------------------------------------------------
# Build outbound payloads
# -------------------------------------------------------
func _send_game(text: String, q_idx: int, resp_code: int) -> void:
	var chunks: Array[String] = []
	for q in questions:
		var c := "[%s^&*%d^&*%d|]" % [q["text"], int(q["idx"]), int(q["resp"])]
		chunks.append(c)

	var questions_field: String = ""
	for c in chunks:
		questions_field += c

	var payload: Dictionary = {
		"game": "questions",
		"id": game_id,
		"questions": questions_field
	}

	var json := JSON.stringify(payload)
	print("Sending: ", json)
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(json)
	else:
		print("No app plugin (local test).")


func _send_full_state() -> void:
	_send_game("", 0, 0)

# -------------------------------------------------------
# UI gating
# -------------------------------------------------------
func _update_ui_interactivity() -> void:
	var enable_input := (is_my_turn and not game_over and i_am_player == 1)

	if is_instance_valid(send_button):
		send_button.disabled = not enable_input
	if is_instance_valid(text_box):
		text_box.editable = enable_input

	# Player 1 sees the textbox/Send row unless we're in waiting mode
	if is_instance_valid(bottom_items):
		bottom_items.visible = (i_am_player == 1) and (not _waiting_active)

	dbg("ui: enable_input=%s, i_am_player=%d, is_my_turn=%s, game_over=%s" % [str(is_my_turn and not game_over and i_am_player == 1), i_am_player, str(is_my_turn), str(game_over)])
	if is_instance_valid(bottom_items):
		dbg("ui: bottom_items.visible=%s" % str(bottom_items.visible))

	# Drive waiting state *without* recursion
	var should_wait := (not game_over) and (not is_my_turn)
	if should_wait and not _waiting_active:
		_start_waiting()
	elif (not should_wait) and _waiting_active:
		_stop_waiting()

func _render_all_questions() -> void:
	if not is_instance_valid(questions_list):
		return
	dbg("render: rebuilding list; questions=%d" % questions.size())
	# wipe old rows
	for c in questions_list.get_children():
		c.queue_free()

	# sort by idx
	var sorted: Array[Dictionary] = []
	for q in questions:
		sorted.append(q)
	var cmp := func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["idx"]) < int(b["idx"])
	sorted.sort_custom(cmp)

	# find most-recent idx
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
	
	dbg("render: finished; latest_idx=%d" % latest_idx)
	
func _smooth_scroll_to_bottom() -> void:
	if not is_instance_valid(questions_scroll):
		return
	var bar := questions_scroll.get_v_scroll_bar()
	if bar == null:
		return
	# ensure layout is finalized
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

# --- QUESTION ROW: show only the single resolved response (chip), no inline answer buttons ---
func _make_question_row(q: Dictionary, is_latest: bool) -> HBoxContainer:
	var idx := int(q["idx"])
	var col := _question_color_for_index(idx)
	var resp_code := int(q.get("resp", 0))

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 72)
	row.add_theme_constant_override("separation", 12)

	# Left glyph (avatar + "?" on latest; just "?" for older)
	var left_holder := Control.new()
	left_holder.custom_minimum_size = Vector2(48, 56)
	left_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Use a container so we can stack avatar + overlay "?"
	var left_stack := Control.new()
	left_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left_holder.add_child(left_stack)
	row.add_child(left_holder)

	if is_latest and OpponentAvatarScene != null:
		var opp_inst := OpponentAvatarScene.instantiate()
		if opp_inst is Control:
			opp_inst.name = "OpponentAvatar"
			opp_inst.custom_minimum_size = Vector2(72, 56)
			opp_inst.set_anchors_preset(Control.PRESET_CENTER)
			opp_inst.mouse_filter = Control.MOUSE_FILTER_IGNORE
			opp_inst.scale = Vector2(0.6, 0.6)
			left_stack.add_child(opp_inst)

			if _opponent_avatar_data.is_empty():
				_opponent_avatar_data = _parse_avatar_string("")
			opp_inst.call_deferred("update_avatar_from_data", _opponent_avatar_data)
	else:
		var qmark := Label.new()
		qmark.name = "HistoryQuestionMark"
		qmark.text = "?"
		qmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qmark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		qmark.add_theme_font_size_override("font_size", 48)
		qmark.add_theme_color_override("font_color", col)
		qmark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qmark.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left_stack.add_child(qmark)

	# Colored card
	var card := PanelContainer.new()
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
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	card.add_child(inner)

	var num_lbl := Label.new()
	num_lbl.text = str(idx) + "."
	num_lbl.add_theme_color_override("font_color", Color.BLACK)
	num_lbl.add_theme_font_size_override("font_size", 22)
	num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num_lbl.custom_minimum_size = Vector2(36, 0)
	inner.add_child(num_lbl)

	var q_lbl := Label.new()
	q_lbl.text = str(q["text"])
	q_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_lbl.add_theme_color_override("font_color", Color.BLACK)
	q_lbl.add_theme_font_size_override("font_size", 20)
	inner.add_child(q_lbl)

	# If answered (1..4), show one inline chip to the right
	if resp_code > 0:
		var chip := _make_response_chip(resp_code)
		inner.add_child(chip)

	row.add_child(card)
	return row
	
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

			# --- Skin color (accept both) ---
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
	# keep label readable on black chip
	if code == 2:
		lbl.add_theme_color_override("font_color", Color(1,1,1,1))
	holder.add_child(lbl)

	return holder
			
func _on_inline_answer_pressed(q_idx: int, code: int) -> void:
	_apply_answer_code_to_idx(q_idx, code)

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
	# Q1 → hue 0.0, Q20 → hue 1.0 (wrapped back to 0.0)
	# Equally spaced between (idx-1)/19 around the wheel.
	var h := float(max(idx, 1) - 1) / 19.0
	if h >= 1.0:
		h = 0.0
	# Tune S/V to taste; these give bright, readable cards behind black text.
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

	# Only P2 answers, on our turn, and while game is live
	if i_am_player != 2 or not is_my_turn or game_over:
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
	_apply_answer_code_to_idx(_overlay_idx, code)
	_hide_answer_overlay()  # hide after sending

	# If still eligible to answer, auto-advance to next
	if not game_over and i_am_player == 2 and is_my_turn:
		_maybe_show_answer_popup()

func _on_overlay_btn_pressed(code: int) -> void:
	# funnels overlay button clicks
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

	# Avoid standalone lambda; use Callable.bind instead
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
	# If your “card” is a child, e.g. %AnswerOverlay/Card
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

	# Make sure it's stretched every time (defensive)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 1000
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	_set_overlay_style_color(col)

	if is_instance_valid(overlay_num):
		overlay_num.text = str(idx) + "."
	if is_instance_valid(overlay_text):
		overlay_text.text = text

	_overlay_idx = idx
	overlay.visible = true
	print("VISIBLE OVERLAY")
	overlay.move_to_front()
		# Center the card and make it 80% of viewport width
	var vp_w := get_viewport_rect().size.x
	var card := overlay.get_node_or_null("Card") as Control
	var target := card if card else overlay

	target.set_anchors_preset(Control.PRESET_CENTER)
	target.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	target.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	target.custom_minimum_size.x = vp_w * 0.8
	# height wraps to content; if you want a max, uncomment:
	# target.custom_minimum_size.y = min(target.custom_minimum_size.y, get_viewport_rect().size.y * 0.9)


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

	if i_am_player == 2 and secret_answer.strip_edges() != "":
		var your_word := "[font_size=20]Your word:[/font_size]\n"
		var the_word  := "[font_size=34][b]%s[/b][/font_size]" % secret_answer
		_desc_rich.parse_bbcode(your_word + the_word)
		_desc_rich.visible = true
	else:
		# Player 1 guidance — always show
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
	# P1 waits for an answer, P2 waits for a question
	BASE_WAIT_TEXT = "Waiting for an answer" if i_am_player == 1 else "Waiting for a question"

func _start_waiting() -> void:
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

	# Hide BottomItems if we're Player 1 (question input)
	if i_am_player == 1 and is_instance_valid(bottom_items):
		bottom_items.visible = false

func _stop_waiting() -> void:
	print("STOP WAITING")
	# Guard: avoid work (and potential loops) if already inactive
	if not _waiting_active:
		print("no waiting active")
		return

	if is_instance_valid(wait_for_label):
		wait_for_label.visible = false
	if is_instance_valid(dot_timer):
		dot_timer.stop()

	_waiting_active = false

	# If we're Player 1, restore the input row directly
	if i_am_player == 1 and is_instance_valid(bottom_items):
		bottom_items.visible = true
