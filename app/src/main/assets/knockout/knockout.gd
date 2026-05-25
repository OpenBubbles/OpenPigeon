extends Control

# --- Preloaded Assets ---
const PieceScene := preload("res://knockout/piece.tscn")
const P1_PIECE_TEX := preload("res://knockout/bw_penguin.png")
const P2_PIECE_TEX := preload("res://knockout/gw_penguin.png")
const BLACK_PRESERVER_TEX := preload("res://knockout/life_prev_black.png")
const GRAY_PRESERVER_TEX := preload("res://knockout/life_prev_gray.png")
const MAP1_TEX := preload("res://knockout/ko_map1.png")
const MAP2_TEX := preload("res://knockout/ko_map2.png")
const MAP3_TEX := preload("res://knockout/ko_map3.png")


const RULES_POPUP_SCENE = preload("res://global/RulesPopup.tscn")
const MUSHROOM_SCENE := preload("res://knockout/mushroom.tscn")
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
@onready var piece_container := %PieceContainer
@onready var left_preserver := %LeftPreserver
@onready var right_preserver := %RightPreserver
@onready var safe_zone_polygon := %SafeZonePolygon
@onready var _texrect := %TextureRect
var _board_scale_node: Control = null
const PDIFF_ENABLED := false
var _pdiff = null
var _pdiff_active := false
const PDIFF_DEV_REPLAY := "board:1#-41.490452,-18.381981,2,2.568027,0.311887,11.024456#35.786495,56.762127,1,0.193446,3.140568,125.850670|shoot:1|board:2#-24.121695,-12.309731,2,1.882683,0.311887,0.000000#-135.776291,51.576973,1,4.711365,-0.038352,95.461876|board:2#-24.121695,-12.309731,2,1.882683,0.311887,0.000000#-135.776291,51.576973,1,4.711365,-0.038352,95.461876"

# Debug/watch state
const LOGICAL_BOARD_SIZE := Vector2(375.0, 375.0)
const IOS_BOARD_TEXTURE_SIZE := LOGICAL_BOARD_SIZE
const IOS_BOARD_TEXTURE_OFFSET := Vector2.ZERO
const IOS_PENGUIN_VISUAL_SIZE := Vector2(50.0, 50.0)

const ZOOM_START := 1
const ZOOM_DUR := 0.22
const PIECE_HEADING_OFFSET: float = -PI * 0.5

# iOS board shrink: board index/melt 0 = 1.0, 1 = 0.9, 2 = 0.8, 3 = 0.7, etc.
const BOARD_MAX_INDEX := 7

var _target_physical_size: float = 350.0
var _board_base_scale_factor: float = 1.0
var _kill_detection_enabled := true

const DEBUG_DRAW_ZONES := false

const Z_BACKGROUND := -100
const Z_WATER_RIPPLE := 0
const Z_BOARD := 10
const Z_ARROWS := 20
const Z_PIECES := 30
const Z_TEXT := 50
const Z_BLUR := 99
const Z_UI_TOP := 100

var _current_board_index: int = 0
var _safe_area: Area2D
var _safe_poly: CollisionPolygon2D
var _hole_areas: Array[Area2D] = []
var _hole_polys: Array[CollisionPolygon2D] = []

const ARROW_COLOR_MAP1 := Color(0,0,0,1)
const ARROW_COLOR_MAP2 := Color(0.95, 0.95, 0.95, 1.0)
const ARROW_COLOR_MAP3 := Color(0.92, 0.92, 0.92, 1.0)
const ARROW_COLOR_PLAYER2 := Color("#61779e")
const SEND_WHITE := Color("#ffffff")
const SEND_BLUE := Color("#5798f6")
const SEND_RED := Color("#d62828")
const SEND_GREEN := Color("#14532d")

var current_scale: float = ZOOM_START
const DEBUG_KILL := true


# --- Replay state ---
var last_pre_round: Dictionary = {}      # {"round": int, "pieces": Array[Dictionary]}
var last_post_round: Dictionary = {}     # same shape; board #2 snapshot after physics
var last_pending_setup_round: Dictionary = {} # board after replay where only one player has aimed
var current_round_index: int = 0

const PPM                 := 32.0
const PIECE_RADIUS_PX     := 12.5
const FRICTION            := 1.0
const RESTITUTION         := 1.0
const LINEAR_DAMP         := 1.35
const ANGULAR_DAMP        := 0.0
const DENSITY             := 1.0
const GRAVITY_SCALE       := 0.0
const CCD_MODE            := RigidBody2D.CCD_MODE_CAST_RAY
const LOCK_ROTATION       := false
const IOS_STOP_LINEAR_SPEED := 1.0
const IOS_STOP_ANGULAR_SPEED := 0.08
const CAN_SLEEP := false

var PIECE_RADIUS := PIECE_RADIUS_PX
const ROUND_SNAP_AFTER: float = 1.4
var _staged_launch_mode: bool = false
var _goal_popup_shown: bool = false
var _pending_goal_popup: bool = false
var _staged_pre_board_str: String = ""
var _staged_next_index: int = 0

var _water_kill_areas: Array[Area2D] = []
var _base_iceberg_poly: PackedVector2Array = []
var _base_hole_polys: Array[PackedVector2Array] = []     # holes in image space
var _mushroom_layer: Node2D
var _last_safe_poly: PackedVector2Array = []
var _last_hole_polys_cached: Array[PackedVector2Array] = []
var _kill_check_accum := 0.0

# Throttle kill checks to reduce per-frame cost
const KILL_CHECK_INTERVAL := 0.05

# --- Game State Variables ---
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
var game_settings_category: String
var map_mode: int = 1

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
var spectator_mode: bool = false
var avatar_key = 0
var player = 1
var sent_tween: Tween
var dot_count = 0
var _aim_instruction_label: Label = null
var _aim_instruction_tween: Tween = null
var _resize_pending := false
var _loading_board_data := false
var _incoming_data_seq := 0

func _is_stale_data_seq(data_seq: int) -> bool:
	return data_seq >= 0 and data_seq != _incoming_data_seq

func _on_viewport_resize() -> void:
	if not _board_initialized:
		return
	# When we are animating zoom or board shrink, defer the resize math.
	if _is_zooming:
		if not _resize_pending:
			_resize_pending = true
			call_deferred("_apply_resize_refresh")
		return
	_apply_resize_refresh()

func _apply_resize_refresh() -> void:
	_resize_pending = false
	_target_physical_size = get_viewport_rect().size.x
	_recalc_board_base_scale_factor()
	_ensure_board_scaler()
	_layout_board_centered()
	_apply_board_index_immediate(_current_board_index)
	_apply_board_draw_order()
	_refresh_safe_polys_for_transform()
	_seed_area_overlaps()

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

func _texrect_draw_rect(texr: TextureRect, img: Image) -> Rect2:
	var tex_size: Vector2 = Vector2.ZERO
	if img and not img.is_empty():
		tex_size = Vector2(img.get_width(), img.get_height())
	elif texr.texture:
		tex_size = Vector2(texr.texture.get_size())
	if tex_size == Vector2.ZERO:
		return Rect2(Vector2.ZERO, texr.size)

	var draw_pos: Vector2 = Vector2.ZERO
	var draw_size: Vector2 = texr.size

	match texr.stretch_mode:
		TextureRect.STRETCH_SCALE:
			draw_pos = Vector2.ZERO
			draw_size = texr.size

		TextureRect.STRETCH_TILE:
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
	
func _style_button(btn: Button, base: Color) -> void:
	if not is_instance_valid(btn): return
	var normal := StyleBoxFlat.new()
	normal.bg_color = base
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate()
	hover.bg_color = base.lerp(Color.WHITE, 0.08)
	var pressed := normal.duplicate()
	pressed.bg_color = base.darkened(0.12)
	var disabled := normal.duplicate()
	disabled.bg_color = base.darkened(0.35)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", Color.WHITE)

func _aim_label_base_color() -> Color:
	if map_mode == 2:
		return SEND_RED
	if map_mode == 3:
		return SEND_GREEN
	return SEND_WHITE

func _arrow_color_for_piece(piece: Node) -> Color:
	if int(piece.get_meta("player", -1)) == 2:
		return ARROW_COLOR_PLAYER2

	if map_mode == 2:
		return ARROW_COLOR_MAP2
	if map_mode == 3:
		return ARROW_COLOR_MAP3

	return ARROW_COLOR_MAP1

func _apply_arrow_color_for_current_map() -> void:
	if not is_instance_valid(piece_container):
		return

	for piece in piece_container.get_children():
		var arrow := piece.get_node_or_null("Arrow") as CanvasItem
		if arrow:
			var old_alpha := arrow.modulate.a
			arrow.modulate = _arrow_color_for_piece(piece)
			arrow.modulate.a = old_alpha
			
func _apply_send_button_color_for_current_map() -> void:
	if not is_instance_valid(send_button): return
	if map_mode == 2:
		_style_button(send_button, SEND_RED)
	elif map_mode == 3:
		_style_button(send_button, SEND_GREEN)

func _can_show_aim_ui() -> bool:
	return (
		is_my_turn
		and not spectator_mode
		and not game_over
		and not _replay_in_progress
		and not _is_zooming
		and not _loading_board_data
	)
	
func _update_aim_instruction_label() -> void:
	if not is_instance_valid(_aim_instruction_label):
		_aim_instruction_label = Label.new()
		_aim_instruction_label.name = "AimInstructionLabel"
		_aim_instruction_label.text = "Adjust power and direction\nfor all your penguins."
		_aim_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_aim_instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_aim_instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_aim_instruction_label.add_theme_font_size_override("font_size", 28)
		_aim_instruction_label.add_theme_color_override("font_color", _aim_label_base_color())
		_aim_instruction_label.z_as_relative = false
		_aim_instruction_label.z_index = Z_TEXT
		_aim_instruction_label.visible = false
		_aim_instruction_label.modulate.a = 0.0
		add_child(_aim_instruction_label)

		_aim_instruction_label.anchor_left = 0.0
		_aim_instruction_label.anchor_right = 1.0
		_aim_instruction_label.anchor_top = 1.0
		_aim_instruction_label.anchor_bottom = 1.0
		_aim_instruction_label.offset_left = 36.0
		_aim_instruction_label.offset_right = -36.0
		_aim_instruction_label.offset_top = -190.0
		_aim_instruction_label.offset_bottom = -95.0

	var should_show := (
		_can_show_aim_ui()
		and not _owned_live_pieces().is_empty()
		and not _all_my_arrows_visible()
	)

	if _aim_instruction_tween and _aim_instruction_tween.is_running():
		_aim_instruction_tween.kill()

	if should_show:
		_aim_instruction_label.visible = true
		_aim_instruction_tween = create_tween()
		_aim_instruction_tween.tween_property(_aim_instruction_label, "modulate:a", 1.0, 0.22)
	else:
		_aim_instruction_label.visible = false
		_aim_instruction_label.modulate.a = 0.0

# Rebuild base polygons from the image ONCE (or when the texture/map changes).
func _rebuild_base_polys_from_png(alpha_threshold: float = 0.1, simplify_epsilon: float = 1.5) -> void:
	_base_iceberg_poly.clear()
	_base_hole_polys.clear()
	print("274 Call")
	var texrect := _get_texrect()
	if not is_instance_valid(texrect) or texrect.texture == null:
		print("[POLY] No TextureRect/texture; skipping build")
		return

	var img := _texture_to_image_or_fallback(texrect.texture)

	# Absolute last-resort fallback so debug/kill still work:
	if img == null or img.is_empty():
		var tex_px := Vector2(texrect.texture.get_size())  # renderer size is still known
		if tex_px.x <= 0.0 or tex_px.y <= 0.0:
			tex_px = LOGICAL_BOARD_SIZE
		_base_iceberg_poly = PackedVector2Array([
			Vector2(0, 0),
			Vector2(tex_px.x, 0),
			Vector2(tex_px.x, tex_px.y),
			Vector2(0, tex_px.y),
		])
		print("[POLY] WARNING: get_image() empty; using full-rect fallback: ", tex_px)
		return

	# Build alpha mask and extract polygons
	var bm := BitMap.new()
	bm.create_from_image_alpha(img, alpha_threshold)

	var rect_img := Rect2i(Vector2i.ZERO, img.get_size())
	var contours: Array[PackedVector2Array] = bm.opaque_to_polygons(rect_img, simplify_epsilon)

	if contours.is_empty():
		print("[POLY] No opaque polygons found; using full-rect fallback.")
		_base_iceberg_poly = PackedVector2Array([
			Vector2(0, 0),
			Vector2(img.get_width(), 0),
			Vector2(img.get_width(), img.get_height()),
			Vector2(0, img.get_height()),
		])
		return

	# pick largest as outer
	var best := contours[0]
	var best_area := _poly_area(best)
	for poly in contours:
		var a := _poly_area(poly)
		if a > best_area:
			best = poly
			best_area = a
	_base_iceberg_poly = best

	# Map 2: find transparent islands fully inside the iceberg
	if map_mode == 2:
		_base_hole_polys = _extract_holes_from_transparency(img, best, alpha_threshold, simplify_epsilon)
	else:
		_base_hole_polys.clear()

