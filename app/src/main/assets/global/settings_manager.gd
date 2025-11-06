# settings_manager.gd
extends Node
class_name GlobalSettings

@warning_ignore("unused_signal")
signal avatar_changed

const SETTINGS_FILE_PATH = "user://settings.cfg"
var config = ConfigFile.new()

func _first_key(d: Dictionary, fallback: String) -> String:
	for k in d.keys():
		return String(k)
	return fallback

func _ready():
	load_settings()

func load_settings():
	var error = config.load(SETTINGS_FILE_PATH)
	if error != OK:
		print("Settings file not found or corrupted, creating new one.")

func save_settings():
	var error = config.save(SETTINGS_FILE_PATH)
	if error != OK:
		print("Failed to save settings to ", SETTINGS_FILE_PATH, ". Error: ", error)

func set_setting(category: String, key: String, value):
	config.set_value(category, key, value)
	save_settings()

func get_setting(category: String, key: String, default_value = null):
	return config.get_value(category, key, default_value)

func get_game_name_from_path(scene_path: String) -> String:
	var file_name = scene_path.get_file()
	return file_name.get_basename()

func ensure_avatar_defaults() -> void:
	var AT = preload("res://global/avatar_textures/avatar_thumbnail.gd")

	# Background style
	var bg_style_val: String = str(get_setting("avatar_background", "style", ""))
	if bg_style_val == "":
		# If you want the first patterned background instead, use:
		# set_setting("avatar_background", "style", _first_key(AT.avatar_background_regions, "Pattern 1"))
		set_setting("avatar_background", "style", "Plain")

	# Face: eyes, mouth
	var eyes_val: String = str(get_setting("avatar_face", "eyes", ""))
	if eyes_val == "":
		set_setting("avatar_face", "eyes", _first_key(AT.avatar_eyes_regions, "eyes1"))

	var mouth_val: String = str(get_setting("avatar_face", "mouth", ""))
	if mouth_val == "":
		set_setting("avatar_face", "mouth", _first_key(AT.avatar_mouth_regions, "mouth1"))

	# Fshape (head style)
	var fshape_val: String = str(get_setting("avatar_fshape", "head_style", ""))
	if fshape_val == "":
		set_setting("avatar_fshape", "head_style", _first_key(AT.avatar_fshape_regions, "Default"))

	# Hair (both layers + legacy)
	var hair_style_val: String = str(get_setting("avatar_hair_front", "style",
		get_setting("avatar_hair", "style", "")))
	if hair_style_val == "":
		var first_hair: String = _first_key(AT.avatar_hair_regions, "hair1")
		set_setting("avatar_hair_front", "style", first_hair)
		set_setting("avatar_hair_back", "style", first_hair)
		set_setting("avatar_hair", "style", first_hair) # legacy key for safety

	# Clothing style
	var clothing_val: String = str(get_setting("avatar_clothing", "style", ""))
	if clothing_val == "":
		set_setting("avatar_clothing", "style", _first_key(AT.avatar_clothing_regions, "clothing1"))

	# Accessories (head/face)
	var head_acc: String = str(get_setting("avatar_accessories", "head_style", ""))
	if head_acc == "":
		set_setting("avatar_accessories", "head_style", _first_key(AT.avatar_head_accessories_regions, "None"))

	var face_acc: String = str(get_setting("avatar_accessories", "face_style", ""))
	if face_acc == "":
		set_setting("avatar_accessories", "face_style", _first_key(AT.avatar_face_accessories_regions, "None"))
