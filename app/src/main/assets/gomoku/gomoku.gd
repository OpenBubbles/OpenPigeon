extends Control

@onready var PlayerBowl: TextureRect = %PlayerBowl
@onready var OppBowl: TextureRect = %OppBowl
@onready var Board: PanelContainer = %Board
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var rules_button: Button = %RulesButton
@onready var settings_button: Button = %SettingsButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: Control = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var background: ColorRect = %Background
@onready var win_loss_label: Label = %WinLossLabel
@onready var you_label: Label = %YouLabel
@onready var spec_label: Label = %SpecLabel
@onready var send_button: Button = %SendButton

const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const RULES_POPUP_SCENE  = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")
const PLAYER1_BOWL_TEX := preload("res://gomoku/player1_bowl.png")
const PLAYER2_BOWL_TEX := preload("res://gomoku/player2_bowl.png")

var my_id := ""
var my_player := 0           # 0 spectator, 1 black, 2 white
const GRID_SQUARES := 12
var board_size := GRID_SQUARES + 1
@export var BOARD_MARGIN_PX := 32.0
@export var TILE_TEXTURE_PATH := "res://gomoku/gomoku_tile.png"
const TILE_PX := 40
const SNAP_PX := 10.0
var _is_dragging := false
var _press_global := Vector2.ZERO
const DRAG_THRESHOLD := 6.0
const DEBUG_DRAG := true

var is_my_turn = false
var game_id := ""
var board_state: Array = []          # 2D: board_state[y][x] = 0/1/2
var moves: Array = []                # history [{x,y,p}]
var game_ended := false
var win_loss_state = ""
var winner = null
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
var appPlugin: Object = null
var has_connected := false
var send_button_tween: Tween
var sent_label_tween: Tween
var dot_count := 0
var spectator_mode := false
const BASE_WAIT_TEXT := "WAITING FOR OPPONENT"
var game_settings_category := ""
var _send_btn_shown_y := 0.0
var _send_btn_hidden_y := 0.0

func _log(s:String)->void: 
	if DEBUG_DRAG: 
		print(s)
func _dbg(s:String)->void: 
	print("[GOMOKU] ", s)

