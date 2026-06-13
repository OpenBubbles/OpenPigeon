extends BaseGame
class_name TanksGame

@onready var world: Node2D = %World
@onready var player_avatar_display: Control = %PlayerAvatarDisplay
@onready var opp_avatar_display: Control = %OppAvatarDisplay
@onready var sent_label: Label = %SentLabel
@onready var win_loss_label: Label = %WinLossLabel
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
@onready var spec_label: Label = %SpecLabel

const MUSIC_STREAM := preload("res://global/audio/tanks.ogg")

var core: TanksCore
var sent_tween: Tween
var _view_flipped: bool = false
var _is_dragging_aim: bool = false
var can_interact: bool = true
var has_replay: bool = false

var game_over: bool = false
var winner: String = ""
var win_loss_state: String = ""

const HEALTH_TEX := {
	0: preload("res://tanks/tanks_health_0.png"),
	1: preload("res://tanks/tanks_health_1.png"),
	2: preload("res://tanks/tanks_health_2.png"),
	3: preload("res://tanks/tanks_health_3.png"),
}

const LOG_TAG := "Tanks"
const DEBUG_TANKS := false

func dbg(parts: Variant) -> void:
	if DEBUG_TANKS:
		OpLog.d(LOG_TAG, parts)

func _replay_summary(raw: String) -> String:
	return "len=%d boards=%d shoots=%d" % [
		raw.length(),
		raw.count("board:"),
		raw.count("shoot:")
	]

func _board_summary(board: Dictionary) -> String:
	if board.is_empty():
		return "empty"

	return "height=%s wind=%s hp1=%s hp2=%s t1x=%s t2x=%s t1rot=%s t2rot=%s t1p=%s t2p=%s" % [
		str(board.get("height", "")),
		str(board.get("wind", "")),
		str(board.get("tank1hp", "")),
		str(board.get("tank2hp", "")),
		str(board.get("tank1x", "")),
		str(board.get("tank2x", "")),
		str(board.get("tank1rot", "")),
		str(board.get("tank2rot", "")),
		str(board.get("tank1power", "")),
		str(board.get("tank2power", ""))
	]

func _state_summary() -> String:
	if core == null:
		return "core=null gameOver=%s winner=%s" % [str(game_over), winner]

	return "player=%d turn=%s spectator=%s replay=%s winner=%s playing=%s interact=%s gameOver=%s state=%s board={%s}" % [
		core.player,
		str(core.is_my_turn),
		str(core.spectator_mode),
		str(has_replay),
		str(game_over),
		str(_is_playing_round),
		str(can_interact),
		str(game_over),
		win_loss_state,
		_board_summary(core.current_board)
	]

const TANK1_COLOR := Color(0.25, 0.55, 1.0, 1.0) # Blue
const TANK2_COLOR := Color(1.0, 0.25, 0.25, 1.0) # Red

const BOARD_X_MIN := -220.0
const BOARD_X_MAX := 220.0
const BOARD_X_WIDTH := BOARD_X_MAX - BOARD_X_MIN # 440.0  (iOS board_size = 220 half-width)

const SHOT_FIXED_DT := 1.0 / 60.0

# --- Physics constants (measured directly from iOS via Frida) ---
const SHOT_GRAVITY_UNITS := -200.8       # bullet vertical accel, px/s^2
const SHOT_SPEED_SLOPE_01 := 340.0047    # v0 = SLOPE * power_01 + INTERCEPT
const SHOT_SPEED_INTERCEPT := 60.0029
const SHOT_WIND_AX_PER_UNIT := 11.9367   # bullet ax = wind_value × this
const SHOT_LINEAR_DAMPING := 0.0
const SHOT_MUZZLE_OFFSET_UNITS := 20.0
const SHOT_BULLET_RADIUS_UNITS := 1.0    # iOS bullet fixture radius
const SHOT_TANK_HALF_W_UNITS := 11.5     # iOS tank box half width
const SHOT_TANK_HALF_H_UNITS := 6.0      # iOS tank box half height
const SHOT_SAFE_TRAVEL_UNITS := 40.0
const SHOT_OUT_Y_UNITS := 2500.0
const SHOT_OUT_X_UNITS := 5000.0

const TANK_WIDTH_UNITS := 25.0
const TANK_HALF_WIDTH_UNITS := TANK_WIDTH_UNITS * 0.5

func _game_x_to_screen_x(game_x: float) -> float:
	if not is_instance_valid(terrain):
		return game_x
	
	return remap(game_x, BOARD_X_MIN, BOARD_X_MAX, 0.0, terrain.get_world_width())

var _aim_label: Label

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM
	
func _get_dev_data() -> String:
	return JSON.stringify({
		"myPlayerId": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb",
		"player1": "82B2A470-70BC-4EDF-9AAA-0B99A98C58DAj2fM2b",
		"player2": "AA3B9A3D-4EA9-41ED-AC35-395DBBC9AEA0XBHDAb",
		"player": "1",
		"isYourTurn": true,
		"avatar1": "body,3|eyes,6|mouth,3|acc,0|wins,0|bg_color,0.933333,0.407843,0.647059|body_color,0.968627,0.811765,0.333333|glasses,0|stache,0|backdrop,0|hair,0|clothes,2|hair_color,0.505882,0.725490,0.254902|clothes_color,0.686657,0.686657,0.686657",
		"avatar2": "",
		"replay": "board:height,0.0&wind,-1.0&tank1x,-150.0&tank1rot,4.960246&tank1power,0.82741&tank1hp,3&tank2x,150.0&tank2rot,-4.960246&tank2power,0.82741&tank2hp,2|shoot:1"
	})
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display

func _get_rules_title() -> String:
	return "Tanks"

