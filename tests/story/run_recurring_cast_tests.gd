extends SceneTree

const CastRules := preload("res://scripts/story/premise/RecurringCast.gd")
const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")
const Arcs := preload("res://scripts/story/premise/ArcEngine.gd")
const HISTORY_PATH := "user://test_recurring_cast_history.json"

var _failures: Array[String] = []


func _initialize() -> void:
	_test_rules()
	_test_campaign()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HISTORY_PATH))
	if _failures.is_empty():
		print("[PASS] Recurring cast tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _person(eid: String, name: String) -> Dictionary:
	return {"kind": "person", "entity_id": eid, "display_name": name}


func _test_rules() -> void:
	var state := {
		"arcs": {
			"arc.0001": {"shown": true, "status": "resolved", "system_id": "sys.a", "cast": {"a": _person("npc.mara", "Mara Venn"), "b": _person("npc.dead", "Olek Stray")}},
			"arc.0002": {"shown": true, "status": "resolved", "system_id": "sys.b", "cast": {"a": _person("npc.mara", "Mara Venn"), "b": _person("npc.pal", "Tully Ash")}},
			"arc.0003": {"shown": true, "status": "active", "system_id": "sys.c", "cast": {"a": _person("npc.busy", "Ren Kasso")}},
			"arc.0004": {"shown": false, "status": "active", "system_id": "sys.c", "cast": {"a": _person("npc.unseen", "Never Met")}},
			"arc.0005": {"shown": true, "status": "resolved", "system_id": "sys.c", "cast": {"a": _person("npc.jail", "Ivo Brandt"), "b": _person("npc.plain", "Sia Morrow")}},
		},
		"fates": {"npc.mara": ["promoted", "alive_grudge"], "npc.dead": ["dead"], "npc.pal": ["owes_debt"], "npc.jail": ["imprisoned"]},
	}
	_check(CastRules.attitude(["promoted", "alive_grudge"]) == "bitter", "the last ending sets the feeling")
	_check(CastRules.attitude(["dead", "promoted"]) == "gone", "the dead stay dead")
	var ids := CastRules.candidates(state).map(func(c): return str(c["id"]))
	_check(ids == ["npc.mara", "npc.pal", "npc.plain"], "candidates: alive, free, met, strongest feelings first; got %s" % str(ids))
	var names := {"sys.a": "Vessa", "sys.b": "Korrin"}
	var note := CastRules.history_note(state, "npc.mara", names, "arc.0009")
	_check(note == "They have dealt with the pilot twice before; last time in Korrin, it went badly for them, they still blame the pilot for it, and they are not hiding it.", "history note: %s" % note)
	_check(CastRules.history_note(state, "npc.pal", names, "arc.0002") == "", "the current arc is not history")
	_check(CastRules.history_note(state, "npc.nobody", names) == "", "strangers have no history")
	_check(CastRules.history_note(state, "npc.plain", {}, "arc.0009") == "They have dealt with the pilot once before.", "no fate, no system name: a plain note")


## A long simulated campaign: people come back, never twice at once, never from the grave.
func _test_campaign() -> void:
	var d = DirectorType.new()
	d.history_path = HISTORY_PATH
	d.use_showrunner = false
	d.reset_for_new_campaign(777)
	var returns := 0
	var now := 0
	for n in range(1, 13):
		var w := _world(n)
		d.ensure_arcs(w, now)
		d.board_postings(w, now)
		# Nobody is in two live stories at once.
		var live_people := {}
		for arc_id in Arcs.active_arc_ids(d.state):
			for role in (Arcs.arc(d.state, arc_id)["cast"] as Dictionary).values():
				if str(role.get("kind", "")) == "person":
					var eid := str(role["entity_id"])
					_check(not live_people.has(eid) or live_people[eid] == arc_id, "%s is in two live stories (%s card %s, %s card %s)" % [eid, live_people.get(eid, ""), Arcs.arc(d.state, str(live_people.get(eid, arc_id))).get("card_id", ""), arc_id, Arcs.arc(d.state, arc_id)["card_id"]])
					live_people[eid] = arc_id
					if bool(role.get("reused", false)):
						var fates: Array = (d.state.get("fates", {}) as Dictionary).get(eid, [])
						_check(not ("dead" in fates) and not ("imprisoned" in fates), "%s came back dead or imprisoned" % eid)
		# Let every live arc settle so fates accumulate.
		now += 20 * 1440
		d.tick(now)
	for arc_id in (d.state["arcs"] as Dictionary).keys():
		for role in (d.state["arcs"][arc_id]["cast"] as Dictionary).values():
			if bool(role.get("reused", false)):
				returns += 1
	print("[RecurringCast] %d returning faces over 12 systems" % returns)
	_check(returns >= 2, "people should come back in a long campaign (got %d)" % returns)
	d.free()


func _world(n: int) -> Dictionary:
	return {
		"system_id": "system.gen_%d" % n, "system_display": "System %d" % n,
		"system_seed": 1000 + n, "star_type": ["red", "blue", "yellow", "white"][n % 4],
		"post_tutorial": true, "is_first_system": false, "investigation_fallback": true,
		"main_station": {"id": "system.gen_%d" % n, "display": "Main %d" % n},
		"outposts": [{"id": "outpost.%d_a" % n, "display": "Reach %d" % n}, {"id": "outpost.%d_b" % n, "display": "Kova %d" % n}],
		"factions": [{"id": "faction.generated.a%d" % n, "display_name": "Guild %d" % n},
			{"id": "faction.generated.b%d" % n, "display_name": "Consortium %d" % n},
			{"id": "faction.generated.c%d" % n, "display_name": "Collective %d" % n}],
		"hostile_factions": ["reavers", "dustborn"], "known_npcs": [],
		"store_items": [],
	}
