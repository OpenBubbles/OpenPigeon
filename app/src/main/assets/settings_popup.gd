extends PanelContainer
class_name SettingsPopup

signal closed
signal settings_theme_selected(new_theme_name: String)

# --- Existing Nodes ---
@onready var settings_label = %SettingsLabel as Label
@onready var theme_option_button = %ThemeOptionButton as OptionButton

# --- New Avatar Customizer Nodes ---
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

var avatar_body_regions = {
	"Default": Rect2(0, 0, 64, 64),
	"Smiling": Rect2(64, 0, 64, 64),
	"Winking": Rect2(128, 0, 64, 64),
	"Surprised": Rect2(192, 0, 64, 64),
	"Frowning": Rect2(256, 0, 64, 64),
	"Tongue Out": Rect2(320, 0, 64, 64),
	"Cute": Rect2(384, 0, 64, 64)
}

var dim_rect: ColorRect # Reference to the dimming ColorRect

# --- Constants for the customizer ---
const ICON_SVG_PATH = "res://icon.svg"
const GRABBER_IMAGE_PATH = "res://hollow_grabber.png" # Path to your custom grabber

# --- New Texture Map and Region Data ---
const AVATAR_BODY_MAP_PATH = "res://avatar_textures/body/avatar_bodies.png"
const AVATAR_HAIR_MAP_PATH = "res://avatar_textures/hair/avatar_hair.png"
const AVATAR_EYES_MAP_PATH = "res://avatar_textures/face/avatar_eyes.png"
const AVATAR_MOUTH_MAP_PATH = "res://avatar_textures/face/avatar_mouth.png"
const AVATAR_CLOTHING_MAP_PATH = "res://avatar_textures/clothing/avatar_clothing.png"
const AVATAR_ACCESSORIES_MAP_PATH = "res://avatar_textures/accessories/avatar_accessories.png" # New accessory texture map

# Dictionary to store regions for different avatar parts on the texture map.
# The key is the name of the part, and the value is the Rect2 region on the texture map.
# You will need to define these regions based on your actual texture maps.
var avatar_hair_regions = {
	"Spiky": Rect2(0, 0, 64, 64),
	"Long": Rect2(64, 0, 64, 64),
	"Bun": Rect2(128, 0, 64, 64),
	"Bald": Rect2(192, 0, 64, 64),
}

var avatar_eyes_regions = {
	"Open": Rect2(0, 0, 64, 64),
	"Closed": Rect2(64, 0, 64, 64),
	"Winking": Rect2(128, 0, 64, 64),
}

var avatar_mouth_regions = {
	"Plain": Rect2(0, 0, 64, 64),
	"Smile": Rect2(64, 0, 64, 64),
	"Frown": Rect2(128, 0, 64, 64),
}

var avatar_clothing_regions = {
	"T-Shirt": Rect2(0, 0, 64, 64),
	"Sweater": Rect2(64, 0, 64, 64),
	"Tank Top": Rect2(128, 0, 64, 64),
}

# New: Placeholder for accessories regions - you'll need to define these based on your texture map
var avatar_head_accessories_regions = {
	"None": Rect2(0, 0, 1, 1), # A tiny region for "None" if you want to display an empty texture
	"Hat1": Rect2(0, 0, 64, 64), # Example head accessory
	"Headband": Rect2(64, 0, 64, 64), # Example head accessory
}

var avatar_face_accessories_regions = {
	"None": Rect2(0, 0, 1, 1), # A tiny region for "None" if you want to display an empty texture
	"Glasses": Rect2(128, 0, 64, 64), # Example face accessory (glasses)
	"Mask": Rect2(192, 0, 64, 64), # Example face accessory (mask)
}

# Store a reference to the brightness slider for updating its gradient
var current_brightness_slider: HSlider = null


# --- Main Functions ---

