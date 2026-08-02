class_name QuietMomentBeats
extends RefCounted

# Loads the beat definitions and builds one prompt.
#
# Code owns every choice except the words themselves: which facts exist, how
# they are worded, which demos are shown, which detail she mentions, which
# device she uses. Five separate attempts to make the model vary these by
# instruction failed; rotating them here works. See
# skills/skill_llm_character_dialogue.md.

const BEATS_PATH := "res://data/content/quiet_moment_beats.json"
const Checks := preload("res://scripts/story/QuietMomentChecks.gd")

static var _cache: Dictionary = {}
# Draw bags: rotation means WITHOUT replacement. rng.choice-style sampling
# repeated one detail 4/10 in a single run during research.
static var _bags: Dictionary = {}


static func load_document() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var file := FileAccess.open(BEATS_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "beats_file_missing"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"ok": false, "reason": "beats_json_invalid"}
	var root: Variant = parser.get_data()
	if not root is Dictionary or not (root as Dictionary).has("beats"):
		return {"ok": false, "reason": "beats_document_invalid"}
	_cache = {
		"ok": true,
		"beats": (root as Dictionary).get("beats", {}),
		"demo_pools": (root as Dictionary).get("demo_pools", {}),
	}
	return _cache


# Rotation bags are static and deliberately persist: that is what makes a
# playthrough feel varied. A NEW CAMPAIGN must clear them, or it inherits the
# previous campaign's position in every cycle.
static func reset_rotation() -> void:
	_bags.clear()


static func beat_ids() -> Array:
	var doc := load_document()
	if not bool(doc.get("ok", false)):
		return []
	return (doc.get("beats", {}) as Dictionary).keys()


static func beat(beat_id: String) -> Dictionary:
	var doc := load_document()
	if not bool(doc.get("ok", false)):
		return {}
	return (doc.get("beats", {}) as Dictionary).get(beat_id, {})


