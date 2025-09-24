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
@onready var _texrect: TextureRect = null
var _board_scale_node: Control = null   # our new, safe scaler parent for the board image

# Debug/watch state
var _inside_our_scale_write := 0
var _watch_prev_tr_scale := Vector2(-999, -999)
var _watch_prev_sc_scale := Vector2(-999, -999)
const LOGICAL_BOARD_SIZE := Vector2(360.0, 360.0)
const ZOOM_AIM   := 1  # how large to look when aiming (tweak)
const ZOOM_PLAY  := 1
const ZOOM_DUR   := 0.22 # seconds
const PIECE_HEADING_OFFSET: float = -PI * 0.5

# --- Board size & piece inset by board index ---
const BOARD0_SIZE_PX := 180.0         # board:0 => 180x180
const BOARD_DELTA_PER_LEVEL := 20.0    # each +1 index shrinks ~20px
const BOARD_MAX_INDEX := 7             # board:7 => 40x40
const PIECE_INSET_PER_LEVEL := 5.0     # each +1 index pulls pieces 5px toward center (x and y)

var _target_physical_size: float = 350.0
var _board_base_scale_factor: float = 1.0
var _kill_detection_enabled := true

const DEBUG_DRAW_ZONES := true

var _current_board_index: int = 0
var _safe_area: Area2D
var _safe_poly: CollisionPolygon2D
var _hole_areas: Array[Area2D] = []
var _hole_polys: Array[CollisionPolygon2D] = []

const ARROW_COLOR_MAP1 := Color(0,0,0,1)
const ARROW_COLOR_MAP2 := Color(0.95, 0.95, 0.95, 1.0)
const ARROW_COLOR_MAP3 := Color(0.92, 0.92, 0.92, 1.0)
const SEND_RED := Color("#d62828")
const SEND_GREEN := Color("#14532d")

const SHRINK_STEP := ZOOM_AIM - ZOOM_PLAY
var current_scale: float = ZOOM_AIM
const DEBUG_KILL := true


# --- Replay state ---
var last_pre_round: Dictionary = {}      # {"round": int, "pieces": Array[Dictionary]}
var last_post_round: Dictionary = {}     # same shape; board #2 (or #3) snapshot after physics
var current_round_index: int = 0

# --- Physics (ONE source of truth) ---
const PPM                 := 32.0          # pixels-per-meter (only used for mass estimate)
const PIECE_RADIUS_PX     := 24.0          # collision radius used everywhere
const FRICTION            := 0.02          # PhysicsMaterial.friction
const RESTITUTION         := 0.30          # PhysicsMaterial.bounce
const LINEAR_DAMP         := 0.25
const ANGULAR_DAMP        := 0.45
const DENSITY             := 1.0           # for mass approximation (optional)
const POWER_TO_IMPULSE    := 1.29          # unified “pixels of arrow” -> impulse scale
const GRAVITY_SCALE       := 0.0
const CCD_MODE            := RigidBody2D.CCD_MODE_CAST_RAY
const LOCK_ROTATION       := false

var PIECE_RADIUS := PIECE_RADIUS_PX
const ROUND_SNAP_AFTER: float = 1.4      # seconds: snap to post board after physics play
var _staged_launch_mode: bool = false       # true after we auto-play locally
var _staged_pre_board_str: String = ""      # serialized first board captured before auto-play
var _staged_next_index: int = 0             # next board index after auto-play
#const DEV_REPLAY_STRING := "board:2#77.861351,66.122459,1,-0.876164,-2.354301,104.423691#23.355244,93.006905,2,1.830075,-1.580594,61.118755#-4.830564,36.334606,2,2.219335,0.272333,38.293098#-18.615202,-35.732677,2,2.316064,0.583284,79.135498#99.505798,94.505386,2,2.833030,-1.843283,72.001610|shoot:1|board:3#68.967499,51.041775,1,-0.956223,-2.354301,0.000000#50.799763,68.490479,2,0.031407,-1.832990,21.633646#-33.968060,-1.493485,2,1.201969,0.854556,49.784225#22.491690,-81.952728,2,2.664457,1.825102,79.211861#64.293983,-6.814495,2,-0.272487,1.906639,43.372223|board:3#68.967499,51.041775,1,-0.956223,-2.354301,0.000000#50.799763,68.490479,2,0.031407,-1.832990,21.633646#-33.968060,-1.493485,2,1.201969,0.854556,49.784225#22.491690,-81.952728,2,2.664457,1.825102,79.211861#64.293983,-6.814495,2,-0.272487,1.906639,43.372223"

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
var _resize_pending := false

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
	_target_physical_size = get_viewport_rect().size.x - 20.0
	_recalc_board_base_scale_factor()
	_apply_board_index_immediate(_current_board_index)
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

func _apply_arrow_color_for_current_map() -> void:
	var c := ARROW_COLOR_MAP1
	if map_mode == 2: c = ARROW_COLOR_MAP2
	elif map_mode == 3: c = ARROW_COLOR_MAP3
	for piece in piece_container.get_children():
		var arrow := piece.get_node_or_null("Arrow") as CanvasItem
		if arrow: arrow.modulate = c

func _apply_send_button_color_for_current_map() -> void:
	if not is_instance_valid(send_button): return
	if map_mode == 2:
		_style_button(send_button, SEND_RED)
	elif map_mode == 3:
		_style_button(send_button, SEND_GREEN)

