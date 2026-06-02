class_name GameUtils
extends RefCounted

const AvatarWinAnimScene: PackedScene = preload("res://global/avatar_textures/avatar_win_anim.tscn")
const RULES_POPUP_SCENE: PackedScene = preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE: PackedScene = preload("res://global/settings_popup.tscn")

# ---------- Avatars ----------

static func _parse_avatar_string(data_string: String) -> Dictionary:
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

static func _ensure_avatar_wrapper(avatar: Control) -> Control:
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

static func _show_win_burst(avatar: Control) -> void:
	var wrapper: Control = _ensure_avatar_wrapper(avatar)
	if not is_instance_valid(wrapper):
		return

	var existing: Node = wrapper.get_node_or_null("AvatarWinAnim")
	if existing != null:
		return

	var anim_instance: Control = AvatarWinAnimScene.instantiate() as Control
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

# ---------- Rules popup ----------

static func open_rules_popup(game: Node, rules_button: Button, title: String, body: String) -> void:
	if is_instance_valid(rules_button):
		rules_button.pivot_offset = rules_button.size / 2.0
		var bump := game.create_tween()
		bump.tween_property(rules_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		bump.tween_property(rules_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await bump.finished

	var popup := RULES_POPUP_SCENE.instantiate() as RulesPopup
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := game.get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 200
	dim.z_index = 150
	popup.tree_exited.connect(func():
		if is_instance_valid(dim):
			dim.queue_free()
	)
	popup.open(title, body)

# ---------- Settings popup ----------
# add_rows:  Callable(container, popup_script) -> void   (optional; pass invalid Callable to skip)
# on_closed: Callable() -> void                          (base resets its _settings_open guard here)

static func open_settings_popup(game: Node, media_plugin, settings_button: Button,
		avatar_display, music_stream: AudioStream,
		add_rows: Callable, on_closed: Callable) -> void:
	if not is_instance_valid(settings_button):
		return

	settings_button.pivot_offset = settings_button.size / 2.0
	var bump := game.create_tween()
	bump.tween_property(settings_button, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	bump.tween_property(settings_button, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await bump.finished

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var popup := SETTINGS_POPUP_SCENE.instantiate()
	var popup_script := popup as SettingsPopup
	var root := game.get_tree().root
	root.add_child(dim)
	root.add_child(popup)
	popup.z_index = 200
	dim.z_index = 150
	root.move_child(dim, root.get_child_count() - 2)
	popup_script.setup_popup(dim)

	# Music row — common to every game.
	if media_plugin:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := Label.new()
		lbl.text = "Music"
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var toggle := CheckButton.new()
		toggle.button_pressed = media_plugin.isMusicEnabled()
		toggle.toggled.connect(func(enabled: bool) -> void:
			media_plugin.setMusicEnabled(enabled)
			if enabled:
				start_music(game, music_stream, media_plugin)
			else:
				stop_music(game)
		)
		row.add_child(lbl)
		row.add_child(toggle)
		popup_script.custom_settings_container.add_child(row)

	# Per-game extra rows / signal hookups.
	if add_rows.is_valid():
		add_rows.call(popup_script.custom_settings_container, popup_script)

	var title := popup.find_child("CustomSettingsTitleLabel", true)
	if title and title is Label:
		(title as Label).visible = popup_script.custom_settings_container.get_child_count() > 0

	popup_script.closed.connect(func():
		if on_closed.is_valid():
			on_closed.call()
		if is_instance_valid(avatar_display):
			avatar_display.update_display_from_settings()
		if is_instance_valid(dim):
			dim.queue_free()
	)

	popup.set_as_top_level(true)
	popup.visible = true
	await game.get_tree().process_frame

	var vp := game.get_viewport().get_visible_rect().size
	var w := vp.x * 0.95
	var h: float = popup.get_combined_minimum_size().y
	popup.size = Vector2(w, h)
	popup.position = Vector2((vp.x - w) / 2, vp.y)
	var target_y := vp.y - h - 50.0
	var slide := game.create_tween()
	slide.tween_property(popup, "position", Vector2((vp.x - w) / 2, target_y), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	popup.grab_focus()

# ---------- Music ----------

static func start_music(game: Node, stream: AudioStream, media_plugin) -> void:
	if media_plugin and not media_plugin.isMusicEnabled():
		return
	if stream == null:
		return
	var mp := game.get_node_or_null("MusicPlayer") as AudioStreamPlayer
	if mp == null:
		mp = AudioStreamPlayer.new()
		mp.name = "MusicPlayer"
		mp.stream = stream
		mp.volume_db = -4.0
		game.add_child(mp)
	if not mp.playing:
		mp.play()

static func stop_music(game: Node) -> void:
	var mp := game.get_node_or_null("MusicPlayer") as AudioStreamPlayer
	if mp:
		mp.stop()
