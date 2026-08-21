extends BaseGame
class_name CheckersBoardTop

@export var board_origin: Vector2 = Vector2(0, 0)
@export var cell_px: int = 80

@onready var player_avatar_display: Control = %PlayerAvatarDisplay
@onready var opp_avatar_display: Control = %OppAvatarDisplay
@onready var send_button: Button = %SendButton
@onready var turn_hint_label: Label = %TurnHintLabel
@onready var sent_label: Label = %SentLabel
@onready var win_loss_label: Label = %WinLossLabel
@onready var player_piece_icon: TextureRect = %PlayerPiece
@onready var opp_piece_icon: TextureRect = %OppPiece
@onready var you_label: Label = %YouLabel
@onready var background = %Background
@onready var spec_label: Label = %SpecLabel
@onready var board: TextureRect = %CheckersBoardTop
@onready var checkers_scene_root: Control = background.get_parent() as Control
@onready var checkers_main_vbox: VBoxContainer = %CheckersMainVBox
@onready var checkers_top_hud_margin: MarginContainer = %CheckersTopHudMargin
@onready var checkers_top_hud: HBoxContainer = %TopInfoHBoxContainer
@onready var checkers_board_center: CenterContainer = %CheckersBoardCenter
@onready var checkers_board_panel: PanelContainer = %CheckersBoardPanel
@onready var checkers_bottom_controls: HBoxContainer = %BottomItemHBoxContainer
@onready var checkers_bottom_controls_margin: MarginContainer = %CheckersBottomControlsMargin
@onready var player_piece_top_spacer: Control = %PlayerPieceTopSpacer
@onready var opp_piece_top_spacer: Control = %OppPieceTopSpacer
@onready var opponent_avatar_top_spacer: Control = %OppLabel

var sent_tween: Tween
var black_king_texture := preload("res://checkers/checker_black_king.png")
var red_king_texture := preload("res://checkers/checker_red_king.png")
var black_normal_texture := preload("res://checkers/checker_black.png")
var red_normal_texture := preload("res://checkers/checker_red.png")
const MUSIC_STREAM := preload("res://global/audio/checkers.ogg")

const LOG_TAG := "Checkers"
var DEBUG_CHECKERS := false

const CHECKERS_LANDSCAPE_BOARD_HEIGHT_RATIO := 0.80
const CHECKERS_REFERENCE_BOARD_SIZE := 625.0

const CHECKERS_BASE_AVATAR_SIZE := Vector2(
	96.0,
	90.0,
)

const CHECKERS_BASE_PIECE_ICON_SIZE := Vector2(
	64.0,
	64.0,
)

const CHECKERS_BASE_OPPONENT_AVATAR_SPACER := 26.0
const CHECKERS_BASE_YOU_FONT_SIZE := 21.0

const CHECKERS_BASE_MENU_BUTTON_SIZE := Vector2(
	64.0,
	64.0,
)

const CHECKERS_BASE_MENU_BUTTON_FONT_SIZE := 32.0

const CHECKERS_BASE_SEND_BUTTON_SIZE := Vector2(
	70.0,
	50.0,
)

const CHECKERS_BASE_SEND_BUTTON_FONT_SIZE := 28.0

const CHECKERS_BASE_TURN_HINT_WIDTH := 320.0
const CHECKERS_BASE_TURN_HINT_FONT_SIZE := 21.0

const CHECKERS_LANDSCAPE_AVATAR_MIN_SCALE := 2.05
const CHECKERS_LANDSCAPE_AVATAR_MAX_SCALE := 2.35

const CHECKERS_BASE_TOP_MARGIN_LEFT := 20.0
const CHECKERS_PORTRAIT_TOP_MARGIN := 40.0
const CHECKERS_LANDSCAPE_TOP_MARGIN := 10.0
const CHECKERS_BASE_BOTTOM_SIDE_MARGIN := 40.0
const CHECKERS_BASE_BOTTOM_MARGIN := 30.0

const CHECKERS_PORTRAIT_BOTTOM_HEIGHT := 120.0
const CHECKERS_BOARD_ACTION_GAP := 24.0
const CHECKERS_LANDSCAPE_BOTTOM_PADDING := 24.0

const CHECKERS_BASE_SPECTATOR_FONT_SIZE := 50.0
const CHECKERS_BASE_SPECTATOR_HALF_WIDTH := 324.0
const CHECKERS_BASE_SPECTATOR_HEIGHT := 220.0
const CHECKERS_PORTRAIT_SPECTATOR_TOP_OFFSET := 90.0

const CHECKERS_LANDSCAPE_OVERLAY_MIN_SCALE := 1.35
const CHECKERS_LANDSCAPE_OVERLAY_MAX_SCALE := 1.65

const CHECKERS_WIN_BURST_WRAPPER_NAME := (
	"CheckersResponsiveWinBurstWrapper"
)

var _checkers_layout_pending := false
var _checkers_last_viewport_size := Vector2.ZERO
var _checkers_layout_generation := 0
var _checkers_portrait_vbox_separation := 0

var _checkers_current_avatar_scale := 1.0
var _checkers_active_win_burst_avatar: TextureButton = null

func dbg(parts: Variant) -> void:
	if DEBUG_CHECKERS:
		OpLog.d(LOG_TAG, parts)

func _piece_summary() -> String:
	var red := 0
	var black := 0
	var red_kings := 0
	var black_kings := 0

	if pieces_root == null:
		return "red=0 redK=0 black=0 blackK=0"

	for child in pieces_root.get_children():
		var piece := child as Sprite2D
		if piece == null or not is_instance_valid(piece) or piece.name.begins_with("_captured_"):
			continue

		var color := get_piece_color(piece)
		if color == "red":
			red += 1
			if is_checker_king(piece):
				red_kings += 1
		elif color == "black":
			black += 1
			if is_checker_king(piece):
				black_kings += 1

	return "red=%d redK=%d black=%d blackK=%d" % [red, red_kings, black, black_kings]

var ui_piece_textures := {
	"red": preload("res://checkers/checker_red.png"),
	"black": preload("res://checkers/checker_black.png")
}

var replay: String = ""
var pieces_root: Node2D
var highlights: Array[Node] = []
var move_highlights: Dictionary[Vector2i, Sprite2D] = {}
var temp_start_pos: Vector2i = Vector2i(-1, -1)
var selected_highlight: Sprite2D
var clicked_piece: Sprite2D
var moves: Dictionary[Vector2, Sprite2D] = {}
var has_moved: bool = false
var prev_moves: Array[Vector2] = []
var prev_jumps: Array[Dictionary] = []
var chain_jump_piece: Sprite2D = null
var checking_for_jumps: bool = false
var must_jump: bool = false
var rule_mandatory_jumps: bool = true
var jumping_pieces: Array[Sprite2D] = []
var game_over: bool = false
var has_connected: bool = false
var mode: String = "n"
var input_locked: bool = false
var replay_locked: bool = false
var isTurn: bool = false
var waitingForOpponent: bool = false
var player: int = 0
var turn_owner: int = 1
var my_player: String = ""
var suppress_next_click: bool = false

var recovery_turn_num: String = ""
var recovery_snapshot_pending := false
var recovery_snapshot_progress := ""
var recovery_restore_in_progress := false
var recovery_loaded := false

@export_range(0.3, 1.0, 0.01) var piece_fill: float = 0.78
@export var board_inset: int = 0

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
func _get_dev_data() -> String:
	return '{"isYourTurn":true,"myPlayerId":"p2uid","player":"1","player1":"p1uid","player2":"p2uid","sender":"p1uid","mode":"n","replay":"board:0,0,0,0,0,0,0,0,2,0,0,0,0,0,3,0,0,2,0,0,0,0,0,0,0,0,2,0,3,0,0,0,0,0,0,4,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,2,0,0,0,2,0,0,0,0,0,0,0,0|board:0,0,0,0,0,0,0,0,2,0,0,0,0,0,3,0,0,2,0,0,0,0,0,0,0,0,2,0,3,0,0,0,0,0,0,4,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,2,0,0,0,2,0,0,0,0,0,0,0,0"}'

func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)
	if is_instance_valid(board):
		board.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		board.mouse_filter = Control.MOUSE_FILTER_STOP
		if not board.is_connected("resized", Callable(self, "_on_board_resized")):
			board.resized.connect(_on_board_resized)
		if not board.gui_input.is_connected(Callable(self, "_on_board_gui_input")):
			board.gui_input.connect(_on_board_gui_input)
	_recalculate_board_layout_from_board()

	pieces_root = Node2D.new()
	pieces_root.name = "PiecesRoot"
	add_child(pieces_root)
	if is_instance_valid(send_button):
		send_button.disabled = true
		send_button.visible = false
		send_button.modulate.a = 0
		send_button.scale = Vector2(1.0, 1.0)
		if not send_button.pressed.is_connected(Callable(self, "_on_send_pressed")):
			send_button.pressed.connect(_on_send_pressed)
	
	if is_instance_valid(turn_hint_label):
		turn_hint_label.visible = false
		turn_hint_label.modulate.a = 0.0
		turn_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_initialize_checkers_responsive_layout()
	if player == 0 or replay == "":
		return

	var playerBox := get_node_or_null("Player" + str(player) + "Box")
	if playerBox != null and not spectator_mode:
		playerBox.get_child(0).set_text("[center]You[/center]")	

func _tween_for(target: Object) -> Tween:
	var tw := get_tree().create_tween()
	if is_instance_valid(target):
		tw.bind_node(target)
	return tw
			
func _await_all_tweens(arr: Array[Tween]) -> void:
	for t in arr:
		if t and t.is_running():
			await t.finished
			
func _get_piece_pos(piece: Sprite2D) -> Vector2i:
	if piece == null or not is_instance_valid(piece):
		return Vector2i(-1, -1)
	var parts = piece.name.split(",")
	if parts.size() == 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(-1, -1)

func _select_piece(piece: Sprite2D) -> void:
	if piece == null or not is_instance_valid(piece):
		return

	if not check_player(piece):
		return

	if chain_jump_piece != null and piece != chain_jump_piece:
		return

	clear_highlights()
	clicked_piece = piece
	moves.clear()

	var p_pos := _get_piece_pos(piece)
	if p_pos == Vector2i(-1, -1):
		clicked_piece = null
		return

	_show_selected_highlight_at(p_pos.x, p_pos.y)

	var force_jumps_only: bool = (chain_jump_piece != null)
	gen_moves(force_jumps_only)

	if moves.size() == 0:
		clicked_piece = null
		_clear_selected_highlight()
		
func _apply_board_orientation() -> void:
	if not is_instance_valid(board):
		return
	if board.size == Vector2.ZERO:
		call_deferred("_apply_board_orientation")
		return
	board.pivot_offset = board.size / 2.0
	board.rotation_degrees = 0.0 
	
func _can_accept_board_input() -> bool:
	return (
		not _settings_open
		and not _rules_open
		and not input_locked
		and not replay_locked
		and not spectator_mode
		and not waitingForOpponent
		and isTurn
		and not game_over
	)

