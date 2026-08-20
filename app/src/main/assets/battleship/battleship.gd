extends BaseGame

const BOMB_TEXTURE_PATH := preload("res://battleship/bomb.png")
const PLANE_TEXTURE_PATH := preload("res://battleship/plane.png")
const MUSIC_STREAM := preload("res://global/audio/battleship.ogg")
signal replay_finished

var _replay_pending: int = 0
var _replay_token: int = 0
var _data_token: int = 0

var sent_tween: Tween

@onready var state: Label = %StateLabel
@onready var start_button: Button = %StartButton
@onready var fire_button: Button = %FireButton
@onready var shuffle_button: TextureButton = %ShuffleButton
@onready var battleground1: BattleGround = %BattleGround1
@onready var battleground2: BattleGround = %BattleGround2
@onready var battle_area_root: MarginContainer = %BattleAreaRoot
@onready var top_bar: HBoxContainer = %TopBar
@onready var bottom_bar: HBoxContainer = %BottomBar
@onready var p1_board_wrapper: Control = %P1BoardWrapper
@onready var p2_board_wrapper: Control = %P2BoardWrapper
@onready var winner_label: Label = %WinLossLabel
@onready var sent_label: Label = %SentLabel
@onready var spectator_label: Label = %SpecLabel
@onready var p1_avatar_display: TextureButton = %P1AvatarDisplay
@onready var p1_you_label: Label = %P1YouLabel
@onready var p2_you_label: Label = %P2YouLabel
@onready var p2_avatar_display: TextureButton = %P2AvatarDisplay
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
var player = null
var fireMode = false
var is_end = false
var winner = false
var _board_center_pos: Vector2 = Vector2.ZERO
var _board_travel_distance: float = 0.0
var travel_distance: float = 6.0
var travel_anim_duration: float = 2.5
var _clouds_home_pos: Vector2 = Vector2.ZERO
const PLANE_SCALE := 0.45
const BOMB_START_SCALE := 0.15
const BOMB_END_SCALE := 0.01
var _shake_tween: Tween
var replay: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_random_layout_by_size: Dictionary = {}

const RAND48_MULTIPLIER: int = 0x5DEECE66D
const RAND48_ADDEND: int = 0xB
const RAND48_MASK: int = (1 << 48) - 1
const RAND48_DIVISOR: float = 281474976710656.0 # 2^48

var _rand48_state: int = 0
var _rand48_initialized: bool = false
var _ship_creation_draws_consumed: bool = false
var _popup_input_blocked: bool = false
var _on_opponent_board := false

var turn_num: String = ""
var recovery_snapshot_pending: bool = false
var recovery_snapshot_progress: String = ""
var recovery_loaded: bool = false
var recovery_shots: Array[String] = []
var recovery_restore_in_progress: bool = false

const SHIP_TEMPLATES := {
	8:  "pos:2,3&num:0,0,0,0&rot:0|pos:1,0&num:0,0,0&rot:1|pos:4,2&num:0,0,0&rot:1|pos:7,4&num:0,0,0&rot:0|pos:0,4&num:0,0&rot:0|pos:5,6&num:0,0&rot:0|pos:5,0&num:0,0&rot:1",
	9:  "pos:2,0&num:0,0,0,0&rot:0|pos:5,7&num:0,0,0,0&rot:1|pos:0,5&num:0,0,0,0&rot:0|pos:8,3&num:0,0,0&rot:0|pos:2,5&num:0,0,0&rot:0|pos:4,0&num:0,0,0&rot:0|pos:0,0&num:0,0,0&rot:0|pos:6,0&num:0,0,0&rot:0",
	10: "pos:2,7&num:0,0,0,0&rot:1|pos:7,6&num:0,0,0&rot:1|pos:3,1&num:0,0,0&rot:1|pos:2,3&num:0,0&rot:0|pos:7,2&num:0,0&rot:0|pos:0,0&num:0,0&rot:1|pos:2,9&num:0&rot:0|pos:0,6&num:0&rot:1|pos:9,9&num:0&rot:0|pos:0,3&num:0&rot:1",
}

const LOG_TAG := "Battleship"
const DEBUG_BATTLESHIP := false

func dbg(parts: Variant) -> void:
	if DEBUG_BATTLESHIP:
		OpLog.d(LOG_TAG, parts)

func _csv_true_count(csv: String) -> int:
	if csv.is_empty():
		return 0

	var count := 0
	for item in csv.split(",", false):
		if item == "1":
			count += 1
	return count

func _bool_array_true_count(values: Array) -> int:
	var count := 0
	for value in values:
		if bool(value):
			count += 1
	return count

func _bg_summary(bg: BattleGround) -> String:
	if not is_instance_valid(bg):
		return "invalid"

	var sunk := 0
	for ship in bg.ships:
		if is_instance_valid(ship) and ship.is_sunk():
			sunk += 1

	return "name=%s size=%dx%d ships=%d sunk=%d bullets=%d marked=%d" % [
		bg.name,
		bg.columns,
		bg.rows,
		bg.ships.size(),
		sunk,
		_bool_array_true_count(bg.bullets),
		_bool_array_true_count(bg.marked_cells)
	]

# ----- Base overrides -----
func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM

func _get_dev_data() -> String:
	var local_id: String = my_uuid
	if local_id.is_empty():
		local_id = "DEV_LOCAL_PLAYER"

	var opponent_id: String = "DEV_OPPONENT"

	var zero_bullets: String = ",".join(
		PackedStringArray([
			"0", "0", "0", "0", "0", "0", "0", "0",
			"0", "0", "0", "0", "0", "0", "0", "0",
			"0", "0", "0", "0", "0", "0", "0", "0",
			"0", "0", "0", "0", "0", "0", "0", "0",
			"0", "0", "0", "0", "0", "0", "0", "0",
			"0", "0", "0", "0", "0", "0", "0", "0",
			"0", "0", "0", "0", "0", "0", "0", "0",
			"0", "0", "0", "0", "0", "0", "0", "0"
		])
	)

	var report_data: Dictionary = {
		"isYourTurn": false,
		"myPlayerId": local_id,

		"player": "2",
		"player1": opponent_id,
		"player2": local_id,
		"sender": local_id,

		"game": "sea",
		"size": "8",
		"mode": "1,3,3,0",
		"num": "3",
		"version": "0",
		"tver": "5",
		"ios": "26.5.1",
		"build": "EB0c3PUeBgiZ94wrU8jsu",
		"id": "DEV_SEA_REPORT",

		"avatar1": "",
		"avatar2": "",

		"ships1":
			"pos:4,3&num:0,0,0,0&rot:2|" +
			"pos:0,5&num:0,0,0&rot:0|" +
			"pos:7,2&num:0,0,0&rot:2|" +
			"pos:2,5&num:0,0,0&rot:1|" +
			"pos:0,1&num:0,0&rot:0|" +
			"pos:7,4&num:0,0&rot:0|" +
			"pos:4,7&num:0,0&rot:1",

		"ships2":
			"pos:1,7&num:0,0,0,0&rot:1|" +
			"pos:1,0&num:0,0,0&rot:1|" +
			"pos:7,2&num:0,0,0&rot:0|" +
			"pos:0,3&num:0,0,0&rot:0|" +
			"pos:5,1&num:0,0&rot:0|" +
			"pos:2,2&num:0,0&rot:1|" +
			"pos:6,6&num:0,0&rot:1",

		"bullets1": zero_bullets,
		"bullets2": zero_bullets,

		"replay": "4,6|4,7|5,7|4,5|4,4|4,3|6,1",

		"skip_ships":
			"pos:4,1&num:1,1,1,1&rot:0|" +
			"pos:0,0&num:0,0,0&rot:0|" +
			"pos:7,3&num:0,0,0&rot:0|" +
			"pos:-1,-1&num:0,0,0&rot:1|" +
			"pos:0,5&num:0,0&rot:0|" +
			"pos:-1,-1&num:0,0&rot:0|" +
			"pos:4,0&num:1,1&rot:1",

		"skip_bullets":
			"0,0,0,1,0,0,1,0," +
			"0,0,0,1,0,1,1,0," +
			"0,0,0,1,0,1,0,0," +
			"0,0,0,1,0,1,0,0," +
			"0,0,0,1,0,1,0,0," +
			"0,0,0,1,1,1,0,0," +
			"0,0,0,0,0,0,1,0," +
			"0,0,0,0,0,0,0,0",

		"caption": "Your Move."
	}

	return JSON.stringify(report_data)

func _get_rules_title() -> String:
	return "How to Play Sea Battle"

func _get_settings_avatar_display():
	var avatar_display := _get_my_avatar_display()

	if is_instance_valid(avatar_display):
		return avatar_display

	if is_instance_valid(p1_avatar_display):
		return p1_avatar_display

	return p2_avatar_display

func _add_settings_rows(_container, popup_script) -> void:
	popup_script.settings_theme_selected.connect(_on_theme_changed)

@warning_ignore("shadowed_global_identifier")
func _srand48(seed: int) -> void:
	var unsigned_seed: int = seed & 0xffffffff
	_rand48_state = (
		(unsigned_seed << 16) | 0x330e
	) & RAND48_MASK

	_rand48_initialized = true


func _drand48() -> float:
	if not _rand48_initialized:
		_srand48(_rng.randi())

	_rand48_state = (
		RAND48_MULTIPLIER * _rand48_state +
		RAND48_ADDEND
	) & RAND48_MASK

	return float(_rand48_state) / RAND48_DIVISOR

func _configure_battleship_avatar(avatar_button: TextureButton) -> void:
	if not is_instance_valid(avatar_button):
		return

	avatar_button.clip_contents = false
	avatar_button.scale = Vector2.ONE
	avatar_button.custom_minimum_size = Vector2(96.0, 90.0)

	var internal_viewport := avatar_button.get_node_or_null("SubViewportContainer/SubViewport") as SubViewport

	if internal_viewport != null:
		internal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var internal_preview := avatar_button.get_node_or_null("SubViewportContainer") as SubViewportContainer

	if internal_preview != null:
		internal_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		internal_preview.visible = true
		internal_preview.self_modulate = Color.WHITE
		internal_preview.pivot_offset = Vector2(48.0, 140.0)
		internal_preview.scale = Vector2.ONE

