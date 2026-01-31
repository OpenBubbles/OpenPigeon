extends Control
class_name ChessTop

## Chess game main controller for OpenPigeon integration.

# ============================================================================
# SIGNALS - Game events for observers (sound effects, analytics, etc.)
# ============================================================================
signal move_executed(from_sq: Vector2i, to_sq: Vector2i, piece: String)
signal game_over_detected(winner_side: String, reason: String)
signal check_detected(side: String)
signal turn_changed(new_turn: String)
##
## Architecture:
## - ChessNotation: Format parsing/serialization (GamePigeon format, UCI, algebraic notation)
## - ChessPiece: Piece class with type enum, movement patterns, and move generation
## - ChessEngine: Game logic (check detection, legal moves, game state evaluation)
## - ChessBoard: Board state management (position, moves, snapshots)
## - ChessUI: UI utilities (colors, dimensions, constants)
## - ChessAnimations: Animation controller (piece moves, pulses, transitions)
## - ChessDialogs: Dialog manager (game over panel, promotion dialog)
## - ChessDebug: Logging utilities with configurable log levels (TRACE, DEBUG, INFO, WARNING, ERROR)
## - ChessTop (this file): Main controller, scene integration, AppPlugin communication

# Piece textures dictionary (const with inline preloads for cleaner code)
const PIECE_TEXTURES: Dictionary = {
	"wP": preload("res://chess/pieces/chess_wP.png"),
	"wR": preload("res://chess/pieces/chess_wR.png"),
	"wN": preload("res://chess/pieces/chess_wN.png"),
	"wB": preload("res://chess/pieces/chess_wB.png"),
	"wQ": preload("res://chess/pieces/chess_wQ.png"),
	"wK": preload("res://chess/pieces/chess_wK.png"),
	"bP": preload("res://chess/pieces/chess_bP.png"),
	"bR": preload("res://chess/pieces/chess_bR.png"),
	"bN": preload("res://chess/pieces/chess_bN.png"),
	"bB": preload("res://chess/pieces/chess_bB.png"),
	"bQ": preload("res://chess/pieces/chess_bQ.png"),
	"bK": preload("res://chess/pieces/chess_bK.png"),
}

# Verbose-debugging-enabled ChessTop for OpenPidgeon integration
# - Local-mode friendly (play both sides in debug)
# - Lots of CHESSDBG logs
# - Correct move generation & highlighting
# - Detects check, checkmate, stalemate
# - Dims pieces that cannot help when side is in check
# - On-screen CHECK and GAME OVER UI indicators
# - King square red highlight when in check

const FILE_RANKS: Array[String] = ["a","b","c","d","e","f","g","h"]

var SQUARE_SIZE: float = 100.0
var BOARD_ORIGIN: Vector2 = Vector2(40, 40)
var BORDER_THICK: float = 16.0
var board_border: ColorRect = null
var black_border: ColorRect = null
var BLACK_THICK: float = 2.0
var pending_evaluate: bool = false   # set true if parse_gp_replay ran before UI built

var appPlugin: Object = null
var local_mode: bool = false        # true when running without appPlugin (local debug)
var isTurn: bool = false
var waitingForOpponent: bool = true
var my_player_id: String = ""
var enemy_player_index: int = 2  # 1 or 2, used for UI if needed
var my_player_index: int = 1
var my_color: String = "w"  # Tracks whether the local player is white or black
var flip_board_ui: bool = false  # Whether to flip the board UI to put local player at bottom
@onready var rules_button: Button     = %RulesButton
@onready var settings_button: Button = %SettingsButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: Control = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var background: ColorRect = %Background
@onready var player_marker: TextureRect = %PlayerMarker
@onready var opp_marker: TextureRect = %OpponentMarker


const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const RULES_POPUP_SCENE = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")

var sent_tween: Tween
var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"

# Chess state - managed by ChessBoard instance
# Property wrappers provide read access to game_board state. Mutations should go through
# game_board methods (execute_move, commit_move, etc.) rather than direct assignment.
var game_board: ChessBoard = null  # Main state manager

# Read-only access to board state (mutations through game_board.execute_move())
var board: Array:
	get: return game_board.board if game_board else []

# Turn can be set during game data parsing and commit
var turn: String:
	get: return game_board.turn if game_board else "w"
	set(value):
		if game_board:
			game_board.turn = value

# Castling can be set during game data parsing (inferred from position)
var castling: String:
	get: return game_board.castling if game_board else "KQkq"
	set(value):
		if game_board:
			game_board.castling = value

# Read-only access (managed by game_board.execute_move())
var en_passant: String:
	get: return game_board.en_passant if game_board else "-"

var halfmove: int:
	get: return game_board.halfmove if game_board else 0

var fullmove: int:
	get: return game_board.fullmove if game_board else 1

var prev_board_gp: String:
	get: return game_board.prev_board_gp if game_board else ""

# UI grid arrays - each is an 8-element Array where each element is an 8-element Array
# Access pattern: grid[rank][file] where rank=0-7, file=0-7
# GDScript doesn't support Array[Array[T]] so we document the expected types here
var squares: Array = []              ## 8x8 grid: Array[Array[ColorRect]] - board square backgrounds
var pieces: Array = []               ## 8x8 grid: Array[Array[TextureRect]] - piece textures
var move_overlays: Array = []        ## 8x8 grid: Array[Array[ColorRect]] - legal move highlights
var king_overlays: Array = []        ## 8x8 grid: Array[Array[ColorRect]] - king-in-check highlights
var board_container: Control = null  # Container for batch insertion of board elements
var highlighted: Array[Vector2i] = []          # list of positions being highlighted
var selected: Vector2i = Vector2i(-1, -1)           # selected square or Vector2i(-1, -1) when none
var legal_moves: Array[Vector2i] = []          # array of Vector2i targets for selected
var opponent_last_move_from: Vector2i = Vector2i(-1, -1)  # opponent's last move origin square (for green highlight)
var opponent_last_move_to: Vector2i = Vector2i(-1, -1)    # opponent's last move destination square (for green highlight)
var game_settings_category: String = ""
var spectator_mode: bool = false

# UI controls
var send_button: Button = null
var undo_arrow_label: Label = null
var player_chess_black: Sprite2D = null
var player_chess_white: Sprite2D = null

# Promotion state (dialogs managed by ChessDialogs)
var promotion_choice: String = ""  # "Q", "R", "B", or "N", set when user chooses
var promotion_pending_from: Vector2i = Vector2i(-1, -1)
var promotion_pending_to: Vector2i = Vector2i(-1, -1)
var last_move_promotion_piece: String = ""  # Store promotion piece for UCI notation

# Winner side for nicer game-over messaging
var game_over_winner_side: String = ""  # "w", "b", or ""

# Coordinate axis labels
var file_labels: Array[Label] = []   # Labels for a–h along the bottom
var rank_labels: Array[Label] = []   # Labels for 1–8 along the left

# UI labels
var check_label: Label = null
var game_over_label: Label = null

# Repetition - read-only access (managed by game_board internally)
var position_counts: Dictionary:
	get: return game_board.position_counts if game_board else {}

var game_over: bool = false
var game_over_reason: String = ""  # "checkmate", "stalemate", "draw", etc.
var game_over_state: ChessEngine.GameState = ChessEngine.GameState.ONGOING

# Animation controller
var animations: ChessAnimations = ChessAnimations.new()

# Dialog manager
var dialogs: ChessDialogs = ChessDialogs.new()

var is_processing_game_data: bool = false   # Prevents concurrent _set_game_data() calls

## Property wrapper for animation state
var is_animating: bool:
	get: return animations.is_animating()
	set(value): pass  # Read-only, controlled by animations

## Property wrapper for promotion state
var awaiting_promotion: bool:
	get: return dialogs.awaiting_promotion
	set(value): dialogs.awaiting_promotion = value

# ---------- Debug helpers ----------
func _log(msg: String) -> void:
	print(">> CHESSDBG: " + msg)

func _debug_state(tag: String = "") -> void:
	_log("[%s] turn=%s my_color=%s local_mode=%s isTurn=%s waitingForOpponent=%s fullmove=%d halfmove=%d castling=%s en_passant=%s game_over=%s reason=%s"
		% [tag, turn, my_color, str(local_mode), str(isTurn), str(waitingForOpponent), fullmove, halfmove, castling, en_passant, str(game_over), game_over_reason])


# ---------- Scoped Loggers (Consolidated) ----------
## Pre-initialized loggers for each context to avoid repeated context strings
## Consolidated from 10 loggers to 5 for cleaner code:
## - INIT: Initialization only
## - GAME: Move execution, turn management, engine evaluation (was MOVE, TURN, ENGINE)
## - UI: UI rendering, input handling, promotion dialogs (was UI, INPUT, PROMO)
## - DATA: Data parsing, notation conversion (was DATA, NOTATION)
## - BOARD: Board state management
var _log_init := ChessDebug.ScopedLogger.new("INIT")
var _log_game := ChessDebug.ScopedLogger.new("GAME")
var _log_ui := ChessDebug.ScopedLogger.new("UI")
var _log_data := ChessDebug.ScopedLogger.new("DATA")
var _log_board := ChessDebug.ScopedLogger.new("BOARD")