func _apply_piece_scale(s: Sprite2D) -> void:
	if s.texture == null:
		return
	var tex_size: Vector2i = s.texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	var target_px: float = float(cell_px) * piece_fill
	var sx: float = target_px / float(tex_size.x)
	var sy: float = target_px / float(tex_size.y)
	var scale_factor: float = minf(sx, sy)
	s.scale = Vector2(scale_factor, scale_factor)
	s.centered = true

func _view_y(y: int) -> int:
	return (7 - y) if (player == 2 and not spectator_mode) else y

func _cell_pos(lx: int, ly: int) -> Vector2:
	var gx := lx if (player == 2 and not spectator_mode) else (7 - lx)
	var gy := (7 - ly) if (player == 2 and not spectator_mode) else ly
	return board_origin + Vector2((gx + 0.5) * float(cell_px), (gy + 0.5) * float(cell_px))


func _apply_player_piece_icons() -> void:
	if not is_instance_valid(player_piece_icon) or not is_instance_valid(opp_piece_icon):
		return
	var my_color: String = "red" if player == 1 else "black"
	var opp_color: String = "black" if player == 1 else "red"
	player_piece_icon.texture = ui_piece_textures.get(my_color, null)
	opp_piece_icon.texture = ui_piece_textures.get(opp_color, null)
	if is_instance_valid(you_label):
		you_label.text = "You"
		you_label.modulate.a = 1.0 if not spectator_mode else 0.0

func _get_nth_board_str(src: String, n: int) -> String:
	var i := 0
	for elem in src.split("|"):
		var p := elem.split(":")
		if p.size() >= 2 and p[0] == "board":
			if i == n:
				return p[1]
			i += 1
	return ""

func _current_board_string() -> String:
	var board_values: Array[String] = []
	board_values.resize(64)

	for k in range(64):
		board_values[k] = "0"

	for ly in range(8):
		for lx in range(8):
			var piece := get_node_or_null("PiecesRoot/%d,%d" % [lx, ly]) as Sprite2D
			if piece != null:
				var color := get_piece_color(piece)
				var v := "0"

				if color == "red":
					v = "3" if is_checker_king(piece) else "1"
				elif color == "black":
					v = "4" if is_checker_king(piece) else "2"

				var A := _logical_to_abs(lx, ly)
				var idx := A.y * 8 + A.x

				if idx >= 0 and idx < 64:
					board_values[idx] = v

	return ",".join(board_values)

func _on_send_pressed() -> void:
	if _settings_open or _rules_open:
		return

	if input_locked:
		dbg("send_pressed blocked input_locked")
		return

	if not has_moved or prev_moves.size() < 2:
		dbg(["send_pressed blocked hasMoved=", has_moved, " prevMoves=", prev_moves.size()])
		return

	OpLog.i(LOG_TAG, ["send_pressed moves=", floori(float(prev_moves.size()) / 2.0)])

	isTurn = false
	_animate_send_button(false)
	call_deferred("send_game_checkers")

func send_game_checkers() -> void:
	if prev_moves.size() < 2:
		OpLog.w(LOG_TAG, ["send_game_checkers skipped prevMoves=", prev_moves.size()])
		return

	var steps: Array = []
	for i in range(0, prev_moves.size(), 2):
		var p1: Vector2 = prev_moves[i]
		var p2: Vector2 = prev_moves[i + 1]
		var A1: Vector2i = _logical_to_abs(int(p1.x), int(p1.y))
		var A2: Vector2i = _logical_to_abs(int(p2.x), int(p2.y))
		var kind: String = "attack" if absi(int(p1.x - p2.x)) > 1 else "move"
		steps.append({"kind": kind, "A1": A1, "A2": A2})

	var pre_board_str: String = _get_nth_board_str(replay, 1)
	if pre_board_str == "":
		pre_board_str = _get_nth_board_str(replay, 0)

	for y in range(8):
		for x in range(8):
			var piece := get_node_or_null("PiecesRoot/%d,%d" % [x, y]) as Sprite2D
			if piece == null:
				continue

			var col: String = get_piece_color(piece)
			if col == "unknown" or is_checker_king(piece):
				continue

			if col == "red" and y == 0:
				set_checker_king(piece, "red")
			elif col == "black" and y == 7:
				set_checker_king(piece, "black")

	var post_board_str: String = _current_board_string()

	var red_left := false
	var black_left := false

	for yy in range(8):
		for xx in range(8):
			var pc := get_node_or_null("PiecesRoot/%d,%d" % [xx, yy]) as Sprite2D
			if pc == null:
				continue

			var c: String = get_piece_color(pc)
			if c == "red":
				red_left = true
			elif c == "black":
				black_left = true

	var game_is_over: bool = (red_left and not black_left) or (black_left and not red_left)

	var parts: Array[String] = []
	if pre_board_str != "":
		parts.append("board:" + pre_board_str)

	for s in steps:
		var a1: Vector2i = s["A1"]
		var a2: Vector2i = s["A2"]
		parts.append("%s:%d,%d,%d,%d" % [String(s["kind"]), a1.x, a1.y, a2.x, a2.y])

	parts.append("board:" + post_board_str)

	var new_replay: String = String("|").join(parts)
	var payload: Dictionary = {"replay": new_replay}
	var avatar_key: String = "avatar1" if player == 1 else "avatar2"

	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	var wl: String = check_win_loss()
	if wl != "":
		payload["winner"] = my_player + "|" + ("1" if wl == "win" else "-1")

	var ended_game: bool = game_is_over or wl != ""
	var out_json: String = JSON.stringify(payload)

	OpLog.event(LOG_TAG, ["send_game_out steps=", steps.size(), " winLoss=", wl, " gameOver=", game_is_over, " raw=", out_json])
	send_game_data(out_json)

	clear_highlights()
	clicked_piece = null
	has_moved = false
	moves.clear()
	chain_jump_piece = null
	prev_jumps.clear()
	prev_moves.clear()

	if ended_game:
		game_over = true
		stop_waiting_animation()

		if sent_tween != null and sent_tween.is_running():
			sent_tween.kill()

		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0

		if is_instance_valid(send_button):
			send_button.visible = false
			send_button.disabled = true

		if is_instance_valid(turn_hint_label):
			turn_hint_label.visible = false
			turn_hint_label.modulate.a = 0.0

		if wl != "":
			await game_over_visual(wl)

		return

	play_sent_animation()

func _on_board_resized() -> void:
	_recalculate_board_layout_from_board()
	_apply_board_orientation()

	if is_instance_valid(pieces_root):
		for child in pieces_root.get_children():
			var piece := child as Sprite2D

			if not is_instance_valid(piece):
				continue

			var piece_position := _get_piece_pos(
				piece,
			)

			if piece_position == Vector2i(-1, -1):
				continue

			_apply_piece_scale(piece)

			piece.position = _cell_pos(
				piece_position.x,
				piece_position.y,
			)

	for key in move_highlights.keys():
		var move_highlight := (
			move_highlights[key] as Sprite2D
		)

		if not is_instance_valid(move_highlight):
			continue

		var target_px := float(cell_px) * 0.9

		var scale_factor := minf(
			target_px /
				float(
					move_highlight.texture.get_width()
				),
			target_px /
				float(
					move_highlight.texture.get_height()
				),
		)

		move_highlight.scale = Vector2.ONE * (
			scale_factor
		)

		move_highlight.position = _cell_pos(
			key.x,
			key.y,
		)

	if (
		is_instance_valid(selected_highlight) and
		selected_highlight.visible and
		is_instance_valid(clicked_piece)
	):
		var selected_position := (
			_get_piece_pos(clicked_piece)
		)

		if selected_position != Vector2i(-1, -1):
			_show_selected_highlight_at(
				selected_position.x,
				selected_position.y,
			)

func _spawn_piece(val: String, lx: int, ly: int) -> Sprite2D:
	var s := Sprite2D.new()
	var color: String = ""
	var is_king: bool = false
	
	match val:
		"1":
			color = "red"
			is_king = false
		"2":
			color = "black"
			is_king = false
		"3":
			color = "red"
			is_king = true
		"4":
			color = "black"
			is_king = true
		_:
			s.queue_free()
			return null

	if color == "red":
		s.texture = red_king_texture if is_king else red_normal_texture
	else:
		s.texture = black_king_texture if is_king else black_normal_texture

	_apply_piece_scale(s)
	s.position = _cell_pos(lx, ly)
	s.name = "%d,%d" % [lx, ly]
	s.z_as_relative = false
	s.z_index = 2
	s.visible = true
	pieces_root.add_child(s)
	return s

func _recalculate_board_layout_from_board() -> void:
	if board == null:
		return
	var board_rect: Rect2 = _get_board_draw_rect()
	var draw_pos: Vector2 = board_rect.position
	var draw_size: Vector2 = board_rect.size
	var square_side: float = min(draw_size.x, draw_size.y) - float(board_inset) * 2.0
	var px: int = int(floor(square_side / 8.0))
	px = max(px, 1)
	cell_px = px
	var total_grid_px: Vector2 = Vector2(px * 8, px * 8)
	board_origin = draw_pos \
		+ Vector2((draw_size.x - total_grid_px.x) * 0.5, (draw_size.y - total_grid_px.y) * 0.5) \
		+ Vector2(board_inset, board_inset)

func _prepare_scene_once() -> void:
	_recalculate_board_layout_from_board()
	if is_instance_valid(board):
		if not board.is_connected("resized", Callable(self, "_on_board_resized")):
			board.resized.connect(_on_board_resized)
	if pieces_root == null:
		pieces_root = Node2D.new()
		pieces_root.name = "PiecesRoot"
		add_child(pieces_root)

func _clear_pieces() -> void:
	if pieces_root:
		for c in pieces_root.get_children():
			c.queue_free()
	highlights.clear()
	prev_moves.clear()
	prev_jumps.clear()
	clicked_piece = null
	has_moved = false
	chain_jump_piece = null

func _board_value_side(value: String) -> int:
	match value:
		"1", "3":
			return 1 # red
		"2", "4":
			return 2 # black
		_:
			return 0

func _infer_single_move_from_boards(
	initial_board: PackedStringArray,
	final_board: PackedStringArray,
) -> String:
	if initial_board.size() < 64 or final_board.size() < 64:
		return ""

	var candidates: Array[Dictionary] = []

	for side in [1, 2]:
		var removed: Array[int] = []
		var added: Array[int] = []

		for idx in range(64):
			var before := String(initial_board[idx])
			var after := String(final_board[idx])

			if before == after:
				continue

			var before_side := _board_value_side(before)
			var after_side := _board_value_side(after)

			if before_side == side and after_side != side:
				removed.append(idx)

			if after_side == side and before_side != side:
				added.append(idx)

		if removed.size() == 1 and added.size() == 1:
			candidates.append({
				"from": removed[0],
				"to": added[0],
			})

	if candidates.size() != 1:
		return ""

	var candidate: Dictionary = candidates[0]

	var from_idx := int(candidate["from"])
	var to_idx := int(candidate["to"])

	var from_x: int = from_idx % 8
	var from_y: int = floori(float(from_idx) / 8.0)
	var to_x: int = to_idx % 8
	var to_y: int = floori(float(to_idx) / 8.0)

	var dx: int = absi(from_x - to_x)
	var dy: int = absi(from_y - to_y)

	var kind: String = ""

	if dx == 1 and dy == 1:
		kind = "move"
	elif dx == 2 and dy == 2:
		kind = "attack"
	else:
		return ""

	return "%s:%d,%d,%d,%d" % [
		kind,
		from_x,
		from_y,
		to_x,
		to_y,
	]

