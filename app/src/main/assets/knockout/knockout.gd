extends Control

# --- Preloaded Assets ---
const PieceScene := preload("res://knockout/piece.tscn")
const P1_PIECE_TEX := preload("res://knockout/bw_penguin.png")
const P2_PIECE_TEX := preload("res://knockout/gw_penguin.png")
const BLACK_PRESERVER_TEX := preload("res://knockout/life_prev_black.png")
const GRAY_PRESERVER_TEX := preload("res://knockout/life_prev_gray.png")

const RULES_POPUP_SCENE = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE = preload("res://global/settings_popup.tscn")
const AvatarWinAnimScene := preload("res://global/avatar_textures/avatar_win_anim.tscn")


# --- UI and Game Node References ---
@onready var game_board := %GameBoard
@onready var board_zoom : Control = %BoardZoom
@onready var player_avatar_display = %PlayerAvatarDisplay
@onready var opp_avatar_display = %OppAvatarDisplay
@onready var background = %Background
@onready var send_button: Button = %SendButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: ColorRect = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var win_loss_label = %WinLossLabel
@onready var rules_button = %RulesButton
@onready var settings_button = %SettingsButton
@onready var spec_label = %SpecLabel
@onready var you_label = %YouLabel
@onready var piece_container := %PieceContainer # Container for penguin pieces
@onready var left_preserver := %LeftPreserver   # TextureRect for player 1 status
@onready var right_preserver := %RightPreserver  # TextureRect for player 2 status

const LOGICAL_BOARD_SIZE := Vector2(300, 300) # protocol / replay space
const ZOOM_AIM   := 2.0  # how large to look when aiming (tweak)
const ZOOM_PLAY  := 1.5  # how large to look during physics (tweak)
const ZOOM_DUR   := 0.22 # seconds

# --- Replay state ---
var last_pre_round: Dictionary = {}      # {"round": int, "pieces": Array[Dictionary]}
var last_post_round: Dictionary = {}     # same shape; board #2 (or #3) snapshot after physics
var current_round_index: int = 0

const POWER_TO_IMPULSE: float = 6.0      # must match piece.gd feel
const ROUND_SNAP_AFTER: float = 1.4      # seconds: snap to post board after physics play (optional)
const PIECE_RADIUS: float = 24.0  # must match your piece CollisionShape2D
const DEV_REPLAY_STRING := "board:2#77.861351,66.122459,1,-0.876164,-2.354301,104.423691#23.355244,93.006905,2,1.830075,-1.580594,61.118755#-4.830564,36.334606,2,2.219335,0.272333,38.293098#-18.615202,-35.732677,2,2.316064,0.583284,79.135498#99.505798,94.505386,2,2.833030,-1.843283,72.001610|shoot:1|board:3#68.967499,51.041775,1,-0.956223,-2.354301,0.000000#50.799763,68.490479,2,0.031407,-1.832990,21.633646#-33.968060,-1.493485,2,1.201969,0.854556,49.784225#22.491690,-81.952728,2,2.664457,1.825102,79.211861#64.293983,-6.814495,2,-0.272487,1.906639,43.372223|board:3#68.967499,51.041775,1,-0.956223,-2.354301,0.000000#50.799763,68.490479,2,0.031407,-1.832990,21.633646#-33.968060,-1.493485,2,1.201969,0.854556,49.784225#22.491690,-81.952728,2,2.664457,1.825102,79.211861#64.293983,-6.814495,2,-0.272487,1.906639,43.372223"

var _water_kill_areas: Array[Area2D] = []
var _safe_polys_global: Array[PackedVector2Array] = [] # shrunken iceberg polygons in global coords
var _base_iceberg_poly: PackedVector2Array = [] # Add this line to store the original shape


# --- Game State Variables ---
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
var game_settings_category: String

var game_ended = false
var game_over = false
var _board_initialized: bool = false
var _pending_replay_str: String = ""
var _replay_in_progress: bool = false
var tween: Tween
var win_loss_state = ""
var has_connected: bool = false
var is_your_turn: bool = false
var is_my_turn: bool = false
var _is_zooming: bool = false
var my_player
var my_player_id
var _kill_guard_until_msec: int = 0
var spectator_mode: bool = false
var avatar_key = 0
var player = 1
var sent_tween: Tween
var dot_count = 0

var pre_board_data: Array = []
var post_board_data: Array = []

const AUTO_BOUNDS_GROUP := "board_bounds_auto" # for easy cleanup of generated nodes

func _poly_area(poly: PackedVector2Array) -> float:
	var n := poly.size()
	if n < 3:
		return 0.0
	var sum: float = 0.0
	for i in n:
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % n]
		sum += p.x * q.y - q.x * p.y
	return absf(sum) * 0.5


# Where the texture is actually drawn inside the TextureRect (accounts for keep-aspect modes)
func _texrect_draw_rect(texr: TextureRect, img: Image) -> Rect2:
	var tex_size: Vector2 = Vector2.ZERO
	if img and not img.is_empty():
		tex_size = Vector2(img.get_width(), img.get_height())
	elif texr.texture:
		# Ensure Vector2 (Texture2D.get_size() may be Vector2i)
		tex_size = Vector2(texr.texture.get_size())

	# No texture? Just say it fills the control.
	if tex_size == Vector2.ZERO:
		return Rect2(Vector2.ZERO, texr.size)

	var draw_pos: Vector2 = Vector2.ZERO
	var draw_size: Vector2 = texr.size

	match texr.stretch_mode:
		TextureRect.STRETCH_SCALE:
			draw_pos = Vector2.ZERO
			draw_size = texr.size

		TextureRect.STRETCH_TILE:
			# Tiled over control; for our mapping treat like fill.
			draw_pos = Vector2.ZERO
			draw_size = texr.size

		TextureRect.STRETCH_KEEP:
			draw_pos = Vector2.ZERO
			draw_size = tex_size

		TextureRect.STRETCH_KEEP_CENTERED:
			draw_size = tex_size
			draw_pos = (texr.size - draw_size) * 0.5

		TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var img_aspect: float = tex_size.x / max(1.0, tex_size.y)
			var rect_aspect: float = texr.size.x / max(1.0, texr.size.y)

			if img_aspect > rect_aspect:
				draw_size.x = texr.size.x
				draw_size.y = texr.size.x / img_aspect
			else:
				draw_size.y = texr.size.y
				draw_size.x = texr.size.y * img_aspect

			draw_pos = Vector2.ZERO
			if texr.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
				draw_pos = (texr.size - draw_size) * 0.5

		TextureRect.STRETCH_KEEP_ASPECT_COVERED:
			# Fill (may crop), centered.
			var img_aspect: float = tex_size.x / max(1.0, tex_size.y)
			var rect_aspect: float = texr.size.x / max(1.0, texr.size.y)

			if img_aspect > rect_aspect:
				draw_size.y = texr.size.y
				draw_size.x = texr.size.y * img_aspect
			else:
				draw_size.x = texr.size.x
				draw_size.y = texr.size.x / img_aspect

			draw_pos = (texr.size - draw_size) * 0.5

		_:
			draw_pos = Vector2.ZERO
			draw_size = texr.size

	return Rect2(draw_pos, draw_size)