# Recompute transformed (BoardZoom-local & global) polygons when transforms/layout change.
func _refresh_safe_polys_for_transform() -> void:
	_ensure_debug_preview_hosted_in_board_zoom()

	if _base_iceberg_poly.is_empty():
		if is_instance_valid(safe_zone_polygon):
			safe_zone_polygon.polygon = PackedVector2Array()
			print("311 Call")
		_destroy_safe_hole_areas()
		print("313 CALL")
		return

	var texrect := _get_texrect()
	if not is_instance_valid(board_zoom) or not is_instance_valid(texrect) or not texrect.texture:
		print("EXITING 316")
		return

	var xf: Transform2D = board_zoom.get_global_transform().affine_inverse() * texrect.get_global_transform()
	var tex_draw_rect: Rect2 = _texrect_draw_rect(texrect, null)
	var img_size := Vector2(texrect.texture.get_size())
	var tex_scale := tex_draw_rect.size / img_size if img_size.x > 0.0 and img_size.y > 0.0 else Vector2.ONE

	var local_poly := PackedVector2Array()
	for v_img in _base_iceberg_poly:
		var p_tex := tex_draw_rect.position + (v_img * tex_scale)
		local_poly.append(xf * p_tex)

	var offset_amount := 1.0
	var final_poly := local_poly
	var expanded := Geometry2D.offset_polygon(local_poly, offset_amount)
	if expanded is Array and expanded.size() > 0:
		final_poly = expanded[0]

	var hole_locals: Array[PackedVector2Array] = []
	if map_mode == 2 and not _base_hole_polys.is_empty():
		for hole_img in _base_hole_polys:
			var hl := PackedVector2Array()
			for v_img in hole_img:
				var p_tex := tex_draw_rect.position + (v_img * tex_scale)
				hl.append(xf * p_tex)

			var shrink_amount := -1.0
			var shrunk := Geometry2D.offset_polygon(hl, shrink_amount)
			hole_locals.append(shrunk[0] if (shrunk is Array and shrunk.size() > 0) else hl)

	_last_safe_poly = final_poly
	_last_hole_polys_cached = hole_locals.duplicate()

	if is_instance_valid(safe_zone_polygon):
		safe_zone_polygon.polygon = final_poly
		safe_zone_polygon.visible = DEBUG_DRAW_ZONES
		if safe_zone_polygon is Polygon2D:
			safe_zone_polygon.color = Color(0, 1, 0, 0.10)

	_build_safe_area(final_poly)
	_build_hole_areas(hole_locals)

	if _kill_debug_showing:
		_ensure_kill_overlay()
		_safe_debug_poly.polygon = final_poly
		_safe_debug_outline.points = final_poly
		_set_hole_debug_polys(hole_locals)
		_update_hole_outlines(hole_locals)

func _ensure_piece_container_hosted_in_board_zoom() -> void:
	if not is_instance_valid(piece_container) or not is_instance_valid(board_zoom):
		return

	if piece_container.get_parent() != board_zoom:
		piece_container.reparent(board_zoom)

	piece_container.position = LOGICAL_BOARD_SIZE * 0.5
	piece_container.scale = Vector2.ONE

func _texture_to_image_or_fallback(tex: Texture2D) -> Image:
	var img: Image = null
	if tex:
		img = tex.get_image()
	# Fallback: load the source file directly (works even when VRAM-compressed)
	if img == null or img.is_empty():
		var path := tex.resource_path if tex else ""
		if path != "":
			var raw := Image.new()
			var err := raw.load(path)
			if err == OK and not raw.is_empty():
				return raw
		# Still nothing: return an empty Image so caller can decide what to do.
		return Image.new()
	return img
	
func _destroy_safe_hole_areas() -> void:
	if is_instance_valid(_safe_area):
		_safe_area.queue_free()
	_safe_area = null
	_safe_poly = null

	for a in _hole_areas:
		if is_instance_valid(a):
			a.queue_free()
	_hole_areas.clear()
	_hole_polys.clear()

func _build_safe_area(poly: PackedVector2Array) -> void:
	if not is_instance_valid(board_zoom): return

	# Create once
	if not is_instance_valid(_safe_area):
		_safe_area = Area2D.new()
		_safe_area.name = "KillArea"
		_safe_area.collision_layer = 0
		_safe_area.collision_mask = 1
		_safe_area.monitoring = true
		_safe_area.monitorable = true
		_safe_area.position = Vector2.ZERO
		_safe_area.rotation = 0.0
		_safe_area.scale = Vector2.ONE
		board_zoom.add_child(_safe_area)
		_safe_area.body_exited.connect(_on_safe_area_body_exited)

	if not is_instance_valid(_safe_poly):
		_safe_poly = CollisionPolygon2D.new()
		_safe_poly.name = "KillPoly"
		_safe_poly.build_mode = CollisionPolygon2D.BUILD_SOLIDS
		_safe_poly.position = Vector2.ZERO
		_safe_poly.rotation = 0.0
		_safe_poly.scale = Vector2.ONE
		_safe_area.add_child(_safe_poly)

	# Exact same polygon we show in the preview; in BoardZoom-local coords
	_safe_poly.polygon = poly


func _build_hole_areas(hole_polys: Array[PackedVector2Array]) -> void:
	# Grow / create
	while _hole_areas.size() < hole_polys.size():
		var a := Area2D.new()
		a.name = "HoleArea_%d" % _hole_areas.size()
		a.collision_layer = 0
		a.collision_mask = 1
		a.monitoring = true
		a.monitorable = true
		a.position = Vector2.ZERO
		a.rotation = 0.0
		a.scale = Vector2.ONE
		board_zoom.add_child(a)

		var cp := CollisionPolygon2D.new()
		cp.build_mode = CollisionPolygon2D.BUILD_SOLIDS
		cp.position = Vector2.ZERO
		cp.rotation = 0.0
		cp.scale = Vector2.ONE
		a.add_child(cp)

		a.body_entered.connect(_on_hole_body_entered)
		_hole_areas.append(a)
		_hole_polys.append(cp)

	# Update existing
	for i in hole_polys.size():
		_hole_areas[i].visible = DEBUG_DRAW_ZONES
		_hole_polys[i].polygon = hole_polys[i]

	# Trim extras
	for j in range(hole_polys.size(), _hole_areas.size()):
		if is_instance_valid(_hole_areas[j]):
			_hole_areas[j].queue_free()
	if _hole_areas.size() > hole_polys.size():
		_hole_areas = _hole_areas.slice(0, hole_polys.size())
		_hole_polys   = _hole_polys.slice(0, hole_polys.size())

func _on_safe_area_body_exited(body: Node) -> void:
	if _loading_board_data or not _kill_detection_enabled:
		return
	if body is RigidBody2D and body.get_parent() == piece_container:
		if DEBUG_KILL: print("[KILL] SafeArea.body_exited →", body.name)
		_safe_kill(body)

func _on_hole_body_entered(body: Node) -> void:
	if _loading_board_data or not _kill_detection_enabled:
		return
	if body is RigidBody2D and body.get_parent() == piece_container:
		if DEBUG_KILL: print("[KILL] HoleArea.body_entered →", body.name)
		_safe_kill(body)

func _on_water_kill_body_entered(body: Node) -> void:
	if _loading_board_data or not _kill_detection_enabled:
		return
	if body is RigidBody2D and body.get_parent() == piece_container:
		if DEBUG_KILL: print("[KILL] Water.body_entered →", body.name)
		_safe_kill(body)
		
func _apply_piece_container_scale_for_board() -> void:
	if not is_instance_valid(piece_container):
		return

	piece_container.scale = Vector2.ONE
	_resync_piece_sprite_sizes()
	
func _target_scale_for_index(i: int) -> float:
	return _board_scale_for_index(i)
	
func _recalc_board_base_scale_factor() -> void:
	var vp := get_viewport_rect().size
	_board_base_scale_factor = 1.0

	if LOGICAL_BOARD_SIZE.x > 0.0:
		_board_base_scale_factor = vp.x / LOGICAL_BOARD_SIZE.x

	if DEBUG_SHRINK:
		print("[SHRINK] _recalc_board_base_scale_factor",
			" | base_factor=", _board_base_scale_factor,
			" | viewport=", vp,
			" | logical=", LOGICAL_BOARD_SIZE
		)
		
func _pin_control_rect(c: Control, pos: Vector2, sz: Vector2) -> void:
	if not is_instance_valid(c):
		return

	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0

	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y

	c.custom_minimum_size = sz
	c.size = sz
	c.position = pos
	c.pivot_offset = sz * 0.5

func _layout_board_centered() -> void:
	if not is_instance_valid(board_zoom):
		return

	var vp := get_viewport_rect().size
	var board_pos := Vector2(
		roundf((vp.x - LOGICAL_BOARD_SIZE.x) * 0.5),
		roundf((vp.y - LOGICAL_BOARD_SIZE.y) * 0.5)
	)

	var zoom_scale := _board_base_scale_factor * current_scale

	board_zoom.set_as_top_level(true)
	_pin_control_rect(board_zoom, board_pos, LOGICAL_BOARD_SIZE)
	board_zoom.clip_contents = false
	board_zoom.scale = Vector2.ONE * zoom_scale
	board_zoom.pivot_offset = LOGICAL_BOARD_SIZE * 0.5

	if is_instance_valid(_board_scale_node):
		_pin_control_rect(_board_scale_node, Vector2.ZERO, LOGICAL_BOARD_SIZE)
		_board_scale_node.pivot_offset = LOGICAL_BOARD_SIZE * 0.5

	var texrect := _get_texrect()
	if is_instance_valid(texrect):
		_pin_control_rect(texrect, Vector2.ZERO, LOGICAL_BOARD_SIZE)
		texrect.scale = Vector2.ONE
		texrect.pivot_offset = LOGICAL_BOARD_SIZE * 0.5

	if is_instance_valid(piece_container):
		piece_container.position = LOGICAL_BOARD_SIZE * 0.5
		piece_container.scale = Vector2.ONE

	_apply_board_draw_order()
	
func _set_canvas_z(item: CanvasItem, z: int) -> void:
	if not is_instance_valid(item):
		return

	item.z_as_relative = false
	item.z_index = z

func _apply_top_ui_draw_order() -> void:
	if is_instance_valid(waiting_blur):
		_set_canvas_z(waiting_blur, Z_BLUR)

	if is_instance_valid(win_loss_label):
		_set_canvas_z(win_loss_label, Z_UI_TOP)

	if is_instance_valid(waiting_label):
		_set_canvas_z(waiting_label, Z_UI_TOP)

	if is_instance_valid(sent_label):
		_set_canvas_z(sent_label, Z_UI_TOP)

	if is_instance_valid(_aim_instruction_label):
		_set_canvas_z(_aim_instruction_label, Z_UI_TOP)
		
func _apply_water_ripple_draw_order(root: Node) -> void:
	if not is_instance_valid(root):
		return

	for child in root.get_children():
		if child is CanvasItem:
			var ci := child as CanvasItem
			var n := String(child.name).to_lower()

			if child != background and child != waiting_blur:
				if n.find("ripple") >= 0 or n.find("water") >= 0:
					_set_canvas_z(ci, Z_WATER_RIPPLE)

		_apply_water_ripple_draw_order(child)

func _apply_piece_draw_order() -> void:
	if not is_instance_valid(piece_container):
		return

	# Container is the absolute piece layer.
	piece_container.z_as_relative = false
	piece_container.z_index = Z_PIECES

	for piece in piece_container.get_children():
		if piece == _mushroom_layer:
			if piece is CanvasItem:
				var mushroom_ci := piece as CanvasItem
				mushroom_ci.z_as_relative = true
				mushroom_ci.z_index = -1
			continue

		if piece is CanvasItem:
			var piece_ci := piece as CanvasItem
			piece_ci.z_as_relative = true
			piece_ci.z_index = 0

		var arrow := piece.get_node_or_null("Arrow") as CanvasItem
		if arrow:
			arrow.z_as_relative = false
			arrow.z_index = Z_ARROWS

		var sprite := piece.get_node_or_null("Sprite2D") as CanvasItem
		if sprite:
			sprite.z_as_relative = true
			sprite.z_index = 1

		var ring := piece.get_node_or_null("HighlightRing") as CanvasItem
		if ring:
			ring.z_as_relative = true
			ring.z_index = 2
				
