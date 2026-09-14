extends RefCounted

## Opening separation between campaigns (plan P3 deliverable E).
##
## Records, per campaign, the pressure pair in ACTIVATION order and the first two
## ACCEPTED investigation shapes. Used to bias the next campaign's opening away
## from the last two OTHER campaigns. This is limited opening separation, not a
## guarantee that every campaign is unique.

const HISTORY_VERSION := 1
const DEFAULT_PATH := "user://run_opening_history.json"
const RETAINED_OPENINGS := 2
const KINDS := ["signals", "claims", "supply"]


static func empty_history() -> Dictionary:
	return {"version": HISTORY_VERSION, "openings": []}


static func load_history(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "history": empty_history(), "reason": "missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[RunOpeningHistory] Could not open %s; using a fresh history." % path)
		return {"ok": false, "history": empty_history(), "reason": "unreadable"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or int((parsed as Dictionary).get("version", 0)) != HISTORY_VERSION \
			or not (parsed as Dictionary).get("openings", []) is Array:
		push_warning("[RunOpeningHistory] %s is corrupt; using a fresh history." % path)
		return {"ok": false, "history": empty_history(), "reason": "corrupt"}
	for entry: Variant in parsed["openings"]:
		if not entry is Dictionary or not entry.get("campaign_id") is String or not entry.get("pressure_pair") is Array or not entry.get("first_shapes") is Array:
			return {"ok": false, "history": empty_history(), "reason": "corrupt"}
	while parsed["openings"].size() > RETAINED_OPENINGS + 1:
		parsed["openings"].pop_front()
	return {"ok": true, "history": parsed, "reason": ""}


static func save_history(history: Dictionary, path: String = DEFAULT_PATH) -> Dictionary:
	var temp_path := "%s.tmp" % path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "unwritable"}
	file.store_string(JSON.stringify(history))
	file.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return {"ok": false, "reason": "missing_directory"}
	if dir.rename(temp_path.get_file(), path.get_file()) != OK:
		return {"ok": false, "reason": "rename_failed"}
	return {"ok": true, "history": history}


## Upsert THIS campaign's opening. A retry or a restore updates the existing
## entry rather than creating a second opening for the same campaign.
static func upsert_opening(history: Dictionary, campaign_id: String, pressure_pair: Array, first_shapes: Array) -> Dictionary:
	if campaign_id.is_empty():
		return {"ok": false, "changed": false, "history": history, "reason": "missing_campaign_id"}
	var next := history.duplicate(true) if not history.is_empty() else empty_history()
	if not next.get("openings", []) is Array:
		next["openings"] = []
	var entry := {"campaign_id": campaign_id, "pressure_pair": pressure_pair.duplicate(),
		"first_shapes": first_shapes.duplicate()}
	for index in range(next["openings"].size()):
		if str((next["openings"][index] as Dictionary).get("campaign_id", "")) == campaign_id:
			next["openings"][index] = entry
			return {"ok": true, "changed": true, "history": next, "reason": ""}
	next["openings"].append(entry)
	while next["openings"].size() > RETAINED_OPENINGS + 1:
		next["openings"].pop_front()
	return {"ok": true, "changed": true, "history": next, "reason": ""}


## Ordered pressure pairs to prefer, given which kinds are CURRENTLY eligible.
##
## Recent pairs are filtered out only when an alternative is actually available.
## With zero or one eligible kind the opening is recorded honestly as incomplete;
## an unsupported track is never activated just to make a unique pair.
static func preferred_pairs(history: Dictionary, eligible_kinds: Array, campaign_id: String) -> Array:
	var kinds: Array = []
	for kind: Variant in eligible_kinds:
		if str(kind) in KINDS and str(kind) not in kinds:
			kinds.append(str(kind))
	kinds.sort()
	if kinds.size() < 2:
		return [] # Honest incomplete opening: nothing to separate.
	var ordered: Array = []
	for first: String in kinds:
		for second: String in kinds:
			if first != second:
				ordered.append([first, second])
	var recent: Array = []
	for entry: Variant in history.get("openings", []):
		var record: Dictionary = entry
		# Only OTHER campaigns constrain this one.
		if str(record.get("campaign_id", "")) == campaign_id:
			continue
		var pair: Array = record.get("pressure_pair", [])
		if pair.size() == 2:
			recent.append("%s>%s" % [str(pair[0]), str(pair[1])])
	while recent.size() > RETAINED_OPENINGS:
		recent.pop_front()
	var fresh: Array = []
	for pair: Array in ordered:
		if "%s>%s" % [pair[0], pair[1]] not in recent:
			fresh.append(pair)
	# Filtering only applies when something survives it.
	return fresh if not fresh.is_empty() else ordered


static func reset(path: String = DEFAULT_PATH) -> Dictionary:
	return save_history(empty_history(), path)
