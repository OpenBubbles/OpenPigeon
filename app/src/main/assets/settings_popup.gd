extends PanelContainer
class_name SettingsPopup

signal closed
signal settings_theme_selected(new_theme_name: String)

# --- Existing Nodes ---
@onready var settings_label = %SettingsLabel as Label
@onready var theme_option_button = %ThemeOptionButton as OptionButton

# --- New Avatar Customizer Nodes ---
@onready var avatar_preview = %AvatarPreview as TextureRect
@onready var avatar_tab_container = %AvatarTabContainer as TabBar
@onready var properties_box = %PropertiesBox as VBoxContainer
@onready var custom_settings_container = %CustomSettingsContainer as VBoxContainer

var dim_rect: ColorRect # Reference to the dimming ColorRect

# Constants for the customizer
const ICON_SVG_PATH = "res://icon.svg" # Assuming icon.svg is in your project root

# Store a reference to the brightness slider for updating its gradient
var current_brightness_slider: HSlider = null


# --- Main Functions ---

func _ready():
	print("SettingsPopup: _ready() called.")
	_setup_theme_button()
	_setup_avatar_customizer()

func close_popup():
	print("SettingsPopup: Closing popup.")
	var tween = create_tween()
	tween.tween_property(self, "position", Vector2(position.x, get_viewport_rect().size.y), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		emit_signal("closed")
		queue_free()
		if is_instance_valid(dim_rect):
			dim_rect.queue_free()
	)

# --- Theme Setup ---

func _setup_theme_button():
	if theme_option_button:
		print("SettingsPopup: ThemeOptionButton found at path: ", theme_option_button.get_path())
		theme_option_button.clear()
		theme_option_button.item_selected.connect(_on_theme_option_button_item_selected)
		theme_option_button.add_item("Default", 0)
		theme_option_button.add_item("Default (Dark)", 1)
		theme_option_button.add_item("Penguin", 2)
		theme_option_button.add_item("Penguin (Dark)", 3)

		var saved_theme = SettingsManager.get_setting("global", "theme", "Default")
		for i in range(theme_option_button.item_count):
			if theme_option_button.get_item_text(i) == saved_theme:
				theme_option_button.select(i)
				break
	else:
		printerr("SettingsPopup: ERROR! ThemeOptionButton not found.")

func _on_theme_option_button_item_selected(index: int):
	var selected_theme_name = theme_option_button.get_item_text(index)
	print("SettingsPopup: Theme selected: ", selected_theme_name)
	settings_theme_selected.emit(selected_theme_name)
	SettingsManager.set_setting("global", "theme", selected_theme_name)

# --- Avatar Customizer Logic ---

func _setup_avatar_customizer():
	if avatar_tab_container and properties_box and avatar_preview:
		print("SettingsPopup: Avatar customizer nodes found and assigned.")
		print("  AvatarTabContainer path: ", avatar_tab_container.get_path())
		print("  PropertiesBox path: ", properties_box.get_path()) # Will reflect new path
		print("  AvatarPreview path: ", avatar_preview.get_path())

		# Connect the tab selection signal
		avatar_tab_container.tab_changed.connect(_on_avatar_tab_changed)
		print("SettingsPopup: Connected tab_changed signal.")

		# Add all the tabs FIRST
		avatar_tab_container.add_tab("Background")
		avatar_tab_container.add_tab("Skin")
		avatar_tab_container.add_tab("Hair")
		avatar_tab_container.add_tab("Face")
		avatar_tab_container.add_tab("Clothing")
		avatar_tab_container.add_tab("Accessories")
		print("SettingsPopup: Added avatar tabs.") # This print now happens after all tabs are added

		# Set the default tab to "Hair" (index 2)
		# This line will emit tab_changed(2) automatically,
		# triggering _on_avatar_tab_changed and populating the box.
		avatar_tab_container.current_tab = 2
		print("SettingsPopup: Set current_tab to index 2 (Hair). This should trigger _on_avatar_tab_changed.")

		# Initial update for the avatar preview based on saved settings
		_update_avatar_preview()
	else:
		printerr("SettingsPopup: ERROR! One or more avatar customizer nodes not found.")
		if not avatar_tab_container: printerr("  - AvatarTabContainer is null.")
		if not properties_box: printerr("  - PropertiesBox is null. CHECK NEW PATH!")
		if not avatar_preview: printerr("  - AvatarPreview is null.")

