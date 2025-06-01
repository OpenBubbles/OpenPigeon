extends Node2D

var has_connected = false
var player = null
var state: Label = null

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#1e9bdd"))
	var appPlugin := Engine.get_singleton("AppPlugin")
	state = get_node("Label") as Label
	if appPlugin:
		if not has_connected:
			print("App plugin is available")
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			return
	else:
		if player == null or replay == null:
			_set_game_data("size:10;isYourTurn:1;bullets1:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0;bullets2:;player:1;replay:;sender:385747AF-7E23-4DFF-9607-FE96C40AF1C6OUVBps;ships1:pos:2,7&num:0,0,0,0&rot:1|pos:7,6&num:0,0,0&rot:1|pos:3,1&num:0,0,0&rot:1|pos:2,3&num:0,0&rot:0|pos:7,2&num:0,0&rot:0|pos:0,0&num:0,0&rot:1|pos:2,9&num:0&rot:0|pos:0,6&num:0&rot:1|pos:9,9&num:0&rot:0|pos:0,3&num:0&rot:1;ships2:;avatar1:body,4|eyes,2|mouth,10|acc,0|wins,0|bg_color,0.161031,0.402684,0.535008|body_color,0.458824,0.325490,0.266667|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.736287,0.106887,0.855236;avatar2:body,4|eyes,0|mouth,2|acc,0|wins,0|bg_color,0.608878,0.670567,0.842836|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,3|clothes,2|hair_color,0.000000,0.000000,0.000000|clothes_color,0.290639,0.935341,0.083265;pl")
			print("App plugin is not available")
			return
			
	if replay == null or player == null:
		return


var isTurn = false
var myBattleground: BattleGround = null
var theirBattleground: BattleGround = null
var uuid1
var uuid2

func _set_game_data(new_replay: String):
	var battleground1 = get_node("BattleGround1") as BattleGround
	var battleground2 = get_node("BattleGround2") as BattleGround
	
	var parsed = JSON.parse_string(new_replay)
	
	uuid1 = parsed["player1"]
	uuid2 = parsed["player2"]
	var replay = parsed["replay"]
	var bullets1 = parsed["bullets1"]
	var bullets2 = parsed["bullets2"]
	var skip = parsed["skip_ships"]
	var s1 = parsed["ships1"]
	var s2 = parsed["ships2"]
	var size = int(parsed["size"])
	isTurn = parsed["isYourTurn"]
	player = int(parsed["player"])
	print(new_replay)
	if isTurn:
		player = 2 if player == 1 else 1
	
	battleground1.set_size(size)
	battleground2.set_size(size)
	
	if not s1.is_empty():
		battleground1.from_encoded(s1)
	if not s2.is_empty():
		battleground2.from_encoded(s2)
	
	if not bullets1.is_empty():
		battleground1.from_bullets(bullets1)
		
	if not bullets2.is_empty():
		battleground2.from_bullets(bullets2)
	
	# show my board
	if player == 1:
		myBattleground = battleground1
		theirBattleground = battleground2
	else:
		myBattleground = battleground2
		theirBattleground = battleground1
	
	show_battleground(true)
	if isTurn:
		(get_node("waitingLabel") as CanvasItem).hide()
		
		if not replay.is_empty():
			(get_node("SendButton") as Button).disabled = true
			state.text = ""
			play_replay(replay)
		elif myBattleground.is_empty():
			state.text = "Place your ships"
			if size == 8:
				myBattleground.from_encoded("pos:4,1&num:0,0,0,0&rot:1|pos:0,4&num:0,0,0&rot:0|pos:0,2&num:0,0,0&rot:1|pos:4,6&num:0,0,0&rot:1|pos:7,3&num:0,0&rot:0|pos:0,0&num:0,0&rot:1|pos:2,6&num:0,0&rot:0")
			if size == 9:
				myBattleground.from_encoded("pos:2,0&num:0,0,0,0&rot:0|pos:5,7&num:0,0,0,0&rot:1|pos:0,5&num:0,0,0,0&rot:0|pos:8,3&num:0,0,0&rot:0|pos:2,5&num:0,0,0&rot:0|pos:4,0&num:0,0,0&rot:0|pos:0,0&num:0,0,0&rot:0|pos:6,0&num:0,0,0&rot:0")
			if size == 10:
				myBattleground.from_encoded("pos:2,7&num:0,0,0,0&rot:1|pos:7,6&num:0,0,0&rot:1|pos:3,1&num:0,0,0&rot:1|pos:2,3&num:0,0&rot:0|pos:7,2&num:0,0&rot:0|pos:0,0&num:0,0&rot:1|pos:2,9&num:0&rot:0|pos:0,6&num:0&rot:1|pos:9,9&num:0&rot:0|pos:0,3&num:0&rot:1")
			myBattleground.placing_items = true
			for ship in myBattleground.ships:
				ship.canBeMoved = true
		else:
			my_battleground_ready()
	else:
		(get_node("SendButton") as Button).disabled = true
		if not skip.is_empty():
			theirBattleground.from_encoded(skip)
		if theirBattleground.is_over():
			mark_end(true)
			return
		state.text = ""
		(get_node("waitingLabel") as CanvasItem).show()
		myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
		theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED

func play_replay(replay: String):
	for move in replay.split("|"):
		await get_tree().create_timer(1.0).timeout
		var elements = move.split(",")
		myBattleground.fire(Vector2(int(elements[0]), int(elements[1])))
	await get_tree().create_timer(2.0).timeout
	my_battleground_ready()

func show_battleground(mine: bool):
	myBattleground.visible = mine
	theirBattleground.visible = not mine
	myBattleground.process_mode = Node.PROCESS_MODE_INHERIT if mine else Node.PROCESS_MODE_DISABLED
	theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED if mine else Node.PROCESS_MODE_INHERIT
	print("setting their process mode dto " + str(not mine))
	print(theirBattleground.process_mode)

# state before we take action, state other person should go to for replay
var replay: Array[String] = []
func send_update():
	var myEncoded = myBattleground.encode_ships()
	var bullets = myBattleground.encode_bullets()
	var msg = {
		"ships" + str(player): myEncoded,
		"bullets" + str(player): bullets,
	}
	if not replay.is_empty():
		msg["replay"] = "|".join(replay)
		msg["skip_ships"] = theirBattleground.encode_ships()
		msg["skip_bullets"] = theirBattleground.encode_bullets()
	
	if is_end:
		var whoWon = player if winner else 2 if player == 1 else 1
		msg["winner"] = (uuid1 if whoWon == 1 else uuid2) + "|1"
	
	var encoded = JSON.stringify(msg)
	
	print("replay")
	print(encoded)
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(encoded)
	else:
		print("app not connected??")
	state.text = ""
	if not is_end:
		(get_node("waitingLabel") as CanvasItem).show()
	(get_node("SendButton") as Button).disabled = true
	myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
	theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED
	print("setting their process mode to " + str(false))


var fireMode = false
func my_battleground_ready():
	if theirBattleground.is_empty():
		send_update()
		return
	if myBattleground.is_over():
		mark_end(false)
		return
	(get_node("SendButton") as Button).disabled = false
	state.text = "Choose your target"
	theirBattleground.set_attack()
	show_battleground(false)
	fireMode = true
	(get_node("SendButton") as Button).text = "Fire"

var is_end = false
var winner = false
func mark_end(win: bool):
	state.text = ""
	myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
	theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED
	print("setting their process mode to " + str(false))
	get_node("winLoseLabel").get_child(0).set_text("[center]YOU WIN![/center]" if win else "[center]YOU LOSE :([/center]")
	get_node("winLoseLabel").visible = true
	get_node("waitingLabel").visible = false
	winner = win
	is_end = true

func _on_send_button_pressed() -> void:
	print("presesd")
	if fireMode:
		replay.append(str(theirBattleground.targeting_grid.x) + "," + str(theirBattleground.targeting_grid.y))
		if not theirBattleground.fire(theirBattleground.targeting_grid):
			(get_node("SendButton") as Button).disabled = true
			theirBattleground.can_attack = false
			await get_tree().create_timer(1.0).timeout
			send_update()
		if theirBattleground.is_over():
			mark_end(true)
			send_update()
		return
	my_battleground_ready()


func _on_battle_ground_is_valid(valid: bool) -> void:
	(get_node("SendButton") as Button).disabled = not valid
