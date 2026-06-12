extends Node3D
class_name Cups

const LOG_TAG := "Cups"
const DEBUG_CUPS := false

func dbg(parts: Variant) -> void:
	if DEBUG_CUPS:
		OpLog.d(LOG_TAG, parts)

var prev_cups: Array
var cups_in_play: Array = [0,1,2,3,4,5,6,7,8,9]
var random_positions: Dictionary = {}
var mirror_x: bool = false

func _ready():
	for cup in get_children():
		var mesh3d: CSGMesh3D = cup.get_child(0)
		mesh3d.mesh = mesh3d.mesh.duplicate()
		mesh3d.mesh.surface_set_material(0, mesh3d.mesh.surface_get_material(0).duplicate())

func reset_cups(cups: Array):
	dbg(["reset_cups name=", name, " cups=", cups])
	var all_cups = get_children()
	for cup_idx in range(len(all_cups)):
		all_cups[cup_idx].name = "cupremoved"
	for cup_idx in range(len(all_cups)):
		var cup_mesh: ArrayMesh = all_cups[cup_idx].get_child(0).mesh
		all_cups[cup_idx].name = "cup"+str(cup_idx+1)
		all_cups[cup_idx].visible = true
		all_cups[cup_idx].get_child(0).use_collision = true
		cup_mesh.surface_get_material(0).transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		cup_mesh.surface_get_material(0).albedo_color = Color(1, 1, 1, 1)
	cups_in_play = [0,1,2,3,4,5,6,7,8,9]
	set_cups_in_play(cups)

func apply_random_positions(positions: Array) -> void:
	random_positions.clear()
	for i in range(min(positions.size(), 10)):
		random_positions[i] = positions[i]
	dbg(["apply_random_positions name=", name, " count=", random_positions.size(), " mirrorX=", mirror_x])

func set_cups_in_play(cups: Array):
	dbg(["set_cups_in_play name=", name, " from=", cups_in_play, " to=", cups])
	for cup_idx in cups_in_play:
		if cup_idx not in cups:
			var cup = get_child(cup_idx)
			cup.visible = false
			cup.name = "cupremoved"
			cup.get_child(0).use_collision = false
	cups_in_play = cups

	if random_positions.size() > 0:
		_arrange_random()
	else:
		arrangeCups()

const CUP_REMOVE_LIFT_HEIGHT: float = 0.18
const CUP_REMOVE_LIFT_DURATION: float = 0.18
const CUP_REMOVE_SLIDE_DURATION: float = 0.22
const CUP_REMOVE_EXIT_X: float = 2.0

func remove_cup(cup_num: int):
	var cup: StaticBody3D = get_node("cup" + str(cup_num))
	cup.name = "cupremoved"
	cup.get_child(0).use_collision = false

	var start_pos: Vector3 = cup.position
	var exit_x_sign: float = 1.0 if start_pos.x >= 0.0 else -1.0
	var lifted_pos: Vector3 = start_pos + Vector3(0.0, CUP_REMOVE_LIFT_HEIGHT, 0.0)
	var exit_pos: Vector3 = Vector3(exit_x_sign * CUP_REMOVE_EXIT_X, lifted_pos.y, lifted_pos.z)

	var anim = get_tree().create_tween()
	anim.tween_property(cup, "position", lifted_pos, CUP_REMOVE_LIFT_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	anim.tween_property(cup, "position", exit_pos, CUP_REMOVE_SLIDE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	anim.tween_callback(func():
		if is_instance_valid(cup):
			cup.visible = false
	)
	anim.play()

	cups_in_play.remove_at(cups_in_play.find(cup_num-1))
	OpLog.i(LOG_TAG, ["remove_cup name=", name, " cup=", cup_num, " remaining=", cups_in_play])

	# In random mode don't rerack cups
	if random_positions.size() == 0:
		arrangeCups()

func _arrange_random() -> void:
	dbg(["arrange_random name=", name, " inPlay=", cups_in_play, " positions=", random_positions.size()])
	for cup_idx in cups_in_play:
		if not random_positions.has(cup_idx):
			continue
		var cup_node: Node = get_node_or_null("cup" + str(cup_idx + 1))
		if cup_node == null:
			cup_node = get_child(cup_idx)
		if cup_node == null:
			continue
		cup_node.position = random_positions[cup_idx]

func arrangeCups():
	var num_cups = len(cups_in_play)
	dbg(["arrange_cups name=", name, " count=", num_cups, " inPlay=", cups_in_play])
	
	var tween = get_tree().create_tween()
	tween.set_loops(1)
	for cup_idx in range(len(cups_in_play)):
		if num_cups == 6:
			var cup = get_node("cup"+str(cups_in_play[cup_idx]+1))
			cup.name = "cup"+str(cup_idx+1)
			if cup_idx == 0:
				tween.tween_property(cup, "position", Vector3(0.0, -0.597, -1.967), 0.1)
			elif cup_idx == 1:
				tween.tween_property(cup, "position", Vector3(-0.071, -0.597, -2.087), 0.1)
			elif cup_idx == 2:
				tween.tween_property(cup, "position", Vector3(0.071, -0.597, -2.087), 0.05)
			elif cup_idx == 3:
				tween.tween_property(cup, "position", Vector3(-0.142, -0.597, -2.207), 0.05)
			elif cup_idx == 4:
				tween.tween_property(cup, "position", Vector3(0.0, -0.597, -2.207), 0.05)
			elif cup_idx == 5:
				tween.tween_property(cup, "position", Vector3(0.142, -0.597, -2.207), 0.05)
		if num_cups == 3:
			var cup = get_node("cup"+str(cups_in_play[cup_idx]+1))
			cup.name = "cup"+str(cup_idx+1)
			if cup_idx == 0:
				tween.tween_property(cup, "position", Vector3(0, -0.597, -2.027), 0.05)
			elif cup_idx == 1:
				tween.tween_property(cup, "position", Vector3(-0.071, -0.597, -2.147), 0.05)
			elif cup_idx == 2:
				tween.tween_property(cup, "position", Vector3(0.071, -0.597, -2.147), 0.05)
	tween.play()
	
	if num_cups == 6:
		cups_in_play = [0,1,2,3,4,5]
	elif num_cups == 3:
		cups_in_play = [0,1,2]
