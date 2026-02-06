extends Node3D

@onready var shadow: MeshInstance3D = $BlobShadow
@onready var ground: Node3D = %floor

@export var max_height: float = 3.0
@export var scale_near: float = 1
@export var scale_far: float = 0.35
@export var alpha_near: float = 0.55
@export var alpha_far: float = 0.12
@export var shadow_y_offset: float = 0.02

var mat: StandardMaterial3D

func _ready() -> void:
	var base_mat: Material = shadow.get_active_material(0)
	if base_mat == null:
		return
	mat = base_mat.duplicate(true) as StandardMaterial3D
	shadow.set_surface_override_material(0, mat)

func _process(_delta: float) -> void:
	if ground == null or mat == null:
		return

	var ground_y: float = ground.global_position.y

	var shadow_gp: Vector3 = shadow.global_position
	shadow_gp.y = ground_y + shadow_y_offset
	shadow.global_position = shadow_gp

	var h: float = global_position.y - ground_y
	if h < 0.0:
		h = 0.0

	var t: float = clamp(h / max_height, 0.0, 1.0)

	var s: float = lerp(scale_near, scale_far, t)
	shadow.scale = Vector3(s, 1.0, s)

	var a: float = lerp(alpha_near, alpha_far, t)
	var col: Color = mat.albedo_color
	col.a = a
	mat.albedo_color = col
