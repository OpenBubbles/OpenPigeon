extends PointLight2D

var parent: Node;

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	parent = get_parent()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	energy = parent.get_meta("Energy")
	position = parent.get_meta("Position")
	visible = parent.get_meta("Visible")
