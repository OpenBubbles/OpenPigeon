extends RigidBody3D

var time: float = 0.0
var shot: bool = false
var finished: bool = false
var bb: basketball

func _ready() -> void:
	bb = get_parent()

func _process(delta: float) -> void:
	time += delta
	var this: RigidBody3D = get_node(".")
	if this.name != "Ball":
		if time > 1 and not shot:
			this.linear_velocity = Vector3(-0.5, 6.5, -2.5)
			shot = true
		if time > 1.25 and not finished:
			print("SPAWNING NEW BALL!!!! " + str(this))
			bb.spawnBall()
			finished = true
		
