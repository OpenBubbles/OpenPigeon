# res://paintball/modules/PB_Round.gd
extends RefCounted
class_name PB_Round

var g: PaintballGame

func setup(owner: PaintballGame) -> void:
	g = owner

func compute_zoom_target(camera: Camera3D, focus_world: Vector3) -> Transform3D:
	var start_xform := camera.global_transform
	var start_pos := start_xform.origin
	var to_focus := focus_world - start_pos
	var dist := maxf(to_focus.length(), 0.01)
	var target_dist := maxf(2.0, dist * 0.75)
	var forward := -start_xform.basis.z.normalized()
	var up := start_xform.basis.y.normalized()
	var target_pos := focus_world - forward * target_dist + up * 0.6
	var target_xform := start_xform
	target_xform.origin = target_pos
	return target_xform

func update_opponent_sprite_pose_for_shot() -> void:
	if not is_instance_valid(g.opponent_sprite):
		return

	if not is_instance_valid(g.player):
		g.opponent_sprite.texture = g.OPPONENT_FACING_TEX
		g.opponent_sprite.flip_h = false
		return

	var delta: int = int(g._opp_target_lane) - int(g._player_lane)

	if delta == 0:
		g.opponent_sprite.texture = g.OPPONENT_FACING_TEX
		g.opponent_sprite.flip_h = false
		return

	g.opponent_sprite.texture = g.OPPONENT_SIDE_TEX
	g.opponent_sprite.flip_h = (delta > 0)

func reveal_opponent_sprite() -> void:
	if not is_instance_valid(g.opponent_sprite):
		return

	g._opp_reveal_lane = g._nearest_lane_from_x(g.opponent_sprite.global_position.x)
	print("[OPP] Reveal start. Opp lane=", g._opp_reveal_lane, " opp_x=", g.opponent_sprite.global_position.x)

	var start_pos := g.opponent_sprite.global_position
	var end_pos := start_pos + Vector3(0.0, g._opp_sprite_reveal_offset_y, 0.0)

	var t := g.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(g.opponent_sprite, "global_position", end_pos, 0.28)

func fade_out_selected_aim_target() -> void:
	if not is_instance_valid(g._selected_shoot):
		return

	var spr := g._selected_shoot.get_node_or_null("Sprite3D") as Sprite3D
	if spr == null:
		return

	var t := g.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(spr, "modulate:a", 0.0, 0.18)
	t.tween_callback(func():
		if is_instance_valid(g._selected_shoot):
			g._selected_shoot.visible = false
	)

func restore_ui_after_round() -> void:
	g._is_shot_sequence_running = false
	g._shot_in_progress = false
	g._hide_player_hit_splat()
	g._hide_opponent_hit_splat()
	(g.fire_button as Control).mouse_filter = Control.MOUSE_FILTER_STOP

	var ui_nodes := [g.rules_button, g.settings_button, g.top_info]
	for n in ui_nodes:
		if is_instance_valid(n):
			n.visible = true
			n.modulate.a = 1.0

	g._show_fire_button(false)
	if is_instance_valid(g.fire_button):
		g.fire_button.modulate.a = 1.0
		g.fire_button.global_position = g._fire_btn_hidden_pos

	for b in g._buttons:
		if not is_instance_valid(b):
			continue

		b.visible = true
		b.set_click_enabled(true)

		var spr := b.get_node_or_null("Sprite3D") as Sprite3D
		if spr != null:
			var c := spr.modulate
			c.a = 1.0
			spr.modulate = c

		g._set_button_enabled(b, true)

	g._selected_shoot = null

	if is_instance_valid(g.player):
		g._player_lane = g._lane_from_player_x()

	g._update_move_buttons()

