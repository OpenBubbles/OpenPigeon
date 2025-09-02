extends RigidBody2D
signal aim_changed(angle_degrees: float, power: float)

# --- Debug toggle ---
const DEBUG_AIM: bool = false
func _dbg(msg: String) -> void:
	if DEBUG_AIM:
		print("[PIECE][%s] %s" % [name, msg])

# --- Aim / UI tunables ---
const MAX_POWER: float = 150.0
const MAX_ARROW_LENGTH: float = 240.0
const ANGLE_STEP_DEG: float = 2.0
const POWER_STEP: float = 3.0
const INTERACT_RADIUS: float = 24.0
const HEAD_LEN: float = 18.0
const HEAD_W: float = 24.0
const HANDLE_RADIUS: float = 40.0
const HEAD_GRAB_EXTRA_LEN: float = 28.0
const HEAD_GRAB_EXTRA_W: float = 28.0
const ARROW_SHAFT_WIDTH: float = 8.0
const ARROW_COLOR: Color = Color(0,0,0,1)

# --- Physics tunables (slidey feel) ---
const POWER_TO_IMPULSE: float = 1.29
const LINEAR_DAMP_CUSTOM: float = 0.25
const ANGULAR_DAMP_CUSTOM: float = 0.45
const MAT_FRICTION: float = 0.02
const MAT_BOUNCE: float = 0.30
const SHOOT_ON_RELEASE: bool = false

# --- Nodes ---
@onready var sprite: Sprite2D = $Sprite2D

var arrow_root: Node2D
var arrow_shaft: Line2D
var arrow_head: Polygon2D
var arrow_handle_area: Area2D
var arrow_handle_shape: CollisionShape2D
var arrow_head_area: Area2D
var arrow_head_poly: CollisionPolygon2D

# --- State ---
var pulse_tween: Tween
var arrow_fade_tween: Tween
var controlled_by_me: bool = false
var dragging: bool = false
var dragging_handle: bool = false
var aim_dir: Vector2 = Vector2.RIGHT
var power: float = 0.0
var last_q_angle: int = -999_999
var last_q_power: int = -999_999

func _ready() -> void:
	set_process_input(true)

	# No gravity, slidey feel
	gravity_scale = 0.0

	var pm := PhysicsMaterial.new()
	pm.friction = MAT_FRICTION
	pm.bounce = MAT_BOUNCE
	physics_material_override = pm

	linear_damp = LINEAR_DAMP_CUSTOM
	angular_damp = ANGULAR_DAMP_CUSTOM

	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	lock_rotation = false

	# collide with other pieces (layer 1 <-> layer 1)
	collision_layer = 1
	collision_mask  = 1

	# Make sure the body itself has a CollisionShape2D
	_ensure_body_collision_shape()

	_build_arrow_if_needed()
	_update_arrow_visuals()

	if sprite:
		sprite.z_index = 1
		
func _ensure_body_collision_shape() -> void:
	# If a CollisionShape2D already exists directly under the body, use it.
	var body_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape:
		return

	# Try to find a shape under a child Area2D and clone it onto the body
	var area := get_node_or_null("Area2D") as Area2D
	if area:
		var area_shape := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if area_shape and area_shape.shape:
			var new_body_shape := CollisionShape2D.new()
			new_body_shape.name = "CollisionShape2D"
			new_body_shape.shape = area_shape.shape.duplicate(true)
			add_child(new_body_shape)
			return

	# Fallback: create a default circle if nothing found
	var fallback := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	fallback.shape = circle
	add_child(fallback)

func set_controlled_by_me(v: bool) -> void:
	controlled_by_me = v
	if arrow_handle_area: arrow_handle_area.input_pickable = v
	if arrow_head_area: arrow_head_area.input_pickable = v

# ---------------- INPUT (drag to aim) ----------------
func _input(event: InputEvent) -> void:
	if not controlled_by_me:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var close: bool = _pointer_close_enough(event.position)
			if close:
				_begin_drag(event.position, false)
		else:
			if dragging and not dragging_handle:
				_update_aim_from_global_pos(event.position)
				_end_drag()
	elif event is InputEventMouseMotion and dragging and not dragging_handle:
		_update_aim_from_global_pos(event.position)

	if event is InputEventScreenTouch:
		if event.pressed:
			if _pointer_close_enough(event.position):
				_begin_drag(event.position, false)
		else:
			if dragging and not dragging_handle:
				_update_aim_from_global_pos(event.position)
				_end_drag()
	elif event is InputEventScreenDrag and dragging and not dragging_handle:
		_update_aim_from_global_pos(event.position)