# Rebuild base polygons from the image ONCE (or when the texture/map changes).
func _rebuild_base_polys_from_png(alpha_threshold: float = 0.1, simplify_epsilon: float = 1.5) -> void:
	_base_iceberg_poly.clear()
	_base_hole_polys.clear()

	var texrect := game_board.get_node_or_null("TextureRect") as TextureRect
	if not is_instance_valid(texrect) or not is_instance_valid(texrect.texture): return

	var img: Image = texrect.texture.get_image()
	if img.is_empty(): return

	var bm := BitMap.new()
	bm.create_from_image_alpha(img, alpha_threshold)

	var rect_img := Rect2i(Vector2i.ZERO, img.get_size())
	var contours: Array[PackedVector2Array] = bm.opaque_to_polygons(rect_img, simplify_epsilon)
	if contours.is_empty(): return

	# pick largest as outer
	var best := contours[0]
	var best_area := _poly_area(best)
	for poly in contours:
		var a := _poly_area(poly)
		if a > best_area:
			best = poly
			best_area = a
	_base_iceberg_poly = best

	# holes are transparent islands *inside* the iceberg (map 2)
	if map_mode == 2:
		_base_hole_polys = _extract_holes_from_transparency(img, best, alpha_threshold, simplify_epsilon)

	var bounding_rect: Rect2 = _get_poly_bounds(best)
	print("BASE POLYGON BUILT (Image Coords): %s ; holes=%d" % [bounding_rect, _base_hole_polys.size()])

# Recompute transformed (BoardZoom-local & global) polygons when transforms/layout change.
func _refresh_safe_polys_for_transform() -> void:
	# Build/refresh BoardZoom-local polygons and wire them to Areas (no per-frame tests).
	if _base_iceberg_poly.is_empty():
		if is_instance_valid(safe_zone_polygon):
			safe_zone_polygon.polygon = PackedVector2Array()
		# Tear down old areas if any
		_destroy_safe_hole_areas()
		return

	var texrect := game_board.get_node_or_null("TextureRect") as TextureRect
	if not is_instance_valid(board_zoom) or not is_instance_valid(texrect) or not texrect.texture:
		return

	# Map: Image space -> TextureRect draw space -> BoardZoom local
	var xf: Transform2D = board_zoom.get_global_transform().affine_inverse() * texrect.get_global_transform()
	var tex_draw_rect: Rect2 = _texrect_draw_rect(texrect, null)
	var img_size := Vector2(texrect.texture.get_size())
	var tex_scale := tex_draw_rect.size / img_size if img_size.x > 0.0 and img_size.y > 0.0 else Vector2.ONE
	
	# The inverse scale and pivot are the keys to fixing the "double scaling" problem correctly.
	var inv_zoom_scale := Vector2.ONE
	if board_zoom.scale.x != 0.0 and board_zoom.scale.y != 0.0:
		inv_zoom_scale = Vector2.ONE / board_zoom.scale
	var pivot := board_zoom.pivot_offset

	# Outer polygon in BoardZoom local (unscaled and correctly positioned)
	var local_poly := PackedVector2Array()
	for v_img in _base_iceberg_poly:
		var p_tex := tex_draw_rect.position + (v_img * tex_scale)
		var scaled_pt := xf * p_tex
		# Scale the point around the pivot to correct its position
		local_poly.append(pivot + ((scaled_pt - pivot) * inv_zoom_scale))

	# Optional outward offset (amount must also be in the unscaled space)
	var offset_amount = 1.0 * inv_zoom_scale.x
	var final_poly := local_poly
	var expanded := Geometry2D.offset_polygon(local_poly, offset_amount)
	if expanded is Array and expanded.size() > 0:
		final_poly = expanded[0]

	# (Map 2) hole polygons in BoardZoom local (unscaled and correctly positioned)
	var hole_locals: Array[PackedVector2Array] = []
	if map_mode == 2 and not _base_hole_polys.is_empty():
		for hole_img in _base_hole_polys:
			var hl := PackedVector2Array()
			for v_img in hole_img:
				var p_tex := tex_draw_rect.position + (v_img * tex_scale)
				var scaled_pt := xf * p_tex
				# Scale the point around the pivot here as well
				hl.append(pivot + ((scaled_pt - pivot) * inv_zoom_scale))
			
			var shrink_amount = -1.0 * inv_zoom_scale.x
			var shrunk := Geometry2D.offset_polygon(hl, shrink_amount)
			hole_locals.append(shrunk[0] if (shrunk is Array and shrunk.size() > 0) else hl)

	_last_safe_poly = final_poly
	_last_hole_polys_cached = hole_locals.duplicate()

	# Existing preview node
	if is_instance_valid(safe_zone_polygon):
		safe_zone_polygon.polygon = final_poly
		safe_zone_polygon.visible = DEBUG_DRAW_ZONES
		if safe_zone_polygon is Polygon2D:
			safe_zone_polygon.color = Color(0, 1, 0, 0.10)

	# Build/update Areas
	_build_safe_area(final_poly)
	_build_hole_areas(hole_locals)

	# Update debug overlay shapes
	if _kill_debug_showing:
		_ensure_kill_overlay()
		_safe_debug_poly.polygon = final_poly
		_safe_debug_outline.points = final_poly
		_set_hole_debug_polys(hole_locals)
		_update_hole_outlines(hole_locals)
	
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
	if body is RigidBody2D and body.get_parent() == piece_container:
		if DEBUG_KILL: print("[KILL] SafeArea.body_exited →", body.name)
		_safe_kill(body)

func _on_hole_body_entered(body: Node) -> void:
	if body is RigidBody2D and body.get_parent() == piece_container:
		if DEBUG_KILL: print("[KILL] HoleArea.body_entered →", body.name)
		_safe_kill(body)

func _on_water_kill_body_entered(body: Node) -> void:
	if body is RigidBody2D and body.get_parent() == piece_container:
		if DEBUG_KILL: print("[KILL] Water.body_entered →", body.name)
		_safe_kill(body)
	
func _target_scale_for_index(i: int) -> float:
	return _board_base_scale_factor * _board_scale_for_index(i)
	
