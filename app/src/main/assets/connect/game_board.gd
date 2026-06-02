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
var board_state: PackedInt32Array = PackedInt32Array()
var winner : String = ""

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
func _get_dev_data() -> String:
	return '{"isYourTurn":true,"player":"2","replay":"board:1,1,1,0,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"}'
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Four In A Row"

func _on_game_ready() -> void:
	var is_dark = bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)

	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)
		if not send_button.pressed.is_connected(send_game):
			send_button.pressed.connect(send_game)

	if player == 0 or replay.is_empty():
		return

	_label_you_box()
	_hydrate_board_from_replay(replay)
	_reset_board_state()

	if not game_over:
		await get_tree().process_frame
		_set_waiting(not isTurn)
		
func _clear_board_pieces() -> void:
	_clear_last_highlight()
	_clear_pending_move()

	for c in get_children():
		if c is RigidBody2D:
			var n: String = String(c.name)
			if n.find(",") != -1:
				c.queue_free()
	_reset_board_state()

func _set_game_data(new_replay: String) -> void:
	var data: Dictionary = JSON.parse_string(new_replay)
	print("[INCOMING] Raw Data: ", data)
	isTurn		= bool(data.get("isYourTurn", false))
	replay		= String(data.get("replay", ""))

	var p1_id: String	= String(data.get("player1", ""))
	var p2_id: String	= String(data.get("player2", ""))
	turn_owner			= clamp(int(data.get("player", 1)), 1, 2)
	player				= _resolve_my_side(my_uuid, p1_id, p2_id, turn_owner, isTurn)
	spectator_mode		= (player == 0)

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
			
	if sent_tween and sent_tween.is_running():
		sent_tween.kill()
	if is_instance_valid(sent_label):
		sent_label.visible = false
		sent_label.modulate.a = 1.0
		
	_apply_player_piece_icons()
	_label_you_box()
	
	winner = String(data.get("winner", ""))

	stop_waiting_animation()
	_update_send_button_visibility(false)
	can_interact = false

	var replay_will_apply := _hydrate_board_from_replay(replay)
	if not replay_will_apply:
		_finish_replay_turn_state()

func _resolve_my_side(my_id: String, p1_id: String, p2_id: String, turn_player: int, my_turn: bool) -> int:
	if my_id != "" and p1_id != "" and p2_id != "":
		if my_id == p1_id:
			return 1
		elif my_id == p2_id:
			return 2
		else:
			return 0  # spectator/unknown

	if p1_id == "" or p2_id == "":
		if (turn_player == 2 and my_turn) or (turn_player == 1):
			return 1
		return 2

	return 0

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
		return

	if _is_board_full():
		_finalize_draw()
		return

	_refresh_turn_ui()

func _finalize_draw() -> void:
	if game_over:
		return

	game_over = true
	can_interact = false
	isTurn = false
	waitingForOpponent = false
	win_loss_state = "0"

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

func _hydrate_board_from_replay(rep: String) -> bool:
	if rep.is_empty():
		return false

	if rep == _last_applied_replay:
		return false

	_last_applied_replay = rep
	_replay_apply_id += 1
	call_deferred("_apply_replay_with_drop", rep, _replay_apply_id)
	return true

func _apply_replay_with_drop(rep: String, apply_id: int) -> void:
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

	for y in range(0, BOARD_H):
		for x in range(0, BOARD_W):
			var idx := y * BOARD_W + x
			var v: int = int(board[idx])

			if has_move and x == mx and y == my:
				v = 0

			board_state[_idx(x, y)] = v

			if v == 1 or v == 2:
				_spawn_piece_static(x, v, y)

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

	return piece


func _spawn_piece_drop_anim(x: int, pid: int, y: int, apply_id: int) -> void:
	var proto: RigidBody2D = get_node("ConnectPiece" + str(x))
	var piece: RigidBody2D = proto.duplicate()

	var target_y: float = yPoses[y]
	var start_y: float = yPoses[BOARD_H - 1] - DROP_START_OFFSET

	piece.position.y = start_y
	piece.name = "%d,%d" % [x, y]

	add_child(piece)

	var spr: Sprite2D = piece.get_child(0) as Sprite2D
	spr.texture = PIECE_TEX[_player_id_to_color(pid)]

	(piece.get_child(1) as CollisionShape2D).disabled = false
	piece.visible = true
	piece.set_freeze_enabled(true)

	var tw := create_tween()
	tw.tween_property(piece, "position:y", target_y, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	tw.tween_callback(func():
		if apply_id != _replay_apply_id:
			if is_instance_valid(piece):
				piece.queue_free()
			return

		_highlight_last(piece)
		_check_and_finalize_from_board()
		_finish_replay_turn_state()
	)

func _build_replay_payload() -> Dictionary:
	if droppedPiece == null:
		return {}

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
	print("[SEND] Payload: ", payload)
	send_game_data(JSON.stringify(payload))

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
		
func _refresh_turn_ui() -> void:
	if game_over:
		can_interact = false
		waitingForOpponent = false
		_set_waiting(false)
		return

	can_interact = (not spectator_mode) and isTurn
	waitingForOpponent = (not spectator_mode) and (not isTurn)

	print("Can Interact: ", can_interact, " | Spectator Mode: ", spectator_mode, " | Game Over: ", game_over, " | Is Turn: ", isTurn)

	if waitingForOpponent:
		_set_waiting(true)
	else:
		_set_waiting(false)

	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)
		
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

