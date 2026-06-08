extends Area2D

@export var index: int = 0

signal pit_clicked(idx)

const LOG_TAG := "MancalaPit"

func _ready():
	input_pickable = true

func _input_event(_viewport: Viewport, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		OpLog.d(LOG_TAG, [
			"pit_input name=", name,
			" index=", index,
			" shape_idx=", shape_idx,
			" class=", get_class()
		])
		emit_signal("pit_clicked", index)
