class_name ChessBoard
extends RefCounted

## Chess board state management.
## Handles board representation, move execution, and state tracking.

## Board state
var board: Array = []  # 8x8 array of piece strings ("wP", "bK", "", etc.)
var turn: String = "w"  # "w" or "b"
var castling: String = "KQkq"  # Castling rights
var en_passant: String = "-"  # En passant target square or "-"
var halfmove: int = 0  # Halfmove clock (50-move rule)
var fullmove: int = 1  # Full move counter

## Position history for repetition detection
var position_counts: Dictionary = {}

## Previous board state (for replay generation)
var prev_board_gp: String = ""

## Last move info (for highlighting)
var last_move_from: Vector2i = Vector2i(-1, -1)
var last_move_to: Vector2i = Vector2i(-1, -1)

## Promotion piece for the last move (if any)
var last_promotion_piece: String = ""

## Pending move state (for undo before send)
var _pending_snapshot: Dictionary = {}
var _pending_from: Vector2i = Vector2i(-1, -1)
var _pending_to: Vector2i = Vector2i(-1, -1)

## Constructor - initializes with starting position
func _init(start_position: bool = true) -> void:
	if start_position:
		reset_to_starting_position()
	else:
		_init_empty_board()

## Initialize an empty 8x8 board
func _init_empty_board() -> void:
	board.clear()
	for _r in range(8):
		var row: Array[String] = []
		for _f in range(8):
			row.append("")
		board.append(row)

## Reset the board to the standard starting position
func reset_to_starting_position() -> void:
	var starting_gp: String = ChessNotation.get_default_position_gp()
	board = ChessNotation.gp_array_to_board(starting_gp)
	turn = "w"
	castling = "KQkq"
	en_passant = "-"
	halfmove = 0
	fullmove = 1
	position_counts.clear()
	prev_board_gp = ""
	last_move_from = Vector2i(-1, -1)
	last_move_to = Vector2i(-1, -1)
	last_promotion_piece = ""
	_count_position()

## Load board from GamePigeon format
func load_from_gp(gp_array_str: String) -> void:
	board = ChessNotation.gp_array_to_board(gp_array_str)
	if board.is_empty():
		_init_empty_board()
	# Infer castling rights from board position
	castling = ChessNotation.infer_castling_rights(board)
	_count_position()

## Get piece at a position
func get_piece(pos: Vector2i) -> String:
	if not ChessPiece.is_in_bounds(pos):
		return ""
	return board[pos.y][pos.x]

## Get piece at rank and file
func get_piece_rf(rank: int, file: int) -> String:
	if not ChessPiece.is_in_bounds_rf(rank, file):
		return ""
	return board[rank][file]

## Set piece at a position
func set_piece(pos: Vector2i, piece: String) -> void:
	if ChessPiece.is_in_bounds(pos):
		board[pos.y][pos.x] = piece

## Check if a position is empty
func is_empty(pos: Vector2i) -> bool:
	return get_piece(pos) == ""

## Find the king position for a side
func find_king(side: String) -> Vector2i:
	return ChessEngine.find_king(board, side)

## Check if the current side is in check
func is_in_check() -> bool:
	return ChessEngine.is_in_check(board, turn)

## Get legal moves for a piece at the given position
func get_legal_moves(from_sq: Vector2i) -> Array[Vector2i]:
	return ChessEngine.get_legal_moves(board, from_sq, turn, en_passant, castling)

## Execute a move on the board (modifies state)
## Returns a dictionary with move details
func execute_move(from_sq: Vector2i, to_sq: Vector2i, promotion_piece: String = "") -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"piece": "",
		"captured": "",
		"is_capture": false,
		"is_castle": false,
		"is_en_passant": false,
		"is_promotion": false,
		"castle_rook_from": Vector2i(-1, -1),
		"castle_rook_to": Vector2i(-1, -1),
		"en_passant_capture": Vector2i(-1, -1),
		"new_en_passant": "-"
	}

	var moving: String = get_piece(from_sq)
	if moving == "":
		return result

	var target: String = get_piece(to_sq)
	var side: String = moving[0]
	var ptype: String = moving[1]

	# Save previous board state for replay
	prev_board_gp = ChessNotation.board_to_gp_array(board)

	result["piece"] = moving
	result["captured"] = target
	result["success"] = true

	# Reset en passant (will be set if this is a pawn double-push)
	var old_en_passant: String = en_passant
	en_passant = "-"

	# Handle en passant capture
	if ptype == "P" and target == "" and from_sq.x != to_sq.x:
		var dir: int = 1 if side == "w" else -1
		var cap_pos: Vector2i = Vector2i(to_sq.x, to_sq.y - dir)
		result["captured"] = get_piece(cap_pos)
		result["is_en_passant"] = true
		result["en_passant_capture"] = cap_pos
		result["is_capture"] = true
		set_piece(cap_pos, "")
	elif target != "":
		result["is_capture"] = true

	# Move the piece
	set_piece(to_sq, moving)
	set_piece(from_sq, "")

	# Handle pawn double-push (set en passant target)
	if ptype == "P" and abs(to_sq.y - from_sq.y) == 2:
		var dir: int = 1 if side == "w" else -1
		var ep_rank: int = from_sq.y + dir
		en_passant = ChessNotation.FILE_RANKS[to_sq.x] + str(ep_rank + 1)
		result["new_en_passant"] = en_passant

	# Handle promotion
	if ptype == "P":
		var promo_rank: int = 7 if side == "w" else 0
		if to_sq.y == promo_rank:
			var promo_piece: String = promotion_piece if promotion_piece != "" else "Q"
			set_piece(to_sq, side + promo_piece)
			result["is_promotion"] = true
			last_promotion_piece = promo_piece

	# Handle castling
	if ptype == "K":
		# Remove castling rights for this side
		if side == "w":
			castling = castling.replace("K", "").replace("Q", "")
		else:
			castling = castling.replace("k", "").replace("q", "")

		# Move rook if this is a castling move
		if abs(to_sq.x - from_sq.x) == 2:
			result["is_castle"] = true
			if to_sq.x == 6:  # Kingside
				result["castle_rook_from"] = Vector2i(7, to_sq.y)
				result["castle_rook_to"] = Vector2i(5, to_sq.y)
				set_piece(Vector2i(5, to_sq.y), side + "R")
				set_piece(Vector2i(7, to_sq.y), "")
			elif to_sq.x == 2:  # Queenside
				result["castle_rook_from"] = Vector2i(0, to_sq.y)
				result["castle_rook_to"] = Vector2i(3, to_sq.y)
				set_piece(Vector2i(3, to_sq.y), side + "R")
				set_piece(Vector2i(0, to_sq.y), "")

	# Handle rook moves (update castling rights)
	if ptype == "R":
		if from_sq == Vector2i(0, 7): castling = castling.replace("Q", "")
		elif from_sq == Vector2i(7, 7): castling = castling.replace("K", "")
		elif from_sq == Vector2i(0, 0): castling = castling.replace("q", "")
		elif from_sq == Vector2i(7, 0): castling = castling.replace("k", "")

	# Handle rook captures (update opponent's castling rights)
	if result["captured"] == "bR":
		if to_sq == Vector2i(0, 0): castling = castling.replace("q", "")
		elif to_sq == Vector2i(7, 0): castling = castling.replace("k", "")
	elif result["captured"] == "wR":
		if to_sq == Vector2i(0, 7): castling = castling.replace("Q", "")
		elif to_sq == Vector2i(7, 7): castling = castling.replace("K", "")

	# Update halfmove clock
	if ptype == "P" or result["is_capture"]:
		halfmove = 0
	else:
		halfmove += 1

	# Store last move info
	last_move_from = from_sq
	last_move_to = to_sq

	return result

