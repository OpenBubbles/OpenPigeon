extends BaseGame3D
class_name ArcheryGame

const MUSIC_STREAM := preload("res://global/audio/archery.ogg")

@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var winner_label: Label = %WinLossLabel
@onready var sent_label: Label = %SentLabel
@onready var main_overlay: Control = %MainOverlay
@onready var spectator_label: Label = %SpecLabel
@onready var you_label: Label = %YouLabel
@onready var opp_label: Label = %OppLabel
@onready var set_label: RichTextLabel = %SetLabel
@onready var score_label: RichTextLabel = %SetScoreLabel
@onready var player_wins: PanelContainer = %PlayerSetWins
@onready var opp_wins: PanelContainer = %OppSetWins
@onready var player_set_win_label: Label = %PlayerSetWinCount
@onready var opp_set_win_label: Label = %OppSetWinCount
@onready var wind_label: RichTextLabel = %WindLabel
@onready var wind_arrow: WindArrow = %WindArrow
@onready var wind_arrow_circle: TextureRect = %WindArrowCircle
@onready var wind_panel_container: PanelContainer = %WindPanel
@onready var top_game_bar: HBoxContainer = %TopGameBar
@onready var score_box: Control = %ScoreBox
@onready var distance_label: Label3D = %distancemarkerlabel

var _score_box_orig_min_size: Vector2 = Vector2.ZERO
var _score_box_inited: bool = false
var _should_play_replay: bool = true

var _top_bar_inited: bool = false

@onready var aim_cursor: Sprite2D = %AimCursor
@onready var aim_progress_bar: TextureProgressBar = aim_cursor.get_node("TextureProgressBar")

@export var sensitivity: float = 4.9
@export var damping_factor: float = 0.4
@export var max_speed: float = 1000.0

@export var target: Target
@export var arrow: Arrow
@export var camera: Camera3D

var num: int
var isTurn: bool
var player: int
var gseed: int
var upped_set = false
var replay: Dictionary = {}
const MAX_WIND_POWER: float = 5.0   # used for color scaling
const BOARD_RADIUS: float = 0.75
const RING_COUNT: float = 10.0
const RING_SPACING: float = BOARD_RADIUS / RING_COUNT
var wind_anim_time: float = 0.0     # for the stretching arrow animation
var wind_pulse_amount: float = 0.01
var has_turn_pre_state: bool = false
var turn_pre_state: Array[int] = []
var sent_tween: Tween
var game_over: bool = false

var num_shots: int = 0
var aim_tween: Tween = null
var aim_zoom_tween: Tween = null
var bow_fully_drawn: bool = false
var shots: Array[Arrow] = []
var moves: Array[Vector3] = []
var current_arrow: Arrow = null
var played_replay: bool = false
var replay_in_progress: bool = false
var last_replay_raw: String = ""
var set_award_in_progress: bool = false
var send_winner: String = ""
var local_index: int = 1

var current_wind_angle: Vector2
var current_wind_power: float

const CAMERA_DEFAULT_POS := Vector3(0.0, 1.718, 1.616)
const CAMERA_DEFAULT_FOV := 50.0

const CAMERA_FOLLOW_DISTANCE_Z := 3.5	 # how close to the board when following
const CAMERA_FOLLOW_Y_OFFSET := 0.5	 # how far above board center
const CAMERA_LOOK_AT_Y_OFFSET := 0.55	# how far below bullseye to look
const CAMERA_FOLLOW_FOV := 50.0		 # zoom amount for close-up
const CAMERA_FOLLOW_LERP_TIME := 0.7	 # tween time into the close-up

const LOG_TAG := "Archery"
const DEBUG_ARCHERY := false

func dbg(parts: Variant) -> void:
	if DEBUG_ARCHERY:
		OpLog.d(LOG_TAG, parts)

func _score_summary() -> String:
	return "set=%d shots=%d you=%d opp=%d youSets=%d oppSets=%d gameOver=%s winner=%s" % [
		set_num,
		num_shots,
		you_score,
		opp_score,
		you_set_wins,
		opp_set_wins,
		str(game_over),
		send_winner
	]

func _replay_summary_dict(data: Dictionary) -> String:
	var move_count := 0
	var has_pre := data.has("pre_state")
	var has_post := data.has("post_state")

	if data.has("moves") and data["moves"] is Array:
		move_count = data["moves"].size()

	return "moves=%d pre=%s post=%s" % [move_count, str(has_pre), str(has_post)]

var set_num: int = 1          # current set (1–3)
var you_score: int = 0        # per-set score (you)
var opp_score: int = 0        # per-set score (opponent)
var you_set_wins: int = 0     # total sets won (you)
var opp_set_wins: int = 0     # total sets won (opponent)

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
func _get_dev_data() -> String:
	return '{ "isYourTurn": true, "player": "1", "replay": "state:1,18,0,0,0|move:1,0.059418,1.351113,-14.397592|move:1,-0.077269,1.397037,-14.397591|move:1,-0.020799,1.492665,-14.397592|state:1,29,18,0,1", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,0|mouth,0|acc,0|wins,0|bg_color,0.900000,0.900000,0.900000|body_color,0.000000,1.000000,0.000000|glasses,0|stache,0|backdrop,0|hair,3|clothes,2|hair_color,0.431373,0.254902,0.121569|clothes_color,0.438450,0.340784,0.366469", "player1": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player2": "", "id": "6gt6WvSteSKHYrKr", "ios": "16.3.1", "num": "3", "game": "archery", "seed": "247149971", "tver": "5", "build": "d4yGowcTuIW9i", "version": "0" }'

func _update_set_score_labels() -> void:
	score_label.text = "[center]%d - %d[/center]" % [you_score, opp_score]

	player_set_win_label.text = str(you_set_wins)
	if you_set_wins > 0:
		player_wins.visible = true
		you_label.visible = false
	else:
		player_wins.visible = false
		you_label.visible = true

	opp_set_win_label.text = str(opp_set_wins)
	if opp_set_wins > 0:
		opp_wins.visible = true
		opp_label.visible = false
	else:
		opp_wins.visible = false
		opp_label.visible = true

