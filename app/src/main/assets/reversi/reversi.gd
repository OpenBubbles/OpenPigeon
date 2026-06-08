extends BaseGame

@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var player_count_label = %PlayerCountLabel
@onready var opp_count_label = %OppCountLabel
@onready var grid = %GridContainer
@onready var send_button = %SendButton
@onready var sent_label = %SentLabel
@onready var background = %Background
@onready var win_loss_label = %WinLossLabel
@onready var replay_button = %ReplayButton
@onready var spec_label = %SpecLabel
@onready var board_root: Control = %GameAreaCenterContainer
@onready var star_layer: Control = %StarPointLayer
@onready var main_vbox: Control = %MainVBoxContainer

const BOARD_SIZE = 8
const LOG_TAG := "Reversi"

var board = []
var player_symbol = ""
var game_over = false
var is_your_turn: bool = false
var is_my_turn: bool = false
var player: int = -1
var avatar_key = 0
var replay_val
var replay_symbol
var replay: String = ""
var replay_played: bool = false
var my_moves: Array[Array]
var pre_board_data: Array[int] = []
var post_board_data: Array[int] = []
var win_loss_state = ""
var white_score = 0
var black_score = 0
var preview_flips_active = false

const STAR_POINTS = [
Vector2i(2, 2),
Vector2i(2, 6),
Vector2i(5, 2),
Vector2i(5, 6),
]

var temp_piece_active = false
var temp_piece_x = -1
var temp_piece_y = -1

var button_tween: Tween
var sent_tween: Tween
var send_button_target_y_position = -1
const BUTTON_OFFSCREEN_OFFSET = 100
const STAR_POINT_SCENE = preload("res://reversi/StarPoint.tscn")
const PIECE_TEX := preload("res://reversi/reversi_tile.png")
const MUSIC_STREAM := preload("res://global/audio/reversi.ogg")
const PIECE_PADDING := 6

func _make_piece_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

// Keeps highlights when modulating to black.
uniform float preserve_highlight := 0.65;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	// Apply node's modulate (COLOR) to the texture
	vec4 tinted = base * COLOR;

	// Luminance from the original texture (assumes white chip PNG with shading)
	float lum = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));

	// Specular-ish mask from bright areas, curved for punch
	float spec = pow(smoothstep(0.55, 1.0, lum), 2.2);

	// Mix some "white light" back in so highlights survive black tint
	vec3 outc = mix(tinted.rgb, vec3(1.0), spec * preserve_highlight);

	COLOR = vec4(outc, tinted.a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat
	
func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
func _get_dev_data() -> String:
	return '{ "isYourTurn": true, "player": "2", "replay": "board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,0,0,2,0,2,2,2,2,0,0,1,2,1,1,1,1,1,0,0,0,2,2,0,0,0,0,0,0,0,2,0,0,0,0|move:0,3,1|board:0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,2,2,2,0,0,1,0,2,2,2,2,0,0,1,2,1,1,1,1,1,0,0,0,2,2,0,0,0,0,0,0,0,2,0,0,0,0", "player1": "TEST_P1", "player2": "TEST_P2", "id": "dev", "game": "reversi" }'
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Reversi"

func _on_game_ready():
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)

	post_board_data.resize(64)
	post_board_data.fill(0)

	setup_board_structure()
	call_deferred("place_star_points")

	setup_ui_elements_style_and_signals()
	setup_score_labels()
	setup_sent_label()

	call_deferred("calculate_button_target_position")

	if is_instance_valid(send_button):
		send_button.visible = false
		
func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color(0.08, 0.08, 0.08) if is_dark else Color("#e5e5e5")

func setup_board_structure():
	if not grid:
		return
	board.clear()
	for y in range(BOARD_SIZE):
		board.append([])
		for x in range(BOARD_SIZE):
			var cell_scene = preload("res://reversi/Cell.tscn")
			var cell = cell_scene.instantiate()
			if cell:
				grid.add_child(cell)
				board[y].append(cell)
				cell.set_meta("pos", Vector2i(x, y))
				cell.pressed.connect(on_cell_pressed.bind(x, y))

				_ensure_piece_nodes(cell)

				var highlight = cell.find_child("Highlight")
				if highlight and highlight is TextureRect:
					highlight.texture = create_radial_gradient_texture(64)
					(highlight as TextureRect).mouse_filter = Control.MOUSE_FILTER_IGNORE
					(highlight as TextureRect).z_index = 2
					highlight.visible = false

				var temp_label = cell.find_child("TempPieceLabel")
				if temp_label:
					temp_label.visible = false
			else:
				board[y].append(null)
	dot_timer.timeout.connect(_on_dot_timer_timeout)

func calculate_button_target_position():
	var grid_global_bottom_y = grid.get_global_position().y + grid.size.y
	var main_vbox_global_position = $MainVBoxContainer.get_global_position().y
	send_button_target_y_position = grid_global_bottom_y - main_vbox_global_position + 60
	
	var offscreen_bottom_y = $MainVBoxContainer.size.y + BUTTON_OFFSCREEN_OFFSET
	send_button.position.y = offscreen_bottom_y

