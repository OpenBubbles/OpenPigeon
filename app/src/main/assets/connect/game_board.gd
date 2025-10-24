extends Node2D
class_name ConnectGameBoard

@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var rules_button: Button     = %RulesButton
@onready var settings_button: Button = %SettingsButton
@onready var send_button: Button = %SendButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: Control = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var background: ColorRect = %Background
@onready var win_loss_label: Label = %WinLossLabel
@onready var player_piece: TextureRect = %PlayerPiece
@onready var opp_piece: TextureRect = %OppPiece
@onready var you_label: Label = %YouLabel

var sent_tween: Tween
var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"

const PIECE_YELLOW := "yellow"
const PIECE_RED := "red"

var piece_textures = {
	"red": preload("res://connect/red_piece.png"),
	"yellow": preload("res://connect/yellow_piece.png")
}

const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const RULES_POPUP_SCENE = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")

var yPoses = [192.544, 109.498, 26.612, -56.274, -139.121, -221.902]

var droppedPiece = null

var firstReplay = true
var isTurn = false
var game_settings_category: String = ""
var spectator_mode: bool = false
var has_connected = false
var waitingForOpponent = true
var replay = null
var player = null # note; enemy player id, not my player id

var boardSizeX = 7
var boardSizeY = 6

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		if not has_connected:
			print("App plugin is available")
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			return
	else:
		if player == null or replay == null:
			_set_game_data('{"isYourTurn":true,"player":"1","replay":"board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"}')
			print("App plugin is not available")
			return
		
	if player == null or replay == null:
		return
	
	var playerBox = get_node_or_null("../Player" + str(player) + "Box")
	if playerBox != null:
		playerBox.get_child(0).set_text("[center]You[/center]")
		
	var board = replay.split('board:')[1].split('|')[0].split(',')

	if firstReplay:
		for y in range(0, boardSizeY):
			for x in range(0, boardSizeX):
				var val = board[y * boardSizeX + x]
				if val == "1":
					spawnPiece(x, "yellow", y)
				elif val == "2":
					spawnPiece(x, "red", y)
		firstReplay = false
	
	var replaySplit = replay.split('|')
	for elem in replaySplit:
		var spl = elem.split(':')
		if spl[0] == "move":
			spawnPiece(int(elem.split(',')[0]), getPlayerColor(isTurn))
	
	if check_win() == false:
		set_waiting(not isTurn)
		
	if is_instance_valid(rules_button):
		rules_button.pressed.connect(on_rules_button_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)
		send_button.pressed.connect(_on_send_pressed)
		
func _build_replay_payload() -> Dictionary:
	# Safety: must have an active dropped piece
	if droppedPiece == null:
		return {}

	var board_str := ""
	for y in range(0, boardSizeY):
		for x in range(0, boardSizeX):
			if str(x) + "," + str(y) != droppedPiece.name:
				board_str += getPositionInt(x, y) + ","
			else:
				board_str += "0,"
	board_str = board_str.substr(0, board_str.length() - 1)

	var move_x := int(droppedPiece.name.split(',')[0])
	var move_y := int(droppedPiece.name.split(',')[1])
	var move_color := getPositionInt(move_x, move_y)

	var did_win := check_win()
	var payload := {
		"replay": "board:" + board_str + "|move:" + str(move_x) + "," + str(move_y) + "," + move_color
	}

	if did_win:
		payload["winner"] = my_player + "|" + ("1" if didIWin else "-1")

	return payload

func _on_send_pressed() -> void:
	await send_game()

func send_game() -> void:
	if droppedPiece == null:
		print("[Send] No move to send.")
		return

	print("[Send] send_game() called")
	await get_tree().process_frame

	var payload := _build_replay_payload()
	if payload.is_empty():
		print("[Send] Payload empty; abort.")
		return

	# Remember what we sent (optional logging parity)
	var replay: String = payload.get("replay", "")
	print("[Send] PAYLOAD replay: ", replay)

	# Include avatar data like the other game
	var avatar_key := ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	# Ship it to host
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(JSON.stringify(payload))
	else:
		print("AppPlugin is null. Cannot send game data.")

	# UI: disable/hide send, play "Sent ✔", then go into waiting
	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)

	play_sent_animation()

	# Move to waiting state and clear the move
	set_waiting(true)
		
