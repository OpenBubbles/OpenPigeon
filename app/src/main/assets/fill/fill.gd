extends BaseGame

@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var grid = %GridContainer
@onready var background = %Background
@onready var color_selector: HBoxContainer = %ColorSelectorContainer
@onready var left_bg: ColorRect = %LeftBG
@onready var right_bg: ColorRect = %RightBG
@onready var left_score_label: Label = %LeftScore
@onready var right_score_label: Label = %RightScore
@onready var sent_label: Label = %SentLabel
@onready var win_loss_label: Label = %WinLossLabel
@onready var spec_label: Label = %SpecLabel
@onready var you_label: Label = %YouLabel
@onready var fill_main_layout_vbox: VBoxContainer = %MainVBoxContainer
@onready var fill_top_hud_margin: MarginContainer = %ScoreMarginContainer
@onready var fill_score_top_spacer: Control = %FillScoreTopSpacer
@onready var fill_opponent_top_spacer: Control = %FillOpponentTopSpacer
@onready var fill_left_score_panel: Control = %LeftPlayer
@onready var fill_right_score_panel: Control = %RightPlayer
@onready var fill_board_center: CenterContainer = %GameAreaCenterContainer
@onready var fill_board_panel: PanelContainer = %BorderPanelContainer
@onready var fill_bottom_controls_hbox: HBoxContainer = %BottomItemHBoxContainer
@onready var fill_bottom_controls_margin: MarginContainer = %FillBottomControlsMargin

const COLORS = [0, 1, 2, 3, 4, 5]
const BOARD_WIDTH = 8
const BOARD_HEIGHT = 7

const COLOR_MAP = {
	0: Color(0.92, 0.13, 0.432), # Red
	1: Color(0.45, 0.75, 0.29),  # Green
	2: Color(0.96, 0.85, 0.13),  # Yellow
	3: Color(0.2, 0.55, 0.81),   # Blue
	4: Color(0.35, 0.25, 0.53),  # Purple
	5: Color(0.25, 0.25, 0.25)   # Black
}

const MUSIC_STREAM := preload("res://global/audio/fill.ogg")

var board: Array = []
var color_board: Array = []
var tween: Tween

var game_ended = false
var game_over = false
var win_loss_state = ""
var is_your_turn: bool = false
var is_my_turn: bool = false

var left_start: Vector2i
var right_start: Vector2i
var left_color: int
var right_color: int
var my_count: int
var op_count: int

var pre_board_data: Array = []
var post_board_data: Array = []
var player: int = 1
var sent_tween: Tween
var _loading_replay: bool = false
var _move_in_progress: bool = false

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
const LOG_TAG := "Filler"
var DEBUG_FILLER := false

const LANDSCAPE_BOARD_HEIGHT_RATIO := 0.80

const DEFAULT_CELL_SIZE := 64.0

const BOARD_REFERENCE_WIDTH := (
	DEFAULT_CELL_SIZE *
	BOARD_WIDTH
)

const BOARD_REFERENCE_HEIGHT := (
	DEFAULT_CELL_SIZE *
	BOARD_HEIGHT
)

const BASE_AVATAR_SIZE := Vector2(
	96.0,
	90.0,
)

const BASE_YOU_LABEL_FONT_SIZE := 18.0
const BASE_SCORE_TOP_SPACER_HEIGHT := 46.0
const BASE_OPPONENT_TOP_SPACER_HEIGHT := 26.0

const BASE_SCORE_PANEL_SIZE := Vector2(
	56.0,
	38.0,
)

const BASE_SCORE_FONT_SIZE := 24.0

const BASE_MENU_BUTTON_SIZE := Vector2(
	64.0,
	64.0,
)

const BASE_MENU_BUTTON_FONT_SIZE := 32.0

const BASE_COLOR_BUTTON_SIZE := 64.0
const BASE_COLOR_SELECTOR_SEPARATION := 8.0
const BASE_COLOR_SELECTOR_BOTTOM_GAP := 14.0
const LANDSCAPE_BOARD_SELECTOR_GAP: float = 24.0

const BASE_SIDE_MARGIN := 40.0
const BASE_TOP_MARGIN := 20.0
const BASE_BOTTOM_MARGIN := 30.0
const PORTRAIT_BOTTOM_AREA_HEIGHT := 250.0

const LANDSCAPE_AVATAR_MIN_SCALE := 2.05
const LANDSCAPE_AVATAR_MAX_SCALE := 2.35

const BASE_SPECTATOR_FONT_SIZE := 50.0
const BASE_SPECTATOR_HALF_WIDTH := 324.0
const BASE_SPECTATOR_HEIGHT := 220.0
const PORTRAIT_SPECTATOR_TOP_OFFSET := 90.0

const LANDSCAPE_OVERLAY_MIN_SCALE := 1.35
const LANDSCAPE_OVERLAY_MAX_SCALE := 1.65

const WIN_BURST_WRAPPER_NAME := (
	"ResponsiveWinBurstWrapper"
)

var _responsive_layout_pending := false
var _last_viewport_size := Vector2.ZERO

var _avatar_layout_generation := 0
var _current_avatar_scale := 1.0

var _active_win_burst_avatar: TextureButton = null

func dbg(msg: String) -> void:
	if DEBUG_FILLER:
		OpLog.d(LOG_TAG, msg)
	
func _get_dev_data() -> String:
	return '{ "isYourTurn": true, "player": "2", "seed": "0", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player2": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "id": "dev", "ios": "16.3.1", "num": "2", "game": "fill", "mode": "0", "tver": "5", "build": "56", "version": "0" }'
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Filler"

func _on_game_ready():
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)

	randomize()
	OpLog.i(LOG_TAG, ["game_ready dark_mode=", is_dark])

	setup_color_selector()
	init_color_selector_collapsed()
	setup_board_structure()

	OpLog.i(LOG_TAG, [
		"game_ready_done board=", BOARD_WIDTH, "x", BOARD_HEIGHT,
		" colors=", COLORS.size()
	])
	
	_initialize_responsive_layout()

