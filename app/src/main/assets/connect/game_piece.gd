extends RigidBody2D
class_name ConnectPiece

func _integrate_forces(state):
	state.linear_velocity.x = 0
	state.angular_velocity = 0