func _recalc_board_base_scale_factor() -> void:
	# This function now calculates the scale needed to make our 360-unit logical board
	# fit the dynamically calculated _target_physical_size.
	_board_base_scale_factor = 1.0 if LOGICAL_BOARD_SIZE.x <= 0.0 else _target_physical_size / LOGICAL_BOARD_SIZE.x
	if DEBUG_SHRINK:
		print("[SHRINK] _recalc_board_base_scale_factor | target_px=", _target_physical_size, " | base_factor=", _board_base_scale_factor)

func _physics_process(delta: float) -> void:
	_kill_check_accum += delta
	if _kill_check_accum >= KILL_CHECK_INTERVAL:
		_kill_check_accum = 0.0
		_update_piece_center_debug_dots()  # <- always refresh when visible
		if _replay_in_progress or _is_zooming or not _kill_detection_enabled:
			return
		_fallback_kill_pass()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K:
			_set_kill_debug_visible(not _kill_debug_showing)

func _fallback_kill_pass() -> void:
	if _last_safe_poly.is_empty() or not is_instance_valid(board_zoom):
		return
	var to_bz := board_zoom.get_global_transform().affine_inverse()

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

		if (not in_safe) or in_hole:
			if DEBUG_KILL:
				print("[KILL] fallback → ", n.name, " in_safe=", in_safe, " in_hole=", in_hole, " pos=", p_bz)
			_safe_kill(n)

					
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
		p.z_index = 100
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
			
func _get_texrect() -> TextureRect:
	if _texrect and is_instance_valid(_texrect):
		return _texrect
	_texrect = game_board.get_node_or_null("TextureRect") as TextureRect
	return _texrect

func _ensure_board_scaler() -> void:
	if is_instance_valid(_board_scale_node):
		return
	var tex := _get_texrect()
	if not is_instance_valid(tex):
		return

	# Create a wrapper that we — and only we — will scale.
	var wrapper := Control.new()
	wrapper.name = "BoardScaler"
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	wrapper.custom_minimum_size   = LOGICAL_BOARD_SIZE
	wrapper.pivot_offset          = LOGICAL_BOARD_SIZE * 0.5
	game_board.add_child(wrapper)
	game_board.move_child(wrapper, tex.get_index())

	tex.reparent(wrapper)
	tex.position = Vector2.ZERO
	# keep the TextureRect itself at identity so outside code changing it is harmless
	tex.scale = Vector2.ONE

	_board_scale_node = wrapper
	print("[SHRINK] BoardScaler injected. We'll scale this wrapper instead of TextureRect.")

func _ready():
	# Wait a single frame for the viewport size to be accurate before we do any calculations.
	await get_tree().process_frame
	# 1. Dynamically set the board's target size based on the screen width.
	_target_physical_size = get_viewport_rect().size.x - 20.0 # 10px padding on each side

	# 2. Standard scene and UI setup.
	var is_dark := bool(SettingsManager.get_setting("global", "dark_mode", false))
	_apply_map_theme(map_mode)
	_apply_bg_for_dark(is_dark)
	background.z_index = -10
	self.z_index = 10
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
	var texrect := game_board.get_node_or_null("TextureRect") as TextureRect
	if is_instance_valid(texrect):
		texrect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		texrect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		texrect.custom_minimum_size = LOGICAL_BOARD_SIZE

	if is_instance_valid(board_zoom):
		board_zoom.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		board_zoom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		board_zoom.custom_minimum_size = LOGICAL_BOARD_SIZE
		board_zoom.clip_contents = false
		# BoardZoom's scale is now ONLY for gameplay zoom.
		board_zoom.scale = Vector2.ONE * ZOOM_AIM
		current_scale = ZOOM_AIM
		board_zoom.pivot_offset = board_zoom.custom_minimum_size * 0.5
		board_zoom.resized.connect(func():
			board_zoom.pivot_offset = board_zoom.size * 0.5
		)
	
	piece_container.position = board_zoom.custom_minimum_size * 0.5
	
	_texrect = game_board.get_node_or_null("TextureRect") as TextureRect
	_ensure_board_scaler()

	
	# 4. Calculate the base scale factor and apply the initial board state.
	_recalc_board_base_scale_factor()
	_rebuild_base_polys_from_png()
	_apply_board_index_immediate(0) # Sets initial TextureRect scale and generates polygons.

	# 5. Connect signals to handle screen resizing events.
	get_viewport().size_changed.connect(_on_viewport_resize)

	# 6. Final game initialization steps.
	_board_initialized = true
	print("Board initialized and scaled.")

	if _pending_replay_str != "":
		parse_replay_string(_pending_replay_str)
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
			"myPlayerId": "player1_id",
			"player1": "player1_id",
			"mode": "1",
			"replay": "board:0#-123.164268,12.253189,1,187.688141,-1.385261,17.847954#-4.496841,98.564392,1,150.148392,-1.958740,30.476469#-128.793274,126.112091,1,132.961517,-1.525080,19.882833#-39.626404,-31.231033,1,352.372589,-1.908161,19.720287#-128.491425,90.655441,2,224.981232,270.000000,150.000000#37.309402,-82.729164,2,130.874207,180.000000,60.000000#52.552505,-38.661270,2,188.420181,90.000000,20.000000#47.671448,20.402176,2,292.878235,0.000000,150.000000|shoot:1|board:1#-107.245102,-11.783591,1,0.185535,1.068582,62.991386#95.616051,78.460869,1,0.211298,-2.598553,52.906605#-115.448547,88.224197,1,0.045716,-0.761526,42.157124#-44.425999,-52.628483,1,-0.337365,1.551364,59.530804#-34.058250,20.246990,2,272.170044,270.000000,0.000000#-13.993504,-138.885513,2,181.570801,180.000000,0.000000#35.868378,-11.620506,2,91.570793,90.000000,0.000000|board:1#-107.245102,-11.783591,1,0.185535,1.068582,62.991386#95.616051,78.460869,1,0.211298,-2.598553,52.906605#-115.448547,88.224197,1,0.045716,-0.761526,42.157124#-44.425999,-52.628483,1,-0.337365,1.551364,59.530804#-34.058250,20.246990,2,272.170044,270.000000,0.000000#-13.993504,-138.885513,2,181.570801,180.000000,0.000000#35.868378,-11.620506,2,91.570793,90.000000,0.000000"
		}
		_set_game_data(JSON.stringify(dev_payload))

	call_deferred("_seed_area_overlaps")
	if piece_container.get_parent() != board_zoom:
		piece_container.reparent(board_zoom)
	piece_container.position = board_zoom.custom_minimum_size * 0.5