func _ready():
	print("SettingsPopup: _ready() called.")
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
	# Check for each node individually to provide a specific error message.
	if not is_instance_valid(avatar_tab_container):
		printerr("SettingsPopup: ERROR! AvatarTabContainer node not found. Check your scene tree.")
		return
	if not is_instance_valid(properties_box):
		printerr("SettingsPopup: ERROR! PropertiesBox node not found. Check your scene tree.")
		return
	if not is_instance_valid(avatar_preview):
		printerr("SettingsPopup: ERROR! AvatarPreview node not found. Check your scene tree.")
		return
	if not is_instance_valid(avatar_background_image):
		printerr("SettingsPopup: ERROR! AvatarBackground node not found. Check your scene tree.")
		return
	if not is_instance_valid(avatar_base_body):
		printerr("SettingsPopup: ERROR! AvatarBaseBody node not found. Check your scene tree.")
		return
	if not is_instance_valid(avatar_hair):
		printerr("SettingsPopup: ERROR! AvatarHair node not found. Check your scene tree.")
		return
	if not is_instance_valid(avatar_eyes):
		printerr("SettingsPopup: ERROR! AvatarEyes node not found. Check your scene tree.")
		return
	if not is_instance_valid(avatar_mouth):
		printerr("SettingsPopup: ERROR! Avatarmouth node not found. Check your scene tree.")
		return
	if not is_instance_valid(avatar_clothing):
		printerr("SettingsPopup: ERROR! AvatarClothing node not found. Check your scene tree.")
		return
	if not is_instance_valid(avatar_head_accessories):
		printerr("SettingsPopup: ERROR! AvatarHeadAccessories node not found. Check your scene tree.")
		return
	if not is_instance_valid(avatar_face_accessories):
		printerr("SettingsPopup: ERROR! AvatarFaceAccessories node not found. Check your scene tree.")
		return

	# If we get here, all nodes are present. Proceed with setup.
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
		
