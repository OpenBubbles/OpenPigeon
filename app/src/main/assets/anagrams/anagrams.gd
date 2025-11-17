extends Control

@onready var intro_screen: Control = %IntroScreen
@onready var game_screen: Control = %GameScreen
@onready var score_screen: Control = %ScoreScreen
@onready var start_button: Button = %StartButton

var screens: Array[Control] = []
var current_screen: int = 0


func _ready() -> void:
	_init_screens()

	if not start_button.pressed.is_connected(_on_start_button_pressed):
		start_button.pressed.connect(_on_start_button_pressed)

	if not game_screen.time_up.is_connected(_on_game_time_up):
		game_screen.time_up.connect(_on_game_time_up)


func _init_screens() -> void:
	screens = [intro_screen, game_screen, score_screen]
	for i in screens.size():
		var node := screens[i]
		node.visible = (i == 0)
		node.position = Vector2.ZERO
	current_screen = 0


func _switch_to_screen(next: int) -> void:
	if next == current_screen:
		return

	var from_node := screens[current_screen]
	var to_node := screens[next]
	var width := size.x

	to_node.visible = true
	to_node.position = Vector2(width, 0)

	var tween := create_tween()
	tween.tween_property(
		from_node, "position",
		Vector2(-width, 0), 0.25
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	tween.parallel().tween_property(
		to_node, "position",
		Vector2.ZERO, 0.25
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished

	from_node.visible = false
	from_node.position = Vector2.ZERO
	current_screen = next


func _on_start_button_pressed() -> void:
	await _switch_to_screen(1)      # GameScreen
	game_screen.start_game()


func _on_game_time_up() -> void:
	await _switch_to_screen(2)      # ScoreScreen