func _on_avatar_tab_changed(tab_index: int):
	print("SettingsPopup: _on_avatar_tab_changed called. Tab index: ", tab_index)
	if not is_instance_valid(properties_box):
		printerr("SettingsPopup: ERROR! properties_box is not valid when _on_avatar_tab_changed is called.")
		return

	# Clear out any controls from the previously selected tab
	var children_to_remove = properties_box.get_children()
	if not children_to_remove.is_empty():
		print("SettingsPopup: Clearing ", children_to_remove.size(), " existing properties from PropertiesBox.")
		for child in children_to_remove:
			child.queue_free()
	else:
		print("SettingsPopup: PropertiesBox was already empty.")

	# Reset brightness slider reference
	current_brightness_slider = null

	# Populate the properties box based on the new tab
	var tab_name = avatar_tab_container.get_tab_title(tab_index)
	print("SettingsPopup: Populating properties for tab: ", tab_name)
	match tab_name:
		"Background":
			_populate_background_properties()
		"Skin":
			_populate_skin_properties()
		"Hair":
			_populate_hair_properties()
		"Face":
			_populate_face_properties()
		"Clothing":
			_populate_clothing_properties()
		"Accessories":
			_populate_accessories_properties()

	# After populating, let's check what's actually in properties_box
	if properties_box:
		print("SettingsPopup: PropertiesBox children after populating tab '", tab_name, "':")
		if properties_box.get_child_count() > 0:
			for child in properties_box.get_children():
				print("  - Child: ", child.name, " (Type: ", child.get_class(), ")")
		else:
			print("  - No children found in PropertiesBox after populating.")
	else:
		printerr("SettingsPopup: PropertiesBox is still null after _on_avatar_tab_changed. This should not happen if _setup_avatar_customizer passed.")


func _update_avatar_preview():
	print("Updating avatar preview based on saved settings...")
	var background_color = SettingsManager.get_setting("avatar_background", "color", Color.GRAY)
	
	# Apply brightness if it's a background setting
	var background_brightness = SettingsManager.get_setting("avatar_background", "brightness", -1.0)
	if background_brightness != -1.0: # -1.0 is our sentinel for "not set" or "not applicable"
		# CORRECTED LINE: Access h, s, v directly as properties
		background_color = Color.from_hsv(background_color.h, background_color.s, background_brightness)
		print("Applying brightness ", background_brightness, " to background color. New color: ", background_color)

	if avatar_preview:
		avatar_preview.self_modulate = background_color
		print("AvatarPreview self_modulate set to: ", background_color)
	else:
		printerr("SettingsPopup: ERROR! AvatarPreview is null during _update_avatar_preview.")

	# Update the brightness slider's gradient if it exists and we're on the background tab
	if is_instance_valid(current_brightness_slider):
		_update_brightness_slider_gradient(background_color)

func _on_avatar_setting_changed(category: String, key: String, value):
	var section = "avatar_" + category
	SettingsManager.set_setting(section, key, value)
	print("SettingsPopup: Avatar setting changed: %s/%s = %s" % [section, key, value])
	_update_avatar_preview()


# --- Property Population Functions ---
# Each function below creates the UI for one tab.

