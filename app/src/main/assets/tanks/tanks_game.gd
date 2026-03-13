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
@onready var wind_indicator: WindIndicator = %WindIndicator

const RULES_POPUP_SCENE := preload("res://global/RulesPopup.tscn")
const SETTINGS_POPUP_SCENE := preload("res://global/settings_popup.tscn")

var core: TanksCore
var has_connected: bool = false
var sent_tween: Tween
var dot_count: int = 0
var _view_flipped: bool = false
var _is_dragging_aim: bool = false
var spectator_mode: bool = false
var can_interact: bool = true
var has_replay: bool = false
const BASE_WAIT_TEXT := "WAITING FOR OPPONENT"

const HEALTH_TEX := {
	0: preload("res://tanks/tanks_health_0.png"),
	1: preload("res://tanks/tanks_health_1.png"),
	2: preload("res://tanks/tanks_health_2.png"),
	3: preload("res://tanks/tanks_health_3.png"),
}

const TANK1_COLOR := Color(0.25, 0.55, 1.0, 1.0) # Blue
const TANK2_COLOR := Color(1.0, 0.25, 0.25, 1.0) # Red

const BOARD_X_MIN := -187.0
const BOARD_X_MAX := 187.0
const BOARD_X_WIDTH := BOARD_X_MAX - BOARD_X_MIN # 374.0

const TANK_WIDTH_UNITS := 25.0
const TANK_HALF_WIDTH_UNITS := TANK_WIDTH_UNITS * 0.5

func _game_x_to_screen_x(game_x: float) -> float:
	if not is_instance_valid(terrain):
		return game_x
	
	return remap(game_x, BOARD_X_MIN, BOARD_X_MAX, 0.0, terrain.get_world_width())

var _aim_label: Label

func _ready() -> void:
	core = TanksCore.new()
	add_child(core)
	core.replay_true.connect(_on_has_replay)
	core.turn_changed.connect(_on_turn_changed)
	core.board_loaded.connect(_on_board_loaded)
	core.replay_action.connect(_on_replay_action)
	core.outbound_ready.connect(_send_payload)
	core.opponent_avatar_ready.connect(_on_opponent_avatar_received)

	if is_instance_valid(rules_button):
		rules_button.pressed.connect(_on_rules_pressed)
	if is_instance_valid(settings_button):
		settings_button.pressed.connect(_on_settings_pressed)
	if is_instance_valid(fire_button):
		fire_button.pressed.connect(_on_send_pressed)
		fire_button.button_down.connect(_on_fire_button_down)
		fire_button.button_up.connect(_on_fire_button_up)
	if is_instance_valid(dot_timer):
		dot_timer.timeout.connect(_on_dot_timer_timeout)
	if is_instance_valid(power_slider):
		power_slider.value_changed.connect(_on_power_slider_changed)

	resized.connect(_on_resized)
	_on_resized()
	
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_apply_tank_size()
	_apply_tank_colors()
	_debug_tank_sizes()

	_apply_health_colors()
	_set_health_tex(player_health, 3)
	_set_health_tex(opp_health, 3)

	_apply_tank_colors()
	_setup_aim_label()
	
	# Set UI to "Out" state immediately
	fire_button.modulate.a = 0.0
	power_slider.modulate.a = 0.0
	power_label.modulate.a = 0.0
	if is_instance_valid(_aim_label):
		_aim_label.modulate.a = 0.0
		
	tank_p1.set_power_visibility(false)
	tank_p2.set_power_visibility(false)
	
	# Disable interaction until board is loaded and it's our turn
	can_interact = false
	power_slider.editable = false

	_connect_app_plugin_or_dev()

func _get_pixels_per_board_unit() -> float:
	if not is_instance_valid(terrain):
		return 1.0
	
	return terrain.get_world_width() / BOARD_X_WIDTH

func _get_target_tank_width_screen_px() -> float:
	return TANK_WIDTH_UNITS * _get_pixels_per_board_unit()

func _apply_tank_size() -> void:
	var target_width_px := _get_target_tank_width_screen_px()
	
	if is_instance_valid(tank_p1):
		tank_p1.fit_visual_width_px(target_width_px)
	if is_instance_valid(tank_p2):
		tank_p2.fit_visual_width_px(target_width_px)
	
func _screen_x_to_game_x(screen_x: float) -> float:
	if not is_instance_valid(terrain):
		return screen_x
	
	return remap(screen_x, 0.0, terrain.get_world_width(), BOARD_X_MIN, BOARD_X_MAX)

