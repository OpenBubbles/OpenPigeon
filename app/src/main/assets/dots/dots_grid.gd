extends Control

signal turn_changed(player: int)
signal score_changed(p1: int, p2: int)
signal game_over(p1: int, p2: int)
signal temp_line_changed(has_line: bool)
signal line_committed_bl(player: int, x1: int, y1: int, x2: int, y2: int)
signal square_completed_bl(player: int, x_bl: int, y_bl: int)

# Config
var N: int = 5                      # dots per side (4/5/6)
@export var dot_radius: float = 9.0
@export var dot_color: Color = Color(0.1, 0.1, 0.1)
@export var line_width: float = 8.0
@export var hover_width: float = 8.0
@export var p_colors: Array[Color] = [Color(0.20,0.55,0.81,0.8), Color(0.92,0.13,0.43,0.8)] # P1 blue, P2 magenta
@export var padding_pct: float = 0.12
@export var animation_duration: float = 0.15
@export var box_animation_duration: float = 0.18
var animating_boxes := {} # keys: Vector2i(bc, br) -> true while animating

# State
var h_edges: Array = []  # size N rows x (N-1) cols; -1 = empty, 1/2 = owner
var v_edges: Array = []  # size (N-1) rows x N cols
var boxes: Array = []    # size (N-1) x (N-1); -1 empty, 1/2 = owner
var input_enabled: bool = true
var last_completed_boxes_bl: Array = []   # each: [player, x_bl, y_bl]

var player: int = 1 # MODIFIED: Player is now 1 or 2
var score: Array[int] = [0, 0] # Index 0 for P1, Index 1 for P2
var edges_claimed: int = 0
var total_edges: int = 0

# Cached layout
var inner: Rect2 = Rect2()
var step: Vector2 = Vector2()
var hover_edge: Dictionary = {"type":"", "r":-1, "c":-1} # {type:"h"/"v", r, c}

# Temp-line placement (not committed to board)
var temp_mode: bool = false
# FIXED: Removed the unused and buggy temp_owner variable.
var temp_edge: Dictionary = {"type":"", "r":-1, "c":-1}


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_PASS
	resized.connect(_on_resized)
	mouse_exited.connect(_on_mouse_exited)
	_reset(5)

func set_grid(n: int) -> void:
	_reset(clamp(n, 4, 6))

func _reset(n: int) -> void:
	N = n

	h_edges.resize(N)
	for r: int in range(N):
		h_edges[r] = []
		h_edges[r].resize(N - 1)
		for c: int in range(N - 1):
			h_edges[r][c] = -1

	v_edges.resize(N - 1)
	for r2: int in range(N - 1):
		v_edges[r2] = []
		v_edges[r2].resize(N)
	for r3: int in range(N - 1):
		for c2: int in range(N):
			v_edges[r3][c2] = -1

	boxes.resize(N - 1)
	for r4: int in range(N - 1):
		boxes[r4] = []
		boxes[r4].resize(N - 1)
		for c3: int in range(N - 1):
			boxes[r4][c3] = -1

	player = 1 # MODIFIED: Start with player 1
	score = [0, 0]
	edges_claimed = 0
	total_edges = N * (N - 1) * 2
	hover_edge = {"type":"", "r":-1, "c":-1}
	animating_boxes.clear()

	# clear any temp state
	temp_mode = false
	temp_edge = {"kind":"", "r":-1, "c":-1}
	emit_signal("temp_line_changed", false)

	_on_resized()
	emit_signal("turn_changed", player)
	emit_signal("score_changed", score[0], score[1])
	queue_redraw()
	
func _is_box_animating(br: int, bc: int) -> bool:
	return animating_boxes.has(Vector2i(bc, br))

func _on_resized() -> void:
	var r: Rect2 = get_rect()
	var side: float = min(r.size.x, r.size.y)
	var pad: float = side * padding_pct
	inner = Rect2(
		Vector2((r.size.x - side) * 0.5 + pad, (r.size.y - side) * 0.5 + pad),
		Vector2(side - 2.0 * pad, side - 2.0 * pad)
	)
	step = inner.size / Vector2(N - 1, N - 1)
	queue_redraw()

# ---------- Temp helpers / API ----------

