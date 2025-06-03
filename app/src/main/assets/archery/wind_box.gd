extends Panel

@export var camera3d: Camera3D
@export var target: Target

func _process(delta: float) -> void:
	pass
	#self.position = camera3d.unproject_position(target.global_position) + Vector2(-100, -100)
	#if camera3d.position.z < 1.615:
		#self.visible = false
	#else:
		#self.visible = true
