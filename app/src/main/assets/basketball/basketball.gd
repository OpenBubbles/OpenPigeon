extends BaseGame3D
class_name basketball

var elapsedTime: float = 0.0

const MUSIC_STREAM := preload("res://global/audio/basketball.ogg")
const MIN_DRAG_DISTANCE := 30.0

const LOG_TAG := "Basketball"
const DEBUG_BASKETBALL := false

func dbg(parts: Variant) -> void:
	if DEBUG_BASKETBALL:
		OpLog.d(LOG_TAG, parts)

func _replay_shot_count(value) -> int:
	if isNullOrEmpty(value):
		return 0
	return String(value).split("|", false).size()

func _score_summary() -> String:
	return "my=%d opp=%d score1=%s score2=%s skip1=%s skip2=%s" % [
		myScore,
		oppScore,
		str(score1),
		str(score2),
		str(skip_score1),
		str(skip_score2)
	]

@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var winner_label: Label = %WinLossLabel
@onready var sent_label: Label = %SentLabel
@onready var spectator_label: Label = %SpecLabel
@onready var start_button: Button = %StartButton
@onready var skip_button: TextureButton = %SkipButton
@onready var round_container: PanelContainer = %RoundUI
@onready var round_label: Label = %RoundLabel

@onready var static_backboard: MeshInstance3D = %backboard
@onready var static_hoop_collision: Node3D = %hoop_collision
@onready var static_net: MeshInstance3D = %net
@onready var static_pole: Node3D = %pole

@onready var moving_hoop_root: Node3D = %MovingHoopRoot
@onready var moving_backboard: Node3D = %backboard_moving
@onready var moving_hoop_collision: Node3D = %hoop_collision_moving
@onready var moving_net: Node3D = %net_moving
@onready var moving_pole: Node3D = %pole_moving

var hoop_time: int = 0
var _hoop_acc: float = 0.0
var hoop_center_tween: Tween

const SCORE_RADIUS_X := 0.32
const SCORE_RADIUS_Z := 0.26
const SCORE_MIN_DOWN_VELOCITY := -0.05
const SCORE_DUPLICATE_LOCK_MS := 300

var replayTimers: Array[Timer] = []
var replayEndTimer: Timer = null
var replayPlaying = false
var replayFinished = false
var gamePlaying = false
var gameDataSet = false
var game_over = false
var _ui_initialized := false
var sent_tween: Tween
var allow_waiting_from_loaded_data: bool = false
var loaded_has_winner: bool = false
var winner_sent: bool = false
var _loaded_replay_key: String = ""
var _score_run_id: int = 0
var _scored_shot_keys: Dictionary = {}
var _last_score_msec_by_player: Dictionary = {}

var replay = null
var replay2 = null
var replay3 = null
var replay4 = null
var isTurn = null
var player = null
var game_seed = null
var seed2 = null
var score1 = null
var score2 = null
var skip_score1 = null
var skip_score2 = null
var turnNum = null

var has_connected = false
var dev_data = ""
var game_mode: String = "n"

var youScoreLabel: Label3D
var oppScoreLabel: Label3D
var timeRemainingLabel: Label3D

var currentBall = {1: null, 2: null}
var ballNum = {1: 1, 2: 1}

var oppScore = 0
var myScore = 0
var myReplay = ""

var isWaiting = false
var receivedMessage = null
var drag_start_pos: Vector2 = Vector2.ZERO
var dragging: bool = false
var my_player: Variant = null

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM

func _get_dev_data() -> String:
	return '{"isYourTurn": true, "myPlayerId": "9a6e234c-2244-4621-a08f-38acd277a2e0", "skip_score1": "18", "skip_score2": "46", "player": "2", "score1": "18", "score2": "23", "sender": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb", "avatar2": "body,3|eyes,6|mouth,3|acc,0|wins,0|bg_color,0.933333,0.407843,0.647059|body_color,0.968627,0.811765,0.333333|glasses,0|stache,0|backdrop,0|hair,0|clothes,2|hair_color,0.505882,0.725490,0.254902|clothes_color,0.686657,0.686657,0.686657", "player2": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb", "id": "G4m1HA79uZDuAtHY", "ios": "26.1", "num": "1", "game": "basketball", "mode": "h", "seed": "-1417153476", "tver": "5", "build": "28R", "round": "1", "seed2": "-16614620", "start": "", "version": "5", "caption": "Lets play Basketball!", "game_name": "Basketball", "replay": "60,0.264,0,0"}'

func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	if not _ui_initialized:
		_ui_initialized = true

		timeRemainingLabel = get_node("Scoreboard/Time")
		youScoreLabel = get_node("Scoreboard/YouScore")
		oppScoreLabel = get_node("Scoreboard/OppScore")

		if is_instance_valid(start_button):
			start_button.pressed.connect(start_button_pressed)
		if is_instance_valid(skip_button):
			skip_button.pressed.connect(skipReplay)
			
	OpLog.i(LOG_TAG, [
		"game_ready localMode=", appPlugin == null,
		" dataSet=", gameDataSet,
		" mode=", game_mode,
		" player=", str(player),
		" turn=", str(isTurn)
	])

	if not gameDataSet:
		return

	refresh_ui_state()

func showWinner():
	if myScore == oppScore:
		winner_label.set_text("DRAW!")
		GameUtils._show_win_burst(player_avatar_display)
		GameUtils._show_win_burst(opp_avatar_display)
	elif myScore > oppScore:
		if spectator_mode:
			winner_label.set_text("PLAYER 1 WINS!")
		else:
			winner_label.set_text("YOU WIN!")
		winner_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		GameUtils._show_win_burst(player_avatar_display)
	else:
		if spectator_mode:
			winner_label.set_text("PLAYER 2 WINS!")
		else:
			winner_label.set_text("YOU LOSE!")
		winner_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
		GameUtils._show_win_burst(opp_avatar_display)
	winner_label.visible = true

func _set_collision_shapes_enabled(root: Node, enabled: bool) -> void:
	if not is_instance_valid(root):
		return

	for child in root.get_children():
		if child is CollisionShape3D:
			child.disabled = not enabled
		_set_collision_shapes_enabled(child, enabled)

func _set_collision_debug_meshes_visible(
	root: Node,
	visible_value: bool,
) -> void:
	if not is_instance_valid(root):
		return

	for child in root.get_children():
		if child is CSGSphere3D:
			child.visible = visible_value

		_set_collision_debug_meshes_visible(
			child,
			visible_value,
		)

func _set_moving_hoop_x(x_pos: float) -> void:
	if not is_instance_valid(moving_hoop_root):
		return

	moving_hoop_root.position.x = x_pos
	moving_hoop_root.force_update_transform()

