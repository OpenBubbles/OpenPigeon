class_name ChessDebug
extends RefCounted

## Chess debug and logging utilities.
## Provides configurable log levels for debugging chess game flow.

## Log level enumeration (ordered by severity)
enum LogLevel {
	TRACE = 0,    ## Most verbose - detailed execution flow
	DEBUG = 1,    ## Debug information - variable states, decisions
	INFO = 2,     ## General information - game events, moves
	WARNING = 3,  ## Warnings - unexpected but recoverable situations
	ERROR = 4,    ## Errors - failures that affect game functionality
	NONE = 5      ## Disable all logging
}

## Current log level (only messages at or above this level are logged)
## Default to INFO in production builds to avoid string formatting overhead
static var current_level: LogLevel = LogLevel.INFO

## Prefix for all chess log messages
const LOG_PREFIX: String = "CHESS"
const OP_LOG_TAG: String = "Chess"
static var route_to_op_log: bool = true

## Enable/disable timestamps in log output
static var show_timestamps: bool = false

## Enable/disable function context in log output
static var show_context: bool = true

## Set the current log level
static func set_level(level: LogLevel) -> void:
	current_level = level

## Get the current log level
static func get_level() -> LogLevel:
	return current_level

## Check if a log level is enabled
static func is_enabled(level: LogLevel) -> bool:
	return level >= current_level

## Get log level name for display
static func level_name(level: LogLevel) -> String:
	match level:
		LogLevel.TRACE: return "TRACE"
		LogLevel.DEBUG: return "DEBUG"
		LogLevel.INFO: return "INFO"
		LogLevel.WARNING: return "WARN"
		LogLevel.ERROR: return "ERROR"
		LogLevel.NONE: return "NONE"
	return "???"
	
static func _get_op_log() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null

	var tree := loop as SceneTree
	if tree.root == null:
		return null

	return tree.root.get_node_or_null("/root/OpLog")

## Internal logging implementation
static func _log(level: LogLevel, message: String, context: String = "") -> void:
	if level < current_level:
		return

	var parts: Array[String] = []

	if show_timestamps:
		var time: Dictionary = Time.get_time_dict_from_system()
		parts.append("[%02d:%02d:%02d]" % [time.hour, time.minute, time.second])

	parts.append("[%s:%s]" % [LOG_PREFIX, level_name(level)])

	if show_context and context != "":
		parts.append("[%s]" % context)

	parts.append(message)

	var line := " ".join(parts)

	if route_to_op_log:
		var op_log := _get_op_log()
		if op_log != null:
			match level:
				LogLevel.TRACE, LogLevel.DEBUG:
					if op_log.has_method("d"):
						op_log.call("d", OP_LOG_TAG, line)
						return
				LogLevel.INFO:
					if op_log.has_method("i"):
						op_log.call("i", OP_LOG_TAG, line)
						return
				LogLevel.WARNING:
					if op_log.has_method("w"):
						op_log.call("w", OP_LOG_TAG, line)
						return
				LogLevel.ERROR:
					if op_log.has_method("e"):
						op_log.call("e", OP_LOG_TAG, line)
						return

	if level >= LogLevel.ERROR:
		printerr(line)
	else:
		print(line)

## Log a TRACE level message (most verbose)
static func trace(message: String, context: String = "") -> void:
	_log(LogLevel.TRACE, message, context)

## Log a DEBUG level message
static func debug(message: String, context: String = "") -> void:
	_log(LogLevel.DEBUG, message, context)

## Log an INFO level message
static func info(message: String, context: String = "") -> void:
	_log(LogLevel.INFO, message, context)

## Log a WARNING level message
static func warn(message: String, context: String = "") -> void:
	_log(LogLevel.WARNING, message, context)

## Log an ERROR level message
static func error(message: String, context: String = "") -> void:
	_log(LogLevel.ERROR, message, context)

## Log arbitrary state dictionary for debugging
static func state(tag: String, state_dict: Dictionary, context: String = "") -> void:
	if not is_enabled(LogLevel.DEBUG):
		return

	var parts: PackedStringArray = []
	for key in state_dict.keys():
		parts.append("%s=%s" % [key, str(state_dict[key])])

	var msg: String = "[%s] %s" % [tag, ", ".join(parts)]
	debug(msg, context)

## Log chess game state for debugging (standardized format)
## This is a convenience method that logs the most important chess state variables.
static func game_state(tag: String, game_data: Dictionary, context: String = "") -> void:
	if not is_enabled(LogLevel.DEBUG):
		return

	# Expected keys: turn, my_color, local_mode, isTurn, waitingForOpponent,
	#                fullmove, halfmove, castling, en_passant, game_over, reason
	var parts: PackedStringArray = []

	# Order matters for readability - most important first
	var ordered_keys: Array[String] = [
		"turn", "my_color", "local_mode", "isTurn", "waitingForOpponent",
		"fullmove", "halfmove", "castling", "en_passant", "game_over", "reason"
	]

	for key in ordered_keys:
		if game_data.has(key):
			parts.append("%s=%s" % [key, str(game_data[key])])

	# Include any extra keys not in the ordered list
	for key in game_data.keys():
		if key not in ordered_keys:
			parts.append("%s=%s" % [key, str(game_data[key])])

	var msg: String = "[%s] %s" % [tag, ", ".join(parts)]
	debug(msg, context)

## Convenience method to log with automatic context from caller
## Note: GDScript doesn't support stack introspection, so context must be passed manually

## Create a scoped logger with a fixed context
class ScopedLogger:
	var _context: String

	func _init(context: String) -> void:
		_context = context

	func trace(message: String) -> void:
		ChessDebug.trace(message, _context)

	func debug(message: String) -> void:
		ChessDebug.debug(message, _context)

	func info(message: String) -> void:
		ChessDebug.info(message, _context)

	func warn(message: String) -> void:
		ChessDebug.warn(message, _context)

	func error(message: String) -> void:
		ChessDebug.error(message, _context)

	## Log arbitrary state dictionary with this logger's context
	func state(tag: String, state_dict: Dictionary) -> void:
		ChessDebug.state(tag, state_dict, _context)

	## Log chess game state with this logger's context
	func game_state(tag: String, game_data: Dictionary) -> void:
		ChessDebug.game_state(tag, game_data, _context)
