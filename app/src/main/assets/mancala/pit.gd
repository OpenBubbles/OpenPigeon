# Pit.gd
extends Area2D

# Which position this pit represents (0..13)
@export var index: int = 0

# Emitted when the player clicks this pit
signal pit_clicked(idx)

func _ready():
	# Ensure this Area2D can receive input
	input_pickable = true

func _input_event(viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 'self' refers to the node that was clicked (e.g., your Pit)
		print("Clicked on Node: ", self.name)
		print("Node Type: ", self.get_class())
		if self.has_node("CollisionShape2D"):
			print("Collision Shape Index: ", shape_idx) # Useful if you have multiple shapes
		emit_signal("pit_clicked", index) # Your existing signal
