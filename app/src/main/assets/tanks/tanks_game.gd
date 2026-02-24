extends Control
class_name TanksGame

@onready var world: Node2D = %World
@onready var player_avatar_display: Control = %PlayerAvatarDisplay
@onready var opp_avatar_display: Control = %OppAvatarDisplay
@onready var rules_button: Button = %RulesButton
@onready var settings_button: Button = %SettingsButton
@onready var sent_label: Label = %SentLabel
@onready var waiting_label: Label = %WaitForOpponentLabel
@onready var waiting_blur: Control = %WaitBlur
@onready var dot_timer: Timer = %DotTimer
@onready var terrain: TanksTerrain = %Terrain
@onready var sky: TanksSky = %Sky
@onready var player_health: TextureRect = %PlayerHealth
@onready var opp_health: TextureRect = %OppHealth
@onready var tank_p1: Tank = %TankP1
@onready var tank_p2: Tank = %TankP2
@onready var overlay: Control = %Overlay
@onready var aim_layer: Node = %AimLayer
@onready var fire_button: CanvasItem = %FireButton
@onready var power_slider: Slider = %PowerSlider
@onready var power_label: RichTextLabel = %PowerLabel

const RULES_POPUP_SCENE := preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE := preload("res://global/settings_popup.tscn")

var core: TanksCore
var has_connected: bool = false
var sent_tween: Tween
var dot_count: int = 0
var _view_flipped: bool = false
var _is_dragging_aim: bool = false
var spectator_mode: bool = false
const BASE_WAIT_TEXT := "WAITING FOR OPPONENT"

#~~~~~~~~~~~ DEBUG ~~~~~~~~~~~~~~~~
var _aim_probe_frames: int = 0
const AIM_PROBE_MAX_FRAMES := 60
var _aim_debug_draw: bool = true

func _start_aim_probe() -> void:
	_aim_probe_frames = AIM_PROBE_MAX_FRAMES
	set_process(true)
	
func _process(_delta: float) -> void:
	if _aim_probe_frames <= 0:
		set_process(false)
		return

	_aim_probe_frames -= 1
	_debug_dump_aim_state()
	
func _debug_dump_aim_state() -> void:
	if not is_instance_valid(_aim_label):
		print("[AIM] label invalid")
		return

	var my_tank: Tank = tank_p1 if core.player == 1 else tank_p2
	if not is_instance_valid(my_tank):
		print("[AIM] tank invalid")
		return

	var pivot_world: Vector2 = my_tank.barrel_pivot.global_position
	var tip_world: Vector2 = my_tank.get_indicator_tip_global() if my_tank.has_method("get_indicator_tip_global") else my_tank.get_barrel_tip_global()

	var canvas_xf: Transform2D = get_viewport().get_canvas_transform()
	var pivot_screen: Vector2 = canvas_xf * pivot_world
	var tip_screen: Vector2 = canvas_xf * tip_world

	print("[AIM]",
		"	frame=", str(AIM_PROBE_MAX_FRAMES - _aim_probe_frames),
		"	player=", str(core.player),
		"	view_flipped=", str(_view_flipped),
		"	label_vis=", str(_aim_label.visible),
		"	label_pos=", str(_aim_label.position),
		"	pivotW=", str(pivot_world),
		"	tipW=", str(tip_world),
		"	pivotS=", str(pivot_screen),
		"	tipS=", str(tip_screen),
		"	world_scale=", str(world.scale),
		"	world_pos=", str(world.position)
	)
	if _aim_debug_draw:
		overlay.queue_redraw()

