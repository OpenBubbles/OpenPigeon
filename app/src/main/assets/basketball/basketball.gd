extends BaseGame3D
class_name basketball

var elapsedTime: float = 0.0

const MUSIC_STREAM := preload("res://global/audio/basketball.ogg")
const IOS_DRAG_RELEASE_DISTANCE := 65.0
const IOS_DRAG_RELEASE_SPEED := 20.0
const IOS_NORMAL_AIM_ASSIST := 0.25

const IOS_AIM_REFERENCE := Vector3(
	0.0,
	1.05,
	-3.5,
)

const LOG_TAG := "Basketball"
const DEBUG_BASKETBALL := false

func dbg(parts: Variant) -> void:
	if DEBUG_BASKETBALL:
		OpLog.d(LOG_TAG, parts)

func _replay_shot_count(value) -> int:
	if isNullOrEmpty(value):
		return 0
	return String(value).split("|", false).size()

func _score_summary() -> String:
	return "my=%d opp=%d score1=%s score2=%s skip1=%s skip2=%s" % [
		myScore,
		oppScore,
		str(score1),
		str(score2),
		str(skip_score1),
		str(skip_score2)
	]
	
func _has_player_submitted_round(
	player_num: int,
	round_num: int,
) -> bool:
	if round_num == 1:
		if player_num == 1:
			return replay != null

		return replay2 != null

	if player_num == 1:
		return replay3 != null

	return replay4 != null


func _can_local_player_play_current_round() -> bool:
	if spectator_mode:
		return false

	if player == null:
		return false

	var current_turn := int(
		turnNum if turnNum != null else 1,
	)

	var local_player_num := int(
		player,
	)

	if current_turn <= 2:
		return not _has_player_submitted_round(
			local_player_num,
			1,
		)

	if current_turn == 3:
		return (
			replayFinished and
			not _has_player_submitted_round(
				local_player_num,
				2,
			)
		)

	if current_turn == 4:
		return not _has_player_submitted_round(
			local_player_num,
			2,
		)

	return false

@onready var opp_avatar_display: TextureButton = %OppAvatarDisplay
@onready var player_avatar_display: TextureButton = %PlayerAvatarDisplay
@onready var winner_label: Label = %WinLossLabel
@onready var sent_label: Label = %SentLabel
@onready var spectator_label: Label = %SpecLabel
@onready var waiting_status_label: Label = %waitingLabel
@onready var start_button: Button = %StartButton
@onready var skip_button: TextureButton = %SkipButton
@onready var round_container: PanelContainer = %RoundUI
@onready var round_label: Label = %RoundLabel
@onready var game_camera: Camera3D = %Camera3D
@onready var round_goal_label: Label = %GoalLabel
@onready var round_content_margin: MarginContainer = %RoundMarginContainer
@onready var round_content_vbox: VBoxContainer = %RoundVBoxContainer
@onready var you_label: Label = %YouLabel
@onready var opponent_label_spacer: Control = %OppLabelSpacer
@onready var static_backboard: MeshInstance3D = %backboard
@onready var static_hoop_collision: Node3D = %hoop_collision
@onready var static_net: MeshInstance3D = %net
@onready var static_pole: Node3D = %pole
@onready var static_net_collision_point: Marker3D = %StaticNetCollisionPoint

@onready var moving_hoop_root: Node3D = %MovingHoopRoot
@onready var moving_backboard: Node3D = %backboard_moving
@onready var moving_hoop_collision: Node3D = %hoop_collision_moving
@onready var moving_net: Node3D = %net_moving
@onready var moving_pole: Node3D = %pole_moving
@onready var moving_net_collision_point: Marker3D = %MovingNetCollisionPoint

var hoop_time: int = 0
var _hoop_acc: float = 0.0
var hoop_center_tween: Tween

var _moving_hoop_x: float = 0.0

var _moving_hoop_physics_initialized: bool = false

var _moving_hoop_physics_bodies: Array[AnimatableBody3D] = []

var _moving_hoop_base_transforms: Dictionary = {}

const SCORE_RADIUS := 0.15
const FIRST_REAL_RIM_SPHERE := 11
const LAST_REAL_RIM_SPHERE := 18

const IOS_MOVING_NET_Y := 0.843138
const IOS_MOVING_NET_Z := -3.529706

const ROUND_CARD_SIZE_RATIO := 0.80
const ROUND_CARD_REFERENCE_WIDTH := 518.4

const ROUND_CARD_MIN_CONTENT_SCALE := 0.75
const ROUND_CARD_MAX_CONTENT_SCALE := 1.80

const ROUND_BASE_HORIZONTAL_MARGIN := 24.0
const ROUND_BASE_VERTICAL_MARGIN := 20.0
const ROUND_BASE_SEPARATION := 40.0

const ROUND_BASE_TITLE_FONT_SIZE := 60.0
const ROUND_BASE_GOAL_FONT_SIZE := 24.0
const ROUND_BASE_BUTTON_FONT_SIZE := 28.0

const ROUND_BASE_BUTTON_WIDTH := 100.0
const ROUND_BASE_BUTTON_HEIGHT := 33.0

const BASE_AVATAR_SIZE := Vector2(
	96.0,
	90.0,
)

const BASE_YOU_LABEL_FONT_SIZE := 18.0
const BASE_OPP_LABEL_SPACER_HEIGHT := 26.0

const LANDSCAPE_AVATAR_MIN_SCALE := 2.05
const LANDSCAPE_AVATAR_MAX_SCALE := 2.35

const BASE_STATUS_LABEL_FONT_SIZE := 25.0
const BASE_SPECTATOR_LABEL_FONT_SIZE := 50.0

const BASE_STATUS_EXPAND_HORIZONTAL := 20.0
const BASE_STATUS_EXPAND_VERTICAL := 10.0
const BASE_STATUS_CORNER_RADIUS := 8.0

const BASE_WAITING_HALF_WIDTH := 163.0
const BASE_WAITING_HALF_HEIGHT := 17.5

const BASE_SPECTATOR_HALF_WIDTH := 324.0
const BASE_SPECTATOR_HEIGHT := 220.0

const LANDSCAPE_OVERLAY_MIN_SCALE := 1.35
const LANDSCAPE_OVERLAY_MAX_SCALE := 1.65

var _skip_button_base_size: Vector2 = Vector2.ZERO

var _responsive_layout_pending: bool = false
var _last_viewport_size: Vector2 = Vector2.ZERO
var _round_card_resources_prepared: bool = false

var _avatar_layout_generation: int = 0
var _current_avatar_scale: float = 1.0

const WIN_BURST_WRAPPER_NAME := "ResponsiveWinBurstWrapper"

const REPLAY_FRAME_RATE := 60.0
const REPLAY_SPAWN_DELAY_TICKS := 10
const REPLAY_LOOKAHEAD_TICKS := 60

const REPLAY_MIN_MISS_CORRECTION := 0.16
const REPLAY_MISS_MULTIPLIER := 1.5

var replayTimers: Array[Timer] = []
var replayEndTimer: Timer = null

var _replay_tick := 0

var _replay_shots: Dictionary = {
	1: [],
	2: [],
}

var _replay_spawn_tick: Dictionary = {
	1: -1,
	2: -1,
}
var replayPlaying = false
var replayFinished = false
var gamePlaying = false
var gameDataSet = false
var game_over = false
var _ui_initialized := false
var sent_tween: Tween
var allow_waiting_from_loaded_data: bool = false
var loaded_has_winner: bool = false
var winner_sent: bool = false
var _loaded_replay_key: String = ""
var _score_run_id: int = 0
var _scored_shot_keys: Dictionary = {}

var replay = null
var replay2 = null
var replay3 = null
var replay4 = null
var isTurn = null
var player = null
var game_seed = null
var seed2 = null
var score1 = null
var score2 = null
var skip_score1 = null
var skip_score2 = null
var turnNum = null

var has_connected = false
var dev_data = ""
var game_mode: String = "n"

var youScoreLabel: Label3D
var oppScoreLabel: Label3D
var timeRemainingLabel: Label3D

var currentBall = {1: null, 2: null}
var ballNum = {1: 1, 2: 1}

var oppScore = 0
var myScore = 0
var myReplay = ""

var recovery_deadline_ms: int = 0
var recovery_round_start_score: int = 0
var recovery_shots: Array[Dictionary] = []
var recovery_restore_in_progress: bool = false
var recovery_pending_send: bool = false
var recovery_loaded: bool = false
var recovery_check_scheduled: bool = false
var recovery_allow_waiting: bool = false
var recovery_snapshot_pending: bool = false
var recovery_snapshot_progress: String = ""

var isWaiting = false
var receivedMessage = null
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_previous_pos: Vector2 = Vector2.ZERO
var drag_smoothed_speed: float = 0.0
var dragging: bool = false
var active_drag_touch_index: int = -1

var my_player: Variant = null

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM

func _get_dev_data() -> String:
	return '{"isYourTurn": true, "myPlayerId": "9a6e234c-2244-4621-a08f-38acd277a2e0", "skip_score1": "18", "skip_score2": "46", "player": "2", "score1": "18", "score2": "23", "sender": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb", "avatar2": "body,3|eyes,6|mouth,3|acc,0|wins,0|bg_color,0.933333,0.407843,0.647059|body_color,0.968627,0.811765,0.333333|glasses,0|stache,0|backdrop,0|hair,0|clothes,2|hair_color,0.505882,0.725490,0.254902|clothes_color,0.686657,0.686657,0.686657", "player2": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb", "id": "G4m1HA79uZDuAtHY", "ios": "26.1", "num": "1", "game": "basketball", "mode": "h", "seed": "-1417153476", "tver": "5", "build": "28R", "round": "1", "seed2": "-16614620", "start": "", "version": "5", "caption": "Lets play Basketball!", "game_name": "Basketball", "replay": "60,0.264,0,0"}'

func _on_game_ready() -> void:
	OpLog.game_opened(
		LOG_TAG,
		[
			"localMode=",
			appPlugin == null,
			" uuid=",
			my_uuid,
		],
	)

	_initialize_moving_hoop_physics()
	_initialize_responsive_layout()

	if not _ui_initialized:
		_ui_initialized = true

		timeRemainingLabel = get_node("Scoreboard/Time")
		youScoreLabel = get_node("Scoreboard/YouScore")
		oppScoreLabel = get_node("Scoreboard/OppScore")

		if is_instance_valid(start_button):
			start_button.pressed.connect(start_button_pressed)
		if is_instance_valid(skip_button):
			skip_button.pressed.connect(skipReplay)

		if appPlugin:
			var complete_callable := Callable(self, "_on_basketball_send_complete")
			var failed_callable := Callable(self, "_on_basketball_send_failed")
			if appPlugin.has_signal("send_game_complete") and not appPlugin.is_connected("send_game_complete", complete_callable):
				appPlugin.connect("send_game_complete", complete_callable)
			if appPlugin.has_signal("send_game_failed") and not appPlugin.is_connected("send_game_failed", failed_callable):
				appPlugin.connect("send_game_failed", failed_callable)

	OpLog.i(LOG_TAG, [
		"game_ready localMode=", appPlugin == null,
		" dataSet=", gameDataSet,
		" mode=", game_mode,
		" player=", str(player),
		" turn=", str(isTurn)
	])

	if not gameDataSet:
		return

	_schedule_basketball_recovery_check()

func _configure_avatar_rendering(
	avatar_button: TextureButton,
) -> void:
	if not is_instance_valid(
		avatar_button,
	):
		return

	avatar_button.clip_contents = false

	var internal_viewport: SubViewport = (
		avatar_button.get_node_or_null(
			"SubViewportContainer/SubViewport",
		)
		as SubViewport
	)

	if internal_viewport != null:
		internal_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS
		)

	var internal_preview: SubViewportContainer = (
		avatar_button.get_node_or_null(
			"SubViewportContainer",
		)
		as SubViewportContainer
	)

	if internal_preview != null:
		internal_preview.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE
		)
		internal_preview.visible = true
		internal_preview.self_modulate = Color.WHITE
		internal_preview.pivot_offset = Vector2(
			48.0,
			140.0,
		)

