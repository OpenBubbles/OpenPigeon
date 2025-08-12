extends Control

var player_str: int     = 2
var game_settings_category: String
var player: int     = 1
var is_your_turn: bool = false
var is_my_turn: bool = false
var spectator_mode: bool = false
var mode: String = ""
var my_player: String = ""
const PIT_COUNT: int = 14
var avatar_key = 0
var _last_sown_pit: int = -1
var has_connected: bool = false
var offsets: Array[Vector2]
var _board_initialized: bool = false
var game_over: bool = false
var in_replay: bool = false
const BASE_STONE_SCALE := Vector2(0.1, 0.1)
var win_loss_state: String = ""
var winner_id = -1
var disp_winner = false
var _skip_replay_animation = false
var pits: Array = []
var pit_nodes: Array[Area2D] = []
var spawn_points: Array[Marker2D] = []
var board_labels: Array = []
var replay_moves: Array = []

var PitScene    : PackedScene = preload("res://mancala/pit.tscn")
var StoreScene  : PackedScene = preload("res://mancala/store.tscn")
var StoneScene : PackedScene = preload("res://mancala/stone.tscn")
const AvatarWinAnimScene := preload("res://avatar_textures/avatar_win_anim.tscn")

@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var rules_button    = %RulesButton
@onready var settings_button = %SettingsButton
@onready var sent_label = %SentLabel
@onready var waiting_label = %WaitForOpponentLabel
@onready var waiting_blur = %WaitBlur
@onready var dot_timer = %DotTimer
@onready var background = %Background
@onready var win_loss_label = %WinLossLabel
@onready var pits_root       = %PitsContainer
@onready var free_turn_label = %FreeTurnLabel
@onready var skip_button = %SkipButton
@onready var spec_label = %SpecLabel

const RULES_POPUP_SCENE = preload("res://mancala/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://settings_popup.tscn")

var _carrying_stones_container: Node2D = Node2D.new()
const STONE_DROP_DELAY = 0.1 # Time to pause after dropping each stone
const PIT_PICKUP_TIME = 0.3 # How long it takes for the pit to lift
const PILE_TRAVEL_TIME = 0.35 # Time for the entire pile to move between pits
const BOUNCE_SCALE_FACTOR = 1.3 # Stones will scale to 120% of their base size
const BOUNCE_DURATION = 0.01 # Duration for the initial bounce at pickup (for the very first pickup)
var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
var sent_tween: Tween

var _is_animating: bool = false
var moves_made: Array = []
var prev_board_str: String = ""

func _debug_pit_input_layers() -> void:
	for pit in pit_nodes:
		print("=== Pit", pit.index, "layers ===")
		for node in pit.get_children():
			var info = ""
			if node is CollisionShape2D:
				info = "CollisionShape2D, disabled=%s" % node.disabled
			elif node is Area2D:
				info = "Area2D, pickable=%s" % node.input_pickable
			elif node is Control:
				info = "Control, mouse_filter=%d" % node.mouse_filter
			else:
				info = "%s (%s)" % [node.get_class(), node.visible if node.has_method("is_visible") else ""]
			print("    ", node.name, "→", info)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Unhandled Click at: ", event.position)

func _ready() -> void:
	game_settings_category = SettingsManager.get_game_name_from_path(get_tree().current_scene.scene_file_path)
	print("Current game scene for settings: ", game_settings_category)
	_load_game_specific_settings()
	_init_mancala_board_structure()
	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin: 
		print("AppPlugin Available")
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
	else:
		print("[DEV] Editor hint active, loading sample game data")
		#var dev_data = """
		#{
			#"isYourTurn": true,
			#"mode": "n",
			#"player": "1",
			#"myPlayerId": "7482724F-12A2-4917-9EB3-8857DD4D44EAP3AIzX",
			#"replay": "board:2,3,2,3&&&&&&1,2,3,1,2,3,11,12,13,11,12,13,1,2,3,1,2,3,11,12,13,11,12,13&13,12,13,13,13&12&&&&13,11,11,13&1,2,3,1,2,3,11,12,13,1|move:2,6|board:2,3,2,3&&&&&&1,2,3,1,2,3,11,12,13,11,12,13,1,2,3,1,2,3,11,12,13,11,12,13&12,13,13,13&12,13&&&&13,11,11,13&1,2,3,1,2,3,11,12,13,1",
			#"player2": "7482724F-12A2-4917-9EB3-8857DD4D44EAP3AIzX",
			#"player1": "7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX",
			#"avatar1": "body,1|eyes,2|mouth,1|hair,1|clothes,2|bg_color,0.42,0.94,0.86|body_color,0.79,0.70,0.66|hair_color,0.43,0.25,0.12|clothes_color,0.22,0.80,0.69",
			#"avatar2": "body,3|eyes,1|mouth,1|hair,3|clothes,2|bg_color,0.42,0.94,0.86|body_color,0.79,0.70,0.66|hair_color,0.43,0.25,0.12|clothes_color,0.22,0.80,0.69",
			#"replay": "board:4,4,4,4,4,4&&4,4,4,4,4,4&",
			#"sender": "7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX",
			#"version": "5",
			#"tver": "5",
			#"ios": "18.5",
			#"subcaption": "Capture Mode",
			#"id": "ziadBSjDYgc4ruev"
		#}
		#"""		
		var dev_data = '{"isYourTurn": true,"mode": "n","player": "2","replay": "board:2,3,2,3&&&&&&1,2,3,1,2,3,11,12,13,11,12,13,1,2,3,1,2,3,11,12,13,11,12,13&13,12,13,13,13&12&&&&13,11,11,13&1,2,3,1,2,3,11,12,13,1|move:2,6|board:2,3,2,3&&&&&&1,2,3,1,2,3,11,12,13,11,12,13,1,2,3,1,2,3,11,12,13,11,12,13&12,13,13,13&12,13&&&&13,11,11,13&1,2,3,1,2,3,11,12,13,1","sender":"7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX","version": "5","tver": "5","ios": "18.5","subcaption": "Capture Mode","id": "ziadBSjDYgc4ruev","player2": "7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX"}'
		_set_game_data(dev_data)
	for pit in pit_nodes:
		for node in pit.get_children():
			if node is Control and node.name != "DebugRect":
				node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rules_button:
		rules_button.pressed.connect(on_rules_button_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)
	if skip_button:
		skip_button.pressed.connect(_on_skip_button_pressed)

	add_child(_carrying_stones_container)
	_carrying_stones_container.z_index = 90
	
