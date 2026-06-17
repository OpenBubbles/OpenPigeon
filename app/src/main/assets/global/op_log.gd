extends Node

var _logger = null
var _last_title_key := ""
var _last_title_ms := 0
var _bridge_logged := false
var _logger_name := ""

func _ensure_logger() -> void:
	if _logger != null:
		return

	if Engine.has_singleton("OpenPigeonLog"):
		_logger = Engine.get_singleton("OpenPigeonLog")
		_logger_name = "OpenPigeonLog"
	elif Engine.has_singleton("OpenPigeonGodotLog"):
		_logger = Engine.get_singleton("OpenPigeonGodotLog")
		_logger_name = "OpenPigeonGodotLog"
	elif Engine.has_singleton("AppPlugin"):
		_logger = Engine.get_singleton("AppPlugin")
		_logger_name = "AppPlugin"

func _message(parts: Variant) -> String:
	if parts is Array:
		var text := ""
		for part in parts:
			text += str(part)
		return text

	return str(parts)

func _fallback(level: String, tag: String, text: String) -> void:
	match level:
		"E", "ERROR":
			printerr("[ERROR:%s] %s" % [tag, text])
		"W", "WARN", "WARNING":
			print("[WARN:%s] %s" % [tag, text])
		"EVENT":
			print("[EVENT:%s] %s" % [tag, text])
		_:
			print("[%s] %s" % [tag, text])

func _send(level: String, tag: String, parts: Variant) -> void:
	_ensure_logger()

	var text := _message(parts)

	if _logger:
		if _logger_name == "AppPlugin":
			_logger.call("log", level, tag, text)
			return

		if _logger.has_method("godotLog"):
			_logger.call("godotLog", level, tag, text)
			return

		match level:
			"D", "DEBUG":
				if _logger.has_method("godotD"):
					_logger.call("godotD", tag, text)
					return

			"I", "INFO":
				if _logger.has_method("godotI"):
					_logger.call("godotI", tag, text)
					return

			"W", "WARN", "WARNING":
				if _logger.has_method("godotW"):
					_logger.call("godotW", tag, text)
					return

			"E", "ERROR":
				if _logger.has_method("godotE"):
					_logger.call("godotE", tag, text)
					return

			"EVENT":
				if _logger.has_method("godotEvent"):
					_logger.call("godotEvent", tag, text)
					return

	_fallback(level, tag, text)

func d(tag: String, parts: Variant) -> void:
	_send("D", tag, parts)

func i(tag: String, parts: Variant) -> void:
	_send("I", tag, parts)

func w(tag: String, parts: Variant) -> void:
	_send("W", tag, parts)

func e(tag: String, parts: Variant) -> void:
	_send("E", tag, parts)

func event(tag: String, parts: Variant) -> void:
	_send("EVENT", tag, parts)

func title(tag: String, title_text: String, parts: Variant = "") -> void:
	var now := Time.get_ticks_msec()
	var key := tag + "|" + title_text

	if key == _last_title_key and now - _last_title_ms < 1000:
		return

	_last_title_key = key
	_last_title_ms = now

	var detail := _message(parts)
	var stamp := Time.get_datetime_string_from_system(false, true)

	event(tag, "============================================================")
	if detail.is_empty():
		event(tag, ["GAME OPENED: ", title_text, " | ", stamp])
	else:
		event(tag, ["GAME OPENED: ", title_text, " | ", stamp, " | ", detail])
	event(tag, "============================================================")

func game_opened(game_name: String, parts: Variant = "") -> void:
	title(game_name, game_name, parts)

func bridge_test() -> void:
	_ensure_logger()

	var singleton_names := PackedStringArray()
	for name in Engine.get_singleton_list():
		singleton_names.append(str(name))

	var found := _logger != null

	_fallback("EVENT", "OpLog", "bridge_test loggerFound=%s loggerName=%s singletons=%s" % [
		found,
		_logger_name,
		",".join(singleton_names)
	])

	if found:
		_send("EVENT", "DiagSelfTest", [
			"GODOT_BRIDGE_CALL_TEST loggerName=", _logger_name,
			" ticks=", Time.get_ticks_msec()
		])
	else:
		_fallback("EVENT", "DiagSelfTest", "GODOT_BRIDGE_NO_LOGGER")