# This function now ONLY calculates the base shape of the iceberg once.
func _build_safe_poly_from_png(alpha_threshold: float = 0.1, simplify_epsilon: float = 1.5) -> void:
	# This function now ONLY calculates the base shape of the iceberg.
	_base_iceberg_poly.clear()

	var texrect := game_board.get_node_or_null("TextureRect") as TextureRect
	if not is_instance_valid(texrect) or not is_instance_valid(texrect.texture): return

	var img: Image = texrect.texture.get_image()
	if img.is_empty(): return

	var bm := BitMap.new()
	bm.create_from_image_alpha(img, alpha_threshold)

	var rect_img := Rect2i(Vector2i.ZERO, img.get_size())
	var contours: Array[PackedVector2Array] = bm.opaque_to_polygons(rect_img, simplify_epsilon)
	if contours.is_empty(): return

	var best := contours[0]
	var best_area := _poly_area(best)
	for poly in contours:
		var current_area := _poly_area(poly)
		if current_area > best_area:
			best = poly
			best_area = current_area # FIX: Was "best_area = a"
	
	_base_iceberg_poly = best
	
	# Use the new helper function to print the bounds
	var bounding_rect := _get_poly_bounds(best)
	print("BASE POLYGON BUILT (Image Coords): %s" % bounding_rect)
	
func _get_poly_bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	
	var min_pos := poly[0]
	var max_pos := poly[0]
	for i in range(1, poly.size()):
		var p := poly[i]
		min_pos.x = min(min_pos.x, p.x)
		min_pos.y = min(min_pos.y, p.y)
		max_pos.x = max(max_pos.x, p.x)
		max_pos.y = max(max_pos.y, p.y)
	
	return Rect2(min_pos, max_pos - min_pos)

# This function is now simpler and just triggers the base shape calculation.
func _rebuild_safe_polys() -> void:
	_build_safe_poly_from_png(0.1, 1.5)


# This function now handles everything in real-time, ensuring perfect sync.
func _physics_process(_delta: float) -> void:
	# --- Top-level guards ---
	if not _board_initialized: return
	if Time.get_ticks_msec() < _kill_guard_until_msec: return
	
	# Pause kill checks during zoom animations.
	if _is_zooming: return

	# If we haven't traced the base shape yet, we can't do anything.
	if _base_iceberg_poly.is_empty(): return
		
	# --- Real-time Polygon Generation for This Frame ---
	var texrect := game_board.get_node_or_null("TextureRect") as TextureRect
	if not is_instance_valid(texrect): return

	# 1. Get the texture's current transform for this frame
	var tex_draw_rect: Rect2 = _texrect_draw_rect(texrect, null)
	var img_size := Vector2(texrect.texture.get_size())
	var tex_scale := tex_draw_rect.size / img_size
	var xf: Transform2D = texrect.get_global_transform()

	# 2. Build the polygon's visual shape based on the current transform
	var gpoly := PackedVector2Array()
	for v_img in _base_iceberg_poly:
		var local_in_tr := tex_draw_rect.position + (v_img * tex_scale)
		gpoly.append(xf * local_in_tr)
	
	# 3. Calculate the offset to align the visual polygon with the physics container
	var offset: Vector2 = piece_container.global_position - game_board.global_position
	var translated_poly := PackedVector2Array()
	for point in gpoly:
		translated_poly.append(point + offset)
		
	# 4. Expand the aligned polygon by the piece radius
	var expansion_amount := PIECE_RADIUS * _current_zoom()
	var final_poly_array: Array = Geometry2D.offset_polygon(translated_poly, expansion_amount)
	
	if not final_poly_array.is_empty():
		_safe_polys_global = final_poly_array
			
	# --- Kill Check Logic (using the freshly generated polygon) ---
	if not _safe_polys_global.is_empty():
		for n in piece_container.get_children():
			if n is RigidBody2D:
				var rb := n as RigidBody2D
				if not rb.has_meta("dying") and not _point_in_any_safe_poly(rb.global_position):
					print("KILLING PIECE: %s at global_pos %s" % [rb.name, rb.global_position])
					_kill_piece(rb)
# --- Godot Lifecycle & Setup ---

func _ready():
	# --- Initial Setup (UI, Timers, Buttons) ---
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)
	background.z_index = -10 # Add this line
	randomize()
	print("Knockout Scene ready!")

	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)

	if is_instance_valid(send_button):
		send_button.visible = true
		send_button.pressed.connect(send_game)
	else:
		push_warning("No %SendButton in scene")

	if rules_button:    rules_button.pressed.connect(on_rules_button_pressed)
	if settings_button: settings_button.pressed.connect(_on_settings_button_pressed)

	_wire_water_kill_areas()

	# --- Board Initialization Sequence ---
	if is_instance_valid(board_zoom):
		# 1. Prevent parent containers from resizing this node.
		board_zoom.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		board_zoom.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		# 2. Set a stable base size for the board.
		board_zoom.custom_minimum_size = LOGICAL_BOARD_SIZE

		# 3. Disable content clipping to make scaling visible.
		board_zoom.clip_contents = false

		# 4. Apply the initial scale and pivot.
		board_zoom.scale = Vector2.ONE * ZOOM_AIM
		board_zoom.pivot_offset = board_zoom.custom_minimum_size * 0.5
		board_zoom.resized.connect(func():
			board_zoom.pivot_offset = board_zoom.size * 0.5
		)
	
	piece_container.position = board_zoom.custom_minimum_size * 0.5
	
	# 5. Wait for one frame for all visual changes to be processed by the engine.
	await get_tree().process_frame

	# 6. Now that the board is visually stable, build dependent elements.
	_rebuild_safe_polys()

	var texrect := game_board.get_node_or_null("TextureRect") as TextureRect
	if texrect:
		texrect.resized.connect(func(): _rebuild_safe_polys())
	get_viewport().size_changed.connect(func(): _rebuild_safe_polys())

	# 7. The board is officially ready. It's now safe to add pieces.
	_board_initialized = true
	print("Board initialized and scaled.")

	# 8. If any data arrived very early, process it now.
	if _pending_replay_str != "":
		parse_replay_string(_pending_replay_str)
		_pending_replay_str = ""

	# 9. Finally, connect to the data source to get piece information.
	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("AppPlugin Available")
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
	else:
		# The dev payload is also loaded only AFTER the board is fully initialized.
		var dev_payload := {
			"isYourTurn": true,
			"player": "1",
			"myPlayerId": "player1_id",
			"player1": "player1_id",
			"replay": DEV_REPLAY_DOWN
		}
		_set_game_data(JSON.stringify(dev_payload))

func _update_all_piece_visuals() -> void:
	if not is_instance_valid(board_zoom): return
	
	for piece in piece_container.get_children():
		if not piece is RigidBody2D: continue
		
		# Get the piece's logical position (which we'll store in metadata)
		var logical_pos = piece.get_meta("logical_pos", piece.position)
		
		# Update the actual position by scaling the logical position
		piece.position = logical_pos
		
		# Update the visual scale of the sprite
		#var sprite = piece.find_child("Sprite2D", true, false)
		#if sprite and sprite.texture:
			#var texture_size = sprite.texture.get_size()
			#var desired_visual_size = Vector2(48.0, 48.0) * current_scale
			#sprite.scale = desired_visual_size / texture_size