func _apply_board_snapshot(
	board_values: PackedStringArray,
) -> void:
	if board_values.size() < 64:
		OpLog.w(
			LOG_TAG,
			[
				"apply_board_snapshot invalid size=",
				board_values.size(),
			],
		)
		return

	_prepare_scene_once()
	_clear_pieces()

	selected_highlight = null

	await get_tree().process_frame
	await get_tree().process_frame

	for ay in range(8):
		for ax in range(8):
			var idx := ay * 8 + ax
			var value := String(board_values[idx])

			if value == "0":
				continue

			var logical := _abs_to_logical(
				ax,
				ay,
			)

			_spawn_piece(
				value,
				logical.x,
				logical.y,
			)

	await get_tree().process_frame

func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color(0.08, 0.08, 0.08) if is_dark else Color("#e5e5e5")

func _initialize_checkers_responsive_layout() -> void:
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
			internal_preview.pivot_offset = Vector2(
				48.0,
				140.0,
			)

	_checkers_portrait_vbox_separation = (
		checkers_main_vbox.get_theme_constant(
			"separation",
		)
	)

	var viewport := get_viewport()

	if viewport == null:
		return

	if not viewport.size_changed.is_connected(
		_schedule_checkers_responsive_layout,
	):
		viewport.size_changed.connect(
			_schedule_checkers_responsive_layout,
		)

	_schedule_checkers_responsive_layout(true)


func _schedule_checkers_responsive_layout(
	force: bool = false,
) -> void:
	if force:
		_checkers_last_viewport_size = Vector2.ZERO

	if _checkers_layout_pending:
		return

	_checkers_layout_pending = true

	call_deferred(
		"_apply_checkers_responsive_layout",
	)

func _apply_checkers_responsive_layout() -> void:
	_checkers_layout_pending = false

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
		_checkers_last_viewport_size,
	):
		return

	_checkers_last_viewport_size = viewport_size

	var is_portrait := (
		viewport_size.y >=
		viewport_size.x
	)

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
			CHECKERS_LANDSCAPE_AVATAR_MIN_SCALE,
			CHECKERS_LANDSCAPE_AVATAR_MAX_SCALE,
		)

	# ---------------------------------------------------------
	# Scene hierarchy
	# ---------------------------------------------------------

	if not is_portrait:
		if (
			checkers_top_hud_margin.get_parent() !=
			checkers_scene_root
		):
			checkers_top_hud_margin.reparent(
				checkers_scene_root,
				false,
			)

		checkers_main_vbox.move_child(
			checkers_board_center,
			0,
		)

		checkers_main_vbox.move_child(
			checkers_bottom_controls,
			1,
		)

		checkers_main_vbox.alignment = (
			BoxContainer.ALIGNMENT_CENTER
		)

		checkers_top_hud_margin.z_index = 20
		spec_label.z_index = 30
	else:
		if (
			checkers_top_hud_margin.get_parent() !=
			checkers_main_vbox
		):
			checkers_top_hud_margin.reparent(
				checkers_main_vbox,
				false,
			)

		checkers_main_vbox.move_child(
			checkers_top_hud_margin,
			0,
		)

		checkers_main_vbox.move_child(
			checkers_board_center,
			1,
		)

		checkers_main_vbox.move_child(
			checkers_bottom_controls,
			2,
		)

		checkers_main_vbox.alignment = (
			BoxContainer.ALIGNMENT_BEGIN
		)

		checkers_top_hud_margin.z_index = 0

		checkers_top_hud_margin.set_anchors_preset(
			Control.PRESET_TOP_LEFT,
			false,
		)

		checkers_top_hud_margin.offset_left = 0.0
		checkers_top_hud_margin.offset_top = 0.0
		checkers_top_hud_margin.offset_right = 0.0
		checkers_top_hud_margin.offset_bottom = 0.0

		checkers_board_center.set_anchors_preset(
			Control.PRESET_TOP_LEFT,
			false,
		)

		checkers_board_center.offset_left = 0.0
		checkers_board_center.offset_top = 0.0
		checkers_board_center.offset_right = 0.0
		checkers_board_center.offset_bottom = 0.0

		checkers_bottom_controls.set_anchors_preset(
			Control.PRESET_TOP_LEFT,
			false,
		)

		checkers_bottom_controls.offset_left = 0.0
		checkers_bottom_controls.offset_top = 0.0
		checkers_bottom_controls.offset_right = 0.0
		checkers_bottom_controls.offset_bottom = 0.0

	# ---------------------------------------------------------
	# Board size
	# ---------------------------------------------------------

	var board_display_size := (
		CHECKERS_REFERENCE_BOARD_SIZE
	)

	if not is_portrait:
		var target_stack_height := floorf(
			viewport_size.y *
			CHECKERS_LANDSCAPE_BOARD_HEIGHT_RATIO
		)

		var action_height := (
			maxf(
				CHECKERS_BASE_MENU_BUTTON_SIZE.y,
				CHECKERS_BASE_SEND_BUTTON_SIZE.y,
			) *
			action_scale_hint +
			CHECKERS_LANDSCAPE_BOTTOM_PADDING
		)

		var available_board_height := maxf(
			target_stack_height -
				action_height -
				CHECKERS_BOARD_ACTION_GAP,
			1.0,
		)

		var available_board_width := maxf(
			viewport_size.x -
				CHECKERS_BASE_BOTTOM_SIDE_MARGIN *
					2.0,
			1.0,
		)

		board_display_size = floorf(
			minf(
				available_board_height,
				available_board_width,
			)
		)

	board_display_size = maxf(
		board_display_size,
		1.0,
	)

	board.custom_minimum_size = Vector2(
		board_display_size,
		board_display_size,
	)

	checkers_board_panel.custom_minimum_size = Vector2(
		board_display_size,
		board_display_size,
	)

	checkers_board_center.custom_minimum_size = Vector2(
		board_display_size,
		board_display_size,
	)

	var content_scale := clampf(
		board_display_size /
			CHECKERS_REFERENCE_BOARD_SIZE,
		0.5,
		2.0,
	)

	# ---------------------------------------------------------
	# Avatars and checker trays
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
			CHECKERS_LANDSCAPE_AVATAR_MIN_SCALE,
			CHECKERS_LANDSCAPE_AVATAR_MAX_SCALE,
		)

	_checkers_current_avatar_scale = avatar_scale

	var avatar_size := (
		CHECKERS_BASE_AVATAR_SIZE *
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

		var internal_preview := (
			avatar_button.get_node_or_null(
				"SubViewportContainer",
			) as SubViewportContainer
		)

		if internal_preview != null:
			internal_preview.scale = (
				Vector2.ONE *
				avatar_scale
			)

		avatar_button.queue_redraw()

	var piece_icon_size := CHECKERS_BASE_PIECE_ICON_SIZE * avatar_scale

	player_piece_icon.custom_minimum_size = piece_icon_size
	opp_piece_icon.custom_minimum_size = piece_icon_size
	player_piece_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	opp_piece_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	player_piece_top_spacer.custom_minimum_size = Vector2.ZERO
	opp_piece_top_spacer.custom_minimum_size = Vector2.ZERO
	opponent_avatar_top_spacer.custom_minimum_size = Vector2(0.0, CHECKERS_BASE_OPPONENT_AVATAR_SPACER * avatar_scale)

	you_label.add_theme_font_size_override(
		"font_size",
		maxi(
			roundi(
				CHECKERS_BASE_YOU_FONT_SIZE *
					avatar_scale
			),
			1,
		),
	)

	# ---------------------------------------------------------
	# Rules, Settings, and Send
	# ---------------------------------------------------------

	var menu_size := (
		CHECKERS_BASE_MENU_BUTTON_SIZE *
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
					CHECKERS_BASE_MENU_BUTTON_FONT_SIZE *
						avatar_scale
				),
				1,
			),
		)

	var send_size := (
		CHECKERS_BASE_SEND_BUTTON_SIZE *
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
				CHECKERS_BASE_SEND_BUTTON_FONT_SIZE *
					avatar_scale
			),
			1,
		),
	)

	send_button.pivot_offset = (
		send_size *
		0.5
	)
	
	if is_instance_valid(turn_hint_label):
		var hint_width: float = minf(
			CHECKERS_BASE_TURN_HINT_WIDTH *
				avatar_scale,
			maxf(
				checkers_scene_root.size.x - 32.0,
				120.0,
			),
		)

		var hint_size := Vector2(
			hint_width,
			send_size.y,
		)

		turn_hint_label.custom_minimum_size = hint_size
		turn_hint_label.size = hint_size

		turn_hint_label.add_theme_font_size_override(
			"font_size",
			maxi(
				roundi(
					CHECKERS_BASE_TURN_HINT_FONT_SIZE *
						avatar_scale
				),
				1,
			),
		)

	# ---------------------------------------------------------
	# Landscape positioning or portrait restoration
	# ---------------------------------------------------------

	if not is_portrait:
		var side_margin := (
			CHECKERS_BASE_TOP_MARGIN_LEFT *
			avatar_scale
		)

		var top_margin := CHECKERS_LANDSCAPE_TOP_MARGIN * avatar_scale

		checkers_top_hud_margin.add_theme_constant_override(
			"margin_left",
			roundi(side_margin),
		)

		checkers_top_hud_margin.add_theme_constant_override(
			"margin_top",
			roundi(top_margin),
		)

		checkers_top_hud_margin.add_theme_constant_override(
			"margin_right",
			roundi(side_margin),
		)

		checkers_top_hud_margin.set_anchors_preset(
			Control.PRESET_TOP_WIDE,
			false,
		)

		var avatar_stack_height: float = (CHECKERS_BASE_AVATAR_SIZE.y + maxf(CHECKERS_BASE_YOU_FONT_SIZE, CHECKERS_BASE_OPPONENT_AVATAR_SPACER)) * avatar_scale
		var piece_stack_height: float = CHECKERS_BASE_PIECE_ICON_SIZE.y * avatar_scale
		var top_hud_height: float = maxf(avatar_stack_height, piece_stack_height) + top_margin

		checkers_top_hud_margin.offset_left = 0.0
		checkers_top_hud_margin.offset_top = 0.0
		checkers_top_hud_margin.offset_right = 0.0
		checkers_top_hud_margin.offset_bottom = (
			top_hud_height
		)

		var bottom_side_margin := (
			CHECKERS_BASE_BOTTOM_SIDE_MARGIN *
			avatar_scale
		) 

		var bottom_margin := (
			CHECKERS_BASE_BOTTOM_MARGIN *
			avatar_scale
		)

		checkers_bottom_controls_margin.add_theme_constant_override(
			"margin_left",
			roundi(bottom_side_margin),
		)

		checkers_bottom_controls_margin.add_theme_constant_override(
			"margin_right",
			roundi(bottom_side_margin),
		)

		checkers_bottom_controls_margin.add_theme_constant_override(
			"margin_bottom",
			roundi(bottom_margin),
		)

		var action_height := (
			maxf(
				CHECKERS_BASE_MENU_BUTTON_SIZE.y,
				CHECKERS_BASE_SEND_BUTTON_SIZE.y,
			) *
			avatar_scale +
			CHECKERS_LANDSCAPE_BOTTOM_PADDING
		)

		checkers_bottom_controls.custom_minimum_size = Vector2(
			0.0,
			action_height,
		)

		checkers_main_vbox.add_theme_constant_override(
			"separation",
			roundi(
				CHECKERS_BOARD_ACTION_GAP,
			),
		)
	else:
		checkers_top_hud_margin.add_theme_constant_override(
			"margin_left",
			roundi(
				CHECKERS_BASE_TOP_MARGIN_LEFT,
			),
		)

		checkers_top_hud_margin.add_theme_constant_override("margin_top", roundi(CHECKERS_PORTRAIT_TOP_MARGIN))

		checkers_top_hud_margin.add_theme_constant_override(
			"margin_right",
			roundi(
				CHECKERS_BASE_TOP_MARGIN_LEFT,
			),
		)

		checkers_bottom_controls_margin.add_theme_constant_override(
			"margin_left",
			roundi(
				CHECKERS_BASE_BOTTOM_SIDE_MARGIN,
			),
		)

		checkers_bottom_controls_margin.add_theme_constant_override(
			"margin_right",
			roundi(
				CHECKERS_BASE_BOTTOM_SIDE_MARGIN,
			),
		)

		checkers_bottom_controls_margin.add_theme_constant_override(
			"margin_bottom",
			roundi(
				CHECKERS_BASE_BOTTOM_MARGIN,
			),
		)

		checkers_bottom_controls.custom_minimum_size = Vector2(
			0.0,
			CHECKERS_PORTRAIT_BOTTOM_HEIGHT,
		)

		checkers_main_vbox.add_theme_constant_override(
			"separation",
			_checkers_portrait_vbox_separation,
		)

	# ---------------------------------------------------------
	# Spectator label
	# ---------------------------------------------------------

	var overlay_scale := 1.0

	if not is_portrait:
		overlay_scale = clampf(
			content_scale,
			CHECKERS_LANDSCAPE_OVERLAY_MIN_SCALE,
			CHECKERS_LANDSCAPE_OVERLAY_MAX_SCALE,
		)

	var spectator_top_offset := (
		CHECKERS_PORTRAIT_SPECTATOR_TOP_OFFSET
		if is_portrait
		else 0.0
	)

	spec_label.set_anchors_preset(
		Control.PRESET_CENTER_TOP,
		false,
	)

	spec_label.offset_left = (
		-CHECKERS_BASE_SPECTATOR_HALF_WIDTH *
			overlay_scale
	)

	spec_label.offset_right = (
		CHECKERS_BASE_SPECTATOR_HALF_WIDTH *
			overlay_scale
	)

	spec_label.offset_top = spectator_top_offset

	spec_label.offset_bottom = (
		spectator_top_offset +
		CHECKERS_BASE_SPECTATOR_HEIGHT *
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
				CHECKERS_BASE_SPECTATOR_FONT_SIZE *
					overlay_scale
			),
			1,
		),
	)

	board.queue_redraw()
	checkers_board_panel.queue_sort()
	checkers_board_center.queue_sort()
	checkers_top_hud.queue_sort()
	checkers_main_vbox.queue_sort()

	_checkers_layout_generation += 1

	call_deferred(
		"_finish_checkers_responsive_layout",
		_checkers_layout_generation,
	)

