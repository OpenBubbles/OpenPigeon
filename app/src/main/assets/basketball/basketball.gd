extends BaseGame3D
class_name basketball

var elapsedTime: float = 0.0

const MUSIC_STREAM := preload("res://global/audio/basketball.ogg")
const MIN_DRAG_DISTANCE := 30.0

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

const HOOP_AMPLITUDE := 1.0
const HOOP_PERIOD_FRAMES := 510.0
const HOOP_QUARTER_FRAMES := 127.5
const HOOP_THREE_QUARTER_FRAMES := 382.5
const SCORE_RADIUS_X := 0.32
const SCORE_RADIUS_Z := 0.26
const SCORE_MIN_DOWN_VELOCITY := -0.05

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

var replay = null
var replay2 = null
var replay3 = null
var replay4 = null
var isTurn = null
var player = null
var seed = null
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

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM

func _get_dev_data() -> String:
	return '{"isYourTurn": true, "myPlayerId": "9a6e234c-2244-4621-a08f-38acd277a2e0", "skip_score1": "18", "skip_score2": "46", "player": "2", "score1": "18", "score2": "23", "sender": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb", "avatar2": "body,3|eyes,6|mouth,3|acc,0|wins,0|bg_color,0.933333,0.407843,0.647059|body_color,0.968627,0.811765,0.333333|glasses,0|stache,0|backdrop,0|hair,0|clothes,2|hair_color,0.505882,0.725490,0.254902|clothes_color,0.686657,0.686657,0.686657", "player2": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb", "id": "G4m1HA79uZDuAtHY", "ios": "26.1", "num": "1", "game": "basketball", "mode": "h", "seed": "-1417153476", "tver": "5", "build": "28R", "round": "1", "seed2": "-16614620", "start": "", "version": "5", "caption": "Lets play Basketball!", "game_name": "Basketball", "replay": "60,0.264,0,0"}'

func _on_game_ready() -> void:
	if not _ui_initialized:
		_ui_initialized = true

		timeRemainingLabel = get_node("Scoreboard/Time")
		youScoreLabel = get_node("Scoreboard/YouScore")
		oppScoreLabel = get_node("Scoreboard/OppScore")

		if is_instance_valid(start_button):
			start_button.pressed.connect(start_button_pressed)
		if is_instance_valid(skip_button):
			skip_button.pressed.connect(skipReplay)

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


func _hard_hoop_x_from_tick(tick: int) -> float:
	var t: int = tick % 480

	if t < 120:
		return float(t) / 120.0
	elif t < 240:
		return 1.0 - float(t - 120) / 120.0
	elif t < 360:
		return -float(t - 240) / 120.0

	return -1.0 + float(t - 360) / 120.0

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

	if not hard_mode:
		hoop_time = 0
		_hoop_acc = 0.0
		if hoop_center_tween and hoop_center_tween.is_running():
			hoop_center_tween.kill()
		if is_instance_valid(moving_hoop_root):
			_set_moving_hoop_x(0.0)
			
	_set_collision_shapes_enabled(static_hoop_collision, not hard_mode)
	_set_collision_shapes_enabled(static_backboard, not hard_mode)

	_set_collision_shapes_enabled(moving_hoop_collision, hard_mode)
	_set_collision_shapes_enabled(moving_backboard, hard_mode)
		
func getReplay(player_num: int):
	if player_num == 1:
		if turnNum <= 3:
			return replay
		return replay3
	if player_num == 2:
		if turnNum <= 3:
			return replay2
		return replay4
	assert(true, "wtf player is not 1 or 2") 
		
var drag_start_pos = Vector2.ZERO
var dragging = false

func _is_touch_on_current_ball(screen_pos: Vector2) -> bool:
	if player == null or currentBall[player] == null:
		return false

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false

	var ball_screen_pos := camera.unproject_position(currentBall[player].global_position)
	var buffer := 120.0

	return screen_pos.distance_to(ball_screen_pos) <= buffer