func end_round_fade_and_restore_next_round() -> void:
	if not is_instance_valid(g.fade_white) or not is_instance_valid(g.cam):
		return

 सुनिश्चित

	print("[ROUND] Fade to white start")
	g.fade_white.visible = true

	var t_in := g.create_tween()
	t_in.tween_property(g.fade_white, "color:a", 1.0, g._round_end_white_in).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await t_in.finished
	print("[ROUND] White fully in")

	print("[ROUND] Restoring camera + UI (while white)")
	g.cam.fov = g._cam_start_fov
	g.cam.global_transform = g._cam_start_xform

	if is_instance_valid(g.opponent_sprite):
		g.opponent_sprite.global_position = g._opp_sprite_start_pos

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

	if g._is_replay_playback:
		g._is_replay_playback = false

		if g._replay_auto_end_state.size() > 0:
			var end_state := g._replay_auto_end_state

			print("[REPLAY] end_state dict=", end_state)

			var hp1e: int = int(end_state.get("hp1", 3))
			var hp2e: int = int(end_state.get("hp2", 3))
			g._hp_me = clamp((hp1e if g.playernum == 1 else hp2e), 0, 3)
			g._hp_opp = clamp((hp2e if g.playernum == 1 else hp1e), 0, 3)
			print("ME HP: ", g._hp_me, " | OPP HP: ", g._hp_opp, " Comment 2")
			g._apply_hearts_from_hp()

			var pos1e: int = int(end_state.get("pos1", -1))
			var pos2e: int = int(end_state.get("pos2", -1))
			var t1e: int = int(end_state.get("target1", -1))
			var t2e: int = int(end_state.get("target2", -1))

			var opp_pos_e: int = (pos2e if g.playernum == 1 else pos1e)
			var opp_target_e: int = (t2e if g.playernum == 1 else t1e)

			g._opp_pos_enc = opp_pos_e
			g._opp_target_enc = opp_target_e
			g._pending_enemy_shot = (opp_pos_e != -1 and opp_target_e != -1)

			print("[REPLAY] carried forward next-round opp enc pos=", g._opp_pos_enc, " target=", g._opp_target_enc, " pending=", g._pending_enemy_shot)

			g._replay_auto_end_state = {}

		if g._replay_segments.size() > 0:
			var pending_seg := g._replay_segments[g._replay_segments.size() - 1]
			g._replay_segments = PackedStringArray([pending_seg])
			g._replay_seg_index = 0
			g._last_replay_str = pending_seg
		else:
			g._last_replay_str = ""

		g._replay_auto_full_str = ""

	print("[ROUND] Fade out from white start")
	var t_out := g.create_tween()
	t_out.tween_property(g.fade_white, "color:a", 0.0, g._round_end_white_out).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await t_out.finished

	print("[ROUND] Fade out complete, next round ready")