func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color(0.08, 0.08, 0.08) if is_dark else Color("#68d4f6")

# --- Game Data Handling ---

func _set_game_data(new_game_data_json: String):
	var parsed = JSON.parse_string(new_game_data_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	_stop_all_highlights()
	stop_waiting_animation()

	var data: Dictionary = parsed
	is_your_turn = data.get("isYourTurn", false)
	print("INCOMING RAW DATA: ", data)
	var replay_str: String = data.get("replay", "")
	var player1_id: String = data.get("player1", "")
	var player2_id: String = data.get("player2", "")
	my_player_id = data.get("myPlayerId", "")
	var opponent_avatar_key = ""

	# ownership/spectator logic (unchanged)
	if my_player_id == player1_id or my_player_id == player2_id or player1_id == "":
		is_my_turn = is_your_turn
		if my_player_id == player1_id:
			player = 1; opponent_avatar_key = "avatar2"
		elif my_player_id == player2_id:
			player = 2; opponent_avatar_key = "avatar1"
		else:
			player = 1
	else:
		spectator_mode = true
		you_label.text = ""
		is_my_turn = false
		spec_label.show()
		player = 1

	if player == 1:
		left_preserver.texture = BLACK_PRESERVER_TEX
		right_preserver.texture = GRAY_PRESERVER_TEX
	else:
		left_preserver.texture = GRAY_PRESERVER_TEX
		right_preserver.texture = BLACK_PRESERVER_TEX

	if opponent_avatar_key != "" and data.has(opponent_avatar_key):
		var avatar_string = data[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		if is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	# 🔒 Gate piece spawning until the board has finished building.
	if replay_str != "":
		if _board_initialized:
			parse_replay_string(replay_str)
		else:
			_pending_replay_str = replay_str
	else:
		print("New Game - No replay string found.")

	call_deferred("_apply_turn_highlights_based_on_arrows")
	_update_piece_interactivity()

	if not is_my_turn and not game_over and not spectator_mode:
		start_waiting_animation()

func send_game() -> void:
	print("[Send] send_game() called")
	_stop_all_highlights()
	await get_tree().process_frame

	var replay_string_to_send := ""
	if DEV_USE_HARDCODED_REPLAY:
		match DEV_REPLAY_MODE:
			"corners":
				replay_string_to_send = DEV_REPLAY_CORNERS
			"down":
				replay_string_to_send = DEV_REPLAY_DOWN
			"right":
				replay_string_to_send = DEV_REPLAY_RIGHT
			"left":
				replay_string_to_send = DEV_REPLAY_LEFT
			"up":
				replay_string_to_send = DEV_REPLAY_UP
			"all_dirs":
				replay_string_to_send = DEV_REPLAY_ALL_DIRS
			_:
				# default backstop
				replay_string_to_send = DEV_REPLAY_CORNERS
		print("[Send][DEV] Using DEV_REPLAY_MODE='%s'." % DEV_REPLAY_MODE)
	else:
		# Use your real game-state serialization (assumes you added this helper earlier).
		# If you don't have it yet, you can keep your previous builder here.
		replay_string_to_send = _build_replay_string()

	var payload: Dictionary = { "replay": replay_string_to_send }

	avatar_key = ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = player_avatar_display.get_avatar_data_string()

	# Evaluate end state (optional; you can keep as-is)
	game_ended = await check_win()
	if game_ended and win_loss_state != "":
		payload["winner"] = my_player_id + "|" + win_loss_state

	print("[Send] PAYLOAD: ", payload)
	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(JSON.stringify(payload))
	else:
		print("AppPlugin is null. Cannot send game data.")

	is_my_turn = false
	_update_piece_interactivity()
	if not game_over:
		play_sent_animation()
		
func _log_replay_preview(label: String, s: String) -> void:
	var preview := s
	if preview.length() > 220:
		preview = preview.substr(0, 220) + "..."
	print("[%s] replay (%d chars): %s" % [label, s.length(), preview])

		
func _build_replay_string() -> String:
	var round_num := 1
	if last_pre_round.has("round"):
		round_num = int(last_pre_round["round"]) + 1

	# Pre-board with current aim/power, then instruct to simulate,
	# then a post "stub" board (same positions format, power=0)
	var pre_board := _serialize_current_board(round_num, false)
	var post_board := _serialize_current_board(round_num + 1, true)
	return "%s|shoot:1|%s" % [pre_board, post_board]


func _serialize_current_board(round_num: int, zero_power: bool) -> String:
	var parts := PackedStringArray()

	for n in piece_container.get_children():
		if not (n is RigidBody2D): continue
		if n.has_meta("dying") and n.get_meta("dying"): continue

		var b := n as Node2D
		var pos: Vector2 = b.position  # <-- no / current_scale
		var owner_id := int(n.get_meta("player", -1))

		var rot_rad := b.rotation
		var shoot_dir_deg := float(n.get_meta("shoot_dir", rad_to_deg(rot_rad)))
		var shoot_dir_rad := deg_to_rad(shoot_dir_deg)
		var power_val := 0.0 if zero_power else float(n.get_meta("power", 0.0))

		parts.append("%s,%s,%d,%s,%s,%s" % [
			String.num(pos.x, 6),
			String.num(-pos.y, 6),
			owner_id,
			String.num(-rot_rad, 6),
			String.num(-shoot_dir_rad, 6),
			String.num(power_val, 6),
		])

	var body := "#".join(parts)
	return "board:%d%s%s" % [round_num, "#" if body.length() > 0 else "", body]

# --- Replay Parsing & Board Setup ---

func _update_piece_interactivity() -> void:
	for piece in piece_container.get_children():
		if piece.has_method("set_controlled_by_me"):
			var owner_id: int = int(piece.get_meta("player", -1))
			var can_control: bool = (owner_id == player) and is_my_turn and (not spectator_mode) and (not game_over)
			piece.set_controlled_by_me(can_control)

func parse_replay_string(replay: String) -> void:
	var chunks: PackedStringArray = replay.split("|", false)
	var boards: Array[Dictionary] = []
	var shoot_flag := false

	for raw in chunks:
		var tok := raw.strip_edges()
		if tok.begins_with("board:"):
			var body := tok.substr(6)
			var bd := _parse_board_chunk(body)
			if bd.has("pieces") and (bd["pieces"] as Array).size() > 0:
				boards.append(bd)
		elif tok.begins_with("shoot:"):
			shoot_flag = int(tok.substr(6).strip_edges()) == 1

	if boards.is_empty():
		push_warning("Replay had no valid boards.")
		return

	# Always set the board from the FIRST board only
	last_pre_round = boards[0]
	_setup_board_from_board_dict(last_pre_round)

	# If shoot:1 is present, *play* from the pre-board (no snapping to post)
	if shoot_flag:
		await _play_round_from_replay(last_pre_round)
	
# Parse "<round>#x,y,player,rot,dir,power#..." into {"round":int, "pieces":[...]}
func _parse_board_chunk(body: String) -> Dictionary:
	var round_num: int = 0
	var rest: String = body

	var hash_idx: int = body.find("#")
	if hash_idx >= 0:
		var maybe_round: String = body.substr(0, hash_idx)
		if maybe_round.is_valid_int():
			round_num = int(maybe_round)
			rest = body.substr(hash_idx + 1)
	else:
		rest = body

	var parsed_pieces: Array[Dictionary] = []
	var piece_strings: PackedStringArray = rest.split("#", false)  # <- use PackedStringArray
	for pstr in piece_strings:
		var params: PackedStringArray = pstr.split(",", false)      # <- use PackedStringArray
		if params.size() == 6:
			# Convert from external (Y-up) to Godot's internal (Y-down) coordinates
			var d: Dictionary = {
				"pos": Vector2(params[0].to_float(), -params[1].to_float()), # Negate Y position
				"player": params[2].to_int(),
				"rotation": -params[3].to_float(), # Negate rotation angle
				"shoot_dir": -params[4].to_float(), # Negate shoot direction angle
				"power": params[5].to_float()
			}
			parsed_pieces.append(d)

	return { "round": round_num, "pieces": parsed_pieces }
	
func _current_zoom() -> float:
	if is_instance_valid(board_zoom):
		var s := board_zoom.get_global_transform().get_scale()
		return (s.x + s.y) * 0.5
	return 1.0
	
func _apply_zoom(target_scale: float, dur: float = ZOOM_DUR) -> void:
	if not is_instance_valid(board_zoom): return
	if game_over: return

	_is_zooming = true # START zooming
	var tw := create_tween()
	tw.tween_property(board_zoom, "scale", Vector2.ONE * target_scale, dur)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	_is_zooming = false # STOP zooming

	_rebuild_safe_polys()

func enter_aim_view() -> void:
	print("581 Call")
	await _apply_zoom(ZOOM_AIM)

func enter_play_view() -> void:
	await _apply_zoom(ZOOM_PLAY)

func _setup_board_if_needed_for_pre(pre_board: Dictionary) -> void:
	# If we already spawned the right number of pieces, we can just update pose.
	var _pieces: Array = pre_board.get("pieces", [])
	if piece_container.get_child_count() == 0:
		_setup_board_from_board_dict(pre_board)
	else:
		_apply_pre_board_pose(pre_board)

func _setup_board_from_board_dict(bd: Dictionary) -> void:
	var arr: Array = bd.get("pieces", [])
	_setup_board_from_data(arr)

func _apply_pre_board_pose(bd: Dictionary) -> void:
	var arr: Array = bd.get("pieces", [])
	var children: Array[Node] = piece_container.get_children()
	var count: int = min(children.size(), arr.size())
	for i in count:
		var piece_node := children[i]
		var pd: Dictionary = arr[i]
		# The piece's local position is now just its data position. No offsets needed.
		var target_pos: Vector2 = pd["pos"] as Vector2
		var target_rot: float = float(pd["rotation"])  # radians

		if piece_node is RigidBody2D:
			var rb := piece_node as RigidBody2D
			rb.freeze = true
			# We set the local position, not the global_position.
			rb.position = target_pos
			rb.rotation = target_rot
			rb.linear_velocity = Vector2.ZERO
			rb.angular_velocity = 0.0
			rb.freeze = false
		else:
			piece_node.position = target_pos
			piece_node.rotation = target_rot

func _parse_board_data(board_string: String) -> Array[Dictionary]:
	var parsed_pieces: Array[Dictionary] = []
	if board_string.is_empty() or board_string == "0":
		return parsed_pieces

	var piece_strings: Array = board_string.split("#")
	for piece_str in piece_strings:
		if piece_str.is_empty():
			continue

		var params: Array = piece_str.split(",")
		if params.size() == 6:
			var piece_data := {
				"pos": Vector2(params[0].to_float(), params[1].to_float()),
				"player": params[2].to_int(),
				"rotation": params[3].to_float(),
				"shoot_dir": params[4].to_float(),
				"power": params[5].to_float()
			}
			parsed_pieces.append(piece_data)
		else:
			push_warning("Invalid piece data format, expected 6 params: " + piece_str)

	return parsed_pieces



func _setup_board_from_data(board_data: Array[Dictionary]) -> void:
	# Guard: never spawn before board is ready.
	if not _board_initialized:
		await get_tree().process_frame  # just in case we got here early

	# Clear old pieces
	for child in piece_container.get_children():
		child.queue_free()
	await get_tree().process_frame  # ensure frees land before we add new ones

	# Temporarily disable water-kill checks for a few frames after we place.
	_kill_guard_until_msec = Time.get_ticks_msec() + 500

	for piece_data in board_data:
		var piece_instance = PieceScene.instantiate()
		var player_num = piece_data["player"]

		piece_instance.set_meta("player", player_num)

		# Local pose (child of BoardZoom) – safe now that the board is scaled.
		piece_instance.position = piece_data["pos"]
		piece_instance.rotation = piece_data["rotation"]

		# Sprite size: 2*PIECE_RADIUS at 1x zoom; parent zoom scales it visually.
		var sprite = piece_instance.find_child("Sprite2D", true, false)
		if sprite:
			sprite.texture = P1_PIECE_TEX if player_num == 1 else P2_PIECE_TEX
			var texture_size = sprite.texture.get_size()
			var desired_visual_size = Vector2(PIECE_RADIUS * 2.0, PIECE_RADIUS * 2.0)
			if texture_size.x > 0.0:
				sprite.scale = desired_visual_size / texture_size

		# Physics radius in local space (global size follows parent scale).
		var collision_shape = piece_instance.find_child("CollisionShape2D", true, false) as CollisionShape2D
		if collision_shape and collision_shape.shape is CircleShape2D:
			(collision_shape.shape as CircleShape2D).radius = PIECE_RADIUS

		piece_container.add_child(piece_instance)
		call_deferred("_try_watch_arrow_for_piece", piece_instance)

		if piece_instance.has_method("set_controlled_by_me"):
			piece_instance.set_controlled_by_me(player_num == player and is_my_turn and not spectator_mode and not game_over)

		if piece_instance.has_signal("aim_changed"):
			piece_instance.connect("aim_changed", func(_angle_deg: float, _pow: float): pass)

func _set_piece_arrow_from_data(piece: Node, shoot_dir_rad: float, pow_px: float, fade_sec: float) -> void:
	var angle_deg: float = rad_to_deg(shoot_dir_rad)
	if piece.has_method("show_arrow_from_replay"):
		piece.call("show_arrow_from_replay", angle_deg, pow_px, fade_sec)
	else:
		# Fallback: at least store meta so your arrow code can pick it up
		piece.set_meta("shoot_dir", angle_deg)
		piece.set_meta("power", pow_px)
		# If the piece scene exposes an "Arrow" CanvasItem, make it visible
		var arrow := piece.get_node_or_null("Arrow") as CanvasItem
		if arrow:
			arrow.modulate.a = 1.0
			arrow.visible = true

func _rotate_piece_to_dir(piece: Node, shoot_dir_rad: float, dur: float) -> void:
	if piece is Node2D:
		var n2d := piece as Node2D
		var tw := create_tween()
		tw.tween_property(n2d, "rotation", shoot_dir_rad, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _fire_piece_from_arrow(piece: Node, shoot_dir_rad: float, pow_px: float) -> void:
	if pow_px <= 0.5:
		return
	if piece.has_method("fire_from_meta"):
		piece.set_meta("shoot_dir", rad_to_deg(shoot_dir_rad))
		piece.set_meta("power", pow_px)
		piece.call("fire_from_meta")
	elif piece is RigidBody2D:
		# fallback (kept for safety)
		var impulse := Vector2(cos(shoot_dir_rad), sin(shoot_dir_rad)) * (pow_px * 1.29)
		(piece as RigidBody2D).apply_impulse(impulse)
	
func _hide_all_arrows_and_refresh_highlights() -> void:
	for piece in piece_container.get_children():
		# Prefer the piece API if present
		if piece.has_method("hide_arrow"):
			piece.hide_arrow()
		else:
			var arrow := piece.get_node_or_null("Arrow") as CanvasItem
			if arrow:
				arrow.visible = false
		# Optional: normalize metadata
		piece.set_meta("power", 0.0)
		piece.set_meta("shoot_dir", 0.0)
		

	# Re-apply the “your-turn” pulsing rings for pieces that have no arrow
	call_deferred("_apply_turn_highlights_based_on_arrows")
	
func _wire_water_kill_areas() -> void:
	_water_kill_areas.clear()
	for n in get_tree().get_nodes_in_group("water_kill"):
		if n is Area2D:
			var a := n as Area2D
			_water_kill_areas.append(a)
			var cb := Callable(self, "_on_water_kill_body_entered")
			if not a.body_entered.is_connected(cb):
				a.body_entered.connect(cb)

func _on_water_kill_body_entered(body: Node) -> void:
	# Only kill our pieces
	if body is RigidBody2D and body.get_parent() == piece_container:
		_kill_piece(body as RigidBody2D)

func _refresh_board_bounds() -> void:
	_safe_polys_global.clear()
	# Collect every polygon tagged as the iceberg outline
	for n in get_tree().get_nodes_in_group("board_bounds"):
		var poly: PackedVector2Array = []
		var xform: Transform2D
		if n is Polygon2D:
			var p2d := n as Polygon2D
			poly = p2d.polygon
			xform = p2d.get_global_transform()
		elif n is CollisionPolygon2D:
			var cp := n as CollisionPolygon2D
			poly = cp.polygon
			xform = cp.get_global_transform()
		else:
			continue
		if poly.size() >= 3:
			# transform to global coords
			var gpoly := PackedVector2Array()
			for v in poly:
				gpoly.append(xform * v)
			# shrink by piece radius so death happens when circle leaves ice
			# Geometry2D.offset_polygon returns Array[PackedVector2Array]
			var shrunk := Geometry2D.offset_polygon(gpoly, -PIECE_RADIUS)
			if shrunk is Array:
				for sub in shrunk:
					if sub.size() >= 3:
						_safe_polys_global.append(sub)

func _point_in_any_safe_poly(pt: Vector2) -> bool:
	for poly in _safe_polys_global:
		if Geometry2D.is_point_in_polygon(pt, poly):
			return true
	return false

func _kill_piece(rb: RigidBody2D) -> void:
	if not is_instance_valid(rb):
		return
	# prevent double-kill from multiple signals/overlaps
	if rb.has_meta("dying"):
		return
	rb.set_meta("dying", true)

	# stop future triggers & physics
	rb.collision_layer = 0
	rb.collision_mask = 0
	rb.freeze = true
	rb.linear_velocity = Vector2.ZERO
	rb.angular_velocity = 0.0

	# hide visuals/arrow/highlights if present
	var arrow := rb.get_node_or_null("Arrow") as CanvasItem
	if arrow: arrow.visible = false
	var ring := rb.get_node_or_null("HighlightRing") as CanvasItem
	if ring: ring.visible = false
	var aim_area := rb.get_node_or_null("Area2D") as Area2D
	if aim_area:
		aim_area.monitoring = false
		aim_area.monitorable = false

	# fade sprite, then free safely
	var spr := rb.get_node_or_null("Sprite2D") as Sprite2D
	if spr:
		var tw := create_tween()
		tw.tween_property(spr, "modulate:a", 0.0, 0.25)
		tw.finished.connect(func():
			if is_instance_valid(rb):
				rb.queue_free()
		)
	else:
		rb.queue_free()

# Call this when your replay round (movement) is complete
func _on_replay_round_finished() -> void:
	# Hide arrows & restore highlights AFTER everything has settled
	_hide_all_arrows_and_refresh_highlights()

	# Mark replay done before checking win so a manual call elsewhere won’t get blocked
	_replay_in_progress = false

	# Small grace to let any fade-out queue_frees complete
	await get_tree().create_timer(0.05).timeout

	#var ended := await check_win()
	#if ended:
		#stop_waiting_animation()
		#game_over = true
		## Keep your existing behavior of notifying the host by sending once the game ends.
		## (This mirrors what you were doing in _set_game_data after a win.)
		#send_game()
		
	# If the match continues and it's your turn next, zoom back in for aiming.
	if not game_over and is_my_turn and not spectator_mode:
		await enter_aim_view()
#
#
	#print("Round finished. Win check => ", ended)

func _any_piece_moving(speed_threshold: float = 8.0, ang_threshold: float = 0.25) -> bool:
	for n in piece_container.get_children():
		if not (n is RigidBody2D):
			continue
		if n.has_meta("dying") and n.get_meta("dying"):
			continue
		var rb := n as RigidBody2D
		# Prefer actual velocities; sleeping can be false during brief contacts
		if rb.linear_velocity.length() > speed_threshold or absf(rb.angular_velocity) > ang_threshold:
			return true
	return false

func _wait_for_pieces_to_settle(timeout_sec: float = 5.0, still_frames_needed: int = 6, speed_threshold: float = 8.0, ang_threshold: float = 0.25) -> void:
	var start_ms := Time.get_ticks_msec()
	var still_frames := 0
	while (Time.get_ticks_msec() - start_ms) < int(timeout_sec * 1000.0):
		await get_tree().physics_frame
		if _any_piece_moving(speed_threshold, ang_threshold):
			still_frames = 0
		else:
			still_frames += 1
			if still_frames >= still_frames_needed:
				break
	# Give Area2D body_entered and fade-out/queue_free a moment to run
	await get_tree().create_timer(0.35).timeout

func _apply_post_round_snapshot(post_board: Dictionary) -> void:
	var arr: Array = post_board.get("pieces", [])
	# The 'off' variable is no longer needed and has been removed.
	var children: Array[Node] = piece_container.get_children()
	var count: int = min(children.size(), arr.size())

	for i in count:
		var piece_node := children[i]
		var pd: Dictionary = arr[i]
		# The target position is now just the piece's data position.
		var pos: Vector2 = pd["pos"] as Vector2
		var rot: float = float(pd["rotation"])

		if piece_node is RigidBody2D:
			var rb := piece_node as RigidBody2D
			rb.freeze = true
			# We set the local 'position' instead of 'global_position'.
			rb.position = pos
			rb.rotation = rot
			rb.linear_velocity = Vector2.ZERO
			rb.angular_velocity = 0.0
			rb.freeze = false
		else:
			# Also set local 'position' here.
			piece_node.position = pos
			piece_node.rotation = rot

# Main round flow
func _play_round_from_replay(pre_board: Dictionary) -> void:
	_replay_in_progress = true
	
	var pre_arr: Array = pre_board.get("pieces", [])
	var children: Array[Node] = piece_container.get_children()
	var count: int = min(children.size(), pre_arr.size())
	await enter_play_view()

	# 1) show arrows (fade)
	for i in count:
		var piece := children[i]
		var pd: Dictionary = pre_arr[i]
		_set_piece_arrow_from_data(piece, float(pd["shoot_dir"]), float(pd["power"]), 0.18)

	# 2) rotate to arrow
	await get_tree().process_frame
	for i in count:
		var piece := children[i]
		var pd: Dictionary = pre_arr[i]
		_rotate_piece_to_dir(piece, float(pd["shoot_dir"]), 0.18)

	# 3) fire all pieces together
	await get_tree().create_timer(0.20).timeout
	for i in count:
		var piece := children[i]
		if not is_instance_valid(piece):
			continue
		var pd: Dictionary = pre_arr[i]
		_fire_piece_from_arrow(piece, float(pd["shoot_dir"]), float(pd["power"]))

	# 4) wait for physics + kill signals to settle, then finish
	await _wait_for_pieces_to_settle(5.0, 6, 8.0, 0.25)
	_on_replay_round_finished()

# --- Piece Highlighting ---
func _apply_turn_highlights_based_on_arrows() -> void:
	if not is_my_turn or spectator_mode or game_over:
		_stop_all_highlights()
		return

	for piece in piece_container.get_children():
		var owner_id: int = int(piece.get_meta("player", -1))
		var ring := piece.get_node_or_null("HighlightRing") as TextureRect
		var anim := piece.get_node_or_null("HighlightAnimator") as AnimationPlayer

		# non-owned -> no highlight
		if owner_id != player:
			if anim: anim.stop()
			if ring: ring.visible = false
			continue

		# owned piece: pulse only if Arrow is not visible
		var arrow := piece.get_node_or_null("Arrow") as CanvasItem
		var arrow_visible := (arrow != null and arrow.visible)

		if arrow_visible:
			if anim: anim.stop()
			if ring: ring.visible = false
		else:
			if ring and anim:
				ring.visible = true
				if anim.has_animation("ring_anim"):
					anim.play("ring_anim")

func _stop_all_highlights() -> void:
	for piece in piece_container.get_children():
		var ring := piece.get_node_or_null("HighlightRing") as TextureRect
		var anim := piece.get_node_or_null("HighlightAnimator") as AnimationPlayer
		if anim:
			anim.stop()
		if ring:
			ring.visible = false
			
func _stop_highlight_for_piece(piece: Node) -> void:
	var ring := piece.get_node_or_null("HighlightRing") as TextureRect
	var anim := piece.get_node_or_null("HighlightAnimator") as AnimationPlayer
	if anim:
		anim.stop()
	if ring:
		ring.visible = false

func _on_arrow_visibility_changed(piece: Node) -> void:
	var arrow := piece.get_node_or_null("Arrow") as CanvasItem
	if not arrow:
		return
	if arrow.visible:
		# Arrow appeared -> stop the pulsing ring on this piece
		_stop_highlight_for_piece(piece)
	else:
		# Arrow was hidden -> (optional) restart ring if it's your turn & it's your piece
		if is_my_turn and not spectator_mode and not game_over and int(piece.get_meta("player", -1)) == player:
			var ring := piece.get_node_or_null("HighlightRing") as TextureRect
			var anim := piece.get_node_or_null("HighlightAnimator") as AnimationPlayer
			if ring and anim:
				ring.visible = true
				if anim.has_animation("ring_anim"):
					anim.play("ring_anim")

func _try_watch_arrow_for_piece(piece: Node) -> void:
	# Wait one frame so the piece scene finishes _ready() and creates the Arrow node.
	await get_tree().process_frame
	var arrow := piece.get_node_or_null("Arrow") as CanvasItem
	if not arrow:
		return
	# Avoid duplicate connections
	if not piece.has_meta("arrow_watch_connected"):
		arrow.connect("visibility_changed", Callable(self, "_on_arrow_visibility_changed").bind(piece))
		piece.set_meta("arrow_watch_connected", true)
	# Apply current state immediately
	_on_arrow_visibility_changed(piece)


# If you ever toggle turn state locally, call this to refresh highlight state.
func set_my_turn(value: bool) -> void:
	is_my_turn = value
	call_deferred("_apply_turn_highlights_based_on_arrows")

# --- UI Animations & State ---

func check_win() -> bool:
	# If a replay is running, defer the decision
	if _replay_in_progress:
		print("--- CHECKING WIN CONDITION --- (deferred; replay in progress)")
		return false

	print("--- CHECKING WIN CONDITION ---")

	# Count live pieces per player (skip anything already flagged as dying)
	var p1_count := 0
	var p2_count := 0
	for n in piece_container.get_children():
		if not (n is RigidBody2D):
			continue
		if n.has_meta("dying") and n.get_meta("dying"):
			continue
		var owner_id := int(n.get_meta("player", -1))
		if owner_id == 1:
			p1_count += 1
		elif owner_id == 2:
			p2_count += 1

	var unique_colors := 0
	if p1_count > 0: unique_colors += 1
	if p2_count > 0: unique_colors += 1

	var my_count := p1_count if (player == 1) else p2_count
	var op_count := p2_count if (player == 1) else p1_count

	if unique_colors > 1:
		print("-> RESULT: Game Continues. Both colors still present. P1=%d, P2=%d" % [p1_count, p2_count])
		return false

	var was_over: bool = game_over
	game_over = true

	if unique_colors == 0:
		print("-> No pieces remain. Declaring draw.")
		if not was_over:
			win_loss_label.text = "DRAW!"
			win_loss_state = "0"
			win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
			win_loss_label.visible = true
			await get_tree().process_frame
			win_loss_label.scale = Vector2.ZERO
			win_loss_label.pivot_offset = win_loss_label.size / 2
			var tween_draw := create_tween()
			tween_draw.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		else:
			print("-> Game was already marked as over. No new result displayed.")
		return true

	# Exactly one color remains: decide winner
	print("-> WIN CONDITION MET: only one color remains. My:%d, Opp:%d (P1=%d, P2=%d)" % [my_count, op_count, p1_count, p2_count])

	if not was_over:
		if my_count > 0 and op_count == 0:
			print("-> FINAL TALLY: YOU WIN!")
			_show_win_burst(player_avatar_display)
			if not spectator_mode:
				win_loss_label.text = "YOU WIN!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			else:
				win_loss_label.text = "Player 1 Wins!" if (p1_count > 0) else "Player 2 Wins!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			win_loss_state = "1"
		elif op_count > 0 and my_count == 0:
			print("-> FINAL TALLY: YOU LOSE")
			_show_win_burst(opp_avatar_display)
			if not spectator_mode:
				win_loss_label.text = "YOU LOSE"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			else:
				win_loss_label.text = "Player 1 Wins!" if (p1_count > 0) else "Player 2 Wins!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			win_loss_state = "-1"
		else:
			print("-> Edge case: counts ambiguous. Declaring draw.")
			win_loss_label.text = "DRAW!"
			win_loss_state = "0"
			win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))

		win_loss_label.visible = true
		await get_tree().process_frame
		win_loss_label.scale = Vector2.ZERO
		win_loss_label.pivot_offset = win_loss_label.size / 2
		var tween_in := create_tween()
		tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	else:
		print("-> Game was already marked as over. No new result displayed.")

	return true
	
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

# ... (rest of your existing functions: play_sent_animation, start_waiting_animation, etc.)
func play_sent_animation():
	if not is_instance_valid(sent_label) or game_over:
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
		if is_instance_valid(sent_label): sent_label.text = "Sent ✔"
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
	if not is_instance_valid(waiting_label) or spectator_mode:
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
		if is_instance_valid(dot_timer): dot_timer.start()
	)

