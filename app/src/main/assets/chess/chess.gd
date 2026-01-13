extends Control
class_name ChessTop

# Preload piece textures (PNG files, 100x100 pixels)
var wP_texture: Resource = preload("res://chess/pieces/chess_wP.png")
var wR_texture: Resource = preload("res://chess/pieces/chess_wR.png")
var wN_texture: Resource = preload("res://chess/pieces/chess_wN.png")
var wB_texture: Resource = preload("res://chess/pieces/chess_wB.png")
var wQ_texture: Resource = preload("res://chess/pieces/chess_wQ.png")
var wK_texture: Resource = preload("res://chess/pieces/chess_wK.png")
var bP_texture: Resource = preload("res://chess/pieces/chess_bP.png")
var bR_texture: Resource = preload("res://chess/pieces/chess_bR.png")
var bN_texture: Resource = preload("res://chess/pieces/chess_bN.png")
var bB_texture: Resource = preload("res://chess/pieces/chess_bB.png")
var bQ_texture: Resource = preload("res://chess/pieces/chess_bQ.png")
var bK_texture: Resource = preload("res://chess/pieces/chess_bK.png")

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

# Chess state
var board: Array = []                # 8x8 array of strings, e.g., "wP", "bK", or "" for empty
var turn: String = "w"               # 'w' or 'b'
var castling: String = "KQkq"
var en_passant: String = "-"         # e.g., "e3" or "-"
var halfmove: int = 0
var fullmove: int = 1
var prev_board_gp: String = ""       # Previous board state in GamePigeon format (for replay string)

# UI
var squares: Array = []              # 8x8 ColorRect grid
var pieces: Array = []               # 8x8 TextureRect grid
var move_overlays: Array = []        # 8x8 ColorRect overlays for highlights (above pieces)
var king_overlays: Array = []        # 8x8 ColorRect overlays to highlight king-in-check
var highlighted: Array[Vector2i] = []          # list of positions being highlighted
var selected: Vector2i = Vector2i(-1, -1)           # selected square or Vector2i(-1, -1) when none
var legal_moves: Array[Vector2i] = []          # array of Vector2i targets for selected
var opponent_last_move_from: Vector2i = Vector2i(-1, -1)  # opponent's last move origin square (for green highlight)
var opponent_last_move_to: Vector2i = Vector2i(-1, -1)    # opponent's last move destination square (for green highlight)
var game_settings_category: String = ""
var spectator_mode: bool = false

# Pulsing tween map for highlight overlays
var pulse_tweens: Dictionary = {}  # Map[ColorRect, Tween]

# Pending move (pre-send commit)
var pending_snapshot: Dictionary[String, Variant] = {}
var pending_origin_square: Vector2i = Vector2i(-1, -1)
var pending_destination_square: Vector2i = Vector2i(-1, -1)
var suppress_send: bool = false

# UI controls
var send_button: Button = null
var undo_arrow_label: Label = null
var game_over_panel: Panel = null
var game_over_text: Label = null
var player_chess_black: Sprite2D = null
var player_chess_white: Sprite2D = null

# Promotion dialog
var promotion_dialog: Panel = null
var promotion_queen_button: TextureRect = null
var promotion_knight_button: TextureRect = null
var promotion_choice: String = ""  # "Q" or "N", set when user chooses
var awaiting_promotion: bool = false
var promotion_pending_from: Vector2i = Vector2i(-1, -1)
var promotion_pending_to: Vector2i = Vector2i(-1, -1)
var promotion_side: String = ""  # "w" or "b", the side promoting
var last_move_promotion_piece: String = ""  # Store promotion piece for UCI notation ("Q", "N", etc.)

# Winner side for nicer game-over messaging
var game_over_winner_side: String = ""  # "w", "b", or ""

# Coordinate axis labels
var file_labels: Array[Label] = []   # Labels for a–h along the bottom
var rank_labels: Array[Label] = []   # Labels for 1–8 along the left

# UI labels
var check_label: Label = null
var game_over_label: Label = null

# Repetition
var position_counts: Dictionary = {}

var game_over: bool = false
var game_over_reason: String = ""  # "checkmate", "stalemate", "draw", etc.

# Piece textures dictionary (maps piece codes to preloaded PNG textures)
var PIECE_TEXTURES: Dictionary = {}

# Animation constants and state
const MOVE_ANIMATION_DURATION: float = 0.4  # seconds
const MOVE_HOP_HEIGHT: float = 20.0         # pixels above board for hop arc (currently unused - flat slide animation)
var is_animating: bool = false              # Blocks input during animation
var is_processing_game_data: bool = false   # Prevents concurrent _set_game_data() calls

# ---------- Debug helpers ----------
func _log(msg: String) -> void:
	print(">> CHESSDBG: " + msg)

func _debug_state(tag: String = "") -> void:
	_log("[%s] turn=%s my_color=%s local_mode=%s isTurn=%s waitingForOpponent=%s fullmove=%d halfmove=%d castling=%s en_passant=%s game_over=%s reason=%s"
		% [tag, turn, my_color, str(local_mode), str(isTurn), str(waitingForOpponent), fullmove, halfmove, castling, en_passant, str(game_over), game_over_reason])