func _apply_board_draw_order() -> void:
	if is_instance_valid(background):
		_set_canvas_z(background, Z_BACKGROUND)

	_apply_water_ripple_draw_order(self)

	if is_instance_valid(game_board):
		_set_canvas_z(game_board, Z_BOARD)

	if is_instance_valid(board_zoom):
		_set_canvas_z(board_zoom, Z_BOARD)

	if is_instance_valid(_board_scale_node):
		_set_canvas_z(_board_scale_node, Z_BOARD)

	var texrect := _get_texrect()
	if is_instance_valid(texrect):
		_set_canvas_z(texrect, Z_BOARD)

	_apply_piece_draw_order()
	_apply_top_ui_draw_order()
	
func _physics_process(delta: float) -> void:
	if _pdiff_active and _pdiff != null:
		_pdiff.tick(_collect_diff_pieces())
 
	_kill_check_accum += delta
	if _kill_check_accum >= KILL_CHECK_INTERVAL:
		_kill_check_accum = 0.0
		_update_piece_center_debug_dots()  # only draws if debug is on
		if not _kill_detection_enabled:
			return
		_fallback_kill_pass()
		
func _resync_piece_sprite_sizes() -> void:
	if not is_instance_valid(piece_container):
		return

	for piece in piece_container.get_children():
		if not (piece is RigidBody2D):
			continue

		var sprite := piece.find_child("Sprite2D", true, false) as Sprite2D
		if sprite == null or sprite.texture == null:
			continue

		var ts: Vector2 = sprite.texture.get_size()
		if ts.x <= 0.0 or ts.y <= 0.0:
			continue

		# This is logical board-space size. BoardZoom handles screen-width scaling.
		sprite.scale = IOS_PENGUIN_VISUAL_SIZE / ts
		sprite.centered = true
		sprite.position = Vector2.ZERO
		
func _collect_diff_pieces() -> Array:
	var p1: Array = []
	var p2: Array = []
	for c in piece_container.get_children():
		if c is RigidBody2D and c.has_meta("player"):
			if int(c.get_meta("player", 1)) == 1:
				p1.append(c)
			else:
				p2.append(c)
	var out: Array = []
	out.append_array(p1)
	out.append_array(p2)
	return out

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K:
			_set_kill_debug_visible(not _kill_debug_showing)

func _fallback_kill_pass() -> void:
	if _loading_board_data or _last_safe_poly.is_empty() or not is_instance_valid(board_zoom):
		return
	var to_bz: Transform2D = board_zoom.get_global_transform().affine_inverse()
	for n in piece_container.get_children():
		if not (n is RigidBody2D): continue
		if n.get_meta("dying", false): continue
		var p_bz: Vector2 = to_bz * (n as Node2D).global_position
		var in_safe: bool = Geometry2D.is_point_in_polygon(p_bz, _last_safe_poly)
		var in_hole: bool = false
		for hp in _last_hole_polys_cached:
			if not hp.is_empty() and Geometry2D.is_point_in_polygon(p_bz, hp):
				in_hole = true
				break
		if (not in_safe) or in_hole:
			if DEBUG_KILL:
				print("[KILL] fallback → ", n.name, " in_safe=", in_safe, " in_hole=", in_hole, " pos=", p_bz)
			_safe_kill(n)
			
func _align_piece_container_to_texrect() -> void:
	_ensure_piece_container_hosted_in_board_zoom()
	
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
	
func _poly_inside_other(inner: PackedVector2Array, outer: PackedVector2Array) -> bool:
	for p in inner:
		if not Geometry2D.is_point_in_polygon(p, outer):
			return false
	return true

func _extract_holes_from_transparency(img: Image, outer: PackedVector2Array, alpha_threshold := 0.5, simplify_epsilon := 1.5) -> Array[PackedVector2Array]:
	var holes: Array[PackedVector2Array] = []

	# 1) Build alpha mask of the *iceberg* (opaque)
	var bm_alpha := BitMap.new()
	bm_alpha.create_from_image_alpha(img, alpha_threshold)

	# 2) Invert to get a mask where *transparent* is true
	var bm_trans := _invert_bitmap(bm_alpha)

	# 3) Polygons from the transparent regions
	var rect_img := Rect2i(Vector2i.ZERO, img.get_size())
	var transparent_polys: Array[PackedVector2Array] = bm_trans.opaque_to_polygons(rect_img, simplify_epsilon)

	# 4) Keep only transparent islands fully inside the iceberg
	for poly in transparent_polys:
		if poly.size() >= 3 and _poly_inside_other(poly, outer):
			holes.append(poly)

	return holes

var _hole_debug_nodes: Array[Polygon2D] = []

func _invert_bitmap(src: BitMap) -> BitMap:
	var sz := src.get_size()        # Vector2i
	var dst := BitMap.new()
	dst.create(sz)
	for y in sz.y:
		for x in sz.x:
			var p := Vector2i(x, y)
			dst.set_bitv(p, not src.get_bitv(p))
	return dst

func _set_hole_debug_polys(hole_locals: Array[PackedVector2Array]) -> void:
	# grow/reuse nodes
	while _hole_debug_nodes.size() < hole_locals.size():
		var p := Polygon2D.new()
		p.z_index = 502
		p.color = Color(1, 0, 0, 0.35)  # red translucent
		board_zoom.add_child(p)         # BoardZoom-local coords
		_hole_debug_nodes.append(p)

	# update current
	for i in hole_locals.size():
		_hole_debug_nodes[i].visible = true
		_hole_debug_nodes[i].polygon = hole_locals[i]

	# hide extras
	for j in range(hole_locals.size(), _hole_debug_nodes.size()):
		if is_instance_valid(_hole_debug_nodes[j]):
			_hole_debug_nodes[j].visible = false
			
func _apply_ios_board_texture_layout() -> void:
	var texrect := _get_texrect()
	if not is_instance_valid(texrect):
		return

	if DEBUG_SHRINK and texrect.texture:
		print("[BOARD_TEX] native_texture_size=", texrect.texture.get_size(),
			" | rect_size=", LOGICAL_BOARD_SIZE,
			" | logical=", LOGICAL_BOARD_SIZE
		)

	_pin_control_rect(texrect, Vector2.ZERO, LOGICAL_BOARD_SIZE)
	texrect.scale = Vector2.ONE
	texrect.pivot_offset = LOGICAL_BOARD_SIZE * 0.5
	texrect.stretch_mode = TextureRect.STRETCH_SCALE
	texrect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texrect.modulate = Color.WHITE
	_set_canvas_z(texrect, Z_BOARD)
	
func _get_texrect() -> TextureRect:
	if is_instance_valid(_texrect):
		return _texrect

	# If a BoardScaler already exists, prefer its child
	var scaler := game_board.get_node_or_null("BoardScaler") as Control
	if is_instance_valid(scaler):
		_texrect = scaler.get_node_or_null("TextureRect") as TextureRect
		if is_instance_valid(_texrect):
			return _texrect

	# Final fallback: recursive search
	var any := game_board.find_child("TextureRect", true, false)
	_texrect = any if (any is TextureRect) else null
	return _texrect

func _ensure_board_scaler() -> void:
	if is_instance_valid(_board_scale_node):
		_pin_control_rect(_board_scale_node, Vector2.ZERO, LOGICAL_BOARD_SIZE)
		_apply_ios_board_texture_layout()
		_apply_board_draw_order()
		return

	var existing := game_board.get_node_or_null("BoardScaler") as Control
	if is_instance_valid(existing):
		_board_scale_node = existing
		_pin_control_rect(_board_scale_node, Vector2.ZERO, LOGICAL_BOARD_SIZE)

		if not is_instance_valid(_texrect):
			_texrect = existing.get_node_or_null("TextureRect") as TextureRect

		_apply_ios_board_texture_layout()
		_apply_board_draw_order()
		print("[SHRINK] Using existing BoardScaler.")
		return

	var tex := _get_texrect()
	if not is_instance_valid(tex):
		push_warning("[SHRINK] _ensure_board_scaler: no TextureRect to wrap.")
		return

	var wrapper := Control.new()
	wrapper.name = "BoardScaler"
	_pin_control_rect(wrapper, Vector2.ZERO, LOGICAL_BOARD_SIZE)

	game_board.add_child(wrapper)
	game_board.move_child(wrapper, tex.get_index())

	tex.reparent(wrapper)
	tex.position = Vector2.ZERO
	tex.scale = Vector2.ONE

	_board_scale_node = wrapper
	_apply_ios_board_texture_layout()
	_apply_board_draw_order()
	print("[SHRINK] BoardScaler injected.")
	
func _ready():
	modulate.a = 0.0

	# Wait a single frame for the viewport size to be accurate before we do any calculations.
	await get_tree().process_frame
	Engine.physics_ticks_per_second = 60
	# 1. Dynamically set the board's target size based on the screen width.
	_recalc_board_base_scale_factor()

	# 2. Standard scene and UI setup.
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_bg_for_dark(is_dark)
	self.z_index = 10
	_apply_board_draw_order()
	randomize()
	print("Knockout Scene ready!")

	if is_instance_valid(dot_timer):
		dot_timer.connect("timeout", _on_dot_timer_timeout)
	if is_instance_valid(send_button):
		send_button.visible = false
		send_button.pressed.connect(send_game)
	else:
		push_warning("No %SendButton in scene")
		
	_recompute_send_button_visibility()
	if rules_button:    rules_button.pressed.connect(on_rules_button_pressed)
	if settings_button: settings_button.pressed.connect(_on_settings_button_pressed)
	_wire_water_kill_areas()

	# 3. Configure the TextureRect and BoardZoom nodes to use our logical size.
	var texrect := _get_texrect()
	if is_instance_valid(texrect):
		_apply_ios_board_texture_layout()

	if is_instance_valid(board_zoom):
		board_zoom.set_as_top_level(true)
		board_zoom.clip_contents = false
		current_scale = ZOOM_START
		board_zoom.scale = Vector2.ONE * (_board_base_scale_factor * current_scale)
		board_zoom.pivot_offset = LOGICAL_BOARD_SIZE * 0.5
		board_zoom.resized.connect(func():
			_layout_board_centered()
		)
	
	_ensure_board_scaler()
	_apply_ios_board_texture_layout()
	_layout_board_centered()
	_ensure_piece_container_hosted_in_board_zoom()
	_ensure_debug_preview_hosted_in_board_zoom()
	_set_kill_debug_visible(false)
	_ensure_kill_overlay()
	_apply_board_draw_order()
	
	# 4. Calculate the base scale factor and apply the initial board state.
	_recalc_board_base_scale_factor()
	_rebuild_base_polys_from_png()
	_apply_board_index_immediate(0) # Sets initial TextureRect scale and generates polygons.

	# 5. Connect signals to handle screen resizing events.
	get_viewport().size_changed.connect(_on_viewport_resize)

	# 6. Final game initialization steps.
	_board_initialized = true
	print("Board initialized and scaled.")
	if PDIFF_ENABLED:
		await get_tree().create_timer(0.4).timeout   # let board settle/layout
		
	if _pending_replay_str != "":
		parse_replay_string(_pending_replay_str, _incoming_data_seq)
		_pending_replay_str = ""
		
	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("AppPlugin Available")
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
	else:
		var dev_payload := {
			"isYourTurn": true,
			"player": "1",
			"myPlayerId": "TEST2",
			"player1": "TEST1",
			"player2": "TEST2",
			"mode": "3",
			"replay": "board:1#-41.490452,-18.381981,2,2.568027,0.311887,11.024456#35.786495,56.762127,1,0.193446,3.140568,125.850670|shoot:1|board:2#-24.121695,-12.309731,2,1.882683,0.311887,0.000000#-135.776291,51.576973,1,4.711365,-0.038352,95.461876|board:2#-24.121695,-12.309731,2,1.882683,0.311887,0.000000#-135.776291,51.576973,1,4.711365,-0.038352,95.461876"
		}
		_set_game_data(JSON.stringify(dev_payload))

	call_deferred("_seed_area_overlaps")
	_ensure_piece_container_hosted_in_board_zoom()
	_resync_piece_sprite_sizes()
	_refresh_safe_polys_for_transform()
	_seed_area_overlaps()

func _seed_area_overlaps() -> void:
	if not is_instance_valid(_safe_area): return
	# Touch the overlap list so the physics server evaluates it this frame
	_safe_area.get_overlapping_bodies()

func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color(0.08, 0.08, 0.08) if is_dark else Color("#68d4f6")

# --- Game Data Handling ---

func _animate_and_fire_from_current_arrows() -> void:
	_stop_all_highlights()
	_recompute_send_button_visibility()

	var pieces: Array[RigidBody2D] = []
	for c in piece_container.get_children():
		if c is RigidBody2D and c.has_meta("player"):
			pieces.append(c)

	for p in pieces:
		var ang_deg: float = float(p.get_meta("shoot_dir", 0.0))
		var pow_px: float = float(p.get_meta("power", 0.0))
		_set_piece_arrow_from_data(p, deg_to_rad(ang_deg), pow_px, 0.22)

	await get_tree().create_timer(0.5).timeout

	var rot_tw := create_tween().set_parallel()
	for p in pieces:
		var ang_deg: float = float(p.get_meta("shoot_dir", 0.0))
		_rotate_piece_to_dir(rot_tw, p, deg_to_rad(ang_deg), 0.5)

	if rot_tw.is_running():
		await rot_tw.finished

	await get_tree().create_timer(0.5).timeout

	for p in pieces:
		var ang_deg: float = float(p.get_meta("shoot_dir", 0.0))
		var pow_px: float = float(p.get_meta("power", 0.0))
		_fire_piece_from_arrow(p, deg_to_rad(ang_deg), pow_px)

	await _wait_for_pieces_to_settle(10.0, 8, IOS_STOP_LINEAR_SPEED, IOS_STOP_ANGULAR_SPEED)
	