func _draw() -> void:
	if not _aim_debug_draw:
		return
	if core == null:
		return

	var my_tank: Tank = tank_p1 if core.player == 1 else tank_p2
	if not is_instance_valid(my_tank):
		return

	var pivot_world: Vector2 = my_tank.barrel_pivot.global_position
	var tip_world: Vector2 = my_tank.get_indicator_tip_global() if my_tank.has_method("get_indicator_tip_global") else my_tank.get_barrel_tip_global()

	var canvas_xf: Transform2D = get_viewport().get_canvas_transform()
	var pivot_screen: Vector2 = canvas_xf * pivot_world
	var tip_screen: Vector2 = canvas_xf * tip_world

	# Draw small circles in overlay/canvas space
	draw_circle(pivot_screen, 4.0, Color(1, 1, 0, 1))
	draw_circle(tip_screen, 4.0, Color(0, 1, 1, 1))
	draw_line(pivot_screen, tip_screen, Color(0, 1, 0, 1), 2.0)
#~~~~~~~~~~~ DEBUG ~~~~~~~~~~~~~~~~

const HEALTH_TEX := {
	0: preload("res://tanks/tanks_health_0.png"),
	1: preload("res://tanks/tanks_health_1.png"),
	2: preload("res://tanks/tanks_health_2.png"),
	3: preload("res://tanks/tanks_health_3.png"),
}

const TANK1_COLOR := Color(0.25, 0.55, 1.0, 1.0) # Blue
const TANK2_COLOR := Color(1.0, 0.25, 0.25, 1.0) # Red

var _aim_label: Label

func _ready() -> void:
	core = TanksCore.new()
	add_child(core)

	core.turn_changed.connect(_on_turn_changed)
	core.board_loaded.connect(_on_board_loaded)
	core.replay_action.connect(_on_replay_action)
	core.outbound_ready.connect(_send_payload)

	if is_instance_valid(rules_button):
		rules_button.pressed.connect(_on_rules_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_pressed)
	if is_instance_valid(fire_button):
		fire_button.pressed.connect(_on_send_pressed)
	if is_instance_valid(dot_timer):
		dot_timer.timeout.connect(_on_dot_timer_timeout)
	if is_instance_valid(power_slider):
		power_slider.value_changed.connect(_on_power_slider_changed)

	resized.connect(_on_resized)
	_on_resized()
	
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_apply_health_colors()
	_set_health_tex(player_health, 3)
	_set_health_tex(opp_health, 3)

	_apply_tank_colors()
	_setup_aim_label()

	_connect_app_plugin_or_dev()

func _setup_aim_label() -> void:
	_aim_label = Label.new()
	_aim_label.text = ""
	_aim_label.visible = false
	_aim_label.z_index = 1000
	_aim_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Keep it immune from any Control containers
	_aim_label.set_as_top_level(true)

	if is_instance_valid(aim_layer):
		aim_layer.add_child(_aim_label)
	elif is_instance_valid(overlay):
		# Fallback, but AimLayer should exist
		overlay.add_child(_aim_label)

func _connect_app_plugin_or_dev() -> void:
	var app_plugin := Engine.get_singleton("AppPlugin")
	if app_plugin:
		if not has_connected:
			app_plugin.connect("set_game_data", _set_game_data)
			has_connected = true
			app_plugin.onReady()
	else:
		var dev := JSON.stringify({ #PLAYER 2
			"myPlayerId": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb",
			"player1": "82B2A470-70BC-4EDF-9AAA-0B99A98C58DAj2fM2b",
			"player2": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb",
			"player": "1",
			"isYourTurn": true,
			"avatar1": "",
			"avatar2": "",
			"replay": "board:height,55.690147&wind,0.413690&tank1x,-140.662827&tank1rot,0.000000&tank1power,1.000000&tank1hp,2&tank2x,116.385284&tank2rot,0.000000&tank2power,0.500000&tank2hp,2"
		})
		#var dev := JSON.stringify({ #PLAYER 1
			#"myPlayerId": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb",
			#"player1": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb",
			#"player2": "82B2A470-70BC-4EDF-9AAA-0B99A98C58DAj2fM2b",
			#"player": "1",
			#"isYourTurn": true,
			#"avatar1": "",
			#"avatar2": "",
			#"replay": "board:height,55.690147&wind,0.413690&tank1x,-140.662827&tank1rot,0.000000&tank1power,1.000000&tank1hp,2&tank2x,116.385284&tank2rot,0.000000&tank2power,0.500000&tank2hp,2"
		#})
		_set_game_data(dev)

