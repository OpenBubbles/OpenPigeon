extends Node2D
class_name ConnectGameBoard

var piece_textures = {
	"red": preload("res://connect/red_piece.png"),
	"blue": preload("res://connect/blue_piece.png")
}

var yPoses = [192.544, 109.498, 26.612, -56.274, -139.121, -221.902]

var droppedPiece = null

var firstReplay = true
var isTurn = false
var has_connected = false
var waitingForOpponent = true
var replay = null
var player = null

var boardSizeX = 7
var boardSizeY = 6

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		if not has_connected:
			print("App plugin is available")
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			return
	else:
		if player == null or replay == null:
			_set_game_data("isYourTurn:1;player:1;replay:board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0")
			print("App plugin is not available")
			return
		
	if player == null or replay == null:
		return
	
	var playerBox = get_node_or_null("../Player" + str(player) + "Box")
	if playerBox != null:
		playerBox.get_child(0).set_text("[center]You[/center]")
		
	var board = replay.split('board:')[1].split('|')[0].split(',')

	if firstReplay:
		for y in range(0, boardSizeY):
			for x in range(0, boardSizeX):
				var val = board[y * boardSizeX + x]
				if val == "1":
					spawnPiece(x, "blue", y)
				elif val == "2":
					spawnPiece(x, "red", y)
		firstReplay = false
	
	var replaySplit = replay.split('|')
	for elem in replaySplit:
		var spl = elem.split(':')
		if spl[0] == "move":
			spawnPiece(int(elem.split(',')[0]), getPlayerColor(isTurn))
	
	if check_win() == false:
		set_waiting(not isTurn)

func set_waiting(enabled: bool):
	if enabled:
		replay = null
		player = null
		waitingForOpponent = true
		get_node("../waitingLabel").visible = true
	else:
		droppedPiece = null
		waitingForOpponent = false
		get_node("../waitingLabel").visible = false

func export_replay() -> String:
	var boardStr = ""
	for y in range(0, boardSizeY):
		for x in range(0, boardSizeX):
			if str(x) + "," + str(y) != droppedPiece.name:
				boardStr += getPositionInt(x, y) + ","
			else:
				boardStr += "0,"
	boardStr = boardStr.substr(0, boardStr.length()-1)
				
	var moveX = int(droppedPiece.name.split(',')[0])
	var moveY = int(droppedPiece.name.split(',')[1])
	var moveColor = getPositionInt(moveX, moveY)
	
	if check_win() == false:
		set_waiting(true)
	droppedPiece = null
	(get_node("../UndoButton") as Button).disabled = true
	(get_node("../SendButton") as Button).disabled = true
	
	return "replay:board:" + boardStr + "|move:" + str(moveX) + "," + str(moveY) + "," + moveColor
		
func _set_game_data(new_replay: String):
	for elem in new_replay.split(';'):
		var spl = elem.split(':', true, 1)
		print(spl)
		if spl[0] == "isYourTurn":
			isTurn = bool(int(spl[1]))
		elif spl[0] == "player":
			player = int(spl[1])
		elif spl[0] == "replay":
			replay = spl[1]
	
	if isTurn == false:
		player = 2 if player == 1 else 1
		print(player)
	_ready()
	
func getPlayerColor(other: bool = false) -> String:
	if player == 1:
		if not other:
			return "red"
		else:
			return "blue" 
	if player == 2:
		if not other:
			return "blue"
		else:
			return "red"
	assert(true, "Player is not 1 or 2")
	return ""

func getPieceColor(piece: RigidBody2D):
	var texture = piece.get_child(0).texture.resource_path
	if texture.contains("red"):
		return "red"
	return "blue"

func getPositionInt(posX: int, posY: int) -> String:
	var piece: Node2D = get_node_or_null(str(posX) + "," + str(posY))
	if piece == null:
		return "0"
	var texture_path: String = piece.get_child(0).texture.resource_path
	if texture_path.contains("red"):
		return "2"
	return "1"

func spawnPiece(posX: int, color: String, posY: Variant = null):
	var piece: RigidBody2D = get_node("ConnectPiece"+str(posX)).duplicate()
	if posY != null:
		piece.position.y = yPoses[posY]
	else:
		posY = get_piece_y(posX)
	
	if posY < 0:
		#no free spots
		return
		
	add_child(piece)
	piece.get_child(0).texture = piece_textures[color]
	piece.get_child(1).disabled = false
	piece.set_visible(true)
	piece.set_freeze_enabled(false)
	piece.name = str(posX) + "," + str(posY)
	
	if waitingForOpponent == false:
		droppedPiece = piece
		get_node("../SendButton").disabled = false
		get_node("../UndoButton").disabled = false
	
func get_piece_y(posX: int):
	for posY in range(0, boardSizeY):
		if get_node_or_null(str(posX) + "," + str(posY)) == null:
			return posY
	return -1
	
func undo_move():
	if droppedPiece != null:
		droppedPiece.queue_free()
		droppedPiece = null
		get_node("../SendButton").disabled = true
		get_node("../UndoButton").disabled = true

func check_dir(direction: Vector2, startingPos: Vector2, numChecks: int = 1) -> bool:
	var startingPiece = get_node_or_null(str(int(startingPos.x)) + "," + str(int(startingPos.y)))
	if startingPiece == null:
		return false
	var newPos = Vector2(startingPos.x + direction.x, startingPos.y + direction.y)
	if newPos.x >= boardSizeX or newPos.y >= boardSizeY:
		return false
	var checkPiece = get_node_or_null(str(int(newPos.x)) + "," + str(int(newPos.y)))
	if checkPiece != null:
		if checkPiece.get_child(0).texture.resource_path == startingPiece.get_child(0).texture.resource_path:
			if numChecks == 3:
				return true
			return check_dir(direction, newPos, numChecks+1)
	return false
		
func check_win() -> bool:
	var directions: Array[Vector2] = [
		Vector2(0, 1),  Vector2(0, -1), Vector2(1, 0),  
		Vector2(-1, 0), Vector2(-1, 1),  Vector2(1, 1),  
		Vector2(-1, -1), Vector2(1, -1)  
	]
	
	for y in range(0, boardSizeY):
		for x in range(0, boardSizeX):
			var piece = get_node_or_null(str(x) + "," + str(y))
			if piece == null:
				continue
			for direction in directions:
				if check_dir(direction, Vector2(x, y)):
					if getPieceColor(piece) == getPlayerColor():
						get_node("../winLoseLabel").get_child(0).set_text("[center]YOU WIN!!![/center]")
					else:
						get_node("../winLoseLabel").get_child(0).set_text("[center]You Lose :([/center]")
					get_node("../waitingLabel").visible = false
					get_node("../winLoseLabel").visible = true
					waitingForOpponent = true
					return true
	return false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
