# =============================================================================
#  PhysicsDiff.gd  —  iOS-vs-Godot Knockout physics divergence harness
# =============================================================================
#
#  PURPOSE
#  -------
#  Records per-frame piece state during a replay shot, then compares it
#  against ground-truth captured from iOS via Frida. Prints a frame-by-frame
#  delta table plus a single summary score so we can tune physics constants
#  and immediately see whether a change made things better or worse.
#
#  HOW IT WORKS
#  ------------
#   1. iOS side: run frida_capture_knockout.js against the live game, do ONE
#      known shot. It prints a JSON blob.
#   2. Paste that JSON into  res://dev/ios_reference.json  (or set the path).
#   3. In Godot, enable PhysicsDiff, run the SAME shot (same seed / same
#      DEV_REPLAY string). It records every physics frame.
#   4. On settle, it aligns the two timelines by frame index and prints:
#        - per-piece, per-sample position error (in world units)
#        - mean / max / RMS error across the whole shot
#        - the single worst frame so you know where divergence starts
#
#  The key number to optimize is  SUMMARY  max_err  and  rms_err.
#  Lower = closer to iOS. Tune one constant, re-run, compare.
#
#  INTEGRATION  (see bottom of file for exact call sites)
# =============================================================================

class_name PhysicsDiff
extends RefCounted

# ---- Config -----------------------------------------------------------------
const SAMPLE_EVERY_N_PHYSICS_FRAMES := 1   # 1 = every frame (60Hz). 6 ≈ 100ms.
const PRINT_FULL_TABLE := true             # false = only summary
const MATCH_BY := "index"                  # "index" = piece[i] vs ref[i]
const POSITION_EPSILON := 0.01             # treat < this as "exact"

# iOS Frida reference. Either load from file, or paste inline (see _load_ref).
const IOS_REFERENCE_PATH := "res://dev/ios_reference.json"

# ---- State ------------------------------------------------------------------
var _recording := false
var _frame_idx := 0
var _samples: Array = []          # [{ "f": int, "t_ms": int, "pieces": [ {p,x,y,vx,vy,a}, ... ] }]
var _ref: Dictionary = {}         # parsed iOS reference
var _label := ""

# -----------------------------------------------------------------------------
#  Recording
# -----------------------------------------------------------------------------
func start(label: String = "") -> void:
	_recording = true
	_frame_idx = 0
	_samples.clear()
	_label = label
	print("\n[PDIFF] ===== recording started: ", label, " =====")

func stop() -> void:
	_recording = false
	print("[PDIFF] ===== recording stopped: ", _samples.size(), " samples =====")

# Call once per physics frame from knockout.gd::_physics_process while a
# replay shot is in flight.  `pieces` = array of RigidBody2D (order matters,
# must match the iOS capture order — both walk player1 then player2, by slot).
func tick(pieces: Array) -> void:
	if not _recording:
		return
	_frame_idx += 1
	if _frame_idx % SAMPLE_EVERY_N_PHYSICS_FRAMES != 0:
		return

	var rec_pieces: Array = []
	for rb in pieces:
		if not is_instance_valid(rb):
			continue
		# Convert Godot screen-space back to iOS world coords for apples-to-apples.
		# Godot piece.position is relative to piece_container, whose origin sits
		# at board-center (LOGICAL_BOARD_SIZE * 0.5). iOS coords are board-center
		# relative with Y-up. We negate Y to undo the parse-time negation.
		var wp: Vector2 = _godot_to_ios(rb)
		var v: Vector2 = rb.linear_velocity
		rec_pieces.append({
			"p":  int(rb.get_meta("player", 0)),
			"x":  wp.x,
			"y":  wp.y,
			"vx": v.x,
			"vy": -v.y,                       # iOS Y-up
			"a":  -rb.rotation,               # iOS angle (undo parse negation)
		})

	_samples.append({
		"f":      _frame_idx,
		"t_ms":   Time.get_ticks_msec(),
		"pieces": rec_pieces,
	})

# Godot piece -> iOS world coordinate.
# piece_container origin = LOGICAL_BOARD_SIZE*0.5 in screen space, so
# piece.position is ALREADY board-center-relative. Parser did Vector2(x, -y),
# so to recover iOS we negate y back.
func _godot_to_ios(rb: Node) -> Vector2:
	var p: Vector2 = rb.position
	return Vector2(p.x, -p.y)

