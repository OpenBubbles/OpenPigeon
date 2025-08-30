extends Control

# --- Preloaded Assets ---
const PieceScene := preload("res://knockout/piece.tscn")
const P1_PIECE_TEX := preload("res://knockout/bw_penguin.png")
const P2_PIECE_TEX := preload("res://knockout/gw_penguin.png")
const BLACK_PRESERVER_TEX := preload("res://knockout/life_prev_black.png")
const GRAY_PRESERVER_TEX := preload("res://knockout/life_prev_gray.png")

const RULES_POPUP_SCENE = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")
const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")

# --- UI and Game Node References ---
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var background = %Background
@onready var send_button: Button = %SendButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: ColorRect = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var win_loss_label = %WinLossLabel
@onready var rules_button = %RulesButton
@onready var settings_button = %SettingsButton
@onready var spec_label = %SpecLabel
@onready var you_label = %YouLabel
@onready var piece_container := %PieceContainer # Container for penguin pieces
@onready var left_preserver := %LeftPreserver   # TextureRect for player 1 status
@onready var right_preserver := %RightPreserver  # TextureRect for player 2 status


# --- Game State Variables ---
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
var game_settings_category: String

var game_ended = false
var game_over = false
var tween: Tween
var win_loss_state = ""
var has_connected: bool = false
var is_your_turn: bool = false
var is_my_turn: bool = false
var my_player
var my_player_id
var spectator_mode: bool = false
var avatar_key = 0
var player = 1
var sent_tween: Tween
var dot_count = 0

var pre_board_data: Array = []
var post_board_data: Array = []

# --- Godot Lifecycle & Setup ---

func _ready():
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)
	
	randomize()
	print("Knockout Scene ready!")

	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)

	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("AppPlugin Available")
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
	else:
		# Dev data for testing in the editor
		var dev_data = '{ "isYourTurn": true, "player": "1", "myPlayerId": "player1_id", "player1": "player1_id", "replay": "board:-123.16,12.25,1,187.68,0.0,0.0#-4.49,98.56,1,150.14,0.0,0.0#-128.79,126.11,1,132.96,0.0,0.0#-39.62,-31.23,1,352.37,0.0,0.0#-128.49,90.65,2,224.98,0.0,0.0#37.30,-82.72,2,130.87,0.0,0.0#52.55,-38.66,2,188.42,0.0,0.0#47.67,20.40,2,292.87,0.0,0.0"}'
		call_deferred("_set_game_data", dev_data)
	
	if is_instance_valid(send_button):
		send_button.visible = true
		send_button.pressed.connect(send_game)
	else:
		push_warning("No %SendButton in scene")
		
	if rules_button:
		rules_button.pressed.connect(on_rules_button_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)

func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color(0.08, 0.08, 0.08) if is_dark else Color("#68d4f6")
		
# --- Game Data Handling ---

