extends Control
class_name CheckersBoardTop

@export var board_origin: Vector2 = Vector2(0, 0)
@export var cell_px: int = 80

@onready var player_avatar_display: Control = %PlayerAvatarDisplay
@onready var opp_avatar_display: Control = %OppAvatarDisplay
@onready var rules_button: Button = %RulesButton
@onready var settings_button: Button = %SettingsButton
@onready var send_button: Button = %SendButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: Control = %WaitBlur
@onready var win_loss_label: Label = %WinLossLabel
@onready var dot_timer: Timer = %DotTimer
@onready var player_piece_icon: TextureRect = %PlayerPiece
@onready var opp_piece_icon: TextureRect = %OppPiece
@onready var you_label: Label = %YouLabel
@onready var background = %Background
@onready var spec_label: Label = %SpecLabel
@onready var board: TextureRect = %CheckersBoardTop
var appPlugin: Node = null
var mediaPlugin = null

var sent_tween: Tween
var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"

const RULES_POPUP_SCENE := preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE := preload("res://global/settings_popup.tscn")
const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")

var black_king_texture := preload("res://checkers/checker_black_king.png")
var red_king_texture := preload("res://checkers/checker_red_king.png")
var black_normal_texture := preload("res://checkers/checker_black.png")
var red_normal_texture := preload("res://checkers/checker_red.png")
const MUSIC_STREAM := preload("res://global/audio/checkers.ogg")

var ui_piece_textures := {
	"red": preload("res://checkers/checker_red.png"),
	"black": preload("res://checkers/checker_black.png")
}

var replay: String = ""
var pieces_root: Node2D
var highlights: Array[Node] = []
var move_highlights: Dictionary[Vector2i, Sprite2D] = {}
var temp_start_pos: Vector2i = Vector2i(-1, -1)
var selected_highlight: Sprite2D
var clicked_piece: Sprite2D
var moves: Dictionary[Vector2, Sprite2D] = {}
var has_moved: bool = false
var prev_moves: Array[Vector2] = []
var prev_jumps: Array[Sprite2D] = []
var _replay_tweens: Array[Tween] = []
var chain_jump_piece: Sprite2D = null
var checking_for_jumps: bool = false
var must_jump: bool = false
var rule_mandatory_jumps: bool = true
var jumping_pieces: Array[Sprite2D] = []
var game_over: bool = false
var has_connected: bool = false
var mode: String = "n"
var input_locked: bool = false
var replay_locked: bool = false
var isTurn: bool = false
var waitingForOpponent: bool = false
var spectator_mode: bool = false
var player: int = 0
var turn_owner: int = 1
var my_player: String = ""
var suppress_next_click: bool = false

@export_range(0.3, 1.0, 0.01) var piece_fill: float = 0.78
@export var board_inset: int = 0
	
func _tween_for(target: Object) -> Tween:
	var tw := get_tree().create_tween()
	if is_instance_valid(target):
		tw.bind_node(target)
	return tw
			
func _await_all_tweens(arr: Array[Tween]) -> void:
	for t in arr:
		if t and t.is_running():
			await t.finished
			
func _get_piece_pos(piece: Sprite2D) -> Vector2i:
	if piece == null or not is_instance_valid(piece):
		return Vector2i(-1, -1)
	var parts = piece.name.split(",")
	if parts.size() == 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(-1, -1)

func _select_piece(piece: Sprite2D) -> void:
	if piece == null or not is_instance_valid(piece):
		return

	if not check_player(piece):
		return

	if chain_jump_piece != null and piece != chain_jump_piece:
		return

	clear_highlights()
	clicked_piece = piece
	moves.clear()

	var p_pos := _get_piece_pos(piece)
	if p_pos == Vector2i(-1, -1):
		clicked_piece = null
		return

	_show_selected_highlight_at(p_pos.x, p_pos.y)

	var force_jumps_only: bool = (chain_jump_piece != null)
	gen_moves(force_jumps_only)

	if moves.size() == 0:
		clicked_piece = null
		_clear_selected_highlight()
		
func _apply_board_orientation() -> void:
	if not is_instance_valid(board):
		return
	if board.size == Vector2.ZERO:
		call_deferred("_apply_board_orientation")
		return
	board.pivot_offset = board.size / 2.0
	board.rotation_degrees = 0.0 
	
func _can_accept_board_input() -> bool:
	return (
		not input_locked
		and not replay_locked
		and not spectator_mode
		and not waitingForOpponent
		and isTurn
		and not game_over
	)

func _apply_piece_scale(s: Sprite2D) -> void:
	if s.texture == null:
		return
	var tex_size: Vector2i = s.texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	var target_px: float = float(cell_px) * piece_fill
	var sx: float = target_px / float(tex_size.x)
	var sy: float = target_px / float(tex_size.y)
	var scale_factor: float = minf(sx, sy)
	s.scale = Vector2(scale_factor, scale_factor)
	s.centered = true

func _view_y(y: int) -> int:
	return (7 - y) if (player == 2 and not spectator_mode) else y

func _cell_pos(lx: int, ly: int) -> Vector2:
	var gx := lx if (player == 2 and not spectator_mode) else (7 - lx)
	var gy := (7 - ly) if (player == 2 and not spectator_mode) else ly
	return board_origin + Vector2((gx + 0.5) * float(cell_px), (gy + 0.5) * float(cell_px))


func _apply_player_piece_icons() -> void:
	if not is_instance_valid(player_piece_icon) or not is_instance_valid(opp_piece_icon):
		return
	var my_color: String = "red" if player == 1 else "black"
	var opp_color: String = "black" if player == 1 else "red"
	player_piece_icon.texture = ui_piece_textures.get(my_color, null)
	opp_piece_icon.texture = ui_piece_textures.get(opp_color, null)
	if is_instance_valid(you_label):
		you_label.text = "You"
		you_label.modulate.a = 1.0 if not spectator_mode else 0.0

func _get_nth_board_str(src: String, n: int) -> String:
	var i := 0
	for elem in src.split("|"):
		var p := elem.split(":")
		if p.size() >= 2 and p[0] == "board":
			if i == n:
				return p[1]
			i += 1
	return ""

func _current_board_string() -> String:
	var board: Array[String] = []
	board.resize(64)
	for k in range(64):
		board[k] = "0"

	for ly in range(8):
		for lx in range(8):
			var piece := get_node_or_null("PiecesRoot/%d,%d" % [lx, ly]) as Sprite2D
			if piece != null:
				var color := get_piece_color(piece)
				var v := "0"
				if color == "red":
					v = "3" if is_checker_king(piece) else "1"
				elif color == "black":
					v = "4" if is_checker_king(piece) else "2"
				var A := _logical_to_abs(lx, ly)
				var idx := A.y * 8 + A.x
				if idx >= 0 and idx < 64:
					board[idx] = v

	return ",".join(board)