# After physics settles, move pieces to the next-board inset, shrink board, and enable re-aiming
func _stage_after_local_play(next_idx: int) -> void:
	_dbg_board_state("staging pre-shrink")

	_is_zooming = true
	_update_piece_interactivity()
	_stop_all_highlights()

	for c in piece_container.get_children():
		if c is RigidBody2D and c.has_meta("player"):
			var rb := c as RigidBody2D
			rb.freeze = true
			rb.linear_velocity = Vector2.ZERO
			rb.angular_velocity = 0.0
			rb.freeze = false

	_hide_all_arrows_and_refresh_highlights()

	var will_shrink := _clamp_board_index(next_idx) != _clamp_board_index(_current_board_index)
	if will_shrink:
		_set_kill_detection_enabled(false)

	await _tween_board_index_to(next_idx, 0.42)

	if will_shrink and _kill_detection_enabled == false:
		_set_kill_detection_enabled(true)

	_is_zooming = false
	_staged_launch_mode = true
	_staged_next_index = next_idx

	_update_piece_interactivity()
	call_deferred("_apply_turn_highlights_based_on_arrows")
	_recompute_send_button_visibility()
	
func _set_game_data(new_game_data_json: String):
	var parsed = JSON.parse_string(new_game_data_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	_stop_all_highlights()
	stop_waiting_animation()
	_incoming_data_seq += 1
	var data_seq := _incoming_data_seq

	_loading_board_data = false
	_replay_in_progress = false
	_staged_launch_mode = false
	_staged_pre_board_str = ""
	_staged_next_index = 0

	var data: Dictionary = parsed
	is_your_turn = data.get("isYourTurn", false)
	print("INCOMING RAW DATA: ", data)
	var replay_str: String = data.get("replay", "")
	var player1_id: String = str(data.get("player1", ""))
	var player2_id: String = str(data.get("player2", ""))
	my_player_id = str(data.get("myPlayerId", ""))
	map_mode = int(data.get("map", data.get("mode", map_mode)))
	_apply_map_theme(map_mode)

	spectator_mode = false
	if my_player_id != "" and player1_id != "" and player2_id != "":
		spectator_mode = my_player_id != player1_id and my_player_id != player2_id

	if spectator_mode:
		player = 1
		is_my_turn = false
		you_label.text = ""
		spec_label.show()
	else:
		is_my_turn = is_your_turn
		if my_player_id != "" and my_player_id == player1_id:
			player = 1
		elif my_player_id != "" and my_player_id == player2_id:
			player = 2
		elif player1_id != "" and player2_id == "":
			player = 2
		elif player1_id == "" and player2_id != "":
			player = 1
		else:
			player = int(data.get("player", player))

		if is_instance_valid(spec_label):
			spec_label.hide()

	print("P1ID: ", player1_id, " | P2ID: ", player2_id, " | MyID: ", my_player_id, " | Player: ", player, " | spectator=", spectator_mode)
	
	# Brand-new-to-me game: my_player_id isn't recognized as an assigned slot yet.
	# Spectators never see the goal popup.
	if not spectator_mode and (my_player_id == "" or (my_player_id != player1_id and my_player_id != player2_id)):
		_pending_goal_popup = true

	if player == 1:
		left_preserver.texture = BLACK_PRESERVER_TEX
		right_preserver.texture = GRAY_PRESERVER_TEX
	else:
		left_preserver.texture = GRAY_PRESERVER_TEX
		right_preserver.texture = BLACK_PRESERVER_TEX

	if spectator_mode:
		if data.has("avatar1") and is_instance_valid(player_avatar_display):
			player_avatar_display.call_deferred("update_avatar_from_data", _parse_avatar_string(str(data["avatar1"])))
		if data.has("avatar2") and is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", _parse_avatar_string(str(data["avatar2"])))
	else:
		var opponent_avatar_key := "avatar2" if player == 1 else "avatar1"
		if data.has(opponent_avatar_key) and is_instance_valid(opp_avatar_display):
			opp_avatar_display.call_deferred("update_avatar_from_data", _parse_avatar_string(str(data[opponent_avatar_key])))
			print("[AVATAR] Updated opponent avatar from ", opponent_avatar_key)

	if replay_str != "":
		if _board_initialized:
			parse_replay_string(replay_str, data_seq)
		else:
			_pending_replay_str = replay_str
	else:
		print("New Game - No replay string found.")

	_update_piece_interactivity()

	if spectator_mode:
		is_my_turn = false
		stop_waiting_animation()
		_stop_all_highlights()
		_recompute_send_button_visibility()
	else:
		call_deferred("_apply_turn_highlights_based_on_arrows")

		if not is_my_turn and not game_over:
			start_waiting_animation()
			_recompute_send_button_visibility()

	if replay_str == "":
		modulate.a = 1.0

func send_game() -> void:
	print("[Send] send_game() called")
	_stop_all_highlights()
	await get_tree().process_frame
	
	# When the scene stayed open, old hide/reset logic can wipe the opponent's
	# stored power meta after a received replay. Restore opponent setup data from
	# last_pre_round before checking readiness.
	if not last_pre_round.is_empty():
		var pending_arr: Array = last_pre_round.get("pieces", [])
		var live_pieces: Array[Node] = []

		for c in piece_container.get_children():
			if c is RigidBody2D and c.has_meta("player"):
				live_pieces.append(c)

		var restore_count: int = min(live_pieces.size(), pending_arr.size())
		for i in restore_count:
			var piece := live_pieces[i]
			var pd: Dictionary = pending_arr[i]

			if int(piece.get_meta("player", -1)) == player:
				continue

			var pending_power := float(pd.get("power", 0.0))
			if pending_power > 0.5 and float(piece.get_meta("power", 0.0)) <= 0.5:
				piece.set_meta("shoot_dir", rad_to_deg(float(pd.get("shoot_dir", 0.0))))
				piece.set_meta("power", pending_power)

	# If we already auto-played locally, this click FINALIZES and sends.
	if _staged_launch_mode:
		var payload: Dictionary = {}
		var setup_str := _serialize_current_board(_staged_next_index, false, true)
		var staged_replay_str := "%s|shoot:1|%s|%s" % [_staged_pre_board_str, setup_str, setup_str]
		payload["replay"] = staged_replay_str

		avatar_key = ("avatar1" if player == 1 else "avatar2")
		if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
			payload[avatar_key] = player_avatar_display.get_avatar_data_string()

		game_ended = check_win()
		if game_ended and win_loss_state != "":
			payload["winner"] = my_player_id + "|" + win_loss_state

		var appPlugin := Engine.get_singleton("AppPlugin")
		if appPlugin:
			appPlugin.updateGameData(JSON.stringify(payload))
		else:
			print("AppPlugin is null. Cannot send game data.")

		# Reset staged mode and hand off turn
		_staged_launch_mode = false
		_staged_pre_board_str = ""
		is_my_turn = false
		_update_piece_interactivity()
		if not game_over:
			play_sent_animation()
		return

	# Not staged yet → decide whether to auto-play first or just send normally.
	var my_ready := _all_my_arrows_visible() and _all_my_piece_powers_nonzero()
	var opp_ready := _all_opponent_arrows_nonzero()
	
	print("[Send] readiness | staged=", _staged_launch_mode,
		" | my_ready=", my_ready,
		" | opp_ready=", opp_ready,
		" | current_idx=", _current_board_index,
		" | has_last_pre=", not last_pre_round.is_empty()
	)

	# If EVERYONE has set arrows, we do the local play NOW, then let user re-aim.
	if my_ready and opp_ready:
		# 1) Capture the initial board (with current aims) as the first segment.
		_staged_pre_board_str = _serialize_current_board(_current_board_index, false, true)

		# 2) Play locally (animate + physics)
		_replay_in_progress = true
		_update_piece_interactivity()
		_recompute_send_button_visibility()
		await _animate_and_fire_from_current_arrows()
		_replay_in_progress = false
		
		if check_win():
			_staged_launch_mode = false
			_staged_pre_board_str = ""
			_update_piece_interactivity()
			_recompute_send_button_visibility()
			return

		# 3) Stage the "post" board at next index and let the player aim again.
		var next_idx: int = _next_board_index_after_round(_current_board_index)
		await _stage_after_local_play(next_idx)

		# Done: DO NOT send yet. The next click will send the 3-chunk payload.
		return

	# Fallback: opponent not ready
	var replay_string_to_send := _build_replay_string()
	var payload2: Dictionary = { "replay": replay_string_to_send }

	avatar_key = ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload2[avatar_key] = player_avatar_display.get_avatar_data_string()

	game_ended = check_win()
	if game_ended and win_loss_state != "":
		payload2["winner"] = my_player_id + "|" + win_loss_state

	print("[Send] PAYLOAD: ", payload2)
	var appPlugin2 := Engine.get_singleton("AppPlugin")
	if appPlugin2:
		appPlugin2.updateGameData(JSON.stringify(payload2))
	else:
		print("AppPlugin is null. Cannot send game data.")

	is_my_turn = false
	_update_piece_interactivity()
	if not game_over:
		play_sent_animation()
		
func _build_replay_string() -> String:
	var have_prev := not last_pre_round.is_empty()
	var idx := _current_board_index
	var my_ready := _all_my_arrows_visible()
	var opp_ready := _all_opponent_arrows_nonzero()

	# 1) First ever send in a fresh game: one board, no index, no shoot
	if not have_prev:
		return _serialize_current_board(idx, false, false)  # include_index = false -> "board:"

	# 2) Setup echo from the second player (initial placement, no arrows yet)
	#    Use index 0 and duplicate the board, no shoot.
	if idx == 0 and not my_ready and not opp_ready and last_post_round.is_empty():
		var b0 := _serialize_current_board(0, false, true)
		return "%s|%s" % [b0, b0]

	# 3) Full round ready fallback. Normal flow should stage locally first,
	# but if this path is used, duplicate the current setup-style board like iOS.
	if my_ready and opp_ready:
		var pre := _serialize_current_board(idx, false, true)
		var setup := _serialize_current_board(idx, false, true)
		return "%s|shoot:1|%s|%s" % [pre, setup, setup]

	var b4 := _serialize_current_board(idx, false, true)
	return "%s|%s" % [b4, b4]

func _serialize_current_board(board_idx: int, zero_power: bool, include_index: bool = true) -> String:
	var parts := PackedStringArray()

	for n in piece_container.get_children():
		if not (n is RigidBody2D): continue
		if n.has_meta("dying") and n.get_meta("dying"): continue

		var b := n as Node2D
		var pos: Vector2 = b.position
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
	var header := "board:" + (str(board_idx) if include_index else "")
	return "%s%s%s" % [header, "#" if body.length() > 0 else "", body]
	
func _all_opponent_arrows_nonzero() -> bool:
	var any := false
	for n in piece_container.get_children():
		if not (n is RigidBody2D): continue
		if n.has_meta("dying") and n.get_meta("dying"): continue
		if int(n.get_meta("player", -1)) == player: continue
		any = true
		if float(n.get_meta("power", 0.0)) <= 0.0:
			return false
	return any  # true only if there was at least one opponent piece and none had zero power
	
func _other_player_id() -> int:
	return 2 if player == 1 else 1


func _next_board_index_after_round(from_idx: int) -> int:
	return int(max(0, from_idx)) + 1


func _board_player_power_state(bd: Dictionary, owner_id: int) -> Dictionary:
	var any_piece := false
	var any_power := false
	var all_power := true

	for pd in bd.get("pieces", []):
		if int(pd.get("player", -1)) != owner_id:
			continue

		any_piece = true
		var power_val := float(pd.get("power", 0.0))
		if power_val > 0.5:
			any_power = true
		else:
			all_power = false

	return {
		"any_piece": any_piece,
		"any_power": any_power,
		"all_power": any_piece and all_power
	}


func _board_all_players_powered(bd: Dictionary) -> bool:
	var p1 := _board_player_power_state(bd, 1)
	var p2 := _board_player_power_state(bd, 2)
	return bool(p1["all_power"]) and bool(p2["all_power"])

func _all_my_arrows_visible() -> bool:
	var mine := _owned_live_pieces()
	if mine.is_empty():
		return false
	for p in mine:
		var arrow := p.get_node_or_null("Arrow") as CanvasItem
		if arrow == null or not arrow.visible:
			return false
	return true

func _all_my_piece_powers_nonzero() -> bool:
	var mine := _owned_live_pieces()
	if mine.is_empty():
		return false

	for p in mine:
		if float(p.get_meta("power", 0.0)) <= 0.5:
			return false

	return true

# --- Replay Parsing & Board Setup ---

func _update_piece_interactivity() -> void:
	for piece in piece_container.get_children():
		if piece.has_method("set_controlled_by_me"):
			var owner_id: int = int(piece.get_meta("player", -1))
			var can_control: bool = (
				not spectator_mode
				and owner_id == player
				and _can_show_aim_ui()
			)
			piece.set_controlled_by_me(can_control)

	if spectator_mode:
		_stop_all_highlights()

	_recompute_send_button_visibility()
	
func parse_replay_string(replay: String, data_seq: int = -1) -> void:
	if _is_stale_data_seq(data_seq):
		return

	_loading_board_data = true
	_set_kill_detection_enabled(false)
	_staged_launch_mode = false
	_staged_pre_board_str = ""
	_staged_next_index = 0

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
		_loading_board_data = false
		_replay_in_progress = false
		_set_kill_detection_enabled(not game_over)
		return

	last_pre_round = boards[0]
	last_post_round = boards[1] if (boards.size() > 1) else {}
	last_pending_setup_round = {}

	var pre_idx := int(last_pre_round.get("round", 0))
	var complete_board_without_shoot := (not shoot_flag) and _board_all_players_powered(last_pre_round)

	if complete_board_without_shoot:
		last_post_round = {}
		print("[REPLAY] Complete setup board without shoot token. Playing it locally.")

	if shoot_flag and boards.size() >= 3:
		var possible_setup: Dictionary = boards[boards.size() - 1]
		var p1_state := _board_player_power_state(possible_setup, 1)
		var p2_state := _board_player_power_state(possible_setup, 2)

		if bool(p1_state["any_power"]) != bool(p2_state["any_power"]):
			last_pending_setup_round = possible_setup.duplicate(true)
			print("[REPLAY] Preserved pending setup board | p1=", p1_state, " | p2=", p2_state)

	var should_play_round := shoot_flag or complete_board_without_shoot

	print("[REPLAY] parse | pre_idx=", pre_idx,
		" | boards=", boards.size(),
		" | shoot_flag=", shoot_flag,
		" | complete_no_shoot=", complete_board_without_shoot,
		" | should_play=", should_play_round,
		" | has_pending_setup=", not last_pending_setup_round.is_empty()
	)

	_replay_in_progress = should_play_round

	_apply_board_index_immediate(pre_idx)
	if _is_stale_data_seq(data_seq):
		return

	_dbg_board_state("parse after pre_idx apply")

	await _setup_board_from_board_dict(last_pre_round)
	if _is_stale_data_seq(data_seq):
		return

	await get_tree().process_frame
	if _is_stale_data_seq(data_seq):
		return

	_ensure_piece_container_hosted_in_board_zoom()
	_resync_piece_sprite_sizes()
	_apply_aim_data_from_board_dict(last_pre_round, false)
	_refresh_safe_polys_for_transform()

	_set_kill_detection_enabled(false)

	for i in range(3):
		await get_tree().physics_frame
		if _is_stale_data_seq(data_seq):
			return

	_seed_area_overlaps()

	_loading_board_data = false
	_set_kill_detection_enabled(not game_over)
	modulate.a = 1.0

	if should_play_round:
		_update_piece_interactivity()
		_stop_all_highlights()
		await get_tree().process_frame
		if _is_stale_data_seq(data_seq):
			return
		_play_round_from_replay(last_pre_round, data_seq)
	else:
		_replay_in_progress = false
		_update_piece_interactivity()
		call_deferred("_apply_turn_highlights_based_on_arrows")
		_recompute_send_button_visibility()
		_maybe_show_pending_goal_popup()
		
func _maybe_show_pending_goal_popup() -> void:
	if not _pending_goal_popup or _goal_popup_shown:
		return
	_pending_goal_popup = false
	# Wait several physics frames so the safe area has stable overlap state
	# with all the freshly-spawned pieces before we add popup nodes to the tree.
	for i in range(4):
		await get_tree().physics_frame
	# Final sanity: pieces should now be reliably "inside" the safe area.
	_seed_area_overlaps()
	await get_tree().process_frame
	_show_goal_popup()
		
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
	var piece_strings: PackedStringArray = rest.split("#", false)
	for pstr in piece_strings:
		var params: PackedStringArray = pstr.split(",", false)
		if params.size() == 6:
			var d: Dictionary = {
				"pos": Vector2(params[0].to_float(), -params[1].to_float()),
				"player": params[2].to_int(),
				"rotation": -params[3].to_float(),
				"shoot_dir": -params[4].to_float(),
				"power": params[5].to_float()
			}
			parsed_pieces.append(d)

	return { "round": round_num, "pieces": parsed_pieces }
	
func _owned_live_pieces() -> Array:
	var out: Array = []
	for n in piece_container.get_children():
		if not (n is RigidBody2D):
			continue
		if n.has_meta("dying") and n.get_meta("dying"):
			continue
		if int(n.get_meta("player", -1)) != player:
			continue
		out.append(n)
	return out

func _animate_send_button(should_show: bool) -> void:
	if not is_instance_valid(send_button):
		return

	send_button.set_as_top_level(true)

	if not send_button.has_meta("home_y"):
		send_button.set_meta("home_y", send_button.global_position.y)

	if send_button.has_meta("sb_tween"):
		var old_tw: Variant = send_button.get_meta("sb_tween")
		if old_tw is Tween and (old_tw as Tween).is_running():
			(old_tw as Tween).kill()

	var vp: Rect2 = get_viewport_rect()
	var button_width: float = maxf(send_button.size.x, send_button.get_combined_minimum_size().x)
	var home_y: float = float(send_button.get_meta("home_y"))
	var home: Vector2 = Vector2(
		roundf((vp.size.x - button_width) * 0.5),
		home_y
	)

	var off_y: float = vp.size.y + send_button.size.y + 30.0
	var start_pos: Vector2 = Vector2(home.x, off_y)
	var is_send_visible := send_button.visible

	if should_show:
		if not is_send_visible:
			send_button.global_position = start_pos
			send_button.visible = true
			send_button.modulate.a = 1.0
		elif send_button.global_position.y > vp.size.y:
			send_button.global_position = start_pos

		var t_in := create_tween()
		send_button.set_meta("sb_tween", t_in)
		t_in.tween_property(send_button, "global_position", home, 0.35)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		if is_send_visible:
			var end_pos: Vector2 = Vector2(home.x, off_y)
			var t_out := create_tween()
			send_button.set_meta("sb_tween", t_out)
			t_out.tween_property(send_button, "global_position", end_pos, 0.25)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t_out.tween_callback(func():
				if is_instance_valid(send_button):
					send_button.visible = false
			)
			
func _set_kill_detection_enabled(on: bool) -> void:
	_kill_detection_enabled = on
	if is_instance_valid(_safe_area):
		_safe_area.set_deferred("monitoring", on)
		_safe_area.set_deferred("monitorable", on)
	for a in _hole_areas:
		if is_instance_valid(a):
			a.set_deferred("monitoring", on)
			a.set_deferred("monitorable", on)
	for a in _water_kill_areas:
		if is_instance_valid(a):
			a.set_deferred("monitoring", on)
			a.set_deferred("monitorable", on)

func _recompute_send_button_visibility() -> void:
	if spectator_mode:
		_animate_send_button(false)

		if is_instance_valid(_aim_instruction_label):
			_aim_instruction_label.visible = false
			_aim_instruction_label.modulate.a = 0.0

		return

	var can_aim := _can_show_aim_ui()
	var my_ready := _all_my_arrows_visible() and _all_my_piece_powers_nonzero()

	var should_show := (
		can_aim
		and my_ready
	)

	if is_instance_valid(send_button):
		send_button.text = "Send" if _staged_launch_mode else "Launch"

	_animate_send_button(should_show)

	_update_aim_instruction_label()
	
func _apply_zoom(target_zoom_level: float, dur: float = ZOOM_DUR) -> void:
	if not is_instance_valid(board_zoom) or game_over:
		return

	var target_scale_vector := Vector2.ONE * (_board_base_scale_factor * target_zoom_level)

	if DEBUG_SHRINK:
		print("[SHRINK] _apply_zoom start",
			" | current bz.scale=", board_zoom.scale,
			" | base=", _board_base_scale_factor,
			" | zoom=", target_zoom_level,
			" | target=", target_scale_vector,
			" | dur=", dur
		)

	_is_zooming = true
	_set_kill_detection_enabled(false)

	var tw := create_tween()
	tw.tween_property(board_zoom, "scale", target_scale_vector, dur)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

	await tw.finished

	_is_zooming = false
	current_scale = target_zoom_level

	if DEBUG_SHRINK:
		print("[SHRINK] _apply_zoom done | bz.scale=", board_zoom.scale)

	_layout_board_centered()
	_apply_board_draw_order()
	_refresh_safe_polys_for_transform()
	_seed_area_overlaps()
	_set_kill_detection_enabled(true)
	
func _apply_map_theme(mode: int) -> void:
	if is_instance_valid(background):
		match mode:
			2: background.color = Color("#ffd938")
			3: background.color = Color("#34f671")
			_: _apply_bg_for_dark(bool(SettingsManager.get_setting("global", "dark_mode", false)))

	var texrect := _get_texrect()
	if texrect:
		var new_tex: Texture2D = MAP1_TEX
		match mode:
			2: new_tex = MAP2_TEX
			3: new_tex = MAP3_TEX
			_: new_tex = MAP1_TEX
		if texrect.texture != new_tex:
			texrect.texture = new_tex
			_rebuild_base_polys_from_png()
			_apply_board_index_immediate(_current_board_index)
			_refresh_safe_polys_for_transform()


	if mode == 3:
		_spawn_mushrooms_for_map3()
	else:
		_clear_mushrooms()

	_apply_arrow_color_for_current_map()
	_apply_send_button_color_for_current_map()

func _setup_board_from_board_dict(bd: Dictionary) -> void:
	var arr: Array = bd.get("pieces", [])
	await _setup_board_from_data(arr)
	
func _apply_aim_data_from_board_dict(bd: Dictionary, show_arrows: bool = false) -> void:
	var arr: Array = bd.get("pieces", [])
	var pieces: Array[Node] = []

	for c in piece_container.get_children():
		if c is RigidBody2D and c.has_meta("player"):
			pieces.append(c)

	var count: int = min(pieces.size(), arr.size())
	for i in count:
		var piece := pieces[i]
		var pd: Dictionary = arr[i]

		var shoot_dir_rad := float(pd.get("shoot_dir", 0.0))
		var power_val := float(pd.get("power", 0.0))

		var arrow := piece.get_node_or_null("Arrow") as CanvasItem
		var should_show_arrow := show_arrows and power_val > 0.5

		if should_show_arrow:
			_set_piece_arrow_from_data(piece, shoot_dir_rad, power_val, 0.18)
		else:
			if arrow:
				arrow.visible = false
				arrow.z_as_relative = false
				arrow.z_index = Z_ARROWS
				arrow.modulate = _arrow_color_for_piece(piece)
				arrow.modulate.a = 1.0

		# Important: set these AFTER hiding the arrow.
		# Some piece-side hide logic can reset power to 0, which makes opponent readiness fail.
		piece.set_meta("shoot_dir", rad_to_deg(shoot_dir_rad))
		piece.set_meta("power", power_val)

	_apply_piece_draw_order()
	_apply_arrow_color_for_current_map()
	_recompute_send_button_visibility()
	
func _setup_board_from_data(board_data: Array[Dictionary]) -> void:
	if not _board_initialized:
		await get_tree().process_frame

	for child in piece_container.get_children():
		if child == _mushroom_layer:
			continue
		if child is RigidBody2D and child.has_meta("player"):
			child.queue_free()
	await get_tree().process_frame

	for piece_data in board_data:
		var piece_instance: RigidBody2D = PieceScene.instantiate()

		# Ownership / pose
		var player_num: int = int(piece_data.get("player", 1))
		piece_instance.set_meta("player", player_num)

		var raw_pos: Vector2 = piece_data.get("pos", Vector2.ZERO)
		piece_instance.position = raw_pos
		piece_instance.rotation = float(piece_data.get("rotation", 0.0))

		# Cache arrows from incoming data (keep visuals hidden unless we’re replaying)
		var sd_rad := float(piece_data.get("shoot_dir", 0.0))
		var pow_px := float(piece_data.get("power", 0.0))
		piece_instance.set_meta("shoot_dir", rad_to_deg(sd_rad))
		piece_instance.set_meta("power", pow_px)

		# Collisions
		piece_instance.collision_layer = 1
		piece_instance.collision_mask  = 1
		piece_instance.add_to_group("pieces")

		# Visuals
		var sprite := piece_instance.find_child("Sprite2D", true, false) as Sprite2D
		if sprite:
			sprite.texture = P1_PIECE_TEX if player_num == 1 else P2_PIECE_TEX
			var tex_size: Vector2 = sprite.texture.get_size() if sprite.texture else Vector2.ZERO
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = IOS_PENGUIN_VISUAL_SIZE / tex_size
				sprite.modulate = Color.WHITE
				sprite.z_as_relative = true
				sprite.z_index = 1

		var collision_shape := piece_instance.find_child("CollisionShape2D", true, false) as CollisionShape2D
		if collision_shape and collision_shape.shape is CircleShape2D:
			(collision_shape.shape as CircleShape2D).radius = PIECE_RADIUS_PX

		if piece_instance.has_method("set_physics_params"):
			piece_instance.set_physics_params({
				"PPM": PPM,
				"PIECE_RADIUS_PX": PIECE_RADIUS_PX,
				"FRICTION": FRICTION,
				"RESTITUTION": RESTITUTION,
				"LINEAR_DAMP": LINEAR_DAMP,
				"ANGULAR_DAMP": ANGULAR_DAMP,
				"DENSITY": DENSITY,
				"GRAVITY_SCALE": GRAVITY_SCALE,
				"CCD_MODE": CCD_MODE,
				"LOCK_ROTATION": LOCK_ROTATION,
				"CAN_SLEEP": CAN_SLEEP
			})

		piece_container.add_child(piece_instance)

		var arrow := piece_instance.get_node_or_null("Arrow") as CanvasItem
		if arrow:
			arrow.z_as_relative = false
			arrow.z_index = Z_ARROWS
			arrow.modulate = _arrow_color_for_piece(piece_instance)
			arrow.modulate.a = 1.0
			# Keep arrows hidden unless we’re animating a replay
			arrow.visible = false

		if piece_instance.has_method("set_controlled_by_me"):
			var can_control := (player_num == player) and is_my_turn and (not spectator_mode) and (not game_over) and (not _replay_in_progress)
			piece_instance.set_controlled_by_me(can_control)

		if piece_instance.has_signal("aim_changed"):
			piece_instance.connect("aim_changed", Callable(self, "_on_piece_aim_changed"))

		call_deferred("_try_watch_arrow_for_piece", piece_instance)
	_apply_piece_draw_order()
	_apply_top_ui_draw_order()

func _on_piece_aim_changed(_angle_deg: float, _pow: float) -> void:
	_recompute_send_button_visibility()

func _set_piece_arrow_from_data(piece: Node, shoot_dir_rad: float, pow_px: float, fade_sec: float) -> void:
	var angle_deg: float = rad_to_deg(shoot_dir_rad)
	piece.set_meta("shoot_dir", angle_deg)
	piece.set_meta("power", pow_px)

	var arrow := piece.get_node_or_null("Arrow") as CanvasItem
	var was_visible := arrow != null and arrow.visible and arrow.modulate.a > 0.05

	if piece.has_method("show_arrow_from_replay"):
		piece.call("show_arrow_from_replay", angle_deg, pow_px, fade_sec)
	elif arrow:
		arrow.visible = pow_px > 0.5

	arrow = piece.get_node_or_null("Arrow") as CanvasItem
	if arrow:
		arrow.z_as_relative = false
		arrow.z_index = Z_ARROWS
		arrow.modulate = _arrow_color_for_piece(piece)

		if pow_px > 0.5:
			arrow.visible = true

			if fade_sec > 0.0 and not was_visible:
				arrow.modulate.a = 0.0
				var tw := create_tween()
				tw.tween_property(arrow, "modulate:a", 1.0, fade_sec)\
					.set_trans(Tween.TRANS_SINE)\
					.set_ease(Tween.EASE_OUT)
			else:
				arrow.modulate.a = 1.0
		else:
			arrow.visible = false
			arrow.modulate.a = 1.0

	_apply_piece_draw_order()
	_recompute_send_button_visibility()
	
func _rotate_piece_to_dir(tw: Tween, piece: Node, shoot_dir_rad: float, dur: float) -> void:
	if not (piece is Node2D):
		return
	var n := piece as Node2D
	var start  := n.rotation
	var target := shoot_dir_rad + PIECE_HEADING_OFFSET
	tw.tween_method(
		func(t: float) -> void:
			n.rotation = lerp_angle(start, target, t),
		0.0, 1.0, dur
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _fire_piece_from_arrow(piece: Node, shoot_dir_rad: float, pow_px: float) -> void:
	if pow_px <= 0.5:
		return
	if piece is RigidBody2D:
		var rb := piece as RigidBody2D
		rb.freeze = false
		rb.sleeping = false
		rb.angular_velocity = 0.0
		rb.rotation = shoot_dir_rad + PIECE_HEADING_OFFSET
		rb.linear_velocity = Vector2(cos(shoot_dir_rad), sin(shoot_dir_rad)) * (pow_px * 2.0)
	if piece.has_method("fade_out_arrow_for_shot"):
		piece.call("fade_out_arrow_for_shot", 0.18)
		
func _hide_all_arrows_and_refresh_highlights() -> void:
	for piece in piece_container.get_children():
		if piece.has_method("hide_arrow"):
			piece.hide_arrow()
		else:
			var arrow := piece.get_node_or_null("Arrow") as CanvasItem
			if arrow:
				arrow.visible = false
		piece.set_meta("power", 0.0)
		piece.set_meta("shoot_dir", 0.0)
	_apply_piece_draw_order()
	call_deferred("_apply_turn_highlights_based_on_arrows")
	_recompute_send_button_visibility()
	
func _wire_water_kill_areas() -> void:
	_water_kill_areas.clear()
	for n in get_tree().get_nodes_in_group("water_kill"):
		if n is Area2D:
			var a := n as Area2D
			_water_kill_areas.append(a)
			var cb := Callable(self, "_on_water_kill_body_entered")
			if not a.body_entered.is_connected(cb):
				a.body_entered.connect(cb)

func _kill_piece(rb: RigidBody2D) -> void:
	if _loading_board_data or not _kill_detection_enabled:
		return
	if not is_instance_valid(rb): return
	if rb.get_meta("dying", false): return
	rb.set_meta("dying", true)

	# Stop visuals
	var arrow := rb.get_node_or_null("Arrow") as CanvasItem
	if arrow: arrow.visible = false
	var ring := rb.get_node_or_null("HighlightRing") as CanvasItem
	if ring: ring.visible = false

	# Defer ALL physics-state changes (Godot 4 signal/flush safe)
	rb.set_deferred("collision_layer", 0)
	rb.set_deferred("collision_mask", 0)
	rb.set_deferred("freeze", true)
	rb.set_deferred("linear_velocity", Vector2.ZERO)
	rb.set_deferred("angular_velocity", 0.0)

	var aim_area := rb.get_node_or_null("Area2D") as Area2D
	if aim_area:
		aim_area.set_deferred("monitoring", false)
		aim_area.set_deferred("monitorable", false)

	# Fade then free
	var spr := rb.get_node_or_null("Sprite2D") as Sprite2D
	if spr:
		var tw := create_tween()
		tw.tween_property(spr, "modulate:a", 0.0, 0.25)
		tw.finished.connect(Callable(rb, "queue_free"))
	else:
		rb.queue_free()
		
func _safe_kill(n: Node) -> void:
	if _loading_board_data or not _kill_detection_enabled:
		return
	if n is RigidBody2D:
		call_deferred("_kill_piece", n)
		
func _on_replay_round_finished(data_seq: int = -1) -> void:
	if _is_stale_data_seq(data_seq):
		return

	_hide_all_arrows_and_refresh_highlights()

	_replay_in_progress = false
	_is_zooming = true
	_update_piece_interactivity()
	_stop_all_highlights()
	_recompute_send_button_visibility()

	if check_win():
		_is_zooming = false
		_update_piece_interactivity()
		_recompute_send_button_visibility()
		return

	var next_idx := _next_board_index_after_round(_current_board_index)
	if not last_post_round.is_empty():
		next_idx = int(last_post_round.get("round", _next_board_index_after_round(_current_board_index)))

	_dbg_board_state("replay_finished computed next_idx=%d" % next_idx)

	var will_shrink := _clamp_board_index(next_idx) != _clamp_board_index(_current_board_index)
	if will_shrink:
		_set_kill_detection_enabled(false)

	await get_tree().create_timer(0.05).timeout
	if _is_stale_data_seq(data_seq):
		return

	if not last_post_round.is_empty():
		_dbg_board_state("before post snapshot")
		_apply_post_round_snapshot(last_post_round, next_idx)
		_dbg_board_state("after post snapshot")

	_dbg_board_state("before shrink tween")
	await _tween_board_index_to(next_idx, 0.42)
	if _is_stale_data_seq(data_seq):
		return

	_dbg_board_state("after shrink tween")

	if will_shrink and _kill_detection_enabled == false:
		_set_kill_detection_enabled(true)

	if not last_pending_setup_round.is_empty():
		var setup_idx := int(last_pending_setup_round.get("round", _current_board_index))

		if setup_idx != _current_board_index:
			_apply_board_index_immediate(setup_idx)

		_apply_post_round_snapshot(last_pending_setup_round, setup_idx)

		_apply_aim_data_from_board_dict(last_pending_setup_round, false)

		last_pre_round = last_pending_setup_round.duplicate(true)
		last_post_round = {}
		last_pending_setup_round = {}

		_staged_launch_mode = false
		_staged_pre_board_str = ""
		_staged_next_index = setup_idx

		print("[REPLAY] Applied pending setup board after replay. Opponent arrows are stored but hidden.")

	_is_zooming = false

	if spectator_mode:
		is_my_turn = false
		_stop_all_highlights()
		_update_piece_interactivity()
		_recompute_send_button_visibility()
		return

	_update_piece_interactivity()
	call_deferred("_apply_turn_highlights_based_on_arrows")
	_recompute_send_button_visibility()
	
func _piece_is_moving(rb: RigidBody2D, v_thresh := IOS_STOP_LINEAR_SPEED, w_thresh := IOS_STOP_ANGULAR_SPEED) -> bool:
	if rb.has_meta("dying") and rb.get_meta("dying"):
		return false
	if rb.sleeping:
		return false
	return rb.linear_velocity.length() > v_thresh or absf(rb.angular_velocity) > w_thresh

func _wait_for_pieces_to_settle(timeout_sec: float = 10.0, still_frames_needed: int = 8, v_thresh: float = IOS_STOP_LINEAR_SPEED, w_thresh: float = IOS_STOP_ANGULAR_SPEED) -> void:
	var start_ms := Time.get_ticks_msec()
	var still_frames := 0

	while (Time.get_ticks_msec() - start_ms) < int(timeout_sec * 1000.0):
		await get_tree().physics_frame

		var any_moving := false
		for n in piece_container.get_children():
			if n is RigidBody2D and is_instance_valid(n):
				var rb := n as RigidBody2D
				if _piece_is_moving(rb, v_thresh, w_thresh):
					any_moving = true
					break

		if any_moving:
			still_frames = 0
		else:
			still_frames += 1
			if still_frames >= still_frames_needed:
				break

	await get_tree().create_timer(0.35).timeout

func _apply_post_round_snapshot(post_board: Dictionary, _board_idx: int = -1) -> void:
	var arr: Array = post_board.get("pieces", [])

	# Collect only piece bodies
	var children_pieces: Array[Node] = []
	for c in piece_container.get_children():
		if c is RigidBody2D and c.has_meta("player"):
			children_pieces.append(c)

	var count: int = min(children_pieces.size(), arr.size())
	for i in count:
		var piece_node := children_pieces[i]
		var pd: Dictionary = arr[i]
		var pos: Vector2 = pd["pos"]
		var rot: float = float(pd["rotation"])

		if piece_node is RigidBody2D:
			var rb := piece_node as RigidBody2D
			rb.freeze = true
			rb.position = pos
			rb.rotation = rot
			rb.linear_velocity = Vector2.ZERO
			rb.angular_velocity = 0.0
			rb.freeze = false
		else:
			piece_node.position = pos
			piece_node.rotation = rot

func _play_round_from_replay(pre_board: Dictionary, data_seq: int = -1) -> void:
	if _is_stale_data_seq(data_seq):
		return

	print("[REPLAY] Starting round playback.")
	_replay_in_progress = true
	_update_piece_interactivity()
	_stop_all_highlights()
	_recompute_send_button_visibility()

	var pre_arr: Array = pre_board.get("pieces", [])

	var pieces: Array[RigidBody2D] = []
	for child in piece_container.get_children():
		if child is RigidBody2D and child.has_meta("player"):
			pieces.append(child)

	var count: int = min(pieces.size(), pre_arr.size())
	if count == 0:
		_on_replay_round_finished(data_seq)
		return

	for i in count:
		var piece := pieces[i]
		if not is_instance_valid(piece): continue
		var pd: Dictionary = pre_arr[i]
		_set_piece_arrow_from_data(piece, float(pd["shoot_dir"]), float(pd["power"]), 0.18)

	await get_tree().create_timer(0.5).timeout
	if _is_stale_data_seq(data_seq):
		return

	var rotation_tween := create_tween().set_parallel()
	for i in count:
		var piece := pieces[i]
		if not is_instance_valid(piece): continue
		var pd: Dictionary = pre_arr[i]
		_rotate_piece_to_dir(rotation_tween, piece, float(pd["shoot_dir"]), 0.5)

	if rotation_tween.is_running():
		await rotation_tween.finished
	if _is_stale_data_seq(data_seq):
		return

	await get_tree().create_timer(0.5).timeout
	if _is_stale_data_seq(data_seq):
		return

	if PDIFF_ENABLED and _pdiff != null:
		_pdiff.start("replay idx=%d" % _current_board_index)
		_pdiff_active = true
		_set_kill_detection_enabled(false)

	for i in count:
		var piece := pieces[i]
		if not is_instance_valid(piece): continue
		var pd: Dictionary = pre_arr[i]
		_fire_piece_from_arrow(piece, float(pd["shoot_dir"]), float(pd["power"]))

	await _wait_for_pieces_to_settle(10.0, 8, IOS_STOP_LINEAR_SPEED, IOS_STOP_ANGULAR_SPEED)
	if _is_stale_data_seq(data_seq):
		return

	if PDIFF_ENABLED and _pdiff != null:
		_pdiff_active = false
		_pdiff.stop()
		_pdiff.report()
		_set_kill_detection_enabled(true)

	_on_replay_round_finished(data_seq)
	
func _clamp_board_index(i: int) -> int:
	return clamp(i, 0, BOARD_MAX_INDEX)

func _board_size_for_index(i: int) -> float:
	return LOGICAL_BOARD_SIZE.x * _board_scale_for_index(i)

func _board_scale_for_index(i: int) -> float:
	return maxf(0.0, 1.0 - float(_clamp_board_index(i)) * 0.1)

func _apply_board_index_immediate(i: int) -> void:
	var old_idx: int = _current_board_index
	_current_board_index = int(max(0, i))
	var visual_idx: int = _clamp_board_index(_current_board_index)

	_dbg_board_state("apply_immediate BEFORE old=%d new=%d visual=%d" % [old_idx, _current_board_index, visual_idx])

	_ensure_board_scaler()
	_layout_board_centered()

	if is_instance_valid(_board_scale_node):
		var target := _target_scale_for_index(_current_board_index)
		_board_scale_node.scale = Vector2.ONE * target
		_board_scale_node.pivot_offset = LOGICAL_BOARD_SIZE * 0.5

		print("[SHRINK] apply_immediate SET scaler.scale=", _board_scale_node.scale,
			" | idx=", _current_board_index,
			" | visual_idx=", visual_idx,
			" | base=", _board_base_scale_factor,
			" | melt_scale=", _board_scale_for_index(_current_board_index),
			" | target=", target
		)

	_apply_piece_container_scale_for_board()
	_apply_ios_board_texture_layout()
	_layout_board_centered()

	_refresh_safe_polys_for_transform()
	_dbg_board_state("apply_immediate AFTER")
	
func _tween_board_index_to(i: int, dur: float = 0.42) -> void:
	var target_raw_idx: int = int(max(0, i))
	var target_visual_idx: int = _clamp_board_index(target_raw_idx)
	var current_visual_idx: int = _clamp_board_index(_current_board_index)

	_ensure_board_scaler()
	_layout_board_centered()

	var scaler := _board_scale_node
	if not is_instance_valid(scaler):
		push_warning("[SHRINK] tween failed: no BoardScaler")
		_current_board_index = target_raw_idx
		return

	if target_visual_idx == current_visual_idx:
		_current_board_index = target_raw_idx
		scaler.scale = Vector2.ONE * _target_scale_for_index(_current_board_index)
		scaler.pivot_offset = LOGICAL_BOARD_SIZE * 0.5
		_layout_board_centered()
		_resync_piece_sprite_sizes()
		_refresh_safe_polys_for_transform()
		_seed_area_overlaps()
		print("[SHRINK] tween skipped because visual target == current | raw_idx=", _current_board_index, " | visual_idx=", target_visual_idx)
		_dbg_board_state("tween skipped")
		return

	_is_zooming = true
	_set_kill_detection_enabled(false)

	var start_idx := _current_board_index
	var s0 := scaler.scale.x
	var s1 := _target_scale_for_index(target_raw_idx)

	print("[SHRINK] TWEEN START",
		" | idx ", start_idx, " -> ", target_raw_idx,
		" | visual ", current_visual_idx, " -> ", target_visual_idx,
		" | base=", _board_base_scale_factor,
		" | board_zoom.scale=", board_zoom.scale if is_instance_valid(board_zoom) else Vector2.ZERO,
		" | scaler.current=", scaler.scale,
		" | s0_actual=", s0,
		" | s1_target=", s1,
		" | expected_start_px=", LOGICAL_BOARD_SIZE * _board_base_scale_factor * current_scale * s0,
		" | expected_end_px=", LOGICAL_BOARD_SIZE * _board_base_scale_factor * current_scale * s1
	)

	_dbg_board_state("tween BEFORE")

	var last_bucket := [-1]

	var update_scale := func(t: float) -> void:
		var step_scale: float = lerp(s0, s1, t)

		scaler.scale = Vector2.ONE * step_scale
		scaler.pivot_offset = LOGICAL_BOARD_SIZE * 0.5

		if is_instance_valid(piece_container):
			piece_container.position = LOGICAL_BOARD_SIZE * 0.5
			piece_container.scale = Vector2.ONE

		_resync_piece_sprite_sizes()

		if DEBUG_SHRINK:
			var bucket := int(floor(t * 4.0))
			if bucket != int(last_bucket[0]):
				last_bucket[0] = bucket
				print("[SHRINK] TWEEN STEP",
					" | t=", String.num(t, 3),
					" | step_scale=", step_scale,
					" | board_px=", LOGICAL_BOARD_SIZE * _board_base_scale_factor * current_scale * step_scale,
					" | scaler.scale=", scaler.scale
				)

	var tw := create_tween()
	tw.tween_method(update_scale, 0.0, 1.0, dur)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_IN_OUT)

	await tw.finished

	_current_board_index = target_raw_idx
	scaler.scale = Vector2.ONE * _target_scale_for_index(_current_board_index)
	scaler.pivot_offset = LOGICAL_BOARD_SIZE * 0.5

	_layout_board_centered()

	if is_instance_valid(piece_container):
		piece_container.position = LOGICAL_BOARD_SIZE * 0.5
		piece_container.scale = Vector2.ONE

	_resync_piece_sprite_sizes()

	_is_zooming = false

	_refresh_safe_polys_for_transform()
	_seed_area_overlaps()
	_set_kill_detection_enabled(true)
	_fallback_kill_pass()

	print("[SHRINK] TWEEN FINISHED | committed raw_idx=", _current_board_index, " | visual_idx=", _clamp_board_index(_current_board_index))
	_dbg_board_state("tween AFTER COMMIT")
	
# --- Piece Highlighting ---
func _apply_turn_highlights_based_on_arrows() -> void:
	if spectator_mode or not _can_show_aim_ui():
		_stop_all_highlights()
		_recompute_send_button_visibility()
		return

	for piece in piece_container.get_children():
		var owner_id: int = int(piece.get_meta("player", -1))
		var ring := piece.get_node_or_null("HighlightRing") as TextureRect
		var anim := piece.get_node_or_null("HighlightAnimator") as AnimationPlayer

		if owner_id != player:
			if anim:
				anim.stop()
			if ring:
				ring.visible = false
			continue

		var arrow := piece.get_node_or_null("Arrow") as CanvasItem
		var arrow_visible := (arrow != null and arrow.visible)

		if arrow_visible:
			if anim:
				anim.stop()
			if ring:
				ring.visible = false
		else:
			if ring and anim:
				ring.z_as_relative = true
				ring.z_index = 2
				ring.visible = true
				if anim.has_animation("ring_anim"):
					anim.play("ring_anim")

	_recompute_send_button_visibility()
	
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

	if spectator_mode:
		_stop_highlight_for_piece(piece)
		_recompute_send_button_visibility()
		return

	if arrow.visible:
		arrow.z_as_relative = false
		arrow.z_index = Z_ARROWS
		arrow.modulate = _arrow_color_for_piece(piece)
		arrow.modulate.a = maxf(arrow.modulate.a, 1.0)
		_stop_highlight_for_piece(piece)
	else:
		if _can_show_aim_ui() and int(piece.get_meta("player", -1)) == player:
			var ring := piece.get_node_or_null("HighlightRing") as TextureRect
			var anim := piece.get_node_or_null("HighlightAnimator") as AnimationPlayer
			if ring and anim:
				ring.z_as_relative = true
				ring.z_index = 2
				ring.visible = true
				if anim.has_animation("ring_anim"):
					anim.play("ring_anim")

	_recompute_send_button_visibility()
	
func _try_watch_arrow_for_piece(piece: Node) -> void:
	await get_tree().process_frame
	var arrow := piece.get_node_or_null("Arrow") as CanvasItem
	if not arrow:
		return
	if not piece.has_meta("arrow_watch_connected"):
		arrow.connect("visibility_changed", Callable(self, "_on_arrow_visibility_changed").bind(piece))
		piece.set_meta("arrow_watch_connected", true)
	_on_arrow_visibility_changed(piece)

func set_my_turn(value: bool) -> void:
	is_my_turn = value
	call_deferred("_apply_turn_highlights_based_on_arrows")
	_recompute_send_button_visibility()

# --- UI Animations & State ---

func _animate_win_loss_label(text: String, color: Color) -> void:
	win_loss_label.text = text
	win_loss_label.add_theme_color_override("font_color", color)
	win_loss_label.visible = true
	await get_tree().process_frame
	
	win_loss_label.scale = Vector2.ZERO
	win_loss_label.pivot_offset = win_loss_label.size / 2.0
	var win_loss_tween := create_tween()
	win_loss_tween.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func check_win() -> bool:
	if _replay_in_progress:
		print("--- CHECKING WIN CONDITION --- (deferred; replay in progress)")
		return false

	print("--- CHECKING WIN CONDITION ---")

	var p1_count := 0
	var p2_count := 0
	for n in piece_container.get_children():
		if n is RigidBody2D and not n.get_meta("dying", false):
			var owner_id := int(n.get_meta("player", -1))
			if owner_id == 1: p1_count += 1
			elif owner_id == 2: p2_count += 1
	
	var my_count := p1_count if player == 1 else p2_count
	var op_count := p2_count if player == 1 else p1_count
	
	var game_is_over := (p1_count == 0 or p2_count == 0)
	if not game_is_over:
		print("-> RESULT: Game Continues. P1=%d, P2=%d" % [p1_count, p2_count])
		return false

	if game_over: # Already handled
		print("-> Game was already marked as over. No new result displayed.")
		return true

	game_over = true
	print("-> WIN CONDITION MET: My:%d, Opp:%d (P1=%d, P2=%d)" % [my_count, op_count, p1_count, p2_count])
	
	if my_count > 0 and op_count == 0:
		print("-> FINAL TALLY: YOU WIN!")
		_show_win_burst(player_avatar_display)
		win_loss_state = "1"
		var text = "Player 1 Wins!" if spectator_mode and p1_count > 0 else "YOU WIN!"
		_animate_win_loss_label(text, Color(1, 0.84, 0))
	elif op_count > 0 and my_count == 0:
		print("-> FINAL TALLY: YOU LOSE")
		_show_win_burst(opp_avatar_display)
		win_loss_state = "-1"
		var text = "Player 2 Wins!" if spectator_mode and p2_count > 0 else "YOU LOSE"
		var color = Color(1, 0.84, 0) if spectator_mode else Color(1, 0.2, 0.2)
		_animate_win_loss_label(text, color)
	else: # Both 0
		print("-> No pieces remain. Declaring draw.")
		win_loss_state = "0"
		_animate_win_loss_label("DRAW!", Color.WHITE)

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

func _show_goal_popup() -> void:
	if _goal_popup_shown:
		return
	_goal_popup_shown = true

	var viewport_size := get_viewport_rect().size
	var popup_width: float = viewport_size.x * 0.8
	var popup_height: float = 320.0

	# Dim overlay
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 99

	# Card
	var popup := PanelContainer.new()
	popup.custom_minimum_size = Vector2(popup_width, popup_height)
	popup.z_index = 100

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color.WHITE
	card_style.corner_radius_top_left = 16
	card_style.corner_radius_top_right = 16
	card_style.corner_radius_bottom_left = 16
	card_style.corner_radius_bottom_right = 16
	card_style.shadow_size = 8
	card_style.shadow_color = Color(0, 0, 0, 0.3)
	popup.add_theme_stylebox_override("panel", card_style)

	# Vertical layout inside the card
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(vbox)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 16)
	margin.add_child(inner)

	var title := Label.new()
	title.text = "Goal:"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.BLACK)
	title.add_theme_font_size_override("font_size", 36)
	var bold_font := ThemeDB.fallback_font.duplicate() as FontVariation
	if bold_font == null:
		bold_font = FontVariation.new()
		bold_font.base_font = ThemeDB.fallback_font
	bold_font.variation_embolden = 1.0
	title.add_theme_font_override("font", bold_font)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(title)

	# Body — center
	var body_wrap := CenterContainer.new()
	body_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(body_wrap)

	var body := Label.new()
	body.text = "Push your opponent out into the water before they push you out."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", Color.BLACK)
	body.add_theme_font_size_override("font_size", 20)
	body.custom_minimum_size = Vector2(popup_width - 96, 0)
	body_wrap.add_child(body)

	# Start button — bottom center, map-specific styling
	var btn_wrap := CenterContainer.new()
	inner.add_child(btn_wrap)

	var start_btn := Button.new()
	start_btn.text = "Start"
	start_btn.custom_minimum_size = Vector2(160, 56)
	start_btn.focus_mode = Control.FOCUS_NONE
	start_btn.add_theme_font_size_override("font_size", 24)

	var btn_bg: Color
	var btn_text: Color
	match map_mode:
		2:
			btn_bg = SEND_RED
			btn_text = Color("#ffd938")
		3:
			btn_bg = SEND_GREEN
			btn_text = Color.WHITE
		_:
			btn_bg = SEND_BLUE
			btn_text = Color.WHITE

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = btn_bg
	btn_normal.corner_radius_top_left = 12
	btn_normal.corner_radius_top_right = 12
	btn_normal.corner_radius_bottom_left = 12
	btn_normal.corner_radius_bottom_right = 12
	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = btn_bg.lerp(Color.WHITE, 0.08)
	var btn_pressed := btn_normal.duplicate()
	btn_pressed.bg_color = btn_bg.darkened(0.12)
	start_btn.add_theme_stylebox_override("normal", btn_normal)
	start_btn.add_theme_stylebox_override("hover", btn_hover)
	start_btn.add_theme_stylebox_override("pressed", btn_pressed)
	start_btn.add_theme_color_override("font_color", btn_text)
	start_btn.add_theme_color_override("font_hover_color", btn_text)
	start_btn.add_theme_color_override("font_pressed_color", btn_text)

	btn_wrap.add_child(start_btn)

	# Add to this scene (not viewport root) so we don't disturb top-level transforms.
	add_child(dim)
	add_child(popup)

	popup.set_as_top_level(true)
	dim.set_as_top_level(true)
	dim.z_index = 200
	popup.z_index = 201
	popup.size = Vector2(popup_width, popup_height)
	popup.position = (viewport_size / 2) - (popup.size / 2)
	popup.set_pivot_offset(popup.size / 2)
	popup.scale = Vector2.ZERO

	var popup_tween := create_tween()
	popup_tween.tween_property(popup, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	start_btn.pressed.connect(func():
		dim.queue_free()
		popup.queue_free()
	)

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
	
func _clear_mushrooms() -> void:
	if is_instance_valid(_mushroom_layer):
		_mushroom_layer.queue_free()
		_mushroom_layer = null

func _spawn_mushrooms_for_map3() -> void:
	_clear_mushrooms()
	if not is_instance_valid(piece_container):
		return

	_mushroom_layer = Node2D.new()
	_mushroom_layer.name = "MushroomLayer"
	piece_container.add_child(_mushroom_layer)

	var half := LOGICAL_BOARD_SIZE * 0.5
	var inset := 75.0

	var positions := [
		Vector2(-half.x + inset, -half.y + inset),
		Vector2( half.x - inset, -half.y + inset),
		Vector2(-half.x + inset,  half.y - inset),
		Vector2( half.x - inset,  half.y - inset)
	]

	for pos in positions:
		var m := MUSHROOM_SCENE.instantiate()
		m.position = pos
		_mushroom_layer.add_child(m)

		# purely visual: align draw depth with pieces
		var spr := m.get_node_or_null("Sprite2D") as Sprite2D
		if spr:
			spr.z_index = 0

		# give each mushroom access to the pieces for a guaranteed overlap check
		if m.has_method("set_piece_container"):
			m.set_piece_container(piece_container)

const DEBUG_SHRINK := false
func _control_global_aabb(c: Control) -> Rect2:
	var xf := c.get_global_transform()
	var pts := [
		xf * Vector2.ZERO,
		xf * Vector2(c.size.x, 0.0),
		xf * c.size,
		xf * Vector2(0.0, c.size.y)
	]

	var min_p: Vector2 = pts[0]
	var max_p: Vector2 = pts[0]
	for p in pts:
		min_p.x = minf(min_p.x, p.x)
		min_p.y = minf(min_p.y, p.y)
		max_p.x = maxf(max_p.x, p.x)
		max_p.y = maxf(max_p.y, p.y)

	return Rect2(min_p, max_p - min_p)


func _dbg_control_state(where: String, label: String, c: Control) -> void:
	if not DEBUG_SHRINK:
		return
	if not is_instance_valid(c):
		print("[SHRINK] ", where, " | ", label, " = null")
		return

	var r := _control_global_aabb(c)
	print("[SHRINK] ", where, " | ", label,
		" | pos=", c.position,
		" | size=", c.size,
		" | scale=", c.scale,
		" | pivot=", c.pivot_offset,
		" | global_pos=", c.global_position,
		" | global_rect_pos=", r.position,
		" | global_rect_size=", r.size
	)


func _dbg_piece_container_state(where: String) -> void:
	if not DEBUG_SHRINK:
		return
	if not is_instance_valid(piece_container):
		print("[SHRINK] ", where, " | PieceContainer = null")
		return

	if piece_container is Node2D:
		var pc := piece_container as Node2D
		print("[SHRINK] ", where, " | PieceContainer",
			" | pos=", pc.position,
			" | scale=", pc.scale,
			" | global_pos=", pc.global_position,
			" | global_scale=", pc.global_transform.get_scale()
		)

	var printed := 0
	for n in piece_container.get_children():
		if not (n is RigidBody2D):
			continue
		var rb := n as RigidBody2D
		print("[SHRINK] ", where, " | piece#", printed,
			" | local_pos=", rb.position,
			" | global_pos=", rb.global_position,
			" | scale=", rb.scale,
			" | global_scale=", rb.global_transform.get_scale(),
			" | rot=", rb.rotation
		)
		printed += 1
		if printed >= 4:
			break


func _dbg_board_state(where: String) -> void:
	if not DEBUG_SHRINK:
		return

	var texrect := _get_texrect()
	var board_scale := _board_scale_for_index(_current_board_index)
	var target_scale := _target_scale_for_index(_current_board_index)
	var expected_visual := LOGICAL_BOARD_SIZE * _board_base_scale_factor * current_scale * target_scale

	print("")
	print("[SHRINK] ==================== ", where, " ====================")
	print("[SHRINK] idx=", _current_board_index,
		" | logical=", LOGICAL_BOARD_SIZE,
		" | board_scale=", board_scale,
		" | base_factor=", _board_base_scale_factor,
		" | target_scale=", target_scale,
		" | expected_visual_px=", expected_visual,
		" | viewport=", get_viewport_rect().size
	)

	if is_instance_valid(board_zoom):
		_dbg_control_state(where, "BoardZoom", board_zoom)

	if is_instance_valid(_board_scale_node):
		_dbg_control_state(where, "BoardScaler", _board_scale_node)
	else:
		print("[SHRINK] ", where, " | BoardScaler = null")

	if is_instance_valid(texrect):
		_dbg_control_state(where, "TextureRect", texrect)
	else:
		print("[SHRINK] ", where, " | TextureRect = null")

	_dbg_piece_container_state(where)
	print("[SHRINK] ===========================================================")
	print("")
	
var _kill_debug_showing := false
var _kill_overlay_root: Node2D
var _safe_debug_poly: Polygon2D
var _safe_debug_outline: Line2D
var _hole_debug_outlines: Array[Line2D] = []
var _center_debug_nodes: Array[Polygon2D] = []

func _ensure_kill_overlay() -> void:
	if not is_instance_valid(board_zoom):
		return
	if not is_instance_valid(_kill_overlay_root):
		_kill_overlay_root = Node2D.new()
		_kill_overlay_root.name = "KillDebugOverlay"
		_kill_overlay_root.z_index = 500     # <= always above everything
		board_zoom.add_child(_kill_overlay_root)

	if not is_instance_valid(_safe_debug_poly):
		_safe_debug_poly = Polygon2D.new()
		_safe_debug_poly.color = Color(0, 1, 0, 0.15)
		_safe_debug_poly.visible = _kill_debug_showing
		_safe_debug_poly.z_index = 501
		_kill_overlay_root.add_child(_safe_debug_poly)

	if not is_instance_valid(_safe_debug_outline):
		_safe_debug_outline = Line2D.new()
		_safe_debug_outline.width = 2.0
		_safe_debug_outline.default_color = Color(0, 1, 0, 0.8)
		_safe_debug_outline.closed = true
		_safe_debug_outline.visible = _kill_debug_showing
		_safe_debug_outline.z_index = 502
		_kill_overlay_root.add_child(_safe_debug_outline)

func _set_kill_debug_visible(should_show: bool) -> void:
	_kill_debug_showing = should_show
	if is_instance_valid(_safe_debug_poly): _safe_debug_poly.visible = should_show
	if is_instance_valid(_safe_debug_outline): _safe_debug_outline.visible = should_show
	for p in _hole_debug_nodes:
		if is_instance_valid(p): p.visible = should_show
	for l in _hole_debug_outlines:
		if is_instance_valid(l): l.visible = should_show
	for d in _center_debug_nodes:
		if is_instance_valid(d): d.visible = should_show

func _update_hole_outlines(hole_locals: Array[PackedVector2Array]) -> void:
	# grow outlines to match holes
	while _hole_debug_outlines.size() < hole_locals.size():
		var ln := Line2D.new()
		ln.width = 2.0
		ln.default_color = Color(1, 0, 0, 0.9)
		ln.closed = true
		ln.z_index = 1001
		_kill_overlay_root.add_child(ln)
		_hole_debug_outlines.append(ln)
	# update
	for i in hole_locals.size():
		var pts := hole_locals[i]
		_hole_debug_outlines[i].points = pts
		_hole_debug_outlines[i].visible = _kill_debug_showing
	# hide extras
	for j in range(hole_locals.size(), _hole_debug_outlines.size()):
		if is_instance_valid(_hole_debug_outlines[j]):
			_hole_debug_outlines[j].visible = false

func _regular_ngon(center: Vector2, r: float, sides: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts

func _update_piece_center_debug_dots() -> void:
	if not _kill_debug_showing or _last_safe_poly.is_empty() or not is_instance_valid(board_zoom):
		return
	_ensure_kill_overlay()
	var to_bz := board_zoom.get_global_transform().affine_inverse()

	var idx := 0
	for n in piece_container.get_children():
		if not (n is RigidBody2D): continue
		if n.get_meta("dying", false): continue
		var p_bz := to_bz * (n as Node2D).global_position

		var in_safe := Geometry2D.is_point_in_polygon(p_bz, _last_safe_poly)
		var in_hole := false
		for hp in _last_hole_polys_cached:
			if not hp.is_empty() and Geometry2D.is_point_in_polygon(p_bz, hp):
				in_hole = true
				break

		# ensure dot node
		if idx >= _center_debug_nodes.size():
			var dot := Polygon2D.new()
			dot.z_index = 1002
			_kill_overlay_root.add_child(dot)
			_center_debug_nodes.append(dot)

		var dot_node := _center_debug_nodes[idx]
		dot_node.visible = true
		dot_node.polygon = _regular_ngon(p_bz, 4.0, 12)
		dot_node.color = Color(0, 1, 0, 0.9) if (in_safe and not in_hole) \
			else (Color(1, 0.9, 0, 0.95) if in_hole else Color(1, 0, 0, 0.95))
		idx += 1

	# hide leftovers
	for j in range(idx, _center_debug_nodes.size()):
		if is_instance_valid(_center_debug_nodes[j]):
			_center_debug_nodes[j].visible = false

func _ensure_debug_preview_hosted_in_board_zoom() -> void:
	if is_instance_valid(safe_zone_polygon):
		if safe_zone_polygon.get_parent() != board_zoom:
			safe_zone_polygon.reparent(board_zoom)
		if safe_zone_polygon is CanvasItem:
			var ci := safe_zone_polygon as CanvasItem
			ci.z_index = 999
			ci.visible = DEBUG_DRAW_ZONES
		# zero out local transforms so BoardZoom-local points line up
		if safe_zone_polygon is Node2D:
			var n2 := safe_zone_polygon as Node2D
			n2.position = Vector2.ZERO
			n2.rotation = 0.0
			n2.scale = Vector2.ONE
