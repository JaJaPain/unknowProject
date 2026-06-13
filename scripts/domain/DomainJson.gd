class_name DomainJson
extends RefCounted

const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)


static func parse_object(text: String, source: String = "<memory>") -> Dictionary:
	var result := ValidationResultType.new()
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		result.add_error(
			"invalid_json",
			"%s at line %d in %s." % [
				parser.get_error_message(),
				parser.get_error_line(),
				source,
			]
		)
		return {"data": {}, "validation": result}

	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		result.add_error(
			"root_not_object",
			"JSON root in %s must be an object." % source
		)
		return {"data": {}, "validation": result}

	return {
		"data": (parsed as Dictionary).duplicate(true),
		"validation": result,
	}


static func read_object(path: String) -> Dictionary:
	var result := ValidationResultType.new()
	if not FileAccess.file_exists(path):
		result.add_error("file_not_found", "Definition file not found.", path)
		return {"data": {}, "validation": result}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.add_error("file_unreadable", "Definition file is unreadable.", path)
		return {"data": {}, "validation": result}
	return parse_object(file.get_as_text(), path)


static func stringify(data: Dictionary, pretty: bool = true) -> String:
	return JSON.stringify(data, "\t" if pretty else "")


static func deep_copy(data: Dictionary) -> Dictionary:
	var parsed := parse_object(stringify(data, false))
	var validation := parsed["validation"] as ValidationResult
	if not validation.is_valid():
		return {}
	return parsed["data"]