func _on_send_pressed() -> void:
	if input_locked:
		return
	if not has_moved or prev_moves.size() < 2:
		return
	var red_left := false
	var black_left := false
	for y in range(8):
		for x in range(8):
			var piece := get_node_or_null("PiecesRoot/%d,%d" % [x, y]) as Sprite2D
			if piece == null:
				continue
			var col := get_piece_color(piece)
			if col == "red":
				red_left = true
			elif col == "black":
				black_left = true
	var game_is_over_pre := (red_left and not black_left) or (black_left and not red_left)

	isTurn = false
	_animate_send_button(false)
	call_deferred("send_game_checkers")

func send_game_checkers() -> void:
	if prev_moves.size() < 2:
		return

	var steps: Array = []	# each = { "kind": "move"/"attack", "A1": Vector2i, "A2": Vector2i }
	for i in range(0, prev_moves.size(), 2):
		var p1: Vector2 = prev_moves[i]
		var p2: Vector2 = prev_moves[i + 1]
		var A1: Vector2i = _logical_to_abs(int(p1.x), int(p1.y))
		var A2: Vector2i = _logical_to_abs(int(p2.x), int(p2.y))
		var kind: String = ("attack" if abs(int(p1.x - p2.x)) > 1 else "move")
		steps.append({ "kind": kind, "A1": A1, "A2": A2 })

	var pre_board_str: String = _get_nth_board_str(replay, 1)
	if pre_board_str == "":
		pre_board_str = _get_nth_board_str(replay, 0)

	for y in range(8):
		for x in range(8):
			var piece := get_node_or_null("PiecesRoot/%d,%d" % [x, y]) as Sprite2D
			if piece == null:
				continue
			var col := get_piece_color(piece)
			if col == "unknown" or is_checker_king(piece):
				continue
			if (col == "red" and y == 0):
				set_checker_king(piece, "red")
			elif (col == "black" and y == 7):
				set_checker_king(piece, "black")

	var post_board_str: String = _current_board_string()

	var red_left := false
	var black_left := false
	for yy in range(8):
		for xx in range(8):
			var pc := get_node_or_null("PiecesRoot/%d,%d" % [xx, yy]) as Sprite2D
			if pc == null:
				continue
			var c := get_piece_color(pc)
			if c == "red":
				red_left = true
			elif c == "black":
				black_left = true
	var game_is_over := (red_left and not black_left) or (black_left and not red_left)

	var parts: Array[String] = []
	if pre_board_str != "":
		parts.append("board:" + pre_board_str)

	for s in steps:
		var a1: Vector2i = s["A1"]
		var a2: Vector2i = s["A2"]
		parts.append("%s:%d,%d,%d,%d" % [String(s["kind"]), a1.x, a1.y, a2.x, a2.y])

	parts.append("board:" + post_board_str)

	var new_replay := String("|").join(parts)
	var payload: Dictionary = { "replay": new_replay }
	var avatar_key := ("avatar1" if player == 1 else "avatar2")

	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	var wl := check_win_loss()
	if wl != "":
		payload["winner"] = my_player + "|" + ("1" if wl == "win" else "-1")

	if appPlugin:
		appPlugin.updateGameData(JSON.stringify(payload))
	else:
		print("AppPlugin is null. Cannot send game data.")

	if game_is_over or wl != "":
		game_over = true
		stop_waiting_animation()
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0
		clear_highlights()
		clicked_piece = null
		has_moved = false
		moves.clear()
		chain_jump_piece = null
		prev_jumps.clear()
		prev_moves.clear()
		return

	play_sent_animation()
	clear_highlights()
	clicked_piece = null
	has_moved = false
	moves.clear()
	chain_jump_piece = null
	prev_jumps.clear()
	prev_moves.clear()
		
func _on_board_resized() -> void:
	_recalculate_board_layout_from_board()
	_apply_board_orientation()
	if selected_highlight and selected_highlight.visible and clicked_piece:
		var p := getPiecePos(clicked_piece)
		_show_selected_highlight_at(int(p.x), int(p.y))

func _spawn_piece(val: String, lx: int, ly: int) -> Sprite2D:
	var s := Sprite2D.new()
	var color: String = ""
	var is_king: bool = false
	
	match val:
		"1":
			color = "red"
			is_king = false
		"2":
			color = "black"
			is_king = false
		"3":
			color = "red"
			is_king = true
		"4":
			color = "black"
			is_king = true
		_:
			s.queue_free()
			return null

	if color == "red":
		s.texture = red_king_texture if is_king else red_normal_texture
	else:
		s.texture = black_king_texture if is_king else black_normal_texture

	_apply_piece_scale(s)
	s.position = _cell_pos(lx, ly)
	s.name = "%d,%d" % [lx, ly]
	s.z_as_relative = false
	s.z_index = 2
	s.visible = true
	pieces_root.add_child(s)
	return s

func _recalculate_board_layout_from_board() -> void:
	if board == null:
		return
	var draw: Rect2 = _get_board_draw_rect()
	var draw_pos: Vector2 = draw.position
	var draw_size: Vector2 = draw.size
	var square_side: float = min(draw_size.x, draw_size.y) - float(board_inset) * 2.0
	var px: int = int(floor(square_side / 8.0))
	px = max(px, 1)
	cell_px = px
	var total_grid_px: Vector2 = Vector2(px * 8, px * 8)
	board_origin = draw_pos \
		+ Vector2((draw_size.x - total_grid_px.x) * 0.5, (draw_size.y - total_grid_px.y) * 0.5) \
		+ Vector2(board_inset, board_inset)

func _prepare_scene_once() -> void:
	_recalculate_board_layout_from_board()
	if is_instance_valid(board):
		if not board.is_connected("resized", Callable(self, "_on_board_resized")):
			board.resized.connect(_on_board_resized)
	if pieces_root == null:
		pieces_root = Node2D.new()
		pieces_root.name = "PiecesRoot"
		add_child(pieces_root)

func _clear_pieces() -> void:
	if pieces_root:
		for c in pieces_root.get_children():
			c.queue_free()
	highlights.clear()
	prev_moves.clear()
	prev_jumps.clear()
	clicked_piece = null
	has_moved = false
	chain_jump_piece = null

