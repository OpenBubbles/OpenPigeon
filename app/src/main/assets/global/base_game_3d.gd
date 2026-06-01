class_name BaseGame3D
extends Node3D

const DEV_UUID := "0a602920-2033-469d-aab8-5e832c5d4f6a"
const BASE_WAIT_TEXT: String = "WAITING FOR OPPONENT"

@onready var settings_button: Button = get_node_or_null("%SettingsButton")
@onready var rules_button: Button = get_node_or_null("%RulesButton")

@onready var waiting_label: Label = get_node_or_null("%waitingLabel")
@onready var waiting_blur: ColorRect = get_node_or_null("%WaitBlur")
@onready var dot_timer: Timer = get_node_or_null("%DotTimer")

var appPlugin = null
var mediaPlugin = null
var my_uuid: String = ""
var _settings_open := false

var spectator_mode: bool = false
var dot_count: int = 0
var game_settings_category: String = ""

func _ready() -> void:
	if Engine.has_singleton("OpenPigeonMedia"):
		mediaPlugin = Engine.get_singleton("OpenPigeonMedia")
	GameUtils.start_music(self, _get_music_stream(), mediaPlugin)

	if is_instance_valid(settings_button) and not settings_button.pressed.is_connected(_on_settings_button_pressed):
		settings_button.pressed.connect(_on_settings_button_pressed)
	if is_instance_valid(rules_button) and not rules_button.pressed.is_connected(_on_rules_button_pressed):
		rules_button.pressed.connect(_on_rules_button_pressed)
	if is_instance_valid(dot_timer) and not dot_timer.timeout.is_connected(_on_dot_timer_timeout):
		dot_timer.timeout.connect(_on_dot_timer_timeout)

	appPlugin = Engine.get_singleton("AppPlugin")
	if appPlugin:
		appPlugin.connect("set_game_data", _set_game_data)
		my_uuid = appPlugin.getSenderUUID()
		appPlugin.onReady()
	else:
		my_uuid = DEV_UUID
		var dev := _get_dev_data()
		if dev != "":
			_set_game_data(dev)

	_on_game_ready()

func _exit_tree() -> void:
	GameUtils.stop_music(self)

func _on_settings_button_pressed() -> void:
	if _settings_open:
		return
	_settings_open = true
	GameUtils.open_settings_popup(
		self, mediaPlugin, settings_button, _get_settings_avatar_display(), _get_music_stream(),
		Callable(self, "_add_settings_rows"),
		func(): _settings_open = false
	)

func _on_rules_button_pressed() -> void:
	GameUtils.open_rules_popup(self, rules_button, _get_rules_title(), _get_rules_text())

func start_waiting_animation() -> void:
	if spectator_mode:
		return
	dot_count = 0
	waiting_label.text = BASE_WAIT_TEXT + "."
	waiting_label.visible = true
	waiting_label.modulate.a = 0.0
	waiting_blur.visible = true
	waiting_blur.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(waiting_label, "modulate:a", 1.0, 0.3)
	tw.tween_property(waiting_blur, "modulate:a", 1.0, 0.3)
	tw.tween_callback(func(): dot_timer.start())

func stop_waiting_animation() -> void:
	dot_timer.stop()
	waiting_label.visible = false
	waiting_label.modulate.a = 1.0
	waiting_blur.visible = false
	waiting_blur.modulate.a = 1.0

func _on_dot_timer_timeout() -> void:
	dot_count = (dot_count % 3) + 1
	waiting_label.text = BASE_WAIT_TEXT + ".".repeat(dot_count)

func send_game_data(json: String) -> void:
	if appPlugin:
		appPlugin.updateGameData(json)
	else:
		print("No app plugin (local test): ", json)

func _load_game_specific_settings() -> void:
	var saved_volume: float = float(SettingsManager.get_setting(game_settings_category, "master_volume", 0.75))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(saved_volume))
	var show_debug_info: bool = bool(SettingsManager.get_setting(game_settings_category, "show_debug_info", false))
	print("Loaded game-specific settings for ", game_settings_category, ": volume=", saved_volume, " debug=", show_debug_info)

func _get_music_stream() -> AudioStream: return null
func _get_dev_data() -> String: return ""
func _on_game_ready() -> void: pass
func _set_game_data(_json: String) -> void: pass
func _add_settings_rows(_container, _popup_script) -> void: pass
func _get_settings_avatar_display(): return get_node_or_null("%PlayerAvatarDisplay")
func _get_rules_title() -> String: return ""
func _get_rules_text() -> String: return ""

@warning_ignore("unused_parameter")
func _on_theme_changed(new_theme_name: String) -> void: pass
