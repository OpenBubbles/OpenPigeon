extends Control

const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const RULES_POPUP_SCENE = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")
const BOMB_TEXTURE_PATH := preload("res://battleship/bomb.png")
const PLANE_TEXTURE_PATH := preload("res://battleship/plane.png")
const MUSIC_STREAM := preload("res://global/audio/battleship.ogg")
signal replay_finished

var _replay_pending: int = 0
var _replay_token: int = 0


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
@onready var p1_avatar_display = %P1AvatarDisplay
@onready var p1_you_label: Label = %P1YouLabel
@onready var p2_you_label: Label = %P2YouLabel
@onready var p2_avatar_display = %P2AvatarDisplay
@onready var choose_target_label: Label = %ChooseTargetLabel
@onready var water_rect: ColorRect = %WaterRect
@onready var clouds_rect: ColorRect = %CloudsRect
@onready var player1_container: Control = %Player1BoardContainer
@onready var player2_container: Control = %Player2BoardContainer

var _water_scroll_x: float = 0.0
var isTurn = false
var appPlugin = null
var mediaPlugin = null
var myBattleground: BattleGround = null
var theirBattleground: BattleGround = null
var myBoardContainer: Control = null
var theirBoardContainer: Control = null
var my_player
var my_uuid: String = ""
var player = null
var game_settings_category: String = ""
var spectator_mode: bool = false
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

const USE_DIAGONAL_BUFFER := false
const SHIP_TEMPLATES := {
	8:  "pos:2,3&num:0,0,0,0&rot:0|pos:1,0&num:0,0,0&rot:1|pos:4,2&num:0,0,0&rot:1|pos:7,4&num:0,0,0&rot:0|pos:0,4&num:0,0&rot:0|pos:5,6&num:0,0&rot:0|pos:5,0&num:0,0&rot:1",
	9:  "pos:2,0&num:0,0,0,0&rot:0|pos:5,7&num:0,0,0,0&rot:1|pos:0,5&num:0,0,0,0&rot:0|pos:8,3&num:0,0,0&rot:0|pos:2,5&num:0,0,0&rot:0|pos:4,0&num:0,0,0&rot:0|pos:0,0&num:0,0,0&rot:0|pos:6,0&num:0,0,0&rot:0",
	10: "pos:2,7&num:0,0,0,0&rot:1|pos:7,6&num:0,0,0&rot:1|pos:3,1&num:0,0,0&rot:1|pos:2,3&num:0,0&rot:0|pos:7,2&num:0,0&rot:0|pos:0,0&num:0,0&rot:1|pos:2,9&num:0&rot:0|pos:0,6&num:0&rot:1|pos:9,9&num:0&rot:0|pos:0,3&num:0&rot:1",
}

const BUFFER_OFFSETS_ORTHO: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

const BUFFER_OFFSETS_DIAG: Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