func _ready() -> void:
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)
	if is_instance_valid(board):
		board.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		board.mouse_filter = Control.MOUSE_FILTER_STOP
		if not board.is_connected("resized", Callable(self, "_on_board_resized")):
			board.resized.connect(_on_board_resized)
		if not board.gui_input.is_connected(Callable(self, "_on_board_gui_input")):
			board.gui_input.connect(_on_board_gui_input)
	_recalculate_board_layout_from_board()

	pieces_root = Node2D.new()
	pieces_root.name = "PiecesRoot"
	add_child(pieces_root)
	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	if is_instance_valid(rules_button) and not rules_button.pressed.is_connected(Callable(self, "_on_rules_button_pressed")):
		rules_button.pressed.connect(_on_rules_button_pressed)
	if is_instance_valid(settings_button) and not settings_button.pressed.is_connected(Callable(self, "_on_settings_button_pressed")):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(send_button):
		send_button.disabled = true
		send_button.visible = false
		send_button.modulate.a = 0
		send_button.scale = Vector2(1.0, 1.0)
		if not send_button.pressed.is_connected(Callable(self, "_on_send_pressed")):
			send_button.pressed.connect(_on_send_pressed)
			
	appPlugin = Engine.get_singleton("AppPlugin")
	
	if Engine.has_singleton("OpenPigeonMedia"):
		mediaPlugin = Engine.get_singleton("OpenPigeonMedia")
		print("OpenPigeonMedia plugin is available")
	else:
		print("OpenPigeonMedia plugin is not available")

	_start_music()
	
	if appPlugin:
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
	else:
		if player == 0 or replay == "":
			_set_game_data('{"isYourTurn":1,"player":"1","replay":"board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0|move:6,5,7,4|board:0,2,0,2,0,2,0,2,2,0,2,0,2,0,2,0,0,2,0,2,0,2,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,1,0,1,0,0,1,0,1,0,1,0,1,1,0,1,0,1,0,1,0"}')
			print("App plugin is not available")

	if player == 0 or replay == "":
		return

	var playerBox := get_node_or_null("Player" + str(player) + "Box")
	if playerBox != null and not spectator_mode:
		playerBox.get_child(0).set_text("[center]You[/center]")	
		
func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color(0.08, 0.08, 0.08) if is_dark else Color("#e5e5e5")
	
func _visual_to_logical(gx: int, gy: int) -> Vector2i:
	var lx := gx if (player == 2 and not spectator_mode) else (7 - gx)
	var ly := (7 - gy) if (player == 2 and not spectator_mode) else gy
	return Vector2i(lx, ly)
	
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
	
func _animate_send_button(show: bool) -> void:
	if not is_instance_valid(send_button):
		return
	if not send_button.has_meta("sb_home_pos"):
		send_button.set_meta("sb_home_pos", send_button.position)
	var home_pos: Vector2 = send_button.get_meta("sb_home_pos")
	var off_pos: Vector2 = Vector2(home_pos.x, get_viewport_rect().size.y + send_button.size.y + 24.0)
	if send_button.has_meta("sb_tween"):
		var old_tw: Variant = send_button.get_meta("sb_tween")
		if old_tw is Tween and (old_tw as Tween).is_running():
			(old_tw as Tween).kill()

	var tw := create_tween()
	send_button.set_meta("sb_tween", tw)

	if show:
		send_button.visible = true
		send_button.disabled = false
		send_button.position = off_pos
		send_button.modulate.a = 0.0
		tw.tween_property(send_button, "position", home_pos, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(send_button, "modulate:a", 1.0, 0.35)
	else:
		send_button.disabled = true
		tw.tween_property(send_button, "position", off_pos, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(send_button, "modulate:a", 0.0, 0.25)
		tw.tween_callback(func():
			if is_instance_valid(send_button):
				send_button.visible = false
				send_button.position = home_pos
		)

func _make_move_highlight_node() -> Sprite2D:
	var spr := Sprite2D.new()
	spr.name = "MoveHighlight"
	spr.centered = true
	spr.z_as_relative = false
	spr.z_index = 1

	var grad := Gradient.new()
	grad.add_point(0.00, Color(1, 1, 1, 0.00))
	grad.add_point(0.35, Color(1, 1, 1, 0.18))
	grad.add_point(0.75, Color(1, 1, 1, 0.32))
	grad.add_point(1.00, Color(1, 1, 1, 0.00))

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 512
	tex.height = 512
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.25, 0.5)

	spr.texture = tex
	_start_pulse(spr, 0.10, 0.60, 1.2)
	return spr
	
func _post_replay_ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_scan_row(3)
	_scan_row(4)
	_scan_row(5)

	_compute_mandatory_jumps()
	if rule_mandatory_jumps and must_jump and chain_jump_piece == null:
		_show_mandatory_jump_previews()

func _add_move_highlight(lx: int, ly: int) -> void:
	var key := Vector2i(lx, ly)
	if move_highlights.has(key):
		var existing: Sprite2D = move_highlights[key]
		if is_instance_valid(existing):
			existing.position = _cell_pos(lx, ly)
			existing.visible = true
			return

	var spr := _make_move_highlight_node()
	var target_px := float(cell_px) * 0.9
	var sx := target_px / float(spr.texture.get_width())
	var sy := target_px / float(spr.texture.get_height())
	var scale_factor : float = min(sx, sy)
	spr.scale = Vector2(scale_factor, scale_factor)
	spr.position = _cell_pos(lx, ly)
	add_child(spr)
	move_highlights[key] = spr

func _clear_move_highlights() -> void:
	for k in move_highlights.keys():
		var n2: Sprite2D = move_highlights[k]
		if is_instance_valid(n2):
			if n2.has_meta("_pulse_tween"):
				var t: Tween = n2.get_meta("_pulse_tween")
				if t and t.is_running(): t.kill()
				n2.set_meta("_pulse_tween", null)
			n2.queue_free()
	move_highlights.clear()

func _revert_temp_move_if_any() -> void:
	if input_locked:
		return
	if not has_moved or prev_moves.size() < 2:
		return

	input_locked = true

	for i in range(prev_moves.size() - 2, -1, -2):
		var from_v := Vector2i(int(prev_moves[i].x), int(prev_moves[i].y))
		var to_v := Vector2i(int(prev_moves[i + 1].x), int(prev_moves[i + 1].y))

		var piece_to_revert := get_node_or_null("PiecesRoot/%d,%d" % [to_v.x, to_v.y]) as Sprite2D
		if piece_to_revert != null:
			move_piece(piece_to_revert, from_v.x, from_v.y, 0.0)

	if prev_jumps.size() > 0:
		for jumped in prev_jumps:
			if jumped == null or not is_instance_valid(jumped):
				continue

			var parts := String(jumped.name).replace("_captured_", "").split(",")
			if parts.size() == 2:
				jumped.name = "%s,%s" % [parts[0], parts[1]]
			jumped.self_modulate.a = 1.0
			jumped.visible = true

			if jumped.get_parent() == null and pieces_root != null:
				pieces_root.add_child(jumped)

	prev_moves.clear()
	prev_jumps.clear()
	has_moved = false
	chain_jump_piece = null
	clicked_piece = null
	moves.clear()

	clear_highlights()
	_update_send_button()
	_compute_mandatory_jumps()

	if rule_mandatory_jumps and must_jump:
		_show_mandatory_jump_previews()

	input_locked = false
	
func _update_send_button() -> void:
	if not is_instance_valid(send_button):
		return
	if has_moved:
		_animate_send_button(true)
	else:
		_animate_send_button(false)
	
func _on_board_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	if not _can_accept_board_input():
		return

	var draw: Rect2 = _get_board_draw_rect()
	var p: Vector2 = event.position
	if not draw.has_point(p):
		return

	var rel: Vector2 = p - draw.position - Vector2(board_inset, board_inset)
	var gx: int = int(floor(rel.x / float(cell_px)))
	var gy: int = int(floor(rel.y / float(cell_px)))
	if gx < 0 or gx > 7 or gy < 0 or gy > 7:
		return

	var L: Vector2i = _visual_to_logical(gx, gy)
	var lx: int = L.x
	var ly: int = L.y

	if not rule_mandatory_jumps:
		must_jump = false
		jumping_pieces.clear()
	else:
		_compute_mandatory_jumps()

	var clicked_piece_on_cell := get_node_or_null("PiecesRoot/%d,%d" % [lx, ly]) as Sprite2D

	if has_moved and chain_jump_piece == null:
		if clicked_piece_on_cell != null and check_player(clicked_piece_on_cell):
			var moved_to := Vector2i(int(prev_moves[-1].x), int(prev_moves[-1].y))
			if _get_piece_pos(clicked_piece_on_cell) == moved_to:
				_revert_temp_move_if_any()
				return
			_revert_temp_move_if_any()
			_select_piece(clicked_piece_on_cell)
			return

		if clicked_piece != null:
			_try_commit_move(clicked_piece, lx, ly)
		return

	if clicked_piece_on_cell != null:
		if not check_player(clicked_piece_on_cell):
			return

		if chain_jump_piece != null and clicked_piece_on_cell != chain_jump_piece:
			return

		if rule_mandatory_jumps and must_jump and chain_jump_piece == null:
			if not (clicked_piece_on_cell in jumping_pieces):
				for piece_to_pulse in jumping_pieces:
					_start_pulse(piece_to_pulse, 0.1, 0.7, 1.0)
				return

		if clicked_piece_on_cell == clicked_piece and not has_moved:
			clicked_piece = null
			clear_highlights()
			_clear_selected_highlight()
			if rule_mandatory_jumps and must_jump:
				_show_mandatory_jump_previews()
			return

		_select_piece(clicked_piece_on_cell)
		return

	if clicked_piece != null:
		_try_commit_move(clicked_piece, lx, ly)
		return

	clear_highlights()
	_clear_selected_highlight()

	if rule_mandatory_jumps and must_jump:
		_show_mandatory_jump_previews()
		
func _start_pulse(node: CanvasItem, min_a: float = 0.35, max_a: float = 0.85, period: float = 1.2) -> void:
	if node == null or not is_instance_valid(node):
		return

	if node.has_meta("_pulse_tween"):
		var old: Tween = node.get_meta("_pulse_tween")
		if old and old.is_running():
			old.kill()
		node.set_meta("_pulse_tween", null)

	if not node.is_inside_tree():
		await get_tree().process_frame
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			return

	var tw := _tween_for(node)
	tw.set_loops(0)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "self_modulate:a", min_a, period * 0.5)
	tw.tween_property(node, "self_modulate:a", max_a, period * 0.5)

	node.set_meta("_pulse_tween", tw)
	node.tree_exited.connect(func():
		if is_instance_valid(tw):
			tw.kill()
		node.set_meta("_pulse_tween", null)
	)

