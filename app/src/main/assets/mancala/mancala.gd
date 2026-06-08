extends BaseGame

var player_str: int      = 2
var player: int      = 1
var is_your_turn: bool = false
var is_my_turn: bool = false
var mode: String = ""
const PIT_COUNT: int = 14
var avatar_key: String = "0"
var _last_sown_pit: int = -1
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
var disp_winner: bool = false
var _skip_replay_animation: bool = false
var pits: Array = []
var pit_nodes: Array[Area2D] = []
var spawn_points: Array[Marker2D] = []
var board_labels: Array = []
var replay_moves: Array = []
var current_theme_name: String = "Default"
var winner_id

var PitScene    : PackedScene = preload("res://mancala/pit.tscn")
var StoreScene  : PackedScene = preload("res://mancala/store.tscn")
var StoneScene : PackedScene = preload("res://mancala/stone.tscn")
const MUSIC_STREAM := preload("res://global/audio/mancala.ogg")

@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var sent_label = %SentLabel
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
var sent_tween: Tween

var _is_animating: bool = false
var moves_made: Array = []
var prev_board_str: String = ""

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
const LOG_TAG := "Mancala"
var DEBUG_MANCALA := false

func dbg(msg: String) -> void:
	if DEBUG_MANCALA:
		OpLog.d(LOG_TAG, msg)
	
func _get_dev_data() -> String:
	return '{"isYourTurn": true,"mode": "n","player": "2","replay": "board:&2,2&2&&3,3,3&11&3,3,1,2,1,12,3,3,12&12,12,13,13,3,3,13,1,3,2&3&11,3&&1,13,12&13,11,12,11,13,12,11,1,13,3,11,2&13,13,11,12,2|move:2,4|board:12&2,2&2&&3,3&11&3,3,1,2,1,12,3,3,12&12,12,13,13,3,3,13,1,3,2&3&11,3&&&13,11,12,11,13,12,11,1,13,3,11,2,1&13,13,11,12,2,13","sender":"7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX","version": "5","tver": "5","ios": "18.5","subcaption": "Capture Mode","id": "ziadBSjDYgc4ruev","player2": "7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX"}'
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Mancala"
	
func _get_rules_text() -> String:
	return _get_rules_text_for_mode()

func _debug_pit_input_layers() -> void:
	for pit in pit_nodes:
		dbg("pit_layers index=%s" % str(pit.index))

		for node in pit.get_children():
			var info = ""

			if node is CollisionShape2D:
				info = "CollisionShape2D disabled=%s" % str(node.disabled)
			elif node is Area2D:
				info = "Area2D pickable=%s" % str(node.input_pickable)
			elif node is Control:
				info = "Control mouse_filter=%d" % node.mouse_filter
			else:
				info = "%s visible=%s" % [
					node.get_class(),
					str(node.visible if node.has_method("is_visible") else "")
				]

			dbg("pit_layer child=%s info=%s" % [str(node.name), info])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dbg("unhandled_click pos=%s" % str(event.position))

