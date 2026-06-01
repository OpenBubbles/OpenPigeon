extends Node3D
class_name PongGame

#---------------------------------------------
var _debug_perf := false
var _debug_label: Label

var _frame_accum := 0.0
var _frame_count := 0
var _max_delta := 0.0
#---------------------------------------------

var REPLAY_FRAME_DURATION: float = 0.03
var CHARMAP = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789~!@*()_+-.';"
var CHARMAP_LEN = len(CHARMAP)
const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")
const MUSIC_STREAM := preload("res://global/audio/pong.ogg")

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
@onready var spectator_label: Label = %SpecLabel

@export var show_overlay: bool = true

var appPlugin: Object
var mediaPlugin = null
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
var _current_seed: int = 0

var my_uuid: String = ""
var game_over: bool = false


var start_replay_boards: String = "0,1,2,3,4,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9"

@export var replay_ball_start_pos: Vector3 = Vector3(0.0, -0.574, -0.80)
@export var player_ball_start_pos: Vector3 = Vector3(0.0, -0.55, -1.00)
@export var second_ball_offset: Vector3 = Vector3(0.28, 0.0, 0.0)

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
var ball_popo: Vector3 = Vector3.ZERO   # ball position at touch-down

const IOS_H_SCALE: float = 0.65          # horizontal scale before distance
const IOS_POWER_SLOPE: float = -5.7      # distance -> forward force
const IOS_POWER_FLOOR: float = -3.85     # max forward force magnitude
const IOS_X_NORM: float = 3.62           # X-target normalizer
const IOS_X_GAIN: float = 2.08           # 1.3 * 1.6
const IOS_Z_NORM: float = -3.62
const IOS_Z_BIAS: float = -1.05
const IOS_Z_GAIN: float = 1.3
const IOS_Z_SPLIT: float = -2.0          # threshold: long vs short arc branch
const IOS_LONG_GAIN: float = 1.3
const IOS_LONG_Y: float = 4.12
const IOS_SHORT_GAIN: float = 1.35
const IOS_SHORT_Y_OFFSET: float = -3.0
const IOS_BALL_Y_AIM_OFFSET: float = 0.45
const IOS_DRAG_DEAD_DIST: float = 0.18

# Aim-assist lerp toward the nearest cup, matching the typical case
@export var ios_aim_assist: float = 0.28
# Screen-pixel -> world-meter conversion. Tune up for easier throws
@export var ios_screen_to_world_scale: float = 0.0030

var player: int
var is_my_turn: int
var replay_string: String
var mode: String
var spectator_mode: bool = false

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
		
	if Engine.has_singleton("OpenPigeonMedia"):
		mediaPlugin = Engine.get_singleton("OpenPigeonMedia")
		print("OpenPigeonMedia plugin is available")
	else:
		print("OpenPigeonMedia plugin is not available")

	_start_music()
	
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
		#_set_game_data('{"isYourTurn":true,"skip_score1":"0","skip_score2":"0","player":"1","replay":"board:0,1,3,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9|move:K;AEDSLaDmDeLcFACRLdHyCjLeJgBXLgKVBpLhL;A3LiNjAvLjOez9LlO7zBLmPyy_LnPWyILoP5ybLqP0xQLrPFxjLsO-wYLtOtwrLvNCv6LwMxvALxLdu)LyJQuJLzH)udLBGdtTLCD;tnK\'C;tHLgC9tALsCYtxLhCItZK;CstFK*B7tsK(ButuK;A_tFLeA_tOLhA_tOLhA_tNLhA_tN0&24,27,31|move:K;AEDSK-C-DhK)FlCVK@HkCmK9I_B0K6KLBsK3L@A6K0NcAyKXN;z@KVO2zFKSPvy.KPPVyMKMP5yeKJP1xTKGPIxmKDO;w1KBOzwvKyNJv~KvMFvDKsLmu.KpJ1uMKnIfugKkGrtWKhEotqKgDhtHKgC uxKgCPvnKhB;wcKhBqw(KhAsx3KhBoyQKhB3zCKiCgAoKiCqBaKiCmB8KiB(CTKiBGDEKjA5EqKjA3E;KjBpF4&24,29,38|board:1,3,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9","score1":"0","score2":"0","num":"2","game":"beer","mode":"h","seed":"-1429210425","round":"1","seed2":"0"}')
		_set_game_data('{"isYourTurn":true,"skip_score1":"0","skip_score2":"0","player":"2","score1":"0","score2":"0","num":"1","game":"beer","mode":"h","seed":"-472793889","seed2":"0"}')
	if _debug_perf:
		_create_debug_overlay()
	_enforce_mobile_lighting_settings()
	
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
	
