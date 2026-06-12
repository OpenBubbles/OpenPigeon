extends BaseGame3D
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
const MUSIC_STREAM := preload("res://global/audio/pong.ogg")

const LOG_TAG := "Cup Pong"
const DEBUG_PONG := false

func dbg(parts: Variant) -> void:
	if DEBUG_PONG:
		OpLog.d(LOG_TAG, parts)

func _cup_summary(cups: Cups) -> String:
	if not is_instance_valid(cups):
		return "invalid"

	return "name=%s inPlay=%s count=%d random=%d mirrorX=%s" % [
		cups.name,
		str(cups.cups_in_play),
		cups.cups_in_play.size(),
		cups.random_positions.size(),
		str(cups.mirror_x)
	]

func _replay_move_count(value: String) -> int:
	if value.is_empty():
		return 0
	return value.count("move:")

@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var winner_label: Label = %WinLossLabel
@onready var balls_back_label: Label = %ballsBackLabel
@onready var redemption_label: Label = %redemptionLabel
@onready var overtime_label: Label = %overtimeLabel
@onready var sent_label: Label = %SentLabel
@onready var main_overlay: Control = %MainOverlay
@onready var sun: DirectionalLight3D = $DirectionalLight3D1
@onready var env: WorldEnvironment = $WorldEnvironment
@onready var spectator_label: Label = %SpecLabel

@export var show_overlay: bool = true

var screen_size: Vector2
var balls_back_tween: Tween
var sent_tween: Tween
var redemption_tween: Tween

var camera: Camera3D
var ball: RigidBody3D
var my_cups: Cups
var replay_cups: Cups
var current_ball: PongBall
var winner: String = ""
var _current_seed: int = 0

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
var _stabilized_mats: Dictionary = {}

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
const IOS_DRAG_DEAD_DIST: float = 0.06

# iOS seems to use about 0.21 to 0.31 depending on player/cup state.
# Keep this slightly generous for our version.
@export var ios_aim_assist: float = 0.20

# Screen-pixel -> world-meter conversion.
@export var ios_screen_to_world_scale: float = 0.0030

var player: int
var is_my_turn: int
var replay_string: String
var mode: String

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM

func _get_dev_data() -> String:
	return '{"isYourTurn":true,"skip_score1":"0","skip_score2":"0","player":"2","score1":"0","score2":"0","num":"1","game":"beer","mode":"h","seed":"-472793889","seed2":"0"}'

func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Cup Pong"

func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	screen_size = get_viewport().get_visible_rect().size

	if is_instance_valid(main_overlay):
		main_overlay.visible = show_overlay

	my_cups = get_node_or_null("cups2") as Cups
	replay_cups = get_node_or_null("cups1") as Cups
	camera = get_node_or_null("Camera3D") as Camera3D
	ball = get_node_or_null("ball") as RigidBody3D

	if _debug_perf:
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
	
	OpLog.i(LOG_TAG, [
		"game_ready screen=", screen_size,
		" myCups=", is_instance_valid(my_cups),
		" replayCups=", is_instance_valid(replay_cups),
		" camera=", is_instance_valid(camera),
		" ball=", is_instance_valid(ball)
	])

