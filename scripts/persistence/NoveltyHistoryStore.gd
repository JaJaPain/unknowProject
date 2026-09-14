extends RefCounted

## Cross-campaign novelty history (plan P3 deliverable E).
##
## Stores ONLY structural signatures, exposure IDs, campaign IDs and sequence
## order. Never dialogue, names, secrets, companion memories, voices or
## relationships. This influences future SELECTION; a restored checkpoint must
## never apply it as a gameplay fact.
##
## Missing history starts empty. Corrupt history produces a diagnostic and a
## fresh bounded history without damaging any campaign save.

const HISTORY_VERSION := 1
const DEFAULT_PATH := "user://quest_novelty_history.json"
const MAX_PUBLISHED := 128
const MAX_ACCEPTED := 64


static func empty_history() -> Dictionary:
	return {"version": HISTORY_VERSION, "published": [], "accepted": []}


## Returns {history, ok, reason}. `ok` false means the file was unreadable or
## corrupt and a fresh bounded history is being used instead.
static func load_history(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "history": empty_history(), "reason": "missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[NoveltyHistory] Could not open %s; using a fresh history." % path)
		return {"ok": false, "history": empty_history(), "reason": "unreadable"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or int((parsed as Dictionary).get("version", 0)) != HISTORY_VERSION:
		push_warning("[NoveltyHistory] %s is corrupt or an unsupported version; using a fresh history." % path)
		return {"ok": false, "history": empty_history(), "reason": "corrupt"}
	var history: Dictionary = parsed
	for field in ["published", "accepted"]:
		if not history.get(field) is Array:
			push_warning("[NoveltyHistory] %s has an invalid '%s' list; using a fresh history." % [path, field])
			return {"ok": false, "history": empty_history(), "reason": "corrupt"}
		for entry: Variant in history[field]:
			if not entry is Dictionary or not entry.get("id") is String or not entry.get("signature") is String or not entry.get("campaign_id") is String:
				return {"ok": false, "history": empty_history(), "reason": "corrupt"}
	return {"ok": true, "history": _trimmed(history), "reason": ""}


## Atomic replacement: write a temporary file, then rename over the target, so a
## crash mid-write cannot leave a half-written history.
static func save_history(history: Dictionary, path: String = DEFAULT_PATH) -> Dictionary:
	var trimmed := _trimmed(history)
	var temp_path := "%s.tmp" % path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "unwritable"}
	file.store_string(JSON.stringify(trimmed))
	file.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return {"ok": false, "reason": "missing_directory"}
	if dir.rename(temp_path.get_file(), path.get_file()) != OK:
		return {"ok": false, "reason": "rename_failed"}
	return {"ok": true, "history": trimmed}


## One successful VISIBLE publication. Not a prefetch, a failed save, a reload,
## a panel refresh or the writer starting. `publication_id` deduplicates.
static func record_published(history: Dictionary, publication_id: String, signature: String, campaign_id: String) -> Dictionary:
	if publication_id.is_empty() or signature.is_empty():
		return {"ok": false, "changed": false, "history": history, "reason": "unbound_publication"}
	var next := _opened(history)
	for entry: Variant in next["published"]:
		if str((entry as Dictionary).get("id", "")) == publication_id:
			return {"ok": true, "changed": false, "history": next, "reason": "already_recorded"}
	var sequence := int(next["published"][-1].get("sequence", -1)) + 1 if not next["published"].is_empty() else 0
	next["published"].append({"id": publication_id, "signature": signature,
		"campaign_id": campaign_id, "sequence": sequence})
	return {"ok": true, "changed": true, "history": _trimmed(next), "reason": ""}


## One acceptance updates the accepted sequence once.
static func record_accepted(history: Dictionary, acceptance_id: String, signature: String, campaign_id: String) -> Dictionary:
	if acceptance_id.is_empty() or signature.is_empty():
		return {"ok": false, "changed": false, "history": history, "reason": "unbound_acceptance"}
	var next := _opened(history)
	for entry: Variant in next["accepted"]:
		if str((entry as Dictionary).get("id", "")) == acceptance_id:
			return {"ok": true, "changed": false, "history": next, "reason": "already_recorded"}
	var sequence := int(next["accepted"][-1].get("sequence", -1)) + 1 if not next["accepted"].is_empty() else 0
	next["accepted"].append({"id": acceptance_id, "signature": signature,
		"campaign_id": campaign_id, "sequence": sequence})
	return {"ok": true, "changed": true, "history": _trimmed(next), "reason": ""}


## Consecutive accepted pairs and triples, derived from the bounded sequence.
##
## Runs never span a campaign boundary. Campaign A's last acceptance followed by
## campaign B's first is not an adjacency the player ever experienced, and
## counting it as one would penalise a perfectly fresh opening.
static func accepted_runs(history: Dictionary) -> Dictionary:
	var pairs: Dictionary = {}
	var triples: Dictionary = {}
	for run: Array in _accepted_runs_by_campaign(history).values():
		for index in range(run.size()):
			if index + 1 < run.size():
				var pair := "%s>%s" % [run[index], run[index + 1]]
				pairs[pair] = int(pairs.get(pair, 0)) + 1
			if index + 2 < run.size():
				var triple := "%s>%s>%s" % [run[index], run[index + 1], run[index + 2]]
				triples[triple] = int(triples.get(triple, 0)) + 1
	return {"pairs": pairs, "triples": triples}