func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])

	_configure_battleship_avatar(p1_avatar_display)
	_configure_battleship_avatar(p2_avatar_display)

	if player == null:
		if is_instance_valid(state):
			state.visible = false

		_set_avatar_display_shown(p1_avatar_display, false)
		_set_avatar_display_shown(p2_avatar_display, false)
		_update_you_labels(false)

	_rng.randomize()
	_srand48(_rng.randi())

	if is_instance_valid(battleground1):
		_board_center_pos = battleground1.global_position
	else:
		_board_center_pos = Vector2.ZERO

	if is_instance_valid(clouds_rect):
		_clouds_home_pos = clouds_rect.global_position

	_board_travel_distance = get_viewport_rect().size.x * travel_distance

	if is_instance_valid(start_button):
		start_button.pressed.connect(_on_start_button_pressed)
	if is_instance_valid(fire_button):
		fire_button.pressed.connect(_on_fire_button_pressed)
	if is_instance_valid(shuffle_button):
		shuffle_button.pressed.connect(_on_shuffle_button_pressed)
	if is_instance_valid(fire_button):
		fire_button.visible = false
		fire_button.disabled = true

	if not get_viewport().size_changed.is_connected(_apply_responsive_ui):
		get_viewport().size_changed.connect(_apply_responsive_ui)

	if replay == null or player == null:
		return
		
	OpLog.i(LOG_TAG, ["game_ready player=", player, " localMode=", appPlugin == null])

	if water_rect and water_rect.material is ShaderMaterial:
		var mat := water_rect.material as ShaderMaterial
		if mat.shader:
			var uniforms := mat.shader.get_shader_uniform_list()
			for u in uniforms:
				if u.name == "scroll_x":
					var val = mat.get_shader_parameter("scroll_x")
					if val != null:
						_water_scroll_x = float(val)
					break

func _set_game_data(new_replay: String) -> void:
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", new_replay])

	var parsed = JSON.parse_string(new_replay)
	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, ["set_game_data invalid JSON parsed=", parsed, " raw=", new_replay])
		return

	turn_num = String(parsed.get("num", ""))
	recovery_snapshot_pending = String(parsed.get("_recoveryPending", "false")).to_lower() == "true"
	recovery_snapshot_progress = String(parsed.get("_recoveryProgress", ""))
	recovery_loaded = false
	recovery_shots.clear()
	recovery_restore_in_progress = false

	OpLog.i(LOG_TAG, ["recovery_snapshot_received pending=", recovery_snapshot_pending, " progressLen=", recovery_snapshot_progress.length(), " turn=", turn_num])

	_data_token += 1
	var data_token := _data_token

	_replay_token += 1
	_replay_pending = 0
	emit_signal("replay_finished")

	replay.clear()
	_ensure_clouds_visible()
	var greplay: String = parsed.get("replay", "")
	dbg(["replay_field=", greplay])

	if not greplay.is_empty():
		replay = greplay.split("|", false)
		dbg(["replay_array=", replay])
	else:
		dbg("replay empty")

	var raw_turn = parsed.get("isYourTurn", false)
	dbg(["turn_raw=", raw_turn, " type=", typeof(raw_turn)])
	isTurn = raw_turn

	my_player = parsed.get("myPlayerId", "")

	var payload_player: int = int(parsed.get("player", 0))
	var p1_id: String = parsed.get("player1", "")
	var p2_id: String = parsed.get("player2", "")

	var s1: String = parsed.get("ships1", "")
	var s2: String = parsed.get("ships2", "")
	var bullets1: String = parsed.get("bullets1", "")
	var bullets2: String = parsed.get("bullets2", "")
	var skip: String = parsed.get("skip_ships", "")
	var skip_bullets: String = parsed.get("skip_bullets", "")
	var bsize: int = int(parsed.get("size", 8))
	
	OpLog.i(LOG_TAG, [
		"set_game_data parsed turn=", isTurn,
		" payloadPlayer=", payload_player,
		" localPlayer=", my_player,
		" p1=", p1_id,
		" p2=", p2_id,
		" size=", bsize,
		" replayMoves=", replay.size(),
		" ships1Len=", s1.length(),
		" ships2Len=", s2.length(),
		" bullets1=", _csv_true_count(bullets1),
		" bullets2=", _csv_true_count(bullets2),
		" skipShipsLen=", skip.length(),
		" skipBullets=", _csv_true_count(skip_bullets)
	])

	spectator_mode = my_player != "" and p1_id != "" and p2_id != "" and my_player != p1_id and my_player != p2_id
	OpLog.i(LOG_TAG, ["spectator_mode=", spectator_mode])

	var resolved_player := payload_player

	if spectator_mode:
		resolved_player = 1
		clouds_rect.visible = true
		if is_instance_valid(start_button):
			start_button.visible = false
			start_button.disabled = true
		if is_instance_valid(shuffle_button):
			shuffle_button.visible = false
			shuffle_button.disabled = true
	else:
		if my_player != "" and p1_id != "" and p2_id != "":
			if my_player == p1_id:
				resolved_player = 1
			elif my_player == p2_id:
				resolved_player = 2
		else:
			if isTurn:
				resolved_player = 2 if payload_player == 1 else 1

	player = resolved_player
	_apply_responsive_ui()

	OpLog.i(LOG_TAG, [
		"player_resolve payloadPlayer=", payload_player,
		" myId=", my_player,
		" isTurn=", isTurn,
		" spectator=", spectator_mode,
		" localPlayer=", player
	])

	if is_instance_valid(spectator_label):
		spectator_label.visible = spectator_mode
		_update_you_labels(not spectator_mode)
	else:
		_update_you_labels(true)

	if is_instance_valid(battleground1):
		battleground1.set_size(bsize)
	if is_instance_valid(battleground2):
		battleground2.set_size(bsize)

	_prepare_pins()

	var opponent_avatar_key := ""
	var player_avatar_key := ""

	if player == 1:
		opponent_avatar_key = "avatar2"
		player_avatar_key  = "avatar1"
		myBattleground     = battleground1
		theirBattleground  = battleground2
		myBoardContainer   = player1_container
		theirBoardContainer = player2_container
	else:
		opponent_avatar_key = "avatar1"
		player_avatar_key  = "avatar2"
		myBattleground     = battleground2
		theirBattleground  = battleground1
		myBoardContainer   = player2_container
		theirBoardContainer = player1_container
		
	if spectator_mode:
		if payload_player == 1:
			myBattleground = battleground2
			theirBattleground = battleground1
			myBoardContainer = player2_container
			theirBoardContainer = player1_container
		else:
			myBattleground = battleground1
			theirBattleground = battleground2
			myBoardContainer = player1_container
			theirBoardContainer = player2_container

	var my_bg_name: String = "NULL"
	var their_bg_name: String = "NULL"

	if is_instance_valid(myBattleground):
		my_bg_name = String(myBattleground.name)

	if is_instance_valid(theirBattleground):
		their_bg_name = String(theirBattleground.name)

	OpLog.i(LOG_TAG, ["board_map player=", player, " my=", my_bg_name, " their=", their_bg_name])

	if (not spectator_mode and is_instance_valid(theirBattleground)):
		theirBattleground.set_grid_tint(Color.BLACK)

	var my_avatar := _get_my_avatar_display()
	var opp_avatar := _get_opp_avatar_display()

	if spectator_mode:
		if parsed.has("avatar1"):
			var player1_avatar_string := str(parsed["avatar1"])

			if player1_avatar_string != "":
				p1_avatar_display.call_deferred(
					"update_avatar_from_data",
					GameUtils._parse_avatar_string(
						player1_avatar_string
					)
				)

		if parsed.has("avatar2"):
			var player2_avatar_string := str(parsed["avatar2"])

			if player2_avatar_string != "":
				p2_avatar_display.call_deferred(
					"update_avatar_from_data",
					GameUtils._parse_avatar_string(
						player2_avatar_string
					)
				)

		_set_avatar_display_shown(
			p1_avatar_display,
			true
		)

		_set_avatar_display_shown(
			p2_avatar_display,
			true
		)
	else:
		var loaded_local_from_settings := false

		if is_instance_valid(my_avatar) and my_avatar.has_method("update_display_from_settings"):
			dbg("avatar loading local settings")
			my_avatar.call_deferred("update_display_from_settings")
			loaded_local_from_settings = true

		if not loaded_local_from_settings and parsed.has(player_avatar_key):
			var player_avatar_string := str(parsed[player_avatar_key])

			dbg([
				"avatar local fallback key=",
				player_avatar_key,
				" len=",
				player_avatar_string.length()
			])

			if player_avatar_string != "":
				var player_data := GameUtils._parse_avatar_string(player_avatar_string)

				if is_instance_valid(my_avatar):
					my_avatar.call_deferred("update_avatar_from_data", player_data)

		if parsed.has(opponent_avatar_key):
			var opp_avatar_string := str(parsed[opponent_avatar_key])

			dbg([
				"avatar opponent key=",
				opponent_avatar_key,
				" len=",
				opp_avatar_string.length()
			])

			if opp_avatar_string != "":
				var opp_data := GameUtils._parse_avatar_string(opp_avatar_string)

				if is_instance_valid(opp_avatar):
					opp_avatar.call_deferred("update_avatar_from_data", opp_data)

	if not s1.is_empty():
		dbg(["board_load ships1 len=", s1.length()])
		battleground1.from_encoded(s1)
	else:
		dbg("board_load ships1 empty")

	if not s2.is_empty():
		dbg(["board_load ships2 len=", s2.length()])
		battleground2.from_encoded(s2)
	else:
		dbg("board_load ships2 empty")
	if spectator_mode:
		for bg in [battleground1, battleground2]:
			if not is_instance_valid(bg):
				continue

			for ship in bg.ships:
				ship.visible = false
	var my_ships_encoded := (s1 if player == 1 else s2)
	var has_recovery_progress := not recovery_snapshot_progress.is_empty()

	if not spectator_mode and my_ships_encoded.is_empty() and not has_recovery_progress:
		OpLog.i(LOG_TAG, ["init_board randomize localPlayer=", player, " board=", myBattleground.name])
		_randomize_my_ships(bsize)
	else:
		dbg(["init_board not_randomizing spectator=", spectator_mode, " shipsEmpty=", my_ships_encoded.is_empty(), " recovery=", has_recovery_progress, " player=", player])
	if spectator_mode and not greplay.is_empty():
		OpLog.i(
			LOG_TAG,
			[
				"spectator_replay replayMoves=",
				replay.size()
			]
		)

		_apply_bullets_from_payload(
			battleground1,
			bullets1
		)

		_apply_bullets_from_payload(
			battleground2,
			bullets2
		)

		show_battleground(true)
		_ensure_clouds_visible()

		await get_tree().process_frame

		if data_token != _data_token:
			return

		await play_replay(
			greplay,
			false
		)

		if data_token != _data_token:
			return

	show_battleground(true)
	_ensure_clouds_visible()

	OpLog.i(LOG_TAG, [
		"set_game_data_done turn=", isTurn,
		" spectator=", spectator_mode,
		" replayMoves=", replay.size(),
		" myBoard={", _bg_summary(myBattleground), "}",
		" theirBoard={", _bg_summary(theirBattleground), "}"
	])

	if isTurn and not spectator_mode:
		OpLog.i(LOG_TAG, "enter_turn_flow")
		
		if is_instance_valid(battleground1):
			battleground1.process_mode = Node.PROCESS_MODE_INHERIT
		if is_instance_valid(battleground2):
			battleground2.process_mode = Node.PROCESS_MODE_INHERIT
		_apply_bullets_from_payload(battleground1, bullets1)
		_apply_bullets_from_payload(battleground2, bullets2)


		stop_waiting_animation()

		if await _restore_battleship_recovery(true, greplay):
			OpLog.i(LOG_TAG, "turn_flow recovered_local_shots_skip_opponent_replay")
			return

		if not greplay.is_empty():
			OpLog.i(LOG_TAG, ["turn_flow play_replay moves=", replay.size()])

			_set_setup_mode(false)

			if is_instance_valid(start_button):
				start_button.disabled = true

			if is_instance_valid(shuffle_button):
				shuffle_button.disabled = true
				shuffle_button.modulate.a = 0.0

			if is_instance_valid(state):
				state.text = ""

			await play_replay(greplay, false)

			if data_token != _data_token:
				return

			if await _restore_battleship_recovery():
				return

			await get_tree().create_timer(1.0).timeout

			if data_token != _data_token:
				return

			my_battleground_ready()
		else:
			if await _restore_battleship_recovery():
				return

			OpLog.i(LOG_TAG, "turn_flow initial_setup")
			_set_setup_mode(true)

	else:
		OpLog.i(
			LOG_TAG,
			[
				"wait_flow turn=",
				isTurn,
				" spectator=",
				spectator_mode
			]
		)

		_set_setup_mode(false)

		fireMode = false

		if is_instance_valid(fire_button):
			fire_button.visible = false
			fire_button.disabled = true

		if is_instance_valid(start_button):
			start_button.visible = false
			start_button.disabled = true

		if is_instance_valid(shuffle_button):
			shuffle_button.visible = false
			shuffle_button.disabled = true
			shuffle_button.modulate.a = 0.0

		if is_instance_valid(myBattleground):
			myBattleground.placing_items = false
			myBattleground.can_attack = false

			for ship in myBattleground.ships:
				if is_instance_valid(ship):
					ship.canBeMoved = false

		if is_instance_valid(theirBattleground):
			theirBattleground.placing_items = false
			theirBattleground.can_attack = false
		
		if not skip.is_empty():
			var flipped_skip := _flip_ships_encoded_vertical(skip, bsize)

			OpLog.i(LOG_TAG, [
				"apply_skip_state shipsOriginalLen=", skip.length(),
				" shipsFlippedLen=", flipped_skip.length(),
				" skipBullets=", _csv_true_count(skip_bullets)
			])

			theirBattleground.from_encoded(flipped_skip)

			_apply_bullets_from_payload(
				theirBattleground,
				skip_bullets
			)

		_apply_bullets_from_payload(battleground1, bullets1)
		_apply_bullets_from_payload(battleground2, bullets2)

		if theirBattleground.is_over():
			OpLog.i(LOG_TAG, "opponent_board_already_over")
			mark_end(true)
			return

		if is_instance_valid(state):
			state.text = ""

		if spectator_mode:
			stop_waiting_animation()
			_ensure_clouds_visible()
		else:
			start_waiting_animation()
			myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
			theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED

func _apply_replay_state(preplay: String) -> void:
	if preplay.is_empty() or not is_instance_valid(myBattleground):
		return

	for move in preplay.split("|", false):
		var parts := move.split(",", false)
		if parts.size() < 2:
			continue

		var x := int(parts[0])
		var wire_y := int(parts[1])
		var local_y := _flip_y_index(wire_y, myBattleground.rows)
		var grid := Vector2(x, local_y)

		if grid.x < 0 or grid.x >= myBattleground.columns or grid.y < 0 or grid.y >= myBattleground.rows:
			continue

		myBattleground.replay_fire(grid)

	OpLog.i(LOG_TAG, ["recovery_applied_opponent_state moves=", preplay.split("|", false).size()])

func play_replay(preplay: String, enter_turn_after: bool = true) -> void:
	var moves := preplay.split("|", false)

	OpLog.i(LOG_TAG, [
		"play_replay_start moves=", moves.size(),
		" enterTurnAfter=", enter_turn_after,
		" raw=", preplay
	])

	_ensure_clouds_visible()

	if moves.is_empty():
		OpLog.i(LOG_TAG, "play_replay_empty")
		if enter_turn_after:
			await get_tree().create_timer(1.0).timeout
			my_battleground_ready()
		return

	if not is_instance_valid(myBattleground):
		OpLog.e(LOG_TAG, "play_replay skipped: myBattleground invalid")
		if enter_turn_after:
			await get_tree().create_timer(1.0).timeout
			my_battleground_ready()
		return

	_replay_token += 1
	var token := _replay_token
	_replay_pending = 0

	var scheduled_moves := 0

	for i in range(moves.size()):
		var move := moves[i]
		if move.is_empty():
			continue

		var parts := move.split(",", false)
		if parts.size() < 2:
			OpLog.w(LOG_TAG, ["play_replay malformed move=", move])
			continue

		var x := int(parts[0])
		var wire_y := int(parts[1])
		var local_y := _flip_y_index(wire_y, myBattleground.rows)
		var v := Vector2(x, local_y)

		dbg(["play_replay moveIndex=", i, " raw=", move, " local=", v])

		if v.x < 0 or v.x >= myBattleground.columns or v.y < 0 or v.y >= myBattleground.rows:
			OpLog.w(LOG_TAG, ["play_replay out_of_bounds local=", v, " raw=", move])
			continue

		var start_delay := 0.5 * float(scheduled_moves)

		_replay_pending += 1
		_start_replay_move_async(v, start_delay, token)
		scheduled_moves += 1

	if _replay_pending == 0:
		OpLog.w(LOG_TAG, ["play_replay no_valid_moves raw=", preplay])
		if enter_turn_after:
			await get_tree().create_timer(1.0).timeout
			my_battleground_ready()
		return

	OpLog.i(LOG_TAG, ["play_replay_scheduled pending=", _replay_pending])
	await replay_finished
	await get_tree().process_frame

	if token != _replay_token:
		OpLog.w(LOG_TAG, "play_replay stale token ignored")
		return

	replay.clear()
	_ensure_clouds_visible()

	OpLog.i(
		LOG_TAG,
		[
			"play_replay_done myBoard={",
			_bg_summary(myBattleground),
			"}"
		]
	)

	if enter_turn_after:
		await get_tree().create_timer(1.0).timeout

		if token != _replay_token:
			return

		my_battleground_ready()

func _start_replay_move_async(
	local_pos: Vector2,
	delay: float,
	token: int
) -> void:
	await _run_replay_move(
		local_pos,
		delay,
		token
	)

	if token != _replay_token:
		return

	_replay_pending -= 1
	dbg(["play_replay_move_finished remaining=", _replay_pending])

	if _replay_pending <= 0:
		_replay_pending = 0
		emit_signal("replay_finished")

func _on_shuffle_button_pressed() -> void:
	OpLog.i(
		LOG_TAG,
		[
			"shuffle_pressed turn=",
			isTurn,
			" spectator=",
			spectator_mode,
			" placing=",
			myBattleground.placing_items
				if is_instance_valid(myBattleground)
				else false
		]
	)

	if not _can_edit_ship_placement():
		OpLog.w(
			LOG_TAG,
			"shuffle_ignored placement_not_allowed"
		)
		return

	if not myBattleground.placing_items:
		OpLog.w(
			LOG_TAG,
			"shuffle_ignored not_in_setup_mode"
		)
		return

	_randomize_my_ships(myBattleground.columns)

func _randomize_my_ships(board_size: int) -> void:
	if not is_instance_valid(myBattleground):
		push_error("[RANDOMIZE] Missing BattleGround")
		return

	var template: String = SHIP_TEMPLATES.get(board_size, "")
	if template.is_empty():
		push_warning(
			"[RANDOMIZE] No template for board_size=%d; keeping existing layout" %
			board_size
		)
		return

	var encoded := _build_randomized_encoded(
		template,
		board_size
	)

	if encoded.is_empty():
		push_warning(
			"[RANDOMIZE] generation failed; using known-good template"
		)
		encoded = template

	_last_random_layout_by_size[board_size] = encoded

	OpLog.i(
		LOG_TAG,
		[
			"randomized_ships boardSize=",
			board_size,
			" encoded=",
			encoded
		]
	)

	myBattleground.from_encoded(encoded)

	var setup_enabled := _can_edit_ship_placement()

	myBattleground.placing_items = setup_enabled

	for ship in myBattleground.ships:
		if is_instance_valid(ship):
			ship.canBeMoved = setup_enabled

	for ship in myBattleground.ships:
		if ship == null or not is_instance_valid(ship):
			push_error(
				"[RANDOMIZE] Invalid ship after from_encoded. encoded=" +
				encoded
			)
			return

		ship.canBeMoved = true

func _build_randomized_encoded(
	template: String,
	bsize: int
) -> String:
	var ship_defs: Array[Dictionary] = []

	for piece in template.split("|", false):
		if piece.is_empty():
			continue

		var num_text := ""

		for section in piece.split("&", false):
			if section.begins_with("num:"):
				num_text = section.substr(4)
				break

		if num_text.is_empty():
			continue

		var length := num_text.split(",", false).size()

		ship_defs.append({
			"num_text": num_text,
			"length": length,
		})

	if ship_defs.is_empty():
		return ""

	if not _ship_creation_draws_consumed:
		for _ship_def in ship_defs:
			_drand48()

		_ship_creation_draws_consumed = true

	var occupied: Dictionary = {}
	var placed: Array[String] = []

	for ship_index in range(ship_defs.size()):
		var ship_def: Dictionary = ship_defs[ship_index]
		var length: int = int(ship_def["length"])
		var num_text: String = String(ship_def["num_text"])

		var accepted := false
		var attempts := 0

		const MAX_PLACEMENT_ATTEMPTS := 100000

		while not accepted and attempts < MAX_PLACEMENT_ATTEMPTS:
			attempts += 1

			var x := int(floor(_drand48() * float(bsize)))
			var y := int(floor(_drand48() * float(bsize)))
			var rot := int(floor(_drand48() * 2.0))

			if not _candidate_fits_board(
				x,
				y,
				length,
				rot,
				bsize
			):
				continue

			var cells := _ship_cells(
				x,
				y,
				length,
				rot
			)

			if _candidate_conflicts(
				cells,
				occupied
			):
				continue

			accepted = true

			for cell in cells:
				occupied[cell] = true

			placed.append(
				"pos:%d,%d&num:%s&rot:%d" % [
					x,
					y,
					num_text,
					rot
				]
			)

			OpLog.d(
				LOG_TAG,
				[
					"place shipIndex=",
					ship_index,
					" length=",
					length,
					" x=",
					x,
					" y=",
					y,
					" rot=",
					rot,
					" attempts=",
					attempts
				]
			)

		if not accepted:
			OpLog.e(
				LOG_TAG,
				[
					"place failed shipIndex=",
					ship_index,
					" length=",
					length,
					" attempts=",
					attempts
				]
			)
			return ""

	return "|".join(placed)
	