func _set_game_data(new_game_data_json: String):
	var parsed = JSON.parse_string(new_game_data_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	stop_waiting_animation()

	var data: Dictionary = parsed
	is_your_turn = data.get("isYourTurn", false)
	print("INCOMING RAW DATA: ", data)
	var replay_str: String = data.get("replay", "")
	var player1_id: String = data.get("player1", "")
	var player2_id: String = data.get("player2", "")
	my_player_id = data.get("myPlayerId", "")
	var opponent_avatar_key = ""

	if my_player_id == player1_id or my_player_id == player2_id or player1_id == "":
		is_my_turn = is_your_turn
		if my_player_id == player1_id:
			player = 1
			opponent_avatar_key = "avatar2"
		elif my_player_id == player2_id:
			player = 2
			opponent_avatar_key = "avatar1"
		else: # Default case if myPlayerId is not specified
			player = 1
	else:
		spectator_mode = true
		you_label.text = ""
		is_my_turn = false # Spectators can't take turns
		spec_label.show()
		player = 1 # Default view
	
	# Set player preserver textures
	if player == 1:
		left_preserver.texture = BLACK_PRESERVER_TEX
		right_preserver.texture = GRAY_PRESERVER_TEX
	else: # Player 2
		left_preserver.texture = GRAY_PRESERVER_TEX
		right_preserver.texture = BLACK_PRESERVER_TEX

	if opponent_avatar_key != "" and data.has(opponent_avatar_key):
		var avatar_string = data[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
	
	if replay_str != "":
		print("Parsing Replay String")
		parse_replay_string(replay_str)
	else:
		print("New Game - No replay string found.")
		
	if not spectator_mode and is_my_turn and not game_over:
		print("It's your turn!")
		
	if not is_my_turn and not game_over and not spectator_mode:
		start_waiting_animation()

	game_ended = check_win()
	if game_ended:
		stop_waiting_animation()
		game_over = true

func send_game() -> void:
	print("[Send] send_game() called")
	await get_tree().process_frame

	var replay_string_to_send = "board:0#47.671448,20.402176,2,292.878235,0.000000,0.000000#52.552505,-38.661270,2,188.420181,0.000000,0.000000#37.309402,-82.729164,2,130.874207,0.000000,0.000000#-128.491425,90.655441,2,224.981232,0.000000,0.000000#-39.626404,-31.231033,1,352.372589,3.139531,146.271362#-128.793274,126.112091,1,132.961517,-1.549612,150.000000#-4.496841,98.564392,1,150.148392,1.542944,150.000000#-123.164268,12.253189,1,187.688141,-0.018010,150.000000|board:0#47.671448,20.402176,2,292.878235,0.000000,150.000000#52.552505,-38.661270,2,188.420181,90.000000,20.000000#37.309402,-82.729164,2,130.874207,180.000000,60.00000#-128.491425,90.655441,2,224.981232,270.000000,150.000000#-39.626404,-31.231033,1,352.372589,0.000000,0.000000#-128.793274,126.112091,1,132.961517,0.000000,0.000000#-4.496841,98.564392,1,150.148392,0.000000,0.000000#-123.164268,12.253189,1,187.688141,0.000000,0.000000"
	var payload: Dictionary = { "replay": replay_string_to_send }
	
	avatar_key = ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	game_ended = check_win()
	if game_ended and win_loss_state != "":
		payload["winner"] = my_player_id + "|" + win_loss_state
		
	print("[Send] PAYLOAD: ", payload)
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(JSON.stringify(payload))
	else:
		print("AppPlugin is null. Cannot send game data.")

	is_my_turn = false
	if not game_over:
		play_sent_animation()

# --- Replay Parsing & Board Setup ---

func parse_replay_string(replay: String) -> void:
	var board_strings: Array = replay.split("|")

	if board_strings.is_empty():
		push_warning("Replay string is empty.")
		return

	# Process the first (or only) board state
	if board_strings[0].begins_with("board:"):
		var board_data_string = board_strings[0].substr(6)
		pre_board_data = _parse_board_data(board_data_string)
		_setup_board_from_data(pre_board_data)

		# Check for a "shoot" action in the initial board state
		for piece_data in pre_board_data:
			var shoot_dir: float = piece_data.get("shoot_dir", 0.0)
			var power: float = piece_data.get("power", 0.0)
			if shoot_dir != 0.0 or power != 0.0:
				print("Shooting (Temp)")
				# We only need to see it once
				break

	# If there's a second board, parse and store it for later
	if board_strings.size() > 1 and board_strings[1].begins_with("board:"):
		var second_board_data_string = board_strings[1].substr(6)
		post_board_data = _parse_board_data(second_board_data_string)
		print("Stored post-move board data for future animation.")

func _parse_board_data(board_string: String) -> Array[Dictionary]:
	var parsed_pieces: Array[Dictionary] = []
	if board_string.is_empty() or board_string == "0":
		return parsed_pieces

	var piece_strings: Array = board_string.split("#")
	for piece_str in piece_strings:
		if piece_str.is_empty():
			continue

		var params: Array = piece_str.split(",")
		if params.size() == 6:
			var piece_data := {
				"pos": Vector2(params[0].to_float(), params[1].to_float()),
				"player": params[2].to_int(),
				"rotation": params[3].to_float(),
				"shoot_dir": params[4].to_float(),
				"power": params[5].to_float()
			}
			parsed_pieces.append(piece_data)
		else:
			push_warning("Invalid piece data format, expected 6 params: " + piece_str)

	return parsed_pieces

func _setup_board_from_data(board_data: Array[Dictionary]) -> void:
	# Clear any existing pieces from the container
	for child in piece_container.get_children():
		child.queue_free()

	# Instantiate new pieces based on the data
	for piece_data in board_data:
		var piece_instance = PieceScene.instantiate()
		piece_instance.position = piece_data["pos"]
		piece_instance.rotation_degrees = piece_data["rotation"]
		
		var player_num = piece_data["player"]
		# Assuming the sprite node inside piece.tscn is named "Sprite2D"
		var sprite = piece_instance.find_child("Sprite2D", true, false)
		if sprite:
			if player_num == 1:
				sprite.texture = P1_PIECE_TEX
			else: # Player 2
				sprite.texture = P2_PIECE_TEX
		else:
			push_warning("Could not find a 'Sprite2D' node in the PieceScene instance.")
			
		piece_container.add_child(piece_instance)

# --- UI Animations & State ---

func check_win() -> bool:
	# Placeholder for win condition logic
	return false

func play_sent_animation():
	if not is_instance_valid(sent_label) or game_over:
		return

	if sent_tween and sent_tween.is_running():
		sent_tween.kill()

	sent_tween = create_tween().set_parallel(false)
	sent_label.text = "Sent"
	sent_label.visible = true
	sent_label.modulate.a = 0.0
	sent_label.scale = Vector2.ONE
	sent_label.pivot_offset = sent_label.get_size() / 2.0

	sent_tween.tween_property(sent_label, "modulate:a", 1.0, 0.3)
	sent_tween.tween_interval(0.6)
	sent_tween.tween_callback(func():
		if is_instance_valid(sent_label): sent_label.text = "Sent ✔"
	)
	sent_tween.tween_interval(2.0)
	sent_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)

	sent_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0
			start_waiting_animation()
	)
	