func _set_game_data(new_game_data_json: String):
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", new_game_data_json])

	var parsed = JSON.parse_string(new_game_data_json)

	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, [
			"set_game_data_parse_failed type=", typeof(parsed),
			" raw=", new_game_data_json
		])
		return

	stop_pulsing_all_cells()
	stop_waiting_animation()
	hide_color_selector()

	game_over = false
	game_ended = false
	win_loss_state = ""
	spectator_mode = false
	_move_in_progress = false

	if is_instance_valid(win_loss_label):
		win_loss_label.visible = false
		win_loss_label.text = ""
		win_loss_label.scale = Vector2.ONE

	_active_win_burst_avatar = null
	_clear_all_win_burst_proxies()

	var data: Dictionary = parsed
	is_your_turn = bool(data.get("isYourTurn", false))

	var replay_str: String = String(data.get("replay", ""))
	var player1_id: String = String(data.get("player1", ""))
	var player2_id: String = String(data.get("player2", ""))
	var winner_payload: String = String(data.get("winner", ""))
	var sender_player: int = int(data.get("player", 1))

	OpLog.i(LOG_TAG, [
		"set_game_data_fields my_uuid=", my_uuid,
		" player1=", player1_id,
		" player2=", player2_id,
		" sender_player=", sender_player,
		" isYourTurn=", is_your_turn,
		" replay_len=", replay_str.length(),
		" has_seed=", data.has("seed"),
		" seed=", data.get("seed", "MISSING"),
		" has_winner=", winner_payload != ""
	])

	var opponent_avatar_key := ""

	if my_uuid != "" and player1_id != "" and player2_id != "":
		if my_uuid == player1_id:
			player = 1
			opponent_avatar_key = "avatar2"
		elif my_uuid == player2_id:
			player = 2
			opponent_avatar_key = "avatar1"
		else:
			spectator_mode = true
			player = 1
			opponent_avatar_key = "avatar2"
	else:
		player = (3 - sender_player) if is_your_turn else sender_player
		player = clamp(player, 1, 2)
		opponent_avatar_key = "avatar2" if player == 1 else "avatar1"

	is_my_turn = is_your_turn and not spectator_mode

	OpLog.i(LOG_TAG, [
		"resolved_player player=", player,
		" is_my_turn=", is_my_turn,
		" spectator=", spectator_mode,
		" opponent_avatar_key=", opponent_avatar_key
	])

	if is_instance_valid(spec_label):
		spec_label.visible = spectator_mode

	if is_instance_valid(you_label):
		you_label.text = "You"
		you_label.modulate.a = (
			0.0
			if spectator_mode
			else 1.0
		)

	_update_start_positions()

	if opponent_avatar_key != "" and data.has(opponent_avatar_key):
		var avatar_string = data[opponent_avatar_key]
		var opponent_data = GameUtils._parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	if spectator_mode and data.has("avatar1"):
		var p1_data = GameUtils._parse_avatar_string(data["avatar1"])
		if is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", p1_data)

	_schedule_responsive_layout(true)

	_loading_replay = true

	if replay_str != "":
		OpLog.i(LOG_TAG, ["replay_start len=", replay_str.length(), " play_animation=", is_my_turn])
		await parse_replay_string(replay_str, is_my_turn)
	else:
		OpLog.i(LOG_TAG, "new_board_generation")

		if data.has("seed") and str(data["seed"]).is_valid_int():
			OpLog.i(LOG_TAG, [
				"generate_board_from_seed seed=", data.get("seed", "MISSING"),
				" seed_type=", typeof(data.get("seed", null))
			])
			generate_filler_colors(int(data["seed"]))
		else:
			OpLog.w(LOG_TAG, [
				"generate_board_without_valid_seed seed=", data.get("seed", "MISSING"),
				" seed_type=", typeof(data.get("seed", null))
			])
			generate_filler_colors()

		apply_colors_to_cells()
		await _apply_visual_board_transform()
		update_ui_from_board_state()

	_loading_replay = false

	if winner_payload != "":
		OpLog.event(LOG_TAG, ["winner_payload_received payload=", winner_payload])
		_apply_winner_payload(winner_payload, player1_id, player2_id)
		return

	game_ended = check_win()

	if game_ended:
		stop_waiting_animation()
		hide_color_selector()
		game_over = true
	elif not spectator_mode and is_my_turn:
		call_deferred("show_color_selector")
		start_pulsing_my_cells()
		stop_waiting_animation()
	elif not spectator_mode:
		hide_color_selector()
		start_waiting_animation()
	else:
		hide_color_selector()
		stop_waiting_animation()

	OpLog.i(LOG_TAG, [
		"set_game_data_done player=", player,
		" player1_id=", player1_id,
		" player2_id=", player2_id,
		" is_my_turn=", is_my_turn,
		" spectator=", spectator_mode,
		" game_over=", game_over,
		" game_ended=", game_ended,
		" my_count=", my_count,
		" op_count=", op_count
	])

func _update_start_positions() -> void:
	if player == 2:
		left_start = Vector2i(BOARD_WIDTH - 1, BOARD_HEIGHT - 1)
		right_start = Vector2i(0, 0)
	else:
		left_start = Vector2i(0, 0)
		right_start = Vector2i(BOARD_WIDTH - 1, BOARD_HEIGHT - 1)
		
func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color(0.08, 0.08, 0.08) if is_dark else Color("#e5e5e5")

const FILLER_NUM_PIECES := 6
const FILLER_POLISH_ITERATIONS := 15

const _DRAND48_A: int = 0x5DEECE66D
const _DRAND48_C: int = 0xB
const _DRAND48_MASK: int = (1 << 48) - 1
const _DRAND48_M24: int = (1 << 24) - 1
const _DRAND48_DENOM: float = 281474976710656.0

var _drand48_state: int = 0

func _filler_srand48(seed_val: int) -> void:
	var s32: int = seed_val & 0xFFFFFFFF
	_drand48_state = ((s32 << 16) | 0x330E) & _DRAND48_MASK
	
func _configure_avatar_rendering(
	avatar_button: TextureButton,
) -> void:
	if not is_instance_valid(avatar_button):
		return

	avatar_button.clip_contents = false

	var internal_viewport: SubViewport = (
		avatar_button.get_node_or_null(
			"SubViewportContainer/SubViewport",
		) as SubViewport
	)

	if internal_viewport != null:
		internal_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS
		)

	var internal_preview: SubViewportContainer = (
		avatar_button.get_node_or_null(
			"SubViewportContainer",
		) as SubViewportContainer
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

func _initialize_responsive_layout() -> void:
	_configure_avatar_rendering(
		player_avatar_display,
	)

	_configure_avatar_rendering(
		opp_avatar_display,
	)

	var viewport := get_viewport()

	if viewport == null:
		return

	if not viewport.size_changed.is_connected(
		_on_viewport_size_changed,
	):
		viewport.size_changed.connect(
			_on_viewport_size_changed,
		)

	_schedule_responsive_layout(true)


func _on_viewport_size_changed() -> void:
	_schedule_responsive_layout(true)


func _schedule_responsive_layout(
	force: bool = false,
) -> void:
	if force:
		_last_viewport_size = Vector2.ZERO

	if _responsive_layout_pending:
		return

	_responsive_layout_pending = true

	call_deferred(
		"_apply_responsive_layout",
	)

func _reset_control_for_vbox(
	control: Control,
) -> void:
	if not is_instance_valid(control):
		return

	control.set_anchors_preset(
		Control.PRESET_TOP_LEFT,
	)

	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0

func _set_landscape_overlay_mode(
	enabled: bool,
) -> void:
	if color_selector.get_parent() != fill_main_layout_vbox:
		color_selector.reparent(
			fill_main_layout_vbox,
			false,
		)

	if enabled:
		if fill_top_hud_margin.get_parent() != self:
			fill_top_hud_margin.reparent(
				self,
				false,
			)

		if fill_bottom_controls_hbox.get_parent() != self:
			fill_bottom_controls_hbox.reparent(
				self,
				false,
			)

		fill_main_layout_vbox.move_child(
			fill_board_center,
			0,
		)

		fill_main_layout_vbox.move_child(
			color_selector,
			1,
		)

		fill_main_layout_vbox.alignment = (
			BoxContainer.ALIGNMENT_CENTER
		)

		fill_top_hud_margin.z_index = 20
		fill_bottom_controls_hbox.z_index = 20
		spec_label.z_index = 30

		fill_board_center.size_flags_horizontal = (
			Control.SIZE_SHRINK_CENTER
		)

		fill_board_center.size_flags_vertical = (
			Control.SIZE_SHRINK_CENTER
		)

		color_selector.size_flags_horizontal = (
			Control.SIZE_SHRINK_CENTER
		)

		color_selector.size_flags_vertical = (
			Control.SIZE_SHRINK_CENTER
		)

		fill_main_layout_vbox.queue_sort()
		return

	if fill_top_hud_margin.get_parent() != fill_main_layout_vbox:
		fill_top_hud_margin.reparent(
			fill_main_layout_vbox,
			false,
		)

	if fill_bottom_controls_hbox.get_parent() != fill_main_layout_vbox:
		fill_bottom_controls_hbox.reparent(
			fill_main_layout_vbox,
			false,
		)

	fill_main_layout_vbox.move_child(
		fill_top_hud_margin,
		0,
	)

	fill_main_layout_vbox.move_child(
		fill_board_center,
		1,
	)

	fill_main_layout_vbox.move_child(
		color_selector,
		2,
	)

	fill_main_layout_vbox.move_child(
		fill_bottom_controls_hbox,
		3,
	)

	fill_main_layout_vbox.alignment = (
		BoxContainer.ALIGNMENT_BEGIN
	)

	fill_top_hud_margin.z_index = 0
	fill_bottom_controls_hbox.z_index = 0

	_reset_control_for_vbox(
		fill_top_hud_margin,
	)

	_reset_control_for_vbox(
		fill_board_center,
	)

	_reset_control_for_vbox(
		color_selector,
	)

	_reset_control_for_vbox(
		fill_bottom_controls_hbox,
	)

	fill_top_hud_margin.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	fill_top_hud_margin.size_flags_vertical = (
		Control.SIZE_FILL
	)

	fill_board_center.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	fill_board_center.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)

	color_selector.size_flags_horizontal = (
		Control.SIZE_SHRINK_CENTER
	)

	color_selector.size_flags_vertical = (
		Control.SIZE_FILL
	)

	fill_bottom_controls_hbox.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	fill_bottom_controls_hbox.size_flags_vertical = (
		Control.SIZE_FILL
	)

	fill_main_layout_vbox.queue_sort()

	call_deferred(
		"_finish_portrait_layout_restore",
	)

