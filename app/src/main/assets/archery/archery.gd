extends Node3D
class_name ArcheryGame

const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")

@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var settings_button: Button = %SettingsButton
@onready var winner_label: Label = %WinLossLabel
@onready var waiting_label: Label = %waitingLabel
@onready var sent_label: Label = %SentLabel
@onready var waiting_blur: ColorRect = %WaitBlur
@onready var main_overlay: Control = %MainOverlay
@onready var dot_timer: Timer = %DotTimer
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
var my_uuid: String = ""
const MAX_WIND_POWER: float = 5.0   # used for color scaling
const BOARD_RADIUS: float = 0.75
const RING_COUNT: float = 10.0
const RING_SPACING: float = BOARD_RADIUS / RING_COUNT
var wind_anim_time: float = 0.0     # for the stretching arrow animation
var wind_pulse_amount: float = 0.01
var _settings_open: bool = false
var has_turn_pre_state: bool = false
var turn_pre_state: Array[int] = []
var sent_tween: Tween
var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
var spectator_mode: bool = false
var game_over: bool = false

var appPlugin = null
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

var set_num: int = 1          # current set (1–3)
var you_score: int = 0        # per-set score (you)
var opp_score: int = 0        # per-set score (opponent)
var you_set_wins: int = 0     # total sets won (you)
var opp_set_wins: int = 0     # total sets won (opponent)

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


func _ready() -> void:
	appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("App plugin is available")
		appPlugin.connect("set_game_data", _set_game_data)
		my_uuid = appPlugin.getSenderUUID()
		appPlugin.onReady()
	else:
		print("App plugin is not available")
		my_uuid = "0a602920-2033-469d-aab8-5e832c5d4f6a"
		#var dev_data = '{ "isYourTurn": true, "player": "1", "replay": "state:2,0,0,1,1|move:0,2.433302,4.115979,-19.019581|move:0,1.885665,4.547050,-19.018667|move:0,1.404883,4.726025,-19.029633|state:2,0,0,0,1", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,0|mouth,0|acc,0|wins,0|bg_color,0.900000,0.900000,0.900000|body_color,0.000000,1.000000,0.000000|glasses,0|stache,0|backdrop,0|hair,3|clothes,2|hair_color,0.431373,0.254902,0.121569|clothes_color,0.438450,0.340784,0.366469", "player1": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player2": "", "id": "6gt6WvSteSKHYrKr\n", "ios": "16.3.1", "num": "3", "game": "archery", "seed": "247149971", "tver": "5", "build": "d4yGowcTuIW9i", "version": "0" }'
		var dev_data = '{ "isYourTurn": true, "player": "1", "replay": "state:1,18,0,0,0|move:1,0.059418,1.351113,-14.397592|move:1,-0.077269,1.397037,-14.397591|move:1,-0.020799,1.492665,-14.397592|state:1,29,18,0,1", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,0|mouth,0|acc,0|wins,0|bg_color,0.900000,0.900000,0.900000|body_color,0.000000,1.000000,0.000000|glasses,0|stache,0|backdrop,0|hair,3|clothes,2|hair_color,0.431373,0.254902,0.121569|clothes_color,0.438450,0.340784,0.366469", "player1": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player2": "", "id": "6gt6WvSteSKHYrKr\n", "ios": "16.3.1", "num": "3", "game": "archery", "seed": "247149971", "tver": "5", "build": "d4yGowcTuIW9i", "version": "0" }'
		_set_game_data(dev_data)
	if is_instance_valid(aim_cursor):
		aim_cursor.visible = false
	if is_instance_valid(aim_progress_bar):
		aim_progress_bar.visible = false
		aim_progress_bar.value = 0.0
	if is_instance_valid(wind_arrow):
		wind_arrow.pivot_offset = wind_arrow.size / 2.0
		print("Wind Arrow Set 1")
		wind_arrow.scale = Vector2.ONE
	if is_instance_valid(wind_arrow_circle):
		if wind_arrow_circle is Control:
			wind_arrow_circle.pivot_offset = wind_arrow_circle.size / 2.0
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
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

