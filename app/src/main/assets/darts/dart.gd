extends MeshInstance3D
class_name Dart

signal on_hit_board(score: Array[int])

const LOG_TAG := "Dart"
const REFERENCE_FPS := 60.0
const FLIGHT_FRAMES := 30.0
const FLIGHT_DURATION := FLIGHT_FRAMES / REFERENCE_FPS
const ARC_HEIGHT := 0.25
const ROTATION_SPEED_MIN := 0.12
const ROTATION_SPEED_RANGE := 0.05
const FADE_RETAIN_PER_FRAME := 0.92
const MODEL_FORWARD_AXIS := Vector3(0.0, -1.0, 0.0)

var finished: bool = false
var is_mine: bool = false
var replay_hit: Array[int] = []

var start_pos: Vector3 = Vector3.ZERO
var end_pos: Vector3 = Vector3.ZERO

var rotation_speed: float = ROTATION_SPEED_MIN

var game: DartsGame
var dartboard: Dartboard

var DEBUG_DART := false

var _flying: bool = false
var _flight_elapsed: float = 0.0

var _base_basis: Basis = Basis.IDENTITY
var _base_forward: Vector3 = Vector3.FORWARD

var _spin_angle: float = 0.0
var _spin_direction: float = 1.0


func dbg(msg: String) -> void:
	if DEBUG_DART:
		OpLog.d(LOG_TAG, msg)


func _ready() -> void:
	game = get_parent() as DartsGame
	dartboard = get_parent().get_node_or_null("dart_board") as Dartboard

	_base_basis = basis

	_base_forward = _base_basis * MODEL_FORWARD_AXIS

	if _base_forward.length_squared() > 0.000001:
		_base_forward = _base_forward.normalized()
	else:
		_base_forward = Vector3.FORWARD

	rotation_speed = (
		ROTATION_SPEED_MIN +
		randf() * ROTATION_SPEED_RANGE
	)

	transparency = 1.0

	OpLog.d(LOG_TAG, [
		"dart_ready game_valid=", is_instance_valid(game),
		" dartboard_valid=", is_instance_valid(dartboard),
		" rotation_speed=", rotation_speed,
		" base_forward=", _base_forward,
		" basis=", _base_basis
	])


func throw(p_end_pos: Vector3) -> void:
	start_pos = position
	end_pos = p_end_pos

	finished = false
	_flying = true
	_flight_elapsed = 0.0
	_spin_angle = 0.0
	_spin_direction = -1.0 if end_pos.x >= 0.0 else 1.0

	OpLog.event(LOG_TAG, [
		"throw start=", start_pos,
		" end=", end_pos,
		" is_mine=", is_mine,
		" duration=", FLIGHT_DURATION,
		" arc_height=", ARC_HEIGHT,
		" rotation_speed=", rotation_speed,
		" spin_direction=", _spin_direction
	])


func _process(delta: float) -> void:
	_update_opacity(delta)

	if not _flying:
		return

	_flight_elapsed += delta

	var progress := clampf(
		_flight_elapsed / FLIGHT_DURATION,
		0.0,
		1.0
	)

	_update_flight_position(progress)
	_update_flight_rotation(delta)

	if progress >= 1.0:
		position = end_pos
		_flying = false
		_register_board_hit()


func _update_opacity(delta: float) -> void:
	if transparency <= 0.0001:
		transparency = 0.0
		return

	var frame_multiplier := delta * REFERENCE_FPS
	transparency *= pow(FADE_RETAIN_PER_FRAME, frame_multiplier)

	if transparency < 0.001:
		transparency = 0.0


func _update_flight_position(progress: float) -> void:
	var next_position := start_pos.lerp(end_pos, progress)
	next_position.y += sin(progress * PI) * ARC_HEIGHT
	position = next_position

func _update_flight_rotation(delta: float) -> void:
	var flight_vector := end_pos - start_pos

	if flight_vector.length_squared() <= 0.000001:
		return

	var flight_direction := flight_vector.normalized()

	var alignment := _quaternion_from_to(
		_base_forward,
		flight_direction
	)

	var aligned_basis := Basis(alignment) * _base_basis

	_spin_angle += (
		_spin_direction *
		rotation_speed *
		delta *
		REFERENCE_FPS
	)

	var spin_basis := Basis(flight_direction, _spin_angle)
	basis = spin_basis * aligned_basis

func restore_hit(
	p_end_pos: Vector3,
	hit: Array[int]
) -> void:
	start_pos = position
	end_pos = p_end_pos
	position = p_end_pos

	replay_hit = hit.duplicate()

	finished = true
	_flying = false
	_flight_elapsed = FLIGHT_DURATION

	transparency = 0.0

func _quaternion_from_to(
	from_direction: Vector3,
	to_direction: Vector3
) -> Quaternion:
	var from_normalized := from_direction.normalized()
	var to_normalized := to_direction.normalized()
	var direction_dot := clampf(
		from_normalized.dot(to_normalized),
		-1.0,
		1.0
	)

	if direction_dot >= 0.999999:
		return Quaternion.IDENTITY

	if direction_dot <= -0.999999:
		var rotation_axis := from_normalized.cross(Vector3.UP)

		if rotation_axis.length_squared() <= 0.000001:
			rotation_axis = from_normalized.cross(Vector3.RIGHT)

		return Quaternion(rotation_axis.normalized(), PI)

	return Quaternion(from_normalized, to_normalized)


func _register_board_hit() -> void:
	if finished:
		return

	finished = true

	if not is_instance_valid(dartboard):
		OpLog.e(LOG_TAG, [
			"dart_hit_missing_board world_pos=",
			position
		])
		return

	var board_center := Vector2(
		dartboard.position.x,
		dartboard.position.y
	)

	var pos_2d := Vector2(
		position.x - board_center.x,
		board_center.y - position.y
	)

	if is_mine:
		var score: Array[int] = dartboard.get_score(pos_2d)

		OpLog.event(LOG_TAG, [
			"dart_hit_board mine=true",
			" pos_2d=", pos_2d,
			" world_pos=", position,
			" score=", score
		])

		if on_hit_board.has_connections():
			on_hit_board.emit(score)
		else:
			OpLog.w(LOG_TAG, [
				"dart_hit_no_signal_connections",
				" score=", score
			])

		return

	OpLog.event(LOG_TAG, [
		"dart_replay_hit",
		" pos_2d=", pos_2d,
		" world_pos=", position,
		" replay_hit=", replay_hit
	])

	if replay_hit.size() >= 3:
		dartboard.set_replay_highlight(
			pos_2d,
			int(replay_hit[1]),
			int(replay_hit[2])
		)
	else:
		OpLog.w(LOG_TAG, [
			"dart_replay_hit_bad_data",
			" replay_hit=", replay_hit
		])
