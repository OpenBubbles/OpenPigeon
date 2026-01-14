extends RigidBody3D
class_name BasketballBall

var didGoInReplay = null

var player = null
var shotAt = 0.0
var shotX = 0.0
var didHitHoop = false
var didGoIn = false
var BasketballGame: basketball

func _ready() -> void:
	self.contact_monitor = true
	self.max_contacts_reported = 10
	self.BasketballGame = get_parent()
	
	self.can_sleep = false
	self.sleeping = false

func _process(delta: float) -> void:
	if self.name != "Ball" and self.BasketballGame.replayPlaying == false and self.BasketballGame.replayFinished == true:
		queue_free()
	
func _physics_process(delta: float) -> void:
	for node in get_colliding_bodies():
		if "HoopCollisionSphere" in node.name and node.position.y >= 0.95:
			self.physics_material_override.bounce = 0.2
			var x_nudge = 0
			if didGoInReplay:
				if self.position.x > 0:
					x_nudge = -1.5
				elif self.position.x < 0:
					x_nudge = 1.5
			
				self.linear_velocity = Vector3(x_nudge, -2.5, 0)
			didHitHoop = true
		elif "HoopCollisionSphere" in node.name:
			self.physics_material_override.bounce = 0.6
			self.linear_velocity = Vector3(0.0, -2.5, 0)
			if didGoIn == false and (didGoInReplay == null or didGoInReplay == true):
				BasketballGame.incrementScore(player)
			didHitHoop = true
			didGoIn = true

func set_player(player_num: int):
	player = player_num

func set_didGoInReplay(val: bool):
	didGoInReplay = val

func shoot(x_delta: float) -> void:
	shotAt = BasketballGame.elapsedTime
	shotX = x_delta
	var x_force = self.position.x + shotX
	
	if player != BasketballGame.player:
		x_force *= -1

	self.axis_lock_angular_x = false
	self.axis_lock_angular_y = false
	self.axis_lock_angular_z = false

	self.freeze = false
	self.sleeping = false
	self.linear_velocity = Vector3.ZERO
	self.angular_velocity = Vector3.ZERO

	self.apply_impulse(Vector3(x_force, 6.80, -2.5))
	self.apply_torque_impulse(Vector3(-0.02, 0, 0))
	
	var timer = Timer.new()
	self.add_child(timer)
	timer.timeout.connect(despawn)
	timer.set_wait_time(2.5)
	timer.start()

func despawn() -> void:
	#failsafe in case one misses for some reason
	if didGoInReplay == true and didGoIn == false:
		BasketballGame.incrementScore(player)
		
	if didGoInReplay == null:
		BasketballGame.myReplay += str(int(shotAt * 60.0)) + "," + str("%0.3f" % shotX) + ",0," + str(1 if didGoIn else 0) + "|"
	queue_free()
		
