extends Node3D
class_name basketball

var replay = null
var isTurn = null
var player = null
var seed = null

var appPlugin = null
var has_connected = false

var ballNum = 1

func _ready() -> void:
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
		
	if player == null or replay == null:
		return
		
	if has_connected:
		spawnBall()
		
func spawnBall():
	appPlugin.srand48(seed)
	
	if (ballNum > 1):
		for i in range(ballNum, 1, -1):
			appPlugin.drand48()
	
	var new_ball: RigidBody3D = get_node("Ball").duplicate()
	
	var roll: float = appPlugin.drand48() * 8.0 + -9.0
	var pitch: float = appPlugin.drand48() * 20.0 + 70.0
	var yaw: float = appPlugin.drand48() * 10.0 + -5.0
	
	var x_pos: float = appPlugin.drand48()
	x_pos = x_pos * 0.66 + -0.33
	
	print("ball RPY: " + str(roll) + ", " + str(pitch) + ", " + str(yaw))
	print("ball x: " + str(x_pos))
	new_ball.rotation = Vector3(roll, pitch, yaw)
	new_ball.position = Vector3(x_pos, -0.5, -0.317)
	new_ball.get_child(0).disabled = false
	new_ball.freeze = false
	new_ball.set_visible(true)
	new_ball.name = "Ball" + str(ballNum)

	add_child(new_ball)
	ballNum += 1
		
func _set_game_data(new_replay: String):
	print("NEW REPLAY: " + new_replay)
	for elem in new_replay.split(';'):
		var spl = elem.split(':', true, 1)
		print(spl)
		if spl[0] == "isYourTurn":
			isTurn = bool(int(spl[1]))
		elif spl[0] == "player":
			player = int(spl[1])
		elif spl[0] == "replay":
			replay = spl[1]
		elif spl[0] == "seed":
			seed = int(spl[1])
	
	if isTurn == false:
		player = 2 if player == 1 else 1
		print(player)
	_ready()
