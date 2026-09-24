extends SceneTree

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const Arcs := preload("res://scripts/story/premise/ArcEngine.gd")
const Hand := preload("res://scripts/story/premise/HiddenHand.gd")
const Radio := preload("res://scripts/story/premise/RadioBroadcaster.gd")
const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_broadcast_contents()
	_test_director_airs_each_item_once()
	if _failures.is_empty():
		print("[PASS] Radio tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _card(card_id: String) -> Dictionary:
	return {"id": card_id, "schema_version": 1, "scale": "local",
		"roles": [{"id": "boss", "kind": "person"}, {"id": "dock", "kind": "place"}],
		"beats": [{"n": 1, "function": "setup", "missions": [{"verb": "kill_ships", "requester": "boss", "target": "dock",
			"outcome_tags": ["won"], "routes": {"won": "resolution:win"}}]}],
		"resolutions": [{"id": "win", "seeds": [], "consequences": [
			{"type": "deed", "tag": "broke_it", "public_summary": "A pilot broke {role:boss}'s grip on the docks."},
			{"type": "system_state", "add": ["strike"], "remove": []},
			{"type": "law_change", "law": "curfew", "change": "enacted"}]}, {"id": "lose"}],
		"default_resolution": "lose",
		"radio_hooks": ["{role:boss} denies everything on {system} channels."],
		"loose_threads": [{"id": "t_radio", "surface": "radio", "detail": "The same call sign keeps signing off a minute early.", "can_carry_methods": ["bribery"]}]}


func _test_broadcast_contents() -> void:
	var lib = LibraryType.new()
	lib.load_from_array([_card("premise.far"), _card("premise.here")])
	var cast := {"boss": {"kind": "person", "entity_id": "npc.b", "display_name": "Dara Holt"}, "dock": {"kind": "place", "entity_id": "st", "display_name": "Dock"}}
	var s := Hand.begin_season(Arcs.empty_state(), 3, 0)
	# A story in a far system, finished at minute 100: its deed must travel.
	var far := Arcs.start_arc(s, lib.get_card("premise.far"), "system.far", cast, 0)
	s = Arcs.apply_mission_result(far["state"], lib, far["arc_id"], 1, 0, "completed", "", 100)
	# A live story here, with a radio thread.
	var here := Arcs.start_arc(s, lib.get_card("premise.here"), "system.here", cast, 150)
	s = here["state"]
	var card_here: Dictionary = lib.get_card("premise.here")
	card_here["loose_threads"][0]["can_carry_methods"] = [str(Hand.main_story(s)["method"])]
	s = Hand.seed_threads(s, card_here, here["arc_id"], 3)
	var world := {"system_id": "system.here", "system_display": "Vessa", "system_names": {"system.far": "Kora", "system.here": "Vessa"}}
	var early := Radio.broadcast(s, lib, world, 200)
	var kinds := early.map(func(i): return str(i["kind"]))
	_check("headline" in kinds, "live stories here should make headlines")
	_check(not "rumour" in kinds, "a distant deed must not arrive before it has had time to travel")
	var headline := str(early.filter(func(i): return i["kind"] == "headline")[0]["text"])
	_check(headline == "Dara Holt denies everything on Vessa channels.", "headlines are filled with the cast: %s" % headline)
	_check("thread" in kinds, "a radio loose thread should air here")
	var later := Radio.broadcast(s, lib, world, 100 + Radio.DEED_TRAVEL_MINUTES + 1)
	var rumours := later.filter(func(i): return i["kind"] == "rumour")
	_check(rumours.size() == 1 and str(rumours[0]["text"]).contains("Kora") and str(rumours[0]["text"]).contains("Dara Holt"),
		"the deed should arrive as a rumour naming where it came from: %s" % str(rumours))
	var far_world := {"system_id": "system.far", "system_display": "Kora", "system_names": world["system_names"]}
	var far_items := Radio.broadcast(s, lib, far_world, 300)
	var far_kinds := far_items.map(func(i): return str(i["kind"]))
	_check("local_deed" in far_kinds, "where it happened, the deed is local talk")
	_check("news" in far_kinds and far_items.any(func(i): return str(i["text"]).contains("strike")), "a strike the story caused becomes news")
	_check(far_items.any(func(i): return str(i["text"]).contains("curfew")), "a law the story enacted becomes news")
	_check(load("res://scripts/story/ReservedTopics.gd").is_clean(JSON.stringify(later + far_items)), "radio text stays clear of reserved topics")


func _test_director_airs_each_item_once() -> void:
	var d = DirectorType.new()
	d.use_showrunner = false
	d.history_path = "user://test_radio_history.json"
	d.reset_for_new_campaign(7)
	var world := {"system_id": "system.gen_2", "system_display": "Two", "system_seed": 2, "star_type": "red",
		"post_tutorial": true, "is_first_system": false, "investigation_fallback": true,
		"main_station": {"id": "system.gen_2", "display": "Main"}, "outposts": [{"id": "o.a", "display": "A"}],
		"factions": [{"id": "faction.generated.x", "display_name": "X", "spawn_key": "x"},
			{"id": "faction.generated.y", "display_name": "Y", "spawn_key": "y"},
			{"id": "faction.generated.z", "display_name": "Z", "spawn_key": "z"}],
		"hostile_factions": ["reavers"], "known_npcs": []}
	d.ensure_arcs(world, 0)
	var seen_ids := {}
	var count := 0
	while count < 50:
		var item: Dictionary = d.next_radio_item(world, 10)
		if item.is_empty():
			break
		_check(not seen_ids.has(item["id"]), "an item must not air twice in one visit")
		seen_ids[item["id"]] = true
		_check(not str(item["text"]).contains("{role:"), "radio text is filled")
		count += 1
	_check(count >= 1, "a system with live stories should have something on the radio")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_radio_history.json"))
	d.free()
