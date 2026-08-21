extends BaseGame

@onready var paper: PanelContainer = %Paper
@onready var grid: Control = %DotsGrid
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var send_button: Button = %SendButton
@onready var sent_label: Label = %SentLabel
@onready var background: ColorRect = %Background
@onready var win_loss_label: Label = %WinLossLabel
@onready var player_score_label: Label = %PlayerScore
@onready var opp_score_label: Label = %OppScore
@onready var player_color_icon: TextureRect = %PlayerColor
@onready var opp_color_icon: TextureRect = %OppColor
@onready var player_marker: TextureRect = %PlayerMarker
@onready var opp_marker: TextureRect = %OppMarker
@onready var you_label: Label = %YouLabel
@onready var spec_label: Label = %SpecLabel
@onready var dots_main_vbox: VBoxContainer = %DotsMainVBox
@onready var dots_top_hud: HBoxContainer = %TopInfoHBoxContainer
@onready var dots_board_center: CenterContainer = %Center
@onready var dots_bottom_controls: HBoxContainer = %BottomItemHBoxContainer
@onready var dots_settings_button: Button = %SettingsButton
@onready var dots_rules_button: Button = %RulesButton

const MUSIC_STREAM := preload("res://global/audio/dots.ogg")

var sent_tween: Tween
var _turn_steps: Array = []
var player: int = 1
var turn_owner: int = 1
var is_your_turn: bool = false
var is_my_turn: bool = false : set = _set_is_my_turn
var pre_board_str: String = ""
var post_board_str_from_opponent: String = ""
var opponent_post_lines: Array = []
var opponent_post_squares: Array = []
var game_ended: bool = false
var game_over: bool = false
var win_loss_state: String = ""
var my_score: int = 0
var opp_score: int = 0

var prev_lines_cache: Array = []
var last_replay_sent: String = ""
var _loading_replay: bool = false

var recovery_turn_num: String = ""
var recovery_snapshot_pending := false
var recovery_snapshot_progress := ""
var recovery_loaded := false
var recovery_restore_in_progress := false
var recovery_committing_send := false

var _send_button_home_global := Vector2.ZERO
var _send_button_home_ready := false
var _send_button_target_visible := false
var _send_button_init_queued := false

@export var board_size: int = 4 : set = set_board_size # 4, 5, or 6
var blue_marker_tex: Texture2D = preload("res://dots/blue_marker.png")
var red_marker_tex: Texture2D = preload("res://dots/red_marker.png")

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
const LOG_TAG := "DotsBoxes"
var DEBUG_DOTS_BOXES := false

const DOTS_LANDSCAPE_BOARD_HEIGHT_RATIO := 0.80
const DOTS_PORTRAIT_BOARD_RATIO := 0.70
const DOTS_REFERENCE_BOARD_SIZE := 500.0

const DOTS_BASE_AVATAR_SIZE := Vector2(
	96.0,
	90.0,
)

const DOTS_BASE_YOU_FONT_SIZE := 18.0
const DOTS_BASE_SCORE_FONT_SIZE := 20.0

const DOTS_BASE_SCORE_ICON_SIZE := Vector2(
	28.0,
	28.0,
)

const DOTS_BASE_MARKER_SIZE := Vector2(
	80.0,
	80.0,
)

const DOTS_BASE_MENU_BUTTON_SIZE := Vector2(
	64.0,
	64.0,
)

const DOTS_BASE_MENU_BUTTON_FONT_SIZE := 32.0

const DOTS_BASE_SEND_BUTTON_SIZE := Vector2(
	70.0,
	50.0,
)

const DOTS_BASE_SEND_BUTTON_FONT_SIZE := 28.0

const DOTS_LANDSCAPE_AVATAR_MIN_SCALE := 2.05
const DOTS_LANDSCAPE_AVATAR_MAX_SCALE := 2.35

const DOTS_BASE_SIDE_MARGIN := 40.0
const DOTS_BASE_TOP_MARGIN := 20.0
const DOTS_LANDSCAPE_BOTTOM_PADDING := 24.0
const DOTS_BOARD_ACTION_GAP := 24.0

const DOTS_PORTRAIT_BOTTOM_HEIGHT := 120.0

const DOTS_BASE_SPECTATOR_FONT_SIZE := 50.0
const DOTS_BASE_SPECTATOR_HALF_WIDTH := 324.0
const DOTS_BASE_SPECTATOR_HEIGHT := 220.0
const DOTS_PORTRAIT_SPECTATOR_TOP_OFFSET := 90.0

const DOTS_LANDSCAPE_OVERLAY_MIN_SCALE := 1.35
const DOTS_LANDSCAPE_OVERLAY_MAX_SCALE := 1.65

const DOTS_BASE_DOT_RADIUS := 9.0
const DOTS_BASE_LINE_WIDTH := 8.0
const DOTS_BASE_HOVER_WIDTH := 8.0
const DOTS_BASE_ANIMATION_LINE_WIDTH := 12.0

const DOTS_WIN_BURST_WRAPPER_NAME := (
	"DotsResponsiveWinBurstWrapper"
)

var _dots_layout_pending := false
var _dots_last_viewport_size := Vector2.ZERO
var _dots_layout_generation := 0

var _dots_current_avatar_scale := 1.0
var _dots_current_board_scale := 1.0

var _dots_portrait_vbox_separation := 0

var _dots_active_win_burst_avatar: TextureButton = null

func dbg(msg: String) -> void:
	if DEBUG_DOTS_BOXES:
		OpLog.d(LOG_TAG, msg)
	
func _get_dev_data() -> String:
	return '{"isYourTurn": true,"size": "4","player": "2","replay": "board:1,0,2,0,3#2,0,1,0,2#1,0,0,0,1#2,2,1,2,2#1,3,0,3,1#2,2,0,2,1#1,1,1,1,2#2,1,0,1,1#1,3,2,3,3#2,1,2,1,3#1,3,1,3,2#2,2,2,2,3#1,1,0,2,0|line:2,1,1,2,1|square:2,1,0|line:2,1,2,2,2|square:2,1,1|line:2,1,3,2,3|square:2,1,2|line:2,2,0,3,0|board:1,0,2,0,3#2,0,1,0,2#1,0,0,0,1#2,2,1,2,2#1,3,0,3,1#2,2,0,2,1#1,1,1,1,2#2,1,0,1,1#1,3,2,3,3#2,1,2,1,3#1,3,1,3,2#2,2,2,2,3#1,1,0,2,0#2,1,1,2,1#2,1,2,2,2#2,1,3,2,3#2,2,0,3,0#2,1,0#2,1,1#2,1,2","sender":"7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX","version": "5","tver": "5","ios": "18.5","id": "dev","player2": "7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX"}'
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Dots & Boxes"