func _ready() -> void:
	_rng.randomize()
	_tile_tex = load(TILE_TEXTURE_PATH)
	_make_runtime_nodes()
	_reset_board_arrays(GRID_SQUARES + 1)
	if is_instance_valid(rules_button):
		rules_button.pressed.connect(on_rules_button_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
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
		send_button.pressed.connect(_on_send_button_pressed)
		print("[SendButton] ready; visible=", send_button.visible, " a=", send_button.modulate.a)
	else:
		push_warning("No %SendButton in scene")

	appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		if not has_connected:
			appPlugin.connect("set_game_data", Callable(self, "_set_game_data"))
			has_connected = true
			appPlugin.call("onReady")
	else:
		var dev := '{"isYourTurn": true,"player":"2","map":"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000222200000000000000000000000000000000000000000000","move":"12,12,1","id":"dev"}'
		await get_tree().process_frame
		_set_game_data(dev)

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

	var dbg := GridDebug.new()
	dbg.name = "GridDebug"
	dbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dbg.z_as_relative = false
	dbg.z_index = 30
	dbg.get_centers = func() -> Array:
		var area := _grid_area_rect()
		var s := _steps()
		var pts: Array = []
		for y in board_size:
			for x in board_size:
				pts.append(Vector2(area.position.x + x*s.x, area.position.y + y*s.y))
		return pts
	Board.add_child(dbg)
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
		dbg.queue_redraw()
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
			bowl.remove_child(c)
			return c
	return null
	
func _clear_bowl(bowl: Control) -> void:
	for c in bowl.get_children():
		if c is TextureRect:
			bowl.remove_child(c)
			c.free()

func _top_up_bowl(bowl: Control) -> void:
	var count := 0
	var is_black := (bowl == PlayerBowl and my_player == 1) or (bowl == OppBowl and my_player == 2)
	for c in bowl.get_children():
		if c is TextureRect and not c.is_queued_for_deletion():
			count += 1
	for _i in max(0, 8 - count):
		var t := _make_tile(is_black)
		bowl.add_child(t)
		_place_random_in_bowl(bowl, t)

func _retint_bowl(bowl: Control, is_black: bool) -> void:
	for c in bowl.get_children():
		if c is TextureRect:
			(c as TextureRect).modulate = (Color(0.278, 0.278, 0.278, 1.0) if is_black else Color.WHITE)

func _ensure_active_tile() -> void:
	if _active_tile and is_instance_valid(_active_tile): return
	_active_tile = _pop_bowl_tile(true)
	if _active_tile == null: _active_tile = _make_tile(my_player == 1)
	_active_from_bowl_offset = Vector2(_active_tile.offset_left, _active_tile.offset_top)
	_active_tile = _prepare_tile_for_board(_active_tile, my_player == 1)
	_board_tiles_root.add_child(_active_tile)
	_active_tile.z_index = 75

func _place_or_move_active_to(g: Vector2i) -> void:
	if not _grid_in_bounds(g):
		return

	if _current_move.x >= 0:
		board_state[_current_move.y][_current_move.x] = 0

	if board_state[g.y][g.x] != 0:
		return

	_ensure_active_tile()

	var p := (2 if my_player == 1 else 1)
	board_state[g.y][g.x] = p
	_current_move = g

	var c := _grid_to_pos(g)
	_set_tile_offsets(_active_tile, c.x - TILE_PX * 0.5, c.y - TILE_PX * 0.5)

	_has_uncommitted_move = true
	_show_send_button()

	print("[MOVE] Placing stone p=", p, " at ", g, " my_player=", my_player)
	print("[MOVE] Board updated; calling _update_win_preview_for_current_move()")
	_update_win_preview_for_current_move()

	for i in range(moves.size() - 1, -1, -1):
		var m := moves[i] as Dictionary
		if int(m.get("p", 0)) == p:
			moves.remove_at(i)
			break

	moves.append({"x": g.x, "y": g.y, "p": p})
	print("[MOVE] Moves history now: ", moves)

func _return_active_to_bowl() -> void:
	if _active_tile == null:
		return
	_active_tile.reparent(PlayerBowl)
	_set_tile_offsets(_active_tile, _active_from_bowl_offset.x, _active_from_bowl_offset.y)
	_active_tile = null
	_current_move = Vector2i(-1, -1)
	_clear_win_preview()
	
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
	if not is_my_turn or _ui_gesture_block:
		return

	# -------- PRESS: mouse OR touch --------
	if (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (e as InputEventMouseButton).pressed) \
	or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed):
		var gp := _event_pos(e)
		if gp == Vector2.INF:
			return
		if _is_over_blocking_ui(gp):
			_ui_gesture_block = true
			_is_dragging = false
			return
		else:
			_ui_gesture_block = false

		_press_global = gp
		_is_dragging = true
		_ensure_active_tile()

		var br: Rect2 = Board.get_global_rect()
		if br.has_point(gp):
			var local_board := _board_local_from_global(gp)
			var info := _nearest_grid_center(local_board)
			var c_board: Vector2 = info["pos"]
			_set_tile_offsets(_active_tile, c_board.x - TILE_PX * 0.5, c_board.y - TILE_PX * 0.5)
			_drag_snapped_grid = info["g"]
		else:
			var in_root := _root_local_from_global(gp)
			_set_tile_offsets(_active_tile, in_root.x - TILE_PX * 0.5, in_root.y - TILE_PX * 0.5)
			_drag_snapped_grid = Vector2i(-1, -1)

	# -------- MOVE: mouse OR touch drag --------
	elif _is_dragging and _active_tile and (e is InputEventMouseMotion or e is InputEventScreenDrag):
		if _ui_gesture_block:
			return

		var gp := _event_pos(e)
		if gp == Vector2.INF:
			return
		var br: Rect2 = Board.get_global_rect()

		if br.has_point(gp):
			var local_board := _board_local_from_global(gp)
			var info := _nearest_grid_center(local_board)
			var c_board: Vector2 = info["pos"]
			_set_tile_offsets(_active_tile, c_board.x - TILE_PX * 0.5, c_board.y - TILE_PX * 0.5)
			_drag_snapped_grid = info["g"]
		else:
			var in_root := _root_local_from_global(gp)
			_set_tile_offsets(_active_tile, in_root.x - TILE_PX * 0.5, in_root.y - TILE_PX * 0.5)
			_drag_snapped_grid = Vector2i(-1, -1)

	# -------- RELEASE: mouse OR touch --------
	elif (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (e as InputEventMouseButton).pressed and _is_dragging) \
	or (e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed and _is_dragging):
		if _ui_gesture_block:
			_ui_gesture_block = false
			_is_dragging = false
			return

		_is_dragging = false

		var gp := _event_pos(e)
		if gp == Vector2.INF:
			gp = _press_global
		var br: Rect2 = Board.get_global_rect()

		if not br.has_point(gp):
			_return_active_to_bowl()
			_hide_send_button()
			_has_uncommitted_move = false
			_clear_win_preview()
			_drag_snapped_grid = Vector2i(-1, -1)
			return


		var local_board := _board_local_from_global(gp)
		var info := _nearest_grid_center(local_board)
		var g: Vector2i = info["g"]

		if not _grid_in_bounds(g):
			_return_active_to_bowl()
			_hide_send_button()
			_has_uncommitted_move = false
			_clear_win_preview()
			_drag_snapped_grid = Vector2i(-1, -1)
			return


		if _current_move == g:
			_has_uncommitted_move = true
			_show_send_button()
			_update_win_preview_for_current_move()
			_drag_snapped_grid = Vector2i(-1, -1)
			return


		if board_state[g.y][g.x] == 0:
			_place_or_move_active_to(g)
		else:
			_return_active_to_bowl()
			_hide_send_button()
			_has_uncommitted_move = false
			_clear_win_preview()


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