func stop_waiting_animation():
	if is_instance_valid(dot_timer): dot_timer.stop()
	if is_instance_valid(waiting_label): waiting_label.visible = false
	if is_instance_valid(waiting_blur): waiting_blur.visible = false

func _on_dot_timer_timeout():
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count): dots += "."
	if is_instance_valid(waiting_label): waiting_label.text = BASE_WAIT_TEXT + dots

# --- Popups & Settings ---
func on_rules_button_pressed() -> void:
	if not is_instance_valid(rules_button):
		return

	rules_button.pivot_offset = rules_button.size / 2.0
	tween = create_tween()
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
		title_label.text = "How to Play Knockout"

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

func _get_rules_text() -> String:
	return """
[font_size={18px}]
[b]Goal[/b]
Knock your opponent’s penguins off the iceberg. The last color with any pieces left wins.

[b]How to Play[/b]
1) On your turn, select one of [b]your[/b] penguins. Press/drag from the penguin to show the aim arrow.  
   • Arrow direction = shot direction.  
   • Arrow length = shot power.
2) When you’re satisfied, press [b]Send[/b] to lock in your turn. Then wait for your opponent.
3) Once both players have selected their moves the round will start.
4) Any penguin that leaves the iceberg is eliminated from the game.

[b]End of Game[/b]
• The game ends [b]immediately[/b] when only one color remains on the board → that color wins.  
• If no pieces remain, it’s a [b]draw[/b].

[b]Tips[/b]
Higher power slides farther but is harder to control; edges are risky!
[/font_size]
"""

