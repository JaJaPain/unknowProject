class_name MissionDefinition
extends DomainDefinition

const SUPPORTED_SCHEMA_VERSION := 1
const ObjectiveType := preload(
	"res://scripts/domain/MissionObjectiveDefinition.gd"
)
const RewardType := preload(
	"res://scripts/domain/MissionRewardDefinition.gd"
)
const TimingType := preload(
	"res://scripts/domain/MissionTimingDefinition.gd"
)
const NarrativeMetadataType := preload(
	"res://scripts/domain/NarrativeMetadata.gd"
)

var title: String = ""
var faction_id: StringName
var giver_npc_id: StringName
var dialogue: String = ""
var objective: MissionObjectiveDefinition
var reward: MissionRewardDefinition
var timing: MissionTimingDefinition
var choices: Array = []
var narrative_metadata: Dictionary = {}


func load_from_offer(source: Dictionary) -> ValidationResult:
	var normalized := source.duplicate(true)
	if str(normalized.get("id", "")).is_empty():
		normalized["id"] = derive_offer_id(source)
	if not normalized.has("schema_version"):
		normalized["schema_version"] = SUPPORTED_SCHEMA_VERSION
	var result := load_common(
		normalized,
		"mission",
		SUPPORTED_SCHEMA_VERSION
	)
	result.merge(
		NarrativeMetadataType.validate_source(source),
		"narrative_metadata"
	)

	title = str(source.get("title", "")).strip_edges()
	if title.is_empty():
		result.add_error("missing_title", "Mission title cannot be empty.", "title")
	dialogue = str(source.get("dialogue", ""))

	var legacy_faction := str(source.get("faction", "")).strip_edges()
	faction_id = (
		&"faction.neutral"
		if legacy_faction == "neutral"
		else DomainIdType.canonicalize(legacy_faction)
	)
	if not DomainIdType.is_valid(faction_id, "faction"):
		result.add_error(
			"invalid_faction",
			"Mission faction '%s' is not a valid faction ID." % legacy_faction,
			"faction"
		)

	giver_npc_id = _derive_giver_id(
		str(source.get("agent_name", "")),
		legacy_faction
	)
	if not DomainIdType.is_valid(giver_npc_id, "npc"):
		result.add_error(
			"invalid_giver",
			"Mission giver could not be assigned a stable NPC ID.",
			"agent_name"
		)

	var raw_objective: Variant = source.get("objective", null)
	objective = ObjectiveType.new()
	if not raw_objective is Dictionary:
		result.add_error(
			"missing_objective",
			"Mission objective must be an object.",
			"objective"
		)
	else:
		result.merge(
			objective.load_from_dict(raw_objective as Dictionary),
			"objective"
		)

	reward = RewardType.new()
	if raw_objective is Dictionary:
		result.merge(
			reward.load_from_objective(raw_objective as Dictionary),
			"reward"
		)

	timing = TimingType.new()
	var raw_timing: Variant = source.get("timing", {})
	if not raw_timing is Dictionary:
		result.add_error(
			"invalid_timing",
			"Mission timing must be an object.",
			"timing"
		)
	else:
		result.merge(timing.load_from_dict(raw_timing as Dictionary), "timing")

	var raw_choices: Variant = source.get("choices", [])
	if not raw_choices is Array:
		result.add_error(
			"invalid_choices",
			"Mission choices must be an array.",
			"choices"
		)
	else:
		choices = (raw_choices as Array).duplicate(true)
	narrative_metadata = NarrativeMetadataType.from_source(source)
	return result


func to_dict() -> Dictionary:
	var result := to_common_dict()
	result.merge({
		"title": title,
		"faction_id": str(faction_id),
		"giver_npc_id": str(giver_npc_id),
		"dialogue": dialogue,
		"objective": objective.to_dict() if objective else {},
		"reward": reward.to_dict() if reward else {},
		"timing": timing.to_dict() if timing else {},
		"choices": choices.duplicate(true),
		"narrative_metadata": narrative_metadata.duplicate(true),
	})
	return result


static func derive_offer_id(source: Dictionary) -> String:
	var objective: Variant = source.get("objective", {})
	var identity_source := JSON.stringify({
		"title": str(source.get("title", "")),
		"faction": str(source.get("faction", "")),
		"agent_name": str(source.get("agent_name", "")),
		"objective": objective,
	})
	return "mission.offer.%s" % identity_source.sha256_text().substr(0, 16)


static func _derive_giver_id(agent_name: String, legacy_faction: String) -> StringName:
	match agent_name.strip_edges().to_lower():
		"broker kaelen":
			return &"npc.kaelen"
		"director voss":
			return &"npc.agent.zenith"
		"liaison ryn":
			return &"npc.agent.aurelia"
		"captain dask":
			return &"npc.agent.vanguard"
		"jenna kross":
			return &"npc.jenna_kross"
	if not legacy_faction.is_empty() and legacy_faction != "neutral":
		return StringName("npc.agent.%s" % legacy_faction)
	var digest := agent_name.to_lower().sha256_text().substr(0, 12)
	return StringName("npc.legacy.%s" % digest)