func _setup_aim_label() -> void:
	_aim_label = Label.new()
	_aim_label.text = ""
	_aim_label.visible = false
	_aim_label.z_index = 1000
	_aim_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_label.set_as_top_level(true)

	if is_instance_valid(aim_layer):
		aim_layer.add_child(_aim_label)
	elif is_instance_valid(overlay):
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
			"avatar1": "body,3|eyes,6|mouth,3|acc,0|wins,0|bg_color,0.933333,0.407843,0.647059|body_color,0.968627,0.811765,0.333333|glasses,0|stache,0|backdrop,0|hair,0|clothes,2|hair_color,0.505882,0.725490,0.254902|clothes_color,0.686657,0.686657,0.686657",
			"avatar2": "",
			"replay": "board:height,55.690147&wind,0.0&tank1x,-140.662827&tank1rot,-3.1415&tank1power,1.000000&tank1hp,2&tank2x,116.385284&tank2rot,-3.1415&tank2power,0.500000&tank2hp,2|shoot:1"
		})
		#var dev := JSON.stringify({ #PLAYER 1
			#"myPlayerId": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb",
			#"player1": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb",
			#"player2": "82B2A470-70BC-4EDF-9AAA-0B99A98C58DAj2fM2b",
			#"player": "1",
			#"isYourTurn": true,
			#"avatar1": "",
			#"avatar2": "body,3|eyes,6|mouth,3|acc,0|wins,0|bg_color,0.933333,0.407843,0.647059|body_color,0.968627,0.811765,0.333333|glasses,0|stache,0|backdrop,0|hair,0|clothes,2|hair_color,0.505882,0.725490,0.254902|clothes_color,0.686657,0.686657,0.686657",
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
	
func _apply_view_flip() -> void:
	_view_flipped = (core.player == 2)

	if not is_instance_valid(world):
		return

	var vp_w: float = get_viewport().get_visible_rect().size.x

	if _view_flipped:
		world.scale = Vector2(-1, 1)
		world.position = Vector2(vp_w, 0.0)
	else:
		world.scale = Vector2(1, 1)
		world.position = Vector2(0.0, 0.0)

	_apply_tank_facing(_view_flipped)

	_update_aim_label_visibility()

func _on_resized() -> void:
	if is_instance_valid(sky):
		sky.set_view_size(size)
		
func _on_opponent_avatar_received(avatar_data: Dictionary) -> void:
	if is_instance_valid(opp_avatar_display):
		if opp_avatar_display.has_method("update_avatar_from_data"):
			opp_avatar_display.update_avatar_from_data(avatar_data)

func _apply_health_colors() -> void:
	if not is_instance_valid(player_health) or not is_instance_valid(opp_health):
		return

	var my_color: Color = TANK1_COLOR if core.player == 1 else TANK2_COLOR
	var opp_color: Color = TANK2_COLOR if core.player == 1 else TANK1_COLOR

	player_health.self_modulate = my_color
	opp_health.self_modulate = opp_color

	_apply_fire_button_color(my_color)
	
func _apply_fire_button_color(c: Color) -> void:
	if not is_instance_valid(fire_button):
		return

	fire_button.self_modulate = c
	
func _visual_deg_to_data_deg(visual_deg: float) -> float:
	visual_deg = clamp(visual_deg, 0.0, 180.0)
	if _view_flipped:
		return 180.0 - visual_deg
	return visual_deg
	
func _on_fire_button_down() -> void:
	if is_instance_valid(fire_button):
		fire_button.self_modulate = fire_button.self_modulate.darkened(0.2)

func _on_fire_button_up() -> void:
	var my_color: Color = TANK1_COLOR if core.player == 1 else TANK2_COLOR
	_apply_fire_button_color(my_color)

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
	print("Wind Speed: ", w)
	if is_instance_valid(terrain):
		terrain.apply_board(h, false)

	if is_instance_valid(sky):
		sky.set_wind(w)
		
	if is_instance_valid(wind_indicator):
		wind_indicator.set_wind(w)
		print("Setting Wind: ", w)

	_apply_tank_colors()

	_apply_tank_facing(_view_flipped)

	call_deferred("_apply_tanks_from_board", board)
	call_deferred("_update_aim_label_visibility")
	
	terrain.apply_board(h, false)
	
	if is_instance_valid(sky):
		sky.set_terrain_height(terrain.base_y)
		
func _debug_tank_sizes() -> void:
	var ppu := _get_pixels_per_board_unit()
	var tank_w := _get_target_tank_width_screen_px()
	print("Pixels per board unit: ", ppu)
	print("Target tank width screen px: ", tank_w)
	
	if is_instance_valid(tank_p1):
		print("Tank P1 width px: ", tank_p1.get_body_width_px())
	if is_instance_valid(tank_p2):
		print("Tank P2 width px: ", tank_p2.get_body_width_px())

