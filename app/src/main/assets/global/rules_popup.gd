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

func _ready() -> void:
	# Close button behavior is owned by the popup
	_close.pressed.connect(queue_free)
	get_viewport().size_changed.connect(_refresh_layout)

	# Required label settings for measuring height reliably
	_rules.bbcode_enabled = true
	_rules.visible = true
	_rules.fit_content = true
	_rules.scroll_active = false
	_rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Scroll container defaults
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

func open(title_text: String, rules_bbcode: String) -> void:
	_title.text = title_text
	_rules.text = rules_bbcode

	# Let layout settle so wrapping + content height are correct
	call_deferred("_open_deferred")

func _open_deferred() -> void:
	# Two frames is the most reliable way to ensure content height is correct
	await get_tree().process_frame
	await get_tree().process_frame
	_refresh_layout()

	# Center on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	position = (viewport_size / 2.0) - (size / 2.0)

	# Optional: animate in (owned by popup)
	pivot_offset = size / 2.0
	scale = Vector2.ZERO
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	grab_focus()

func _refresh_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var desired_w: float = viewport_size.x * width_ratio
	var max_h: float = viewport_size.y * max_height_ratio

	# Force the popup width first so text wraps correctly for height measurement
	size.x = desired_w
	_panel.custom_minimum_size.x = desired_w

	# Re-measure after width is set (wrapping changes height)
	# (One frame is often enough here, but keep it deterministic without more awaits.)
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
