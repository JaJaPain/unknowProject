extends SceneTree

# N.O.V.A.'s database (ContactsLedger): lines read like Abe's examples, people
# known by name and by story id are one entry, story people and fates merge
# in, the revealed culprit is marked, pins stick.

const Ledger := preload("res://scripts/story/ContactsLedger.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_job_lines()
	_test_handover_and_lounge()
	_test_story_people_fates_and_hand()
	_test_name_then_id_merge()
	_test_pins_and_order()
	if _failures.is_empty():
		print("[PASS] ContactsLedger (all cases)")
		quit(0)
		return
	for f in _failures:
		push_error(f)
	print("[FAIL] ContactsLedger: %d case(s)" % _failures.size())
	quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_failures.append(msg)


func _one(book: Dictionary) -> Dictionary:
	return Ledger.entries(book)[0]


func _test_job_lines() -> void:
	var b := {}
	for i in 3:
		b = Ledger.record(b, {"name": "Dan Orel", "role": "Agent"}, "Myrion Watch", "job", "DELIVER_ORE", 10 + i)
	_check(_one(b)["line"] == "Sent you on 3 jobs for ore in Myrion Watch.", "3 ore jobs: %s" % _one(b)["line"])
	var c := Ledger.record({}, {"name": "Eric Vale"}, "Kova", "job", "PICKUP_SPECIAL", 5)
	_check(_one(c)["line"] == "Sent you on a job to fetch something in Kova.", "one pickup job: %s" % _one(c)["line"])
	c = Ledger.record(c, {"name": "Eric Vale"}, "Zaren", "job", "DELIVER_ORE", 6)
	_check(_one(c)["line"] == "Sent you on 2 jobs in Kova and Zaren.", "mixed jobs in two systems: %s" % _one(c)["line"])


func _test_handover_and_lounge() -> void:
	var b := Ledger.record({}, {"name": "Vale Venn"}, "Zaren Relay", "handover", "Audit-Proof Relay", 3)
	_check(_one(b)["line"] == "Handed you the Audit-Proof Relay.", "handover: %s" % _one(b)["line"])
	var l := Ledger.record({}, {"name": "Mariska Vonn"}, "Kova", "lounge", "", 1)
	_check(_one(l)["line"] == "Talked with you in the lounge in Kova.", "lounge: %s" % _one(l)["line"])


func _test_story_people_fates_and_hand() -> void:
	var people := [{"entity_id": "npc.arc_0001.villain", "name": "Oren Vask", "story": "The Last Patrol", "system": "Myrion", "minute": 50},
		{"entity_id": "npc.arc_0002.villain", "name": "Oren Vask", "story": "Sins of the Father", "system": "Kova", "minute": 80}]
	var shown := Ledger.entries({}, people)
	_check(shown.size() == 2, "two story ids are two people until known otherwise")
	var one: Dictionary = Ledger.entries({}, [people[0]])[0]
	_check(one["line"] == "Came up in a story at Myrion.", "story person: %s" % one["line"])
	var dead: Dictionary = Ledger.entries({}, [people[0]], {"npc.arc_0001.villain": ["dead"]})[0]
	_check(str(dead["line"]).ends_with("Now dead."), "fate shown: %s" % dead["line"])
	var hand: Dictionary = Ledger.entries({}, [people[0]], {}, "npc.arc_0001.villain")[0]
	_check(bool(hand["is_hand"]) and str(hand["line"]).begins_with("Behind it all."), "culprit marked: %s" % hand["line"])


func _test_name_then_id_merge() -> void:
	var b := Ledger.record({}, {"name": "Oren Vask"}, "Myrion", "lounge", "", 1)
	b = Ledger.record(b, {"name": "Oren Vask", "entity_id": "npc.arc_0001.villain"}, "Myrion", "job", "DELIVER_ORE", 2)
	_check(b.size() == 1 and b.has("npc.arc_0001.villain"), "known by name, then by story id: one entry: %s" % str(b.keys()))
	var merged := Ledger.entries(b, [{"entity_id": "npc.arc_0001.villain", "name": "Oren Vask", "story": "The Last Patrol", "system": "Myrion", "minute": 3}])
	_check(merged.size() == 1, "story person merges with the recorded entry")


func _test_pins_and_order() -> void:
	var b := Ledger.record({}, {"name": "Old Contact"}, "A", "lounge", "", 1)
	b = Ledger.record(b, {"name": "New Contact"}, "B", "lounge", "", 9)
	_check(str(Ledger.entries(b)[0]["name"]) == "New Contact", "newest first")
	b = Ledger.set_pinned(b, Ledger.key_for("Old Contact"), true)
	var old: Dictionary = Ledger.entries(b).filter(func(e): return e["name"] == "Old Contact")[0]
	_check(bool(old["pinned"]), "a pin sticks")