func _populate_background_properties():
	print("SettingsPopup: Populating background properties.")

	var default_color = SettingsManager.get_setting("avatar_background", "color", Color("#4e5d89"))

	# 1. Preset Color Dots (removed label)
	_create_color_dot_presets("background", "color", [
		Color("#FF0000"), Color("#FFA500"), Color("#FFFF00"), Color("#008000"), Color("#0000FF"),
		Color("#4B0082"), Color("#EE82EE"), Color("#FFFFFF"), Color("#000000"), Color("#808080"), Color("#A52A2A")
	], default_color)

	# 2. Brightness Slider (removed label)
	# CORRECTED LINE: Access v directly for the initial brightness value
	var initial_brightness = SettingsManager.get_setting("avatar_background", "brightness", default_color.v)
	_create_horizontal_slider("Brightness", "background", "brightness", initial_brightness, 0.0, 1.0, 0.01)


	# 3. Image Presets (removed label)
	_create_image_presets_scrollbar("background", "image_preset", [
		ICON_SVG_PATH, # Sample image 1
		ICON_SVG_PATH, # Sample image 2
		ICON_SVG_PATH, # Sample image 3
		ICON_SVG_PATH, # Sample image 4
		ICON_SVG_PATH, # Sample image 5
		ICON_SVG_PATH, # Sample image 6
		ICON_SVG_PATH, # Sample image 7
		ICON_SVG_PATH, # Sample image 8
		ICON_SVG_PATH, # Sample image 9
		ICON_SVG_PATH  # Sample image 10
	])


func _populate_skin_properties():
	print("SettingsPopup: Populating skin properties.")
	var default_color = SettingsManager.get_setting("avatar_skin", "color", Color("#e0ac69"))
	_create_color_picker("Tone", "skin", "color", default_color)
	_create_filler_label("Skin Property 1: Freckles (Filler)")
	_create_filler_label("Skin Property 2: Tattoos (Filler)")

func _populate_hair_properties():
	print("SettingsPopup: Populating hair properties.")
	var hair_styles = ["Spiky", "Long", "Bun", "Bald"]
	var default_style = SettingsManager.get_setting("avatar_hair", "style", "Spiky")
	_create_option_button("Style", "hair", "style", hair_styles, default_style)

	var default_color = SettingsManager.get_setting("avatar_hair", "color", Color("#2c232b"))
	_create_color_picker("Color", "hair", "color", default_color)
	_create_filler_label("Hair Property 1: Length (Filler)")
	_create_filler_label("Hair Property 2: Highlights (Filler)")

func _populate_face_properties():
	print("SettingsPopup: Populating face properties.")
	var eye_styles = ["Open", "Closed", "Winking"]
	var default_eyes = SettingsManager.get_setting("avatar_face", "eyes", "Open")
	_create_option_button("Eyes", "face", "eyes", eye_styles, default_eyes)

	var mouth_styles = ["Smile", "Frown", "Neutral"]
	var default_mouth = SettingsManager.get_setting("avatar_face", "mouth", "Smile")
	_create_option_button("Mouth", "face", "mouth", mouth_styles, default_mouth)
	_create_filler_label("Face Property 1: Nose (Filler)")
	_create_filler_label("Face Property 2: Eyebrows (Filler)")

func _populate_clothing_properties():
	print("SettingsPopup: Populating clothing properties.")
	var shirt_styles = ["T-Shirt", "Sweater", "Tank Top"]
	var default_shirt = SettingsManager.get_setting("avatar_clothing", "shirt", "T-Shirt")
	_create_option_button("Shirt", "clothing", "shirt", shirt_styles, default_shirt)

	var default_color = SettingsManager.get_setting("avatar_clothing", "shirt_color", Color("#a03c3c"))
	_create_color_picker("Shirt Color", "clothing", "shirt_color", default_color)
	_create_filler_label("Clothing Property 1: Pants (Filler)")
	_create_filler_label("Clothing Property 2: Shoes (Filler)")

func _populate_accessories_properties():
	print("SettingsPopup: Populating accessories properties.")
	var glasses_styles = ["None", "Reading", "Sun Glasses"]
	var default_glasses = SettingsManager.get_setting("avatar_accessories", "glasses", "None")
	_create_option_button("Glasses", "accessories", "glasses", glasses_styles, default_glasses)
	_create_filler_label("Accessories Property 1: Hat (Filler)")
	_create_filler_label("Accessories Property 2: Necklace (Filler)")

# --- Helper Functions to Create UI Controls ---