func check_winner(completed_round: int = set_num) -> bool:
	print("check_winner: completed_round=", completed_round, " you_sets=", you_set_wins, " opp_sets=", opp_set_wins)

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
				_show_win_burst(player_avatar_display)
			send_winner = my_uuid + "|1"
			print("check_winner: EARLY YOU WIN (2-0 rule)")
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
				_show_win_burst(opp_avatar_display)
			send_winner = my_uuid + "|-1"
			print("check_winner: EARLY YOU LOSE (0-2 rule)")
			return true

	# No final winner unless round 3 has actually completed.
	if completed_round < 3:
		print("check_winner: completed_round < 3 and no early clinch; no result yet.")
		return false

	game_over = true
	stop_waiting_animation()
	_hide_wind_panel(0.0)

	if you_set_wins == opp_set_wins:
		winner_label.text = "DRAW"
		winner_label.visible = true
		winner_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		if is_instance_valid(player_avatar_display):
			_show_win_burst(player_avatar_display)
		if is_instance_valid(opp_avatar_display):
			_show_win_burst(opp_avatar_display)
		send_winner = my_uuid + "|0"
		print("check_winner: DRAW (final)")
		return true
	elif you_set_wins > opp_set_wins:
		if not spectator_mode:
			winner_label.text = "YOU WIN!"
		else:
			winner_label.text = "Player 1 Wins!"
		winner_label.visible = true
		winner_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		if is_instance_valid(player_avatar_display):
			_show_win_burst(player_avatar_display)
		send_winner = my_uuid + "|1"
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
		if is_instance_valid(opp_avatar_display):
			_show_win_burst(opp_avatar_display)
		send_winner = my_uuid + "|-1"
		print("check_winner: YOU LOSE (final)")
		return true
		
func _process_game_state() -> void:
	if game_over:
		print("PROCESS_GAME_STATE: game_over=true, ignoring further state.")
		stop_waiting_animation()
		_hide_wind_panel(0.0)
		return
		
	print("PROCESS_GAME_STATE: num_shots=", num_shots, " isTurn=", isTurn, " replay_empty=", replay.is_empty(), " played_replay=", played_replay, " you_sets=", you_set_wins, " opp_sets=", opp_set_wins)

	stop_waiting_animation()
	_hide_wind_panel(0.0)

	if replay_in_progress:
		print("PROCESS_GAME_STATE: replay already in progress, skipping re-entry")
		return

	if not replay.is_empty() and not played_replay and _should_play_replay:
		print("PROCESS_GAME_STATE: playing opponent replay first")
		replay_in_progress = true
		played_replay = true
		await play_replay()
	else:
		if not replay.is_empty() and not played_replay:
			print("PROCESS_GAME_STATE: replay present but _should_play_replay=false; skipping replay (likely our own last turn).")

	if (not isTurn or spectator_mode) and not game_over:
		print("PROCESS_GAME_STATE: not our turn and game_over=", game_over, "; showing waiting UI")
		start_waiting_animation()
		return

	stop_waiting_animation()

	if num_shots < 3:
		print("PROCESS_GAME_STATE: preparing shot index", num_shots)

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
			print("PROCESS_GAME_STATE: captured turn_pre_state=", turn_pre_state)

		calc_wind()
		current_arrow = arrow.spawn()
		if not spectator_mode and not game_over:
			_show_wind_panel(target.global_position)
	else:
		print("PROCESS_GAME_STATE: set finished (local), calling _animate_set_bar_and_award_points()")
		await _animate_set_bar_and_award_points()

func _award_set_points_and_continue(completed_round: int = set_num) -> bool:
	var won_now: bool = check_winner(completed_round)
	if appPlugin:
		appPlugin.updateGameData(export_replay())
	else:
		print("No app plugin! " + export_replay())
	return won_now
	