func _seed_area_overlaps() -> void:
	if not is_instance_valid(_safe_area): return
	# Touch the overlap list so the physics server evaluates it this frame
	_safe_area.get_overlapping_bodies()

func _apply_bg_for_dark(is_dark: bool) -> void:
	if is_instance_valid(background):
		background.color = Color(0.08, 0.08, 0.08) if is_dark else Color("#68d4f6")

# --- Game Data Handling ---

func _animate_and_fire_from_current_arrows() -> void:
	var pieces: Array[RigidBody2D] = []
	for c in piece_container.get_children():
		if c is RigidBody2D and c.has_meta("player"):
			pieces.append(c)

	# Make sure arrows are visible for the pre-play animation
	for p in pieces:
		var ang_deg: float = float(p.get_meta("shoot_dir", 0.0))
		var pow_px: float  = float(p.get_meta("power", 0.0))
		_set_piece_arrow_from_data(p, deg_to_rad(ang_deg), pow_px, 0.18)

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
		var pow_px: float  = float(p.get_meta("power", 0.0))
		_fire_piece_from_arrow(p, deg_to_rad(ang_deg), pow_px)

	await _wait_for_pieces_to_settle(10.0, 8, 1.8, 0.10)


# After physics settles, move pieces to the next-board inset, shrink board, and enable re-aiming
func _stage_after_local_play(next_idx: int) -> void:
	_dbg_board_state("staging pre-shrink")
	for c in piece_container.get_children():
		if c is RigidBody2D and c.has_meta("player"):
			var rb := c as RigidBody2D
			var new_pos := _inset_pos_for_board(rb.position, next_idx)
			rb.freeze = true
			rb.position = new_pos
			rb.linear_velocity = Vector2.ZERO
			rb.angular_velocity = 0.0
			rb.freeze = false

	_hide_all_arrows_and_refresh_highlights()

	print("[SHRINK] staging: next_idx=", next_idx, " | step=", SHRINK_STEP)
	current_scale = current_scale - SHRINK_STEP
	print("[SHRINK] staging: calling _apply_zoom with target=", current_scale)
	await _apply_zoom(current_scale, 0.18)
	_dbg_board_state("staging after _apply_zoom")

	print("[SHRINK] staging: calling _tween_board_index_to -> ", next_idx)
	await _tween_board_index_to(next_idx, 0.18)
	_dbg_board_state("staging after _tween_board_index_to")

	_staged_launch_mode = true
	_staged_next_index = next_idx
	_update_piece_interactivity()
	_recompute_send_button_visibility()

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
	map_mode = int(data.get("map", data.get("mode", map_mode)))
	_apply_map_theme(map_mode)

	if my_player_id == player1_id or my_player_id == player2_id or player1_id == "":
		is_my_turn = is_your_turn
		if my_player_id == player1_id:
			player = 1; opponent_avatar_key = "avatar2"
		elif my_player_id == player2_id:
			player = 2; opponent_avatar_key = "avatar1"
		else:
			player = 1
	else:
		#spectator_mode = true
		you_label.text = ""
		#is_my_turn = false
		is_my_turn = is_your_turn
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
		_recompute_send_button_visibility()

func send_game() -> void:
	print("[Send] send_game() called")
	_stop_all_highlights()
	await get_tree().process_frame

	# If we already auto-played locally, this click FINALIZES and sends.
	if _staged_launch_mode:
		var payload: Dictionary = {}
		var post_str := _serialize_current_board(_staged_next_index, false, true)
		var staged_replay_str := "%s|shoot:1|%s|%s" % [_staged_pre_board_str, post_str, post_str]
		payload["replay"] = staged_replay_str

		avatar_key = ("avatar1" if player == 1 else "avatar2")
		if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
			payload[avatar_key] = player_avatar_display.get_avatar_data_string()

		# (Optional) Check win now (in case local round ended the game)
		game_ended = await check_win()
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
	var my_ready := _all_my_arrows_visible()
	var opp_ready := _all_opponent_arrows_nonzero()

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

		# 3) Stage the "post" board at next index and let the player aim again.
		var next_idx: int = int(min(_current_board_index + 1, BOARD_MAX_INDEX))
		await _stage_after_local_play(next_idx)

		# Done: DO NOT send yet. The next click will send the 3-chunk payload.
		return

	# Fallback: opponent not ready
	var replay_string_to_send := _build_replay_string()
	var payload2: Dictionary = { "replay": replay_string_to_send }

	avatar_key = ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		payload2[avatar_key] = player_avatar_display.get_avatar_data_string()

	game_ended = await check_win()
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

	# 3) Full round ready: everyone has arrows -> pre | shoot:1 | post | post
	if my_ready and opp_ready:
		var pre := _serialize_current_board(idx, false, true)
		var next_idx: int = int(min(idx + 1, BOARD_MAX_INDEX))
		var post := _serialize_current_board(next_idx, true, true) # zero powers in post
		return "%s|shoot:1|%s|%s" % [pre, post, post]

	# 4) Default hand-off: I’ve set my arrows, opponent hasn’t → send a single pre board (no shoot)
	return _serialize_current_board(idx, false, true)

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

# --- Replay Parsing & Board Setup ---

