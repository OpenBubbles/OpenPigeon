extends Control

# ——————————————
# Mancala Game State
# ——————————————
@export var player: int     = 0     # 0 = bottom, 1 = top
@export var is_my_turn: bool = true
@export var mode: String = ""     # "n", "h", "an", or "ah"
const PIT_COUNT: int = 14

# Changed to track individual stone labels for each pit
var pits: Array = [] # Each element is an array of stone labels
var pit_nodes: Array[Area2D] = []
var spawn_points: Array[Marker2D] = []

# Parsed board labels: Array of Array[int]
var board_labels: Array = []
# Parsed moves: Array of Array[float]
var replay_moves: Array = []

# Scenes
var PitScene    : PackedScene = preload("res://mancala/Pit.tscn")
var StoneScene : PackedScene = preload("res://mancala/Stone.tscn")

# UI References
@onready var rules_button    = $BottomItemHBoxContainer/MarginContainer/RulesButton
@onready var settings_button = $BottomItemHBoxContainer/MarginContainer/SettingsButton
@onready var turn_label      = $MarginContainer/InfoHBoxContainer/TurnLabel
@onready var pits_root       = $MarginContainer/InfoHBoxContainer/GameAreaCenterContainer/PitsContainer

const RULES_POPUP_SCENE = preload("res://mancala/RulesPopup.tscn")

# --- New Animation Variables ---
var _carrying_stones_container: Node2D = Node2D.new() # A temporary container for stones being carried
const STONE_DROP_DELAY = 0.1 # Time to pause after dropping each stone
const PIT_PICKUP_LIFT_Y = -50 # How much the pit lifts when picked up
const PIT_PICKUP_TIME = 0.2 # How long it takes for the pit to lift
const PILE_TRAVEL_TIME = 0.2 # Time for the entire pile to move between pits

# --- Helper to prevent multiple clicks during animation ---
var _is_animating: bool = false

func _debug_pit_input_layers() -> void:
	for pit in pit_nodes:
		print("=== Pit", pit.index, "layers ===")
		for node in pit.get_children():
			var info = ""
			if node is CollisionShape2D:
				info = "CollisionShape2D, disabled=%s" % node.disabled
			elif node is Area2D:
				info = "Area2D, pickable=%s" % node.input_pickable
			elif node is Control:
				info = "Control, mouse_filter=%d" % node.mouse_filter
			else:
				info = "%s (%s)" % [node.get_class(), node.visible if node.has_method("is_visible") else ""]
			print("    ", node.name, "→", info)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Unhandled Click at: ", event.position)

func _ready() -> void:
	_init_mancala_board()
	for pit in pit_nodes:
		for node in pit.get_children():
			if node is Control and node.name != "DebugRect":
				node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_pit_input_layers()
	_start_pit_highlights()
	if rules_button:
		rules_button.pressed.connect(on_rules_button_pressed)
	if settings_button:
		settings_button.pressed.connect(on_settings_button_pressed)

	# Add the carrying stones container to the scene
	add_child(_carrying_stones_container)
	_carrying_stones_container.z_index = 100 # Ensure it draws on top of everything

	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin and not appPlugin.is_connected("set_game_data", Callable(self, "_set_game_data")):
		appPlugin.connect("set_game_data", Callable(self, "_set_game_data"))
		appPlugin.onReady()
	# Dev: preload a sample game state when running in editor
	if Engine.is_editor_hint():
		print("[DEV] Editor hint active, loading sample game data")
		var dev_data = {
			"sender": ["7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX"],
			"version": ["5"],
			"tver": ["5"],
			"ios": ["18.5"],
			"caption": ["Let's play Mancala!"],
			"subcaption": ["Capture Mode"],
			"id": ["ziadBSjDYgc4ruev"],
			"player": ["2"],
			"player2": ["7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX"],
			"replay": ["board:2,3,2,3&2,1,3,2&1,1,3,3&2,3,3,1&2,2,3,3&3,2,2,2&&12,13,13,13&13,11,12,13&12,11,12,12&11,11,11,12&11,12,13,13&13,11,11,13&|move:2,4,1|board:..."],
			"mode": ["n"]
		}
		_set_game_data(dev_data)