func has_temp_line() -> bool:
	return String(temp_edge["type"]) != ""
	
func _box_topdown_to_bl(br: int, bc: int) -> Array[int]:
	return [bc, (N - 2) - br]

# Returns [player(1|2), x1,y1,x2,y2] in bottom-left dot coords, or [] if none
func get_temp_line() -> Array:
	if not has_temp_line():
		return []
	var kind: String = String(temp_edge["type"])
	var r: int = int(temp_edge["r"])
	var c: int = int(temp_edge["c"])
	var seg: Array = _edge_to_segment_bl(kind, r, c)
	# FIXED: Get the owner from the temp_edge dictionary, fallback to current player.
	var owner: int = int(temp_edge.get("owner", player))
	return [owner, int(seg[0]), int(seg[1]), int(seg[2]), int(seg[3])]

func clear_temp_line() -> void:
	# Hide the animation line when clearing a temp line.
	if is_instance_valid($AnimationLine):
		$AnimationLine.visible = false
		
	temp_mode = false
	temp_edge = {"kind":"", "r":-1, "c":-1}
	emit_signal("temp_line_changed", false)
	queue_redraw()

func _is_edge_free(kind: String, r: int, c: int) -> bool:
	if kind == "h":
		return h_edges[r][c] == -1
	else:
		return v_edges[r][c] == -1

func _edge_to_segment_bl(kind: String, r: int, c: int) -> Array[int]:
	if kind == "h":
		var y_bl: int = (N - 1) - r
		return [c, y_bl, c + 1, y_bl]
	else: # Vertical line
		var y_top_bl: int = (N - 1) - r
		# This now returns the line as Bottom-to-Top (y1 < y2)
		return [c, y_top_bl - 1, c, y_top_bl]

# ---------- Input / picking ----------
func _gui_input(e: InputEvent) -> void:
	if not input_enabled:
		return

	if e is InputEventMouseMotion:
		var pos: Vector2 = (e as InputEventMouseMotion).position
		hover_edge = _pick_edge(pos)
		queue_redraw()

	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var pos2: Vector2 = (e as InputEventMouseButton).position
		var pick2: Dictionary = _pick_edge(pos2)

		var k2: String = String(pick2.get("type", ""))
		var rr2: int = int(pick2.get("r", -1))
		var cc2: int = int(pick2.get("c", -1))

		if k2 == "":
			clear_temp_line() # Use the new clear function
			return

		var free_ok: bool = false
		if k2 == "h" and rr2 >= 0 and rr2 < N and cc2 >= 0 and cc2 < N - 1:
			free_ok = (h_edges[rr2][cc2] == -1)
		elif k2 == "v" and rr2 >= 0 and rr2 < N - 1 and cc2 >= 0 and cc2 < N:
			free_ok = (v_edges[rr2][cc2] == -1)

		if not free_ok:
			return

		if _would_complete_box(k2, rr2, cc2):
			clear_temp_line()
			# This is a final, scoring move. Animate it as permanent.
			_play_line_animation(k2, rr2, cc2, player, false)
			_claim_edge(k2, rr2, cc2)
			return

		# This is a temporary line. Animate it and show the Send button.
		temp_edge = {"type":k2, "r":rr2, "c":cc2, "owner": player}
		_play_line_animation(k2, rr2, cc2, player, true)
		emit_signal("temp_line_changed", true)
		queue_redraw()

func _would_complete_box(kind: String, r: int, c: int) -> bool:
	# Check adjacent boxes without mutating state.
	if kind == "h":
		# Box above (r-1, c)
		if r - 1 >= 0 and boxes[r - 1][c] == -1:
			if h_edges[r - 1][c] != -1 and v_edges[r - 1][c] != -1 and v_edges[r - 1][c + 1] != -1:
				return true
		# Box below (r, c)
		if r <= (N - 2) and boxes[r][c] == -1:
			if h_edges[r + 1][c] != -1 and v_edges[r][c] != -1 and v_edges[r][c + 1] != -1:
				return true
	else: # kind == "v"
		# Box left (r, c-1)
		if c - 1 >= 0 and boxes[r][c - 1] == -1:
			if v_edges[r][c - 1] != -1 and h_edges[r][c - 1] != -1 and h_edges[r + 1][c - 1] != -1:
				return true
		# Box right (r, c)
		if c <= (N - 2) and boxes[r][c] == -1:
			if v_edges[r][c + 1] != -1 and h_edges[r][c] != -1 and h_edges[r + 1][c] != -1:
				return true
	return false

			