func _apply_tanks_from_board(board: Dictionary) -> void:
	if not is_instance_valid(terrain):
		return
	if not is_instance_valid(tank_p1) or not is_instance_valid(tank_p2):
		return
		
	_apply_tank_size()

	var tank1x: float = float(board.get("tank1x", 0.0))
	var tank2x: float = float(board.get("tank2x", 0.0))

	var x1: float = _game_x_to_screen_x(tank1x)
	var x2: float = _game_x_to_screen_x(tank2x)

	var y1: float = terrain.get_surface_y_at_screen_x(x1)
	var y2: float = terrain.get_surface_y_at_screen_x(x2)

	var off1: float = tank_p1.get_bottom_offset_px()
	var off2: float = tank_p2.get_bottom_offset_px()

	tank_p1.position = Vector2(x1, y1 - off1)
	tank_p2.position = Vector2(x2, y2 - off2)

	var r1: float = float(board.get("tank1rot", 0.0))
	var r2: float = float(board.get("tank2rot", 0.0))

	tank_p1.set_barrel_display_deg(_display_deg_from_godot_rad(r1))
	tank_p2.set_barrel_display_deg(_display_deg_from_godot_rad(r2))

	tank_p1.z_index = 20
	tank_p2.z_index = 20

	_apply_tank_facing(_view_flipped)

	_update_aim_label_position()
	
	var p1_power: float = float(board.get("tank1power", 0.5))
	var p2_power: float = float(board.get("tank2power", 0.5))
	
	if core.player == 1:
		power_slider.value = p1_power * 100.0
	else:
		power_slider.value = p2_power * 100.0

	tank_p1.set_power(p1_power)
	tank_p2.set_power(p2_power)
	
	var my_power = p1_power if core.player == 1 else p2_power
	if is_instance_valid(power_slider):
		power_slider.value = my_power * 100.0
	
	var my_tank = tank_p1 if core.player == 1 else tank_p2
	core.set_my_aim(my_tank.barrel_pivot.rotation, my_power)
	
	var should_show_power = core.is_my_turn and not _is_playing_round
	tank_p1.set_power_visibility(should_show_power and core.player == 1)
	tank_p2.set_power_visibility(should_show_power and core.player == 2)
	_update_aim_label_visibility()
	
func _display_deg_from_godot_rad(godot_rad: float) -> float:
	# Convert raw radians to degrees
	var raw_deg = rad_to_deg(godot_rad) 
	
	# Based on your data:
	# -3.14 rad (-180 deg) -> 180 visual deg
	# -4.69 rad (-268 deg) -> ~90 visual deg
	# We use abs() or 360-based logic to fit the 0-180 arc
	var visual_deg = fmod(abs(raw_deg), 360.0)
	
	if visual_deg > 180.0:
		visual_deg = 360.0 - visual_deg
	
	# Conversion for data (flipped view logic)
	var final_data_deg = _visual_deg_to_data_deg(visual_deg)
	
	# --- DEBUG BLOCK ---
	print("--- Rotation Conversion Debug ---")
	print("Input Rad: ", godot_rad)
	print("Raw Deg: ", raw_deg)
	print("Visual Deg (0-180): ", visual_deg)
	print("Final Data Deg: ", final_data_deg)
	print("---------------------------------")
	
	return final_data_deg
	
func _apply_tank_facing(_flip_view: bool) -> void:
	if not is_instance_valid(tank_p1) or not is_instance_valid(tank_p2):
		return

	tank_p1.body.scale.x = abs(tank_p1.body.scale.x)
	tank_p2.body.scale.x = abs(tank_p2.body.scale.x)

	tank_p1.barrel_sprite.scale.y = abs(tank_p1.barrel_sprite.scale.y)
	tank_p2.barrel_sprite.scale.y = abs(tank_p2.barrel_sprite.scale.y)

	tank_p2.body.scale.x = -tank_p2.body.scale.x
	tank_p2.barrel_sprite.scale.y = -tank_p2.barrel_sprite.scale.y
	
func _update_aim_label_visibility() -> void:
	if not is_instance_valid(_aim_label):
		return

	_aim_label.visible = (core.is_my_turn and not core.spectator_mode)

	if not _aim_label.visible:
		return

	call_deferred("_update_aim_label_position")
	
func _update_aim_label_position() -> void:
	if not is_instance_valid(_aim_label):
		return
	if not _aim_label.visible:
		return

	var my_tank: Tank = tank_p1 if core.player == 1 else tank_p2
	if not is_instance_valid(my_tank):
		return

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
	
	var rot_rad := my_tank.barrel_pivot.rotation 
	core.set_my_aim(rot_rad, p_01)
	
	_update_aim_label_position()
	
