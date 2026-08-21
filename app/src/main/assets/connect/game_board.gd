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
@onready var connect_scene_root: Control = background.get_parent() as Control
@onready var connect_main_vbox: VBoxContainer = %ConnectMainVBox
@onready var connect_top_hud_margin: MarginContainer = %ConnectTopHudMargin
@onready var connect_top_hud: HBoxContainer = %TopInfoHBoxContainer
@onready var connect_board_center: CenterContainer = %ConnectBoardCenter
@onready var connect_bottom_controls: HBoxContainer = %BottomItemHBoxContainer
@onready var connect_bottom_controls_margin: MarginContainer = %ConnectBottomControlsMargin
@onready var player_piece_top_spacer: Control = %PlayerPieceTopSpacer
@onready var opp_piece_top_spacer: Control = %OppPieceTopSpacer
@onready var opponent_avatar_top_spacer: Control = %OppLabel

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
var recovery_turn_num: String = ""
var recovery_snapshot_pending := false
var recovery_snapshot_progress := ""
var recovery_loaded := false
var recovery_restore_in_progress := false
var _highlighted_column: int = -1
var _column_highlight_rect: ColorRect
var _column_highlight_tween: Tween

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM

const LOG_TAG := "Connect4"
var DEBUG_CONNECT4 := false

const CONNECT_LANDSCAPE_BOARD_HEIGHT_RATIO := 0.80

const CONNECT_REFERENCE_BOARD_EXTENT := Vector2(
	648.0,
	621.0,
)

const CONNECT_BASE_AVATAR_SIZE := Vector2(
	96.0,
	90.0,
)

const CONNECT_BASE_PIECE_ICON_SIZE := Vector2(
	64.0,
	64.0,
)

const CONNECT_BASE_PIECE_TOP_SPACER := 40.0
const CONNECT_BASE_OPPONENT_AVATAR_SPACER := 26.0
const CONNECT_BASE_YOU_FONT_SIZE := 18.0

const CONNECT_BASE_MENU_BUTTON_SIZE := Vector2(
	64.0,
	64.0,
)

const CONNECT_BASE_MENU_BUTTON_FONT_SIZE := 32.0

const CONNECT_BASE_SEND_BUTTON_SIZE := Vector2(
	70.0,
	50.0,
)

const CONNECT_BASE_SEND_BUTTON_FONT_SIZE := 28.0

const CONNECT_LANDSCAPE_AVATAR_MIN_SCALE := 2.05
const CONNECT_LANDSCAPE_AVATAR_MAX_SCALE := 2.35

const CONNECT_BASE_TOP_SIDE_MARGIN := 20.0
const CONNECT_BASE_TOP_MARGIN := 10.0
const CONNECT_BASE_BOTTOM_SIDE_MARGIN := 40.0
const CONNECT_BASE_BOTTOM_MARGIN := 30.0

const CONNECT_PORTRAIT_BOTTOM_HEIGHT := 120.0
const CONNECT_BOARD_ACTION_GAP := 24.0
const CONNECT_LANDSCAPE_BOTTOM_PADDING := 24.0

const CONNECT_BASE_SPECTATOR_FONT_SIZE := 50.0
const CONNECT_BASE_SPECTATOR_HALF_WIDTH := 324.0
const CONNECT_BASE_SPECTATOR_HEIGHT := 220.0
const CONNECT_PORTRAIT_SPECTATOR_TOP_OFFSET := 90.0

const CONNECT_LANDSCAPE_OVERLAY_MIN_SCALE := 1.35
const CONNECT_LANDSCAPE_OVERLAY_MAX_SCALE := 1.65

const CONNECT_WIN_BURST_WRAPPER_NAME := (
	"ConnectResponsiveWinBurstWrapper"
)

var _connect_layout_pending := false
var _connect_last_viewport_size := Vector2.ZERO
var _connect_layout_generation := 0
var _connect_portrait_vbox_separation := 0

var _connect_current_avatar_scale := 1.0
var _connect_send_target_visible := false

