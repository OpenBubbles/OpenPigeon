extends Control


func _on_close_button_pressed():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	hide()
	modulate.a = 1.0