func _enforce_mobile_lighting_settings() -> void:
	if is_instance_valid(camera):
		camera.near = 0.1
		camera.far = 20.0

	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.use_debanding = true
	vp.positional_shadow_atlas_size = 2048
	vp.positional_shadow_atlas_quad_0 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
	vp.positional_shadow_atlas_quad_1 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED
	vp.positional_shadow_atlas_quad_2 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED
	vp.positional_shadow_atlas_quad_3 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED

	if is_instance_valid(sun):
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 6.0
		sun.directional_shadow_fade_start = 0.95
		sun.directional_shadow_blend_splits = false
		sun.shadow_bias = 0.1
		sun.shadow_normal_bias = 2.0
		sun.shadow_blur = 2.0
		sun.shadow_opacity = 0.85

	if is_instance_valid(env) and env.environment != null:
		var e: Environment = env.environment
		e.ssao_enabled = false
		e.ssil_enabled = false
		e.sdfgi_enabled = false
		e.glow_enabled = false
		e.fog_enabled = false
		e.volumetric_fog_enabled = false
		if e.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED:
			e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			e.ambient_light_color = Color(0.6, 0.6, 0.65)
			e.ambient_light_energy = 0.35

	_stabilized_mats.clear()
	_stabilize_geometry(self)

	Engine.physics_jitter_fix = 0.5

var _stabilized_mats: Dictionary = {}

func _stabilize_geometry(root: Node) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			var gi: GeometryInstance3D = child
			gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

			var mesh: Mesh = null
			if gi is MeshInstance3D:
				mesh = (gi as MeshInstance3D).mesh
			elif gi is CSGMesh3D:
				mesh = (gi as CSGMesh3D).mesh

			if mesh != null:
				for s in range(mesh.get_surface_count()):
					var src_mat: Material = mesh.surface_get_material(s)
					if src_mat == null or not (src_mat is BaseMaterial3D):
						continue
					var key: String = str(src_mat.get_instance_id()) + "_" + str(s)
					var new_mat: BaseMaterial3D
					if _stabilized_mats.has(key):
						new_mat = _stabilized_mats[key]
					else:
						new_mat = (src_mat as BaseMaterial3D).duplicate()
						new_mat.metallic_specular = 0.0
						_stabilized_mats[key] = new_mat
					mesh.surface_set_material(s, new_mat)
		_stabilize_geometry(child)


func _apply_static_geometry_hints(root: Node) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			var gi: GeometryInstance3D = child
			gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_apply_static_geometry_hints(child)
		
