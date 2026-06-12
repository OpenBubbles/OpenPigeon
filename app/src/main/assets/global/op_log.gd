extends Node

var _logger = null
var _last_title_key := ""
var _last_title_ms := 0

func _ensure_logger() -> void:
	if _logger != null:
		return

	if Engine.has_singleton("OpenPigeonLog"):
		_logger = Engine.get_singleton("OpenPigeonLog")
	elif Engine.has_singleton("AppPlugin"):
		_logger = Engine.get_singleton("AppPlugin")

func _message(parts: Variant) -> String:
	if parts is Array:
		var text := ""
		for part in parts:
			text += str(part)
		return text

	return str(parts)

func d(tag: String, parts: Variant) -> void:
	_ensure_logger()
	var text := _message(parts)

	if _logger and _logger.has_method("d"):
		_logger.d(tag, text)
	else:
		print("[%s] %s" % [tag, text])

func i(tag: String, parts: Variant) -> void:
	_ensure_logger()
	var text := _message(parts)

	if _logger and _logger.has_method("i"):
		_logger.i(tag, text)
	else:
		print("[%s] %s" % [tag, text])

func w(tag: String, parts: Variant) -> void:
	_ensure_logger()
	var text := _message(parts)

	if _logger and _logger.has_method("w"):
		_logger.w(tag, text)
	else:
		print("[WARN:%s] %s" % [tag, text])

func e(tag: String, parts: Variant) -> void:
	_ensure_logger()
	var text := _message(parts)

	if _logger and _logger.has_method("e"):
		_logger.e(tag, text)
	else:
		printerr("[ERROR:%s] %s" % [tag, text])

func event(tag: String, parts: Variant) -> void:
	_ensure_logger()
	var text := _message(parts)

	if _logger and _logger.has_method("event"):
		_logger.event(tag, text)
	else:
		print("[EVENT:%s] %s" % [tag, text])

func title(tag: String, title_text: String, parts: Variant = "") -> void:
	var now := Time.get_ticks_msec()
	var key := tag + "|" + title_text

	# Prevent duplicate title blocks if _ready/_on_game_ready fires twice quickly.
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