func _set_game_data(raw_text: String) -> void:
	core.ingest_game_data(raw_text)
	_apply_view_flip()
	_update_avatars()

	_apply_health_colors()

	if not core.current_board.is_empty():
		_apply_health_from_board(core.current_board)

	_apply_tank_colors()

	if not core.current_board.is_empty():
		call_deferred("_apply_tanks_from_board", core.current_board)
		
	_update_aim_label_visibility()
	_start_aim_probe()
	
func _apply_view_flip() -> void:
	# Flip exactly once based on who I am
	_view_flipped = (core.player == 2)

	if not is_instance_valid(world):
		return

	var vp_w: float = get_viewport().get_visible_rect().size.x

	# Mirror World only, do not mirror Overlay
	if _view_flipped:
		world.scale = Vector2(-1, 1)
		world.position = Vector2(vp_w, 0.0)
	else:
		world.scale = Vector2(1, 1)
		world.position = Vector2(0.0, 0.0)

	# After world flip changes, re-apply which tank is visually mirrored
	_apply_tank_facing(_view_flipped)

	# Keep label correct if it is currently visible
	_update_aim_label_visibility()

func _on_resized() -> void:
	if is_instance_valid(sky):
		sky.set_view_size(size)

func _apply_health_colors() -> void:
	if not is_instance_valid(player_health) or not is_instance_valid(opp_health):
		return

	var my_color: Color = TANK1_COLOR if core.player == 1 else TANK2_COLOR
	var opp_color: Color = TANK2_COLOR if core.player == 1 else TANK1_COLOR

	player_health.self_modulate = my_color
	opp_health.self_modulate = opp_color

	# Match FireButton to MY color (same as PlayerHealth)
	_apply_fire_button_color(my_color)
	
func _apply_fire_button_color(c: Color) -> void:
	if not is_instance_valid(fire_button):
		return

	# Works for Button/TextureRect/etc
	fire_button.self_modulate = c
	
func _visual_deg_to_data_deg(visual_deg: float) -> float:
	visual_deg = clamp(visual_deg, 0.0, 180.0)
	if _view_flipped:
		return 180.0 - visual_deg
	return visual_deg

func _data_deg_to_visual_deg(data_deg: float) -> float:
	data_deg = clamp(data_deg, 0.0, 180.0)
	if _view_flipped:
		return 180.0 - data_deg
	return data_deg

func _set_health_tex(node: TextureRect, hp: int) -> void:
	if not is_instance_valid(node):
		return
	var h: int = int(clamp(hp, 0, 3))
	if HEALTH_TEX.has(h):
		node.texture = HEALTH_TEX[h]

func _apply_health_from_board(board: Dictionary) -> void:
	var hp1: int = int(board.get("tank1hp", 3))
	var hp2: int = int(board.get("tank2hp", 3))

	var my_hp: int = hp1 if core.player == 1 else hp2
	var opp_hp: int = hp2 if core.player == 1 else hp1

	_set_health_tex(player_health, my_hp)
	_set_health_tex(opp_health, opp_hp)

func _apply_tank_colors() -> void:
	if is_instance_valid(tank_p1):
		tank_p1.set_player_color(TANK1_COLOR)
	if is_instance_valid(tank_p2):
		tank_p2.set_player_color(TANK2_COLOR)

func _on_board_loaded(board: Dictionary) -> void:
	_apply_health_from_board(board)

	var h: float = float(board.get("height", 0.0))
	var w: float = float(board.get("wind", 0.0))

	# Terrain is always built the same direction.
	# World mirroring handles the player-2 view.
	if is_instance_valid(terrain):
		terrain.apply_board(h, false)

	if is_instance_valid(sky):
		sky.set_wind(w)

	_apply_tank_colors()

	# Make sure the correct single tank is visually flipped
	_apply_tank_facing(_view_flipped)

	call_deferred("_apply_tanks_from_board", board)
	call_deferred("_update_aim_label_visibility")
	_start_aim_probe()

