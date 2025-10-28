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
@onready var spec_label: Label = %SpecLabel

var sent_tween: Tween
var dot_count: int = 0
var my_player
var turn_owner: int = 1
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
var win_loss_state: String = ""
var replay = null
var player = null # note; enemy player id, not my player id
var game_over: bool = false
var can_interact: bool = true
var suppress_next_click: bool = false
var last_highlight: Node2D = null

var boardSizeX = 7
var boardSizeY = 6

func _ready() -> void:
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		if not has_connected:
			print("App plugin is available")
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			set_waiting(true)
			return

	else:
		if player == null or replay == null:
			_set_game_data('{"isYourTurn":true,"player":"1","replay":"board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"}')
			print("App plugin is not available")
			return
		
	if player == null or replay == null:
		return
	
	var playerBox = get_node_or_null("../Player" + str(player) + "Box")
	if playerBox != null and not spectator_mode:
		playerBox.get_child(0).set_text("[center]You[/center]")
		
	var board = replay.split('board:')[1].split('|')[0].split(',')

	if firstReplay:
		for y in range(0, boardSizeY):
			for x in range(0, boardSizeX):
				var val: String = board[y * boardSizeX + x]
				if val == "1":
					spawnPiece(x, "yellow", y, false)
				elif val == "2":
					spawnPiece(x, "red", y, false)
		firstReplay = false
	
	var replay_split: PackedStringArray = replay.split("|")
	for elem in replay_split:
		if elem.begins_with("move:"):
			var mv := elem.substr(5).split(",")  # ["x","y","playerId"]
			if mv.size() >= 3:
				var mx := int(mv[0])
				var mover_id := int(mv[2])
				var color := _player_id_to_color(mover_id)
				spawnPiece(mx, color, -1, true)
	
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
	var move_color := str(player)

	var payload: Dictionary = {
		"replay": "board:" + board_str + "|move:" + str(move_x) + "," + str(move_y) + "," + move_color
	}

	if game_over and win_loss_state != "":
		var winner_id: String = (my_player if my_player != "" else str(player))
		payload["winner"] = winner_id + "|" + win_loss_state

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

	var avatar_key := ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	print("[Send] PAYLOAD: ", payload)

	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(JSON.stringify(payload))
	else:
		print("AppPlugin is null. Cannot send game data.")

	if is_instance_valid(send_button):
		send_button.disabled = true
		_update_send_button_visibility(false)

	if not game_over:
		play_sent_animation()

	
func _lock_interaction_briefly(duration: float = 0.25) -> void:
	can_interact = false
	var t := get_tree().create_timer(duration)
	t.timeout.connect(func(): can_interact = true)
	
func _clear_last_highlight() -> void:
	if last_highlight and is_instance_valid(last_highlight):
		var old_spr: Sprite2D = last_highlight.get_child(0) as Sprite2D
		if old_spr:
			old_spr.self_modulate.a = 1.0
		var t: Tween = last_highlight.get_meta("hl_tween") as Tween
		if t != null and t.is_running():
			t.kill()
		last_highlight.set_meta("hl_tween", null)
	last_highlight = null

func _start_last_move_pulse(piece: Node2D) -> void:
	var spr: Sprite2D = piece.get_child(0) as Sprite2D
	if spr == null:
		return
	spr.self_modulate.a = 1.0

	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_loops(0)
	tw.tween_property(spr, "self_modulate:a", 0.6, 0.45)
	tw.tween_property(spr, "self_modulate:a", 1.0, 0.45)
	piece.set_meta("hl_tween", tw)

	piece.tree_exited.connect(func():
		var t2: Tween = piece.get_meta("hl_tween") as Tween
		if t2 != null and t2.is_running():
			t2.kill()
		piece.set_meta("hl_tween", null)
	)

func _highlight_last(p: Node2D) -> void:
	_clear_last_highlight()
	if p != null and is_instance_valid(p):
		last_highlight = p
		_start_last_move_pulse(p)
		
func _pulse_sprite(spr: Sprite2D) -> Tween:
	spr.self_modulate.a = 1.0
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_loops(0)
	tw.tween_property(spr, "self_modulate:a", 0.6, 0.45)
	tw.tween_property(spr, "self_modulate:a", 1.0, 0.45)
	return tw

