extends BaseGame3D
class_name PaintballGame

@export var buttons_root: NodePath
@export var splat_tex: Texture2D

@onready var player: Node3D = %Player
@onready var fire_button: Control = %FireButton
@onready var player_avatar_display: Control = %PlayerAvatarDisplay
@onready var opp_avatar_display: Control = %OppAvatarDisplay
@onready var sent_label: Label = %SentLabel
@onready var win_loss_label: Label = %WinLossLabel
@onready var spec_label: Label = %SpecLabel
@onready var you_label: Label = %YouLabel
@onready var cam: Camera3D = get_viewport().get_camera_3d()
@onready var fade_white: ColorRect = %FadeWhite
@onready var top_info: Control = %TopInfoContainer
@onready var fp_aim_sprite: Sprite2D = %FirstPersonAimSprite
@onready var opponent_sprite: Sprite3D = %Opponent
@onready var pheart1: TextureRect = %pheart1
@onready var pheart2: TextureRect = %pheart2
@onready var pheart3: TextureRect = %pheart3
@onready var oheart1: TextureRect = %oheart1
@onready var oheart2: TextureRect = %oheart2
@onready var oheart3: TextureRect = %oheart3

const HEART_FULL_TEX := preload("res://paintball/heart.png")
const HEART_VOID_TEX := preload("res://paintball/heart_void.png")
const PAINTBALL_SCENE := preload("res://paintball/PaintballProjectile.tscn")
const MUSIC_STREAM := preload("res://global/audio/paintball.ogg")
const SPLAT_TEX := preload("res://paintball/splat.png")
const OPPONENT_FACING_TEX := preload("res://paintball/opponent_facing.png")
const OPPONENT_SIDE_TEX := preload("res://paintball/opponent_side.png")

# -------------------------------------------------------------------
# Modules
# -------------------------------------------------------------------
const PBButtons := preload("res://paintball/paintball_buttons.gd")
const PBReplay := preload("res://paintball/paintball_replay.gd")
const PBRound := preload("res://paintball/paintball_round.gd")
const PBShots := preload("res://paintball/paintball_shots.gd")
const PBState := preload("res://paintball/paintball_state.gd")
const PBUI := preload("res://paintball/paintball_ui.gd")

var buttons
var replay
var round_mgr
var shots
var states
var ui

# -------------------------------------------------------------------
# Connection / plugin
# -------------------------------------------------------------------
var has_connected: bool = false

# -------------------------------------------------------------------
# Identity and turn state (PB_State expects these)
# -------------------------------------------------------------------
var my_id: String = ""
var p1_id: String = ""
var p2_id: String = ""
var winner: String = ""

var playernum: int = 0
var turn_owner: int = 1
var is_your_turn: bool = false
var is_my_turn: bool = false

# -------------------------------------------------------------------
# Win state (PB_UI + PB_State expect these)
# -------------------------------------------------------------------
var game_ended: bool = false
var game_over: bool = false
var win_loss_state: String = "0"

# -------------------------------------------------------------------
# HP (PB_UI, PB_State, PB_Round)
# -------------------------------------------------------------------
var _hp_me: int = 3
var _hp_opp: int = 3

# -------------------------------------------------------------------
# Buttons / lanes (PB_Buttons, PB_Shots, PB_Round)
# -------------------------------------------------------------------
var _buttons: Array[ActionButton3D] = []
var _shoot_btn_by_lane: Dictionary = {}
var _lane_x: Dictionary = {
	ActionButton3D.Lane.LEFT: -1.0,
	ActionButton3D.Lane.CENTER: 0.0,
	ActionButton3D.Lane.RIGHT: 1.0
}

var _player_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
var _selected_shoot: ActionButton3D = null

# -------------------------------------------------------------------
# Round / sequence flags (cross-module)
# -------------------------------------------------------------------
var _is_shot_sequence_running: bool = false
var _round_sequence_running: bool = false
var _require_new_shoot_selection: bool = true
var _opp_sprite_base_scale: Vector3 = Vector3.ONE

# -------------------------------------------------------------------
# Opponent pending shot + reveal (PB_State, PB_Round, PB_Shots)
# -------------------------------------------------------------------
var _pending_enemy_shot: bool = false
var _opp_pos_enc: int = -1
var _opp_target_enc: int = -1
var _opp_sprite_start_pos: Vector3 = Vector3.ZERO

