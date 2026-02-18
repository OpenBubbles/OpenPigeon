extends RefCounted
class_name PB_Replay

var g: PaintballGame

func setup(owner: PaintballGame) -> void:
	g = owner
	
func _flip_enc_for_perspective(enc: int) -> int:
	if enc == 0:
		return 2
	if enc == 2:
		return 0
	return enc

func parse_replay_state(state: String) -> Dictionary:
	var out := {
		"hp1": 3, "hp2": 3,
		"pos1": -1, "pos2": -1,
		"target1": -1, "target2": -1
	}

	if state == "":
		return out

	for p in state.split(",", false):
		var kv := String(p).split(":", false)
		if kv.size() != 2:
			continue
		var k := String(kv[0])
		var v := int(String(kv[1]))
		if out.has(k):
			out[k] = v

	return out

func state_to_replay_string(st: Dictionary) -> String:
	return "hp1:%d,hp2:%d,pos1:%d,pos2:%d,target1:%d,target2:%d" % [
		int(st.get("hp1", 3)),
		int(st.get("hp2", 3)),
		int(st.get("pos1", -1)),
		int(st.get("pos2", -1)),
		int(st.get("target1", -1)),
		int(st.get("target2", -1))
	]

func state_has_both_players_ready(st: Dictionary) -> bool:
	return int(st.get("pos1", -1)) != -1 and int(st.get("target1", -1)) != -1 and int(st.get("pos2", -1)) != -1 and int(st.get("target2", -1)) != -1

func state_has_opponent_ready(st: Dictionary) -> bool:
	var opp_pos: int = int(st.get("pos2", -1)) if g.playernum == 1 else int(st.get("pos1", -1))
	var opp_tgt: int = int(st.get("target2", -1)) if g.playernum == 1 else int(st.get("target1", -1))
	return opp_pos != -1 and opp_tgt != -1

func hp_as_p1_order() -> Dictionary:
	if g.playernum == 1:
		return {"hp1": g._hp_me, "hp2": g._hp_opp}
	return {"hp1": g._hp_opp, "hp2": g._hp_me}

func my_replay_keys() -> Dictionary:
	if g.playernum == 1:
		return {"pos": "pos1", "target": "target1"}
	return {"pos": "pos2", "target": "target2"}

func replay_is_full_round(st: Dictionary) -> bool:
	return int(st.get("pos1", -1)) != -1 and int(st.get("pos2", -1)) != -1 and int(st.get("target1", -1)) != -1 and int(st.get("target2", -1)) != -1

func replay_trim_to_sliding_window(segs: PackedStringArray) -> PackedStringArray:
	while segs.size() > 2:
		segs.remove_at(0)
	return segs

func ingest_replay_string(replay_str: String) -> void:
	g._replay_segments = PackedStringArray()
	g._replay_seg_index = 0
	g._replay_base_state = {}
	g._replay_auto_end_state = {}
	g._replay_auto_full_str = ""
	g._replay_auto_pending = false
	g._is_replay_playback = false
	g._last_autoplayed_replay_str = ""

	if replay_str == "":
		g._last_replay_str = ""
		return

	g._replay_segments = replay_str.split("|", false)
	g._last_replay_str = "|".join(g._replay_segments)

	# Apply the first queued segment to set HP/positions/pending shot state
	var first_seg: String = String(g._replay_segments[0])
	var first_state: Dictionary = parse_replay_state(first_seg)
	apply_loaded_replay_segment(first_state)

	# Autoplay any leading FULL segments
	prime_autoplay_if_loaded_segment_ready()

func replay_build_after_my_fire(my_pos_int: int, my_target_int: int) -> String:
	var hp := hp_as_p1_order()
	var myk := my_replay_keys()

	# If we have queued segments, try to fill the FIRST one if my fields are missing
	if g._replay_segments.size() > 0:
		var first_state: Dictionary = parse_replay_state(String(g._replay_segments[0]))

		first_state["hp1"] = int(hp["hp1"])
		first_state["hp2"] = int(hp["hp2"])

		var my_pos_key: String = String(myk["pos"])
		var my_tgt_key: String = String(myk["target"])

		var my_missing: bool = int(first_state.get(my_pos_key, -1)) == -1 or int(first_state.get(my_tgt_key, -1)) == -1

		if my_missing:
			first_state[my_pos_key] = my_pos_int
			first_state[my_tgt_key] = my_target_int
			g._replay_segments[0] = state_to_replay_string(first_state)
			return "|".join(g._replay_segments)

	# Otherwise append a NEW segment with only my fields filled, opponent stays -1
	var st := {
		"hp1": int(hp["hp1"]),
		"hp2": int(hp["hp2"]),
		"pos1": 0, "pos2": 0,
		"target1": -1, "target2": -1
	}

	st[String(myk["pos"])] = my_pos_int
	st[String(myk["target"])] = my_target_int

	g._replay_segments.append(state_to_replay_string(st))
	return "|".join(g._replay_segments)

