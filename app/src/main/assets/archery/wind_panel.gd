extends Panel
class_name WindPanel

@export var cam3d: Camera3D
@export var target: Target
@export var wind_label: RichTextLabel
@export var wind_arrow: Sprite2D

func _ready() -> void:
	self.pivot_offset = self.size / 2.0

func _process(delta: float) -> void:
	if cam3d.position.z > 1.616:
		self.visible = true
		var target_2d_pos: Vector2 = cam3d.unproject_position(target.global_position)
		if is_equal_approx(target.global_position.z, -14.4329):
			self.position = target_2d_pos + Vector2(-75, -130)
		else:
			self.position = target_2d_pos + Vector2(-75, -110)
	else:
		self.visible = false
		
func set_wind_power(power: float):
	wind_label.text = str("[center][b]WIND: ","%0.1f" % power,"[/b][/center]")

func set_wind_angle(angle: float):
	wind_arrow.rotation_degrees = angle
