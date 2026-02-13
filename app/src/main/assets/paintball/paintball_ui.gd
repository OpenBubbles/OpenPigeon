# res://paintball/paintball_ui.gd
extends RefCounted
class_name PB_UI

var g: PaintballGame

func setup(owner: PaintballGame) -> void:
	g = owner

func init_fire_button() -> void:
	await g.get_tree().process_frame
	await g.get_tree().process_frame

	g.fire_button.top_level = true
	g.fire_button.visible = true
	g.fire_button.reset_size()
	await g.get_tree().process_frame

	var vp := g.get_viewport().get_visible_rect().size
	var margin := 26.0
	var lift := 100.0

	g._fire_btn_shown_pos = Vector2(
		(vp.x - g.fire_button.size.x) * 0.5,
		vp.y - g.fire_button.size.y - margin - lift
	)

	g._fire_btn_hidden_pos = Vector2(g._fire_btn_shown_pos.x, vp.y + g.fire_button.size.y + 40.0)
	g.fire_button.modulate.a = 0.0
	g.fire_button.global_position = g._fire_btn_hidden_pos

func show_fire_button(should_show: bool) -> void:
	if should_show == g._fire_button_is_shown:
		return
	g.fire_button.visible = true
	g._fire_button_is_shown = should_show

	if g._fire_btn_tween and g._fire_btn_tween.is_valid():
		g._fire_btn_tween.kill()

	g._fire_btn_tween = g.create_tween()
	g._fire_btn_tween.set_trans(Tween.TRANS_SINE)
	g._fire_btn_tween.set_ease(Tween.EASE_OUT)

	if should_show:
		g.fire_button.top_level = true
		g.fire_button.global_position = g._fire_btn_hidden_pos
		g.fire_button.modulate.a = 0.0
		g.fire_button.visible = true

		g._fire_btn_tween.tween_property(g.fire_button, "global_position", g._fire_btn_shown_pos, 0.25)
		g._fire_btn_tween.parallel().tween_property(g.fire_button, "modulate:a", 1.0, 0.18)
	else:
		g._fire_btn_tween.tween_property(g.fire_button, "modulate:a", 0.0, 0.15)
		g._fire_btn_tween.tween_callback(func() -> void:
			g.fire_button.global_position = g._fire_btn_hidden_pos
		)

func apply_hearts_from_hp() -> void:
	var p_hearts := [g.pheart1, g.pheart2, g.pheart3]
	var o_hearts := [g.oheart1, g.oheart2, g.oheart3]

	for i in range(3):
		if is_instance_valid(p_hearts[i]):
			p_hearts[i].texture = (g.HEART_FULL_TEX if i < g._hp_me else g.HEART_VOID_TEX)
		if is_instance_valid(o_hearts[i]):
			o_hearts[i].texture = (g.HEART_FULL_TEX if i < g._hp_opp else g.HEART_VOID_TEX)

func init_player_splat_overlay() -> void:
	if g._player_splat != null and is_instance_valid(g._player_splat):
		return

	var attach_parent: Node = null

	if is_instance_valid(g.fp_aim_sprite):
		var parent: Node = g.fp_aim_sprite.get_parent()
		while parent != null and not (parent is CanvasLayer):
			parent = parent.get_parent()
		if parent != null and parent is CanvasLayer:
			attach_parent = parent
		else:
			attach_parent = g.fp_aim_sprite.get_parent()

	if attach_parent == null:
		attach_parent = g.get_tree().root

	g._player_splat = TextureRect.new()
	g._player_splat.name = "PlayerHitSplat"
	g._player_splat.texture = g.SPLAT_TEX
	g._player_splat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g._player_splat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g._player_splat.stretch_mode = TextureRect.STRETCH_SCALE
	g._player_splat.visible = false
	g._player_splat.modulate = Color(0.9, 0.15, 0.15, 0.0)
	g._player_splat.z_as_relative = false
	g._player_splat.z_index = 9000

	attach_parent.add_child(g._player_splat)

func show_player_hit_splat() -> void:
	if g._player_splat == null or not is_instance_valid(g._player_splat):
		return

	if g._player_splat_tween and g._player_splat_tween.is_valid():
		g._player_splat_tween.kill()

	var vp := g.get_viewport().get_visible_rect().size
	var center := vp * 0.5
	var base_w := vp.x * 0.78
	var base_h := vp.y * 0.58
	var w := base_w * randf_range(0.85, 1.10)
	var h := base_h * randf_range(0.85, 1.15)
	var off := Vector2(randf_range(-60.0, 60.0), randf_range(-90.0, 50.0))
	var pos := center + off

	g._player_splat.size = Vector2(w, h)
	g._player_splat.pivot_offset = g._player_splat.size * 0.5
	g._player_splat.position = pos - (g._player_splat.size * 0.5)
	g._player_splat.rotation = deg_to_rad(randf_range(0.0, 360.0))
	g._player_splat.scale = Vector2(0.18, 0.18)
	g._player_splat.modulate.a = 0.0
	g._player_splat.visible = true

	g._player_splat_tween = g.create_tween()
	g._player_splat_tween.set_trans(Tween.TRANS_BACK)
	g._player_splat_tween.set_ease(Tween.EASE_OUT)

	g._player_splat_tween.tween_property(g._player_splat, "modulate:a", 1.0, 0.08)
	g._player_splat_tween.parallel().tween_property(g._player_splat, "scale", Vector2.ONE, 0.18)

