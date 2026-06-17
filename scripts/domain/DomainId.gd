class_name DomainId
extends RefCounted

const _AUTHORED_PATTERN := "^[a-z0-9_]+(?:\\.[a-z0-9_]+)+$"
const _GENERATED_MARKER := "gen"

const LEGACY_ALIASES: Dictionary = {
	"start_system": "system.start",
	"test_system": "system.test",
	"start_to_test": "gate.start.to_test",
	"test_to_start": "gate.test.to_start",
	"zenith": "faction.zenith",
	"aurelia": "faction.aurelia",
	"vanguard": "faction.vanguard",
}

static var _authored_regex: RegEx


static func canonicalize(value: Variant) -> StringName:
	var raw := str(value)
	return StringName(str(LEGACY_ALIASES.get(raw, raw)))


static func is_valid(value: Variant, expected_namespace: String = "") -> bool:
	return validation_error(value, expected_namespace).is_empty()


static func validation_error(
	value: Variant,
	expected_namespace: String = ""
) -> String:
	var raw := str(value).strip_edges()
	if raw.is_empty():
		return "ID cannot be empty."
	if raw != str(value):
		return "ID cannot contain leading or trailing whitespace."
	if not _get_authored_regex().search(raw):
		return (
			"ID '%s' must contain lowercase ASCII dot-separated segments "
			+ "using only a-z, 0-9, and underscore."
		) % raw
	if not expected_namespace.is_empty() and namespace_of(raw) != expected_namespace:
		return "ID '%s' must use the '%s' namespace." % [
			raw,
			expected_namespace,
		]
	return ""


static func namespace_of(value: Variant) -> String:
	var raw := str(value)
	var separator := raw.find(".")
	if separator <= 0:
		return ""
	return raw.substr(0, separator)


static func is_generated(value: Variant) -> bool:
	var segments := str(value).split(".")
	return segments.size() >= 4 and segments[1] == _GENERATED_MARKER


static func build_generated(
	id_namespace: String,
	campaign_key: String,
	creation_key: String
) -> StringName:
	var generated := "%s.%s.%s.%s" % [
		id_namespace,
		_GENERATED_MARKER,
		campaign_key,
		creation_key,
	]
	if not is_valid(generated, id_namespace):
		return StringName()
	return StringName(generated)


static func _get_authored_regex() -> RegEx:
	if _authored_regex == null:
		_authored_regex = RegEx.new()
		var error := _authored_regex.compile(_AUTHORED_PATTERN)
		if error != OK:
			push_error("[DomainId] Failed to compile ID validation pattern.")
	return _authored_regex
