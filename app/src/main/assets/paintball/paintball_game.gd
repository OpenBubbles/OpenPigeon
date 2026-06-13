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

const LOG_TAG := "Paintball"
const DEBUG_PAINTBALL := false

func dbg(parts: Variant) -> void:
	if DEBUG_PAINTBALL:
		OpLog.d(LOG_TAG, parts)

func _replay_segment_is_full(seg: String) -> bool:
	if seg.is_empty():
		return false

	var st: Dictionary = _parse_replay_state(seg)
	return int(st.get("pos1", -1)) != -1 \
		and int(st.get("pos2", -1)) != -1 \
		and int(st.get("target1", -1)) != -1 \
		and int(st.get("target2", -1)) != -1

func _replay_summary(raw: String) -> String:
	if raw.is_empty():
		return "len=0 segs=0 full=0 pending=0"

	var parts := raw.split("|", false)
	var full := 0
	for seg in parts:
		if _replay_segment_is_full(String(seg)):
			full += 1

	return "len=%d segs=%d full=%d pending=%d" % [
		raw.length(),
		parts.size(),
		full,
		parts.size() - full
	]

func _selected_shoot_lane() -> int:
	if _selected_shoot == null or not is_instance_valid(_selected_shoot):
		return -1
	return int(_selected_shoot.lane)

func _state_summary() -> String:
	return "player=%d turn=%s spectator=%s hpMe=%d hpOpp=%d pendingEnemy=%s oppPos=%d oppTarget=%d selected=%d segs=%d sendq=%d replayPlayback=%s autoPending=%s round=%s shot=%s gameOver=%s result=%s" % [
		playernum,
		str(is_my_turn),
		str(spectator_mode),
		_hp_me,
		_hp_opp,
		str(_pending_enemy_shot),
		_opp_pos_enc,
		_opp_target_enc,
		_selected_shoot_lane(),
		_replay_segments.size(),
		_replay_send_segments.size(),
		str(_is_replay_playback),
		str(_replay_auto_pending),
		str(_round_sequence_running),
		str(_is_shot_sequence_running),
		str(game_over),
		win_loss_state
	]

var buttons
var replay
var round_mgr
var shots
var states
var ui

# -------------------------------------------------------------------
# Identity and turn state
# -------------------------------------------------------------------
var my_id: String = ""
var p1_id: String = ""
var p2_id: String = ""
var _opp_id: String = ""
var winner: String = ""

var playernum: int = 0
var turn_owner: int = 1
var is_your_turn: bool = false
var is_my_turn: bool = false
var _suppress_send_after_round: bool = false

# -------------------------------------------------------------------
# Win state
# -------------------------------------------------------------------
var game_ended: bool = false
var game_over: bool = false
var win_loss_state: String = "0"

# -------------------------------------------------------------------
# HP
# -------------------------------------------------------------------
var _hp_me: int = 3
var _hp_opp: int = 3

# -------------------------------------------------------------------
# Buttons / lanes
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
# Round / sequence flags
# -------------------------------------------------------------------
var _is_shot_sequence_running: bool = false
var _round_sequence_running: bool = false
var _shot_in_progress: bool = false
var _require_new_shoot_selection: bool = true
var _need_new_selection: bool = true
var _touched_this_turn: bool = false
var _opp_sprite_base_scale: Vector3 = Vector3.ONE
var _fp_aim_base_scale: Vector2 = Vector2.ONE
var _last_autoplayed_replay_str: String = ""

# -------------------------------------------------------------------
# Opponent pending shot + reveal
# -------------------------------------------------------------------
var _pending_enemy_shot: bool = false
var _opp_pos_enc: int = -1
var _opp_target_enc: int = -1
var _opp_target_enc_vis: int = -1
var _opp_target_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
var _opp_target_world: Vector3 = Vector3.ZERO
var _opp_reveal_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
var _opp_sprite_reveal_offset_y: float = -1.3
var _opp_sprite_start_pos: Vector3 = Vector3.ZERO

# -------------------------------------------------------------------
# Replay fields
# -------------------------------------------------------------------
var _replay_segments: PackedStringArray = PackedStringArray()
var _replay_seg_index: int = 0
var _replay_base_state: Dictionary = {}
var _last_replay_str: String = ""