func _apply_basketball_mode() -> void:
	var hard_mode := game_mode == "h"

	static_backboard.visible = not hard_mode
	static_hoop_collision.visible = not hard_mode
	static_net.visible = not hard_mode
	static_pole.visible = not hard_mode

	moving_hoop_root.visible = hard_mode
	moving_backboard.visible = hard_mode
	moving_hoop_collision.visible = hard_mode
	moving_net.visible = hard_mode
	moving_pole.visible = hard_mode

	# Collision geometry must never be rendered.
	_set_collision_debug_meshes_visible(
		static_hoop_collision,
		false,
	)

	_set_collision_debug_meshes_visible(
		moving_hoop_collision,
		false,
	)

	if not hard_mode:
		hoop_time = 0
		_hoop_acc = 0.0

		if hoop_center_tween and hoop_center_tween.is_running():
			hoop_center_tween.kill()

		if is_instance_valid(moving_hoop_root):
			_set_moving_hoop_x(
				0.0,
			)

	_set_collision_shapes_enabled(
		static_hoop_collision,
		not hard_mode,
	)

	_set_collision_shapes_enabled(
		static_backboard,
		not hard_mode,
	)

	_set_collision_shapes_enabled(
		moving_hoop_collision,
		hard_mode,
	)

	_set_collision_shapes_enabled(
		moving_backboard,
		hard_mode,
	)

func _input(
	event: InputEvent,
) -> void:
	if spectator_mode:
		return

	var mouse_event: InputEventMouseButton = (
		event as InputEventMouseButton
	)

	if mouse_event == null:
		return

	if player == null or not gamePlaying:
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var local_player_num: int = int(
		player,
	)

	var active_ball: BasketballBall = (
		currentBall.get(
			local_player_num,
		) as BasketballBall
	)

	if not is_instance_valid(active_ball):
		return

	if mouse_event.pressed:
		var camera: Camera3D = (
			get_viewport().get_camera_3d()
		)

		if camera == null:
			return

		var ball_screen_pos: Vector2 = (
			camera.unproject_position(
				active_ball.global_position,
			)
		)

		var touch_distance: float = (
			mouse_event.position.distance_to(
				ball_screen_pos,
			)
		)

		if touch_distance > 120.0:
			return

		dbg(
			[
				"drag_start pos=",
				mouse_event.position,
				" player=",
				local_player_num,
				" ball=",
				active_ball.name,
			],
		)

		drag_start_pos = mouse_event.position
		dragging = true
		return

	if not dragging:
		return

	var drag_end_pos: Vector2 = (
		mouse_event.position
	)

	var drag_delta: Vector2 = (
		drag_end_pos -
		drag_start_pos
	)

	var drag_distance: float = (
		drag_delta.length()
	)

	dragging = false

	if drag_distance < MIN_DRAG_DISTANCE:
		dbg(
			[
				"drag_cancelled len=",
				drag_distance,
			],
		)

		return

	var interpolation_amount: float = inverse_lerp(
		-200.0,
		200.0,
		drag_delta.x,
	)

	var x_delta_lerp: float = lerpf(
		-1.0,
		1.0,
		interpolation_amount,
	)

	var shot_number: int = (
		int(
			ballNum.get(
				local_player_num,
				1,
			),
		) -
		1
	)

	OpLog.i(
		LOG_TAG,
		[
			"shot_release player=",
			local_player_num,
			" drag=",
			drag_delta,
			" dragLen=",
			drag_distance,
			" xDelta=",
			x_delta_lerp,
			" elapsed=",
			elapsedTime,
			" shotNum=",
			shot_number,
		],
	)

	active_ball.shoot(
		x_delta_lerp,
	)

	if (
		currentBall.get(
			local_player_num,
		) ==
		active_ball
	):
		currentBall[local_player_num] = null

	await get_tree().create_timer(
		0.25,
	).timeout

	if (
		gamePlaying and
		player != null and
		int(player) == local_player_num
	):
		spawnBall(
			local_player_num,
		)

func playReplay(
	player_num: int,
	replay_str: String,
) -> float:
	replayPlaying = true

	var parsed_shots: Array[Dictionary] = []

	for raw_shot in replay_str.split(
		"|",
		false,
	):
		var shot_text := String(
			raw_shot,
		).strip_edges()

		if shot_text.is_empty():
			continue

		var shot_parts := shot_text.split(
			",",
			false,
		)

		if shot_parts.size() < 4:
			OpLog.w(
				LOG_TAG,
				[
					"play_replay malformed shot=",
					shot_text,
				],
			)

			continue

		parsed_shots.append(
			{
				"time": maxf(
					float(int(shot_parts[0])) / 60.0,
					0.0,
				),
				"x_delta": float(shot_parts[1]),
				"did_go_in": int(shot_parts[3]) != 0,
			},
		)

	OpLog.i(
		LOG_TAG,
		[
			"play_replay_start player=",
			player_num,
			" shots=",
			parsed_shots.size(),
			" raw=",
			replay_str,
		],
	)

	if parsed_shots.is_empty():
		return 0.0

	var first_result := bool(
		parsed_shots[0]["did_go_in"],
	)

	var first_ball: BasketballBall = currentBall.get(
		player_num,
	)

	if is_instance_valid(first_ball):
		first_ball.set_didGoInReplay(
			first_result,
		)
	else:
		spawnBall(
			player_num,
			first_result,
		)

	var last_time_delay := 0.0

	for shot_index in range(
		parsed_shots.size(),
	):
		var shot_data: Dictionary = parsed_shots[shot_index]

		var scheduled_player := player_num
		var scheduled_time := float(
			shot_data["time"],
		)
		var scheduled_x := float(
			shot_data["x_delta"],
		)

		last_time_delay = maxf(
			last_time_delay,
			scheduled_time,
		)

		var shot_timer := Timer.new()

		replayTimers.append(
			shot_timer,
		)

		add_child(
			shot_timer,
		)

		shot_timer.one_shot = true

		shot_timer.timeout.connect(
			func() -> void:
				if not replayPlaying:
					return

				var replay_ball: BasketballBall = currentBall.get(
					scheduled_player,
				)

				if not is_instance_valid(replay_ball):
					OpLog.w(
						LOG_TAG,
						[
							"replay_shot_missing_ball player=",
							scheduled_player,
							" x=",
							scheduled_x,
						],
					)

					return

				replay_ball.shoot(
					scheduled_x,
				)

				if currentBall.get(scheduled_player) == replay_ball:
					currentBall[scheduled_player] = null
		)

		shot_timer.wait_time = scheduled_time
		shot_timer.start()

		var next_index := shot_index + 1

		if next_index < parsed_shots.size():
			var next_result := bool(
				parsed_shots[next_index]["did_go_in"],
			)

			var spawn_player := player_num
			var spawn_result := next_result
			var spawn_delay := scheduled_time + 0.1

			var spawn_timer := Timer.new()

			replayTimers.append(
				spawn_timer,
			)

			add_child(
				spawn_timer,
			)

			spawn_timer.one_shot = true

			spawn_timer.timeout.connect(
				func() -> void:
					if replayPlaying:
						spawnBall(
							spawn_player,
							spawn_result,
						)
			)

			spawn_timer.wait_time = spawn_delay
			spawn_timer.start()

	OpLog.i(
		LOG_TAG,
		[
			"play_replay_scheduled player=",
			player_num,
			" lastDelay=",
			last_time_delay,
		],
	)

	return last_time_delay