func _ready() -> void:
	if Engine.has_singleton("OpenPigeonMedia"):
		mediaPlugin = Engine.get_singleton("OpenPigeonMedia")
		print("OpenPigeonMedia plugin is available")
	else:
		print("OpenPigeonMedia plugin is not available")

	_start_music()
	appPlugin = Engine.get_singleton("AppPlugin")
	
	if appPlugin:
		print("App plugin is available")
		appPlugin.connect("set_game_data", _set_game_data)
		my_uuid = appPlugin.getSenderUUID()
		appPlugin.onReady()
	else:
		print("App plugin is not available, using dev data")
		my_uuid = "0a602920-2033-469d-aab8-5e832c5d4f6a"

		var dev_data := { #SETUP SCREEN PLAYER 1
			"size": 9,
			"isYourTurn": true,
			"player": 2,
			"myPlayerId": "DEV_PLAYER",
			"replay": "",
			"bullets1": "",
			"bullets2": "",
			"skip_ships": "",
			"ships1": "",
			"ships2": "",
		}
		
		#var dev_data := { #SETUP SCREEN PLAYER 2 (PLAYER 1 Has Chosen Board)
			#"size": 8,
			#"isYourTurn": true,
			#"player": 1,
			#"myPlayerId": "DEV_PLAYER",
			#"replay": "",
			#"bullets1": "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0",
			#"bullets2": "",
			#"skip_ships": "",
			#"ships1": "pos:2,3&num:0,0,0,0&rot:0|pos:1,0&num:0,0,0&rot:1|pos:4,2&num:0,0,0&rot:1|pos:7,4&num:0,0,0&rot:0|pos:0,4&num:0,0&rot:0|pos:5,6&num:0,0&rot:0|pos:5,0&num:0,0&rot:1",
			#"ships2": "",
		#}
		
		#var dev_data := { #Player 1 Sent a Shot after player 2 sent one
			#"size": 8,
			#"isYourTurn": true,
			#"player": 1,
			#"myPlayerId": "DEV_PLAYER",
			#"replay": "0,1",
			#"bullets1": "0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0",
			#"bullets2": "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0",
			#"skip_ships": "pos:2,2&num:0,0,0,0&rot:0|pos:7,5&num:0,0,0&rot:0|pos:4,3&num:0,0,0&rot:1|pos:1,0&num:0,0,0&rot:1|pos:5,0&num:0,0&rot:1|pos:0,4&num:0,0&rot:0|pos:4,6&num:0,0&rot:0",
			#"ships1": "pos:2,1&num:0,0,0,0&rot:0|pos:5,5&num:0,0,0&rot:1|pos:1,7&num:0,0,0&rot:1|pos:7,1&num:0,0,0&rot:0|pos:5,7&num:0,0&rot:1|pos:0,2&num:0,0&rot:0|pos:5,0&num:0,0&rot:0",
			#"ships2": "pos:2,2&num:0,0,0,0&rot:0|pos:7,5&num:0,0,0&rot:0|pos:4,3&num:0,0,0&rot:1|pos:1,0&num:0,0,0&rot:1|pos:5,0&num:0,0&rot:1|pos:0,4&num:0,0&rot:0|pos:4,6&num:0,0&rot:0",
		#}

		_set_game_data(JSON.stringify(dev_data))
	_rng.randomize()
	
	if is_instance_valid(battleground1):
		_board_center_pos = battleground1.global_position
	else:
		_board_center_pos = Vector2.ZERO
		
	if is_instance_valid(clouds_rect):
		_clouds_home_pos = clouds_rect.global_position

	_board_travel_distance = get_viewport_rect().size.x * travel_distance
	
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
	if is_instance_valid(shuffle_button):
		shuffle_button.pressed.connect(_on_shuffle_button_pressed)
	if is_instance_valid(fire_button):
		fire_button.visible = false
		fire_button.disabled = true

	if replay == null or player == null:
		return
		
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
	print("\n==========================")
	print("[SET_GAME_DATA] NEW PAYLOAD RECEIVED")
	print("==========================")
	print("[RAW JSON STRING]: ", new_replay)

	var parsed = JSON.parse_string(new_replay)
	if typeof(parsed) != TYPE_DICTIONARY:
		print("[SET_GAME_DATA] ERROR: Parsed payload is not a Dictionary. Parsed value: ", parsed)
		return

	print("[PARSED DATA]: ", parsed)

	replay.clear()
	var greplay: String = parsed.get("replay", "")
	print("[REPLAY FIELD FROM PAYLOAD]: ", greplay)

	if not greplay.is_empty():
		replay = greplay.split("|", false)
		print("[REPLAY ARRAY PARSED]: ", replay)
	else:
		print("[REPLAY] No moves in replay")

	var raw_turn = parsed.get("isYourTurn", false)
	print("[TURN RAW] value:", raw_turn, " typeof=", typeof(raw_turn))
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
	var bsize: int = int(parsed.get("size", 8))

	print("[PLAYER TURN FLAG isYourTurn]: ", isTurn)
	print("[PAYLOAD PLAYER]: ", payload_player)
	print("[MY PLAYER ID]: ", my_player)
	print("[P1 ID]: ", p1_id, "  [P2 ID]: ", p2_id)
	print("[BOARD SIZE]: ", bsize)
	print("[SHIPS1]: ", s1)
	print("[SHIPS2]: ", s2)
	print("[BULLETS1]: ", bullets1)
	print("[BULLETS2]: ", bullets2)
	print("[SKIP_SHIPS]: ", skip)

	spectator_mode = my_player != "" and p1_id != "" and p2_id != "" and my_player != p1_id and my_player != p2_id
	print("[SPECTATOR MODE]: ", spectator_mode)

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

	print("[PLAYER RESOLVE] payload_player=", payload_player,
		" my_id=", my_player,
		" p1_id=", p1_id,
		" p2_id=", p2_id,
		" isTurn=", isTurn,
		" spectator_mode=", spectator_mode,
		" => LOCAL PLAYER = ", player,
		" (", ("P1" if player == 1 else "P2"), ")")

	if is_instance_valid(spectator_label):
		spectator_label.visible = spectator_mode
		_update_you_labels(not spectator_mode)
	else:
		_update_you_labels(true)

	if is_instance_valid(battleground1):
		battleground1.set_size(bsize)
	if is_instance_valid(battleground2):
		battleground2.set_size(bsize)

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

	print("[BOARD MAP] Local player is P", player,
		" -> myBattleground=", (myBattleground.name if is_instance_valid(myBattleground) else "NULL"),
		", theirBattleground=", (theirBattleground.name if is_instance_valid(theirBattleground) else "NULL"))

	if is_instance_valid(theirBattleground):
		theirBattleground.set_grid_tint(Color.BLACK)

	var my_avatar := _get_my_avatar_display()
	var opp_avatar := _get_opp_avatar_display()

	var had_avatar_from_payload := false

	if parsed.has(player_avatar_key):
		var player_avatar_string: String = str(parsed[player_avatar_key])
		print("[AVATAR] Player avatar string (", player_avatar_key, "): ", player_avatar_string)
		var player_data: Dictionary = _parse_avatar_string(player_avatar_string)
		if is_instance_valid(my_avatar):
			my_avatar.call_deferred("update_avatar_from_data", player_data)
		had_avatar_from_payload = true

	if parsed.has(opponent_avatar_key):
		var opp_avatar_string: String = str(parsed[opponent_avatar_key])
		print("[AVATAR] Opponent avatar string (", opponent_avatar_key, "): ", opp_avatar_string)
		var opp_data: Dictionary = _parse_avatar_string(opp_avatar_string)
		if is_instance_valid(opp_avatar):
			opp_avatar.call_deferred("update_avatar_from_data", opp_data)
		had_avatar_from_payload = true

	if not had_avatar_from_payload:
		print("[AVATAR] No avatar strings in payload; using settings-based avatar for local player.")
		if is_instance_valid(my_avatar) and my_avatar.has_method("update_display_from_settings"):
			my_avatar.call_deferred("update_display_from_settings")

	if not s1.is_empty():
		print("[BOARD LOAD] Applying ships1 to battleground1 (P1 board)")
		battleground1.from_encoded(s1)
	else:
		print("[BOARD LOAD] ships1 is empty; battleground1 starts empty")

	if not s2.is_empty():
		print("[BOARD LOAD] Applying ships2 to battleground2 (P2 board)")
		battleground2.from_encoded(s2)
	else:
		print("[BOARD LOAD] ships2 is empty; battleground2 starts empty")
	_apply_spectator_ship_hiding()
	var my_ships_encoded := (s1 if player == 1 else s2)

	if not spectator_mode and my_ships_encoded.is_empty():
		print("[INIT BOARD] No existing ships for local player P", player, " → generating random layout on ", myBattleground.name)
		_randomize_my_ships(bsize)
	else:
		print("[INIT BOARD] Not randomizing: spectator_mode=", spectator_mode,
			" my_ships_empty=", my_ships_encoded.is_empty(),
			" (P", player, ")")
	if spectator_mode and not greplay.is_empty():
		print("[SET_GAME_DATA] Spectator replay: preparing board and playing replay.")
		_apply_bullets_from_payload(battleground1, bullets1)
		_apply_bullets_from_payload(battleground2, bullets2)
		show_battleground(false)
		await get_tree().process_frame
		if not greplay.is_empty():
			play_replay(greplay, false)
	show_battleground(true)

	print("[SET_GAME_DATA] FINAL isTurn: ", isTurn, "  spectator_mode: ", spectator_mode)
	print("[SET_GAME_DATA] replay array: ", replay)

	if isTurn and not spectator_mode:
		print("[SET_GAME_DATA] It IS our turn. Entering 'my turn' flow.")
		
		if is_instance_valid(battleground1):
			battleground1.process_mode = Node.PROCESS_MODE_INHERIT
		if is_instance_valid(battleground2):
			battleground2.process_mode = Node.PROCESS_MODE_INHERIT
		_apply_bullets_from_payload(battleground1, bullets1)
		_apply_bullets_from_payload(battleground2, bullets2)


		stop_waiting_animation()

		if not greplay.is_empty():
			print("[SET_GAME_DATA] Replay is NOT empty. Will play last move from: ", greplay)

			_set_setup_mode(false)
			if is_instance_valid(start_button):
				start_button.disabled = true
			if is_instance_valid(shuffle_button):
				shuffle_button.disabled = true
				shuffle_button.modulate.a = 0.0
			if is_instance_valid(state):
				state.text = ""

			play_replay(greplay)
		else:
			print("[SET_GAME_DATA] Replay is EMPTY. This is initial setup for our board.")
			_set_setup_mode(true)

	else:
		print("[SET_GAME_DATA] It is NOT our turn, or we are a spectator. isTurn=", isTurn, " spectator_mode=", spectator_mode)
		_set_setup_mode(false)
		if is_instance_valid(start_button):
			start_button.disabled = true
		
		if not skip.is_empty():
			var flipped_skip := _flip_ships_encoded_vertical(skip, bsize)
			print("[SET_GAME_DATA] Applying skip_ships layout to opponent board with vertical flip. original=", skip, " flipped=", flipped_skip)
			theirBattleground.from_encoded(flipped_skip)

		_apply_bullets_from_payload(battleground1, bullets1)
		_apply_bullets_from_payload(battleground2, bullets2)

		if theirBattleground.is_over():
			print("[SET_GAME_DATA] Opponent board is already over -> we won.")
			mark_end(true)
			return

		if is_instance_valid(state):
			state.text = ""

		start_waiting_animation()
		if not spectator_mode:
			myBattleground.process_mode = Node.PROCESS_MODE_DISABLED
			theirBattleground.process_mode = Node.PROCESS_MODE_DISABLED

