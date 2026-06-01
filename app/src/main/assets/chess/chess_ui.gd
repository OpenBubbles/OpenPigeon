class_name ChessUI
extends RefCounted

## Chess UI utilities and constants.
## Provides helper functions for UI rendering, colors, and animations.

# ============================================================================
# LAYOUT CONSTANTS
# ============================================================================

## Viewport and board sizing
const BOARD_DIMENSION: int = 8
const VIEWPORT_MARGIN: float = 20.0
const VIEWPORT_PADDING: float = 8.0
const MIN_SQUARE_SIZE: float = 8.0
const MIN_LABEL_SIZE: float = 12.0
const MIN_BORDER_THICK: float = 6.0

## Label sizing ratios (relative to square size)
const FILE_LABEL_HEIGHT_RATIO: float = 0.28
const RANK_LABEL_WIDTH_RATIO: float = 0.24
const LABEL_FONT_SIZE_RATIO: float = 0.28
const LABEL_BORDER_PADDING: float = 6.0

## Border sizing ratio (relative to square size)
const BORDER_RATIO: float = 0.03

## Piece sizing ratios (relative to square size)
const PIECE_SIZE_RATIO: float = 0.9
const PIECE_OFFSET_RATIO: float = 0.1

## Overlay sizing ratios (relative to square size)
const OVERLAY_MARGIN_RATIO: float = 0.06
const OVERLAY_ALPHA: float = 0.35

# ============================================================================
# COLOR CONSTANTS
# ============================================================================

## Board colors
const LIGHT_SQUARE_COLOR: Color = Color(240.0/255.0, 217.0/255.0, 181.0/255.0)
const DARK_SQUARE_COLOR: Color = Color(181.0/255.0, 136.0/255.0, 99.0/255.0)
const BORDER_COLOR: Color = Color(181.0/255.0, 136.0/255.0, 99.0/255.0)

## Highlight colors
const SELECTED_COLOR: Color = Color(0.2, 0.6, 1.0, 0.38)
const LEGAL_MOVE_COLOR: Color = Color(0.2, 0.6, 1.0, 0.33)
const CAPTURE_COLOR: Color = Color(0.9, 0.1, 0.1, 0.45)
const OPPONENT_MOVE_COLOR: Color = Color(0.2, 0.8, 0.2, 0.4)
const CHECK_COLOR: Color = Color(0.9, 0.1, 0.1, 0.55)
const DIMMED_COLOR: Color = Color(0.6, 0.6, 0.6)

## Animation constants
const MOVE_ANIMATION_DURATION: float = 0.4
const PULSE_DURATION: float = 0.6
const PULSE_MIN_ALPHA: float = 0.25
const PULSE_MAX_ALPHA: float = 0.6

## Background colors for themes
const LIGHT_BACKGROUND: Color = Color("#947972")
const DARK_BACKGROUND: Color = Color("#261a19")

## Get the square color for a given position
static func get_square_color(rank: int, file: int) -> Color:
	return DARK_SQUARE_COLOR if ((file + rank) % 2 == 0) else LIGHT_SQUARE_COLOR

## Get the highlight color for a legal move
static func get_move_highlight_color(is_capture: bool) -> Color:
	return CAPTURE_COLOR if is_capture else LEGAL_MOVE_COLOR