func apply_loaded_replay_segment(seg_state: Dictionary) -> void:
	var pos1: int = int(seg_state.get("pos1", -1))
	var pos2: int = int(seg_state.get("pos2", -1))
	var target1: int = int(seg_state.get("target1", -1))
	var target2: int = int(seg_state.get("target2", -1))

	var hp1: int = int(seg_state.get("hp1", 3))
	var hp2: int = int(seg_state.get("hp2", 3))

	var pos_me: int = (pos1 if g.playernum == 1 else pos2)
	var pos_opp: int = (pos2 if g.playernum == 1 else pos1)
	var target_me: int = (target1 if g.playernum == 1 else target2)
	var target_opp: int = (target2 if g.playernum == 1 else target1)

	# HP first
	g._hp_me = clamp((hp1 if g.playernum == 1 else hp2), 0, 3)
	g._hp_opp = clamp((hp2 if g.playernum == 1 else hp1), 0, 3)
	g._apply_hearts_from_hp()

	# Pending enemy shot
	# Flip opponent POSITION for our visual perspective (0 <-> 2)
	var pos_opp_vis: int = (pos_opp if pos_opp == -1 else _flip_enc_for_perspective(pos_opp))

	g._opp_pos_enc = pos_opp_vis
	g._opp_target_enc = target_opp
	g._pending_enemy_shot = (g._opp_pos_enc != -1 and g._opp_target_enc != -1)


	# Apply my lane immediately + update move arrows immediately
	if pos_me != -1 and is_instance_valid(g.player):
		g._player_lane = g._enc_to_lane(pos_me)

		var pp: Vector3 = g.player.global_position
		pp.x = float(g._lane_x.get(g._player_lane, 0.0))
		g.player.global_position = pp

		g._update_move_buttons()

	# Keep opponent sprite aligned to lane X (use VIS pos encoding)
	if pos_opp_vis != -1 and is_instance_valid(g.opponent_sprite):
		var opp_lane: ActionButton3D.Lane = g._enc_to_lane(pos_opp_vis)
		var op: Vector3 = g.opponent_sprite.global_position
		op.x = float(g._lane_x.get(opp_lane, 0.0))
		g.opponent_sprite.global_position = op

	# Enemy target world must be on OUR plane (Z = player Z)
	g._opp_target_world = Vector3.ZERO
	g._opp_target_lane = ActionButton3D.Lane.CENTER
	if target_opp != -1 and is_instance_valid(g.player):
		g._opp_target_lane = g._enc_to_lane(target_opp)
		var tx: float = float(g._lane_x.get(g._opp_target_lane, 0.0))
		g._opp_target_world = Vector3(tx, g.player.global_position.y + 0.7, g.player.global_position.z)
		g._update_opponent_sprite_pose_for_shot()

	# Preselect my prior shoot (optional convenience)
	g._selected_shoot = null
	g._require_new_shoot_selection = true
	if target_me != -1:
		var my_t_lane: ActionButton3D.Lane = g._enc_to_lane(target_me)
		var btn: ActionButton3D = g._shoot_btn_by_lane.get(my_t_lane, null)
		if is_instance_valid(btn):
			g._selected_shoot = btn
			g._require_new_shoot_selection = false

	print("[DBG][REPLAY_APPLY] pnum=", g.playernum,
		" pos_me=", pos_me,
		" pos_opp=", pos_opp,
		" tgt_opp=", target_opp,
		" pending_enemy=", g._pending_enemy_shot,
		" me_lane=", int(g._player_lane)
	)

func prime_autoplay_if_loaded_segment_ready() -> void:
	if g._replay_segments.size() <= 0:
		return

	# Always look at the FRONT of the queue
	var cur_state: Dictionary = parse_replay_state(String(g._replay_segments[0]))

	# Only autoplay if this segment is a complete round (both players pos+target)
	if not state_has_both_players_ready(cur_state):
		return

	g._is_replay_playback = true
	g._replay_auto_full_str = "|".join(g._replay_segments)
	g._replay_auto_pending = true

	# Prevent double-fire on same exact queue string
	if g._replay_auto_full_str == g._last_autoplayed_replay_str:
		g._replay_auto_pending = false
		return

	g._last_autoplayed_replay_str = g._replay_auto_full_str

	# Apply this segment so the round plays with correct lanes/targets
	apply_loaded_replay_segment(cur_state)

	# Defer into game wrapper so we don’t need Node methods in RefCounted
	g.call_deferred("_replay_autoplay_round")