## Get standardized game state dictionary for logging.
func _game_state_dict() -> Dictionary:
	return {
		"turn": turn,
		"my_color": my_color,
		"local_mode": local_mode,
		"isTurn": isTurn,
		"waitingForOpponent": waitingForOpponent,
		"fullmove": fullmove,
		"halfmove": halfmove,
		"castling": castling,
		"en_passant": en_passant,
		"game_over": game_over,
		"reason": game_over_reason
	}

## Calculate player index from GamePigeon protocol fields.
## GamePigeon protocol: The "player" field indicates whose turn it currently is.
## - If it's NOT your turn, you are the OPPOSITE of the message player (flip 1↔2)
## - If it IS your turn, you are the SAME as the message player
## Returns the local player's index (1 = black, 2 = white)
func _calculate_player_index(is_your_turn: bool, message_player: int) -> int:
	return message_player if is_your_turn else (3 - message_player)

# ---------- Ready / plugin ----------
func _ready() -> void:
	_log_init.info("_ready() start")

	# Initialize ChessBoard instance first - this manages all game state
	game_board = ChessBoard.new(true)  # Start with initial position
	_log_init.debug("ChessBoard instance initialized")

	var is_dark = bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)
	if is_instance_valid(rules_button):
		rules_button.pressed.connect(on_rules_button_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)

	appPlugin = Engine.get_singleton("AppPlugin")
	local_mode = (appPlugin == null)
	if not local_mode:
		_log_init.info("AppPlugin found")
		if not appPlugin.is_connected("set_game_data", _set_game_data):
			appPlugin.connect("set_game_data", _set_game_data)
		my_player_id = appPlugin.getSenderUUID()
		# Board already initialized by ChessBoard.new(true) with starting position
		_update_turn_flags()
		appPlugin.onReady()
	else:
		_log_init.debug("No AppPlugin (local debug mode)")
		my_player_index = 2  # Player 2 is white
		my_color = "w"
		flip_board_ui = false
		# Board already initialized by ChessBoard.new(true) with starting position
		_update_turn_flags()
	_log_init.game_state("_ready after init", _game_state_dict())
	_compute_sizes()
	_build_board_ui()
	_refresh_board_ui()
	_update_waiting_label()
	_log_init.info("_ready() complete")

func _set_game_data(raw: String) -> void:
	_log_data.debug("_set_game_data invoked; raw length=%d" % raw.length())

	# Prevent concurrent executions to avoid race conditions with animations and UI rebuilds
	if is_processing_game_data:
		_log_data.trace("_set_game_data: already processing, ignoring concurrent call")
		return
	is_processing_game_data = true

	# Process the game data in a helper to ensure cleanup always happens
	await _set_game_data_impl(raw)

	# Always release the guard flag (guaranteed cleanup)
	is_processing_game_data = false
	_log_data.info("_set_game_data complete")

## Internal implementation of _set_game_data - separated to ensure guard flag cleanup
func _set_game_data_impl(raw: String) -> void:
	var orientation_changed: bool = false  # Track if board orientation changes
	var ui_already_rebuilt: bool = false  # Track if we rebuilt UI early (before animation)
	var data: Variant = JSON.parse_string(raw)
	var opponent_avatar_key = ""
	_log_data.debug("_set_game_data parse result type=%s" % typeof(data))
	if typeof(data) == TYPE_DICTIONARY:
		_log_data.debug("_set_game_data: dictionary keys = %s" % str(data.keys()))

		# Determine player assignment from GamePigeon protocol fields
		var isYourTurn: bool = bool(data.get("isYourTurn", false))
		var message_player: int = int(data.get("player", 2))
		_log_data.debug("_set_game_data: isYourTurn=%s, message_player=%d" % [str(isYourTurn), message_player])

		my_player_index = _calculate_player_index(isYourTurn, message_player)
		enemy_player_index = 3 - my_player_index  # Flip: 1↔2
		_log_data.debug("Player assignment: my_player=%d, enemy_player=%d" % [my_player_index, enemy_player_index])

		# Player 1 = black, Player 2 = white (GamePigeon convention)
		my_color = "b" if my_player_index == 1 else "w"
		var opp_color: String = ChessPiece.opposite_side(my_color)
		if my_player_index == 1:
			opponent_avatar_key = "avatar1"
		else:
			opponent_avatar_key = "avatar2"
		player_marker.modulate = ChessUI.get_marker_color(my_color)
		opp_marker.modulate = ChessUI.get_marker_color(opp_color)

		if opponent_avatar_key != "" and data.has(opponent_avatar_key):
			var avatar_string = data[opponent_avatar_key]
			var opponent_data = _parse_avatar_string(avatar_string)

			if is_instance_valid(opp_avatar_display):
				opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
		# Track if orientation changed (for UI rebuild detection)
		var old_flip_board_ui = flip_board_ui
		flip_board_ui = (my_color == "b")
		orientation_changed = (old_flip_board_ui != flip_board_ui)

		if not spectator_mode:
			if isYourTurn: stop_waiting_animation()

		_log_data.debug("Player assignment: index=%d, color=%s, flip=%s" % [my_player_index, my_color, str(flip_board_ui)])
		_log_data.debug("Board orientation: %s at bottom (changed: %s)" % ["Black" if flip_board_ui else "White", str(orientation_changed)])

		# If orientation changed, flip the existing UI (faster than full rebuild)
		if orientation_changed and _ui_ready():
			_log_data.debug("Flipping board orientation (no rebuild)")
			_flip_board_ui()
			_refresh_board_ui()
			ui_already_rebuilt = true

		my_player_id = str(data.get("myPlayerId", my_player_id))
		_log_data.debug("my_player_id=%s" % my_player_id)

		# Parse the game state - GamePigeon format only
		var replay = str(data.get("replay", ""))
		_log_data.debug("replay='%s'" % replay)
		if replay.begins_with("board:") or replay.find("|board:") != -1:
			# GamePigeon format
			_log_data.debug("Detected GamePigeon format replay")
			await parse_gp_replay(replay)
		else:
			# If not provided, ensure at least initial state (GamePigeon format)
			if board.is_empty():
				_log_data.debug("No replay data, using initial position")
				gp_array_to_board("12,13,14,15,16,14,13,12,11,11,11,11,11,11,11,11,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,21,21,21,21,21,21,21,21,22,23,24,25,26,24,23,22")

		# Determine if it's our turn based on the current turn in the FEN
		_update_turn_flags()

		# Override with explicit isYourTurn from message data (for initial state and updates)
		isTurn = isYourTurn
		waitingForOpponent = not isTurn
		# Update board turn to match message data
		if isTurn:
			turn = my_color
		else:
			turn = ChessPiece.opposite_side(my_color)
		_log_data.debug("Turn flags: isTurn=%s, waiting=%s, turn=%s" % [str(isTurn), str(waitingForOpponent), turn])

	_log_data.game_state("_set_game_data end", _game_state_dict())

	# If orientation changed AND UI already built, flip it (much faster than full rebuild)
	# (Skip if we already flipped earlier before animation to prevent jarring flip)
	# Otherwise, if UI already built, just refresh it. Otherwise, build for first time.
	if orientation_changed and _ui_ready() and not ui_already_rebuilt:
		_log_data.debug("Board orientation changed, flipping UI")
		_flip_board_ui()
		_refresh_board_ui()
	elif _ui_ready():
		_log_data.debug("UI already built, refreshing")
		_refresh_board_ui()
	else:
		_log_data.debug("Building UI for first time")
		_compute_sizes()
		_build_board_ui()
		_refresh_board_ui()

	# Update the waiting label to show/hide based on current state
	_update_waiting_label()

func _update_turn_flags() -> void:
	# canonicalize interaction flags based on board 'turn' and local 'my_color'
	if game_over:
		isTurn = false
		waitingForOpponent = true
		_log_game.debug("_update_turn_flags: game over, interaction disabled")
		return
	if local_mode:
		# In local debug mode: always allow interaction for both sides.
		isTurn = true
		waitingForOpponent = false
		_log_game.debug("_update_turn_flags: local mode, isTurn=true")
	else:
		isTurn = (turn == my_color)
		waitingForOpponent = not isTurn
		_log_game.debug("_update_turn_flags: isTurn=%s, waiting=%s" % [str(isTurn), str(waitingForOpponent)])
	_log_game.game_state("_update_turn_flags", _game_state_dict())

func _update_waiting_label() -> void:
	# Show or hide the waiting label based on waitingForOpponent flag
	if waiting_label == null:
		waiting_label = get_node_or_null("waitingLabel")

	if waiting_label != null:
		if waitingForOpponent and not game_over:
			waiting_label.visible = true
			_log_ui.debug("Showing waiting label")
		else:
			waiting_label.visible = false
			_log_ui.debug("Hiding waiting label")
	else:
		_log_ui.info("waiting_label node not found")

# ---------- UI / sizes ----------
func _compute_sizes() -> void:
	# Delegate to ChessUI.calculate_board_dimensions for consistent dimension calculations
	var vp: Vector2 = get_viewport_rect().size
	var dims: Dictionary = ChessUI.calculate_board_dimensions(vp)

	SQUARE_SIZE = dims["square_size"]
	BORDER_THICK = dims["border_thick"]
	BOARD_ORIGIN = dims["board_origin"]
	BLACK_THICK = dims["black_thick"]

	_log_ui.debug("_compute_sizes: SQUARE_SIZE=%d, BORDER_THICK=%d, BOARD_ORIGIN=%s" % [SQUARE_SIZE, BORDER_THICK, str(BOARD_ORIGIN)])

