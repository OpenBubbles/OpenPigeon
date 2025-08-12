extends PanelContainer
class_name SettingsPopup

signal closed
signal settings_theme_selected(new_theme_name: String)
signal dark_mode_changed(is_dark: bool)

var dark_mode_enabled: bool = false              # canonical state you can read
var dark_mode_auto_apply_theme: bool = true      # set false to NOT sync theme automatically
var dark_mode_button: Button = null

const AvatarThumbnailScene = preload("res://avatar_textures/AvatarThumbnail.tscn")
const MOON_TEX: Texture2D = preload("res://avatar_textures/moon.svg")
const SUN_TEX: Texture2D  = preload("res://avatar_textures/sun.svg")


@onready var settings_label = %SettingsLabel as Label
@onready var theme_option_button = %ThemeOptionButton as OptionButton
@onready var main_preview_container = %MainPreviewContainer as CenterContainer
@onready var avatar_tab_container = %AvatarTabContainer as TabBar
@onready var properties_box = %PropertiesBox as VBoxContainer
@onready var custom_settings_container = %CustomSettingsContainer as VBoxContainer
@onready var global_settings_container = %GlobalSettingsContainer as VBoxContainer

var dim_rect: ColorRect
var main_avatar_preview: Node
var current_brightness_slider: HSlider = null
const GRABBER_IMAGE_PATH = "res://hollow_grabber.png"

func _ready():
	print("SettingsPopup: _ready() called.")
	self.custom_minimum_size.x = 400
	_setup_theme_button()
	_add_dark_mode_toggle()
	_setup_avatar_customizer()
	
	var saved_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	set_dark_mode(saved_dark, dark_mode_auto_apply_theme, true)

func close_popup():
	SettingsManager.avatar_changed.emit()
	
	print("SettingsPopup: Closing popup.")
	var tween = create_tween()
	tween.tween_property(self, "position", Vector2(position.x, get_viewport_rect().size.y), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		emit_signal("closed")
		queue_free()
		if is_instance_valid(dim_rect):
			dim_rect.queue_free()
	)

func _setup_theme_button():
	if theme_option_button:
		theme_option_button.clear()
		theme_option_button.item_selected.connect(_on_theme_option_button_item_selected)
		theme_option_button.add_item("Default", 0)
		theme_option_button.add_item("Default (Dark)", 1)
		theme_option_button.add_item("Penguin", 2)
		theme_option_button.add_item("Penguin (Dark)", 3)
		var saved_theme = SettingsManager.get_setting("global", "theme", "Default")
		for i in range(theme_option_button.item_count):
			if theme_option_button.get_item_text(i) == saved_theme:
				theme_option_button.select(i)
				break
	else:
		printerr("SettingsPopup: ERROR! ThemeOptionButton not found.")

func _on_theme_option_button_item_selected(index: int):
	var selected_theme_name = theme_option_button.get_item_text(index)
	settings_theme_selected.emit(selected_theme_name)
	SettingsManager.set_setting("global", "theme", selected_theme_name)

func _setup_avatar_customizer():
	main_avatar_preview = AvatarThumbnailScene.instantiate()
	main_avatar_preview.is_display_only = true
	main_avatar_preview.custom_minimum_size = Vector2(96, 64)
	main_preview_container.add_child(main_avatar_preview)

	avatar_tab_container.tab_changed.connect(_on_avatar_tab_changed)
	avatar_tab_container.add_tab("Background")
	avatar_tab_container.add_tab("Body")
	avatar_tab_container.add_tab("Hair")
	avatar_tab_container.add_tab("Face")
	avatar_tab_container.add_tab("Clothing")
	avatar_tab_container.add_tab("Accessories")
	avatar_tab_container.current_tab = 0
	_on_avatar_tab_changed(0)

func _on_avatar_tab_changed(tab_index: int):
	if not is_instance_valid(properties_box):
		printerr("SettingsPopup: ERROR! properties_box is not valid.")
		return
	for child in properties_box.get_children():
		child.queue_free()
	current_brightness_slider = null
	var tab_name = avatar_tab_container.get_tab_title(tab_index)
	match tab_name:
		"Background": _populate_background_properties()
		"Body": _populate_body_properties()
		"Hair": _populate_hair_properties()
		"Face": _populate_face_properties()
		"Clothing": _populate_clothing_properties()
		"Accessories": _populate_accessories_properties()

