# res://paintball/paintball_shots.gd
extends RefCounted
class_name PB_Shots

var g: PaintballGame

func setup(owner: PaintballGame) -> void:
	g = owner

func tick(delta: float) -> void:
	tick_aim(delta)
	tick_debug_shot_guides()

# This is what paintball_game.gd should call from _process(delta)
func tick_aim(delta: float) -> void:
	if g == null:
		return
	if not is_instance_valid(g.cam):
		return
	if not is_instance_valid(g.fp_aim_sprite):
		return
	if not g.fp_aim_sprite.visible:
		return
	var aim_world: Vector3 = Vector3.ZERO

	if g._selected_shoot != null and is_instance_valid(g._selected_shoot):
		aim_world = g._selected_shoot.global_position + Vector3(0.0, 0.7, 0.0)
	elif g._aim_target_world != Vector3.ZERO:
		aim_world = g._aim_target_world
	else:
		return

	# Store if you rely on it elsewhere
	g._aim_target_world = aim_world
	
	aim_gun_sprite_at_world_point(
		g.cam,
		g.fp_aim_sprite,
		aim_world,
		delta
	)

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
	var impact_lane: ActionButton3D.Lane = nearest_lane_from_x(impact_world.x)
	var hit: bool = (impact_lane == g._opp_reveal_lane)

	print("[HITCHECK][PLAYER] impact_x=", impact_world.x, " impact_lane=", impact_lane, " opp_reveal_lane=", g._opp_reveal_lane, " => hit=", hit)
	return hit

func get_muzzle_screen_pos() -> Vector2:
	if not is_instance_valid(g.fp_aim_sprite):
		return Vector2.ZERO
	if g.fp_aim_sprite.texture == null:
		return g.fp_aim_sprite.global_position

	var tex_size: Vector2 = g.fp_aim_sprite.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return g.fp_aim_sprite.global_position

	var drawn_size := Vector2(tex_size.x * g.fp_aim_sprite.scale.x, tex_size.y * g.fp_aim_sprite.scale.y)
	var sx: float = drawn_size.x / tex_size.x
	var sy: float = drawn_size.y / tex_size.y

	var local := Vector2(g._muzzle_tex_px.x * sx, g._muzzle_tex_px.y * sy)
	if g.fp_aim_sprite.centered:
		local -= drawn_size * 0.5

	return g.fp_aim_sprite.to_global(local)

