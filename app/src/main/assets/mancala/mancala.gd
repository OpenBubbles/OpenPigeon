extends Control

var player_str: int      = 2
var game_settings_category: String
var player: int      = 1
var is_your_turn: bool = false
var is_my_turn: bool = false
var spectator_mode: bool = false
var mode: String = ""
var my_player: String = ""
const PIT_COUNT: int = 14
var avatar_key: String = "0"
var _last_sown_pit: int = -1
var has_connected: bool = false
var offsets: Array[Vector2]
const GOLDEN_ANGLE := TAU * (1.0 - 1.0/1.61803398875)
const PIT_PADDING := 12.0
const STORE_PADDING := 12.0
const SAFETY_SCALE_PIT := 0.90
const SAFETY_SCALE_STORE := 0.92
var game_over: bool = false
var in_replay: bool = false
const BASE_STONE_SCALE := Vector2(0.1, 0.1)
var win_loss_state: String = ""
var winner_id: int = -1
var disp_winner: bool = false
var _skip_replay_animation: bool = false
var pits: Array = []
var pit_nodes: Array[Area2D] = []
var spawn_points: Array[Marker2D] = []
var board_labels: Array = []
var replay_moves: Array = []
var current_theme_name: String = "Default"


var PitScene    : PackedScene = preload("res://mancala/pit.tscn")
var StoreScene  : PackedScene = preload("res://mancala/store.tscn")
var StoneScene : PackedScene = preload("res://mancala/stone.tscn")
const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const RULES_POPUP_SCENE = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")

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
@onready var board_sprite := %BoardSprite as TextureRect

var _carrying_stones_container: Node2D = Node2D.new()
const STONE_DROP_DELAY: float = 0.1 # Time to pause after dropping each stone
const PIT_PICKUP_TIME: float = 0.3 # How long it takes for the pit to lift
const PILE_TRAVEL_TIME: float = 0.35 # Time for the entire pile to move between pits
const BOUNCE_SCALE_FACTOR: float = 1.3 # Stones will scale to 120% of their base size
const BOUNCE_DURATION: float = 0.01 # Duration for the initial bounce at pickup (for the very first pickup)
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
	var saved_theme: String = str(SettingsManager.get_setting("global", "theme", current_theme_name))
	current_theme_name = saved_theme
	current_palette     = _get_palette_for_theme(saved_theme)
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_board_sprite_modulate()
	_apply_bg_for_dark(is_dark)
	_init_mancala_board_structure()

	if skip_button:
		skip_button.visible = false

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
		var dev_data = '{"isYourTurn": true,"mode": "n","player": "2","replay": "board:&2,2&2&&3,3,3&11&3,3,1,2,1,12,3,3,12&12,12,13,13,3,3,13,1,3,2&3&11,3&&1,13,12&13,11,12,11,13,12,11,1,13,3,11,2&13,13,11,12,2|move:2,4|board:12&2,2&2&&3,3&11&3,3,1,2,1,12,3,3,12&12,12,13,13,3,3,13,1,3,2&3&11,3&&&13,11,12,11,13,12,11,1,13,3,11,2,1&13,13,11,12,2,13","sender":"7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX","version": "5","tver": "5","ios": "18.5","subcaption": "Capture Mode","id": "ziadBSjDYgc4ruev","player2": "7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX"}'
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
	_apply_board_sprite_modulate()
	
func _apply_bg_for_dark(is_dark: bool) -> void:
	if not is_instance_valid(background):
		return

	var base_color: Color = (current_palette.get("board_dark", Color(0.13, 0.14, 0.15)) as Color)
	if not is_dark:
		base_color = (current_palette.get("board_light", Color(0.43, 0.49, 0.51)) as Color)

	var color: Color = base_color
	if mode == "an" or mode == "ah":
		color = color.darkened(0.15) if is_dark else color.lightened(0.15)

	var tint: Color = (current_palette.get("board_tint", Color(1, 1, 1)) as Color)
	var strength: float = float(current_palette.get("board_tint_strength", 0.0))
	if strength > 0.0:
		color = color.lerp(tint, clamp(strength, 0.0, 1.0))

	background.color = color

