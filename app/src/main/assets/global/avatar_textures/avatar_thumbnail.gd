# AvatarThumbnail.gd
extends TextureButton
class_name AvatarThumbnail

@export var is_display_only: bool = false
@export var controlled_by_data: bool = false

@onready var color_rect: ColorRect = %ColorRect
@onready var avatar_background: Sprite2D = %AvatarBackground
@onready var avatar_base_body: Sprite2D = %AvatarBaseBody
@onready var avatar_hair_back: Sprite2D = %AvatarHairBack       # back layer
@onready var avatar_hair_front: Sprite2D = %AvatarHairFront     # front layer
@onready var avatar_eyes: Sprite2D = %AvatarEyes
@onready var avatar_mouth: Sprite2D = %AvatarMouth
@onready var avatar_clothing: Sprite2D = %AvatarClothing
@onready var avatar_head_accessories: Sprite2D = %AvatarHeadAccessories
@onready var avatar_face_accessories: Sprite2D = %AvatarFaceAccessories

const AVATAR_BG_MAP_PATH          = "res://global/avatar_textures/backgrounds/background_sheet.png"
const AVATAR_BODY_MAP_PATH        = "res://global/avatar_textures/body/avatar_bodies.png"
const AVATAR_HAIR_FRONT_MAP_PATH  = "res://global/avatar_textures/hair/avatar_hair_front.png"
const AVATAR_HAIR_BACK_MAP_PATH   = "res://global/avatar_textures/hair/avatar_hair_back.png"
const AVATAR_EYES_MAP_PATH        = "res://global/avatar_textures/face/avatar_eyes.png"
const AVATAR_MOUTH_MAP_PATH       = "res://global/avatar_textures/face/avatar_mouth.png"
const AVATAR_CLOTHING_MAP_PATH    = "res://global/avatar_textures/clothing/avatar_clothing.png"
const AVATAR_ACCESSORIES_MAP_PATH = "res://global/avatar_textures/accessories/avatar_accessories.png"

# ---- Absolute Z-ordering (Top to Bottom as requested) ----
# Top
const Z_FACE_ACCESSORIES := 80
const Z_HEAD_ACCESSORIES := 70
const Z_CLOTHING         := 60
const Z_HAIR_FRONT       := 50
const Z_MOUTH            := 40
const Z_EYES             := 30
const Z_BASE_BODY        := 20
const Z_HAIR_BACK        := 10
const Z_BACKGROUND       := 0
# Bottom
# ----------------------------------------------------------

var avatar_background_regions = {
	"Pattern 1": Rect2(0, 0, 128, 128),   "Pattern 2": Rect2(128, 0, 128, 128),
	"Pattern 3": Rect2(256, 0, 128, 128), "Pattern 4": Rect2(384, 0, 128, 128),
	"Pattern 5": Rect2(0, 128, 128, 128), "Pattern 6": Rect2(128, 128, 128, 128),
	"Pattern 7": Rect2(256, 128, 128, 128), "Pattern 8": Rect2(384, 128, 128, 128),
	"Pattern 9": Rect2(0, 256, 128, 128)
}
var avatar_body_regions = {
	"Default": Rect2(0, 0, 96, 64), "body1": Rect2(96, 0, 96, 64), "body2": Rect2(192, 0, 96, 64),
	"body3": Rect2(288, 0, 96, 64), "body4": Rect2(384, 0, 96, 64), "body5": Rect2(0, 64, 96, 64),
	"body6": Rect2(96, 64, 96, 64)
}
# Shared regions for BOTH hair layers (front/back)
var avatar_hair_regions = {
	"hair1": Rect2(0, 0, 2000, 2000),   "hair2": Rect2(2000, 0, 2000, 2000),
	"hair3": Rect2(4000, 0, 2000, 2000),"hair4": Rect2(6000, 0, 2000, 2000),
	"hair5": Rect2(8000, 0, 2000, 2000),"hair6": Rect2(0, 2000, 2000, 2000),
	"hair7": Rect2(2000, 2000, 2000, 2000),"hair8": Rect2(4000, 2000, 2000, 2000),
	"hair9": Rect2(6000, 2000, 2000, 2000),"hair10": Rect2(8000, 2000, 2000, 2000),
	"hair11": Rect2(0, 4000, 2000, 2000),"hair12": Rect2(2000, 4000, 2000, 2000),
	"hair13": Rect2(4000, 4000, 2000, 2000),"hair14": Rect2(6000, 4000, 2000, 2000),
	"hair15": Rect2(8000, 4000, 2000, 2000)
}
var avatar_eyes_regions  = { "Open": Rect2(0, 0, 64, 64), "Closed": Rect2(64, 0, 64, 64), "Winking": Rect2(128, 0, 64, 64) }
var avatar_mouth_regions = { "Plain": Rect2(0, 0, 64, 64), "Smile": Rect2(64, 0, 64, 64), "Frown": Rect2(128, 0, 64, 64) }
var avatar_clothing_regions = { "T-Shirt": Rect2(0, 0, 64, 64), "Sweater": Rect2(64, 0, 64, 64), "Tank Top": Rect2(128, 0, 64, 64) }
var avatar_head_accessories_regions = { "None": Rect2(0, 0, 1, 1), "Hat1": Rect2(0, 0, 64, 64), "Headband": Rect2(64, 0, 64, 64) }
var avatar_face_accessories_regions = { "None": Rect2(0, 0, 1, 1), "Glasses": Rect2(128, 0, 64, 64), "Mask": Rect2(192, 0, 64, 64) }

