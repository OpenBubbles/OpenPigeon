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

const CUP_ENTER_RADIUS: float = 0.128
const CUP_STAY_RADIUS: float = 0.155
const CUP_ENTER_Y: float = -0.405
const CUP_KILL_Y: float = -0.500
const CUP_MIN_FRAMES: int = 14
const CUP_MAX_XZ_SPEED: float = 1.55

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

		_update_ios_style_cup_check()

	var collisions: Array[Node3D] = get_colliding_bodies()

	if collisions.size() > 0 and not thrown:
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

	if made_in != null:
		return

	if hit_cup == null:
		for collision: Node3D in collisions:
			if "CupMesh" not in collision.name:
				continue

			var parent := collision.get_parent() as StaticBody3D
			if parent == null:
				continue

			var xz_speed: float = Vector2(linear_velocity.x, linear_velocity.z).length()
			var low_enough: bool = global_position.y < CUP_ENTER_Y
			var not_skipping_across: bool = xz_speed <= CUP_MAX_XZ_SPEED

			if low_enough and not_skipping_across:
				_set_hit_cup(parent)
				break
			else:
				print("bouncer!")


func _update_ios_style_cup_check() -> void:
	if made_in != null or not is_instance_valid(game) or not is_instance_valid(game.my_cups):
		return

	var nearest_cup: StaticBody3D = null
	var nearest_dist: float = INF

	for cup in game.my_cups.get_children():
		if cup == null or not (cup is StaticBody3D):
			continue
		if cup.name == &"cupremoved" or not cup.visible:
			continue

		var cup_pos: Vector3 = (cup as StaticBody3D).global_position
		var dxz: float = Vector2(global_position.x - cup_pos.x, global_position.z - cup_pos.z).length()

		if dxz < nearest_dist:
			nearest_dist = dxz
			nearest_cup = cup as StaticBody3D

	if nearest_cup == null:
		soft_cup_frames = 0
		return

	var xz_speed: float = Vector2(linear_velocity.x, linear_velocity.z).length()
	var falling_or_low: bool = linear_velocity.y < 0.20 or global_position.y < CUP_ENTER_Y
	var low_enough: bool = global_position.y < CUP_ENTER_Y
	var centered_enough: bool = nearest_dist <= CUP_ENTER_RADIUS
	var not_skipping_across: bool = xz_speed <= CUP_MAX_XZ_SPEED

	if hit_cup == null:
		if centered_enough and low_enough and falling_or_low and not_skipping_across:
			_set_hit_cup(nearest_cup)
		else:
			soft_cup_frames = 0
		return

	if not is_instance_valid(hit_cup):
		hit_cup = null
		soft_cup_frames = 0
		return

	var hit_pos: Vector3 = hit_cup.global_position
	var hit_dist: float = Vector2(global_position.x - hit_pos.x, global_position.z - hit_pos.z).length()
	var still_in_cup_area: bool = hit_dist <= CUP_STAY_RADIUS and global_position.y < -0.390

	if still_in_cup_area:
		soft_cup_frames += 1

		if self.physics_material_override != null:
			self.physics_material_override.bounce = minf(self.physics_material_override.bounce, 0.08)

		if soft_cup_frames >= CUP_MIN_FRAMES or global_position.y < CUP_KILL_Y:
			made_in = hit_cup.duplicate()
			print("ios-style made it in! " + str(made_in.name))
			await game.my_cups.remove_cup(int(made_in.name.replace("cup", "")))
			remove()
			return
	else:
		soft_cup_frames = max(0, soft_cup_frames - 1)

		if hit_dist > CUP_STAY_RADIUS * 1.6 or global_position.y > -0.30:
			hit_cup = null
			soft_cup_frames = 0


func _set_hit_cup(cup: StaticBody3D) -> void:
	if hit_cup == cup:
		return

	hit_cup = cup
	soft_cup_name = String(cup.name)
	soft_cup_frames = 0
	num_collisions = 0

	print("ios-style set cup " + str(cup.name))

	if self.physics_material_override != null:
		self.physics_material_override.bounce = minf(self.physics_material_override.bounce, 0.08)


func throw(x_force: float, y_force: float):
	apply_impulse(Vector3(-x_force, -1.30, y_force))
	thrown = true
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
