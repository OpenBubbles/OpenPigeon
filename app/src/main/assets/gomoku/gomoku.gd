extends Control
# Godot 4.x — concise, aligned, single-active-stone, send-on-button

# --- Scene references ---
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
@onready var send_button: Button = %SendButton   # unique

const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")
const RULES_POPUP_SCENE  = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")

# --- Identity / config ---
var my_id := ""
var my_player := 0           # 0 spectator, 1 black, 2 white
const GRID_SIZE := 12
@export var BOARD_MARGIN_PX := 40.0
@export var TILE_TEXTURE_PATH := "res://gomoku/gomoku_tile.png"
const TILE_PX := 32
const SNAP_PX := 10.0
const DEBUG_DRAG := false

# --- Game state ---
var is_my_turn := false
var game_id := ""
var board_size := GRID_SIZE
var board_state: Array = []          # 2D: board_state[y][x] = 0/1/2
var moves: Array = []                # history [{x,y,p}]
var game_ended := false
var game_over := false

# Active stone (the ONE you move this turn)
var _active_tile: TextureRect = null
var _active_from_bowl_offset := Vector2.ZERO
var _current_move := Vector2i(-1, -1)    # tentative grid pos for our turn
var _has_uncommitted_move := false

# Drag helpers (drag uses the active tile)
var _drag_snapped_grid := Vector2i(-1, -1)

# Runtime / misc
var _tile_tex: Texture2D
var _board_tiles_root: Control
var _rng := RandomNumberGenerator.new()
var appPlugin: Object = null
var has_connected := false
var sent_tween: Tween
var dot_count := 0
var spectator_mode := false
const BASE_WAIT_TEXT := "WAITING FOR OPPONENT"
var game_settings_category := ""
var _send_btn_shown_y := 0.0
var _send_btn_hidden_y := 0.0

func _log(s:String)->void: if DEBUG_DRAG: print(s)
func _dbg(s:String)->void: print("[GOMOKU] ", s)

