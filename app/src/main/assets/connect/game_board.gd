extends BaseGame
class_name ConnectGameBoard

@onready var player_avatar_display: Control = %PlayerAvatarDisplay
@onready var opp_avatar_display: Control = %OppAvatarDisplay
@onready var send_button: Button = %SendButton
@onready var sent_label: Label = %SentLabel
@onready var background: ColorRect = %Background
@onready var win_loss_label: Label = %WinLossLabel
@onready var player_piece: TextureRect = %PlayerPiece
@onready var opp_piece: TextureRect = %OppPiece
@onready var you_label: Label = %YouLabel
@onready var spec_label: Label = %SpecLabel

const BOARD_W:= 7
const BOARD_H:= 6
const PIECE_YELLOW:= "yellow"
const PIECE_RED:= "red"
const DROP_START_OFFSET	:= 90.0
const DIRS:= [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(1,-1)]
const MUSIC_STREAM := preload("res://global/audio/connect4.ogg")
const PIECE_TEX := {
	"red": preload("res://connect/red_piece.png"),
	"yellow": preload("res://connect/yellow_piece.png")
}

var yPoses: Array[float] = [192.544, 109.498, 26.612, -56.274, -139.121, -221.902]
var sent_tween: Tween
var turn_owner: int	= 1
var isTurn: bool	= false
var _last_applied_replay: String = ""
var waitingForOpponent: bool	= true
var win_loss_state: String = ""
var replay: String = ""
var player: int	= 0		# 0=spectator/unknown, 1=P1, 2=P2
var game_over: bool	= false
var can_interact: bool	= true
var _replay_apply_id: int = 0
var last_highlight: Node2D = null
var droppedPiece: RigidBody2D = null
const PIECE_DRAG_THRESHOLD := 8.0

var _piece_pointer_down := false
var _piece_dragging := false
var _piece_press_column := -1
var _piece_press_global := Vector2.ZERO
var _piece_drag_origin := Vector2i(-1, -1)
var _piece_motion_tween: Tween
var _local_piece_icon_hidden := false
var board_state: PackedInt32Array = PackedInt32Array()
var winner : String = ""
var _highlighted_column: int = -1
var _column_highlight_rect: ColorRect
var _column_highlight_tween: Tween

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM

const LOG_TAG := "Connect4"
var DEBUG_CONNECT4 := false

func dbg(msg: String) -> void:
	if DEBUG_CONNECT4:
		OpLog.d(LOG_TAG, msg)

func _get_dev_data() -> String:
	return '{"isYourTurn":true,"player":"2","replay":"board:1,1,1,0,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"}'
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Four In A Row"

func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	var is_dark = bool(SettingsManager.get_setting("global", "dark_mode", false))

	OpLog.i(LOG_TAG, [
		"game_ready dark_mode=", is_dark,
		" player=", player,
		" replay_empty=", replay.is_empty()
	])

	if is_instance_valid(background):
		background.color = Color("352925ff") if is_dark else Color("#d8c7c2")
	else:
		OpLog.w(LOG_TAG, "missing_background")

	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)

		if not send_button.pressed.is_connected(send_game):
			send_button.pressed.connect(send_game)
	else:
		OpLog.w(LOG_TAG, "missing_send_button")

	if player == 0 or replay.is_empty():
		OpLog.d(LOG_TAG, [
			"game_ready_skip_hydrate player=", player,
			" replay_empty=", replay.is_empty()
		])
		return

	_label_you_box()
	_hydrate_board_from_replay(replay)
	_reset_board_state()

	if not game_over:
		await get_tree().process_frame
		_set_waiting(not isTurn)

func _clear_board_pieces() -> void:
	_clear_last_highlight()
	_clear_column_highlight()
	_clear_pending_move()

	for c in get_children():
		if c is RigidBody2D:
			var n: String = String(c.name)
			if n.find(",") != -1:
				c.queue_free()
	_reset_board_state()