# ---------- Ready / plugin ----------
func _ready() -> void:
	_log("_ready() start")
	var is_dark = bool(SettingsManager.get_setting("global", "dark_mode", false))
	print("Dark Mode: ", is_dark)
	_apply_bg_for_dark(is_dark)
	if is_instance_valid(rules_button):
		rules_button.pressed.connect(on_rules_button_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	# Initialize piece textures dictionary with preloaded PNG textures
	PIECE_TEXTURES = {
		"wP": wP_texture, "wR": wR_texture, "wN": wN_texture, "wB": wB_texture, "wQ": wQ_texture, "wK": wK_texture,
		"bP": bP_texture, "bR": bR_texture, "bN": bN_texture, "bB": bB_texture, "bQ": bQ_texture, "bK": bK_texture
	}
	
	appPlugin = Engine.get_singleton("AppPlugin")
	local_mode = (appPlugin == null)
	if not local_mode:
		_log("AppPlugin found")
		if not appPlugin.is_connected("set_game_data", _set_game_data):
			appPlugin.connect("set_game_data", _set_game_data)
		my_player_id = appPlugin.getSenderUUID()
		# Initialize board with starting position to ensure pieces show immediately
		# This prevents empty board when creating a new game
		gp_array_to_board("12,13,14,15,16,14,13,12,11,11,11,11,11,11,11,11,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,21,21,21,21,21,21,21,21,22,23,24,25,26,24,23,22")
		turn = "w"
		castling = "KQkq"
		en_passant = "-"
		halfmove = 0
		fullmove = 1
		_update_turn_flags()
		appPlugin.onReady()
	else:
		_log("No AppPlugin (local debug). Setting local defaults.")
		my_player_index = 2  # Player 2 is white
		my_color = "w"
		flip_board_ui = false
		# Initialize board with starting position in GamePigeon format
		gp_array_to_board("12,13,14,15,16,14,13,12,11,11,11,11,11,11,11,11,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,21,21,21,21,21,21,21,21,22,23,24,25,26,24,23,22")
		turn = "w"
		castling = "KQkq"
		en_passant = "-"
		halfmove = 0
		fullmove = 1
		_update_turn_flags()
	_debug_state("_ready after init")
	_compute_sizes()
	_build_board_ui()
	_refresh_board_ui()
	_update_waiting_label()
	_log("_ready() done")

func _set_game_data(raw: String) -> void:
	_log("_set_game_data invoked; raw length=%d" % raw.length())

	# Prevent concurrent executions to avoid race conditions with animations and UI rebuilds
	if is_processing_game_data:
		_log("_set_game_data: already processing, ignoring concurrent call")
		return
	is_processing_game_data = true

	var orientation_changed: bool = false  # Track if board orientation changes
	var ui_already_rebuilt: bool = false  # Track if we rebuilt UI early (before animation)
	var data: Variant = JSON.parse_string(raw)
	var opponent_avatar_key = ""
	print("Raw Data: ", data)
	_log("_set_game_data parse result type=%s" % typeof(data))
	if typeof(data) == TYPE_DICTIONARY:
		_log("_set_game_data: dictionary keys = %s" % str(data.keys()))
		
		# Determine player assignment using simpler logic (like checkers)
		# The "player" field indicates whose turn it currently is in the message (1 or 2)
		# If it's NOT your turn, then you are the player indicated by "player" field
		# If it IS your turn, then you are the opposite player
		var isYourTurn: bool = bool(data.get("isYourTurn", false))
		var message_player: int = int(data.get("player", 2))
		_log("_set_game_data: isYourTurn=%s, message_player=%d" % [str(isYourTurn), message_player])
		
		# If it's not your turn, the message player field indicates who you are
		# If it is your turn, you're the opposite player
		if not isYourTurn:
			my_player_index = 3 - message_player  # Flip: 1->2, 2->1
			_log("_set_game_data: NOT my turn, so I am player %d (opposite of message player %d)" % [my_player_index, message_player])
		else:
			my_player_index = message_player
			_log("_set_game_data: IS my turn, so I am player %d (same as message player %d)" % [my_player_index, message_player])
		
		enemy_player_index = 3 - my_player_index  # Flip: 1->2, 2->1

		# Player 1 = black, Player 2 = white
		my_color = "b" if my_player_index == 1 else "w"
		if my_player_index == 1:
			opponent_avatar_key = "avatar1"
			player_marker.modulate = Color(0, 0, 0, 1)
			opp_marker.modulate = Color(1, 1, 1, 1)
		else:
			opponent_avatar_key = "avatar2"
			player_marker.modulate = Color(1, 1, 1, 1)
			opp_marker.modulate = Color(0, 0, 0, 1)
			
		if opponent_avatar_key != "" and data.has(opponent_avatar_key):
			print("Parsing Opponent Avatar")
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
		
		_log("_set_game_data: PLAYER ASSIGNMENT -> my_player_index=%d enemy_player_index=%d my_color=%s flip_board_ui=%s" % [my_player_index, enemy_player_index, my_color, str(flip_board_ui)])
		_log("_set_game_data: BOARD ORIENTATION -> %s pieces at bottom, %s pieces at top (changed: %s)" % ["Black" if flip_board_ui else "White", "White" if flip_board_ui else "Black", str(orientation_changed)])

		# If orientation changed, rebuild UI NOW (before animation) to prevent jarring flip
		if orientation_changed and _ui_ready():
			_log("_set_game_data: Rebuilding UI with new orientation BEFORE animation...")
			_compute_sizes()
			_build_board_ui()
			_refresh_board_ui()
			ui_already_rebuilt = true

		my_player_id = str(data.get("myPlayerId", my_player_id))
		_log("_set_game_data my_player_id=%s" % my_player_id)

		# Parse the game state - GamePigeon format only
		var replay = str(data.get("replay", ""))
		_log("_set_game_data replay='%s'" % replay)
		if replay.begins_with("board:") or replay.find("|board:") != -1:
			# GamePigeon format
			_log("_set_game_data: detected GamePigeon format")
			await parse_gp_replay(replay)
		else:
			# If not provided, ensure at least initial state (GamePigeon format)
			if board.is_empty():
				_log("_set_game_data: no replay data provided, fallback to initial GamePigeon position")
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
			turn = "b" if my_color == "w" else "w"
		_log("_set_game_data: set isTurn=%s, waitingForOpponent=%s, turn=%s from message data" % [str(isTurn), str(waitingForOpponent), turn])
	
	_debug_state("_set_game_data end")

	# If orientation changed AND UI already built, rebuild it with new orientation
	# (Skip if we already rebuilt earlier before animation to prevent jarring flip)
	# Otherwise, if UI already built, just refresh it. Otherwise, build for first time.
	if orientation_changed and _ui_ready() and not ui_already_rebuilt:
		_log("_set_game_data: Board orientation changed! Rebuilding UI with new orientation...")
		_compute_sizes()
		_build_board_ui()
		_refresh_board_ui()
	elif _ui_ready():
		_log("_set_game_data: UI already built, just refreshing board")
		_refresh_board_ui()
	else:
		_log("_set_game_data: UI not built yet, building UI for first time")
		_compute_sizes()
		_build_board_ui()
		_refresh_board_ui()

	# Update the waiting label to show/hide based on current state
	_update_waiting_label()
	_log("_set_game_data finished")

	# Release the guard flag to allow next call
	is_processing_game_data = false

func _update_turn_flags() -> void:
	# canonicalize interaction flags based on board 'turn' and local 'my_color'
	if game_over:
		isTurn = false
		waitingForOpponent = true
		_log("_update_turn_flags: game over -> interaction disabled")
		return
	if local_mode:
		# In local debug mode: always allow interaction for both sides.
		isTurn = true
		waitingForOpponent = false
		_log("_update_turn_flags (local_mode): set isTurn=true waiting=false")
	else:
		isTurn = (turn == my_color)
		waitingForOpponent = not isTurn
		_log("_update_turn_flags (remote): set isTurn=%s waiting=%s" % [str(isTurn), str(waitingForOpponent)])
	_debug_state("_update_turn_flags")

func _update_waiting_label() -> void:
	# Show or hide the waiting label based on waitingForOpponent flag
	if waiting_label == null:
		waiting_label = get_node_or_null("waitingLabel")
	
	if waiting_label != null:
		if waitingForOpponent and not game_over:
			waiting_label.visible = true
			_log("_update_waiting_label: showing waiting label (waitingForOpponent=true)")
		else:
			waiting_label.visible = false
			_log("_update_waiting_label: hiding waiting label (waitingForOpponent=%s game_over=%s)" % [str(waitingForOpponent), str(game_over)])
	else:
		_log("_update_waiting_label: waiting_label node not found")

# ---------- UI / sizes ----------
func _compute_sizes() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var margin: float = 20.0
	var avail: float = minf(vp.x, vp.y) - margin * 2.0
	# Initial estimate using a conservative border ratio so labels fit inside the border
	var pad: float = 8.0
	var t_ratio: float = 0.28  # matches file label height ratio; rank uses 0.24
	var S: float = floorf((avail - pad * 2.0) / (8.0 + 2.0 * t_ratio))
	if S < 10.0:
		S = 10.0
	# Derive label-driven border thickness from this S and re-adjust if needed
	var file_label_h: float = maxf(12.0, S * 0.28)
	var rank_label_w: float = maxf(12.0, S * 0.24)
	BORDER_THICK = maxf(file_label_h, rank_label_w) + 6.0
	var total_w: float = 8.0 * S + 2.0 * BORDER_THICK
	if total_w > avail:
		S = floorf((avail - 2.0 * BORDER_THICK) / 8.0)
		if S < 8.0:
			S = 8.0
		# Recalculate thickness with the new S (one more pass)
		file_label_h = maxf(12.0, S * 0.28)
		rank_label_w = maxf(12.0, S * 0.24)
		BORDER_THICK = maxf(file_label_h, rank_label_w) + 6.0
		total_w = 8.0 * S + 2.0 * BORDER_THICK
		if total_w > avail:
			# As a last resort, shave the border down to fit
			var overflow: float = total_w - avail
			BORDER_THICK = maxf(6.0, BORDER_THICK - overflow * 0.5)
			total_w = 8.0 * S + 2.0 * BORDER_THICK
	SQUARE_SIZE = S
	BLACK_THICK = maxf(2.0, S * 0.03)
	var total_h: float = total_w  # keep square area
	var top_left: Vector2 = Vector2((vp.x - total_w) / 2.0, (vp.y - total_h) / 2.0)
	BOARD_ORIGIN = top_left + Vector2(BORDER_THICK, BORDER_THICK)
	_log("_compute_sizes SQUARE_SIZE=%d BORDER_THICK=%d BOARD_ORIGIN=%s total=%s" % [SQUARE_SIZE, BORDER_THICK, str(BOARD_ORIGIN), str(Vector2(total_w, total_h))])

func _create_square_elements(r: int, f: int, rect: ColorRect, pieces_row: Array[TextureRect], move_overlays_row: Array[ColorRect], king_overlays_row: Array[ColorRect]) -> void:
	# Create piece texture
	var tex: TextureRect = TextureRect.new()
	var board_piece_size: Vector2 = Vector2(SQUARE_SIZE * 0.9, SQUARE_SIZE * 0.9)
	var piece_pos: Vector2 = rect.position + (rect.size - board_piece_size) * 0.5 + Vector2(SQUARE_SIZE * 0.1, SQUARE_SIZE * 0.1)
	tex.position = piece_pos
	tex.size = board_piece_size
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.z_index = 10  # Pieces layer (above squares, below overlays)
	add_child(tex)
	pieces_row.append(tex)

	# Highlight overlay above piece (green/capture/selected)
	var ov: ColorRect = ColorRect.new()
	var m: float = SQUARE_SIZE * 0.06
	ov.position = rect.position + Vector2(m, m)
	ov.size = rect.size - Vector2(m * 2.0, m * 2.0)
	ov.color = Color(0.2, 0.8, 0.2, 0.35)
	ov.visible = false
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.z_index = 20  # Overlays layer (above pieces)
	add_child(ov)
	move_overlays_row.append(ov)

	# King highlight overlay (red) - separate so it can show when in check
	var k_ov: ColorRect = ColorRect.new()
	k_ov.position = rect.position + Vector2(m, m)
	k_ov.size = rect.size - Vector2(m * 2.0, m * 2.0)
	k_ov.color = Color(0.9, 0.1, 0.1, 0.55)
	k_ov.visible = false
	k_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	k_ov.z_index = 20  # Overlays layer (above pieces)
	add_child(k_ov)
	king_overlays_row.append(k_ov)

func _build_board_ui() -> void:
	_log("_build_board_ui start")

	# Stop all pulse animations before freeing UI elements to prevent tween warnings
	var tween_count: int = pulse_tweens.size()
	for ov in pulse_tweens.keys():
		var tw: Tween = pulse_tweens[ov]
		if is_instance_valid(tw):
			tw.kill()
	pulse_tweens.clear()
	_log("_build_board_ui: stopped and cleared %d pulse tweens" % tween_count)

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

	# Build board border
	var board_w: float = SQUARE_SIZE * 8.0
	var board_h: float = SQUARE_SIZE * 8.0
	board_border = ColorRect.new()
	var dark_border = Color(181.0/255.0, 136.0/255.0, 99.0/255.0)
	board_border.color = dark_border
	board_border.position = BOARD_ORIGIN - Vector2(BORDER_THICK, BORDER_THICK)
	board_border.size = Vector2(board_w + 2.0 * BORDER_THICK, board_h + 2.0 * BORDER_THICK)
	board_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_border.z_index = -2  # Bottom layer (below everything)
	add_child(board_border)

	# Inner black border between brown border and board
	black_border = ColorRect.new()
	black_border.color = Color(0,0,0)
	black_border.position = BOARD_ORIGIN - Vector2(BLACK_THICK, BLACK_THICK)
	black_border.size = Vector2(board_w + 2.0 * BLACK_THICK, board_h + 2.0 * BLACK_THICK)
	black_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black_border.z_index = -1  # Second layer (above brown border, below squares)
	add_child(black_border)
	
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
			var light: Color = Color(240.0/255.0, 217.0/255.0, 181.0/255.0)
			var dark: Color = Color(181.0/255.0, 136.0/255.0, 99.0/255.0)
			rect.color = dark if ((f + r) % 2 == 0) else light
			rect.z_index = 0  # Board squares layer (above borders, below pieces)
			add_child(rect)
			squares_row.append(rect)

			# Create piece elements for this square
			_create_square_elements(r, f, rect, pieces_row, move_overlays_row, king_overlays_row)

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
		# Flip file labels when board is flipped (Black player views board from top, sees h-a left to right)
		var file_index: int = (7 - f_idx) if flip_board_ui else f_idx
		fl.text = FILE_RANKS[file_index]
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fl.size = Vector2(SQUARE_SIZE, file_label_h)
		fl.position = Vector2(BOARD_ORIGIN.x + f_idx * SQUARE_SIZE, file_y)
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fl.add_theme_font_size_override("font_size", files_font_size)
		add_child(fl)
		file_labels.append(fl)
	_log("_build_board_ui: file labels created with flip_board_ui=%s (order: %s)" % [str(flip_board_ui), "h-a" if flip_board_ui else "a-h"])
	
	# Rank numbers (1–8) along the left, centered within left border area
	# When flip_board_ui is false (White player): 8 at top, 1 at bottom (standard chess orientation)
	# When flip_board_ui is true (Black player): 1 at top, 8 at bottom (flipped orientation)
	var ranks_font_size: int = int(maxf(12.0, SQUARE_SIZE * 0.22))
	var rank_label_w: float = maxf(12.0, SQUARE_SIZE * 0.24)
	var left_border_left: float = BOARD_ORIGIN.x - BORDER_THICK
	for i in range(8):
		var rl: Label = Label.new()
		# Adjust rank numbering based on board orientation (White: 8→1 top to bottom, Black: 1→8 top to bottom)
		var rank_number: int = (i + 1) if flip_board_ui else (8 - i)
		rl.text = str(rank_number)
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rh: float = SQUARE_SIZE * 0.6
		rl.size = Vector2(rank_label_w, rh)
		var y_center: float = BOARD_ORIGIN.y + i * SQUARE_SIZE + SQUARE_SIZE * 0.5
		var y_pos: float = y_center - rh * 0.5
		rl.position = Vector2(left_border_left + (BORDER_THICK - rank_label_w) * 0.5, y_pos)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rl.add_theme_font_size_override("font_size", ranks_font_size)
		add_child(rl)
		rank_labels.append(rl)
	_log("_build_board_ui: rank labels created with flip_board_ui=%s (order from top: %s)" % [str(flip_board_ui), "1-8" if flip_board_ui else "8-1"])

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
	if is_instance_valid(game_over_panel):
		game_over_panel.queue_free()
		game_over_panel = null
		game_over_text = null
	if is_instance_valid(promotion_dialog):
		promotion_dialog.queue_free()
		promotion_dialog = null
		promotion_queen_button = null
		promotion_knight_button = null

	# Create centered game-over panel (hidden by default)
	var panel_w = board_w * 0.7
	var panel_h = maxf(56.0, SQUARE_SIZE * 0.6)
	game_over_panel = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.2, 0.2, 0.65)
	sb.corner_radius_top_left = 20
	sb.corner_radius_top_right = 20
	sb.corner_radius_bottom_left = 20
	sb.corner_radius_bottom_right = 20
	game_over_panel.add_theme_stylebox_override("panel", sb)
	game_over_panel.size = Vector2(panel_w, panel_h)
	var center = BOARD_ORIGIN + Vector2(board_w * 0.5, board_w * 0.5)
	game_over_panel.position = center - game_over_panel.size * 0.5
	game_over_panel.visible = false
	add_child(game_over_panel)
	game_over_text = Label.new()
	game_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_text.size = game_over_panel.size
	game_over_text.add_theme_font_size_override("font_size", int(maxf(20.0, SQUARE_SIZE * 0.28)))
	game_over_text.add_theme_color_override("font_color", Color(1,1,1))
	game_over_panel.add_child(game_over_text)

	# Create promotion dialog (hidden by default)
	var promo_w: float = SQUARE_SIZE * 5.0
	var promo_h: float = SQUARE_SIZE * 2.5
	promotion_dialog = Panel.new()
	var promo_sb: StyleBoxFlat = StyleBoxFlat.new()
	promo_sb.bg_color = Color(0.15, 0.15, 0.15, 0.92)
	promo_sb.corner_radius_top_left = 15
	promo_sb.corner_radius_top_right = 15
	promo_sb.corner_radius_bottom_left = 15
	promo_sb.corner_radius_bottom_right = 15
	promotion_dialog.add_theme_stylebox_override("panel", promo_sb)
	promotion_dialog.size = Vector2(promo_w, promo_h)
	promotion_dialog.position = center - promotion_dialog.size * 0.5
	promotion_dialog.visible = false
	promotion_dialog.z_index = 2000  # Above everything else
	add_child(promotion_dialog)
	
	# Promotion title label
	var promo_title: Label = Label.new()
	promo_title.text = "Promote to:"
	promo_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	promo_title.size = Vector2(promo_w, SQUARE_SIZE * 0.5)
	promo_title.position = Vector2(0, SQUARE_SIZE * 0.2)
	promo_title.add_theme_font_size_override("font_size", int(maxf(16.0, SQUARE_SIZE * 0.25)))
	promo_title.add_theme_color_override("font_color", Color(1,1,1))
	promotion_dialog.add_child(promo_title)
	
	# Queen piece button (left)
	var piece_size: float = SQUARE_SIZE * 1.2
	var spacing: float = SQUARE_SIZE * 0.4
	var start_x: float = (promo_w - (piece_size * 2.0 + spacing)) * 0.5
	var piece_y: float = SQUARE_SIZE * 0.9
	
	promotion_queen_button = TextureRect.new()
	promotion_queen_button.size = Vector2(piece_size, piece_size)
	promotion_queen_button.position = Vector2(start_x, piece_y)
	promotion_queen_button.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	promotion_queen_button.mouse_filter = Control.MOUSE_FILTER_STOP
	promotion_dialog.add_child(promotion_queen_button)
	
	# Knight piece button (right)
	promotion_knight_button = TextureRect.new()
	promotion_knight_button.size = Vector2(piece_size, piece_size)
	promotion_knight_button.position = Vector2(start_x + piece_size + spacing, piece_y)
	promotion_knight_button.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	promotion_knight_button.mouse_filter = Control.MOUSE_FILTER_STOP
	promotion_dialog.add_child(promotion_knight_button)

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
			_log("SendButton pressed signal connected to _on_send_pressed")

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
		_log("PlayerChessBlack scaled to %f (piece_size=%f)" % [target_scale, piece_display_size])
	
	if is_instance_valid(player_chess_white):
		player_chess_white.scale = Vector2(target_scale, target_scale)
		_log("PlayerChessWhite scaled to %f (piece_size=%f)" % [target_scale, piece_display_size])

	_log("_build_board_ui done")

		# If parse_gp_replay ran earlier and requested evaluation, do it now that UI exists
	if pending_evaluate:
		_log("_build_board_ui: running deferred _evaluate_check_and_update_flags()")
		pending_evaluate = false
		_evaluate_check_and_update_flags()


