class_name CharacterDirector
extends RefCounted

const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")

const TRAIT_PATH := "res://data/content/character_trait_axes.json"
const SUPPORTED_SCHEMA_VERSION := 1
const PERSONA_FIELDS := [
	"core_drive",
	"current_want",
	"fear",
	"contradiction",
	"social_strategy",
	"pressure_tell",
	"kindness_tell",
	"verbal_habit",
	"humor_mechanism",
	"taboo",
]


static func generate_card(
	npc_source: Dictionary,
	campaign_seed: String,
	recent_combinations: Array = []
) -> Dictionary:
	var registry := _load_registry()
	if not bool(registry.get("ok", false)):
		return registry
	var npc_id := str(npc_source.get("id", npc_source.get("source_key", ""))).strip_edges()
	if npc_id.is_empty():
		return {"ok": false, "error": "NPC source requires id or source_key."}
	var selected := _select_traits(
		registry,
		"%s|%s" % [campaign_seed, npc_id],
		recent_combinations
	)
	var persona := _persona_from_selection(npc_source, selected)
	return {
		"ok": true,
		"card": {
			"persona": persona,
			"voice_rules": _voice_rules_from_selection(registry, npc_source, selected),
			"trait_combination_key": _combination_key(selected),
			"trait_memory_keys": _memory_keys(selected),
		},
	}


static func is_complete_card(card: Dictionary) -> bool:
	var persona: Dictionary = card.get("persona", {}) \
		if card.get("persona", {}) is Dictionary else {}
	for field in PERSONA_FIELDS:
		if str(persona.get(field, "")).strip_edges().is_empty():
			return false
	var voice_rules: Dictionary = card.get("voice_rules", {}) \
		if card.get("voice_rules", {}) is Dictionary else {}
	if str(voice_rules.get("sentence_shape", "")).strip_edges().is_empty():
		return false
	if str(voice_rules.get("address_rule", "")).strip_edges().is_empty():
		return false
	if not voice_rules.get("favored_vocabulary", []) is Array:
		return false
	if (voice_rules.get("favored_vocabulary", []) as Array).is_empty():
		return false
	if not voice_rules.get("banned_tics", []) is Array:
		return false
	return true


static func _load_registry() -> Dictionary:
	var parsed := DomainJsonType.read_object(TRAIT_PATH)
	if not parsed["validation"].is_valid():
		return {
			"ok": false,
			"error": parsed["validation"].summary(),
		}
	var data: Dictionary = parsed["data"]
	if int(data.get("schema_version", 0)) != SUPPORTED_SCHEMA_VERSION:
		return {"ok": false, "error": "Unsupported character trait schema version."}
	return {"ok": true, "data": data}


static func _select_traits(
	registry_result: Dictionary,
	key: String,
	recent_combinations: Array
) -> Dictionary:
	var data: Dictionary = registry_result.get("data", {})
	var axes: Dictionary = data.get("axes", {}) if data.get("axes", {}) is Dictionary else {}
	var selected := {}
	for axis in axes.keys():
		var values: Array = axes[axis] if axes[axis] is Array else []
		if values.is_empty():
			continue
		selected[str(axis)] = str(values[_hash_index("%s|%s" % [key, axis], values.size())])
	var attempts := 0
	var retry_limit := _recent_memory_retry_limit(axes)
	while (_is_incompatible(selected, data) or _recently_used(selected, recent_combinations)) \
			and attempts < retry_limit:
		attempts += 1
		for axis in selected.keys():
			var values: Array = axes[axis] if axes[axis] is Array else []
			if values.is_empty():
				continue
			selected[axis] = str(values[_hash_index(
				"%s|%s|retry.%d" % [key, axis, attempts],
				values.size()
			)])
	return selected