func _on_game_ready() -> void:
	OpLog.game_opened(LOG_TAG, ["localMode=", appPlugin == null, " uuid=", my_uuid])
	core = TanksCore.new()
	add_child(core)

	core.replay_true.connect(_on_has_replay)
	core.winner_true.connect(_has_winner)
	core.turn_changed.connect(_on_turn_changed)
	core.board_loaded.connect(_on_board_loaded)
	core.replay_action.connect(_on_replay_action)
	core.outbound_ready.connect(_send_payload)
	core.opponent_avatar_ready.connect(_on_opponent_avatar_received)

	if is_instance_valid(fire_button):
		if not fire_button.pressed.is_connected(_on_send_pressed):
			fire_button.pressed.connect(_on_send_pressed)

		if not fire_button.button_down.is_connected(_on_fire_button_down):
			fire_button.button_down.connect(_on_fire_button_down)

		if not fire_button.button_up.is_connected(_on_fire_button_up):
			fire_button.button_up.connect(_on_fire_button_up)

	if is_instance_valid(power_slider):
		if not power_slider.value_changed.is_connected(_on_power_slider_changed):
			power_slider.value_changed.connect(_on_power_slider_changed)

	if not resized.is_connected(_on_resized):
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

	if is_instance_valid(fire_button):
		fire_button.modulate.a = 0.0

	if is_instance_valid(power_slider):
		power_slider.modulate.a = 0.0
		power_slider.editable = false

	if is_instance_valid(power_label):
		power_label.modulate.a = 0.0

	if is_instance_valid(_aim_label):
		_aim_label.modulate.a = 0.0

	if is_instance_valid(tank_p1):
		tank_p1.set_power_visibility(false)

	if is_instance_valid(tank_p2):
		tank_p2.set_power_visibility(false)

	can_interact = false
	
	OpLog.i(LOG_TAG, [
		"game_ready localMode=", appPlugin == null,
		" fireButton=", is_instance_valid(fire_button),
		" powerSlider=", is_instance_valid(power_slider),
		" terrain=", is_instance_valid(terrain),
		" tank1=", is_instance_valid(tank_p1),
		" tank2=", is_instance_valid(tank_p2)
	])

func _set_game_data(raw_text: String) -> void:
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", raw_text])

	var parsed: Variant = JSON.parse_string(raw_text)

	if typeof(parsed) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, ["set_game_data invalid JSON raw=", raw_text])
		return

	var data: Dictionary = parsed

	if my_uuid != "":
		data["myPlayerId"] = my_uuid

	var winner_payload: String = str(data.get("winner", ""))
	var p1_id: String = str(data.get("player1", ""))
	var p2_id: String = str(data.get("player2", ""))
	
	OpLog.i(LOG_TAG, [
		"set_game_data parsed_initial isYourTurn=", str(data.get("isYourTurn", "")),
		" payloadPlayer=", str(data.get("player", "")),
		" p1=", p1_id,
		" p2=", p2_id,
		" winner=", winner_payload,
		" replay=", _replay_summary(str(data.get("replay", "")))
	])

	game_over = false
	winner = ""
	win_loss_state = ""
	can_interact = false
	has_replay = false

	stop_waiting_animation()

	if is_instance_valid(win_loss_label):
		win_loss_label.visible = false
		win_loss_label.text = ""
		win_loss_label.scale = Vector2.ONE
		win_loss_label.modulate.a = 1.0

	core.ingest_game_data(JSON.stringify(data))
	OpLog.i(LOG_TAG, ["set_game_data core_ingested ", _state_summary()])
	_apply_view_flip()

	if is_instance_valid(spec_label):
		spec_label.visible = core.spectator_mode

	_update_avatars()
	_apply_health_colors()

	if not core.current_board.is_empty():
		_apply_health_from_board(core.current_board)

	_apply_tank_colors()

	if not core.current_board.is_empty():
		call_deferred("_apply_tanks_from_board", core.current_board)

	_update_aim_label_visibility()

	if winner_payload != "":
		_apply_winner_payload(winner_payload, p1_id, p2_id)
	
	OpLog.i(LOG_TAG, ["set_game_data_done ", _state_summary()])

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
	
func _units_vec_to_screen_delta(units: Vector2) -> Vector2:
	var x_sign: float = -1.0 if _view_flipped else 1.0
	return Vector2(
		x_sign * _board_units_to_screen_px(units.x),
		-_board_units_to_screen_px(units.y)
	)
	
func _bullet_global_to_terrain_screen_pos(bullet_global_pos: Vector2) -> Vector2:
	if not _view_flipped or not is_instance_valid(world):
		return bullet_global_pos
	var vp_w: float = get_viewport().get_visible_rect().size.x
	return Vector2(vp_w - bullet_global_pos.x, bullet_global_pos.y)

func _get_original_launch_angle(player_idx: int, rot_rad: float) -> float:
	if player_idx == 1:
		return rot_rad
	return -PI - rot_rad
	
func _protocol_rot_from_visual_deg(player_idx: int, visual_deg: float) -> float:
	visual_deg = clampf(visual_deg, 0.0, 180.0)
	var a := deg_to_rad(visual_deg)

	if player_idx == 1:
		return a

	return a - 2.0 * PI

func _launch_angle_from_protocol_rot(player_idx: int, rot_rad: float) -> float:
	if player_idx == 1:
		return rot_rad

	return -PI - rot_rad


func _visual_deg_from_protocol_rot(player_idx: int, rot_rad: float) -> float:
	var a_rad: float
	if player_idx == 1:
		a_rad = rot_rad
	else:
		a_rad = rot_rad + 2.0 * PI

	var deg := rad_to_deg(a_rad)
	deg = fposmod(deg, 360.0)

	if deg > 180.0:
		deg = 360.0 - deg

	return clampf(deg, 0.0, 180.0)

func _get_launch_speed_units(power_01: float) -> float:
	power_01 = clampf(power_01, 0.0, 1.0)
	# Measured directly from iOS across 4 shots: v0 = 340.0047 * power_01 + 60.0029
	return SHOT_SPEED_SLOPE_01 * power_01 + SHOT_SPEED_INTERCEPT

func _get_shot_spawn_screen_position(tank: Tank, launch_angle: float) -> Vector2:
	var muzzle_base: Vector2 = tank.barrel_pivot.global_position
	var x_sign: float = -1.0 if _view_flipped else 1.0
	var muzzle_offset_screen: Vector2 = Vector2(
		x_sign * cos(launch_angle),
		-sin(launch_angle)
	) * _board_units_to_screen_px(SHOT_MUZZLE_OFFSET_UNITS)

	return muzzle_base + muzzle_offset_screen

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
		
