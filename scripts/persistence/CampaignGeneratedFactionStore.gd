class_name CampaignGeneratedFactionStore
extends RefCounted

const DomainIdType := preload("res://scripts/domain/DomainId.gd")
const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const TransactionStoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const DOCUMENT_VERSION := 1
const FACTIONS_PATH := "generated_factions.json"
const GENERATED_PREFIX := "faction.generated."
const BADGE_METADATA_PATH := "res://tools/ship_generator/textures/badges/badge_sheets_metadata.json"

var campaign_path: String
var campaign: Dictionary = {}
var data: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> CampaignGeneratedFactionStore:
	var store := CampaignGeneratedFactionStore.new()
	store.campaign_path = path.trim_suffix("/")
	store._load_or_create()
	return store


func is_valid() -> bool:
	return validation.is_valid()


func all_factions() -> Array:
	return (data.get("factions", []) as Array).duplicate(true)


func faction_ids() -> Array[String]:
	var ids: Array[String] = []
	for faction in all_factions():
		if faction is Dictionary:
			ids.append(str(faction.get("id", "")))
	return ids


func revealed_faction_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in data.get("revealed_faction_ids", []):
		ids.append(str(id))
	return ids


func unrevealed_factions() -> Array:
	var revealed := {}
	for id in revealed_faction_ids():
		revealed[id] = true
	var output: Array = []
	for faction in all_factions():
		if faction is Dictionary and not revealed.has(str(faction.get("id", ""))):
			output.append((faction as Dictionary).duplicate(true))
	return output


func revealed_factions() -> Array:
	var revealed := {}
	for id in revealed_faction_ids():
		revealed[id] = true
	var output: Array = []
	for faction in all_factions():
		if faction is Dictionary and revealed.has(str(faction.get("id", ""))):
			output.append((faction as Dictionary).duplicate(true))
	return output


func factions_by_ids(ids: Array) -> Array:
	var wanted := {}
	for id in ids:
		wanted[str(id)] = true
	var output: Array = []
	for faction in all_factions():
		if faction is Dictionary and wanted.has(str(faction.get("id", ""))):
			output.append((faction as Dictionary).duplicate(true))
	return output


func ensure_frontier_batch(seed_text: String, count: int = 6) -> Dictionary:
	if not is_valid():
		return _failure("Generated faction store is invalid.")
	if not all_factions().is_empty():
		return {"ok": true, "created": 0, "factions": all_factions()}
	var created: Array = []
	for index in range(max(count, 0)):
		created.append(_generate_faction(seed_text, index))
	var prepared := data.duplicate(true)
	prepared["factions"] = created
	var committed := _commit(prepared, "generated_factions_bootstrap_batch")
	if not bool(committed.get("ok", false)):
		return committed
	data = prepared
	return {"ok": true, "created": created.size(), "factions": created.duplicate(true)}


func reveal_next_for_system(system_id: String, count: int = 2) -> Dictionary:
	if not is_valid():
		return _failure("Generated faction store is invalid.")
	var revealed := revealed_faction_ids()
	var revealed_lookup := {}
	for id in revealed:
		revealed_lookup[id] = true
	var newly_revealed: Array[String] = []
	for faction in all_factions():
		if newly_revealed.size() >= count:
			break
		if not faction is Dictionary:
			continue
		var faction_id := str(faction.get("id", ""))
		if faction_id.is_empty() or revealed_lookup.has(faction_id):
			continue
		newly_revealed.append(faction_id)
		revealed_lookup[faction_id] = true
	if newly_revealed.is_empty():
		return {"ok": true, "revealed": [], "revealed_faction_ids": revealed}
	var prepared := data.duplicate(true)
	var next_revealed := revealed.duplicate()
	next_revealed.append_array(newly_revealed)
	prepared["revealed_faction_ids"] = next_revealed
	var history: Array = prepared.get("reveal_history", [])
	history.append({
		"system_id": system_id,
		"faction_ids": newly_revealed,
		"time_msec": Time.get_ticks_msec(),
	})
	prepared["reveal_history"] = history
	var committed := _commit(prepared, "generated_factions_reveal")
	if not bool(committed.get("ok", false)):
		return committed
	data = prepared
	return {
		"ok": true,
		"revealed": newly_revealed,
		"revealed_faction_ids": next_revealed,
	}