# Helper to wrap any control in a PanelContainer with white background and add to properties_box
func _add_property_to_box(control_to_wrap: Control):
	var panel_container = PanelContainer.new()
	# Create a custom stylebox for the white background
	var stylebox_flat = StyleBoxFlat.new()
	stylebox_flat.bg_color = Color(1, 1, 1, 0.1) # White with slight transparency
	stylebox_flat.border_width_left = 1
	stylebox_flat.border_width_top = 1
	stylebox_flat.border_width_right = 1
	stylebox_flat.border_width_bottom = 1
	stylebox_flat.border_color = Color(1, 1, 1, 0.2) # Light border
	stylebox_flat.corner_radius_top_left = 5
	stylebox_flat.corner_radius_top_right = 5
	stylebox_flat.corner_radius_bottom_left = 5
	stylebox_flat.corner_radius_bottom_right = 5
	stylebox_flat.set_content_margin(SIDE_LEFT, 10)
	stylebox_flat.set_content_margin(SIDE_RIGHT, 10)
	stylebox_flat.set_content_margin(SIDE_TOP, 5)
	stylebox_flat.set_content_margin(SIDE_BOTTOM, 5)
	panel_container.add_theme_stylebox_override("panel", stylebox_flat)

	panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL # Make the background fill horizontally
	properties_box.add_child(panel_container) # Add panel_container to properties_box
	panel_container.add_child(control_to_wrap) # Add the actual control inside the panel_container

func _create_label(text: String):
	var label = Label.new()
	label.text = text
	properties_box.add_child(label)

func _create_option_button(label_text: String, category: String, key: String, options: Array, default_value):
	print("  Creating OptionButton for: ", label_text)
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label = Label.new()
	label.text = label_text + ":"

	var option_btn = OptionButton.new()
	option_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in options:
		option_btn.add_item(item)

	var item_index = options.find(default_value)
	if item_index != -1:
		option_btn.select(item_index)

	option_btn.item_selected.connect(func(index):
		_on_avatar_setting_changed(category, key, option_btn.get_item_text(index))
	)

	hbox.add_child(label)
	hbox.add_child(option_btn)
	_add_property_to_box(hbox) # Wrap in PanelContainer

func _create_color_picker(label_text: String, category: String, key: String, default_color: Color):
	print("  Creating ColorPicker for: ", label_text)
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label = Label.new()
	label.text = label_text + ":"

	var color_picker = ColorPickerButton.new()
	color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_picker.color = default_color

	color_picker.color_changed.connect(func(new_color):
		_on_avatar_setting_changed(category, key, new_color)
	)

	hbox.add_child(label)
	hbox.add_child(color_picker)
	_add_property_to_box(hbox) # Wrap in PanelContainer

func _create_filler_label(text: String):
	print("  Creating Filler Label: ", text)
	var label = Label.new()
	label.text = text
	properties_box.add_child(label)


# --- NEW CUSTOMIZER CONTROL FUNCTIONS ---

# Function to create horizontal color dots
func _create_color_dot_presets(category: String, key: String, colors: Array[Color], default_color: Color):
	var hbox_main = HBoxContainer.new()
	hbox_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_main.alignment = HBoxContainer.ALIGNMENT_CENTER # Center the dots
	hbox_main.add_theme_constant_override("separation", 8) # Space between dots

	for color_value in colors:
		var btn = Button.new() # Using a button for click detection easily
		btn.custom_minimum_size = Vector2(28, 28) # Slightly larger than dot
		btn.flat = true
		btn.mouse_filter = Control.MOUSE_FILTER_PASS # Allow clicks to pass to the button
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER # Let buttons shrink and center

		var color_rect = ColorRect.new()
		color_rect.custom_minimum_size = Vector2(24, 24) # Size of the dot
		color_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL # Fill the button
		color_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL # Fill the button
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # So button gets click

		# Create a custom stylebox for the circle
		var stylebox_flat = StyleBoxFlat.new()
		stylebox_flat.bg_color = color_value
		# Set individual border widths
		stylebox_flat.border_width_left = 2
		stylebox_flat.border_width_top = 2
		stylebox_flat.border_width_right = 2
		stylebox_flat.border_width_bottom = 2
		# Set individual corner radii using properties for a perfect circle
		stylebox_flat.corner_radius_top_left = 12
		stylebox_flat.corner_radius_top_right = 12
		stylebox_flat.corner_radius_bottom_left = 12
		stylebox_flat.corner_radius_bottom_right = 12
		color_rect.add_theme_stylebox_override("panel", stylebox_flat)

		btn.add_child(color_rect)
		
		# Set an identifier for the button to access the color
		btn.set_meta("preset_color", color_value)
		btn.pressed.connect(func():
			var selected_color = btn.get_meta("preset_color")
			_on_avatar_setting_changed(category, key, selected_color)
			# You might want to update the border of the selected dot here
			_update_selected_color_dot_border(hbox_main, selected_color)
		)
		hbox_main.add_child(btn)

	_add_property_to_box(hbox_main) # Wrap in PanelContainer