func _set_game_data(raw_text: String) -> void:
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	var res = JSON.parse_string(raw_text)
	print("[PARSE] Raw game data received:", res)

	_skip_replay_animation = false
	in_replay = false
	if skip_button:
		skip_button.visible = false

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
	winner_id = int(res.get("winner", ""))
	is_your_turn = res.get("isYourTurn", false)
	
	if my_player == p1_id or (p1_id == "" and is_your_turn):
		player = 1
		is_my_turn = is_your_turn
		spectator_mode = false
	elif my_player == p2_id or (p1_id == "" and not is_your_turn):
		player = 2
		is_my_turn = is_your_turn
		spectator_mode = false
	else:
		spectator_mode = true
		print("Spectator Mode Enabled!")
		spec_label.visible = true
		is_my_turn = false
		player = 1

	print("YOUR TURN?: ", is_your_turn, " MY TURN?: ", is_my_turn, " Spectator Mode: ", spectator_mode)
	
	_apply_bg_for_dark(is_dark)

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

	replay_moves.clear()
	if parsed.moves.size() > 0:
		replay_moves = parsed.moves
		_is_animating = true
		in_replay = true
		if skip_button:
			skip_button.visible = true
		for i in range(replay_moves.size()):
			if _skip_replay_animation:
				print("Skipped 230")
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
			if game_over:
				if skip_button: skip_button.visible = false
				_is_animating = false
				return
			var current_sow_player_store_idx = 6 if player_str == 1 else 13
			if _last_sown_pit == current_sow_player_store_idx:
				free_turn_label.text = "Free Turn!"
				free_turn_label.visible = true
				var free_turn_tween = create_tween()
				free_turn_tween.tween_interval(0.8)
				free_turn_tween.tween_callback(func(): free_turn_label.visible = false)
				await free_turn_tween.finished
			player_str = original_player_str_for_sow
		if skip_button: skip_button.visible = false
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
	else:
		if skip_button:
			skip_button.visible = false

	print("258 CALLED GAME OVER")
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

			# --- Skin color (accept both) ---
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

func _apply_board_layout(_is_current_turn: bool) -> void:
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
	
	if game_over:
		_is_animating = false
		_stop_pit_highlights()
		_end_turn()
		return

	var give_free_turn = false
	if _last_sown_pit != -1:
		if _last_sown_pit == 6 or _last_sown_pit == 13:
			give_free_turn = true
			print("DEBUG: Last stone landed in own store pit -> free turn!")
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
		print("END TURN!")
		_end_turn()
		
	_is_animating = false
	if is_my_turn:
		_start_pit_highlights()
		
func _add_stone_to_pit(pit_idx: int, stone_node: Node2D, stone_label: int) -> void:
	var pit_container := pit_nodes[pit_idx].get_node("StonesContainer") as Node2D
	pit_container.add_child(stone_node)
	pits[pit_idx].append(stone_label)
	var n_stones: int = pits[pit_idx].size()
	var stone_half_size := 8.0

	var cr := _get_pit_center_and_radii(pit_idx, stone_half_size)
	var center: Vector2 = cr[0]
	var radii: Vector2 = cr[1]
	var k = n_stones - 1
	var t := float(k + 0.5) / float(n_stones)
	var r := sqrt(t)
	var a := GOLDEN_ANGLE * float(k)
	var new_pos := center + Vector2(cos(a) * radii.x * r, sin(a) * radii.y * r)
	
	stone_node.position = new_pos
	if stone_node.rotation_degrees == 0.0:
		stone_node.rotation_degrees = randf_range(0, 360)
	if stone_node is Sprite2D:
		var sh := Sprite2D.new()
		sh.name = "Shadow"
		sh.texture = (stone_node as Sprite2D).texture
		sh.modulate = Color(0, 0, 0, 0.3)
		sh.scale = stone_node.scale * 1.05
		sh.position = new_pos + Vector2(5, 5)
		sh.z_index = -1
		pit_container.add_child(sh)
	_refresh_pit_count_label(pit_idx)
		
