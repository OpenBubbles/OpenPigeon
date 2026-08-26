extends PanelContainer
class_name SettingsPopup

signal closed
signal settings_theme_selected(new_theme_name: String)
signal dark_mode_changed(is_dark: bool)

var dark_mode_enabled: bool = false
var dark_mode_auto_apply_theme: bool = true
var dark_mode_button: Button = null
var theme_previews_enabled: bool = false

const AvatarThumbnailScene = preload("res://global/avatar_textures/AvatarThumbnail.tscn")
const MOON_TEX: Texture2D = preload("res://global/avatar_textures/moon.svg")
const SUN_TEX: Texture2D = preload("res://global/avatar_textures/sun.svg")

@onready var settings_label = %SettingsLabel as Label
@onready var theme_option_button = %ThemeOptionButton as OptionButton
@onready var main_preview_container = %MainPreviewContainer as CenterContainer
@onready var avatar_tab_container = %AvatarTabContainer as TabBar
@onready var properties_box = %PropertiesBox as VBoxContainer
@onready var custom_settings_container = %CustomSettingsContainer as VBoxContainer
@onready var global_settings_container = %GlobalSettingsContainer as VBoxContainer
@onready var theme_dropdown_container = %ThemeDropdownContainer
@onready var theme_preview_picker = %ThemePreviewPicker
@onready var preview_box = %PreviewBox

var dim_rect: ColorRect
var main_avatar_preview: Node
var current_brightness_slider: HSlider = null
const GRABBER_IMAGE_PATH = "res://global/hollow_grabber.png"
const THUMB_PRESS_MODE := BaseButton.ACTION_MODE_BUTTON_PRESS
const DEADZONE_PX := 4
var _scroll_pos_by_tab: Dictionary[String, Vector2] = {}
var _responsive_scroll_landscape_only: bool = false

const SETTINGS_LANDSCAPE_REFERENCE_SHORT_SIDE: float = 540.0
const SETTINGS_LANDSCAPE_REFERENCE_SCALE: float = 2.1
const SETTINGS_LANDSCAPE_MIN_SCALE: float = 2.0
const SETTINGS_LANDSCAPE_MAX_SCALE: float = 2.5
const SETTINGS_PICKER_DRAG_THRESHOLD: float = 7.0
const SETTINGS_SCALE_MIN_SIZE_META := "_settings_scale_min_size"
const SETTINGS_BASE_H_SIZE_FLAGS_META := "_settings_base_h_size_flags"
const SETTINGS_BASE_V_SIZE_FLAGS_META := "_settings_base_v_size_flags"
const SETTINGS_BASE_SLIDER_MIN_SIZE_META := "_settings_base_slider_min_size"
const SETTINGS_MISC_PREVIEW_VISUAL_META := "_settings_misc_preview_visual"
const SETTINGS_MISC_PREVIEW_BASE_SCALE_META := "_settings_misc_preview_base_scale"
const SETTINGS_AVATAR_THUMBNAIL_META := "_settings_avatar_thumbnail"
const SETTINGS_AVATAR_BASE_PREVIEW_META := "_settings_avatar_base_preview"
const SETTINGS_SCALE_BOOST_META := "_settings_scale_boost"
const SETTINGS_LANDSCAPE_PICKER_BOOST: float = 1.25

const SETTINGS_RICH_TEXT_FONT_ITEMS := [
	"normal_font_size",
	"bold_font_size",
	"italics_font_size",
	"bold_italics_font_size",
	"mono_font_size"
]

const SETTINGS_MARGIN_ITEMS := [
	"margin_left",
	"margin_top",
	"margin_right",
	"margin_bottom"
]

const SETTINGS_TAB_CONSTANT_ITEMS := [
	"h_separation",
	"tab_separation"
]

const SETTINGS_TAB_STYLEBOX_ITEMS := [
	"tab_selected",
	"tab_unselected",
	"tab_hovered",
	"tab_disabled",
	"tab_focus"
]

const SETTINGS_BASE_MIN_SIZE_META := (
	"_settings_base_minimum_size"
)

const SETTINGS_BASE_SIZE_META := (
	"_settings_base_size"
)

const SETTINGS_BASE_POSITION_META := (
	"_settings_base_position"
)

var _settings_layout_refresh_queued: bool = false
var _responsive_scroll: ScrollContainer = null
var _responsive_body: Control = null
var _responsive_layout_active: bool = false
var _misc_settings_container: VBoxContainer = null
var _misc_tab_index: int = -1
var _misc_preview_loading: bool = false

func _remember_scroll_positions() -> void:
	for child in properties_box.get_children():
		if child is ScrollContainer:
			var key: String
			if child.has_meta("list_key"):
				key = String(child.get_meta("list_key"))
			else:
				key = String(avatar_tab_container.get_tab_title(avatar_tab_container.current_tab))
			_scroll_pos_by_tab[key] = Vector2(child.scroll_horizontal, child.scroll_vertical)

func _restore_scroll(sc: ScrollContainer) -> void:
	var key: String = String(sc.get_meta("list_key")) \
		if sc.has_meta("list_key") \
		else String(avatar_tab_container.get_tab_title(avatar_tab_container.current_tab))
	if _scroll_pos_by_tab.has(key):
		var pos: Vector2 = _scroll_pos_by_tab[key] as Vector2
		sc.call_deferred("set", "scroll_horizontal", int(pos.x))
		sc.call_deferred("set", "scroll_vertical", int(pos.y))

func _ready() -> void:
	print("SettingsPopup: _ready() called.")

	self.custom_minimum_size.x = 0

	if (
		SettingsManager and
		SettingsManager.has_method(
			"ensure_avatar_defaults"
		)
	):
		SettingsManager.ensure_avatar_defaults()

	var viewport := get_viewport()

	if (
		is_instance_valid(viewport) and
		not viewport.size_changed.is_connected(
			_queue_settings_layout_refresh
		)
	):
		viewport.size_changed.connect(
			_queue_settings_layout_refresh
		)

	_setup_theme_button()
	_style_theme_dropdown()
	_add_dark_mode_toggle()
	_setup_avatar_customizer()

	var saved_dark: bool = (
		SettingsManager.get_setting(
			"global",
			"dark_mode",
			false
		) == true
	)

	set_dark_mode(saved_dark, true)

	if is_instance_valid(custom_settings_container):
		custom_settings_container.add_theme_constant_override(
			"separation",
			8
		)

		if not custom_settings_container.child_entered_tree.is_connected(
			_on_settings_control_added
		):
			custom_settings_container.child_entered_tree.connect(
				_on_settings_control_added
			)

	if is_instance_valid(properties_box):
		if not properties_box.child_entered_tree.is_connected(
			_on_settings_control_added
		):
			properties_box.child_entered_tree.connect(
				_on_settings_control_added
			)

	if is_instance_valid(global_settings_container):
		if not global_settings_container.child_entered_tree.is_connected(
			_on_settings_control_added
		):
			global_settings_container.child_entered_tree.connect(
				_on_settings_control_added
			)

	_queue_settings_layout_refresh()

func _is_settings_landscape() -> bool:
	var viewport_size := get_viewport_rect().size
	return viewport_size.x > viewport_size.y

func _settings_ui_scale() -> float:
	if not _is_settings_landscape():
		return 1.0

	var viewport_size := get_viewport_rect().size
	var short_side := minf(viewport_size.x, viewport_size.y)
	return clampf((short_side / SETTINGS_LANDSCAPE_REFERENCE_SHORT_SIDE) * SETTINGS_LANDSCAPE_REFERENCE_SCALE, SETTINGS_LANDSCAPE_MIN_SCALE, SETTINGS_LANDSCAPE_MAX_SCALE)

func _mark_settings_scalable(control: Control, boosted: bool = false) -> void:
	control.set_meta(SETTINGS_SCALE_MIN_SIZE_META, true)
	if boosted:
		control.set_meta(SETTINGS_SCALE_BOOST_META, true)

func _settings_boosted_scale(scale_factor: float) -> float:
	return scale_factor * SETTINGS_LANDSCAPE_PICKER_BOOST if scale_factor > 1.0 else scale_factor

func _on_settings_control_added(
	_node: Node
) -> void:
	_queue_settings_layout_refresh()


func _queue_settings_layout_refresh() -> void:
	if _settings_layout_refresh_queued:
		return

	_settings_layout_refresh_queued = true

	call_deferred(
		"_apply_settings_layout_deferred"
	)


func _apply_settings_layout_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_settings_layout_refresh_queued = false

	if not is_inside_tree():
		return

	_apply_settings_orientation_layout()


func _settings_meta_key(
	prefix: String,
	item_name: String
) -> String:
	return "%s_%s" % [
		prefix,
		item_name
	]

func _scale_settings_misc_preview_visual(control: Control, scale_factor: float) -> void:
	if not control.has_meta(SETTINGS_MISC_PREVIEW_BASE_SCALE_META):
		control.set_meta(SETTINGS_MISC_PREVIEW_BASE_SCALE_META, control.scale)

	var base_scale: Vector2 = control.get_meta(SETTINGS_MISC_PREVIEW_BASE_SCALE_META)

	if control.size.x > 0.0 and control.size.y > 0.0:
		control.pivot_offset = control.size * 0.5

	control.scale = base_scale * scale_factor

func _scale_settings_font_item(
	control: Control,
	font_item: String,
	scale_factor: float
) -> void:
	var meta_key := _settings_meta_key(
		"_settings_base_font",
		font_item
	)

	if not control.has_meta(meta_key):
		control.set_meta(
			meta_key,
			control.get_theme_font_size(font_item)
		)

	var base_size: int = int(
		control.get_meta(meta_key)
	)

	control.add_theme_font_size_override(
		font_item,
		max(
			1,
			int(
				round(
					float(base_size) *
					scale_factor
				)
			)
		)
	)