func set_input_enabled(v: bool) -> void:
	input_enabled = v

func _pick_edge(pos: Vector2) -> Dictionary:
	# This is the tolerance for how close you need to click to a line.
	# We'll use this value to expand our detection area.
	var hit_px: float = min(step.x, step.y) * 0.50

	# Convert to grid space
	var rel: Vector2 = pos - inner.position
	
	# FIXED: The check below now includes the 'hit_px' leeway. This allows clicks
	# just outside the formal grid boundaries to be detected, fixing the edge issue.
	if rel.x < -hit_px or rel.y < -hit_px or rel.x > inner.size.x + hit_px or rel.y > inner.size.y + hit_px:
		return {"type":"", "r":-1, "c":-1}

	var i_f: float = rel.x / step.x
	var j_f: float = rel.y / step.y
	var i: int = clamp(int(floor(i_f)), 0, N - 2)
	var j: int = clamp(int(floor(j_f)), 0, N - 2)

	# Nearest row/col lines
	var row: int = clamp(int(round(j_f)), 0, N - 1)
	var col: int = clamp(int(round(i_f)), 0, N - 1)

	var y_line: float = float(row) * step.y
	var x_line: float = float(col) * step.x

	var dist_h: float = abs(rel.y - y_line)
	var dist_v: float = abs(rel.x - x_line)
	
	# Horizontal candidate (between dots along row)
	var h_ok: bool = dist_h <= hit_px and i_f >= 0.0 and i_f <= float(N - 1) and i <= N - 2
	# Vertical candidate
	var v_ok: bool = dist_v <= hit_px and j_f >= 0.0 and j_f <= float(N - 1) and j <= N - 2

	if h_ok and v_ok:
		# choose closer
		if dist_h <= dist_v:
			return {"type":"h", "r":row, "c":i}
		else:
			return {"type":"v", "r":j, "c":col}
	elif h_ok:
		return {"type":"h", "r":row, "c":i}
	elif v_ok:
		return {"type":"v", "r":j, "c":col}
	return {"type":"", "r":-1, "c":-1}
	
func _on_mouse_exited() -> void:
	# This function is called automatically when the mouse leaves the control's area.
	# We clear the hover_edge and redraw to ensure the gray line disappears.
	hover_edge = {"type":"", "r":-1, "c":-1}
	queue_redraw()

func _claim_edge(kind: String, r: int, c: int) -> void:
	# This function now only handles game logic, not animation.
	if kind == "h":
		if h_edges[r][c] != -1: return
		h_edges[r][c] = player
	elif kind == "v":
		if v_edges[r][c] != -1: return
		v_edges[r][c] = player
	else:
		return
		
	var seg := _edge_to_segment_bl(kind, r, c)
	emit_signal("line_committed_bl", player, int(seg[0]), int(seg[1]), int(seg[2]), int(seg[3]))
	edges_claimed += 1
	var made_box: int = _check_boxes_from_edge(kind, r, c)

	if made_box == 0:
		player = 3 - player
		emit_signal("turn_changed", player)
	else:
		emit_signal("score_changed", score[0], score[1])

	queue_redraw()

	if score[0] + score[1] == (N - 1) * (N - 1):
		emit_signal("game_over", score[0], score[1])