func _set_game_data(new_replay: String) -> void:
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", new_replay])

	var parsed: Variant = JSON.parse_string(new_replay)

	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, [
			"set_game_data_parse_failed type=", typeof(parsed),
			" raw=", new_replay
		])
		return

	var data: Dictionary = parsed

	isTurn = bool(data.get("isYourTurn", false))
	replay = String(data.get("replay", ""))

	var p1_id: String = String(data.get("player1", ""))
	var p2_id: String = String(data.get("player2", ""))
	turn_owner = clamp(int(data.get("player", 1)), 1, 2)

	OpLog.i(LOG_TAG, [
		"set_game_data_fields my_uuid=", my_uuid,
		" player1=", p1_id,
		" player2=", p2_id,
		" turn_owner=", turn_owner,
		" isTurn=", isTurn,
		" replay_len=", replay.length(),
		" has_winner=", String(data.get("winner", "")) != ""
	])

	if my_uuid != "" and p1_id != "" and p2_id != "":
		if my_uuid == p1_id:
			player = 1
		elif my_uuid == p2_id:
			player = 2
		else:
			player = 0
	elif p1_id == "" or p2_id == "":
		if (turn_owner == 2 and isTurn) or turn_owner == 1:
			player = 1
		else:
			player = 2
	else:
		player = 0

	spectator_mode = (player == 0)

	OpLog.i(LOG_TAG, [
		"resolved_player player=", player,
		" spectator=", spectator_mode,
		" isTurn=", isTurn
	])

	if is_instance_valid(spec_label):
		spec_label.visible = spectator_mode

	if is_instance_valid(you_label):
		you_label.modulate.a = 1.0 if not spectator_mode else 0.0

	var opp_key: String = ""

	if player == 1:
		opp_key = "avatar2"
	elif player == 2:
		opp_key = "avatar1"

	if opp_key != "" and data.has(opp_key):
		var opp_data: Dictionary = GameUtils._parse_avatar_string(String(data[opp_key]))
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opp_data)
	else:
		dbg("opponent_avatar_missing key=%s" % opp_key)

	if sent_tween and sent_tween.is_running():
		sent_tween.kill()

	if is_instance_valid(sent_label):
		sent_label.visible = false
		sent_label.modulate.a = 1.0

	if is_instance_valid(player_piece) and is_instance_valid(opp_piece):
		player_piece.texture = PIECE_TEX[getPlayerColor(false)]
		opp_piece.texture = PIECE_TEX[getPlayerColor(true)]
	else:
		OpLog.w(LOG_TAG, "piece_icons_missing")

	if is_instance_valid(you_label):
		you_label.text = "You"
		you_label.modulate.a = 1.0 if not spectator_mode else 0.0

	_label_you_box()

	winner = String(data.get("winner", ""))

	if winner != "":
		OpLog.event(LOG_TAG, ["winner_payload_received payload=", winner])

	stop_waiting_animation()
	_update_send_button_visibility(false)
	can_interact = false

	var replay_will_apply := _hydrate_board_from_replay(replay)

	OpLog.i(LOG_TAG, [
		"set_game_data_replay hydrate_started=", replay_will_apply,
		" replay_len=", replay.length()
	])

	if not replay_will_apply:
		_finish_replay_turn_state()

func _label_you_box() -> void:
	if spectator_mode:
		return
	var box: Node = get_node_or_null("../Player%dBox" % player)
	if box:
		(box.get_child(0) as Label).set_text("[center]You[/center]")

func _idx(x: int, y: int) -> int:
	return y * BOARD_W + x

func _reset_board_state() -> void:
	board_state.resize(BOARD_W * BOARD_H)
	for i in range(board_state.size()):
		board_state[i] = 0
		
func _is_board_full() -> bool:
	if board_state.size() < BOARD_W * BOARD_H:
		return false

	for i in range(BOARD_W * BOARD_H):
		if board_state[i] == 0:
			return false

	return true

func _finish_replay_turn_state() -> void:
	if game_over:
		can_interact = false
		isTurn = false
		waitingForOpponent = false
		stop_waiting_animation()
		_update_send_button_visibility(false)

		OpLog.i(LOG_TAG, "finish_replay_turn_state game_over=true")
		return

	if _is_board_full():
		OpLog.event(LOG_TAG, "finish_replay_board_full_draw")
		_finalize_draw()
		return

	can_interact = (not spectator_mode) and isTurn
	waitingForOpponent = (not spectator_mode) and (not isTurn)

	OpLog.i(LOG_TAG, [
		"finish_replay_turn_state can_interact=", can_interact,
		" spectator=", spectator_mode,
		" game_over=", game_over,
		" isTurn=", isTurn,
		" waiting=", waitingForOpponent
	])

	if waitingForOpponent:
		_set_waiting(true)
	else:
		_set_waiting(false)

	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)

func _finalize_draw() -> void:
	if game_over:
		return

	game_over = true
	can_interact = false
	isTurn = false
	waitingForOpponent = false
	win_loss_state = "0"

	OpLog.event(LOG_TAG, [
		"finalize_draw player=", player,
		" spectator=", spectator_mode
	])

	stop_waiting_animation()
	_update_send_button_visibility(false)

	if is_instance_valid(win_loss_label):
		win_loss_label.text = "DRAW!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
		win_loss_label.visible = true

		await get_tree().process_frame
		win_loss_label.scale = Vector2.ZERO
		win_loss_label.pivot_offset = win_loss_label.size / 2

		var t_in: Tween = create_tween()
		t_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	else:
		OpLog.w(LOG_TAG, "draw_missing_win_loss_label")

func _hydrate_board_from_replay(rep: String) -> bool:
	if rep.is_empty():
		OpLog.d(LOG_TAG, "hydrate_replay_skipped empty")
		return false

	if rep == _last_applied_replay:
		OpLog.d(LOG_TAG, ["hydrate_replay_skipped duplicate len=", rep.length()])
		return false

	_last_applied_replay = rep
	_replay_apply_id += 1

	OpLog.event(LOG_TAG, [
		"hydrate_replay_start apply_id=", _replay_apply_id,
		" replay_len=", rep.length()
	])

	call_deferred("_apply_replay_with_drop", rep, _replay_apply_id)
	return true