func _get_pixels_per_board_unit() -> float:
	if not is_instance_valid(terrain):
		return 1.0
	
	return terrain.get_world_width() / BOARD_X_WIDTH

func _board_units_to_screen_px(units: float) -> float:
	return units * _get_pixels_per_board_unit()

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
	if _view_flipped or core.player == 1:
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
	
	OpLog.i(LOG_TAG, ["health_update myHp=", my_hp, " oppHp=", opp_hp])

	_set_health_tex(player_health, my_hp)
	_set_health_tex(opp_health, opp_hp)

func _apply_tank_colors() -> void:
	var hp1: int = int(core.current_board.get("tank1hp", 3)) if core != null else 3
	var hp2: int = int(core.current_board.get("tank2hp", 3)) if core != null else 3
	dbg(["tank_colors hp1=", hp1, " hp2=", hp2])
	if is_instance_valid(tank_p1):
		tank_p1.set_player_color(Color.BLACK if hp1 <= 0 else TANK1_COLOR)
	if is_instance_valid(tank_p2):
		tank_p2.set_player_color(Color.BLACK if hp2 <= 0 else TANK2_COLOR)

func _on_board_loaded(board: Dictionary) -> void:
	_apply_health_from_board(board)

	var h: float = float(board.get("height", 0.0))
	var w: float = float(board.get("wind", 0.0))
	OpLog.i(LOG_TAG, ["board_loaded wind=", w, " height=", h, " board={", _board_summary(board), "}"])
	if is_instance_valid(terrain):
		terrain.apply_board(h, false)
		
	var w_visual: float = -w if _view_flipped else w
	if is_instance_valid(sky):
		sky.set_wind(w_visual)

		
	if is_instance_valid(wind_indicator):
		wind_indicator.set_wind(w_visual)
		dbg(["wind_visual=", w_visual, " raw=", w, " flipped=", _view_flipped])

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
	dbg([
		"tank_sizes ppu=", ppu,
		" targetWidth=", tank_w,
		" p1Width=", tank_p1.get_body_width_px() if is_instance_valid(tank_p1) else -1.0,
		" p2Width=", tank_p2.get_body_width_px() if is_instance_valid(tank_p2) else -1.0
	])

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

	var p1_visual_deg: float = _visual_deg_from_protocol_rot(1, r1)
	var p2_visual_deg: float = 180.0 - _visual_deg_from_protocol_rot(2, r2)

	tank_p1.set_barrel_display_deg(p1_visual_deg)
	tank_p2.set_barrel_display_deg(p2_visual_deg)

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
	core.set_my_aim(_protocol_rot_from_visual_deg(core.player, my_tank.get_barrel_display_deg()), my_power)
	
	var should_show_power = core.is_my_turn and not _is_playing_round
	tank_p1.set_power_visibility(should_show_power and core.player == 1)
	tank_p2.set_power_visibility(should_show_power and core.player == 2)
	_update_aim_label_visibility()
	
func _display_deg_from_godot_rad(godot_rad: float) -> float:
	var raw_deg = rad_to_deg(godot_rad) 
	var visual_deg = fmod(abs(raw_deg), 360.0)
	
	if visual_deg > 180.0:
		visual_deg = 360.0 - visual_deg

	var final_data_deg = _visual_deg_to_data_deg(visual_deg)
	
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

	if not _flip_view:
		tank_p1.barrel_sprite.scale.y = -tank_p1.barrel_sprite.scale.y
	
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
	
	var rot_rad := _protocol_rot_from_visual_deg(core.player, my_tank.get_barrel_display_deg())
	core.set_my_aim(rot_rad, p_01)
	
	_update_aim_label_position()
	
func _unhandled_input(event: InputEvent) -> void:
	if core == null or core.spectator_mode or not core.is_my_turn or not can_interact or _is_playing_round:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging_aim = true
			_handle_aim_at_screen_pos(event.position)
		else:
			_is_dragging_aim = false
		return

	if event is InputEventMouseMotion and _is_dragging_aim:
		_handle_aim_at_screen_pos(event.position)
		
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
	core.set_my_aim(_protocol_rot_from_visual_deg(core.player, my_tank.get_barrel_display_deg()), p_01)
	
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
	OpLog.i(LOG_TAG, ["has_replay=", r, " ", _state_summary()])
	
func _has_winner(w: bool) -> void:
	OpLog.i(LOG_TAG, ["has_winner=", w, " ", _state_summary()])
	game_over = w

	if game_over:
		can_interact = false
		stop_waiting_animation()

		if is_instance_valid(_aim_label):
			_aim_label.visible = false

func _on_turn_changed(v: bool) -> void:
	OpLog.i(LOG_TAG, [
		"turn_changed turn=", v,
		" blockedByReplay=", has_replay,
		" playing=", _is_playing_round,
		" spectator=", core.spectator_mode if core != null else false,
		" boardEmpty=", core.current_board.is_empty() if core != null else true
	])
	if _is_playing_round or has_replay or core.current_board.is_empty() or core.spectator_mode:
		can_interact = false
		stop_waiting_animation()
		await _set_ui_visible(false)
		_update_aim_label_visibility()
		return
		
	if v:
		stop_waiting_animation()
		can_interact = true
		await _set_ui_visible(true)
	else:
		can_interact = false
		await _set_ui_visible(false)
		if not game_over:
			_start_waiting_for_opponent()	
	
	_update_aim_label_visibility()

func _send_payload(payload: Dictionary) -> bool:
	if game_over and win_loss_state != "":
		var sender_id := my_uuid

		if sender_id == "" and core != null:
			sender_id = core.my_id

		if sender_id != "" and not payload.has("winner"):
			payload["winner"] = sender_id + "|" + win_loss_state

	var json := JSON.stringify(payload)

	OpLog.event(LOG_TAG, [
		"send_game_out replay=", _replay_summary(String(payload.get("replay", ""))),
		" winner=", str(payload.get("winner", "")),
		" avatar1=", payload.has("avatar1"),
		" avatar2=", payload.has("avatar2"),
		" ", _state_summary(),
		" raw=", json
	])

	send_game_data(json)

	return true

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