func _check_boxes_from_edge(kind: String, r: int, c: int) -> int:
	var won: int = 0
	if kind == "h":
		if r - 1 >= 0 and boxes[r - 1][c] == -1 and _is_box_complete(r - 1, c):
			boxes[r - 1][c] = player
			_play_box_x_animation(r - 1, c, player)
			score[player - 1] += 1
			var bl := _box_topdown_to_bl(r - 1, c)
			last_completed_boxes_bl.append([player, int(bl[0]), int(bl[1])])  # NEW
			emit_signal("square_completed_bl", player, int(bl[0]), int(bl[1]))
			won += 1
		if r <= (N - 2) and boxes[r][c] == -1 and _is_box_complete(r, c):
			boxes[r][c] = player
			_play_box_x_animation(r, c, player)
			score[player - 1] += 1
			var bl2 := _box_topdown_to_bl(r, c)
			last_completed_boxes_bl.append([player, int(bl2[0]), int(bl2[1])]) # NEW
			emit_signal("square_completed_bl", player, int(bl2[0]), int(bl2[1]))
			won += 1
	elif kind == "v":
		if c - 1 >= 0 and boxes[r][c - 1] == -1 and _is_box_complete(r, c - 1):
			boxes[r][c - 1] = player
			_play_box_x_animation(r, c - 1, player)
			score[player - 1] += 1
			var bl3 := _box_topdown_to_bl(r, c - 1)
			last_completed_boxes_bl.append([player, int(bl3[0]), int(bl3[1])]) # NEW
			emit_signal("square_completed_bl", player, int(bl3[0]), int(bl3[1]))
			won += 1
		if c <= (N - 2) and boxes[r][c] == -1 and _is_box_complete(r, c):
			boxes[r][c] = player
			_play_box_x_animation(r, c, player)
			score[player - 1] += 1
			var bl4 := _box_topdown_to_bl(r, c)
			last_completed_boxes_bl.append([player, int(bl4[0]), int(bl4[1])]) # NEW
			emit_signal("square_completed_bl", player, int(bl4[0]), int(bl4[1]))
			won += 1
	return won
	
func _x_endpoints_for_box(br: int, bc: int) -> Dictionary:
	var tl: Vector2 = _dot_pos(bc,   br)
	var tr: Vector2 = _dot_pos(bc+1, br)
	var bl: Vector2 = _dot_pos(bc,   br+1)
	var brp: Vector2 = _dot_pos(bc+1, br+1)

	var shrink: float = min(step.x, step.y) * 0.22
	var center: Vector2 = (tl + brp) * 0.5

	var a0: Vector2 = _shrink_toward(center, tl,  shrink)
	var a1: Vector2 = _shrink_toward(center, brp, shrink)
	var b0: Vector2 = _shrink_toward(center, tr,  shrink)
	var b1: Vector2 = _shrink_toward(center, bl,  shrink)

	return {"a0": a0, "a1": a1, "b0": b0, "b1": b1}


func _make_temp_line2d(col: Color, width: float) -> Line2D:
	var ln := Line2D.new()
	ln.default_color = col
	ln.width = width
	ln.antialiased = true
	# Draw on top of dots/edges while animating
	ln.z_index = 9999
	add_child(ln)
	return ln


func _play_box_x_animation(br: int, bc: int, owner: int) -> void:
	var ends := _x_endpoints_for_box(br, bc)
	var col := p_colors[owner - 1]
	col.a = 0.8
	var w := line_width * 0.75

	# NEW: mark as animating so _draw() skips the permanent X
	var key := Vector2i(bc, br)
	animating_boxes[key] = true

	# First stroke
	var l1 := _make_temp_line2d(col, w)
	l1.points = [ends["a0"], ends["a0"]]

	# Second stroke
	var l2 := _make_temp_line2d(col, w)
	l2.points = [ends["b0"], ends["b0"]]

	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(
		func(p):
			if is_instance_valid(l1):
				l1.points[1] = p,
		ends["a0"], ends["a1"], box_animation_duration
	)

	t.tween_callback(func():
		if is_instance_valid(l2):
			var t2 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			t2.tween_method(
				func(p):
					if is_instance_valid(l2):
						l2.points[1] = p,
				ends["b0"], ends["b1"], box_animation_duration
			)
			t2.tween_callback(func():
				if is_instance_valid(l1): l1.queue_free()
				if is_instance_valid(l2): l2.queue_free()

				# NEW: unmark and redraw so the permanent X appears now
				animating_boxes.erase(key)
				queue_redraw()
			)
	)

func _is_box_complete(br: int, bc: int) -> bool:
	# edges:
	# top:    h_edges[br][bc]
	# bottom: h_edges[br+1][bc]
	# left:   v_edges[br][bc]
	# right:  v_edges[br][bc+1]
	if h_edges[br][bc] == -1: return false
	if h_edges[br + 1][bc] == -1: return false
	if v_edges[br][bc] == -1: return false
	if v_edges[br][bc + 1] == -1: return false
	return true
	