func _finish_portrait_layout_restore() -> void:
	await get_tree().process_frame

	if not is_inside_tree():
		return

	_reset_control_for_vbox(
		fill_top_hud_margin,
	)

	_reset_control_for_vbox(
		fill_board_center,
	)

	_reset_control_for_vbox(
		color_selector,
	)

	_reset_control_for_vbox(
		fill_bottom_controls_hbox,
	)

	fill_main_layout_vbox.queue_sort()
	fill_top_hud_margin.queue_sort()
	fill_board_center.queue_sort()
	color_selector.queue_sort()
	fill_bottom_controls_hbox.queue_sort()

	await get_tree().process_frame

	if not is_inside_tree():
		return

	color_selector.pivot_offset = (
		color_selector.size *
		0.5
	)

	call_deferred(
		"_apply_visual_board_transform",
	)

func _set_fill_cell_size(
	cell_size: float,
) -> void:
	for row in board:
		for cell in row:
			if not is_instance_valid(cell):
				continue

			cell.custom_minimum_size = Vector2(
				cell_size,
				cell_size,
			)

func _apply_board_responsive_layout(
	viewport_size: Vector2,
	is_portrait: bool,
	selector_size: Vector2,
) -> float:
	var cell_size := DEFAULT_CELL_SIZE

	if not is_portrait:
		var target_stack_height := floorf(
			viewport_size.y *
			LANDSCAPE_BOARD_HEIGHT_RATIO
		)

		var selector_gap: float = LANDSCAPE_BOARD_SELECTOR_GAP

		var available_board_height := maxf(
			target_stack_height -
				selector_size.y -
				selector_gap,
			1.0,
		)

		var height_limited_cell_size := floorf(
			available_board_height /
				float(BOARD_HEIGHT)
		)

		var width_limited_cell_size := floorf(
			viewport_size.x /
				float(BOARD_WIDTH)
		)

		cell_size = maxf(
			minf(
				height_limited_cell_size,
				width_limited_cell_size,
			),
			1.0,
		)

		fill_main_layout_vbox.add_theme_constant_override(
			"separation",
			roundi(selector_gap),
		)

	_set_fill_cell_size(
		cell_size,
	)

	var board_width := (
		cell_size *
		BOARD_WIDTH
	)

	var board_height := (
		cell_size *
		BOARD_HEIGHT
	)

	grid.custom_minimum_size = Vector2(
		board_width,
		board_height,
	)

	fill_board_panel.custom_minimum_size = Vector2(
		board_width,
		board_height,
	)

	fill_board_center.custom_minimum_size = Vector2(
		board_width,
		board_height,
	)

	grid.queue_sort()
	fill_board_panel.queue_sort()
	fill_board_center.queue_sort()

	return board_height

func _apply_score_panel_layout(
	panel: Control,
	label: Label,
	avatar_scale: float,
) -> void:
	if not is_instance_valid(panel):
		return

	panel.custom_minimum_size = (
		BASE_SCORE_PANEL_SIZE *
		avatar_scale
	)

	if is_instance_valid(label):
		label.add_theme_font_size_override(
			"font_size",
			maxi(
				roundi(
					BASE_SCORE_FONT_SIZE *
					avatar_scale
				),
				1,
			),
		)


func _apply_menu_button_layout(
	avatar_scale: float,
) -> void:
	var button_size := (
		BASE_MENU_BUTTON_SIZE *
		avatar_scale
	)

	var menu_buttons: Array[Button] = [
		rules_button,
		settings_button,
	]

	for menu_button in menu_buttons:
		if not is_instance_valid(menu_button):
			continue

		menu_button.custom_minimum_size = button_size

		menu_button.add_theme_font_size_override(
			"font_size",
			maxi(
				roundi(
					BASE_MENU_BUTTON_FONT_SIZE *
					avatar_scale
				),
				1,
			),
		)

		menu_button.queue_redraw()


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
		if not is_instance_valid(avatar_button):
			continue

		_configure_avatar_rendering(
			avatar_button,
		)

		avatar_button.scale = Vector2.ONE
		avatar_button.custom_minimum_size = avatar_size

		var internal_preview := (
			avatar_button.get_node_or_null(
				"SubViewportContainer",
			) as SubViewportContainer
		)

		if internal_preview != null:
			internal_preview.scale = Vector2.ONE * avatar_scale

		avatar_button.queue_redraw()

		var avatar_parent := (
			avatar_button.get_parent()
			as Container
		)

		if avatar_parent != null:
			avatar_parent.queue_sort()

	if is_instance_valid(you_label):
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

	fill_score_top_spacer.custom_minimum_size = Vector2(
		0.0,
		BASE_SCORE_TOP_SPACER_HEIGHT *
			avatar_scale,
	)

	fill_opponent_top_spacer.custom_minimum_size = Vector2(
		0.0,
		BASE_OPPONENT_TOP_SPACER_HEIGHT *
			avatar_scale,
	)

	_apply_score_panel_layout(
		fill_left_score_panel,
		left_score_label,
		avatar_scale,
	)

	_apply_score_panel_layout(
		fill_right_score_panel,
		right_score_label,
		avatar_scale,
	)

	_apply_menu_button_layout(
		avatar_scale,
	)

	_avatar_layout_generation += 1

	call_deferred(
		"_finalize_avatar_responsive_layout",
		_avatar_layout_generation,
	)


func _apply_color_selector_responsive_layout(
	content_scale: float,
	is_portrait: bool,
) -> Vector2:
	var selector_scale := 1.0

	if not is_portrait:
		selector_scale = clampf(
			content_scale,
			0.78,
			1.25,
		)

	var button_size := (
		BASE_COLOR_BUTTON_SIZE *
		selector_scale
	)

	var separation := (
		BASE_COLOR_SELECTOR_SEPARATION *
		selector_scale
	)

	color_selector.add_theme_constant_override(
		"separation",
		roundi(separation),
	)

	for wrapper in color_selector.get_children():
		if not wrapper is Control:
			continue

		var wrapper_control := wrapper as Control

		wrapper_control.custom_minimum_size = Vector2(
			button_size,
			button_size,
		)

		var button := (
			wrapper_control.find_child(
				"Color_*",
				true,
				false,
			) as Button
		)

		if button == null:
			continue

		button.custom_minimum_size = Vector2(
			button_size,
			button_size,
		)

		button.pivot_offset = (
			button.custom_minimum_size *
			0.5
		)

	var selector_width := (
		button_size *
			float(COLORS.size()) +
		separation *
			float(COLORS.size() - 1)
	)

	var selector_size := Vector2(
		selector_width,
		button_size,
	)

	color_selector.custom_minimum_size = selector_size
	color_selector.queue_sort()

	return selector_size