func _load_avatar_textures():
	# Load texture maps for all avatar parts.
	var body_texture = load(AVATAR_BODY_MAP_PATH)
	if is_instance_valid(body_texture):
		avatar_base_body.texture = body_texture
	else:
		printerr("SettingsPopup: ERROR! Failed to load body texture at path: ", AVATAR_BODY_MAP_PATH)

	var hair_texture = load(AVATAR_HAIR_MAP_PATH)
	if is_instance_valid(hair_texture):
		avatar_hair.texture = hair_texture
	else:
		printerr("SettingsPopup: ERROR! Failed to load hair texture at path: ", AVATAR_HAIR_MAP_PATH)

	var eyes_texture = load(AVATAR_EYES_MAP_PATH)
	if is_instance_valid(eyes_texture):
		avatar_eyes.texture = eyes_texture
	else:
		printerr("SettingsPopup: ERROR! Failed to load eyes texture at path: ", AVATAR_EYES_MAP_PATH)

	var mouth_texture = load(AVATAR_MOUTH_MAP_PATH)
	if is_instance_valid(mouth_texture):
		avatar_mouth.texture = mouth_texture
	else:
		printerr("SettingsPopup: ERROR! Failed to load mouth texture at path: ", AVATAR_MOUTH_MAP_PATH)

	var clothing_texture = load(AVATAR_CLOTHING_MAP_PATH)
	if is_instance_valid(clothing_texture):
		avatar_clothing.texture = clothing_texture
	else:
		printerr("SettingsPopup: ERROR! Failed to load clothing texture at path: ", AVATAR_CLOTHING_MAP_PATH)

	# New: Load accessories texture map
	var accessories_texture = load(AVATAR_ACCESSORIES_MAP_PATH)
	if is_instance_valid(accessories_texture):
		avatar_head_accessories.texture = accessories_texture
		avatar_face_accessories.texture = accessories_texture
	else:
		printerr("SettingsPopup: ERROR! Failed to load accessories texture at path: ", AVATAR_ACCESSORIES_MAP_PATH)

	# background texture is handled in _update_avatar_preview() as it's optional

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
	# --- Update Background ---
	# 1. Get the base color and brightness value from settings.
	var bg_color = SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89"))
	var bg_brightness = SettingsManager.get_setting("avatar_background", "brightness", 0.0)

	# 2. Calculate the final background color.
	var final_bg = calculate_final_color_with_brightness(bg_color, bg_brightness)

	# 3. Apply this final color to the preview’s ColorRect.
	if is_instance_valid(avatar_preview):
		var bg_rect = avatar_preview.get_node("ColorRect") as ColorRect
		if is_instance_valid(bg_rect):
			bg_rect.color = final_bg
		else:
			printerr("SettingsPopup: ERROR! 'ColorRect' not found in AvatarPreview.")
	
	# 4. Background image preset (if any)
	var bg_image_idx = SettingsManager.get_setting("avatar_background", "image_preset", -1)
	if bg_image_idx != -1:
		# avatar_background_image.texture = load(your_image_paths[bg_image_idx])
		pass
	else:
		avatar_background_image.texture = null

	# --- Update Body (Skin Tone + Style) ---
	# 1. Apply skin tone + brightness
	var tone_color = SettingsManager.get_setting("avatar_body", "color", Color("#e0ac69"))
	var tone_bright = SettingsManager.get_setting("avatar_body", "brightness", 0.0)
	var final_tone = calculate_final_color_with_brightness(tone_color, tone_bright)
	avatar_base_body.self_modulate = final_tone

	# 2. Apply body region/style
	var body_style = SettingsManager.get_setting("avatar_body", "head_style", "Default")
	if avatar_body_regions.has(body_style):
		avatar_base_body.region_enabled = true
		avatar_base_body.region_rect = avatar_body_regions[body_style]
	else:
		avatar_base_body.region_enabled = false
		avatar_base_body.region_rect = Rect2()

	# --- Update Hair ---
	var hair_style = SettingsManager.get_setting("avatar_hair", "style", "Spiky")
	var hair_color = SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b"))
	var hair_brightness = SettingsManager.get_setting("avatar_hair", "brightness", 0.0)
	var final_hair_color = calculate_final_color_with_brightness(hair_color, hair_brightness)
	avatar_hair.self_modulate = final_hair_color

	if avatar_hair_regions.has(hair_style):
		avatar_hair.region_enabled = true
		avatar_hair.region_rect = avatar_hair_regions[hair_style]
	else:
		avatar_hair.region_enabled = false
		avatar_hair.region_rect = Rect2()

	# --- Update Face (Eyes and Mouth) ---
	var eyes_style = SettingsManager.get_setting("avatar_face", "eyes", "Open")
	if avatar_eyes_regions.has(eyes_style):
		avatar_eyes.region_enabled = true
		avatar_eyes.region_rect = avatar_eyes_regions[eyes_style]
	else:
		avatar_eyes.region_enabled = false
		avatar_eyes.region_rect = Rect2()

	var mouth_style = SettingsManager.get_setting("avatar_face", "mouth", "Plain")
	if avatar_mouth_regions.has(mouth_style):
		avatar_mouth.region_enabled = true
		avatar_mouth.region_rect = avatar_mouth_regions[mouth_style]
	else:
		avatar_mouth.region_enabled = false
		avatar_mouth.region_rect = Rect2()

	# --- Update Clothing ---
	var clothing_style = SettingsManager.get_setting("avatar_clothing", "style", "T-Shirt")
	var clothing_color = SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c"))
	var clothing_brightness = SettingsManager.get_setting("avatar_clothing", "brightness", 0.0)
	var final_clothing_color = calculate_final_color_with_brightness(clothing_color, clothing_brightness)
	avatar_clothing.self_modulate = final_clothing_color

	if avatar_clothing_regions.has(clothing_style):
		avatar_clothing.region_enabled = true
		avatar_clothing.region_rect = avatar_clothing_regions[clothing_style]
	else:
		avatar_clothing.region_enabled = false
		avatar_clothing.region_rect = Rect2()

	# --- Update Accessories ---
	var head_accessory_style = SettingsManager.get_setting("avatar_accessories", "head_style", "None")
	var face_accessory_style = SettingsManager.get_setting("avatar_accessories", "face_style", "None")
	var accessories_color = SettingsManager.get_setting("avatar_accessories", "color", Color("#ffffff")) # Applies to both
	var accessories_brightness = SettingsManager.get_setting("avatar_accessories", "brightness", 0.0)
	var final_accessories_color = calculate_final_color_with_brightness(accessories_color, accessories_brightness)
	
	avatar_head_accessories.self_modulate = final_accessories_color
	if avatar_head_accessories_regions.has(head_accessory_style):
		avatar_head_accessories.region_enabled = true
		avatar_head_accessories.region_rect = avatar_head_accessories_regions[head_accessory_style]
		if head_accessory_style == "None":
			avatar_head_accessories.self_modulate.a = 0.0
		else:
			avatar_head_accessories.self_modulate.a = 1.0
	else:
		avatar_head_accessories.region_enabled = false
		avatar_head_accessories.region_rect = Rect2()
		avatar_head_accessories.self_modulate.a = 0.0

	avatar_face_accessories.self_modulate = final_accessories_color
	if avatar_face_accessories_regions.has(face_accessory_style):
		avatar_face_accessories.region_enabled = true
		avatar_face_accessories.region_rect = avatar_face_accessories_regions[face_accessory_style]
		if face_accessory_style == "None":
			avatar_face_accessories.self_modulate.a = 0.0
		else:
			avatar_face_accessories.self_modulate.a = 1.0
	else:
		avatar_face_accessories.region_enabled = false
		avatar_face_accessories.region_rect = Rect2()
		avatar_face_accessories.self_modulate.a = 0.0


	# --- Update Brightness Slider Gradient ---
	if is_instance_valid(current_brightness_slider):
		var slider_category: String = current_brightness_slider.get_meta("category") if current_brightness_slider.has_meta("category") else "background"
		var slider_key: String = current_brightness_slider.get_meta("key") if current_brightness_slider.has_meta("key") else "" # Get the key too
		
		if slider_category == "body":
			_update_brightness_slider_gradient(tone_color)
		elif slider_category == "hair":
			_update_brightness_slider_gradient(hair_color)
		elif slider_category == "clothing":
			_update_brightness_slider_gradient(clothing_color)
		elif slider_category == "accessories":
			_update_brightness_slider_gradient(accessories_color)
		else:
			_update_brightness_slider_gradient(bg_color)

	# --- Re-center all avatar sprites ---
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