func _pointer_close_enough(global_pos: Vector2) -> bool:
	var local: Vector2 = to_local(global_pos)
	return local.length() <= INTERACT_RADIUS

func _begin_drag(global_pos: Vector2, from_handle: bool=false) -> void:
	dragging = true
	dragging_handle = from_handle
	if arrow_root:
		# make sure it's actually visible again after hide_arrow()
		arrow_root.visible = true
		# kill any in-flight fade tween and restore alpha
		if arrow_fade_tween and arrow_fade_tween.is_running():
			arrow_fade_tween.kill()
		arrow_root.modulate.a = 1.0
	_update_aim_from_global_pos(global_pos)

func _end_drag() -> void:
	dragging = false
	dragging_handle = false
	if SHOOT_ON_RELEASE:
		fire_from_current_aim()
		
# Show/refresh arrow from replay (angle in degrees, power in pixels)
func show_arrow_from_replay(angle_deg: float, pow_px: float, fade_sec: float = 0.18) -> void:
	aim_dir = Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
	power = remap(pow_px, 0.0, MAX_ARROW_LENGTH,0.0, MAX_POWER)
	_update_arrow_visuals()
	if arrow_root:
		arrow_root.visible = true
		# reset any previous tween and alpha before fading in
		if arrow_fade_tween and arrow_fade_tween.is_running():
			arrow_fade_tween.kill()
		if fade_sec <= 0.0:
			arrow_root.modulate.a = 1.0
		else:
			arrow_root.modulate.a = 0.0
			arrow_fade_tween = create_tween()
			arrow_fade_tween.tween_property(arrow_root, "modulate:a", 1.0, fade_sec)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# Optional direct rotate (radians)
