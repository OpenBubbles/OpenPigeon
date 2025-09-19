extends RigidBody2D
signal aim_changed(angle_degrees: float, power: float)

# ---------- Arrow / input UI tuning ----------
const MAX_POWER: float = 150.0          # server/game power cap (replay clamp)
const MAX_ARROW_LENGTH: float = 275.0   # on-screen arrow length (pixels)
const ANGLE_STEP_DEG: float = 2.0
const POWER_STEP: float = 3.0
const INTERACT_RADIUS: float = 24.0
const HEAD_LEN: float = 18.0
const HEAD_W: float = 24.0
const HANDLE_RADIUS: float = 40.0
const HEAD_GRAB_EXTRA_LEN: float = 28.0
const HEAD_GRAB_EXTRA_W: float = 28.0
const ARROW_SHAFT_WIDTH: float = 8.0
const ARROW_BASE_COLOR: Color = Color(1,1,1,1)
const SHOOT_ON_RELEASE: bool = false

# ---------- Unified physics params (overridden by knockout.gd) ----------
var phys := {
	"PPM": 32.0,                         # pixels per meter (info only here)
	"PIECE_RADIUS_PX": 24.0,            # visual + collider radius in pixels
	"FRICTION": 0.02,                   # physics material friction
	"RESTITUTION": 0.30,                # physics material bounce
	"LINEAR_DAMP": 0.25,                # body linear damping
	"ANGULAR_DAMP": 0.45,               # body angular damping
	"DENSITY": 1.0,                     # (unused in 2D RigidBody2D, kept for parity)
	"POWER_TO_IMPULSE": 1.29,           # pixels-of-power -> impulse scale
	"GRAVITY_SCALE": 0.0,               # no gravity sliding
	"CCD_MODE": RigidBody2D.CCD_MODE_CAST_RAY,
	"LOCK_ROTATION": false
}

func set_physics_params(p: Dictionary) -> void:
	for k in p.keys():
		phys[k] = p[k]
	_apply_phys_now()

func _apply_phys_now() -> void:
	# Body-level props
	gravity_scale = float(phys.get("GRAVITY_SCALE", 0.0))
	continuous_cd = int(phys.get("CCD_MODE", RigidBody2D.CCD_MODE_CAST_RAY))
	lock_rotation = bool(phys.get("LOCK_ROTATION", false))
	linear_damp = float(phys.get("LINEAR_DAMP", 0.25))
	angular_damp = float(phys.get("ANGULAR_DAMP", 0.45))

	# Collider radius (if present / circular)
	var body_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape and body_shape.shape is CircleShape2D:
		(body_shape.shape as CircleShape2D).radius = float(phys.get("PIECE_RADIUS_PX", 24.0))

	# Physics material
	var pm: PhysicsMaterial = physics_material_override
	if pm == null:
		pm = PhysicsMaterial.new()
		physics_material_override = pm
	pm.friction = float(phys.get("FRICTION", 0.02))
	pm.bounce   = float(phys.get("RESTITUTION", 0.30))

@onready var sprite: Sprite2D = $Sprite2D

# ---------- Arrow nodes ----------
var arrow_root: Node2D
var arrow_shaft: Line2D
var arrow_head: Polygon2D
var arrow_handle_area: Area2D
var arrow_handle_shape: CollisionShape2D
var arrow_head_area: Area2D
var arrow_head_poly: CollisionPolygon2D

# ---------- State ----------
var pulse_tween: Tween
var arrow_fade_tween: Tween
var _arrow_faded_this_move := false
var controlled_by_me: bool = false
var dragging: bool = false
var dragging_handle: bool = false
var aim_dir: Vector2 = Vector2.RIGHT
var power: float = 0.0
var last_q_angle: int = -999_999
var last_q_power: int = -999_999
var _head_tri_local: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	set_process_input(true)
	set_process(true)
	set_physics_process(true)

	# Layers/masks first
	collision_layer = 1
	collision_mask  = 1

	# Ensure body shape exists before applying params (so radius can be set)
	_ensure_body_collision_shape()
	_apply_phys_now()

	# Build arrow / visuals
	_build_arrow_if_needed()
	set_controlled_by_me(controlled_by_me)
	_sync_arrow_origin()
	_update_arrow_visuals()
	if sprite:
		sprite.z_index = 1