func _on_avatar_setting_changed(category: String, key: String, value):
	var section = "avatar_" + category
	SettingsManager.set_setting(section, key, value)
	_update_avatar_preview()

func _populate_background_properties():
	print("SettingsPopup: Populating background properties.")

	# grab the saved background color as your default
	var default_color = SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89"))

	# 1. Preset Color Dots (your custom palette!)
	var preset_colors: PackedColorArray = PackedColorArray([
		Color("#7c7b7c"), Color("#e962a1"), Color("#9d45c1"),
		Color("#5897f9"), Color("#32d5ca"), Color("#7cb23f"),
		Color("#b2d91c"), Color("#f6d61e"), Color("#ef7c0b"),
		Color("#f1200a"), Color("#d42c2f")
	])
	_create_color_dot_presets("background", "color", preset_colors, default_color)

	# 2. Brightness Slider
	var initial_brightness = SettingsManager.get_setting("avatar_background", "brightness", default_color.v)
	_create_horizontal_slider("Brightness", "background", "brightness", initial_brightness, -1.0, 1.0, 0.01)

	# 3. Image Presets
	# Use style names as the keys for your presets
	var bg_image_styles = ["Image1", "Image2", "Image3"] # You'll need to define these
	_create_image_presets_scrollbar("background", "image_preset", bg_image_styles)

func _populate_body_properties():
	print("SettingsPopup: Populating body properties.")
	
	# 1. Body Style Image Scrollbar
	var body_styles = avatar_body_regions.keys()
	var default_style = SettingsManager.get_setting("avatar_body", "head_style", "Default")
	_create_image_presets_scrollbar("body", "head_style", body_styles)

	# 2. Skin Tone Color Dots
	# Define a custom palette of skin tones
	var skin_tones: PackedColorArray = PackedColorArray([
		Color("#ffbd9a"),
		Color("#ffb070"),
		Color("#804734"),
		Color("#5f442f"),
		Color("#cccccc"),
		Color("#da73a2"),
		Color("#6394f1"),
		Color("#82b941"),
		Color("#f8cf55"),
		Color("#f6820c"),
		Color("#c34126")
	])
	var default_tone = SettingsManager.get_setting("avatar_body", "color", Color("#e0ac69"))
	_create_color_dot_presets("body", "color", skin_tones, default_tone)

	# 3. Brightness Slider for Tone Adjustment
	var initial_brightness = SettingsManager.get_setting("avatar_body", "brightness", 0.0)
	_create_horizontal_slider("Brightness", "body", "brightness", initial_brightness, -1.0, 1.0, 0.01)

func _populate_hair_properties():
	print("SettingsPopup: Populating hair properties.")
	
	# 1. Hair Style Image Scrollbar
	var hair_styles = avatar_hair_regions.keys()
	var default_style = SettingsManager.get_setting("avatar_hair", "style", "Spiky")
	_create_image_presets_scrollbar("hair", "style", hair_styles)

	# 2. Hair Color Dots
	# Define a custom palette of hair colors
	var hair_colors: PackedColorArray = PackedColorArray([
		Color("#2c232b"), # Black
		Color("#4a2c2c"), # Dark Brown
		Color("#8b4513"), # Brown
		Color("#b8860b"), # Golden Blonde
		Color("#d2b48c"), # Sandy Blonde
		Color("#f0e68c"), # Light Blonde
		Color("#ff0000"), # Red
		Color("#800080"), # Purple
		Color("#0000ff"), # Blue
		Color("#00ff00"), # Green
		Color("#ffffff")  # White
	])
	var default_color = SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b"))
	_create_color_dot_presets("hair", "color", hair_colors, default_color)

	# 3. Brightness Slider for Hair Color Adjustment
	var initial_brightness = SettingsManager.get_setting("avatar_hair", "brightness", 0.0)
	_create_horizontal_slider("Brightness", "hair", "brightness", initial_brightness, -1.0, 1.0, 0.01)


