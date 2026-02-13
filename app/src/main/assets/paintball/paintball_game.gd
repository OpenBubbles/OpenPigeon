extends Node3D
class_name PaintballGame

@export var buttons_root: NodePath
@export var splat_tex: Texture2D

@onready var player: Node3D = %Player
@onready var fire_button: Control = %FireButton
@onready var player_avatar_display: Control = %PlayerAvatarDisplay
@onready var opp_avatar_display: Control = %OppAvatarDisplay
@onready var rules_button: Button = %RulesButton
@onready var settings_button: Button = %SettingsButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: Control = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
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
const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const RULES_POPUP_SCENE := preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE := preload("res://global/settings_popup.tscn")
const PAINTBALL_SCENE := preload("res://paintball/PaintballProjectile.tscn")
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
const SPLAT_TEX := preload("res://paintball/splat.png")
const OPPONENT_FACING_TEX := preload("res://paintball/opponent_facing.png")
const OPPONENT_SIDE_TEX := preload("res://paintball/opponent_side.png")

# -------------------------------------------------------------------
# Modules (match your class_name declarations)
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
var _opp_id: String = ""

var playernum: int = 0
var turn_owner: int = 1
var is_your_turn: bool = false
var is_my_turn: bool = false
var spectator_mode: bool = false

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
var _move_btn_by_lane: Dictionary = {}
var _shoot_btn_by_lane: Dictionary = {}
var _lane_x: Dictionary = {
	ActionButton3D.Lane.LEFT: -1.0,
	ActionButton3D.Lane.CENTER: 0.0,
	ActionButton3D.Lane.RIGHT: 1.0
}

var _player_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
var _selected_shoot: ActionButton3D = null
var _move_tween: Tween = null

# -------------------------------------------------------------------
# Round / sequence flags (cross-module)
# -------------------------------------------------------------------
var _is_shot_sequence_running: bool = false
var _round_sequence_running: bool = false
var _shot_in_progress: bool = false
var _require_new_shoot_selection: bool = true
var _need_new_selection: bool = true
var _touched_this_turn: bool = false
var _opp_sprite_base_scale: Vector3 = Vector3.ONE
var _fp_aim_base_scale: Vector2 = Vector2.ONE

# -------------------------------------------------------------------
# Opponent pending shot + reveal (PB_State, PB_Round, PB_Shots)
# -------------------------------------------------------------------
var _pending_enemy_shot: bool = false
var _opp_pos_enc: int = -1
var _opp_target_enc: int = -1
var _opp_target_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
var _opp_target_world: Vector3 = Vector3.ZERO
var _opp_reveal_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
var _opp_sprite_reveal_offset_y: float = -1.3
var _opp_sprite_start_pos: Vector3 = Vector3.ZERO

# -------------------------------------------------------------------
# Replay fields (PB_State expects these on g)
# -------------------------------------------------------------------
var _replay_segments: PackedStringArray = PackedStringArray()
var _replay_seg_index: int = 0
var _replay_base_state: Dictionary = {}
var _last_replay_str: String = ""

var _is_replay_playback: bool = false
var _replay_auto_pending: bool = false
var _replay_auto_full_str: String = ""
var _replay_auto_end_state: Dictionary = {}

# -------------------------------------------------------------------
# Camera / aim / recoil (PB_Round + PB_Shots)
# -------------------------------------------------------------------
var _cam_start_fov: float = 70.0
var _cam_start_xform: Transform3D = Transform3D.IDENTITY
var _aim_target_world: Vector3 = Vector3.ZERO

var _round_end_white_in: float = 0.25
var _round_end_white_out: float = 0.25

var _fp_aim_base_pos: Vector2 = Vector2.ZERO
var _muzzle_tex_px: Vector2 = Vector2(340.0, 120.0)

var ball_speed: float = 36.0
var _paintball_scale: float = 0.10

var _opp_recoil_z: float = 0.22
var _opp_recoil_in_time: float = 0.05
var _opp_recoil_out_time: float = 0.12

var _player_hit_last: bool = false
var _enemy_hit_last: bool = false

# -------------------------------------------------------------------
# Fire button placement + splats (PB_UI expects these on g)
# -------------------------------------------------------------------
var _fire_btn_shown_pos: Vector2 = Vector2.ZERO
var _fire_btn_hidden_pos: Vector2 = Vector2.ZERO
var _fire_button_is_shown: bool = false
var _fire_btn_tween: Tween = null

var _player_splat: TextureRect = null
var _player_splat_tween: Tween = null

var _opp_splat: Sprite3D = null
var _opp_splat_tween: Tween = null

