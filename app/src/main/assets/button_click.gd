extends Button


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _pressed() -> void:
	if name == "SendButton":
		print("Send clicked")
		var board: CheckersBoardTop = get_node("../CheckersBoardTop")

		var appPlugin := Engine.get_singleton("AppPlugin")
		if appPlugin:
			appPlugin.sendReplay(board.export_replay())
		else:
			print("app not connected??")
			
	elif name == "UndoButton":
		print("Undo clicked")
		var board: CheckersBoardTop = get_node("../CheckersBoardTop")
		board.undo_move()