func _unhandled_input(event: InputEvent) -> void:
	if core == null or core.spectator_mode or not core.is_my_turn or not can_interact or _is_playing_round:
		return
	if fire_button.modulate.a == 0:
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

	var pivot_world: Vector2 = my_tank.barrel_pivot.global_position
	var pivot_screen: Vector2 = get_viewport().get_canvas_transform() * pivot_world

	var v: Vector2 = screen_pos - pivot_screen
	if v.length() < 1.0:
		return

	if _view_flipped:
		v.x = -v.x

	if v.y > 0.0:
		var end_visual: float = 0.0 if v.x >= 0.0 else 180.0
		const END_SNAP_DEG := 25.0
		if abs(my_tank.get_barrel_display_deg() - end_visual) <= END_SNAP_DEG:
			my_tank.set_barrel_display_deg(end_visual)
			_update_aim_label_position()
		return

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

	var display_deg: float = -rad_to_deg(v.angle())
	display_deg = fposmod(display_deg, 360.0)
	if display_deg > 180.0:
		display_deg = 360.0 - display_deg
	display_deg = clamp(display_deg, 0.0, 180.0)

	my_tank.set_barrel_display_deg(display_deg)

	_update_aim_label_position()
	
func _on_has_replay(r: bool) -> void:
	has_replay = r

func _on_turn_changed(v: bool) -> void:
	if v and not (_is_playing_round or core.current_board.is_empty() or has_replay):
		stop_waiting_animation()
		_set_ui_visible(true)
	else:
		start_waiting_animation()
		await _set_ui_visible(false)
	_update_aim_label_visibility()

#func _on_send_pressed() -> void:
	#if _is_playing_round: return
	#
	#print("Executing Local Shot...")
	#_is_playing_round = true
	#can_interact = false
	#
	## 1. Lock UI
	#_set_ui_visible(false)
	#
	#
	## 2. Get current local aim
	#var my_tank: Tank = tank_p1 if core.player == 1 else tank_p2
	#var my_rot := my_tank.barrel_pivot.rotation
	#var my_pwr := power_slider.value / 100.0
	#var wind_val := float(core.current_board.get("wind", 0.0))
	#
	## 3. Play ONLY your shot
	#await _execute_shot(core.player, my_rot, my_pwr, wind_val)
	#
	## 4. Update core with your final aim before sending
	#core.set_my_aim(my_rot, my_pwr)
	#
	## 5. Package and Send
	#var avatar_str := ""
	#if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		#avatar_str = player_avatar_display.get_avatar_data_string()
	#
	#core.request_send(avatar_str)
	#play_sent_animation()
	#
	#_is_playing_round = false
	## can_interact remains false because we are now waiting for opponent

func _send_payload(payload: Dictionary) -> bool:
	print(">>> _send_payload CALLED")
	print(">>> PAYLOAD: ", payload)

	var json := JSON.stringify(payload)
	var app_plugin := Engine.get_singleton("AppPlugin")

	if app_plugin:
		print(">>> AppPlugin found, calling updateGameData")
		app_plugin.updateGameData(json)
		return true

	print(">>> AppPlugin NOT found. DEV MODE FALLBACK.")
	print(">>> JSON TO SEND: ", json)

	return true

func _on_rules_pressed() -> void:
	var popup := RULES_POPUP_SCENE.instantiate()
	var dim := _make_dim()
	popup.z_index = 1000
	can_interact = false
	get_tree().root.add_child(dim)
	get_tree().root.add_child(popup)
	(popup as Node).tree_exited.connect(func():
		if is_instance_valid(dim):
			dim.queue_free()
		can_interact = true
	)
	if popup.has_method("open"):
		popup.open("How to Play Tanks", _rules_text())

func _on_settings_pressed() -> void:
	if not is_instance_valid(settings_button):
		return

	await _pop_button(settings_button)
	can_interact = false
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
			can_interact = true
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
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
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
	var my_str := (core.avatar1_str if my_key == "avatar1" else core.avatar2_str)
	
	if player_avatar_display.has_method("update_avatar_from_string") and my_str != "":
		player_avatar_display.update_avatar_from_string(my_str)

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
	
# --- ADD TO THE VERY BOTTOM OF tanks_game.gd ---