var music_player: AudioStreamPlayer = null

func _start_music() -> void:
	if mediaPlugin and not mediaPlugin.isMusicEnabled():
		return

	if music_player == null:
		music_player = AudioStreamPlayer.new()
		music_player.name = "MusicPlayer"
		music_player.stream = MUSIC_STREAM
		music_player.volume_db = -4.0
		add_child(music_player)

	if not music_player.playing:
		music_player.play()
		
func _stop_music() -> void:
	if music_player:
		music_player.stop()
	
func _exit_tree() -> void:
	_stop_music()

func _apply_spectator_ship_hiding() -> void:
	if not spectator_mode:
		return

	for bg in [battleground1, battleground2]:
		if not is_instance_valid(bg):
			continue
		for ship in bg.ships:
			ship.visible = false
		
func play_replay(preplay: String, enter_turn_after: bool = true) -> void:
	print("\n========== PLAY_REPLAY START ==========")
	print("[PLAY_REPLAY] Incoming replay string: ", preplay)
	
	clouds_rect.visible = false
	var m := clouds_rect.modulate
	m.a = 0.0
	clouds_rect.modulate = m

	var moves := preplay.split("|", false)
	print("[PLAY_REPLAY] Parsed moves: ", moves)

	if moves.is_empty():
		print("[PLAY_REPLAY] No moves to replay — entering my turn immediately.")
		print("========== PLAY_REPLAY END — EMPTY ==========\n")
		if enter_turn_after:
			await get_tree().create_timer(1.0).timeout
			my_battleground_ready()
		return

	if not is_instance_valid(myBattleground):
		print("[PLAY_REPLAY] ERROR — myBattleground is not valid.")
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
			print("[PLAY_REPLAY] ERROR — malformed move entry: ", move)
			continue

		var x := int(parts[0])
		var wire_y := int(parts[1])

		var local_y := _flip_y_index(wire_y, myBattleground.rows)
		var v := Vector2(x, local_y)

		print("[PLAY_REPLAY] Move ", i, "/", moves.size() - 1,
			" raw=(", x, ",", wire_y, ")",
			" local=(", v.x, ",", v.y, ")")

		if v.x < 0 or v.x >= myBattleground.columns or v.y < 0 or v.y >= myBattleground.rows:
			print("[PLAY_REPLAY] WARNING — local coords out of bounds, skipping move: ", v)
			continue

		var start_delay := 0.5 * float(scheduled_moves)

		_replay_pending += 1
		_start_replay_move_async(v, start_delay, token)

		scheduled_moves += 1

	if _replay_pending == 0:
		print("[PLAY_REPLAY] No valid moves parsed; entering my turn.")
		print("========== PLAY_REPLAY END — NONE SCHEDULED ==========\n")
		if enter_turn_after:
			await get_tree().create_timer(1.0).timeout
			my_battleground_ready()
		return

	print("[PLAY_REPLAY] Scheduled ", _replay_pending, " replay moves. Waiting for completion…")
	await replay_finished
	await get_tree().process_frame
	if token != _replay_token:
		print("[PLAY_REPLAY] Ignoring replay_finished (stale token).")
		return
	replay.clear()
	await get_tree().create_timer(1.0).timeout
	
	print("[PLAY_REPLAY] All replay animations finished. Transitioning into my active turn.")
	print("========== PLAY_REPLAY END ==========\n")
	my_battleground_ready()

