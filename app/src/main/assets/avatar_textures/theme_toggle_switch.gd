# ThemeToggleSwitch.gd
extends Control

signal toggled(is_dark_mode: bool)

@onready var background: ColorRect = $Background
@onready var sun_icon: TextureRect = $SunIcon
@onready var moon_icon: TextureRect = $MoonIcon
@onready var knob: ColorRect = $Knob

var is_dark := false

func _ready() -> void:
	sun_icon.texture = load("res://avatar_textures/sun.svg")
	moon_icon.texture = load("res://avatar_textures/moon.svg")

	_update_layout()
	resized.connect(_update_layout)

	gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			set_state(!is_dark, true)
			toggled.emit(is_dark)
	)

func set_state(dark_mode: bool, animate: bool) -> void:
	is_dark = dark_mode
	
	var sun_alpha = 1.0 if not is_dark else 0.0
	var moon_alpha = 1.0 if is_dark else 0.0
	var knob_pos_x = size.x - knob.size.x - 5 if is_dark else 5
	
	if animate:
		var tween = create_tween().set_parallel()
		tween.tween_property(knob, "position:x", knob_pos_x, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(sun_icon, "modulate:a", sun_alpha, 0.2)
		tween.tween_property(moon_icon, "modulate:a", moon_alpha, 0.2)
	else:
		knob.position.x = knob_pos_x
		sun_icon.modulate.a = sun_alpha
		moon_icon.modulate.a = moon_alpha

func _update_layout() -> void:
	background.size = size
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color.BLACK.lightened(0.15)
	stylebox.corner_radius_top_left = size.y / 2
	stylebox.corner_radius_top_right = size.y / 2
	stylebox.corner_radius_bottom_left = size.y / 2
	stylebox.corner_radius_bottom_right = size.y / 2
	background.add_theme_stylebox_override("panel", stylebox)

	knob.size = Vector2(size.y - 10, size.y - 10)
	knob.position = Vector2(5, 5)
	var knob_stylebox = stylebox.duplicate()
	knob_stylebox.bg_color = Color.WHITE.darkened(0.1)
	knob.add_theme_stylebox_override("panel", knob_stylebox)

	var icon_size = size.y * 0.6
	sun_icon.size = Vector2(icon_size, icon_size)
	moon_icon.size = Vector2(icon_size, icon_size)
	sun_icon.position = Vector2(size.x - icon_size - 10, (size.y - icon_size) / 2)
	moon_icon.position = Vector2(10, (size.y - icon_size) / 2)