var _selection_stylebox: StyleBox = null

func _ready():
	print("AvatarThumbnail ready: '", self.name, "'. is_display_only: ", is_display_only, ", controlled_by_data: ", controlled_by_data)

	var stylebox_flat = StyleBoxFlat.new()
	stylebox_flat.bg_color = Color(0,0,0,0)
	stylebox_flat.border_width_left = 3; stylebox_flat.border_width_top = 3; stylebox_flat.border_width_right = 3; stylebox_flat.border_width_bottom = 3
	stylebox_flat.border_color = Color(0.2, 0.8, 0.2, 0.9)
	stylebox_flat.corner_radius_top_left = 5; stylebox_flat.corner_radius_top_right = 5; stylebox_flat.corner_radius_bottom_left = 5; stylebox_flat.corner_radius_bottom_right = 5
	_selection_stylebox = stylebox_flat

	if is_display_only:
		self.disabled = true
		
	if controlled_by_data:
		pass
	else:
		if SettingsManager:
			SettingsManager.avatar_changed.connect(update_display_from_settings)
		update_display_from_settings()

func update_preview(base_settings: Dictionary, category: String, key: String, override_value):
	var temp_settings = base_settings.duplicate(true)
	if not temp_settings.has(category):
		temp_settings[category] = {}
	temp_settings[category][key] = override_value
	_draw_avatar(temp_settings)
	
func update_avatar_from_data(avatar_data: Dictionary):
	print("SUCCESS: '", self.name, "' is updating from this external data: ", avatar_data)

	# Use single hair values from data, apply to BOTH layers so body can sit between
	var hair_color      = avatar_data.get("hair_color", Color.BLACK)
	var hair_brightness = avatar_data.get("hair_brightness", 0.0)
	var hair_style      = avatar_data.get("hair_style", "hair1")

	var settings = {
		"background": {
			"color": avatar_data.get("bg_color", Color.WHITE),
			"brightness": avatar_data.get("bg_brightness", 0.0),
			"style": avatar_data.get("bg_style", "Plain")
		},
		"body": {
			"color": avatar_data.get("body_color", Color.WHITE),
			"brightness": avatar_data.get("body_brightness", 0.0),
			"head_style": avatar_data.get("body_style", "Default")
		},
		# New front/back hair layers
		"hair_front": { "color": hair_color, "brightness": hair_brightness, "style": hair_style },
		"hair_back":  { "color": hair_color, "brightness": hair_brightness, "style": hair_style },
		"face": {
			"eyes": avatar_data.get("eyes_style", "Open"),
			"mouth": avatar_data.get("mouth_style", "Plain")
		},
		"clothing": {
			"color": avatar_data.get("clothing_color", Color.WHITE),
			"brightness": avatar_data.get("clothing_brightness", 0.0),
			"style": avatar_data.get("clothing_style", "T-Shirt")
		},
		"accessories": {
			"color": avatar_data.get("acc_color", Color.WHITE),
			"brightness": avatar_data.get("acc_brightness", 0.0),
			"head_style": avatar_data.get("head_acc_style", "None"),
			"face_style": avatar_data.get("face_acc_style", "None")
		}
	}
	_draw_avatar(settings)

