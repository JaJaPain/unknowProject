class_name PremiseCardSelector
extends RefCounted

## Chooses premise cards for a moment in play (plan Section 3.2).
##
## `situation` is a plain dictionary so this runs without the game:
##   quirks: Array[String]           system quirks present here
##   states: Array[String]           system states active here
##   faction_count: int              generated factions available to cast
##   seeds: Array[String]            seed tags left by recent resolutions
##   scale: String                   "personal" | "local" | "regional" | "" (any)
##   themes: Array[String]           campaign theme bias (optional)
##   hidden_hand_method: String      main-story method to fit (optional)
##   excluded_ids: Array[String]     used or live in this campaign (never repeat)
##
## Hard requirements filter; then the order is:
##   1. history group on this machine (fresh, then older, then recent),
##   2. fit with the situation (seeds, preferred quirks, theme, hidden hand),
##   3. within "older", the card used longest ago; otherwise a seeded shuffle.
## Freshness comes first so a well-fitting card the player saw last week never
## beats one they have never seen.

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const HistoryType := preload("res://scripts/story/premise/PremiseCardHistoryStore.gd")

const SEED_WEIGHT := 3
const QUIRK_WEIGHT := 1
const THEME_WEIGHT := 1
const HIDDEN_HAND_WEIGHT := 2


## Why a card cannot be used here, or "" if it can.
static func rejection(card: Dictionary, situation: Dictionary) -> String:
	var card_id := str(card.get("id", ""))
	if card_id in _strings(situation.get("excluded_ids", [])):
		return "already used in this campaign"
	var wanted_scale := str(situation.get("scale", ""))
	if not wanted_scale.is_empty() and str(card.get("scale", "")) != wanted_scale:
		return "wrong scale"
	var req: Dictionary = card.get("requirements", {})
	var quirks := _strings(situation.get("quirks", []))
	var states := _strings(situation.get("states", []))
	for q in _strings(req.get("quirks_required", [])):
		if not q in quirks:
			return "needs quirk %s" % q
	for q in _strings(req.get("quirks_forbidden", [])):
		if q in quirks:
			return "forbidden quirk %s" % q
	for s in _strings(req.get("states_required", [])):
		if not s in states:
			return "needs state %s" % s
	for s in _strings(req.get("states_forbidden", [])):
		if s in states:
			return "forbidden state %s" % s
	if int(req.get("min_factions", 1)) > int(situation.get("faction_count", 0)):
		return "not enough factions"
	return ""


static func score(card: Dictionary, situation: Dictionary) -> int:
	var total := 0
	var seeds := _strings(situation.get("seeds", []))
	for accepted in _strings(card.get("accepts_seeds", [])):
		if accepted in seeds:
			total += SEED_WEIGHT
	var quirks := _strings(situation.get("quirks", []))
	for q in _strings((card.get("requirements", {}) as Dictionary).get("quirks_preferred", [])):
		if q in quirks:
			total += QUIRK_WEIGHT
	var themes := _strings(situation.get("themes", []))
	for t in _strings(card.get("themes", [])):
		if t in themes:
			total += THEME_WEIGHT
	var method := str(situation.get("hidden_hand_method", ""))
	if not method.is_empty() and method in _strings((card.get("hidden_hand_compat", {}) as Dictionary).get("methods", [])):
		total += HIDDEN_HAND_WEIGHT
	return total


static func eligible_ids(library, situation: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for card_id in library.ids():
		if rejection(library.get_card(card_id), situation).is_empty():
			out.append(card_id)
	return out


## Best-first card ids for this situation. `count` <= 0 returns all of them.
static func pick(library, history: Dictionary, situation: Dictionary, seed_value: int, count: int = 1) -> Array[String]:
	var keyed: Array = []
	for card_id in eligible_ids(library, situation):
		var group := _history_group(history, card_id)
		var fit := score(library.get_card(card_id), situation)
		var tie: Variant = HistoryType.last_seq(history, card_id) if group == 1 else _shuffle_key(seed_value, card_id)
		keyed.append([group, -fit, tie, card_id])
	keyed.sort_custom(_compare_keys)
	var ordered: Array[String] = []
	for entry in keyed:
		ordered.append(str(entry[3]))
	if count > 0 and ordered.size() > count:
		ordered.resize(count)
	return ordered


static func _history_group(history: Dictionary, card_id: String) -> int:
	if not HistoryType.used_this_cycle(history, card_id):
		return 0
	return 2 if HistoryType.is_recent(history, card_id) else 1


static func _compare_keys(a: Array, b: Array) -> bool:
	for i in 3:
		if a[i] == b[i]:
			continue
		# Mixed tie types never meet: a group always uses one kind of tie key.
		return a[i] < b[i]
	return str(a[3]) < str(b[3])


static func _shuffle_key(seed_value: int, card_id: String) -> String:
	return ("%d|%s" % [seed_value, card_id]).sha256_text()


static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in value:
			out.append(str(item))
	return out