func _parse_avatar_string(data_string: String) -> Dictionary:
	var hair_map = ["Spiky", "Long", "Bun", "Bald"]
	var body_map = ["Default", "Smiling", "Winking", "Surprised", "Frowning", "Tongue Out", "Cute"]
	var eyes_map = ["Open", "Closed", "Winking"]
	var mouth_map = ["Plain", "Smile", "Frown"]
	var clothing_map = ["T-Shirt", "Sweater", "Tank Top"]
	var backdrop_map = ["Plain", "Pattern 1", "Pattern 2", "Pattern 3", "Pattern 4", "Pattern 5", "Pattern 6", "Pattern 7", "Pattern 8", "Pattern 9"]

	var data = {}
	var parts = data_string.split("|")
	for part in parts:
		var key_value = part.split(",")
		if key_value.size() < 2:
			continue

		var key = key_value[0]
		var values = key_value.slice(1)

		match key:
			"hair":
				var index = int(values[0])
				if index >= 0 and index < hair_map.size():
					data["hair_style"] = hair_map[index]
				else:
					print("Warning: Invalid hair index received: ", index)
			"body":
				var index = int(values[0])
				if index >= 0 and index < body_map.size():
					data["body_style"] = body_map[index]
				else:
					print("Warning: Invalid body index received: ", index)
			"eyes":
				var index = int(values[0])
				if index >= 0 and index < eyes_map.size():
					data["eyes_style"] = eyes_map[index]
				else:
					print("Warning: Invalid eyes index received: ", index)
			"mouth":
				var index = int(values[0])
				if index >= 0 and index < mouth_map.size():
					data["mouth_style"] = mouth_map[index]
				else:
					print("Warning: Invalid mouth index received: ", index)
			"clothes":
				var index = int(values[0])
				if index >= 0 and index < clothing_map.size():
					data["clothing_style"] = clothing_map[index]
				else:
					print("Warning: Invalid clothes index received: ", index)
			"backdrop":
				var backdrop_index = int(values[0])
				if backdrop_index >= 0 and backdrop_index < backdrop_map.size():
					data["bg_style"] = backdrop_map[backdrop_index]
				else:
					print("Warning: Invalid backdrop index received: ", backdrop_index)
			"bg_color", "body_color", "hair_color", "clothes_color":
				if values.size() >= 3:
					var color_key = key.replace("_color", "") + "_color"
					data[color_key] = Color(float(values[0]), float(values[1]), float(values[2]))
	return data

