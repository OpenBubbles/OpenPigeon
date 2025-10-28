extends Control
class_name CheckersBoardTop

# ===== Layout / Board =====
@export var board_origin: Vector2 = Vector2(0, 0)  # top-left of cell (0,0)
@export var cell_px: int = 80                      # piece grid size in pixels

# ===== UI / Avatars / Controls =====
@onready var player_avatar_display: Control = %PlayerAvatarDisplay
@onready var opp_avatar_display: Control    = %OppAvatarDisplay
@onready var rules_button: Button           = %RulesButton
@onready var settings_button: Button        = %SettingsButton
@onready var send_button: Button            = %SendButton
@onready var waiting_label: Label           = %WaitForOpponentLabel
@onready var player_piece_icon: TextureRect = %PlayerPiece
@onready var opp_piece_icon: TextureRect    = %OppPiece
@onready var you_label: Label               = %YouLabel
@onready var spec_label: Label              = %SpecLabel
@onready var board: TextureRect             = %CheckersBoardTop

const RULES_POPUP_SCENE    := preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE := preload("res://global/settings_popup.tscn")

# ===== Checker piece textures =====
var black_king_texture    := preload("res://checkers/checker_black_king.png")
var red_king_texture      := preload("res://checkers/checker_red_king.png")
var black_normal_texture  := preload("res://checkers/checker_black.png")
var red_normal_texture    := preload("res://checkers/checker_red.png")

var ui_piece_textures := {
	"red":   preload("res://checkers/checker_red.png"),
	"black": preload("res://checkers/checker_black.png")
}

# ===== Game data / state =====
var replay: String = ""

# Root to keep the spawned pieces organized
var pieces_root: Node2D

# Highlights (optional visual cues)
var highlights: Array[Node] = []

var clicked_piece: Sprite2D
var moves: Dictionary[Vector2, Sprite2D] = {}
var has_moved: bool = false
var prev_moves: Array[Vector2] = []
var prev_jumps: Array[Sprite2D] = []

var checking_for_jumps: bool = false
var must_jump: bool = false
var has_connected: bool = false

var mode: String = "n"
var isTurn: bool = false
var waitingForOpponent: bool = false
var spectator_mode: bool = false

# Player mapping: 1 = RED (we want at bottom), 2 = BLACK
var player: int = 0
var my_player: String = ""
var suppress_next_click: bool = false

@export_range(0.3, 1.0, 0.01) var piece_fill: float = 0.78
@export var board_inset: int = 0

# ===== Helpers =====

func _apply_piece_scale(s: Sprite2D) -> void:
	if s.texture == null:
		return

	# Explicit types to avoid Variant inference.
	var tex_size: Vector2i = s.texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return

	var target_px: float = float(cell_px) * piece_fill
	var sx: float = target_px / float(tex_size.x)
	var sy: float = target_px / float(tex_size.y)
	var scale_factor: float = minf(sx, sy)

	s.scale = Vector2(scale_factor, scale_factor)
	s.centered = true

func _cell_pos(x: int, y: int) -> Vector2:
	return board_origin + Vector2((float(x) + 0.5) * float(cell_px), (float(y) + 0.5) * float(cell_px))

func _apply_player_piece_icons() -> void:
	if not is_instance_valid(player_piece_icon) or not is_instance_valid(opp_piece_icon):
		return
	var my_color: String = "red" if player == 1 else "black"
	var opp_color: String = "black" if player == 1 else "red"
	player_piece_icon.texture = ui_piece_textures.get(my_color, null)
	opp_piece_icon.texture = ui_piece_textures.get(opp_color, null)
	if is_instance_valid(you_label):
		you_label.text = "You"
		you_label.visible = not spectator_mode