func _on_avatar_preview_setting_changed(value, category: String, key: String):
	SettingsManager.set_setting("avatar_" + category, key, value)
	main_avatar_preview.update_display_from_settings()

func _on_avatar_setting_changed(category: String, key: String, value):
	SettingsManager.set_setting("avatar_" + category, key, value)

	var saved_value = SettingsManager.get_setting("avatar_" + category, key)
	print("--- SETTING CHANGED ---")
	print("Saved '", key, "' for '", category, "' with new value: '", saved_value, "'")
	print("-----------------------")

	if is_instance_valid(main_avatar_preview):
		main_avatar_preview.update_display_from_settings()
	_on_avatar_tab_changed(avatar_tab_container.current_tab)

func _populate_background_properties():
	var preset_colors = [ Color("#7c7c7c"), Color("#e7639f"), Color("#9e45c0"), Color("#5798f6"), Color("#32d5c8"), Color("#7cb33e"), Color("#b1da1a"), Color("#f6d61a"), Color("#ee7c09"), Color("#f11f06"), Color("#d3292c") ]
	var default_color = SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89"))
	var initial_brightness = SettingsManager.get_setting("avatar_background", "brightness", 0.0)
	_create_color_and_brightness_control("background", "color", "brightness", preset_colors, default_color, initial_brightness)
	var style_options = ["Plain", "Pattern 1", "Pattern 2", "Pattern 3", "Pattern 4", "Pattern 5", "Pattern 6", "Pattern 7", "Pattern 8", "Pattern 9"]
	_create_image_presets_scrollbar("background", "style", style_options)

func _populate_body_properties():
	var body_styles = ["Default", "body1", "body2", "body3", "body4", "body5", "body6"]
	_create_image_presets_scrollbar("body", "head_style", body_styles)
	var skin_tones = [ Color("#ffbd9a"), Color("#ffb070"), Color("#804734"), Color("#5f442f"), Color("#cccccc"), Color("#da73a2"), Color("#6394f1"), Color("#82b941"), Color("#f8cf55"), Color("#f6820c"), Color("#c34126") ]
	var default_tone = SettingsManager.get_setting("avatar_body", "color", Color("#e0ac69"))
	var initial_brightness = SettingsManager.get_setting("avatar_body", "brightness", 0.0)
	_create_color_and_brightness_control("body", "color", "brightness", skin_tones, default_tone, initial_brightness)

func _populate_hair_properties():
	var hair_styles = ["Spiky", "Long", "Bun", "Bald"]
	_create_image_presets_scrollbar("hair", "style", hair_styles)
	var hair_colors = [ Color("#f8cf55"), Color("#e1872f"), Color("#d24325"), Color("#6d411d"), Color("#572c1f"), Color("#000000"), Color("#e1e1e1"), Color("#ee67a4"), Color("#a348c7"), Color("#699bff"), Color("#82b941") ]
	var default_color = SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b"))
	var initial_brightness = SettingsManager.get_setting("avatar_hair", "brightness", 0.0)
	_create_color_and_brightness_control("hair", "color", "brightness", hair_colors, default_color, initial_brightness)

func _populate_face_properties():
	var eye_styles = ["Open", "Closed", "Winking"]
	_create_image_presets_scrollbar("face", "eyes", eye_styles)
	var mouth_styles = ["Plain", "Smile", "Frown"]
	_create_image_presets_scrollbar("face", "mouth", mouth_styles)

func _populate_clothing_properties():
	var clothing_styles = ["T-Shirt", "Sweater", "Tank Top"]
	_create_image_presets_scrollbar("clothing", "style", clothing_styles)
	var clothing_colors = [ Color("#7c7c7c"), Color("#e7639f"), Color("#9e45c0"), Color("#5798f6"), Color("#32d5c8"), Color("#7cb33e"), Color("#b1da1a"), Color("#f6d61a"), Color("#ee7c09"), Color("#f11f06"), Color("#d3292c") ]
	var default_color = SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c"))
	var initial_brightness = SettingsManager.get_setting("avatar_clothing", "brightness", 0.0)
	_create_color_and_brightness_control("clothing", "color", "brightness", clothing_colors, default_color, initial_brightness)