func _input(event: InputEvent) -> void:
	if spectator_mode:
		return
	if player != null and gamePlaying and event is InputEventMouseButton and currentBall[player] != null:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not _is_touch_on_current_ball(event.position):
					return

				drag_start_pos = event.position
				dragging = true
			else:
				if dragging:
					var drag_end_pos = event.position
					var delta = drag_end_pos - drag_start_pos

					if delta.length() < MIN_DRAG_DISTANCE:
						dragging = false
						return

					var x_delta_lerp = interpolate_x_delta(delta.x)

					currentBall[player].shoot(x_delta_lerp)
					currentBall[player] = null
					dragging = false

					await get_tree().create_timer(0.25).timeout

					if gamePlaying:
						spawnBall(player)

func interpolate_x_delta(value: float) -> float:
	var t = inverse_lerp(-200.0, 200.0, value)
	return lerp(-1, 1, t)

func playReplay(player_num: int, replay_str: String) -> float:
	replayPlaying = true
	var replayShots = replay_str.split('|')
	var replayBallNum = 0
	var last_time_delay: float = 0.0

	for shot in replayShots:
		var shotSplit = shot.split(',')
		if shotSplit.size() < 4:
			continue

		var timeDelay: float = float(shotSplit[0]) / 60.0
		var x_delta: float = float(shotSplit[1])
		var did_go_in: bool = bool(int(shotSplit[3]))
		last_time_delay = max(last_time_delay, timeDelay)
		
		var shotTimer = Timer.new()
		replayTimers.append(shotTimer)
		self.add_child(shotTimer)
		shotTimer.one_shot = true
		shotTimer.timeout.connect(func():
			if currentBall[player_num] != null:
				currentBall[player_num].shoot(x_delta)
		)
		shotTimer.set_wait_time(timeDelay)
		shotTimer.start()
		
		if replayBallNum + 1 < len(replayShots):
			var timer = Timer.new()
			replayTimers.append(timer)
			self.add_child(timer)
			timer.one_shot = true
			timer.timeout.connect(func(): spawnBall(player_num, did_go_in))
			timer.set_wait_time(timeDelay + 0.1)
			timer.start()
			
		replayBallNum += 1

	return last_time_delay
	
func _schedule_replay_auto_finish(delay_seconds: float) -> void:
	if replayEndTimer != null and is_instance_valid(replayEndTimer):
		replayEndTimer.stop()
		replayEndTimer.queue_free()

	replayEndTimer = Timer.new()
	replayTimers.append(replayEndTimer)
	add_child(replayEndTimer)
	replayEndTimer.one_shot = true
	replayEndTimer.timeout.connect(func():
		if replayPlaying:
			_finish_replay(true)
	)
	replayEndTimer.wait_time = max(delay_seconds + 2.5, 1.0)
	replayEndTimer.start()
	
func _finish_replay(finalize_scores: bool = true) -> void:
	for timer in replayTimers:
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
	replayTimers.clear()
	replayEndTimer = null

	clearBalls()

	if finalize_scores:
		if turnNum == 3:
			setScore(1, score1)
			setScore(2, score2)
			isTurn = true
		elif turnNum >= 5:
			setScore(1, skip_score1)
			setScore(2, skip_score2)
			game_over = true
			isTurn = not spectator_mode
			showWinner()

	timeRemainingLabel.text = "00:00"
	hideUI()
	replayPlaying = false
	replayFinished = true
	elapsedTime = 0.0
	stop_waiting_animation()

	refresh_ui_state()
	
func _get_active_hoop_collision_root() -> Node3D:
	if game_mode == "h" and is_instance_valid(moving_hoop_collision):
		return moving_hoop_collision
	return static_hoop_collision


func _get_active_hoop_center() -> Vector3:
	var root := _get_active_hoop_collision_root()
	if not is_instance_valid(root):
		return Vector3.ZERO

	var total := Vector3.ZERO
	var count := 0

	for child in root.get_children():
		if child is Node3D and child.name.begins_with("HoopCollisionSphere"):
			total += (child as Node3D).global_position
			count += 1

	if count <= 0:
		return root.global_position

	return total / float(count)


