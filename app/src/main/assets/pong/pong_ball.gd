extends RigidBody3D
class_name PongBall

const LOG_TAG := "PongBall"
const DEBUG_PONG_BALL := false

const BALL_TEXTURE_DIR := "res://pong/balls"
const DEFAULT_BALL_STYLE: int = 1
const BALL_STYLE_COUNT: int = 21

@export_range(1, BALL_STYLE_COUNT, 1) var ball_style: int = DEFAULT_BALL_STYLE

var _ball_material: StandardMaterial3D
static var _ball_texture_cache: Dictionary = {}

func dbg(parts: Variant) -> void:
	if DEBUG_PONG_BALL:
		OpLog.d(LOG_TAG, parts)

var game: PongGame
var made_in: StaticBody3D = null
var thrown: bool = false
var is_mine: bool = false
var replay_poses: Array[Vector3]

var frame_num: int = 2
var still_time: float = 0.0
var throw_time: float = 0.0
var _replay_every: int = 2

var _prev_global_pos: Vector3 = Vector3.ZERO
var _has_prev_global_pos: bool = false

const CUP_DAMP_OFFSET_Y: float = 0.124
const CUP_DAMP_RADIUS: float = 0.080
const CUP_REST_OFFSET_Y: float = 0.041
const CUP_MADE_RADIUS: float = 0.068
const BALL_AIRBORNE_Y: float = -0.375
const BALL_LIVE_BOUNCE: float = 0.85
const BALL_DEAD_BOUNCE: float = 0.10
const REST_SPEED: float = 0.15
const REST_TIME: float = 0.08
const REST_MIN_TIME: float = 1.0


func _ready() -> void:
	self.game = get_parent()

	if self.physics_material_override != null:
		self.physics_material_override = self.physics_material_override.duplicate()
	else:
		self.physics_material_override = PhysicsMaterial.new()

	self.physics_material_override.bounce = BALL_LIVE_BOUNCE
	self.physics_material_override.friction = 0.35

	self.mass = 1.0
	self.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	self.linear_damp = 0.1
	self.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	self.angular_damp = 1.0
	self.contact_monitor = true
	self.continuous_cd = true
	self.max_contacts_reported = 8
	
	_replay_every = maxi(1, roundi(Engine.physics_ticks_per_second / 30.0))
	set_ball_style(ball_style)

func set_ball_style(style: int) -> void:
	ball_style = clampi(style, 1, BALL_STYLE_COUNT)

	var sphere := get_node_or_null("CSGSphere3D") as GeometryInstance3D
	if sphere == null:
		OpLog.w(LOG_TAG, ["ball_style_missing_mesh style=", ball_style])
		return

	if _ball_material == null:
		_ball_material = StandardMaterial3D.new()
		_ball_material.roughness = 1.0
		_ball_material.metallic = 0.0

	var path := "%s/ball%d.png" % [BALL_TEXTURE_DIR, ball_style]
	var texture: Texture2D = _ball_texture_cache.get(path) as Texture2D

	if texture == null and ResourceLoader.exists(path):
		texture = ResourceLoader.load(path) as Texture2D
		if texture != null:
			_ball_texture_cache[path] = texture

	if texture == null:
		var fallback_path := "%s/ball%d.png" % [BALL_TEXTURE_DIR, DEFAULT_BALL_STYLE]
		OpLog.w(LOG_TAG, ["ball_style_missing style=", ball_style, " path=", path, " fallback=", fallback_path])

		if _ball_texture_cache.has(fallback_path):
			texture = _ball_texture_cache[fallback_path] as Texture2D
		elif ResourceLoader.exists(fallback_path):
			texture = ResourceLoader.load(fallback_path) as Texture2D
			if texture != null:
				_ball_texture_cache[fallback_path] = texture

	_ball_material.albedo_texture = texture
	sphere.material_override = _ball_material

static func available_ball_styles() -> Array[int]:
	var styles: Array[int] = []
	for style in range(1, BALL_STYLE_COUNT + 1):
		styles.append(style)
	return styles

func _physics_process(delta: float) -> void:
	if not is_mine:
		return

	if thrown:
		if frame_num >= _replay_every:
			replay_poses.append(self.position)
			frame_num = 0
		frame_num += 1

		_update_cup_entry_check(delta)

	var collisions: Array[Node3D] = get_colliding_bodies()

	if collisions.size() > 0 and not thrown:
		_store_prev_position()
		return

	if collisions.size() > 0:
		dbg([
			"ball_contact pos=", global_position,
			" vel=", linear_velocity,
			" count=", collisions.size()
		])

		for c: Node3D in collisions:
			dbg([
				"collider name=", c.name,
				" parent=", c.get_parent().name if c.get_parent() else "<no parent>",
				" path=", str(c.get_path())
			])

	_store_prev_position()

