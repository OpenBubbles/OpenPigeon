extends Node3D
class_name PaintballGame

@export var buttons_root: NodePath
@export var splat_tex: Texture2D

@onready var player: Node3D = %Player
@onready var fire_button: Control = %FireButton
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
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
const RULES_POPUP_SCENE = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")
const PAINTBALL_SCENE := preload("res://paintball/PaintballProjectile.tscn")
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
const SPLAT_TEX := preload("res://paintball/splat.png")
const OPPONENT_FACING_TEX := preload("res://paintball/opponent_facing.png")
const OPPONENT_SIDE_TEX := preload("res://paintball/opponent_side.png")

var _player_splat: TextureRect = null
var _player_splat_tween: Tween = null
var _opp_splat: Sprite3D = null
var _opp_splat_tween: Tween = null
var _hp_me: int = 3
var _hp_opp: int = 3
var ball_speed: float = 36.0
var _opp_id: String = ""
var p1_id: String = ""
var p2_id: String = ""
var _cam_start_xform: Transform3D
var _cam_start_fov: float
var _aim_target_world: Vector3
var _fp_aim_base_pos: Vector2
var _opp_reveal_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
var _player_hit_last: bool = false
var _enemy_hit_last: bool = false
var _opp_pos_enc: int = -1
var _require_new_shoot_selection: bool = true
var _opp_target_enc: int = -1
var _replay_auto_pending: bool = false
var _replay_auto_end_state: Dictionary = {}
var _replay_auto_full_str: String = ""
var _is_replay_playback: bool = false
var _is_shot_sequence_running: bool = false
var _round_sequence_running: bool = false
var _move_btn_by_lane: Dictionary = {}
var _shoot_btn_by_lane: Dictionary = {}
var _pending_enemy_shot: bool = false
var _opp_target_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
var _opp_target_world: Vector3 = Vector3.ZERO
var _opp_recoil_z: float = 0.22
var _replay_segments: PackedStringArray = PackedStringArray()
var _replay_seg_index: int = 0
var _replay_base_state: Dictionary = {}
var _opp_recoil_in_time: float = 0.06
var _opp_recoil_out_time: float = 0.10
var _round_end_white_in: float = 0.25
var _round_end_hold: float = 1.00
var _round_end_white_out: float = 0.45
var _opp_sprite_start_pos: Vector3
var _opp_sprite_reveal_offset_y: float = 1.5
var _muzzle_tex_px := Vector2(370.0, 180.0)
var _paintball_scale: float = 0.12
var _shot_in_progress: bool = false
var sent_tween: Tween
var _last_replay_str: String = ""
var dot_count: int = 0
var _replay_send_only_delta: bool = false
var has_connected: bool = false
var my_id: String
var _buttons: Array[ActionButton3D] = []
var _player_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
var playernum: int = 1
var _last_autoplayed_replay_str: String = ""
var _move_tween: Tween
var _need_new_selection: bool = true
var _touched_this_turn: bool = false
var _fire_btn_shown_pos: Vector2
var _fire_btn_hidden_pos: Vector2
var _fire_btn_tween: Tween
var _fire_button_is_shown: bool = false
var winner_id: String = "-1"
var game_settings_category: String = ""
var is_your_turn: bool = false
var turn_owner: int = 1
var is_my_turn: bool = false
var spectator_mode: bool = false
var game_ended = false
var game_over = false
var win_loss_state = ""

var _lane_x := {
	ActionButton3D.Lane.LEFT: 0.0,
	ActionButton3D.Lane.CENTER: 0.0,
	ActionButton3D.Lane.RIGHT: 0.0,
}

var _selected_shoot: ActionButton3D = null