func _prepare_round_card_resources() -> void:
	if _round_card_resources_prepared:
		return

	if (
		is_instance_valid(round_label) and
		round_label.label_settings != null
	):
		var title_settings: LabelSettings = (
			round_label.label_settings.duplicate()
			as LabelSettings
		)

		if title_settings != null:
			round_label.label_settings = title_settings

	if (
		is_instance_valid(round_goal_label) and
		round_goal_label.label_settings != null
	):
		var goal_settings: LabelSettings = (
			round_goal_label.label_settings.duplicate()
			as LabelSettings
		)

		if goal_settings != null:
			round_goal_label.label_settings = goal_settings

	var status_labels: Array[Label] = [
		winner_label,
		sent_label,
		waiting_status_label,
	]

	for status_label in status_labels:
		if not is_instance_valid(
			status_label,
		):
			continue

		var current_style: StyleBox = (
			status_label.get_theme_stylebox(
				"normal",
			)
		)

		if current_style == null:
			continue

		var duplicated_style: StyleBox = (
			current_style.duplicate()
			as StyleBox
		)

		if duplicated_style != null:
			status_label.add_theme_stylebox_override(
				"normal",
				duplicated_style,
			)

	if is_instance_valid(
		skip_button,
	):
		if skip_button.texture_normal != null:
			_skip_button_base_size = (
				skip_button.texture_normal.get_size()
			)

		if (
			_skip_button_base_size.x <= 0.0 or
			_skip_button_base_size.y <= 0.0
		):
			_skip_button_base_size = Vector2(
				64.0,
				64.0,
			)

		skip_button.ignore_texture_size = true
		skip_button.stretch_mode = (
			TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		)

	_configure_avatar_rendering(
		player_avatar_display,
	)

	_configure_avatar_rendering(
		opp_avatar_display,
	)

	_round_card_resources_prepared = true

func _initialize_responsive_layout() -> void:
	_prepare_round_card_resources()

	var viewport := get_viewport()

	if viewport == null:
		return

	if not viewport.size_changed.is_connected(
		_on_viewport_size_changed,
	):
		viewport.size_changed.connect(
			_on_viewport_size_changed,
		)

	_schedule_responsive_layout()

func _on_viewport_size_changed() -> void:
	_cancel_ball_drag()

	_schedule_responsive_layout()

func _schedule_responsive_layout() -> void:
	if _responsive_layout_pending:
		return

	_responsive_layout_pending = true

	call_deferred(
		"_apply_responsive_layout",
	)

func _apply_round_card_content_scale(
	content_scale: float,
	card_width: float,
	is_portrait: bool,
) -> void:
	var horizontal_margin := maxi(
		roundi(
			ROUND_BASE_HORIZONTAL_MARGIN *
			content_scale
		),
		1,
	)

	var vertical_margin := maxi(
		roundi(
			ROUND_BASE_VERTICAL_MARGIN *
			content_scale
		),
		1,
	)

	var content_separation := maxi(
		roundi(
			ROUND_BASE_SEPARATION *
			content_scale
		),
		1,
	)

	if is_instance_valid(
		round_content_margin,
	):
		round_content_margin.add_theme_constant_override(
			"margin_left",
			horizontal_margin,
		)

		round_content_margin.add_theme_constant_override(
			"margin_right",
			horizontal_margin,
		)

		round_content_margin.add_theme_constant_override(
			"margin_top",
			vertical_margin,
		)

		round_content_margin.add_theme_constant_override(
			"margin_bottom",
			vertical_margin,
		)

	if is_instance_valid(
		round_content_vbox,
	):
		round_content_vbox.add_theme_constant_override(
			"separation",
			content_separation,
		)

		round_content_vbox.alignment = (
			BoxContainer.ALIGNMENT_BEGIN
			if is_portrait
			else BoxContainer.ALIGNMENT_CENTER
		)

	if (
		is_instance_valid(round_label) and
		round_label.label_settings != null
	):
		round_label.label_settings.font_size = maxi(
			roundi(
				ROUND_BASE_TITLE_FONT_SIZE *
				content_scale
			),
			1,
		)

	if is_instance_valid(
		round_goal_label,
	):
		var goal_font_size := maxi(
			roundi(
				ROUND_BASE_GOAL_FONT_SIZE *
					content_scale
			),
			1,
		)

		if round_goal_label.label_settings != null:
			round_goal_label.label_settings.font_size = (
				goal_font_size
			)

		round_goal_label.add_theme_font_size_override(
			"font_size",
			goal_font_size,
		)

		var goal_width := maxf(
			card_width -
				float(
					horizontal_margin *
					2
				),
			1.0,
		)

		round_goal_label.custom_minimum_size = Vector2(
			goal_width,
			0.0,
		)

	if is_instance_valid(
		start_button,
	):
		start_button.add_theme_font_size_override(
			"font_size",
			maxi(
				roundi(
					ROUND_BASE_BUTTON_FONT_SIZE *
						content_scale
				),
				1,
			),
		)

		start_button.custom_minimum_size = Vector2(
			ROUND_BASE_BUTTON_WIDTH *
				content_scale,
			ROUND_BASE_BUTTON_HEIGHT *
				content_scale,
		)

	if is_instance_valid(
		round_content_vbox,
	):
		round_content_vbox.queue_sort()

	if is_instance_valid(
		round_content_margin,
	):
		round_content_margin.queue_sort()

func _remove_win_burst_proxy(
	avatar_button: TextureButton,
) -> void:
	if not is_instance_valid(
		avatar_button,
	):
		return

	var existing_proxy: Node = (
		avatar_button.get_node_or_null(
			WIN_BURST_WRAPPER_NAME,
		)
	)

	if existing_proxy == null:
		return

	avatar_button.remove_child(
		existing_proxy,
	)

	existing_proxy.queue_free()


func _clear_all_win_burst_proxies() -> void:
	_remove_win_burst_proxy(
		player_avatar_display,
	)

	_remove_win_burst_proxy(
		opp_avatar_display,
	)


func _create_win_burst_target(
	avatar_button: TextureButton,
	avatar_scale: float,
) -> TextureButton:
	if not is_instance_valid(
		avatar_button,
	):
		return null

	_remove_win_burst_proxy(
		avatar_button,
	)

	var burst_wrapper := Control.new()

	burst_wrapper.name = (
		WIN_BURST_WRAPPER_NAME
	)

	burst_wrapper.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	burst_wrapper.show_behind_parent = true
	burst_wrapper.clip_contents = false

	avatar_button.add_child(
		burst_wrapper,
	)

	burst_wrapper.size = BASE_AVATAR_SIZE

	burst_wrapper.pivot_offset = (
		BASE_AVATAR_SIZE *
		0.5
	)

	burst_wrapper.position = (
		avatar_button.size *
			0.5 -
		BASE_AVATAR_SIZE *
			0.5
	)

	burst_wrapper.scale = Vector2(
		avatar_scale,
		avatar_scale,
	)

	var burst_target := TextureButton.new()

	burst_target.name = "BurstTarget"

	burst_target.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	burst_target.ignore_texture_size = true
	burst_target.clip_contents = false
	burst_target.size = BASE_AVATAR_SIZE

	burst_target.pivot_offset = (
		BASE_AVATAR_SIZE *
		0.5
	)

	burst_wrapper.add_child(
		burst_target,
	)

	return burst_target


func _show_win_burst_for_avatar(
	avatar_button: TextureButton,
) -> void:
	var burst_target := (
		_create_win_burst_target(
			avatar_button,
			_current_avatar_scale,
		)
	)

	if not is_instance_valid(
		burst_target,
	):
		return

	GameUtils._show_win_burst(
		burst_target,
	)

func _apply_avatar_responsive_layout(
	content_scale: float,
	is_portrait: bool,
	viewport_size: Vector2,
) -> void:
	var avatar_scale := 1.0

	if not is_portrait:
		var landscape_aspect := (
			viewport_size.x /
			maxf(
				viewport_size.y,
				1.0,
			)
		)

		avatar_scale = clampf(
			maxf(
				content_scale,
				landscape_aspect,
			),
			LANDSCAPE_AVATAR_MIN_SCALE,
			LANDSCAPE_AVATAR_MAX_SCALE,
		)

	_current_avatar_scale = avatar_scale

	_clear_all_win_burst_proxies()

	var avatar_size := (
		BASE_AVATAR_SIZE *
		avatar_scale
	)

	var avatar_buttons: Array[TextureButton] = [
		player_avatar_display,
		opp_avatar_display,
	]

	for avatar_button in avatar_buttons:
		if not is_instance_valid(
			avatar_button,
		):
			continue

		_configure_avatar_rendering(
			avatar_button,
		)

		avatar_button.scale = Vector2.ONE

		avatar_button.custom_minimum_size = (
			avatar_size
		)

		var internal_preview := (
			avatar_button.get_node_or_null(
				"SubViewportContainer",
			) as SubViewportContainer
		)

		if internal_preview != null:
			internal_preview.scale = Vector2(
				avatar_scale,
				avatar_scale,
			)

		avatar_button.queue_redraw()

		var avatar_parent := (
			avatar_button.get_parent()
			as Container
		)

		if avatar_parent != null:
			avatar_parent.queue_sort()

	if is_instance_valid(
		you_label,
	):
		you_label.add_theme_font_size_override(
			"font_size",
			maxi(
				roundi(
					BASE_YOU_LABEL_FONT_SIZE *
					avatar_scale
				),
				1,
			),
		)

	if is_instance_valid(
		opponent_label_spacer,
	):
		opponent_label_spacer.custom_minimum_size = Vector2(
			0.0,
			BASE_OPP_LABEL_SPACER_HEIGHT *
				avatar_scale,
		)

	_avatar_layout_generation += 1

	call_deferred(
		"_finalize_avatar_responsive_layout",
		_avatar_layout_generation,
	)

func _finalize_avatar_responsive_layout(
	layout_generation: int,
) -> void:
	await get_tree().process_frame

	if (
		not is_inside_tree() or
		layout_generation !=
			_avatar_layout_generation
	):
		return

	var avatar_buttons: Array[TextureButton] = [
		player_avatar_display,
		opp_avatar_display,
	]

	for avatar_button in avatar_buttons:
		if not is_instance_valid(
			avatar_button,
		):
			continue

		var avatar_parent := (
			avatar_button.get_parent()
			as Container
		)

		if avatar_parent != null:
			avatar_parent.queue_sort()

	await get_tree().process_frame

	if (
		not is_inside_tree() or
		layout_generation !=
			_avatar_layout_generation
	):
		return

	for avatar_button in avatar_buttons:
		if not is_instance_valid(
			avatar_button,
		):
			continue

		avatar_button.scale = Vector2.ONE

		avatar_button.pivot_offset = (
			avatar_button.size *
			0.5
		)

		avatar_button.queue_redraw()

	_clear_all_win_burst_proxies()

	if (
		is_instance_valid(
			winner_label,
		) and
		winner_label.visible
	):
		_show_current_winner_burst()

func _apply_status_label_scale(
	label: Label,
	base_font_size: float,
	overlay_scale: float,
) -> void:
	if not is_instance_valid(
		label,
	):
		return

	label.add_theme_font_size_override(
		"font_size",
		maxi(
			roundi(
				base_font_size *
					overlay_scale
			),
			1,
		),
	)

	var normal_style := (
		label.get_theme_stylebox(
			"normal",
		)
	)

	if normal_style is StyleBoxFlat:
		var flat_style := (
			normal_style as StyleBoxFlat
		)

		flat_style.expand_margin_left = (
			BASE_STATUS_EXPAND_HORIZONTAL *
			overlay_scale
		)

		flat_style.expand_margin_right = (
			BASE_STATUS_EXPAND_HORIZONTAL *
			overlay_scale
		)

		flat_style.expand_margin_top = (
			BASE_STATUS_EXPAND_VERTICAL *
			overlay_scale
		)

		flat_style.expand_margin_bottom = (
			BASE_STATUS_EXPAND_VERTICAL *
			overlay_scale
		)

		var radius := maxi(
			roundi(
				BASE_STATUS_CORNER_RADIUS *
					overlay_scale
			),
			1,
		)

		flat_style.corner_radius_top_left = radius
		flat_style.corner_radius_top_right = radius
		flat_style.corner_radius_bottom_left = radius
		flat_style.corner_radius_bottom_right = radius