func _apply_landscape_overlay_positions(
	avatar_scale: float,
) -> void:
	var side_margin := (
		BASE_SIDE_MARGIN *
		avatar_scale
	)

	var top_margin := (
		BASE_TOP_MARGIN *
		avatar_scale
	)

	var bottom_margin := (
		BASE_BOTTOM_MARGIN *
		avatar_scale
	)

	fill_top_hud_margin.add_theme_constant_override(
		"margin_left",
		roundi(side_margin),
	)

	fill_top_hud_margin.add_theme_constant_override(
		"margin_top",
		roundi(top_margin),
	)

	fill_top_hud_margin.add_theme_constant_override(
		"margin_right",
		roundi(side_margin),
	)

	var avatar_stack_height := (
		BASE_AVATAR_SIZE.y *
			avatar_scale +
		BASE_YOU_LABEL_FONT_SIZE *
			avatar_scale +
		top_margin
	)

	var score_stack_height := (
		BASE_SCORE_PANEL_SIZE.y *
			avatar_scale +
		BASE_SCORE_TOP_SPACER_HEIGHT *
			avatar_scale +
		top_margin
	)

	var top_hud_height := maxf(
		avatar_stack_height,
		score_stack_height,
	)

	fill_top_hud_margin.set_anchors_preset(
		Control.PRESET_TOP_WIDE,
	)

	fill_top_hud_margin.offset_left = 0.0
	fill_top_hud_margin.offset_top = 0.0
	fill_top_hud_margin.offset_right = 0.0
	fill_top_hud_margin.offset_bottom = top_hud_height

	fill_bottom_controls_margin.add_theme_constant_override(
		"margin_left",
		roundi(side_margin),
	)

	fill_bottom_controls_margin.add_theme_constant_override(
		"margin_right",
		roundi(side_margin),
	)

	fill_bottom_controls_margin.add_theme_constant_override(
		"margin_bottom",
		roundi(bottom_margin),
	)

	var bottom_height := (
		BASE_MENU_BUTTON_SIZE.y *
			avatar_scale +
		bottom_margin
	)

	fill_bottom_controls_hbox.custom_minimum_size = Vector2(
		0.0,
		bottom_height,
	)

	fill_bottom_controls_hbox.set_anchors_preset(
		Control.PRESET_BOTTOM_WIDE,
	)

	fill_bottom_controls_hbox.offset_left = 0.0
	fill_bottom_controls_hbox.offset_top = -bottom_height
	fill_bottom_controls_hbox.offset_right = 0.0
	fill_bottom_controls_hbox.offset_bottom = 0.0

	fill_top_hud_margin.queue_sort()
	fill_bottom_controls_hbox.queue_sort()

func _restore_portrait_container_layout() -> void:
	fill_top_hud_margin.add_theme_constant_override(
		"margin_left",
		roundi(BASE_SIDE_MARGIN),
	)

	fill_top_hud_margin.add_theme_constant_override(
		"margin_top",
		roundi(BASE_TOP_MARGIN),
	)

	fill_top_hud_margin.add_theme_constant_override(
		"margin_right",
		roundi(BASE_SIDE_MARGIN),
	)

	fill_bottom_controls_margin.add_theme_constant_override(
		"margin_left",
		roundi(BASE_SIDE_MARGIN),
	)

	fill_bottom_controls_margin.add_theme_constant_override(
		"margin_right",
		roundi(BASE_SIDE_MARGIN),
	)

	fill_bottom_controls_margin.add_theme_constant_override(
		"margin_bottom",
		roundi(BASE_BOTTOM_MARGIN),
	)

	fill_bottom_controls_hbox.custom_minimum_size = Vector2(
		0.0,
		PORTRAIT_BOTTOM_AREA_HEIGHT,
	)

	fill_main_layout_vbox.add_theme_constant_override(
		"separation",
		0,
	)

	_reset_control_for_vbox(
		fill_top_hud_margin,
	)

	_reset_control_for_vbox(
		fill_board_center,
	)

	_reset_control_for_vbox(
		color_selector,
	)

	_reset_control_for_vbox(
		fill_bottom_controls_hbox,
	)

	fill_main_layout_vbox.queue_sort()

func _apply_spectator_label_responsive_layout(
	content_scale: float,
	is_portrait: bool,
) -> void:
	if not is_instance_valid(spec_label):
		return

	var overlay_scale := 1.0

	if not is_portrait:
		overlay_scale = clampf(
			content_scale,
			LANDSCAPE_OVERLAY_MIN_SCALE,
			LANDSCAPE_OVERLAY_MAX_SCALE,
		)

	var top_offset := (
		PORTRAIT_SPECTATOR_TOP_OFFSET
		if is_portrait
		else 0.0
	)

	spec_label.set_anchors_preset(
		Control.PRESET_CENTER_TOP,
	)

	spec_label.offset_left = (
		-BASE_SPECTATOR_HALF_WIDTH *
		overlay_scale
	)

	spec_label.offset_right = (
		BASE_SPECTATOR_HALF_WIDTH *
		overlay_scale
	)

	spec_label.offset_top = top_offset

	spec_label.offset_bottom = (
		top_offset +
		BASE_SPECTATOR_HEIGHT *
			overlay_scale
	)

	spec_label.grow_horizontal = (
		Control.GROW_DIRECTION_BOTH
	)

	spec_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	spec_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	spec_label.add_theme_font_size_override(
		"font_size",
		maxi(
			roundi(
				BASE_SPECTATOR_FONT_SIZE *
					overlay_scale
			),
			1,
		),
	)


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

	var is_portrait := (
		viewport_size.y >=
		viewport_size.x
	)

	_set_landscape_overlay_mode(
		not is_portrait,
	)

	var selector_scale_hint := 1.0

	if not is_portrait:
		selector_scale_hint = clampf(
			viewport_size.y /
				BOARD_REFERENCE_HEIGHT,
			0.78,
			1.25,
		)

	var selector_size := (
		_apply_color_selector_responsive_layout(
			selector_scale_hint,
			is_portrait,
		)
	)

	var board_height := (
		_apply_board_responsive_layout(
			viewport_size,
			is_portrait,
			selector_size,
		)
	)

	var content_scale := clampf(
		board_height /
			BOARD_REFERENCE_HEIGHT,
		0.5,
		2.0,
	)

	_apply_avatar_responsive_layout(
		content_scale,
		is_portrait,
		viewport_size,
	)

	if is_portrait:
		_restore_portrait_container_layout()
	else:
		_apply_landscape_overlay_positions(
			_current_avatar_scale,
		)

	_apply_spectator_label_responsive_layout(
		content_scale,
		is_portrait,
	)

	fill_main_layout_vbox.queue_sort()
	fill_board_center.queue_sort()


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
		if not is_instance_valid(avatar_button):
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
		if not is_instance_valid(avatar_button):
			continue

		avatar_button.scale = Vector2.ONE

		avatar_button.pivot_offset = (
			avatar_button.size *
			0.5
		)

		avatar_button.queue_redraw()

	call_deferred(
		"_apply_visual_board_transform",
	)

	_clear_all_win_burst_proxies()

	if (
		is_instance_valid(win_loss_label) and
		win_loss_label.visible and
		is_instance_valid(_active_win_burst_avatar)
	):
		_show_win_burst_for_avatar(
			_active_win_burst_avatar,
		)