class TankBullet extends Node2D:
	signal impact(target_hit: String)
	
	var velocity: Vector2 = Vector2.ZERO
	var gravity: float = 600.0
	var wind: float = 0.0
	var game: TanksGame
	var _distance_traveled: float = 0.0
	
	var _trail: Line2D
	var _is_dead: bool = false
	
	func _ready() -> void:
		_trail = Line2D.new()
		_trail.width = 4.0
		_trail.default_color = Color(1.0, 0.9, 0.4, 0.8)
		# Setting as top level ensures the trail stays put globally 
		# even if the bullet rotates or moves
		_trail.set_as_top_level(true) 
		add_child(_trail)
		set_as_top_level(true)
		
	func _draw() -> void:
		if not _is_dead:
			draw_circle(Vector2.ZERO, 4.0, Color.WHITE)
			draw_circle(Vector2.ZERO, 2.0, Color.YELLOW)
			
	func _physics_process(delta: float) -> void:
		if _is_dead:
			return
			
		velocity.y += gravity * delta
		velocity.x += wind * delta
		
		var step = velocity * delta
		global_position += step
		_distance_traveled += step.length() # Track how far we've gone
		
		_trail.add_point(global_position)
		if _trail.get_point_count() > 20:
			_trail.remove_point(0)
			
		_check_collisions()
		
	func _check_collisions() -> void:
		# 1. Safety check: Don't collide with the shooter until we've moved 40 pixels
		if _distance_traveled < 40.0:
			return

		# 2. Out of Bounds
		if global_position.y > 2500 or abs(global_position.x) > 5000:
			_trigger_impact("out")
			return
			
		# 3. Tank Collisions
		const TANK_HIT_RADIUS := 13.0
		if is_instance_valid(game.tank_p1) and global_position.distance_to(game.tank_p1.global_position) < TANK_HIT_RADIUS:
			_trigger_impact("tank1")
			return
		if is_instance_valid(game.tank_p2) and global_position.distance_to(game.tank_p2.global_position) < TANK_HIT_RADIUS:
			_trigger_impact("tank2")
			return
			
		# 4. Ground Collision
		if is_instance_valid(game.terrain):
			var ground_y := game.terrain.get_surface_y_at_screen_x(global_position.x)
			if global_position.y >= ground_y:
				_trigger_impact("ground")
				return

	func _trigger_impact(target: String) -> void:
		_is_dead = true
		emit_signal("impact", target)
		queue_redraw() # Hides the bullet core
		
		# Fade out the trail smoothly before deleting
		var tw := create_tween()
		tw.tween_property(_trail, "modulate:a", 0.0, 0.5)
		tw.tween_callback(queue_free)

var _is_playing_round: bool = false

func _on_replay_action(_action: Dictionary) -> void:
	if _is_playing_round:
		return
	
	_is_playing_round = true
	can_interact = false
	await _set_ui_visible(false)
	
	var b := core.current_board
	var wind_val := float(b.get("wind", 0.0))
	
	# The opponent is the "other" player
	var opp_idx := 2 if core.player == 1 else 1
	
	# Get opponent's stats from the board data
	var rot := float(b.get("tank%drot" % opp_idx, 0.0))
	var pwr := float(b.get("tank%dpower" % opp_idx, 0.5))
	
	# Execute ONLY the opponent's shot
	await _execute_shot(opp_idx, rot, pwr, wind_val)
	
	_is_playing_round = false
	has_replay = false
	can_interact = true
	_on_turn_changed(core.is_my_turn)

func _play_round_sequence() -> void:
	_is_playing_round = true
	can_interact = false
	
	# 1. Fade out UI
	await _set_ui_visible(false)
	
	var b := core.current_board
	var wind_val := float(b.get("wind", 0.0))
	
	# Determine shot order. Usually, the active player goes first.
	var p1_idx := core.player
	var p2_idx := 2 if core.player == 1 else 1
	
	# Get data for both tanks
	# If it's a replay, these come from 'b'. 
	# If it's a fresh shot, p1_idx's data comes from the current barrel/slider.
	var t1_tank = tank_p1 if p1_idx == 1 else tank_p2
	var t1_rot = t1_tank.barrel_pivot.rotation
	var t1_pow = power_slider.value / 100.0
	
	var t2_rot = float(b.get("tank%drot" % p2_idx, 0.0))
	var t2_pow = float(b.get("tank%dpower" % p2_idx, 0.5))
	
	# --- EXECUTE SHOTS ---
	# Shot 1 (Current Player)
	await _execute_shot(p1_idx, t1_rot, t1_pow, wind_val)
	if _check_win_condition(): return
	
	# Shot 2 (Opponent's Last Known/Current Turn)
	await _execute_shot(p2_idx, t2_rot, t2_pow, wind_val)
	if _check_win_condition(): return
	
	_is_playing_round = false
	can_interact = true
	# Note: can_interact remains false here because we are about to send/wait
	
	# Fade UI back in (will be overridden by 'Waiting' blur in _on_send_pressed)
	_on_turn_changed(core.is_my_turn)
	