func _update_piece_interactivity() -> void:
	for piece in piece_container.get_children():
		if piece.has_method("set_controlled_by_me"):
			var owner_id: int = int(piece.get_meta("player", -1))
			var can_control: bool = (
				owner_id == player
				and is_my_turn
				and not spectator_mode
				and not game_over
				and not _replay_in_progress            # <-- add
			)
			piece.set_controlled_by_me(can_control)
	_recompute_send_button_visibility()

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

	last_pre_round = boards[0]
	last_post_round = boards[1] if (boards.size() > 1) else {}

	var pre_idx := int(last_pre_round.get("round", 0))
	_apply_board_index_immediate(pre_idx)

	_setup_board_from_board_dict(last_pre_round)

	if shoot_flag:
		_replay_in_progress = true
		_update_piece_interactivity()
		_stop_all_highlights()
		await get_tree().process_frame
		_play_round_from_replay(last_pre_round)

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

func _all_my_arrows_visible() -> bool:
	var mine := _owned_live_pieces()
	if mine.is_empty():
		return false
	for p in mine:
		var arrow := p.get_node_or_null("Arrow") as CanvasItem
		if arrow == null or not arrow.visible:
			return false
	return true

func _animate_send_button(should_show: bool) -> void:
	if not is_instance_valid(send_button):
		return
	send_button.set_as_top_level(true)

	if not send_button.has_meta("home_pos"):
		send_button.set_meta("home_pos", send_button.global_position)

	if send_button.has_meta("sb_tween"):
		var old_tw: Variant = send_button.get_meta("sb_tween")
		if old_tw is Tween and (old_tw as Tween).is_running():
			(old_tw as Tween).kill()

	var home: Vector2 = send_button.get_meta("home_pos")
	var vp := get_viewport_rect()
	var off_y: float = vp.size.y + send_button.size.y + 30.0
	var start_pos := Vector2(home.x, off_y)
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
			var end_pos := Vector2(home.x, off_y)
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

func _recompute_send_button_visibility() -> void:
	var should_show := (
		is_my_turn
		and not spectator_mode
		and not game_over
		and not _replay_in_progress
		and _all_my_arrows_visible()
	)
	_animate_send_button(should_show)
	if is_instance_valid(send_button):
		send_button.text = "Send" if _staged_launch_mode else "Launch"
	
func _apply_zoom(target_zoom_level: float, dur: float = ZOOM_DUR) -> void:
	if not is_instance_valid(board_zoom) or game_over: return
	
	# The scale is simply the target zoom level. The screen-fit logic is handled by the TextureRect.
	var target_scale_vector := Vector2.ONE * target_zoom_level

	if DEBUG_SHRINK:
		print("[SHRINK] _apply_zoom start | current bz.scale=", board_zoom.scale, " -> target=", target_scale_vector, " dur=", dur)

	_is_zooming = true
	_set_kill_detection_enabled(false)
	var tw := create_tween()
	tw.tween_property(board_zoom, "scale", target_scale_vector, dur)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	_is_zooming = false
	
	# The 'current_scale' variable correctly tracks the zoom level.
	current_scale = target_zoom_level

	if DEBUG_SHRINK:
		print("[SHRINK] _apply_zoom done  | bz.scale=", board_zoom.scale)

	_refresh_safe_polys_for_transform()
	_seed_area_overlaps()
	_set_kill_detection_enabled(true)

func _apply_map_theme(mode: int) -> void:
	if is_instance_valid(background):
		match mode:
			2: background.color = Color("#ffd938")
			3: background.color = Color("#34f671")
			_: _apply_bg_for_dark(bool(SettingsManager.get_setting("global", "dark_mode", false)))

	var texrect := game_board.get_node_or_null("TextureRect") as TextureRect
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
	_setup_board_from_data(arr)

func _setup_board_from_data(board_data: Array[Dictionary]) -> void:
	if not _board_initialized:
		await get_tree().process_frame

	for child in piece_container.get_children():
		if child == _mushroom_layer:
			continue
		if child is RigidBody2D and child.has_meta("player"):
			child.queue_free()
	await get_tree().process_frame

	var use_idx := _current_board_index

	for piece_data in board_data:
		var piece_instance: RigidBody2D = PieceScene.instantiate()

		# Ownership / pose
		var player_num: int = int(piece_data.get("player", 1))
		piece_instance.set_meta("player", player_num)

		var raw_pos: Vector2 = piece_data.get("pos", Vector2.ZERO)
		piece_instance.position = _inset_pos_for_board(raw_pos, use_idx)
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
			var desired_px := Vector2(PIECE_RADIUS_PX * 2.0, PIECE_RADIUS_PX * 2.0)
			if tex_size.x > 0.0 and tex_size.y > 0.0:
				sprite.scale = desired_px / tex_size
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
				"POWER_TO_IMPULSE": POWER_TO_IMPULSE,
				"GRAVITY_SCALE": GRAVITY_SCALE,
				"CCD_MODE": CCD_MODE,
				"LOCK_ROTATION": LOCK_ROTATION
			})

		piece_container.add_child(piece_instance)

		var arrow := piece_instance.get_node_or_null("Arrow") as CanvasItem
		if arrow:
			match map_mode:
				2: arrow.modulate = ARROW_COLOR_MAP2
				3: arrow.modulate = ARROW_COLOR_MAP3
				_: arrow.modulate = ARROW_COLOR_MAP1
			# Keep arrows hidden unless we’re animating a replay
			arrow.visible = false

		if piece_instance.has_method("set_controlled_by_me"):
			var can_control := (player_num == player) and is_my_turn and (not spectator_mode) and (not game_over) and (not _replay_in_progress)
			piece_instance.set_controlled_by_me(can_control)

		if piece_instance.has_signal("aim_changed"):
			piece_instance.connect("aim_changed", Callable(self, "_on_piece_aim_changed"))

		call_deferred("_try_watch_arrow_for_piece", piece_instance)

func _on_piece_aim_changed(_angle_deg: float, _pow: float) -> void:
	_recompute_send_button_visibility()

