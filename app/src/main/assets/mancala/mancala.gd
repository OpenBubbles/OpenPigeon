extends Control

# ——————————————
# Mancala Game State
# ——————————————
var player_str: int     = 2
var player: int     = 1     # 1 = bottom, 2 = top
var is_your_turn: bool = false
var is_my_turn: bool = false
var spectator_mode: bool = false
var mode: String = ""     # "n", "h", "an", or "ah"
var my_player: String = ""
const PIT_COUNT: int = 14
var _last_sown_pit: int = -1
var has_connected: bool = false
var offsets: Array[Vector2]
var _board_initialized: bool = false
var game_over: bool = false
var in_replay: bool = false
const BASE_STONE_SCALE := Vector2(0.1, 0.1)
var win_loss_state: String = ""
var winner_id = -1
var disp_winner = false
var _skip_replay_animation = false # New flag to control replay skipping

# Changed to track individual stone labels for each pit
var pits: Array = [] # Each element is an array of stone labels
var pit_nodes: Array[Area2D] = []
var spawn_points: Array[Marker2D] = []

# Parsed board labels: Array of Array[int]
var board_labels: Array = []
# Parsed moves: Array of Array[float]
var replay_moves: Array = []

# Scenes
var PitScene    : PackedScene = preload("res://mancala/pit.tscn")
var StoreScene  : PackedScene = preload("res://mancala/store.tscn")
var StoneScene : PackedScene = preload("res://mancala/stone.tscn")

# UI References
@onready var rules_button    = $BottomItemHBoxContainer/MarginContainer/RulesButton
@onready var settings_button = $BottomItemHBoxContainer/MarginContainer/SettingsButton
@onready var sent_label = $MarginContainer/InfoHBoxContainer/GameAreaCenterContainer/SentLabel
@onready var waiting_label = $WaitingContainer/WaitForOpponentLabel
@onready var waiting_blur = $WaitBlur
@onready var dot_timer = $DotTimer
@onready var background = $Background
@onready var win_loss_label = $MarginContainer/InfoHBoxContainer/GameAreaCenterContainer/WinLossLabel
@onready var pits_root       = $MarginContainer/InfoHBoxContainer/GameAreaCenterContainer/PitsContainer
@onready var free_turn_label = $MarginContainer/InfoHBoxContainer/GameAreaCenterContainer/FreeTurnLabel
@onready var skip_button = $MarginContainer/InfoHBoxContainer/GameAreaCenterContainer/SkipButton
@onready var spec_label = $MarginContainer/SpecLabel

const RULES_POPUP_SCENE = preload("res://mancala/RulesPopup.tscn")

# --- New Animation Variables ---
var _carrying_stones_container: Node2D = Node2D.new() # A temporary container for stones being carried
const STONE_DROP_DELAY = 0.1 # Time to pause after dropping each stone
const PIT_PICKUP_TIME = 0.3 # How long it takes for the pit to lift
const PILE_TRAVEL_TIME = 0.35 # Time for the entire pile to move between pits
const BOUNCE_SCALE_FACTOR = 1.3 # Stones will scale to 120% of their base size
const BOUNCE_DURATION = 0.01 # Duration for the initial bounce at pickup (for the very first pickup)
var dot_count: int = 0
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"
var sent_tween: Tween

# --- Helper to prevent multiple clicks during animation ---
var _is_animating: bool = false
var moves_made: Array = []  # store moves as "player,pit" per turn
var prev_board_str: String = ""  # will hold the prior board snapshot

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
	_init_mancala_board_structure()
	var appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin: 
		print("AppPlugin Available")
		if not has_connected:
			appPlugin.connect("set_game_data", _set_game_data)
			has_connected = true
			appPlugin.onReady()
			print("AppPlugin Connected")
	# Dev: preload a sample game state when running in editor
	else:
		print("[DEV] Editor hint active, loading sample game data")
		var dev_data = '{"isYourTurn": true,"mode": "n","player": "1","replay": "board:2,3,2,3&2,1,3,2&1,1,3,3&2,3,3,1&12&3,2,2,2&12&12,13,13,13&11,12,13,11&12,11,12,12,13&11,11,11,12,11&11,12,1,2,3,1,2,3,1,2,3,1,2,3,1,2,3,1,2,3&13,11,11,13,13&11|move:2,4|board:2,3,2,3&2,1,3,2&1,1,3,3&2,3,3,1&12&3,2,2,2&12&12,13,13,13&11,12,13,11&12,11,12,12,13&11,11,11,12,11&&13,11,11,13,13,11&11,12","sender":"7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX","version": "5","tver": "5","ios": "18.5","subcaption": "Capture Mode","id": "ziadBSjDYgc4ruev","player2": "7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX"}'
		#var dev_data = '{"isYourTurn": true,"mode": "n","player": "2","replay": "board:2,3,2,3&&&&&&1,2,3,1,2,3,11,12,13,11,12,13,1,2,3,1,2,3,11,12,13,11,12,13&13,12,13,13,13&12&&&&13,11,11,13&1,2,3,1,2,3,11,12,13,1|move:2,6|board:2,3,2,3&&&&&&1,2,3,1,2,3,11,12,13,11,12,13,1,2,3,1,2,3,11,12,13,11,12,13&12,13,13,13&12,13&&&&13,11,11,13&1,2,3,1,2,3,11,12,13,1","sender":"7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX","version": "5","tver": "5","ios": "18.5","subcaption": "Capture Mode","id": "ziadBSjDYgc4ruev","player2": "7482724F-04A2-4917-9EB3-8857DD4D44EAP3AIzX"}'
		_set_game_data(dev_data)
	for pit in pit_nodes:
		for node in pit.get_children():
			if node is Control and node.name != "DebugRect":
				node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	#_debug_pit_input_layers()
	if rules_button:
		rules_button.pressed.connect(on_rules_button_pressed)
	if settings_button:
		settings_button.pressed.connect(on_settings_button_pressed)
	if skip_button: # Always good practice to check if the node exists
		skip_button.pressed.connect(_on_skip_button_pressed)

	# Add the carrying stones container to the scene
	add_child(_carrying_stones_container)
	_carrying_stones_container.z_index = 100 # Ensure it draws on top of everything
	
