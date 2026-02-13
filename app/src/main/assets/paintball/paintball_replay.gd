# res://paintball/paintball_replay.gd
extends RefCounted
class_name PB_Replay

var g: PaintballGame

func setup(owner: PaintballGame) -> void:
	g = owner

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

func replay_build_after_my_fire(my_pos_int: int, my_target_int: int) -> String:
	var segs: PackedStringArray = PackedStringArray()
	if g._last_replay_str != "":
		segs = g._last_replay_str.split("|", false)

	var hp := hp_as_p1_order()
	var myk := my_replay_keys()

	if segs.size() == 0:
		segs.append("hp1:%d,hp2:%d,pos1:-1,pos2:-1,target1:-1,target2:-1" % [int(hp["hp1"]), int(hp["hp2"])])

	var last_i := segs.size() - 1
	var last_state := parse_replay_state(segs[last_i])

	last_state["hp1"] = int(hp["hp1"])
	last_state["hp2"] = int(hp["hp2"])

	var my_target_missing := int(last_state.get(myk["target"], -1)) == -1

	if my_target_missing:
		last_state[myk["pos"]] = my_pos_int
		last_state[myk["target"]] = my_target_int
		segs[last_i] = state_to_replay_string(last_state)
		segs = replay_trim_to_sliding_window(segs)
		return "|".join(segs)

	var next_state := last_state.duplicate(true)
	next_state["hp1"] = int(hp["hp1"])
	next_state["hp2"] = int(hp["hp2"])
	next_state["target1"] = -1
	next_state["target2"] = -1
	next_state[myk["pos"]] = my_pos_int
	next_state[myk["target"]] = my_target_int

	segs.append(state_to_replay_string(next_state))
	segs = replay_trim_to_sliding_window(segs)
	return "|".join(segs)

func apply_loaded_replay_segment(seg_state: Dictionary) -> void:
	var pos1: int = int(seg_state.get("pos1", -1))
	var pos2: int = int(seg_state.get("pos2", -1))
	var target1: int = int(seg_state.get("target1", -1))
	var target2: int = int(seg_state.get("target2", -1))

	var pos_me: int = (pos1 if g.playernum == 1 else pos2)
	var pos_opp: int = (pos2 if g.playernum == 1 else pos1)
	var target_me: int = (target1 if g.playernum == 1 else target2)
	var target_opp: int = (target2 if g.playernum == 1 else target1)

	g._opp_pos_enc = pos_opp
	g._opp_target_enc = target_opp
	g._pending_enemy_shot = (pos_opp != -1 and target_opp != -1)

	if pos_me != -1 and is_instance_valid(g.player):
		g._player_lane = g._enc_to_lane(pos_me)
		var pp := g.player.global_position
		pp.x = float(g._lane_x[g._player_lane])
		g.player.global_position = pp

	if pos_opp != -1 and is_instance_valid(g.opponent_sprite):
		var opp_lane: ActionButton3D.Lane = g._enc_to_lane(pos_opp)
		var op := g.opponent_sprite.global_position
		op.x = float(g._lane_x[opp_lane])
		g.opponent_sprite.global_position = op

	g._opp_target_world = Vector3.ZERO
	g._opp_target_lane = ActionButton3D.Lane.CENTER
	if target_opp != -1:
		g._opp_target_lane = g._enc_to_lane(target_opp)
		var tx: float = float(g._lane_x[g._opp_target_lane])
		g._opp_target_world = Vector3(tx, g.player.global_position.y + 0.7, g.player.global_position.z)
		g._update_opponent_sprite_pose_for_shot()

	g._selected_shoot = null
	g._require_new_shoot_selection = true
	if target_me != -1:
		var my_t_lane: ActionButton3D.Lane = g._enc_to_lane(target_me)
		g._selected_shoot = g._shoot_btn_by_lane.get(my_t_lane, null)
		if g._selected_shoot != null:
			g._require_new_shoot_selection = false

func prime_autoplay_if_loaded_segment_ready() -> void:
	if g._replay_segments.size() <= 0:
		return

	var cur_state := parse_replay_state(g._replay_segments[g._replay_seg_index])

	if not state_has_both_players_ready(cur_state):
		return

	g._is_replay_playback = true

	if g._replay_seg_index < g._replay_segments.size() - 1:
		var next_state := parse_replay_state(g._replay_segments[g._replay_seg_index + 1])
		g._replay_auto_end_state = next_state
		g._replay_seg_index += 1
	else:
		g._replay_auto_end_state = cur_state

	g._replay_auto_full_str = "|".join(g._replay_segments)
	g._replay_auto_pending = true
	g.call_deferred("_autoplay_replay_round")

func autoplay_replay_round() -> void:
	if not g._replay_auto_pending:
		return
	if g._round_sequence_running or g._is_shot_sequence_running:
		return

	g._replay_auto_pending = false

	if g._replay_auto_full_str != "" and g._replay_auto_full_str == g._last_autoplayed_replay_str:
		return
	g._last_autoplayed_replay_str = g._replay_auto_full_str

	g._set_all_buttons_clickable(false)

	g._pending_enemy_shot = true
	g._is_replay_playback = true

	g.play_round()