func _set_piece_arrow_from_data(piece: Node, shoot_dir_rad: float, pow_px: float, fade_sec: float) -> void:
	var angle_deg: float = rad_to_deg(shoot_dir_rad)
	if piece.has_method("show_arrow_from_replay"):
		piece.call("show_arrow_from_replay", angle_deg, pow_px, fade_sec)
	else:
		piece.set_meta("shoot_dir", angle_deg)
		piece.set_meta("power", pow_px)
		var arrow := piece.get_node_or_null("Arrow") as CanvasItem
		if arrow:
			arrow.modulate.a = 1.0
			arrow.visible = true

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
	if piece.has_method("fire_from_meta"):
		piece.set_meta("shoot_dir", rad_to_deg(shoot_dir_rad))
		piece.set_meta("power", pow_px)
		piece.call("fire_from_meta")
	elif piece is RigidBody2D:
		var impulse := Vector2(cos(shoot_dir_rad), sin(shoot_dir_rad)) * (pow_px * POWER_TO_IMPULSE)
		(piece as RigidBody2D).apply_impulse(impulse)
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
	if n is RigidBody2D:
		call_deferred("_kill_piece", n)
		
func _on_replay_round_finished() -> void:
	_hide_all_arrows_and_refresh_highlights()

	_replay_in_progress = false
	_update_piece_interactivity()
	_recompute_send_button_visibility()

	# small delay to let physics/colliders settle
	await get_tree().create_timer(0.05).timeout

	# Determine next board index and snap pieces to the post snapshot if provided
	var next_idx := _current_board_index + 1
	if not last_post_round.is_empty():
		print("[SHRINK] applying post snapshot for idx=", int(last_post_round.get("round", _current_board_index + 1)))
		next_idx = int(last_post_round.get("round", _current_board_index + 1))
		_apply_post_round_snapshot(last_post_round, next_idx)

	# --- NEW: re-assert the correct baseline scale for the CURRENT index before any zoom ---
	# This prevents the "grow" effect when something (layout/other code) reset the scaler to (1,1).
	_apply_board_index_immediate(_current_board_index)
	await get_tree().process_frame  # ensure transforms are up-to-date for accurate debug
	_dbg_board_state("before zoom (post round)")

	# Plan and apply gameplay zoom (AIM -> PLAY)
	var target_zoom := current_scale - SHRINK_STEP
	print("[SHRINK] planning zoom: current_scale ", current_scale, " -> ", target_zoom, " (step=", SHRINK_STEP, ")")
	await _apply_zoom(target_zoom, 0.18)
	_dbg_board_state("after _apply_zoom")

	# Tween the actual board shrink (index change)
	print("[SHRINK] tweening board index: ", _current_board_index, " -> ", next_idx, " (dur=0.18)")
	await _tween_board_index_to(next_idx, 0.18)
	_dbg_board_state("after _tween_board_index_to")

func _piece_is_moving(rb: RigidBody2D, v_thresh := 1.8, w_thresh := 0.10) -> bool:
	if rb.has_meta("dying") and rb.get_meta("dying"):
		return false
	if rb.sleeping:
		return false
	return rb.linear_velocity.length() > v_thresh or absf(rb.angular_velocity) > w_thresh

func _wait_for_pieces_to_settle(timeout_sec: float = 10.0, still_frames_needed: int = 8, v_thresh: float = 1.8, w_thresh: float = 0.10) -> void:
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

func _apply_post_round_snapshot(post_board: Dictionary, board_idx: int = -1) -> void:
	var arr: Array = post_board.get("pieces", [])
	var use_idx := _clamp_board_index(board_idx) if (board_idx >= 0) else _current_board_index

	# Collect only piece bodies
	var children_pieces: Array[Node] = []
	for c in piece_container.get_children():
		if c is RigidBody2D and c.has_meta("player"):
			children_pieces.append(c)

	var count: int = min(children_pieces.size(), arr.size())
	for i in count:
		var piece_node := children_pieces[i]
		var pd: Dictionary = arr[i]
		var pos: Vector2 = _inset_pos_for_board(pd["pos"], use_idx)
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

func _play_round_from_replay(pre_board: Dictionary) -> void:
	print("[REPLAY] Starting round playback.")
	_replay_in_progress = true
	_set_kill_detection_enabled(false)
	_update_piece_interactivity()
	_stop_all_highlights()
	_recompute_send_button_visibility()
	var pre_arr: Array = pre_board.get("pieces", [])

	# Only gather actual piece bodies (have the "player" meta)
	var pieces: Array[RigidBody2D] = []
	for child in piece_container.get_children():
		if child is RigidBody2D and child.has_meta("player"):
			pieces.append(child)

	var count: int = min(pieces.size(), pre_arr.size())
	if count == 0:
		_on_replay_round_finished()
		return

	for i in count:
		var piece := pieces[i]
		if not is_instance_valid(piece): continue
		var pd: Dictionary = pre_arr[i]
		_set_piece_arrow_from_data(piece, float(pd["shoot_dir"]), float(pd["power"]), 0.18)

	await get_tree().create_timer(0.5).timeout

	var rotation_tween := create_tween().set_parallel()
	for i in count:
		var piece := pieces[i]
		if not is_instance_valid(piece): continue
		var pd: Dictionary = pre_arr[i]
		_rotate_piece_to_dir(rotation_tween, piece, float(pd["shoot_dir"]), 0.5)

	if rotation_tween.is_running():
		await rotation_tween.finished

	await get_tree().create_timer(0.5).timeout
	for i in count:
		var piece := pieces[i]
		if not is_instance_valid(piece): continue
		var pd: Dictionary = pre_arr[i]
		_fire_piece_from_arrow(piece, float(pd["shoot_dir"]), float(pd["power"]))

	await _wait_for_pieces_to_settle(10.0, 8, 1.8, 0.10)
	_on_replay_round_finished()
	