func _check_ball_score_crossing(ball: BasketballBall) -> void:
	if not is_instance_valid(ball):
		return
	if ball.get_meta("score_counted", false):
		return

	var prev_pos: Vector3 = ball.get_meta("last_score_pos", ball.global_position)
	var curr_pos: Vector3 = ball.global_position
	ball.set_meta("last_score_pos", curr_pos)

	var hoop_center := _get_active_hoop_center()

	if prev_pos.y <= hoop_center.y:
		return
	if curr_pos.y > hoop_center.y:
		return
	if ball.linear_velocity.y > SCORE_MIN_DOWN_VELOCITY:
		return

	var dx := absf(curr_pos.x - hoop_center.x)
	var dz := absf(curr_pos.z - hoop_center.z)

	if dx <= SCORE_RADIUS_X and dz <= SCORE_RADIUS_Z:
		ball.set_meta("score_counted", true)

		var ball_player: int = int(ball.get_meta("player_num", 0))
		if ball_player != 0:
			incrementScore(ball_player)
	
func skipReplay():
	_finish_replay(true)
	
func refresh_ui_state() -> void:
	if gamePlaying or replayPlaying:
		print("Game or Replay Playing")
		round_container.visible = false
		return

	var other_player: int = 2 if player == 1 else 1

	if turnNum != null and turnNum >= 3 and replayFinished == false:
		var r_self = getReplay(player)
		var r_other = getReplay(other_player)

		if spectator_mode:
			r_self = getReplay(1)
			r_other = getReplay(2)

		if not isNullOrEmpty(r_self) and not isNullOrEmpty(r_other):
			print("Starting replay playback")
			stop_waiting_animation()
			round_container.visible = false

			ballNum = {1: 1, 2: 1}

			if turnNum >= 5:
				print("Turn Number > 5")
				setScore(1, score1)
				setScore(2, score2)
			else:
				print("Turn Number < 5")
				setScore(1, 0)
				setScore(2, 0)

			hoop_time = 0
			_hoop_acc = 0.0
			elapsedTime = 0.0
			if hoop_center_tween and hoop_center_tween.is_running():
				hoop_center_tween.kill()
			if is_instance_valid(moving_hoop_root):
				_set_moving_hoop_x(0.0)

			clearBalls()
			spawnBall(1)
			spawnBall(2)
			print("PLAYING REPLAY>>>")
			var replay1_end: float = playReplay(1, r_self if spectator_mode else getReplay(1))
			var replay2_end: float = playReplay(2, r_other if spectator_mode else getReplay(2))
			_schedule_replay_auto_finish(max(replay1_end, replay2_end))

			skip_button.visible = true
			return

		if not isNullOrEmpty(r_self) and isNullOrEmpty(r_other):
			print("We already played, opponent replay missing")
			round_container.visible = false
			skip_button.visible = false

			if turnNum >= 4:
				setScore(1, skip_score1 if skip_score1 != null else 0)
				setScore(2, skip_score2 if skip_score2 != null else 0)
			else:
				setScore(1, score1 if score1 != null else 0)
				setScore(2, score2 if score2 != null else 0)

			if allow_waiting_from_loaded_data:
				start_waiting_animation()

			return

		print("Opponent has not played yet, allowing us to play")
		stop_waiting_animation()

	if isTurn == false:
		print("Is Turn False")
		round_container.visible = false
		skip_button.visible = false

		if turnNum != null:
			if turnNum >= 4:
				setScore(1, skip_score1 if skip_score1 != null else 0)
				setScore(2, skip_score2 if skip_score2 != null else 0)
			else:
				setScore(1, score1 if score1 != null else 0)
				setScore(2, score2 if score2 != null else 0)

		if not spectator_mode and allow_waiting_from_loaded_data:
			start_waiting_animation()
		return

	print("Is Turn True")
	stop_waiting_animation()

	if turnNum >= 3:
		print("Turn >= 3")

		if spectator_mode:
			round_container.visible = false
			waiting_blur.visible = false
			return

		if turnNum >= 5:
			game_over = true
			showWinner()
			return

		setScore(1, score1)
		setScore(2, score2)

		waiting_blur.visible = true
		round_label.text = "Round 2"
		print("Round 2 Shown")
		round_container.visible = true
		return

	round_label.text = "Round 1"
	waiting_blur.visible = true
	print("Round 1 Shown")
	round_container.visible = true

