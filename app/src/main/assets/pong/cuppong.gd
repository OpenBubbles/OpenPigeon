extends Node3D
class_name PongGame

#---------------------------------------------
var _debug_perf := false
var _debug_label: Label

var _frame_accum := 0.0
var _frame_count := 0
var _max_delta := 0.0
var _last_long_frame_ms := 0.0
#---------------------------------------------

var REPLAY_FRAME_DURATION: float = 0.03
var CHARMAP = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789~!@*()_+-.';"
var CHARMAP_LEN = len(CHARMAP)
const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")

@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var settings_button: Button = %SettingsButton
@onready var winner_label: Label = %WinLossLabel
@onready var waiting_label: Label = %waitingLabel
@onready var balls_back_label: Label = %ballsBackLabel
@onready var redemption_label: Label = %redemptionLabel
@onready var overtime_label: Label = %overtimeLabel
@onready var sent_label: Label = %SentLabel
@onready var waiting_blur: ColorRect = %WaitBlur
@onready var main_overlay: Control = %MainOverlay
@onready var dot_timer: Timer = %DotTimer
@onready var sun: DirectionalLight3D = $DirectionalLight3D1
@onready var env: WorldEnvironment = $WorldEnvironment

@export var show_overlay: bool = true

var appPlugin: Object
var screen_size: Vector2
var has_connected: bool = false
var game_settings_category: String = ""
var _settings_open: bool = false
var balls_back_tween: Tween
var sent_tween: Tween
var redemption_tween: Tween
var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"

var camera: Camera3D
var ball: RigidBody3D
var my_cups: Cups
var replay_cups: Cups
var current_ball: PongBall
var winner: String = ""

var my_uuid: String = ""
var game_over: bool = false


var start_replay_boards: String = "0,1,2,3,4,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9"

@export var replay_ball_start_pos: Vector3 = Vector3(0.0, -0.574, -0.80)
@export var player_ball_start_pos: Vector3 = Vector3(0.0, -0.55, -1.00)
@export var second_ball_offset: Vector3 = Vector3(0.28, 0.0, 0.0)

@export var min_drag_distance: float = 15.0 #Min Distance Required to be considered a throw
@export var min_speed_for_throw: float = 250.0 #Speed Deadband to prevent tapping on throw
@export var max_force_x: float = 0.40 #Absolute Max Force in x dir
@export var max_force_y: float = 1.1 #Absolute Max Force in y dir
@export var max_throw_speed_x: float = 2000.0 #How fast does this need to be flicked for 100% strength in x dir (lower is easy full power)
@export var max_throw_speed_y: float = 3800.0 #How fast does this need to be flicked for 100% strength in y dir (lower is easy full power)
@export var vertical_power_curve: float = 1.3 #Shape how the speed maps to the vertical force (lower is more sensitive)
@export var horizontal_power_curve: float = 1 #Shape how the speed maps to the horizontal force (lower is more sensitive)
@export var throw_power_scale: float = 0.65 #Global Scale Multiplier

var last_drag_distance: float = 0.0
var last_drag_duration: float = 0.0
var last_drag_speed_x: float = 0.0	# px/s
var last_drag_speed_y: float = 0.0	# px/s (screen space, before inversion)

var preview_ball: PongBall = null
var num_balls: int = 2
var throws: Array[Dictionary] = []
var redemption: bool = false
var played_replay: bool = false
var lost: bool = false

var drag_start_pos = Vector2.ZERO
var drag_start_time: float = 0.0
var dragging = false
var ball_ready: bool = false
var player: int
var is_my_turn: int
var replay_string: String
var mode: String

