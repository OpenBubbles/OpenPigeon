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
const PHYSICS_TICKS_PER_SECOND: int = 200

const CUP_STYLE_SETTINGS_PATH := "user://settings.cfg"
const CUP_STYLE_SETTINGS_SECTION := "beer"
const CUP_STYLE_SETTINGS_FALLBACK_SECTION := "pong"
const CUP_STYLE_SETTINGS_KEY := "cup_style"
const BALL_STYLE_SETTINGS_KEY := "ball_style"

const DEFAULT_CUP_STYLE: int = 1
const DEFAULT_BALL_STYLE: int = 1
const BALL_STYLE_COUNT: int = 21

# my_cups is the rack the active player shoots into, while replay_cups is the rack nearest the local player.
const LOCAL_CUP_TINT := Color(0.92, 0.08, 0.10, 1.0)
const OPPONENT_CUP_TINT := Color(0.08, 0.30, 0.95, 1.0)

var current_cup_style: int = DEFAULT_CUP_STYLE
var current_ball_style: int = DEFAULT_BALL_STYLE
const CUP_SETTINGS_PREVIEW_YAW: float = 180.0
const BALL_SETTINGS_PREVIEW_YAW: float = 0.0
const BALL_SETTINGS_PREVIEW_PITCH: float = -55.0
const SETTINGS_PREVIEW_VIEWPORT_SIZE: int = 128
const SETTINGS_PREVIEW_BAKED_DIR := "res://pong/previews"
const SETTINGS_PREVIEW_BAKE_OUT_DIR := "user://cuppong_previews"
const BAKE_CUPPONG_PREVIEWS: bool = false #Set this to True if needed to update the Paid Asset Images. This will Produce images in %APPDATA%\Godot\app_userdata\OpenPigeon Games\cuppong_previews which go into the pong\assets folder

static var _settings_preview_texture_cache: Dictionary = {}
var _settings_preview_waiters: Dictionary = {}
var _settings_preview_render_queue: Array[Dictionary] = []
var _settings_preview_queue_running: bool = false

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

@onready var opp_avatar_display: TextureButton = %OppAvatarDisplay
@onready var player_avatar_display: TextureButton = %PlayerAvatarDisplay
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
var _previous_physics_ticks_per_second: int = 60
var _physics_tick_rate_overridden: bool = false

var game_over: bool = false


var start_replay_boards: String = "0,1,2,3,4,5,6,7,8,9&0,1,2,3,4,5,6,7,8,9"

@export var replay_ball_start_pos: Vector3 = Vector3(0.0, -0.574, -0.80)
@export var player_ball_start_pos: Vector3 = Vector3(0.0, -0.55, -1.00)
@export var second_ball_offset: Vector3 = Vector3(0.28, 0.0, 0.0)

var preview_ball: PongBall = null
var num_balls: int = 2
var throws: Array[Dictionary] = []

var recovery_turn_num: String = ""
var recovery_snapshot_pending := false
var recovery_snapshot_progress := ""
var recovery_loaded := false
var recovery_restore_in_progress := false
var recovery_key: String = ""
var _turn_base_boards: String = ""
const RECOVERY_STORE_PATH := "user://cuppong_recovery.cfg"
const RECOVERY_STORE_MAX_GAMES: int = 24
var current_throw_impulse: Vector3 = Vector3.ZERO
var redemption: bool = false
var played_replay: bool = false
var lost: bool = false
var _stabilized_mats: Dictionary = {}

var drag_start_pos = Vector2.ZERO
var drag_start_time: float = 0.0
var dragging = false
var ball_ready: bool = false
var ball_popo: Vector3 = Vector3.ZERO   # ball position at touch-down

const H_SCALE: float = 0.65
const POWER_SLOPE: float = -5.7
const POWER_FLOOR: float = -3.85

const X_NORM: float = 3.62
const X_GAIN: float = 2.08

const Z_NORM: float = -3.62
const Z_BIAS: float = -1.05
const Z_GAIN: float = 1.3

const Z_SPLIT: float = -1.7

const LONG_GAIN: float = 1.3
const LONG_Y: float = 4.12

const SHORT_GAIN: float = 1.35

const SHORT_Z_DIVISOR: float = -0.6
const SHORT_Y_BASE: float = 4.0
const SHORT_Y_SCALE: float = -3.0

const BALL_Y_AIM_OFFSET: float = 0.45
const DRAG_DEAD_DIST: float = 1.0 / 17.0

const DRAG_FILTER_FRAME: float = 0.016
const DRAG_FILTER_FOLLOW: float = 0.15

const AIM_BASE_NEW_PLAYER: float = 0.23
const AIM_BASE_EXPERIENCED: float = 0.21
const AIM_FIRST_MISS_BONUS: float = 0.03
const AIM_LATER_MISS_BONUS: float = 0.08
const AIM_BEHIND_BONUS: float = 0.03

@export_range(0, 100000, 1)
var local_cup_pong_wins: int = 0

var _drag_world_current: Vector3 = Vector3.ZERO
var _drag_world_filtered: Vector3 = Vector3.ZERO

# Camera positions used by normal play and replay playback.
const CUPPONG_CAM_THROW := Vector3(
	0.0,
	1.147,
	-1.76
)

const CUPPONG_CAM_REPLAY := Vector3(
	0.0,
	1.147,
	-3.486
)

# Landscape UI sizing.
const CUPPONG_LANDSCAPE_UI_SCALE: float = 1.5
const CUPPONG_LANDSCAPE_BUTTON_SCALE: float = 1.8
const CUPPONG_LANDSCAPE_LABEL_SCALE: float = 1.8

# Cup Pong popup menu sizing.
const CUPPONG_MENU_SIZE := Vector2(
	142.0,
	104.0
)

const CUPPONG_MENU_ROW_HEIGHT: float = 48.0
const CUPPONG_MENU_ROW_FONT: int = 21
const CUPPONG_MENU_GAP: float = 6.0
const CUPPONG_MENU_MARGIN: float = 8.0
const CUPPONG_LANDSCAPE_MENU_SCALE: float = 1.6

# Runtime menu nodes.
var cuppong_menu_layer: Control = null
var cuppong_menu_panel: PanelContainer = null
var cuppong_menu_rows: Array[Button] = []
var cuppong_menu_open: bool = false

# Responsive camera/UI state.
var _cam_station: Vector3 = Vector3.INF
var _applied_landscape: int = -1
var _base_theme_values: Dictionary = {}

# Temporary visual debugging controls.
@export var hide_all_cups: bool = false
@export var hide_ball: bool = false
@export var hide_table: bool = false

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

func _add_settings_rows(_container, popup_script) -> void:
	var cup_items: Array[Dictionary] = []
	var ball_items: Array[Dictionary] = []

	for style: int in range(1, Cups.CUP_STYLE_COUNT + 1):
		cup_items.append({
			"id": str(style),
			"style": style,
		})

	for style: int in range(1, BALL_STYLE_COUNT + 1):
		ball_items.append({
			"id": str(style),
			"style": style,
		})

	var cup_row: Control = popup_script.make_game_picker_card(
		"Cups",
		"Choose your cup style",
		cup_items,
		str(current_cup_style),
		func(selected_id: String) -> void:
			var style: int = clampi(selected_id.to_int(), 1, Cups.CUP_STYLE_COUNT)
			SettingsManager.set_setting(CUP_STYLE_SETTINGS_SECTION, CUP_STYLE_SETTINGS_KEY, style)
			_apply_cup_style(style, "settings"),
		Callable(self, "_make_cuppong_cup_settings_preview")
	)

	popup_script.add_custom_setting(cup_row)

	var ball_row: Control = popup_script.make_game_picker_card(
		"Balls",
		"Choose your ball style",
		ball_items,
		str(current_ball_style),
		func(selected_id: String) -> void:
			var style: int = clampi(selected_id.to_int(), 1, BALL_STYLE_COUNT)
			SettingsManager.set_setting(CUP_STYLE_SETTINGS_SECTION, BALL_STYLE_SETTINGS_KEY, style)
			_apply_ball_style(style, "settings"),
		Callable(self, "_make_cuppong_ball_settings_preview")
	)

	popup_script.add_custom_setting(ball_row)

func _make_cuppong_ball_settings_preview(item: Dictionary) -> Control:
	var style: int = clampi(int(item.get("style", DEFAULT_BALL_STYLE)), 1, BALL_STYLE_COUNT)
	return _make_cuppong_cached_settings_preview("ball", style)


func _make_cuppong_cup_settings_preview(item: Dictionary) -> Control:
	var style: int = clampi(int(item.get("style", DEFAULT_CUP_STYLE)), 1, Cups.CUP_STYLE_COUNT)
	return _make_cuppong_cached_settings_preview("cup", style)

func _cuppong_settings_preview_key(preview_kind: String, style: int) -> String:
	return "%s:%d" % [preview_kind, style]