func setup_ui_elements_style_and_signals():
	if send_button:
		if not send_button.pressed.is_connected(on_send_button_pressed):
			send_button.pressed.connect(on_send_button_pressed)

		send_button.text = "Send"
		send_button.add_theme_font_override("font", SystemFont.new())
		send_button.add_theme_color_override("font_color", Color.WHITE)
		send_button.add_theme_font_size_override("font_size", 24)
		send_button.set_custom_minimum_size(Vector2(180, 50))
		send_button.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		send_button.set_v_size_flags(Control.SIZE_SHRINK_BEGIN)

	if player_count_label:
		var player_score_style = StyleBoxFlat.new()
		player_score_style.bg_color = Color.BLACK
		player_score_style.corner_radius_top_left = 20
		player_score_style.corner_radius_top_right = 20
		player_score_style.corner_radius_bottom_left = 20
		player_score_style.corner_radius_bottom_right = 20
		player_count_label.add_theme_stylebox_override("normal", player_score_style)
		player_count_label.add_theme_color_override("font_color", Color.WHITE)
		player_count_label.add_theme_font_size_override("font_size", 24)
		player_count_label.set_custom_minimum_size(Vector2(100, 40))
		player_count_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
		player_count_label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		player_count_label.set_h_size_flags(Control.SIZE_SHRINK_CENTER)

	if opp_count_label:
		var opp_score_style = StyleBoxFlat.new()
		opp_score_style.bg_color = Color.WHITE
		opp_score_style.set_border_width_all(2)
		opp_score_style.border_color = Color.DARK_GRAY
		opp_count_label.add_theme_stylebox_override("normal", opp_score_style)
		opp_count_label.add_theme_color_override("font_color", Color.BLACK)
		opp_count_label.add_theme_font_size_override("font_size", 24)
		opp_count_label.set_custom_minimum_size(Vector2(100, 40))
		opp_count_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
		opp_count_label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		opp_count_label.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		
func setup_score_labels():
	if player_count_label:
		var player_score_style = StyleBoxFlat.new()
		if player == 1 or spectator_mode:
			player_score_style.bg_color = Color.BLACK
			player_count_label.add_theme_color_override("font_color", Color.WHITE)
		else:
			player_score_style.bg_color = Color.WHITE
			player_count_label.add_theme_color_override("font_color", Color.BLACK)
		player_count_label.add_theme_stylebox_override("normal", player_score_style)
		player_count_label.add_theme_font_size_override("font_size", 24)
		player_count_label.set_custom_minimum_size(Vector2(60, 60))
		player_count_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
		player_count_label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		player_count_label.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		player_score_style.set_border_width_all(2)
		player_score_style.border_color = Color.GRAY
		player_score_style.corner_radius_top_left = 30
		player_score_style.corner_radius_top_right = 30
		player_score_style.corner_radius_bottom_left = 30
		player_score_style.corner_radius_bottom_right = 30

	if opp_count_label:
		var opp_score_style = StyleBoxFlat.new()
		if player == 1:
			opp_score_style.bg_color = Color.WHITE
			opp_count_label.add_theme_color_override("font_color", Color.BLACK)
		else:
			opp_score_style.bg_color = Color.BLACK
			opp_count_label.add_theme_color_override("font_color", Color.WHITE)
		opp_count_label.add_theme_stylebox_override("normal", opp_score_style)
		opp_count_label.add_theme_font_size_override("font_size", 24)
		opp_count_label.set_custom_minimum_size(Vector2(60, 60))
		opp_count_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
		opp_count_label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		opp_count_label.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
		opp_score_style.set_border_width_all(2)
		opp_score_style.border_color = Color.GRAY
		opp_score_style.corner_radius_top_left = 30
		opp_score_style.corner_radius_top_right = 30
		opp_score_style.corner_radius_bottom_left = 30
		opp_score_style.corner_radius_bottom_right = 30

func setup_sent_label():
	if sent_label:
		sent_label.visible = false
		sent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sent_label.add_theme_color_override("font_color", Color.WHITE)
		sent_label.add_theme_font_size_override("font_size", 22)
		
func _ensure_piece_nodes(cell: Control) -> void:
	var piece := cell.get_node_or_null("Piece") as TextureRect
	if piece == null:
		piece = TextureRect.new()
		piece.name = "Piece"
		piece.texture = PIECE_TEX
		piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		piece.z_index = 0
		piece.material = _make_piece_material()

		piece.ignore_texture_size = true
		piece.custom_minimum_size = Vector2.ZERO
		piece.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		piece.size_flags_vertical   = Control.SIZE_EXPAND_FILL

		cell.add_child(piece)
		piece.set_anchors_preset(Control.PRESET_FULL_RECT)
		piece.offset_left   = PIECE_PADDING
		piece.offset_right  = -PIECE_PADDING
		piece.offset_top    = PIECE_PADDING
		piece.offset_bottom = -PIECE_PADDING
		piece.modulate = Color.WHITE
		piece.visible = false
		piece.scale = Vector2.ONE

	var tpiece := cell.get_node_or_null("TempPiece") as TextureRect
	if tpiece == null:
		tpiece = TextureRect.new()
		tpiece.name = "TempPiece"
		tpiece.texture = PIECE_TEX
		tpiece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tpiece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tpiece.z_index = 1
		tpiece.material = _make_piece_material()

		tpiece.ignore_texture_size = true
		tpiece.custom_minimum_size = Vector2.ZERO
		tpiece.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tpiece.size_flags_vertical   = Control.SIZE_EXPAND_FILL

		cell.add_child(tpiece)
		tpiece.set_anchors_preset(Control.PRESET_FULL_RECT)
		tpiece.offset_left   = PIECE_PADDING
		tpiece.offset_right  = -PIECE_PADDING
		tpiece.offset_top    = PIECE_PADDING
		tpiece.offset_bottom = -PIECE_PADDING
		tpiece.visible = false
		tpiece.scale = Vector2.ONE

	var lbl := cell.find_child("Label")
	if lbl and lbl is Label:
		lbl.visible = false
		(lbl as Control).custom_minimum_size = Vector2.ZERO
	var tlbl := cell.find_child("TempPieceLabel")
	if tlbl and tlbl is Label:
		tlbl.visible = false
		(tlbl as Control).custom_minimum_size = Vector2.ZERO
		