func _clamp_board_index(i: int) -> int:
	return clamp(i, 0, BOARD_MAX_INDEX)

func _board_size_for_index(i: int) -> float:
	var idx := _clamp_board_index(i)
	return BOARD0_SIZE_PX - BOARD_DELTA_PER_LEVEL * float(idx)

func _board_scale_for_index(i: int) -> float:
	return _board_size_for_index(i) / BOARD0_SIZE_PX

func _apply_board_index_immediate(i: int) -> void:
	_current_board_index = _clamp_board_index(i)
	var texrect := _get_texrect()
	_ensure_board_scaler()

	if is_instance_valid(_board_scale_node):
		_board_scale_node.pivot_offset = LOGICAL_BOARD_SIZE * 0.5
		var target := _target_scale_for_index(_current_board_index)
		_inside_our_scale_write += 1
		_board_scale_node.scale = Vector2.ONE * target
		_inside_our_scale_write -= 1

	# keep the TextureRect itself at (1,1) so outside writes won’t affect the visual size
	if is_instance_valid(texrect) and texrect.scale != Vector2.ONE:
		texrect.scale = Vector2.ONE

	if DEBUG_SHRINK:
		print("[SHRINK] _apply_board_index_immediate | idx=", _current_board_index,
			" | scaler.scale=", ( _board_scale_node.scale if is_instance_valid(_board_scale_node) else Vector2.ONE ),
			" | texrect.scale=", ( texrect.scale if is_instance_valid(texrect) else Vector2.ONE ))

	_refresh_safe_polys_for_transform()