func _get_pit_center_and_radii(i: int, stone_half: float) -> Array:
	var pit := pit_nodes[i]
	var pad := STORE_PADDING if (i == 6 or i == 13) else PIT_PADDING
	var safety := SAFETY_SCALE_STORE if (i == 6 or i == 13) else SAFETY_SCALE_PIT
	var center := spawn_points[i].position
	var radii := (Vector2(64, 40) if (i == 6 or i == 13) else Vector2(34, 34))

	var col := pit.find_child("CollisionShape2D", true, false) as CollisionShape2D
	if col and col.shape:
		center = col.position

		match col.shape:
			CircleShape2D:
				var r: float = (col.shape as CircleShape2D).radius - pad - stone_half
				radii = Vector2(max(6.0, r), max(6.0, r))

			RectangleShape2D:
				var half := (col.shape as RectangleShape2D).size * 0.5 - Vector2(pad + stone_half, pad + stone_half)
				radii = Vector2(max(6.0, half.x), max(6.0, half.y))

			CapsuleShape2D:
				var cap := col.shape as CapsuleShape2D
				var half := Vector2(cap.radius, cap.height * 0.5 + cap.radius) - Vector2(pad + stone_half, pad + stone_half)
				radii = Vector2(max(6.0, half.x), max(6.0, half.y))

			_:
				pass

	radii *= safety
	return [center, radii]


func _layout_pit_stones(i: int) -> void:
	var pit := pit_nodes[i]
	if not pit: return
	var container := pit.get_node("StonesContainer") as Node2D
	if not container: return

	for child in container.get_children():
		if child is Node2D and child.name == "Shadow":
			child.queue_free()

	var stones: Array[Node2D] = []
	for child in container.get_children():
		if child is Node2D and child.name != "Shadow":
			stones.append(child)

	var n := stones.size()
	if n == 0: return

	var stone_half := 8.0
	if stones[0] is Sprite2D and (stones[0] as Sprite2D).texture:
		var tex := (stones[0] as Sprite2D).texture
		var sz := tex.get_size() * stones[0].scale
		stone_half = max(sz.x, sz.y) * 0.5

	var cr := _get_pit_center_and_radii(i, stone_half)
	var center: Vector2 = cr[0]
	var radii: Vector2 = cr[1]
	const AREA_SCALE = 0.85
	for s in stones:
		var angle = randf_range(0, TAU)
		var distance_factor = sqrt(randf()) * AREA_SCALE
		var random_offset = Vector2(cos(angle) * radii.x * distance_factor, sin(angle) * radii.y * distance_factor)
		
		var pos = center + random_offset
		s.position = pos

		if s.rotation_degrees == 0.0:
			s.rotation_degrees = randf_range(0, 360)

		if s is Sprite2D:
			var sh := Sprite2D.new()
			sh.name = "Shadow"
			sh.texture = (s as Sprite2D).texture
			sh.modulate = Color(0, 0, 0, 0.3)
			sh.scale = s.scale * 1.05
			sh.position = pos + Vector2(5, 5)
			sh.z_index = -1
			container.add_child(sh)

