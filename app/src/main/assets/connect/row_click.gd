extends Panel

func _input(event):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == 1:
			var global_click_position = event.position
			var board: ConnectGameBoard = get_node("../GameBoard")
			if get_global_rect().has_point(global_click_position) and board.droppedPiece == null and board.waitingForOpponent == false:
				var clicked: Panel = get_node(".")
				var posX: int = int(clicked.name.replace("Row", ""))
				var color: String = board.getPlayerColor()
				board.spawnPiece(posX, color)