func run_player_then_enemy_shot_sequence(player_target_world: Vector3) -> void:
	if g._round_sequence_running:
		print("[ROUND] Sequence already running, abort duplicate call.")
		return

	g._round_sequence_running = true
	g._is_shot_sequence_running = true
	var was_replay := g._is_replay_playback
	var shoot_for_send := g._selected_shoot

	print("[ROUND] ==============================")
	print("[ROUND] Sequence start")
	print("[ROUND] Player lane=", g._player_lane, " Selected shoot=", (g._selected_shoot.lane if g._selected_shoot != null else -1))
	print("[ROUND] Opponent target lane=", g._opp_target_lane, " Opponent target world=", g._opp_target_world)
	print("[ROUND] ==============================")

	print("[ROUND][PLAYER] Step 1: Prep opp splat target + fire yellow shot")

	var shot_target := player_target_world

	if g._opp_splat != null and is_instance_valid(g._opp_splat) and is_instance_valid(g.opponent_sprite):
		if g._opp_splat_tween and g._opp_splat_tween.is_valid():
			g._opp_splat_tween.kill()

		g._opp_splat.visible = false
		g._opp_splat.modulate.a = 0.0

		var splat_pos := Vector3(
			randf_range(-0.12, 0.12),
			1.5,
			-0.02
		)
		var splat_rot := Vector3(0.0, 0.0, deg_to_rad(randf_range(0.0, 360.0)))

		if g._opp_target_lane == ActionButton3D.Lane.CENTER:
			splat_pos.x = 0.0
		elif g._opp_target_lane == ActionButton3D.Lane.LEFT:
			splat_pos.x = 0.5
		elif g._opp_target_lane == ActionButton3D.Lane.RIGHT:
			splat_pos.x = -0.5

		g._opp_splat.position = splat_pos
		g._opp_splat.rotation = splat_rot
		g._opp_splat.scale = Vector3.ONE * 0.1

		var splat_world: Vector3 = g.opponent_sprite.to_global(g._opp_splat.position)
		shot_target.y = splat_world.y

		if is_instance_valid(g.opponent_sprite):
			shot_target.z = g.opponent_sprite.global_position.z

	var player_impact := await g._fire_paintball_and_wait(shot_target, false)

	print("[ROUND][PLAYER] Step 2: Determine hit/miss")
	g._player_hit_last = g._compute_player_hit_debug(player_impact)
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
	g._play_opponent_recoil()

	var enemy_target_world := g._opp_target_world
	if enemy_target_world == Vector3.ZERO:
		enemy_target_world = g._get_world_for_player_lane(g._opp_target_lane)

	print("[ROUND][ENEMY] Target lane=", g._opp_target_lane, " computed_target_world=", enemy_target_world)

	print("[ROUND][ENEMY] Step 5: Fire red shot and wait until it passes us")
	var _enemy_impact := await g._fire_paintball_and_wait(enemy_target_world, true)

	print("[ROUND][ENEMY] Step 6: Determine hit/miss")
	g._enemy_hit_last = (g._opp_target_lane == g._player_lane)
	print("[HITCHECK][ENEMY] opp_target_lane=", g._opp_target_lane, " player_lane=", g._player_lane, " => hit=", g._enemy_hit_last)
	print("[ROUND][ENEMY] Result => hit=", g._enemy_hit_last)

	if g._enemy_hit_last:
		g._show_player_hit_splat()

		g._hp_me = clamp(g._hp_me - 1, 0, 3)
		print("ME HP: ", g._hp_me, " | OPP HP: ", g._hp_opp, " Comment 4")
		g._apply_hearts_from_hp()

		print("[ROUND] Player was hit. Holding 2.0s before fade-to-white")
		await g.get_tree().create_timer(2.0).timeout

	g.game_ended = g.check_win()
	if g.game_ended:
		print("End Valid")
		if not g._is_replay_playback:
			g.send_game()
		return

	print("[ROUND] Step 7: End of round fade/restore")
	await end_round_fade_and_restore_next_round()

	if not was_replay:
		g._selected_shoot = shoot_for_send
		g._require_new_shoot_selection = (g._selected_shoot == null)

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

