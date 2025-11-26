extends Node3D
class_name basketball

var elapsedTime: float = 0.0

const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")
const MIN_DRAG_DISTANCE := 30.0

@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var winner_label: Label = %WinLossLabel
@onready var waiting_label: Label = %waitingLabel
@onready var sent_label: Label = %SentLabel
@onready var waiting_blur: ColorRect = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var spectator_label: Label = %SpecLabel
@onready var start_button: Button = %StartButton
@onready var skip_button: TextureButton = %SkipButton
@onready var round_container: PanelContainer = %RoundUI
@onready var round_label: Label = %RoundLabel

var replayTimers: Array[Timer] = []
var replayPlaying = false
var replayFinished = false
var gamePlaying = false
var gameDataSet = false
var game_over = false
var sent_tween: Tween
var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
var spectator_mode: bool = false

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

var appPlugin = null
var has_connected = false
var dev_data = ""

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

func _ready() -> void:
	timeRemainingLabel = get_node("Scoreboard/Time")
	youScoreLabel = get_node("Scoreboard/YouScore")
	oppScoreLabel = get_node("Scoreboard/OppScore")
	appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		if not has_connected:
			print("App plugin is available")
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			return
	else:
		print("App plugin is not available")
		#dev_data = '{"isYourTurn": true, "myPlayerId": "9a6e234c-2244-4621-a08f-38acd277a2e0", "skip_score1": "0", "skip_score2": "0", "player": "2", "score1": "0", "score2": "0", "sender": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb", "avatar2": "body,3|eyes,6|mouth,3|acc,0|wins,0|bg_color,0.933333,0.407843,0.647059|body_color,0.968627,0.811765,0.333333|glasses,0|stache,0|backdrop,0|hair,0|clothes,2|hair_color,0.505882,0.725490,0.254902|clothes_color,0.686657,0.686657,0.686657", "player2": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb", "id": "G4m1HA79uZDuAtHY", "ios": "26.1", "num": "1", "game": "basketball", "mode": "n", "seed": "-1417153476", "tver": "5", "build": "28R", "round": "1", "seed2": "-16614620", "start": "", "version": "5", "caption": "Let\'s play Basketball!", "game_name": "Basketball", "replay": ""}'
		dev_data = '{"isYourTurn": true, "myPlayerId": "9a6e234c-2244-4621-a08f-38acd277a2e0", "skip_score1": "18", "skip_score2": "46", "player": "2", "score1": "18", "score2": "23", "sender": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb", "avatar2": "body,3|eyes,6|mouth,3|acc,0|wins,0|bg_color,0.933333,0.407843,0.647059|body_color,0.968627,0.811765,0.333333|glasses,0|stache,0|backdrop,0|hair,0|clothes,2|hair_color,0.505882,0.725490,0.254902|clothes_color,0.686657,0.686657,0.686657", "player2": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb", "id": "G4m1HA79uZDuAtHY", "ios": "26.1", "num": "1", "game": "basketball", "mode": "n", "seed": "-1417153476", "tver": "5", "build": "28R", "round": "1", "seed2": "-16614620", "start": "", "version": "5", "caption": "Let\'s play Basketball!", "game_name": "Basketball", "replay": "60,0.264,0,0|115,-0.392,0,1|166,0.120,0,0|218,-0.078,0,1|274,0.576,0,0|332,-0.401,0,0|391,0.232,0,0|445,0.418,0,1|501,0.170,0,0|569,-0.418,0,0|630,0.157,0,0|681,-0.284,0,0|738,0.247,0,1|796,0.024,0,0|854,0.249,0,1|912,-0.427,0,0|969,0.184,0,1|1034,0.478,0,0|1089,-0.010,0,0|1143,0.277,0,0|1197,-0.259,0,1|1251,0.252,0,1|1309,-0.392,0,0|1367,-0.218,0,0|1433,0.596,0,1|1486,-0.083,0,1|1541,0.304,0,0|1593,-0.206,0,0|1644,-0.308,0,0|1696,-0.362,0,1|1747,-0.203,0,0|1803,-0.142,0,0|1864,0.406,0,0|1914,-0.225,0,1|1967,-0.138,0,0|2024,-0.361,0,0|2078,0.036,0,1|2136,-0.414,0,1|2195,0.100,0,0|2256,0.580,0,1|2309,-0.239,0,0|2364,0.400,0,1|2416,-0.113,0,1|2474,-0.001,0,0|2529,0.261,0,1|2594,-0.402,0,0|2640,0.194,0,0"}'
		_set_game_data(dev_data, true)
	if is_instance_valid(start_button):
		start_button.pressed.connect(start_button_pressed)
		print("Connected Start Button")
	if is_instance_valid(skip_button):
		skip_button.pressed.connect(skipReplay)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	if not gameDataSet:
		return
		
	var other_player: int
	if player == 1:
		other_player = 2
	elif player == 2:
		other_player = 1
		
	if has_connected or dev_data != "":
		print("Initial")
		if turnNum >= 3:
			print("Option 1")
			if isNullOrEmpty(getReplay(other_player)):
				print("Option 2")
				start_waiting_animation()
			elif replayFinished == false:
				print("Option 3")
				stop_waiting_animation()
				ballNum = {1: 1, 2: 1}
				if turnNum == 5:
					print("Option 4")
					setScore(1, score1)
					setScore(2, score2)
				else:
					print("Option 5")
					setScore(1, 0)
					setScore(2, 0)
				spawnBall(1)
				spawnBall(2)
				playReplay(1, getReplay(1))
				playReplay(2, getReplay(2))
				skip_button.visible = true
			else:
				print("Option 6")
				if turnNum == 5:
					print("Game Over")
					game_over = true
					showWinner()
				else:
					stop_waiting_animation()
					waiting_blur.visible = true
					round_label.text = "Round 2"
					print("Round 2 Popup")
					round_container.visible = true
		elif isNullOrEmpty(getReplay(other_player)) and not isNullOrEmpty(getReplay(player)):
			print("Option 7")
			start_waiting_animation()
		else:
			stop_waiting_animation()
			round_label.text = "Round 1"
			print("Round 1 Popup")
			waiting_blur.visible = true
			round_container.visible = true

