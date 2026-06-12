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

const PLAYER1_BOWL_TEX := preload("res://gomoku/player1_bowl.png")
const PLAYER2_BOWL_TEX := preload("res://gomoku/player2_bowl.png")
const MUSIC_STREAM := preload("res://global/audio/gomoku.ogg")

const GRID_SQUARES := 12
var board_size := GRID_SQUARES + 1
@export var BOARD_MARGIN_PX := 32.0
@export var TILE_TEXTURE_PATH := "res://gomoku/gomoku_tile.png"
const TILE_PX := 40
const SNAP_PX := 10.0
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
		you_label.text = "" if spectator_mode else "You"

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

	if move_str != "":
		var parts: PackedStringArray = move_str.split(",", false)
		if parts.size() >= 3:
			var row := int(parts[0])
			var col := int(parts[1])
			var gg: Vector2i = _proto_to_grid(row, col, board_size)
			var mp: int = int(parts[2])

			if _grid_in_bounds(gg) and board_state[gg.y][gg.x] == 0:
				_place_stone_direct(gg, mp)
				board_state[gg.y][gg.x] = mp
				moves.append({"x": gg.x, "y": gg.y, "p": mp})
				_current_move = gg

				OpLog.event(LOG_TAG, [
					"incoming_move_applied proto_row=", row,
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

	if winner_payload != "":
		OpLog.event(LOG_TAG, ["winner_payload_received payload=", winner_payload])
		_apply_winner_payload(winner_payload, p1_id, p2_id)
		return

	game_ended = check_win()

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
	return Rect2(inner.position + Vector2(BOARD_MARGIN_PX, BOARD_MARGIN_PX),
				 inner.size - Vector2(2.0*BOARD_MARGIN_PX, 2.0*BOARD_MARGIN_PX))

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
	_win_preview_node.radius_px = TILE_PX * 0.3
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
	t.custom_minimum_size = Vector2(TILE_PX, TILE_PX)
	t.size = Vector2(TILE_PX, TILE_PX)
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
		final_center_pos.x - TILE_PX * 0.5,
		final_center_pos.y - TILE_PX * 0.5 - 18.0
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
			_active_tile.z_index = 75

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
			_active_tile.z_index = 75

		if lift_move:
			_haptic_explosion(0.32, 22)
		else:
			_haptic_explosion(0.22, 16)
	)

func _set_tile_offsets(t: TextureRect, left: float, top: float) -> void:
	t.offset_left = left; t.offset_top = top; t.offset_right = left + TILE_PX; t.offset_bottom = top + TILE_PX

func _prepare_tile_for_board(tile: TextureRect, is_black: bool) -> TextureRect:
	if tile == null: 
		tile = _make_tile(is_black)
	tile.texture = _tile_tex
	tile = tile
	return tile

func _place_random_in_bowl(bowl: Control, t: TextureRect) -> void:
	var sz := (bowl.size if bowl.size != Vector2.ZERO else bowl.get_rect().size)
	var pad := 25.0
	var x := _rng.randf_range(pad, max(pad, sz.x - TILE_PX - pad))
	var y := _rng.randf_range(pad, max(pad, sz.y - TILE_PX - pad))
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

	if _current_move == g:
		_has_uncommitted_move = true
		_show_send_button()
		_update_place_hint_visibility()
		_update_win_preview_for_current_move()

		if from_drag and is_instance_valid(_active_tile):
			var same_center := _grid_to_pos(g)
			var same_final_pos := Vector2(same_center.x - TILE_PX * 0.5, same_center.y - TILE_PX * 0.5)
			_drop_active_tile_to(same_final_pos)

		return

	if board_state[g.y][g.x] != 0:
		return

	var lift_move := _current_move.x >= 0 and _current_move.y >= 0 and is_instance_valid(_active_tile) and not from_drag

	if _current_move.x >= 0 and _current_move.y >= 0:
		board_state[_current_move.y][_current_move.x] = 0

	_ensure_active_tile()

	var p := (2 if player == 1 else 1)
	board_state[g.y][g.x] = p
	_current_move = g

	var c := _grid_to_pos(g)
	var final_pos := Vector2(c.x - TILE_PX * 0.5, c.y - TILE_PX * 0.5)

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

	_active_tile.reparent(PlayerBowl)
	_set_tile_offsets(_active_tile, _active_from_bowl_offset.x, _active_from_bowl_offset.y)
	_active_tile = null
	_current_move = Vector2i(-1, -1)
	_clear_win_preview()
	_update_place_hint_visibility()
	
func _finalize_active_tile() -> void:
	if _active_tile:
		_active_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_active_tile = null

func _place_stone_direct(g: Vector2i, p:int) -> void:
	if not _grid_in_bounds(g): 
		return
	board_state[g.y][g.x] = p
	var tile := _prepare_tile_for_board(null, p==2)
	_board_tiles_root.add_child(tile)
	var c := _grid_to_pos(g)
	_set_tile_offsets(tile, c.x - TILE_PX*0.5, c.y - TILE_PX*0.5)

func _input(e: InputEvent) -> void:
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

	var parent := send_button.get_parent() as Control
	if parent == null:
		return

	var existing := parent.get_node_or_null("PlaceHintLabel") as Label
	if existing:
		place_hint_label = existing
	else:
		place_hint_label = Label.new()
		place_hint_label.name = "PlaceHintLabel"
		parent.add_child(place_hint_label)

	place_hint_label.text = "Place a stone on an empty tile."
	place_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	place_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place_hint_label.add_theme_font_size_override("font_size", 22)
	place_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))

	var hint_size := send_button.size
	if hint_size.x <= 0.0:
		hint_size.x = 360.0
	if hint_size.y <= 0.0:
		hint_size.y = 50.0

	place_hint_label.size = hint_size
	place_hint_label.position = Vector2(send_button.position.x, _send_btn_shown_y)
	place_hint_label.visible = false


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
			if g == _current_move:
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
				GameUtils._show_win_burst(player_avatar_display)
		else:
			if is_instance_valid(opp_avatar_display):
				GameUtils._show_win_burst(opp_avatar_display)
	elif state == "1":
		win_loss_label.text = "YOU WIN!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

		if is_instance_valid(player_avatar_display):
			GameUtils._show_win_burst(player_avatar_display)
	else:
		win_loss_label.text = "YOU LOSE"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

		if is_instance_valid(opp_avatar_display):
			GameUtils._show_win_burst(opp_avatar_display)

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
	var p := 1 if player == 1 else 2

	var payload := {
		"map": _compose_lagged_map_string(),
		"move": "%d,%d,%d" % [send_row, send_col, p]
	}

	var avatar_key := "avatar1" if player == 1 else "avatar2"
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	game_ended = check_win()

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