# -----------------------------------------------------------------------------
#  Reference loading
# -----------------------------------------------------------------------------
func _load_ref() -> bool:
	if not _ref.is_empty():
		return true

	# 1) Try file
	if FileAccess.file_exists(IOS_REFERENCE_PATH):
		var f := FileAccess.open(IOS_REFERENCE_PATH, FileAccess.READ)
		if f:
			var txt := f.get_as_text()
			f.close()
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary:
				_ref = parsed
				print("[PDIFF] loaded iOS reference from ", IOS_REFERENCE_PATH,
					  " (", _ref.get("samples", []).size(), " samples)")
				return true
			else:
				push_warning("[PDIFF] ios_reference.json did not parse to a Dictionary")

	push_warning("[PDIFF] No iOS reference available — printing Godot-only trace.")
	return false

# -----------------------------------------------------------------------------
#  Comparison / report
# -----------------------------------------------------------------------------
func report() -> void:
	print("\n[PDIFF] ================ REPORT: ", _label, " ================")
	print("[PDIFF] Godot samples: ", _samples.size())

	var have_ref := _load_ref()
	if not have_ref:
		_print_godot_only()
		return

	var ref_samples: Array = _ref.get("samples", [])
	if ref_samples.is_empty():
		push_warning("[PDIFF] reference has no samples[]")
		_print_godot_only()
		return

	print("[PDIFF] iOS samples:   ", ref_samples.size())
	print("[PDIFF] aligning by frame index (Godot frame N <-> iOS sample N)\n")

	var n := min(_samples.size(), ref_samples.size())
	var sum_sq := 0.0
	var sum_abs := 0.0
	var max_err := 0.0
	var max_err_frame := -1
	var max_err_piece := -1
	var count := 0

	if PRINT_FULL_TABLE:
		print("  frame |  pc |    godot (x,y)     |     ios (x,y)      |  err")
		print("  ------+-----+--------------------+--------------------+--------")

	for i in n:
		var g_pieces: Array = _samples[i]["pieces"]
		var r_pieces: Array = ref_samples[i].get("pieces", [])
		var m := min(g_pieces.size(), r_pieces.size())
		for j in m:
			var g: Dictionary = g_pieces[j]
			var r: Dictionary = r_pieces[j]
			var gx := float(g["x"]); var gy := float(g["y"])
			var rx := float(r.get("x", 0.0)); var ry := float(r.get("y", 0.0))
			var err := Vector2(gx - rx, gy - ry).length()

			sum_sq += err * err
			sum_abs += err
			count += 1
			if err > max_err:
				max_err = err
				max_err_frame = int(_samples[i]["f"])
				max_err_piece = j

			if PRINT_FULL_TABLE:
				var flag := ""
				if err > 5.0: flag = "  <-- drift"
				if err > 20.0: flag = "  <-- BIG"
				print("  %5d | %3d | (%8.2f,%8.2f) | (%8.2f,%8.2f) | %6.2f%s" % [
					int(_samples[i]["f"]), j, gx, gy, rx, ry, err, flag
				])

	print("\n[PDIFF] ---------------- SUMMARY ----------------")
	if count > 0:
		print("[PDIFF]   compared points : ", count)
		print("[PDIFF]   mean error      : %.3f units" % (sum_abs / count))
		print("[PDIFF]   rms  error      : %.3f units" % sqrt(sum_sq / count))
		print("[PDIFF]   MAX  error      : %.3f units  (frame %d, piece %d)" % [
			max_err, max_err_frame, max_err_piece])
		print("[PDIFF]   --> lower mean/rms = closer to iOS. Tune & re-run.")
	else:
		print("[PDIFF]   no comparable points")
	print("[PDIFF] =========================================\n")

func _print_godot_only() -> void:
	print("[PDIFF] --- Godot-only trace (no iOS ref) ---")
	for s in _samples:
		var line := "[PDIFF] f=%4d t=%6d " % [int(s["f"]), int(s["t_ms"])]
		for pc in s["pieces"]:
			line += "| p%d (%.1f,%.1f) v=%.1f " % [
				int(pc["p"]), float(pc["x"]), float(pc["y"]),
				Vector2(float(pc["vx"]), float(pc["vy"])).length()
			]
		print(line)
	print("[PDIFF] Paste an iOS reference to enable diffing.\n")

# Dump the Godot recording as JSON (handy to archive a run, or to compare two
# Godot runs against each other when tuning without iOS access).
func dump_godot_json() -> String:
	return JSON.stringify({
		"label": _label,
		"engine": "godot",
		"samples": _samples,
	}, "  ")
