extends Node

var _logger = null
var _ready_checked := false

func _ensure_logger() -> void:
	if _ready_checked:
		return

	_ready_checked = true

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
