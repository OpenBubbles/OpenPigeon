class_name ChessAnimations
extends RefCounted

## Chess animation controller.
## Handles piece movement animations, pulse highlights, and UI transitions.

## Animation timing constants - reference ChessUI for single source of truth
const MOVE_DURATION: float = ChessUI.MOVE_ANIMATION_DURATION
const PULSE_DURATION: float = ChessUI.PULSE_DURATION
const PULSE_MIN_ALPHA: float = ChessUI.PULSE_MIN_ALPHA
const PULSE_MAX_ALPHA: float = ChessUI.PULSE_MAX_ALPHA
const LIFT_SCALE: float = 1.08  # Slight grow while a piece is "picked up"
const SNAP_DURATION: float = 0.14  # Drag drop / return snap
const LIFT_Z: int = 50  # Above pieces (10) and overlays (20) while moving
const REST_Z: int = 10

## Internal state
var _pieces: Array = []  # 8x8 array of TextureRect
var _squares: Array = []  # 8x8 array of ColorRect
var _pulse_tweens: Dictionary = {}  # ColorRect -> Tween
var _scene_tree: SceneTree = null
var _is_animating: bool = false
var _log_callback: Callable = Callable()

## Initialize with UI element references
func setup(pieces: Array, squares: Array, scene_tree: SceneTree, log_callback: Callable = Callable()) -> void:
	_pieces = pieces
	_squares = squares
	_scene_tree = scene_tree
	_log_callback = log_callback

## Check if UI is ready for animations
func is_ready() -> bool:
	return _pieces.size() == 8 and _squares.size() == 8 and _scene_tree != null

## Check if currently animating
func is_animating() -> bool:
	return _is_animating

## Internal logging
func _log(msg: String) -> void:
	if _log_callback.is_valid():
		_log_callback.call("ANIM: " + msg)

# ============================================================================
# PULSE ANIMATIONS
# ============================================================================

