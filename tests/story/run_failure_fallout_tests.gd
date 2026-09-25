extends SceneTree

## Failing forward: a failed, abandoned or expired job changes its system for
## a while (a shortage raises store prices, unchecked raiders spawn more),
## the radio says why, and it wears off.
##   Godot --headless --path . --script res://tests/story/run_failure_fallout_tests.gd --log-file <path> -- --baseline-offline

const Fallout := preload("res://scripts/story/premise/FailureFallout.gd")
const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")
const StoreDef := preload("res://scripts/economy/StoreDefinition.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var names := {"system": "Tarn", "requester": "Vessa Orl", "place": "Kova Station", "faction": "Reavers"}
	var courier := {"runtime_id": "mission.runtime.a", "objective_type": "DELIVERY_COURIER", "system_id": "sys.a", "faction": "faction.guild", "agent_name": "Vessa Orl"}
	var kill := {"runtime_id": "mission.runtime.b", "objective_type": "KILL_SHIPS", "system_id": "sys.a"}

	_check(Fallout.for_mission(courier, "completed", 100, names).is_empty(), "finishing a job leaves no fallout")
	var short := Fallout.for_mission(courier, "expired", 100, names)
	_check(short["family"] == "supply" and short["state"] == "shortage" and float(short["environment"]["store_price_mult"]) > 1.0, "a missed delivery is a shortage")
	_check(str(short["radio"]).contains("Vessa Orl") or str(short["radio"]).contains("Kova Station"), "the radio says what happened: %s" % short["radio"])
	_check(int(short["until_minute"]) == 100 + int(Fallout.deck()["duration_minutes"]), "for a while")
	var raid := Fallout.for_mission(kill, "abandoned", 100, names)
	_check(raid["family"] == "security" and float(raid["environment"]["hostile_spawn_mult"]) > 1.0, "an unfinished kill job emboldens raiders")
	_check(Fallout.for_mission({"objective_type": "SOMETHING_NEW", "system_id": "sys.a"}, "abandoned", 0, names).is_empty(), "unknown jobs leave nothing")

	# Two failures compound, capped; nothing leaks to other systems; it wears off.
	var env := Fallout.environment([short, short, short, short])
	_check(float(env["store_price_mult"]) == 2.0, "compounding is capped: %s" % str(env))
	_check(Fallout.active([short], "sys.b", 120).is_empty(), "only where it happened")
	_check(Fallout.active([short], "sys.a", int(short["until_minute"])).is_empty(), "and it wears off")

	# The director keeps it, puts it on the radio once, and saves it.
	var d = DirectorType.new()
	root.add_child(d)
	var rec: Dictionary = d.record_failure(courier, "expired", 100, names)
	_check(not rec.is_empty() and d.record_failure(courier, "expired", 101, names).is_empty(), "recorded once per job")
	_check(d.active_fallout("sys.a", 200).size() == 1, "active in its system")
	var item: Dictionary = d.next_radio_item({"system_id": "sys.a"}, 200)
	_check(str(item.get("text", "")) == str(rec["radio"]), "the radio leads with it: %s" % str(item))
	_check(str(d.next_radio_item({"system_id": "sys.a"}, 201).get("id", "")) != str(rec["id"]), "and says it once per visit")
	var reloaded = DirectorType.new()
	reloaded.load_from_dict(d.to_dict())
	_check(reloaded.active_fallout("sys.a", 200).size() == 1, "fallout survives a save")
	reloaded.free()

	# The store feels it.
	var saved_mult: float = StoreDef.system_price_mult
	var store = StoreDef.new()
	var item_def = load("res://scripts/economy/StoreItemDefinition.gd").new()
	item_def.item_id = "repair_kit"
	item_def.base_price = 100
	item_def.max_stock = 5
	store.add_item(item_def)
	var normal: int = store.get_price("repair_kit", "neutral")
	StoreDef.system_price_mult = float(Fallout.environment([rec]).get("store_price_mult", 1.0))
	_check(store.get_price("repair_kit", "neutral") > normal, "a shortage raises store prices (%d -> %d)" % [normal, store.get_price("repair_kit", "neutral")])
	StoreDef.system_price_mult = saved_mult

	# Raiders read it through the environment.
	var gs: Node = root.get_node("GlobalState")
	gs.fallout_environment = Fallout.environment([raid])
	_check(float(gs.environment_value("hostile_spawn_mult", 1.0)) > 1.0, "hostile spawns read the fallout")
	gs.fallout_environment = {}

	d.free()
	if _failures.is_empty():
		print("[PASS] Failure fallout")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
