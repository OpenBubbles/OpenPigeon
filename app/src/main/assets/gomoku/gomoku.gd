extends BaseGame

@onready var PlayerBowl: TextureRect = %PlayerBowl
@onready var OppBowl: TextureRect = %OppBowl
@onready var Board: PanelContainer = %Board
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var sent_label: Label = %SentLabel
@onready var background: ColorRect = %Background
@onready var win_loss_label: Label = %WinLossLabel
@onready var you_label: Label = %YouLabel
@onready var spec_label: Label = %SpecLabel
@onready var send_button: Button = %SendButton
@onready var gomoku_root_margin: MarginContainer = %GomokuRootMargin
@onready var gomoku_main_vbox: VBoxContainer = %GomokuMainVBox
@onready var gomoku_top_hud: HBoxContainer = %TopInfoHBoxContainer
@onready var gomoku_bowls_hbox: HBoxContainer = %GomokuBowlsHBox
@onready var gomoku_opponent_top_spacer: Control = %GomokuOpponentTopSpacer
@onready var gomoku_board_center: CenterContainer = %GameBoard
@onready var gomoku_board_texture: TextureRect = %Board_Tex
@onready var gomoku_bottom_controls: HBoxContainer = %BottomItemHBoxContainer
@onready var gomoku_bottom_controls_margin: MarginContainer = %GomokuBottomControlsMargin

const PLAYER1_BOWL_TEX := preload("res://gomoku/player1_bowl.png")
const PLAYER2_BOWL_TEX := preload("res://gomoku/player2_bowl.png")
const MUSIC_STREAM := preload("res://global/audio/gomoku.ogg")

const GRID_SQUARES := 12
var board_size := GRID_SQUARES + 1
@export var BOARD_MARGIN_PX := 32.0
@export var TILE_TEXTURE_PATH := "res://gomoku/gomoku_tile.png"
const TILE_PX := 40
const SNAP_PX := 10.0
const BOARD_TILE_Z := 75
const LIFTED_TILE_Z := 90
const DUST_Z := 65
var _is_dragging := false
var _press_global := Vector2.ZERO
const DRAG_THRESHOLD := 6.0
var _drag_started := false
var _active_tile_tween: Tween
var _active_spawn_root_pos := Vector2.ZERO
var _active_spawn_valid := false
var _active_tile_lifted := false
var place_hint_label: Label

var is_my_turn = false
var game_id := ""
var board_state: Array = []          # 2D: board_state[y][x] = 0/1/2
var moves: Array = []                # history [{x,y,p}]
var game_ended := false
var win_loss_state = ""
var winner = null
var player
var game_over := false
var _ui_gesture_block := false
var _active_tile: TextureRect = null
var _active_from_bowl_offset := Vector2.ZERO
var _current_move := Vector2i(-1, -1)
var _has_uncommitted_move := false
var _drag_snapped_grid := Vector2i(-1, -1)
var _tile_tex: Texture2D
var last_win_coords: Array = []
var _preview_win_line: Array = []	# Vector2i[] for tentative move preview
var _win_preview_node: Control = null	# overlay that draws the golden outline
var _board_tiles_root: Control
var _rng := RandomNumberGenerator.new()
var send_button_tween: Tween
var sent_label_tween: Tween
var _send_btn_shown_y := 0.0
var _send_btn_hidden_y := 0.0

const LOG_TAG := "Gomoku"

const GOMOKU_LANDSCAPE_BOARD_HEIGHT_RATIO := 0.80
const GOMOKU_PORTRAIT_BOARD_SIZE := 600.0

const GOMOKU_BASE_AVATAR_SIZE := Vector2(
	96.0,
	90.0,
)

const GOMOKU_BASE_TOP_HUD_HEIGHT := 150.0
const GOMOKU_BASE_BOTTOM_HEIGHT := 150.0

const GOMOKU_BASE_SIDE_MARGIN := 40.0
const GOMOKU_BASE_TOP_MARGIN := 20.0
const GOMOKU_BASE_BOTTOM_MARGIN := 30.0

const GOMOKU_BASE_MENU_BUTTON_SIZE := Vector2(
	64.0,
	64.0,
)

const GOMOKU_BASE_SEND_BUTTON_SIZE := Vector2(
	70.0,
	50.0,
)

const GOMOKU_BASE_SEND_BUTTON_FONT_SIZE := 28.0
const GOMOKU_BOARD_SEND_GAP := 24.0

const GOMOKU_BASE_HINT_FONT_SIZE := 22.0
const GOMOKU_BASE_HINT_WIDTH := 420.0
const GOMOKU_BASE_HINT_HEIGHT := 56.0

var _gomoku_is_portrait := true

const GOMOKU_BASE_MENU_BUTTON_FONT_SIZE := 32.0
const GOMOKU_BASE_YOU_FONT_SIZE := 18.0
const GOMOKU_BASE_OPPONENT_SPACER_HEIGHT := 26.0

const GOMOKU_LANDSCAPE_AVATAR_MIN_SCALE := 2.05
const GOMOKU_LANDSCAPE_AVATAR_MAX_SCALE := 2.35

const GOMOKU_BASE_SPECTATOR_FONT_SIZE := 50.0
const GOMOKU_BASE_SPECTATOR_HALF_WIDTH := 324.0
const GOMOKU_BASE_SPECTATOR_HEIGHT := 220.0
const GOMOKU_PORTRAIT_SPECTATOR_TOP_OFFSET := 90.0

const GOMOKU_LANDSCAPE_OVERLAY_MIN_SCALE := 1.35
const GOMOKU_LANDSCAPE_OVERLAY_MAX_SCALE := 1.65

const GOMOKU_WIN_BURST_WRAPPER_NAME := (
	"GomokuResponsiveWinBurstWrapper"
)

const GOMOKU_TILE_GRID_META := &"gomoku_grid_position"

var _gomoku_responsive_layout_pending := false
var _gomoku_last_viewport_size := Vector2.ZERO
var _gomoku_layout_generation := 0

var _gomoku_current_avatar_scale := 1.0
var _gomoku_current_board_scale := 1.0

var _gomoku_base_player_bowl_size := Vector2(
	140.0,
	90.0,
)

var _gomoku_base_opponent_bowl_size := Vector2(
	140.0,
	90.0,
)

var _current_tile_px: float = float(TILE_PX)
var _current_board_margin_px: float = 32.0

var _gomoku_active_win_burst_avatar: TextureButton = null

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
func _get_dev_data() -> String:
	return '{"isYourTurn": true,"player":"2","map":"00000000000000000000000000000000000000000000000000000000000000000211100000000222110000000021111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000","move":"6,6,1","id":"dev"}'
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Gomoku"

func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	_rng.randomize()
	_tile_tex = load(TILE_TEXTURE_PATH)

	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)

	_make_runtime_nodes()
	_reset_board_arrays(GRID_SQUARES + 1)

	if is_instance_valid(Board):
		Board.mouse_filter = Control.MOUSE_FILTER_PASS

	if is_instance_valid(send_button):
		send_button.visible = false
		send_button.modulate.a = 0.0
		send_button.scale = Vector2(1.0, 1.0)

		var parent_h: float = send_button.get_parent().size.y
		_send_btn_shown_y = parent_h - send_button.size.y - 150.0
		_send_btn_hidden_y = parent_h + 40.0
		send_button.position.y = _send_btn_hidden_y

		if not send_button.pressed.is_connected(_on_send_button_pressed):
			send_button.pressed.connect(_on_send_button_pressed)

		OpLog.d(LOG_TAG, [
			"send_button_ready visible=", send_button.visible,
			" alpha=", send_button.modulate.a,
			" shown_y=", _send_btn_shown_y,
			" hidden_y=", _send_btn_hidden_y
		])
	else:
		OpLog.w(LOG_TAG, "missing_send_button")
		push_warning("No %SendButton in scene")
		
	_setup_place_hint_label()
	_update_place_hint_visibility()
	_initialize_gomoku_responsive_layout()
		