func update_display_from_settings():
	var current_settings = _get_current_avatar_settings()
	_draw_avatar(current_settings)

func _draw_avatar(settings: Dictionary):
	# Background
	var bg_color = settings["background"]["color"]
	var final_bg = calculate_final_color(bg_color, settings["background"]["brightness"])
	color_rect.color = final_bg
	var bg_style = settings["background"]["style"]
	if bg_style == "Plain" or not avatar_background_regions.has(bg_style):
		color_rect.visible = true
		avatar_background.visible = false
	else:
		color_rect.visible = false
		avatar_background.visible = true
		var atlas = AtlasTexture.new()
		atlas.atlas = load(AVATAR_BG_MAP_PATH)
		atlas.region = avatar_background_regions[bg_style]
		avatar_background.texture = atlas
		
	# Body
	var tone_color = settings["body"]["color"]
	avatar_base_body.self_modulate = calculate_final_color(tone_color, settings["body"]["brightness"])
	avatar_base_body.texture = load(AVATAR_BODY_MAP_PATH)
	var body_style = settings["body"]["head_style"]
	if avatar_body_regions.has(body_style):
		avatar_base_body.region_enabled = true
		avatar_base_body.region_rect = avatar_body_regions[body_style]

	# Hair Back
	var hair_back_color = settings["hair_back"]["color"]
	avatar_hair_back.self_modulate = calculate_final_color(hair_back_color, settings["hair_back"]["brightness"])
	var back_tex: Texture2D = load(AVATAR_HAIR_BACK_MAP_PATH)
	if back_tex:
		avatar_hair_back.texture = back_tex
	else:
		push_warning("Avatar hair BACK texture missing: " + AVATAR_HAIR_BACK_MAP_PATH)
	var hair_style_back = settings["hair_back"]["style"]
	if avatar_hair_regions.has(hair_style_back):
		avatar_hair_back.region_enabled = true
		avatar_hair_back.region_rect = avatar_hair_regions[hair_style_back]

	# Hair Front
	var hair_front_color = settings["hair_front"]["color"]
	avatar_hair_front.self_modulate = calculate_final_color(hair_front_color, settings["hair_front"]["brightness"])
	var front_tex: Texture2D = load(AVATAR_HAIR_FRONT_MAP_PATH)
	if front_tex:
		avatar_hair_front.texture = front_tex
	else:
		push_warning("Avatar hair FRONT texture missing: " + AVATAR_HAIR_FRONT_MAP_PATH)
	var hair_style_front = settings["hair_front"]["style"]
	if avatar_hair_regions.has(hair_style_front):
		avatar_hair_front.region_enabled = true
		avatar_hair_front.region_rect = avatar_hair_regions[hair_style_front]

	# Face
	avatar_eyes.texture = load(AVATAR_EYES_MAP_PATH)
	avatar_mouth.texture = load(AVATAR_MOUTH_MAP_PATH)
	var eyes_style = settings["face"]["eyes"]
	if avatar_eyes_regions.has(eyes_style):
		avatar_eyes.region_enabled = true
		avatar_eyes.region_rect = avatar_eyes_regions[eyes_style]
	var mouth_style = settings["face"]["mouth"]
	if avatar_mouth_regions.has(mouth_style):
		avatar_mouth.region_enabled = true
		avatar_mouth.region_rect = avatar_mouth_regions[mouth_style]

	# Clothing
	var clothing_color = settings["clothing"]["color"]
	avatar_clothing.self_modulate = calculate_final_color(clothing_color, settings["clothing"]["brightness"])
	avatar_clothing.texture = load(AVATAR_CLOTHING_MAP_PATH)
	var clothing_style = settings["clothing"]["style"]
	if avatar_clothing_regions.has(clothing_style):
		avatar_clothing.region_enabled = true
		avatar_clothing.region_rect = avatar_clothing_regions[clothing_style]

	# Accessories
	var acc_color = settings["accessories"]["color"]
	var final_acc_color = calculate_final_color(acc_color, settings["accessories"]["brightness"])
	avatar_head_accessories.texture = load(AVATAR_ACCESSORIES_MAP_PATH)
	avatar_face_accessories.texture = load(AVATAR_ACCESSORIES_MAP_PATH)
	avatar_head_accessories.self_modulate = final_acc_color
	avatar_face_accessories.self_modulate = final_acc_color
	var head_acc_style = settings["accessories"]["head_style"]
	if avatar_head_accessories_regions.has(head_acc_style) and head_acc_style != "None":
		avatar_head_accessories.region_enabled = true
		avatar_head_accessories.region_rect = avatar_head_accessories_regions[head_acc_style]
		avatar_head_accessories.self_modulate.a = 1.0
	else:
		avatar_head_accessories.self_modulate.a = 0.0
	var face_acc_style = settings["accessories"]["face_style"]
	if avatar_face_accessories_regions.has(face_acc_style) and face_acc_style != "None":
		avatar_face_accessories.region_enabled = true
		avatar_face_accessories.region_rect = avatar_face_accessories_regions[face_acc_style]
		avatar_face_accessories.self_modulate.a = 1.0
	else:
		avatar_face_accessories.self_modulate.a = 0.0
	
	_center_and_scale_sprites()
	_apply_layer_order()

