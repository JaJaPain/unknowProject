class_name MissionShapeRegistry
extends RefCounted

## Loads and validates the investigation shape catalog (plan P2).
##
## Rejects a broken catalog wholesale rather than partially applying it: a
## half-loaded catalog would let the selector draw a shape whose branches cannot
## be dispatched, and the player would meet that as a contract they cannot
## finish. Export validation and development startup both call `load_from_path`
## and treat a failure as fatal.

const CATALOG_PATH := "res://data/content/mission_shapes.json"
const SUPPORTED_CATALOG_VERSION := 1

const ValidationResultType := preload("res://scripts/domain/ValidationResult.gd")
const MissionShapeDefinitionType := preload(
	"res://scripts/domain/MissionShapeDefinition.gd"
)

var shapes: Dictionary = {}          # StringName id -> MissionShapeDefinition
var loaded := false


func load_from_path(path: String = CATALOG_PATH) -> Variant:
	var result = ValidationResultType.new()
	shapes = {}
	loaded = false
	if not FileAccess.file_exists(path):
		result.add_error("missing_catalog", "No shape catalog at %s." % path, path)
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.add_error("unreadable_catalog", "Could not open %s." % path, path)
		return result
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return load_from_dict(parsed if parsed is Dictionary else {}, result)


func load_from_dict(data: Dictionary, result: Variant = null) -> Variant:
	var out = result if result != null else ValidationResultType.new()
	if data.is_empty():
		out.add_error("invalid_catalog", "Shape catalog is not a JSON object.")
		return out
	var version := int(data.get("version", 0))
	if version != SUPPORTED_CATALOG_VERSION:
		out.add_error(
			"unsupported_catalog_version",
			"Catalog version %d is not supported (expected %d)." % [
				version, SUPPORTED_CATALOG_VERSION
			],
			"version"
		)
	var raw_shapes = data.get("shapes", [])
	if not raw_shapes is Array or (raw_shapes as Array).is_empty():
		out.add_error("no_shapes", "Catalog lists no shapes.", "shapes")
		return out

	var by_recipe: Dictionary = {}
	var staged: Dictionary = {}
	for entry in (raw_shapes as Array):
		if not entry is Dictionary:
			out.add_error("invalid_shape_entry", "Shape entries must be objects.", "shapes")
			continue
		var shape = MissionShapeDefinitionType.new()
		var shape_result = shape.load_from_dict(entry as Dictionary)
		out.merge(shape_result, "shapes/%s" % str((entry as Dictionary).get("id", "?")))
		if not shape_result.is_valid():
			continue
		if staged.has(shape.id):
			out.add_error("duplicate_shape_id", "Shape id %s appears twice." % shape.id, "shapes")
			continue
		# One shape per recipe: dispatch is a closed match on recipe, so two
		# shapes claiming the same one would make selection ambiguous.
		if by_recipe.has(shape.recipe):
			out.add_error(
				"duplicate_recipe",
				"Recipe '%s' is claimed by both %s and %s." % [
					shape.recipe, str(by_recipe[shape.recipe]), str(shape.id)
				],
				"shapes"
			)
			continue
		by_recipe[shape.recipe] = shape.id
		staged[shape.id] = shape

	if not out.is_valid():
		return out
	shapes = staged
	loaded = true
	return out


func get_shape(id: Variant) -> Variant:
	return shapes.get(StringName(str(id)), null)


func shape_for_recipe(recipe: String) -> Variant:
	for shape in shapes.values():
		if str(shape.recipe) == recipe:
			return shape
	return null


## Shapes whose required story flags are all set. Eligibility is filtered BEFORE
## a selection pool is formed, never by skipping draws inside one -- skipping
## inside a cycle silently breaks the no-repeat guarantee.
func eligible_shapes(story_flags: Dictionary) -> Array:
	var out: Array = []
	for shape in shapes.values():
		var definition = shape
		var ok := true
		for flag in definition.requires_flags:
			if not bool(story_flags.get(flag, false)):
				ok = false
				break
		if ok:
			out.append(definition)
	out.sort_custom(func(a, b): return str(a.id) < str(b.id))
	return out