func _tween_board_index_to(i: int, dur: float = 0.18) -> void:
	var target_idx := _clamp_board_index(i)
	if target_idx == _current_board_index:
		return

	var texrect := _get_texrect()
	_ensure_board_scaler()
	var scaler := _board_scale_node
	if is_instance_valid(scaler):
		_is_zooming = true
		_set_kill_detection_enabled(false)

		var s0 := _target_scale_for_index(_current_board_index)
		var s1 := _target_scale_for_index(target_idx)
		if DEBUG_SHRINK:
			print("[SHRINK] tweening board index: ", _current_board_index, " -> ", target_idx,
				" | scaler.start=", scaler.scale, " | s0=", s0, " | s1=", s1)

		var tw := create_tween()
		tw.tween_method(
			func(t: float) -> void:
				_inside_our_scale_write += 1
				scaler.scale = Vector2.ONE * lerp(s0, s1, t)
				_inside_our_scale_write -= 1
				_refresh_safe_polys_for_transform(),
			0.0, 1.0, dur
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await tw.finished
		_is_zooming = false

	_current_board_index = target_idx
	_refresh_safe_polys_for_transform()
	_seed_area_overlaps()
	_set_kill_detection_enabled(true)
	_fallback_kill_pass()
	_dbg_board_state("after index commit")

func _inset_pos_for_board(pos: Vector2, board_idx: int) -> Vector2:
	# Move each piece toward (0,0) by 5px * board_idx on both axes.
	var inset: float = PIECE_INSET_PER_LEVEL * float(_clamp_board_index(board_idx))
	var x: float = move_toward(pos.x, 0.0, inset)
	var y: float = move_toward(pos.y, 0.0, inset)
	return Vector2(x, y)

# --- Piece Highlighting ---
func _apply_turn_highlights_based_on_arrows() -> void:
	if not is_my_turn or spectator_mode or game_over or _replay_in_progress:
		_stop_all_highlights()
		return

	for piece in piece_container.get_children():
		var owner_id: int = int(piece.get_meta("player", -1))
		var ring := piece.get_node_or_null("HighlightRing") as TextureRect
		var anim := piece.get_node_or_null("HighlightAnimator") as AnimationPlayer
		if owner_id != player:
			if anim: anim.stop()
			if ring: ring.visible = false
			continue
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
	if _replay_in_progress:
		return
	if arrow.visible:
		_stop_highlight_for_piece(piece)
	else:
		if is_my_turn and not spectator_mode and not game_over and int(piece.get_meta("player", -1)) == player:
			var ring := piece.get_node_or_null("HighlightRing") as TextureRect
			var anim := piece.get_node_or_null("HighlightAnimator") as AnimationPlayer
			if ring and anim:
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
	var tween := create_tween()
	tween.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

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

#DEV CODE

# --- Dev replay override (for visual verification) ---
const DEV_USE_HARDCODED_REPLAY := false  # set true to force one of the dev strings below
const DEV_REPLAY_MODE := "line"      # "corners" | "down" | "right" | "left" | "up" | "all_dirs"

# Corner anchors (relative to board center). Tweak if the board is larger/smaller.
const DEV_CORNER_UL := Vector2(-140, -140)
const DEV_CORNER_UR := Vector2( 140, -140)
const DEV_CORNER_LR := Vector2( 140,  140)
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
var DEV_REPLAY_CORNERS := "board:2#" \
+ str(DEV_CORNER_UL.x)  + "," + str(DEV_CORNER_UL.y)  + ",1,0.0,0.0,0.0#" \
+ str(DEV_CORNER_UR.x)  + "," + str(DEV_CORNER_UR.y)  + ",2,0.0,0.0,0.0#" \
+ str(DEV_CORNER_LR.x)  + "," + str(DEV_CORNER_LR.y)  + ",1,0.0,0.0,0.0#" \
+ str(DEV_CORNER_CC.x)  + "," + str(DEV_CORNER_CC.y)  + ",1,0.0,0.0,0.0#" \
+ str(DEV_CORNER_LL.x)  + "," + str(DEV_CORNER_LL.y)  + ",2,0.0,0.0,0.0" \
+ "|shoot:0"

var DEV_REPLAY_LINE_X := "board:6#" \
+ "-210,210"  + ",2,0.0,0.0,0.0#" \
+ "-200,-200"  + ",1,0.0,0.0,0.0#" \
+ "-180,-180"  + ",2,0.0,0.0,0.0#" \
+ "-160,-160"  + ",1,0.0,0.0,0.0#" \
+ "-140,-140"  + ",2,0.0,0.0,0.0#" \
+ "-120,-120"  + ",1,0.0,0.0,0.0#" \
+ "-100,-100"  + ",2,0.0,0.0,0.0#" \
+ "-80,-80"  + ",1,0.0,0.0,0.0#" \
+ "-60,-60"  + ",2,0.0,0.0,0.0#" \
+ "-40,-40"  + ",1,0.0,0.0,0.0#" \
+ "-20,-20"  + ",2,0.0,0.0,0.0#" \
+ "0,0"  + ",1,0.0,0.0,0.0#" \
+ "20,20"  + ",1,0.0,0.0,0.0#" \
+ "40,40"  + ",1,0.0,0.0,0.0#" \
+ "60,60"  + ",2,0.0,0.0,0.0#" \
+ "80,80"  + ",1,0.0,0.0,0.0#" \
+ "100,100"  + ",2,0.0,0.0,0.0#" \
+ "120,120"  + ",1,0.0,0.0,0.0#" \
+ "140,140"  + ",2,0.0,0.0,0.0#" \
+ "160,160"  + ",1,0.0,0.0,0.0#" \
+ "180,180"  + ",2,0.0,0.0,0.0#" \
+ "200,200"  + ",2,0.0,0.0,0.0#" \
+ "210,-210"  + ",1,0.0,0.0,0.0#" \
+ "|shoot:0"

# 2) Cardinal movement helpers (same starting layout, different shot dirs)
const _DEV_POWER := 60.0  # moderate power for clear motion without insta-fall

var DEV_REPLAY_DOWN  := "board:0#" \
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

const DEBUG_SHRINK := true
func _dbg_board_state(where: String) -> void:
	if not DEBUG_SHRINK: return
	var texrect := _get_texrect()
	var bz_scale := board_zoom.scale if is_instance_valid(board_zoom) else Vector2.ONE
	var tx_scale := texrect.scale if is_instance_valid(texrect) else Vector2.ONE
	var sc_scale := _board_scale_node.scale if is_instance_valid(_board_scale_node) else Vector2.ONE
	print("[SHRINK] ", where,
		" | idx=", _current_board_index,
		" | zoom_level=", current_scale,
		" | board_zoom.scale=", bz_scale,
		" | scaler.scale=", sc_scale,
		" | texrect.scale=", tx_scale,
		" | base_factor=", _board_base_scale_factor
	)

func _process(_dt: float) -> void:
	_watch_board_nodes()

func _watch_board_nodes() -> void:
	var tex := _get_texrect()
	var tr_s := tex.scale if is_instance_valid(tex) else Vector2.ZERO
	var sc_s := _board_scale_node.scale if is_instance_valid(_board_scale_node) else Vector2.ZERO

	# TextureRect.scale watcher (should stay at 1,1)
	if tr_s != _watch_prev_tr_scale:
		if _inside_our_scale_write == 0:
			print("[WATCH] TextureRect.scale changed -> ", tr_s,
				" | idx=", _current_board_index,
				" | board_zoom.scale=", (board_zoom.scale if is_instance_valid(board_zoom) else Vector2.ONE),
				" | scaler.scale=", sc_s)
			print_stack()
		_watch_prev_tr_scale = tr_s

	# BoardScaler.scale watcher (the one that actually drives board size)
	if sc_s != _watch_prev_sc_scale:
		if _inside_our_scale_write == 0:
			var expected := _target_scale_for_index(_current_board_index)
			print("[WATCH-EXT] BoardScaler.scale changed EXTERNALLY -> ", sc_s,
				" | expected=", expected, " | idx=", _current_board_index)
			print_stack()
			# Auto-restore to keep visuals correct
			if absf(sc_s.x - expected) > 0.0005 or absf(sc_s.y - expected) > 0.0005:
				print("[WATCH-EXT] Restoring BoardScaler.scale to expected: ", expected)
				_inside_our_scale_write += 1
				_board_scale_node.scale = Vector2.ONE * expected
				_inside_our_scale_write -= 1
				sc_s = _board_scale_node.scale
		else:
			# Likely our own tween/immediate set – quiet log (or comment this out)
			# print("[WATCH] BoardScaler.scale changed -> ", sc_s, " (ours)")
			pass

		_watch_prev_sc_scale = sc_s

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
		_kill_overlay_root.z_index = 1000
		board_zoom.add_child(_kill_overlay_root)

	if not is_instance_valid(_safe_debug_poly):
		_safe_debug_poly = Polygon2D.new()
		_safe_debug_poly.color = Color(0, 1, 0, 0.15)
		_safe_debug_poly.visible = _kill_debug_showing
		_kill_overlay_root.add_child(_safe_debug_poly)

	if not is_instance_valid(_safe_debug_outline):
		_safe_debug_outline = Line2D.new()
		_safe_debug_outline.width = 2.0
		_safe_debug_outline.default_color = Color(0, 1, 0, 0.8)
		_safe_debug_outline.closed = true
		_safe_debug_outline.visible = _kill_debug_showing
		_kill_overlay_root.add_child(_safe_debug_outline)

func _set_kill_debug_visible(show: bool) -> void:
	_kill_debug_showing = show
	if is_instance_valid(_safe_debug_poly): _safe_debug_poly.visible = show
	if is_instance_valid(_safe_debug_outline): _safe_debug_outline.visible = show
	for p in _hole_debug_nodes:
		if is_instance_valid(p): p.visible = show
	for l in _hole_debug_outlines:
		if is_instance_valid(l): l.visible = show
	for d in _center_debug_nodes:
		if is_instance_valid(d): d.visible = show

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