func _get_current_avatar_settings() -> Dictionary:
	# Pull hair from new keys, fall back to legacy single-layer if needed
	var hair_color  = SettingsManager.get_setting("avatar_hair_front", "color",
		SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b")))
	var hair_bright = SettingsManager.get_setting("avatar_hair_front", "brightness",
		SettingsManager.get_setting("avatar_hair", "brightness", 0.0))
	var hair_style  = SettingsManager.get_setting("avatar_hair_front", "style",
		SettingsManager.get_setting("avatar_hair", "style", "hair1"))

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
		# New: both layers carry same values by default
		"hair_front": { "color": hair_color, "brightness": hair_bright, "style": hair_style },
		"hair_back":  { "color": hair_color, "brightness": hair_bright, "style": hair_style },
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
	
func get_avatar_data_string() -> String:
	var settings = _get_current_avatar_settings()

	# Build reverse lookups
	var hair_map = {}
	for i in avatar_hair_regions.keys().size():
		hair_map[avatar_hair_regions.keys()[i]] = i
	var body_map = {}
	for i in avatar_body_regions.keys().size():
		body_map[avatar_body_regions.keys()[i]] = i
	var eyes_map = {}
	for i in avatar_eyes_regions.keys().size():
		eyes_map[avatar_eyes_regions.keys()[i]] = i
	var mouth_map = {}
	for i in avatar_mouth_regions.keys().size():
		mouth_map[avatar_mouth_regions.keys()[i]] = i
	var clothing_map = {}
	for i in avatar_clothing_regions.keys().size():
		clothing_map[avatar_clothing_regions.keys()[i]] = i
	var backdrop_map = ["Plain", "Pattern 1", "Pattern 2", "Pattern 3", "Pattern 4", "Pattern 5", "Pattern 6", "Pattern 7", "Pattern 8", "Pattern 9"]

	var parts = []
	# Body
	var body_style_name = settings["body"]["head_style"]
	parts.append("body,%d" % body_map.get(body_style_name, 0))
	var body_c = settings["body"]["color"]
	parts.append("body_color,%.6f,%.6f,%.6f" % [body_c.r, body_c.g, body_c.b])

	# Hair (serialize from FRONT layer for backwards-compat)
	var hair_style_name = settings["hair_front"]["style"]
	parts.append("hair,%d" % hair_map.get(hair_style_name, 0))
	var hair_c = settings["hair_front"]["color"]
	parts.append("hair_color,%.6f,%.6f,%.6f" % [hair_c.r, hair_c.g, hair_c.b])

	# Face
	var eyes_style_name = settings["face"]["eyes"]
	parts.append("eyes,%d" % eyes_map.get(eyes_style_name, 0))
	var mouth_style_name = settings["face"]["mouth"]
	parts.append("mouth,%d" % mouth_map.get(mouth_style_name, 0))

	# Clothing
	var clothing_style_name = settings["clothing"]["style"]
	parts.append("clothes,%d" % clothing_map.get(clothing_style_name, 0))
	var clothes_c = settings["clothing"]["color"]
	parts.append("clothes_color,%.6f,%.6f,%.6f" % [clothes_c.r, clothes_c.g, clothes_c.b])

	# Background Color
	var bg_c = settings["background"]["color"]
	parts.append("bg_color,%.6f,%.6f,%.6f" % [bg_c.r, bg_c.g, bg_c.b])

	# Backdrop Style
	var bg_style_name = settings["background"]["style"]
	var backdrop_index = backdrop_map.find(bg_style_name)
	if backdrop_index == -1:
		backdrop_index = 0
	parts.append("backdrop,%d" % backdrop_index)
	
	return "|".join(parts)

func set_selected(is_selected: bool):
	if is_selected:
		add_theme_stylebox_override("normal", _selection_stylebox)
	else:
		remove_theme_stylebox_override("normal")

func _center_and_scale_sprites():
	var center_pos: Vector2 = size / 2.0
	
	# Background Scaling
	var base_bg_size = 128.0
	var bg_scale_x = size.x / base_bg_size
	var bg_scale_y = size.y / base_bg_size
	var bg_scale_factor = max(bg_scale_x, bg_scale_y)

	avatar_background.position = center_pos
	avatar_background.scale = Vector2(bg_scale_factor, bg_scale_factor)

	# Character Scaling
	var base_character_size = 64.0
	var char_scale_factor = size.y / base_character_size

	# Scale standard sprites (based on 64x64)
	for sprite in [ avatar_base_body, avatar_eyes, avatar_mouth, \
					avatar_clothing, avatar_head_accessories, avatar_face_accessories ]:
		sprite.centered = true
		sprite.position = center_pos
		sprite.scale = Vector2(char_scale_factor, char_scale_factor)

	# Scale high-res hair sprites separately (based on 2000x2000)
	var base_hair_size = 2000.0
	var hair_scale_factor = size.y / base_hair_size
	for hair_sprite in [avatar_hair_back, avatar_hair_front]:
		hair_sprite.centered = true
		hair_sprite.position = center_pos
		hair_sprite.scale = Vector2(hair_scale_factor, hair_scale_factor)

func _apply_layer_order():
	# Use absolute Z for predictable ordering
	for n in [avatar_face_accessories, avatar_head_accessories, avatar_clothing, avatar_hair_front,
			  avatar_mouth, avatar_eyes, avatar_base_body, avatar_hair_back, avatar_background]:
		if n:
			n.z_as_relative = false
	if color_rect:
		color_rect.z_as_relative = false

	# Top -> Bottom
	if avatar_face_accessories: avatar_face_accessories.z_index = Z_FACE_ACCESSORIES
	if avatar_head_accessories: avatar_head_accessories.z_index = Z_HEAD_ACCESSORIES
	if avatar_clothing:         avatar_clothing.z_index         = Z_CLOTHING
	if avatar_hair_front:       avatar_hair_front.z_index       = Z_HAIR_FRONT
	if avatar_mouth:            avatar_mouth.z_index            = Z_MOUTH
	if avatar_eyes:             avatar_eyes.z_index             = Z_EYES
	if avatar_base_body:        avatar_base_body.z_index        = Z_BASE_BODY
	if avatar_hair_back:        avatar_hair_back.z_index        = Z_HAIR_BACK
	if avatar_background:       avatar_background.z_index       = Z_BACKGROUND
	if color_rect:              color_rect.z_index              = Z_BACKGROUND  # same layer as background

func calculate_final_color(base_color: Color, brightness_slider_val: float) -> Color:
	if brightness_slider_val < 0.0:
		var t = brightness_slider_val + 1.0
		var new_v = lerp(0.3, base_color.v, t)
		return Color.from_hsv(base_color.h, base_color.s, new_v)
	elif brightness_slider_val > 0.0:
		var h_val = base_color.h
		var s_val = base_color.s * (1.0 - brightness_slider_val)
		var v_val = base_color.v + (1.0 - base_color.v) * brightness_slider_val
		return Color.from_hsv(h_val, s_val, v_val)
	else:
		return base_color
