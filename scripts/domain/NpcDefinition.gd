class_name NpcDefinition
extends DomainDefinition

const SUPPORTED_SCHEMA_VERSION := 1

var display_name := ""
var faction_id: StringName
var role_tags: Array[String] = []
var portrait_id: StringName
var voice_profile_id: StringName
var importance := "minor"
var protected := false
var location_id: StringName
var presentation_color := Color.WHITE


func load_from_dict(data: Dictionary) -> ValidationResult:
	var result := load_common(data, "npc", SUPPORTED_SCHEMA_VERSION)
	display_name = str(data.get("display_name", "")).strip_edges()
	faction_id = _optional_id(data.get("faction_id", ""))
	portrait_id = DomainId.canonicalize(data.get("portrait_id", ""))
	voice_profile_id = DomainId.canonicalize(data.get("voice_profile_id", ""))
	location_id = DomainId.canonicalize(data.get("location_id", ""))
	importance = str(data.get("importance", "minor"))
	protected = bool(data.get("protected", false))
	for tag in data.get("role_tags", []):
		role_tags.append(str(tag))
	var color: Array = data.get("presentation_color", [])
	if color.size() == 4:
		presentation_color = Color(color[0], color[1], color[2], color[3])
	else:
		result.add_error("invalid_color", "presentation_color must contain four numbers.")
	if display_name.is_empty():
		result.add_error("missing_display_name", "NPC display_name is required.")
	for pair in [
		[portrait_id, "portrait", "portrait_id"],
		[voice_profile_id, "voice", "voice_profile_id"],
		[location_id, "station", "location_id"],
	]:
		var error := DomainId.validation_error(pair[0], pair[1])
		if not error.is_empty():
			result.add_error("invalid_reference", error, pair[2])
	if not faction_id.is_empty():
		var faction_error := DomainId.validation_error(faction_id, "faction")
		if not faction_error.is_empty():
			result.add_error("invalid_reference", faction_error, "faction_id")
	return result


static func _optional_id(value: Variant) -> StringName:
	return StringName() if str(value).is_empty() else DomainId.canonicalize(value)