func _apply_game_overlay_responsive_layout(
	content_scale: float,
	is_portrait: bool,
) -> void:
	var overlay_scale := 1.0

	if not is_portrait:
		overlay_scale = clampf(
			content_scale,
			LANDSCAPE_OVERLAY_MIN_SCALE,
			LANDSCAPE_OVERLAY_MAX_SCALE,
		)

	_apply_status_label_scale(
		winner_label,
		BASE_STATUS_LABEL_FONT_SIZE,
		overlay_scale,
	)

	_apply_status_label_scale(
		sent_label,
		BASE_STATUS_LABEL_FONT_SIZE,
		overlay_scale,
	)

	_apply_status_label_scale(
		waiting_status_label,
		BASE_STATUS_LABEL_FONT_SIZE,
		overlay_scale,
	)

	if is_instance_valid(
		waiting_status_label,
	):
		waiting_status_label.offset_left = (
			-BASE_WAITING_HALF_WIDTH *
			overlay_scale
		)

		waiting_status_label.offset_right = (
			BASE_WAITING_HALF_WIDTH *
			overlay_scale
		)

		waiting_status_label.offset_top = (
			-BASE_WAITING_HALF_HEIGHT *
			overlay_scale
		)

		waiting_status_label.offset_bottom = (
			BASE_WAITING_HALF_HEIGHT *
			overlay_scale
		)

	if is_instance_valid(
		spectator_label,
	):
		spectator_label.add_theme_font_size_override(
			"font_size",
			maxi(
				roundi(
					BASE_SPECTATOR_LABEL_FONT_SIZE *
						overlay_scale
				),
				1,
			),
		)

		spectator_label.offset_left = (
			-BASE_SPECTATOR_HALF_WIDTH *
			overlay_scale
		)

		spectator_label.offset_right = (
			BASE_SPECTATOR_HALF_WIDTH *
			overlay_scale
		)

		spectator_label.offset_bottom = (
			BASE_SPECTATOR_HEIGHT *
			overlay_scale
		)

	if is_instance_valid(
		skip_button,
	):
		skip_button.ignore_texture_size = true
		skip_button.stretch_mode = (
			TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		)

		skip_button.custom_minimum_size = (
			_skip_button_base_size *
			overlay_scale
		)

		skip_button.queue_redraw()

		var skip_parent := (
			skip_button.get_parent()
			as Container
		)

		if skip_parent != null:
			skip_parent.queue_sort()

func _apply_responsive_layout() -> void:
	_responsive_layout_pending = false

	if not is_inside_tree():
		return

	var viewport := get_viewport()

	if viewport == null:
		return

	var viewport_size := (
		viewport.get_visible_rect().size
	)

	if (
		viewport_size.x <= 1.0 or
		viewport_size.y <= 1.0
	):
		return

	if viewport_size.is_equal_approx(
		_last_viewport_size,
	):
		return

	_last_viewport_size = viewport_size

	if is_instance_valid(
		game_camera,
	):
		game_camera.keep_aspect = (
			Camera3D.KEEP_HEIGHT
		)

	if not is_instance_valid(
		round_container,
	):
		return

	var is_portrait := (
		viewport_size.y >=
		viewport_size.x
	)

	var card_width: float
	var card_height: float

	if is_portrait:
		card_width = floorf(
			viewport_size.x *
			ROUND_CARD_SIZE_RATIO
		)

		card_height = 0.0
	else:
		card_height = floorf(
			viewport_size.y *
			ROUND_CARD_SIZE_RATIO
		)

		card_width = card_height

	round_container.custom_minimum_size = Vector2(
		card_width,
		card_height,
	)

	var content_scale := clampf(
		card_width /
			ROUND_CARD_REFERENCE_WIDTH,
		ROUND_CARD_MIN_CONTENT_SCALE,
		ROUND_CARD_MAX_CONTENT_SCALE,
	)

	_apply_round_card_content_scale(
		content_scale,
		card_width,
		is_portrait,
	)

	_apply_avatar_responsive_layout(
		content_scale,
		is_portrait,
		viewport_size,
	)

	_apply_game_overlay_responsive_layout(
		content_scale,
		is_portrait,
	)

	round_container.queue_sort()

	var card_parent := (
		round_container.get_parent()
		as Container
	)

	if card_parent != null:
		card_parent.queue_sort()

	OpLog.i(
		LOG_TAG,
		[
			"responsive_layout viewport=",
			viewport_size,
			" cardSize=",
			Vector2(
				card_width,
				card_height,
			),
			" contentScale=",
			content_scale,
			" portrait=",
			is_portrait,
		],
	)

func _show_current_winner_burst() -> void:
	_clear_all_win_burst_proxies()

	if myScore == oppScore:
		_show_win_burst_for_avatar(
			player_avatar_display,
		)

		_show_win_burst_for_avatar(
			opp_avatar_display,
		)

		return

	var winning_avatar: TextureButton = (
		player_avatar_display
		if myScore > oppScore
		else opp_avatar_display
	)

	_show_win_burst_for_avatar(
		winning_avatar,
	)

func showWinner() -> void:
	if myScore == oppScore:
		winner_label.set_text(
			"DRAW!",
		)

		winner_label.add_theme_color_override(
			"font_color",
			Color.WHITE,
		)

	elif myScore > oppScore:
		if spectator_mode:
			winner_label.set_text(
				"PLAYER 1 WINS!",
			)
		else:
			winner_label.set_text(
				"YOU WIN!",
			)

		winner_label.add_theme_color_override(
			"font_color",
			Color(
				1.0,
				0.84,
				0.0,
			),
		)

	else:
		if spectator_mode:
			winner_label.set_text(
				"PLAYER 2 WINS!",
			)
		else:
			winner_label.set_text(
				"YOU LOSE!",
			)

		winner_label.add_theme_color_override(
			"font_color",
			Color(
				1.0,
				0.2,
				0.2,
			),
		)

	winner_label.visible = true

	_show_current_winner_burst()

func _set_collision_shapes_enabled(
	root: Node,
	enabled: bool,
) -> void:
	if not is_instance_valid(root):
		return

	for child in root.get_children():
		if child is CollisionShape3D:
			child.disabled = not enabled

		_set_collision_shapes_enabled(
			child,
			enabled,
		)

func _set_hoop_collision_shapes_enabled(
	root: Node,
	enabled: bool,
) -> void:
	_set_collision_shapes_enabled(
		root,
		enabled,
	)
	
func _set_collision_debug_meshes_visible(
	root: Node,
	visible_value: bool,
) -> void:
	if not is_instance_valid(root):
		return

	for child in root.get_children():
		if child is CSGSphere3D:
			child.visible = visible_value

		_set_collision_debug_meshes_visible(
			child,
			visible_value,
		)

func _collect_moving_hoop_physics_bodies(
	root: Node,
) -> void:
	if not is_instance_valid(
		root,
	):
		return

	for child in root.get_children():
		if child is AnimatableBody3D:
			_moving_hoop_physics_bodies.append(
				child as AnimatableBody3D,
			)

		_collect_moving_hoop_physics_bodies(
			child,
		)


func _initialize_moving_hoop_physics() -> void:
	if _moving_hoop_physics_initialized:
		return

	if not is_instance_valid(
		moving_hoop_root,
	):
		return

	var current_root_x := (
		moving_hoop_root.position.x
	)

	moving_hoop_root.force_update_transform()

	_moving_hoop_physics_bodies.clear()
	_moving_hoop_base_transforms.clear()

	_collect_moving_hoop_physics_bodies(
		moving_hoop_root,
	)

	for body in _moving_hoop_physics_bodies:
		if not is_instance_valid(
			body,
		):
			continue

		var current_transform := (
			body.global_transform
		)

		var base_transform := (
			current_transform
		)

		base_transform.origin.x -= (
			current_root_x
		)

		body.top_level = true
		body.sync_to_physics = true
		body.global_transform = current_transform

		_moving_hoop_base_transforms[
			body.get_instance_id()
		] = base_transform

	_moving_hoop_physics_initialized = true

	_set_moving_hoop_x(
		current_root_x,
	)

	OpLog.i(
		LOG_TAG,
		[
			"moving_hoop_physics_initialized bodies=",
			_moving_hoop_physics_bodies.size(),
			" rootX=",
			current_root_x,
		],
	)


func _set_moving_hoop_x(
	x_pos: float,
) -> void:
	if not is_instance_valid(
		moving_hoop_root,
	):
		return

	_moving_hoop_x = x_pos

	moving_hoop_root.position.x = x_pos
	moving_hoop_root.force_update_transform()

	if not _moving_hoop_physics_initialized:
		return

	for body in _moving_hoop_physics_bodies:
		if not is_instance_valid(
			body,
		):
			continue

		var body_id := (
			body.get_instance_id()
		)

		if not _moving_hoop_base_transforms.has(
			body_id,
		):
			continue

		var base_transform: Transform3D = (
			_moving_hoop_base_transforms[
				body_id
			]
		)

		var moved_transform := (
			base_transform
		)

		moved_transform.origin.x = (
			base_transform.origin.x +
			x_pos
		)

		body.global_transform = moved_transform
		body.force_update_transform()

func _hoop_x_at_tick(
	tick: int,
) -> float:
	var movement_tick := posmod(
		tick,
		480,
	)

	if movement_tick < 120:
		return (
			float(movement_tick) /
			120.0
		)

	if movement_tick < 240:
		return (
			1.0 -
			float(
				movement_tick - 120,
			) /
			120.0
		)

	if movement_tick < 360:
		return (
			-float(
				movement_tick - 240,
			) /
			120.0
		)

	return (
		-1.0 +
		float(
			movement_tick - 360,
		) /
		120.0
	)

func get_saved_replay_x(
	target_x: float,
) -> float:
	if game_mode == "h":
		return (
			_hoop_x_at_tick(
				hoop_time +
					REPLAY_LOOKAHEAD_TICKS,
			) -
			target_x
		)

	return -target_x

func _reset_replay_scheduler() -> void:
	_replay_tick = 0

	_replay_shots[1] = []
	_replay_shots[2] = []

	_replay_spawn_tick[1] = -1
	_replay_spawn_tick[2] = -1

func _calculate_replay_x_velocity(
	ball: BasketballBall,
	saved_replay_x: float,
	did_go_in: bool,
) -> float:
	var predicted_hoop_x := 0.0

	if game_mode == "h":
		predicted_hoop_x = _hoop_x_at_tick(
			_replay_tick +
				REPLAY_LOOKAHEAD_TICKS,
		)

	var center_velocity := (
		predicted_hoop_x -
		ball.position.x
	)

	if did_go_in:
		return center_velocity

	var correction := saved_replay_x

	if absf(
		correction,
	) < REPLAY_MIN_MISS_CORRECTION:
		correction = (
			-REPLAY_MIN_MISS_CORRECTION
			if correction < 0.0
			else REPLAY_MIN_MISS_CORRECTION
		)

	return (
		center_velocity -
		correction *
			REPLAY_MISS_MULTIPLIER
	)

