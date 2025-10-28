extends Panel
@onready var board: ConnectGameBoard = %GameBoard

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not get_global_rect().has_point(get_global_mouse_position()):
			return
		if board.waitingForOpponent:
			return

		var posX: int = int(name.replace("Row", ""))
		if board.droppedPiece == null:
			board.spawnPiece(posX, board.getPlayerColor())
		else:
			board.move_dropped_piece_to_column(posX)