func _ghost_color_for(symbol: String) -> Color:
	return Color(0.18, 0.18, 0.18, 0.70) if symbol == "⚫" else Color(0.90, 0.90, 0.90, 0.65)

func _piece_color_for(symbol: String) -> Color:
	return Color.BLACK if symbol == "⚫" else Color.WHITE

func _show_piece(cell: Control, symbol: String) -> void:
	_ensure_piece_nodes(cell)
	var piece := cell.get_node("Piece") as TextureRect
	piece.visible = symbol != ""
	if symbol != "":
		piece.modulate = _piece_color_for(symbol)

func _show_temp_piece(cell: Control, symbol: String) -> void:
	_ensure_piece_nodes(cell)
	var tpiece := cell.get_node("TempPiece") as TextureRect
	tpiece.visible = true
	tpiece.modulate = _ghost_color_for(symbol)

func _clear_temp_piece(cell: Control) -> void:
	var t := cell.get_node_or_null("TempPiece") as TextureRect
	if t:
		t.visible = false

func _clear_all_preview_overlays() -> void:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var cell: Control = board[y][x] as Control
			if cell:
				_clear_temp_piece(cell)

func _show_preview_overlay_at(x: int, y: int, symbol: String) -> void:
	if not is_in_bounds(Vector2i(x, y)): return
	var cell: Control = board[y][x] as Control
	_show_temp_piece(cell, symbol)

func _flip_squash(cell: Control, to_symbol: String) -> void:
	_ensure_piece_nodes(cell)
	var piece := cell.get_node("Piece") as TextureRect
	piece.visible = true
	piece.pivot_offset = piece.size / 2.0

	var tw := create_tween()
	tw.tween_property(piece, "scale:y", 0.05, 0.16)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): piece.modulate = _piece_color_for(to_symbol))
	tw.tween_property(piece, "scale:y", 1.0, 0.18)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(piece, "scale:x", 1.08, 0.10)\
		.set_ease(Tween.EASE_OUT)
	tw.tween_property(piece, "scale:x", 1.0, 0.12)\
		.set_ease(Tween.EASE_IN)

func initialize_board_pieces():
	OpLog.d(LOG_TAG, [
		"initialize_board_pieces pre_size=", pre_board_data.size(),
		" post_size=", post_board_data.size()
	])

	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			set_piece(x, y, "", true)

	@warning_ignore("integer_division")
	var center = BOARD_SIZE / 2
	set_piece(center - 1, center -1, "⚫", true)
	set_piece(center, center, "⚫", true)
	set_piece(center - 1, center, "⚪", true)
	set_piece(center, center -1, "⚪", true)

func set_piece(x: int, y: int, symbol: String, instant: bool = false) -> void:
	if not is_in_bounds(Vector2i(x, y)): return
	if y >= board.size() or board[y] == null: return
	if x >= board[y].size() or board[y][x] == null: return

	var cell = board[y][x]
	if cell:
		var label = cell.find_child("Label")
		if label:
			(label as Label).text = symbol
		if instant:
			_show_piece(cell, symbol)
		else:
			_flip_squash(cell, symbol)

func get_piece(x: int, y: int) -> String:
	if not is_in_bounds(Vector2i(x, y)):
		return ""

	if y >= board.size() or board[y] == null:
		return ""
	
	if x >= board[y].size() or board[y][x] == null:
		return ""

	var cell = board[y][x]
	
	if cell:
		var label = cell.find_child("Label")
		if label:
			return label.text
		else:
			return ""
	else:
		return ""

func place_star_points():
	for child in star_layer.get_children():
		child.queue_free()

	for pos in STAR_POINTS:
		var star = STAR_POINT_SCENE.instantiate()
		var cell = board[pos.y][pos.x]
		if not cell:
			continue

		var cell_global_pos = cell.get_global_position()
		var star_layer_global_pos = star_layer.get_global_position()
		var relative_pos = cell_global_pos - star_layer_global_pos

		var cell_size = cell.get_size()
		var star_size = star.get_size()

		var offset = Vector2(-8, -7)
		@warning_ignore("integer_division")
		if pos.x >= BOARD_SIZE / 2:
			offset = Vector2(cell_size.x - star_size.x + 8, -7)

		star.position = relative_pos + offset
		star_layer.add_child(star)

func update_piece_counts() -> Dictionary:
	var white_count = 0
	var black_count = 0

	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			match get_piece(x, y):
				"⚪": white_count += 1
				"⚫": black_count += 1

	if temp_piece_active:
		if player_symbol == "⚪":
			white_count += 1
		elif player_symbol == "⚫":
			black_count += 1

	if player == 1:
		opp_count_label.text = str(white_count)
		player_count_label.text = str(black_count)
	else:
		opp_count_label.text = str(black_count)
		player_count_label.text = str(white_count)

	white_score = white_count
	black_score = black_count

	OpLog.d(LOG_TAG, [
		"score_update white=", white_count,
		" black=", black_count,
		" temp_active=", temp_piece_active,
		" player=", player
	])

	return {"white": white_count, "black": black_count}

