extends RigidBody3D
class_name BasketballBall

const LOG_TAG := "BasketballBall"
const DEBUG_BASKETBALL_BALL := false
const SHOT_Y_VELOCITY := 6.5
const SHOT_Z_VELOCITY := -2.499991
const REPLAY_STEP_SECONDS := 0.01666
const REPLAY_GRAVITY_PER_STEP := 0.163268
const REPLAY_PRE_SIM_STEPS := 52
const LIVE_BALL_LIFETIME_SECONDS := 2.5
const REPLAY_BALL_LIFETIME_SECONDS := 5.52

var didGoInReplay = null
var player = null
var shotAt := 0.0
var shotX := 0.0
var didHitHoop := false
var didGoIn := false
var BasketballGame: basketball
var replay_manual_simulating := false
var replay_manual_steps := 0
var replay_velocity := Vector3.ZERO

func dbg(parts: Variant) -> void:
	if DEBUG_BASKETBALL_BALL:
		OpLog.d(
			LOG_TAG,
			parts,
		)

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 10

	BasketballGame = get_parent()

	can_sleep = false
	sleeping = false

	if not body_entered.is_connected(
		_on_body_entered,
	):
		body_entered.connect(
			_on_body_entered,
		)

func _process(
	_delta: float,
) -> void:
	if (
		name != "Ball" and
		BasketballGame.replayPlaying == false and
		BasketballGame.replayFinished == true
	):
		queue_free()

func _on_body_entered(
	body: Node,
) -> void:
	var body_name := String(
		body.name,
	)

	if not body_name.begins_with(
		"HoopCollisionSphere",
	):
		return

	var sphere_number := int(
		body_name.trim_prefix(
			"HoopCollisionSphere",
		),
	)

	if (
		sphere_number <
			basketball.FIRST_REAL_RIM_SPHERE or
		sphere_number >
			basketball.LAST_REAL_RIM_SPHERE
	):
		return

	didHitHoop = true

	OpLog.i(
		LOG_TAG,
		[
			"rim_contact body=",
			body_name,
			" sphere=",
			sphere_number,
			" pos=",
			global_position,
			" velocity=",
			linear_velocity,
			" didGoIn=",
			didGoIn,
		],
	)

func set_player(
	player_num: int,
) -> void:
	player = player_num

func set_didGoInReplay(
	value: bool,
) -> void:
	didGoInReplay = value

func shoot(
	target_x: float,
) -> void:
	shotAt = BasketballGame.elapsedTime

	shotX = BasketballGame.get_saved_replay_x(
		target_x,
	)

	var x_velocity := (
		target_x -
		position.x
	)

	OpLog.i(
		LOG_TAG,
		[
			"shoot player=",
			player,
			" targetX=",
			target_x,
			" savedReplayX=",
			shotX,
			" velocityX=",
			x_velocity,
			" pos=",
			position,
		],
	)

	_start_dynamic_shot(
		Vector3(
			x_velocity,
			SHOT_Y_VELOCITY,
			SHOT_Z_VELOCITY,
		),
		true,
	)

	_start_despawn_timer(
		LIVE_BALL_LIFETIME_SECONDS,
	)

func shoot_recovery(target_x: float, saved_shot_at: float, saved_replay_x: float) -> void:
	shotAt = saved_shot_at
	shotX = saved_replay_x
	didGoInReplay = null
	didGoIn = false
	didHitHoop = false
	var x_velocity := target_x - position.x
	_start_dynamic_shot(Vector3(x_velocity, SHOT_Y_VELOCITY, SHOT_Z_VELOCITY), true)
	_start_despawn_timer(LIVE_BALL_LIFETIME_SECONDS)
	OpLog.i(LOG_TAG, ["recovery_shot player=", player, " targetX=", target_x, " shotAt=", shotAt, " savedReplayX=", shotX, " velocityX=", x_velocity])