func _ready() -> void:
	var root: Node = self
	if buttons_root != NodePath(""):
		root = get_node(buttons_root)

	_buttons.clear()
	_collect_buttons(root)
	_index_buttons()

	for b in _buttons:
		b.clicked.connect(_on_button_clicked)

	_update_move_buttons()
	_init_fire_button()
	_show_fire_button(false)

	if is_instance_valid(rules_button):
		rules_button.pressed.connect(on_rules_button_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	if is_instance_valid(opponent_sprite):
		_opp_sprite_start_pos = opponent_sprite.global_position
	if fire_button is Button:
		(fire_button as Button).pressed.connect(_on_fire_pressed)
	elif fire_button is BaseButton:
		(fire_button as BaseButton).pressed.connect(_on_fire_pressed)

	if is_instance_valid(fp_aim_sprite):
		fp_aim_sprite.visible = false
		_fp_aim_base_pos = fp_aim_sprite.position
		_init_player_splat_overlay()
		_init_opponent_splat()

	if is_instance_valid(fade_white):
		fade_white.top_level = true
		fade_white.z_as_relative = false
		fade_white.z_index = 10000
		fade_white.visible = true
		fade_white.color.a = 0.0

	if is_instance_valid(fp_aim_sprite):
		fp_aim_sprite.top_level = false
		fp_aim_sprite.z_as_relative = false
		fp_aim_sprite.z_index = -10

	if is_instance_valid(opponent_sprite):
		opponent_sprite.scale = Vector3.ONE * 0.4

	if is_instance_valid(top_info):
		top_info.z_as_relative = false
		top_info.z_index = 10

	if is_instance_valid(player_avatar_display) and player_avatar_display is CanvasItem:
		(player_avatar_display as CanvasItem).z_as_relative = false
		(player_avatar_display as CanvasItem).z_index = 10
	if is_instance_valid(opp_avatar_display) and opp_avatar_display is CanvasItem:
		(opp_avatar_display as CanvasItem).z_as_relative = false
		(opp_avatar_display as CanvasItem).z_index = 10

	_cache_lane_x_from_move_buttons()
	_player_lane = _lane_from_player_x()
	_update_move_buttons()
	randomize()
	_spawn_player_random_lane()

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

		var DEV_SCENARIO: int = 3

		var dev_data_0 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV0"}'
		var dev_data_1 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV1","replay":"hp1:3,hp2:3,pos1:2,pos2:-1,target1:2,target2:-1"}'
		var dev_data_2 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV2","replay":"hp1:3,hp2:3,pos1:2,pos2:1,target1:2,target2:0"}'
		var dev_data_3 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV3","replay":"hp1:2,hp2:3,pos1:2,pos2:1,target1:2,target2:2|hp1:1,hp2:3,pos1:2,pos2:1,target1:-1,target2:1"}'
		var dev_data_4 := '{"isYourTurn": true,"player":"2","myPlayerId":"","player1":"","player2":"","avatar1":"","avatar2":"","game":"paint","tver":"5","ios":"26.2.1","id":"DEV4","replay":"hp1:1,hp2:1,pos1:-1,pos2:2,target1:-1,target2:2"}'

		var dev_data := dev_data_1
		match DEV_SCENARIO:
			0:
				dev_data = dev_data_0
			1:
				dev_data = dev_data_1
			2:
				dev_data = dev_data_2
			3:
				dev_data = dev_data_3
			4:
				dev_data = dev_data_4
			_:
				dev_data = dev_data_1

		print("[DEV] Using scenario=", DEV_SCENARIO, " data=", dev_data)
		_set_game_data(dev_data)

func _set_game_data(raw_text: String) -> void:
	var res: Dictionary = JSON.parse_string(raw_text)
	if typeof(res) != TYPE_DICTIONARY:
		return

	print("RAW INCOMING DATA: ", res)

	my_id = _res_str(res, "myPlayerId", "")
	p1_id = _res_str(res, "player1", "")
	p2_id = _res_str(res, "player2", "")

	_opp_id = ""
	if my_id != "" and p1_id != "" and p2_id != "":
		if my_id == p1_id:
			_opp_id = p2_id
		elif my_id == p2_id:
			_opp_id = p1_id

	turn_owner = clamp(_res_int(res, "player", 1), 1, 2)
	is_your_turn = _res_bool(res, "isYourTurn", false)

	if my_id != "" and p1_id != "" and p2_id != "":
		playernum = (1 if my_id == p1_id else (2 if my_id == p2_id else 0))
		if playernum == 0:
			spectator_mode = true
			if is_instance_valid(you_label):
				you_label.text = ""
			if is_instance_valid(spec_label):
				spec_label.show()
			playernum = 1
	else:
		playernum = (1 if turn_owner == 2 else 2)

	is_my_turn = is_your_turn
	_need_new_selection = true
	_touched_this_turn = false
	_selected_shoot = null

	if is_my_turn:
		_require_new_shoot_selection = true
		_selected_shoot = null
		_show_fire_button(false)
		if is_instance_valid(fire_button):
			fire_button.visible = false

		stop_waiting_animation()

		_set_all_buttons_clickable(true)
		_update_move_buttons()
	else:
		_show_fire_button(false)
		if is_instance_valid(fire_button):
			fire_button.visible = false

		_set_all_buttons_clickable(false)

		if not game_over:
			start_waiting_animation()

	var opponent_avatar_key: String = ("avatar2" if playernum == 1 else "avatar1")
	if opponent_avatar_key != "" and res.has(opponent_avatar_key):
		var avatar_string: String = _res_str(res, opponent_avatar_key, "")
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	var replay_str: String = _res_str(res, "replay", "")
	print("[REPLAY] raw=", replay_str)

	_pending_enemy_shot = false
	_opp_target_world = Vector3.ZERO
	_opp_target_lane = ActionButton3D.Lane.CENTER

	var hp1: int = 3
	var hp2: int = 3

	if replay_str != "":
		_replay_segments = replay_str.split("|", false)
		_replay_seg_index = 0
		_replay_base_state = {}

		var cur_seg := _replay_segments[_replay_seg_index]
		var cur_state := _parse_replay_state(cur_seg)
		_replay_base_state = cur_state

		print("[REPLAY] segments=", _replay_segments.size(), " cur=", cur_seg)

		_apply_loaded_replay_segment(cur_state)

		hp1 = int(cur_state.get("hp1", 3))
		hp2 = int(cur_state.get("hp2", 3))

		_last_replay_str = replay_str

		_prime_autoplay_if_loaded_segment_ready()
	else:
		_replay_segments = []
		_replay_seg_index = 0
		_replay_base_state = {}
		print("[REPLAY] no replay in payload yet (first move scenario)")

	_hp_me = clamp((hp1 if playernum == 1 else hp2), 0, 3)
	_hp_opp = clamp((hp2 if playernum == 1 else hp1), 0, 3)
	print("ME HP: ", _hp_me, " | OPP HP: ", _hp_opp)
	_last_replay_str = replay_str

	_apply_hearts_from_hp()
	_update_move_buttons()

	game_ended = check_win()
	if game_ended:
		stop_waiting_animation()
		game_over = true
		if is_instance_valid(fp_aim_sprite):
			fp_aim_sprite.visible = false

		_show_fire_button(false)
		if is_instance_valid(fire_button):
			fire_button.visible = false

		for b in _buttons:
			if not is_instance_valid(b):
				continue
			b.visible = false
			b.set_click_enabled(false)
			_set_button_enabled(b, false)

func _collect_buttons(n: Node) -> void:
	if n is ActionButton3D:
		_buttons.append(n)
	for c in n.get_children():
		_collect_buttons(c)

func _spawn_player_random_lane() -> void:
	var lanes := [
		ActionButton3D.Lane.LEFT,
		ActionButton3D.Lane.CENTER,
		ActionButton3D.Lane.RIGHT
	]

	var chosen: ActionButton3D.Lane = lanes[randi() % lanes.size()]
	var p := player.global_position
	p.x = float(_lane_x[chosen])
	player.global_position = p

	_player_lane = chosen
	_update_move_buttons()

func _init_fire_button() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	fire_button.top_level = true
	fire_button.visible = true
	fire_button.reset_size()
	await get_tree().process_frame

	var vp := get_viewport().get_visible_rect().size
	var margin := 26.0
	var lift := 100.0

	_fire_btn_shown_pos = Vector2(
		(vp.x - fire_button.size.x) * 0.5,
		vp.y - fire_button.size.y - margin - lift
	)

	_fire_btn_hidden_pos = Vector2(_fire_btn_shown_pos.x, vp.y + fire_button.size.y + 40.0)
	fire_button.modulate.a = 0.0
	fire_button.global_position = _fire_btn_hidden_pos

func _show_fire_button(should_show: bool) -> void:
	if should_show == _fire_button_is_shown:
		return
	fire_button.visible = true
	_fire_button_is_shown = should_show

	if _fire_btn_tween and _fire_btn_tween.is_valid():
		_fire_btn_tween.kill()

	_fire_btn_tween = create_tween()
	_fire_btn_tween.set_trans(Tween.TRANS_SINE)
	_fire_btn_tween.set_ease(Tween.EASE_OUT)

	if should_show:
		fire_button.top_level = true
		fire_button.global_position = _fire_btn_hidden_pos
		fire_button.modulate.a = 0.0
		fire_button.visible = true

		_fire_btn_tween.tween_property(fire_button, "global_position", _fire_btn_shown_pos, 0.25)
		_fire_btn_tween.parallel().tween_property(fire_button, "modulate:a", 1.0, 0.18)
	else:
		_fire_btn_tween.tween_property(fire_button, "modulate:a", 0.0, 0.15)
		_fire_btn_tween.tween_callback(func() -> void:
			fire_button.global_position = _fire_btn_hidden_pos
		)

func _on_button_clicked(b: ActionButton3D) -> void:
	if not is_my_turn or _is_shot_sequence_running or _round_sequence_running:
		print("[INPUT] Ignored button click (not my turn or sequence running). kind=", b.kind, " lane=", b.lane)
		return

	if b.kind == ActionButton3D.ButtonKind.MOVE:
		_move_player_to_button(b)
	elif b.kind == ActionButton3D.ButtonKind.SHOOT:
		_select_shoot_button(b)

func set_player_lane(v: ActionButton3D.Lane) -> void:
	_player_lane = v
	_update_move_buttons()

func _cache_lane_x_from_move_buttons() -> void:
	for b in _buttons:
		if b.kind != ActionButton3D.ButtonKind.MOVE:
			continue
		_lane_x[b.lane] = b.global_position.x

func _lane_from_player_x() -> ActionButton3D.Lane:
	var px: float = player.global_position.x

	var best_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
	var best_d: float = INF

	for ln in [ActionButton3D.Lane.LEFT, ActionButton3D.Lane.CENTER, ActionButton3D.Lane.RIGHT]:
		var d: float = abs(px - float(_lane_x[ln]))
		if d < best_d:
			best_d = d
			best_lane = ln

	return best_lane

func _move_player_to_button(b: ActionButton3D) -> void:
	if not is_my_turn or _is_shot_sequence_running or _round_sequence_running:
		print("[INPUT] Ignored move (not my turn or sequence running).")
		return

	if not player:
		return

	var start_lane: ActionButton3D.Lane = _player_lane
	var target_lane: ActionButton3D.Lane = b.lane
	if start_lane == target_lane:
		return

	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()

	var base_y: float = player.global_position.y
	var base_z: float = player.global_position.z

	var path: Array[ActionButton3D.Lane] = []
	path.append(start_lane)

	if abs(int(target_lane) - int(start_lane)) == 2:
		path.append(ActionButton3D.Lane.CENTER)

	path.append(target_lane)

	var hop_height: float = 0.85
	var leg_time: float = 0.35

	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_SINE)
	_move_tween.set_ease(Tween.EASE_OUT)

	for i in range(1, path.size()):
		var leg_lane: ActionButton3D.Lane = path[i]
		var leg_x: float = float(_lane_x[leg_lane])

		_move_tween.tween_property(player, "global_position:x", leg_x, leg_time)

		var yseq: Tween = _move_tween.parallel()
		yseq.tween_method(func(t: float) -> void:
			var y := base_y + hop_height * 4.0 * t * (1.0 - t)
			player.global_position.y = y
		, 0.0, 1.0, leg_time)

		_move_tween.tween_callback(func() -> void:
			var p := player.global_position
			p.y = base_y
			p.z = base_z
			player.global_position = p

			_player_lane = leg_lane
			_update_move_buttons()
		)

	_move_tween.finished.connect(func() -> void:
		var p := player.global_position
		p.y = base_y
		p.z = base_z
		player.global_position = p

		_player_lane = _lane_from_player_x()
		_update_move_buttons()
	)

func _parse_replay_state(state: String) -> Dictionary:
	var out := {
		"hp1": 3, "hp2": 3,
		"pos1": -1, "pos2": -1,
		"target1": -1, "target2": -1
	}

	if state == "":
		return out

	for p in state.split(",", false):
		var kv := String(p).split(":", false)
		if kv.size() != 2:
			continue
		var k := String(kv[0])
		var v := int(String(kv[1]))
		if out.has(k):
			out[k] = v

	return out

func _autoplay_replay_round() -> void:
	if not _replay_auto_pending:
		return
	if _round_sequence_running or _is_shot_sequence_running:
		return

	_replay_auto_pending = false

	if _replay_auto_full_str != "" and _replay_auto_full_str == _last_autoplayed_replay_str:
		return
	_last_autoplayed_replay_str = _replay_auto_full_str

	_set_all_buttons_clickable(false)

	_pending_enemy_shot = true
	_is_replay_playback = true

	play_round()