func _set_game_data(raw_text: String) -> void:
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", raw_text])

	var res: Variant = JSON.parse_string(raw_text)
	if typeof(res) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, ["set_game_data_parse_failed raw=", raw_text])
		return

	var d: Dictionary = res

	game_over = false
	game_ended = false
	win_loss_state = ""
	winner = ""
	spectator_mode = false
	is_my_turn = false
	_ui_gesture_block = false
	_is_dragging = false
	_has_uncommitted_move = false
	_current_move = Vector2i(-1, -1)
	last_win_coords = []

	stop_waiting_animation()
	_hide_send_button()
	_clear_win_preview()

	if is_instance_valid(win_loss_label):
		win_loss_label.visible = false
		win_loss_label.text = ""
		win_loss_label.scale = Vector2.ONE

	_gomoku_active_win_burst_avatar = null
	_clear_gomoku_win_burst_proxies()

	game_id = _get_first(d, "id", game_id)

	var p1_id: String = _get_first(d, "player1", "")
	var p2_id: String = _get_first(d, "player2", "")
	var sender_s: String = _get_first(d, "player", "1")
	var map_str: String = _get_first(d, "map", "")
	var move_str: String = _get_first(d, "move", "")
	var winner_payload: String = _get_first(d, "winner", "")
	var is_your_turn := bool(d.get("isYourTurn", false))
	var sender_player: int = clampi(int(sender_s), 1, 2)
	var opponent_avatar_key := ""

	OpLog.i(LOG_TAG, [
		"set_game_data_fields game_id=", game_id,
		" my_uuid=", my_uuid,
		" player1=", p1_id,
		" player2=", p2_id,
		" sender_player=", sender_player,
		" isYourTurn=", is_your_turn,
		" map_len=", map_str.length(),
		" move=", move_str,
		" has_winner=", winner_payload != ""
	])

	if p1_id != "" and p2_id != "":
		if my_uuid != "" and my_uuid == p1_id:
			player = 1
		elif my_uuid != "" and my_uuid == p2_id:
			player = 2
		else:
			player = 1
			spectator_mode = true
	else:
		player = (1 if ((sender_player == 2 and is_your_turn) or (sender_player == 1 and not is_your_turn)) else 2)

	is_my_turn = is_your_turn and not spectator_mode

	OpLog.i(LOG_TAG, [
		"resolved_player player=", player,
		" is_my_turn=", is_my_turn,
		" spectator=", spectator_mode
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

	opponent_avatar_key = "avatar2" if player == 1 else "avatar1"

	if opponent_avatar_key != "" and d.has(opponent_avatar_key):
		var avatar_string = d[opponent_avatar_key]
		var opponent_data = GameUtils._parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	if spectator_mode and d.has("avatar1"):
		var p1_data = GameUtils._parse_avatar_string(d["avatar1"])
		if is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", p1_data)

	_apply_bowl_skins()
	_clear_bowl(PlayerBowl)
	_clear_bowl(OppBowl)
	_top_up_bowl(PlayerBowl)
	_top_up_bowl(OppBowl)

	var inferred_dim: int = (_infer_dim_from_map(map_str) if map_str.length() > 0 else board_size)
	_reset_board_arrays(clampi(inferred_dim, 4, 32))
	_clear_board_visuals()
	_make_runtime_nodes()

	_schedule_gomoku_responsive_layout(true)

	OpLog.d(LOG_TAG, [
		"board_reset inferred_dim=", inferred_dim,
		" board_size=", board_size
	])

	if map_str.length() > 0:
		var dim: int = _infer_dim_from_map(map_str)
		var placed_from_map := 0

		for i in map_str.length():
			var ch := String(map_str[i])
			if ch == "1" or ch == "2":
				var col := i % dim
				@warning_ignore("integer_division")
				var row := i / dim
				var g := _proto_to_grid(row, col, dim)
				_place_stone_direct(g, int(ch))
				placed_from_map += 1

		OpLog.i(LOG_TAG, [
			"map_applied dim=", dim,
			" stones=", placed_from_map
		])

	var pending_incoming_move := Vector2i(-1, -1)
	var pending_incoming_stone := 0

	if move_str != "":
		var parts: PackedStringArray = move_str.split(",", false)
		if parts.size() >= 3:
			var row := int(parts[0])
			var col := int(parts[1])
			var gg: Vector2i = _proto_to_grid(row, col, board_size)
			var mp: int = int(parts[2])

			if _grid_in_bounds(gg) and board_state[gg.y][gg.x] == 0:
				if _is_opponent_stone_value(mp):
					pending_incoming_move = gg
					pending_incoming_stone = mp
					_ui_gesture_block = true

					OpLog.event(LOG_TAG, [
						"incoming_move_pending_animation proto_row=", row,
						" proto_col=", col,
						" grid=", gg,
						" p=", mp
					])
				else:
					_place_stone_direct(gg, mp)
					moves.append({"x": gg.x, "y": gg.y, "p": mp})
					_current_move = gg

					OpLog.event(LOG_TAG, [
						"incoming_move_applied_direct proto_row=", row,
						" proto_col=", col,
						" grid=", gg,
						" p=", mp
					])
			else:
				OpLog.w(LOG_TAG, [
					"incoming_move_rejected move=", move_str,
					" grid=", gg,
					" in_bounds=", _grid_in_bounds(gg),
					" cell=", board_state[gg.y][gg.x] if _grid_in_bounds(gg) else -1
				])
		else:
			OpLog.w(LOG_TAG, ["bad_incoming_move move=", move_str])

	if pending_incoming_stone != 0:
		await _animate_incoming_move_from_opp_bowl(
			pending_incoming_move,
			pending_incoming_stone
		)

	if winner_payload != "":
		OpLog.event(LOG_TAG, ["winner_payload_received payload=", winner_payload])
		_apply_winner_payload(winner_payload, p1_id, p2_id)
		return

	game_ended = check_win()

	if not game_ended:
		_current_move = Vector2i(-1, -1)

	if game_ended:
		stop_waiting_animation()
		is_my_turn = false
	elif not is_my_turn and not spectator_mode:
		start_waiting_animation()
	else:
		stop_waiting_animation()

	if _has_uncommitted_move:
		_return_active_to_bowl()
	else:
		_finalize_active_tile()

	_update_place_hint_visibility()

	_ui_gesture_block = false
	_is_dragging = false

	OpLog.i(LOG_TAG, [
		"set_game_data_done is_my_turn=", is_my_turn,
		" game_over=", game_over,
		" game_ended=", game_ended,
		" player=", player,
		" moves=", moves.size()
	])

func _remove_gomoku_win_burst_proxy(
	avatar_button: TextureButton,
) -> void:
	if not is_instance_valid(avatar_button):
		return

	var existing := avatar_button.get_node_or_null(
		GOMOKU_WIN_BURST_WRAPPER_NAME,
	)

	if existing == null:
		return

	avatar_button.remove_child(existing)
	existing.queue_free()

func _gomoku_avatar_scale_hint(
	viewport_size: Vector2,
	is_portrait: bool,
) -> float:
	if is_portrait:
		return 1.0

	var landscape_aspect: float = (
		viewport_size.x /
		maxf(
			viewport_size.y,
			1.0,
		)
	)

	return clampf(
		landscape_aspect,
		GOMOKU_LANDSCAPE_AVATAR_MIN_SCALE,
		GOMOKU_LANDSCAPE_AVATAR_MAX_SCALE,
	)

func _clear_gomoku_win_burst_proxies() -> void:
	_remove_gomoku_win_burst_proxy(
		player_avatar_display,
	)

	_remove_gomoku_win_burst_proxy(
		opp_avatar_display,
	)


func _create_gomoku_win_burst_target(
	avatar_button: TextureButton,
) -> TextureButton:
	if not is_instance_valid(avatar_button):
		return null

	_remove_gomoku_win_burst_proxy(
		avatar_button,
	)

	var wrapper := Control.new()

	wrapper.name = (
		GOMOKU_WIN_BURST_WRAPPER_NAME
	)

	wrapper.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	wrapper.show_behind_parent = true
	wrapper.clip_contents = false
	wrapper.size = GOMOKU_BASE_AVATAR_SIZE

	wrapper.pivot_offset = (
		GOMOKU_BASE_AVATAR_SIZE *
		0.5
	)

	wrapper.position = (
		avatar_button.size *
			0.5 -
		GOMOKU_BASE_AVATAR_SIZE *
			0.5
	)

	wrapper.scale = Vector2.ONE * (
		_gomoku_current_avatar_scale
	)

	avatar_button.add_child(wrapper)

	var target := TextureButton.new()

	target.name = "GomokuBurstTarget"
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.ignore_texture_size = true
	target.clip_contents = false
	target.size = GOMOKU_BASE_AVATAR_SIZE

	target.pivot_offset = (
		GOMOKU_BASE_AVATAR_SIZE *
		0.5
	)

	wrapper.add_child(target)

	return target


func _show_gomoku_win_burst(
	avatar_button: TextureButton,
) -> void:
	if not is_instance_valid(avatar_button):
		return

	_gomoku_active_win_burst_avatar = avatar_button

	var target := _create_gomoku_win_burst_target(
		avatar_button,
	)

	if not is_instance_valid(target):
		return

	GameUtils._show_win_burst(target)

func _panel_inner_rect() -> Rect2:
	var r := Board.get_rect()
	var sb := Board.get_theme_stylebox("panel")
	if sb == null: 
		return r
	var l := sb.get_content_margin(SIDE_LEFT)
	var t := sb.get_content_margin(SIDE_TOP)
	var rr := sb.get_content_margin(SIDE_RIGHT)
	var b := sb.get_content_margin(SIDE_BOTTOM)
	return Rect2(Vector2(l,t), Vector2(max(0.0, r.size.x-l-rr), max(0.0, r.size.y-t-b)))

func _grid_area_rect() -> Rect2:
	var inner := _panel_inner_rect()

	return Rect2(
		inner.position +
			Vector2(
				_current_board_margin_px,
				_current_board_margin_px,
			),
		inner.size -
			Vector2(
				2.0 *
					_current_board_margin_px,
				2.0 *
					_current_board_margin_px,
			),
	)

func _steps() -> Vector2:
	var area := _grid_area_rect()
	return Vector2(
		area.size.x / float(max(1, board_size-1)),
		area.size.y / float(max(1, board_size-1))
	)

func _grid_to_pos(g: Vector2i) -> Vector2:
	var area := _grid_area_rect()
	var s := _steps()
	return Vector2(area.position.x + g.x * s.x, area.position.y + g.y * s.y)

func _pos_to_grid(p: Vector2) -> Vector2i:
	var area := _grid_area_rect()
	var s := _steps()
	return Vector2i(roundi((p.x - area.position.x) / s.x), roundi((p.y - area.position.y) / s.y))

func _nearest_grid_center(local: Vector2) -> Dictionary:
	var area := _grid_area_rect()
	var s := _steps()
	var gx := clampi(roundi((local.x - area.position.x) / s.x), 0, board_size-1)
	var gy := clampi(roundi((local.y - area.position.y) / s.y), 0, board_size-1)
	var c := Vector2(area.position.x + gx*s.x, area.position.y + gy*s.y)
	return {"g": Vector2i(gx,gy), "pos": c, "dist": c.distance_to(local)}

func _has_active_local_move() -> bool:
	return _has_uncommitted_move and _current_move.x >= 0 and _current_move.y >= 0
	
func _stone_value_for_player(player_num: int) -> int:
	return 2 if player_num == 1 else 1


func _is_opponent_stone_value(stone_value: int) -> bool:
	if spectator_mode:
		return false

	return stone_value != _stone_value_for_player(player)

func _grid_in_bounds(g: Vector2i) -> bool:
	return g.x >= 0 and g.x < board_size and g.y >= 0 and g.y < board_size
	
func _root_local_from_global(p_global: Vector2) -> Vector2:
	return _to_local_ci(_board_tiles_root, p_global)

func _board_local_from_global(p_global: Vector2) -> Vector2:
	return _to_local_ci(Board, p_global)

func _to_local_ci(ci: CanvasItem, p_global: Vector2) -> Vector2:
	var inv := ci.get_global_transform_with_canvas().affine_inverse()
	return inv * p_global
	
func _is_point_over(ci: Control, p: Vector2) -> bool:
	return is_instance_valid(ci) and ci.is_visible_in_tree() and ci.get_global_rect().has_point(p)

func _is_over_blocking_ui(p: Vector2) -> bool:
	return _is_point_over(rules_button, p) \
		or _is_point_over(settings_button, p) \
		or _is_point_over(send_button, p)

func _event_pos(e: InputEvent) -> Vector2:
	if e is InputEventMouseButton: return (e as InputEventMouseButton).position
	if e is InputEventMouseMotion: return (e as InputEventMouseMotion).position
	if e is InputEventScreenTouch: return (e as InputEventScreenTouch).position
	if e is InputEventScreenDrag: return (e as InputEventScreenDrag).position
	return Vector2.INF

func _make_runtime_nodes() -> void:
	var old := get_node_or_null("BoardTiles")
	if old:
		old.queue_free()

	_board_tiles_root = Control.new()
	_board_tiles_root.name = "BoardTiles"
	_board_tiles_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_tiles_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_tiles_root.z_as_relative = false
	_board_tiles_root.z_index = 50
	Board.add_child(_board_tiles_root)

	_win_preview_node = WinLinePreview.new()
	_win_preview_node.name = "WinPreview"
	_win_preview_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_preview_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_preview_node.z_as_relative = false
	_win_preview_node.z_index = 40
	_win_preview_node.radius_px = _current_tile_px * 0.3
	_win_preview_node.get_pos_for_grid = func(g: Vector2i) -> Vector2:
		return _grid_to_pos(g)
	_board_tiles_root.add_child(_win_preview_node)

	Board.resized.connect(func():
		if is_instance_valid(_win_preview_node):
			_win_preview_node.queue_redraw()
	)

func _reset_board_arrays(dim:int) -> void:
	board_size = dim
	board_state.resize(board_size)
	for y in board_size:
		board_state[y] = []
		(board_state[y] as Array).resize(board_size)
		for x in board_size:
			board_state[y][x] = 0
	moves.clear()
	_current_move = Vector2i(-1,-1)
	_has_uncommitted_move = false
	_clear_win_preview()

func _clear_board_visuals() -> void:
	for c in _board_tiles_root.get_children():
		c.queue_free()

func _make_tile(is_black: bool) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _tile_tex
	t.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	t.ignore_texture_size = true
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(_current_tile_px, _current_tile_px)
	t.size = Vector2(_current_tile_px, _current_tile_px)
	t.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.z_as_relative = false
	t.z_index = 50
	t.modulate = (Color(0.139, 0.139, 0.139, 1.0) if is_black else Color.WHITE)
	return t
	
func _haptic_explosion(strength: float = 0.35, duration_ms: int = 22) -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return

	strength = clampf(strength, 0.0, 1.0)
	Input.vibrate_handheld(duration_ms, strength)
	
func _lift_active_tile_for_drag() -> void:
	if not is_instance_valid(_active_tile):
		return

	if _active_tile_lifted:
		return

	if _active_tile_tween and _active_tile_tween.is_running():
		_active_tile_tween.kill()

	_active_tile_lifted = true
	_active_tile.z_index = 90
	_active_tile.pivot_offset = _active_tile.size / 2.0

	_active_tile_tween = create_tween().set_parallel(true)
	_active_tile_tween.tween_property(_active_tile, "position", _active_tile.position + Vector2(0, -18.0), 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_active_tile_tween.tween_property(_active_tile, "scale", Vector2(1.08, 1.08), 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_active_tile_drag_pos(final_center_pos: Vector2) -> void:
	if not is_instance_valid(_active_tile):
		return

	var lifted_pos := Vector2(
		final_center_pos.x - _current_tile_px * 0.5,
		final_center_pos.y - _current_tile_px * 0.5 - 18.0
	)

	_set_tile_offsets(_active_tile, lifted_pos.x, lifted_pos.y)
	_active_tile.scale = Vector2(1.08, 1.08)
	_active_tile.z_index = 90
	_active_tile_lifted = true


func _drop_active_tile_to(final_pos: Vector2) -> void:
	if not is_instance_valid(_active_tile):
		return

	if _active_tile_tween and _active_tile_tween.is_running():
		_active_tile_tween.kill()

	_active_tile.z_index = 90
	_active_tile.pivot_offset = _active_tile.size / 2.0

	_active_tile_tween = create_tween().set_parallel(true)
	_active_tile_tween.tween_property(_active_tile, "position", final_pos, 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_active_tile_tween.tween_property(_active_tile, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	_active_tile_tween.tween_callback(func():
		if is_instance_valid(_active_tile):
			_set_tile_offsets(_active_tile, final_pos.x, final_pos.y)
			_active_tile.scale = Vector2.ONE
			_active_tile.z_index = BOARD_TILE_Z

			var center := final_pos + Vector2(_current_tile_px * 0.5, _current_tile_px * 0.5)
			_spawn_drop_dust(center)

		_active_tile_lifted = false
		_haptic_explosion(0.25, 18)
	)

func _animate_active_tile_to(final_pos: Vector2, lift_move: bool) -> void:
	if not is_instance_valid(_active_tile):
		return

	if _active_tile_tween and _active_tile_tween.is_running():
		_active_tile_tween.kill()

	_active_tile.z_index = 90
	_active_tile.pivot_offset = _active_tile.size / 2.0

	if lift_move:
		var lift_pos := _active_tile.position + Vector2(0, -18.0)
		var travel_pos := final_pos + Vector2(0, -18.0)

		_active_tile_tween = create_tween().set_parallel(false)
		_active_tile_tween.tween_property(_active_tile, "position", lift_pos, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_active_tile_tween.parallel().tween_property(_active_tile, "scale", Vector2(1.08, 1.08), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_active_tile_tween.tween_property(_active_tile, "position", travel_pos, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_active_tile_tween.tween_property(_active_tile, "position", final_pos, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_active_tile_tween.parallel().tween_property(_active_tile, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	else:
		_active_tile.scale = Vector2.ONE
		_active_tile_tween = create_tween()
		_active_tile_tween.tween_property(_active_tile, "position", final_pos, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_active_tile_tween.tween_callback(func():
		if is_instance_valid(_active_tile):
			_set_tile_offsets(_active_tile, final_pos.x, final_pos.y)
			_active_tile.scale = Vector2.ONE
			_active_tile.z_index = BOARD_TILE_Z

			var center := final_pos + Vector2(_current_tile_px * 0.5, _current_tile_px * 0.5)
			_spawn_drop_dust(center)

		if lift_move:
			_haptic_explosion(0.32, 22)
		else:
			_haptic_explosion(0.22, 16)
	)

func _set_tile_offsets(t: TextureRect, left: float, top: float) -> void:
	t.offset_left = left; t.offset_top = top; t.offset_right = left + _current_tile_px; t.offset_bottom = top + _current_tile_px

func _prepare_tile_for_board(tile: TextureRect, is_black: bool) -> TextureRect:
	if tile == null:
		tile = _make_tile(is_black)

	tile.texture = _tile_tex
	tile.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	tile.ignore_texture_size = true
	tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tile.custom_minimum_size = Vector2(_current_tile_px, _current_tile_px)
	tile.size = Vector2(_current_tile_px, _current_tile_px)
	tile.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.z_as_relative = false
	tile.z_index = BOARD_TILE_Z
	tile.scale = Vector2.ONE
	tile.modulate = Color(0.139, 0.139, 0.139, 1.0) if is_black else Color.WHITE

	return tile
	
func _take_tile_from_bowl_for_board(bowl: Control, is_black: bool) -> Dictionary:
	if is_instance_valid(bowl):
		for c in bowl.get_children():
			if c is TextureRect:
				var tile := c as TextureRect
				var start_pos := _root_local_from_global(tile.get_global_rect().position)

				bowl.remove_child(tile)

				return {
					"tile": tile,
					"start": start_pos
				}

	var fallback_tile := _make_tile(is_black)
	var fallback_start := Vector2.ZERO

	if is_instance_valid(bowl):
		var bowl_rect := bowl.get_global_rect()
		var bowl_center_global := bowl_rect.position + bowl_rect.size * 0.5
		fallback_start = _root_local_from_global(bowl_center_global) - Vector2(_current_tile_px * 0.5, _current_tile_px * 0.5)

	return {
		"tile": fallback_tile,
		"start": fallback_start
	}


func _animate_incoming_move_from_opp_bowl(g: Vector2i, p: int) -> void:
	if not _grid_in_bounds(g):
		OpLog.w(LOG_TAG, ["incoming_animation_blocked out_of_bounds grid=", g, " p=", p])
		_ui_gesture_block = false
		return

	if board_state[g.y][g.x] != 0:
		OpLog.w(LOG_TAG, [
			"incoming_animation_blocked occupied grid=", g,
			" p=", p,
			" cell=", board_state[g.y][g.x]
		])
		_ui_gesture_block = false
		return

	var is_black := p == 2
	var taken := _take_tile_from_bowl_for_board(OppBowl, is_black)

	var tile := taken["tile"] as TextureRect
	var start_pos := taken["start"] as Vector2

	tile = _prepare_tile_for_board(tile, is_black)
	tile.set_meta(
		GOMOKU_TILE_GRID_META,
		g,
	)

	if tile.get_parent() != null:
		tile.get_parent().remove_child(tile)

	_board_tiles_root.add_child(tile)

	_set_tile_offsets(tile, start_pos.x, start_pos.y)
	tile.z_index = LIFTED_TILE_Z
	tile.scale = Vector2(0.92, 0.92)

	var center := _grid_to_pos(g)
	var final_pos := Vector2(center.x - _current_tile_px * 0.5, center.y - _current_tile_px * 0.5)

	var tw := create_tween().set_parallel(false)

	tw.tween_property(
		tile,
		"position",
		final_pos + Vector2(0, -18.0),
		0.26
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	tw.tween_property(
		tile,
		"position",
		final_pos,
		0.12
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tw.parallel().tween_property(
		tile,
		"scale",
		Vector2.ONE,
		0.12
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await tw.finished

	if is_instance_valid(tile):
		_set_tile_offsets(tile, final_pos.x, final_pos.y)
		tile.scale = Vector2.ONE
		tile.z_index = BOARD_TILE_Z

	board_state[g.y][g.x] = p
	moves.append({"x": g.x, "y": g.y, "p": p})
	_current_move = g

	_spawn_drop_dust(center)
	_haptic_explosion(0.25, 18)
	_top_up_bowl(OppBowl)

	_ui_gesture_block = false

	OpLog.event(LOG_TAG, [
		"incoming_move_animation_finished grid=", g,
		" p=", p
	])
	
func _spawn_drop_dust(center: Vector2) -> void:
	if not is_instance_valid(_board_tiles_root):
		return

	var dust := DropDust.new()
	dust.setup()

	_board_tiles_root.add_child(dust)

	dust.z_as_relative = false
	dust.z_index = DUST_Z
	dust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dust.position = center - dust.size * 0.5 + Vector2(0, _current_tile_px * 0.32)
	dust.scale = Vector2(0.65, 0.50)
	dust.modulate.a = 0.0

	var start_pos := dust.position

	var tw := create_tween()
	tw.set_parallel(true)

	tw.tween_property(
		dust,
		"modulate:a",
		1.0,
		0.05
	)

	tw.tween_property(
		dust,
		"scale",
		Vector2(1.25, 0.90),
		0.20
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tw.tween_property(
		dust,
		"position",
		start_pos + Vector2(0, 4.0),
		0.20
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tw.set_parallel(false)

	tw.tween_property(
		dust,
		"modulate:a",
		0.0,
		0.16
	)

	tw.tween_callback(func():
		if is_instance_valid(dust):
			dust.queue_free()
	)

func _place_random_in_bowl(bowl: Control, t: TextureRect) -> void:
	var sz := (bowl.size if bowl.size != Vector2.ZERO else bowl.get_rect().size)
	var pad := 25.0
	var x := _rng.randf_range(pad, max(pad, sz.x - _current_tile_px - pad))
	var y := _rng.randf_range(pad, max(pad, sz.y - _current_tile_px - pad))
	_set_tile_offsets(t, x, y)

func _pop_bowl_tile(is_ours: bool) -> TextureRect:
	var bowl := (PlayerBowl if is_ours else OppBowl)

	for c in bowl.get_children():
		if c is TextureRect:
			if is_ours and is_instance_valid(_board_tiles_root):
				_active_spawn_root_pos = _root_local_from_global((c as TextureRect).get_global_rect().position)
				_active_spawn_valid = true

			bowl.remove_child(c)
			return c

	return null
	
func _clear_bowl(bowl: Control) -> void:
	for c in bowl.get_children():
		if c is TextureRect:
			bowl.remove_child(c)
			c.free()

func _top_up_bowl(bowl: Control) -> void:
	var count: int = 0
	var is_black: bool = (bowl == PlayerBowl and player == 1) or (bowl == OppBowl and player == 2)

	for c in bowl.get_children():
		if c is TextureRect and not c.is_queued_for_deletion():
			count += 1

	for _i in range(max(0, 8 - count)):
		var t: TextureRect = _make_tile(is_black)
		bowl.add_child(t)
		_place_random_in_bowl(bowl, t)

func _retint_bowl(bowl: Control, is_black: bool) -> void:
	for c in bowl.get_children():
		if c is TextureRect:
			(c as TextureRect).modulate = (Color(0.278, 0.278, 0.278, 1.0) if is_black else Color.WHITE)

func _ensure_active_tile() -> void:
	if _active_tile and is_instance_valid(_active_tile):
		return

	_active_spawn_valid = false
	_active_tile = _pop_bowl_tile(true)

	if _active_tile == null:
		_active_tile = _make_tile(player == 1)
		_active_spawn_valid = false

	_active_from_bowl_offset = Vector2(_active_tile.offset_left, _active_tile.offset_top)
	_active_tile = _prepare_tile_for_board(_active_tile, player == 1)
	_board_tiles_root.add_child(_active_tile)
	_active_tile.z_index = 75
	_active_tile.scale = Vector2.ONE

	if _active_spawn_valid:
		_set_tile_offsets(_active_tile, _active_spawn_root_pos.x, _active_spawn_root_pos.y)

func _place_or_move_active_to(g: Vector2i, from_drag: bool = false) -> void:
	if not _grid_in_bounds(g):
		return

	if _has_active_local_move() and _current_move == g:
		_has_uncommitted_move = true
		_show_send_button()
		_update_place_hint_visibility()
		_update_win_preview_for_current_move()

		if from_drag and is_instance_valid(_active_tile):
			var same_center := _grid_to_pos(g)
			var same_final_pos := Vector2(same_center.x - _current_tile_px * 0.5, same_center.y - _current_tile_px * 0.5)
			_drop_active_tile_to(same_final_pos)

		return

	if board_state[g.y][g.x] != 0:
		return

	var lift_move := _current_move.x >= 0 and _current_move.y >= 0 and is_instance_valid(_active_tile) and not from_drag

	if _has_active_local_move():
		board_state[_current_move.y][_current_move.x] = 0

	_ensure_active_tile()

	var p := (2 if player == 1 else 1)
	board_state[g.y][g.x] = p
	_current_move = g
	if is_instance_valid(_active_tile):
		_active_tile.set_meta(
			GOMOKU_TILE_GRID_META,
			g,
		)

	var c := _grid_to_pos(g)
	var final_pos := Vector2(c.x - _current_tile_px * 0.5, c.y - _current_tile_px * 0.5)

	if from_drag:
		_drop_active_tile_to(final_pos)
	else:
		_animate_active_tile_to(final_pos, lift_move)

	_has_uncommitted_move = true
	_show_send_button()

	OpLog.event(LOG_TAG, [
		"local_move_selected grid=", g,
		" p=", p,
		" player=", player,
		" from_drag=", from_drag
	])

	_update_win_preview_for_current_move()

	for i in range(moves.size() - 1, -1, -1):
		var m := moves[i] as Dictionary
		if int(m.get("p", 0)) == p:
			moves.remove_at(i)
			break

	moves.append({"x": g.x, "y": g.y, "p": p})

	OpLog.d(LOG_TAG, [
		"moves_history size=", moves.size(),
		" latest=", moves[-1]
	])

func _return_active_to_bowl() -> void:
	if _active_tile == null:
		return

	if _active_tile_tween and _active_tile_tween.is_running():
		_active_tile_tween.kill()

	_active_tile.scale = Vector2.ONE
	_active_tile.z_index = 50
	_active_tile_lifted = false

	_active_tile.remove_meta(
		GOMOKU_TILE_GRID_META,
	)

	_active_tile.reparent(
		PlayerBowl,
	)

	_place_random_in_bowl(
		PlayerBowl,
		_active_tile,
	)
	_active_tile = null
	_current_move = Vector2i(-1, -1)
	_clear_win_preview()
	_update_place_hint_visibility()
	
func _finalize_active_tile() -> void:
	if _active_tile:
		_active_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_active_tile = null

func _place_stone_direct(
	g: Vector2i,
	p: int,
) -> void:
	if not _grid_in_bounds(g):
		return

	board_state[g.y][g.x] = p

	var tile := _prepare_tile_for_board(
		null,
		p == 2,
	)

	tile.set_meta(
		GOMOKU_TILE_GRID_META,
		g,
	)

	_board_tiles_root.add_child(
		tile,
	)

	var center := _grid_to_pos(g)

	_set_tile_offsets(
		tile,
		center.x -
			_current_tile_px *
				0.5,
		center.y -
			_current_tile_px *
				0.5,
	)

func _input(e: InputEvent) -> void:
	if get("_settings_open") == true or get("_rules_open") == true:
		_ui_gesture_block = false
		_is_dragging = false
		_drag_started = false
		_drag_snapped_grid = Vector2i(-1, -1)
		return

	if _ui_gesture_block:
		if (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (e as InputEventMouseButton).pressed) \
		or (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed):
			_ui_gesture_block = false
			_is_dragging = false
			_drag_started = false
		return

	if not is_my_turn:
		return

	# -------- PRESS: mouse OR touch --------
	if (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (e as InputEventMouseButton).pressed) \
	or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed):
		var gp := _event_pos(e)
		if gp == Vector2.INF:
			return

		if _is_over_blocking_ui(gp):
			_is_dragging = false
			_drag_started = false
			return

		_ui_gesture_block = false
		_press_global = gp
		_is_dragging = true
		_drag_started = false
		_drag_snapped_grid = Vector2i(-1, -1)

	# -------- MOVE: mouse OR touch drag --------
	elif _is_dragging and (e is InputEventMouseMotion or e is InputEventScreenDrag):
		var gp := _event_pos(e)
		if gp == Vector2.INF:
			return

		if not _drag_started and gp.distance_to(_press_global) < DRAG_THRESHOLD:
			return

		if not _drag_started:
			_drag_started = true
			_ensure_active_tile()
			_lift_active_tile_for_drag()

		if not is_instance_valid(_active_tile):
			return

		var br: Rect2 = Board.get_global_rect()

		if br.has_point(gp):
			var local_board := _board_local_from_global(gp)
			var info := _nearest_grid_center(local_board)
			var c_board: Vector2 = info["pos"]
			_set_active_tile_drag_pos(c_board)
			_drag_snapped_grid = info["g"]
		else:
			var in_root := _root_local_from_global(gp)
			_set_active_tile_drag_pos(in_root)
			_drag_snapped_grid = Vector2i(-1, -1)

	# -------- RELEASE: mouse OR touch --------
	elif (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (e as InputEventMouseButton).pressed and _is_dragging) \
	or (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed and _is_dragging):
		_is_dragging = false

		var was_dragging := _drag_started
		var gp := _event_pos(e)

		if gp == Vector2.INF:
			gp = _press_global

		var br: Rect2 = Board.get_global_rect()

		if not br.has_point(gp):
			if was_dragging:
				_return_active_to_bowl()
				_hide_send_button()
				_has_uncommitted_move = false
				_clear_win_preview()

			_drag_started = false
			_drag_snapped_grid = Vector2i(-1, -1)
			return

		var local_board := _board_local_from_global(gp)
		var info := _nearest_grid_center(local_board)
		var g: Vector2i = info["g"]

		if not _grid_in_bounds(g):
			if was_dragging:
				_return_active_to_bowl()
				_hide_send_button()
				_has_uncommitted_move = false
				_clear_win_preview()

			_drag_started = false
			_drag_snapped_grid = Vector2i(-1, -1)
			return

		if _current_move == g:
			_place_or_move_active_to(g, was_dragging)
			_drag_started = false
			_drag_snapped_grid = Vector2i(-1, -1)
			return

		if board_state[g.y][g.x] == 0:
			_place_or_move_active_to(g, was_dragging)
		else:
			if was_dragging:
				_return_active_to_bowl()
				_hide_send_button()
				_has_uncommitted_move = false
				_clear_win_preview()

		_drag_started = false
		_drag_snapped_grid = Vector2i(-1, -1)

func _tween_send_button(sb: bool) -> void:
	if not is_instance_valid(send_button):
		return

	if send_button_tween:
		send_button_tween.kill()

	if sb:
		send_button.visible = true
		send_button.modulate.a = 1.0

	var target := (_send_btn_shown_y if sb else _send_btn_hidden_y)
	var dur := (0.25 if sb else 0.20)
	var ea := (Tween.EASE_OUT if sb else Tween.EASE_IN)

	send_button_tween = create_tween()
	send_button_tween.tween_property(send_button, "position:y", target, dur) \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(ea)

	if not sb:
		send_button_tween.tween_callback(func ():
			if is_instance_valid(send_button):
				send_button.visible = false
		)
		
func _setup_place_hint_label() -> void:
	if not is_instance_valid(send_button):
		return

	var existing := (
		find_child(
			"PlaceHintLabel",
			true,
			false,
		) as Label
	)

	if existing != null:
		place_hint_label = existing

		if place_hint_label.get_parent() != self:
			place_hint_label.reparent(
				self,
				false,
			)
	else:
		place_hint_label = Label.new()
		place_hint_label.name = "PlaceHintLabel"

		add_child(
			place_hint_label,
		)

	place_hint_label.text = (
		"Place a stone on an empty tile."
	)

	place_hint_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	place_hint_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	place_hint_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	place_hint_label.add_theme_color_override(
		"font_color",
		Color(
			1.0,
			1.0,
			1.0,
			0.9,
		),
	)

	place_hint_label.z_index = 99
	place_hint_label.visible = false

func _layout_gomoku_action_ui(
	is_portrait: bool,
) -> void:
	if not is_instance_valid(send_button):
		return

	var button_parent := (
		send_button.get_parent() as Control
	)

	if button_parent == null:
		return

	if (
		send_button_tween != null and
		send_button_tween.is_running()
	):
		send_button_tween.kill()

	var parent_height: float = maxf(
		button_parent.size.y,
		send_button.size.y,
	)

	_send_btn_shown_y = maxf(
		(
			parent_height -
				send_button.size.y
		) *
			0.5,
		0.0,
	)

	_send_btn_hidden_y = (
		parent_height +
			send_button.size.y +
			40.0
	)

	var should_show_send: bool = (
		_has_uncommitted_move and
		is_my_turn and
		not spectator_mode and
		not game_over
	)

	send_button.modulate.a = 1.0

	if should_show_send:
		send_button.visible = true
		send_button.position.y = _send_btn_shown_y
	else:
		send_button.position.y = _send_btn_hidden_y
		send_button.visible = false

	if not is_instance_valid(place_hint_label):
		return

	var hint_scale: float = (
		1.0
		if is_portrait
		else _gomoku_current_avatar_scale
	)

	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)

	var hint_width: float = minf(
		viewport_size.x *
			0.82,
		GOMOKU_BASE_HINT_WIDTH *
			hint_scale,
	)

	var hint_height: float = (
		GOMOKU_BASE_HINT_HEIGHT *
			hint_scale
	)

	var root_global_top: float = (
		get_global_rect().position.y
	)

	var parent_global_top: float = (
		button_parent.get_global_rect().position.y
	)

	var hint_top: float = (
		parent_global_top -
			root_global_top +
		_send_btn_shown_y +
		(
			send_button.size.y -
				hint_height
		) *
			0.5
	)

	place_hint_label.set_anchors_preset(
		Control.PRESET_CENTER_TOP,
		false,
	)

	place_hint_label.offset_left = (
		-hint_width *
			0.5
	)

	place_hint_label.offset_right = (
		hint_width *
			0.5
	)

	place_hint_label.offset_top = hint_top

	place_hint_label.offset_bottom = (
		hint_top +
			hint_height
	)

	place_hint_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	place_hint_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	place_hint_label.add_theme_font_size_override(
		"font_size",
		maxi(
			roundi(
				GOMOKU_BASE_HINT_FONT_SIZE *
					hint_scale
			),
			1,
		),
	)

	place_hint_label.pivot_offset = (
		place_hint_label.size *
			0.5
	)

	_update_place_hint_visibility()

func _update_place_hint_visibility() -> void:
	if not is_instance_valid(place_hint_label):
		return

	var should_show := is_my_turn \
		and not spectator_mode \
		and not game_over \
		and not _has_uncommitted_move \
		and _current_move.x < 0 \
		and not _is_dragging \
		and not _ui_gesture_block

	place_hint_label.visible = should_show

func _show_send_button() -> void:
	if is_instance_valid(place_hint_label):
		place_hint_label.visible = false

	_tween_send_button(true)


func _hide_send_button() -> void:
	_tween_send_button(false)
	call_deferred("_update_place_hint_visibility")

func _on_send_button_pressed() -> void:
	if game_over or spectator_mode or not is_my_turn:
		_hide_send_button()
		return

	if not _has_uncommitted_move or _current_move.x < 0:
		_hide_send_button()
		return

	_ui_gesture_block = true
	await send_game()
	_ui_gesture_block = false
	
func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		OpLog.w(LOG_TAG, "sent_animation_missing_label")
		return

	if game_over:
		return

	if sent_label_tween and sent_label_tween.is_running():
		sent_label_tween.kill()

	sent_label_tween = create_tween().set_parallel(false)

	sent_label.text = "Sent"
	sent_label.visible = true
	sent_label.modulate.a = 0.0
	sent_label.scale = Vector2.ONE
	sent_label.pivot_offset = sent_label.get_size() / 2.0

	sent_label_tween.tween_property(sent_label, "modulate:a", 1.0, 0.3)
	sent_label_tween.tween_interval(0.6)
	sent_label_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.text = "Sent ✔"
	)
	sent_label_tween.tween_interval(2.0)
	sent_label_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)

	sent_label_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0

		if not game_over and not spectator_mode and not is_my_turn:
			start_waiting_animation()
		else:
			stop_waiting_animation()
	)
	
func _apply_bowl_skins() -> void:
	if not (is_instance_valid(PlayerBowl) and is_instance_valid(OppBowl)):
		return
	match player:
		1:
			PlayerBowl.texture = PLAYER1_BOWL_TEX
			OppBowl.texture    = PLAYER2_BOWL_TEX
		2:
			PlayerBowl.texture = PLAYER2_BOWL_TEX
			OppBowl.texture    = PLAYER1_BOWL_TEX
		_:
			PlayerBowl.texture = PLAYER1_BOWL_TEX
			OppBowl.texture    = PLAYER2_BOWL_TEX

func _compose_current_map_string() -> String:
	var s := ""
	for row in range(0, board_size):
		for col in range(0, board_size):
			var g := _proto_to_grid(row, col, board_size)
			s += str(board_state[g.y][g.x])
	return s

func _compose_lagged_map_string() -> String:
	var s := ""

	for row in range(0, board_size):
		for col in range(0, board_size):
			var g := _proto_to_grid(row, col, board_size)

			if _has_active_local_move() and g == _current_move:
				s += "0"
			else:
				s += str(board_state[g.y][g.x])

	return s
	
func _find_five_or_more(p: int) -> Array:
	var dirs := [
		Vector2i(1, 0),  # →
		Vector2i(0, 1),  # ↓
		Vector2i(1, 1),  # ↘
		Vector2i(1, -1)  # ↗
	]

	for y in range(board_size):
		for x in range(board_size):
			if board_state[y][x] != p:
				continue

			for d in dirs:
				var coords: Array = []
				var cx: int = x
				var cy: int = y

				while cx >= 0 and cy >= 0 and cx < board_size and cy < board_size \
					and board_state[cy][cx] == p:
					coords.append(Vector2i(cx, cy))
					cx += d.x
					cy += d.y

				if coords.size() >= 5:
					OpLog.event(LOG_TAG, [
						"found_five_or_more p=", p,
						" coords=", coords
					])
					return coords

	return []

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
	var sender_state := String(parts[1])

	if sender_state == "0":
		_show_result_from_state("0")
		return

	var local_state := sender_state
	var winning_player := 0

	if spectator_mode:
		var sender_player := 0

		if sender_uuid == p1_id:
			sender_player = 1
		elif sender_uuid == p2_id:
			sender_player = 2

		winning_player = sender_player

		if sender_state == "-1":
			winning_player = 2 if sender_player == 1 else 1

		local_state = "1" if winning_player == 1 else "-1"
	else:
		if sender_uuid != my_uuid:
			local_state = "-1" if sender_state == "1" else "1"

	OpLog.i(LOG_TAG, [
		"winner_resolved sender_uuid=", sender_uuid,
		" sender_state=", sender_state,
		" local_state=", local_state,
		" winning_player=", winning_player
	])

	_show_result_from_state(local_state, winning_player)

func _show_result_from_state(state: String, spectator_winner_player: int = 0) -> void:
	game_over = true
	game_ended = true
	win_loss_state = state
	is_my_turn = false
	_has_uncommitted_move = false
	_ui_gesture_block = false
	_is_dragging = false
	
	OpLog.event(LOG_TAG, [
		"show_result state=", state,
		" spectator_winner_player=", spectator_winner_player,
		" player=", player,
		" spectator=", spectator_mode,
		" last_win_coords=", last_win_coords
	])

	stop_waiting_animation()
	_hide_send_button()

	if not is_instance_valid(win_loss_label):
		return

	_clear_gomoku_win_burst_proxies()
	_gomoku_active_win_burst_avatar = null

	if state == "0":
		win_loss_label.text = "DRAW!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
	elif spectator_mode:
		var player_num := spectator_winner_player

		if player_num == 0:
			player_num = 1 if state == "1" else 2

		win_loss_label.text = "Player %d Wins!" % player_num
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

		if player_num == 1:
			if is_instance_valid(player_avatar_display):
				_show_gomoku_win_burst(
					player_avatar_display,
				)
		else:
			if is_instance_valid(opp_avatar_display):
				_show_gomoku_win_burst(
					opp_avatar_display,
				)
	elif state == "1":
		win_loss_label.text = "YOU WIN!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

		if is_instance_valid(player_avatar_display):
			_show_gomoku_win_burst(
				player_avatar_display,
			)
	else:
		win_loss_label.text = "YOU LOSE"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

		if is_instance_valid(opp_avatar_display):
			_show_gomoku_win_burst(
				opp_avatar_display,
			)

	win_loss_label.visible = true
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2

	var tween_in := create_tween()
	tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func check_win() -> bool:
	OpLog.d(LOG_TAG, [
		"check_win start player=", player,
		" current_move=", _current_move
	])

	var p1_coords: Array = []
	var p2_coords: Array = []

	if _current_move.x >= 0 and _current_move.y >= 0:
		var cur_p: int = int(board_state[_current_move.y][_current_move.x])

		OpLog.d(LOG_TAG, [
			"check_win current_cell value=", cur_p,
			" current_move=", _current_move
		])

		if cur_p == 2:
			p1_coords = _get_line_through_cell(2, _current_move)
			OpLog.d(LOG_TAG, ["check_win p1_line=", p1_coords])
		elif cur_p == 1:
			p2_coords = _get_line_through_cell(1, _current_move)
			OpLog.d(LOG_TAG, ["check_win p2_line=", p2_coords])

	if p1_coords.is_empty() and p2_coords.is_empty():
		OpLog.d(LOG_TAG, "check_win full_board_scan")
		p1_coords = _find_five_or_more(2)
		p2_coords = _find_five_or_more(1)
	else:
		OpLog.d(LOG_TAG, "check_win skip_full_scan_line_found")

	var p1_has: bool = p1_coords.size() >= 5
	var p2_has: bool = p2_coords.size() >= 5

	OpLog.i(LOG_TAG, [
		"check_win result p1_has=", p1_has,
		" p2_has=", p2_has,
		" p1_len=", p1_coords.size(),
		" p2_len=", p2_coords.size()
	])

	if not p1_has and not p2_has:
		last_win_coords = []
		return false

	if p1_has and not p2_has:
		last_win_coords = p1_coords
		OpLog.event(LOG_TAG, ["game_finished winner_player=1 coords=", last_win_coords])
		_show_result_from_state("1" if player == 1 else "-1", 1)
	elif p2_has and not p1_has:
		last_win_coords = p2_coords
		OpLog.event(LOG_TAG, ["game_finished winner_player=2 coords=", last_win_coords])
		_show_result_from_state("1" if player == 2 else "-1", 2)
	else:
		last_win_coords = []
		OpLog.event(LOG_TAG, "game_finished draw both_players_have_line")
		_show_result_from_state("0")

	if is_instance_valid(_win_preview_node):
		_win_preview_node.coords = last_win_coords
		_win_preview_node.queue_redraw()
		OpLog.d(LOG_TAG, ["win_overlay_coords=", last_win_coords])

	return true

func send_game() -> void:
	await get_tree().process_frame

	if _current_move.x < 0:
		OpLog.w(LOG_TAG, "send_game_blocked no_current_move")
		_hide_send_button()
		return

	var proto := _grid_to_proto(_current_move, board_size)
	var send_row := proto.x
	var send_col := proto.y
	var p := 2 if player == 1 else 1

	var payload := {
		"map": _compose_lagged_map_string(),
		"move": "%d,%d,%d" % [send_row, send_col, p]
	}

	var avatar_key := "avatar1" if player == 1 else "avatar2"
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	game_ended = check_win()
	
	if not game_ended:
		_current_move = Vector2i(-1, -1)

	if game_ended and win_loss_state != "":
		payload["winner"] = my_uuid + "|" + win_loss_state
		OpLog.event(LOG_TAG, [
			"send_game_winner winner=", payload["winner"],
			" win_loss_state=", win_loss_state
		])

	var json := JSON.stringify(payload)

	OpLog.event(LOG_TAG, [
		"send_game_out player=", player,
		" p=", p,
		" current_move=", _current_move,
		" proto_row=", send_row,
		" proto_col=", send_col,
		" board_size=", board_size,
		" game_ended=", game_ended,
		" game_over=", game_over,
		" has_winner=", payload.has("winner"),
		" map_len=", str(payload["map"]).length(),
		" raw=", json
	])

	send_game_data(json)

	_has_uncommitted_move = false
	_hide_send_button()
	is_my_turn = false
	_update_place_hint_visibility()
	_finalize_active_tile()

	if not game_ended:
		OpLog.d(LOG_TAG, "send_game_no_win_clear_preview")
		_clear_win_preview()
	else:
		OpLog.d(LOG_TAG, [
			"send_game_keep_preview win_loss_state=", win_loss_state,
			" last_win_coords=", last_win_coords
		])

	_top_up_bowl(PlayerBowl)
	_top_up_bowl(OppBowl)

	if game_over:
		stop_waiting_animation()
	else:
		play_sent_animation()

func _proto_to_grid(row: int, col: int, dim: int) -> Vector2i:
	var x_grid := col
	var y_grid := (dim - 1) - row
	return Vector2i(x_grid, y_grid)


func _grid_to_proto(g: Vector2i, dim: int) -> Vector2i:
	var row := (dim - 1) - g.y
	var col := g.x
	return Vector2i(row, col)

func _get_first(d: Dictionary, key: String, def: String = "") -> String:
	if not d.has(key):
		return def
	var v: Variant = d[key]
	if typeof(v) == TYPE_STRING:
		return v
	if typeof(v) == TYPE_ARRAY and (v as Array).size() > 0:
		return String((v as Array)[0])
	return def
	
func _is_all_zeros(s: String) -> bool:
	for i in s.length():
		if s[i] != '0':
			return false
	return true
	
func _infer_dim_from_map(m:String)->int:
	var L := m.length(); if L<=0: return board_size
	var r := int(round(sqrt(L))); return (board_size if r*r!=L else r)

func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		OpLog.d(LOG_TAG, ["apply_background is_dark=", is_dark])
		background.color = Color("#261a19") if is_dark else Color("#947972")

func _configure_gomoku_avatar(
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

func _initialize_gomoku_responsive_layout() -> void:
	_configure_gomoku_avatar(
		player_avatar_display,
	)

	_configure_gomoku_avatar(
		opp_avatar_display,
	)

	PlayerBowl.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)

	OppBowl.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)

	await get_tree().process_frame

	if PlayerBowl.size.x > 1.0 and PlayerBowl.size.y > 1.0:
		_gomoku_base_player_bowl_size = PlayerBowl.size

	if OppBowl.size.x > 1.0 and OppBowl.size.y > 1.0:
		_gomoku_base_opponent_bowl_size = OppBowl.size

	var viewport := get_viewport()

	if viewport == null:
		return

	if not viewport.size_changed.is_connected(
		_on_gomoku_viewport_size_changed,
	):
		viewport.size_changed.connect(
			_on_gomoku_viewport_size_changed,
		)

	_schedule_gomoku_responsive_layout(true)


func _on_gomoku_viewport_size_changed() -> void:
	_schedule_gomoku_responsive_layout(true)


func _schedule_gomoku_responsive_layout(
	force: bool = false,
) -> void:
	if force:
		_gomoku_last_viewport_size = Vector2.ZERO

	if _gomoku_responsive_layout_pending:
		return

	_gomoku_responsive_layout_pending = true

	call_deferred(
		"_apply_gomoku_responsive_layout",
	)

func _reset_gomoku_control_for_container(
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


func _set_gomoku_landscape_overlay_mode(
	enabled: bool,
) -> void:
	if enabled:
		if gomoku_top_hud.get_parent() != self:
			gomoku_top_hud.reparent(
				self,
				false,
			)

		if gomoku_bottom_controls.get_parent() != self:
			gomoku_bottom_controls.reparent(
				self,
				false,
			)

		gomoku_main_vbox.move_child(
			gomoku_board_center,
			0,
		)

		gomoku_main_vbox.alignment = (
			BoxContainer.ALIGNMENT_CENTER
		)

		gomoku_board_center.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL
		)

		gomoku_board_center.size_flags_vertical = (
			Control.SIZE_EXPAND_FILL
		)

		gomoku_top_hud.z_index = 20
		gomoku_bottom_controls.z_index = 20
		spec_label.z_index = 30

		gomoku_main_vbox.queue_sort()
		return

	if gomoku_top_hud.get_parent() != gomoku_main_vbox:
		gomoku_top_hud.reparent(
			gomoku_main_vbox,
			false,
		)

	if gomoku_bottom_controls.get_parent() != gomoku_main_vbox:
		gomoku_bottom_controls.reparent(
			gomoku_main_vbox,
			false,
		)

	gomoku_main_vbox.move_child(
		gomoku_top_hud,
		0,
	)

	gomoku_main_vbox.move_child(
		gomoku_board_center,
		1,
	)

	gomoku_main_vbox.move_child(
		gomoku_bottom_controls,
		2,
	)

	gomoku_main_vbox.alignment = (
		BoxContainer.ALIGNMENT_BEGIN
	)

	gomoku_top_hud.z_index = 0
	gomoku_bottom_controls.z_index = 0

	_reset_gomoku_control_for_container(
		gomoku_top_hud,
	)

	_reset_gomoku_control_for_container(
		gomoku_board_center,
	)

	_reset_gomoku_control_for_container(
		gomoku_bottom_controls,
	)

	gomoku_top_hud.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	gomoku_top_hud.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER
	)

	gomoku_board_center.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	gomoku_board_center.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)

	gomoku_bottom_controls.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	gomoku_bottom_controls.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER
	)

	gomoku_main_vbox.queue_sort()

func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Gomoku[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
• Place your stones on the intersections of the board.
• Be the first player to create an unbroken line of 5 or more stones.
• Lines can be horizontal, vertical, or diagonal.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• Players take turns placing a stone on an empty intersection.
• If your placed stone creates 5 or more in a row, your winning line will be highlighted.
[/font_size]

[font_size={24px}][b]End of Game[/b][/font_size]
[font_size={18px}]
• The game ends immediately when a player forms a line of 5 or more stones.
• That player is declared the winner.
• If both players simultaneously achieve a line (rare), the game is a draw.
[/font_size]
"""

class GridDebug:
	extends Control
	var get_centers: Callable = Callable()
	func _draw():
		if not get_centers.is_valid():
			return
		var pts: Array = get_centers.call()
		for p in pts:
			draw_circle(p, 2.0, Color(1, 0, 0, 0.9))

class BoardGrid:
	extends Control
	var get_area: Callable  = Callable()
	var get_steps: Callable = Callable()
	var n: int = 12
	func _draw():
		if not get_area.is_valid() or not get_steps.is_valid():
			return
		var area: Rect2 = get_area.call()
		var s: Vector2  = get_steps.call()
		var col := Color(0, 0, 0, 1)
		draw_rect(area, Color(0, 0, 0, 0), false, 2.0, true)
		for i in n:
			var x := area.position.x + i * s.x
			var y := area.position.y + i * s.y
			draw_line(Vector2(x, area.position.y), Vector2(x, area.position.y + area.size.y), col, 1.0)
			draw_line(Vector2(area.position.x, y), Vector2(area.position.x + area.size.x, y), col, 1.0)


func _get_line_through_cell(p: int, start_g: Vector2i) -> Array:
	if not _grid_in_bounds(start_g):
		return []
	if board_state[start_g.y][start_g.x] != p:
		return []

	var best: Array = []
	var dirs := [
		Vector2i(1, 0),		# →
		Vector2i(0, 1),		# ↓
		Vector2i(1, 1),		# ↘
		Vector2i(1, -1)		# ↗
	]

	for d in dirs:
		var coords: Array = []
		var g := start_g

		while true:
			var prev := Vector2i(g.x - d.x, g.y - d.y)
			if prev.x < 0 or prev.y < 0 or prev.x >= board_size or prev.y >= board_size:
				break
			if board_state[prev.y][prev.x] != p:
				break
			g = prev

		while true:
			coords.append(g)
			var next := Vector2i(g.x + d.x, g.y + d.y)
			if next.x < 0 or next.y < 0 or next.x >= board_size or next.y >= board_size:
				break
			if board_state[next.y][next.x] != p:
				break
			g = next

		if coords.size() > best.size():
			best = coords

	return best

func _clear_win_preview() -> void:
	_preview_win_line.clear()
	if is_instance_valid(_win_preview_node):
		_win_preview_node.coords = []
		_win_preview_node.queue_redraw()

func _apply_gomoku_board_layout(
	viewport_size: Vector2,
	is_portrait: bool,
	action_scale: float,
) -> float:
	var target_board_size: float = (
		GOMOKU_PORTRAIT_BOARD_SIZE
	)

	if not is_portrait:
		var target_stack_height: float = floorf(
			viewport_size.y *
				GOMOKU_LANDSCAPE_BOARD_HEIGHT_RATIO
		)

		var reserved_send_height: float = (
			GOMOKU_BASE_SEND_BUTTON_SIZE.y *
				action_scale +
			GOMOKU_BOARD_SEND_GAP
		)

		var height_limited_size: float = floorf(
			maxf(
				target_stack_height -
					reserved_send_height,
				1.0,
			)
		)

		var width_limited_size: float = floorf(
			viewport_size.x -
				GOMOKU_BASE_TOP_MARGIN *
					2.0
		)

		target_board_size = maxf(
			minf(
				height_limited_size,
				width_limited_size,
			),
			1.0,
		)

		Board.custom_minimum_size = Vector2(
			target_board_size,
			target_board_size,
		)

		gomoku_board_texture.custom_minimum_size = Vector2(
			target_board_size,
			target_board_size,
		)

		gomoku_board_center.custom_minimum_size = Vector2(
			target_board_size,
			target_board_size,
		)
	else:
		Board.custom_minimum_size = Vector2.ZERO

		gomoku_board_texture.custom_minimum_size = Vector2(
			0.0,
			GOMOKU_PORTRAIT_BOARD_SIZE,
		)

		gomoku_board_center.custom_minimum_size = Vector2.ZERO

	_gomoku_current_board_scale = (
		target_board_size /
			GOMOKU_PORTRAIT_BOARD_SIZE
	)

	_current_tile_px = (
		float(TILE_PX) *
			_gomoku_current_board_scale
	)

	_current_board_margin_px = (
		BOARD_MARGIN_PX *
			_gomoku_current_board_scale
	)

	Board.queue_sort()
	gomoku_board_texture.queue_redraw()
	gomoku_board_center.queue_sort()

	return target_board_size

func _apply_gomoku_send_button_layout(
	avatar_scale: float,
) -> void:
	if not is_instance_valid(send_button):
		return

	var button_size: Vector2 = (
		GOMOKU_BASE_SEND_BUTTON_SIZE *
			avatar_scale
	)

	send_button.custom_minimum_size = button_size
	send_button.scale = Vector2.ONE
	send_button.size = button_size

	send_button.add_theme_font_size_override(
		"font_size",
		maxi(
			roundi(
				GOMOKU_BASE_SEND_BUTTON_FONT_SIZE *
					avatar_scale
			),
			1,
		),
	)

	send_button.pivot_offset = (
		button_size *
			0.5
	)

	send_button.queue_redraw()

func _apply_gomoku_menu_button_layout(
	avatar_scale: float,
) -> void:
	var button_size := (
		GOMOKU_BASE_MENU_BUTTON_SIZE *
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
					GOMOKU_BASE_MENU_BUTTON_FONT_SIZE *
						avatar_scale
				),
				1,
			),
		)

		menu_button.queue_redraw()


func _apply_gomoku_avatar_and_tray_layout(
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
			GOMOKU_LANDSCAPE_AVATAR_MIN_SCALE,
			GOMOKU_LANDSCAPE_AVATAR_MAX_SCALE,
		)

	_gomoku_current_avatar_scale = avatar_scale

	_clear_gomoku_win_burst_proxies()

	var avatar_size := (
		GOMOKU_BASE_AVATAR_SIZE *
		avatar_scale
	)

	var avatars: Array[TextureButton] = [
		player_avatar_display,
		opp_avatar_display,
	]

	for avatar_button in avatars:
		if not is_instance_valid(avatar_button):
			continue

		_configure_gomoku_avatar(
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
	
	_apply_gomoku_send_button_layout(
		avatar_scale,
	)
	
	PlayerBowl.custom_minimum_size = (
		_gomoku_base_player_bowl_size *
		avatar_scale
	)

	OppBowl.custom_minimum_size = (
		_gomoku_base_opponent_bowl_size *
		avatar_scale
	)

	PlayerBowl.queue_redraw()
	OppBowl.queue_redraw()
	gomoku_bowls_hbox.queue_sort()

	you_label.add_theme_font_size_override(
		"font_size",
		maxi(
			roundi(
				GOMOKU_BASE_YOU_FONT_SIZE *
					avatar_scale
			),
			1,
		),
	)

	gomoku_opponent_top_spacer.custom_minimum_size = Vector2(
		0.0,
		GOMOKU_BASE_OPPONENT_SPACER_HEIGHT *
			avatar_scale,
	)

	_apply_gomoku_menu_button_layout(
		avatar_scale,
	)

func _apply_gomoku_landscape_overlay_positions(
	avatar_scale: float,
) -> void:
	var side_margin := (
		GOMOKU_BASE_SIDE_MARGIN *
		avatar_scale
	)

	var top_margin := (
		GOMOKU_BASE_TOP_MARGIN *
		avatar_scale
	)

	var bottom_margin := (
		GOMOKU_BASE_BOTTOM_MARGIN *
		avatar_scale
	)

	var avatar_stack_height := (
		GOMOKU_BASE_AVATAR_SIZE.y *
			avatar_scale +
		GOMOKU_BASE_YOU_FONT_SIZE *
			avatar_scale
	)

	var tray_height := maxf(
		PlayerBowl.custom_minimum_size.y,
		OppBowl.custom_minimum_size.y,
	)

	var top_hud_height := (
		maxf(
			avatar_stack_height,
			tray_height,
		) +
		top_margin
	)

	gomoku_top_hud.custom_minimum_size = Vector2(
		0.0,
		top_hud_height,
	)

	gomoku_top_hud.set_anchors_preset(
		Control.PRESET_TOP_WIDE,
	)

	gomoku_top_hud.offset_left = side_margin
	gomoku_top_hud.offset_top = top_margin
	gomoku_top_hud.offset_right = -side_margin
	gomoku_top_hud.offset_bottom = (
		top_margin +
		top_hud_height
	)

	gomoku_bottom_controls_margin.add_theme_constant_override(
		"margin_left",
		roundi(side_margin),
	)

	gomoku_bottom_controls_margin.add_theme_constant_override(
		"margin_right",
		roundi(side_margin),
	)

	gomoku_bottom_controls_margin.add_theme_constant_override(
		"margin_bottom",
		roundi(bottom_margin),
	)

	var largest_action_height: float = maxf(
		GOMOKU_BASE_MENU_BUTTON_SIZE.y,
		GOMOKU_BASE_SEND_BUTTON_SIZE.y,
	) * avatar_scale

	var bottom_height: float = (
		largest_action_height +
			bottom_margin
	)

	gomoku_bottom_controls.custom_minimum_size = Vector2(
		0.0,
		bottom_height,
	)

	gomoku_bottom_controls.set_anchors_preset(
		Control.PRESET_BOTTOM_WIDE,
	)

	gomoku_bottom_controls.offset_left = 0.0
	gomoku_bottom_controls.offset_top = -bottom_height
	gomoku_bottom_controls.offset_right = 0.0
	gomoku_bottom_controls.offset_bottom = 0.0

	gomoku_top_hud.queue_sort()
	gomoku_bottom_controls.queue_sort()


func _restore_gomoku_portrait_layout() -> void:
	gomoku_top_hud.custom_minimum_size = Vector2(
		0.0,
		GOMOKU_BASE_TOP_HUD_HEIGHT,
	)

	gomoku_bottom_controls.custom_minimum_size = Vector2(
		0.0,
		GOMOKU_BASE_BOTTOM_HEIGHT,
	)

	PlayerBowl.custom_minimum_size = (
		_gomoku_base_player_bowl_size
	)

	OppBowl.custom_minimum_size = (
		_gomoku_base_opponent_bowl_size
	)

	gomoku_bottom_controls_margin.add_theme_constant_override(
		"margin_left",
		roundi(GOMOKU_BASE_SIDE_MARGIN),
	)

	gomoku_bottom_controls_margin.add_theme_constant_override(
		"margin_right",
		roundi(GOMOKU_BASE_SIDE_MARGIN),
	)

	gomoku_bottom_controls_margin.add_theme_constant_override(
		"margin_bottom",
		roundi(GOMOKU_BASE_BOTTOM_MARGIN),
	)

	_reset_gomoku_control_for_container(
		gomoku_top_hud,
	)

	_reset_gomoku_control_for_container(
		gomoku_board_center,
	)

	_reset_gomoku_control_for_container(
		gomoku_bottom_controls,
	)

	gomoku_main_vbox.queue_sort()
	gomoku_top_hud.queue_sort()
	gomoku_board_center.queue_sort()
	gomoku_bottom_controls.queue_sort()

func _apply_gomoku_spectator_label_layout(
	content_scale: float,
	is_portrait: bool,
) -> void:
	if not is_instance_valid(spec_label):
		return

	var overlay_scale := 1.0

	if not is_portrait:
		overlay_scale = clampf(
			content_scale,
			GOMOKU_LANDSCAPE_OVERLAY_MIN_SCALE,
			GOMOKU_LANDSCAPE_OVERLAY_MAX_SCALE,
		)

	var top_offset := (
		GOMOKU_PORTRAIT_SPECTATOR_TOP_OFFSET
		if is_portrait
		else 0.0
	)

	spec_label.set_anchors_preset(
		Control.PRESET_CENTER_TOP,
	)

	spec_label.offset_left = (
		-GOMOKU_BASE_SPECTATOR_HALF_WIDTH *
		overlay_scale
	)

	spec_label.offset_right = (
		GOMOKU_BASE_SPECTATOR_HALF_WIDTH *
		overlay_scale
	)

	spec_label.offset_top = top_offset

	spec_label.offset_bottom = (
		top_offset +
		GOMOKU_BASE_SPECTATOR_HEIGHT *
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
				GOMOKU_BASE_SPECTATOR_FONT_SIZE *
					overlay_scale
			),
			1,
		),
	)

func _apply_gomoku_responsive_layout() -> void:
	_gomoku_responsive_layout_pending = false

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
		_gomoku_last_viewport_size,
	):
		return

	_gomoku_last_viewport_size = viewport_size

	var is_portrait := (
		viewport_size.y >=
		viewport_size.x
	)
	
	_gomoku_is_portrait = is_portrait

	var action_scale_hint: float = (
		_gomoku_avatar_scale_hint(
			viewport_size,
			is_portrait,
		)
	)

	_set_gomoku_landscape_overlay_mode(
		not is_portrait,
	)

	var board_display_size := (
		_apply_gomoku_board_layout(
			viewport_size,
			is_portrait,
			action_scale_hint,
		)
	)

	var content_scale := clampf(
		board_display_size /
			GOMOKU_PORTRAIT_BOARD_SIZE,
		0.5,
		2.0,
	)

	_apply_gomoku_avatar_and_tray_layout(
		content_scale,
		is_portrait,
		viewport_size,
	)

	if is_portrait:
		_restore_gomoku_portrait_layout()
	else:
		_apply_gomoku_landscape_overlay_positions(
			_gomoku_current_avatar_scale,
		)

	_apply_gomoku_spectator_label_layout(
		content_scale,
		is_portrait,
	)

	_gomoku_layout_generation += 1

	call_deferred(
		"_finish_gomoku_responsive_layout",
		_gomoku_layout_generation,
	)

	gomoku_main_vbox.queue_sort()
	gomoku_board_center.queue_sort()

func _relayout_gomoku_board_tiles() -> void:
	if not is_instance_valid(_board_tiles_root):
		return

	if (
		_active_tile_tween and
		_active_tile_tween.is_running()
	):
		_active_tile_tween.kill()

	for child in _board_tiles_root.get_children():
		if not child is TextureRect:
			continue

		var tile := child as TextureRect

		if not tile.has_meta(
			GOMOKU_TILE_GRID_META,
		):
			continue

		var grid_value: Variant = tile.get_meta(
			GOMOKU_TILE_GRID_META,
		)

		if typeof(grid_value) != TYPE_VECTOR2I:
			continue

		var grid_position := grid_value as Vector2i

		if not _grid_in_bounds(grid_position):
			continue

		var stone_value := int(
			board_state[
				grid_position.y
			][
				grid_position.x
			]
		)

		if stone_value == 0:
			continue

		_prepare_tile_for_board(
			tile,
			stone_value == 2,
		)

		var center := _grid_to_pos(
			grid_position,
		)

		_set_tile_offsets(
			tile,
			center.x -
				_current_tile_px *
					0.5,
			center.y -
				_current_tile_px *
					0.5,
		)

		tile.scale = Vector2.ONE
		tile.z_index = BOARD_TILE_Z

	if is_instance_valid(_win_preview_node):
		_win_preview_node.radius_px = (
			_current_tile_px *
			0.3
		)

		_win_preview_node.queue_redraw()


func _relayout_gomoku_bowl_tiles() -> void:
	var bowls: Array[TextureRect] = [
		PlayerBowl,
		OppBowl,
	]

	for bowl in bowls:
		if not is_instance_valid(bowl):
			continue

		for child in bowl.get_children():
			if not child is TextureRect:
				continue

			var tile := child as TextureRect

			tile.custom_minimum_size = Vector2(
				_current_tile_px,
				_current_tile_px,
			)

			tile.size = Vector2(
				_current_tile_px,
				_current_tile_px,
			)

			tile.pivot_offset = (
				tile.size *
				0.5
			)

			tile.z_index = 50

			_place_random_in_bowl(
				bowl,
				tile,
			)


func _finish_gomoku_responsive_layout(
	layout_generation: int,
) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if (
		not is_inside_tree() or
		layout_generation !=
			_gomoku_layout_generation
	):
		return
	
	_layout_gomoku_action_ui(
		_gomoku_is_portrait,
	)

	_relayout_gomoku_board_tiles()
	_relayout_gomoku_bowl_tiles()

	player_avatar_display.pivot_offset = (
		player_avatar_display.size *
		0.5
	)

	opp_avatar_display.pivot_offset = (
		opp_avatar_display.size *
		0.5
	)

	_clear_gomoku_win_burst_proxies()

	if (
		is_instance_valid(win_loss_label) and
		win_loss_label.visible and
		is_instance_valid(
			_gomoku_active_win_burst_avatar
		)
	):
		_show_gomoku_win_burst(
			_gomoku_active_win_burst_avatar,
		)

func _update_win_preview_for_current_move() -> void:
	if _current_move.x < 0 or _current_move.y < 0:
		OpLog.d(LOG_TAG, "preview_clear no_current_move")
		_clear_win_preview()
		return

	var p: int = int(board_state[_current_move.y][_current_move.x])
	if p == 0:
		OpLog.d(LOG_TAG, ["preview_clear empty_current_move current_move=", _current_move])
		_clear_win_preview()
		return

	var coords := _get_line_through_cell(p, _current_move)

	OpLog.d(LOG_TAG, [
		"preview_check current_move=", _current_move,
		" p=", p,
		" line_size=", coords.size(),
		" coords=", coords
	])

	if coords.size() >= 5:
		_preview_win_line = coords
		OpLog.event(LOG_TAG, ["preview_win_line_found coords=", coords])
	else:
		_preview_win_line.clear()

	if is_instance_valid(_win_preview_node):
		_win_preview_node.coords = _preview_win_line
		_win_preview_node.queue_redraw()
		
class DropDust:
	extends Control

	var spots: Array = []

	func setup() -> void:
		size = Vector2(78, 34)
		pivot_offset = size * 0.5

		spots = [
			{"p": Vector2(15, 19), "r": 5.5, "a": 0.22},
			{"p": Vector2(25, 15), "r": 7.0, "a": 0.28},
			{"p": Vector2(37, 18), "r": 8.0, "a": 0.26},
			{"p": Vector2(50, 15), "r": 6.5, "a": 0.22},
			{"p": Vector2(62, 20), "r": 5.0, "a": 0.18},
			{"p": Vector2(32, 24), "r": 5.0, "a": 0.14},
			{"p": Vector2(48, 25), "r": 4.5, "a": 0.13}
		]

		queue_redraw()

	func _draw() -> void:
		for spot in spots:
			var p: Vector2 = spot["p"]
			var r: float = float(spot["r"])
			var a: float = float(spot["a"])

			draw_circle(
				p,
				r,
				Color(0.48, 0.39, 0.32, a)
			)

class WinLinePreview:
	extends Control

	var coords: Array = []
	var get_pos_for_grid: Callable = Callable()
	var radius_px: float = 20.0

	func _draw() -> void:
		if coords.is_empty() or not get_pos_for_grid.is_valid():
			return

		var pts: Array = []
		for g in coords:
			if g is Vector2i:
				pts.append(get_pos_for_grid.call(g))

		if pts.is_empty():
			return

		var outline_col := Color(1.0, 0.84, 0.0, 0.7)
		var line_width := 20.0

		for p in pts:
			draw_arc(p, radius_px, 0.0, TAU, 64, outline_col, line_width)