func rotate_to_angle_rad(angle_rad: float, dur: float = 0.18) -> void:
	var tw := create_tween()
	tw.tween_property(self, "rotation", angle_rad, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# Fire using current arrow (if you prefer calling from outside)
func fire_current_arrow(power_to_impulse: float = 1.29) -> void:
	if power <= 0.5:
		return
	if self is RigidBody2D:
		var impulse: Vector2 = aim_dir * (power * power_to_impulse)
		(self as RigidBody2D).apply_impulse(impulse)

func _update_aim_from_global_pos(global_pos: Vector2) -> void:
	var local: Vector2 = to_local(global_pos)
	var tip_local: Vector2 = local.limit_length(MAX_ARROW_LENGTH)

	var local_len: float = tip_local.length()
	var dir: Vector2 = tip_local / max(local_len, 0.0001)

	var angle_deg: float = fposmod(rad_to_deg(dir.angle()), 360.0)
	var q_angle: int = int(round(angle_deg / ANGLE_STEP_DEG))
	var q_power: int = int(round(local_len / POWER_STEP))
	_maybe_tick(q_angle, q_power)

	aim_dir = dir
	power = local_len

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
	_update_arrow_visuals()                # sets visible=false because power=0
	if arrow_root:
		arrow_root.modulate.a = 0.0       # nuke any fade-in effect
		arrow_root.visible = false
	set_meta("shoot_dir", 0.0)
	set_meta("power", 0.0)

# ---------------- ARROW BUILD/VISUALS ----------------
func _build_arrow_if_needed() -> void:
	if arrow_root:
		return

	arrow_root = Node2D.new()
	arrow_root.name = "Arrow"
	add_child(arrow_root)
	arrow_root.visible = false
	arrow_root.z_as_relative = true
	arrow_root.z_index = 0  # visuals below sprite

	arrow_shaft = Line2D.new()
	arrow_shaft.name = "Shaft"
	arrow_shaft.width = ARROW_SHAFT_WIDTH
	arrow_shaft.antialiased = true
	arrow_shaft.default_color = ARROW_COLOR
	arrow_shaft.begin_cap_mode = Line2D.LINE_CAP_NONE
	arrow_shaft.end_cap_mode = Line2D.LINE_CAP_NONE
	arrow_root.add_child(arrow_shaft)

	arrow_head = Polygon2D.new()
	arrow_head.color = ARROW_COLOR
	arrow_root.add_child(arrow_head)

	# Tip circle picker (invisible)
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

	# Head triangle picker (invisible, larger than visual)
	arrow_head_area = Area2D.new()
	arrow_head_area.name = "HeadHandle"
	arrow_head_area.input_pickable = controlled_by_me
	arrow_head_area.z_index = 2
	arrow_root.add_child(arrow_head_area)

	arrow_head_poly = CollisionPolygon2D.new()
	arrow_head_area.add_child(arrow_head_poly)
	arrow_head_area.connect("input_event", Callable(self, "_on_tip_handle_input"))
	
	arrow_handle_area.collision_layer = 0
	arrow_handle_area.collision_mask  = 0
	arrow_head_area.collision_layer   = 0
	arrow_head_area.collision_mask    = 0

func _on_tip_handle_input(_vp: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not controlled_by_me:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position, true)
		else:
			if dragging and dragging_handle:
				_update_aim_from_global_pos(event.position)
				_end_drag()
	elif event is InputEventMouseMotion and dragging and dragging_handle:
		_update_aim_from_global_pos(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_drag(event.position, true)
		else:
			if dragging and dragging_handle:
				_update_aim_from_global_pos(event.position)
				_end_drag()
	elif event is InputEventScreenDrag and dragging and dragging_handle:
		_update_aim_from_global_pos(event.position)

func _update_arrow_visuals() -> void:
	if not arrow_root:
		return

	var tip: Vector2 = aim_dir * power

	# Keep shaft visible even when short
	var head_len_vis: float = min(HEAD_LEN, power)
	var min_shaft: float = 2.0
	var shaft_len: float = max(power - head_len_vis, 0.0)
	if power > 0.0 and shaft_len < min_shaft:
		shaft_len = min(power, min_shaft)

	var base_center: Vector2 = aim_dir * shaft_len
	arrow_shaft.points = PackedVector2Array([Vector2.ZERO, base_center])

	var perp: Vector2 = aim_dir.orthogonal()
	var left_vis: Vector2 = base_center + perp * (HEAD_W * 0.5)
	var right_vis: Vector2 = base_center - perp * (HEAD_W * 0.5)
	var head_poly_vis: PackedVector2Array = PackedVector2Array([tip, left_vis, right_vis])
	arrow_head.polygon = head_poly_vis

	# Larger click area for the head
	var grab_len: float = min(HEAD_LEN + HEAD_GRAB_EXTRA_LEN, max(power, HEAD_LEN))
	var grab_base_center: Vector2 = tip - aim_dir * grab_len
	var grab_w: float = HEAD_W + HEAD_GRAB_EXTRA_W
	var left_grab: Vector2 = grab_base_center + perp * (grab_w * 0.5)
	var right_grab: Vector2 = grab_base_center - perp * (grab_w * 0.5)
	var head_poly_grab: PackedVector2Array = PackedVector2Array([tip, left_grab, right_grab])

	if arrow_handle_area:
		arrow_handle_area.position = tip
	if arrow_head_poly:
		arrow_head_poly.polygon = head_poly_grab

	# Draw order: keep visuals below sprite
	arrow_root.visible = dragging or (power > 0.5)
	if sprite:
		sprite.z_index = 1

# ---------------- SHOOT / IMPULSE ----------------
func fire_from_current_aim(power_to_impulse: float = 1.29) -> void:
	if power <= 0.5:
		return
	sleeping = false
	var impulse: Vector2 = aim_dir * (power * power_to_impulse)
	apply_impulse(impulse)

func fire_from_meta() -> void:
	if not has_meta("shoot_dir") or not has_meta("power"):
		return

	var angle_deg: float = float(get_meta("shoot_dir"))
	var pwr: float = clamp(float(get_meta("power")), 0.0, MAX_POWER)
	if pwr <= 0.5:
		return

	aim_dir = Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
	power = pwr
	_update_arrow_visuals()
	fire_from_current_aim()
