extends RigidBody2D
signal aim_changed(angle_degrees: float, power: float)

# ---------- Arrow / input UI tuning ----------
const MAX_POWER: float = 150.0
const MAX_ARROW_LENGTH: float = MAX_POWER
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
const IOS_STOP_LINEAR_SPEED: float = 1.0
const IOS_STOP_ANGULAR_SPEED: float = 0.08
const POWER_TO_VELOCITY: float = 2.0
const IOS_ARROW_REPLAY_ALPHA: float = 0.8
const IOS_ARROW_REPLAY_FADE_SEC: float = 0.5
const IOS_ARROW_SHOT_FADE_SEC: float = 0.18
const DEBUG_CONTACTS: bool = false
const IOS_BODY_RADIUS: float = 12.5
const IOS_COLLISION_RADIUS_PAD: float = 0.0

var phys := {
	"PPM": 32.0,
	"PIECE_RADIUS_PX": IOS_BODY_RADIUS + IOS_COLLISION_RADIUS_PAD,
	"FRICTION": 1.0,
	"RESTITUTION": 1.0,
	"LINEAR_DAMP": 1.35,
	"ANGULAR_DAMP": 0.0,
	"DENSITY": 1.0,
	"GRAVITY_SCALE": 0.0,
	"CCD_MODE": RigidBody2D.CCD_MODE_CAST_SHAPE,
	"LOCK_ROTATION": false,
	"CAN_SLEEP": false
}

func set_physics_params(p: Dictionary) -> void:
	for k in p.keys():
		phys[k] = p[k]
	_apply_phys_now()
	
func _force_ios_body_collision_shape() -> void:
	var body_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape == null:
		body_shape = CollisionShape2D.new()
		body_shape.name = "CollisionShape2D"
		add_child(body_shape)

	body_shape.position = Vector2.ZERO
	body_shape.rotation = 0.0
	body_shape.scale = Vector2.ONE
	body_shape.disabled = false

	if not (body_shape.shape is CircleShape2D):
		body_shape.shape = CircleShape2D.new()
	else:
		body_shape.shape = body_shape.shape.duplicate(true)

	var radius: float = float(phys.get("PIECE_RADIUS_PX", IOS_BODY_RADIUS))
	(body_shape.shape as CircleShape2D).radius = radius

	if not has_meta("printed_collision_radius"):
		set_meta("printed_collision_radius", true)
		print("[PIECE_COLLIDER]",
			" name=", name,
			" radius=", radius,
			" diameter=", radius * 2.0,
			" global_scale=", global_transform.get_scale()
		)
		
func _apply_phys_now() -> void:
	gravity_scale = float(phys.get("GRAVITY_SCALE", 0.0))
	continuous_cd = int(phys.get("CCD_MODE", RigidBody2D.CCD_MODE_DISABLED))
	lock_rotation = bool(phys.get("LOCK_ROTATION", false))
	can_sleep = bool(phys.get("CAN_SLEEP", false))

	# Let Box2D apply damping natively.
	linear_damp = float(phys.get("LINEAR_DAMP", 1.35))
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE

	angular_damp = float(phys.get("ANGULAR_DAMP", 0.0))
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE

	_force_ios_body_collision_shape()

	var pm: PhysicsMaterial = physics_material_override
	if pm == null:
		pm = PhysicsMaterial.new()
		physics_material_override = pm

	pm.friction = float(phys.get("FRICTION", 1.0))
	pm.bounce = float(phys.get("RESTITUTION", 1.0))
	
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
	
	contact_monitor = DEBUG_CONTACTS
	max_contacts_reported = 8
	if DEBUG_CONTACTS and not body_entered.is_connected(_on_debug_body_entered):
		body_entered.connect(_on_debug_body_entered)

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
		
func _on_debug_body_entered(body: Node) -> void:
	if not DEBUG_CONTACTS:
		return
	if body is RigidBody2D:
		print("[PIECE_CONTACT]",
			" self=", name,
			" other=", body.name,
			" self_pos=", position,
			" other_pos=", (body as RigidBody2D).position,
			" self_v=", linear_velocity.length(),
			" other_v=", (body as RigidBody2D).linear_velocity.length()
		)

