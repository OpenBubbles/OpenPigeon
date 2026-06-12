extends RigidBody3D
class_name BasketballBall

const LOG_TAG := "BasketballBall"
const DEBUG_BASKETBALL_BALL := false

func dbg(parts: Variant) -> void:
	if DEBUG_BASKETBALL_BALL:
		OpLog.d(LOG_TAG, parts)

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
			dbg(["upper_hoop_contact player=", player, " pos=", position, " vel=", linear_velocity, " replay=", str(didGoInReplay)])
		elif "HoopCollisionSphere" in node.name:
			self.physics_material_override.bounce = 0.6
			self.linear_velocity = Vector3(0.0, -2.5, 0)
			if didGoIn == false and (didGoInReplay == null or didGoInReplay == true):
				OpLog.i(LOG_TAG, [
					"hoop_score_contact player=", player,
					" shotAt=", shotAt,
					" shotX=", shotX,
					" pos=", position,
					" vel=", linear_velocity,
					" replay=", str(didGoInReplay)
				])
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
	var x_force: float = self.position.x + shotX
	var raw_x_force: float = x_force
	
	if player != BasketballGame.player:
		x_force *= -1
		
	OpLog.i(LOG_TAG, [
		"shoot player=", player,
		" localPlayer=", BasketballGame.player,
		" shotAt=", shotAt,
		" shotX=", shotX,
		" rawXForce=", raw_x_force,
		" finalXForce=", x_force,
		" pos=", position
	])

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
	# failsafe in case one misses for some reason
	if didGoInReplay == true and didGoIn == false:
		OpLog.w(LOG_TAG, [
			"despawn_replay_score_failsafe player=", player,
			" shotAt=", shotAt,
			" shotX=", shotX,
			" pos=", position
		])
		BasketballGame.incrementScore(player)
		
	if didGoInReplay == null:
		var replay_entry := str(int(shotAt * 60.0)) + "," + str("%0.3f" % shotX) + ",0," + str(1 if didGoIn else 0)
		OpLog.i(LOG_TAG, [
			"shot_finished player=", player,
			" replayEntry=", replay_entry,
			" didHitHoop=", didHitHoop,
			" didGoIn=", didGoIn
		])
		BasketballGame.myReplay += replay_entry + "|"
	else:
		dbg(["replay_ball_despawn player=", player, " didGoIn=", didGoIn, " expected=", didGoInReplay])
	queue_free()
		