func _init_mancala_board() -> void:
	randomize()
	for i in range(PIT_COUNT):
		var pit = PitScene.instantiate() as Area2D
		pit.index = i
		var dbg = Label.new()
		dbg.add_theme_font_size_override("font_size", 18)
		dbg.modulate = Color(1, 0, 0)
		dbg.position = Vector2(0, 0)
		pit.add_child(dbg)
		if i == 6 or i == 13:
			pit.scale = Vector2(2, 1)
			var cs = pit.get_node("CollisionShape2D") as CollisionShape2D
			var rect_shape = RectangleShape2D.new()
			rect_shape.extents = Vector2(100, 40)
			cs.shape = rect_shape
		pit.connect("pit_clicked", Callable(self, "_on_pit_clicked"))
		pits_root.add_child(pit)
		pit_nodes.append(pit)
		spawn_points.append(pit.get_node("SpawnPoint") as Marker2D)
	var offsets: Array[Vector2] = [
		Vector2(-271, -342), Vector2(-271, -251), Vector2(-271, -158),
		Vector2(-271,  -67), Vector2(-271,   24), Vector2(-271,  116),
		Vector2(-226,  210),
		Vector2(-173,  116), Vector2(-173,   24), Vector2(-173,  -67),
		Vector2(-173, -158), Vector2(-173, -251), Vector2(-173, -342),
		Vector2(-226, -438)
	]
	for i in range(PIT_COUNT): pit_nodes[i].position = offsets[i]

	pits.clear()
	for i in range(PIT_COUNT):
		if i == 6 or i == 13: # Store pits start empty
			pits.append([]) # Append an empty array for store pits
		else:
			var initial_stones: Array[int] = []
			var base_label = 0
			if i >= 0 and i <= 5: # Pits 0-5 (bottom player's side)
				base_label = 1 # Stone labels for player 0: 1 (white), 2 (black), 3 (blue)
			elif i >= 7 and i <= 12: # Pits 7-12 (top player's side)
				base_label = 11 # Stone labels for player 1: 11 (white), 12 (black), 13 (blue)

			for _k in range(4): # Each non-store pit starts with 4 stones
				# Assign colors cyclically (e.g., 1, 2, 3, 1 for player 0; 11, 12, 13, 11 for player 1)
				initial_stones.append(base_label + (_k % 3)) 
			pits.append(initial_stones)
			
	_refresh_all_pits()

