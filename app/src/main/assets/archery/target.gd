extends MeshInstance3D
class_name Target

const BASE_RADIUS = 0.0808
const BASE_RADIUS_HIGHLIGHT = 0.079
const NUM_SEGMENTS = 10

const LOG_TAG := "Target"
const DEBUG_TARGET := false

func dbg(parts: Variant) -> void:
	if DEBUG_TARGET:
		OpLog.d(LOG_TAG, parts)

@export var highlight_outer: CSGCylinder3D
@export var highlight_inner: CSGCylinder3D

func calc_score(arrow: Arrow) -> int:
	dbg(["calc_score globalArrowPos=", arrow.position])
	var arrow_hit_position = self.to_local(arrow.position)
	arrow_hit_position.z = 0
	
	var distance = arrow_hit_position.length()
	var hit_segment = -1 

	dbg(["calc_score localHit=", arrow_hit_position, " distance=", distance])

	if distance == 0.0:
		hit_segment = 1 
	else:
		var calculated_segment = int(ceil(distance / BASE_RADIUS))
		if calculated_segment <= NUM_SEGMENTS:
			hit_segment = calculated_segment
		else:
			hit_segment = -1
			
	if hit_segment != -1:
		OpLog.i(LOG_TAG, [
			"score_hit segment=", hit_segment,
			" score=", 11 - hit_segment,
			" localHit=", arrow_hit_position,
			" distance=", distance
		])
	else:
		OpLog.i(LOG_TAG, ["score_miss localHit=", arrow_hit_position, " distance=", distance])
		return 0
		
	update_highlight_ring(hit_segment)
		
	return 11 - hit_segment
	
	
func update_highlight_ring(segment_id: int):
	highlight_outer.visible = false
	highlight_inner.visible = false
	highlight_inner.radius = 0.0001
	
	if segment_id < 1 or segment_id > NUM_SEGMENTS:
		dbg(["highlight skipped invalid segment=", segment_id])
		return
	
	var outer_radius = float(segment_id) * BASE_RADIUS_HIGHLIGHT
	var inner_radius = float(segment_id - 1) * BASE_RADIUS_HIGHLIGHT
	
	highlight_outer.radius = outer_radius
	
	if inner_radius > 0.0001:
		highlight_inner.radius = inner_radius
	
	highlight_inner.visible = true
	highlight_outer.visible = true
	