func _sow_from(start_idx: int) -> void:
	var current_sowing_pit_idx = start_idx
	
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
			var pits_to_take = [7, 8, 9, 10, 11, 12] if current_sow_player == 1 else [0, 1, 2, 3, 4, 5]
			await _animate_sweep(pits_to_take, opponent_store_idx)
			break

		if pits[current_sowing_pit_idx].size() == 0:
			break
		
		var stones_to_sow = pits[current_sowing_pit_idx].size()
		if stones_to_sow == 0:
			break
			
		var start_pit_node = pit_nodes[current_sowing_pit_idx]
		var start_container = start_pit_node.get_node("StonesContainer") as Node2D

		var carried_stone_labels: Array = pits[current_sowing_pit_idx].duplicate()
		for c in start_container.get_children():
			c.queue_free()
		pits[current_sowing_pit_idx].clear()
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
				_add_stone_to_pit(current_idx, stone_to_drop_visual, dropped_stone_label)

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
				break
			
			print("Avalanche continues: Picking up stones from pit ", _last_sown_pit)
			if current_sowing_pit_idx == 6 or current_sowing_pit_idx == 13:
				break
			current_sowing_pit_idx = _last_sown_pit
		else:
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
	
	_refresh_pit_count_label(last_sown_pit_idx)
	_refresh_pit_count_label(opposite_pit_idx)
	var capture_tween = create_tween()
	if capture_tween == null:
		push_error("capture_tween is null during capture animation!")
		for s_visual in all_visual_stones_to_capture:
			s_visual.queue_free()
		return
	var target_global_pos_for_capture = store_node.global_position
	
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

			var shadow := Sprite2D.new()
			shadow.name = "Shadow"
			shadow.texture = (s_visual as Sprite2D).texture
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
		container.add_child(s)

	_refresh_pit_count_label(i)
	_layout_pit_stones(i)

func _get_color_from_label(label: int) -> Color:
	match label:
		1, 11: return _palette_color("primary")
		2, 12: return _palette_color("secondary")
		3, 13: return _palette_color("accent")
		_:     return Color(1, 1, 1)

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

func _place_stone(_container: Node2D, _base_pos: Vector2, _label: int) -> void:
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
		if not game_over:
			play_sent_animation()
		
func _check_game_over_and_winner() -> bool:
	print("Checking for game over condition...")
	var is_game_over_condition_met := false

	if not game_over:
		var player1_store_count: int = pits[6].size()
		var player2_store_count: int = pits[13].size()
		print("PLAYER 1 STORE QTY: ", player1_store_count, " | PLAYER 2 STORE QTY: ", player2_store_count)

		var player1_side_empty := true
		for i in range(0, 6):
			if pits[i].size() > 0:
				player1_side_empty = false
				break

		var player2_side_empty := true
		for i in range(7, 13):
			if pits[i].size() > 0:
				player2_side_empty = false
				break

		if player1_side_empty or player2_side_empty:
			print("Game over: One player's side is empty.")
			is_game_over_condition_met = true

			if player1_side_empty:
				print("Player 1's side empty -> animate stones from Player 2 pits to Store 13.")
				await _animate_sweep([7, 8, 9, 10, 11, 12], 13)
			elif player2_side_empty:
				print("Player 2's side empty -> animate stones from Player 1 pits to Store 6.")
				await _animate_sweep([0, 1, 2, 3, 4, 5], 6)
				_refresh_pit_count_label(6)

	if is_game_over_condition_met and not game_over:
		game_over = true

		var p1: int = pits[6].size()
		var p2: int = pits[13].size()
		print("Final scores: Player 1 (store 6): ", p1, ", Player 2 (store 13): ", p2)

		if p1 > p2:
			winner_id = 1
		elif p2 > p1:
			winner_id = 2
		else:
			winner_id = -1

	if game_over and not disp_winner:
		print("Setting Game_Over_State")
		disp_winner = true

		_stop_pit_highlights()

		if is_instance_valid(free_turn_label):
			free_turn_label.visible = false

		if winner_id == -1:
			win_loss_label.text = "DRAW!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
			win_loss_state = "0"
		elif (player == 1 and winner_id == 1) or (player == 2 and winner_id == 2):
			if not spectator_mode:
				win_loss_label.text = "YOU WIN!"
				_show_win_burst(player_avatar_display)
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
				win_loss_state = "1"
			else:
				win_loss_label.text = "Player {0} Wins!".format([winner_id])
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			
		else:
			if not spectator_mode:
				win_loss_label.text = "YOU LOSE"
				_show_win_burst(opp_avatar_display)
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
				win_loss_state = "-1"
			else:
				win_loss_label.text = "Player {0} Wins!".format([winner_id])
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			
		win_loss_label.visible = true
		await get_tree().process_frame
		win_loss_label.scale = Vector2.ZERO
		win_loss_label.pivot_offset = win_loss_label.size / 2

		var tween_in := create_tween()
		tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6)\
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		await tween_in.finished

	return game_over	
	