# Helper to update border of selected color dot
func _update_selected_color_dot_border(parent_hbox: HBoxContainer, selected_color: Color):
	for child in parent_hbox.get_children():
		if child is Button and child.has_meta("preset_color"):
			var color_rect = child.get_child(0) as ColorRect # Assuming ColorRect is first child
			if color_rect:
				# Retrieve the current stylebox to modify it
				var stylebox_flat = color_rect.get_theme_stylebox("panel") as StyleBoxFlat
				if stylebox_flat:
					if child.get_meta("preset_color") == selected_color:
						stylebox_flat.border_color = Color(0.2, 0.8, 0.2, 0.9) # Highlight with green
						# Set individual border widths
						stylebox_flat.border_width_left = 3
						stylebox_flat.border_width_top = 3
						stylebox_flat.border_width_right = 3
						stylebox_flat.border_width_bottom = 3
					else:
						stylebox_flat.border_color = Color(1, 1, 1, 0.5) # Default border
						# Set individual border widths
						stylebox_flat.border_width_left = 2
						stylebox_flat.border_width_top = 2
						stylebox_flat.border_width_right = 2
						stylebox_flat.border_width_bottom = 2
					# Reapply the modified stylebox (important!)
					color_rect.add_theme_stylebox_override("panel", stylebox_flat)


# Function to create a horizontal slider for brightness
func _create_horizontal_slider(label_text: String, category: String, key: String, initial_value: float, min_value: float, max_value: float, step: float):
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label = Label.new()
	label.text = label_text + ":"
	hbox.add_child(label)

	var slider = HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = initial_value
	slider.value_changed.connect(func(new_val):
		# This will update the 'brightness' key. You'll need logic in _update_avatar_preview
		# to apply this brightness to the background color.
		_on_avatar_setting_changed(category, key, new_val)
	)
	hbox.add_child(slider)

	# Store reference to this slider if it's the brightness slider
	if key == "brightness":
		current_brightness_slider = slider
		# Initial gradient setup for the slider
		_update_brightness_slider_gradient(SettingsManager.get_setting("avatar_background", "color", Color.GRAY))

	_add_property_to_box(hbox) # Wrap in PanelContainer

# NEW: Function to update the HSlider's gradient based on the selected color
func _update_brightness_slider_gradient(base_color: Color):
	if not is_instance_valid(current_brightness_slider):
		return

	# 1. Create the Gradient object
	var gradient = Gradient.new()
	gradient.add_point(0.0, base_color.darkened(1.0)) # Start from black (fully darkened)
	gradient.add_point(1.0, base_color) # End with the current base color

	# 2. Create a GradientTexture2D from the Gradient
	var gradient_texture = GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 256 # A reasonable width for the texture
	gradient_texture.height = 1  # For a horizontal gradient

	# 3. Create a StyleBoxTexture to apply the GradientTexture2D
	var grabber_area_style = StyleBoxTexture.new()
	grabber_area_style.texture = gradient_texture
	# REMOVED: grabber_area_style.margin_left = 5
	# REMOVED: grabber_area_style.margin_right = 5
	# Keep using expand_margin for padding around the texture within the stylebox
	grabber_area_style.expand_margin_left = 5 # Changed from 2 to 5 for consistency with original intent
	grabber_area_style.expand_margin_right = 5 # Changed from 2 to 5 for consistency with original intent
	grabber_area_style.expand_margin_top = 2
	grabber_area_style.expand_margin_bottom = 2
	# If you want rounded corners, you'd need to use a nine-patch texture for borders,
	# or overlay a StyleBoxFlat for the border *over* this.
	# For simplicity, we'll keep it rectangular with texture.
	
	# Override the "grabber_area" style of the HSlider
	current_brightness_slider.add_theme_stylebox_override("grabber_area", grabber_area_style)

	# Keep the "bar_bg" as a StyleBoxFlat for consistent background
	var bar_bg_style = StyleBoxFlat.new()
	bar_bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.5) # A dark background
	bar_bg_style.border_width_left = 1
	bar_bg_style.border_width_top = 1
	bar_bg_style.border_width_right = 1
	bar_bg_style.border_width_bottom = 1
	bar_bg_style.border_color = Color(0.3, 0.3, 0.3, 0.5)
	bar_bg_style.corner_radius_top_left = 5
	bar_bg_style.corner_radius_top_right = 5
	bar_bg_style.corner_radius_bottom_left = 5
	bar_bg_style.corner_radius_bottom_right = 5
	current_brightness_slider.add_theme_stylebox_override("bar_bg", bar_bg_style)