var _connect_active_win_burst_avatar: TextureButton = null

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
	
	_initialize_connect_responsive_layout()

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
	
	recovery_turn_num = String(data.get("num", ""))
	recovery_snapshot_pending = String(data.get("_recoveryPending", "false")).to_lower() == "true"
	recovery_snapshot_progress = String(data.get("_recoveryProgress", ""))
	recovery_loaded = false
	recovery_restore_in_progress = false

	OpLog.i(LOG_TAG, [
		"recovery_snapshot pending=", recovery_snapshot_pending,
		" progressLen=", recovery_snapshot_progress.length(),
		" turn=", recovery_turn_num
	])
	
	_connect_active_win_burst_avatar = null
	_clear_connect_win_bursts()

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

	if spectator_mode:
		if data.has("avatar1"):
			var player_one_data := (
				GameUtils._parse_avatar_string(
					String(data["avatar1"]),
				)
			)

			player_avatar_display.call_deferred(
				"update_avatar_from_data",
				player_one_data,
			)

		if data.has("avatar2"):
			var player_two_data := (
				GameUtils._parse_avatar_string(
					String(data["avatar2"]),
				)
			)

			opp_avatar_display.call_deferred(
				"update_avatar_from_data",
				player_two_data,
			)
	else:
		var opp_key := (
			"avatar2"
			if player == 1
			else "avatar1"
		)

		if data.has(opp_key):
			var opponent_data := (
				GameUtils._parse_avatar_string(
					String(data[opp_key]),
				)
			)

			opp_avatar_display.call_deferred(
				"update_avatar_from_data",
				opponent_data,
			)

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
	
	_schedule_connect_responsive_layout(true)

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
	if _restore_connect4_recovery():
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
	
	_connect_active_win_burst_avatar = null
	_clear_connect_win_bursts()

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

func _save_connect4_progress(col: int, row: int) -> void:
	if recovery_restore_in_progress or spectator_mode or not isTurn or appPlugin == null:
		return

	var progress := {
		"phase": "pending",
		"turn": recovery_turn_num,
		"col": str(col),
		"row": str(row)
	}

	appPlugin.saveTurnProgress(JSON.stringify(progress))

	OpLog.i(LOG_TAG, [
		"recovery_saved col=", col,
		" row=", row,
		" turn=", recovery_turn_num
	])

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
		_save_connect4_progress(col, row)

		if from_drag:
			droppedPiece.position = _slot_pos(col, row)
			await _animate_pending_piece_to_slot(droppedPiece, col, row)
		else:
			await _animate_piece_from_icon_to_slot(droppedPiece, _piece_icon_center_global(player_piece), col, row)
	else:
		droppedPiece.name = "%d,%d" % [col, row]
		board_state[_idx(col, row)] = pid
		_save_connect4_progress(col, row)
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

func _restore_connect4_recovery() -> bool:
	if recovery_loaded or spectator_mode or not isTurn or game_over:
		return false

	if recovery_snapshot_pending:
		recovery_loaded = true
		can_interact = false
		waitingForOpponent = true
		_update_send_button_visibility(false)
		stop_waiting_animation()
		OpLog.i(LOG_TAG, "recovery_pending_send")
		return true

	if recovery_snapshot_progress.is_empty():
		return false

	var parsed: Variant = JSON.parse_string(recovery_snapshot_progress)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	var progress: Dictionary = parsed

	if String(progress.get("phase", "")) != "pending":
		return false

	var saved_turn := String(progress.get("turn", ""))
	if not saved_turn.is_empty() and not recovery_turn_num.is_empty() and saved_turn != recovery_turn_num:
		OpLog.i(LOG_TAG, [
			"recovery_stale savedTurn=", saved_turn,
			" currentTurn=", recovery_turn_num
		])
		return false

	var col := int(String(progress.get("col", "-1")))
	var row := int(String(progress.get("row", "-1")))

	if col < 0 or col >= BOARD_W or row < 0 or row >= BOARD_H:
		return false

	if board_state[_idx(col, row)] != 0:
		OpLog.w(LOG_TAG, ["recovery_slot_not_empty col=", col, " row=", row])
		return false

	recovery_loaded = true
	recovery_restore_in_progress = true

	var color := getPlayerColor()
	var pid := 1 if color == PIECE_YELLOW else 2

	board_state[_idx(col, row)] = pid
	droppedPiece = _make_board_piece_for_column(col, color)
	droppedPiece.name = "%d,%d" % [col, row]
	droppedPiece.position = _slot_pos(col, row)
	droppedPiece.z_index = 5
	droppedPiece.set_freeze_enabled(true)

	var col_shape := droppedPiece.get_child(1) as CollisionShape2D
	col_shape.disabled = false

	_set_local_piece_icon_hidden(true)
	_highlight_last(droppedPiece)

	recovery_restore_in_progress = false
	can_interact = true
	waitingForOpponent = false
	stop_waiting_animation()

	if _check_and_finalize_from_board():
		_update_send_button_visibility(false)
		call_deferred("send_game")
	elif _is_board_full():
		_finalize_draw()
		call_deferred("send_game")
	else:
		_update_send_button_visibility(true)

	OpLog.i(LOG_TAG, ["recovery_restored col=", col, " row=", row])
	return true

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