func _scale_settings_theme_constant(
	control: Control,
	constant_name: String,
	scale_factor: float
) -> void:
	var meta_key := _settings_meta_key(
		"_settings_base_constant",
		constant_name
	)

	if not control.has_meta(meta_key):
		control.set_meta(
			meta_key,
			control.get_theme_constant(
				constant_name
			)
		)

	var base_value: int = int(
		control.get_meta(meta_key)
	)

	control.add_theme_constant_override(
		constant_name,
		int(
			round(
				float(base_value) *
				scale_factor
			)
		)
	)

func _scale_settings_stylebox_margins(control: Control, stylebox_name: String, scale_factor: float) -> void:
	var meta_key := _settings_meta_key("_settings_base_stylebox", stylebox_name)

	if not control.has_meta(meta_key):
		var current := control.get_theme_stylebox(stylebox_name)
		if current == null:
			return
		control.set_meta(meta_key, current)

	var base: StyleBox = control.get_meta(meta_key)
	var scaled := base.duplicate() as StyleBox

	for side: int in 4:
		scaled.set_content_margin(side, base.get_margin(side) * scale_factor)

	control.add_theme_stylebox_override(stylebox_name, scaled)

func _scale_settings_minimum_size(
	control: Control,
	scale_factor: float
) -> void:
	if not control.has_meta(
		SETTINGS_BASE_MIN_SIZE_META
	):
		control.set_meta(
			SETTINGS_BASE_MIN_SIZE_META,
			control.custom_minimum_size
		)

	var base_minimum_size: Vector2 = (
		control.get_meta(
			SETTINGS_BASE_MIN_SIZE_META
		)
	)

	control.custom_minimum_size = (
		base_minimum_size *
		scale_factor
	)


func _scale_button_child_geometry(
	control: Control,
	scale_factor: float
) -> void:
	if not control.get_parent() is BaseButton:
		return

	if not control.has_meta(
		SETTINGS_BASE_SIZE_META
	):
		control.set_meta(
			SETTINGS_BASE_SIZE_META,
			control.size
		)

	if not control.has_meta(
		SETTINGS_BASE_POSITION_META
	):
		control.set_meta(
			SETTINGS_BASE_POSITION_META,
			control.position
		)

	var base_size: Vector2 = control.get_meta(
		SETTINGS_BASE_SIZE_META
	)

	var base_position: Vector2 = control.get_meta(
		SETTINGS_BASE_POSITION_META
	)

	control.size = base_size * scale_factor
	control.position = base_position * scale_factor

func _configure_settings_avatar_thumbnail(avatar: TextureButton) -> void:
	avatar.scale = Vector2.ONE
	avatar.clip_contents = true
	avatar.set_meta(SETTINGS_AVATAR_THUMBNAIL_META, true)

	var internal_viewport := avatar.get_node_or_null("SubViewportContainer/SubViewport") as SubViewport
	if internal_viewport != null:
		internal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	_scale_settings_avatar_thumbnail(avatar, _settings_ui_scale())

func _scale_settings_avatar_thumbnail(avatar: Control, scale_factor: float) -> void:
	var preview := avatar.get_node_or_null("SubViewportContainer") as SubViewportContainer
	if preview == null:
		return

	if not preview.has_meta(SETTINGS_AVATAR_BASE_PREVIEW_META):
		preview.set_meta(SETTINGS_AVATAR_BASE_PREVIEW_META, [
			Vector4(preview.offset_left, preview.offset_top, preview.offset_right, preview.offset_bottom),
			preview.scale,
			preview.pivot_offset
		])

	var base: Array = preview.get_meta(SETTINGS_AVATAR_BASE_PREVIEW_META)
	var base_offsets: Vector4 = base[0]
	var base_w: float = base_offsets.z - base_offsets.x
	var base_h: float = base_offsets.w - base_offsets.y

	preview.pivot_offset = base[2] if scale_factor <= 1.0 else Vector2.ZERO
	preview.scale = (base[1] as Vector2) * scale_factor
	preview.offset_left = -base_w * 0.5 * scale_factor
	preview.offset_right = preview.offset_left + base_w
	preview.offset_top = -base_h * scale_factor
	preview.offset_bottom = preview.offset_top + base_h

func _scale_settings_control_recursive(node: Node, scale_factor: float) -> void:
	var control := node as Control

	if control != null:
		var item_scale := _settings_boosted_scale(scale_factor) if bool(control.get_meta(SETTINGS_SCALE_BOOST_META, false)) else scale_factor

		if bool(control.get_meta(SETTINGS_SCALE_MIN_SIZE_META, false)):
			_scale_settings_minimum_size(control, item_scale)

		if bool(control.get_meta(SETTINGS_AVATAR_THUMBNAIL_META, false)):
			_scale_settings_avatar_thumbnail(control, item_scale)

		if bool(control.get_meta(SETTINGS_MISC_PREVIEW_VISUAL_META, false)):
			_scale_settings_misc_preview_visual(control, item_scale)

		if control is HSlider:
			_scale_settings_slider(control as HSlider, item_scale)

		if control is RichTextLabel:
			for font_item: String in SETTINGS_RICH_TEXT_FONT_ITEMS:
				_scale_settings_font_item(control, font_item, item_scale)
		elif control is Label or control is BaseButton or control is LineEdit or control is TextEdit or control is TabBar:
			_scale_settings_font_item(control, "font_size", item_scale)

		if control is MarginContainer:
			for margin_item: String in SETTINGS_MARGIN_ITEMS:
				_scale_settings_theme_constant(control, margin_item, item_scale)

		if control is BoxContainer:
			_scale_settings_theme_constant(control, "separation", item_scale)

		if control is TabBar:
			for constant_item: String in SETTINGS_TAB_CONSTANT_ITEMS:
				_scale_settings_theme_constant(control, constant_item, item_scale)
			for stylebox_item: String in SETTINGS_TAB_STYLEBOX_ITEMS:
				_scale_settings_stylebox_margins(control, stylebox_item, item_scale)

	for child: Node in node.get_children():
		_scale_settings_control_recursive(child, scale_factor)

func _refresh_settings_switches(
	node: Node
) -> void:
	var button := node as Button

	if button != null:
		_apply_switch_visual(button, button.button_pressed, true)

	for child: Node in node.get_children():
		_refresh_settings_switches(child)

func _apply_switch_visual(btn: Button, enabled: bool, instant: bool) -> void:
	if is_instance_valid(btn.get_node_or_null("KnobWrap")):
		_layout_switch_children(btn)
		_update_switch_visual(btn, enabled, instant)
	elif is_instance_valid(btn.get_node_or_null("Knob")):
		_update_game_switch_visual(btn, enabled, instant)

func _apply_settings_orientation_layout() -> void:
	var scale_factor := _settings_ui_scale()
	var body := _find_responsive_body()

	if is_instance_valid(body):
		_scale_settings_control_recursive(body, scale_factor)

	if is_instance_valid(theme_option_button):
		var popup_menu := theme_option_button.get_popup()
		if popup_menu != null:
			popup_menu.add_theme_font_size_override("font_size", int(round(15.0 * scale_factor)))

	_refresh_settings_switches(self)

	if _responsive_layout_active:
		_apply_responsive_popup_geometry()

func _find_responsive_body() -> Control:
	if is_instance_valid(_responsive_body):
		return _responsive_body
	for child in get_children():
		if child is Control and child != _responsive_scroll:
			_responsive_body = child as Control
			return _responsive_body
	return null

func _ensure_responsive_scroll(landscape_only: bool = false) -> void:
	if is_instance_valid(_responsive_scroll):
		if not landscape_only:
			_responsive_scroll_landscape_only = false
		return

	var body := _find_responsive_body()
	if not is_instance_valid(body):
		return

	if not body.has_meta(SETTINGS_BASE_H_SIZE_FLAGS_META):
		body.set_meta(SETTINGS_BASE_H_SIZE_FLAGS_META, body.size_flags_horizontal)
	if not body.has_meta(SETTINGS_BASE_V_SIZE_FLAGS_META):
		body.set_meta(SETTINGS_BASE_V_SIZE_FLAGS_META, body.size_flags_vertical)

	remove_child(body)

	_responsive_scroll = ScrollContainer.new()
	_responsive_scroll.name = "ResponsiveSettingsScroll"
	_responsive_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_responsive_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_responsive_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_responsive_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_responsive_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_responsive_scroll.scroll_deadzone = 10
	_responsive_scroll_landscape_only = landscape_only

	add_child(_responsive_scroll)
	_responsive_scroll.add_child(body)

	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

func _remove_responsive_scroll() -> void:
	if not is_instance_valid(_responsive_scroll):
		return

	var body := _responsive_body

	if is_instance_valid(body) and body.get_parent() == _responsive_scroll:
		_responsive_scroll.remove_child(body)

	if _responsive_scroll.get_parent() == self:
		remove_child(_responsive_scroll)

	_responsive_scroll.queue_free()
	_responsive_scroll = null
	_responsive_scroll_landscape_only = false

	if is_instance_valid(body):
		add_child(body)
		if body.has_meta(SETTINGS_BASE_H_SIZE_FLAGS_META):
			body.size_flags_horizontal = int(body.get_meta(SETTINGS_BASE_H_SIZE_FLAGS_META))
		if body.has_meta(SETTINGS_BASE_V_SIZE_FLAGS_META):
			body.size_flags_vertical = int(body.get_meta(SETTINGS_BASE_V_SIZE_FLAGS_META))