func play_round() -> void:
	if not g.is_my_turn or g._is_shot_sequence_running or g._round_sequence_running:
		print("[INPUT] Ignored play_round (not my turn or sequence running).")
		return

	if g._require_new_shoot_selection or g._selected_shoot == null or not is_instance_valid(g._selected_shoot):
		print("[PLAYROUND] Blocked: select a shoot target first.")
		return
	g._dbg("PLAY_ROUND_ENTER")

	if not g._pending_enemy_shot:
		print("[PLAYROUND] Blocked: opponent shot not ready (this should be gated by _on_fire_pressed).")
		return

	if g._opp_pos_enc != -1 and is_instance_valid(g.opponent_sprite):
		var opp_lane: ActionButton3D.Lane = g._enc_to_lane(g._opp_pos_enc)

		var opp_x: float = float(g._lane_x[opp_lane])
		var shoot_btn: ActionButton3D = g._shoot_btn_by_lane.get(opp_lane, null)
		if is_instance_valid(shoot_btn):
			opp_x = shoot_btn.global_position.x

		var op := g.opponent_sprite.global_position
		op.x = opp_x
		g.opponent_sprite.global_position = op
		print("[PLAYROUND] Opp pos enc=", g._opp_pos_enc, " => lane=", opp_lane, " set opp_x=", opp_x)

	if g._opp_target_enc != -1:
		var flipped_enc: int = g._flip_enc_for_perspective(g._opp_target_enc)
		g._opp_target_lane = g._enc_to_lane(flipped_enc)

		var tgt_world: Vector3 = Vector3.ZERO
		var shoot_btn2: ActionButton3D = g._shoot_btn_by_lane.get(g._opp_target_lane, null)
		if is_instance_valid(shoot_btn2):
			tgt_world = shoot_btn2.global_position + Vector3(0.0, 0.7, 0.0)

		if tgt_world == Vector3.ZERO:
			var tx: float = float(g._lane_x[g._opp_target_lane])
			tgt_world = Vector3(tx, g.player.global_position.y + 0.7, g.player.global_position.z)

		g._opp_target_world = tgt_world
		print("[PLAYROUND] Opp target enc=", g._opp_target_enc, " => lane=", g._opp_target_lane, " world=", g._opp_target_world)
		update_opponent_sprite_pose_for_shot()

	var cam3d := g.get_viewport().get_camera_3d()
	if not cam3d:
		return

	g._is_shot_sequence_running = true
	(g.fire_button as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	g._cam_start_fov = cam3d.fov
	g._cam_start_xform = cam3d.global_transform

	var focus_point := g.player.global_position + Vector3(0.0, 0.8, 0.0)
	var aim_point := g._selected_shoot.global_position + Vector3(0.0, 0.7, 0.0)
	g._aim_target_world = aim_point

	var dur_in := 1.10
	var hold_white := 1.00
	var dur_out := 0.65
	var dur_pan := 0.85
	var snap_offset_local := Vector3(0, 1.65, 2.10)
	var start_pitch_down_deg := 18.0
	var extra_pitch_down_deg := 20.0

	var target_fov := clampf(g._cam_start_fov * 0.35, 10.0, g._cam_start_fov)
	var punch_transform := compute_zoom_target(cam3d, focus_point)

	if is_instance_valid(g.fade_white):
		g.fade_white.top_level = true
		g.fade_white.z_as_relative = false
		g.fade_white.z_index = 10000
		g.fade_white.visible = true

	if is_instance_valid(g.fp_aim_sprite):
		g.fp_aim_sprite.top_level = false
		g.fp_aim_sprite.z_as_relative = false
		g.fp_aim_sprite.z_index = -10

	var t := g.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	t.tween_property(cam3d, "fov", target_fov, dur_in)
	t.parallel().tween_property(cam3d, "global_transform", punch_transform, dur_in)
	t.parallel().tween_property(g.fade_white, "color:a", 1.0, dur_in)

	var fade_out_nodes := [g.rules_button, g.settings_button, g.fire_button, g.top_info, g.player_avatar_display, g.opp_avatar_display]
	for n in fade_out_nodes:
		if is_instance_valid(n) and n is CanvasItem:
			t.parallel().tween_property(n, "modulate:a", 0.0, dur_in)

	t.tween_callback(func() -> void:
		if is_instance_valid(g.player):
			g.player.visible = false
		if is_instance_valid(g.opponent_sprite):
			g.opponent_sprite.visible = true
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
			g._fp_aim_base_pos = Vector2(259, 1071)
			g.fp_aim_sprite.position = g._fp_aim_base_pos

		for b in g._buttons:
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

		var hide_nodes := [g.rules_button, g.settings_button, g.fire_button]
		for n in hide_nodes:
			if is_instance_valid(n):
				n.visible = false

		if is_instance_valid(g.player):
			var player_xform := g.player.global_transform
			var snap_pos := player_xform.origin + (player_xform.basis * snap_offset_local)

			var snap_basis := player_xform.basis
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
		var cam_pos := cam3d.global_transform.origin

		var aim_bias_x := 0.0
		if g._player_lane == ActionButton3D.Lane.LEFT and g._selected_shoot.lane == ActionButton3D.Lane.LEFT:
			aim_bias_x = 4
		elif g._player_lane == ActionButton3D.Lane.RIGHT and g._selected_shoot.lane == ActionButton3D.Lane.RIGHT:
			aim_bias_x = -4

		var biased_aim_point := aim_point + Vector3(aim_bias_x, 0.0, 0.0)

		var look_xform := Transform3D().looking_at(biased_aim_point, Vector3.UP)
		look_xform.origin = cam_pos

		var b := look_xform.basis
		b = b.rotated(b.x.normalized(), -deg_to_rad(extra_pitch_down_deg))

		var end_xform := Transform3D(b, cam_pos)

		var pan := g.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		pan.tween_property(cam3d, "global_transform", end_xform, dur_pan)

		pan.finished.connect(func() -> void:
			g._shot_in_progress = true
			print("[ROUND] Camera pan finished. Begin reveal + shot sequence")

			reveal_opponent_sprite()

			var seq := g.create_tween()
			seq.tween_interval(0.5)

			seq.tween_callback(func() -> void:
				print("[ROUND] Player firing moment reached (after 0.5s)")
				fade_out_selected_aim_target()
				g._play_fp_recoil()
				run_player_then_enemy_shot_sequence(aim_point)
			)
		)
	)