func _on_settings_button_pressed() -> void:
	settings_button.pivot_offset = settings_button.size / 2.0
	tween = create_tween()
	tween.tween_property(settings_button, "scale", Vector2(1.3, 1.3), 0.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(settings_button, "scale", Vector2.ONE, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var popup_instance = SETTINGS_POPUP_SCENE.instantiate()
	var settings_popup_script = popup_instance as SettingsPopup

	var root = get_tree().root
	root.add_child(dim)
	root.add_child(popup_instance)
	popup_instance.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)
	settings_popup_script.setup_popup(dim)

	var custom_settings_title = popup_instance.find_child("CustomSettingsTitleLabel", true)
	if custom_settings_title and custom_settings_title is Label and settings_popup_script.custom_settings_container.get_child_count() > 0:
		custom_settings_title.visible = true
	else:
		if custom_settings_title and custom_settings_title is Label:
			custom_settings_title.visible = false

	settings_popup_script.closed.connect(func():
		print("Settings popup was closed for game: ", game_settings_category)
		if is_instance_valid(player_avatar_display):
			player_avatar_display.update_display_from_settings()
	)
	settings_popup_script.settings_theme_selected.connect(_on_theme_changed)
	settings_popup_script.dark_mode_changed.connect(_apply_bg_for_dark)

	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await get_tree().process_frame

	var viewport_size = get_viewport_rect().size
	var desired_width = viewport_size.x * 0.95
	var desired_height = popup_instance.get_combined_minimum_size().y

	popup_instance.size = Vector2(desired_width, desired_height)
	popup_instance.position = Vector2((viewport_size.x - desired_width) / 2, viewport_size.y)

	var bottom_offset = 50
	var target_y_position = viewport_size.y - desired_height - bottom_offset
	var target_position = Vector2((viewport_size.x - desired_width) / 2, target_y_position)

	var popup_tween = create_tween()
	popup_tween.tween_property(popup_instance, "position", target_position, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	popup_instance.grab_focus()

func _on_theme_changed(new_theme_name: String):
	print("Game scene received theme change: ", new_theme_name)
	pass

func _load_game_specific_settings():
	var saved_volume = SettingsManager.get_setting(game_settings_category, "master_volume", 0.75)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info = SettingsManager.get_setting(game_settings_category, "show_debug_info", false)

	print("Loaded game-specific settings for ", game_settings_category, ":")
	print("  Master Volume: ", saved_volume)
	print("  Show Debug Info: ", show_debug_info)




#DEV CODE

# --- Dev replay override (for visual verification) ---
const DEV_USE_HARDCODED_REPLAY := true  # set true to force one of the dev strings below
var _debug_draw_kill_zone := true # Set to false to hide the kill zone
const DEV_REPLAY_MODE := "corners"      # "corners" | "down" | "right" | "left" | "up" | "all_dirs"

# Corner anchors (relative to board center). Tweak if your board is larger/smaller.
const DEV_CORNER_UL := Vector2(-150, -150)
const DEV_CORNER_UR := Vector2( 150, -150)
const DEV_CORNER_LR := Vector2( 150,  150)
const DEV_CORNER_LL := Vector2(-150,  150)
const DEV_CORNER_CC := Vector2(0,  0)

# Convenience (radians)
const RAD_RIGHT := 0.0
const RAD_DOWN := -PI * 0.5
const RAD_LEFT := PI
const RAD_UP := PI * 0.5

# Base layout used by all tests (two P1, two P2)
const _DEV_BASE_LAYOUT := [
	{ "pos": DEV_CORNER_UL, "player": 1 },
	{ "pos": DEV_CORNER_UR, "player": 2 },
	{ "pos": DEV_CORNER_LR, "player": 1 },
	{ "pos": DEV_CORNER_LL, "player": 2 },
]

# 1) Corners only (no shooting) — place pieces, verify positions
var DEV_REPLAY_CORNERS := "board:1#" \
+ str(DEV_CORNER_UL.x)  + "," + str(DEV_CORNER_UL.y)  + ",1,0.0,0.0,0.0#" \
+ str(DEV_CORNER_UR.x)  + "," + str(DEV_CORNER_UR.y)  + ",2,0.0,0.0,0.0#" \
+ str(DEV_CORNER_LR.x)  + "," + str(DEV_CORNER_LR.y)  + ",1,0.0,0.0,0.0#" \
+ str(DEV_CORNER_CC.x)  + "," + str(DEV_CORNER_CC.y)  + ",1,0.0,0.0,0.0#" \
+ str(DEV_CORNER_LL.x)  + "," + str(DEV_CORNER_LL.y)  + ",2,0.0,0.0,0.0" \
+ "|shoot:0"

# 2) Cardinal movement helpers (same starting layout, different shot dirs)
const _DEV_POWER := 60.0  # moderate power for clear motion without insta-fall

var DEV_REPLAY_DOWN  := "board:2#" \
+ str(DEV_CORNER_UL.x)  + "," + str(DEV_CORNER_UL.y)  + ",1,0.0," + str(RAD_DOWN)  + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_UR.x)  + "," + str(DEV_CORNER_UR.y)  + ",2,0.0," + str(RAD_DOWN)  + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_LR.x)  + "," + str(DEV_CORNER_LR.y)  + ",1,0.0," + str(RAD_DOWN)  + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_LL.x)  + "," + str(DEV_CORNER_LL.y)  + ",2,0.0," + str(RAD_DOWN)  + "," + str(_DEV_POWER) \
+ "|shoot:1"