func _apply_tanks_from_board(board: Dictionary) -> void:
	if not is_instance_valid(terrain):
		return
	if not is_instance_valid(tank_p1) or not is_instance_valid(tank_p2):
		return

	var tank1x: float = float(board.get("tank1x", 0.0))
	var tank2x: float = float(board.get("tank2x", 0.0))

	var world_w: float = terrain.get_world_width()
	var cx: float = world_w * 0.5

	# Positions are always in the terrain’s base coordinate system.
	# World mirroring handles what player 2 sees.
	var x1: float = cx + tank1x
	var x2: float = cx + tank2x

	var y1: float = terrain.get_surface_y_at_screen_x(x1)
	var y2: float = terrain.get_surface_y_at_screen_x(x2)

	var off1: float = tank_p1.get_bottom_offset_px()
	var off2: float = tank_p2.get_bottom_offset_px()

	tank_p1.position = Vector2(x1, y1 - off1)
	tank_p2.position = Vector2(x2, y2 - off2)

	# Board rotations are radians in Godot space (0 right, -pi/2 up, pi left)
	var r1: float = float(board.get("tank1rot", 0.0))
	var r2: float = float(board.get("tank2rot", 0.0))

	var p1_data_deg: float = _display_deg_from_godot_rad(r1)
	var p2_data_deg: float = _display_deg_from_godot_rad(r2)

	tank_p1.set_barrel_display_deg(_data_deg_to_visual_deg(p1_data_deg))
	tank_p2.set_barrel_display_deg(_data_deg_to_visual_deg(p2_data_deg))

	tank_p1.z_index = 20
	tank_p2.z_index = 20

	# Apply single-tank facing after placement
	_apply_tank_facing(_view_flipped)

	_update_aim_label_position()
	
	var p1_power: float = float(board.get("tank1power", 0.5))
	var p2_power: float = float(board.get("tank2power", 0.5))

	tank_p1.set_power(p1_power)
	tank_p2.set_power(p2_power)
	
	# --- NEW: Sync Slider and Core on Load ---
	var my_power = p1_power if core.player == 1 else p2_power
	if is_instance_valid(power_slider):
		power_slider.value = my_power * 100.0
	
	# Sync the core internal state so 'Send' works immediately
	var my_tank = tank_p1 if core.player == 1 else tank_p2
	core.set_my_aim(my_tank.barrel_pivot.rotation, my_power)
	
	tank_p1.set_power_visibility(core.player == 1)
	tank_p2.set_power_visibility(core.player == 2)
	_update_aim_label_visibility()
	
func _display_deg_from_godot_rad(godot_rad: float) -> float:
	# Godot rad: 0 right, -pi/2 up, pi left
	# Convert to VISUAL deg: 0 right..180 left
	var visual_deg: float = -rad_to_deg(godot_rad)
	visual_deg = fposmod(visual_deg, 360.0)
	if visual_deg > 180.0:
		visual_deg = 360.0 - visual_deg
	visual_deg = clamp(visual_deg, 0.0, 180.0)

	# Return DATA deg for UI/serialization (swap ends if view flipped)
	return _visual_deg_to_data_deg(visual_deg)
	
func _apply_tank_facing(_flip_view: bool) -> void:
	if not is_instance_valid(tank_p1) or not is_instance_valid(tank_p2):
		return

	# Reset scales to absolute values first
	tank_p1.body.scale.x = abs(tank_p1.body.scale.x)
	tank_p2.body.scale.x = abs(tank_p2.body.scale.x)

	tank_p1.barrel_sprite.scale.y = abs(tank_p1.barrel_sprite.scale.y)
	tank_p2.barrel_sprite.scale.y = abs(tank_p2.barrel_sprite.scale.y)

	# Tank 1 is naturally on the left, so it faces Right (+1 local scale)
	# (No changes needed since we used abs() above)
	
	# Tank 2 is naturally on the right, so it faces Left (-1 local scale)
	tank_p2.body.scale.x = -tank_p2.body.scale.x
	tank_p2.barrel_sprite.scale.y = -tank_p2.barrel_sprite.scale.y
	