func _stop_pulse(node: CanvasItem) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_meta("_pulse_tween"):
		var t: Tween = node.get_meta("_pulse_tween")
		if t and t.is_running():
			t.kill()
		node.set_meta("_pulse_tween", null)
	node.self_modulate.a = 1.0

func _stop_all_jump_pulses(except: Sprite2D = null) -> void:
	for p in jumping_pieces:
		if p != null and is_instance_valid(p) and p != except:
			_stop_pulse(p)


func _get_board_draw_rect() -> Rect2:
	if not is_instance_valid(board) or board.texture == null:
		return Rect2(board.position, board.size)
	var tex_size_i: Vector2i = board.texture.get_size()
	var tex_size: Vector2 = Vector2(tex_size_i)
	var ctl_size: Vector2 = board.size
	var off: Vector2 = board.position
	var mode: int = board.stretch_mode

	match mode:
		TextureRect.STRETCH_SCALE, TextureRect.STRETCH_TILE:
			return Rect2(off, ctl_size)

		TextureRect.STRETCH_KEEP, TextureRect.STRETCH_KEEP_CENTERED:
			var draw_size: Vector2 = tex_size
			var draw_pos: Vector2 = off
			if mode == TextureRect.STRETCH_KEEP_CENTERED:
				draw_pos += (ctl_size - draw_size) * 0.5
			return Rect2(draw_pos, draw_size)

		TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var s: float = min(ctl_size.x / tex_size.x, ctl_size.y / tex_size.y)
			var draw_size: Vector2 = tex_size * s
			var draw_pos: Vector2 = off
			if mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
				draw_pos += (ctl_size - draw_size) * 0.5
			return Rect2(draw_pos, draw_size)

		TextureRect.STRETCH_KEEP_ASPECT_COVERED:
			var s2: float = max(ctl_size.x / tex_size.x, ctl_size.y / tex_size.y)
			var draw_size2: Vector2 = tex_size * s2
			var draw_pos2: Vector2 = off + (ctl_size - draw_size2) * 0.5
			return Rect2(draw_pos2, draw_size2)

		_:
			return Rect2(off, ctl_size)
	
func _abs_to_logical(ax: int, ay: int) -> Vector2i:
	var lx := ax
	var ly := ay
	return Vector2i(lx, ly)

func _logical_to_abs(lx: int, ly: int) -> Vector2i:
	var ax := lx
	var ay := ly
	return Vector2i(ax, ay)
	