func _advance_replay_frame() -> void:
	_replay_tick += 1

	for player_num in [1, 2]:
		var shots: Array = _replay_shots.get(
			player_num,
			[],
		)

		if shots.is_empty():
			continue

		var scheduled_spawn_tick := int(
			_replay_spawn_tick.get(
				player_num,
				-1,
			),
		)

		if (
			not is_instance_valid(
				currentBall.get(
					player_num,
				),
			) and
			scheduled_spawn_tick >= 0 and
			_replay_tick >= scheduled_spawn_tick
		):
			spawnBall(
				player_num,
				bool(
					shots[0][
						"did_go_in"
					],
				),
			)

			_replay_spawn_tick[player_num] = -1

		var next_shot: Dictionary = shots[0]

		if (
			int(
				next_shot[
					"time_tick"
				],
			) >
			_replay_tick
		):
			continue

		var replay_ball := currentBall.get(
			player_num,
		) as BasketballBall

		if not is_instance_valid(
			replay_ball,
		):
			replay_ball = spawnBall(
				player_num,
				bool(
					next_shot[
						"did_go_in"
					],
				),
			)

		var saved_replay_x := float(
			next_shot[
				"saved_replay_x"
			],
		)

		var did_go_in := bool(
			next_shot[
				"did_go_in"
			],
		)

		var replay_x_velocity := (
			_calculate_replay_x_velocity(
				replay_ball,
				saved_replay_x,
				did_go_in,
			)
		)

		replay_ball.begin_replay_shot(
			replay_x_velocity,
			saved_replay_x,
			did_go_in,
			game_mode == "h",
		)

		if (
			currentBall.get(
				player_num,
			) ==
			replay_ball
		):
			currentBall[player_num] = null

		shots.pop_front()

		if not shots.is_empty():
			_replay_spawn_tick[player_num] = (
				_replay_tick +
				REPLAY_SPAWN_DELAY_TICKS
			)
		else:
			_replay_spawn_tick[player_num] = -1

	for child in get_children():
		if (
			child is BasketballBall and
			(child as BasketballBall).replay_manual_simulating
		):
			(
				child as BasketballBall
			).step_replay_pre_simulation()

func _apply_basketball_mode() -> void:
	var hard_mode := game_mode == "h"

	static_backboard.visible = not hard_mode
	static_hoop_collision.visible = not hard_mode
	static_net.visible = not hard_mode
	static_pole.visible = not hard_mode

	moving_hoop_root.visible = hard_mode
	moving_backboard.visible = hard_mode
	moving_hoop_collision.visible = hard_mode
	moving_net.visible = hard_mode
	moving_pole.visible = hard_mode

	_set_collision_debug_meshes_visible(
		static_hoop_collision,
		false,
	)

	_set_collision_debug_meshes_visible(
		moving_hoop_collision,
		false,
	)

	if not hard_mode:
		hoop_time = 0
		_hoop_acc = 0.0

		if hoop_center_tween and hoop_center_tween.is_running():
			hoop_center_tween.kill()

		if is_instance_valid(moving_hoop_root):
			_set_moving_hoop_x(
				0.0,
			)

	_set_hoop_collision_shapes_enabled(
		static_hoop_collision,
		not hard_mode,
	)

	_set_collision_shapes_enabled(
		static_backboard,
		not hard_mode,
	)

	_set_hoop_collision_shapes_enabled(
		moving_hoop_collision,
		hard_mode,
	)

	_set_collision_shapes_enabled(
		moving_backboard,
		hard_mode,
	)

func _recovery_now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func _sync_recovery_elapsed() -> void:
	if recovery_deadline_ms <= 0:
		return
	var remaining_ms: int = maxi(0, recovery_deadline_ms - _recovery_now_ms())
	elapsedTime = clampf(45.0 - float(remaining_ms) / 1000.0, 0.0, 45.0)

func _save_basketball_progress() -> void:
	if appPlugin == null or spectator_mode or turnNum == null:
		return
	var progress := {"phase": "round", "deadline": str(recovery_deadline_ms), "turn": str(turnNum), "roundStartScore": str(recovery_round_start_score), "shots": recovery_shots}
	var saved := bool(appPlugin.saveTurnProgress(JSON.stringify(progress)))
	OpLog.i(LOG_TAG, ["recovery_saved saved=", saved, " shots=", recovery_shots.size(), " deadline=", recovery_deadline_ms])

func _recovery_shot_index(shot_num: int) -> int:
	for i in range(recovery_shots.size()):
		if int(recovery_shots[i].get("num", 0)) == shot_num:
			return i
	return -1

func _max_recovery_shot_num() -> int:
	var result := 0
	for shot in recovery_shots:
		result = maxi(result, int(shot.get("num", 0)))
	return result

func _build_recovery_replay() -> String:
	var entries: Array[String] = []
	for shot in recovery_shots:
		if not bool(shot.get("finished", false)):
			continue
		var time_tick := int(float(shot.get("time", 0.0)) * REPLAY_FRAME_RATE)
		var saved_x := float(shot.get("savedX", 0.0))
		var result := 1 if int(shot.get("result", 0)) == 1 else 0
		entries.append("%d,%0.3f,0,%d" % [time_tick, saved_x, result])
	return "|".join(entries)

func _recovery_score() -> int:
	var result: int = recovery_round_start_score

	for shot in recovery_shots:
		if bool(shot.get("finished", false)) and int(shot.get("result", -1)) == 1:
			result += 1

	return result

func _record_basketball_release(shot_num: int, target_x: float, saved_x: float) -> void:
	recovery_shots.append({"num": shot_num, "time": elapsedTime, "hoop": hoop_time, "target": target_x, "savedX": saved_x, "result": -1, "finished": false})
	_save_basketball_progress()

func mark_basketball_shot_scored(shot_num: int) -> void:
	var index := _recovery_shot_index(shot_num)
	if index < 0:
		return
	recovery_shots[index]["result"] = 1
	_save_basketball_progress()

func mark_basketball_shot_finished(shot_num: int, did_go_in: bool) -> void:
	var index := _recovery_shot_index(shot_num)
	if index < 0:
		return
	recovery_shots[index]["result"] = 1 if did_go_in else 0
	recovery_shots[index]["finished"] = true
	_save_basketball_progress()

func _launch_recovered_basketball_shot(shot: Dictionary) -> void:
	if player == null or not recovery_restore_in_progress:
		return
	var local_player_num := int(player)
	var shot_num := int(shot.get("num", 1))
	ballNum[local_player_num] = shot_num
	var recovered_ball := spawnBall(local_player_num)
	if not is_instance_valid(recovered_ball):
		return
	elapsedTime = float(shot.get("time", 0.0))
	hoop_time = int(shot.get("hoop", int(elapsedTime * REPLAY_FRAME_RATE)))
	_hoop_acc = 0.0
	if game_mode == "h" and is_instance_valid(moving_hoop_root):
		_set_moving_hoop_x(_hoop_x_at_tick(hoop_time))
	recovered_ball.shoot_recovery(float(shot.get("target", 0.0)), elapsedTime, float(shot.get("savedX", 0.0)))
	if currentBall.get(local_player_num) == recovered_ball:
		currentBall[local_player_num] = null

func _finish_basketball_recovery() -> void:
	recovery_restore_in_progress = false
	_sync_recovery_elapsed()
	ballNum[int(player)] = _max_recovery_shot_num() + 1
	if recovery_deadline_ms > _recovery_now_ms() and not is_instance_valid(currentBall.get(int(player))):
		spawnBall(int(player))
	updateStrokeRecoveryUi()

func updateStrokeRecoveryUi() -> void:
	if is_instance_valid(youScoreLabel):
		youScoreLabel.text = str(myScore).pad_zeros(2)
	if is_instance_valid(timeRemainingLabel):
		var remaining_seconds := int(ceil(maxf(0.0, 45.0 - elapsedTime)))
		timeRemainingLabel.text = "00:" + str(remaining_seconds).pad_zeros(2)

func _replay_unfinished_basketball_shots() -> void:
	var unfinished: Array[Dictionary] = []
	for shot in recovery_shots:
		if not bool(shot.get("finished", false)):
			unfinished.append(shot)
	if unfinished.is_empty():
		_finish_basketball_recovery()
		return
	var previous_time := float(unfinished[0].get("time", 0.0))
	for shot in unfinished:
		var shot_time := float(shot.get("time", previous_time))
		var delay := maxf(0.0, shot_time - previous_time)
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
		if not recovery_restore_in_progress:
			return
		_launch_recovered_basketball_shot(shot)
		previous_time = shot_time
	await get_tree().create_timer(2.6).timeout
	if recovery_restore_in_progress:
		_finish_basketball_recovery()

func _schedule_basketball_recovery_check(allow_waiting: bool = false) -> void:
	recovery_allow_waiting = recovery_allow_waiting or allow_waiting

	if recovery_check_scheduled:
		return

	recovery_check_scheduled = true
	call_deferred("_run_basketball_recovery_check")

func _run_basketball_recovery_check() -> void:
	recovery_check_scheduled = false

	if not is_inside_tree() or not _ui_initialized or not gameDataSet:
		return

	var recovered: bool = _restore_basketball_recovery()

	if recovered:
		recovery_allow_waiting = false
		return

	allow_waiting_from_loaded_data = recovery_allow_waiting
	recovery_allow_waiting = false
	refresh_ui_state()
	allow_waiting_from_loaded_data = false

func _restore_basketball_recovery() -> bool:
	if recovery_loaded or not _ui_initialized or spectator_mode or game_over or not isTurn:
		return false

	recovery_pending_send = recovery_snapshot_pending

	OpLog.i(LOG_TAG, ["recovery_snapshot pending=", recovery_pending_send, " progressLen=", recovery_snapshot_progress.length()])

	if recovery_pending_send:
		recovery_loaded = true
		gamePlaying = false
		replayPlaying = false
		round_container.visible = false
		stop_waiting_animation()
		return true

	var raw_progress := recovery_snapshot_progress
	if raw_progress.is_empty():
		return false

	var parsed: Variant = JSON.parse_string(raw_progress)
	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.w(LOG_TAG, ["recovery_snapshot invalid JSON len=", raw_progress.length()])
		return false

	var progress: Dictionary = parsed

	if String(progress.get("phase", "")) != "round":
		return false

	if int(String(progress.get("turn", "-1"))) != int(turnNum):
		OpLog.i(LOG_TAG, ["recovery_snapshot stale savedTurn=", progress.get("turn", ""), " currentTurn=", turnNum])
		return false

	recovery_deadline_ms = int(String(progress.get("deadline", "0")))
	recovery_round_start_score = int(String(progress.get("roundStartScore", "0")))
	recovery_shots.clear()

	var raw_shots_value: Variant = progress.get("shots", [])
	var raw_shots: Array = []

	if typeof(raw_shots_value) == TYPE_ARRAY:
		raw_shots = raw_shots_value
	elif typeof(raw_shots_value) == TYPE_STRING:
		var parsed_shots: Variant = JSON.parse_string(String(raw_shots_value))
		if typeof(parsed_shots) == TYPE_ARRAY:
			raw_shots = parsed_shots

	for value in raw_shots:
		if typeof(value) == TYPE_DICTIONARY:
			var shot: Dictionary = value
			recovery_shots.append(shot.duplicate(true))

	recovery_loaded = true
	recovery_restore_in_progress = true
	gamePlaying = true
	replayPlaying = false
	replayFinished = false
	receivedMessage = null
	_score_run_id += 1
	_scored_shot_keys.clear()

	clearBalls()

	ballNum = {
		1: 1,
		2: 1,
	}

	myScore = _recovery_score()
	myReplay = _build_recovery_replay()

	if is_instance_valid(youScoreLabel):
		youScoreLabel.text = str(myScore).pad_zeros(2)

	if is_instance_valid(round_container):
		round_container.visible = false

	if is_instance_valid(waiting_blur):
		waiting_blur.visible = false

	stop_waiting_animation()

	OpLog.i(LOG_TAG, ["recovery_loaded turn=", turnNum, " shots=", recovery_shots.size(), " score=", myScore, " replayShots=", _replay_shot_count(myReplay), " deadline=", recovery_deadline_ms])

	_replay_unfinished_basketball_shots()
	return true

func _get_local_active_ball() -> BasketballBall:
	if spectator_mode or recovery_restore_in_progress:
		return null

	if player == null:
		return null

	if not gamePlaying:
		return null

	return currentBall.get(
		int(player),
		null,
	) as BasketballBall


