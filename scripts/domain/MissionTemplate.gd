class_name MissionTemplate
extends RefCounted

var template_id: String = ""
var objective_type: String = ""
var source_lane: String = ""
var tone_card: String = ""
var required_placeholders: Array[String] = []
var write_fields: Array[String] = []
var field_limits: Dictionary = {}
var forbidden_words: Array[String] = []
var fallback_variants: Array[Dictionary] = []
var custom_rules: Array[String] = []


static func create(config: Dictionary) -> MissionTemplate:
	var t := MissionTemplate.new()
	t.template_id = str(config.get("template_id", ""))
	t.objective_type = str(config.get("objective_type", ""))
	t.source_lane = str(config.get("source_lane", ""))
	t.tone_card = str(config.get("tone_card", ""))
	for p in config.get("required_placeholders", []):
		t.required_placeholders.append(str(p))
	for f in config.get("write_fields", []):
		t.write_fields.append(str(f))
	t.field_limits = config.get("field_limits", {}).duplicate(true)
	for w in config.get("forbidden_words", []):
		t.forbidden_words.append(str(w))
	for v in config.get("fallback_variants", []):
		t.fallback_variants.append(v.duplicate(true))
	for r in config.get("custom_rules", []):
		t.custom_rules.append(str(r))
	return t


func get_field_limit(field: String) -> int:
	return int(field_limits.get(field, 220))


func has_rule(rule: String) -> bool:
	return rule in custom_rules