func _update_aim_label_visibility() -> void:
	if not is_instance_valid(_aim_label):
		return

	_aim_label.visible = (core.is_my_turn and not core.spectator_mode)

	# If we’re not showing it, nothing to position
	if not _aim_label.visible:
		return

	# One-frame defer so Tank + IndicatorTip globals are valid
	call_deferred("_update_aim_label_position")
	
func _update_aim_label_position() -> void:
	if not is_instance_valid(_aim_label):
		return
	if not _aim_label.visible:
		return

	var my_tank: Tank = tank_p1 if core.player == 1 else tank_p2
	if not is_instance_valid(my_tank):
		return

	# --- FIX: Account for the power indicator tip instead of just the barrel tip ---
	var tip_world: Vector2 = my_tank.get_indicator_tip_global() if my_tank.has_method("get_indicator_tip_global") else my_tank.get_barrel_tip_global()
	var pivot_world: Vector2 = my_tank.barrel_pivot.global_position

	var canvas_xf: Transform2D = get_viewport().get_canvas_transform()
	var tip_screen: Vector2 = canvas_xf * tip_world
	var pivot_screen: Vector2 = canvas_xf * pivot_world

	var visual_deg: float = my_tank.get_barrel_display_deg()
	var data_deg: float = _visual_deg_to_data_deg(visual_deg)
	_aim_label.text = str(int(round(data_deg))) + "°"
	_aim_label.reset_size()

	var offset: Vector2
	if tip_screen.x < pivot_screen.x:
		offset = Vector2(-_aim_label.size.x - 15.0, -15.0)
	else:
		offset = Vector2(15.0, -15.0)

	_aim_label.global_position = tip_screen + offset
	
func _on_power_slider_changed(value: float) -> void:
	var my_tank: Tank = tank_p1 if core.player == 1 else tank_p2
	var p_01: float = value / 100.0
	
	my_tank.set_power(p_01)
	
	var power_val = int(value)
	power_label.text = "Power: " + str(power_val)
	
	# Update Core so the data is ready for outbound payload
	var rot_rad := my_tank.barrel_pivot.rotation 
	core.set_my_aim(rot_rad, p_01)
	
	# Keep the label attached to the moving tip
	_update_aim_label_position()
	
func _unhandled_input(event: InputEvent) -> void:
	if core == null:
		return
	if core.spectator_mode:
		return
	if not core.is_my_turn:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging_aim = true
			_handle_aim_at_screen_pos((event as InputEventMouseButton).position)
			accept_event()
		else:
			_is_dragging_aim = false
			accept_event()
		return

	if event is InputEventMouseMotion and _is_dragging_aim:
		_handle_aim_at_screen_pos((event as InputEventMouseMotion).position)
		accept_event()

func _handle_aim_at_screen_pos(screen_pos: Vector2) -> void:
	var my_tank: Tank = tank_p1 if core.player == 1 else tank_p2
	if not is_instance_valid(my_tank):
		return

	# Work entirely in SCREEN space. World is already mirrored visually when _view_flipped.
	var pivot_world: Vector2 = my_tank.barrel_pivot.global_position
	var pivot_screen: Vector2 = get_viewport().get_canvas_transform() * pivot_world

	var v: Vector2 = screen_pos - pivot_screen
	if v.length() < 1.0:
		return

	# --- THE FIX: Invert X when the world is flipped to match screen drag ---
	if _view_flipped:
		v.x = -v.x

	# Restriction: below pivot does nothing,
	# but allow finishing to 0/180 if already close to an end.
	if v.y > 0.0:
		var end_visual: float = 0.0 if v.x >= 0.0 else 180.0
		const END_SNAP_DEG := 25.0
		if abs(my_tank.get_barrel_display_deg() - end_visual) <= END_SNAP_DEG:
			my_tank.set_barrel_display_deg(end_visual)
			_update_aim_label_position()
		return

	# v.angle(): 0 right, -90 up, 180 left
	var visual_deg: float = -rad_to_deg(v.angle())
	visual_deg = fposmod(visual_deg, 360.0)
	if visual_deg > 180.0:
		visual_deg = 360.0 - visual_deg
	visual_deg = clamp(visual_deg, 0.0, 180.0)

	my_tank.set_barrel_display_deg(visual_deg)
	
	var p_01 := power_slider.value / 100.0 if is_instance_valid(power_slider) else 0.5
	core.set_my_aim(my_tank.barrel_pivot.rotation, p_01)
	
	_update_aim_label_position()
	
