extends SceneTree

## Leverage: a revealed secret about a client is kept, and each can be used
## once: sold, exposed (standing and a deed) or used for blackmail (a real
## job the captain can take).
##   Godot --headless --path . --script res://tests/story/run_leverage_tests.gd --log-file <path> -- --baseline-offline

const Leverage := preload("res://scripts/story/premise/Leverage.gd")
const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")
const Adapter := preload("res://scripts/domain/MissionAdapter.gd")
const PanelType := preload("res://scripts/ui/LeveragePanel.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var lie := {"runtime_id": "mission.runtime.lie", "twist_reveal_kind": "client_lie", "twist_target_name": "Vessa Orl",
		"twist_reveal": "She is skimming the relief fund.", "faction": "faction.guild", "system_id": "sys.a"}
	var cargo := {"runtime_id": "mission.runtime.crate", "twist_reveal_kind": "wrong_cargo", "twist_target_name": "Dask",
		"twist_true_cargo": "military targeting cores", "system_id": "sys.a"}
	var e1 := Leverage.from_twist(lie, 100)
	var e2 := Leverage.from_twist(cargo, 100)
	_check(e1["kind"] == "client_secret" and e1["subject"] == "Vessa Orl" and str(e1["summary"]).contains("relief fund"), "a client's lie is leverage")
	_check(e2["kind"] == "smuggling" and str(e2["summary"]).contains("military targeting cores"), "so is smuggled cargo: %s" % e2["summary"])
	_check(Leverage.from_twist({"twist_reveal_kind": "rival", "twist_target_name": "X"}, 0).is_empty(), "a rival on the job is not")
	var entries := Leverage.add(Leverage.add([], e1), e1)
	_check(entries.size() == 1, "kept once")

	# Other sources: an overheard intercept, a flight recorder.
	var heard := Leverage.make("intercept", "thread:th.0002", "Vessa Orl", "Overheard: she paid the guild twice.", "sys.a", 50)
	_check(heard["kind"] == "intercept" and Leverage.value_of(heard) > 0, "an overheard conversation is leverage")
	_check(Leverage.make("recorder", "x", "", "text", "sys.a", 0).is_empty(), "but only on someone")
	var faint := preload("res://scripts/story/activities/FaintTransmissions.gd").pick({"arcs": {"arc.1": {"system_id": "sys.a", "cast": {
		"broker": {"kind": "person", "entity_id": "npc.broker", "display_name": "Vessa Orl"}}}},
		"main_story": {"threads": [{"id": "th.1", "arc_id": "arc.1", "surface": "dialogue", "detail": "{role:broker} paid twice.", "seen": false}]}},
		"sys.a", "Tarn", [], 1)
	_check(faint["speaker_name"] == "Vessa Orl", "an intercept knows who was speaking")

	var world := {"system_id": "sys.a", "outposts": [{"id": "outpost.a", "display": "Rusk Outpost"}],
		"main_station": {"id": "station.main", "display": "Tarn Station"},
		"factions": [{"id": "faction.guild", "display_name": "Ore Guild"}, {"id": "faction.watch", "display_name": "Tarn Watch"}]}
	var sold := Leverage.use(e1, "sell", world, {})
	_check(bool(sold["ok"]) and int(sold["credits"]) == Leverage.value_of(e1), "selling pays")
	var lawful := {"id": "faction.watch", "display_name": "Tarn Watch"}
	var exposed := Leverage.use(e1, "expose", world, lawful)
	_check(float(exposed["standing"]["faction.watch"]) > 0.0 and float(exposed["standing"]["faction.guild"]) < 0.0, "exposing wins the law and loses the subject's side")
	_check(str(exposed["deed"]["public_summary"]).contains("Vessa Orl"), "and is a deed")
	var squeeze := Leverage.use(e1, "blackmail", world, lawful)
	var offer: Dictionary = squeeze["offer"]
	_check(offer["objective"]["type"] == "PICKUP_SPECIAL" and offer["objective"]["target_outpost"] == "outpost.a", "blackmail is a pickup at their dead drop")
	_check(int(offer["objective"]["reward_credits"]) > Leverage.value_of(e1), "and pays more than selling (with the risk of the run)")
	var built := Adapter.build_active_state(offer, offer["choices"][0], "mission.runtime.blackmail", "sys.a", 0)
	_check(built["validation"].is_valid(), "the blackmail job is a real mission: %s" % built["validation"].summary())
	_check(not bool(Leverage.use(e1, "blackmail", {"outposts": []}, lawful)["ok"]), "no dead drop here, no blackmail")

	# The director keeps it, spends it once, records the deed, and saves it.
	var d = DirectorType.new()
	root.add_child(d)
	_check(not d.record_leverage(lie, 100).is_empty() and d.record_leverage(lie, 100).is_empty(), "recorded once")
	d.record_leverage(cargo, 100)
	_check(d.leverage_items().size() == 2, "two secrets held")
	var effect: Dictionary = d.use_leverage(str(e1["id"]), "expose", world, 120)
	_check(bool(effect["ok"]) and d.leverage_items().size() == 1, "used once")
	_check(not bool(d.use_leverage(str(e1["id"]), "sell", world, 121).get("ok", true)), "and not twice")
	_check((d.state["deeds"] as Array).any(func(x): return str(x.get("tag", "")) == "exposed_client_secret"), "the exposure is a deed")
	var lawful_pick: Dictionary = d.lawful_faction(world)
	_check(not lawful_pick.is_empty(), "someone hears it")
	var failed_drop: Dictionary = d.use_leverage(str(e2["id"]), "blackmail", {"outposts": []}, 122)
	_check(not bool(failed_drop["ok"]) and d.leverage_items().size() == 1, "a blackmail with no drop spends nothing")
	_check(not d.record_leverage_entry(heard).is_empty() and d.record_leverage_entry(heard).is_empty(), "an intercept is kept once")
	_check(d.leverage_items().size() == 2, "alongside the rest")
	var reloaded = DirectorType.new()
	reloaded.load_from_dict(d.to_dict())
	_check(reloaded.leverage_items().size() == 2, "leverage survives a save")
	reloaded.free()

	# The panel lists it and asks for a use.
	var panel = PanelType.new()
	root.add_child(panel)
	var asked := []
	panel.use_requested.connect(func(id: String, how: String) -> void: asked.append([id, how]))
	panel.show_entries(d.leverage_items())
	_check(panel.visible, "the panel opens")
	var buttons: Array = panel.find_children("*", "Button", true, false)
	var blackmail_btn: Button = null
	for b: Button in buttons:
		if b.text.begins_with("Blackmail"):
			blackmail_btn = b
	_check(blackmail_btn != null, "with a blackmail button")
	if blackmail_btn != null:
		blackmail_btn.pressed.emit()
		_check(asked.size() == 1 and asked[0][1] == "blackmail", "which asks for it")

	panel.free()
	d.free()
	if _failures.is_empty():
		print("[PASS] Leverage")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
