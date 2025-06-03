extends Node3D
class_name Arrow

@export var target: Target

func spawn() -> Arrow:
	var new_arrow: Arrow = self.duplicate()
	new_arrow.position = Vector3(0.086, 1.586, 1.373)
	new_arrow.visible = true
	get_parent().add_child(new_arrow)
	return new_arrow
	
func shoot(pos: Vector3, callback: Callable) -> void:
	print("shot at " + str(pos))
	if (pos.x < -0.9 or pos.x > 0.9) or (pos.y < 0.45 or pos.y > 2.26):
		pos.z = target.position.z - 10
	
	var _tween = create_tween()
	_tween.set_parallel()
	_tween.set_loops(1)
	_tween.tween_property(self, "rotation:x", 0, 0.5)
	_tween.tween_property(self, "position", pos, 0.5)
	_tween.connect("finished", func():
		callback.call()
		if pos.z == (target.position.z - 10):
			self.queue_free()
	)
