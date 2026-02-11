# res://paintball/modules/PB_Shots.gd
extends RefCounted
class_name PB_Shots

var g: PaintballGame

func setup(owner: PaintballGame) -> void:
	g = owner

func nearest_lane_from_x(x: float) -> ActionButton3D.Lane:
	var best_lane: ActionButton3D.Lane = ActionButton3D.Lane.CENTER
	var best_d: float = INF

	for ln: ActionButton3D.Lane in [
		ActionButton3D.Lane.LEFT,
		ActionButton3D.Lane.CENTER,
		ActionButton3D.Lane.RIGHT
	]:
		var lx: float = float(g._lane_x[ln])
		var d: float = abs(x - lx)
		if d < best_d:
			best_d = d
			best_lane = ln

	return best_lane

func get_world_for_player_lane(lane: ActionButton3D.Lane) -> Vector3:
	if not is_instance_valid(g.player):
		return Vector3.ZERO

	var p := g.player.global_position
	p.x = float(g._lane_x[lane])
	return p + Vector3(0.0, 0.85, 0.0)

func compute_player_hit_debug(impact_world: Vector3) -> bool:
	var impact_lane := nearest_lane_from_x(impact_world.x)
	var hit := (impact_lane == g._opp_reveal_lane)

	print("[HITCHECK][PLAYER] impact_x=", impact_world.x, " impact_lane=", impact_lane, " opp_reveal_lane=", g._opp_reveal_lane, " => hit=", hit)
	return hit

func get_muzzle_screen_pos() -> Vector2:
	if not is_instance_valid(g.fp_aim_sprite):
		return Vector2.ZERO
	if g.fp_aim_sprite.texture == null:
		return g.fp_aim_sprite.global_position

	var tex_size := g.fp_aim_sprite.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return g.fp_aim_sprite.global_position

	var drawn_size := Vector2(tex_size.x * g.fp_aim_sprite.scale.x, tex_size.y * g.fp_aim_sprite.scale.y)

	var sx := drawn_size.x / tex_size.x
	var sy := drawn_size.y / tex_size.y
	var muzzle_local := Vector2(g._muzzle_tex_px.x * sx, g._muzzle_tex_px.y * sy)

	if g.fp_aim_sprite.centered:
		muzzle_local -= drawn_size * 0.5

	return g.fp_aim_sprite.global_position + muzzle_local.rotated(g.fp_aim_sprite.global_rotation)

func fire_paintball_and_wait(target_world: Vector3, is_enemy: bool, on_reached: Callable = Callable()) -> Vector3:
	if not is_instance_valid(g.cam):
		print("[SHOT] ERROR: cam invalid, cannot fire.")
		return Vector3.ZERO

	var ball := g.PAINTBALL_SCENE.instantiate() as PaintballProjectile
	if ball == null:
		print("[SHOT] ERROR: projectile instantiate failed.")
		return Vector3.ZERO

	var muzzle_world: Vector3
	var target_fixed := target_world

	if is_enemy and is_instance_valid(g.opponent_sprite):
		muzzle_world = g.opponent_sprite.global_position + Vector3(0.0, 0.9, 0.0)

		var cam_pos := g.cam.global_transform.origin
		muzzle_world.y = cam_pos.y
		target_fixed.y = cam_pos.y
		target_fixed.z = cam_pos.z

		if is_equal_approx(muzzle_world.z, target_fixed.z):
			target_fixed.z += 0.05
	else:
		var muzzle_screen := get_muzzle_screen_pos()

		var ray_origin := g.cam.project_ray_origin(muzzle_screen)
		var ray_dir := g.cam.project_ray_normal(muzzle_screen).normalized()

		var tt := (target_fixed - ray_origin).dot(ray_dir)
		tt = maxf(tt, 0.35)
		muzzle_world = ray_origin + ray_dir * tt

		if is_instance_valid(g.opponent_sprite):
			target_fixed.z = g.opponent_sprite.global_position.z

	ball.scale = Vector3.ONE * g._paintball_scale
	ball.speed = (g.ball_speed * 2.25) if is_enemy else g.ball_speed
	ball.use_plane_z = true

	if is_enemy:
		if is_instance_valid(g.player):
			ball.hit_plane_z = g.player.global_position.z
		else:
			ball.use_plane_z = false
	else:
		if is_instance_valid(g.opponent_sprite):
			ball.hit_plane_z = g.opponent_sprite.global_position.z
		else:
			ball.use_plane_z = false

	var desired_color: Color
	if is_enemy:
		desired_color = Color(0.9, 0.15, 0.15)
	else:
		desired_color = Color(1.0, 0.95, 0.2)

	ball.set_ball_color(desired_color)

	var mi := ball.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi == null:
		mi = ball.find_child("MeshInstance3D", true, false) as MeshInstance3D
	if mi != null:
		var mat := mi.material_override
		if mat == null:
			mat = StandardMaterial3D.new()
			mi.material_override = mat
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			sm.albedo_color = desired_color
			sm.emission_enabled = true
			sm.emission = desired_color * 0.35

	g.get_tree().current_scene.add_child(ball)

	print("[SHOT] launch is_enemy=", is_enemy, " muzzle=", muzzle_world, " target=", target_fixed, " plane_z=", ball.hit_plane_z)

	var box := {
		"got": false,
		"impact": Vector3.ZERO
	}

	ball.reached_plane.connect(func(world_pos: Vector3) -> void:
		if box["got"]:
			return

		if not is_enemy and is_instance_valid(ball):
			ball.visible = false
			ball.queue_free()

		if on_reached.is_valid():
			on_reached.call(world_pos)

		box["got"] = true
		box["impact"] = world_pos
	)

	ball.launch(muzzle_world, target_fixed)

	var timeout_s: float = 3.0
	var start_ms: int = Time.get_ticks_msec()

	while not box["got"]:
		await g.get_tree().process_frame
		var elapsed_s: float = float(Time.get_ticks_msec() - start_ms) / 1000.0
		if elapsed_s >= timeout_s:
			break

	if not box["got"]:
		print("[SHOT] WARNING: reached_plane timeout after ", timeout_s, "s. Forcing impact.")
		box["impact"] = target_fixed

	var impact_world: Vector3 = box["impact"]

	await g.get_tree().process_frame

	if is_enemy and is_instance_valid(ball):
		ball.queue_free()

	return impact_world

