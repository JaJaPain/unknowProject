class_name PortraitDefinition
extends RefCounted

var id: StringName
var sheet_id: StringName
var source_path := ""
var bounds := Rect2()
var tags: Array[String] = []


func load_from_dict(data: Dictionary, owner_id: StringName, path: String) -> ValidationResult:
	var result := ValidationResult.new()
	id = DomainId.canonicalize(data.get("id", ""))
	sheet_id = owner_id
	source_path = path
	var error := DomainId.validation_error(id, "portrait")
	if not error.is_empty():
		result.add_error("invalid_id", error, "id")
	var raw: Dictionary = data.get("bounds", {})
	bounds = Rect2(raw.get("x", 0), raw.get("y", 0), raw.get("width", 0), raw.get("height", 0))
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		result.add_error("invalid_bounds", "Portrait bounds must be positive.", "bounds")
	for tag in data.get("tags", []):
		tags.append(str(tag))
	return result


func texture() -> AtlasTexture:
	var source := load(source_path) as Texture2D
	if source == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = bounds
	return atlas
