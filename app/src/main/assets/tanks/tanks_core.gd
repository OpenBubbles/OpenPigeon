extends Node
class_name TanksCore

signal opponent_avatar_ready(avatar_data: Dictionary)
signal state_changed
signal board_loaded(board: Dictionary)
signal replay_action(action: Dictionary)
signal turn_changed(is_my_turn: bool)
signal replay_true(has_replay: bool)
signal outbound_ready(payload: Dictionary)
signal outbound_edit_requested(payload: Dictionary)

var allow_outbound_edit: bool = false
var _pending_outbound_payload: Dictionary = {}

var player: int = 1
var spectator_mode: bool = false
var is_my_turn: bool = false
var has_replay: bool = false
var is_your_turn: bool = false
var turn_owner: int = 1

var my_id: String = ""
var p1_id: String = ""
var p2_id: String = ""

var avatar1_str: String = ""
var avatar2_str: String = ""

var replay_raw: String = ""
var steps: Array = []
var current_board: Dictionary = {}

var _my_selection_ready: bool = false
var _my_rot: float = 0.0
var _my_power: float = 0.5

func ingest_game_data(raw_text: String) -> void:
	var res: Variant = JSON.parse_string(raw_text)
	print("RAW INCOMING DATA: ", res)
	var opponent_avatar_key = ""
	if typeof(res) != TYPE_DICTIONARY:
		return

	var d: Dictionary = _normalize_incoming_dict(res as Dictionary)

	my_id = String(d.get("myPlayerId", d.get("sender", "")))
	p1_id = String(d.get("player1", ""))
	p2_id = String(d.get("player2", ""))

	avatar1_str = String(d.get("avatar1", ""))
	avatar2_str = String(d.get("avatar2", ""))
	replay_raw = String(d.get("replay", ""))

	is_your_turn = _to_bool(d.get("isYourTurn", false), false)
	turn_owner = clamp(_to_int(d.get("player", 1), 1), 1, 2)

	_resolve_player_identity(is_your_turn, turn_owner)
	
	if my_id != "" and p1_id != "" and p2_id != "":
		player = (1 if my_id == p1_id else (2 if my_id == p2_id else 0))
		if player == 0:
			spectator_mode = true
			#you_label.text = ""
			#spec_label.show()
			player = 1
	else:
		player = (3 - turn_owner) if is_your_turn else turn_owner
	
	if player == 1:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"
	print("Player: ", player, " | Opponent Avatar Key: ", opponent_avatar_key)
	if opponent_avatar_key != "" and res.has(opponent_avatar_key):
		var avatar_string = res[opponent_avatar_key]
		var opponent_data = _parse_avatar_string(avatar_string)
		emit_signal("opponent_avatar_ready", opponent_data)

	steps = _parse_replay(replay_raw)
	current_board = _find_last_board(steps)

	is_my_turn = is_your_turn
	has_replay = replay_raw.contains("shoot:1")
	emit_signal("replay_true", has_replay)
	emit_signal("turn_changed", is_my_turn)
	emit_signal("state_changed")

	_play_steps_into_signals(steps)

func _to_int(v: Variant, default_val: int) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return int(v)
		TYPE_STRING:
			var s: String = String(v).strip_edges()
			return int(s) if s != "" else default_val
		TYPE_BOOL:
			return 1 if bool(v) else 0
		_:
			return default_val

func _to_bool(v: Variant, default_val: bool) -> bool:
	match typeof(v):
		TYPE_BOOL:
			return bool(v)
		TYPE_INT:
			return int(v) != 0
		TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING:
			var s: String = String(v).strip_edges().to_lower()
			if s in ["1", "true", "yes", "y", "on"]:
				return true
			if s in ["0", "false", "no", "n", "off"]:
				return false
			return default_val
		_:
			return default_val

func set_my_aim(rot_radians: float, power_0_to_1: float) -> void:
	_my_rot = rot_radians
	_my_power = clamp(power_0_to_1, 0.0, 1.0)
	_my_selection_ready = true
	emit_signal("state_changed")

func clear_my_selection() -> void:
	_my_selection_ready = false
	emit_signal("state_changed")

# Toggle this to true when you want to bypass live data
var use_hardcoded_test: bool = false 

func build_outbound_payload(my_avatar_str: String = "") -> Dictionary:
	if current_board.is_empty() and not use_hardcoded_test:
		return {}
	
	var final_payload: Dictionary = {}
	var replay_string: String = ""

	if use_hardcoded_test:
		replay_string = "board:height,0&wind,0.2&tank1x,-140.662827&tank1rot,090.000000&tank1power,1.000000&tank1hp,2&tank2x,116.385284&tank2rot,90.000000&tank2power,0.500000&tank2hp,2|shoot:1"
	else:
		var out_board: Dictionary = current_board.duplicate(true)
		
		# --- RADIANS CALCULATION ---
		var send_rot: float = _my_rot

		if player == 1:
			out_board["tank1rot"] = send_rot
			out_board["tank1power"] = _my_power
		else:
			out_board["tank2rot"] = send_rot
			out_board["tank2power"] = _my_power
		
		var parts: Array[String] = []
		parts.append("board:" + _compose_board_kv(out_board))
		
		if _my_selection_ready:
			parts.append("shoot:1")
		
		replay_string = String("|").join(parts)

	final_payload["replay"] = replay_string
	var avatar_key := ("avatar1" if player == 1 else "avatar2")
	if my_avatar_str != "":
		final_payload[avatar_key] = my_avatar_str
	
	return final_payload
	