func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		print("Is Dark: ", is_dark)
		background.color = Color("#261a19") if is_dark else Color("#947972")

func set_waiting(enabled: bool):
	if enabled:
		replay = null
		player = null
		waitingForOpponent = true
		droppedPiece = null
		if is_instance_valid(send_button):
			send_button.disabled = true
			_update_send_button_visibility(false)
	else:
		droppedPiece = null
		waitingForOpponent = false
		if is_instance_valid(send_button):
			send_button.disabled = true
			_update_send_button_visibility(false)

func export_replay() -> String:
	var payload := _build_replay_payload()
	return JSON.stringify(payload)

var my_player
func _set_game_data(new_replay: String):
	var data = JSON.parse_string(new_replay)
	isTurn = data["isYourTurn"]
	player = int(data["player"])
	replay = data["replay"]
	
	if isTurn == false:
		player = 2 if player == 1 else 1
		print(player)
	#my_player = data["myPlayerId"]
	my_player = ""
	print("Whoami" + str(player))
	
	_ready()
	
func getPlayerColor(other: bool = false) -> String:
	# Player 1 = yellow, Player 2 = red
	var my_color   := PIECE_YELLOW if player == 1 else PIECE_RED
	var opp_color  := PIECE_RED    if player == 1 else PIECE_YELLOW
	return opp_color if other else my_color

func getPieceColor(piece: RigidBody2D):
	var texture = piece.get_child(0).texture.resource_path
	if texture.contains("red"):
		return "red"
	return "yellow"

func getPositionInt(posX: int, posY: int) -> String:
	var piece: Node2D = get_node_or_null(str(posX) + "," + str(posY))
	if piece == null:
		return "0"
	var texture_path: String = piece.get_child(0).texture.resource_path
	if texture_path.contains("red"):
		return "2"
	return "1"

func spawnPiece(posX: int, color: String, posY: Variant = null):
	var piece: RigidBody2D = get_node("ConnectPiece"+str(posX)).duplicate()
	if posY != null:
		piece.position.y = yPoses[posY]
	else:
		posY = get_piece_y(posX)
	
	if posY < 0:
		#no free spots
		return
		
	add_child(piece)
	piece.get_child(0).texture = piece_textures[color]
	piece.get_child(1).disabled = false
	piece.set_visible(true)
	piece.set_freeze_enabled(false)
	piece.name = str(posX) + "," + str(posY)
	
	if waitingForOpponent == false:
		droppedPiece = piece
		if is_instance_valid(send_button):
			send_button.disabled = false
			_update_send_button_visibility(true)
	
func get_piece_y(posX: int):
	for posY in range(0, boardSizeY):
		if get_node_or_null(str(posX) + "," + str(posY)) == null:
			return posY
	return -1
	
func undo_move():
	if droppedPiece != null:
		droppedPiece.queue_free()
		droppedPiece = null
		get_node("../SendButton").disabled = true
		get_node("../UndoButton").disabled = true

func check_dir(direction: Vector2, startingPos: Vector2, numChecks: int = 1) -> bool:
	var startingPiece = get_node_or_null(str(int(startingPos.x)) + "," + str(int(startingPos.y)))
	if startingPiece == null:
		return false
	var newPos = Vector2(startingPos.x + direction.x, startingPos.y + direction.y)
	if newPos.x >= boardSizeX or newPos.y >= boardSizeY:
		return false
	var checkPiece = get_node_or_null(str(int(newPos.x)) + "," + str(int(newPos.y)))
	if checkPiece != null:
		if checkPiece.get_child(0).texture.resource_path == startingPiece.get_child(0).texture.resource_path:
			if numChecks == 3:
				return true
			return check_dir(direction, newPos, numChecks+1)
	return false

