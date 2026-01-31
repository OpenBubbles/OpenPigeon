class_name ChessDialogs
extends RefCounted

## Chess dialog manager for game-over panels and promotion dialogs.
## Handles creation, display, and interaction of modal dialogs.

# ============================================================================
# SIGNALS - Decoupled callbacks for promotion selection
# ============================================================================
signal promotion_selected(piece: String)

## Dialog references
var game_over_panel: Panel = null
var game_over_text: Label = null
var promotion_dialog: Panel = null
var promotion_queen_button: TextureRect = null
var promotion_rook_button: TextureRect = null
var promotion_bishop_button: TextureRect = null
var promotion_knight_button: TextureRect = null

## State
var awaiting_promotion: bool = false
var promotion_side: String = ""

## References
var _parent: Control = null
var _piece_textures: Dictionary = {}
var _log_callback: Callable = Callable()

## Style constants
const PANEL_CORNER_RADIUS: int = 20
const PANEL_BG_COLOR: Color = Color(0.2, 0.2, 0.2, 0.65)
const PROMO_PANEL_BG_COLOR: Color = Color(0.15, 0.15, 0.15, 0.92)
const PROMO_CORNER_RADIUS: int = 15
const TEXT_COLOR: Color = Color(1, 1, 1)

## Initialize the dialog manager
func setup(parent: Control, piece_textures: Dictionary, log_callback: Callable = Callable()) -> void:
	_parent = parent
	_piece_textures = piece_textures
	_log_callback = log_callback

## Internal logging
func _log(msg: String) -> void:
	if _log_callback.is_valid():
		_log_callback.call("DIALOGS: " + msg)

## Check if dialogs are ready
func is_ready() -> bool:
	return _parent != null

# ============================================================================
# GAME OVER PANEL
# ============================================================================

## Create the game over panel
func create_game_over_panel(board_origin: Vector2, board_size: float, square_size: float) -> void:
	if not is_ready():
		return

	# Clean up existing panel
	if is_instance_valid(game_over_panel):
		game_over_panel.queue_free()
		game_over_panel = null
		game_over_text = null

	var panel_w: float = board_size * 0.7
	var panel_h: float = maxf(56.0, square_size * 0.6)

	game_over_panel = Panel.new()
	var sb: StyleBoxFlat = ChessUI.create_panel_stylebox(PANEL_BG_COLOR, PANEL_CORNER_RADIUS)
	game_over_panel.add_theme_stylebox_override("panel", sb)
	game_over_panel.size = Vector2(panel_w, panel_h)

	var center: Vector2 = board_origin + Vector2(board_size * 0.5, board_size * 0.5)
	game_over_panel.position = center - game_over_panel.size * 0.5
	game_over_panel.visible = false
	_parent.add_child(game_over_panel)

	game_over_text = Label.new()
	game_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_text.size = game_over_panel.size
	game_over_text.add_theme_font_size_override("font_size", int(maxf(20.0, square_size * 0.28)))
	game_over_text.add_theme_color_override("font_color", TEXT_COLOR)
	game_over_panel.add_child(game_over_text)

	_log("game_over_panel created")

## Show the game over panel with a message
func show_game_over(message: String) -> void:
	if is_instance_valid(game_over_panel) and is_instance_valid(game_over_text):
		game_over_text.text = message
		game_over_panel.visible = true
		_log("show_game_over: %s" % message)

## Hide the game over panel
func hide_game_over() -> void:
	if is_instance_valid(game_over_panel):
		game_over_panel.visible = false

## Check if game over panel is visible
func is_game_over_visible() -> bool:
	return is_instance_valid(game_over_panel) and game_over_panel.visible

# ============================================================================
# PROMOTION DIALOG
# ============================================================================

## Create the promotion dialog
func create_promotion_dialog(board_origin: Vector2, board_size: float, square_size: float) -> void:
	if not is_ready():
		return

	# Clean up existing dialog
	if is_instance_valid(promotion_dialog):
		promotion_dialog.queue_free()
		promotion_dialog = null
		promotion_queen_button = null
		promotion_rook_button = null
		promotion_bishop_button = null
		promotion_knight_button = null

	var promo_w: float = square_size * 6.0  # Wide enough for 4 pieces
	var promo_h: float = square_size * 2.5

	promotion_dialog = Panel.new()
	var promo_sb: StyleBoxFlat = ChessUI.create_panel_stylebox(PROMO_PANEL_BG_COLOR, PROMO_CORNER_RADIUS)
	promotion_dialog.add_theme_stylebox_override("panel", promo_sb)
	promotion_dialog.size = Vector2(promo_w, promo_h)

	var center: Vector2 = board_origin + Vector2(board_size * 0.5, board_size * 0.5)
	promotion_dialog.position = center - promotion_dialog.size * 0.5
	promotion_dialog.visible = false
	promotion_dialog.z_index = 2000  # Above everything else
	_parent.add_child(promotion_dialog)

	# Add title label
	var promo_title: Label = Label.new()
	promo_title.text = "Promote to:"
	promo_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	promo_title.add_theme_font_size_override("font_size", int(maxf(16.0, square_size * 0.24)))
	promo_title.add_theme_color_override("font_color", TEXT_COLOR)
	promo_title.position = Vector2(0, square_size * 0.15)
	promo_title.size = Vector2(promo_w, square_size * 0.4)
	promotion_dialog.add_child(promo_title)

	# Calculate piece button positions
	var piece_size: float = square_size * 1.0
	var spacing: float = square_size * 0.2
	var total_width: float = (piece_size * 4.0) + (spacing * 3.0)
	var start_x: float = (promo_w - total_width) * 0.5
	var piece_y: float = square_size * 0.9

	# Create piece buttons (textures will be set when showing dialog)
	promotion_queen_button = _create_piece_button(start_x, piece_y, piece_size)
	promotion_dialog.add_child(promotion_queen_button)

	promotion_rook_button = _create_piece_button(start_x + piece_size + spacing, piece_y, piece_size)
	promotion_dialog.add_child(promotion_rook_button)

	promotion_bishop_button = _create_piece_button(start_x + (piece_size + spacing) * 2, piece_y, piece_size)
	promotion_dialog.add_child(promotion_bishop_button)

	promotion_knight_button = _create_piece_button(start_x + (piece_size + spacing) * 3, piece_y, piece_size)
	promotion_dialog.add_child(promotion_knight_button)

	_log("promotion_dialog created")