func commit_temp_line_now() -> bool:
	if String(temp_edge.get("type", "")) == "":
		return false

	var k: String = String(temp_edge["type"])
	var r: int = int(temp_edge["r"])
	var c: int = int(temp_edge["c"])

	if not _is_edge_free(k, r, c):
		return false
	
	# This is a final, non-scoring move. Animate it as permanent.
	_play_line_animation(k, r, c, player, false)

	if k == "h":
		h_edges[r][c] = player
	elif k == "v":
		v_edges[r][c] = player
	else:
		return false

	edges_claimed += 1

	var seg := _edge_to_segment_bl(k, r, c)
	emit_signal("line_committed_bl", player, int(seg[0]), int(seg[1]), int(seg[2]), int(seg[3]))

	last_completed_boxes_bl.clear()
	var made_box: int = _check_boxes_from_edge(k, r, c)

	if made_box == 0:
		player = 3 - player
		emit_signal("turn_changed", player)
	else:
		emit_signal("score_changed", score[0], score[1])

	clear_temp_line()
	queue_redraw()

	if score[0] + score[1] == (N - 1) * (N - 1):
		emit_signal("game_over", score[0], score[1])

	return true
	
func get_last_completed_boxes() -> Array:
	# Returns [[player, x_bl, y_bl], ...] for the most recent committed line
	return last_completed_boxes_bl.duplicate(true)
	
func get_all_committed_lines() -> Array:
	var lines: Array = []
	# horizontals
	for r: int in range(N):
		for c: int in range(N - 1):
			var o: int = h_edges[r][c]
			if o != -1:
				var seg := _edge_to_segment_bl("h", r, c)
				# MODIFIED: owner `o` is already 1 or 2
				lines.append([o, int(seg[0]), int(seg[1]), int(seg[2]), int(seg[3])])
	# verticals
	for r2: int in range(N - 1):
		for c2: int in range(N):
			var o2: int = v_edges[r2][c2]
			if o2 != -1:
				var seg2 := _edge_to_segment_bl("v", r2, c2)
				# MODIFIED: owner `o2` is already 1 or 2
				lines.append([o2, int(seg2[0]), int(seg2[1]), int(seg2[2]), int(seg2[3])])
	return lines

func _draw() -> void:
	# --- DRAW LINES FIRST ---

	# NOTE: The temporary line is now drawn by the AnimationLine node,
	# so we have removed it from this function.

	# Claimed edges
	for r2: int in range(N):
		for c2: int in range(N - 1):
			var o: int = h_edges[r2][c2]
			if o != -1:
				_draw_edge("h", r2, c2, p_colors[o - 1], line_width)
	for r3: int in range(N - 1):
		for c3: int in range(N):
			var o2: int = v_edges[r3][c3]
			if o2 != -1:
				_draw_edge("v", r3, c3, p_colors[o2 - 1], line_width)

	# Box X (owner color)
	for r4: int in range(N - 1):
		for c4: int in range(N - 1):
			var owner: int = boxes[r4][c4]
			if owner != -1 and not _is_box_animating(r4, c4):
				_draw_box_x(r4, c4, p_colors[owner - 1])

	# --- DRAW DOTS ON TOP ---
	for r: int in range(N):
		for c: int in range(N):
			var p: Vector2 = _dot_pos(c, r)
			draw_circle(p, dot_radius, dot_color)

func _dot_pos(c: int, r: int) -> Vector2:
	return inner.position + Vector2(float(c) * step.x, float(r) * step.y)

func _edge_endpoints(kind: String, r: int, c: int) -> Array[Vector2]:
	if kind == "h":
		var p0: Vector2 = _dot_pos(c,   r)
		var p1: Vector2 = _dot_pos(c+1, r)
		return [p0, p1]
	else:
		var p0v: Vector2 = _dot_pos(c, r)
		var p1v: Vector2 = _dot_pos(c, r+1)
		return [p0v, p1v]

func _draw_edge(kind: String, r: int, c: int, col: Color, width: float) -> void:
	var pts: Array = _edge_endpoints(kind, r, c)
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	# inset so lines don't overlap dot circles
	var dir: Vector2 = (b - a).normalized()
	var inset: Vector2 = dir * dot_radius * 0.9
	draw_line(a + inset, b - inset, col, width, true)