var didIWin = false
func check_win() -> bool:
	var directions: Array[Vector2] = [
		Vector2(0, 1),  Vector2(0, -1), Vector2(1, 0),  
		Vector2(-1, 0), Vector2(-1, 1),  Vector2(1, 1),  
		Vector2(-1, -1), Vector2(1, -1)  
	]
	
	for y in range(0, boardSizeY):
		for x in range(0, boardSizeX):
			var piece = get_node_or_null(str(x) + "," + str(y))
			if piece == null:
				continue
			for direction in directions:
				if check_dir(direction, Vector2(x, y)):
					didIWin = getPieceColor(piece) == getPlayerColor()
					if getPieceColor(piece) == getPlayerColor():
						get_node("../winLoseLabel").get_child(0).set_text("[center]YOU WIN!!![/center]")
					else:
						get_node("../winLoseLabel").get_child(0).set_text("[center]You Lose :([/center]")
					get_node("../waitingLabel").visible = false
					get_node("../winLoseLabel").visible = true
					waitingForOpponent = true
					return true
	return false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func move_dropped_piece_to_column(new_x: int) -> void:
	if droppedPiece == null:
		return

	# If we’re moving to a different column, make sure there is space there first.
	# If it's the SAME column, we allow it (we'll free then re-drop in the same column).
	var current_x := int(droppedPiece.name.split(",")[0])
	var moving_to_same_column := (current_x == new_x)
	if not moving_to_same_column and get_piece_y(new_x) < 0:
		# Target column full; keep current piece where it is.
		return

	# Remember color, then remove the old piece.
	var color : String = getPieceColor(droppedPiece)
	droppedPiece.queue_free()
	droppedPiece = null

	# Wait one frame so the freed piece is actually gone from the tree (and board naming).
	await get_tree().process_frame

	# Now place a fresh one that will drop in the new column.
	spawnPiece(new_x, color)

	# Ensure Send is available/visible (spawnPiece already enables it when appropriate, but this is safe)
	if is_instance_valid(send_button):
		send_button.disabled = false
		_update_send_button_visibility(true)
	
func on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return

	rules_button.pivot_offset = rules_button.size / 2.0
	var tween := create_tween()
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
		title_label.text = "How to Play Four In A Row"

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
	
func _update_send_button_visibility(should_show: bool) -> void:
	if not is_instance_valid(send_button):
		return

	send_button.set_as_top_level(true)

	# Cache the home/global position once
	if not send_button.has_meta("home_pos"):
		send_button.set_meta("home_pos", send_button.global_position)

	# Kill any running tween
	if send_button.has_meta("sb_tween"):
		var old_tw: Variant = send_button.get_meta("sb_tween")
		if old_tw is Tween and (old_tw as Tween).is_running():
			(old_tw as Tween).kill()

	var home: Vector2 = send_button.get_meta("home_pos")
	var vp := get_viewport_rect()
	var off_y: float = vp.size.y + send_button.size.y + 30.0
	var start_pos := Vector2(home.x, off_y)
	var is_send_visible := send_button.visible

	if should_show:
		if not is_send_visible:
			send_button.global_position = start_pos
			send_button.visible = true
			send_button.modulate.a = 1.0
		elif send_button.global_position.y > vp.size.y:
			send_button.global_position = start_pos

		var t_in := create_tween()
		send_button.set_meta("sb_tween", t_in)
		t_in.tween_property(send_button, "global_position", home, 0.35)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		if is_send_visible:
			var end_pos := Vector2(home.x, off_y)
			var t_out := create_tween()
			send_button.set_meta("sb_tween", t_out)
			t_out.tween_property(send_button, "global_position", end_pos, 0.25)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t_out.tween_callback(func():
				if is_instance_valid(send_button):
					send_button.visible = false
			)