# -------------------------------------------------------------------
# Replay fields (PB_State expects these on g)
# -------------------------------------------------------------------
var _replay_segments: PackedStringArray = PackedStringArray()
var _last_replay_str: String = ""

var _is_replay_playback: bool = false
var _replay_auto_pending: bool = false
var _replay_send_segments: PackedStringArray = PackedStringArray()
var _replay_is_autoplay_round: bool = false
var _replay_send_armed: bool = false

# -------------------------------------------------------------------
# Camera / aim / recoil (PB_Round + PB_Shots)
# -------------------------------------------------------------------
var _aim_target_world: Vector3 = Vector3.ZERO

var ball_speed: float = 36.0

# -------------------------------------------------------------------
# Fire button placement + splats (PB_UI expects these on g)
# -------------------------------------------------------------------
var sent_tween: Tween = null
var _opp_avatar_texture_normal: Texture2D = null
var _opp_avatar_texture_pressed: Texture2D = null
var _opp_avatar_texture_hover: Texture2D = null

# -------------------------------------------------------------------
# Ready / process
# -------------------------------------------------------------------
func _ready() -> void:
	_build_modules()

	# Owner refs first
	buttons.setup(self)
	shots.setup(self)
	ui.setup(self)
	states.setup(self)
	replay.setup(self)
	round_mgr.setup(self)

	# Buttons boot
	buttons.setup_buttons_root(buttons_root)
	buttons.collect_and_index_buttons()
	buttons.cache_lane_x_from_move_buttons()
	
	print("[GAME] buttons collected:", _buttons.size())
	for b in _buttons:
		if is_instance_valid(b):
			print("[GAME]  -", b.name, " kind=", int(b.kind), " lane=", int(b.lane))

	buttons.connect_button_signals()
	buttons.update_move_buttons()

	_selected_shoot = null
	_require_new_shoot_selection = true
	ui.show_fire_button(false)

	# UI signals
	if is_instance_valid(dot_timer):
		dot_timer.timeout.connect(ui.on_dot_timer_timeout)

	if is_instance_valid(rules_button):
		rules_button.pressed.connect(_on_rules_button_pressed)

	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
		
	if is_instance_valid(opponent_sprite):
		_opp_sprite_base_scale = opponent_sprite.scale
		_opp_sprite_start_pos = opponent_sprite.global_position
		print("[DBG][READY] cached _opp_sprite_start_pos=", _opp_sprite_start_pos)

	if is_instance_valid(opp_avatar_display):
		_opp_avatar_texture_normal = opp_avatar_display.get("texture_normal") as Texture2D
		_opp_avatar_texture_pressed = opp_avatar_display.get("texture_pressed") as Texture2D
		_opp_avatar_texture_hover = opp_avatar_display.get("texture_hover") as Texture2D

	# Fire button
	if fire_button is Button:
		(fire_button as Button).pressed.connect(_on_fire_pressed)
	elif fire_button is BaseButton:
		(fire_button as BaseButton).pressed.connect(_on_fire_pressed)
		
	if Engine.has_singleton("OpenPigeonMedia"):
		mediaPlugin = Engine.get_singleton("OpenPigeonMedia")
		print("OpenPigeonMedia plugin is available")
	else:
		print("OpenPigeonMedia plugin is not available")

	_start_music()
		
	# Important: load/parse game data before any await that allows the screen to draw.
	_connect_app_plugin_or_dev()

	# UI boot after data request/parse.
	await ui.init_fire_button()
	ui.init_player_splat_overlay()
	ui.init_opponent_splat()
	ui.apply_hearts_from_hp()
	
func _process(delta: float) -> void:		
	if shots != null:
		shots.tick(delta)
		
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		var appPlugin := Engine.get_singleton("AppPlugin")
		if appPlugin:
			print("[APP] Resumed; refreshing paintball data")
			appPlugin.onReady()

# -------------------------------------------------------------------
# Modules bootstrapping
# -------------------------------------------------------------------
func _build_modules() -> void:
	buttons = PBButtons.new()
	replay = PBReplay.new()
	round_mgr = PBRound.new()
	shots = PBShots.new()
	states = PBState.new()
	ui = PBUI.new()