func _connect_common_ui() -> void:
	if is_instance_valid(rules_button):
		rules_button.pressed.connect(_on_rules_button_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(send_button):
		send_button.disabled = true

# ===== Piece spawning (no scene templates needed) =====
func _spawn_piece(color: String, king: bool, x: int, y: int) -> Sprite2D:
	var s := Sprite2D.new()
	if color == "red":
		s.texture = red_king_texture if king else red_normal_texture
	else:
		s.texture = black_king_texture if king else black_normal_texture

	_apply_piece_scale(s)               # <-- NEW

	s.position = _cell_pos(x, y)
	s.name = str(x) + "," + str(7 - y)
	s.visible = true
	pieces_root.add_child(s)
	return s
	
func _recalculate_board_layout_from_board() -> void:
	if board == null:
		return

	# Local rect of the TextureRect relative to this Control
	var rect_pos: Vector2 = board.position
	var rect_size: Vector2 = board.size

	# Use the largest 8x8 square centered inside the TextureRect, with optional inset
	var square_side: float = min(rect_size.x, rect_size.y) - float(board_inset) * 2.0
	var px: int = int(floor(square_side / 8.0))
	px = max(px, 1)

	cell_px = px
	var total_grid_px := Vector2(px * 8, px * 8)

	# Center the grid inside the TextureRect
	board_origin = rect_pos \
		+ Vector2((rect_size.x - total_grid_px.x) * 0.5, (rect_size.y - total_grid_px.y) * 0.5) \
		+ Vector2(board_inset, board_inset)

# ===== Lifecycle =====
func _ready() -> void:
	# Create containers
	_recalculate_board_layout_from_board()
	pieces_root = Node2D.new()
	pieces_root.name = "PiecesRoot"
	add_child(pieces_root)

	_connect_common_ui()

	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		if not has_connected:
			print("App plugin is available")
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			return
	else:
		if player == 0 or replay == "":
			# Local test default; assume player 2 (black) with a board state
			_set_game_data('{"isYourTurn":0,"player":"2","replay":"board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0"}')
			print("App plugin is not available")
			return

	if player == 0 or replay == "":
		return

	var playerBox := get_node_or_null("Player" + str(player) + "Box")
	if playerBox != null and not spectator_mode:
		playerBox.get_child(0).set_text("[center]You[/center]")

	# Build boards from replay
	var prevBoard: PackedStringArray = PackedStringArray()
	var nextBoard: PackedStringArray = PackedStringArray()
	var replayMoves: Array[String] = []

	for elem in replay.split("|"):
		var spl: PackedStringArray = elem.split(":")
		if spl[0] == "move" or spl[0] == "attack":
			replayMoves.append(elem)
		if spl[0] == "board":
			if prevBoard.is_empty():
				prevBoard = spl[1].split(",")
			else:
				nextBoard = spl[1].split(",")

	# Fallback if moves omitted
	if replayMoves.size() == 0 and prevBoard != nextBoard and not nextBoard.is_empty():
		prevBoard = nextBoard

	# ----- Initial piece placement (mirror so YOUR color is at bottom) -----
	# Source orientation: red on top, black on bottom.
	if waitingForOpponent == false and not prevBoard.is_empty():
		for y in range(0, 8):
			for x in range(0, 8):
				# Map source index -> screen index
				var sx: int = (7 - x) if player == 1 else x
				var sy: int = y       if player == 1 else (7 - y)
				var val: String = prevBoard[sy * 8 + sx]

				if val == "1":
					_spawn_piece("red", false, x, y)
				elif val == "2":
					_spawn_piece("black", false, x, y)
				elif val == "3":
					_spawn_piece("red", true, x, y)
				elif val == "4":
					_spawn_piece("black", true, x, y)
				# "0" -> empty

	# ----- Animate replayed moves (respect mirroring) -----
	if replayMoves.size() > 0:
		var firstMovePos: PackedStringArray = replayMoves[0].split(":")[1].split(",")
		var sx0: int = int(firstMovePos[0])
		var sy0: int = int(firstMovePos[1])

		var name_x: int = (7 - sx0) if player == 1 else sx0
		var name_y: int = (7 - sy0) if player == 1 else sy0
		var movedPiece := get_node_or_null("PiecesRoot/" + str(name_x) + "," + str(name_y)) as Sprite2D

		if movedPiece != null:
			var tween := movedPiece.get_tree().create_tween()
			for i in range(replayMoves.size()):
				var moveType: String = replayMoves[i].split(":")[0]
				var movePos: PackedStringArray = replayMoves[i].split(":")[1].split(",")

				var sx: int = int(movePos[2])
				var sy: int = int(movePos[3])

				var dx: int = (7 - sx) if player == 1 else sx
				var dy: int = sy       if player == 1 else (7 - sy)

				var newPos := _cell_pos(dx, dy)
				tween.tween_property(movedPiece, "position", newPos, 0.5).set_trans(Tween.TRANS_SINE)

				# Keep name in SOURCE coords for internal consistency where needed
				movedPiece.name = str(sx) + "," + str(sy)

				var color := get_piece_color(movedPiece)
				if (color == "black" and sy == 7) or (color == "red" and sy == 0):
					tween.tween_callback(set_checker_king.bind(movedPiece, color))

				if moveType == "attack":
					var px: int = int(movePos[0])
					var py: int = int(movePos[1])
					jump_piece(px, py, sx, sy, i * 0.5, true)

	# Pre-scan for mandatory jumps when in normal mode
	if mode == "n":
		must_jump = false
		checking_for_jumps = true
		for y in range(0, 8):
			for x in range(0, 8):
				var piece := get_node_or_null("PiecesRoot/" + str(x) + "," + str(7 - y)) as Sprite2D
				if piece != null and check_player(piece):
					clicked_piece = piece
					gen_moves(true)
					if moves.size() > 0:
						must_jump = true
		checking_for_jumps = false

	set_waiting(not isTurn)
	_apply_player_piece_icons()

# ===== Waiting / Win-Loss =====
func set_waiting(enabled: bool) -> void:
	if enabled:
		waitingForOpponent = true
		if is_instance_valid(waiting_label):
			waiting_label.visible = true
	else:
		prev_jumps.clear()
		prev_moves.clear()
		waitingForOpponent = false
		if is_instance_valid(waiting_label):
			waiting_label.visible = false

	var win_loss := check_win_loss()
	if win_loss == "win":
		var wl := get_node_or_null("winLoseLabel")
		if wl:
			wl.get_child(0).set_text("[center]YOU WIN![/center]")
			wl.visible = true
		if is_instance_valid(waiting_label):
			waiting_label.visible = false
	elif win_loss == "lose":
		var wl2 := get_node_or_null("winLoseLabel")
		if wl2:
			wl2.get_child(0).set_text("[center]YOU LOSE :([/center]")
			wl2.visible = true

# ===== Game plugin ingest =====
func _set_game_data(new_replay: String) -> void:
	var data_raw: Variant = JSON.parse_string(new_replay)
	if typeof(data_raw) != TYPE_DICTIONARY:
		return
	var data: Dictionary = data_raw

	isTurn    = bool(data.get("isYourTurn", false))
	player    = int(data.get("player", 0))   # 1=red, 2=black
	replay    = String(data.get("replay", ""))
	mode      = String(data.get("mode", "n"))
	my_player = String(data.get("myPlayerId", ""))

	var p1_id: String = String(data.get("player1", ""))
	var p2_id: String = String(data.get("player2", ""))
	var opponent_avatar_key: String = ""

	# Resolve my color if IDs are present
	if my_player != "" and p1_id != "" and p2_id != "":
		if my_player == p1_id:
			player = 1
		elif my_player == p2_id:
			player = 2
		else:
			player = 0
			spectator_mode = true
			if is_instance_valid(spec_label):
				spec_label.visible = true
			if is_instance_valid(you_label):
				you_label.visible = false

	# Load opponent avatar if provided
	if player == 1:
		opponent_avatar_key = "avatar2"
	elif player == 2:
		opponent_avatar_key = "avatar1"

	if opponent_avatar_key != "" and data.has(opponent_avatar_key):
		var avatar_string: String = String(data[opponent_avatar_key])
		var opponent_data: Dictionary = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	_ready()

# ===== Export replay =====
func export_replay() -> String:
	var board: Array[String] = []
	for i in range(0, 64):
		board.append("0")

	for y in range(0, 8):
		for x in range(0, 8):
			var piece := get_node_or_null("PiecesRoot/" + str(x) + "," + str(7 - y)) as Sprite2D
			if piece != null:
				var color := get_piece_color(piece)
				if color == "red":
					board[(7 - y) * 8 + x] = "3" if is_checker_king(piece) else "1"
				elif color == "black":
					board[(7 - y) * 8 + x] = "4" if is_checker_king(piece) else "2"

	var boardStr := ""
	for val in board:
		boardStr += val + ","

	var move_str := "|"
	for i in range(0, prev_moves.size(), 2):
		var moveType := "attack" if abs(prev_moves[i].x - prev_moves[i + 1].x) > 1 else "move"
		move_str += moveType + ":" + str(int(prev_moves[i].x)) + "," + str(int(prev_moves[i].y)) + "," + str(int(prev_moves[i + 1].x)) + "," + str(int(prev_moves[i + 1].y)) + "|"

	clear_highlights()
	clicked_piece = null
	has_moved = false
	moves.clear()
	prev_jumps.clear()
	prev_moves.clear()
	var undo_btn := get_node_or_null("../UndoButton") as Button
	var send_btn := get_node_or_null("../SendButton") as Button
	if undo_btn: undo_btn.disabled = true
	if send_btn: send_btn.disabled = true
	set_waiting(true)

	var result: Dictionary = {
		"replay": replay.split("|")[-1] + move_str + "board:" + boardStr.substr(0, boardStr.length() - 1)
	}

	var win_loss_state := check_win_loss()
	if win_loss_state != "":
		result["winner"] = my_player + "|" + ("1" if win_loss_state == "win" else "-1")

	return JSON.stringify(result)

func check_win_loss() -> String:
	var num_your_pieces := 0
	var num_other_pieces := 0
	for y in range(0, 8):
		for x in range(0, 8):
			var piece := get_node_or_null("PiecesRoot/" + str(x) + "," + str(7 - y)) as Sprite2D
			if piece != null:
				if check_player(piece):
					num_your_pieces += 1
				else:
					num_other_pieces += 1
	if num_your_pieces == 0:
		return "lose"
	if num_other_pieces == 0:
		return "win"
	return ""

# During replay, convert jumped piece lookup to screen coords if player==1 (red).
func jump_piece(prevX: int, prevY: int, newX: int, newY: int, anim_delay: float = 0.0, replay_mode: bool = false) -> void:
	var x_step := 1 if newX > prevX else -1
	var y_step := 1 if newY > prevY else -1
	var jx := prevX + x_step
	var jy := prevY + y_step
	if replay_mode and player == 1:
		jx = 7 - jx
		jy = 7 - jy
	var jumpedPiece := get_node_or_null("PiecesRoot/" + str(jx) + "," + str(jy)) as Sprite2D
	if jumpedPiece != null:
		var tween := jumpedPiece.get_tree().create_tween()
		var modulate_color := jumpedPiece.self_modulate
		modulate_color.a = 0.0
		tween.tween_interval(anim_delay)
		tween.tween_property(jumpedPiece, "self_modulate", modulate_color, 0.5).set_trans(Tween.TRANS_LINEAR)
		jumpedPiece.name = str(jx) + "," + str(jy) + "_jumped"
		if not replay_mode:
			prev_jumps.append(jumpedPiece)

func move_piece(piece: Sprite2D, x: int, y: int, anim_delay: float = 0.0) -> void:
	var newPos := _cell_pos(x, y)
	var tween := piece.get_tree().create_tween()
	tween.tween_interval(anim_delay)
	tween.tween_property(piece, "position", newPos, 0.5).set_trans(Tween.TRANS_SINE)
	var color := get_piece_color(piece)
	if (color == "black" and (7 - y) == 7) or (color == "red" and (7 - y) == 0):
		tween.tween_callback(set_checker_king.bind(piece, color))
	piece.name = str(x) + "," + str(7 - y)

func set_checker_king(piece: Sprite2D, color: String, undo: bool = false) -> void:
	if color == "red":
		piece.texture = red_normal_texture if undo else red_king_texture
	elif color == "black":
		piece.texture = black_normal_texture if undo else black_king_texture
	_apply_piece_scale(piece)

func is_checker_king(piece: Sprite2D) -> bool:
	return piece.texture.resource_path.contains("king")

func getPiecePos(piece: Sprite2D) -> Vector2:
	var posStr := piece.name.split(",")
	return Vector2(int(posStr[0]), int(posStr[1]))

# ---- Minimal highlights (no BoardHighlight dependency) ----
func add_highlight(x: int, y: int) -> void:
	# Optional: draw a faint square under the target cell.
	# For now, keep API but skip visuals to avoid asset dependencies.
	var marker := Node2D.new()
	marker.name = "hl_%d_%d" % [x, y]
	marker.position = _cell_pos(x, y)
	add_child(marker)
	highlights.append(marker)

func clear_highlights() -> void:
	for n in highlights:
		if is_instance_valid(n):
			n.queue_free()
	highlights.clear()

func get_piece_color(piece: Sprite2D) -> String:
	if piece.texture.resource_path.contains("red"):
		return "red"
	elif piece.texture.resource_path.contains("black"):
		return "black"
	return "unknown"

func gen_moves(first_move: bool = false) -> void:
	if not first_move:
		moves.clear()

	var diagonals: Array[Vector2] = []
	var color := get_piece_color(clicked_piece)
	var isKing := is_checker_king(clicked_piece)
	if color == "black" or isKing:
		diagonals.append(Vector2(-1, 1))
		diagonals.append(Vector2(1, 1))
	if color == "red" or isKing:
		diagonals.append(Vector2(1, -1))
		diagonals.append(Vector2(-1, -1))

	for diagonal in diagonals:
		var clickedPiecePos := getPiecePos(clicked_piece)
		var pos := Vector2(clickedPiecePos.x + diagonal.x, clickedPiecePos.y + diagonal.y)
		if (pos.x >= 0 and pos.x <= 7) and (pos.y >= 0 and pos.y <= 7):
			var piece := get_node_or_null("PiecesRoot/" + str(int(pos.x)) + "," + str(int(pos.y))) as Sprite2D
			if piece == null:
				if not checking_for_jumps:
					if prev_moves.size() > 0:
						continue
					moves[pos] = clicked_piece
					add_highlight(pos.x, 7 - pos.y)
			elif not check_player(piece) and (prev_moves.size() / 2 == prev_jumps.size()):
				var x_step := 1 if pos.x > clickedPiecePos.x else -1
				var y_step := 1 if pos.y > clickedPiecePos.y else -1
				var newPos2 := Vector2(pos.x + x_step, pos.y + y_step)
				if (newPos2.x >= 0 and newPos2.x <= 7) and (newPos2.y >= 0 and newPos2.y <= 7):
					if get_node_or_null("PiecesRoot/" + str(int(newPos2.x)) + "," + str(int(newPos2.y))) == null:
						moves[newPos2] = clicked_piece
						add_highlight(newPos2.x, 7 - newPos2.y)

func undo_move() -> void:
	clear_highlights()
	for i in range(prev_moves.size(), 0, -2):
		move_piece(clicked_piece, prev_moves[i - 2].x, abs(prev_moves[i - 2].y - 7), (prev_moves.size() - i) * 0.25)

	var color := get_piece_color(clicked_piece)
	if (color == "black" and prev_moves[-1].y == 7) or (color == "red" and prev_moves[-1].y == 0):
		set_checker_king(clicked_piece, color, true)

	for i in range(prev_jumps.size() - 1, -1, -1):
		var prev_jump := prev_jumps[i]
		var tween := prev_jump.get_tree().create_tween()
		var modulate_color := prev_jump.self_modulate
		modulate_color.a = 1.0
		tween.tween_interval((prev_jumps.size() - 1 - i) * 0.5)
		tween.tween_property(prev_jump, "self_modulate", modulate_color, 0.5).set_trans(Tween.TRANS_LINEAR)
		prev_jump.name = prev_jump.name.split("_")[0]
	clicked_piece = null
	has_moved = false
	prev_jumps.clear()
	prev_moves.clear()
	var undo_btn := get_node_or_null("../UndoButton") as Button
	var send_btn := get_node_or_null("../SendButton") as Button
	if undo_btn: undo_btn.disabled = true
	if send_btn: send_btn.disabled = true

# Player 1 controls RED; Player 2 controls BLACK.
func check_player(piece: Sprite2D) -> bool:
	var color := get_piece_color(piece)
	if player == 1 and color == "red":
		return true
	if player == 2 and color == "black":
		return true
	return false

# ===== Input =====
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not waitingForOpponent:
			var gx := int(floor((event.position.x - board_origin.x) / float(cell_px)))
			var gy := int(floor((event.position.y - board_origin.y) / float(cell_px)))
			if gx < 0 or gx > 7 or gy < 0 or gy > 7:
				return

			var clickedPiece := get_node_or_null("PiecesRoot/" + str(gx) + "," + str(7 - gy)) as Sprite2D
			if must_jump != true and clickedPiece != null and (clicked_piece == null or has_moved == false):
				if check_player(clickedPiece):
					clear_highlights()
					clicked_piece = clickedPiece
					add_highlight(gx, gy)
					gen_moves()
			elif clicked_piece != null and moves.has(Vector2(gx, 7 - gy)):
				clicked_piece = moves[Vector2(gx, 7 - gy)]
				var prevPiecePos := getPiecePos(clicked_piece)
				move_piece(clicked_piece, gx, gy)
				clear_highlights()
				has_moved = true
				prev_moves.append(prevPiecePos)
				prev_moves.append(Vector2(gx, 7 - gy))
				if abs(prev_moves[-2].x - prev_moves[-1].x) > 1:
					jump_piece(prev_moves[-2].x, prev_moves[-2].y, prev_moves[-1].x, prev_moves[-1].y)
				gen_moves()
				var undo_btn := get_node_or_null("../UndoButton") as Button
				var send_btn := get_node_or_null("../SendButton") as Button
				if not must_jump and undo_btn:
					undo_btn.disabled = false
				if send_btn:
					send_btn.disabled = false

# ===== Rules popup (with click-suppression) =====
func _on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return

	rules_button.pivot_offset = rules_button.size / 2.0
	var tween := create_tween()
	tween.tween_property(rules_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(rules_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var popup := RULES_POPUP_SCENE.instantiate()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_gui_input_rules)

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)

	var close_btn := popup.find_child("CloseButton", true, false)
	if close_btn:
		close_btn.pressed.connect(_on_rules_close_pressed.bind(dim, popup))

	var title_label := popup.find_child("Title", true, false) as Label
	if title_label:
		title_label.text = "How to Play Checkers"

	var rules_label := popup.find_child("RulesLabel", true, false) as RichTextLabel
	if rules_label:
		rules_label.bbcode_enabled = true
		rules_label.visible = true
		rules_label.fit_content = true
		rules_label.scroll_active = false
		rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rules_label.text = "[b]Goal[/b]: Capture all opponent pieces or block all their moves.\n[b]Moves[/b]: Diagonal forward unless kinged. Jumps are mandatory when available.\n[b]Kings[/b]: Reach the far row to crown."

	popup.set_as_top_level(true)
	popup.visible = true
	await get_tree().process_frame

	var viewport_size := get_viewport_rect().size
	var desired_width := viewport_size.x * 0.9
	var desired_height: float = popup.get_combined_minimum_size().y
	popup.size = Vector2(desired_width, desired_height)
	popup.set_pivot_offset(popup.size / 2)
	popup.position = (viewport_size / 2) - (popup.size / 2)
	popup.scale = Vector2.ZERO

	var popup_tween := create_tween()
	popup_tween.tween_property(popup, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	popup.grab_focus()

func _on_dim_gui_input_rules(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		suppress_next_click = true
		get_viewport().set_input_as_handled()

func _on_rules_close_pressed(dim: ColorRect, popup: Control) -> void:
	suppress_next_click = true
	if is_instance_valid(dim):
		dim.queue_free()
	if is_instance_valid(popup):
		popup.queue_free()

# ===== Settings popup (with click-suppression) =====
func _on_settings_button_pressed() -> void:
	if not is_instance_valid(settings_button):
		return
	settings_button.pivot_offset = settings_button.size / 2.0
	var tween := create_tween()
	tween.tween_property(settings_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(settings_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var popup_instance := SETTINGS_POPUP_SCENE.instantiate()
	var settings_popup_script := popup_instance as SettingsPopup

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup_instance)
	popup_instance.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)

	settings_popup_script.setup_popup(dim)

	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_gui_input_settings)

	var custom_settings_title := popup_instance.find_child("CustomSettingsTitleLabel", true)
	var cst_label := custom_settings_title as Label
	if cst_label != null:
		var has_children := false
		if settings_popup_script and settings_popup_script.custom_settings_container:
			has_children = settings_popup_script.custom_settings_container.get_child_count() > 0
		cst_label.visible = has_children

	settings_popup_script.closed.connect(_on_settings_closed)
	settings_popup_script.settings_theme_selected.connect(_on_settings_theme_selected)
	settings_popup_script.dark_mode_changed.connect(_on_dark_mode_changed)

	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await get_tree().process_frame

	var viewport_size := get_viewport_rect().size
	var desired_width := viewport_size.x * 0.95
	var desired_height: float = popup_instance.get_combined_minimum_size().y
	popup_instance.size = Vector2(desired_width, desired_height)
	popup_instance.position = Vector2((viewport_size.x - desired_width) / 2, viewport_size.y)

	var bottom_offset := 50
	var target_y_position := viewport_size.y - desired_height - bottom_offset
	var target_position := Vector2((viewport_size.x - desired_width) / 2, target_y_position)

	var popup_tween := create_tween()
	popup_tween.tween_property(popup_instance, "position", target_position, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	popup_instance.grab_focus()

func _on_dim_gui_input_settings(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		suppress_next_click = true
		get_viewport().set_input_as_handled()

func _on_settings_closed() -> void:
	suppress_next_click = true
	if is_instance_valid(player_avatar_display):
		player_avatar_display.update_display_from_settings()

func _on_settings_theme_selected(_name: String) -> void:
	# no-op hook (theme changes handled by SettingsPopup internally or elsewhere)
	pass

func _on_dark_mode_changed(_is_dark: bool) -> void:
	# hook for dark mode if you want to update background colors
	pass

# Swallow exactly one click after closing a popup, so it doesn't move/delete a piece.
func _unhandled_input(event: InputEvent) -> void:
	if suppress_next_click and event is InputEventMouseButton and event.pressed:
		suppress_next_click = false
		get_viewport().set_input_as_handled()

# ===== Avatar parser (ported, no inline lambdas) =====
func _read_color(vals: Array) -> Color:
	if vals.size() >= 3:
		return Color(vals[0].to_float(), vals[1].to_float(), vals[2].to_float())
	return Color.WHITE

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
				data["fshape_color"] = _read_color(key_value.slice(1))
			"hair":
				var i2 := key_value[1].to_int()
				if i2 >= 0 and i2 < hair_map.size():
					data["hair_style"] = String(hair_map[i2])
			"hair_color":
				data["hair_color"] = _read_color(key_value.slice(1))
			"eyes":
				var i3 := key_value[1].to_int()
				if i3 >= 0 and i3 < eyes_map.size():
					data["eyes_style"] = String(eyes_map[i3])
			"mouth":
				var i4 := key_value[1].to_int()
				if i4 >= 0 and i4 < mouth_map.size():
					data["mouth_style"] = String(mouth_map[i4])
			"clothes":
				var i5 := key_value[1].to_int()
				if i5 >= 0 and i5 < clothing_map.size():
					data["clothing_style"] = String(clothing_map[i5])
			"clothes_color":
				data["clothing_color"] = _read_color(key_value.slice(1))
			"bg_color":
				data["bg_color"] = _read_color(key_value.slice(1))
			"backdrop":
				var i6 := key_value[1].to_int()
				if i6 >= 0 and i6 < backdrop_map.size():
					data["bg_style"] = String(backdrop_map[i6])
			_:
				pass
	return data

func _process(_delta: float) -> void:
	pass
