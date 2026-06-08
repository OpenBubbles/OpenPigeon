extends MeshInstance3D
class_name Dartboard

const BULLSEYE_RADIUS = 0.023
const OUTER_BULL_RADIUS = 0.056

const TRIPLE_RING_INNER_RADIUS = 0.287
const TRIPLE_RING_OUTER_RADIUS = 0.325

const DOUBLE_RING_INNER_RADIUS = 0.495
const DOUBLE_RING_OUTER_RADIUS = 0.535

const BOARD_EDGE_RADIUS = 0.535

const SECTOR_SCORES = [
	20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5
]
const SECTOR_ANGLE_DEGREES = 18.0 
const SECTOR_ANGLE_RADIANS = deg_to_rad(SECTOR_ANGLE_DEGREES)

var highlight_polygon: CSGPolygon3D

const LOG_TAG := "Dartboard"
var DEBUG_DARTBOARD := false

func dbg(msg: String) -> void:
	if DEBUG_DARTBOARD:
		OpLog.d(LOG_TAG, msg)

func _ready() -> void:
	highlight_polygon = get_node("HighlightPolygon")

	OpLog.d(LOG_TAG, [
		"dartboard_ready highlight_valid=", is_instance_valid(highlight_polygon)
	])

func set_replay_highlight(hit_pos: Vector2, score: int, multiplier: int) -> void:
	var distance_from_center = hit_pos.length()

	OpLog.event(LOG_TAG, [
		"set_replay_highlight hit_pos=", hit_pos,
		" score=", score,
		" multiplier=", multiplier,
		" distance=", distance_from_center
	])

	if score == 0:
		_update_highlight_visuals("miss", -1, -1, -1)
	elif score == 50:
		_update_highlight_visuals("bullseye", -1, -1, BULLSEYE_RADIUS)
	elif score == 25:
		_update_highlight_visuals("outer_bull", -1, BULLSEYE_RADIUS, OUTER_BULL_RADIUS)
	else:
		var sector_idx = SECTOR_SCORES.find(score)

		if sector_idx < 0:
			OpLog.w(LOG_TAG, [
				"replay_highlight_score_not_found score=", score,
				" multiplier=", multiplier
			])
			return

		if multiplier == 3:
			_update_highlight_visuals("sector", sector_idx, TRIPLE_RING_INNER_RADIUS, TRIPLE_RING_OUTER_RADIUS)
		elif multiplier == 2:
			_update_highlight_visuals("sector", sector_idx, DOUBLE_RING_INNER_RADIUS, DOUBLE_RING_OUTER_RADIUS)
		else:
			if distance_from_center <= TRIPLE_RING_INNER_RADIUS:
				_update_highlight_visuals("sector", sector_idx, OUTER_BULL_RADIUS, TRIPLE_RING_INNER_RADIUS)
			else:
				_update_highlight_visuals("sector", sector_idx, TRIPLE_RING_OUTER_RADIUS, DOUBLE_RING_INNER_RADIUS)