func _get_piece_texture(code: String) -> Texture2D:
	# Return preloaded PNG texture from PIECE_TEXTURES dictionary
	if code == "":
		return null
	return PIECE_TEXTURES.get(code, null)

func _refresh_board_ui() -> void:
	_log("_refresh_board_ui start")
	
	# If UI hasn't been built yet, skip refresh and request an evaluate after UI is built
	if not _ui_ready():
		_log("_refresh_board_ui: UI not ready (squares/pieces not initialized). Skipping UI refresh.")
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
		sel_ov.color = Color(0.2, 0.6, 1.0, 0.38)
		sel_ov.visible = true
		_start_pulse(sel_ov)

	# Legal destination overlays (light blue for moves, red for captures)
	for pos: Vector2i in highlighted:
		var r: int = pos.y
		var f: int = pos.x
		var is_capture: bool = board[r][f] != "" and board[r][f][0] != turn
		var ov: ColorRect = move_overlays[r][f]
		ov.color = (Color(0.9, 0.1, 0.1, 0.45) if is_capture else Color(0.2, 0.6, 1.0, 0.33))
		ov.visible = true
		_start_pulse(ov)

	# Opponent's last move highlights (green with pulse)
	# Skip if the square is a legal destination (red/blue highlights take priority)
	if opponent_last_move_from != Vector2i(-1, -1) and opponent_last_move_from not in highlighted:
		var from_ov: ColorRect = move_overlays[opponent_last_move_from.y][opponent_last_move_from.x]
		from_ov.color = Color(0.2, 0.8, 0.2, 0.4)  # Green for opponent's origin square
		from_ov.visible = true
		_start_pulse(from_ov)

	if opponent_last_move_to != Vector2i(-1, -1) and opponent_last_move_to not in highlighted:
		var to_ov: ColorRect = move_overlays[opponent_last_move_to.y][opponent_last_move_to.x]
		to_ov.color = Color(0.2, 0.8, 0.2, 0.4)  # Green for opponent's destination square
		to_ov.visible = true
		_start_pulse(to_ov)

	# If the side-to-move is in check, highlight the king square and dim pieces without legal moves
	var side_to_move: String = turn
	var incheck: bool = _in_check(side_to_move)
	if incheck:
		var kp: Vector2i = _king_pos(side_to_move)
		if kp.x != -1:
			king_overlays[kp.y][kp.x].visible = true
		# dim same-side pieces without legal moves
		for r: int in range(8):
			for f: int in range(8):
				if board[r][f] != "" and board[r][f][0] == side_to_move:
					var lm: Array[Vector2i] = _legal_moves_for_square(Vector2i(f, r))
					if lm.size() == 0:
						# dim square to indicate this piece cannot help
						squares[r][f].modulate = Color(0.6, 0.6, 0.6)
					else:
						# keep normal
						squares[r][f].modulate = Color(1,1,1)

	# Update check / game_over labels
	if incheck:
		check_label.text = "CHECK — %s to move" % ("White" if side_to_move == "w" else "Black")
		check_label.visible = true
	else:
		check_label.visible = false

	if game_over:
		var msg: String = ""
		if game_over_winner_side == "":
			msg = "DRAW!"
		else:
			msg = ("YOU WIN!" if my_color == game_over_winner_side else "YOU LOSE!")
		if is_instance_valid(game_over_panel) and is_instance_valid(game_over_text):
			game_over_text.text = msg
			game_over_panel.visible = true
	else:
		if is_instance_valid(game_over_panel):
			game_over_panel.visible = false
	# Always hide the old top game over label in favor of the centered panel
	game_over_label.visible = false
	
	# Ensure pending-state UI is visible and correct
	if _has_pending():
		var from_sq: Vector2i = pending_origin_square
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
			ov_back.color = Color(0.2, 0.6, 1.0, 0.33)
			ov_back.visible = true
			_start_pulse(ov_back)
		if is_instance_valid(send_button):
			send_button.disabled = false
			send_button.visible = true
	else:
		if is_instance_valid(send_button):
			send_button.disabled = true
			send_button.visible = false
	
	_log("_refresh_board_ui done")
	_debug_state("_refresh_board_ui")