## Flip board orientation without rebuilding nodes.
## Updates positions of existing squares, pieces, overlays, and labels in-place.
## This is ~200x faster than _build_board_ui() since it avoids node allocation/deallocation.
func _flip_board_ui() -> void:
	_log_ui.debug("_flip_board_ui: flipping orientation (flip_board_ui=%s)" % str(flip_board_ui))

	# Flip square, piece, and overlay positions
	for r in range(8):
		for f in range(8):
			# Calculate new Y position based on flip state
			var ui_y: float = (7 - r) * SQUARE_SIZE if not flip_board_ui else r * SQUARE_SIZE
			var new_pos: Vector2 = BOARD_ORIGIN + Vector2(f * SQUARE_SIZE, ui_y)

			# Update square position
			squares[r][f].position = new_pos

			# Update piece position using ChessUI helper for consistent sizing
			var piece_rect: Dictionary = ChessUI.calculate_piece_rect(new_pos, SQUARE_SIZE)
			pieces[r][f].position = piece_rect["position"]

			# Update overlay positions
			var overlay_rect: Dictionary = ChessUI.calculate_overlay_rect(new_pos, SQUARE_SIZE)
			move_overlays[r][f].position = overlay_rect["position"]
			king_overlays[r][f].position = overlay_rect["position"]

	# Update file labels (a-h or h-a depending on flip) using ChessUI helper
	for i in range(8):
		file_labels[i].text = ChessUI.get_file_label(i, flip_board_ui)

	# Update rank labels (1-8 or 8-1 depending on flip) using ChessUI helper
	for i in range(8):
		rank_labels[i].text = str(ChessUI.get_rank_label(i, flip_board_ui))

	_log_ui.debug("_flip_board_ui: positions and labels updated")

func _create_square_elements(r: int, f: int, rect: ColorRect, pieces_row: Array[TextureRect], move_overlays_row: Array[ColorRect], king_overlays_row: Array[ColorRect], container: Control) -> void:
	# Create piece texture using ChessUI helper for consistent sizing
	var tex: TextureRect = TextureRect.new()
	var piece_rect: Dictionary = ChessUI.calculate_piece_rect(rect.position, SQUARE_SIZE)
	tex.position = piece_rect["position"]
	tex.size = piece_rect["size"]
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.z_index = 10  # Pieces layer (above squares, below overlays)
	container.add_child(tex)
	pieces_row.append(tex)

	# Highlight overlay above piece (green/capture/selected) using ChessUI helper
	var ov: ColorRect = ColorRect.new()
	var overlay_rect: Dictionary = ChessUI.calculate_overlay_rect(rect.position, SQUARE_SIZE)
	ov.position = overlay_rect["position"]
	ov.size = overlay_rect["size"]
	ov.color = Color(0.2, 0.8, 0.2, ChessUI.OVERLAY_ALPHA)
	ov.visible = false
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.z_index = 20  # Overlays layer (above pieces)
	container.add_child(ov)
	move_overlays_row.append(ov)

	# King highlight overlay (red) - separate so it can show when in check
	var k_ov: ColorRect = ColorRect.new()
	k_ov.position = overlay_rect["position"]
	k_ov.size = overlay_rect["size"]
	k_ov.color = ChessUI.CHECK_COLOR
	k_ov.visible = false
	k_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	k_ov.z_index = 20  # Overlays layer (above pieces)
	container.add_child(k_ov)
	king_overlays_row.append(k_ov)

func _build_board_ui() -> void:
	_log_ui.info("_build_board_ui start")

	# Stop all pulse animations before freeing UI elements to prevent tween warnings
	var tween_count: int = animations.get_pulse_count()
	animations.stop_all_pulses()
	_log_ui.debug("_build_board_ui: stopped and cleared %d pulse tweens" % tween_count)

	# free previous UI if needed
	for r in squares:
		for c in r:
			if is_instance_valid(c):
				c.queue_free()
	for r in pieces:
		for c in r:
			if is_instance_valid(c):
				c.queue_free()
	for r in move_overlays:
		for c in r:
			if is_instance_valid(c):
				c.queue_free()
	for r in king_overlays:
		for c in r:
			if is_instance_valid(c):
				c.queue_free()
	for l in file_labels:
		if is_instance_valid(l):
			l.queue_free()
	for l in rank_labels:
		if is_instance_valid(l):
			l.queue_free()

	# Free previous board container (includes all board elements)
	if is_instance_valid(board_container):
		board_container.queue_free()
	board_container = null

	# Free previous border if present
	if is_instance_valid(board_border):
		board_border.queue_free()
	board_border = null
	if is_instance_valid(black_border):
		black_border.queue_free()
	black_border = null

	squares.clear()
	pieces.clear()
	move_overlays.clear()
	king_overlays.clear()
	file_labels.clear()
	rank_labels.clear()
	highlighted.clear()

	# Create container for batch insertion of board elements
	# This reduces scene tree notifications from ~200+ individual add_child calls to a single insertion
	board_container = Control.new()
	board_container.name = "BoardContainer"
	board_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Build board border
	var board_w: float = SQUARE_SIZE * 8.0
	var board_h: float = SQUARE_SIZE * 8.0
	board_border = ColorRect.new()
	board_border.color = ChessUI.BORDER_COLOR
	board_border.position = BOARD_ORIGIN - Vector2(BORDER_THICK, BORDER_THICK)
	board_border.size = Vector2(board_w + 2.0 * BORDER_THICK, board_h + 2.0 * BORDER_THICK)
	board_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_border.z_index = -2  # Bottom layer (below everything)
	board_container.add_child(board_border)

	# Inner black border between brown border and board
	black_border = ColorRect.new()
	black_border.color = Color(0,0,0)
	black_border.position = BOARD_ORIGIN - Vector2(BLACK_THICK, BLACK_THICK)
	black_border.size = Vector2(board_w + 2.0 * BLACK_THICK, board_h + 2.0 * BLACK_THICK)
	black_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black_border.z_index = -1  # Second layer (above brown border, below squares)
	board_container.add_child(black_border)

	# Build board squares, piece rects, move overlays, and king overlays
	for r in range(8):
		var squares_row: Array[ColorRect] = []
		var pieces_row: Array[TextureRect] = []
		var move_overlays_row: Array[ColorRect] = []
		var king_overlays_row: Array[ColorRect] = []

		for f in range(8):
			var rect: ColorRect = ColorRect.new()
			rect.size = Vector2(SQUARE_SIZE, SQUARE_SIZE)
			var ui_y: float = (7 - r) * SQUARE_SIZE if not flip_board_ui else r * SQUARE_SIZE
			rect.position = BOARD_ORIGIN + Vector2(f * SQUARE_SIZE, ui_y)
			rect.color = ChessUI.get_square_color(r, f)
			rect.z_index = 0  # Board squares layer (above borders, below pieces)
			board_container.add_child(rect)
			squares_row.append(rect)

			# Create piece elements for this square (using container for batch insertion)
			_create_square_elements(r, f, rect, pieces_row, move_overlays_row, king_overlays_row, board_container)

		squares.append(squares_row)
		pieces.append(pieces_row)
		move_overlays.append(move_overlays_row)
		king_overlays.append(king_overlays_row)

	# Coordinate labels: files and ranks inside the border gutter

	# File letters (a–h) along the bottom, centered within bottom border area
	# When flip_board_ui is true (Black player), reverse the file order (h-a)
	var files_font_size: int = int(maxf(12.0, SQUARE_SIZE * 0.22))
	var file_label_h: float = maxf(12.0, SQUARE_SIZE * 0.28)
	var bottom_y: float = BOARD_ORIGIN.y + board_h
	var file_y: float = bottom_y + (BORDER_THICK - file_label_h) * 0.5
	for f_idx in range(8):
		var fl: Label = Label.new()
		# Use ChessUI helper for consistent file label calculation
		fl.text = ChessUI.get_file_label(f_idx, flip_board_ui)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fl.size = Vector2(SQUARE_SIZE, file_label_h)
		fl.position = Vector2(BOARD_ORIGIN.x + f_idx * SQUARE_SIZE, file_y)
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fl.add_theme_font_size_override("font_size", files_font_size)
		board_container.add_child(fl)
		file_labels.append(fl)
	_log_ui.debug("_build_board_ui: file labels created with flip_board_ui=%s (order: %s)" % [str(flip_board_ui), "h-a" if flip_board_ui else "a-h"])

	# Rank numbers (1–8) along the left, centered within left border area
	# When flip_board_ui is false (White player): 8 at top, 1 at bottom (standard chess orientation)
	# When flip_board_ui is true (Black player): 1 at top, 8 at bottom (flipped orientation)
	var ranks_font_size: int = int(maxf(12.0, SQUARE_SIZE * 0.22))
	var rank_label_w: float = maxf(12.0, SQUARE_SIZE * 0.24)
	var left_border_left: float = BOARD_ORIGIN.x - BORDER_THICK
	for i in range(8):
		var rl: Label = Label.new()
		# Use ChessUI helper for consistent rank label calculation
		rl.text = str(ChessUI.get_rank_label(i, flip_board_ui))
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rh: float = SQUARE_SIZE * 0.6
		rl.size = Vector2(rank_label_w, rh)
		var y_center: float = BOARD_ORIGIN.y + i * SQUARE_SIZE + SQUARE_SIZE * 0.5
		var y_pos: float = y_center - rh * 0.5
		rl.position = Vector2(left_border_left + (BORDER_THICK - rank_label_w) * 0.5, y_pos)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rl.add_theme_font_size_override("font_size", ranks_font_size)
		board_container.add_child(rl)
		rank_labels.append(rl)
	_log_ui.debug("_build_board_ui: rank labels created with flip_board_ui=%s (order from top: %s)" % [str(flip_board_ui), "1-8" if flip_board_ui else "8-1"])

	# Single tree modification adds all ~260 nodes at once (vs 200+ individual add_child calls)
	add_child(board_container)

	# Create check label and game over label (top of screen)
	if check_label == null:
		check_label = Label.new()
		check_label.name = "CHECK_LABEL"
		check_label.visible = false
		check_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(check_label)
	if game_over_label == null:
		game_over_label = Label.new()
		game_over_label.name = "GAME_OVER_LABEL"
		game_over_label.visible = false
		game_over_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(game_over_label)

	# Style / position labels (positioned below board instead of top)
	# Note: board_w is already declared earlier in this function (line 414)
	var check_label_y: float = BOARD_ORIGIN.y + board_w + BORDER_THICK + 5.0
	check_label.position = Vector2(BOARD_ORIGIN.x, check_label_y)
	check_label.size = Vector2(board_w, 40)
	check_label.add_theme_font_size_override("font_size", 28)
	check_label.add_theme_color_override("font_color", Color(1,0.1,0.1))
	check_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check_label.text = ""
	check_label.visible = false

	var game_over_label_y: float = check_label_y + 45.0
	game_over_label.position = Vector2(BOARD_ORIGIN.x - 100, game_over_label_y)
	game_over_label.size = Vector2(board_w + 200, 60)
	game_over_label.add_theme_font_size_override("font_size", 32)
	game_over_label.add_theme_color_override("font_color", Color(0.9,0.2,0.2))
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.text = ""
	game_over_label.visible = false

	# Clean any previous floating UI controls (note: send_button is now a scene node, not cleaned up here)
	if is_instance_valid(undo_arrow_label):
		undo_arrow_label.queue_free()
		undo_arrow_label = null

	# Setup and create dialogs via ChessDialogs controller
	dialogs.cleanup()
	dialogs.setup(self, PIECE_TEXTURES, func(msg: String) -> void: _log_ui.debug(msg))
	dialogs.create_game_over_panel(BOARD_ORIGIN, board_w, SQUARE_SIZE)
	dialogs.create_promotion_dialog(BOARD_ORIGIN, board_w, SQUARE_SIZE)
	_log_ui.debug("_build_board_ui: dialogs controller initialized")

	# Get the Send button from the scene and reposition it
	send_button = get_node("SendButton")
	if send_button:
		# Calculate dynamic size and position based on board dimensions (increased for better visibility)
		var btn_w: float = maxf(120.0, SQUARE_SIZE * 2.4)
		var btn_h: float = maxf(48.0, SQUARE_SIZE * 0.6)
		send_button.size = Vector2(btn_w, btn_h)
		var btn_x: float = BOARD_ORIGIN.x + board_w * 0.5 - btn_w * 0.5
		# Position send button below check label (check label is 40px tall)
		var btn_y: float = BOARD_ORIGIN.y + board_w + BORDER_THICK + 50.0
		send_button.position = Vector2(btn_x, btn_y)
		send_button.disabled = true
		send_button.visible = _has_pending()
		# Connect the pressed signal only if not already connected
		if not send_button.pressed.is_connected(_on_send_pressed):
			send_button.pressed.connect(_on_send_pressed)
			_log_ui.debug("SendButton pressed signal connected to _on_send_pressed")

	# Get and scale the player piece icons based on board piece size
	player_chess_black = get_node("Player1Box/PlayerChessBlack")
	player_chess_white = get_node("Player2Box/PlayerChessWhite")
	
	# Calculate scale based on piece size (pieces on board are SQUARE_SIZE * 0.9)
	# The original texture is large, so we scale it to match the board piece size
	var piece_display_size: float = SQUARE_SIZE * 0.9
	# Assuming the original SVG is around 1000px, scale to match piece_display_size
	var target_scale: float = piece_display_size / 50.0
	
	if is_instance_valid(player_chess_black):
		player_chess_black.scale = Vector2(target_scale, target_scale)
		_log_ui.debug("PlayerChessBlack scaled to %f (piece_size=%f)" % [target_scale, piece_display_size])

	if is_instance_valid(player_chess_white):
		player_chess_white.scale = Vector2(target_scale, target_scale)
		_log_ui.debug("PlayerChessWhite scaled to %f (piece_size=%f)" % [target_scale, piece_display_size])

	# Setup animations controller with UI references
	animations.setup(pieces, squares, get_tree(), func(msg: String) -> void: _log_ui.debug(msg))
	_log_ui.debug("_build_board_ui: animations controller initialized")

	_log_ui.debug("_build_board_ui done")

		# If parse_gp_replay ran earlier and requested evaluation, do it now that UI exists
	if pending_evaluate:
		_log_ui.debug("_build_board_ui: running deferred _evaluate_check_and_update_flags()")
		pending_evaluate = false
		_evaluate_check_and_update_flags()


