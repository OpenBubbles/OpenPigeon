# res://paintball/modules/PB_Buttons.gd
extends RefCounted
class_name PB_Buttons

var g: PaintballGame
var _root: Node = null
var _did_initial_spawn: bool = false

func setup(owner: PaintballGame) -> void:
	g = owner

# ADD: stores the resolved root node for button collection
func setup_buttons_root(root_path: NodePath) -> void:
	if g == null:
		push_error("[PB_Buttons] setup_buttons_root called before setup(owner).")
		_root = null
		return

	_root = g
	if root_path != NodePath(""):
		if g.has_node(root_path):
			_root = g.get_node(root_path)
		else:
			push_error("[PB_Buttons] buttons_root path not found: %s" % String(root_path))
			_root = g

# ADD: one-call convenience used by PaintballGame._ready()
func collect_and_index_buttons() -> void:
	if g == null:
		push_error("[PB_Buttons] collect_and_index_buttons called before setup(owner).")
		return
	if _root == null:
		push_error("[PB_Buttons] collect_and_index_buttons called before setup_buttons_root().")
		return

	g._buttons.clear()
	collect_buttons(_root)
	index_buttons()

func connect_button_signals() -> void:
	print("[PB_BUTTONS] connect_button_signals count=", g._buttons.size())

	for b in g._buttons:
		if not is_instance_valid(b):
			continue

		print("[PB_BUTTONS] wiring:", b.name, " kind=", int(b.kind), " lane=", int(b.lane))

		if b.has_signal("clicked"):
			if not b.clicked.is_connected(_on_button_clicked):
				b.clicked.connect(_on_button_clicked)
			continue

		if b.has_signal("pressed"):
			var cb: Callable = _on_button_pressed.bind(b)
			if not b.pressed.is_connected(cb):
				b.pressed.connect(cb)
			continue


		if b.has_signal("button_clicked"):
			if not b.button_clicked.is_connected(_on_button_clicked):
				b.button_clicked.connect(_on_button_clicked)
			continue

		print("[PB_BUTTONS] WARNING no usable signal on:", b.name)

func _on_button_clicked(b: ActionButton3D) -> void:
	print("[PB_BUTTONS] CLICKED:", b.name,
		" kind=", int(b.kind),
		" lane=", int(b.lane),
		" is_my_turn=", g.is_my_turn,
		" shot_seq=", g._is_shot_sequence_running,
		" round_seq=", g._round_sequence_running
	)

	# forward to PaintballGame
	g._on_button_clicked(b)

func _on_button_pressed(b: ActionButton3D) -> void:
	print("[PB_BUTTONS] PRESSED:", b.name,
		" kind=", int(b.kind),
		" lane=", int(b.lane)
	)
	_on_button_clicked(b)

func collect_buttons(n: Node) -> void:
	if g == null:
		return
	if n == null or not is_instance_valid(n):
		return

	if n is ActionButton3D:
		g._buttons.append(n)

	for c in n.get_children():
		if c != null and is_instance_valid(c):
			collect_buttons(c)

func index_buttons() -> void:
	if g == null:
		return

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
	if g == null:
		return

	for b in g._buttons:
		if not is_instance_valid(b):
			continue
		b.set_click_enabled(enabled)
		set_button_enabled(b, enabled)

func update_move_buttons() -> void:
	if g == null:
		return

	print("Update move buttons: lane=", g._player_lane)
	for b in g._buttons:
		if b.kind == ActionButton3D.ButtonKind.MOVE:
			b.set_player_lane(g._player_lane)

func cache_lane_x_from_move_buttons() -> void:
	if g == null:
		return

	for b in g._buttons:
		if b.kind != ActionButton3D.ButtonKind.MOVE:
			continue
		g._lane_x[b.lane] = b.global_position.x