func spawnBall(player_num: int, didGoInReplay = null) -> BasketballBall:
	if appPlugin != null:
		if (turnNum < 3) or (didGoInReplay != null and turnNum == 3):
			appPlugin.srand48(player_num, seed)
		else:
			appPlugin.srand48(player_num, seed2)
	else:
		randomize()

	if ballNum[player_num] >= 1:
		var i: int = ballNum[player_num]
		while true:
			if appPlugin != null:
				appPlugin.drand48(player_num)
			else:
				randf()
			if i == 1:
				break
			i -= 1

	var new_ball: BasketballBall = get_node("Ball").duplicate()
	var ball_mesh: MeshInstance3D = new_ball.get_child(1)

	var roll_source: float = appPlugin.drand48(player_num) if appPlugin != null else randf()
	var pitch_source: float = appPlugin.drand48(player_num) if appPlugin != null else randf()
	var yaw_source: float = appPlugin.drand48(player_num) if appPlugin != null else randf()

	var roll: float = roll_source * 8.0 + -9.0
	var pitch: float = pitch_source * 20.0 + 70.0
	var yaw: float = yaw_source * 10.0 + -5.0

	var x_rand: float = appPlugin.drand48(player_num) if appPlugin != null else randf()
	var x_pos: float = x_rand * 0.66 + -0.33
	if player_num == 2:
		x_pos *= -1

	new_ball.set_player(player_num)

	if didGoInReplay != null:
		new_ball.set_didGoInReplay(didGoInReplay)

	new_ball.collision_layer = player_num
	new_ball.collision_mask = player_num

	new_ball.rotation = Vector3(roll, pitch, yaw)
	new_ball.position = Vector3(x_pos, -0.45, -1)
	new_ball.get_child(0).disabled = false

	new_ball.axis_lock_angular_x = true
	new_ball.axis_lock_angular_y = true
	new_ball.axis_lock_angular_z = true
	new_ball.angular_velocity = Vector3.ZERO

	new_ball.freeze = false
	new_ball.sleeping = false
	new_ball.visible = true

	if player_num != player:
		ball_mesh.material_override = ball_mesh.material_override.duplicate()
		ball_mesh.material_override.albedo_color = Color(1, 1, 1, 0.75)

	new_ball.name = "Ball_P" + str(player_num) + "_" + str(ballNum[player_num])

	add_child(new_ball)
	new_ball.set_meta("player_num", player_num)
	new_ball.set_meta("score_counted", false)
	new_ball.set_meta("last_score_pos", new_ball.global_position)
	ballNum[player_num] += 1
	currentBall[player_num] = new_ball
	return new_ball