func _shrink_toward(center: Vector2, p: Vector2, shrink: float) -> Vector2:
	var v: Vector2 = p - center
	var len: float = v.length()
	if len <= 0.0001:
		return p
	return center + v.normalized() * max(0.0, len - shrink)

func _draw_box_x(br: int, bc: int, col: Color) -> void:
	var tl: Vector2 = _dot_pos(bc,   br)
	var tr: Vector2 = _dot_pos(bc+1, br)
	var bl: Vector2 = _dot_pos(bc,   br+1)
	var brp: Vector2 = _dot_pos(bc+1, br+1)

	# Shrink toward center to avoid touching dots/edges
	var shrink: float = min(step.x, step.y) * 0.22
	var center: Vector2 = (tl + brp) * 0.5

	var a0: Vector2 = _shrink_toward(center, tl,  shrink)
	var a1: Vector2 = _shrink_toward(center, brp, shrink)
	var b0: Vector2 = _shrink_toward(center, tr,  shrink)
	var b1: Vector2 = _shrink_toward(center, bl,  shrink)

	draw_line(a0, a1, col, line_width * 0.75, true)
	draw_line(b0, b1, col, line_width * 0.75, true)

# ---------- External load / replay helpers ----------

func load_lines_and_squares_state(lines: Array, squares: Array) -> void:
	_reset(N)
	# lines
	for l in lines:
		if typeof(l) == TYPE_ARRAY and l.size() >= 5:
			_apply_committed_line(int(l[0]), int(l[1]), int(l[2]), int(l[3]), int(l[4]))
	for s in squares:
		if typeof(s) == TYPE_ARRAY and s.size() >= 3:
			var p: int = clampi(int(s[0]), 1, 2)              # <-- typed + clampi
			var br_bc: Array[int] = _square_bl_to_topdown(int(s[1]), int(s[2]))
			var br: int = br_bc[0]
			var bc: int = br_bc[1]
			if br >= 0 and br < (N - 1) and bc >= 0 and bc < (N - 1):
				if boxes[br][bc] == -1:
					boxes[br][bc] = p
					score[p - 1] += 1
					var bl: Array[int] = _box_topdown_to_bl(br, bc)
					emit_signal("square_completed_bl", p, bl[0], bl[1])
	emit_signal("score_changed", score[0], score[1])
	queue_redraw()

func load_lines_state(lines: Array) -> void:
	# Start from a clean board of current N
	_reset(N)
	for l in lines:
		if typeof(l) != TYPE_ARRAY or l.size() < 5:
			continue
		# MODIFIED: Input player is already 1 or 2
		var p_owner12: int = clamp(int(l[0]), 1, 2)
		var x1: int = int(l[1])
		var y1: int = int(l[2])
		var x2: int = int(l[3])
		var y2: int = int(l[4])
		_apply_committed_line(p_owner12, x1, y1, x2, y2)
	# update UI
	emit_signal("score_changed", score[0], score[1])
	queue_redraw()

func replay_line_move(move: Array) -> void:
	if typeof(move) != TYPE_ARRAY or move.size() < 5:
		return
	
	var p_owner12: int = clamp(int(move[0]), 1, 2)
	var x1: int = int(move[1])
	var y1: int = int(move[2])
	var x2: int = int(move[3])
	var y2: int = int(move[4])

	var m: Dictionary = _segment_to_edge(x1, y1, x2, y2)
	if not bool(m.get("ok", false)):
		_apply_committed_line(p_owner12, x1, y1, x2, y2) # Fallback for safety
		return

	# Animate the opponent's move as a permanent line.
	_play_line_animation(String(m["kind"]), int(m["r"]), int(m["c"]), p_owner12, false)
	
	_apply_committed_line(p_owner12, x1, y1, x2, y2)

	emit_signal("score_changed", score[0], score[1])
	emit_signal("turn_changed", player)
	queue_redraw()
	
func _square_bl_to_topdown(br_bl_x: int, br_bl_y: int) -> Array[int]:
	return [(N - 2) - br_bl_y, br_bl_x]