func _finish_replay(
	finalize_scores: bool = true,
) -> void:
	OpLog.i(
		LOG_TAG,
		[
			"finish_replay_start finalize=",
			finalize_scores,
			" turnNum=",
			turnNum,
			" replayFinished=",
			replayFinished,
			" ",
			_score_summary(),
		],
	)

	for timer in replayTimers:
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()

	replayTimers.clear()
	replayEndTimer = null

	clearBalls()

	if finalize_scores:
		if turnNum != null and int(turnNum) <= 3:
			setScore(
				1,
				int(score1 if score1 != null else 0),
			)

			setScore(
				2,
				int(score2 if score2 != null else 0),
			)
		elif turnNum != null and int(turnNum) >= 5:
			setScore(
				1,
				int(skip_score1 if skip_score1 != null else 0),
			)

			setScore(
				2,
				int(skip_score2 if skip_score2 != null else 0),
			)

	timeRemainingLabel.text = "00:00"

	if is_instance_valid(round_container):
		round_container.visible = false

	if is_instance_valid(skip_button):
		skip_button.visible = false

	replayPlaying = false
	replayFinished = true
	elapsedTime = 0.0

	stop_waiting_animation()

	OpLog.i(
		LOG_TAG,
		[
			"finish_replay_done gameOver=",
			game_over,
			" turn=",
			isTurn,
			" replayFinished=",
			replayFinished,
			" ",
			_score_summary(),
		],
	)

	refresh_ui_state()

func _check_ball_score_crossing(
	ball: BasketballBall,
) -> void:
	if not is_instance_valid(ball):
		return

	if not gamePlaying and not replayPlaying:
		return

	if ball.get_meta(
		"score_counted",
		false,
	):
		return

	var ball_run_id := int(
		ball.get_meta(
			"score_run_id",
			-1,
		),
	)

	if ball_run_id != _score_run_id:
		ball.set_meta(
			"score_counted",
			true,
		)

		return

	var shot_key := String(
		ball.get_meta(
			"score_key",
			"",
		),
	)

	if shot_key.is_empty() or _scored_shot_keys.has(shot_key):
		ball.set_meta(
			"score_counted",
			true,
		)

		return

	var previous_value = ball.get_meta(
		"last_score_pos",
		ball.global_position,
	)

	var previous_position: Vector3 = (
		previous_value
		if previous_value is Vector3
		else ball.global_position
	)

	var current_position := ball.global_position

	ball.set_meta(
		"last_score_pos",
		current_position,
	)

	var hoop_root: Node3D = (
		moving_hoop_collision
		if (
			game_mode == "h" and
			is_instance_valid(moving_hoop_collision)
		)
		else static_hoop_collision
	)

	if not is_instance_valid(hoop_root):
		return

	var hoop_center := hoop_root.global_position
	var hoop_position_total := Vector3.ZERO
	var hoop_position_count := 0

	for child in hoop_root.get_children():
		if (
			child is Node3D and
			child.name.begins_with("HoopCollisionSphere")
		):
			hoop_position_total += (child as Node3D).global_position
			hoop_position_count += 1

	if hoop_position_count > 0:
		hoop_center = (
			hoop_position_total /
			float(hoop_position_count)
		)

	if previous_position.y <= hoop_center.y:
		return

	if current_position.y > hoop_center.y:
		return

	if ball.linear_velocity.y > SCORE_MIN_DOWN_VELOCITY:
		return

	var y_span := previous_position.y - current_position.y

	if absf(y_span) < 0.0001:
		return

	var crossing_fraction := clampf(
		(
			previous_position.y -
			hoop_center.y
		) /
		y_span,
		0.0,
		1.0,
	)

	var crossing_position := previous_position.lerp(
		current_position,
		crossing_fraction,
	)

	var dx := absf(
		crossing_position.x -
		hoop_center.x,
	)

	var dz := absf(
		crossing_position.z -
		hoop_center.z,
	)

	if dx > SCORE_RADIUS_X or dz > SCORE_RADIUS_Z:
		return

	ball.set_meta(
		"score_counted",
		true,
	)

	_scored_shot_keys[shot_key] = true

	if replayPlaying and ball.didGoInReplay == false:
		OpLog.w(
			LOG_TAG,
			[
				"replay_actual_crossing_ignored expectedMiss player=",
				ball.player,
				" key=",
				shot_key,
			],
		)

		return

	ball.didGoIn = true

	var ball_player := int(
		ball.get_meta(
			"player_num",
			0,
		),
	)

	if ball_player == 0:
		return

	OpLog.i(
		LOG_TAG,
		[
			"score_crossing player=",
			ball_player,
			" shotKey=",
			shot_key,
			" crossPos=",
			crossing_position,
			" hoop=",
			hoop_center,
			" dx=",
			dx,
			" dz=",
			dz,
			" replayExpected=",
			str(ball.didGoInReplay),
			" vel=",
			ball.linear_velocity,
		],
	)

	incrementScore(
		ball_player,
	)

func skipReplay():
	OpLog.i(LOG_TAG, ["skip_replay pressed turnNum=", turnNum])
	_finish_replay(true)

func _display_score_for_player(
	player_num: int,
) -> int:
	var round_one_score := 0
	var round_two_score := 0
	var round_two_replay = null

	if player_num == 1:
		round_one_score = int(
			score1 if score1 != null else 0,
		)

		round_two_score = int(
			skip_score1 if skip_score1 != null else round_one_score,
		)

		round_two_replay = replay3
	else:
		round_one_score = int(
			score2 if score2 != null else 0,
		)

		round_two_score = int(
			skip_score2 if skip_score2 != null else round_one_score,
		)

		round_two_replay = replay4

	if turnNum == null or int(turnNum) < 4:
		return round_one_score

	if int(turnNum) >= 5:
		return round_two_score

	# An empty replay is still a submitted round with zero shots.
	if round_two_replay != null:
		return round_two_score

	return round_one_score

