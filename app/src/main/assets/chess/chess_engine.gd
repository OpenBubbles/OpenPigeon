class_name ChessEngine
extends RefCounted

## Chess engine for move validation, check detection, and game state evaluation.
## Works with an 8x8 board array of piece strings ("wP", "bK", "", etc.)

## Game state result from evaluation
enum GameState { ONGOING, CHECK, CHECKMATE, STALEMATE, DRAW_INSUFFICIENT, DRAW_FIFTY_MOVE, DRAW_REPETITION }

# ============================================================================
# MOVE UNDO DATA STRUCTURE
# ============================================================================

## Information needed to unmake a move - enables efficient in-place make/unmake
## instead of cloning the entire board for each legal move check.
class MoveUndo:
	var from_sq: Vector2i
	var to_sq: Vector2i
	var moving_piece: String
	var captured_piece: String
	var captured_pos: Vector2i      # Different from to_sq for en passant captures
	var rook_from: Vector2i         # For castling: where the rook came from
	var rook_to: Vector2i           # For castling: where the rook moved to
	var was_promotion: bool         # If pawn was promoted
	var promoted_to: String         # What piece it promoted to (for unmake)

	func _init() -> void:
		from_sq = Vector2i(-1, -1)
		to_sq = Vector2i(-1, -1)
		moving_piece = ""
		captured_piece = ""
		captured_pos = Vector2i(-1, -1)
		rook_from = Vector2i(-1, -1)
		rook_to = Vector2i(-1, -1)
		was_promotion = false
		promoted_to = ""

# ============================================================================
# MAKE/UNMAKE MOVE FUNCTIONS (Performance optimization)
# ============================================================================

## Apply move to board in-place, return undo info for later reversal
## This is ~10-50x faster than cloning the board for each move check
static func _make_move(board: Array, from_sq: Vector2i, to_sq: Vector2i, en_passant: String) -> MoveUndo:
	var undo := MoveUndo.new()
	undo.from_sq = from_sq
	undo.to_sq = to_sq
	undo.moving_piece = board[from_sq.y][from_sq.x]
	undo.captured_piece = board[to_sq.y][to_sq.x]
	undo.captured_pos = to_sq  # Default: capture at destination

	if undo.moving_piece == "":
		return undo  # Invalid move, return empty undo

	var side: String = undo.moving_piece[0]
	var ptype: String = undo.moving_piece[1]

	# Handle en passant capture: pawn moves diagonally to empty square
	if ptype == "P" and undo.captured_piece == "" and from_sq.x != to_sq.x:
		var dir: int = 1 if side == "w" else -1
		undo.captured_pos = Vector2i(to_sq.x, to_sq.y - dir)
		undo.captured_piece = board[undo.captured_pos.y][undo.captured_pos.x]
		board[undo.captured_pos.y][undo.captured_pos.x] = ""

	# Move the piece
	board[to_sq.y][to_sq.x] = undo.moving_piece
	board[from_sq.y][from_sq.x] = ""

	# Handle castling rook movement
	if ptype == "K" and abs(to_sq.x - from_sq.x) == 2:
		if to_sq.x == 6:  # Kingside
			undo.rook_from = Vector2i(7, to_sq.y)
			undo.rook_to = Vector2i(5, to_sq.y)
		else:  # Queenside (to_sq.x == 2)
			undo.rook_from = Vector2i(0, to_sq.y)
			undo.rook_to = Vector2i(3, to_sq.y)
		board[undo.rook_to.y][undo.rook_to.x] = board[undo.rook_from.y][undo.rook_from.x]
		board[undo.rook_from.y][undo.rook_from.x] = ""

	# Handle pawn promotion (default to queen for legality testing)
	# Board orientation: rank 0 = white's back rank, rank 7 = black's back rank
	# White pawns promote at rank 7, black pawns promote at rank 0
	if ptype == "P":
		var promo_rank: int = 7 if side == "w" else 0
		if to_sq.y == promo_rank:
			undo.was_promotion = true
			undo.promoted_to = side + "Q"  # Default to queen
			board[to_sq.y][to_sq.x] = undo.promoted_to

	return undo