## Calculate board dimensions based on viewport
static func calculate_board_dimensions(viewport_size: Vector2, margin: float = VIEWPORT_MARGIN) -> Dictionary:
	var avail: float = minf(viewport_size.x, viewport_size.y) - margin * 2.0

	# Initial estimate using conservative border ratio so labels fit inside the border
	var square_size: float = floorf((avail - VIEWPORT_PADDING * 2.0) / (BOARD_DIMENSION + 2.0 * FILE_LABEL_HEIGHT_RATIO))
	if square_size < MIN_SQUARE_SIZE + 2.0:
		square_size = MIN_SQUARE_SIZE + 2.0

	# Calculate border thickness based on label sizes
	var file_label_h: float = maxf(MIN_LABEL_SIZE, square_size * FILE_LABEL_HEIGHT_RATIO)
	var rank_label_w: float = maxf(MIN_LABEL_SIZE, square_size * RANK_LABEL_WIDTH_RATIO)
	var border_thick: float = maxf(file_label_h, rank_label_w) + LABEL_BORDER_PADDING

	# Verify fit and adjust if needed
	var total_w: float = BOARD_DIMENSION * square_size + 2.0 * border_thick
	if total_w > avail:
		square_size = floorf((avail - 2.0 * border_thick) / BOARD_DIMENSION)
		if square_size < MIN_SQUARE_SIZE:
			square_size = MIN_SQUARE_SIZE
		# Recalculate border with new square size
		file_label_h = maxf(MIN_LABEL_SIZE, square_size * FILE_LABEL_HEIGHT_RATIO)
		rank_label_w = maxf(MIN_LABEL_SIZE, square_size * RANK_LABEL_WIDTH_RATIO)
		border_thick = maxf(file_label_h, rank_label_w) + LABEL_BORDER_PADDING
		total_w = BOARD_DIMENSION * square_size + 2.0 * border_thick
		# As a last resort, shave the border down to fit
		if total_w > avail:
			var overflow: float = total_w - avail
			border_thick = maxf(MIN_BORDER_THICK, border_thick - overflow * 0.5)
			total_w = BOARD_DIMENSION * square_size + 2.0 * border_thick

	var total_h: float = total_w  # Keep square board area
	var top_left: Vector2 = Vector2((viewport_size.x - total_w) / 2.0, (viewport_size.y - total_h) / 2.0)
	var board_origin: Vector2 = top_left + Vector2(border_thick, border_thick)

	return {
		"square_size": square_size,
		"border_thick": border_thick,
		"board_origin": board_origin,
		"total_size": Vector2(total_w, total_h),
		"black_thick": maxf(2.0, square_size * BORDER_RATIO)
	}

## Convert a board position to screen coordinates
static func board_to_screen(pos: Vector2i, board_origin: Vector2, square_size: float, flip_board: bool) -> Vector2:
	var ui_x: float = ((7 - pos.x) if flip_board else pos.x) * square_size
	var ui_y: float = (pos.y if flip_board else (7 - pos.y)) * square_size
	return board_origin + Vector2(ui_x, ui_y)

## Convert screen coordinates to a board position
static func screen_to_board(screen_pos: Vector2, board_origin: Vector2, square_size: float, flip_board: bool) -> Vector2i:
	var rel: Vector2 = screen_pos - board_origin
	if rel.x < 0 or rel.y < 0:
		return Vector2i(-1, -1)

	var ui_f: int = int(rel.x / square_size)
	var ui_r: int = int(rel.y / square_size)

	if ui_f < 0 or ui_f > 7 or ui_r < 0 or ui_r > 7:
		return Vector2i(-1, -1)

	var f: int = (7 - ui_f) if flip_board else ui_f
	var r: int = ui_r if flip_board else (7 - ui_r)

	return Vector2i(f, r)

