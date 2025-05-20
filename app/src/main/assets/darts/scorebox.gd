extends Panel

func _ready():
	# adjust position for screen size bc SubViewportContainer is dumb
	var screen_size: Vector2 = get_node("../../../").get_viewport().get_visible_rect().size
	self.position.y = screen_size.y - self.size.y - 10
