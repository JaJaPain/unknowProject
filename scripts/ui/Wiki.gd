extends RefCounted

## The in-game wiki (pause menu > WIKI; Abe, 2026-09-30). Entries live in
## data/content/wiki_entries.json. Basics start unlocked; the rest unlock the
## first time the player meets that system, via Wiki.unlock("receiver") from
## wherever it is taught. Unlocks are kept in StoryManager.story_state, so they
## save with the campaign. New entries are marked until read.

const ENTRIES_PATH := "res://data/content/wiki_entries.json"
const UNLOCKED_KEY := "wiki_unlocked"
const UNREAD_KEY := "wiki_unread"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(ENTRIES_PATH, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


## Controller-aware control names. Entry text says "{approach}", never "Q".
## When controller support lands: fill in each control's "controller" label in
## wiki_entries.json and have the input code set `prefer_controller` from the
## last device used. Until then a connected pad with no label falls back to
## the keyboard name.
static var prefer_controller := false


static func using_controller() -> bool:
	return prefer_controller or not Input.get_connected_joypads().is_empty()


static func control_label(control_id: String) -> String:
	var spec: Dictionary = data().get("controls", {}).get(control_id, {})
	if spec.is_empty():
		return control_id
	if using_controller() and not str(spec.get("controller", "")).is_empty():
		return str(spec["controller"])
	# A live InputMap binding wins over the written label (rebinding shows up).
	var action := str(spec.get("action", ""))
	if not action.is_empty() and InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var key := ev as InputEventKey
				var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
				if code != 0:
					return OS.get_keycode_string(code)
	return str(spec.get("keyboard", control_id))


## An entry's body with every {control} token filled in.
static func body_text(e: Dictionary) -> String:
	var text := str(e.get("body", ""))
	for control_id in data().get("controls", {}).keys():
		text = text.replace("{%s}" % control_id, control_label(str(control_id)))
	return text


static func categories() -> Array:
	return data().get("categories", [])


static func all_entries() -> Array:
	return data().get("entries", [])


static func entry(id: String) -> Dictionary:
	for e in all_entries():
		if str(e.get("id", "")) == id:
			return e
	return {}


static func _story_state() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return {}
	var story := tree.root.get_node_or_null("StoryManager")
	if story == null:
		return {}
	return story.story_state


static func is_unlocked(id: String) -> bool:
	var e := entry(id)
	if e.is_empty():
		return false
	if bool(e.get("unlocked", false)):
		return true
	return _story_state().get(UNLOCKED_KEY, []).has(id)


static func is_unread(id: String) -> bool:
	return _story_state().get(UNREAD_KEY, []).has(id)


static func mark_read(id: String) -> void:
	var unread: Array = _story_state().get(UNREAD_KEY, [])
	unread.erase(id)


## Entries the player can read now, in file order.
static func unlocked_entries() -> Array:
	var out: Array = []
	for e in all_entries():
		if is_unlocked(str(e.get("id", ""))):
			out.append(e)
	return out


static func unread_count() -> int:
	return _story_state().get(UNREAD_KEY, []).size()


## Unlock an entry the first time the player meets it. Safe to call often:
## only the first call does anything. Returns true when newly unlocked.
static func unlock(id: String) -> bool:
	if is_unlocked(id) or entry(id).is_empty():
		return false
	var state := _story_state()
	if state.is_empty():
		return false
	if not state.has(UNLOCKED_KEY):
		state[UNLOCKED_KEY] = []
	if not state.has(UNREAD_KEY):
		state[UNREAD_KEY] = []
	state[UNLOCKED_KEY].append(id)
	state[UNREAD_KEY].append(id)
	var tree := Engine.get_main_loop() as SceneTree
	var gs := tree.root.get_node_or_null("GlobalState") if tree != null else null
	if gs != null and gs.has_method("emit_chatter"):
		gs.emit_chatter("WIKI", "New entry: %s. Esc > Wiki to read it any time." % str(entry(id).get("title", id)), Color(0.55, 0.85, 1.0))
	return true