func _make_cuppong_cached_settings_preview(preview_kind: String, style: int) -> Control:
	var texture_rect := TextureRect.new()
	texture_rect.custom_minimum_size = Vector2(70.0, 70.0)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var key: String = _cuppong_settings_preview_key(preview_kind, style)
	var baked: Texture2D = _baked_preview_texture(preview_kind, style)

	if baked != null:
		texture_rect.texture = baked
		return texture_rect

	if not _settings_preview_waiters.has(key):
		_settings_preview_waiters[key] = []

	var waiters: Array = _settings_preview_waiters[key]
	waiters.append(weakref(texture_rect))
	_settings_preview_waiters[key] = waiters

	_queue_cuppong_settings_preview(preview_kind, style)
	return texture_rect


func _baked_preview_texture(preview_kind: String, style: int) -> Texture2D:
	var key: String = _cuppong_settings_preview_key(preview_kind, style)

	if _settings_preview_texture_cache.has(key):
		return _settings_preview_texture_cache[key] as Texture2D

	var path: String = "%s/%s%d.png" % [SETTINGS_PREVIEW_BAKED_DIR, preview_kind, style]

	if not ResourceLoader.exists(path):
		return null

	var texture := ResourceLoader.load(path) as Texture2D

	if texture == null:
		return null

	_settings_preview_texture_cache[key] = texture
	return texture

func _queue_cuppong_settings_preview(preview_kind: String, style: int) -> void:
	var key: String = _cuppong_settings_preview_key(preview_kind, style)

	if _baked_preview_texture(preview_kind, style) != null:
		return

	for queued: Dictionary in _settings_preview_render_queue:
		if String(queued.get("key", "")) == key:
			return

	_settings_preview_render_queue.append({
		"key": key,
		"kind": preview_kind,
		"style": style,
	})

	if not _settings_preview_queue_running:
		_settings_preview_queue_running = true
		call_deferred("_process_cuppong_settings_preview_queue")


func _process_cuppong_settings_preview_queue() -> void:
	while not _settings_preview_render_queue.is_empty():
		while not played_replay and not _settings_open:
			await get_tree().process_frame

			if not is_inside_tree():
				_settings_preview_queue_running = false
				return

		var entry: Dictionary = _settings_preview_render_queue.pop_front()
		var key: String = String(entry.get("key", ""))
		var preview_kind: String = String(entry.get("kind", ""))
		var style: int = int(entry.get("style", 1))

		if _settings_preview_texture_cache.has(key):
			continue

		var texture: Texture2D = await _render_cuppong_settings_preview_texture(preview_kind, style)

		if texture != null:
			_settings_preview_texture_cache[key] = texture
			_update_cuppong_settings_preview_waiters(key, texture)

		await get_tree().process_frame

	_settings_preview_queue_running = false


func _update_cuppong_settings_preview_waiters(key: String, texture: Texture2D) -> void:
	if not _settings_preview_waiters.has(key):
		return

	var waiters: Array = _settings_preview_waiters[key]

	for waiter in waiters:
		var texture_rect: TextureRect = null

		if waiter is WeakRef:
			var ref_obj: Object = (waiter as WeakRef).get_ref()
			if ref_obj is TextureRect:
				texture_rect = ref_obj as TextureRect
		elif waiter is TextureRect:
			texture_rect = waiter as TextureRect

		if is_instance_valid(texture_rect):
			texture_rect.texture = texture

	_settings_preview_waiters.erase(key)

func bake_cuppong_settings_previews() -> void:
	DirAccess.make_dir_recursive_absolute(SETTINGS_PREVIEW_BAKE_OUT_DIR)

	for style: int in Cups.available_cup_styles(Cups.CUP_STYLE_COUNT):
		await _bake_cuppong_preview("cup", style)

	for style: int in PongBall.available_ball_styles():
		await _bake_cuppong_preview("ball", style)

	OpLog.i(LOG_TAG, ["preview_bake_done dir=", SETTINGS_PREVIEW_BAKE_OUT_DIR])

func _bake_cuppong_preview(preview_kind: String, style: int) -> void:
	var texture: Texture2D = await _render_cuppong_settings_preview_texture(preview_kind, style)

	if texture == null:
		return

	var image: Image = texture.get_image()

	if image == null or image.is_empty():
		return

	image.save_png("%s/%s%d.png" % [SETTINGS_PREVIEW_BAKE_OUT_DIR, preview_kind, style])

