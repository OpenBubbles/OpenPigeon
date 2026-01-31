class_name ChessNotation
extends RefCounted

## Chess notation utilities for GamePigeon format parsing and serialization.
## Handles conversion between internal board representation and GamePigeon's
## 64-element array format.

## File letters for algebraic notation (a-h)
const FILE_RANKS: Array[String] = ["a", "b", "c", "d", "e", "f", "g", "h"]

## GamePigeon piece encoding:
## 0 = empty
## White: 11=P, 12=R, 13=N, 14=B, 15=Q, 16=K
## Black: 21=P, 22=R, 23=N, 24=B, 25=Q, 26=K

## Convert a piece code string (e.g., "wP", "bK") to GamePigeon integer code
static func piece_to_gp_code(piece: String) -> int:
	if piece == "":
		return 0
	var side: String = piece[0]
	var ptype: String = piece[1]
	var code: int = 0
	match ptype:
		"P": code = 1
		"R": code = 2
		"N": code = 3
		"B": code = 4
		"Q": code = 5
		"K": code = 6
	return (10 + code) if side == "w" else (20 + code)

## Convert a GamePigeon integer code to piece string (e.g., 11 -> "wP")
static func gp_code_to_piece(code: int) -> String:
	if code == 0:
		return ""
	var side: String = "w" if code < 20 else "b"
	var piece_code: int = code % 10
	var piece_type: String = ""
	match piece_code:
		1: piece_type = "P"
		2: piece_type = "R"
		3: piece_type = "N"
		4: piece_type = "B"
		5: piece_type = "Q"
		6: piece_type = "K"
	return side + piece_type

## Convert internal 8x8 board array to GamePigeon's flat 64-element comma-separated string.
## Board layout: board[0] is rank 1 (white's back rank), board[7] is rank 8 (black's back rank)
static func board_to_gp_array(board: Array) -> String:
	var gp_pieces: Array = []
	for r in range(8):
		for f in range(8):
			var piece: String = board[r][f]
			gp_pieces.append(str(piece_to_gp_code(piece)))
	return ",".join(gp_pieces)

## Parse GamePigeon's 64-element comma-separated string into 8x8 board array.
## Returns the populated board array.
static func gp_array_to_board(gp_array_str: String) -> Array:
	var pieces: PackedStringArray = gp_array_str.split(",")
	if pieces.size() != 64:
		push_warning("ChessNotation.gp_array_to_board: invalid array size=%d (expected 64)" % pieces.size())
		return []

	var board: Array = []
	for r in range(8):
		var row_arr: Array[String] = []
		for f in range(8):
			var idx: int = f + (r * 8)
			var code: int = int(pieces[idx])
			row_arr.append(gp_code_to_piece(code))
		board.append(row_arr)
	return board

## Infer castling rights from the current board state.
## Returns a string like "KQkq", "-", or partial rights based on piece positions.
static func infer_castling_rights(board: Array) -> String:
	if board.size() != 8:
		return "-"

	var rights: String = ""

	# Board orientation: board[0] = rank 0 = white's back rank, board[7] = rank 7 = black's back rank
	# White castling: king must be on e1 (board[0][4]) and respective rook on starting square
	if board[0][4] == "wK" and board[0][7] == "wR":
		rights += "K"  # White kingside
	if board[0][4] == "wK" and board[0][0] == "wR":
		rights += "Q"  # White queenside

	# Black castling: king must be on e8 (board[7][4]) and respective rook on starting square
	if board[7][4] == "bK" and board[7][7] == "bR":
		rights += "k"  # Black kingside
	if board[7][4] == "bK" and board[7][0] == "bR":
		rights += "q"  # Black queenside

	return rights if rights != "" else "-"