func _apply_replay_with_drop(rep: String, apply_id: int) -> void:
	OpLog.i(LOG_TAG, [
		"apply_replay_with_drop start apply_id=", apply_id,
		" current_apply_id=", _replay_apply_id,
		" len=", rep.length()
	])

	_clear_board_pieces()

	var parts: PackedStringArray = rep.split("|")
	if parts.is_empty():
		OpLog.e(LOG_TAG, "apply_replay_failed empty_parts")
		return

	var head: String = String(parts[0])
	if not head.begins_with("board:"):
		OpLog.e(LOG_TAG, ["apply_replay_failed missing_board_head head=", head])
		return

	var board: PackedStringArray = head.substr(6).split(",")
	if board.size() < BOARD_W * BOARD_H:
		OpLog.e(LOG_TAG, [
			"apply_replay_failed short_board size=", board.size(),
			" expected=", BOARD_W * BOARD_H
		])
		return

	var has_move: bool = false
	var mx: int = -1
	var my: int = -1
	var mpid: int = 0

	for p in parts:
		if p.begins_with("move:"):
			var mv: PackedStringArray = p.substr(5).split(",")
			if mv.size() >= 3:
				mx = int(mv[0])
				my = int(mv[1])
				mpid = int(mv[2])
				has_move = (mx >= 0 and mx < BOARD_W and my >= 0 and my < BOARD_H and mpid > 0)
			else:
				OpLog.w(LOG_TAG, ["bad_replay_move part=", p])

	var static_count := 0

	for y in range(0, BOARD_H):
		for x in range(0, BOARD_W):
			var idx := y * BOARD_W + x
			var v: int = int(board[idx])

			if has_move and x == mx and y == my:
				v = 0

			board_state[_idx(x, y)] = v

			if v == 1 or v == 2:
				_spawn_piece_static(x, v, y)
				static_count += 1

	OpLog.i(LOG_TAG, [
		"apply_replay_board_loaded static_count=", static_count,
		" has_move=", has_move,
		" move_x=", mx,
		" move_y=", my,
		" move_pid=", mpid
	])

	if has_move:
		board_state[_idx(mx, my)] = mpid
		_spawn_piece_drop_anim(mx, mpid, my, apply_id)
	else:
		_finish_replay_turn_state()

func _spawn_piece_static(x: int, pid: int, y: int) -> Node2D:
	var proto: RigidBody2D = get_node("ConnectPiece" + str(x))
	var piece: RigidBody2D = proto.duplicate()

	piece.position.y = yPoses[y]
	piece.name = "%d,%d" % [x, y]

	add_child(piece)

	var spr: Sprite2D = piece.get_child(0) as Sprite2D
	spr.texture = PIECE_TEX[_player_id_to_color(pid)]

	(piece.get_child(1) as CollisionShape2D).disabled = false
	piece.visible = true
	piece.set_freeze_enabled(true)
	piece.z_index = 5

	return piece

func _spawn_piece_drop_anim(x: int, pid: int, y: int, apply_id: int) -> void:
	var color := _player_id_to_color(pid)
	var piece := _make_board_piece_for_column(x, color)

	piece.name = "%d,%d" % [x, y]

	var start_global: Vector2

	if spectator_mode:
		start_global = _piece_icon_center_global(player_piece if pid == 1 else opp_piece)
	else:
		start_global = _piece_icon_center_global(player_piece if pid == player else opp_piece)

	await _animate_piece_from_icon_to_slot(piece, start_global, x, y)

	if apply_id != _replay_apply_id:
		if is_instance_valid(piece):
			piece.queue_free()
		return

	_highlight_last(piece)
	_check_and_finalize_from_board()
	_finish_replay_turn_state()

func _place_or_move_piece_to_column(col: int, from_drag: bool) -> void:
	if _is_blocking_menu_open():
		OpLog.w(LOG_TAG, ["place_blocked menu_open col=", col, " from_drag=", from_drag])
		return

	if game_over or not can_interact or spectator_mode:
		OpLog.w(LOG_TAG, [
			"place_blocked state col=", col,
			" from_drag=", from_drag,
			" game_over=", game_over,
			" can_interact=", can_interact,
			" spectator=", spectator_mode
		])
		return

	if col < 0 or col >= BOARD_W:
		OpLog.w(LOG_TAG, ["place_blocked bad_col col=", col])
		return

	var color: String = getPlayerColor()
	var pid: int = 1 if color == PIECE_YELLOW else 2
	var old_x: int = -1
	var old_y: int = -1

	if is_instance_valid(droppedPiece):
		old_x = int(droppedPiece.name.get_slice(",", 0))
		old_y = int(droppedPiece.name.get_slice(",", 1))

		if old_x >= 0 and old_x < BOARD_W and old_y >= 0 and old_y < BOARD_H:
			board_state[_idx(old_x, old_y)] = 0

		if old_x == col and old_y >= 0 and not from_drag:
			board_state[_idx(old_x, old_y)] = pid
			OpLog.d(LOG_TAG, ["place_same_column_noop col=", col, " row=", old_y])
			return

	var row: int = get_piece_y(col)

	if row < 0:
		OpLog.w(LOG_TAG, ["place_blocked column_full col=", col])

		if old_x >= 0 and old_x < BOARD_W and old_y >= 0 and old_y < BOARD_H:
			board_state[_idx(old_x, old_y)] = pid

			if is_instance_valid(droppedPiece):
				droppedPiece.name = "%d,%d" % [old_x, old_y]
				await _animate_pending_piece_to_slot(droppedPiece, old_x, old_y)
		else:
			_clear_pending_move()

		return

	var is_first_piece: bool = not is_instance_valid(droppedPiece)

	OpLog.event(LOG_TAG, [
		"local_piece_placed col=", col,
		" row=", row,
		" pid=", pid,
		" color=", color,
		" from_drag=", from_drag,
		" first_piece=", is_first_piece,
		" old_x=", old_x,
		" old_y=", old_y
	])

	if is_first_piece:
		droppedPiece = _make_board_piece_for_column(col, color)
		droppedPiece.name = "%d,%d" % [col, row]
		_set_local_piece_icon_hidden(true)
		board_state[_idx(col, row)] = pid

		if from_drag:
			droppedPiece.position = _slot_pos(col, row)
			await _animate_pending_piece_to_slot(droppedPiece, col, row)
		else:
			await _animate_piece_from_icon_to_slot(droppedPiece, _piece_icon_center_global(player_piece), col, row)
	else:
		droppedPiece.name = "%d,%d" % [col, row]
		board_state[_idx(col, row)] = pid
		await _animate_pending_piece_to_slot(droppedPiece, col, row)

	if _check_and_finalize_from_board():
		_update_send_button_visibility(false)
		await get_tree().process_frame
		await send_game()
	elif _is_board_full():
		OpLog.event(LOG_TAG, "local_move_filled_board_draw")
		_finalize_draw()
		await get_tree().process_frame
		await send_game()
	else:
		_update_send_button_visibility(true)

