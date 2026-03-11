extends RefCounted
class_name PB_Round

var g: PaintballGame

func setup(owner: PaintballGame) -> void:
	g = owner

func compute_zoom_target(camera: Camera3D, focus_world: Vector3) -> Transform3D:
	var start_xform: Transform3D = camera.global_transform
	var start_pos: Vector3 = start_xform.origin
	var to_focus: Vector3 = focus_world - start_pos
	var dist: float = maxf(to_focus.length(), 0.01)
	var target_dist: float = maxf(2.0, dist * 0.75)
	var forward: Vector3 = -start_xform.basis.z.normalized()
	var up: Vector3 = start_xform.basis.y.normalized()
	var target_pos: Vector3 = focus_world - forward * target_dist + up * 0.6
	var target_xform: Transform3D = start_xform
	target_xform.origin = target_pos
	return target_xform

func update_opponent_sprite_pose_for_shot() -> void:
	if not is_instance_valid(g.opponent_sprite):
		return

	if not is_instance_valid(g.player):
		g.opponent_sprite.texture = g.OPPONENT_FACING_TEX
		g.opponent_sprite.flip_h = false
		return

	if g._opp_target_enc_vis == -1:
		g.opponent_sprite.texture = g.OPPONENT_FACING_TEX
		g.opponent_sprite.flip_h = false
		return

	var tgt_lane_vis: ActionButton3D.Lane = g._enc_to_lane(g._opp_target_enc_vis)

	# FACE only if target is OUR lane, otherwise SIDE
	if tgt_lane_vis == g._player_lane:
		g.opponent_sprite.texture = g.OPPONENT_FACING_TEX
		g.opponent_sprite.flip_h = false
		return

	g.opponent_sprite.texture = g.OPPONENT_SIDE_TEX

	# Flip side asset based on which way they're aiming relative to us
	var delta: int = int(tgt_lane_vis) - int(g._player_lane)
	g.opponent_sprite.flip_h = (delta > 0)

func reveal_opponent_sprite() -> void:
	if not is_instance_valid(g.opponent_sprite):
		return

	g._opp_reveal_lane = _nearest_lane_from_x(g.opponent_sprite.global_position.x)
	print("[OPP] Reveal start. Opp lane=", g._opp_reveal_lane, " opp_x=", g.opponent_sprite.global_position.x)

	var start_pos: Vector3 = g.opponent_sprite.global_position
	var end_pos: Vector3 = start_pos + Vector3(0.0, absf(g._opp_sprite_reveal_offset_y), 0.0)

	var t: Tween = g.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(g.opponent_sprite, "global_position", end_pos, 0.28)

func _nearest_lane_from_x(x: float) -> ActionButton3D.Lane:
	var best_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
	var best_d: float = INF

	for ln in [ActionButton3D.Lane.LEFT, ActionButton3D.Lane.CENTER, ActionButton3D.Lane.RIGHT]:
		var lane_x: float = float(g._lane_x.get(ln, 0.0))
		var d: float = abs(x - lane_x)
		if d < best_d:
			best_d = d
			best_lane = ln

	return best_lane

func fade_out_selected_aim_target() -> void:
	if not is_instance_valid(g._selected_shoot):
		return

	var spr: Sprite3D = g._selected_shoot.get_node_or_null("Sprite3D") as Sprite3D
	if spr == null:
		return

	var t: Tween = g.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(spr, "modulate:a", 0.0, 0.18)
	t.tween_callback(func() -> void:
		if is_instance_valid(g._selected_shoot):
			g._selected_shoot.visible = false
	)