func _populate_face_properties():
	print("SettingsPopup: Populating face properties.")
	
	# 1. Eyes Style Image Scrollbar
	var eye_styles = avatar_eyes_regions.keys()
	var default_eyes = SettingsManager.get_setting("avatar_face", "eyes", "Open")
	_create_image_presets_scrollbar("face", "eyes", eye_styles)

	# 2. Mouth Style Image Scrollbar
	var mouth_styles = avatar_mouth_regions.keys()
	var default_mouth = SettingsManager.get_setting("avatar_face", "mouth", "Plain")
	_create_image_presets_scrollbar("face", "mouth", mouth_styles)

func _populate_clothing_properties():
	print("SettingsPopup: Populating clothing properties.")
	
	# 1. Clothing Style Image Scrollbar
	var clothing_styles = avatar_clothing_regions.keys()
	var default_style = SettingsManager.get_setting("avatar_clothing", "style", "T-Shirt")
	_create_image_presets_scrollbar("clothing", "style", clothing_styles)

	# 2. Clothing Color Dots
	# Define a custom palette of clothing colors
	var clothing_colors: PackedColorArray = PackedColorArray([
		Color("#a03c3c"), # Red
		Color("#3c3ca0"), # Blue
		Color("#3ca03c"), # Green
		Color("#a0a03c"), # Yellow
		Color("#a03ca0"), # Purple
		Color("#3ca0a0"), # Cyan
		Color("#808080"), # Gray
		Color("#ffffff"), # White
		Color("#000000")  # Black
	])
	var default_color = SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c"))
	_create_color_dot_presets("clothing", "color", clothing_colors, default_color)

	# 3. Brightness Slider for Clothing Color Adjustment
	var initial_brightness = SettingsManager.get_setting("avatar_clothing", "brightness", 0.0)
	_create_horizontal_slider("Brightness", "clothing", "brightness", initial_brightness, -1.0, 1.0, 0.01)

func _populate_accessories_properties():
	print("SettingsPopup: Populating accessories properties.")
	
	# 1. Head Accessories Style Image Scrollbar
	var head_accessories_styles = avatar_head_accessories_regions.keys()
	var default_head_style = SettingsManager.get_setting("avatar_accessories", "head_style", "None")
	_create_image_presets_scrollbar("accessories", "head_style", head_accessories_styles)

	# 2. Face Accessories Style Image Scrollbar
	var face_accessories_styles = avatar_face_accessories_regions.keys()
	var default_face_style = SettingsManager.get_setting("avatar_accessories", "face_style", "None")
	_create_image_presets_scrollbar("accessories", "face_style", face_accessories_styles)

# --- Helper Functions to Create UI Controls ---

# Helper to wrap any control in a PanelContainer with white background and add to properties_box
func _add_property_to_box(control_to_wrap: Control):
	var panel_container = PanelContainer.new()
	# Create a custom stylebox for the white background
	var stylebox_flat = StyleBoxFlat.new()
	stylebox_flat.bg_color = Color(1, 1, 1, 0.1) # White with slight transparency
	stylebox_flat.border_width_left = 1
	stylebox_flat.border_width_top = 1
	stylebox_flat.border_width_right = 1
	stylebox_flat.border_width_bottom = 1
	stylebox_flat.border_color = Color(1, 1, 1, 0.2) # Light border
	stylebox_flat.corner_radius_top_left = 5
	stylebox_flat.corner_radius_top_right = 5
	stylebox_flat.corner_radius_bottom_left = 5
	stylebox_flat.corner_radius_bottom_right = 5
	stylebox_flat.set_content_margin(SIDE_LEFT, 10)
	stylebox_flat.set_content_margin(SIDE_RIGHT, 10)
	stylebox_flat.set_content_margin(SIDE_TOP, 5)
	stylebox_flat.set_content_margin(SIDE_BOTTOM, 5)
	panel_container.add_theme_stylebox_override("panel", stylebox_flat)

	panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL # Make the background fill horizontally
	properties_box.add_child(panel_container) # Add panel_container to properties_box
	panel_container.add_child(control_to_wrap) # Add the actual control inside the panel_container

func _create_label(text: String):
	var label = Label.new()
	label.text = text
	properties_box.add_child(label)

func _create_option_button(label_text: String, category: String, key: String, options: Array, default_value):
	print("  Creating OptionButton for: ", label_text)
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label = Label.new()
	label.text = label_text + ":"

	var option_btn = OptionButton.new()
	option_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in options:
		option_btn.add_item(item)

	var item_index = options.find(default_value)
	if item_index != -1:
		option_btn.select(item_index)

	option_btn.item_selected.connect(func(index):
		_on_avatar_setting_changed(category, key, option_btn.get_item_text(index))
	)

	hbox.add_child(label)
	hbox.add_child(option_btn)
	_add_property_to_box(hbox) # Wrap in PanelContainer

