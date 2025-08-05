# AvatarThumbnail.gd
# This script controls a single, self-contained avatar preview.
extends TextureButton
class_name AvatarThumbnail

# --- Node References (Using % Unique Name syntax) ---
@onready var viewport_container: SubViewportContainer = %SubViewportContainer
@onready var viewport: SubViewport = %SubViewport
@onready var background_rect: ColorRect = %ColorRect
@onready var avatar_background_image: Sprite2D = %AvatarBackground
@onready var avatar_base_body: Sprite2D = %AvatarBaseBody
@onready var avatar_hair: Sprite2D = %AvatarHair
@onready var avatar_eyes: Sprite2D = %AvatarEyes
@onready var avatar_mouth: Sprite2D = %AvatarMouth
@onready var avatar_clothing: Sprite2D = %AvatarClothing
@onready var avatar_head_accessories: Sprite2D = %AvatarHeadAccessories
@onready var avatar_face_accessories: Sprite2D = %AvatarFaceAccessories

# --- Textures and Regions (must match SettingsPopup.gd) ---
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

var _selection_stylebox: StyleBox = null

func _ready():
	# The SubViewport's texture is automatically used by the TextureButton parent
	texture_normal = viewport.get_texture()

	# Create a stylebox for highlighting the selection
	var stylebox_flat = StyleBoxFlat.new()
	stylebox_flat.bg_color = Color(0,0,0,0) # Transparent background
	stylebox_flat.border_width_left = 3
	stylebox_flat.border_width_top = 3
	stylebox_flat.border_width_right = 3
	stylebox_flat.border_width_bottom = 3
	stylebox_flat.border_color = Color(0.2, 0.8, 0.2, 0.9) # Bright green border
	stylebox_flat.corner_radius_top_left = 5
	stylebox_flat.corner_radius_top_right = 5
	stylebox_flat.corner_radius_bottom_left = 5
	stylebox_flat.corner_radius_bottom_right = 5
	_selection_stylebox = stylebox_flat

	# Initial centering of sprites
	_center_sprites()