func _populate_accessories_properties():
	var head_accessories_styles = ["None", "Hat1", "Headband"]
	_create_image_presets_scrollbar("accessories", "head_style", head_accessories_styles)
	var face_accessories_styles = ["None", "Glasses", "Mask"]
	_create_image_presets_scrollbar("accessories", "face_style", face_accessories_styles)

func _create_color_and_brightness_control(category: String, color_key: String, brightness_key: String, colors: PackedColorArray, default_color: Color, initial_brightness: float):
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size.y = 80
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 5)
	var hbox_colors = HBoxContainer.new()
	hbox_colors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_colors.add_theme_constant_override("separation", 5)
	var diameter = 24
	var radius = diameter * 0.5
	var spacer_left = Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_colors.add_child(spacer_left)
	for color_value in colors:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(diameter, diameter)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = color_value
		style_normal.border_width_left = 2; style_normal.border_width_top = 2; style_normal.border_width_right = 2; style_normal.border_width_bottom = 2
		style_normal.border_color = color_value.darkened(0.2)
		style_normal.corner_radius_top_left = radius; style_normal.corner_radius_top_right = radius; style_normal.corner_radius_bottom_left = radius; style_normal.corner_radius_bottom_right = radius
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("pressed", style_normal.duplicate())
		var style_focus = style_normal.duplicate()
		style_focus.border_color = Color(0.2, 0.8, 0.2, 0.9)
		btn.add_theme_stylebox_override("hover", style_focus)
		btn.add_theme_stylebox_override("focus", style_focus)
		btn.set_meta("preset_color", color_value)
		btn.pressed.connect(func():
			_on_avatar_setting_changed(category, color_key, btn.get_meta("preset_color"))
			_on_avatar_setting_changed(category, brightness_key, 0.0)
		)
		hbox_colors.add_child(btn)
		var spacer_mid = Control.new()
		spacer_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox_colors.add_child(spacer_mid)
	vbox.add_child(hbox_colors)
	var slider = HSlider.new()
	slider.set_meta("category", category)
	slider.set_meta("key", brightness_key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = -1.0; slider.max_value = 1.0; slider.step = 0.01
	slider.value = initial_brightness
	slider.value_changed.connect(_on_avatar_preview_setting_changed.bind(category, brightness_key))
	slider.drag_ended.connect(func(_value_doesnt_matter): _on_avatar_tab_changed(avatar_tab_container.current_tab))
	vbox.add_child(slider)
	current_brightness_slider = slider
	_update_brightness_slider_gradient(default_color)
	_add_property_to_box(vbox)
	_update_selected_color_dot_border(hbox_colors, default_color)

func _add_property_to_box(control_to_wrap: Control):
	var panel_container = PanelContainer.new()
	var stylebox_flat = StyleBoxFlat.new()
	stylebox_flat.bg_color = Color(1, 1, 1, 0.1)
	stylebox_flat.border_width_left = 1; stylebox_flat.border_width_top = 1; stylebox_flat.border_width_right = 1; stylebox_flat.border_width_bottom = 1
	stylebox_flat.border_color = Color(1, 1, 1, 0.2)
	stylebox_flat.corner_radius_top_left = 5; stylebox_flat.corner_radius_top_right = 5; stylebox_flat.corner_radius_bottom_left = 5; stylebox_flat.corner_radius_bottom_right = 5
	stylebox_flat.set_content_margin_all(5)
	panel_container.add_theme_stylebox_override("panel", stylebox_flat)
	panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	properties_box.add_child(panel_container)
	panel_container.add_child(control_to_wrap)

func _update_selected_color_dot_border(parent_hbox: HBoxContainer, selected_color: Color):
	for child in parent_hbox.get_children():
		if child is Button and child.has_meta("preset_color"):
			var stylebox_normal = child.get_theme_stylebox("normal", "Button") as StyleBoxFlat
			if stylebox_normal:
				var new_stylebox = stylebox_normal.duplicate() as StyleBoxFlat
				if child.get_meta("preset_color") == selected_color:
					new_stylebox.border_color = Color(0.2, 0.8, 0.2, 0.9)
					new_stylebox.border_width_left = 3; new_stylebox.border_width_top = 3; new_stylebox.border_width_right = 3; new_stylebox.border_width_bottom = 3
				else:
					new_stylebox.border_color = child.get_meta("preset_color").darkened(0.2)
					new_stylebox.border_width_left = 2; new_stylebox.border_width_top = 2; new_stylebox.border_width_right = 2; new_stylebox.border_width_bottom = 2
				child.add_theme_stylebox_override("normal", new_stylebox)

func _update_brightness_slider_gradient(color: Color):
	if not is_instance_valid(current_brightness_slider): return
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color.from_hsv(color.h, color.s, 0.3))
	gradient.add_point(0.5, color)
	gradient.add_point(1.0, Color.from_hsv(color.h, 0.0, 1.0))
	var grad_tex = GradientTexture2D.new()
	grad_tex.gradient = gradient
	var main_bar_style = StyleBoxTexture.new()
	main_bar_style.texture = grad_tex
	main_bar_style.texture_margin_top = 8; main_bar_style.texture_margin_bottom = 8; main_bar_style.texture_margin_left = 6; main_bar_style.texture_margin_right = 6
	current_brightness_slider.add_theme_stylebox_override("slider", main_bar_style)
	var clear_style = StyleBoxFlat.new()
	clear_style.bg_color = Color.TRANSPARENT
	current_brightness_slider.add_theme_stylebox_override("grabber_area", clear_style)
	current_brightness_slider.add_theme_stylebox_override("grabber_area_highlight", clear_style)
	var grabber_icon = load(GRABBER_IMAGE_PATH)
	current_brightness_slider.add_theme_icon_override("grabber", grabber_icon)
	current_brightness_slider.add_theme_icon_override("grabber_highlight", grabber_icon)
	current_brightness_slider.add_theme_icon_override("grabber_pressed", grabber_icon)