func begin_replay_shot(
	x_velocity: float,
	saved_replay_x: float,
	expected_score: bool,
	manual_pre_simulation: bool,
) -> void:
	shotAt = BasketballGame.elapsedTime
	shotX = saved_replay_x

	didGoInReplay = expected_score
	didGoIn = false
	didHitHoop = false

	var launch_velocity := Vector3(
		x_velocity,
		SHOT_Y_VELOCITY,
		SHOT_Z_VELOCITY,
	)

	if manual_pre_simulation:
		replay_manual_simulating = true
		replay_manual_steps = 0
		replay_velocity = launch_velocity

		axis_lock_angular_x = true
		axis_lock_angular_y = true
		axis_lock_angular_z = true

		angular_velocity = Vector3.ZERO
		linear_velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0

		freeze = true
		sleeping = false
	else:
		_start_dynamic_shot(
			launch_velocity,
			true,
		)

	_start_despawn_timer(
		REPLAY_BALL_LIFETIME_SECONDS,
	)

	OpLog.i(
		LOG_TAG,
		[
			"replay_shot player=",
			player,
			" expected=",
			expected_score,
			" savedReplayX=",
			saved_replay_x,
			" velocity=",
			launch_velocity,
			" manual=",
			manual_pre_simulation,
			" pos=",
			position,
		],
	)

func step_replay_pre_simulation() -> void:
	if not replay_manual_simulating:
		return

	if replay_manual_steps >= REPLAY_PRE_SIM_STEPS:
		_finish_replay_pre_simulation()
		return

	replay_velocity.y -= REPLAY_GRAVITY_PER_STEP

	position += (
		replay_velocity *
		REPLAY_STEP_SECONDS
	)

	replay_manual_steps += 1

func _finish_replay_pre_simulation() -> void:
	replay_manual_simulating = false

	collision_layer = int(
		player,
	)

	collision_mask = int(
		player,
	)

	axis_lock_angular_x = false
	axis_lock_angular_y = false
	axis_lock_angular_z = false

	freeze = false
	sleeping = false

	linear_velocity = replay_velocity
	angular_velocity = Vector3.ZERO

	OpLog.i(
		LOG_TAG,
		[
			"replay_sim_finished player=",
			player,
			" steps=",
			replay_manual_steps,
			" pos=",
			position,
			" velocity=",
			linear_velocity,
		],
	)

func _start_dynamic_shot(
	launch_velocity: Vector3,
	apply_rotation: bool,
) -> void:
	replay_manual_simulating = false
	replay_manual_steps = 0
	replay_velocity = Vector3.ZERO

	collision_layer = int(
		player,
	)

	collision_mask = int(
		player,
	)

	axis_lock_angular_x = false
	axis_lock_angular_y = false
	axis_lock_angular_z = false

	freeze = false
	sleeping = false

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	apply_impulse(
		launch_velocity,
	)

	if apply_rotation:
		apply_torque_impulse(
			Vector3(
				-0.02,
				0.0,
				0.0,
			),
		)

func _start_despawn_timer(
	wait_seconds: float,
) -> void:
	if has_meta(
		"despawn_timer_started",
	):
		return

	set_meta(
		"despawn_timer_started",
		true,
	)

	var timer := Timer.new()

	add_child(
		timer,
	)

	timer.one_shot = true
	timer.wait_time = wait_seconds

	timer.timeout.connect(
		despawn,
	)

	timer.start()

func despawn() -> void:
	if didGoInReplay == null:
		var replay_entry := (
			str(
				int(
					shotAt *
					60.0,
				),
			) +
			"," +
			str(
				"%0.3f" %
					shotX,
			) +
			",0," +
			str(
				1
					if didGoIn
					else 0,
			)
		)

		OpLog.i(
			LOG_TAG,
			[
				"shot_finished player=",
				player,
				" replayEntry=",
				replay_entry,
				" didHitHoop=",
				didHitHoop,
				" didGoIn=",
				didGoIn,
			],
		)

		if not BasketballGame.myReplay.is_empty():
			BasketballGame.myReplay += "|"

		BasketballGame.myReplay += replay_entry
		BasketballGame.mark_basketball_shot_finished(int(get_meta("shot_num", 0)), didGoIn)
	else:
		dbg(
			[
				"replay_ball_despawn player=",
				player,
				" didGoIn=",
				didGoIn,
				" expected=",
				didGoInReplay,
			],
		)

	if (
		BasketballGame.currentBall.get(
			player,
		) ==
		self
	):
		BasketballGame.currentBall[player] = null

	queue_free()