func update_preview(settings: Dictionary, category: String, key: String, override_value):
	# Create a temporary copy of the settings to modify
	var temp_settings = settings.duplicate(true)
	# Apply the specific override for this thumbnail
	temp_settings[category][key] = override_value

	# --- Load Textures ---
	# In a larger project, you might pass textures in to avoid reloading them constantly.
	avatar_base_body.texture = load(AVATAR_BODY_MAP_PATH)
	avatar_hair.texture = load(AVATAR_HAIR_MAP_PATH)
	avatar_eyes.texture = load(AVATAR_EYES_MAP_PATH)
	avatar_mouth.texture = load(AVATAR_MOUTH_MAP_PATH)
	avatar_clothing.texture = load(AVATAR_CLOTHING_MAP_PATH)
	avatar_head_accessories.texture = load(AVATAR_ACCESSORIES_MAP_PATH)
	avatar_face_accessories.texture = load(AVATAR_ACCESSORIES_MAP_PATH)

	# --- Render Avatar using temp_settings ---
	var bg_color = temp_settings["background"]["color"]
	var bg_bright = temp_settings["background"]["brightness"]
	background_rect.color = _calculate_final_color(bg_color, bg_bright)
	
	var bg_style = temp_settings["background"]["style"]
	if bg_style == "Plain" or not avatar_background_regions.has(bg_style):
		avatar_background_image.texture = null # Hide the pattern sprite
		avatar_background_image.region_enabled = false
	else:
		avatar_background_image.texture = load(AVATAR_BG_MAP_PATH)
		avatar_background_image.region_enabled = true
		avatar_background_image.region_rect = avatar_background_regions[bg_style]

	var tone_color = temp_settings["body"]["color"]
	var tone_bright = temp_settings["body"]["brightness"]
	avatar_base_body.self_modulate = _calculate_final_color(tone_color, tone_bright)
	var body_style = temp_settings["body"]["head_style"]
	if avatar_body_regions.has(body_style):
		avatar_base_body.region_enabled = true
		avatar_base_body.region_rect = avatar_body_regions[body_style]

	var hair_color = temp_settings["hair"]["color"]
	var hair_bright = temp_settings["hair"]["brightness"]
	avatar_hair.self_modulate = _calculate_final_color(hair_color, hair_bright)
	var hair_style = temp_settings["hair"]["style"]
	if avatar_hair_regions.has(hair_style):
		avatar_hair.region_enabled = true
		avatar_hair.region_rect = avatar_hair_regions[hair_style]

	var eyes_style = temp_settings["face"]["eyes"]
	if avatar_eyes_regions.has(eyes_style):
		avatar_eyes.region_enabled = true
		avatar_eyes.region_rect = avatar_eyes_regions[eyes_style]

	var mouth_style = temp_settings["face"]["mouth"]
	if avatar_mouth_regions.has(mouth_style):
		avatar_mouth.region_enabled = true
		avatar_mouth.region_rect = avatar_mouth_regions[mouth_style]

	var clothing_color = temp_settings["clothing"]["color"]
	var clothing_bright = temp_settings["clothing"]["brightness"]
	avatar_clothing.self_modulate = _calculate_final_color(clothing_color, clothing_bright)
	var clothing_style = temp_settings["clothing"]["style"]
	if avatar_clothing_regions.has(clothing_style):
		avatar_clothing.region_enabled = true
		avatar_clothing.region_rect = avatar_clothing_regions[clothing_style]

	var acc_color = temp_settings["accessories"]["color"]
	var acc_bright = temp_settings["accessories"]["brightness"]
	var final_acc_color = _calculate_final_color(acc_color, acc_bright)
	
	avatar_head_accessories.self_modulate = final_acc_color
	var head_acc_style = temp_settings["accessories"]["head_style"]
	if avatar_head_accessories_regions.has(head_acc_style) and head_acc_style != "None":
		avatar_head_accessories.region_enabled = true
		avatar_head_accessories.region_rect = avatar_head_accessories_regions[head_acc_style]
		avatar_head_accessories.self_modulate.a = 1.0
	else:
		avatar_head_accessories.self_modulate.a = 0.0

	avatar_face_accessories.self_modulate = final_acc_color
	var face_acc_style = temp_settings["accessories"]["face_style"]
	if avatar_face_accessories_regions.has(face_acc_style) and face_acc_style != "None":
		avatar_face_accessories.region_enabled = true
		avatar_face_accessories.region_rect = avatar_face_accessories_regions[face_acc_style]
		avatar_face_accessories.self_modulate.a = 1.0
	else:
		avatar_face_accessories.self_modulate.a = 0.0

func set_selected(is_selected: bool):
	if is_selected:
		add_theme_stylebox_override("focus", _selection_stylebox)
		add_theme_stylebox_override("hover", _selection_stylebox)
		add_theme_stylebox_override("normal", _selection_stylebox)
		add_theme_stylebox_override("pressed", _selection_stylebox)
	else:
		# Clear the overrides to return to default
		remove_theme_stylebox_override("focus")
		remove_theme_stylebox_override("hover")
		remove_theme_stylebox_override("normal")
		remove_theme_stylebox_override("pressed")

func _center_sprites():
	var viewport_size = viewport.size # This is 64x64
	var center_pos = viewport_size / 2.0
	
	# --- Manually position and scale the background sprite ---
	# The base size of our background art region is 128x128
	var texture_size = 128.0
	avatar_background_image.scale.x = viewport_size.x / texture_size # 64 / 128 = 0.5
	avatar_background_image.scale.y = viewport_size.y / texture_size # 64 / 128 = 0.5
	avatar_background_image.position = center_pos
	
	# Center all the character parts
	for sprite in [ avatar_base_body, avatar_hair, avatar_eyes, avatar_mouth, \
					avatar_clothing, avatar_head_accessories, avatar_face_accessories ]:
		sprite.centered = true
		sprite.position = center_pos

func _calculate_final_color(base_color: Color, brightness_slider_val: float) -> Color:
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