func refresh_ui_state() -> void:
	if gamePlaying or replayPlaying:
		round_container.visible = false
		skip_button.visible = false
		return

	var current_turn := int(
		turnNum if turnNum != null else 1,
	)

	var replay_player1 = null
	var replay_player2 = null
	var replay_round := 0

	if current_turn == 3:
		replay_player1 = replay
		replay_player2 = replay2
		replay_round = 1
	elif current_turn >= 5:
		replay_player1 = replay3
		replay_player2 = replay4
		replay_round = 2

	var has_complete_replay := (
		replay_round > 0 and
		replay_player1 != null and
		replay_player2 != null
	)

	var current_replay_key := ""

	if has_complete_replay:
		current_replay_key = (
			str(replay_round) +
			"|" +
			String(replay_player1) +
			"|" +
			String(replay_player2)
		)

	var replay_loaded_from_data := (
		not current_replay_key.is_empty() and
		current_replay_key == _loaded_replay_key
	)

	#
	# A completed round is always replayed before the next turn or
	# final winner state is evaluated. _loaded_replay_key changes only
	# when returned or reopened game data is loaded, so a just-sent
	# local replay pair remains in the waiting state.
	#
	if replay_loaded_from_data and not replayFinished:
		OpLog.i(
			LOG_TAG,
			[
				"refresh_ui start_completed_replay round=",
				replay_round,
				" turnNum=",
				current_turn,
				" isTurn=",
				isTurn,
				" spectator=",
				spectator_mode,
				" p1Shots=",
				_replay_shot_count(replay_player1),
				" p2Shots=",
				_replay_shot_count(replay_player2),
			],
		)

		stop_waiting_animation()

		if is_instance_valid(winner_label):
			winner_label.visible = false

		round_container.visible = false
		skip_button.visible = true

		ballNum = {
			1: 1,
			2: 1,
		}

		_score_run_id += 1
		_scored_shot_keys.clear()
		_last_score_msec_by_player.clear()

		if replay_round == 1:
			setScore(
				1,
				0,
			)

			setScore(
				2,
				0,
			)
		else:
			setScore(
				1,
				int(score1 if score1 != null else 0),
			)

			setScore(
				2,
				int(score2 if score2 != null else 0),
			)

		hoop_time = 0
		_hoop_acc = 0.0
		elapsedTime = 0.0
		replayPlaying = true

		if (
			hoop_center_tween and
			hoop_center_tween.is_running()
		):
			hoop_center_tween.kill()

		if is_instance_valid(moving_hoop_root):
			_set_moving_hoop_x(
				0.0,
			)

		clearBalls()

		spawnBall(
			1,
		)

		spawnBall(
			2,
		)

		var replay1_end := playReplay(
			1,
			String(replay_player1),
		)

		var replay2_end := playReplay(
			2,
			String(replay_player2),
		)

		if (
			replayEndTimer != null and
			is_instance_valid(replayEndTimer)
		):
			replayEndTimer.stop()
			replayEndTimer.queue_free()

		replayEndTimer = Timer.new()

		replayTimers.append(
			replayEndTimer,
		)

		add_child(
			replayEndTimer,
		)

		replayEndTimer.one_shot = true

		replayEndTimer.timeout.connect(
			func() -> void:
				if replayPlaying:
					_finish_replay(
						true,
					)
		)

		replayEndTimer.wait_time = maxf(
			maxf(
				replay1_end,
				replay2_end,
			) + 2.5,
			1.0,
		)

		replayEndTimer.start()
		return

	#
	# Final win/loss is shown only after the round-two replay.
	#
	if (
		current_turn >= 5 and
		replay_loaded_from_data and
		replayFinished
	):
		stop_waiting_animation()

		round_container.visible = false
		skip_button.visible = false
		waiting_blur.visible = false

		setScore(
			1,
			int(skip_score1 if skip_score1 != null else 0),
		)

		setScore(
			2,
			int(skip_score2 if skip_score2 != null else 0),
		)

		game_over = true
		showWinner()

		#
		# Older or cross-platform final data may not include winner.
		# Add it once after the final replay. Existing winner data is
		# never sent again.
		#
		if (
			not spectator_mode and
			not loaded_has_winner and
			not winner_sent and
			not isNullOrEmpty(my_player)
		):
			var win_value := 0

			if myScore > oppScore:
				win_value = 1
			elif myScore < oppScore:
				win_value = -1

			var winner_data: Dictionary = {
				"game": "basketball",
				"player": str(player),
				"mode": game_mode,
				"round": "2",
				"seed": str(
					game_seed if game_seed != null else 0,
				),
				"seed2": str(
					seed2 if seed2 != null else 0,
				),
				"score1": str(
					score1 if score1 != null else 0,
				),
				"score2": str(
					score2 if score2 != null else 0,
				),
				"skip_score1": str(
					skip_score1 if skip_score1 != null else 0,
				),
				"skip_score2": str(
					skip_score2 if skip_score2 != null else 0,
				),
				"replay": str(
					replay if replay != null else "",
				),
				"replay2": str(
					replay2 if replay2 != null else "",
				),
				"replay3": str(
					replay3 if replay3 != null else "",
				),
				"replay4": str(
					replay4 if replay4 != null else "",
				),
				"winner": (
					str(my_player) +
					"|" +
					str(win_value)
				),
			}

			var local_player_id_key := (
				"player1"
				if player == 1
				else "player2"
			)

			winner_data[local_player_id_key] = str(
				my_player,
			)

			var avatar_key := (
				"avatar1"
				if player == 1
				else "avatar2"
			)

			if (
				is_instance_valid(player_avatar_display) and
				player_avatar_display.has_method(
					"get_avatar_data_string",
				)
			):
				winner_data[avatar_key] = (
					player_avatar_display.get_avatar_data_string()
				)

			winner_sent = true
			loaded_has_winner = true

			var serialized_winner_data := JSON.stringify(
				winner_data,
			)

			OpLog.event(
				LOG_TAG,
				[
					"send_missing_winner winner=",
					winner_data["winner"],
					" raw=",
					serialized_winner_data,
				],
			)

			appPlugin = Engine.get_singleton(
				"AppPlugin",
			)

			if appPlugin:
				appPlugin.updateGameData(
					serialized_winner_data,
				)
			else:
				OpLog.w(
					LOG_TAG,
					[
						"missing_winner_not_sent AppPlugin unavailable raw=",
						serialized_winner_data,
					],
				)

		return

	#
	# If a completed round has replayed, decide whether this user gets
	# the next round or waits for the opponent.
	#
	if current_turn == 3 and replay_loaded_from_data and replayFinished:
		setScore(
			1,
			int(score1 if score1 != null else 0),
		)

		setScore(
			2,
			int(score2 if score2 != null else 0),
		)

		if isTurn == true and not spectator_mode:
			stop_waiting_animation()

			waiting_blur.visible = true
			round_label.text = "Round 2"
			round_container.visible = true
			skip_button.visible = false

			OpLog.i(
				LOG_TAG,
				[
					"round_ready round=2 turnNum=",
					current_turn,
					" ",
					_score_summary(),
				],
			)
		else:
			round_container.visible = false
			skip_button.visible = false

			if not spectator_mode:
				start_waiting_animation()

		return

	#
	# Turn 3 represents the completed first round. Do not expose round
	# 2 until the complete replay pair has arrived through game data
	# and has been played.
	#
	if current_turn == 3 and not replay_loaded_from_data:
		round_container.visible = false
		skip_button.visible = false

		setScore(
			1,
			_display_score_for_player(1),
		)

		setScore(
			2,
			_display_score_for_player(2),
		)

		if not spectator_mode and allow_waiting_from_loaded_data:
			start_waiting_animation()

		return

	#
	# A final state without both round-two replays must wait instead of
	# jumping directly to win/loss.
	#
	if current_turn >= 5 and not replay_loaded_from_data:
		round_container.visible = false
		skip_button.visible = false

		setScore(
			1,
			_display_score_for_player(1),
		)

		setScore(
			2,
			_display_score_for_player(2),
		)

		if not spectator_mode and allow_waiting_from_loaded_data:
			start_waiting_animation()

		return

	#
	# Turn 4 means one round-two result exists and the other player may
	# now play round 2. No replay occurs until both round-two results
	# are available.
	#
	if current_turn == 4:
		setScore(
			1,
			_display_score_for_player(1),
		)

		setScore(
			2,
			_display_score_for_player(2),
		)

		if isTurn == true and not spectator_mode:
			stop_waiting_animation()

			waiting_blur.visible = true
			round_label.text = "Round 2"
			round_container.visible = true
			skip_button.visible = false
		else:
			round_container.visible = false
			skip_button.visible = false

			if not spectator_mode and allow_waiting_from_loaded_data:
				start_waiting_animation()

		return

	#
	# Before a completed round is available, show the active round only
	# when it is this user's turn.
	#
	if isTurn == true and not spectator_mode:
		stop_waiting_animation()

		round_label.text = (
			"Round 2"
			if current_turn >= 3
			else "Round 1"
		)

		waiting_blur.visible = true
		round_container.visible = true
		skip_button.visible = false
		return

	round_container.visible = false
	skip_button.visible = false

	if current_turn >= 1:
		setScore(
			1,
			_display_score_for_player(1),
		)

		setScore(
			2,
			_display_score_for_player(2),
		)

	if not spectator_mode and allow_waiting_from_loaded_data:
		start_waiting_animation()