func _handle_aim_click() -> void:
	var my_tank: Tank = tank_p1 if core.player == 1 else tank_p2
	if not is_instance_valid(my_tank):
		return

	var click_world: Vector2 = get_global_mouse_position()
	var pivot_pos: Vector2 = my_tank.barrel_pivot.global_position
	var v: Vector2 = click_world - pivot_pos
	if v.length() < 1.0:
		return
		
	if _view_flipped:
		v.x = -v.x

	# v.angle(): 0 right, -90 up, 180 left
	var display_deg: float = -rad_to_deg(v.angle())
	display_deg = fposmod(display_deg, 360.0)
	if display_deg > 180.0:
		display_deg = 360.0 - display_deg
	display_deg = clamp(display_deg, 0.0, 180.0)

	my_tank.set_barrel_display_deg(display_deg)

	_update_aim_label_position()
	
func _on_replay_action(_action: Dictionary) -> void:
	pass

func _on_turn_changed(v: bool) -> void:
	if v:
		stop_waiting_animation()
	else:
		start_waiting_animation()
	_update_aim_label_visibility()

func _on_send_pressed() -> void:
	print("Fire Button Pressed!")
	core.request_send()
	play_sent_animation()

func _send_payload(payload: Dictionary) -> void:
	var app_plugin := Engine.get_singleton("AppPlugin")
	if app_plugin:
		app_plugin.updateGameData(JSON.stringify(payload))

func _on_rules_pressed() -> void:
	var popup := RULES_POPUP_SCENE.instantiate()
	var dim := _make_dim()
	popup.z_index = 1000
	get_tree().root.add_child(dim)
	get_tree().root.add_child(popup)
	(popup as Node).tree_exited.connect(func():
		if is_instance_valid(dim):
			dim.queue_free()
	)
	if popup.has_method("open"):
		popup.open("How to Play Tanks", _rules_text())