func _begin_ball_drag(
	screen_position: Vector2,
) -> bool:
	var active_ball := _get_local_active_ball()

	if not is_instance_valid(
		active_ball,
	):
		return false

	var camera := get_viewport().get_camera_3d()

	if camera == null:
		return false

	var ball_screen_position := (
		camera.unproject_position(
			active_ball.global_position,
		)
	)

	if (
		screen_position.distance_to(
			ball_screen_position,
		) >
		120.0
	):
		return false

	drag_start_pos = screen_position
	drag_previous_pos = screen_position
	drag_smoothed_speed = 0.0
	dragging = true

	OpLog.i(
		LOG_TAG,
		[
			"drag_started player=",
			player,
			" screen=",
			screen_position,
			" ball=",
			active_ball.global_position,
		],
	)

	return true


func _cancel_ball_drag() -> void:
	dragging = false
	drag_smoothed_speed = 0.0
	active_drag_touch_index = -1


func _calculate_ios_target_x(
	camera: Camera3D,
	drag_end_position: Vector2,
) -> float:
	var drag_direction := (
		drag_end_position -
		drag_start_pos
	)

	if absf(
		drag_direction.y,
	) < 0.001:
		return 0.0

	var reference_screen_position := (
		camera.unproject_position(
			IOS_AIM_REFERENCE,
		)
	)

	var extension_amount := (
		(
			reference_screen_position.y -
			drag_start_pos.y
		) /
		drag_direction.y
	)

	var target_screen_position := Vector2(
		drag_start_pos.x +
			drag_direction.x *
			extension_amount,
		reference_screen_position.y,
	)

	var camera_space_reference := (
		camera.global_transform.affine_inverse() *
		IOS_AIM_REFERENCE
	)

	var reference_depth := (
		-camera_space_reference.z
	)

	var target_world_position := (
		camera.project_position(
			target_screen_position,
			reference_depth,
		)
	)

	var raw_target_x := (
		target_world_position.x
	)

	if game_mode == "n":
		var hoop_center_x := (
			static_net_collision_point.global_position.x
		)

		return lerpf(
			raw_target_x,
			hoop_center_x,
			IOS_NORMAL_AIM_ASSIST,
		)

	return raw_target_x


func _launch_ball_from_drag(
	active_ball: BasketballBall,
	drag_end_position: Vector2,
) -> void:
	if not is_instance_valid(
		active_ball,
	):
		_cancel_ball_drag()
		return

	var camera := get_viewport().get_camera_3d()

	if camera == null:
		_cancel_ball_drag()
		return

	var local_player_num := int(
		player,
	)

	var target_x := _calculate_ios_target_x(
		camera,
		drag_end_position,
	)

	var shot_number := (
		int(
			ballNum.get(
				local_player_num,
				1,
			),
		) -
		1
	)

	dragging = false
	active_drag_touch_index = -1

	OpLog.i(
		LOG_TAG,
		[
			"ios_shot_release player=",
			local_player_num,
			" start=",
			drag_start_pos,
			" end=",
			drag_end_position,
			" distance=",
			drag_start_pos.distance_to(
				drag_end_position,
			),
			" speed=",
			drag_smoothed_speed,
			" targetX=",
			target_x,
			" ballX=",
			active_ball.global_position.x,
			" shotNum=",
			shot_number,
		],
	)

	var saved_replay_x := get_saved_replay_x(target_x)
	_record_basketball_release(shot_number, target_x, saved_replay_x)
	active_ball.shoot(target_x)

	if (
		currentBall.get(
			local_player_num,
		) ==
		active_ball
	):
		currentBall[local_player_num] = null

	await get_tree().create_timer(
		20.0 /
			REPLAY_FRAME_RATE,
	).timeout

	if (
		gamePlaying and
		player != null and
		int(player) ==
			local_player_num and
		not is_instance_valid(
			currentBall.get(
				local_player_num,
			),
		)
	):
		spawnBall(
			local_player_num,
		)


func _update_ball_drag(
	screen_position: Vector2,
) -> void:
	if not dragging:
		return

	var active_ball := _get_local_active_ball()

	if not is_instance_valid(
		active_ball,
	):
		_cancel_ball_drag()
		return

	var movement_distance := (
		screen_position.distance_to(
			drag_previous_pos,
		)
	)

	drag_smoothed_speed = (
		drag_smoothed_speed +
		movement_distance
	) * 0.5

	drag_previous_pos = screen_position

	var total_distance := (
		screen_position.distance_to(
			drag_start_pos,
		)
	)

	var upward_distance := (
		drag_start_pos.y -
		screen_position.y
	)

	if total_distance <= IOS_DRAG_RELEASE_DISTANCE:
		return

	if drag_smoothed_speed <= IOS_DRAG_RELEASE_SPEED:
		return

	if upward_distance <= 0.0:
		return

	_launch_ball_from_drag(
		active_ball,
		screen_position,
	)


func _input(
	event: InputEvent,
) -> void:
	if _settings_open or _rules_open:
		if dragging:
			_cancel_ball_drag()

		return

	if spectator_mode:
		return

	if event is InputEventScreenTouch:
		var touch_event := (
			event as InputEventScreenTouch
		)

		if touch_event.pressed:
			if not dragging:
				if _begin_ball_drag(
					touch_event.position,
				):
					active_drag_touch_index = (
						touch_event.index
					)

			return

		if (
			dragging and
			active_drag_touch_index ==
				touch_event.index
		):
			_update_ball_drag(
				touch_event.position,
			)

			if dragging:
				_cancel_ball_drag()

		return

	if event is InputEventScreenDrag:
		var drag_event := (
			event as InputEventScreenDrag
		)

		if (
			dragging and
			active_drag_touch_index ==
				drag_event.index
		):
			_update_ball_drag(
				drag_event.position,
			)

		return

	if event is InputEventMouseButton:
		var mouse_button := (
			event as InputEventMouseButton
		)

		if (
			mouse_button.button_index !=
			MOUSE_BUTTON_LEFT
		):
			return

		if active_drag_touch_index >= 0:
			return

		if mouse_button.pressed:
			if not dragging:
				_begin_ball_drag(
					mouse_button.position,
				)

			return

		if dragging:
			_update_ball_drag(
				mouse_button.position,
			)

			if dragging:
				_cancel_ball_drag()

		return

	if event is InputEventMouseMotion:
		if active_drag_touch_index >= 0:
			return

		if not dragging:
			return

		var mouse_motion := (
			event as InputEventMouseMotion
		)

		_update_ball_drag(
			mouse_motion.position,
		)

func playReplay(
	player_num: int,
	replay_str: String,
) -> float:
	replayPlaying = true

	var parsed_shots: Array = []
	var last_shot_tick := 0

	for raw_shot in replay_str.split(
		"|",
		false,
	):
		var shot_text := String(
			raw_shot,
		).strip_edges()

		if shot_text.is_empty():
			continue

		var shot_parts := shot_text.split(
			",",
			false,
		)

		if shot_parts.size() < 4:
			OpLog.w(
				LOG_TAG,
				[
					"play_replay malformed shot=",
					shot_text,
				],
			)

			continue

		var shot_tick := maxi(
			int(
				shot_parts[0],
			),
			0,
		)

		last_shot_tick = maxi(
			last_shot_tick,
			shot_tick,
		)

		parsed_shots.append(
			{
				"time_tick": shot_tick,
				"saved_replay_x": float(
					shot_parts[1],
				),
				"did_go_in": (
					int(
						shot_parts[3],
					) !=
					0
				),
			},
		)

	parsed_shots.sort_custom(
		func(
			a: Dictionary,
			b: Dictionary,
		) -> bool:
			return (
				int(
					a["time_tick"],
				) <
				int(
					b["time_tick"],
				)
			)
	)

	_replay_shots[player_num] = parsed_shots
	_replay_spawn_tick[player_num] = -1

	OpLog.i(
		LOG_TAG,
		[
			"play_replay_loaded player=",
			player_num,
			" shots=",
			parsed_shots.size(),
			" lastTick=",
			last_shot_tick,
		],
	)

	if parsed_shots.is_empty():
		var unused_ball := currentBall.get(
			player_num,
		) as BasketballBall

		if is_instance_valid(
			unused_ball,
		):
			unused_ball.set_meta(
				"score_counted",
				true,
			)

			unused_ball.queue_free()

		currentBall[player_num] = null

		return 0.0

	var first_ball := currentBall.get(
		player_num,
	) as BasketballBall

	if is_instance_valid(
		first_ball,
	):
		first_ball.set_didGoInReplay(
			bool(
				parsed_shots[0][
					"did_go_in"
				],
			),
		)
	else:
		spawnBall(
			player_num,
			bool(
				parsed_shots[0][
					"did_go_in"
				],
			),
		)

	return (
		float(
			last_shot_tick,
		) /
		REPLAY_FRAME_RATE
	)

func _finish_replay(
	finalize_scores: bool = true,
) -> void:
	OpLog.i(
		LOG_TAG,
		[
			"finish_replay_start finalize=",
			finalize_scores,
			" turnNum=",
			turnNum,
			" replayFinished=",
			replayFinished,
			" ",
			_score_summary(),
		],
	)

	for timer in replayTimers:
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()

	replayTimers.clear()
	replayEndTimer = null
	_reset_replay_scheduler()

	clearBalls()

	if finalize_scores:
		if turnNum != null and int(turnNum) <= 3:
			setScore(
				1,
				int(score1 if score1 != null else 0),
			)

			setScore(
				2,
				int(score2 if score2 != null else 0),
			)
		elif turnNum != null and int(turnNum) >= 5:
			setScore(
				1,
				int(skip_score1 if skip_score1 != null else 0),
			)

			setScore(
				2,
				int(skip_score2 if skip_score2 != null else 0),
			)

	timeRemainingLabel.text = "00:00"

	if is_instance_valid(round_container):
		round_container.visible = false

	if is_instance_valid(skip_button):
		skip_button.visible = false

	replayPlaying = false
	replayFinished = true
	elapsedTime = 0.0

	stop_waiting_animation()

	OpLog.i(
		LOG_TAG,
		[
			"finish_replay_done gameOver=",
			game_over,
			" turn=",
			isTurn,
			" replayFinished=",
			replayFinished,
			" ",
			_score_summary(),
		],
	)

	refresh_ui_state()

func _check_ball_score_crossing(
	ball: BasketballBall,
) -> void:
	if not is_instance_valid(
		ball,
	):
		return

	if not gamePlaying and not replayPlaying:
		return

	if ball.get_meta(
		"score_counted",
		false,
	):
		return

	var ball_run_id := int(
		ball.get_meta(
			"score_run_id",
			-1,
		),
	)

	if ball_run_id != _score_run_id:
		ball.set_meta(
			"score_counted",
			true,
		)

		return

	var shot_key := String(
		ball.get_meta(
			"score_key",
			"",
		),
	)

	if (
		shot_key.is_empty() or
		_scored_shot_keys.has(
			shot_key,
		)
	):
		ball.set_meta(
			"score_counted",
			true,
		)

		return

	var score_position: Vector3

	if game_mode == "h":
		score_position = Vector3(
			_moving_hoop_x,
			IOS_MOVING_NET_Y,
			IOS_MOVING_NET_Z,
		)
	else:
		if not is_instance_valid(
			static_net_collision_point,
		):
			return

		score_position = (
			static_net_collision_point.global_position
		)

	var score_delta := (
		ball.global_position -
		score_position
	)

	var net_distance := (
		score_delta.length()
	)

	if net_distance >= SCORE_RADIUS:
		return

	ball.set_meta(
		"score_counted",
		true,
	)

	_scored_shot_keys[shot_key] = true

	if (
		replayPlaying and
		ball.didGoInReplay == false
	):
		OpLog.w(
			LOG_TAG,
			[
				"replay_net_entry_ignored expectedMiss player=",
				ball.player,
				" key=",
				shot_key,
				" distance=",
				net_distance,
			],
		)

		return

	ball.didGoIn = true

	var ball_player := int(
		ball.get_meta(
			"player_num",
			0,
		),
	)

	if ball_player == 0:
		return

	OpLog.i(
		LOG_TAG,
		[
			"score_net_distance player=",
			ball_player,
			" shotKey=",
			shot_key,
			" ball=",
			ball.global_position,
			" net=",
			score_position,
			" delta=",
			score_delta,
			" horizontalDistance=",
			Vector2(
				score_delta.x,
				score_delta.z,
			).length(),
			" distance=",
			net_distance,
			" hoopX=",
			_moving_hoop_x,
			" replayExpected=",
			str(
				ball.didGoInReplay,
			),
		],
	)

	incrementScore(ball_player)
	if not replayPlaying and player != null and ball_player == int(player):
		mark_basketball_shot_scored(int(ball.get_meta("shot_num", 0)))