func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	var sb := StyleBoxFlat.new()
	var is_dark = bool(SettingsManager.get_setting("global", "dark_mode", false))

	OpLog.i(LOG_TAG, ["game_ready dark_mode=", is_dark, " board_size=", board_size])

	_apply_bg_for_dark(is_dark)

	sb.bg_color = Color(1, 1, 1, 1)
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 16

	if is_instance_valid(paper):
		paper.add_theme_stylebox_override("panel", sb)

	set_board_size(board_size)

	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)

	_on_resized()

	if is_instance_valid(grid):
		if not grid.is_connected("turn_changed", Callable(self, "_on_turn")):
			grid.connect("turn_changed", Callable(self, "_on_turn"))

		if not grid.is_connected("score_changed", Callable(self, "_on_score")):
			grid.connect("score_changed", Callable(self, "_on_score"))

		if not grid.is_connected("game_over", Callable(self, "_on_game_over")):
			grid.connect("game_over", Callable(self, "_on_game_over"))

		if grid.has_signal("line_committed_bl"):
			if not grid.is_connected("line_committed_bl", Callable(self, "_on_line_committed_bl")):
				grid.connect("line_committed_bl", Callable(self, "_on_line_committed_bl"))

		if grid.has_signal("square_completed_bl"):
			if not grid.is_connected("square_completed_bl", Callable(self, "_on_square_completed_bl")):
				grid.connect("square_completed_bl", Callable(self, "_on_square_completed_bl"))

		if grid.has_signal("temp_line_changed"):
			if not grid.is_connected("temp_line_changed", Callable(self, "_on_temp_line_changed")):
				grid.connect("temp_line_changed", Callable(self, "_on_temp_line_changed"))
				OpLog.d(LOG_TAG, "connected_temp_line_changed")
		else:
			OpLog.w(LOG_TAG, "grid_temp_line_changed_signal_missing")
			push_warning("[Grid] temp_line_changed signal missing")
	else:
		OpLog.e(LOG_TAG, "missing_dots_grid_node")
		push_warning("No %DotsGrid in scene")

	if is_instance_valid(send_button):
		send_button.visible = true
		send_button.disabled = true
		send_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		send_button.modulate.a = 0.0
		send_button.scale = Vector2.ONE

		if not send_button.pressed.is_connected(_on_send_pressed):
			send_button.pressed.connect(_on_send_pressed)

		_queue_send_button_initialization()

		OpLog.d(LOG_TAG, [
			"send_button_ready visible=",
			send_button.visible
		])
	else:
		OpLog.w(LOG_TAG, "missing_send_button")
		push_warning("No %SendButton in scene")

	_apply_player_color_icons()
	_initialize_dots_responsive_layout()

func _set_game_data(raw_text: String) -> void:
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", raw_text])

	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, [
			"set_game_data_parse_failed type=", typeof(parsed),
			" raw=", raw_text
		])
		return

	var res: Dictionary = parsed
	
	recovery_turn_num = String(res.get("num", ""))
	recovery_snapshot_pending = String(res.get("_recoveryPending", "false")).to_lower() == "true"
	recovery_snapshot_progress = String(res.get("_recoveryProgress", ""))
	recovery_loaded = false
	recovery_restore_in_progress = false

	OpLog.i(LOG_TAG, [
		"recovery_snapshot pending=", recovery_snapshot_pending,
		" progressLen=", recovery_snapshot_progress.length(),
		" turn=", recovery_turn_num
	])

	game_over = false
	game_ended = false
	win_loss_state = ""
	spectator_mode = false
	_turn_steps.clear()
	stop_waiting_animation()
	_update_send_button_visibility(false)

	if is_instance_valid(win_loss_label):
		win_loss_label.visible = false
		win_loss_label.text = ""
		win_loss_label.scale = Vector2.ONE
	
	_dots_active_win_burst_avatar = null
	_clear_dots_win_burst_proxies()

	var p1_id: String = res.get("player1", "")
	var p2_id: String = res.get("player2", "")
	var opponent_avatar_key := ""

	turn_owner = clamp(int(res.get("player", 1)), 1, 2)
	is_your_turn = bool(res.get("isYourTurn", false))

	var replay_str: String = String(res.get("replay", ""))
	var winner_payload: String = String(res.get("winner", ""))

	OpLog.i(LOG_TAG, [
		"set_game_data_fields my_uuid=", my_uuid,
		" player1=", p1_id,
		" player2=", p2_id,
		" turn_owner=", turn_owner,
		" isYourTurn=", is_your_turn,
		" size=", res.get("size", board_size),
		" replay_len=", replay_str.length(),
		" has_winner=", winner_payload != ""
	])

	if my_uuid != "" and p1_id != "" and p2_id != "":
		player = (1 if my_uuid == p1_id else (2 if my_uuid == p2_id else 0))

		if player == 0:
			spectator_mode = true

			if is_instance_valid(spec_label):
				spec_label.show()

			player = 1
		else:
			if is_instance_valid(spec_label):
				spec_label.hide()
	else:
		player = (3 - turn_owner) if is_your_turn else turn_owner

		if is_instance_valid(spec_label):
			spec_label.hide()

	if player == 1:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"

	if is_instance_valid(you_label):
		you_label.text = "You"

		you_label.modulate.a = (
			0.0
			if spectator_mode
			else 1.0
		)

	if is_instance_valid(spec_label):
		spec_label.visible = spectator_mode

	OpLog.i(LOG_TAG, [
		"resolved_player player=", player,
		" spectator=", spectator_mode,
		" is_your_turn=", is_your_turn,
		" opponent_avatar_key=", opponent_avatar_key
	])

	if opponent_avatar_key != "" and res.has(opponent_avatar_key):
		var avatar_string = res[opponent_avatar_key]
		var opponent_data = GameUtils._parse_avatar_string(avatar_string)

		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	if spectator_mode and res.has("avatar1"):
		var p1_data = GameUtils._parse_avatar_string(res["avatar1"])

		if is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", p1_data)

	_apply_player_color_icons()
	_schedule_dots_responsive_layout(true)

	board_size = clamp(int(res.get("size", board_size)), 4, 6)

	if is_instance_valid(grid) and grid.has_method("set_grid"):
		grid.call("set_grid", board_size)
	else:
		OpLog.w(LOG_TAG, "grid_missing_set_grid")

	await _load_pre_state_and_replay(replay_str)

	if winner_payload != "":
		OpLog.event(LOG_TAG, ["winner_payload_received payload=", winner_payload])
		_apply_winner_payload(winner_payload, p1_id, p2_id)
		return

	is_my_turn = is_your_turn

	if await _restore_dots_recovery():
		return

	game_ended = await check_win()

	if game_ended:
		stop_waiting_animation()
		_update_send_button_visibility(false)
		game_over = true
	elif not is_my_turn and not spectator_mode:
		start_waiting_animation()
	else:
		stop_waiting_animation()

	OpLog.i(LOG_TAG, [
		"set_game_data_done player=", player,
		" is_my_turn=", is_my_turn,
		" spectator=", spectator_mode,
		" game_over=", game_over,
		" game_ended=", game_ended,
		" my_score=", my_score,
		" opp_score=", opp_score,
		" turn_steps=", _turn_steps.size()
	])

func _save_dots_progress(phase: String = "active") -> void:
	if recovery_restore_in_progress or spectator_mode or not is_my_turn or appPlugin == null:
		return

	var serialized_steps: Array[String] = []

	for step in _turn_steps:
		if not step.has("line"):
			continue

		var line: Array = step["line"]
		var squares: Array = step.get("squares", [])
		var square_parts: Array[String] = []

		for sq in squares:
			square_parts.append("%d,%d,%d" % [int(sq[0]), int(sq[1]), int(sq[2])])

		serialized_steps.append("%d,%d,%d,%d,%d;%s" % [
			int(line[0]), int(line[1]), int(line[2]), int(line[3]), int(line[4]), ":".join(square_parts)
		])

	var progress := {
		"phase": phase,
		"turn": recovery_turn_num,
		"steps": "|".join(serialized_steps)
	}

	appPlugin.saveTurnProgress(JSON.stringify(progress))

	OpLog.i(LOG_TAG, [
		"recovery_saved phase=", phase,
		" steps=", _turn_steps.size(),
		" turn=", recovery_turn_num
	])

func _remove_dots_win_burst_proxy(
	avatar_button: TextureButton,
) -> void:
	if not is_instance_valid(avatar_button):
		return

	var existing := avatar_button.get_node_or_null(
		DOTS_WIN_BURST_WRAPPER_NAME,
	)

	if existing == null:
		return

	avatar_button.remove_child(existing)
	existing.queue_free()