func _finish_checkers_responsive_layout(
	layout_generation: int,
) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if (
		not is_inside_tree() or
		layout_generation !=
			_checkers_layout_generation
	):
		return

	_on_board_resized()

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
		CHECKERS_BASE_SEND_BUTTON_SIZE *
		_checkers_current_avatar_scale
	)

	send_button.custom_minimum_size = send_size
	send_button.size = send_size
	send_button.scale = Vector2.ONE
	send_button.pivot_offset = send_size * 0.5

	var root_rect := (
		checkers_scene_root.get_global_rect()
	)

	var controls_rect := (
		checkers_bottom_controls.get_global_rect()
	)

	var home_position := Vector2(
		(
			root_rect.size.x -
			send_button.size.x
		) *
		0.5,
		controls_rect.position.y -
			root_rect.position.y +
		(
			controls_rect.size.y -
			send_button.size.y
		) *
		0.5,
	)

	send_button.set_meta(
		"sb_home_pos",
		home_position,
	)

	send_button.position = home_position

	if is_instance_valid(turn_hint_label):
		var hint_home_position := Vector2(
			(
				root_rect.size.x -
				turn_hint_label.size.x
			) *
			0.5,
			home_position.y +
				(
					send_button.size.y -
						turn_hint_label.size.y
				) *
				0.5,
		)

		turn_hint_label.set_meta(
			"th_home_pos",
			hint_home_position,
		)

		turn_hint_label.position = hint_home_position

	var should_show_send := (
		has_moved and
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

	if is_instance_valid(turn_hint_label):
		var should_show_hint := (
			not has_moved and
			isTurn and
			not waitingForOpponent and
			not spectator_mode and
			not game_over
		)

		turn_hint_label.text = _turn_hint_text()
		turn_hint_label.visible = should_show_hint
		turn_hint_label.modulate.a = (
			1.0
			if should_show_hint
			else 0.0
		)

	_clear_checkers_win_bursts()

	if (
		is_instance_valid(win_loss_label) and
		win_loss_label.visible and
		is_instance_valid(
			_checkers_active_win_burst_avatar
		)
	):
		_show_checkers_win_burst(
			_checkers_active_win_burst_avatar,
		)

func _visual_to_logical(gx: int, gy: int) -> Vector2i:
	var lx := gx if (player == 2 and not spectator_mode) else (7 - gx)
	var ly := (7 - gy) if (player == 2 and not spectator_mode) else gy
	return Vector2i(lx, ly)

func _turn_hint_text() -> String:
	if rule_mandatory_jumps and must_jump:
		return "Capture your opponent's piece"

	return "Move one of your pieces"


func _animate_turn_hint(
	should_show: bool,
) -> void:
	if not is_instance_valid(turn_hint_label):
		return

	turn_hint_label.text = _turn_hint_text()

	if not turn_hint_label.has_meta("th_home_pos"):
		turn_hint_label.set_meta(
			"th_home_pos",
			turn_hint_label.position,
		)

	var home_pos: Vector2 = (
		turn_hint_label.get_meta("th_home_pos")
	)

	var off_pos := Vector2(
		home_pos.x,
		checkers_scene_root.size.y +
			turn_hint_label.size.y +
			24.0,
	)

	if turn_hint_label.has_meta("th_tween"):
		var old_tween: Variant = (
			turn_hint_label.get_meta("th_tween")
		)

		if (
			old_tween is Tween and
			(old_tween as Tween).is_running()
		):
			(old_tween as Tween).kill()

	var tween := create_tween()

	turn_hint_label.set_meta(
		"th_tween",
		tween,
	)

	if should_show:
		turn_hint_label.visible = true
		turn_hint_label.position = off_pos
		turn_hint_label.modulate.a = 0.0

		tween.tween_property(
			turn_hint_label,
			"position",
			home_pos,
			0.35,
		).set_ease(
			Tween.EASE_OUT,
		).set_trans(
			Tween.TRANS_QUAD,
		)

		tween.parallel().tween_property(
			turn_hint_label,
			"modulate:a",
			1.0,
			0.35,
		)
	else:
		if not turn_hint_label.visible:
			turn_hint_label.position = home_pos
			turn_hint_label.modulate.a = 0.0
			return

		tween.tween_property(
			turn_hint_label,
			"position",
			off_pos,
			0.20,
		).set_ease(
			Tween.EASE_IN,
		).set_trans(
			Tween.TRANS_QUAD,
		)

		tween.parallel().tween_property(
			turn_hint_label,
			"modulate:a",
			0.0,
			0.20,
		)

		tween.tween_callback(
			func() -> void:
				if not is_instance_valid(
					turn_hint_label
				):
					return

				turn_hint_label.visible = false
				turn_hint_label.position = home_pos
		)

func _animate_send_button(
	should_show: bool,
) -> void:
	if not is_instance_valid(send_button):
		return

	if not send_button.has_meta("sb_home_pos"):
		send_button.set_meta(
			"sb_home_pos",
			send_button.position,
		)

	var home_pos: Vector2 = (
		send_button.get_meta("sb_home_pos")
	)

	var off_pos := Vector2(
		home_pos.x,
		checkers_scene_root.size.y +
			send_button.size.y +
			24.0,
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

	var tween := create_tween()

	send_button.set_meta(
		"sb_tween",
		tween,
	)

	if should_show:
		send_button.visible = true
		send_button.disabled = false
		send_button.position = off_pos
		send_button.modulate.a = 0.0

		tween.tween_property(
			send_button,
			"position",
			home_pos,
			0.35,
		).set_ease(
			Tween.EASE_OUT,
		).set_trans(
			Tween.TRANS_QUAD,
		)

		tween.parallel().tween_property(
			send_button,
			"modulate:a",
			1.0,
			0.35,
		)
	else:
		send_button.disabled = true

		tween.tween_property(
			send_button,
			"position",
			off_pos,
			0.25,
		).set_ease(
			Tween.EASE_IN,
		).set_trans(
			Tween.TRANS_QUAD,
		)

		tween.parallel().tween_property(
			send_button,
			"modulate:a",
			0.0,
			0.25,
		)

		tween.tween_callback(
			func() -> void:
				if not is_instance_valid(send_button):
					return

				send_button.visible = false
				send_button.position = home_pos
		)

func _make_move_highlight_node() -> Sprite2D:
	var spr := Sprite2D.new()
	spr.name = "MoveHighlight"
	spr.centered = true
	spr.z_as_relative = false
	spr.z_index = 1

	var grad := Gradient.new()
	grad.add_point(0.00, Color(1, 1, 1, 0.00))
	grad.add_point(0.35, Color(1, 1, 1, 0.18))
	grad.add_point(0.75, Color(1, 1, 1, 0.32))
	grad.add_point(1.00, Color(1, 1, 1, 0.00))

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 512
	tex.height = 512
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.25, 0.5)

	spr.texture = tex
	_start_pulse(spr, 0.10, 0.60, 1.2)
	return spr
	
func _post_replay_ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_scan_row(3)
	_scan_row(4)
	_scan_row(5)

	_compute_mandatory_jumps()
	_update_send_button()

	if rule_mandatory_jumps and must_jump and chain_jump_piece == null:
		_show_mandatory_jump_previews()

func _add_move_highlight(lx: int, ly: int) -> void:
	var key := Vector2i(lx, ly)
	if move_highlights.has(key):
		var existing: Sprite2D = move_highlights[key]
		if is_instance_valid(existing):
			existing.position = _cell_pos(lx, ly)
			existing.visible = true
			return

	var spr := _make_move_highlight_node()
	var target_px := float(cell_px) * 0.9
	var sx := target_px / float(spr.texture.get_width())
	var sy := target_px / float(spr.texture.get_height())
	var scale_factor : float = min(sx, sy)
	spr.scale = Vector2(scale_factor, scale_factor)
	spr.position = _cell_pos(lx, ly)
	add_child(spr)
	move_highlights[key] = spr

func _clear_move_highlights() -> void:
	for k in move_highlights.keys():
		var n2: Sprite2D = move_highlights[k]
		if is_instance_valid(n2):
			if n2.has_meta("_pulse_tween"):
				var t: Tween = n2.get_meta("_pulse_tween")
				if t and t.is_running(): t.kill()
				n2.set_meta("_pulse_tween", null)
			n2.queue_free()
	move_highlights.clear()

func _revert_temp_move_if_any() -> void:
	if input_locked:
		return
	if not has_moved or prev_moves.size() < 2:
		return

	input_locked = true

	for i in range(prev_moves.size() - 2, -1, -2):
		var from_v := Vector2i(int(prev_moves[i].x), int(prev_moves[i].y))
		var to_v := Vector2i(int(prev_moves[i + 1].x), int(prev_moves[i + 1].y))

		var piece_to_revert := get_node_or_null("PiecesRoot/%d,%d" % [to_v.x, to_v.y]) as Sprite2D
		if piece_to_revert != null:
			move_piece(piece_to_revert, from_v.x, from_v.y, 0.0)

	if prev_jumps.size() > 0:
		for captured_data: Dictionary in prev_jumps:
			var jx: int = int(captured_data.get("x", -1))
			var jy: int = int(captured_data.get("y", -1))
			var value: String = String(captured_data.get("value", ""))

			if jx < 0 or jx > 7 or jy < 0 or jy > 7 or value == "":
				continue

			var old_captured := get_node_or_null("PiecesRoot/_captured_%d,%d" % [jx, jy]) as Sprite2D
			if old_captured != null:
				old_captured.visible = false

			if get_node_or_null("PiecesRoot/%d,%d" % [jx, jy]) == null:
				_spawn_piece(value, jx, jy)

	prev_moves.clear()
	prev_jumps.clear()
	has_moved = false
	chain_jump_piece = null
	clicked_piece = null
	moves.clear()
	_save_checkers_idle()

	clear_highlights()

	_compute_mandatory_jumps()
	_update_send_button()

	if rule_mandatory_jumps and must_jump:
		_show_mandatory_jump_previews()

	input_locked = false
	
func _update_send_button() -> void:
	var can_act := (
		isTurn and
		not waitingForOpponent and
		not spectator_mode and
		not game_over
	)

	var show_send := (
		can_act and
		has_moved and
		chain_jump_piece == null
	)

	var show_hint := (
		can_act and
		not has_moved
	)

	if show_send:
		_animate_turn_hint(false)
		_animate_send_button(true)
	elif show_hint:
		_animate_send_button(false)
		_animate_turn_hint(true)
	else:
		_animate_send_button(false)
		_animate_turn_hint(false)
	
func _on_board_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	if not _can_accept_board_input():
		return

	var board_rect: Rect2 = _get_board_draw_rect()
	var p: Vector2 = event.position

	if not board_rect.has_point(p):
		return

	var rel: Vector2 = p - board_rect.position - Vector2(board_inset, board_inset)
	var gx: int = int(floor(rel.x / float(cell_px)))
	var gy: int = int(floor(rel.y / float(cell_px)))
	if gx < 0 or gx > 7 or gy < 0 or gy > 7:
		return

	var L: Vector2i = _visual_to_logical(gx, gy)
	var lx: int = L.x
	var ly: int = L.y

	if not rule_mandatory_jumps:
		must_jump = false
		jumping_pieces.clear()
	else:
		_compute_mandatory_jumps()

	var clicked_piece_on_cell := get_node_or_null("PiecesRoot/%d,%d" % [lx, ly]) as Sprite2D

	if has_moved:
		# During a required multi-jump, only the same piece can continue.
		if chain_jump_piece != null:
			if clicked_piece_on_cell == chain_jump_piece:
				_revert_temp_move_if_any()
				return

			if clicked_piece_on_cell == null:
				_try_commit_move(chain_jump_piece, lx, ly)
			return

		# Normal temporary move: tapping the moved piece cancels it.
		if clicked_piece_on_cell != null and check_player(clicked_piece_on_cell):
			var moved_to := Vector2i(int(prev_moves[-1].x), int(prev_moves[-1].y))

			if _get_piece_pos(clicked_piece_on_cell) == moved_to:
				_revert_temp_move_if_any()
				return

			_revert_temp_move_if_any()
			_select_piece(clicked_piece_on_cell)
			return

		if clicked_piece != null:
			_try_commit_move(clicked_piece, lx, ly)
		return

	if clicked_piece_on_cell != null:
		if not check_player(clicked_piece_on_cell):
			return

		if chain_jump_piece != null and clicked_piece_on_cell != chain_jump_piece:
			return

		if rule_mandatory_jumps and must_jump and chain_jump_piece == null:
			if not (clicked_piece_on_cell in jumping_pieces):
				for piece_to_pulse in jumping_pieces:
					_start_pulse(piece_to_pulse, 0.1, 0.7, 1.0)
				return

		if clicked_piece_on_cell == clicked_piece and not has_moved:
			clicked_piece = null
			clear_highlights()
			_clear_selected_highlight()
			if rule_mandatory_jumps and must_jump:
				_show_mandatory_jump_previews()
			return

		_select_piece(clicked_piece_on_cell)
		return

	if clicked_piece != null:
		_try_commit_move(clicked_piece, lx, ly)
		return

	clear_highlights()
	_clear_selected_highlight()

	if rule_mandatory_jumps and must_jump:
		_show_mandatory_jump_previews()
		
func _start_pulse(node: CanvasItem, min_a: float = 0.35, max_a: float = 0.85, period: float = 1.2) -> void:
	if node == null or not is_instance_valid(node):
		return

	if node.has_meta("_pulse_tween"):
		var old: Tween = node.get_meta("_pulse_tween")
		if old and old.is_running():
			old.kill()
		node.set_meta("_pulse_tween", null)

	if not node.is_inside_tree():
		await get_tree().process_frame
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			return

	var tw := _tween_for(node)
	tw.set_loops(0)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "self_modulate:a", min_a, period * 0.5)
	tw.tween_property(node, "self_modulate:a", max_a, period * 0.5)

	node.set_meta("_pulse_tween", tw)
	node.tree_exited.connect(func():
		if is_instance_valid(tw):
			tw.kill()
		node.set_meta("_pulse_tween", null)
	)