func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	if is_instance_valid(aim_cursor):
		aim_cursor.visible = false
	if is_instance_valid(aim_progress_bar):
		aim_progress_bar.visible = false
		aim_progress_bar.value = 0.0
	if is_instance_valid(wind_arrow):
		wind_arrow.pivot_offset = wind_arrow.size / 2.0
		wind_arrow.scale = Vector2.ONE
	if is_instance_valid(wind_arrow_circle) and wind_arrow_circle is Control:
		wind_arrow_circle.pivot_offset = wind_arrow_circle.size / 2.0
	if is_instance_valid(top_game_bar):
		top_game_bar.modulate.a = 1.0
		_top_bar_inited = true
	if is_instance_valid(wind_panel_container):
		wind_panel_container.pivot_offset = wind_panel_container.size / 2.0
		wind_panel_container.visible = false
		wind_panel_container.modulate.a = 1.0
	if is_instance_valid(score_box):
		_score_box_inited = true
		_score_box_orig_min_size = score_box.custom_minimum_size
		if _score_box_orig_min_size == Vector2.ZERO:
			_score_box_orig_min_size = score_box.get_combined_minimum_size()
		score_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_instance_valid(camera):
		camera.position = CAMERA_DEFAULT_POS
		camera.fov = CAMERA_DEFAULT_FOV
		var center := _get_bullseye_center_world()
		camera.look_at(center - Vector3(0.0, CAMERA_LOOK_AT_Y_OFFSET, 0.0), Vector3.UP)

	update_distance()
	
	OpLog.i(LOG_TAG, [
		"game_ready localMode=", appPlugin == null,
		" camera=", is_instance_valid(camera),
		" target=", is_instance_valid(target),
		" arrow=", is_instance_valid(arrow),
		" ", _score_summary()
	])

func check_winner(completed_round: int = set_num) -> bool:
	OpLog.i(LOG_TAG, ["check_winner round=", completed_round, " ", _score_summary()])

	# Early clinch only after round 2 or later.
	if completed_round >= 2:
		if you_set_wins == 2 and opp_set_wins == 0:
			game_over = true
			stop_waiting_animation()
			_hide_wind_panel(0.0)
			if not spectator_mode:
				winner_label.text = "YOU WIN!"
			else:
				winner_label.text = "Player 1 Wins!"
			winner_label.visible = true
			winner_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
			if is_instance_valid(player_avatar_display):
				GameUtils._show_win_burst(player_avatar_display)
			send_winner = my_uuid + "|1"
			OpLog.i(LOG_TAG, ["game_end early=true result=win round=", completed_round, " ", _score_summary()])
			return true

		if opp_set_wins == 2 and you_set_wins == 0:
			game_over = true
			stop_waiting_animation()
			_hide_wind_panel(0.0)
			if not spectator_mode:
				winner_label.text = "YOU LOSE"
				winner_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
			else:
				winner_label.text = "Player 2 Wins"
				winner_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
			winner_label.visible = true
			if is_instance_valid(opp_avatar_display):
				GameUtils._show_win_burst(opp_avatar_display)
			send_winner = my_uuid + "|-1"
			OpLog.i(LOG_TAG, ["game_end early=true result=lose round=", completed_round, " ", _score_summary()])
			return true

	# No final winner unless round 3 has actually completed.
	if completed_round < 3:
		dbg(["check_winner no_result_yet round=", completed_round, " ", _score_summary()])
		return false

	game_over = true
	stop_waiting_animation()
	_hide_wind_panel(0.0)

	if you_set_wins == opp_set_wins:
		winner_label.text = "DRAW"
		winner_label.visible = true
		winner_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		if is_instance_valid(player_avatar_display):
			GameUtils._show_win_burst(player_avatar_display)
		if is_instance_valid(opp_avatar_display):
			GameUtils._show_win_burst(opp_avatar_display)
		send_winner = my_uuid + "|0"
		OpLog.i(LOG_TAG, ["game_end result=draw round=", completed_round, " ", _score_summary()])
		return true
	elif you_set_wins > opp_set_wins:
		if not spectator_mode:
			winner_label.text = "YOU WIN!"
		else:
			winner_label.text = "Player 1 Wins!"
		winner_label.visible = true
		winner_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		if is_instance_valid(player_avatar_display):
			GameUtils._show_win_burst(player_avatar_display)
		send_winner = my_uuid + "|1"
		OpLog.i(LOG_TAG, ["game_end result=win round=", completed_round, " ", _score_summary()])
		return true
	else:
		if not spectator_mode:
			winner_label.text = "YOU LOSE"
			winner_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		else:
			winner_label.text = "Player 2 Wins"
			winner_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		winner_label.visible = true
		if is_instance_valid(opp_avatar_display):
			GameUtils._show_win_burst(opp_avatar_display)
		send_winner = my_uuid + "|-1"
		OpLog.i(LOG_TAG, ["game_end result=lose round=", completed_round, " ", _score_summary()])
		return true
		
func _process_game_state() -> void:
	if game_over:
		OpLog.i(LOG_TAG, ["process_state skipped game_over=true ", _score_summary()])
		stop_waiting_animation()
		_hide_wind_panel(0.0)
		return
		
	OpLog.i(LOG_TAG, [
		"process_state_start turn=", isTurn,
		" spectator=", spectator_mode,
		" replayEmpty=", replay.is_empty(),
		" playedReplay=", played_replay,
		" shouldPlayReplay=", _should_play_replay,
		" replayProgress=", replay_in_progress,
		" ", _score_summary()
	])

	stop_waiting_animation()
	_hide_wind_panel(0.0)

	if replay_in_progress:
		OpLog.w(LOG_TAG, ["process_state skipped replay already in progress ", _score_summary()])
		return

	if not replay.is_empty() and not played_replay and _should_play_replay:
		OpLog.i(LOG_TAG, ["process_state play_replay ", _replay_summary_dict(replay), " ", _score_summary()])
		replay_in_progress = true
		played_replay = true
		await play_replay()
	else:
		if not replay.is_empty() and not played_replay:
			OpLog.i(LOG_TAG, ["process_state skip_own_replay ", _replay_summary_dict(replay), " localIndex=", local_index])

	if (not isTurn or spectator_mode) and not game_over:
		OpLog.i(LOG_TAG, ["process_state waiting turn=", isTurn, " spectator=", spectator_mode, " gameOver=", game_over])
		start_waiting_animation()
		return

	stop_waiting_animation()

	if num_shots < 3:
		OpLog.i(LOG_TAG, ["prepare_shot index=", num_shots, " set=", set_num, " ", _score_summary()])

		if num_shots == 0 and not spectator_mode and not game_over and not has_turn_pre_state:
			var p1_sets := (you_set_wins if player == 1 else opp_set_wins)
			var p2_sets := (you_set_wins if player == 2 else opp_set_wins)

			var p1_score: int
			var p2_score: int
			if player == 1:
				p1_score = you_score
				p2_score = opp_score
			else:
				p1_score = opp_score
				p2_score = you_score

			turn_pre_state = [set_num, p1_score, p2_score, p1_sets, p2_sets]
			has_turn_pre_state = true
			OpLog.i(LOG_TAG, ["captured_turn_pre_state=", turn_pre_state])

		calc_wind()
		current_arrow = arrow.spawn()
		if not spectator_mode and not game_over:
			_show_wind_panel(target.global_position)
	else:
		OpLog.i(LOG_TAG, ["local_set_finished award_points ", _score_summary()])
		await _animate_set_bar_and_award_points()