func _get_data_deg_for_send(rads: float) -> float:
	# 1. Convert Radians to Degrees
	var deg = rad_to_deg(rads)
	
	# 2. Normalize to a 0-180 arc (the "Visual Degree")
	var visual_deg = fmod(abs(deg), 360.0)
	if visual_deg > 180.0:
		visual_deg = 360.0 - visual_deg
	
	# 3. Handle Player 2 Flip:
	# If Player 2 aims at 45° (inward), they must send 135° so 
	# Player 1 sees them aiming inward from the other side.
	if player == 2:
		return 180.0 - visual_deg
		
	return visual_deg
	
func request_send(my_avatar_str: String = "") -> void:
	var payload: Dictionary = build_outbound_payload(my_avatar_str)
	print("RAW OUTGOING DATA: ", payload)
	if payload.is_empty():
		return

	var safe_payload: Dictionary = payload.duplicate(true)

	if allow_outbound_edit:
		_pending_outbound_payload = safe_payload
		emit_signal("outbound_edit_requested", _pending_outbound_payload.duplicate(true))
		return

	_emit_outbound_ready_deferred(safe_payload)
	
func send_modified_payload(modified_payload: Dictionary = {}) -> void:
	var final_payload: Dictionary = {}

	if not modified_payload.is_empty():
		final_payload = modified_payload.duplicate(true)
	elif not _pending_outbound_payload.is_empty():
		final_payload = _pending_outbound_payload.duplicate(true)

	_pending_outbound_payload.clear()

	if final_payload.is_empty():
		print("send_modified_payload: no payload to send")
		return

	print("FINAL OUTGOING DATA: ", final_payload)
	_emit_outbound_ready_deferred(final_payload)
	
func cancel_pending_payload() -> void:
	_pending_outbound_payload.clear()
	
func _emit_outbound_ready_deferred(payload: Dictionary) -> void:
	var safe_payload: Dictionary = payload.duplicate(true)
	call_deferred("_deferred_emit_outbound_ready", safe_payload)

func _deferred_emit_outbound_ready(payload: Dictionary) -> void:
	emit_signal("outbound_ready", payload)

func _resolve_player_identity(is_your_turn_in: bool, turn_owner_in: int) -> void:
	spectator_mode = false
	player = 1

	if my_id != "" and p1_id != "" and p2_id != "":
		if my_id == p1_id:
			player = 1
		elif my_id == p2_id:
			player = 2
		else:
			spectator_mode = true
			player = 1
	else:
		player = (3 - turn_owner_in) if is_your_turn_in else turn_owner_in
		
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

func _normalize_incoming_dict(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		var v: Variant = d[k]
		if typeof(v) == TYPE_ARRAY:
			var a: Array = v as Array
			out[k] = (String(a[0]) if a.size() > 0 else "")
		else:
			out[k] = v
	return out

func _parse_replay(raw: String) -> Array:
	var out: Array = []
	var s: String = raw.strip_edges()
	if s == "":
		return out

	for part in s.split("|", false):
		var p: String = part.strip_edges()
		if p.begins_with("board:"):
			out.append({ "type": "board", "data": _parse_board_kv(p.substr(6)) })
		elif p.begins_with("shoot:"):
			out.append({ "type": "shoot", "data": { "value": _to_int(p.substr(6), 0) } })
		else:
			out.append({ "type": "unknown", "data": { "raw": p } })
	return out

func _parse_board_kv(kv: String) -> Dictionary:
	var d: Dictionary = {}
	for pair in kv.split("&", false):
		var t: String = pair.strip_edges()
		if t == "":
			continue
		var kvp: Array = t.split(",", false)
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

func _compose_board_kv(board: Dictionary) -> String:
	var parts: Array[String] = []

	var push_kv := func(key: String) -> void:
		if board.has(key):
			parts.append("%s,%s" % [key, str(board[key])])

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

	for k in board.keys():
		var key: String = String(k)
		if key in ["height","wind","tank1x","tank1rot","tank1power","tank1hp","tank2x","tank2rot","tank2power","tank2hp"]:
			continue
		parts.append("%s,%s" % [key, str(board[k])])

	return String("&").join(parts)
	
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

func _find_last_board(parsed_steps: Array) -> Dictionary:
	for i in range(parsed_steps.size() - 1, -1, -1):
		var st: Dictionary = parsed_steps[i] as Dictionary
		if String(st.get("type", "")) == "board":
			return st.get("data", {}) as Dictionary
	return {}

func _play_steps_into_signals(parsed_steps: Array) -> void:
	for st_v in parsed_steps:
		var st: Dictionary = st_v as Dictionary
		var t: String = String(st.get("type", ""))
		if t == "board":
			emit_signal("board_loaded", st.get("data", {}) as Dictionary)
		elif t == "shoot":
			emit_signal("replay_action", st)