func skipReplay():
	OpLog.i(LOG_TAG, ["skip_replay pressed turnNum=", turnNum])
	_finish_replay(true)

func _display_score_for_player(
	player_num: int,
) -> int:
	var round_one_score := 0
	var round_two_score := 0
	var round_two_replay = null

	if player_num == 1:
		round_one_score = int(
			score1 if score1 != null else 0,
		)

		round_two_score = int(
			skip_score1 if skip_score1 != null else round_one_score,
		)

		round_two_replay = replay3
	else:
		round_one_score = int(
			score2 if score2 != null else 0,
		)

		round_two_score = int(
			skip_score2 if skip_score2 != null else round_one_score,
		)

		round_two_replay = replay4

	if turnNum == null or int(turnNum) < 4:
		return round_one_score

	if int(turnNum) >= 5:
		return round_two_score

	if round_two_replay != null:
		return round_two_score

	return round_one_score

func refresh_ui_state() -> void:
	if gamePlaying or replayPlaying:
		round_container.visible = false
		skip_button.visible = false
		return

	var current_turn := int(
		turnNum if turnNum != null else 1,
	)

	var local_can_play := (
		_can_local_player_play_current_round()
	)

	isTurn = local_can_play

	OpLog.i(
		LOG_TAG,
		[
			"refresh_ui eligibility player=",
			player,
			" turnNum=",
			current_turn,
			" canPlay=",
			local_can_play,
			" replayFinished=",
			replayFinished,
		],
	)

	var replay_player1 = null
	var replay_player2 = null
	var replay_round := 0

	if current_turn == 3:
		replay_player1 = replay
		replay_player2 = replay2
		replay_round = 1
	elif current_turn >= 5:
		replay_player1 = replay3
		replay_player2 = replay4
		replay_round = 2

	var has_complete_replay := (
		replay_round > 0 and
		replay_player1 != null and
		replay_player2 != null
	)

	var current_replay_key := ""

	if has_complete_replay:
		current_replay_key = (
			str(replay_round) +
			"|" +
			String(replay_player1) +
			"|" +
			String(replay_player2)
		)

	var replay_loaded_from_data := (
		not current_replay_key.is_empty() and
		current_replay_key == _loaded_replay_key
	)

	if replay_loaded_from_data and not replayFinished:
		OpLog.i(
			LOG_TAG,
			[
				"refresh_ui start_completed_replay round=",
				replay_round,
				" turnNum=",
				current_turn,
				" isTurn=",
				isTurn,
				" spectator=",
				spectator_mode,
				" p1Shots=",
				_replay_shot_count(replay_player1),
				" p2Shots=",
				_replay_shot_count(replay_player2),
			],
		)

		stop_waiting_animation()

		if is_instance_valid(winner_label):
			winner_label.visible = false
			
		_clear_all_win_burst_proxies()

		round_container.visible = false
		skip_button.visible = true

		ballNum = {
			1: 1,
			2: 1,
		}

		_score_run_id += 1
		_scored_shot_keys.clear()
		
		if replay_round == 1:
			setScore(
				1,
				0,
			)

			setScore(
				2,
				0,
			)
		else:
			setScore(
				1,
				int(score1 if score1 != null else 0),
			)

			setScore(
				2,
				int(score2 if score2 != null else 0),
			)

		hoop_time = 0
		_hoop_acc = 0.0
		elapsedTime = 0.0
		replayPlaying = true

		if (
			hoop_center_tween and
			hoop_center_tween.is_running()
		):
			hoop_center_tween.kill()

		if is_instance_valid(moving_hoop_root):
			_set_moving_hoop_x(
				0.0,
			)

		clearBalls()
		_reset_replay_scheduler()

		spawnBall(
			1,
		)

		spawnBall(
			2,
		)

		var replay1_end := playReplay(
			1,
			String(replay_player1),
		)

		var replay2_end := playReplay(
			2,
			String(replay_player2),
		)

		if (
			replayEndTimer != null and
			is_instance_valid(replayEndTimer)
		):
			replayEndTimer.stop()
			replayEndTimer.queue_free()

		replayEndTimer = Timer.new()

		replayTimers.append(
			replayEndTimer,
		)

		add_child(
			replayEndTimer,
		)

		replayEndTimer.one_shot = true

		replayEndTimer.timeout.connect(
			func() -> void:
				if replayPlaying:
					_finish_replay(
						true,
					)
		)

		replayEndTimer.wait_time = maxf(
			maxf(
				replay1_end,
				replay2_end,
			) + 5.6,
			1.0,
		)

		replayEndTimer.start()
		return

	if (
		current_turn >= 5 and
		replay_loaded_from_data and
		replayFinished
	):
		stop_waiting_animation()

		round_container.visible = false
		skip_button.visible = false
		waiting_blur.visible = false

		setScore(
			1,
			int(skip_score1 if skip_score1 != null else 0),
		)

		setScore(
			2,
			int(skip_score2 if skip_score2 != null else 0),
		)

		game_over = true
		showWinner()

		if (
			not spectator_mode and
			not loaded_has_winner and
			not winner_sent and
			not isNullOrEmpty(my_player)
		):
			var win_value := 0

			if myScore > oppScore:
				win_value = 1
			elif myScore < oppScore:
				win_value = -1

			var winner_data: Dictionary = {
				"game": "basketball",
				"player": str(player),
				"mode": game_mode,
				"round": "2",
				"seed": str(
					game_seed if game_seed != null else 0,
				),
				"seed2": str(
					seed2 if seed2 != null else 0,
				),
				"score1": str(
					score1 if score1 != null else 0,
				),
				"score2": str(
					score2 if score2 != null else 0,
				),
				"skip_score1": str(
					skip_score1 if skip_score1 != null else 0,
				),
				"skip_score2": str(
					skip_score2 if skip_score2 != null else 0,
				),
				"replay": str(
					replay if replay != null else "",
				),
				"replay2": str(
					replay2 if replay2 != null else "",
				),
				"replay3": str(
					replay3 if replay3 != null else "",
				),
				"replay4": str(
					replay4 if replay4 != null else "",
				),
				"winner": (
					str(my_player) +
					"|" +
					str(win_value)
				),
			}

			var local_player_id_key := (
				"player1"
				if player == 1
				else "player2"
			)

			winner_data[local_player_id_key] = str(
				my_player,
			)

			var avatar_key := (
				"avatar1"
				if player == 1
				else "avatar2"
			)

			if (
				is_instance_valid(player_avatar_display) and
				player_avatar_display.has_method(
					"get_avatar_data_string",
				)
			):
				winner_data[avatar_key] = (
					player_avatar_display.get_avatar_data_string()
				)

			winner_sent = true
			loaded_has_winner = true

			var serialized_winner_data := JSON.stringify(
				winner_data,
			)

			OpLog.event(
				LOG_TAG,
				[
					"send_missing_winner winner=",
					winner_data["winner"],
					" raw=",
					serialized_winner_data,
				],
			)

			appPlugin = Engine.get_singleton(
				"AppPlugin",
			)

			if appPlugin:
				appPlugin.updateGameData(
					serialized_winner_data,
				)
			else:
				OpLog.w(
					LOG_TAG,
					[
						"missing_winner_not_sent AppPlugin unavailable raw=",
						serialized_winner_data,
					],
				)

		return

	if current_turn == 3 and replay_loaded_from_data and replayFinished:
		setScore(
			1,
			int(score1 if score1 != null else 0),
		)

		setScore(
			2,
			int(score2 if score2 != null else 0),
		)

		if local_can_play:
			stop_waiting_animation()

			waiting_blur.visible = true
			round_label.text = "Round 2"
			round_container.visible = true
			skip_button.visible = false

			OpLog.i(
				LOG_TAG,
				[
					"round_ready round=2 turnNum=",
					current_turn,
					" ",
					_score_summary(),
				],
			)
		else:
			round_container.visible = false
			skip_button.visible = false

			if not spectator_mode:
				start_waiting_animation()

		return

	if current_turn == 3 and not replay_loaded_from_data:
		round_container.visible = false
		skip_button.visible = false

		setScore(
			1,
			_display_score_for_player(1),
		)

		setScore(
			2,
			_display_score_for_player(2),
		)

		if not spectator_mode and allow_waiting_from_loaded_data:
			start_waiting_animation()

		return

	if current_turn >= 5 and not replay_loaded_from_data:
		round_container.visible = false
		skip_button.visible = false

		setScore(
			1,
			_display_score_for_player(1),
		)

		setScore(
			2,
			_display_score_for_player(2),
		)

		if not spectator_mode and allow_waiting_from_loaded_data:
			start_waiting_animation()

		return

	if current_turn == 4:
		setScore(
			1,
			_display_score_for_player(1),
		)

		setScore(
			2,
			_display_score_for_player(2),
		)

		if local_can_play:
			stop_waiting_animation()

			waiting_blur.visible = true
			round_label.text = "Round 2"
			round_container.visible = true
			skip_button.visible = false
		else:
			round_container.visible = false
			skip_button.visible = false

			if not spectator_mode and allow_waiting_from_loaded_data:
				start_waiting_animation()

		return

	if local_can_play:
		stop_waiting_animation()

		round_label.text = (
			"Round 2"
			if current_turn >= 3
			else "Round 1"
		)

		waiting_blur.visible = true
		round_container.visible = true
		skip_button.visible = false
		return

	round_container.visible = false
	skip_button.visible = false

	if current_turn >= 1:
		setScore(
			1,
			_display_score_for_player(1),
		)

		setScore(
			2,
			_display_score_for_player(2),
		)

	if not spectator_mode and allow_waiting_from_loaded_data:
		start_waiting_animation()