func _stop_pulse(node: CanvasItem) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_meta("_pulse_tween"):
		var t: Tween = node.get_meta("_pulse_tween")
		if t and t.is_running():
			t.kill()
		node.set_meta("_pulse_tween", null)
	node.self_modulate.a = 1.0

func _stop_all_jump_pulses(except: Sprite2D = null) -> void:
	for p in jumping_pieces:
		if p != null and is_instance_valid(p) and p != except:
			_stop_pulse(p)


func _get_board_draw_rect() -> Rect2:
	if not is_instance_valid(board) or board.texture == null:
		return Rect2(board.position, board.size)
	var tex_size_i: Vector2i = board.texture.get_size()
	var tex_size: Vector2 = Vector2(tex_size_i)
	var ctl_size: Vector2 = board.size
	var off: Vector2 = board.position
	var stretch_mode_value: int = board.stretch_mode

	match stretch_mode_value:
		TextureRect.STRETCH_SCALE, TextureRect.STRETCH_TILE:
			return Rect2(off, ctl_size)

		TextureRect.STRETCH_KEEP, TextureRect.STRETCH_KEEP_CENTERED:
			var draw_size: Vector2 = tex_size
			var draw_pos: Vector2 = off
			if stretch_mode_value == TextureRect.STRETCH_KEEP_CENTERED:
				draw_pos += (ctl_size - draw_size) * 0.5
			return Rect2(draw_pos, draw_size)

		TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var s: float = min(ctl_size.x / tex_size.x, ctl_size.y / tex_size.y)
			var draw_size: Vector2 = tex_size * s
			var draw_pos: Vector2 = off
			if stretch_mode_value == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
				draw_pos += (ctl_size - draw_size) * 0.5
			return Rect2(draw_pos, draw_size)

		TextureRect.STRETCH_KEEP_ASPECT_COVERED:
			var s2: float = max(ctl_size.x / tex_size.x, ctl_size.y / tex_size.y)
			var draw_size2: Vector2 = tex_size * s2
			var draw_pos2: Vector2 = off + (ctl_size - draw_size2) * 0.5
			return Rect2(draw_pos2, draw_size2)

		_:
			return Rect2(off, ctl_size)
	
func _abs_to_logical(ax: int, ay: int) -> Vector2i:
	var lx := ax
	var ly := ay
	return Vector2i(lx, ly)

func _logical_to_abs(lx: int, ly: int) -> Vector2i:
	var ax := lx
	var ay := ly
	return Vector2i(ax, ay)
	
func _get_legal_targets_for_piece(piece: Sprite2D, jumps_only: bool = false) -> Dictionary:
	var out: Dictionary = {}
	if piece == null or not is_instance_valid(piece):
		return out
	if not check_player(piece):
		return out

	var pos := _get_piece_pos(piece)
	if pos == Vector2i(-1, -1):
		return out

	if chain_jump_piece != null and piece != chain_jump_piece:
		return out

	var effective_must: bool = must_jump if rule_mandatory_jumps else false
	var continuing_jump: bool = (chain_jump_piece != null and piece == chain_jump_piece)
	var require_jumps: bool = jumps_only or continuing_jump or effective_must

	if effective_must and not _any_jump_from(piece):
		return out

	for d: Vector2i in _jump_dirs_for(piece):
		var mid := pos + d
		var land := pos + (d * 2)
		if land.x < 0 or land.x > 7 or land.y < 0 or land.y > 7:
			continue

		var mid_node := get_node_or_null("PiecesRoot/%d,%d" % [mid.x, mid.y]) as Sprite2D
		if mid_node != null and not check_player(mid_node) \
		and get_node_or_null("PiecesRoot/%d,%d" % [land.x, land.y]) == null:
			out[Vector2i(land.x, land.y)] = true

	if not require_jumps and not has_moved:
		for d: Vector2i in _move_dirs_for(piece):
			var adj := pos + d
			if adj.x < 0 or adj.x > 7 or adj.y < 0 or adj.y > 7:
				continue
			if get_node_or_null("PiecesRoot/%d,%d" % [adj.x, adj.y]) == null:
				out[Vector2i(adj.x, adj.y)] = true

	return out