func _get_legal_targets_for_piece(piece: Sprite2D, jumps_only: bool = false) -> Dictionary:
	var out: Dictionary = {}
	if piece == null or not is_instance_valid(piece):
		return out
	if not check_player(piece):
		return out

	var pos := _get_piece_pos(piece)
	if pos == Vector2i(-1, -1):
		return out

	if chain_jump_piece != null and piece != chain_jump_piece:
		return out

	var effective_must: bool = must_jump if rule_mandatory_jumps else false
	var continuing_jump: bool = (chain_jump_piece != null and piece == chain_jump_piece)
	var require_jumps: bool = jumps_only or continuing_jump or effective_must

	if effective_must and not _any_jump_from(piece):
		return out

	for d: Vector2i in _jump_dirs_for(piece):
		var mid := pos + d
		var land := pos + (d * 2)
		if land.x < 0 or land.x > 7 or land.y < 0 or land.y > 7:
			continue

		var mid_node := get_node_or_null("PiecesRoot/%d,%d" % [mid.x, mid.y]) as Sprite2D
		if mid_node != null and not check_player(mid_node) \
		and get_node_or_null("PiecesRoot/%d,%d" % [land.x, land.y]) == null:
			out[Vector2i(land.x, land.y)] = true

	if not require_jumps and not has_moved:
		for d: Vector2i in _move_dirs_for(piece):
			var adj := pos + d
			if adj.x < 0 or adj.x > 7 or adj.y < 0 or adj.y > 7:
				continue
			if get_node_or_null("PiecesRoot/%d,%d" % [adj.x, adj.y]) == null:
				out[Vector2i(adj.x, adj.y)] = true

	return out
	
func _try_commit_move(piece: Sprite2D, to_lx: int, to_ly: int) -> void:
	if input_locked:
		return
	if piece == null or not is_instance_valid(piece):
		return
	if not check_player(piece):
		return
	if not isTurn or waitingForOpponent or spectator_mode or game_over:
		return
	if chain_jump_piece != null and piece != chain_jump_piece:
		return

	var from_pos: Vector2i = _get_piece_pos(piece)
	if from_pos == Vector2i(-1, -1):
		return

	var legal: Dictionary = _get_legal_targets_for_piece(piece, chain_jump_piece != null)
	var target := Vector2i(to_lx, to_ly)
	if not legal.has(target):
		return

	input_locked = true
	clear_highlights()
	_stop_all_jump_pulses(piece)

	var was_jump: bool = abs(from_pos.x - to_lx) == 2 and abs(from_pos.y - to_ly) == 2

	prev_moves.append(Vector2(from_pos.x, from_pos.y))
	prev_moves.append(Vector2(to_lx, to_ly))
	has_moved = true

	var move_tw: Tween = move_piece(piece, to_lx, to_ly)
	var jump_tw: Tween = null

	if was_jump:
		jump_tw = jump_piece(from_pos.x, from_pos.y, to_lx, to_ly)
		chain_jump_piece = piece
	else:
		chain_jump_piece = null

	if move_tw != null and move_tw.is_running():
		await move_tw.finished
	if jump_tw != null and jump_tw.is_running():
		await jump_tw.finished

	if piece == null or not is_instance_valid(piece):
		input_locked = false
		return

	clicked_piece = piece
	_compute_mandatory_jumps()

	if was_jump:
		var follow_ups: Dictionary = _get_legal_targets_for_piece(piece, true)
		if follow_ups.size() > 0:
			moves.clear()
			for k in follow_ups.keys():
				var v: Vector2i = k
				moves[Vector2(v.x, v.y)] = piece
				_add_move_highlight(v.x, v.y)
			_show_selected_highlight_at(to_lx, to_ly)
			_update_send_button()
			input_locked = false
			return

	chain_jump_piece = null
	clicked_piece = piece
	moves.clear()
	_clear_move_highlights()
	_show_selected_highlight_at(to_lx, to_ly)

	_update_send_button()
	input_locked = false
	
func _rebuild_from_replay() -> void:
	replay_locked = true
	input_locked = true

	clear_highlights()
	clicked_piece = null
	moves.clear()
	has_moved = false
	prev_moves.clear()
	prev_jumps.clear()
	chain_jump_piece = null
	must_jump = false
	jumping_pieces.clear()

	_prepare_scene_once()
	_clear_pieces()
	await get_tree().process_frame
	await get_tree().process_frame

	var initial_board: PackedStringArray = PackedStringArray()
	var final_board: PackedStringArray = PackedStringArray()
	var replay_moves: Array[String] = []

	for elem in replay.split("|", false):
		var spl := elem.split(":", false, 1)
		if spl.size() < 2:
			continue

		match spl[0]:
			"move", "attack":
				replay_moves.append(elem)
			"board":
				if initial_board.is_empty():
					initial_board = spl[1].split(",")
				else:
					final_board = spl[1].split(",")

	if initial_board.is_empty() and not final_board.is_empty():
		initial_board = final_board
	if final_board.is_empty() and not initial_board.is_empty():
		final_board = initial_board

	if not initial_board.is_empty():
		for ay in range(8):
			for ax in range(8):
				var idx: int = ay * 8 + ax
				if idx >= initial_board.size():
					continue

				var v: String = initial_board[idx]
				if v == "0":
					continue

				var L: Vector2i = _abs_to_logical(ax, ay)
				_spawn_piece(v, L.x, L.y)

	await get_tree().process_frame

	for move_entry in replay_moves:
		var parts := move_entry.split(":", false, 1)
		if parts.size() < 2:
			continue

		var kind: String = parts[0]
		var p := parts[1].split(",")
		if p.size() < 4:
			continue

		var src_l: Vector2i = _abs_to_logical(int(p[0]), int(p[1]))
		var dst_l: Vector2i = _abs_to_logical(int(p[2]), int(p[3]))

		var moved := get_node_or_null("PiecesRoot/%d,%d" % [src_l.x, src_l.y]) as Sprite2D
		if moved == null:
			continue

		var move_tw: Tween = move_piece(moved, dst_l.x, dst_l.y, 0.0)
		var jump_tw: Tween = null

		if kind == "attack":
			jump_tw = jump_piece(src_l.x, src_l.y, dst_l.x, dst_l.y, 0.0, true)

		if move_tw != null and move_tw.is_running():
			await move_tw.finished
		if jump_tw != null and jump_tw.is_running():
			await jump_tw.finished

		if is_instance_valid(moved):
			var col: String = get_piece_color(moved)
			if (col == "red" and dst_l.y == 0) or (col == "black" and dst_l.y == 7):
				set_checker_king(moved, col)

	await get_tree().process_frame
	await get_tree().process_frame

	_compute_mandatory_jumps()

	if isTurn and not spectator_mode and rule_mandatory_jumps and must_jump:
		_show_mandatory_jump_previews()
	else:
		_clear_move_highlights()

	_update_send_button()
	_apply_player_piece_icons()
	_apply_board_orientation()

	var wl := check_win_loss()
	if wl != "":
		game_over = true
		stop_waiting_animation()
		if is_instance_valid(send_button):
			send_button.visible = false
			send_button.disabled = true
		game_over_visual(wl)
	else:
		game_over = false
		if isTurn and not spectator_mode:
			stop_waiting_animation()
		else:
			start_waiting_animation()

	replay_locked = false
	input_locked = false

	if isTurn and not spectator_mode and not game_over:
		call_deferred("_post_replay_ready")
		