var DEV_REPLAY_RIGHT := "board:2#" \
+ str(DEV_CORNER_UL.x)  + "," + str(DEV_CORNER_UL.y)  + ",1,0.0," + str(RAD_RIGHT) + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_UR.x)  + "," + str(DEV_CORNER_UR.y)  + ",2,0.0," + str(RAD_RIGHT) + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_LR.x)  + "," + str(DEV_CORNER_LR.y)  + ",1,0.0," + str(RAD_RIGHT) + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_LL.x)  + "," + str(DEV_CORNER_LL.y)  + ",2,0.0," + str(RAD_RIGHT) + "," + str(_DEV_POWER) \
+ "|shoot:1"

var DEV_REPLAY_LEFT  := "board:2#" \
+ str(DEV_CORNER_UL.x)  + "," + str(DEV_CORNER_UL.y)  + ",1,0.0," + str(RAD_LEFT)  + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_UR.x)  + "," + str(DEV_CORNER_UR.y)  + ",2,0.0," + str(RAD_LEFT)  + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_LR.x)  + "," + str(DEV_CORNER_LR.y)  + ",1,0.0," + str(RAD_LEFT)  + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_LL.x)  + "," + str(DEV_CORNER_LL.y)  + ",2,0.0," + str(RAD_LEFT)  + "," + str(_DEV_POWER) \
+ "|shoot:1"