func hide_player_hit_splat() -> void:
	if g._player_splat == null or not is_instance_valid(g._player_splat):
		return

	if g._player_splat_tween and g._player_splat_tween.is_valid():
		g._player_splat_tween.kill()

	g._player_splat.visible = false
	g._player_splat.modulate.a = 0.0

func init_opponent_splat() -> void:
	if g._opp_splat != null and is_instance_valid(g._opp_splat):
		return
	if not is_instance_valid(g.opponent_sprite):
		return

	g._opp_splat = Sprite3D.new()
	g._opp_splat.name = "OppHitSplat"
	g._opp_splat.texture = g.SPLAT_TEX
	g._opp_splat.visible = false
	g._opp_splat.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g._opp_splat.render_priority = 10
	g._opp_splat.modulate = Color(1.0, 0.95, 0.2, 1.0)

	g.opponent_sprite.add_child(g._opp_splat)

func show_opponent_hit_splat() -> void:
	if g._opp_splat == null or not is_instance_valid(g._opp_splat):
		return

	if g._opp_splat_tween and g._opp_splat_tween.is_valid():
		g._opp_splat_tween.kill()

	g._opp_splat.visible = true
	g._opp_splat.modulate.a = 0.0
	g._opp_splat.position = Vector3(randf_range(-0.10, 0.10), 0.4, 0.03)
	g._opp_splat.rotation = Vector3(0.0, 0.0, deg_to_rad(randf_range(0.0, 360.0)))

	g._opp_splat_tween = g.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	g._opp_splat_tween.tween_property(g._opp_splat, "modulate:a", 1.0, 0.10)

func hide_opponent_hit_splat() -> void:
	if g._opp_splat == null or not is_instance_valid(g._opp_splat):
		return

	if g._opp_splat_tween and g._opp_splat_tween.is_valid():
		g._opp_splat_tween.kill()

	g._opp_splat.visible = false
	g._opp_splat.modulate.a = 0.0

func play_sent_animation() -> void:
	if not is_instance_valid(g.sent_label):
		print("Warning: sent_label is not valid for play_sent_animation.")
		return

	if g.sent_tween and g.sent_tween.is_running():
		g.sent_tween.kill()

	g.sent_tween = g.create_tween().set_parallel(false)

	g.sent_label.text = "Sent"
	g.sent_label.visible = true
	g.sent_label.modulate.a = 0.0
	g.sent_label.scale = Vector2.ONE
	g.sent_label.pivot_offset = g.sent_label.get_size() / 2.0

	g.sent_tween.tween_property(g.sent_label, "modulate:a", 1.0, 0.3)
	g.sent_tween.tween_interval(0.6)
	g.sent_tween.tween_callback(func():
		if is_instance_valid(g.sent_label):
			g.sent_label.text = "Sent ✔"
	)
	g.sent_tween.tween_interval(2.0)
	g.sent_tween.tween_property(g.sent_label, "modulate:a", 0.0, 0.5)

	g.sent_tween.tween_callback(func():
		if is_instance_valid(g.sent_label):
			g.sent_label.visible = false
			g.sent_label.modulate.a = 1.0
			start_waiting_animation()
	)