# =============== READY ===============
func _ready() -> void:
	_rng.randomize()
	_tile_tex = load(TILE_TEXTURE_PATH)
	_make_runtime_nodes()
	_reset_board_arrays(GRID_SIZE)
	_connect_board_input()
	if is_instance_valid(rules_button):
		rules_button.pressed.connect(on_rules_button_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
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

	# Plugin wiring
	appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		if not has_connected:
			appPlugin.connect("set_game_data", Callable(self, "_set_game_data"))
			has_connected = true
			appPlugin.call("onReady")
	else:
		var dev := '{"isYourTurn": true,"size":"12","player":"2","map":"","move":"","id":"dev"}'
		await get_tree().process_frame
		_set_game_data(dev)

# =============== LAYOUT HELPERS (fix alignment) ===============
func _panel_inner_rect() -> Rect2:
	var r := Board.get_rect()
	var sb := Board.get_theme_stylebox("panel")
	if sb == null: return r
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

# =============== RUNTIME NODES / BOARD RESET ===============
func _make_runtime_nodes() -> void:
	var old := get_node_or_null("BoardTiles")
	if old: old.queue_free()
	_board_tiles_root = Control.new()
	_board_tiles_root.name = "BoardTiles"
	_board_tiles_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_tiles_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_tiles_root.z_as_relative = false
	_board_tiles_root.z_index = Board.z_index + 1
	Board.add_child(_board_tiles_root)

func _reset_board_arrays(dim:int) -> void:
	board_size = dim
	board_state.resize(board_size)
	for y in board_size:
		board_state[y] = []
		(board_state[y] as Array).resize(board_size)
		for x in board_size: board_state[y][x] = 0
	moves.clear()
	_current_move = Vector2i(-1,-1)
	_has_uncommitted_move = false

func _clear_board_visuals() -> void:
	for c in _board_tiles_root.get_children():
		c.queue_free()

# =============== TILES / BOWLS ===============
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
	t.z_index = 101
	t.modulate = (Color.BLACK if is_black else Color.WHITE)
	return t

func _set_tile_offsets(t: TextureRect, left: float, top: float) -> void:
	t.offset_left = left; t.offset_top = top; t.offset_right = left + TILE_PX; t.offset_bottom = top + TILE_PX

func _prepare_tile_for_board(tile: TextureRect, is_black: bool) -> TextureRect:
	if tile == null: tile = _make_tile(is_black)
	tile.texture = _tile_tex
	tile = tile
	return tile

func _place_random_in_bowl(bowl: Control, t: TextureRect) -> void:
	var sz := (bowl.size if bowl.size != Vector2.ZERO else bowl.get_rect().size)
	var pad := 8.0
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

func _top_up_bowl(bowl: Control, want: int, is_black: bool) -> void:
	var count := 0
	for c in bowl.get_children():
		if c is TextureRect: count += 1
	for _i in max(0, want - count):
		var t := _make_tile(is_black); bowl.add_child(t); _place_random_in_bowl(bowl, t)
	# (optional strict trim omitted intentionally)

func _top_up_bowls_show7() -> void:
	var our_is_black := (my_player == 1)
	_top_up_bowl(PlayerBowl, 7, our_is_black)
	_top_up_bowl(OppBowl,    7, not our_is_black)

# Ensure exactly one active tile (the movable stone)
func _ensure_active_tile() -> void:
	if _active_tile and is_instance_valid(_active_tile): return
	_active_tile = _pop_bowl_tile(true)
	if _active_tile == null: _active_tile = _make_tile(true)
	_active_from_bowl_offset = Vector2(_active_tile.offset_left, _active_tile.offset_top)
	_active_tile = _prepare_tile_for_board(_active_tile, true)
	_board_tiles_root.add_child(_active_tile)
	_active_tile.z_index = 101

# Move/replace tentative move; no extra stones created
func _place_or_move_active_to(g: Vector2i) -> void:
	if not _grid_in_bounds(g): return
	# Clear previous tentative cell
	if _current_move.x >= 0: board_state[_current_move.y][_current_move.x] = 0
	if board_state[g.y][g.x] != 0: return
	_ensure_active_tile()
	board_state[g.y][g.x] = 1
	_current_move = g
	var c := _grid_to_pos(g)
	_set_tile_offsets(_active_tile, c.x - TILE_PX*0.5, c.y - TILE_PX*0.5)
	_has_uncommitted_move = true
	_show_send_button()
	# replace last our move in history
	for i in range(moves.size()-1, -1, -1):
		var m := moves[i] as Dictionary
		if int(m.get("p",0)) == 1: moves.remove_at(i); break
	moves.append({"x": g.x, "y": g.y, "p": 1})

func _return_active_to_bowl() -> void:
	if _active_tile == null: return
	_active_tile.reparent(PlayerBowl)
	_set_tile_offsets(_active_tile, _active_from_bowl_offset.x, _active_from_bowl_offset.y)
	_active_tile = null

# Place a stone directly (for map rebuild / opponent moves)
func _place_stone_direct(g: Vector2i, p:int) -> void:
	if not _grid_in_bounds(g): return
	board_state[g.y][g.x] = p
	var tile := _prepare_tile_for_board(null, p==1)
	_board_tiles_root.add_child(tile)
	var c := _grid_to_pos(g)
	_set_tile_offsets(tile, c.x - TILE_PX*0.5, c.y - TILE_PX*0.5)

# =============== INPUT ===============
func _connect_board_input() -> void:
	if not Board.gui_input.is_connected(_on_board_gui_input):
		Board.gui_input.connect(_on_board_gui_input)

func _on_board_gui_input(e: InputEvent) -> void:
	if not is_my_turn: return
	# simple tap-to-place/move active stone
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		var g := _pos_to_grid(Board.get_local_mouse_position())
		_place_or_move_active_to(g)

func _unhandled_input(e: InputEvent) -> void:
	if not is_my_turn:
		return
	# Drag preview: as cursor moves near intersections, we relocate the active stone
	if (e is InputEventMouseMotion or e is InputEventScreenDrag) and _active_tile:
		var gp: Vector2 = (e as InputEventWithModifiers).position
		var local: Vector2 = Board.to_local(gp)
		var info: Dictionary = _nearest_grid_center(local)
		if float(info["dist"]) <= SNAP_PX:
			_place_or_move_active_to(info["g"])

# =============== SEND BUTTON (slide up/down) ===============

func _tween_send_button(show: bool) -> void:
	if not is_instance_valid(send_button):
		return
	if sent_tween:
		sent_tween.kill()

	# show/hide setup
	if show:
		send_button.visible = true
		send_button.modulate.a = 1.0

	var target := (_send_btn_shown_y if show else _send_btn_hidden_y)
	var dur := (0.25 if show else 0.20)
	var ease := (Tween.EASE_OUT if show else Tween.EASE_IN)

	sent_tween = create_tween()
	sent_tween.tween_property(send_button, "position:y", target, dur) \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(ease)

	if not show:
		sent_tween.tween_callback(func ():
			if is_instance_valid(send_button):
				send_button.visible = false
		)

func _show_send_button() -> void: _tween_send_button(true)
func _hide_send_button() -> void: _tween_send_button(false)

func _on_send_button_pressed() -> void:
	if not _has_uncommitted_move or _current_move.x < 0: return
	send_game()

# =============== DATA FLOW ===============
func _set_game_data(raw_text: String) -> void:
	var res: Variant = JSON.parse_string(raw_text)
	if typeof(res) != TYPE_DICTIONARY:
		print("[GOMOKU] Bad JSON for _set_game_data")
		return
	var d: Dictionary = res

	game_id = _get_first(d, "id", game_id)
	my_id   = _get_first(d, "myPlayerId", my_id)
	var p1_id: String = _get_first(d, "player1", "")
	var p2_id: String = _get_first(d, "player2", "")
	var sender_s: String = _get_first(d, "player", "1")
	var map_str: String = _get_first(d, "map", "")
	var move_str: String = _get_first(d, "move", "")
	var is_turn_s: String = _get_first(d, "isYourTurn", "")

	var sender_player: int = clampi(int(sender_s), 1, 2)
	# resolve my_player
	if p1_id != "" and p2_id != "":
		if my_id != "" and my_id == p1_id:
			my_player = 1
		elif my_id != "" and my_id == p2_id:
			my_player = 2
		else:
			my_player = 0
	else:
		my_player = (1 if sender_player == 2 and move_str == "" else (2 if sender_player == 1 and _is_all_zeros(map_str) else 1))

	is_my_turn = (is_turn_s == "true" or is_turn_s == "True" or is_turn_s == "1") if is_turn_s != "" else (my_player != 0 and my_player != sender_player)

	# dimension & rebuild
	var inferred_dim: int = (_infer_dim_from_map(map_str) if map_str.length() > 0 else board_size)
	_reset_board_arrays(clampi(inferred_dim, 4, 32))
	_clear_board_visuals()
	_make_runtime_nodes() # ensure root exists

	# rebuild from map (bottom-left origin)
	if map_str.length() > 0:
		var dim: int = _infer_dim_from_map(map_str)
		for i in map_str.length():
			var ch := String(map_str[i])
			if ch == "1" or ch == "2":
				var x := i % dim
				var y := i / dim
				_place_stone_direct(_map_to_grid(x, y, dim), int(ch))

	# single incoming move
	if move_str != "":
		var parts: PackedStringArray = move_str.split(",", false)
		if parts.size() >= 3:
			var gg: Vector2i = _map_to_grid(int(parts[0]), int(parts[1]), board_size)
			var mp: int = int(parts[2])
			if _grid_in_bounds(gg) and board_state[gg.y][gg.x] == 0:
				_place_stone_direct(gg, mp)
				board_state[gg.y][gg.x] = mp
				moves.append({"x": gg.x, "y": gg.y, "p": mp})

	_top_up_bowls_show7()
	if is_my_turn:
		stop_waiting_animation()
	else:
		start_waiting_animation()
	_hide_send_button()
	_return_active_to_bowl()
	
	_dbg("set_game_data id=%s me=%s my_player=%d sender=%d size=%d my_turn=%s map_len=%d move=%s"
		% [game_id, my_id, my_player, sender_player, board_size, str(is_my_turn), map_str.length(), move_str])

# =============== SENDING ===============
func _compose_current_map_string() -> String:
	var s := ""
	for y in range(board_size-1, -1, -1):
		for x in board_size: s += str(board_state[y][x])
	return s

func send_game() -> void:
	await get_tree().process_frame
	if _current_move.x < 0: print("[Send] No move."); return
	var payload := {
		"map": _compose_current_map_string(),
		"move": "%d,%d,%d" % [_current_move.x, _current_move.y, 1]
	}
	var plug := Engine.get_singleton("AppPlugin")
	if plug: plug.updateGameData(JSON.stringify(payload))
	else: print("AppPlugin is null; cannot send.")
	_has_uncommitted_move = false
	_hide_send_button()
	is_my_turn = false
	_return_active_to_bowl()
	_top_up_bowls_show7()

# =============== Misc UI (unchanged logic, compact) ===============
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
	if is_instance_valid(dot_timer): dot_timer.stop()
	if is_instance_valid(waiting_label): waiting_label.visible=false; waiting_label.modulate.a=1.0
	if is_instance_valid(waiting_blur): waiting_blur.visible=false; waiting_blur.modulate.a=1.0

func _on_dot_timer_timeout():
	if not is_instance_valid(waiting_label): return
	dot_count = (dot_count % 3) + 1
	waiting_label.text = BASE_WAIT_TEXT + ".".repeat(dot_count)

# =============== Small utils ===============
func _map_to_grid(x_map:int, y_map:int, dim:int) -> Vector2i: return Vector2i(x_map, (dim-1)-y_map)
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

			# --- Skin color (accept both) ---
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

func _on_theme_changed(new_theme_name: String) -> void:
	pass

func _load_game_specific_settings() -> void:
	var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	print("Loaded game-specific settings for ", game_settings_category, ": volume=", saved_volume, " debug=", show_debug_info)