func highlight_valid_moves():
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var cell = board[y][x]
			var highlight = cell.find_child("Highlight")
			if highlight:
				highlight.visible = replay_played and not game_over and is_valid_move(x, y, player_symbol)
	
	if temp_piece_active and temp_piece_x != -1 and is_my_turn:
		var cell = board[temp_piece_y][temp_piece_x]
		var highlight = cell.find_child("Highlight")
		if highlight:
			highlight.visible = false
		place_temp_piece_visual(temp_piece_x, temp_piece_y, player_symbol)

func _set_game_data(new_game_data_json: String):
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", new_game_data_json])

	var parsed_data = JSON.parse_string(new_game_data_json)

	if not (parsed_data is Dictionary):
		OpLog.e(LOG_TAG, [
			"set_game_data parse_failed type=", typeof(parsed_data),
			" raw=", new_game_data_json
		])

		initialize_board_pieces()
		update_piece_counts()
		highlight_valid_moves()
		return

	game_over = false
	win_loss_state = ""
	spectator_mode = false
	replay_played = false
	temp_piece_active = false
	temp_piece_x = -1
	temp_piece_y = -1
	preview_flips_active = false
	my_moves.clear()

	stop_waiting_animation()
	set_highlight_visibility(false)

	if is_instance_valid(send_button):
		send_button.visible = false

	if is_instance_valid(win_loss_label):
		win_loss_label.visible = false
		win_loss_label.text = ""
		win_loss_label.scale = Vector2.ONE
		win_loss_label.modulate.a = 1.0

	var player1_id: String = str(parsed_data.get("player1", ""))
	var player2_id: String = str(parsed_data.get("player2", ""))
	var winner_payload: String = str(parsed_data.get("winner", ""))
	is_your_turn = bool(parsed_data.get("isYourTurn", false))

	var opponent_avatar_key := ""

	OpLog.i(LOG_TAG, [
		"set_game_data ids my_uuid=", my_uuid,
		" player1=", player1_id,
		" player2=", player2_id,
		" isYourTurn=", is_your_turn
	])

	if my_uuid != "" and player1_id != "" and player2_id != "":
		if my_uuid == player1_id:
			player = 1
			player_symbol = "⚫"
			opponent_avatar_key = "avatar2"
			is_my_turn = is_your_turn
			spectator_mode = false
			OpLog.i(LOG_TAG, "resolved_player player=1 symbol=black")
		elif my_uuid == player2_id:
			player = 2
			player_symbol = "⚪"
			opponent_avatar_key = "avatar1"
			is_my_turn = is_your_turn
			spectator_mode = false
			OpLog.i(LOG_TAG, "resolved_player player=2 symbol=white")
		else:
			spectator_mode = true
			is_my_turn = false
			player = 1
			player_symbol = "⚫"
			OpLog.i(LOG_TAG, "resolved_player spectator=true")
	else:
		if is_your_turn:
			player = 1
			player_symbol = "⚫"
			opponent_avatar_key = "avatar2"
		else:
			player = 2
			player_symbol = "⚪"
			opponent_avatar_key = "avatar1"

		is_my_turn = is_your_turn
		spectator_mode = false

		OpLog.w(LOG_TAG, [
			"fallback_player_resolution player=", player,
			" symbol=", player_symbol,
			" player1_empty=", player1_id == "",
			" player2_empty=", player2_id == ""
		])

	if is_instance_valid(spec_label):
		spec_label.visible = spectator_mode

	setup_score_labels()

	OpLog.i(LOG_TAG, [
		"set_game_data_state player=", player,
		" symbol=", player_symbol,
		" is_my_turn=", is_my_turn,
		" spectator=", spectator_mode,
		" winner_payload=", winner_payload
	])

	if spectator_mode:
		if parsed_data.has("avatar1") and is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", GameUtils._parse_avatar_string(str(parsed_data["avatar1"])))

		if parsed_data.has("avatar2") and is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", GameUtils._parse_avatar_string(str(parsed_data["avatar2"])))
	else:
		if opponent_avatar_key != "" and parsed_data.has(opponent_avatar_key):
			var avatar_string = parsed_data[opponent_avatar_key]
			var opponent_data = GameUtils._parse_avatar_string(avatar_string)

			if is_instance_valid(opp_avatar_display):
				opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	replay = str(parsed_data.get("replay", ""))

	OpLog.i(LOG_TAG, [
		"set_game_data_replay replay_len=", replay.length(),
		" replay_empty=", replay.is_empty()
	])

	if replay.is_empty():
		initialize_board_pieces()
		pre_board_data = get_current_board_as_array()
		update_piece_counts()
	else:
		var temp_parsed_replay = parse_replay(replay)

		if "post_board" in temp_parsed_replay and temp_parsed_replay["post_board"] is Array:
			pre_board_data = temp_parsed_replay["post_board"]
		elif "pre_board" in temp_parsed_replay and temp_parsed_replay["pre_board"] is Array:
			pre_board_data = temp_parsed_replay["pre_board"]
		else:
			OpLog.w(LOG_TAG, "set_game_data replay_missing_board_data")
			pre_board_data.clear()
			pre_board_data.resize(BOARD_SIZE * BOARD_SIZE)
			pre_board_data.fill(0)

		await process_game_state()
		update_piece_counts()

	if winner_payload != "":
		OpLog.event(LOG_TAG, ["winner_payload_received payload=", winner_payload])
		_apply_winner_payload(winner_payload, player1_id, player2_id)
		return

	check_win()

	if not is_my_turn and not game_over and not spectator_mode:
		start_waiting_animation()
	else:
		stop_waiting_animation()

	if is_my_turn and not game_over:
		highlight_valid_moves()
		