func _save_checkers_progress() -> void:
	if recovery_restore_in_progress or spectator_mode or not isTurn or appPlugin == null:
		return

	var saved_moves: Array[String] = []

	for i in range(0, prev_moves.size(), 2):
		if i + 1 >= prev_moves.size():
			break

		var a: Vector2 = prev_moves[i]
		var b: Vector2 = prev_moves[i + 1]
		saved_moves.append("%d,%d,%d,%d" % [int(a.x), int(a.y), int(b.x), int(b.y)])

	var progress := {
		"phase": "pending" if not saved_moves.is_empty() else "idle",
		"turn": recovery_turn_num,
		"moves": "|".join(saved_moves)
	}

	appPlugin.saveTurnProgress(JSON.stringify(progress))
	OpLog.i(LOG_TAG, ["recovery_saved phase=", progress["phase"], " moves=", saved_moves.size()])


func _save_checkers_idle() -> void:
	if recovery_restore_in_progress or spectator_mode or appPlugin == null:
		return

	var progress := {
		"phase": "idle",
		"turn": recovery_turn_num,
		"moves": ""
	}

	appPlugin.saveTurnProgress(JSON.stringify(progress))

func _try_commit_move(
	piece: Sprite2D,
	to_lx: int,
	to_ly: int,
) -> void:
	if input_locked:
		return

	if piece == null or not is_instance_valid(piece):
		return

	if not check_player(piece):
		return

	if (
		not isTurn or
		waitingForOpponent or
		spectator_mode or
		game_over
	):
		return

	if (
		chain_jump_piece != null and
		piece != chain_jump_piece
	):
		return

	var from_pos: Vector2i = (
		_get_piece_pos(
			piece,
		)
	)

	if from_pos == Vector2i(-1, -1):
		return

	var legal: Dictionary = (
		_get_legal_targets_for_piece(
			piece,
			chain_jump_piece != null,
		)
	)

	var target := Vector2i(
		to_lx,
		to_ly,
	)

	if not legal.has(target):
		return

	# Remember whether this move is part of a mandatory
	# capture sequence BEFORE changing the board.
	var was_required_jump: bool = (
		rule_mandatory_jumps and
		(
			must_jump or
			chain_jump_piece != null
		)
	)

	input_locked = true

	clear_highlights()
	_stop_all_jump_pulses(
		piece,
	)

	var was_jump: bool = (
		absi(
			from_pos.x -
				to_lx
		) == 2 and
		absi(
			from_pos.y -
				to_ly
		) == 2
	)

	dbg(
		[
			"commit_move from=",
			from_pos,
			" to=",
			target,
			" jump=",
			was_jump,
			" required=",
			was_required_jump,
		]
	)

	prev_moves.append(
		Vector2(
			from_pos.x,
			from_pos.y,
		)
	)

	prev_moves.append(
		Vector2(
			to_lx,
			to_ly,
		)
	)

	has_moved = true
	_save_checkers_progress()

	var move_tw: Tween = move_piece(
		piece,
		to_lx,
		to_ly,
	)

	var jump_tw: Tween = null

	if was_jump:
		jump_tw = jump_piece(
			from_pos.x,
			from_pos.y,
			to_lx,
			to_ly,
		)

		chain_jump_piece = piece
	else:
		chain_jump_piece = null

	if (
		move_tw != null and
		move_tw.is_running()
	):
		await move_tw.finished

	if (
		jump_tw != null and
		jump_tw.is_running()
	):
		await jump_tw.finished

	if (
		piece == null or
		not is_instance_valid(piece)
	):
		input_locked = false
		return

	clicked_piece = piece

	_compute_mandatory_jumps()

	if was_jump:
		var follow_ups: Dictionary = (
			_get_legal_targets_for_piece(
				piece,
				true,
			)
		)

		# Mandatory multi-jump:
		# this same checker MUST continue.
		if follow_ups.size() > 0:
			moves.clear()

			for k in follow_ups.keys():
				var v: Vector2i = k

				moves[
					Vector2(
						v.x,
						v.y,
					)
				] = piece

				_add_move_highlight(
					v.x,
					v.y,
				)

			_show_selected_highlight_at(
				to_lx,
				to_ly,
			)

			# Because chain_jump_piece is still set,
			# Send remains hidden.
			_update_send_button()

			input_locked = false
			return

	# There are no additional captures available.
	chain_jump_piece = null
	clicked_piece = piece
	moves.clear()

	_clear_move_highlights()

	_show_selected_highlight_at(
		to_lx,
		to_ly,
	)

	if (
		was_jump and
		was_required_jump
	):
		_animate_turn_hint(
			false,
		)

		_animate_send_button(
			false,
		)

		input_locked = false

		OpLog.i(
			LOG_TAG,
			[
				"required_jump_complete auto_send steps=",
				floori(
					float(
						prev_moves.size()
					) /
					2.0
				),
			],
		)

		if not recovery_restore_in_progress:
			call_deferred("_on_send_pressed")
		return

	_update_send_button()

	input_locked = false

func _restore_checkers_recovery() -> bool:
	if recovery_loaded or spectator_mode or not isTurn or game_over:
		return false

	if recovery_snapshot_pending:
		recovery_loaded = true
		waitingForOpponent = true
		input_locked = true

		if is_instance_valid(send_button):
			send_button.visible = false
			send_button.disabled = true

		if is_instance_valid(turn_hint_label):
			turn_hint_label.visible = false

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
		OpLog.i(LOG_TAG, ["recovery_stale savedTurn=", saved_turn, " currentTurn=", recovery_turn_num])
		return false

	var raw_moves := String(progress.get("moves", ""))
	if raw_moves.is_empty():
		return false

	var restored_moves: Array[String] = raw_moves.split("|", false)

	recovery_loaded = true
	recovery_restore_in_progress = true

	OpLog.i(LOG_TAG, ["recovery_restore moves=", restored_moves.size()])

	for move_string in restored_moves:
		var p := move_string.split(",", false)
		if p.size() < 4:
			continue

		var from_pos := Vector2i(int(p[0]), int(p[1]))
		var to_pos := Vector2i(int(p[2]), int(p[3]))
		var piece := get_node_or_null("PiecesRoot/%d,%d" % [from_pos.x, from_pos.y]) as Sprite2D

		if piece == null:
			OpLog.w(LOG_TAG, ["recovery missing piece from=", from_pos])
			continue

		await _try_commit_move(piece, to_pos.x, to_pos.y)

	recovery_restore_in_progress = false
	input_locked = false

	OpLog.i(LOG_TAG, ["recovery_restored steps=", floori(float(prev_moves.size()) / 2.0), " chain=", chain_jump_piece != null])
	return true

func _rebuild_from_replay() -> void:
	OpLog.i(LOG_TAG, ["rebuild_start turn=", isTurn, " spectator=", spectator_mode, " replayLen=", replay.length(), " boards=", replay.count("board:"), " moves=", replay.count("move:") + replay.count("attack:")])
	replay_locked = true
	input_locked = true

	clear_highlights()
	clicked_piece = null
	moves.clear()
	has_moved = false
	prev_moves.clear()
	prev_jumps.clear()
	chain_jump_piece = null
	must_jump = false
	jumping_pieces.clear()

	_prepare_scene_once()
	_clear_pieces()
	await get_tree().process_frame
	await get_tree().process_frame

	var initial_board: PackedStringArray = PackedStringArray()
	var final_board: PackedStringArray = PackedStringArray()
	var replay_moves: Array[String] = []

	for elem in replay.split("|", false):
		var spl := elem.split(":", false, 1)
		if spl.size() < 2:
			continue

		match spl[0]:
			"move", "attack":
				replay_moves.append(elem)
			"board":
				if initial_board.is_empty():
					initial_board = spl[1].split(",")
				else:
					final_board = spl[1].split(",")

	if initial_board.is_empty() and not final_board.is_empty():
		initial_board = final_board
	if final_board.is_empty() and not initial_board.is_empty():
		final_board = initial_board
	if initial_board.is_empty():
		OpLog.w(LOG_TAG, ["rebuild has no board entries raw=", replay])
	
	if (
		replay_moves.is_empty()
		and not initial_board.is_empty()
		and not final_board.is_empty()
		and initial_board != final_board
	):
		var inferred_move := _infer_single_move_from_boards(
			initial_board,
			final_board,
		)

		if inferred_move != "":
			replay_moves.append(
				inferred_move,
			)

			OpLog.i(
				LOG_TAG,
				[
					"rebuild inferred board-only replay move=",
					inferred_move,
				],
			)
		else:
			OpLog.w(
				LOG_TAG,
				"rebuild could not infer board-only replay move; final snapshot will be applied",
			)

	if not initial_board.is_empty():
		for ay in range(8):
			for ax in range(8):
				var idx: int = ay * 8 + ax
				if idx >= initial_board.size():
					continue

				var v: String = initial_board[idx]
				if v == "0":
					continue

				var L: Vector2i = _abs_to_logical(ax, ay)
				_spawn_piece(v, L.x, L.y)

	await get_tree().process_frame

	for move_entry in replay_moves:
		var parts := move_entry.split(":", false, 1)
		if parts.size() < 2:
			continue

		var kind: String = parts[0]
		var p := parts[1].split(",")
		if p.size() < 4:
			OpLog.w(LOG_TAG, ["rebuild skipped malformed move=", move_entry])
			continue

		var src_l: Vector2i = _abs_to_logical(int(p[0]), int(p[1]))
		var dst_l: Vector2i = _abs_to_logical(int(p[2]), int(p[3]))

		var moved := get_node_or_null("PiecesRoot/%d,%d" % [src_l.x, src_l.y]) as Sprite2D
		if moved == null:
			OpLog.w(LOG_TAG, ["rebuild missing source piece move=", move_entry, " src=", src_l])
			continue

		var move_tw: Tween = move_piece(moved, dst_l.x, dst_l.y, 0.0)
		var jump_tw: Tween = null

		if kind == "attack":
			jump_tw = jump_piece(src_l.x, src_l.y, dst_l.x, dst_l.y, 0.0, true)

		if move_tw != null and move_tw.is_running():
			await move_tw.finished
		if jump_tw != null and jump_tw.is_running():
			await jump_tw.finished

		if is_instance_valid(moved):
			var col: String = get_piece_color(moved)
			if (col == "red" and dst_l.y == 0) or (col == "black" and dst_l.y == 7):
				set_checker_king(moved, col)

	await get_tree().process_frame
	await get_tree().process_frame

	if not final_board.is_empty():
		var expected_board := ",".join(
			final_board,
		)

		var actual_board := _current_board_string()

		if actual_board != expected_board:
			OpLog.w(
				LOG_TAG,
				[
					"rebuild final board mismatch; applying authoritative snapshot",
					" replayMoves=",
					replay_moves.size(),
					" actual=",
					actual_board,
					" expected=",
					expected_board,
				],
			)

			await _apply_board_snapshot(
				final_board,
			)

			OpLog.i(
				LOG_TAG,
				[
					"rebuild final snapshot applied ",
					_piece_summary(),
				],
			)

	_compute_mandatory_jumps()

	if isTurn and not spectator_mode and rule_mandatory_jumps and must_jump:
		_show_mandatory_jump_previews()
	else:
		_clear_move_highlights()

	_update_send_button()
	_apply_player_piece_icons()
	_apply_board_orientation()

	var wl := check_win_loss()
	if wl != "":
		game_over = true
		stop_waiting_animation()

		if is_instance_valid(send_button):
			send_button.visible = false
			send_button.disabled = true

		if is_instance_valid(turn_hint_label):
			turn_hint_label.visible = false
			turn_hint_label.modulate.a = 0.0

		game_over_visual(wl)
	else:
		game_over = false
		if isTurn and not spectator_mode:
			stop_waiting_animation()
		else:
			start_waiting_animation()
			
	OpLog.i(LOG_TAG, ["rebuild_done moves=", replay_moves.size(), " gameOver=", game_over, " mustJump=", must_jump, " ", _piece_summary()])

	replay_locked = false
	input_locked = false

	if isTurn and not spectator_mode and not game_over:
		if await _restore_checkers_recovery():
			return

		call_deferred("_post_replay_ready")
		