func _ready():
	screen_size = get_viewport().get_visible_rect().size
	if is_instance_valid(main_overlay):
		main_overlay.visible = show_overlay
		
	my_cups = get_node("cups2")
	replay_cups = get_node("cups1")
	camera = get_node("Camera3D")
	ball = get_node("ball")
	appPlugin = Engine.get_singleton("AppPlugin")
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	if appPlugin:
		if not has_connected:
			print("App plugin is available")
			appPlugin.connect("set_game_data", _set_game_data)
			my_uuid = appPlugin.getSenderUUID()
			has_connected = true
			appPlugin.onReady()
	else:
		print("App plugin is not available")
		#board:0,1,2,3,4,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9|move:K;AEDSK;AEDSLaC~DgLbFdCRLdHdCgLeI~BSLfKFBhLgL7ATLhM\'AiLiN zULjO0zkLlPtyWLmPTymLnP5xZLoP1xpLpPJw2LqPbwsLrOCv5LsNNvwLuMJu9LvLruALwJ7t(LxIltFLyGys-LzEwsKL9CIskL;BAsGLRA_suL1A siL*A_sgL;A_sgMdA_siMgA_skMiA_skMiA_skMiA_sk2&25|move:K;AEDSK-DgC K_FtCAK(HsB5K!JbBoK9KRAUK7L AdK4NgzJK2Ocy(K0O5yyKYPxx4KVPVxoKTP5wVKRP0wfKOPGvMKMO.u.KKOwuEKINFt!KFMAtwKDLhs3KBJUspKzH\'rWKxGjriKuEfqQKsB~qcJ(A(qaJ)BjqmKeBnqsKnBeqqKuA_qpKxA_qmKyA_qlKyA_qlKyA_ql6&24,28|move:K;AEDSK\'B9DyK-EjC*K_GpCGK)IhB\'K*J5BNK!LrBgK9MLAWK8NPApK6ODz4K4PdzyK2PKy*K1P2yHKZP5ybKXPTxRKWPsxlKUOYw1KSN_wwKRM-v@KPL7vGKNKGvbKMI*uSKKHkunKIFot4KHDetzLSB8tnK5BotALtA-tALoA-tELkA_tGLiA_tILhA_tJLhA_tJLhA_tJ0&24|move:K;AEDSK(C(DdK6FhCMKZHhB;KSI*BJKLKIA-KEL9AGKxNaz)KpN.zDKiO1y*KbPuyBJ_PUx@J9P5xAJ2P1w!JWPIwzJPPav~JIOAvzJBNLu~JuMHuzJnLpt~JhJ4tAJaIis!I)GvsBI8Esr*ITEvrOIAFHrxIgGErgH9Hlq!HPH0qUHwIeqDHcIoqmG5Ikp-GMH*p1GtHFpKGaG4puF3F)pdFKE!o9FrDSoSE\'CloCE1ALolEJyXn EqwUn1D\'uDnLD1r\'nv&24|board:1,3,4,5,7,8,9&0,1,2,3,4,5,6,7,8,9
		_set_game_data('{"isYourTurn":true,"skip_score1":"0","skip_score2":"0","player":"1","replay":"board:0,1,3,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9|move:K;AEDSLaDmDeLcFACRLdHyCjLeJgBXLgKVBpLhL;A3LiNjAvLjOez9LlO7zBLmPyy_LnPWyILoP5ybLqP0xQLrPFxjLsO-wYLtOtwrLvNCv6LwMxvALxLdu)LyJQuJLzH)udLBGdtTLCD;tnK\'C;tHLgC9tALsCYtxLhCItZK;CstFK*B7tsK(ButuK;A_tFLeA_tOLhA_tOLhA_tNLhA_tN0&24,27,31|move:K;AEDSK-C-DhK)FlCVK@HkCmK9I_B0K6KLBsK3L@A6K0NcAyKXN;z@KVO2zFKSPvy.KPPVyMKMP5yeKJP1xTKGPIxmKDO;w1KBOzwvKyNJv~KvMFvDKsLmu.KpJ1uMKnIfugKkGrtWKhEotqKgDhtHKgC uxKgCPvnKhB;wcKhBqw(KhAsx3KhBoyQKhB3zCKiCgAoKiCqBaKiCmB8KiB(CTKiBGDEKjA5EqKjA3E;KjBpF4&24,29,38|board:1,3,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9","score1":"0","score2":"0","num":"2","game":"beer","mode":"n","seed":"-1429210425","round":"1","seed2":"0"}')
	if _debug_perf:
		_create_debug_overlay()
	_enforce_mobile_lighting_settings()
	