func _get_piece_texture(code: String) -> Texture2D:
	# Return preloaded PNG texture from PIECE_TEXTURES dictionary
	if code == "":
		return null
	return PIECE_TEXTURES.get(code, null)

func _refresh_board_ui() -> void:
	_log_ui.info("_refresh_board_ui start")

	# If UI hasn't been built yet, skip refresh and request an evaluate after UI is built
	if not _ui_ready():
		_log_ui.debug("_refresh_board_ui: UI not ready (squares/pieces not initialized). Skipping UI refresh.")
		return

	# First, update all piece textures and reset square modulate
	for r: int in range(8):
		for f: int in range(8):
			var code: String = board[r][f]
			var tex: Texture2D = _get_piece_texture(code)
			pieces[r][f].texture = tex

			# Reset piece position and scale (critical for undo and post-animation state)
			# This ensures pieces are at their correct grid positions even if animation was interrupted
			var square: ColorRect = squares[r][f]
			var board_piece_size: Vector2 = Vector2(SQUARE_SIZE * 0.9, SQUARE_SIZE * 0.9)
			var correct_pos: Vector2 = square.position + (square.size - board_piece_size) * 0.5 + Vector2(SQUARE_SIZE * 0.1, SQUARE_SIZE * 0.1)
			pieces[r][f].position = correct_pos
			pieces[r][f].scale = Vector2.ONE

			# Reset default modulate
			squares[r][f].modulate = Color(1,1,1)
			# Hide overlays by default and stop pulsing
			_stop_pulse(move_overlays[r][f])
			move_overlays[r][f].visible = false
			king_overlays[r][f].visible = false

	# Selected square overlay (light blue with pulse)
	if selected != Vector2i(-1, -1):
		var sel_ov: ColorRect = move_overlays[selected.y][selected.x]
		sel_ov.color = ChessUI.SELECTED_COLOR
		sel_ov.visible = true
		_start_pulse(sel_ov)

	# Legal destination overlays (light blue for moves, red for captures)
	for pos: Vector2i in highlighted:
		var r: int = pos.y
		var f: int = pos.x
		var is_capture: bool = board[r][f] != "" and board[r][f][0] != turn
		var ov: ColorRect = move_overlays[r][f]
		ov.color = ChessUI.get_move_highlight_color(is_capture)
		ov.visible = true
		_start_pulse(ov)

	# Opponent's last move highlights (green with pulse)
	# Skip if the square is a legal destination (red/blue highlights take priority)
	if opponent_last_move_from != Vector2i(-1, -1) and opponent_last_move_from not in highlighted:
		var from_ov: ColorRect = move_overlays[opponent_last_move_from.y][opponent_last_move_from.x]
		from_ov.color = ChessUI.OPPONENT_MOVE_COLOR
		from_ov.visible = true
		_start_pulse(from_ov)

	if opponent_last_move_to != Vector2i(-1, -1) and opponent_last_move_to not in highlighted:
		var to_ov: ColorRect = move_overlays[opponent_last_move_to.y][opponent_last_move_to.x]
		to_ov.color = ChessUI.OPPONENT_MOVE_COLOR
		to_ov.visible = true
		_start_pulse(to_ov)

	# If the side-to-move is in check, highlight the king square and dim pieces without legal moves
	var side_to_move: String = turn
	var incheck: bool = _in_check(side_to_move)
	if incheck:
		var kp: Vector2i = ChessEngine.find_king(board, side_to_move)
		if kp.x != -1:
			king_overlays[kp.y][kp.x].visible = true
		# dim same-side pieces without legal moves
		for r: int in range(8):
			for f: int in range(8):
				if board[r][f] != "" and board[r][f][0] == side_to_move:
					var lm: Array[Vector2i] = _legal_moves_for_square(Vector2i(f, r))
					if lm.size() == 0:
						# dim square to indicate this piece cannot help
						squares[r][f].modulate = ChessUI.DIMMED_COLOR
					else:
						# keep normal
						squares[r][f].modulate = Color(1, 1, 1)

	# Update check / game_over labels
	if incheck:
		check_label.text = "CHECK — %s to move" % ("White" if side_to_move == "w" else "Black")
		check_label.visible = true
		# Emit signal for check detection (only when becoming visible)
		check_detected.emit(side_to_move)
	else:
		check_label.visible = false

	if game_over:
		var msg: String = ChessUI.format_result_message(game_over_state, game_over_winner_side, my_color)
		dialogs.show_game_over(msg)
	else:
		dialogs.hide_game_over()
	# Always hide the old top game over label in favor of the centered panel
	game_over_label.visible = false
	
	# Ensure pending-state UI is visible and correct
	if _has_pending():
		var from_sq: Vector2i = _get_pending_from()
		if from_sq != Vector2i(-1, -1):
			# Ensure undo arrow is present and positioned
			if not is_instance_valid(undo_arrow_label):
				_show_undo_arrow(from_sq)
			else:
				var rect: ColorRect = squares[from_sq.y][from_sq.x]
				undo_arrow_label.position = rect.position
				undo_arrow_label.size = rect.size
				undo_arrow_label.z_index = 1000
			# Highlight the origin square as a legal move (light blue with pulse)
			var ov_back: ColorRect = move_overlays[from_sq.y][from_sq.x]
			ov_back.color = ChessUI.LEGAL_MOVE_COLOR
			ov_back.visible = true
			_start_pulse(ov_back)
		if is_instance_valid(send_button):
			send_button.disabled = false
			send_button.visible = true
	else:
		if is_instance_valid(send_button):
			send_button.disabled = true
			send_button.visible = false
	
	_log_ui.debug("_refresh_board_ui done")
	_log_ui.game_state("_refresh_board_ui", _game_state_dict())

