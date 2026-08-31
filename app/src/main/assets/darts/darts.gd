extends BaseGame3D
class_name DartsGame

const MUSIC_STREAM := preload("res://global/audio/darts.ogg")

@onready var opp_avatar_display: TextureButton = %OppAvatarDisplay
@onready var player_avatar_display: TextureButton = %PlayerAvatarDisplay
@onready var winner_label: Label = %WinLossLabel
@onready var sent_label: Label = %SentLabel
@onready var you_score_label: Label = %PlayerScoreLabel
@onready var opp_score_label: Label = %OpponentScoreLabel
@onready var main_overlay: Control = %MainOverlay
@onready var spectator_label: Label = %SpecLabel
@onready var you_label: Label = %YouLabel
@onready var darts_menu_button: Button = %MenuButton

const DARTS_LANDSCAPE_UI_SCALE: float = 1.5
const DARTS_LANDSCAPE_LABEL_SCALE: float = 1.8
const DARTS_LANDSCAPE_BUTTON_SCALE: float = 1.8
@export var camera_fit_margin: float = 1.5
const DART_BOARD_PLANE_Z := 0.067
const DART_FIT_PAD := 0.14

var _base_theme_values: Dictionary = {}
var _darts_portrait_fov: float = -1.0
var points_to_win_popup: Control
var points_to_win_panel: PanelContainer
var points_to_win_label: RichTextLabel
var points_to_win_arrow: Polygon2D
var points_to_win_fade_tween: Tween

const POINTS_TO_WIN_FADE_TIME := 0.22

var main_dart: Dart

const DART_IDLE_POSITION := Vector3(0.0, -0.095, 1.803)
const DART_IDLE_BOUNCE_Z := 0.035
const DART_IDLE_BOUNCE_TIME := 0.65
const DARTS_MODAL_Z_INDEX := 4096
const DARTS_MODAL_CANVAS_LAYER := 1000

const DART_ICON_TEX := preload("res://darts/dart2d.png")
const DART_INDICATOR_POS := Vector2(10, 8)
const DART_INDICATOR_SIZE := Vector2(60, 120)
const DART_INDICATOR_SPACING := 35.0
const DART_INDICATOR_MAX := 3

const SCORE_POPUP_DIR := "res://darts/score/"
const SCORE_POPUP_SIZE := Vector2(82, 50)
const SCORE_POPUP_OFFSET := Vector2(0, -42)
const SCORE_POPUP_RISE := 58.0
const SCORE_POPUP_FINAL_SCALE := Vector2(0.75, 0.75)
const SCORE_POPUP_GROW_TIME := 0.35
const SCORE_POPUP_TIME := 1.35
const SCORE_POPUP_FADE_DELAY := 0.45
const SCORE_REPLAY_POPUP_WAIT := 1.15
const SCORE_BUST_DELAY := 0.25
const DART_REPLAY_HIT_WAIT := 0.52

const DART_BOARD_CENTER := Vector2(0.0, 0.344)
const DART_BOARD_RADIUS := 0.535
const DART_SEGMENTS := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

const DARTS_MENU_SIZE := Vector2(142.0, 104.0)
const DARTS_MENU_ROW_HEIGHT := 48.0
const DARTS_MENU_FONT_SIZE: int = 21
const DARTS_MENU_BUTTON_GAP := 6.0
const DARTS_MENU_SCREEN_MARGIN := 8.0

const DARTS_LANDSCAPE_MENU_SCALE: float = 1.5

var darts_menu_layer: Control
var darts_menu_panel: PanelContainer
var darts_menu_open: bool = false

const DART_WHITE_SEGMENTS := {
	20: true,
	18: true,
	13: true,
	10: true,
	2: true,
	3: true,
	7: true,
	8: true,
	14: true,
	12: true
}

var darts: Array[Dart] = []
var current_dart: Dart
var num_shots: int = 0
var replay_played: bool = false
var is_replaying: bool = false
var last_replay_played: String = ""
var sent_tween: Tween
var is_my_turn: bool = false
var player: int = -1
var mode: int = -1
var replay: String = ""

var my_moves: Array[Array]

var p1_pre_score: int = 0
var p2_pre_score: int = 0
var p1_score: int = 0
var p2_score: int = 0
var redemption_active: bool = false
var redemption_darts_allowed: int = 0
var game_over: bool = false
var dart_idle_tween: Tween
var dart_indicator_root: Control
var dart_indicator_slots: Array[Control] = []
var score_popup_textures: Dictionary = {}
var drag_start_pos: Vector2 = Vector2.ZERO
var dragging: bool = false
var player_score_tween: Tween
var opponent_score_tween: Tween

const SCORE_TICK_MIN_DURATION := 0.30
const SCORE_TICK_MAX_DURATION := 1.05
const SCORE_TICK_LOG_SCALE := 0.16

const POINTS_TO_WIN_COLOR := Color(1.0, 0.84, 0.0)

const POINTS_TO_WIN_SIZE := Vector2(142.0, 42.0)
const POINTS_TO_WIN_PANEL_HEIGHT := 38.0
const POINTS_TO_WIN_ARROW_HEIGHT := 10.0
const POINTS_TO_WIN_ARROW_HALF_WIDTH := 10.0
const POINTS_TO_WIN_FONT_SIZE: int = 24
const POINTS_TO_WIN_CORNER_RADIUS: int = 17
const POINTS_TO_WIN_AVATAR_GAP := 6.0

const POINTS_TO_WIN_LANDSCAPE_SIZE := Vector2(190.0, 58.0)
const POINTS_TO_WIN_LANDSCAPE_PANEL_HEIGHT := 50.0
const POINTS_TO_WIN_LANDSCAPE_ARROW_HEIGHT := 14.0
const POINTS_TO_WIN_LANDSCAPE_ARROW_HALF_WIDTH := 14.0
const POINTS_TO_WIN_LANDSCAPE_FONT_SIZE: int = 32
const POINTS_TO_WIN_LANDSCAPE_CORNER_RADIUS: int = 23
const POINTS_TO_WIN_LANDSCAPE_AVATAR_GAP := 8.0

const RESULT_NONE := 0
const RESULT_WIN := 1
const RESULT_LOSS := -1
const RESULT_DRAW := 2

var match_result: int = RESULT_NONE

func _get_music_stream() -> AudioStream:
	return MUSIC_STREAM

const LOG_TAG := "Darts"
var DEBUG_DARTS := false

func dbg(msg: String) -> void:
	if DEBUG_DARTS:
		OpLog.d(LOG_TAG, msg)

func _get_dev_data() -> String:
	return '{ "isYourTurn": true, "player": "1", "replay": "state:101,10|move:0,0.103483,0.142005,2,2,0|move:0,-0.343160,0.606544,9,9,0|move:0,0.128320,0.867287,0,0,0|state:90,10", "sender": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "style1": "0", "style2": "0", "avatar1": "body,4|eyes,2|mouth,1|acc,0|wins,0|bg_color,0.682208,0.913005,0.498769|body_color,0.764706,0.254902,0.152941|glasses,0|stache,0|backdrop,0|hair,4|clothes,2|hair_color,0.345098,0.180392,0.125490|clothes_color,0.918355,0.098772,0.427231", "avatar2": "body,0|eyes,2|mouth,6|acc,0|wins,0|bg_color,0.758100,0.554724,0.647306|body_color,0.114548,0.061022,0.017790|glasses,0|stache,0|backdrop,0|hair,6|clothes,0|hair_color,0.325444,0.509636,0.885538|clothes_color,0.987590,0.452528,0.395021", "player1": "7ED3F73A-C6BE-45C5-A64B-EC28215C3180XvmbKU", "player2": "", "id": "dev", "ios": "16.3.1", "num": "2", "game": "darts", "mode": "101", "tver": "5", "build": "56", "version": "0" }'
	
func _get_settings_avatar_display() -> Control:
	return player_avatar_display
	
func _get_rules_title() -> String:
	return "Darts"

func _get_rules_text() -> String:
	return (
		"[font_size=24][b]Goal[/b][/font_size]\n" +
		"\n" +
		"Be the first player to reduce your score to exactly 0.\n" +
		"\n" +
		"[font_size=24][b]How to Play[/b][/font_size]\n" +
		"\n" +
		"• Players take turns throwing up to 3 darts.\n" +
		"• Drag and release to throw a dart at the board.\n" +
		"• The score from each dart is subtracted from your remaining score.\n" +
		"• You must finish on exactly 0. A double is not required to win.\n" +
		"\n" +
		"[font_size=24][b]Board Scoring[/b][/font_size]\n" +
		"\n" +
		"• The large black and white sections score the number shown beside them.\n" +
		"• The thin inner red and green ring scores triple the section number.\n" +
		"• The thin outer red and green ring scores double the section number.\n" +
		"• The outer green bullseye scores 25 points.\n" +
		"• The center red bullseye scores 50 points.\n" +
		"• A dart outside the scoring area scores 0 points.\n" +
		"\n" +
		"[font_size=24][b]Busts[/b][/font_size]\n" +
		"\n" +
		"If your score falls below 0, your turn is a bust. Any points scored " +
		"during that turn are canceled, and your score returns to what it " +
		"was at the beginning of the turn.\n" +
		"\n" +
		"[font_size=24][b]Last Chance[/b][/font_size]\n" +
		"\n" +
		"If the player who went first reaches 0 first, the other player gets " +
		"one final turn of up to 3 darts.\n" +
		"\n" +
		"• If the second player also reaches exactly 0, the game ends in a draw.\n" +
		"• If the second player does not reach 0, the first player wins."
	)

func _add_settings_rows(_container, popup_script) -> void:
	var items: Array[Dictionary] = []

	for style: int in Dart.available_dart_styles():
		items.append({
			"id": str(style),
			"label": "Dart %d" % style,
			"texture_path": Dart.dart_style_path(style)
		})

	if items.is_empty():
		return

	var dart_row: Control = popup_script.make_game_picker_card(
		"Dart",
		"Flight design",
		items,
		str(Dart.active_dart_style),
		func(id: String) -> void:
			Dart.set_dart_style(int(id))
			SettingsManager.set_setting("darts", "dart_style", Dart.active_dart_style)
			OpLog.i(LOG_TAG, ["dart_style_selected style=", Dart.active_dart_style])
	)

	popup_script.add_custom_setting(dart_row)