func _send_turn_state_only() -> void:
	if appPlugin:
		appPlugin.updateGameData(export_replay())
	else:
		print("No app plugin! " + export_replay())
		
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
		printerr("export_replay: ray is parallel to target plane for screen_pos=%s" % screen_pos)
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
		print("export_replay: using turn_pre_state as pre_state: ", pre_state)
	elif not replay.is_empty() and replay.has("post_state"):
		pre_state = replay["post_state"]
		if pre_state.size() < 5:
			pre_state.resize(5)
		set_index_for_turn = pre_state[0]
		print("export_replay: using replay.post_state as pre_state: ", pre_state)
	else:
		var p1_sets := (you_set_wins if player == 1 else opp_set_wins)
		var p2_sets := (you_set_wins if player == 2 else opp_set_wins)
		set_index_for_turn = set_num
		pre_state = [set_index_for_turn, 0, 0, p1_sets, p2_sets]
		print("export_replay: no prior replay; using default pre_state: ", pre_state)

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
		print("Adding Winner Attribute")
		replay_dict["winner"] = send_winner
	else:
		play_sent_animation()
	print("OUTGOING DATA: ", replay_dict)
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
		print("_animate_set_bar_and_award_points: already in progress, skipping duplicate entry")
		return
	set_award_in_progress = true
	_hide_wind_panel(0.0)
	print("=== _animate_set_bar_and_award_points START === from_replay=", from_replay)
	print("num_shots:", num_shots, " num:", num, " you_score:", you_score, " opp_score:", opp_score)

	if not _top_bar_inited \
		or not is_instance_valid(top_game_bar) \
		or not _score_box_inited \
		or not is_instance_valid(score_box) \
		or not is_instance_valid(score_label):
		print("Top bar / score_box / score_label missing, skipping animation.")
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

	print("Top bar start_global:", start_global, " target_global:", target_global)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(top_game_bar, "global_position", target_global, 0.5)
	tween.parallel().tween_property(score_box, "custom_minimum_size", target_min_size, 0.5)
	await tween.finished
	print("Center tween finished")

	await get_tree().create_timer(1).timeout

	if not is_second_shooter:
		print("Mid-set animation: only first shooter has shot; send state only, no winner check, no set award.")

		_send_turn_state_only()

		var tween_back_mid := create_tween()
		tween_back_mid.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween_back_mid.tween_property(top_game_bar, "global_position", start_global, 0.5)
		tween_back_mid.parallel().tween_property(score_box, "custom_minimum_size", start_min_size, 0.5)
		await tween_back_mid.finished

		top_game_bar.set_as_top_level(was_top_level)

		print("Back tween finished (mid-set)")
		print("=== _animate_set_bar_and_award_points END (mid-set) ===")
		set_award_in_progress = false
		return

	var start_you: int = you_score
	var start_opp: int = opp_score
	print("End-of-set scoring (before awarding set): you=", start_you, " opp=", start_opp)

	if opp_score > you_score:
		opp_set_wins += 1
		print("Set result: OPPONENT wins set -> opp_set_wins=", opp_set_wins)
		_update_set_score_labels()
		_animate_set_win_bump(false)
		_spawn_avatar_score_popup(false, 1)
	elif you_score > opp_score:
		you_set_wins += 1
		print("Set result: YOU win set -> you_set_wins=", you_set_wins)
		_update_set_score_labels()
		_animate_set_win_bump(true)
		_spawn_avatar_score_popup(true, 1)
	else:
		opp_set_wins += 1
		you_set_wins += 1
		print("Set result: TIE set -> you_set_wins=", you_set_wins, " opp_set_wins=", opp_set_wins)
		_update_set_score_labels()
		_animate_set_win_bump(true)
		_animate_set_win_bump(false)
		_spawn_avatar_score_popup(true, 1)
		_spawn_avatar_score_popup(false, 1)
	
	
	var completed_round: int = set_num
	var match_over_now: bool = false

	if not from_replay:
		print("Calling _award_set_points_and_continue (end of full set, before score reset)")
		match_over_now = _award_set_points_and_continue(completed_round)
	else:
		match_over_now = check_winner(completed_round)

	# If the match just ended, keep the final round score visible.
	if match_over_now:
		print("_animate_set_bar_and_award_points: match_over_now=true; preserving final score display")
	else:
		if set_num < 3:
			update_set_number(set_num + 1)
			update_distance()
			print("CALL 506")

		if start_you != 0 or start_opp != 0:
			print("Starting score tween from:", start_you, start_opp, "to 0,0")
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
			print("Score tween finished")

		you_score = 0
		opp_score = 0
		_update_set_score_labels()
		print("Per-set scores reset to 0-0")

	await get_tree().create_timer(0.4).timeout

	var tween_back := create_tween()
	tween_back.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween_back.tween_property(top_game_bar, "global_position", start_global, 0.5)
	tween_back.parallel().tween_property(score_box, "custom_minimum_size", start_min_size, 0.5)
	await tween_back.finished

	top_game_bar.set_as_top_level(was_top_level)

	print("Back tween finished")
	print("=== _animate_set_bar_and_award_points END (full set) ===")
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

	print("calc_wind: set=", set_num,
		" num_shots=", num_shots,
		" derived_seed=", derived_seed)

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
	
	print("wind angle(deg)=", angle,
		" vec=", current_wind_angle,
		" power=", power)

	_update_wind_ui(angle, power)

