extends Panel
class_name PopupLabel

func _ready():
	var screen_size: Vector2 = get_node("../../../").get_viewport().get_visible_rect().size
	self.position.y = (screen_size.y/2) - self.size.y

func show_label(text: String):
	get_child(0).text = "[center]"+text+"[/center]"
	self.modulate = Color(1, 1, 1, 1)
	self.visible = true

func popup():
	self.modulate = Color(1, 1, 1, 0)
	self.visible = true
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.5)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.5)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.set_loops(1)
	tween.play()