func send_game() -> void:
	if _is_blocking_menu_open():
		OpLog.w(LOG_TAG, "send_game_blocked menu_open")
		return

	if droppedPiece == null:
		OpLog.w(LOG_TAG, "send_game_blocked no_dropped_piece")
		return

	await get_tree().process_frame

	var move_x: int = int(droppedPiece.name.get_slice(",", 0))
	var move_y: int = int(droppedPiece.name.get_slice(",", 1))
	var move_color: String = str(player)

	var board_str := ""

	for y in range(0, BOARD_H):
		for x in range(0, BOARD_W):
			if x == move_x and y == move_y:
				board_str += "0,"
			else:
				board_str += str(board_state[_idx(x, y)]) + ","

	board_str = board_str.left(board_str.length() - 1)

	var payload: Dictionary = {
		"replay": "board:%s|move:%d,%d,%s" % [board_str, move_x, move_y, move_color]
	}

	if game_over and win_loss_state != "":
		payload["winner"] = "%s|%s" % [my_uuid, win_loss_state]
		OpLog.event(LOG_TAG, [
			"send_game_winner winner=", payload["winner"],
			" win_loss_state=", win_loss_state
		])

	var avatar_key: String = "avatar1" if player == 1 else "avatar2"

	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.call("get_avatar_data_string")

	var json := JSON.stringify(payload)

	OpLog.event(LOG_TAG, [
		"send_game_out player=", player,
		" move_x=", move_x,
		" move_y=", move_y,
		" move_color=", move_color,
		" game_over=", game_over,
		" has_winner=", payload.has("winner"),
		" replay_len=", str(payload["replay"]).length(),
		" raw=", json
	])

	send_game_data(json)

	_restore_local_piece_icon()

	if is_instance_valid(droppedPiece):
		droppedPiece.z_index = 5

	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)

	if game_over:
		can_interact = false
		isTurn = false
		waitingForOpponent = false
		stop_waiting_animation()
	else:
		can_interact = false
		isTurn = false
		waitingForOpponent = true
		play_sent_animation()

func _is_blocking_menu_open() -> bool:
	if get("_settings_open") == true or get("_rules_open") == true:
		return true

	var root := get_tree().root

	for child in root.get_children():
		if child == self:
			continue

		if child is CanvasItem:
			var ci := child as CanvasItem
			if not ci.is_visible_in_tree():
				continue

			var n := String(child.name).to_lower()

			if n.contains("settings") or n.contains("rules") or n.contains("popup"):
				return true

	return false

func _set_waiting(enabled: bool) -> void:
	waitingForOpponent = enabled

	_clear_pending_move()

	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)

	if enabled:
		start_waiting_animation()
	else:
		stop_waiting_animation()

func _update_send_button_visibility(should_show: bool) -> void:
	if not is_instance_valid(send_button):
		return

	send_button.disabled = not should_show
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

	if should_show:
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
		OpLog.w(LOG_TAG, "sent_animation_missing_label")
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
		if not is_instance_valid(sent_label):
			return

		sent_label.visible = false
		sent_label.modulate.a = 1.0

		if game_over or spectator_mode:
			return

		if waitingForOpponent and not isTurn and not can_interact:
			start_waiting_animation()
	)

func _player_id_to_color(pid: int) -> String:
	return PIECE_YELLOW if pid == 1 else PIECE_RED

func getPlayerColor(other: bool=false) -> String:
	var mine: String = PIECE_YELLOW if player == 1 else PIECE_RED
	return (PIECE_RED if player == 1 else PIECE_YELLOW) if other else mine

func getPositionInt(x: int, y: int) -> String:
	if board_state.is_empty():
		return "0"
	return str(board_state[_idx(x, y)])

func get_piece_y(x: int) -> int:
	for y in range(0, BOARD_H):
		if board_state[_idx(x, y)] == 0:
			return y
	return -1
	