#Returns array [full_points, points, multiplier]
func get_score(hit_pos: Vector2) -> Array[int]:
	var distance_from_center = hit_pos.length()

	var final_score = 0
	var determined_sector_index = -1

	if distance_from_center <= BULLSEYE_RADIUS:
		_update_highlight_visuals("bullseye", -1, -1, BULLSEYE_RADIUS)
		OpLog.event(LOG_TAG, ["score_hit bullseye hit_pos=", hit_pos, " distance=", distance_from_center])
		return [50, 25, 2]

	if distance_from_center <= OUTER_BULL_RADIUS:
		_update_highlight_visuals("outer_bull", -1, BULLSEYE_RADIUS, OUTER_BULL_RADIUS)
		OpLog.event(LOG_TAG, ["score_hit outer_bull hit_pos=", hit_pos, " distance=", distance_from_center])
		return [25, 25, 0]

	if distance_from_center > BOARD_EDGE_RADIUS:
		_update_highlight_visuals("miss", -1, -1, -1)
		OpLog.event(LOG_TAG, ["score_hit miss hit_pos=", hit_pos, " distance=", distance_from_center])
		return [0, 0, 0]

	var hl_rad_in: float
	var hl_rad_out: float

	var multiplier = 0
	if distance_from_center >= TRIPLE_RING_INNER_RADIUS and distance_from_center <= TRIPLE_RING_OUTER_RADIUS:
		hl_rad_in = TRIPLE_RING_INNER_RADIUS
		hl_rad_out = TRIPLE_RING_OUTER_RADIUS
		multiplier = 3
	elif distance_from_center >= DOUBLE_RING_INNER_RADIUS and distance_from_center <= DOUBLE_RING_OUTER_RADIUS:
		hl_rad_in = DOUBLE_RING_INNER_RADIUS
		hl_rad_out = DOUBLE_RING_OUTER_RADIUS
		multiplier = 2
	else:
		if distance_from_center > OUTER_BULL_RADIUS and distance_from_center < TRIPLE_RING_INNER_RADIUS:
			hl_rad_in = OUTER_BULL_RADIUS
			hl_rad_out = TRIPLE_RING_INNER_RADIUS
		elif distance_from_center > TRIPLE_RING_OUTER_RADIUS and distance_from_center < DOUBLE_RING_INNER_RADIUS:
			hl_rad_in = TRIPLE_RING_OUTER_RADIUS
			hl_rad_out = DOUBLE_RING_INNER_RADIUS

	var angle_deg = rad_to_deg(hit_pos.angle())
	var normalized_angle_deg = fmod(angle_deg + 90.0 + (SECTOR_ANGLE_DEGREES / 2.0) + 360.0, 360.0)

	var sector_index = int(floor(normalized_angle_deg / SECTOR_ANGLE_DEGREES))
	if sector_index >= SECTOR_SCORES.size():
		sector_index = SECTOR_SCORES.size() - 1

	var base_score = SECTOR_SCORES[sector_index]

	_update_highlight_visuals("sector", sector_index, hl_rad_in, hl_rad_out)

	var full_score: int = base_score
	if multiplier > 0:
		full_score *= multiplier

	OpLog.event(LOG_TAG, [
		"score_hit sector hit_pos=", hit_pos,
		" distance=", distance_from_center,
		" angle=", normalized_angle_deg,
		" sector_index=", sector_index,
		" base_score=", base_score,
		" multiplier=", multiplier,
		" full_score=", full_score
	])

	return [full_score, base_score, multiplier]

func _update_highlight_visuals(hit_type: String, p_sector_index: int, p_radius_inner: float, p_radius_outer: float):
	highlight_polygon.polygon = []
	highlight_polygon.visible = false

	if hit_type == "sector":
		if p_sector_index < 0 or p_sector_index >= SECTOR_SCORES.size():
			OpLog.e(LOG_TAG, [
				"invalid_sector_index_for_highlight sector=", p_sector_index,
				" hit_type=", hit_type,
				" radius_inner=", p_radius_inner,
				" radius_outer=", p_radius_outer
			])
			return

		var points = PackedVector2Array()
		var num_arc_segments = 8 

		var angle_offset = (-PI / 2.0) - (SECTOR_ANGLE_RADIANS / 2.0)

		var sector_start_rad = angle_offset + (p_sector_index * SECTOR_ANGLE_RADIANS)
		var sector_end_rad = sector_start_rad + SECTOR_ANGLE_RADIANS

		for i in range(num_arc_segments + 1):
			var angle = sector_start_rad + (SECTOR_ANGLE_RADIANS * (float(i) / num_arc_segments))
			points.append(Vector2(cos(angle), sin(angle)) * p_radius_outer)

		for i in range(num_arc_segments, -1, -1):
			var angle = sector_start_rad + (SECTOR_ANGLE_RADIANS * (float(i) / num_arc_segments))
			points.append(Vector2(cos(angle), sin(angle)) * p_radius_inner)

		highlight_polygon.polygon = points
		highlight_polygon.visible = true
		
	elif hit_type == "bullseye": 
		var points = PackedVector2Array()
		var num_circle_segments = 32
		for i in range(num_circle_segments):
			var angle = (2.0 * PI * float(i)) / num_circle_segments
			points.append(Vector2(cos(angle), sin(angle)) * p_radius_outer)
		highlight_polygon.polygon = points
		highlight_polygon.visible = true
		
	elif hit_type == "outer_bull": 
		var points = PackedVector2Array()
		var num_circle_segments = 32

		for i in range(num_circle_segments + 1): 
			var angle = (2.0 * PI * float(i)) / num_circle_segments
			points.append(Vector2(cos(angle), sin(angle)) * p_radius_outer)

		for i in range(num_circle_segments, -1, -1): 
			var angle = (2.0 * PI * float(i)) / num_circle_segments
			points.append(Vector2(cos(angle), sin(angle)) * p_radius_inner) 
			
		highlight_polygon.polygon = points
		highlight_polygon.visible = true
	else:
		highlight_polygon.visible = false
		