func _award_set_points_and_continue(completed_round: int = set_num) -> bool:
	OpLog.i(LOG_TAG, ["award_set_points round=", completed_round, " ", _score_summary()])
	var won_now: bool = check_winner(completed_round)
	var out_json := export_replay()
	OpLog.event(LOG_TAG, ["send_game_out award_set raw=", out_json])
	send_game_data(out_json)
	return won_now
	
func _send_turn_state_only() -> void:
	var out_json := export_replay()
	OpLog.event(LOG_TAG, ["send_game_out state_only raw=", out_json])
	send_game_data(out_json)
		
func _spawn_avatar_score_popup(is_you: bool, amount: int, is_miss: bool = false) -> void:
	var avatar: Control = player_avatar_display if is_you else opp_avatar_display
	if not is_instance_valid(avatar):
		return

	var parent_control: Control = main_overlay if is_instance_valid(main_overlay) else avatar

	var popup := Label.new()
	if is_miss:
		popup.text = "MISS!"
	else:
		popup.text = "+%d" % amount

	popup.scale = Vector2(1.5, 1.5)

	var gold := Color(1.0, 0.84, 0.0)
	popup.modulate = gold
	popup.add_theme_color_override("font_color", gold)
	popup.add_theme_color_override("font_outline_color", Color.BLACK)
	popup.add_theme_constant_override("outline_size", 3)

	parent_control.add_child(popup)

	if parent_control == main_overlay:
		var rect := avatar.get_global_rect()
		var top_center := rect.position + Vector2(rect.size.x * 0.5, 0.0)
		var local_pos: Vector2 = top_center - parent_control.global_position
		popup.position = local_pos + Vector2(0.0, -10.0)
	else:
		popup.set_anchors_preset(Control.PRESET_CENTER_TOP)
		popup.position = Vector2(0.0, -10.0)

	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var start_pos := popup.position
	var end_pos := start_pos + Vector2(0.0, -40.0)
	t.tween_property(popup, "position", end_pos, 0.8)
	t.parallel().tween_property(popup, "modulate:a", 0.0, 0.8)
	t.tween_callback(func():
		if is_instance_valid(popup):
			popup.queue_free()
	)

func _project_to_plane(screen_pos: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_normal: Vector3 = camera.project_ray_normal(screen_pos)
	
	if abs(ray_normal.z) < 0.0001:
		OpLog.e(LOG_TAG, ["project_to_plane ray_parallel screenPos=", screen_pos])
		return Vector3.ZERO
	
	var t := ((target.position.z) - ray_origin.z) / ray_normal.z
	return ray_origin + ray_normal * t

const BULLSEYE_Z_OFFSET: float = 0.03541
const BULLSEYE_Y_OFFSET: float = 0
const REMOTE_Y_FUDGE: float = 0.02

func _get_ring_center_radius(score: int) -> float:
	if score >= 10:
		return 0.0
	if score == 9:
		return 1.5 * RING_SPACING

	var ring_number := float(10 - score)
	return 1.0625 * ring_number * RING_SPACING

func _get_bullseye_center_world() -> Vector3:
	if is_instance_valid(target):
		var center: Vector3 = target.global_transform.origin
		center.z += BULLSEYE_Z_OFFSET
		center.y += BULLSEYE_Y_OFFSET
		return center

	var base_z: float = -14.39759
	return Vector3(0.0, 1.718 + BULLSEYE_Y_OFFSET, base_z + BULLSEYE_Z_OFFSET)

func export_replay() -> String:
	var pre_state: Array[int] = []
	var set_index_for_turn: int

	if has_turn_pre_state:
		pre_state = turn_pre_state.duplicate()
		if pre_state.size() < 5:
			pre_state.resize(5)
		set_index_for_turn = pre_state[0]
		dbg(["export_replay pre_state=turn_pre_state ", pre_state])
	elif not replay.is_empty() and replay.has("post_state"):
		pre_state = replay["post_state"]
		if pre_state.size() < 5:
			pre_state.resize(5)
		set_index_for_turn = pre_state[0]
		dbg(["export_replay pre_state=replay_post_state ", pre_state])
	else:
		var p1_sets := (you_set_wins if player == 1 else opp_set_wins)
		var p2_sets := (you_set_wins if player == 2 else opp_set_wins)
		set_index_for_turn = set_num
		pre_state = [set_index_for_turn, 0, 0, p1_sets, p2_sets]
		dbg(["export_replay pre_state=default ", pre_state])

	while pre_state.size() < 5:
		pre_state.append(0)

	var replay_str: String = "state:%d,%d,%d,%d,%d|" % [
		set_index_for_turn,
		pre_state[1],
		pre_state[2],
		pre_state[3],
		pre_state[4]
	]

	for pos in moves:
		var wire_pos := pos
		wire_pos.y += REMOTE_Y_FUDGE

		replay_str += str(
			"move:1,",
			"%0.6f" % wire_pos.x, ",",
			"%0.6f" % wire_pos.y, ",",
			"%0.6f" % wire_pos.z,
			"|"
		)

	var p1_score: int = you_score if player == 1 else opp_score
	var p2_score: int = you_score if player == 2 else opp_score
	var p1_set_score: int = you_set_wins if player == 1 else opp_set_wins
	var p2_set_score: int = you_set_wins if player == 2 else opp_set_wins

	replay_str += "state:%d,%d,%d,%d,%d" % [
		set_index_for_turn,
		p1_score,
		p2_score,
		p1_set_score,
		p2_set_score
	]

	var replay_dict: Dictionary = {"replay": replay_str}
	var avatar_key := ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		replay_dict[avatar_key] = player_avatar_display.get_avatar_data_string()
	if send_winner.is_empty() == false:
		OpLog.i(LOG_TAG, ["export_replay adding_winner=", send_winner])
		replay_dict["winner"] = send_winner
	else:
		play_sent_animation()
	var out_json := JSON.stringify(replay_dict)
	OpLog.event(LOG_TAG, [
		"export_replay_out moves=", moves.size(),
		" preState=", pre_state,
		" winner=", send_winner,
		" replayLen=", replay_str.length(),
		" ", _score_summary(),
		" raw=", out_json
	])
	return out_json
	return JSON.stringify(replay_dict)

func _animate_set_win_bump(is_you: bool) -> void:
	var panel: PanelContainer = player_wins if is_you else opp_wins
	if not is_instance_valid(panel):
		return

	var start_scale: Vector2 = panel.scale
	panel.pivot_offset = panel.size / 2.0

	var t := create_tween()
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "scale", start_scale * 1.25, 0.18)
	t.tween_property(panel, "scale", start_scale, 0.18)
	