func _commit_made_cup(cup: StaticBody3D) -> void:
	if made_in != null or not is_instance_valid(cup):
		return

	var cup_name := String(cup.name)
	var cup_num := int(cup_name.replace("cup", ""))

	if cup_num <= 0:
		OpLog.w(LOG_TAG, [
			"cup_commit_invalid_name name=", cup_name,
			" pos=", global_position
		])
		return

	made_in = cup.duplicate()

	OpLog.i(LOG_TAG, [
		"cup_made cup=", cup_name,
		" cupNum=", cup_num,
		" stillTime=", still_time,
		" throwTime=", throw_time,
		" pos=", global_position,
		" vel=", linear_velocity
	])

	await game.my_cups.remove_cup(cup_num)
	remove()

func _update_cup_entry_check(delta: float) -> void:
	if made_in != null:
		return

	if not is_instance_valid(game) or not is_instance_valid(game.my_cups):
		return

	throw_time += delta

	if global_position.y > BALL_AIRBORNE_Y:
		physics_material_override.bounce = BALL_LIVE_BOUNCE
	elif _nearest_cup(CUP_DAMP_OFFSET_Y, CUP_DAMP_RADIUS) != null:
		physics_material_override.bounce = BALL_DEAD_BOUNCE

	if (
		not _has_prev_global_pos
		or linear_velocity.length() >= REST_SPEED
		or throw_time < REST_MIN_TIME
	):
		still_time = 0.0
		return

	still_time += delta

	if still_time < REST_TIME:
		return

	var cup: StaticBody3D = _nearest_cup(CUP_REST_OFFSET_Y, CUP_MADE_RADIUS)

	if cup != null:
		await _commit_made_cup(cup)

func _nearest_cup(offset_y: float, radius: float) -> StaticBody3D:
	var best: StaticBody3D = null
	var best_dist: float = radius

	for child: Node in game.my_cups.get_children():
		var cup := child as StaticBody3D

		if not is_instance_valid(cup) or cup.name == &"cupremoved" or not cup.visible:
			continue

		var dist: float = global_position.distance_to(
			cup.global_position + Vector3(0.0, offset_y, 0.0)
		)

		if dist < best_dist:
			best_dist = dist
			best = cup

	return best

func _store_prev_position() -> void:
	_prev_global_pos = global_position
	_has_prev_global_pos = true

func throw(x_force: float, y_force: float) -> void:
	OpLog.i(LOG_TAG, [
		"throw_old_api xForce=", x_force,
		" yForce=", y_force,
		" pos=", global_position
	])

	apply_impulse(Vector3(-x_force, -1.30, y_force))
	thrown = true
	_store_prev_position()

	await get_tree().create_timer(3.0).timeout

	if not is_inside_tree() or made_in != null:
		return

	var final_cup: StaticBody3D = _nearest_cup(CUP_REST_OFFSET_Y, CUP_MADE_RADIUS)

	if final_cup != null:
		OpLog.i(LOG_TAG, [
			"cup_timeout_rescue cup=", final_cup.name,
			" pos=", global_position,
			" vel=", linear_velocity
		])

		await _commit_made_cup(final_cup)
		return

	remove()

func remove():
	if is_mine:
		if made_in == null:
			var late_cup: StaticBody3D = _nearest_cup(CUP_REST_OFFSET_Y, CUP_MADE_RADIUS)

			OpLog.i(LOG_TAG, [
				"ball_remove_check still=", still_time,
				" throwTime=", throw_time,
				" speed=", linear_velocity.length(),
				" lateCup=", late_cup.name if late_cup != null else "<none>",
				" pos=", global_position
			])

			if late_cup != null:
				made_in = late_cup.duplicate()
				game.my_cups.remove_cup(int(String(late_cup.name).replace("cup", "")))

		if made_in != null:
			var cup_num: int = int(String(made_in.name).replace("cup", ""))
			OpLog.i(LOG_TAG, ["ball_remove made cup=", cup_num, " replayPoints=", replay_poses.size()])
			game.throws.append({"poses": replay_poses, "cup": cup_num - 1})
		else:
			OpLog.i(LOG_TAG, ["ball_remove miss replayPoints=", replay_poses.size()])
			game.throws.append({"poses": replay_poses, "cup": -1})

		game.throw_finished()

	queue_free()