func _get_rules_text() -> String:
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
		OpLog.w(LOG_TAG, "play_sent_animation skipped: sent_label invalid")
		return

	if game_over or (core != null and core.spectator_mode):
		stop_waiting_animation()
		return

	stop_waiting_animation()

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

		if not game_over and core != null and not core.spectator_mode and not core.is_my_turn:
			_start_waiting_for_opponent()
		else:
			stop_waiting_animation()
	)

func _start_waiting_for_opponent() -> void:
	if is_instance_valid(waiting_label):
		waiting_label.modulate.a = 1.0

	if is_instance_valid(waiting_blur):
		waiting_blur.modulate.a = 1.0

	start_waiting_animation()

func _update_avatars() -> void:
	if not is_instance_valid(player_avatar_display) or not is_instance_valid(opp_avatar_display):
		return

	var my_key := ("avatar1" if core.player == 1 else "avatar2")
	var my_str := (core.avatar1_str if my_key == "avatar1" else core.avatar2_str)
	
	if player_avatar_display.has_method("update_avatar_from_string") and my_str != "":
		player_avatar_display.update_avatar_from_string(my_str)

func _circle_intersects_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest_x: float = clampf(center.x, rect.position.x, rect.position.x + rect.size.x)
	var closest_y: float = clampf(center.y, rect.position.y, rect.position.y + rect.size.y)
	var closest: Vector2 = Vector2(closest_x, closest_y)
	return center.distance_squared_to(closest) <= radius * radius

func _circle_intersects_tank(center: Vector2, radius: float, tank: Tank) -> bool:
	if not is_instance_valid(tank) or not is_instance_valid(tank.body) or tank.body.texture == null:
		return false

	var tex_size := Vector2(
		float(tank.body.texture.get_width()),
		float(tank.body.texture.get_height())
	)

	var scaled_size := Vector2(
		tex_size.x * abs(tank.scale.x * tank.body.scale.x),
		tex_size.y * abs(tank.scale.y * tank.body.scale.y)
	)

	var top_left := tank.global_position - Vector2(scaled_size.x * 0.5, scaled_size.y)
	var rect := Rect2(top_left, scaled_size)

	return _circle_intersects_rect(center, radius, rect)

func _bullet_hits_tank_ios(bullet_screen_pos: Vector2, tank: Tank) -> bool:
	if not is_instance_valid(tank):
		return false
	var ppu := _get_pixels_per_board_unit()
	var hw_px := SHOT_TANK_HALF_W_UNITS * ppu
	var full_h_px := SHOT_TANK_HALF_H_UNITS * 2.0 * ppu
	var radius_px := SHOT_BULLET_RADIUS_UNITS * ppu
	# top_left.y is full_h_px above tank position (since y down means -y is up)
	var top_left := tank.global_position - Vector2(hw_px, full_h_px)
	var rect := Rect2(top_left, Vector2(hw_px * 2.0, full_h_px))
	return _circle_intersects_rect(bullet_screen_pos, radius_px, rect)
	
func _bullet_swept_hits_tank_ios(prev_pos: Vector2, curr_pos: Vector2, tank: Tank) -> bool:
	if not is_instance_valid(tank):
		return false
	# If we don't have a valid prev_pos, fall back to point in time check
	if prev_pos.x == INF or prev_pos.y == INF:
		return _bullet_hits_tank_ios(curr_pos, tank)
	var ppu := _get_pixels_per_board_unit()
	var hw_px := SHOT_TANK_HALF_W_UNITS * ppu
	var full_h_px := SHOT_TANK_HALF_H_UNITS * 2.0 * ppu
	var radius_px := SHOT_BULLET_RADIUS_UNITS * ppu
	var top_left := tank.global_position - Vector2(hw_px, full_h_px)
	var rect := Rect2(top_left, Vector2(hw_px * 2.0, full_h_px))
	return _segment_circle_intersects_rect(prev_pos, curr_pos, radius_px, rect)

func _segment_circle_intersects_rect(a: Vector2, b: Vector2, r: float, rect: Rect2) -> bool:
	var seg_min := Vector2(min(a.x, b.x) - r, min(a.y, b.y) - r)
	var seg_max := Vector2(max(a.x, b.x) + r, max(a.y, b.y) + r)
	if seg_max.x < rect.position.x or seg_min.x > rect.position.x + rect.size.x:
		return false
	if seg_max.y < rect.position.y or seg_min.y > rect.position.y + rect.size.y:
		return false
	# Endpoint check (covers stationary or near-stationary case)
	if _circle_intersects_rect(a, r, rect) or _circle_intersects_rect(b, r, rect):
		return true
	# Subdivide segment based on length and radius
	var seg_len := a.distance_to(b)
	if seg_len <= 0.0001:
		return false
	var step_count := int(ceil(seg_len / max(r * 0.5, 1.0)))
	step_count = clamp(step_count, 4, 64)
	for i in range(1, step_count):
		var t := float(i) / float(step_count)
		var p := a.lerp(b, t)
		if _circle_intersects_rect(p, r, rect):
			return true
	return false
	
func _play_impact_feedback(impact_pos: Vector2, target_hit: String) -> void:
	var is_tank_hit := target_hit.begins_with("tank")
	_haptic_explosion(1.0 if is_tank_hit else 0.65, 55 if is_tank_hit else 35)
	_start_camera_shake(5.0 if is_tank_hit else 3.0)
	_spawn_impact_fx(impact_pos, target_hit)

func _haptic_explosion(strength: float = 1.0, duration_ms: int = 45) -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return

	strength = clampf(strength, 0.0, 1.0)
	Input.vibrate_handheld(duration_ms, strength)


