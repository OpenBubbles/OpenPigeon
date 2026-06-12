extends Button

const LOG_TAG := "BasketballButton"

func _pressed() -> void:
	if self.name == "StartButton":
		var BasketballGame: basketball = get_node("../../../..")
		OpLog.i(LOG_TAG, ["start_button_pressed gameValid=", is_instance_valid(BasketballGame)])

		self.get_parent().visible = false
		get_node("../../BlackBackground").visible = false
		BasketballGame.startGame()

	elif self.name == "SkipButton":
		var BasketballGame: basketball = get_node("../../..")
		OpLog.i(LOG_TAG, ["skip_button_pressed gameValid=", is_instance_valid(BasketballGame)])
		BasketballGame.skipReplay()