func _pulse_nodes(nodes: Array[Node2D]) -> void:
	for n in nodes:
		if n:
			var spr := n.get_child(0) as Sprite2D
			if spr:
				_pulse_sprite(spr)
				
func _find_winning_sequence() -> Array[Vector2i]:
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(1,-1)]
	for y in range(0, boardSizeY):
		for x in range(0, boardSizeX):
			for d in dirs:
				var seq := _four_coords(x, y, d.x, d.y)
				if seq.size() == 4 and _coords_same_color(seq):
					return seq
	return []
	
func _apply_turn_state() -> void:
	if game_over:
		stop_waiting_animation()
		return

	if player == null or not isTurn:
		set_waiting(true)
	else:
		set_waiting(false)

		
func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		print("Is Dark: ", is_dark)
		background.color = Color("#261a19") if is_dark else Color("#947972")

func set_waiting(enabled: bool):
	if game_over:
		stop_waiting_animation()
		waitingForOpponent = false
		if is_instance_valid(send_button):
			send_button.disabled = true
			_update_send_button_visibility(false)
		return

	if enabled:
		waitingForOpponent = true
		droppedPiece = null
		if is_instance_valid(send_button):
			send_button.disabled = true
			_update_send_button_visibility(false)
		start_waiting_animation()
	else:
		droppedPiece = null
		waitingForOpponent = false
		if is_instance_valid(send_button):
			send_button.disabled = true
			_update_send_button_visibility(false)
		stop_waiting_animation()

func export_replay() -> String:
	var payload := _build_replay_payload()
	return JSON.stringify(payload)