func _filler_drand48() -> float:
	var a_hi: int = _DRAND48_A >> 24
	var a_lo: int = _DRAND48_A & _DRAND48_M24
	var x_hi: int = (_drand48_state >> 24) & _DRAND48_M24
	var x_lo: int = _drand48_state & _DRAND48_M24

	var low: int = (a_lo * x_lo) + _DRAND48_C
	var new_lo: int = low & _DRAND48_M24
	var carry: int = low >> 24

	var new_hi: int = (a_hi * x_lo + a_lo * x_hi + carry) & _DRAND48_M24

	_drand48_state = ((new_hi << 24) | new_lo) & _DRAND48_MASK
	return float(_drand48_state) / _DRAND48_DENOM

func _filler_rand_piece() -> int:
	return int(floor(_filler_drand48() * float(FILLER_NUM_PIECES)))

func _filler_iterate_check(b: Array, i: int, j: int, c: int, temp_array: Array) -> void:
	if i < 0 or i >= BOARD_HEIGHT or j < 0 or j >= BOARD_WIDTH:
		return
	for pt in temp_array:
		if pt[0] == i and pt[1] == j:
			return
	if b[i][j] != c:
		return
	temp_array.append([i, j])
	if j >= 1:
		_filler_iterate_check(b, i, j - 1, c, temp_array)
	if j + 1 < BOARD_WIDTH:
		_filler_iterate_check(b, i, j + 1, c, temp_array)
	if i >= 1:
		_filler_iterate_check(b, i - 1, j, c, temp_array)
	if i + 1 < BOARD_HEIGHT:
		_filler_iterate_check(b, i + 1, j, c, temp_array)

func generate_gamepigeon_board(seed_val: int) -> Array:
	_filler_srand48(seed_val)

	var b: Array = []
	for i in range(BOARD_HEIGHT):
		var row: Array = []
		for j in range(BOARD_WIDTH):
			row.append(_filler_rand_piece())
		b.append(row)

	var pmask: Array = []
	for i in range(BOARD_HEIGHT):
		var mrow: Array = []
		for j in range(BOARD_WIDTH):
			mrow.append(false)
		pmask.append(mrow)
	pmask[0][0] = true
	pmask[1][0] = true
	pmask[0][1] = true
	pmask[BOARD_HEIGHT - 1][BOARD_WIDTH - 1] = true  # (6,7)
	pmask[BOARD_HEIGHT - 1][BOARD_WIDTH - 2] = true  # (6,6)
	pmask[BOARD_HEIGHT - 2][BOARD_WIDTH - 1] = true  # (5,7)

	while true:
		b[0][0] = _filler_rand_piece()
		b[0][1] = _filler_rand_piece()
		b[1][0] = _filler_rand_piece()
		var a: int = b[0][0]
		var bb: int = b[0][1]
		var cc: int = b[1][0]
		if a != bb and a != cc and bb != cc:
			break

	while true:
		b[BOARD_HEIGHT - 1][BOARD_WIDTH - 1] = _filler_rand_piece()
		b[BOARD_HEIGHT - 1][BOARD_WIDTH - 2] = _filler_rand_piece()
		b[BOARD_HEIGHT - 2][BOARD_WIDTH - 1] = _filler_rand_piece()
		var a2: int = b[BOARD_HEIGHT - 1][BOARD_WIDTH - 1]
		var b2: int = b[BOARD_HEIGHT - 1][BOARD_WIDTH - 2]
		var c2: int = b[BOARD_HEIGHT - 2][BOARD_WIDTH - 1]
		if a2 != b2 and a2 != c2 and b2 != c2:
			break

	for _iter in range(FILLER_POLISH_ITERATIONS):
		for i in range(BOARD_HEIGHT):
			for j in range(BOARD_WIDTH):
				var temp_array: Array = []
				_filler_iterate_check(b, i, j, b[i][j], temp_array)
				if temp_array.size() >= 2:
					for pt in temp_array:
						var pr: int = pt[0]
						var pc: int = pt[1]
						if not pmask[pr][pc]:
							b[pr][pc] = _filler_rand_piece()

	return b
	
const _NO_SEED_SENTINEL: int = -9223372036854775808

func generate_filler_colors(seed_val: int = _NO_SEED_SENTINEL):
	if seed_val != _NO_SEED_SENTINEL:
		# Real seed
		color_board = generate_gamepigeon_board(seed_val)
	else:
		# Fallback
		color_board.clear()
		for y in range(BOARD_HEIGHT):
			color_board.append([])
			for x in range(BOARD_WIDTH):
				var forbidden_colors = []
				if x > 0:
					forbidden_colors.append(color_board[y][x - 1])
				if y > 0:
					forbidden_colors.append(color_board[y - 1][x])

				var options = COLORS.filter(func(c): return not forbidden_colors.has(c))
				if options.is_empty():
					generate_filler_colors()
					return

				var chosen = options[randi() % options.size()]
				color_board[y].append(chosen)

func apply_colors_to_cells():
	for y in range(BOARD_HEIGHT):
		for x in range(BOARD_WIDTH):
			var cell = board[y][x]
			if not is_instance_valid(cell):
				continue

			var bg = cell.find_child("Btn_Color", true)
			if bg:
				bg.modulate = COLOR_MAP.get(color_board[y][x], Color.GRAY)

func setup_board_structure():
	if not grid:
		return

	board.clear()
	grid.columns = BOARD_WIDTH

	for y in range(BOARD_HEIGHT):
		board.append([])
		for x in range(BOARD_WIDTH):
			board[y].append(null)

	for y in range(BOARD_HEIGHT - 1, -1, -1):
		for x in range(BOARD_WIDTH):
			var cell_scene = preload("res://fill/Cell.tscn")
			var cell = cell_scene.instantiate()
			if cell:
				grid.add_child(cell)
				board[y][x] = cell
				cell.set_meta("pos", Vector2i(x, y))

				var highlight = cell.find_child("Highlight")
				if highlight and highlight is TextureRect:
					highlight.texture = create_radial_gradient_texture(64)
					highlight.visible = false

func setup_color_selector():
	if not color_selector:
		OpLog.w(LOG_TAG, "setup_color_selector_missing_node")
		return

	for i in COLORS:
		var outer_container := Control.new()
		outer_container.name = "Wrapper_%d" % i
		outer_container.custom_minimum_size = Vector2(64, 64)
		outer_container.size_flags_horizontal = Control.SIZE_FILL
		outer_container.size_flags_vertical = Control.SIZE_FILL

		dbg("setup_color_button color=%d" % i)

		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var btn := Button.new()
		btn.name = "Color_%d" % i
		btn.custom_minimum_size = Vector2(64, 64)
		btn.pivot_offset = btn.custom_minimum_size / 2.0
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.connect("pressed", _on_color_selection_made.bind(i))

		var rect := ColorRect.new()
		rect.color = COLOR_MAP[i]
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		btn.add_child(rect)
		center.add_child(btn)
		outer_container.add_child(center)
		color_selector.add_child(outer_container)

	OpLog.i(LOG_TAG, ["color_selector_setup colors=", COLORS.size()])

func update_color_selector_states():
	dbg("update_selector_states left_color=%d right_color=%d" % [left_color, right_color])

	for i in COLORS:
		var container = color_selector.get_node_or_null("Wrapper_%d" % i)
		if not container:
			OpLog.w(LOG_TAG, ["selector_missing_wrapper color=", i])
			continue

		var btn = container.find_child("Color_%d" % i, true, false)
		if not btn:
			OpLog.w(LOG_TAG, ["selector_missing_button color=", i])
			continue

		if i == left_color or i == right_color:
			btn.disabled = true
			btn.scale = Vector2(0.5, 0.5)
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			btn.disabled = false
			btn.scale = Vector2(1, 1)
			btn.mouse_filter = Control.MOUSE_FILTER_STOP