func _start_pit_highlights() -> void:
	for pit in pit_nodes:
		(pit.get_node("HighlightCircle") as ColorRect).visible = false
	var first = 0 if player == 0 else 7
	var last  = 5 if player == 0 else 12
	for i in range(first, last + 1):
		var hl = pit_nodes[i].get_node("HighlightCircle") as ColorRect
		hl.visible = true
		var mat = hl.material as ShaderMaterial
		mat.set_shader_parameter("alpha_fade", 0.0)
		var tw = hl.create_tween()
		tw.set_loops()
		tw.tween_property(mat, "shader_parameter/alpha_fade", 0.3, 0.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(mat, "shader_parameter/alpha_fade", 0.0, 0.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_pit_clicked(idx: int) -> void:
	if _is_animating: # Prevent multiple clicks during animation
		return

	print("Pit clicked: ", idx)
	if not is_my_turn:
		print("Not your turn.")
		return
	# Check if the clicked pit belongs to the current player and is not a store pit
	if (player == 0 and (idx < 0 or idx > 5)) or (player == 1 and (idx < 7 or idx > 12)):
		print("Cannot click opponent's pit or a store pit.")
		return
	if pits[idx].size() == 0: # Check if the pit is empty (using .size() for Array[Array[int]])
		print("Cannot click an empty pit.")
		return

	print("[INPUT] Pit clicked:", idx)
	_is_animating = true # Set animation flag

	# --- Start Pit Pickup Animation ---
	var clicked_pit = pit_nodes[idx]
	var original_pit_pos = clicked_pit.position
	
	# Lift the pit visually
	var tween_lift = create_tween()
	if tween_lift == null:
		push_error("tween_lift is null! Cannot animate pit lift.")
		_is_animating = false
		return
	tween_lift.tween_property(clicked_pit, "position", original_pit_pos + Vector2(0, PIT_PICKUP_LIFT_Y), PIT_PICKUP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween_lift.finished # Wait for the pit to lift

	is_my_turn = false # Disable further clicks now that animation is starting
	await _sow_from(idx) # Await the sowing animation

	# --- Return Pit to Original Position after sowing ---
	var tween_return = create_tween()
	if tween_return == null:
		push_error("tween_return is null! Cannot animate pit return.")
		_is_animating = false
		return
	tween_return.tween_property(clicked_pit, "position", original_pit_pos, PIT_PICKUP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween_return.finished

	_end_turn()
	_is_animating = false # Reset animation flag

	# Print the new array at the end of each click
	print("Final Board State after click:")
	for i in range(PIT_COUNT):
		print("Pit ", i, ": ", pits[i])

func _sow_from(start_idx: int) -> void:
	# Use pits[start_idx].size() to get the count of stones by labels
	var stones_to_sow_initial_count = pits[start_idx].size()
	var start_pit_node = pit_nodes[start_idx]
	var start_container = start_pit_node.get_node("StonesContainer") as Node2D

	# 1. Prepare stones for carrying - get actual stone labels
	# Duplicate the array of labels from the starting pit
	var carried_stone_labels: Array = pits[start_idx].duplicate()
	
	# Clear the original pit's *visuals* immediately and update its label
	# The actual 'pits' array will be cleared after duplicating 'carried_stone_labels'
	for c in start_container.get_children():
		c.queue_free()
	pits[start_idx].clear() # Clear the original pit's labels
	_refresh_pit_count_label(start_idx) # Update source pit label to 0

	# Create visual stone nodes for carrying. These will be children of _carrying_stones_container
	var carried_visual_stones: Array[Node2D] = []
	for stone_label in carried_stone_labels:
		var s = StoneScene.instantiate() as Node2D
		s.scale = Vector2(0.15, 0.15)
		s.modulate = _get_color_from_label(stone_label) # Use the actual stone's color
		# Position stones relative to the carrying container's center for a pile effect
		s.position = Vector2(randf_range(-5, 5), randf_range(-5, 5))
		_carrying_stones_container.add_child(s)
		carried_visual_stones.append(s)

	# 2. Position the carrying container at the starting pit's lifted position
	# The _carrying_stones_container should start at the *original* pit's lifted position,
	# then travel. The pit itself is already lifted from _on_pit_clicked.
	_carrying_stones_container.global_position = start_pit_node.global_position 
	_carrying_stones_container.global_position.y += PIT_PICKUP_LIFT_Y
	
	var current_idx = start_idx
	
	# Loop while there are stones visually in the _carrying_stones_container
	while carried_visual_stones.size() > 0:
		current_idx = (current_idx + 1) % PIT_COUNT
		
		# Skip opponent's store pit
		if (player == 0 and current_idx == 13) or (player == 1 and current_idx == 6):
			continue

		var target_pit_node = pit_nodes[current_idx]
		# The target global position for the entire carrying pile
		# This should align with the *already lifted* pit position
		var target_global_position_for_pile = target_pit_node.global_position
		target_global_position_for_pile.y += PIT_PICKUP_LIFT_Y

		# Create a NEW tween for each segment of the pile's movement
		var segment_tween = create_tween()
		if segment_tween == null:
			push_error("segment_tween is null during movement! Aborting sowing animation.")
			break # Exit loop to prevent further errors
		
		# Animate the entire carrying container to the next pit
		segment_tween.tween_property(_carrying_stones_container, "global_position", target_global_position_for_pile, PILE_TRAVEL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await segment_tween.finished # Wait for this segment of pile movement to finish

		# Drop one stone animation
		var stone_to_drop_visual = carried_visual_stones.pop_front() as Node2D # Get the first visual stone from the carrying pile
		
		# Get the label of the stone being dropped (from the original sequence)
		var dropped_stone_label = carried_stone_labels.pop_front() # Get the label from the original sequence

		if stone_to_drop_visual:
			# Reparent the visual stone to the target pit's StonesContainer
			stone_to_drop_visual.reparent(target_pit_node.get_node("StonesContainer"))

			var drop_tween = create_tween()
			if drop_tween == null:
				push_error("drop_tween is null during drop! Stone will appear instantly.")
				# If tween fails, still add stone to pit data and free visual stone
				stone_to_drop_visual.queue_free()
			else:
				var original_stone_local_pos = stone_to_drop_visual.position
				# Target position for the stone *within* the pit's local coordinate space
				var drop_target_local_pos = spawn_points[current_idx].position + Vector2(randf_range(-5, 5), randf_range(-5, 5))
				
				# Animate a small bounce up, then drop down into the pit
				drop_tween.tween_property(stone_to_drop_visual, "position", original_stone_local_pos + Vector2(0, 20), STONE_DROP_DELAY/2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				drop_tween.tween_property(stone_to_drop_visual, "position", drop_target_local_pos, STONE_DROP_DELAY/2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				await drop_tween.finished

			# Update game state: Add the stone's label to the end of the target pit's array
			pits[current_idx].append(dropped_stone_label)
			# Only update the pit's count label; _refresh_all_pits will handle full stone re-rendering
			_refresh_pit_count_label(current_idx) 

			# Brief pause after dropping a stone before moving to the next pit
			if carried_visual_stones.size() > 0: # Only if more stones are left to sow
				await get_tree().create_timer(STONE_DROP_DELAY / 2.0).timeout

	# 4. After all stones are distributed, clear the carrying container (it should be empty visually)
	for c in _carrying_stones_container.get_children():
		c.queue_free()
	
	# 5. Finally, refresh all pits to ensure correct state and physical stone rendering
	_refresh_all_pits()

func _end_turn() -> void:
	player = 1 - player
	_update_turn_label()

func _refresh_all_pits() -> void:
	for i in range(PIT_COUNT): _refresh_pit(i)

# This function is responsible for clearing all existing stone visuals
# and re-instantiating them based on the current `pits[i]` array of labels.
func _refresh_pit(i: int) -> void:
	var pit = pit_nodes[i]
	var container = pit.get_node("StonesContainer") as Node2D
	
	# Clear old stones
	for c in container.get_children():
		c.queue_free()
	
	# Instantiate new stones based on labels in pits[i]
	for stone_label in pits[i]: # Iterate through the array of stone labels
		var s = StoneScene.instantiate()
		s.scale = Vector2(0.15, 0.15)
		s.modulate = _get_color_from_label(stone_label) # Set color based on label
		s.position = spawn_points[i].position + Vector2(
			randf_range(-5, 5),
			randf_range(-5, 5)
		)
		container.add_child(s)
	
	_refresh_pit_count_label(i) # Ensure label is always updated

# New helper function to get color from stone label
func _get_color_from_label(label: int) -> Color:
	match label:
		1, 11: return Color.WHITE
		2, 12: return Color.BLACK
		3, 13: return Color.BLUE
		_: return Color(randf_range(0.8,1), randf_range(0.8,1), randf_range(0.8,1)) # Fallback for unknown labels

# New function to only refresh the count label
func _refresh_pit_count_label(i: int) -> void:
	var pit = pit_nodes[i]
	var lbl = pit.get_node("CountLabel") as Label
	lbl.text = str(pits[i].size()) # Get the count from the size of the labels array
	lbl.get_parent().force_update_transform()
	var lw = lbl.get_minimum_size().x
	var lh = lbl.get_minimum_size().y
	var base = spawn_points[i].position
	const OFFX = 5
	const OFFY = 10
	const Mx = 50
	const My = 50
	if i == 6 or i == 13: # Houses
		lbl.scale = Vector2(0.5, 1) # Only scale label for houses
		if i == 6: # Player 0's house (right side of their pits)
			lbl.position = base + Vector2(-Mx - lw/2 + OFFX*2,  My - lh/2 - OFFY)
		else: # Player 1's house (left side of their pits)
			lbl.position = base + Vector2( Mx - lw/2 - OFFX, -My - lh/2 + OFFY)
	else: # Regular pits
		lbl.scale = Vector2(1,1) # Ensure regular pits don't have scaled labels
		if i < 6: # Player 0's pits
			lbl.position = base + Vector2(-Mx - lw/2,        -lh/2)
		else: # Player 1's pits
			lbl.position = base + Vector2( Mx - lw/2,        -lh/2)


func _place_stone(container: Node2D, base_pos: Vector2, label: int) -> void:
	# This function is deprecated and no longer used in the animated sowing.
	pass

func _update_turn_label() -> void:
	if turn_label:
		turn_label.text = "Your Turn" if is_my_turn else "Opponent's Turn"
	else:
		push_error("turn_label is null! Cannot update turn label.")


# ——————————————
# Game Data Parsing
# ——————————————
func _set_game_data(raw: Dictionary) -> void:
	print("[PARSE] Raw game data received:", raw)
	var parsed = parse_game_data(raw)
	mode = parsed.mode
	print("[PARSE] Mode:", mode)
	
	pits.clear() # Clear existing pits data before parsing new data
	for _i in range(PIT_COUNT):
		pits.append([]) # Initialize each pit with an empty array of stone labels

	# Use first board for initial layout
	if parsed.boards.size() > 0:
		board_labels = parsed.boards[0]
		print("[PARSE] Parsed", parsed.boards.size(), "boards; first board labels:", board_labels)
		# Set pit contents by assigning the array of labels directly
		for i in range(min(board_labels.size(), PIT_COUNT)):
			pits[i] = board_labels[i].duplicate() # Assign the array of labels directly
		_refresh_all_pits()
	else:
		push_warning("_set_game_data: no boards parsed")
	
	# If a second board exists, assume it's post-move and apply
	if parsed.boards.size() > 1:
		print("[PARSE] Applying post-move board")
		var post = parsed.boards[1]
		for i in range(min(post.size(), PIT_COUNT)):
			pits[i] = post[i].duplicate() # Assign the array of labels
		_refresh_all_pits()

	# If moves exist, log them (could animate here)
	if parsed.moves.size() > 0:
		replay_moves = parsed.moves
		print("[PARSE] Parsed moves:", replay_moves)
	
	# Turn and player
	if raw.has("isYourTurn"): is_my_turn = raw["isYourTurn"][0].to_bool()
	if raw.has("player"): player = int(raw["player"][0]) - 1
	_update_turn_label()

func parse_game_data(raw: Dictionary) -> Dictionary:
	var out = {"mode": null, "boards": [], "moves": []}
	if raw.has("mode"):
		out.mode = str(raw["mode"][0])
	else:
		push_error("parse_game_data: no mode field!")
	if raw.has("replay"):
		var replay_str = str(raw["replay"][0])
		print("[PARSE] Replay string:", replay_str)
		for chunk in replay_str.strip_edges().split("|"):
			if chunk.begins_with("board:"):
				var data = chunk.substr(6)
				out.boards.append(_parse_single_board(data))
			elif chunk.begins_with("move:"):
				var mv = []
				for v in chunk.substr(5).split(","):
					if v != "": mv.append(float(v))
				out.moves.append(mv)
	else:
		push_warning("parse_game_data: no replay field!")
	return out

func _parse_single_board(data: String) -> Array:
	var pit_list = []
	for pit_str in data.split("&"):
		if pit_str == "":
			pit_list.append([]) # Append an empty array for empty pits
		else:
			var arr = []
			for lbl in pit_str.split(","):
				if lbl != "": arr.append(int(lbl))
			pit_list.append(arr)
	return pit_list

func on_rules_button_pressed() -> void:
	var popup = RULES_POPUP_SCENE.instantiate()
	var dim   = ColorRect.new()
	dim.color = Color(0,0,0,0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	add_child(popup)
	move_child(dim, get_child_count() - 2)

	var close_btn = popup.get_node("MarginContainer/PanelContainer/VBoxContainer/HeaderMarginContainer/CloseButton")
	if close_btn:
		close_btn.pressed.connect(func():
			dim.queue_free()
			popup.queue_free()
		)

	await get_tree().process_frame
	var size = get_viewport_rect().size
	popup.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	popup.set_as_top_level(true)
	popup.visible = true
	popup.size = Vector2(size.x, 10)
	await get_tree().process_frame

	var final_h = popup.get_combined_minimum_size().y
	popup.position = Vector2(size.x/2, (size.y - final_h)/2)
	popup.size      = Vector2(0, final_h)

	var tween = create_tween()
	tween.tween_property(popup, "size:x", size.x, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(popup, "position:x", 0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	popup.grab_focus()


func on_settings_button_pressed() -> void:
	show_toast_notification("Feature Coming Soon")


func show_toast_notification(message: String, duration: float=2.0) -> void:
	var toast = Label.new()
	toast.text = message
	toast.add_theme_font_size_override("font_size", 28)
	toast.add_theme_color_override("font_color", Color.WHITE)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0,0,0,0.7)
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.content_margin_left      = 20
	style.content_margin_right  = 20
	style.content_margin_top      = 10
	style.content_margin_bottom = 10
	toast.add_theme_stylebox_override("normal", style)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast.position.y -= 150
	toast.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
	toast.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	toast.modulate.a = 0.0
	add_child(toast)

	var tw_toast = create_tween()
	tw_toast.tween_property(toast, "modulate:a", 1.0, 0.3)
	tw_toast.tween_interval(duration)
	tw_toast.tween_property(toast, "modulate:a", 0.0, 0.5)
	tw_toast.tween_callback(toast.queue_free)