# Draws without replacement, reshuffling when the bag empties.
static func _draw(key: String, pool: Array, rng: RandomNumberGenerator) -> Variant:
	if pool.is_empty():
		return null
	var bag: Array = _bags.get(key, [])
	if bag.is_empty():
		bag = pool.duplicate()
		# Fisher-Yates with the caller's rng so a seeded run is reproducible
		for i in range(bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Variant = bag[i]
			bag[i] = bag[j]
			bag[j] = tmp
	var picked: Variant = bag.pop_back()
	_bags[key] = bag
	return picked


static func _demos_for(speaker: String, avoid_facts: String, count: int,
		rng: RandomNumberGenerator) -> Array:
	var doc := load_document()
	var pool: Array = (doc.get("demo_pools", {}) as Dictionary).get(speaker, [])
	if pool.is_empty():
		return []
	var candidates := pool.duplicate()

	# Drop the demo whose facts most resemble this moment: a near-match gets
	# templated rather than transferred.
	if not avoid_facts.is_empty():
		var target := Checks.words_of(avoid_facts)
		var best_index := -1
		var best_overlap := -1
		for i in candidates.size():
			var facts := str((candidates[i] as Dictionary).get("facts", ""))
			var overlap := 0
			for w in Checks.words_of(facts):
				if target.has(w):
					overlap += 1
			if overlap > best_overlap:
				best_overlap = overlap
				best_index = i
		if best_index >= 0:
			candidates.remove_at(best_index)

	# One per shape first, so structure is never uniform within a request.
	var by_shape := {}
	for entry in candidates:
		var shape := str((entry as Dictionary).get("shape", "plain"))
		if not by_shape.has(shape):
			by_shape[shape] = []
		(by_shape[shape] as Array).append(entry)
	var shapes: Array = by_shape.keys()
	for i in range(shapes.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = shapes[i]
		shapes[i] = shapes[j]
		shapes[j] = tmp

	var picked: Array = []
	for shape in shapes:
		if picked.size() >= count:
			break
		var group: Array = by_shape[shape]
		picked.append(group[rng.randi_range(0, group.size() - 1)])
	for entry in candidates:
		if picked.size() >= count:
			break
		if not picked.has(entry):
			picked.append(entry)
	return picked


# Builds one request. Returns:
#   ok, prompt, packet, lead_in, brief, demos, speaker, word_cap, third_parties
#
# `brief` is returned so the screening can reject the model quoting our own
# prose back at us — that happened when a valence paragraph read like sample
# dialogue.
static func build_request(beat_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var b := beat(beat_id)
	if b.is_empty():
		return {"ok": false, "reason": "unknown_beat:%s" % beat_id}

	var speaker := str(b.get("speaker", ""))
	var packet := str(_draw("%s.packet" % beat_id, b.get("packets", []), rng))
	var lead_in := ""
	if b.has("lead_in_pool"):
		lead_in = str(_draw("%s.lead" % beat_id, b.get("lead_in_pool", []), rng))

	var demos := _demos_for(speaker, packet, 5, rng)
	var demo_lines: Array[String] = []
	var shown_parts: Array[String] = []
	for entry in demos:
		var facts := str((entry as Dictionary).get("facts", ""))
		var line := str((entry as Dictionary).get("line", ""))
		demo_lines.append(line)
		var lead_word := facts.substr(0, 1).to_lower() + facts.substr(1)
		shown_parts.append("Once, when %s she said this.\n“%s”" % [lead_word, line])
	var shown := "\n\n".join(shown_parts)

	var third_parties: Array = []
	var prompt := ""
	var brief := ""

	if b.has("devices"):
		var result := _build_device_prompt(beat_id, b, packet, lead_in, shown, rng)
		prompt = str(result.get("prompt", ""))
		brief = str(result.get("brief", ""))
		third_parties = result.get("third_parties", [])
	else:
		var scoped_packet := packet
		if b.has("detail_pool"):
			var detail := str(_draw("%s.detail" % beat_id, b.get("detail_pool", []), rng))
			scoped_packet = "%s %s" % [
				packet,
				str(b.get("detail_prompt", "")).replace("{detail}", detail),
			]
		brief = "%s\n%s" % [str(b.get("valence", "")), str(b.get("register", ""))]
		prompt = _assemble(b, scoped_packet, lead_in, shown)

	return {
		"ok": true,
		"prompt": prompt,
		"packet": packet,
		"lead_in": lead_in,
		"brief": brief,
		"demos": demo_lines,
		"speaker": speaker,
		"word_cap": int(b.get("word_cap", 28)),
		"third_parties": third_parties,
	}


static func _assemble(b: Dictionary, packet: String, lead_in: String,
		shown: String) -> String:
	var parts: Array[String] = [
		str(b.get("who", "")),
		str(b.get("register", "")),
		"You'll be given the only facts that are true right now. Write one spoken line for her.",
		str(b.get("scope", "")),
		"Say one concrete thing. No grand comparisons, no metaphors that need thinking about.",
		"The examples below are built differently from each other. Vary the shape; don't copy the sentence pattern of any of them.",
		shown,
		"Now: %s" % [packet.substr(0, 1).to_lower() + packet.substr(1)],
	]
	if not lead_in.is_empty():
		# Without a factual opener some reactions sound unwarranted. The
		# lead-in is authored; the model must carry on from it, not restate it.
		parts.append(
			"She has ALREADY said this out loud, just now: \"%s\"\n" % lead_in
			+ "Your line is what she says NEXT. Do not repeat it, do not restate the "
			+ "fact it contains, and do not begin by agreeing with it — carry straight "
			+ "on from it as the same breath of speech.")
	parts.append(str(b.get("valence", "")))
	parts.append("Write what she says. Use a different idea AND a different sentence shape from every example above.")
	parts.append("Return ONLY this JSON object, with exactly one key: {\"line\":\"...\"}")
	var kept: Array[String] = []
	for p in parts:
		if not p.strip_edges().is_empty():
			kept.append(p)
	return "\n\n".join(kept)


# Long transit carries two devices. Naming only one made it formulaic
# (20/20 identical retractions), so code rotates between them.
static func _build_device_prompt(beat_id: String, b: Dictionary, packet: String,
		lead_in: String, shown: String, rng: RandomNumberGenerator) -> Dictionary:
	var devices: Dictionary = b.get("devices", {})
	var names: Array = devices.keys()
	var chosen := str(_draw("%s.device" % beat_id, names, rng))
	var device: Dictionary = devices.get(chosen, {})
	var template := str(device.get("template", ""))
	var third_parties: Array = []

	var filled := template \
		.replace("{who}", str(b.get("who", ""))) \
		.replace("{register}", str(b.get("register", ""))) \
		.replace("{lead}", lead_in) \
		.replace("{shown}", shown)

	if chosen == "jealousy":
		var mech := str(_draw("%s.mech" % beat_id, device.get("mechanics", []), rng))
		third_parties = device.get("mechanics", [])
		filled = filled \
			.replace("{mechanic}", mech) \
			.replace("{tool}", str(_draw("%s.tool" % beat_id, device.get("tools", []), rng))) \
			.replace("{part}", str(_draw("%s.part" % beat_id, device.get("parts", []), rng))) \
			.replace("{mishap}", str(_draw("%s.mishap" % beat_id, device.get("mishaps", []), rng)))
	else:
		filled = filled.replace(
			"{detail}", str(_draw("%s.detail" % beat_id, device.get("detail_pool", []), rng)))

	return {
		"prompt": filled,
		"brief": str(b.get("register", "")),
		"third_parties": third_parties,
	}