func _clear_dots_win_burst_proxies() -> void:
	_remove_dots_win_burst_proxy(
		player_avatar_display,
	)

	_remove_dots_win_burst_proxy(
		opp_avatar_display,
	)


func _create_dots_win_burst_target(
	avatar_button: TextureButton,
) -> TextureButton:
	if not is_instance_valid(avatar_button):
		return null

	_remove_dots_win_burst_proxy(
		avatar_button,
	)

	var wrapper := Control.new()

	wrapper.name = DOTS_WIN_BURST_WRAPPER_NAME

	wrapper.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	wrapper.show_behind_parent = true
	wrapper.clip_contents = false
	wrapper.size = DOTS_BASE_AVATAR_SIZE

	wrapper.pivot_offset = (
		DOTS_BASE_AVATAR_SIZE *
		0.5
	)

	wrapper.position = (
		avatar_button.size *
			0.5 -
		DOTS_BASE_AVATAR_SIZE *
			0.5
	)

	wrapper.scale = Vector2.ONE * (
		_dots_current_avatar_scale
	)

	avatar_button.add_child(wrapper)

	var target := TextureButton.new()

	target.name = "DotsBurstTarget"
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.ignore_texture_size = true
	target.clip_contents = false
	target.size = DOTS_BASE_AVATAR_SIZE

	target.pivot_offset = (
		DOTS_BASE_AVATAR_SIZE *
		0.5
	)

	wrapper.add_child(target)

	return target


func _show_dots_win_burst(
	avatar_button: TextureButton,
) -> void:
	if not is_instance_valid(avatar_button):
		return

	_dots_active_win_burst_avatar = avatar_button

	var target := _create_dots_win_burst_target(
		avatar_button,
	)

	if not is_instance_valid(target):
		return

	GameUtils._show_win_burst(target)

func _load_pre_state_and_replay(replay_str: String) -> void:
	_loading_replay = true

	var parsed := _parse_replay_dnb(replay_str)
	var pre_lines: Array = parsed.get("pre_lines", [])
	var pre_squares: Array = parsed.get("pre_squares", [])
	var moves: Array = parsed.get("moves", [])

	pre_board_str = parsed.get("pre_board_str", "")
	post_board_str_from_opponent = parsed.get("post_board_str", "")
	opponent_post_lines = parsed.get("post_lines", [])
	opponent_post_squares = parsed.get("post_squares", [])

	OpLog.i(LOG_TAG, [
		"load_replay pre_lines=", pre_lines.size(),
		" pre_squares=", pre_squares.size(),
		" moves=", moves.size(),
		" post_lines=", opponent_post_lines.size(),
		" post_squares=", opponent_post_squares.size(),
		" replay_len=", replay_str.length()
	])

	if is_instance_valid(grid) and grid.has_method("load_lines_and_squares_state"):
		grid.call("load_lines_and_squares_state", pre_lines, pre_squares)
	else:
		OpLog.w(LOG_TAG, "grid_missing_load_lines_and_squares_state")

	if not moves.is_empty() and is_instance_valid(grid) and grid.has_method("replay_line_move"):
		for move in moves:
			OpLog.event(LOG_TAG, ["replay_line_move move=", move])
			await grid.call("replay_line_move", move)
			await get_tree().create_timer(0.05).timeout

	prev_lines_cache = _get_committed_lines()

	if is_instance_valid(player_score_label) and is_instance_valid(opp_score_label):
		if player_score_label.text == "" and opp_score_label.text == "":
			player_score_label.text = "0"
			opp_score_label.text = "0"

	_loading_replay = false

	OpLog.i(LOG_TAG, [
		"load_replay_done committed_lines=", prev_lines_cache.size(),
		" my_score=", my_score,
		" opp_score=", opp_score
	])

func _set_is_my_turn(v: bool) -> void:
	is_my_turn = v
	_apply_turn_state()
	
func _apply_turn_state() -> void:
	if is_instance_valid(grid):
		var grid_player := player if is_my_turn else (3 - player)
		grid.set("player", grid_player)
		grid.call_deferred("set_input_enabled", is_my_turn and not spectator_mode and not game_over and not _loading_replay)

	if game_over or spectator_mode:
		stop_waiting_animation()
	elif is_my_turn:
		stop_waiting_animation()
		
func _parse_replay_dnb(raw: String) -> Dictionary:
	var out := {
		"pre_board_str": "",
		"post_board_str": "",
		"pre_lines": [],
		"pre_squares": [],
		"moves": [],
		"post_lines": [],
		"post_squares": []
	}

	if raw.strip_edges() == "":
		OpLog.d(LOG_TAG, "parse_replay empty")
		return out

	var parts := raw.split("|")
	var is_first_board := true

	for p in parts:
		if p.begins_with("board:"):
			var b := p.substr(6)
			var br := _parse_board_string(b)

			if is_first_board:
				out["pre_board_str"] = b
				out["pre_lines"] = br["lines"]
				out["pre_squares"] = br["squares"]
				is_first_board = false
			else:
				out["post_board_str"] = b
				out["post_lines"] = br["lines"]
				out["post_squares"] = br["squares"]
		elif p.begins_with("line:"):
			var mv := _csv_to_ints(p.substr(5))
			if mv.size() >= 5:
				out["moves"].append([mv[0], mv[1], mv[2], mv[3], mv[4]])
			else:
				OpLog.w(LOG_TAG, ["parse_replay_bad_line chunk=", p])
		elif p.begins_with("square:"):
			# Squares are included in replay for payload parity but are applied from board snapshots.
			dbg("parse_replay_square_chunk %s" % p)
		elif p.strip_edges() != "":
			OpLog.w(LOG_TAG, ["parse_replay_unknown_chunk chunk=", p])

	OpLog.i(LOG_TAG, [
		"parse_replay_done parts=", parts.size(),
		" pre_lines=", out["pre_lines"].size(),
		" pre_squares=", out["pre_squares"].size(),
		" moves=", out["moves"].size(),
		" post_lines=", out["post_lines"].size(),
		" post_squares=", out["post_squares"].size()
	])

	return out

func _parse_board_string(b: String) -> Dictionary:
	var lines: Array = []; var squares: Array = []
	for chunk in b.split("#"):
		var s := chunk.strip_edges()
		if s == "": continue
		var nums := _csv_to_ints(s)
		if nums.size() == 5:
			lines.append([nums[0], nums[1], nums[2], nums[3], nums[4]])
		elif nums.size() == 3:
			squares.append([nums[0], nums[1], nums[2]])
	return { "lines": lines, "squares": squares }

func _csv_to_ints(s: String) -> Array:
	var out: Array = []
	for t in s.split(","):
		var tt := t.strip_edges()
		if tt != "":
			out.append(int(tt))
	return out
	
func _get_grid_colors() -> Array[Color]:
	var cols: Array[Color] = []
	if is_instance_valid(grid) and grid.has_method("get"):
		var got: Variant = grid.get("p_colors")
		if typeof(got) == TYPE_ARRAY:
			var tmp: Array[Color] = []
			for v in (got as Array):
				if v is Color:
					tmp.append(v)
			cols = tmp
	if cols.size() < 2:
		cols = [Color(0.20, 0.55, 0.81), Color(0.92, 0.13, 0.43)]
	return cols

func _apply_player_color_icons() -> void:
	var cols := _get_grid_colors()
	var my_col: Color = cols[player - 1]
	var opp_col: Color = cols[2 - player]

	if is_instance_valid(player_color_icon):
		player_color_icon.modulate = my_col
	if is_instance_valid(opp_color_icon):
		opp_color_icon.modulate = opp_col

	if is_instance_valid(player_score_label):
		player_score_label.add_theme_color_override("font_color", my_col)
	if is_instance_valid(opp_score_label):
		opp_score_label.add_theme_color_override("font_color", opp_col)

	if is_instance_valid(player_marker):
		player_marker.texture = (blue_marker_tex if player == 1 else red_marker_tex)
	if is_instance_valid(opp_marker):
		opp_marker.texture = (red_marker_tex if player == 1 else blue_marker_tex)

