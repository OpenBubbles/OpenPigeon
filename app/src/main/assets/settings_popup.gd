extends PanelContainer
class_name SettingsPopup

signal closed
signal settings_theme_selected(new_theme_name: String)

# --- Node References ---
@onready var settings_label = %SettingsLabel as Label
@onready var theme_option_button = %ThemeOptionButton as OptionButton
@onready var avatar_preview = %AvatarPreview as Control
@onready var avatar_tab_container = %AvatarTabContainer as TabBar
@onready var properties_box = %PropertiesBox as VBoxContainer
@onready var custom_settings_container = %CustomSettingsContainer as VBoxContainer
@onready var avatar_background_image = %AvatarBackground as Sprite2D
@onready var avatar_base_body = %AvatarBaseBody as Sprite2D
@onready var avatar_hair = %AvatarHair as Sprite2D
@onready var avatar_eyes = %AvatarEyes as Sprite2D
@onready var avatar_mouth = %AvatarMouth as Sprite2D
@onready var avatar_clothing = %AvatarClothing as Sprite2D
@onready var avatar_head_accessories = %AvatarHeadAccessories as Sprite2D
@onready var avatar_face_accessories = %AvatarFaceAccessories as Sprite2D

var dim_rect: ColorRect

# --- Constants ---
const GRABBER_IMAGE_PATH = "res://hollow_grabber.png"
# !!! IMPORTANT: Update this path to where you saved your AvatarThumbnail.tscn file
const AvatarThumbnailScene = preload("res://avatar_textures/AvatarThumbnail.tscn")

# --- Texture Maps and Region Data ---
const AVATAR_BG_MAP_PATH = "res://avatar_textures/backgrounds/background_sheet.png"
const AVATAR_BODY_MAP_PATH = "res://avatar_textures/body/avatar_bodies.png"
const AVATAR_HAIR_MAP_PATH = "res://avatar_textures/hair/avatar_hair.png"
const AVATAR_EYES_MAP_PATH = "res://avatar_textures/face/avatar_eyes.png"
const AVATAR_MOUTH_MAP_PATH = "res://avatar_textures/face/avatar_mouth.png"
const AVATAR_CLOTHING_MAP_PATH = "res://avatar_textures/clothing/avatar_clothing.png"
const AVATAR_ACCESSORIES_MAP_PATH = "res://avatar_textures/accessories/avatar_accessories.png"

var avatar_background_regions = { "Pattern 1":  Rect2(0,   0,   128, 128), "Pattern 2":  Rect2(128, 0,   128, 128), "Pattern 3":  Rect2(256, 0,   128, 128), "Pattern 4":  Rect2(384, 0,   128, 128), "Pattern 5":  Rect2(0,   128, 128, 128), "Pattern 6":  Rect2(128, 128, 128, 128), "Pattern 7":  Rect2(256, 128, 128, 128), "Pattern 8":  Rect2(384, 128, 128, 128), "Pattern 9":  Rect2(0,   256, 128, 128) }
var avatar_body_regions = { "Default": Rect2(0, 0, 64, 64), "Smiling": Rect2(64, 0, 64, 64), "Winking": Rect2(128, 0, 64, 64), "Surprised": Rect2(192, 0, 64, 64), "Frowning": Rect2(256, 0, 64, 64), "Tongue Out": Rect2(320, 0, 64, 64), "Cute": Rect2(384, 0, 64, 64) }
var avatar_hair_regions = { "Spiky": Rect2(0, 0, 64, 64), "Long": Rect2(64, 0, 64, 64), "Bun": Rect2(128, 0, 64, 64), "Bald": Rect2(192, 0, 64, 64) }
var avatar_eyes_regions = { "Open": Rect2(0, 0, 64, 64), "Closed": Rect2(64, 0, 64, 64), "Winking": Rect2(128, 0, 64, 64) }
var avatar_mouth_regions = { "Plain": Rect2(0, 0, 64, 64), "Smile": Rect2(64, 0, 64, 64), "Frown": Rect2(128, 0, 64, 64) }
var avatar_clothing_regions = { "T-Shirt": Rect2(0, 0, 64, 64), "Sweater": Rect2(64, 0, 64, 64), "Tank Top": Rect2(128, 0, 64, 64) }
var avatar_head_accessories_regions = { "None": Rect2(0, 0, 1, 1), "Hat1": Rect2(0, 0, 64, 64), "Headband": Rect2(64, 0, 64, 64) }
var avatar_face_accessories_regions = { "None": Rect2(0, 0, 1, 1), "Glasses": Rect2(128, 0, 64, 64), "Mask": Rect2(192, 0, 64, 64) }