# -------------------------------------------------------------------
# ActionButton3D signal hookup (robust: clicked OR pressed)
# -------------------------------------------------------------------
func _on_button_pressed(b: ActionButton3D) -> void:
	_on_button_clicked(b)

# -------------------------------------------------------------------
# AppPlugin hookup
# -------------------------------------------------------------------
func _connect_app_plugin_or_dev() -> void:
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("AppPlugin Available")
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
		return

	# Editor dev payload
	print("[DEV] Editor hint active, loading sample game data")
	var DEV_SCENARIO: int = 3
	var dev_data_1 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV1"}'
	var dev_data_2 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV1","replay":"hp1:3,hp2:3,pos1:0,pos2:0,target1:2,target2:2"}'
	var dev_data_3 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV3","replay":"hp1:3,hp2:3,pos1:0,pos2:0,target1:0,target2:0|hp1:2,hp2:3,pos1:0,pos2:0,target1:-1,target2:0"}'
	var dev_data := dev_data_1
	if DEV_SCENARIO == 3:
		dev_data = dev_data_3
	_set_game_data(dev_data)

func _set_game_data(raw_text: String) -> void:
	# PB_State is the parser/turn gatekeeper right now
	states.set_game_data(raw_text)

	# If PB_Replay wants a hook when payload arrives
	if replay != null and replay.has_method("on_payload_loaded"):
		replay.call("on_payload_loaded")

	# UI reflect
	ui.apply_hearts_from_hp()
	
# -------------------------------------------------------------------
# Music hookup
# -------------------------------------------------------------------
	
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
		
# -------------------------------------------------------------------
# Button clicked entry point
# -------------------------------------------------------------------
func _on_button_clicked(b: ActionButton3D) -> void:
	if not is_my_turn or _is_shot_sequence_running or _round_sequence_running:
		return

	if b.kind == ActionButton3D.ButtonKind.MOVE:
		buttons.move_player_to_button(b)
		return

	if b.kind == ActionButton3D.ButtonKind.SHOOT:
		_selected_shoot = b
		_require_new_shoot_selection = false
		_aim_target_world = _selected_shoot.global_position + Vector3(0.0, 0.7, 0.0)

		buttons.update_shoot_selection_visuals(_selected_shoot)

		ui.show_fire_button(true)
		return

# -------------------------------------------------------------------
# Fire pressed gatekeeper
# -------------------------------------------------------------------
func _on_fire_pressed() -> void:
	if not is_my_turn:
		return
	if _is_shot_sequence_running or _round_sequence_running:
		return
	if _require_new_shoot_selection or _selected_shoot == null or not is_instance_valid(_selected_shoot):
		return

	print("[DBG][FIRE_PRESSED] is_my_turn=", is_my_turn,
		" shot_seq=", _is_shot_sequence_running,
		" round_seq=", _round_sequence_running,
		" require_select=", _require_new_shoot_selection,
		" selected=", (-1 if _selected_shoot == null else int(_selected_shoot.lane)),
		" pending_enemy=", _pending_enemy_shot,
		" replay_playback=", _is_replay_playback,
		" replay_auto_pending=", _replay_auto_pending,
		" segs=", _replay_segments.size(),
		" last_replay_len=", _last_replay_str.length()
	)
	
	_replay_send_armed = true
	_replay_is_autoplay_round = false

	if _pending_enemy_shot:
		var my_pos_int: int = states.lane_to_pos_enc(_player_lane)
		var my_target_int: int = states.lane_to_target_enc(_selected_shoot.lane)

		if _replay_send_segments.size() > 0:
			var head_state: Dictionary = _parse_replay_state(String(_replay_send_segments[0]))

			# Only if opponent is ready and my fields are missing (the "2nd replay" case)
			var opp_ready: bool = false
			if playernum == 1:
				opp_ready = int(head_state.get("pos2", -1)) != -1 and int(head_state.get("target2", -1)) != -1
			else:
				opp_ready = int(head_state.get("pos1", -1)) != -1 and int(head_state.get("target1", -1)) != -1

			var my_pos_key: String = ("pos1" if playernum == 1 else "pos2")
			var my_tgt_key: String = ("target1" if playernum == 1 else "target2")
			var my_missing: bool = int(head_state.get(my_pos_key, -1)) == -1 or int(head_state.get(my_tgt_key, -1)) == -1

			if opp_ready and my_missing:
				# Keep hp aligned with current game state in p1 order
				if playernum == 1:
					head_state["hp1"] = _hp_me
					head_state["hp2"] = _hp_opp
				else:
					head_state["hp1"] = _hp_opp
					head_state["hp2"] = _hp_me

				head_state[my_pos_key] = my_pos_int
				head_state[my_tgt_key] = my_target_int

				_replay_send_segments[0] = _replay_state_to_string(head_state)

				if _replay_segments.size() > 0:
					_replay_segments[0] = _replay_send_segments[0]

				print("[DBG][SENDQ] committed my selection into head=", String(_replay_send_segments[0]))

		_replay_auto_pending = false
		_is_replay_playback = true
		round_mgr.play_round()
		return

	print("[DBG][FIRE_PRESSED] BRANCH: send_game (pending_enemy_shot=false)")

	var my_pos_int: int = states.lane_to_pos_enc(_player_lane)
	var my_target_int: int = states.lane_to_target_enc(_selected_shoot.lane)
	var st: Dictionary = {
		"hp1": 3, "hp2": 3,
		"pos1": -1, "pos2": -1,
		"target1": -1, "target2": -1
	}

	if playernum == 1:
		st["hp1"] = _hp_me
		st["hp2"] = _hp_opp
		st["pos1"] = my_pos_int
		st["target1"] = my_target_int
	else:
		st["hp1"] = _hp_opp
		st["hp2"] = _hp_me
		st["pos2"] = my_pos_int
		st["target2"] = my_target_int

	_replay_send_segments.append(_replay_state_to_string(st))

	print("[DBG][SENDQ] appended my-only seg=", _replay_state_to_string(st),
		" sendq_size=", _replay_send_segments.size()
	)

	send_game()
	
