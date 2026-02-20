extends RefCounted
class_name PB_State

var g: PaintballGame

func setup(owner: PaintballGame) -> void:
	g = owner

func dbg(tag: String) -> void:
	print("[DBG][", tag, "] playernum=", g.playernum,
		" is_my_turn=", g.is_my_turn,
		" pending_enemy=", g._pending_enemy_shot,
		" opp_pos_enc=", g._opp_pos_enc,
		" opp_target_enc=", g._opp_target_enc,
		" my_lane=", int(g._player_lane),
		" my_selected=", (-1 if g._selected_shoot == null else int(g._selected_shoot.lane)),
		" segs=", g._replay_segments.size(),
		" seg_i=", g._replay_seg_index,
		" last_replay_len=", g._last_replay_str.length()
	)
	if g._last_replay_str != "":
		var parts: PackedStringArray = g._last_replay_str.split("|", false)
		print("[DBG][", tag, "] last_replay_segs=", parts.size(), " last_seg=", parts[parts.size() - 1])

func res_str(res: Dictionary, key: String, default_value: String = "") -> String:
	var v: Variant = res.get(key, default_value)
	if v is Array:
		var a: Array = v
		if a.size() > 0:
			return String(a[0])
	return String(v)

func res_bool(res: Dictionary, key: String, default_value: bool = false) -> bool:
	var v: Variant = res.get(key, default_value)
	if v is Array:
		var a: Array = v
		if a.size() > 0:
			return bool(a[0])
	return bool(v)

func res_int(res: Dictionary, key: String, default_value: int = 0) -> int:
	var v: Variant = res.get(key, default_value)
	if v is Array:
		var a: Array = v
		if a.size() > 0:
			return int(a[0])
	return int(v)

func lane_to_enc(lane: ActionButton3D.Lane) -> int:
	match lane:
		ActionButton3D.Lane.LEFT:
			return 0
		ActionButton3D.Lane.CENTER:
			return 1
		ActionButton3D.Lane.RIGHT:
			return 2
		_:
			return 1

func enc_to_lane(enc: int) -> ActionButton3D.Lane:
	match enc:
		0:
			return ActionButton3D.Lane.LEFT
		1:
			return ActionButton3D.Lane.CENTER
		2:
			return ActionButton3D.Lane.RIGHT
		_:
			return ActionButton3D.Lane.CENTER
			
func lane_to_pos_enc(lane: ActionButton3D.Lane) -> int:
	return lane_to_enc(lane) # normal

func lane_to_target_enc(lane: ActionButton3D.Lane) -> int:
	return flip_enc_for_perspective(lane_to_enc(lane))

func pos_enc_to_lane_for_view(enc: int) -> ActionButton3D.Lane:
	return enc_to_lane(flip_enc_for_perspective(enc))

func target_enc_to_lane_for_view(enc: int) -> ActionButton3D.Lane:
	return enc_to_lane(enc)

func my_target_enc_to_lane(enc: int) -> ActionButton3D.Lane:
	return enc_to_lane(flip_enc_for_perspective(enc))

func flip_enc_for_perspective(enc: int) -> int:
	if enc == 0:
		return 2
	if enc == 2:
		return 0
	return enc

func parse_avatar_string(data_string: String) -> Dictionary:
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