## Create a pulse animation tween for a ColorRect overlay
static func create_pulse_tween(overlay: ColorRect, tree: SceneTree) -> Tween:
	if overlay == null or tree == null:
		return null
	var tween: Tween = tree.create_tween()
	tween.set_loops()
	tween.tween_property(overlay, "modulate:a", PULSE_MIN_ALPHA, PULSE_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(overlay, "modulate:a", PULSE_MAX_ALPHA, PULSE_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween

## Create a move animation tween for a piece
static func create_move_tween(piece_tex: TextureRect, end_pos: Vector2, tree: SceneTree, duration: float = MOVE_ANIMATION_DURATION) -> Tween:
	if piece_tex == null or tree == null:
		return null

	var tween: Tween = tree.create_tween()
	tween.set_parallel(true)

	# Smooth slide animation
	tween.tween_property(piece_tex, "position", end_pos, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Scale bounce for polish
	tween.tween_property(piece_tex, "scale", Vector2(1.1, 1.1), duration * 0.5)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Chain scale-back
	tween.chain()
	tween.tween_property(piece_tex, "scale", Vector2.ONE, duration * 0.5)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	# Cleanup callback
	tween.finished.connect(func():
		piece_tex.position = end_pos
		piece_tex.scale = Vector2.ONE
	)

	return tween

## Create a stylebox for panels
static func create_panel_stylebox(bg_color: Color, corner_radius: int = 15) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.corner_radius_top_left = corner_radius
	sb.corner_radius_top_right = corner_radius
	sb.corner_radius_bottom_left = corner_radius
	sb.corner_radius_bottom_right = corner_radius
	return sb

## Get the appropriate marker color for a player side
static func get_marker_color(side: String) -> Color:
	return Color(1, 1, 1, 1) if side == "w" else Color(0, 0, 0, 1)

## Format a game result message for display
static func format_result_message(state: ChessEngine.GameState, winner_side: String, my_color: String) -> String:
	match state:
		ChessEngine.GameState.CHECKMATE:
			return "YOU WIN!" if my_color == winner_side else "YOU LOSE!"
		ChessEngine.GameState.STALEMATE:
			return "DRAW - Stalemate"
		ChessEngine.GameState.DRAW_INSUFFICIENT:
			return "DRAW - Insufficient Material"
		ChessEngine.GameState.DRAW_FIFTY_MOVE:
			return "DRAW - 50 Move Rule"
		ChessEngine.GameState.DRAW_REPETITION:
			return "DRAW - Repetition"
	return ""

## Get the piece texture key for a piece code
static func get_piece_texture_key(piece_code: String) -> String:
	return piece_code  # e.g., "wP", "bK"

## Calculate piece display size and position within a square
static func calculate_piece_rect(square_pos: Vector2, square_size: float) -> Dictionary:
	var piece_size: Vector2 = Vector2(square_size * PIECE_SIZE_RATIO, square_size * PIECE_SIZE_RATIO)
	var offset: float = square_size * PIECE_OFFSET_RATIO
	var piece_pos: Vector2 = square_pos + (Vector2(square_size, square_size) - piece_size) * 0.5 + Vector2(offset, offset)
	return {
		"position": piece_pos,
		"size": piece_size
	}

## Calculate overlay margin and size within a square
static func calculate_overlay_rect(square_pos: Vector2, square_size: float) -> Dictionary:
	var margin: float = square_size * OVERLAY_MARGIN_RATIO
	return {
		"position": square_pos + Vector2(margin, margin),
		"size": Vector2(square_size - margin * 2.0, square_size - margin * 2.0)
	}

## Get file label text for a given index (considering board flip)
static func get_file_label(index: int, flip_board: bool) -> String:
	var file_index: int = (7 - index) if flip_board else index
	return ChessNotation.FILE_RANKS[file_index]

## Get rank label text for a given index (considering board flip)
static func get_rank_label(index: int, flip_board: bool) -> int:
	return (index + 1) if flip_board else (8 - index)


## Promotion dialog helper class
class PromotionDialogConfig:
	var dialog_width: float
	var dialog_height: float
	var piece_size: float
	var spacing: float
	var title_height: float
	var piece_y: float

	func _init(square_size: float) -> void:
		dialog_width = square_size * 6.0
		dialog_height = square_size * 2.5
		piece_size = square_size * 1.0
		spacing = square_size * 0.2
		title_height = square_size * 0.5
		piece_y = square_size * 0.9

	func get_piece_positions() -> Array[Vector2]:
		var total_width: float = (piece_size * 4.0) + (spacing * 3.0)
		var start_x: float = (dialog_width - total_width) * 0.5
		var positions: Array[Vector2] = []
		for i in range(4):
			positions.append(Vector2(start_x + (piece_size + spacing) * i, piece_y))
		return positions

	func get_piece_rect(index: int) -> Rect2:
		var positions: Array[Vector2] = get_piece_positions()
		if index < 0 or index >= positions.size():
			return Rect2()
		return Rect2(positions[index], Vector2(piece_size, piece_size))
