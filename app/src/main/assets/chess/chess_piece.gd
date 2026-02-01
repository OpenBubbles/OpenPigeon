class_name ChessPiece
extends RefCounted

## Chess piece class with type, color, position, and movement validation.
## Handles piece-specific move generation and special moves.

## Piece type enumeration
enum PieceType { PAWN, ROOK, KNIGHT, BISHOP, QUEEN, KING }

## Piece color enumeration
enum PieceColor { WHITE, BLACK }

## Board bounds constants
const BOARD_MIN: int = 0
const BOARD_MAX: int = 7

## Piece properties
var type: PieceType
var color: PieceColor
var position: Vector2i  # Current location (file, rank)

## Movement patterns (relative translations)
var move_directions: Array[Vector2i] = []  # Directions for sliding pieces or single moves
var is_sliding: bool = false  # True for R, B, Q - they slide along directions

## State tracking
var has_moved: bool = false  # For castling/pawn double-push tracking

## Constructor
func _init(p_type: PieceType, p_color: PieceColor, p_position: Vector2i = Vector2i(-1, -1)) -> void:
	type = p_type
	color = p_color
	position = p_position
	has_moved = false
	_setup_movement_patterns()

## Setup movement patterns based on piece type
func _setup_movement_patterns() -> void:
	move_directions.clear()
	match type:
		PieceType.PAWN:
			is_sliding = false
			# Pawn moves are handled specially in get_pseudo_legal_moves()
			move_directions = []

		PieceType.ROOK:
			is_sliding = true
			move_directions = [
				Vector2i(1, 0), Vector2i(-1, 0),
				Vector2i(0, 1), Vector2i(0, -1)
			]

		PieceType.KNIGHT:
			is_sliding = false
			move_directions = [
				Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
				Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2)
			]

		PieceType.BISHOP:
			is_sliding = true
			move_directions = [
				Vector2i(1, 1), Vector2i(1, -1),
				Vector2i(-1, 1), Vector2i(-1, -1)
			]

		PieceType.QUEEN:
			is_sliding = true
			move_directions = [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
			]

		PieceType.KING:
			is_sliding = false
			move_directions = [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
			]

## Check if position is within board bounds
static func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= BOARD_MIN and pos.x <= BOARD_MAX and pos.y >= BOARD_MIN and pos.y <= BOARD_MAX

static func is_in_bounds_rf(rank: int, file: int) -> bool:
	return file >= BOARD_MIN and file <= BOARD_MAX and rank >= BOARD_MIN and rank <= BOARD_MAX

## Get the pawn movement direction based on color
## White pawns move in +y direction (toward rank 8), Black in -y direction
func get_pawn_direction() -> int:
	return 1 if color == PieceColor.WHITE else -1

## Get the starting rank for pawns of this color
func get_pawn_start_rank() -> int:
	return 1 if color == PieceColor.WHITE else 6

## Get the promotion rank for pawns of this color
func get_pawn_promotion_rank() -> int:
	return 7 if color == PieceColor.WHITE else 0

## Get the en passant capture rank for pawns of this color
func get_en_passant_rank() -> int:
	return 4 if color == PieceColor.WHITE else 3

## Get pseudo-legal moves for this piece (ignoring check)
## board: 8x8 array of piece strings ("wP", "bK", "", etc.)
## en_passant: en passant target square in algebraic notation ("-" if none)
## castling: castling rights string ("KQkq" format)
## Returns array of Vector2i destination squares
func get_pseudo_legal_moves(board: Array, en_passant: String = "-", castling: String = "-") -> Array[Vector2i]:
	var moves: Array[Vector2i] = []

	if type == PieceType.PAWN:
		moves = _get_pawn_moves(board, en_passant)
	elif type == PieceType.KING:
		moves = _get_king_moves(board, castling)
	elif is_sliding:
		moves = _get_sliding_moves(board)
	else:
		moves = _get_non_sliding_moves(board)

	return moves