func _draw_highlights() -> void:
	# Deprecated: highlights handled inside _refresh_board_ui for overlap order
	pass

# ---------- Highlight pulse helpers ----------
func _start_pulse(ov: ColorRect) -> void:
	if ov == null:
		return
	_stop_pulse(ov)
	var tw: Tween = get_tree().create_tween()
	tw.set_loops()
	tw.tween_property(ov, "modulate:a", 0.25, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ov, "modulate:a", 0.6, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse_tweens[ov] = tw

func _stop_pulse(ov: ColorRect) -> void:
	if pulse_tweens.has(ov):
		var tw: Tween = pulse_tweens[ov]
		if is_instance_valid(tw):
			tw.kill()
		pulse_tweens.erase(ov)
	# reset modulate alpha
	if is_instance_valid(ov):
		ov.modulate = Color(1,1,1,1)

# ---------- Pending move helpers ----------
func _has_pending() -> bool:
	return pending_origin_square != Vector2i(-1, -1) and pending_destination_square != Vector2i(-1, -1)

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
	if not is_instance_valid(promotion_dialog):
		_log("_show_promotion_dialog: promotion_dialog not initialized")
		return
	_log("_show_promotion_dialog for side=%s" % side)
	promotion_side = side
	# Set textures for Queen and Knight based on side
	var queen_code: String = side + "Q"
	var knight_code: String = side + "N"
	if is_instance_valid(promotion_queen_button):
		promotion_queen_button.texture = _get_piece_texture(queen_code)
	if is_instance_valid(promotion_knight_button):
		promotion_knight_button.texture = _get_piece_texture(knight_code)
	# Ensure dialog is visible and brought to front
	promotion_dialog.visible = true
	promotion_dialog.z_index = 3000  # Ensure it's above everything, including check labels
	move_child(promotion_dialog, get_child_count() - 1)  # Move to front of render order
	awaiting_promotion = true
	_log("_show_promotion_dialog: dialog shown and brought to front, awaiting_promotion=true")

func _hide_promotion_dialog() -> void:
	if is_instance_valid(promotion_dialog):
		promotion_dialog.visible = false
	awaiting_promotion = false
	promotion_choice = ""
	promotion_side = ""
	_log("_hide_promotion_dialog: dialog hidden")

func _on_promotion_choice(piece: String) -> void:
	_log("_on_promotion_choice: chose %s" % piece)
	promotion_choice = piece
	_hide_promotion_dialog()
	
	# Now execute the pending promotion move
	if promotion_pending_from != Vector2i(-1, -1) and promotion_pending_to != Vector2i(-1, -1):
		_log("_on_promotion_choice: executing promotion move %s -> %s with piece %s" % [_square_name(promotion_pending_from), _square_name(promotion_pending_to), piece])
		pending_snapshot = _snapshot()
		pending_origin_square = promotion_pending_from
		pending_destination_square = promotion_pending_to

		# Animate the promotion move
		await _animate_player_move(promotion_pending_from, promotion_pending_to)

		_execute_move(promotion_pending_from, promotion_pending_to)
		_show_undo_arrow(pending_origin_square)
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
		_log("_on_promotion_choice: ERROR - no pending promotion move stored")

func _on_send_pressed() -> void:
	_log("_on_send_pressed called: has_pending=%s local_mode=%s" % [str(_has_pending()), str(local_mode)])
	if not _has_pending():
		_log("_on_send_pressed: early return (no pending move)")
		return
	_log("_on_send_pressed: committing pending move %s -> %s" % [_square_name(pending_origin_square), _square_name(pending_destination_square)])
	# Call _commit_move to switch turns and send to appPlugin
	_commit_move(pending_origin_square, pending_destination_square)
	# Clear pending state
	pending_snapshot = {}
	pending_origin_square = Vector2i(-1, -1)
	pending_destination_square = Vector2i(-1, -1)
	_hide_undo_arrow()
	if is_instance_valid(send_button):
		send_button.disabled = true
		send_button.visible = false
	_refresh_board_ui()

func _undo_pending() -> void:
	if not _has_pending():
		return
	_log("_undo_pending: reverting to snapshot")
	if pending_snapshot.size() > 0:
		_restore(pending_snapshot)
	pending_snapshot = {}
	pending_origin_square = Vector2i(-1, -1)
	pending_destination_square = Vector2i(-1, -1)
	_hide_undo_arrow()
	if is_instance_valid(send_button):
		send_button.disabled = true
		send_button.visible = false
	_update_turn_flags()
	_refresh_board_ui()

# ---------- Input gating ----------
func _input(event: InputEvent) -> void:
	# _debug_state("_input at start")
	# Only allow interaction when it's allowed by _can_interact
	if not _can_interact():
		# _log("_input: interaction blocked (can_interact=false)")
		# _debug_state("_input blocked")
		return
	
	if event is InputEventScreenTouch and event.pressed:
		_on_tap(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_tap(event.position)

func _can_interact() -> bool:
	if game_over:
		#_log("_can_interact -> false (game over)")
		return false
	if is_animating:
		#_log("_can_interact -> false (animation in progress)")
		return false
	if local_mode:
		# local mode: allow interacting with the board for both sides
		#_log("_can_interact -> true (local_mode)")
		return true
	var allowed: bool = (turn == my_color) and (not waitingForOpponent)
	#_log("_can_interact -> %s (turn=%s my_color=%s waiting=%s)" % [str(allowed), turn, my_color, str(waitingForOpponent)])
	return allowed

func _on_tap(pos: Vector2) -> void:
	_log("_on_tap at pos=%s" % str(pos))

	# Block all input during animation
	if is_animating:
		_log("_on_tap: blocked during animation")
		return

	# If awaiting promotion choice, check if user clicked on promotion pieces
	if awaiting_promotion and is_instance_valid(promotion_dialog) and promotion_dialog.visible:
		# Check if click is on promotion dialog pieces
		if is_instance_valid(promotion_queen_button):
			var queen_rect: Rect2 = Rect2(promotion_dialog.position + promotion_queen_button.position, promotion_queen_button.size)
			if queen_rect.has_point(pos):
				_log("_on_tap: clicked Queen in promotion dialog")
				_on_promotion_choice("Q")
				return
		if is_instance_valid(promotion_knight_button):
			var knight_rect: Rect2 = Rect2(promotion_dialog.position + promotion_knight_button.position, promotion_knight_button.size)
			if knight_rect.has_point(pos):
				_log("_on_tap: clicked Knight in promotion dialog")
				_on_promotion_choice("N")
				return
		_log("_on_tap: awaiting promotion but click not on pieces, ignoring")
		return
	
	var sq: Vector2i = _pos_to_square(pos)
	if sq == Vector2i(-1, -1):
		_log("_on_tap: clicked outside board")
		return
	# If a pending move exists, handle undo or commit
	if _has_pending():
		if sq == pending_origin_square:
			# Tap origin square to undo
			_undo_pending()
		elif local_mode and sq == pending_destination_square:
			# In local mode: tap destination square to commit the move
			_log("_on_tap: local mode - committing pending move by tapping destination")
			_commit_move(pending_origin_square, pending_destination_square)
			pending_snapshot = {}
			pending_origin_square = Vector2i(-1, -1)
			pending_destination_square = Vector2i(-1, -1)
			_hide_undo_arrow()
			_refresh_board_ui()
		else:
			_log("_on_tap: pending move active; tap origin to undo" + (" or destination to commit" if local_mode else " or press Send"))
		return
	var r: int = sq.y
	var f: int = sq.x
	var piece: String = board[r][f]
	_log("_on_tap at square %s (f=%d r=%d) piece=%s" % [_square_name(sq), f, r, str(piece)])
	
	if selected == Vector2i(-1, -1):
		# No piece selected - try to select one
		# Allow selecting a piece if it belongs to the side to move and (local_mode or it's our remote color)
		if piece != "" and piece[0] == turn and (local_mode or piece[0] == my_color):
			# Only allow selecting this piece if it has at least one legal move
			var candidate_moves: Array[Vector2i] = _legal_moves_for_square(Vector2i(f, r))
			if candidate_moves.size() == 0:
				_log("_on_tap: piece %s at %s has no legal moves and cannot be selected right now" % [piece, _square_name(Vector2i(f, r))])
			else:
				selected = Vector2i(f, r)
				legal_moves = candidate_moves
				highlighted.clear()
				for m in legal_moves:
					highlighted.append(m)
				_log("_on_tap selected piece %s at %s ; legal_moves_count=%d" % [piece, _square_name(selected), legal_moves.size()])
				for m in legal_moves:
					_log("  legal -> %s" % _square_name(m))
				_refresh_board_ui()
		else:
			_log("_on_tap: can't select piece (either empty or not permitted)")
	else:
		# A piece is already selected - try to move or reselect
		_log("_on_tap: piece already selected at %s ; attempting move or reselect" % _square_name(selected))
		var move_made = false
		for m in legal_moves:
			if m.x == f and m.y == r:
				_log("_on_tap: move matched legal move -> %s to %s" % [_square_name(selected), _square_name(m)])
				
				# Check if this is a pawn promotion move
				var moving_piece: String = board[selected.y][selected.x]
				var is_promotion: bool = false
				if moving_piece != "" and moving_piece[1] == "P":
					var dest_rank: int = r
					var moving_side: String = moving_piece[0]
					# Board layout: board[0] is black's back rank (rank 8), board[7] is white's back rank (rank 1)
					# White pawns promote when reaching board[0] (opponent's back rank)
					# Black pawns promote when reaching board[7] (opponent's back rank)
					if (moving_side == "w" and dest_rank == 0) or (moving_side == "b" and dest_rank == 7):
						is_promotion = true
						_log("_on_tap: detected promotion move for %s pawn to rank %d" % [moving_side, dest_rank])
				
				if is_promotion:
					# Show promotion dialog instead of executing move immediately
					# This must happen regardless of check/checkmate state
					promotion_pending_from = selected
					promotion_pending_to = Vector2i(f, r)
					selected = Vector2i(-1, -1)
					highlighted.clear()
					legal_moves.clear()
					# Show promotion dialog AFTER clearing selection to prevent interference
					_show_promotion_dialog(moving_piece[0])
					move_made = true
					break
				
				# Both modes: execute move (visual only), show undo arrow, enable pending state
				pending_snapshot = _snapshot()
				pending_origin_square = selected
				pending_destination_square = Vector2i(f, r)

				# Animate the move before executing it on the board
				await _animate_player_move(selected, pending_destination_square)

				_execute_move(selected, pending_destination_square)
				_show_undo_arrow(pending_origin_square)
				# Send button enabled after move (visible in all modes for testing)
				if is_instance_valid(send_button):
					send_button.disabled = false
					send_button.visible = true
				selected = Vector2i(-1, -1)
				highlighted.clear()
				legal_moves.clear()
				_refresh_board_ui()
				move_made = true
				break
		
		if not move_made:
			if piece != "" and piece[0] == turn and (local_mode or piece[0] == my_color):
				# reselect (again only if has legal moves)
				var candidate_moves: Array[Vector2i] = _legal_moves_for_square(Vector2i(f, r))
				if candidate_moves.size() == 0:
					_log("_on_tap: reselect piece %s at %s has no legal moves" % [piece, _square_name(Vector2i(f, r))])
					selected = Vector2i(-1, -1)
					highlighted.clear()
					legal_moves.clear()
					_refresh_board_ui()
				else:
					selected = Vector2i(f, r)
					legal_moves = candidate_moves
					highlighted.clear()
					for m in legal_moves:
						highlighted.append(m)
					_log("_on_tap: reselected piece %s at %s ; legal_moves_count=%d" % [piece, _square_name(selected), legal_moves.size()])
					_refresh_board_ui()
			else:
				selected = Vector2i(-1, -1)
				highlighted.clear()
				legal_moves.clear()
				_refresh_board_ui()
				_log("_on_tap: deselected")

func _pos_to_square(pos: Vector2) -> Vector2i:
	var rel: Vector2 = pos - BOARD_ORIGIN
	if rel.x < 0 or rel.y < 0:
		return Vector2i(-1, -1)
	var f: int = int(rel.x / SQUARE_SIZE)
	var rf: int = int(rel.y / SQUARE_SIZE)
	if f < 0 or f > 7 or rf < 0 or rf > 7:
		return Vector2i(-1, -1)
	var r: int = (7 - rf) if not flip_board_ui else rf
	_log("_pos_to_square: screen_pos=%s -> grid_pos(f=%d,rf=%d) -> board_pos(f=%d,r=%d) [flip=%s]" % [str(pos), f, rf, f, r, str(flip_board_ui)])
	return Vector2i(f, r)

#======================== Chess engine ========================
#======================== GamePigeon format conversion ========================
# GamePigeon uses a flat 64-element array where index = file + (rank * 8)
# Piece encoding: 0=empty, white: 11=P, 12=R, 13=N, 14=B, 15=Q, 16=K
#                          black: 21=P, 22=R, 23=N, 24=B, 25=Q, 26=K

func board_to_gp_array() -> String:
	"""Convert internal 8x8 board to GamePigeon's flat 64-element comma-separated string."""
	var gp_pieces: Array = []
	for r in range(8):
		for f in range(8):
			var piece: String = board[r][f]
			if piece == "":
				gp_pieces.append("0")
			else:
				var side: String = piece[0]
				var p: String = piece[1]
				var code: int = 0
				match p:
					"P": code = 1
					"R": code = 2
					"N": code = 3
					"B": code = 4
					"Q": code = 5
					"K": code = 6
				if side == "w":
					gp_pieces.append(str(10 + code))
				else:
					gp_pieces.append(str(20 + code))
	return ",".join(gp_pieces)

func gp_array_to_board(gp_array_str: String) -> void:
	"""Parse GamePigeon's 64-element comma-separated string into internal 8x8 board."""
	_log("gp_array_to_board: parsing '%s'" % gp_array_str)
	var pieces: PackedStringArray = gp_array_str.split(",")
	if pieces.size() != 64:
		_log("gp_array_to_board: invalid array size=%d (expected 64)" % pieces.size())
		return

	board.clear()
	for r in range(8):
		var row_arr: Array[String] = []
		for f in range(8):
			var idx: int = f + (r * 8)
			var code: int = int(pieces[idx])
			if code == 0:
				row_arr.append("")
			else:
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
				row_arr.append(side + piece_type)
		board.append(row_arr)

	_log("gp_array_to_board: board populated")
	_count_position()

func parse_gp_replay(replay: String) -> void:
	"""Parse GamePigeon replay string format: board:<prev>|move:<from_f>,<from_r>,<to_f>,<to_r>|board:<current>"""
	_log("parse_gp_replay: '%s'" % replay)
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

	if current_board == "":
		_log("parse_gp_replay: no board state found in replay")
		return

	# If we have move coordinates, animate the move
	if move_coords.size() == 4 and prev_board != "":
		var from_f: int = int(move_coords[0])
		var from_r: int = int(move_coords[1])
		var to_f: int = int(move_coords[2])
		var to_r: int = int(move_coords[3])

		# Store opponent's last move for green highlighting
		opponent_last_move_from = Vector2i(from_f, from_r)
		opponent_last_move_to = Vector2i(to_f, to_r)
		_log("parse_gp_replay: stored opponent last move %s -> %s" % [
			_square_name(opponent_last_move_from),
			_square_name(opponent_last_move_to)
		])

		_log("parse_gp_replay: animating move %s -> %s" % [
			_square_name(Vector2i(from_f, from_r)),
			_square_name(Vector2i(to_f, to_r))
		])

		# Set board to previous state for animation
		gp_array_to_board(prev_board)
		if _ui_ready():
			_refresh_board_ui()

		# Animate the opponent's move
		await _animate_opponent_move(Vector2i(from_f, from_r), Vector2i(to_f, to_r), current_board)
	else:
		_log("parse_gp_replay: no move data, just updating to current board (initial position)")

	# Set final board state
	gp_array_to_board(current_board)
	# Note: We don't parse turn, castling, etc. from GamePigeon format
	# These would need to be inferred or passed separately

	if _ui_ready():
		_evaluate_check_and_update_flags()
	else:
		pending_evaluate = true
	_debug_state("parse_gp_replay end")

func to_gp_replay(prev_board_gp: String, from_sq: Vector2i, to_sq: Vector2i) -> String:
	"""Generate GamePigeon replay string with previous board, move, and current board."""
	var current_board_gp: String = board_to_gp_array()
	var move_str: String = "move:%d,%d,%d,%d" % [from_sq.x, from_sq.y, to_sq.x, to_sq.y]
	return "board:%s|%s|board:%s" % [prev_board_gp, move_str, current_board_gp]

func to_position_key() -> String:
	"""Generate unique position key for threefold repetition detection.
	Includes board state, turn, castling rights, and en passant target."""
	var board_gp: String = board_to_gp_array()
	return "%s %s %s %s" % [board_gp, turn, castling if castling != "" else "-", en_passant]

# ---------- Animation Functions ----------

func _create_piece_tween(from_rank: int, from_file: int, to_rank: int, to_file: int) -> Tween:
	"""Create and return a Tween for animating a piece move with smooth sliding motion.
	Does NOT await the tween - caller must await tween.finished.
	Returns null if animation cannot be created."""

	if not _ui_ready():
		_log("_create_piece_tween: UI not ready, cannot create tween")
		return null

	var piece_tex: TextureRect = pieces[from_rank][from_file]
	if piece_tex == null or piece_tex.texture == null:
		_log("_create_piece_tween: no piece at source %s, cannot create tween" % _square_name(Vector2i(from_file, from_rank)))
		return null

	_log("_create_piece_tween: creating tween for %s -> %s" % [_square_name(Vector2i(from_file, from_rank)), _square_name(Vector2i(to_file, to_rank))])

	# Store start and end positions
	var start_pos: Vector2 = piece_tex.position
	var end_pos: Vector2 = pieces[to_rank][to_file].position

	# Create tween for the animation
	var tween: Tween = create_tween()
	tween.set_parallel(true)  # Run position and scale animations in parallel

	# Smooth slide animation (flat, no arc) from start to end position
	tween.tween_property(piece_tex, "position", end_pos, MOVE_ANIMATION_DURATION)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)

	# Optional: Add slight scale bounce for polish
	tween.tween_property(piece_tex, "scale", Vector2(1.1, 1.1), MOVE_ANIMATION_DURATION * 0.5)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

	# Chain the scale-back animation after scale-up
	tween.chain()
	tween.tween_property(piece_tex, "scale", Vector2.ONE, MOVE_ANIMATION_DURATION * 0.5)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_IN)

	# Add cleanup callback when tween finishes
	tween.finished.connect(func():
		piece_tex.position = end_pos
		piece_tex.scale = Vector2.ONE
		_log("_create_piece_tween: tween finished for %s" % _square_name(Vector2i(to_file, to_rank)))
	)

	return tween