func _make_circle_poly(r: float, segs: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var a := TAU * float(i) / float(segs)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts
	
func _integrate_forces(_state: PhysicsDirectBodyState2D) -> void:
	pass
	
func _physics_process(_dt: float) -> void:
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
	
func _motion_scale() -> float:
	var parent_node: Node2D = get_parent() as Node2D
	if parent_node == null:
		return 1.0

	var global_scale: Vector2 = parent_node.get_global_transform().get_scale()
	return maxf(0.001, (absf(global_scale.x) + absf(global_scale.y)) * 0.5)

func _ensure_body_collision_shape() -> void:
	_force_ios_body_collision_shape()

# ---------- Control / picking ----------
func set_controlled_by_me(v: bool) -> void:
	controlled_by_me = v

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
func show_arrow_from_replay(angle_deg: float, pow_px: float, fade_sec: float = IOS_ARROW_REPLAY_FADE_SEC) -> void:
	aim_dir = Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
	power = clamp(pow_px, 0.0, MAX_POWER)
	_update_arrow_visuals()

	if arrow_root:
		_sync_arrow_origin()
		arrow_root.visible = true

		if arrow_fade_tween and arrow_fade_tween.is_running():
			arrow_fade_tween.kill()

		arrow_root.modulate.a = 0.0
		arrow_fade_tween = create_tween()
		arrow_fade_tween.tween_property(arrow_root, "modulate:a", IOS_ARROW_REPLAY_ALPHA, fade_sec)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_OUT)

func rotate_to_angle_rad(angle_rad: float, dur: float = 0.18) -> void:
	var tw := create_tween()
	tw.tween_property(self, "rotation", angle_rad, dur)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------- Aiming ----------
func _update_aim_from_global_pos(global_pos: Vector2) -> void:
	var delta: Vector2 = global_pos - global_position
	var parent_node: Node2D = get_parent() as Node2D

	if parent_node != null:
		delta = parent_node.to_local(global_pos) - position

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
	arrow_handle_area.input_pickable = false
	arrow_handle_area.monitoring = false
	arrow_handle_area.monitorable = false
	arrow_handle_area.collision_layer = 0
	arrow_handle_area.collision_mask = 0
	arrow_handle_area.z_index = 2
	arrow_root.add_child(arrow_handle_area)

	arrow_handle_shape = CollisionShape2D.new()
	var tip_shape: CircleShape2D = CircleShape2D.new()
	tip_shape.radius = HANDLE_RADIUS
	arrow_handle_shape.shape = tip_shape
	arrow_handle_shape.disabled = true
	arrow_handle_area.add_child(arrow_handle_shape)

	# Head (triangle) handle
	arrow_head_area = Area2D.new()
	arrow_head_area.name = "HeadHandle"
	arrow_head_area.input_pickable = false
	arrow_head_area.monitoring = false
	arrow_head_area.monitorable = false
	arrow_head_area.collision_layer = 0
	arrow_head_area.collision_mask = 0
	arrow_head_area.z_index = 2
	arrow_root.add_child(arrow_head_area)

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

	var visual_scale: float = 1.0
	var parent_node: Node2D = get_parent() as Node2D
	if parent_node != null:
		var global_scale: Vector2 = parent_node.get_global_transform().get_scale()
		visual_scale = maxf(0.001, (absf(global_scale.x) + absf(global_scale.y)) * 0.5)

	var visual_power: float = power * visual_scale
	var tip: Vector2 = aim_dir * visual_power

	var head_len_vis: float = min(HEAD_LEN, visual_power)
	var min_shaft: float = 2.0
	var shaft_len: float = max(visual_power - head_len_vis, 0.0)
	if visual_power > 0.0 and shaft_len < min_shaft:
		shaft_len = min(visual_power, min_shaft)

	var base_center: Vector2 = aim_dir * shaft_len
	arrow_shaft.points = PackedVector2Array([Vector2.ZERO, base_center])

	var perp: Vector2 = aim_dir.orthogonal()
	var left_vis: Vector2 = base_center + perp * (HEAD_W * 0.5)
	var right_vis: Vector2 = base_center - perp * (HEAD_W * 0.5)
	arrow_head.polygon = PackedVector2Array([tip, left_vis, right_vis])

	var grab_len: float = min(HEAD_LEN + HEAD_GRAB_EXTRA_LEN, max(visual_power, HEAD_LEN))
	var grab_base_center: Vector2 = tip - aim_dir * grab_len
	var grab_w: float = HEAD_W + HEAD_GRAB_EXTRA_W
	var left_grab: Vector2 = grab_base_center + perp * (grab_w * 0.5)
	var right_grab: Vector2 = grab_base_center - perp * (grab_w * 0.5)

	if arrow_head_area:
		arrow_head_area.position = grab_base_center

	var local_tip := tip - grab_base_center
	var local_left := left_grab - grab_base_center
	var local_right := right_grab - grab_base_center
	_head_tri_local = PackedVector2Array([local_tip, local_left, local_right])

	if arrow_handle_area:
		arrow_handle_area.position = tip

	arrow_root.visible = dragging or (power > 0.5)

	if sprite:
		sprite.z_index = 1

func fire_from_current_aim() -> void:
	if power <= 0.5:
		return

	var motion_scale: float = _motion_scale()

	sleeping = false
	angular_velocity = 0.0
	rotation = aim_dir.angle() - PI * 0.5
	linear_velocity = aim_dir * (power * POWER_TO_VELOCITY * motion_scale)
	fade_out_arrow_for_shot(IOS_ARROW_SHOT_FADE_SEC)
	
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
