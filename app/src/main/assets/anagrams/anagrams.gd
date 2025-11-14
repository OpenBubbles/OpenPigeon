extends Control

@export var letters: String = "PLANET"	# 6–7 letters depending on mode

@onready var picked_row: HBoxContainer = %VoidBox
@onready var letter_row: HBoxContainer = %LetterBox
@onready var enter_button: Button = %EnterButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: Control = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var background: ColorRect = %Background
@onready var win_loss_label: Label = %WinLossLabel
@onready var spec_label: Label = %SpecLabel

var selected_indices: Array[int] = []	# indices into `letters`
var source_buttons: Array[Button] = []
var picked_buttons: Array[Button] = []


func _ready() -> void:
	_create_source_buttons()
	_create_picked_slots()
	_update_ui()


func _create_source_buttons() -> void:
	# Clear any existing children (if you had some in the scene)
	for child in letter_row.get_children():
		child.queue_free()

	source_buttons.clear()

	for i in letters.length():
		var btn := Button.new()
		btn.text = letters[i]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_source_letter_pressed.bind(i))
		letter_row.add_child(btn)
		source_buttons.append(btn)


func _create_picked_slots() -> void:
	# One slot per letter (you can clamp to a fixed max if you want)
	for child in picked_row.get_children():
		child.queue_free()

	picked_buttons.clear()

	for i in letters.length():
		var btn := Button.new()
		btn.text = ""
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = true	# empty slot not clickable
		btn.pressed.connect(_on_picked_slot_pressed.bind(i))
		picked_row.add_child(btn)
		picked_buttons.append(btn)


func _on_source_letter_pressed(letter_index: int) -> void:
	# If this letter is already used up, ignore
	if letter_index in selected_indices:
		return

	# Optional: enforce a max picked length (e.g., same as number of letters)
	if selected_indices.size() >= letters.length():
		return

	selected_indices.append(letter_index)
	_update_ui()


func _on_picked_slot_pressed(slot_index: int) -> void:
	# Only react if this slot actually has a letter
	if slot_index >= selected_indices.size():
		return

	# Remove that letter and shift everything left automatically
	selected_indices.remove_at(slot_index)
	_update_ui()


func _update_ui() -> void:
	# Update picked row
	for i in picked_buttons.size():
		var btn := picked_buttons[i]
		if i < selected_indices.size():
			var letter_index := selected_indices[i]
			btn.text = letters[letter_index]
			btn.disabled = false
		else:
			btn.text = ""
			btn.disabled = true

	# Update source letters (disable those already picked)
	for i in source_buttons.size():
		var src_btn := source_buttons[i]
		src_btn.disabled = i in selected_indices

	# Enable Enter button only when 3+ letters are picked
	enter_button.disabled = selected_indices.size() < 3