## Start a pulse animation on a ColorRect overlay
func start_pulse(overlay: ColorRect) -> void:
	if overlay == null:
		return
	stop_pulse(overlay)

	if _scene_tree == null:
		return

	var tween: Tween = _scene_tree.create_tween()
	tween.set_loops()
	tween.tween_property(overlay, "modulate:a", PULSE_MIN_ALPHA, PULSE_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(overlay, "modulate:a", PULSE_MAX_ALPHA, PULSE_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tweens[overlay] = tween

	# Auto-cleanup when overlay is about to be freed (prevents orphaned tweens)
	if not overlay.tree_exiting.is_connected(_on_pulse_overlay_exiting):
		overlay.tree_exiting.connect(_on_pulse_overlay_exiting.bind(overlay), CONNECT_ONE_SHOT)

## Callback when a pulsing overlay is about to be freed from the scene tree
func _on_pulse_overlay_exiting(overlay: ColorRect) -> void:
	stop_pulse(overlay)

## Stop a pulse animation on a ColorRect overlay
func stop_pulse(overlay: ColorRect) -> void:
	if _pulse_tweens.has(overlay):
		var tween: Tween = _pulse_tweens[overlay]
		if is_instance_valid(tween):
			tween.kill()
		_pulse_tweens.erase(overlay)
	# Reset modulate alpha
	if is_instance_valid(overlay):
		overlay.modulate = Color(1, 1, 1, 1)

## Stop all pulse animations
func stop_all_pulses() -> void:
	for overlay in _pulse_tweens.keys():
		var tween: Tween = _pulse_tweens[overlay]
		if is_instance_valid(tween):
			tween.kill()
		if is_instance_valid(overlay):
			overlay.modulate = Color(1, 1, 1, 1)
	_pulse_tweens.clear()

## Get count of active pulse animations
func get_pulse_count() -> int:
	return _pulse_tweens.size()

# ============================================================================
# PIECE MOVEMENT ANIMATIONS
# ============================================================================
## Resting (unscaled) top-left of the piece slot for a square
func _slot_pos(sq: Vector2i) -> Vector2:
	var square: ColorRect = _squares[sq.y][sq.x]
	return ChessUI.calculate_piece_rect(square.position, square.size.x)["position"]

## Waypoints for a move: straight line, or an L for knight jumps (long leg first)
func _move_path(from_sq: Vector2i, to_sq: Vector2i) -> Array[Vector2]:
	var path: Array[Vector2] = [_slot_pos(from_sq)]
	var d: Vector2i = (to_sq - from_sq).abs()
	if d == Vector2i(2, 1) or d == Vector2i(1, 2):
		path.append(_slot_pos(Vector2i(to_sq.x, from_sq.y) if d.x == 2 else Vector2i(from_sq.x, to_sq.y)))
	path.append(_slot_pos(to_sq))
	return path

## Point at fraction t (0..1) of the total length along a path
static func _point_on_path(path: Array[Vector2], t: float) -> Vector2:
	var total: float = 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	var remaining: float = t * total
	for i in range(1, path.size()):
		var seg: float = path[i - 1].distance_to(path[i])
		if seg > 0.0 and remaining <= seg:
			return path[i - 1].lerp(path[i], remaining / seg)
		remaining -= seg
	return path[path.size() - 1]

## Tween a piece along a path. From rest it grows (picked up) then settles;
## if it is already lifted (drag) it shrinks back down as it lands.
func _path_tween(piece_tex: TextureRect, path: Array[Vector2], duration: float) -> Tween:
	var start_scale: float = piece_tex.scale.x
	piece_tex.pivot_offset = piece_tex.size * 0.5
	piece_tex.z_index = LIFT_Z
	var step := func(t: float) -> void:
		piece_tex.position = _point_on_path(path, t)
		var s: float = lerpf(start_scale, 1.0, t) if start_scale > 1.0 else 1.0 + (LIFT_SCALE - 1.0) * sin(PI * t)
		piece_tex.scale = Vector2(s, s)
	var tween: Tween = _scene_tree.create_tween()
	tween.tween_method(step, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func():
		piece_tex.position = path[path.size() - 1]
		piece_tex.scale = Vector2.ONE
		piece_tex.z_index = REST_Z
	)
	return tween

## Pick a piece up (drag start): grow slightly and draw above everything
func lift_piece(piece_tex: TextureRect) -> void:
	piece_tex.pivot_offset = piece_tex.size * 0.5
	piece_tex.z_index = LIFT_Z
	_scene_tree.create_tween().tween_property(piece_tex, "scale", Vector2.ONE * LIFT_SCALE, SNAP_DURATION)

## Return a dragged piece to its own square (invalid drop)
func return_piece(sq: Vector2i) -> void:
	var piece_tex: TextureRect = _pieces[sq.y][sq.x]
	var back: Array[Vector2] = [piece_tex.position, _slot_pos(sq)]
	_is_animating = true
	await _path_tween(piece_tex, back, SNAP_DURATION).finished
	_is_animating = false

## Create a tween for animating a piece move (does not await)
## Returns null if animation cannot be created
func create_piece_tween(from_rank: int, from_file: int, to_rank: int, to_file: int, from_drag: bool = false) -> Tween:
	if not is_ready():
		_log("create_piece_tween: not ready")
		return null

	if from_rank < 0 or from_rank > 7 or from_file < 0 or from_file > 7:
		_log("create_piece_tween: invalid from position")
		return null

	if to_rank < 0 or to_rank > 7 or to_file < 0 or to_file > 7:
		_log("create_piece_tween: invalid to position")
		return null

	var piece_tex: TextureRect = _pieces[from_rank][from_file]
	if piece_tex == null or piece_tex.texture == null:
		_log("create_piece_tween: no piece at source")
		return null

	# Null check for destination square to prevent potential crash
	if _pieces[to_rank][to_file] == null:
		_log("create_piece_tween: no target piece slot at [%d][%d]" % [to_rank, to_file])
		return null

	var to_sq := Vector2i(to_file, to_rank)
	if from_drag:
		var snap: Array[Vector2] = [piece_tex.position, _slot_pos(to_sq)]
		return _path_tween(piece_tex, snap, SNAP_DURATION)
	var path: Array[Vector2] = _move_path(Vector2i(from_file, from_rank), to_sq)
	return _path_tween(piece_tex, path, MOVE_DURATION * (1.0 + 0.25 * (path.size() - 2)))

## Animate a single piece move (awaitable)
func animate_piece_move(from_rank: int, from_file: int, to_rank: int, to_file: int, from_drag: bool = false) -> void:
	var tween: Tween = create_piece_tween(from_rank, from_file, to_rank, to_file, from_drag)
	if tween == null:
		_log("animate_piece_move: failed to create tween")
		return

	_is_animating = true
	_log("animate_piece_move: %d,%d -> %d,%d" % [from_file, from_rank, to_file, to_rank])

	await tween.finished

	_is_animating = false
	_log("animate_piece_move: complete")

## Animate castling (king and rook move together)
func animate_castling(king_from_rank: int, king_from_file: int, king_to_rank: int, king_to_file: int,
					  rook_from_rank: int, rook_from_file: int, rook_to_rank: int, rook_to_file: int, from_drag: bool = false) -> void:
	if not is_ready():
		_log("animate_castling: not ready")
		return

	_is_animating = true
	_log("animate_castling: king %d,%d->%d,%d, rook %d,%d->%d,%d" % [
		king_from_file, king_from_rank, king_to_file, king_to_rank,
		rook_from_file, rook_from_rank, rook_to_file, rook_to_rank
	])

	# Create both tweens (they run in parallel)
	var king_tween: Tween = create_piece_tween(king_from_rank, king_from_file, king_to_rank, king_to_file, from_drag)
	var rook_tween: Tween = create_piece_tween(rook_from_rank, rook_from_file, rook_to_rank, rook_to_file)

	if king_tween == null or rook_tween == null:
		_log("animate_castling: failed to create tweens")
		_is_animating = false
		return

	# Wait for both to complete
	await king_tween.finished
	await rook_tween.finished

	_is_animating = false
	_log("animate_castling: complete")

# ============================================================================
# HIGH-LEVEL MOVE ANIMATIONS
# ============================================================================

## Animation result structure
class MoveAnimationParams:
	var from_sq: Vector2i
	var to_sq: Vector2i
	var moving_piece: String
	var target_piece: String
	var is_castling: bool = false
	var is_en_passant: bool = false
	var is_capture: bool = false
	var rook_from_file: int = -1
	var rook_to_file: int = -1
	var captured_pawn_rank: int = -1

	func _init(from: Vector2i, to: Vector2i, moving: String, target: String) -> void:
		from_sq = from
		to_sq = to
		moving_piece = moving
		target_piece = target

## Analyze a move and return animation parameters
## Uses ChessPiece for canonical castle/en passant logic to avoid duplication
func analyze_move(from_sq: Vector2i, to_sq: Vector2i, board: Array) -> MoveAnimationParams:
	var moving: String = board[from_sq.y][from_sq.x]
	var target: String = board[to_sq.y][to_sq.x]

	var params := MoveAnimationParams.new(from_sq, to_sq, moving, target)

	if moving == "":
		return params

	# Create ChessPiece instance for canonical move analysis
	var piece: ChessPiece = ChessPiece.from_notation(moving, from_sq)
	if piece == null:
		return params

	# Detect castling using ChessPiece
	if piece.is_castle_move(to_sq):
		params.is_castling = true
		var rook_move: Dictionary = piece.get_castle_rook_move(to_sq)
		if not rook_move.is_empty():
			params.rook_from_file = rook_move["rook_from"].x
			params.rook_to_file = rook_move["rook_to"].x

	# Detect en passant (pawn diagonal move to empty square)
	elif piece.type == ChessPiece.PieceType.PAWN and target == "" and from_sq.x != to_sq.x:
		params.is_en_passant = true
		var ep_capture: Vector2i = piece.get_en_passant_capture_square(to_sq)
		params.captured_pawn_rank = ep_capture.y

	# Detect capture
	elif target != "":
		params.is_capture = true

	return params

## Hide a piece at the given position (for captures)
func hide_piece(rank: int, file: int) -> void:
	if not is_ready():
		return
	if rank >= 0 and rank < 8 and file >= 0 and file < 8:
		if _pieces[rank][file] != null:
			_pieces[rank][file].texture = null

## Animate a move with automatic detection of special moves
func animate_move(from_sq: Vector2i, to_sq: Vector2i, board: Array, from_drag: bool = false) -> void:
	if not is_ready():
		_log("animate_move: not ready")
		return

	var params: MoveAnimationParams = analyze_move(from_sq, to_sq, board)

	if params.moving_piece == "":
		_log("animate_move: no piece at source")
		return

	_log("animate_move: %s from %d,%d to %d,%d" % [params.moving_piece, from_sq.x, from_sq.y, to_sq.x, to_sq.y])

	# Handle castling
	if params.is_castling:
		_log("animate_move: castling detected")
		await animate_castling(from_sq.y, from_sq.x, to_sq.y, to_sq.x,
							   from_sq.y, params.rook_from_file, to_sq.y, params.rook_to_file, from_drag)
		return

	# Handle en passant (hide captured pawn)
	if params.is_en_passant:
		_log("animate_move: en passant detected")
		hide_piece(params.captured_pawn_rank, to_sq.x)

	# Handle capture (hide captured piece)
	elif params.is_capture:
		_log("animate_move: capture detected")
		hide_piece(to_sq.y, to_sq.x)

	# Animate the moving piece
	await animate_piece_move(from_sq.y, from_sq.x, to_sq.y, to_sq.x, from_drag)
