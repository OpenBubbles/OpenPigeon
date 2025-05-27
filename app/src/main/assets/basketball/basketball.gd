extends Node3D
class_name basketball

var elapsedTime: float = 0.0

var replayTimers: Array[Timer] = []
var replayPlaying = false
var replayFinished = false
var gamePlaying = false
var gameDataSet = false

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
		if player == null or replay == null:
			print("App plugin is not available")
			return
		
	if not gameDataSet:
		return
		
	var other_player: int
	if player == 1:
		other_player = 2
	elif player == 2:
		other_player = 1
		
	if has_connected:
		if turnNum >= 3:
			if isNullOrEmpty(getReplay(other_player)):
				setWaiting(true)
			elif replayFinished == false:
				setWaiting(false)
				ballNum = {1: 1, 2: 1}
				if turnNum == 5:
					setScore(1, score1)
					setScore(2, score2)
				else:
					setScore(1, 0)
					setScore(2, 0)
				spawnBall(1)
				spawnBall(2)
				playReplay(1, getReplay(1))
				playReplay(2, getReplay(2))
				get_node("SubViewportContainer/SubViewport/SkipButton").visible = true
			else:
				if turnNum == 5:
					showWinner()
				else:
					setWaiting(false)
					get_node("SubViewportContainer/SubViewport/BlackBackground").visible = true
					get_node("SubViewportContainer/SubViewport/Round2UI").visible = true
		elif isNullOrEmpty(getReplay(other_player)) and not isNullOrEmpty(getReplay(player)):
			setWaiting(true)
		else:
			setWaiting(false)
			get_node("SubViewportContainer/SubViewport/BlackBackground").visible = true
			get_node("SubViewportContainer/SubViewport/Round1UI").visible = true
		
func showWinner():
	if myScore == oppScore:
		get_node("SubViewportContainer/SubViewport/winnerLabel").get_child(0).set_text("[center]DRAW![/center]")
	elif myScore > oppScore:
		get_node("SubViewportContainer/SubViewport/winnerLabel").get_child(0).set_text("[center]YOU WIN![/center]")
	else:
		get_node("SubViewportContainer/SubViewport/winnerLabel").get_child(0).set_text("[center]YOU LOSE![/center]")
	get_node("SubViewportContainer/SubViewport/winnerLabel").visible = true
		
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
		if event.button_index == 1:
			if event.pressed:
				drag_start_pos = event.position
				dragging = true
			else:
				if dragging:
					var drag_end_pos = event.position
					var delta = drag_end_pos - drag_start_pos
					
					#print("X delta: " + str(delta.x))
					
					var x_delta_lerp = interpolate_x_delta(delta.x)
					#print("X delta interpolated: " + str(x_delta_lerp))
					
					currentBall[player].shoot(x_delta_lerp)
					currentBall[player] = null
					await get_tree().create_timer(0.25).timeout
					
					if gamePlaying:
						spawnBall(player)
					
					dragging = false
					

func setWaiting(isWaiting: bool):
	hideUI()
	if isWaiting:
		get_node("SubViewportContainer/SubViewport/waitingLabel").visible = true
		get_node("SubViewportContainer/SubViewport/BlackBackground").visible = true
	self.isWaiting = isWaiting
	

func interpolate_x_delta(value: float) -> float:
	# Normalize the value to 0.0 - 1.0
	var t = inverse_lerp(-200.0, 200.0, value)
	# Interpolate to the new range
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
		
	timeRemainingLabel.text = "0:00"
		
	hideUI()
	replayPlaying = false
	replayFinished = true
	_ready()
		
func spawnBall(player_num: int, didGoInReplay = null) -> BasketballBall:
	if (turnNum < 3) or (didGoInReplay != null and turnNum == 3):
		appPlugin.srand48(player_num, seed)
	else:
		appPlugin.srand48(player_num, seed2)
	
	if (ballNum[player_num] >= 1):
		var i = ballNum[player_num]
		while true:
			appPlugin.drand48(player_num)
			if i == 1:
				break
			i -= 1
	
	var new_ball: BasketballBall = get_node("Ball").duplicate()
	var ball_CSGSphere3D: CSGSphere3D = new_ball.get_child(1)
	
	var roll: float = appPlugin.drand48(player_num) * 8.0 + -9.0
	var pitch: float = appPlugin.drand48(player_num) * 20.0 + 70.0
	var yaw: float = appPlugin.drand48(player_num) * 10.0 + -5.0
	
	var x_pos: float = appPlugin.drand48(player_num)
	x_pos = x_pos * 0.66 + -0.33
	
	if player_num == 2:
		x_pos *= -1
	
	#print("ball RPY: " + str(roll) + ", " + str(pitch) + ", " + str(yaw))
	#print("ball x: " + str(x_pos))
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
		
func _set_game_data(new_replay: String):
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: " + str(parsed))
	
	if gamePlaying == true:
		print("Message received during game, saving!")
		receivedMessage = new_replay
		return
	
	isTurn = parsed["isYourTurn"]
	player = int(parsed["player"])
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
		
	if isTurn:
		player = 2 if player == 1 else 1
	
	print("YOU ARE PLAYER " + str(player))	
	
	receivedMessage = null
	gameDataSet = true
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
	
	print("Sending game data: " + JSON.stringify(gameData))
	appPlugin.updateGameData(JSON.stringify(gameData))
	
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
	get_node("SubViewportContainer/SubViewport/BlackBackground").visible = false
	get_node("SubViewportContainer/SubViewport/Round1UI").visible = false
	get_node("SubViewportContainer/SubViewport/Round2UI").visible = false
	get_node("SubViewportContainer/SubViewport/waitingLabel").visible = false
	get_node("SubViewportContainer/SubViewport/SkipButton").visible = false

func _process(delta: float) -> void:
	if gamePlaying or replayPlaying:
		elapsedTime += delta
		timeRemainingLabel.text = "0:" + str(int(ceil(45.0 - elapsedTime))).pad_zeros(2)
		if int(ceil(45.0 - elapsedTime)) <= 0:
			elapsedTime = 0.0
			gamePlaying = false
			var wasReplayPlaying = replayPlaying
			replayPlaying = false
			await get_tree().create_timer(3).timeout
			
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
			
			if receivedMessage != null:
				print("Received message during game! Setting new data..")
				_set_game_data(receivedMessage)
				return
			
			print("ready up!")
			_ready()
				
			