func reset_board_to_pre_data():
	for idx in range(BOARD_SIZE * BOARD_SIZE):
		@warning_ignore("integer_division")
		var y = BOARD_SIZE - 1 - int(idx / BOARD_SIZE)
		var x = idx % BOARD_SIZE
		var piece_val = pre_board_data[idx]
		var symbol = ""
		if piece_val == 1:
			symbol = "⚫"
		elif piece_val == 2:
			symbol = "⚪"
		set_piece(x, y, symbol, true)

func process_game_state():
	stop_waiting_animation()

	if not replay.is_empty() and not replay_played:
		await play_replay(replay)
	else:
		print("Replay is empty or replay was already played")

		if not replay.is_empty() and replay_played:
			print("Replay Already Played")
		elif not replay.is_empty() and not replay_played:
			for y_godot in range(BOARD_SIZE):
				for x_godot in range(BOARD_SIZE):
					var replay_y = (BOARD_SIZE - 1) - y_godot
					var cell_index = replay_y * BOARD_SIZE + x_godot

					if cell_index >= 0 and cell_index < pre_board_data.size():
						var piece_value = pre_board_data[cell_index]

						var symbol = ""
						if piece_value == 1:
							symbol = "⚫"
						elif piece_value == 2:
							symbol = "⚪"

						set_piece(x_godot, y_godot, symbol, true)
					else:
						print(str("Error: pre_board_data index out of bounds or size mismatch. Index: ", cell_index, " Size: ", pre_board_data.size()))

	print("Call Update Count")
	update_piece_counts()

	if is_my_turn and not game_over and not spectator_mode:
		highlight_valid_moves()
		send_button.visible = true
	else:
		set_highlight_visibility(false)
		send_button.visible = false

func get_current_board_as_array() -> Array[int]:
	var current_board_array: Array[int] = []
	current_board_array.resize(BOARD_SIZE * BOARD_SIZE)
	current_board_array.fill(0)

	for y_godot in range(BOARD_SIZE):
		for x_godot in range(BOARD_SIZE):
			var replay_y = (BOARD_SIZE - 1) - y_godot
			var cell_index = replay_y * BOARD_SIZE + x_godot
			
			var piece_symbol = get_piece(x_godot, y_godot)

			var piece_value = 0
			if piece_symbol == "⚪":
				piece_value = 2
			elif piece_symbol == "⚫":
				piece_value = 1

			current_board_array[cell_index] = piece_value
	return current_board_array
	
func _show_result_from_state(state: String, spectator_winner_player: int = 0) -> void:
	game_over = true
	win_loss_state = state
	is_my_turn = false
	temp_piece_active = false
	preview_flips_active = false

	stop_waiting_animation()
	set_highlight_visibility(false)

	if is_instance_valid(send_button):
		send_button.visible = false

	set_cells_interactable(false)

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
	win_loss_label.modulate.a = 1.0
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2.0

	var tween = create_tween()
	tween.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _apply_winner_payload(winner_payload: String, player1_id: String = "", player2_id: String = "") -> void:
	var parts := winner_payload.split("|", false)
	if parts.size() < 2:
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

		if sender_uuid == player1_id:
			sender_player = 1
		elif sender_uuid == player2_id:
			sender_player = 2

		winning_player = sender_player

		if sender_state == "-1":
			winning_player = 2 if sender_player == 1 else 1

		local_state = "1" if winning_player == 1 else "-1"
	else:
		if sender_uuid != my_uuid:
			local_state = "-1" if sender_state == "1" else "1"

	_show_result_from_state(local_state, winning_player)

func check_win() -> bool:
	update_piece_counts()

	var current_has_moves = has_any_valid_moves(player_symbol)
	var opponent_player = "⚫" if player_symbol == "⚪" else "⚪"
	var opponent_has_moves = has_any_valid_moves(opponent_player)

	OpLog.d(LOG_TAG, [
		"check_win game_over=", game_over,
		" current_has_moves=", current_has_moves,
		" opponent_has_moves=", opponent_has_moves,
		" white_score=", white_score,
		" black_score=", black_score,
		" player=", player
	])

	if game_over:
		return true

	if current_has_moves or opponent_has_moves:
		return false
		
	OpLog.event(LOG_TAG, [
		"game_finished white_score=", white_score,
		" black_score=", black_score,
		" player=", player
	])

	if white_score == black_score:
		_show_result_from_state("0")
	elif black_score > white_score:
		_show_result_from_state("1" if player == 1 else "-1", 1)
	else:
		_show_result_from_state("1" if player == 2 else "-1", 2)

	return true

func set_cells_interactable(active: bool):
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var cell = board[y][x]
			if cell:
				cell.mouse_filter = Control.MOUSE_FILTER_STOP if not active else Control.MOUSE_FILTER_PASS

func show_replay_button():
	replay_button.text = "Play Again"
	if button_tween and button_tween.is_valid() and button_tween.is_running():
		button_tween.kill()

	replay_button.scale = Vector2(0.0, 0.0)
	replay_button.visible = true
	
	await get_tree().process_frame

	replay_button.pivot_offset = replay_button.size / 2.0

	button_tween = create_tween()
	
	button_tween.tween_property(replay_button, "scale", Vector2(1.0, 1.0), 2.0)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_LINEAR)

	if not replay_button.is_connected("pressed", on_replay_pressed):
		replay_button.pressed.connect(on_replay_pressed)