var current_brightness_slider: HSlider = null

# --- Main Functions ---

func _ready():
	print("SettingsPopup: _ready() called.")
	self.custom_minimum_size.x = 400
	_setup_theme_button()
	_setup_avatar_customizer()

func close_popup():
	print("SettingsPopup: Closing popup.")
	var tween = create_tween()
	tween.tween_property(self, "position", Vector2(position.x, get_viewport_rect().size.y), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		emit_signal("closed")
		queue_free()
		if is_instance_valid(dim_rect):
			dim_rect.queue_free()
	)

# --- Theme Setup ---

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

# --- Avatar Customizer Logic ---

func _setup_avatar_customizer():
	if not is_instance_valid(avatar_tab_container):
		printerr("SettingsPopup: ERROR! AvatarTabContainer node not found.")
		return

	avatar_tab_container.tab_changed.connect(_on_avatar_tab_changed)
	avatar_tab_container.add_tab("Background")
	avatar_tab_container.add_tab("Body")
	avatar_tab_container.add_tab("Hair")
	avatar_tab_container.add_tab("Face")
	avatar_tab_container.add_tab("Clothing")
	avatar_tab_container.add_tab("Accessories")
	avatar_tab_container.current_tab = 0
	
	_load_avatar_textures()
	_update_avatar_preview()
	_on_avatar_tab_changed(0) # Manually trigger the first tab population

func _load_avatar_textures():
	avatar_base_body.texture = load(AVATAR_BODY_MAP_PATH)
	avatar_hair.texture = load(AVATAR_HAIR_MAP_PATH)
	avatar_eyes.texture = load(AVATAR_EYES_MAP_PATH)
	avatar_mouth.texture = load(AVATAR_MOUTH_MAP_PATH)
	avatar_clothing.texture = load(AVATAR_CLOTHING_MAP_PATH)
	avatar_head_accessories.texture = load(AVATAR_ACCESSORIES_MAP_PATH)
	avatar_face_accessories.texture = load(AVATAR_ACCESSORIES_MAP_PATH)

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