func _set_game_data(new_replay: String):
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", new_replay])

	var parsed = JSON.parse_string(new_replay)
	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, ["set_game_data invalid JSON raw=", new_replay])
		return

	dbg(["set_game_data parsed=", parsed])
	
	if not is_instance_valid(my_cups):
		my_cups = get_node_or_null("cups2") as Cups
	if not is_instance_valid(replay_cups):
		replay_cups = get_node_or_null("cups1") as Cups
	if not is_instance_valid(camera):
		camera = get_node_or_null("Camera3D") as Camera3D
	if not is_instance_valid(ball):
		ball = get_node_or_null("ball") as RigidBody3D

	if not is_instance_valid(my_cups) or not is_instance_valid(replay_cups):
		OpLog.w(LOG_TAG, [
			"set_game_data deferred missing nodes myCups=", is_instance_valid(my_cups),
			" replayCups=", is_instance_valid(replay_cups)
		])
		call_deferred("_set_game_data", new_replay)
		return
	
	is_my_turn = parsed["isYourTurn"]
	player = int(parsed["player"])
	replay_string = parsed["replay"] if "replay" in parsed else ""
	mode = parsed["mode"]
	_current_seed = int(parsed.get("seed", "0"))
	
	if mode == "h":
		var seed_value: int = _current_seed
		var positions: Array = _generate_random_cup_positions(seed_value)

		var min_x := 999.0
		var max_x := -999.0
		var min_z := 999.0
		var max_z := -999.0

		for p: Vector3 in positions:
			min_x = min(min_x, p.x)
			max_x = max(max_x, p.x)
			min_z = min(min_z, p.z)
			max_z = max(max_z, p.z)

		dbg([
			"random_cups seed=", seed_value,
			" count=", positions.size(),
			" boundsX=", Vector2(min_x, max_x),
			" boundsZ=", Vector2(min_z, max_z)
		])

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
		
	winner = parsed["winner"] if "winner" in parsed else ""
	if winner != "":
		game_over = check_winner()
	var opponent_avatar_key = ""
	var p1_id: String = parsed.get("player1", "")
	var p2_id: String = parsed.get("player2", "")
	spectator_mode = my_uuid != "" and p1_id != "" and p2_id != "" and my_uuid != p1_id and my_uuid != p2_id
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
	if spectator_mode and parsed.has("avatar1"):
		var p1_data = GameUtils._parse_avatar_string(parsed["avatar1"])
		if is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", p1_data)
		
		
	played_replay = false
	redemption = false
	num_balls = 2
	throws = []
		
	OpLog.i(LOG_TAG, [
		"set_game_data parsed turn=", is_my_turn,
		" player=", player,
		" mode=", mode,
		" seed=", _current_seed,
		" spectator=", spectator_mode,
		" replayLen=", replay_string.length(),
		" replayMoves=", _replay_move_count(replay_string),
		" winner=", winner
	])

	_process_game_state()

	OpLog.i(LOG_TAG, [
		"set_game_data_done gameOver=", game_over,
		" lost=", lost,
		" numBalls=", num_balls,
		" redemption=", redemption,
		" myCups={", _cup_summary(my_cups), "}",
		" replayCups={", _cup_summary(replay_cups), "}"
	])

	if not is_my_turn and not game_over and not spectator_mode:
		start_waiting_animation()
	else:
		stop_waiting_animation()

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
			OpLog.w(LOG_TAG, [
				"long_frame maxMs=", max_ms,
				" fps=", fps,
				" drawCalls=", draw_calls,
				" objects=", render_objects,
				" primitives=", render_primitives,
				" balls=", ball_count,
				" turn=", is_my_turn,
				" playedReplay=", played_replay
			])
		
		_frame_accum = 0.0
		_frame_count = 0
		_max_delta = 0.0

func check_winner() -> bool:
	if game_over:
		return true

	if winner.is_empty():
		return false

	var parts := winner.split("|", false)
	if parts.size() < 2:
		OpLog.w(LOG_TAG, ["winner malformed raw=", winner])
		return false

	var sender_uuid := String(parts[0])
	var result := String(parts[1])

	if result == "0":
		game_over = true
		num_balls = 0
		ball_ready = false
		current_ball = null
		stop_waiting_animation()

		if is_instance_valid(winner_label):
			winner_label.text = "DRAW!"
			winner_label.visible = true
			winner_label.add_theme_color_override("font_color", Color(1, 1, 1))
	elif sender_uuid == my_uuid:
		if result == "1":
			_handle_game_over_i_won()
		else:
			_handle_game_over_i_lost()
	else:
		if result == "1":
			_handle_game_over_i_lost()
		else:
			_handle_game_over_i_won()

	return true

func _handle_game_over_i_lost() -> void:
	if game_over:
		return

	OpLog.i(LOG_TAG, ["game_end result=lose winner=", winner])

	game_over = true
	lost = true
	num_balls = 0
	ball_ready = false
	current_ball = null
	stop_waiting_animation()

	if is_instance_valid(winner_label):
		winner_label.text = "YOU LOSE"
		winner_label.visible = true
		winner_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

	if is_instance_valid(opp_avatar_display):
		GameUtils._show_win_burst(opp_avatar_display)

func _handle_game_over_i_won() -> void:
	if game_over:
		return

	OpLog.i(LOG_TAG, ["game_end result=win winner=", winner])

	game_over = true
	num_balls = 0
	ball_ready = false
	current_ball = null
	stop_waiting_animation()

	if is_instance_valid(winner_label):
		winner_label.text = "YOU WIN!"
		winner_label.visible = true
		winner_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

	if is_instance_valid(player_avatar_display):
		GameUtils._show_win_burst(player_avatar_display)

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

		if not game_over and not spectator_mode:
			is_my_turn = false
			start_waiting_animation()
		else:
			stop_waiting_animation()
	)

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