func on_replay_pressed():
	replay_button.visible = false
	print("NEED TO IMPLEMENT!!!!!")

func has_any_valid_moves(player_symbol_to_check: String) -> bool:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if get_piece(x, y) == "" and is_valid_move(x, y, player_symbol_to_check):
				return true
	return false

func play_replay(replay_string: String):
	print("Starting play_replay")
	print("Replay String: ", replay_string)

	var parsed = parse_replay(replay_string)
	print("Parsed Replay: ", parsed)

	set_highlight_visibility(false)
	send_button.visible = false

	if "pre_board" in parsed and parsed["pre_board"] is Array:
		print("Parsed contains pre_board data")
		var replay_pre_board_data = parsed["pre_board"]
		print("Replay Pre-Board Data Length: ", replay_pre_board_data.size())

		for y in range(BOARD_SIZE):
			for x in range(BOARD_SIZE):
				set_piece(x, y, "", true)

		if not replay_pre_board_data.is_empty():
			for i in range(replay_pre_board_data.size()):
				var piece_value = replay_pre_board_data[i]
				var replay_x = i % BOARD_SIZE
				@warning_ignore("integer_division")
				var replay_y = i / BOARD_SIZE
				
				var godot_x = replay_x
				var godot_y = (BOARD_SIZE - 1) - replay_y
				
				var symbol = ""
				if piece_value == 2:
					symbol = "⚪"
				elif piece_value == 1:
					symbol = "⚫"

				print("Setting piece at (", godot_x, ",", godot_y, ") with symbol: ", symbol)
				
				if symbol != "":
					set_piece(godot_x, godot_y, symbol, true)
	else:
		print("Parsed has no valid pre_board. Initializing default board.")
		initialize_board_pieces()
	update_piece_counts()
	
	await get_tree().create_timer(0.4).timeout

	if "move" in parsed and parsed["move"] is Array:
		print("Parsed contains move data")
		for move_data in parsed["move"]:
			print("Processing move: ", move_data)
			if move_data is Array and move_data.size() >= 3:
				var col = int(move_data[0])
				var row_from_replay = int(move_data[1])
				replay_val = int(move_data[2])

				var row = (BOARD_SIZE - 1) - row_from_replay

				replay_symbol = ""
				if replay_val == 2:
					replay_symbol = "⚪"
				elif replay_val == 1:
					replay_symbol = "⚫"
				else:
					print("Invalid replay_val: ", replay_val)
					continue
				
				print("Move at col: ", col, ", row: ", row, ", symbol: ", replay_symbol)

				var directions_to_flip = get_flippable_directions(col, row, replay_symbol)
				print("Directions to flip: ", directions_to_flip)

				if not directions_to_flip.is_empty():
					print("Flipping pieces for move")
					flip_pieces(col, row, replay_symbol, directions_to_flip)
					set_piece(col, row, replay_symbol, false)

					await get_tree().create_timer(0.5).timeout
					update_piece_counts()
				else:
					print("No pieces to flip for this move")
			else:
				print("Invalid move_data format: ", move_data)
	else:
		print("Parsed has no valid moves array")

	replay_played = true
	pre_board_data = get_current_board_as_array()

	print("Replay played, checking turn and game over status")
	if not game_over and is_my_turn:
		print("Highlighting valid moves and showing send button")
		highlight_valid_moves()
		send_button.visible = true
	else:
		print("Game Over State: ", game_over, " | Is My Turn: ", is_my_turn)
		set_highlight_visibility(false)
		send_button.visible = false

func parse_replay(replay_string: String) -> Dictionary:
	OpLog.d(LOG_TAG, ["parse_replay start len=", replay_string.length()])

	var result = {"move": []}
	var elements = replay_string.split("|")

	for i in range(elements.size()):
		var elem = elements[i]
		var spl = elem.split(":")

		if spl.size() < 2:
			continue

		var type = spl[0]
		var data_str = spl[1]

		if type == "board":
			var state_key = "pre_board"
			if "pre_board" in result:
				state_key = "post_board"

			var board_data: Array[int] = []
			var state_spl = data_str.split(",")

			if not state_spl.is_empty():
				for val_str in state_spl:
					if not val_str.is_empty():
						board_data.append(int(val_str))
					else:
						OpLog.w(LOG_TAG, ["parse_replay skipped_empty_board_value index=", i])
			else:
				OpLog.w(LOG_TAG, ["parse_replay empty_board_split index=", i])

			result[state_key] = board_data
			OpLog.d(LOG_TAG, [state_key, "_size=", board_data.size()])

		elif type == "move":
			var move = []
			var move_spl = data_str.split(",")

			if move_spl.size() >= 3:
				for val in move_spl:
					move.append(float(val))
				result["move"].append(move)
				OpLog.d(LOG_TAG, ["parse_replay move=", move])
			else:
				OpLog.w(LOG_TAG, ["parse_replay bad_move_data data=", data_str])
		else:
			OpLog.w(LOG_TAG, ["parse_replay unknown_type=", type])

	OpLog.i(LOG_TAG, [
		"parse_replay done moves=", result["move"].size(),
		" has_pre=", "pre_board" in result,
		" has_post=", "post_board" in result
	])

	return result