func _start_replay_move_async(local_pos: Vector2, delay: float, token: int) -> void:
	await _run_replay_move(local_pos, delay)

	if token != _replay_token:
		return

	_replay_pending -= 1
	print("[PLAY_REPLAY] Move finished. Remaining: ", _replay_pending)

	if _replay_pending <= 0:
		_replay_pending = 0
		emit_signal("replay_finished")

func _on_shuffle_button_pressed() -> void:
	if not is_instance_valid(myBattleground):
		return
	if not myBattleground.placing_items:
		return
	
	_randomize_my_ships(myBattleground.columns)

func _get_template_for_size(bsize: int) -> String:
	return SHIP_TEMPLATES.get(bsize, "")

func _randomize_my_ships(board_size: int) -> void:
	if not is_instance_valid(myBattleground):
		print("Missing BattleGround")
		return

	var template := _get_template_for_size(board_size)
	if template.is_empty():
		print("[RANDOMIZE] No template for board_size=", board_size, " – keeping existing layout")
		return

	var encoded := template

	# Minimal stability fix:
	# size 9 currently crashes in the backtracking randomizer, so use the known-good layout.
	if board_size != 9:
		var previous_layout: String = _last_random_layout_by_size.get(board_size, "")
		var max_distinct_attempts := 6

		for i in range(max_distinct_attempts):
			encoded = _build_randomized_encoded(template, board_size)
			if encoded != previous_layout:
				break

		if encoded == "":
			print("[RANDOMIZE] Empty encoded result; falling back to template.")
			encoded = template

		if encoded == previous_layout:
			print("[RANDOMIZE] Could not find a different layout after ", max_distinct_attempts,
				" attempts; reusing previous layout.")
		else:
			print("[RANDOMIZE] FINAL encoded layout for my board_size=", board_size, " => ", encoded)
	else:
		print("[RANDOMIZE] board_size=9 -> using known-good template layout for stability")

	_last_random_layout_by_size[board_size] = encoded

	myBattleground.from_encoded(encoded)
	myBattleground.placing_items = true

	for ship in myBattleground.ships:
		if ship == null or not is_instance_valid(ship):
			push_error("[RANDOMIZE] Invalid ship after from_encoded. encoded=" + encoded)
			return
		ship.canBeMoved = true
		
