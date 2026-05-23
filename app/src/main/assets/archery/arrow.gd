extends Node3D
class_name Arrow

@export var target: MeshInstance3D

const MISS_Z_OFFSET: float = -10.0

func spawn() -> Arrow:
	var new_arrow: Arrow = duplicate() as Arrow
	new_arrow.position = Vector3(0.086, 1.586, 1.373)
	new_arrow.visible = true
	# Copy rotation so all arrows start the same way
	new_arrow.rotation = rotation
	get_parent().add_child(new_arrow)
	return new_arrow
	

func shoot(pos: Vector3, callback: Callable) -> void:
	print("shot at " + str(pos))

	var missed_target := false

	if is_instance_valid(target):
		if (pos.x < -0.9 or pos.x > 0.9) or (pos.y < 0.45 or pos.y > 2.26):
			pos.z = target.position.z + MISS_Z_OFFSET
			missed_target = true

	var visual_root := get_node_or_null("VisualSpinRoot") as Node3D
	if visual_root == null:
		visual_root = Node3D.new()
		visual_root.name = "VisualSpinRoot"
		add_child(visual_root)

		for child in get_children():
			if child == visual_root:
				continue
			if child is Node3D:
				child.reparent(visual_root, true)

	var spin_start := visual_root.rotation.x

	var fly_tween = create_tween()
	fly_tween.set_parallel()
	fly_tween.set_loops(1)
	fly_tween.tween_property(self, "rotation:x", 0, 0.5)
	fly_tween.tween_property(visual_root, "rotation:x", spin_start + TAU * 0.75, 0.5).set_trans(Tween.TRANS_LINEAR)
	fly_tween.tween_property(self, "position", pos, 0.5)
	fly_tween.connect("finished", func() -> void:
		callback.call()

		if missed_target:
			queue_free()
			return

		var base_rot := visual_root.rotation
		var wiggle = create_tween()
		wiggle.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		wiggle.tween_property(visual_root, "rotation:y", base_rot.y + 0.08, 0.05)
		wiggle.tween_property(visual_root, "rotation:y", base_rot.y - 0.06, 0.06)
		wiggle.tween_property(visual_root, "rotation:y", base_rot.y + 0.035, 0.06)
		wiggle.tween_property(visual_root, "rotation:y", base_rot.y - 0.015, 0.06)
		wiggle.tween_property(visual_root, "rotation:y", base_rot.y, 0.08)
	)