func _make_radial_highlight_node() -> Sprite2D:
	var spr := Sprite2D.new()
	spr.name = "SelectedCellHighlight"
	spr.centered = true
	spr.z_as_relative = false
	spr.z_index = 1

	var grad := Gradient.new()
	grad.add_point(0.0, Color(1.0, 1.0, 1.0, 0))
	grad.add_point(1.0, Color(1.0, 1.0, 1.0, 0.1))

	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 512
	gt.height = 512
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.use_hdr = false
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.25, 0.5)

	spr.texture = gt
	return spr

func _show_selected_highlight_at(lx: int, ly: int) -> void:
	if pieces_root == null:
		_prepare_scene_once()

	if selected_highlight == null:
		selected_highlight = _make_radial_highlight_node()
		pieces_root.add_child(selected_highlight)
	selected_highlight.self_modulate = Color(1, 1, 1, 0.5)

	var tex := selected_highlight.texture
	if tex != null:
		var target_px: float = float(cell_px)
		var sx: float = target_px / float(tex.get_width())
		var sy: float = target_px / float(tex.get_height())
		selected_highlight.scale = Vector2(min(sx, sy), min(sx, sy))

	selected_highlight.position = _cell_pos(lx, ly)
	selected_highlight.visible = true


func _clear_selected_highlight() -> void:
	if selected_highlight and is_instance_valid(selected_highlight):
		selected_highlight.visible = false
		
func _set_game_data(new_replay: String) -> void:
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", new_replay])
	var data_raw: Variant = JSON.parse_string(new_replay)
	if typeof(data_raw) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, ["set_game_data invalid JSON raw=", new_replay])
		return
	var data: Dictionary = data_raw
	
	recovery_turn_num = String(data.get("num", ""))
	recovery_snapshot_pending = String(data.get("_recoveryPending", "false")).to_lower() == "true"
	recovery_snapshot_progress = String(data.get("_recoveryProgress", ""))
	recovery_restore_in_progress = false
	recovery_loaded = false

	OpLog.i(LOG_TAG, ["recovery_snapshot pending=", recovery_snapshot_pending, " progressLen=", recovery_snapshot_progress.length(), " turn=", recovery_turn_num])

	isTurn = bool(data.get("isYourTurn", false))
	replay = String(data.get("replay", ""))
	mode = String(data.get("mode", "n"))
	rule_mandatory_jumps = (mode == "n")
	my_player = String(data.get("myPlayerId", ""))

	var data_sender: int = clamp(int(data.get("player", 0)), 0, 2)
	turn_owner = clamp(int(data.get("player", 1)), 1, 2)
	var p1_id: String = String(data.get("player1", ""))
	var p2_id: String = String(data.get("player2", ""))
 
	var my_side := 0
	var opponent_avatar_key := ""
	
	_checkers_active_win_burst_avatar = null
	_clear_checkers_win_bursts()

	if my_player != "" and p1_id != "" and p2_id != "":
		if my_player == p1_id:
			my_side = 1
			opponent_avatar_key = "avatar2"
		elif my_player == p2_id:
			my_side = 2
			opponent_avatar_key = "avatar1"
		else:
			my_side = 0
	else:
		if isTurn:
			my_side = 1
			opponent_avatar_key = "avatar2"
		else:
			my_side = 2
			opponent_avatar_key = "avatar1"

	spectator_mode = my_side == 0
	player = my_side

	if is_instance_valid(spec_label):
		spec_label.visible = spectator_mode

	if is_instance_valid(you_label):
		you_label.modulate.a = 0.0 if spectator_mode else 1.0

	if spectator_mode:
		if data.has("avatar1") and is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred(
				"update_avatar_from_data",
				GameUtils._parse_avatar_string(
					String(data["avatar1"])
				)
			)

		if data.has("avatar2") and is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred(
				"update_avatar_from_data",
				GameUtils._parse_avatar_string(
					String(data["avatar2"])
				)
			)
	else:
		if opponent_avatar_key != "" and data.has(opponent_avatar_key):
			var avatar_string: String = String(
				data[opponent_avatar_key]
			)

			var opponent_data: Dictionary = (
				GameUtils._parse_avatar_string(
					avatar_string
				)
			)

			if is_instance_valid(opp_avatar_display):
				opp_avatar_display.call_deferred(
					"update_avatar_from_data",
					opponent_data
				)

	_schedule_checkers_responsive_layout(true)

	waitingForOpponent = not isTurn
	OpLog.i(LOG_TAG, ["set_game_data parsed turn=", isTurn, " player=", player, " sender=", data_sender, " spectator=", spectator_mode, " mode=", mode, " replayLen=", replay.length(), " boards=", replay.count("board:"), " moves=", replay.count("move:") + replay.count("attack:")])
	_apply_player_piece_icons()
	call_deferred("_rebuild_from_replay")

func _clear_checkers_win_bursts() -> void:
	var avatars: Array[TextureButton] = [
		player_avatar_display,
		opp_avatar_display,
	]

	for avatar_button in avatars:
		if not is_instance_valid(avatar_button):
			continue

		var wrapper := avatar_button.get_node_or_null(
			CHECKERS_WIN_BURST_WRAPPER_NAME,
		)

		if wrapper != null:
			wrapper.queue_free()


func _show_checkers_win_burst(
	avatar_button: TextureButton,
) -> void:
	if not is_instance_valid(avatar_button):
		return

	_checkers_active_win_burst_avatar = avatar_button

	var existing := avatar_button.get_node_or_null(
		CHECKERS_WIN_BURST_WRAPPER_NAME,
	)

	if existing != null:
		existing.queue_free()

	var wrapper := Control.new()

	wrapper.name = (
		CHECKERS_WIN_BURST_WRAPPER_NAME
	)

	wrapper.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	wrapper.show_behind_parent = true
	wrapper.clip_contents = false
	wrapper.size = CHECKERS_BASE_AVATAR_SIZE

	wrapper.pivot_offset = (
		CHECKERS_BASE_AVATAR_SIZE *
		0.5
	)

	wrapper.position = (
		avatar_button.size *
			0.5 -
		CHECKERS_BASE_AVATAR_SIZE *
			0.5
	)

	wrapper.scale = Vector2.ONE * (
		_checkers_current_avatar_scale
	)

	avatar_button.add_child(wrapper)

	var target := TextureButton.new()

	target.name = "CheckersBurstTarget"
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.ignore_texture_size = true
	target.clip_contents = false
	target.size = CHECKERS_BASE_AVATAR_SIZE

	target.pivot_offset = (
		CHECKERS_BASE_AVATAR_SIZE *
		0.5
	)

	wrapper.add_child(target)

	GameUtils._show_win_burst(target)

func game_over_visual(
	results: String,
) -> void:
	_clear_checkers_win_bursts()
	_checkers_active_win_burst_avatar = null

	if spectator_mode:
		if results == "win":
			win_loss_label.text = "Player 1 Wins!"

			win_loss_label.add_theme_color_override(
				"font_color",
				Color(1, 0.84, 0),
			)

			_show_checkers_win_burst(
				player_avatar_display,
			)
		else:
			win_loss_label.text = "Player 2 Wins!"

			win_loss_label.add_theme_color_override(
				"font_color",
				Color(1, 0.84, 0),
			)

			_show_checkers_win_burst(
				opp_avatar_display,
			)
	else:
		if results == "win":
			win_loss_label.text = "YOU WIN!"

			win_loss_label.add_theme_color_override(
				"font_color",
				Color(1, 0.84, 0),
			)

			_show_checkers_win_burst(
				player_avatar_display,
			)
		else:
			win_loss_label.text = "YOU LOSE"

			win_loss_label.add_theme_color_override(
				"font_color",
				Color(1, 0.2, 0.2),
			)

			_show_checkers_win_burst(
				opp_avatar_display,
			)

	win_loss_label.visible = true

	await get_tree().process_frame

	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = (
		win_loss_label.size *
		0.5
	)

	var tween_in := create_tween()

	tween_in.tween_property(
		win_loss_label,
		"scale",
		Vector2.ONE,
		0.6,
	).set_ease(
		Tween.EASE_OUT,
	).set_trans(
		Tween.TRANS_BACK,
	)

func export_replay() -> String:
	var board_values: Array[String] = []

	for i in range(64):
		board_values.append("0")

	for ly in range(8):
		for lx in range(8):
			var piece := get_node_or_null("PiecesRoot/%d,%d" % [lx, ly]) as Sprite2D
			if piece != null:
				var A := _logical_to_abs(lx, ly)
				var idx := A.y * 8 + A.x
				var color := get_piece_color(piece)
				if color == "red":
					board_values[idx] = "3" if is_checker_king(piece) else "1"
				elif color == "black":
					board_values[idx] = "4" if is_checker_king(piece) else "2"

	var boardStr := ",".join(board_values)

	var move_str := "|"
	var step_count: int = floori(float(prev_moves.size()) / 2.0)
	for i in range(0, prev_moves.size(), 2):
		var p1: Vector2 = prev_moves[i]
		var p2: Vector2 = prev_moves[i + 1]
		var A1 := _logical_to_abs(int(p1.x), int(p1.y))
		var A2 := _logical_to_abs(int(p2.x), int(p2.y))
		var moveType := "attack" if abs(p1.x - p2.x) > 1 else "move"
		move_str += "%s:%d,%d,%d,%d|" % [moveType, A1.x, A1.y, A2.x, A2.y]

	clear_highlights()
	clicked_piece = null
	has_moved = false
	moves.clear()
	prev_jumps.clear()
	prev_moves.clear()
	if is_instance_valid(send_button):
		send_button.disabled = true

	var result: Dictionary = {
		"replay": replay.split("|")[-1] + move_str + "board:" + boardStr
	}
	var wl := check_win_loss()
	if wl != "":
		result["winner"] = my_player + "|" + ("1" if wl == "win" else "-1")
	var out_json := JSON.stringify(result)
	OpLog.event(LOG_TAG, ["export_replay_out steps=", step_count, " winLoss=", wl, " raw=", out_json])
	return out_json

