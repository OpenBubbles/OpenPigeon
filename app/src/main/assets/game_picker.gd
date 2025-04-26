extends Control

var games = {
	"checkers": "res://checkers/checkers.tscn"
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("Game picker loaded..")
		get_tree().call_deferred("change_scene_to_file", games[appPlugin.getGameName()])
	
