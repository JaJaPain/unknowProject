class_name MissionShapeDefinition
extends DomainDefinition

## One investigation shape: an objective composed with a complication and a
## closed set of terminal branches (plan P2).
##
## A shape is EXECUTABLE CONTENT, not a model-authored script. The model supplies
## bounded dialogue around it and never decides what the player may do, what is
## true at a site, or what a branch pays. Everything here is validated on load and
## a broken shape is rejected outright rather than partially applied -- a shape
## that half-loads would hand the player a contract with unreachable branches.

const SUPPORTED_SCHEMA_VERSION := 1

## The four recipes are a closed enum because dispatch is a match, not a lookup.
## Adding a fifth is a code change by design.
const VALID_RECIPES: Array[String] = [
	"survey_discrepancy",
	"competing_claims",
	"transmitter_lure",
	"unstable_archive",
]

## Every branch any recipe may terminate on. Kept here so a typo in the data is
## an error at load rather than a branch the player can never select.
const VALID_BRANCHES: Array[String] = [
	"report",
	"certify_match",
	"certify_mismatch",
	"preserve",
	"liquidate",
	"extract",
	"stabilize",
	"reconstruct",
]

var recipe := ""
var objective_type := ""
var display_name := ""
var preview := ""
var requires_second_site := true
var can_spawn_hostile := false
var branch_ids: Array[String] = []
var requires_flags: Array[String] = []
var weight := 1


func load_from_dict(data: Dictionary) -> ValidationResult:
	var result := load_common(data, "mission_shape", SUPPORTED_SCHEMA_VERSION)
	recipe = str(data.get("recipe", "")).strip_edges()
	objective_type = str(data.get("objective_type", "")).strip_edges()
	display_name = str(data.get("display_name", "")).strip_edges()
	preview = str(data.get("preview", "")).strip_edges()
	requires_second_site = bool(data.get("requires_second_site", true))
	can_spawn_hostile = bool(data.get("can_spawn_hostile", false))
	weight = int(data.get("weight", 1))

	branch_ids = _string_list(data.get("branch_ids", []))
	requires_flags = _string_list(data.get("requires_flags", []))

	if recipe not in VALID_RECIPES:
		result.add_error(
			"invalid_recipe",
			"Recipe must be one of %s, got '%s'." % [str(VALID_RECIPES), recipe],
			"recipe"
		)
	if objective_type != "INVESTIGATE_SIGNAL":
		result.add_error(
			"invalid_objective_type",
			"Investigation shapes must use INVESTIGATE_SIGNAL.",
			"objective_type"
		)
	if display_name.is_empty():
		result.add_error("missing_display_name", "A shape needs a display name.", "display_name")
	if branch_ids.is_empty():
		result.add_error("missing_branches", "A shape needs at least one branch.", "branch_ids")
	# "report" is always available after the first scan, so a missing consumable
	# can never strand a contract. A shape without it is a soft-lock waiting to
	# happen, so it is an error rather than a warning.
	if not branch_ids.has("report"):
		result.add_error(
			"missing_report_branch",
			"Every shape must offer 'report' so a missing consumable cannot strand it.",
			"branch_ids"
		)
	for branch in branch_ids:
		if branch not in VALID_BRANCHES:
			result.add_error(
				"unknown_branch",
				"Branch '%s' is not dispatchable." % branch,
				"branch_ids"
			)
	if branch_ids.size() != _unique_count(branch_ids):
		result.add_error("duplicate_branch", "Branch ids must be unique.", "branch_ids")
	if weight < 1:
		result.add_error("invalid_weight", "Weight must be at least 1.", "weight")
	return result


func _string_list(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if not raw is Array:
		return out
	for value in (raw as Array):
		var text := str(value).strip_edges()
		if not text.is_empty():
			out.append(text)
	return out


func _unique_count(values: Array[String]) -> int:
	var seen: Dictionary = {}
	for value in values:
		seen[value] = true
	return seen.size()