## Parse GamePigeon replay string format.
## Format: board:<prev>|move:<from_f>,<from_r>,<to_f>,<to_r>|board:<current>
## Returns a dictionary with:
##   - prev_board: String (64-element GP array)
##   - current_board: String (64-element GP array)
##   - move_from: Vector2i (file, rank) or Vector2i(-1, -1) if no move
##   - move_to: Vector2i (file, rank) or Vector2i(-1, -1) if no move
##   - has_move: bool
static func parse_gp_replay(replay: String) -> Dictionary:
	var result: Dictionary = {
		"prev_board": "",
		"current_board": "",
		"move_from": Vector2i(-1, -1),
		"move_to": Vector2i(-1, -1),
		"has_move": false
	}

	var parts: PackedStringArray = replay.split("|")

	# Extract previous board, move coordinates, and current board
	var prev_board: String = ""
	var current_board: String = ""
	var move_coords: PackedStringArray = PackedStringArray()

	for part in parts:
		if part.begins_with("board:"):
			var board_data: String = part.substr(6)
			if prev_board == "":
				prev_board = board_data
			else:
				current_board = board_data
		elif part.begins_with("move:"):
			var move_data: String = part.substr(5)
			move_coords = move_data.split(",")

	result["prev_board"] = prev_board
	result["current_board"] = current_board

	# Parse move coordinates if present
	if move_coords.size() == 4:
		var from_f: int = int(move_coords[0])
		var from_r: int = int(move_coords[1])
		var to_f: int = int(move_coords[2])
		var to_r: int = int(move_coords[3])
		result["move_from"] = Vector2i(from_f, from_r)
		result["move_to"] = Vector2i(to_f, to_r)
		result["has_move"] = true

	return result

## Generate GamePigeon replay string with previous board, move, and current board.
static func to_gp_replay(prev_board_gp: String, from_sq: Vector2i, to_sq: Vector2i, current_board_gp: String) -> String:
	var move_str: String = "move:%d,%d,%d,%d" % [from_sq.x, from_sq.y, to_sq.x, to_sq.y]
	return "board:%s|%s|board:%s" % [prev_board_gp, move_str, current_board_gp]

## Generate unique position key for threefold repetition detection.
## Includes board state, turn, castling rights, and en passant target.
static func to_position_key(board: Array, turn: String, castling: String, en_passant: String) -> String:
	var board_gp: String = board_to_gp_array(board)
	var castling_str: String = castling if castling != "" else "-"
	return "%s %s %s %s" % [board_gp, turn, castling_str, en_passant]

## Convert a board position (Vector2i with file, rank) to algebraic notation (e.g., "e4")
static func square_name(sq: Vector2i) -> String:
	if sq.x < 0 or sq.x > 7 or sq.y < 0 or sq.y > 7:
		return "??"
	return FILE_RANKS[sq.x] + str(sq.y + 1)

## Parse algebraic notation (e.g., "e4") to board position Vector2i
static func parse_square(name: String) -> Vector2i:
	if name.length() < 2:
		return Vector2i(-1, -1)
	var file_idx: int = FILE_RANKS.find(name[0].to_lower())
	if file_idx == -1:
		return Vector2i(-1, -1)
	var rank: int = int(name.substr(1)) - 1
	if rank < 0 or rank > 7:
		return Vector2i(-1, -1)
	return Vector2i(file_idx, rank)

## Convert a move to UCI notation (e.g., "e2e4", "e7e8q" for promotion)
static func to_uci(from_sq: Vector2i, to_sq: Vector2i, promotion_piece: String = "") -> String:
	var uci: String = square_name(from_sq) + square_name(to_sq)
	if promotion_piece != "":
		uci += promotion_piece.to_lower()
	return uci

## Parse UCI notation to move coordinates
## Returns dictionary with from_sq, to_sq, promotion (or empty if invalid)
static func parse_uci(uci: String) -> Dictionary:
	var result: Dictionary = {
		"from_sq": Vector2i(-1, -1),
		"to_sq": Vector2i(-1, -1),
		"promotion": ""
	}
	if uci.length() < 4:
		return result
	result["from_sq"] = parse_square(uci.substr(0, 2))
	result["to_sq"] = parse_square(uci.substr(2, 2))
	if uci.length() >= 5:
		result["promotion"] = uci[4].to_upper()
	return result

## Clone a board array (deep copy)
static func clone_board(src: Array) -> Array:
	var out: Array = []
	for r in range(src.size()):
		var row: Array[String] = []
		for f in range(src[r].size()):
			row.append(src[r][f])
		out.append(row)
	return out

## Get the default starting position in GamePigeon format
static func get_default_position_gp() -> String:
	return "12,13,14,15,16,14,13,12,11,11,11,11,11,11,11,11,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,21,21,21,21,21,21,21,21,22,23,24,25,26,24,23,22"

## Get the default starting board as 8x8 array
static func get_default_board() -> Array:
	return gp_array_to_board(get_default_position_gp())
