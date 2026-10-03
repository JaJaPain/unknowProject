extends RefCounted

## Short-range pulls (docs/core_loop_plan_2026_10_01.md 4.3, core loop step
## 11): a reason to try every next gate, beside the Lodestar's long pull.
##
## - TEASER: before you go, the star map shows one true thing about a system:
##   a quirk the long-range scans can see, or its richest ore. Built from the
##   same deterministic profile the system will have when you arrive.
## - SURVEY DATA: the first visit to a system, and each anomaly scanned there,
##   is survey data Kaelen buys. Deeper data pays more. Exploring is income.
## - FIRSTS: the first time you meet a kind of system (a nebula, a pulsar, a
##   dying star...), N.O.V.A. reacts and the wiki adds it.
##
## State in StoryManager.story_state: "survey_data" (unsold entries),
## "quirks_seen" (kinds met), "surveyed_systems" (systems already charted).

const ProfileType := preload("res://scripts/story/premise/SystemProfile.gd")
const OreTypes := preload("res://scripts/economy/OreTypes.gd")

# --- Teasers ------------------------------------------------------------------

## What the long-range scans can see through a gate, per quirk.
const QUIRK_TEASERS := {
	"pulsar": "A pulsar ticks away on the long-range scans",
	"nebula": "Long-range scans show a dense nebula",
	"ion_storm": "Ion storms on the long-range scans",
	"dense_debris": "Heavy debris fields on the scans",
	"dying_star": "Its star is dying",
	"black_hole_proximity": "Something massive bends the light there",
	"dead_system": "No sign of life on the long-range scans",
	"gravity_tides": "Strong gravity tides on the scans",
	"relay_dark_zone": "The relay network goes dark past this gate",
}


## One true thing about a system from its profile ({quirks, ores}), or "" when
## there's nothing worth saying. Fixed per system.
static func teaser_from_profile(profile: Dictionary, system_id: String) -> String:
	var quirks: Array = profile.get("quirks", [])
	var ore := richest_ore(profile.get("ores", {}))
	var options: Array[String] = []
	for q in quirks:
		if QUIRK_TEASERS.has(str(q)):
			options.append(str(QUIRK_TEASERS[str(q)]))
	if not ore.is_empty():
		options.append("Its belts carry %s" % OreTypes.display(ore).to_lower())
	if options.is_empty():
		return ""
	return options[posmod(hash("teaser|%s" % system_id), options.size())]


## The belt's most common ore besides plain silicate ("" if none).
static func richest_ore(ores: Dictionary) -> String:
	var best := ""
	var best_share := 0.0
	for ore in ores:
		if str(ore) == "silicate":
			continue
		if float(ores[ore]) > best_share:
			best_share = float(ores[ore])
			best = str(ore)
	return best


## The profile a generated system will have (the same inputs the premise
## director uses on arrival). {} for systems without a generated config.
static func profile_for_system(config, system_id: String, depth: int) -> Dictionary:
	if config == null:
		return {}
	return ProfileType.generate(system_id, int(config.seed_value), str(config.star_type), false, depth)


# --- Survey data --------------------------------------------------------------

const SURVEY_KEY := "survey_data"
const SURVEYED_KEY := "surveyed_systems"
## What Kaelen pays: a system charted, an anomaly scanned; +25% per depth.
const SYSTEM_SURVEY_PAY := 40
const ANOMALY_SURVEY_PAY := 30
const PAY_PER_DEPTH := 0.25


static func survey_value(base: int, depth: int) -> int:
	return int(round(float(base) * (1.0 + PAY_PER_DEPTH * float(maxi(depth, 0)))))


