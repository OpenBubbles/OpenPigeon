# res://effects/avatar_win_anim.gd
extends Control

@onready var fx: ColorRect = $Fx
var mat: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if fx:
		fx.set_anchors_preset(Control.PRESET_FULL_RECT)
		mat = fx.material as ShaderMaterial

func play(speed_val: float = 0.15, fade_in: float = 0.25) -> void:
	if not mat: return
	mat.set_shader_parameter("speed", speed_val)
	visible = true
	modulate.a = 0.0
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, fade_in)

func stop(fade_out: float = 0.25, queue: bool = true) -> void:
	if fade_out <= 0.0:
		visible = false
		if queue: queue_free()
		return
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, fade_out)
	t.tween_callback(func():
		visible = false
		if queue: queue_free()
	)

func set_color(col: Color) -> void:
	if not mat: return
	mat.set_shader_parameter("ray_color", col)

func set_rays(count: int) -> void:
	if not mat: return
	mat.set_shader_parameter("rays", float(count))

func set_inner_radius(v: float) -> void:
	if not mat: return
	mat.set_shader_parameter("inner", clampf(v, 0.0, 0.9))

func set_brightness(v: float) -> void:
	if not mat: return
	mat.set_shader_parameter("brightness", maxf(0.0, v))