func _update_avatar_preview():
	var bg_color = SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89"))
	var bg_brightness = SettingsManager.get_setting("avatar_background", "brightness", 0.0)
	var final_bg = calculate_final_color_with_brightness(bg_color, bg_brightness)

	if is_instance_valid(avatar_preview):
		var bg_rect = avatar_preview.get_node("ColorRect") as ColorRect
		if is_instance_valid(bg_rect):
			bg_rect.color = final_bg
			
	var bg_style = SettingsManager.get_setting("avatar_background", "style", "Plain")
	if bg_style == "Plain" or not avatar_background_regions.has(bg_style):
		avatar_background_image.texture = null # Hide the pattern sprite
		avatar_background_image.region_enabled = false
	else:
		avatar_background_image.texture = load(AVATAR_BG_MAP_PATH)
		avatar_background_image.region_enabled = true
		avatar_background_image.region_rect = avatar_background_regions[bg_style]

	var tone_color = SettingsManager.get_setting("avatar_body", "color", Color("#e0ac69"))
	var tone_bright = SettingsManager.get_setting("avatar_body", "brightness", 0.0)
	avatar_base_body.self_modulate = calculate_final_color_with_brightness(tone_color, tone_bright)

	var body_style = SettingsManager.get_setting("avatar_body", "head_style", "Default")
	if avatar_body_regions.has(body_style):
		avatar_base_body.region_enabled = true
		avatar_base_body.region_rect = avatar_body_regions[body_style]

	var hair_style = SettingsManager.get_setting("avatar_hair", "style", "Spiky")
	var hair_color = SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b"))
	var hair_brightness = SettingsManager.get_setting("avatar_hair", "brightness", 0.0)
	avatar_hair.self_modulate = calculate_final_color_with_brightness(hair_color, hair_brightness)

	if avatar_hair_regions.has(hair_style):
		avatar_hair.region_enabled = true
		avatar_hair.region_rect = avatar_hair_regions[hair_style]

	var eyes_style = SettingsManager.get_setting("avatar_face", "eyes", "Open")
	if avatar_eyes_regions.has(eyes_style):
		avatar_eyes.region_enabled = true
		avatar_eyes.region_rect = avatar_eyes_regions[eyes_style]

	var mouth_style = SettingsManager.get_setting("avatar_face", "mouth", "Plain")
	if avatar_mouth_regions.has(mouth_style):
		avatar_mouth.region_enabled = true
		avatar_mouth.region_rect = avatar_mouth_regions[mouth_style]

	var clothing_style = SettingsManager.get_setting("avatar_clothing", "style", "T-Shirt")
	var clothing_color = SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c"))
	var clothing_brightness = SettingsManager.get_setting("avatar_clothing", "brightness", 0.0)
	avatar_clothing.self_modulate = calculate_final_color_with_brightness(clothing_color, clothing_brightness)

	if avatar_clothing_regions.has(clothing_style):
		avatar_clothing.region_enabled = true
		avatar_clothing.region_rect = avatar_clothing_regions[clothing_style]
	
	var head_accessory_style = SettingsManager.get_setting("avatar_accessories", "head_style", "None")
	var face_accessory_style = SettingsManager.get_setting("avatar_accessories", "face_style", "None")
	var accessories_color = SettingsManager.get_setting("avatar_accessories", "color", Color("#ffffff"))
	var accessories_brightness = SettingsManager.get_setting("avatar_accessories", "brightness", 0.0)
	var final_accessories_color = calculate_final_color_with_brightness(accessories_color, accessories_brightness)
	
	avatar_head_accessories.self_modulate = final_accessories_color
	if avatar_head_accessories_regions.has(head_accessory_style) and head_accessory_style != "None":
		avatar_head_accessories.region_enabled = true
		avatar_head_accessories.region_rect = avatar_head_accessories_regions[head_accessory_style]
		avatar_head_accessories.self_modulate.a = 1.0
	else:
		avatar_head_accessories.self_modulate.a = 0.0

	avatar_face_accessories.self_modulate = final_accessories_color
	if avatar_face_accessories_regions.has(face_accessory_style) and face_accessory_style != "None":
		avatar_face_accessories.region_enabled = true
		avatar_face_accessories.region_rect = avatar_face_accessories_regions[face_accessory_style]
		avatar_face_accessories.self_modulate.a = 1.0
	else:
		avatar_face_accessories.self_modulate.a = 0.0

	if is_instance_valid(current_brightness_slider):
		var slider_category: String = current_brightness_slider.get_meta("category", "background")
		if slider_category == "body": _update_brightness_slider_gradient(tone_color)
		elif slider_category == "hair": _update_brightness_slider_gradient(hair_color)
		elif slider_category == "clothing": _update_brightness_slider_gradient(clothing_color)
		elif slider_category == "accessories": _update_brightness_slider_gradient(accessories_color)
		else: _update_brightness_slider_gradient(bg_color)

	_center_avatar_sprites()
		
func calculate_final_color_with_brightness(base_color: Color, brightness_slider_val: float) -> Color:
	if brightness_slider_val < 0.0:
		var t = brightness_slider_val + 1.0
		return Color.from_hsv(base_color.h, base_color.s, t * base_color.v)
	elif brightness_slider_val > 0.0:
		var h_val = base_color.h
		var s_val = base_color.s * (1.0 - brightness_slider_val)
		var v_val = base_color.v + (1.0 - base_color.v) * brightness_slider_val
		return Color.from_hsv(h_val, s_val, v_val)
	else:
		return base_color
		
func _on_avatar_preview_setting_changed(value, category: String, key: String):
	# This lightweight function only updates the data and the main preview.
	# It allows for smooth UI interactions like dragging a slider.
	var section = "avatar_" + category
	SettingsManager.set_setting(section, key, value)
	_update_avatar_preview()