func _make_radial_highlight_node() -> Sprite2D:
	var spr := Sprite2D.new()
	spr.name = "SelectedCellHighlight"
	spr.centered = true
	spr.z_as_relative = false
	spr.z_index = 1

	var grad := Gradient.new()
	grad.add_point(0.0, Color(1.0, 1.0, 1.0, 0))
	grad.add_point(1.0, Color(1.0, 1.0, 1.0, 0.1))

	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 512
	gt.height = 512
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.use_hdr = false
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.25, 0.5)

	spr.texture = gt
	return spr

func _show_selected_highlight_at(lx: int, ly: int) -> void:
	if pieces_root == null:
		_prepare_scene_once()

	if selected_highlight == null:
		selected_highlight = _make_radial_highlight_node()
		pieces_root.add_child(selected_highlight)
	selected_highlight.self_modulate = Color(1, 1, 1, 0.5)

	var tex := selected_highlight.texture
	if tex != null:
		var target_px: float = float(cell_px)
		var sx: float = target_px / float(tex.get_width())
		var sy: float = target_px / float(tex.get_height())
		selected_highlight.scale = Vector2(min(sx, sy), min(sx, sy))

	selected_highlight.position = _cell_pos(lx, ly)
	selected_highlight.visible = true


func _clear_selected_highlight() -> void:
	if selected_highlight and is_instance_valid(selected_highlight):
		selected_highlight.visible = false
		
func _set_game_data(new_replay: String) -> void:
	var data_raw: Variant = JSON.parse_string(new_replay)
	if typeof(data_raw) != TYPE_DICTIONARY:
		return
	var data: Dictionary = data_raw
	print("RAW GAME DATA: ", data_raw)

	isTurn = bool(data.get("isYourTurn", false))
	replay = String(data.get("replay", ""))
	mode = String(data.get("mode", "n"))
	rule_mandatory_jumps = (mode == "n")
	my_player = String(data.get("myPlayerId", ""))

	var data_sender: int = clamp(int(data.get("player", 0)), 0, 2)
	turn_owner = clamp(int(data.get("player", 1)), 1, 2)
	var p1_id: String = String(data.get("player1", ""))
	var p2_id: String = String(data.get("player2", ""))
 
	var my_side := 0
	if my_player != "" and p1_id != "" and p2_id != "":
		if my_player == p1_id:
			my_side = 1
		elif my_player == p2_id:
			my_side = 2
		else:
			my_side = 0
	else:
		if data_sender == 1:
			my_side = 2
		elif data_sender == 2:
			my_side = 1
		else:
			my_side = 0

	spectator_mode = (my_side == 0)
	if spectator_mode:
		if is_instance_valid(spec_label):
			spec_label.visible = true
		if is_instance_valid(you_label):
			you_label.modulate.a = 0.0

	player = my_side

	var opponent_avatar_key := ""
	if player == 1:
		opponent_avatar_key = "avatar2"
	elif player == 2:
		opponent_avatar_key = "avatar1"

	if opponent_avatar_key != "" and data.has(opponent_avatar_key):
		var avatar_string: String = String(data[opponent_avatar_key])
		var opponent_data: Dictionary = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	waitingForOpponent = not isTurn
	_apply_player_piece_icons()
	call_deferred("_rebuild_from_replay")
	
func game_over_visual(results: String) -> void:
	if spectator_mode:
		if results == "win":
			win_loss_label.text = "Player 1 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			_show_win_burst(player_avatar_display)
		else:
			win_loss_label.text = "Player 2 Wins!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			_show_win_burst(opp_avatar_display)
	else:
		if results == "win":
			_show_win_burst(player_avatar_display)
			win_loss_label.text = "YOU WIN!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		else:
			_show_win_burst(opp_avatar_display)
			win_loss_label.text = "YOU LOSE"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

	win_loss_label.visible = true
	await get_tree().process_frame
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2
	var t_in: Tween = create_tween()
	t_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
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
				data["fshape_color"] = _read_color(key_value.slice(1))
			"hair":
				var i2 := key_value[1].to_int()
				if i2 >= 0 and i2 < hair_map.size():
					data["hair_style"] = String(hair_map[i2])
			"hair_color":
				data["hair_color"] = _read_color(key_value.slice(1))
			"eyes":
				var i3 := key_value[1].to_int()
				if i3 >= 0 and i3 < eyes_map.size():
					data["eyes_style"] = String(eyes_map[i3])
			"mouth":
				var i4 := key_value[1].to_int()
				if i4 >= 0 and i4 < mouth_map.size():
					data["mouth_style"] = String(mouth_map[i4])
			"clothes":
				var i5 := key_value[1].to_int()
				if i5 >= 0 and i5 < clothing_map.size():
					data["clothing_style"] = String(clothing_map[i5])
			"clothes_color":
				data["clothing_color"] = _read_color(key_value.slice(1))
			"bg_color":
				data["bg_color"] = _read_color(key_value.slice(1))
			"backdrop":
				var i6 := key_value[1].to_int()
				if i6 >= 0 and i6 < backdrop_map.size():
					data["bg_style"] = String(backdrop_map[i6])
			_:
				pass
	return data

func export_replay() -> String:
	var board: Array[String] = []
	for i in range(64):
		board.append("0")

	for ly in range(8):
		for lx in range(8):
			var piece := get_node_or_null("PiecesRoot/%d,%d" % [lx, ly]) as Sprite2D
			if piece != null:
				var A := _logical_to_abs(lx, ly)
				var idx := A.y * 8 + A.x
				var color := get_piece_color(piece)
				if color == "red":
					board[idx] = "3" if is_checker_king(piece) else "1"
				elif color == "black":
					board[idx] = "4" if is_checker_king(piece) else "2"

	var boardStr := ",".join(board)

	var move_str := "|"
	for i in range(0, prev_moves.size(), 2):
		var p1: Vector2 = prev_moves[i]
		var p2: Vector2 = prev_moves[i + 1]
		var A1 := _logical_to_abs(int(p1.x), int(p1.y))
		var A2 := _logical_to_abs(int(p2.x), int(p2.y))
		var moveType := "attack" if abs(p1.x - p2.x) > 1 else "move"
		move_str += "%s:%d,%d,%d,%d|" % [moveType, A1.x, A1.y, A2.x, A2.y]

	clear_highlights()
	clicked_piece = null
	has_moved = false
	moves.clear()
	prev_jumps.clear()
	prev_moves.clear()
	if is_instance_valid(send_button):
		send_button.disabled = true

	var result: Dictionary = {
		"replay": replay.split("|")[-1] + move_str + "board:" + boardStr
	}
	var wl := check_win_loss()
	if wl != "":
		result["winner"] = my_player + "|" + ("1" if wl == "win" else "-1")
	return JSON.stringify(result)