func _make_circle_poly(r: float, segs: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var a := TAU * float(i) / float(segs)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

func _physics_process(_dt: float) -> void:
	# If we start moving, fade the arrow for readability
	if arrow_root and arrow_root.visible and not _arrow_faded_this_move:
		if linear_velocity.length() > 1.0 or absf(angular_velocity) > 0.05:
			_fade_out_arrow(0.18)
			_arrow_faded_this_move = true
	elif linear_velocity.length() < 0.1 and absf(angular_velocity) < 0.01:
		_arrow_faded_this_move = false

func _process(_dt: float) -> void:
	if arrow_root and arrow_root.visible:
		_sync_arrow_origin()

# ---------- Arrow fading ----------
func fade_out_arrow_for_shot(fade_sec: float = 0.18) -> void:
	_fade_out_arrow(fade_sec)

func _fade_out_arrow(fade_sec: float) -> void:
	if not arrow_root or not arrow_root.visible:
		return
	if arrow_fade_tween and arrow_fade_tween.is_running():
		arrow_fade_tween.kill()
	arrow_fade_tween = create_tween()
	arrow_fade_tween.tween_property(arrow_root, "modulate:a", 0.0, fade_sec)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	arrow_fade_tween.finished.connect(func():
		if is_instance_valid(arrow_root):
			arrow_root.visible = false
			arrow_root.modulate.a = 0.0
	)

# ---------- Collision shape bootstrap ----------
func _ensure_body_collision_shape() -> void:
	var body_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape:
		return

	# Try to mirror Area2D shape if it exists
	var area := get_node_or_null("Area2D") as Area2D
	if area:
		var area_shape := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if area_shape and area_shape.shape:
			var new_body_shape := CollisionShape2D.new()
			new_body_shape.name = "CollisionShape2D"
			new_body_shape.shape = area_shape.shape.duplicate(true)
			add_child(new_body_shape)
			return

	# Fallback circle of our configured radius
	var fallback := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = float(phys.get("PIECE_RADIUS_PX", 24.0))
	fallback.shape = circle
	add_child(fallback)

# ---------- Control / picking ----------
func set_controlled_by_me(v: bool) -> void:
	controlled_by_me = v
	if arrow_handle_area: arrow_handle_area.input_pickable = v
	if arrow_head_area: arrow_head_area.input_pickable = v

func _candidate_at_point(global_pos: Vector2) -> Dictionary:
	var best_dist := INF
	var hit := false
	var from_handle := false

	if _hit_arrow_tip(global_pos) and arrow_handle_area:
		hit = true
		from_handle = true
		best_dist = (arrow_handle_area.global_position - global_pos).length()

	if _hit_arrow_head(global_pos) and arrow_head_area:
		var d_head := (arrow_head_area.global_position - global_pos).length()
		if not hit or d_head < best_dist:
			hit = true
			from_handle = true
			best_dist = d_head

	if not hit and _pointer_close_enough(global_pos):
		hit = true
		from_handle = false
		best_dist = (global_position - global_pos).length()

	return {"hit": hit, "dist": best_dist, "from_handle": from_handle}

func _nearest_piece_at_point(global_pos: Vector2) -> Dictionary:
	var parent := get_parent()
	if not parent:
		return {"node": null, "from_handle": false}

	var best_node: Node = null
	var best_dist := INF
	var best_from_handle := false

	for n in parent.get_children():
		if not (n is RigidBody2D) or not n.has_method("_candidate_at_point"):
			continue
		if not n.controlled_by_me:
			continue

		var res: Dictionary = n._candidate_at_point(global_pos)
		if not res["hit"]:
			continue

		var d := float(res["dist"])
		var fh := bool(res["from_handle"])
		var current_best_id := best_node.get_instance_id() if (best_node != null) else self.get_instance_id()

		if d < best_dist or (absf(d - best_dist) < 0.001 and n.get_instance_id() < current_best_id):
			best_dist = d
			best_node = n
			best_from_handle = fh

	return {"node": best_node, "from_handle": best_from_handle}

# ---------- Input ----------
func _input(event: InputEvent) -> void:
	if not controlled_by_me:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var win: Dictionary = _nearest_piece_at_point(event.position)
			if win["node"] == self:
				var self_res: Dictionary = _candidate_at_point(event.position)
				if self_res["hit"]:
					_begin_drag(event.position, bool(self_res["from_handle"]))
		else:
			if dragging:
				_update_aim_from_global_pos(event.position)
				_end_drag()

	elif event is InputEventMouseMotion and dragging:
		_update_aim_from_global_pos(event.position)

	if event is InputEventScreenTouch:
		if event.pressed:
			var win_t: Dictionary = _nearest_piece_at_point(event.position)
			if win_t["node"] == self:
				var self_res_t: Dictionary = _candidate_at_point(event.position)
				if self_res_t["hit"]:
					_begin_drag(event.position, true)
		else:
			if dragging:
				_update_aim_from_global_pos(event.position)
				_end_drag()

	elif event is InputEventScreenDrag and dragging:
		_update_aim_from_global_pos(event.position)

func _pointer_close_enough(global_pos: Vector2) -> bool:
	var local: Vector2 = to_local(global_pos)
	return local.length() <= INTERACT_RADIUS

func _hit_arrow_tip(global_pos: Vector2) -> bool:
	if not arrow_handle_area: return false
	var lp := arrow_handle_area.to_local(global_pos)
	return lp.length() <= HANDLE_RADIUS

func _hit_arrow_head(global_pos: Vector2) -> bool:
	if not arrow_head_area or _head_tri_local.size() != 3: return false
	var lp := arrow_head_area.to_local(global_pos)
	return Geometry2D.is_point_in_polygon(lp, _head_tri_local)

func _begin_drag(global_pos: Vector2, from_handle: bool=false) -> void:
	dragging = true
	dragging_handle = from_handle
	if arrow_root:
		arrow_root.visible = true
		if arrow_fade_tween and arrow_fade_tween.is_running():
			arrow_fade_tween.kill()
		arrow_root.modulate.a = 1.0
		_sync_arrow_origin()
	_update_aim_from_global_pos(global_pos)

func _end_drag() -> void:
	dragging = false
	dragging_handle = false
	if SHOOT_ON_RELEASE:
		fire_from_current_aim()

# ---------- Replay helpers ----------
func show_arrow_from_replay(angle_deg: float, pow_px: float, fade_sec: float = 0.18) -> void:
	aim_dir = Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
	power = clamp(pow_px, 0.0, MAX_ARROW_LENGTH)
	_update_arrow_visuals()
	if arrow_root:
		_sync_arrow_origin()
		arrow_root.visible = true
		if arrow_fade_tween and arrow_fade_tween.is_running():
			arrow_fade_tween.kill()
		arrow_root.modulate.a = 0.0
		arrow_fade_tween = create_tween()
		arrow_fade_tween.tween_property(arrow_root, "modulate:a", 1.0, fade_sec)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func rotate_to_angle_rad(angle_rad: float, dur: float = 0.18) -> void:
	var tw := create_tween()
	tw.tween_property(self, "rotation", angle_rad, dur)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------- Aiming ----------
func _update_aim_from_global_pos(global_pos: Vector2) -> void:
	var delta: Vector2 = global_pos - global_position
	var tip_vec: Vector2 = delta.limit_length(MAX_ARROW_LENGTH)
	var tlen: float = tip_vec.length()
	var dir: Vector2 = (tip_vec / tlen) if (tlen > 0.0001) else Vector2.RIGHT

	var angle_deg: float = fposmod(rad_to_deg(dir.angle()), 360.0)
	var q_angle: int = int(round(angle_deg / ANGLE_STEP_DEG))
	var q_power: int = int(round(tlen / POWER_STEP))
	_maybe_tick(q_angle, q_power)

	aim_dir = dir
	power = tlen

	_sync_arrow_origin()
	_update_arrow_visuals()

	set_meta("shoot_dir", angle_deg)
	set_meta("power", power)
	emit_signal("aim_changed", angle_deg, power)

func _maybe_tick(q_angle: int, q_power: int) -> bool:
	var tick: bool = false
	if q_angle != last_q_angle:
		tick = true
		last_q_angle = q_angle
	if q_power != last_q_power:
		tick = true
		last_q_power = q_power
	if tick and OS.has_feature("mobile"):
		Input.vibrate_handheld(12)
	return tick

func hide_arrow() -> void:
	dragging = false
	dragging_handle = false
	power = 0.0
	aim_dir = Vector2.RIGHT
	_update_arrow_visuals()
	if arrow_root:
		arrow_root.modulate.a = 0.0
		arrow_root.visible = false
	set_meta("shoot_dir", 0.0)
	set_meta("power", 0.0)

# ---------- Arrow build / visuals ----------
func _build_arrow_if_needed() -> void:
	if arrow_root:
		return

	arrow_root = Node2D.new()
	arrow_root.name = "Arrow"
	add_child(arrow_root)
	arrow_root.top_level = true
	arrow_root.visible = false
	arrow_root.z_as_relative = false
	arrow_root.z_index = 10

	arrow_shaft = Line2D.new()
	arrow_shaft.name = "Shaft"
	arrow_shaft.width = ARROW_SHAFT_WIDTH
	arrow_shaft.antialiased = true
	arrow_shaft.default_color = ARROW_BASE_COLOR
	arrow_shaft.begin_cap_mode = Line2D.LINE_CAP_NONE
	arrow_shaft.end_cap_mode = Line2D.LINE_CAP_NONE
	arrow_root.add_child(arrow_shaft)

	arrow_head = Polygon2D.new()
	arrow_head.color = ARROW_BASE_COLOR
	arrow_root.add_child(arrow_head)

	# Tip (circular) handle
	arrow_handle_area = Area2D.new()
	arrow_handle_area.name = "TipHandle"
	arrow_handle_area.input_pickable = controlled_by_me
	arrow_handle_area.z_index = 2
	arrow_root.add_child(arrow_handle_area)

	arrow_handle_shape = CollisionShape2D.new()
	var tip_shape: CircleShape2D = CircleShape2D.new()
	tip_shape.radius = HANDLE_RADIUS
	arrow_handle_shape.shape = tip_shape
	arrow_handle_area.add_child(arrow_handle_shape)
	arrow_handle_area.connect("input_event", Callable(self, "_on_tip_handle_input"))

	# Head (triangle) handle
	arrow_head_area = Area2D.new()
	arrow_head_area.name = "HeadHandle"
	arrow_head_area.input_pickable = controlled_by_me
	arrow_head_area.z_index = 2
	arrow_root.add_child(arrow_head_area)

	arrow_head_poly = CollisionPolygon2D.new()
	arrow_head_area.add_child(arrow_head_poly)
	arrow_head_area.connect("input_event", Callable(self, "_on_tip_handle_input"))

	arrow_handle_area.collision_layer = 1
	arrow_handle_area.collision_mask = 0
	arrow_head_area.collision_layer = 1
	arrow_head_area.collision_mask = 0

func _sync_arrow_origin() -> void:
	if arrow_root:
		arrow_root.global_position = global_position

func _on_tip_handle_input(_vp: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not controlled_by_me:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var win: Dictionary = _nearest_piece_at_point(event.position)
		if win["node"] == self:
			_begin_drag(event.position, true)
	elif event is InputEventScreenTouch and event.pressed:
		var win_t: Dictionary = _nearest_piece_at_point(event.position)
		if win_t["node"] == self:
			_begin_drag(event.position, true)

func _update_arrow_visuals() -> void:
	if not arrow_root:
		return

	var tip: Vector2 = aim_dir * power

	# Shaft
	var head_len_vis: float = min(HEAD_LEN, power)
	var min_shaft: float = 2.0
	var shaft_len: float = max(power - head_len_vis, 0.0)
	if power > 0.0 and shaft_len < min_shaft:
		shaft_len = min(power, min_shaft)
	var base_center: Vector2 = aim_dir * shaft_len
	arrow_shaft.points = PackedVector2Array([Vector2.ZERO, base_center])

	# Head tri
	var perp: Vector2 = aim_dir.orthogonal()
	var left_vis: Vector2 = base_center + perp * (HEAD_W * 0.5)
	var right_vis: Vector2 = base_center - perp * (HEAD_W * 0.5)
	arrow_head.polygon = PackedVector2Array([tip, left_vis, right_vis])

	# Big, easy-to-grab triangle overlay
	var grab_len: float = min(HEAD_LEN + HEAD_GRAB_EXTRA_LEN, max(power, HEAD_LEN))
	var grab_base_center: Vector2 = tip - aim_dir * grab_len
	var grab_w: float = HEAD_W + HEAD_GRAB_EXTRA_W
	var left_grab: Vector2 = grab_base_center + perp * (grab_w * 0.5)
	var right_grab: Vector2 = grab_base_center - perp * (grab_w * 0.5)

	if arrow_head_area:
		arrow_head_area.position = grab_base_center

	if arrow_head_poly:
		var local_tip := tip - grab_base_center
		var local_left := left_grab - grab_base_center
		var local_right := right_grab - grab_base_center
		arrow_head_poly.polygon = PackedVector2Array([local_tip, local_left, local_right])
		_head_tri_local = arrow_head_poly.polygon

	if arrow_handle_area:
		arrow_handle_area.position = tip

	arrow_root.visible = dragging or (power > 0.5)
	if sprite:
		sprite.z_index = 1

# ---------- Firing ----------
func fire_from_current_aim() -> void:
	if power <= 0.5:
		return
	sleeping = false
	var k := float(phys.get("POWER_TO_IMPULSE", 1.29))
	var impulse: Vector2 = aim_dir * (power * k)
	apply_impulse(impulse)
	fade_out_arrow_for_shot(0.18)

func fire_from_meta() -> void:
	if not has_meta("shoot_dir") or not has_meta("power"):
		return
	var angle_deg: float = float(get_meta("shoot_dir"))
	var pwr: float = clamp(float(get_meta("power")), 0.0, MAX_POWER) # match remote cap
	if pwr <= 0.5:
		return
	aim_dir = Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
	power = pwr
	_update_arrow_visuals()
	fire_from_current_aim()