func _set_game_data(new_replay: String):
	var data = JSON.parse_string(new_replay)
	print("Incoming Game Data: ", data)
	isTurn = data["isYourTurn"]
	player = int(data["player"])
	my_player = data.get("myPlayerId", "")
	replay = data["replay"]
	var p1_id: String = data.get("player1", "")
	var p2_id: String = data.get("player2", "")
	var opponent_avatar_key = ""
	turn_owner = clamp(int(data.get("player", 1)), 1, 2)

	if my_player != "" and p1_id != "" and p2_id != "":
		player = (1 if my_player == p1_id else (2 if my_player == p2_id else 0))
		if player == 0:
			spectator_mode = true
			if is_instance_valid(spec_label):
				spec_label.visible = spectator_mode
			if is_instance_valid(you_label):
				you_label.visible = not spectator_mode
	else:
		player = (3 - turn_owner) if isTurn else turn_owner

	if player == 1:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"

	if opponent_avatar_key != "" and data.has(opponent_avatar_key):
		var avatar_string = data[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	if isTurn == false:
		if not (player == 2 and p1_id == ""):
			player = 2 if player == 1 else 1

	print("Whoami" + str(player))
	_apply_player_piece_icons()
	_apply_turn_state()
	_ready()
	
func _apply_player_piece_icons() -> void:
	if not is_instance_valid(player_piece) or not is_instance_valid(opp_piece):
		return
	var my_col := getPlayerColor(false)
	var opp_col := getPlayerColor(true)
	player_piece.texture = piece_textures[my_col]
	opp_piece.texture = piece_textures[opp_col]
	if is_instance_valid(you_label):
		you_label.text = "You"
		you_label.visible = not spectator_mode
		
func _player_id_to_color(pid: int) -> String:
	return PIECE_YELLOW if pid == 1 else PIECE_RED
	
func getPlayerColor(other: bool = false) -> String:
	# Player 1 = yellow, Player 2 = red
	var my_color   := PIECE_YELLOW if player == 1 else PIECE_RED
	var opp_color  := PIECE_RED    if player == 1 else PIECE_YELLOW
	return opp_color if other else my_color

func getPieceColor(piece: RigidBody2D) -> String:
	var texture_path: String = piece.get_child(0).texture.resource_path
	return PIECE_RED if texture_path.contains("red") else PIECE_YELLOW

func getPositionInt(posX: int, posY: int) -> String:
	var piece: Node2D = get_node_or_null(str(posX) + "," + str(posY))
	if piece == null:
		return "0"
	var texture_path: String = piece.get_child(0).texture.resource_path
	if texture_path.contains("red"):
		return "2"
	return "1"

func spawnPiece(posX: int, color: String, posY: int = -1, from_replay: bool = false) -> void:
	var piece: RigidBody2D = get_node("ConnectPiece" + str(posX)).duplicate()
	if game_over and not from_replay:
		return
	if (not can_interact) and not from_replay:
		return

	if posY >= 0:
		piece.position.y = yPoses[posY]
	else:
		posY = get_piece_y(posX)
	if posY < 0:
		return

	add_child(piece)
	var spr: Sprite2D = piece.get_child(0) as Sprite2D
	spr.texture = piece_textures[color]
	(piece.get_child(1) as CollisionShape2D).disabled = false
	piece.visible = true
	piece.set_freeze_enabled(false)
	piece.name = str(posX) + "," + str(posY)

	if from_replay:
		_highlight_last(piece)
		var opp_win := _find_winning_sequence()
		if opp_win.size() == 4:
			_clear_last_highlight()
			_highlight_winning_pulse(opp_win)
			_finalize_win(false)
		return

	droppedPiece = piece
	var win_seq := _find_winning_sequence()
	if win_seq.size() == 4:
		_clear_last_highlight()
		_highlight_winning_pulse(win_seq)
		_finalize_win(true)
		await get_tree().process_frame
		await send_game()
		return
	else:
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
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for y in range(0, boardSizeY):
		for x in range(0, boardSizeX):
			for d in dirs:
				var seq := _four_coords(x, y, d.x, d.y)
				if seq.size() == 4 and _coords_same_color(seq):
					_highlight_winning_pulse(seq)
					return true
	return false

func _four_coords(x: int, y: int, dx: int, dy: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(0, 4):
		var nx := x + dx * i
		var ny := y + dy * i
		if nx < 0 or nx >= boardSizeX or ny < 0 or ny >= boardSizeY:
			return []
		if get_node_or_null("%d,%d" % [nx, ny]) == null:
			return []
		out.append(Vector2i(nx, ny))
	return out

func _coords_same_color(cs: Array[Vector2i]) -> bool:
	var first_node := get_node_or_null("%d,%d" % [cs[0].x, cs[0].y])
	if first_node == null:
		return false
	var first_sprite := first_node.get_child(0) as Sprite2D
	if first_sprite == null:
		return false
	var tex0: Texture2D = first_sprite.texture
	for i in range(1, cs.size()):
		var n := get_node_or_null("%d,%d" % [cs[i].x, cs[i].y])
		if n == null:
			return false
		var spr := n.get_child(0) as Sprite2D
		if spr == null or spr.texture != tex0:
			return false
	return true

func _winning_nodes_from_coords(cs: Array[Vector2i]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for c in cs:
		var n := get_node_or_null("%d,%d" % [c.x, c.y])
		if n: out.append(n)
	return out

func _highlight_winning_pulse(cs: Array[Vector2i]) -> void:
	var nodes := _winning_nodes_from_coords(cs)
	_pulse_nodes(nodes)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func move_dropped_piece_to_column(new_x: int) -> void:
	if game_over or not can_interact or droppedPiece == null:
		return

	var new_y: int = get_piece_y(new_x)
	if new_y < 0:
		return

	var color: String = getPieceColor(droppedPiece)

	droppedPiece.queue_free()
	droppedPiece = null
	await get_tree().process_frame
	spawnPiece(new_x, color, -1, false)

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
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			suppress_next_click = true
			dim.queue_free()
			popup.queue_free()
			_lock_interaction_briefly()
			get_viewport().set_input_as_handled()
	)

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)
 
	var close_btn := popup.find_child("CloseButton", true, false)
	if close_btn:
		close_btn.pressed.connect(func():
			suppress_next_click = true
			dim.queue_free()
			popup.queue_free()
			_lock_interaction_briefly()
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

	if not send_button.has_meta("home_pos"):
		send_button.set_meta("home_pos", send_button.global_position)

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
	)

func _finalize_win(i_won: bool) -> void:
	if game_over:
		return
	game_over = true
	didIWin = i_won
	win_loss_state = "1" if i_won else "-1"

	stop_waiting_animation()
	waitingForOpponent = false
	if spectator_mode:
		if (i_won and player == 1) or (!i_won and player == 2):
			win_loss_label.text = "Player 1 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			_show_win_burst(player_avatar_display)
		elif (i_won and player == 2) or (!i_won and player == 1):
			win_loss_label.text = "Player 2 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			_show_win_burst(opp_avatar_display)
	elif not spectator_mode and i_won:
		_show_win_burst(player_avatar_display)
		if not spectator_mode:
			win_loss_label.text = "YOU WIN!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	else:
		_show_win_burst(opp_avatar_display)
		if not spectator_mode:
			win_loss_label.text = "YOU LOSE"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			

	win_loss_label.visible = true
	await get_tree().process_frame
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2
	var tween_in := create_tween()
	tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	can_interact = false
	
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
	
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			suppress_next_click = true
			# Let your SettingsPopup handle the actual close if it already does
			get_viewport().set_input_as_handled()
	)

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
		suppress_next_click = true
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
		_lock_interaction_briefly()
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
	
