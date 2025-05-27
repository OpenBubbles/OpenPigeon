extends Node3D
class_name Cups

var prev_cups: Array
var cups_in_play: Array = [0,1,2,3,4,5,6,7,8,9]
	
func _ready():
	for cup in get_children():
		var mesh3d: CSGMesh3D = cup.get_child(0)
		mesh3d.mesh = mesh3d.mesh.duplicate()
		mesh3d.mesh.surface_set_material(0, mesh3d.mesh.surface_get_material(0).duplicate())
	
func reset_cups(cups: Array):
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
	
func set_cups_in_play(cups: Array):
	for cup_idx in cups_in_play:
		if cup_idx not in cups:
			var cup = get_child(cup_idx)
			cup.visible = false
			cup.name = "cupremoved"
			cup.get_child(0).use_collision = false
	cups_in_play = cups
	arrangeCups()
	
func remove_cup(cup_num: int):
	var cup: StaticBody3D = get_node("cup" + str(cup_num))
	cup.name = "cupremoved"
	var cup_mesh: ArrayMesh = cup.get_child(0).mesh
	cup_mesh.surface_get_material(0).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	cup.get_child(0).use_collision = false
	var fade_out = get_tree().create_tween()
	fade_out.tween_property(cup_mesh.surface_get_material(0), "albedo_color", Color(1, 1, 1, 0), 0.25).set_trans(Tween.TRANS_SINE)
	fade_out.set_loops(1)
	fade_out.play()
	cups_in_play.remove_at(cups_in_play.find(cup_num-1))
	arrangeCups()
	print(cups_in_play)
	
func arrangeCups():
	var num_cups = len(cups_in_play)
	
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