func _set_ui_visible(v: bool) -> void:
	var target_alpha := 1.0 if v else 0.0
	var tw := create_tween().set_parallel(true)
	
	# Standard UI elements
	tw.tween_property(power_slider, "modulate:a", target_alpha, 0.4)
	tw.tween_property(fire_button, "modulate:a", target_alpha, 0.4)
	
	tw.tween_property(power_label, "modulate:a", target_alpha, 0.4)
	
	if is_instance_valid(_aim_label):
		tw.tween_property(_aim_label, "modulate:a", target_alpha, 0.4)
		
	if not v: 
		tw.tween_property(waiting_label, "modulate:a", 0.0, 0.4)
		tw.tween_property(waiting_blur, "modulate:a", 0.0, 0.4)
	
	if not v:
		tank_p1.set_power_visibility(false)
		tank_p2.set_power_visibility(false)
	else:
		tank_p1.set_power_visibility(core.player == 1)
		tank_p2.set_power_visibility(core.player == 2)
		
	power_slider.editable = v
	
	await tw.finished
	
func _execute_shot(player_idx: int, rot_rad: float, power_01: float, wind_val: float) -> void:
	var tank: Tank = tank_p1 if player_idx == 1 else tank_p2
	
	var target_visual_deg = _display_deg_from_godot_rad(rot_rad)
	if player_idx != core.player:
		target_visual_deg = 180.0 - target_visual_deg
	var target_visual = _data_deg_to_visual_deg(target_visual_deg)
	
	var tw := create_tween()
	# Call your tank's setter method
	tw.tween_method(tank.set_barrel_display_deg, tank.get_barrel_display_deg(), target_visual, 0.6).set_trans(Tween.TRANS_SINE)
	await tw.finished
	await get_tree().create_timer(0.2).timeout 
	
	# 2. Spawn Bullet
	var bullet := TankBullet.new()
	bullet.game = self
	bullet.wind = wind_val * 450.0 
	
	# --- USE YOUR TANK'S HELPER ---
	bullet.global_position = tank.get_barrel_tip_global()
	
	# To get the perfect velocity direction, we look from the pivot to the tip
	var shoot_dir = (tank.barrel_tip.global_position - tank.barrel_pivot.global_position).normalized()
	bullet.velocity = shoot_dir * (power_01 * 1200.0)
	# ------------------------------
	
	add_child(bullet)
	
	# 3. Wait for impact
	var target_hit: String = await bullet.impact
	
	# 4. Handle Damage
	if target_hit == "tank1":
		_damage_tank(1)
	elif target_hit == "tank2":
		_damage_tank(2)
		
	await get_tree().create_timer(0.8).timeout
	
func _damage_tank(idx: int) -> void:
	var key := "tank1hp" if idx == 1 else "tank2hp"
	var current_hp: int = core.current_board.get(key, 3)
	current_hp = max(0, current_hp - 1)
	core.current_board[key] = current_hp
	
	# Visual updates
	_apply_health_from_board(core.current_board)
	print("Tank ", idx, " hit! HP remaining: ", current_hp)

func _check_win_condition() -> bool:
	var hp1: int = core.current_board.get("tank1hp", 3)
	var hp2: int = core.current_board.get("tank2hp", 3)
	
	if hp1 <= 0 or hp2 <= 0:
		var winner := 1 if hp2 <= 0 else 2
		print("GAME OVER! Winner is Player ", winner)
		
		_aim_label.visible = false
		waiting_label.text = "PLAYER " + str(winner) + " WINS!"
		waiting_label.visible = true
		waiting_blur.visible = true
		waiting_label.modulate.a = 1.0
		waiting_blur.modulate.a = 1.0
		
		# Prevent further interaction
		_is_playing_round = true 
		return true
		
	return false
	
	
# --- DEV MIDDLEMAN POPUP (FIXED) ---
# Replaces your current dev middleman code.
# Key fixes:
# - Clicking "SEND PAYLOAD" actually calls _send_payload(...)
# - No core.ingest_game_data(...) (it breaks turn/UI state)
# - Popup always unlocks so it can be reopened

@export var DEV_SEND_POPUP := true

const DEV_POPUP_MARGIN_PX := 16.0
const DEV_POPUP_MAX_W_PX := 720.0
const DEV_POPUP_MAX_H_FRAC := 0.92