func check_win_loss() -> String:
	var num_your_pieces := 0
	var num_other_pieces := 0
	var scanned_any := false

	for y in range(0, 8):
		for x in range(0, 8):
			var piece := get_node_or_null("PiecesRoot/" + str(x) + "," + str(y)) as Sprite2D
			if piece != null:
				scanned_any = true
				if check_player(piece):
					num_your_pieces += 1
				else:
					num_other_pieces += 1

	if not scanned_any:
		return ""
	if num_your_pieces == 0 and num_other_pieces > 0:
		return "lose"
	if num_other_pieces == 0 and num_your_pieces > 0:
		return "win"

	return ""

func _piece_board_value(piece: Sprite2D) -> String:
	if piece == null or not is_instance_valid(piece):
		return ""

	var color: String = get_piece_color(piece)

	if color == "red":
		return "3" if is_checker_king(piece) else "1"
	if color == "black":
		return "4" if is_checker_king(piece) else "2"

	return ""

func jump_piece(prev_x: int, prev_y: int, new_x: int, new_y: int, anim_delay: float = 0.0, replay_mode: bool = false) -> Tween:
	var x_step: int = 1 if new_x > prev_x else -1
	var y_step: int = 1 if new_y > prev_y else -1
	var jx: int = prev_x + x_step
	var jy: int = prev_y + y_step

	var jumped_piece := get_node_or_null("PiecesRoot/%d,%d" % [jx, jy]) as Sprite2D
	if jumped_piece == null:
		return null

	if not replay_mode:
		var captured_value: String = _piece_board_value(jumped_piece)
		if captured_value != "":
			prev_jumps.append({"x": jx, "y": jy, "value": captured_value})

	jumped_piece.name = "_captured_%d,%d" % [jx, jy]

	var tween := jumped_piece.get_tree().create_tween()
	var modulate_color: Color = jumped_piece.self_modulate
	modulate_color.a = 0.0

	tween.tween_interval(anim_delay)
	tween.tween_property(jumped_piece, "self_modulate", modulate_color, 0.2).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func():
		if is_instance_valid(jumped_piece):
			jumped_piece.queue_free()
	)

	return tween

func move_piece(piece: Sprite2D, x: int, y: int, anim_delay: float = 0.0) -> Tween:
	var new_pos := _cell_pos(x, y)
	var tween := piece.get_tree().create_tween()
	tween.tween_interval(anim_delay)
	tween.tween_property(piece, "position", new_pos, 0.5).set_trans(Tween.TRANS_SINE)

	var color := get_piece_color(piece)
	if (color == "red" and y == 0) or (color == "black" and y == 7):
		tween.tween_callback(set_checker_king.bind(piece, color))

	piece.name = "%d,%d" % [x, y]
	return tween
	
func set_checker_king(piece: Sprite2D, color: String, undo: bool = false) -> void:
	if color == "red":
		piece.texture = red_normal_texture if undo else red_king_texture
	elif color == "black":
		piece.texture = black_normal_texture if undo else black_king_texture
	_apply_piece_scale(piece)


func is_checker_king(piece: Sprite2D) -> bool:
	return piece.texture != null and piece.texture.resource_path.contains("king")


func getPiecePos(piece: Sprite2D) -> Vector2:
	var posStr := piece.name.split(",")
	return Vector2(int(posStr[0]), int(posStr[1]))

func add_highlight(x: int, y: int) -> void:
	_add_move_highlight(x, y)

func clear_highlights() -> void:
	for n: Node in highlights:
		if is_instance_valid(n):
			n.queue_free()
	highlights.clear()
	_clear_move_highlights()
	_clear_selected_highlight()
	_stop_all_jump_pulses()

func get_piece_color(piece: Sprite2D) -> String:
	if piece.texture.resource_path.contains("red"):
		return "red"
	elif piece.texture.resource_path.contains("black"):
		return "black"
	return "unknown"

func gen_moves(jumps_only: bool = false) -> void:
	moves.clear()
	_clear_move_highlights()

	if clicked_piece == null or not is_instance_valid(clicked_piece):
		return

	var legal: Dictionary = _get_legal_targets_for_piece(clicked_piece, jumps_only)
	for target in legal.keys():
		var v: Vector2i = target
		moves[Vector2(v.x, v.y)] = clicked_piece
		_add_move_highlight(v.x, v.y)
		
func check_player(piece: Sprite2D) -> bool:
	var color := get_piece_color(piece)
	if spectator_mode and color == "red":
		return true
	if player == 1 and color == "red":
		return true
	if player == 2 and color == "black":
		return true
	return false
	
func _cell_pos_visual(gx: int, gy: int) -> Vector2:
	return board_origin + Vector2((gx + 0.5) * float(cell_px), (gy + 0.5) * float(cell_px))

func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Checkers[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
Capture all of your opponent’s pieces or block them so they have no legal moves left.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• Pieces move diagonally forward to an empty dark square.  
• Capturing (jumping over an adjacent enemy piece into an empty square) is [b]mandatory[/b].  
• Multiple jumps must continue until no further captures are possible.  
• Regular pieces (“men”) move and capture forward only.  
• When a man reaches the farthest row, it becomes a [b]King[/b] and can move and capture both forward and backward.  
• Crowning happens immediately, and a new King may keep jumping if captures remain available.
[/font_size]

[font_size={24px}][b]End of Game[/b][/font_size]
[font_size={18px}]
The game ends when one player loses all their pieces or cannot make a legal move.  
The other player is declared the winner.
[/font_size]

"""

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		return
	
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
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0

		if game_over or spectator_mode:
			stop_waiting_animation()
		else:
			start_waiting_animation()
	)
	
func _unhandled_input(event: InputEvent) -> void:
	if suppress_next_click and event is InputEventMouseButton and event.pressed:
		suppress_next_click = false
		get_viewport().set_input_as_handled()
		
func _read_color(vals: Array) -> Color:
	if vals.size() >= 3:
		return Color(vals[0].to_float(), vals[1].to_float(), vals[2].to_float())
	return Color.WHITE

func _process(_delta: float) -> void:
	pass

func _dump_pieces() -> void:
	var names: Array[String] = []
	if pieces_root:
		for c in pieces_root.get_children():
			if c is Sprite2D:
				names.append((c as Sprite2D).name)
	
func _peek_cell(_lx: int, _ly: int) -> void:
	pass
	
func _scan_row(ly: int) -> void:
	var row: Array[String] = []
	for x in range(8):
		var n := get_node_or_null("PiecesRoot/%d,%d" % [x, ly])
		row.append(String(n.name) if n != null else ".")
	
func _diagonal_dirs_for(piece: Sprite2D) -> Array:
	var dirs: Array[Vector2i] = []
	var col := get_piece_color(piece)
	var king := is_checker_king(piece)
	if col == "black" or king:
		dirs.append(Vector2i(-1, -1))
		dirs.append(Vector2i( 1, -1))
	if col == "red" or king:
		dirs.append(Vector2i(-1,  1))
		dirs.append(Vector2i( 1,  1))
	return dirs

func _any_jump_from(piece: Sprite2D) -> bool:
	if piece == null or not is_instance_valid(piece):
		return false
	var p := Vector2i(int(getPiecePos(piece).x), int(getPiecePos(piece).y))
	for d in _jump_dirs_for(piece):
		var mid := p + d
		var land := p + (d * 2)
		if land.x < 0 or land.x > 7 or land.y < 0 or land.y > 7:
			continue
		var mid_node := get_node_or_null("PiecesRoot/%d,%d" % [mid.x, mid.y]) as Sprite2D
		if mid_node != null and not check_player(mid_node) \
		and get_node_or_null("PiecesRoot/%d,%d" % [land.x, land.y]) == null:
			return true
	return false

func _compute_mandatory_jumps() -> void:
	must_jump = false
	jumping_pieces.clear()

	if not rule_mandatory_jumps:
		return

	if spectator_mode or not isTurn:
		return

	for y in range(8):
		for x in range(8):
			var piece := get_node_or_null("PiecesRoot/%d,%d" % [x, y]) as Sprite2D
			if piece and check_player(piece) and _any_jump_from(piece):
				must_jump = true
				jumping_pieces.append(piece)

func _pos_str(v: Vector2i) -> String:
	return "(%d,%d)" % [v.x, v.y]
	
func _collect_jump_landings(piece: Sprite2D) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if piece == null or not is_instance_valid(piece):
		return out

	var p := Vector2i(int(getPiecePos(piece).x), int(getPiecePos(piece).y))
	for d: Vector2i in _jump_dirs_for(piece):
		var mid := p + d
		var land := p + (d * 2)
		if land.x < 0 or land.x > 7 or land.y < 0 or land.y > 7:
			continue
		var mid_node := get_node_or_null("PiecesRoot/%d,%d" % [mid.x, mid.y]) as Sprite2D
		if mid_node != null and not check_player(mid_node) \
		and get_node_or_null("PiecesRoot/%d,%d" % [land.x, land.y]) == null:
			out.append(land)
	return out

func _highlight_all_jump_targets() -> void:
	_clear_move_highlights()

	for jp in jumping_pieces:
		if not is_instance_valid(jp):
			continue

		_start_pulse(jp, 0.1, 0.7, 1.0)

		for land in _collect_jump_landings(jp):
			_add_move_highlight(land.x, land.y)

func _move_dirs_for(piece: Sprite2D) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = []
	var col := get_piece_color(piece)
	var king := is_checker_king(piece)
	if king or col == "red":
		dirs.append(Vector2i(-1, -1))
		dirs.append(Vector2i( 1, -1))
	if king or col == "black":
		dirs.append(Vector2i(-1,  1))
		dirs.append(Vector2i( 1,  1))
	return dirs

func _jump_dirs_for(piece: Sprite2D) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = []
	if piece == null or not is_instance_valid(piece):
		return dirs

	var col := get_piece_color(piece)
	var king := is_checker_king(piece)

	if king or col == "red":
		dirs.append(Vector2i(-1, -1))
		dirs.append(Vector2i( 1, -1))
	if king or col == "black":
		dirs.append(Vector2i(-1,  1))
		dirs.append(Vector2i( 1,  1))

	return dirs
	
func _sanity_check_any_jump_exists() -> void:
	var found := false
	for y in range(8):
		for x in range(8):
			var p := get_node_or_null("PiecesRoot/%d,%d" % [x, y]) as Sprite2D
			if p == null or not check_player(p):
				continue
			if _any_jump_from(p):
				found = true
				break
		if found: break
	
func _show_mandatory_jump_previews() -> void:
	_clear_move_highlights()

	for jp in jumping_pieces:
		if not is_instance_valid(jp):
			continue

		_start_pulse(jp, 0.10, 0.85, 1.0)

		for land in _collect_jump_landings(jp):
			_add_move_highlight(land.x, land.y)