func spawnBall(
	player_num: int,
	didGoInReplay = null,
) -> BasketballBall:
	if appPlugin != null:
		var use_round_one_seed := false

		if replayPlaying:
			use_round_one_seed = (
				turnNum != null and
				int(turnNum) <= 3
			)
		else:
			use_round_one_seed = (
				turnNum == null or
				int(turnNum) < 3
			)

		appPlugin.srand48(
			player_num,
			game_seed if use_round_one_seed else seed2,
		)
	else:
		randomize()

	if ballNum[player_num] >= 1:
		var i: int = ballNum[player_num]

		while true:
			if appPlugin != null:
				appPlugin.drand48(
					player_num,
				)
			else:
				randf()

			if i == 1:
				break

			i -= 1

	var new_ball: BasketballBall = get_node(
		"Ball",
	).duplicate()

	var ball_mesh: MeshInstance3D = new_ball.get_child(
		1,
	)

	var roll_source: float = (
		appPlugin.drand48(player_num)
		if appPlugin != null
		else randf()
	)

	var pitch_source: float = (
		appPlugin.drand48(player_num)
		if appPlugin != null
		else randf()
	)

	var yaw_source: float = (
		appPlugin.drand48(player_num)
		if appPlugin != null
		else randf()
	)

	var roll: float = roll_source * 8.0 - 9.0
	var pitch: float = pitch_source * 20.0 + 70.0
	var yaw: float = yaw_source * 10.0 - 5.0

	var x_rand: float = (
		appPlugin.drand48(player_num)
		if appPlugin != null
		else randf()
	)

	var x_pos: float = x_rand * 0.66 - 0.33

	if player_num == 2:
		x_pos *= -1.0

	new_ball.set_player(
		player_num,
	)

	if didGoInReplay != null:
		new_ball.set_didGoInReplay(
			didGoInReplay,
		)

	new_ball.collision_layer = player_num
	new_ball.collision_mask = player_num

	new_ball.rotation = Vector3(
		roll,
		pitch,
		yaw,
	)

	new_ball.position = Vector3(
		x_pos,
		-0.45,
		-1.0,
	)

	new_ball.get_child(
		0,
	).disabled = false

	new_ball.axis_lock_angular_x = true
	new_ball.axis_lock_angular_y = true
	new_ball.axis_lock_angular_z = true
	new_ball.angular_velocity = Vector3.ZERO

	new_ball.freeze = false
	new_ball.sleeping = false
	new_ball.visible = true

	if player_num != player:
		ball_mesh.material_override = (
			ball_mesh.material_override.duplicate()
		)

		ball_mesh.material_override.albedo_color = Color(
			1.0,
			1.0,
			1.0,
			0.75,
		)

	var shot_num: int = int(
		ballNum[player_num],
	)

	new_ball.name = (
		"Ball_P" +
		str(player_num) +
		"_" +
		str(shot_num)
	)

	add_child(
		new_ball,
	)

	new_ball.set_meta(
		"player_num",
		player_num,
	)

	new_ball.set_meta(
		"shot_num",
		shot_num,
	)

	new_ball.set_meta(
		"score_run_id",
		_score_run_id,
	)

	new_ball.set_meta(
		"score_key",
		"%d:%d:%d" % [
			_score_run_id,
			player_num,
			shot_num,
		],
	)

	new_ball.set_meta(
		"score_counted",
		false,
	)

	ballNum[player_num] += 1
	currentBall[player_num] = new_ball

	dbg(
		[
			"spawn_ball player=",
			player_num,
			" shotNum=",
			shot_num,
			" replayResult=",
			str(didGoInReplay),
			" pos=",
			new_ball.position,
			" rot=",
			new_ball.rotation,
			" runId=",
			_score_run_id,
			" key=",
			new_ball.get_meta("score_key"),
		],
	)

	return new_ball

func _set_game_data(
	new_replay: String,
	saved: bool = false,
) -> void:
	OpLog.event(
		LOG_TAG,
		[
			"set_game_data_in saved=",
			saved,
			" raw=",
			new_replay,
		],
	)

	var parsed = JSON.parse_string(
		new_replay,
	)

	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.e(
			LOG_TAG,
			[
				"set_game_data invalid JSON raw=",
				new_replay,
			],
		)

		return
	
	var recovery_pending_value: Variant = parsed.get("_recoveryPending", "false")
	recovery_snapshot_pending = String(recovery_pending_value).to_lower() == "true"
	recovery_snapshot_progress = String(parsed.get("_recoveryProgress", ""))

	if gamePlaying or replayPlaying:
		OpLog.i(
			LOG_TAG,
			[
				"set_game_data deferred activeRound=",
				gamePlaying,
				" replayPlaying=",
				replayPlaying,
				" rawLen=",
				new_replay.length(),
			],
		)

		receivedMessage = new_replay
		return

	loaded_has_winner = (
		parsed.has("winner") and
		not isNullOrEmpty(
			str(parsed["winner"]),
		)
	)

	winner_sent = loaded_has_winner

	game_mode = str(
		parsed.get(
			"mode",
			game_mode,
		),
	)

	_apply_basketball_mode()

	if parsed.has("num"):
		turnNum = int(
			parsed["num"],
		)
	elif turnNum == null:
		turnNum = 1

	var payload_is_your_turn := bool(
		parsed.get(
			"isYourTurn",
			false,
		),
	)

	isTurn = payload_is_your_turn

	var payload_player := int(
		parsed.get(
			"player",
			1,
		),
	)

	my_player = parsed.get(
		"myPlayerId",
		my_player,
	)

	var player1_id := str(
		parsed.get(
			"player1",
			"",
		),
	)

	var player2_id := str(
		parsed.get(
			"player2",
			"",
		),
	)

	var my_player_id := str(
		my_player if my_player != null else "",
	)

	spectator_mode = false

	if (
		not my_player_id.is_empty() and
		not player1_id.is_empty() and
		not player2_id.is_empty()
	):
		spectator_mode = (
			my_player_id != player1_id and
			my_player_id != player2_id
		)

	if spectator_mode:
		player = 1
		isTurn = false
		gamePlaying = false

		if is_instance_valid(spectator_label):
			spectator_label.show()
	else:
		var resolved_player := payload_player

		if not my_player_id.is_empty():
			if (
				not player1_id.is_empty() and
				my_player_id == player1_id
			):
				resolved_player = 1
			elif (
				not player2_id.is_empty() and
				my_player_id == player2_id
			):
				resolved_player = 2
			elif (
				player1_id.is_empty() and
				not player2_id.is_empty() and
				my_player_id != player2_id
			):
				resolved_player = 1
			elif (
				player2_id.is_empty() and
				not player1_id.is_empty() and
				my_player_id != player1_id
			):
				resolved_player = 2
			elif isTurn:
				resolved_player = (
					2
					if payload_player == 1
					else 1
				)
		elif isTurn:
			resolved_player = (
				2
				if payload_player == 1
				else 1
			)

		player = resolved_player

		if is_instance_valid(spectator_label):
			spectator_label.hide()

	if is_instance_valid(you_label):
		you_label.modulate.a = 0.0 if spectator_mode else 1.0

	stop_waiting_animation()

	OpLog.i(
		LOG_TAG,
		[
			"player_resolve payloadPlayer=",
			payload_player,
			" localPlayer=",
			player,
			" payloadIsYourTurn=",
			payload_is_your_turn,
			" turnNum=",
			turnNum,
			" myId=",
			my_player_id,
			" player1Id=",
			player1_id,
			" player2Id=",
			player2_id,
		],
	)

	if spectator_mode:
		if (
			parsed.has("avatar1") and
			is_instance_valid(player_avatar_display)
		):
			var player1_avatar_data: Dictionary = (
				GameUtils._parse_avatar_string(
					str(parsed["avatar1"]),
				)
			)

			player_avatar_display.call_deferred(
				"update_avatar_from_data",
				player1_avatar_data,
			)

		if (
			parsed.has("avatar2") and
			is_instance_valid(opp_avatar_display)
		):
			var player2_avatar_data: Dictionary = (
				GameUtils._parse_avatar_string(
					str(parsed["avatar2"]),
				)
			)

			opp_avatar_display.call_deferred(
				"update_avatar_from_data",
				player2_avatar_data,
			)
	else:
		var opponent_avatar_key := (
			"avatar2"
			if player == 1
			else "avatar1"
		)

		if (
			parsed.has(opponent_avatar_key) and
			is_instance_valid(opp_avatar_display)
		):
			var opponent_avatar_data: Dictionary = (
				GameUtils._parse_avatar_string(
					str(parsed[opponent_avatar_key]),
				)
			)

			opp_avatar_display.call_deferred(
				"update_avatar_from_data",
				opponent_avatar_data,
			)

	if parsed.has("seed"):
		game_seed = int(
			parsed["seed"],
		)

	if parsed.has("seed2"):
		seed2 = int(
			parsed["seed2"],
		)

	if parsed.has("score1"):
		score1 = int(
			parsed["score1"],
		)

	if parsed.has("score2"):
		score2 = int(
			parsed["score2"],
		)

	if parsed.has("skip_score1"):
		skip_score1 = int(
			parsed["skip_score1"],
		)

	if parsed.has("skip_score2"):
		skip_score2 = int(
			parsed["skip_score2"],
		)

	replay = (
		parsed["replay"]
		if parsed.has("replay")
		else null
	)

	replay2 = (
		parsed["replay2"]
		if parsed.has("replay2")
		else null
	)

	replay3 = (
		parsed["replay3"]
		if parsed.has("replay3")
		else null
	)

	replay4 = (
		parsed["replay4"]
		if parsed.has("replay4")
		else null
	)

	var normalized_turn := int(
		turnNum if turnNum != null else 1,
	)

	if normalized_turn <= 1:
		replay = null
		replay2 = null
		replay3 = null
		replay4 = null

	elif normalized_turn == 2:
		if payload_player == 1:
			replay2 = null
		else:
			replay = null

		replay3 = null
		replay4 = null

	elif normalized_turn == 3:
		replay3 = null
		replay4 = null

	elif normalized_turn == 4:
		if payload_player == 1:
			replay4 = null
		else:
			replay3 = null

	var incoming_replay_key := ""

	if (
		turnNum != null and
		int(turnNum) == 3 and
		replay != null and
		replay2 != null
	):
		incoming_replay_key = (
			"1|" +
			String(replay) +
			"|" +
			String(replay2)
		)
	elif (
		turnNum != null and
		int(turnNum) >= 5 and
		replay3 != null and
		replay4 != null
	):
		incoming_replay_key = (
			"2|" +
			String(replay3) +
			"|" +
			String(replay4)
		)

	if (
		not incoming_replay_key.is_empty() and
		incoming_replay_key != _loaded_replay_key
	):
		_loaded_replay_key = incoming_replay_key
		replayFinished = false
		game_over = false

		if is_instance_valid(winner_label):
			winner_label.visible = false
			
		_clear_all_win_burst_proxies()

		OpLog.i(
			LOG_TAG,
			[
				"new_completed_replay_pair keyLength=",
				incoming_replay_key.length(),
				" turnNum=",
				turnNum,
			],
		)
		
	isTurn = _can_local_player_play_current_round()

	OpLog.i(
		LOG_TAG,
		[
			"local_play_eligibility player=",
			player,
			" turnNum=",
			turnNum,
			" canPlay=",
			isTurn,
			" replay1Set=",
			replay != null,
			" replay2Set=",
			replay2 != null,
			" replay3Set=",
			replay3 != null,
			" replay4Set=",
			replay4 != null,
			" replayFinished=",
			replayFinished,
		],
	)

	receivedMessage = null
	gameDataSet = true

	OpLog.i(
		LOG_TAG,
		[
			"set_game_data_done turnNum=",
			turnNum,
			" payloadPlayer=",
			payload_player,
			" localPlayer=",
			player,
			" isTurn=",
			isTurn,
			" spectator=",
			spectator_mode,
			" mode=",
			game_mode,
			" replayFinished=",
			replayFinished,
			" loadedWinner=",
			loaded_has_winner,
			" replay1Shots=",
			_replay_shot_count(replay),
			" replay2Shots=",
			_replay_shot_count(replay2),
			" replay3Shots=",
			_replay_shot_count(replay3),
			" replay4Shots=",
			_replay_shot_count(replay4),
			" ",
			_score_summary(),
		],
	)

	_schedule_basketball_recovery_check(not saved)

