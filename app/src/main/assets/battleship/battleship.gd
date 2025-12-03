extends Control

const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const RULES_POPUP_SCENE = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")
const BOMB_TEXTURE_PATH := preload("res://battleship/bomb.png")
const PLANE_TEXTURE_PATH := preload("res://battleship/plane.png")

var sent_tween: Tween
var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"

@onready var state: Label = %StateLabel
@onready var start_button: Button = %StartButton
@onready var fire_button: Button = %FireButton
@onready var shuffle_button: TextureButton = %ShuffleButton
@onready var battleground1: BattleGround = %BattleGround1
@onready var battleground2: BattleGround = %BattleGround2
@onready var settings_button: Button = %SettingsButton
@onready var rules_button: Button = %RulesButton
@onready var winner_label: Label = %WinLossLabel
@onready var waiting_label: Label = %waitingLabel
@onready var sent_label: Label = %SentLabel
@onready var waiting_blur: ColorRect = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var spectator_label: Label = %SpecLabel
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var choose_target_label: Label = %ChooseTargetLabel
@onready var water_rect: ColorRect = %WaterRect
@onready var clouds_rect: ColorRect = %CloudsRect
@onready var player1_container: Control = %Player1BoardContainer
@onready var player2_container: Control = %Player2BoardContainer

var _water_scroll_x: float = 0.0
var isTurn = false
var myBattleground: BattleGround = null
var theirBattleground: BattleGround = null
var myBoardContainer: Control = null
var theirBoardContainer: Control = null
var my_player
var has_connected = false
var player = null
var game_settings_category: String = ""
var spectator_mode: bool = false
var fireMode = false
var is_end = false
var winner = false
var _board_center_pos: Vector2 = Vector2.ZERO
var _board_travel_distance: float = 0.0
var travel_distance: float = 6.0
var travel_anim_duration: float = 3.0
var _clouds_home_pos: Vector2 = Vector2.ZERO
const PLANE_SCALE := 0.45        # smaller plane
const BOMB_START_SCALE := 0.15    # still big when it appears
const BOMB_END_SCALE := 0.01     # much smaller when it hits
var _shake_tween: Tween