func get_responsive_popup_size(viewport_size: Vector2) -> Vector2:
	var landscape := viewport_size.x > viewport_size.y

	if landscape:
		_ensure_responsive_scroll(true)
		return viewport_size * 0.90

	if is_instance_valid(_responsive_scroll) and _responsive_scroll_landscape_only:
		_remove_responsive_scroll()

	var body := _find_responsive_body()
	var preferred := get_combined_minimum_size()
	if is_instance_valid(body):
		preferred = body.get_combined_minimum_size() + Vector2(20.0, 20.0)

	var width_limit: float = minf(viewport_size.x * 0.94, 640.0)
	var min_width: float = minf(width_limit, minf(viewport_size.x * 0.90, 400.0))
	var popup_width: float = clampf(preferred.x, min_width, width_limit)

	var max_height: float = viewport_size.y * 0.94
	var popup_height: float = minf(preferred.y, max_height)

	if preferred.y > max_height:
		_ensure_responsive_scroll(false)
		popup_height = max_height

	return Vector2(popup_width, max(120.0, popup_height))

func get_responsive_target_position(viewport_size: Vector2, popup_size: Vector2) -> Vector2:
	if viewport_size.x > viewport_size.y:
		return (viewport_size - popup_size) * 0.5
	return Vector2((viewport_size.x - popup_size.x) * 0.5, max(0.0, viewport_size.y - popup_size.y))

func set_responsive_layout_active(enabled: bool) -> void:
	_responsive_layout_active = enabled
	if enabled:
		_apply_responsive_popup_geometry()

func _apply_responsive_popup_geometry() -> void:
	if not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	var popup_size := get_responsive_popup_size(viewport_size)
	size = popup_size
	position = get_responsive_target_position(viewport_size, popup_size)

func close_popup():
	if not SettingsManager.suppress_avatar_changed:
		SettingsManager.avatar_changed.emit()
	
	print("SettingsPopup: Closing popup.")
	var tween = create_tween()
	tween.tween_property(self, "position", Vector2(position.x, get_viewport_rect().size.y), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		emit_signal("closed")
		queue_free()
		if is_instance_valid(dim_rect):
			dim_rect.queue_free()
	)

func _setup_theme_button() -> void:
	if is_instance_valid(theme_dropdown_container):
		theme_dropdown_container.hide()

	if is_instance_valid(theme_option_button):
		theme_option_button.hide()

	if is_instance_valid(preview_box):
		preview_box.hide()

func _populate_theme_dropdown():
	if not is_instance_valid(theme_option_button):
		printerr("SettingsPopup: ERROR! ThemeOptionButton not found.")
		return
	
	theme_option_button.clear()

	if not theme_option_button.item_selected.is_connected(_on_theme_option_button_item_selected):
		theme_option_button.item_selected.connect(_on_theme_option_button_item_selected)

	var theme_names: Array[String] = [
	]

	for i in range(theme_names.size()):
		theme_option_button.add_item(theme_names[i], i)
	
	var saved_theme: String = str(SettingsManager.get_setting("global", "theme", "Default"))

	for i in range(theme_option_button.item_count):
		if theme_option_button.get_item_text(i) == saved_theme:
			theme_option_button.select(i)
			break

func _populate_theme_previews():
	for child in preview_box.get_children():
		child.queue_free()
	
	var all_themes = _get_all_themes()
	var saved_theme = SettingsManager.get_setting("global", "theme", "Default")
	
	for theme_name in all_themes.keys():
		var btn = TextureButton.new()
		var preview_data = all_themes[theme_name]
		
		var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		image.fill(preview_data.preview_color)
		var texture = ImageTexture.create_from_image(image)
		
		btn.texture_normal = texture
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = Vector2(64, 64)
		_mark_settings_scalable(btn)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.button_mask = MOUSE_BUTTON_MASK_LEFT
		
		if theme_name == saved_theme:
			var style_box = StyleBoxFlat.new()
			style_box.bg_color = Color(0, 0, 0, 0)
			style_box.border_width_left = 4; style_box.border_width_top = 4; style_box.border_width_right = 4; style_box.border_width_bottom = 4
			style_box.border_color = Color(0.2, 0.8, 0.2, 0.9)
			btn.add_theme_stylebox_override("normal", style_box)
		
		btn.pressed.connect(func(): _on_theme_preview_selected(theme_name))
		
		preview_box.add_child(btn)
		
func _set_avatar_value(category: String, key: String, value) -> void:
	if category == "hair":
		SettingsManager.set_setting("avatar_hair_front", key, value)
		SettingsManager.set_setting("avatar_hair_back", key, value)
		SettingsManager.set_setting("avatar_hair", key, value)
	else:
		SettingsManager.set_setting("avatar_" + category, key, value)
		
func populate_theme_previews(themes_data: Dictionary) -> void:
	const HOVER_SCALE := 1.08
	const PRESS_SCALE := 0.95
	const TWEEN_TIME := 0.08

	for child in preview_box.get_children():
		child.queue_free()

	if themes_data.is_empty():
		print("No theme data provided to populate previews.")
		return

	var saved_theme: String = str(SettingsManager.get_setting("global", "theme", "Default"))

	for theme_name in themes_data.keys():
		var btn: TextureButton = TextureButton.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.button_mask = MOUSE_BUTTON_MASK_LEFT
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.custom_minimum_size = Vector2(60, 60)
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.scale = Vector2.ONE
		btn.resized.connect(func(): btn.pivot_offset = btn.size * 0.5)
		
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color("#FFD700", 0.4)
		bg_style.border_color = Color("#DAA520", 0.6)
		bg_style.border_width_left = 1
		bg_style.border_width_top = 1
		bg_style.border_width_right = 1
		bg_style.border_width_bottom = 1
		bg_style.corner_radius_bottom_left = 5
		bg_style.corner_radius_bottom_right = 5
		bg_style.corner_radius_top_left = 5
		bg_style.corner_radius_top_right = 5
		btn.add_theme_stylebox_override("normal", bg_style)
		btn.add_theme_stylebox_override("hover", bg_style)
		btn.add_theme_stylebox_override("pressed", bg_style)
		btn.add_theme_stylebox_override("focus", bg_style)

		var texture: Texture2D
		
		if themes_data[theme_name].has("texture") and themes_data[theme_name]["texture"] is Texture2D:
			texture = themes_data[theme_name]["texture"]
		else:
			var preview_path: String = str(themes_data[theme_name].get("preview_path", ""))
			if FileAccess.file_exists(preview_path):
				texture = load(preview_path) as Texture2D
			else:
				push_warning("Theme preview image missing: " + preview_path)
				var placeholder := Image.create(64, 64, false, Image.FORMAT_RGBA8)
				placeholder.fill(Color.MAGENTA)
				texture = ImageTexture.create_from_image(placeholder)

		if not is_instance_valid(texture): continue

		var img: Image = texture.get_image()
		if img:
			img.resize(40, 40, Image.INTERPOLATE_LANCZOS)
			btn.texture_normal = ImageTexture.create_from_image(img)
		else:
			btn.texture_normal = texture

		if theme_name == saved_theme:
			var selected_style_box := bg_style.duplicate() as StyleBoxFlat
			
			selected_style_box.border_width_left = 3
			selected_style_box.border_width_top = 3
			selected_style_box.border_width_right = 3
			selected_style_box.border_width_bottom = 3
			selected_style_box.border_color = Color(0.2, 0.8, 0.2, 0.9)
			
			btn.add_theme_stylebox_override("normal", selected_style_box)

		var tween_to := func(target: float) -> void:
			if btn.has_meta("preview_tween"):
				var old = btn.get_meta("preview_tween")
				if old: old.kill()
			var tw = create_tween()
			btn.set_meta("preview_tween", tw)
			tw.tween_property(btn, "scale", Vector2(target, target), TWEEN_TIME)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		btn.mouse_entered.connect(func(): tween_to.call(HOVER_SCALE))
		btn.mouse_exited.connect(func(): tween_to.call(1.0))
		btn.button_down.connect(func(): tween_to.call(PRESS_SCALE))
		btn.button_up.connect(func():
			var hovered := btn.get_rect().has_point(btn.get_local_mouse_position())
			tween_to.call(HOVER_SCALE if hovered else 1.0)
		)
		btn.pivot_offset = btn.custom_minimum_size * 0.5
		var captured_name : String = theme_name
		btn.pressed.connect(func(): _on_theme_preview_selected(captured_name))

		preview_box.add_child(btn)
		
func _get_all_themes() -> Dictionary:
	return {
		"Default": { "path": "res://themes/default.tres", "preview_color": Color("#e0e0e0") }
	}

func _on_theme_preview_selected(selected_theme_name: String):
	print("Theme preview button clicked: ", selected_theme_name)
	SettingsManager.set_setting("global", "theme", selected_theme_name)
	if SettingsManager.has_method("save"):
		SettingsManager.save()
	settings_theme_selected.emit(selected_theme_name)

func _on_theme_option_button_item_selected(index: int):
	var selected_theme_name = theme_option_button.get_item_text(index)
	print("Theme dropdown item selected: ", selected_theme_name)
	SettingsManager.set_setting("global", "theme", selected_theme_name)
	if SettingsManager.has_method("save"):
		SettingsManager.save()
	settings_theme_selected.emit(selected_theme_name)

