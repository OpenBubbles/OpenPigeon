extends Control
class_name ConnectGameBoard

@onready var player_avatar_display	: Control		= %PlayerAvatarDisplay
@onready var opp_avatar_display		: Control		= %OppAvatarDisplay
@onready var rules_button			: Button		= %RulesButton
@onready var settings_button		: Button		= %SettingsButton
@onready var send_button			: Button		= %SendButton
@onready var sent_label				: Label			= %SentLabel
@onready var waiting_label			: Label			= %WaitForOpponentLabel
@onready var waiting_blur			: Control		= %WaitBlur
@onready var dot_timer				: Timer			= %DotTimer
@onready var background				: ColorRect		= %Background
@onready var win_loss_label			: Label			= %WinLossLabel
@onready var player_piece			: TextureRect	= %PlayerPiece
@onready var opp_piece				: TextureRect	= %OppPiece
@onready var you_label				: Label			= %YouLabel
@onready var spec_label				: Label			= %SpecLabel

const BOARD_W			:= 7
const BOARD_H			:= 6
const BASE_WAIT_TEXT	:= "WAITING FOR OPPONENT"
const PIECE_YELLOW		:= "yellow"
const PIECE_RED			:= "red"
const DIRS				:= [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(1,-1)]
const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const RULES_POPUP_SCENE	 := preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE := preload("res://global/settings_popup.tscn")
const PIECE_TEX := {
	"red":		preload("res://connect/red_piece.png"),
	"yellow":	preload("res://connect/yellow_piece.png")
}

var yPoses: Array[float]	= [192.544, 109.498, 26.612, -56.274, -139.121, -221.902]
var sent_tween				: Tween
var dot_count				: int	= 0
var my_player				: String = ""
var turn_owner				: int	= 1
var firstReplay				: bool	= true
var isTurn					: bool	= false
var game_settings_category	: String = ""
var spectator_mode			: bool	= false
var has_connected			: bool	= false
var _last_applied_replay: String = ""
var waitingForOpponent		: bool	= true
var win_loss_state			: String = ""
var replay					: String = ""
var player					: int	= 0		# 0=spectator/unknown, 1=P1, 2=P2
var game_over				: bool	= false
var can_interact			: bool	= true
var suppress_next_click		: bool	= false
var last_highlight			: Node2D = null
var droppedPiece			: RigidBody2D = null

func _ready() -> void:
	var is_dark = bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)
	var app: Object = Engine.get_singleton("AppPlugin")

	if app:
		if not has_connected:
			app.connect("set_game_data", _set_game_data)
			has_connected = true
			app.call("onReady")
			await get_tree().process_frame
			_set_waiting(true)
			return
	else:
		if player == 0 or replay.is_empty():
			_set_game_data('{"isYourTurn":true,"player":"2","replay":"board:1,1,1,0,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"}')
			return

	if player == 0 or replay.is_empty():
		return

	_label_you_box()
	_hydrate_board_from_replay(replay)

	if not game_over:
		await get_tree().process_frame
		_set_waiting(not isTurn)

	if is_instance_valid(rules_button):
		rules_button.pressed.connect(on_rules_button_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.timeout.connect(_on_dot_timer_timeout)
	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)
		send_button.pressed.connect(send_game)
		
func _apply_turn_lock() -> void:
	can_interact = isTurn and (not game_over) and (not spectator_mode)
	_set_waiting(not can_interact)
	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)

func _clear_board_pieces() -> void:
	_clear_last_highlight()
	droppedPiece = null

	for c in get_children():
		if c is RigidBody2D:
			var n: String = String(c.name)
			if n.find(",") != -1:
				c.queue_free()