func _show_send_button() -> void: _tween_send_button(true)
func _hide_send_button() -> void: _tween_send_button(false)

func _on_send_button_pressed() -> void:
	if not _has_uncommitted_move or _current_move.x < 0: return
	_ui_gesture_block = true
	send_game()
	
func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		print("Warning: sent_label is not valid for play_sent_animation.")
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
			start_waiting_animation()
	)
	
func _apply_bowl_skins() -> void:
	if not (is_instance_valid(PlayerBowl) and is_instance_valid(OppBowl)):
		return
	match my_player:
		1:
			PlayerBowl.texture = PLAYER1_BOWL_TEX
			OppBowl.texture    = PLAYER2_BOWL_TEX
		2:
			PlayerBowl.texture = PLAYER2_BOWL_TEX
			OppBowl.texture    = PLAYER1_BOWL_TEX
		_:
			PlayerBowl.texture = PLAYER1_BOWL_TEX
			OppBowl.texture    = PLAYER2_BOWL_TEX

func _set_game_data(raw_text: String) -> void:
	var res: Variant = JSON.parse_string(raw_text)
	if typeof(res) != TYPE_DICTIONARY:
		print("[GOMOKU] Bad JSON for _set_game_data")
		return
	var d: Dictionary = res
	print("INCOMING DATA: ", res)

	game_id = _get_first(d, "id", game_id)
	my_id   = _get_first(d, "myPlayerId", my_id)
	var p1_id: String = _get_first(d, "player1", "")
	var p2_id: String = _get_first(d, "player2", "")
	var sender_s: String = _get_first(d, "player", "1")
	var map_str: String = _get_first(d, "map", "")
	var move_str: String = _get_first(d, "move", "")
	var is_your_turn = bool(res.get("isYourTurn", false))
	is_my_turn = is_your_turn
	var opponent_avatar_key = ""
	winner = _get_first(d, "winner", "")
	stop_waiting_animation()
	var sender_player: int = clampi(int(sender_s), 1, 2)
	if p1_id != "" and p2_id != "":
		if my_id != "" and my_id == p1_id:
			my_player = 1
			print("SETTING FOR ID PLAYER 1")
		elif my_id != "" and my_id == p2_id:
			my_player = 2
			print("SETTING FOR ID PLAYER 2")
		else:
			my_player = 0
			print("SETTING FOR ID PLAYER 0")
			spectator_mode = true
			
	else:
		print("IS MY TURN?: ", is_my_turn, " | SENDER PLAYER: ", sender_player)
		my_player = (1 if ((sender_player == 2 and is_my_turn) or (sender_player == 1 and not is_my_turn)) else 2)
		print("ELSE SETTING FOR PLAYER: ", my_player)
	if spectator_mode:
		is_my_turn = false
		print("SPECTATOR MODE ACTIVE")
		you_label.text = ""
		spec_label.show()
	if my_player == 1:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"
		
	if opponent_avatar_key != "" and res.has(opponent_avatar_key):
		var avatar_string = res[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	
	_apply_bowl_skins()
	_clear_bowl(PlayerBowl)
	_clear_bowl(OppBowl)
	_top_up_bowl(PlayerBowl)
	_top_up_bowl(OppBowl)

	var inferred_dim: int = (_infer_dim_from_map(map_str) if map_str.length() > 0 else board_size)
	_reset_board_arrays(clampi(inferred_dim, 4, 32))
	_clear_board_visuals()
	_make_runtime_nodes()

	if map_str.length() > 0:
		var dim: int = _infer_dim_from_map(map_str)
		for i in map_str.length():
			var ch := String(map_str[i])
			if ch == "1" or ch == "2":
				var col := i % dim
				@warning_ignore("integer_division")
				var row := i / dim
				var g := _proto_to_grid(row, col, dim)
				_place_stone_direct(g, int(ch))


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


	print("Winner: ", winner)
	if winner != "":
		game_over = true
	game_ended = await check_win()
	if game_ended:
		stop_waiting_animation()
		print("GAME OVER")
		is_my_turn = false
	print("IS MY TURN?: ", is_my_turn, " | GAME OVER?: ", game_over, " | PLAYER NUM?: ", my_player)
	if not is_my_turn and not game_over:
		start_waiting_animation()
	else:
		stop_waiting_animation()
	_hide_send_button()
	if _has_uncommitted_move:
		_return_active_to_bowl()
	else:
		_finalize_active_tile()
		
	_ui_gesture_block = false
	_is_dragging = false
	
	_dbg("set_game_data id=%s me=%s my_player=%d sender=%d size=%d my_turn=%s map_len=%d move=%s"
		% [game_id, my_id, my_player, sender_player, board_size, str(is_my_turn), map_str.length(), move_str])

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
					print("Found 5+ run for player ", p, " -> ", coords)
					return coords

	return []

func check_win() -> bool:
	print("--- CHECKING WIN CONDITION (5+ in-a-row) ---")
	print("[WIN] my_player=", my_player, " current_move=", _current_move)

	var p1_coords: Array = []
	var p2_coords: Array = []

	if _current_move.x >= 0 and _current_move.y >= 0:
		var cur_p: int = int(board_state[_current_move.y][_current_move.x])
		print("[WIN] Current cell value=", cur_p)
		if cur_p == 1:
			p1_coords = _get_line_through_cell(2, _current_move)
			print("[WIN] Line through current move for P1: ", p1_coords)
		elif cur_p == 2:
			p2_coords = _get_line_through_cell(1, _current_move)
			print("[WIN] Line through current move for P2: ", p2_coords)

	if p1_coords.is_empty() and p2_coords.is_empty():
		print("[WIN] No line found through current move; doing full-board scan.")
		p1_coords = _find_five_or_more(2)
		p2_coords = _find_five_or_more(1)
	else:
		print("[WIN] Skipping full scan; already have line via current move.")

	var p1_has: bool = p1_coords.size() >= 5
	var p2_has: bool = p2_coords.size() >= 5

	print("[WIN] p1_has=", p1_has, " p2_has=", p2_has)

	if not p1_has and not p2_has:
		print("[WIN] RESULT: Game continues. No 5+ in-a-row found.")
		last_win_coords = []
		return false

	if p1_has and not p2_has:
		winner = "1"
		last_win_coords = p1_coords
		print("[WIN] P1 5+ coords: ", p1_coords)
	elif p2_has and not p1_has:
		winner = "-1"
		last_win_coords = p2_coords
		print("[WIN] P2 5+ coords: ", p2_coords)
	else:
		winner = "0"
		last_win_coords = []
		print("[WIN] Both players appear to have 5+; marking as draw.")

	game_over = true

	if is_instance_valid(_win_preview_node):
		_win_preview_node.coords = last_win_coords
		_win_preview_node.queue_redraw()
		print("[WIN] Win overlay coords set to: ", last_win_coords)

	if winner != "":
		if winner == "0":
			print("[WIN] FINAL TALLY: DRAW!")
			win_loss_label.text = "DRAW!"
			win_loss_state = "0"
			win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
		else:
			var you_win: bool = (not spectator_mode) and (
				(my_player == 1 and winner == "1") or
				(my_player == 2 and winner == "-1")
			)
			print("[WIN] you_win=", you_win, " spectator_mode=", spectator_mode)

			if you_win:
				print("[WIN] FINAL TALLY: YOU WIN! coords=", last_win_coords)
				_show_win_burst(player_avatar_display)
				win_loss_label.text = "YOU WIN!"
				win_loss_state = "1"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			else:
				if spectator_mode:
					print("[WIN] FINAL TALLY: Player %s Wins! coords=%s" % [winner, str(last_win_coords)])
					_show_win_burst(player_avatar_display if winner == "1" else opp_avatar_display)
					win_loss_label.text = "Player %s Wins!" % winner
					win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
					win_loss_state = "-1"
				else:
					print("[WIN] FINAL TALLY: YOU LOSE. coords=", last_win_coords)
					_show_win_burst(opp_avatar_display)
					win_loss_label.text = "YOU LOSE"
					win_loss_state = "-1"
					win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

		win_loss_label.visible = true
		await get_tree().process_frame
		win_loss_label.scale = Vector2.ZERO
		win_loss_label.pivot_offset = win_loss_label.size / 2
		var tween_in := create_tween()
		tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		return true
	return false


func send_game() -> void:
	await get_tree().process_frame
	if _current_move.x < 0:
		print("[Send] No move.")
		return

	var proto := _grid_to_proto(_current_move, board_size)
	var send_row := proto.x
	var send_col := proto.y
	var p := 1 if my_player == 1 else 2

	var payload := {
		"map": _compose_lagged_map_string(),
		"move": "%d,%d,%d" % [send_row, send_col, p]
	}
	var avatar_key := ("avatar1" if my_player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	game_ended = await check_win()
	if game_ended and win_loss_state != "":
		payload["winner"] = my_id + "|" + win_loss_state

	var plug := Engine.get_singleton("AppPlugin")
	if plug:
		plug.updateGameData(JSON.stringify(payload))
	else:
		print("AppPlugin is null; cannot send.")
	print("OUTGOING DATA", payload)

	_has_uncommitted_move = false
	_hide_send_button()
	is_my_turn = false
	_finalize_active_tile()

	if not game_ended:
		print("[SEND] No win detected; clearing preview.")
		_clear_win_preview()
	else:
		print("[SEND] Game ended with winner=", winner, " win_loss_state=", win_loss_state, " — keeping preview line.")

	_top_up_bowl(PlayerBowl)
	_top_up_bowl(OppBowl)

	if not game_over:
		play_sent_animation()


func start_waiting_animation():
	if spectator_mode or not (is_instance_valid(waiting_label) and is_instance_valid(waiting_blur) and is_instance_valid(dot_timer)): return
	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true; waiting_blur.visible = true
	waiting_label.modulate.a = 0.0; waiting_blur.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(waiting_label,"modulate:a",1.0,0.3)
	tw.tween_property(waiting_blur,"modulate:a",1.0,0.3)
	tw.tween_callback(func(): dot_timer.start())

func stop_waiting_animation():
	if is_instance_valid(dot_timer): 
		dot_timer.stop()
	if is_instance_valid(waiting_label): 
		waiting_label.visible=false
		waiting_label.modulate.a=1.0
	if is_instance_valid(waiting_blur): 
		waiting_blur.visible=false
		waiting_blur.modulate.a=1.0

func _on_dot_timer_timeout():
	if not is_instance_valid(waiting_label): return
	dot_count = (dot_count % 3) + 1
	waiting_label.text = BASE_WAIT_TEXT + ".".repeat(dot_count)

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
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
		_ui_gesture_block = false
	)
	settings_popup_script.settings_theme_selected.connect(_on_theme_changed)
	settings_popup_script.dark_mode_changed.connect(_apply_bg_for_dark)

	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await get_tree().process_frame

	var viewport_size := get_viewport_rect().size
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
	
func on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return

	rules_button.pivot_offset = rules_button.size / 2.0
	var tween := create_tween()
	tween.tween_property(rules_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(rules_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var popup := RULES_POPUP_SCENE.instantiate()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)
 
	var close_btn := popup.find_child("CloseButton", true, false)
	if close_btn:
		close_btn.pressed.connect(func():
			dim.queue_free()
			popup.queue_free()
			_ui_gesture_block = false
		)

	var title_label := popup.find_child("Title", true, false) as Label
	if title_label:
		title_label.text = "How to Play Gomoku"

	var rules_label := popup.find_child("RulesLabel", true, false) as RichTextLabel
	if rules_label:
		rules_label.bbcode_enabled = true
		rules_label.visible = true
		rules_label.fit_content = true
		rules_label.scroll_active = false
		rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rules_label.text = _get_rules_text()

	popup.set_as_top_level(true)
	popup.visible = true
	await get_tree().process_frame

	var viewport_size := get_viewport_rect().size
	var desired_width := viewport_size.x * 0.9
	var desired_height: float = popup.get_combined_minimum_size().y
	popup.size = Vector2(desired_width, desired_height)
	popup.set_pivot_offset(popup.size / 2)
	popup.position = (viewport_size / 2) - (popup.size / 2)
	popup.scale = Vector2.ZERO

	var popup_tween := create_tween()
	popup_tween.tween_property(popup, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	popup.grab_focus()
	
func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		print("Is Dark: ", is_dark)
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

@warning_ignore("unused_parameter")
func _on_theme_changed(new_theme_name: String) -> void:
	pass

func _load_game_specific_settings() -> void:
	var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	print("Loaded game-specific settings for ", game_settings_category, ": volume=", saved_volume, " debug=", show_debug_info)

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
		print("[PREVIEW] No current move; clearing preview.")
		_clear_win_preview()
		return

	var p: int = int(board_state[_current_move.y][_current_move.x])
	if p == 0:
		print("[PREVIEW] Current move cell is empty; clearing preview.")
		_clear_win_preview()
		return

	print("[PREVIEW] Checking current_move=", _current_move, " value=", p)

	var coords := _get_line_through_cell(p, _current_move)
	print("[PREVIEW] Line through cell: ", coords, " size=", coords.size())

	if coords.size() >= 5:
		print("[PREVIEW] Found 5+ in line; showing golden outline.")
		_preview_win_line = coords
	else:
		print("[PREVIEW] Less than 5 stones in line; clearing preview.")
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