func _parse_avatar_string(data_string: String) -> Dictionary:
	var hair_map: Array     = AvatarThumbnail.avatar_hair_regions.keys()
	var body_map: Array     = AvatarThumbnail.avatar_fshape_regions.keys()
	var eyes_map: Array     = AvatarThumbnail.avatar_eyes_regions.keys()
	var mouth_map: Array    = AvatarThumbnail.avatar_mouth_regions.keys()
	var clothing_map: Array = AvatarThumbnail.avatar_clothing_regions.keys()
	var backdrop_map: Array = ["Plain"]
	backdrop_map.append_array(AvatarThumbnail.avatar_background_regions.keys())

	var data: Dictionary = {
		"fshape_style":   body_map[0]     if body_map.size()     > 0 else "Default",
		"hair_style":     hair_map[0]     if hair_map.size()     > 0 else "hair1",
		"eyes_style":     eyes_map[0]     if eyes_map.size()     > 0 else "eyes1",
		"mouth_style":    mouth_map[0]    if mouth_map.size()    > 0 else "mouth1",
		"clothing_style": clothing_map[0] if clothing_map.size() > 0 else "clothing1",
		"bg_style":       "Plain",
		"fshape_color":   Color(0.88, 0.67, 0.41),
		"hair_color":     Color(0.17, 0.14, 0.17),
		"clothing_color": Color(0.63, 0.24, 0.24),
		"bg_color":       Color(0.31, 0.36, 0.54),
	}

	if data_string.is_empty():
		return data

	var read_color = func(vals: Array) -> Color:
		if vals.size() >= 3:
			return Color(vals[0].to_float(), vals[1].to_float(), vals[2].to_float())
		return Color.WHITE

	for part in data_string.split("|", false):
		var key_value := part.split(",", false)
		if key_value.size() < 2:
			continue
		var key := key_value[0]

		match key:
			"fshape", "body":
				var i := key_value[1].to_int()
				if i >= 0 and i < body_map.size():
					data["fshape_style"] = String(body_map[i])

			"fshape_color", "body_color":
				data["fshape_color"] = read_color.call(key_value.slice(1))

			"hair":
				var i := key_value[1].to_int()
				if i >= 0 and i < hair_map.size():
					data["hair_style"] = String(hair_map[i])

			"hair_color":
				data["hair_color"] = read_color.call(key_value.slice(1))

			"eyes":
				var i := key_value[1].to_int()
				if i >= 0 and i < eyes_map.size():
					data["eyes_style"] = String(eyes_map[i])

			"mouth":
				var i := key_value[1].to_int()
				if i >= 0 and i < mouth_map.size():
					data["mouth_style"] = String(mouth_map[i])

			"clothes":
				var i := key_value[1].to_int()
				if i >= 0 and i < clothing_map.size():
					data["clothing_style"] = String(clothing_map[i])

			"clothes_color":
				data["clothing_color"] = read_color.call(key_value.slice(1))

			"bg_color":
				data["bg_color"] = read_color.call(key_value.slice(1))

			"backdrop":
				var i := key_value[1].to_int()
				if i >= 0 and i < backdrop_map.size():
					data["bg_style"] = String(backdrop_map[i])
			_:
				pass
	return data
	
func _unhandled_input(event: InputEvent) -> void:
	if suppress_next_click and event is InputEventMouseButton and event.pressed:
		# Consume exactly one click after a popup closes
		suppress_next_click = false
		get_viewport().set_input_as_handled()

func _load_game_specific_settings() -> void:
	var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	print("Loaded game-specific settings for ", game_settings_category, ": volume=", saved_volume, " debug=", show_debug_info)