## Restore board to state before move using undo info
## Must be called with the exact undo returned from _make_move
static func _unmake_move(board: Array, undo: MoveUndo) -> void:
	if undo.moving_piece == "":
		return  # Invalid undo, nothing to restore

	# Undo castling rook movement first
	if undo.rook_from.x != -1:
		board[undo.rook_from.y][undo.rook_from.x] = board[undo.rook_to.y][undo.rook_to.x]
		board[undo.rook_to.y][undo.rook_to.x] = ""

	# Restore moving piece to original position (undo any promotion)
	board[undo.from_sq.y][undo.from_sq.x] = undo.moving_piece

	# Clear destination (or restore promoted piece position)
	board[undo.to_sq.y][undo.to_sq.x] = ""

	# Restore captured piece at its original position
	# (For en passant, captured_pos differs from to_sq)
	if undo.captured_piece != "":
		board[undo.captured_pos.y][undo.captured_pos.x] = undo.captured_piece

# ============================================================================
# CORE ENGINE FUNCTIONS
# ============================================================================

## Find the king position for a given side
static func find_king(board: Array, side: String) -> Vector2i:
	var king_code: String = side + "K"
	for r in range(8):
		for f in range(8):
			if board[r][f] == king_code:
				return Vector2i(f, r)
	return Vector2i(-1, -1)

## Check if a square is attacked by pieces of the given attacker side
static func is_square_attacked(board: Array, rank: int, file: int, attacker_side: String) -> bool:
	# Knight attacks
	var knight_moves: Array = [[1,2],[2,1],[-1,2],[-2,1],[1,-2],[2,-1],[-1,-2],[-2,-1]]
	for m in knight_moves:
		var nf: int = file + m[0]
		var nr: int = rank + m[1]
		if ChessPiece.is_in_bounds_rf(nr, nf) and board[nr][nf] == attacker_side + "N":
			return true

	# King attacks (for adjacent squares)
	for dr in range(-1, 2):
		for df in range(-1, 2):
			if dr == 0 and df == 0:
				continue
			var nf: int = file + df
			var nr: int = rank + dr
			if ChessPiece.is_in_bounds_rf(nr, nf) and board[nr][nf] == attacker_side + "K":
				return true

	# Diagonal attacks (bishop/queen)
	var diag_dirs: Array = [[1,1], [1,-1], [-1,1], [-1,-1]]
	for d in diag_dirs:
		var nf: int = file + d[0]
		var nr: int = rank + d[1]
		while ChessPiece.is_in_bounds_rf(nr, nf):
			var piece: String = board[nr][nf]
			if piece != "":
				if piece[0] == attacker_side and (piece[1] == "B" or piece[1] == "Q"):
					return true
				break
			nf += d[0]
			nr += d[1]

	# Orthogonal attacks (rook/queen)
	var ortho_dirs: Array = [[1,0], [-1,0], [0,1], [0,-1]]
	for d in ortho_dirs:
		var nf: int = file + d[0]
		var nr: int = rank + d[1]
		while ChessPiece.is_in_bounds_rf(nr, nf):
			var piece: String = board[nr][nf]
			if piece != "":
				if piece[0] == attacker_side and (piece[1] == "R" or piece[1] == "Q"):
					return true
				break
			nf += d[0]
			nr += d[1]

	# Pawn attacks
	var pawn_dir: int = -1 if attacker_side == "w" else 1  # Direction pawns attack FROM
	for df in [-1, 1]:
		var nf: int = file + df
		var nr: int = rank + pawn_dir
		if ChessPiece.is_in_bounds_rf(nr, nf) and board[nr][nf] == attacker_side + "P":
			return true

	return false

## Check if the given side's king is in check
static func is_in_check(board: Array, side: String) -> bool:
	var king_pos: Vector2i = find_king(board, side)
	if king_pos.x == -1:
		return false
	var opp: String = ChessPiece.opposite_side(side)
	return is_square_attacked(board, king_pos.y, king_pos.x, opp)