func _create_color_picker(label_text: String, category: String, key: String, default_color: Color):
	print("  Creating ColorPicker for: ", label_text)
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label = Label.new()
	label.text = label_text + ":"

	var color_picker = ColorPickerButton.new()
	color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_picker.color = default_color

	color_picker.color_changed.connect(func(new_color):
		_on_avatar_setting_changed(category, key, new_color)
	)

	hbox.add_child(label)
	hbox.add_child(color_picker)
	_add_property_to_box(hbox) # Wrap in PanelContainer

func _create_filler_label(text: String):
	print("  Creating Filler Label: ", text)
	var label = Label.new()
	label.text = text
	properties_box.add_child(label)
	
func _center_avatar_sprites():
	# get_size() on a Control gives you its rect size
	var preview_size : Vector2 = avatar_preview.get_size()
	# midpoint
	var center_pos : Vector2 = preview_size * 0.5

	for sprite in [ avatar_base_body, avatar_hair, avatar_eyes, avatar_mouth,
					avatar_clothing, avatar_head_accessories, avatar_face_accessories ]:
		sprite.centered = true# ensure pivot is middle
		sprite.position = center_pos


func _create_color_dot_presets(category: String, key: String, colors: PackedColorArray, default_color: Color):
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var diameter = 24
	var radius = diameter * 0.5

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	for color_value in colors:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(diameter, diameter)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = color_value
		style_normal.border_width_left = 2
		style_normal.border_width_top = 2
		style_normal.border_width_right = 2
		style_normal.border_width_bottom = 2
		
		style_normal.border_color = color_value.darkened(0.2)
		
		style_normal.corner_radius_top_left = radius
		style_normal.corner_radius_top_right = radius
		style_normal.corner_radius_bottom_left = radius
		style_normal.corner_radius_bottom_right = radius
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("pressed", style_normal.duplicate())

		var style_focus = style_normal.duplicate()
		style_focus.border_color = Color(0.2, 0.8, 0.2, 0.9)
		btn.add_theme_stylebox_override("hover", style_focus)
		btn.add_theme_stylebox_override("focus", style_focus)

		btn.set_meta("preset_color", color_value)

		var loop_btn = btn
		btn.pressed.connect(func():
			var sel_color: Color = loop_btn.get_meta("preset_color")
			# 1. Reset the brightness slider to the center (0.0)
			if is_instance_valid(current_brightness_slider):
				current_brightness_slider.value = 0.0
			
			# 2. Save the new color and the reset brightness value to settings
			_on_avatar_setting_changed(category, key, sel_color)
			
			# If this is a color setting that also has a brightness slider, reset its brightness
			if category == "body" or category == "hair" or \
			   (category == "clothing" and key == "color") or (category == "accessories" and key == "color"):
				_on_avatar_setting_changed(category, "brightness", 0.0)
			
			# 3. Update the slider’s gradient bar and the selected dot's border
			if is_instance_valid(current_brightness_slider):
				_update_brightness_slider_gradient(sel_color)
			
			_update_selected_color_dot_border(hbox, sel_color)
		)

		hbox.add_child(btn)

		var spacer_mid = Control.new()
		spacer_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(spacer_mid)

	_add_property_to_box(hbox)

# Helper to update border of selected color dot
func _update_selected_color_dot_border(parent_hbox: HBoxContainer, selected_color: Color):
	for child in parent_hbox.get_children():
		if child is Button and child.has_meta("preset_color"):
			# Retrieve the current stylebox from the button itself
			var stylebox_normal = child.get_theme_stylebox("normal") as StyleBoxFlat
			if stylebox_normal:
				if child.get_meta("preset_color") == selected_color:
					stylebox_normal.border_color = Color(0.2, 0.8, 0.2, 0.9) # Highlight with green
					stylebox_normal.border_width_left = 3
					stylebox_normal.border_width_top = 3
					stylebox_normal.border_width_right = 3
					stylebox_normal.border_width_bottom = 3
				else:
					# Reset to the default border color for unselected dots
					stylebox_normal.border_color = child.get_meta("preset_color").darkened(0.2)
					stylebox_normal.border_width_left = 2
					stylebox_normal.border_width_top = 2
					stylebox_normal.border_width_right = 2
					stylebox_normal.border_width_bottom = 2
				# Reapply the modified stylebox (important!)
				child.add_theme_stylebox_override("normal", stylebox_normal)
				child.add_theme_stylebox_override("pressed", stylebox_normal.duplicate()) # Also update pressed state

