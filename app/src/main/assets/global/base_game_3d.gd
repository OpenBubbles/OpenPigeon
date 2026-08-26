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
var _rules_open := false

var spectator_mode: bool = false
var dot_count: int = 0
var game_settings_category: String = ""
var _startup_cover: CanvasLayer
var _startup_reveal_queued: bool = false
var _startup_revealed: bool = false
var _turn_retry_ui: Dictionary = {}
var _send_check_serial: int = 0

func _create_startup_cover() -> void:
	_startup_cover = CanvasLayer.new()
	_startup_cover.name = "StartupCover"
	_startup_cover.layer = 1000
	add_child(_startup_cover)

	var cover := ColorRect.new()
	cover.name = "Cover"
	cover.color = Color.BLACK
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_startup_cover.add_child(cover)
	cover.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT,
	)


func _receive_game_data(json: String) -> void:
	_set_game_data(json)
	_queue_startup_reveal()


func _queue_startup_reveal() -> void:
	if _startup_revealed or _startup_reveal_queued:
		return

	_startup_reveal_queued = true
	call_deferred("_reveal_startup_after_layout")


func _reveal_startup_after_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	if not is_inside_tree():
		return

	_startup_revealed = true

	if is_instance_valid(_startup_cover):
		_startup_cover.visible = false
		_startup_cover.queue_free()
		_startup_cover = null

func _ready() -> void:
	_create_startup_cover()

	if Engine.has_singleton("OpenPigeonMedia"):
		mediaPlugin = Engine.get_singleton("OpenPigeonMedia")

	GameUtils.start_music(
		self,
		_get_music_stream(),
		mediaPlugin,
	)

	if (
		is_instance_valid(settings_button) and
		not settings_button.pressed.is_connected(
			_on_settings_button_pressed,
		)
	):
		settings_button.pressed.connect(
			_on_settings_button_pressed,
		)

	if (
		is_instance_valid(rules_button) and
		not rules_button.pressed.is_connected(
			_on_rules_button_pressed,
		)
	):
		rules_button.pressed.connect(
			_on_rules_button_pressed,
		)

	if (
		is_instance_valid(dot_timer) and
		not dot_timer.timeout.is_connected(
			_on_dot_timer_timeout,
		)
	):
		dot_timer.timeout.connect(
			_on_dot_timer_timeout,
		)

	if Engine.has_singleton("AppPlugin"):
		appPlugin = Engine.get_singleton("AppPlugin")
	else:
		appPlugin = null
	
	if appPlugin:
		_turn_retry_ui = GameUtils.create_send_retry_overlay(
			self,
			Callable(
				self,
				"_retry_saved_send"
			)
		)

		if appPlugin.has_signal(
			"send_game_complete"
		):
			appPlugin.connect(
				"send_game_complete",
				Callable(
					self,
					"_on_send_game_complete"
				)
			)

		if appPlugin.has_signal(
			"send_game_failed"
		):
			appPlugin.connect(
				"send_game_failed",
				Callable(
					self,
					"_on_send_game_failed"
				)
			)

	if appPlugin:
		var receive_callable := Callable(
			self,
			"_receive_game_data",
		)

		if not appPlugin.is_connected(
			"set_game_data",
			receive_callable,
		):
			appPlugin.connect(
				"set_game_data",
				receive_callable,
			)

		my_uuid = appPlugin.getSenderUUID()
	else:
		my_uuid = DEV_UUID

	_on_game_ready()

	if appPlugin:
		appPlugin.onReady()
		call_deferred(
			"_refresh_turn_recovery_state"
		)
	else:
		var dev := _get_dev_data()

		if dev != "":
			_receive_game_data(dev)
		else:
			_queue_startup_reveal()

func _exit_tree() -> void:
	SettingsManager.suppress_avatar_changed = false
	GameUtils.stop_music(self)

func _on_settings_button_pressed() -> void:
	if _settings_open:
		return

	_settings_open = true
	SettingsManager.suppress_avatar_changed = spectator_mode

	GameUtils.open_settings_popup(
		self,
		mediaPlugin,
		settings_button,
		null if spectator_mode else _get_settings_avatar_display(),
		_get_music_stream(),
		Callable(self, "_settings_rows_hook"),
		func():
			SettingsManager.suppress_avatar_changed = false
			_settings_open = false
			_on_settings_dark_mode_changed(bool(SettingsManager.get_setting("global", "dark_mode", false)))
	)

func _settings_rows_hook(container, popup_script) -> void:
	_connect_settings_dark_mode(popup_script)
	_add_settings_rows(container, popup_script)

func _connect_settings_dark_mode(popup) -> void:
	if not is_instance_valid(popup) or not popup.has_signal("dark_mode_changed"):
		push_warning("BaseGame3D: settings popup missing dark_mode_changed")
		return

	var handler := Callable(self, "_on_settings_dark_mode_changed")

	if not popup.is_connected("dark_mode_changed", handler):
		popup.connect("dark_mode_changed", handler)

func _on_settings_dark_mode_changed(is_dark: bool) -> void:
	if has_method("_apply_bg_for_dark"):
		call("_apply_bg_for_dark", is_dark)

func _on_rules_button_pressed() -> void:
	if _rules_open:
		return

	_rules_open = true

	GameUtils.open_rules_popup(
		self,
		rules_button,
		_get_rules_title(),
		_get_rules_text(),
		func():
			_rules_open = false
	)

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
	if not appPlugin:
		print(
			"No app plugin (local test): ",
			json
		)
		return

	var dispatched: bool = bool(
		appPlugin.updateGameData(
			json
		)
	)

	if not dispatched:
		_show_send_retry(
			false
		)
		return

	_send_check_serial += 1

	_check_pending_send_after_delay(
		_send_check_serial
	)

func save_turn_progress(
	data: Dictionary
) -> void:
	if not appPlugin:
		return

	appPlugin.saveTurnProgress(
		JSON.stringify(
			data
		)
	)


func get_saved_turn_progress() -> Dictionary:
	if not appPlugin:
		return {}

	var raw: String = String(
		appPlugin.getTurnProgress()
	)

	if raw.is_empty():
		return {}

	var parsed: Variant = JSON.parse_string(
		raw
	)

	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed

	return {}


func has_pending_send() -> bool:
	return (
		appPlugin != null and
		bool(
			appPlugin.hasPendingSend()
		)
	)


func _refresh_turn_recovery_state() -> void:
	if has_pending_send():
		_show_send_retry(
			false
		)
	else:
		_hide_send_retry()


func _retry_saved_send() -> void:
	if not appPlugin:
		return

	_show_send_retry(
		true
	)

	var dispatched: bool = bool(
		appPlugin.retryPendingSend()
	)

	if not dispatched:
		_show_send_retry(
			false
		)
		return

	_send_check_serial += 1

	_check_pending_send_after_delay(
		_send_check_serial
	)


func _on_send_game_complete() -> void:
	_send_check_serial += 1
	_hide_send_retry()


func _on_send_game_failed() -> void:
	_send_check_serial += 1
	_show_send_retry(
		false
	)


func _show_send_retry(
	sending: bool
) -> void:
	GameUtils.set_send_retry_overlay_state(
		_turn_retry_ui,
		true,
		sending
	)


func _hide_send_retry() -> void:
	GameUtils.set_send_retry_overlay_state(
		_turn_retry_ui,
		false,
		false
	)


func _check_pending_send_after_delay(
	serial: int
) -> void:
	await get_tree().create_timer(
		8.0
	).timeout

	if serial != _send_check_serial:
		return

	if has_pending_send():
		_show_send_retry(
			false
		)

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
