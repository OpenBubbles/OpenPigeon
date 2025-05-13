extends Node2D


@export var radius: float = 50.0
@export var color: Color = Color(1, 0, 0, 1) # Red

func _draw():
	draw_circle(Vector2.ZERO, radius, color)
