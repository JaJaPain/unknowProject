class_name MissionTextGenerator
extends RefCounted

const KAELEN_AUTHORSHIP_BLOCKLIST: Array[String] = [
	"i posted",
	"my posting",
	"my job",
	"i arranged",
	"i set this up",
	"my contract",
]

const KAELEN_DISGUST_CUES: Array[String] = [
	"slumming",
	"public board",
	"public-board",
	"stain",
	"stains",
	"smell",
	"grime",
	"scrape",
	"desperate",
	"standards",
	"dumpster",
	"gutter",
]


static func build_generation_request(
	template: MissionTemplate,
	offer: Dictionary,
	critique: String = ""
) -> Dictionary:
	var facts := _facts_for_prompt(offer)
	var prompt := template.tone_card
	if template.source_lane == "BOARD":
		var spice: String = MissionTemplateRegistry.BOARD_SPICE[
			randi() % MissionTemplateRegistry.BOARD_SPICE.size()
		]
		prompt += "Creative seed for this particular posting: " + spice + "\n"
	if not template.required_placeholders.is_empty():
		prompt += "Required placeholders: " + ", ".join(template.required_placeholders) + "\n"
	prompt += "Facts you must obey:\n" + facts + "\n"
	if template.has_rule(MissionTemplateRegistry.KAELEN_DISGUST_RULE):
		prompt += (
			"Kaelen turn-in rule: Kaelen may process payout, but she did not post this job. "
			+ "She should sound visibly grossed out that the player is slumming it on public-board work.\n"
		)
	if not critique.strip_edges().is_empty():
		prompt += "\nSELF-CRITIQUE: previous output failed because " + critique
	return {
		"template_id": template.template_id,
		"prompt": prompt,
		"format": "json",
		"required_placeholders": template.required_placeholders.duplicate(),
		"fields": template.write_fields.duplicate(),
	}


static func validate_payload(
	template: MissionTemplate,
	offer: Dictionary,
	payload: Dictionary
) -> Dictionary:
	if not payload is Dictionary:
		return _invalid("payload is not a dictionary")
	for field in template.write_fields:
		var value := str(payload.get(field, "")).strip_edges()
		if value.is_empty():
			return _invalid("missing field '%s'" % field)
		if value.length() > template.get_field_limit(field):
			return _invalid("field '%s' is too long (%d > %d)" % [
				field, value.length(), template.get_field_limit(field),
			])
	var combined := ""
	for field in template.write_fields:
		combined += "\n" + str(payload.get(field, ""))
	for placeholder in template.required_placeholders:
		if not combined.contains(placeholder):
			return _invalid("missing placeholder %s" % placeholder)
	var lower := combined.to_lower()
	for word in template.forbidden_words:
		if lower.contains(word):
			return _invalid("invented unsupported mechanic '%s'" % word)
	if template.has_rule(MissionTemplateRegistry.NO_DROP_PERCENT_RULE):
		if combined.contains("%"):
			return _invalid("recovery posting exposed hidden drop percentage")
	if template.has_rule(MissionTemplateRegistry.KAELEN_DISGUST_RULE):
		var result := _validate_kaelen(payload)
		if not bool(result.get("ok", false)):
			return result
	return {"ok": true, "reason": ""}


static func fallback_payload(
	template: MissionTemplate,
	offer: Dictionary,
	salt: int = 0
) -> Dictionary:
	if template.fallback_variants.is_empty():
		var fb := {}
		for field in template.write_fields:
			fb[field] = "—"
		return fb
	return template.fallback_variants[abs(salt) % template.fallback_variants.size()].duplicate(true)


static func apply_payload_to_offer(
	template: MissionTemplate,
	offer: Dictionary,
	payload: Dictionary,
	is_fallback: bool
) -> Dictionary:
	var result := validate_payload(template, offer, payload)
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"reason": str(result.get("reason", "invalid generated text")),
			"offer": offer.duplicate(true),
		}
	var rendered := offer.duplicate(true)
	for field in template.write_fields:
		var key := field
		if field == "briefing":
			key = "generated_briefing"
		rendered[key] = _render(str(payload.get(field, "")), offer)
	rendered["generated_text_is_fallback"] = is_fallback
	rendered["generated_text_payload"] = payload.duplicate(true)

	if template.source_lane == "BOARD":
		_apply_board_quest_data(rendered, payload, template, is_fallback)
	return {
		"ok": true,
		"offer": rendered,
		"reason": "",
	}


static func fallback_offer(
	template: MissionTemplate,
	offer: Dictionary,
	salt: int = 0
) -> Dictionary:
	var payload := fallback_payload(template, offer, salt)
	var applied := apply_payload_to_offer(template, offer, payload, true)
	if bool(applied.get("ok", false)):
		return applied["offer"]
	push_warning(
		"[MissionTextGenerator] Fallback failed validation: %s" %
		str(applied.get("reason", "unknown"))
	)
	return offer


static func _apply_board_quest_data(
	rendered: Dictionary,
	payload: Dictionary,
	template: MissionTemplate,
	is_fallback: bool
) -> void:
	var quest_data: Dictionary = rendered.get("quest_data", {})
	if quest_data.is_empty():
		return
	quest_data = quest_data.duplicate(true)
	quest_data["title"] = str(rendered.get("title", ""))
	quest_data["dialogue"] = str(rendered.get("generated_briefing", ""))
	quest_data["public_board"] = true
	quest_data["public_board_template_id"] = template.template_id
	quest_data["public_board_turn_in_line"] = _render(
		str(payload.get("kaelen_turn_in", "")), rendered
	)
	quest_data["public_board_text_is_fallback"] = is_fallback
	rendered["quest_data"] = quest_data


static func _validate_kaelen(payload: Dictionary) -> Dictionary:
	var kaelen := str(payload.get("kaelen_turn_in", "")).to_lower()
	for blocked in KAELEN_AUTHORSHIP_BLOCKLIST:
		if kaelen.contains(blocked):
			return _invalid("Kaelen line implies she authored the posting")
	var has_disgust := false
	for cue in KAELEN_DISGUST_CUES:
		if kaelen.contains(cue):
			has_disgust = true
			break
	if not has_disgust:
		return _invalid("Kaelen line is not disgusted enough about public-board work")
	return {"ok": true, "reason": ""}


static func render_text(text: String, offer: Dictionary) -> String:
	return _render(text, offer)


static func _render(text: String, offer: Dictionary) -> String:
	var rendered := text
	var values: Dictionary = offer.get("placeholder_values", {})
	for key in values.keys():
		rendered = rendered.replace(str(key), str(values[key]))
	return rendered


static func _facts_for_prompt(offer: Dictionary) -> String:
	var quest_data: Dictionary = offer.get("quest_data", {})
	var objective: Dictionary = quest_data.get("objective", {})
	var lines: Array[String] = [
		"- template_id: " + str(offer.get("template_id", "")),
		"- objective_summary: " + str(offer.get("objective", "")),
		"- base_reward: " + str(offer.get("base_reward", 0)) + " SC",
	]
	if int(offer.get("duration_minutes", 0)) > 0:
		lines.append(
			"- deadline_minutes: " + str(offer.get("duration_minutes", 0))
		)
		lines.append(
			"- urgent_multiplier: " + str(offer.get("urgent_multiplier", 1.0))
		)
	if not objective.is_empty():
		lines.append("- objective_type: " + str(objective.get("type", "")))
		for key in objective.keys():
			if key == "type" or key == "drop_chance":
				continue
			lines.append("- " + str(key) + ": " + str(objective[key]))
	return "\n".join(lines)


static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