func set_game_data(raw_text: String) -> void:
	var res: Dictionary = JSON.parse_string(raw_text)
	if typeof(res) != TYPE_DICTIONARY:
		return

	print("RAW INCOMING DATA: ", res)

	g.my_id = res_str(res, "myPlayerId", "")
	g.p1_id = res_str(res, "player1", "")
	g.p2_id = res_str(res, "player2", "")

	g._opp_id = ""
	if g.my_id != "" and g.p1_id != "" and g.p2_id != "":
		if g.my_id == g.p1_id:
			g._opp_id = g.p2_id
		elif g.my_id == g.p2_id:
			g._opp_id = g.p1_id

	g.turn_owner = clamp(res_int(res, "player", 1), 1, 2)
	g.is_your_turn = res_bool(res, "isYourTurn", false)
	g.winner = res_str(res, "winner", "")

	if g.my_id != "" and g.p1_id != "" and g.p2_id != "":
		g.playernum = (1 if g.my_id == g.p1_id else (2 if g.my_id == g.p2_id else 0))
		if g.playernum == 0:
			g.spectator_mode = true
			if is_instance_valid(g.you_label):
				g.you_label.text = ""
			if is_instance_valid(g.spec_label):
				g.spec_label.show()
			g.playernum = 1
	else:
		g.playernum = (1 if g.turn_owner == 2 else 2)

	g.is_my_turn = g.is_your_turn
	if g.is_my_turn:
	# If it's my turn, we must not be "in replay playback"
		g._is_replay_playback = false
		g._replay_auto_pending = false
	g._need_new_selection = true
	g._touched_this_turn = false
	g._selected_shoot = null

	if g.is_my_turn:
		g._require_new_shoot_selection = true
		g._selected_shoot = null
		g._show_fire_button(false)
		if is_instance_valid(g.fire_button):
			g.fire_button.visible = false

		g.stop_waiting_animation()

		g._set_all_buttons_clickable(true)
		g._update_move_buttons()
	else:
		g._show_fire_button(false)
		if is_instance_valid(g.fire_button):
			g.fire_button.visible = false

		g._set_all_buttons_clickable(false)

		if not g.game_over:
			g.start_waiting_animation()

	var opponent_avatar_key: String = ("avatar2" if g.playernum == 1 else "avatar1")
	if opponent_avatar_key != "" and res.has(opponent_avatar_key):
		var avatar_string: String = res_str(res, opponent_avatar_key, "")
		var opponent_data = parse_avatar_string(avatar_string)
		if is_instance_valid(g.opp_avatar_display):
			g.opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	var replay_str: String = res_str(res, "replay", "")
	print("[REPLAY] raw=", replay_str)

	g._pending_enemy_shot = false
	g._opp_target_world = Vector3.ZERO
	g._opp_target_lane = ActionButton3D.Lane.CENTER

	var hp1: int = 3
	var hp2: int = 3

	if replay_str != "":
		g.replay.ingest_replay_string(replay_str)

		# Build SEND-only queue from the payload, but strip any FULL rounds (start-of-game autoplay history)
		g._replay_send_segments = PackedStringArray(replay_str.split("|", false))
		while g._replay_send_segments.size() > 0:
			var st: Dictionary = g._parse_replay_state(String(g._replay_send_segments[0]))
			var full: bool = (
				int(st.get("pos1", -1)) != -1 and int(st.get("pos2", -1)) != -1 and
				int(st.get("target1", -1)) != -1 and int(st.get("target2", -1)) != -1
			)
			if full:
				g._replay_send_segments.remove_at(0)
				continue
			break

		hp1 = g._hp_opp if g.playernum == 2 else g._hp_me
		hp2 = g._hp_me if g.playernum == 2 else g._hp_opp
	else:
		g._replay_send_segments = PackedStringArray()
		g._replay_segments = PackedStringArray()
		g._replay_seg_index = 0
		g._replay_base_state = {}
		g._last_replay_str = ""
		print("[REPLAY] no replay in payload yet (first move scenario)")

	if replay_str == "":
		if g.buttons != null and g.buttons.has_method("spawn_player_random_lane"):
			g.buttons.spawn_player_random_lane()

	g._hp_me = clamp((hp1 if g.playernum == 1 else hp2), 0, 3)
	g._hp_opp = clamp((hp2 if g.playernum == 1 else hp1), 0, 3)
	print("ME HP: ", g._hp_me, " | OPP HP: ", g._hp_opp)

	g._apply_hearts_from_hp()
	g._update_move_buttons()

	g.game_ended = g.check_win()
	if g.game_ended:
		print("GAME ENDED")
		g.stop_waiting_animation()
		g.game_over = true
		if is_instance_valid(g.fp_aim_sprite):
			g.fp_aim_sprite.visible = false

		g._show_fire_button(false)
		if is_instance_valid(g.fire_button):
			g.fire_button.visible = false

		for b in g._buttons:
			if not is_instance_valid(b):
				continue
			b.visible = false
			b.set_click_enabled(false)
			g._set_button_enabled(b, false)