func _animate_set_bar_and_award_points(from_replay: bool = false) -> void:
	if set_award_in_progress:
		OpLog.w(LOG_TAG, ["award_set skipped already_in_progress fromReplay=", from_replay])
		return
	set_award_in_progress = true
	_hide_wind_panel(0.0)
	OpLog.i(LOG_TAG, ["award_set_start fromReplay=", from_replay, " num=", num, " ", _score_summary()])

	if not _top_bar_inited \
		or not is_instance_valid(top_game_bar) \
		or not _score_box_inited \
		or not is_instance_valid(score_box) \
		or not is_instance_valid(score_label):
		OpLog.w(LOG_TAG, "award_set missing top bar / score box / score label")
		if not from_replay:
			_award_set_points_and_continue()
		set_award_in_progress = false
		return

	var is_second_shooter: bool = from_replay or (num % 2 == 0)

	var start_global: Vector2 = top_game_bar.get_global_position()
	var start_min_size: Vector2 = score_box.custom_minimum_size
	if start_min_size == Vector2.ZERO:
		start_min_size = _score_box_orig_min_size
	var was_top_level: bool = top_game_bar.is_set_as_top_level()

	top_game_bar.set_as_top_level(true)
	top_game_bar.global_position = start_global

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var bar_size: Vector2 = top_game_bar.size
	if bar_size == Vector2.ZERO:
		bar_size = top_game_bar.get_combined_minimum_size()

	var target_global: Vector2 = viewport_size * 0.5 - bar_size * 0.5

	var grow_factor: float = 1.25
	var target_min_size: Vector2 = _score_box_orig_min_size * grow_factor

	dbg(["award_set topbar start=", start_global, " target=", target_global])

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(top_game_bar, "global_position", target_global, 0.5)
	tween.parallel().tween_property(score_box, "custom_minimum_size", target_min_size, 0.5)
	await tween.finished
	dbg("award_set center_tween_done")

	await get_tree().create_timer(1).timeout

	if not is_second_shooter:
		OpLog.i(LOG_TAG, ["award_set mid_set send_state_only ", _score_summary()])

		_send_turn_state_only()

		var tween_back_mid := create_tween()
		tween_back_mid.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween_back_mid.tween_property(top_game_bar, "global_position", start_global, 0.5)
		tween_back_mid.parallel().tween_property(score_box, "custom_minimum_size", start_min_size, 0.5)
		await tween_back_mid.finished

		top_game_bar.set_as_top_level(was_top_level)

		OpLog.i(LOG_TAG, ["award_set_done mid_set ", _score_summary()])
		set_award_in_progress = false
		return

	var start_you: int = you_score
	var start_opp: int = opp_score
	OpLog.i(LOG_TAG, ["award_set end_of_set startYou=", start_you, " startOpp=", start_opp])

	if opp_score > you_score:
		opp_set_wins += 1
		OpLog.i(LOG_TAG, ["set_result opponent_wins ", _score_summary()])
		_update_set_score_labels()
		_animate_set_win_bump(false)
		_spawn_avatar_score_popup(false, 1)
	elif you_score > opp_score:
		you_set_wins += 1
		OpLog.i(LOG_TAG, ["set_result you_win ", _score_summary()])
		_update_set_score_labels()
		_animate_set_win_bump(true)
		_spawn_avatar_score_popup(true, 1)
	else:
		opp_set_wins += 1
		you_set_wins += 1
		OpLog.i(LOG_TAG, ["set_result tie ", _score_summary()])
		_update_set_score_labels()
		_animate_set_win_bump(true)
		_animate_set_win_bump(false)
		_spawn_avatar_score_popup(true, 1)
		_spawn_avatar_score_popup(false, 1)
	
	
	var completed_round: int = set_num
	var match_over_now: bool = false

	if not from_replay:
		OpLog.i(LOG_TAG, ["award_set sending_full_set ", _score_summary()])
		match_over_now = _award_set_points_and_continue(completed_round)
	else:
		match_over_now = check_winner(completed_round)

	# If the match just ended, keep the final round score visible.
	if match_over_now:
		OpLog.i(LOG_TAG, ["award_set match_over preserve_score ", _score_summary()])
	else:
		if set_num < 3:
			update_set_number(set_num + 1)
			update_distance()

		if start_you != 0 or start_opp != 0:
			dbg(["award_set score_tween from=", Vector2i(start_you, start_opp), " to=0,0"])
			var score_tween := create_tween()
			score_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

			var update_score := func(t: float) -> void:
				var y_val: int = int(round(lerp(float(start_you), 0.0, t)))
				var o_val: int = int(round(lerp(float(start_opp), 0.0, t)))
				you_score = y_val
				opp_score = o_val
				_update_set_score_labels()

			score_tween.tween_method(update_score, 0.0, 1.0, 0.7)
			await score_tween.finished
			dbg("award_set score_tween_done")

		you_score = 0
		opp_score = 0
		_update_set_score_labels()
		OpLog.i(LOG_TAG, ["set_scores_reset ", _score_summary()])

	await get_tree().create_timer(0.4).timeout

	var tween_back := create_tween()
	tween_back.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween_back.tween_property(top_game_bar, "global_position", start_global, 0.5)
	tween_back.parallel().tween_property(score_box, "custom_minimum_size", start_min_size, 0.5)
	await tween_back.finished

	top_game_bar.set_as_top_level(was_top_level)

	OpLog.i(LOG_TAG, ["award_set_done full_set ", _score_summary()])
	set_award_in_progress = false

func _hide_wind_panel(duration: float = 0.2) -> void:
	if not is_instance_valid(wind_panel_container):
		return

	if duration <= 0.0:
		wind_panel_container.visible = false
		wind_panel_container.modulate.a = 1.0
		return

	var t := create_tween()
	t.tween_property(wind_panel_container, "modulate:a", 0.0, duration)
	t.tween_callback(func():
		if is_instance_valid(wind_panel_container):
			wind_panel_container.visible = false
			wind_panel_container.modulate.a = 1.0
	)

func _show_wind_panel(world_pos: Vector3) -> void:
	if not is_instance_valid(wind_panel_container) or not is_instance_valid(camera):
		return

	var target_2d_pos: Vector2 = camera.unproject_position(world_pos)
	var offset: Vector2 = Vector2(-75.0, -130.0) \
		if is_equal_approx(world_pos.z, -14.4329) \
		else Vector2(-75.0, -110.0)

	wind_panel_container.position = target_2d_pos + offset
	wind_panel_container.visible = true
	wind_panel_container.modulate.a = 0.0

	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(wind_panel_container, "modulate:a", 1.0, 0.25)

func _fade_top_bar(fshow: bool) -> void:
	if not is_instance_valid(top_game_bar):
		return

	var target_alpha: float = 1.0 if fshow else 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(top_game_bar, "modulate:a", target_alpha, 0.5)
	
