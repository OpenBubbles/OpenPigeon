extends RigidBody3D
class_name PongBall

var game: PongGame
var hit_cup: StaticBody3D = null
var made_in: StaticBody3D = null
var thrown: bool = false
var is_mine: bool = false
var replay_poses: Array[Vector3]

func _ready() -> void:
	self.game = get_parent()
	self.physics_material_override = self.physics_material_override.duplicate()
	self.mass = 1.0

var frame_num: int = 2
var num_collisions: int = 0
func _physics_process(delta: float) -> void:
	if is_mine:
		if thrown:
			if frame_num >= 2:
				replay_poses.append(self.position)
				frame_num = 0
			frame_num += 1
			
		var collisions = get_colliding_bodies()
		if collisions.size() > 0 and not thrown:
			pass  # ignore pre-throw contacts (sitting on table)
		elif collisions.size() > 0:
			print("ball_contact pos=(%.3f, %.3f, %.3f) vel=%s  hit_count=%d" % [position.x, position.y, position.z, str(linear_velocity), collisions.size()])
			for c in collisions:
				print("  collider name='%s' parent='%s' parent_path='%s'" % [c.name, c.get_parent().name if c.get_parent() else "<no parent>", str(c.get_path())])
		if hit_cup == null:
			if len(collisions) == 1:
				for collision in collisions:
					if "CupMesh" in collision.name:
						if self.position.y < -0.415:
							self.physics_material_override.bounce = 0.0
							self.linear_velocity = Vector3(0, 0, 0)
							hit_cup = collision.get_parent()
							num_collisions += 1
						else:
							print("bouncer!")
		elif self.position.y < -0.5 and len(collisions) == 1 and collisions[0].get_parent().name == hit_cup.name:
			num_collisions += 1
			if num_collisions >= 10:
				made_in = hit_cup.duplicate()
				print("made it in! " + str(made_in.name))
				await game.my_cups.remove_cup(int(made_in.name.replace("cup", "")))
				remove()
				
func throw(x_force: float, y_force: float):
	apply_impulse(Vector3(-x_force, -1.30, y_force))
	thrown = true
	await get_tree().create_timer(3).timeout
	remove()
	
func remove():
	if is_mine:
		if made_in != null:
			var cup_num = int(made_in.name.replace("cup", ""))
			print("MADE IN CUP NUM: " + str(cup_num))
			game.throws.append({"poses": replay_poses, "cup": cup_num-1})
		else:
			game.throws.append({"poses": replay_poses, "cup": -1})
		game.throw_finished()
	queue_free()
