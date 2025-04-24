extends Node
class_name BoardHighlight

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var tween = get_tree().create_tween()
	tween.tween_method(set_energy, 0.0, 5.0, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_method(set_energy, 5.0, 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	tween.set_loops(5000)

func set_energy(value: float):
	set_meta("Energy", value);

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