func _update_wind_ui(angle_degrees: float, power: float) -> void:
	print(">>> _update_wind_ui CALLED angle=", angle_degrees, " power=", power)
	var t: float = clamp(power / MAX_WIND_POWER, 0.0, 1.0)

	var green: Color = Color(0.792, 0.792, 0.792, 1.0)
	var yellow: Color = Color(1.0, 0.9, 0.1)
	var red: Color = Color(0.95, 0.1, 0.1)

	var color: Color
	if t < 0.5:
		color = green.lerp(yellow, t * 2.0)
	else:
		color = yellow.lerp(red, (t - 0.5) * 2.0)

	print("_update_wind_ui: angle_degrees=", angle_degrees, " power=", power, " current_wind_angle=", current_wind_angle)

	if is_instance_valid(wind_label):
		print("Have Wind Label")
		var hex: String = color.to_html(false)
		wind_label.bbcode_enabled = true
		wind_label.text = "[center][b]WIND: [color=#%s]%.1f[/color][/b][/center]" % [hex, power]

	if is_instance_valid(wind_arrow_circle):
		print("Have Wind Arrow Circle")
		wind_arrow_circle.modulate = color

	if is_instance_valid(wind_arrow):
		print("Have Wind Arrow (custom draw)")

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
	
	print("update_set_number 680: set_num =", set_num)
	
func _reconcile_scores_with_post_state() -> void:
	if not replay.has("post_state"):
		print("_reconcile_scores_with_post_state: no post_state in replay; skipping.")
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
		print("_reconcile_scores_with_post_state: scores already match post_state; no adjustment.")
		return

	print("_reconcile_scores_with_post_state: reconciling. current you=", you_score,
		" opp=", opp_score, " target you=", target_you, " target opp=", target_opp)

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
		print("play_replay: called without replay_in_progress guard, aborting")
		return
	_hide_wind_panel(0.0)
	update_distance()
	_update_set_score_labels()
	print("play_replay: starting, you_score=", you_score, " opp_score=", opp_score, " you_sets=", you_set_wins, " opp_sets=", opp_set_wins)

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

			print("play_replay: move[", i, "] raw=", move, " adjusted_pos=", replay_pos)

			replay_arrows.append(arrow.spawn())
			var this_arrow: Arrow = replay_arrows[-1]

			this_arrow.shoot(replay_pos, func() -> void:
				var arrow_score: int = target.calc_score(this_arrow)
				print("play_replay: arrow hit score=", arrow_score, " (before add_score) opp_score=", opp_score)

				var hit_pos: Vector3 = this_arrow.global_transform.origin
				_spawn_score_popup(hit_pos, arrow_score, _get_score_color(arrow_score))

				if arrow_score > 0:
					add_score(arrow_score, false)
			)
			await get_tree().create_timer(2.0).timeout
	else:
		print("play_replay: no moves in replay")

	await cam_reset_pos()
	
	for arrow_i in replay_arrows:
		if is_instance_valid(arrow_i):
			arrow_i.queue_free()
	replay_arrows.clear()

	print("play_replay: finished (before reconcile), you_score=", you_score, " opp_score=", opp_score,
		" you_sets=", you_set_wins, " opp_sets=", opp_set_wins)

	await _reconcile_scores_with_post_state()
	print("play_replay: after reconcile, you_score=", you_score, " opp_score=", opp_score)

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

		print("play_replay: pre_state=", pre, " post_state=", post,
			" pre_sets=", pre_sets, " post_sets=", post_sets,
			" pre_set_num=", pre_set_num, " post_set_num=", post_set_num,
			" post_scores=", post_scores,
			" both_have_score=", both_players_have_score,
			" sets_changed=", sets_changed,
			" set_index_changed=", set_index_changed,
			" should_end_set=", should_end_set)
	else:
		print("play_replay: no pre/post state; assuming not end-of-set for safety.")
		should_end_set = false

	if should_end_set:
		await _animate_set_bar_and_award_points(true)
		print("play_replay: _animate_set_bar_and_award_points(true, ", post_set_num, ") completed (end-of-set)")
	else:
		print("play_replay: not end-of-set; skipping set animation and letting local player shoot.")
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
	var result = {'moves': []}
	var replay_split = replay_str.split('|')
	for elem in replay_split:
		if elem.begins_with("state:"):
			var state_name = "post_state" if "pre_state" in result else "pre_state"
			result[state_name] = convert_to_int_arr(elem.split(':')[1])
		elif elem.begins_with("move:"):
			result['moves'].append(convert_to_float_arr(elem.split(':')[1]))
	return result