func _board_local_from_global_point(global_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * global_pos


func _piece_icon_center_global(icon: Control) -> Vector2:
	if not is_instance_valid(icon):
		return global_position

	return icon.get_global_rect().get_center()

func _set_local_piece_icon_hidden(should_hide: bool) -> void:
	_local_piece_icon_hidden = should_hide

	if is_instance_valid(player_piece):
		player_piece.visible = not should_hide

func _restore_local_piece_icon() -> void:
	_set_local_piece_icon_hidden(false)

func _column_x(col: int) -> float:
	var proto := get_node_or_null("ConnectPiece" + str(col)) as RigidBody2D

	if proto:
		return proto.position.x

	return 0.0

func _slot_pos(col: int, row: int) -> Vector2:
	return Vector2(_column_x(col), yPoses[row])

func _get_row_node(col: int) -> Control:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null

	return scene.get_node_or_null("Row%d" % col) as Control

func _ensure_column_highlight_rect() -> void:
	if is_instance_valid(_column_highlight_rect):
		if _column_highlight_rect.get_parent() != self:
			_column_highlight_rect.reparent(self)
		_column_highlight_rect.set_as_top_level(false)
		_column_highlight_rect.z_index = 1
		return

	_column_highlight_rect = ColorRect.new()
	_column_highlight_rect.name = "ColumnHighlight"
	_column_highlight_rect.color = Color(1.0, 1.0, 1.0, 0.38)
	_column_highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column_highlight_rect.visible = false
	_column_highlight_rect.z_index = 1
	_column_highlight_rect.set_as_top_level(false)

	add_child(_column_highlight_rect)

func _set_column_highlight(col: int) -> void:
	if col < 0 or col >= BOARD_W:
		_clear_column_highlight()
		return

	_ensure_column_highlight_rect()

	if not is_instance_valid(_column_highlight_rect):
		return

	var spacing: float = 80.0

	if BOARD_W > 1:
		spacing = absf(_column_x(1) - _column_x(0))

	var highlight_width: float = spacing
	var top_y: float = yPoses[BOARD_H - 1] - 20.0
	var height: float = yPoses[0] - yPoses[BOARD_H - 1] + 40.0

	var layer_sprite: Sprite2D = get_node_or_null("%TextureLayer1") as Sprite2D

	if layer_sprite != null:
		var sprite_rect: Rect2 = layer_sprite.get_rect()

		var p1: Vector2 = _board_local_from_global_point(layer_sprite.to_global(sprite_rect.position))
		var p2: Vector2 = _board_local_from_global_point(layer_sprite.to_global(sprite_rect.position + Vector2(sprite_rect.size.x, 0.0)))
		var p3: Vector2 = _board_local_from_global_point(layer_sprite.to_global(sprite_rect.position + sprite_rect.size))
		var p4: Vector2 = _board_local_from_global_point(layer_sprite.to_global(sprite_rect.position + Vector2(0.0, sprite_rect.size.y)))

		var min_y: float = min(p1.y, p2.y, p3.y, p4.y)
		var max_y: float = max(p1.y, p2.y, p3.y, p4.y)

		top_y = min_y
		height = max_y - min_y

	var my_color: String = getPlayerColor(false)

	if my_color == PIECE_YELLOW:
		_column_highlight_rect.color = Color(1.0, 0.94, 0.25, 0.48)
	else:
		_column_highlight_rect.color = Color(1.0, 0.25, 0.25, 0.46)

	_column_highlight_rect.position = Vector2(_column_x(col) - highlight_width * 0.5, top_y)
	_column_highlight_rect.size = Vector2(highlight_width, height)
	_column_highlight_rect.z_index = 1
	_column_highlight_rect.visible = true

	if _column_highlight_tween and _column_highlight_tween.is_running():
		_column_highlight_tween.kill()

	_column_highlight_rect.modulate = Color.WHITE
	_column_highlight_tween = create_tween().set_loops()
	_column_highlight_tween.tween_property(_column_highlight_rect, "modulate:a", 0.62, 0.45)
	_column_highlight_tween.tween_property(_column_highlight_rect, "modulate:a", 1.0, 0.45)

	_highlighted_column = col

func _clear_column_highlight() -> void:
	if _column_highlight_tween and _column_highlight_tween.is_running():
		_column_highlight_tween.kill()

	if is_instance_valid(_column_highlight_rect):
		_column_highlight_rect.visible = false
		_column_highlight_rect.modulate = Color.WHITE

	_highlighted_column = -1

func _column_from_global_pos(global_pos: Vector2) -> int:
	var scene: Node = get_tree().current_scene
	var nearest_col: int = -1
	var nearest_dist: float = INF

	if scene:
		for i in range(BOARD_W):
			var row: Control = scene.get_node_or_null("Row%d" % i) as Control

			if row == null:
				continue

			var rect: Rect2 = row.get_global_rect()

			if rect.has_point(global_pos):
				return i

			var center_x: float = rect.get_center().x
			var dist_to_row: float = absf(global_pos.x - center_x)

			if dist_to_row < nearest_dist:
				nearest_dist = dist_to_row
				nearest_col = i

	if nearest_col != -1:
		return nearest_col

	var local: Vector2 = _board_local_from_global_point(global_pos)
	var best_col: int = 0
	var best_dist: float = INF

	for i in range(BOARD_W):
		var dist_to_col: float = absf(local.x - _column_x(i))

		if dist_to_col < best_dist:
			best_dist = dist_to_col
			best_col = i

	return best_col

func _haptic_explosion(strength: float = 0.35, duration_ms: int = 22) -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return

	strength = clampf(strength, 0.0, 1.0)
	Input.vibrate_handheld(duration_ms, strength)
	
func _gravity_duration(from_y: float, to_y: float, min_time: float = 0.12, max_time: float = 0.42) -> float:
	var dy: float = absf(to_y - from_y)
	var gravity_px: float = 4200.0
	return clampf(sqrt((2.0 * dy) / gravity_px), min_time, max_time)

func _make_board_piece_for_column(col: int, color: String) -> RigidBody2D:
	var proto := get_node("ConnectPiece" + str(col)) as RigidBody2D
	var piece := proto.duplicate() as RigidBody2D

	add_child(piece)

	var spr := piece.get_child(0) as Sprite2D
	spr.texture = PIECE_TEX[color]

	var col_shape := piece.get_child(1) as CollisionShape2D
	col_shape.disabled = true

	piece.visible = true
	piece.set_freeze_enabled(true)
	piece.z_index = 3

	return piece

func _quad_bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var ab := a.lerp(b, t)
	var bc := b.lerp(c, t)
	return ab.lerp(bc, t)

func _animate_piece_from_icon_to_slot(piece: RigidBody2D, start_global: Vector2, col: int, row: int) -> void:
	if not is_instance_valid(piece):
		return

	if _piece_motion_tween and _piece_motion_tween.is_running():
		_piece_motion_tween.kill()

	var start_pos: Vector2 = _board_local_from_global_point(start_global)
	var target_pos: Vector2 = _slot_pos(col, row)
	var top_y: float = yPoses[BOARD_H - 1] - DROP_START_OFFSET
	var entry_y: float = min(top_y, start_pos.y, target_pos.y) - 8.0
	var entry_pos: Vector2 = Vector2(_column_x(col), entry_y)
	var duration: float = _gravity_duration(start_pos.y, target_pos.y, 0.26, 0.48)

	piece.position = start_pos
	piece.z_index = 3

	_piece_motion_tween = create_tween().set_parallel(false)
	_piece_motion_tween.tween_method(
		func(t: float):
			if not is_instance_valid(piece):
				return

			var arc_t: float = sin(t * PI * 0.5)
			var fall_t: float = t * t
			var arc_pos: Vector2 = _quad_bezier(start_pos, entry_pos, target_pos, arc_t)

			piece.position = Vector2(
				arc_pos.x,
				lerpf(start_pos.y, target_pos.y, fall_t)
			),
		0.0,
		1.0,
		duration
	).set_trans(Tween.TRANS_LINEAR)

	await _piece_motion_tween.finished

	if is_instance_valid(piece):
		piece.position = target_pos

		var col_shape: CollisionShape2D = piece.get_child(1) as CollisionShape2D
		col_shape.disabled = false

		if piece != droppedPiece:
			piece.z_index = 5
		else:
			piece.z_index = 3

	_haptic_explosion(0.28, 18)

func _animate_pending_piece_to_slot(piece: RigidBody2D, col: int, row: int) -> void:
	if not is_instance_valid(piece):
		return

	if _piece_motion_tween and _piece_motion_tween.is_running():
		_piece_motion_tween.kill()

	var start_pos: Vector2 = piece.position
	var target_pos: Vector2 = _slot_pos(col, row)
	var duration: float = _gravity_duration(start_pos.y, target_pos.y, 0.12, 0.34)

	piece.z_index = 3

	_piece_motion_tween = create_tween().set_parallel(false)
	_piece_motion_tween.tween_method(
		func(t: float):
			if not is_instance_valid(piece):
				return

			if target_pos.y < start_pos.y:
				var control_pos: Vector2 = Vector2(
					(start_pos.x + target_pos.x) * 0.5,
					min(start_pos.y, target_pos.y) - 55.0
				)
				piece.position = _quad_bezier(start_pos, control_pos, target_pos, t)
			else:
				var x_t: float = sin(t * PI * 0.5)
				var y_t: float = t * t
				piece.position = Vector2(
					lerpf(start_pos.x, target_pos.x, x_t),
					lerpf(start_pos.y, target_pos.y, y_t)
				),
		0.0,
		1.0,
		duration
	).set_trans(Tween.TRANS_LINEAR)

	await _piece_motion_tween.finished

	if is_instance_valid(piece):
		piece.position = target_pos

		var col_shape: CollisionShape2D = piece.get_child(1) as CollisionShape2D
		col_shape.disabled = false

	_haptic_explosion(0.24, 16)

func _set_drag_piece_position(global_pos: Vector2) -> void:
	if not is_instance_valid(droppedPiece):
		return

	var col: int = _column_from_global_pos(global_pos)
	var old_x: int = -1
	var old_y: int = -1
	var old_val: int = 0

	if is_instance_valid(droppedPiece):
		old_x = int(droppedPiece.name.get_slice(",", 0))
		old_y = int(droppedPiece.name.get_slice(",", 1))

		if old_x >= 0 and old_x < BOARD_W and old_y >= 0 and old_y < BOARD_H:
			old_val = board_state[_idx(old_x, old_y)]
			board_state[_idx(old_x, old_y)] = 0

	var row: int = get_piece_y(col)

	if old_x >= 0 and old_x < BOARD_W and old_y >= 0 and old_y < BOARD_H:
		board_state[_idx(old_x, old_y)] = old_val

	if row >= 0:
		droppedPiece.position = _slot_pos(col, row)
	else:
		droppedPiece.position = Vector2(_column_x(col), yPoses[BOARD_H - 1] - DROP_START_OFFSET)

	_set_column_highlight(col)

func column_pointer_down(col: int, global_pos: Vector2) -> void:
	if _is_blocking_menu_open():
		return

	if game_over or not can_interact or spectator_mode:
		return

	if col < 0 or col >= BOARD_W:
		return

	_piece_pointer_down = true
	_piece_dragging = false
	_piece_press_column = col
	_piece_press_global = global_pos

	if is_instance_valid(droppedPiece):
		_piece_drag_origin = Vector2i(
			int(droppedPiece.name.get_slice(",", 0)),
			int(droppedPiece.name.get_slice(",", 1))
		)
	else:
		_piece_drag_origin = Vector2i(-1, -1)
	
	_set_column_highlight(col)

func _input(event: InputEvent) -> void:
	if not _piece_pointer_down:
		return

	if game_over or not can_interact or spectator_mode:
		_piece_pointer_down = false
		_piece_dragging = false
		_piece_press_column = -1
		_piece_drag_origin = Vector2i(-1, -1)
		_clear_column_highlight()
		return

	if event is InputEventMouseMotion:
		var gp_mouse_motion: Vector2 = (event as InputEventMouseMotion).position

		if not _piece_dragging and gp_mouse_motion.distance_to(_piece_press_global) < PIECE_DRAG_THRESHOLD:
			return

		if not _piece_dragging:
			_piece_dragging = true

			if not is_instance_valid(droppedPiece):
				var color_mouse: String = getPlayerColor()
				droppedPiece = _make_board_piece_for_column(_piece_press_column, color_mouse)
				droppedPiece.name = "-1,-1"
				_set_local_piece_icon_hidden(true)
			else:
				if _piece_drag_origin.x >= 0 and _piece_drag_origin.y >= 0:
					board_state[_idx(_piece_drag_origin.x, _piece_drag_origin.y)] = 0

			if _piece_motion_tween and _piece_motion_tween.is_running():
				_piece_motion_tween.kill()

		_set_drag_piece_position(gp_mouse_motion)

	elif event is InputEventScreenDrag:
		var gp_screen_drag: Vector2 = (event as InputEventScreenDrag).position

		if not _piece_dragging and gp_screen_drag.distance_to(_piece_press_global) < PIECE_DRAG_THRESHOLD:
			return

		if not _piece_dragging:
			_piece_dragging = true

			if not is_instance_valid(droppedPiece):
				var color_touch: String = getPlayerColor()
				droppedPiece = _make_board_piece_for_column(_piece_press_column, color_touch)
				droppedPiece.name = "-1,-1"
				_set_local_piece_icon_hidden(true)
			else:
				if _piece_drag_origin.x >= 0 and _piece_drag_origin.y >= 0:
					board_state[_idx(_piece_drag_origin.x, _piece_drag_origin.y)] = 0

			if _piece_motion_tween and _piece_motion_tween.is_running():
				_piece_motion_tween.kill()

		_set_drag_piece_position(gp_screen_drag)

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
			return

		var gp_mouse_release: Vector2 = mb.position
		var release_col_mouse: int = _column_from_global_pos(gp_mouse_release)

		_piece_pointer_down = false
		_clear_column_highlight()

		if _piece_dragging:
			_piece_dragging = false
			_place_or_move_piece_to_column(release_col_mouse, true)
		else:
			_place_or_move_piece_to_column(_piece_press_column, false)

		_piece_press_column = -1
		_piece_drag_origin = Vector2i(-1, -1)

	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch

		if touch.pressed:
			return

		var gp_touch_release: Vector2 = touch.position
		var release_col_touch: int = _column_from_global_pos(gp_touch_release)

		_piece_pointer_down = false
		_clear_column_highlight()

		if _piece_dragging:
			_piece_dragging = false
			_place_or_move_piece_to_column(release_col_touch, true)
		else:
			_place_or_move_piece_to_column(_piece_press_column, false)

		_piece_press_column = -1
		_piece_drag_origin = Vector2i(-1, -1)

func spawnPiece(x: int, color: String, y: int=-1, from_replay: bool=false) -> void:
	if from_replay:
		var pid := 1 if color == PIECE_YELLOW else 2
		var row := y

		if row < 0:
			row = get_piece_y(x)

		if row < 0:
			return

		board_state[_idx(x, row)] = pid
		var piece := _make_board_piece_for_column(x, color)
		piece.position = _slot_pos(x, row)
		piece.name = "%d,%d" % [x, row]

		var col_shape := piece.get_child(1) as CollisionShape2D
		col_shape.disabled = false

		_highlight_last(piece)
		_check_and_finalize_from_board()
		return

	_place_or_move_piece_to_column(x, false)

func move_dropped_piece_to_column(new_x: int) -> void:
	if _is_blocking_menu_open():
		return

	if game_over or not can_interact or droppedPiece == null:
		return

	_place_or_move_piece_to_column(new_x, false)

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
			var base: int = board_state[_idx(x, y)]
			if base == 0:
				continue

			for d in DIRS:
				var px: int = x - d.x
				var py: int = y - d.y
				var prev_ok: bool = (px >= 0 and px < BOARD_W and py >= 0 and py < BOARD_H)

				if prev_ok and board_state[_idx(px, py)] == base:
					continue

				var run: Array[Vector2i] = []
				var cx: int = x
				var cy: int = y

				while cx >= 0 and cx < BOARD_W and cy >= 0 and cy < BOARD_H and board_state[_idx(cx, cy)] == base:
					run.append(Vector2i(cx, cy))
					cx += d.x
					cy += d.y

				if run.size() >= 4:
					return {
						"coords": run,
						"pid": base
					}

	return {}

func _check_and_finalize_from_board() -> bool:
	var win: Dictionary = _find_winning_sequence()
	if win.is_empty():
		return false

	_clear_last_highlight()

	var coords: Array[Vector2i] = win["coords"]

	OpLog.event(LOG_TAG, [
		"win_sequence_found pid=", int(win["pid"]),
		" coords=", coords,
		" player=", player,
		" spectator=", spectator_mode
	])

	for c in coords:
		var n: Node2D = get_node_or_null("%d,%d" % [c.x, c.y])
		if n:
			var spr: Sprite2D = n.get_child(0) as Sprite2D
			if spr:
				_pulse_sprite(spr)

	var winner_pid: int = int(win["pid"])
	_finalize_win(winner_pid)
	return true

func _clear_last_highlight() -> void:
	if last_highlight and is_instance_valid(last_highlight):
		var spr: Sprite2D = last_highlight.get_child(0) as Sprite2D
		if spr:
			spr.self_modulate.a = 1.0

		if last_highlight.has_meta("hl_tween"):
			var t: Tween = last_highlight.get_meta("hl_tween") as Tween
			if t and t.is_running():
				t.kill()
			last_highlight.remove_meta("hl_tween")
			
	last_highlight = null

func _highlight_last(p: Node2D) -> void:
	_clear_last_highlight()
	if p == null or not is_instance_valid(p):
		return

	last_highlight = p

	var spr := p.get_child(0) as Sprite2D
	if spr == null:
		return

	var tw := _pulse_sprite(spr)
	p.set_meta("hl_tween", tw)

	if not p.is_connected("tree_exited", Callable(self, "_on_highlight_piece_exited")):
		p.tree_exited.connect(_on_highlight_piece_exited.bind(p))

func _on_highlight_piece_exited(p: Node) -> void:
	if p == null or not is_instance_valid(p):
		return

	if p.has_meta("hl_tween"):
		var t := p.get_meta("hl_tween") as Tween
		if t and t.is_running():
			t.kill()
		p.remove_meta("hl_tween")
		
	last_highlight = null

func _pulse_sprite(spr: Sprite2D) -> Tween:
	spr.self_modulate.a = 1.0
	var tw: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_loops(0)
	tw.tween_property(spr, "self_modulate:a", 0.6, 0.45)
	tw.tween_property(spr, "self_modulate:a", 1.0, 0.45)
	return tw

func _finalize_win(winner_pid: int) -> void:
	if game_over:
		return

	game_over = true
	can_interact = false
	isTurn = false
	waitingForOpponent = false

	var i_won: bool = (winner_pid == player) and (not spectator_mode)
	win_loss_state = "1" if i_won else "-1"

	stop_waiting_animation()
	_update_send_button_visibility(false)

	if spectator_mode:
		if winner_pid == 1:
			win_loss_label.text = "Player 1 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			GameUtils._show_win_burst(player_avatar_display)
		else:
			win_loss_label.text = "Player 2 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			GameUtils._show_win_burst(opp_avatar_display)
	else:
		if i_won:
			GameUtils._show_win_burst(player_avatar_display)
			win_loss_label.text = "YOU WIN!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		else:
			GameUtils._show_win_burst(opp_avatar_display)
			win_loss_label.text = "YOU LOSE"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

	OpLog.event(LOG_TAG, [
		"show_result winner_pid=", winner_pid,
		" player=", player,
		" spectator=", spectator_mode,
		" i_won=", i_won,
		" win_loss_state=", win_loss_state,
		" text=", win_loss_label.text
	])

	win_loss_label.visible = true
	await get_tree().process_frame
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2

	var t_in: Tween = create_tween()
	t_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _clear_pending_move() -> void:
	_clear_column_highlight()

	if droppedPiece == null or not is_instance_valid(droppedPiece):
		droppedPiece = null
		_restore_local_piece_icon()
		return

	if droppedPiece.has_meta("drop_tween"):
		var tw: Tween = droppedPiece.get_meta("drop_tween") as Tween
		if tw and tw.is_running():
			tw.kill()
		droppedPiece.remove_meta("drop_tween")

	if _piece_motion_tween and _piece_motion_tween.is_running():
		_piece_motion_tween.kill()

	var ox: int = int(droppedPiece.name.get_slice(",", 0))
	var oy: int = int(droppedPiece.name.get_slice(",", 1))

	if ox >= 0 and ox < BOARD_W and oy >= 0 and oy < BOARD_H:
		board_state[_idx(ox, oy)] = 0

	droppedPiece.queue_free()
	droppedPiece = null
	_update_send_button_visibility(false)
	_restore_local_piece_icon()

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