func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color("352925ff") if is_dark else Color("#d8c7c2")

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
	if board_state.is_empty():
		return "0"
	return str(board_state[_idx(x, y)])

func get_piece_y(x: int) -> int:
	for y in range(0, BOARD_H):
		if board_state[_idx(x, y)] == 0:
			return y
	return -1

func spawnPiece(x: int, color: String, y: int=-1, from_replay: bool=false) -> void:
	var proto: RigidBody2D = get_node("ConnectPiece" + str(x))
	if game_over and not from_replay:
		return
	if (not can_interact) and not from_replay:
		return

	if not from_replay and is_instance_valid(droppedPiece):
		var old_x: int = int(droppedPiece.name.get_slice(",", 0))
		if old_x == x:
			return
		_clear_pending_move()

	var piece: RigidBody2D = proto.duplicate()

	var target_y: float
	var should_animate_drop := false

	if y >= 0:
		target_y = yPoses[y]
		piece.position.y = target_y
	else:
		y = get_piece_y(x)
		if y < 0:
			return

		target_y = yPoses[y]
		piece.position.y = yPoses[BOARD_H - 1] - DROP_START_OFFSET
		should_animate_drop = true

	var pid: int = 1 if color == PIECE_YELLOW else 2
	board_state[_idx(x, y)] = pid

	add_child(piece)

	var spr: Sprite2D = piece.get_child(0) as Sprite2D
	spr.texture = PIECE_TEX[color]

	(piece.get_child(1) as CollisionShape2D).disabled = false
	piece.visible = true
	piece.set_freeze_enabled(true)
	piece.name = "%d,%d" % [x, y]

	if not from_replay:
		droppedPiece = piece

	if should_animate_drop:
		var tw := create_tween()
		piece.set_meta("drop_tween", tw)
		tw.tween_property(piece, "position:y", target_y, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tw.finished

		if not is_instance_valid(piece):
			return

		if piece.has_meta("drop_tween"):
			piece.remove_meta("drop_tween")

		if not from_replay and droppedPiece != piece:
			return

	if from_replay:
		_highlight_last(piece)
		_check_and_finalize_from_board()
		return

	if _check_and_finalize_from_board():
		_update_send_button_visibility(false)
		await get_tree().process_frame
		await send_game()
	elif _is_board_full():
		_finalize_draw()
		await get_tree().process_frame
		await send_game()
	else:
		_update_send_button_visibility(true)
		
func move_dropped_piece_to_column(new_x: int) -> void:
	if game_over or not can_interact or droppedPiece == null:
		return
	
	var old_x: int = int(droppedPiece.name.get_slice(",", 0))
	if old_x == new_x:
		return

	var new_y: int = get_piece_y(new_x)
	if new_y < 0:
		return

	var color: String = getPieceColor(droppedPiece)

	_clear_pending_move()

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
	_highlight_winning_pulse(win["coords"])

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

func _highlight_winning_pulse(cs: Array[Vector2i]) -> void:
	_pulse_nodes(_winning_nodes_from_coords(cs))

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

	win_loss_label.visible = true
	await get_tree().process_frame
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2

	var t_in: Tween = create_tween()
	t_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
func _clear_pending_move() -> void:
	if droppedPiece == null or not is_instance_valid(droppedPiece):
		droppedPiece = null
		return

	if droppedPiece.has_meta("drop_tween"):
		var tw: Tween = droppedPiece.get_meta("drop_tween") as Tween
		if tw and tw.is_running():
			tw.kill()
		droppedPiece.remove_meta("drop_tween")

	var ox: int = int(droppedPiece.name.get_slice(",", 0))
	var oy: int = int(droppedPiece.name.get_slice(",", 1))

	if ox >= 0 and ox < BOARD_W and oy >= 0 and oy < BOARD_H:
		board_state[_idx(ox, oy)] = 0

	droppedPiece.queue_free()
	droppedPiece = null
	_update_send_button_visibility(false)

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