func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Four In A Row[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
• Be the first player to connect four of your colored pieces in a row.
• Rows can be vertical, horizontal, or diagonal.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• Players take turns dropping one piece into any of the columns on the board.
• The piece will fall to the lowest available space in that column.
• Once placed, a piece cannot be moved or removed.
• After your move, play passes to your opponent.
[/font_size]

[font_size={24px}][b]Winning the Game[/b][/font_size]
[font_size={18px}]
• You win by connecting four of your own colored pieces in a straight line—vertically, horizontally, or diagonally.
• If the board fills completely with no four-in-a-row for either player, the game ends in a draw.
[/font_size]
"""

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		print("Warning: sent_label is not valid for play_sent_animation.")
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
		if is_instance_valid(sent_label):
			sent_label.text = "Sent ✔"
	)
	sent_tween.tween_interval(2.0)
	sent_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)

	sent_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0
			start_waiting_animation()
	)
	
#func check_win() -> bool:
	#print("--- CHECKING WIN CONDITION ---")
	#if my_score + opp_score < (board_size - 1) * (board_size - 1):
		#print("-> RESULT: Game Continues. More than 2 colors remain or combined score is too low.")
		#return false
	#print("-> WIN CONDITION MET: 2 or fewer colors remain.")
	#
	#var was_over = game_over
	#game_over = true
	#if not was_over:
		#print("-> Evaluating final scores. My score: %d, Opponent's score: %d" % [my_score, opp_score])
		#if my_score > opp_score:
			#print("-> FINAL TALLY: YOU WIN!")
			#_show_win_burst(player_avatar_display)
			#if not spectator_mode:
				#win_loss_label.text = "YOU WIN!"
				#win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			#else:
				#win_loss_label.text = "Player 1 Wins!"
				#win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			#win_loss_state = "1"
		#elif opp_score > my_score:
			#print("-> FINAL TALLY: YOU LOSE")
			#_show_win_burst(opp_avatar_display)
			#win_loss_label.text = "YOU LOSE"
			#if not spectator_mode:
				#win_loss_label.text = "YOU LOSE"
				#win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			#else:
				#win_loss_label.text = "Player 2 Wins!"
				#win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			#win_loss_state = "-1"
		#else:
			#print("-> FINAL TALLY: TIE!")
			#win_loss_label.text = "DRAW!"
			#win_loss_state = "0"
			#win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
#
		#win_loss_label.visible = true
		#await get_tree().process_frame
		#win_loss_label.scale = Vector2.ZERO
		#win_loss_label.pivot_offset = win_loss_label.size / 2
		#
		#var tween_in = create_tween()
		#tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	#else:
		#print("-> Game was already marked as over. No new result displayed.")
#
	#return true
	
func _ensure_avatar_wrapper(avatar: Control) -> Control:
	var parent: Node = avatar.get_parent()
	if parent == null:
		return null

	if parent is Control and not (parent is Container):
		return parent as Control

	var wrapper: Control = Control.new()
	wrapper.name = "%s_Wrap" % avatar.name
	wrapper.size_flags_horizontal = avatar.size_flags_horizontal
	wrapper.size_flags_vertical = avatar.size_flags_vertical
	wrapper.custom_minimum_size = avatar.get_combined_minimum_size()

	var idx: int = avatar.get_index()
	parent.add_child(wrapper)
	parent.move_child(wrapper, idx)

	avatar.reparent(wrapper)
	avatar.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar.offset_left = 0.0
	avatar.offset_top = 0.0
	avatar.offset_right = 0.0
	avatar.offset_bottom = 0.0

	avatar.item_rect_changed.connect(func():
		if is_instance_valid(wrapper):
			wrapper.custom_minimum_size = avatar.get_combined_minimum_size()
	)

	return wrapper
	
func _show_win_burst(avatar: Control) -> void:
	var wrapper: Control = _ensure_avatar_wrapper(avatar)
	if not is_instance_valid(wrapper):
		return

	var existing: Node = wrapper.get_node_or_null("AvatarWinAnim")
	if existing != null:
		return

	var anim_instance: Control = AvatarWinAnimScene.instantiate() as Control
	anim_instance.name = "AvatarWinAnim"
	wrapper.add_child(anim_instance)

	var avatar_idx: int = avatar.get_index()
	wrapper.move_child(anim_instance, avatar_idx)

	anim_instance.z_as_relative = false
	avatar.z_as_relative = false
	anim_instance.z_index = 0
	avatar.z_index = max(avatar.z_index, 1)

	anim_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	anim_instance.offset_left = -52.0
	anim_instance.offset_right = 52.0
	anim_instance.offset_top = -43.0
	anim_instance.offset_bottom = 43.0

	(anim_instance as Node).call("set_color", Color(1.0, 0.84, 0.0))
	(anim_instance as Node).call("play", 0.05)

func start_waiting_animation():
	if not is_instance_valid(waiting_label) or not is_instance_valid(waiting_blur) or not is_instance_valid(dot_timer):
		print("Warning: Waiting animation nodes are not valid.")
		return
	if spectator_mode:
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
		dot_timer.start()
	)

func stop_waiting_animation():
	if is_instance_valid(dot_timer):
		dot_timer.stop()
	if is_instance_valid(waiting_label):
		waiting_label.visible = false
		waiting_label.modulate.a = 1.0
	if is_instance_valid(waiting_blur):
		waiting_blur.visible = false
		waiting_blur.modulate.a = 1.0

func _on_dot_timer_timeout():
	if not is_instance_valid(waiting_label):
		print("Warning: waiting_label is not valid in _on_dot_timer_timeout.")
		return
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots

func _on_settings_button_pressed() -> void:
	if not is_instance_valid(settings_button):
		return
	settings_button.pivot_offset = settings_button.size / 2.0
	var tween := create_tween()
	tween.tween_property(settings_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(settings_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var popup_instance := SETTINGS_POPUP_SCENE.instantiate()
	var settings_popup_script := popup_instance as SettingsPopup

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup_instance)
	popup_instance.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)

	settings_popup_script.setup_popup(dim)

	#var volume_setting_hbox := HBoxContainer.new()
	#volume_setting_hbox.add_child(Label.new())
	#(volume_setting_hbox.get_child(0) as Label).text = "Game Volume:"
	#(volume_setting_hbox.get_child(0) as Label).set_h_size_flags(Control.SIZE_EXPAND_FILL)
#
	#var volume_slider := HSlider.new()
	#volume_slider.min_value = 0.0
	#volume_slider.max_value = 1.0
	#volume_slider.step = 0.05
	#var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	#volume_slider.value = saved_volume
	#volume_slider.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	#volume_slider.value_changed.connect(func(value):
		#AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))
		#SettingsManager.set_setting(game_settings_category, "master_volume", value)
	#)
	#volume_setting_hbox.add_child(volume_slider)
	#settings_popup_script.add_custom_setting(volume_setting_hbox)
#
	#var toggle_debug_checkbox := CheckBox.new()
	#toggle_debug_checkbox.text = "Show Debug Info"
	#var saved_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	#toggle_debug_checkbox.button_pressed = saved_debug_info
	#toggle_debug_checkbox.pressed.connect(func():
		#SettingsManager.set_setting(game_settings_category, "show_debug_info", toggle_debug_checkbox.button_pressed)
	#)
	#settings_popup_script.add_custom_setting(toggle_debug_checkbox)

	var custom_settings_title := popup_instance.find_child("CustomSettingsTitleLabel", true)
	if custom_settings_title and custom_settings_title is Label and settings_popup_script.custom_settings_container.get_child_count() > 0:
		(custom_settings_title as Label).visible = true
	elif custom_settings_title and custom_settings_title is Label:
		(custom_settings_title as Label).visible = false

	settings_popup_script.closed.connect(func():
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
	)
	settings_popup_script.settings_theme_selected.connect(_on_theme_changed)
	settings_popup_script.dark_mode_changed.connect(_apply_bg_for_dark)

	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await get_tree().process_frame

	var viewport_size := get_viewport_rect().size
	var desired_width := viewport_size.x * 0.95
	var desired_height: float = popup_instance.get_combined_minimum_size().y
	popup_instance.size = Vector2(desired_width, desired_height)
	popup_instance.position = Vector2((viewport_size.x - desired_width) / 2, viewport_size.y)

	var bottom_offset := 50
	var target_y_position := viewport_size.y - desired_height - bottom_offset
	var target_position := Vector2((viewport_size.x - desired_width) / 2, target_y_position)

	var popup_tween := create_tween()
	popup_tween.tween_property(popup_instance, "position", target_position, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	popup_instance.grab_focus()

func _on_theme_changed(new_theme_name: String) -> void:
	pass

func _load_game_specific_settings() -> void:
	var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	print("Loaded game-specific settings for ", game_settings_category, ": volume=", saved_volume, " debug=", show_debug_info)
