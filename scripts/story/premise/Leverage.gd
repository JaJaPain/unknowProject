extends RefCounted

## Leverage (vision plan 4.4): what the captain learns becomes something to
## use. A secret about a client (their lie, the smuggled cargo) is kept as a
## leverage entry; at any station it can be
##   sold     to an information broker, for credits;
##   exposed  to the local faction that cares most about order, for standing
##            (and a deed the factions hear about);
##   used for blackmail, which creates a new job on the spot: collect the
##            subject's payment from their dead drop. The captain is the cause.
## Each entry is used once.
##
## PURE: entries live in the premise director's saved state; GameRoot applies
## the effects (credits, standing, accepting the job).

const VALUES := {"client_secret": 220, "smuggling": 180, "intercept": 140}
const BLACKMAIL_MULT := 2.5
const EXPOSE_STANDING := 5.0

const SOURCES := {
	"client_lie": "client_secret",
	"wrong_cargo": "smuggling",
}


## An entry from a revealed twist on a mission, or {} when the twist gives no
## leverage (a rival on the job, say).
static func from_twist(mission_data: Dictionary, now_minute: int) -> Dictionary:
	var kind := str(SOURCES.get(str(mission_data.get("twist_reveal_kind", "")), ""))
	if kind.is_empty():
		return {}
	var subject := str(mission_data.get("twist_target_name", "")).strip_edges()
	if subject.is_empty():
		return {}
	var what := str(mission_data.get("twist_reveal", "")).strip_edges()
	if kind == "smuggling":
		what = "%s had %s shipped under a false manifest." % [subject, str(mission_data.get("twist_true_cargo", "undeclared cargo"))]
	return {
		"id": "leverage:%s" % str(mission_data.get("runtime_id", mission_data.get("title", ""))),
		"kind": kind,
		"subject": subject,
		"subject_faction": str(mission_data.get("faction", "")),
		"summary": what,
		"system_id": str(mission_data.get("system_id", "")),
		"minute": now_minute,
		"used": "",
	}


## Adds an entry unless one with its id exists. Returns the new list.
static func add(entries: Array, entry: Dictionary) -> Array:
	if entry.is_empty():
		return entries
	for e in entries:
		if str(e.get("id", "")) == str(entry["id"]):
			return entries
	var out := entries.duplicate(true)
	out.append(entry.duplicate(true))
	return out


static func unused(entries: Array) -> Array:
	return entries.filter(func(e): return e is Dictionary and str(e.get("used", "")).is_empty())


static func value_of(entry: Dictionary) -> int:
	return int(VALUES.get(str(entry.get("kind", "")), 120))


## The effect of using `entry` one way: {ok, credits, standing: {faction:
## delta}, deed: {...}, offer: {...}}. `world`: the premise world snapshot
## (factions and outposts here). `lawful_faction`: who hears an exposure.
static func use(entry: Dictionary, how: String, world: Dictionary, lawful_faction: Dictionary) -> Dictionary:
	if entry.is_empty() or not str(entry.get("used", "")).is_empty():
		return {"ok": false, "reason": "already_used"}
	var subject := str(entry.get("subject", "someone"))
	match how:
		"sell":
			return {"ok": true, "credits": value_of(entry), "standing": {}, "deed": {}, "offer": {}}
		"expose":
			var standing := {}
			if not lawful_faction.is_empty():
				standing[str(lawful_faction.get("id", ""))] = EXPOSE_STANDING
			if not str(entry.get("subject_faction", "")).is_empty():
				standing[str(entry["subject_faction"])] = -EXPOSE_STANDING
			return {"ok": true, "credits": 0, "standing": standing, "offer": {},
				"deed": {"tag": "exposed_%s" % str(entry.get("kind", "secret")),
					"public_summary": "A pilot handed what they knew about %s to %s." % [subject, str(lawful_faction.get("display_name", "the authorities"))]}}
		"blackmail":
			var offer := blackmail_offer(entry, world)
			if offer.is_empty():
				return {"ok": false, "reason": "no_dead_drop"}
			return {"ok": true, "credits": 0, "standing": {}, "offer": offer,
				"deed": {"tag": "blackmailed_%s" % str(entry.get("kind", "secret")).replace("client_secret", "client"),
					"public_summary": "Someone is squeezing %s for money. Nobody is saying who." % subject}}
	return {"ok": false, "reason": "unknown_use"}


## The job blackmail creates: collect the subject's payment from a dead drop
## at an outpost in this system and bring it to the main station.
static func blackmail_offer(entry: Dictionary, world: Dictionary) -> Dictionary:
	var outposts: Array = world.get("outposts", [])
	if outposts.is_empty():
		return {}
	var drop: Dictionary = outposts[abs(str(entry.get("id", "")).hash()) % outposts.size()]
	var main: Dictionary = world.get("main_station", {})
	var subject := str(entry.get("subject", "the mark"))
	var reward := int(round(value_of(entry) * BLACKMAIL_MULT))
	return {
		"title": "Payment from %s" % subject,
		"faction": "neutral",
		"agent_name": subject,
		"dialogue": "Fine. You'll get your money. It's at %s. Collect it and we never speak again." % str(drop.get("display", "the drop")),
		"objective": {"type": "PICKUP_SPECIAL", "target_outpost": str(drop.get("id", "")),
			"target_outpost_display": str(drop.get("display", "")), "target_npc": subject,
			"part_name": "Sealed payment", "destination": str(main.get("display", "the main station")),
			"reward_credits": reward},
		"choices": [{"text": "Collect it.", "consequence": {"credits_immediate": 0, "reputation_change": {},
			"combat_multiplier": 1.0, "reward_credits_multiplier": 1.0, "dialogue_response": "Don't come back."}}],
		"leverage_id": str(entry.get("id", "")),
	}


## Marks an entry used (returns the new list).
static func mark_used(entries: Array, entry_id: String, how: String) -> Array:
	var out := entries.duplicate(true)
	for e in out:
		if str(e.get("id", "")) == entry_id:
			e["used"] = how
	return out