func _start_camera_shake(strength: float = 4.0) -> void:
	if not is_instance_valid(world):
		return

	var original_pos := world.position
	var tw := create_tween()

	for i in range(6):
		var falloff := 1.0 - float(i) / 6.0
		var offset := Vector2(
			randf_range(-strength, strength) * falloff,
			randf_range(-strength, strength) * falloff
		)
		tw.tween_property(world, "position", original_pos + offset, 0.025)

	tw.tween_property(world, "position", original_pos, 0.04)


func _spawn_impact_fx(impact_pos: Vector2, target_hit: String) -> void:
	var root := Node2D.new()
	root.set_as_top_level(true)
	root.global_position = impact_pos
	root.z_index = 900
	add_child(root)

	var is_tank_death := target_hit == "tank_death"
	var is_tank_hit := target_hit.begins_with("tank") and not is_tank_death

	var count: int
	var max_dist: float
	var dot_size: float
	var duration: float
	if is_tank_death:
		count = 70
		max_dist = 110.0
		dot_size = 9.0
		duration = 0.75
	elif is_tank_hit:
		count = 34
		max_dist = 58.0
		dot_size = 7.0
		duration = 0.48
	else:
		count = 18
		max_dist = 34.0
		dot_size = 5.5
		duration = 0.38

	for i in range(count):
		var dot := ColorRect.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size = Vector2(dot_size, dot_size)
		dot.pivot_offset = dot.size * 0.5
		dot.position = -dot.pivot_offset

		if is_tank_death or is_tank_hit:
			if i % 4 == 0:
				dot.color = Color(1.0, 0.18, 0.03, 0.95)
			elif i % 4 == 1:
				dot.color = Color(1.0, 0.62, 0.08, 0.9)
			else:
				dot.color = Color(0.08, 0.08, 0.08, 0.72)
		else:
			dot.color = Color(0.50, 0.39, 0.25, 0.62)

		root.add_child(dot)

		var angle := randf_range(0.0, TAU)
		var dist := randf_range(12.0, max_dist)
		var end_pos := Vector2(cos(angle), sin(angle)) * dist

		var tw := create_tween().set_parallel(true)
		tw.tween_property(dot, "position", end_pos - dot.pivot_offset, duration)
		tw.tween_property(dot, "modulate:a", 0.0, duration)
		tw.tween_property(dot, "scale", Vector2.ONE * randf_range(1.4, 2.4), duration)

	await get_tree().create_timer(duration + 0.25).timeout
	if is_instance_valid(root):
		root.queue_free()
		
func _spawn_muzzle_flash(muzzle_pos: Vector2, launch_angle: float) -> void:
	var root := Node2D.new()
	root.set_as_top_level(true)
	root.global_position = muzzle_pos
	root.z_index = 950
	add_child(root)

	var x_sign: float = -1.0 if _view_flipped else 1.0
	var forward := Vector2(x_sign * cos(launch_angle), -sin(launch_angle))
	var side := Vector2(-forward.y, forward.x)

	for i in range(12):
		var dot := ColorRect.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.size = Vector2(4.0, 4.0)
		dot.pivot_offset = dot.size * 0.5
		dot.position = -dot.pivot_offset
		dot.color = Color(1.0, 0.72, 0.20, 0.9) if i % 2 == 0 else Color(0.75, 0.75, 0.75, 0.5)
		root.add_child(dot)

		var spread := randf_range(-9.0, 9.0)
		var push := randf_range(10.0, 28.0)
		var end_pos := forward * push + side * spread

		var tw := create_tween().set_parallel(true)
		tw.tween_property(dot, "position", end_pos - dot.pivot_offset, 0.18)
		tw.tween_property(dot, "modulate:a", 0.0, 0.18)
		tw.tween_property(dot, "scale", Vector2.ONE * 1.6, 0.18)

	await get_tree().create_timer(0.25).timeout
	if is_instance_valid(root):
		root.queue_free()
		