func _process_game_state():
	OpLog.i(LOG_TAG, [
		"process_state_start turn=", is_my_turn,
		" playedReplay=", played_replay,
		" replayMoves=", _replay_move_count(replay_string),
		" gameOver=", game_over,
		" numBalls=", num_balls,
		" redemption=", redemption
	])
	if played_replay == false:
		if not replay_string.is_empty():
			var parsed_replay := {"moves": []}

			for elem in replay_string.split("|"):
				var spl = elem.split(":")
				if spl.size() < 2:
					continue

				if spl[0] == "board":
					if "p1_board" not in parsed_replay:
						var boards = spl[1].split("&")
						var p1_board := []
						var p2_board := []

						if boards.size() > 0 and len(boards[0]) > 0:
							for cup_id in boards[0].split(","):
								p1_board.append(int(cup_id))

						if boards.size() > 1 and len(boards[1]) > 0:
							for cup_id in boards[1].split(","):
								p2_board.append(int(cup_id))

						parsed_replay["p1_board"] = p1_board
						parsed_replay["p2_board"] = p2_board
					else:
						start_replay_boards = spl[1]

				if spl[0] == "move":
					var move = []
					var move_spl = spl[1].split("&")[0]

					for idx in range(0, len(move_spl), 6):
						if idx + 5 < len(move_spl):
							var x = convback(move_spl[idx] + move_spl[idx + 1]) * 6.0 - 3.0
							var y = convback(move_spl[idx + 2] + move_spl[idx + 3]) * 4.0 - 2.0
							var z = convback(move_spl[idx + 4] + move_spl[idx + 5]) * 8.0 - 4.0
							move.append(Vector3(x, y, z))

					if len(move_spl) % 6 > 0:
						move.append(int(move_spl[-1]))

					parsed_replay["moves"].append(move)
					dbg(["parsed_replay_move index=", parsed_replay["moves"].size() - 1, " points=", move.size()])

			var my_board: Array
			var other_board: Array

			if player == 1:
				my_board = parsed_replay["p1_board"]
				other_board = parsed_replay["p2_board"]
			else:
				my_board = parsed_replay["p2_board"]
				other_board = parsed_replay["p1_board"]
				
			OpLog.i(LOG_TAG, [
				"replay_parsed moves=", parsed_replay["moves"].size(),
				" myBoard=", my_board,
				" otherBoard=", other_board,
				" player=", player
			])

			if mode == "h":
				var seed_value: int = int(parsed_replay.get("seed", 0))
				if seed_value == 0 and _current_seed != 0:
					seed_value = _current_seed

				var positions: Array = _generate_random_cup_positions(seed_value)
				my_cups.mirror_x = false
				replay_cups.mirror_x = true
				my_cups.apply_random_positions(positions)
				replay_cups.apply_random_positions(positions)
			else:
				my_cups.random_positions.clear()
				replay_cups.random_positions.clear()

			my_cups.prev_cups = my_board
			my_cups.set_cups_in_play(my_board)
			replay_cups.set_cups_in_play(other_board)

			if is_my_turn:
				stop_waiting_animation()
				playReplay(parsed_replay)
				return
		else:
			if check_winner():
				return
			if is_my_turn:
				stop_waiting_animation()
				camera.position = Vector3(0.0, 1.147, -1.73)
	elif is_my_turn:
		if check_winner():
			return

		if len(replay_cups.cups_in_play) == 0:
			if is_instance_valid(redemption_label):
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

			redemption = true

	if check_winner():
		return

	if is_my_turn:
		if current_ball == null:
			current_ball = spawn_ball()

		if throws.size() == 0 and num_balls > 0 and preview_ball == null:
			var new_ball: PongBall = ball.duplicate()
			new_ball.position = player_ball_start_pos + second_ball_offset
			new_ball.freeze = true
			new_ball.is_mine = true
			new_ball.collision_layer = 0
			new_ball.collision_mask = 0

			add_child(new_ball)
			preview_ball = new_ball

	OpLog.i(LOG_TAG, [
		"process_state_done turn=", is_my_turn,
		" playedReplay=", played_replay,
		" ballReady=", ball_ready,
		" numBalls=", num_balls,
		" throws=", throws.size(),
		" myCups={", _cup_summary(my_cups), "}",
		" replayCups={", _cup_summary(replay_cups), "}"
	])