var _dev_popup_open := false
var _dev_payload_override := ""
var _dev_force_turn := false
var _dev_skip_wait := false
var _dev_inject_shoot := true
var _dev_override_wind_enabled := false
var _dev_override_wind_value := 0.0
var _dev_kb_h_last := -1

func _on_send_pressed() -> void:
	print(">>> _on_send_pressed entered")
	if _is_playing_round:
		print(">>> blocked: _is_playing_round is true")
		return

	# Run your normal local-shot flow first (so visuals/trajectory are correct)
	print("Executing Local Shot...")
	_is_playing_round = true
	can_interact = false
	await _set_ui_visible(false)

	var my_tank: Tank = tank_p1 if core.player == 1 else tank_p2
	var my_rot := my_tank.barrel_pivot.rotation
	var my_pwr := power_slider.value / 100.0
	var wind_val := float(core.current_board.get("wind", 0.0))

	await _execute_shot(core.player, my_rot, my_pwr, wind_val)

	# Update core aim before building payload
	core.set_my_aim(my_rot, my_pwr)

	# Build avatar string
	var avatar_str := ""
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		avatar_str = player_avatar_display.get_avatar_data_string()

	# If dev popup is off, do normal send
	if not DEV_SEND_POPUP:
		core.request_send(avatar_str)
		play_sent_animation()
		_is_playing_round = false
		return
	print(">>> local shot complete, opening dev middleman")
	# Dev middleman send (this will call _send_payload itself)
	var did_send := await _dev_send_middleman_and_send(avatar_str)
	if not did_send:
		# Cancel pressed: return to normal turn UI
		_is_playing_round = false
		can_interact = true
		_on_turn_changed(core.is_my_turn)
		return

	# We already sent the payload inside the middleman.
	_is_playing_round = false
	# can_interact stays false if you want to behave like a normal send
	# If you want interaction back immediately when skipping wait:
	if _dev_skip_wait:
		can_interact = true
		_on_turn_changed(core.is_my_turn)

func _dev_send_middleman_and_send(avatar_str: String) -> bool:
	print(">>> _dev_send_middleman_and_send entered")
	if _dev_popup_open:
		print(">>> popup already open, aborting")
		return false
	_dev_popup_open = true

	# Ensure we always unlock even if something weird happens
	var accepted := false
	var base_payload: Dictionary = core.build_outbound_payload(avatar_str)
	print(">>> base_payload = ", base_payload)
	if base_payload.is_empty():
		print(">>> base_payload is empty")
	var result := await _dev_popup(JSON.stringify(base_payload, "\t"))
	print(">>> popup result = ", result)
	_dev_popup_open = false

	if not result["accepted"]:
		return false

	# Persist toggles
	_dev_force_turn = bool(result["force_turn"])
	_dev_skip_wait = bool(result["skip_wait"])
	_dev_inject_shoot = bool(result["inject_shoot"])
	_dev_override_wind_enabled = bool(result["override_wind"])
	_dev_override_wind_value = float(result["wind_value"])

	# Apply dev toggles that affect local state immediately
	if _dev_force_turn:
		core.is_my_turn = true
		spectator_mode = false
		stop_waiting_animation()
		await _set_ui_visible(true)
		can_interact = true

	# If override wind, patch board + visuals now (so your world matches the payload you send)
	if _dev_override_wind_enabled:
		core.current_board["wind"] = _dev_override_wind_value
		if is_instance_valid(sky):
			sky.set_wind(_dev_override_wind_value)
		if is_instance_valid(wind_indicator):
			wind_indicator.set_wind(_dev_override_wind_value)

	# Parse edited JSON into final payload
	var final_payload: Dictionary = {}
	var raw := String(result["json"]).strip_edges()
	var parsed: Variant = JSON.parse_string(raw)

	if typeof(parsed) == TYPE_DICTIONARY:
		final_payload = parsed as Dictionary
	else:
		# If JSON is broken, fall back
		final_payload = base_payload

	# Optional: inject shoot flag
	if _dev_inject_shoot and final_payload.has("replay"):
		var r: String = String(final_payload["replay"])
		if not r.contains("|shoot:"):
			final_payload["replay"] = r + "|shoot:1"

	# >>> THE IMPORTANT PART: SEND NOW <<<
	print("DEV MIDDLEMAN SENDING: ", final_payload)
	accepted = _send_payload(final_payload)

	if not accepted:
		print("DEV MIDDLEMAN: send failed")
		return false

	# Waiting UX
	if _dev_skip_wait:
		stop_waiting_animation()
	else:
		play_sent_animation()

	return accepted