## Get pseudo-legal moves for a piece at the given position
## These moves don't account for leaving the king in check
static func get_pseudo_legal_moves(board: Array, from_sq: Vector2i, en_passant: String, castling: String) -> Array[Vector2i]:
	var piece: String = board[from_sq.y][from_sq.x]
	if piece == "":
		return []

	var chess_piece: ChessPiece = ChessPiece.from_notation(piece, from_sq)
	if chess_piece == null:
		return []

	return chess_piece.get_pseudo_legal_moves(board, en_passant, castling)

## Get legal moves for a piece at the given position
## Filters pseudo-legal moves to exclude those that leave the king in check
## Uses efficient make/unmake pattern instead of cloning the board for each move
static func get_legal_moves(board: Array, from_sq: Vector2i, turn: String, en_passant: String, castling: String) -> Array[Vector2i]:
	var piece: String = board[from_sq.y][from_sq.x]
	if piece == "" or piece[0] != turn:
		return []

	var pseudo_moves: Array[Vector2i] = get_pseudo_legal_moves(board, from_sq, en_passant, castling)
	var legal_moves: Array[Vector2i] = []
	var opp: String = ChessPiece.opposite_side(turn)

	ChessDebug.trace("get_legal_moves: %s at %s, turn=%s, %d pseudo-legal moves" % [
		piece, ChessNotation.square_name(from_sq), turn, pseudo_moves.size()
	], "ENGINE")

	# Log king position before any moves
	var initial_king_pos: Vector2i = find_king(board, turn)
	ChessDebug.trace("  King position before moves: %s at %s" % [
		turn + "K", ChessNotation.square_name(initial_king_pos)
	], "ENGINE")

	for to_sq in pseudo_moves:
		var move_notation: String = "%s -> %s" % [
			ChessNotation.square_name(from_sq), ChessNotation.square_name(to_sq)
		]
		var target_piece: String = board[to_sq.y][to_sq.x]

		ChessDebug.trace("  Testing move: %s %s (target: '%s')" % [
			piece, move_notation, target_piece
		], "ENGINE")

		# Use make/unmake pattern for efficient in-place move testing
		var undo: MoveUndo = _make_move(board, from_sq, to_sq, en_passant)

		# Check if our king is in check after the move
		var king_pos: Vector2i = find_king(board, turn)
		var king_attacked: bool = is_square_attacked(board, king_pos.y, king_pos.x, opp)
		var is_legal: bool = king_pos.x != -1 and not king_attacked

		if not is_legal:
			if king_pos.x == -1:
				ChessDebug.trace("    -> REJECTED: King not found after move!", "ENGINE")
			else:
				ChessDebug.trace("    -> REJECTED: King at %s would be in check by %s" % [
					ChessNotation.square_name(king_pos), opp
				], "ENGINE")
				# Log what's attacking the king
				_log_attackers(board, king_pos.y, king_pos.x, opp)
		else:
			ChessDebug.trace("    -> King safe at %s" % ChessNotation.square_name(king_pos), "ENGINE")

		# Unmake the move to restore board state
		_unmake_move(board, undo)

		if is_legal:
			# Additional castling validation: king cannot castle through check
			# (Check this on the original board, not the modified one)
			if piece[1] == "K" and abs(to_sq.x - from_sq.x) == 2:
				# Check the squares the king passes through
				var step: int = 1 if to_sq.x > from_sq.x else -1
				var blocked: bool = false
				for check_f in range(from_sq.x, to_sq.x + step, step):
					if is_square_attacked(board, from_sq.y, check_f, opp):
						blocked = true
						break
				if not blocked:
					legal_moves.append(to_sq)
					ChessDebug.trace("    -> LEGAL (castling path clear)" , "ENGINE")
				else:
					ChessDebug.trace("    -> REJECTED: Castling through check", "ENGINE")
			else:
				legal_moves.append(to_sq)
				ChessDebug.trace("    -> LEGAL", "ENGINE")

	ChessDebug.trace("get_legal_moves: %s has %d legal moves" % [piece, legal_moves.size()], "ENGINE")
	return legal_moves