var didIWin = false
func showWinner():
	if myScore == oppScore:
		winner_label.set_text("DRAW!")
		didIWin = 0
	elif myScore > oppScore:
		winner_label.set_text("YOU WIN!")
		winner_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		_show_win_burst(player_avatar_display)
		didIWin = 1
	else:
		winner_label.set_text("YOU LOSE!")
		winner_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
		_show_win_burst(opp_avatar_display)
		didIWin = -1
	winner_label.visible = true
		
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
func _input(event: InputEvent) -> void:
	if player != null and gamePlaying and event is InputEventMouseButton and currentBall[player] != null:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
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

func playReplay(player_num: int, replay_str: String):	
	replayPlaying = true
	var replayShots = replay_str.split('|')
	var replayBallNum = 0
	for shot in replayShots:
		var shotSplit = shot.split(',')

		var timeDelay: float = float(shotSplit[0]) / 60.0
		var x_delta: float = float(shotSplit[1])
		var did_go_in: bool = bool(int(shotSplit[3]))
		
		var shotTimer = Timer.new()
		replayTimers.append(shotTimer)
		self.add_child(shotTimer)
		shotTimer.one_shot = true
		shotTimer.timeout.connect(func(): currentBall[player_num].shoot(x_delta))
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
		
func skipReplay():
	for timer in replayTimers:
		timer.stop()
		timer.queue_free()
	replayTimers.clear()
	
	if currentBall[1] != null:
		currentBall[1].queue_free()
		currentBall[1] = null
		
	if currentBall[2] != null:
		currentBall[2].queue_free()
		currentBall[2] = null
	
	if turnNum == 3:
		setScore(1, score1)
		setScore(2, score2)
	elif turnNum == 5:
		setScore(1, skip_score1)
		setScore(2, skip_score2)
		
	timeRemainingLabel.text = "00:00"
		
	hideUI()
	replayPlaying = false
	replayFinished = true
	_ready()
		
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
	var ball_CSGSphere3D: CSGSphere3D = new_ball.get_child(1)

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
	ball_CSGSphere3D.collision_layer = player_num
	ball_CSGSphere3D.collision_mask = player_num

	new_ball.rotation = Vector3(roll, pitch, yaw)
	new_ball.position = Vector3(x_pos, -0.45, -1)
	new_ball.get_child(0).disabled = false
	new_ball.freeze = false
	new_ball.set_visible(true)

	if player_num != player:
		ball_CSGSphere3D.material_override = ball_CSGSphere3D.material_override.duplicate()
		ball_CSGSphere3D.material_override.albedo_color = Color(1, 1, 1, 0.75)

	new_ball.name = "Ball_P" + str(player_num) + "_" + str(ballNum[player_num])

	add_child(new_ball)
	ballNum[player_num] += 1
	currentBall[player_num] = new_ball
	return new_ball