func _on_game_ready() -> void:
	game_settings_category = SettingsManager.get_game_name_from_path(get_tree().current_scene.scene_file_path)
	OpLog.i(LOG_TAG, ["game_ready settings_category=", game_settings_category])

	_load_game_specific_settings()

	var saved_theme: String = str(SettingsManager.get_setting("global", "theme", current_theme_name))
	current_theme_name = saved_theme
	current_palette = _get_palette_for_theme(saved_theme)

	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_board_sprite_modulate()
	_apply_bg_for_dark(is_dark)
	_init_mancala_board_structure()

	if is_instance_valid(skip_button):
		skip_button.visible = false

		if not skip_button.pressed.is_connected(_on_skip_button_pressed):
			skip_button.pressed.connect(_on_skip_button_pressed)

	for pit in pit_nodes:
		for node in pit.get_children():
			if node is Control and node.name != "DebugRect":
				node.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(_carrying_stones_container)
	_carrying_stones_container.z_index = 90
	_apply_board_sprite_modulate()
	OpLog.i(LOG_TAG, [
		"game_ready_done theme=", current_theme_name,
		" pit_nodes=", pit_nodes.size(),
		" mode=", mode
	])
	
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
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", raw_text])

	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	var res = JSON.parse_string(raw_text)

	if typeof(res) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, ["set_game_data_parse_failed raw=", raw_text])
		return

	OpLog.i(LOG_TAG, [
		"set_game_data_parsed keys=", (res as Dictionary).keys()
	])
	
	_skip_replay_animation = false
	in_replay = false
	_is_animating = false
	game_over = false
	disp_winner = false
	win_loss_state = ""
	winner_id = null
	spectator_mode = false
	moves_made.clear()
	replay_moves.clear()
	_stop_pit_highlights()
	stop_waiting_animation()

	if is_instance_valid(skip_button):
		skip_button.visible = false

	if is_instance_valid(win_loss_label):
		win_loss_label.visible = false
		win_loss_label.text = ""
		win_loss_label.scale = Vector2.ONE

	if is_instance_valid(free_turn_label):
		free_turn_label.visible = false

	var p1_id: String = str(res.get("player1", ""))
	var p2_id: String = str(res.get("player2", ""))
	var winner_payload: String = str(res.get("winner", ""))
	var opponent_avatar_key := ""

	player_str = int(res.get("player", player))
	mode = String(res.get("mode", mode))
	is_your_turn = bool(res.get("isYourTurn", false))
	
	OpLog.i(LOG_TAG, [
		"set_game_data_fields my_uuid=", my_uuid,
		" player1=", p1_id,
		" player2=", p2_id,
		" player_str=", player_str,
		" mode=", mode,
		" isYourTurn=", is_your_turn,
		" has_winner=", winner_payload != "",
		" replay_len=", String(res.get("replay", "")).length()
	])

	if my_uuid != "" and p1_id != "" and p2_id != "":
		if my_uuid == p1_id:
			player = 1
			is_my_turn = is_your_turn
			spectator_mode = false
			opponent_avatar_key = "avatar2"
		elif my_uuid == p2_id:
			player = 2
			is_my_turn = is_your_turn
			spectator_mode = false
			opponent_avatar_key = "avatar1"
		else:
			player = 1
			is_my_turn = false
			spectator_mode = true
	else:
		player = 1 if is_your_turn else 2
		is_my_turn = is_your_turn
		spectator_mode = false
		opponent_avatar_key = "avatar2" if player == 1 else "avatar1"

	if spectator_mode:
		OpLog.i(LOG_TAG, "spectator_mode_enabled")

		if is_instance_valid(spec_label):
			spec_label.visible = true

		is_my_turn = false

		if res.has("avatar1") and is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", GameUtils._parse_avatar_string(str(res["avatar1"])))

		if res.has("avatar2") and is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", GameUtils._parse_avatar_string(str(res["avatar2"])))
	else:
		if is_instance_valid(spec_label):
			spec_label.visible = false

		if opponent_avatar_key != "" and res.has(opponent_avatar_key):
			var avatar_string = res[opponent_avatar_key]
			var opponent_data = GameUtils._parse_avatar_string(avatar_string)

			if is_instance_valid(opp_avatar_display):
				opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	OpLog.i(LOG_TAG, [
		"resolved_player player=", player,
		" player_str=", player_str,
		" is_your_turn=", is_your_turn,
		" is_my_turn=", is_my_turn,
		" spectator=", spectator_mode
	])

	_apply_bg_for_dark(is_dark)
	_apply_board_layout(is_my_turn)

	var replay_str: String = String(res.get("replay", ""))
	var parsed = parse_replay_string(replay_str)
	var raw_boards: Array = parsed.get("raw_boards", [])

	if raw_boards.size() > 0:
		var initial_board_data = _parse_single_board(str(raw_boards[0]))

		pits.clear()
		for i in range(PIT_COUNT):
			pits.append([])

		for i in range(min(initial_board_data.size(), PIT_COUNT)):
			pits[i] = initial_board_data[i].duplicate()

		_refresh_all_pits()
	else:
		OpLog.w(LOG_TAG, "set_game_data_no_replay_board keeping_default_layout")

	if parsed.moves.size() > 0:
		replay_moves = parsed.moves
		_is_animating = true
		in_replay = true

		if is_instance_valid(skip_button):
			skip_button.visible = true

		for i in range(replay_moves.size()):
			if _skip_replay_animation:
				OpLog.i(LOG_TAG, "replay_skipped")
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
				if is_instance_valid(skip_button):
					skip_button.visible = false

				_is_animating = false
				return

			var current_sow_player_store_idx = 6 if player_str == 1 else 13
			if _last_sown_pit == current_sow_player_store_idx:
				free_turn_label.text = "Free Turn!"
				free_turn_label.visible = true

				var free_turn_tween = create_tween()
				free_turn_tween.tween_interval(0.8)
				free_turn_tween.tween_callback(func():
					free_turn_label.visible = false
				)
				await free_turn_tween.finished

			player_str = original_player_str_for_sow

		if is_instance_valid(skip_button):
			skip_button.visible = false

		_is_animating = false
		in_replay = false

		if raw_boards.size() > 1:
			var final_board_data = _parse_single_board(str(raw_boards[raw_boards.size() - 1]))

			for k in range(min(final_board_data.size(), PIT_COUNT)):
				pits[k] = final_board_data[k].duplicate()

			if _skip_replay_animation:
				_refresh_all_pits()
		else:
			OpLog.w(LOG_TAG, "set_game_data_no_final_board_after_replay")
			push_warning("_set_game_data: No final board state available for post-replay update.")

		_skip_replay_animation = false
		prev_board_str = str(raw_boards[raw_boards.size() - 1]) if raw_boards.size() > 0 else ""
	elif raw_boards.size() > 0:
		prev_board_str = str(raw_boards[0])
	else:
		if is_instance_valid(skip_button):
			skip_button.visible = false

	if winner_payload != "":
		_apply_winner_payload(winner_payload, p1_id, p2_id)
		return
		
	OpLog.i(LOG_TAG, [
		"set_game_data_replay_done raw_boards=", raw_boards.size(),
		" replay_moves=", replay_moves.size(),
		" prev_board_len=", prev_board_str.length()
	])

	await check_win()

	if game_over:
		stop_waiting_animation()
	elif is_my_turn and not spectator_mode:
		_start_pit_highlights()
		stop_waiting_animation()
	elif not spectator_mode:
		start_waiting_animation()
	else:
		stop_waiting_animation()

	OpLog.i(LOG_TAG, [
		"set_game_data_done is_my_turn=", is_my_turn,
		" game_over=", game_over,
		" in_replay=", in_replay,
		" spectator=", spectator_mode,
		" player=", player,
		" winner_id=", winner_id
	])