func _on_avatar_setting_changed(category: String, key: String, value, needs_ui_refresh: bool = false):
	var section = "avatar_" + category
	SettingsManager.set_setting(section, key, value)
	_update_avatar_preview()
	_on_avatar_tab_changed(avatar_tab_container.current_tab)
	
	if needs_ui_refresh:
		_on_avatar_tab_changed(avatar_tab_container.current_tab)

func _populate_background_properties():
	var preset_colors = [ Color("#7c7c7c"), Color("#e7639f"), Color("#9e45c0"), Color("#5798f6"), Color("#32d5c8"), Color("#7cb33e"), Color("#b1da1a"), Color("#f6d61a"), Color("#ee7c09"), Color("#f11f06"), Color("#d3292c") ]
	var default_color = SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89"))
	var initial_brightness = SettingsManager.get_setting("avatar_background", "brightness", 0.0)
	_create_color_and_brightness_control("Background Color", "background", "color", "brightness", preset_colors, default_color, initial_brightness)
	
	var style_options = ["Plain"] + avatar_background_regions.keys()
	_create_image_presets_scrollbar("background", "style", style_options)

func _populate_body_properties():
	var body_styles = avatar_body_regions.keys()
	_create_image_presets_scrollbar("body", "head_style", body_styles)

	var skin_tones = [ Color("#ffbd9a"), Color("#ffb070"), Color("#804734"), Color("#5f442f"), Color("#cccccc"), Color("#da73a2"), Color("#6394f1"), Color("#82b941"), Color("#f8cf55"), Color("#f6820c"), Color("#c34126") ]
	var default_tone = SettingsManager.get_setting("avatar_body", "color", Color("#e0ac69"))
	var initial_brightness = SettingsManager.get_setting("avatar_body", "brightness", 0.0)
	_create_color_and_brightness_control("Skin Tone", "body", "color", "brightness", skin_tones, default_tone, initial_brightness)

func _populate_hair_properties():
	var hair_styles = avatar_hair_regions.keys()
	_create_image_presets_scrollbar("hair", "style", hair_styles)

	var hair_colors = [ Color("#f8cf55"), Color("#e1872f"), Color("#d24325"), Color("#6d411d"), Color("#572c1f"), Color("#000000"), Color("#e1e1e1"), Color("#ee67a4"), Color("#a348c7"), Color("#699bff"), Color("#82b941") ]
	var default_color = SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b"))
	var initial_brightness = SettingsManager.get_setting("avatar_hair", "brightness", 0.0)
	_create_color_and_brightness_control("Hair Color", "hair", "color", "brightness", hair_colors, default_color, initial_brightness)

func _populate_face_properties():
	var eye_styles = avatar_eyes_regions.keys()
	_create_image_presets_scrollbar("face", "eyes", eye_styles)

	var mouth_styles = avatar_mouth_regions.keys()
	_create_image_presets_scrollbar("face", "mouth", mouth_styles)

func _populate_clothing_properties():
	var clothing_styles = avatar_clothing_regions.keys()
	_create_image_presets_scrollbar("clothing", "style", clothing_styles)
	var clothing_colors = [ Color("#7c7c7c"), Color("#e7639f"), Color("#9e45c0"), Color("#5798f6"), Color("#32d5c8"), Color("#7cb33e"), Color("#b1da1a"), Color("#f6d61a"), Color("#ee7c09"), Color("#f11f06"), Color("#d3292c") ]
	var default_color = SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c"))
	var initial_brightness = SettingsManager.get_setting("avatar_clothing", "brightness", 0.0)
	_create_color_and_brightness_control("Clothing Color", "clothing", "color", "brightness", clothing_colors, default_color, initial_brightness)

func _populate_accessories_properties():
	var head_accessories_styles = avatar_head_accessories_regions.keys()
	_create_image_presets_scrollbar("accessories", "head_style", head_accessories_styles)

	var face_accessories_styles = avatar_face_accessories_regions.keys()
	_create_image_presets_scrollbar("accessories", "face_style", face_accessories_styles)

# --- UI Control Creation Helpers ---