func _render_cuppong_settings_preview_texture(preview_kind: String, style: int) -> Texture2D:
	var model: Node3D = _build_cuppong_settings_preview_model(preview_kind, style)
	if not is_instance_valid(model):
		return null

	var viewport := SubViewport.new()
	viewport.size = Vector2i(SETTINGS_PREVIEW_VIEWPORT_SIZE, SETTINGS_PREVIEW_VIEWPORT_SIZE)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.world_3d = World3D.new()
	add_child(viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.25
	viewport.world_3d.environment = environment

	var scene_root := Node3D.new()
	viewport.add_child(scene_root)

	var model_root := Node3D.new()
	scene_root.add_child(model_root)
	model_root.add_child(model)

	var camera_node := Camera3D.new()
	camera_node.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_node.current = true
	scene_root.add_child(camera_node)

	var key_light := DirectionalLight3D.new()
	key_light.light_energy = 1.35
	key_light.rotation_degrees = Vector3(-38.0, -30.0, 0.0)
	scene_root.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.light_energy = 0.55
	fill_light.rotation_degrees = Vector3(20.0, 145.0, 0.0)
	scene_root.add_child(fill_light)

	await get_tree().process_frame

	var bounds: AABB = _cuppong_settings_preview_bounds(model_root, preview_kind)
	var visible_width: float = bounds.size.x
	var visible_height: float = bounds.size.y

	if visible_width < 0.001 or visible_height < 0.001:
		visible_width = 1.0
		visible_height = 1.0
	else:
		model_root.position = -bounds.get_center()

	var fill: float = 0.84
	if preview_kind == "ball":
		fill = 0.96
	elif preview_kind == "cup":
		fill = 0.86

	var fit_extent: float = maxf(visible_width, visible_height)
	var camera_size: float = fit_extent / fill

	camera_node.size = camera_size
	camera_node.near = 0.01
	camera_node.far = maxf(10.0, fit_extent * 10.0)
	camera_node.position = Vector3(0.0, 0.0, maxf(2.0, fit_extent * 4.0))
	camera_node.look_at(Vector3.ZERO, Vector3.UP)

	await RenderingServer.frame_post_draw

	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()

	if image == null or image.is_empty():
		return null

	return ImageTexture.create_from_image(image)

func _build_cuppong_settings_preview_model(preview_kind: String, style: int) -> Node3D:
	if preview_kind == "ball":
		if not is_instance_valid(ball):
			return null

		var duplicated: Node = ball.duplicate()
		if not duplicated is PongBall:
			if is_instance_valid(duplicated):
				duplicated.queue_free()
			return null

		var preview_ball := duplicated as PongBall
		preview_ball.freeze = true
		preview_ball.collision_layer = 0
		preview_ball.collision_mask = 0
		preview_ball.position = Vector3.ZERO
		preview_ball.rotation_degrees = Vector3(BALL_SETTINGS_PREVIEW_PITCH, BALL_SETTINGS_PREVIEW_YAW, 0.0)
		preview_ball.visible = true
		preview_ball.set_ball_style(clampi(style, 1, BALL_STYLE_COUNT))
		_cuppong_settings_preview_disable_runtime(preview_ball)
		return preview_ball

	var source_rack: Cups = null
	if is_instance_valid(replay_cups):
		source_rack = replay_cups
	elif is_instance_valid(my_cups):
		source_rack = my_cups

	if source_rack == null:
		return null

	var duplicated_rack: Node = source_rack.duplicate()
	if not duplicated_rack is Cups:
		if is_instance_valid(duplicated_rack):
			duplicated_rack.queue_free()
		return null

	var preview_rack := duplicated_rack as Cups
	var found_cup: bool = false

	for child: Node in preview_rack.get_children():
		if child is Node3D and child.name != &"cupremoved":
			var cup_node := child as Node3D
			if not found_cup:
				cup_node.visible = true
				found_cup = true
			else:
				cup_node.visible = false

	if not found_cup:
		preview_rack.queue_free()
		return null

	preview_rack.transform = Transform3D.IDENTITY
	preview_rack.rotation_degrees = Vector3(0.0, CUP_SETTINGS_PREVIEW_YAW, 0.0)
	preview_rack.visible = true
	preview_rack.set_cup_style(clampi(style, 1, Cups.CUP_STYLE_COUNT), LOCAL_CUP_TINT)
	_cuppong_settings_preview_disable_runtime(preview_rack)
	return preview_rack

func _cuppong_settings_preview_bounds(root: Node3D, preview_kind: String) -> AABB:
	var bounds := AABB()
	var has_bounds: bool = false
	var root_inverse: Transform3D = root.global_transform.affine_inverse()
	var visual_nodes: Array[Node] = root.find_children("*", "VisualInstance3D", true, false)

	for found: Node in visual_nodes:
		var visual := found as VisualInstance3D
		if visual == null or not visual.is_visible_in_tree():
			continue

		var node_name: String = visual.name.to_lower()
		if preview_kind == "ball" and ("shadow" in node_name or "trail" in node_name or "aim" in node_name or "indicator" in node_name):
			continue

		var local_bounds: AABB = visual.get_aabb()
		if local_bounds.size.length_squared() <= 0.000001:
			continue

		var to_root: Transform3D = root_inverse * visual.global_transform
		var visual_bounds: AABB = to_root * local_bounds

		if has_bounds:
			bounds = bounds.merge(visual_bounds)
		else:
			bounds = visual_bounds
			has_bounds = true

	return bounds

func _cuppong_settings_preview_disable_runtime(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED

	if node is RigidBody3D:
		var body: RigidBody3D = node as RigidBody3D
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
	elif node is CollisionObject3D:
		var collision_object: CollisionObject3D = node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0

	for child: Node in node.get_children():
		_cuppong_settings_preview_disable_runtime(child)

func _get_rules_title() -> String:
	return "Cup Pong"

func _cuppong_ui_scale() -> float:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	return CUPPONG_LANDSCAPE_UI_SCALE if vp.x > vp.y else 1.0

func _cam_pos(base: Vector3) -> Vector3:
	_cam_station = base

	var viewport_size: Vector2 = (
		get_viewport()
		.get_visible_rect()
		.size
	)

	if viewport_size.x <= viewport_size.y:
		return base

	var aspect_ratio: float = (
		viewport_size.x /
		maxf(viewport_size.y, 1.0)
	)

	var ultra_wide_amount: float = clampf(
		(aspect_ratio - 1.7) / 0.6,
		0.0,
		1.0
	)

	var pull_back: float = lerpf(
		0.08,
		0.14,
		ultra_wide_amount
	)

	var camera_lift: float = lerpf(
		0.01,
		0.03,
		ultra_wide_amount
	)

	return base + Vector3(
		0.0,
		camera_lift,
		-pull_back
	)

func _scale_theme(node: Control, theme_item: String, k: float) -> void:
	if not is_instance_valid(node):
		return
	var key: String = str(node.get_instance_id()) + theme_item
	if not _base_theme_values.has(key):
		_base_theme_values[key] = node.get_theme_font_size(theme_item)
	node.add_theme_font_size_override(theme_item, int(round(float(_base_theme_values[key]) * k)))

func _apply_responsive_ui() -> void:
	await get_tree().process_frame

	var vp: Vector2 = (
		get_viewport()
		.get_visible_rect()
		.size
	)

	var is_landscape: bool = vp.x > vp.y
	var landscape_state: int = 1 if is_landscape else 0

	_configure_cuppong_avatar(
		player_avatar_display
	)

	_configure_cuppong_avatar(
		opp_avatar_display
	)

	if is_instance_valid(camera):
		if _cam_station == Vector3.INF:
			_cam_station = camera.position

		if is_landscape:
			camera.keep_aspect = Camera3D.KEEP_HEIGHT
			camera.fov = 40.0
		else:
			camera.keep_aspect = Camera3D.KEEP_WIDTH
			camera.fov = 27.0

		camera.position = _cam_pos(
			_cam_station
		)

		if _applied_landscape != landscape_state:
			_applied_landscape = landscape_state

			OpLog.i(LOG_TAG, [
				"camera_responsive viewport=",
				vp,
				" landscape=",
				is_landscape,
				" keepAspect=",
				"KEEP_HEIGHT"
				if is_landscape
				else "KEEP_WIDTH",
				" fov=",
				camera.fov,
				" station=",
				_cam_station,
				" position=",
				camera.position
			])

	var button_k: float = (
		CUPPONG_LANDSCAPE_BUTTON_SCALE
		if is_landscape
		else 1.0
	)

	for button: Control in [
		settings_button
	]:
		if not is_instance_valid(button):
			continue

		var id: String = str(
			button.get_instance_id()
		)

		if not _base_theme_values.has(
			id + "minsize"
		):
			_base_theme_values[
				id + "minsize"
			] = button.custom_minimum_size

		button.scale = Vector2.ONE
		button.pivot_offset = Vector2.ZERO

		button.custom_minimum_size = (
			_base_theme_values[
				id + "minsize"
			] * button_k
		)

		if button is Button:
			(button as Button).expand_icon = true

	var label_k: float = (
		CUPPONG_LANDSCAPE_LABEL_SCALE
		if is_landscape
		else 1.0
	)

	for overlay: Control in [
		winner_label,
		sent_label,
		waiting_label,
		overtime_label,
		redemption_label,
		balls_back_label,
		spectator_label,
	]:
		_scale_theme(
			overlay,
			"font_size",
			label_k
		)

	if is_instance_valid(
		cuppong_menu_panel
	):
		_apply_cuppong_menu_scale()
		_position_cuppong_menu()

func _configure_cuppong_avatar(avatar_button: TextureButton) -> void:
	if not is_instance_valid(avatar_button):
		return

	var k: float = _cuppong_ui_scale()

	avatar_button.clip_contents = false
	avatar_button.scale = Vector2.ONE
	avatar_button.custom_minimum_size = Vector2(96.0, 90.0) * k
	avatar_button.texture_normal = null
	avatar_button.texture_pressed = null
	avatar_button.texture_hover = null
	avatar_button.texture_disabled = null
	avatar_button.texture_focused = null

	var internal_viewport := avatar_button.get_node_or_null("SubViewportContainer/SubViewport") as SubViewport

	if internal_viewport != null:
		internal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var internal_preview := avatar_button.get_node_or_null("SubViewportContainer") as SubViewportContainer

	if internal_preview != null:
		internal_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		internal_preview.visible = true
		internal_preview.self_modulate = Color.WHITE
		internal_preview.pivot_offset = Vector2(48.0, 140.0)
		internal_preview.scale = Vector2(k, k)

func _menu_scale() -> float:
	return CUPPONG_LANDSCAPE_MENU_SCALE if _cuppong_ui_scale() > 1.0 else 1.0

func _menu_size() -> Vector2:
	return CUPPONG_MENU_SIZE * _menu_scale()

func _make_cuppong_menu_style(background_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style

func _make_cuppong_menu_row(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var dark := Color(0.04, 0.04, 0.04, 1.0)
	for item: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(item, dark)
	button.add_theme_stylebox_override("normal", _make_cuppong_menu_style(Color(1.0, 1.0, 1.0, 0.0)))
	button.add_theme_stylebox_override("hover", _make_cuppong_menu_style(Color(0.94, 0.94, 0.94, 1.0)))
	button.add_theme_stylebox_override("pressed", _make_cuppong_menu_style(Color(0.86, 0.86, 0.86, 1.0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button

func _setup_cuppong_menu() -> void:
	if (
		is_instance_valid(cuppong_menu_layer) or
		not is_instance_valid(main_overlay) or
		not is_instance_valid(settings_button)
	):
		return

	if settings_button.pressed.is_connected(_on_settings_button_pressed):
		settings_button.pressed.disconnect(_on_settings_button_pressed)

	if not settings_button.pressed.is_connected(_on_cuppong_menu_button_pressed):
		settings_button.pressed.connect(_on_cuppong_menu_button_pressed)

	settings_button.tooltip_text = "Menu"

	cuppong_menu_layer = Control.new()
	cuppong_menu_layer.name = "CupPongMenuLayer"
	cuppong_menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cuppong_menu_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	cuppong_menu_layer.visible = false
	cuppong_menu_layer.z_index = 4096
	main_overlay.add_child(cuppong_menu_layer)
	cuppong_menu_layer.gui_input.connect(_on_cuppong_menu_layer_gui_input)

	cuppong_menu_panel = PanelContainer.new()
	cuppong_menu_panel.name = "CupPongMenuPanel"
	cuppong_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color.WHITE
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 4.0
	panel_style.content_margin_top = 4.0
	panel_style.content_margin_right = 4.0
	panel_style.content_margin_bottom = 4.0
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	panel_style.shadow_size = 8
	panel_style.shadow_offset = Vector2(0.0, 3.0)
	cuppong_menu_panel.add_theme_stylebox_override("panel", panel_style)

	cuppong_menu_layer.add_child(cuppong_menu_panel)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 0)
	cuppong_menu_panel.add_child(rows)

	var settings_row := _make_cuppong_menu_row("Settings")
	var help_row := _make_cuppong_menu_row("Rules")
	rows.add_child(settings_row)
	rows.add_child(help_row)
	cuppong_menu_rows = [settings_row, help_row]

	settings_row.pressed.connect(_on_cuppong_menu_settings_pressed)
	help_row.pressed.connect(_on_cuppong_menu_help_pressed)

	_apply_cuppong_menu_scale()
	call_deferred("_position_cuppong_menu")

func _apply_cuppong_menu_scale() -> void:
	if not is_instance_valid(cuppong_menu_panel):
		return

	var k: float = _menu_scale()
	var menu_size := _menu_size()

	cuppong_menu_panel.custom_minimum_size = menu_size
	cuppong_menu_panel.size = menu_size

	for row: Button in cuppong_menu_rows:
		if is_instance_valid(row):
			row.custom_minimum_size = Vector2(menu_size.x - 8.0 * k, CUPPONG_MENU_ROW_HEIGHT * k)
			row.add_theme_font_size_override("font_size", int(round(CUPPONG_MENU_ROW_FONT * k)))

func _position_cuppong_menu() -> void:
	if (
		not is_instance_valid(cuppong_menu_panel) or
		not is_instance_valid(settings_button) or
		not is_instance_valid(main_overlay)
	):
		return

	var overlay_rect := main_overlay.get_global_rect()
	var button_rect := settings_button.get_global_rect()
	var menu_size := _menu_size()

	var target_position := Vector2(
		button_rect.position.x - overlay_rect.position.x,
		button_rect.end.y - overlay_rect.position.y + CUPPONG_MENU_GAP
	)

	target_position.x = clampf(
		target_position.x,
		CUPPONG_MENU_MARGIN,
		maxf(CUPPONG_MENU_MARGIN, main_overlay.size.x - menu_size.x - CUPPONG_MENU_MARGIN)
	)

	target_position.y = clampf(
		target_position.y,
		CUPPONG_MENU_MARGIN,
		maxf(CUPPONG_MENU_MARGIN, main_overlay.size.y - menu_size.y - CUPPONG_MENU_MARGIN)
	)

	cuppong_menu_panel.position = target_position
	cuppong_menu_panel.size = menu_size

func _on_cuppong_menu_button_pressed() -> void:
	if cuppong_menu_open:
		_hide_cuppong_menu()
	else:
		_show_cuppong_menu()

func _show_cuppong_menu() -> void:
	if not is_instance_valid(cuppong_menu_layer) or not is_instance_valid(cuppong_menu_panel):
		return

	cuppong_menu_open = true
	_settings_open = true

	_apply_cuppong_menu_scale()
	_position_cuppong_menu()

	cuppong_menu_layer.visible = true
	cuppong_menu_layer.move_to_front()

	cuppong_menu_panel.pivot_offset = Vector2.ZERO
	cuppong_menu_panel.scale = Vector2(0.92, 0.92)
	cuppong_menu_panel.modulate.a = 0.0

	var tween := create_tween().set_parallel(true)
	tween.tween_property(cuppong_menu_panel, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(cuppong_menu_panel, "modulate:a", 1.0, 0.10)

func _hide_cuppong_menu() -> void:
	cuppong_menu_open = false
	if is_instance_valid(cuppong_menu_layer):
		cuppong_menu_layer.visible = false
	_settings_open = false

func _on_cuppong_menu_layer_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton and
		event.button_index == MOUSE_BUTTON_LEFT and
		event.pressed
	):
		_hide_cuppong_menu()
		get_viewport().set_input_as_handled()

func _on_cuppong_menu_settings_pressed() -> void:
	_hide_cuppong_menu()
	call_deferred("_on_settings_button_pressed")

func _on_cuppong_menu_help_pressed() -> void:
	_hide_cuppong_menu()
	call_deferred("_on_rules_button_pressed")

func _read_style_setting(key: String, default_style: int) -> Dictionary:
	var config := ConfigFile.new()
	var load_error := config.load(CUP_STYLE_SETTINGS_PATH)

	if load_error != OK:
		return {
			"style": default_style,
			"source": "default(load_error=%d)" % load_error,
		}

	for section: String in [
		CUP_STYLE_SETTINGS_SECTION,
		CUP_STYLE_SETTINGS_FALLBACK_SECTION,
	]:
		if config.has_section_key(section, key):
			return {
				"style": maxi(1, int(config.get_value(section, key, default_style))),
				"source": "%s/%s" % [section, key],
			}

	return {
		"style": default_style,
		"source": "default(missing_key)",
	}


func _read_cup_style_setting() -> Dictionary:
	return _read_style_setting(CUP_STYLE_SETTINGS_KEY, DEFAULT_CUP_STYLE)


func _read_ball_style_setting() -> Dictionary:
	return _read_style_setting(BALL_STYLE_SETTINGS_KEY, DEFAULT_BALL_STYLE)

func _apply_cup_style(style: int, source: String = "runtime") -> void:
	current_cup_style = clampi(style, 1, Cups.CUP_STYLE_COUNT)

	# my_cups is the target/opponent rack in the current Cup Pong flow.
	if is_instance_valid(my_cups):
		my_cups.set_cup_style(
			current_cup_style,
			OPPONENT_CUP_TINT
		)

	# replay_cups is the local rack shown on the player's side.
	if is_instance_valid(replay_cups):
		replay_cups.set_cup_style(
			current_cup_style,
			LOCAL_CUP_TINT
		)

	OpLog.i(LOG_TAG, [
		"cup_style_applied style=", current_cup_style,
		" source=", source,
		" targetRack=", my_cups.name if is_instance_valid(my_cups) else "<missing>",
		" targetTint=", OPPONENT_CUP_TINT,
		" localRack=", replay_cups.name if is_instance_valid(replay_cups) else "<missing>",
		" localTint=", LOCAL_CUP_TINT,
		" available=", Cups.available_cup_styles()
	])

func _apply_ball_style(style: int, source: String = "runtime") -> void:
	current_ball_style = clampi(style, 1, BALL_STYLE_COUNT)

	for child: Node in get_children():
		if child is PongBall:
			(child as PongBall).set_ball_style(current_ball_style)

	OpLog.i(LOG_TAG, [
		"ball_style_applied style=", current_ball_style,
		" source=", source
	])

func refresh_cup_style_from_settings() -> void:
	var setting := _read_cup_style_setting()
	_apply_cup_style(
		int(setting.style),
		String(setting.source)
	)

func refresh_ball_style_from_settings() -> void:
	var setting := _read_ball_style_setting()
	_apply_ball_style(
		int(setting.style),
		String(setting.source)
	)


func refresh_custom_styles_from_settings() -> void:
	refresh_cup_style_from_settings()
	refresh_ball_style_from_settings()

func _apply_physics_tick_rate() -> void:
	if not _physics_tick_rate_overridden:
		_previous_physics_ticks_per_second = Engine.physics_ticks_per_second
		_physics_tick_rate_overridden = true

	Engine.physics_ticks_per_second = PHYSICS_TICKS_PER_SECOND

	if not tree_exiting.is_connected(_restore_physics_tick_rate):
		tree_exiting.connect(_restore_physics_tick_rate, CONNECT_ONE_SHOT)

	OpLog.i(LOG_TAG, [
		"physics_tick_rate previous=", _previous_physics_ticks_per_second,
		" active=", Engine.physics_ticks_per_second,
		" fixedDelta=", 1.0 / float(Engine.physics_ticks_per_second)
	])


func _restore_physics_tick_rate() -> void:
	if not _physics_tick_rate_overridden:
		return

	if Engine.physics_ticks_per_second == PHYSICS_TICKS_PER_SECOND:
		Engine.physics_ticks_per_second = _previous_physics_ticks_per_second

	_physics_tick_rate_overridden = false


func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	_apply_physics_tick_rate()
	_configure_cuppong_avatar(player_avatar_display)
	_configure_cuppong_avatar(opp_avatar_display)
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
	vp.positional_shadow_atlas_quad_1 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
	vp.positional_shadow_atlas_quad_2 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED
	vp.positional_shadow_atlas_quad_3 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED

	if is_instance_valid(sun):
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 16.0
		sun.directional_shadow_fade_start = 1.0
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
	refresh_custom_styles_from_settings()

	if BAKE_CUPPONG_PREVIEWS:
		call_deferred("bake_cuppong_settings_previews")

	Engine.physics_jitter_fix = 0.5

	rules_button = settings_button

	get_viewport().size_changed.connect(_apply_responsive_ui)
	_apply_responsive_ui()
	call_deferred("_setup_cuppong_menu")
	
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

	recovery_turn_num = String(parsed.get("num", ""))
	recovery_key = "%s:%s:%s" % [
		String(parsed.get("id", "")),
		String(parsed.get("seed", "0")),
		recovery_turn_num
	]
	recovery_snapshot_pending = String(parsed.get("_recoveryPending", "false")).to_lower() == "true"
	recovery_snapshot_progress = _read_recovery_store()
	recovery_loaded = false
	recovery_restore_in_progress = false
	_turn_base_boards = ""

	if recovery_snapshot_progress.is_empty():
		recovery_snapshot_progress = String(parsed.get("_recoveryProgress", ""))

	OpLog.i(LOG_TAG, [
		"recovery_input key=", recovery_key,
		" pending=", recovery_snapshot_pending,
		" progressLen=", recovery_snapshot_progress.length()
	])

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
	
	my_cups.reset_cups([0,1,2,3,4,5,6,7,8,9])
	replay_cups.reset_cups([0,1,2,3,4,5,6,7,8,9])
	
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
	var p1_id: String = str(parsed.get("player1", ""))
	var p2_id: String = str(parsed.get("player2", ""))

	spectator_mode = my_uuid != "" and p1_id != "" and p2_id != "" and my_uuid != p1_id and my_uuid != p2_id

	if is_instance_valid(spectator_label):
		spectator_label.visible = spectator_mode

	if is_my_turn and not spectator_mode:
		player = 2 if player == 1 else 1
	elif spectator_mode:
		player = 1

	_configure_cuppong_avatar(player_avatar_display)
	_configure_cuppong_avatar(opp_avatar_display)

	if spectator_mode:
		var player_avatar_string := str(parsed.get("avatar1", ""))
		var opponent_avatar_string := str(parsed.get("avatar2", ""))

		if player_avatar_string != "" and is_instance_valid(player_avatar_display):
			var player_data := GameUtils._parse_avatar_string(player_avatar_string)
			player_avatar_display.call_deferred("update_avatar_from_data", player_data)

		if opponent_avatar_string != "" and is_instance_valid(opp_avatar_display):
			var opponent_data := GameUtils._parse_avatar_string(opponent_avatar_string)
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
	else:
		if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("update_display_from_settings"):
			player_avatar_display.call_deferred("update_display_from_settings")

		var opponent_avatar_key := "avatar2" if player == 1 else "avatar1"
		var opponent_avatar_string := str(parsed.get(opponent_avatar_key, ""))

		if opponent_avatar_string != "" and is_instance_valid(opp_avatar_display):
			var opponent_data := GameUtils._parse_avatar_string(opponent_avatar_string)
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
		
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

func _apply_debug_hides() -> void:
	if hide_all_cups:
		for rack: Node in [my_cups, replay_cups]:
			if not is_instance_valid(rack):
				continue
			for cup: Node in rack.get_children():
				if cup is Node3D:
					(cup as Node3D).visible = false

	if hide_ball and is_instance_valid(ball):
		ball.visible = false

	if hide_table:
		var table_node: Node = get_node_or_null("table")
		if table_node is Node3D:
			(table_node as Node3D).visible = false

	OpLog.i(LOG_TAG, [
		"debug_hides cups=", hide_all_cups,
		" ball=", hide_ball,
		" table=", hide_table
	])

func _dump_cup_state(label: String, cups: Cups) -> void:
	if not is_instance_valid(cups):
		return

	var seen: Dictionary = {}

	for child: Node in cups.get_children():
		var cup := child as Node3D
		if cup == null:
			continue

		var mesh_child: Node = cup.get_child(0) if cup.get_child_count() > 0 else null
		var key: String = "%.3f_%.3f" % [cup.global_position.x, cup.global_position.z]
		var dup: String = seen.get(key, "")
		seen[key] = cup.name

		OpLog.i(LOG_TAG, [
			label, " ", cup.name,
			" visible=", cup.visible,
			" inTree=", cup.is_visible_in_tree(),
			" layer=", (cup as StaticBody3D).collision_layer if cup is StaticBody3D else -1,
			" pos=", cup.global_position,
			" child0=", mesh_child.get_class() if mesh_child != null else "<none>",
			" child0Vis=", (mesh_child as GeometryInstance3D).visible if mesh_child is GeometryInstance3D else false,
			" children=", cup.get_child_count(),
			" COINCIDENT_WITH=", dup
		])

func _process(delta: float) -> void:
	if dragging:
		_advance_throw_drag_filter(delta)

	if not _debug_perf or not is_instance_valid(_debug_label):
		return

	_frame_accum += delta
	_frame_count += 1

	if delta > _max_delta:
		_max_delta = delta

	if _frame_accum < 0.5:
		return

	var fps := Engine.get_frames_per_second()
	var avg_dt := _frame_accum / _frame_count
	var avg_ms := avg_dt * 1000.0
	var max_ms := _max_delta * 1000.0

	var mem_static_mb := (
		Performance.get_monitor(
			Performance.MEMORY_STATIC
		) / 1048576.0
	)

	var draw_calls := Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
	)

	var render_objects := Performance.get_monitor(
		Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
	)

	var render_primitives := Performance.get_monitor(
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
	)

	var ball_count := 0

	for child: Node in get_children():
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

			if is_my_turn and _has_cuppong_recovery_throw():
				OpLog.i(LOG_TAG, [
					"recovery_skip_opponent_replay throwsPresent=true",
					" finalBoards=", start_replay_boards
				])

				_apply_cuppong_post_opponent_board(parsed_replay)

				played_replay = true
				stop_waiting_animation()

				if _restore_cuppong_recovery():
					return
			else:
				my_cups.prev_cups = my_board.duplicate()
				my_cups.reset_cups(my_board)
				replay_cups.reset_cups(other_board)

				if is_my_turn:
					stop_waiting_animation()
					playReplay(parsed_replay)
					return
		else:
			if check_winner():
				return
			if is_my_turn:
				stop_waiting_animation()
				camera.position = _cam_pos(CUPPONG_CAM_THROW)
	elif is_my_turn:
		if check_winner():
			return

		if not recovery_snapshot_pending and recovery_snapshot_progress.is_empty():
			_update_cuppong_redemption()

	if _restore_cuppong_recovery():
		return

	if check_winner():
		return

	if is_my_turn:
		if current_ball == null:
			current_ball = spawn_ball()

		_ensure_preview_ball()

		if throws.is_empty():
			_capture_turn_baseline()

	_apply_debug_hides()
	_dump_cup_state("cupstate_mine", my_cups)
	_dump_cup_state("cupstate_replay", replay_cups)
	
	OpLog.i(LOG_TAG, [
		"process_state_done turn=", is_my_turn,
		" playedReplay=", played_replay,
		" ballReady=", ball_ready,
		" numBalls=", num_balls,
		" throws=", throws.size(),
		" myCups={", _cup_summary(my_cups), "}",
		" replayCups={", _cup_summary(replay_cups), "}"
	])

func _update_cuppong_redemption() -> void:
	if not is_instance_valid(replay_cups):
		return

	var in_redemption: bool = replay_cups.cups_in_play.is_empty()

	if in_redemption == redemption:
		return

	redemption = in_redemption

	if not redemption:
		return

	if redemption_tween and redemption_tween.is_running():
		redemption_tween.kill()

	redemption_tween = _flash_label(redemption_label)

func _vec3_str(v: Vector3) -> String:
	return "%s,%s,%s" % [str(v.x), str(v.y), str(v.z)]

func _str_vec3(raw: String) -> Vector3:
	var parts := raw.split(",", false)
	if parts.size() < 3:
		return Vector3.INF
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

func _board_string(cups: Cups) -> String:
	var parts := PackedStringArray()
	for cup_idx in cups.cups_in_play:
		parts.append(str(cup_idx))
	return ",".join(parts)

func _flash_label(target: Label) -> Tween:
	if not is_instance_valid(target):
		return null

	target.visible = true
	target.modulate.a = 1.0

	var tween := create_tween().set_parallel(false)
	tween.tween_interval(2.0)
	tween.tween_property(target, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		if is_instance_valid(target):
			target.visible = false
			target.modulate.a = 1.0
	)
	return tween

func _tween_ball_path(node: PongBall, poses: Array, release_on_jump: bool = false) -> Tween:
	var tween := create_tween()
	var previous: Vector3 = node.position
	var count: int = 0

	for value in poses:
		if not value is Vector3:
			continue

		if previous.distance_to(value) > 0.5:
			if release_on_jump:
				tween.tween_callback(func():
					if is_instance_valid(node):
						node.linear_velocity = Vector3(0.0, -1.0, -1.0)
						node.freeze = false
				)
				count += 1
			break

		tween.tween_property(node, "position", value, REPLAY_FRAME_DURATION).set_trans(Tween.TRANS_LINEAR)
		previous = value
		count += 1

	if count == 0:
		tween.kill()
		return null

	return tween

func _await_throw_settle(thrown_ball: PongBall) -> void:
	var still_time: float = 0.0
	var elapsed: float = 0.0

	while is_instance_valid(thrown_ball):
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

		if elapsed < 1.0 or not is_instance_valid(thrown_ball):
			continue

		var speed: float = thrown_ball.linear_velocity.length()
		var pos: Vector3 = thrown_ball.global_position
		var out_of_play: bool = pos.y < -1.2 or pos.z > 0.75 or pos.z < -2.6

		still_time = still_time + 0.1 if speed < 0.08 else 0.0

		if still_time >= 0.4 or out_of_play or elapsed >= 5.0:
			OpLog.i(LOG_TAG, [
				"throw_resolved elapsed=", elapsed,
				" speed=", speed,
				" stillTime=", still_time,
				" outOfPlay=", out_of_play,
				" pos=", pos
			])

			if is_instance_valid(thrown_ball):
				thrown_ball.remove()
			else:
				throw_finished()
			return

func _send_turn() -> void:
	var outgoing := export_replay()
	OpLog.event(LOG_TAG, ["send_game_out raw=", outgoing])
	_clear_recovery_store()
	send_game_data(outgoing)

	is_my_turn = false
	ball_ready = false
	current_ball = null
	dragging = false

	if not game_over:
		play_sent_animation()

func _recovery_section() -> String:
	return recovery_key.replace(":", "_")

func _write_recovery_store(json: String) -> void:
	if recovery_key.is_empty():
		return

	var cfg := ConfigFile.new()
	cfg.load(RECOVERY_STORE_PATH)
	cfg.set_value(_recovery_section(), "progress", json)
	cfg.set_value(_recovery_section(), "stamp", Time.get_unix_time_from_system())
	_prune_recovery_store(cfg)
	cfg.save(RECOVERY_STORE_PATH)

func _read_recovery_store() -> String:
	if recovery_key.is_empty():
		return ""

	var cfg := ConfigFile.new()

	if cfg.load(RECOVERY_STORE_PATH) != OK:
		return ""

	return String(cfg.get_value(_recovery_section(), "progress", ""))

func _clear_recovery_store() -> void:
	var cfg := ConfigFile.new()

	if cfg.load(RECOVERY_STORE_PATH) != OK:
		return

	if cfg.has_section(_recovery_section()):
		cfg.erase_section(_recovery_section())
		cfg.save(RECOVERY_STORE_PATH)

func _prune_recovery_store(cfg: ConfigFile) -> void:
	var sections: Array = cfg.get_sections()

	if sections.size() <= RECOVERY_STORE_MAX_GAMES:
		return

	sections.sort_custom(func(a: String, b: String) -> bool:
		return float(cfg.get_value(a, "stamp", 0.0)) < float(cfg.get_value(b, "stamp", 0.0))
	)

	for idx: int in range(sections.size() - RECOVERY_STORE_MAX_GAMES):
		cfg.erase_section(String(sections[idx]))

func _boards_string() -> String:
	return "%s&%s" % [_board_string(my_cups), _board_string(replay_cups)]

func _capture_turn_baseline() -> void:
	_turn_base_boards = _boards_string()
	OpLog.i(LOG_TAG, ["recovery_baseline base=", _turn_base_boards])

func _apply_recovery_boards(raw: String, label: String) -> void:
	var parts := raw.split("&", true)

	if parts.size() < 2:
		OpLog.w(LOG_TAG, ["recovery_boards_skipped label=", label, " raw=", raw])
		return

	my_cups.reset_cups(_parse_cuppong_board(String(parts[0])))
	replay_cups.reset_cups(_parse_cuppong_board(String(parts[1])))

	OpLog.i(LOG_TAG, [
		"recovery_boards label=", label,
		" raw=", raw,
		" my=", my_cups.cups_in_play,
		" opp=", replay_cups.cups_in_play
	])

func _encode_poses(poses: Array) -> String:
	var out := ""

	for pos in poses:
		if pos is Vector3:
			out += conv((pos.x + 3.0) / 6.0)
			out += conv((pos.y + 2.0) * 0.25)
			out += conv((pos.z + 4.0) * 0.125)

	return out

func _decode_poses(raw: String) -> Array:
	var out: Array = []

	for idx in range(0, raw.length() - 5, 6):
		out.append(Vector3(
			convback(raw.substr(idx, 2)) * 6.0 - 3.0,
			convback(raw.substr(idx + 2, 2)) * 4.0 - 2.0,
			convback(raw.substr(idx + 4, 2)) * 8.0 - 4.0
		))

	return out

func _serialize_cuppong_throws() -> Array:
	var result: Array = []

	for move in throws:
		result.append("%d,%s,%s,%s,%s" % [
			int(move.get("cup", -1)),
			str(float(move.get("ix", 0.0))),
			str(float(move.get("iy", 0.0))),
			str(float(move.get("iz", 0.0))),
			_encode_poses(move.get("poses", []))
		])

	return result

func _deserialize_cuppong_throws(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if typeof(raw) != TYPE_ARRAY:
		return result

	for entry in raw:
		var parts := String(entry).split(",", true)

		if parts.size() < 5:
			continue

		result.append({
			"poses": _decode_poses(String(parts[4])),
			"cup": int(parts[0]),
			"ix": float(parts[1]),
			"iy": float(parts[2]),
			"iz": float(parts[3])
		})

	return result

func _save_cuppong_progress(phase: String, impulse: Vector3 = Vector3.ZERO, start: Vector3 = Vector3.INF) -> void:
	if recovery_restore_in_progress or spectator_mode or not is_my_turn or game_over:
		return

	if _turn_base_boards.is_empty():
		_capture_turn_baseline()

	var progress := {
		"phase": phase,
		"turn": recovery_turn_num,
		"throws": _serialize_cuppong_throws(),
		"numBalls": num_balls,
		"redemption": redemption,
		"base": _turn_base_boards,
		"now": _boards_string()
	}

	if phase == "throw":
		progress["start"] = _vec3_str(start if start.is_finite() else player_ball_start_pos)
		progress["impulse"] = _vec3_str(impulse)

	save_turn_progress(progress)

	OpLog.i(LOG_TAG, [
		"recovery_saved phase=", phase,
		" throws=", throws.size(),
		" numBalls=", num_balls,
		" base=", _turn_base_boards,
		" now=", progress["now"]
	])

func _restore_cuppong_recovery() -> bool:
	if recovery_loaded or spectator_mode or not is_my_turn or game_over:
		return false

	if recovery_snapshot_pending:
		recovery_loaded = true
		ball_ready = false
		current_ball = null
		dragging = false
		stop_waiting_animation()
		OpLog.i(LOG_TAG, "recovery_pending_send")
		return true

	if recovery_snapshot_progress.is_empty():
		return false

	var parsed: Variant = JSON.parse_string(recovery_snapshot_progress)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	var progress: Dictionary = parsed
	var phase := String(progress.get("phase", ""))

	if phase != "active" and phase != "throw":
		return false

	var saved_turn := String(progress.get("turn", ""))
	if not saved_turn.is_empty() and not recovery_turn_num.is_empty() and saved_turn != recovery_turn_num:
		return false

	recovery_loaded = true
	recovery_restore_in_progress = true

	throws = _deserialize_cuppong_throws(progress.get("throws", []))
	num_balls = int(progress.get("numBalls", num_balls))
	redemption = bool(progress.get("redemption", redemption))

	for child in get_children():
		if child is PongBall and child != ball:
			child.queue_free()

	current_ball = null
	preview_ball = null
	ball_ready = false
	dragging = false

	OpLog.i(LOG_TAG, [
		"recovery_loaded phase=", phase,
		" throws=", throws.size(),
		" numBalls=", num_balls,
		" myCupsBaseline=", my_cups.cups_in_play if is_instance_valid(my_cups) else [],
		" replayCupsBaseline=", replay_cups.cups_in_play if is_instance_valid(replay_cups) else []
	])

	call_deferred("_run_cuppong_recovery", progress)
	return true

func _run_cuppong_recovery(progress: Dictionary) -> void:
	var phase := String(progress.get("phase", ""))

	_turn_base_boards = String(progress.get("base", ""))
	_apply_recovery_boards(_turn_base_boards, "base")

	camera.position = _cam_pos(CUPPONG_CAM_THROW)

	await _replay_recovered_local_throws()

	_apply_recovery_boards(String(progress.get("now", "")), "now")
	_update_cuppong_redemption()

	if not redemption and throws.size() + (1 if phase == "throw" else 0) == 1:
		num_balls = maxi(num_balls, 1)

	recovery_restore_in_progress = false

	OpLog.i(LOG_TAG, [
		"recovery_resume phase=", phase,
		" throws=", throws.size(),
		" numBalls=", num_balls,
		" myCups=", my_cups.cups_in_play,
		" oppCups=", replay_cups.cups_in_play
	])

	if phase == "throw":
		var start := _str_vec3(String(progress.get("start", "")))

		if not start.is_finite():
			start = player_ball_start_pos

		current_throw_impulse = _str_vec3(String(progress.get("impulse", "")))

		if not current_throw_impulse.is_finite():
			current_throw_impulse = Vector3.ZERO

		_ensure_preview_ball()

		var thrown_ball: PongBall = ball.duplicate()
		thrown_ball.position = start
		thrown_ball.freeze = false
		thrown_ball.is_mine = true
		thrown_ball.thrown = true

		add_child(thrown_ball)
		thrown_ball.set_ball_style(current_ball_style)

		thrown_ball.linear_velocity = Vector3.ZERO
		thrown_ball.angular_velocity = Vector3.ZERO
		thrown_ball.apply_impulse(current_throw_impulse)

		await _await_throw_settle(thrown_ball)
		return

	if num_balls > 0:
		current_ball = spawn_ball()
	else:
		_send_turn()

func _replay_recovered_local_throws() -> void:
	if throws.is_empty():
		return

	OpLog.i(LOG_TAG, [
		"recovery_local_replay_start throws=", throws.size(),
		" targetCups=", my_cups.cups_in_play
	])

	for move: Dictionary in throws:
		var poses: Array = move.get("poses", [])
		var cup_idx := int(move.get("cup", -1))

		if not poses.is_empty():
			var replay_ball: PongBall = ball.duplicate()
			replay_ball.position = poses[0]
			replay_ball.freeze = true
			replay_ball.is_mine = false
			replay_ball.collision_layer = 0
			replay_ball.collision_mask = 0

			add_child(replay_ball)
			replay_ball.set_ball_style(current_ball_style)

			var tween := _tween_ball_path(replay_ball, poses)

			if tween != null:
				await tween.finished

			replay_ball.queue_free()

		if cup_idx >= 0:
			my_cups.remove_cup(cup_idx + 1)
			await get_tree().create_timer(0.45).timeout

		await get_tree().create_timer(0.25).timeout

	OpLog.i(LOG_TAG, ["recovery_local_replay_done targetCups=", my_cups.cups_in_play])

func _should_award_balls_back() -> bool:
	if throws.size() < 2:
		return false

	if throws.size() % 2 != 0:
		return false

	var last_throw: Dictionary = throws[-1]
	var previous_throw: Dictionary = throws[-2]

	if int(last_throw.get("cup", -1)) < 0:
		return false

	if int(previous_throw.get("cup", -1)) < 0:
		return false

	if not is_instance_valid(my_cups):
		return false

	if my_cups.cups_in_play.is_empty():
		return false

	return true

func throw_finished():
	OpLog.i(LOG_TAG, [
		"throw_finished throws=", throws.size(),
		" lastCup=", throws[-1]["cup"] if throws.size() > 0 else "none",
		" numBalls=", num_balls,
		" redemption=", redemption,
		" myCups=", my_cups.cups_in_play if is_instance_valid(my_cups) else []
	])

	if throws.size() > 0:
		throws[-1]["ix"] = current_throw_impulse.x
		throws[-1]["iy"] = current_throw_impulse.y
		throws[-1]["iz"] = current_throw_impulse.z

	var rack_cleared: bool = is_instance_valid(my_cups) and my_cups.cups_in_play.is_empty()
	var award_balls_back: bool = _should_award_balls_back()

	OpLog.i(LOG_TAG, [
		"throw_resolution rackCleared=", rack_cleared,
		" awardBallsBack=", award_balls_back,
		" redemption=", redemption,
		" numBallsBefore=", num_balls
	])

	if award_balls_back:
		if balls_back_tween and balls_back_tween.is_running():
			balls_back_tween.kill()

		balls_back_tween = _flash_label(balls_back_label)
		num_balls = 2
	elif rack_cleared:
		num_balls = 0

	if redemption and throws.size() > 0:
		if int(throws[-1].get("cup", -1)) == -1:
			lost = true
			_handle_game_over_i_lost()
			_send_turn()
			return

		if rack_cleared:
			if mode != "h":
				my_cups.reset_cups([0, 1, 2])
				replay_cups.reset_cups([0, 1, 2])

				if is_instance_valid(overtime_label):
					overtime_label.popup()

				await get_tree().create_timer(1.5).timeout

			num_balls = 0

	if game_over:
		return

	_save_cuppong_progress("active")

	if num_balls <= 0:
		_send_turn()
		return

	if preview_ball != null and is_instance_valid(preview_ball):
		var b := preview_ball
		preview_ball = null

		b.freeze = true
		b.collision_layer = 0
		b.collision_mask = 0

		var tween := create_tween()
		tween.tween_property(b, "position", player_ball_start_pos, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
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

func _apply_post_replay_board_state() -> void:
	if start_replay_boards.is_empty():
		return

	var boards := start_replay_boards.split("&", true)

	if boards.size() < 2:
		OpLog.w(LOG_TAG, [
			"post_replay_board_invalid raw=",
			start_replay_boards
		])
		return

	var p1_board: Array = _parse_cuppong_board(String(boards[0]))
	var p2_board: Array = _parse_cuppong_board(String(boards[1]))

	var my_board: Array
	var other_board: Array

	if player == 1:
		my_board = p1_board
		other_board = p2_board
	else:
		my_board = p2_board
		other_board = p1_board

	OpLog.i(LOG_TAG, [
		"post_replay_board_apply player=", player,
		" myBoard=", my_board,
		" otherBoard=", other_board,
		" beforeMy=", my_cups.cups_in_play,
		" beforeReplay=", replay_cups.cups_in_play
	])

	my_cups.reset_cups(my_board)
	replay_cups.reset_cups(other_board)

	OpLog.i(LOG_TAG, [
		"post_replay_board_applied myCups=",
		my_cups.cups_in_play,
		" replayCups=",
		replay_cups.cups_in_play
	])

func export_board(exp_player: int) -> String:
	return _board_string(my_cups if player == exp_player else replay_cups)

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

func _has_cuppong_recovery_throw() -> bool:
	if recovery_snapshot_progress.is_empty():
		return false

	var parsed: Variant = JSON.parse_string(recovery_snapshot_progress)

	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	var progress: Dictionary = parsed
	var phase := String(progress.get("phase", ""))

	if phase == "throw":
		return true

	if phase == "active":
		var saved_throws: Variant = progress.get("throws", [])

		if typeof(saved_throws) == TYPE_ARRAY:
			return not (saved_throws as Array).is_empty()

	return false

func _parse_cuppong_board(raw: String) -> Array:
	var result: Array = []

	if raw.is_empty():
		return result

	for value in raw.split(",", false):
		if not String(value).is_empty():
			result.append(int(value))

	return result

func _apply_cuppong_post_opponent_board(parsed_replay: Dictionary) -> void:
	var p1_board: Array = parsed_replay.get("p1_board", []).duplicate()
	var p2_board: Array = parsed_replay.get("p2_board", []).duplicate()

	if not start_replay_boards.is_empty():
		var boards := start_replay_boards.split("&", true)

		if boards.size() > 0:
			p1_board = _parse_cuppong_board(String(boards[0]))

		if boards.size() > 1:
			p2_board = _parse_cuppong_board(String(boards[1]))

	var my_board: Array
	var other_board: Array

	if player == 1:
		my_board = p1_board
		other_board = p2_board
	else:
		my_board = p2_board
		other_board = p1_board

	my_cups.prev_cups = my_board.duplicate()
	my_cups.reset_cups(my_board)
	replay_cups.reset_cups(other_board)

	OpLog.i(LOG_TAG, [
		"recovery_baseline_applied my=", my_board,
		" other=", other_board,
		" myCups=", my_cups.cups_in_play,
		" replayCups=", replay_cups.cups_in_play
	])

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

func _ensure_preview_ball() -> void:
	if not throws.is_empty() or num_balls <= 0 or preview_ball != null:
		return

	var new_ball: PongBall = ball.duplicate()
	new_ball.position = player_ball_start_pos + second_ball_offset
	new_ball.freeze = true
	new_ball.is_mine = true
	new_ball.collision_layer = 0
	new_ball.collision_mask = 0

	add_child(new_ball)
	new_ball.set_ball_style(current_ball_style)
	preview_ball = new_ball

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
	new_ball.set_ball_style(current_ball_style)
	current_ball = new_ball
	dbg([
		"spawn_ball replay=", is_replay,
		" pos=", new_ball.position,
		" numBalls=", num_balls,
		" ballReady=", ball_ready
	])
	return new_ball

func playReplay(parsed: Dictionary):
	camera.position = _cam_pos(CUPPONG_CAM_REPLAY)

	var moves = parsed["moves"]

	if moves.is_empty():
		OpLog.i(LOG_TAG, "play_replay_no_moves_apply_final_board")

		_apply_post_replay_board_state()
		played_replay = true
		_process_game_state()
		return
	
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
		
		var tween := _tween_ball_path(new_ball, move_cleaned, true)
		var is_final_move: bool = (idx + 1 == len(moves))

		if tween == null:
			_on_replay_finished(new_ball, move, is_final_move)
		else:
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
			camera, "position", _cam_pos(CUPPONG_CAM_THROW), 1.0
		).from(camera.position).set_trans(Tween.TRANS_SINE)
		cam_tween.play()

		await cam_tween.finished
		
		_apply_post_replay_board_state()

		OpLog.i(LOG_TAG, [
			"play_replay_done myCups={",
			_cup_summary(my_cups),
			"} replayCups={",
			_cup_summary(replay_cups),
			"}"
		])

		played_replay = true
		_process_game_state()

func _screen_to_throw_plane(
	screen_position: Vector2
) -> Vector3:
	if not is_instance_valid(camera):
		return ball_popo

	var ray_origin: Vector3 = camera.project_ray_origin(
		screen_position
	)

	var ray_direction: Vector3 = camera.project_ray_normal(
		screen_position
	).normalized()

	if absf(ray_direction.y) < 0.000001:
		return _drag_world_current

	var distance: float = (
		ball_popo.y -
		ray_origin.y
	) / ray_direction.y

	if distance <= 0.0:
		return _drag_world_current

	return ray_origin + ray_direction * distance


func _advance_throw_drag_filter(
	delta: float
) -> void:
	if not dragging:
		return

	var follow: float = clampf(
		(
			delta /
			DRAG_FILTER_FRAME
		) * DRAG_FILTER_FOLLOW,
		0.0,
		1.0
	)

	_drag_world_filtered += (
		_drag_world_current -
		_drag_world_filtered
	) * follow


func _live_target_cups() -> Array[Node3D]:
	var result: Array[Node3D] = []

	if not is_instance_valid(my_cups):
		return result

	for child: Node in my_cups.get_children():
		var cup := child as Node3D

		if cup == null:
			continue

		if not cup.visible:
			continue

		if cup.name == &"cupremoved":
			continue

		result.append(cup)

	return result


func _throw_forward_direction() -> Vector3:
	var live_cups: Array[Node3D] = _live_target_cups()

	if live_cups.is_empty():
		var rack_direction: Vector3 = (
			my_cups.global_position -
			ball_popo
			if is_instance_valid(my_cups)
			else Vector3(0.0, 0.0, 1.0)
		)

		rack_direction.y = 0.0

		if rack_direction.length_squared() > 0.000001:
			return rack_direction.normalized()

		return Vector3(0.0, 0.0, 1.0)

	var target_center := Vector3.ZERO

	for cup: Node3D in live_cups:
		target_center += cup.global_position

	target_center /= float(live_cups.size())

	var direction: Vector3 = target_center - ball_popo
	direction.y = 0.0

	if direction.length_squared() <= 0.000001:
		return Vector3(0.0, 0.0, 1.0)

	return direction.normalized()


func _aim_assist_strength() -> float:
	var assist: float = (
		AIM_BASE_NEW_PLAYER
		if local_cup_pong_wins < 2
		else AIM_BASE_EXPERIENCED
	)

	var made_cup_this_turn := false

	for shot: Dictionary in throws:
		if int(shot.get("cup", -1)) >= 0:
			made_cup_this_turn = true
			break

	if not made_cup_this_turn:
		if throws.is_empty():
			assist += AIM_FIRST_MISS_BONUS
		else:
			assist += AIM_LATER_MISS_BONUS

	if (
		is_instance_valid(my_cups) and
		is_instance_valid(replay_cups)
	):
		var target_cups_remaining: int = (
			my_cups.cups_in_play.size()
		)

		var shooter_cups_remaining: int = (
			replay_cups.cups_in_play.size()
		)

		if (
			target_cups_remaining -
			shooter_cups_remaining >= 4 and
			shooter_cups_remaining > 0
		):
			assist += AIM_BEHIND_BONUS

	return assist

func _unhandled_input(event: InputEvent) -> void:
	if (
		_settings_open or
		spectator_mode or
		not ball_ready or
		current_ball == null
	):
		return

	if event is InputEventMouseMotion:
		if dragging:
			var motion := event as InputEventMouseMotion

			_drag_world_current = _screen_to_throw_plane(
				motion.position
			)

		return

	if not (
		event is InputEventMouseButton
	):
		return

	var mouse_button := event as InputEventMouseButton

	if mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	if mouse_button.pressed:
		ball_popo = current_ball.global_position
		drag_start_pos = mouse_button.position

		var world_position := _screen_to_throw_plane(
			mouse_button.position
		)

		_drag_world_current = world_position
		_drag_world_filtered = world_position
		dragging = true

		OpLog.i(LOG_TAG, [
			"throw_drag_start screen=",
			drag_start_pos,
			" world=",
			world_position,
			" ball=",
			ball_popo
		])

		return

	if dragging:
		_throw_release(
			mouse_button.position
		)

func _throw_release(
	release_screen_pos: Vector2
) -> void:
	if current_ball == null:
		dragging = false
		return

	_drag_world_current = _screen_to_throw_plane(
		release_screen_pos
	)

	dragging = false

	var flick_world: Vector3 = (
		_drag_world_current -
		_drag_world_filtered
	)

	flick_world.y = 0.0

	var throw_forward: Vector3 = (
		_throw_forward_direction()
	)

	var throw_right: Vector3 = Vector3.UP.cross(
		throw_forward
	).normalized()

	var dx_world: float = flick_world.dot(
		throw_right
	)

	var dz_world: float = flick_world.dot(
		throw_forward
	)

	var drag_len: float = sqrt(
		dx_world * dx_world +
		dz_world * dz_world
	)

	if drag_len < DRAG_DEAD_DIST:
		OpLog.i(LOG_TAG, [
			"throw_cancelled dead_drag len=",
			drag_len,
			" flick=",
			flick_world,
			" current=",
			_drag_world_current,
			" filtered=",
			_drag_world_filtered
		])

		ball_ready = true
		return

	var scaled_dx: float = (
		dx_world *
		H_SCALE
	)

	var input_distance: float = sqrt(
		scaled_dx * scaled_dx +
		dz_world * dz_world
	)

	var forward_force: float = maxf(
		input_distance * POWER_SLOPE,
		POWER_FLOOR
	)

	var force_magnitude: float = absf(
		forward_force
	)

	var angle_factor: float = (
		dx_world / drag_len
		if drag_len > 0.000001
		else 0.0
	)

	var lateral_distance: float = (
		force_magnitude /
		X_NORM *
		X_GAIN *
		angle_factor
	)

	var raw_target_z: float = (
		Z_BIAS +
		(
			force_magnitude /
			Z_NORM
		) * Z_GAIN
	)

	var forward_distance: float = (
		absf(raw_target_z) -
		absf(Z_BIAS)
	)

	var raw_world_target: Vector3 = (
		ball_popo +
		throw_right * lateral_distance +
		throw_forward * forward_distance
	)

	raw_world_target.y = ball_popo.y

	var nearest_cup: Node3D = null
	var nearest_distance: float = INF

	for cup: Node3D in _live_target_cups():
		var cup_position: Vector3 = cup.global_position

		var aim_delta := Vector3(
			cup_position.x -
			raw_world_target.x,
			cup_position.y +
			BALL_Y_AIM_OFFSET,
			cup_position.z -
			raw_world_target.z
		)

		var cup_distance: float = aim_delta.length()

		if cup_distance < nearest_distance:
			nearest_distance = cup_distance
			nearest_cup = cup

	var aim_assist: float = 0.0
	var final_world_target: Vector3 = raw_world_target
	var assisted_target_z: float = raw_target_z
	var target_name: String = "none"

	if nearest_cup != null:
		aim_assist = _aim_assist_strength()

		var cup_position: Vector3 = (
			nearest_cup.global_position
		)

		final_world_target.x = lerpf(
			raw_world_target.x,
			cup_position.x,
			aim_assist
		)

		final_world_target.z = lerpf(
			raw_world_target.z,
			cup_position.z,
			aim_assist
		)

		var cup_local_position: Vector3 = (
			my_cups.to_local(
				cup_position
			)
		)

		assisted_target_z = lerpf(
			raw_target_z,
			cup_local_position.z,
			aim_assist
		)

		target_name = String(
			nearest_cup.name
		)

	var ball_position: Vector3 = (
		current_ball.global_position
	)

	var target_delta: Vector3 = (
		final_world_target -
		ball_position
	)

	target_delta.y = 0.0

	var fx_impulse: float
	var fy_impulse: float
	var fz_impulse: float
	var arc_branch: String

	if assisted_target_z <= Z_SPLIT:
		arc_branch = "long"

		fx_impulse = (
			target_delta.x *
			LONG_GAIN
		)

		fy_impulse = LONG_Y

		fz_impulse = (
			target_delta.z *
			LONG_GAIN
		)
	else:
		arc_branch = "short"

		fx_impulse = (
			target_delta.x *
			SHORT_GAIN
		)

		var short_curve: float = (
			(
				(
					absf(
						assisted_target_z
					) -
					absf(Z_BIAS)
				) /
				SHORT_Z_DIVISOR
			) +
			1.0
		)

		fy_impulse = (
			SHORT_Y_BASE +
			short_curve *
			SHORT_Y_SCALE
		)

		fz_impulse = (
			target_delta.z *
			SHORT_GAIN
		)

	var thrown_ball: PongBall = current_ball
	var committed_impulse := Vector3(fx_impulse, fy_impulse, fz_impulse)
	current_throw_impulse = committed_impulse
	_save_cuppong_progress("throw", committed_impulse, thrown_ball.position)

	thrown_ball.freeze = false
	thrown_ball.linear_velocity = Vector3.ZERO
	thrown_ball.angular_velocity = Vector3.ZERO
	thrown_ball.apply_impulse(committed_impulse)

	thrown_ball.thrown = true

	ball_ready = false
	current_ball = null

	OpLog.i(LOG_TAG, [
		"throw_release screenStart=",
			drag_start_pos,
		" screenEnd=",
			release_screen_pos,
		" flickWorld=",
			flick_world,
		" dx=",
			dx_world,
		" dz=",
			dz_world,
		" dragLen=",
			drag_len,
		" inputDistance=",
			input_distance,
		" force=",
			forward_force,
		" rawZ=",
			raw_target_z,
		" assistedZ=",
			assisted_target_z,
		" rawTarget=",
			raw_world_target,
		" assistedTarget=",
			final_world_target,
		" targetCup=",
			target_name,
		" targetDistance=",
			nearest_distance,
		" aimAssist=",
			aim_assist,
		" branch=",
			arc_branch,
		" impulse=",
			Vector3(
				fx_impulse,
				fy_impulse,
				fz_impulse
			)
	])

	await _await_throw_settle(thrown_ball)