func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		OpLog.d(LOG_TAG, ["apply_background is_dark=", is_dark])
		background.color = Color("#261a19") if is_dark else Color("#947972")

func _configure_dots_avatar(
	avatar_button: TextureButton,
) -> void:
	if not is_instance_valid(avatar_button):
		return

	avatar_button.clip_contents = false

	var internal_viewport := (
		avatar_button.get_node_or_null(
			"SubViewportContainer/SubViewport",
		) as SubViewport
	)

	if internal_viewport != null:
		internal_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS
		)

	var internal_preview := (
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

func _initialize_dots_responsive_layout() -> void:
	_configure_dots_avatar(
		player_avatar_display,
	)

	_configure_dots_avatar(
		opp_avatar_display,
	)

	_dots_portrait_vbox_separation = (
		dots_main_vbox.get_theme_constant(
			"separation",
		)
	)

	if spec_label.get_parent() != self:
		spec_label.reparent(
			self,
			false,
		)

	var viewport := get_viewport()

	if viewport != null:
		if not viewport.size_changed.is_connected(
			_on_dots_viewport_size_changed,
		):
			viewport.size_changed.connect(
				_on_dots_viewport_size_changed,
			)

	_schedule_dots_responsive_layout(true)


func _on_dots_viewport_size_changed() -> void:
	_schedule_dots_responsive_layout(true)


func _schedule_dots_responsive_layout(
	force: bool = false,
) -> void:
	if force:
		_dots_last_viewport_size = Vector2.ZERO

	if _dots_layout_pending:
		return

	_dots_layout_pending = true

	call_deferred(
		"_apply_dots_responsive_layout",
	)

func _reset_dots_control_for_container(
	control: Control,
) -> void:
	if not is_instance_valid(control):
		return

	control.set_anchors_preset(
		Control.PRESET_TOP_LEFT,
		false,
	)

	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
	control.scale = Vector2.ONE


func _set_dots_landscape_mode(
	enabled: bool,
) -> void:
	if enabled:
		if dots_top_hud.get_parent() != self:
			dots_top_hud.reparent(
				self,
				false,
			)

		dots_main_vbox.move_child(
			dots_board_center,
			0,
		)

		dots_main_vbox.move_child(
			dots_bottom_controls,
			1,
		)

		dots_main_vbox.alignment = (
			BoxContainer.ALIGNMENT_CENTER
		)

		dots_board_center.size_flags_horizontal = (
			Control.SIZE_SHRINK_CENTER
		)

		dots_board_center.size_flags_vertical = (
			Control.SIZE_SHRINK_CENTER
		)

		dots_bottom_controls.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL
		)

		dots_bottom_controls.size_flags_vertical = (
			Control.SIZE_SHRINK_CENTER
		)

		dots_top_hud.z_index = 20
		spec_label.z_index = 30

		dots_main_vbox.queue_sort()
		return

	if dots_top_hud.get_parent() != dots_main_vbox:
		dots_top_hud.reparent(
			dots_main_vbox,
			false,
		)

	dots_main_vbox.move_child(
		dots_top_hud,
		0,
	)

	dots_main_vbox.move_child(
		dots_board_center,
		1,
	)

	dots_main_vbox.move_child(
		dots_bottom_controls,
		2,
	)

	dots_main_vbox.alignment = (
		BoxContainer.ALIGNMENT_CENTER
	)

	dots_top_hud.z_index = 0

	_reset_dots_control_for_container(
		dots_top_hud,
	)

	_reset_dots_control_for_container(
		dots_board_center,
	)

	_reset_dots_control_for_container(
		dots_bottom_controls,
	)

	dots_top_hud.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	dots_top_hud.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER
	)

	dots_board_center.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	dots_board_center.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)

	dots_bottom_controls.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	dots_bottom_controls.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER
	)

	dots_main_vbox.queue_sort()

	call_deferred(
		"_finish_dots_portrait_restore",
	)


func _finish_dots_portrait_restore() -> void:
	await get_tree().process_frame

	if not is_inside_tree():
		return

	_reset_dots_control_for_container(
		dots_top_hud,
	)

	_reset_dots_control_for_container(
		dots_board_center,
	)

	_reset_dots_control_for_container(
		dots_bottom_controls,
	)

	dots_main_vbox.queue_sort()
	dots_top_hud.queue_sort()
	dots_board_center.queue_sort()
	dots_bottom_controls.queue_sort()

func _dots_avatar_scale_hint(
	viewport_size: Vector2,
	is_portrait: bool,
) -> float:
	if is_portrait:
		return 1.0

	var landscape_aspect := (
		viewport_size.x /
		maxf(
			viewport_size.y,
			1.0,
		)
	)

	return clampf(
		landscape_aspect,
		DOTS_LANDSCAPE_AVATAR_MIN_SCALE,
		DOTS_LANDSCAPE_AVATAR_MAX_SCALE,
	)


func _dots_landscape_action_height(
	avatar_scale: float,
) -> float:
	var largest_button_height := maxf(
		DOTS_BASE_MENU_BUTTON_SIZE.y,
		DOTS_BASE_SEND_BUTTON_SIZE.y,
	)

	return (
		largest_button_height *
			avatar_scale +
		DOTS_LANDSCAPE_BOTTOM_PADDING
	)


func _apply_dots_grid_visual_scale(
	board_scale: float,
) -> void:
	if not is_instance_valid(grid):
		return

	grid.set(
		"dot_radius",
		DOTS_BASE_DOT_RADIUS *
			board_scale,
	)

	grid.set(
		"line_width",
		DOTS_BASE_LINE_WIDTH *
			board_scale,
	)

	grid.set(
		"hover_width",
		DOTS_BASE_HOVER_WIDTH *
			board_scale,
	)

	var animation_line := (
		grid.get_node_or_null(
			"AnimationLine",
		) as Line2D
	)

	if animation_line != null:
		animation_line.width = (
			DOTS_BASE_ANIMATION_LINE_WIDTH *
			board_scale
		)

	grid.queue_redraw()


func _apply_dots_board_layout(
	viewport_size: Vector2,
	is_portrait: bool,
	action_scale: float,
) -> float:
	var board_display_size := 0.0

	if is_portrait:
		board_display_size = floorf(
			minf(
				viewport_size.x,
				viewport_size.y,
			) *
			DOTS_PORTRAIT_BOARD_RATIO
		)
	else:
		var target_stack_height := floorf(
			viewport_size.y *
			DOTS_LANDSCAPE_BOARD_HEIGHT_RATIO
		)

		var action_height := (
			_dots_landscape_action_height(
				action_scale,
			)
		)

		var available_board_height := maxf(
			target_stack_height -
				action_height -
				DOTS_BOARD_ACTION_GAP,
			1.0,
		)

		var available_board_width := maxf(
			viewport_size.x -
				DOTS_BASE_SIDE_MARGIN *
					2.0,
			1.0,
		)

		board_display_size = floorf(
			minf(
				available_board_height,
				available_board_width,
			)
		)

	board_display_size = maxf(
		board_display_size,
		1.0,
	)

	_dots_current_board_scale = (
		board_display_size /
		DOTS_REFERENCE_BOARD_SIZE
	)

	paper.custom_minimum_size = Vector2(
		board_display_size,
		board_display_size,
	)

	grid.custom_minimum_size = Vector2(
		board_display_size,
		board_display_size,
	)

	dots_board_center.custom_minimum_size = Vector2(
		board_display_size,
		board_display_size,
	)

	_apply_dots_grid_visual_scale(
		_dots_current_board_scale,
	)

	paper.queue_sort()
	grid.update_minimum_size()
	dots_board_center.queue_sort()

	return board_display_size