func start_waiting_animation() -> void:
	if not is_instance_valid(g.waiting_label) or not is_instance_valid(g.waiting_blur) or not is_instance_valid(g.dot_timer):
		print("Warning: Waiting animation nodes are not valid.")
		return
	if g.spectator_mode:
		return

	g.dot_count = 0
	g.waiting_label.text = g.BASE_WAIT_TEXT + "."
	g.waiting_label.visible = true
	g.waiting_blur.visible = true

	g.waiting_label.modulate.a = 0.0
	g.waiting_blur.modulate.a = 0.0

	var tween_wait_in = g.create_tween().set_parallel(true)
	tween_wait_in.tween_property(g.waiting_label, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_property(g.waiting_blur, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_callback(func():
		g.dot_timer.start()
	)

func stop_waiting_animation() -> void:
	if is_instance_valid(g.dot_timer):
		g.dot_timer.stop()
	if is_instance_valid(g.waiting_label):
		g.waiting_label.visible = false
		g.waiting_label.modulate.a = 1.0
	if is_instance_valid(g.waiting_blur):
		g.waiting_blur.visible = false
		g.waiting_blur.modulate.a = 1.0

func on_dot_timer_timeout() -> void:
	if not is_instance_valid(g.waiting_label):
		print("Warning: waiting_label is not valid in _on_dot_timer_timeout.")
		return
	g.dot_count = (g.dot_count % 3) + 1
	var dots = ""
	for i in range(g.dot_count):
		dots += "."
	g.waiting_label.text = g.BASE_WAIT_TEXT + dots

func pop_button(btn: Control) -> void:
	btn.pivot_offset = btn.size / 2.0
	var tween := g.create_tween()
	tween.tween_property(btn, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

func on_rules_button_pressed() -> void:
	if not is_instance_valid(g.rules_button):
		return

	await pop_button(g.rules_button)

	var popup := g.RULES_POPUP_SCENE.instantiate() as RulesPopup
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := g.get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 100
	dim.z_index = 99

	popup.tree_exited.connect(func():
		if is_instance_valid(dim):
			dim.queue_free()
	)

	popup.open("How to Play Paintball", get_rules_text())

func get_rules_text() -> String:
	return """
[font_size={32px}][b]Paintball[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
• Replace in Future
[/font_size]

[font_size={24px}][b]How to Play[/b][/font_size]
[font_size={18px}]
• Replace in Future
[/font_size]

[font_size={24px}][b]End of Game[/b][/font_size]
[font_size={18px}]
• Replace in Future
[/font_size]
"""

func on_settings_button_pressed() -> void:
	if not is_instance_valid(g.settings_button):
		return

	await pop_button(g.settings_button)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var popup_instance := g.SETTINGS_POPUP_SCENE.instantiate()
	var settings_popup_script := popup_instance as SettingsPopup

	var root := g.get_tree().root
	root.add_child(dim)
	root.add_child(popup_instance)
	popup_instance.z_index = 100
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)

	settings_popup_script.setup_popup(dim)

	var custom_settings_title := popup_instance.find_child("CustomSettingsTitleLabel", true)
	if custom_settings_title and custom_settings_title is Label and settings_popup_script.custom_settings_container.get_child_count() > 0:
		(custom_settings_title as Label).visible = true
	elif custom_settings_title and custom_settings_title is Label:
		(custom_settings_title as Label).visible = false

	settings_popup_script.closed.connect(func():
		if is_instance_valid(g.player_avatar_display):
			g.player_avatar_display.update_display_from_settings()
	)
	settings_popup_script.settings_theme_selected.connect(g._on_theme_changed)

	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await g.get_tree().process_frame

	var viewport_size: Vector2 = g.get_viewport().get_visible_rect().size
	var desired_width: float = viewport_size.x * 0.95
	var desired_height: float = popup_instance.get_combined_minimum_size().y

	popup_instance.size = Vector2(desired_width, desired_height)
	popup_instance.position = Vector2((viewport_size.x - desired_width) / 2.0, viewport_size.y)

	var bottom_offset: float = 50.0
	var target_y_position: float = viewport_size.y - desired_height - bottom_offset
	var target_position: Vector2 = Vector2((viewport_size.x - desired_width) / 2.0, target_y_position)

	var popup_tween := g.create_tween()
	popup_tween.tween_property(popup_instance, "position", target_position, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	popup_instance.grab_focus()

func ensure_avatar_wrapper(avatar: Control) -> Control:
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

func show_win_burst(avatar: Control) -> void:
	var wrapper: Control = ensure_avatar_wrapper(avatar)
	if not is_instance_valid(wrapper):
		return

	var existing: Node = wrapper.get_node_or_null("AvatarWinAnim")
	if existing != null:
		return

	var anim_instance: Control = g.AvatarWinAnimScene.instantiate() as Control
	anim_instance.name = "AvatarWinAnim"
	wrapper.add_child(anim_instance)

	var avatar_idx: int = avatar.get_index()
	wrapper.move_child(anim_instance, avatar_idx)

	anim_instance.z_as_relative = false
	avatar.z_as_relative = false
	anim_instance.z_index = 0
	avatar.z_index = max(avatar.z_index, 1)

	anim_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	anim_instance.offset_left = -52.0
	anim_instance.offset_right = 52.0
	anim_instance.offset_top = -43.0
	anim_instance.offset_bottom = 43.0

	(anim_instance as Node).call("set_color", Color(1.0, 0.84, 0.0))
	(anim_instance as Node).call("play", 0.05)

func check_win() -> bool:
	print("--- CHECKING WIN CONDITION ---")

	if g.game_over:
		return true

	if g._hp_me > 0 and g._hp_opp > 0:
		return false

	g.game_over = true

	if g._hp_me <= 0 and g._hp_opp <= 0:
		g.win_loss_state = "0"
		if is_instance_valid(g.win_loss_label):
			g.win_loss_label.text = "DRAW!"
			g.win_loss_label.visible = true
		return true

	if g._hp_opp <= 0:
		g.win_loss_state = "1"
		if is_instance_valid(g.win_loss_label):
			g.win_loss_label.text = ("Player 1 Wins!" if g.spectator_mode else "YOU WIN!")
			g.win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			g.win_loss_label.visible = true
		if is_instance_valid(g.player_avatar_display):
			show_win_burst(g.player_avatar_display)
		return true

	g.win_loss_state = "-1"
	if is_instance_valid(g.win_loss_label):
		g.win_loss_label.text = ("Player 2 Wins!" if g.spectator_mode else "YOU LOSE")
		g.win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
		g.win_loss_label.visible = true
	if is_instance_valid(g.opp_avatar_display):
		show_win_burst(g.opp_avatar_display)

	return true
