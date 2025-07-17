extends Button

@onready var label = $Label

func flip_to(symbol: String) -> void:
	var tween = create_tween()

	# Step 1: squash the label vertically
	tween.tween_property(label, "scale", Vector2(1, 0.1), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Step 2: update the label text at midpoint
	tween.tween_callback(Callable(self, "_set_symbol").bind(symbol))

	# Step 3: grow label back to normal
	tween.tween_property(label, "scale", Vector2(1, 1), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_symbol(symbol: String):
	label.text = symbol