# ——————————————
# Game Data Parsing
# ——————————————
func _set_game_data(raw_text: String) -> void:
	var res = JSON.parse_string(raw_text)
	print("NEW REPLAY: " + str(res))

	print("[PARSE] Raw game data received:", res)

	# basic flags
	player_str = int(res.get("player", player))
	mode = String(res.get("mode", mode))
	my_player = String(res.get("myPlayerId", my_player))
	var sender_id = res.get("sender", "")
	var player1_id: String = res.get("player1", "")
	var player2_id: String = res.get("player2", "")
	#game_over = true if res.get("winner", "") != "" else false # Keep this commented out as per previous logic
	winner_id = res.get("winner", "")
	print("Winner State is: ", winner_id, " | With Game Over State being: ", game_over)
	print("Player Parsed Val: ", player_str, " SENDER: ", sender_id, " PLAYER1ID: ",player1_id, " PLAYER2ID: ",player2_id)
	is_your_turn = res.get("isYourTurn", false)
	if is_your_turn and (my_player == player1_id or my_player == player2_id or player1_id == ""):
		is_my_turn = true
		player = 1 if (player_str == 2 and is_my_turn) else 2
		print("Current Player Number post: ", player, " MY PLAYER ID: ", my_player)
	else:
		print("Spectator mode activated")
		spectator_mode = true
		spec_label.visible = true
		player = 1
		print("Current Player Number pre: ", player, " MY PLAYER ID: ", my_player)
	#is_my_turn = is_your_turn
	print("YOUR TURN?: ", is_your_turn, " MY TURN?: ", is_my_turn, " Spectator Mode: ", spectator_mode)
	
	print("SET GAME MODE: ", mode)
	
	print("Set Mode: ", mode)
	if mode == "an" or mode == "ah":
		print("MODE IS AVALANCHE")
		background.color = Color("#704b4a")
	else:
		print("MODE IS CAPTURE")
		background.color = Color("#6d7c82")
	# grab the replay string
	var replay_str: String = String(res.get("replay", ""))
	
	# Ensure the board structure and layout are applied before parsing specific board states
	_apply_board_layout(is_my_turn)

	# parse boards/moves/raw_boards
	var parsed = parse_game_data(replay_str)

	# --- MODIFICATION START ---
	# Determine the initial board state for this replay. This is the state *before* the moves in `replay_moves`.
	var initial_board_for_replay_str = ""
	var rb: Array = parsed.get("raw_boards", [])
	if rb.size() > 0:
		initial_board_for_replay_str = rb[0]
	else:
		push_warning("_set_game_data: no initial board state found for replay.")

	# Clear and rebuild pits
	pits.clear()
	for i in range(PIT_COUNT):
		pits.append([])
	print("Setting up the board with INITIAL_BOARD_STATE for the replay")
	# Set up the board with the INITIAL_BOARD_STATE for this replay
	if initial_board_for_replay_str != "":
		var initial_board_data = _parse_single_board(initial_board_for_replay_str)
		for i in range(min(initial_board_data.size(), PIT_COUNT)):
			pits[i] = initial_board_data[i].duplicate()
		_refresh_all_pits() # Visually update the board to this state
	else:
		push_warning("_set_game_data: no previous board state found for replay, using default setup.")

	print("Capturing And Animating Moves (If Present)")
	# Capture and animate moves if present
	if parsed.moves.size() > 0:
		replay_moves = parsed.moves
		print("[PARSE] Parsed moves:", replay_moves)
		_is_animating = true # Set animation flag to prevent clicks during replay
		# Animate each move in sequence
		
		# Enable the skip button only during replay animation
		skip_button.visible = true # Assuming skip_button is a Node reference

		for i in range(replay_moves.size()): # Use index to access corresponding raw_board
			if _skip_replay_animation:
				print("Replay animation skipped by user.")
				break # Exit the replay loop early
				
			var move_data = replay_moves[i]
			var replay_player = int(move_data[0]) # Get the player who made this move in replay
			var replay_pit_offset = int(move_data[1])
			var actual_pit_idx = replay_pit_offset
			if replay_player == 2: # Convert player 2's relative pit index to absolute for our fixed layout
				actual_pit_idx += 7
			
			print("Replaying move: Player ", replay_player, ", Pit offset ", replay_pit_offset, " (Actual pit ", actual_pit_idx, ")")
			
			# Temporarily set the 'player_str' (current_sow_player in _sow_from) to the replaying player
			var original_player_str_for_sow = player_str
			player_str = replay_player # This is the key change for replay's _sow_from
			
			in_replay = true
			# We need to pass the skip flag to _sow_from or ensure _sow_from checks it internally
			await _sow_from(actual_pit_idx) 
			in_replay = false
			
			# After sowing, check if the last stone landed in the current sowing player's store
			var current_sow_player_store_idx = 6 if player_str == 1 else 13
			if _last_sown_pit == current_sow_player_store_idx:
				print("DEBUG: Replay - Player ", player_str, " got a free turn!")
				free_turn_label.text = "Free Turn!"
				free_turn_label.visible = true
				var free_turn_tween = create_tween()
				free_turn_tween.tween_interval(0.8) # Show for a moment
				free_turn_tween.tween_callback(func(): free_turn_label.visible = false)
				await free_turn_tween.finished # Wait for the label to disappear before next move
			
			player_str = original_player_str_for_sow # Restore global player_str
			
		# After the replay loop (either completed or broken by skip)
		skip_button.visible = false # Hide the skip button
		_is_animating = false # Reset animation flag after replay
		

		# If replay was skipped, or finished, set the board to the final state (rb[1])
		# This is crucial for skipped replays to show the final board immediately.
		if rb.size() > 1: # Ensure post_board exists
			var final_board_data = _parse_single_board(rb[rb.size() - 1]) # Get the last board state
			for k in range(min(final_board_data.size(), PIT_COUNT)):
				pits[k] = final_board_data[k].duplicate()
			if _skip_replay_animation:
				_refresh_all_pits() # Update visuals to the final state
			print("Board updated to final state from raw_boards after replay (or skip).")
		else:
			push_warning("_set_game_data: No final board state (rb[1]) available for post-replay update.")
		_skip_replay_animation = false
		# Update the global prev_board_str to reflect the board state *after* the replay.
		prev_board_str = rb[rb.size() - 1] if rb.size() > 0 else "" # Use the last available board state
		print("UPDATED prev_board_str AFTER REPLAY: ", prev_board_str)
	elif rb.size() > 0:
		# If there are no moves, but there's a board string in the replay (e.g., initial state from server),
		# it means the board is simply initialized to that state.
		# So, that state becomes the prev_board_str for the next move.
		prev_board_str = rb[0]
		print("UPDATED prev_board_str (no moves in replay): ", prev_board_str)
	# --- MODIFICATION END ---

	# If it's your turn, start highlights. Otherwise, start waiting animation.
	await _check_game_over_and_winner()
	if is_my_turn and not game_over:
		_start_pit_highlights()
		stop_waiting_animation()
	elif not is_my_turn and not game_over:
		start_waiting_animation() # Assuming you have this function to show "Waiting for opponent"

