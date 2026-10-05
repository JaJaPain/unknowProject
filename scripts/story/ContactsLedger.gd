extends RefCounted

## N.O.V.A.'s database of people (Abe, 2026-10-05; campaign spine plan,
## section 8): everyone the Captain has dealt with, their portrait, and a very
## brief line of how ("Sent you on 3 jobs for ore in Myrion Watch.").
##
## Every line is assembled by code from what actually happened, never by a
## model, so it's always true. Kept in StoryManager.story_state["contacts"], so
## it saves and rolls back with the campaign.
##
## Two sources, merged when shown:
## - recorded here as they happen: jobs a person gave, items they handed over,
##   lounge talks;
## - read from the story system when shown (GameRoot.premise_people()): people
##   who came up in stories the Captain saw, their fates, and, once revealed,
##   who was behind it all. So the main story's culprit is always already in
##   the database.
##
## Book: {key: entry}. Entry: {key, name, entity_id, portrait_id, role, faction,
## events: [{kind, detail, system, minute}], pinned, first_minute, last_minute}.

const MAX_EVENTS := 30

## How a job reads in a line: "sent you on 3 jobs for ore".
const JOB_PHRASE := {
	"DELIVER_ORE": "for ore",
	"PICKUP_SPECIAL": "to fetch something",
	"DELIVERY_COURIER": "to deliver cargo",
	"PURCHASE_DELIVERY": "to buy supplies",
	"KILL_SHIPS": "to hunt ships",
	"TARGET_WITH_COMMS_REVERSAL": "to hunt ships",
	"RECOVER_COMBAT_DROP": "to recover a drop",
	"INVESTIGATE_SIGNAL": "to check a signal",
}


static func key_for(name: String, entity_id: String = "") -> String:
	if not entity_id.strip_edges().is_empty():
		return entity_id.strip_edges()
	return "name:" + name.strip_edges().to_lower()


## Adds what happened with `who` ({name, entity_id?, portrait_id?, role?,
## faction?}). Returns the book; `is_new` set on the entry the first time.
static func record(book: Dictionary, who: Dictionary, system: String, kind: String, detail: String, minute: int) -> Dictionary:
	var name := str(who.get("name", "")).strip_edges()
	if name.is_empty():
		return book
	var next := book.duplicate(true)
	var key := key_for(name, str(who.get("entity_id", "")))
	# The same person may have been recorded by name before their story id was known.
	if not next.has(key) and next.has(key_for(name)):
		next[key] = next[key_for(name)]
		next.erase(key_for(name))
		next[key]["key"] = key
		next[key]["entity_id"] = str(who.get("entity_id", ""))
	var entry: Dictionary = next.get(key, {"key": key, "name": name, "entity_id": str(who.get("entity_id", "")),
		"portrait_id": "", "role": "", "faction": "", "events": [], "pinned": false, "first_minute": minute})
	for field in ["portrait_id", "role", "faction"]:
		var v := str(who.get(field, "")).strip_edges()
		if not v.is_empty() and str(entry.get(field, "")).is_empty():
			entry[field] = v
	var events: Array = entry["events"]
	events.append({"kind": kind, "detail": detail, "system": system, "minute": minute})
	while events.size() > MAX_EVENTS:
		events.pop_front()
	entry["last_minute"] = minute
	next[key] = entry
	return next


static func set_pinned(book: Dictionary, key: String, pinned: bool) -> Dictionary:
	if not book.has(key):
		return book
	var next := book.duplicate(true)
	next[key]["pinned"] = pinned
	return next


## The database as shown: recorded people merged with `story_people`
## ([{entity_id, name, story, system}] from stories the Captain saw), newest
## first. `fates`: {entity_id: ["dead"|"imprisoned"|...]}; `hand_id`: the
## revealed culprit's entity id, "" until the reveal.
static func entries(book: Dictionary, story_people: Array = [], fates: Dictionary = {}, hand_id: String = "") -> Array:
	var merged := book.duplicate(true)
	for p in story_people:
		var key := key_for(str(p.get("name", "")), str(p.get("entity_id", "")))
		if not merged.has(key) and merged.has(key_for(str(p.get("name", "")))):
			key = key_for(str(p.get("name", "")))
		var entry: Dictionary = merged.get(key, {"key": key, "name": str(p.get("name", "")), "entity_id": str(p.get("entity_id", "")),
			"portrait_id": "", "role": "", "faction": "", "events": [], "pinned": false,
			"first_minute": int(p.get("minute", 0)), "last_minute": int(p.get("minute", 0))})
		var stories: Array = entry.get("stories", [])
		var tag := "%s|%s" % [str(p.get("story", "")), str(p.get("system", ""))]
		if not stories.has(tag):
			stories.append(tag)
		entry["stories"] = stories
		entry["last_minute"] = maxi(int(entry.get("last_minute", 0)), int(p.get("minute", 0)))
		merged[key] = entry
	var out: Array = []
	for entry in merged.values():
		var eid := str(entry.get("entity_id", ""))
		var fate_list: Array = fates.get(eid, []) if not eid.is_empty() else []
		var view: Dictionary = entry.duplicate(true)
		view["is_hand"] = not hand_id.is_empty() and eid == hand_id
		view["fate"] = "dead" if "dead" in fate_list else ("in custody" if "imprisoned" in fate_list else "")
		view["line"] = line(entry, str(view["fate"]), bool(view["is_hand"]))
		view["systems"] = systems_of(entry)
		out.append(view)
	out.sort_custom(func(a, b): return int(a.get("last_minute", 0)) > int(b.get("last_minute", 0)))
	return out


