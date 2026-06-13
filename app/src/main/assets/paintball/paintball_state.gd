extends RefCounted
class_name PB_State

const LOG_TAG := "Paintball"

var g: PaintballGame

func setup(owner: PaintballGame) -> void:
	g = owner

func dbg(tag: String) -> void:
	if g == null:
		return

	g.dbg([
		"state_dbg tag=", tag,
		" playernum=", g.playernum,
		" turn=", g.is_my_turn,
		" pendingEnemy=", g._pending_enemy_shot,
		" oppPos=", g._opp_pos_enc,
		" oppTarget=", g._opp_target_enc,
		" myLane=", int(g._player_lane),
		" selected=", (-1 if g._selected_shoot == null else int(g._selected_shoot.lane)),
		" segs=", g._replay_segments.size(),
		" segIndex=", g._replay_seg_index,
		" replayLen=", g._last_replay_str.length()
	])

	if g._last_replay_str != "":
		var parts: PackedStringArray = g._last_replay_str.split("|", false)
		g.dbg(["state_dbg tag=", tag, " lastReplaySegs=", parts.size(), " lastSeg=", parts[parts.size() - 1]])

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
	return lane_to_enc(lane)

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

func set_game_data(raw_text: String) -> void:
	var parsed : Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, ["state_set_game_data invalid JSON raw=", raw_text])
		return

	var res: Dictionary = parsed
	g.dbg(["state_set_game_data keys=", res.keys()])

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

	g.spectator_mode = false

	if g.my_id != "":
		if g.my_id == g.p1_id:
			g.playernum = 1
		elif g.my_id == g.p2_id:
			g.playernum = 2
		elif g.p1_id != "" and g.p2_id != "":
			g.playernum = 0
			g.spectator_mode = true
			if is_instance_valid(g.you_label):
				g.you_label.text = ""
			if is_instance_valid(g.spec_label):
				g.spec_label.show()
		else:
			g.playernum = (1 if g.turn_owner == 2 else 2)
	else:
		if g.p1_id == "" and g.p2_id != "":
			g.playernum = 1 if g.is_your_turn else 2
		elif g.p2_id == "" and g.p1_id != "":
			g.playernum = 2 if g.is_your_turn else 1
		else:
			g.playernum = (1 if g.turn_owner == 2 else 2)

	if g.playernum == 0:
		g.playernum = 1

	g.is_my_turn = g.is_your_turn
	if g.is_my_turn:
		if g.sent_tween and g.sent_tween.is_running():
			g.sent_tween.kill()
		if is_instance_valid(g.sent_label):
			g.sent_label.visible = false
			g.sent_label.modulate.a = 1.0
		g.stop_waiting_animation()
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
	var avatar_string: String = res_str(res, opponent_avatar_key, "").strip_edges()

	if avatar_string != "" and is_instance_valid(g.opp_avatar_display):
		var opponent_data = GameUtils._parse_avatar_string(avatar_string)
		if g.opp_avatar_display.has_method("update_avatar_from_data"):
			g.opp_avatar_display.update_avatar_from_data(opponent_data)

	var replay_str: String = res_str(res, "replay", "")
	OpLog.i(LOG_TAG, ["state_replay_loaded ", g._replay_summary(replay_str), " raw=", replay_str])

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
		OpLog.i(LOG_TAG, "state_replay_empty first_move_scenario")

	if replay_str == "":
		if g.buttons != null and g.buttons.has_method("spawn_player_random_lane"):
			g.buttons.spawn_player_random_lane()

	g._hp_me = clamp((hp1 if g.playernum == 1 else hp2), 0, 3)
	g._hp_opp = clamp((hp2 if g.playernum == 1 else hp1), 0, 3)
	OpLog.i(LOG_TAG, ["hp_loaded me=", g._hp_me, " opp=", g._hp_opp, " player=", g.playernum])

	g._apply_hearts_from_hp()
	g._update_move_buttons()

	g.game_ended = g.check_win()
	if g.game_ended:
		OpLog.i(LOG_TAG, ["state_detected_game_end ", g._state_summary()])
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
			
	OpLog.i(LOG_TAG, [
		"state_set_game_data_done player=", g.playernum,
		" turn=", g.is_my_turn,
		" spectator=", g.spectator_mode,
		" winner=", g.winner,
		" ", g._state_summary()
	])

func send_game(clear_targets_for_next_turn: bool = false) -> void:
	if g._is_replay_playback and (g._round_sequence_running or g._is_shot_sequence_running) and not g.game_over:
		OpLog.w(LOG_TAG, ["send_game blocked replay playback running ", g._state_summary()])
		return

	if g._is_replay_playback and not g._round_sequence_running and not g._is_shot_sequence_running:
		OpLog.w(LOG_TAG, "send_game clearing stuck replay playback flag")
		g._is_replay_playback = false
		g._replay_auto_pending = false

	if g._replay_auto_pending:
		OpLog.i(LOG_TAG, "send_game cancelling pending autoplay")
		g._replay_auto_pending = false

	OpLog.i(LOG_TAG, ["send_game_start clearTargets=", clear_targets_for_next_turn, " ", g._state_summary()])
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
	OpLog.i(LOG_TAG, [
		"send_game_replay ", g._replay_summary(out_replay),
		" lastSeg=", out_parts[out_parts.size() - 1] if out_parts.size() > 0 else ""
	])

	g.game_ended = g.check_win()
	if g.game_ended:
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

		OpLog.i(LOG_TAG, [
			"send_game_winner myId=", g.my_id,
			" winner=", winner,
			" winnerPlayer=", winner_player,
			" result=", g.win_loss_state
		])

	var avatar_key := ("avatar1" if g.playernum == 1 else "avatar2")
	if is_instance_valid(g.player_avatar_display) and g.player_avatar_display.has_method("get_avatar_data_string"):
		payload[avatar_key] = g.player_avatar_display.get_avatar_data_string()

	dbg("SEND_GAME_BEFORE")

	var out_json := JSON.stringify(payload)
	OpLog.event(LOG_TAG, [
		"send_game_out replay=", g._replay_summary(out_replay),
		" pos=", my_pos_int,
		" target=", my_target_int,
		" winner=", str(payload.get("winner", "")),
		" avatarKey=", avatar_key,
		" ", g._state_summary(),
		" raw=", out_json
	])

	var appPlugin := Engine.get_singleton("AppPlugin") if Engine.has_singleton("AppPlugin") else null
	if appPlugin:
		appPlugin.updateGameData(out_json)
	else:
		OpLog.w(LOG_TAG, ["AppPlugin is null; payload not sent raw=", out_json])

	g.is_my_turn = false

	g._show_fire_button(false)
	if is_instance_valid(g.fire_button):
		g.fire_button.visible = false

	g._selected_shoot = null
	g._set_all_buttons_clickable(false)

	if not g.game_over:
		g.play_sent_animation()
