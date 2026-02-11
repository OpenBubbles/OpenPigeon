# res://paintball/modules/PB_Buttons.gd
extends RefCounted
class_name PB_Buttons

var g: PaintballGame

func setup(owner: PaintballGame) -> void:
	g = owner

func collect_buttons(n: Node) -> void:
	if n is ActionButton3D:
		g._buttons.append(n)
	for c in n.get_children():
		collect_buttons(c)

func index_buttons() -> void:
	g._move_btn_by_lane.clear()
	g._shoot_btn_by_lane.clear()

	for b in g._buttons:
		if not is_instance_valid(b):
			continue
		if b.kind == ActionButton3D.ButtonKind.MOVE:
			g._move_btn_by_lane[b.lane] = b
		elif b.kind == ActionButton3D.ButtonKind.SHOOT:
			g._shoot_btn_by_lane[b.lane] = b

func set_button_enabled(b: ActionButton3D, enabled: bool) -> void:
	var sprite := b.get_node("Sprite3D") as Sprite3D
	if not sprite:
		return

	if enabled:
		sprite.modulate = Color(1, 1, 1, 1)
	else:
		sprite.modulate = Color(0.5, 0.5, 0.5, 0.4)

func set_all_buttons_clickable(enabled: bool) -> void:
	for b in g._buttons:
		if not is_instance_valid(b):
			continue
		b.set_click_enabled(enabled)
		set_button_enabled(b, enabled)

func update_move_buttons() -> void:
	print("Update move buttons: lane=", g._player_lane)
	for b in g._buttons:
		if b.kind == ActionButton3D.ButtonKind.MOVE:
			b.set_player_lane(g._player_lane)

func cache_lane_x_from_move_buttons() -> void:
	for b in g._buttons:
		if b.kind != ActionButton3D.ButtonKind.MOVE:
			continue
		g._lane_x[b.lane] = b.global_position.x

func lane_from_player_x() -> ActionButton3D.Lane:
	var px: float = g.player.global_position.x

	var best_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
	var best_d: float = INF

	for ln in [ActionButton3D.Lane.LEFT, ActionButton3D.Lane.CENTER, ActionButton3D.Lane.RIGHT]:
		var d: float = abs(px - float(g._lane_x[ln]))
		if d < best_d:
			best_d = d
			best_lane = ln

	return best_lane

func spawn_player_random_lane() -> void:
	var lanes := [
		ActionButton3D.Lane.LEFT,
		ActionButton3D.Lane.CENTER,
		ActionButton3D.Lane.RIGHT
	]

	var chosen: ActionButton3D.Lane = lanes[randi() % lanes.size()]
	var p := g.player.global_position
	p.x = float(g._lane_x[chosen])
	g.player.global_position = p

	g._player_lane = chosen
	update_move_buttons()

func move_player_to_button(b: ActionButton3D) -> void:
	if not g.is_my_turn or g._is_shot_sequence_running or g._round_sequence_running:
		print("[INPUT] Ignored move (not my turn or sequence running).")
		return

	if not g.player:
		return

	var start_lane: ActionButton3D.Lane = g._player_lane
	var target_lane: ActionButton3D.Lane = b.lane
	if start_lane == target_lane:
		return

	if g._move_tween and g._move_tween.is_valid():
		g._move_tween.kill()

	var base_y: float = g.player.global_position.y
	var base_z: float = g.player.global_position.z

	var path: Array[ActionButton3D.Lane] = []
	path.append(start_lane)

	if abs(int(target_lane) - int(start_lane)) == 2:
		path.append(ActionButton3D.Lane.CENTER)

	path.append(target_lane)

	var hop_height: float = 0.85
	var leg_time: float = 0.35

	g._move_tween = g.create_tween()
	g._move_tween.set_trans(Tween.TRANS_SINE)
	g._move_tween.set_ease(Tween.EASE_OUT)

	for i in range(1, path.size()):
		var leg_lane: ActionButton3D.Lane = path[i]
		var leg_x: float = float(g._lane_x[leg_lane])

		g._move_tween.tween_property(g.player, "global_position:x", leg_x, leg_time)

		var yseq: Tween = g._move_tween.parallel()
		yseq.tween_method(func(t: float) -> void:
			var y := base_y + hop_height * 4.0 * t * (1.0 - t)
			g.player.global_position.y = y
		, 0.0, 1.0, leg_time)

		g._move_tween.tween_callback(func() -> void:
			var p := g.player.global_position
			p.y = base_y
			p.z = base_z
			g.player.global_position = p

			g._player_lane = leg_lane
			update_move_buttons()
		)

	g._move_tween.finished.connect(func() -> void:
		var p := g.player.global_position
		p.y = base_y
		p.z = base_z
		g.player.global_position = p

		g._player_lane = lane_from_player_x()
		update_move_buttons()
	)