func _dev_popup(initial_json: String) -> Dictionary:
	var out := {
		"accepted": false,
		"json": initial_json,
		"force_turn": _dev_force_turn,
		"skip_wait": _dev_skip_wait,
		"inject_shoot": _dev_inject_shoot,
		"override_wind": _dev_override_wind_enabled,
		"wind_value": _dev_override_wind_value,
	}

	var state := {
		"done": false
	}

	var root := get_tree().root

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.z_index = 5000
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var popup := Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.z_index = 5001
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(popup)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "DEV PAYLOAD OVERRIDE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)

	var te := TextEdit.new()
	te.size_flags_vertical = Control.SIZE_EXPAND_FILL
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	te.text = initial_json
	vb.add_child(te)

	var grid := GridContainer.new()
	grid.columns = 2
	vb.add_child(grid)

	var cb_turn := CheckBox.new()
	cb_turn.text = "Force My Turn"
	cb_turn.button_pressed = _dev_force_turn
	grid.add_child(cb_turn)

	var cb_skip := CheckBox.new()
	cb_skip.text = "Skip Wait UX"
	cb_skip.button_pressed = _dev_skip_wait
	grid.add_child(cb_skip)

	var cb_shoot := CheckBox.new()
	cb_shoot.text = "Inject |shoot:1"
	cb_shoot.button_pressed = _dev_inject_shoot
	grid.add_child(cb_shoot)

	var wind_hb := HBoxContainer.new()
	var cb_wind := CheckBox.new()
	cb_wind.text = "Override Wind"
	cb_wind.button_pressed = _dev_override_wind_enabled
	wind_hb.add_child(cb_wind)

	var wind_spin := SpinBox.new()
	wind_spin.min_value = -2.0
	wind_spin.max_value = 2.0
	wind_spin.step = 0.01
	wind_spin.value = _dev_override_wind_value
	wind_spin.editable = cb_wind.button_pressed
	wind_hb.add_child(wind_spin)
	grid.add_child(wind_hb)

	var hb2 := HBoxContainer.new()
	hb2.alignment = BoxContainer.ALIGNMENT_END
	hb2.add_theme_constant_override("separation", 15)
	vb.add_child(hb2)

	var btn_cancel := Button.new()
	btn_cancel.text = "CANCEL"
	hb2.add_child(btn_cancel)

	var btn_send := Button.new()
	btn_send.text = "SEND PAYLOAD"
	hb2.add_child(btn_send)

	cb_wind.toggled.connect(func(v: bool):
		wind_spin.editable = v
	)

	var close_all := func() -> void:
		state["done"] = true
		if is_instance_valid(popup):
			popup.queue_free()
		if is_instance_valid(dim):
			dim.queue_free()

	btn_cancel.pressed.connect(func():
		print(">>> DEV POPUP CANCEL PRESSED")
		out["accepted"] = false
		close_all.call()
	)

	btn_send.pressed.connect(func():
		print(">>> DEV POPUP SEND PRESSED")
		out["accepted"] = true
		out["json"] = te.text
		out["force_turn"] = cb_turn.button_pressed
		out["skip_wait"] = cb_skip.button_pressed
		out["inject_shoot"] = cb_shoot.button_pressed
		out["override_wind"] = cb_wind.button_pressed
		out["wind_value"] = float(wind_spin.value)
		close_all.call()
	)

	popup.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and not ev.echo:
			if ev.keycode == KEY_ESCAPE:
				btn_cancel.emit_signal("pressed")
	)

	var relayout := func() -> void:
		if not is_instance_valid(panel):
			return

		var vp_size := get_viewport().get_visible_rect().size

		var kb_h := 0
		if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			kb_h = int(DisplayServer.virtual_keyboard_get_height())

		var margin := DEV_POPUP_MARGIN_PX * 2.0
		var usable_h: float = max(1.0, vp_size.y - float(kb_h) - margin)

		var target_w: float = min(vp_size.x - margin, DEV_POPUP_MAX_W_PX)
		var target_h: float = min(usable_h, vp_size.y * DEV_POPUP_MAX_H_FRAC)

		panel.size = Vector2(target_w, target_h)
		panel.position = Vector2(
			(vp_size.x - target_w) * 0.5,
			(vp_size.y - float(kb_h) - target_h) * 0.5
		)

	get_viewport().size_changed.connect(func():
		relayout.call()
	)

	relayout.call()
	te.grab_focus()

	_dev_kb_h_last = -1
	var has_kb := DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)

	while not bool(state["done"]):
		if has_kb:
			var cur := int(DisplayServer.virtual_keyboard_get_height())
			if cur != _dev_kb_h_last:
				_dev_kb_h_last = cur
				relayout.call()
		await get_tree().process_frame

	print(">>> DEV POPUP RETURNING: ", out)
	return out