func check_win_loss() -> String:
	var num_your_pieces := 0
	var num_other_pieces := 0
	var scanned_any := false

	for y in range(0, 8):
		for x in range(0, 8):
			var piece := get_node_or_null("PiecesRoot/" + str(x) + "," + str(y)) as Sprite2D
			if piece != null:
				scanned_any = true
				if check_player(piece):
					num_your_pieces += 1
				else:
					num_other_pieces += 1

	if not scanned_any:
		return ""
	if num_your_pieces == 0 and num_other_pieces > 0:
		return "lose"
	if num_other_pieces == 0 and num_your_pieces > 0:
		return "win"

	return ""
	
func jump_piece(prev_x: int, prev_y: int, new_x: int, new_y: int, anim_delay: float = 0.0, replay_mode: bool = false) -> Tween:
	var x_step := 1 if new_x > prev_x else -1
	var y_step := 1 if new_y > prev_y else -1
	var jx := prev_x + x_step
	var jy := prev_y + y_step

	var jumped_piece := get_node_or_null("PiecesRoot/%d,%d" % [jx, jy]) as Sprite2D
	if jumped_piece == null:
		return null

	jumped_piece.name = "_captured_%d,%d" % [jx, jy]

	var tween := jumped_piece.get_tree().create_tween()
	var modulate_color := jumped_piece.self_modulate
	modulate_color.a = 0.0
	tween.tween_interval(anim_delay)
	tween.tween_property(jumped_piece, "self_modulate", modulate_color, 0.2).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func():
		if is_instance_valid(jumped_piece):
			jumped_piece.queue_free()
	)

	if not replay_mode:
		prev_jumps.append(jumped_piece)

	return tween
	
func move_piece(piece: Sprite2D, x: int, y: int, anim_delay: float = 0.0) -> Tween:
	var new_pos := _cell_pos(x, y)
	var tween := piece.get_tree().create_tween()
	tween.tween_interval(anim_delay)
	tween.tween_property(piece, "position", new_pos, 0.5).set_trans(Tween.TRANS_SINE)

	var color := get_piece_color(piece)
	if (color == "red" and y == 0) or (color == "black" and y == 7):
		tween.tween_callback(set_checker_king.bind(piece, color))

	piece.name = "%d,%d" % [x, y]
	return tween
	
func set_checker_king(piece: Sprite2D, color: String, undo: bool = false) -> void:
	if color == "red":
		piece.texture = red_normal_texture if undo else red_king_texture
	elif color == "black":
		piece.texture = black_normal_texture if undo else black_king_texture
	_apply_piece_scale(piece)


func is_checker_king(piece: Sprite2D) -> bool:
	return piece.texture != null and piece.texture.resource_path.contains("king")


func getPiecePos(piece: Sprite2D) -> Vector2:
	var posStr := piece.name.split(",")
	return Vector2(int(posStr[0]), int(posStr[1]))

func add_highlight(x: int, y: int) -> void:
	_add_move_highlight(x, y)

func clear_highlights() -> void:
	for n: Node in highlights:
		if is_instance_valid(n):
			n.queue_free()
	highlights.clear()
	_clear_move_highlights()
	_clear_selected_highlight()
	_stop_all_jump_pulses()

func get_piece_color(piece: Sprite2D) -> String:
	if piece.texture.resource_path.contains("red"):
		return "red"
	elif piece.texture.resource_path.contains("black"):
		return "black"
	return "unknown"

func gen_moves(jumps_only: bool = false) -> void:
	moves.clear()
	_clear_move_highlights()

	if clicked_piece == null or not is_instance_valid(clicked_piece):
		return

	var legal: Dictionary = _get_legal_targets_for_piece(clicked_piece, jumps_only)
	for target in legal.keys():
		var v: Vector2i = target
		moves[Vector2(v.x, v.y)] = clicked_piece
		_add_move_highlight(v.x, v.y)
		
func check_player(piece: Sprite2D) -> bool:
	var color := get_piece_color(piece)
	if spectator_mode and color == "red":
		return true
	if player == 1 and color == "red":
		return true
	if player == 2 and color == "black":
		return true
	return false
	
func _cell_pos_visual(gx: int, gy: int) -> Vector2:
	return board_origin + Vector2((gx + 0.5) * float(cell_px), (gy + 0.5) * float(cell_px))