var my_player
func _set_game_data(new_replay: String) -> void:
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: ", parsed)

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
	print("_set_game_data: isTurn=", isTurn, " player(from payload)=", player, " my_player=", my_player, " spectator_mode=", spectator_mode)

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

	print("_set_game_data: resolved player(local)=", player, " local_index=", local_index)

	if player == 1 or spectator_mode:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"

	if opponent_avatar_key != "" and parsed.has(opponent_avatar_key):
		var avatar_string = parsed[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	if spectator_mode and parsed.has("avatar1"):
		var p1_data = _parse_avatar_string(parsed["avatar1"])
		if is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", p1_data)

	var incoming_replay_raw: String = ""
	if "replay" in parsed:
		incoming_replay_raw = String(parsed["replay"])

	if not incoming_replay_raw.is_empty():
		replay = parse_replay(incoming_replay_raw)

		var has_pre: bool = replay.has("pre_state")
		var has_post: bool = replay.has("post_state")
		print("_set_game_data: has_pre_state=", has_pre, " has_post_state=", has_post, " replay=", replay)
		if incoming_replay_raw == last_replay_raw and replay_in_progress:
			print("_set_game_data: same replay received while replay_in_progress=true; ignoring duplicate processing request")
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

			print("_set_game_data: shooter_index=", shooter_index,
				" pre_p1=", pre_p1_score, " pre_p2=", pre_p2_score,
				" post_p1=", post_p1_score, " post_p2=", post_p2_score)

		_should_play_replay = true
		if not spectator_mode and shooter_index != 0 and shooter_index == local_index:
			_should_play_replay = false

		print("_set_game_data: _should_play_replay=", _should_play_replay, " local_index=", local_index)

		var use_post_for_ui: bool = (not spectator_mode and has_post and shooter_index != 0 and shooter_index == local_index)
		var state: Array[int]

		if use_post_for_ui:
			state = replay["post_state"]
			print("_set_game_data: using POST state for initial UI")
		else:
			state = replay["pre_state"]
			print("_set_game_data: using PRE state for initial UI")

		if use_post_for_ui:
			print("_set_game_data: applying POST set_num from state[0]=", state[0])
			update_set_number(state[0])
		else:
			print("_set_game_data: applying set_num from state[0]=", state[0])
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

		print("_set_game_data: mapped you_score=", you_score, " opp_score=", opp_score,
			" you_sets=", you_set_wins, " opp_sets=", opp_set_wins)
		_update_set_score_labels()

	for arrow_i in shots:
		if is_instance_valid(arrow_i):
			arrow_i.queue_free()

	shots.clear()
	moves = []
	num_shots = 0

	if replay_in_progress:
		print("_set_game_data: replay already in progress, preserving played_replay state")
	else:
		played_replay = false

	has_turn_pre_state = false
	turn_pre_state.clear()

	print("YOU ARE PLAYER ", player, " (local_index=", local_index, ")")

	if replay_in_progress and incoming_replay_raw == last_replay_raw:
		print("_set_game_data: suppressing _process_game_state re-entry for identical replay already in progress")
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

	print("add_score called: score=", score, " you=", you, " old_val=", old_val, " new_val=", new_val)

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
		print("Input ignored: game_over=true")
		return
	
	if _settings_open or spectator_mode:
		print("Settings|Spectator: ", _settings_open, spectator_mode)
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
				print("started dragging")
			elif is_dragging:
				shoot_dart()
				print("stopped dragging")

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
	print("calc_shot_pos: using aim_cursor.position=", screen_pos)

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_normal: Vector3 = camera.project_ray_normal(screen_pos)

	if abs(ray_normal.z) < 0.0001:
		printerr("Ray is parallel to the target plane!!!")
		return Vector3()

	var t: float = ((target.position.z) - ray_origin.z) / ray_normal.z
	var target_3d_position: Vector3 = ray_origin + ray_normal * t

	print("Projected 3D position: ", target_3d_position)
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
		print("shoot_dart: game_over=true, ignoring shot.")
		return

	if not bow_fully_drawn:
		print("shoot_dart: released before bow fully drawn; cancelling shot.")
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
	print("initial shot pos (no wind): " + str(shot_pos))
	
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
		
		print("wind: set=", set_num,
			" power=", current_wind_power,
			" rings_offset=", rings_offset,
			" displacement_mag=", displacement_mag,
			" dir=", dir,
			" disp=", wind_displacement)
		
		var shot_pos_2d: Vector2 = Vector2(shot_pos.x, shot_pos.y) + wind_displacement
		shot_pos = Vector3(shot_pos_2d.x, shot_pos_2d.y, shot_pos.z)
		print("final shot pos (with wind): " + str(shot_pos))
	else:
		print("shoot_dart: wind not applied (angle len="
			+ str(current_wind_angle.length())
			+ ", power=" + str(current_wind_power) + ")")

	var shot_arrow := current_arrow
	shot_arrow.shoot(shot_pos, func() -> void:
		var pts: int = target.calc_score(shot_arrow)
		var hit_pos: Vector3 = shot_arrow.global_transform.origin

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
		print("SPAWN POPUP 3D: missing target or camera")
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

	print("SPAWN POPUP 3D: world_pos=", world_pos, " final_world=", final_world, " start_local=", start_local, " amount=", amount)

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
	
func _on_dot_timer_timeout():
	if not is_instance_valid(waiting_label):
		print("Warning: waiting_label is not valid in _on_dot_timer_timeout.")
		return
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots

func start_waiting_animation():
	if not is_instance_valid(waiting_label) or not is_instance_valid(waiting_blur) or not is_instance_valid(dot_timer):
		print("Warning: Waiting animation nodes are not valid.")
		return
	if spectator_mode:
		return

	_hide_wind_panel(0.2)

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

func _on_settings_button_pressed() -> void:
	if not is_instance_valid(settings_button):
		return
	if _settings_open:
		return
	_settings_open = true
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

	var custom_settings_title := popup_instance.find_child("CustomSettingsTitleLabel", true)
	if custom_settings_title and custom_settings_title is Label and settings_popup_script.custom_settings_container.get_child_count() > 0:
		(custom_settings_title as Label).visible = true
	elif custom_settings_title and custom_settings_title is Label:
		(custom_settings_title as Label).visible = false

	settings_popup_script.closed.connect(func():
		_settings_open = false
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
		if is_instance_valid(dim):
			dim.queue_free()
	)
	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await get_tree().process_frame

	var viewport_size := get_viewport().get_visible_rect().size
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