func _build_randomized_encoded(template: String, bsize: int) -> String:
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
		return template

	var cmp := func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["length"]) > int(b["length"])
	ship_defs.sort_custom(cmp)

	var blocked: Array = []
	for x in range(bsize):
		var col: Array[bool] = []
		col.resize(bsize)
		col.fill(false)
		blocked.append(col)

	var placed: Array[String] = []
	if _try_place_ships(ship_defs, 0, blocked, bsize, placed):
		var final_encoded := "|".join(placed)
		print("[RANDOMIZE] Backtracking success encoded=", final_encoded)
		return final_encoded

	push_warning("Backtracking randomization failed; using template.")
	print("[RANDOMIZE] Backtracking FAILED, returning ORIGINAL TEMPLATE: ", template)
	return template
	
func _try_place_ships(ship_defs: Array[Dictionary], ship_idx: int, blocked: Array, bsize: int, placed: Array[String]) -> bool:
	if ship_idx >= ship_defs.size():
		return true

	var def: Dictionary = ship_defs[ship_idx]
	var length: int = int(def["length"])
	var num_text: String = String(def["num_text"])

	var candidates: Array[Dictionary] = []

	for rot in [0, 1]:
		var is_horizontal: bool = (rot == 1)
		var max_x := bsize - (length if is_horizontal else 1)
		var max_y := bsize - (1 if is_horizontal else length)

		if max_x < 0 or max_y < 0:
			continue

		for x in range(max_x + 1):
			for y in range(max_y + 1):
				if _can_place_ship_at(blocked, bsize, x, y, length, rot):
					candidates.append({
						"x": x,
						"y": y,
						"rot": rot,
					})

	_shuffle_in_place(candidates)

	for choice in candidates:
		var px: int = int(choice["x"])
		var py: int = int(choice["y"])
		var prot: int = int(choice["rot"])

		var next_blocked := _clone_blocked(blocked)
		_place_ship_on_blocked(next_blocked, bsize, px, py, length, prot)

		placed.append("pos:%d,%d&num:%s&rot:%d" % [px, py, num_text, prot])

		if _try_place_ships(ship_defs, ship_idx + 1, next_blocked, bsize, placed):
			return true

		placed.pop_back()

	return false
	