class TankBullet extends Node2D:
	signal impact(target_hit: String)

	var game: TanksGame
	var origin_screen_position: Vector2 = Vector2.ZERO
	var position_units: Vector2 = Vector2.ZERO
	var velocity_units: Vector2 = Vector2.ZERO
	var gravity_units: float = SHOT_GRAVITY_UNITS
	var wind_accel_units: float = 0.0     # iOS units/s^2, set as wind_value * SHOT_WIND_AX_PER_UNIT

	var _distance_traveled_units: float = 0.0
	var _trail: Line2D
	var _is_dead: bool = false
	var _step_accum: float = 0.0
	var _trail_max_length_px: float = 170.0
	var _trail_min_point_spacing_px: float = 1.5

	func _ready() -> void:
		set_as_top_level(true)

		_trail = Line2D.new()
		_trail.width = 4.0
		_trail.default_color = Color.WHITE
		_trail.antialiased = true
		_trail.joint_mode = Line2D.LINE_JOINT_ROUND
		_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
		_trail.gradient = Gradient.new()
		_trail.gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
		_trail.gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.85))
		_trail.set_as_top_level(true)
		add_child(_trail)

	func _draw() -> void:
		if _is_dead:
			return

		draw_circle(Vector2.ZERO, 4.0, Color.WHITE)
		draw_circle(Vector2.ZERO, 2.0, Color.YELLOW)

	func _physics_process(delta: float) -> void:
		if _is_dead:
			return

		_step_accum += delta

		while _step_accum >= SHOT_FIXED_DT and not _is_dead:
			_step_accum -= SHOT_FIXED_DT
			_step_simulation()
			
	func _update_trail(point: Vector2) -> void:
		if not is_instance_valid(_trail):
			return

		var point_count := _trail.get_point_count()

		if point_count == 0:
			_trail.add_point(point)
			return

		var last_point := _trail.get_point_position(point_count - 1)
		var dist := last_point.distance_to(point)

		if dist <= 0.01:
			return

		var steps: int = max(1, int(ceil(dist / _trail_min_point_spacing_px)))

		for i in range(1, steps + 1):
			var t := float(i) / float(steps)
			var interpolated_point := last_point.lerp(point, t)
			_trail.add_point(interpolated_point)

		_trim_trail_to_max_length()

	func _trim_trail_to_max_length() -> void:
		while _trail.get_point_count() >= 2 and _get_trail_length_px() > _trail_max_length_px:
			_trail.remove_point(0)


	func _get_trail_length_px() -> float:
		var total := 0.0

		for i in range(1, _trail.get_point_count()):
			total += _trail.get_point_position(i - 1).distance_to(_trail.get_point_position(i))

		return total

	func _step_simulation() -> void:

		velocity_units.y += gravity_units * SHOT_FIXED_DT
		velocity_units.x += wind_accel_units * SHOT_FIXED_DT

		var step_units := velocity_units * SHOT_FIXED_DT
		var prev_global_position := global_position
		position_units += step_units
		_distance_traveled_units += step_units.length()

		global_position = origin_screen_position + game._units_vec_to_screen_delta(position_units)

		_update_trail(global_position)

		_check_collisions(prev_global_position)


	func _check_collisions(prev_pos: Vector2 = Vector2.INF) -> void:
		if _distance_traveled_units < SHOT_SAFE_TRAVEL_UNITS:
			return

		var terrain_pos: Vector2 = game._bullet_global_to_terrain_screen_pos(global_position)
		var pos_units_x := game._screen_x_to_game_x(terrain_pos.x)

		if abs(position_units.y) > SHOT_OUT_Y_UNITS or abs(pos_units_x) > SHOT_OUT_X_UNITS:
			_trigger_impact("out")
			return

		# iOS-spec hit detection: bullet circle (r=1.0 iOS units) vs tank box (half extents 11.5×6.0 iOS-units, centered on tank's body origin = terrain surface y at tank.x). Uses swept-circle vs box check to match iOS's continuous-collision behavior despite our discrete time steps
		var ppu := game._get_pixels_per_board_unit()
		var radius_px := SHOT_BULLET_RADIUS_UNITS * ppu

		if game._bullet_swept_hits_tank_ios(prev_pos, global_position, game.tank_p1):
			_trigger_impact("tank1")
			return

		if game._bullet_swept_hits_tank_ios(prev_pos, global_position, game.tank_p2):
			_trigger_impact("tank2")
			return

		if is_instance_valid(game.terrain) and game.terrain.has_tower():
			var tower_rect := game.terrain.get_tower_rect()
			if game._circle_intersects_rect(terrain_pos, radius_px, tower_rect):
				_trigger_impact("tower")
				return

		if is_instance_valid(game.terrain):
			var ground_y := game.terrain.get_surface_y_at_screen_x(terrain_pos.x)
			if terrain_pos.y >= ground_y:
				_trigger_impact("ground")
				return

	func _trigger_impact(target: String) -> void:
		_is_dead = true
		var impact_pos := global_position

		if is_instance_valid(_trail):
			if _trail.get_point_count() == 0 or _trail.get_point_position(_trail.get_point_count() - 1).distance_to(impact_pos) > 0.5:
				_trail.add_point(impact_pos)

		if is_instance_valid(game):
			game._play_impact_feedback(impact_pos, target)

		emit_signal("impact", target)
		queue_redraw()

		var tw := create_tween()
		tw.tween_interval(0.25)
		tw.tween_property(_trail, "modulate:a", 0.0, 0.55)
		tw.tween_callback(queue_free)
		
var _is_playing_round: bool = false

func _on_replay_action(_action: Dictionary) -> void:
	if _is_playing_round:
		OpLog.w(LOG_TAG, ["replay_action skipped already_playing action=", _action])
		return

	OpLog.i(LOG_TAG, ["replay_action_start action=", _action, " ", _state_summary()])
	
	_is_playing_round = true
	can_interact = false
	await _set_ui_visible(false)
	
	var b := core.current_board
	var wind_val := float(b.get("wind", 0.0))
	
	var is_own_replay: bool = not core.is_my_turn
	var shooter_idx: int = core.player if is_own_replay else (2 if core.player == 1 else 1)

	var rot := float(b.get("tank%drot" % shooter_idx, 0.0))
	var pwr := float(b.get("tank%dpower" % shooter_idx, 0.5))
	dbg(["replay_core_player=", core.player, " isOwnReplay=", is_own_replay])
	
	if (core.player == 1 and not is_own_replay) or (core.player == 2 and is_own_replay):
		OpLog.i(LOG_TAG, [
			"replay_flip_adjust player=", core.player,
			" shooter=", shooter_idx,
			" beforeRot=", rot
		])
		var replay_visual_deg := _visual_deg_from_protocol_rot(shooter_idx, rot)
		replay_visual_deg = 180.0 - replay_visual_deg
		rot = _protocol_rot_from_visual_deg(shooter_idx, replay_visual_deg)
	
	await _execute_shot(shooter_idx, rot, pwr, wind_val)
	
	OpLog.i(LOG_TAG, [
		"replay_action_shot_done shooter=", shooter_idx,
		" rot=", rot,
		" power=", pwr,
		" wind=", wind_val,
		" postShot={", _board_summary(core._post_shot_board), "}"
	])

	var post_shot: Dictionary = core.consume_post_shot_board()
	if not post_shot.is_empty():
		if post_shot.has("tank1hp"):
			core.current_board["tank1hp"] = int(post_shot["tank1hp"])
		if post_shot.has("tank2hp"):
			core.current_board["tank2hp"] = int(post_shot["tank2hp"])
		_apply_health_from_board(core.current_board)
		_apply_tank_colors()

	if not is_own_replay and core.player == 1:
		var new_wind: float = randf_range(-1.0, 1.0)
		core.current_board["wind"] = new_wind
		var w_visual: float = -new_wind if _view_flipped else new_wind
		if is_instance_valid(sky):
			sky.set_wind(w_visual)
		if is_instance_valid(wind_indicator):
			wind_indicator.set_wind(w_visual)

	if _finish_round_or_show_result():
		return
		
	OpLog.i(LOG_TAG, ["replay_action_done ", _state_summary()])
	
	_is_playing_round = false
	has_replay = false
	can_interact = true
	_on_turn_changed(core.is_my_turn)

