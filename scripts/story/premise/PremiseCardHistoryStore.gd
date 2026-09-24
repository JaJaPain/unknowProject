class_name PremiseCardHistoryStore
extends RefCounted

## Which premise cards this computer has already shown, across every campaign
## (plan Section 3.2). Lives in user://, outside the campaign slots, so deleting
## a campaign never resets it.
##
## Drawing order:
##   1. cards never used in the current cycle (in a seeded shuffle),
##   2. then the card used longest ago, never one of the last RECENT_WINDOW used,
##   3. and only if nothing else fits, a recent card (oldest first).
## When CYCLE_FRACTION of the deck has been used this cycle, a new cycle starts;
## the use order is kept, so the recency rule still holds across the reset.
##
## Stores card ids and counters only. No story text, no names, no fixed cast.
## "Used" means the player was SHOWN the card's opening beat: a card drawn in a
## campaign that was deleted before the player saw it stays fresh.

const HISTORY_VERSION := 1
const DEFAULT_PATH := "user://premise_card_history.json"
const RECENT_WINDOW := 30
const CYCLE_FRACTION := 0.9


static func empty_history() -> Dictionary:
	return {"version": HISTORY_VERSION, "cycle": 1, "counter": 0, "used": {}}


## Returns {ok, history, reason}. A missing file is a fresh history; a corrupt
## one is replaced by a fresh history with ok = false, never an error.
static func load_history(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "history": empty_history(), "reason": "missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "history": empty_history(), "reason": "unreadable"}
	var json := JSON.new()
	# JSON.new().parse() fails quietly; parse_string() would print an engine error.
	var parse_error := json.parse(file.get_as_text())
	file.close()
	var parsed: Variant = json.data if parse_error == OK else null
	if not parsed is Dictionary or int((parsed as Dictionary).get("version", 0)) != HISTORY_VERSION:
		push_warning("[PremiseCardHistory] %s is corrupt or an unsupported version; starting fresh." % path)
		return {"ok": false, "history": empty_history(), "reason": "corrupt"}
	var history: Dictionary = parsed
	if not history.get("used") is Dictionary:
		return {"ok": false, "history": empty_history(), "reason": "corrupt"}
	for card_id in (history["used"] as Dictionary).keys():
		var entry: Variant = history["used"][card_id]
		if not entry is Dictionary:
			return {"ok": false, "history": empty_history(), "reason": "corrupt"}
	history["cycle"] = maxi(1, int(history.get("cycle", 1)))
	history["counter"] = maxi(0, int(history.get("counter", 0)))
	return {"ok": true, "history": history, "reason": ""}


## Atomic replacement: temp file, then rename over the target.
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
	return {"ok": true}


## The player has just been shown this card's opening beat.
static func record_shown(history: Dictionary, card_id: String) -> Dictionary:
	var next := history.duplicate(true)
	next["counter"] = int(next.get("counter", 0)) + 1
	var used: Dictionary = next.get("used", {})
	used[card_id] = {"cycle": int(next.get("cycle", 1)), "seq": int(next["counter"])}
	next["used"] = used
	return next


static func used_this_cycle(history: Dictionary, card_id: String) -> bool:
	var entry: Variant = (history.get("used", {}) as Dictionary).get(card_id)
	return entry is Dictionary and int(entry.get("cycle", 0)) == int(history.get("cycle", 1))


## Sequence number of the card's last use, or -1 if this machine never used it.
static func last_seq(history: Dictionary, card_id: String) -> int:
	var entry: Variant = (history.get("used", {}) as Dictionary).get(card_id)
	return int(entry.get("seq", -1)) if entry is Dictionary else -1


static func is_recent(history: Dictionary, card_id: String, window: int = RECENT_WINDOW) -> bool:
	var seq := last_seq(history, card_id)
	return seq >= 0 and seq > int(history.get("counter", 0)) - window


## Starts a new cycle once enough of the deck has been used in this one.
## Returns the (possibly) updated history.
static func advance_cycle_if_due(history: Dictionary, deck_ids: Array) -> Dictionary:
	if deck_ids.is_empty():
		return history
	var used_now := 0
	for card_id in deck_ids:
		if used_this_cycle(history, str(card_id)):
			used_now += 1
	if float(used_now) / float(deck_ids.size()) < CYCLE_FRACTION:
		return history
	var next := history.duplicate(true)
	next["cycle"] = int(next.get("cycle", 1)) + 1
	return next


## Orders candidate card ids best-first for drawing. `seed_value` makes the
## order of equally fresh cards stable for a given campaign and moment.
static func order_candidates(history: Dictionary, candidate_ids: Array, seed_value: int, window: int = RECENT_WINDOW) -> Array[String]:
	var fresh: Array = []
	var older: Array = []
	var recent: Array = []
	for raw_id in candidate_ids:
		var card_id := str(raw_id)
		if not used_this_cycle(history, card_id):
			fresh.append([_shuffle_key(seed_value, card_id), card_id])
		elif is_recent(history, card_id, window):
			recent.append([last_seq(history, card_id), card_id])
		else:
			older.append([last_seq(history, card_id), card_id])
	fresh.sort()
	older.sort()
	recent.sort()
	var ordered: Array[String] = []
	for group in [fresh, older, recent]:
		for pair in group:
			ordered.append(str(pair[1]))
	return ordered


static func _shuffle_key(seed_value: int, card_id: String) -> String:
	return ("%d|%s" % [seed_value, card_id]).sha256_text()