var my_player
func _set_game_data(new_replay: String, saved: bool = false):
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: " + str(parsed))
	loaded_has_winner = parsed.has("winner") and not isNullOrEmpty(str(parsed["winner"]))
	winner_sent = loaded_has_winner
	
	game_mode = str(parsed.get("mode", "n"))
	_apply_basketball_mode()
	
	if gamePlaying == true:
		print("Message received during game, saving!")
		receivedMessage = new_replay
		return
	
	turnNum = int(parsed["num"])
	isTurn = parsed["isYourTurn"]
	player = int(parsed["player"])
	print("Turn Num: ", turnNum, " IsTurn: ", isTurn, " Player: ", player)

	# Round 1 needs to be playable by both the sender and receiver.
	# After round 1, keep the original opponent/player flip behavior.
	if turnNum == 1:
		isTurn = true
	elif isTurn:
		player = 2 if player == 1 else 1

	stop_waiting_animation()

	print("YOU ARE PLAYER " + str(player))
	my_player = parsed.get("myPlayerId", null)
	
	var player1_id := str(parsed.get("player1", ""))
	var player2_id := str(parsed.get("player2", ""))
	var my_player_id := str(my_player)

	spectator_mode = false
	if my_player_id != "" and player1_id != "" and player2_id != "":
		if my_player_id != player1_id and my_player_id != player2_id:
			spectator_mode = true

	if spectator_mode:
		player = 1
		isTurn = false
		gamePlaying = false
		print("SPECTATOR MODE ACTIVE")
		if is_instance_valid(spectator_label):
			spectator_label.show()
	else:
		if is_instance_valid(spectator_label):
			spectator_label.hide()

	if spectator_mode:
		if parsed.has("avatar1") and is_instance_valid(player_avatar_display):
			var p1_data: Dictionary = GameUtils._parse_avatar_string(str(parsed["avatar1"]))
			player_avatar_display.call_deferred("update_avatar_from_data", p1_data)
		if parsed.has("avatar2") and is_instance_valid(opp_avatar_display):
			var p2_data: Dictionary = GameUtils._parse_avatar_string(str(parsed["avatar2"]))
			opp_avatar_display.call_deferred("update_avatar_from_data", p2_data)
	else:
		var opponent_avatar_key := "avatar2" if player == 1 else "avatar1"
		if parsed.has(opponent_avatar_key):
			var avatar_string: String = str(parsed[opponent_avatar_key])
			var opponent_data: Dictionary = GameUtils._parse_avatar_string(avatar_string)
			if is_instance_valid(opp_avatar_display):
				opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	if saved:
		if player == 1:
			score2 = int(parsed["score2"])
			skip_score2 = int(parsed["skip_score2"])
			replay2 = parsed["replay2"] if "replay2" in parsed else null
			replay4 = parsed["replay4"] if "replay4" in parsed else null
		else:
			score1 = int(parsed["score1"])
			skip_score1 = int(parsed["skip_score1"])
			replay = parsed["replay"] if "replay" in parsed else null
			replay3 = parsed["replay3"] if "replay3" in parsed else null
	else:
		seed = int(parsed["seed"])
		seed2 = int(parsed["seed2"])
		score1 = int(parsed["score1"])
		score2 = int(parsed["score2"])
		skip_score1 = int(parsed["skip_score1"])
		skip_score2 = int(parsed["skip_score2"])
		replay = parsed["replay"] if "replay" in parsed else null
		replay2 = parsed["replay2"] if "replay2" in parsed else null
		replay3 = parsed["replay3"] if "replay3" in parsed else null
		replay4 = parsed["replay4"] if "replay4" in parsed else null
	
	receivedMessage = null
	gameDataSet = true
	
	if turnNum >= 5:
		if isNullOrEmpty(replay3) and not isNullOrEmpty(replay):
			replay3 = replay
		if isNullOrEmpty(replay4) and not isNullOrEmpty(replay2):
			replay4 = replay2

	if not saved:
		allow_waiting_from_loaded_data = true
		refresh_ui_state()
		allow_waiting_from_loaded_data = false

func sendGameData() -> void:
	turnNum += 1
	var scoreKey: String
	var replayKey: String
	if turnNum <= 3:
		scoreKey = "score2" if player == 2 else "score1"
		replayKey = "replay2" if player == 2 else "replay"
	else:
		scoreKey = "skip_score2" if player == 2 else "skip_score1"
		replayKey = "replay4" if player == 2 else "replay3"
		
	var gameData = {
		scoreKey: str(myScore),
		replayKey: myReplay.substr(0, len(myReplay)-1),
		"round": "1" if turnNum+1 <= 3 else "2"
	}
	
	if turnNum >= 5:
		var oppFinalScore : int = skip_score1 if player == 2 else skip_score2
		var winNum = 1 if myScore > oppFinalScore else (-1 if myScore < oppFinalScore else 0)
		gameData["winner"] = str(my_player) + "|" + str(winNum)
		print("My Final Score: ", myScore, " Opp Final Score: ", oppFinalScore, " winNum: ", winNum)
	if game_over:
		stop_waiting_animation()
		showWinner()
	else:
		play_sent_animation()
	var avatar_key := ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		gameData[avatar_key] = player_avatar_display.get_avatar_data_string()
	print("Sending game data: " + JSON.stringify(gameData))
	var game_data = JSON.stringify(gameData)
	appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(game_data)
	else:
		print("App not connected! " + game_data)
	
func start_button_pressed():
	if spectator_mode:
		return
	round_container.visible = false
	waiting_blur.visible = false
	print("Start Button Pressed")
	startGame()
	