func calc_wind() -> void:
	var rng := RandomNumberGenerator.new()

	var derived_seed: int = int(gseed) \
		+ int(set_num) * 1009 \
		+ int(num_shots) * 7919
	rng.seed = derived_seed

	dbg(["calc_wind set=", set_num, " shot=", num_shots, " seed=", derived_seed])

	var angle: float = rng.randf_range(0.0, 360.0)

	var power: float
	match set_num:
		1:
			if num_shots == 0:
				power = rng.randf_range(0.5, 0.8)
			elif num_shots == 1:
				power = rng.randf_range(1.0, 1.5)
			else:
				power = rng.randf_range(1.5, 3.0)
		2:
			power = rng.randf_range(1.5, 3.0)
		3:
			power = rng.randf_range(2.0, 4.0)
		_:
			power = rng.randf_range(0.5, 3.0)
	current_wind_angle = Vector2.UP.rotated(deg_to_rad(angle))
	current_wind_power = power
	
	OpLog.i(LOG_TAG, [
		"wind set=", set_num,
		" shot=", num_shots,
		" seed=", derived_seed,
		" angleDeg=", angle,
		" vec=", current_wind_angle,
		" power=", power
	])

	_update_wind_ui(angle, power)

func _update_wind_ui(angle_degrees: float, power: float) -> void:
	dbg(["update_wind_ui angle=", angle_degrees, " power=", power])
	var t: float = clamp(power / MAX_WIND_POWER, 0.0, 1.0)

	var green: Color = Color(0.792, 0.792, 0.792, 1.0)
	var yellow: Color = Color(1.0, 0.9, 0.1)
	var red: Color = Color(0.95, 0.1, 0.1)

	var color: Color
	if t < 0.5:
		color = green.lerp(yellow, t * 2.0)
	else:
		color = yellow.lerp(red, (t - 0.5) * 2.0)

	dbg(["update_wind_ui currentWind=", current_wind_angle])

	if is_instance_valid(wind_label):
		var hex: String = color.to_html(false)
		wind_label.bbcode_enabled = true
		wind_label.text = "[center][b]WIND: [color=#%s]%.1f[/color][/b][/center]" % [hex, power]

	if is_instance_valid(wind_arrow_circle):
		wind_arrow_circle.modulate = color

	if is_instance_valid(wind_arrow):

		var display_angle_deg: float
		if current_wind_angle.length() > 0.0001:
			var godot_angle_deg: float = rad_to_deg(current_wind_angle.angle())
			display_angle_deg = godot_angle_deg
		else:
			display_angle_deg = angle_degrees

		wind_arrow.set_arrow(display_angle_deg, t, color)

func update_set_number(uset_num: int) -> void:
	set_num = uset_num
	
	if uset_num == 1:
		target.position.z = -14.39759
	elif uset_num == 2:
		target.position.z = -20.39759
	elif uset_num == 3:
		target.position.z = -26.39759
	
	if is_instance_valid(set_label):
		set_label.text = "[center]Set " + str(uset_num) + "[/center]"
	
	OpLog.i(LOG_TAG, ["set_number=", set_num, " targetZ=", target.position.z if is_instance_valid(target) else 0.0])
	
func _reconcile_scores_with_post_state() -> void:
	if not replay.has("post_state"):
		dbg("reconcile_scores skipped no post_state")
		return

	var post: Array[int] = replay["post_state"]

	var p1_score_final: int = post[1]
	var p2_score_final: int = post[2]

	var target_you: int
	var target_opp: int

	if spectator_mode:
		target_you = p1_score_final
		target_opp = p2_score_final
	else:
		if local_index == 1:
			target_you = p1_score_final
			target_opp = p2_score_final
		else:
			target_you = p2_score_final
			target_opp = p1_score_final

	if you_score == target_you and opp_score == target_opp:
		dbg(["reconcile_scores already_match ", _score_summary()])
		return

	OpLog.i(LOG_TAG, [
		"reconcile_scores current=", Vector2i(you_score, opp_score),
		" target=", Vector2i(target_you, target_opp),
		" spectator=", spectator_mode,
		" localIndex=", local_index
	])

	var start_you: int = you_score
	var start_opp: int = opp_score

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(t: float) -> void:
			you_score = int(round(lerp(float(start_you), float(target_you), t)))
			opp_score = int(round(lerp(float(start_opp), float(target_opp), t)))
			_update_set_score_labels()
	,
		0.0,
		1.0,
		0.5
	)
	await tween.finished

func play_replay() -> void:
	if not replay_in_progress:
		OpLog.w(LOG_TAG, "play_replay skipped: replay_in_progress=false")
		return
	_hide_wind_panel(0.0)
	update_distance()
	_update_set_score_labels()
	OpLog.i(LOG_TAG, ["play_replay_start ", _replay_summary_dict(replay), " ", _score_summary()])

	var replay_arrows: Array[Arrow] = []
	if replay.has("moves"):
		var moves_arr: Array = replay["moves"]

		if moves_arr.size() > 0:
			var first_move = moves_arr[0]
			if first_move.size() >= 4:
				cam_follow_dart()

		for i in range(moves_arr.size()):
			var move = moves_arr[i]
			if move.size() < 4:
				continue

			var replay_pos := Vector3(move[1], move[2] - REMOTE_Y_FUDGE, move[3])

			OpLog.i(LOG_TAG, ["play_replay_move index=", i, " raw=", move, " adjustedPos=", replay_pos])

			replay_arrows.append(arrow.spawn())
			var this_arrow: Arrow = replay_arrows[-1]

			this_arrow.shoot(replay_pos, func() -> void:
				var arrow_score: int = target.calc_score(this_arrow)
				OpLog.i(LOG_TAG, ["play_replay_score score=", arrow_score, " oppBefore=", opp_score])

				var hit_pos: Vector3 = this_arrow.global_transform.origin
				_spawn_score_popup(hit_pos, arrow_score, _get_score_color(arrow_score))

				if arrow_score > 0:
					add_score(arrow_score, false)
			)
			await get_tree().create_timer(2.0).timeout
	else:
		OpLog.w(LOG_TAG, ["play_replay no_moves ", _replay_summary_dict(replay)])

	await cam_reset_pos()
	
	for arrow_i in replay_arrows:
		if is_instance_valid(arrow_i):
			arrow_i.queue_free()
	replay_arrows.clear()

	OpLog.i(LOG_TAG, ["play_replay_before_reconcile ", _score_summary()])

	await _reconcile_scores_with_post_state()
	OpLog.i(LOG_TAG, ["play_replay_after_reconcile ", _score_summary()])

	var should_end_set := false
	var post_set_num: int = -1

	if replay.has("pre_state") and replay.has("post_state"):
		var pre: Array[int] = replay["pre_state"]
		var post: Array[int] = replay["post_state"]

		var pre_set_num := pre[0]
		post_set_num = post[0]

		var pre_sets := Vector2i(pre[3], pre[4])
		var post_sets := Vector2i(post[3], post[4])

		var post_scores := Vector2i(post[1], post[2])
		var both_players_have_score: bool = (post_scores.x > 0 and post_scores.y > 0)

		var sets_changed: bool = (pre_sets != post_sets)
		var set_index_changed: bool = (pre_set_num != post_set_num)

		should_end_set = sets_changed or set_index_changed

		OpLog.i(LOG_TAG, [
			"play_replay_state pre=", pre,
			" post=", post,
			" preSets=", pre_sets,
			" postSets=", post_sets,
			" postScores=", post_scores,
			" setsChanged=", sets_changed,
			" setIndexChanged=", set_index_changed,
			" shouldEndSet=", should_end_set
		])
	else:
		OpLog.w(LOG_TAG, "play_replay missing pre/post state; assuming not end-of-set")
		should_end_set = false

	if should_end_set:
		await _animate_set_bar_and_award_points(true)
		OpLog.i(LOG_TAG, ["play_replay_set_animation_done postSet=", post_set_num, " ", _score_summary()])
	else:
		OpLog.i(LOG_TAG, ["play_replay_done no_set_end ", _score_summary()])
	replay_in_progress = false