func _set_game_data(new_replay: String) -> void:
	var data: Dictionary = JSON.parse_string(new_replay)
	isTurn		= bool(data.get("isYourTurn", false))
	replay		= String(data.get("replay", ""))
	my_player	= String(data.get("myPlayerId", ""))

	var p1_id: String	= String(data.get("player1", ""))
	var p2_id: String	= String(data.get("player2", ""))
	turn_owner			= clamp(int(data.get("player", 1)), 1, 2)
	player				= _resolve_my_side(my_player, p1_id, p2_id, turn_owner, isTurn)
	spectator_mode		= (player == 0)

	if is_instance_valid(spec_label):
		spec_label.visible = spectator_mode
	if is_instance_valid(you_label):
		you_label.modulate.a = 1.0 if not spectator_mode else 0.0
		
	_apply_turn_lock()

	var opp_key: String = ""
	if player == 1:
		opp_key = "avatar2"
	elif player == 2:
		opp_key = "avatar1"

	if opp_key != "" and data.has(opp_key):
		var opp_data: Dictionary = _parse_avatar_string(String(data[opp_key]))
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opp_data)

	_apply_player_piece_icons()
	_label_you_box()
	_hydrate_board_from_replay(replay)

	game_over = _check_and_finalize_from_board()
	_apply_turn_state()

func _resolve_my_side(my_id: String, p1_id: String, p2_id: String, owner: int, my_turn: bool) -> int:
	if my_id != "" and p1_id != "" and p2_id != "":
		if my_id == p1_id:
			return 1
		elif my_id == p2_id:
			return 2
		else:
			return 0  # spectator/unknown

	if p1_id == "" or p2_id == "":
		if (owner == 2 and my_turn) or (owner == 1):
			return 1
		return 2
	return 0

func _label_you_box() -> void:
	if spectator_mode:
		return
	var box: Node = get_node_or_null("../Player%dBox" % player)
	if box:
		(box.get_child(0) as Label).set_text("[center]You[/center]")

func _hydrate_board_from_replay(rep: String) -> void:
	if rep.is_empty():
		return

	if rep == _last_applied_replay:
		return
	_last_applied_replay = rep

	_clear_board_pieces()

	var parts: PackedStringArray = rep.split("|")
	if parts.is_empty():
		return

	var head: String = String(parts[0])
	if not head.begins_with("board:"):
		return

	var board: PackedStringArray = head.substr(6).split(",")
	if board.size() < BOARD_W * BOARD_H:
		return

	for y in range(0, BOARD_H):
		for x in range(0, BOARD_W):
			var v: String = board[y * BOARD_W + x]
			if v == "1":
				spawnPiece(x, PIECE_YELLOW, y, true)
			elif v == "2":
				spawnPiece(x, PIECE_RED, y, true)

	for p in parts:
		if p.begins_with("move:"):
			var mv: PackedStringArray = p.substr(5).split(",") # x,y,playerId
			if mv.size() >= 3:
				var mx: int = int(mv[0])
				var my: int = int(mv[1])
				var color: String = _player_id_to_color(int(mv[2]))
				spawnPiece(mx, color, my, true)

func _build_replay_payload() -> Dictionary:
	if droppedPiece == null:
		return {}
	var board_str := ""
	for y in range(0, BOARD_H):
		for x in range(0, BOARD_W):
			if (str(x) + "," + str(y)) == droppedPiece.name:
				board_str += "0,"
			else:
				board_str += getPositionInt(x, y) + ","
	board_str = board_str.left(board_str.length() - 1)

	var move_x: int = int(droppedPiece.name.get_slice(",", 0))
	var move_y: int = int(droppedPiece.name.get_slice(",", 1))
	var move_color: String = str(player)

	var payload: Dictionary = {
		"replay": "board:%s|move:%d,%d,%s" % [board_str, move_x, move_y, move_color]
	}
	if game_over and win_loss_state != "":
		var winner_id: String = my_player if my_player != "" else str(player)
		payload["winner"] = "%s|%s" % [winner_id, win_loss_state]
	return payload

func send_game() -> void:
	if droppedPiece == null:
		return
	await get_tree().process_frame
	var payload: Dictionary = _build_replay_payload()
	if payload.is_empty():
		return

	var avatar_key: String = "avatar1" if player == 1 else "avatar2"
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.call("get_avatar_data_string")

	var app: Object = Engine.get_singleton("AppPlugin")
	if app:
		app.call("updateGameData", JSON.stringify(payload))

	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)

	if not game_over:
		play_sent_animation()
		can_interact = false
		

