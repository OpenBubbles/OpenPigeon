extends Node3D
class_name PaintballProjectile

signal reached_plane(world_pos: Vector3)

@export var speed: float = 12.0
@export var hit_plane_z: float = 0.0
@export var use_plane_z: bool = true

@onready var ball_mesh: MeshInstance3D = $MeshInstance3D

var target: Vector3 = Vector3.ZERO

var _dir: Vector3 = Vector3.FORWARD
var _prev_z: float = 0.0
var _active: bool = false

func _ready() -> void:
	_prev_z = global_position.z
	_active = false

func launch(from_world: Vector3, to_world: Vector3) -> void:
	global_position = from_world
	target = to_world

	var v := target - global_position
	if v.length_squared() < 0.000001:
		_dir = -global_transform.basis.z.normalized()
	else:
		_dir = v.normalized()

	_prev_z = global_position.z
	_active = true

func _process(delta: float) -> void:
	if not _active:
		return

	global_position += _dir * speed * delta

	if use_plane_z:
		var z := global_position.z

		var crossed := false
		if _prev_z <= hit_plane_z and z >= hit_plane_z:
			crossed = true
		elif _prev_z >= hit_plane_z and z <= hit_plane_z:
			crossed = true

		_prev_z = z

		if crossed:
			_active = false
			emit_signal("reached_plane", global_position)
	else:
		var to_t := target - global_position
		if to_t.dot(_dir) <= 0.0:
			_active = false
			emit_signal("reached_plane", global_position)

func set_ball_color(color: Color) -> void:
	if not is_instance_valid(ball_mesh):
		return

	var mat := ball_mesh.get_surface_override_material(0)
	if mat == null:
		mat = ball_mesh.get_active_material(0)
	if mat == null:
		return

	mat = mat.duplicate(true)
	ball_mesh.set_surface_override_material(0, mat)

	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_color = color
