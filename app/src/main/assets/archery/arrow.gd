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

	# Only do the "fly behind board on miss" logic if we have a valid target
	if is_instance_valid(target):
		if (pos.x < -0.9 or pos.x > 0.9) or (pos.y < 0.45 or pos.y > 2.26):
			pos.z = target.position.z + MISS_Z_OFFSET

	var _tween = create_tween()
	_tween.set_parallel()
	_tween.set_loops(1)
	_tween.tween_property(self, "rotation:x", 0, 0.5)
	_tween.tween_property(self, "position", pos, 0.5)
	_tween.connect("finished", func() -> void:
		callback.call()
		if is_instance_valid(target) and is_equal_approx(pos.z, target.position.z + MISS_Z_OFFSET):
			queue_free()
	)
