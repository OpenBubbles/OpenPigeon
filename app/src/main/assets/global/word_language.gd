class_name WordLanguage
extends RefCounted

const DEFAULT_LANGUAGE := "en"
const DICTIONARY_DIRECTORY := "res://global/dictionaries"

const DICTIONARY_FILE_OVERRIDES := {
	#"en": "op_wg_en2.txt"
}

const LANGUAGE_NAMES := {
	"en": "English",
	"es": "Español",
	"fr": "Français",
	"it": "Italiano",
	"ru": "Русский",
	"de": "Deutsch",
	"pt": "Português"
}


static func normalize_code(value: String) -> String:
	var code := value.strip_edges().to_lower()
	code = code.replace("_", "-")

	# Accept regional language codes such as en-US, es-MX, or pt-BR.
	if code.contains("-"):
		code = code.get_slice("-", 0)

	match code:
		"english", "eng":
			return "en"

		"spanish", "espanol", "español", "spa":
			return "es"

		"french", "francais", "français", "fra", "fre":
			return "fr"

		"italian", "italiano", "ita":
			return "it"

		"russian", "русский", "rus":
			return "ru"

		"german", "deutsch", "deu", "ger":
			return "de"

		"portuguese", "portugues", "português", "por":
			return "pt"

	if code.length() == 2 or code.length() == 3:
		return code

	return DEFAULT_LANGUAGE


static func _dictionary_filename_for_code(code: String) -> String:
	if DICTIONARY_FILE_OVERRIDES.has(code):
		return String(DICTIONARY_FILE_OVERRIDES[code])

	return "op_wg_%s.txt" % code


static func _candidate_dictionary_path(code: String) -> String:
	return DICTIONARY_DIRECTORY.path_join(
		_dictionary_filename_for_code(code)
	)


static func resolve_code(value: String) -> String:
	var normalized := normalize_code(value)
	var candidate_path := _candidate_dictionary_path(normalized)

	if FileAccess.file_exists(candidate_path):
		return normalized

	return DEFAULT_LANGUAGE


static func get_dictionary_path(value: String) -> String:
	var resolved := resolve_code(value)
	var dictionary_path := _candidate_dictionary_path(resolved)

	if FileAccess.file_exists(dictionary_path):
		return dictionary_path

	# This should only occur when even the bundled English dictionary
	# is missing.
	return _candidate_dictionary_path(DEFAULT_LANGUAGE)


static func get_display_name(value: String) -> String:
	var resolved := resolve_code(value)

	if LANGUAGE_NAMES.has(resolved):
		return String(LANGUAGE_NAMES[resolved])

	return resolved.to_upper()


static func dictionary_exists(value: String) -> bool:
	var normalized := normalize_code(value)

	return FileAccess.file_exists(
		_candidate_dictionary_path(normalized)
	)


static func normalize_word(value: String) -> String:
	return value.strip_edges().to_upper()