var DEV_REPLAY_UP    := "board:2#" \
+ str(DEV_CORNER_UL.x)  + "," + str(DEV_CORNER_UL.y)  + ",1,0.0," + str(RAD_UP)    + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_UR.x)  + "," + str(DEV_CORNER_UR.y)  + ",2,0.0," + str(RAD_UP)    + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_LR.x)  + "," + str(DEV_CORNER_LR.y)  + ",1,0.0," + str(RAD_UP)    + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_LL.x)  + "," + str(DEV_CORNER_LL.y)  + ",2,0.0," + str(RAD_UP)    + "," + str(_DEV_POWER) \
+ "|shoot:1"

# Optional: one-shot where each piece moves a different cardinal direction
var DEV_REPLAY_ALL_DIRS := "board:2#" \
+ str(DEV_CORNER_UL.x)  + "," + str(DEV_CORNER_UL.y)  + ",1,0.0," + str(RAD_DOWN)  + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_UR.x)  + "," + str(DEV_CORNER_UR.y)  + ",2,0.0," + str(RAD_RIGHT) + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_LR.x)  + "," + str(DEV_CORNER_LR.y)  + ",1,0.0," + str(RAD_LEFT)  + "," + str(_DEV_POWER) + "#" \
+ str(DEV_CORNER_LL.x)  + "," + str(DEV_CORNER_LL.y)  + ",2,0.0," + str(RAD_UP)    + "," + str(_DEV_POWER) \
+ "|shoot:1"

func _draw() -> void:
	# Only draw the polygon if our debug flag is turned on.
	if _debug_draw_kill_zone:
		if not _safe_polys_global.is_empty():
			# Define a color for the debug shape (semi-transparent red is good).
			var debug_color = Color(1.0, 0.0, 0.0, 0.4)
			
			# Loop through all safe polygons (usually just one) and draw them.
			# Note: This works because the script is on the root Control node,
			# whose local coordinates match the global coordinates of the polygon.
			for poly in _safe_polys_global:
				draw_polygon(poly, PackedColorArray([debug_color]))
