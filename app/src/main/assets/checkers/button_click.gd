extends Button

const LOG_TAG := "ButtonClick"

func _ready() -> void:
	pass

func _pressed() -> void:
	if name != "SendButton":
		return

	var board := get_node_or_null("../GameBoard")
	if board == null or not board.has_method("export_replay"):
		OpLog.e(LOG_TAG, "SendButton pressed but ../GameBoard.export_replay is not available")
		return

	var payload: String = board.export_replay()
	OpLog.event(LOG_TAG, ["send_button_out raw=", payload])

	var appPlugin := Engine.get_singleton("AppPlugin") if Engine.has_singleton("AppPlugin") else null
	if appPlugin:
		appPlugin.updateGameData(payload)
	else:
		OpLog.w(LOG_TAG, "AppPlugin not connected; payload was not sent")