# ---------- Highlight pulse helpers (delegated to animations) ----------
func _start_pulse(ov: ColorRect) -> void:
	animations.start_pulse(ov)

func _stop_pulse(ov: ColorRect) -> void:
	animations.stop_pulse(ov)
	# reset modulate alpha
	if is_instance_valid(ov):
		ov.modulate = Color(1,1,1,1)

# ---------- Pending move helpers (delegated to game_board) ----------
## Check if there's a pending move waiting to be sent
func _has_pending() -> bool:
	return game_board.has_pending() if game_board else false

## Set a pending move (stores snapshot for undo)
func _set_pending(from_sq: Vector2i, to_sq: Vector2i) -> void:
	if game_board:
		game_board.set_pending(from_sq, to_sq)

## Clear pending move state
func _clear_pending() -> void:
	if game_board:
		game_board.clear_pending()

## Get pending move origin
func _get_pending_from() -> Vector2i:
	return game_board.get_pending_from() if game_board else Vector2i(-1, -1)

## Get pending move destination
func _get_pending_to() -> Vector2i:
	return game_board.get_pending_to() if game_board else Vector2i(-1, -1)

func _show_undo_arrow(from_sq: Vector2i) -> void:
	_hide_undo_arrow()
	var rect: ColorRect = squares[from_sq.y][from_sq.x]
	undo_arrow_label = Label.new()
	# Use a widely supported back arrow; keep strong outline for contrast.
	undo_arrow_label.text = "↩"
	undo_arrow_label.size = rect.size
	undo_arrow_label.position = rect.position
	undo_arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	undo_arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	undo_arrow_label.add_theme_font_size_override("font_size", int(SQUARE_SIZE * 0.6))
	undo_arrow_label.add_theme_color_override("font_color", Color(1,1,1))
	undo_arrow_label.add_theme_color_override("font_outline_color", Color(0,0,0))
	undo_arrow_label.add_theme_constant_override("outline_size", 3)
	undo_arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ensure it's drawn on top of pieces/overlays.
	undo_arrow_label.z_index = 1000
	add_child(undo_arrow_label)

func _hide_undo_arrow() -> void:
	if is_instance_valid(undo_arrow_label):
		undo_arrow_label.queue_free()
	undo_arrow_label = null

func _show_promotion_dialog(side: String) -> void:
	_log_ui.info("_show_promotion_dialog for side=%s" % side)
	dialogs.show_promotion(side)

func _hide_promotion_dialog() -> void:
	dialogs.hide_promotion()
	promotion_choice = ""
	_log_ui.info("_hide_promotion_dialog: dialog hidden")

func _on_promotion_choice(piece: String) -> void:
	_log_ui.info("_on_promotion_choice: chose %s" % piece)
	promotion_choice = piece
	_hide_promotion_dialog()

	# Now execute the pending promotion move
	if promotion_pending_from != Vector2i(-1, -1) and promotion_pending_to != Vector2i(-1, -1):
		_log_ui.info("_on_promotion_choice: executing promotion move %s -> %s with piece %s" % [_square_name(promotion_pending_from), _square_name(promotion_pending_to), piece])
		_set_pending(promotion_pending_from, promotion_pending_to)

		# Animate the promotion move
		await _animate_player_move(promotion_pending_from, promotion_pending_to)

		_execute_move(promotion_pending_from, promotion_pending_to)
		_show_undo_arrow(_get_pending_from())
		# Send button enabled after move
		if is_instance_valid(send_button):
			send_button.disabled = false
			send_button.visible = true
		selected = Vector2i(-1, -1)
		highlighted.clear()
		legal_moves.clear()
		# Clear promotion state after successful execution
		promotion_pending_from = Vector2i(-1, -1)
		promotion_pending_to = Vector2i(-1, -1)
		_refresh_board_ui()
	else:
		_log_ui.error("_on_promotion_choice: ERROR - no pending promotion move stored")

func _on_send_pressed() -> void:
	_log_ui.debug("_on_send_pressed called: has_pending=%s local_mode=%s" % [str(_has_pending()), str(local_mode)])
	if not _has_pending():
		_log_ui.debug("_on_send_pressed: early return (no pending move)")
		return
	_log_ui.debug("_on_send_pressed: committing pending move %s -> %s" % [_square_name(_get_pending_from()), _square_name(_get_pending_to())])
	# Call _commit_move to switch turns and send to appPlugin
	_commit_move(_get_pending_from(), _get_pending_to())
	# Clear pending state
	_clear_pending()
	_hide_undo_arrow()
	if is_instance_valid(send_button):
		send_button.disabled = true
		send_button.visible = false
	_refresh_board_ui()

func _undo_pending() -> void:
	if not _has_pending():
		return
	_log_ui.debug("_undo_pending: reverting to snapshot via game_board")
	if game_board:
		game_board.undo_pending()
	_hide_undo_arrow()
	if is_instance_valid(send_button):
		send_button.disabled = true
		send_button.visible = false
	_update_turn_flags()
	_refresh_board_ui()