func send_game(clear_targets_for_next_turn: bool = false) -> void:
	if g._is_replay_playback and (g._round_sequence_running or g._is_shot_sequence_running) and not g.game_over:
		print("[Send] Blocked: replay playback running. Not sending.")
		return

	# Safety: clear stuck playback flag if nothing is actually running
	if g._is_replay_playback and not g._round_sequence_running and not g._is_shot_sequence_running:
		print("[Send] NOTE: replay flag was true but no sequence running. Clearing.")
		g._is_replay_playback = false
		g._replay_auto_pending = false


	# If autoplay was queued but user is firing, cancel autoplay and send.
	if g._replay_auto_pending:
		print("[Send] NOTE: autoplay was pending, cancelling due to user send.")
		g._replay_auto_pending = false


	print("[Send] send_game() called clear_targets_for_next_turn=", clear_targets_for_next_turn)
	await g.get_tree().process_frame

	var my_pos_int: int = lane_to_pos_enc(g._player_lane)

	var my_target_int: int = -1
	if g._selected_shoot != null and is_instance_valid(g._selected_shoot):
		my_target_int = lane_to_target_enc(g._selected_shoot.lane)


	var out_replay: String = "|".join(g._replay_send_segments)
	g._last_replay_str = out_replay

	var payload: Dictionary = {
		"replay": out_replay
	}

	var out_parts: PackedStringArray = out_replay.split("|", false)
	print("[Send] REPLAY_OUT segs=", out_parts.size(), " last_seg=", out_parts[out_parts.size() - 1])

	g.game_ended = g.check_win()
	if g.game_ended:
		print("GAME ENDED 1")
		clear_targets_for_next_turn = true

		var winner: String = ""
		var winner_player: int = 0
		var opp_id: String = ""
		if g.my_id != "":
			if g.p1_id != "" and g.my_id == g.p1_id:
				opp_id = g.p2_id
			elif g.p2_id != "" and g.my_id == g.p2_id:
				opp_id = g.p1_id
		if g.win_loss_state == "":
			if g._hp_opp < g._hp_me:
				g.win_loss_state = "1" 
			elif g._hp_opp > g._hp_me:
				g.win_loss_state = "-1"
			else:
				g.win_loss_state = "0"
		if g.win_loss_state == "1":
			winner = g.my_id
			winner_player = g.playernum
		elif g.win_loss_state == "-1":
			winner = opp_id
			winner_player = (2 if g.playernum == 1 else 1)
		else:
			winner = "0"
			winner_player = 0

		payload["winner"] = g.my_id + "|" + g.win_loss_state
		print("[Send] Game ended. my_id=", g.my_id, " winner=", winner, " winnerPlayer=", winner_player, " result=", g.win_loss_state)

	var avatar_key := ("avatar1" if g.playernum == 1 else "avatar2")
	if is_instance_valid(g.player_avatar_display) and g.player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = g.player_avatar_display.get_avatar_data_string()

	print("[Send] PAYLOAD: ", payload)
	dbg("SEND_GAME_BEFORE")

	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.updateGameData(JSON.stringify(payload))
	else:
		print("AppPlugin is null. Cannot send game data.")

	g.is_my_turn = false

	g._show_fire_button(false)
	if is_instance_valid(g.fire_button):
		g.fire_button.visible = false

	g._selected_shoot = null

	g._set_all_buttons_clickable(false)

	if not g.game_over:
		g.play_sent_animation()