func restore_ui_after_round() -> void:
	print("[DBG][ROUND_RESTORE_UI] BEFORE restore",
		" pending_enemy=", g._pending_enemy_shot,
		" opp_pos_enc=", g._opp_pos_enc,
		" opp_target_enc=", g._opp_target_enc,
		" segs=", g._replay_segments.size(),
		" replay_playback=", g._is_replay_playback,
		" replay_auto_pending=", g._replay_auto_pending
	)

	if g.replay != null and g.replay.has_method("debug_dump_replay_queue"):
		g.replay.debug_dump_replay_queue("ROUND_RESTORE_UI_BEFORE")

	g._is_shot_sequence_running = false
	g._shot_in_progress = false
	g.ui.hide_player_hit_splat()
	g.ui.hide_opponent_hit_splat()
	(g.fire_button as Control).mouse_filter = Control.MOUSE_FILTER_STOP

	var ui_nodes: Array = [g.rules_button, g.settings_button, g.top_info]
	for n in ui_nodes:
		if is_instance_valid(n):
			n.visible = true
			n.modulate.a = 1.0

	g._show_fire_button(false)
	if is_instance_valid(g.fire_button):
		g.fire_button.modulate.a = 1.0
		g.fire_button.global_position = g._fire_btn_hidden_pos

	for b: ActionButton3D in g._buttons:
		if not is_instance_valid(b):
			continue

		b.visible = true
		b.set_click_enabled(true)

		var spr: Sprite3D = b.get_node_or_null("Sprite3D") as Sprite3D
		if spr != null:
			var c: Color = spr.modulate
			c.a = 1.0
			spr.modulate = c

		g._set_button_enabled(b, true)

	g._selected_shoot = null

	if is_instance_valid(g.player) and g.buttons != null:
		g._player_lane = g.buttons.lane_from_player_x()

	g._update_move_buttons()

	print("[DBG][ROUND_RESTORE_UI] AFTER restore",
		" pending_enemy=", g._pending_enemy_shot,
		" opp_pos_enc=", g._opp_pos_enc,
		" opp_target_enc=", g._opp_target_enc,
		" segs=", g._replay_segments.size()
	)

	if g.replay != null and g.replay.has_method("debug_dump_replay_queue"):
		g.replay.debug_dump_replay_queue("ROUND_RESTORE_UI_AFTER")

func end_round_fade_and_restore_next_round() -> void:
	if not is_instance_valid(g.fade_white) or not is_instance_valid(g.cam):
		return

	print("[DBG][ROUND_END] enter",
		" replay_playback=", g._is_replay_playback,
		" auto_pending=", g._replay_auto_pending,
		" segs=", g._replay_segments.size()
	)

	if g.replay != null and g.replay.has_method("debug_dump_replay_queue"):
		g.replay.debug_dump_replay_queue("ROUND_END_ENTER")

	print("[ROUND] Fade to white start")
	g.fade_white.visible = true

	var t_in: Tween = g.create_tween()
	t_in.tween_property(g.fade_white, "color:a", 1.0, g._round_end_white_in).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await t_in.finished
	print("[ROUND] White fully in")

	print("[ROUND] Restoring camera + UI (while white)")
	g.cam.fov = g._cam_start_fov
	g.cam.global_transform = g._cam_start_xform

	if is_instance_valid(g.opponent_sprite):
		g.opponent_sprite.global_position = g._opp_sprite_start_pos
		g.opponent_sprite.visible = false

	if is_instance_valid(g.fp_aim_sprite):
		g.fp_aim_sprite.visible = false

	if is_instance_valid(g.player):
		g.player.visible = true

	g._pending_enemy_shot = false
	g._opp_pos_enc = -1
	g._opp_target_enc = -1
	g._opp_target_lane = ActionButton3D.Lane.CENTER
	g._opp_target_world = Vector3.ZERO
	print("[ROUND] Cleared opponent move state (_pending_enemy_shot=false, enc=-1)")

	restore_ui_after_round()

	g._require_new_shoot_selection = true
	g._selected_shoot = null
	g._show_fire_button(false)
	if is_instance_valid(g.fire_button):
		g.fire_button.visible = false

	print("[ROUND] Holding white for 0.5s")
	await g.get_tree().create_timer(0.5).timeout

	# =========================================================================
	# MOVED LOGIC: Pop the replay chain and snap positions WHILE screen is white
	# =========================================================================
	print("[DBG][ROUND_END] before replay pop/chain",
		" replay_playback=", g._is_replay_playback,
		" auto_pending=", g._replay_auto_pending,
		" segs=", g._replay_segments.size()
	)
	if g.replay != null and g.replay.has_method("debug_dump_replay_queue"):
		g.replay.debug_dump_replay_queue("ROUND_END_BEFORE_POP")

	if g.replay != null and g.replay.has_method("on_round_finished_pop_autoplayed_head_and_chain"):
		g.replay.on_round_finished_pop_autoplayed_head_and_chain()

	print("[DBG][ROUND_END] after replay pop/chain",
		" replay_playback=", g._is_replay_playback,
		" auto_pending=", g._replay_auto_pending,
		" segs=", g._replay_segments.size(),
		" pending_enemy=", g._pending_enemy_shot,
		" opp_pos_enc=", g._opp_pos_enc,
		" opp_target_enc=", g._opp_target_enc
	)
	
	if g._replay_segments.size() == 0:
		g._is_replay_playback = false
		g._replay_auto_pending = false
		print("[ROUND_END] Replay chain empty. is_replay_playback set to FALSE.")
		
	if g.replay != null and g.replay.has_method("debug_dump_replay_queue"):
		g.replay.debug_dump_replay_queue("ROUND_END_AFTER_POP")
	# =========================================================================

	print("[ROUND] Fade out from white start")
	var t_out: Tween = g.create_tween()
	t_out.tween_property(g.fade_white, "color:a", 0.0, g._round_end_white_out).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await t_out.finished

	print("[ROUND] Fade out complete, next round ready")
	
