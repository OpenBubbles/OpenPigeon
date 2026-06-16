extends Node

var _logger = null
var _last_title_key := ""
var _last_title_ms := 0
var _bridge_logged := false

func _ensure_logger() -> void:
	if _logger != null:
		return

	if Engine.has_singleton("OpenPigeonLog"):
		_logger = Engine.get_singleton("OpenPigeonLog")
	elif Engine.has_singleton("OpenPigeonGodotLog"):
		_logger = Engine.get_singleton("OpenPigeonGodotLog")
	elif Engine.has_singleton("AppPlugin"):
		_logger = Engine.get_singleton("AppPlugin")

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
		# Preferred bridge: routes through OpenPigeonLog.godotLog(),
		# which sanitizes, prefixes Godot tags, and adds to diagnostic entries.
		if _logger.has_method("godotLog"):
			_logger.call("godotLog", level, tag, text)
			return

		match level:
			"D", "DEBUG":
				if _logger.has_method("godotD"):
					_logger.call("godotD", tag, text)
					return
				if _logger.has_method("d"):
					_logger.call("d", tag, text)
					return

			"I", "INFO":
				if _logger.has_method("godotI"):
					_logger.call("godotI", tag, text)
					return
				if _logger.has_method("i"):
					_logger.call("i", tag, text)
					return

			"W", "WARN", "WARNING":
				if _logger.has_method("godotW"):
					_logger.call("godotW", tag, text)
					return
				if _logger.has_method("w"):
					_logger.call("w", tag, text)
					return

			"E", "ERROR":
				if _logger.has_method("godotE"):
					_logger.call("godotE", tag, text)
					return
				if _logger.has_method("e"):
					_logger.call("e", tag, text)
					return

			"EVENT":
				if _logger.has_method("godotEvent"):
					_logger.call("godotEvent", tag, text)
					return
				if _logger.has_method("event"):
					_logger.call("event", tag, text)
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

	event("OpLog", [
		"bridge_test loggerFound=", _logger != null,
		" loggerMethods=",
		" godotLog=", _logger != null and _logger.has_method("godotLog"),
		" godotEvent=", _logger != null and _logger.has_method("godotEvent"),
		" i=", _logger != null and _logger.has_method("i"),
		" event=", _logger != null and _logger.has_method("event"),
		" singletons=", ",".join(singleton_names)
	])