static func _persona_from_selection(
	npc_source: Dictionary,
	selected: Dictionary
) -> Dictionary:
	var role := str(npc_source.get("job_role", "local contact")).strip_edges()
	if role.is_empty():
		role = "local contact"
	var current_want := str(npc_source.get("current_want", "")).strip_edges()
	if current_want.is_empty():
		current_want = "Resolve the current %s pressure without losing control of the room." % role
	return {
		"core_drive": str(selected.get("core_drive", "")),
		"current_want": current_want,
		"fear": str(selected.get("fear", "")),
		"contradiction": str(selected.get("contradiction", "")),
		"social_strategy": str(selected.get("social_strategy", "")),
		"pressure_tell": str(selected.get("pressure_tell", "")),
		"kindness_tell": str(selected.get("kindness_tell", "")),
		"verbal_habit": "Frames trouble through %s work without turning it into a catchphrase." % role,
		"humor_mechanism": str(selected.get("humor_mechanism", "")),
		"taboo": "Does not joke about decompression deaths or civilian casualties.",
	}


static func _voice_rules_from_selection(
	registry_result: Dictionary,
	npc_source: Dictionary,
	selected: Dictionary
) -> Dictionary:
	var data: Dictionary = registry_result.get("data", {})
	var rules: Dictionary = data.get("voice_rules", {}) \
		if data.get("voice_rules", {}) is Dictionary else {}
	var seed := _combination_key(selected)
	var sentence_shapes: Array = rules.get("sentence_shapes", []) \
		if rules.get("sentence_shapes", []) is Array else []
	var address_rules: Array = rules.get("address_rules", []) \
		if rules.get("address_rules", []) is Array else []
	var vocab_sets: Array = rules.get("favored_vocabulary", []) \
		if rules.get("favored_vocabulary", []) is Array else []
	var vocabulary: Array = []
	if not vocab_sets.is_empty():
		var picked = vocab_sets[_hash_index("%s|vocab" % seed, vocab_sets.size())]
		if picked is Array:
			for item in picked:
				vocabulary.append(str(item))
	var banned := []
	var banned_source: Array = rules.get("banned_tics", []) \
		if rules.get("banned_tics", []) is Array else []
	for item in banned_source:
		banned.append(str(item))
	return {
		"sentence_shape": _pick_text(sentence_shapes, "%s|sentence" % seed),
		"address_rule": _pick_text(address_rules, "%s|address" % seed),
		"favored_vocabulary": vocabulary if not vocabulary.is_empty() else ["station", "work", "pressure"],
		"banned_tics": banned if not banned.is_empty() else ["Shiny"],
	}


static func _pick_text(values: Array, key: String) -> String:
	if values.is_empty():
		return "plain, specific, grounded"
	return str(values[_hash_index(key, values.size())])


static func _is_incompatible(selected: Dictionary, data: Dictionary) -> bool:
	var rules: Array = data.get("incompatibilities", []) \
		if data.get("incompatibilities", []) is Array else []
	for rule in rules:
		if not rule is Dictionary:
			continue
		var matches := true
		for field in (rule as Dictionary).keys():
			if str(selected.get(field, "")) != str((rule as Dictionary).get(field, "")):
				matches = false
				break
		if matches:
			return true
	return false


static func _recently_used(selected: Dictionary, recent_combinations: Array) -> bool:
	if _combination_key(selected) in recent_combinations:
		return true
	for key in _memory_keys(selected):
		if key in recent_combinations:
			return true
	return false


static func _recent_memory_retry_limit(axes: Dictionary) -> int:
	var humor_count := _axis_value_count(axes, "humor_mechanism")
	var contradiction_count := _axis_value_count(axes, "contradiction")
	return maxi(16, humor_count * contradiction_count * 8)


static func _axis_value_count(axes: Dictionary, axis: String) -> int:
	var values: Array = axes.get(axis, []) if axes.get(axis, []) is Array else []
	return maxi(1, values.size())


static func _combination_key(selected: Dictionary) -> String:
	var keys := selected.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append("%s=%s" % [str(key), str(selected[key])])
	return "|".join(parts)


static func _memory_keys(selected: Dictionary) -> Array[String]:
	var keys: Array[String] = [_combination_key(selected)]
	for field in ["humor_mechanism", "contradiction"]:
		var value := str(selected.get(field, "")).strip_edges()
		if not value.is_empty():
			keys.append("%s=%s" % [field, value])
	return keys


static func _hash_index(key: String, count: int) -> int:
	if count <= 0:
		return 0
	var hex := key.sha256_text().substr(0, 8)
	return hex.hex_to_int() % count