func autoplay_replay_round() -> void:
	if not g._replay_auto_pending:
		return
	if g._round_sequence_running or g._is_shot_sequence_running:
		return
	if g._replay_segments.size() <= 0:
		g._replay_auto_pending = false
		return

	g._replay_auto_pending = false

	g._set_all_buttons_clickable(false)

	# Force the round path (same as if opponent data is ready)
	g._replay_is_autoplay_round = true
	g._pending_enemy_shot = true
	g._is_replay_playback = true

	# This will run the full cinematic + shots
	g.play_round()
	
func debug_dump_replay_queue(tag: String) -> void:
	print("[DBG][REPLAY_QUEUE][", tag, "] segs=", g._replay_segments.size(),
		" last_replay_len=", g._last_replay_str.length(),
		" is_replay_playback=", g._is_replay_playback,
		" auto_pending=", g._replay_auto_pending
	)

	if g._replay_segments.size() <= 0:
		print("[DBG][REPLAY_QUEUE][", tag, "] (empty)")
		return

	var head: String = String(g._replay_segments[0])
	var head_state: Dictionary = parse_replay_state(head)
	print("[DBG][REPLAY_QUEUE][", tag, "] head=", head)
	print("[DBG][REPLAY_QUEUE][", tag, "] head_state=", head_state,
		" head_full=", replay_is_full_round(head_state)
	)

	if g._replay_segments.size() > 1:
		var nxt: String = String(g._replay_segments[1])
		var nxt_state: Dictionary = parse_replay_state(nxt)
		print("[DBG][REPLAY_QUEUE][", tag, "] next=", nxt)
		print("[DBG][REPLAY_QUEUE][", tag, "] next_state=", nxt_state,
			" next_full=", replay_is_full_round(nxt_state)
		)


func on_round_finished_pop_autoplayed_head_and_chain() -> void:
	print("[DBG][REPLAY_POPCHAIN] enter")
	debug_dump_replay_queue("POPCHAIN_ENTER")

	if g._replay_segments.size() <= 0:
		print("[DBG][REPLAY_POPCHAIN] no segs, exit")
		return

	var head_state: Dictionary = get_head_state()
	var head_full: bool = (not head_state.is_empty() and replay_is_full_round(head_state))

	# If we were in replay playback and head was full, consume it
	if g._is_replay_playback and head_full:
		print("[DBG][REPLAY_POPCHAIN] popping full head")
		pop_head_segment()
		rebuild_last_replay_str_from_segments()
	else:
		print("[DBG][REPLAY_POPCHAIN] not popping (is_replay_playback=", g._is_replay_playback, " head_full=", head_full, ")")

	# Clear playback flags
	g._is_replay_playback = false
	g._replay_auto_pending = false

	# Apply the new head (if any) so pending_enemy_shot is correct for UI phase
	if g._replay_segments.size() > 0:
		var new_head: String = String(g._replay_segments[0])
		var new_state: Dictionary = parse_replay_state(new_head)
		var hp_now: Dictionary = hp_as_p1_order()
		new_state["hp1"] = int(hp_now.get("hp1", 3))
		new_state["hp2"] = int(hp_now.get("hp2", 3))

		print("[DBG][REPLAY_POPCHAIN] applying new head=", new_head, " with forced hp1/hp2=", new_state["hp1"], "/", new_state["hp2"])
		g._apply_loaded_replay_segment(new_state)
	else:
		print("[DBG][REPLAY_POPCHAIN] queue empty after pop")

	debug_dump_replay_queue("POPCHAIN_AFTER_APPLY")

	# Chain next autoplay if the new head is full
	queue_autoplay_if_head_full()

func get_head_state() -> Dictionary:
	if g._replay_segments.size() <= 0:
		return {}
	return parse_replay_state(String(g._replay_segments[0]))

func pop_head_segment() -> void:
	if g._replay_segments.size() <= 0:
		return
	g._replay_segments.remove_at(0)

func rebuild_last_replay_str_from_segments() -> void:
	if g._replay_segments.size() <= 0:
		g._last_replay_str = ""
		return
	g._last_replay_str = "|".join(g._replay_segments)

func queue_autoplay_if_head_full() -> void:
	if g._replay_segments.size() <= 0:
		print("[DBG][REPLAY_AUTO] no segs to autoplay")
		return

	var head_seg: String = String(g._replay_segments[0])
	var head_state: Dictionary = parse_replay_state(head_seg)

	print("[DBG][REPLAY_AUTO] check head_full=", replay_is_full_round(head_state),
		" head=", head_seg
	)

	if replay_is_full_round(head_state):
		# This sets flags and calls deferred autoplay round
		g._replay_seg_index = 0
		g._replay_base_state = head_state
		g._apply_loaded_replay_segment(head_state)
		prime_autoplay_if_loaded_segment_ready()
