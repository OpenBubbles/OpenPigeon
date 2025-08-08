
extends Area2D

@export var index: int = 0

signal pit_clicked(idx)

func _ready():
	input_pickable = true

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Clicked on Node: ", self.name)
		print("Node Type: ", self.get_class())
		if self.has_node("CollisionShape2D"):
			print("Collision Shape Index: ", shape_idx)
		emit_signal("pit_clicked", index)