func _animate_sweep(pit_indices: Array, store_idx: int) -> void:
	var store_node := pit_nodes[store_idx]
	var store_container := store_node.get_node("StonesContainer") as Node2D

	var visuals_to_animate: Dictionary = {}
	var all_labels: Array[int] = []

	for i in pit_indices:
		if pits[i].is_empty():
			continue

		var pit_container := pit_nodes[i].get_node("StonesContainer") as Node2D
		
		for child in pit_container.get_children():
			if child is Sprite2D and not child.name.begins_with("Shadow"):
				var stone_visual = child as Sprite2D
				visuals_to_animate[stone_visual] = stone_visual.global_position

		all_labels.append_array(pits[i])
		pits[i].clear()
		_refresh_pit_count_label(i)

	if visuals_to_animate.is_empty():
		return

	var travel_tween := create_tween().set_parallel()
	var travel_time := PILE_TRAVEL_TIME * 1.2
	if _skip_replay_animation:
		travel_time = 0.05
	
	var target_global_pos := store_node.global_position

	for stone_visual in visuals_to_animate:
		var start_global_pos = visuals_to_animate[stone_visual]

		stone_visual.get_parent().remove_child(stone_visual)
		self.add_child(stone_visual)

		stone_visual.global_position = start_global_pos

		travel_tween.tween_property(stone_visual, "global_position", target_global_pos, travel_time)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await travel_tween.finished

	for stone_visual in visuals_to_animate:
		if not is_instance_valid(stone_visual): continue

		self.remove_child(stone_visual)
		store_container.add_child(stone_visual)

		stone_visual.position = spawn_points[store_idx].position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		stone_visual.rotation_degrees = randf_range(0, 360)

		var shadow := Sprite2D.new()
		shadow.name = "Shadow"
		shadow.texture = (stone_visual as Sprite2D).texture
		shadow.modulate = Color(0, 0, 0, 0.3)
		shadow.scale = stone_visual.scale * 1.05
		shadow.position = stone_visual.position + Vector2(5, 5)
		shadow.z_index = -1
		store_container.add_child(shadow)

	pits[store_idx].append_array(all_labels)
	_refresh_pit_count_label(store_idx)
	
func _show_win_burst(avatar: Control) -> void:
	if not is_instance_valid(avatar) or not is_instance_valid(avatar.get_parent()):
		push_warning("Tried to show win burst on an invalid avatar or avatar with no parent.")
		return

	var parent = avatar.get_parent()

	if parent.get_node_or_null("%s_Wrapper/AvatarWinAnim" % avatar.name):
		return

	var wrapper = Control.new()
	wrapper.name = "%s_Wrapper" % avatar.name

	wrapper.layout_mode = avatar.layout_mode
	wrapper.size_flags_horizontal = avatar.size_flags_horizontal
	wrapper.size_flags_vertical = avatar.size_flags_vertical
	wrapper.position = avatar.position
	wrapper.size = avatar.size
	wrapper.rotation = avatar.rotation
	wrapper.scale = avatar.scale
	wrapper.pivot_offset = avatar.pivot_offset
	wrapper.custom_minimum_size = avatar.custom_minimum_size

	var avatar_index = avatar.get_index()
	parent.remove_child(avatar)
	parent.add_child(wrapper)
	parent.move_child(wrapper, avatar_index)
	wrapper.add_child(avatar)

	avatar.position = Vector2.ZERO
	avatar.set_anchors_preset(Control.PRESET_FULL_RECT)

	var anim_instance = AvatarWinAnimScene.instantiate() as Control
	if not is_instance_valid(anim_instance):
		push_error("Failed to instantiate AvatarWinAnimScene.")
		return
	anim_instance.name = "AvatarWinAnim"
	wrapper.add_child(anim_instance)
	
	wrapper.move_child(anim_instance, 0)

	anim_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	anim_instance.offset_left = -52.0
	anim_instance.offset_right = 52.0
	anim_instance.offset_top = -43.0
	anim_instance.offset_bottom = 43.0

	if anim_instance.has_method("set_color"):
		anim_instance.call("set_color", Color(1.0, 0.84, 0.0))
	
	if anim_instance.has_method("play"):
		anim_instance.call("play", 0.05)
	