var _is_replay_playback: bool = false
var _replay_auto_pending: bool = false
var _replay_auto_full_str: String = ""
var _replay_auto_end_state: Dictionary = {}
var _replay_send_segments: PackedStringArray = PackedStringArray()
var _replay_is_autoplay_round: bool = false
var _replay_send_armed: bool = false

# -------------------------------------------------------------------
# Camera / aim / recoil
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
# Fire button placement + splats
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
var _opp_avatar_texture_normal: Texture2D = null
var _opp_avatar_texture_pressed: Texture2D = null
var _opp_avatar_texture_hover: Texture2D = null

# -------------------------------------------------------------------
# Ready / process
# -------------------------------------------------------------------
func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
func _get_dev_data() -> String:
	var DEV_SCENARIO: int = 3

	var dev_data_1 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV1"}'
	var dev_data_2 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV1","replay":"hp1:3,hp2:3,pos1:0,pos2:0,target1:2,target2:2"}'
	var dev_data_3 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV3","replay":"hp1:3,hp2:3,pos1:0,pos2:0,target1:0,target2:0|hp1:2,hp2:3,pos1:0,pos2:0,target1:-1,target2:0"}'

	if DEV_SCENARIO == 2:
		return dev_data_2
	elif DEV_SCENARIO == 3:
		return dev_data_3

	return dev_data_1
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Paintball"
	
func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Paintball[/b][/font_size]

[font_size={24px}][b]Goal[/b][/font_size]
[font_size={18px}]
Pick where to move and where to shoot. Try to hit your opponent before they hit you.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• Choose a lane to move to.
• Choose a lane to shoot at.
• Press Fire to lock in your move.
• When both players have chosen, the round plays out.
[/font_size]