func _apply_dots_action_button_layout(
	avatar_scale: float,
) -> void:
	var menu_size := (
		DOTS_BASE_MENU_BUTTON_SIZE *
		avatar_scale
	)

	var menu_buttons: Array[Button] = [
		dots_settings_button,
		dots_rules_button,
	]

	for menu_button in menu_buttons:
		if not is_instance_valid(menu_button):
			continue

		menu_button.custom_minimum_size = menu_size

		menu_button.add_theme_font_size_override(
			"font_size",
			maxi(
				roundi(
					DOTS_BASE_MENU_BUTTON_FONT_SIZE *
						avatar_scale
				),
				1,
			),
		)

		menu_button.queue_redraw()

	if is_instance_valid(send_button):
		var send_size := (
			DOTS_BASE_SEND_BUTTON_SIZE *
			avatar_scale
		)

		send_button.size_flags_horizontal = (
			Control.SIZE_SHRINK_CENTER
		)

		send_button.size_flags_vertical = (
			Control.SIZE_SHRINK_CENTER
		)

		send_button.custom_minimum_size = send_size
		send_button.size = send_size
		send_button.scale = Vector2.ONE

		send_button.add_theme_font_size_override(
			"font_size",
			maxi(
				roundi(
					DOTS_BASE_SEND_BUTTON_FONT_SIZE *
						avatar_scale
				),
				1,
			),
		)

		send_button.pivot_offset = (
			send_button.size *
			0.5
		)


func _apply_dots_avatar_and_score_layout(
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
			DOTS_LANDSCAPE_AVATAR_MIN_SCALE,
			DOTS_LANDSCAPE_AVATAR_MAX_SCALE,
		)

	_dots_current_avatar_scale = avatar_scale

	_clear_dots_win_burst_proxies()

	var avatar_size := (
		DOTS_BASE_AVATAR_SIZE *
		avatar_scale
	)

	var avatars: Array[TextureButton] = [
		player_avatar_display,
		opp_avatar_display,
	]

	for avatar_button in avatars:
		if not is_instance_valid(avatar_button):
			continue

		_configure_dots_avatar(
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

	if is_instance_valid(you_label):
		you_label.add_theme_font_size_override(
			"font_size",
			maxi(
				roundi(
					DOTS_BASE_YOU_FONT_SIZE *
						avatar_scale
				),
				1,
			),
		)

	var score_labels: Array[Label] = [
		player_score_label,
		opp_score_label,
	]

	for score_label in score_labels:
		if not is_instance_valid(score_label):
			continue

		score_label.add_theme_font_size_override(
			"font_size",
			maxi(
				roundi(
					DOTS_BASE_SCORE_FONT_SIZE *
						avatar_scale
				),
				1,
			),
		)

	var score_icon_size := (
		DOTS_BASE_SCORE_ICON_SIZE *
		avatar_scale
	)

	player_color_icon.custom_minimum_size = score_icon_size
	opp_color_icon.custom_minimum_size = score_icon_size

	var marker_size := (
		DOTS_BASE_MARKER_SIZE *
		avatar_scale
	)

	player_marker.custom_minimum_size = marker_size
	opp_marker.custom_minimum_size = marker_size

	_apply_dots_action_button_layout(
		avatar_scale,
	)

func _apply_dots_landscape_positions(
	avatar_scale: float,
) -> void:
	var side_margin := (
		DOTS_BASE_SIDE_MARGIN *
		avatar_scale
	)

	var top_margin := (
		DOTS_BASE_TOP_MARGIN *
		avatar_scale
	)

	var score_height := (
		DOTS_BASE_SCORE_ICON_SIZE.y *
		avatar_scale
	)

	var avatar_stack_height := (
		DOTS_BASE_YOU_FONT_SIZE *
			avatar_scale +
		DOTS_BASE_AVATAR_SIZE.y *
			avatar_scale +
		score_height +
		10.0 *
			avatar_scale
	)

	var marker_height := (
		DOTS_BASE_MARKER_SIZE.y *
		avatar_scale
	)

	var top_hud_height := (
		maxf(
			avatar_stack_height,
			marker_height,
		) +
		top_margin
	)

	dots_top_hud.custom_minimum_size = Vector2(
		0.0,
		top_hud_height,
	)

	dots_top_hud.set_anchors_preset(
		Control.PRESET_TOP_WIDE,
		false,
	)

	dots_top_hud.offset_left = side_margin
	dots_top_hud.offset_top = top_margin
	dots_top_hud.offset_right = -side_margin
	dots_top_hud.offset_bottom = (
		top_margin +
		top_hud_height
	)

	dots_bottom_controls.custom_minimum_size = Vector2(
		0.0,
		_dots_landscape_action_height(
			avatar_scale,
		),
	)

	dots_main_vbox.add_theme_constant_override(
		"separation",
		roundi(
			DOTS_BOARD_ACTION_GAP,
		),
	)

	dots_top_hud.queue_sort()
	dots_bottom_controls.queue_sort()


func _restore_dots_portrait_layout() -> void:
	dots_top_hud.custom_minimum_size = Vector2.ZERO

	dots_bottom_controls.custom_minimum_size = Vector2(
		0.0,
		DOTS_PORTRAIT_BOTTOM_HEIGHT,
	)

	dots_main_vbox.add_theme_constant_override(
		"separation",
		_dots_portrait_vbox_separation,
	)

	_reset_dots_control_for_container(
		dots_top_hud,
	)

	_reset_dots_control_for_container(
		dots_board_center,
	)

	_reset_dots_control_for_container(
		dots_bottom_controls,
	)

	dots_main_vbox.queue_sort()

func _apply_dots_spectator_label_layout(
	content_scale: float,
	is_portrait: bool,
) -> void:
	if not is_instance_valid(spec_label):
		return

	var overlay_scale := 1.0

	if not is_portrait:
		overlay_scale = clampf(
			content_scale,
			DOTS_LANDSCAPE_OVERLAY_MIN_SCALE,
			DOTS_LANDSCAPE_OVERLAY_MAX_SCALE,
		)

	var top_offset := (
		DOTS_PORTRAIT_SPECTATOR_TOP_OFFSET
		if is_portrait
		else 0.0
	)

	spec_label.set_anchors_preset(
		Control.PRESET_CENTER_TOP,
		false,
	)

	spec_label.offset_left = (
		-DOTS_BASE_SPECTATOR_HALF_WIDTH *
			overlay_scale
	)

	spec_label.offset_right = (
		DOTS_BASE_SPECTATOR_HALF_WIDTH *
			overlay_scale
	)

	spec_label.offset_top = top_offset

	spec_label.offset_bottom = (
		top_offset +
		DOTS_BASE_SPECTATOR_HEIGHT *
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
				DOTS_BASE_SPECTATOR_FONT_SIZE *
					overlay_scale
			),
			1,
		),
	)

func _kill_dots_send_button_tween() -> void:
	if not is_instance_valid(send_button):
		return

	if not send_button.has_meta("sb_tween"):
		return

	var existing: Variant = send_button.get_meta(
		"sb_tween",
	)

	if (
		existing is Tween and
		(existing as Tween).is_running()
	):
		(existing as Tween).kill()