## The very brief "how": one or two plain clauses from the facts.
static func line(entry: Dictionary, fate: String = "", is_hand: bool = false) -> String:
	var parts: Array[String] = []
	var events: Array = entry.get("events", [])
	var jobs := events.filter(func(e): return str(e.get("kind", "")) == "job")
	if not jobs.is_empty():
		var kinds := {}
		for j in jobs:
			kinds[str(j.get("detail", ""))] = true
		var count := jobs.size()
		var what := "a job" if count == 1 else "%d jobs" % count
		if kinds.size() == 1:
			var phrase := str(JOB_PHRASE.get(str(kinds.keys()[0]), ""))
			if not phrase.is_empty():
				what += " " + phrase
		parts.append("sent you on %s%s" % [what, _in(jobs)])
	var handed := events.filter(func(e): return str(e.get("kind", "")) == "handover")
	if not handed.is_empty():
		var last := str(handed[-1].get("detail", "")).strip_edges()
		parts.append(("handed you the %s" % last) if handed.size() == 1 and not last.is_empty() else "handed you %d items" % handed.size())
	var talks := events.filter(func(e): return str(e.get("kind", "")) == "lounge")
	if not talks.is_empty() and parts.size() < 2:
		parts.append("talked with you in the lounge%s" % _in(talks))
	var stories: Array = entry.get("stories", [])
	if not stories.is_empty() and parts.size() < 2:
		if stories.size() == 1:
			var sys := str(stories[0]).split("|")[1] if str(stories[0]).contains("|") else ""
			parts.append("came up in a story%s" % ((" at " + sys) if not sys.is_empty() else ""))
		else:
			parts.append("came up in %d stories" % stories.size())
	if parts.is_empty():
		parts.append("crossed your path")
	var text := " and ".join(parts)
	text = text.substr(0, 1).to_upper() + text.substr(1) + "."
	if is_hand:
		text = "Behind it all. " + text
	if not fate.is_empty():
		text += " Now %s." % fate
	return text


static func systems_of(entry: Dictionary) -> Array:
	var out: Array = []
	for e in entry.get("events", []):
		var s := str(e.get("system", ""))
		if not s.is_empty() and not out.has(s):
			out.append(s)
	for tag in entry.get("stories", []):
		var parts := str(tag).split("|")
		if parts.size() > 1 and not parts[1].is_empty() and not out.has(parts[1]):
			out.append(parts[1])
	return out


static func _in(events: Array) -> String:
	var systems: Array = []
	for e in events:
		var s := str(e.get("system", ""))
		if not s.is_empty() and not systems.has(s):
			systems.append(s)
	if systems.is_empty():
		return ""
	if systems.size() == 1:
		return " in %s" % systems[0]
	if systems.size() == 2:
		return " in %s and %s" % [systems[0], systems[1]]
	return " across %d systems" % systems.size()


# --- the game's entry point ---------------------------------------------------------

## N.O.V.A. now and then about her database (Abe, 2026-10-05): she keeps every
## face and every odd detail, to work out why they're out here. Vague, in
## keeping with her missing memory; nothing about the fixed cast. Lines approved
## by Abe 2026-10-05.
const NOVA_LINES := [
	"I'm keeping a file on everyone we meet. Don't ask me why. It feels like one of them matters.",
	"Another name for the database. If I collect enough of them, something has to click.",
	"Every face, every odd detail. I'm saving it all, Captain. Somewhere in there is the reason we're out here.",
	"I don't remember much from before we arrived. So I remember everything since. It's in the database, if you want it.",
	"Filed. It's probably nothing. I file the nothings too.",
]
const NOVA_CHANCE := 0.35
const NOVA_COOLDOWN_MS := 20 * 60 * 1000
static var _nova_last_ms := -NOVA_COOLDOWN_MS
static var _nova_bag: Array = []


## Records something that happened with a person, in the current system, now.
## Returns true when they're new to the database.
static func note(who: Dictionary, kind: String, detail: String = "") -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var story_manager := tree.root.get_node_or_null("/root/StoryManager")
	if story_manager == null or str(who.get("name", "")).strip_edges().is_empty():
		return false
	var gs := tree.root.get_node_or_null("/root/GlobalState")
	var clock := tree.root.get_node_or_null("/root/CampaignClock")
	var system := ""
	var ui = gs.get_ui_manager() if gs != null and gs.has_method("get_ui_manager") else null
	if ui != null and is_instance_valid(ui) and ui.has_method("_get_current_system_display_name"):
		system = str(ui.call("_get_current_system_display_name"))
	var minute := int(clock.get("total_minutes")) if clock != null else 0
	var book: Dictionary = story_manager.story_state.get("contacts", {})
	var key := key_for(str(who.get("name", "")), str(who.get("entity_id", "")))
	var is_new := not book.has(key) and not book.has(key_for(str(who.get("name", ""))))
	story_manager.story_state["contacts"] = record(book, who, system, kind, detail, minute)
	if is_new:
		_maybe_nova_remark(tree)
	return is_new


static func _maybe_nova_remark(tree: SceneTree) -> void:
	var now := Time.get_ticks_msec()
	if now - _nova_last_ms < NOVA_COOLDOWN_MS or randf() > NOVA_CHANCE:
		return
	var nova := tree.root.get_node_or_null("/root/Nova")
	if nova == null or not nova.has_method("speak"):
		return
	if _nova_bag.is_empty():
		_nova_bag = NOVA_LINES.duplicate()
		_nova_bag.shuffle()
	# Said a moment later, so it doesn't land on top of whoever's talking.
	var line: String = _nova_bag.pop_back()
	_nova_last_ms = now
	tree.create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(nova):
			nova.call("speak", line, 0, "thoughtful"))