# Return all claimed squares as [player, x_bl, y_bl]
func get_all_claimed_squares() -> Array:
	var out: Array = []
	for br in range(N - 1):
		for bc in range(N - 1):
			var o: int = boxes[br][bc]
			if o != -1:
				var bl := _box_topdown_to_bl(br, bc)
				out.append([o, int(bl[0]), int(bl[1])])
	return out

func _play_line_animation(kind: String, r: int, c: int, owner: int, is_temp: bool) -> void:
	# Find the screen coordinates for the line
	var endpoints: Array[Vector2] = _edge_endpoints(kind, r, c)
	var start_pos: Vector2 = endpoints[0]
	var end_pos: Vector2 = endpoints[1]

	# Set up the animation line
	var anim_line: Line2D = $AnimationLine
	# Kill any previous animation to prevent overlap
	if anim_line.has_meta("tween"):
		var old_tween: Tween = anim_line.get_meta("tween")
		if is_instance_valid(old_tween):
			old_tween.kill()

	anim_line.points = [start_pos, start_pos] # Start with a zero-length line
	anim_line.default_color = p_colors[owner - 1]
	anim_line.width = line_width
	anim_line.visible = true

	# Create and run the animation
	var tween := create_tween()
	tween.tween_method(
		func(p): 
			if is_instance_valid(anim_line): anim_line.points[1] = p,
		start_pos,
		end_pos,
		animation_duration # Use our new speed variable here
	).set_ease(Tween.EASE_OUT)

	anim_line.set_meta("tween", tween)

	# For permanent lines, hide the animation line when done,
	# as the _draw function will handle drawing it from now on.
	if not is_temp:
		tween.tween_callback(func():
			if is_instance_valid(anim_line):
				anim_line.visible = false
		)
		
func _to_topdown_row(y_bottom_left: int) -> int:
	return (N - 1) - y_bottom_left

# Given two bottom-left points, figure out whether it is H or V and the r/c indices for our grids.
# Returns: { ok: bool, kind: "h"|"v", r: int, c: int }
func _segment_to_edge(x1: int, y1: int, x2: int, y2: int) -> Dictionary:
	# Horizontal?
	if y1 == y2 and abs(x2 - x1) == 1:
		var row_td: int = _to_topdown_row(y1)
		var c: int = min(x1, x2)
		if row_td >= 0 and row_td <= N - 1 and c >= 0 and c <= N - 2:
			return {"ok": true, "kind":"h", "r": row_td, "c": c}
	# Vertical?
	if x1 == x2 and abs(y2 - y1) == 1:
		var col: int = x1
		# top-down rows cover the *upper* endpoint
		var r_td: int = min(_to_topdown_row(y1), _to_topdown_row(y2))
		if r_td >= 0 and r_td <= N - 2 and col >= 0 and col <= N - 1:
			return {"ok": true, "kind":"v", "r": r_td, "c": col}
	return {"ok": false}

# Commit a line as if it was already played by p_owner12 (1/2).
# This sets the edge owner, updates score/boxes, and keeps the same player
# if they completed a box—otherwise flips for display parity.
func _apply_committed_line(p_owner12: int, x1: int, y1: int, x2: int, y2: int) -> void:
	var m: Dictionary = _segment_to_edge(x1, y1, x2, y2)
	if not bool(m.get("ok", false)):
		return

	# Temporarily force 'player' to the owner of this committed edge
	var prev_player: int = player
	player = p_owner12 # MODIFIED: Use player 1 or 2 directly

	var kind: String = String(m["kind"])
	var r: int = int(m["r"])
	var c: int = int(m["c"])

	# Skip if already set
	if kind == "h":
		if h_edges[r][c] != -1:
			player = prev_player
			return
		h_edges[r][c] = player
	elif kind == "v":
		if v_edges[r][c] != -1:
			player = prev_player
			return
		v_edges[r][c] = player

	edges_claimed += 1
	var made_box: int = _check_boxes_from_edge(kind, r, c)

	# Turn logic for replay display: if no box, flip to the "other" player
	# so that subsequent committed moves come from the right side by default.
	if made_box == 0:
		player = 3 - player # MODIFIED: Logic to switch between player 1 and 2
	# else: keep same player if they scored (matches dots&boxes extra turn rule)