func start_waiting_animation():
	if not is_instance_valid(waiting_label) or spectator_mode:
		return

	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true
	waiting_blur.visible = true
	waiting_label.modulate.a = 0.0
	waiting_blur.modulate.a = 0.0

	var tween_wait_in = create_tween().set_parallel(true)
	tween_wait_in.tween_property(waiting_label, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_property(waiting_blur, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_callback(func():
		if is_instance_valid(dot_timer): dot_timer.start()
	)

func stop_waiting_animation():
	if is_instance_valid(dot_timer): dot_timer.stop()
	if is_instance_valid(waiting_label): waiting_label.visible = false
	if is_instance_valid(waiting_blur): waiting_blur.visible = false

func _on_dot_timer_timeout():
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count): dots += "."
	if is_instance_valid(waiting_label): waiting_label.text = BASE_WAIT_TEXT + dots
	
# --- Popups & Settings ---
func on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return

	rules_button.pivot_offset = rules_button.size / 2.0
	tween = create_tween()
	tween.tween_property(rules_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(rules_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var popup := RULES_POPUP_SCENE.instantiate()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)

	var close_btn := popup.find_child("CloseButton", true, false)
	if close_btn:
		close_btn.pressed.connect(func():
			dim.queue_free()
			popup.queue_free()
		)

	var title_label := popup.find_child("Title", true, false) as Label
	if title_label:
		title_label.text = "How to Play Filler"

	var rules_label := popup.find_child("RulesLabel", true, false) as RichTextLabel
	if rules_label:
		rules_label.bbcode_enabled = true
		rules_label.visible = true
		rules_label.fit_content = true
		rules_label.scroll_active = false
		rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rules_label.text = _get_rules_text()

	popup.set_as_top_level(true)
	popup.visible = true
	await get_tree().process_frame

	var viewport_size := get_viewport_rect().size
	var desired_width := viewport_size.x * 0.9
	var desired_height: float = popup.get_combined_minimum_size().y
	popup.size = Vector2(desired_width, desired_height)
	popup.set_pivot_offset(popup.size / 2)
	popup.position = (viewport_size / 2) - (popup.size / 2)
	popup.scale = Vector2.ZERO

	var popup_tween := create_tween()
	popup_tween.tween_property(popup, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	popup.grab_focus()
	
func _get_rules_text() -> String:
	return """
[font_size={18px}]
1. Each player is assigned a corner tile at the start of the game.
2. Players take turns filling their tiles with one of 6 colors in an attempt to capture adjacent tiles of the same color.
3. You are not allowed to change the color of your tiles into the color of your opponents tiles.
4. The game ends when there are no more tiles to occupy
[/font_size]
"""

func _parse_avatar_string(data_string: String) -> Dictionary:
	var hair_map = ["Spiky", "Long", "Bun", "Bald"]
	var body_map = ["Default", "Smiling", "Winking", "Surprised", "Frowning", "Tongue Out", "Cute"]
	var eyes_map = ["Open", "Closed", "Winking"]
	var mouth_map = ["Plain", "Smile", "Frown"]
	var clothing_map = ["T-Shirt", "Sweater", "Tank Top"]
	var backdrop_map = ["Plain", "Pattern 1", "Pattern 2", "Pattern 3", "Pattern 4", "Pattern 5", "Pattern 6", "Pattern 7", "Pattern 8", "Pattern 9"]

	var data = {}
	var parts = data_string.split("|")
	for part in parts:
		var key_value = part.split(",")
		if key_value.size() < 2:
			continue

		var key = key_value[0]
		var values = key_value.slice(1)

		match key:
			"hair":
				var index = int(values[0])
				if index >= 0 and index < hair_map.size():
					data["hair_style"] = hair_map[index]
				else:
					print("Warning: Invalid hair index received: ", index)
			"body":
				var index = int(values[0])
				if index >= 0 and index < body_map.size():
					data["body_style"] = body_map[index]
				else:
					print("Warning: Invalid body index received: ", index)
			"eyes":
				var index = int(values[0])
				if index >= 0 and index < eyes_map.size():
					data["eyes_style"] = eyes_map[index]
				else:
					print("Warning: Invalid eyes index received: ", index)
			"mouth":
				var index = int(values[0])
				if index >= 0 and index < mouth_map.size():
					data["mouth_style"] = mouth_map[index]
				else:
					print("Warning: Invalid mouth index received: ", index)
			"clothes":
				var index = int(values[0])
				if index >= 0 and index < clothing_map.size():
					data["clothing_style"] = clothing_map[index]
				else:
					print("Warning: Invalid clothes index received: ", index)
			"backdrop":
				var backdrop_index = int(values[0])
				if backdrop_index >= 0 and backdrop_index < backdrop_map.size():
					data["bg_style"] = backdrop_map[backdrop_index]
				else:
					print("Warning: Invalid backdrop index received: ", backdrop_index)
			"bg_color", "body_color", "hair_color", "clothes_color":
				if values.size() >= 3:
					var color_key = key.replace("_color", "") + "_color"
					data[color_key] = Color(float(values[0]), float(values[1]), float(values[2]))
	return data

func _on_settings_button_pressed() -> void:
	settings_button.pivot_offset = settings_button.size / 2.0
	tween = create_tween()
	tween.tween_property(settings_button, "scale", Vector2(1.3, 1.3), 0.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(settings_button, "scale", Vector2.ONE, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var popup_instance = SETTINGS_POPUP_SCENE.instantiate()
	var settings_popup_script = popup_instance as SettingsPopup

	var root = get_tree().root
	root.add_child(dim)
	root.add_child(popup_instance)
	popup_instance.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)
	settings_popup_script.setup_popup(dim)

	#var volume_setting_hbox = HBoxContainer.new()
	#volume_setting_hbox.add_child(Label.new())
	#volume_setting_hbox.get_child(0).text = "Game Volume:"
	#volume_setting_hbox.get_child(0).set_h_size_flags(Control.SIZE_EXPAND_FILL)
#
	#var volume_slider = HSlider.new()
	#volume_slider.min_value = 0.0
	#volume_slider.max_value = 1.0
	#volume_slider.step = 0.05
	#
	#var saved_volume = SettingsManager.get_setting(game_settings_category, "master_volume", 0.75)
	#volume_slider.value = saved_volume
#
	#volume_slider.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	#volume_slider.value_changed.connect(func(value):
		#AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))
		#print("Master Volume: ", value)
		#SettingsManager.set_setting(game_settings_category, "master_volume", value)
	#)
	#volume_setting_hbox.add_child(volume_slider)
#
	#settings_popup_script.add_custom_setting(volume_setting_hbox)
	#
	#var toggle_debug_checkbox = CheckBox.new()
	#toggle_debug_checkbox.text = "Show Debug Info"
	#
	#var saved_debug_info = SettingsManager.get_setting(game_settings_category, "show_debug_info", false)
	#toggle_debug_checkbox.button_pressed = saved_debug_info
#
	#toggle_debug_checkbox.pressed.connect(func():
		#print("Debug Info Toggled: ", toggle_debug_checkbox.button_pressed)
		#SettingsManager.set_setting(game_settings_category, "show_debug_info", toggle_debug_checkbox.button_pressed)
	#)
	#settings_popup_script.add_custom_setting(toggle_debug_checkbox)

	var custom_settings_title = popup_instance.find_child("CustomSettingsTitleLabel", true)
	if custom_settings_title and custom_settings_title is Label and settings_popup_script.custom_settings_container.get_child_count() > 0:
		custom_settings_title.visible = true
	else:
		if custom_settings_title and custom_settings_title is Label:
			custom_settings_title.visible = false

	settings_popup_script.closed.connect(func():
		print("Settings popup was closed for game: ", game_settings_category)
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
	)
	settings_popup_script.settings_theme_selected.connect(_on_theme_changed)
	settings_popup_script.dark_mode_changed.connect(_apply_bg_for_dark)

	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await get_tree().process_frame

	var viewport_size = get_viewport_rect().size
	var desired_width = viewport_size.x * 0.95
	var desired_height = popup_instance.get_combined_minimum_size().y
	
	popup_instance.size = Vector2(desired_width, desired_height)
	popup_instance.position = Vector2((viewport_size.x - desired_width) / 2, viewport_size.y)
	
	var bottom_offset = 50
	var target_y_position = viewport_size.y - desired_height - bottom_offset
	var target_position = Vector2((viewport_size.x - desired_width) / 2, target_y_position)

	var popup_tween = create_tween()
	popup_tween.tween_property(popup_instance, "position", target_position, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	popup_instance.grab_focus()
	
func _on_theme_changed(new_theme_name: String):
	print("Game scene received theme change: ", new_theme_name)
	pass
	
func _load_game_specific_settings():
	var saved_volume = SettingsManager.get_setting(game_settings_category, "master_volume", 0.75)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info = SettingsManager.get_setting(game_settings_category, "show_debug_info", false)
	
	print("Loaded game-specific settings for ", game_settings_category, ":")
	print("  Master Volume: ", saved_volume)
	print("  Show Debug Info: ", show_debug_info)
