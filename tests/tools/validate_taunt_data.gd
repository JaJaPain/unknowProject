extends SceneTree

# Validates the whole authored taunt file against the real runtime rules, and
# checks for the failure modes a hand-written pool is prone to: duplicates
# across causes, and near-duplicates that share a whole sentence.

const CauseType := preload("res://scripts/combat/TauntCause.gd")
const DATA_PATH := "res://data/content/taunt_lines.json"


func _initialize() -> void:
	await process_frame
	var llm: Node = get_root().get_node_or_null("LLMInterface")
	if llm == null:
		push_error("[Validate] LLMInterface unavailable.")
		quit(1)
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	var causes: Dictionary = (data as Dictionary).get("causes", {})
	var failures: Array[String] = []
	var seen_global: Dictionary = {}
	var total := 0
	var long_lines := 0
	for cause_id in CauseType.ALL:
		var record: Dictionary = causes.get(cause_id, {})
		var lines: Array = record.get("lines", [])
		total += lines.size()
		if lines.size() < 20:
			failures.append("%s has only %d lines (target 25+)." % [cause_id, lines.size()])
		for raw in lines:
			var text := str(raw)
			var reason := str(llm.validate_taunt_line(text))
			if not reason.is_empty():
				failures.append("%s REJECT(%s): %s" % [cause_id, reason, text])
				continue
			var role := str(llm.taunt_role_confusion(text, cause_id))
			if not role.is_empty():
				failures.append("%s REJECT(%s): %s" % [cause_id, role, text])
				continue
			if seen_global.has(text):
				failures.append(
					"DUPLICATE across causes (%s and %s): %s"
					% [str(seen_global[text]), cause_id, text]
				)
				continue
			seen_global[text] = cause_id
			if text.split(" ", false).size() > 18:
				long_lines += 1
				print("  long (%d words) %s: %s" % [
					text.split(" ", false).size(), cause_id, text
				])
	# Stock phrases repeated across causes: not exact duplicates, so the check
	# above misses them, but the player hears them as the game's verbal tic. I
	# wrote three "Nothing personal" lines and three "make this one hurt" lines
	# in the same pass I warned Abe about doing exactly that.
	var stock := [
		"nothing personal", "no hard feelings", "take it personally",
		"take this personally", "make this one hurt", "this is the part where",
		"get this over with",
	]
	for phrase in stock:
		var hits: Array[String] = []
		for text in seen_global.keys():
			if str(text).to_lower().contains(str(phrase)):
				hits.append("[%s] %s" % [str(seen_global[text]), str(text)])
		if hits.size() > 1:
			failures.append(
				"STOCK PHRASE '%s' appears %d times:
      %s"
				% [phrase, hits.size(), "
      ".join(hits)]
			)
	print("[Validate] %d lines, %d over 18 words, %d failure(s)." % [
		total, long_lines, failures.size(),
	])
	for cause_id in CauseType.ALL:
		print("    %-20s %d" % [cause_id, (causes.get(cause_id, {}).get("lines", []) as Array).size()])
	for failure in failures:
		push_error("[FAIL] %s" % failure)
	if failures.is_empty():
		print("[PASS] Authored taunt data")
		quit(0)
		return
	quit(1)