func prompt_context(revealed_only: bool = false) -> String:
	if not is_valid() or data.is_empty():
		return ""
	var source: Array = all_factions()
	if revealed_only:
		var revealed := {}
		for id in revealed_faction_ids():
			revealed[id] = true
		source = source.filter(func(item: Variant) -> bool:
			return item is Dictionary and revealed.has(str(item.get("id", "")))
		)
	if source.is_empty():
		return ""
	var lines: Array[String] = ["Generated frontier factions:"]
	for faction in source:
		if not faction is Dictionary:
			continue
		var voice_style: Dictionary = (
			faction.get("voice_style", {}) as Dictionary
			if faction.get("voice_style", {}) is Dictionary
			else {}
		)
		var mission_preferences: Dictionary = (
			faction.get("mission_preferences", {}) as Dictionary
			if faction.get("mission_preferences", {}) is Dictionary
			else {}
		)
		lines.append(
			"- %s (%s): %s; wants %s; taboo: %s; humor: %s; voice: %s; missions: %s" %
			[
				str(faction.get("display_name", "")),
				str(faction.get("abbreviation", "")),
				str(faction.get("ideology", "")),
				str(faction.get("business_model", "")),
				str(faction.get("taboo", "")),
				str(faction.get("humor_style", "")),
				str(voice_style.get("delivery", "")),
				", ".join(_string_array(
					mission_preferences.get("preferred_types", [])
				)),
			]
		)
	return "\n".join(lines)


func _load_or_create() -> void:
	var campaign_result := DomainJsonType.read_object(
		"%s/campaign.json" % campaign_path
	)
	validation.merge(campaign_result["validation"], "campaign")
	if not validation.is_valid():
		return
	campaign = campaign_result["data"]
	var campaign_id := str(campaign.get("id", ""))
	if not DomainIdType.is_valid(campaign_id, "campaign"):
		validation.add_error(
			"invalid_campaign_id",
			"Generated factions require a valid campaign id.",
			"campaign.id"
		)
		return
	var factions_path := "%s/%s" % [campaign_path, FACTIONS_PATH]
	if not FileAccess.file_exists(factions_path):
		data = _default_document(campaign_id, str(campaign.get("campaign_seed", "")))
		var committed := _commit(data, "generated_factions_bootstrap")
		if not bool(committed.get("ok", false)):
			validation.add_error(
				"generated_factions_bootstrap_failed",
				str(committed.get("error", "Generated factions could not be created.")),
				FACTIONS_PATH
			)
		return
	var factions_result := DomainJsonType.read_object(factions_path)
	validation.merge(factions_result["validation"], "generated_factions")
	if not validation.is_valid():
		return
	data = factions_result["data"]
	validation.merge(_validate_data(data, campaign_id), "generated_factions")


func _commit(next_data: Dictionary, operation: String) -> Dictionary:
	return TransactionStoreType.commit_json_set(
		campaign_path,
		operation,
		{FACTIONS_PATH: next_data},
		FACTIONS_PATH,
		func(_path: String, value: Dictionary) -> ValidationResult:
			return _validate_data(value, str(campaign.get("id", "")))
	)


static func _default_document(campaign_id: String, campaign_seed: String) -> Dictionary:
	return {
		"schema_version": DOCUMENT_VERSION,
		"document_type": "generated_factions",
		"campaign_id": campaign_id,
		"campaign_seed": campaign_seed,
		"source": "procedural_bootstrap",
		"factions": [],
		"revealed_faction_ids": [],
		"reveal_history": [],
	}