func throw_finished():
	OpLog.i(LOG_TAG, [
		"throw_finished throws=", throws.size(),
		" lastCup=", throws[-1]["cup"] if throws.size() > 0 else "none",
		" numBalls=", num_balls,
		" redemption=", redemption,
		" myCups=", my_cups.cups_in_play if is_instance_valid(my_cups) else []
	])
	
	if len(throws) > 0 and len(throws) % 2 == 0:
		if throws[-1]["cup"] > -1 and throws[-2]["cup"] > -1:
			if is_instance_valid(balls_back_label):
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

			num_balls = 2

	if redemption:
		if throws[-1]["cup"] == -1:
			lost = true
			var outgoing := export_replay()
			_handle_game_over_i_lost()
			OpLog.event(LOG_TAG, ["send_game_out redemption_loss raw=", outgoing])
			send_game_data(outgoing)
			return
		elif len(my_cups.cups_in_play) == 0:
			if mode != "h":
				my_cups.reset_cups([0, 1, 2])
				replay_cups.reset_cups([0, 1, 2])
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
		var outgoing := export_replay()
		OpLog.event(LOG_TAG, ["send_game_out turn_end raw=", outgoing])
		send_game_data(outgoing)
		is_my_turn = false
		ball_ready = false
		current_ball = null
		dragging = false

		if not game_over:
			play_sent_animation()

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
	var replay_str = str("board:", start_replay_boards, "|")

	for move in throws:
		var converted := ""

		for pos in move["poses"]:
			converted += conv(((-pos.x) + 3.0) / 6.0)
			converted += conv((pos.y + 2.0) * 0.25)
			converted += conv((((2.0 * -1.0 - pos.z) + 0.1) + 4.0) * 0.125)

		replay_str += "move:" + converted

		if move["cup"] > -1:
			replay_str += str(move["cup"])

		replay_str += "&24|"

	replay_str += str("board:", export_board(1), "&", export_board(2))

	var avatar_key := ("avatar1" if player == 1 else "avatar2")
	var export_data = {"replay": replay_str}

	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		export_data[avatar_key] = player_avatar_display.get_avatar_data_string()

	if lost:
		export_data["winner"] = my_uuid + "|-1"

	var out_json := JSON.stringify(export_data)
	OpLog.event(LOG_TAG, [
		"export_replay_out throws=", throws.size(),
		" lost=", lost,
		" replayMoves=", _replay_move_count(replay_str),
		" replayLen=", replay_str.length(),
		" raw=", out_json
	])
	return out_json

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
	dbg([
		"spawn_ball replay=", is_replay,
		" pos=", new_ball.position,
		" numBalls=", num_balls,
		" ballReady=", ball_ready
	])
	return new_ball

func playReplay(parsed: Dictionary):
	camera.position = Vector3(0.0, 1.147, -3.486)
	
	var moves = parsed["moves"]
	
	OpLog.i(LOG_TAG, [
		"play_replay_start moves=", moves.size(),
		" p1Board=", parsed.get("p1_board", []),
		" p2Board=", parsed.get("p2_board", [])
	])
	
	for idx in range(len(moves)):
		var move: Array = moves[idx]
		dbg(["play_replay_move index=", idx, " rawPoints=", move.size()])
		
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

		if move_cleaned.size() == 0:
			OpLog.w(LOG_TAG, ["play_replay skipped empty move index=", idx])
			continue

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
		OpLog.i(LOG_TAG, ["replay_hit_cup cup=", hit_cup])
		replay_cups.remove_cup(hit_cup)

	new_ball.queue_free()

	if final_move:
		for child in get_children():
			if child is PongBall and child != ball:
				child.queue_free()

		current_ball = null
		ball_ready = false
		dragging = false

		await get_tree().create_timer(1).timeout

		var cam_tween = create_tween()
		cam_tween.tween_property(
			camera, "position", Vector3(0.0, 1.147, -1.73), 1.0
		).from(camera.position).set_trans(Tween.TRANS_SINE)
		cam_tween.play()

		await cam_tween.finished
		
		OpLog.i(LOG_TAG, [
			"play_replay_done replayCups={", _cup_summary(replay_cups), "}"
		])

		played_replay = true
		_process_game_state()

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