func _on_skip_button_pressed() -> void:
	if in_replay:
		print("Skip button pressed during replay!")
		_skip_replay_animation = true

func on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return

	rules_button.pivot_offset = rules_button.size / 2.0
	var tween := create_tween()
	tween.tween_property(rules_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(rules_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var popup := RULES_POPUP_SCENE.instantiate() as RulesPopup
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99

	popup.tree_exited.connect(func():
		if is_instance_valid(dim):
			dim.queue_free()
	)

	popup.open("How to Play Mancala", _get_rules_text_for_mode())
	
func _get_rules_text_for_mode() -> String:
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
	settings_popup_script.theme_previews_enabled = true
	
	var mancala_themes = await _get_mancala_themes()
	popup_instance.ready.connect(func():
			settings_popup_script.populate_theme_previews(mancala_themes)
	)
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
	current_theme_name = new_theme_name
	current_palette    = _get_palette_for_theme(new_theme_name)
	
	SettingsManager.set_setting("global", "theme", new_theme_name)
	if SettingsManager.has_method("save"):
		SettingsManager.save()

	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)
	_apply_board_sprite_modulate()
	_refresh_all_pits()
	
func _palette_color(key: String) -> Color:
	var v = current_palette.get(key)
	if v == null and key == "primary":
		var variants = current_palette.get("primary_variants")
		if variants is Array and variants.size() > 0 and variants[0] is Color:
			return variants[randi() % variants.size()]
	if v is Color:
		return v
	return Color(1, 1, 1)

func _generate_theme_preview(theme_palette: Dictionary) -> Texture2D:
	var preview_size := Vector2i(64, 64)

	var vp := SubViewport.new()
	vp.size = preview_size
	vp.set_update_mode(SubViewport.UpdateMode.UPDATE_ONCE)
	# --- ADD THIS LINE ---
	vp.transparent_bg = true # Makes the viewport corners transparent
	# --- END ADDITION ---

	# Use a Panel with StyleBoxFlat for rounded corners
	var bg_panel := Panel.new()
	bg_panel.size = Vector2(preview_size)
	bg_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg_style := StyleBoxFlat.new()
	var bg_color: Color = theme_palette.get("board_light", Color.GRAY)
	bg_color.a = 0.4 # Set opacity to 40%
	bg_style.bg_color = bg_color
	bg_style.corner_radius_bottom_left = 8
	bg_style.corner_radius_bottom_right = 8
	bg_style.corner_radius_top_left = 8
	bg_style.corner_radius_top_right = 8
	
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	vp.add_child(bg_panel)

	var temp_pit := PitScene.instantiate()
	var debug_label = temp_pit.find_child("Debug_num", true, false)
	if debug_label: debug_label.visible = false
	var count_label = temp_pit.find_child("CountLabel", true, false)
	if count_label: count_label.visible = false
	
	var collision_shape_node := temp_pit.get_node("CollisionShape2D") as CollisionShape2D
	var pit_local_center := collision_shape_node.position
	var preview_scale := 0.75
	
	temp_pit.scale = Vector2.ONE * preview_scale
	temp_pit.position = (Vector2(preview_size) * 0.5) - (pit_local_center * preview_scale)
	vp.add_child(temp_pit)
	
	var all_stone_colors: Array[Color] = []
	if theme_palette.has("primary_variants") and theme_palette["primary_variants"] is Array:
		all_stone_colors.append_array(theme_palette["primary_variants"])
	elif theme_palette.has("primary") and theme_palette["primary"] is Color:
		all_stone_colors.append(theme_palette["primary"])
	if theme_palette.has("secondary") and theme_palette["secondary"] is Color:
		all_stone_colors.append(theme_palette["secondary"])
	if theme_palette.has("accent") and theme_palette["accent"] is Color:
		all_stone_colors.append(theme_palette["accent"])
	if all_stone_colors.is_empty():
		all_stone_colors.append(Color.WHITE)

	var final_colors_to_render: Array[Color] = []
	final_colors_to_render.append_array(all_stone_colors)
	
	var total_stone_count := randi_range(8, 12)
	var remaining_stones_needed = total_stone_count - final_colors_to_render.size()

	if remaining_stones_needed > 0 and not all_stone_colors.is_empty():
		for i in range(remaining_stones_needed):
			final_colors_to_render.append(all_stone_colors.pick_random())

	final_colors_to_render.shuffle()

	var stone_container := temp_pit.get_node("StonesContainer")
	var pit_radius := (collision_shape_node.shape as CircleShape2D).radius
	var layout_radius := pit_radius * SAFETY_SCALE_PIT
	
	for i in range(final_colors_to_render.size()):
		var stone_color = final_colors_to_render[i]
		var stone := StoneScene.instantiate() as Node2D
		stone.scale = BASE_STONE_SCALE * 1.0
		stone.modulate = stone_color
		
		var angle := float(i) * GOLDEN_ANGLE
		var radius_factor := sqrt(float(i + 1) / float(final_colors_to_render.size()))
		var radius := layout_radius * radius_factor * 0.9
		stone.position = Vector2(cos(angle), sin(angle)) * radius
		stone.rotation = randf_range(0, TAU)
		
		stone_container.add_child(stone)

	add_child(vp)
	await get_tree().process_frame
	await get_tree().process_frame

	var vp_tex := vp.get_texture()
	var out_tex: Texture2D

	if vp_tex == null:
		var fallback_img := Image.create(preview_size.x, preview_size.y, false, Image.FORMAT_RGBA8)
		fallback_img.fill(Color.MAGENTA)
		out_tex = ImageTexture.create_from_image(fallback_img)
	else:
		var img := vp_tex.get_image()
		out_tex = ImageTexture.create_from_image(img)
	
	vp.queue_free()
	
	return out_tex
	
func _get_mancala_themes() -> Dictionary:
	var themes_data := {}
	var theme_names := ["Default", "Retro", "Penguin", "Sakura Ink", "Emerald Brass", "Desert Dusk"]

	for theme_name in theme_names:
		var palette := _get_palette_for_theme(theme_name)
		# Generate each preview image and wait for it to finish
		var preview_tex := await _generate_theme_preview(palette)
		# Store the generated texture object directly in the dictionary
		themes_data[theme_name] = {"texture": preview_tex}
	
	print("Dynamic theme previews generated:", themes_data.keys())
	return themes_data
	
func _apply_board_sprite_modulate() -> void:
	if not is_instance_valid(board_sprite): return
	var c: Color = current_palette.get("board_sprite_modulate", Color(1, 1, 1)) as Color
	board_sprite.modulate = c
	
func _load_game_specific_settings():
	var saved_volume = SettingsManager.get_setting(game_settings_category, "master_volume", 0.75)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))

	var show_debug_info = SettingsManager.get_setting(game_settings_category, "show_debug_info", false)

	print("Loaded game-specific settings for ", game_settings_category, ":")
	print("  Master Volume: ", saved_volume)
	print("  Show Debug Info: ", show_debug_info)
	
