extends Button

func _pressed() -> void:
	if self.name == "StartButton":
		var BasketballGame: basketball = get_node("../../../..")
		self.get_parent().visible = false
		get_node("../../BlackBackground").visible = false
		BasketballGame.startGame()
	elif self.name == "SkipButton":
		var BasketballGame: basketball = get_node("../../..")
		BasketballGame.skipReplay()