## Create a piece button for the promotion dialog
func _create_piece_button(x: float, y: float, size: float) -> TextureRect:
	var btn: TextureRect = TextureRect.new()
	btn.position = Vector2(x, y)
	btn.size = Vector2(size, size)
	btn.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	btn.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return btn

## Show the promotion dialog for a given side
func show_promotion(side: String) -> void:
	if not is_instance_valid(promotion_dialog):
		_log("show_promotion: dialog not initialized")
		return

	_log("show_promotion for side=%s" % side)
	promotion_side = side
	awaiting_promotion = true

	# Set textures based on side
	var queen_key: String = side + "Q"
	var rook_key: String = side + "R"
	var bishop_key: String = side + "B"
	var knight_key: String = side + "N"

	if _piece_textures.has(queen_key):
		promotion_queen_button.texture = _piece_textures[queen_key]
	if _piece_textures.has(rook_key):
		promotion_rook_button.texture = _piece_textures[rook_key]
	if _piece_textures.has(bishop_key):
		promotion_bishop_button.texture = _piece_textures[bishop_key]
	if _piece_textures.has(knight_key):
		promotion_knight_button.texture = _piece_textures[knight_key]

	promotion_dialog.visible = true
	promotion_dialog.z_index = 3000  # Ensure above everything

	# Move to front of render order
	if is_instance_valid(_parent):
		_parent.move_child(promotion_dialog, _parent.get_child_count() - 1)

	_log("show_promotion: dialog shown")

## Hide the promotion dialog
func hide_promotion() -> void:
	if is_instance_valid(promotion_dialog):
		promotion_dialog.visible = false
	awaiting_promotion = false
	promotion_side = ""
	_log("hide_promotion: dialog hidden")

## Check if promotion dialog is visible
func is_promotion_visible() -> bool:
	return awaiting_promotion and is_instance_valid(promotion_dialog) and promotion_dialog.visible

## Handle a tap on the promotion dialog
## Returns the selected piece ("Q", "R", "B", "N") or "" if no button was hit
## Also emits promotion_selected signal when a piece is chosen (for signal-based observers)
func handle_promotion_tap(position: Vector2) -> String:
	if not is_promotion_visible():
		return ""

	var dialog_pos: Vector2 = promotion_dialog.position
	var selected_piece: String = ""

	# Check queen button
	if is_instance_valid(promotion_queen_button):
		var queen_rect: Rect2 = Rect2(dialog_pos + promotion_queen_button.position, promotion_queen_button.size)
		if queen_rect.has_point(position):
			_log("handle_promotion_tap: Queen selected")
			selected_piece = "Q"

	# Check rook button
	if selected_piece == "" and is_instance_valid(promotion_rook_button):
		var rook_rect: Rect2 = Rect2(dialog_pos + promotion_rook_button.position, promotion_rook_button.size)
		if rook_rect.has_point(position):
			_log("handle_promotion_tap: Rook selected")
			selected_piece = "R"

	# Check bishop button
	if selected_piece == "" and is_instance_valid(promotion_bishop_button):
		var bishop_rect: Rect2 = Rect2(dialog_pos + promotion_bishop_button.position, promotion_bishop_button.size)
		if bishop_rect.has_point(position):
			_log("handle_promotion_tap: Bishop selected")
			selected_piece = "B"

	# Check knight button
	if selected_piece == "" and is_instance_valid(promotion_knight_button):
		var knight_rect: Rect2 = Rect2(dialog_pos + promotion_knight_button.position, promotion_knight_button.size)
		if knight_rect.has_point(position):
			_log("handle_promotion_tap: Knight selected")
			selected_piece = "N"

	# Emit signal for observers (if a piece was selected)
	if selected_piece != "":
		promotion_selected.emit(selected_piece)

	return selected_piece

# ============================================================================
# CLEANUP
# ============================================================================

## Clean up all dialogs
func cleanup() -> void:
	if is_instance_valid(game_over_panel):
		game_over_panel.queue_free()
		game_over_panel = null
		game_over_text = null

	if is_instance_valid(promotion_dialog):
		promotion_dialog.queue_free()
		promotion_dialog = null
		promotion_queen_button = null
		promotion_rook_button = null
		promotion_bishop_button = null
		promotion_knight_button = null

	awaiting_promotion = false
	promotion_side = ""
	_log("cleanup: all dialogs freed")