func _on_fire_pressed() -> void:
	if not is_my_turn or _is_shot_sequence_running or _round_sequence_running:
		print("[INPUT] Ignored fire (not my turn or sequence running).")
		return

	_dbg("FIRE_PRESSED")

	if _require_new_shoot_selection or _selected_shoot == null or not is_instance_valid(_selected_shoot):
		print("[FIRE] Blocked: select a shoot target first.")
		return

	if _pending_enemy_shot:
		play_round()
		return

	if _replay_segments.size() > 0 and _replay_seg_index < _replay_segments.size() - 1:
		var next_state := _parse_replay_state(_replay_segments[_replay_seg_index + 1])

		if _state_has_opponent_ready(next_state):
			_is_replay_playback = false
			_replay_auto_end_state = next_state
			_replay_auto_full_str = "|".join(_replay_segments)

			var opp_pos: int = int(next_state.get("pos2", -1)) if playernum == 1 else int(next_state.get("pos1", -1))
			var opp_tgt: int = int(next_state.get("target2", -1)) if playernum == 1 else int(next_state.get("target1", -1))
			_opp_pos_enc = opp_pos
			_opp_target_enc = opp_tgt
			_pending_enemy_shot = (opp_pos != -1 and opp_tgt != -1)

			_replay_seg_index += 1

			play_round()
			return

	print("[FIRE] Opponent has not moved yet. Sending my move only.")
	send_game()

func _select_shoot_button(selected: ActionButton3D) -> void:
	if not is_my_turn or _is_shot_sequence_running or _round_sequence_running:
		print("[INPUT] Ignored shoot select (not my turn or sequence running).")
		return

	var had_selection := _selected_shoot != null

	if _selected_shoot == selected:
		_selected_shoot = null

		for b in _buttons:
			if b.kind == ActionButton3D.ButtonKind.SHOOT:
				_set_button_enabled(b, true)

		_show_fire_button(false)

		_require_new_shoot_selection = true
		return

	_selected_shoot = selected
	_require_new_shoot_selection = false

	for b in _buttons:
		if b.kind != ActionButton3D.ButtonKind.SHOOT:
			continue

		if b == selected:
			_set_button_enabled(b, true)
		else:
			_set_button_enabled(b, false)

	if not had_selection:
		_show_fire_button(true)