func _shuffle_in_place(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
		
func _clone_blocked(blocked: Array) -> Array:
	var out: Array = []
	for col in blocked:
		out.append((col as Array).duplicate())
	return out
	
func _can_place_ship_at(blocked: Array, bsize: int, x: int, y: int, length: int, rot: int) -> bool:
	var is_horizontal: bool = (rot == 1)

	for i in range(length):
		var cx: int = x + i if is_horizontal else x
		var cy: int = y if is_horizontal else y + i

		if cx < 0 or cy < 0 or cx >= bsize or cy >= bsize:
			return false

		for off: Vector2i in BUFFER_OFFSETS_ORTHO:
			var nx: int = cx + off.x
			var ny: int = cy + off.y

			if nx < 0 or ny < 0 or nx >= bsize or ny >= bsize:
				continue
			if blocked[nx][ny]:
				return false

		if USE_DIAGONAL_BUFFER:
			for off: Vector2i in BUFFER_OFFSETS_DIAG:
				var dx: int = cx + off.x
				var dy: int = cy + off.y

				if dx < 0 or dy < 0 or dx >= bsize or dy >= bsize:
					continue
				if blocked[dx][dy]:
					return false

	return true


func _place_ship_on_blocked(blocked: Array, bsize: int, x: int, y: int, length: int, rot: int) -> void:
	var is_horizontal: bool = (rot == 1)

	for i in range(length):
		var cx: int = x + i if is_horizontal else x
		var cy: int = y if is_horizontal else y + i

		for off: Vector2i in BUFFER_OFFSETS_ORTHO:
			var nx: int = cx + off.x
			var ny: int = cy + off.y

			if nx < 0 or ny < 0 or nx >= bsize or ny >= bsize:
				continue
			blocked[nx][ny] = true

		if USE_DIAGONAL_BUFFER:
			for off: Vector2i in BUFFER_OFFSETS_DIAG:
				var dx: int = cx + off.x
				var dy: int = cy + off.y

				if dx < 0 or dy < 0 or dx >= bsize or dy >= bsize:
					continue
				blocked[dx][dy] = true

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
	
func _set_setup_mode(enabled: bool) -> void:
	if is_instance_valid(state):
		state.visible = enabled

	var my_avatar := _get_my_avatar_display()
	if is_instance_valid(my_avatar):
		var m: Color = my_avatar.modulate
		m.a = 0.0 if enabled else 1.0
		my_avatar.modulate = m

	_update_you_labels(not enabled)

func show_battleground(mine: bool):
	if not is_instance_valid(myBoardContainer) or not is_instance_valid(theirBoardContainer):
		return

	_set_board_active(myBoardContainer, myBattleground, mine)
	_set_board_active(theirBoardContainer, theirBattleground, not mine)
	
func _set_board_active(container: Control, board: BattleGround, active: bool) -> void:
	if not is_instance_valid(container) or not is_instance_valid(board):
		return

	container.visible = true
	container.modulate.a = 1.0 if active else 0.0

	if spectator_mode:
		board.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		board.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

func send_update():
	print("\n========== SEND_UPDATE ==========")
	print("[SEND] Preparing outbound update…")

	if not is_instance_valid(myBattleground):
		push_error("[SEND] myBattleground invalid")
		return

	if myBattleground.rows <= 0 or myBattleground.columns <= 0:
		push_error("[SEND] Invalid battleground dimensions rows=%s cols=%s" % [myBattleground.rows, myBattleground.columns])
		return

	for ship in myBattleground.ships:
		if ship == null or not is_instance_valid(ship):
			push_error("[SEND] Invalid ship found before encode_ships")
			return

	var myEncoded := myBattleground.encode_ships()
	if myEncoded == null:
		push_error("[SEND] encode_ships returned null")
		return

	var bullets := myBattleground.encode_bullets()
	if bullets == null:
		push_error("[SEND] encode_bullets returned null")
		return

	var flipped_ships := _flip_ships_encoded_vertical(myEncoded, myBattleground.rows)
	var flipped_bullets := _flip_bullets_vertical(bullets, myBattleground.rows, myBattleground.columns)

	print("[SEND] Ships encoded (Original): ", myEncoded)
	print("[SEND] Ships encoded (Flipped):  ", flipped_ships)
	print("[SEND] Bullets encoded (Original): ", bullets)
	
	var msg := {
		"bullets" + str(player): flipped_bullets,
	}

	if not myEncoded.is_empty():
		msg["ships" + str(player)] = flipped_ships
		print("[SEND] Including ships for player ", player, " (first-time send).")
	else:
		print("[SEND] Skipping ships: ")

	var my_avatar := _get_my_avatar_display()
	if is_instance_valid(my_avatar) and my_avatar.has_method("get_avatar_data_string"):
		var avatar_key := "avatar%d" % player
		msg[avatar_key] = my_avatar.call("get_avatar_data_string")
		print("[SEND] Avatar data included under key: ", avatar_key)

	if not replay.is_empty():
		msg["replay"] = "|".join(replay)
		print("[SEND] Replay string included: ", msg["replay"])

		msg["skip_ships"] = theirBattleground.encode_ships()
		msg["skip_bullets"] = theirBattleground.encode_bullets()
		print("[SEND] skip_ships: ", msg["skip_ships"])
		print("[SEND] skip_bullets: ", msg["skip_bullets"])

	if is_end:
		msg["winner"] = my_player + "|" + ("1" if winner else "-1")
		print("[SEND] Winner flag included: ", msg["winner"])

	var encoded = JSON.stringify(msg)
	if appPlugin:
		appPlugin.updateGameData(encoded)
	else:
		print("No app plugin! ")

	print("[SEND] FINAL JSON SENT TO APP PLUGIN:")
	print(encoded)
	print("===================================\n")

	replay.clear()

	if not is_end:
		play_sent_animation()
		
func my_battleground_ready():
	print("[MY_BATTLEGROUND_READY] Entered")
	if spectator_mode:
		print("[MY_BATTLEGROUND_READY] Spectator — skipping turn flow.")
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

	var travel_distance_local: float = screen_width * 3.0
	var offset := Vector2(travel_distance_local, 0.0)

	print("[SWAP] my_home=", my_home, " their_home=", their_home, " travel_distance_local=", travel_distance_local)

	myBoardContainer.set_as_top_level(true)
	theirBoardContainer.set_as_top_level(true)

	var base_z : int = max(myBoardContainer.z_index, theirBoardContainer.z_index)
	print("[SWAP] base_z=", base_z, " (pre-adjust z_index: my=", myBoardContainer.z_index, " their=", theirBoardContainer.z_index, ")")
	if reverse:
		myBoardContainer.z_index = base_z + 1
		theirBoardContainer.z_index = base_z
	else:
		theirBoardContainer.z_index = base_z + 1
		myBoardContainer.z_index = base_z
	print("[SWAP] post-adjust z_index: my=", myBoardContainer.z_index, " their=", theirBoardContainer.z_index)

	var my_start_pos: Vector2
	var my_target_pos: Vector2
	var their_start_pos: Vector2
	var their_target_pos: Vector2

	if reverse:
		my_start_pos = my_home - offset
		my_target_pos = my_home
		their_start_pos = their_home
		their_target_pos = their_home + offset
	else:
		my_start_pos = my_home
		my_target_pos = my_home - offset
		their_start_pos = their_home + offset
		their_target_pos = their_home

	print("[SWAP] my_start_pos=", my_start_pos, " my_target_pos=", my_target_pos)
	print("[SWAP] their_start_pos=", their_start_pos, " their_target_pos=", their_target_pos)

	myBoardContainer.visible = true
	myBoardContainer.modulate.a = 1.0
	
	theirBoardContainer.visible = true
	theirBoardContainer.modulate.a = 1.0

	myBoardContainer.global_position = my_start_pos
	theirBoardContainer.global_position = their_start_pos

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

		print("[SWAP] Clouds swipe_offset from ", sw_start, " to ", sw_end)
		clouds_tween.tween_method(func(v): cmat.set_shader_parameter("swipe_offset", v), sw_start, sw_end, travel_anim_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var main_tween := create_tween().set_parallel(true)
	print("[SWAP] Starting main_tween for board slide.")

	main_tween.parallel().tween_property(
		myBoardContainer, "global_position",
		my_target_pos, travel_anim_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	main_tween.parallel().tween_property(
		theirBoardContainer, "global_position",
		their_target_pos, travel_anim_duration
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

	if reverse:
		incoming_container = myBoardContainer
		incoming_battleground = myBattleground
		leaving_container = theirBoardContainer
		leaving_battleground = theirBattleground
	else:
		incoming_container = theirBoardContainer
		incoming_battleground = theirBattleground
		leaving_container = myBoardContainer
		leaving_battleground = myBattleground

	print("[SWAP] incoming_battleground=", incoming_battleground.name, " leaving_battleground=", leaving_battleground.name)

	myBoardContainer.set_as_top_level(false)
	theirBoardContainer.set_as_top_level(false)

	_set_board_active(leaving_container, leaving_battleground, false)
	_set_board_active(incoming_container, incoming_battleground, true)

	print("[SWAP] After _set_board_active calls.")

	if is_instance_valid(choose_target_label) and not reverse and not spectator_mode:
		choose_target_label.visible = true
		choose_target_label.modulate.a = 0.0
		choose_target_label.z_index = clouds_rect.z_index + 1
		var label_tween := create_tween()
		label_tween.tween_property(choose_target_label, "modulate:a", 1.0, 1.0)
		print("[SWAP] choose_target_label fade-in tween started.")


	print("[SWAP] === _swap_to_opponent_board END ===\n")

func _update_you_labels(show_you: bool = true) -> void:
	if is_instance_valid(p1_you_label):
		p1_you_label.visible = false
	if is_instance_valid(p2_you_label):
		p2_you_label.visible = false

	if not show_you or spectator_mode:
		return

	if player == 1 and is_instance_valid(p1_you_label):
		p1_you_label.text = "You"
		p1_you_label.visible = true
	elif player == 2 and is_instance_valid(p2_you_label):
		p2_you_label.text = "You"
		p2_you_label.visible = true

func _process(_delta: float) -> void:
	if spectator_mode or not fireMode or not is_instance_valid(theirBattleground):
		return
	
	var tg := theirBattleground.targeting_grid
	var has_target := tg.x >= 0 and tg.y >= 0 and theirBattleground.can_attack
	
	if has_target:
		if is_instance_valid(choose_target_label):
			choose_target_label.visible = false
		
		if is_instance_valid(fire_button):
			fire_button.visible = true
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

func _flip_coord_vertical(pos: Vector2, rows: int) -> Vector2:
	return Vector2(pos.x, _flip_y_index(int(pos.y), rows))

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
	print("Fire pressed")

	if not fireMode or not is_instance_valid(theirBattleground):
		print("[FIRE_BUTTON] Ignored — fireMode:", fireMode, " theirBattleground valid:", is_instance_valid(theirBattleground))
		return

	var grid := theirBattleground.targeting_grid
	if grid.x < 0 or grid.y < 0:
		print("[FIRE_BUTTON] No valid target selected. targeting_grid:", grid)
		return

	print("[FIRE_BUTTON] Firing at grid: ", grid)
	
	if is_instance_valid(fire_button):
		fire_button.disabled = true
		fire_button.visible = false 

	theirBattleground.targeting_grid = Vector2(-1, -1)
	theirBattleground.can_attack = false
	fireMode = false

	if is_instance_valid(choose_target_label):
		choose_target_label.visible = false

	print("[FIRE_BUTTON] Started Bomb Fall animation")
	await _play_bomb_fall_animation_for_board(theirBattleground, grid, false, 2.0)
	print("[FIRE_BUTTON] Finished Bomb Fall animation")

	var top_x := int(grid.x)
	var rows := theirBattleground.rows
	var top_y := _flip_y_index(int(grid.y), rows)

	var move_str := "%d,%d" % [top_x, top_y]
	replay.append(move_str)

	print("[FIRE_BUTTON] Replay now (wire coords with vertical flip for opponent): ", replay)


	var hit: bool = theirBattleground.fire(grid)
	print("[FIRE_BUTTON] Hit result: ", hit)

	if not hit:
		await get_tree().create_timer(1.0).timeout
		print("[FIRE_BUTTON] Miss → sending update and waiting for opponent.")
		send_update()
	else:
		_do_hit_camera_shake()
		
		if theirBattleground.is_over():
			print("[FIRE_BUTTON] Opponent board is over — we win. Sending final update.")
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
				
				var button_tween := create_tween()
				button_tween.tween_property(fire_button, "modulate:a", 1.0, 0.5)
			
			if is_instance_valid(choose_target_label):
				choose_target_label.modulate.a = 0.0
				choose_target_label.visible = true 
				
				choose_target_label.z_index = clouds_rect.z_index + 1
				var label_tween := create_tween()
				label_tween.tween_property(choose_target_label, "modulate:a", 1.0, 1.0)
				
			print("[FIRE_BUTTON] Hit → player gets another turn. Ready for next shot.")
			
func _play_bomb_fall_animation_for_board(board: BattleGround, grid_pos: Vector2, from_right: bool, plane_duration: float = 2.0) -> void:
	if not is_instance_valid(board):
		print("SOMETHING FAILED IN BOMB FALL (missing board)")
		return
	
	var bomb_tex: Texture2D = BOMB_TEXTURE_PATH
	var plane_tex: Texture2D = PLANE_TEXTURE_PATH
	
	if bomb_tex == null:
		print("Bomb texture not found")
		return
	if plane_tex == null:
		print("Plane texture not found")
		return
	
	var cell_center_local: Vector2 = board.grid_to_coord(
		grid_pos + Vector2(0.5, 0.5)
	)
	var board_size: Vector2 = board.rect_size
	
	var plane_width: float = plane_tex.get_size().x * PLANE_SCALE
	var plane_height: float = plane_tex.get_size().y * PLANE_SCALE
	
	var plane_y := cell_center_local.y - board_size.y * 0.45
	
	var plane_start: Vector2
	var plane_end: Vector2
	
	if from_right:
		plane_start = Vector2(board_size.x + plane_width, plane_y)
		plane_end = Vector2(-plane_width, plane_y)
	else:
		plane_start = Vector2(-plane_width, plane_y)
		plane_end = Vector2(board_size.x + plane_width, plane_y)
	
	var plane := Sprite2D.new()
	plane.texture = plane_tex
	plane.centered = true
	plane.position = plane_start
	plane.scale = Vector2(PLANE_SCALE, PLANE_SCALE)
	plane.z_index = 1000
	
	if from_right:
		plane.rotation = PI 
	
	board.add_child(plane)
	
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
	
	if is_instance_valid(bomb):
		bomb.queue_free()
	if is_instance_valid(plane):
		plane.queue_free()
		
func _run_replay_move(local_pos: Vector2, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await _play_bomb_fall_animation_for_board(myBattleground, local_pos, true, 2.0)

	if is_instance_valid(myBattleground):
		var hit : bool = myBattleground.replay_fire(local_pos)
		if hit:
			_haptic_explosion(1.0, 45)
		print("[PLAY_REPLAY] Applied replay fire at ", local_pos, " hit=", hit)
		await get_tree().process_frame
	else:
		print("[PLAY_REPLAY] WARNING – myBattleground invalid when applying replay fire")

	print("[PLAY_REPLAY] Replayed visual move at ", local_pos)

func mark_end(win: bool):
	state.text = ""
	var my_avatar := _get_my_avatar_display()
	var opp_avatar := _get_opp_avatar_display()
	print("setting their process mode to " + str(false))
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
			_show_win_burst(my_avatar)
		print("check_winner: YOU WIN (final)")
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
			_show_win_burst(opp_avatar)
		print("check_winner: YOU LOSE (final)")
		return true
	
func _on_start_button_pressed() -> void:
	print("Start pressed")
	
	if not fireMode:
		if is_instance_valid(myBattleground):
			myBattleground.placing_items = false
			for ship in myBattleground.ships:
				ship.canBeMoved = false

		_set_setup_mode(false)
		start_button.disabled = true
		shuffle_button.modulate.a = 0
		shuffle_button.disabled = true

		my_battleground_ready()
		return

func _on_battle_ground_is_valid(valid: bool) -> void:
	start_button.disabled = not valid
	
func _do_hit_camera_shake(intensity: float = 6.0, duration: float = 0.25) -> void:
	var vp := get_viewport()
	if vp == null:
		return

	if _shake_tween and _shake_tween.is_running():
		_shake_tween.kill()
		vp.canvas_transform = Transform2D.IDENTITY

	_shake_tween = create_tween()

	_shake_tween.tween_method(
		func(alpha: float) -> void:
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
	
func _haptic_explosion(strength: float = 1.0, duration_ms: int = 45) -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return

	strength = clampf(strength, 0.0, 1.0)
	Input.vibrate_handheld(duration_ms, strength)
	
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

	popup.open("How to Play Sea Battle", _get_rules_text())
	
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
		var my_avatar := _get_my_avatar_display()
		if is_instance_valid(my_avatar):
			my_avatar.update_display_from_settings()
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

@warning_ignore("unused_parameter")
func _on_theme_changed(new_theme_name: String) -> void:
	pass

func _load_game_specific_settings() -> void:
	var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	print("Loaded game-specific settings for ", game_settings_category, ": volume=", saved_volume, " debug=", show_debug_info)
