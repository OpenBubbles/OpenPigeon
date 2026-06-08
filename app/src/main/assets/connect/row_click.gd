extends Panel

@onready var board: ConnectGameBoard = %GameBoard

const LOG_TAG := "Connect4Row"

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return

		if not get_global_rect().has_point(mb.position):
			return

		if board.waitingForOpponent:
			OpLog.d(LOG_TAG, ["row_click_blocked waiting=true row=", name])
			return

		var col: int = int(name.replace("Row", ""))
		OpLog.event(LOG_TAG, ["row_pointer_down col=", col, " input=mouse"])
		board.column_pointer_down(col, mb.position)
		get_viewport().set_input_as_handled()

	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch

		if not touch.pressed:
			return

		if not get_global_rect().has_point(touch.position):
			return

		if board.waitingForOpponent:
			OpLog.d(LOG_TAG, ["row_touch_blocked waiting=true row=", name])
			return

		var col: int = int(name.replace("Row", ""))
		OpLog.event(LOG_TAG, ["row_pointer_down col=", col, " input=touch"])
		board.column_pointer_down(col, touch.position)
		get_viewport().set_input_as_handled()