func run_player_then_enemy_shot_sequence(player_target_world: Vector3) -> void:
	if g._round_sequence_running:
		print("[ROUND] Sequence already running, abort duplicate call.")
		return

	g._round_sequence_running = true
	g._is_shot_sequence_running = true

	var was_replay: bool = bool(g._is_replay_playback)
	var suppress_send: bool = bool(g._suppress_send_after_round)
	var shoot_for_send: ActionButton3D = g._selected_shoot


	print("[ROUND] ==============================")
	print("[ROUND] Sequence start")
	print("[ROUND] Player lane=", g._player_lane, " Selected shoot=", (g._selected_shoot.lane if g._selected_shoot != null else -1))
	print("[ROUND] Opponent target lane=", g._opp_target_lane, " Opponent target world=", g._opp_target_world)
	print("[ROUND] ==============================")

	print("[ROUND][PLAYER] Step 1: Prep opp splat target + fire yellow shot")

	var shot_target: Vector3 = player_target_world

	if g._opp_splat != null and is_instance_valid(g._opp_splat) and is_instance_valid(g.opponent_sprite):
		if g._opp_splat_tween and g._opp_splat_tween.is_valid():
			g._opp_splat_tween.kill()

		g._opp_splat.visible = false
		g._opp_splat.modulate.a = 0.0

		var splat_pos: Vector3 = Vector3(
			randf_range(-0.12, 0.12),
			1.5,
			-0.02
		)
		var splat_rot: Vector3 = Vector3(0.0, 0.0, deg_to_rad(randf_range(0.0, 360.0)))

		if g._opp_target_lane == ActionButton3D.Lane.CENTER:
			splat_pos.x = 0.0
		elif g._opp_target_lane == ActionButton3D.Lane.LEFT:
			splat_pos.x = -0.5
		elif g._opp_target_lane == ActionButton3D.Lane.RIGHT:
			splat_pos.x = 0.5

		g._opp_splat.position = splat_pos
		g._opp_splat.rotation = splat_rot
		g._opp_splat.scale = Vector3.ONE * 0.1

		var splat_world: Vector3 = g.opponent_sprite.to_global(g._opp_splat.position)
		shot_target.y = splat_world.y

		if is_instance_valid(g.opponent_sprite):
			shot_target.z = g.opponent_sprite.global_position.z

	var player_impact: Vector3 = await g.shots.fire_paintball_and_wait(shot_target, false)

	print("[ROUND][PLAYER] Step 2: Determine hit/miss")

	var opp_lane_for_hit: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
	if g._opp_pos_enc != -1:
		opp_lane_for_hit = g._enc_to_lane(g._opp_pos_enc)

	g._player_hit_last = (g._selected_shoot != null and is_instance_valid(g._selected_shoot) and g._selected_shoot.lane == opp_lane_for_hit)

	print("[HITCHECK][PLAYER] selected_lane=", (-1 if g._selected_shoot == null else int(g._selected_shoot.lane)),
		" opp_pos_enc=", g._opp_pos_enc,
		" opp_lane=", int(opp_lane_for_hit),
		" => hit=", g._player_hit_last)

	print("[ROUND][PLAYER] Result => hit=", g._player_hit_last)

	if g._player_hit_last:
		if g._opp_splat != null and is_instance_valid(g._opp_splat):
			if g._opp_splat_tween and g._opp_splat_tween.is_valid():
				g._opp_splat_tween.kill()

			g._opp_splat.visible = true
			g._opp_splat.modulate.a = 0.0

			g._opp_splat_tween = g.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			g._opp_splat_tween.tween_property(g._opp_splat, "modulate:a", 1.0, 0.10)

		g._hp_opp = clamp(g._hp_opp - 1, 0, 3)
		g._apply_hearts_from_hp()

	print("[ROUND][PLAYER] Step 3: Pause 1.0s before opponent returns fire")
	await g.get_tree().create_timer(1.0).timeout

	print("[ROUND][ENEMY] Step 4: Opponent recoil + fire red shot")
	await g.shots.play_opponent_recoil()

	# Determine hit/miss FIRST using RAW enc (logic)
	var my_hit_enc: int = g.states.lane_to_enc(g._player_lane)
	g._enemy_hit_last = (g._opp_target_enc == my_hit_enc)
	
	var visual_lane_for_shot: ActionButton3D.Lane = g.states.enc_to_lane(
		g.states.flip_enc_for_perspective(g._opp_target_enc)
	)

	# Base target (normal lane world)
	var enemy_target_world: Vector3 = g.get_world_for_player_lane(visual_lane_for_shot)
	if enemy_target_world == Vector3.ZERO:
		enemy_target_world = g._get_world_for_player_lane(g._opp_target_lane)

	# If it's a hit, aim at camera instead of lane point so splat reads correctly
	if g._enemy_hit_last and is_instance_valid(g.cam):
		var cam_pos: Vector3 = g.cam.global_transform.origin
		var cam_fwd: Vector3 = (-g.cam.global_transform.basis.z).normalized()

		# Put the target a little in front of the camera so projectile hits "screen" plane
		var hit_dist: float = 0.85
		var cam_target: Vector3 = cam_pos + cam_fwd * hit_dist

		# Tiny lane-based X offset so it still feels like it came from that lane
		var lane_x_offset: float = 0.0
		if g._player_lane == ActionButton3D.Lane.LEFT:
			lane_x_offset = -0.12
		elif g._player_lane == ActionButton3D.Lane.RIGHT:
			lane_x_offset = 0.12

		cam_target.x += lane_x_offset
		enemy_target_world = cam_target

	print("[ROUND][ENEMY] Target lane=", g._opp_target_lane,
		" raw_hit_enc=", my_hit_enc,
		" enemy_hit_last=", g._enemy_hit_last,
		" computed_target_world=", enemy_target_world
	)

	print("[ROUND][ENEMY] Step 5: Fire red shot and wait until it passes us")
	var _enemy_impact: Vector3 = await g.shots.fire_paintball_and_wait(enemy_target_world, true)

	print("[ROUND][ENEMY] Step 6: Determine hit/miss (already computed)")
	print("[HITCHECK][ENEMY] opp_target_enc=", g._opp_target_enc,
		" my_hit_enc=", my_hit_enc,
		" player_lane=", int(g._player_lane),
		" => hit=", g._enemy_hit_last
	)
	print("[ROUND][ENEMY] Result => hit=", g._enemy_hit_last)


	print("[HITCHECK][ENEMY] opp_target_enc=", g._opp_target_enc,
		" my_hit_enc=", my_hit_enc,
		" player_lane=", int(g._player_lane),
		" => hit=", g._enemy_hit_last
	)
	print("[ROUND][ENEMY] Result => hit=", g._enemy_hit_last)

	if g._enemy_hit_last:
		if g.ui != null:
			g.ui.show_player_hit_splat()


		g._hp_me = clamp(g._hp_me - 1, 0, 3)
		print("ME HP: ", g._hp_me, " | OPP HP: ", g._hp_opp, " Comment 4")
		g._apply_hearts_from_hp()

		print("[ROUND] Player was hit. Holding 2.0s before fade-to-white")
		_end_round_sequence()
		await g.get_tree().create_timer(2.0).timeout

	g.game_ended = g.check_win()
	if g.game_ended:
		print("End Valid")
		g.game_over = true
		if g.winner == "":
			g.send_game(true)
		return

	print("[ROUND] Step 7: End of round fade/restore")
	_end_round_sequence()
	await end_round_fade_and_restore_next_round()

	if not was_replay:
		g._selected_shoot = shoot_for_send
		g._require_new_shoot_selection = (g._selected_shoot == null)

		if suppress_send:
			print("[ROUND] Completed queued partial head. Not sending. Waiting for next selection.")
		else:
			print("[ROUND] Live turn complete. Sending new data to server.")
			g.send_game()
			g._selected_shoot = null
			g._require_new_shoot_selection = true

	if not was_replay:
		g._pending_enemy_shot = false
		g._opp_pos_enc = -1
		g._opp_target_enc = -1
		g._opp_target_world = Vector3.ZERO
		g._opp_target_lane = ActionButton3D.Lane.CENTER

	print("[ROUND] Sequence done")
	g._round_sequence_running = false
	g._is_shot_sequence_running = false
	
