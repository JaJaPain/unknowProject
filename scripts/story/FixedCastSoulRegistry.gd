class_name FixedCastSoulRegistry
extends RefCounted

# Human-curated fixed-cast source of truth. This registry intentionally carries
# only public, prompt-safe identity and state rules. Campaign secrets remain in
# StoryManager/CampaignBibleStore and are never copied here.

const SOUL_PATH := "res://data/content/fixed_cast_souls.json"
const REQUIRED_IDS := ["kaelen", "nova"]
const REQUIRED_FIELDS := [
	"version", "permanent_core", "relationship_lens", "voice_controls",
	"states", "situation_rules", "rapport_tone",
]


static func load_registry() -> Dictionary:
	var file := FileAccess.open(SOUL_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "soul_file_missing"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"ok": false, "reason": "soul_json_invalid"}
	var data: Variant = parser.get_data()
	if not data is Dictionary:
		return {"ok": false, "reason": "soul_root_invalid"}
	var souls: Variant = (data as Dictionary).get("souls", {})
	if not souls is Dictionary:
		return {"ok": false, "reason": "souls_missing"}
	for soul_id in REQUIRED_IDS:
		var soul: Variant = (souls as Dictionary).get(soul_id, {})
		if not soul is Dictionary:
			return {"ok": false, "reason": "soul_missing:%s" % soul_id}
		for field in REQUIRED_FIELDS:
			if not (soul as Dictionary).has(field):
				return {"ok": false, "reason": "soul_field_missing:%s:%s" % [soul_id, field]}
	return {"ok": true, "souls": (souls as Dictionary).duplicate(true)}


static func public_prompt_projection(
	soul_id: String,
	state_id: String,
	situation: String
) -> Dictionary:
	var loaded := load_registry()
	if not bool(loaded.get("ok", false)):
		return loaded
	var soul: Dictionary = (loaded.get("souls", {}) as Dictionary).get(soul_id, {})
	var states: Dictionary = soul.get("states", {}) if soul.get("states", {}) is Dictionary else {}
	var state: Dictionary = states.get(state_id, {}) if states.get(state_id, {}) is Dictionary else {}
	if state.is_empty():
		return {"ok": false, "reason": "unknown_soul_state:%s:%s" % [soul_id, state_id]}
	var situations: Dictionary = soul.get("situation_rules", {}) if soul.get("situation_rules", {}) is Dictionary else {}
	var rule: Dictionary = situations.get(situation, {}) if situations.get(situation, {}) is Dictionary else {}
	if rule.is_empty():
		return {"ok": false, "reason": "unknown_soul_situation:%s:%s" % [soul_id, situation]}
	var relationship_lens: Dictionary = (soul.get("relationship_lens", {}) as Dictionary).duplicate(true)
	# The docs/data may record a boundary for designers, but prompts only need
	# the observable trust lens. Never tell the model what remains private.
	relationship_lens.erase("always_private")
	return {
		"ok": true,
		"soul_id": soul_id,
		"version": str(soul.get("version", "")),
		"state": state_id,
		"situation": situation,
		"permanent_core": (soul.get("permanent_core", {}) as Dictionary).duplicate(true),
		"relationship_lens": relationship_lens,
		"voice_controls": (soul.get("voice_controls", {}) as Dictionary).duplicate(true),
		"rapport_tone": (soul.get("rapport_tone", {}) as Dictionary).duplicate(true),
		"state_rule": state.duplicate(true),
		"situation_rule": rule.duplicate(true),
	}


static func prompt_block(
	soul_id: String,
	state_id: String,
	situation: String,
	rapport_band: String = "neutral",
	attachment_memory: String = ""
) -> String:
	var projection := public_prompt_projection(soul_id, state_id, situation)
	if not bool(projection.get("ok", false)):
		return ""
	var core: Dictionary = projection.get("permanent_core", {})
	var voice: Dictionary = projection.get("voice_controls", {})
	var state_rule: Dictionary = projection.get("state_rule", {})
	var situation_rule: Dictionary = projection.get("situation_rule", {})
	var rapport_tone: Dictionary = projection.get("rapport_tone", {}) \
		if projection.get("rapport_tone", {}) is Dictionary else {}
	var lines: Array[String] = [
		"Fixed-cast soul v%s (non-negotiable public guidance):" % str(projection.get("version", "")),
		"- Role: %s" % str(core.get("public_role", "")),
		"- Coping style: %s" % str(core.get("coping_mechanism", "")),
		"- Moral boundary: %s" % str(core.get("moral_boundary", "")),
		"- State outward tell: %s" % str(state_rule.get("outward_tell", "")),
		"- Situation must do: %s" % str(situation_rule.get("must_do", "")),
		"- Situation must not: %s" % str(situation_rule.get("must_not", "")),
		"- Voice: %s" % str(voice.get("sentence_rhythm", "")),
		"- Address: %s" % str(voice.get("address_rule", "")),
		"- Line value: %s" % str(voice.get("line_value_rule", "")),
		"- Offer money bias: %s" % str(voice.get("offer_money_bias", "")),
		"- Public-board money: %s" % str(voice.get("public_board_money_rule", "")),
		"- Current rapport (%s): %s" % [rapport_band, str(rapport_tone.get(rapport_band, rapport_tone.get("neutral", "")))],
	]
	if not attachment_memory.strip_edges().is_empty():
		lines.append("- Earned shared-memory callback: %s" % attachment_memory.strip_edges())
	return "\n".join(lines)