func _play_round_sequence() -> void:
	OpLog.i(LOG_TAG, ["round_sequence_start ", _state_summary()])
	_is_playing_round = true
	can_interact = false
	
	await _set_ui_visible(false)
	
	var b := core.current_board
	var wind_val := float(b.get("wind", 0.0))
	
	# Determine shot order. Usually, the active player goes first
	var p1_idx := core.player
	var p2_idx := 2 if core.player == 1 else 1
	
	# Get data for both tanks
	# If it's a replay, these come from 'b'
	# If it's a fresh shot, p1_idx's data comes from the current barrel/slider
	var t1_tank = tank_p1 if p1_idx == 1 else tank_p2
	var t1_rot = _protocol_rot_from_visual_deg(p1_idx, t1_tank.get_barrel_display_deg())
	var t1_pow = power_slider.value / 100.0
	
	var t2_rot = float(b.get("tank%drot" % p2_idx, 0.0))
	var t2_pow = float(b.get("tank%dpower" % p2_idx, 0.5))
	
	# --- EXECUTE SHOTS ---
	# Shot 1 (Current Player)
	await _execute_shot(p1_idx, t1_rot, t1_pow, wind_val)
	if _check_win_condition():
		return
	
	# Shot 2 (Opponent's Last Known/Current Turn)
	await _execute_shot(p2_idx, t2_rot, t2_pow, wind_val)
	if _check_win_condition():
		return
		
	OpLog.i(LOG_TAG, ["round_sequence_done ", _state_summary()])
	
	_is_playing_round = false
	can_interact = true
	_on_turn_changed(core.is_my_turn)
	
func _set_ui_visible(v: bool) -> void:
	var target_alpha := 1.0 if v else 0.0
	var tw := create_tween().set_parallel(true)
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

	var target_visual := _visual_deg_from_protocol_rot(player_idx, rot_rad)
	
	var launch_speed := _get_launch_speed_units(power_01)
	OpLog.i(LOG_TAG, [
		"shot_start shooter=", player_idx,
		" protocolRot=", rot_rad,
		" visualDeg=", target_visual,
		" power=", power_01,
		" wind=", wind_val,
		" speed=", launch_speed
	])

	var tw := create_tween()
	tw.tween_method(tank.set_barrel_display_deg, tank.get_barrel_display_deg(), target_visual, 0.6).set_trans(Tween.TRANS_SINE)
	await tw.finished
	await get_tree().create_timer(0.2).timeout

	var launch_angle := _launch_angle_from_protocol_rot(player_idx, rot_rad)
	
	if player_idx == 2:
		launch_angle = PI - launch_angle
		
	var muzzle_pos := _get_shot_spawn_screen_position(tank, launch_angle)
	_spawn_muzzle_flash(muzzle_pos, launch_angle)

	var bullet := TankBullet.new()
	bullet.game = self
	bullet.origin_screen_position = muzzle_pos
	bullet.global_position = bullet.origin_screen_position
	bullet.position_units = Vector2.ZERO
	bullet.velocity_units = Vector2(cos(launch_angle), sin(launch_angle)) * launch_speed
	bullet.gravity_units = SHOT_GRAVITY_UNITS
	bullet.wind_accel_units = wind_val * SHOT_WIND_AX_PER_UNIT

	add_child(bullet)

	var target_hit: String = await bullet.impact
	
	OpLog.i(LOG_TAG, [
		"shot_impact shooter=", player_idx,
		" target=", target_hit,
		" launchAngle=", launch_angle,
		" muzzle=", muzzle_pos,
		" ", _state_summary()
	])

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
	_apply_health_from_board(core.current_board)
	_apply_tank_colors()
	OpLog.i(LOG_TAG, ["tank_damage tank=", idx, " hp=", current_hp, " ", _state_summary()])
	
	if current_hp <= 0:
		var tank_node: Tank = tank_p1 if idx == 1 else tank_p2
		var death_pos: Vector2 = tank_node.global_position if is_instance_valid(tank_node) else get_viewport().get_visible_rect().size * 0.5
		_play_death_feedback(death_pos)

func _play_death_feedback(at_pos: Vector2) -> void:
	# Bigger shake, stronger vibration, a beefier secondary explosion.
	_haptic_explosion(1.0, 180)
	_start_camera_shake(14.0)
	_spawn_impact_fx(at_pos, "tank_death")
	
func _finish_round_or_show_result() -> bool:
	if _check_win_condition():
		can_interact = false
		_update_aim_label_visibility()
		return true

	return false

func _apply_winner_payload(winner_payload: String, p1_id: String = "", p2_id: String = "") -> void:
	var parts := winner_payload.split("|", false)

	if parts.size() < 2:
		OpLog.w(LOG_TAG, ["winner_payload malformed raw=", winner_payload])
		return

	var sender_uuid := String(parts[0])
	var sender_state := String(parts[1])
	
	OpLog.i(LOG_TAG, [
		"winner_payload raw=", winner_payload,
		" sender=", sender_uuid,
		" senderState=", sender_state,
		" p1=", p1_id,
		" p2=", p2_id
	])

	if sender_state == "0":
		_show_result_from_state("0")
		return

	var local_state := sender_state
	var winning_player := 0

	if core != null and core.spectator_mode:
		var sender_player := 0

		if sender_uuid == p1_id:
			sender_player = 1
		elif sender_uuid == p2_id:
			sender_player = 2

		winning_player = sender_player

		if sender_state == "-1":
			winning_player = 2 if sender_player == 1 else 1

		local_state = "1" if winning_player == 1 else "-1"
	else:
		if sender_uuid != my_uuid:
			local_state = "-1" if sender_state == "1" else "1"

	_show_result_from_state(local_state, winning_player)
	