func play_round() -> void:
	if not is_my_turn or _is_shot_sequence_running or _round_sequence_running:
		print("[INPUT] Ignored play_round (not my turn or sequence running).")
		return

	if _require_new_shoot_selection or _selected_shoot == null or not is_instance_valid(_selected_shoot):
		print("[PLAYROUND] Blocked: select a shoot target first.")
		return
	_dbg("PLAY_ROUND_ENTER")

	if not _pending_enemy_shot:
		print("[PLAYROUND] Blocked: opponent shot not ready (this should be gated by _on_fire_pressed).")
		return

	if _opp_pos_enc != -1 and is_instance_valid(opponent_sprite):
		var opp_lane: ActionButton3D.Lane = _enc_to_lane(_opp_pos_enc)

		var opp_x: float = float(_lane_x[opp_lane])
		var shoot_btn: ActionButton3D = _shoot_btn_by_lane.get(opp_lane, null)
		if is_instance_valid(shoot_btn):
			opp_x = shoot_btn.global_position.x

		var op := opponent_sprite.global_position
		op.x = opp_x
		opponent_sprite.global_position = op
		print("[PLAYROUND] Opp pos enc=", _opp_pos_enc, " => lane=", opp_lane, " set opp_x=", opp_x)

	if _opp_target_enc != -1:
		var flipped_enc: int = _flip_enc_for_perspective(_opp_target_enc)
		_opp_target_lane = _enc_to_lane(flipped_enc)

		var tgt_world: Vector3 = Vector3.ZERO
		var shoot_btn2: ActionButton3D = _shoot_btn_by_lane.get(_opp_target_lane, null)
		if is_instance_valid(shoot_btn2):
			tgt_world = shoot_btn2.global_position + Vector3(0.0, 0.7, 0.0)

		if tgt_world == Vector3.ZERO:
			var tx: float = float(_lane_x[_opp_target_lane])
			tgt_world = Vector3(tx, player.global_position.y + 0.7, player.global_position.z)

		_opp_target_world = tgt_world
		print("[PLAYROUND] Opp target enc=", _opp_target_enc, " => lane=", _opp_target_lane, " world=", _opp_target_world)
		_update_opponent_sprite_pose_for_shot()

	var cam3d := get_viewport().get_camera_3d()
	if not cam3d:
		return

	_is_shot_sequence_running = true
	(fire_button as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	_cam_start_fov = cam3d.fov
	_cam_start_xform = cam3d.global_transform

	var focus_point := player.global_position + Vector3(0.0, 0.8, 0.0)
	var aim_point := _selected_shoot.global_position + Vector3(0.0, 0.7, 0.0)
	_aim_target_world = aim_point

	var dur_in := 1.10
	var hold_white := 1.00
	var dur_out := 0.65
	var dur_pan := 0.85
	var snap_offset_local := Vector3(0, 1.65, 2.10)
	var start_pitch_down_deg := 18.0
	var extra_pitch_down_deg := 20.0

	var target_fov := clampf(_cam_start_fov * 0.35, 10.0, _cam_start_fov)
	var punch_transform := _compute_zoom_target(cam3d, focus_point)

	if is_instance_valid(fade_white):
		fade_white.top_level = true
		fade_white.z_as_relative = false
		fade_white.z_index = 10000
		fade_white.visible = true

	if is_instance_valid(fp_aim_sprite):
		fp_aim_sprite.top_level = false
		fp_aim_sprite.z_as_relative = false
		fp_aim_sprite.z_index = -10

	var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	t.tween_property(cam3d, "fov", target_fov, dur_in)
	t.parallel().tween_property(cam3d, "global_transform", punch_transform, dur_in)
	t.parallel().tween_property(fade_white, "color:a", 1.0, dur_in)

	var fade_out_nodes := [rules_button, settings_button, fire_button, top_info, player_avatar_display, opp_avatar_display]
	for n in fade_out_nodes:
		if is_instance_valid(n) and n is CanvasItem:
			t.parallel().tween_property(n, "modulate:a", 0.0, dur_in)

	t.tween_callback(func() -> void:
		if is_instance_valid(player):
			player.visible = false
		if is_instance_valid(opponent_sprite):
			opponent_sprite.visible = true
		if is_instance_valid(player_avatar_display) and player_avatar_display is CanvasItem:
			player_avatar_display.visible = true
			(player_avatar_display as CanvasItem).modulate.a = 0.0
		if is_instance_valid(opp_avatar_display) and opp_avatar_display is CanvasItem:
			opp_avatar_display.visible = true
			(opp_avatar_display as CanvasItem).modulate.a = 0.0
		if is_instance_valid(top_info) and top_info is CanvasItem:
			top_info.visible = true
			(top_info as CanvasItem).modulate.a = 0.0

		if is_instance_valid(fp_aim_sprite):
			fp_aim_sprite.visible = true
			_fp_aim_base_pos = Vector2(259, 1071)
			fp_aim_sprite.position = _fp_aim_base_pos

		for b in _buttons:
			if not is_instance_valid(b):
				continue
			if b.kind == ActionButton3D.ButtonKind.MOVE:
				b.visible = false
				b.set_click_enabled(false)
			elif b.kind == ActionButton3D.ButtonKind.SHOOT:
				if b == _selected_shoot:
					b.visible = true
					b.set_click_enabled(false)
				else:
					b.visible = false
					b.set_click_enabled(false)

		var hide_nodes := [rules_button, settings_button, fire_button]
		for n in hide_nodes:
			if is_instance_valid(n):
				n.visible = false

		if is_instance_valid(player):
			var player_xform := player.global_transform
			var snap_pos := player_xform.origin + (player_xform.basis * snap_offset_local)

			var snap_basis := player_xform.basis
			snap_basis = snap_basis.rotated(snap_basis.x.normalized(), -deg_to_rad(start_pitch_down_deg))

			cam3d.global_transform = Transform3D(snap_basis, snap_pos)

		cam3d.fov = _cam_start_fov
	)

	t.tween_interval(hold_white)
	t.tween_property(fade_white, "color:a", 0.0, dur_out)

	if is_instance_valid(player_avatar_display) and player_avatar_display is CanvasItem:
		t.parallel().tween_property(player_avatar_display, "modulate:a", 1.0, dur_out)
	if is_instance_valid(opp_avatar_display) and opp_avatar_display is CanvasItem:
		t.parallel().tween_property(opp_avatar_display, "modulate:a", 1.0, dur_out)
	if is_instance_valid(top_info) and top_info is CanvasItem:
		t.parallel().tween_property(top_info, "modulate:a", 1.0, dur_out)

	t.tween_callback(func() -> void:
		var cam_pos := cam3d.global_transform.origin

		var aim_bias_x := 0.0
		if _player_lane == ActionButton3D.Lane.LEFT and _selected_shoot.lane == ActionButton3D.Lane.LEFT:
			aim_bias_x = 4
		elif _player_lane == ActionButton3D.Lane.RIGHT and _selected_shoot.lane == ActionButton3D.Lane.RIGHT:
			aim_bias_x = -4

		var biased_aim_point := aim_point + Vector3(aim_bias_x, 0.0, 0.0)

		var look_xform := Transform3D().looking_at(biased_aim_point, Vector3.UP)
		look_xform.origin = cam_pos

		var b := look_xform.basis
		b = b.rotated(b.x.normalized(), -deg_to_rad(extra_pitch_down_deg))

		var end_xform := Transform3D(b, cam_pos)

		var pan := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		pan.tween_property(cam3d, "global_transform", end_xform, dur_pan)

		pan.finished.connect(func() -> void:
			_shot_in_progress = true
			print("[ROUND] Camera pan finished. Begin reveal + shot sequence")

			_reveal_opponent_sprite()

			var seq := create_tween()
			seq.tween_interval(0.5)

			seq.tween_callback(func() -> void:
				print("[ROUND] Player firing moment reached (after 0.5s)")
				_fade_out_selected_aim_target()
				_play_fp_recoil()
				_run_player_then_enemy_shot_sequence(aim_point)
			)
		)
	)

func _nearest_lane_from_x(x: float) -> ActionButton3D.Lane:
	var best_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
	var best_d: float = INF

	for ln: ActionButton3D.Lane in [
		ActionButton3D.Lane.LEFT,
		ActionButton3D.Lane.CENTER,
		ActionButton3D.Lane.RIGHT
	]:
		var lx: float = float(_lane_x[ln])
		var d: float = abs(x - lx)
		if d < best_d:
			best_d = d
			best_lane = ln

	return best_lane

func _get_world_for_player_lane(lane: ActionButton3D.Lane) -> Vector3:
	if not is_instance_valid(player):
		return Vector3.ZERO

	var p := player.global_position
	p.x = float(_lane_x[lane])
	return p + Vector3(0.0, 0.85, 0.0)

func _compute_player_hit_debug(impact_world: Vector3) -> bool:
	var impact_lane := _nearest_lane_from_x(impact_world.x)
	var hit := (impact_lane == _opp_reveal_lane)

	print("[HITCHECK][PLAYER] impact_x=", impact_world.x, " impact_lane=", impact_lane, " opp_reveal_lane=", _opp_reveal_lane, " => hit=", hit)
	return hit

func _fire_paintball_and_wait(target_world: Vector3, is_enemy: bool, on_reached: Callable = Callable()) -> Vector3:
	if not is_instance_valid(cam):
		print("[SHOT] ERROR: cam invalid, cannot fire.")
		return Vector3.ZERO

	var ball := PAINTBALL_SCENE.instantiate() as PaintballProjectile
	if ball == null:
		print("[SHOT] ERROR: projectile instantiate failed.")
		return Vector3.ZERO

	var muzzle_world: Vector3
	var target_fixed := target_world

	if is_enemy and is_instance_valid(opponent_sprite):
		muzzle_world = opponent_sprite.global_position + Vector3(0.0, 0.9, 0.0)

		var cam_pos := cam.global_transform.origin
		muzzle_world.y = cam_pos.y
		target_fixed.y = cam_pos.y
		target_fixed.z = cam_pos.z

		if is_equal_approx(muzzle_world.z, target_fixed.z):
			target_fixed.z += 0.05
	else:
		var muzzle_screen := _get_muzzle_screen_pos()

		var ray_origin := cam.project_ray_origin(muzzle_screen)
		var ray_dir := cam.project_ray_normal(muzzle_screen).normalized()

		var tt := (target_fixed - ray_origin).dot(ray_dir)
		tt = maxf(tt, 0.35)
		muzzle_world = ray_origin + ray_dir * tt

		if is_instance_valid(opponent_sprite):
			target_fixed.z = opponent_sprite.global_position.z

	ball.scale = Vector3.ONE * _paintball_scale
	ball.speed = (ball_speed * 2.25) if is_enemy else ball_speed
	ball.use_plane_z = true

	if is_enemy:
		if is_instance_valid(player):
			ball.hit_plane_z = player.global_position.z
		else:
			ball.use_plane_z = false
	else:
		if is_instance_valid(opponent_sprite):
			ball.hit_plane_z = opponent_sprite.global_position.z
		else:
			ball.use_plane_z = false

	var desired_color: Color
	if is_enemy:
		desired_color = Color(0.9, 0.15, 0.15)
	else:
		desired_color = Color(1.0, 0.95, 0.2)

	ball.set_ball_color(desired_color)

	var mi := ball.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi == null:
		mi = ball.find_child("MeshInstance3D", true, false) as MeshInstance3D
	if mi != null:
		var mat := mi.material_override
		if mat == null:
			mat = StandardMaterial3D.new()
			mi.material_override = mat
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			sm.albedo_color = desired_color
			sm.emission_enabled = true
			sm.emission = desired_color * 0.35

	get_tree().current_scene.add_child(ball)

	print("[SHOT] launch is_enemy=", is_enemy, " muzzle=", muzzle_world, " target=", target_fixed, " plane_z=", ball.hit_plane_z)

	var box := {
		"got": false,
		"impact": Vector3.ZERO
	}

	ball.reached_plane.connect(func(world_pos: Vector3) -> void:
		if box["got"]:
			return

		if not is_enemy and is_instance_valid(ball):
			ball.visible = false
			ball.queue_free()

		if on_reached.is_valid():
			on_reached.call(world_pos)

		box["got"] = true
		box["impact"] = world_pos
	)

	ball.launch(muzzle_world, target_fixed)

	var timeout_s: float = 3.0
	var start_ms: int = Time.get_ticks_msec()

	while not box["got"]:
		await get_tree().process_frame
		var elapsed_s: float = float(Time.get_ticks_msec() - start_ms) / 1000.0
		if elapsed_s >= timeout_s:
			break

	if not box["got"]:
		print("[SHOT] WARNING: reached_plane timeout after ", timeout_s, "s. Forcing impact.")
		box["impact"] = target_fixed

	var impact_world: Vector3 = box["impact"]

	await get_tree().process_frame

	if is_enemy and is_instance_valid(ball):
		ball.queue_free()

	return impact_world

func _end_round_fade_and_restore_next_round() -> void:
	if not is_instance_valid(fade_white) or not is_instance_valid(cam):
		return

	print("[ROUND] Fade to white start")
	fade_white.visible = true

	var t_in := create_tween()
	t_in.tween_property(fade_white, "color:a", 1.0, _round_end_white_in)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await t_in.finished
	print("[ROUND] White fully in")

	print("[ROUND] Restoring camera + UI (while white)")
	cam.fov = _cam_start_fov
	cam.global_transform = _cam_start_xform

	if is_instance_valid(opponent_sprite):
		opponent_sprite.global_position = _opp_sprite_start_pos

	if is_instance_valid(fp_aim_sprite):
		fp_aim_sprite.visible = false

	if is_instance_valid(player):
		player.visible = true

	_pending_enemy_shot = false
	_opp_pos_enc = -1
	_opp_target_enc = -1
	_opp_target_lane = ActionButton3D.Lane.CENTER
	_opp_target_world = Vector3.ZERO
	print("[ROUND] Cleared opponent move state (_pending_enemy_shot=false, enc=-1)")

	_restore_ui_after_round()

	_require_new_shoot_selection = true
	_selected_shoot = null
	_show_fire_button(false)
	if is_instance_valid(fire_button):
		fire_button.visible = false

	print("[ROUND] Holding white for 0.5s")
	await get_tree().create_timer(0.5).timeout

	if _is_replay_playback:
		_is_replay_playback = false

		if _replay_auto_end_state.size() > 0:
			var end_state := _replay_auto_end_state

			print("[REPLAY] end_state dict=", end_state)

			var hp1e: int = int(end_state.get("hp1", 3))
			var hp2e: int = int(end_state.get("hp2", 3))
			_hp_me = clamp((hp1e if playernum == 1 else hp2e), 0, 3)
			_hp_opp = clamp((hp2e if playernum == 1 else hp1e), 0, 3)
			print("ME HP: ", _hp_me, " | OPP HP: ", _hp_opp, " Comment 2")
			_apply_hearts_from_hp()

			var pos1e: int = int(end_state.get("pos1", -1))
			var pos2e: int = int(end_state.get("pos2", -1))
			var t1e: int = int(end_state.get("target1", -1))
			var t2e: int = int(end_state.get("target2", -1))

			var opp_pos_e: int = (pos2e if playernum == 1 else pos1e)
			var opp_target_e: int = (t2e if playernum == 1 else t1e)

			_opp_pos_enc = opp_pos_e
			_opp_target_enc = opp_target_e
			_pending_enemy_shot = (opp_pos_e != -1 and opp_target_e != -1)

			print("[REPLAY] carried forward next-round opp enc pos=", _opp_pos_enc, " target=", _opp_target_enc, " pending=", _pending_enemy_shot)

			_replay_auto_end_state = {}

		if _replay_segments.size() > 0:
			var pending_seg := _replay_segments[_replay_segments.size() - 1]
			_replay_segments = PackedStringArray([pending_seg])
			_replay_seg_index = 0
			_last_replay_str = pending_seg
		else:
			_last_replay_str = ""

		_replay_auto_full_str = ""

	print("[ROUND] Fade out from white start")
	var t_out := create_tween()
	t_out.tween_property(fade_white, "color:a", 0.0, _round_end_white_out)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await t_out.finished

	print("[ROUND] Fade out complete, next round ready")

func _init_player_splat_overlay() -> void:
	if _player_splat != null and is_instance_valid(_player_splat):
		return

	var attach_parent: Node = null

	if is_instance_valid(fp_aim_sprite):
		var parent: Node = fp_aim_sprite.get_parent()
		while parent != null and not (parent is CanvasLayer):
			parent = parent.get_parent()
		if parent != null and parent is CanvasLayer:
			attach_parent = parent
		else:
			attach_parent = fp_aim_sprite.get_parent()

	if attach_parent == null:
		attach_parent = get_tree().root

	_player_splat = TextureRect.new()
	_player_splat.name = "PlayerHitSplat"
	_player_splat.texture = SPLAT_TEX
	_player_splat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_splat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_splat.stretch_mode = TextureRect.STRETCH_SCALE
	_player_splat.visible = false
	_player_splat.modulate = Color(0.9, 0.15, 0.15, 0.0)
	_player_splat.z_as_relative = false
	_player_splat.z_index = 9000

	attach_parent.add_child(_player_splat)

func _state_has_both_players_ready(st: Dictionary) -> bool:
	return int(st.get("pos1", -1)) != -1 and int(st.get("target1", -1)) != -1 and int(st.get("pos2", -1)) != -1 and int(st.get("target2", -1)) != -1

func _state_has_opponent_ready(st: Dictionary) -> bool:
	var opp_pos: int = int(st.get("pos2", -1)) if playernum == 1 else int(st.get("pos1", -1))
	var opp_tgt: int = int(st.get("target2", -1)) if playernum == 1 else int(st.get("target1", -1))
	return opp_pos != -1 and opp_tgt != -1

func _apply_loaded_replay_segment(seg_state: Dictionary) -> void:
	var pos1: int = int(seg_state.get("pos1", -1))
	var pos2: int = int(seg_state.get("pos2", -1))
	var target1: int = int(seg_state.get("target1", -1))
	var target2: int = int(seg_state.get("target2", -1))

	var pos_me: int = (pos1 if playernum == 1 else pos2)
	var pos_opp: int = (pos2 if playernum == 1 else pos1)
	var target_me: int = (target1 if playernum == 1 else target2)
	var target_opp: int = (target2 if playernum == 1 else target1)

	_opp_pos_enc = pos_opp
	_opp_target_enc = target_opp
	_pending_enemy_shot = (pos_opp != -1 and target_opp != -1)

	if pos_me != -1 and is_instance_valid(player):
		_player_lane = _enc_to_lane(pos_me)
		var pp := player.global_position
		pp.x = float(_lane_x[_player_lane])
		player.global_position = pp

	if pos_opp != -1 and is_instance_valid(opponent_sprite):
		var opp_lane: ActionButton3D.Lane = _enc_to_lane(pos_opp)
		var op := opponent_sprite.global_position
		op.x = float(_lane_x[opp_lane])
		opponent_sprite.global_position = op

	_opp_target_world = Vector3.ZERO
	_opp_target_lane = ActionButton3D.Lane.CENTER
	if target_opp != -1:
		_opp_target_lane = _enc_to_lane(target_opp)
		var tx: float = float(_lane_x[_opp_target_lane])
		_opp_target_world = Vector3(tx, player.global_position.y + 0.7, player.global_position.z)
		_update_opponent_sprite_pose_for_shot()

	_selected_shoot = null
	_require_new_shoot_selection = true
	if target_me != -1:
		var my_t_lane: ActionButton3D.Lane = _enc_to_lane(target_me)
		_selected_shoot = _shoot_btn_by_lane.get(my_t_lane, null)
		if _selected_shoot != null:
			_require_new_shoot_selection = false

func _apply_hearts_from_hp() -> void:
	var p_hearts := [pheart1, pheart2, pheart3]
	var o_hearts := [oheart1, oheart2, oheart3]

	for i in range(3):
		if is_instance_valid(p_hearts[i]):
			p_hearts[i].texture = (HEART_FULL_TEX if i < _hp_me else HEART_VOID_TEX)
		if is_instance_valid(o_hearts[i]):
			o_hearts[i].texture = (HEART_FULL_TEX if i < _hp_opp else HEART_VOID_TEX)

func _prime_autoplay_if_loaded_segment_ready() -> void:
	if _replay_segments.size() <= 0:
		return

	var cur_state := _parse_replay_state(_replay_segments[_replay_seg_index])

	if not _state_has_both_players_ready(cur_state):
		return

	_is_replay_playback = true

	if _replay_seg_index < _replay_segments.size() - 1:
		var next_state := _parse_replay_state(_replay_segments[_replay_seg_index + 1])
		_replay_auto_end_state = next_state
		_replay_seg_index += 1
	else:
		_replay_auto_end_state = cur_state

	_replay_auto_full_str = "|".join(_replay_segments)
	_replay_auto_pending = true
	call_deferred("_autoplay_replay_round")

func _show_player_hit_splat() -> void:
	if _player_splat == null or not is_instance_valid(_player_splat):
		return

	if _player_splat_tween and _player_splat_tween.is_valid():
		_player_splat_tween.kill()

	var vp := get_viewport().get_visible_rect().size
	var center := vp * 0.5
	var base_w := vp.x * 0.78
	var base_h := vp.y * 0.58
	var w := base_w * randf_range(0.85, 1.10)
	var h := base_h * randf_range(0.85, 1.15)
	var off := Vector2(randf_range(-60.0, 60.0), randf_range(-90.0, 50.0))
	var pos := center + off

	_player_splat.size = Vector2(w, h)
	_player_splat.pivot_offset = _player_splat.size * 0.5
	_player_splat.position = pos - (_player_splat.size * 0.5)
	_player_splat.rotation = deg_to_rad(randf_range(0.0, 360.0))
	_player_splat.scale = Vector2(0.18, 0.18)
	_player_splat.modulate.a = 0.0
	_player_splat.visible = true

	_player_splat_tween = create_tween()
	_player_splat_tween.set_trans(Tween.TRANS_BACK)
	_player_splat_tween.set_ease(Tween.EASE_OUT)

	_player_splat_tween.tween_property(_player_splat, "modulate:a", 1.0, 0.08)
	_player_splat_tween.parallel().tween_property(_player_splat, "scale", Vector2.ONE, 0.18)

func _hide_player_hit_splat() -> void:
	if _player_splat == null or not is_instance_valid(_player_splat):
		return

	if _player_splat_tween and _player_splat_tween.is_valid():
		_player_splat_tween.kill()

	_player_splat.visible = false
	_player_splat.modulate.a = 0.0

func _init_opponent_splat() -> void:
	if _opp_splat != null and is_instance_valid(_opp_splat):
		return
	if not is_instance_valid(opponent_sprite):
		return

	_opp_splat = Sprite3D.new()
	_opp_splat.name = "OppHitSplat"
	_opp_splat.texture = SPLAT_TEX
	_opp_splat.visible = false
	_opp_splat.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_opp_splat.render_priority = 10
	_opp_splat.modulate = Color(1.0, 0.95, 0.2, 1.0)

	opponent_sprite.add_child(_opp_splat)

func _show_opponent_hit_splat() -> void:
	if _opp_splat == null or not is_instance_valid(_opp_splat):
		return

	if _opp_splat_tween and _opp_splat_tween.is_valid():
		_opp_splat_tween.kill()

	_opp_splat.visible = true
	_opp_splat.modulate.a = 0.0
	_opp_splat.position = Vector3(randf_range(-0.10, 0.10), 0.4, 0.03)
	_opp_splat.rotation = Vector3(0.0, 0.0, deg_to_rad(randf_range(0.0, 360.0)))

	_opp_splat_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_opp_splat_tween.tween_property(_opp_splat, "modulate:a", 1.0, 0.10)

func _hide_opponent_hit_splat() -> void:
	if _opp_splat == null or not is_instance_valid(_opp_splat):
		return

	if _opp_splat_tween and _opp_splat_tween.is_valid():
		_opp_splat_tween.kill()

	_opp_splat.visible = false
	_opp_splat.modulate.a = 0.0

func _run_player_then_enemy_shot_sequence(player_target_world: Vector3) -> void:
	if _round_sequence_running:
		print("[ROUND] Sequence already running, abort duplicate call.")
		return

	_round_sequence_running = true
	_is_shot_sequence_running = true
	var was_replay := _is_replay_playback
	var shoot_for_send := _selected_shoot
	var opp_pos_for_send := _opp_pos_enc
	var opp_target_for_send := _opp_target_enc

	print("[ROUND] ==============================")
	print("[ROUND] Sequence start")
	print("[ROUND] Player lane=", _player_lane, " Selected shoot=", (_selected_shoot.lane if _selected_shoot != null else -1))
	print("[ROUND] Opponent target lane=", _opp_target_lane, " Opponent target world=", _opp_target_world)
	print("[ROUND] ==============================")

	print("[ROUND][PLAYER] Step 1: Prep opp splat target + fire yellow shot")

	var shot_target := player_target_world

	if _opp_splat != null and is_instance_valid(_opp_splat) and is_instance_valid(opponent_sprite):
		if _opp_splat_tween and _opp_splat_tween.is_valid():
			_opp_splat_tween.kill()

		_opp_splat.visible = false
		_opp_splat.modulate.a = 0.0

		var splat_pos := Vector3(
			randf_range(-0.12, 0.12),
			1.5,
			-0.02
		)
		var splat_rot := Vector3(0.0, 0.0, deg_to_rad(randf_range(0.0, 360.0)))

		if _opp_target_lane == ActionButton3D.Lane.CENTER:
			splat_pos.x = 0.0
		elif _opp_target_lane == ActionButton3D.Lane.LEFT:
			splat_pos.x = 0.5
		elif _opp_target_lane == ActionButton3D.Lane.RIGHT:
			splat_pos.x = -0.5

		_opp_splat.position = splat_pos
		_opp_splat.rotation = splat_rot
		_opp_splat.scale = Vector3.ONE * 0.1

		var splat_world: Vector3 = opponent_sprite.to_global(_opp_splat.position)
		shot_target.y = splat_world.y

		if is_instance_valid(opponent_sprite):
			shot_target.z = opponent_sprite.global_position.z

	var player_impact := await _fire_paintball_and_wait(shot_target, false)

	print("[ROUND][PLAYER] Step 2: Determine hit/miss")
	_player_hit_last = _compute_player_hit_debug(player_impact)
	print("[ROUND][PLAYER] Result => hit=", _player_hit_last)

	if _player_hit_last:
		if _opp_splat != null and is_instance_valid(_opp_splat):
			if _opp_splat_tween and _opp_splat_tween.is_valid():
				_opp_splat_tween.kill()

			_opp_splat.visible = true
			_opp_splat.modulate.a = 0.0

			_opp_splat_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_opp_splat_tween.tween_property(_opp_splat, "modulate:a", 1.0, 0.10)

		_hp_opp = clamp(_hp_opp - 1, 0, 3)
		_apply_hearts_from_hp()

	print("[ROUND][PLAYER] Step 3: Pause 1.0s before opponent returns fire")
	await get_tree().create_timer(1.0).timeout

	print("[ROUND][ENEMY] Step 4: Opponent recoil + fire red shot")
	_play_opponent_recoil()

	var enemy_target_world := _opp_target_world
	if enemy_target_world == Vector3.ZERO:
		enemy_target_world = _get_world_for_player_lane(_opp_target_lane)

	print("[ROUND][ENEMY] Target lane=", _opp_target_lane, " computed_target_world=", enemy_target_world)

	print("[ROUND][ENEMY] Step 5: Fire red shot and wait until it passes us")
	var _enemy_impact := await _fire_paintball_and_wait(enemy_target_world, true)

	print("[ROUND][ENEMY] Step 6: Determine hit/miss")
	_enemy_hit_last = (_opp_target_lane == _player_lane)
	print("[HITCHECK][ENEMY] opp_target_lane=", _opp_target_lane, " player_lane=", _player_lane, " => hit=", _enemy_hit_last)
	print("[ROUND][ENEMY] Result => hit=", _enemy_hit_last)

	if _enemy_hit_last:
		_show_player_hit_splat()

		_hp_me = clamp(_hp_me - 1, 0, 3)
		print("ME HP: ", _hp_me, " | OPP HP: ", _hp_opp, " Comment 4")
		_apply_hearts_from_hp()

		print("[ROUND] Player was hit. Holding 2.0s before fade-to-white")
		await get_tree().create_timer(2.0).timeout

	game_ended = check_win()
	if game_ended:
		print("End Valid")
		if not _is_replay_playback:
			send_game()
		return

	print("[ROUND] Step 7: End of round fade/restore")
	await _end_round_fade_and_restore_next_round()

	if not was_replay:
		_selected_shoot = shoot_for_send
		_require_new_shoot_selection = (_selected_shoot == null)

		_selected_shoot = null
		_require_new_shoot_selection = true

	if not was_replay:
		_pending_enemy_shot = false
		_opp_pos_enc = -1
		_opp_target_enc = -1
		_opp_target_world = Vector3.ZERO
		_opp_target_lane = ActionButton3D.Lane.CENTER

	print("[ROUND] Sequence done")
	_round_sequence_running = false
	_is_shot_sequence_running = false

func _update_opponent_sprite_pose_for_shot() -> void:
	if not is_instance_valid(opponent_sprite):
		return

	if not is_instance_valid(player):
		opponent_sprite.texture = OPPONENT_FACING_TEX
		opponent_sprite.flip_h = false
		return

	var delta: int = int(_opp_target_lane) - int(_player_lane)

	if delta == 0:
		opponent_sprite.texture = OPPONENT_FACING_TEX
		opponent_sprite.flip_h = false
		return

	opponent_sprite.texture = OPPONENT_SIDE_TEX
	opponent_sprite.flip_h = (delta > 0)

func _reveal_opponent_sprite() -> void:
	if not is_instance_valid(opponent_sprite):
		return

	_opp_reveal_lane = _nearest_lane_from_x(opponent_sprite.global_position.x)
	print("[OPP] Reveal start. Opp lane=", _opp_reveal_lane, " opp_x=", opponent_sprite.global_position.x)

	var start_pos := opponent_sprite.global_position
	var end_pos := start_pos + Vector3(0.0, _opp_sprite_reveal_offset_y, 0.0)

	var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(opponent_sprite, "global_position", end_pos, 0.28)

func _fade_out_selected_aim_target() -> void:
	if not is_instance_valid(_selected_shoot):
		return

	var spr := _selected_shoot.get_node_or_null("Sprite3D") as Sprite3D
	if spr == null:
		return

	var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(spr, "modulate:a", 0.0, 0.18)
	t.tween_callback(func() -> void:
		if is_instance_valid(_selected_shoot):
			_selected_shoot.visible = false
	)

func _play_fp_recoil() -> void:
	if not is_instance_valid(fp_aim_sprite):
		return

	var base := fp_aim_sprite.position
	var kick := Vector2(18.0, 22.0)

	var t := create_tween()
	t.tween_property(fp_aim_sprite, "position", base + kick, 0.04)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(fp_aim_sprite, "position", base, 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _play_opponent_recoil() -> void:
	if not is_instance_valid(opponent_sprite):
		return

	var start := opponent_sprite.global_position
	var kick := start + Vector3(0.0, 0.0, -_opp_recoil_z)

	var t := create_tween()
	t.tween_property(opponent_sprite, "global_position", kick, _opp_recoil_in_time)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(opponent_sprite, "global_position", start, _opp_recoil_out_time)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await t.finished

func _restore_ui_after_round() -> void:
	_is_shot_sequence_running = false
	_shot_in_progress = false
	_hide_player_hit_splat()
	_hide_opponent_hit_splat()
	(fire_button as Control).mouse_filter = Control.MOUSE_FILTER_STOP

	var ui_nodes := [rules_button, settings_button, top_info]
	for n in ui_nodes:
		if is_instance_valid(n):
			n.visible = true
			n.modulate.a = 1.0

	_show_fire_button(false)
	if is_instance_valid(fire_button):
		fire_button.modulate.a = 1.0
		fire_button.global_position = _fire_btn_hidden_pos

	for b in _buttons:
		if not is_instance_valid(b):
			continue

		b.visible = true
		b.set_click_enabled(true)

		var spr := b.get_node_or_null("Sprite3D") as Sprite3D
		if spr != null:
			var c := spr.modulate
			c.a = 1.0
			spr.modulate = c

		_set_button_enabled(b, true)

	_selected_shoot = null

	if is_instance_valid(player):
		_player_lane = _lane_from_player_x()

	_update_move_buttons()

func _get_muzzle_screen_pos() -> Vector2:
	if not is_instance_valid(fp_aim_sprite):
		return Vector2.ZERO
	if fp_aim_sprite.texture == null:
		return fp_aim_sprite.global_position

	var tex_size := fp_aim_sprite.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return fp_aim_sprite.global_position

	var drawn_size := Vector2(tex_size.x * fp_aim_sprite.scale.x, tex_size.y * fp_aim_sprite.scale.y)

	var sx := drawn_size.x / tex_size.x
	var sy := drawn_size.y / tex_size.y
	var muzzle_local := Vector2(_muzzle_tex_px.x * sx, _muzzle_tex_px.y * sy)

	if fp_aim_sprite.centered:
		muzzle_local -= drawn_size * 0.5

	return fp_aim_sprite.global_position + muzzle_local.rotated(fp_aim_sprite.global_rotation)

func _state_to_replay_string(st: Dictionary) -> String:
	return "hp1:%d,hp2:%d,pos1:%d,pos2:%d,target1:%d,target2:%d" % [
		int(st.get("hp1", 3)),
		int(st.get("hp2", 3)),
		int(st.get("pos1", -1)),
		int(st.get("pos2", -1)),
		int(st.get("target1", -1)),
		int(st.get("target2", -1))
	]

func _my_keys() -> Dictionary:
	if playernum == 1:
		return {"pos":"pos1", "target":"target1"}
	return {"pos":"pos2", "target":"target2"}

func _hp_as_p1_order() -> Dictionary:
	if playernum == 1:
		return {"hp1": _hp_me, "hp2": _hp_opp}
	return {"hp1": _hp_opp, "hp2": _hp_me}

func _my_replay_keys() -> Dictionary:
	if playernum == 1:
		return {"pos": "pos1", "target": "target1"}
	return {"pos": "pos2", "target": "target2"}

func _replay_is_full_round(st: Dictionary) -> bool:
	return int(st.get("pos1", -1)) != -1 and int(st.get("pos2", -1)) != -1 and int(st.get("target1", -1)) != -1 and int(st.get("target2", -1)) != -1

func _replay_trim_to_sliding_window(segs: PackedStringArray) -> PackedStringArray:
	while segs.size() > 2:
		segs.remove_at(0)
	return segs

func _replay_build_after_my_fire(my_pos_int: int, my_target_int: int) -> String:
	var segs: PackedStringArray = PackedStringArray()
	if _last_replay_str != "":
		segs = _last_replay_str.split("|", false)

	var hp := _hp_as_p1_order()
	var myk := _my_replay_keys()

	if segs.size() == 0:
		segs.append("hp1:%d,hp2:%d,pos1:-1,pos2:-1,target1:-1,target2:-1" % [int(hp["hp1"]), int(hp["hp2"])])

	var last_i := segs.size() - 1
	var last_state := _parse_replay_state(segs[last_i])

	last_state["hp1"] = int(hp["hp1"])
	last_state["hp2"] = int(hp["hp2"])

	var my_target_missing := int(last_state.get(myk["target"], -1)) == -1

	if my_target_missing:
		last_state[myk["pos"]] = my_pos_int
		last_state[myk["target"]] = my_target_int
		segs[last_i] = _state_to_replay_string(last_state)
		return "|".join(_replay_trim_to_sliding_window(segs))

	var next_state := last_state.duplicate(true)
	next_state["hp1"] = int(hp["hp1"])
	next_state["hp2"] = int(hp["hp2"])
	next_state["target1"] = -1
	next_state["target2"] = -1

	next_state[myk["pos"]] = my_pos_int
	next_state[myk["target"]] = my_target_int

	segs.append(_state_to_replay_string(next_state))
	segs = _replay_trim_to_sliding_window(segs)
	return "|".join(segs)

func _process(delta: float) -> void:
	if not _is_shot_sequence_running:
		return
	if not is_instance_valid(fp_aim_sprite):
		return
	if not is_instance_valid(cam):
		return

	_aim_gun_sprite_at_world_point(
		cam,
		fp_aim_sprite,
		_aim_target_world,
		delta,
		6.0,
		12.0,
		28.0,
		10.0
	)

func _aim_gun_sprite_at_world_point(
	camera: Camera3D,
	sprite: Sprite2D,
	target_world: Vector3,
	delta: float,
	max_rot_deg: float = 6.0,
	rot_lerp_speed: float = 10.0,
	max_pos_px: float = 24.0,
	pos_lerp_speed: float = 10.0
) -> void:
	var viewport := camera.get_viewport()
	if viewport == null:
		return
	if sprite.texture == null:
		return

	var target_screen := camera.unproject_position(target_world)

	var tex_size := sprite.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return

	var drawn_size := Vector2(tex_size.x * sprite.scale.x, tex_size.y * sprite.scale.y)
	var sx := drawn_size.x / tex_size.x
	var sy := drawn_size.y / tex_size.y

	var tex_px_to_screen := func(tex_px: Vector2) -> Vector2:
		var local := Vector2(tex_px.x * sx, tex_px.y * sy)
		if sprite.centered:
			local -= drawn_size * 0.5
		return sprite.global_position + local.rotated(sprite.global_rotation)

	var rear_tex_px := Vector2(570.0, 470.0)
	var muzzle_tex_px := _muzzle_tex_px
	var rear_screen: Vector2 = tex_px_to_screen.call(rear_tex_px)
	var muzzle_screen: Vector2 = tex_px_to_screen.call(muzzle_tex_px)
	var cur_dir := (muzzle_screen - rear_screen)
	var des_dir := (target_screen - rear_screen)

	if cur_dir.length_squared() < 0.00001 or des_dir.length_squared() < 0.00001:
		return

	var cur_ang := cur_dir.angle()
	var des_ang := des_dir.angle()
	var delta_ang := wrapf(des_ang - cur_ang, -PI, PI)

	var max_step := deg_to_rad(max_rot_deg)
	delta_ang = clampf(delta_ang, -max_step, max_step)

	var target_rot := sprite.rotation + delta_ang
	sprite.rotation = lerp(sprite.rotation, target_rot, delta * rot_lerp_speed)

	var screen_center := viewport.get_visible_rect().size * 0.5
	var px_delta := target_screen - screen_center

	var nx: float = 0.0
	var ny: float = 0.0
	if screen_center.x > 0.0:
		nx = px_delta.x / screen_center.x
	if screen_center.y > 0.0:
		ny = px_delta.y / screen_center.y

	nx = clampf(nx, -1.0, 1.0)
	ny = clampf(ny, -1.0, 1.0)

	var target_pos := _fp_aim_base_pos + Vector2(nx * max_pos_px, ny * (max_pos_px * 0.6))
	sprite.position = sprite.position.lerp(target_pos, delta * pos_lerp_speed)

func _set_button_enabled(b: ActionButton3D, enabled: bool) -> void:
	var sprite := b.get_node("Sprite3D") as Sprite3D
	if not sprite:
		return

	if enabled:
		sprite.modulate = Color(1, 1, 1, 1)
	else:
		sprite.modulate = Color(0.5, 0.5, 0.5, 0.4)

func _update_move_buttons() -> void:
	print("Update move buttons: lane=", _player_lane)
	for b in _buttons:
		if b.kind == ActionButton3D.ButtonKind.MOVE:
			b.set_player_lane(_player_lane)

func _compute_zoom_target(camera: Camera3D, focus_world: Vector3) -> Transform3D:
	var start_xform := camera.global_transform
	var start_pos := start_xform.origin
	var to_focus := focus_world - start_pos
	var dist := maxf(to_focus.length(), 0.01)
	var target_dist := maxf(2.0, dist * 0.75)
	var forward := -start_xform.basis.z.normalized()
	var up := start_xform.basis.y.normalized()
	var target_pos := focus_world - forward * target_dist + up * 0.6
	var target_xform := start_xform

	target_xform.origin = target_pos

	return target_xform

func _parse_avatar_string(data_string: String) -> Dictionary:
	var hair_map: Array = AvatarThumbnail.avatar_hair_regions.keys()
	var body_map: Array = AvatarThumbnail.avatar_fshape_regions.keys()
	var eyes_map: Array = AvatarThumbnail.avatar_eyes_regions.keys()
	var mouth_map: Array = AvatarThumbnail.avatar_mouth_regions.keys()
	var clothing_map: Array = AvatarThumbnail.avatar_clothing_regions.keys()
	var backdrop_map: Array = ["Plain"]
	backdrop_map.append_array(AvatarThumbnail.avatar_background_regions.keys())

	var data: Dictionary = {
		"fshape_style": body_map[0] if body_map.size() > 0 else "Default",
		"hair_style": hair_map[0] if hair_map.size() > 0 else "hair1",
		"eyes_style": eyes_map[0] if eyes_map.size() > 0 else "eyes1",
		"mouth_style": mouth_map[0] if mouth_map.size() > 0 else "mouth1",
		"clothing_style": clothing_map[0] if clothing_map.size() > 0 else "clothing1",
		"bg_style": "Plain",
		"fshape_color": Color(0.88, 0.67, 0.41),
		"hair_color": Color(0.17, 0.14, 0.17),
		"clothing_color": Color(0.63, 0.24, 0.24),
		"bg_color": Color(0.31, 0.36, 0.54),
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

func send_game(clear_targets_for_next_turn: bool = false) -> void:
	if _is_replay_playback or _replay_auto_pending:
		print("[Send] Blocked: replay playback/autoplay pending. Not sending.")
		return

	print("[Send] send_game() called clear_targets_for_next_turn=", clear_targets_for_next_turn)
	await get_tree().process_frame

	var my_pos_int: int = _lane_to_enc(_player_lane)

	var my_target_int: int = -1
	if _selected_shoot != null and is_instance_valid(_selected_shoot):
		my_target_int = _lane_to_enc(_selected_shoot.lane)

	var out_replay := _replay_build_after_my_fire(my_pos_int, my_target_int)
	_last_replay_str = out_replay

	var payload: Dictionary = {
		"replay": out_replay
	}

	var out_parts := out_replay.split("|", false)
	print("[Send] REPLAY_OUT segs=", out_parts.size(), " last_seg=", out_parts[out_parts.size() - 1])

	game_ended = check_win()
	if game_ended:
		clear_targets_for_next_turn = true

		var winner: String = ""
		var winner_player: int = 0
		var opp_id: String = ""
		if my_id != "":
			if p1_id != "" and my_id == p1_id:
				opp_id = p2_id
			elif p2_id != "" and my_id == p2_id:
				opp_id = p1_id

		if win_loss_state == "1":
			winner = my_id
			winner_player = playernum
		elif win_loss_state == "-1":
			winner = opp_id
			winner_player = (2 if playernum == 1 else 1)
		else:
			winner = "0"
			winner_player = 0

		payload["winner"] = my_id + "|" + win_loss_state
		print("[Send] Game ended. my_id=", my_id, " winner=", winner, " winnerPlayer=", winner_player, " result=", win_loss_state)

	var avatar_key := ("avatar1" if playernum == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	print("[Send] PAYLOAD: ", payload)
	_dbg("SEND_GAME_BEFORE")

	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(JSON.stringify(payload))
	else:
		print("AppPlugin is null. Cannot send game data.")

	is_my_turn = false

	_show_fire_button(false)
	if is_instance_valid(fire_button):
		fire_button.visible = false

	_selected_shoot = null

	_set_all_buttons_clickable(false)

	if not game_over:
		play_sent_animation()

func on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return

	await _pop_button(rules_button)

	var popup := RULES_POPUP_SCENE.instantiate() as RulesPopup
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99

	popup.tree_exited.connect(func() -> void:
		if is_instance_valid(dim):
			dim.queue_free()
	)

	popup.open("How to Play Paintball", _get_rules_text())

func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Paintball[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
• Replace in Future
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• Replace in Future
[/font_size]

[font_size={24px}][b]End of Game[/b][/font_size]
[font_size={18px}]
• Replace in Future
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
	sent_tween.tween_callback(func() -> void:
		if is_instance_valid(sent_label):
			sent_label.text = "Sent ✔"
	)
	sent_tween.tween_interval(2.0)
	sent_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)

	sent_tween.tween_callback(func() -> void:
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0
			start_waiting_animation()
	)

func check_win() -> bool:
	print("--- CHECKING WIN CONDITION ---")

	if game_over:
		return true

	if _hp_me > 0 and _hp_opp > 0:
		return false

	game_over = true

	if _hp_me <= 0 and _hp_opp <= 0:
		win_loss_state = "0"
		if is_instance_valid(win_loss_label):
			win_loss_label.text = "DRAW!"
			win_loss_label.visible = true
		return true

	if _hp_opp <= 0:
		win_loss_state = "1"
		if is_instance_valid(win_loss_label):
			win_loss_label.text = ("Player 1 Wins!" if spectator_mode else "YOU WIN!")
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			win_loss_label.visible = true
		if is_instance_valid(player_avatar_display):
			_show_win_burst(player_avatar_display)
		return true

	win_loss_state = "-1"
	if is_instance_valid(win_loss_label):
		win_loss_label.text = ("Player 2 Wins!" if spectator_mode else "YOU LOSE")
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
		win_loss_label.visible = true
	if is_instance_valid(opp_avatar_display):
		_show_win_burst(opp_avatar_display)

	return true

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

	avatar.item_rect_changed.connect(func() -> void:
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

func start_waiting_animation() -> void:
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
	tween_wait_in.tween_callback(func() -> void:
		dot_timer.start()
	)

func stop_waiting_animation() -> void:
	if is_instance_valid(dot_timer):
		dot_timer.stop()
	if is_instance_valid(waiting_label):
		waiting_label.visible = false
		waiting_label.modulate.a = 1.0
	if is_instance_valid(waiting_blur):
		waiting_blur.visible = false
		waiting_blur.modulate.a = 1.0

func _on_dot_timer_timeout() -> void:
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

	await _pop_button(settings_button)

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

	var custom_settings_title := popup_instance.find_child("CustomSettingsTitleLabel", true)
	if custom_settings_title and custom_settings_title is Label and settings_popup_script.custom_settings_container.get_child_count() > 0:
		(custom_settings_title as Label).visible = true
	elif custom_settings_title and custom_settings_title is Label:
		(custom_settings_title as Label).visible = false

	settings_popup_script.closed.connect(func() -> void:
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
	)
	settings_popup_script.settings_theme_selected.connect(_on_theme_changed)

	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await get_tree().process_frame

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var desired_width: float = viewport_size.x * 0.95
	var desired_height: float = popup_instance.get_combined_minimum_size().y

	popup_instance.size = Vector2(desired_width, desired_height)
	popup_instance.position = Vector2((viewport_size.x - desired_width) / 2.0, viewport_size.y)

	var bottom_offset: float = 50.0
	var target_y_position: float = viewport_size.y - desired_height - bottom_offset
	var target_position: Vector2 = Vector2((viewport_size.x - desired_width) / 2.0, target_y_position)

	var popup_tween := create_tween()
	popup_tween.tween_property(popup_instance, "position", target_position, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	popup_instance.grab_focus()

func _on_theme_changed(_new_theme_name: String) -> void:
	pass

func _load_game_specific_settings() -> void:
	var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	print("Loaded game-specific settings for ", game_settings_category, ": volume=", saved_volume, " debug=", show_debug_info)

func _dbg(tag: String) -> void:
	print("[DBG][", tag, "] playernum=", playernum,
		" is_my_turn=", is_my_turn,
		" pending_enemy=", _pending_enemy_shot,
		" opp_pos_enc=", _opp_pos_enc,
		" opp_target_enc=", _opp_target_enc,
		" my_lane=", int(_player_lane),
		" my_selected=", (-1 if _selected_shoot == null else int(_selected_shoot.lane)),
		" segs=", _replay_segments.size(),
		" seg_i=", _replay_seg_index,
		" last_replay_len=", _last_replay_str.length()
	)
	if _last_replay_str != "":
		var parts := _last_replay_str.split("|", false)
		print("[DBG][", tag, "] last_replay_segs=", parts.size(), " last_seg=", parts[parts.size() - 1])

func _res_str(res: Dictionary, key: String, default_value: String = "") -> String:
	var v: Variant = res.get(key, default_value)
	if v is Array:
		var a: Array = v
		if a.size() > 0:
			return String(a[0])
	return String(v)

func _res_bool(res: Dictionary, key: String, default_value: bool = false) -> bool:
	var v: Variant = res.get(key, default_value)
	if v is Array:
		var a: Array = v
		if a.size() > 0:
			return bool(a[0])
	return bool(v)

func _res_int(res: Dictionary, key: String, default_value: int = 0) -> int:
	var v: Variant = res.get(key, default_value)
	if v is Array:
		var a: Array = v
		if a.size() > 0:
			return int(a[0])
	return int(v)

func _lane_to_enc(lane: ActionButton3D.Lane) -> int:
	match lane:
		ActionButton3D.Lane.LEFT:
			return 0
		ActionButton3D.Lane.CENTER:
			return 1
		ActionButton3D.Lane.RIGHT:
			return 2
		_:
			return 1

func _enc_to_lane(enc: int) -> ActionButton3D.Lane:
	match enc:
		0:
			return ActionButton3D.Lane.LEFT
		1:
			return ActionButton3D.Lane.CENTER
		2:
			return ActionButton3D.Lane.RIGHT
		_:
			return ActionButton3D.Lane.CENTER

func _flip_enc_for_perspective(enc: int) -> int:
	if enc == 0:
		return 2
	if enc == 2:
		return 0
	return enc

func _index_buttons() -> void:
	_move_btn_by_lane.clear()
	_shoot_btn_by_lane.clear()

	for b in _buttons:
		if not is_instance_valid(b):
			continue
		if b.kind == ActionButton3D.ButtonKind.MOVE:
			_move_btn_by_lane[b.lane] = b
		elif b.kind == ActionButton3D.ButtonKind.SHOOT:
			_shoot_btn_by_lane[b.lane] = b

func _set_all_buttons_clickable(enabled: bool) -> void:
	for b in _buttons:
		if not is_instance_valid(b):
			continue
		b.set_click_enabled(enabled)
		_set_button_enabled(b, enabled)

func _pop_button(btn: Control) -> void:
	btn.pivot_offset = btn.size / 2.0
	var tween := create_tween()
	tween.tween_property(btn, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