func spawnBall(
	player_num: int,
	didGoInReplay = null,
) -> BasketballBall:
	if appPlugin != null:
		var use_round_one_seed := false

		if replayPlaying:
			use_round_one_seed = (
				turnNum != null and
				int(turnNum) <= 3
			)
		else:
			use_round_one_seed = (
				turnNum == null or
				int(turnNum) < 3
			)

		appPlugin.srand48(
			player_num,
			game_seed if use_round_one_seed else seed2,
		)
	else:
		randomize()

	if ballNum[player_num] >= 1:
		var i: int = ballNum[player_num]

		while true:
			if appPlugin != null:
				appPlugin.drand48(
					player_num,
				)
			else:
				randf()

			if i == 1:
				break

			i -= 1

	var new_ball: BasketballBall = get_node(
		"Ball",
	).duplicate()

	var ball_mesh: MeshInstance3D = new_ball.get_child(
		1,
	)

	var roll_source: float = (
		appPlugin.drand48(player_num)
		if appPlugin != null
		else randf()
	)

	var pitch_source: float = (
		appPlugin.drand48(player_num)
		if appPlugin != null
		else randf()
	)

	var yaw_source: float = (
		appPlugin.drand48(player_num)
		if appPlugin != null
		else randf()
	)

	var roll: float = roll_source * 8.0 - 9.0
	var pitch: float = pitch_source * 20.0 + 70.0
	var yaw: float = yaw_source * 10.0 - 5.0

	var x_rand: float = (
		appPlugin.drand48(player_num)
		if appPlugin != null
		else randf()
	)

	var x_pos: float = x_rand * 0.66 - 0.33

	if player_num == 2:
		x_pos *= -1.0

	new_ball.set_player(
		player_num,
	)

	if didGoInReplay != null:
		new_ball.set_didGoInReplay(
			didGoInReplay,
		)

	new_ball.collision_layer = player_num
	new_ball.collision_mask = player_num

	new_ball.rotation = Vector3(
		roll,
		pitch,
		yaw,
	)

	new_ball.position = Vector3(
		x_pos,
		-0.45,
		-1.0,
	)

	new_ball.get_child(
		0,
	).disabled = false

	new_ball.axis_lock_angular_x = true
	new_ball.axis_lock_angular_y = true
	new_ball.axis_lock_angular_z = true
	new_ball.angular_velocity = Vector3.ZERO

	new_ball.freeze = false
	new_ball.sleeping = false
	new_ball.visible = true

	if player_num != player:
		ball_mesh.material_override = (
			ball_mesh.material_override.duplicate()
		)

		ball_mesh.material_override.albedo_color = Color(
			1.0,
			1.0,
			1.0,
			0.75,
		)

	var shot_num: int = int(
		ballNum[player_num],
	)

	new_ball.name = (
		"Ball_P" +
		str(player_num) +
		"_" +
		str(shot_num)
	)

	add_child(
		new_ball,
	)

	new_ball.set_meta(
		"player_num",
		player_num,
	)

	new_ball.set_meta(
		"shot_num",
		shot_num,
	)

	new_ball.set_meta(
		"score_run_id",
		_score_run_id,
	)

	new_ball.set_meta(
		"score_key",
		"%d:%d:%d" % [
			_score_run_id,
			player_num,
			shot_num,
		],
	)

	new_ball.set_meta(
		"score_counted",
		false,
	)

	new_ball.set_meta(
		"last_score_pos",
		new_ball.global_position,
	)

	ballNum[player_num] += 1
	currentBall[player_num] = new_ball

	dbg(
		[
			"spawn_ball player=",
			player_num,
			" shotNum=",
			shot_num,
			" replayResult=",
			str(didGoInReplay),
			" pos=",
			new_ball.position,
			" rot=",
			new_ball.rotation,
			" runId=",
			_score_run_id,
			" key=",
			new_ball.get_meta("score_key"),
		],
	)

	return new_ball

