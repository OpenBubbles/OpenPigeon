extends RigidBody3D
class_name PongBall

var game: PongGame
var hit_cup: StaticBody3D = null
var made_in: StaticBody3D = null
var thrown: bool = false
var is_mine: bool = false
var replay_poses: Array[Vector3]

var frame_num: int = 2
var num_collisions: int = 0
var soft_cup_frames: int = 0
var soft_cup_name: String = ""

var _prev_global_pos: Vector3 = Vector3.ZERO
var _has_prev_global_pos: bool = false

const CUP_MOUTH_Y: float = -0.445
const CUP_KILL_Y: float = -0.515

# Tighter than before. This is the actual "went into the mouth" radius.
const CUP_ENTER_RADIUS: float = 0.092

# Slightly larger than enter radius so a real in-cup ball can wobble/rim around.
const CUP_STAY_RADIUS: float = 0.118

# If it gets this far away after being assigned, it clearly bounced/rimmed out.
const CUP_RESET_RADIUS: float = 0.165

const CUP_MIN_FRAMES: int = 12
const CUP_MAX_XZ_SPEED: float = 1.45


func _ready() -> void:
	self.game = get_parent()

	if self.physics_material_override != null:
		self.physics_material_override = self.physics_material_override.duplicate()
	else:
		self.physics_material_override = PhysicsMaterial.new()

	self.physics_material_override.bounce = 0.22
	self.physics_material_override.friction = 0.68

	self.mass = 1.0
	self.linear_damp = 0.03
	self.angular_damp = 0.15
	self.contact_monitor = true
	self.max_contacts_reported = 8


func _physics_process(_delta: float) -> void:
	if not is_mine:
		return

	if thrown:
		if frame_num >= 2:
			replay_poses.append(self.position)
			frame_num = 0
		frame_num += 1

		_update_cup_entry_check()

	var collisions: Array[Node3D] = get_colliding_bodies()

	if collisions.size() > 0 and not thrown:
		_store_prev_position()
		return

	if collisions.size() > 0:
		print("ball_contact pos=(%.3f, %.3f, %.3f) vel=%s hit_count=%d" % [
			position.x,
			position.y,
			position.z,
			str(linear_velocity),
			collisions.size()
		])

		for c: Node3D in collisions:
			print("  collider name='%s' parent='%s' parent_path='%s'" % [
				c.name,
				c.get_parent().name if c.get_parent() else "<no parent>",
				str(c.get_path())
			])

	if made_in == null and hit_cup == null:
		for collision: Node3D in collisions:
			if "CupMesh" not in collision.name:
				continue

			var parent := collision.get_parent() as StaticBody3D
			if parent == null:
				continue

			if _ball_really_entered_cup(parent):
				_set_hit_cup(parent)
				break
			else:
				print("rim / outside cup")

	_store_prev_position()


func _update_cup_entry_check() -> void:
	if made_in != null or not is_instance_valid(game) or not is_instance_valid(game.my_cups):
		return

	if hit_cup == null:
		var entered_cup: StaticBody3D = _find_entered_cup()
		if entered_cup != null:
			_set_hit_cup(entered_cup)
		else:
			soft_cup_frames = 0
		return

	if not is_instance_valid(hit_cup):
		hit_cup = null
		soft_cup_frames = 0
		return

	var cup_pos: Vector3 = hit_cup.global_position
	var dist: float = Vector2(global_position.x - cup_pos.x, global_position.z - cup_pos.z).length()
	var below_mouth: bool = global_position.y < CUP_MOUTH_Y
	var deep_in_cup: bool = global_position.y < CUP_KILL_Y
	var still_inside: bool = dist <= CUP_STAY_RADIUS and below_mouth
	var clearly_out: bool = dist > CUP_RESET_RADIUS or global_position.y > CUP_MOUTH_Y + 0.045

	if still_inside:
		soft_cup_frames += 1

		if self.physics_material_override != null:
			self.physics_material_override.bounce = minf(self.physics_material_override.bounce, 0.08)

		if soft_cup_frames >= CUP_MIN_FRAMES or (deep_in_cup and dist <= CUP_ENTER_RADIUS):
			made_in = hit_cup.duplicate()
			print("confirmed made it in! " + str(made_in.name))
			await game.my_cups.remove_cup(int(made_in.name.replace("cup", "")))
			remove()
			return
	else:
		soft_cup_frames = max(0, soft_cup_frames - 1)

		if clearly_out:
			print("cup rejected / bounced out")
			hit_cup = null
			soft_cup_frames = 0