func parse_game_data(raw: String) -> Dictionary:
	var out = {
		"boards": [],      # Array of Array[int]
		"moves": [],       # Array of Array[float]
		"raw_boards": []   # Array of String
	}

	for chunk in raw.strip_edges().split("|"):
		if chunk.begins_with("board:"):
			var board_str = chunk.substr(6)
			out["raw_boards"].append(board_str)
			out["boards"].append(_parse_single_board(board_str))
		elif chunk.begins_with("move:"):
			var mv: Array = []
			for s in chunk.substr(5).split(","):
				if s != "":
					mv.append(float(s))
			out["moves"].append(mv)

	return out

func _parse_single_board(data: String) -> Array:
	var pit_list = []
	for pit_str in data.split("&"):
		if pit_str == "":
			pit_list.append([])
		else:
			var arr = []
			for lbl in pit_str.split(","):
				if lbl != "": arr.append(int(lbl))
			pit_list.append(arr)
	return pit_list
	
func _on_plugin_set_game_data(raw_text: String) -> void:
	# Immediately hop onto the main thread
	call_deferred("_set_game_data", raw_text)

func _init_mancala_board_structure() -> void:
	randomize()
	for i in range(PIT_COUNT):
		var pit: Area2D
		if i == 6 or i == 13: # These are the store pits
			pit = StoreScene.instantiate() as Area2D
			pit.name = "Store%d" % i
		else:
			pit = PitScene.instantiate() as Area2D
			pit.name = "Pit%d" % i
		pit.index = i
		pit.connect("pit_clicked", Callable(self, "_on_pit_clicked"))
		pits_root.add_child(pit)
		pit_nodes.append(pit)
		spawn_points.append(pit.get_node("SpawnPoint") as Marker2D)
		var debug_label = pit.find_child("Debug_num")
		if debug_label and debug_label is Label:
			debug_label.text = str(i)
		else:
			print("No Label for Debug!")
		
	pits.clear()
	for i in range(PIT_COUNT):
		pits.append([])

	print("Mancala board structure initialized.")
	dot_timer.timeout.connect(_on_dot_timer_timeout)

func _apply_board_layout(is_current_turn: bool) -> void:
	# This function applies the layout and initial stone setup based on player info.
	print("YOU ARE PLAYER: ", player)
	if player == 1:
		offsets = [
			Vector2(125, 171.5), Vector2(125, 262.5), Vector2(125, 355.5),
			Vector2(125, 446.5), Vector2(125, 537.5), Vector2(125, 629.5),
			Vector2(170, 723.5), # Store
			Vector2(223, 629.5), Vector2(223, 537.5), Vector2(223, 446.5),
			Vector2(223, 355.5), Vector2(223, 262.5), Vector2(223, 171.5),
			Vector2(170, 75.5) # Store
		]
	elif player == 2:
		offsets = [
			Vector2(223, 629.5), Vector2(223, 537.5), Vector2(223, 446.5),
			Vector2(223, 355.5), Vector2(223, 262.5), Vector2(223, 171.5),
			Vector2(170, 75.5), # Store
			Vector2(125, 171.5), Vector2(125, 262.5), Vector2(125, 355.5),
			Vector2(125, 446.5), Vector2(125, 537.5), Vector2(125, 629.5),
			Vector2(170, 723.5) # Store
		]
	else:
		print("Cannot Setup Board!! (Player or turn info missing)")
		# You might want a default layout or error handling here

	# Apply positions to the already instantiated pit_nodes
	for i in range(PIT_COUNT):
		if i < pit_nodes.size() and i < offsets.size(): # Safety check
			pit_nodes[i].position = offsets[i]

	for i in range(PIT_COUNT):
		if i == 6 or i == 13: # Store pits start empty
			pits[i] = [] # Ensure store pits are empty
		else:
			var initial_stones: Array[int] = []
			var base_label = 0
			if i >= 0 and i <= 5: # Pits 0-5 (bottom player's side)
				base_label = 1 # Stone labels for player 0: 1 (white), 2 (black), 3 (blue)
			elif i >= 7 and i <= 12: # Pits 7-12 (top player's side)
				base_label = 11 # Stone labels for player 1: 11 (white), 12 (black), 13 (blue)

			for _k in range(4): # Each non-store pit starts with 4 stones
				initial_stones.append(base_label + (_k % 3))
			pits[i] = initial_stones

	print("Board layout applied and initial stones set.")
	if is_my_turn:
		_start_pit_highlights()
		stop_waiting_animation()