func _on_settings_pressed() -> void:
	if not is_instance_valid(settings_button):
		return

	await _pop_button(settings_button)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var popup_instance := SETTINGS_POPUP_SCENE.instantiate()
	var settings_popup := popup_instance as SettingsPopup

	var root := get_tree().root
	root.add_child(dim)
	root.add_child(popup_instance)

	popup_instance.z_index = 1000
	dim.z_index = 99
	root.move_child(dim, root.get_child_count() - 2)

	if settings_popup != null:
		settings_popup.setup_popup(dim)
	else:
		if popup_instance.has_method("setup_popup"):
			popup_instance.call("setup_popup", dim)

	var custom_settings_title := popup_instance.find_child("CustomSettingsTitleLabel", true)
	if custom_settings_title != null and custom_settings_title is Label and settings_popup != null:
		(custom_settings_title as Label).visible = (settings_popup.custom_settings_container.get_child_count() > 0)
	elif custom_settings_title != null and custom_settings_title is Label:
		(custom_settings_title as Label).visible = false

	if settings_popup != null:
		settings_popup.closed.connect(func():
			if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("update_display_from_settings"):
				player_avatar_display.update_display_from_settings()
		)
		settings_popup.settings_theme_selected.connect(_on_theme_changed)

	popup_instance.set_as_top_level(true)
	popup_instance.visible = true
	await get_tree().process_frame

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var desired_width: float = viewport_size.x * 0.95
	var desired_height: float = popup_instance.get_combined_minimum_size().y

	popup_instance.size = Vector2(desired_width, desired_height)
	popup_instance.position = Vector2((viewport_size.x - desired_width) * 0.5, viewport_size.y)

	var bottom_offset: float = 50.0
	var target_y: float = viewport_size.y - desired_height - bottom_offset
	var target_pos: Vector2 = Vector2((viewport_size.x - desired_width) * 0.5, target_y)

	var tw := create_tween()
	tw.tween_property(popup_instance, "position", target_pos, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	popup_instance.grab_focus()

func _on_theme_changed(_new_theme_name: String) -> void:
	pass

func _pop_button(b: Control) -> void:
	if not is_instance_valid(b):
		return
	b.pivot_offset = b.size * 0.5
	var t := create_tween()
	t.tween_property(b, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished

func _make_dim() -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 99
	return dim

func _rules_text() -> String:
	return """
[font_size={32px}][b]Tanks[/b][/font_size]

[font_size={24px}][b]Objective[/b][/font_size]
[font_size={18px}]
• Aim your barrel and choose power.
• Wind affects your shot.
• Reduce your opponent to 0 HP.
[/font_size]

[font_size={24px}][b]Turn Flow[/b][/font_size]
[font_size={18px}]
• Set your barrel rotation and power.
• Send your selection.
• When both players are ready, the round plays.
[/font_size]
"""

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		print("Warning: sent_label is not valid for play_sent_animation.")
		return
	
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
		if is_instance_valid(sent_label):
			sent_label.text = "Sent ✔"
	)
	sent_tween.tween_interval(2.0)
	sent_tween.tween_property(sent_label, "modulate:a", 0.0, 0.5)

	sent_tween.tween_callback(func():
		if is_instance_valid(sent_label):
			sent_label.visible = false
			sent_label.modulate.a = 1.0
			start_waiting_animation()
	)

func _update_avatars() -> void:
	if not is_instance_valid(player_avatar_display) or not is_instance_valid(opp_avatar_display):
		return

	var my_key := ("avatar1" if core.player == 1 else "avatar2")
	var opp_key := ("avatar2" if core.player == 1 else "avatar1")

	var my_str := (core.avatar1_str if my_key == "avatar1" else core.avatar2_str)
	var opp_str := (core.avatar2_str if opp_key == "avatar2" else core.avatar1_str)

	if player_avatar_display.has_method("update_avatar_from_string") and my_str != "":
		player_avatar_display.call_deferred("update_avatar_from_string", my_str)

	if opp_avatar_display.has_method("update_avatar_from_string") and opp_str != "":
		opp_avatar_display.call_deferred("update_avatar_from_string", opp_str)

func start_waiting_animation():
	if not is_instance_valid(waiting_label) or not is_instance_valid(waiting_blur) or not is_instance_valid(dot_timer):
		print("Warning: Waiting animation nodes are not valid.")
		return
	if spectator_mode:
		return

	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true
	waiting_blur.visible = true

	waiting_label.modulate.a = 0.0
	waiting_blur.modulate.a = 0.0

	var tween_wait_in = create_tween().set_parallel(true)
	tween_wait_in.tween_property(waiting_label, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_property(waiting_blur, "modulate:a", 1.0, 0.3)
	tween_wait_in.tween_callback(func():
		dot_timer.start()
	)

func stop_waiting_animation():
	if is_instance_valid(dot_timer):
		dot_timer.stop()
	if is_instance_valid(waiting_label):
		waiting_label.visible = false
		waiting_label.modulate.a = 1.0
	if is_instance_valid(waiting_blur):
		waiting_blur.visible = false
		waiting_blur.modulate.a = 1.0

func _on_dot_timer_timeout() -> void:
	if not is_instance_valid(waiting_label):
		return
	dot_count = (dot_count % 3) + 1
	var dots := ""
	for i in range(dot_count):
		dots += "."
	waiting_label.text = BASE_WAIT_TEXT + dots