## Commit the move (switch turns, update fullmove counter)
func commit_move() -> void:
	# Switch turn
	turn = ChessPiece.opposite_side(turn)

	# Update fullmove counter
	if turn == "w":
		fullmove += 1

	# Count position for repetition
	_count_position()

## Undo the last move by restoring from a snapshot
func restore_from_snapshot(snapshot: Dictionary) -> void:
	board = ChessNotation.clone_board(snapshot["board"])
	turn = snapshot["turn"]
	castling = snapshot["castling"]
	en_passant = snapshot["en_passant"]
	halfmove = snapshot["halfmove"]
	fullmove = snapshot["fullmove"]
	position_counts = snapshot["position_counts"].duplicate(true)

## Create a snapshot of the current state
func create_snapshot() -> Dictionary:
	return {
		"board": ChessNotation.clone_board(board),
		"turn": turn,
		"castling": castling,
		"en_passant": en_passant,
		"halfmove": halfmove,
		"fullmove": fullmove,
		"position_counts": position_counts.duplicate(true)
	}

## Count the current position for repetition detection
func _count_position() -> void:
	var key: String = ChessNotation.to_position_key(board, turn, castling, en_passant)
	position_counts[key] = int(position_counts.get(key, 0)) + 1

# ============================================================================
# PENDING MOVE MANAGEMENT
# ============================================================================

## Check if there's a pending move waiting to be sent
func has_pending() -> bool:
	return _pending_from != Vector2i(-1, -1) and _pending_to != Vector2i(-1, -1)

## Set a pending move (call before executing the move)
func set_pending(from_sq: Vector2i, to_sq: Vector2i) -> void:
	_pending_snapshot = create_snapshot()
	_pending_from = from_sq
	_pending_to = to_sq

## Clear pending move state
func clear_pending() -> void:
	_pending_snapshot = {}
	_pending_from = Vector2i(-1, -1)
	_pending_to = Vector2i(-1, -1)

## Get the pending move origin square
func get_pending_from() -> Vector2i:
	return _pending_from

## Get the pending move destination square
func get_pending_to() -> Vector2i:
	return _pending_to

## Undo the pending move by restoring the snapshot
## Returns true if there was a pending move to undo
func undo_pending() -> bool:
	if not has_pending():
		return false
	if _pending_snapshot.size() > 0:
		restore_from_snapshot(_pending_snapshot)
	clear_pending()
	return true

## Evaluate the current game state
func evaluate_state() -> Dictionary:
	return ChessEngine.evaluate_position(board, turn, en_passant, castling, halfmove, position_counts)

## Get the current board in GamePigeon format
func to_gp_array() -> String:
	return ChessNotation.board_to_gp_array(board)

## Generate a replay string for the last move
func generate_replay(from_sq: Vector2i, to_sq: Vector2i) -> String:
	var current_gp: String = to_gp_array()
	return ChessNotation.to_gp_replay(prev_board_gp, from_sq, to_sq, current_gp)

## String representation for debugging
func _to_string() -> String:
	var s: String = "ChessBoard (turn: %s, fullmove: %d)\n" % [turn, fullmove]
	s += "  a b c d e f g h\n"
	for r in range(7, -1, -1):
		s += str(r + 1) + " "
		for f in range(8):
			var p: String = board[r][f]
			s += (p if p != "" else ".") + " "
		s += str(r + 1) + "\n"
	s += "  a b c d e f g h\n"
	s += "Castling: %s, En passant: %s, Halfmove: %d" % [castling, en_passant, halfmove]
	return s