func _refresh_dots_send_button_home() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not is_inside_tree():
		return

	if not is_instance_valid(send_button):
		return

	if not is_instance_valid(dots_bottom_controls):
		return

	_kill_dots_send_button_tween()
	
	var send_size := (
		DOTS_BASE_SEND_BUTTON_SIZE *
		_dots_current_avatar_scale
	)

	send_button.custom_minimum_size = send_size
	send_button.size = send_size
	send_button.scale = Vector2.ONE
	send_button.pivot_offset = send_size * 0.5

	var should_show := _send_button_target_visible
	var root_rect := get_global_rect()
	var controls_rect := (
		dots_bottom_controls.get_global_rect()
	)

	_send_button_home_global = Vector2(
		root_rect.position.x +
			(
				root_rect.size.x -
				send_button.size.x
			) *
			0.5,
		controls_rect.position.y +
			(
				controls_rect.size.y -
					send_button.size.y
			) *
			0.5,
	)

	_send_button_home_ready = true
	send_button.set_as_top_level(true)
	send_button.global_position = (
		_send_button_home_global
	)

	if should_show:
		send_button.visible = true
		send_button.disabled = false
		send_button.mouse_filter = (
			Control.MOUSE_FILTER_STOP
		)

		send_button.modulate.a = 1.0
	else:
		send_button.visible = false
		send_button.disabled = true
		send_button.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE
		)

func _on_resized() -> void:
	_schedule_dots_responsive_layout(true)

func set_board_size(n: int) -> void:
	board_size = clamp(n, 4, 6)

	if is_instance_valid(grid) and grid.has_method(
		"set_grid",
	):
		grid.call(
			"set_grid",
			board_size,
		)

	if is_inside_tree():
		_schedule_dots_responsive_layout(true)

func _on_turn() -> void:
	pass

func _on_score(p0: int, p1: int) -> void:
	my_score = p0 if player == 1 else p1
	opp_score = p1 if player == 1 else p0

	if is_instance_valid(player_score_label):
		player_score_label.text = str(my_score)

	if is_instance_valid(opp_score_label):
		opp_score_label.text = str(opp_score)

	if _loading_replay:
		return

	game_ended = await check_win()

	if game_ended:
		stop_waiting_animation()
		_update_send_button_visibility(false)
		game_over = true

func _on_game_over() -> void:
	pass

func _on_temp_line_changed(has_line: bool) -> void:
	if game_over or spectator_mode or not is_my_turn:
		_update_send_button_visibility(false)
		return

	_update_send_button_visibility(has_line)
	
func _queue_send_button_initialization() -> void:
	if (
		_send_button_home_ready or
		_send_button_init_queued or
		not is_instance_valid(send_button)
	):
		return

	_send_button_init_queued = true
	call_deferred("_initialize_send_button_animation")

func _initialize_send_button_animation() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_send_button_init_queued = false

	if not is_instance_valid(send_button):
		return

	_send_button_home_global = send_button.global_position
	_send_button_home_ready = true

	OpLog.i(LOG_TAG, [
		"send_button_home_captured position=",
		_send_button_home_global,
		" size=",
		send_button.size,
		" parent=",
		send_button.get_parent().get_path()
	])

	send_button.set_as_top_level(true)
	send_button.global_position = _send_button_home_global
	send_button.visible = false
	send_button.disabled = true
	send_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	send_button.modulate.a = 1.0

	if _send_button_target_visible:
		_update_send_button_visibility(true)

func _update_send_button_visibility(
	should_show: bool
) -> void:
	if not is_instance_valid(send_button):
		return

	_send_button_target_visible = should_show
	send_button.disabled = not should_show

	if not _send_button_home_ready:
		send_button.visible = true
		send_button.disabled = true
		send_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		send_button.modulate.a = 0.0

		_queue_send_button_initialization()
		return

	_kill_dots_send_button_tween()

	var home := _send_button_home_global
	var root_bottom := get_global_rect().end.y

	var offscreen_position := Vector2(
		home.x,
		root_bottom +
			send_button.size.y +
			30.0,
	)

	if should_show:
		send_button.global_position = offscreen_position
		send_button.visible = true
		send_button.disabled = false
		send_button.mouse_filter = Control.MOUSE_FILTER_STOP
		send_button.modulate.a = 1.0

		var tween_in := create_tween()
		send_button.set_meta(
			"sb_tween",
			tween_in
		)

		tween_in.tween_property(
			send_button,
			"global_position",
			home,
			0.35
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_OUT
		)
	else:
		if not send_button.visible:
			return

		var tween_out := create_tween()
		send_button.set_meta(
			"sb_tween",
			tween_out
		)

		tween_out.tween_property(
			send_button,
			"global_position",
			offscreen_position,
			0.25
		).set_trans(
			Tween.TRANS_QUAD
		).set_ease(
			Tween.EASE_IN
		)

		tween_out.tween_callback(
			func() -> void:
				if (
					is_instance_valid(send_button) and
					not _send_button_target_visible
				):
					send_button.visible = false
					send_button.disabled = true
					send_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
					send_button.global_position = _send_button_home_global
		)

func _apply_dots_responsive_layout() -> void:
	_dots_layout_pending = false

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
		_dots_last_viewport_size,
	):
		return

	_dots_last_viewport_size = viewport_size

	var is_portrait := (
		viewport_size.y >=
		viewport_size.x
	)

	_set_dots_landscape_mode(
		not is_portrait,
	)

	var action_scale_hint := (
		_dots_avatar_scale_hint(
			viewport_size,
			is_portrait,
		)
	)

	var board_display_size := (
		_apply_dots_board_layout(
			viewport_size,
			is_portrait,
			action_scale_hint,
		)
	)

	var content_scale := clampf(
		board_display_size /
			DOTS_REFERENCE_BOARD_SIZE,
		0.5,
		2.0,
	)

	_apply_dots_avatar_and_score_layout(
		content_scale,
		is_portrait,
		viewport_size,
	)

	if is_portrait:
		_restore_dots_portrait_layout()
	else:
		_apply_dots_landscape_positions(
			_dots_current_avatar_scale,
		)

	_apply_dots_spectator_label_layout(
		content_scale,
		is_portrait,
	)

	_dots_layout_generation += 1

	call_deferred(
		"_finish_dots_responsive_layout",
		_dots_layout_generation,
	)

	dots_main_vbox.queue_sort()
	dots_board_center.queue_sort()


func _finish_dots_responsive_layout(
	layout_generation: int,
) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if (
		not is_inside_tree() or
		layout_generation !=
			_dots_layout_generation
	):
		return

	player_avatar_display.pivot_offset = (
		player_avatar_display.size *
		0.5
	)

	opp_avatar_display.pivot_offset = (
		opp_avatar_display.size *
		0.5
	)

	await _refresh_dots_send_button_home()

	_clear_dots_win_burst_proxies()

	if (
		is_instance_valid(win_loss_label) and
		win_loss_label.visible and
		is_instance_valid(
			_dots_active_win_burst_avatar
		)
	):
		_show_dots_win_burst(
			_dots_active_win_burst_avatar,
		)

func _on_send_pressed() -> void:
	if _settings_open or _rules_open:
		return

	OpLog.event(LOG_TAG, [
		"send_pressed game_over=", game_over,
		" spectator=", spectator_mode,
		" is_my_turn=", is_my_turn,
		" turn_steps=", _turn_steps.size()
	])

	if game_over or spectator_mode or not is_my_turn:
		OpLog.w(LOG_TAG, [
			"send_pressed_blocked game_over=", game_over,
			" spectator=", spectator_mode,
			" is_my_turn=", is_my_turn
		])
		_update_send_button_visibility(false)
		return

	var committed: bool = false

	recovery_committing_send = true

	if is_instance_valid(grid) and grid.has_method("commit_temp_line_now"):
		committed = bool(grid.call("commit_temp_line_now"))
	else:
		OpLog.w(LOG_TAG, "grid_missing_commit_temp_line_now")

	if committed:
		_save_dots_progress("sending")

	recovery_committing_send = false

	OpLog.i(LOG_TAG, ["commit_temp_line_now committed=", committed])

	is_my_turn = false

	if is_instance_valid(grid) and grid.has_method("set_input_enabled"):
		grid.call("set_input_enabled", false)

	_update_send_button_visibility(false)

	if has_method("send_game"):
		call_deferred("send_game")