func _on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return

	rules_button.pivot_offset = rules_button.size / 2.0
	var tween := create_tween()
	tween.tween_property(rules_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(rules_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var popup := RULES_POPUP_SCENE.instantiate() as RulesPopup
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99

	popup.tree_exited.connect(func():
		if is_instance_valid(dim):
			dim.queue_free()
	)

	popup.open("How to Play Checkers", _get_rules_text())
	
func _get_rules_text() -> String:
	return """
[font_size={32px}][b]Checkers[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
Capture all of your opponent’s pieces or block them so they have no legal moves left.
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• Pieces move diagonally forward to an empty dark square.  
• Capturing (jumping over an adjacent enemy piece into an empty square) is [b]mandatory[/b].  
• Multiple jumps must continue until no further captures are possible.  
• Regular pieces (“men”) move and capture forward only.  
• When a man reaches the farthest row, it becomes a [b]King[/b] and can move and capture both forward and backward.  
• Crowning happens immediately, and a new King may keep jumping if captures remain available.
[/font_size]

[font_size={24px}][b]End of Game[/b][/font_size]
[font_size={18px}]
The game ends when one player loses all their pieces or cannot make a legal move.  
The other player is declared the winner.
[/font_size]

"""

func _on_dim_gui_input_rules(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		suppress_next_click = true
		get_viewport().set_input_as_handled()

func _on_rules_close_pressed(dim: ColorRect, popup: Control) -> void:
	suppress_next_click = true
	if is_instance_valid(dim):
		dim.queue_free()
	if is_instance_valid(popup):
		popup.queue_free()

func _on_settings_button_pressed() -> void:
	if not is_instance_valid(settings_button):
		return
	settings_button.pivot_offset = settings_button.size / 2.0
	var tween := _tween_for(rules_button)
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

	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_gui_input_settings)

	var custom_settings_title := popup_instance.find_child("CustomSettingsTitleLabel", true)
	var cst_label := custom_settings_title as Label
	if cst_label != null:
		var has_children := false
		if settings_popup_script and settings_popup_script.custom_settings_container:
			has_children = settings_popup_script.custom_settings_container.get_child_count() > 0
		cst_label.visible = has_children

	settings_popup_script.closed.connect(_on_settings_closed)
	settings_popup_script.settings_theme_selected.connect(_on_settings_theme_selected)
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

func _on_dim_gui_input_settings(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		suppress_next_click = true
		get_viewport().set_input_as_handled()

func _on_settings_closed() -> void:
	suppress_next_click = true
	if is_instance_valid(player_avatar_display):
		player_avatar_display.update_display_from_settings()

func _on_settings_theme_selected(_name: String) -> void:
	pass
	
func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
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
	
func start_waiting_animation():
	if not is_instance_valid(waiting_label) or not is_instance_valid(waiting_blur) or not is_instance_valid(dot_timer):
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

func _on_dot_timer_timeout():
	if not is_instance_valid(waiting_label):
		return
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots

func _unhandled_input(event: InputEvent) -> void:
	if suppress_next_click and event is InputEventMouseButton and event.pressed:
		suppress_next_click = false
		get_viewport().set_input_as_handled()
		
func _read_color(vals: Array) -> Color:
	if vals.size() >= 3:
		return Color(vals[0].to_float(), vals[1].to_float(), vals[2].to_float())
	return Color.WHITE

func _process(_delta: float) -> void:
	pass

func _dump_pieces() -> void:
	var names: Array[String] = []
	if pieces_root:
		for c in pieces_root.get_children():
			if c is Sprite2D:
				names.append((c as Sprite2D).name)
	
func _peek_cell(lx: int, ly: int) -> void:
	var n := get_node_or_null("PiecesRoot/%d,%d" % [lx, ly])
	
func _scan_row(ly: int) -> void:
	var row: Array[String] = []
	for x in range(8):
		var n := get_node_or_null("PiecesRoot/%d,%d" % [x, ly])
		row.append(n.name if n else ".")
	
func _diagonal_dirs_for(piece: Sprite2D) -> Array:
	var dirs: Array[Vector2i] = []
	var col := get_piece_color(piece)
	var king := is_checker_king(piece)
	if col == "black" or king:
		dirs.append(Vector2i(-1, -1))
		dirs.append(Vector2i( 1, -1))
	if col == "red" or king:
		dirs.append(Vector2i(-1,  1))
		dirs.append(Vector2i( 1,  1))
	return dirs

func _any_jump_from(piece: Sprite2D) -> bool:
	if piece == null or not is_instance_valid(piece):
		return false
	var p := Vector2i(int(getPiecePos(piece).x), int(getPiecePos(piece).y))
	for d in _jump_dirs_for(piece):
		var mid := p + d
		var land := p + (d * 2)
		if land.x < 0 or land.x > 7 or land.y < 0 or land.y > 7:
			continue
		var mid_node := get_node_or_null("PiecesRoot/%d,%d" % [mid.x, mid.y]) as Sprite2D
		if mid_node != null and not check_player(mid_node) \
		and get_node_or_null("PiecesRoot/%d,%d" % [land.x, land.y]) == null:
			return true
	return false

func _compute_mandatory_jumps() -> void:
	must_jump = false
	jumping_pieces.clear()

	if not rule_mandatory_jumps:
		return

	if spectator_mode or not isTurn:
		return

	for y in range(8):
		for x in range(8):
			var piece := get_node_or_null("PiecesRoot/%d,%d" % [x, y]) as Sprite2D
			if piece and check_player(piece) and _any_jump_from(piece):
				must_jump = true
				jumping_pieces.append(piece)

func _pos_str(v: Vector2i) -> String:
	return "(%d,%d)" % [v.x, v.y]
	
func _collect_jump_landings(piece: Sprite2D) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if piece == null or not is_instance_valid(piece):
		return out

	var p := Vector2i(int(getPiecePos(piece).x), int(getPiecePos(piece).y))
	for d: Vector2i in _jump_dirs_for(piece):
		var mid := p + d
		var land := p + (d * 2)
		if land.x < 0 or land.x > 7 or land.y < 0 or land.y > 7:
			continue
		var mid_node := get_node_or_null("PiecesRoot/%d,%d" % [mid.x, mid.y]) as Sprite2D
		if mid_node != null and not check_player(mid_node) \
		and get_node_or_null("PiecesRoot/%d,%d" % [land.x, land.y]) == null:
			out.append(land)
	return out

func _highlight_all_jump_targets() -> void:
	_clear_move_highlights()
	var c := 0
	for jp in jumping_pieces:
		if not is_instance_valid(jp): continue
		_start_pulse(jp, 0.1, 0.7, 1.0)
		for land in _collect_jump_landings(jp):
			_add_move_highlight(land.x, land.y)
			c += 1

func _move_dirs_for(piece: Sprite2D) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = []
	var col := get_piece_color(piece)
	var king := is_checker_king(piece)
	if king or col == "red":
		dirs.append(Vector2i(-1, -1))
		dirs.append(Vector2i( 1, -1))
	if king or col == "black":
		dirs.append(Vector2i(-1,  1))
		dirs.append(Vector2i( 1,  1))
	return dirs

func _jump_dirs_for(piece: Sprite2D) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = []
	if piece == null or not is_instance_valid(piece):
		return dirs

	var col := get_piece_color(piece)
	var king := is_checker_king(piece)

	if king or col == "red":
		dirs.append(Vector2i(-1, -1))
		dirs.append(Vector2i( 1, -1))
	if king or col == "black":
		dirs.append(Vector2i(-1,  1))
		dirs.append(Vector2i( 1,  1))

	return dirs
	
func _sanity_check_any_jump_exists() -> void:
	var found := false
	for y in range(8):
		for x in range(8):
			var p := get_node_or_null("PiecesRoot/%d,%d" % [x, y]) as Sprite2D
			if p == null or not check_player(p):
				continue
			if _any_jump_from(p):
				found = true
				break
		if found: break
	
func _show_mandatory_jump_previews() -> void:
	_clear_move_highlights()

	for jp in jumping_pieces:
		if not is_instance_valid(jp):
			continue

		_start_pulse(jp, 0.10, 0.85, 1.0)

		for land in _collect_jump_landings(jp):
			_add_move_highlight(land.x, land.y)