func _ship_cells(
	x: int,
	y: int,
	length: int,
	rot: int
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	for index in range(length):
		match rot:
			0:
				cells.append(
					Vector2i(x, y + index)
				)

			1:
				cells.append(
					Vector2i(x + index, y)
				)

			2:
				cells.append(
					Vector2i(x, y - index)
				)

			3:
				cells.append(
					Vector2i(x - index, y)
				)

	return cells


func _candidate_fits_board(
	x: int,
	y: int,
	length: int,
	rot: int,
	bsize: int
) -> bool:
	var cells := _ship_cells(
		x,
		y,
		length,
		rot
	)

	for cell in cells:
		if (
			cell.x < 0 or
			cell.y < 0 or
			cell.x >= bsize or
			cell.y >= bsize
		):
			return false

	return true

func _candidate_conflicts(
	cells: Array[Vector2i],
	occupied: Dictionary
) -> bool:
	for cell in cells:
		for offset_x in range(-1, 2):
			for offset_y in range(-1, 2):
				var checked_cell := Vector2i(
					cell.x + offset_x,
					cell.y + offset_y
				)

				if occupied.has(checked_cell):
					return true

	return false

func _ensure_clouds_visible() -> void:
	if not is_instance_valid(clouds_rect):
		return

	var required_cloud_z := clouds_rect.z_index

	if is_instance_valid(player1_container):
		required_cloud_z = max(
			required_cloud_z,
			player1_container.z_index + 5
		)

	if is_instance_valid(player2_container):
		required_cloud_z = max(
			required_cloud_z,
			player2_container.z_index + 5
		)

	clouds_rect.z_index = required_cloud_z
	clouds_rect.visible = true

	var cloud_modulate := clouds_rect.modulate
	cloud_modulate.a = 1.0
	clouds_rect.modulate = cloud_modulate

func _set_avatar_display_shown(display: Control, should_show: bool) -> void:
	if not is_instance_valid(display):
		return

	display.visible = true

	var m: Color = display.modulate
	m.a = 1.0 if should_show else 0.0
	display.modulate = m

const BS_LANDSCAPE_ROTATION := -90.0
const BS_LANDSCAPE_UI_SCALE := 1.5
const BS_BOARD_BASE := 512.0
const BS_BOARD_HEIGHT_FRACTION := 0.8

func _is_landscape() -> bool:
	var vp := get_viewport_rect().size
	return vp.x > vp.y

func _fit_center_label(l: Label) -> void:
	var m: Vector2 = l.get_theme_font("font").get_string_size(
		l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")
	) + Vector2(24.0, 12.0)
	l.offset_left = -m.x * 0.5
	l.offset_right = m.x * 0.5
	l.offset_top = -m.y * 0.5
	l.offset_bottom = m.y * 0.5
	l.pivot_offset = m * 0.5

var _pin_homes: Dictionary = {}

var _pins_ready := false

func _pinned_nodes() -> Array:
	return [
		rules_button, settings_button, shuffle_button, state,
		choose_target_label, fire_button, start_button,
		p1_you_label, p2_you_label,
		p1_avatar_display, p2_avatar_display
	]

func _prepare_pins() -> void:
	if _pins_ready:
		return
	_pins_ready = true

	var hidden: Array = []
	for c in _pinned_nodes():
		if is_instance_valid(c) and not c.visible:
			hidden.append([c, c.modulate.a])
			c.modulate.a = 0.0
			c.visible = true

	await get_tree().process_frame
	await get_tree().process_frame

	for c in _pinned_nodes():
		if is_instance_valid(c) and c.get_parent() != self and c.size.x > 1.0 and c.size.y > 1.0:
			_pin_homes[c] = Rect2(c.global_position, c.size)

	for c in _pinned_nodes():
		if is_instance_valid(c) and _pin_homes.has(c):
			c.reparent(self)
			c.set_anchors_preset(Control.PRESET_TOP_LEFT)

	for entry in hidden:
		var c: Control = entry[0]
		if is_instance_valid(c):
			c.visible = false
			c.modulate.a = entry[1]

	_apply_responsive_ui()

func _capture_pin_home(_c: Control) -> void:
	pass

func _pin_to_root(c: Control, anchor: Vector2, off: Vector2, sz: Vector2) -> void:
	if not _pin_homes.has(c):
		return
	c.rotation_degrees = 0.0
	c.pivot_offset = Vector2.ZERO
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = off.x
	c.offset_top = off.y
	c.offset_right = off.x + sz.x
	c.offset_bottom = off.y + sz.y

func _unpin_from_root(c: Control) -> void:
	if not _pin_homes.has(c):
		return
	var r: Rect2 = _pin_homes[c]
	_pin_to_root(c, Vector2.ZERO, r.position, r.size)

var _avatar_rects: Dictionary = {}

var _flight_nodes: Array = []
var _ui_was_land := -1

func _clear_flight_nodes() -> void:
	for n in _flight_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_flight_nodes.clear()

func _capture_avatar_rect(c: Control) -> void:
	if not _avatar_rects.has(c) and c.get_parent() != self and c.size.x > 1.0:
		_avatar_rects[c] = Rect2(c.global_position, c.size)

func _refresh_action_controls() -> void:
	await get_tree().process_frame
	var land := _is_landscape()
	var s := BS_LANDSCAPE_UI_SCALE if land else 1.0
	var counter := -BS_LANDSCAPE_ROTATION if land else 0.0
	choose_target_label.add_theme_font_size_override("font_size", int(28.0 * s))
	if is_instance_valid(start_button):
		start_button.reset_size()
		start_button.pivot_offset = start_button.size * 0.5
		start_button.rotation_degrees = counter
	if is_instance_valid(fire_button):
		fire_button.add_theme_font_size_override("font_size", int(32.0 * s))

func _apply_responsive_ui() -> void:
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	var land := vp.x > vp.y
	var s := BS_LANDSCAPE_UI_SCALE if land else 1.0
	var land_i := 1 if land else 0
	if _ui_was_land != -1 and _ui_was_land != land_i:
		_clear_flight_nodes()
	_ui_was_land = land_i

	if land:
		battle_area_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var want := Vector2(vp.y, vp.x)
		var mins := battle_area_root.get_combined_minimum_size()
		var actual := Vector2(maxf(want.x, mins.x), maxf(want.y, mins.y))
		battle_area_root.size = actual
		battle_area_root.pivot_offset = actual * 0.5
		battle_area_root.rotation_degrees = BS_LANDSCAPE_ROTATION
		battle_area_root.position = (vp - actual) * 0.5
	else:
		battle_area_root.rotation_degrees = 0.0
		battle_area_root.pivot_offset = Vector2.ZERO
		battle_area_root.set_anchors_preset(Control.PRESET_FULL_RECT, true)
		battle_area_root.offset_left = 0.0
		battle_area_root.offset_top = 0.0
		battle_area_root.offset_right = 0.0
		battle_area_root.offset_bottom = 0.0

	var my_avatar := _get_my_avatar_display()
	var my_you_label: Label = p1_you_label if my_avatar == p1_avatar_display else p2_you_label
	var pad := 20.0
	var bsz := Vector2(96.0, 96.0) if land else Vector2(56.0, 56.0)
	var gutter_w := (vp.x - vp.y * BS_BOARD_HEIGHT_FRACTION) * 0.5
	var gutter_c := gutter_w * 0.5

	for c in [rules_button, settings_button, shuffle_button, state, my_avatar, my_you_label]:
		if is_instance_valid(c):
			_capture_pin_home(c)

	if land:
		_pin_to_root(rules_button, Vector2(0.0, 0.0),
			Vector2(gutter_c - bsz.x * 0.5, pad), bsz)
		_pin_to_root(settings_button, Vector2(1.0, 0.0),
			Vector2(-gutter_c - bsz.x * 0.5, pad), bsz)
		_pin_to_root(shuffle_button, Vector2(1.0, 1.0),
			Vector2(-gutter_c - bsz.x * 0.5, -pad - bsz.y), bsz)
		var av := Vector2(96.0, 90.0) * s
		var youh := 24.0 * s
		var lbl := Vector2(gutter_w * 0.9, 44.0)
		var y0 := -lbl.y * 0.5 - 8.0 - youh - av.y
		if is_instance_valid(my_avatar):
			_pin_to_root(my_avatar, Vector2(0.0, 0.5),
				Vector2(gutter_c - av.x * 0.5, y0), av)
			_pin_to_root(my_you_label, Vector2(0.0, 0.5),
				Vector2(gutter_c - av.x * 0.5, y0 + av.y), Vector2(av.x, youh))
			var their_avatar := _get_opp_avatar_display()
			if is_instance_valid(their_avatar):
				_capture_pin_home(their_avatar)
				_pin_to_root(their_avatar, Vector2(0.0, 0.5),
					Vector2(gutter_c - av.x * 0.5, y0), av)
			for a in [my_avatar, their_avatar]:
				if is_instance_valid(a):
					a.custom_minimum_size = av
					var prev := a.get_node_or_null("SubViewportContainer") as SubViewportContainer
					if prev != null:
						prev.scale = Vector2.ONE * s
		else:
			y0 = -lbl.y * 0.5
		_pin_to_root(state, Vector2(0.0, 0.5), Vector2(gutter_c - lbl.x * 0.5, -lbl.y * 0.5), lbl)
		var cth := 76.0
		_capture_pin_home(choose_target_label)
		_pin_to_root(choose_target_label, Vector2(1.0, 0.5),
			Vector2(-gutter_c - lbl.x * 0.5, -cth * 0.5), Vector2(lbl.x, cth))
		_capture_pin_home(fire_button)
		_pin_to_root(fire_button, Vector2(1.0, 0.5),
			Vector2(-gutter_c - lbl.x * 0.5, -42.0), Vector2(lbl.x, 84.0))
	else:
		_unpin_from_root(rules_button)
		_unpin_from_root(settings_button)
		_unpin_from_root(shuffle_button)
		_unpin_from_root(state)
		_unpin_from_root(choose_target_label)
		_unpin_from_root(fire_button)
		for a in [my_avatar, _get_opp_avatar_display()]:
			if is_instance_valid(a):
				a.custom_minimum_size = Vector2(96.0, 90.0)
				var prev := a.get_node_or_null("SubViewportContainer") as SubViewportContainer
				if prev != null:
					prev.scale = Vector2.ONE
				_unpin_from_root(a)
	_unpin_from_root(p1_you_label)
	_unpin_from_root(p2_you_label)

	rules_button.custom_minimum_size = bsz
	settings_button.custom_minimum_size = bsz
	shuffle_button.custom_minimum_size = bsz
	var wide := Vector2(gutter_w * 0.75, 84.0) if land else Vector2(200.0, 56.0)
	start_button.custom_minimum_size = wide
	fire_button.custom_minimum_size = wide
	start_button.add_theme_font_size_override("font_size", int(32.0 * s))
	fire_button.add_theme_font_size_override("font_size", int(32.0 * s))

	state.add_theme_font_size_override("font_size", int(28.0 * s))
	my_you_label.add_theme_font_size_override("font_size", int(18.0 * s))
	spectator_label.add_theme_font_size_override("font_size", int(50.0 * s))
	for l in [waiting_label, winner_label, sent_label]:
		l.add_theme_font_size_override("font_size", int(25.0 * s))
		_fit_center_label(l)

	var k := 1.0
	if land:
		k = (vp.y * BS_BOARD_HEIGHT_FRACTION) / BS_BOARD_BASE
	p1_board_wrapper.custom_minimum_size = Vector2.ONE * BS_BOARD_BASE * k
	p2_board_wrapper.custom_minimum_size = Vector2.ONE * BS_BOARD_BASE * k
	battleground1.scale = Vector2.ONE * k
	battleground2.scale = Vector2.ONE * k

	await get_tree().process_frame

	if land:
		var gutter_center: float = (vp.x - vp.y * BS_BOARD_HEIGHT_FRACTION) * 0.25
		battle_area_root.add_theme_constant_override(
			"margin_top", int(maxf(gutter_center - top_bar.size.y * 0.5, 0.0))
		)
		battle_area_root.add_theme_constant_override(
			"margin_bottom", int(maxf(gutter_center - bottom_bar.size.y * 0.5, 0.0))
		)
	else:
		battle_area_root.add_theme_constant_override("margin_top", 30)
		battle_area_root.add_theme_constant_override("margin_bottom", 30)

	_refresh_action_controls()

func _get_my_avatar_display() -> Control:
	if player == 1:
		return p1_avatar_display
	elif player == 2:
		return p2_avatar_display
	return null

func _get_opp_avatar_display() -> Control:
	if player == 1:
		return p2_avatar_display
	elif player == 2:
		return p1_avatar_display
	return null
	
func _can_edit_ship_placement() -> bool:
	return (
		isTurn and
		not spectator_mode and
		not is_end and
		is_instance_valid(myBattleground)
	)

func _set_setup_mode(enabled: bool) -> void:
	var setup_enabled := (
		enabled and
		_can_edit_ship_placement()
	)

	if is_instance_valid(state):
		state.text = "Arrange your ships"
		state.visible = setup_enabled

	if is_instance_valid(myBattleground):
		myBattleground.placing_items = setup_enabled

		for ship in myBattleground.ships:
			if is_instance_valid(ship):
				ship.canBeMoved = setup_enabled

	if is_instance_valid(start_button):
		start_button.visible = setup_enabled
		start_button.disabled = (
			not setup_enabled or
			myBattleground.has_conflict
		)

	if is_instance_valid(shuffle_button):
		shuffle_button.visible = setup_enabled
		shuffle_button.disabled = not setup_enabled
		shuffle_button.modulate.a = 1.0 if setup_enabled else 0.0

	if spectator_mode:
		_set_avatar_display_shown(
			p1_avatar_display,
			true
		)

		_set_avatar_display_shown(
			p2_avatar_display,
			true
		)

		_update_you_labels(false)
	else:
		var my_avatar := _get_my_avatar_display()
		var should_show_avatar := not setup_enabled

		_set_avatar_display_shown(
			my_avatar,
			should_show_avatar
		)

		_update_you_labels(
			should_show_avatar
		)

func show_battleground(mine: bool) -> void:
	if (
		not is_instance_valid(myBoardContainer) or
		not is_instance_valid(theirBoardContainer)
	):
		return

	_set_board_active(
		myBoardContainer,
		myBattleground,
		mine
	)

	_set_board_active(
		theirBoardContainer,
		theirBattleground,
		not mine
	)

	_on_opponent_board = not mine
	_ensure_clouds_visible()
	call_deferred("_ensure_clouds_visible")

func _set_board_active(container: Control, board: BattleGround, active: bool) -> void:
	if not is_instance_valid(container) or not is_instance_valid(board):
		return

	container.visible = true
	container.modulate.a = 1.0 if active else 0.0

	if spectator_mode:
		board.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		board.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

func _save_battleship_progress() -> void:
	if recovery_restore_in_progress or spectator_mode or not isTurn or not is_instance_valid(myBattleground):
		return

	var progress := {
		"phase": "attack",
		"turn": turn_num,
		"ships": myBattleground.encode_ships(),
		"shots": recovery_shots
	}

	if appPlugin != null:
		appPlugin.saveTurnProgress(JSON.stringify(progress))

	OpLog.i(LOG_TAG, ["recovery_saved turn=", turn_num, " shots=", recovery_shots.size(), " shipsLen=", String(progress["ships"]).length()])

func send_update():
	OpLog.i(LOG_TAG, ["send_update_start player=", player, " isEnd=", is_end, " winner=", winner])

	if not is_instance_valid(myBattleground):
		OpLog.e(LOG_TAG, "send_update skipped: myBattleground invalid")
		return

	if myBattleground.rows <= 0 or myBattleground.columns <= 0:
		OpLog.e(LOG_TAG, ["send_update invalid dimensions rows=", myBattleground.rows, " cols=", myBattleground.columns])
		return

	for ship in myBattleground.ships:
		if ship == null or not is_instance_valid(ship):
			OpLog.e(LOG_TAG, "send_update invalid ship found before encode_ships")
			return

	var myEncoded := myBattleground.encode_ships()
	if myEncoded == null:
		OpLog.e(LOG_TAG, "send_update encode_ships returned null")
		return

	var bullets := myBattleground.encode_bullets()
	if bullets == null:
		OpLog.e(LOG_TAG, "send_update encode_bullets returned null")
		return

	var flipped_ships := _flip_ships_encoded_vertical(myEncoded, myBattleground.rows)
	var flipped_bullets := _flip_bullets_vertical(bullets, myBattleground.rows, myBattleground.columns)

	var msg := {
		"bullets" + str(player): flipped_bullets,
	}

	if not myEncoded.is_empty():
		msg["ships" + str(player)] = flipped_ships
	else:
		dbg("send_update skipping empty ships")

	var my_avatar := _get_my_avatar_display()
	if is_instance_valid(my_avatar) and my_avatar.has_method("get_avatar_data_string"):
		var avatar_key := "avatar%d" % player
		msg[avatar_key] = my_avatar.call("get_avatar_data_string")
		dbg(["send_update avatarKey=", avatar_key])

	var replay_str := ""
	if not replay.is_empty():
		replay_str = "|".join(replay)
		msg["replay"] = replay_str

		if is_instance_valid(theirBattleground):
			msg["skip_ships"] = theirBattleground.encode_ships()
			msg["skip_bullets"] = theirBattleground.encode_bullets()

	if is_end:
		msg["winner"] = my_player + "|" + ("1" if winner else "-1")

	var encoded := JSON.stringify(msg)

	OpLog.event(LOG_TAG, [
		"send_game_out player=", player,
		" replayMoves=", replay.size(),
		" shipsLen=", myEncoded.length(),
		" bullets=", _csv_true_count(bullets),
		" winner=", str(msg.get("winner", "")),
		" myBoard={", _bg_summary(myBattleground), "}",
		" theirBoard={", _bg_summary(theirBattleground), "}",
		" raw=", encoded
	])

	send_game_data(encoded)

	replay.clear()

	if not is_end:
		play_sent_animation()

		if _on_opponent_board:
			_swap_to_opponent_board(true)

func my_battleground_ready():
	print("[MY_BATTLEGROUND_READY] Entered")
	if spectator_mode:
		print("[MY_BATTLEGROUND_READY] Spectator - skipping turn flow.")
		return
	if theirBattleground.is_empty():
		print("[MY_BATTLEGROUND_READY] TheirBattleground is empty → sending update immediately.")
		send_update()
		return

	if myBattleground.is_over():
		print("[MY_BATTLEGROUND_READY] MyBattleground is already over → mark_end(false).")
		mark_end(false)
		return
		
	_set_setup_mode(false)

	fireMode = true

	if is_instance_valid(state):
		state.visible = false
		state.text = ""

	shuffle_button.disabled = true
	shuffle_button.modulate.a = 0
	start_button.visible = false
	start_button.disabled = true

	theirBattleground.set_attack()

	print("[MY_BATTLEGROUND_READY] About to swap to opponent board (reverse=false)")
	_swap_to_opponent_board(false)
	print("[MY_BATTLEGROUND_READY] Returned from _swap_to_opponent_board")

func _swap_to_opponent_board(reverse: bool = false) -> void:
	print("\n[SWAP] === _swap_to_opponent_board called. reverse=", reverse, " ===")
	if not is_instance_valid(myBattleground) or not is_instance_valid(theirBattleground):
		print("[SWAP] battlegrounds not valid")
		show_battleground(false)
		return
	if not is_instance_valid(myBoardContainer) or not is_instance_valid(theirBoardContainer):
		print("[SWAP] board containers not valid")
		show_battleground(false)
		return

	var screen_rect := get_viewport_rect()
	var screen_width: float = screen_rect.size.x

	var my_home: Vector2 = myBoardContainer.global_position
	var their_home: Vector2 = theirBoardContainer.global_position

	var my_avatar := _get_my_avatar_display()
	var their_avatar := _get_opp_avatar_display()
	var my_avatar_home: Vector2 = Vector2.ZERO
	var their_avatar_home: Vector2 = Vector2.ZERO

	if is_instance_valid(my_avatar):
		my_avatar_home = my_avatar.global_position
	if is_instance_valid(their_avatar):
		their_avatar_home = their_avatar.global_position

	var travel_distance_local: float = screen_width * 3.0
	var offset := Vector2(travel_distance_local, 0.0)

	print("[SWAP] my_home=", my_home, " their_home=", their_home, " travel_distance_local=", travel_distance_local)

	myBoardContainer.set_as_top_level(true)
	theirBoardContainer.set_as_top_level(true)

	if is_instance_valid(my_avatar):
		my_avatar.set_as_top_level(true)
		my_avatar.visible = true
		my_avatar.modulate.a = 1.0

	if is_instance_valid(their_avatar):
		their_avatar.set_as_top_level(true)
		their_avatar.visible = true
		their_avatar.modulate.a = 1.0

	var base_z: int = max(myBoardContainer.z_index, theirBoardContainer.z_index)
	print("[SWAP] base_z=", base_z, " (pre-adjust z_index: my=", myBoardContainer.z_index, " their=", theirBoardContainer.z_index, ")")

	if reverse:
		myBoardContainer.z_index = base_z + 1
		theirBoardContainer.z_index = base_z
	else:
		theirBoardContainer.z_index = base_z + 1
		myBoardContainer.z_index = base_z

	if is_instance_valid(my_avatar):
		my_avatar.z_index = myBoardContainer.z_index + 1
	if is_instance_valid(their_avatar):
		their_avatar.z_index = theirBoardContainer.z_index + 1

	print("[SWAP] post-adjust z_index: my=", myBoardContainer.z_index, " their=", theirBoardContainer.z_index)

	var my_start_pos: Vector2
	var my_target_pos: Vector2
	var their_start_pos: Vector2
	var their_target_pos: Vector2

	var my_avatar_start_pos: Vector2
	var my_avatar_target_pos: Vector2
	var their_avatar_start_pos: Vector2
	var their_avatar_target_pos: Vector2

	if reverse:
		my_start_pos = my_home - offset
		my_target_pos = my_home
		their_start_pos = their_home
		their_target_pos = their_home + offset

		my_avatar_start_pos = my_avatar_home - offset
		my_avatar_target_pos = my_avatar_home
		their_avatar_start_pos = their_avatar_home
		their_avatar_target_pos = their_avatar_home + offset
	else:
		my_start_pos = my_home
		my_target_pos = my_home - offset
		their_start_pos = their_home + offset
		their_target_pos = their_home

		my_avatar_start_pos = my_avatar_home
		my_avatar_target_pos = my_avatar_home - offset
		their_avatar_start_pos = their_avatar_home + offset
		their_avatar_target_pos = their_avatar_home

	print("[SWAP] my_start_pos=", my_start_pos, " my_target_pos=", my_target_pos)
	print("[SWAP] their_start_pos=", their_start_pos, " their_target_pos=", their_target_pos)

	myBoardContainer.visible = true
	myBoardContainer.modulate.a = 1.0
	
	theirBoardContainer.visible = true
	theirBoardContainer.modulate.a = 1.0

	myBoardContainer.global_position = my_start_pos
	theirBoardContainer.global_position = their_start_pos

	if is_instance_valid(my_avatar):
		my_avatar.global_position = my_avatar_start_pos
	if is_instance_valid(their_avatar):
		their_avatar.global_position = their_avatar_start_pos

	if is_instance_valid(p1_you_label):
		p1_you_label.visible = false
	if is_instance_valid(p2_you_label):
		p2_you_label.visible = false

	if is_instance_valid(fire_button):
		fire_button.visible = false
		fire_button.disabled = true
	if is_instance_valid(choose_target_label):
		choose_target_label.visible = false

	print("[SWAP] Disabling both battlegrounds process_mode before tween.")
	if not spectator_mode:
		myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
		theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED

	var clouds_tween: Tween
	if clouds_rect and clouds_rect.material is ShaderMaterial:
		print("[SWAP] Setting up clouds tween.")
		var cmat := clouds_rect.material as ShaderMaterial

		clouds_rect.z_index = max(myBoardContainer.z_index, theirBoardContainer.z_index) + 5
		clouds_rect.visible = true

		var viewport_size: Vector2 = screen_rect.size
		var view_center: Vector2 = viewport_size / 2.0
		var board_span: float = BS_BOARD_BASE * battleground1.scale.x
		clouds_rect.custom_minimum_size = Vector2(board_span * 2.4, board_span * 1.6)
		var cloud_size := Vector2(
			maxf(clouds_rect.custom_minimum_size.x, viewport_size.x),
			maxf(clouds_rect.custom_minimum_size.y, viewport_size.y)
		)
		var cloud_offset: Vector2 = cloud_size / 2.0
		var cloud_container: Control = myBoardContainer if reverse else theirBoardContainer
		var cloud_bg = myBattleground if reverse else theirBattleground
		var cloud_x_offset: float = cloud_container.size.x * 0.5
		if is_instance_valid(cloud_bg) and is_instance_valid(cloud_container):
			cloud_x_offset = (
				cloud_bg.global_position.x
				+ BS_BOARD_BASE * cloud_bg.scale.x * 0.5
				- cloud_container.global_position.x
			)

		var incoming_start_pos: Vector2 = my_start_pos if reverse else their_start_pos
		var incoming_target_pos: Vector2 = my_target_pos if reverse else their_target_pos

		var clouds_start_pos: Vector2 = Vector2(incoming_start_pos.x + cloud_x_offset, view_center.y) - cloud_offset
		var clouds_target_pos: Vector2 = Vector2(incoming_target_pos.x + cloud_x_offset, view_center.y) - cloud_offset

		clouds_rect.global_position = clouds_start_pos
		clouds_rect.modulate.a = 1.0

		clouds_tween = create_tween().set_parallel(true)
		clouds_tween.tween_property(
			clouds_rect,
			"global_position",
			clouds_target_pos,
			travel_anim_duration
		).set_trans(
			Tween.TRANS_SINE
		).set_ease(
			Tween.EASE_IN_OUT
		)

		var sw_start_val = cmat.get_shader_parameter("swipe_offset")
		var sw_start := float(sw_start_val if sw_start_val != null else 0.0)
		var dir := -1.0 if reverse else 1.0
		var sw_end: float = sw_start + travel_distance_local * 0.001 * dir

		print("[SWAP] Clouds swipe_offset from ", sw_start, " to ", sw_end)
		clouds_tween.tween_method(func(v): cmat.set_shader_parameter("swipe_offset", v), sw_start, sw_end, travel_anim_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var main_tween := create_tween().set_parallel(true)
	print("[SWAP] Starting main_tween for board and avatar slide.")

	main_tween.parallel().tween_property(
		myBoardContainer, "global_position",
		my_target_pos, travel_anim_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	main_tween.parallel().tween_property(
		theirBoardContainer, "global_position",
		their_target_pos, travel_anim_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if is_instance_valid(my_avatar):
		main_tween.parallel().tween_property(
			my_avatar, "global_position",
			my_avatar_target_pos, travel_anim_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if is_instance_valid(their_avatar):
		main_tween.parallel().tween_property(
			their_avatar, "global_position",
			their_avatar_target_pos, travel_anim_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if water_rect and water_rect.material is ShaderMaterial:
		print("[SWAP] Setting up water swipe tween.")
		var wmat := water_rect.material as ShaderMaterial
		var w_start_val = wmat.get_shader_parameter("swipe_offset")
		var w_start := float(w_start_val if w_start_val != null else 0.0)
		var dir := -1.0 if reverse else 1.0
		var w_end: float = w_start + travel_distance_local * 0.002 * dir

		print("[SWAP] Water swipe_offset from ", w_start, " to ", w_end)
		main_tween.parallel().tween_method(func(v): wmat.set_shader_parameter("swipe_offset", v), w_start, w_end, travel_anim_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await main_tween.finished
	print("[SWAP] main_tween finished.")

	var incoming_container: Control
	var incoming_battleground: BattleGround
	var leaving_container: Control
	var leaving_battleground: BattleGround
	var incoming_avatar: Control
	var leaving_avatar: Control

	if reverse:
		incoming_container = myBoardContainer
		incoming_battleground = myBattleground
		leaving_container = theirBoardContainer
		leaving_battleground = theirBattleground
		incoming_avatar = my_avatar
		leaving_avatar = their_avatar
	else:
		incoming_container = theirBoardContainer
		incoming_battleground = theirBattleground
		leaving_container = myBoardContainer
		leaving_battleground = myBattleground
		incoming_avatar = their_avatar
		leaving_avatar = my_avatar

	print("[SWAP] incoming_battleground=", incoming_battleground.name, " leaving_battleground=", leaving_battleground.name)

	myBoardContainer.set_as_top_level(false)
	theirBoardContainer.set_as_top_level(false)
	myBoardContainer.global_position = my_home
	theirBoardContainer.global_position = their_home

	if is_instance_valid(my_avatar):
		my_avatar.set_as_top_level(false)
		my_avatar.global_position = my_avatar_home

	if is_instance_valid(their_avatar):
		their_avatar.set_as_top_level(false)
		their_avatar.global_position = their_avatar_home

	_set_board_active(leaving_container, leaving_battleground, false)
	_set_board_active(incoming_container, incoming_battleground, true)

	if is_instance_valid(leaving_avatar):
		leaving_avatar.visible = true
		leaving_avatar.modulate.a = 0.0

	if is_instance_valid(incoming_avatar):
		incoming_avatar.visible = true
		incoming_avatar.modulate.a = 1.0

	if reverse:
		_update_you_labels(not spectator_mode)
	else:
		_update_you_labels(false)

	print("[SWAP] After _set_board_active calls.")

	if is_instance_valid(choose_target_label) and not reverse and not spectator_mode:
		choose_target_label.visible = true
		choose_target_label.modulate.a = 0.0
		choose_target_label.z_index = clouds_rect.z_index + 1
		var label_tween := create_tween()
		label_tween.tween_property(choose_target_label, "modulate:a", 1.0, 1.0)
		print("[SWAP] choose_target_label fade-in tween started.")

	_on_opponent_board = not reverse
	print("[SWAP] === _swap_to_opponent_board END ===\n")

func _update_you_labels(show_you: bool = true) -> void:
	if is_instance_valid(p1_you_label):
		p1_you_label.visible = true
		p1_you_label.modulate.a = 0.0

	if is_instance_valid(p2_you_label):
		p2_you_label.visible = true
		p2_you_label.modulate.a = 0.0

	if not show_you or spectator_mode:
		return

	if player == 1 and is_instance_valid(p1_you_label):
		p1_you_label.text = "You"
		p1_you_label.modulate.a = 1.0
	elif player == 2 and is_instance_valid(p2_you_label):
		p2_you_label.text = "You"
		p2_you_label.modulate.a = 1.0

func _process(_delta: float) -> void:
	var menu_open: bool = get("_settings_open") == true or get("_rules_open") == true

	if menu_open:
		if not _popup_input_blocked:
			_popup_input_blocked = true

			if is_instance_valid(battleground1):
				battleground1.process_mode = Node.PROCESS_MODE_DISABLED
			if is_instance_valid(battleground2):
				battleground2.process_mode = Node.PROCESS_MODE_DISABLED
			if is_instance_valid(fire_button):
				fire_button.disabled = true

		return

	if _popup_input_blocked:
		_popup_input_blocked = false

		if spectator_mode:
			if is_instance_valid(battleground1):
				battleground1.process_mode = Node.PROCESS_MODE_INHERIT
			if is_instance_valid(battleground2):
				battleground2.process_mode = Node.PROCESS_MODE_INHERIT
		elif fireMode:
			if is_instance_valid(myBattleground):
				myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
			if is_instance_valid(theirBattleground):
				theirBattleground.process_mode = Node.PROCESS_MODE_INHERIT
		elif is_instance_valid(myBattleground) and myBattleground.placing_items:
			myBattleground.process_mode = Node.PROCESS_MODE_INHERIT
			if is_instance_valid(theirBattleground):
				theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			if is_instance_valid(myBattleground):
				myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
			if is_instance_valid(theirBattleground):
				theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED

	if spectator_mode or not fireMode or not is_instance_valid(theirBattleground):
		return
	
	var tg := theirBattleground.targeting_grid
	var has_target := tg.x >= 0 and tg.y >= 0 and theirBattleground.can_attack
	
	if has_target:
		if is_instance_valid(choose_target_label):
			choose_target_label.visible = false
		
		if is_instance_valid(fire_button):
			fire_button.visible = true
			_refresh_action_controls()
			fire_button.disabled = false
	else:
		if is_instance_valid(fire_button):
			fire_button.visible = false
			fire_button.disabled = true
		
		if is_instance_valid(choose_target_label):
			if theirBattleground.process_mode == Node.PROCESS_MODE_INHERIT:
				choose_target_label.visible = true
				choose_target_label.modulate.a = 0.0
				choose_target_label.z_index = clouds_rect.z_index + 1
				var label_tween := create_tween()
				label_tween.tween_property(choose_target_label, "modulate:a", 1.0, 1.0)

func _flip_y_index(y: int, rows: int) -> int:
	return (rows - 1) - y

func _flip_bullets_vertical(bullets_str: String, rows: int, cols: int) -> String:
	if bullets_str.is_empty():
		return ""
	
	var list := bullets_str.split(",")
	if list.size() != rows * cols:
		print("[FLIP] Warning: Bullet list size mismatch. Returning original.")
		return bullets_str

	var new_list: Array[String] = []
	new_list.resize(list.size())

	for y in range(rows):
		for x in range(cols):
			var src_idx := y * cols + x
			var dst_idx := (rows - 1 - y) * cols + x
			new_list[dst_idx] = list[src_idx]

	return ",".join(new_list)

func _apply_bullets_from_payload(bg: BattleGround, wire_bullets: String) -> void:
	if wire_bullets.is_empty() or not is_instance_valid(bg):
		return

	var local_bullets := _flip_bullets_vertical(wire_bullets, bg.rows, bg.columns)
	bg.from_bullets(local_bullets)

func _flip_ships_encoded_vertical(encoded: String, rows: int) -> String:
	print("FLIP SHIPS ENCODED VERTICAL CALLED!")
	if encoded.is_empty():
		return encoded
	print("FLIP SHIPS ENCODED VERTICAL NOT EMPTY!")
	var pieces := encoded.split("|", false)
	var flipped_pieces: Array[String] = []

	for piece in pieces:
		if piece.is_empty():
			continue

		var sections := piece.split("&", false)
		var x := 0
		var y := 0
		var rot := 0
		var length := 1

		for section in sections:
			if section.begins_with("pos:"):
				var coords := section.substr(4).split(",", false)
				if coords.size() >= 2:
					x = coords[0].to_int()
					y = coords[1].to_int()
			elif section.begins_with("rot:"):
				rot = section.substr(4).to_int()
			elif section.begins_with("num:"):
				length = section.substr(4).split(",", false).size()

		var new_y := 0
		if rot == 1:
			new_y = (rows - 1) - y
		else:
			new_y = (rows - 1) - (y + length - 1)

		var new_sections: Array[String] = []
		for section in sections:
			print("Updating Sections!")
			if section.begins_with("pos:"):
				new_sections.append("pos:%d,%d" % [x, new_y])
			elif section.begins_with("num:") and rot == 0:
				var nums = section.substr(4).split(",", false)
				print("FLIPPING VERTICAL SHIP NUM FROM: ", nums)
				nums.reverse()
				print("TO: ", nums)
				new_sections.append("num:" + ",".join(nums))
			else:
				new_sections.append(section)

		flipped_pieces.append("&".join(new_sections))

	return "|".join(flipped_pieces)

func _on_fire_button_pressed() -> void:
	OpLog.i(LOG_TAG, "fire_pressed")

	if not fireMode or not is_instance_valid(theirBattleground):
		OpLog.w(LOG_TAG, ["fire_ignored fireMode=", fireMode, " theirValid=", is_instance_valid(theirBattleground)])
		return

	var grid := theirBattleground.targeting_grid
	if grid.x < 0 or grid.y < 0:
		OpLog.w(LOG_TAG, ["fire_no_target grid=", grid])
		return

	var top_x := int(grid.x)
	var top_y := _flip_y_index(int(grid.y), theirBattleground.rows)
	var move_str := "%d,%d" % [top_x, top_y]

	replay.append(move_str)
	recovery_shots.append(move_str)
	_save_battleship_progress()

	OpLog.i(LOG_TAG, ["fire_start grid=", grid, " wire=", move_str, " committedShots=", recovery_shots.size()])
	
	if is_instance_valid(fire_button):
		fire_button.disabled = true
		fire_button.visible = false 

	theirBattleground.targeting_grid = Vector2(-1, -1)
	theirBattleground.can_attack = false
	fireMode = false

	if is_instance_valid(choose_target_label):
		choose_target_label.visible = false

	dbg("fire bomb_animation_start")
	await _play_bomb_fall_animation_for_board(theirBattleground, grid, false, 2.0)
	dbg("fire bomb_animation_done")

	dbg(["fire replay=", replay])


	var hit: bool = theirBattleground.fire(grid)
	OpLog.i(LOG_TAG, ["fire_result grid=", grid, " wire=", move_str, " hit=", hit, " replayMoves=", replay.size()])

	if not hit:
		await get_tree().create_timer(1.0).timeout
		OpLog.i(LOG_TAG, "fire_miss_send_update")
		send_update()
	else:
		var vp := get_viewport()
		if vp != null:
			if _shake_tween and _shake_tween.is_running():
				_shake_tween.kill()
				vp.canvas_transform = Transform2D.IDENTITY

			_shake_tween = create_tween()

			_shake_tween.tween_method(
				func(alpha: float) -> void:
					var offset := Vector2(
						randf_range(-1.0, 1.0),
						randf_range(-1.0, 1.0)
					) * 6.0 * alpha
					vp.canvas_transform = Transform2D(0.0, offset),
				1.0,
				0.0,
				0.25
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

			_shake_tween.tween_callback(func() -> void:
				vp.canvas_transform = Transform2D.IDENTITY
			)
		
		if theirBattleground.is_over():
			OpLog.i(LOG_TAG, "fire_win_send_final_update")
			mark_end(true)
			send_update()
		else:
			await get_tree().create_timer(0.5).timeout
			
			fireMode = true
			theirBattleground.can_attack = true
			
			if is_instance_valid(fire_button):
				fire_button.disabled = false
				fire_button.modulate.a = 0.0
				fire_button.visible = true
				_refresh_action_controls()
				
				var button_tween := create_tween()
				button_tween.tween_property(fire_button, "modulate:a", 1.0, 0.5)
			
			if is_instance_valid(choose_target_label):
				choose_target_label.modulate.a = 0.0
				choose_target_label.visible = true 
				
				choose_target_label.z_index = clouds_rect.z_index + 1
				var label_tween := create_tween()
				label_tween.tween_property(choose_target_label, "modulate:a", 1.0, 1.0)
				
			OpLog.i(LOG_TAG, "fire_hit_extra_turn")

func _restore_battleship_recovery(require_committed_shot: bool = false, opponent_replay: String = "") -> bool:
	if recovery_loaded or spectator_mode or not isTurn:
		return false

	if recovery_snapshot_pending:
		recovery_loaded = true
		fireMode = false
		_set_setup_mode(false)

		if is_instance_valid(fire_button):
			fire_button.visible = false
			fire_button.disabled = true

		if is_instance_valid(choose_target_label):
			choose_target_label.visible = false

		if is_instance_valid(myBattleground):
			myBattleground.can_attack = false

		if is_instance_valid(theirBattleground):
			theirBattleground.can_attack = false

		stop_waiting_animation()
		OpLog.i(LOG_TAG, "recovery_pending_send")
		return true

	if recovery_snapshot_progress.is_empty():
		return false

	var parsed: Variant = JSON.parse_string(recovery_snapshot_progress)
	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.w(LOG_TAG, ["recovery_invalid_json len=", recovery_snapshot_progress.length()])
		return false

	var progress: Dictionary = parsed

	if String(progress.get("phase", "")) != "attack":
		return false

	var saved_turn := String(progress.get("turn", ""))
	if not saved_turn.is_empty() and not turn_num.is_empty() and saved_turn != turn_num:
		OpLog.i(LOG_TAG, ["recovery_stale savedTurn=", saved_turn, " currentTurn=", turn_num])
		return false

	var restored_shots: Array[String] = []
	var raw_shots: Variant = progress.get("shots", [])

	if typeof(raw_shots) == TYPE_ARRAY:
		for value in raw_shots:
			restored_shots.append(String(value))
	elif typeof(raw_shots) == TYPE_STRING:
		var parsed_shots: Variant = JSON.parse_string(String(raw_shots))
		if typeof(parsed_shots) == TYPE_ARRAY:
			for value in parsed_shots:
				restored_shots.append(String(value))

	if require_committed_shot and restored_shots.is_empty():
		return false

	if require_committed_shot and not opponent_replay.is_empty():
		_apply_replay_state(opponent_replay)

	recovery_loaded = true
	recovery_restore_in_progress = true
	recovery_shots.clear()
	recovery_shots.append_array(restored_shots)

	var saved_ships := String(progress.get("ships", ""))

	if is_instance_valid(myBattleground) and myBattleground.ships.is_empty() and not saved_ships.is_empty():
		myBattleground.from_encoded(saved_ships)

	replay.clear()
	for move in recovery_shots:
		replay.append(move)

	_set_setup_mode(false)
	stop_waiting_animation()

	OpLog.i(LOG_TAG, ["recovery_loaded turn=", turn_num, " shots=", recovery_shots.size(), " shipsLen=", saved_ships.length()])

	if is_instance_valid(theirBattleground) and theirBattleground.is_empty():
		recovery_restore_in_progress = false
		send_update()
		return true

	if recovery_shots.is_empty():
		recovery_restore_in_progress = false
		my_battleground_ready()
		return true

	theirBattleground.set_attack()
	theirBattleground.can_attack = false
	show_battleground(false)

	var last_hit := true

	for move in recovery_shots:
		var parts := move.split(",", false)
		if parts.size() < 2:
			continue

		var x := int(parts[0])
		var wire_y := int(parts[1])
		var grid := Vector2(x, _flip_y_index(wire_y, theirBattleground.rows))

		if grid.x < 0 or grid.x >= theirBattleground.columns or grid.y < 0 or grid.y >= theirBattleground.rows:
			continue

		await _play_bomb_fall_animation_for_board(theirBattleground, grid, false, 2.0)
		last_hit = theirBattleground.fire(grid)

	recovery_restore_in_progress = false

	if theirBattleground.is_over():
		mark_end(true)
		send_update()
		return true

	if not last_hit:
		await get_tree().create_timer(1.0).timeout
		send_update()
		return true

	fireMode = true
	theirBattleground.set_attack()

	if is_instance_valid(state):
		state.visible = false
		state.text = ""

	if is_instance_valid(start_button):
		start_button.visible = false
		start_button.disabled = true

	if is_instance_valid(shuffle_button):
		shuffle_button.visible = false
		shuffle_button.disabled = true
		shuffle_button.modulate.a = 0.0

	if is_instance_valid(choose_target_label):
		choose_target_label.visible = true

	OpLog.i(LOG_TAG, "recovery_hit_extra_turn")
	return true

func _play_bomb_fall_animation_for_board(board: BattleGround, grid_pos: Vector2, from_right: bool, plane_duration: float = 2.0) -> void:
	if not is_instance_valid(board):
		OpLog.e(LOG_TAG, "bomb_animation skipped: missing board")
		return
	
	var bomb_tex: Texture2D = BOMB_TEXTURE_PATH
	var plane_tex: Texture2D = PLANE_TEXTURE_PATH
	
	if bomb_tex == null:
		OpLog.e(LOG_TAG, "bomb_animation skipped: bomb texture missing")
		return
	if plane_tex == null:
		OpLog.e(LOG_TAG, "bomb_animation skipped: plane texture missing")
		return
	
	var cell_center_local: Vector2 = board.grid_to_coord(
		grid_pos + Vector2(0.5, 0.5)
	)
	var board_size: Vector2 = board.rect_size
	
	var plane_width: float = plane_tex.get_size().x * PLANE_SCALE
	var plane_height: float = plane_tex.get_size().y * PLANE_SCALE
	
	var plane_y := cell_center_local.y - board_size.y * 0.45
	
	var vp_w: float = get_viewport_rect().size.x
	var board_scale: float = maxf(board.scale.x, 0.001)
	var board_origin_x: float = board.global_position.x
	var left_edge_local: float = -board_origin_x / board_scale
	var right_edge_local: float = (vp_w - board_origin_x) / board_scale
	var margin_local: float = plane_width * 0.5 + 8.0 / board_scale
	
	var plane_start: Vector2
	var plane_end: Vector2
	
	if from_right:
		plane_start = Vector2(right_edge_local + margin_local, plane_y)
		plane_end = Vector2(left_edge_local - margin_local, plane_y)
	else:
		plane_start = Vector2(left_edge_local - margin_local, plane_y)
		plane_end = Vector2(right_edge_local + margin_local, plane_y)
	
	var plane := Sprite2D.new()
	plane.texture = plane_tex
	plane.centered = true
	plane.position = plane_start
	plane.scale = Vector2(PLANE_SCALE, PLANE_SCALE)
	plane.z_index = 1000
	
	if from_right:
		plane.rotation = PI 
	
	board.add_child(plane)
	_flight_nodes.append(plane)
	
	var bomb := Sprite2D.new()
	bomb.texture = bomb_tex
	bomb.centered = true
	bomb.visible = false
	
	if from_right:
		bomb.rotation = PI
	
	board.add_child(bomb)
	
	var bomb_above_z: int = 1100
	var bomb_below_z: int = 0
	if is_instance_valid(clouds_rect):
		bomb_above_z = clouds_rect.z_index + 1
		bomb_below_z = clouds_rect.z_index - 1
	
	bomb.z_index = bomb_above_z
	
	var plane_tween := create_tween()
	plane_tween.tween_property(
		plane, "position",
		plane_end, plane_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	var fraction := (cell_center_local.x - plane_start.x) / (plane_end.x - plane_start.x)
	fraction = clamp(fraction, 0.0, 1.0)
	
	var spawn_delay := (plane_duration * fraction) - 0.1
	spawn_delay = max(0.0, spawn_delay)
	
	await get_tree().create_timer(spawn_delay).timeout
	
	var drop_x: float = lerp(plane_start.x, plane_end.x, fraction)
	var plane_drop_pos: Vector2 = Vector2(drop_x, plane.position.y)
	var bomb_offset_y: float = plane_height * 0.15
	if from_right:
		bomb_offset_y *= -1.0
	
	var bomb_start: Vector2 = plane_drop_pos + Vector2(0.0, bomb_offset_y)
	var bomb_end: Vector2 = cell_center_local
	
	bomb.position = bomb_start
	bomb.scale = Vector2(BOMB_START_SCALE, BOMB_START_SCALE)
	bomb.visible = true
	if is_instance_valid(clouds_rect) and not from_right:
		var z_swap := create_tween()
		z_swap.tween_callback(
			func():
				if is_instance_valid(bomb):
					bomb.z_index = bomb_below_z
		).set_delay(1.0)
	var bomb_fall_duration := plane_duration
	
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
	
	_flight_nodes.erase(bomb)
	_flight_nodes.erase(plane)
	if is_instance_valid(bomb):
		bomb.queue_free()
	if is_instance_valid(plane):
		plane.queue_free()

func _run_replay_move(
	local_pos: Vector2,
	delay: float,
	token: int
) -> void:
	await get_tree().create_timer(delay).timeout

	if token != _replay_token:
		return

	await _play_bomb_fall_animation_for_board(
		myBattleground,
		local_pos,
		true,
		2.0
	)

	if token != _replay_token:
		return

	if is_instance_valid(myBattleground):
		var hit: bool = myBattleground.replay_fire(
			local_pos
		)
		if hit:
			_haptic_explosion(1.0, 45)
		OpLog.i(LOG_TAG, ["replay_fire pos=", local_pos, " hit=", hit])
		await get_tree().process_frame
	else:
		OpLog.w(LOG_TAG, "replay_fire skipped: myBattleground invalid")

	dbg(["replay_visual_done pos=", local_pos])

func mark_end(win: bool):
	state.text = ""
	var my_avatar := _get_my_avatar_display()
	var opp_avatar := _get_opp_avatar_display()
	dbg("mark_end disabling opponent process mode")
	stop_waiting_animation()
	winner = win
	is_end = true
	if win:
		if not spectator_mode:
			winner_label.text = "YOU WIN!"
		else:
			winner_label.text = "Player 1 Wins!"
		winner_label.visible = true
		winner_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		if is_instance_valid(my_avatar):
			GameUtils._show_win_burst(my_avatar)
		OpLog.i(LOG_TAG, "game_end win=true")
		return true
	else:
		if not spectator_mode:
			winner_label.text = "YOU LOSE"
			winner_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		else:
			winner_label.text = "Player 2 Wins"
			winner_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		winner_label.visible = true
		if is_instance_valid(opp_avatar):
			GameUtils._show_win_burst(opp_avatar)
		OpLog.i(LOG_TAG, "game_end win=false")
		return true

func _on_start_button_pressed() -> void:
	OpLog.i(
		LOG_TAG,
		[
			"start_pressed fireMode=",
			fireMode,
			" turn=",
			isTurn,
			" spectator=",
			spectator_mode,
			" placing=",
			myBattleground.placing_items
				if is_instance_valid(myBattleground)
				else false
		]
	)

	if fireMode:
		return

	if not _can_edit_ship_placement():
		OpLog.w(
			LOG_TAG,
			"start_ignored placement_not_allowed"
		)
		_set_setup_mode(false)
		return

	if not myBattleground.placing_items:
		OpLog.w(
			LOG_TAG,
			"start_ignored not_in_setup_mode"
		)
		return

	if myBattleground.has_conflict:
		OpLog.w(
			LOG_TAG,
			"start_ignored board_has_conflict"
		)
		return

	recovery_shots.clear()
	_save_battleship_progress()
	myBattleground.placing_items = false

	for ship in myBattleground.ships:
		if is_instance_valid(ship):
			ship.canBeMoved = false

	_set_setup_mode(false)

	my_battleground_ready()

func _on_battle_ground_is_valid(valid: bool) -> void:
	if not is_instance_valid(start_button):
		return

	var can_start := (
		valid and
		_can_edit_ship_placement() and
		is_instance_valid(myBattleground) and
		myBattleground.placing_items
	)

	start_button.disabled = not can_start
	start_button.visible = can_start

func _haptic_explosion(strength: float = 1.0, duration_ms: int = 45) -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return

	strength = clampf(strength, 0.0, 1.0)
	Input.vibrate_handheld(duration_ms, strength)

func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Sea Battle[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
• Be the first commander to locate and sink all of your opponent's hidden ships.
• Protect your own fleet while strategically firing upon the enemy grid.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• [b]Setup:[/b] Drag and rotate your ships to place them on the grid. Ships cannot overlap or touch each other.
• [b]Attack:[/b] On your turn, tap a cell on the enemy grid to fire a shot.
• [b]Hit:[/b] If you strike a ship, you will see an explosion.
• [b]Miss:[/b] If you hit open water, a splash marker will appear.
• [b]Sinking:[/b] A ship sinks only when all of its occupied cells have been hit.
[/font_size]

[font_size={24px}][b]End of Game[/b][/font_size]
[font_size={18px}]
• The game ends immediately when one player has sunk the opponent's entire fleet.
• The survivor is declared the winner!
[/font_size]
"""

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		OpLog.w(LOG_TAG, "play_sent_animation skipped: sent_label invalid")
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
