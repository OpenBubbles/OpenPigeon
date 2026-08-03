# AvatarThumbnail.gd
extends TextureButton
class_name AvatarThumbnail

@export var is_display_only: bool = false
@export var controlled_by_data: bool = false
@onready var sub_viewport: SubViewport = %SubViewport
@onready var color_rect: ColorRect = %SubViewport/PillMask/ColorRect
@onready var avatar_background: Sprite2D = %SubViewport/PillMask/AvatarBackground
@onready var avatar_hair_back: Sprite2D = %SubViewport/Foreground/AvatarHairBack
@onready var avatar_torso: Sprite2D = %SubViewport/Foreground/AvatarTorso
@onready var avatar_clothing: Sprite2D = %SubViewport/Foreground/AvatarClothing
@onready var avatar_clothing_details: Sprite2D = %SubViewport/Foreground/AvatarClothingDetails
@onready var avatar_base_fshape: Sprite2D = %SubViewport/Foreground/AvatarBaseFace
@onready var avatar_eyes: Sprite2D = %SubViewport/Foreground/AvatarEyes
@onready var avatar_mouth: Sprite2D = %SubViewport/Foreground/AvatarMouth
@onready var avatar_hair_front: Sprite2D = %SubViewport/Foreground/AvatarHairFront     # front layer
@onready var avatar_head_accessories: Sprite2D = %SubViewport/Foreground/AvatarHeadAccessories
@onready var avatar_face_accessories: Sprite2D = %SubViewport/Foreground/AvatarFaceAccessories

# Top
const Z_FACE_ACCESSORIES := 80
const Z_HEAD_ACCESSORIES := 70

const Z_HAIR_FRONT       := 60
const Z_MOUTH            := 50
const Z_EYES             := 40
const Z_BASE_FSHAPE      := 30
const Z_CLOTHING_DETAILS := 25
const Z_CLOTHING         := 20
const Z_TORSO            := 15
const Z_HAIR_BACK        := 10
const Z_BACKGROUND       := 0
# Bottom

const AVATAR_PART_SIZE := 256
const HEAD_ACCESSORY_CELL_SIZE := 384

@export var AVATAR_FG_SCALE_RATIO := 1.1  # >1.0 makes the avatar larger inside the background
@export var AVATAR_FG_BOTTOM_PAD  := -12   # +down / -up in pixels

const TEMP_DISABLE_AVATAR_RENDER := false
# ----------------------------------------------------------

const avatar_background_regions := {
	"Pattern 1": Rect2(0, 0, 128, 128),   "Pattern 2": Rect2(128, 0, 128, 128),
	"Pattern 3": Rect2(256, 0, 128, 128), "Pattern 4": Rect2(384, 0, 128, 128),
	"Pattern 5": Rect2(0, 128, 128, 128), "Pattern 6": Rect2(128, 128, 128, 128),
	"Pattern 7": Rect2(256, 128, 128, 128), "Pattern 8": Rect2(384, 128, 128, 128),
	"Pattern 9": Rect2(0, 256, 128, 128)
}
const avatar_torso_regions := {
	"Default": Rect2(0, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE)
}