func _preview_flip_visual(x: int, y: int, to_symbol: String) -> void:
	var cell: Control = board[y][x] as Control
	_ensure_piece_nodes(cell)
	var piece := cell.get_node("Piece") as TextureRect
	var current_symbol := get_piece(x, y)
	if current_symbol != "":
		piece.visible = true
		piece.modulate = _piece_color_for(current_symbol)
	else:
		return
	var target_color := _piece_color_for(to_symbol)
	if piece.modulate == target_color:
		return
	piece.pivot_offset = piece.size / 2.0
	var tw := create_tween()
	tw.tween_property(piece, "scale:y", 0.06, 0.09).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): piece.modulate = target_color)
	tw.tween_property(piece, "scale:y", 1.0, 0.11).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(piece, "scale:x", 1.06, 0.06).set_ease(Tween.EASE_OUT)
	tw.tween_property(piece, "scale:x", 1.0, 0.08).set_ease(Tween.EASE_IN)
	
func preview_flip_pieces(x: int, y: int, player_symbol_to_check: String):
	_clear_all_preview_overlays()
	place_temp_piece_visual(x, y, player_symbol_to_check)
	var directions = get_flippable_directions(x, y, player_symbol_to_check)
	for dir in directions:
		var pos = Vector2i(x, y) + dir
		while is_in_bounds(pos):
			var piece_symbol := get_piece(pos.x, pos.y)
			if piece_symbol == player_symbol_to_check:
				break
			elif piece_symbol == "":
				break
			else:
				_preview_flip_visual(pos.x, pos.y, player_symbol_to_check)
			pos += dir

func on_cell_pressed(x: int, y: int) -> void:
	if not is_my_turn or game_over:
		OpLog.d(LOG_TAG, [
			"cell_press_ignored x=", x,
			" y=", y,
			" is_my_turn=", is_my_turn,
			" game_over=", game_over
		])
		return

	var current_piece = get_piece(x, y)
	var directions = get_flippable_directions(x, y, player_symbol)

	if current_piece != "" or directions.size() == 0:
		OpLog.d(LOG_TAG, [
			"invalid_move x=", x,
			" y=", y,
			" current_piece=", current_piece,
			" directions=", directions.size(),
			" symbol=", player_symbol
		])
		return

	OpLog.event(LOG_TAG, [
		"move_selected x=", x,
		" y=", y,
		" symbol=", player_symbol,
		" directions=", directions.size()
	])

	var empty_count = 0
	for ty in range(BOARD_SIZE):
		for tx in range(BOARD_SIZE):
			if get_piece(tx, ty) == "":
				empty_count += 1

	if empty_count == 1:
		if temp_piece_active:
			reset_board_to_pre_data()
			clear_temp_piece_visual()
		
		flip_pieces(x, y, player_symbol, directions)
		set_piece(x, y, player_symbol, true)
		
		temp_piece_active = false
		update_piece_counts()
		
		await get_tree().create_timer(0.5).timeout
		
		_internal_submit_move(x, y)
	else:
		if temp_piece_active and temp_piece_x == x and temp_piece_y == y:
			return

		if temp_piece_active:
			reset_board_to_pre_data()
			clear_temp_piece_visual()
		
		temp_piece_x = x
		temp_piece_y = y
		temp_piece_active = true
		preview_flips_active = true

		place_temp_piece_visual(x, y, player_symbol)
		preview_flip_pieces(x, y, player_symbol)
		
		var base_counts = update_piece_counts()
		var flipped_count = 0
		for dir in directions:
			var pos = Vector2i(x, y) + dir
			while is_in_bounds(pos) and get_piece(pos.x, pos.y) != "" and get_piece(pos.x, pos.y) != player_symbol:
				flipped_count += 1
				pos += dir
		
		if player == 1:
			player_count_label.text = str(base_counts["black"] + flipped_count)
			opp_count_label.text = str(base_counts["white"] - flipped_count)
		else:
			player_count_label.text = str(base_counts["white"] + flipped_count)
			opp_count_label.text = str(base_counts["black"] - flipped_count)

		animate_button_slide_up()
		
func _internal_submit_move(final_x: int, final_y: int):
	post_board_data = get_current_board_as_array()
	send_game(final_x, final_y)
	
func on_send_button_pressed():
	if not temp_piece_active or temp_piece_x == -1:
		return

	if game_over or spectator_mode or not is_my_turn:
		animate_button_slide_down()
		return

	set_highlight_visibility(false)
	reset_board_to_pre_data()
	clear_temp_piece_visual()
	preview_flips_active = false

	var directions_to_flip = get_flippable_directions(temp_piece_x, temp_piece_y, player_symbol)
	if directions_to_flip.is_empty():
		temp_piece_active = false
		send_button.visible = false
		highlight_valid_moves()
		return

	flip_pieces(temp_piece_x, temp_piece_y, player_symbol, directions_to_flip)
	set_piece(temp_piece_x, temp_piece_y, player_symbol, true)
	temp_piece_active = false
	update_piece_counts()

	post_board_data = get_current_board_as_array()

	print("Pre board data: ", pre_board_data)
	print("Post board data: ", post_board_data)

	send_game(temp_piece_x, temp_piece_y)

	temp_piece_x = -1
	temp_piece_y = -1
	