func update_distance() -> void:
	if not is_instance_valid(distance_label):
		return

	match set_num:
		1:
			distance_label.text = "50ft"
		2:
			distance_label.text = "70ft"
		3:
			distance_label.text = "90ft"
		_:
			distance_label.text = "50ft"

func parse_replay(replay_str: String) -> Dictionary:
	OpLog.i(LOG_TAG, ["parse_replay_start rawLen=", replay_str.length(), " raw=", replay_str])
	var result = {'moves': []}
	var replay_split = replay_str.split('|')
	for elem in replay_split:
		if elem.begins_with("state:"):
			var state_name = "post_state" if "pre_state" in result else "pre_state"
			result[state_name] = convert_to_int_arr(elem.split(':')[1])
		elif elem.begins_with("move:"):
			result['moves'].append(convert_to_float_arr(elem.split(':')[1]))
	OpLog.i(LOG_TAG, ["parse_replay_done ", _replay_summary_dict(result)])
	return result

var my_player
func _set_game_data(new_replay: String) -> void:
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", new_replay])

	var parsed = JSON.parse_string(new_replay)
	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, ["set_game_data invalid JSON raw=", new_replay])
		return

	dbg(["set_game_data parsed=", parsed])

	isTurn = parsed["isYourTurn"]
	player = int(parsed["player"])
	gseed = int(parsed["seed"])
	num = int(parsed["num"])
	var opponent_avatar_key = ""
	my_player = parsed.get("myPlayerId", "")
	var p1_id: String = parsed.get("player1", "")
	var p2_id: String = parsed.get("player2", "")

	spectator_mode = my_player != "" and p1_id != "" and p2_id != "" and my_player != p1_id and my_player != p2_id
	if is_instance_valid(spectator_label):
		spectator_label.visible = spectator_mode
	OpLog.i(LOG_TAG, [
		"set_game_data parsed_initial turn=", isTurn,
		" payloadPlayer=", player,
		" myPlayer=", my_player,
		" p1=", p1_id,
		" p2=", p2_id,
		" spectator=", spectator_mode,
		" seed=", gseed,
		" num=", num
	])

	local_index = 1
	if not spectator_mode and my_player != "":
		if my_player == p1_id:
			local_index = 1
		elif my_player == p2_id:
			local_index = 2

	if isTurn and not spectator_mode:
		player = 2 if player == 1 else 1
	elif spectator_mode:
		player = 1

	OpLog.i(LOG_TAG, ["player_resolve localPlayer=", player, " localIndex=", local_index, " spectator=", spectator_mode])

	if player == 1 or spectator_mode:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"

	if opponent_avatar_key != "" and parsed.has(opponent_avatar_key):
		var avatar_string = parsed[opponent_avatar_key]
		var opponent_data = GameUtils._parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	if spectator_mode and parsed.has("avatar1"):
		var p1_data = GameUtils._parse_avatar_string(parsed["avatar1"])
		if is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", p1_data)

	var incoming_replay_raw: String = ""
	if "replay" in parsed:
		incoming_replay_raw = String(parsed["replay"])

	if not incoming_replay_raw.is_empty():
		replay = parse_replay(incoming_replay_raw)

		var has_pre: bool = replay.has("pre_state")
		var has_post: bool = replay.has("post_state")
		OpLog.i(LOG_TAG, ["set_game_data replay_loaded ", _replay_summary_dict(replay)])
		if incoming_replay_raw == last_replay_raw and replay_in_progress:
			OpLog.w(LOG_TAG, "set_game_data duplicate replay received while replay_in_progress=true")
		last_replay_raw = incoming_replay_raw

		var shooter_index: int = 0
		if has_pre and has_post:
			var pre: Array[int] = replay["pre_state"]
			var post: Array[int] = replay["post_state"]

			var pre_p1_score: int = pre[1]
			var pre_p2_score: int = pre[2]
			var post_p1_score: int = post[1]
			var post_p2_score: int = post[2]

			var p1_changed: bool = (post_p1_score != pre_p1_score)
			var p2_changed: bool = (post_p2_score != pre_p2_score)

			if p1_changed and not p2_changed:
				shooter_index = 1
			elif p2_changed and not p1_changed:
				shooter_index = 2
			else:
				shooter_index = 0

			OpLog.i(LOG_TAG, [
				"replay_shooter shooter=", shooter_index,
				" pre=", Vector2i(pre_p1_score, pre_p2_score),
				" post=", Vector2i(post_p1_score, post_p2_score)
			])

		_should_play_replay = true
		if not spectator_mode and shooter_index != 0 and shooter_index == local_index:
			_should_play_replay = false

		OpLog.i(LOG_TAG, ["should_play_replay=", _should_play_replay, " localIndex=", local_index])

		var use_post_for_ui: bool = (not spectator_mode and has_post and shooter_index != 0 and shooter_index == local_index)
		var state: Array[int]

		if use_post_for_ui:
			state = replay["post_state"]
			OpLog.i(LOG_TAG, "set_game_data using_post_state_for_ui")
		else:
			state = replay["pre_state"]
			OpLog.i(LOG_TAG, "set_game_data using_pre_state_for_ui")

		if use_post_for_ui:
			dbg(["apply_post_set_num=", state[0]])
			update_set_number(state[0])
		else:
			dbg(["apply_pre_set_num=", state[0]])
			update_set_number(state[0])
		update_distance()

		var p1_score: int = state[1]
		var p2_score: int = state[2]
		var p1_sets: int = state[3]
		var p2_sets: int = state[4]

		if spectator_mode:
			you_score = p1_score
			opp_score = p2_score
			you_set_wins = p1_sets
			opp_set_wins = p2_sets
		else:
			if local_index == 1:
				you_score = p1_score
				opp_score = p2_score
				you_set_wins = p1_sets
				opp_set_wins = p2_sets
			else:
				you_score = p2_score
				opp_score = p1_score
				you_set_wins = p2_sets
				opp_set_wins = p1_sets

		OpLog.i(LOG_TAG, ["set_game_data scores_mapped ", _score_summary()])
		_update_set_score_labels()

	for arrow_i in shots:
		if is_instance_valid(arrow_i):
			arrow_i.queue_free()

	shots.clear()
	moves = []
	num_shots = 0

	if replay_in_progress:
		OpLog.i(LOG_TAG, "set_game_data preserving played_replay during replay")
	else:
		played_replay = false

	has_turn_pre_state = false
	turn_pre_state.clear()

	OpLog.i(LOG_TAG, ["set_game_data_done player=", player, " localIndex=", local_index, " ", _score_summary()])

	if replay_in_progress and incoming_replay_raw == last_replay_raw:
		OpLog.w(LOG_TAG, "set_game_data suppress process_state duplicate replay")
		return

	_process_game_state()

