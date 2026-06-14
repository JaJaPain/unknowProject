class_name ShipDesignDefinition
extends DomainDefinition

const SUPPORTED_SCHEMA_VERSION := 1

var display_name := ""
var faction_id: StringName
var role := ""
var asset_path := ""
var fallback_asset_path := ""


func load_from_dict(data: Dictionary) -> ValidationResult:
	var result := load_common(data, "ship_design", SUPPORTED_SCHEMA_VERSION)
	display_name = str(data.get("display_name", ""))
	faction_id = StringName() if str(data.get("faction_id", "")).is_empty() else DomainId.canonicalize(data["faction_id"])
	role = str(data.get("role", ""))
	asset_path = str(data.get("asset_path", ""))
	fallback_asset_path = str(data.get("fallback_asset_path", ""))
	if display_name.is_empty() or role.is_empty():
		result.add_error("missing_ship_field", "Ship display_name and role are required.")
	if not faction_id.is_empty():
		var faction_error := DomainId.validation_error(faction_id, "faction")
		if not faction_error.is_empty():
			result.add_error("invalid_reference", faction_error, "faction_id")
	if not ResourceLoader.exists(asset_path):
		result.add_error("asset_not_found", "Ship asset does not exist.", "asset_path")
	if not fallback_asset_path.is_empty() and not ResourceLoader.exists(fallback_asset_path):
		result.add_error("fallback_not_found", "Ship fallback asset does not exist.", "fallback_asset_path")
	return result