var current_palette := {
	"primary": Color("#fffcf2"),
	"secondary": Color("#414851"),
	"accent": Color("#176cab"),
	"board_light": Color("#6d7c82"),
	"board_dark": Color("#202526"),
	"board_sprite_modulate": Color(1, 1, 1)
}

func _get_palette_for_theme(themename: String) -> Dictionary:
	match themename:
		"Default":
			return {
				"primary": Color("#fffcf2"),
				"secondary": Color("#414851"),
				"accent": Color("#176cab"),
				"board_light": Color("#6d7c82"),
				"board_dark": Color("#202526"),
				"board_sprite_modulate": Color(1, 1, 1)
			}
		"Retro":
			return {
				"primary_variants": [
					Color("e80038ff"),  # apricot
				],
				"secondary": Color("ffb900ff"),   # umber (stones 2/12)
				"accent":    Color("#2FA5A0"),   # turquoise (stones 3/13)

				# board
				"board_light": Color("#F1E5D1"), # pale sand
				"board_dark":  Color("#2C1F1A"), # dusk
				"board_sprite_modulate": Color("dbdfdeff"), # warm peach tint
				"board_tint": Color("f6f5f1ff"),
				"board_tint_strength": 0.07
			}
		"Penguin":
			return {
				#"primary": Color("#00e603"),
				"primary_variants": [
					Color("#00e603"),  # neon green
					Color("#00c6cf"),  # punchy red
					Color("#0083e3")   # electric purple
				],
				"secondary": Color("#e90008"),
				"accent": Color("#c303c1"),
				"board_light": Color("#00529b"),
				"board_dark": Color("#00254dff"),
				# bright yellow tint for the board image
				"board_sprite_modulate": Color("#fdd22b")
			}
		"Sakura Ink":
			return {
				# blossom tones for stones 1/11
				"primary_variants": [
					Color("#F7BFCF"),  # rose
				],
				"secondary": Color("#2A2E34"),   # ink charcoal (stones 2/12)
				"accent":    Color("#4F65A3"),   # indigo (stones 3/13)

				# board
				"board_light": Color("#F3EDE8"), # warm parchment
				"board_dark":  Color("#191C22"), # deep ink
				"board_sprite_modulate": Color("#FFE8D1"), # ivory tint
				"board_tint": Color("#FFFAF5"),           # feather-light warm overlay
				"board_tint_strength": 0.05
			}

		"Emerald Brass":
			return {
				# lush greens for stones 1/11
				"primary_variants": [
					Color("#2FAF74"),  # emerald
					Color("#1D8F5A"),  # forest
					Color("#66C79E")   # jade
				],
				"secondary": Color("#8C6B32"),   # brass (stones 2/12)
				"accent":    Color("#2B8C7B"),   # teal (stones 3/13)

				# board
				"board_light": Color("#E7E3DA"), # linen
				"board_dark":  Color("#13281F"), # evergreen
				"board_sprite_modulate": Color("#D8B269"), # soft brass tint
				"board_tint": Color("#F6F2E7"),
				"board_tint_strength": 0.06
			}

		"Desert Dusk":
			return {
				# desert minerals for stones 1/11
				"primary_variants": [
					Color("#E8A66A"),  # apricot
				],
				"secondary": Color("#3A2C27"),   # umber (stones 2/12)
				"accent":    Color("#2FA5A0"),   # turquoise (stones 3/13)

				# board
				"board_light": Color("#F1E5D1"), # pale sand
				"board_dark":  Color("#2C1F1A"), # dusk
				"board_sprite_modulate": Color("#FFD7A1"), # warm peach tint
				"board_tint": Color("#FFF3E1"),
				"board_tint_strength": 0.07
			}
		_:
			return current_palette
