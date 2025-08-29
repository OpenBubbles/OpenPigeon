extends Node

var games = {
	"checkers": "res://checkers/checkers.tscn",
	"connect": "res://connect/connect.tscn",
	"basketball": "res://basketball/basketball.tscn",
	"sea": "res://battleship/battleship.tscn",
	"darts": "res://darts/DartsScene.tscn",
	"beer": "res://pong/cuppong.tscn",
	"archery": "res://archery/archery.tscn",
}

func _ready() -> void:
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.connect("switch_game", func(game: String):
			get_tree().call_deferred("change_scene_to_file", games[game])
		)
	else:
		print("Error: App not connected")