func get_world_for_player_lane(lane: ActionButton3D.Lane) -> Vector3:
	var tx: float = float(_lane_x.get(lane, 0.0))
	
	var shoot_btn = _shoot_btn_by_lane.get(lane, null)
	if is_instance_valid(shoot_btn):
		tx = shoot_btn.global_position.x
		
	var py: float = 0.0
	var pz: float = 0.0
	if is_instance_valid(player):
		py = player.global_position.y
		pz = player.global_position.z
		
	return Vector3(tx, py + 0.7, pz)
	
func _replay_state_to_string(st: Dictionary) -> String:
	return "hp1:%d,hp2:%d,pos1:%d,pos2:%d,target1:%d,target2:%d" % [
		int(st.get("hp1", 3)),
		int(st.get("hp2", 3)),
		int(st.get("pos1", -1)),
		int(st.get("pos2", -1)),
		int(st.get("target1", -1)),
		int(st.get("target2", -1))
	]

func play_round() -> void:
	if round_mgr != null:
		round_mgr.play_round()

func _replay_autoplay_round() -> void:
	if replay != null and replay.has_method("autoplay_replay_round"):
		replay.autoplay_replay_round()

# -------------------------------------------------------------------
# Compatibility wrappers PB_State / PB_Round expect on PaintballGame
# -------------------------------------------------------------------
func send_game(clear_targets_for_next_turn: bool = false) -> void:
	if states != null:
		states.send_game(clear_targets_for_next_turn)

func _enc_to_lane(enc: int) -> ActionButton3D.Lane:
	if states != null and states.has_method("enc_to_lane"):
		return states.enc_to_lane(enc)

	match enc:
		0:
			return ActionButton3D.Lane.LEFT
		1:
			return ActionButton3D.Lane.CENTER
		2:
			return ActionButton3D.Lane.RIGHT
		_:
			return ActionButton3D.Lane.CENTER

func _lane_to_enc(lane: ActionButton3D.Lane) -> int:
	if states != null and states.has_method("lane_to_enc"):
		return states.lane_to_enc(lane)

	match lane:
		ActionButton3D.Lane.LEFT:
			return 0
		ActionButton3D.Lane.CENTER:
			return 1
		ActionButton3D.Lane.RIGHT:
			return 2
		_:
			return 1
			
func _update_opponent_sprite_pose_for_shot() -> void:
	if round_mgr != null and round_mgr.has_method("update_opponent_sprite_pose_for_shot"):
		round_mgr.update_opponent_sprite_pose_for_shot()

func _on_action_button_pressed(b: ActionButton3D) -> void:
	_on_button_clicked(b)