func _apply_turn_state() -> void:
	if game_over:
		_stop_waiting_animation()
		return
	_set_waiting(player == 0 or not isTurn)

func _set_waiting(enabled: bool) -> void:
	waitingForOpponent = enabled
	droppedPiece = null
	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)
	if enabled:
		_start_waiting_animation()
	else:
		_stop_waiting_animation()

func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color("352925ff") if is_dark else Color("#d8c7c2")

func _update_send_button_visibility(show: bool) -> void:
	if not is_instance_valid(send_button):
		return
	send_button.set_as_top_level(true)

	if not send_button.has_meta("home_pos"):
		send_button.set_meta("home_pos", send_button.global_position)

	if send_button.has_meta("sb_tween"):
		var old: Tween = send_button.get_meta("sb_tween") as Tween
		if old and old.is_running():
			old.kill()

	var home: Vector2 = send_button.get_meta("home_pos")
	var vp: Rect2 = get_viewport_rect()
	var off_y: float = vp.size.y + send_button.size.y + 30.0
	var start_pos: Vector2 = Vector2(home.x, off_y)

	if show:
		if not send_button.visible:
			send_button.global_position = start_pos
			send_button.visible = true
			send_button.modulate.a = 1.0
		elif send_button.global_position.y > vp.size.y:
			send_button.global_position = start_pos

		var t_in: Tween = create_tween()
		send_button.set_meta("sb_tween", t_in)
		t_in.tween_property(send_button, "global_position", home, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		if send_button.visible:
			var t_out: Tween = create_tween()
			send_button.set_meta("sb_tween", t_out)
			t_out.tween_property(send_button, "global_position", Vector2(home.x, off_y), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t_out.tween_callback(func():
				if is_instance_valid(send_button):
					send_button.visible = false
			)

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		return
	if sent_tween and sent_tween.is_running():
		sent_tween.kill()
	sent_tween = create_tween()
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
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0
			_set_waiting(true)
	)

func _player_id_to_color(pid: int) -> String:
	return PIECE_YELLOW if pid == 1 else PIECE_RED

func getPlayerColor(other: bool=false) -> String:
	var mine: String = PIECE_YELLOW if player == 1 else PIECE_RED
	return (PIECE_RED if player == 1 else PIECE_YELLOW) if other else mine

func _apply_player_piece_icons() -> void:
	if not is_instance_valid(player_piece) or not is_instance_valid(opp_piece):
		return
	player_piece.texture = PIECE_TEX[getPlayerColor(false)]
	opp_piece.texture	= PIECE_TEX[getPlayerColor(true)]
	if is_instance_valid(you_label):
		you_label.text = "You"
		you_label.modulate.a = 1.0 if not spectator_mode else 0.0

func getPieceColor(piece: RigidBody2D) -> String:
	var p: String = piece.get_child(0).texture.resource_path
	return PIECE_RED if p.contains("red") else PIECE_YELLOW

func _cell_color(x: int, y: int) -> String:
	var n: Node2D = get_node_or_null("%d,%d" % [x, y])
	if n == null:
		return ""
	return getPieceColor(n as RigidBody2D)

func getPositionInt(x: int, y: int) -> String:
	var n: Node2D = get_node_or_null("%d,%d" % [x, y])
	if n == null:
		return "0"
	var path: String = (n.get_child(0) as Sprite2D).texture.resource_path
	return "2" if path.contains("red") else "1"

func get_piece_y(x: int) -> int:
	for y in range(0, BOARD_H):
		if get_node_or_null("%d,%d" % [x, y]) == null:
			return y
	return -1

func spawnPiece(x: int, color: String, y: int=-1, from_replay: bool=false) -> void:
	var proto: RigidBody2D = get_node("ConnectPiece" + str(x))
	if game_over and not from_replay:
		return
	if (not can_interact) and not from_replay:
		return

	var piece: RigidBody2D = proto.duplicate()
	if y >= 0:
		piece.position.y = yPoses[y]
	else:
		y = get_piece_y(x)
		if y < 0:
			return

	add_child(piece)
	var spr: Sprite2D = piece.get_child(0) as Sprite2D
	spr.texture = PIECE_TEX[color]
	(piece.get_child(1) as CollisionShape2D).disabled = false
	piece.visible = true
	piece.set_freeze_enabled(false
	)
	piece.name = "%d,%d" % [x, y]

	if from_replay:
		_highlight_last(piece)
		_check_and_finalize_from_board()
		return

	droppedPiece = piece
	if _check_and_finalize_from_board():
		await get_tree().process_frame
		await send_game()
	else:
		if is_instance_valid(send_button):
			send_button.disabled = false
			_update_send_button_visibility(true)

func move_dropped_piece_to_column(new_x: int) -> void:
	if game_over or not can_interact or droppedPiece == null:
		return
	var new_y: int = get_piece_y(new_x)
	if new_y < 0:
		return
	var color: String = getPieceColor(droppedPiece)
	droppedPiece.queue_free()
	droppedPiece = null
	await get_tree().process_frame
	spawnPiece(new_x, color, -1, false)
	if is_instance_valid(send_button):
		send_button.disabled = false
		_update_send_button_visibility(true)

func undo_move() -> void:
	if droppedPiece:
		droppedPiece.queue_free()
		droppedPiece = null
		var sb: Button = get_node_or_null("../SendButton") as Button
		var ub: Button = get_node_or_null("../UndoButton") as Button
		if sb:
			sb.disabled = true
		if ub:
			ub.disabled = true

func _find_winning_sequence() -> Dictionary:
	for y in range(0, BOARD_H):
		for x in range(0, BOARD_W):
			var base: String = _cell_color(x, y)
			if base == "":
				continue
			for d in DIRS:
				var px: int = x - d.x
				var py: int = y - d.y
				var prev_ok: bool = (px >= 0 and px < BOARD_W and py >= 0 and py < BOARD_H)
				if prev_ok and _cell_color(px, py) == base:
					continue

				var run: Array[Vector2i] = []
				var cx: int = x
				var cy: int = y
				while cx >= 0 and cx < BOARD_W and cy >= 0 and cy < BOARD_H and _cell_color(cx, cy) == base:
					run.append(Vector2i(cx, cy))
					cx += d.x
					cy += d.y
				if run.size() >= 4:
					return {"coords": run, "color": base}
	return {}

func _check_and_finalize_from_board() -> bool:
	var win: Dictionary = _find_winning_sequence()
	if win.is_empty():
		return false
	_clear_last_highlight()
	_highlight_winning_pulse(win["coords"])
	var winner_pid: int = 1 if String(win["color"]) == PIECE_YELLOW else 2
	var i_won_now: bool = (winner_pid == player) and (not spectator_mode)
	_finalize_win(i_won_now)
	return true

func _clear_last_highlight() -> void:
	if last_highlight and is_instance_valid(last_highlight):
		var spr: Sprite2D = last_highlight.get_child(0) as Sprite2D
		if spr:
			spr.self_modulate.a = 1.0
		var t: Tween = last_highlight.get_meta("hl_tween") as Tween
		if t and t.is_running():
			t.kill()
		last_highlight.set_meta("hl_tween", null)
	last_highlight = null

func _pulse_sprite(spr: Sprite2D) -> Tween:
	spr.self_modulate.a = 1.0
	var tw: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_loops(0)
	tw.tween_property(spr, "self_modulate:a", 0.6, 0.45)
	tw.tween_property(spr, "self_modulate:a", 1.0, 0.45)
	return tw

func _pulse_nodes(nodes: Array[Node2D]) -> void:
	for n in nodes:
		if n:
			var spr: Sprite2D = n.get_child(0) as Sprite2D
			if spr:
				_pulse_sprite(spr)

func _winning_nodes_from_coords(cs: Array[Vector2i]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for c in cs:
		var n: Node2D = get_node_or_null("%d,%d" % [c.x, c.y])
		if n:
			out.append(n)
	return out

func _highlight_last(p: Node2D) -> void:
	_clear_last_highlight()
	if p and is_instance_valid(p):
		last_highlight = p
		var spr: Sprite2D = p.get_child(0) as Sprite2D
		if not spr:
			return
		var tw: Tween = _pulse_sprite(spr)
		p.set_meta("hl_tween", tw)
		p.tree_exited.connect(func():
			var t2: Tween = p.get_meta("hl_tween") as Tween
			if t2 and t2.is_running():
				t2.kill()
			p.set_meta("hl_tween", null)
		)

func _highlight_winning_pulse(cs: Array[Vector2i]) -> void:
	_pulse_nodes(_winning_nodes_from_coords(cs))

func _finalize_win(i_won: bool) -> void:
	if game_over:
		return
	game_over = true
	win_loss_state = "1" if i_won else "-1"

	_stop_waiting_animation()
	waitingForOpponent = false

	if spectator_mode:
		var p1_w: bool = (i_won and player == 1) or ((not i_won) and player == 2)
		if p1_w:
			win_loss_label.text = "Player 1 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			_show_win_burst(player_avatar_display)
		else:
			win_loss_label.text = "Player 2 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			_show_win_burst(opp_avatar_display)
	else:
		if i_won:
			_show_win_burst(player_avatar_display)
			win_loss_label.text = "YOU WIN!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		else:
			_show_win_burst(opp_avatar_display)
			win_loss_label.text = "YOU LOSE"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

	win_loss_label.visible = true
	await get_tree().process_frame
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2
	var t_in: Tween = create_tween()
	t_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	can_interact = false

func _ensure_avatar_wrapper(avatar: Control) -> Control:
	var parent: Node = avatar.get_parent()
	if parent == null:
		return null
	if parent is Control and not (parent is Container):
		return parent as Control

	var wrap: Control = Control.new()
	wrap.name = "%s_Wrap" % avatar.name
	wrap.size_flags_horizontal = avatar.size_flags_horizontal
	wrap.size_flags_vertical = avatar.size_flags_vertical
	wrap.custom_minimum_size = avatar.get_combined_minimum_size()
	var idx: int = avatar.get_index()
	parent.add_child(wrap)
	parent.move_child(wrap, idx)
	avatar.reparent(wrap)
	avatar.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar.offset_left = 0.0
	avatar.offset_top = 0.0
	avatar.offset_right = 0.0
	avatar.offset_bottom = 0.0
	avatar.item_rect_changed.connect(func():
		if is_instance_valid(wrap):
			wrap.custom_minimum_size = avatar.get_combined_minimum_size()
	)
	return wrap

func _show_win_burst(avatar: Control) -> void:
	var w: Control = _ensure_avatar_wrapper(avatar)
	if not is_instance_valid(w):
		return
	if w.get_node_or_null("AvatarWinAnim") != null:
		return

	var anim: Control = AvatarWinAnimScene.instantiate() as Control
	anim.name = "AvatarWinAnim"
	w.add_child(anim)
	w.move_child(anim, avatar.get_index())

	anim.z_as_relative = false
	avatar.z_as_relative = false
	anim.z_index = 0
	avatar.z_index = max(avatar.z_index, 1)

	anim.set_anchors_preset(Control.PRESET_FULL_RECT)
	anim.offset_left = -52.0
	anim.offset_right = 52.0
	anim.offset_top = -43.0
	anim.offset_bottom = 43.0

	anim.call("set_color", Color(1.0, 0.84, 0.0))
	anim.call("play", 0.05)

func _start_waiting_animation() -> void:
	if spectator_mode or not (is_instance_valid(waiting_label) and is_instance_valid(waiting_blur) and is_instance_valid(dot_timer)):
		return
	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true
	waiting_blur.visible = true
	waiting_label.modulate.a = 0.0
	waiting_blur.modulate.a = 0.0
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(waiting_label, "modulate:a", 1.0, 0.3)
	t.tween_property(waiting_blur, "modulate:a", 1.0, 0.3)
	t.tween_callback(func():
		dot_timer.start()
	)

func _stop_waiting_animation() -> void:
	if is_instance_valid(dot_timer):
		dot_timer.stop()
	if is_instance_valid(waiting_label):
		waiting_label.visible = false
		waiting_label.modulate.a = 1.0
	if is_instance_valid(waiting_blur):
		waiting_blur.visible = false
		waiting_blur.modulate.a = 1.0

func _on_dot_timer_timeout() -> void:
	if not is_instance_valid(waiting_label):
		return
	dot_count = (dot_count % 3) + 1
	var dots: String = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots

func on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return
	await _tap_bounce(rules_button)

	var popup: Control = RULES_POPUP_SCENE.instantiate()
	var dim: ColorRect = _make_dim(popup)

	var title: Label = popup.find_child("Title", true, false) as Label
	if title:
		title.text = "How to Play Four In A Row"

	var rules: RichTextLabel = popup.find_child("RulesLabel", true, false) as RichTextLabel
	if rules:
		rules.bbcode_enabled = true
		rules.visible = true
		rules.fit_content = true
		rules.scroll_active = false
		rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rules.text = _get_rules_text()

	_show_center_scale_in(popup)

func _on_settings_button_pressed() -> void:
	if not is_instance_valid(settings_button):
		return
	await _tap_bounce(settings_button)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0,0,0,0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var popup: Control = SETTINGS_POPUP_SCENE.instantiate()
	var script := popup as SettingsPopup

	var root: Window = get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)

	script.setup_popup(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			suppress_next_click = true
			get_viewport().set_input_as_handled()
	)

	var title_node: Node = popup.find_child("CustomSettingsTitleLabel", true)
	if title_node and title_node is Label:
		(title_node as Label).visible = (script.custom_settings_container.get_child_count() > 0)

	script.closed.connect(func():
		suppress_next_click = true
		if is_instance_valid(player_avatar_display):
			player_avatar_display.call("update_display_from_settings")
		_lock_interaction_briefly()
	)

	script.settings_theme_selected.connect(_on_theme_changed)
	script.dark_mode_changed.connect(_apply_bg_for_dark)

	_slide_up_in(popup)

func _tap_bounce(btn: Button) -> void:
	btn.pivot_offset = btn.size / 2.0
	var t: Tween = create_tween()
	t.tween_property(btn, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(btn, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished

func _make_dim(popup: Control) -> ColorRect:
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0,0,0,0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			suppress_next_click = true
			dim.queue_free()
			popup.queue_free()
			_lock_interaction_briefly()
			get_viewport().set_input_as_handled()
	)
	var root: Window = get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)

	var close_btn: Button = popup.find_child("CloseButton", true, false) as Button
	if close_btn:
		close_btn.pressed.connect(func():
			suppress_next_click = true
			dim.queue_free()
			popup.queue_free()
			_lock_interaction_briefly()
		)
	return dim

func _show_center_scale_in(popup: Control) -> void:
	popup.set_as_top_level(true)
	popup.visible = true
	await get_tree().process_frame
	var vp: Vector2 = get_viewport_rect().size
	popup.size = Vector2(vp.x * 0.9, popup.get_combined_minimum_size().y)
	popup.set_pivot_offset(popup.size / 2)
	popup.position = (vp / 2) - (popup.size / 2)
	popup.scale = Vector2.ZERO
	var t: Tween = create_tween()
	t.tween_property(popup, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	popup.grab_focus()

func _slide_up_in(popup: Control) -> void:
	popup.set_as_top_level(true)
	popup.visible = true
	await get_tree().process_frame
	var vp: Vector2 = get_viewport_rect().size
	var w: float = vp.x * 0.95
	popup.size = Vector2(w, popup.get_combined_minimum_size().y)
	popup.position = Vector2((vp.x - w) / 2, vp.y)
	var target: Vector2 = Vector2((vp.x - w) / 2, vp.y - popup.size.y - 50)
	var t: Tween = create_tween()
	t.tween_property(popup, "position", target, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	popup.grab_focus()

func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Four In A Row[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
• Be the first player to connect four of your colored pieces in a row.
• Rows can be vertical, horizontal, or diagonal.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• Players take turns dropping one piece into any of the columns on the board.
• The piece will fall to the lowest available space in that column.
• Once placed, a piece cannot be moved or removed.
• After your move, play passes to your opponent.
[/font_size]

[font_size={24px}][b]Winning the Game[/b][/font_size]
[font_size={18px}]
• You win by connecting four of your own colored pieces in a straight line—vertically, horizontally, or diagonally.
• If the board fills completely with no four-in-a-row for either player, the game ends in a draw.
[/font_size]
"""

func _parse_avatar_string(data_string: String) -> Dictionary:
	var hair_map: Array			= AvatarThumbnail.avatar_hair_regions.keys()
	var body_map: Array			= AvatarThumbnail.avatar_fshape_regions.keys()
	var eyes_map: Array			= AvatarThumbnail.avatar_eyes_regions.keys()
	var mouth_map: Array		= AvatarThumbnail.avatar_mouth_regions.keys()
	var clothing_map: Array		= AvatarThumbnail.avatar_clothing_regions.keys()
	var backdrop_map: Array		= ["Plain"]
	backdrop_map.append_array(AvatarThumbnail.avatar_background_regions.keys())

	var data: Dictionary = {
		"fshape_style":   (body_map[0]     if body_map.size()     > 0 else "Default"),
		"hair_style":     (hair_map[0]     if hair_map.size()     > 0 else "hair1"),
		"eyes_style":     (eyes_map[0]     if eyes_map.size()     > 0 else "eyes1"),
		"mouth_style":    (mouth_map[0]    if mouth_map.size()    > 0 else "mouth1"),
		"clothing_style": (clothing_map[0] if clothing_map.size() > 0 else "clothing1"),
		"bg_style":       "Plain",
		"fshape_color":   Color(0.88, 0.67, 0.41),
		"hair_color":     Color(0.17, 0.14, 0.17),
		"clothing_color": Color(0.63, 0.24, 0.24),
		"bg_color":       Color(0.31, 0.36, 0.54),
	}

	if data_string.is_empty():
		return data

	var read_color := func(vals: Array) -> Color:
		if vals.size() >= 3:
			return Color(vals[0].to_float(), vals[1].to_float(), vals[2].to_float())
		return Color.WHITE

	for part in data_string.split("|", false):
		var key_value: PackedStringArray = part.split(",", false)
		if key_value.size() < 2:
			continue
		var key: String = key_value[0]

		match key:
			"fshape", "body":
				var i: int = key_value[1].to_int()
				if i >= 0 and i < body_map.size():
					data["fshape_style"] = String(body_map[i])
			"fshape_color", "body_color":
				data["fshape_color"] = read_color.call(key_value.slice(1))
			"hair":
				var hi: int = key_value[1].to_int()
				if hi >= 0 and hi < hair_map.size():
					data["hair_style"] = String(hair_map[hi])
			"hair_color":
				data["hair_color"] = read_color.call(key_value.slice(1))
			"eyes":
				var ei: int = key_value[1].to_int()
				if ei >= 0 and ei < eyes_map.size():
					data["eyes_style"] = String(eyes_map[ei])
			"mouth":
				var mi: int = key_value[1].to_int()
				if mi >= 0 and mi < mouth_map.size():
					data["mouth_style"] = String(mouth_map[mi])
			"clothes":
				var ci: int = key_value[1].to_int()
				if ci >= 0 and ci < clothing_map.size():
					data["clothing_style"] = String(clothing_map[ci])
			"clothes_color":
				data["clothing_color"] = read_color.call(key_value.slice(1))
			"bg_color":
				data["bg_color"] = read_color.call(key_value.slice(1))
			"backdrop":
				var bi: int = key_value[1].to_int()
				if bi >= 0 and bi < backdrop_map.size():
					data["bg_style"] = String(backdrop_map[bi])
			_:
				pass
	return data

func _on_theme_changed(_n: String) -> void:
	pass

func _unhandled_input(e: InputEvent) -> void:
	if suppress_next_click and e is InputEventMouseButton and e.pressed:
		suppress_next_click = false
		get_viewport().set_input_as_handled()

func _load_game_specific_settings() -> void:
	var vol: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(vol))
	var _dbg: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))

func _lock_interaction_briefly(d: float=0.25) -> void:
	can_interact = false
	var timer: SceneTreeTimer = get_tree().create_timer(d)
	timer.timeout.connect(func():
		can_interact = true
	)