func _enforce_mobile_lighting_settings() -> void:
	var vp = get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X
	Engine.physics_jitter_fix = 0.5
		
func _create_debug_overlay() -> void:
	if not _debug_perf:
		return
	
	var parent: Node = main_overlay if is_instance_valid(main_overlay) else get_tree().root
	var label := Label.new()
	label.name = "PerfOverlay"
	label.text = "Perf..."
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 0.0
	label.anchor_bottom = 0.0
	label.offset_left = 8.0
	label.offset_top = 8.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 999
	
	if parent is Viewport:
		var wrapper := Control.new()
		wrapper.name = "PerfOverlayRoot"
		wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
		parent.add_child(wrapper)
		wrapper.add_child(label)
	else:
		parent.add_child(label)
	
	_debug_label = label
	
func _process(delta: float) -> void:
	if not _debug_perf or not is_instance_valid(_debug_label):
		return
	
	_frame_accum += delta
	_frame_count += 1
	if delta > _max_delta:
		_max_delta = delta
	
	if _frame_accum >= 0.5:
		var fps := Engine.get_frames_per_second()
		var avg_dt := _frame_accum / _frame_count
		var avg_ms := avg_dt * 1000.0
		var max_ms := _max_delta * 1000.0
		var mem_static_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		var draw_calls := Performance.get_monitor(1000)        # RENDER_TOTAL_DRAW_CALLS_IN_FRAME
		var render_objects := Performance.get_monitor(1001)    # RENDER_TOTAL_OBJECTS_IN_FRAME
		var render_primitives := Performance.get_monitor(1002) # RENDER_PRIMITIVES_IN_FRAME
		var render_2d_items := Performance.get_monitor(1003)   # RENDER_2D_ITEMS_IN_FRAME
		var render_2d_calls := Performance.get_monitor(1004)   # RENDER_2D_DRAW_CALLS_IN_FRAME
		var ball_count := 0
		for child in get_children():
			if child is PongBall and child != ball:
				ball_count += 1

				_debug_label.text = (
			"FPS: %d\n" +
			"avg dt: %.2f ms\n" +
			"max dt: %.2f ms\n" +
			"Static Mem: %.1f MB\n" +
			"Draw Calls: %d\n" +
			"Render Obj: %d\n" +
			"Primitives: %d\n" +
			"2D Items: %d\n" +
			"2D Calls: %d\n" +
			"DragDist: %.1f px\n" +
			"DragDur: %.3f s\n" +
			"DragVx: %.1f px/s\n" +
			"DragVy: %.1f px/s\n" +
			"Balls: %d"
		) % [
			fps,
			avg_ms,
			max_ms,
			mem_static_mb,
			draw_calls,
			render_objects,
			render_primitives,
			render_2d_items,
			render_2d_calls,
			last_drag_distance,
			last_drag_duration,
			last_drag_speed_x,
			last_drag_speed_y,
			ball_count
		]
		
		if max_ms > 25.0:
			print(
				"LONG FRAME: ", max_ms, " ms",
				"  fps=", fps,
				"  draw_calls=", draw_calls,
				"  objects=", render_objects,
				"  prim=", render_primitives,
				"  balls=", ball_count,
				"  is_my_turn=", is_my_turn,
				"  played_replay=", played_replay
			)
		
		_frame_accum = 0.0
		_frame_count = 0
		_max_delta = 0.0

func check_winner() -> bool:
	if game_over:
		return true
	
	if winner.is_empty():
		return false
	
	var loser_uuid := winner.split("|")[0]
	
	if loser_uuid == my_uuid:
		_handle_game_over_i_lost()
	else:
		_handle_game_over_i_won()
	
	return true
	
