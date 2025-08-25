# settings_manager.gd
extends Node
class_name GlobalSettings

@warning_ignore("unused_signal")
signal avatar_changed

const SETTINGS_FILE_PATH = "user://settings.cfg"
var config = ConfigFile.new()

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