func _create_color_and_brightness_control(label_text: String, category: String, color_key: String, brightness_key: String, colors: PackedColorArray, default_color: Color, initial_brightness: float):
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size.y = 80
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 5)

	# The HBoxContainer for color dots does not need to be changed.
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
	
	slider.drag_ended.connect(func(_value_doesnt_matter):
		_on_avatar_tab_changed(avatar_tab_container.current_tab)
	)
	
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

func _center_avatar_sprites():
	var preview_size = avatar_preview.size
	var center_pos = preview_size / 2.0
	
	# --- Manually position and scale the background sprite ---
	# The base size of our background art region is 128x128
	var texture_size = 128.0 
	avatar_background_image.scale.x = preview_size.x / texture_size
	avatar_background_image.scale.y = preview_size.y / texture_size
	avatar_background_image.position = center_pos
	
	# Center all the character parts
	for sprite in [ avatar_base_body, avatar_hair, avatar_eyes, avatar_mouth, \
					avatar_clothing, avatar_head_accessories, avatar_face_accessories ]:
		sprite.centered = true
		sprite.position = center_pos

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
	gradient.add_point(0.0, Color.from_hsv(color.h, color.s, 0.0))
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

# --- NEW: Helper to get all current avatar settings ---
func _get_current_avatar_settings() -> Dictionary:
	return {
		"background": {
			"color": SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89")),
			"brightness": SettingsManager.get_setting("avatar_background", "brightness", 0.0),
			"style": SettingsManager.get_setting("avatar_background", "style", "Plain"),
		},
		"body": {
			"color": SettingsManager.get_setting("avatar_body", "color", Color("#e0ac69")),
			"brightness": SettingsManager.get_setting("avatar_body", "brightness", 0.0),
			"head_style": SettingsManager.get_setting("avatar_body", "head_style", "Default"),
		},
		"hair": {
			"color": SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b")),
			"brightness": SettingsManager.get_setting("avatar_hair", "brightness", 0.0),
			"style": SettingsManager.get_setting("avatar_hair", "style", "Spiky"),
		},
		"face": {
			"eyes": SettingsManager.get_setting("avatar_face", "eyes", "Open"),
			"mouth": SettingsManager.get_setting("avatar_face", "mouth", "Plain"),
		},
		"clothing": {
			"color": SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c")),
			"brightness": SettingsManager.get_setting("avatar_clothing", "brightness", 0.0),
			"style": SettingsManager.get_setting("avatar_clothing", "style", "T-Shirt"),
		},
		"accessories": {
			"color": SettingsManager.get_setting("avatar_accessories", "color", Color("#ffffff")),
			"brightness": SettingsManager.get_setting("avatar_accessories", "brightness", 0.0),
			"head_style": SettingsManager.get_setting("avatar_accessories", "head_style", "None"),
			"face_style": SettingsManager.get_setting("avatar_accessories", "face_style", "None"),
		}
	}

# --- REBUILT: Function to create full avatar previews for each option ---
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
		var thumbnail: AvatarThumbnail = AvatarThumbnailScene.instantiate()
		thumbnail.custom_minimum_size = Vector2(64, 64)
		
		# Add the thumbnail to the scene tree FIRST
		hbox.add_child(thumbnail) 
		
		# NOW, safely call the update function using call_deferred
		thumbnail.call_deferred("update_preview", current_settings, category, key, style_name)

		if style_name == current_style_value:
			thumbnail.set_selected(true)
		
		# The connection logic remains the same
		thumbnail.pressed.connect(func():
			_on_avatar_setting_changed(category, key, style_name, true)
		)
		
		hbox.add_child(thumbnail)

	_add_property_to_box(scroll_container)

# --- Popup Management ---

func _exit_tree():
	print("SettingsPopup: _exit_tree() called.")
	if is_instance_valid(dim_rect):
		dim_rect.queue_free()

func setup_popup(dimmer: ColorRect):
	dim_rect = dimmer
	if is_instance_valid(dim_rect):
		dim_rect.gui_input.connect(_on_dim_rect_gui_input)

func _on_dim_rect_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close_popup()

func add_custom_setting(control_node: Control):
	if custom_settings_container:
		custom_settings_container.add_child(control_node)
	else:
		printerr("SettingsPopup: ERROR! custom_settings_container is null.")
