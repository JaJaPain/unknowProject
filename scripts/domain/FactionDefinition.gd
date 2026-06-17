class_name FactionDefinition
extends DomainDefinition

const SUPPORTED_SCHEMA_VERSION := 1

var legacy_id := ""
var display_name := ""
var classification := ""
var descriptor := ""
var abbreviation := ""
var agent_npc_id: StringName
var agent_portrait_id: StringName
var voice_profile_id: StringName
var ship_family := ""
var ui_color := Color.WHITE
var projectile_color := Color.WHITE
var hull_tint := Color.WHITE


func load_from_dict(data: Dictionary) -> ValidationResult:
	var result := load_common(data, "faction", SUPPORTED_SCHEMA_VERSION)
	legacy_id = str(data.get("legacy_id", ""))
	display_name = str(data.get("display_name", "")).strip_edges()
	classification = str(data.get("classification", ""))
	descriptor = str(data.get("descriptor", ""))
	abbreviation = str(data.get("abbreviation", ""))
	agent_npc_id = _optional_id(data.get("agent_npc_id", ""))
	agent_portrait_id = _optional_id(data.get("agent_portrait_id", ""))
	voice_profile_id = _optional_id(data.get("voice_profile_id", ""))
	ship_family = str(data.get("ship_family", ""))
	ui_color = _color(data.get("ui_color", []), result, "ui_color")
	projectile_color = _color(
		data.get("projectile_color", []), result, "projectile_color"
	)
	hull_tint = _color(data.get("hull_tint", [1, 1, 1, 1]), result, "hull_tint")
	if legacy_id.is_empty() or display_name.is_empty():
		result.add_error("missing_identity", "Faction legacy_id and display_name are required.")
	if classification not in ["major", "minor"]:
		result.add_error("invalid_classification", "Faction must be major or minor.", "classification")
	for pair in [
		[agent_npc_id, "npc", "agent_npc_id"],
		[agent_portrait_id, "portrait", "agent_portrait_id"],
		[voice_profile_id, "voice", "voice_profile_id"],
	]:
		if pair[0].is_empty():
			continue
		var error := DomainId.validation_error(pair[0], pair[1])
		if not error.is_empty():
			result.add_error("invalid_reference", error, pair[2])
	return result


static func _optional_id(value: Variant) -> StringName:
	return StringName() if str(value).is_empty() else DomainId.canonicalize(value)


static func _color(value: Variant, result: ValidationResult, path: String) -> Color:
	if not value is Array or value.size() != 4:
		result.add_error("invalid_color", "Color must contain four numbers.", path)
		return Color.WHITE
	return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