func sendGameData(
	completed_score: int,
	completed_replay_value: String,
) -> void:
	var completed_turn := int(
		turnNum,
	)

	var outgoing_replay := completed_replay_value.strip_edges()

	while outgoing_replay.ends_with("|"):
		outgoing_replay = outgoing_replay.left(
			outgoing_replay.length() - 1,
		)

	var next_turn := completed_turn + 1
	var is_round_one := next_turn <= 3

	var score_key := (
		"score1"
		if player == 1
		else "score2"
	)

	var replay_key := (
		"replay"
		if player == 1
		else "replay2"
	)

	if not is_round_one:
		score_key = (
			"skip_score1"
			if player == 1
			else "skip_score2"
		)

		replay_key = (
			"replay3"
			if player == 1
			else "replay4"
		)

	if player == 1:
		if is_round_one:
			score1 = completed_score
			replay = outgoing_replay
		else:
			skip_score1 = completed_score
			replay3 = outgoing_replay
	else:
		if is_round_one:
			score2 = completed_score
			replay2 = outgoing_replay
		else:
			skip_score2 = completed_score
			replay4 = outgoing_replay

	turnNum = next_turn

	var game_data: Dictionary = {
		"game": "basketball",
		"player": str(player),
		"mode": game_mode,
		"seed": str(
			game_seed if game_seed != null else 0,
		),
		"seed2": str(
			seed2 if seed2 != null else 0,
		),
		"round": "1" if is_round_one else "2",
		"score1": str(
			score1 if score1 != null else 0,
		),
		"score2": str(
			score2 if score2 != null else 0,
		),
		"skip_score1": str(
			skip_score1 if skip_score1 != null else 0,
		),
		"skip_score2": str(
			skip_score2 if skip_score2 != null else 0,
		),
	}

	game_data[replay_key] = outgoing_replay

	if replay != null:
		game_data["replay"] = str(replay)

	if replay2 != null:
		game_data["replay2"] = str(replay2)

	if replay3 != null:
		game_data["replay3"] = str(replay3)

	if replay4 != null:
		game_data["replay4"] = str(replay4)

	if not isNullOrEmpty(my_player):
		var local_player_id_key := (
			"player1"
			if player == 1
			else "player2"
		)

		game_data[local_player_id_key] = str(
			my_player,
		)

	var avatar_key := (
		"avatar1"
		if player == 1
		else "avatar2"
	)

	if (
		is_instance_valid(player_avatar_display) and
		player_avatar_display.has_method(
			"get_avatar_data_string",
		)
	):
		game_data[avatar_key] = (
			player_avatar_display.get_avatar_data_string()
		)

	if next_turn >= 5 and not isNullOrEmpty(my_player):
		var opponent_final_score := int(
			skip_score2
			if player == 1 and skip_score2 != null
			else (
				skip_score1
				if player == 2 and skip_score1 != null
				else 0
			),
		)

		var win_value := 0

		if completed_score > opponent_final_score:
			win_value = 1
		elif completed_score < opponent_final_score:
			win_value = -1

		game_data["winner"] = (
			str(my_player) +
			"|" +
			str(win_value)
		)

		winner_sent = true
		loaded_has_winner = true

	var local_pair_complete := false

	if next_turn == 3:
		local_pair_complete = (
			replay != null and
			replay2 != null
		)
	elif next_turn >= 5:
		local_pair_complete = (
			replay3 != null and
			replay4 != null
		)

	game_over = false

	if is_instance_valid(winner_label):
		winner_label.visible = false
		
	_clear_all_win_burst_proxies()

	play_sent_animation()

	var serialized_game_data := JSON.stringify(
		game_data,
	)

	OpLog.event(
		LOG_TAG,
		[
			"send_game_out turnNum=",
			turnNum,
			" localPlayer=",
			player,
			" scoreKey=",
			score_key,
			" replayKey=",
			replay_key,
			" replayShots=",
			_replay_shot_count(outgoing_replay),
			" pairComplete=",
			local_pair_complete,
			" winner=",
			str(
				game_data.get(
					"winner",
					"",
				),
			),
			" raw=",
			serialized_game_data,
		],
	)

	appPlugin = Engine.get_singleton(
		"AppPlugin",
	)

	if appPlugin:
		appPlugin.updateGameData(
			serialized_game_data,
		)
	else:
		OpLog.w(
			LOG_TAG,
			[
				"AppPlugin not connected; payload not sent raw=",
				serialized_game_data,
			],
		)

func start_button_pressed() -> void:
	if spectator_mode:
		return

	if not _can_local_player_play_current_round():
		OpLog.w(
			LOG_TAG,
			[
				"start_pressed_blocked player=",
				player,
				" turnNum=",
				turnNum,
				" replay1Set=",
				replay != null,
				" replay2Set=",
				replay2 != null,
				" replay3Set=",
				replay3 != null,
				" replay4Set=",
				replay4 != null,
			],
		)

		refresh_ui_state()
		return

	round_container.visible = false
	waiting_blur.visible = false

	OpLog.i(
		LOG_TAG,
		[
			"start_pressed turnNum=",
			turnNum,
			" player=",
			player,
		],
	)

	startGame()

func startGame() -> void:
	OpLog.i(
		LOG_TAG,
		[
			"start_game player=",
			player,
			" turnNum=",
			turnNum,
			" mode=",
			game_mode,
			" runId=",
			_score_run_id + 1,
		],
	)

	if is_instance_valid(winner_label):
		winner_label.visible = false
		
	_clear_all_win_burst_proxies()

	game_over = false

	ballNum = {
		1: 1,
		2: 1,
	}

	_score_run_id += 1
	_scored_shot_keys.clear()

	myReplay = ""
	elapsedTime = 0.0
	recovery_deadline_ms = _recovery_now_ms() + 45000
	recovery_round_start_score = myScore
	recovery_shots.clear()
	recovery_loaded = true
	gamePlaying = true
	replayPlaying = false
	replayFinished = false
	receivedMessage = null

	for timer in replayTimers:
		if is_instance_valid(timer):
			timer.stop()
			timer.queue_free()

	replayTimers.clear()
	replayEndTimer = null
	_reset_replay_scheduler()

	hoop_time = 0
	_hoop_acc = 0.0

	if (
		hoop_center_tween and
		hoop_center_tween.is_running()
	):
		hoop_center_tween.kill()

	if is_instance_valid(moving_hoop_root):
		_set_moving_hoop_x(
			0.0,
		)
	
	_save_basketball_progress()
	
	spawnBall(
		player,
	)

	OpLog.i(
		LOG_TAG,
		[
			"start_game_done ",
			_score_summary(),
		],
	)

func _haptic_explosion(strength: float = 0.35, duration_ms: int = 22) -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return

	strength = clampf(strength, 0.0, 1.0)
	Input.vibrate_handheld(duration_ms, strength)

func incrementScore(
	player_num: int,
) -> void:
	if player_num == player:
		myScore += 1

		youScoreLabel.text = str(
			myScore,
		).pad_zeros(
			2,
		)

		_haptic_explosion()
	else:
		oppScore += 1

		oppScoreLabel.text = str(
			oppScore,
		).pad_zeros(
			2,
		)

	OpLog.i(
		LOG_TAG,
		[
			"score_increment player=",
			player_num,
			" ",
			_score_summary(),
		],
	)

func setScore(player_num: int, score: int) -> void:
	dbg(["set_score player=", player_num, " score=", score])

	if player_num == player:
		_haptic_explosion()
		myScore = score
		youScoreLabel.text = str(myScore).pad_zeros(2)
	else:
		oppScore = score
		oppScoreLabel.text = str(oppScore).pad_zeros(2)

	dbg(["set_score_done player=", player_num, " ", _score_summary()])

func isNullOrEmpty(value) -> bool:
	if value == null:
		return true
	return String(value).length() == 0

func clearBalls() -> void:
	var cleared := 0
	for node in get_children():
		if node.name.begins_with("Ball_P"):
			node.set_meta("score_counted", true)
			node.name = "Cleared_" + String(node.name)
			cleared += 1
			node.queue_free()

	currentBall[1] = null
	currentBall[2] = null
	dbg(["clear_balls count=", cleared])

func _physics_process(
	delta: float,
) -> void:
	if not gamePlaying and not replayPlaying:
		return

	_hoop_acc += (
		delta *
		REPLAY_FRAME_RATE
	)

	while _hoop_acc >= 1.0:
		hoop_time += 1
		_hoop_acc -= 1.0

		if (
			game_mode == "h" and
			is_instance_valid(
				moving_hoop_root,
			)
		):
			_set_moving_hoop_x(
				_hoop_x_at_tick(
					hoop_time,
				),
			)

		if replayPlaying:
			_advance_replay_frame()

	for node in get_children():
		if (
			node is BasketballBall and
			node.name.begins_with(
				"Ball_P",
			)
		):
			_check_ball_score_crossing(
				node as BasketballBall,
			)

func _process(
	delta: float,
) -> void:
	if not is_inside_tree():
		return

	if (
		(gamePlaying or replayPlaying) and
		not is_instance_valid(
			timeRemainingLabel,
		)
	):
		return
		
	if (
		game_mode == "h" and
		is_instance_valid(
			moving_hoop_root,
		) and
		not gamePlaying and
		not replayPlaying
	):
		hoop_time = 0
		_hoop_acc = 0.0

		var centered_x := lerpf(
			moving_hoop_root.position.x,
			0.0,
			0.04,
		)

		if absf(
			centered_x,
		) < 0.001:
			centered_x = 0.0

		_set_moving_hoop_x(
			centered_x,
		)

	if not gamePlaying and not replayPlaying:
		return

	if recovery_restore_in_progress:
		elapsedTime += delta
		return

	if recovery_deadline_ms > 0:
		_sync_recovery_elapsed()
	else:
		elapsedTime += delta

	var remaining_seconds := int(
		ceil(
			45.0 -
			elapsedTime,
		),
	)

	timeRemainingLabel.text = (
		"00:" +
		str(
			maxi(
				remaining_seconds,
				0,
			),
		).pad_zeros(2)
	)

	if remaining_seconds > 0:
		return

	timeRemainingLabel.text = "00:00"

	if replayPlaying:
		return

	elapsedTime = 0.0
	gamePlaying = false

	await get_tree().create_timer(
		3.0,
	).timeout

	var completed_player := int(
		player,
	)

	var completed_turn := int(
		turnNum,
	)

	var completed_score := int(
		myScore,
	)

	var completed_replay := String(
		myReplay,
	)

	while completed_replay.ends_with("|"):
		completed_replay = completed_replay.left(
			completed_replay.length() - 1,
		)

	OpLog.i(
		LOG_TAG,
		[
			"game_timer_done sending_data completedPlayer=",
			completed_player,
			" completedTurn=",
			completed_turn,
			" score=",
			completed_score,
			" replayShots=",
			_replay_shot_count(completed_replay),
		],
	)

	isTurn = false

	sendGameData(
		completed_score,
		completed_replay,
	)

	clearBalls()

	round_container.visible = false
	skip_button.visible = false

	var deferred_message = receivedMessage

	receivedMessage = null

	if deferred_message != null:
		var deferred_parsed = JSON.parse_string(
			String(
				deferred_message,
			),
		)

		var deferred_turn := -1

		if deferred_parsed is Dictionary:
			deferred_turn = int(
				deferred_parsed.get(
					"num",
					-1,
				),
			)

		if deferred_turn >= int(turnNum):
			OpLog.i(
				LOG_TAG,
				[
					"applying_deferred_message_after_send num=",
					deferred_turn,
				],
			)

			_set_game_data(
				String(
					deferred_message,
				),
				true,
			)
		else:
			OpLog.w(
				LOG_TAG,
				[
					"ignoring_stale_deferred_message deferredNum=",
					deferred_turn,
					" currentNum=",
					turnNum,
				],
			)

	OpLog.i(
		LOG_TAG,
		[
			"game_round_done localPlayer=",
			completed_player,
			" isTurn=",
			isTurn,
			" turnNum=",
			turnNum,
			" ",
			_score_summary(),
		],
	)

	refresh_ui_state()

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		return
	stop_waiting_animation()
	if sent_tween and sent_tween.is_running():
		sent_tween.kill()
	sent_label.text = "Sent"
	sent_label.visible = true
	sent_label.modulate.a = 1.0
	sent_label.scale = Vector2.ONE
	sent_label.pivot_offset = sent_label.get_size() / 2.0

func _on_basketball_send_complete() -> void:
	recovery_pending_send = false
	if game_over or not is_instance_valid(sent_label):
		return
	if sent_tween and sent_tween.is_running():
		sent_tween.kill()
	sent_label.text = "Sent ✔"
	sent_label.visible = true
	sent_label.modulate.a = 1.0
	sent_tween = create_tween()
	sent_tween.tween_interval(2.0)
	sent_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)
	sent_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0
		if not replayPlaying and not gamePlaying and isTurn == false:
			start_waiting_animation()
	)

func _on_basketball_send_failed() -> void:
	if sent_tween and sent_tween.is_running():
		sent_tween.kill()
	if is_instance_valid(sent_label):
		sent_label.visible = false
		sent_label.modulate.a = 1.0
	stop_waiting_animation()