func _get_current_avatar_settings() -> Dictionary:
	return {
		"background": { "color": SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89")), "brightness": SettingsManager.get_setting("avatar_background", "brightness", 0.0), "style": SettingsManager.get_setting("avatar_background", "style", "Plain"), },
		"body": { "color": SettingsManager.get_setting("avatar_body", "color", Color("#e0ac69")), "brightness": SettingsManager.get_setting("avatar_body", "brightness", 0.0), "head_style": SettingsManager.get_setting("avatar_body", "head_style", "Default"), },
		"hair": { "color": SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b")), "brightness": SettingsManager.get_setting("avatar_hair", "brightness", 0.0), "style": SettingsManager.get_setting("avatar_hair", "style", "Spiky"), },
		"face": { "eyes": SettingsManager.get_setting("avatar_face", "eyes", "Open"), "mouth": SettingsManager.get_setting("avatar_face", "mouth", "Plain"), },
		"clothing": { "color": SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c")), "brightness": SettingsManager.get_setting("avatar_clothing", "brightness", 0.0), "style": SettingsManager.get_setting("avatar_clothing", "style", "T-Shirt"), },
		"accessories": { "color": SettingsManager.get_setting("avatar_accessories", "color", Color("#ffffff")), "brightness": SettingsManager.get_setting("avatar_accessories", "brightness", 0.0), "head_style": SettingsManager.get_setting("avatar_accessories", "head_style", "None"), "face_style": SettingsManager.get_setting("avatar_accessories", "face_style", "None"), }
	}

func _create_image_presets_scrollbar(category: String, key: String, style_options: Array):
	var scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.custom_minimum_size = Vector2(0, 80)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	scroll_container.add_child(hbox)
	var current_settings = _get_current_avatar_settings()
	var current_style_value = SettingsManager.get_setting("avatar_" + category, key, style_options[0])
	for style_name in style_options:
		var thumbnail = AvatarThumbnailScene.instantiate()
		thumbnail.custom_minimum_size = Vector2(96, 64)
		hbox.add_child(thumbnail)
		thumbnail.call_deferred("update_preview", current_settings, category, key, style_name)
		if style_name == current_style_value:
			thumbnail.set_selected(true)
		thumbnail.pressed.connect(_on_avatar_setting_changed.bind(category, key, style_name))
	_add_property_to_box(scroll_container)

func _exit_tree():
	print("SettingsPopup: _exit_tree() called.")
	if is_instance_valid(dim_rect):
		dim_rect.queue_free()

func setup_popup(dimmer: ColorRect):
	dim_rect = dimmer
	if is_instance_valid(dim_rect):
		dim_rect.gui_input.connect(_on_dim_rect_gui_input)
		
func set_dark_mode(enabled: bool, apply_theme: bool = true, instant: bool = false) -> void:
	if dark_mode_enabled == enabled:
		_apply_dark_mode_visuals(enabled, instant)
		return
	dark_mode_enabled = enabled
	SettingsManager.set_setting("global", "dark_mode", enabled)
	_apply_dark_mode_visuals(enabled, instant)
	if apply_theme:
		_sync_theme_dropdown_from_dark(enabled)
	emit_signal("dark_mode_changed", enabled)

func get_dark_mode() -> bool:
	return dark_mode_enabled

func get_dark_palette() -> Dictionary:
	if dark_mode_enabled:
		return {
			"bg": Color(0.12,0.12,0.12),
			"fg": Color(0.92,0.92,0.92),
			"muted": Color(0.65,0.65,0.65),
			"accent": Color(0.85,0.85,0.85)
		}
	else:
		return {
			"bg": Color(0.95,0.95,0.95),
			"fg": Color(0.10,0.10,0.10),
			"muted": Color(0.40,0.40,0.40),
			"accent": Color(0.40,0.40,0.40)
		}

func _apply_dark_mode_visuals(enabled: bool, instant: bool) -> void:
	if dark_mode_button == null: return
	dark_mode_button.set_pressed_no_signal(enabled)
	_update_switch_visual(dark_mode_button, enabled, instant)
		
func _add_dark_mode_toggle():
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(1, 1, 1, 0.1)
	card_style.border_width_left = 1; card_style.border_width_top = 1; card_style.border_width_right = 1; card_style.border_width_bottom = 1
	card_style.border_color = Color(1, 1, 1, 0.2)
	card_style.corner_radius_top_left = 5; card_style.corner_radius_top_right = 5
	card_style.corner_radius_bottom_left = 5; card_style.corner_radius_bottom_right = 5
	card_style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", card_style)

	var row := CenterContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 40)

	dark_mode_button = _make_switch_button()
	row.add_child(dark_mode_button)
	card.add_child(row)

	if is_instance_valid(global_settings_container):
		global_settings_container.add_child(card)
	else:
		printerr("SettingsPopup: GlobalSettingsContainer not found; cannot add dark mode toggle.")

	dark_mode_button.toggled.connect(func(pressed: bool):
		set_dark_mode(pressed, dark_mode_auto_apply_theme, false)
	)
	
func _make_switch_button() -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(72, 36)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.clip_contents = false

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.75, 0.75, 0.78, 1.0)
	track.corner_radius_top_left = 18
	track.corner_radius_top_right = 18
	track.corner_radius_bottom_left = 18
	track.corner_radius_bottom_right = 18
	track.content_margin_left = 2; track.content_margin_right = 2
	track.content_margin_top = 2; track.content_margin_bottom = 2
	btn.add_theme_stylebox_override("normal", track)
	btn.add_theme_stylebox_override("hover", track)
	btn.add_theme_stylebox_override("pressed", track)
	btn.add_theme_stylebox_override("focus", track)
	btn.add_theme_stylebox_override("disabled", track)

	var knob_wrap := PanelContainer.new()
	knob_wrap.name = "KnobWrap"
	knob_wrap.size = Vector2(32, 32)
	knob_wrap.position = Vector2(2, 2)
	knob_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob_wrap.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	btn.add_child(knob_wrap)

	var knob := PanelContainer.new()
	knob.name = "Knob"
	knob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	knob.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var kbox := StyleBoxFlat.new()
	kbox.bg_color = Color(0, 0, 0, 1)
	kbox.corner_radius_top_left = 16
	kbox.corner_radius_top_right = 16
	kbox.corner_radius_bottom_left = 16
	kbox.corner_radius_bottom_right = 16
	kbox.anti_aliasing = true
	knob.add_theme_stylebox_override("panel", kbox)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob_wrap.add_child(knob)

	var moon := TextureRect.new()
	moon.name = "MoonIn"
	moon.texture = MOON_TEX
	moon.ignore_texture_size = true
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	moon.z_index = 2
	btn.add_child(moon)

	var sun := TextureRect.new()
	sun.name = "SunIn"
	sun.texture = SUN_TEX
	sun.ignore_texture_size = true
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun.z_index = 2
	btn.add_child(sun)

	_layout_switch_children(btn)
	btn.resized.connect(_layout_switch_children.bind(btn))

	return btn
	
func _layout_switch_children(btn: Button) -> void:
	var icon_size := 20.0
	var pad := 8.0

	var moon := btn.get_node_or_null("MoonIn") as TextureRect
	var sun := btn.get_node_or_null("SunIn") as TextureRect
	var knob_wrap := btn.get_node_or_null("KnobWrap") as PanelContainer

	if is_instance_valid(moon):
		moon.custom_minimum_size = Vector2(icon_size, icon_size)
		moon.size = moon.custom_minimum_size
		moon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		moon.position = Vector2(btn.size.x - icon_size - pad, (btn.size.y - icon_size) / 2.0)

	if is_instance_valid(sun):
		sun.custom_minimum_size = Vector2(icon_size, icon_size)
		sun.size = sun.custom_minimum_size
		sun.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sun.position = Vector2(pad, (btn.size.y - icon_size) / 2.0)

	if is_instance_valid(knob_wrap):
		knob_wrap.position.y = (btn.size.y - knob_wrap.size.y) / 2.0

func _update_switch_visual(btn: Button, on: bool, instant: bool):
	var base := btn.get_theme_stylebox("normal", "Button") as StyleBoxFlat
	if base:
		var tdup := base.duplicate() as StyleBoxFlat
		tdup.bg_color = Color(0.4, 0.4, 0.4, 1.0) if on else Color(0.85, 0.85, 0.85, 1.0)
		btn.add_theme_stylebox_override("normal", tdup)
		btn.add_theme_stylebox_override("hover", tdup)
		btn.add_theme_stylebox_override("pressed", tdup)

	var knob_wrap := btn.get_node_or_null("KnobWrap") as PanelContainer
	var knob := knob_wrap.get_node_or_null("Knob") if is_instance_valid(knob_wrap) else null
	var moon := btn.get_node_or_null("MoonIn") as TextureRect
	var sun := btn.get_node_or_null("SunIn") as TextureRect
	if not is_instance_valid(knob_wrap) or not is_instance_valid(knob):
		return

	if is_instance_valid(moon): moon.move_to_front()
	if is_instance_valid(sun): sun.move_to_front()

	var left_x := 2.0
	var right_x := btn.size.x - knob_wrap.size.x - 2.0
	var target_x := right_x if on else left_x

	var knob_color := Color(0, 0, 0) if on else Color(1, 1, 1)
	var icon_color := Color(1, 1, 1) if on else Color(0, 0, 0)

	var kbox := knob.get_theme_stylebox("panel") as StyleBoxFlat
	if kbox:
		kbox = kbox.duplicate() as StyleBoxFlat
		kbox.bg_color = knob_color
		knob.add_theme_stylebox_override("panel", kbox)

	if instant:
		knob_wrap.position.x = target_x
		if is_instance_valid(moon): moon.modulate = icon_color
		if is_instance_valid(sun):  sun.modulate  = icon_color
	else:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(knob_wrap, "position:x", target_x, 0.2)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if is_instance_valid(moon):
			tw.tween_property(moon, "modulate", icon_color, 0.15)
		if is_instance_valid(sun):
			tw.tween_property(sun, "modulate", icon_color, 0.15)

func _sync_theme_dropdown_from_dark(dark_on: bool):
	var desired := "Default (Dark)" if dark_on else "Default"

	if is_instance_valid(theme_option_button):
		for i in range(theme_option_button.item_count):
			if theme_option_button.get_item_text(i) == desired:
				theme_option_button.select(i)
				break

	SettingsManager.set_setting("global", "theme", desired)
	settings_theme_selected.emit(desired)


func _on_dim_rect_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close_popup()

func add_custom_setting(control_node: Control):
	if custom_settings_container:
		custom_settings_container.add_child(control_node)
	else:
		printerr("SettingsPopup: ERROR! custom_settings_container is null.")