func _get_lane_world_x(lane: ActionButton3D.Lane) -> float:
	# Prefer the actual MOVE button world X for that lane
	if g._move_btn_by_lane.has(lane):
		var mb := g._move_btn_by_lane[lane] as ActionButton3D
		if is_instance_valid(mb):
			return mb.global_position.x

	# Fallback to cached lane map
	if g._lane_x.has(lane):
		return float(g._lane_x[lane])

	# Last resort
	return g.player.global_position.x

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
	# Only do this once per scene lifetime
	if _did_initial_spawn:
		return

	if not is_instance_valid(g.player):
		return

	# If replay already exists, do NOT randomize. Replay will place us.
	if g._replay_segments.size() > 0 or g._last_replay_str != "":
		return

	var lanes: Array = [
		ActionButton3D.Lane.LEFT,
		ActionButton3D.Lane.CENTER,
		ActionButton3D.Lane.RIGHT
	]

	var chosen: ActionButton3D.Lane = lanes[randi() % lanes.size()]

	var p: Vector3 = g.player.global_position
	p.x = float(g._lane_x.get(chosen, 0.0))
	g.player.global_position = p

	g._player_lane = chosen
	update_move_buttons()

	_did_initial_spawn = true

func move_player_to_button(b: ActionButton3D) -> void:
	if g == null:
		return

	if not g.is_my_turn or g._is_shot_sequence_running or g._round_sequence_running:
		print("[INPUT] Ignored move (not my turn or sequence running).")
		return

	if not is_instance_valid(g.player):
		print("[INPUT] Ignored move because player is invalid.")
		return

	if not is_instance_valid(b):
		print("[INPUT] Ignored move because button is invalid.")
		return

	var start_lane: ActionButton3D.Lane = g._player_lane
	var target_lane: ActionButton3D.Lane = b.lane

	print("[MOVE] requested start=", int(start_lane), " target=", int(target_lane))

	if start_lane == target_lane:
		print("[MOVE] ignored because already in target lane.")
		return

	var path: Array[ActionButton3D.Lane] = [start_lane]

	if abs(int(target_lane) - int(start_lane)) == 2:
		path.append(ActionButton3D.Lane.CENTER)

	path.append(target_lane)

	if path.size() < 2:
		return

	if g._move_tween and g._move_tween.is_valid():
		g._move_tween.kill()

	var base_y: float = g.player.global_position.y
	var base_z: float = g.player.global_position.z
	var hop_height: float = 0.85
	var leg_time: float = 0.35

	g._move_tween = g.create_tween()
	g._move_tween.set_trans(Tween.TRANS_SINE)
	g._move_tween.set_ease(Tween.EASE_OUT)

	for i in range(1, path.size()):
		var from_lane: ActionButton3D.Lane = path[i - 1]
		var leg_lane: ActionButton3D.Lane = path[i]
		var from_pos: Vector3 = Vector3(_get_lane_world_x(from_lane), base_y, base_z)
		var to_pos: Vector3 = Vector3(_get_lane_world_x(leg_lane), base_y, base_z)

		g._move_tween.tween_method(func(t: float) -> void:
			if not is_instance_valid(g.player):
				return

			var p: Vector3 = from_pos.lerp(to_pos, t)
			p.y = base_y + hop_height * 4.0 * t * (1.0 - t)
			p.z = base_z
			g.player.global_position = p
		, 0.0, 1.0, leg_time)

		g._move_tween.tween_callback(func() -> void:
			if not is_instance_valid(g.player):
				return

			g._player_lane = leg_lane
			g.player.global_position = Vector3(_get_lane_world_x(leg_lane), base_y, base_z)
		)

	g._move_tween.finished.connect(func() -> void:
		if not is_instance_valid(g.player):
			return

		g._player_lane = target_lane
		g.player.global_position = Vector3(_get_lane_world_x(target_lane), base_y, base_z)
		call_deferred("update_move_buttons")

		print("[MOVE] finished lane=", int(g._player_lane), " pos=", g.player.global_position)
	)

func update_shoot_selection_visuals(selected: ActionButton3D) -> void:
	for b in g._buttons:
		if not is_instance_valid(b):
			continue
		if b.kind != ActionButton3D.ButtonKind.SHOOT:
			continue

		var is_selected := (selected != null and b == selected)

		# Keep clickable, just change look
		b.set_click_enabled(true)

		var sprite := b.get_node_or_null("Sprite3D") as Sprite3D
		if sprite == null:
			continue

		if selected == null:
			sprite.modulate = Color(1, 1, 1, 1)
		elif is_selected:
			sprite.modulate = Color(1, 1, 1, 1)
		else:
			# Dim non-selected targets
			sprite.modulate = Color(0.5, 0.5, 0.5, 0.4)
