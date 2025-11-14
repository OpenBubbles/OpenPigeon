extends Control

var games = {
	"checkers": "res://checkers/checkers.tscn",
	"connect": "res://connect/connect.tscn",
	"basketball": "res://basketball/basketball.tscn",
	"sea": "res://battleship/battleship.tscn",
	"darts": "res://darts/DartsScene.tscn",
	"beer": "res://pong/cuppong.tscn",
	"archery": "res://archery/archery.tscn",
	"reversi": "res://reversi/reversi.tscn",
	"fill": "res://fill/fill.tscn",
	"mancala": "res://mancala/mancala.tscn",
	"dots": "res://dots/dots.tscn",
	"knock": "res://knockout/knockout.tscn",
	"questions": "res://questions/questions.tscn",
	"paintball": "res://paintball/paintball.tscn",
	"renju": "res://gomoku/gomoku.tscn",
	"anagrams": "res://anagrams/anagrams.tscn",
	"bites": "res://bites/bites.tscn",
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if name == "GamePicker":
		var appPlugin := Engine.get_singleton("AppPlugin")
		if appPlugin:
			print("Game picker loaded..")
			get_tree().call_deferred("change_scene_to_file", games[appPlugin.getGameName()])
		else:
			print("Error: App not connected")

func _pressed() -> void:
	if name == "CheckersButton":
		get_tree().call_deferred("change_scene_to_file", games["checkers"])
	elif name == "ConnectFourButton":
		get_tree().call_deferred("change_scene_to_file", games["connect"])
	elif name == "BasketballButton":
		get_tree().call_deferred("change_scene_to_file", games["basketball"])
	elif name == "DartsButton":
		get_tree().call_deferred("change_scene_to_file", games["darts"])
	elif name == "BeerButton":
		get_tree().call_deferred("change_scene_to_file", games["beer"])
	elif name == "ArcheryButton":
		get_tree().call_deferred("change_scene_to_file", games["archery"])
	elif name == "ReversiButton":
		get_tree().call_deferred("change_scene_to_file", games["reversi"])
	elif name == "FillerButton":
		get_tree().call_deferred("change_scene_to_file", games["fill"])
	elif name == "MancalaButton":
		get_tree().call_deferred("change_scene_to_file", games["mancala"])
	elif name == "QuestionsButton":
		get_tree().call_deferred("change_scene_to_file", games["questions"])