func _create_debug_overlay() -> void:
	if not _debug_perf:
		return
	
	var parent: Node = get_tree().root
	if is_instance_valid(main_overlay):
		parent = main_overlay
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
		var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var render_objects := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var render_primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
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
			"Balls: %d"
		) % [
			fps,
			avg_ms,
			max_ms,
			mem_static_mb,
			draw_calls,
			render_objects,
			render_primitives,
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
		GameUtils._show_win_burst(opp_avatar_display)

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
		GameUtils._show_win_burst(player_avatar_display)
	
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
	
func _generate_random_cup_positions(seed_value: int) -> Array:
	var rng := Drand48.new()
	rng.srand48(seed_value)

	const TARGET_COUNT: int = 10
	const MIN_DIST: float = 0.136
	const X_BASE: float = -0.426
	const X_SCALE: float = 0.852
	const Z_BASE: float = -1.907
	const Z_SCALE: float = -0.4207
	const Y_FIXED: float = -0.597

	var positions: Array = []
	var max_attempts: int = 5000

	while positions.size() < TARGET_COUNT and max_attempts > 0:
		max_attempts -= 1
		var rx: float = rng.drand48()
		var rz: float = rng.drand48()
		var x: float = X_BASE + X_SCALE * rx
		var z: float = Z_BASE + Z_SCALE * rz

		var ok: bool = true
		for p in positions:
			var dx: float = p.x - x
			var dz: float = p.z - z
			if sqrt(dx * dx + dz * dz) < MIN_DIST:
				ok = false
				break

		if ok:
			positions.append(Vector3(x, Y_FIXED, z))

	return positions
	
func _apply_mode_board_layout() -> void:
	if mode == "h":
		var seed_value: int = _current_seed
		var positions: Array = _generate_random_cup_positions(seed_value)
		
		print("=== Random cup positions for seed %d ===" % seed_value)
		var min_x := 999.0; var max_x := -999.0
		var min_z := 999.0; var max_z := -999.0
		for i in range(positions.size()):
			var p: Vector3 = positions[i]
			print("  [%d] x=%.4f y=%.4f z=%.4f" % [i, p.x, p.y, p.z])
			min_x = min(min_x, p.x); max_x = max(max_x, p.x)
			min_z = min(min_z, p.z); max_z = max(max_z, p.z)
		print("  bounds: x=[%.3f, %.3f] z=[%.3f, %.3f]" % [min_x, max_x, min_z, max_z])
		print("  normal-mode bounds: x=[-0.142, 0.142] z=[-2.207, -1.967]")

		my_cups.mirror_x = false
		replay_cups.mirror_x = true
		my_cups.apply_random_positions(positions)
		replay_cups.apply_random_positions(positions)

		my_cups.set_cups_in_play(my_cups.cups_in_play)
		replay_cups.set_cups_in_play(replay_cups.cups_in_play)
	else:
		my_cups.random_positions.clear()
		replay_cups.random_positions.clear()
		my_cups.arrangeCups()
		replay_cups.arrangeCups()
		
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
		
func _clear_active_balls() -> void:
	for child in get_children():
		if child is PongBall and child != ball:
			child.queue_free()
	
	current_ball = null
	ball_ready = false
	dragging = false
		
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
			if mode != "h":
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

	# Random mode:
	if mode == "h":
		var seed_value: int = int(parsed_replay.get("seed", 0))
		# Fall back to the default seed from _set_game_data if needed
		if seed_value == 0 and _current_seed != 0:
			seed_value = _current_seed
		var positions: Array = _generate_random_cup_positions(seed_value)
		my_cups.mirror_x = false
		replay_cups.mirror_x = true
		my_cups.apply_random_positions(positions)
		replay_cups.apply_random_positions(positions)
	else:
		# Normal mode
		my_cups.random_positions.clear()
		replay_cups.random_positions.clear()

	my_cups.prev_cups = my_board
	my_cups.set_cups_in_play(my_board)
	replay_cups.set_cups_in_play(other_board)

var my_player
func _set_game_data(new_replay: String):
	var parsed = JSON.parse_string(new_replay)
	print("NEW REPLAY: " + str(parsed))
	
	is_my_turn = parsed["isYourTurn"]
	player = int(parsed["player"])
	replay_string = parsed["replay"] if "replay" in parsed else ""
	mode = parsed["mode"]
	_current_seed = int(parsed.get("seed", "0"))
	_apply_mode_board_layout()
	winner = parsed["winner"] if "winner" in parsed else ""
	if winner != "":
		game_over = check_winner()
	var opponent_avatar_key = ""
	my_player = parsed.get("myPlayerId", "")
	var p1_id: String = parsed.get("player1", "")
	var p2_id: String = parsed.get("player2", "")
	spectator_mode = my_player != "" and p1_id != "" and p2_id != "" and my_player != p1_id and my_player != p2_id
	if is_instance_valid(spectator_label):
		spectator_label.visible = spectator_mode
	if is_my_turn and not spectator_mode:
		player = 2 if player == 1 else 1
	elif spectator_mode: player = 1
		
	if player == 1 or spectator_mode:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"
		
	if opponent_avatar_key != "" and parsed.has(opponent_avatar_key):
		var avatar_string = parsed[opponent_avatar_key]
		var opponent_data = GameUtils._parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
	if spectator_mode:
		var p1_data = GameUtils._parse_avatar_string(parsed["avatar1"])
		if is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", p1_data)
		
		
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
	
func convback(enc: String) -> float:
	var first_idx = CHARMAP.find(enc[0])
	var second_idx = CHARMAP.find(enc[1])
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
		
func convert_arr(csv: String):
	var result = []
	if len(csv) > 0:
		for elem in csv.split(','):
			result.append(int(elem))
	return result

func _unhandled_input(event: InputEvent) -> void:
	if _settings_open or spectator_mode or not ball_ready or current_ball == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			ball_popo = current_ball.global_position
			drag_start_pos = mb.position
			dragging = true
		elif dragging:
			dragging = false
			_ios_throw_release(mb.position)
			
func _screen_drag_to_world_delta(screen_start: Vector2, screen_end: Vector2) -> Vector2:
	var sdx: float = screen_end.x - screen_start.x
	var sdy: float = screen_end.y - screen_start.y
	return Vector2(-sdx * ios_screen_to_world_scale, -sdy * ios_screen_to_world_scale)
	
func _ios_throw_release(release_screen_pos: Vector2) -> void:
	if current_ball == null:
		return

	var screen_delta: Vector2 = release_screen_pos - drag_start_pos
	var dx_world: float = -screen_delta.x * ios_screen_to_world_scale
	var dz_world: float = -screen_delta.y * ios_screen_to_world_scale
	var drag_len: float = sqrt(dx_world * dx_world + dz_world * dz_world)
	if drag_len < IOS_DRAG_DEAD_DIST:
		ball_ready = true   # let the player try again
		return

	# Forward force from drag distance
	var scaled_dx: float = dx_world * IOS_H_SCALE
	var dist: float = sqrt(scaled_dx * scaled_dx + dz_world * dz_world) * 0.9   # ratio=1.0 case
	var forward_force: float = max(dist * IOS_POWER_SLOPE, IOS_POWER_FLOOR)
	var abs_force: float = abs(forward_force)

	# Preaim X/Z targets
	var angle_factor: float = (dx_world / drag_len) if drag_len > 1e-6 else 0.0
	var fx_target: float = abs_force / IOS_X_NORM * IOS_X_GAIN * angle_factor
	var ios_fz_target: float = IOS_Z_BIAS + (abs_force / IOS_Z_NORM) * IOS_Z_GAIN
	var forward_z_target: float = ball_popo.z + (abs(ios_fz_target) - abs(IOS_Z_BIAS))

	# Aim assist
	var target_cup: Vector3 = _ios_find_nearest_cup_xz(current_ball.global_position)
	var final_x: float = lerp(fx_target, target_cup.x, ios_aim_assist)
	var final_z: float = lerp(forward_z_target, target_cup.z, ios_aim_assist)

	# Long vs short arc branch
	var ball_pos: Vector3 = current_ball.global_position
	var fx_impulse: float
	var fy_impulse: float
	var fz_impulse: float
	if ios_fz_target <= IOS_Z_SPLIT:
		fx_impulse = (final_x - ball_pos.x) * IOS_LONG_GAIN
		fy_impulse = IOS_LONG_Y
		fz_impulse = (final_z - ball_pos.z) * IOS_LONG_GAIN
	else:
		fx_impulse = (final_x - ball_pos.x) * IOS_SHORT_GAIN
		fy_impulse = 4.0 * ((abs(final_z) - 1.05) / -7.2 + 1.0) + IOS_SHORT_Y_OFFSET
		fz_impulse = (final_z - ball_pos.z) * IOS_SHORT_GAIN

	# Fire
	var thrown_ball: PongBall = current_ball
	thrown_ball.freeze = false
	thrown_ball.apply_impulse(Vector3(fx_impulse, fy_impulse, fz_impulse))
	thrown_ball.thrown = true
	ball_ready = false
	current_ball = null
	_watch_ios_ball_until_finished(thrown_ball)
	
func _watch_ios_ball_until_finished(b: PongBall) -> void:
	var min_wait_time: float = 1.0
	var max_wait_time: float = 5.0
	var still_time: float = 0.0
	var elapsed: float = 0.0

	while is_instance_valid(b):
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

		if elapsed < min_wait_time:
			continue

		var speed := b.linear_velocity.length()
		var too_slow := speed < 0.08
		var out_of_play := b.global_position.y < -1.2 or b.global_position.z > 0.75 or b.global_position.z < -2.6

		if too_slow:
			still_time += 0.1
		else:
			still_time = 0.0

		if still_time >= 0.4 or out_of_play or elapsed >= max_wait_time:
			if is_instance_valid(b):
				b.remove()
			else:
				throw_finished()
			return

func _ios_find_nearest_cup_xz(ball_pos: Vector3) -> Vector3:
	var probe: Vector3 = ball_pos + Vector3(0.0, IOS_BALL_Y_AIM_OFFSET, 0.0)
	var best: Vector3 = ball_pos + Vector3(0.0, 0.0, -2.0)
	var best_d: float = INF
	if not is_instance_valid(my_cups):
		return best
	for cup in my_cups.get_children():
		if cup == null or not (cup is Node3D):
			continue
		if cup.name == &"cupremoved" or not (cup as Node3D).visible:
			continue
		var p: Vector3 = (cup as Node3D).global_position
		var d: float = probe.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best
	
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