func send_game(final_x: int, final_y: int) -> void:
	if spectator_mode:
		OpLog.w(LOG_TAG, ["send_game_blocked spectator=true x=", final_x, " y=", final_y])
		return

	var move_arr = [final_x, 7 - final_y, player]

	my_moves.clear()
	my_moves.append(move_arr)

	var moves_str = ""
	for move in my_moves:
		moves_str += "move:" + str(move[0]) + "," + str(move[1]) + "," + str(move[2])

	var result = {
		"replay": "board:" + ",".join(pre_board_data) + "|" + moves_str + "|" + "board:" + ",".join(post_board_data)
	}

	avatar_key = "avatar" + str(player)

	if player != 0 and is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		var avatar_string = player_avatar_display.get_avatar_data_string()
		result[avatar_key] = avatar_string
		OpLog.d(LOG_TAG, ["send_game avatar_added key=", avatar_key])

	if check_win():
		if win_loss_state != "":
			result["winner"] = my_uuid + "|" + win_loss_state
			OpLog.event(LOG_TAG, [
				"send_game_winner winner=", result["winner"],
				" white_score=", white_score,
				" black_score=", black_score
			])
	else:
		play_sent_animation()

	var game_data = JSON.stringify(result)

	OpLog.event(LOG_TAG, [
		"send_game_out move=", move_arr,
		" player=", player,
		" symbol=", player_symbol,
		" pre_board_size=", pre_board_data.size(),
		" post_board_size=", post_board_data.size(),
		" raw=", game_data
	])

	send_game_data(game_data)

	my_moves.clear()
	animate_button_slide_down()
	is_my_turn = false

	if game_over:
		stop_waiting_animation()

func play_sent_animation():
	if not is_instance_valid(sent_label) or game_over or spectator_mode:
		stop_waiting_animation()
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
	
func animate_button_slide_up():
	if button_tween and button_tween.is_running():
		button_tween.kill()
	
	send_button.visible = true
	button_tween = create_tween()
	button_tween.tween_property(send_button, "position:y", send_button_target_y_position, 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func animate_button_slide_down():
	if button_tween and button_tween.is_running():
		button_tween.kill()

	var offscreen_bottom_y = $MainVBoxContainer.size.y + BUTTON_OFFSCREEN_OFFSET

	button_tween = create_tween()
	button_tween.tween_property(send_button, "position:y", offscreen_bottom_y, 0.6)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	button_tween.tween_callback(func():
		send_button.visible = false
	)

func set_highlight_visibility(_visible: bool):
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var cell = board[y][x]
			if cell:
				var highlight = cell.find_child("Highlight")
				if highlight:
					highlight.visible = _visible

func place_temp_piece_visual(x: int, y: int, symbol: String):
	if is_in_bounds(Vector2i(x, y)):
		var cell = board[y][x]
		_show_temp_piece(cell, symbol)

func clear_temp_piece_visual():
	_clear_all_preview_overlays()
	if temp_piece_x != -1 and is_in_bounds(Vector2i(temp_piece_x, temp_piece_y)):
		var cell = board[temp_piece_y][temp_piece_x]
		_clear_temp_piece(cell)

func has_any_empty_cells() -> bool:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if get_piece(x, y) == "":
				return true
	return false

func handle_turn_transition():
	print("948 Call Update Count")
	update_piece_counts()
	if not has_any_empty_cells():
		highlight_valid_moves()
		return

func is_valid_move(x: int, y: int, player_symbol_to_check: String) -> bool:
	return get_flippable_directions(x, y, player_symbol_to_check).size() > 0

func flip_pieces(x: int, y: int, player_symbol_to_check: String, directions: Array) -> void:
	for dir in directions:
		var pos = Vector2i(x, y) + dir
		while is_in_bounds(pos) and get_piece(pos.x, pos.y) != player_symbol_to_check:
			set_piece(pos.x, pos.y, player_symbol_to_check, false)
			pos += dir

func get_flippable_directions(x: int, y: int, player_symbol_to_check: String) -> Array:
	var opponent = "⚪" if player_symbol_to_check == "⚫" else "⚫"
	var directions = []
	if get_piece(x, y) != "":
		return directions
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var dir = Vector2i(dx, dy)
			var pos = Vector2i(x + dx, y + dy)
			if not is_in_bounds(pos) or get_piece(pos.x, pos.y) != opponent:
				continue
			pos += dir
			while is_in_bounds(pos):
				var piece = get_piece(pos.x, pos.y)
				if piece == player_symbol_to_check:
					directions.append(dir)
					break
				elif piece == "":
					break
				pos += dir
	return directions

func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_SIZE and pos.y >= 0 and pos.y < BOARD_SIZE

func create_radial_gradient_texture(_size: int = 64) -> Texture2D:
	var image = Image.create(_size, _size, false, Image.FORMAT_RGBA8)
	@warning_ignore("integer_division")
	var center = Vector2(_size / 2, _size / 2)
	var max_dist = center.length()
	for y in _size:
		for x in _size:
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center) / max_dist
			var alpha = clamp(pow(dist,1.5), 0.0, 0.4)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(image)
	
func _get_rules_text() -> String:
	return """
[font_size={18px}]
1. Players take turns placing their colored discs on the board.
2. When you place a disc, any opponent's discs that are in a straight line (horizontally, vertically, or diagonally) between your new disc and an existing disc of your color are "flipped" to your color.
3. You must flip at least one disc to make a valid move.
4. If a player cannot make a valid move, they pass their turn.
5. The game ends when neither player can make a valid move (usually when the board is full).
6. The player with the most discs on the board wins!
[/font_size]
"""
