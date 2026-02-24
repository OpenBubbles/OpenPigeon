extends RefCounted
class_name TanksReplay

static func parse(raw: String) -> Array:
	var out: Array = []
	var s: String = raw.strip_edges()
	if s == "":
		return out

	var parts := s.split("|", false)
	for part in parts:
		var p: String = String(part).strip_edges()
		if p.begins_with("board:"):
			out.append({
				"type": "board",
				"data": parse_board_kv(p.substr(6))
			})
		elif p.begins_with("shoot:"):
			var v_str: String = p.substr(6).strip_edges()
			out.append({
				"type": "shoot",
				"data": { "value": int(v_str) }
			})
		else:
			out.append({
				"type": "unknown",
				"data": { "raw": p }
			})

	return out

static func parse_board_kv(kv: String) -> Dictionary:
	var d: Dictionary = {}
	var pairs := kv.split("&", false)

	for pair in pairs:
		var t: String = String(pair).strip_edges()
		if t == "":
			continue

		var kvp := t.split(",", false)
		if kvp.size() < 2:
			continue

		var key: String = String(kvp[0]).strip_edges()
		var val: String = String(kvp[1]).strip_edges()

		match key:
			"height", "wind", "tank1x", "tank1rot", "tank1power", "tank2x", "tank2rot", "tank2power":
				d[key] = float(val)
			"tank1hp", "tank2hp":
				d[key] = int(val)
			_:
				d[key] = val

	return d

static func compose_board_kv(board: Dictionary) -> String:
	var parts: Array[String] = []

	var push_kv = func(key: String) -> void:
		if board.has(key):
			parts.append("%s,%s" % [key, str(board[key])])

	# Stable key order for debugging
	push_kv.call("height")
	push_kv.call("wind")
	push_kv.call("tank1x")
	push_kv.call("tank1rot")
	push_kv.call("tank1power")
	push_kv.call("tank1hp")
	push_kv.call("tank2x")
	push_kv.call("tank2rot")
	push_kv.call("tank2power")
	push_kv.call("tank2hp")

	# Unknown keys at end
	for k in board.keys():
		var key: String = String(k)
		if key in ["height","wind","tank1x","tank1rot","tank1power","tank1hp","tank2x","tank2rot","tank2power","tank2hp"]:
			continue
		parts.append("%s,%s" % [key, str(board[k])])

	return String("&").join(parts)

static func find_last_board(steps: Array) -> Dictionary:
	for i in range(steps.size() - 1, -1, -1):
		var st: Dictionary = steps[i]
		if String(st.get("type", "")) == "board":
			return st.get("data", {}) as Dictionary
	return {}

static func has_shoot_ready(steps: Array) -> bool:
	for st in steps:
		var d: Dictionary = st as Dictionary
		if String(d.get("type", "")) == "shoot":
			var data: Dictionary = d.get("data", {}) as Dictionary
			return int(data.get("value", 0)) == 1
	return false