static func _generate_faction(seed_text: String, index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|generated_faction|%d" % [seed_text, index]).hash()
	var prefixes := ["Ash", "Glass", "Null", "Rust", "Signal", "Cinder", "Vow", "Latch"]
	var nouns := ["Choir", "Ledger", "Wake", "Covenant", "Foundry", "Index", "Parish", "Drift"]
	var descriptors := ["Salvage Compact", "Claims Office", "Pilgrim Fleet", "Security Lease", "Courier Union"]
	var ideologies := [
		"ownership through recovery",
		"contracts above blood",
		"survival by silence",
		"public mercy with private knives",
		"debt as citizenship",
	]
	var businesses := ["salvage rights", "gate tolls", "ore futures", "escort bonds", "black-box auctions"]
	var taboos := ["wasting air", "free repairs", "unlogged favors", "unmasked command", "joking about maps"]
	var humor := ["dry gallows wit", "bureaucratic absurdism", "deadpan threats", "cheerful fatalism", "dad jokes under fire"]
	var voice_deliveries := ["quiet clipped threats", "warm legalese", "raspy dockside sermons", "bright courier patter", "slow ceremonial calm"]
	var voice_tempos := ["slow", "measured", "brisk", "urgent"]
	var mission_sets := [
		["PICKUP_SPECIAL", "DELIVER_ORE"],
		["KILL_SHIPS", "PICKUP_SPECIAL"],
		["DELIVER_ORE", "KILL_SHIPS"],
		["PICKUP_SPECIAL", "KILL_SHIPS", "DELIVER_ORE"],
	]
	var textures := ["metal.png", "NavyBlueMetal.png", "ForestGreenMetal.png", "RedMetal.png"]
	var emblems := ["none", "ZenithBadge.png", "AurelliaBadge.png", "VanguardBadge.png"]
	var badges := _badge_options()
	var badge: Dictionary = (
		badges[rng.randi() % badges.size()]
		if not badges.is_empty()
		else {"id": "badge.generated.%02d" % (index + 1), "file": "", "main_color": ""}
	)
	var name := "%s %s" % [
		prefixes[rng.randi() % prefixes.size()],
		nouns[rng.randi() % nouns.size()],
	]
	var slug := name.to_lower().replace(" ", "_")
	var hue := rng.randf()
	var color := Color.from_hsv(hue, rng.randf_range(0.45, 0.75), rng.randf_range(0.65, 0.95))
	return {
		"id": "%s%s_%02d" % [GENERATED_PREFIX, slug, index],
		"legacy_id": "gen_%s_%02d" % [slug, index],
		"display_name": name,
		"abbreviation": _abbreviation(name),
		"classification": "generated",
		"descriptor": descriptors[rng.randi() % descriptors.size()],
		"ideology": ideologies[rng.randi() % ideologies.size()],
		"business_model": businesses[rng.randi() % businesses.size()],
		"taboo": taboos[rng.randi() % taboos.size()],
		"humor_style": humor[rng.randi() % humor.size()],
		"voice_style": {
			"profile_hint": "voice.generated.%s.v1" % slug,
			"delivery": voice_deliveries[rng.randi() % voice_deliveries.size()],
			"tempo": voice_tempos[rng.randi() % voice_tempos.size()],
			"pitch_bias": snapped(rng.randf_range(-0.08, 0.08), 0.01),
		},
		"mission_preferences": {
			"preferred_types": mission_sets[rng.randi() % mission_sets.size()],
			"target_bias": ["minor_hostile", "rival_faction"],
			"risk_tolerance": ["low", "medium", "high"][rng.randi() % 3],
		},
		"badge_id": str(badge.get("id", "")),
		"badge_source": {
			"metadata_path": BADGE_METADATA_PATH,
			"sheet_file": str(badge.get("file", "")),
			"main_color": str(badge.get("main_color", "")),
		},
		"ship_style": {
			"texture": textures[rng.randi() % textures.size()],
			"emblem": emblems[rng.randi() % emblems.size()],
			"metallic_min": 0.55,
			"metallic_max": 0.95,
		},
		"ui_color": [color.r, color.g, color.b, 1.0],
		"relationship_hooks": [],
		"revealed": false,
	}


static func _validate_data(value: Dictionary, campaign_id: String) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(value.get("schema_version", 0)) != DOCUMENT_VERSION:
		result.add_error(
			"invalid_generated_factions_version",
			"Generated factions schema version is invalid.",
			"schema_version"
		)
	if str(value.get("document_type", "")) != "generated_factions":
		result.add_error(
			"invalid_generated_factions_type",
			"Generated factions document type is invalid.",
			"document_type"
		)
	if str(value.get("campaign_id", "")) != campaign_id:
		result.add_error(
			"generated_factions_campaign_mismatch",
			"Generated factions belong to a different campaign.",
			"campaign_id"
		)
	if not value.get("factions", []) is Array:
		result.add_error("invalid_factions", "Generated factions must be an array.", "factions")
	if not value.get("revealed_faction_ids", []) is Array:
		result.add_error(
			"invalid_revealed_faction_ids",
			"Revealed faction IDs must be an array.",
			"revealed_faction_ids"
		)
	var seen := {}
	for index in range((value.get("factions", []) as Array).size()):
		var faction: Variant = value["factions"][index]
		if not faction is Dictionary:
			result.add_error("invalid_faction_record", "Faction record must be an object.", "factions.%d" % index)
			continue
		_validate_faction(faction, result, "factions.%d" % index, seen)
	for id in value.get("revealed_faction_ids", []):
		if not seen.has(str(id)):
			result.add_error(
				"unknown_revealed_faction",
				"Revealed faction ID is not in generated faction records.",
				"revealed_faction_ids"
			)
	return result


static func _validate_faction(
	faction: Dictionary,
	result: ValidationResult,
	path: String,
	seen: Dictionary
) -> void:
	var faction_id := str(faction.get("id", ""))
	if not DomainIdType.is_valid(faction_id, "faction"):
		result.add_error("invalid_faction_id", "Generated faction ID is invalid.", "%s.id" % path)
	elif not faction_id.begins_with(GENERATED_PREFIX):
		result.add_error("invalid_generated_prefix", "Generated faction ID must use generated prefix.", "%s.id" % path)
	elif seen.has(faction_id):
		result.add_error("duplicate_generated_faction", "Generated faction ID is duplicated.", "%s.id" % path)
	else:
		seen[faction_id] = true
	for field in [
		"legacy_id",
		"display_name",
		"abbreviation",
		"descriptor",
		"ideology",
		"business_model",
		"taboo",
		"humor_style",
		"badge_id",
	]:
		if str(faction.get(field, "")).strip_edges().is_empty():
			result.add_error("missing_generated_faction_field", "Generated faction field is required.", "%s.%s" % [path, field])
	if not faction.get("ship_style", {}) is Dictionary:
		result.add_error("invalid_ship_style", "Generated faction ship_style must be an object.", "%s.ship_style" % path)
	var voice_style = faction.get("voice_style", {})
	if not voice_style is Dictionary:
		result.add_error("invalid_voice_style", "Generated faction voice_style must be an object.", "%s.voice_style" % path)
	else:
		for field in ["profile_hint", "delivery", "tempo"]:
			if str((voice_style as Dictionary).get(field, "")).strip_edges().is_empty():
				result.add_error("missing_voice_style_field", "Generated faction voice_style field is required.", "%s.voice_style.%s" % [path, field])
	var mission_preferences = faction.get("mission_preferences", {})
	if not mission_preferences is Dictionary:
		result.add_error("invalid_mission_preferences", "Generated faction mission_preferences must be an object.", "%s.mission_preferences" % path)
	else:
		if not (mission_preferences as Dictionary).get("preferred_types", []) is Array:
			result.add_error("invalid_preferred_mission_types", "Generated faction preferred_types must be an array.", "%s.mission_preferences.preferred_types" % path)
		elif ((mission_preferences as Dictionary).get("preferred_types", []) as Array).is_empty():
			result.add_error("missing_preferred_mission_types", "Generated faction preferred_types cannot be empty.", "%s.mission_preferences.preferred_types" % path)
	if not faction.get("badge_source", {}) is Dictionary:
		result.add_error("invalid_badge_source", "Generated faction badge_source must be an object.", "%s.badge_source" % path)
	if not faction.get("ui_color", []) is Array or (faction.get("ui_color", []) as Array).size() != 4:
		result.add_error("invalid_ui_color", "Generated faction ui_color must have four values.", "%s.ui_color" % path)


static func _abbreviation(name: String) -> String:
	var letters := ""
	for part in name.split(" ", false):
		letters += part.substr(0, 1).to_upper()
	return letters.left(4)


static func _badge_options() -> Array:
	var parsed := DomainJsonType.read_object(BADGE_METADATA_PATH)
	var validation := parsed["validation"] as ValidationResult
	if not validation.is_valid():
		return []
	var data: Dictionary = parsed["data"]
	var output: Array = []
	for sheet in data.get("sheets", []):
		if not sheet is Dictionary:
			continue
		var sheet_file := str(sheet.get("file", ""))
		for sprite in sheet.get("sprites", []):
			if not sprite is Dictionary:
				continue
			var badge_id := str(sprite.get("id", "")).strip_edges()
			if badge_id.is_empty():
				continue
			output.append({
				"id": badge_id,
				"file": sheet_file,
				"main_color": str(sprite.get("mainColor", "")),
			})
	return output


static func _string_array(values: Variant) -> Array[String]:
	var output: Array[String] = []
	if not values is Array:
		return output
	for value in values:
		output.append(str(value))
	return output


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