func _parse_recovery_steps(raw_steps: String) -> Array:
	var result: Array = []

	if raw_steps.is_empty():
		return result

	for raw_step in raw_steps.split("|", false):
		var sides := raw_step.split(";", true, 1)
		var line_values := _csv_to_ints(String(sides[0]))

		if line_values.size() < 5:
			continue

		var step := {
			"line": [
				line_values[0],
				line_values[1],
				line_values[2],
				line_values[3],
				line_values[4]
			],
			"squares": []
		}

		if sides.size() > 1 and String(sides[1]) != "":
			for raw_square in String(sides[1]).split(":", false):
				var square_values := _csv_to_ints(raw_square)
				if square_values.size() >= 3:
					step["squares"].append([
						square_values[0],
						square_values[1],
						square_values[2]
					])

		result.append(step)

	return result

func _restore_dots_recovery() -> bool:
	if recovery_loaded or spectator_mode or not is_my_turn or game_over:
		return false

	if recovery_snapshot_pending:
		recovery_loaded = true
		is_my_turn = false

		if is_instance_valid(grid):
			grid.call_deferred("set_input_enabled", false)

		_update_send_button_visibility(false)
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

	if phase != "active" and phase != "sending":
		return false

	var saved_turn := String(progress.get("turn", ""))
	if not saved_turn.is_empty() and not recovery_turn_num.is_empty() and saved_turn != recovery_turn_num:
		OpLog.i(LOG_TAG, [
			"recovery_stale savedTurn=", saved_turn,
			" currentTurn=", recovery_turn_num
		])
		return false

	var steps := _parse_recovery_steps(String(progress.get("steps", "")))
	if steps.is_empty():
		return false

	recovery_loaded = true
	recovery_restore_in_progress = true
	_loading_replay = true
	_turn_steps.clear()

	var restored_lines: Array = opponent_post_lines.duplicate(true)
	var restored_squares: Array = opponent_post_squares.duplicate(true)

	for step in steps:
		if step.has("line"):
			restored_lines.append(step["line"])

		if step.has("squares"):
			restored_squares.append_array(step["squares"])

		_turn_steps.append(step.duplicate(true))

	if is_instance_valid(grid) and grid.has_method("load_lines_and_squares_state"):
		grid.call("load_lines_and_squares_state", restored_lines, restored_squares)

	_loading_replay = false
	recovery_restore_in_progress = false

	OpLog.i(LOG_TAG, [
		"recovery_restored phase=", phase,
		" steps=", _turn_steps.size(),
		" lines=", restored_lines.size(),
		" squares=", restored_squares.size()
	])

	if phase == "sending":
		is_my_turn = false

		if is_instance_valid(grid):
			grid.call("set_input_enabled", false)

		_update_send_button_visibility(false)
		stop_waiting_animation()
		call_deferred("send_game")
		return true

	is_my_turn = true

	if is_instance_valid(grid):
		grid.set("player", player)
		grid.call("set_input_enabled", true)
		grid.call("clear_temp_line")

	_update_send_button_visibility(false)
	stop_waiting_animation()

	game_ended = await check_win()

	if game_ended:
		game_over = true
		is_my_turn = false

		if is_instance_valid(grid):
			grid.call("set_input_enabled", false)

		call_deferred("send_game")

	return true

func send_game() -> void:
	await get_tree().process_frame

	if _turn_steps.is_empty():
		OpLog.w(LOG_TAG, "send_game_blocked no_committed_steps")
		_update_send_button_visibility(false)
		return

	var new_lines: Array = []
	var new_squares: Array = []

	for step in _turn_steps:
		if step.has("line"):
			new_lines.append(step["line"])

		if step.has("squares"):
			new_squares.append_array(step["squares"])

	var final_lines: Array = opponent_post_lines.duplicate(true)
	final_lines.append_array(new_lines)

	var final_squares: Array = opponent_post_squares.duplicate(true)
	final_squares.append_array(new_squares)

	var final_pre_board_str: String = post_board_str_from_opponent if post_board_str_from_opponent != "" else pre_board_str
	var final_post_board_str: String = _compose_board_string(final_lines, final_squares)

	var parts: Array[String] = []
	parts.append("board:" + final_pre_board_str)

	for step2 in _turn_steps:
		var mv: Array = step2["line"]
		parts.append("line:%d,%d,%d,%d,%d" % [int(mv[0]), int(mv[1]), int(mv[2]), int(mv[3]), int(mv[4])])

		for sq in (step2["squares"] as Array):
			parts.append("square:%d,%d,%d" % [int(sq[0]), int(sq[1]), int(sq[2])])

	parts.append("board:" + final_post_board_str)

	var replay: String = String("|").join(parts)
	last_replay_sent = replay

	var payload: Dictionary = {
		"replay": replay
	}

	var avatar_key := "avatar1" if player == 1 else "avatar2"
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	game_ended = await check_win()

	if game_ended:
		OpLog.event(LOG_TAG, [
			"send_game_check_win game_ended=true my_uuid=", my_uuid,
			" win_loss_state=", win_loss_state
		])

		if win_loss_state != "":
			payload["winner"] = my_uuid + "|" + win_loss_state

	var json := JSON.stringify(payload)

	OpLog.event(LOG_TAG, [
		"send_game_out player=", player,
		" new_lines=", new_lines.size(),
		" new_squares=", new_squares.size(),
		" final_lines=", final_lines.size(),
		" final_squares=", final_squares.size(),
		" game_ended=", game_ended,
		" game_over=", game_over,
		" has_winner=", payload.has("winner"),
		" replay_len=", replay.length(),
		" raw=", json
	])

	send_game_data(json)

	is_my_turn = false

	if is_instance_valid(grid) and grid.has_method("clear_temp_line"):
		grid.call("clear_temp_line")

	_update_send_button_visibility(false)

	if game_over:
		stop_waiting_animation()
	elif not spectator_mode:
		play_sent_animation()

	prev_lines_cache = final_lines
	_turn_steps.clear()

func _on_line_committed_bl(p: int, x1: int, y1: int, x2: int, y2: int) -> void:
	if recovery_restore_in_progress:
		return

	var mv := [p, x1, y1, x2, y2]

	for step in _turn_steps:
		if step.has("line") and step["line"] == mv:
			OpLog.d(LOG_TAG, ["duplicate_line_commit_ignored line=", mv])
			return

	_turn_steps.append({ "line": mv, "squares": [] })

	OpLog.event(LOG_TAG, [
		"line_committed player=", p,
		" line=", mv,
		" turn_steps=", _turn_steps.size()
	])

	_save_dots_progress("sending" if recovery_committing_send else "active")

func _on_square_completed_bl(p: int, x_bl: int, y_bl: int) -> void:
	if recovery_restore_in_progress:
		return

	if _turn_steps.size() > 0:
		var sq := [p, x_bl, y_bl]
		_turn_steps[_turn_steps.size() - 1]["squares"].append(sq)

		OpLog.event(LOG_TAG, [
			"square_completed player=", p,
			"square=", sq,
			" current_step=", _turn_steps[_turn_steps.size() - 1]
		])

		_save_dots_progress("sending" if recovery_committing_send else "active")
	else:
		OpLog.w(LOG_TAG, [
			"square_completed_without_turn_step player=", p,
			"x=", x_bl,
			" y=", y_bl
		])

func _find_new_moves(current_lines: Array, prev_lines: Array) -> Array:
	var new_moves: Array = []
	var prev_set := _lines_to_set(prev_lines)
	
	for l in current_lines:
		var k := str(l[0]) + ":" + str(l[1]) + "," + str(l[2]) + "," + str(l[3]) + "," + str(l[4])
		if not prev_set.has(k):
			new_moves.append([int(l[0]), int(l[1]), int(l[2]), int(l[3]), int(l[4])])
			
	return new_moves