func _animate_piece_move(from_rank: int, from_file: int, to_rank: int, to_file: int) -> void:
	"""Animate a piece moving from one square to another with smooth sliding motion.
	Sets is_animating flag during animation."""

	var tween: Tween = _create_piece_tween(from_rank, from_file, to_rank, to_file)
	if tween == null:
		_log("_animate_piece_move: failed to create tween, skipping animation")
		return

	is_animating = true
	_log("_animate_piece_move: animating %s -> %s" % [_square_name(Vector2i(from_file, from_rank)), _square_name(Vector2i(to_file, to_rank))])

	# Wait for animation to complete
	await tween.finished

	is_animating = false
	_log("_animate_piece_move: animation complete")

func _animate_castling(king_from_rank: int, king_from_file: int, king_to_rank: int, king_to_file: int,
					  rook_from_rank: int, rook_from_file: int, rook_to_rank: int, rook_to_file: int) -> void:
	"""Animate both king and rook moving simultaneously during castling."""

	if not _ui_ready():
		_log("_animate_castling: UI not ready, skipping animation")
		return

	_log("_animate_castling: king %s->%s, rook %s->%s" % [
		_square_name(Vector2i(king_from_file, king_from_rank)),
		_square_name(Vector2i(king_to_file, king_to_rank)),
		_square_name(Vector2i(rook_from_file, rook_from_rank)),
		_square_name(Vector2i(rook_to_file, rook_to_rank))
	])

	is_animating = true

	# Create both tweens (they start immediately and run in parallel)
	var king_tween: Tween = _create_piece_tween(king_from_rank, king_from_file, king_to_rank, king_to_file)
	var rook_tween: Tween = _create_piece_tween(rook_from_rank, rook_from_file, rook_to_rank, rook_to_file)

	# Check if both tweens were created successfully
	if king_tween == null or rook_tween == null:
		_log("_animate_castling: failed to create one or both tweens, aborting")
		is_animating = false
		return

	# Wait for both to complete (they run in parallel)
	await king_tween.finished
	await rook_tween.finished

	is_animating = false
	_log("_animate_castling: both animations complete")