# Function to create image presets with a horizontal scrollbar
func _create_image_presets_scrollbar(category: String, key: String, image_paths: Array[String]):
	var scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.custom_minimum_size = Vector2(0, 70) # Give it some height for the images
	
	var hbox_images = HBoxContainer.new()
	hbox_images.add_theme_constant_override("separation", 10) # Space between images
	hbox_images.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hbox_images.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var default_texture = load(ICON_SVG_PATH) # Load once

	for i in range(image_paths.size()):
		var img_path = image_paths[i]
		var texture = load(img_path) if ResourceLoader.exists(img_path) else default_texture

		var texture_button = TextureButton.new()
		texture_button.texture_normal = texture
		# ADJUSTED: Smaller image size
		texture_button.custom_minimum_size = Vector2(48, 48) # Smaller size
		texture_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		texture_button.set_meta("image_index", i) # Store index for selection

		var stylebox_flat = StyleBoxFlat.new()
		stylebox_flat.bg_color = Color(0,0,0,0) # Transparent background
		stylebox_flat.border_width_left = 2
		stylebox_flat.border_width_top = 2
		stylebox_flat.border_width_right = 2
		stylebox_flat.border_width_bottom = 2
		stylebox_flat.border_color = Color(0.2, 0.6, 1.0, 0.7) # Blue border
		stylebox_flat.corner_radius_top_left = 5
		stylebox_flat.corner_radius_top_right = 5
		stylebox_flat.corner_radius_bottom_left = 5
		stylebox_flat.corner_radius_bottom_right = 5
		texture_button.add_theme_stylebox_override("focus", stylebox_flat) # Show on focus
		texture_button.add_theme_stylebox_override("hover", stylebox_flat) # Show on hover

		texture_button.pressed.connect(func():
			_on_avatar_setting_changed(category, key, texture_button.get_meta("image_index")) # Save image index
		)
		hbox_images.add_child(texture_button)

	scroll_container.add_child(hbox_images)
	_add_property_to_box(scroll_container) # Wrap in PanelContainer

# --- Popup Management (Unchanged from your original) ---

func _exit_tree():
	print("SettingsPopup: _exit_tree() called.")
	if is_instance_valid(dim_rect):
		dim_rect.queue_free()

func setup_popup(dimmer: ColorRect):
	print("SettingsPopup: setup_popup() called with dimmer: ", dimmer.name if is_instance_valid(dimmer) else "null")
	dim_rect = dimmer
	if is_instance_valid(dim_rect):
		dim_rect.gui_input.connect(_on_dim_rect_gui_input)

func _on_dim_rect_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close_popup()

func add_custom_setting(control_node: Control):
	print("SettingsPopup: add_custom_setting() called with node: ", control_node.name if is_instance_valid(control_node) else "INVALID_NODE")
	if custom_settings_container:
		custom_settings_container.add_child(control_node)
		custom_settings_container.queue_sort()
	else:
		printerr("SettingsPopup: ERROR! custom_settings_container is null when trying to add custom setting.")
