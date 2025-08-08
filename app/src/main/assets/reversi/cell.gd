extends Button

@onready var label = $Label

func flip_to(symbol: String) -> void:
	var tween = create_tween()

	tween.tween_property(label, "scale", Vector2(1, 0.1), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(Callable(self, "_set_symbol").bind(symbol))
	tween.tween_property(label, "scale", Vector2(1, 1), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_symbol(symbol: String):
	label.text = symbol
