extends Control
class_name RulesPopup

@export var width_ratio: float = 0.90
@export var max_height_ratio: float = 0.80
@export var body_padding: float = 16.0

@onready var _panel: PanelContainer = %PanelContainer
@onready var _vbox: VBoxContainer = %VBoxContainer
@onready var _body_margin: MarginContainer = %BodyMarginContainer
@onready var _scroll: ScrollContainer = %ScrollContainer
@onready var _title: Label = %Title
@onready var _rules: RichTextLabel = %RulesLabel
@onready var _close: Button = %CloseButton

const RULES_LANDSCAPE_TEXT_SCALE: float = 1.5

const RULES_RICH_TEXT_FONT_ITEMS := [
	"normal_font_size",
	"bold_font_size",
	"italics_font_size",
	"bold_italics_font_size",
	"mono_font_size"
]

var _raw_rules_bbcode: String = ""
var _base_title_font_size: int = 20
var _base_rules_font_sizes: Dictionary = {}
var _font_size_tag_regex := RegEx.new()

func _ready() -> void:
	_close.pressed.connect(queue_free)

	var viewport := get_viewport()

	if (
		is_instance_valid(viewport) and
		not viewport.size_changed.is_connected(
			_on_viewport_size_changed
		)
	):
		viewport.size_changed.connect(
			_on_viewport_size_changed
		)

	_rules.bbcode_enabled = true
	_rules.visible = true
	_rules.fit_content = true
	_rules.scroll_active = false
	_rules.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)

	_scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)

	_scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_AUTO
	)

	_base_title_font_size = _title.get_theme_font_size(
		"font_size"
	)

	for font_item: String in RULES_RICH_TEXT_FONT_ITEMS:
		_base_rules_font_sizes[font_item] = (
			_rules.get_theme_font_size(font_item)
		)

	var regex_error := _font_size_tag_regex.compile(
		"\\[font_size=(\\d+)\\]"
	)

	if regex_error != OK:
		push_warning(
			"RulesPopup: Could not compile font-size regex."
		)

	_apply_rules_orientation_layout()

func open(
	title_text: String,
	rules_bbcode: String
) -> void:
	_title.text = title_text
	_raw_rules_bbcode = rules_bbcode

	_apply_rules_orientation_layout()

	call_deferred("_open_deferred")

func _rules_text_scale() -> float:
	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)

	return (
		RULES_LANDSCAPE_TEXT_SCALE
		if viewport_size.x > viewport_size.y
		else 1.0
	)


func _scale_rules_bbcode(
	source: String,
	scale_factor: float
) -> String:
	if (
		source.is_empty() or
		is_equal_approx(scale_factor, 1.0)
	):
		return source

	var result := source
	var matches: Array[RegExMatch] = (
		_font_size_tag_regex.search_all(source)
	)

	# Work backward so earlier match positions are not changed by
	# replacing later font-size numbers.
	for index in range(
		matches.size() - 1,
		-1,
		-1
	):
		var match_result: RegExMatch = matches[index]

		var number_start: int = match_result.get_start(1)
		var number_end: int = match_result.get_end(1)

		var original_size_text: String = source.substr(
			number_start,
			number_end - number_start
		)

		var scaled_size: int = max(
			1,
			int(
				round(
					float(original_size_text) *
					scale_factor
				)
			)
		)

		result = (
			result.substr(0, number_start) +
			str(scaled_size) +
			result.substr(number_end)
		)

	return result


func _apply_rules_orientation_layout() -> void:
	if (
		not is_instance_valid(_title) or
		not is_instance_valid(_rules)
	):
		return

	var scale_factor: float = _rules_text_scale()

	_title.add_theme_font_size_override(
		"font_size",
		max(
			1,
			int(
				round(
					float(_base_title_font_size) *
					scale_factor
				)
			)
		)
	)

	for font_item: String in RULES_RICH_TEXT_FONT_ITEMS:
		var base_size: int = int(
			_base_rules_font_sizes.get(
				font_item,
				16
			)
		)

		_rules.add_theme_font_size_override(
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

	_rules.text = _scale_rules_bbcode(
		_raw_rules_bbcode,
		scale_factor
	)


func _on_viewport_size_changed() -> void:
	_apply_rules_orientation_layout()
	call_deferred(
		"_refresh_after_orientation_change"
	)


func _refresh_after_orientation_change() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_refresh_layout()

	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)

	position = (
		viewport_size * 0.5 -
		size * 0.5
	)

func _open_deferred() -> void:
	_apply_rules_orientation_layout()

	await get_tree().process_frame
	await get_tree().process_frame

	_refresh_layout()

	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)

	position = (
		viewport_size * 0.5 -
		size * 0.5
	)

	pivot_offset = size * 0.5
	scale = Vector2.ZERO

	var tween := create_tween()

	tween.tween_property(
		self,
		"scale",
		Vector2.ONE,
		0.4
	).set_trans(
		Tween.TRANS_BACK
	).set_ease(
		Tween.EASE_OUT
	)

	grab_focus()

func _refresh_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var desired_w: float = viewport_size.x * width_ratio
	var max_h: float = viewport_size.y * max_height_ratio

	# Force the popup width first so text wraps correctly for height measurement
	size.x = desired_w
	_panel.custom_minimum_size.x = desired_w

	# Re-measure after width is set (wrapping changes height)
	var vbox_h: float = _vbox.size.y
	var body_h: float = _body_margin.size.y
	var header_h: float = vbox_h - body_h
	if header_h < 0.0:
		header_h = 0.0

	var content_h: float = _rules.get_content_height()
	var desired_body_h: float = content_h + body_padding
	var desired_popup_h: float = header_h + desired_body_h

	var final_popup_h: float = desired_popup_h
	if final_popup_h > max_h:
		final_popup_h = max_h

	# Apply popup height
	size.y = final_popup_h
	_panel.custom_minimum_size.y = final_popup_h

	# Allocate remaining height to the scroll area
	var final_body_h: float = final_popup_h - header_h
	if final_body_h < 0.0:
		final_body_h = 0.0
	_scroll.custom_minimum_size.y = final_body_h

	# Scroll only when needed
	var needs_scroll: bool = desired_popup_h > max_h
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if needs_scroll else ScrollContainer.SCROLL_MODE_DISABLED

func _on_close_button_pressed():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	hide()
	modulate.a = 1.0