func _animate_player_move(from_sq: Vector2i, to_sq: Vector2i) -> void:
	"""Detect move type and animate appropriately for player moves.
	Handles castling, en passant, captures, and normal moves."""

	if not _ui_ready():
		_log("_animate_player_move: UI not ready, skipping animation")
		return

	var moving: String = board[from_sq.y][from_sq.x]
	var target: String = board[to_sq.y][to_sq.x]
	var side: String = moving[0]
	var piece_type: String = moving[1]

	_log("_animate_player_move: %s from %s to %s" % [moving, _square_name(from_sq), _square_name(to_sq)])

	# Detect castling (king moves 2 squares)
	if piece_type == "K" and abs(to_sq.x - from_sq.x) == 2:
		_log("_animate_player_move: detected castling")
		var is_kingside: bool = (to_sq.x == 6)
		var rook_from_file: int = 7 if is_kingside else 0
		var rook_to_file: int = 5 if is_kingside else 3
		await _animate_castling(from_sq.y, from_sq.x, to_sq.y, to_sq.x,
								from_sq.y, rook_from_file, to_sq.y, rook_to_file)
		return

	# Detect en passant (pawn diagonal move to empty square)
	var is_en_passant: bool = false
	if piece_type == "P" and target == "" and from_sq.x != to_sq.x:
		is_en_passant = true
		_log("_animate_player_move: detected en passant")
		# Hide the captured pawn (one rank behind destination)
		var dir: int = 1 if side == "w" else -1
		var captured_rank: int = to_sq.y - dir
		if _ui_ready() and pieces[captured_rank][to_sq.x].texture != null:
			pieces[captured_rank][to_sq.x].texture = null
			_log("_animate_player_move: hid captured pawn at %s" % _square_name(Vector2i(to_sq.x, captured_rank)))

	# Detect capture (hide captured piece before animation)
	if target != "" and not is_en_passant:
		_log("_animate_player_move: detected capture of %s" % target)
		if _ui_ready():
			pieces[to_sq.y][to_sq.x].texture = null
			_log("_animate_player_move: hid captured piece at %s" % _square_name(to_sq))

	# Animate the moving piece
	await _animate_piece_move(from_sq.y, from_sq.x, to_sq.y, to_sq.x)

func _animate_opponent_move(from_sq: Vector2i, to_sq: Vector2i, final_board_gp: String) -> void:
	"""Animate opponent's move during replay.
	Board is currently set to previous state. final_board_gp contains the state after the move."""

	if not _ui_ready():
		_log("_animate_opponent_move: UI not ready, skipping animation")
		return

	var moving: String = board[from_sq.y][from_sq.x]
	var target: String = board[to_sq.y][to_sq.x]

	if moving == "":
		_log("_animate_opponent_move: ERROR - no piece at source square %s" % _square_name(from_sq))
		return

	var side: String = moving[0]
	var piece_type: String = moving[1]

	_log("_animate_opponent_move: %s from %s to %s" % [moving, _square_name(from_sq), _square_name(to_sq)])

	# Detect castling (king moves 2 squares)
	if piece_type == "K" and abs(to_sq.x - from_sq.x) == 2:
		_log("_animate_opponent_move: detected castling")
		var is_kingside: bool = (to_sq.x == 6)
		var rook_from_file: int = 7 if is_kingside else 0
		var rook_to_file: int = 5 if is_kingside else 3
		await _animate_castling(from_sq.y, from_sq.x, to_sq.y, to_sq.x,
								from_sq.y, rook_from_file, to_sq.y, rook_to_file)
		return

	# Detect en passant (pawn diagonal move to empty square)
	var is_en_passant: bool = false
	if piece_type == "P" and target == "" and from_sq.x != to_sq.x:
		is_en_passant = true
		_log("_animate_opponent_move: detected en passant")
		# Hide the captured pawn (one rank behind destination)
		var dir: int = 1 if side == "w" else -1
		var captured_rank: int = to_sq.y - dir
		if _ui_ready() and pieces[captured_rank][to_sq.x].texture != null:
			pieces[captured_rank][to_sq.x].texture = null
			_log("_animate_opponent_move: hid captured pawn at %s" % _square_name(Vector2i(to_sq.x, captured_rank)))

	# Detect capture (hide captured piece before animation)
	if target != "" and not is_en_passant:
		_log("_animate_opponent_move: detected capture of %s" % target)
		if _ui_ready():
			pieces[to_sq.y][to_sq.x].texture = null
			_log("_animate_opponent_move: hid captured piece at %s" % _square_name(to_sq))

	# Animate the moving piece
	await _animate_piece_move(from_sq.y, from_sq.x, to_sq.y, to_sq.x)

func _in_bounds(f: int, r: int) -> bool:
	return f >= 0 and f < 8 and r >= 0 and r < 8

func _is_attacked_by(r: int, f: int, attacker_side: String) -> bool:
	# Knights
	var k_moves = [[1,2],[2,1],[-1,2],[-2,1],[1,-2],[2,-1],[-1,-2],[-2,-1]]
	for m in k_moves:
		var nf = f + m[0]
		var nr = r + m[1]
		if _in_bounds(nf, nr) and board[nr][nf] == attacker_side + "N":
			return true
	# King
	for nr in range(r-1, r+2):
		for nf in range(f-1, f+2):
			if nf == f and nr == r:
				continue
			if _in_bounds(nf, nr) and board[nr][nf] == attacker_side + "K":
				return true
	# Sliding: bishops/queens
	var dirs_b = [[1,1], [1,-1], [-1,1], [-1,-1]]
	for d in dirs_b:
		var nf = f + d[0]
		var nr = r + d[1]
		while _in_bounds(nf, nr):
			var v = board[nr][nf]
			if v != "":
				if v[0] == attacker_side and (v[1] == "B" or v[1] == "Q"):
					return true
				break
			nf += d[0]
			nr += d[1]
	# Sliding: rooks/queens
	var dirs_r = [[1,0],[-1,0],[0,1],[0,-1]]
	for d in dirs_r:
		var nf = f + d[0]
		var nr = r + d[1]
		while _in_bounds(nf, nr):
			var v = board[nr][nf]
			if v != "":
				if v[0] == attacker_side and (v[1] == "R" or v[1] == "Q"):
					return true
				break
			nf += d[0]
			nr += d[1]
	# Pawns
	var dir: int = -1 if attacker_side == "w" else 1
	for df in [-1, 1]:
		var nf: int = f + df
		var nr: int = r + dir
		if _in_bounds(nf, nr) and board[nr][nf] == attacker_side + "P":
			return true
	return false

func _in_check(side: String) -> bool:
	var kp: Vector2i = _king_pos(side)
	if kp.x == -1:
		return false
	var opp: String = ("b" if side == "w" else "w")
	return _is_attacked_by(kp.y, kp.x, opp)

func _king_pos(side: String) -> Vector2i:
	for r in range(8):
		for f in range(8):
			if board[r][f] == side + "K":
				return Vector2i(f, r)
	return Vector2i(-1, -1)

func _legal_moves_for_square(from_sq: Vector2i) -> Array[Vector2i]:
	var piece: String = board[from_sq.y][from_sq.x]
	if piece == "":
		_log("_legal_moves_for_square: empty square %s" % _square_name(from_sq))
		return []
	if piece[0] != turn:
		_log("_legal_moves_for_square: piece side %s != turn %s" % [piece[0], turn])
		return []
	_log("_legal_moves_for_square: generating for %s at %s" % [piece, _square_name(from_sq)])
	var raw: Array[Vector2i] = _pseudo_legal_moves(from_sq)
	_log("  pseudo_legal count=%d" % raw.size())
	var legal: Array[Vector2i] = []
	for to_sq in raw:
		var snapshot: Dictionary[String, Variant] = _snapshot()
		_make_move_internal(from_sq, to_sq, true)
		var me: String = turn
		var myking: Vector2i = _king_pos(me)
		var opp: String = ("b" if me == "w" else "w")
		var incheck: bool = false
		if myking.x != -1 and myking.y != -1:
			incheck = _is_attacked_by(myking.y, myking.x, opp)
		_restore(snapshot)
		if not incheck:
			legal.append(to_sq)
		else:
			_log("    move %s would leave king in check -> discarded" % _square_name(to_sq))
	_log("  legal moves count=%d" % legal.size())
	return legal