func parse_replay_string(raw: String) -> Dictionary:
	var out = {
		"boards": [],
		"moves": [],
		"raw_boards": []
	}

	if raw.strip_edges() == "":
		OpLog.d(LOG_TAG, "parse_replay empty")
		return out

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
		elif chunk.strip_edges() != "":
			OpLog.w(LOG_TAG, ["parse_replay_unknown_chunk chunk=", chunk])

	OpLog.i(LOG_TAG, [
		"parse_replay_done raw_len=", raw.length(),
		" boards=", out["boards"].size(),
		" moves=", out["moves"].size()
	])

	return out
	
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
			dbg("missing_debug_label pit=%d" % i)
		
	pits.clear()
	for i in range(PIT_COUNT):
		pits.append([])

	OpLog.i(LOG_TAG, ["board_structure_initialized pits=", pit_nodes.size()])
	dot_timer.timeout.connect(_on_dot_timer_timeout)

func _apply_board_layout(_is_current_turn: bool) -> void:
	OpLog.d(LOG_TAG, ["apply_board_layout player=", player, " is_my_turn=", is_my_turn])
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
		OpLog.w(LOG_TAG, ["cannot_setup_board player=", player, " is_my_turn=", is_my_turn])
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

	OpLog.i(LOG_TAG, ["board_layout_applied player=", player, " mode=", mode])
	if is_my_turn:
		_start_pit_highlights()
		stop_waiting_animation()

func _start_pit_highlights() -> void:
	dbg("start_pit_highlights player=%d" % player)
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
	dbg("stop_pit_highlights")
	for pit in pit_nodes:
		var hl = pit.get_node("HighlightCircle") as ColorRect
		hl.visible = false