## Get pawn moves (including captures, double push, en passant)
func _get_pawn_moves(board: Array, en_passant: String) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var dir: int = get_pawn_direction()
	var start_rank: int = get_pawn_start_rank()
	var f: int = position.x
	var r: int = position.y
	var my_side: String = "w" if color == PieceColor.WHITE else "b"

	ChessDebug.trace("_get_pawn_moves: %s pawn at (%d,%d) [%s], dir=%d, start_rank=%d" % [
		my_side, f, r, ChessNotation.square_name(position), dir, start_rank
	], "PAWN")

	# Forward move (non-capturing)
	var one_ahead: Vector2i = Vector2i(f, r + dir)
	if is_in_bounds(one_ahead) and board[one_ahead.y][one_ahead.x] == "":
		moves.append(one_ahead)
		ChessDebug.trace("  Forward move: %s" % ChessNotation.square_name(one_ahead), "PAWN")
		# Double move from starting position
		if r == start_rank:
			var two_ahead: Vector2i = Vector2i(f, r + dir * 2)
			if is_in_bounds(two_ahead) and board[two_ahead.y][two_ahead.x] == "":
				moves.append(two_ahead)
				ChessDebug.trace("  Double push: %s" % ChessNotation.square_name(two_ahead), "PAWN")

	# Diagonal captures
	for df in [-1, 1]:
		var cap_sq: Vector2i = Vector2i(f + df, r + dir)
		var direction_name: String = "left" if df == -1 else "right"
		if is_in_bounds(cap_sq):
			var target: String = board[cap_sq.y][cap_sq.x]
			ChessDebug.trace("  Checking %s diagonal %s: target='%s'" % [
				direction_name, ChessNotation.square_name(cap_sq), target
			], "PAWN")
			if target != "" and target[0] != my_side:
				moves.append(cap_sq)
				ChessDebug.trace("  -> CAPTURE available: %s captures %s at %s" % [
					get_notation(), target, ChessNotation.square_name(cap_sq)
				], "PAWN")
			elif target == "":
				ChessDebug.trace("  -> Empty square (no capture)", "PAWN")
			else:
				ChessDebug.trace("  -> Own piece (blocked)", "PAWN")
		else:
			ChessDebug.trace("  %s diagonal out of bounds" % direction_name, "PAWN")

	# En passant
	if en_passant != "-" and r == get_en_passant_rank():
		var ep_file: int = ChessNotation.FILE_RANKS.find(en_passant[0])
		var ep_rank: int = int(en_passant.substr(1)) - 1
		ChessDebug.trace("  En passant check: ep=%s, ep_file=%d, ep_rank=%d" % [
			en_passant, ep_file, ep_rank
		], "PAWN")
		if ep_rank == r + dir and abs(ep_file - f) == 1:
			moves.append(Vector2i(ep_file, ep_rank))
			ChessDebug.trace("  -> EN PASSANT available: %s" % en_passant, "PAWN")

	ChessDebug.trace("_get_pawn_moves: Generated %d pseudo-legal moves: %s" % [
		moves.size(), _moves_to_string(moves)
	], "PAWN")
	return moves

## Helper to convert move array to string for logging
func _moves_to_string(move_list: Array[Vector2i]) -> String:
	var names: PackedStringArray = []
	for m in move_list:
		names.append(ChessNotation.square_name(m))
	return "[" + ", ".join(names) + "]"

