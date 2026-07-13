class_name ContextBlockBuilder
extends RefCounted

# Owns player-safe prompt projections. New story/bible fields are private by
# default: callers only get fields explicitly copied into these allowlists.


static func story_state_public_block(story_state: Dictionary) -> String:
	if story_state.is_empty():
		return ""
	var lines: Array[String] = []
	lines.append("Story State:")
	lines.append("- Chapter: %d" % int(story_state.get("chapter", 1)))
	_append_string_array_line(
		lines,
		"- Active tensions: %s",
		story_state.get("active_tensions", [])
	)
	_append_string_array_line(
		lines,
		"- Player knows: %s",
		story_state.get("player_knows", [])
	)
	var foreshadow := str(
		story_state.get("current_foreshadow", "")
	).strip_edges()
	if not foreshadow.is_empty():
		lines.append("- Foreshadow hint: %s" % foreshadow)
	_append_recent_consequences(lines, story_state)
	var mood := str(story_state.get("kaelen_current_mood", "")).strip_edges()
	if not mood.is_empty():
		lines.append("- Kaelen mood: %s" % mood)
	var relationship: Dictionary = story_state.get("kaelen_relationship", {}) \
		if story_state.get("kaelen_relationship", {}) is Dictionary else {}
	var relationship_band := str(relationship.get("band", "")).strip_edges()
	if not relationship_band.is_empty():
		lines.append("- Kaelen relationship: %s" % relationship_band)
	_append_pending_hook_projection(lines, story_state)
	_append_faction_pressure_line(lines, story_state)
	return "\n".join(lines)


static func mission_offer_block(story_state: Dictionary) -> String:
	return _capability_block(
		"Mission Offer Context",
		"Use for mission premise, urgency, and visible continuity.",
		story_state
	)


static func mission_answer_block(story_state: Dictionary) -> String:
	return _capability_block(
		"Mission Answer Context",
		"Use for answers to player questions without revealing hidden facts.",
		story_state
	)


static func character_conversation_block(story_state: Dictionary) -> String:
	return _capability_block(
		"Character Conversation Context",
		"Use for grounded NPC conversation and relationship-safe small talk.",
		story_state
	)


static func ambient_chatter_block(story_state: Dictionary) -> String:
	return _capability_block(
		"Ambient Chatter Context",
		"Use for optional background lines that should feel locally specific.",
		story_state
	)


static func nova_block(story_state: Dictionary) -> String:
	return _capability_block(
		"N.O.V.A. Context",
		"Use for ship-AI reactions that may reference only player-safe context.",
		story_state
	)


static func kaelen_block(story_state: Dictionary) -> String:
	return _capability_block(
		"Kaelen Context",
		"Use for Kaelen-facing handoffs, comments, and reactions.",
		story_state
	)


static func director_block(story_state: Dictionary) -> String:
	return _capability_block(
		"Large Model Director Context",
		"Use for high-level planning from public current-timeline state only.",
		story_state
	)


static func _capability_block(
	title: String,
	purpose: String,
	story_state: Dictionary
) -> String:
	var public_block := story_state_public_block(story_state)
	if public_block.is_empty():
		return ""
	var lines: Array[String] = []
	lines.append("### %s" % title)
	lines.append("Purpose: %s" % purpose)
	lines.append(public_block)
	return "\n".join(lines)


static func _append_string_array_line(
	lines: Array[String],
	template: String,
	value: Variant
) -> void:
	if not value is Array:
		return
	var kept: Array[String] = []
	for item in value:
		var text := str(item).strip_edges()
		if not text.is_empty():
			kept.append(text)
	if not kept.is_empty():
		lines.append(template % ", ".join(kept))


static func _append_faction_pressure_line(
	lines: Array[String],
	story_state: Dictionary
) -> void:
	var pressure: Dictionary = story_state.get("faction_pressure", {})
	if pressure.is_empty():
		return
	var parts: Array[String] = []
	for anchor in ["zenith", "aurelia", "vanguard"]:
		var fp: Variant = pressure.get(anchor, null)
		if not fp is Dictionary:
			continue
		var posture := str(fp.get("posture", "")).strip_edges()
		var scalar := int(fp.get("pressure", 0))
		var sign_word := "neutral"
		if scalar > 0:
			sign_word = "rising(+%d)" % scalar
		elif scalar < 0:
			sign_word = "easing(%d)" % scalar
		if not posture.is_empty():
			parts.append("%s [%s]: %s" % [
				anchor.capitalize(),
				sign_word,
				posture,
			])
	if not parts.is_empty():
		lines.append("- Faction pressure: %s" % " | ".join(parts))


static func _append_recent_consequences(
	lines: Array[String],
	story_state: Dictionary
) -> void:
	var consequences: Variant = story_state.get("story_consequences", [])
	if not consequences is Array or consequences.is_empty():
		return
	var parts: Array[String] = []
	var start: int = maxi(0, (consequences as Array).size() - 3)
	for i in range(start, (consequences as Array).size()):
		var entry: Variant = (consequences as Array)[i]
		if not entry is Dictionary:
			continue
		var text := str((entry as Dictionary).get("text", "")).strip_edges()
		if text.is_empty():
			continue
		var outcome := str((entry as Dictionary).get("outcome", "")).strip_edges()
		parts.append("%s%s" % [
			("%s: " % outcome) if not outcome.is_empty() else "",
			text,
		])
	if not parts.is_empty():
		lines.append("- Recent consequences: %s" % " | ".join(parts))


static func _append_pending_hook_projection(
	lines: Array[String],
	story_state: Dictionary
) -> void:
	var hooks: Variant = story_state.get("pending_hooks", [])
	if not hooks is Array or hooks.is_empty():
		return
	var refs: Array[String] = []
	for hook in hooks:
		var text := str(hook).strip_edges()
		if text.is_empty():
			continue
		refs.append("hook:%s" % text.sha256_text().substr(0, 12))
	if not refs.is_empty():
		lines.append("- Open story thread refs: %s" % ", ".join(refs))