func _create_horizontal_slider(label_text: String, category: String, key: String, initial_value: float, min_value: float, max_value: float, step: float):
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label = Label.new()
	label.text = label_text + ":"
	hbox.add_child(label)

	var slider = HSlider.new()
	slider.set_meta("category", category)
	slider.set_meta("key", key) # Set the key meta for specific brightness sliders
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = initial_value
	slider.value_changed.connect(func(new_val):
		_on_avatar_setting_changed(category, key, new_val)
	)
	hbox.add_child(slider)

	if key == "brightness" or key == "eye_brightness": # Check for brightness sliders
		current_brightness_slider = slider
		var initial_color: Color
		if category == "body":
			initial_color = SettingsManager.get_setting("avatar_body", "color", Color("#e0ac69"))
		elif category == "hair":
			initial_color = SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b"))
		elif category == "clothing":
			initial_color = SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c"))
		elif category == "accessories":
			initial_color = SettingsManager.get_setting("avatar_accessories", "color", Color("#ffffff"))
		else:
			initial_color = SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89"))
		_update_brightness_slider_gradient(initial_color)

	_add_property_to_box(hbox)

func _update_brightness_slider_gradient(color: Color):
	# Determine which palette we’re adjusting (body, hair, face, clothing or background)
	if not is_instance_valid(current_brightness_slider):
		return

	var category: String = current_brightness_slider.get_meta("category") if current_brightness_slider.has_meta("category") else "background"
	var base_color : Color
	match category:
		"body":
			base_color = SettingsManager.get_setting("avatar_body", "color", Color("#e0ac69"))
		"hair":
			base_color = SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b"))
		"clothing":
			base_color = SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c"))
		"accessories":
			base_color = SettingsManager.get_setting("avatar_accessories", "color", Color("#ffffff"))
		_: # Default to background
			base_color = SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89"))

	# 1. Create the new Gradient (Black -> Base Color -> White)
	var h := base_color.h
	var s := base_color.s
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color.from_hsv(h, s, 0.0))# black at slider -1.0
	gradient.add_point(0.5, base_color)# base color at slider 0.0
	gradient.add_point(1.0, Color.from_hsv(h, 0.0, 1.0))# white at slider +1.0

	# 2. Build the texture and stylebox
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = gradient
	grad_tex.width = 256
	grad_tex.height = 1

	var main_bar_style := StyleBoxTexture.new()
	main_bar_style.texture = grad_tex
	main_bar_style.texture_margin_top = 8
	main_bar_style.texture_margin_bottom = 8
	main_bar_style.texture_margin_left = 6
	main_bar_style.texture_margin_right = 6
	current_brightness_slider.add_theme_stylebox_override("slider", main_bar_style)

	# 3. Clear the filled area to the left of the grabber
	var clear_style := StyleBoxFlat.new()
	clear_style.bg_color = Color.TRANSPARENT
	current_brightness_slider.add_theme_stylebox_override("grabber_area", clear_style)
	current_brightness_slider.add_theme_stylebox_override("grabber_area_highlight", clear_style)

	# 4. Use the custom grabber icon
	var grabber_icon := load(GRABBER_IMAGE_PATH)
	current_brightness_slider.add_theme_icon_override("grabber", grabber_icon)
	current_brightness_slider.add_theme_icon_override("grabber_highlight", grabber_icon)
	current_brightness_slider.add_theme_icon_override("grabber_pressed", grabber_icon)
	