func fire_paintball_and_wait(target_world: Vector3, is_enemy: bool, on_reached: Callable = Callable()) -> Vector3:
	if not is_instance_valid(g.cam):
		print("[SHOT] ERROR: cam invalid, cannot fire.")
		return Vector3.ZERO

	var ball := g.PAINTBALL_SCENE.instantiate() as PaintballProjectile
	if ball == null:
		print("[SHOT] ERROR: projectile instantiate failed.")
		return Vector3.ZERO

	var muzzle_world: Vector3
	var target_fixed: Vector3 = target_world

	if is_enemy and is_instance_valid(g.opponent_sprite):
		muzzle_world = g.opponent_sprite.global_position + Vector3(0.0, 0.9, 0.0)

		var cam_pos: Vector3 = g.cam.global_transform.origin

		# Keep enemy shot on camera Y (your rule)
		muzzle_world.y = cam_pos.y
		target_fixed.y = cam_pos.y

		# IMPORTANT: keep target on the same Z plane the projectile will hit (player plane)
		if is_instance_valid(g.player):
			target_fixed.z = g.player.global_position.z

		# Safety: avoid zero-length forward
		if is_equal_approx(muzzle_world.z, target_fixed.z):
			target_fixed.z += 0.05
	else:
		var muzzle_screen: Vector2 = get_muzzle_screen_pos()

		var ray_origin: Vector3 = g.cam.project_ray_origin(muzzle_screen)
		var ray_dir: Vector3 = g.cam.project_ray_normal(muzzle_screen).normalized()

		var tt: float = (target_fixed - ray_origin).dot(ray_dir)
		tt = maxf(tt, 0.35)
		muzzle_world = ray_origin + ray_dir * tt
		
		# Debug: draw muzzle -> target line on screen
	if is_instance_valid(g.cam):
		var muzzle_screen_dbg: Vector2
		if is_enemy:
			muzzle_screen_dbg = g.cam.unproject_position(muzzle_world)
		else:
			muzzle_screen_dbg = get_muzzle_screen_pos()

		var target_screen_dbg: Vector2 = g.cam.unproject_position(target_fixed)
	
		if not is_enemy and is_instance_valid(g.opponent_sprite):
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

	var desired_color: Color = Color(0.9, 0.15, 0.15) if is_enemy else Color(1.0, 0.95, 0.2)
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

	var box: Dictionary = {
		"got": false,
		"impact": Vector3.ZERO
	}

	ball.reached_plane.connect(func(world_pos: Vector3) -> void:
		if bool(box["got"]):
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

	while not bool(box["got"]):
		await g.get_tree().process_frame
		var elapsed_s: float = float(Time.get_ticks_msec() - start_ms) / 1000.0
		if elapsed_s >= timeout_s:
			break

	if not bool(box["got"]):
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

	var target_screen: Vector2 = camera.unproject_position(target_world)

	var tex_size: Vector2 = sprite.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return

	var drawn_size := Vector2(tex_size.x * sprite.scale.x, tex_size.y * sprite.scale.y)
	var sx: float = drawn_size.x / tex_size.x
	var sy: float = drawn_size.y / tex_size.y

	var tex_px_to_screen := func(tex_px: Vector2) -> Vector2:
		var local := Vector2(tex_px.x * sx, tex_px.y * sy)
		if sprite.centered:
			local -= drawn_size * 0.5
		return sprite.global_position + local.rotated(sprite.global_rotation)

	var rear_tex_px := Vector2(570.0, 470.0)
	var muzzle_tex_px: Vector2 = g._muzzle_tex_px

	var rear_screen: Vector2 = tex_px_to_screen.call(rear_tex_px)
	var muzzle_screen: Vector2 = tex_px_to_screen.call(muzzle_tex_px)

	var cur_dir: Vector2 = (muzzle_screen - rear_screen)
	var des_dir: Vector2 = (target_screen - rear_screen)

	if cur_dir.length_squared() < 0.00001 or des_dir.length_squared() < 0.00001:
		return

	var cur_ang: float = cur_dir.angle()
	var des_ang: float = des_dir.angle()
	var delta_ang: float = wrapf(des_ang - cur_ang, -PI, PI)

	var max_step: float = deg_to_rad(max_rot_deg)
	delta_ang = clampf(delta_ang, -max_step, max_step)

	var target_rot: float = sprite.rotation + delta_ang
	sprite.rotation = lerp(sprite.rotation, target_rot, delta * rot_lerp_speed)
	print("[FP AIM] rot_deg=", rad_to_deg(sprite.rotation), " pos=", sprite.position)
	var screen_center: Vector2 = viewport.get_visible_rect().size * 0.5
	var px_delta: Vector2 = target_screen - screen_center

	var nx: float = 0.0
	var ny: float = 0.0
	if screen_center.x > 0.0:
		nx = px_delta.x / screen_center.x
	if screen_center.y > 0.0:
		ny = px_delta.y / screen_center.y

	nx = clampf(nx, -1.0, 1.0)
	ny = clampf(ny, -1.0, 1.0)

	var target_pos: Vector2 = g._fp_aim_base_pos + Vector2(nx * max_pos_px, ny * (max_pos_px * 0.6))
	sprite.position = sprite.position.lerp(target_pos, delta * pos_lerp_speed)

func play_fp_recoil() -> void:
	if not is_instance_valid(g.fp_aim_sprite):
		return

	var base: Vector2 = g.fp_aim_sprite.position
	var kick: Vector2 = Vector2(18.0, 22.0)

	var t := g.create_tween()
	t.tween_property(g.fp_aim_sprite, "position", base + kick, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(g.fp_aim_sprite, "position", base, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func play_opponent_recoil() -> void:
	if not is_instance_valid(g.opponent_sprite):
		return

	var start: Vector3 = g.opponent_sprite.global_position
	var kick: Vector3 = start + Vector3(0.0, 0.0, -g._opp_recoil_z)

	var t := g.create_tween()
	t.tween_property(g.opponent_sprite, "global_position", kick, g._opp_recoil_in_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(g.opponent_sprite, "global_position", start, g._opp_recoil_out_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await t.finished
 
#~~~~~~~~~~~~~~~~~~~~~~~~ DEBUG (REMOVE BEFORE PUBLISHING) ~~~~~~~~~~~~~~~~~~~~~~~~
var _dbg_enabled: bool = true

var _dbg_layer: CanvasLayer = null
var _dbg_overlay: PB_Shots_DebugOverlay = null

const _REAR_TEX_PX := Vector2(590.0, 500.0) # back of gun reference (tune as needed)

func _ensure_dbg_overlay() -> void:
	if not _dbg_enabled:
		return
	if g == null:
		return
	if _dbg_layer != null and is_instance_valid(_dbg_layer) and _dbg_overlay != null and is_instance_valid(_dbg_overlay):
		return

	var root: Node = g.get_tree().current_scene
	if root == null:
		return

	if _dbg_layer == null or not is_instance_valid(_dbg_layer):
		_dbg_layer = CanvasLayer.new()
		_dbg_layer.name = "PB_ShotDebugLayer"
		_dbg_layer.layer = 200 # above most UI; bump if needed
		root.add_child(_dbg_layer)

	if _dbg_overlay == null or not is_instance_valid(_dbg_overlay):
		_dbg_overlay = PB_Shots_DebugOverlay.new()
		_dbg_overlay.name = "PB_ShotDebugOverlay"
		_dbg_layer.add_child(_dbg_overlay)

func _tex_px_to_screen(sprite: Sprite2D, tex_px: Vector2) -> Vector2:
	if sprite.texture == null:
		return sprite.global_position

	var tex_size: Vector2 = sprite.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return sprite.global_position

	var drawn_size := Vector2(tex_size.x * sprite.scale.x, tex_size.y * sprite.scale.y)
	var sx: float = drawn_size.x / tex_size.x
	var sy: float = drawn_size.y / tex_size.y

	# local point in sprite space (same space rotation happens in)
	var local := Vector2(tex_px.x * sx, tex_px.y * sy)
	if sprite.centered:
		local -= drawn_size * 0.5

	# Let Godot handle rotation, scale, parenting, canvas transforms
	return sprite.to_global(local)

func _get_fp_endpoints_screen() -> Dictionary:
	var out := {"rear": Vector2.ZERO, "muzzle": Vector2.ZERO}

	if not is_instance_valid(g.fp_aim_sprite):
		return out
	if g.fp_aim_sprite.texture == null:
		return out

	out["rear"] = _tex_px_to_screen(g.fp_aim_sprite, _REAR_TEX_PX)
	out["muzzle"] = _tex_px_to_screen(g.fp_aim_sprite, g._muzzle_tex_px)
	return out

func tick_debug_shot_guides() -> void:
	if not _dbg_enabled:
		return
	if g == null:
		return
	if not is_instance_valid(g.cam):
		return
	if not is_instance_valid(g.fp_aim_sprite):
		return

	_ensure_dbg_overlay()
	if _dbg_overlay == null or not is_instance_valid(_dbg_overlay):
		return

	# If FP hidden, clear so it doesn't "stick"
	if not g.fp_aim_sprite.visible:
		#_dbg_overlay.clear()
		return

	var aim_world: Vector3 = g._aim_target_world
	if aim_world == Vector3.ZERO and g._selected_shoot != null and is_instance_valid(g._selected_shoot):
		aim_world = g._selected_shoot.global_position + Vector3(0.0, 0.7, 0.0)
	if aim_world == Vector3.ZERO:
		_dbg_overlay.clear()
		return

	var ends: Dictionary = _get_fp_endpoints_screen()
	var rear: Vector2 = ends["rear"]
	var muzzle: Vector2 = ends["muzzle"]

	var target_screen: Vector2 = g.cam.unproject_position(aim_world)

	# Draw rear->muzzle and muzzle->target
	_dbg_overlay.set_points(rear, muzzle, target_screen)

class PB_Shots_DebugOverlay:
	extends Control

	var _rear: Vector2 = Vector2.ZERO
	var _muzzle: Vector2 = Vector2.ZERO
	var _target: Vector2 = Vector2.ZERO
	var _has: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_level = true
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		z_as_relative = false
		z_index = 999999

	func set_points(rear: Vector2, muzzle: Vector2, target: Vector2) -> void:
		_rear = rear
		_muzzle = muzzle
		_target = target
		_has = true
		queue_redraw()

	func clear() -> void:
		_has = false
		queue_redraw()

	func _draw() -> void:
		if not _has:
			return

		# rear -> muzzle (gun direction)
		draw_line(_rear, _muzzle, Color(0.8, 0.8, 0.8, 1.0), 2.0, true)

		# muzzle -> target (shot guide)
		draw_line(_muzzle, _target, Color(1, 1, 1, 1), 2.0, true)

		# dots
		draw_circle(_rear, 6.0, Color(0.2, 0.6, 1.0, 1.0))   # rear (blue)
		draw_circle(_muzzle, 6.0, Color(0.2, 1.0, 0.2, 1.0)) # muzzle (green)
		draw_circle(_target, 6.0, Color(1.0, 0.2, 0.2, 1.0)) # target (red)

		# tiny centers
		draw_circle(_rear, 2.0, Color(0, 0, 0, 1))
		draw_circle(_muzzle, 2.0, Color(0, 0, 0, 1))
		draw_circle(_target, 2.0, Color(0, 0, 0, 1))
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