# ---------- Input gating ----------
func _input(event: InputEvent) -> void:
	# _log_ui.game_state("_input at start", _game_state_dict())
	# Only allow interaction when it's allowed by _can_interact
	if not _can_interact():
		# _log_ui.trace("_input: interaction blocked (can_interact=false)")
		# _log_ui.game_state("_input blocked", _game_state_dict())
		return
	
	if event is InputEventScreenTouch and event.pressed:
		_on_tap(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_tap(event.position)

func _can_interact() -> bool:
	if game_over:
		#_log_ui.debug("_can_interact -> false (game over)")
		return false
	if is_animating:
		#_log_ui.debug("_can_interact -> false (animation in progress)")
		return false
	if local_mode:
		# local mode: allow interacting with the board for both sides
		#_log_ui.debug("_can_interact -> true (local_mode)")
		return true
	var allowed: bool = (turn == my_color) and (not waitingForOpponent)
	#_log_ui.debug("_can_interact -> %s (turn=%s my_color=%s waiting=%s)" % [str(allowed), turn, my_color, str(waitingForOpponent)])
	return allowed

func _on_tap(pos: Vector2) -> void:
	_log_ui.trace("_on_tap at pos=%s" % str(pos))

	# Block all input during animation
	if is_animating:
		_log_ui.trace("_on_tap: blocked during animation")
		return

	# If awaiting promotion choice, handle promotion dialog tap
	if dialogs.is_promotion_visible():
		_handle_promotion_tap(pos)
		return

	var sq: Vector2i = _pos_to_square(pos)
	if sq == Vector2i(-1, -1):
		_log_ui.debug("_on_tap: clicked outside board")
		return

	# If a pending move exists, handle undo or commit
	if _has_pending():
		_handle_pending_tap(sq)
		return

	var piece: String = board[sq.y][sq.x]
	_log_ui.debug("_on_tap at square %s piece=%s" % [_square_name(sq), str(piece)])

	if selected == Vector2i(-1, -1):
		_handle_selection_tap(sq, piece)
	else:
		await _handle_move_tap(sq, piece)

## Handle tap on promotion dialog
func _handle_promotion_tap(pos: Vector2) -> void:
	var selected_piece: String = dialogs.handle_promotion_tap(pos)
	if selected_piece != "":
		_log_ui.info("_handle_promotion_tap: clicked %s" % selected_piece)
		_on_promotion_choice(selected_piece)
	else:
		_log_ui.info("_handle_promotion_tap: click not on pieces, ignoring")

## Handle tap when a pending move exists (undo or commit)
func _handle_pending_tap(sq: Vector2i) -> void:
	if sq == _get_pending_from():
		# Tap origin square to undo
		_undo_pending()
	elif local_mode and sq == _get_pending_to():
		# In local mode: tap destination square to commit the move
		_log_ui.debug("_handle_pending_tap: local mode - committing pending move")
		_commit_move(_get_pending_from(), _get_pending_to())
		_clear_pending()
		_hide_undo_arrow()
		_refresh_board_ui()
	else:
		_log_ui.debug("_handle_pending_tap: tap elsewhere; origin to undo" + (" or dest to commit" if local_mode else " or Send"))

## Handle tap when no piece is selected - try to select a piece
func _handle_selection_tap(sq: Vector2i, piece: String) -> void:
	# Allow selecting a piece if it belongs to the side to move and (local_mode or our color)
	if piece != "" and piece[0] == turn and (local_mode or piece[0] == my_color):
		var candidate_moves: Array[Vector2i] = _legal_moves_for_square(sq)
		if candidate_moves.size() == 0:
			_log_ui.info("_handle_selection_tap: %s at %s has no legal moves" % [piece, _square_name(sq)])
		else:
			selected = sq
			legal_moves = candidate_moves
			highlighted.clear()
			for m in legal_moves:
				highlighted.append(m)
			_log_ui.info("_handle_selection_tap: selected %s at %s ; moves=%d" % [piece, _square_name(sq), legal_moves.size()])
			_refresh_board_ui()
	else:
		_log_ui.debug("_handle_selection_tap: can't select (empty or not permitted)")

## Handle tap when a piece is already selected - try to move or reselect
func _handle_move_tap(sq: Vector2i, piece: String) -> void:
	_log_ui.info("_handle_move_tap: piece selected at %s ; checking move to %s" % [_square_name(selected), _square_name(sq)])

	# Check if tapped square is a legal move destination
	for m in legal_moves:
		if m == sq:
			_log_ui.info("_handle_move_tap: legal move %s -> %s" % [_square_name(selected), _square_name(sq)])

			# Check if this is a pawn promotion move
			var moving_piece: String = board[selected.y][selected.x]
			if _is_promotion_move(moving_piece, sq.y):
				_log_ui.info("_handle_move_tap: promotion move detected")
				promotion_pending_from = selected
				promotion_pending_to = sq
				_clear_selection()
				_show_promotion_dialog(moving_piece[0])
				return

			# Execute normal move with pending state
			_set_pending(selected, sq)
			await _animate_player_move(selected, _get_pending_to())
			_execute_move(selected, _get_pending_to())
			_show_undo_arrow(_get_pending_from())
			if is_instance_valid(send_button):
				send_button.disabled = false
				send_button.visible = true
			_clear_selection()
			_refresh_board_ui()
			return

	# Not a legal move - try to reselect a different piece
	if piece != "" and piece[0] == turn and (local_mode or piece[0] == my_color):
		var candidate_moves: Array[Vector2i] = _legal_moves_for_square(sq)
		if candidate_moves.size() == 0:
			_log_ui.info("_handle_move_tap: reselect %s at %s has no legal moves" % [piece, _square_name(sq)])
			_clear_selection()
			_refresh_board_ui()
		else:
			selected = sq
			legal_moves = candidate_moves
			highlighted.clear()
			for m in legal_moves:
				highlighted.append(m)
			_log_ui.info("_handle_move_tap: reselected %s at %s ; moves=%d" % [piece, _square_name(sq), legal_moves.size()])
			_refresh_board_ui()
	else:
		_clear_selection()
		_refresh_board_ui()
		_log_ui.info("_handle_move_tap: deselected")

## Check if a pawn move is a promotion move
## Delegates to ChessPiece for single source of truth
func _is_promotion_move(piece: String, dest_rank: int) -> bool:
	if piece == "" or piece[1] != "P":
		return false
	# Create temporary ChessPiece to use canonical promotion logic
	# Board orientation: rank 7 = white promotes, rank 0 = black promotes
	var chess_piece: ChessPiece = ChessPiece.from_notation(piece)
	if chess_piece == null:
		return false
	return chess_piece.is_promotion_move(Vector2i(0, dest_rank))  # file doesn't matter for rank check

## Clear selection state
func _clear_selection() -> void:
	selected = Vector2i(-1, -1)
	highlighted.clear()
	legal_moves.clear()

func _pos_to_square(pos: Vector2) -> Vector2i:
	var sq: Vector2i = ChessUI.screen_to_board(pos, BOARD_ORIGIN, SQUARE_SIZE, flip_board_ui)
	_log_ui.trace("_pos_to_square: screen_pos=%s -> board_pos=%s [flip=%s]" % [
		str(pos), _square_name(sq) if sq.x >= 0 else "(-1,-1)", str(flip_board_ui)
	])
	return sq

#======================== Chess engine ========================
#======================== GamePigeon format conversion ========================
# GamePigeon uses a flat 64-element array where index = file + (rank * 8)
# Piece encoding: 0=empty, white: 11=P, 12=R, 13=N, 14=B, 15=Q, 16=K
#                          black: 21=P, 22=R, 23=N, 24=B, 25=Q, 26=K

func board_to_gp_array() -> String:
	"""Convert internal 8x8 board to GamePigeon's flat 64-element comma-separated string."""
	if game_board:
		return game_board.to_gp_array()
	return ChessNotation.board_to_gp_array(board)

func gp_array_to_board(gp_array_str: String) -> void:
	"""Parse GamePigeon's 64-element comma-separated string into internal 8x8 board.
	Delegates to ChessBoard.load_from_gp() which handles board update and castling inference."""
	_log_data.debug("gp_array_to_board: parsing '%s'" % gp_array_str)
	if game_board:
		game_board.load_from_gp(gp_array_str)
		_log_data.debug("gp_array_to_board: board populated via ChessBoard")
	else:
		# Initialize game_board if not already initialized (fallback for edge cases)
		push_warning("ChessTop.gp_array_to_board: game_board not initialized, creating now")
		game_board = ChessBoard.new(false)
		game_board.load_from_gp(gp_array_str)
		_log_data.debug("gp_array_to_board: created game_board and populated")

func parse_gp_replay(replay: String) -> void:
	"""Parse GamePigeon replay string format: board:<prev>|move:<from_f>,<from_r>,<to_f>,<to_r>|board:<current>"""
	_log_data.debug("parse_gp_replay: '%s'" % replay)

	# Use ChessNotation to parse the replay string
	var parsed: Dictionary = ChessNotation.parse_gp_replay(replay)
	var prev_board: String = parsed["prev_board"]
	var current_board: String = parsed["current_board"]
	var move_from: Vector2i = parsed["move_from"]
	var move_to: Vector2i = parsed["move_to"]
	var has_move: bool = parsed["has_move"]

	if current_board == "":
		_log_data.info("parse_gp_replay: no board state found in replay")
		return

	# If we have move coordinates, animate the move
	if has_move and prev_board != "":
		# Store opponent's last move for green highlighting
		opponent_last_move_from = move_from
		opponent_last_move_to = move_to
		_log_data.debug("parse_gp_replay: stored opponent last move %s -> %s" % [
			_square_name(opponent_last_move_from),
			_square_name(opponent_last_move_to)
		])

		_log_data.debug("parse_gp_replay: animating move %s -> %s" % [
			_square_name(move_from),
			_square_name(move_to)
		])

		# Set board to previous state for animation
		gp_array_to_board(prev_board)
		if _ui_ready():
			_refresh_board_ui()

		# Animate the opponent's move
		await _animate_opponent_move(move_from, move_to, current_board)
	else:
		_log_data.debug("parse_gp_replay: no move data, just updating to current board (initial position)")

	# Set final board state
	gp_array_to_board(current_board)
	# Infer castling rights from the current board state since GamePigeon format
	# doesn't include this information - we check if kings and rooks are on starting squares
	castling = ChessNotation.infer_castling_rights(board)
	_log_data.debug("parse_gp_replay: inferred castling rights = '%s'" % castling)

	if _ui_ready():
		_evaluate_check_and_update_flags()
	else:
		pending_evaluate = true
	_log_data.game_state("parse_gp_replay end", _game_state_dict())

func to_position_key() -> String:
	"""Generate unique position key for threefold repetition detection.
	Includes board state, turn, castling rights, and en passant target."""
	return ChessNotation.to_position_key(board, turn, castling, en_passant)

# ---------- Animation Functions (delegated to ChessAnimations) ----------

func _animate_player_move(from_sq: Vector2i, to_sq: Vector2i) -> void:
	## Animate a player's move. Handles castling, en passant, captures, and normal moves.
	_log_ui.debug("_animate_player_move: %s -> %s" % [_square_name(from_sq), _square_name(to_sq)])
	await animations.animate_move(from_sq, to_sq, board)

func _animate_opponent_move(from_sq: Vector2i, to_sq: Vector2i, _final_board_gp: String) -> void:
	## Animate opponent's move during replay.
	_log_ui.debug("_animate_opponent_move: %s -> %s" % [_square_name(from_sq), _square_name(to_sq)])
	await animations.animate_move(from_sq, to_sq, board)

func _in_check(side: String) -> bool:
	return ChessEngine.is_in_check(board, side)

func _legal_moves_for_square(from_sq: Vector2i) -> Array[Vector2i]:
	## Get legal moves for a piece at the given position.
	## Delegates to ChessEngine.get_legal_moves().
	var piece: String = board[from_sq.y][from_sq.x]
	if piece == "":
		_log_game.debug("_legal_moves_for_square: empty square %s" % _square_name(from_sq))
		return []
	if piece[0] != turn:
		_log_game.debug("_legal_moves_for_square: piece side %s != turn %s" % [piece[0], turn])
		return []
	_log_game.debug("_legal_moves_for_square: generating for %s at %s" % [piece, _square_name(from_sq)])
	var legal: Array[Vector2i] = ChessEngine.get_legal_moves(board, from_sq, turn, en_passant, castling)
	_log_game.info("  legal moves count=%d" % legal.size())
	return legal

# Execute the physical move on the board (first half of move logic)
# Does NOT switch turns - that happens in _commit_move
# Delegates to ChessBoard.execute_move() for actual move execution
func _execute_move(from_sq: Vector2i, to_sq: Vector2i) -> void:
	_log_game.debug("_execute_move called %s -> %s" % [_square_name(from_sq), _square_name(to_sq)])
	_log_game.game_state("before_execute", _game_state_dict())

	if not game_board:
		_log_game.debug("_execute_move: game_board not initialized")
		return

	# Determine promotion piece
	var promo: String = promotion_choice if promotion_choice != "" else ""

	# Delegate to ChessBoard
	var result: Dictionary = game_board.execute_move(from_sq, to_sq, promo)

	if not result["success"]:
		_log_game.debug("_execute_move: ChessBoard.execute_move() failed")
		return

	# Store promotion piece for UCI notation
	if result["is_promotion"]:
		last_move_promotion_piece = promo if promo != "" else "Q"
		_log_game.info("_execute_move promotion -> %s" % last_move_promotion_piece)

	# Clear promotion_choice after using it
	promotion_choice = ""

	# Log special moves
	if result["is_castle"]:
		_log_game.info("_execute_move castling detected")
	if result["is_en_passant"]:
		_log_game.debug("_execute_move en-passant capture at %s" % str(result["en_passant_capture"]))

	# Emit signal for observers (sound effects, analytics, etc.)
	var moving_piece: String = board[to_sq.y][to_sq.x]
	move_executed.emit(from_sq, to_sq, moving_piece)

	_log_game.info("_execute_move complete (board updated, turn NOT switched yet)")
	_log_game.game_state("after_execute", _game_state_dict())

# Commit the move: switch turns, check game end, send to appPlugin (second half of move logic)
# This is called after _execute_move when the player confirms the move via send button
func _commit_move(from_sq: Vector2i, to_sq: Vector2i) -> void:
	_log_game.debug("_commit_move called %s -> %s" % [_square_name(from_sq), _square_name(to_sq)])
	_log_game.game_state("before_commit", _game_state_dict())
	var uci: String = _to_uci(from_sq, to_sq)
	last_move_promotion_piece = ""  # Clear after using in UCI
	var moving: String = board[to_sq.y][to_sq.x]  # piece is already at destination
	var side: String = moving[0]

	# Use ChessBoard.commit_move() to properly switch turn, increment fullmove, and count position
	var old_turn: String = turn
	game_board.commit_move()
	_log_game.debug("_commit_move flipped turn %s -> %s" % [old_turn, turn])

	# Emit signal for turn change
	turn_changed.emit(turn)

	_log_game.game_state("after_commit", _game_state_dict())

	# Clear opponent's last move highlights (player is making their move now)
	opponent_last_move_from = Vector2i(-1, -1)
	opponent_last_move_to = Vector2i(-1, -1)
	_log_game.debug("_commit_move: cleared opponent last move highlights")

	# Determine game end conditions using ChessBoard's evaluate_state()
	var winner_decl = null
	var eval_result: Dictionary = game_board.evaluate_state()
	var state: ChessEngine.GameState = eval_result["state"]
	var winner_side: String = eval_result["winner_side"]

	if ChessEngine.is_game_over(state):
		game_over = true
		game_over_state = state
		game_over_reason = ChessEngine.state_description(state, winner_side)
		game_over_winner_side = winner_side
		_log_game.info("_commit_move detected %s" % game_over_reason)

		# Emit signal for game over
		game_over_detected.emit(winner_side, game_over_reason)

		# Calculate winner_decl for network protocol
		if state == ChessEngine.GameState.CHECKMATE:
			# Winner is the side that delivered checkmate (the side that just moved)
			var winner_player_index: int = my_player_index if side == my_color else enemy_player_index
			winner_decl = my_player_id + "|" + str(winner_player_index)
		else:
			# Draw (stalemate, insufficient material, 50-move, repetition)
			winner_decl = my_player_id + "|0"

	# Export data to host in GamePigeon format
	var gp_replay = game_board.generate_replay(from_sq, to_sq)
	_log_game.debug("_commit_move: generated GamePigeon replay: %s" % gp_replay)
	var to_send = {
		"replay": gp_replay
	}
	var avatar_key := ("avatar2" if my_player_index == 1 else "avatar1")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		to_send[avatar_key] = player_avatar_display.get_avatar_data_string()
	if winner_decl != null:
		to_send["winner"] = winner_decl
		waitingForOpponent = true
		isTurn = false
		_log_game.debug("_commit_move: game ended, winner_decl=%s" % str(winner_decl))
	else:
		play_sent_animation()
		if not local_mode:
			waitingForOpponent = true
			isTurn = false
			_log_game.debug("_commit_move: remote mode - set waitingForOpponent=true, isTurn=false (waiting for remote update)")
		else:
			# local debug: keep interaction enabled for the other side (allow playing both sides)
			waitingForOpponent = false
			isTurn = true
			_log_game.debug("_commit_move: local mode - kept interaction enabled for both sides")

	# Evaluate check/stalemate on the new position to update UI/selectability
	_evaluate_check_and_update_flags()
	
	# Update the waiting label to reflect the new waiting state
	_update_waiting_label()

	# Send to appPlugin (always send in commit)
	_log_game.game_state("_commit_move before send", _game_state_dict())
	if not local_mode:
		_log_game.debug("_commit_move sending updateGameData: %s" % str(to_send))
		appPlugin.updateGameData(JSON.stringify(to_send))
	else:
		_log_game.debug("_commit_move local-only; not sending to appPlugin")
	_log_game.info("_commit_move complete")

func _evaluate_check_and_update_flags() -> void:
	## Evaluate game state using ChessBoard and update UI flags accordingly.
	var result: Dictionary = game_board.evaluate_state()
	var state: ChessEngine.GameState = result["state"]
	var in_check: bool = result["in_check"]
	var has_legal: bool = result["has_legal_moves"]
	var winner_side: String = result["winner_side"]

	_log_game.debug("_evaluate_check_and_update_flags: state=%s in_check=%s has_legal=%s winner=%s" % [
		ChessEngine.state_description(state, winner_side), str(in_check), str(has_legal), winner_side
	])

	# Map engine state to local game state variables
	if ChessEngine.is_game_over(state):
		game_over = true
		game_over_state = state
		game_over_reason = ChessEngine.state_description(state, winner_side)
		game_over_winner_side = winner_side
		waitingForOpponent = true
		isTurn = false
	else:
		# Game is ongoing (may be in check but not over)
		if game_over and has_legal:
			# Clear game_over if somehow has legal moves (unlikely during normal play)
			game_over = false
			game_over_state = ChessEngine.GameState.ONGOING
			game_over_reason = ""
			game_over_winner_side = ""
		# Ensure interaction flags stay aligned
		_update_turn_flags()

	if in_check:
		_log_game.debug("Game state: %s is currently in CHECK" % turn)

	# Refresh UI to show disabled pieces / highlight king-in-check / game over
	_refresh_board_ui()

func _to_uci(from_sq: Vector2i, to_sq: Vector2i) -> String:
	return ChessNotation.to_uci(from_sq, to_sq, last_move_promotion_piece)

func _square_name(sq: Vector2i) -> String:
	return ChessNotation.square_name(sq)

func _ui_ready() -> bool:
	# Ensure the UI arrays exist and have 8x8 elements before attempting UI work
	if squares.size() != 8 or pieces.size() != 8 or move_overlays.size() != 8 or king_overlays.size() != 8:
		return false
	for row in pieces:
		if row.size() != 8:
			return false
	return true

#Settings, Rules, and Avatar Code

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

	var read_color = func(vals: Array) -> Color:
		if vals.size() >= 3:
			return Color(vals[0].to_float(), vals[1].to_float(), vals[2].to_float())
		return Color.WHITE

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

			# --- Skin color (accept both) ---
			"fshape_color", "body_color":
				data["fshape_color"] = read_color.call(key_value.slice(1))

			"hair":
				var i := key_value[1].to_int()
				if i >= 0 and i < hair_map.size():
					data["hair_style"] = String(hair_map[i])

			"hair_color":
				data["hair_color"] = read_color.call(key_value.slice(1))

			"eyes":
				var i := key_value[1].to_int()
				if i >= 0 and i < eyes_map.size():
					data["eyes_style"] = String(eyes_map[i])

			"mouth":
				var i := key_value[1].to_int()
				if i >= 0 and i < mouth_map.size():
					data["mouth_style"] = String(mouth_map[i])

			"clothes":
				var i := key_value[1].to_int()
				if i >= 0 and i < clothing_map.size():
					data["clothing_style"] = String(clothing_map[i])

			"clothes_color":
				data["clothing_color"] = read_color.call(key_value.slice(1))

			"bg_color":
				data["bg_color"] = read_color.call(key_value.slice(1))

			"backdrop":
				var i := key_value[1].to_int()
				if i >= 0 and i < backdrop_map.size():
					data["bg_style"] = String(backdrop_map[i])
			_:
				pass
	return data

func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		print("Is Dark: ", is_dark)
		background.color = ChessUI.DARK_BACKGROUND if is_dark else ChessUI.LIGHT_BACKGROUND
		
func on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return

	rules_button.pivot_offset = rules_button.size / 2.0
	var tween := create_tween()
	tween.tween_property(rules_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(rules_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var popup := RULES_POPUP_SCENE.instantiate() as RulesPopup
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99

	popup.tree_exited.connect(func():
		if is_instance_valid(dim):
			dim.queue_free()
	)

	popup.open("How to Play Chess", _get_rules_text())

func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Chess[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
• Checkmate your opponent’s king (put it under attack with no legal escape).
• If checkmate can’t be forced and no one can win, the game may end in a draw.
[/font_size]

[font_size={24px}][b]Setup[/b][/font_size]
[font_size={18px}]
• Each player starts with 16 pieces: 1 King, 1 Queen, 2 Rooks, 2 Bishops, 2 Knights, 8 Pawns.
• The board is 8×8. Place pieces on the back rank: Rook, Knight, Bishop, Queen, King, Bishop, Knight, Rook.
• Queens go on their own color (White queen on a light square; Black queen on a dark square).
[/font_size]

[font_size={24px}][b]How the Pieces Move[/b][/font_size]
[font_size={18px}]
• [b]King[/b]: 1 square in any direction. Cannot move into check.
• [b]Queen[/b]: any number of squares in any direction.
• [b]Rook[/b]: any number of squares horizontally or vertically.
• [b]Bishop[/b]: any number of squares diagonally.
• [b]Knight[/b]: an “L” shape (2 squares in one direction, then 1 perpendicular). Can jump over pieces.
• [b]Pawn[/b]: moves 1 square forward (2 from its starting rank if unobstructed). Captures 1 square diagonally forward.
[/font_size]

[font_size={24px}][b]Capturing & Turns[/b][/font_size]
[font_size={18px}]
• Players alternate turns. On your turn, move exactly one piece.
• If you move onto a square occupied by an opponent’s piece, you capture it and remove it from the board.
• You may not make a move that leaves your king in check.
[/font_size]

[font_size={24px}][b]Special Rules[/b][/font_size]
[font_size={18px}]
• [b]Check[/b]: your king is under attack. You must respond by moving the king, capturing the attacker, or blocking the attack (if possible).
• [b]Castling[/b]: a king-and-rook move that can happen once per game, if:
  – Neither the king nor the rook has moved,
  – Squares between them are empty,
  – The king is not in check and does not pass through or land on an attacked square.
• [b]En passant[/b]: if an opponent pawn moves two squares forward and lands beside your pawn, you may capture it as if it moved one square (only immediately on your next move).
• [b]Promotion[/b]: when a pawn reaches the last rank, it becomes a Queen, Rook, Bishop, or Knight (usually a Queen).
[/font_size]

[font_size={24px}][b]End of Game[/b][/font_size]
[font_size={18px}]
• [b]Checkmate[/b]: the king is in check and has no legal moves. Checkmating player wins.
• [b]Stalemate[/b]: the player to move has no legal moves, but is not in check. The game is a draw.
• Draws can also occur by repetition, the 50-move rule, or insufficient material.
[/font_size]
"""

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		print("Warning: sent_label is not valid for play_sent_animation.")
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
			start_waiting_animation()
	)
	
func _ensure_avatar_wrapper(avatar: Control) -> Control:
	var parent: Node = avatar.get_parent()
	if parent == null:
		return null

	if parent is Control and not (parent is Container):
		return parent as Control

	var wrapper: Control = Control.new()
	wrapper.name = "%s_Wrap" % avatar.name
	wrapper.size_flags_horizontal = avatar.size_flags_horizontal
	wrapper.size_flags_vertical = avatar.size_flags_vertical
	wrapper.custom_minimum_size = avatar.get_combined_minimum_size()

	var idx: int = avatar.get_index()
	parent.add_child(wrapper)
	parent.move_child(wrapper, idx)

	avatar.reparent(wrapper)
	avatar.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar.offset_left = 0.0
	avatar.offset_top = 0.0
	avatar.offset_right = 0.0
	avatar.offset_bottom = 0.0

	avatar.item_rect_changed.connect(func():
		if is_instance_valid(wrapper):
			wrapper.custom_minimum_size = avatar.get_combined_minimum_size()
	)

	return wrapper
	
func _show_win_burst(avatar: Control) -> void:
	var wrapper: Control = _ensure_avatar_wrapper(avatar)
	if not is_instance_valid(wrapper):
		return

	var existing: Node = wrapper.get_node_or_null("AvatarWinAnim")
	if existing != null:
		return

	var anim_instance: Control = AvatarWinAnimScene.instantiate() as Control
	anim_instance.name = "AvatarWinAnim"
	wrapper.add_child(anim_instance)

	var avatar_idx: int = avatar.get_index()
	wrapper.move_child(anim_instance, avatar_idx)

	anim_instance.z_as_relative = false
	avatar.z_as_relative = false
	anim_instance.z_index = 0
	avatar.z_index = max(avatar.z_index, 1)

	anim_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	anim_instance.offset_left = -52.0
	anim_instance.offset_right = 52.0
	anim_instance.offset_top = -43.0
	anim_instance.offset_bottom = 43.0

	(anim_instance as Node).call("set_color", Color(1.0, 0.84, 0.0))
	(anim_instance as Node).call("play", 0.05)

func start_waiting_animation():
	if not is_instance_valid(waiting_label) or not is_instance_valid(waiting_blur) or not is_instance_valid(dot_timer):
		print("Warning: Waiting animation nodes are not valid.")
		return
	if spectator_mode:
		return

	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true
	waiting_blur.visible = true

	waiting_label.modulate.a = 0.0
	waiting_blur.modulate.a = 0.0

	var tween_wait_in = create_tween().set_parallel(true)
	tween_wait_in.tween_property(waiting_label, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_property(waiting_blur, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_callback(func():
		dot_timer.start()
	)

func stop_waiting_animation():
	if is_instance_valid(dot_timer):
		dot_timer.stop()
	if is_instance_valid(waiting_label):
		waiting_label.visible = false
		waiting_label.modulate.a = 1.0
	if is_instance_valid(waiting_blur):
		waiting_blur.visible = false
		waiting_blur.modulate.a = 1.0

func _on_dot_timer_timeout():
	if not is_instance_valid(waiting_label):
		print("Warning: waiting_label is not valid in _on_dot_timer_timeout.")
		return
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots

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

	#var volume_setting_hbox := HBoxContainer.new()
	#volume_setting_hbox.add_child(Label.new())
	#(volume_setting_hbox.get_child(0) as Label).text = "Game Volume:"
	#(volume_setting_hbox.get_child(0) as Label).set_h_size_flags(Control.SIZE_EXPAND_FILL)
#
	#var volume_slider := HSlider.new()
	#volume_slider.min_value = 0.0
	#volume_slider.max_value = 1.0
	#volume_slider.step = 0.05
	#var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	#volume_slider.value = saved_volume
	#volume_slider.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	#volume_slider.value_changed.connect(func(value):
		#AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))
		#SettingsManager.set_setting(game_settings_category, "master_volume", value)
	#)
	#volume_setting_hbox.add_child(volume_slider)
	#settings_popup_script.add_custom_setting(volume_setting_hbox)
#
	#var toggle_debug_checkbox := CheckBox.new()
	#toggle_debug_checkbox.text = "Show Debug Info"
	#var saved_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	#toggle_debug_checkbox.button_pressed = saved_debug_info
	#toggle_debug_checkbox.pressed.connect(func():
		#SettingsManager.set_setting(game_settings_category, "show_debug_info", toggle_debug_checkbox.button_pressed)
	#)
	#settings_popup_script.add_custom_setting(toggle_debug_checkbox)

	var custom_settings_title := popup_instance.find_child("CustomSettingsTitleLabel", true)
	if custom_settings_title and custom_settings_title is Label and settings_popup_script.custom_settings_container.get_child_count() > 0:
		(custom_settings_title as Label).visible = true
	elif custom_settings_title and custom_settings_title is Label:
		(custom_settings_title as Label).visible = false

	settings_popup_script.closed.connect(func():
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
	)
	settings_popup_script.settings_theme_selected.connect(_on_theme_changed)
	settings_popup_script.dark_mode_changed.connect(_apply_bg_for_dark)

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

func _on_theme_changed(new_theme_name: String) -> void:
	pass

func _load_game_specific_settings() -> void:
	var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	print("Loaded game-specific settings for ", game_settings_category, ": volume=", saved_volume, " debug=", show_debug_info)