func _on_pit_clicked(idx: int) -> void:
	if _is_animating:
		OpLog.d(LOG_TAG, ["pit_click_ignored animating=true idx=", idx])
		return

	if game_over:
		OpLog.w(LOG_TAG, ["pit_click_blocked game_over=true idx=", idx])
		return

	_stop_pit_highlights()

	OpLog.event(LOG_TAG, [
		"pit_clicked idx=", idx,
		" player=", player,
		" is_my_turn=", is_my_turn,
		" pit_size=", pits[idx].size() if idx >= 0 and idx < pits.size() else -1
	])

	if not is_my_turn:
		OpLog.w(LOG_TAG, ["pit_click_blocked not_my_turn idx=", idx])
		return

	if ((player == 1 and (idx < 0 or idx > 5)) or (player == 2 and (idx < 7 or idx > 12))):
		OpLog.w(LOG_TAG, [
			"pit_click_blocked invalid_side_or_store idx=", idx,
			" player=", player
		])
		_start_pit_highlights()
		return

	if pits[idx].size() == 0:
		OpLog.w(LOG_TAG, ["pit_click_blocked empty_pit idx=", idx])
		_start_pit_highlights()
		return

	var pit_offset: int = idx if idx < 6 else idx - 7
	moves_made.append(str(player) + "," + str(pit_offset))

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
			OpLog.event(LOG_TAG, ["free_turn last_sown_pit=", _last_sown_pit])
		else:
			dbg("no_free_turn last_sown_pit=%d" % _last_sown_pit)
	else:
		OpLog.w(LOG_TAG, "last_sown_pit_missing_after_sow")

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
			OpLog.i(LOG_TAG, "sow_interrupted_by_skip")
			break

		var current_sow_player = player_str
		if not in_replay and is_my_turn:
			current_sow_player = player
		else:
			dbg("sow_stats animating=%s is_my_turn=%s current_sow_player=%d in_replay=%s player_str=%d player=%d" % [
				str(_is_animating), str(is_my_turn), current_sow_player, str(in_replay), player_str, player
			])

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
			OpLog.event(LOG_TAG, [
				"sow_game_over_side_empty current_sow_player=", current_sow_player,
				" start_idx=", current_sowing_pit_idx
			])

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

		_carrying_stones_container.global_position = start_pit_node.global_position

		dbg("sow_start pit=%d stones=%d pits_root=%s start_global=%s carrying_global=%s" % [
			current_sowing_pit_idx,
			carried_stone_labels.size(),
			str(pits_root.global_position),
			str(start_pit_node.global_position),
			str(_carrying_stones_container.global_position)
		])

		var pickup_tween = create_tween()
		if pickup_tween == null:
			OpLog.e(LOG_TAG, "pickup_tween_null")
			push_error("pickup_tween is null during initial pickup! Aborting.")
			return

		pickup_tween.tween_property(
			_carrying_stones_container,
			"scale",
			Vector2(BOUNCE_SCALE_FACTOR, BOUNCE_SCALE_FACTOR),
			BOUNCE_DURATION / 2.0
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		pickup_tween.tween_property(
			_carrying_stones_container,
			"scale",
			Vector2(1.0, 1.0),
			BOUNCE_DURATION / 2.0
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

		await pickup_tween.finished

		dbg("sow_after_pickup carrying_global=%s" % str(_carrying_stones_container.global_position))

		while carried_visual_stones.size() > 0:
			if _skip_replay_animation:
				OpLog.i(LOG_TAG, "stone_distribution_interrupted_by_skip")
				for c in _carrying_stones_container.get_children():
					c.queue_free()
				return

			current_idx = (current_idx + 1) % PIT_COUNT

			if (current_sow_player == 1 and current_idx == 13) or (current_sow_player == 2 and current_idx == 6):
				continue

			var target_pit_node = pit_nodes[current_idx]
			var target_global_position_for_pile = target_pit_node.global_position

			dbg("sow_travel_to_pit current_idx=%d target_global=%s remaining=%d" % [
				current_idx,
				str(target_global_position_for_pile),
				carried_visual_stones.size()
			])

			var travel_tween = create_tween()
			if travel_tween == null:
				OpLog.e(LOG_TAG, "travel_tween_null")
				push_error("travel_tween is null during movement! Aborting sowing animation.")
				return

			travel_tween.tween_property(
				_carrying_stones_container,
				"global_position",
				target_global_position_for_pile,
				PILE_TRAVEL_TIME
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

			travel_tween.set_parallel(true)

			travel_tween.tween_property(
				_carrying_stones_container,
				"scale",
				Vector2(BOUNCE_SCALE_FACTOR, BOUNCE_SCALE_FACTOR),
				PILE_TRAVEL_TIME / 2.0
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

			travel_tween.tween_property(
				_carrying_stones_container,
				"scale",
				Vector2(1.0, 1.0),
				PILE_TRAVEL_TIME / 2.0
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(PILE_TRAVEL_TIME / 2.0)

			await travel_tween.finished

			dbg("sow_after_travel current_idx=%d carrying_global=%s" % [
				current_idx,
				str(_carrying_stones_container.global_position)
			])

			if _skip_replay_animation:
				OpLog.i(LOG_TAG, "stone_distribution_interrupted_after_travel")
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
						OpLog.i(LOG_TAG, "stone_distribution_interrupted_during_delay")
						for c in _carrying_stones_container.get_children():
							c.queue_free()
						return

		_last_sown_pit = current_idx

		OpLog.i(LOG_TAG, [
			"sow_finished last_sown_pit=", _last_sown_pit,
			" current_sow_player=", current_sow_player,
			" mode=", mode,
			" stones_in_last=", pits[_last_sown_pit].size()
		])

		if mode == "an" or mode == "ah":
			var player_store_idx = 6 if current_sow_player == 1 else 13

			OpLog.event(LOG_TAG, [
				"avalanche_check last_sown_pit=", _last_sown_pit,
				" player_store_idx=", player_store_idx,
				" stones=", pits[_last_sown_pit].size()
			])

			if _last_sown_pit == player_store_idx:
				dbg("avalanche_ends_store")
				break

			if pits[_last_sown_pit].size() == 1:
				dbg("avalanche_ends_empty_pit")
				break

			OpLog.event(LOG_TAG, [
				"avalanche_continues from_pit=", _last_sown_pit,
				" stones=", pits[_last_sown_pit].size()
			])

			if current_sowing_pit_idx == 6 or current_sowing_pit_idx == 13:
				break

			current_sowing_pit_idx = _last_sown_pit
		else:
			var should_capture = false

			if current_sow_player == 1 and _last_sown_pit >= 0 and _last_sown_pit <= 5 and pits[_last_sown_pit].size() == 1:
				should_capture = true
			elif current_sow_player == 2 and _last_sown_pit >= 7 and _last_sown_pit <= 12 and pits[_last_sown_pit].size() == 1:
				should_capture = true

			if should_capture:
				OpLog.event(LOG_TAG, [
					"capture_condition_met last_sown_pit=", _last_sown_pit,
					" current_sow_player=", current_sow_player,
					" in_replay=", in_replay
				])

				var opposite_pit_idx = -1
				if current_sow_player == 1:
					opposite_pit_idx = 12 - _last_sown_pit
				elif current_sow_player == 2:
					opposite_pit_idx = 12 - _last_sown_pit

				var player_store_idx = 6 if current_sow_player == 1 else 13

				if opposite_pit_idx != -1 and pits[opposite_pit_idx].size() > 0:
					OpLog.event(LOG_TAG, [
						"capture_stones last_sown_pit=", _last_sown_pit,
						" opposite_pit=", opposite_pit_idx,
						" store=", player_store_idx,
						" opposite_count=", pits[opposite_pit_idx].size()
					])

					var captured_stones = []

					if pits[_last_sown_pit].size() > 0:
						captured_stones.append(pits[_last_sown_pit].pop_back())

					captured_stones.append_array(pits[opposite_pit_idx])
					pits[opposite_pit_idx].clear()

					free_turn_label.text = "Captured!"
					free_turn_label.visible = true

					var free_turn_tween = create_tween()
					free_turn_tween.tween_interval(0.5)
					free_turn_tween.tween_callback(func(): free_turn_label.visible = false)

					free_turn_label.add_theme_color_override("font_color", Color(1, 1, 1))
					free_turn_label.add_theme_color_override("background_color", Color(1.0, 0.84, 0.0))

					await _animate_capture(captured_stones, _last_sown_pit, opposite_pit_idx, player_store_idx)

					if _skip_replay_animation:
						OpLog.i(LOG_TAG, "capture_animation_interrupted_by_skip")
						return

					pits[player_store_idx].append_array(captured_stones)
					_refresh_pit_count_label(_last_sown_pit)
					_refresh_pit_count_label(opposite_pit_idx)
					_refresh_pit_count_label(player_store_idx)
				else:
					dbg("capture_not_available opposite_pit=%d" % opposite_pit_idx)

			break

	for child in _carrying_stones_container.get_children():
		child.queue_free()

	_carrying_stones_container.scale = Vector2(1.0, 1.0)
	await check_win()

func _animate_capture(stones_to_capture: Array, last_sown_pit_idx: int, opposite_pit_idx: int, player_store_idx: int) -> void:
	OpLog.event(LOG_TAG, [
		"animate_capture stones=", stones_to_capture.size(),
		" last_sown_pit=", last_sown_pit_idx,
		" opposite_pit=", opposite_pit_idx,
		" store=", player_store_idx
	])

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
		OpLog.e(LOG_TAG, "capture_tween_null")
		push_error("capture_tween is null during capture animation!")

		for s_visual in all_visual_stones_to_capture:
			s_visual.queue_free()

		return

	var target_global_pos_for_capture = store_node.global_position

	capture_tween.tween_property(
		_carrying_stones_container,
		"global_position",
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

	OpLog.i(LOG_TAG, "capture_animation_finished")

func _end_turn() -> void:
	avatar_key = "avatar" + str(player)
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
	dbg("refresh_count player=%d pit=%d in_replay=%s count=%d" % [
		player, i, str(in_replay), pits[i].size()
	])
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
		OpLog.w(LOG_TAG, ["refresh_label_unknown_player player=", player, " pit=", i])

func _place_stone(_container: Node2D, _base_pos: Vector2, _label: int) -> void:
	pass
	
func send_game() -> void:
	OpLog.i(LOG_TAG, [
		"send_game_start spectator=", spectator_mode,
		" player=", player,
		" moves_made=", moves_made,
		" game_over=", game_over
	])

	if spectator_mode:
		OpLog.w(LOG_TAG, "send_game_blocked spectator=true")
		return

	is_my_turn = false
	_stop_pit_highlights()

	var all_moves = ""
	for m in moves_made:
		all_moves += "move:" + m + "|"

	var sent_moves := moves_made.duplicate()
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

	if player != 0 and is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		var avatar_string = player_avatar_display.get_avatar_data_string()
		payload[avatar_key] = avatar_string
		OpLog.d(LOG_TAG, ["send_game_avatar_added key=", avatar_key])

	if await check_win():
		if game_over and win_loss_state != "":
			payload["winner"] = my_uuid + "|" + win_loss_state
			OpLog.event(LOG_TAG, [
				"send_game_winner winner=", payload["winner"],
				" winner_id=", winner_id,
				" win_loss_state=", win_loss_state
			])

	var game_data = JSON.stringify(payload)

	OpLog.event(LOG_TAG, [
		"send_game_out player=", player,
		" mode=", mode,
		" moves=", sent_moves,
		" prev_board_len=", prev_board_str.length(),
		" replay_len=", str(payload["replay"]).length(),
		" has_winner=", payload.has("winner"),
		" raw=", game_data
	])

	send_game_data(game_data)

	if game_over:
		stop_waiting_animation()
	else:
		play_sent_animation()

func _apply_winner_payload(winner_payload: String, p1_id: String = "", p2_id: String = "") -> void:
	OpLog.event(LOG_TAG, [
		"apply_winner_payload payload=", winner_payload,
		" p1=", p1_id,
		" p2=", p2_id,
		" my_uuid=", my_uuid,
		" spectator=", spectator_mode
	])

	var parts := winner_payload.split("|", false)
	if parts.size() < 2:
		OpLog.w(LOG_TAG, ["bad_winner_payload payload=", winner_payload])
		return

	var sender_uuid := String(parts[0])
	var sender_state := String(parts[1])

	if sender_state == "0":
		_show_result_from_state("0")
		return

	var local_state := sender_state
	var winning_player := 0

	if spectator_mode:
		var sender_player := 0

		if sender_uuid == p1_id:
			sender_player = 1
		elif sender_uuid == p2_id:
			sender_player = 2

		winning_player = sender_player

		if sender_state == "-1":
			winning_player = 2 if sender_player == 1 else 1

		local_state = "1" if winning_player == 1 else "-1"
	else:
		if sender_uuid != my_uuid:
			local_state = "-1" if sender_state == "1" else "1"

	OpLog.i(LOG_TAG, [
		"winner_resolved sender_uuid=", sender_uuid,
		" sender_state=", sender_state,
		" local_state=", local_state,
		" winning_player=", winning_player
	])

	_show_result_from_state(local_state, winning_player)

func check_win() -> bool:
	OpLog.d(LOG_TAG, "check_win_start")

	if game_over:
		return true

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

	OpLog.d(LOG_TAG, [
		"check_win_sides p1_empty=", player1_side_empty,
		" p2_empty=", player2_side_empty,
		" p1_store=", pits[6].size(),
		" p2_store=", pits[13].size()
	])

	if not player1_side_empty and not player2_side_empty:
		return false

	OpLog.event(LOG_TAG, [
		"game_over_side_empty p1_empty=", player1_side_empty,
		" p2_empty=", player2_side_empty
	])

	if player1_side_empty:
		OpLog.event(LOG_TAG, "sweep_player2_side_to_store13")
		await _animate_sweep([7, 8, 9, 10, 11, 12], 13)
	elif player2_side_empty:
		OpLog.event(LOG_TAG, "sweep_player1_side_to_store6")
		await _animate_sweep([0, 1, 2, 3, 4, 5], 6)
		_refresh_pit_count_label(6)

	var p1: int = pits[6].size()
	var p2: int = pits[13].size()

	OpLog.event(LOG_TAG, [
		"final_scores p1=", p1,
		" p2=", p2,
		" local_player=", player
	])

	if p1 > p2:
		winner_id = 1
		_show_result_from_state("1" if player == 1 else "-1", 1)
	elif p2 > p1:
		winner_id = 2
		_show_result_from_state("1" if player == 2 else "-1", 2)
	else:
		winner_id = -1
		_show_result_from_state("0")

	return true

func _show_result_from_state(state: String, spectator_winner_player: int = 0) -> void:
	game_over = true
	disp_winner = true
	win_loss_state = state
	is_my_turn = false
	_is_animating = false
	in_replay = false

	_stop_pit_highlights()
	stop_waiting_animation()

	if is_instance_valid(skip_button):
		skip_button.visible = false

	if is_instance_valid(free_turn_label):
		free_turn_label.visible = false

	if not is_instance_valid(win_loss_label):
		return

	if state == "0":
		winner_id = -1
		win_loss_label.text = "DRAW!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
	elif spectator_mode:
		var player_num := spectator_winner_player

		if player_num == 0:
			player_num = 1 if state == "1" else 2

		winner_id = player_num
		win_loss_label.text = "Player {0} Wins!".format([player_num])
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	elif state == "1":
		winner_id = player
		win_loss_label.text = "YOU WIN!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

		if is_instance_valid(player_avatar_display):
			GameUtils._show_win_burst(player_avatar_display)
	else:
		winner_id = 2 if player == 1 else 1
		win_loss_label.text = "YOU LOSE"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

		if is_instance_valid(opp_avatar_display):
			GameUtils._show_win_burst(opp_avatar_display)
	OpLog.event(LOG_TAG, [
		"show_result state=", state,
		" spectator_winner_player=", spectator_winner_player,
		" player=", player,
		" spectator=", spectator_mode,
		" winner_id=", winner_id,
		" win_loss_text=", win_loss_label.text,
		" p1_store=", pits[6].size() if pits.size() > 6 else -1,
		" p2_store=", pits[13].size() if pits.size() > 13 else -1
	])
	win_loss_label.visible = true
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2

	var tween_in := create_tween()
	tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
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
	
func _on_skip_button_pressed() -> void:
	if in_replay:
		OpLog.event(LOG_TAG, "skip_replay_pressed")
		_skip_replay_animation = true

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
	if not is_instance_valid(sent_label):
		OpLog.w(LOG_TAG, "sent_animation_missing_label")
		return

	if game_over:
		OpLog.d(LOG_TAG, "sent_animation_skipped game_over=true")
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

		if not game_over and not spectator_mode and not is_my_turn:
			start_waiting_animation()
		else:
			stop_waiting_animation()
	)
	
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
	
	OpLog.d(LOG_TAG, ["theme_previews_generated themes=", themes_data.keys()])
	return themes_data
	
func _apply_board_sprite_modulate() -> void:
	if not is_instance_valid(board_sprite): return
	var c: Color = current_palette.get("board_sprite_modulate", Color(1, 1, 1)) as Color
	board_sprite.modulate = c
	
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