## Get king moves (including castling)
func _get_king_moves(board: Array, castling: String) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var f: int = position.x
	var r: int = position.y
	var my_side: String = "w" if color == PieceColor.WHITE else "b"

	# Normal king moves (one square in any direction)
	for direction in move_directions:
		var target: Vector2i = position + direction
		if is_in_bounds(target):
			var piece: String = board[target.y][target.x]
			if piece == "" or piece[0] != my_side:
				moves.append(target)

	# Castling moves (added here, but validation for check is done at a higher level)
	# We only add the king's destination squares here; the caller validates legality
	# Board orientation: rank 0 = white's back rank (rank 1), rank 7 = black's back rank (rank 8)
	if not has_moved:
		if color == PieceColor.WHITE and r == 0 and f == 4:
			# White king on e1 (rank 0, file 4)
			# White kingside: K right - king to g1, rook from h1 to f1
			if castling.find("K") != -1:
				if board[0][5] == "" and board[0][6] == "" and board[0][7] == "wR":
					moves.append(Vector2i(6, 0))  # g1
			# White queenside: Q right - king to c1, rook from a1 to d1
			if castling.find("Q") != -1:
				if board[0][1] == "" and board[0][2] == "" and board[0][3] == "" and board[0][0] == "wR":
					moves.append(Vector2i(2, 0))  # c1
		elif color == PieceColor.BLACK and r == 7 and f == 4:
			# Black king on e8 (rank 7, file 4)
			# Black kingside: k right - king to g8, rook from h8 to f8
			if castling.find("k") != -1:
				if board[7][5] == "" and board[7][6] == "" and board[7][7] == "bR":
					moves.append(Vector2i(6, 7))  # g8
			# Black queenside: q right - king to c8, rook from a8 to d8
			if castling.find("q") != -1:
				if board[7][1] == "" and board[7][2] == "" and board[7][3] == "" and board[7][0] == "bR":
					moves.append(Vector2i(2, 7))  # c8

	return moves

## Get moves for sliding pieces (rook, bishop, queen)
func _get_sliding_moves(board: Array) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var my_side: String = "w" if color == PieceColor.WHITE else "b"

	for direction in move_directions:
		var current: Vector2i = position + direction
		while is_in_bounds(current):
			var piece: String = board[current.y][current.x]
			if piece == "":
				moves.append(current)
				current += direction
			elif piece[0] != my_side:
				moves.append(current)  # Capture
				break
			else:
				break  # Blocked by own piece

	return moves

## Get moves for non-sliding pieces (knight)
func _get_non_sliding_moves(board: Array) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var my_side: String = "w" if color == PieceColor.WHITE else "b"

	for direction in move_directions:
		var target: Vector2i = position + direction
		if is_in_bounds(target):
			var piece: String = board[target.y][target.x]
			if piece == "" or piece[0] != my_side:
				moves.append(target)

	return moves

## Check if this move is a castling move
func is_castle_move(to_sq: Vector2i) -> bool:
	if type != PieceType.KING:
		return false
	return abs(to_sq.x - position.x) == 2 and to_sq.y == position.y

## Get rook positions for a castling move
## Returns dictionary with "rook_from" and "rook_to" Vector2i, or empty if not castling
func get_castle_rook_move(to_sq: Vector2i) -> Dictionary:
	if not is_castle_move(to_sq):
		return {}

	var result: Dictionary = {}
	if to_sq.x > position.x:
		# Kingside
		result["rook_from"] = Vector2i(7, position.y)
		result["rook_to"] = Vector2i(5, position.y)
	else:
		# Queenside
		result["rook_from"] = Vector2i(0, position.y)
		result["rook_to"] = Vector2i(3, position.y)
	return result

## Check if a pawn move to target would be a promotion
func is_promotion_move(to_sq: Vector2i) -> bool:
	if type != PieceType.PAWN:
		return false
	return to_sq.y == get_pawn_promotion_rank()

## Check if a pawn move is an en passant capture
func is_en_passant_move(to_sq: Vector2i, en_passant: String) -> bool:
	if type != PieceType.PAWN:
		return false
	if en_passant == "-":
		return false
	var ep_file: int = ChessNotation.FILE_RANKS.find(en_passant[0])
	var ep_rank: int = int(en_passant.substr(1)) - 1
	return to_sq.x == ep_file and to_sq.y == ep_rank