func _ready() -> void:
	randomize()
	print("[READY] water_rect:", water_rect)
	print("[READY] clouds_rect:", clouds_rect)
	print("[READY] battleground1:", battleground1)
	print("[READY] battleground2:", battleground2)
	
	if is_instance_valid(battleground1):
		_board_center_pos = battleground1.global_position
	else:
		_board_center_pos = Vector2.ZERO
		
	if is_instance_valid(clouds_rect):
		_clouds_home_pos = clouds_rect.global_position

	# How far the boards travel off-screen for the swipe
	_board_travel_distance = get_viewport_rect().size.x * travel_distance
	
	var appPlugin := Engine.get_singleton("AppPlugin")
	if is_instance_valid(rules_button):
		rules_button.pressed.connect(on_rules_button_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(start_button):
		start_button.pressed.connect(_on_start_button_pressed)
	if is_instance_valid(fire_button):
		fire_button.pressed.connect(_on_fire_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	if is_instance_valid(fire_button):
		fire_button.visible = false
		fire_button.disabled = true
	if appPlugin:
		if not has_connected:
			print("App plugin is available")
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			return
	else:
		if player == null or replay == null:
			print("App plugin is not available, using dev data")

			#var dev_data := { #SETUP SCREEN PLAYER 1
				#"size": 10,
				#"isYourTurn": true,
				#"player": 1,
				#"myPlayerId": "DEV_PLAYER",
				#"replay": "",
				#"bullets1": "",
				#"bullets2": "",
				#"skip_ships": "",
				#"ships1": "",
				#"ships2": "",
			#}
			
			var dev_data := { #SETUP SCREEN PLAYER 2 (PLAYER 1 Has Chosen Board)
				"size": 8,
				"isYourTurn": true,
				"player": 1,
				"myPlayerId": "DEV_PLAYER",
				"replay": "",
				"bullets1": "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0",
				"bullets2": "",
				"skip_ships": "",
				"ships1": "pos:2,3&num:0,0,0,0&rot:0|pos:1,0&num:0,0,0&rot:1|pos:4,2&num:0,0,0&rot:1|pos:7,4&num:0,0,0&rot:0|pos:0,4&num:0,0&rot:0|pos:5,6&num:0,0&rot:0|pos:5,0&num:0,0&rot:1",
				"ships2": "",
			}

			_set_game_data(JSON.stringify(dev_data))
			return

	if replay == null or player == null:
		return
		
	if water_rect and water_rect.material is ShaderMaterial:
		var mat := water_rect.material as ShaderMaterial
		if mat.get_shader_parameter_list().size() > 0:
			# Adjust "scroll_x" to whatever your shader actually uses
			if mat.get_shader_parameter_list().any(func(p): return p.name == "scroll_x"):
				_water_scroll_x = float(mat.get_shader_parameter("scroll_x"))

func _set_game_data(new_replay: String):
	
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: ", parsed)
	
	my_player = parsed.get("myPlayerId", "")
	var replay = parsed["replay"]
	var bullets1 = parsed["bullets1"]
	var bullets2 = parsed["bullets2"]
	var skip = parsed["skip_ships"]
	var s1 = parsed["ships1"]
	var s2 = parsed["ships2"]
	var bsize = int(parsed["size"])
	isTurn = parsed["isYourTurn"]
	player = int(parsed["player"])
	print(new_replay)
	if isTurn:
		player = 2 if player == 1 else 1
	
	battleground1.set_size(bsize)
	battleground2.set_size(bsize)
	
	if not s1.is_empty():
		battleground1.from_encoded(s1)
	if not s2.is_empty():
		battleground2.from_encoded(s2)
	
	if not bullets1.is_empty():
		battleground1.from_bullets(bullets1)
		
	if not bullets2.is_empty():
		battleground2.from_bullets(bullets2)
	
	# show my board
	if player == 1:
		myBattleground = battleground1
		theirBattleground = battleground2
		myBoardContainer = player1_container
		theirBoardContainer = player2_container
	else:
		myBattleground = battleground2
		theirBattleground = battleground1
		myBoardContainer = player2_container
		theirBoardContainer = player1_container
	
	show_battleground(true)
	if isTurn:
		stop_waiting_animation()
		
		if not replay.is_empty():
			start_button.disabled = true
			state.text = ""
			play_replay(replay)
		elif myBattleground.is_empty():
			if bsize == 8:
				myBattleground.from_encoded("pos:4,1&num:0,0,0,0&rot:1|pos:0,4&num:0,0,0&rot:0|pos:0,2&num:0,0,0&rot:1|pos:4,6&num:0,0,0&rot:1|pos:7,3&num:0,0&rot:0|pos:0,0&num:0,0&rot:1|pos:2,6&num:0,0&rot:0")
			if bsize == 9:
				myBattleground.from_encoded("pos:2,0&num:0,0,0,0&rot:0|pos:5,7&num:0,0,0,0&rot:1|pos:0,5&num:0,0,0,0&rot:0|pos:8,3&num:0,0,0&rot:0|pos:2,5&num:0,0,0&rot:0|pos:4,0&num:0,0,0&rot:0|pos:0,0&num:0,0,0&rot:0|pos:6,0&num:0,0,0&rot:0")
			if bsize == 10:
				myBattleground.from_encoded("pos:2,7&num:0,0,0,0&rot:1|pos:7,6&num:0,0,0&rot:1|pos:3,1&num:0,0,0&rot:1|pos:2,3&num:0,0&rot:0|pos:7,2&num:0,0&rot:0|pos:0,0&num:0,0&rot:1|pos:2,9&num:0&rot:0|pos:0,6&num:0&rot:1|pos:9,9&num:0&rot:0|pos:0,3&num:0&rot:1")
			myBattleground.placing_items = true
			for ship in myBattleground.ships:
				ship.canBeMoved = true
		else:
			my_battleground_ready()
	else:
		start_button.disabled = true
		if not skip.is_empty():
			theirBattleground.from_encoded(skip)
		if theirBattleground.is_over():
			mark_end(true)
			return
		state.text = ""
		start_waiting_animation()
		myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
		theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED

func play_replay(replay: String):
	for move in replay.split("|"):
		await get_tree().create_timer(1.0).timeout
		var elements = move.split(",")
		myBattleground.fire(Vector2(int(elements[0]), int(elements[1])))
	await get_tree().create_timer(2.0).timeout
	my_battleground_ready()

func show_battleground(mine: bool):
	if not is_instance_valid(myBoardContainer) or not is_instance_valid(theirBoardContainer):
		return

	# Use the helper to ensure we don't break layout by setting visible=false
	_set_board_active(myBoardContainer, myBattleground, mine)
	_set_board_active(theirBoardContainer, theirBattleground, not mine)
	
func _set_board_active(container: Control, board: BattleGround, active: bool) -> void:
	if not is_instance_valid(container) or not is_instance_valid(board):
		return

	# ALWAYS keep visible=true so PanelContainers/VBoxContainers calculate size correctly
	container.visible = true 
	
	# Use alpha to hide visually
	container.modulate.a = 1.0 if active else 0.0
	
	# Handle input and processing
	board.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

# state before we take action, state other person should go to for replay
var replay: Array[String] = []
func send_update():
	var myEncoded = myBattleground.encode_ships()
	var bullets = myBattleground.encode_bullets()
	var msg = {
		"ships" + str(player): myEncoded,
		"bullets" + str(player): bullets,
	}
	if not replay.is_empty():
		msg["replay"] = "|".join(replay)
		msg["skip_ships"] = theirBattleground.encode_ships()
		msg["skip_bullets"] = theirBattleground.encode_bullets()
	
	if is_end:
		msg["winner"] = my_player + "|" + ("1" if winner else "-1")
	
	var encoded = JSON.stringify(msg)
	
	print("replay")
	print(encoded)
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(encoded)
	else:
		print("app not connected??")
	state.text = ""
	if not is_end:
		play_sent_animation()
	start_button.disabled = true
	myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
	theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED
	print("setting their process mode to " + str(false))

func my_battleground_ready():
	if theirBattleground.is_empty():
		# Opponent board not ready yet; send ours and wait
		send_update()
		return

	if myBattleground.is_over():
		mark_end(false)
		return

	fireMode = true

	# We're done with setup UI
	if is_instance_valid(state):
		state.visible = false
		state.text = ""

	shuffle_button.disabled = true
	shuffle_button.modulate.a = 0
	start_button.visible = false
	start_button.disabled = true

	theirBattleground.set_attack()

	_swap_to_opponent_board(false)

func _swap_to_opponent_board(reverse: bool = false) -> void:
	if not is_instance_valid(myBattleground) or not is_instance_valid(theirBattleground):
		print("[SWAP] battlegrounds not valid")
		show_battleground(false)
		return
	if not is_instance_valid(myBoardContainer) or not is_instance_valid(theirBoardContainer):
		print("[SWAP] board containers not valid")
		show_battleground(false)
		return

	# Viewport info
	var screen_rect := get_viewport_rect()
	var screen_width: float = screen_rect.size.x

	# 1. Capture HOME positions (for this specific layout state)
	var my_home: Vector2 = myBoardContainer.global_position
	var their_home: Vector2 = theirBoardContainer.global_position

	var travel_distance_local: float = screen_width * 3.0
	var travel_anim_duration: float = 2.5
	var offset := Vector2(travel_distance_local, 0.0)

	# 2. PREPARATION
	myBoardContainer.set_as_top_level(true)
	theirBoardContainer.set_as_top_level(true)

	var my_start_pos: Vector2
	var my_target_pos: Vector2
	var their_start_pos: Vector2
	var their_target_pos: Vector2

	if reverse:
		# Coming BACK to my board (My board enters, Theirs leaves)
		my_start_pos = my_home - offset
		my_target_pos = my_home
		their_start_pos = their_home
		their_target_pos = their_home + offset
	else:
		# Going TO opponent board (My board leaves, Theirs enters)
		my_start_pos = my_home
		my_target_pos = my_home - offset
		their_start_pos = their_home + offset
		their_target_pos = their_home

	# Ensure both are visible and opaque for the animation
	myBoardContainer.visible = true
	myBoardContainer.modulate.a = 1.0
	
	theirBoardContainer.visible = true
	theirBoardContainer.modulate.a = 1.0

	myBoardContainer.global_position = my_start_pos
	theirBoardContainer.global_position = their_start_pos

	# Hide UI
	if is_instance_valid(fire_button):
		fire_button.visible = false
		fire_button.disabled = true
	if is_instance_valid(choose_target_label):
		choose_target_label.visible = false

	# Lock input
	myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
	theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED

	# --- CLOUDS LOGIC ---
	var clouds_tween: Tween
	if clouds_rect and clouds_rect.material is ShaderMaterial:
		var cmat := clouds_rect.material as ShaderMaterial

		clouds_rect.z_index = max(myBoardContainer.z_index, theirBoardContainer.z_index) + 5
		clouds_rect.visible = true

		var viewport_size: Vector2 = screen_rect.size
		var view_center: Vector2 = viewport_size / 2.0
		var cloud_offset: Vector2 = clouds_rect.size / 2.0
		var cloud_x_offset: float = viewport_size.x * 0.25

		var incoming_start_pos: Vector2 = my_start_pos if reverse else their_start_pos
		var incoming_target_pos: Vector2 = my_target_pos if reverse else their_target_pos

		var clouds_start_pos: Vector2 = Vector2(incoming_start_pos.x + cloud_x_offset, view_center.y) - cloud_offset
		var clouds_target_pos: Vector2 = Vector2(incoming_target_pos.x + cloud_x_offset, view_center.y) - cloud_offset

		clouds_rect.global_position = clouds_start_pos
		clouds_rect.modulate.a = 0.0

		clouds_tween = create_tween().set_parallel(true)
		clouds_tween.tween_property(clouds_rect, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		clouds_tween.tween_property(clouds_rect, "global_position", clouds_target_pos, travel_anim_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		var sw_start_val = cmat.get_shader_parameter("swipe_offset")
		var sw_start := float(sw_start_val if sw_start_val != null else 0.0)
		var dir := -1.0 if reverse else 1.0
		var sw_end: float = sw_start + travel_distance_local * 0.001 * dir

		clouds_tween.tween_method(func(v): cmat.set_shader_parameter("swipe_offset", v), sw_start, sw_end, travel_anim_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# --- BOARD & WATER ANIMATION ---
	var main_tween := create_tween().set_parallel(true)

	main_tween.parallel().tween_property(
		myBoardContainer, "global_position",
		my_target_pos, travel_anim_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	main_tween.parallel().tween_property(
		theirBoardContainer, "global_position",
		their_target_pos, travel_anim_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if water_rect and water_rect.material is ShaderMaterial:
		var wmat := water_rect.material as ShaderMaterial
		var w_start_val = wmat.get_shader_parameter("swipe_offset")
		var w_start := float(w_start_val if w_start_val != null else 0.0)
		var dir := -1.0 if reverse else 1.0
		var w_end: float = w_start + travel_distance_local * 0.002 * dir

		main_tween.parallel().tween_method(func(v): wmat.set_shader_parameter("swipe_offset", v), w_start, w_end, travel_anim_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await main_tween.finished

	# --- CLEANUP ---
	var incoming_container: Control
	var incoming_battleground: BattleGround
	var leaving_container: Control
	var leaving_battleground: BattleGround

	if reverse:
		# We slid back to *my* board
		incoming_container = myBoardContainer
		incoming_battleground = myBattleground
		leaving_container = theirBoardContainer
		leaving_battleground = theirBattleground
	else:
		# We slid to *their* board
		incoming_container = theirBoardContainer
		incoming_battleground = theirBattleground
		leaving_container = myBoardContainer
		leaving_battleground = myBattleground

	# Hand them back to the normal layout, but DON'T overwrite positions
	myBoardContainer.set_as_top_level(false)
	theirBoardContainer.set_as_top_level(false)

	# Activate only the one we ended on
	_set_board_active(leaving_container, leaving_battleground, false)
	_set_board_active(incoming_container, incoming_battleground, true)

	# Show target prompt only when ending on opponent board
	if is_instance_valid(choose_target_label) and not reverse:
		choose_target_label.visible = true
		choose_target_label.modulate.a = 0.0
		choose_target_label.z_index = clouds_rect.z_index + 1
		var label_tween := create_tween()
		label_tween.tween_property(choose_target_label, "modulate:a", 1.0, 1.0)

func _debug_bump_water() -> void:
	if water_rect and water_rect.material is ShaderMaterial:
		var mat := water_rect.material as ShaderMaterial
		_water_scroll_x += 1.0
		mat.set_shader_parameter("noise_offset", Vector2(_water_scroll_x, 0.0))
		print("[DEBUG WATER] bump to", _water_scroll_x)
		
func _process(delta: float) -> void:
	# Only care when it's our turn and we're in fire mode
	if not fireMode or not is_instance_valid(theirBattleground):
		return
	
	# Convention: assume (-1, -1) or any negative means "no target selected"
	var tg := theirBattleground.targeting_grid
	var has_target := tg.x >= 0 and tg.y >= 0 and theirBattleground.can_attack
	
	if has_target:
		# We have a valid target: hide the prompt, show Fire
		if is_instance_valid(choose_target_label):
			choose_target_label.visible = false
		
		if is_instance_valid(fire_button):
			fire_button.visible = true
			fire_button.disabled = false
	else:
		# No target selected yet: show the prompt, hide Fire
		if is_instance_valid(fire_button):
			fire_button.visible = false
			fire_button.disabled = true
		
		if is_instance_valid(choose_target_label):
			# Only show this once we're actually on the opponent board
			# (theirBattleground is process_mode INHERIT in that state)
			if theirBattleground.process_mode == Node.PROCESS_MODE_INHERIT:
				choose_target_label.visible = true

func _on_fire_button_pressed() -> void:
	print("Fire pressed")
	
	if not fireMode or not is_instance_valid(theirBattleground):
		return
	
	# Require a valid target
	var grid := theirBattleground.targeting_grid
	if grid.x < 0 or grid.y < 0:
		print("No valid target selected.")
		return
	
	# Freeze UI while bomb falls
	if is_instance_valid(fire_button):
		fire_button.disabled = true
	
	if is_instance_valid(choose_target_label):
		choose_target_label.visible = false
	
	print("Started Bomb Fall")
	# 1) Bomb animation *before* resolving hit/miss
	await _play_bomb_fall_animation(grid)
	print("Finished Bomb Fall")
	# 2) Record move for replay (same as before)
	replay.append(
		str(grid.x) + "," + str(grid.y)
	)
	
	# 3) Try to fire at target (same semantics as original)
	var hit: bool = theirBattleground.fire(grid)
	
	if not hit:
		# Miss or already chosen cell: end turn, wait for opponent
		fireMode = false
		if is_instance_valid(fire_button):
			fire_button.disabled = true
			fire_button.visible = false
		
		theirBattleground.can_attack = false
		await get_tree().create_timer(1.0).timeout
		send_update()
	else:
		# Hit: keep turn unless game is over (same behavior as before)
		_do_hit_camera_shake()
		if theirBattleground.is_over():
			mark_end(true)
			send_update()
	
	# 4) Reset targeting so UI can go back to "choose target" if we still can attack
	theirBattleground.targeting_grid = Vector2(-1, -1)
	
	# Let your _process() handle showing/hiding label + fire button based on can_attack

func _play_bomb_fall_animation(grid_pos: Vector2) -> void:
	# Safety checks
	if not is_instance_valid(theirBattleground):
		print("SOMETHING FAILED IN BOMB FALL (missing battleground)")
		return
	
	var bomb_tex: Texture2D = BOMB_TEXTURE_PATH
	var plane_tex: Texture2D = PLANE_TEXTURE_PATH
	
	if bomb_tex == null:
		print("Bomb texture not found")
		return
	if plane_tex == null:
		print("Plane texture not found")
		return
	
	# --- POSITIONS / COORDS ---
	var cell_center_local: Vector2 = theirBattleground.grid_to_coord(
		grid_pos + Vector2(0.5, 0.5)
	)
	var board_size: Vector2 = theirBattleground.rect_size
	
	# Plane flies LEFT -> RIGHT above the board
	var plane_width: float = plane_tex.get_size().x * PLANE_SCALE
	var plane_height: float = plane_tex.get_size().y * PLANE_SCALE
	
	# Single Y for plane path (a bit above the target row)
	var plane_y := cell_center_local.y - board_size.y * 0.45
	
	var plane_start: Vector2 = Vector2(
		-plane_width,
		plane_y
	)
	var plane_end: Vector2 = Vector2(
		board_size.x + plane_width,
		plane_y
	)
	
	# --- CREATE PLANE ---
	var plane := Sprite2D.new()
	plane.texture = plane_tex
	plane.centered = true
	plane.position = plane_start
	plane.scale = Vector2(PLANE_SCALE, PLANE_SCALE)
	plane.z_index = 1000
	theirBattleground.add_child(plane)
	
	# --- CREATE BOMB (initially hidden) ---
	var bomb := Sprite2D.new()
	bomb.texture = bomb_tex
	bomb.centered = true
	bomb.visible = false
	theirBattleground.add_child(bomb)
	
	# Z-layering relative to clouds
	var bomb_above_z: int = 1100
	var bomb_below_z: int = 0
	if is_instance_valid(clouds_rect):
		bomb_above_z = clouds_rect.z_index + 1
		bomb_below_z = clouds_rect.z_index - 1
	bomb.z_index = bomb_above_z
	
	# --- PLANE TWEEN ---
	var plane_duration := 2.0
	var plane_tween := create_tween()
	plane_tween.tween_property(
		plane, "position",
		plane_end, plane_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# When does the plane pass over the target X?
	var fraction := (cell_center_local.x - plane_start.x) / (plane_end.x - plane_start.x)
	fraction = clamp(fraction, 0.0, 1.0)
	var spawn_delay := plane_duration * fraction
	
	# --- WAIT UNTIL PLANE IS OVER TARGET, THEN DROP BOMB ---
	await get_tree().create_timer(spawn_delay).timeout
	
	# Use the plane's actual position at drop-time
	var plane_drop_pos: Vector2 = plane.position
	
	# Bomb starts right under the plane, then falls to the cell center
	var bomb_start: Vector2 = plane_drop_pos + Vector2(0.0, plane_height * 0.15)
	var bomb_end: Vector2 = cell_center_local
	
	bomb.position = bomb_start
	bomb.scale = Vector2(BOMB_START_SCALE, BOMB_START_SCALE)
	bomb.visible = true
	
	# Bomb above clouds for 1 second, then below
	if is_instance_valid(clouds_rect):
		var z_swap := create_tween()
		z_swap.tween_callback(
			func():
				if is_instance_valid(bomb):
					bomb.z_index = bomb_below_z
		).set_delay(1.0)
	
	var bomb_fall_duration := 2.0
	
	var bomb_tween := create_tween().set_parallel(true)
	bomb_tween.tween_property(
		bomb, "position",
		bomb_end, bomb_fall_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	bomb_tween.tween_property(
		bomb, "scale",
		Vector2(BOMB_END_SCALE, BOMB_END_SCALE), bomb_fall_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	await bomb_tween.finished
	
	if is_instance_valid(bomb):
		bomb.queue_free()
	if is_instance_valid(plane):
		plane.queue_free()

func mark_end(win: bool):
	state.text = ""
	myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
	theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED
	print("setting their process mode to " + str(false))
	get_node("winLoseLabel").get_child(0).set_text("[center]YOU WIN![/center]" if win else "[center]YOU LOSE :([/center]")
	get_node("winLoseLabel").visible = true
	stop_waiting_animation()
	winner = win
	is_end = true

func _on_start_button_pressed() -> void:
	print("Start pressed")
	
	# SETUP PHASE: lock in ships and then either send or start play
	if not fireMode:
		# Stop moving ships
		if is_instance_valid(myBattleground):
			myBattleground.placing_items = false
			for ship in myBattleground.ships:
				ship.canBeMoved = false

		state.visible = false
		start_button.disabled = true
		shuffle_button.modulate.a = 0
		shuffle_button.disabled = true

		# Let my_battleground_ready() decide:
		# - if opponent board is empty -> send_update() + wait
		# - if opponent board exists -> swap to opponent board + start gameplay
		my_battleground_ready()
		return

func _on_battle_ground_is_valid(valid: bool) -> void:
	start_button.disabled = not valid
	
func _do_hit_camera_shake(intensity: float = 6.0, duration: float = 0.25) -> void:
	var vp := get_viewport()
	if vp == null:
		return

	# Kill any existing shake and reset
	if _shake_tween and _shake_tween.is_running():
		_shake_tween.kill()
		vp.canvas_transform = Transform2D.IDENTITY

	_shake_tween = create_tween()

	_shake_tween.tween_method(
		func(alpha: float) -> void:
			# alpha goes from 1 → 0, so shake eases out
			var offset := Vector2(
				randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)
			) * intensity * alpha
			vp.canvas_transform = Transform2D(0.0, offset),
		1.0,
		0.0,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_shake_tween.tween_callback(func() -> void:
		vp.canvas_transform = Transform2D.IDENTITY
	)
	
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
		title_label.text = "How to Play Sea Battle"

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
[font_size={32px}][b]Sea Battle[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
• Take turns drawing single lines between adjacent dots.
• Complete the 4th side of a 1×1 box to claim it and score 1 point.
• The player with the most boxes when no lines remain wins.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• On your turn, draw exactly one horizontal or vertical line between two neighboring dots.
• If your line completes a box, that box is marked with an [b]X[/b] in your color and you immediately take another turn.
• If your line does not complete a box, play passes to your opponent.
• Boxes can be claimed in chains: if completing one box lets you complete another, you continue until you draw a line that doesn’t finish a box.
[/font_size]

[font_size={24px}][b]End of Game[/b][/font_size]
[font_size={18px}]
• The game ends when every possible line has been drawn.
• Each claimed box is worth 1 point. Higher total wins.
• Ties are possible.
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