var sent_tween: Tween = null
var dot_count: int = 0

# -------------------------------------------------------------------
# Ready / process
# -------------------------------------------------------------------
func _ready() -> void:
	_build_modules()

	# Owner refs first (modules read/write via g)
	buttons.setup(self)
	shots.setup(self)
	ui.setup(self)
	states.setup(self)
	replay.setup(self)
	round_mgr.setup(self)

	# Buttons boot (single path, deterministic)
	buttons.setup_buttons_root(buttons_root)
	buttons.collect_and_index_buttons()
	
	# ADD: lane positions must be cached before we can place player correctly
	buttons.cache_lane_x_from_move_buttons()
	
	print("[GAME] buttons collected:", _buttons.size())
	for b in _buttons:
		if is_instance_valid(b):
			print("[GAME]  -", b.name, " kind=", int(b.kind), " lane=", int(b.lane))

	buttons.connect_button_signals()

	# ADD: start player in a random lane immediately on load
	buttons.spawn_player_random_lane()
	buttons.update_move_buttons()

	# Optional but helpful: clear any shoot selection at boot
	_selected_shoot = null
	_require_new_shoot_selection = true
	ui.show_fire_button(false)

	print("[GAME] buttons collected:", _buttons.size())
	for b in _buttons:
		if is_instance_valid(b):
			print("[GAME]  -", b.name, " kind=", int(b.kind), " lane=", int(b.lane))

	buttons.connect_button_signals()

	# UI boot
	await ui.init_fire_button()
	ui.init_player_splat_overlay()
	ui.init_opponent_splat()
	ui.apply_hearts_from_hp()

	# UI signals
	if is_instance_valid(dot_timer):
		dot_timer.timeout.connect(ui.on_dot_timer_timeout)

	if is_instance_valid(rules_button):
		rules_button.pressed.connect(_on_rules_button_pressed)

	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
		
	if is_instance_valid(opponent_sprite):
		_opp_sprite_base_scale = opponent_sprite.scale

	if is_instance_valid(fp_aim_sprite):
		_fp_aim_base_scale = fp_aim_sprite.scale

	# Fire button
	if fire_button is Button:
		(fire_button as Button).pressed.connect(_on_fire_pressed)
	elif fire_button is BaseButton:
		(fire_button as BaseButton).pressed.connect(_on_fire_pressed)

	_connect_app_plugin_or_dev()

func _process(delta: float) -> void:		
	if shots != null:
		shots.tick(delta)

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
	var dev_data_1 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV1","replay":"hp1:3,hp2:3,pos1:2,pos2:-1,target1:2,target2:-1"}'
	var dev_data_3 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV3","replay":"hp1:2,hp2:3,pos1:2,pos2:1,target1:2,target2:2|hp1:1,hp2:3,pos1:2,pos2:1,target1:-1,target2:1"}'
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

		buttons.update_shoot_selection_visuals(_selected_shoot) # ADD THIS

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

	# If opponent shot is ready, we should play the round (DEV3 case).
	if _pending_enemy_shot:
		# This is user driven, not autoplay
		_is_replay_playback = false
		_replay_auto_pending = false

		round_mgr.play_round()
		return

	print("[FIRE] sending. my_lane=", int(_player_lane),
		" target=", (-1 if _selected_shoot == null else int(_selected_shoot.lane)),
		" last_replay_len=", _last_replay_str.length()
	)

	send_game()

# -------------------------------------------------------------------
# Compatibility wrappers PB_State / PB_Round expect on PaintballGame
# Keep these thin and delegate to modules.
# -------------------------------------------------------------------
func send_game(clear_targets_for_next_turn: bool = false) -> void:
	# PB_State owns send_game() in your current module set
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

func start_waiting_animation() -> void:
	if ui != null:
		ui.start_waiting_animation()

func stop_waiting_animation() -> void:
	if ui != null:
		ui.stop_waiting_animation()

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
	# PB_UI currently owns check_win() in your module set
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

# -------------------------------------------------------------------
# Rules / settings
# -------------------------------------------------------------------
func _on_rules_button_pressed() -> void:
	ui.on_rules_button_pressed()

func _on_settings_button_pressed() -> void:
	ui.on_settings_button_pressed()

func _on_theme_changed(_theme: Variant = null) -> void:
	# Keep it simple: when a theme changes, refresh avatars
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("update_display_from_settings"):
		player_avatar_display.update_display_from_settings()

	if is_instance_valid(opp_avatar_display) and opp_avatar_display.has_method("update_display_from_settings"):
		opp_avatar_display.update_display_from_settings()