func add_score(score: int, you: bool = true) -> void:
	await get_tree().create_timer(0.5).timeout
	if score <= 0:
		return

	var old_val: int
	var new_val: int

	if you:
		old_val = you_score
		you_score += score
		new_val = you_score
	else:
		old_val = opp_score
		opp_score += score
		new_val = opp_score

	OpLog.i(LOG_TAG, ["add_score amount=", score, " you=", you, " old=", old_val, " new=", new_val, " ", _score_summary()])

	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(
		func(v: float) -> void:
			if you:
				you_score = int(v)
			else:
				opp_score = int(v)
			_update_set_score_labels()
	,
		float(old_val),
		float(new_val),
		0.25
	)

var aim_cursor_velocity: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var initial_pos: Vector2 = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		dbg("input_ignored game_over=true")
		return
	
	if _settings_open or spectator_mode:
		dbg(["input_ignored settings=", _settings_open, " spectator=", spectator_mode])
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and current_arrow != null:
			if event.pressed:
				reset_aim_tween()
				bow_fully_drawn = false

				if not is_instance_valid(aim_cursor):
					return

				var viewport_size: Vector2 = get_viewport().get_visible_rect().size
				aim_cursor.position = viewport_size * 0.5
				aim_cursor.visible = true

				is_dragging = true
				initial_pos = event.position
				aim_cursor_velocity = Vector2.ZERO

				camera_zoom(41.5, true)
				start_aim_timer()
				_fade_top_bar(false)
				OpLog.i(LOG_TAG, ["aim_start pos=", event.position, " shot=", num_shots, " set=", set_num])
			elif is_dragging:
				shoot_dart()
				dbg(["aim_stop pos=", event.position])

	elif event is InputEventMouseMotion:
		if is_dragging and is_instance_valid(aim_cursor):
			var delta_finger_pos: Vector2 = event.position - initial_pos

			var desired_velocity: Vector2 = delta_finger_pos * sensitivity
			aim_cursor_velocity = desired_velocity

			if aim_cursor_velocity.length() > max_speed:
				aim_cursor_velocity = aim_cursor_velocity.normalized() * max_speed
				
func _process(delta: float) -> void:
	if not is_dragging:
		aim_cursor_velocity *= pow(damping_factor, delta)

	if is_instance_valid(aim_cursor):
		aim_cursor.position += aim_cursor_velocity * delta

		var viewport_size := get_viewport().get_visible_rect().size
		aim_cursor.position.x = clampf(aim_cursor.position.x, 0.0, viewport_size.x)
		aim_cursor.position.y = clampf(aim_cursor.position.y, 0.0, viewport_size.y)

	if is_instance_valid(wind_panel_container) and wind_panel_container.visible \
		and is_instance_valid(camera) and is_instance_valid(target):
		var target_2d_pos: Vector2 = camera.unproject_position(target.global_position)
		var offset: Vector2 = Vector2(-75.0, -130.0) \
			if is_equal_approx(target.global_position.z, -14.4329) \
			else Vector2(-75.0, -110.0)
		wind_panel_container.position = target_2d_pos + offset