func _ensure_main_dart() -> bool:
	if is_instance_valid(main_dart):
		return true

	Dart.set_dart_style(int(SettingsManager.get_setting("darts", "dart_style", 1)))
	main_dart = get_node_or_null("dart") as Dart

	if not is_instance_valid(main_dart):
		OpLog.e(LOG_TAG, "main_dart_missing")
		return false

	return true

func _start_dart_idle(dart: Dart) -> void:
	if dart_idle_tween and dart_idle_tween.is_running():
		dart_idle_tween.kill()

	if not is_instance_valid(dart):
		return

	dart.position = DART_IDLE_POSITION
	dart_idle_tween = create_tween().set_loops()
	dart_idle_tween.tween_property(dart, "position:z", DART_IDLE_POSITION.z - DART_IDLE_BOUNCE_Z, DART_IDLE_BOUNCE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	dart_idle_tween.tween_property(dart, "position:z", DART_IDLE_POSITION.z + DART_IDLE_BOUNCE_Z * 0.35, DART_IDLE_BOUNCE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_dart_idle() -> void:
	if dart_idle_tween and dart_idle_tween.is_running():
		dart_idle_tween.kill()

	dart_idle_tween = null
	
func _setup_dart_indicator() -> void:
	if is_instance_valid(dart_indicator_root):
		return

	if not is_instance_valid(main_overlay):
		OpLog.w(LOG_TAG, "dart_indicator_missing_main_overlay")
		return

	dart_indicator_root = Control.new()
	dart_indicator_root.position = DART_INDICATOR_POS
	dart_indicator_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dart_indicator_root.z_index = 1000
	main_overlay.add_child(dart_indicator_root)

	for i in range(DART_INDICATOR_MAX):
		var slot := Control.new()
		slot.position = Vector2(i * DART_INDICATOR_SPACING, 0.0)
		slot.size = DART_INDICATOR_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dart_indicator_root.add_child(slot)

		var icon := TextureRect.new()
		icon.texture = DART_ICON_TEX
		icon.size = DART_ICON_TEX.get_size()
		icon.custom_minimum_size = Vector2.ZERO
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var tex_size: Vector2 = DART_ICON_TEX.get_size()
		var scale_factor: float = minf(
			DART_INDICATOR_SIZE.x / tex_size.x,
			DART_INDICATOR_SIZE.y / tex_size.y
		)

		icon.scale = Vector2(scale_factor, scale_factor)
		icon.position = (DART_INDICATOR_SIZE - tex_size * scale_factor) * 0.5

		slot.add_child(icon)

		dart_indicator_slots.append(slot)

	_update_dart_indicator()

func _get_darts_left_count() -> int:
	var used := num_shots

	if is_instance_valid(current_dart) and current_dart.is_mine:
		used -= 1

	var limit := _get_turn_dart_limit()
	return clamp(limit - used, 0, limit)

func _update_dart_indicator() -> void:
	if not is_instance_valid(dart_indicator_root):
		return

	var limit := _get_turn_dart_limit()
	var left := _get_darts_left_count()

	dart_indicator_root.visible = is_my_turn and not spectator_mode and not game_over

	for i in range(dart_indicator_slots.size()):
		var slot := dart_indicator_slots[i]
		slot.visible = i < limit
		slot.modulate.a = 1.0 if i < left else 0.25
	
	_update_points_to_win()

func _score_popup_texture(path: String) -> Texture2D:
	if score_popup_textures.has(path):
		return score_popup_textures[path]

	if not ResourceLoader.exists(path):
		OpLog.w(LOG_TAG, ["score_popup_missing path=", path])
		return null

	var tex := load(path) as Texture2D
	score_popup_textures[path] = tex
	return tex

func _hit_segment_from_world(world_pos: Vector3) -> int:
	var p := Vector2(world_pos.x, world_pos.y) - DART_BOARD_CENTER

	if p.length() <= 0.001:
		return 0

	var angle := rad_to_deg(atan2(p.x, p.y))
	if angle < 0.0:
		angle += 360.0

	var idx := int(floor((angle + 9.0) / 18.0)) % DART_SEGMENTS.size()
	return DART_SEGMENTS[idx]

func _hit_multiplier_from_world(world_pos: Vector3, score: Array) -> int:
	if score.is_empty():
		return 0

	var total := int(score[0])
	if total <= 0:
		return 0

	if total == 25 or total == 50:
		return 1

	var p := Vector2(world_pos.x, world_pos.y) - DART_BOARD_CENTER
	var r := p.length() / DART_BOARD_RADIUS

	if r >= 0.582 and r <= 0.629:
		return 3

	if r >= 0.953 and r <= 1.03:
		return 2

	return 1

func _score_color_code(score: Array, world_pos: Vector3) -> String:
	if score.is_empty():
		return "b"

	var total := int(score[0])

	if total <= 0:
		return "b"

	if total == 50:
		return "r"

	if total == 25:
		return "g"

	var segment := _hit_segment_from_world(world_pos)
	var multiplier := _hit_multiplier_from_world(world_pos, score)
	var base_is_white := DART_WHITE_SEGMENTS.has(segment)

	if multiplier >= 2:
		return "g" if base_is_white else "r"

	return "w" if base_is_white else "b"

func _configure_darts_avatar(avatar_button: TextureButton) -> void:
	if not is_instance_valid(avatar_button):
		return

	var k: float = _darts_ui_scale()

	avatar_button.clip_contents = false
	avatar_button.scale = Vector2.ONE
	avatar_button.custom_minimum_size = Vector2(96.0, 90.0) * k

	var internal_viewport := avatar_button.get_node_or_null("SubViewportContainer/SubViewport") as SubViewport

	if internal_viewport != null:
		internal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var internal_preview := avatar_button.get_node_or_null("SubViewportContainer") as SubViewportContainer

	if internal_preview != null:
		internal_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		internal_preview.visible = true
		internal_preview.self_modulate = Color.WHITE
		internal_preview.pivot_offset = Vector2(48.0, 140.0)
		internal_preview.scale = Vector2(k, k)

func _initialize_darts_avatars() -> void:
	if not is_instance_valid(player_avatar_display):
		player_avatar_display = get_node_or_null("%PlayerAvatarDisplay") as TextureButton

	if not is_instance_valid(opp_avatar_display):
		opp_avatar_display = get_node_or_null("%OppAvatarDisplay") as TextureButton

	_configure_darts_avatar(player_avatar_display)
	_configure_darts_avatar(opp_avatar_display)

	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("update_display_from_settings"):
		player_avatar_display.call_deferred("update_display_from_settings")

func _score_popup_path(score: Array, world_pos: Vector3, bust: bool = false) -> String:
	if bust:
		return SCORE_POPUP_DIR + "darts_bust.png"

	if score.is_empty() or int(score[0]) <= 0:
		return SCORE_POPUP_DIR + "darts_miss.png"

	var total := int(score[0])
	var color_code := _score_color_code(score, world_pos)
	var path := SCORE_POPUP_DIR + "darts_score_%s_%04d.png" % [color_code, total]

	if ResourceLoader.exists(path):
		return path

	for fallback_code in ["w", "b", "g", "r"]:
		var fallback_path := SCORE_POPUP_DIR + "darts_score_%s_%04d.png" % [fallback_code, total]
		if ResourceLoader.exists(fallback_path):
			OpLog.w(LOG_TAG, [
				"score_popup_color_fallback wanted=", path,
				" using=", fallback_path,
				" score=", score,
				" world_pos=", world_pos
			])
			return fallback_path

	return path

func _screen_pos_from_world(world_pos: Vector3) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return main_overlay.size * 0.5 if is_instance_valid(main_overlay) else Vector2.ZERO

	return cam.unproject_position(world_pos)

func _show_score_popup(world_pos: Vector3, score: Array = [], bust: bool = false, center_screen: bool = false) -> void:
	if not is_instance_valid(main_overlay):
		OpLog.w(LOG_TAG, "score_popup_missing_overlay")
		return

	var path := _score_popup_path(score, world_pos, bust)
	var tex := _score_popup_texture(path)

	if tex == null:
		return
		
	OpLog.event(LOG_TAG, [
		"score_popup_show path=", path,
		" score=", score,
		" bust=", bust,
		" world_pos=", world_pos
	])

	var popup_size := SCORE_POPUP_SIZE
	if center_screen:
		popup_size = tex.get_size()

	var popup := TextureRect.new()
	popup.texture = tex
	popup.size = popup_size
	popup.pivot_offset = popup_size * 0.5
	popup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.z_index = 2000
	popup.scale = Vector2.ZERO
	popup.modulate.a = 1.0

	main_overlay.add_child(popup)

	var overlay_pos: Vector2

	if center_screen:
		overlay_pos = main_overlay.size * 0.5
	else:
		var screen_pos: Vector2 = _screen_pos_from_world(world_pos)
		overlay_pos = screen_pos - main_overlay.global_position

	var popup_offset := Vector2.ZERO if center_screen else SCORE_POPUP_OFFSET

	popup.position = Vector2(
		overlay_pos.x + popup_offset.x - popup.pivot_offset.x,
		overlay_pos.y + popup_offset.y - popup.pivot_offset.y
	)

	var start_pos: Vector2 = popup.position
	var end_pos: Vector2 = Vector2(start_pos.x, start_pos.y - SCORE_POPUP_RISE)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(popup, "scale", SCORE_POPUP_FINAL_SCALE, SCORE_POPUP_GROW_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(popup, "position", end_pos, SCORE_POPUP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(popup, "modulate:a", 0.0, SCORE_POPUP_TIME).set_delay(SCORE_POPUP_FADE_DELAY)

	tw.finished.connect(func():
		if is_instance_valid(popup):
			popup.queue_free()
	)

func _has_available_shot() -> bool:
	return (
		is_my_turn and
		not spectator_mode and
		not game_over and
		not is_replaying and
		num_shots < _get_turn_dart_limit()
	)


func _winning_target_for_score(score: int) -> Dictionary:
	if score <= 0:
		return {}

	if score >= 1 and score <= 20:
		return {
			"score": score,
			"multiplier": 1
		}

	if score == 25:
		return {
			"score": 25,
			"multiplier": 1
		}

	if score == 50:
		return {
			"score": 50,
			"multiplier": 2
		}

	if score % 2 == 0:
		var double_base := score / 2

		if double_base >= 1 and double_base <= 20:
			return {
				"score": double_base,
				"multiplier": 2
			}

	if score % 3 == 0:
		var triple_base := score / 3

		if triple_base >= 1 and triple_base <= 20:
			return {
				"score": triple_base,
				"multiplier": 3
			}

	return {}

func _update_points_to_win() -> void:
	if not is_instance_valid(points_to_win_popup):
		return

	var dartboard := get_node_or_null("dart_board") as Dartboard

	if (
		not is_my_turn or
		spectator_mode or
		game_over or
		is_replaying
	):
		_hide_points_to_win_popup()

		if is_instance_valid(dartboard):
			dartboard.clear_win_target()

		return

	if not _has_available_shot():
		_hide_points_to_win_popup()

		if is_instance_valid(dartboard):
			dartboard.clear_win_target()

		return

	var local_score := get_score(player)
	var target := _winning_target_for_score(local_score)

	if target.is_empty():
		_hide_points_to_win_popup()

		if is_instance_valid(dartboard):
			dartboard.clear_win_target()

		return

	points_to_win_label.text = "[b]%d[/b] to Win" % local_score
	_show_points_to_win_popup()

	if is_instance_valid(dartboard):
		dartboard.show_win_target(
			int(target["score"]),
			int(target["multiplier"])
		)

func _apply_points_to_win_layout() -> void:
	if (
		not is_instance_valid(points_to_win_popup) or
		not is_instance_valid(points_to_win_panel) or
		not is_instance_valid(points_to_win_label) or
		not is_instance_valid(points_to_win_arrow)
	):
		return

	var viewport_size: Vector2 = (
		get_viewport()
		.get_visible_rect()
		.size
	)

	var is_landscape: bool = (
		viewport_size.x > viewport_size.y
	)

	var popup_size: Vector2 = (
		POINTS_TO_WIN_LANDSCAPE_SIZE
		if is_landscape
		else POINTS_TO_WIN_SIZE
	)

	var panel_height: float = (
		POINTS_TO_WIN_LANDSCAPE_PANEL_HEIGHT
		if is_landscape
		else POINTS_TO_WIN_PANEL_HEIGHT
	)

	var arrow_height: float = (
		POINTS_TO_WIN_LANDSCAPE_ARROW_HEIGHT
		if is_landscape
		else POINTS_TO_WIN_ARROW_HEIGHT
	)

	var arrow_half_width: float = (
		POINTS_TO_WIN_LANDSCAPE_ARROW_HALF_WIDTH
		if is_landscape
		else POINTS_TO_WIN_ARROW_HALF_WIDTH
	)

	var font_size: int = (
		POINTS_TO_WIN_LANDSCAPE_FONT_SIZE
		if is_landscape
		else POINTS_TO_WIN_FONT_SIZE
	)

	var corner_radius: int = (
		POINTS_TO_WIN_LANDSCAPE_CORNER_RADIUS
		if is_landscape
		else POINTS_TO_WIN_CORNER_RADIUS
	)

	points_to_win_popup.custom_minimum_size = popup_size
	points_to_win_popup.size = popup_size

	points_to_win_panel.position = Vector2.ZERO
	points_to_win_panel.custom_minimum_size = Vector2(
		popup_size.x,
		panel_height
	)
	points_to_win_panel.size = Vector2(
		popup_size.x,
		panel_height
	)

	points_to_win_label.add_theme_font_size_override(
		"normal_font_size",
		font_size
	)

	points_to_win_label.add_theme_font_size_override(
		"bold_font_size",
		font_size
	)

	var panel_style := (
		points_to_win_panel.get_theme_stylebox(
			"panel"
		) as StyleBoxFlat
	)

	if panel_style != null:
		panel_style.corner_radius_top_left = corner_radius
		panel_style.corner_radius_top_right = corner_radius
		panel_style.corner_radius_bottom_left = corner_radius
		panel_style.corner_radius_bottom_right = corner_radius

	points_to_win_arrow.polygon = PackedVector2Array([
		Vector2(-arrow_half_width, 0.0),
		Vector2(arrow_half_width, 0.0),
		Vector2(0.0, arrow_height)
	])

	points_to_win_arrow.position = Vector2(
		popup_size.x * 0.5,
		panel_height - 1.0
	)

func _setup_points_to_win_popup() -> void:
	if is_instance_valid(points_to_win_popup):
		return

	if not is_instance_valid(main_overlay):
		OpLog.w(LOG_TAG, "points_to_win_missing_main_overlay")
		return

	points_to_win_popup = Control.new()
	points_to_win_popup.name = "PointsToWinPopup"
	points_to_win_popup.size = POINTS_TO_WIN_SIZE
	points_to_win_popup.custom_minimum_size = POINTS_TO_WIN_SIZE
	points_to_win_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	points_to_win_popup.visible = false
	points_to_win_popup.modulate.a = 0.0
	points_to_win_popup.z_index = 100

	main_overlay.add_child(points_to_win_popup)

	points_to_win_panel = PanelContainer.new()
	points_to_win_panel.name = "PointsToWinPanel"
	points_to_win_panel.position = Vector2.ZERO
	points_to_win_panel.size = Vector2(
		POINTS_TO_WIN_SIZE.x,
		POINTS_TO_WIN_PANEL_HEIGHT
	)
	points_to_win_panel.custom_minimum_size = points_to_win_panel.size
	points_to_win_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = POINTS_TO_WIN_COLOR
	style.corner_radius_top_left = POINTS_TO_WIN_CORNER_RADIUS
	style.corner_radius_top_right = POINTS_TO_WIN_CORNER_RADIUS
	style.corner_radius_bottom_left = POINTS_TO_WIN_CORNER_RADIUS
	style.corner_radius_bottom_right = POINTS_TO_WIN_CORNER_RADIUS
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0

	points_to_win_panel.add_theme_stylebox_override(
		"panel",
		style
	)

	points_to_win_popup.add_child(points_to_win_panel)

	points_to_win_label = RichTextLabel.new()
	points_to_win_label.name = "PointsToWinLabel"
	points_to_win_label.bbcode_enabled = true
	points_to_win_label.fit_content = true
	points_to_win_label.scroll_active = false
	points_to_win_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	points_to_win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points_to_win_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	points_to_win_label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	points_to_win_label.add_theme_font_size_override(
		"normal_font_size",
		POINTS_TO_WIN_FONT_SIZE
	)

	points_to_win_label.add_theme_font_size_override(
		"bold_font_size",
		POINTS_TO_WIN_FONT_SIZE
	)

	points_to_win_label.add_theme_color_override(
		"default_color",
		Color.BLACK
	)

	points_to_win_panel.add_child(points_to_win_label)

	points_to_win_arrow = Polygon2D.new()
	points_to_win_arrow.name = "PointsToWinArrow"
	points_to_win_arrow.polygon = PackedVector2Array([
		Vector2(
			-POINTS_TO_WIN_ARROW_HALF_WIDTH,
			0.0
		),
		Vector2(
			POINTS_TO_WIN_ARROW_HALF_WIDTH,
			0.0
		),
		Vector2(
			0.0,
			POINTS_TO_WIN_ARROW_HEIGHT
		)
	])
	points_to_win_arrow.color = POINTS_TO_WIN_COLOR
	points_to_win_arrow.position = Vector2(
		POINTS_TO_WIN_SIZE.x * 0.5,
		POINTS_TO_WIN_PANEL_HEIGHT - 1.0
	)

	points_to_win_popup.add_child(points_to_win_arrow)
	_apply_points_to_win_layout()
	
func _find_score_texture(
	root: Node
) -> TextureRect:
	if root is TextureRect:
		return root as TextureRect

	for child in root.get_children():
		var found := _find_score_texture(child)

		if is_instance_valid(found):
			return found

	return null

func _position_points_to_win_popup() -> void:
	if (
		not is_instance_valid(points_to_win_popup) or
		not is_instance_valid(player_avatar_display) or
		not is_instance_valid(main_overlay)
	):
		return

	var avatar_control := (
		player_avatar_display as Control
	)

	if avatar_control == null:
		OpLog.w(
			LOG_TAG,
			"points_to_win_avatar_is_not_control"
		)
		return

	var viewport_size: Vector2 = (
		get_viewport()
		.get_visible_rect()
		.size
	)

	var is_landscape: bool = (
		viewport_size.x > viewport_size.y
	)

	var avatar_gap: float = (
		POINTS_TO_WIN_LANDSCAPE_AVATAR_GAP
		if is_landscape
		else POINTS_TO_WIN_AVATAR_GAP
	)

	var popup_size: Vector2 = (
		points_to_win_popup.size
	)

	var avatar_rect: Rect2 = (
		avatar_control.get_global_rect()
	)

	var avatar_top_in_overlay: float = (
		avatar_rect.position.y -
		main_overlay.global_position.y
	)

	var avatar_center_x_in_overlay: float = (
		avatar_rect.position.x -
		main_overlay.global_position.x +
		avatar_rect.size.x * 0.5
	)

	points_to_win_popup.position = Vector2(
		avatar_center_x_in_overlay -
			popup_size.x * 0.5,
		avatar_top_in_overlay -
			popup_size.y -
			avatar_gap
	)

func _show_points_to_win_popup() -> void:
	if not is_instance_valid(points_to_win_popup):
		return

	if points_to_win_fade_tween and points_to_win_fade_tween.is_valid():
		points_to_win_fade_tween.kill()

	points_to_win_popup.visible = true
	_position_points_to_win_popup()

	points_to_win_fade_tween = create_tween()
	points_to_win_fade_tween.tween_property(
		points_to_win_popup,
		"modulate:a",
		1.0,
		POINTS_TO_WIN_FADE_TIME
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _hide_points_to_win_popup() -> void:
	if not is_instance_valid(points_to_win_popup):
		return

	if not points_to_win_popup.visible:
		points_to_win_popup.modulate.a = 0.0
		return

	if points_to_win_fade_tween and points_to_win_fade_tween.is_valid():
		points_to_win_fade_tween.kill()

	points_to_win_fade_tween = create_tween()
	points_to_win_fade_tween.tween_property(
		points_to_win_popup,
		"modulate:a",
		0.0,
		POINTS_TO_WIN_FADE_TIME
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	points_to_win_fade_tween.finished.connect(
		func() -> void:
			if is_instance_valid(points_to_win_popup):
				points_to_win_popup.visible = false
	)

func _darts_ui_scale() -> float:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	return DARTS_LANDSCAPE_UI_SCALE if vp.x > vp.y else 1.0

func _scale_theme(node: Control, theme_item: String, k: float) -> void:
	if not is_instance_valid(node):
		return

	var key: String = str(node.get_instance_id()) + theme_item

	if not _base_theme_values.has(key):
		_base_theme_values[key] = node.get_theme_font_size(theme_item)

	node.add_theme_font_size_override(
		theme_item,
		int(round(float(_base_theme_values[key]) * k))
	)

func _scale_min_size(node: Control, k: float) -> void:
	if not is_instance_valid(node):
		return

	var id: String = str(node.get_instance_id()) + "minsize"

	if not _base_theme_values.has(id):
		_base_theme_values[id] = node.custom_minimum_size

	node.custom_minimum_size = _base_theme_values[id] * k

func _darts_fit_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	var cx: float = DART_BOARD_CENTER.x
	var cy: float = DART_BOARD_CENTER.y
	var r: float = DART_BOARD_RADIUS

	pts.append(Vector3(cx - r, cy, DART_BOARD_PLANE_Z))
	pts.append(Vector3(cx + r, cy, DART_BOARD_PLANE_Z))
	pts.append(Vector3(cx, cy - r, DART_BOARD_PLANE_Z))
	pts.append(Vector3(cx, cy + r, DART_BOARD_PLANE_Z))

	var dart_pos: Vector3 = DART_IDLE_POSITION

	if is_instance_valid(current_dart):
		dart_pos = current_dart.position

	for dx: float in [-DART_FIT_PAD, DART_FIT_PAD]:
		for dy: float in [-DART_FIT_PAD, DART_FIT_PAD]:
			pts.append(dart_pos + Vector3(dx, dy, 0.0))

	return pts

func _configure_darts_camera() -> void:
	var cam := get_viewport().get_camera_3d()

	if cam == null:
		return

	var vp: Vector2 = (
		get_viewport()
		.get_visible_rect()
		.size
	)

	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	if _darts_portrait_fov < 0.0:
		_darts_portrait_fov = cam.fov

	var is_landscape: bool = vp.x > vp.y

	if not is_landscape:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = _darts_portrait_fov

		OpLog.i(LOG_TAG, [
			"darts_camera portrait viewport=",
			vp,
			" keepAspect=KEEP_WIDTH",
			" restoredFov=",
			cam.fov
		])

		return

	cam.keep_aspect = Camera3D.KEEP_HEIGHT

	var aspect: float = (
		vp.x /
		maxf(vp.y, 1.0)
	)

	var inverse_camera: Transform3D = (
		cam.global_transform.affine_inverse()
	)

	var vertical_tangent: float = 0.0
	var horizontal_tangent: float = 0.0

	for world_point: Vector3 in _darts_fit_points():
		var camera_point: Vector3 = (
			inverse_camera * world_point
		)

		var depth: float = -camera_point.z

		if depth <= 0.01:
			continue

		vertical_tangent = maxf(
			vertical_tangent,
			absf(camera_point.y) / depth
		)

		horizontal_tangent = maxf(
			horizontal_tangent,
			absf(camera_point.x) / depth
		)

	if (
		vertical_tangent <= 0.0 and
		horizontal_tangent <= 0.0
	):
		cam.fov = _darts_portrait_fov
		return

	var needed_tangent: float = maxf(
		vertical_tangent,
		horizontal_tangent / aspect
	) * camera_fit_margin

	var fitted_fov: float = clampf(
		rad_to_deg(
			atan(needed_tangent) * 2.0
		),
		1.0,
		120.0
	)

	cam.fov = maxf(
		_darts_portrait_fov,
		fitted_fov
	)

	OpLog.i(LOG_TAG, [
		"darts_camera landscape viewport=",
		vp,
		" aspect=",
		aspect,
		" verticalTangent=",
		vertical_tangent,
		" horizontalTangent=",
		horizontal_tangent,
		" baseFov=",
		_darts_portrait_fov,
		" fittedFov=",
		fitted_fov,
		" appliedFov=",
		cam.fov
	])

func _apply_landscape_ui() -> void:
	await get_tree().process_frame

	_configure_darts_camera()

	var k: float = _darts_ui_scale()

	_configure_darts_avatar(player_avatar_display)
	_configure_darts_avatar(opp_avatar_display)
	
	_apply_points_to_win_layout()

	if (
		is_instance_valid(points_to_win_popup) and
		points_to_win_popup.visible
	):
		_position_points_to_win_popup()

	var label_k: float = DARTS_LANDSCAPE_LABEL_SCALE if k > 1.0 else 1.0

	for overlay: Control in [
		winner_label,
		sent_label,
		waiting_label,
		spectator_label,
		you_label,
	]:
		_scale_theme(overlay, "font_size", label_k)

	for score: Control in [you_score_label, opp_score_label]:
		_scale_theme(score, "font_size", k)
		_scale_min_size(score, k)

	var button_k: float = DARTS_LANDSCAPE_BUTTON_SCALE if k > 1.0 else 1.0

	_scale_min_size(darts_menu_button, button_k)

	if darts_menu_button is Button:
		darts_menu_button.expand_icon = true

	if is_instance_valid(dart_indicator_root):
		dart_indicator_root.pivot_offset = Vector2.ZERO
		dart_indicator_root.scale = Vector2(k, k)
		dart_indicator_root.position = DART_INDICATOR_POS * k

	if is_instance_valid(darts_menu_panel):
		_apply_darts_menu_layout()
		_position_darts_menu()

func _on_viewport_size_changed() -> void:
	await _apply_landscape_ui()
	await get_tree().process_frame

	if (
		is_instance_valid(points_to_win_popup) and
		points_to_win_popup.visible
	):
		_position_points_to_win_popup()

	if is_instance_valid(darts_menu_panel):
		_position_darts_menu()

	OpLog.i(LOG_TAG, [
		"darts_orientation_applied viewport=",
		get_viewport().get_visible_rect().size,
		" portraitFov=",
		_darts_portrait_fov,
		" currentFov=",
		get_viewport().get_camera_3d().fov
		if get_viewport().get_camera_3d() != null
		else -1.0
	])

func _darts_menu_scale() -> float:
	var viewport_size: Vector2 = (
		get_viewport()
		.get_visible_rect()
		.size
	)

	return (
		DARTS_LANDSCAPE_MENU_SCALE
		if viewport_size.x > viewport_size.y
		else 1.0
	)


func _darts_menu_size() -> Vector2:
	return DARTS_MENU_SIZE * _darts_menu_scale()


func _apply_darts_menu_layout() -> void:
	if not is_instance_valid(darts_menu_panel):
		return

	var scale_factor: float = _darts_menu_scale()
	var menu_size: Vector2 = _darts_menu_size()

	darts_menu_panel.custom_minimum_size = menu_size
	darts_menu_panel.size = menu_size

	var panel_style := (
		darts_menu_panel.get_theme_stylebox(
			"panel"
		) as StyleBoxFlat
	)

	if panel_style != null:
		var corner_radius: int = int(
			round(10.0 * scale_factor)
		)

		panel_style.corner_radius_top_left = corner_radius
		panel_style.corner_radius_top_right = corner_radius
		panel_style.corner_radius_bottom_left = corner_radius
		panel_style.corner_radius_bottom_right = corner_radius

		panel_style.content_margin_left = (
			4.0 * scale_factor
		)
		panel_style.content_margin_top = (
			4.0 * scale_factor
		)
		panel_style.content_margin_right = (
			4.0 * scale_factor
		)
		panel_style.content_margin_bottom = (
			4.0 * scale_factor
		)

		panel_style.shadow_size = int(
			round(8.0 * scale_factor)
		)

		panel_style.shadow_offset = Vector2(
			0.0,
			3.0 * scale_factor
		)

	var rows := (
		darts_menu_panel.get_node_or_null(
			"Rows"
		) as VBoxContainer
	)

	if rows == null:
		return

	for child: Node in rows.get_children():
		var row := child as Button

		if row == null:
			continue

		row.custom_minimum_size = Vector2(
			menu_size.x -
				8.0 * scale_factor,
			DARTS_MENU_ROW_HEIGHT *
				scale_factor
		)

		row.add_theme_font_size_override(
			"font_size",
			int(
				round(
					DARTS_MENU_FONT_SIZE *
					scale_factor
				)
			)
		)

func _make_darts_menu_button_style(
	background_color: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	style.bg_color = background_color

	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6

	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0

	return style


func _make_darts_menu_row(text_value: String) -> Button:
	var button := Button.new()

	button.text = text_value
	button.custom_minimum_size = Vector2(
		DARTS_MENU_SIZE.x - 8.0,
		DARTS_MENU_ROW_HEIGHT
	)

	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER

	button.add_theme_font_size_override(
		"font_size",
		DARTS_MENU_FONT_SIZE
	)

	button.add_theme_color_override(
		"font_color",
		Color(0.04, 0.04, 0.04, 1.0)
	)

	button.add_theme_color_override(
		"font_hover_color",
		Color(0.04, 0.04, 0.04, 1.0)
	)

	button.add_theme_color_override(
		"font_pressed_color",
		Color(0.04, 0.04, 0.04, 1.0)
	)

	button.add_theme_stylebox_override(
		"normal",
		_make_darts_menu_button_style(
			Color(1.0, 1.0, 1.0, 0.0)
		)
	)

	button.add_theme_stylebox_override(
		"hover",
		_make_darts_menu_button_style(
			Color(0.94, 0.94, 0.94, 1.0)
		)
	)

	button.add_theme_stylebox_override(
		"pressed",
		_make_darts_menu_button_style(
			Color(0.86, 0.86, 0.86, 1.0)
		)
	)

	button.add_theme_stylebox_override(
		"focus",
		StyleBoxEmpty.new()
	)

	return button


func _setup_darts_menu() -> void:
	if (
		is_instance_valid(darts_menu_layer) or
		not is_instance_valid(main_overlay) or
		not is_instance_valid(darts_menu_button)
	):
		return

	for connection: Dictionary in (
		darts_menu_button.pressed.get_connections()
	):
		var callback: Callable = connection.get(
			"callable",
			Callable()
		)

		if not callback.is_valid():
			continue

		if callback == Callable(
			self,
			"_on_darts_menu_button_pressed"
		):
			continue

		if darts_menu_button.pressed.is_connected(callback):
			darts_menu_button.pressed.disconnect(callback)

	if not darts_menu_button.pressed.is_connected(
		_on_darts_menu_button_pressed
	):
		darts_menu_button.pressed.connect(
			_on_darts_menu_button_pressed
		)

	darts_menu_button.tooltip_text = "Menu"

	darts_menu_layer = Control.new()
	darts_menu_layer.name = "DartsMenuLayer"
	darts_menu_layer.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	darts_menu_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	darts_menu_layer.visible = false
	darts_menu_layer.z_index = 5000

	main_overlay.add_child(darts_menu_layer)

	darts_menu_layer.gui_input.connect(
		_on_darts_menu_layer_gui_input
	)

	darts_menu_panel = PanelContainer.new()
	darts_menu_panel.name = "DartsMenuPanel"
	darts_menu_panel.custom_minimum_size = DARTS_MENU_SIZE
	darts_menu_panel.size = DARTS_MENU_SIZE
	darts_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color.WHITE

	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10

	panel_style.content_margin_left = 4.0
	panel_style.content_margin_top = 4.0
	panel_style.content_margin_right = 4.0
	panel_style.content_margin_bottom = 4.0

	panel_style.shadow_color = Color(
		0.0,
		0.0,
		0.0,
		0.22
	)
	panel_style.shadow_size = 8
	panel_style.shadow_offset = Vector2(0.0, 3.0)

	darts_menu_panel.add_theme_stylebox_override(
		"panel",
		panel_style
	)

	darts_menu_layer.add_child(darts_menu_panel)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override(
		"separation",
		0
	)

	darts_menu_panel.add_child(rows)

	var settings_row := _make_darts_menu_row(
		"Settings"
	)
	settings_row.name = "Settings"

	var help_row := _make_darts_menu_row(
		"Help"
	)
	help_row.name = "Help"

	rows.add_child(settings_row)
	rows.add_child(help_row)

	settings_row.pressed.connect(
		_on_darts_menu_settings_pressed
	)

	help_row.pressed.connect(
		_on_darts_menu_help_pressed
	)

	_apply_darts_menu_layout()

	call_deferred(
		"_position_darts_menu"
	)

func _position_darts_menu() -> void:
	if (
		not is_instance_valid(darts_menu_panel) or
		not is_instance_valid(darts_menu_button) or
		not is_instance_valid(main_overlay)
	):
		return

	var scale_factor: float = _darts_menu_scale()
	var menu_size: Vector2 = _darts_menu_size()

	var menu_gap: float = (
		DARTS_MENU_BUTTON_GAP *
		scale_factor
	)

	var screen_margin: float = (
		DARTS_MENU_SCREEN_MARGIN *
		scale_factor
	)

	var overlay_rect: Rect2 = (
		main_overlay.get_global_rect()
	)

	var button_rect: Rect2 = (
		darts_menu_button.get_global_rect()
	)

	var target_position := Vector2(
		button_rect.end.x -
			overlay_rect.position.x -
			menu_size.x,
		button_rect.end.y -
			overlay_rect.position.y +
			menu_gap
	)

	var maximum_position := Vector2(
		maxf(
			screen_margin,
			main_overlay.size.x -
				menu_size.x -
				screen_margin
		),
		maxf(
			screen_margin,
			main_overlay.size.y -
				menu_size.y -
				screen_margin
		)
	)

	target_position.x = clampf(
		target_position.x,
		screen_margin,
		maximum_position.x
	)

	target_position.y = clampf(
		target_position.y,
		screen_margin,
		maximum_position.y
	)

	darts_menu_panel.position = target_position
	darts_menu_panel.size = menu_size

func _on_darts_menu_button_pressed() -> void:
	if darts_menu_open:
		_hide_darts_menu()
	else:
		_show_darts_menu()

func _show_darts_menu() -> void:
	if (
		not is_instance_valid(darts_menu_layer) or
		not is_instance_valid(darts_menu_panel)
	):
		return

	darts_menu_open = true
	_settings_open = true

	_apply_darts_menu_layout()
	_position_darts_menu()

	var menu_size: Vector2 = _darts_menu_size()

	darts_menu_layer.visible = true
	darts_menu_layer.move_to_front()

	darts_menu_panel.pivot_offset = Vector2(
		menu_size.x,
		0.0
	)

	darts_menu_panel.scale = Vector2(
		0.92,
		0.92
	)

	darts_menu_panel.modulate.a = 0.0

	var tween := create_tween().set_parallel(
		true
	)

	tween.tween_property(
		darts_menu_panel,
		"scale",
		Vector2.ONE,
		0.12
	).set_trans(
		Tween.TRANS_BACK
	).set_ease(
		Tween.EASE_OUT
	)

	tween.tween_property(
		darts_menu_panel,
		"modulate:a",
		1.0,
		0.10
	)

func _hide_darts_menu() -> void:
	darts_menu_open = false

	if is_instance_valid(darts_menu_layer):
		darts_menu_layer.visible = false

	_settings_open = false


func _on_darts_menu_layer_gui_input(
	event: InputEvent
) -> void:
	if (
		event is InputEventMouseButton and
		event.button_index == MOUSE_BUTTON_LEFT and
		event.pressed
	):
		_hide_darts_menu()
		get_viewport().set_input_as_handled()

func _on_darts_menu_settings_pressed() -> void:
	OpLog.event(
		LOG_TAG,
		"darts_menu_settings_pressed"
	)

	_hide_darts_menu()

	call_deferred(
		"_open_darts_settings_popup"
	)


func _open_darts_settings_popup() -> void:
	if _settings_open:
		OpLog.w(
			LOG_TAG,
			"darts_settings_already_open"
		)
		return

	if not is_instance_valid(darts_menu_button):
		OpLog.e(
			LOG_TAG,
			"darts_settings_missing_menu_button"
		)
		return

	var existing_node_ids := _snapshot_darts_node_ids()

	_settings_open = true
	SettingsManager.suppress_avatar_changed = spectator_mode
	_hide_points_to_win_popup()

	GameUtils.open_settings_popup(
		self,
		mediaPlugin,
		darts_menu_button,
		null if spectator_mode else _get_settings_avatar_display(),
		_get_music_stream(),
		Callable(self, "_settings_rows_hook"),
		func() -> void:
			SettingsManager.suppress_avatar_changed = false
			_settings_open = false
			_update_points_to_win()

			OpLog.event(
				LOG_TAG,
				"darts_settings_popup_closed"
			)
	)

	call_deferred(
		"_raise_new_darts_modal",
		existing_node_ids
	)

func _on_darts_menu_help_pressed() -> void:
	OpLog.event(
		LOG_TAG,
		"darts_menu_help_pressed"
	)

	_hide_darts_menu()

	call_deferred(
		"_open_darts_rules_popup"
	)


func _open_darts_rules_popup() -> void:
	if not is_instance_valid(darts_menu_button):
		OpLog.e(
			LOG_TAG,
			"darts_rules_missing_menu_button"
		)
		return

	var existing_node_ids := _snapshot_darts_node_ids()

	OpLog.event(LOG_TAG, [
		"darts_rules_popup_open",
		" title=",
		_get_rules_title(),
		" text_length=",
		_get_rules_text().length()
	])
	
	_hide_points_to_win_popup()

	GameUtils.open_rules_popup(
		self,
		darts_menu_button,
		_get_rules_title(),
		_get_rules_text(),
		func():
			_rules_open = false
	)

	call_deferred(
		"_raise_new_darts_modal",
		existing_node_ids
	)

func _snapshot_darts_node_ids() -> Dictionary:
	var existing_node_ids: Dictionary = {}
	var tree_root := get_tree().root

	if not is_instance_valid(tree_root):
		return existing_node_ids

	_collect_darts_node_ids(
		tree_root,
		existing_node_ids
	)

	return existing_node_ids


func _collect_darts_node_ids(
	node: Node,
	existing_node_ids: Dictionary
) -> void:
	if not is_instance_valid(node):
		return

	existing_node_ids[node.get_instance_id()] = true

	for child: Node in node.get_children():
		_collect_darts_node_ids(
			child,
			existing_node_ids
		)


func _raise_new_darts_modal(
	existing_node_ids: Dictionary
) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if not is_inside_tree():
		return

	var tree_root := get_tree().root

	if not is_instance_valid(tree_root):
		return

	_raise_new_darts_modal_recursive(
		tree_root,
		existing_node_ids
	)


func _raise_new_darts_modal_recursive(
	node: Node,
	existing_node_ids: Dictionary
) -> void:
	if not is_instance_valid(node):
		return

	var node_is_new := not existing_node_ids.has(
		node.get_instance_id()
	)

	if node_is_new and node is Window:
		var popup_window := node as Window

		popup_window.always_on_top = true
		popup_window.transient = true
		popup_window.grab_focus()

		OpLog.d(LOG_TAG, [
			"modal_window_raised path=",
			popup_window.get_path()
		])

		return

	if node_is_new and node is CanvasLayer:
		var canvas_layer := node as CanvasLayer

		canvas_layer.layer = DARTS_MODAL_CANVAS_LAYER

		OpLog.d(LOG_TAG, [
			"modal_canvas_layer_raised path=",
			canvas_layer.get_path(),
			" layer=",
			canvas_layer.layer
		])

		return

	if node_is_new and node is CanvasItem:
		var parent := node.get_parent()

		var parent_is_new_canvas_node := (
			is_instance_valid(parent) and
			not existing_node_ids.has(parent.get_instance_id()) and
			(
				parent is CanvasItem or
				parent is CanvasLayer
			)
		)

		if not parent_is_new_canvas_node:
			var canvas_item := node as CanvasItem

			canvas_item.z_as_relative = false
			canvas_item.z_index = DARTS_MODAL_Z_INDEX
			canvas_item.move_to_front()

			OpLog.d(LOG_TAG, [
				"modal_canvas_item_raised path=",
				canvas_item.get_path(),
				" z_index=",
				canvas_item.z_index
			])

			return

	for child: Node in node.get_children():
		_raise_new_darts_modal_recursive(
			child,
			existing_node_ids
		)

func _on_game_ready():
	OpLog.game_opened(
		LOG_TAG,
		[
			"localMode=",
			appPlugin == null,
			" uuid=",
			my_uuid
		]
	)

	call_deferred("_initialize_darts_avatars")

	_ensure_main_dart()
	_setup_dart_indicator()
	_setup_points_to_win_popup()

	settings_button = darts_menu_button
	rules_button = darts_menu_button

	call_deferred("_setup_darts_menu")

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

	_apply_landscape_ui()

	OpLog.i(LOG_TAG, [
		"game_ready main_dart_valid=",
		is_instance_valid(main_dart),
		" mode=",
		mode,
		" player=",
		player,
		" menu_valid=",
		is_instance_valid(darts_menu_button),
		" settings_anchor_valid=",
		is_instance_valid(settings_button)
	])

func _set_game_data(new_replay: String):
	OpLog.event(LOG_TAG, ["set_game_data_in raw=", new_replay])

	var parsed_v: Variant = JSON.parse_string(new_replay)
	if typeof(parsed_v) != TYPE_DICTIONARY:
		OpLog.e(LOG_TAG, [
			"set_game_data_parse_failed type=", typeof(parsed_v),
			" raw=", new_replay
		])
		return

	var parsed: Dictionary = parsed_v

	var incoming_replay := String(parsed.get("replay", ""))

	if is_replaying and incoming_replay != "" and incoming_replay == replay:
		OpLog.w(LOG_TAG, [
			"set_game_data_ignored_duplicate_while_replaying replay_len=", incoming_replay.length()
		])
		return

	is_my_turn = bool(parsed.get("isYourTurn", false))
	player = int(parsed.get("player", 1))
	replay = incoming_replay
	mode = int(parsed.get("mode", mode if mode > 0 else 101))

	if not is_my_turn:
		_update_points_to_win()

	var opponent_avatar_key = ""
	var p1_id: String = String(parsed.get("player1", ""))
	var p2_id: String = String(parsed.get("player2", ""))
	var winner_payload: String = String(parsed.get("winner", ""))

	spectator_mode = my_uuid != "" and p1_id != "" and p2_id != "" and my_uuid != p1_id and my_uuid != p2_id

	OpLog.i(LOG_TAG, [
		"set_game_data_fields my_uuid=", my_uuid,
		" player1=", p1_id,
		" player2=", p2_id,
		" incoming_player=", player,
		" is_my_turn_raw=", is_my_turn,
		" spectator=", spectator_mode,
		" mode=", mode,
		" replay_len=", replay.length(),
		" has_winner=", winner_payload != ""
	])

	if is_instance_valid(spectator_label):
		spectator_label.visible = spectator_mode

	if is_instance_valid(you_label):
		you_label.modulate.a = 0.0 if spectator_mode else 1.0

	if is_my_turn and not spectator_mode:
		player = 2 if player == 1 else 1
	elif spectator_mode:
		player = 1

	if player == 1 or spectator_mode:
		opponent_avatar_key = "avatar2"
	else:
		opponent_avatar_key = "avatar1"

	OpLog.i(LOG_TAG, [
		"resolved_player player=", player,
		" is_my_turn=", is_my_turn,
		" spectator=", spectator_mode,
		" opponent_avatar_key=", opponent_avatar_key
	])

	_configure_darts_avatar(player_avatar_display)
	_configure_darts_avatar(opp_avatar_display)

	if spectator_mode:
		var player_avatar_string := String(parsed.get("avatar1", ""))
		var opponent_avatar_string := String(parsed.get("avatar2", ""))

		if player_avatar_string != "" and is_instance_valid(player_avatar_display):
			var player_data := GameUtils._parse_avatar_string(player_avatar_string)
			player_avatar_display.call_deferred("update_avatar_from_data", player_data)

		if opponent_avatar_string != "" and is_instance_valid(opp_avatar_display):
			var opponent_data := GameUtils._parse_avatar_string(opponent_avatar_string)
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)
	else:
		if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("update_display_from_settings"):
			player_avatar_display.call_deferred("update_display_from_settings")

		var opponent_avatar_string := String(parsed.get(opponent_avatar_key, ""))

		if opponent_avatar_string != "" and is_instance_valid(opp_avatar_display):
			var opponent_data := GameUtils._parse_avatar_string(opponent_avatar_string)
			opp_avatar_display.call_deferred("update_avatar_from_data", opponent_data)

	stop_waiting_animation()
	redemption_active = false
	redemption_darts_allowed = 0
	replay_played = replay != "" and replay == last_replay_played
	game_over = false
	match_result = RESULT_NONE
	reset_game_board()

	if is_instance_valid(winner_label):
		winner_label.visible = false
	else:
		OpLog.w(LOG_TAG, "winner_label_missing")

	if winner_payload != "":
		OpLog.event(LOG_TAG, ["winner_payload_received payload=", winner_payload])

		var parts := winner_payload.split("|", false)
		var result_code := RESULT_NONE

		if parts.size() >= 2:
			var sender_uuid := String(parts[0])
			var winner_val: int = int(parts[1])

			if winner_val == 0:
				result_code = RESULT_DRAW
			elif sender_uuid == my_uuid:
				result_code = RESULT_WIN if winner_val == 1 else RESULT_LOSS
			else:
				result_code = RESULT_WIN if winner_val == -1 else RESULT_LOSS

			OpLog.i(LOG_TAG, [
				"winner_payload_resolved sender=", sender_uuid,
				" winner_val=", winner_val,
				" result_code=", result_code
			])
		else:
			OpLog.w(LOG_TAG, ["bad_winner_payload payload=", winner_payload])

		if not replay.is_empty():
			var completed_replay := parse_replay(replay)

			if completed_replay.has("post_state"):
				var post_state: Array = completed_replay["post_state"]

				if post_state.size() >= 2:
					set_score(1, int(post_state[0]), false)
					set_score(2, int(post_state[1]), false)

			replay_played = true
			last_replay_played = replay

		_show_result(result_code)
		return

	if replay.is_empty():
		p1_pre_score = mode
		p2_pre_score = mode
		set_score(1, mode)
		set_score(2, mode)

	OpLog.i(LOG_TAG, [
		"set_game_data_before_process p1_score=", p1_score,
		" p2_score=", p2_score,
		" p1_pre=", p1_pre_score,
		" p2_pre=", p2_pre_score
	])

	if (is_my_turn and not spectator_mode):
		var saved_progress = get_saved_turn_progress()

		if not saved_progress.is_empty():
			await _restore_darts_turn_progress(
				saved_progress
			)

			return

	_process_game_state()

func _get_turn_dart_limit() -> int:
	if redemption_active:
		return redemption_darts_allowed
	return 3

func _maybe_start_redemption_from_replay() -> bool:
	if spectator_mode or player != 2 or replay == null or replay.is_empty():
		return false

	var parsed := parse_replay(replay)

	if not parsed.has("pre_state") or not parsed.has("post_state"):
		OpLog.w(LOG_TAG, "redemption_check_missing_state")
		return false

	var pre_state: Array = parsed["pre_state"]
	var post_state: Array = parsed["post_state"]

	if pre_state.size() < 2 or post_state.size() < 2:
		OpLog.w(LOG_TAG, [
			"redemption_check_bad_state pre=", pre_state,
			" post=", post_state
		])
		return false

	if not (int(pre_state[0]) != 0 and int(post_state[0]) == 0):
		return false

	redemption_active = true
	redemption_darts_allowed = 3

	OpLog.event(LOG_TAG, [
		"redemption_started pre_state=", pre_state,
		" post_state=", post_state,
		" darts_allowed=", redemption_darts_allowed
	])

	return true

func _process_game_state():
	OpLog.d(LOG_TAG, [
		"process_game_state is_my_turn=", is_my_turn,
		" spectator=", spectator_mode,
		" replay_len=", replay.length(),
		" replay_played=", replay_played,
		" num_shots=", num_shots,
		" turn_limit=", _get_turn_dart_limit(),
		" game_over=", game_over
	])

	if is_my_turn:
		stop_waiting_animation()

		if replay != null and not replay.is_empty() and not replay_played:
			replay_played = true
			await play_replay(replay)

			var started_redemption := _maybe_start_redemption_from_replay()
			if started_redemption:
				reset_game_board()
				replay_played = true
			else:
				var won_after_replay := check_win()
				if won_after_replay:
					return

				reset_game_board()
				replay_played = true

		var turn_limit := _get_turn_dart_limit()

		if num_shots < turn_limit:
			var player_dart: Dart = spawn_dart(true)
			if not is_instance_valid(player_dart):
				OpLog.e(LOG_TAG, "spawn_turn_dart_failed")
				return

			OpLog.event(LOG_TAG, [
				"spawn_turn_dart num_shots=", num_shots,
				" turn_limit=", turn_limit,
				" player=", player,
				" redemption=", redemption_active
			])

			player_dart.on_hit_board.connect(func(score):
				var hit_pos: Vector3 = player_dart.global_position
				var hit_score: Array = [int(score[0]), int(score[1]), int(score[2])]
				var move_arr: Array = [0, player_dart.position.x, player_dart.position.y]
				move_arr.append_array(score)
				my_moves.append(move_arr)

				OpLog.event(LOG_TAG, [
					"dart_hit score=", score,
					" move=", move_arr,
					" player=", player,
					" before_score=", get_score(player)
				])

				dec_score(player, int(hit_score[0]))

				if get_score(player) < 0:
					OpLog.event(LOG_TAG, [
						"bust player=", player,
						" score_hit=", score[0],
						" score_after=", get_score(player)
					])

					_show_score_popup(hit_pos, hit_score)

					await get_tree().create_timer(SCORE_BUST_DELAY).timeout
					_show_score_popup(Vector3.ZERO, [], true, true)

					var old_score := p1_pre_score if player == 1 else p2_pre_score

					await get_tree().create_timer(1).timeout
					set_score(player, old_score)
					num_shots = _get_turn_dart_limit()
				else:
					_show_score_popup(hit_pos, hit_score)

				if get_score(player) == 0:
					OpLog.event(LOG_TAG, [
						"player_reached_zero player=", player,
						" num_shots=", num_shots
					])
					num_shots = _get_turn_dart_limit()
				
				_save_darts_turn_progress()
				_process_game_state()
			)
		else:
			send_replay()
	else:
		if replay != null and not replay.is_empty():
			var parsed := parse_replay(replay)

			if parsed.has("post_state"):
				var post_state = parsed["post_state"]
				set_score(1, post_state[0])
				set_score(2, post_state[1])

				var won_waiting := check_win()
				if won_waiting:
					return
			else:
				OpLog.w(LOG_TAG, ["waiting_state_missing_post_state replay=", replay])

		if not game_over and not spectator_mode:
			start_waiting_animation()
		else:
			stop_waiting_animation()

func _restore_darts_turn_progress(
	data: Dictionary
) -> void:
	var saved_replay := String(
		data.get(
			"replay",
			""
		)
	)

	if saved_replay.is_empty():
		_process_game_state()
		return

	var parsed := parse_replay(
		saved_replay
	)

	if (
		not parsed.has("pre_state") or
		not parsed.has("post_state")
	):
		OpLog.w(
			LOG_TAG,
			"recovery replay missing state"
		)

		_process_game_state()
		return

	var pre_state: Array = parsed[
		"pre_state"
	]

	var post_state: Array = parsed[
		"post_state"
	]

	if (
		pre_state.size() < 2 or
		post_state.size() < 2
	):
		_process_game_state()
		return

	reset_game_board()

	p1_pre_score = int(
		pre_state[0]
	)

	p2_pre_score = int(
		pre_state[1]
	)

	set_score(
		1,
		int(post_state[0]),
		false
	)

	set_score(
		2,
		int(post_state[1]),
		false
	)

	my_moves.clear()

	var moves: Array = parsed.get(
		"moves",
		[]
	)

	for raw_move in moves:
		var move: Array = raw_move

		my_moves.append(
			move.duplicate()
		)

		var restored_dart: Dart = spawn_dart(
			false
		)

		if not is_instance_valid(
			restored_dart
		):
			continue

		var hit: Array[int] = [
			int(move[3]),
			int(move[4]),
			int(move[5]),
		]

		restored_dart.restore_hit(
			Vector3(
				float(move[1]),
				float(move[2]),
				DART_BOARD_PLANE_Z
			),
			hit
		)

	replay_played = true

	if not replay.is_empty():
		last_replay_played = replay

	OpLog.event(
		LOG_TAG,
		[
			"turn_recovery_restored moves=",
			my_moves.size(),
			" p1=",
			p1_score,
			" p2=",
			p2_score,
			" pending_send=",
			has_pending_send()
		]
	)

	if has_pending_send():
		_show_send_retry(
			false
		)

		return

	_process_game_state()

	if (
		data.has("pending_x") and
		data.has("pending_y")
	):
		await get_tree().process_frame

		if (
			is_instance_valid(current_dart) and
			current_dart.is_mine
		):
			var saved_target := Vector3(
				float(data["pending_x"]),
				float(data["pending_y"]),
				DART_BOARD_PLANE_Z
			)

			_stop_dart_idle()

			current_dart.throw(
				saved_target
			)

			current_dart = null

			_update_dart_indicator()

func _show_result(result_code: int) -> void:
	match_result = result_code
	game_over = result_code != RESULT_NONE

	if result_code == RESULT_NONE:
		OpLog.d(LOG_TAG, "show_result skipped result_none")
		return

	is_my_turn = false
	stop_waiting_animation()
	_update_points_to_win()

	if not is_instance_valid(winner_label):
		OpLog.w(LOG_TAG, ["show_result_missing_winner_label result_code=", result_code])
		return

	winner_label.visible = true

	match result_code:
		RESULT_WIN:
			winner_label.text = "YOU WIN!"
			winner_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
			if is_instance_valid(player_avatar_display):
				GameUtils._show_win_burst(player_avatar_display)

		RESULT_LOSS:
			winner_label.text = "YOU LOSE"
			winner_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			if is_instance_valid(opp_avatar_display):
				GameUtils._show_win_burst(opp_avatar_display)

		RESULT_DRAW:
			winner_label.text = "DRAW!"
			winner_label.add_theme_color_override("font_color", Color(1, 1, 1))

	OpLog.event(LOG_TAG, [
		"show_result result_code=", result_code,
		" text=", winner_label.text,
		" player=", player,
		" spectator=", spectator_mode,
		" p1_score=", p1_score,
		" p2_score=", p2_score,
		" redemption=", redemption_active
	])

func check_win() -> bool:
	if redemption_active:
		OpLog.d(LOG_TAG, "check_win_skipped redemption_active=true")
		return false

	var my_score := get_score(player)
	var opp_player := 1 if player == 2 else 2
	var opp_score := get_score(opp_player)

	OpLog.d(LOG_TAG, [
		"check_win player=", player,
		" my_score=", my_score,
		" opp_player=", opp_player,
		" opp_score=", opp_score,
		" replay_len=", replay.length()
	])

	if replay != null and not replay.is_empty():
		var parsed := parse_replay(replay)

		if parsed.has("pre_state") and parsed.has("post_state"):
			var pre_state: Array = parsed["pre_state"]
			var post_state: Array = parsed["post_state"]

			if pre_state.size() >= 2 and post_state.size() >= 2:
				var p1_pre := int(pre_state[0])
				var p1_post := int(post_state[0])
				var p2_post := int(post_state[1])

				if p1_pre > 0 and p1_post == 0 and p2_post > 0:
					OpLog.i(LOG_TAG, [
						"check_win_waiting_for_redemption pre=", pre_state,
						" post=", post_state
					])
					return false

				if p1_pre == 0 and p1_post == 0:
					if p2_post == 0:
						_show_result(RESULT_DRAW)
					elif player == 1:
						_show_result(RESULT_WIN)
					else:
						_show_result(RESULT_LOSS)

					OpLog.event(LOG_TAG, [
						"check_win_replay_result pre=", pre_state,
						" post=", post_state,
						" result=", match_result
					])

					return true
		else:
			OpLog.w(LOG_TAG, "check_win_replay_missing_state")

	if my_score == 0:
		OpLog.event(LOG_TAG, ["check_win_local_zero player=", player])
		_show_result(RESULT_WIN)
		return true

	if opp_score == 0:
		OpLog.event(LOG_TAG, ["check_win_opponent_zero opp_player=", opp_player])
		_show_result(RESULT_LOSS)
		return true

	return false

func _build_local_turn_replay() -> String:
	var moves_str := ""

	for move in my_moves:
		moves_str += (
			"move:" +
			str(int(move[0])) + "," +
			str("%0.6f" % move[1]) + "," +
			str("%0.6f" % move[2]) + "," +
			str(int(move[3])) + "," +
			str(int(move[4])) + "," +
			str(int(move[5])) + "|"
		)

	return (
		"state:" +
		str(p1_pre_score) + "," +
		str(p2_pre_score) + "|" +
		moves_str +
		"state:" +
		str(p1_score) + "," +
		str(p2_score)
	)


func _save_darts_turn_progress(
	pending_throw = null
) -> void:
	var data := {
		"replay": _build_local_turn_replay()
	}

	if pending_throw is Vector2:
		data["pending_x"] = (
			"%0.6f" %
			float(pending_throw.x)
		)

		data["pending_y"] = (
			"%0.6f" %
			float(pending_throw.y)
		)

	save_turn_progress(
		data
	)

func send_replay():
	var replay_out: String = _build_local_turn_replay()

	var result = {
		"replay": replay_out
	}

	var p1_out := p1_score
	var p2_out := p2_score
	var turn_ended_game := false
	match_result = RESULT_NONE

	if redemption_active and player == 2:
		if p2_out == 0:
			_show_result(RESULT_DRAW)
		else:
			_show_result(RESULT_LOSS)

		turn_ended_game = true
	elif player == 2 and p2_out == 0:
		_show_result(RESULT_WIN)
		turn_ended_game = true
	elif player == 1 and p1_out == 0:
		turn_ended_game = false
	else:
		turn_ended_game = false
		
	if turn_ended_game:
		is_my_turn = false
		_update_points_to_win()

	if turn_ended_game:
		var winner_value := ""

		match match_result:
			RESULT_WIN:
				winner_value = "1"
			RESULT_LOSS:
				winner_value = "-1"
			RESULT_DRAW:
				winner_value = "0"

		if winner_value != "":
			result["winner"] = my_uuid + "|" + winner_value
			OpLog.event(LOG_TAG, [
				"send_replay_winner winner=", result["winner"],
				" match_result=", match_result
			])
	else:
		is_my_turn = false
		_update_points_to_win()
		play_sent_animation()

	var avatar_key := ("avatar1" if player == 1 else "avatar2")
	if is_instance_valid(player_avatar_display) and player_avatar_display.has_method("get_avatar_data_string"):
		result[avatar_key] = player_avatar_display.get_avatar_data_string()

	var game_data = JSON.stringify(result)

	OpLog.event(LOG_TAG, [
		"send_game_out player=", player,
		" mode=", mode,
		" moves=", my_moves.size(),
		" p1_pre=", p1_pre_score,
		" p2_pre=", p2_pre_score,
		" p1_score=", p1_score,
		" p2_score=", p2_score,
		" redemption=", redemption_active,
		" turn_ended_game=", turn_ended_game,
		" has_winner=", result.has("winner"),
		" replay_len=", replay_out.length(),
		" raw=", game_data
	])

	send_game_data(game_data)

func play_replay(replay_str: String):
	if is_replaying:
		OpLog.w(LOG_TAG, ["play_replay_skipped_already_running len=", replay_str.length()])
		return

	is_replaying = true
	_update_points_to_win()
	OpLog.event(LOG_TAG, ["play_replay_start len=", replay_str.length()])

	var parsed = parse_replay(replay_str)

	if not parsed.has("pre_state") or not parsed.has("post_state"):
		OpLog.e(LOG_TAG, ["play_replay_missing_state parsed=", parsed])
		is_replaying = false
		_update_points_to_win()
		return

	var other_player = 1 if player == 2 else 2

	p1_pre_score = parsed["pre_state"][0]
	p2_pre_score = parsed["pre_state"][1]
	set_score(1, parsed["pre_state"][0])
	set_score(2, parsed["pre_state"][1])

	OpLog.i(LOG_TAG, [
		"play_replay_pre_state p1=", p1_pre_score,
		" p2=", p2_pre_score,
		" moves=", parsed["moves"].size(),
		" other_player=", other_player
	])

	for move in parsed["moves"]:
		spawn_dart(false)

		var dart_pos: Vector3 = Vector3(float(move[1]), float(move[2]), 0.067)
		var replay_score: Array[int] = [
			int(move[3]),
			int(move[4]),
			int(move[5])
		]
		var replay_dart: Dart = current_dart
		var replay_popup_pos: Vector3 = dart_pos

		OpLog.event(LOG_TAG, [
			"replay_move move=", move,
			" dart_pos=", dart_pos,
			" popup_pos=", replay_popup_pos,
			" other_player=", other_player
		])

		if is_instance_valid(replay_dart):
			replay_dart.replay_hit = replay_score
			replay_dart.throw(dart_pos)
			await get_tree().create_timer(DART_REPLAY_HIT_WAIT).timeout
		else:
			await get_tree().create_timer(0.25).timeout

		dec_score(other_player, int(move[3]))

		if get_score(other_player) < 0:
			OpLog.event(LOG_TAG, [
				"replay_bust other_player=", other_player,
				" move_score=", move[3],
				" score_after=", get_score(other_player)
			])

			_show_score_popup(replay_popup_pos, replay_score)

			await get_tree().create_timer(SCORE_BUST_DELAY).timeout
			_show_score_popup(Vector3.ZERO, [], true, true)
		else:
			_show_score_popup(replay_popup_pos, replay_score)

		await get_tree().create_timer(SCORE_REPLAY_POPUP_WAIT).timeout

	set_score(1, parsed["post_state"][0])
	set_score(2, parsed["post_state"][1])

	if player == 1:
		p2_pre_score = parsed["post_state"][1]
	elif player == 2:
		p1_pre_score = parsed["post_state"][0]

	OpLog.i(LOG_TAG, [
		"play_replay_done post_state=", parsed["post_state"],
		" p1_score=", p1_score,
		" p2_score=", p2_score
	])
	
	last_replay_played = replay_str
	is_replaying = false
	_update_points_to_win()

func parse_replay(replay_str: String) -> Dictionary:
	var result = {"moves": []}

	if replay_str.strip_edges() == "":
		OpLog.w(LOG_TAG, "parse_replay_empty")
		return result

	for elem in replay_str.split("|"):
		var spl = elem.split(":")

		if spl.size() < 2:
			if elem.strip_edges() != "":
				OpLog.w(LOG_TAG, ["parse_replay_bad_chunk chunk=", elem])
			continue

		if spl[0] == "state":
			var state_spl = spl[1].split(",")

			if state_spl.size() < 2:
				OpLog.w(LOG_TAG, ["parse_replay_bad_state chunk=", elem])
				continue

			var state_key = "pre_state"
			if "pre_state" in result:
				state_key = "post_state"

			result[state_key] = [int(state_spl[0]), int(state_spl[1])]

		if spl[0] == "move":
			var move = []
			var move_spl = spl[1].split(",")

			if move_spl.size() < 6:
				OpLog.w(LOG_TAG, ["parse_replay_bad_move chunk=", elem])
				continue

			for val in move_spl:
				move.append(float(val))

			result["moves"].append(move)

	OpLog.i(LOG_TAG, [
		"parse_replay_done len=", replay_str.length(),
		" moves=", result["moves"].size(),
		" has_pre=", result.has("pre_state"),
		" has_post=", result.has("post_state")
	])

	return result
	
func _format_score(score: int) -> String:
	if score >= 0 and score < 1000:
		return "%03d" % score

	return str(score)

func set_score(
	target_player: int,
	score: int,
	animate: bool = true
) -> void:
	var previous_score := get_score(target_player)

	if target_player == 1:
		p1_score = score
	elif target_player == 2:
		p2_score = score
	else:
		OpLog.w(
			LOG_TAG,
			[
				"set_score_bad_target target_player=",
				target_player,
				" score=",
				score
			]
		)
		return

	var label: Label = null
	var is_local_score := self.player == target_player

	if is_local_score:
		label = you_score_label
	else:
		label = opp_score_label

	if not is_instance_valid(label):
		OpLog.w(
			LOG_TAG,
			[
				"score_label_missing target_player=",
				target_player,
				" score=",
				score
			]
		)
		return

	if not animate or previous_score < 0 or previous_score == score:
		_stop_score_tween(is_local_score)
		label.text = _format_score(score)
	else:
		_animate_score_label(
			label,
			previous_score,
			score,
			is_local_score
		)

	dbg(
		"set_score target=%d score=%d p1=%d p2=%d" %
		[target_player, score, p1_score, p2_score]
	)

	_update_points_to_win()

func _stop_score_tween(local_score: bool) -> void:
	var tween := (
		player_score_tween
		if local_score
		else opponent_score_tween
	)

	if tween and tween.is_valid():
		tween.kill()

	if local_score:
		player_score_tween = null
	else:
		opponent_score_tween = null


func _animate_score_label(
	label: Label,
	from_score: int,
	to_score: int,
	local_score: bool
) -> void:
	_stop_score_tween(local_score)

	var score_difference : Variant = abs(to_score - from_score)

	if score_difference == 0:
		label.text = _format_score(to_score)
		return

	var animation_duration := clampf(
		SCORE_TICK_MIN_DURATION +
			log(1.0 + float(score_difference)) *
			SCORE_TICK_LOG_SCALE,
		SCORE_TICK_MIN_DURATION,
		SCORE_TICK_MAX_DURATION
	)

	var last_displayed_score := from_score
	var tween := create_tween()

	tween.set_trans(Tween.TRANS_EXPO)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_method(
		func(value: float) -> void:
			if not is_instance_valid(label):
				return

			var displayed_score := int(round(value))

			if displayed_score == last_displayed_score:
				return

			last_displayed_score = displayed_score
			label.text = _format_score(displayed_score),
		float(from_score),
		float(to_score),
		animation_duration
	)

	tween.finished.connect(
		func() -> void:
			if is_instance_valid(label):
				label.text = _format_score(to_score)

			if local_score:
				player_score_tween = null
			else:
				opponent_score_tween = null
	)

	if local_score:
		player_score_tween = tween
	else:
		opponent_score_tween = tween

func dec_score(target_player: int, score: int):
	if target_player == 1:
		set_score(1, p1_score - score)
	elif target_player == 2:
		set_score(2, p2_score - score)

func get_score(target_player: int) -> int:
	if target_player == 1:
		return p1_score
	elif target_player == 2:
		return p2_score
	return -1

func reset_game_board():
	_stop_dart_idle()

	if current_dart != null:
		current_dart.queue_free()
		current_dart = null

	for dart in darts:
		dart.queue_free()

	darts.clear()
	my_moves.clear()
	num_shots = 0
	_update_dart_indicator()

	OpLog.d(LOG_TAG, "reset_game_board")

func spawn_dart(is_mine: bool) -> Dart:
	if not _ensure_main_dart():
		return null

	main_dart.visible = false

	var new_dart := main_dart.duplicate() as Dart

	if not is_instance_valid(new_dart):
		OpLog.e(LOG_TAG, "spawn_dart_duplicate_failed")
		return null

	new_dart.is_mine = is_mine
	new_dart.finished = false
	new_dart.replay_hit.clear()
	new_dart.position = DART_IDLE_POSITION
	new_dart.visible = true

	add_child(new_dart)

	darts.append(new_dart)
	current_dart = new_dart
	num_shots += 1

	if is_mine:
		_start_dart_idle(new_dart)

	_update_dart_indicator()

	OpLog.event(LOG_TAG, [
		"spawn_dart is_mine=", is_mine,
		" num_shots=", num_shots,
		" player=", player,
		" pos=", new_dart.position,
		" basis=", new_dart.basis
	])

	return new_dart

func _unhandled_input(event: InputEvent) -> void:
	if _settings_open or spectator_mode:
		if event is InputEventMouseButton and event.pressed:
			OpLog.d(LOG_TAG, [
				"input_blocked settings_open=", _settings_open,
				" spectator=", spectator_mode
			])
		return

	if event is InputEventMouseButton and current_dart != null and current_dart.is_mine:
		if event.button_index == 1:
			if event.pressed:
				drag_start_pos = event.position
				dragging = true

				dbg("drag_start pos=%s" % str(drag_start_pos))
			else:
				if dragging:
					var drag_end_pos: Vector2 = event.position
					var delta: Vector2 = drag_end_pos - drag_start_pos
					delta.y = -delta.y

					var shot_coords = calc_shot_coordinates(delta)
					shot_coords.y += 0.344

					OpLog.event(LOG_TAG, [
						"dart_throw_input drag_start=", drag_start_pos,
						" drag_end=", drag_end_pos,
						" delta=", delta,
						" shot_coords=", shot_coords,
						" player=", player,
						" num_shots=", num_shots
					])

					_stop_dart_idle()
					_save_darts_turn_progress(Vector2(shot_coords.x, shot_coords.y))
					current_dart.throw(Vector3(shot_coords.x, shot_coords.y, 0.067))
					current_dart = null
					_update_dart_indicator()

					dragging = false

const rect_min_x = -250.0
const rect_max_x = 250.0
const rect_min_y = 100.0
const rect_max_y = 550.0
const board_radius = 0.535
func calc_shot_coordinates(shot_delta: Vector2) -> Vector2:
	var rect_center_x: float = (rect_min_x + rect_max_x) / 2.0
	var rect_half_width: float = (rect_max_x - rect_min_x) / 2.0

	var rect_center_y: float = (rect_min_y + rect_max_y) / 2.0
	var rect_half_height: float = (rect_max_y - rect_min_y) / 2.0

	var norm_x: float
	if rect_half_width == 0.0:
		norm_x = 0.0
	else:
		norm_x = (shot_delta.x - rect_center_x) / rect_half_width

	var norm_y: float
	if rect_half_height == 0.0:
		norm_y = 0.0
	else:
		norm_y = (shot_delta.y - rect_center_y) / rect_half_height

	norm_x = clamp(norm_x, -1.0, 1.0)
	norm_y = clamp(norm_y, -1.0, 1.0)

	var u: float = norm_x
	var v: float = norm_y

	var x_unit_disk: float
	var y_unit_disk: float
	if u == 0.0 and v == 0.0:
		x_unit_disk = 0.0
		y_unit_disk = 0.0
	else:
		var r_map: float
		var phi_map: float

		if u * u > v * v:
			r_map = u
			phi_map = (PI / 4.0) * (v / u)
		else:
			r_map = v
			phi_map = (PI / 2.0) - (PI / 4.0) * (u / v)

		x_unit_disk = r_map * cos(phi_map)
		y_unit_disk = r_map * sin(phi_map)

	return Vector2(x_unit_disk, y_unit_disk) * board_radius

func play_sent_animation() -> void:
	if not is_instance_valid(sent_label):
		OpLog.w(LOG_TAG, "sent_animation_missing_label")
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

		if not game_over and not spectator_mode and not is_my_turn:
			start_waiting_animation()
		else:
			stop_waiting_animation()
	)