func _pseudo_legal_moves(from_sq: Vector2i) -> Array[Vector2i]:
	var f: int = from_sq.x
	var r: int = from_sq.y
	var piece: String = board[r][f]
	if piece == "":
		return []
	var side: String = piece[0]
	var p: String = piece[1]
	var out: Array[Vector2i] = []
	
	if p == "P":
		# Pawns: GamePigeon orientation (board[0] is rank 1/white back rank, board[7] is rank 8/black back rank)
		var dir = 1 if side == "w" else -1
		var one_r = r + dir
		var start_r = 1 if side == "w" else 6

		# Forward moves (non-capturing)
		if _in_bounds(f, one_r) and board[one_r][f] == "":
			out.append(Vector2i(f, one_r))
			# Double move from starting position
			var two_r = r + dir * 2
			if r == start_r and _in_bounds(f, two_r) and board[two_r][f] == "":
				out.append(Vector2i(f, two_r))

		# Diagonal captures (MUST capture an enemy piece - never allow diagonal to empty square)
		for df in [-1, 1]:
			var nf = f + df
			var nr = r + dir
			if _in_bounds(nf, nr):
				var target_piece: String = board[nr][nf]
				# Defensive validation: target square MUST be occupied by enemy piece
				if target_piece != "" and target_piece.length() >= 1 and target_piece[0] != side:
					_log("_pseudo_legal_moves: pawn at %s can capture diagonally at %s (target=%s)" % [_square_name(from_sq), _square_name(Vector2i(nf, nr)), target_piece])
					out.append(Vector2i(nf, nr))
				elif target_piece == "" or target_piece.length() == 0:
					# Explicitly log rejection of diagonal moves to empty squares
					_log("_pseudo_legal_moves: REJECTED pawn diagonal move from %s to %s (empty square - not a capture)" % [_square_name(from_sq), _square_name(Vector2i(nf, nr))])
		
		# En passant capture (diagonal move to empty square to capture enemy pawn)
		# En passant ONLY valid from specific ranks: white from rank 5 (r=4), black from rank 4 (r=3)
		if en_passant != "-":
			var epf = FILE_RANKS.find(en_passant[0])
			var epr = int(en_passant.substr(1)) - 1
			var en_passant_rank = 4 if side == "w" else 3

			# Defensive validation: pawn MUST be on en passant rank (NOT starting rank)
			# White: starting rank = 1, en passant rank = 4
			# Black: starting rank = 6, en passant rank = 3
			if r == start_r:
				_log("_pseudo_legal_moves: REJECTED en passant for pawn at %s (still on starting rank %d, ep_rank=%d)" % [_square_name(from_sq), r, en_passant_rank])
			elif abs(epf - f) == 1 and epr == r + dir and r == en_passant_rank:
				_log("_pseudo_legal_moves: pawn at %s can capture en passant at %s (ep_target=%s)" % [_square_name(from_sq), _square_name(Vector2i(epf, epr)), en_passant])
				out.append(Vector2i(epf, epr))
			else:
				_log("_pseudo_legal_moves: en passant check failed for pawn at %s: epf=%d f=%d epr=%d calc=%d r=%d ep_rank=%d" % [_square_name(from_sq), epf, f, epr, r + dir, r, en_passant_rank])
				
	elif p == "N":
		var moves = [[1,2],[2,1],[-1,2],[-2,1],[1,-2],[2,-1],[-1,-2],[-2,-1]]
		for m in moves:
			var nf = f + m[0]
			var nr = r + m[1]
			if _in_bounds(nf, nr) and (board[nr][nf] == "" or board[nr][nf][0] != side):
				out.append(Vector2i(nf, nr))
				
	elif p == "B" or p == "R" or p == "Q":
		var dirs = []
		if p == "B":
			dirs = [[1,1],[1,-1],[-1,1],[-1,-1]]
		elif p == "R":
			dirs = [[1,0],[-1,0],[0,1],[0,-1]]
		else:  # Queen
			dirs = [[1,1],[1,-1],[-1,1],[-1,-1],[1,0],[-1,0],[0,1],[0,-1]]
		
		for d in dirs:
			var nf = f + d[0]
			var nr = r + d[1]
			while _in_bounds(nf, nr):
				if board[nr][nf] == "":
					out.append(Vector2i(nf, nr))
				else:
					if board[nr][nf][0] != side:
						out.append(Vector2i(nf, nr))
					break
				nf += d[0]
				nr += d[1]
				
	elif p == "K":
		for nr in range(r-1, r+2):
			for nf in range(f-1, f+2):
				if nf == f and nr == r:
					continue
				if _in_bounds(nf, nr) and (board[nr][nf] == "" or board[nr][nf][0] != side):
					out.append(Vector2i(nf, nr))
		
		# Castling — fix rows: white row 7, black row 0
		var opp = "b" if side == "w" else "w"
		if side == "w":
			if castling.find("K") != -1 and board[7][7] == "wR":
				if board[7][5] == "" and board[7][6] == "" and not _is_attacked_by(7,4,opp) and not _is_attacked_by(7,5,opp) and not _is_attacked_by(7,6,opp):
					out.append(Vector2i(6,7))
			if castling.find("Q") != -1 and board[7][0] == "wR":
				if board[7][1] == "" and board[7][2] == "" and board[7][3] == "" and not _is_attacked_by(7,4,opp) and not _is_attacked_by(7,3,opp) and not _is_attacked_by(7,2,opp):
					out.append(Vector2i(2,7))
		else:
			if castling.find("k") != -1 and board[0][7] == "bR":
				if board[0][5] == "" and board[0][6] == "" and not _is_attacked_by(0,4,opp) and not _is_attacked_by(0,5,opp) and not _is_attacked_by(0,6,opp):
					out.append(Vector2i(6,0))
			if castling.find("q") != -1 and board[0][0] == "bR":
				if board[0][1] == "" and board[0][2] == "" and board[0][3] == "" and not _is_attacked_by(0,4,opp) and not _is_attacked_by(0,3,opp) and not _is_attacked_by(0,2,opp):
					out.append(Vector2i(2,0))
	
	_log("_pseudo_legal_moves for %s at %s returned %d moves" % [piece, _square_name(from_sq), out.size()])
	return out

# Execute the physical move on the board (first half of move logic)
# Does NOT switch turns - that happens in _commit_move
func _execute_move(from_sq: Vector2i, to_sq: Vector2i) -> void:
	_log("_execute_move called %s -> %s" % [_square_name(from_sq), _square_name(to_sq)])
	_debug_state("before_execute")

	# Save previous board state in GamePigeon format before executing the move
	prev_board_gp = board_to_gp_array()
	_log("_execute_move: saved prev_board_gp")

	var moving: String = board[from_sq.y][from_sq.x]
	var target: String = board[to_sq.y][to_sq.x]
	var side: String = moving[0]
	var p: String = moving[1]

	var _prev_enp: String = en_passant
	en_passant = "-"

	var capture: bool = false

	# Handle en passant capture
	if p == "P" and target == "" and from_sq.x != to_sq.x:
		var dir = 1 if side == "w" else -1
		var cap_r = to_sq.y - dir
		_log("_execute_move performing en-passant capture cap_r=%d cap_file=%d" % [cap_r, to_sq.x])
		board[cap_r][to_sq.x] = ""
		capture = true

	# Move piece
	board[to_sq.y][to_sq.x] = moving
	board[from_sq.y][from_sq.x] = ""

	# Pawn double push sets en passant target
	if p == "P" and abs(to_sq.y - from_sq.y) == 2:
		var dir = 1 if side == "w" else -1
		var ep_r = from_sq.y + dir
		en_passant = FILE_RANKS[to_sq.x] + str(ep_r + 1)
		_log("_execute_move set en_passant=%s" % en_passant)

	# Promotion (using chosen piece or default to Queen)
	if p == "P":
		if (side == "w" and to_sq.y == 7) or (side == "b" and to_sq.y == 0):
			var promo_piece: String = "Q" if promotion_choice == "" else promotion_choice
			board[to_sq.y][to_sq.x] = side + promo_piece
			last_move_promotion_piece = promo_piece  # Store for UCI notation
			_log("_execute_move promotion at %s -> %s (choice=%s)" % [_square_name(to_sq), board[to_sq.y][to_sq.x], promo_piece])
			# Clear promotion_choice after using it
			promotion_choice = ""

	# Castling rook moves
	if p == "K":
		if side == "w":
			castling = castling.replace("K", "").replace("Q", "")
			if from_sq == Vector2i(4,7) and to_sq == Vector2i(6,7):
				board[7][5] = "wR"
				board[7][7] = ""
				_log("_execute_move white kingside castle: moved rook h1->f1")
			elif from_sq == Vector2i(4,7) and to_sq == Vector2i(2,7):
				board[7][3] = "wR"
				board[7][0] = ""
				_log("_execute_move white queenside castle: moved rook a1->d1")
		else:
			castling = castling.replace("k", "").replace("q", "")
			if from_sq == Vector2i(4,0) and to_sq == Vector2i(6,0):
				board[0][5] = "bR"
				board[0][7] = ""
				_log("_execute_move black kingside castle: moved rook h8->f8")
			elif from_sq == Vector2i(4,0) and to_sq == Vector2i(2,0):
				board[0][3] = "bR"
				board[0][0] = ""
				_log("_execute_move black queenside castle: moved rook a8->d8")

	# Rook moves update castling rights
	if p == "R":
		if from_sq == Vector2i(0,7):
			castling = castling.replace("Q", "")
		elif from_sq == Vector2i(7,7):
			castling = castling.replace("K", "")
		elif from_sq == Vector2i(0,0):
			castling = castling.replace("q", "")
		elif from_sq == Vector2i(7,0):
			castling = castling.replace("k", "")

	# Capturing enemy rook also updates castling
	if target == "bR":
		if to_sq == Vector2i(0,0):
			castling = castling.replace("q", "")
		elif to_sq == Vector2i(7,0):
			castling = castling.replace("k", "")
	elif target == "wR":
		if to_sq == Vector2i(0,7):
			castling = castling.replace("Q", "")
		elif to_sq == Vector2i(7,7):
			castling = castling.replace("K", "")

	# halfmove clock
	if p == "P" or target != "":
		halfmove = 0
		capture = capture or (target != "")
	else:
		halfmove += 1
	
	_log("_execute_move complete (board updated, turn NOT switched yet)")
	_debug_state("after_execute")