func camera_zoom(val: float, marks_draw_complete: bool = false) -> void:
	if not is_instance_valid(camera):
		return

	if aim_zoom_tween != null:
		aim_zoom_tween.kill()
		aim_zoom_tween = null

	if marks_draw_complete:
		bow_fully_drawn = false

	aim_zoom_tween = create_tween()
	aim_zoom_tween.set_loops(1)
	aim_zoom_tween.tween_property(camera, "fov", val, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	aim_zoom_tween.connect("finished", func() -> void:
		if marks_draw_complete and is_dragging:
			bow_fully_drawn = true
		aim_zoom_tween = null
	)

func calc_shot_pos() -> Vector3:
	var screen_pos: Vector2

	screen_pos = aim_cursor.position
	dbg(["calc_shot_pos screen=", screen_pos])

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_normal: Vector3 = camera.project_ray_normal(screen_pos)

	if abs(ray_normal.z) < 0.0001:
		OpLog.e(LOG_TAG, ["calc_shot_pos ray_parallel screen=", screen_pos])
		return Vector3()

	var t: float = ((target.position.z) - ray_origin.z) / ray_normal.z
	var target_3d_position: Vector3 = ray_origin + ray_normal * t

	dbg(["calc_shot_pos projected=", target_3d_position])
	return target_3d_position

func cam_follow_dart() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(target):
		return

	var center := _get_bullseye_center_world()

	var cam_pos := Vector3(
		center.x,
		center.y + CAMERA_FOLLOW_Y_OFFSET,
		target.position.z + CAMERA_FOLLOW_DISTANCE_Z
	)

	var look_target := center - Vector3(0.0, CAMERA_LOOK_AT_Y_OFFSET, 0.0)
	camera.look_at(look_target, Vector3.UP)

	var _tween = create_tween()
	_tween.set_loops(1)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(camera, "position", cam_pos, CAMERA_FOLLOW_LERP_TIME)
	_tween.parallel().tween_property(camera, "fov", CAMERA_FOLLOW_FOV, CAMERA_FOLLOW_LERP_TIME)

func cam_reset_pos() -> void:
	await get_tree().create_timer(0.5).timeout
	
	if not is_instance_valid(camera):
		return
	
	var _tween = create_tween()
	_tween.set_loops(1)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(camera, "position", CAMERA_DEFAULT_POS, 0.5)
	_tween.parallel().tween_property(camera, "fov", CAMERA_DEFAULT_FOV, 0.5)
	await _tween.finished
	
func _get_score_color(points: int) -> Color:
	if points <= 2:
		return Color.WHITE
	elif points <= 4:
		return Color.BLACK
	elif points <= 6:
		return Color(0.2, 0.4, 1.0)
	elif points <= 8:
		return Color(1.0, 0.2, 0.2)
	else:
		return Color(1.0, 0.84, 0.0)

func start_aim_timer() -> void:
	if not is_instance_valid(aim_progress_bar):
		return
	
	aim_progress_bar.value = 0.0
	aim_progress_bar.visible = false
	
	await get_tree().create_timer(3.0).timeout
	
	if not is_dragging or not is_instance_valid(aim_cursor) or not aim_cursor.visible:
		return
	
	aim_progress_bar.visible = true
	aim_tween = create_tween()
	aim_tween.set_loops(1)
	aim_tween.tween_property(aim_progress_bar, "value", 100.0, 5.0).set_trans(Tween.TRANS_LINEAR)
	aim_tween.connect("finished", func():
		aim_tween = null
		if is_dragging and aim_cursor.visible:
			shoot_dart()
	)

func shoot_dart() -> void:
	if game_over:
		OpLog.w(LOG_TAG, "shoot_dart skipped game_over=true")
		return

	if not bow_fully_drawn:
		OpLog.i(LOG_TAG, ["shoot_cancelled not_fully_drawn shot=", num_shots, " set=", set_num])
		is_dragging = false
		bow_fully_drawn = false
		reset_aim_tween()
		if is_instance_valid(aim_cursor):
			aim_cursor.visible = false
		aim_cursor_velocity = Vector2.ZERO
		_fade_top_bar(true)
		camera_zoom(CAMERA_DEFAULT_FOV)
		return
		
	is_dragging = false
	bow_fully_drawn = false
	if is_instance_valid(aim_progress_bar):
		aim_progress_bar.visible = false
		aim_progress_bar.value = 0.0
	if is_instance_valid(aim_cursor):
		aim_cursor.visible = false
	aim_cursor_velocity = Vector2.ZERO
	
	_hide_wind_panel(0.2)
	var shot_pos: Vector3 = calc_shot_pos()
	OpLog.i(LOG_TAG, ["shot_release basePos=", shot_pos, " shot=", num_shots, " set=", set_num])
	
	if current_wind_angle.length() > 0.0 and current_wind_power != 0.0:
		var set_factor: float = 1.0
		match set_num:
			1:
				set_factor = 0.75
			2:
				set_factor = 1.0
			3:
				set_factor = 1.25
			_:
				set_factor = 1.0
		
		var rings_offset: float = current_wind_power * set_factor
		var displacement_mag: float = rings_offset * RING_SPACING
		
		var dir: Vector2 = current_wind_angle.normalized()
		var wind_displacement: Vector2 = dir * displacement_mag
		
		OpLog.i(LOG_TAG, [
			"shot_wind set=", set_num,
			" power=", current_wind_power,
			" ringsOffset=", rings_offset,
			" displacement=", displacement_mag,
			" dir=", dir,
			" disp=", wind_displacement
		])
		
		var shot_pos_2d: Vector2 = Vector2(shot_pos.x, shot_pos.y) + wind_displacement
		shot_pos = Vector3(shot_pos_2d.x, shot_pos_2d.y, shot_pos.z)
		OpLog.i(LOG_TAG, ["shot_final pos=", shot_pos])
	else:
		dbg(["shot_wind_not_applied angleLen=", current_wind_angle.length(), " power=", current_wind_power])

	var shot_arrow := current_arrow
	shot_arrow.shoot(shot_pos, func() -> void:
		var pts: int = target.calc_score(shot_arrow)
		var hit_pos: Vector3 = shot_arrow.global_transform.origin
		
		OpLog.i(LOG_TAG, [
			"shot_score points=", pts,
			" hitPos=", shot_arrow.global_transform.origin,
			" shot=", num_shots,
			" set=", set_num
		])

		_spawn_score_popup(hit_pos, pts, _get_score_color(pts))

		if pts > 0:
			add_score(pts)

		_fade_top_bar(true)
		num_shots += 1
		await get_tree().create_timer(1).timeout
		await cam_reset_pos()
		_process_game_state()
	)

	cam_follow_dart()
	shots.append(shot_arrow)
	moves.append(shot_pos)
	OpLog.i(LOG_TAG, ["shot_recorded moves=", moves.size(), " pos=", shot_pos])
	current_arrow = null
	
func reset_aim_tween() -> void:
	if is_instance_valid(aim_progress_bar):
		aim_progress_bar.value = 0.0
		aim_progress_bar.visible = false
	if aim_tween != null:
		aim_tween.stop()
		aim_tween = null

func _spawn_score_popup(world_pos: Vector3, amount: int, color: Color) -> void:
	if not is_instance_valid(target) or not is_instance_valid(camera):
		OpLog.w(LOG_TAG, "score_popup skipped missing target or camera")
		return

	var popup := Label3D.new()

	if amount <= 0:
		popup.text = "MISS!"
		color = Color.WHITE
	else:
		popup.text = "+%d" % amount

	popup.modulate = color
	popup.pixel_size = 0.006
	popup.outline_size = 3
	popup.outline_modulate = Color.BLACK
	popup.double_sided = true
	var parent_3d: Node3D = self
	parent_3d.add_child(popup)
	var center_world: Vector3 = target.global_position
	var final_world: Vector3 = world_pos

	if amount <= 0:
		var horizontal_dist := Vector2(
			world_pos.x - center_world.x,
			world_pos.y - center_world.y
		).length()

		if horizontal_dist > BOARD_RADIUS:
			final_world = center_world

	var to_camera: Vector3 = (camera.global_transform.origin - final_world).normalized()
	var start_world: Vector3 = final_world + to_camera * 0.15

	var start_local: Vector3 = parent_3d.to_local(start_world)
	popup.position = start_local

	dbg(["score_popup amount=", amount, " world=", world_pos, " final=", final_world])

	var end_local: Vector3 = start_local + Vector3(0.0, 0.35, 0.0)

	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(popup, "position", end_local, 0.8)
	t.parallel().tween_property(popup, "modulate:a", 0.0, 0.8)
	t.tween_callback(func():
		if is_instance_valid(popup):
			popup.queue_free()
	)

func convert_to_int_arr(cstr: String) -> Array[int]:
	var result: Array[int] = []
	if len(cstr) > 0:
		for elem in cstr.split(','):
			result.append(int(elem))
	return result

func convert_to_float_arr(cstr: String) -> Array[float]:
	var result: Array[float] = []
	if len(cstr) > 0:
		for elem in cstr.split(','):
			result.append(float(elem))
	return result

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
	