func _show_result_from_state(state: String, spectator_winner_player: int = 0) -> void:
	OpLog.i(LOG_TAG, [
		"show_result state=", state,
		" spectatorWinner=", spectator_winner_player,
		" ", _state_summary()
	])
	game_over = true
	win_loss_state = state
	can_interact = false
	_is_playing_round = true

	if core != null:
		core.is_my_turn = false

	stop_waiting_animation()

	if is_instance_valid(_aim_label):
		_aim_label.visible = false

	if is_instance_valid(fire_button):
		fire_button.modulate.a = 0.0

	if is_instance_valid(power_slider):
		power_slider.modulate.a = 0.0
		power_slider.editable = false

	if is_instance_valid(power_label):
		power_label.modulate.a = 0.0

	if state == "0":
		winner = "0"
	elif core != null and core.spectator_mode:
		winner = str(spectator_winner_player)
	elif state == "1":
		winner = str(core.player)
	else:
		winner = "2" if core.player == 1 else "1"

	if not is_instance_valid(win_loss_label):
		return

	if state == "0":
		win_loss_label.text = "DRAW!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 1, 1))
	elif core != null and core.spectator_mode:
		var player_num := spectator_winner_player

		if player_num == 0:
			player_num = 1 if state == "1" else 2

		win_loss_label.text = "Player %d Wins!" % player_num
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

		var winning_avatar: Control = player_avatar_display if player_num == 1 else opp_avatar_display
		if is_instance_valid(winning_avatar):
			GameUtils._show_win_burst(winning_avatar)
	elif state == "1":
		win_loss_label.text = "YOU WIN!"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.84, 0))

		if is_instance_valid(player_avatar_display):
			GameUtils._show_win_burst(player_avatar_display)
	else:
		win_loss_label.text = "YOU LOSE"
		win_loss_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

		if is_instance_valid(opp_avatar_display):
			GameUtils._show_win_burst(opp_avatar_display)

	win_loss_label.visible = true
	win_loss_label.modulate.a = 1.0
	win_loss_label.scale = Vector2.ZERO

	await get_tree().process_frame

	win_loss_label.pivot_offset = win_loss_label.size / 2.0

	var tween_in := create_tween()
	tween_in.tween_property(win_loss_label, "scale", Vector2.ONE, 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	if is_instance_valid(waiting_blur):
		waiting_blur.visible = true
		waiting_blur.modulate.a = 1.0

func _check_win_condition() -> bool:
	var hp1: int = int(core.current_board.get("tank1hp", 3))
	var hp2: int = int(core.current_board.get("tank2hp", 3))

	if hp1 > 0 and hp2 > 0:
		return false

	if hp1 <= 0 and hp2 <= 0:
		OpLog.i(LOG_TAG, ["game_end draw hp1=", hp1, " hp2=", hp2])
		_show_result_from_state("0")
	elif hp2 <= 0:
		OpLog.i(LOG_TAG, ["game_end player1_wins hp1=", hp1, " hp2=", hp2, " localPlayer=", core.player])
		_show_result_from_state("1" if core.player == 1 else "-1", 1)
	else:
		OpLog.i(LOG_TAG, ["game_end player2_wins hp1=", hp1, " hp2=", hp2, " localPlayer=", core.player])
		_show_result_from_state("1" if core.player == 2 else "-1", 2)

	return true

func _on_send_pressed() -> void:
	if _is_playing_round:
		OpLog.w(LOG_TAG, "send_pressed ignored: round already playing")
		return

	if core == null:
		OpLog.e(LOG_TAG, "send_pressed ignored: core is null")
		return

	if core.spectator_mode or not core.is_my_turn:
		OpLog.w(LOG_TAG, ["send_pressed ignored spectator=", core.spectator_mode, " turn=", core.is_my_turn])
		return

	_is_playing_round = true
	can_interact = false

	await _set_ui_visible(false)

	var my_tank: Tank = tank_p1 if core.player == 1 else tank_p2
	var my_visual_deg: float = my_tank.get_barrel_display_deg()
	var my_play_rot: float = _protocol_rot_from_visual_deg(core.player, my_visual_deg)
	var my_send_deg: float = _visual_deg_to_data_deg(my_visual_deg)
	var my_send_rot: float = _protocol_rot_from_visual_deg(core.player, my_send_deg)
	var my_pwr: float = power_slider.value / 100.0
	var wind_val: float = float(core.current_board.get("wind", 0.0))
	
	OpLog.i(LOG_TAG, [
		"send_pressed player=", core.player,
		" visualDeg=", my_visual_deg,
		" playRot=", my_play_rot,
		" sendDeg=", my_send_deg,
		" sendRot=", my_send_rot,
		" power=", my_pwr,
		" wind=", wind_val,
		" preBoard={", _board_summary(core.current_board), "}"
	])

	var pre_shot_board: Dictionary = core.current_board.duplicate(true)
	pre_shot_board["tank%drot" % core.player] = my_send_rot
	pre_shot_board["tank%dpower" % core.player] = my_pwr

	await _execute_shot(core.player, my_play_rot, my_pwr, wind_val)

	var post_shot_board: Dictionary = core.current_board.duplicate(true)
	post_shot_board["tank%drot" % core.player] = my_send_rot
	post_shot_board["tank%dpower" % core.player] = my_pwr

	core.set_my_aim(my_send_rot, my_pwr)

	var avatar_str := ""

	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		avatar_str = player_avatar_display.get_avatar_data_string()

	var replay_string := "board:" + core._compose_board_kv(pre_shot_board)
	replay_string += "|shoot:" + str(core.player)
	replay_string += "|board:" + core._compose_board_kv(post_shot_board)

	var payload := {
		"replay": replay_string
	}

	var avatar_key := "avatar1" if core.player == 1 else "avatar2"

	if avatar_str != "":
		payload[avatar_key] = avatar_str
	
	OpLog.event(LOG_TAG, [
		"replay_built ", _replay_summary(replay_string),
		" pre={", _board_summary(pre_shot_board), "}",
		" post={", _board_summary(post_shot_board), "}",
		" raw=", replay_string
	])

	var finished := _finish_round_or_show_result()
	
	OpLog.i(LOG_TAG, ["send_pressed shot_finished finished=", finished, " ", _state_summary()])

	_send_payload(payload)

	if finished:
		return

	core.is_my_turn = false
	can_interact = false
	_is_playing_round = false
	_update_aim_label_visibility()

	play_sent_animation()