func _lines_to_set(lines: Array) -> Dictionary:
	var d: Dictionary = {}
	for l in lines:
		if typeof(l) == TYPE_ARRAY and (l as Array).size() >= 5:
			var k := str(l[0]) + ":" + str(l[1]) + "," + str(l[2]) + "," + str(l[3]) + "," + str(l[4])
			d[k] = true
	return d

func _compose_move_string(move: Array) -> String:
	var p := int(move[0]); var x1 := int(move[1]); var y1 := int(move[2]); var x2 := int(move[3]); var y2 := int(move[4])
	return str(p) + "," + str(x1) + "," + str(y1) + "," + str(x2) + "," + str(y2)
	
func _get_committed_lines() -> Array:
	if is_instance_valid(grid) and grid.has_method("get_all_committed_lines"):
		var lines: Variant = grid.call("get_all_committed_lines")
		if typeof(lines) == TYPE_ARRAY:
			return (lines as Array)
	return prev_lines_cache.duplicate(true)

func _compose_board_string(lines: Array, squares: Array = []) -> String:
	var parts: Array[String] = []

	var _ser = func(a: Array) -> String:
		if a.size() == 5:
			return "%d,%d,%d,%d,%d" % [int(a[0]), int(a[1]), int(a[2]), int(a[3]), int(a[4])]
		elif a.size() == 3:
			return "%d,%d,%d" % [int(a[0]), int(a[1]), int(a[2])]
		return ""

	for l in lines:
		if typeof(l) == TYPE_ARRAY and (l as Array).size() == 5:
			var k: String = _ser.call(l)
			if k != "":
				parts.append(k)
	for s in squares:
		if typeof(s) == TYPE_ARRAY and (s as Array).size() == 3:
			var k2: String = _ser.call(s)
			if k2 != "":
				parts.append(k2)
	
	return String("#").join(parts)

func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Dots & Boxes[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
• Take turns drawing single lines between adjacent dots.
• Complete the 4th side of a 1×1 box to claim it and score 1 point.
• The player with the most boxes when no lines remain wins.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• On your turn, draw exactly one horizontal or vertical line between two neighboring dots.
• If your line completes a box, that box is marked with an [b]X[/b] in your color and you immediately take another turn.
• If your line does not complete a box, play passes to your opponent.
• Boxes can be claimed in chains: if completing one box lets you complete another, you continue until you draw a line that doesn’t finish a box.
[/font_size]

[font_size={24px}][b]End of Game[/b][/font_size]
[font_size={18px}]
• The game ends when every possible line has been drawn.
• Each claimed box is worth 1 point. Higher total wins.
• Ties are possible.
[/font_size]
"""

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		OpLog.w(LOG_TAG, "sent_animation_missing_label")
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

func check_win() -> bool:
	var total_boxes := (board_size - 1) * (board_size - 1)
	var claimed := my_score + opp_score

	OpLog.d(LOG_TAG, [
		"check_win claimed=", claimed,
		" total_boxes=", total_boxes,
		" my_score=", my_score,
		" opp_score=", opp_score,
		" game_over=", game_over,
		" spectator=", spectator_mode
	])

	if claimed < total_boxes:
		return false

	var was_over = game_over
	game_over = true

	if not was_over:
		_clear_dots_win_burst_proxies()
		_dots_active_win_burst_avatar = null

		OpLog.event(LOG_TAG, [
			"win_condition_met my_score=", my_score,
			" opp_score=", opp_score,
			" player=", player,
			" spectator=", spectator_mode
		])

		if my_score > opp_score:
			OpLog.event(LOG_TAG, "final_tally local_win")
			_show_dots_win_burst(
				player_avatar_display,
			)

			if not spectator_mode:
				win_loss_label.text = "YOU WIN!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			else:
				win_loss_label.text = "Player 1 Wins!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

			win_loss_state = "1"
		elif opp_score > my_score:
			OpLog.event(LOG_TAG, "final_tally local_loss")
			_show_dots_win_burst(
				opp_avatar_display,
			)

			if not spectator_mode:
				win_loss_label.text = "YOU LOSE"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			else:
				win_loss_label.text = "Player 2 Wins!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

			win_loss_state = "-1"
		else:
			OpLog.event(LOG_TAG, "final_tally_draw")
			win_loss_label.text = "DRAW!"
			win_loss_state = "0"
			win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))

		OpLog.event(LOG_TAG, [
			"show_result state=", win_loss_state,
			" text=", win_loss_label.text,
			" my_score=", my_score,
			" opp_score=", opp_score
		])

		win_loss_label.visible = true
		await get_tree().process_frame
		win_loss_label.scale = Vector2.ZERO
		win_loss_label.pivot_offset = win_loss_label.size / 2

		var tween_in = create_tween()
		tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	else:
		OpLog.d(LOG_TAG, "check_win_already_game_over")

	return true

func _apply_winner_payload(winner_payload: String, p1_id: String = "", p2_id: String = "") -> void:
	OpLog.event(LOG_TAG, [
		"apply_winner_payload payload=", winner_payload,
		" p1=", p1_id,
		" p2=", p2_id,
		" my_uuid=", my_uuid,
		" spectator=", spectator_mode
	])

	var parts := winner_payload.split("|", false)
	if parts.size() < 2:
		OpLog.w(LOG_TAG, ["bad_winner_payload payload=", winner_payload])
		return

	var sender_uuid := String(parts[0])
	var result := String(parts[1])

	game_over = true
	game_ended = true
	is_my_turn = false

	stop_waiting_animation()
	_update_send_button_visibility(false)

	_clear_dots_win_burst_proxies()
	_dots_active_win_burst_avatar = null

	if result == "0":
		win_loss_state = "0"
		win_loss_label.text = "DRAW!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
	elif spectator_mode:
		var sender_player := 0

		if sender_uuid == p1_id:
			sender_player = 1
		elif sender_uuid == p2_id:
			sender_player = 2

		var winning_player := sender_player

		if result == "-1":
			winning_player = 2 if sender_player == 1 else 1
			
		if winning_player == 1:
			win_loss_state = "1"
		elif winning_player == 2:
			win_loss_state = "-1"
		else:
			win_loss_state = ""

		if winning_player == 1:
			win_loss_label.text = "Player 1 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			_show_dots_win_burst(
				player_avatar_display,
			)
		elif winning_player == 2:
			win_loss_label.text = "Player 2 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			_show_dots_win_burst(
				opp_avatar_display,
			)
		else:
			win_loss_label.text = "Game Over"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	elif sender_uuid == my_uuid:
		if result == "1":
			win_loss_state = "1"
			win_loss_label.text = "YOU WIN!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			_show_dots_win_burst(
				player_avatar_display,
			)
		else:
			win_loss_state = "-1"
			win_loss_label.text = "YOU LOSE"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			_show_dots_win_burst(
				opp_avatar_display,
			)
	else:
		if result == "1":
			win_loss_state = "-1"
			win_loss_label.text = "YOU LOSE"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			_show_dots_win_burst(
				opp_avatar_display,
			)
		else:
			win_loss_state = "1"
			win_loss_label.text = "YOU WIN!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			_show_dots_win_burst(
				player_avatar_display,
			)

	OpLog.event(LOG_TAG, [
		"winner_resolved sender_uuid=", sender_uuid,
		" result=", result,
		" local_state=", win_loss_state,
		" text=", win_loss_label.text,
		" my_score=", my_score,
		" opp_score=", opp_score
	])

	win_loss_label.visible = true
	win_loss_label.scale = Vector2.ONE