func update_ui_from_board_state():
	var my_start = left_start
	var opponent_start = right_start
	var my_current_color = get_color_from_position(my_start)
	var opponent_current_color = get_color_from_position(opponent_start)

	my_count = get_connected_cells(my_start, my_current_color).size()
	op_count = get_connected_cells(opponent_start, opponent_current_color).size()
	left_color = my_current_color
	right_color = opponent_current_color

	left_score_label.text = "%02d" % my_count
	right_score_label.text = "%02d" % op_count
	left_bg.color = COLOR_MAP.get(left_color, Color.GRAY)
	right_bg.color = COLOR_MAP.get(right_color, Color.GRAY)

	left_score_label.add_theme_color_override(
		"font_color",
		_get_score_text_color(left_color)
	)

	right_score_label.add_theme_color_override(
		"font_color",
		_get_score_text_color(right_color)
	)

	update_color_selector_states()

	OpLog.d(LOG_TAG, [
		"ui_updated my_count=", my_count,
		" op_count=", op_count,
		" left_color=", left_color,
		" right_color=", right_color,
		" player=", player
	])

func _remove_win_burst_proxy(
	avatar_button: TextureButton,
) -> void:
	if not is_instance_valid(avatar_button):
		return

	var existing_proxy := (
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
	if not is_instance_valid(avatar_button):
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
	if not is_instance_valid(avatar_button):
		return

	_active_win_burst_avatar = avatar_button

	var burst_target := (
		_create_win_burst_target(
			avatar_button,
			_current_avatar_scale,
		)
	)

	if not is_instance_valid(burst_target):
		return

	GameUtils._show_win_burst(
		burst_target,
	)

func _get_score_text_color(bg_color_index: int) -> Color:
	if bg_color_index == 1 or bg_color_index == 2:
		return Color(0.05, 0.05, 0.05)

	return Color.WHITE

func _on_color_selection_made(selected_color_index: int):
	if _settings_open or _rules_open:
		return

	if _loading_replay or spectator_mode or _move_in_progress:
		OpLog.w(LOG_TAG, [
			"color_selection_blocked busy_or_spectator color=", selected_color_index,
			" loading_replay=", _loading_replay,
			" spectator=", spectator_mode,
			" move_in_progress=", _move_in_progress
		])
		return

	if not is_my_turn or game_over:
		OpLog.w(LOG_TAG, [
			"color_selection_blocked turn_or_game_over color=", selected_color_index,
			" is_my_turn=", is_my_turn,
			" game_over=", game_over
		])
		return

	if [left_color, right_color].has(selected_color_index):
		OpLog.w(LOG_TAG, [
			"color_selection_blocked_forbidden color=", selected_color_index,
			" left_color=", left_color,
			" right_color=", right_color
		])
		return

	_move_in_progress = true
	stop_pulsing_all_cells()

	pre_board_data = get_current_board_as_array()

	var connected = get_connected_cells(left_start, left_color)
	var border = get_border_cells(connected)
	var added = []
	var seen = {}

	for pos in border:
		for neighbor in get_neighbors(pos):
			if seen.has(neighbor):
				continue

			seen[neighbor] = true

			if not connected.has(neighbor) and color_board[neighbor.y][neighbor.x] == selected_color_index:
				added += get_connected_cells(neighbor, selected_color_index)

	var all_cells_to_change = connected.duplicate()

	for pos in added:
		if not all_cells_to_change.has(pos):
			all_cells_to_change.append(pos)

	OpLog.event(LOG_TAG, [
		"color_selected color=", selected_color_index,
		" player=", player,
		" connected=", connected.size(),
		" border=", border.size(),
		" added=", added.size(),
		" total_change=", all_cells_to_change.size(),
		" pre_my_count=", my_count,
		" pre_op_count=", op_count
	])

	for pos in all_cells_to_change:
		color_board[pos.y][pos.x] = selected_color_index

	await play_move_animation(left_start)

	update_ui_from_board_state()
	hide_color_selector()

	post_board_data = get_current_board_as_array()

	var moves_str := "move:%d" % selected_color_index
	var pre_str = ",".join(Array(pre_board_data).map(func(i): return str(i)))
	var post_str = ",".join(Array(post_board_data).map(func(i): return str(i)))

	var result = {
		"replay": "board:%s|%s|board:%s" % [pre_str, moves_str, post_str]
	}

	var avatar_out_key := "avatar" + str(player)

	if player != 0 and is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		result[avatar_out_key] = player_avatar_display.get_avatar_data_string()

	game_ended = check_win()

	if game_ended:
		OpLog.event(LOG_TAG, [
			"move_caused_game_end my_uuid=", my_uuid,
			" win_loss_state=", win_loss_state,
			" my_count=", my_count,
			" op_count=", op_count
		])

		if win_loss_state != "":
			result["winner"] = my_uuid + "|" + win_loss_state

	var json := JSON.stringify(result)

	OpLog.event(LOG_TAG, [
		"send_game_out color=", selected_color_index,
		" player=", player,
		" my_count=", my_count,
		" op_count=", op_count,
		" game_ended=", game_ended,
		" has_winner=", result.has("winner"),
		" replay_len=", str(result["replay"]).length(),
		" raw=", json
	])

	send_game_data(json)

	is_my_turn = false
	_move_in_progress = false

	if not game_ended:
		play_sent_animation()
	else:
		stop_waiting_animation()
		hide_color_selector()

func start_pulsing_my_cells():
	var my_start_pos = left_start
	var my_color = get_color_from_position(my_start_pos)
	var my_cells = get_connected_cells(my_start_pos, my_color)

	dbg("pulse_start color=%d cells=%d" % [my_color, my_cells.size()])

	if my_cells.is_empty():
		OpLog.w(LOG_TAG, [
			"pulse_no_cells start=", my_start_pos,
			" color=", my_color
		])
		return

	var success_count = 0

	for cell_pos in my_cells:
		var cell_node = board[cell_pos.y][cell_pos.x]

		if is_instance_valid(cell_node):
			var anim_player = cell_node.get_node_or_null("HighlightAnim")

			if is_instance_valid(anim_player):
				anim_player.play("pulse")
				success_count += 1
			else:
				OpLog.w(LOG_TAG, ["pulse_missing_animation_player cell=", cell_pos])
		else:
			OpLog.w(LOG_TAG, ["pulse_invalid_cell_node cell=", cell_pos])

	dbg("pulse_done success=%d total=%d" % [success_count, my_cells.size()])

func stop_pulsing_all_cells():
	for y in range(BOARD_HEIGHT):
		for x in range(BOARD_WIDTH):
			var cell_node = board[y][x]
			if is_instance_valid(cell_node):
				var anim_player = cell_node.get_node_or_null("HighlightAnim")
				if is_instance_valid(anim_player):
					anim_player.seek(0, true)
					anim_player.stop()
				
				var highlight = cell_node.find_child("Highlight", true)
				if is_instance_valid(highlight):
					highlight.visible = false
		
func play_move_animation(start_pos: Vector2i, forced_cells: Array = [], forced_color_idx: int = -1):
	var visual_start_pos = start_pos
	var new_color_idx: int = forced_color_idx

	if new_color_idx < 0:
		new_color_idx = get_color_from_position(visual_start_pos)

	var new_color = COLOR_MAP.get(new_color_idx, Color.WHITE)

	var cells_to_animate_pos: Array = []

	if not forced_cells.is_empty():
		cells_to_animate_pos = forced_cells.duplicate()
	else:
		cells_to_animate_pos = get_connected_cells_on_display(visual_start_pos, new_color_idx)

	if cells_to_animate_pos.is_empty():
		return

	var animation_tween = create_tween().set_parallel()
	var parent_cell_nodes = []
	var btn_color_nodes = []
	var group_center = Vector2.ZERO
	var original_parent_positions = {}
	var animation_duration = 0.5

	var score_bg: ColorRect = null
	var score_label: Label = null

	if visual_start_pos == left_start:
		score_bg = left_bg
		score_label = left_score_label
	elif visual_start_pos == right_start:
		score_bg = right_bg
		score_label = right_score_label

	if is_instance_valid(score_bg):
		animation_tween.tween_property(score_bg, "color", new_color, animation_duration) \
			.set_trans(Tween.TRANS_LINEAR)

	if is_instance_valid(score_label):
		var target_text_color := _get_score_text_color(new_color_idx)
		animation_tween.tween_method(
			func(c: Color): score_label.add_theme_color_override("font_color", c),
			score_label.get_theme_color("font_color"),
			target_text_color,
			animation_duration
		).set_trans(Tween.TRANS_LINEAR)

	for cell_pos in cells_to_animate_pos:
		var cell_node = board[cell_pos.y][cell_pos.x]
		if is_instance_valid(cell_node):
			var btn_color = cell_node.find_child("Btn_Color", true)
			if is_instance_valid(btn_color):
				parent_cell_nodes.append(cell_node)
				btn_color_nodes.append(btn_color)

				original_parent_positions[cell_node] = cell_node.position
				cell_node.z_index = 10

				animation_tween.tween_property(btn_color, "modulate", new_color, animation_duration) \
					.set_trans(Tween.TRANS_LINEAR)

				group_center += cell_node.position

	if parent_cell_nodes.is_empty():
		return

	group_center /= parent_cell_nodes.size()
	group_center += board[0][0].size / 2.0
	var max_scale = 1.3

	animation_tween.tween_method(
		func(progress): _update_group_transform(progress, btn_color_nodes, parent_cell_nodes, group_center, original_parent_positions, max_scale),
		0.0, 1.0, animation_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	animation_tween.tween_method(
		func(progress): _update_group_transform(progress, btn_color_nodes, parent_cell_nodes, group_center, original_parent_positions, max_scale),
		1.0, 0.0, animation_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await animation_tween.finished

	for i in range(parent_cell_nodes.size()):
		var parent_cell = parent_cell_nodes[i]
		var btn_color = btn_color_nodes[i]

		parent_cell.z_index = 0
		btn_color.scale = Vector2.ONE
		btn_color.position = Vector2.ZERO
		
func _update_group_transform(progress: float, btn_nodes: Array, parent_cells: Array, center: Vector2, original_positions: Dictionary, max_scale: float):
	var current_scale = lerp(1.0, max_scale, progress)
	var gap_compensation = 1.05 
	
	for i in range(btn_nodes.size()):
		var btn_node = btn_nodes[i]
		var parent_cell = parent_cells[i]
		
		var original_pos = original_positions[parent_cell]
		var direction = original_pos - center
		var offset = direction * (current_scale - 1.0)
		btn_node.position = offset
		btn_node.scale = Vector2.ONE * current_scale * gap_compensation

func get_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	for dir in directions:
		var neighbor = pos + dir
		if neighbor.x >= 0 and neighbor.x < BOARD_WIDTH and neighbor.y >= 0 and neighbor.y < BOARD_HEIGHT:
			neighbors.append(neighbor)
	return neighbors

func get_border_cells(connected: Array[Vector2i]) -> Array[Vector2i]:
	var border: Array[Vector2i] = []
	var seen := {}

	for pos in connected:
		var neighbors := get_neighbors(pos)
		for neighbor in neighbors:
			if not connected.has(neighbor) and not seen.has(neighbor):
				border.append(pos)
				seen[neighbor] = true
				break
	return border

func show_color_selector():
	if not is_instance_valid(color_selector):
		return

	update_color_selector_states()

	color_selector.pivot_offset = color_selector.size / 2.0
	color_selector.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if tween and tween.is_running():
		tween.kill()

	tween = create_tween().set_parallel(true)
	tween.tween_property(color_selector, "scale", Vector2.ONE, 0.35)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(color_selector, "modulate:a", 1.0, 0.25)
	tween.tween_callback(func(): color_selector.mouse_filter = Control.MOUSE_FILTER_STOP)

		
func hide_color_selector():
	if not is_instance_valid(color_selector):
		return

	color_selector.pivot_offset = color_selector.size / 2.0
	color_selector.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if tween and tween.is_running():
		tween.kill()

	tween = create_tween().set_parallel(true)
	tween.tween_property(color_selector, "scale", Vector2(0.01, 0.01), 0.25)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(color_selector, "modulate:a", 0.0, 0.2)


func setup_tween():
	if tween and tween.is_valid():
		tween.kill()
	tween = create_tween()

func create_radial_gradient_texture(gradsize: int) -> Texture2D:
	var img = Image.create(gradsize, gradsize, false, Image.FORMAT_RGBA8)
	@warning_ignore("integer_division")
	var center = Vector2(gradsize / 2, gradsize / 2)

	for y in range(gradsize):
		for x in range(gradsize):
			@warning_ignore("integer_division")
			var dist = center.distance_to(Vector2(x, y)) / (gradsize / 2)
			var alpha = clamp(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha))

	var tex = ImageTexture.create_from_image(img)
	return tex
	
func _apply_visual_board_transform() -> void:
	if not is_instance_valid(grid):
		return

	await get_tree().process_frame
	grid.pivot_offset = grid.size / 2.0
	grid.rotation_degrees = 180.0 if player == 2 else 0.0

func init_color_selector_collapsed():
	if not is_instance_valid(color_selector):
		return
	color_selector.scale = Vector2(0.01, 0.01)
	color_selector.modulate.a = 0.0
	color_selector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().process_frame
	color_selector.pivot_offset = color_selector.size / 2.0


func parse_replay_string(replay_str: String, play_animation: bool):
	OpLog.i(LOG_TAG, [
		"parse_replay_start len=", replay_str.length(),
		" play_animation=", play_animation
	])

	var parts = replay_str.split("|")

	if parts.size() != 3:
		OpLog.e(LOG_TAG, [
			"invalid_replay_format parts=", parts.size(),
			" raw=", replay_str
		])
		return

	var pre_part: String = parts[0]
	var move_part: String = parts[1]
	var post_part: String = parts[2]

	if not pre_part.begins_with("board:") or not post_part.begins_with("board:"):
		OpLog.e(LOG_TAG, [
			"invalid_replay_board_parts pre=", pre_part,
			" post=", post_part
		])
		return

	var pre_vals = pre_part.substr(6).split(",")
	var post_vals = post_part.substr(6).split(",")

	OpLog.i(LOG_TAG, [
		"parse_replay_parts pre_vals=", pre_vals.size(),
		" post_vals=", post_vals.size(),
		" move=", move_part
	])

	var post_board_snapshot: Array = []

	for y in range(BOARD_HEIGHT):
		post_board_snapshot.append([])

		for x in range(BOARD_WIDTH):
			var flat_i := y * BOARD_WIDTH + x
			post_board_snapshot[y].append(int(post_vals[flat_i]) if flat_i < post_vals.size() and post_vals[flat_i] != "" else 0)

	var visible_vals = pre_vals if play_animation else post_vals

	color_board.clear()

	for y in range(BOARD_HEIGHT):
		color_board.append([])

		for x in range(BOARD_WIDTH):
			var flat_i := y * BOARD_WIDTH + x
			color_board[y].append(int(visible_vals[flat_i]) if flat_i < visible_vals.size() and visible_vals[flat_i] != "" else 0)

	apply_colors_to_cells()
	await _apply_visual_board_transform()
	update_ui_from_board_state()

	if play_animation:
		var final_color_idx: int = int(post_board_snapshot[right_start.y][right_start.x])
		var final_claimed_cells: Array[Vector2i] = get_connected_cells_in_board(post_board_snapshot, right_start, final_color_idx)

		OpLog.event(LOG_TAG, [
			"replay_animation_start final_color=", final_color_idx,
			" final_claimed_cells=", final_claimed_cells.size(),
			" right_start=", right_start
		])

		await play_move_animation(right_start, final_claimed_cells, final_color_idx)

		color_board.clear()

		for y in range(BOARD_HEIGHT):
			color_board.append([])

			for x in range(BOARD_WIDTH):
				color_board[y].append(int(post_board_snapshot[y][x]))

		apply_colors_to_cells()
		await _apply_visual_board_transform()
		update_ui_from_board_state()

	OpLog.i(LOG_TAG, [
		"parse_replay_done play_animation=", play_animation,
		" my_count=", my_count,
		" op_count=", op_count,
		" left_color=", left_color,
		" right_color=", right_color
	])

func get_color_from_position(pos: Vector2i) -> int:
	if pos.y >= 0 and pos.y < BOARD_HEIGHT and pos.x >= 0 and pos.x < BOARD_WIDTH:
		return color_board[pos.y][pos.x]
	return -1
	
func get_connected_cells_on_display(pos: Vector2i, target_color: int, visited = null) -> Array[Vector2i]:
	
	var display_board = color_board
	if visited == null:
		visited = {}

	if visited.has(pos):
		return []

	if pos.x < 0 or pos.x >= BOARD_WIDTH or pos.y < 0 or pos.y >= BOARD_HEIGHT:
		return []

	if display_board[pos.y][pos.x] != target_color:
		return []

	visited[pos] = true
	var result: Array[Vector2i] = [pos]

	for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		result += get_connected_cells_on_display(pos + dir, target_color, visited)
	return result
	
func get_connected_cells_in_board(source_board: Array, pos: Vector2i, target_color: int, visited = null) -> Array[Vector2i]:
	if visited == null:
		visited = {}

	if visited.has(pos):
		return []

	if pos.x < 0 or pos.x >= BOARD_WIDTH or pos.y < 0 or pos.y >= BOARD_HEIGHT:
		return []

	if pos.y >= source_board.size() or pos.x >= source_board[pos.y].size():
		return []

	if int(source_board[pos.y][pos.x]) != target_color:
		return []

	visited[pos] = true
	var result: Array[Vector2i] = [pos]

	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		result += get_connected_cells_in_board(source_board, pos + dir, target_color, visited)

	return result

func get_connected_cells(pos: Vector2i, target_color: int, visited = null) -> Array[Vector2i]:
	if visited == null:
		visited = {}

	if visited.has(pos):
		return []

	if pos.x < 0 or pos.x >= BOARD_WIDTH or pos.y < 0 or pos.y >= BOARD_HEIGHT:
		return []

	if color_board[pos.y][pos.x] != target_color:
		return []

	visited[pos] = true
	var result: Array[Vector2i] = [pos]

	for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		result += get_connected_cells(pos + dir, target_color, visited)
	return result

func get_current_board_as_array() -> Array:
	var flat_board := []

	for y in range(BOARD_HEIGHT):
		for x in range(BOARD_WIDTH):
			flat_board.append(color_board[y][x])

	dbg("current_board_flat len=%d data=%s" % [flat_board.size(), str(flat_board)])
	return flat_board

func _apply_winner_payload(winner_payload: String, player1_id: String = "", player2_id: String = "") -> void:
	OpLog.event(LOG_TAG, [
		"apply_winner_payload payload=", winner_payload,
		" player1=", player1_id,
		" player2=", player2_id,
		" my_uuid=", my_uuid,
		" spectator=", spectator_mode
	])

	var parts := winner_payload.split("|", false)
	if parts.size() < 2:
		OpLog.w(LOG_TAG, ["bad_winner_payload payload=", winner_payload])
		return

	var sender_uuid := String(parts[0])
	var sender_state := String(parts[1])

	if sender_state == "0":
		_show_result_from_state("0")
		return

	var local_state := sender_state

	if spectator_mode:
		var sender_player := 0

		if sender_uuid == player1_id:
			sender_player = 1
		elif sender_uuid == player2_id:
			sender_player = 2

		if sender_player == 2:
			local_state = "-1" if sender_state == "1" else "1"
	else:
		if sender_uuid != my_uuid:
			local_state = "-1" if sender_state == "1" else "1"

	OpLog.i(LOG_TAG, [
		"winner_resolved sender_uuid=", sender_uuid,
		" sender_state=", sender_state,
		" local_state=", local_state
	])

	_show_result_from_state(local_state)

func _show_result_from_state(state: String) -> void:
	game_over = true
	game_ended = true
	win_loss_state = state
	is_my_turn = false
	_move_in_progress = false

	stop_waiting_animation()
	hide_color_selector()
	stop_pulsing_all_cells()
	_clear_all_win_burst_proxies()
	_active_win_burst_avatar = null

	if state == "0":
		win_loss_label.text = "DRAW!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
	elif state == "1":
		if spectator_mode:
			win_loss_label.text = "Player 1 Wins!"
		else:
			win_loss_label.text = "YOU WIN!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

		if is_instance_valid(player_avatar_display):
			_show_win_burst_for_avatar(
				player_avatar_display,
			)
	else:
		if spectator_mode:
			win_loss_label.text = "Player 2 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		else:
			win_loss_label.text = "YOU LOSE"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

		if is_instance_valid(opp_avatar_display):
			_show_win_burst_for_avatar(
				opp_avatar_display,
			)

	OpLog.event(LOG_TAG, [
		"show_result state=", state,
		" text=", win_loss_label.text,
		" spectator=", spectator_mode,
		" player=", player,
		" my_count=", my_count,
		" op_count=", op_count,
		" left_color=", left_color,
		" right_color=", right_color
	])

	win_loss_label.visible = true
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2

	var tween_in = create_tween()
	tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func check_win() -> bool:
	var unique_colors = get_unique_colors_on_board()

	OpLog.d(LOG_TAG, [
		"check_win unique_colors=", unique_colors,
		" unique_count=", unique_colors.size(),
		" my_count=", my_count,
		" op_count=", op_count,
		" total=", my_count + op_count,
		" board_total=", BOARD_HEIGHT * BOARD_WIDTH
	])

	if unique_colors.size() > 2 or my_count + op_count < (BOARD_HEIGHT * BOARD_WIDTH):
		return false

	OpLog.event(LOG_TAG, [
		"win_condition_met unique_colors=", unique_colors,
		" my_count=", my_count,
		" op_count=", op_count
	])

	if my_count > op_count:
		OpLog.event(LOG_TAG, "final_tally local_win")
		_show_result_from_state("1")
	elif op_count > my_count:
		OpLog.event(LOG_TAG, "final_tally local_loss")
		_show_result_from_state("-1")
	else:
		OpLog.event(LOG_TAG, "final_tally_draw")
		_show_result_from_state("0")

	return true

func get_unique_colors_on_board() -> Array:
	var unique_colors = []
	for y in range(BOARD_HEIGHT):
		for x in range(BOARD_WIDTH):
			var color = color_board[y][x]
			if not unique_colors.has(color):
				unique_colors.append(color)
	return unique_colors

func play_sent_animation():
	if not is_instance_valid(sent_label):
		OpLog.w(LOG_TAG, "sent_animation_missing_label")
		return

	if game_over:
		OpLog.d(LOG_TAG, "sent_animation_skipped game_over=true")
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

		if not game_over and not spectator_mode and not is_my_turn:
			start_waiting_animation()
		else:
			stop_waiting_animation()
	)

func _get_rules_text() -> String:
	return """
[font_size={18px}]
1. Each player is assigned a corner tile at the start of the game.
2. Players take turns filling their tiles with one of 6 colors in an attempt to capture adjacent tiles of the same color.
3. You are not allowed to change the color of your tiles into the color of your opponents tiles.
4. The game ends when there are no more tiles to occupy
[/font_size]
"""