func _find_entered_cup() -> StaticBody3D:
	if not _has_prev_global_pos:
		return null

	var best_cup: StaticBody3D = null
	var best_dist: float = INF

	for cup in game.my_cups.get_children():
		if cup == null or not (cup is StaticBody3D):
			continue
		if cup.name == &"cupremoved" or not cup.visible:
			continue

		if not _ball_really_entered_cup(cup as StaticBody3D):
			continue

		var cup_pos: Vector3 = (cup as StaticBody3D).global_position
		var dist: float = Vector2(global_position.x - cup_pos.x, global_position.z - cup_pos.z).length()

		if dist < best_dist:
			best_dist = dist
			best_cup = cup as StaticBody3D

	return best_cup


func _ball_really_entered_cup(cup: StaticBody3D) -> bool:
	if not _has_prev_global_pos or not is_instance_valid(cup):
		return false

	# Must cross the cup mouth plane from above to below.
	if _prev_global_pos.y < CUP_MOUTH_Y or global_position.y > CUP_MOUTH_Y:
		return false

	var dy: float = _prev_global_pos.y - global_position.y
	if dy <= 0.0001:
		return false

	var t: float = clampf((_prev_global_pos.y - CUP_MOUTH_Y) / dy, 0.0, 1.0)
	var crossing_pos: Vector3 = _prev_global_pos.lerp(global_position, t)

	var cup_pos: Vector3 = cup.global_position
	var crossing_dist: float = Vector2(crossing_pos.x - cup_pos.x, crossing_pos.z - cup_pos.z).length()
	var current_dist: float = Vector2(global_position.x - cup_pos.x, global_position.z - cup_pos.z).length()
	var xz_speed: float = Vector2(linear_velocity.x, linear_velocity.z).length()

	# This is the key fix: next-to-cup balls can be low, but they did not cross
	# through the cup mouth inside the inner radius.
	return crossing_dist <= CUP_ENTER_RADIUS \
		and current_dist <= CUP_STAY_RADIUS \
		and linear_velocity.y < 0.15 \
		and xz_speed <= CUP_MAX_XZ_SPEED


func _set_hit_cup(cup: StaticBody3D) -> void:
	if hit_cup == cup:
		return

	hit_cup = cup
	soft_cup_name = String(cup.name)
	soft_cup_frames = 0
	num_collisions = 0

	print("cup entered " + str(cup.name))

	if self.physics_material_override != null:
		self.physics_material_override.bounce = minf(self.physics_material_override.bounce, 0.08)


func _store_prev_position() -> void:
	_prev_global_pos = global_position
	_has_prev_global_pos = true


func throw(x_force: float, y_force: float):
	apply_impulse(Vector3(-x_force, -1.30, y_force))
	thrown = true
	_store_prev_position()
	await get_tree().create_timer(3).timeout
	remove()


func remove():
	if is_mine:
		if made_in != null:
			var cup_num: int = int(made_in.name.replace("cup", ""))
			print("MADE IN CUP NUM: " + str(cup_num))
			game.throws.append({"poses": replay_poses, "cup": cup_num - 1})
		else:
			game.throws.append({"poses": replay_poses, "cup": -1})

		game.throw_finished()

	queue_free()