## Helper to log what pieces are attacking a square (for debugging)
static func _log_attackers(board: Array, rank: int, file: int, attacker_side: String) -> void:
	var sq_name: String = ChessNotation.square_name(Vector2i(file, rank))

	# Check knights
	var knight_moves: Array = [[1,2],[2,1],[-1,2],[-2,1],[1,-2],[2,-1],[-1,-2],[-2,-1]]
	for m in knight_moves:
		var nf: int = file + m[0]
		var nr: int = rank + m[1]
		if ChessPiece.is_in_bounds_rf(nr, nf) and board[nr][nf] == attacker_side + "N":
			ChessDebug.trace("      Attacker: %sN at %s (knight)" % [
				attacker_side, ChessNotation.square_name(Vector2i(nf, nr))
			], "ENGINE")

	# Check king
	for dr in range(-1, 2):
		for df in range(-1, 2):
			if dr == 0 and df == 0:
				continue
			var nf: int = file + df
			var nr: int = rank + dr
			if ChessPiece.is_in_bounds_rf(nr, nf) and board[nr][nf] == attacker_side + "K":
				ChessDebug.trace("      Attacker: %sK at %s (king)" % [
					attacker_side, ChessNotation.square_name(Vector2i(nf, nr))
				], "ENGINE")

	# Check diagonals (bishop/queen)
	var diag_dirs: Array = [[1,1], [1,-1], [-1,1], [-1,-1]]
	for d in diag_dirs:
		var nf: int = file + d[0]
		var nr: int = rank + d[1]
		while ChessPiece.is_in_bounds_rf(nr, nf):
			var p: String = board[nr][nf]
			if p != "":
				if p[0] == attacker_side and (p[1] == "B" or p[1] == "Q"):
					ChessDebug.trace("      Attacker: %s at %s (diagonal)" % [
						p, ChessNotation.square_name(Vector2i(nf, nr))
					], "ENGINE")
				break
			nf += d[0]
			nr += d[1]

	# Check orthogonals (rook/queen)
	var ortho_dirs: Array = [[1,0], [-1,0], [0,1], [0,-1]]
	for d in ortho_dirs:
		var nf: int = file + d[0]
		var nr: int = rank + d[1]
		while ChessPiece.is_in_bounds_rf(nr, nf):
			var p: String = board[nr][nf]
			if p != "":
				if p[0] == attacker_side and (p[1] == "R" or p[1] == "Q"):
					ChessDebug.trace("      Attacker: %s at %s (orthogonal)" % [
						p, ChessNotation.square_name(Vector2i(nf, nr))
					], "ENGINE")
				break
			nf += d[0]
			nr += d[1]

	# Check pawns
	var pawn_dir: int = -1 if attacker_side == "w" else 1
	for df in [-1, 1]:
		var nf: int = file + df
		var nr: int = rank + pawn_dir
		if ChessPiece.is_in_bounds_rf(nr, nf) and board[nr][nf] == attacker_side + "P":
			ChessDebug.trace("      Attacker: %sP at %s (pawn)" % [
				attacker_side, ChessNotation.square_name(Vector2i(nf, nr))
			], "ENGINE")

## Check if a side has any legal moves
## Uses early-exit optimization: returns true as soon as one legal move is found
static func side_has_legal_moves(board: Array, side: String, en_passant: String, castling: String) -> bool:
	var opp: String = ChessPiece.opposite_side(side)

	for r in range(8):
		for f in range(8):
			var piece: String = board[r][f]
			if piece == "" or piece[0] != side:
				continue

			var from_sq: Vector2i = Vector2i(f, r)
			var pseudo_moves: Array[Vector2i] = get_pseudo_legal_moves(board, from_sq, en_passant, castling)

			# Check each pseudo-legal move using efficient make/unmake
			for to_sq in pseudo_moves:
				var undo: MoveUndo = _make_move(board, from_sq, to_sq, en_passant)
				var king_pos: Vector2i = find_king(board, side)
				var is_legal: bool = king_pos.x != -1 and not is_square_attacked(board, king_pos.y, king_pos.x, opp)
				_unmake_move(board, undo)

				if is_legal:
					# For castling, also check the path isn't through check
					if piece[1] == "K" and abs(to_sq.x - from_sq.x) == 2:
						var step: int = 1 if to_sq.x > from_sq.x else -1
						var blocked: bool = false
						for check_f in range(from_sq.x, to_sq.x + step, step):
							if is_square_attacked(board, from_sq.y, check_f, opp):
								blocked = true
								break
						if not blocked:
							return true  # Found at least one legal move
					else:
						return true  # Found at least one legal move

	return false  # No legal moves found