func _set_game_data(
	new_replay: String,
	saved: bool = false,
) -> void:
	OpLog.event(
		LOG_TAG,
		[
			"set_game_data_in saved=",
			saved,
			" raw=",
			new_replay,
		],
	)

	var parsed = JSON.parse_string(
		new_replay,
	)

	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.e(
			LOG_TAG,
			[
				"set_game_data invalid JSON raw=",
				new_replay,
			],
		)

		return

	if gamePlaying or replayPlaying:
		OpLog.i(
			LOG_TAG,
			[
				"set_game_data deferred activeRound=",
				gamePlaying,
				" replayPlaying=",
				replayPlaying,
				" rawLen=",
				new_replay.length(),
			],
		)

		receivedMessage = new_replay
		return

	loaded_has_winner = (
		parsed.has("winner") and
		not isNullOrEmpty(
			str(parsed["winner"]),
		)
	)

	winner_sent = loaded_has_winner

	game_mode = str(
		parsed.get(
			"mode",
			game_mode,
		),
	)

	_apply_basketball_mode()

	if parsed.has("num"):
		turnNum = int(
			parsed["num"],
		)
	elif turnNum == null:
		turnNum = 1

	isTurn = bool(
		parsed.get(
			"isYourTurn",
			false,
		),
	)

	var payload_player := int(
		parsed.get(
			"player",
			1,
		),
	)

	my_player = parsed.get(
		"myPlayerId",
		my_player,
	)

	var player1_id := str(
		parsed.get(
			"player1",
			"",
		),
	)

	var player2_id := str(
		parsed.get(
			"player2",
			"",
		),
	)

	var my_player_id := str(
		my_player if my_player != null else "",
	)

	spectator_mode = false

	if (
		not my_player_id.is_empty() and
		not player1_id.is_empty() and
		not player2_id.is_empty()
	):
		spectator_mode = (
			my_player_id != player1_id and
			my_player_id != player2_id
		)

	if spectator_mode:
		player = 1
		isTurn = false
		gamePlaying = false

		if is_instance_valid(spectator_label):
			spectator_label.show()
	else:
		var resolved_player := payload_player

		if not my_player_id.is_empty():
			if (
				not player1_id.is_empty() and
				my_player_id == player1_id
			):
				resolved_player = 1
			elif (
				not player2_id.is_empty() and
				my_player_id == player2_id
			):
				resolved_player = 2
			elif (
				player1_id.is_empty() and
				not player2_id.is_empty() and
				my_player_id != player2_id
			):
				resolved_player = 1
			elif (
				player2_id.is_empty() and
				not player1_id.is_empty() and
				my_player_id != player1_id
			):
				resolved_player = 2
			elif isTurn:
				resolved_player = (
					2
					if payload_player == 1
					else 1
				)
		elif isTurn:
			resolved_player = (
				2
				if payload_player == 1
				else 1
			)

		player = resolved_player

		if is_instance_valid(spectator_label):
			spectator_label.hide()

	stop_waiting_animation()

	OpLog.i(
		LOG_TAG,
		[
			"player_resolve payloadPlayer=",
			payload_player,
			" localPlayer=",
			player,
			" isTurn=",
			isTurn,
			" turnNum=",
			turnNum,
			" myId=",
			my_player_id,
			" player1Id=",
			player1_id,
			" player2Id=",
			player2_id,
		],
	)

	if spectator_mode:
		if (
			parsed.has("avatar1") and
			is_instance_valid(player_avatar_display)
		):
			var player1_avatar_data: Dictionary = (
				GameUtils._parse_avatar_string(
					str(parsed["avatar1"]),
				)
			)

			player_avatar_display.call_deferred(
				"update_avatar_from_data",
				player1_avatar_data,
			)

		if (
			parsed.has("avatar2") and
			is_instance_valid(opp_avatar_display)
		):
			var player2_avatar_data: Dictionary = (
				GameUtils._parse_avatar_string(
					str(parsed["avatar2"]),
				)
			)

			opp_avatar_display.call_deferred(
				"update_avatar_from_data",
				player2_avatar_data,
			)
	else:
		var opponent_avatar_key := (
			"avatar2"
			if player == 1
			else "avatar1"
		)

		if (
			parsed.has(opponent_avatar_key) and
			is_instance_valid(opp_avatar_display)
		):
			var opponent_avatar_data: Dictionary = (
				GameUtils._parse_avatar_string(
					str(parsed[opponent_avatar_key]),
				)
			)

			opp_avatar_display.call_deferred(
				"update_avatar_from_data",
				opponent_avatar_data,
			)

	if parsed.has("seed"):
		game_seed = int(
			parsed["seed"],
		)

	if parsed.has("seed2"):
		seed2 = int(
			parsed["seed2"],
		)

	if parsed.has("score1"):
		score1 = int(
			parsed["score1"],
		)

	if parsed.has("score2"):
		score2 = int(
			parsed["score2"],
		)

	if parsed.has("skip_score1"):
		skip_score1 = int(
			parsed["skip_score1"],
		)

	if parsed.has("skip_score2"):
		skip_score2 = int(
			parsed["skip_score2"],
		)

	if parsed.has("replay"):
		replay = parsed["replay"]

	if parsed.has("replay2"):
		replay2 = parsed["replay2"]

	if parsed.has("replay3"):
		replay3 = parsed["replay3"]

	if parsed.has("replay4"):
		replay4 = parsed["replay4"]

	#
	# A fresh complete replay pair must play even when isYourTurn is
	# false. The replay key prevents duplicate delivery of the same
	# message from replaying again during the same open session.
	#
	var incoming_replay_key := ""

	if (
		turnNum != null and
		int(turnNum) == 3 and
		replay != null and
		replay2 != null
	):
		incoming_replay_key = (
			"1|" +
			String(replay) +
			"|" +
			String(replay2)
		)
	elif (
		turnNum != null and
		int(turnNum) >= 5 and
		replay3 != null and
		replay4 != null
	):
		incoming_replay_key = (
			"2|" +
			String(replay3) +
			"|" +
			String(replay4)
		)

	if (
		not incoming_replay_key.is_empty() and
		incoming_replay_key != _loaded_replay_key
	):
		_loaded_replay_key = incoming_replay_key
		replayFinished = false
		game_over = false

		if is_instance_valid(winner_label):
			winner_label.visible = false

		OpLog.i(
			LOG_TAG,
			[
				"new_completed_replay_pair keyLength=",
				incoming_replay_key.length(),
				" turnNum=",
				turnNum,
			],
		)

	receivedMessage = null
	gameDataSet = true

	OpLog.i(
		LOG_TAG,
		[
			"set_game_data_done turnNum=",
			turnNum,
			" payloadPlayer=",
			payload_player,
			" localPlayer=",
			player,
			" isTurn=",
			isTurn,
			" spectator=",
			spectator_mode,
			" mode=",
			game_mode,
			" replayFinished=",
			replayFinished,
			" loadedWinner=",
			loaded_has_winner,
			" replay1Shots=",
			_replay_shot_count(replay),
			" replay2Shots=",
			_replay_shot_count(replay2),
			" replay3Shots=",
			_replay_shot_count(replay3),
			" replay4Shots=",
			_replay_shot_count(replay4),
			" ",
			_score_summary(),
		],
	)

	if not saved:
		allow_waiting_from_loaded_data = true

		refresh_ui_state()

		allow_waiting_from_loaded_data = false