func _setup_avatar_customizer():
	main_avatar_preview = AvatarThumbnailScene.instantiate()
	main_avatar_preview.is_display_only = true
	main_avatar_preview.custom_minimum_size = Vector2(96, 140)
	_mark_settings_scalable(main_avatar_preview)
	_configure_settings_avatar_thumbnail(main_avatar_preview)

	main_preview_container.custom_minimum_size.y = 140
	_mark_settings_scalable(main_preview_container)
	main_preview_container.add_child(main_avatar_preview)

	_mark_settings_scalable(avatar_tab_container, true)
	avatar_tab_container.tab_changed.connect(_on_avatar_tab_changed)
	avatar_tab_container.add_tab("BG")
	avatar_tab_container.add_tab("Body")
	avatar_tab_container.add_tab("Hair")
	avatar_tab_container.add_tab("Face")
	avatar_tab_container.add_tab("Cloth")
	avatar_tab_container.add_tab("Acc.")
	avatar_tab_container.current_tab = 0
	_on_avatar_tab_changed(0)

func _on_avatar_tab_changed(tab_index: int, restored_scroll: Variant = null):
	if not is_instance_valid(properties_box):
		printerr("SettingsPopup: ERROR! properties_box is not valid.")
		return

	var tab_name := avatar_tab_container.get_tab_title(tab_index)

	_remember_scroll_positions()
	for child in properties_box.get_children():
		if child == _misc_settings_container:
			properties_box.remove_child(child)
		else:
			child.queue_free()

	current_brightness_slider = null
	match tab_name:
		"BG": _populate_background_properties()
		"Body": _populate_fshape_properties()
		"Hair": _populate_hair_properties()
		"Face": _populate_face_properties()
		"Cloth": _populate_clothing_properties()
		"Acc.": _populate_accessories_properties()
		"Misc":
			if is_instance_valid(_misc_settings_container):
				properties_box.add_child(_misc_settings_container)
				_misc_settings_container.visible = true
				call_deferred("_load_misc_previews")

	if restored_scroll != null:
		for child in properties_box.get_children():
			if child is ScrollContainer:
				child.call_deferred("set", "scroll_horizontal", int(restored_scroll.x))
				child.call_deferred("set", "scroll_vertical", int(restored_scroll.y))
				break

	_queue_settings_layout_refresh()


func _on_avatar_preview_setting_changed(value, category: String, key: String):
	_set_avatar_value(category, key, value)
	main_avatar_preview.update_display_from_settings()

func _on_avatar_setting_changed(category: String, key: String, value):
	_set_avatar_value(category, key, value)

	var saved_value
	if category == "hair":
		saved_value = SettingsManager.get_setting("avatar_hair_front", key)
	else:
		saved_value = SettingsManager.get_setting("avatar_" + category, key)

	print("--- SETTING CHANGED ---")
	print("Saved '", key, "' for '", category, "' with new value: '", saved_value, "'")
	print("-----------------------")

	main_avatar_preview.update_display_from_settings()

	var keep_pos: Variant = null
	for child in properties_box.get_children():
		if child is ScrollContainer:
			keep_pos = Vector2(child.scroll_horizontal, child.scroll_vertical)
			break

	_on_avatar_tab_changed(avatar_tab_container.current_tab, keep_pos)

func _populate_background_properties():
	var preset_colors = [ Color("#7c7c7c"), Color("#e7639f"), Color("#9e45c0"), Color("#5798f6"), Color("#32d5c8"), Color("#7cb33e"), Color("#b1da1a"), Color("#f6d61a"), Color("#ee7c09"), Color("#f11f06"), Color("#d3292c") ]
	var default_color = SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89"))
	var initial_brightness = SettingsManager.get_setting("avatar_background", "brightness", 0.0)
	_create_color_and_brightness_control("background", "color", "brightness", preset_colors, default_color, initial_brightness)
	var style_options = ["Plain", "Pattern 1", "Pattern 2", "Pattern 3", "Pattern 4", "Pattern 5", "Pattern 6", "Pattern 7", "Pattern 8", "Pattern 9"]
	_create_image_presets_scrollbar("background", "style", style_options)

func _populate_fshape_properties():
	var fshape_styles = ["Default", "fshape1", "fshape2", "fshape3", "fshape4", "fshape5", "fshape6"]
	_create_image_presets_scrollbar("fshape", "head_style", fshape_styles)
	var skin_tones = [ Color("#ffbd9a"), Color("#ffb070"), Color("#804734"), Color("#5f442f"), Color("#cccccc"), Color("#da73a2"), Color("#6394f1"), Color("#82b941"), Color("#f8cf55"), Color("#f6820c"), Color("#c34126") ]
	var default_tone = SettingsManager.get_setting("avatar_fshape", "color", Color("#e0ac69"))
	var initial_brightness = SettingsManager.get_setting("avatar_fshape", "brightness", 0.0)
	_create_color_and_brightness_control("fshape", "color", "brightness", skin_tones, default_tone, initial_brightness)