func _ios_throw_release(release_screen_pos: Vector2) -> void:
	if current_ball == null:
		return

	var screen_delta: Vector2 = release_screen_pos - drag_start_pos
	var dx_world: float = -screen_delta.x * ios_screen_to_world_scale
	var dz_world: float = -screen_delta.y * ios_screen_to_world_scale
	var drag_len: float = sqrt(dx_world * dx_world + dz_world * dz_world)

	if drag_len < IOS_DRAG_DEAD_DIST:
		dbg(["throw_cancelled dead_drag len=", drag_len])
		ball_ready = true
		return

	var scaled_dx: float = dx_world * IOS_H_SCALE
	var dist: float = sqrt(scaled_dx * scaled_dx + dz_world * dz_world) * 0.9
	var forward_force: float = max(dist * IOS_POWER_SLOPE, IOS_POWER_FLOOR)
	var abs_force: float = abs(forward_force)

	var angle_factor: float = (dx_world / drag_len) if drag_len > 0.000001 else 0.0

	var raw_x_target: float = ball_popo.x + (abs_force / IOS_X_NORM * IOS_X_GAIN * angle_factor)
	var ios_fz_target: float = IOS_Z_BIAS + (abs_force / IOS_Z_NORM) * IOS_Z_GAIN

	var raw_z_target: float = ball_popo.z + (abs(ios_fz_target) - abs(IOS_Z_BIAS))

	var target_cup: Vector3 = Vector3(raw_x_target, ball_popo.y, raw_z_target)
	var best_d: float = INF

	if is_instance_valid(my_cups):
		for cup in my_cups.get_children():
			if cup == null or not (cup is Node3D):
				continue
			if cup.name == &"cupremoved" or not (cup as Node3D).visible:
				continue

			var p: Vector3 = (cup as Node3D).global_position
			var d: float = Vector2(raw_x_target - p.x, raw_z_target - p.z).length()

			if d < best_d:
				best_d = d
				target_cup = p

	var assist: float = ios_aim_assist

	if best_d > 0.55:
		assist = 0.0
	elif best_d > 0.34:
		assist *= 0.45

	assist = clampf(assist, 0.0, 0.26)

	var final_x: float = lerp(raw_x_target, target_cup.x, assist)
	var final_z: float = lerp(raw_z_target, target_cup.z, assist)

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

	var thrown_ball: PongBall = current_ball
	thrown_ball.freeze = false
	thrown_ball.linear_velocity = Vector3.ZERO
	thrown_ball.angular_velocity = Vector3.ZERO
	thrown_ball.apply_impulse(Vector3(fx_impulse, fy_impulse, fz_impulse))
	thrown_ball.thrown = true
	ball_ready = false
	current_ball = null

	OpLog.i(LOG_TAG, [
		"throw_release dx=", dx_world,
		" dz=", dz_world,
		" dragLen=", drag_len,
		" rawTarget=", Vector2(raw_x_target, raw_z_target),
		" targetCup=", target_cup,
		" bestCupDist=", best_d,
		" assist=", assist,
		" impulse=", Vector3(fx_impulse, fy_impulse, fz_impulse)
	])

	var min_wait_time: float = 1.0
	var max_wait_time: float = 5.0
	var still_time: float = 0.0
	var elapsed: float = 0.0

	while is_instance_valid(thrown_ball):
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

		if elapsed < min_wait_time:
			continue

		var speed: float = thrown_ball.linear_velocity.length()
		var too_slow: bool = speed < 0.08
		var out_of_play: bool = thrown_ball.global_position.y < -1.2 or thrown_ball.global_position.z > 0.75 or thrown_ball.global_position.z < -2.6

		if too_slow:
			still_time += 0.1
		else:
			still_time = 0.0

		if still_time >= 0.4 or out_of_play or elapsed >= max_wait_time:
			OpLog.i(LOG_TAG, [
				"throw_resolved elapsed=", elapsed,
				" speed=", speed,
				" stillTime=", still_time,
				" outOfPlay=", out_of_play,
				" pos=", thrown_ball.global_position if is_instance_valid(thrown_ball) else Vector3.ZERO
			])
			if is_instance_valid(thrown_ball):
				thrown_ball.remove()
			else:
				throw_finished()
			return