func _end_round_sequence() -> void:
	g._replay_auto_pending = false
	print("[ROUND] playback end (leaving is_replay_playback=", g._is_replay_playback, ")")

func play_round() -> void:
	if not g.is_my_turn or g._is_shot_sequence_running or g._round_sequence_running:
		print("[INPUT] Ignored play_round (not my turn or sequence running).")
		return

	if g._require_new_shoot_selection or g._selected_shoot == null or not is_instance_valid(g._selected_shoot):
		print("[PLAYROUND] Blocked: select a shoot target first.")
		return

	print("[DBG][PLAY_ROUND_ENTER] is_my_turn=", g.is_my_turn,
		" pending_enemy=", g._pending_enemy_shot,
		" my_lane=", int(g._player_lane),
		" selected=", (-1 if g._selected_shoot == null else int(g._selected_shoot.lane)),
		" replay_playback=", g._is_replay_playback,
		" round_seq=", g._round_sequence_running,
		" shot_seq=", g._is_shot_sequence_running
	)

	if not g._pending_enemy_shot:
		print("[PLAYROUND] Blocked: opponent shot not ready (this should be gated by _on_fire_pressed).")
		return

	print("[ROUND] play_round start. replay_playback=", g._is_replay_playback)

	# --- Cache player plane (authoritative for enemy shot) ---
	var player_plane_z: float = 0.0
	var player_plane_y: float = 0.0
	if is_instance_valid(g.player):
		player_plane_z = g.player.global_position.z
		player_plane_y = g.player.global_position.y

	# --- Place opponent by encoded lane (x only) ---
	if g._opp_pos_enc != -1 and is_instance_valid(g.opponent_sprite):
		var opp_lane: ActionButton3D.Lane = g._enc_to_lane(g._opp_pos_enc)

		var opp_x: float = float(g._lane_x.get(opp_lane, 0.0))
		var shoot_btn: ActionButton3D = g._shoot_btn_by_lane.get(opp_lane, null)
		if is_instance_valid(shoot_btn):
			opp_x = shoot_btn.global_position.x

		var op: Vector3 = g.opponent_sprite.global_position
		op.x = opp_x
		g.opponent_sprite.global_position = op

		print("[PLAYROUND] Opp pos enc=", g._opp_pos_enc,
			" => lane=", int(opp_lane),
			" set opp_x=", opp_x,
			" opp_z=", g.opponent_sprite.global_position.z
		)

	# --- Compute opponent target lane and world (Z MUST be player plane) ---
	g._opp_target_world = Vector3.ZERO
	g._opp_target_lane = ActionButton3D.Lane.CENTER

	if g._opp_target_enc_vis != -1:
		g._opp_target_lane = g._enc_to_lane(g._opp_target_enc_vis)

		# X: from the shoot lane button if possible, else lane_x
		var tx: float = float(g._lane_x.get(g._opp_target_lane, 0.0))
		var shoot_btn2: ActionButton3D = g._shoot_btn_by_lane.get(g._opp_target_lane, null)
		if is_instance_valid(shoot_btn2):
			tx = shoot_btn2.global_position.x

		# Y/Z: ALWAYS based on player plane so projectile plane reach matches visuals
		g._opp_target_world = Vector3(tx, player_plane_y + 0.7, player_plane_z)

		print("[PLAYROUND] Opp target enc(raw)=", g._opp_target_enc,
			" enc(vis)=", g._opp_target_enc_vis,
			" => lane=", int(g._opp_target_lane),
			" world=", g._opp_target_world,
			" player_plane_z=", player_plane_z
		)

		update_opponent_sprite_pose_for_shot()

	# --- Resolve camera ---
	var cam3d: Camera3D = null
	if is_instance_valid(g.cam):
		cam3d = g.cam
	else:
		cam3d = g.get_viewport().get_camera_3d()

	if not is_instance_valid(cam3d):
		_end_round_sequence()
		return

	# --- Begin cinematic state ---
	g._is_shot_sequence_running = true
	(g.fire_button as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	g._cam_start_fov = cam3d.fov
	g._cam_start_xform = cam3d.global_transform

	var focus_point: Vector3 = g.player.global_position + Vector3(0.0, 0.8, 0.0)
	var aim_point: Vector3 = g._selected_shoot.global_position + Vector3(0.0, 0.7, 0.0)
	g._aim_target_world = aim_point

	var dur_in: float = 1.10
	var hold_white: float = 1.00
	var dur_out: float = 0.65
	var dur_pan: float = 0.85
	var snap_offset_local: Vector3 = Vector3(0, 1.65, 2.10)
	var start_pitch_down_deg: float = 18.0
	var extra_pitch_down_deg: float = 20.0

	var target_fov: float = clampf(g._cam_start_fov * 0.35, 10.0, g._cam_start_fov)
	var punch_transform: Transform3D = compute_zoom_target(cam3d, focus_point)

	if is_instance_valid(g.fade_white):
		g.fade_white.top_level = true
		g.fade_white.z_as_relative = false
		g.fade_white.z_index = 10000
		g.fade_white.visible = true

	if is_instance_valid(g.fp_aim_sprite):
		g.fp_aim_sprite.top_level = false
		g.fp_aim_sprite.z_as_relative = false
		g.fp_aim_sprite.z_index = -10

	var t: Tween = g.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	t.tween_property(cam3d, "fov", target_fov, dur_in)
	t.parallel().tween_property(cam3d, "global_transform", punch_transform, dur_in)
	t.parallel().tween_property(g.fade_white, "color:a", 1.0, dur_in)

	var fade_out_nodes: Array = [g.rules_button, g.settings_button, g.fire_button, g.top_info, g.player_avatar_display, g.opp_avatar_display]
	for n in fade_out_nodes:
		if is_instance_valid(n) and n is CanvasItem:
			t.parallel().tween_property(n, "modulate:a", 0.0, dur_in)

	t.tween_callback(func() -> void:
		if is_instance_valid(g.player):
			g.player.visible = false
		if is_instance_valid(g.opponent_sprite):
			g.opponent_sprite.visible = true
			g.opponent_sprite.scale = g._opp_sprite_base_scale * 0.2

		if is_instance_valid(g.player_avatar_display) and g.player_avatar_display is CanvasItem:
			g.player_avatar_display.visible = true
			(g.player_avatar_display as CanvasItem).modulate.a = 0.0
		if is_instance_valid(g.opp_avatar_display) and g.opp_avatar_display is CanvasItem:
			g.opp_avatar_display.visible = true
			(g.opp_avatar_display as CanvasItem).modulate.a = 0.0
		if is_instance_valid(g.top_info) and g.top_info is CanvasItem:
			g.top_info.visible = true
			(g.top_info as CanvasItem).modulate.a = 0.0

		if is_instance_valid(g.fp_aim_sprite):
			g.fp_aim_sprite.visible = true
			g.fp_aim_sprite.scale = g._fp_aim_base_scale * 0.85
			g._fp_aim_base_pos = Vector2(259, 1071)
			g._aim_target_world = aim_point
			g.fp_aim_sprite.position = g._fp_aim_base_pos

		for b: ActionButton3D in g._buttons:
			if not is_instance_valid(b):
				continue
			if b.kind == ActionButton3D.ButtonKind.MOVE:
				b.visible = false
				b.set_click_enabled(false)
			elif b.kind == ActionButton3D.ButtonKind.SHOOT:
				if b == g._selected_shoot:
					b.visible = true
					b.set_click_enabled(false)
				else:
					b.visible = false
					b.set_click_enabled(false)

		var hide_nodes: Array = [g.rules_button, g.settings_button, g.fire_button]
		for n2 in hide_nodes:
			if is_instance_valid(n2):
				n2.visible = false

		if is_instance_valid(g.player):
			var player_xform: Transform3D = g.player.global_transform
			var snap_pos: Vector3 = player_xform.origin + (player_xform.basis * snap_offset_local)

			var snap_basis: Basis = player_xform.basis
			snap_basis = snap_basis.rotated(snap_basis.x.normalized(), -deg_to_rad(start_pitch_down_deg))

			cam3d.global_transform = Transform3D(snap_basis, snap_pos)

		cam3d.fov = g._cam_start_fov
	)

	t.tween_interval(hold_white)
	t.tween_property(g.fade_white, "color:a", 0.0, dur_out)

	if is_instance_valid(g.player_avatar_display) and g.player_avatar_display is CanvasItem:
		t.parallel().tween_property(g.player_avatar_display, "modulate:a", 1.0, dur_out)
	if is_instance_valid(g.opp_avatar_display) and g.opp_avatar_display is CanvasItem:
		t.parallel().tween_property(g.opp_avatar_display, "modulate:a", 1.0, dur_out)
	if is_instance_valid(g.top_info) and g.top_info is CanvasItem:
		t.parallel().tween_property(g.top_info, "modulate:a", 1.0, dur_out)

	t.tween_callback(func() -> void:
		var cam_pos: Vector3 = cam3d.global_transform.origin

		var p: int = int(g._player_lane)
		var s: int = int(g._selected_shoot.lane)

		# Tune these
		var bias_same: float = -1.75
		var bias_cross: float = 3.75

		# Pick magnitude (0 when center lane or center shot)
		var mag: float = 0.0
		if p == int(ActionButton3D.Lane.LEFT):
			if s == int(ActionButton3D.Lane.LEFT):
				mag = bias_same
			elif s == int(ActionButton3D.Lane.RIGHT):
				mag = bias_cross
		elif p == int(ActionButton3D.Lane.RIGHT):
			if s == int(ActionButton3D.Lane.RIGHT):
				mag = bias_same
			elif s == int(ActionButton3D.Lane.LEFT):
				mag = bias_cross

		# Figure out which way "toward center" is in WORLD X
		# aim_point.x < 0 means aim is left, so toward center is +X
		# aim_point.x > 0 means aim is right, so toward center is -X
		var toward_center_world_sign: float = 0.0
		if absf(aim_point.x) > 0.001:
			toward_center_world_sign = -signf(aim_point.x)

		# Now determine whether positive cam_right moves world +X or world -X
		var cam_right: Vector3 = cam3d.global_transform.basis.x.normalized()
		var cam_right_world_x: float = cam_right.dot(Vector3(1.0, 0.0, 0.0))
		var cam_right_x_sign: float = 1.0
		if absf(cam_right_world_x) > 0.001:
			cam_right_x_sign = signf(cam_right_world_x)

		# Final scalar along cam_right that always nudges toward world center
		var aim_bias: float = mag * toward_center_world_sign * cam_right_x_sign

		var biased_aim_point: Vector3 = aim_point + (cam_right * aim_bias)

		print("[DBG][AIM_BIAS2] aim_x=", aim_point.x,
			" mag=", mag,
			" toward_center_world_sign=", toward_center_world_sign,
			" cam_right=", cam_right,
			" cam_right_world_x=", cam_right_world_x,
			" aim_bias=", aim_bias
		)

		var look_xform: Transform3D = Transform3D().looking_at(biased_aim_point, Vector3.UP)
		look_xform.origin = cam_pos

		var b: Basis = look_xform.basis
		b = b.rotated(b.x.normalized(), -deg_to_rad(extra_pitch_down_deg))

		var end_xform: Transform3D = Transform3D(b, cam_pos)

		var pan: Tween = g.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		pan.tween_property(cam3d, "global_transform", end_xform, dur_pan)

		pan.finished.connect(func() -> void:
			g._shot_in_progress = true
			reveal_opponent_sprite()

			var seq: Tween = g.create_tween()
			seq.tween_interval(0.5)
			seq.tween_callback(func() -> void:
				fade_out_selected_aim_target()
				if g.shots != null and g.shots.has_method("play_fp_recoil"):
					g.shots.call("play_fp_recoil")
				elif g.has_method("_play_fp_recoil"):
					g.call("_play_fp_recoil")

				run_player_then_enemy_shot_sequence(aim_point)
			)
		)
)