const avatar_fshape_regions := {
	# First row (y = 0)
	"Default": Rect2(0, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),  # alias of fshape1 so the first option works
	"fshape1":   Rect2(0, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"fshape2":   Rect2(AVATAR_PART_SIZE, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"fshape3":   Rect2(AVATAR_PART_SIZE * 2, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"fshape4":   Rect2(AVATAR_PART_SIZE * 3, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"fshape5":   Rect2(AVATAR_PART_SIZE * 4, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),

	# Second row (y = AVATAR_PART_SIZE)
	"fshape6":   Rect2(0, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"fshape7":   Rect2(AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
}
# Shared regions for BOTH hair layers (front/back)
const avatar_hair_regions := {
	"hair1": Rect2(0, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),   "hair2": Rect2(AVATAR_PART_SIZE, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"hair3": Rect2(AVATAR_PART_SIZE * 2, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"hair4": Rect2(AVATAR_PART_SIZE * 3, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"hair5": Rect2(AVATAR_PART_SIZE * 4, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"hair6": Rect2(0, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"hair7": Rect2(AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"hair8": Rect2(AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"hair9": Rect2(AVATAR_PART_SIZE * 3, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"hair10": Rect2(AVATAR_PART_SIZE * 4, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"hair11": Rect2(0, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"hair12": Rect2(AVATAR_PART_SIZE, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"hair13": Rect2(AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"hair14": Rect2(AVATAR_PART_SIZE * 3, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"hair15": Rect2(AVATAR_PART_SIZE * 4, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE)
}
const avatar_eyes_regions  := { "eyes1": Rect2(0, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),   "eyes2": Rect2(AVATAR_PART_SIZE, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"eyes3": Rect2(AVATAR_PART_SIZE * 2, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"eyes4": Rect2(AVATAR_PART_SIZE * 3, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"eyes5": Rect2(AVATAR_PART_SIZE * 4, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"eyes6": Rect2(0, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"eyes7": Rect2(AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"eyes8": Rect2(AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"eyes9": Rect2(AVATAR_PART_SIZE * 3, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"eyes10": Rect2(AVATAR_PART_SIZE * 4, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"eyes11": Rect2(0, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"eyes12": Rect2(AVATAR_PART_SIZE, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"eyes13": Rect2(AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE) }
	
const avatar_mouth_regions := { "mouth1": Rect2(0, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),   "mouth2": Rect2(AVATAR_PART_SIZE, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"mouth3": Rect2(AVATAR_PART_SIZE * 2, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"mouth4": Rect2(AVATAR_PART_SIZE * 3, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"mouth5": Rect2(AVATAR_PART_SIZE * 4, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"mouth6": Rect2(0, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"mouth7": Rect2(AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"mouth8": Rect2(AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"mouth9": Rect2(AVATAR_PART_SIZE * 3, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"mouth10": Rect2(AVATAR_PART_SIZE * 4, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"mouth11": Rect2(0, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"mouth12": Rect2(AVATAR_PART_SIZE, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"mouth13": Rect2(AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"mouth14": Rect2(AVATAR_PART_SIZE * 3, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"mouth15": Rect2(AVATAR_PART_SIZE * 4, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),"mouth16": Rect2(0, AVATAR_PART_SIZE * 3, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"mouth17": Rect2(AVATAR_PART_SIZE, AVATAR_PART_SIZE * 3, AVATAR_PART_SIZE, AVATAR_PART_SIZE) }
	
const MOUTH_WITH_FACIAL_HAIR := {
	"mouth13": true, "mouth14": true, "mouth15": true, "mouth16": true, "mouth17": true
}
	
const avatar_clothing_regions := { "clothing1": Rect2(0, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE), "clothing2": Rect2(AVATAR_PART_SIZE, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE), "clothing3": Rect2(AVATAR_PART_SIZE * 2, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE)}

const FACE_ACCESSORY_COUNT := 14

const avatar_face_accessories_regions := {
	# Row 1
	"face_1": Rect2(0, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"face_2": Rect2(AVATAR_PART_SIZE, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"face_3": Rect2(AVATAR_PART_SIZE * 2, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"face_4": Rect2(AVATAR_PART_SIZE * 3, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"face_5": Rect2(AVATAR_PART_SIZE * 4, 0, AVATAR_PART_SIZE, AVATAR_PART_SIZE),

	# Row 2
	"face_6": Rect2(0, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"face_7": Rect2(AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"face_8": Rect2(AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"face_9": Rect2(AVATAR_PART_SIZE * 3, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"face_10": Rect2(AVATAR_PART_SIZE * 4, AVATAR_PART_SIZE, AVATAR_PART_SIZE, AVATAR_PART_SIZE),

	# Row 3
	"face_11": Rect2(0, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"face_12": Rect2(AVATAR_PART_SIZE, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"face_13": Rect2(AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE),
	"face_14": Rect2(AVATAR_PART_SIZE * 3, AVATAR_PART_SIZE * 2, AVATAR_PART_SIZE, AVATAR_PART_SIZE)
}

var _selection_stylebox: StyleBox = null

func _ready():
	print("AvatarThumbnail ready: '", self.name, "'. is_display_only: ", is_display_only, ", controlled_by_data: ", controlled_by_data)
	
	if SettingsManager and SettingsManager.has_method("ensure_avatar_defaults"):
		SettingsManager.ensure_avatar_defaults()

	var stylebox_flat = StyleBoxFlat.new()
	stylebox_flat.bg_color = Color(0,0,0,0)
	stylebox_flat.border_width_left = 3; stylebox_flat.border_width_top = 3; stylebox_flat.border_width_right = 3; stylebox_flat.border_width_bottom = 3
	stylebox_flat.border_color = Color(0.2, 0.8, 0.2, 0.9)
	stylebox_flat.corner_radius_top_left = 5; stylebox_flat.corner_radius_top_right = 5; stylebox_flat.corner_radius_bottom_left = 5; stylebox_flat.corner_radius_bottom_right = 5
	_selection_stylebox = stylebox_flat

	if is_display_only:
		self.disabled = true

	if TEMP_DISABLE_AVATAR_RENDER:
		visible = false
		disabled = true
		return

	if controlled_by_data:
		pass
	else:
		if SettingsManager:
			SettingsManager.avatar_changed.connect(update_display_from_settings)
		call_deferred("update_display_from_settings")


func update_preview(base_settings: Dictionary, category: String, key: String, override_value):
	if TEMP_DISABLE_AVATAR_RENDER:
		return
	var temp_settings = base_settings.duplicate(true)
	if not temp_settings.has(category):
		temp_settings[category] = {}
	temp_settings[category][key] = override_value
	_draw_avatar(temp_settings)

func update_avatar_from_data(avatar_data: Dictionary):
	print("SUCCESS: '", self.name, "' is updating from this external data: ", avatar_data)
	if TEMP_DISABLE_AVATAR_RENDER:
		return

	var hair_color = avatar_data.get("hair_color", Color.BLACK)
	var hair_brightness = avatar_data.get("hair_brightness", 0.0)
	var hair_style = avatar_data.get("hair_style", "hair1")
	var face_acc_style := str(avatar_data.get("face_acc_style", "face_1"))
	if face_acc_style == "None" or not avatar_face_accessories_regions.has(face_acc_style):
		face_acc_style = "face_1"

	var settings = {
		"background": {"color": avatar_data.get("bg_color", Color.WHITE), "brightness": avatar_data.get("bg_brightness", 0.0), "style": avatar_data.get("bg_style", "Plain")},
		"fshape": {"color": avatar_data.get("fshape_color", Color.WHITE), "brightness": avatar_data.get("fshape_brightness", 0.0), "head_style": avatar_data.get("fshape_style", "Default")},
		"hair_front": {"color": hair_color, "brightness": hair_brightness, "style": hair_style},
		"hair_back": {"color": hair_color, "brightness": hair_brightness, "style": hair_style},
		"face": {"eyes": avatar_data.get("eyes_style", "eyes1"), "mouth": avatar_data.get("mouth_style", "mouth1")},
		"clothing": {"color": avatar_data.get("clothing_color", Color.WHITE), "brightness": avatar_data.get("clothing_brightness", 0.0), "style": avatar_data.get("clothing_style", "clothing1")},
		"accessories": {"color": avatar_data.get("acc_color", Color.WHITE), "brightness": avatar_data.get("acc_brightness", 0.0), "head_style": avatar_data.get("head_acc_style", "hat_0"), "face_style": face_acc_style}
	}

	_draw_avatar(settings)

func update_display_from_settings():
	if TEMP_DISABLE_AVATAR_RENDER:
		return
	var current_settings = _get_current_avatar_settings()
	_draw_avatar(current_settings)


func _draw_avatar(settings: Dictionary) -> void:
	if TEMP_DISABLE_AVATAR_RENDER:
		return

	var bg_color = settings["background"]["color"]
	color_rect.color = calculate_final_color(bg_color, settings["background"]["brightness"])
	var bg_style := str(settings["background"]["style"])

	if bg_style == "Plain" or not avatar_background_regions.has(bg_style):
		color_rect.visible = true
		avatar_background.visible = false
	else:
		color_rect.visible = false
		avatar_background.visible = true
		var atlas := AtlasTexture.new()
		atlas.atlas = AvatarResources.AVATAR_BG_MAP_PATH
		atlas.region = avatar_background_regions[bg_style]
		avatar_background.texture = atlas

	var tone_color = settings["fshape"]["color"]
	avatar_base_fshape.texture = AvatarResources.AVATAR_FSHAPE_MAP_PATH
	avatar_base_fshape.self_modulate = calculate_final_color(tone_color, settings["fshape"]["brightness"])
	var fshape_style := str(settings["fshape"]["head_style"])
	if not avatar_fshape_regions.has(fshape_style):
		fshape_style = "Default"
	avatar_base_fshape.region_enabled = true
	avatar_base_fshape.region_rect = avatar_fshape_regions[fshape_style]

	if is_instance_valid(avatar_torso):
		avatar_torso.texture = AvatarResources.AVATAR_TORSO_MAP_PATH
		avatar_torso.self_modulate = avatar_base_fshape.self_modulate
		avatar_torso.region_enabled = true
		avatar_torso.region_rect = avatar_torso_regions["Default"]

	var hair_back_color = settings["hair_back"]["color"]
	avatar_hair_back.texture = AvatarResources.AVATAR_HAIR_BACK_MAP_PATH
	avatar_hair_back.self_modulate = calculate_final_color(hair_back_color, settings["hair_back"]["brightness"])
	var hair_style_back := str(settings["hair_back"]["style"])
	if not avatar_hair_regions.has(hair_style_back):
		hair_style_back = "hair1"
	avatar_hair_back.region_enabled = true
	avatar_hair_back.region_rect = avatar_hair_regions[hair_style_back]

	var hair_front_color = settings["hair_front"]["color"]
	var hair_front_final = calculate_final_color(hair_front_color, settings["hair_front"]["brightness"])
	avatar_hair_front.texture = AvatarResources.AVATAR_HAIR_FRONT_MAP_PATH
	avatar_hair_front.self_modulate = hair_front_final
	var hair_style_front := str(settings["hair_front"]["style"])
	if not avatar_hair_regions.has(hair_style_front):
		hair_style_front = "hair1"
	avatar_hair_front.region_enabled = true
	avatar_hair_front.region_rect = avatar_hair_regions[hair_style_front]

	avatar_eyes.texture = AvatarResources.AVATAR_EYES_MAP_PATH
	avatar_mouth.texture = AvatarResources.AVATAR_MOUTH_MAP_PATH
	avatar_face_accessories.texture = AvatarResources.AVATAR_FACE_ACCESSORIES_MAP_PATH

	var eyes_style := str(settings["face"]["eyes"])
	if not avatar_eyes_regions.has(eyes_style):
		eyes_style = "eyes1"
	avatar_eyes.region_enabled = true
	avatar_eyes.region_rect = avatar_eyes_regions[eyes_style]

	var mouth_style := str(settings["face"]["mouth"])
	if not avatar_mouth_regions.has(mouth_style):
		mouth_style = "mouth1"
	avatar_mouth.region_enabled = true
	avatar_mouth.region_rect = avatar_mouth_regions[mouth_style]
	avatar_mouth.self_modulate = hair_front_final if MOUTH_WITH_FACIAL_HAIR.has(mouth_style) else Color.WHITE

	var face_acc_style := str(settings["accessories"].get("face_style", "face_1"))
	if face_acc_style == "None" or not avatar_face_accessories_regions.has(face_acc_style):
		face_acc_style = "face_1"
	avatar_face_accessories.modulate = Color.WHITE
	avatar_face_accessories.self_modulate = Color.WHITE
	avatar_face_accessories.offset = Vector2.ZERO
	avatar_face_accessories.region_filter_clip_enabled = true
	avatar_face_accessories.region_enabled = true
	avatar_face_accessories.region_rect = avatar_face_accessories_regions[face_acc_style]
	avatar_face_accessories.visible = true

	var clothing_color = settings["clothing"]["color"]
	avatar_clothing.texture = AvatarResources.AVATAR_CLOTHING_MAP_PATH
	avatar_clothing.self_modulate = calculate_final_color(clothing_color, settings["clothing"]["brightness"])
	var clothing_style := str(settings["clothing"]["style"])
	if not avatar_clothing_regions.has(clothing_style):
		clothing_style = "clothing1"
	avatar_clothing.region_enabled = true
	avatar_clothing.region_rect = avatar_clothing_regions[clothing_style]

	avatar_clothing_details.texture = AvatarResources.AVATAR_CLOTHING_DETAILS_MAP_PATH
	avatar_clothing_details.self_modulate = Color.WHITE
	avatar_clothing_details.region_enabled = true
	avatar_clothing_details.region_rect = avatar_clothing_regions[clothing_style]

	avatar_head_accessories.texture = AvatarResources.AVATAR_HEAD_ACCESSORIES_MAP_PATH
	avatar_head_accessories.self_modulate = Color.WHITE
	avatar_head_accessories.region_filter_clip_enabled = true
	avatar_head_accessories.offset = Vector2(0, -64)

	var head_acc_style := str(settings["accessories"]["head_style"])
	var head_acc_index := 1 if head_acc_style == "Hat1" else 0

	if head_acc_style.begins_with("hat_"):
		var head_acc_number := head_acc_style.trim_prefix("hat_")
		if head_acc_number.is_valid_int():
			head_acc_index = clampi(head_acc_number.to_int(), 0, 12)
	elif head_acc_style.is_valid_int():
		head_acc_index = clampi(head_acc_style.to_int(), 0, 12)

	if head_acc_index > 0:
		avatar_head_accessories.region_enabled = true
		avatar_head_accessories.region_rect = Rect2((head_acc_index % 5) * HEAD_ACCESSORY_CELL_SIZE, int(head_acc_index / 5) * HEAD_ACCESSORY_CELL_SIZE, HEAD_ACCESSORY_CELL_SIZE, HEAD_ACCESSORY_CELL_SIZE)
		avatar_head_accessories.visible = true
	else:
		avatar_head_accessories.region_enabled = false
		avatar_head_accessories.visible = false

	_center_and_scale_sprites()
	_apply_layer_order()

func _get_current_avatar_settings() -> Dictionary:
	var hair_color = SettingsManager.get_setting("avatar_hair_front", "color", SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b")))
	var hair_bright = SettingsManager.get_setting("avatar_hair_front", "brightness", SettingsManager.get_setting("avatar_hair", "brightness", 0.0))
	var hair_style = SettingsManager.get_setting("avatar_hair_front", "style", SettingsManager.get_setting("avatar_hair", "style", "hair1"))
	var face_style := str(SettingsManager.get_setting("avatar_accessories", "face_style", "face_1"))
	if face_style == "None" or not avatar_face_accessories_regions.has(face_style):
		face_style = "face_1"

	return {
		"background": {"color": SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89")), "brightness": SettingsManager.get_setting("avatar_background", "brightness", 0.0), "style": SettingsManager.get_setting("avatar_background", "style", "Plain")},
		"fshape": {"color": SettingsManager.get_setting("avatar_fshape", "color", Color("#e0ac69")), "brightness": SettingsManager.get_setting("avatar_fshape", "brightness", 0.0), "head_style": SettingsManager.get_setting("avatar_fshape", "head_style", "Default")},
		"hair_front": {"color": hair_color, "brightness": hair_bright, "style": hair_style},
		"hair_back": {"color": hair_color, "brightness": hair_bright, "style": hair_style},
		"face": {"eyes": SettingsManager.get_setting("avatar_face", "eyes", "eyes1"), "mouth": SettingsManager.get_setting("avatar_face", "mouth", "mouth1")},
		"clothing": {"color": SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c")), "brightness": SettingsManager.get_setting("avatar_clothing", "brightness", 0.0), "style": SettingsManager.get_setting("avatar_clothing", "style", "clothing1")},
		"accessories": {"color": SettingsManager.get_setting("avatar_accessories", "color", Color.WHITE), "brightness": SettingsManager.get_setting("avatar_accessories", "brightness", 0.0), "head_style": SettingsManager.get_setting("avatar_accessories", "head_style", "hat_0"), "face_style": face_style}
	}

func get_avatar_data_string() -> String:
	var settings = _get_current_avatar_settings()
	var hair_map = {}
	var fshape_map = {}
	var eyes_map = {}
	var mouth_map = {}
	var clothing_map = {}

	for i in avatar_hair_regions.keys().size():
		hair_map[avatar_hair_regions.keys()[i]] = i
	for i in avatar_fshape_regions.keys().size():
		fshape_map[avatar_fshape_regions.keys()[i]] = i
	for i in avatar_eyes_regions.keys().size():
		eyes_map[avatar_eyes_regions.keys()[i]] = i
	for i in avatar_mouth_regions.keys().size():
		mouth_map[avatar_mouth_regions.keys()[i]] = i
	for i in avatar_clothing_regions.keys().size():
		clothing_map[avatar_clothing_regions.keys()[i]] = i

	var backdrop_map = ["Plain", "Pattern 1", "Pattern 2", "Pattern 3", "Pattern 4", "Pattern 5", "Pattern 6", "Pattern 7", "Pattern 8", "Pattern 9"]
	var parts = []
	var fshape_style_name = settings["fshape"]["head_style"]
	var fshape_c = settings["fshape"]["color"]
	parts.append("fshape,%d" % fshape_map.get(fshape_style_name, 0))
	parts.append("fshape_color,%.6f,%.6f,%.6f" % [fshape_c.r, fshape_c.g, fshape_c.b])
	parts.append("body,%d" % fshape_map.get(fshape_style_name, 0))
	parts.append("body_color,%.6f,%.6f,%.6f" % [fshape_c.r, fshape_c.g, fshape_c.b])

	var hair_style_name = settings["hair_front"]["style"]
	var hair_c = settings["hair_front"]["color"]
	parts.append("hair,%d" % hair_map.get(hair_style_name, 0))
	parts.append("hair_color,%.6f,%.6f,%.6f" % [hair_c.r, hair_c.g, hair_c.b])

	parts.append("eyes,%d" % eyes_map.get(settings["face"]["eyes"], 0))
	parts.append("mouth,%d" % mouth_map.get(settings["face"]["mouth"], 0))

	var clothing_style_name = settings["clothing"]["style"]
	var clothes_c = settings["clothing"]["color"]
	parts.append("clothes,%d" % clothing_map.get(clothing_style_name, 0))
	parts.append("clothes_color,%.6f,%.6f,%.6f" % [clothes_c.r, clothes_c.g, clothes_c.b])

	var bg_c = settings["background"]["color"]
	parts.append("bg_color,%.6f,%.6f,%.6f" % [bg_c.r, bg_c.g, bg_c.b])
	parts.append("backdrop,%d" % maxi(backdrop_map.find(settings["background"]["style"]), 0))

	var head_acc_style := str(settings["accessories"]["head_style"])
	var head_acc_index := 1 if head_acc_style == "Hat1" else 0
	if head_acc_style.begins_with("hat_"):
		var head_acc_number := head_acc_style.trim_prefix("hat_")
		if head_acc_number.is_valid_int():
			head_acc_index = clampi(head_acc_number.to_int(), 0, 12)
	elif head_acc_style.is_valid_int():
		head_acc_index = clampi(head_acc_style.to_int(), 0, 12)

	var face_acc_style := str(settings["accessories"]["face_style"])
	var face_acc_index := 0
	if face_acc_style.begins_with("face_"):
		var face_acc_number := face_acc_style.trim_prefix("face_")
		if face_acc_number.is_valid_int():
			face_acc_index = clampi(face_acc_number.to_int() - 1, 0, FACE_ACCESSORY_COUNT)

	parts.append("acc,%d" % head_acc_index)
	parts.append("glasses,%d" % face_acc_index)
	return "|".join(parts)

func set_selected(is_selected: bool):
	if is_selected:
		add_theme_stylebox_override("normal", _selection_stylebox)
	else:
		remove_theme_stylebox_override("normal")

func _center_and_scale_sprites():
	var center_x: float = sub_viewport.size.x * 0.5
	var h: float = 90.0
	var top_offset: float = max(0.0, float(sub_viewport.size.y) - h)
	var base_bg_size := 128.0
	var bg_scale_x := sub_viewport.size.x / base_bg_size
	var bg_scale_y := h / base_bg_size
	var bg_scale_factor : float = max(bg_scale_x, bg_scale_y)

	avatar_background.centered = true
	avatar_background.position = Vector2(center_x, h * 0.5)
	avatar_background.scale = Vector2(bg_scale_factor, bg_scale_factor)

	var s256 := (h / 256.0) * AVATAR_FG_SCALE_RATIO
	var visual_h := h * AVATAR_FG_SCALE_RATIO
	var base_y := top_offset + h - (visual_h * 0.5) - AVATAR_FG_BOTTOM_PAD

	for sprite in [avatar_hair_back, avatar_base_fshape, avatar_torso, avatar_hair_front, avatar_eyes, avatar_mouth, avatar_clothing, avatar_clothing_details, avatar_head_accessories, avatar_face_accessories]:
		if sprite:
			sprite.centered = true
			sprite.position = Vector2(center_x, base_y)
			sprite.scale = Vector2(s256, s256)

func _apply_layer_order():
	# Use absolute Z for predictable ordering
	for n in [avatar_face_accessories, avatar_head_accessories, avatar_clothing, avatar_clothing_details, avatar_hair_front,
			  avatar_mouth, avatar_eyes, avatar_base_fshape, avatar_torso, avatar_hair_back, avatar_background]:
		if n:
			n.z_as_relative = false
	if color_rect:
		color_rect.z_as_relative = false

	# Top -> Bottom
	if avatar_face_accessories: avatar_face_accessories.z_index = Z_FACE_ACCESSORIES
	if avatar_head_accessories: avatar_head_accessories.z_index = Z_HEAD_ACCESSORIES
	if avatar_hair_front:       avatar_hair_front.z_index       = Z_HAIR_FRONT
	if avatar_mouth:            avatar_mouth.z_index            = Z_MOUTH
	if avatar_eyes:             avatar_eyes.z_index             = Z_EYES
	if avatar_base_fshape:      avatar_base_fshape.z_index      = Z_BASE_FSHAPE
	if avatar_clothing_details: avatar_clothing_details.z_index = Z_CLOTHING_DETAILS
	if avatar_clothing:         avatar_clothing.z_index         = Z_CLOTHING
	if avatar_torso:            avatar_torso.z_index            = Z_TORSO
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