# Function to create image presets with a horizontal scrollbar
func _create_image_presets_scrollbar(category: String, key: String, style_options: Array):
	var scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.custom_minimum_size = Vector2(0, 70) # Give it some height for the images
	
	var hbox_images = HBoxContainer.new()
	hbox_images.add_theme_constant_override("separation", 10) # Space between images
	hbox_images.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hbox_images.size_flags_vertical = Control.SIZE_EXPAND_FILL

	for style_name in style_options:
		var texture_button = TextureButton.new()
		
		# Determine the correct texture based on category and style_name
		var texture_to_load: Texture2D = load(ICON_SVG_PATH) # Default fallback

		if category == "body":
			if avatar_body_regions.has(style_name):
				var region_rect = avatar_body_regions[style_name]
				var full_texture = load(AVATAR_BODY_MAP_PATH)
				if is_instance_valid(full_texture):
					var sub_tex = AtlasTexture.new()
					sub_tex.atlas = full_texture
					sub_tex.region = region_rect
					texture_to_load = sub_tex
		elif category == "hair":
			if avatar_hair_regions.has(style_name):
				var region_rect = avatar_hair_regions[style_name]
				var full_texture = load(AVATAR_HAIR_MAP_PATH)
				if is_instance_valid(full_texture):
					var sub_tex = AtlasTexture.new()
					sub_tex.atlas = full_texture
					sub_tex.region = region_rect
					texture_to_load = sub_tex
		elif category == "face":
			if key == "eyes" and avatar_eyes_regions.has(style_name):
				var region_rect = avatar_eyes_regions[style_name]
				var full_texture = load(AVATAR_EYES_MAP_PATH)
				if is_instance_valid(full_texture):
					var sub_tex = AtlasTexture.new()
					sub_tex.atlas = full_texture
					sub_tex.region = region_rect
					texture_to_load = sub_tex
			elif key == "mouth" and avatar_mouth_regions.has(style_name):
				var region_rect = avatar_mouth_regions[style_name]
				var full_texture = load(AVATAR_MOUTH_MAP_PATH)
				if is_instance_valid(full_texture):
					var sub_tex = AtlasTexture.new()
					sub_tex.atlas = full_texture
					sub_tex.region = region_rect
					texture_to_load = sub_tex
		elif category == "clothing":
			if avatar_clothing_regions.has(style_name):
				var region_rect = avatar_clothing_regions[style_name]
				var full_texture = load(AVATAR_CLOTHING_MAP_PATH)
				if is_instance_valid(full_texture):
					var sub_tex = AtlasTexture.new()
					sub_tex.atlas = full_texture
					sub_tex.region = region_rect
					texture_to_load = sub_tex
		elif category == "accessories": # New: Handle accessories textures
			if key == "head_style" and avatar_head_accessories_regions.has(style_name):
				var region_rect = avatar_head_accessories_regions[style_name]
				var full_texture = load(AVATAR_ACCESSORIES_MAP_PATH)
				if is_instance_valid(full_texture):
					var sub_tex = AtlasTexture.new()
					sub_tex.atlas = full_texture
					sub_tex.region = region_rect
					texture_to_load = sub_tex
				else:
					texture_to_load = load(ICON_SVG_PATH) # Fallback if texture map not loaded
			elif key == "face_style" and avatar_face_accessories_regions.has(style_name):
				var region_rect = avatar_face_accessories_regions[style_name]
				var full_texture = load(AVATAR_ACCESSORIES_MAP_PATH)
				if is_instance_valid(full_texture):
					var sub_tex = AtlasTexture.new()
					sub_tex.atlas = full_texture
					sub_tex.region = region_rect
					texture_to_load = sub_tex
				else:
					texture_to_load = load(ICON_SVG_PATH) # Fallback if texture map not loaded
			else:
				texture_to_load = load(ICON_SVG_PATH) # Fallback if style not found or key not recognized


		texture_button.texture_normal = texture_to_load

		# ADJUSTED: Smaller image size
		texture_button.custom_minimum_size = Vector2(48, 48) # Smaller size
		texture_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		
		# We'll use the style_name as the value to save to settings
		texture_button.pressed.connect(func():
			_on_avatar_setting_changed(category, key, style_name)
		)

		var stylebox_flat = StyleBoxFlat.new()
		stylebox_flat.bg_color = Color(0,0,0,0) # Transparent background
		stylebox_flat.border_width_left = 2
		stylebox_flat.border_width_top = 2
		stylebox_flat.border_width_right = 2
		stylebox_flat.border_width_bottom = 2
		stylebox_flat.border_color = Color(0.2, 0.6, 1.0, 0.7) # Blue border
		stylebox_flat.corner_radius_top_left = 5
		stylebox_flat.corner_radius_top_right = 5
		stylebox_flat.corner_radius_bottom_left = 5
		stylebox_flat.corner_radius_bottom_right = 5
		texture_button.add_theme_stylebox_override("focus", stylebox_flat) # Show on focus
		texture_button.add_theme_stylebox_override("hover", stylebox_flat) # Show on hover

		hbox_images.add_child(texture_button)

	scroll_container.add_child(hbox_images)
	_add_property_to_box(scroll_container) # Wrap in PanelContainer

func _exit_tree():
	print("SettingsPopup: _exit_tree() called.")
	if is_instance_valid(dim_rect):
		dim_rect.queue_free()

func setup_popup(dimmer: ColorRect):
	print("SettingsPopup: setup_popup() called with dimmer: ", dimmer.name if is_instance_valid(dimmer) else "null")
	dim_rect = dimmer
	if is_instance_valid(dim_rect):
		dim_rect.gui_input.connect(_on_dim_rect_gui_input)

func _on_dim_rect_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close_popup()

func add_custom_setting(control_node: Control):
	print("SettingsPopup: add_custom_setting() called with node: ", control_node.name if is_instance_valid(control_node) else "INVALID_NODE")
	if custom_settings_container:
		custom_settings_container.add_child(control_node)
		custom_settings_container.queue_sort()
	else:
		printerr("SettingsPopup: ERROR! custom_settings_container is null when trying to add custom setting.")