func aim_gun_sprite_at_world_point(
	camera: Camera3D,
	sprite: Sprite2D,
	target_world: Vector3,
	delta: float,
	max_rot_deg: float = 6.0,
	rot_lerp_speed: float = 10.0,
	max_pos_px: float = 24.0,
	pos_lerp_speed: float = 10.0
) -> void:
	var viewport := camera.get_viewport()
	if viewport == null:
		return
	if sprite.texture == null:
		return

	var target_screen := camera.unproject_position(target_world)

	var tex_size := sprite.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return

	var drawn_size := Vector2(tex_size.x * sprite.scale.x, tex_size.y * sprite.scale.y)
	var sx := drawn_size.x / tex_size.x
	var sy := drawn_size.y / tex_size.y

	var tex_px_to_screen := func(tex_px: Vector2) -> Vector2:
		var local := Vector2(tex_px.x * sx, tex_px.y * sy)
		if sprite.centered:
			local -= drawn_size * 0.5
		return sprite.global_position + local.rotated(sprite.global_rotation)

	var rear_tex_px := Vector2(570.0, 470.0)
	var muzzle_tex_px := g._muzzle_tex_px
	var rear_screen: Vector2 = tex_px_to_screen.call(rear_tex_px)
	var muzzle_screen: Vector2 = tex_px_to_screen.call(muzzle_tex_px)
	var cur_dir := (muzzle_screen - rear_screen)
	var des_dir := (target_screen - rear_screen)

	if cur_dir.length_squared() < 0.00001 or des_dir.length_squared() < 0.00001:
		return

	var cur_ang := cur_dir.angle()
	var des_ang := des_dir.angle()
	var delta_ang := wrapf(des_ang - cur_ang, -PI, PI)

	var max_step := deg_to_rad(max_rot_deg)
	delta_ang = clampf(delta_ang, -max_step, max_step)

	var target_rot := sprite.rotation + delta_ang
	sprite.rotation = lerp(sprite.rotation, target_rot, delta * rot_lerp_speed)

	var screen_center := viewport.get_visible_rect().size * 0.5
	var px_delta := target_screen - screen_center

	var nx: float = 0.0
	var ny: float = 0.0
	if screen_center.x > 0.0:
		nx = px_delta.x / screen_center.x
	if screen_center.y > 0.0:
		ny = px_delta.y / screen_center.y

	nx = clampf(nx, -1.0, 1.0)
	ny = clampf(ny, -1.0, 1.0)

	var target_pos := g._fp_aim_base_pos + Vector2(nx * max_pos_px, ny * (max_pos_px * 0.6))
	sprite.position = sprite.position.lerp(target_pos, delta * pos_lerp_speed)

func play_fp_recoil() -> void:
	if not is_instance_valid(g.fp_aim_sprite):
		return

	var base := g.fp_aim_sprite.position
	var kick := Vector2(18.0, 22.0)

	var t := g.create_tween()
	t.tween_property(g.fp_aim_sprite, "position", base + kick, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(g.fp_aim_sprite, "position", base, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func play_opponent_recoil() -> void:
	if not is_instance_valid(g.opponent_sprite):
		return

	var start := g.opponent_sprite.global_position
	var kick := start + Vector3(0.0, 0.0, -g._opp_recoil_z)

	var t := g.create_tween()
	t.tween_property(g.opponent_sprite, "global_position", kick, g._opp_recoil_in_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(g.opponent_sprite, "global_position", start, g._opp_recoil_out_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await t.finished