## The first visit to a system: an entry worth selling. {} when charted before
## (or the start system, which everyone has charted).
static func record_visit(story_state: Dictionary, system_id: String, depth: int) -> Dictionary:
	if system_id.is_empty() or depth <= 0:
		return {}
	var surveyed: Array = story_state.get(SURVEYED_KEY, [])
	if surveyed.has(system_id):
		return {}
	surveyed.append(system_id)
	story_state[SURVEYED_KEY] = surveyed
	return _add(story_state, {"kind": "system", "id": system_id, "depth": depth, "value": survey_value(SYSTEM_SURVEY_PAY, depth)})


static func record_anomaly(story_state: Dictionary, anomaly_id: String, depth: int) -> Dictionary:
	if anomaly_id.is_empty():
		return {}
	for e in story_state.get(SURVEY_KEY, []):
		if str(e.get("id", "")) == anomaly_id:
			return {}
	return _add(story_state, {"kind": "anomaly", "id": anomaly_id, "depth": maxi(depth, 0), "value": survey_value(ANOMALY_SURVEY_PAY, maxi(depth, 0))})


## How deep the deepest unsold entry is (-1 with none).
static func deepest_unsold(story_state: Dictionary) -> int:
	var deepest := -1
	for e in story_state.get(SURVEY_KEY, []):
		deepest = maxi(deepest, int(e.get("depth", 0)))
	return deepest


static func _add(story_state: Dictionary, entry: Dictionary) -> Dictionary:
	var unsold: Array = story_state.get(SURVEY_KEY, [])
	unsold.append(entry)
	story_state[SURVEY_KEY] = unsold
	return entry


## {count, value} of what's waiting to sell.
static func unsold(story_state: Dictionary) -> Dictionary:
	var total := 0
	var entries: Array = story_state.get(SURVEY_KEY, [])
	for e in entries:
		total += int(e.get("value", 0))
	return {"count": entries.size(), "value": total}


## Sells everything to Kaelen: returns the credits and clears the list.
static func sell_all(story_state: Dictionary) -> int:
	var value := int(unsold(story_state)["value"])
	story_state[SURVEY_KEY] = []
	return value


# --- Firsts -------------------------------------------------------------------

const SEEN_KEY := "quirks_seen"
## N.O.V.A. the first time she meets each kind of system. Authored.
const FIRST_LINES := {
	"pulsar": "A pulsar. Hear that tick? Every sweep is going to sting the shields. Keep them topped up and it's just weather.",
	"nebula": "Nebula. Everything's shorter in here: my sensors, theirs. Good for hiding. Bad for seeing who else is hiding.",
	"ion_storm": "Ion storms roll through here. When one's overhead, the shields crawl back. Plan your fights around the weather.",
	"dense_debris": "Debris everywhere. Somebody had a very bad day here a long time ago. Watch the hull.",
	"dying_star": "That star's dying. Not today, not this century, but you can see it in the colour. Everyone here knows it.",
	"black_hole_proximity": "There's something massive out past the edge of this system. You can watch the stars bend around it. I'd rather not get closer.",
	"dead_system": "Nothing. No beacons, no chatter, no one. Systems this quiet always have a story, and it's never a nice one.",
	"gravity_tides": "Gravity tides. You'll feel the ship lean now and then. That's not me, I promise.",
	"relay_dark_zone": "The relays are dark here. No system radio. Just us and the static.",
}


## The kinds met for the first time in this system's quirks (and remembers
## them). Returns {"new": [quirk...], "line": first new one's N.O.V.A. line}.
static func note_firsts(story_state: Dictionary, quirks: Array) -> Dictionary:
	var seen: Array = story_state.get(SEEN_KEY, [])
	var fresh: Array[String] = []
	for q in quirks:
		var quirk := str(q)
		if FIRST_LINES.has(quirk) and not seen.has(quirk):
			seen.append(quirk)
			fresh.append(quirk)
	story_state[SEEN_KEY] = seen
	return {"new": fresh, "line": str(FIRST_LINES[fresh[0]]) if not fresh.is_empty() else ""}


static func wiki_id(quirk: String) -> String:
	return "quirk_%s" % quirk