func _show_fire_button(should_show: bool) -> void:
	if ui != null:
		ui.show_fire_button(should_show)

func _apply_hearts_from_hp() -> void:
	if ui != null:
		ui.apply_hearts_from_hp()

func play_sent_animation() -> void:
	if ui != null:
		ui.play_sent_animation()

func _set_all_buttons_clickable(enabled: bool) -> void:
	if buttons != null:
		buttons.set_all_buttons_clickable(enabled)

func _set_button_enabled(b: ActionButton3D, enabled: bool) -> void:
	if buttons != null:
		buttons.set_button_enabled(b, enabled)

func _update_move_buttons() -> void:
	if buttons != null:
		buttons.update_move_buttons()

func check_win() -> bool:
	if ui != null:
		return ui.check_win()
	return false

# -------------------------------------------------------------------
# Replay compatibility: PB_State calls these on g
# These delegate to PB_Replay if it implements them, otherwise fallbacks compile.
# -------------------------------------------------------------------
func _parse_replay_state(seg: String) -> Dictionary:
	if replay != null and replay.has_method("parse_replay_state"):
		return replay.call("parse_replay_state", seg)

	var out: Dictionary = {}
	for part in seg.split(",", false):
		var kv := part.split(":", false)
		if kv.size() >= 2:
			out[String(kv[0])] = int(kv[1])
	return out

func _apply_loaded_replay_segment(state: Dictionary) -> void:
	if replay != null and replay.has_method("apply_loaded_replay_segment"):
		replay.call("apply_loaded_replay_segment", state)
		return

	# Minimal fallback
	var hp1: int = int(state.get("hp1", 3))
	var hp2: int = int(state.get("hp2", 3))

	_hp_me = clamp((hp1 if playernum == 1 else hp2), 0, 3)
	_hp_opp = clamp((hp2 if playernum == 1 else hp1), 0, 3)

	var pos1: int = int(state.get("pos1", -1))
	var pos2: int = int(state.get("pos2", -1))
	var t1: int = int(state.get("target1", -1))
	var t2: int = int(state.get("target2", -1))

	_opp_pos_enc = (pos2 if playernum == 1 else pos1)
	_opp_target_enc = (t2 if playernum == 1 else t1)
	_pending_enemy_shot = (_opp_pos_enc != -1 and _opp_target_enc != -1)

func _prime_autoplay_if_loaded_segment_ready() -> void:
	if replay != null and replay.has_method("prime_autoplay_if_loaded_segment_ready"):
		replay.call("prime_autoplay_if_loaded_segment_ready")

func _replay_build_after_my_fire(my_pos_enc: int, my_target_enc: int) -> String:
	if replay != null and replay.has_method("replay_build_after_my_fire"):
		return String(replay.call("replay_build_after_my_fire", my_pos_enc, my_target_enc))

	# Fallback builder: append a fresh segment
	var base_state: Dictionary = {}
	if _replay_segments.size() > 0:
		base_state = _parse_replay_state(String(_replay_segments[_replay_segments.size() - 1]))
	elif _last_replay_str != "":
		var parts: PackedStringArray = _last_replay_str.split("|", false)
		if parts.size() > 0:
			base_state = _parse_replay_state(String(parts[parts.size() - 1]))

	if base_state.is_empty():
		base_state = {"hp1": 3, "hp2": 3, "pos1": -1, "pos2": -1, "target1": -1, "target2": -1}

	var hp1: int = (_hp_me if playernum == 1 else _hp_opp)
	var hp2: int = (_hp_opp if playernum == 1 else _hp_me)
	base_state["hp1"] = hp1
	base_state["hp2"] = hp2

	if playernum == 1:
		base_state["pos1"] = my_pos_enc
		base_state["target1"] = my_target_enc
	else:
		base_state["pos2"] = my_pos_enc
		base_state["target2"] = my_target_enc

	var seg := "hp1:%d,hp2:%d,pos1:%d,pos2:%d,target1:%d,target2:%d" % [
		int(base_state.get("hp1", 3)),
		int(base_state.get("hp2", 3)),
		int(base_state.get("pos1", -1)),
		int(base_state.get("pos2", -1)),
		int(base_state.get("target1", -1)),
		int(base_state.get("target2", -1))
	]

	if _last_replay_str == "":
		return seg
	return _last_replay_str + "|" + seg