func _update_send_button_visibility(
	should_show: bool,
) -> void:
	if not is_instance_valid(send_button):
		return

	_connect_send_target_visible = should_show

	send_button.disabled = not should_show
	send_button.set_as_top_level(true)

	if not send_button.has_meta("home_pos"):
		send_button.set_meta(
			"home_pos",
			send_button.global_position,
		)

	if send_button.has_meta("sb_tween"):
		var old_tween: Variant = (
			send_button.get_meta("sb_tween")
		)

		if (
			old_tween is Tween and
			(old_tween as Tween).is_running()
		):
			(old_tween as Tween).kill()

	var home: Vector2 = (
		send_button.get_meta("home_pos")
	)

	var offscreen_y := (
		connect_scene_root.get_global_rect().end.y +
		send_button.size.y +
		30.0
	)

	var offscreen_position := Vector2(
		home.x,
		offscreen_y,
	)

	if should_show:
		send_button.visible = true
		send_button.disabled = false
		send_button.modulate.a = 1.0

		if send_button.global_position.y >= offscreen_y:
			send_button.global_position = (
				offscreen_position
			)

		var tween_in := create_tween()

		send_button.set_meta(
			"sb_tween",
			tween_in,
		)

		tween_in.tween_property(
			send_button,
			"global_position",
			home,
			0.35,
		).set_trans(
			Tween.TRANS_QUAD,
		).set_ease(
			Tween.EASE_OUT,
		)
	else:
		send_button.disabled = true

		if not send_button.visible:
			send_button.global_position = home
			send_button.modulate.a = 0.0
			return

		var tween_out := create_tween()

		send_button.set_meta(
			"sb_tween",
			tween_out,
		)

		tween_out.tween_property(
			send_button,
			"global_position",
			offscreen_position,
			0.25,
		).set_trans(
			Tween.TRANS_QUAD,
		).set_ease(
			Tween.EASE_IN,
		)

		tween_out.tween_callback(
			func() -> void:
				if not is_instance_valid(send_button):
					return

				if _connect_send_target_visible:
					return

				send_button.visible = false
				send_button.global_position = home
				send_button.modulate.a = 0.0
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
	
	_clear_connect_win_bursts()
	_connect_active_win_burst_avatar = null

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
			_show_connect_win_burst(
				player_avatar_display,
			)
		else:
			win_loss_label.text = "Player 2 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			_show_connect_win_burst(
				opp_avatar_display,
			)
	else:
		if i_won:
			_show_connect_win_burst(
				player_avatar_display,
			)
			win_loss_label.text = "YOU WIN!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		else:
			_show_connect_win_burst(
				opp_avatar_display,
			)
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
• You win by connecting four of your own colored pieces in a straight line-vertically, horizontally, or diagonally.
• If the board fills completely with no four-in-a-row for either player, the game ends in a draw.
[/font_size]
"""

func _initialize_connect_responsive_layout() -> void:
	var avatars: Array[TextureButton] = [
		player_avatar_display,
		opp_avatar_display,
	]

	for avatar_button in avatars:
		if not is_instance_valid(avatar_button):
			continue

		avatar_button.clip_contents = false

		var internal_viewport := (
			avatar_button.get_node_or_null(
				"SubViewportContainer/SubViewport",
			) as SubViewport
		)

		if internal_viewport != null:
			internal_viewport.render_target_update_mode = (
				SubViewport.UPDATE_ALWAYS
			)

		var internal_preview := (
			avatar_button.get_node_or_null(
				"SubViewportContainer",
			) as SubViewportContainer
		)

		if internal_preview != null:
			internal_preview.mouse_filter = (
				Control.MOUSE_FILTER_IGNORE
			)
			internal_preview.visible = true
			internal_preview.self_modulate = Color.WHITE

	_connect_portrait_vbox_separation = (
		connect_main_vbox.get_theme_constant(
			"separation",
		)
	)

	var viewport := get_viewport()

	if viewport == null:
		return

	if not viewport.size_changed.is_connected(
		_schedule_connect_responsive_layout,
	):
		viewport.size_changed.connect(
			_schedule_connect_responsive_layout,
		)

	_schedule_connect_responsive_layout(true)


func _schedule_connect_responsive_layout(
	force: bool = false,
) -> void:
	if force:
		_connect_last_viewport_size = Vector2.ZERO

	if _connect_layout_pending:
		return

	_connect_layout_pending = true

	call_deferred(
		"_apply_connect_responsive_layout",
	)

func _apply_connect_responsive_layout() -> void:
	_connect_layout_pending = false

	if not is_inside_tree():
		return

	var viewport := get_viewport()

	if viewport == null:
		return

	var viewport_size := (
		viewport.get_visible_rect().size
	)

	if (
		viewport_size.x <= 1.0 or
		viewport_size.y <= 1.0
	):
		return

	if viewport_size.is_equal_approx(
		_connect_last_viewport_size,
	):
		return

	_connect_last_viewport_size = viewport_size

	var is_portrait := (
		viewport_size.y >=
		viewport_size.x
	)

	# Stop an old orientation's Send-button callback from
	# hiding the button after the new layout is applied.
	if send_button.has_meta("sb_tween"):
		var old_tween: Variant = (
			send_button.get_meta("sb_tween")
		)

		if (
			old_tween is Tween and
			(old_tween as Tween).is_running()
		):
			(old_tween as Tween).kill()

	var action_scale_hint := 1.0

	if not is_portrait:
		var landscape_aspect := (
			viewport_size.x /
			maxf(
				viewport_size.y,
				1.0,
			)
		)

		action_scale_hint = clampf(
			landscape_aspect,
			CONNECT_LANDSCAPE_AVATAR_MIN_SCALE,
			CONNECT_LANDSCAPE_AVATAR_MAX_SCALE,
		)

	# ---------------------------------------------------------
	# Scene hierarchy
	# ---------------------------------------------------------

	if not is_portrait:
		if (
			connect_top_hud_margin.get_parent() !=
			connect_scene_root
		):
			connect_top_hud_margin.reparent(
				connect_scene_root,
				false,
			)

		connect_main_vbox.move_child(
			connect_board_center,
			0,
		)

		connect_main_vbox.move_child(
			connect_bottom_controls,
			1,
		)

		connect_main_vbox.alignment = (
			BoxContainer.ALIGNMENT_CENTER
		)

		connect_board_center.size_flags_horizontal = (
			Control.SIZE_SHRINK_CENTER
		)

		connect_board_center.size_flags_vertical = (
			Control.SIZE_SHRINK_CENTER
		)

		connect_top_hud_margin.z_index = 20
		spec_label.z_index = 30
	else:
		if (
			connect_top_hud_margin.get_parent() !=
			connect_main_vbox
		):
			connect_top_hud_margin.reparent(
				connect_main_vbox,
				false,
			)

		connect_main_vbox.move_child(
			connect_top_hud_margin,
			0,
		)

		connect_main_vbox.move_child(
			connect_board_center,
			1,
		)

		connect_main_vbox.move_child(
			connect_bottom_controls,
			2,
		)

		connect_main_vbox.alignment = (
			BoxContainer.ALIGNMENT_BEGIN
		)

		connect_top_hud_margin.z_index = 0

		connect_top_hud_margin.set_anchors_preset(
			Control.PRESET_TOP_LEFT,
			false,
		)

		connect_top_hud_margin.offset_left = 0.0
		connect_top_hud_margin.offset_top = 0.0
		connect_top_hud_margin.offset_right = 0.0
		connect_top_hud_margin.offset_bottom = 0.0

		connect_board_center.set_anchors_preset(
			Control.PRESET_TOP_LEFT,
			false,
		)

		connect_board_center.offset_left = 0.0
		connect_board_center.offset_top = 0.0
		connect_board_center.offset_right = 0.0
		connect_board_center.offset_bottom = 0.0

		connect_bottom_controls.set_anchors_preset(
			Control.PRESET_TOP_LEFT,
			false,
		)

		connect_bottom_controls.offset_left = 0.0
		connect_bottom_controls.offset_top = 0.0
		connect_bottom_controls.offset_right = 0.0
		connect_bottom_controls.offset_bottom = 0.0

		connect_board_center.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL
		)

		connect_board_center.size_flags_vertical = (
			Control.SIZE_EXPAND_FILL
		)

	# ---------------------------------------------------------
	# Board scale
	# ---------------------------------------------------------

	var board_scale := 1.0
	var board_display_size := CONNECT_REFERENCE_BOARD_EXTENT

	if not is_portrait:
		var target_stack_height := floorf(
			viewport_size.y *
			CONNECT_LANDSCAPE_BOARD_HEIGHT_RATIO
		)

		var action_height := (
			maxf(
				CONNECT_BASE_MENU_BUTTON_SIZE.y,
				CONNECT_BASE_SEND_BUTTON_SIZE.y,
			) *
			action_scale_hint +
			CONNECT_LANDSCAPE_BOTTOM_PADDING
		)

		var available_board_height := maxf(
			target_stack_height -
				action_height -
				CONNECT_BOARD_ACTION_GAP,
			1.0,
		)

		var available_board_width := maxf(
			viewport_size.x -
				CONNECT_BASE_BOTTOM_SIDE_MARGIN *
					2.0,
			1.0,
		)

		board_scale = minf(
			available_board_height /
				CONNECT_REFERENCE_BOARD_EXTENT.y,
			available_board_width /
				CONNECT_REFERENCE_BOARD_EXTENT.x,
		)

		board_scale = maxf(
			board_scale,
			0.01,
		)

		board_display_size = (
			CONNECT_REFERENCE_BOARD_EXTENT *
			board_scale
		)

		connect_board_center.custom_minimum_size = (
			board_display_size
		)
	else:
		connect_board_center.custom_minimum_size = (
			Vector2.ZERO
		)

	self.scale = Vector2.ONE * board_scale
	self.pivot_offset = Vector2.ZERO

	var content_scale := clampf(
		board_scale,
		0.5,
		2.0,
	)

	# ---------------------------------------------------------
	# Avatars and piece trays
	# ---------------------------------------------------------

	var avatar_scale := 1.0

	if not is_portrait:
		var landscape_aspect := (
			viewport_size.x /
			maxf(
				viewport_size.y,
				1.0,
			)
		)

		avatar_scale = clampf(
			maxf(
				content_scale,
				landscape_aspect,
			),
			CONNECT_LANDSCAPE_AVATAR_MIN_SCALE,
			CONNECT_LANDSCAPE_AVATAR_MAX_SCALE,
		)

	_connect_current_avatar_scale = avatar_scale

	var avatar_size := (
		CONNECT_BASE_AVATAR_SIZE *
		avatar_scale
	)

	var avatars: Array[TextureButton] = [
		player_avatar_display,
		opp_avatar_display,
	]

	for avatar_button in avatars:
		if not is_instance_valid(avatar_button):
			continue

		avatar_button.scale = Vector2.ONE
		avatar_button.custom_minimum_size = avatar_size
		avatar_button.queue_redraw()

	var piece_icon_size := (
		CONNECT_BASE_PIECE_ICON_SIZE *
		avatar_scale
	)

	player_piece.custom_minimum_size = piece_icon_size
	opp_piece.custom_minimum_size = piece_icon_size

	player_piece_top_spacer.custom_minimum_size = Vector2(
		0.0,
		CONNECT_BASE_PIECE_TOP_SPACER *
			avatar_scale,
	)

	opp_piece_top_spacer.custom_minimum_size = Vector2(
		0.0,
		CONNECT_BASE_PIECE_TOP_SPACER *
			avatar_scale,
	)

	opponent_avatar_top_spacer.custom_minimum_size = Vector2(
		0.0,
		CONNECT_BASE_OPPONENT_AVATAR_SPACER *
			avatar_scale,
	)

	you_label.add_theme_font_size_override(
		"font_size",
		maxi(
			roundi(
				CONNECT_BASE_YOU_FONT_SIZE *
					avatar_scale
			),
			1,
		),
	)

	# ---------------------------------------------------------
	# Rules, Settings, and Send
	# ---------------------------------------------------------

	var menu_size := (
		CONNECT_BASE_MENU_BUTTON_SIZE *
		avatar_scale
	)

	var menu_buttons: Array[Button] = [
		settings_button,
		rules_button,
	]

	for menu_button in menu_buttons:
		if not is_instance_valid(menu_button):
			continue

		menu_button.custom_minimum_size = menu_size

		menu_button.add_theme_font_size_override(
			"font_size",
			maxi(
				roundi(
					CONNECT_BASE_MENU_BUTTON_FONT_SIZE *
						avatar_scale
				),
				1,
			),
		)

	var send_size := (
		CONNECT_BASE_SEND_BUTTON_SIZE *
		avatar_scale
	)

	send_button.size_flags_horizontal = (
		Control.SIZE_SHRINK_CENTER
	)

	send_button.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER
	)

	send_button.custom_minimum_size = send_size
	send_button.size = send_size
	send_button.scale = Vector2.ONE

	send_button.add_theme_font_size_override(
		"font_size",
		maxi(
			roundi(
				CONNECT_BASE_SEND_BUTTON_FONT_SIZE *
					avatar_scale
			),
			1,
		),
	)

	send_button.pivot_offset = (
		send_size *
		0.5
	)

	# ---------------------------------------------------------
	# Landscape positioning or portrait restoration
	# ---------------------------------------------------------

	if not is_portrait:
		var top_side_margin := (
			CONNECT_BASE_TOP_SIDE_MARGIN *
			avatar_scale
		)

		var top_margin := (
			CONNECT_BASE_TOP_MARGIN *
			avatar_scale
		)

		connect_top_hud_margin.add_theme_constant_override(
			"margin_left",
			roundi(top_side_margin),
		)

		connect_top_hud_margin.add_theme_constant_override(
			"margin_top",
			roundi(top_margin),
		)

		connect_top_hud_margin.add_theme_constant_override(
			"margin_right",
			roundi(top_side_margin),
		)

		connect_top_hud_margin.set_anchors_preset(
			Control.PRESET_TOP_WIDE,
			false,
		)

		var avatar_stack_height := (
			CONNECT_BASE_AVATAR_SIZE.y *
				avatar_scale +
			CONNECT_BASE_YOU_FONT_SIZE *
				avatar_scale
		)

		var piece_stack_height := (
			CONNECT_BASE_PIECE_TOP_SPACER *
				avatar_scale +
			CONNECT_BASE_PIECE_ICON_SIZE.y *
				avatar_scale
		)

		var top_hud_height := (
			maxf(
				avatar_stack_height,
				piece_stack_height,
			) +
			top_margin
		)

		connect_top_hud_margin.offset_left = 0.0
		connect_top_hud_margin.offset_top = 0.0
		connect_top_hud_margin.offset_right = 0.0
		connect_top_hud_margin.offset_bottom = (
			top_hud_height
		)

		var bottom_side_margin := (
			CONNECT_BASE_BOTTOM_SIDE_MARGIN *
			avatar_scale
		)

		var bottom_margin := (
			CONNECT_BASE_BOTTOM_MARGIN *
			avatar_scale
		)

		connect_bottom_controls_margin.add_theme_constant_override(
			"margin_left",
			roundi(bottom_side_margin),
		)

		connect_bottom_controls_margin.add_theme_constant_override(
			"margin_right",
			roundi(bottom_side_margin),
		)

		connect_bottom_controls_margin.add_theme_constant_override(
			"margin_bottom",
			roundi(bottom_margin),
		)

		var action_height := (
			maxf(
				CONNECT_BASE_MENU_BUTTON_SIZE.y,
				CONNECT_BASE_SEND_BUTTON_SIZE.y,
			) *
			avatar_scale +
			CONNECT_LANDSCAPE_BOTTOM_PADDING
		)

		connect_bottom_controls.custom_minimum_size = Vector2(
			0.0,
			action_height,
		)

		connect_main_vbox.add_theme_constant_override(
			"separation",
			roundi(
				CONNECT_BOARD_ACTION_GAP,
			),
		)
	else:
		connect_top_hud_margin.add_theme_constant_override(
			"margin_left",
			roundi(
				CONNECT_BASE_TOP_SIDE_MARGIN,
			),
		)

		connect_top_hud_margin.add_theme_constant_override(
			"margin_top",
			roundi(
				CONNECT_BASE_TOP_MARGIN,
			),
		)

		connect_top_hud_margin.add_theme_constant_override(
			"margin_right",
			roundi(
				CONNECT_BASE_TOP_SIDE_MARGIN,
			),
		)

		connect_bottom_controls_margin.add_theme_constant_override(
			"margin_left",
			roundi(
				CONNECT_BASE_BOTTOM_SIDE_MARGIN,
			),
		)

		connect_bottom_controls_margin.add_theme_constant_override(
			"margin_right",
			roundi(
				CONNECT_BASE_BOTTOM_SIDE_MARGIN,
			),
		)

		connect_bottom_controls_margin.add_theme_constant_override(
			"margin_bottom",
			roundi(
				CONNECT_BASE_BOTTOM_MARGIN,
			),
		)

		connect_bottom_controls.custom_minimum_size = Vector2(
			0.0,
			CONNECT_PORTRAIT_BOTTOM_HEIGHT,
		)

		connect_main_vbox.add_theme_constant_override(
			"separation",
			_connect_portrait_vbox_separation,
		)

	# ---------------------------------------------------------
	# Spectator label
	# ---------------------------------------------------------

	var overlay_scale := 1.0

	if not is_portrait:
		overlay_scale = clampf(
			content_scale,
			CONNECT_LANDSCAPE_OVERLAY_MIN_SCALE,
			CONNECT_LANDSCAPE_OVERLAY_MAX_SCALE,
		)

	var spectator_top_offset := (
		CONNECT_PORTRAIT_SPECTATOR_TOP_OFFSET
		if is_portrait
		else 0.0
	)

	spec_label.set_anchors_preset(
		Control.PRESET_CENTER_TOP,
		false,
	)

	spec_label.offset_left = (
		-CONNECT_BASE_SPECTATOR_HALF_WIDTH *
			overlay_scale
	)

	spec_label.offset_right = (
		CONNECT_BASE_SPECTATOR_HALF_WIDTH *
			overlay_scale
	)

	spec_label.offset_top = spectator_top_offset

	spec_label.offset_bottom = (
		spectator_top_offset +
		CONNECT_BASE_SPECTATOR_HEIGHT *
			overlay_scale
	)

	spec_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	spec_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	spec_label.add_theme_font_size_override(
		"font_size",
		maxi(
			roundi(
				CONNECT_BASE_SPECTATOR_FONT_SIZE *
					overlay_scale
			),
			1,
		),
	)

	connect_board_center.queue_sort()
	connect_top_hud.queue_sort()
	connect_main_vbox.queue_sort()

	_connect_layout_generation += 1

	call_deferred(
		"_finish_connect_responsive_layout",
		_connect_layout_generation,
	)

func _finish_connect_responsive_layout(
	layout_generation: int,
) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if (
		not is_inside_tree() or
		layout_generation !=
			_connect_layout_generation
	):
		return

	# Rebuild the seven touch columns from the transformed
	# foreground-board bounds.
	var layer := (
		get_node_or_null(
			"%TextureLayer1",
		) as Sprite2D
	)

	if layer != null:
		var layer_rect := layer.get_rect()

		var corners: Array[Vector2] = [
			layer.to_global(
				layer_rect.position,
			),
			layer.to_global(
				layer_rect.position +
					Vector2(
						layer_rect.size.x,
						0.0,
					),
			),
			layer.to_global(
				layer_rect.position +
					layer_rect.size,
			),
			layer.to_global(
				layer_rect.position +
					Vector2(
						0.0,
						layer_rect.size.y,
					),
			),
		]

		var minimum_x := INF
		var minimum_y := INF
		var maximum_x := -INF
		var maximum_y := -INF

		for corner in corners:
			minimum_x = minf(
				minimum_x,
				corner.x,
			)

			minimum_y = minf(
				minimum_y,
				corner.y,
			)

			maximum_x = maxf(
				maximum_x,
				corner.x,
			)

			maximum_y = maxf(
				maximum_y,
				corner.y,
			)

		var column_width := (
			(maximum_x - minimum_x) /
			float(BOARD_W)
		)

		var input_height := (
			maximum_y -
			minimum_y
		)

		var scene := get_tree().current_scene

		if scene != null:
			for column in range(BOARD_W):
				var row := (
					scene.get_node_or_null(
						"Row%d" % column,
					) as Control
				)

				if row == null:
					continue

				row.set_as_top_level(true)

				row.global_position = Vector2(
					minimum_x +
						column_width *
							float(column),
					minimum_y,
				)

				row.size = Vector2(
					column_width,
					input_height,
				)

	if _highlighted_column >= 0:
		_set_column_highlight(
			_highlighted_column,
		)

	player_avatar_display.pivot_offset = (
		player_avatar_display.size *
		0.5
	)

	opp_avatar_display.pivot_offset = (
		opp_avatar_display.size *
		0.5
	)

	if send_button.has_meta("sb_tween"):
		var old_tween: Variant = (
			send_button.get_meta("sb_tween")
		)

		if (
			old_tween is Tween and
			(old_tween as Tween).is_running()
		):
			(old_tween as Tween).kill()

	var send_size := (
		CONNECT_BASE_SEND_BUTTON_SIZE *
		_connect_current_avatar_scale
	)

	send_button.custom_minimum_size = send_size
	send_button.size = send_size
	send_button.scale = Vector2.ONE
	send_button.pivot_offset = send_size * 0.5

	var root_rect := (
		connect_scene_root.get_global_rect()
	)

	var controls_rect := (
		connect_bottom_controls.get_global_rect()
	)

	var home_position := Vector2(
		root_rect.position.x +
			(
				root_rect.size.x -
				send_button.size.x
			) *
				0.5,
		controls_rect.position.y +
			(
				controls_rect.size.y -
					send_button.size.y
			) *
				0.5,
	)

	send_button.set_as_top_level(true)

	send_button.set_meta(
		"home_pos",
		home_position,
	)

	send_button.global_position = home_position

	var should_show_send := (
		_connect_send_target_visible and
		is_instance_valid(droppedPiece) and
		isTurn and
		not spectator_mode and
		not game_over
	)

	send_button.visible = should_show_send
	send_button.disabled = not should_show_send
	send_button.modulate.a = (
		1.0
		if should_show_send
		else 0.0
	)

	_clear_connect_win_bursts()

	if (
		is_instance_valid(win_loss_label) and
		win_loss_label.visible and
		is_instance_valid(
			_connect_active_win_burst_avatar
		)
	):
		_show_connect_win_burst(
			_connect_active_win_burst_avatar,
		)

func _clear_connect_win_bursts() -> void:
	var avatars: Array[TextureButton] = [
		player_avatar_display,
		opp_avatar_display,
	]

	for avatar_button in avatars:
		if not is_instance_valid(avatar_button):
			continue

		var wrapper := avatar_button.get_node_or_null(
			CONNECT_WIN_BURST_WRAPPER_NAME,
		)

		if wrapper == null:
			continue

		avatar_button.remove_child(wrapper)
		wrapper.queue_free()


func _show_connect_win_burst(
	avatar_button: TextureButton,
) -> void:
	if not is_instance_valid(avatar_button):
		return

	_connect_active_win_burst_avatar = avatar_button

	var existing := avatar_button.get_node_or_null(
		CONNECT_WIN_BURST_WRAPPER_NAME,
	)

	if existing != null:
		avatar_button.remove_child(existing)
		existing.queue_free()

	var wrapper := Control.new()

	wrapper.name = (
		CONNECT_WIN_BURST_WRAPPER_NAME
	)

	wrapper.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	wrapper.show_behind_parent = true
	wrapper.clip_contents = false
	wrapper.size = CONNECT_BASE_AVATAR_SIZE

	wrapper.pivot_offset = (
		CONNECT_BASE_AVATAR_SIZE *
		0.5
	)

	wrapper.position = (
		avatar_button.size *
			0.5 -
		CONNECT_BASE_AVATAR_SIZE *
			0.5
	)

	wrapper.scale = Vector2.ONE * (
		_connect_current_avatar_scale
	)

	avatar_button.add_child(wrapper)

	var target := TextureButton.new()

	target.name = "ConnectBurstTarget"
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.ignore_texture_size = true
	target.clip_contents = false
	target.size = CONNECT_BASE_AVATAR_SIZE

	target.pivot_offset = (
		CONNECT_BASE_AVATAR_SIZE *
		0.5
	)

	wrapper.add_child(target)

	GameUtils._show_win_burst(target)