func sendGameData(
	completed_score: int,
	completed_replay_value: String,
) -> void:
	var completed_turn := int(
		turnNum,
	)

	var outgoing_replay := completed_replay_value.strip_edges()

	while outgoing_replay.ends_with("|"):
		outgoing_replay = outgoing_replay.left(
			outgoing_replay.length() - 1,
		)

	var next_turn := completed_turn + 1
	var is_round_one := next_turn <= 3

	var score_key := (
		"score1"
		if player == 1
		else "score2"
	)

	var replay_key := (
		"replay"
		if player == 1
		else "replay2"
	)

	if not is_round_one:
		score_key = (
			"skip_score1"
			if player == 1
			else "skip_score2"
		)

		replay_key = (
			"replay3"
			if player == 1
			else "replay4"
		)

	#
	# Store the completed local result directly in its correct player
	# and round slot.
	#
	if player == 1:
		if is_round_one:
			score1 = completed_score
			replay = outgoing_replay
		else:
			skip_score1 = completed_score
			replay3 = outgoing_replay
	else:
		if is_round_one:
			score2 = completed_score
			replay2 = outgoing_replay
		else:
			skip_score2 = completed_score
			replay4 = outgoing_replay

	turnNum = next_turn

	var game_data: Dictionary = {
		"game": "basketball",
		"player": str(player),
		"mode": game_mode,
		"seed": str(
			game_seed if game_seed != null else 0,
		),
		"seed2": str(
			seed2 if seed2 != null else 0,
		),
		"round": "1" if is_round_one else "2",
		"score1": str(
			score1 if score1 != null else 0,
		),
		"score2": str(
			score2 if score2 != null else 0,
		),
		"skip_score1": str(
			skip_score1 if skip_score1 != null else 0,
		),
		"skip_score2": str(
			skip_score2 if skip_score2 != null else 0,
		),
	}

	# Include the completed replay even when it contains zero shots.
	game_data[replay_key] = outgoing_replay

	if replay != null:
		game_data["replay"] = str(replay)

	if replay2 != null:
		game_data["replay2"] = str(replay2)

	if replay3 != null:
		game_data["replay3"] = str(replay3)

	if replay4 != null:
		game_data["replay4"] = str(replay4)

	if not isNullOrEmpty(my_player):
		var local_player_id_key := (
			"player1"
			if player == 1
			else "player2"
		)

		game_data[local_player_id_key] = str(
			my_player,
		)

	var avatar_key := (
		"avatar1"
		if player == 1
		else "avatar2"
	)

	if (
		is_instance_valid(player_avatar_display) and
		player_avatar_display.has_method(
			"get_avatar_data_string",
		)
	):
		game_data[avatar_key] = (
			player_avatar_display.get_avatar_data_string()
		)

	#
	# The final sender may include winner in the final payload. The UI
	# still waits for returned/reopened data, plays the final replay,
	# and only then shows win/loss.
	#
	if next_turn >= 5 and not isNullOrEmpty(my_player):
		var opponent_final_score := int(
			skip_score2
			if player == 1 and skip_score2 != null
			else (
				skip_score1
				if player == 2 and skip_score1 != null
				else 0
			),
		)

		var win_value := 0

		if completed_score > opponent_final_score:
			win_value = 1
		elif completed_score < opponent_final_score:
			win_value = -1

		game_data["winner"] = (
			str(my_player) +
			"|" +
			str(win_value)
		)

		winner_sent = true
		loaded_has_winner = true

	#
	# A completed pair created by this local send is not replayed yet.
	# _loaded_replay_key is updated only by _set_game_data(), so the
	# replay begins when the message returns or the game is reopened.
	#
	var local_pair_complete := false

	if next_turn == 3:
		local_pair_complete = (
			replay != null and
			replay2 != null
		)
	elif next_turn >= 5:
		local_pair_complete = (
			replay3 != null and
			replay4 != null
		)

	game_over = false

	if is_instance_valid(winner_label):
		winner_label.visible = false

	play_sent_animation()

	var serialized_game_data := JSON.stringify(
		game_data,
	)

	OpLog.event(
		LOG_TAG,
		[
			"send_game_out turnNum=",
			turnNum,
			" localPlayer=",
			player,
			" scoreKey=",
			score_key,
			" replayKey=",
			replay_key,
			" replayShots=",
			_replay_shot_count(outgoing_replay),
			" pairComplete=",
			local_pair_complete,
			" winner=",
			str(
				game_data.get(
					"winner",
					"",
				),
			),
			" raw=",
			serialized_game_data,
		],
	)

	appPlugin = Engine.get_singleton(
		"AppPlugin",
	)

	if appPlugin:
		appPlugin.updateGameData(
			serialized_game_data,
		)
	else:
		OpLog.w(
			LOG_TAG,
			[
				"AppPlugin not connected; payload not sent raw=",
				serialized_game_data,
			],
		)

func start_button_pressed():
	if spectator_mode:
		return
	round_container.visible = false
	waiting_blur.visible = false
	OpLog.i(LOG_TAG, ["start_pressed turnNum=", turnNum, " player=", player])
	startGame()

func startGame() -> void:
	OpLog.i(
		LOG_TAG,
		[
			"start_game player=",
			player,
			" turnNum=",
			turnNum,
			" mode=",
			game_mode,
			" runId=",
			_score_run_id + 1,
		],
	)

	if is_instance_valid(winner_label):
		winner_label.visible = false

	game_over = false

	ballNum = {
		1: 1,
		2: 1,
	}

	_score_run_id += 1
	_scored_shot_keys.clear()
	_last_score_msec_by_player.clear()

	myReplay = ""
	elapsedTime = 0.0
	gamePlaying = true
	replayPlaying = false
	replayFinished = false
	receivedMessage = null

	for timer in replayTimers:
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()

	replayTimers.clear()
	replayEndTimer = null

	hoop_time = 0
	_hoop_acc = 0.0

	if (
		hoop_center_tween and
		hoop_center_tween.is_running()
	):
		hoop_center_tween.kill()

	if is_instance_valid(moving_hoop_root):
		_set_moving_hoop_x(
			0.0,
		)

	spawnBall(
		player,
	)

	OpLog.i(
		LOG_TAG,
		[
			"start_game_done ",
			_score_summary(),
		],
	)

func _haptic_explosion(strength: float = 0.35, duration_ms: int = 22) -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return

	strength = clampf(strength, 0.0, 1.0)
	Input.vibrate_handheld(duration_ms, strength)