func _handle_game_over_i_lost() -> void:
	if game_over:
		return
	
	lost = true
	num_balls = 0
	
	if is_instance_valid(winner_label):
		if winner_label.has_method("show_label"):
			winner_label.show_label("You Lose!")
		else:
			winner_label.text = "YOU LOSE"
			winner_label.visible = true
			winner_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	
	if is_instance_valid(opp_avatar_display):
		_show_win_burst(opp_avatar_display)

func _handle_game_over_i_won() -> void:
	if game_over:
		return
	
	num_balls = 0
	
	if is_instance_valid(winner_label):
		if winner_label.has_method("show_label"):
			winner_label.show_label("You Win!")
		else:
			winner_label.text = "YOU WIN!"
			winner_label.visible = true
			winner_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	
	if is_instance_valid(player_avatar_display):
		_show_win_burst(player_avatar_display)
	
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

func _process_game_state():
	if played_replay == false:
		if not replay_string.is_empty():
			var parsed_replay = parseReplay(replay_string)
			set_boards(parsed_replay)
			if is_my_turn:
				waiting_label.visible = false
				playReplay(parsed_replay)
				return
		else:
			if check_winner(): return
			if is_my_turn:
				waiting_label.visible = false
				camera.position = Vector3(0.0, 1.147, -1.73)
	elif is_my_turn:
		if check_winner(): return
		if len(replay_cups.cups_in_play) == 0:
			_show_redemption_label()
			redemption = true

	if check_winner(): return
	
	if is_my_turn:
		if current_ball == null:
			current_ball = spawn_ball()
		
		if throws.size() == 0 and num_balls > 0 and preview_ball == null:
			preview_ball = spawn_preview_ball()
		
func start_waiting_animation():
	if not is_instance_valid(waiting_label) or not is_instance_valid(waiting_blur) or not is_instance_valid(dot_timer):
		print("Warning: Waiting animation nodes are not valid.")
		return
	#if spectator_mode:
		#return

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
		
func _clear_active_balls() -> void:
	for child in get_children():
		if child is PongBall and child != ball:
			child.queue_free()
	
	current_ball = null
	ball_ready = false
	dragging = false
		
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

func _show_balls_back_label() -> void:
	if not is_instance_valid(balls_back_label):
		return
	
	if balls_back_tween and balls_back_tween.is_running():
		balls_back_tween.kill()
	
	balls_back_label.visible = true
	balls_back_label.modulate.a = 1.0
	
	balls_back_tween = create_tween().set_parallel(false)
	
	balls_back_tween.tween_interval(2.0)
	
	balls_back_tween.tween_property(balls_back_label, "modulate:a", 0.0, 0.5)
	
	balls_back_tween.tween_callback(func():
		if is_instance_valid(balls_back_label):
			balls_back_label.visible = false
			balls_back_label.modulate.a = 1.0
	)

func _show_redemption_label() -> void:
	if not is_instance_valid(redemption_label):
		return
	
	if redemption_tween and redemption_tween.is_running():
		redemption_tween.kill()
	
	redemption_label.visible = true
	redemption_label.modulate.a = 1.0
	
	redemption_tween = create_tween().set_parallel(false)
	
	redemption_tween.tween_interval(2.0)
	redemption_tween.tween_property(redemption_label, "modulate:a", 0.0, 0.5)
	
	redemption_tween.tween_callback(func():
		if is_instance_valid(redemption_label):
			redemption_label.visible = false
			redemption_label.modulate.a = 1.0
	)

