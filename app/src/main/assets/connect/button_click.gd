extends Button

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _pressed() -> void:
	if name == "SendButton":
		var board: ConnectGameBoard = get_node("../GameBoard")
		var appPlugin := Engine.get_singleton("AppPlugin")
		if appPlugin:
			appPlugin.updateGameData(board.export_replay())
		else:
			print(board.export_replay())
			print("App not connected!")
	elif name == "UndoButton":
		var board: ConnectGameBoard = get_node("../GameBoard")
		board.undo_move()