func _apply_bg_for_dark(is_dark: bool, mode: String) -> void:
	if is_instance_valid(background):
		if is_dark:
			if mode == "an" or mode == "ah":
				background.color = Color("#261a19")
			else:
				background.color = Color("#202526")
		else:
			if mode == "an" or mode == "ah":
				background.color = Color("#704b4a")
			else:
				background.color = Color("#6d7c82")

func _set_game_data(raw_text: String) -> void:
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	var res = JSON.parse_string(raw_text)
	print("[PARSE] Raw game data received:", res)

	var my_id = res.get("myPlayerId", "")
	var p1_id = res.get("player1", "")
	var p2_id = res.get("player2", "")
	var opponent_avatar_key = ""

	if my_id != "" and p1_id != "" and p2_id != "":
		if my_id == p1_id:
			opponent_avatar_key = "avatar2"
			print("Opp is avatar2")
		elif my_id == p2_id:
			opponent_avatar_key = "avatar1"
			print("Opp is avatar1")
	
	if opponent_avatar_key != "" and res.has(opponent_avatar_key):
		var avatar_string = res[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
	player_str = int(res.get("player", player))
	mode = String(res.get("mode", mode))
	my_player = my_id
	var sender_id = res.get("sender", "")
	winner_id = res.get("winner", "")
	
	is_your_turn = res.get("isYourTurn", false)
	if (my_player == p1_id or my_player == p2_id or p1_id == ""):
		player = 1 if (player_str == 2 and is_my_turn) else 2
		print("193 Setting Player to ", player)
		if is_your_turn:
			is_my_turn = true	
	else:
		spectator_mode = true
		print("Spectator Mode Enabled!")
		spec_label.visible = true
		player = 1
		print("199 Setting Player to ", player)

	print("YOUR TURN?: ", is_your_turn, " MY TURN?: ", is_my_turn, " Spectator Mode: ", spectator_mode)
	
	_apply_bg_for_dark(is_dark, mode)

	var replay_str: String = String(res.get("replay", ""))
	_apply_board_layout(is_my_turn)
	var parsed = parse_game_data(replay_str)
	var initial_board_for_replay_str = ""
	var rb: Array = parsed.get("raw_boards", [])
	if rb.size() > 0:
		initial_board_for_replay_str = rb[0]
	else:
		push_warning("_set_game_data: no initial board state found for replay.")

	pits.clear()
	for i in range(PIT_COUNT):
		pits.append([])

	if initial_board_for_replay_str != "":
		var initial_board_data = _parse_single_board(initial_board_for_replay_str)
		for i in range(min(initial_board_data.size(), PIT_COUNT)):
			pits[i] = initial_board_data[i].duplicate()
		_refresh_all_pits()
	else:
		push_warning("_set_game_data: no previous board state found for replay, using default setup.")

	if parsed.moves.size() > 0:
		replay_moves = parsed.moves
		_is_animating = true
		skip_button.visible = true
		for i in range(replay_moves.size()):
			if _skip_replay_animation:
				break
			var move_data = replay_moves[i]
			var replay_player = int(move_data[0])
			var replay_pit_offset = int(move_data[1])
			var actual_pit_idx = replay_pit_offset
			if replay_player == 2:
				actual_pit_idx += 7
			var original_player_str_for_sow = player_str
			player_str = replay_player
			in_replay = true
			await _sow_from(actual_pit_idx)
			in_replay = false
			var current_sow_player_store_idx = 6 if player_str == 1 else 13
			if _last_sown_pit == current_sow_player_store_idx:
				free_turn_label.text = "Free Turn!"
				free_turn_label.visible = true
				var free_turn_tween = create_tween()
				free_turn_tween.tween_interval(0.8)
				free_turn_tween.tween_callback(func(): free_turn_label.visible = false)
				await free_turn_tween.finished
			player_str = original_player_str_for_sow
		skip_button.visible = false
		_is_animating = false
		if rb.size() > 1:
			var final_board_data = _parse_single_board(rb[rb.size() - 1])
			for k in range(min(final_board_data.size(), PIT_COUNT)):
				pits[k] = final_board_data[k].duplicate()
			if _skip_replay_animation:
				_refresh_all_pits()
		else:
			push_warning("_set_game_data: No final board state (rb[1]) available for post-replay update.")
		_skip_replay_animation = false
		prev_board_str = rb[rb.size() - 1] if rb.size() > 0 else ""
	elif rb.size() > 0:
		prev_board_str = rb[0]
	
	await _check_game_over_and_winner()
	if is_my_turn and not game_over:
		_start_pit_highlights()
		stop_waiting_animation()
	elif not is_my_turn and not game_over:
		start_waiting_animation()

func parse_game_data(raw: String) -> Dictionary:
	var out = {
		"boards": [],
		"moves": [],
		"raw_boards": []
	}

	for chunk in raw.strip_edges().split("|"):
		if chunk.begins_with("board:"):
			var board_str = chunk.substr(6)
			out["raw_boards"].append(board_str)
			out["boards"].append(_parse_single_board(board_str))
		elif chunk.begins_with("move:"):
			var mv: Array = []
			for s in chunk.substr(5).split(","):
				if s != "":
					mv.append(float(s))
			out["moves"].append(mv)

	return out
	
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
				data["hair_style"] = hair_map[int(values[0])]
			"body":
				data["body_style"] = body_map[int(values[0])]
			"eyes":
				data["eyes_style"] = eyes_map[int(values[0])]
			"mouth":
				data["mouth_style"] = mouth_map[int(values[0])]
			"clothes":
				data["clothing_style"] = clothing_map[int(values[0])]
			"backdrop":
				var backdrop_index = int(values[0])
				if backdrop_index >= 0 and backdrop_index < backdrop_map.size():
					data["bg_style"] = backdrop_map[backdrop_index]
			"bg_color", "body_color", "hair_color", "clothes_color":
				if values.size() >= 3:
					var color_key = key.replace("_color", "") + "_color"
					data[color_key] = Color(float(values[0]), float(values[1]), float(values[2]))

	return data

func _parse_single_board(data: String) -> Array:
	var pit_list = []
	for pit_str in data.split("&"):
		if pit_str == "":
			pit_list.append([])
		else:
			var arr = []
			for lbl in pit_str.split(","):
				if lbl != "": arr.append(int(lbl))
			pit_list.append(arr)
	return pit_list
	
func _on_plugin_set_game_data(raw_text: String) -> void:
	call_deferred("_set_game_data", raw_text)

func _init_mancala_board_structure() -> void:
	randomize()
	for i in range(PIT_COUNT):
		var pit: Area2D
		if i == 6 or i == 13:
			pit = StoreScene.instantiate() as Area2D
			pit.name = "Store%d" % i
		else:
			pit = PitScene.instantiate() as Area2D
			pit.name = "Pit%d" % i
		pit.index = i
		pit.connect("pit_clicked", Callable(self, "_on_pit_clicked"))
		pits_root.add_child(pit)
		pit_nodes.append(pit)
		spawn_points.append(pit.get_node("SpawnPoint") as Marker2D)
		var debug_label = pit.find_child("Debug_num")
		if debug_label and debug_label is Label:
			debug_label.text = str(i)
		else:
			print("No Label for Debug!")
		
	pits.clear()
	for i in range(PIT_COUNT):
		pits.append([])

	print("Mancala board structure initialized.")
	dot_timer.timeout.connect(_on_dot_timer_timeout)

func _apply_board_layout(is_current_turn: bool) -> void:
	print("YOU ARE PLAYER: ", player)
	if player == 1:
		offsets = [
			Vector2(125, 171.5), Vector2(125, 262.5), Vector2(125, 355.5),
			Vector2(125, 446.5), Vector2(125, 537.5), Vector2(125, 629.5),
			Vector2(170, 723.5), # Store
			Vector2(223, 629.5), Vector2(223, 537.5), Vector2(223, 446.5),
			Vector2(223, 355.5), Vector2(223, 262.5), Vector2(223, 171.5),
			Vector2(170, 75.5) # Store
		]
	elif player == 2:
		offsets = [
			Vector2(223, 629.5), Vector2(223, 537.5), Vector2(223, 446.5),
			Vector2(223, 355.5), Vector2(223, 262.5), Vector2(223, 171.5),
			Vector2(170, 75.5), # Store
			Vector2(125, 171.5), Vector2(125, 262.5), Vector2(125, 355.5),
			Vector2(125, 446.5), Vector2(125, 537.5), Vector2(125, 629.5),
			Vector2(170, 723.5) # Store
		]
	else:
		print("Cannot Setup Board!! (Player or turn info missing)")
	for i in range(PIT_COUNT):
		if i < pit_nodes.size() and i < offsets.size():
			pit_nodes[i].position = offsets[i]

	for i in range(PIT_COUNT):
		if i == 6 or i == 13:
			pits[i] = []
		else:
			var initial_stones: Array[int] = []
			var base_label = 0
			if i >= 0 and i <= 5:
				base_label = 1
			elif i >= 7 and i <= 12:
				base_label = 11

			for _k in range(4):
				initial_stones.append(base_label + (_k % 3))
			pits[i] = initial_stones

	print("Board layout applied and initial stones set.")
	if is_my_turn:
		_start_pit_highlights()
		stop_waiting_animation()

func _start_pit_highlights() -> void:
	print("Starting Pit Highlights! Player: ", player)
	for pit in pit_nodes:
		(pit.get_node("HighlightCircle") as ColorRect).visible = false
	var first = 0 if player == 1 else 7
	var last  = 5 if player == 1 else 12
	for i in range(first, last + 1):
		var hl = pit_nodes[i].get_node("HighlightCircle") as ColorRect
		hl.visible = true
		var mat = hl.material as ShaderMaterial
		mat.set_shader_parameter("alpha_fade", 0.0)
		var tw = hl.create_tween()
		tw.set_loops()
		tw.tween_property(mat, "shader_parameter/alpha_fade", 0.2, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(mat, "shader_parameter/alpha_fade", 0.0, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			
func _stop_pit_highlights() -> void:
	print("Stopped Pit Highlights!!")
	for pit in pit_nodes:
		var hl = pit.get_node("HighlightCircle") as ColorRect
		hl.visible = false

func _on_pit_clicked(idx: int) -> void:
	if _is_animating:
		return
	if game_over:
		print("Game is over. No more moves.")
		return
		
	_stop_pit_highlights()

	print("Pit clicked: ", idx)
	if not is_my_turn:
		print("Not your turn.")
		return

	var my_store_pit_idx = 6 if player_str == 1 else 13
	if ((player == 1 and (idx < 0 or idx > 5)) or (player == 2 and (idx < 7 or idx > 12))):
		print("Cannot click opponent's pit or a store pit.")
		_start_pit_highlights()
		return
	if pits[idx].size() == 0:
		print("Cannot click an empty pit.")
		_start_pit_highlights()
		return
		
	var pit_offset: int = idx if idx < 6 else idx - 7
	moves_made.append(str(player) + "," + str(pit_offset))

	print("[INPUT] Pit clicked:", idx)
	_is_animating = true

	var start_pit_node = pit_nodes[idx]
	_carrying_stones_container.global_position = start_pit_node.global_position

	var tween_pickup_scale = create_tween()
	tween_pickup_scale.set_parallel(true)

	tween_pickup_scale.tween_property(
		_carrying_stones_container, "scale",
		Vector2(1.2, 1.2),
		PIT_PICKUP_TIME * 0.7
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	await tween_pickup_scale.finished
	await _sow_from(idx)

	var give_free_turn = false
	if _last_sown_pit != -1:
		if _last_sown_pit == 6 or _last_sown_pit == 13:
			give_free_turn = true
			print("DEBUG: Last stone landed in own store pit → free turn!")
		else:
			print("DEBUG: Last stone landed in pit ", _last_sown_pit, " (not a store pit for free turn).")
	else:
		print("DEBUG: No stone was sown (this shouldn't happen after _sow_from).")

	if give_free_turn:
		is_my_turn = true
		free_turn_label.text = "Free Turn."
		free_turn_label.visible = true
		var free_turn_tween = create_tween()
		free_turn_tween.tween_interval(1.0)
		free_turn_tween.tween_callback(func(): free_turn_label.visible = false)
	else:
		_end_turn()
		
	_is_animating = false
	if is_my_turn:
		_start_pit_highlights()

func _sow_from(start_idx: int) -> void:
	var current_sowing_pit_idx = start_idx
	var last_stone_landed_in_empty_pit = false
	
	while true:
		if _skip_replay_animation:
			print("Sow from interrupted by skip button.")
			break

		var current_sow_player = player_str
		if not in_replay and is_my_turn:
			current_sow_player = player
		else:
			print("SOW STATS!!!!~~ IS ANIMATING: ", _is_animating, " IS MY TURN: ", is_my_turn, " CURRENT SOW PLAYER: ", current_sow_player, " IN_REPLAY: ", in_replay, " PLAYER_STR: ", player_str," PLAYER: ", player)

		var player1_side_empty = true
		for i in range(0, 6):
			if pits[i].size() > 0:
				player1_side_empty = false
				break
		var player2_side_empty = true
		for i in range(7, 13):
			if pits[i].size() > 0:
				player2_side_empty = false
				break

		if (current_sow_player == 1 and player1_side_empty) or (current_sow_player == 2 and player2_side_empty):
			print("GAME OVER: Current sowing player's pits are all empty before sowing from ", current_sowing_pit_idx)
			var opponent_store_idx = 6 if current_sow_player == 2 else 13
			for i in range(PIT_COUNT):
				var is_opponents_non_store_pit = (current_sow_player == 1 and i >= 7 and i <= 12) or \
												 (current_sow_player == 2 and i >= 0 and i <= 5)
				
				if is_opponents_non_store_pit:
					if pits[i].size() > 0:
						print("Moving ", pits[i].size(), " stones from pit ", i, " to opponent's store ", opponent_store_idx)
						pits[opponent_store_idx].append_array(pits[i])
						pits[i].clear()
						print("476 refresh count label call")
						_refresh_pit_count_label(i)
						_refresh_pit_count_label(opponent_store_idx)
			print("483 check game over")
			return

		if pits[current_sowing_pit_idx].size() == 0:
			last_stone_landed_in_empty_pit = true
			break
		
		var stones_to_sow = pits[current_sowing_pit_idx].size()
		if stones_to_sow == 0:
			last_stone_landed_in_empty_pit = true
			break
			
		var start_pit_node = pit_nodes[current_sowing_pit_idx]
		var start_container = start_pit_node.get_node("StonesContainer") as Node2D

		var carried_stone_labels: Array = pits[current_sowing_pit_idx].duplicate()
		for c in start_container.get_children():
			c.queue_free()
		pits[current_sowing_pit_idx].clear()
		print("502 refresh count label call")
		_refresh_pit_count_label(current_sowing_pit_idx)
		var current_idx = current_sowing_pit_idx
		var carried_visual_stones: Array[Node2D] = []
		for stone_label in carried_stone_labels:
			var s = StoneScene.instantiate() as Node2D
			s.scale = BASE_STONE_SCALE
			s.modulate = _get_color_from_label(stone_label)
			s.position = Vector2(randf_range(-5, 5), randf_range(-5, 5))
			_carrying_stones_container.add_child(s)
			carried_visual_stones.append(s)

		await get_tree().create_timer(0.01).timeout
		print("DEBUG: pits_root global_position: ", pits_root.global_position)
		print("DEBUG: start_pit_node local position: ", start_pit_node.global_position, " Current Sowing Pit Index: ", current_sowing_pit_idx)
		_carrying_stones_container.global_position = start_pit_node.global_position
		print("DEBUG: Carrying container set to start pit position: ", _carrying_stones_container.global_position, " (start_pit_node global: ", start_pit_node.global_position, ")")
		
		var pickup_tween = create_tween()
		if pickup_tween == null:
			push_error("pickup_tween is null during initial pickup! Aborting.")
			return

		pickup_tween.tween_property(_carrying_stones_container, "scale", Vector2(BOUNCE_SCALE_FACTOR, BOUNCE_SCALE_FACTOR), BOUNCE_DURATION / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pickup_tween.tween_property(_carrying_stones_container, "scale", Vector2(1.0, 1.0), BOUNCE_DURATION / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await pickup_tween.finished
		print("DEBUG: Carrying container position after pickup tween: ", _carrying_stones_container.global_position)
		while carried_visual_stones.size() > 0:
			if _skip_replay_animation:
				print("Stone distribution interrupted by skip button.")
				for c in _carrying_stones_container.get_children():
					c.queue_free()
				return
				
			current_idx = (current_idx + 1) % PIT_COUNT

			if (current_sow_player == 1 and current_idx == 13) or (current_sow_player == 2 and current_idx == 6):
				continue

			var target_pit_node = pit_nodes[current_idx]
			var target_global_position_for_pile = target_pit_node.global_position
			print("DEBUG: Moving to target pit ", current_idx, " at global position: ", target_global_position_for_pile)

			var travel_tween = create_tween()
			if travel_tween == null:
				push_error("travel_tween is null during movement! Aborting sowing animation.")
				return

			travel_tween.tween_property(_carrying_stones_container, "global_position", target_global_position_for_pile, PILE_TRAVEL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			travel_tween.set_parallel(true)
			travel_tween.tween_property(_carrying_stones_container, "scale", Vector2(BOUNCE_SCALE_FACTOR, BOUNCE_SCALE_FACTOR), PILE_TRAVEL_TIME / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			travel_tween.tween_property(_carrying_stones_container, "scale", Vector2(1.0, 1.0), PILE_TRAVEL_TIME / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(PILE_TRAVEL_TIME / 2.0)
			await travel_tween.finished
			print("DEBUG: Carrying container position after travel tween to pit ", current_idx, ": ", _carrying_stones_container.global_position)
			if _skip_replay_animation:
				print("Stone distribution interrupted after travel by skip button.")
				for c in _carrying_stones_container.get_children():
					c.queue_free()
				return

			var stone_to_drop_visual = carried_visual_stones.pop_front() as Node2D
			var dropped_stone_label = carried_stone_labels.pop_front()

			if stone_to_drop_visual:
				_carrying_stones_container.remove_child(stone_to_drop_visual)
				
				var drop_target_local_pos = spawn_points[current_idx].position + Vector2(randf_range(-15, 15), randf_range(-15, 15))
				
				target_pit_node.get_node("StonesContainer").add_child(stone_to_drop_visual)
				stone_to_drop_visual.position = drop_target_local_pos
				stone_to_drop_visual.rotation_degrees = randf_range(0, 360)

				var shadow = Sprite2D.new()
				shadow.texture = stone_to_drop_visual.texture
				shadow.modulate = Color(0, 0, 0, 0.3)
				shadow.position = drop_target_local_pos + Vector2(5, 5)
				shadow.z_index = -1
				target_pit_node.get_node("StonesContainer").add_child(shadow)

				pits[current_idx].append(dropped_stone_label)
				print("564 refresh count label call")
				_refresh_pit_count_label(current_idx)

				if carried_visual_stones.size() > 0:
					await get_tree().create_timer(STONE_DROP_DELAY / 2.0).timeout
					if _skip_replay_animation:
						print("Stone distribution interrupted during delay by skip button.")
						for c in _carrying_stones_container.get_children():
							c.queue_free()
						return

		_last_sown_pit = current_idx

		# Avalanche Mode Logic
		if mode == "an" or mode == "ah":
			print("Avalanche mode active. Last stone landed in pit: ", _last_sown_pit)
			var player_store_idx = 6 if current_sow_player == 1 else 13
			
			if _last_sown_pit == player_store_idx:
				print("Avalanche ends: Last stone landed in player's store.")
				break
			
			if pits[_last_sown_pit].size() == 1:
				print("Avalanche ends: Last stone landed in an empty pit (now 1 stone).")
				last_stone_landed_in_empty_pit = true
				break
			
			print("Avalanche continues: Picking up stones from pit ", _last_sown_pit)
			if current_sowing_pit_idx == 6 or current_sowing_pit_idx == 13:
				break
			current_sowing_pit_idx = _last_sown_pit
		else:
			var last_sown_pit_is_non_store = (_last_sown_pit >= 0 and _last_sown_pit <= 5) or (_last_sown_pit >= 7 and _last_sown_pit <= 12)
			var should_capture = false
			if not in_replay:
				if current_sow_player == 1 and _last_sown_pit >= 0 and _last_sown_pit <= 5 and pits[_last_sown_pit].size() == 1:
					should_capture = true
				elif current_sow_player == 2 and _last_sown_pit >= 7 and _last_sown_pit <= 12 and pits[_last_sown_pit].size() == 1:
					should_capture = true
			else:
				if current_sow_player == 1 and _last_sown_pit >= 0 and _last_sown_pit <= 5 and pits[_last_sown_pit].size() == 1:
					should_capture = true
				elif current_sow_player == 2 and _last_sown_pit >= 7 and _last_sown_pit <= 12 and pits[_last_sown_pit].size() == 1:
					should_capture = true

			if should_capture:
				print("DEBUG: Capture condition met! Last stone landed in pit ", _last_sown_pit, " which was empty before this stone.")
				
				var opposite_pit_idx = -1
				if current_sow_player == 1:
					opposite_pit_idx = 12 - _last_sown_pit
				elif current_sow_player == 2:
					opposite_pit_idx = 12 - _last_sown_pit

				var player_store_idx = 6 if current_sow_player == 1 else 13

				if opposite_pit_idx != -1 and pits[opposite_pit_idx].size() > 0:
					print("DEBUG: Capturing stones from opposite pit ", opposite_pit_idx)

					var captured_stones = []
					if pits[_last_sown_pit].size() > 0:
						captured_stones.append(pits[_last_sown_pit].pop_back())
					captured_stones.append_array(pits[opposite_pit_idx])
					pits[opposite_pit_idx].clear()
					print("DEBUG: Displaying 'Captured!' label for live player.")
					free_turn_label.text = "Captured!"
					free_turn_label.visible = true
					var free_turn_tween = create_tween()
					free_turn_tween.tween_interval(0.5)
					free_turn_tween.tween_callback(func(): free_turn_label.visible = false)
					free_turn_label.add_theme_color_override("font_color", Color(1, 1, 1))
					free_turn_label.add_theme_color_override("background_color", Color(1.0, 0.84, 0.0))
					await _animate_capture(captured_stones, _last_sown_pit, opposite_pit_idx, player_store_idx)
					if _skip_replay_animation:
						print("Capture animation interrupted by skip button.")
						return
					pits[player_store_idx].append_array(captured_stones)
					print("626 refresh count label call")
					_refresh_pit_count_label(_last_sown_pit)
					_refresh_pit_count_label(opposite_pit_idx)
					_refresh_pit_count_label(player_store_idx)
				else:
					print("DEBUG: Opposite pit ", opposite_pit_idx, " is empty or invalid. No capture.")
			break
	for child in _carrying_stones_container.get_children():
		child.queue_free()
	_carrying_stones_container.scale = Vector2(1.0, 1.0)
	
	await _check_game_over_and_winner()

func _animate_capture(stones_to_capture: Array, last_sown_pit_idx: int, opposite_pit_idx: int, player_store_idx: int) -> void:
	print("Animating capture of ", stones_to_capture.size(), " stones to store ", player_store_idx)
	
	var store_node = pit_nodes[player_store_idx]
	var store_container = store_node.get_node("StonesContainer") as Node2D

	var last_sown_pit_node = pit_nodes[last_sown_pit_idx]
	var opposite_pit_node = pit_nodes[opposite_pit_idx]
	var visual_stones_from_last_sown = []
	var ls_container = last_sown_pit_node.get_node("StonesContainer")
	for child in ls_container.get_children():
		if child is Node2D:
			visual_stones_from_last_sown.append(child)
	var visual_stones_from_opposite = []
	var opp_container = opposite_pit_node.get_node("StonesContainer")
	for child in opp_container.get_children():
		if child is Node2D:
			visual_stones_from_opposite.append(child)
	var all_visual_stones_to_capture = visual_stones_from_last_sown + visual_stones_from_opposite
	
	for s_visual in visual_stones_from_last_sown:
		ls_container.remove_child(s_visual)
		_carrying_stones_container.add_child(s_visual)
		s_visual.global_position = last_sown_pit_node.global_position
	
	for s_visual in visual_stones_from_opposite:
		opp_container.remove_child(s_visual)
		_carrying_stones_container.add_child(s_visual)
		s_visual.global_position = opposite_pit_node.global_position
	
	print("681 refresh count label call")
	_refresh_pit_count_label(last_sown_pit_idx)
	_refresh_pit_count_label(opposite_pit_idx)
	var capture_tween = create_tween()
	if capture_tween == null:
		push_error("capture_tween is null during capture animation!")
		for s_visual in all_visual_stones_to_capture:
			s_visual.queue_free()
		return
	var target_global_pos_for_capture = store_node.global_position
	target_global_pos_for_capture.y

	capture_tween.tween_property(
		_carrying_stones_container, "global_position",
		target_global_pos_for_capture,
		PILE_TRAVEL_TIME * 1.5
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	await capture_tween.finished
	for s_visual in all_visual_stones_to_capture:
		if s_visual:
			_carrying_stones_container.remove_child(s_visual)
			store_container.add_child(s_visual)
			s_visual.position = spawn_points[player_store_idx].position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
			s_visual.rotation_degrees = randf_range(0, 360)

			var shadow = Sprite2D.new()
			shadow.texture = s_visual.texture
			shadow.modulate = Color(0, 0, 0, 0.3)
			shadow.scale = s_visual.scale * 1.05
			shadow.position = s_visual.position + Vector2(5, 5)
			shadow.z_index = -1
			store_container.add_child(shadow)
		await get_tree().create_timer(STONE_DROP_DELAY / (all_visual_stones_to_capture.size() + 1)).timeout

	for child in _carrying_stones_container.get_children():
		child.queue_free()
	
	print("Capture animation finished.")

func _end_turn() -> void:
	avatar_key = "avatar" + str(player)
	player = 1 if player==2 and not spectator_mode else 2
	free_turn_label.visible = false

	send_game()

func _refresh_all_pits() -> void:
	for i in range(PIT_COUNT): _refresh_pit(i)

func _refresh_pit(i: int) -> void:
	var pit = pit_nodes[i]
	var container = pit.get_node("StonesContainer") as Node2D

	for c in container.get_children():
		c.queue_free()
	
	for stone_label in pits[i]:
		var s = StoneScene.instantiate() as Node2D
		s.scale = BASE_STONE_SCALE
		s.modulate = _get_color_from_label(stone_label)
		s.rotation_degrees = randf_range(0, 360) 

		s.position = spawn_points[i].position + Vector2(
			randf_range(-20, 20),
			randf_range(-20, 20)
		)
		
		container.add_child(s)

		var shadow = Sprite2D.new()
		shadow.texture = s.texture
		shadow.modulate = Color(0, 0, 0, 0.3)
		shadow.scale = s.scale * 1.05
		shadow.position = s.position + Vector2(5, 5)
		shadow.z_index = s.z_index - 1
		container.add_child(shadow)

	print("772 refresh count label call")
	_refresh_pit_count_label(i)

func _get_color_from_label(label: int) -> Color:
	match label:
		1, 11: return Color("#fffcf2") # Creamy white
		2, 12: return Color("#414851") # Jet gray
		3, 13: return Color("#176cab") # Bright blue (Google blue)
		_: return Color(randf_range(0.9, 1.0), randf_range(0.9, 1.0), randf_range(0.9, 1.0))

func _refresh_pit_count_label(i: int) -> void:
	var pit = pit_nodes[i]
	var lbl = pit.get_node("CountLabel") as Label
	lbl.text = str(pits[i].size())
	lbl.get_parent().force_update_transform()
	var lw = lbl.get_minimum_size().x
	var lh = lbl.get_minimum_size().y
	var base = spawn_points[i].position
	const OFFX = 40
	const OFFY = 10
	const Mx = 50
	const My = 50
	print("REFRESH COUNT:: PLAYER: ", player, " Pit Number: ", i, " In Replay?: ", in_replay)
	if player == 1:
		if i == 6 or i == 13:
			if i == 6:
				lbl.position = base + Vector2(-Mx - lw/2 - OFFX, My - lh/2 - OFFY)
			else:
				lbl.position = base + Vector2(Mx - lw/2 + OFFX, -My - lh/2 + OFFY)
		else:
			lbl.scale = Vector2(1,1)
			if i < 6:
				lbl.position = base + Vector2(-Mx - lw/2, -lh/2)
			else:
				lbl.position = base + Vector2(Mx - lw/2, -lh/2)
	elif player == 2:
		if i == 6 or i == 13:
			if i == 6:
				lbl.position = base + Vector2(Mx - lw/2 + OFFX,  -My - lh/2 + OFFY)
			else:
				lbl.position = base + Vector2(-Mx - lw/2 - OFFX, My - lh/2 - OFFY)
		else:
			lbl.scale = Vector2(1,1)
			if i < 6:
				lbl.position = base + Vector2(Mx - lw/2, -lh/2)
			else:
				lbl.position = base + Vector2(-Mx - lw/2, -lh/2)
	else:
		print("Shouldn't Update Label as it is not my turn")

func _place_stone(container: Node2D, base_pos: Vector2, label: int) -> void:
	pass
	
func send_game() -> void:
	print("Send Game Called!")
	is_my_turn = false
	var all_moves = ""
	for m in moves_made:
		all_moves += "move:" + m + "|"
	moves_made.clear()

	var post_board_str = "board:"
	for i in range(pits.size()):
		var pit = pits[i]
		if pit.size() > 0:
			for j in range(pit.size()):
				post_board_str += str(pit[j])
				if j < pit.size() - 1:
					post_board_str += ","
		
		if i < pits.size() - 1:
			post_board_str += "&"
	
	var payload = {
		"replay": "board:" + prev_board_str + "|" + all_moves + post_board_str
	}
	
	if player != 0 and is_instance_valid(player_avatar_display):
		var avatar_string = player_avatar_display.get_avatar_data_string()
		payload[avatar_key] = avatar_string
		print("Adding my avatar data to payload with key '", avatar_key, "'")
	
	print("PAYLOAD: ", payload)
	if await _check_game_over_and_winner():
		print("Check Win 863 my_player: ", my_player, " win_loss_state: ", win_loss_state)
		if game_over == true and not spectator_mode:
			payload["winner"] = my_player + "|" + win_loss_state
	var game_data = JSON.stringify(payload)
	print("Game data being sent: " + game_data)

	var appPlugin := Engine.get_singleton("AppPlugin")
	if not spectator_mode:
		if appPlugin:
			print("Attempting to send game data via AppPlugin.")
			appPlugin.updateGameData(game_data)
		else:
			print("AppPlugin is null. Cannot send game data.")
		play_sent_animation()
		
func _check_game_over_and_winner() -> bool:

	print("Checking for game over condition...")
	var is_game_over_condition_met = false

	if not game_over:
		var player1_store_count = pits[6].size()
		var player2_store_count = pits[13].size()
		print("PLAYER 1 STORE QTY: ", player1_store_count, " | PLAYER 2 STORE QTY: ", player2_store_count)

		var player1_side_empty = true
		for i in range(0, 6):
			if pits[i].size() > 0:
				player1_side_empty = false
				break
		var player2_side_empty = true
		for i in range(7, 13):
			if pits[i].size() > 0:
				player2_side_empty = false
				break
		
		if player1_side_empty or player2_side_empty:
			print("Game over: One player's side is empty.")
			is_game_over_condition_met = true

			if mode == "an" or mode == "ah":
				if player1_side_empty:
					print("Player 1's side is empty. Moving remaining stones from Player 2's side to Player 2's store.")
					for i in range(7, 13):
						if pits[i].size() > 0:
							pits[13].append_array(pits[i])
							pits[i].clear()
							print("903 refresh count label call")
							_refresh_pit_count_label(i)
					print("905 refresh count label call")
					_refresh_pit_count_label(13)
				elif player2_side_empty:
					print("Player 2's side is empty. Moving remaining stones from Player 1's side to Player 1's store.")
					for i in range(0, 6):
						if pits[i].size() > 0:
							pits[6].append_array(pits[i])
							pits[i].clear()
							print("913 refresh count label call")
							_refresh_pit_count_label(i)
					print("915 refresh count label call")
					_refresh_pit_count_label(6)
	
	if is_game_over_condition_met and not game_over:
		game_over = true

		print("Final scores: Player 1 (store 6): ", pits[6].size(), ", Player 2 (store 13): ", pits[13].size())
		var local_winner = -1
		if pits[6].size() > pits[13].size():
			local_winner = 1
		elif pits[13].size() > pits[6].size():
			local_winner = 2
		winner_id = local_winner

			
	if game_over and winner_id != -1 and not disp_winner:
		print("Setting Game_Over_State")
		disp_winner = true
		if winner_id == -1:
			win_loss_label.text = "DRAW!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
			win_loss_state = "0"
		elif (player == 1 and winner_id == 1) or (player == 2 and winner_id == 2):
			_show_win_burst(player_avatar_display)
			if not spectator_mode:
				win_loss_label.text = "YOU WIN!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			else:
				win_loss_label.text = "Player 1 Wins!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			win_loss_state = "1"
		else:
			_show_win_burst(opp_avatar_display)
			if not spectator_mode:
				win_loss_label.text = "YOU LOSE"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			else:
				win_loss_label.text = "Player 2 Wins!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			win_loss_state = "-1"
		win_loss_label.visible = true
		await get_tree().process_frame
		win_loss_label.scale = Vector2.ZERO
		win_loss_label.pivot_offset = win_loss_label.size / 2

		var tween_in = create_tween()
		tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		await tween_in.finished
		
	return game_over
	
	
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
	
func _on_skip_button_pressed() -> void:
	if in_replay:
		print("Skip button pressed during replay!")
		_skip_replay_animation = true	

func on_rules_button_pressed() -> void:
	rules_button.pivot_offset = rules_button.size / 2.0
	var tween = create_tween()
	tween.tween_property(rules_button, "scale", Vector2(1.3, 1.3), 0.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(rules_button, "scale", Vector2.ONE, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	var popup = RULES_POPUP_SCENE.instantiate()
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root = get_tree().root
	root.add_child(dim)
	root.add_child(popup)

	popup.z_index = 100
	dim.z_index = 99

	root.move_child(dim, root.get_child_count() - 2)

	var close_btn = popup.get_node("MarginContainer/PanelContainer/VBoxContainer/HeaderMarginContainer/HBoxContainer/MarginContainer/CloseButton")
	if close_btn:
		close_btn.pressed.connect(func():
			dim.queue_free()
			popup.queue_free()
		)

	var rules_label = popup.get_node("MarginContainer/PanelContainer/VBoxContainer/RulesLabel") as RichTextLabel
	if rules_label:
		rules_label.bbcode_enabled = true
		rules_label.visible = true
		rules_label.fit_content_height = true
		rules_label.scroll_active = false
		rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rules_label.text = _get_rules_text_for_mode(mode)

	popup.set_as_top_level(true)
	popup.visible = true

	await get_tree().process_frame

	var viewport_size = get_viewport_rect().size
	var desired_width = viewport_size.x * 0.9
	var desired_height = popup.get_combined_minimum_size().y
	
	popup.size = Vector2(desired_width, desired_height)
	popup.set_pivot_offset(popup.size / 2)
	popup.position = (viewport_size / 2) - (popup.size / 2)
	popup.scale = Vector2.ZERO

	var popup_tween = create_tween()
	popup_tween.tween_property(popup, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	popup.grab_focus()
	
func _get_rules_text_for_mode(mode: String) -> String:
	match mode:
		"n", "h":
			return """
[font_size={32px}][b]Capture Mode[/b][/font_size]

[font_size={24px}][b]Rules:[/b][/font_size]
[font_size={18px}]
1. Each player has a store on one side of the board.

2. Players take turns choosing a pile from one of the holes. Moving counter-clockwise, stones from the selected pile are deposited in each of the following holes until you run out of stones.

3. If you drop the last stone into your store - you get a free turn.

4. If you drop the last stone into an empty hole on your side of the board - you can capture stones from the hole on the opposite side.

5. The game ends when all six holes on either side of the board are empty. If a player has any stones on their side of the board when the game ends - they will capture all of those stones.
[/font_size]
[font_size={24px}][b]Goal:[/b][/font_size]
[font_size={18px}]
Player with the most stones in thir store wins. 
[/font_size]
"""
		"an", "ah":
			return """
[font_size={32px}][b]Avalanche Mode[/b][/font_size]

[font_size={24px}][b]Rules:[/b][/font_size]
[font_size={18px}]
1. Each player has a store on one side of the board.

2. Players take turns choosing a pile from one of the holes. Moving counter-clockwise, stones from the selected pile are deposited in each of the following holes until you run out of stones.

3. If you drop the last stone into an unempty hole, you will pick up the stones from that hole and continue depositing them counter-clockwise.

4. You turn is over when you drop the last stone into an empty hole.

5. If you drop the last stone into your store - you get a free turn.

5. The game ends when all six holes on either side of the board are empty. If a player has any stones on their side of the board when the game ends - they will capture all of those stones.
[/font_size]
[font_size={24px}][b]Goal:[/b][/font_size]
[font_size={18px}]
Player with the most stones in thir store wins.
[/font_size]
"""
		_:
			return """
[b][font_size=22]Unknown Mode[/font_size][/b]

[b]Rules:[/b]

No rule info found for this mode.
"""

func play_sent_animation():
	if sent_label:
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
			sent_label.text = "Sent ✔"
		)

		sent_tween.tween_interval(2.0)
		sent_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)

		sent_tween.tween_callback(func():
			sent_label.visible = false
			sent_label.modulate.a = 1.0
			start_waiting_animation()
		)
 
func start_waiting_animation():
	print("Starting Waiting Animation 826")
	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true
	waiting_blur.visible = true

	waiting_label.modulate.a = 0.0
	waiting_blur.modulate.a = 0.0

	var tween = create_tween().set_parallel(true)
	tween.tween_property(waiting_label, "modulate:a", 1.0, 0.3)
	tween.tween_property(waiting_blur, "modulate:a", 1.0, 0.3)

	dot_timer.start()


func stop_waiting_animation():
	dot_timer.stop()
	waiting_label.visible = false
	waiting_blur.visible = false
	
func _on_dot_timer_timeout():
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots

func _on_settings_button_pressed() -> void:
	settings_button.pivot_offset = settings_button.size / 2.0
	var tween = create_tween()
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

	var volume_setting_hbox = HBoxContainer.new()
	volume_setting_hbox.add_child(Label.new())
	volume_setting_hbox.get_child(0).text = "Game Volume:"
	volume_setting_hbox.get_child(0).set_h_size_flags(Control.SIZE_EXPAND_FILL)

	var volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	
	var saved_volume = SettingsManager.get_setting(game_settings_category, "master_volume", 0.75)
	volume_slider.value = saved_volume

	volume_slider.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	volume_slider.value_changed.connect(func(value):
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))
		print("Master Volume: ", value)
		SettingsManager.set_setting(game_settings_category, "master_volume", value)
	)
	volume_setting_hbox.add_child(volume_slider)

	settings_popup_script.add_custom_setting(volume_setting_hbox)
	
	var toggle_debug_checkbox = CheckBox.new()
	toggle_debug_checkbox.text = "Show Debug Info"
	
	var saved_debug_info = SettingsManager.get_setting(game_settings_category, "show_debug_info", false)
	toggle_debug_checkbox.button_pressed = saved_debug_info

	toggle_debug_checkbox.pressed.connect(func():
		print("Debug Info Toggled: ", toggle_debug_checkbox.button_pressed)
		SettingsManager.set_setting(game_settings_category, "show_debug_info", toggle_debug_checkbox.button_pressed)
	)
	settings_popup_script.add_custom_setting(toggle_debug_checkbox)

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
