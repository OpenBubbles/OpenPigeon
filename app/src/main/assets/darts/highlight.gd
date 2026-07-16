extends CSGPolygon3D

var fade_out: Tween

func _ready():
	reset_fade_out()
	self.visibility_changed.connect(on_visibility_changed)
	
func on_visibility_changed():
	if not self.visible:
		return

	var board := get_parent()

	if (
		is_instance_valid(board) and
		"showing_win_target" in board and
		board.showing_win_target
	):
		return

	if not fade_out.is_valid():
		reset_fade_out()

	fade_out.play()

func reset_fade_out():
	if fade_out and fade_out.is_valid():
		fade_out.kill()

	self.material.albedo_color.a = 0.6

	fade_out = get_tree().create_tween()
	fade_out.tween_property(
		self.material,
		"albedo_color",
		Color(1, 1, 0, 0),
		0.25
	).set_trans(Tween.TRANS_SINE)
	