func incrementScore(player_num: int) -> void:
	var now_ms: int = Time.get_ticks_msec()
	var last_ms: int = int(_last_score_msec_by_player.get(player_num, -1000000))

	if now_ms - last_ms < SCORE_DUPLICATE_LOCK_MS:
		OpLog.w(LOG_TAG, ["score_duplicate_ignored player=", player_num, " deltaMs=", now_ms - last_ms])
		return

	_last_score_msec_by_player[player_num] = now_ms

	if player_num == player:
		myScore += 1
		youScoreLabel.text = str(myScore).pad_zeros(2)
		_haptic_explosion()
	else:
		oppScore += 1
		oppScoreLabel.text = str(oppScore).pad_zeros(2)
	OpLog.i(LOG_TAG, ["score_increment player=", player_num, " ", _score_summary()])

func setScore(player_num: int, score: int) -> void:
	dbg(["set_score player=", player_num, " score=", score])

	if player_num == player:
		_haptic_explosion()
		myScore = score
		youScoreLabel.text = str(myScore).pad_zeros(2)
	else:
		oppScore = score
		oppScoreLabel.text = str(oppScore).pad_zeros(2)

	dbg(["set_score_done player=", player_num, " ", _score_summary()])

func isNullOrEmpty(value) -> bool:
	if value == null:
		return true
	return String(value).length() == 0

func clearBalls() -> void:
	var cleared := 0
	for node in get_children():
		if node.name.begins_with("Ball_P"):
			node.set_meta("score_counted", true)
			node.name = "Cleared_" + String(node.name)
			cleared += 1
			node.queue_free()

	currentBall[1] = null
	currentBall[2] = null
	dbg(["clear_balls count=", cleared])

func _physics_process(
	delta: float,
) -> void:
	if (
		game_mode == "h" and
		is_instance_valid(moving_hoop_root) and
		(gamePlaying or replayPlaying)
	):
		if (
			hoop_center_tween and
			hoop_center_tween.is_running()
		):
			hoop_center_tween.kill()

		_hoop_acc += delta * 60.0

		while _hoop_acc >= 1.0:
			hoop_time += 1
			_hoop_acc -= 1.0

		var movement_tick := hoop_time % 480
		var hoop_x := 0.0

		if movement_tick < 120:
			hoop_x = float(movement_tick) / 120.0
		elif movement_tick < 240:
			hoop_x = (
				1.0 -
				float(movement_tick - 120) / 120.0
			)
		elif movement_tick < 360:
			hoop_x = (
				-float(movement_tick - 240) /
				120.0
			)
		else:
			hoop_x = (
				-1.0 +
				float(movement_tick - 360) /
				120.0
			)

		_set_moving_hoop_x(
			hoop_x,
		)

	if gamePlaying or replayPlaying:
		for node in get_children():
			if (
				node is BasketballBall and
				node.name.begins_with("Ball_P")
			):
				_check_ball_score_crossing(
					node,
				)

func _process(
	delta: float,
) -> void:
	if (
		game_mode == "h" and
		is_instance_valid(moving_hoop_root)
	):
		if not gamePlaying and not replayPlaying:
			hoop_time = 0
			_hoop_acc = 0.0

			if absf(
				moving_hoop_root.position.x,
			) > 0.001:
				if (
					hoop_center_tween == null or
					not hoop_center_tween.is_running()
				):
					hoop_center_tween = create_tween()

					hoop_center_tween.tween_property(
						moving_hoop_root,
						"position:x",
						0.0,
						0.35,
					)
			else:
				_set_moving_hoop_x(
					0.0,
				)

	if not gamePlaying and not replayPlaying:
		return

	elapsedTime += delta

	var remaining_seconds := int(
		ceil(
			45.0 -
			elapsedTime,
		),
	)

	timeRemainingLabel.text = (
		"00:" +
		str(
			maxi(
				remaining_seconds,
				0,
			),
		).pad_zeros(2)
	)

	if remaining_seconds > 0:
		return

	elapsedTime = 0.0

	var was_replay_playing : bool = replayPlaying

	gamePlaying = false
	replayPlaying = false

	await get_tree().create_timer(
		3.0,
	).timeout

	if was_replay_playing:
		_finish_replay(
			true,
		)

		return

	#
	# Snapshot the completed local result before any returned or
	# deferred game message changes the state.
	#
	var completed_player := int(
		player,
	)

	var completed_turn := int(
		turnNum,
	)

	var completed_score := int(
		myScore,
	)

	var completed_replay := String(
		myReplay,
	)

	while completed_replay.ends_with("|"):
		completed_replay = completed_replay.left(
			completed_replay.length() - 1,
		)

	OpLog.i(
		LOG_TAG,
		[
			"game_timer_done sending_data completedPlayer=",
			completed_player,
			" completedTurn=",
			completed_turn,
			" score=",
			completed_score,
			" replayShots=",
			_replay_shot_count(completed_replay),
		],
	)

	#
	# We are waiting as soon as the local result is sent.
	# Do this before sendGameData() starts the Sent animation.
	#
	isTurn = false

	sendGameData(
		completed_score,
		completed_replay,
	)

	clearBalls()

	round_container.visible = false
	skip_button.visible = false

	#
	# A message received during gameplay is applied only after the local
	# result has safely been sent.
	#
	var deferred_message = receivedMessage

	receivedMessage = null

	if deferred_message != null:
		var deferred_parsed = JSON.parse_string(
			String(
				deferred_message,
			),
		)

		var deferred_turn := -1

		if deferred_parsed is Dictionary:
			deferred_turn = int(
				deferred_parsed.get(
					"num",
					-1,
				),
			)

		if deferred_turn >= int(turnNum):
			OpLog.i(
				LOG_TAG,
				[
					"applying_deferred_message_after_send num=",
					deferred_turn,
				],
			)

			_set_game_data(
				String(
					deferred_message,
				),
				true,
			)
		else:
			OpLog.w(
				LOG_TAG,
				[
					"ignoring_stale_deferred_message deferredNum=",
					deferred_turn,
					" currentNum=",
					turnNum,
				],
			)

	OpLog.i(
		LOG_TAG,
		[
			"game_round_done localPlayer=",
			completed_player,
			" isTurn=",
			isTurn,
			" turnNum=",
			turnNum,
			" ",
			_score_summary(),
		],
	)

	refresh_ui_state()

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		OpLog.w(LOG_TAG, "play_sent_animation skipped: sent_label invalid")
		return
	if sent_tween and sent_tween.is_running():
		sent_tween.kill()

	sent_tween = create_tween().set_parallel(false)

	sent_label.text = "Sent"
	sent_label.visible = true
	sent_label.modulate.a = 0.0
	sent_label.scale = Vector2.ONE
	sent_label.pivot_offset = sent_label.get_size() / 2.0

	sent_tween.tween_property(sent_label, "modulate:a", 1.0, 0.3)
	sent_tween.tween_interval(0.6)
	sent_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.text = "Sent ✔"
	)
	sent_tween.tween_interval(2.0)
	sent_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)

	sent_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0

		if not replayPlaying and not gamePlaying and isTurn == false:
			start_waiting_animation()
	)
	