func throw_finished():
	if len(throws) > 0 and len(throws) % 2 == 0:
		if throws[-1]["cup"] > -1 and throws[-2]["cup"] > -1:
			_show_balls_back_label()
			num_balls = 2
	
	if redemption:
		if throws[-1]["cup"] == -1:
			_handle_game_over_i_lost()
		elif len(my_cups.cups_in_play) == 0:
			my_cups.reset_cups([0,1,2])
			replay_cups.reset_cups([0,1,2])
			overtime_label.popup()
			await get_tree().create_timer(1.5).timeout
			num_balls = 0
	
	if num_balls > 0 and not game_over:
		if preview_ball != null and is_instance_valid(preview_ball):
			var b := preview_ball
			preview_ball = null
			
			b.freeze = true
			b.collision_layer = 0
			b.collision_mask = 0
			
			var tween := create_tween()
			tween.tween_property(
				b, "position", player_ball_start_pos, 0.35
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			
			tween.tween_callback(func():
				if is_instance_valid(b):
					b.freeze = false
					b.is_mine = true
					b.collision_layer = ball.collision_layer
					b.collision_mask = ball.collision_mask
					current_ball = b
					ball_ready = true
					num_balls -= 1
			)
		else:
			current_ball = spawn_ball()
	elif not game_over:
		if appPlugin:
			appPlugin.updateGameData(export_replay())
		else:
			print("No app plugin! " + export_replay())

func set_boards(parsed_replay: Dictionary):
	var my_board: Array
	var other_board: Array
	if player == 1:
		my_board = parsed_replay["p1_board"]
		other_board = parsed_replay["p2_board"]
	elif player == 2:
		my_board = parsed_replay["p2_board"]
		other_board = parsed_replay["p1_board"]
	my_cups.prev_cups = my_board
	my_cups.set_cups_in_play(my_board)
	replay_cups.set_cups_in_play(other_board)

func _set_game_data(new_replay: String):
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: " + str(parsed))
	
	is_my_turn = parsed["isYourTurn"]
	player = int(parsed["player"])
	replay_string = parsed["replay"] if "replay" in parsed else ""
	mode = parsed["mode"]
	winner = parsed["winner"] if "winner" in parsed else ""
	if winner != "":
		game_over = check_winner()
	var opponent_avatar_key = ""

	if is_my_turn:
		player = 2 if player == 1 else 1
		
	if player == 1:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"
		
	if opponent_avatar_key != "" and parsed.has(opponent_avatar_key):
		var avatar_string = parsed[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
		
		
	played_replay = false
	redemption = false
	num_balls = 2
	throws = []
		
	_process_game_state()
	print("Game Over: ", game_over, " Winner: ", winner )
	if not is_my_turn and not game_over:
		start_waiting_animation()
	else:
		stop_waiting_animation()

func export_board(exp_player: int):
	var board: Array
	if player == exp_player:
		board = my_cups.cups_in_play
	else:
		board = replay_cups.cups_in_play
	
	var result = ""
	for cup_idx in board:
		result += str(cup_idx)+","
	return result.substr(0, len(result)-1)
	
func export_replay() -> String:
	var replay_str = str("board:",start_replay_boards,"|")
	for move in throws:
		replay_str += "move:"+convert_replay(move["poses"])
		if move["cup"] > -1:
			replay_str += str(move["cup"])
		replay_str += "&24|"
	replay_str += str("board:",export_board(1),"&",export_board(2))
	var avatar_key := ("avatar1" if player == 1 else "avatar2")
	var export_data = {"replay": replay_str}
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		export_data[avatar_key] = player_avatar_display.get_avatar_data_string()
	if lost:
		game_over = true
		export_data["winner"] = my_uuid+"|-1"
	else:
		play_sent_animation()
	return JSON.stringify(export_data)

func convert_replay(poses: Array[Vector3]):
	var result: String = ""
	for pos in poses:
		result += conv(((-pos.x) + 3.0) / 6.0)
		result += conv((pos.y + 2.0) * 0.25)
		result += conv((((2.0 * -1.0 - pos.z) + 0.1) + 4.0) * 0.125)
	return result

func conv(input_float: float) -> String:
	var max_encoded_integer_value = CHARMAP_LEN * CHARMAP_LEN - 1
	var combined_idx_float = input_float * float(max_encoded_integer_value)

	var combined_idx = int(round(combined_idx_float))
	combined_idx = clamp(combined_idx, 0, max_encoded_integer_value)
	
	var first_idx: int = combined_idx / CHARMAP_LEN
	var second_idx: int = combined_idx % CHARMAP_LEN
	var char1: String = CHARMAP[first_idx]
	var char2: String = CHARMAP[second_idx]
	return char1 + char2
	
func convback(str: String) -> float:
	var first_idx = CHARMAP.find(str[0])
	var second_idx = CHARMAP.find(str[1])
	return float(second_idx + first_idx * CHARMAP_LEN) / float(CHARMAP_LEN * CHARMAP_LEN - 1)
	
func spawn_ball(is_replay: bool = false) -> RigidBody3D:
	var new_ball: PongBall = ball.duplicate()
	if is_replay:
		new_ball.position = replay_ball_start_pos
	else:
		new_ball.position = player_ball_start_pos
		new_ball.freeze = false
		new_ball.is_mine = true
		num_balls -= 1
		ball_ready = true

	add_child(new_ball)
	current_ball = new_ball
	return new_ball
	
func spawn_preview_ball() -> PongBall:
	var new_ball: PongBall = ball.duplicate()
	new_ball.position = player_ball_start_pos + second_ball_offset
	new_ball.freeze = true
	new_ball.is_mine = true
	new_ball.collision_layer = 0
	new_ball.collision_mask = 0
	
	add_child(new_ball)
	return new_ball
	
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
	
func parseReplay(replay: String) -> Dictionary:
	var result = {"moves": []}
	for elem in replay.split("|"):
		var spl = elem.split(":")
		if spl[0] == "board":
			if "p1_board" not in result:
				var boards = spl[1].split("&")
				result["p1_board"] = convert_arr(boards[0])
				result["p2_board"] = convert_arr(boards[1])
			else:
				start_replay_boards = spl[1]
		if spl[0] == "move":
			var move = []
			var move_spl = spl[1].split("&")[0]
			for idx in range(0, len(move_spl), 6):
				if idx+5 < len(move_spl):
					var x = convback(move_spl[idx] + move_spl[idx+1]) * 6.0 - 3.0
					var y = convback(move_spl[idx+2] + move_spl[idx+3]) * 4.0 - 2.0
					var z = convback(move_spl[idx+4] + move_spl[idx+5]) * 8.0 - 4.0
					move.append(Vector3(x, y, z))
			if len(move_spl) % 6 > 0:
				move.append(int(move_spl[-1]))
			result["moves"].append(move)
	return result
	
func playReplay(parsed: Dictionary):
	camera.position = Vector3(0.0, 1.147, -3.486)
	
	var moves = parsed["moves"]
	
	for idx in range(len(moves)):
		var move: Array = moves[idx]
		
		await get_tree().create_timer(1).timeout
		
		var new_ball = spawn_ball(true)
		
		var move_cleaned: Array = []
		if move.size() > 0:
			move_cleaned.append(move[0])
			for i in range(1, len(move) - 1):
				if move[i] is Vector3:
					if move[i].distance_squared_to(move_cleaned[-1]) > 0.001:
						move_cleaned.append(move[i])
			if move[-1] is int:
				move_cleaned.append(move[-1])
			else:
				move_cleaned.append(move[-1])

		if move_cleaned.size() == 0: continue

		new_ball.position = move_cleaned[0]
		
		var tween = create_tween()
		
		var current_pos: Vector3 = new_ball.position
		
		for i in range(len(move_cleaned)):
			var next_val = move_cleaned[i]
			if next_val is Vector3:
				var next_pos = next_val
				
				if current_pos.distance_to(next_pos) > 0.5:
					tween.tween_callback(func():
						new_ball.linear_velocity = Vector3(0.0, -1, -1)
						new_ball.freeze = false
					)
					break

				tween.tween_property(
					new_ball, "position", next_pos, REPLAY_FRAME_DURATION
				).set_trans(Tween.TRANS_LINEAR)
				current_pos = next_pos

		var is_final_move: bool = (idx + 1 == len(moves))
		tween.finished.connect(_on_replay_finished.bind(new_ball, move, is_final_move))
		
func _on_replay_finished(new_ball: PongBall, move: Array, final_move: bool):
	if move[-1] is int:
		var hit_cup = move[-1] + 1
		print("replay hit cup ", hit_cup, "!!!")
		replay_cups.remove_cup(hit_cup)
	new_ball.queue_free()
	
	if final_move:
		_clear_active_balls()
		
		await get_tree().create_timer(1).timeout
		
		var cam_tween = create_tween()
		cam_tween.tween_property(
			camera, "position", Vector3(0.0, 1.147, -1.73), 1.0
		).from(camera.position).set_trans(Tween.TRANS_SINE)
		cam_tween.play()
		
		await cam_tween.finished
		
		played_replay = true
		_process_game_state()
		
func convert_arr(str: String):
	var result = []
	if len(str) > 0:
		for elem in str.split(','):
			result.append(int(elem))
	return result

func _unhandled_input(event: InputEvent) -> void:
	if _settings_open:
		return

	if not ball_ready or current_ball == null:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			print("START DRAG: " + str(mb.position))
			drag_start_pos = mb.position
			drag_start_time = Time.get_ticks_msec() / 1000.0
			dragging = true
		else:
			if dragging:
				var drag_end_time: float = Time.get_ticks_msec() / 1000.0
				var drag_duration: float = max(drag_end_time - drag_start_time, 0.016)

				var drag_end_pos: Vector2 = mb.position
				var drag_distance: float = drag_end_pos.distance_to(drag_start_pos)

				# --- store debug info ---
				last_drag_distance = drag_distance
				last_drag_duration = drag_duration
				var t: float = max(drag_duration, 0.0001)
				var raw_dx: float = drag_end_pos.x - drag_start_pos.x
				var raw_dy: float = drag_end_pos.y - drag_start_pos.y
				last_drag_speed_x = raw_dx / t          # px/s
				last_drag_speed_y = raw_dy / t          # px/s (screen-space)
				# -------------------------

				if drag_distance < min_drag_distance:
					print("Tap detected, ignoring throw.")
					dragging = false
					return

				print("END DRAG: " + str(mb.position))
				var delta: Vector2 = drag_end_pos - drag_start_pos
				delta.y = -delta.y

				print("X delta: " + str(delta.x) + ", Y delta: " + str(delta.y))
				var delta_lerp: Vector2 = interpolate_delta(delta.x, delta.y, drag_duration)
				print("Delta interpolated: " + str(delta_lerp) + " duration: " + str(drag_duration))

				if delta_lerp == Vector2.ZERO:
					print("Too slow flick, ignoring throw.")
					dragging = false
					return

				current_ball.throw(delta_lerp.x, delta_lerp.y)

				dragging = false
				ball_ready = false
				current_ball = null

func interpolate_delta(x_delta: float, y_delta: float, duration: float) -> Vector2:
	var t: float = max(duration, 0.016)
	var vx: float = x_delta / t
	var vy: float = y_delta / t

	var speed_x: float = abs(vx)
	var speed_y: float = abs(vy)

	if speed_x < min_speed_for_throw and speed_y < min_speed_for_throw:
		return Vector2.ZERO

	var norm_vx: float = clamp(speed_x / max_throw_speed_x, 0.0, 1.0)
	var norm_vy: float = clamp(speed_y / max_throw_speed_y, 0.0, 1.0)

	var x_curve: float = pow(norm_vx, horizontal_power_curve)
	var y_curve: float = pow(norm_vy, vertical_power_curve)

	var x_force_mag: float = lerp(0.0, max_force_x, x_curve) * throw_power_scale
	var y_force_mag: float = lerp(0.0, max_force_y, y_curve) * throw_power_scale

	var x_sign: float = sign(x_delta)
	var y_sign: float = sign(y_delta)

	return Vector2(x_sign * x_force_mag, y_sign * y_force_mag)

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
		_settings_open = false
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
		if is_instance_valid(dim):
			dim.queue_free()
	)
	settings_popup_script.settings_theme_selected.connect(_on_theme_changed)

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

func _on_theme_changed(_new_theme_name: String) -> void:
	pass

func _load_game_specific_settings() -> void:
	var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	print("Loaded game-specific settings for ", game_settings_category, ": volume=", saved_volume, " debug=", show_debug_info)