[font_size={24px}][b]End of Game[/b][/font_size]
[font_size={18px}]
• Each player starts with 3 hearts.
• A player loses a heart when they are hit.
• First player to reduce the other player to 0 hearts wins.
[/font_size]
"""

func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	_build_modules()

	buttons.setup(self)
	shots.setup(self)
	ui.setup(self)
	states.setup(self)
	replay.setup(self)
	round_mgr.setup(self)

	buttons.setup_buttons_root(buttons_root)
	buttons.collect_and_index_buttons()
	buttons.cache_lane_x_from_move_buttons()

	OpLog.i(LOG_TAG, ["game_ready buttons=", _buttons.size()])
	for b in _buttons:
		if is_instance_valid(b):
			dbg(["button name=", b.name, " kind=", int(b.kind), " lane=", int(b.lane)])

	buttons.connect_button_signals()
	buttons.update_move_buttons()

	_selected_shoot = null
	_require_new_shoot_selection = true

	if is_instance_valid(fire_button):
		fire_button.visible = false
		fire_button.modulate.a = 0.0
		fire_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_fire_button_is_shown = false

	if is_instance_valid(opponent_sprite):
		_opp_sprite_base_scale = opponent_sprite.scale
		_opp_sprite_start_pos = opponent_sprite.global_position
		dbg(["ready opponentStartPos=", _opp_sprite_start_pos])
		
	if is_instance_valid(fp_aim_sprite):
		_fp_aim_base_scale = fp_aim_sprite.scale
		_fp_aim_base_pos = fp_aim_sprite.position

	if is_instance_valid(opp_avatar_display):
		_opp_avatar_texture_normal = opp_avatar_display.get("texture_normal") as Texture2D
		_opp_avatar_texture_pressed = opp_avatar_display.get("texture_pressed") as Texture2D
		_opp_avatar_texture_hover = opp_avatar_display.get("texture_hover") as Texture2D

	if fire_button is BaseButton:
		var fire_callable := Callable(self, "_on_fire_pressed")
		if not (fire_button as BaseButton).pressed.is_connected(fire_callable):
			(fire_button as BaseButton).pressed.connect(fire_callable)

	await ui.init_fire_button()
	if is_instance_valid(fire_button):
		fire_button.visible = false
		fire_button.modulate.a = 0.0
		fire_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_fire_button_is_shown = false
	ui.init_player_splat_overlay()
	ui.init_opponent_splat()
	ui.apply_hearts_from_hp()
	
	OpLog.i(LOG_TAG, [
		"game_ready_done playerValid=", is_instance_valid(player),
		" opponentValid=", is_instance_valid(opponent_sprite),
		" fireButtonValid=", is_instance_valid(fire_button),
		" ", _state_summary()
	])

func _process(delta: float) -> void:		
	if shots != null:
		shots.tick(delta)
		
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		OpLog.i(LOG_TAG, "app_resumed")

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
# Set Game Data
# -------------------------------------------------------------------
func _set_game_data(raw_text: String) -> void:
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", raw_text])

	var parsed : Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, ["set_game_data invalid JSON raw=", raw_text])
		return

	my_id = my_uuid

	game_over = false
	game_ended = false
	win_loss_state = "0"
	winner = ""

	stop_waiting_animation()

	if is_instance_valid(win_loss_label):
		win_loss_label.visible = false
		win_loss_label.text = ""
		win_loss_label.scale = Vector2.ONE

	if states != null:
		states.set_game_data(raw_text)

	if replay != null and replay.has_method("on_payload_loaded"):
		replay.call("on_payload_loaded")

	if ui != null:
		ui.apply_hearts_from_hp()

	if winner != "":
		_apply_winner_payload(winner)
		
	OpLog.i(LOG_TAG, [
		"set_game_data_done winner=", winner,
		" replay=", _replay_summary(_last_replay_str),
		" ", _state_summary()
	])

# -------------------------------------------------------------------
# Button clicked entry point
# -------------------------------------------------------------------
func _on_button_clicked(b: ActionButton3D) -> void:
	if not is_my_turn or _is_shot_sequence_running or _round_sequence_running:
		OpLog.w(LOG_TAG, [
			"button_ignored name=", b.name if is_instance_valid(b) else "invalid",
			" turn=", is_my_turn,
			" shotSeq=", _is_shot_sequence_running,
			" roundSeq=", _round_sequence_running
		])
		return

	if b.kind == ActionButton3D.ButtonKind.MOVE:
		buttons.move_player_to_button(b)
		return

	if b.kind == ActionButton3D.ButtonKind.SHOOT:
		_selected_shoot = b
		_require_new_shoot_selection = false
		_aim_target_world = _selected_shoot.global_position + Vector3(0.0, 0.7, 0.0)

		buttons.update_shoot_selection_visuals(_selected_shoot)
		
		OpLog.i(LOG_TAG, [
			"shoot_selected lane=", int(_selected_shoot.lane),
			" targetWorld=", _aim_target_world,
			" ", _state_summary()
		])

		ui.show_fire_button(true)
		return

# -------------------------------------------------------------------
# Fire pressed gatekeeper
# -------------------------------------------------------------------
func _on_fire_pressed() -> void:
	if not is_my_turn:
		OpLog.w(LOG_TAG, ["fire_ignored turn=false ", _state_summary()])
		return

	if _is_shot_sequence_running or _round_sequence_running:
		OpLog.w(LOG_TAG, ["fire_ignored sequence_running ", _state_summary()])
		return

	if _require_new_shoot_selection or _selected_shoot == null or not is_instance_valid(_selected_shoot):
		OpLog.w(LOG_TAG, ["fire_ignored no_shoot_selection ", _state_summary()])
		return

	OpLog.i(LOG_TAG, [
		"fire_pressed myLane=", int(_player_lane),
		" selectedLane=", _selected_shoot_lane(),
		" pendingEnemy=", _pending_enemy_shot,
		" replay=", _replay_summary(_last_replay_str),
		" ", _state_summary()
	])

	_replay_send_armed = true
	_replay_is_autoplay_round = false

	var my_pos_int: int = states.lane_to_pos_enc(_player_lane)
	var my_target_int: int = states.lane_to_target_enc(_selected_shoot.lane)

	if _pending_enemy_shot:
		var my_pos_key: String = "pos1" if playernum == 1 else "pos2"
		var my_tgt_key: String = "target1" if playernum == 1 else "target2"
		var opp_pos_key: String = "pos2" if playernum == 1 else "pos1"
		var opp_tgt_key: String = "target2" if playernum == 1 else "target1"

		if _replay_send_segments.size() <= 0 and _replay_segments.size() > 0:
			_replay_send_segments = _replay_segments.duplicate()

		if _replay_send_segments.size() > 0:
			var head_state: Dictionary = _parse_replay_state(String(_replay_send_segments[0]))
			var opp_ready: bool = int(head_state.get(opp_pos_key, -1)) != -1 and int(head_state.get(opp_tgt_key, -1)) != -1

			if opp_ready:
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
				else:
					_replay_segments.append(_replay_send_segments[0])

				_apply_loaded_replay_segment(head_state)

				OpLog.i(LOG_TAG, ["fire_committed_pending_head head=", String(_replay_send_segments[0])])
		else:
			var st_pending: Dictionary = {
				"hp1": _hp_me if playernum == 1 else _hp_opp,
				"hp2": _hp_opp if playernum == 1 else _hp_me,
				"pos1": -1,
				"pos2": -1,
				"target1": -1,
				"target2": -1
			}

			if playernum == 1:
				st_pending["pos1"] = my_pos_int
				st_pending["target1"] = my_target_int
				st_pending["pos2"] = _opp_pos_enc
				st_pending["target2"] = _opp_target_enc
			else:
				st_pending["pos2"] = my_pos_int
				st_pending["target2"] = my_target_int
				st_pending["pos1"] = _opp_pos_enc
				st_pending["target1"] = _opp_target_enc

			_replay_send_segments.append(_replay_state_to_string(st_pending))
			_replay_segments.append(_replay_state_to_string(st_pending))
			_apply_loaded_replay_segment(st_pending)

			OpLog.i(LOG_TAG, ["fire_built_fallback_pending head=", _replay_state_to_string(st_pending)])

		_replay_auto_pending = false
		_is_replay_playback = true
		OpLog.i(LOG_TAG, ["fire_play_round_from_pending_enemy ", _state_summary()])
		round_mgr.play_round()
		return

	OpLog.i(LOG_TAG, ["fire_send_only_branch pendingEnemy=false ", _state_summary()])

	var st: Dictionary = {
		"hp1": 3,
		"hp2": 3,
		"pos1": -1,
		"pos2": -1,
		"target1": -1,
		"target2": -1
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

	OpLog.i(LOG_TAG, [
		"fire_appended_my_only seg=", _replay_state_to_string(st),
		" sendq=", _replay_send_segments.size()
	])

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
	OpLog.i(LOG_TAG, ["send_game_wrapper clearTargets=", clear_targets_for_next_turn, " ", _state_summary()])
	if game_over or spectator_mode:
		stop_waiting_animation()

		if ui != null:
			ui.show_fire_button(false)

		return

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
	if game_over or spectator_mode:
		stop_waiting_animation()
		return

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
		
func _apply_winner_payload(winner_payload: String) -> void:
	var parts := winner_payload.split("|", false)
	if parts.size() < 2:
		OpLog.w(LOG_TAG, ["winner_payload malformed raw=", winner_payload])
		return

	var sender_uuid := String(parts[0])
	var sender_state := String(parts[1])
	
	OpLog.i(LOG_TAG, ["winner_payload raw=", winner_payload, " sender=", sender_uuid, " senderState=", sender_state])
	
	if sender_state == "0":
		_show_result_from_state("0")
		return

	var local_state := sender_state

	if sender_uuid != my_uuid:
		local_state = "-1" if sender_state == "1" else "1"

	_show_result_from_state(local_state)
	
func _show_result_from_state(state: String) -> void:
	OpLog.i(LOG_TAG, ["show_result state=", state, " ", _state_summary()])
	game_over = true
	game_ended = true
	win_loss_state = state
	is_my_turn = false
	_is_shot_sequence_running = false
	_round_sequence_running = false
	_replay_auto_pending = false
	_replay_send_armed = false

	stop_waiting_animation()

	if ui != null:
		ui.show_fire_button(false)

	if not is_instance_valid(win_loss_label):
		return

	if state == "0":
		win_loss_label.text = "DRAW!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
	elif state == "1":
		win_loss_label.text = "YOU WIN!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

		if is_instance_valid(player_avatar_display):
			GameUtils._show_win_burst(player_avatar_display)
	else:
		win_loss_label.text = "YOU LOSE"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

		if is_instance_valid(opp_avatar_display):
			GameUtils._show_win_burst(opp_avatar_display)

	win_loss_label.visible = true
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2

	var tween_in := create_tween()
	tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

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