func startGame() -> void:
	ballNum = {1: 1, 2: 1}
	myReplay = ""
	elapsedTime = 0.0
	gamePlaying = true
	replayPlaying = false
	replayFinished = false
	receivedMessage = null
	replayTimers.clear()
	hoop_time = 0
	_hoop_acc = 0.0
	if hoop_center_tween and hoop_center_tween.is_running():
		hoop_center_tween.kill()
	if is_instance_valid(moving_hoop_root):
		_set_moving_hoop_x(0.0)
	spawnBall(player)
	
func _haptic_explosion(strength: float = 0.35, duration_ms: int = 22) -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return

	strength = clampf(strength, 0.0, 1.0)
	Input.vibrate_handheld(duration_ms, strength)
	
func incrementScore(player_num: int) -> void:
	if player_num == player:
		myScore += 1
		youScoreLabel.text = str(myScore).pad_zeros(2)
		_haptic_explosion()
	else:
		oppScore += 1
		oppScoreLabel.text = str(oppScore).pad_zeros(2)
		
func setScore(player_num: int, score: int) -> void:
	print("SETTING SCORE FOR PLAYER " + str(player_num) + " to " + str(score))
	if player_num == player:
		_haptic_explosion()
		myScore = score
		print("MY SCORE: ", myScore)
		youScoreLabel.text = str(myScore).pad_zeros(2)
	else:
		oppScore = score
		print("OPP SCORE: ", oppScore)
		oppScoreLabel.text = str(oppScore).pad_zeros(2)
	
func isNullOrEmpty(str) -> bool:
	if str == null:
		return true
	return str.length() == 0
	
func clearBalls() -> void:
	for node in get_children():
		if node.name.begins_with("Ball_P"):
			node.queue_free()
	currentBall[1] = null
	currentBall[2] = null
	
func hideUI() -> void:
	round_container.visible = false
	skip_button.visible = false
	
func _physics_process(delta: float) -> void:
	if game_mode == "h" and is_instance_valid(moving_hoop_root):
		if gamePlaying or replayPlaying:
			if hoop_center_tween and hoop_center_tween.is_running():
				hoop_center_tween.kill()

			_hoop_acc += delta * 60.0

			while _hoop_acc >= 1.0:
				hoop_time += 1
				_hoop_acc -= 1.0

			_set_moving_hoop_x(_hard_hoop_x_from_tick(hoop_time))

	if gamePlaying:
		for node in get_children():
			if node is BasketballBall and node.name.begins_with("Ball_P"):
				_check_ball_score_crossing(node)
				
func _process(delta: float) -> void:
	if game_mode == "h" and is_instance_valid(moving_hoop_root):
		if not gamePlaying and not replayPlaying:
			hoop_time = 0
			_hoop_acc = 0.0

			if abs(moving_hoop_root.position.x) > 0.001:
				if hoop_center_tween == null or not hoop_center_tween.is_running():
					hoop_center_tween = create_tween()
					hoop_center_tween.tween_property(
						moving_hoop_root,
						"position:x",
						0.0,
						0.35
					)
			else:
				_set_moving_hoop_x(0.0)
	
	if gamePlaying or replayPlaying:
		elapsedTime += delta
		timeRemainingLabel.text = "00:" + str(int(ceil(45.0 - elapsedTime))).pad_zeros(2)
		if int(ceil(45.0 - elapsedTime)) <= 0:
			elapsedTime = 0.0
			gamePlaying = false
			var wasReplayPlaying = replayPlaying
			replayPlaying = false
			await get_tree().create_timer(3).timeout
			
			if receivedMessage != null:
				print("Received message during game! Setting new data..")
				_set_game_data(receivedMessage, true)
			
			if wasReplayPlaying == false:
				print("SENDING DATA")
				sendGameData()
				if player == 1:
					if turnNum <= 3:
						score1 = myScore
						replay = myReplay
					skip_score1 = myScore
					replay3 = myReplay
				if player == 2:
					if turnNum <= 3:
						score2 = myScore
						replay2 = myReplay
					skip_score2 = myScore
					replay4 = myReplay
			else:
				_finish_replay(true)
				return
				
			clearBalls()
			isTurn = false			
			print("ready up!")
			refresh_ui_state()
				
func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		print("Warning: sent_label is not valid for play_sent_animation.")
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
	