func _populate_hair_properties():
	var hair_styles := []
	for i in range(1, 16):
		hair_styles.append("hair" + str(i))

	# thumbnails – selecting a style updates BOTH layers via _on_avatar_setting_changed
	_create_image_presets_scrollbar("hair", "style", hair_styles)

	var hair_colors = [
		Color("#f8cf55"), Color("#e1872f"), Color("#d24325"), Color("#6d411d"), Color("#572c1f"),
		Color("#000000"), Color("#e1e1e1"), Color("#ee67a4"), Color("#a348c7"), Color("#699bff"), Color("#82b941")
	]
	var default_color = SettingsManager.get_setting("avatar_hair_front", "color",
		SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b")))
	var initial_brightness = SettingsManager.get_setting("avatar_hair_front", "brightness",
		SettingsManager.get_setting("avatar_hair", "brightness", 0.0))

	# color/brightness controls – will write to BOTH layers
	_create_color_and_brightness_control("hair", "color", "brightness", hair_colors, default_color, initial_brightness)
	
func _populate_face_properties():
	var eye_styles := []
	for i in range(1, 14):
		eye_styles.append("eyes" + str(i))
	_create_image_presets_scrollbar("face", "eyes", eye_styles)
	var mouth_styles := []
	for i in range(1, 18):
		mouth_styles.append("mouth" + str(i))
	_create_image_presets_scrollbar("face", "mouth", mouth_styles)

func _populate_clothing_properties():
	var clothing_styles := []
	for i in range(1, 4):
		clothing_styles.append("clothing" + str(i))
	_create_image_presets_scrollbar("clothing", "style", clothing_styles)
	var clothing_colors = [ Color("#7c7c7c"), Color("#e7639f"), Color("#9e45c0"), Color("#5798f6"), Color("#32d5c8"), Color("#7cb33e"), Color("#b1da1a"), Color("#f6d61a"), Color("#ee7c09"), Color("#f11f06"), Color("#d3292c") ]
	var default_color = SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c"))
	var initial_brightness = SettingsManager.get_setting("avatar_clothing", "brightness", 0.0)
	_create_color_and_brightness_control("clothing", "color", "brightness", clothing_colors, default_color, initial_brightness)

func _populate_accessories_properties():
	var head_accessories_styles: Array[String] = []
	for i in range(13):
		head_accessories_styles.append("hat_%d" % i)
	_create_image_presets_scrollbar("accessories", "head_style", head_accessories_styles)

	var face_accessories_styles: Array[String] = []
	for i in range(1, 15):
		face_accessories_styles.append("face_%d" % i)
	_create_image_presets_scrollbar("accessories", "face_style", face_accessories_styles)

func _create_color_and_brightness_control(category: String, color_key: String, brightness_key: String, colors: PackedColorArray, default_color: Color, initial_brightness: float):
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size.y = 80
	_mark_settings_scalable(vbox, true)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 5)
	var hbox_colors = HBoxContainer.new()
	hbox_colors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_colors.add_theme_constant_override("separation", 5)
	var diameter = 24
	var radius = 999
	var spacer_left = Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_colors.add_child(spacer_left)
	for color_value in colors:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(diameter, diameter)
		_mark_settings_scalable(btn, true)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = color_value
		style_normal.border_width_left = 2; style_normal.border_width_top = 2; style_normal.border_width_right = 2; style_normal.border_width_bottom = 2
		style_normal.border_color = color_value.darkened(0.2)
		style_normal.corner_radius_top_left = radius; style_normal.corner_radius_top_right = radius; style_normal.corner_radius_bottom_left = radius; style_normal.corner_radius_bottom_right = radius
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("pressed", style_normal.duplicate())
		var style_focus = style_normal.duplicate()
		style_focus.border_color = Color(0.2, 0.8, 0.2, 0.9)
		btn.add_theme_stylebox_override("hover", style_focus)
		btn.add_theme_stylebox_override("focus", style_focus)
		btn.set_meta("preset_color", color_value)
		btn.pressed.connect(func():
			_on_avatar_setting_changed(category, color_key, btn.get_meta("preset_color"))
			_on_avatar_setting_changed(category, brightness_key, 0.0)
		)
		hbox_colors.add_child(btn)
		var spacer_mid = Control.new()
		spacer_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox_colors.add_child(spacer_mid)
	vbox.add_child(hbox_colors)
	var slider = HSlider.new()
	slider.set_meta("category", category)
	slider.set_meta("key", brightness_key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = -1.0; slider.max_value = 1.0; slider.step = 0.01
	slider.value = initial_brightness
	slider.set_meta(SETTINGS_SCALE_BOOST_META, true)
	slider.value_changed.connect(_on_avatar_preview_setting_changed.bind(category, brightness_key))
	vbox.add_child(slider)
	current_brightness_slider = slider
	_update_brightness_slider_gradient(default_color)
	_add_property_to_box(vbox)
	_update_selected_color_dot_border(hbox_colors, default_color)

func _add_property_to_box(control_to_wrap: Control):
	var panel_container = PanelContainer.new()
	var stylebox_flat = StyleBoxFlat.new()
	stylebox_flat.bg_color = Color(1, 1, 1, 0.1)
	stylebox_flat.border_width_left = 1; stylebox_flat.border_width_top = 1; stylebox_flat.border_width_right = 1; stylebox_flat.border_width_bottom = 1
	stylebox_flat.border_color = Color(1, 1, 1, 0.2)
	stylebox_flat.corner_radius_top_left = 5; stylebox_flat.corner_radius_top_right = 5; stylebox_flat.corner_radius_bottom_left = 5; stylebox_flat.corner_radius_bottom_right = 5
	stylebox_flat.set_content_margin_all(5)
	panel_container.add_theme_stylebox_override("panel", stylebox_flat)
	panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	properties_box.add_child(panel_container)
	panel_container.add_child(control_to_wrap)

func _update_selected_color_dot_border(parent_hbox: HBoxContainer, selected_color: Color):
	for child in parent_hbox.get_children():
		if child is Button and child.has_meta("preset_color"):
			var stylebox_normal = child.get_theme_stylebox("normal", "Button") as StyleBoxFlat
			if stylebox_normal:
				var new_stylebox = stylebox_normal.duplicate() as StyleBoxFlat
				if child.get_meta("preset_color") == selected_color:
					new_stylebox.border_color = Color(0.2, 0.8, 0.2, 0.9)
					new_stylebox.border_width_left = 3; new_stylebox.border_width_top = 3; new_stylebox.border_width_right = 3; new_stylebox.border_width_bottom = 3
				else:
					new_stylebox.border_color = child.get_meta("preset_color").darkened(0.2)
					new_stylebox.border_width_left = 2; new_stylebox.border_width_top = 2; new_stylebox.border_width_right = 2; new_stylebox.border_width_bottom = 2
				child.add_theme_stylebox_override("normal", new_stylebox)

func _begin_game_picker_drag(scroll: ScrollContainer) -> void:
	scroll.set_meta("_settings_picker_drag_active", true)
	scroll.set_meta("_settings_picker_dragged", false)
	scroll.set_meta("_settings_picker_drag_delta", Vector2.ZERO)
	scroll.set_meta("_settings_picker_drag_axis", 0)


func _move_game_picker_drag(scroll: ScrollContainer, relative: Vector2) -> void:
	if not bool(scroll.get_meta("_settings_picker_drag_active", false)):
		return

	var delta: Vector2 = Vector2(scroll.get_meta("_settings_picker_drag_delta", Vector2.ZERO)) + relative
	scroll.set_meta("_settings_picker_drag_delta", delta)

	var axis: int = int(scroll.get_meta("_settings_picker_drag_axis", 0))

	if axis == 0:
		if delta.length() < SETTINGS_PICKER_DRAG_THRESHOLD:
			return
		axis = 1 if absf(delta.x) >= absf(delta.y) else 2
		scroll.set_meta("_settings_picker_drag_axis", axis)
		scroll.set_meta("_settings_picker_dragged", true)

	if axis == 1:
		scroll.scroll_horizontal -= int(round(relative.x))
	elif is_instance_valid(_responsive_scroll):
		_responsive_scroll.scroll_vertical -= int(round(relative.y))
	else:
		return

	get_viewport().set_input_as_handled()

func _end_game_picker_drag(scroll: ScrollContainer, on_tap: Callable = Callable()) -> void:
	if not bool(scroll.get_meta("_settings_picker_drag_active", false)):
		return

	var dragged: bool = bool(scroll.get_meta("_settings_picker_dragged", false))
	scroll.set_meta("_settings_picker_drag_active", false)

	if not dragged and on_tap.is_valid():
		on_tap.call()

	get_viewport().set_input_as_handled()


func _on_game_picker_item_input(event: InputEvent, scroll: ScrollContainer, on_tap: Callable) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return

		if mouse_event.pressed:
			_begin_game_picker_drag(scroll)
		else:
			_end_game_picker_drag(scroll, on_tap)

	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_move_game_picker_drag(scroll, motion.relative)

	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_game_picker_drag(scroll)
		else:
			_end_game_picker_drag(scroll, on_tap)

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_move_game_picker_drag(scroll, drag.relative)


func _on_game_picker_scroll_input(event: InputEvent, scroll: ScrollContainer) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return

		if mouse_event.pressed:
			_begin_game_picker_drag(scroll)
		else:
			_end_game_picker_drag(scroll)

	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_move_game_picker_drag(scroll, motion.relative)

	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_game_picker_drag(scroll)
		else:
			_end_game_picker_drag(scroll)

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_move_game_picker_drag(scroll, drag.relative)

func _update_brightness_slider_gradient(color: Color):
	if not is_instance_valid(current_brightness_slider): return
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color.from_hsv(color.h, color.s, 0.3))
	gradient.add_point(0.5, color)
	gradient.add_point(1.0, Color.from_hsv(color.h, 0.0, 1.0))
	var grad_tex = GradientTexture2D.new()
	grad_tex.gradient = gradient
	var main_bar_style = StyleBoxTexture.new()
	main_bar_style.texture = grad_tex
	main_bar_style.texture_margin_top = 8; main_bar_style.texture_margin_bottom = 8; main_bar_style.texture_margin_left = 6; main_bar_style.texture_margin_right = 6
	current_brightness_slider.add_theme_stylebox_override("slider", main_bar_style)
	var clear_style = StyleBoxFlat.new()
	clear_style.bg_color = Color.TRANSPARENT
	current_brightness_slider.add_theme_stylebox_override("grabber_area", clear_style)
	current_brightness_slider.add_theme_stylebox_override("grabber_area_highlight", clear_style)
	var grabber_icon = load(GRABBER_IMAGE_PATH)
	current_brightness_slider.add_theme_icon_override("grabber", grabber_icon)
	current_brightness_slider.add_theme_icon_override("grabber_highlight", grabber_icon)
	current_brightness_slider.add_theme_icon_override("grabber_pressed", grabber_icon)