## Accepted signatures grouped by campaign, in order. Malformed entries are
## skipped rather than crashing: a damaged history degrades ranking, never
## gameplay.
static func _accepted_runs_by_campaign(history: Dictionary) -> Dictionary:
	var by_campaign: Dictionary = {}
	var accepted: Variant = history.get("accepted", [])
	if not accepted is Array:
		return by_campaign
	for entry: Variant in (accepted as Array):
		if not entry is Dictionary:
			continue
		var record: Dictionary = entry
		var signature := str(record.get("signature", ""))
		if signature.is_empty():
			continue
		var campaign := str(record.get("campaign_id", ""))
		if not by_campaign.has(campaign):
			by_campaign[campaign] = []
		(by_campaign[campaign] as Array).append(signature)
	return by_campaign


## The accepted signatures for ONE campaign, in order. "" means every campaign,
## which is what a caller with no campaign identity gets.
static func accepted_signatures_for(history: Dictionary, campaign_id: String) -> Array:
	var by_campaign := _accepted_runs_by_campaign(history)
	if campaign_id.is_empty():
		var all: Array = []
		for run: Array in by_campaign.values():
			all.append_array(run)
		return all
	return (by_campaign.get(campaign_id, []) as Array).duplicate()


## Reset ONLY this file. Never deletes campaigns or companion memory stores.
static func reset(path: String = DEFAULT_PATH) -> Dictionary:
	return save_history(empty_history(), path)


static func _opened(history: Dictionary) -> Dictionary:
	var next := history.duplicate(true) if not history.is_empty() else empty_history()
	for field in ["published", "accepted"]:
		if not next.get(field, []) is Array:
			next[field] = []
	next["version"] = HISTORY_VERSION
	return next


static func _trimmed(history: Dictionary) -> Dictionary:
	var next := _opened(history)
	while next["published"].size() > MAX_PUBLISHED:
		next["published"].pop_front()
	while next["accepted"].size() > MAX_ACCEPTED:
		next["accepted"].pop_front()
	return next


## Rank eligible candidates BEFORE prose generation, least-repeated first.
##
## Order: fewer recent repeated triples, then pairs, then least recently
## offered, then least recently accepted, then a stable campaign-seeded
## tie-break. This can only REORDER candidates the caller already validated:
## no signature match bypasses capability, cause, payment, recipient or
## navigation validation.
## candidates = [{id, signature, ...}]
## `campaign_id` scopes the "what did the player just accept" half of the
## ranking to THIS campaign. Exposure counts stay cross-campaign, which is the
## whole point of the file.
static func rank_candidates(history: Dictionary, candidates: Array, campaign_seed: int,
		campaign_id: String = "") -> Array:
	var runs := accepted_runs(history)
	var accepted: Array = accepted_signatures_for(history, campaign_id)
	var last_two: Array = accepted.slice(maxi(0, accepted.size() - 2))
	var offered_at: Dictionary = {}
	for entry: Variant in (history.get("published", []) as Array if history.get("published", []) is Array else []):
		if not entry is Dictionary:
			continue
		var published: Dictionary = entry
		var published_signature := str(published.get("signature", ""))
		if published_signature.is_empty():
			continue
		offered_at[published_signature] = int(published.get("sequence", 0))
	var accepted_at: Dictionary = {}
	for index in range(accepted.size()):
		accepted_at[str(accepted[index])] = index
	var scored: Array = []
	for raw: Variant in candidates:
		if not raw is Dictionary:
			continue
		var candidate: Dictionary = raw
		var signature := str(candidate.get("signature", ""))
		var triple := 0
		var pair := 0
		if last_two.size() >= 2:
			triple = int((runs["triples"] as Dictionary).get("%s>%s>%s" % [last_two[0], last_two[1], signature], 0))
		if last_two.size() >= 1:
			pair = int((runs["pairs"] as Dictionary).get("%s>%s" % [last_two[last_two.size() - 1], signature], 0))
		scored.append({
			"candidate": candidate,
			# An unknown or legacy signature is INCOMPARABLE, not proven fresh.
			# Treating "never seen" and "cannot tell" the same way is how a
			# missing signature quietly wins every ranking.
			"incomparable": 1 if signature.is_empty() or not signature.begins_with("v2:") else 0,
			"triple": triple,
			"pair": pair,
			"offered": int(offered_at.get(signature, -1)),
			"accepted": int(accepted_at.get(signature, -1)),
			"tie": ("%s|%d" % [signature, campaign_seed]).sha256_text(),
		})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["incomparable"]) != int(b["incomparable"]): return int(a["incomparable"]) < int(b["incomparable"])
		if int(a["triple"]) != int(b["triple"]): return int(a["triple"]) < int(b["triple"])
		if int(a["pair"]) != int(b["pair"]): return int(a["pair"]) < int(b["pair"])
		if int(a["offered"]) != int(b["offered"]): return int(a["offered"]) < int(b["offered"])
		if int(a["accepted"]) != int(b["accepted"]): return int(a["accepted"]) < int(b["accepted"])
		return str(a["tie"]) < str(b["tie"]))
	var out: Array = []
	for entry: Dictionary in scored:
		out.append(entry["candidate"])
	return out


## True when every eligible candidate repeats a recent accepted pair. The caller
## should log this and offer LESS work, never invent a new branch or hazard.
static func variety_exhausted(history: Dictionary, candidates: Array) -> bool:
	if candidates.is_empty():
		return false
	var accepted: Array = []
	for entry: Variant in history.get("accepted", []):
		accepted.append(str((entry as Dictionary).get("signature", "")))
	if accepted.is_empty():
		return false
	var runs := accepted_runs(history)
	var last := str(accepted[accepted.size() - 1])
	for raw: Variant in candidates:
		var signature := str((raw as Dictionary).get("signature", ""))
		if int((runs["pairs"] as Dictionary).get("%s>%s" % [last, signature], 0)) == 0:
			return false
	return true