func _start_pit_highlights() -> void:
	print("Starting Pit Highlights! Player: ", player)
	for pit in pit_nodes:
		(pit.get_node("HighlightCircle") as ColorRect).visible = false
	var first = 0 if player == 1 else 7
	var last  = 5 if player == 1 else 12
	for i in range(first, last + 1):
		var hl = pit_nodes[i].get_node("HighlightCircle") as ColorRect
		hl.visible = true
		var mat = hl.material as ShaderMaterial
		mat.set_shader_parameter("alpha_fade", 0.0)
		var tw = hl.create_tween()
		tw.set_loops()
		tw.tween_property(mat, "shader_parameter/alpha_fade", 0.2, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(mat, "shader_parameter/alpha_fade", 0.0, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			
func _stop_pit_highlights() -> void:
	print("Stopped Pit Highlights!!")
	for pit in pit_nodes:
		var hl = pit.get_node("HighlightCircle") as ColorRect
		hl.visible = false

func _on_pit_clicked(idx: int) -> void:
	if _is_animating: # Prevent multiple clicks during animation
		return
	if game_over: # Prevent clicks if game is already over
		print("Game is over. No more moves.")
		return
		
	_stop_pit_highlights()

	print("Pit clicked: ", idx)
	if not is_my_turn:
		print("Not your turn.")
		return
	# Check if the clicked pit belongs to the current player and is not a store pit
	var my_store_pit_idx = 6 if player_str == 1 else 13
	if ((player == 1 and (idx < 0 or idx > 5)) or (player == 2 and (idx < 7 or idx > 12))):
		print("Cannot click opponent's pit or a store pit.")
		_start_pit_highlights()
		return
	if pits[idx].size() == 0: # Check if the pit is empty
		print("Cannot click an empty pit.")
		_start_pit_highlights()
		return
		
	var pit_offset: int = idx if idx < 6 else idx - 7
	moves_made.append(str(player) + "," + str(pit_offset))

	print("[INPUT] Pit clicked:", idx)
	_is_animating = true # Set animation flag

	# --- Start Pit Pickup Animation (MODIFIED) ---
	var start_pit_node = pit_nodes[idx]
	_carrying_stones_container.global_position = start_pit_node.global_position # Set initial position

	# Animate container scale up for the "lift" effect
	var tween_pickup_scale = create_tween()
	tween_pickup_scale.set_parallel(true) # Allow parallel tweens for scale and position

	# Tween scale up
	tween_pickup_scale.tween_property(
		_carrying_stones_container, "scale",
		Vector2(1.2, 1.2), # Increase size by 20% for "raised" look
		PIT_PICKUP_TIME * 0.7 # Quicker initial pop-up
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Optional: Slight vertical shift for extra pop, if desired, but less crucial now
	# tween_pickup_scale.tween_property(
	# 	_carrying_stones_container, "global_position:y",
	# 	start_pit_node.global_position.y - 15, # Small upward hop
	# 	PIT_PICKUP_TIME * 0.7
	# ).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	await tween_pickup_scale.finished # Wait for the pickup effect to finish
	
	# Start the sowing process, which will handle avalanche logic internally
	await _sow_from(idx)

	var give_free_turn = false
	# Check for "Free Turn" rule (last stone lands in *your* store)
	if _last_sown_pit != -1: # Ensure a stone was actually sown
		if _last_sown_pit == 6 or _last_sown_pit == 13:
			give_free_turn = true
			print("DEBUG: Last stone landed in own store pit → free turn!")
		else:
			print("DEBUG: Last stone landed in pit ", _last_sown_pit, " (not a store pit for free turn).")
	else:
		print("DEBUG: No stone was sown (this shouldn't happen after _sow_from).")

	if give_free_turn:
		is_my_turn = true
		free_turn_label.text = "Free Turn."
		free_turn_label.visible = true
		var free_turn_tween = create_tween()
		free_turn_tween.tween_interval(1.0) # Show for 1 second
		free_turn_tween.tween_callback(func(): free_turn_label.visible = false)
	else:
		_end_turn() # No free turn, end the turn
		
	_is_animating = false # Reset animation flag
	if is_my_turn:
		_start_pit_highlights() # Re-enable highlights for the current player

func _sow_from(start_idx: int) -> void:
	var current_sowing_pit_idx = start_idx # Track the pit from which we are currently sowing
	var last_stone_landed_in_empty_pit = false # Flag for avalanche termination
	
	while true: # Loop for avalanche turns
		# Check for skip flag early in the loop
		if _skip_replay_animation:
			print("Sow from interrupted by skip button.")
			break # Exit this sow loop

		var current_sow_player = player_str # This 'player' variable is adjusted in _set_game_data during replay
		if not in_replay and is_my_turn: # If it's a local click, use player_str
			current_sow_player = player
		else:
			print("SOW STATS!!!!~~ IS ANIMATING: ", _is_animating, " IS MY TURN: ", is_my_turn, " CURRENT SOW PLAYER: ", current_sow_player, " IN_REPLAY: ", in_replay, " PLAYER_STR: ", player_str," PLAYER: ", player)


		# Check for game over condition here before picking up stones
		var player1_side_empty = true
		for i in range(0, 6): # Pits 0-5 for player 1's side
			if pits[i].size() > 0:
				player1_side_empty = false
				break
		var player2_side_empty = true
		for i in range(7, 13): # Pits 7-12 for player 2's side
			if pits[i].size() > 0:
				player2_side_empty = false
				break

		# If all pits on the *current sowing player's* side are empty, the game ends.
		if (current_sow_player == 1 and player1_side_empty) or (current_sow_player == 2 and player2_side_empty):
			print("GAME OVER: Current sowing player's pits are all empty before sowing from ", current_sowing_pit_idx)
			# Distribute remaining stones to the opponent's store
			var opponent_store_idx = 6 if current_sow_player == 2 else 13
			for i in range(PIT_COUNT):
				# Only sweep stones from the opponent's side
				var is_opponents_non_store_pit = (current_sow_player == 1 and i >= 7 and i <= 12) or \
												 (current_sow_player == 2 and i >= 0 and i <= 5)
				
				if is_opponents_non_store_pit:
					if pits[i].size() > 0:
						print("Moving ", pits[i].size(), " stones from pit ", i, " to opponent's store ", opponent_store_idx)
						pits[opponent_store_idx].append_array(pits[i])
						pits[i].clear()
						print("476 refresh count label call")
						_refresh_pit_count_label(i)
						_refresh_pit_count_label(opponent_store_idx)
			print("483 check game over")
			#await _check_game_over_and_winner() # Final check after distributing stones
			return # End sowing if game over

		if pits[current_sowing_pit_idx].size() == 0:
			# If we are starting a sow from an empty pit (can happen in avalanche mode),
			# this turn segment ends.
			last_stone_landed_in_empty_pit = true
			break
		
		var stones_to_sow = pits[current_sowing_pit_idx].size()
		if stones_to_sow == 0: # Should not happen if previous check passed, but good for safety
			last_stone_landed_in_empty_pit = true
			break
			
		var start_pit_node = pit_nodes[current_sowing_pit_idx]
		var start_container = start_pit_node.get_node("StonesContainer") as Node2D

		var carried_stone_labels: Array = pits[current_sowing_pit_idx].duplicate()
		
		# Clear the original pit's *visuals* immediately and update its label
		for c in start_container.get_children():
			c.queue_free()
		pits[current_sowing_pit_idx].clear() # Clear the original pit's labels
		print("502 refresh count label call")
		_refresh_pit_count_label(current_sowing_pit_idx) # Update source pit label to 0
		var current_idx = current_sowing_pit_idx # This will be the index where the last stone lands in this sow cycle
		var carried_visual_stones: Array[Node2D] = []
		for stone_label in carried_stone_labels:
			var s = StoneScene.instantiate() as Node2D
			s.scale = BASE_STONE_SCALE
			s.modulate = _get_color_from_label(stone_label)
			s.position = Vector2(randf_range(-5, 5), randf_range(-5, 5))
			_carrying_stones_container.add_child(s)
			carried_visual_stones.append(s)

		await get_tree().create_timer(0.01).timeout # A minimal delay (e.g., 0.01 seconds)
		print("DEBUG: pits_root global_position: ", pits_root.global_position)
		print("DEBUG: start_pit_node local position: ", start_pit_node.global_position, " Current Sowing Pit Index: ", current_sowing_pit_idx)
		_carrying_stones_container.global_position = start_pit_node.global_position
		print("DEBUG: Carrying container set to start pit position: ", _carrying_stones_container.global_position, " (start_pit_node global: ", start_pit_node.global_position, ")")
		
		# Animate the initial "raise" (scale up and down) at the pickup pit
		var pickup_tween = create_tween()
		if pickup_tween == null:
			push_error("pickup_tween is null during initial pickup! Aborting.")
			return

		# Scale up the carrying container to simulate stones raising
		pickup_tween.tween_property(_carrying_stones_container, "scale", Vector2(BOUNCE_SCALE_FACTOR, BOUNCE_SCALE_FACTOR), BOUNCE_DURATION / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		# Then scale it back down slightly, preparing for movement
		pickup_tween.tween_property(_carrying_stones_container, "scale", Vector2(1.0, 1.0), BOUNCE_DURATION / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await pickup_tween.finished # Wait for the initial bounce to complete before moving
		print("DEBUG: Carrying container position after pickup tween: ", _carrying_stones_container.global_position)
		
		# Animate the distribution of stones
		while carried_visual_stones.size() > 0:
			if _skip_replay_animation: # Check for skip flag inside the stone distribution loop
				print("Stone distribution interrupted by skip button.")
				# Clear any remaining visual stones in the carrying container if skipped mid-sow
				for c in _carrying_stones_container.get_children():
					c.queue_free()
				return # Exit the function immediately
				
			current_idx = (current_idx + 1) % PIT_COUNT
			
			# Skip opponent's store pit based on the current sowing player
			if (current_sow_player == 1 and current_idx == 13) or (current_sow_player == 2 and current_idx == 6):
				continue

			var target_pit_node = pit_nodes[current_idx]
			var target_global_position_for_pile = target_pit_node.global_position
			print("DEBUG: Moving to target pit ", current_idx, " at global position: ", target_global_position_for_pile)

			# --- Movement to the next pit with integrated bouncing ---
			var travel_tween = create_tween()
			if travel_tween == null:
				push_error("travel_tween is null during movement! Aborting sowing animation.")
				return
			
			# Animate position of the carrying container
			travel_tween.tween_property(_carrying_stones_container, "global_position", target_global_position_for_pile, PILE_TRAVEL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			
			# Set the tween to run the next property in parallel
			travel_tween.set_parallel(true)
			
			# Scale up during the first half of the travel
			travel_tween.tween_property(_carrying_stones_container, "scale", Vector2(BOUNCE_SCALE_FACTOR, BOUNCE_SCALE_FACTOR), PILE_TRAVEL_TIME / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			
			# Scale back down during the second half of the travel
			travel_tween.tween_property(_carrying_stones_container, "scale", Vector2(1.0, 1.0), PILE_TRAVEL_TIME / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(PILE_TRAVEL_TIME / 2.0)
			
			await travel_tween.finished
			print("DEBUG: Carrying container position after travel tween to pit ", current_idx, ": ", _carrying_stones_container.global_position)

			if _skip_replay_animation: # Check after tween finishes
				print("Stone distribution interrupted after travel by skip button.")
				for c in _carrying_stones_container.get_children():
					c.queue_free()
				return # Exit the function immediately

			var stone_to_drop_visual = carried_visual_stones.pop_front() as Node2D
			var dropped_stone_label = carried_stone_labels.pop_front()

			if stone_to_drop_visual:
				_carrying_stones_container.remove_child(stone_to_drop_visual)
				
				var drop_target_local_pos = spawn_points[current_idx].position + Vector2(randf_range(-15, 15), randf_range(-15, 15))
				
				# Add stone to target pit's visual container
				target_pit_node.get_node("StonesContainer").add_child(stone_to_drop_visual)
				stone_to_drop_visual.position = drop_target_local_pos # Position it correctly immediately
				stone_to_drop_visual.rotation_degrees = randf_range(0, 360)

				# Create and animate shadow
				var shadow = Sprite2D.new()
				shadow.texture = stone_to_drop_visual.texture
				shadow.modulate = Color(0, 0, 0, 0.3)
				shadow.position = drop_target_local_pos + Vector2(5, 5)
				shadow.z_index = -1
				target_pit_node.get_node("StonesContainer").add_child(shadow)

				# Add the stone label to the logical pit *before* checking for avalanche continuation
				pits[current_idx].append(dropped_stone_label)
				print("564 refresh count label call")
				_refresh_pit_count_label(current_idx)

				if carried_visual_stones.size() > 0:
					await get_tree().create_timer(STONE_DROP_DELAY / 2.0).timeout # Small delay between stone drops
					if _skip_replay_animation: # Check after short delay as well
						print("Stone distribution interrupted during delay by skip button.")
						for c in _carrying_stones_container.get_children():
							c.queue_free()
						return # Exit the function immediately

		_last_sown_pit = current_idx # Update the last sown pit for potential free turn/capture checks

		# Avalanche Mode Logic
		if mode == "an" or mode == "ah":
			print("Avalanche mode active. Last stone landed in pit: ", _last_sown_pit)
			var player_store_idx = 6 if current_sow_player == 1 else 13
			
			# If the last stone landed in the player's store, the turn ends (no further pick-up).
			if _last_sown_pit == player_store_idx:
				print("Avalanche ends: Last stone landed in player's store.")
				break # End the avalanche loop
			
			# If the last stone landed in an empty pit on *any* side, the turn ends.
			if pits[_last_sown_pit].size() == 1: # It became empty before we dropped the stone, now it has 1
				print("Avalanche ends: Last stone landed in an empty pit (now 1 stone).")
				last_stone_landed_in_empty_pit = true
				break # End the avalanche loop
			
			# Otherwise, pick up the stones from _last_sown_pit and continue
			print("Avalanche continues: Picking up stones from pit ", _last_sown_pit)
			if current_sowing_pit_idx == 6 or current_sowing_pit_idx == 13:
				break
			current_sowing_pit_idx = _last_sown_pit # Set the next pit to sow from
			# Do not break; the loop will continue to the next iteration
		else:
			# Normal/Hard mode capture logic (original logic)
			# This block only runs if not in avalanche mode

			# Determine if the last sown stone landed in a non-store pit
			var last_sown_pit_is_non_store = (_last_sown_pit >= 0 and _last_sown_pit <= 5) or (_last_sown_pit >= 7 and _last_sown_pit <= 12)

			# --- Define the capture conditions more precisely ---
			var should_capture = false

			# Case 1: Live game (not in replay)
			if not in_replay:
				# Player 1's turn, last stone landed on Player 1's side (pits 0-5) AND pit now has 1 stone
				if current_sow_player == 1 and _last_sown_pit >= 0 and _last_sown_pit <= 5 and pits[_last_sown_pit].size() == 1:
					should_capture = true
				# Player 2's turn, last stone landed on Player 2's side (pits 7-12) AND pit now has 1 stone
				elif current_sow_player == 2 and _last_sown_pit >= 7 and _last_sown_pit <= 12 and pits[_last_sown_pit].size() == 1:
					should_capture = true
			# Case 2: In replay mode
			else:
				# If it's Player 1's "turn" in replay, and they landed on their side (0-5) and pit now has 1 stone
				if current_sow_player == 1 and _last_sown_pit >= 0 and _last_sown_pit <= 5 and pits[_last_sown_pit].size() == 1:
					should_capture = true
				# If it's Player 2's "turn" in replay, and they landed on their side (7-12) and pit now has 1 stone
				elif current_sow_player == 2 and _last_sown_pit >= 7 and _last_sown_pit <= 12 and pits[_last_sown_pit].size() == 1:
					should_capture = true

			# --- Execute capture logic if conditions are met ---
			if should_capture:
				print("DEBUG: Capture condition met! Last stone landed in pit ", _last_sown_pit, " which was empty before this stone.")
				
				var opposite_pit_idx = -1
				if current_sow_player == 1: # Player 1's pits 0-5. Opposite pits 12-7.
					opposite_pit_idx = 12 - _last_sown_pit
				elif current_sow_player == 2: # Player 2's pits 7-12. Opposite pits 5-0.
					opposite_pit_idx = 12 - _last_sown_pit

				var player_store_idx = 6 if current_sow_player == 1 else 13

				if opposite_pit_idx != -1 and pits[opposite_pit_idx].size() > 0:
					print("DEBUG: Capturing stones from opposite pit ", opposite_pit_idx)
					
					# Collect stones to be captured (last sown stone + opposite pit's stones)
					var captured_stones = []
					if pits[_last_sown_pit].size() > 0:
						# Temporarily remove the last sown stone from the pit to add it to captured_stones
						captured_stones.append(pits[_last_sown_pit].pop_back())
					
					# Add all stones from the opposite pit to captured_stones
					captured_stones.append_array(pits[opposite_pit_idx])
					pits[opposite_pit_idx].clear() # Clear the opposite pit
					
					# --- Visual and UI feedback - only for the local player during live play ---
					# 'player' here refers to the local player ID
					print("DEBUG: Displaying 'Captured!' label for live player.")
					free_turn_label.text = "Captured!"
					free_turn_label.visible = true
					var free_turn_tween = create_tween()
					free_turn_tween.tween_interval(0.5) # Shorter display for quick feedback
					free_turn_tween.tween_callback(func(): free_turn_label.visible = false)
					free_turn_label.add_theme_color_override("font_color", Color(1, 1, 1)) # white text
					free_turn_label.add_theme_color_override("background_color", Color(1.0, 0.84, 0.0))

					# Visually move stones to the store (always animate during replay for accuracy)
					await _animate_capture(captured_stones, _last_sown_pit, opposite_pit_idx, player_store_idx)
					if _skip_replay_animation: # Check after capture animation as well
						print("Capture animation interrupted by skip button.")
						return # Exit the function immediately


					# Add captured stones to the player's store
					pits[player_store_idx].append_array(captured_stones)
					
					# Refresh pit counts (always refresh regardless of in_replay for accurate display)
					print("626 refresh count label call")
					_refresh_pit_count_label(_last_sown_pit)
					_refresh_pit_count_label(opposite_pit_idx)
					_refresh_pit_count_label(player_store_idx)
				else:
					print("DEBUG: Opposite pit ", opposite_pit_idx, " is empty or invalid. No capture.")
			break # End the sowing loop for non-avalanche modes
	
	# Clear the temporary container after all stones have been moved or captured
	# This should always run unless an early return due to skip happens
	for child in _carrying_stones_container.get_children():
		child.queue_free() # Ensure no residual nodes if something went wrong
	
	# Ensure the scale is reset to base after all animations are done
	_carrying_stones_container.scale = Vector2(1.0, 1.0) # Reset container's scale to normal
	
	await _check_game_over_and_winner()

func _animate_capture(stones_to_capture: Array, last_sown_pit_idx: int, opposite_pit_idx: int, player_store_idx: int) -> void:
	print("Animating capture of ", stones_to_capture.size(), " stones to store ", player_store_idx)
	
	var store_node = pit_nodes[player_store_idx]
	var store_container = store_node.get_node("StonesContainer") as Node2D

	var last_sown_pit_node = pit_nodes[last_sown_pit_idx]
	var opposite_pit_node = pit_nodes[opposite_pit_idx]
	
	# Collect visual stones from the last_sown_pit (should be just one)
	var visual_stones_from_last_sown = []
	var ls_container = last_sown_pit_node.get_node("StonesContainer")
	for child in ls_container.get_children():
		if child is Node2D: # Assuming your stones are Node2D based
			visual_stones_from_last_sown.append(child)
	
	# Collect visual stones from the opposite pit
	var visual_stones_from_opposite = []
	var opp_container = opposite_pit_node.get_node("StonesContainer")
	for child in opp_container.get_children():
		if child is Node2D:
			visual_stones_from_opposite.append(child)

	# Combine and clear from source pits
	var all_visual_stones_to_capture = visual_stones_from_last_sown + visual_stones_from_opposite
	
	for s_visual in visual_stones_from_last_sown:
		ls_container.remove_child(s_visual)
		_carrying_stones_container.add_child(s_visual) # Move to temporary container
		s_visual.global_position = last_sown_pit_node.global_position # Set global position
	
	for s_visual in visual_stones_from_opposite:
		opp_container.remove_child(s_visual)
		_carrying_stones_container.add_child(s_visual) # Move to temporary container
		s_visual.global_position = opposite_pit_node.global_position # Set global position
	
	print("681 refresh count label call")
	_refresh_pit_count_label(last_sown_pit_idx) # Update source pit labels to 0
	_refresh_pit_count_label(opposite_pit_idx)

	# Animate all stones moving together to the player's store
	var capture_tween = create_tween()
	if capture_tween == null:
		push_error("capture_tween is null during capture animation!")
		for s_visual in all_visual_stones_to_capture: # Clean up
			s_visual.queue_free()
		return

	# Move the temporary container to the target store's position
	# Using store_node's global position as the target for the _carrying_stones_container
	var target_global_pos_for_capture = store_node.global_position
	target_global_pos_for_capture.y

	capture_tween.tween_property(
		_carrying_stones_container, "global_position",
		target_global_pos_for_capture,
		PILE_TRAVEL_TIME * 1.5 # Make capture animation slightly longer
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	await capture_tween.finished

	# Once the container arrives, drop all stones into the store
	for s_visual in all_visual_stones_to_capture:
		if s_visual:
			_carrying_stones_container.remove_child(s_visual)
			store_container.add_child(s_visual)
			# Apply random position within the store, similar to other pits
			s_visual.position = spawn_points[player_store_idx].position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
			s_visual.rotation_degrees = randf_range(0, 360)
			
			# Re-add shadow for the captured stone
			var shadow = Sprite2D.new()
			shadow.texture = s_visual.texture
			shadow.modulate = Color(0, 0, 0, 0.3)
			shadow.scale = s_visual.scale * 1.05
			shadow.position = s_visual.position + Vector2(5, 5)
			shadow.z_index = -1
			store_container.add_child(shadow)
		await get_tree().create_timer(STONE_DROP_DELAY / (all_visual_stones_to_capture.size() + 1)).timeout # Stagger drops slightly
	
	# Clear the temporary container after all stones have been moved
	for child in _carrying_stones_container.get_children():
		child.queue_free() # Ensure no residual nodes if something went wrong
	
	print("Capture animation finished.")

func _end_turn() -> void:
	player = 1 if player==2 and not spectator_mode else 2
	free_turn_label.visible = false

	# Send the game state each time a turn ends
	send_game()

func _refresh_all_pits() -> void:
	for i in range(PIT_COUNT): _refresh_pit(i)

func _refresh_pit(i: int) -> void:
	var pit = pit_nodes[i]
	var container = pit.get_node("StonesContainer") as Node2D
	
	# Clear existing stones and shadows
	for c in container.get_children():
		c.queue_free()
	
	for stone_label in pits[i]:
		var s = StoneScene.instantiate() as Node2D
		s.scale = BASE_STONE_SCALE
		s.modulate = _get_color_from_label(stone_label)
		s.rotation_degrees = randf_range(0, 360) 
		
		# Offset position significantly to reduce overlap
		s.position = spawn_points[i].position + Vector2(
			randf_range(-20, 20), # Increased range
			randf_range(-20, 20)  # Increased range
		)
		
		container.add_child(s)

		# Create and add the shadow for each stone
		var shadow = Sprite2D.new()
		shadow.texture = s.texture # Assuming StoneScene is a Sprite2D with a texture
		shadow.modulate = Color(0, 0, 0, 0.3) # Dark, semi-transparent shadow
		shadow.scale = s.scale * 1.05 # Slightly larger than the stone
		shadow.position = s.position + Vector2(5, 5) # Offset from the stone for shadow effect
		shadow.z_index = s.z_index - 1 # Draw behind the actual stone
		container.add_child(shadow)

	print("772 refresh count label call")
	_refresh_pit_count_label(i)

func _get_color_from_label(label: int) -> Color:
	match label:
		1, 11: return Color("#fffcf2") # Creamy white
		2, 12: return Color("#414851") # Jet gray
		3, 13: return Color("#2196f3") # Bright blue (Google blue)
		_: return Color(randf_range(0.9, 1.0), randf_range(0.9, 1.0), randf_range(0.9, 1.0))

func _refresh_pit_count_label(i: int) -> void:
	var pit = pit_nodes[i]
	var lbl = pit.get_node("CountLabel") as Label
	lbl.text = str(pits[i].size())
	lbl.get_parent().force_update_transform()
	var lw = lbl.get_minimum_size().x
	var lh = lbl.get_minimum_size().y
	var base = spawn_points[i].position
	const OFFX = 40
	const OFFY = 10
	const Mx = 50
	const My = 50
	print("REFRESH COUNT:: PLAYER: ", player, " Pit Number: ", i, " In Replay?: ", in_replay)
	if player == 1:
		if i == 6 or i == 13:
			if i == 6:
				lbl.position = base + Vector2(-Mx - lw/2 - OFFX, My - lh/2 - OFFY)
			else:
				lbl.position = base + Vector2(Mx - lw/2 + OFFX, -My - lh/2 + OFFY)
		else:
			lbl.scale = Vector2(1,1)
			if i < 6:
				lbl.position = base + Vector2(-Mx - lw/2, -lh/2)
			else:
				lbl.position = base + Vector2(Mx - lw/2, -lh/2)
	elif player == 2:
		if i == 6 or i == 13:
			if i == 6:
				lbl.position = base + Vector2(Mx - lw/2 + OFFX,  -My - lh/2 + OFFY)
			else:
				lbl.position = base + Vector2(-Mx - lw/2 - OFFX, My - lh/2 - OFFY)
		else:
			lbl.scale = Vector2(1,1)
			if i < 6:
				lbl.position = base + Vector2(Mx - lw/2, -lh/2)
			else:
				lbl.position = base + Vector2(-Mx - lw/2, -lh/2)
	else:
		print("Shouldn't Update Label as it is not my turn")

func _place_stone(container: Node2D, base_pos: Vector2, label: int) -> void:
	pass
	
func send_game() -> void:
	print("Send Game Called!")
	is_my_turn = false # Disable further clicks
	var all_moves = ""
	for m in moves_made:
		all_moves += "move:" + m + "|"
	moves_made.clear()

	var post_board_str = "board:"
	for i in range(pits.size()):
		var pit = pits[i]
		if pit.size() > 0:
			# Manually join elements with commas, avoiding trailing comma
			for j in range(pit.size()):
				post_board_str += str(pit[j])
				if j < pit.size() - 1: # Only add comma if it's not the last element
					post_board_str += ","
		
		if i < pits.size() - 1:
			post_board_str += "&"
	
	var payload = {
		"replay": "board:" + prev_board_str + "|" + all_moves + post_board_str
	}
	print("PAYLOAD: ", payload)
	if await _check_game_over_and_winner():
		print("Check Win 863 my_player: ", my_player, " win_loss_state: ", win_loss_state)
		if game_over == true and not spectator_mode:
			payload["winner"] = my_player + "|" + ("1" if win_loss_state == "win" else "-1")
	# wrap our string in JSON so AppPlugin can parse it
	var game_data = JSON.stringify(payload)
	print("Game data being sent: " + game_data)

	var appPlugin := Engine.get_singleton("AppPlugin")
	if appPlugin:
		print("Attempting to send game data via AppPlugin.")
		appPlugin.updateGameData(game_data)
		play_sent_animation()
	else:
		print("AppPlugin is null. Cannot send game data.")
		play_sent_animation()
		
func _check_game_over_and_winner() -> bool:

	print("Checking for game over condition...")
	var is_game_over_condition_met = false

	if not game_over:
		var player1_store_count = pits[6].size()
		var player2_store_count = pits[13].size()
		print("PLAYER 1 STORE QTY: ", player1_store_count, " | PLAYER 2 STORE QTY: ", player2_store_count)
		
		# Condition: Check if one player's non-store pits are empty
		var player1_side_empty = true
		for i in range(0, 6): # Pits 0-5 for player 1's side
			if pits[i].size() > 0:
				player1_side_empty = false
				break
		var player2_side_empty = true
		for i in range(7, 13): # Pits 7-12 for player 2's side
			if pits[i].size() > 0:
				player2_side_empty = false
				break
		
		if player1_side_empty or player2_side_empty:
			print("Game over: One player's side is empty.")
			is_game_over_condition_met = true
			
			# Distribute remaining stones from the non-empty side to that player's store
			# This logic is correct and handles which side sweeps
			if mode == "an" or mode == "ah":
				if player1_side_empty:
					print("Player 1's side is empty. Moving remaining stones from Player 2's side to Player 2's store.")
					for i in range(7, 13): # Pits 7-12 (Player 2's side)
						if pits[i].size() > 0:
							pits[13].append_array(pits[i])
							pits[i].clear()
							print("903 refresh count label call")
							_refresh_pit_count_label(i)
					print("905 refresh count label call")
					_refresh_pit_count_label(13) # Update Player 2's store count
				elif player2_side_empty:
					print("Player 2's side is empty. Moving remaining stones from Player 1's side to Player 1's store.")
					for i in range(0, 6): # Pits 0-5 (Player 1's side)
						if pits[i].size() > 0:
							pits[6].append_array(pits[i])
							pits[i].clear()
							print("913 refresh count label call")
							_refresh_pit_count_label(i)
					print("915 refresh count label call")
					_refresh_pit_count_label(6)
	
	if is_game_over_condition_met and not game_over:
		game_over = true

		print("Final scores: Player 1 (store 6): ", pits[6].size(), ", Player 2 (store 13): ", pits[13].size())
		var local_winner = -1
		if pits[6].size() > pits[13].size():
			local_winner = 1
		elif pits[13].size() > pits[6].size():
			local_winner = 2
		# If scores are equal, local_winner remains -1 (for a tie)
		
		winner_id = local_winner

			
	if game_over and winner_id != -1 and not disp_winner: # Only proceed to display winner if game is over and winner_id is set
		print("Setting Game_Over_State")
		disp_winner = true
		if not spectator_mode:
			if winner_id == -1: # Check for tie
				win_loss_label.text = "TIE!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
				win_loss_state = "tie"
			# Use player_str to determine if 'YOU WIN' or 'YOU LOSE'
			elif (player == 1 and winner_id == 1) or (player == 2 and winner_id == 2):
				win_loss_label.text = "YOU WIN!"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
				win_loss_state = "win"
			else:
				win_loss_label.text = "YOU LOSE"
				win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
				win_loss_state = "loss"
		else:
			win_loss_label.text = "Game Over!"
			win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		win_loss_label.visible = true
		await get_tree().process_frame # Ensure UI updates before tweening
		win_loss_label.scale = Vector2.ZERO
		win_loss_label.pivot_offset = win_loss_label.size / 2

		var tween_in = create_tween()
		tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		await tween_in.finished
		
	return game_over
	
func _on_skip_button_pressed() -> void:
	if in_replay: # Only allow skipping if currently in replay mode
		print("Skip button pressed during replay!")
		_skip_replay_animation = true	

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
	
# --- Animation Functions ---
func play_sent_animation():
	if sent_label:
		if sent_tween and sent_tween.is_running():
			sent_tween.kill()

		sent_tween = create_tween().set_parallel(false)

		sent_label.text = "Sent"
		sent_label.visible = true
		sent_label.modulate.a = 0.0
		sent_label.scale = Vector2.ONE
		sent_label.pivot_offset = sent_label.get_size() / 2.0

		sent_tween.tween_property(sent_label, "modulate:a", 1.0, 0.3)

		sent_tween.tween_interval(0.6)
		sent_tween.tween_callback(func():
			sent_label.text = "Sent ✔"
		)

		sent_tween.tween_interval(2.0)
		sent_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)

		sent_tween.tween_callback(func():
			sent_label.visible = false
			sent_label.modulate.a = 1.0
			start_waiting_animation()
		)
 
func start_waiting_animation():
	print("Starting Waiting Animation 826")
	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true
	waiting_blur.visible = true

	waiting_label.modulate.a = 0.0
	waiting_blur.modulate.a = 0.0

	var tween = create_tween().set_parallel(true)
	tween.tween_property(waiting_label, "modulate:a", 1.0, 0.3)
	tween.tween_property(waiting_blur, "modulate:a", 1.0, 0.3)

	dot_timer.start()


func stop_waiting_animation():
	dot_timer.stop()
	waiting_label.visible = false
	waiting_blur.visible = false
	
func _on_dot_timer_timeout():
	dot_count = (dot_count % 3) + 1
	var dots = ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots

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