func _get_current_avatar_settings() -> Dictionary:
	var hair_color = SettingsManager.get_setting("avatar_hair_front", "color", SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b")))
	var hair_bright = SettingsManager.get_setting("avatar_hair_front", "brightness", SettingsManager.get_setting("avatar_hair", "brightness", 0.0))
	var hair_style = SettingsManager.get_setting("avatar_hair_front", "style", SettingsManager.get_setting("avatar_hair", "style", "hair1"))
	var face_style := str(SettingsManager.get_setting("avatar_accessories", "face_style", "face_1"))
	if face_style == "None" or not AvatarThumbnail.avatar_face_accessories_regions.has(face_style):
		face_style = "face_1"

	return {
		"background": {
			"color": SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89")),
			"brightness": SettingsManager.get_setting("avatar_background", "brightness", 0.0),
			"style": SettingsManager.get_setting("avatar_background", "style", "Plain")
		},
		"fshape": {
			"color": SettingsManager.get_setting("avatar_fshape", "color", Color("#e0ac69")),
			"brightness": SettingsManager.get_setting("avatar_fshape", "brightness", 0.0),
			"head_style": SettingsManager.get_setting("avatar_fshape", "head_style", "Default")
		},
		"hair_front": {"color": hair_color, "brightness": hair_bright, "style": hair_style},
		"hair_back": {"color": hair_color, "brightness": hair_bright, "style": hair_style},
		"face": {
			"eyes": SettingsManager.get_setting("avatar_face", "eyes", "eyes1"),
			"mouth": SettingsManager.get_setting("avatar_face", "mouth", "mouth1")
		},
		"clothing": {
			"color": SettingsManager.get_setting("avatar_clothing", "color", Color("#a03c3c")),
			"brightness": SettingsManager.get_setting("avatar_clothing", "brightness", 0.0),
			"style": SettingsManager.get_setting("avatar_clothing", "style", "clothing1")
		},
		"accessories": {
			"color": SettingsManager.get_setting("avatar_accessories", "color", Color.WHITE),
			"brightness": SettingsManager.get_setting("avatar_accessories", "brightness", 0.0),
			"head_style": SettingsManager.get_setting("avatar_accessories", "head_style", "hat_0"),
			"face_style": face_style
		}
	}

func _create_image_presets_scrollbar(category: String, key: String, style_options: Array):
	var scroll_container := ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.custom_minimum_size = Vector2(0, 150)
	_mark_settings_scalable(scroll_container)
	scroll_container.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.scroll_deadzone = int(SETTINGS_PICKER_DRAG_THRESHOLD)
	scroll_container.gui_input.connect(_on_game_picker_scroll_input.bind(scroll_container))

	var list_key: String = "%s/%s/%s" % [
		avatar_tab_container.get_tab_title(avatar_tab_container.current_tab),
		category, key
	]
	scroll_container.set_meta("list_key", list_key)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll_container.add_child(hbox)

	var current_settings := _get_current_avatar_settings()
	var cfg_section := "avatar_hair_front" if category == "hair" else "avatar_" + category
	var current_style_value = SettingsManager.get_setting(cfg_section, key, style_options[0])

	for style_name in style_options:
		var thumbnail := AvatarThumbnailScene.instantiate()
		thumbnail.custom_minimum_size = Vector2(96, 140)
		_mark_settings_scalable(thumbnail)
		thumbnail.controlled_by_data = true
		thumbnail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_configure_settings_avatar_thumbnail(thumbnail)
		thumbnail.focus_mode = Control.FOCUS_NONE
		thumbnail.mouse_filter = Control.MOUSE_FILTER_STOP
		thumbnail.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		thumbnail.button_mask = MOUSE_BUTTON_MASK_LEFT
		thumbnail.toggle_mode = false

		hbox.add_child(thumbnail)

		if category == "hair":
			var preview_settings = current_settings.duplicate(true)
			preview_settings["hair_front"]["style"] = style_name
			preview_settings["hair_back"]["style"]  = style_name
			thumbnail.call_deferred("update_preview", preview_settings, "hair_front", "style", style_name)
		else:
			thumbnail.call_deferred("update_preview", current_settings, category, key, style_name)

		if style_name == current_style_value:
			thumbnail.set_selected(true)

		var select_item := func() -> void:
			_on_avatar_setting_changed(category, key, style_name)

		thumbnail.gui_input.connect(_on_game_picker_item_input.bind(scroll_container, select_item))

	_add_property_to_box(scroll_container)
	_restore_scroll(scroll_container)

func _exit_tree():
	print("SettingsPopup: _exit_tree() called.")
	if is_instance_valid(dim_rect):
		dim_rect.queue_free()
	if is_instance_valid(_misc_settings_container) and _misc_settings_container.get_parent() == null:
		_misc_settings_container.queue_free()


func setup_popup(
	dimmer: ColorRect
) -> void:
	dim_rect = dimmer

	if is_instance_valid(dim_rect):
		dim_rect.gui_input.connect(
			_on_dim_rect_gui_input
		)

	_queue_settings_layout_refresh()
		
func set_dark_mode(enabled: bool, instant: bool = false) -> void:
	if dark_mode_enabled == enabled:
		_apply_dark_mode_visuals(enabled, instant)
		return
	dark_mode_enabled = enabled
	SettingsManager.set_setting("global", "dark_mode", enabled)
	_apply_dark_mode_visuals(enabled, instant)
	emit_signal("dark_mode_changed", enabled)


func get_dark_mode() -> bool:
	return dark_mode_enabled

func get_dark_palette() -> Dictionary:
	if dark_mode_enabled:
		return {
			"bg": Color(0.12,0.12,0.12),
			"fg": Color(0.92,0.92,0.92),
			"muted": Color(0.65,0.65,0.65),
			"accent": Color(0.85,0.85,0.85)
		}
	else:
		return {
			"bg": Color(0.95,0.95,0.95),
			"fg": Color(0.10,0.10,0.10),
			"muted": Color(0.40,0.40,0.40),
			"accent": Color(0.40,0.40,0.40)
		}

func _apply_dark_mode_visuals(enabled: bool, instant: bool) -> void:
	if dark_mode_button == null: return
	dark_mode_button.set_pressed_no_signal(enabled)
	_update_switch_visual(dark_mode_button, enabled, instant)
	
	var sb := get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		sb = StyleBoxFlat.new()
		add_theme_stylebox_override("panel", sb)

	var target := Color(0.1176, 0.1176, 0.1804, 0.98)

	if instant:
		sb.bg_color = target
	else:
		var tw := create_tween()
		tw.tween_property(sb, "bg_color", target, 0.25)
		
func _add_dark_mode_toggle():
	dark_mode_button = _make_switch_button()

	var on_toggled := func(enabled: bool) -> void:
		set_dark_mode(enabled, false)

	var card := make_game_switch_card("Dark Mode", "Darken menus and popups", dark_mode_enabled, on_toggled, dark_mode_button)

	if is_instance_valid(global_settings_container):
		global_settings_container.add_child(card)
	else:
		printerr("SettingsPopup: GlobalSettingsContainer not found; cannot add dark mode toggle.")

func _make_switch_button() -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(72, 36)
	_mark_settings_scalable(btn)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.clip_contents = false

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.22, 0.24, 1.0)
	track.border_color = Color(1.0, 1.0, 1.0, 0.18)
	track.border_width_left = 1
	track.border_width_top = 1
	track.border_width_right = 1
	track.border_width_bottom = 1
	track.corner_radius_top_left = 999
	track.corner_radius_top_right = 999
	track.corner_radius_bottom_left = 999
	track.corner_radius_bottom_right = 999
	track.content_margin_left = 2; track.content_margin_right = 2
	track.content_margin_top = 2; track.content_margin_bottom = 2
	btn.add_theme_stylebox_override("normal", track)
	btn.add_theme_stylebox_override("hover", track)
	btn.add_theme_stylebox_override("pressed", track)
	btn.add_theme_stylebox_override("focus", track)
	btn.add_theme_stylebox_override("disabled", track)

	var knob_wrap := PanelContainer.new()
	knob_wrap.name = "KnobWrap"
	knob_wrap.size = Vector2(32, 32)
	knob_wrap.position = Vector2(2, 2)
	knob_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob_wrap.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	btn.add_child(knob_wrap)

	var knob := PanelContainer.new()
	knob.name = "Knob"
	knob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	knob.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var kbox := StyleBoxFlat.new()
	kbox.bg_color = Color(0, 0, 0, 1)
	kbox.corner_radius_top_left = 16
	kbox.corner_radius_top_left = 999
	kbox.corner_radius_top_right = 999
	kbox.corner_radius_bottom_left = 999
	kbox.corner_radius_bottom_right = 999
	kbox.anti_aliasing = true
	knob.add_theme_stylebox_override("panel", kbox)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob_wrap.add_child(knob)

	var moon := TextureRect.new()
	moon.name = "MoonIn"
	moon.texture = MOON_TEX
	moon.ignore_texture_size = true
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	moon.z_index = 2
	btn.add_child(moon)

	var sun := TextureRect.new()
	sun.name = "SunIn"
	sun.texture = SUN_TEX
	sun.ignore_texture_size = true
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun.z_index = 2
	btn.add_child(sun)

	_layout_switch_children(btn)
	btn.resized.connect(_layout_switch_children.bind(btn))

	return btn
	
func _layout_switch_children(
	btn: Button
) -> void:
	var scale_factor: float = (
		_settings_ui_scale()
	)

	var icon_size: float = (
		20.0 *
		scale_factor
	)

	var padding: float = (
		8.0 *
		scale_factor
	)

	var knob_size: Vector2 = (
		Vector2(32.0, 32.0) *
		scale_factor
	)

	var moon := btn.get_node_or_null(
		"MoonIn"
	) as TextureRect

	var sun := btn.get_node_or_null(
		"SunIn"
	) as TextureRect

	var knob_wrap := btn.get_node_or_null(
		"KnobWrap"
	) as PanelContainer

	if is_instance_valid(knob_wrap):
		knob_wrap.size = knob_size

		knob_wrap.position.y = (
			btn.size.y -
			knob_wrap.size.y
		) * 0.5

	if is_instance_valid(moon):
		moon.custom_minimum_size = Vector2(
			icon_size,
			icon_size
		)

		moon.size = moon.custom_minimum_size
		moon.stretch_mode = (
			TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		)

		moon.position = Vector2(
			btn.size.x -
				icon_size -
				padding,
			(
				btn.size.y -
				icon_size
			) * 0.5
		)

	if is_instance_valid(sun):
		sun.custom_minimum_size = Vector2(
			icon_size,
			icon_size
		)

		sun.size = sun.custom_minimum_size
		sun.stretch_mode = (
			TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		)

		sun.position = Vector2(
			padding,
			(
				btn.size.y -
				icon_size
			) * 0.5
		)

func _update_switch_visual(btn: Button, on: bool, instant: bool):
	var base := btn.get_theme_stylebox("normal", "Button") as StyleBoxFlat
	if base:
		var tdup := base.duplicate() as StyleBoxFlat
		tdup.bg_color = Color(0.655, 0.545, 0.980, 1.0) if on else Color(0.22, 0.22, 0.24, 1.0)
		tdup.border_color = Color(1.0, 1.0, 1.0, 0.26) if on else Color(1.0, 1.0, 1.0, 0.18)
		btn.add_theme_stylebox_override("normal", tdup)
		btn.add_theme_stylebox_override("hover", tdup)
		btn.add_theme_stylebox_override("pressed", tdup)

	var knob_wrap := btn.get_node_or_null("KnobWrap") as PanelContainer
	var knob := knob_wrap.get_node_or_null("Knob") if is_instance_valid(knob_wrap) else null
	var moon := btn.get_node_or_null("MoonIn") as TextureRect
	var sun := btn.get_node_or_null("SunIn") as TextureRect
	if not is_instance_valid(knob_wrap) or not is_instance_valid(knob):
		return

	if is_instance_valid(moon): moon.move_to_front()
	if is_instance_valid(sun): sun.move_to_front()

	var left_x := 2.0 * _settings_ui_scale()
	var right_x := btn.size.x - knob_wrap.size.x - left_x
	var target_x := right_x if on else left_x

	var knob_color := Color(0, 0, 0) if on else Color(1, 1, 1)
	var icon_color := Color(1, 1, 1) if on else Color(0, 0, 0)

	var kbox := knob.get_theme_stylebox("panel") as StyleBoxFlat
	if kbox:
		kbox = kbox.duplicate() as StyleBoxFlat
		kbox.bg_color = knob_color
		knob.add_theme_stylebox_override("panel", kbox)

	if instant:
		knob_wrap.position.x = target_x
		if is_instance_valid(moon): moon.modulate = icon_color
		if is_instance_valid(sun): sun.modulate = icon_color
	else:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(knob_wrap, "position:x", target_x, 0.2)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if is_instance_valid(moon):
			tw.tween_property(moon, "modulate", icon_color, 0.15)
		if is_instance_valid(sun):
			tw.tween_property(sun, "modulate", icon_color, 0.15)

func _sync_theme_dropdown_from_dark(dark_on: bool):
	var desired := "Default (Dark)" if dark_on else "Default"

	if is_instance_valid(theme_option_button):
		for i in range(theme_option_button.item_count):
			if theme_option_button.get_item_text(i) == desired:
				theme_option_button.select(i)
				break

	SettingsManager.set_setting("global", "theme", desired)
	settings_theme_selected.emit(desired)