# Commit the move: switch turns, check game end, send to appPlugin (second half of move logic)
# This is called after _execute_move when the player confirms the move via send button
func _commit_move(from_sq: Vector2i, to_sq: Vector2i) -> void:
	_log("_commit_move called %s -> %s" % [_square_name(from_sq), _square_name(to_sq)])
	_debug_state("before_commit")
	var uci: String = _to_uci(from_sq, to_sq)
	last_move_promotion_piece = ""  # Clear after using in UCI
	var moving: String = board[to_sq.y][to_sq.x]  # piece is already at destination
	var side: String = moving[0]

	# Switch turn to opponent
	var old_turn: String = turn
	turn = "b" if turn == "w" else "w"
	_log("_commit_move flipped turn %s -> %s" % [old_turn, turn])
	if turn == "w":
		fullmove += 1

	_count_position()
	_debug_state("after_commit")

	# Clear opponent's last move highlights (player is making their move now)
	opponent_last_move_from = Vector2i(-1, -1)
	opponent_last_move_to = Vector2i(-1, -1)
	_log("_commit_move: cleared opponent last move highlights")

	# Determine game end conditions
	var winner_decl = null
	var opp = ("b" if side == "w" else "w")
	var has_legal = _side_has_legal(opp)
	var opp_king = _king_pos(opp)
	var opp_in_check = false
	if opp_king.x != -1 and opp_king.y != -1:
		opp_in_check = _is_attacked_by(opp_king.y, opp_king.x, side)

		if not has_legal:
			if opp_in_check:
				# Checkmate - current player (who just moved) wins
				game_over = true
				game_over_reason = "CHECKMATE - %s wins" % ("White" if side == "w" else "Black")
				game_over_winner_side = side
				winner_decl = my_player_id + "|" + (str(my_player_index) if side == my_color else str(enemy_player_index))
				_log("_commit_move detected CHECKMATE")
			else:
				# Stalemate -> draw
				game_over = true
				game_over_reason = "STALEMATE - Draw"
				game_over_winner_side = ""
				winner_decl = my_player_id + "|0"
				_log("_commit_move detected STALEMATE")
	elif halfmove >= 100:
		game_over = true
		game_over_reason = "DRAW - 50-move rule"
		winner_decl = my_player_id + "|0"
		_log("_commit_move detected 50-move draw")
	else:
		# threefold repetition
		var pos_key = to_position_key()
		if position_counts.get(pos_key, 0) >= 3:
			game_over = true
			game_over_reason = "DRAW - threefold repetition"
			winner_decl = my_player_id + "|0"
			_log("_commit_move detected threefold repetition draw")

	# Export data to host in GamePigeon format
	var gp_replay = to_gp_replay(prev_board_gp, from_sq, to_sq)
	_log("_commit_move: generated GamePigeon replay: %s" % gp_replay)
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
		_log("_commit_move: game ended, winner_decl=%s" % str(winner_decl))
	else:
		play_sent_animation()
		if not local_mode:
			waitingForOpponent = true
			isTurn = false
			_log("_commit_move: remote mode - set waitingForOpponent=true, isTurn=false (waiting for remote update)")
		else:
			# local debug: keep interaction enabled for the other side (allow playing both sides)
			waitingForOpponent = false
			isTurn = true
			_log("_commit_move: local mode - kept interaction enabled for both sides")

	# Evaluate check/stalemate on the new position to update UI/selectability
	_evaluate_check_and_update_flags()
	
	# Update the waiting label to reflect the new waiting state
	_update_waiting_label()

	# Send to appPlugin (always send in commit)
	_debug_state("_commit_move before send")
	if not local_mode:
		_log("_commit_move sending updateGameData: %s" % str(to_send))
		appPlugin.updateGameData(JSON.stringify(to_send))
	else:
		_log("_commit_move local-only; not sending to appPlugin")
	_log("_commit_move complete")

# Full move application (for local mode and backward compatibility)
# Combines _execute_move and _commit_move into one operation
func _apply_move(from_sq: Vector2i, to_sq: Vector2i) -> void:
	_log("_apply_move called %s -> %s (full move for local mode)" % [_square_name(from_sq), _square_name(to_sq)])
	_execute_move(from_sq, to_sq)
	_commit_move(from_sq, to_sq)

func _side_has_legal(side: String) -> bool:
	_log("_side_has_legal check for side=%s" % side)
	var old_turn: String = turn
	turn = side
	for r in range(8):
		for f in range(8):
			if board[r][f].begins_with(side):
				var from_sq = Vector2i(f,r)
				var moves = _legal_moves_for_square(from_sq)
				if moves.size() > 0:
					turn = old_turn
					_log("_side_has_legal -> true (found legal for %s at %s)" % [side, _square_name(from_sq)])
					return true
	turn = old_turn
	_log("_side_has_legal -> false")
	return false

func _evaluate_check_and_update_flags() -> void:
	# Evaluate whether the side to move is in check, and whether there are legal moves.
	game_over = game_over if game_over else false  # ensure default
	game_over_reason = game_over_reason if game_over_reason != "" else ""
	var side_to_move: String = turn
	var incheck: bool = _in_check(side_to_move)
	var has_legal: bool = _side_has_legal(side_to_move)
	if not has_legal:
		if incheck:
			_log("Game state: CHECKMATE for %s (no legal moves while in check)" % side_to_move)
			game_over = true
			game_over_reason = "CHECKMATE - %s loses" % ("White" if side_to_move == "w" else "Black")
			# winner is the opposite side
			game_over_winner_side = ("b" if side_to_move == "w" else "w")
		else:
			_log("Game state: STALEMATE for %s (no legal moves, not in check)" % side_to_move)
			game_over = true
			game_over_reason = "STALEMATE - Draw"
			game_over_winner_side = ""
		# mark game finished for UI and disable interaction
		waitingForOpponent = true
		isTurn = false
	else:
		# If the game was previously finished but now has legal moves, clear game_over (unlikely during normal play)
		if game_over and has_legal:
			game_over = false
			game_over_reason = ""
		# Ensure our usual interaction flags stay aligned (local_mode / remote handled by _update_turn_flags)
		_update_turn_flags()
	if incheck:
		_log("Game state: %s is currently in CHECK" % side_to_move)
	# Refresh UI to show disabled pieces / highlight king-in-check / game over
	_refresh_board_ui()

func _snapshot() -> Dictionary[String, Variant]:
	return {
		"board": _clone_board(),
		"turn": turn,
		"castling": castling,
		"en_passant": en_passant,
		"halfmove": halfmove,
		"fullmove": fullmove,
		"pos_counts": position_counts.duplicate(true)
	}

func _restore(s: Dictionary[String, Variant]) -> void:
	board = _clone_board(s.board)
	turn = s.turn
	castling = s.castling
	en_passant = s.en_passant
	halfmove = s.halfmove
	fullmove = s.fullmove
	position_counts = s.pos_counts
	_log("_restore executed")

func _clone_board(src: Array = board) -> Array:
	var out: Array = []
	for r in range(8):
		var row: Array[String] = src[r].duplicate()
		out.append(row)
	return out

func _make_move_internal(from_sq: Vector2i, to_sq: Vector2i, ignore_end_states: bool = false) -> void:
	_log("_make_move_internal %s -> %s (ignore_end_states=%s)" % [_square_name(from_sq), _square_name(to_sq), str(ignore_end_states)])
	var moving: String = board[from_sq.y][from_sq.x]
	var target: String = board[to_sq.y][to_sq.x]
	var side: String = moving[0]
	var p: String = moving[1]

	en_passant = "-"

	# Handle en passant inside internal move (dir orientation)
	if p == "P" and target == "" and from_sq.x != to_sq.x:
		var dir = 1 if side == "w" else -1
		board[to_sq.y - dir][to_sq.x] = ""
		_log("_make_move_internal en-passant clear cap square %s" % _square_name(Vector2i(to_sq.x, to_sq.y - dir)))

	board[to_sq.y][to_sq.x] = moving
	board[from_sq.y][from_sq.x] = ""

	if p == "P" and abs(to_sq.y - from_sq.y) == 2:
		var dir = 1 if side == "w" else -1
		en_passant = FILE_RANKS[to_sq.x] + str(from_sq.y + dir + 1)
		_log("_make_move_internal set en_passant=%s" % en_passant)

	if p == "P":
		if (side == "w" and to_sq.y == 7) or (side == "b" and to_sq.y == 0):
			# For internal moves (validation), always promote to Queen
			board[to_sq.y][to_sq.x] = side + "Q"
			_log("_make_move_internal promotion at %s" % _square_name(to_sq))
	
	if p == "K":
		if side == "w":
			castling = castling.replace("K", "").replace("Q", "")
			if from_sq == Vector2i(4,7) and to_sq == Vector2i(6,7):
				board[7][5] = "wR"
				board[7][7] = ""
			elif from_sq == Vector2i(4,7) and to_sq == Vector2i(2,7):
				board[7][3] = "wR"
				board[7][0] = ""
		else:
			castling = castling.replace("k", "").replace("q", "")
			if from_sq == Vector2i(4,0) and to_sq == Vector2i(6,0):
				board[0][5] = "bR"
				board[0][7] = ""
			elif from_sq == Vector2i(4,0) and to_sq == Vector2i(2,0):
				board[0][3] = "bR"
				board[0][0] = ""
	
	if p == "R":
		if from_sq == Vector2i(0,7): castling = castling.replace("Q", "")
		elif from_sq == Vector2i(7,7): castling = castling.replace("K", "")
		elif from_sq == Vector2i(0,0): castling = castling.replace("q", "")
		elif from_sq == Vector2i(7,0): castling = castling.replace("k", "")
	
	if target == "bR":
		if to_sq == Vector2i(0,0): castling = castling.replace("q", "")
		elif to_sq == Vector2i(7,0): castling = castling.replace("k", "")
	elif target == "wR":
		if to_sq == Vector2i(0,7): castling = castling.replace("Q", "")
		elif to_sq == Vector2i(7,7): castling = castling.replace("K", "")

	if not ignore_end_states:
		if p == "P" or target != "":
			halfmove = 0
		else:
			halfmove += 1
		turn = "b" if turn == "w" else "w"
		if turn == "w":
			fullmove += 1
		_count_position()
	_log("_make_move_internal done")

func _to_uci(from_sq: Vector2i, to_sq: Vector2i) -> String:
	var uci: String = _square_name(from_sq) + _square_name(to_sq)
	# Append promotion piece in lowercase if this was a promotion
	if last_move_promotion_piece != "":
		uci += last_move_promotion_piece.to_lower()
	return uci

func _square_name(sq: Vector2i) -> String:
	return FILE_RANKS[sq.x] + str(sq.y + 1)

func _count_position() -> void:
	var key: String = to_position_key()
	position_counts[key] = int(position_counts.get(key, 0)) + 1
	_log("_count_position incremented key=%s count=%d" % [key, position_counts[key]])
		
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
		background.color = Color("#261a19") if is_dark else Color("#947972")
		
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