var my_player
func _set_game_data(new_replay: String, saved: bool = false):
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: " + str(parsed))
	
	if gamePlaying == true:
		print("Message received during game, saving!")
		receivedMessage = new_replay
		return
	
	isTurn = parsed["isYourTurn"]
	player = int(parsed["player"])
	
	if isTurn:
		player = 2 if player == 1 else 1
		stop_waiting_animation()
	else:
		start_waiting_animation()
	print("YOU ARE PLAYER " + str(player))	
	my_player = parsed.get("myPlayerId", null)
	if saved:
		turnNum = int(parsed["num"])
		if player == 1:
			score2 = int(parsed["score2"])
			skip_score2 = int(parsed["skip_score2"])
			replay2 = parsed["replay2"] if "replay2" in parsed else null
			replay4 = parsed["replay4"] if "replay4" in parsed else null
		else:
			score1 = int(parsed["score1"])
			skip_score1 = int(parsed["skip_score1"])
			replay = parsed["replay"]
			replay3 = parsed["replay3"] if "replay3" in parsed else null
	else:
		seed = int(parsed["seed"])
		seed2 = int(parsed["seed2"])
		turnNum = int(parsed["num"])
		score1 = int(parsed["score1"])
		score2 = int(parsed["score2"])
		skip_score1 = int(parsed["skip_score1"])
		skip_score2 = int(parsed["skip_score2"])
		replay = parsed["replay"]
		replay2 = parsed["replay2"] if "replay2" in parsed else null
		replay3 = parsed["replay3"] if "replay3" in parsed else null
		replay4 = parsed["replay4"] if "replay4" in parsed else null
	
	receivedMessage = null
	gameDataSet = true
	if not saved:
		_ready()
	
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
	if game_over:
		stop_waiting_animation()
		showWinner()
		gameData["winner"] = my_player + "|" + ("1" if didIWin else "-1")
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
	spawnBall(player)
	
func incrementScore(player_num: int) -> void:
	if player_num == player:
		myScore += 1
		youScoreLabel.text = str(myScore).pad_zeros(2)
	else:
		oppScore += 1
		oppScoreLabel.text = str(oppScore).pad_zeros(2)
		
func setScore(player_num: int, score: int) -> void:
	print("SETTING SCORE FOR PLAYER " + str(player_num) + " to " + str(score))
	if player_num == player:
		myScore = score
		youScoreLabel.text = str(myScore).pad_zeros(2)
	else:
		oppScore = score
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

func _process(delta: float) -> void:
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
				hideUI()
				replayTimers.clear()
				replayPlaying = false
				replayFinished = true
				if turnNum == 3:
					setScore(1, score1)
					setScore(2, score2)
				elif turnNum == 5:
					setScore(1, skip_score1)
					setScore(2, skip_score2)
				
			clearBalls()
			
			print("ready up!")
			_ready()
				
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
			start_waiting_animation()
	)
	
func _on_dot_timer_timeout():
	if not is_instance_valid(waiting_label):
		print("Warning: waiting_label is not valid in _on_dot_timer_timeout.")
		return
	print("Starting Dot Timer Timeout")
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots

func start_waiting_animation():
	if not is_instance_valid(waiting_label) or not is_instance_valid(waiting_blur) or not is_instance_valid(dot_timer):
		print("Warning: Waiting animation nodes are not valid.")
		return
	if spectator_mode:
		return

	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true
	waiting_blur.visible = true

	waiting_label.modulate.a = 0.0
	waiting_blur.modulate.a = 0.0

	var tween_wait_in = create_tween().set_parallel(true)
	tween_wait_in.tween_property(waiting_label, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_property(waiting_blur, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_callback(func():
		dot_timer.start()
	)

func stop_waiting_animation():
	if is_instance_valid(dot_timer):
		dot_timer.stop()
	if is_instance_valid(waiting_label):
		waiting_label.visible = false
		waiting_label.modulate.a = 1.0
	if is_instance_valid(waiting_blur):
		waiting_blur.visible = false
		waiting_blur.modulate.a = 1.0

func _parse_avatar_string(data_string: String) -> Dictionary:
	var hair_map: Array     = AvatarThumbnail.avatar_hair_regions.keys()
	var body_map: Array     = AvatarThumbnail.avatar_fshape_regions.keys()
	var eyes_map: Array     = AvatarThumbnail.avatar_eyes_regions.keys()
	var mouth_map: Array    = AvatarThumbnail.avatar_mouth_regions.keys()
	var clothing_map: Array = AvatarThumbnail.avatar_clothing_regions.keys()
	var backdrop_map: Array = ["Plain"]
	backdrop_map.append_array(AvatarThumbnail.avatar_background_regions.keys())

	var data: Dictionary = {
		"fshape_style":   body_map[0]     if body_map.size()     > 0 else "Default",
		"hair_style":     hair_map[0]     if hair_map.size()     > 0 else "hair1",
		"eyes_style":     eyes_map[0]     if eyes_map.size()     > 0 else "eyes1",
		"mouth_style":    mouth_map[0]    if mouth_map.size()    > 0 else "mouth1",
		"clothing_style": clothing_map[0] if clothing_map.size() > 0 else "clothing1",
		"bg_style":       "Plain",
		"fshape_color":   Color(0.88, 0.67, 0.41),
		"hair_color":     Color(0.17, 0.14, 0.17),
		"clothing_color": Color(0.63, 0.24, 0.24),
		"bg_color":       Color(0.31, 0.36, 0.54),
	}

	if data_string.is_empty():
		return data

	var read_color = func(vals: Array) -> Color:
		if vals.size() >= 3:
			return Color(vals[0].to_float(), vals[1].to_float(), vals[2].to_float())
		return Color.WHITE

	for part in data_string.split("|", false):
		var key_value := part.split(",", false)
		if key_value.size() < 2:
			continue
		var key := key_value[0]

		match key:
			"fshape", "body":
				var i := key_value[1].to_int()
				if i >= 0 and i < body_map.size():
					data["fshape_style"] = String(body_map[i])

			"fshape_color", "body_color":
				data["fshape_color"] = read_color.call(key_value.slice(1))

			"hair":
				var i := key_value[1].to_int()
				if i >= 0 and i < hair_map.size():
					data["hair_style"] = String(hair_map[i])

			"hair_color":
				data["hair_color"] = read_color.call(key_value.slice(1))

			"eyes":
				var i := key_value[1].to_int()
				if i >= 0 and i < eyes_map.size():
					data["eyes_style"] = String(eyes_map[i])

			"mouth":
				var i := key_value[1].to_int()
				if i >= 0 and i < mouth_map.size():
					data["mouth_style"] = String(mouth_map[i])

			"clothes":
				var i := key_value[1].to_int()
				if i >= 0 and i < clothing_map.size():
					data["clothing_style"] = String(clothing_map[i])

			"clothes_color":
				data["clothing_color"] = read_color.call(key_value.slice(1))

			"bg_color":
				data["bg_color"] = read_color.call(key_value.slice(1))

			"backdrop":
				var i := key_value[1].to_int()
				if i >= 0 and i < backdrop_map.size():
					data["bg_style"] = String(backdrop_map[i])
			_:
				pass
	return data
	
func _ensure_avatar_wrapper(avatar: Control) -> Control:
	var parent: Node = avatar.get_parent()
	if parent == null:
		return null

	if parent is Control and not (parent is Container):
		return parent as Control

	var wrapper: Control = Control.new()
	wrapper.name = "%s_Wrap" % avatar.name
	wrapper.size_flags_horizontal = avatar.size_flags_horizontal
	wrapper.size_flags_vertical = avatar.size_flags_vertical
	wrapper.custom_minimum_size = avatar.get_combined_minimum_size()

	var idx: int = avatar.get_index()
	parent.add_child(wrapper)
	parent.move_child(wrapper, idx)

	avatar.reparent(wrapper)
	avatar.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar.offset_left = 0.0
	avatar.offset_top = 0.0
	avatar.offset_right = 0.0
	avatar.offset_bottom = 0.0

	avatar.item_rect_changed.connect(func():
		if is_instance_valid(wrapper):
			wrapper.custom_minimum_size = avatar.get_combined_minimum_size()
	)

	return wrapper

func _show_win_burst(avatar: Control) -> void:
	var wrapper: Control = _ensure_avatar_wrapper(avatar)
	if not is_instance_valid(wrapper):
		return

	var existing: Node = wrapper.get_node_or_null("AvatarWinAnim")
	if existing != null:
		return

	var anim_instance: Control = AvatarWinAnimScene.instantiate() as Control
	anim_instance.name = "AvatarWinAnim"
	wrapper.add_child(anim_instance)

	var avatar_idx: int = avatar.get_index()
	wrapper.move_child(anim_instance, avatar_idx)

	anim_instance.z_as_relative = false
	avatar.z_as_relative = false
	anim_instance.z_index = 0
	avatar.z_index = max(avatar.z_index, 1)

	anim_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	anim_instance.offset_left = -52.0
	anim_instance.offset_right = 52.0
	anim_instance.offset_top = -43.0
	anim_instance.offset_bottom = 43.0

	(anim_instance as Node).call("set_color", Color(1.0, 0.84, 0.0))
	(anim_instance as Node).call("play", 0.05)