func _style_theme_dropdown() -> void:
	if not is_instance_valid(theme_dropdown_container) or not is_instance_valid(theme_option_button):
		return

	if theme_dropdown_container is BoxContainer:
		var box := theme_dropdown_container as BoxContainer
		box.add_theme_constant_override("separation", 8)
		box.alignment = BoxContainer.ALIGNMENT_CENTER

	theme_dropdown_container.custom_minimum_size = Vector2(0, 86)
	theme_dropdown_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := theme_dropdown_container.get_node_or_null("Label") as Label
	if is_instance_valid(label):
		label.text = "Theme"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)

	theme_option_button.custom_minimum_size = Vector2(300, 44)
	theme_option_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	theme_option_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	theme_option_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	theme_option_button.focus_mode = Control.FOCUS_NONE
	theme_option_button.add_theme_font_size_override("font_size", 16)
	theme_option_button.add_theme_color_override("font_color", Color.WHITE)
	theme_option_button.add_theme_color_override("font_hover_color", Color.WHITE)
	theme_option_button.add_theme_color_override("font_pressed_color", Color.WHITE)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.12, 0.14, 0.88)
	normal.border_color = Color(1.0, 1.0, 1.0, 0.20)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 14
	normal.corner_radius_top_right = 14
	normal.corner_radius_bottom_left = 14
	normal.corner_radius_bottom_right = 14
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.17, 0.17, 0.20, 0.94)
	hover.border_color = Color(1.0, 1.0, 1.0, 0.34)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.09, 0.09, 0.11, 0.96)
	pressed.border_color = Color(1.0, 1.0, 1.0, 0.42)

	theme_option_button.add_theme_stylebox_override("normal", normal)
	theme_option_button.add_theme_stylebox_override("hover", hover)
	theme_option_button.add_theme_stylebox_override("pressed", pressed)
	theme_option_button.add_theme_stylebox_override("focus", hover)

	var popup_menu := theme_option_button.get_popup()
	if popup_menu != null:
		popup_menu.add_theme_font_size_override("font_size", 15)
		popup_menu.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
		popup_menu.add_theme_color_override("font_hover_color", Color.WHITE)

		var popup_style := StyleBoxFlat.new()
		popup_style.bg_color = Color(0.10, 0.10, 0.12, 0.98)
		popup_style.border_color = Color(1.0, 1.0, 1.0, 0.18)
		popup_style.border_width_left = 1
		popup_style.border_width_top = 1
		popup_style.border_width_right = 1
		popup_style.border_width_bottom = 1
		popup_style.corner_radius_top_left = 10
		popup_style.corner_radius_top_right = 10
		popup_style.corner_radius_bottom_left = 10
		popup_style.corner_radius_bottom_right = 10
		popup_menu.add_theme_stylebox_override("panel", popup_style)


func make_game_switch_card(title: String, subtitle: String, initial_on: bool, on_toggled: Callable, switch_button: Button = null) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 62)
	_mark_settings_scalable(card)

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.102, 0.102, 0.141, 1.0)
	card_style.border_color = Color(0.278, 0.278, 0.373, 1.0)
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.corner_radius_top_left = 16
	card_style.corner_radius_top_right = 16
	card_style.corner_radius_bottom_left = 16
	card_style.corner_radius_bottom_right = 16
	card_style.content_margin_left = 12
	card_style.content_margin_right = 12
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", card_style)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(copy)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	copy.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.text = subtitle
	subtitle_label.add_theme_font_size_override("font_size", 12)
	subtitle_label.add_theme_color_override("font_color", Color(0.667, 0.667, 0.800, 1.0))
	copy.add_child(subtitle_label)

	var switch := switch_button if switch_button != null else _make_game_switch_button()
	switch.set_pressed_no_signal(initial_on)
	switch.toggled.connect(func(enabled: bool) -> void:
		_apply_switch_visual(switch, enabled, false)
		if on_toggled.is_valid():
			on_toggled.call(enabled)
	)

	row.add_child(switch)
	_apply_switch_visual(switch, initial_on, true)

	return card

func make_game_option_card(title: String, subtitle: String, items: Array[String], selected_index: int, on_selected: Callable) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 62)
	_mark_settings_scalable(card)

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.102, 0.102, 0.141, 1.0)
	card_style.border_color = Color(0.278, 0.278, 0.373, 1.0)
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.corner_radius_top_left = 16
	card_style.corner_radius_top_right = 16
	card_style.corner_radius_bottom_left = 16
	card_style.corner_radius_bottom_right = 16
	card_style.content_margin_left = 12
	card_style.content_margin_right = 12
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", card_style)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(copy)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	copy.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.text = subtitle
	subtitle_label.add_theme_font_size_override("font_size", 12)
	subtitle_label.add_theme_color_override("font_color", Color(0.667, 0.667, 0.800, 1.0))
	copy.add_child(subtitle_label)

	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(130, 40)
	_mark_settings_scalable(option)
	option.size_flags_horizontal = Control.SIZE_SHRINK_END
	option.focus_mode = Control.FOCUS_NONE
	option.alignment = HORIZONTAL_ALIGNMENT_CENTER
	option.fit_to_longest_item = false
	option.add_theme_font_size_override("font_size", 15)
	option.add_theme_color_override("font_color", Color.WHITE)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.12, 0.14, 0.88)
	normal.border_color = Color(1.0, 1.0, 1.0, 0.20)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.corner_radius_bottom_right = 12
	normal.content_margin_left = 12
	normal.content_margin_right = 12

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.17, 0.17, 0.20, 0.94)

	option.add_theme_stylebox_override("normal", normal)
	option.add_theme_stylebox_override("hover", hover)
	option.add_theme_stylebox_override("pressed", hover)
	option.add_theme_stylebox_override("focus", hover)

	for i in range(items.size()):
		option.add_item(items[i], i)

	if not items.is_empty():
		option.select(clampi(selected_index, 0, items.size() - 1))

	option.item_selected.connect(func(index: int) -> void:
		if on_selected.is_valid():
			on_selected.call(index)
	)

	var popup_menu := option.get_popup()
	popup_menu.add_theme_font_size_override("font_size", 15)
	popup_menu.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	popup_menu.add_theme_color_override("font_hover_color", Color.WHITE)

	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = Color(0.10, 0.10, 0.12, 0.98)
	popup_style.border_color = Color(1.0, 1.0, 1.0, 0.18)
	popup_style.border_width_left = 1
	popup_style.border_width_top = 1
	popup_style.border_width_right = 1
	popup_style.border_width_bottom = 1
	popup_style.corner_radius_top_left = 10
	popup_style.corner_radius_top_right = 10
	popup_style.corner_radius_bottom_left = 10
	popup_style.corner_radius_bottom_right = 10
	popup_menu.add_theme_stylebox_override("panel", popup_style)

	row.add_child(option)
	return card

func _scale_settings_slider(slider: HSlider, scale_factor: float) -> void:
	if not slider.has_meta(SETTINGS_BASE_SLIDER_MIN_SIZE_META):
		slider.set_meta(SETTINGS_BASE_SLIDER_MIN_SIZE_META, slider.custom_minimum_size)

	var base_size: Vector2 = slider.get_meta(SETTINGS_BASE_SLIDER_MIN_SIZE_META)

	if scale_factor <= 1.0:
		slider.custom_minimum_size = base_size
	else:
		slider.custom_minimum_size = Vector2(base_size.x, maxf(base_size.y, 24.0) * scale_factor)

	if not slider.has_theme_stylebox_override("slider"):
		return

	var bar := slider.get_theme_stylebox("slider") as StyleBoxTexture
	if bar != null:
		bar.texture_margin_top = 8.0 * scale_factor
		bar.texture_margin_bottom = 8.0 * scale_factor
		bar.texture_margin_left = 6.0 * scale_factor
		bar.texture_margin_right = 6.0 * scale_factor

	var grabber := _scaled_grabber_icon(scale_factor)
	for icon_name: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		slider.add_theme_icon_override(icon_name, grabber)

func _scaled_grabber_icon(scale_factor: float) -> Texture2D:
	var base_icon: Texture2D = load(GRABBER_IMAGE_PATH)
	if scale_factor <= 1.0 or base_icon == null:
		return base_icon
	var image := base_icon.get_image()
	image.resize(int(round(image.get_width() * scale_factor)), int(round(image.get_height() * scale_factor)), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)