## Get the captured pawn position for an en passant move
func get_en_passant_capture_square(to_sq: Vector2i) -> Vector2i:
	var dir: int = get_pawn_direction()
	return Vector2i(to_sq.x, to_sq.y - dir)

## Get piece notation string (e.g., "wP", "bK")
func get_notation() -> String:
	var c: String = "w" if color == PieceColor.WHITE else "b"
	var t: String
	match type:
		PieceType.PAWN: t = "P"
		PieceType.ROOK: t = "R"
		PieceType.KNIGHT: t = "N"
		PieceType.BISHOP: t = "B"
		PieceType.QUEEN: t = "Q"
		PieceType.KING: t = "K"
	return c + t

## Get GamePigeon piece code
func get_gp_code() -> int:
	return ChessNotation.piece_to_gp_code(get_notation())

## Create a ChessPiece from a notation string (e.g., "wP", "bK")
static func from_notation(notation: String, pos: Vector2i = Vector2i(-1, -1)) -> ChessPiece:
	if notation.length() < 2:
		return null

	var piece_color: PieceColor = PieceColor.WHITE if notation[0] == "w" else PieceColor.BLACK
	var piece_type: PieceType

	match notation[1]:
		"P": piece_type = PieceType.PAWN
		"R": piece_type = PieceType.ROOK
		"N": piece_type = PieceType.KNIGHT
		"B": piece_type = PieceType.BISHOP
		"Q": piece_type = PieceType.QUEEN
		"K": piece_type = PieceType.KING
		_: return null

	return ChessPiece.new(piece_type, piece_color, pos)

## Create a ChessPiece from a GamePigeon code
static func from_gp_code(code: int, pos: Vector2i = Vector2i(-1, -1)) -> ChessPiece:
	var notation: String = ChessNotation.gp_code_to_piece(code)
	if notation == "":
		return null
	return from_notation(notation, pos)

## Get valid promotion piece types
static func get_promotion_choices() -> Array[PieceType]:
	return [PieceType.QUEEN, PieceType.ROOK, PieceType.BISHOP, PieceType.KNIGHT]

## Promote this pawn to a new piece type
func promote_to(new_type: PieceType) -> bool:
	if type != PieceType.PAWN:
		return false
	if new_type == PieceType.PAWN or new_type == PieceType.KING:
		return false
	type = new_type
	_setup_movement_patterns()
	return true

## Get the opposite color (enum version)
static func opposite_color(c: PieceColor) -> PieceColor:
	return PieceColor.BLACK if c == PieceColor.WHITE else PieceColor.WHITE

## Get the opposite side string ("w" -> "b", "b" -> "w")
## Use this instead of inline `"b" if side == "w" else "w"` patterns
static func opposite_side(side: String) -> String:
	return "b" if side == "w" else "w"

## Convert PieceColor to side string ("w" or "b")
static func color_to_side(c: PieceColor) -> String:
	return "w" if c == PieceColor.WHITE else "b"

## Convert side string to PieceColor
static func side_to_color(side: String) -> PieceColor:
	return PieceColor.WHITE if side == "w" else PieceColor.BLACK

## Get display name for piece type
static func type_name(t: PieceType) -> String:
	match t:
		PieceType.PAWN: return "Pawn"
		PieceType.ROOK: return "Rook"
		PieceType.KNIGHT: return "Knight"
		PieceType.BISHOP: return "Bishop"
		PieceType.QUEEN: return "Queen"
		PieceType.KING: return "King"
	return "Unknown"

## Get display name for piece color
static func color_name(c: PieceColor) -> String:
	return "White" if c == PieceColor.WHITE else "Black"

## Clone this piece
func duplicate() -> ChessPiece:
	var copy: ChessPiece = ChessPiece.new(type, color, position)
	copy.has_moved = has_moved
	return copy

## String representation for debugging
func _to_string() -> String:
	return "%s %s at %s (moved: %s)" % [
		color_name(color),
		type_name(type),
		ChessNotation.square_name(position),
		str(has_moved)
	]
