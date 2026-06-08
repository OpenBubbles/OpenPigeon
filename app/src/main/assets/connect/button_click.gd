extends Button

const LOG_TAG := "Connect4Button"

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass

func _pressed() -> void:
	if name != "SendButton":
		return

	var board: ConnectGameBoard = get_node("../GameBoard")
	var appPlugin := Engine.get_singleton("AppPlugin")

	if appPlugin:
		OpLog.event(LOG_TAG, "legacy_send_button_updateGameData")
		appPlugin.updateGameData(board.export_replay())
	else:
		OpLog.w(LOG_TAG, [
			"legacy_send_button_no_app_plugin replay=",
			board.export_replay()
		])