## Check for insufficient mating material
static func is_insufficient_material(board: Array) -> bool:
	var white_pieces: Array[String] = []
	var black_pieces: Array[String] = []
	var white_bishop_colors: Array[int] = []
	var black_bishop_colors: Array[int] = []

	for r in range(8):
		for f in range(8):
			var piece: String = board[r][f]
			if piece == "":
				continue
			var ptype: String = piece[1]
			if piece[0] == "w":
				white_pieces.append(ptype)
				if ptype == "B":
					white_bishop_colors.append((r + f) % 2)
			else:
				black_pieces.append(ptype)
				if ptype == "B":
					black_bishop_colors.append((r + f) % 2)

	white_pieces.sort()
	black_pieces.sort()

	# King vs King
	if white_pieces == ["K"] and black_pieces == ["K"]:
		return true

	# King + Bishop vs King
	if white_pieces == ["B", "K"] and black_pieces == ["K"]:
		return true
	if white_pieces == ["K"] and black_pieces == ["B", "K"]:
		return true

	# King + Knight vs King
	if white_pieces == ["K", "N"] and black_pieces == ["K"]:
		return true
	if white_pieces == ["K"] and black_pieces == ["K", "N"]:
		return true

	# King + Bishop vs King + Bishop (same color bishops)
	if white_pieces == ["B", "K"] and black_pieces == ["B", "K"]:
		if white_bishop_colors.size() == 1 and black_bishop_colors.size() == 1:
			if white_bishop_colors[0] == black_bishop_colors[0]:
				return true

	return false

## Evaluate the current game state
## Returns a dictionary with:
##   - state: GameState enum value
##   - in_check: bool
##   - has_legal_moves: bool
##   - winner_side: String ("w", "b", or "" for draw/ongoing)
static func evaluate_position(board: Array, turn: String, en_passant: String, castling: String, halfmove: int, position_counts: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"state": GameState.ONGOING,
		"in_check": false,
		"has_legal_moves": true,
		"winner_side": ""
	}

	var in_check: bool = is_in_check(board, turn)
	var has_legal: bool = side_has_legal_moves(board, turn, en_passant, castling)

	result["in_check"] = in_check
	result["has_legal_moves"] = has_legal

	if in_check:
		result["state"] = GameState.CHECK

	# Check for insufficient material
	if is_insufficient_material(board):
		result["state"] = GameState.DRAW_INSUFFICIENT
		result["has_legal_moves"] = false
		return result

	# Check for checkmate or stalemate
	if not has_legal:
		if in_check:
			result["state"] = GameState.CHECKMATE
			result["winner_side"] = ChessPiece.opposite_side(turn)
		else:
			result["state"] = GameState.STALEMATE
		return result

	# Check for 50-move rule
	if halfmove >= 100:
		result["state"] = GameState.DRAW_FIFTY_MOVE
		return result

	# Check for threefold repetition
	for count in position_counts.values():
		if count >= 3:
			result["state"] = GameState.DRAW_REPETITION
			return result

	return result

## Get a human-readable description of the game state
static func state_description(state: GameState, winner_side: String = "") -> String:
	match state:
		GameState.ONGOING:
			return "Game in progress"
		GameState.CHECK:
			return "Check"
		GameState.CHECKMATE:
			var winner: String = "White" if winner_side == "w" else "Black"
			return "Checkmate - %s wins" % winner
		GameState.STALEMATE:
			return "Stalemate - Draw"
		GameState.DRAW_INSUFFICIENT:
			return "Draw - Insufficient material"
		GameState.DRAW_FIFTY_MOVE:
			return "Draw - 50-move rule"
		GameState.DRAW_REPETITION:
			return "Draw - Threefold repetition"
	return "Unknown state"

## Check if the game is over
static func is_game_over(state: GameState) -> bool:
	return state != GameState.ONGOING and state != GameState.CHECK