func _make_game_picker_item_style(selected: bool, hovered: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if selected:
		style.bg_color = Color(0.165, 0.149, 0.251, 1.0)
		style.border_color = Color(0.655, 0.545, 0.980, 1.0)
	elif hovered:
		style.bg_color = Color(0.155, 0.155, 0.210, 1.0)
		style.border_color = Color(0.360, 0.360, 0.480, 1.0)
	else:
		style.bg_color = Color(0.125, 0.125, 0.173, 1.0)
		style.border_color = Color(0.231, 0.231, 0.314, 1.0)

	var border_width: int = 2 if selected else 1
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 5

	return style

func _resolve_game_picker_texture(item: Dictionary) -> Texture2D:
	if item.has("texture"):
		var texture_value = item["texture"]
		if texture_value is Texture2D:
			return texture_value as Texture2D
		if texture_value is String and ResourceLoader.exists(String(texture_value)):
			return load(String(texture_value)) as Texture2D
	if item.has("texture_path") and ResourceLoader.exists(String(item["texture_path"])):
		return load(String(item["texture_path"])) as Texture2D
	return null

func _ensure_misc_tab() -> void:
	if _misc_tab_index >= 0:
		return
	if not is_instance_valid(avatar_tab_container):
		return
	avatar_tab_container.add_tab("Misc")
	_misc_tab_index = avatar_tab_container.tab_count - 1


func _ensure_misc_settings_container() -> VBoxContainer:
	if is_instance_valid(_misc_settings_container):
		return _misc_settings_container

	_misc_settings_container = VBoxContainer.new()
	_misc_settings_container.name = "MiscSettingsContainer"
	_misc_settings_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_misc_settings_container.add_theme_constant_override("separation", 14)
	return _misc_settings_container

func add_global_setting(control_node: Control) -> void:
	if not is_instance_valid(control_node) or not is_instance_valid(global_settings_container):
		return

	if control_node.get_parent() != null:
		control_node.reparent(global_settings_container)
	else:
		global_settings_container.add_child(control_node)

	_queue_settings_layout_refresh()

func add_misc_setting(control_node: Control) -> void:
	if not is_instance_valid(control_node):
		return

	_ensure_misc_tab()
	var container := _ensure_misc_settings_container()
	if control_node.get_parent() != null:
		control_node.reparent(container)
	else:
		container.add_child(control_node)

	if avatar_tab_container.current_tab == _misc_tab_index and container.get_parent() != properties_box:
		properties_box.add_child(container)

	_queue_settings_layout_refresh()

func make_game_picker_card(
	title: String,
	subtitle: String,
	items: Array[Dictionary],
	selected_id: String,
	on_selected: Callable,
	preview_factory: Callable = Callable()
) -> Control:
	var section := VBoxContainer.new()
	section.set_meta("_settings_misc_picker", true)
	section.add_theme_constant_override("separation", 2)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	_mark_settings_scalable(title_label, true)
	section.add_child(title_label)

	if not subtitle.is_empty():
		var subtitle_label := Label.new()
		subtitle_label.text = subtitle
		subtitle_label.modulate = Color(0.72, 0.72, 0.82, 1.0)
		subtitle_label.add_theme_font_size_override("font_size", 11)
		_mark_settings_scalable(subtitle_label, true)
		section.add_child(subtitle_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 108.0)
	_mark_settings_scalable(scroll, true)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = int(SETTINGS_PICKER_DRAG_THRESHOLD)
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.gui_input.connect(_on_game_picker_scroll_input.bind(scroll))
	section.add_child(scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(row)

	var buttons: Array[Button] = []

	var apply_selection := func(value: String) -> void:
		for index: int in range(buttons.size()):
			var option_button: Button = buttons[index]
			var option_id: String = str(items[index].get("id", ""))
			var selected: bool = option_id == value
			option_button.add_theme_stylebox_override("normal", _make_game_picker_item_style(selected))
			option_button.add_theme_stylebox_override("hover", _make_game_picker_item_style(selected, true))

	for item: Dictionary in items:
		var item_id: String = str(item.get("id", ""))

		var button := Button.new()
		button.custom_minimum_size = Vector2(90.0, 100.0)
		_mark_settings_scalable(button, true)
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = false
		button.clip_contents = true
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.add_theme_stylebox_override("normal", _make_game_picker_item_style(item_id == selected_id))
		button.add_theme_stylebox_override("hover", _make_game_picker_item_style(item_id == selected_id, true))
		button.add_theme_stylebox_override("pressed", _make_game_picker_item_style(true, true))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		var layout := VBoxContainer.new()
		layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layout.add_theme_constant_override("separation", 2)
		button.add_child(layout)

		var preview_host := CenterContainer.new()
		preview_host.custom_minimum_size = Vector2(74.0, 74.0)
		_mark_settings_scalable(preview_host, true)
		preview_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		preview_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(preview_host)

		if preview_factory.is_valid():
			preview_host.set_meta("_settings_preview_pending", true)
			preview_host.set_meta("_settings_preview_factory", preview_factory)
			preview_host.set_meta("_settings_preview_item", item)
		else:
			var texture: Texture2D = _resolve_game_picker_texture(item)

			if texture != null:
				var texture_rect := TextureRect.new()
				texture_rect.texture = texture
				texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				texture_rect.custom_minimum_size = Vector2(70.0, 70.0)
				_mark_settings_scalable(texture_rect, true)
				texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				preview_host.add_child(texture_rect)

		var label_text: String = str(item.get("label", ""))
		if not label_text.is_empty():
			var item_label := Label.new()
			item_label.text = label_text
			item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			item_label.add_theme_font_size_override("font_size", 10)
			item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layout.add_child(item_label)

		buttons.append(button)
		row.add_child(button)

		var select_item := func() -> void:
			if on_selected.is_valid():
				on_selected.call(item_id)
			apply_selection.call(item_id)

		button.gui_input.connect(_on_game_picker_item_input.bind(scroll, select_item))

	return section

func _load_misc_previews() -> void:
	if _misc_preview_loading:
		return

	if not is_instance_valid(_misc_settings_container):
		return

	if _misc_tab_index < 0 or avatar_tab_container.current_tab != _misc_tab_index:
		return

	_misc_preview_loading = true

	var pending_hosts: Array[Node] = _misc_settings_container.find_children("*", "CenterContainer", true, false)

	for found: Node in pending_hosts:
		if _misc_tab_index < 0 or avatar_tab_container.current_tab != _misc_tab_index:
			break

		var host := found as CenterContainer
		if host == null or not host.has_meta("_settings_preview_pending"):
			continue

		var factory: Callable = host.get_meta("_settings_preview_factory", Callable())
		var item_value: Variant = host.get_meta("_settings_preview_item", {})
		var item: Dictionary = {}

		if item_value is Dictionary:
			item = item_value as Dictionary

		host.remove_meta("_settings_preview_pending")
		host.remove_meta("_settings_preview_factory")
		host.remove_meta("_settings_preview_item")

		if factory.is_valid():
			var created: Variant = factory.call(item)

			if created is Control:
				var preview_control := created as Control
				preview_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
				preview_control.set_meta(SETTINGS_MISC_PREVIEW_VISUAL_META, true)
				preview_control.set_meta(SETTINGS_SCALE_BOOST_META, true)
				host.add_child(preview_control)

				await get_tree().process_frame

				if is_instance_valid(preview_control):
					_scale_settings_misc_preview_visual(preview_control, _settings_boosted_scale(_settings_ui_scale()))
			else:
				await get_tree().process_frame

	_misc_preview_loading = false
	_queue_settings_layout_refresh()

func _make_game_switch_button() -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(58, 30)
	_mark_settings_scalable(btn)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.clip_contents = false

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.22, 0.24, 1.0)
	track.border_color = Color(1.0, 1.0, 1.0, 0.18)
	track.border_width_left = 1
	track.border_width_top = 1
	track.border_width_right = 1
	track.border_width_bottom = 1
	track.corner_radius_top_left = 15
	track.corner_radius_top_right = 15
	track.corner_radius_bottom_left = 15
	track.corner_radius_bottom_right = 15
	btn.add_theme_stylebox_override("normal", track)
	btn.add_theme_stylebox_override("hover", track)
	btn.add_theme_stylebox_override("pressed", track)
	btn.add_theme_stylebox_override("focus", track)

	var knob := PanelContainer.new()
	knob.name = "Knob"
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob.custom_minimum_size = Vector2(24, 24)
	knob.size = Vector2(24, 24)
	knob.position = Vector2(3, 3)

	var knob_style := StyleBoxFlat.new()
	knob_style.bg_color = Color.WHITE
	knob_style.corner_radius_top_left = 12
	knob_style.corner_radius_top_right = 12
	knob_style.corner_radius_bottom_left = 12
	knob_style.corner_radius_bottom_right = 12
	knob.add_theme_stylebox_override("panel", knob_style)
	btn.add_child(knob)

	btn.resized.connect(func() -> void:
		_update_game_switch_visual(btn, btn.button_pressed, true)
	)

	return btn

func _update_game_switch_visual(btn: Button, enabled: bool, instant: bool) -> void:
	if not is_instance_valid(btn):
		return

	var track := btn.get_theme_stylebox("normal", "Button") as StyleBoxFlat
	if track:
		var next_track := track.duplicate() as StyleBoxFlat
		next_track.bg_color = Color(0.655, 0.545, 0.980, 1.0) if enabled else Color(0.22, 0.22, 0.24, 1.0)
		next_track.border_color = Color(1.0, 1.0, 1.0, 0.26) if enabled else Color(1.0, 1.0, 1.0, 0.18)
		btn.add_theme_stylebox_override("normal", next_track)
		btn.add_theme_stylebox_override("hover", next_track)
		btn.add_theme_stylebox_override("pressed", next_track)
		btn.add_theme_stylebox_override("focus", next_track)

	var knob := btn.get_node_or_null("Knob") as PanelContainer
	if not is_instance_valid(knob):
		return

	var scale_factor := _settings_ui_scale()
	var knob_size := Vector2(24.0, 24.0) * scale_factor
	var edge_padding := 3.0 * scale_factor

	knob.custom_minimum_size = knob_size
	knob.size = knob_size

	var target_x: float = btn.size.x - knob.size.x - edge_padding if enabled else edge_padding

	if instant:
		knob.position = Vector2(target_x, (btn.size.y - knob.size.y) * 0.5)
	else:
		knob.position.y = (btn.size.y - knob.size.y) * 0.5
		var tw := create_tween()
		tw.tween_property(knob, "position:x", target_x, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_dim_rect_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close_popup()

func add_custom_setting(control_node: Control):
	if not is_instance_valid(control_node):
		return
	if control_node.has_meta("_settings_misc_picker") and bool(control_node.get_meta("_settings_misc_picker")):
		add_misc_setting(control_node)
		return
	if custom_settings_container:
		custom_settings_container.add_child(control_node)
		_queue_settings_layout_refresh()
	else:
		printerr("SettingsPopup: ERROR! custom_settings_container is null.")
