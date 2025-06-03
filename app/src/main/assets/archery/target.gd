extends MeshInstance3D
class_name Target

const BASE_RADIUS = 0.0808
const BASE_RADIUS_HIGHLIGHT = 0.079
const NUM_SEGMENTS = 10

@export var highlight_outer: CSGCylinder3D
@export var highlight_inner: CSGCylinder3D

func calc_score(arrow: Arrow) -> int:
	print("global arrow hit position: " + str(arrow.position))
	var arrow_hit_position = self.to_local(arrow.position)
	arrow_hit_position.z = 0
	
	var distance = arrow_hit_position.length()
	var hit_segment = -1 

	print("arrow_hit_position: ", arrow_hit_position)
	print("arrow distance: ", distance)

	if distance == 0.0:
		hit_segment = 1 
	else:
		var calculated_segment = int(ceil(distance / BASE_RADIUS))
		if calculated_segment <= NUM_SEGMENTS:
			hit_segment = calculated_segment
		else:
			hit_segment = -1
			
	if hit_segment != -1:
		print("Arrow hit segment: ", hit_segment)
	else:
		print("Arrow missed the target.")
		return 0
		
	update_highlight_ring(hit_segment)
		
	return 11 - hit_segment
	
	
func update_highlight_ring(segment_id: int):
	highlight_outer.visible = false
	highlight_inner.visible = false
	highlight_inner.radius = 0.0001
	
	if segment_id < 1 or segment_id > NUM_SEGMENTS:
		print("No valid segment to highlight or missed.")
		return
	
	var outer_radius = float(segment_id) * BASE_RADIUS_HIGHLIGHT
	var inner_radius = float(segment_id - 1) * BASE_RADIUS_HIGHLIGHT
	
	highlight_outer.radius = outer_radius
	
	if inner_radius > 0.0001:
		highlight_inner.radius = inner_radius
	
	highlight_inner.visible = true
	highlight_outer.visible = true
	
