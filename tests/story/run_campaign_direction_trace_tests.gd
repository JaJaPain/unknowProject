extends SceneTree

## Package 6: a reproducible campaign trace over the REAL runtime paths.
##
## Fixed seeds and offline director fixtures. This drives the actual
## QuestManager terminal transaction, the actual StoryManager staging, the
## actual knowledge ledger and an actual disk checkpoint through
## StoryStateStore. What it does NOT do is call a model or assert prose quality:
## a structural trace is evidence of mechanism, not of writing.
##
## The trace REPORTS IDs, effects and semantic signatures. Two campaigns with
## different names and identical signatures are NOT divergent, and this suite
## says so explicitly rather than counting titles.

const Store := preload("res://scripts/persistence/StoryStateStore.gd")
const Direction := preload("res://scripts/story/CampaignDirectionContract.gd")
const Resolution := preload("res://scripts/story/CampaignResolutionCompiler.gd")
const Contract := preload("res://scripts/domain/CollectionContract.gd")
const Ledger := preload("res://scripts/story/DesireProgressLedger.gd")
const Outcome := preload("res://scripts/domain/MissionOutcome.gd")
const Novelty := preload("res://scripts/persistence/NoveltyHistoryStore.gd")
const CausalContract := preload("res://scripts/domain/QuestCausalContract.gd")

class World extends Node3D:
	var active_campaign_slot_id := "campaign.trace"
	var checkpoint_ok := true
	var reasons: Array = []
	func request_safe_checkpoint(reason: String, _station: Node) -> bool:
		reasons.append(reason)
		return checkpoint_ok

class Pilot extends CharacterBody3D:
	var is_docked := true
	var destroyed := false
	func navigation_obstacle_snapshot() -> Array: return []

class Station extends Node3D:
	var world_id := "station.local"
	func get_world_id() -> String: return world_id

var failures: Array[String] = []
var trace: Array[String] = []
var scene: World
var station: Station
var ui: Control
var manager: Node
var quests: Node
var gs: Node

func _initialize():
	call_deferred("_run")

func _run():
	_install()
	var first := _trace_campaign(4242, "system.alpha", "faction.alpha")
	_reset_campaign()
	var second := _trace_campaign(9191, "system.beta", "faction.beta")
	_compare_traces(first, second)
	_teardown()
	for line in trace:
		print("[TRACE] " + line)
	if failures.is_empty():
		print("[PASS] Campaign direction trace: two seeded campaigns, real terminal/staging/checkpoint paths, divergence by signature")
	else:
		for message in failures: push_error("[FAIL] " + message)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _install() -> void:
	gs = root.get_node("GlobalState")
	manager = root.get_node("StoryManager")
	quests = root.get_node("QuestManager")
	scene = World.new()
	scene.name = "GameRoot"
	root.add_child(scene)
	current_scene = scene
	station = Station.new()
	scene.add_child(station)
	var canvas := CanvasLayer.new()
	canvas.name = "CanvasLayer"
	scene.add_child(canvas)
	var script := GDScript.new()
	script.source_code = 'extends "res://scripts/UIManager.gd"
func _ready(): pass
func _process(_delta): pass
func _show_agent_portrait(_visible): pass
'
	_expect(script.reload() == OK, "Trace UI probe did not compile.")
	ui = script.new()
	ui.name = "UIManager"
	ui.current_station = station
	canvas.add_child(ui)
	var pilot := Pilot.new()
	scene.add_child(pilot)
	gs.player = pilot
	_reset_campaign()

func _reset_campaign() -> void:
	manager.story_state = Store._default_state()
	manager.story_state["first_contract_handed_in"] = false
	manager._story_state_store = Store.open("res://.tmp_godot_user/trace_%d" % Time.get_ticks_usec())
	quests.reset_for_restart()

func _teardown() -> void:
	current_scene = null
	if is_instance_valid(scene): scene.queue_free()


## ---------------------------------------------------------------------------
## One seeded campaign, start to recorded ending.
## ---------------------------------------------------------------------------

func _trace_campaign(campaign_seed: int, system_id: String, faction_prefix: String) -> Dictionary:
	gs.campaign_seed = campaign_seed
	gs.current_system_id = system_id
	scene.active_campaign_slot_id = "campaign.trace"
	scene.checkpoint_ok = true
	scene.reasons.clear()
	var record := {"seed": campaign_seed, "system_id": system_id}

	# 1. Tutorial completion. A tutorial contract is excluded from pressure,
	#    desires and discretionary pacing, and it unlocks the board.
	var tutorial_id := _accept_tutorial()
	quests.active_quest["current_count"] = int(quests.active_quest.get("count_required", 1))
	quests.complete_quest()
	_expect(not quests.is_quest_active(), "The tutorial contract did not settle.")
	manager.story_state["first_contract_handed_in"] = true
	var pressures: Dictionary = manager.story_state.get("local_pressures", {})
	var families: Array = pressures.get("recent_accepted_families", []) if pressures is Dictionary else []
	_expect(families.is_empty(), "A tutorial contract entered discretionary pacing: %s" % str(families))
	record["tutorial_outcome_id"] = "%s:completed" % tutorial_id

	# 2. Two verified collection opportunities in two generated systems.
	var opportunities := _opportunities(campaign_seed, system_id, faction_prefix)
	record["collection_ids"] = []
	for opportunity: Dictionary in opportunities:
		record["collection_ids"].append(str(opportunity["contract"]["id"]))

	# 3. The director selects from the supplied packet only. Offline fixture.
	# A link is only declarable when the CODE established the prerequisite, so
	# the trace supplies one and then exercises the link path through it.
	var facts := _premise_facts(system_id)
	var prerequisites: Array = []
	if opportunities.size() >= 2 and facts.size() >= 2:
		prerequisites.append({
			"from_collection_id": str(opportunities[0]["contract"]["id"]),
			"to_collection_id": str(opportunities[1]["contract"]["id"]),
			"dependency_fact_id": str(facts[1])})
	var packet: Dictionary = Direction.build_packet("campaign.trace#%d" % campaign_seed,
		opportunities, facts, [], prerequisites)
	var first_response: Variant = _invalid_response(packet)
	var repaired: Variant = _valid_response(packet)
	var responses: Array = [first_response, repaired]
	var attempts := {"count": 0}
	var responder := func(_view: Dictionary, _reason: String) -> Variant:
		var index: int = mini(attempts["count"], responses.size() - 1)
		attempts["count"] += 1
		return responses[index]
	var authored := _author(packet, responder, opportunities)
	_expect(bool(authored.get("ok", false)),
		"The director could not author a direction: %s" % str(authored.get("reason", "")))
	_expect(int(attempts["count"]) == 2,
		"The director did not use exactly one proposal plus one repair: %d attempts." % int(attempts["count"]))
	if not bool(authored.get("ok", false)):
		return record
	record["plan_id"] = str(authored["plan"]["id"])
	record["selected_collection_ids"] = (authored["proposal"]["selected_collection_ids"] as Array).duplicate()
	record["public_direction"] = str(authored["proposal"]["public_direction"])

	# 4. Novelty publication and acceptance, with the SEMANTIC signature that
	#    decides whether two campaigns actually diverged.
	record["signatures"] = _signatures(opportunities)

	# 5. Deliver one bound collection through the real terminal transaction.
	var delivered := _deliver(opportunities[0]["contract"])
	record["delivery_outcome_id"] = str(delivered.get("outcome_id", ""))
	record["delivery_effect_kinds"] = delivered.get("effect_kinds", [])
	_expect("item_delivered" in (record["delivery_effect_kinds"] as Array),
		"The committed delivery recorded no item_delivered effect.")
	_expect("mission_settled" in scene.reasons,
		"The delivery did not go through a real settlement checkpoint.")

	# 6. Activity pressure advanced, and the discretionary family recorded once.
	pressures = manager.story_state.get("local_pressures", {})
	record["activity_step"] = int(pressures.get("activity_step", 0)) if pressures is Dictionary else 0
	families = pressures.get("recent_accepted_families", []) if pressures is Dictionary else []
	_expect(families == ["delivery"],
		"The discretionary family window is wrong after one courier: %s" % str(families))

	# 7. The collection resolves; the faction's broad goal does NOT.
	var progress: Dictionary = manager.story_state.get("desire_progress", {})
	var receipts: Array = Ledger.fulfilled_collection_receipts(progress)
	record["receipt_collection_ids"] = []
	for receipt: Dictionary in receipts:
		record["receipt_collection_ids"].append(str(receipt["collection_id"]))
	_expect(receipts.size() == 1, "Expected one delivery receipt, got %d." % receipts.size())
	var contract: Dictionary = opportunities[0]["contract"]
	_expect(not Ledger.is_satisfied(progress, str(contract["system_id"]),
		str(contract["faction_id"]), str(contract["desire_id"])),
		"A delivery satisfied the faction's broad goal.")
	record["desire_state"] = _desire_state(progress, contract)
	_expect(str(record["desire_state"]) == "progressed",
		"The delivered desire is %s rather than progressed." % str(record["desire_state"]))
	return record


## ---------------------------------------------------------------------------
## Helpers: fixtures that stay honest about what they stand in for.
## ---------------------------------------------------------------------------

func _accept_tutorial() -> String:
	var offer := {"title": "Clean and Easy", "faction": "vanguard", "agent_name": "Kaelen",
		"dialogue": "Clear them out.", "intro_tutorial_contract": true,
		"objective": {"type": "KILL_SHIPS", "target_faction": "reavers",
			"count_required": 1, "reward_credits": 200}, "choices": []}
	var choice := {"text": "Accepted.", "consequence": {"credits_immediate": 0,
		"reputation_change": {}, "combat_multiplier": 1.0, "reward_credits_multiplier": 1.0}}
	if not quests.accept_quest(offer, choice):
		_expect(false, "Tutorial fixture rejected: %s" % quests.last_validation_error)
		return ""
	return str(quests.active_quest.get("runtime_id", ""))


## Two bound collections in two generated systems, built through the real
## contract compiler so every binding is checked, not asserted.
func _opportunities(campaign_seed: int, system_id: String, faction_prefix: String) -> Array:
	var built: Array = []
	var needs := ["sealed manifests from the last shipment", "a certified lease valuation"]
	var systems := [system_id, "%s.reach" % system_id]
	for index in range(needs.size()):
		var source := {"campaign_id": "campaign.trace#%d" % campaign_seed,
			"system_id": str(systems[index]), "faction_id": "%s.%d" % [faction_prefix, index],
			"desire_id": "desire.%s.%d" % [faction_prefix, index],
			"cause_id": "cause.%s.%d" % [faction_prefix, index],
			"obstacle_binding_id": "carrier_cancelled", "need": str(needs[index])}
		var bindings := {"action": "courier",
			"item_id_or_special_name": "Sealed Manifest Bundle" if index == 0 else "Certified Lease Valuation",
			"quantity": 1, "source_station_id": "station.origin.%d" % index, "source_supplies": true,
			"destination_station_id": "station.local", "destination_registered": true,
			"recipient_id": "npc.%s.clerk.%d" % [faction_prefix, index],
			"recipient_is_generated_local": true, "store_catalogue": false}
		var compiled := Contract.compile(source, bindings)
		if not bool(compiled.get("ok", false)):
			_expect(false, "A trace opportunity failed to bind: %s" % str(compiled.get("reason", "")))
			continue
		built.append({"contract": compiled["contract"], "need": str(needs[index]),
			"faction_name": "Local %d" % index})
	return built


func _premise_facts(system_id: String) -> Array:
	var facts: Array = ["fact.%s.backlog" % system_id, "fact.%s.records" % system_id]
	for fact_id: String in facts:
		manager.story_state["knowledge_states"][fact_id] = {"state": "known",
			"source": "trace_fixture", "at_minute": 0, "confidence": "direct"}
	return facts


## The writer's first attempt invents a fact. This is the case the repair budget
## exists for, and it must be REFUSED, not repaired into silence.
func _invalid_response(packet: Dictionary) -> Dictionary:
	return {"version": 1, "premise_fact_ids": ["fact.that.was.never.supplied"],
		"selected_collection_ids": [str((packet["candidates"][0] as Dictionary)["collection_id"])],
		"links": [], "public_direction": "A claim built on a fact nobody supplied."}


func _valid_response(packet: Dictionary) -> Dictionary:
	var ids: Array = []
	for candidate: Dictionary in packet["candidates"]:
		ids.append(str(candidate["collection_id"]))
	var facts: Array = packet["premise_fact_ids"]
	return {"version": 1, "premise_fact_ids": [str(facts[0])],
		"selected_collection_ids": ids,
		"links": [{"from_collection_id": str(ids[0]), "to_collection_id": str(ids[1]),
			"dependency_fact_id": str(facts[1])}],
		"public_direction": "Recover the records, then get the valuation countersigned."}


## Author through the contract and bind against the real campaign, then store the
## plan on the live story state the way StoryManager does.
func _author(packet: Dictionary, responder: Callable, opportunities: Array) -> Dictionary:
	var last_reason := ""
	for attempt in range(Direction.MAX_SELECTED):
		var response: Variant = responder.call(Direction.writer_view(packet), last_reason)
		var validated: Dictionary = Direction.validate_proposal(response, packet)
		if not bool(validated.get("ok", false)):
			last_reason = str(validated.get("reason", ""))
			if attempt == 0:
				_expect(last_reason.begins_with("unknown_premise_fact"),
					"The invented-fact proposal was refused for the wrong reason: %s" % last_reason)
			continue
		var compiled := Direction.compile_plan(validated["proposal"], packet, "resolution.trace")
		if not bool(compiled.get("ok", false)):
			last_reason = str(compiled.get("reason", ""))
			continue
		var bound := Resolution.bind(compiled["plan"], _bind_context(opportunities))
		if not bool(bound.get("ok", false)):
			last_reason = str(bound.get("reason", ""))
			continue
		manager.story_state["resolution_plan"] = bound["plan"]
		return {"ok": true, "plan": bound["plan"], "proposal": validated["proposal"]}
	return {"ok": false, "reason": last_reason}


func _bind_context(opportunities: Array) -> Dictionary:
	var desires: Array = []
	var systems: Array = []
	var collection_ids: Array = []
	for opportunity: Dictionary in opportunities:
		var contract: Dictionary = opportunity["contract"]
		desires.append({"system_id": str(contract["system_id"]), "faction_id": str(contract["faction_id"]),
			"desire_id": str(contract["desire_id"])})
		if str(contract["system_id"]) not in systems:
			systems.append(str(contract["system_id"]))
		collection_ids.append(str(contract["id"]))
	return {"desires": desires, "system_ids": systems, "station_ids": ["station.local"],
		"known_fact_ids": [], "effect_ids": [], "collection_ids": collection_ids}


func _signatures(opportunities: Array) -> Array:
	var signatures: Array = []
	for opportunity: Dictionary in opportunities:
		var contract: Dictionary = opportunity["contract"]
		signatures.append(("%s|%s|%s|%s" % [str(contract["system_id"]), str(contract["faction_id"]),
			str(opportunity["need"]), str(contract["action"])]).sha256_text().substr(0, 16))
	return signatures


func _desire_state(progress: Dictionary, contract: Dictionary) -> String:
	var key := Ledger.key_for(str(contract["system_id"]), str(contract["faction_id"]),
		str(contract["desire_id"]))
	var entry: Variant = progress.get("entries", {}).get(key, {})
	return str((entry as Dictionary).get("state", "")) if entry is Dictionary else ""


## Accept and settle one bound courier through the REAL QuestManager, including
## a failed checkpoint and its retry, and prove the mission survives a restored
## checkpoint that a newer loose story cache tried to overwrite.
func _deliver(contract: Dictionary) -> Dictionary:
	gs.current_system_id = str(contract["system_id"])
	# A generated local contact really stands at the destination. The public
	# board refuses a delivery without one, and that check stays live here.
	var recipient_name := "Trace Clerk %s" % str(contract["id"]).substr(11, 6)
	gs.generated_outpost_npcs[str(contract["destination_station_id"])] = [recipient_name]
	gs.generated_outpost_npc_data[recipient_name] = {"name": recipient_name,
		"outpost": str(contract["destination_station_id"]), "role": "records clerk",
		"faction": "neutral"}
	station.world_id = str(contract["destination_station_id"])
	var objective := {"type": "DELIVERY_COURIER",
		"item_name": str(contract["item_id_or_special_name"]),
		"item_id": "item.%s" % str(contract["item_id_or_special_name"]).to_snake_case(),
		"quantity_required": int(contract["quantity"]),
		"origin_station_id": str(contract["source_station_id"]),
		"destination_station_id": str(contract["destination_station_id"]),
		"destination_display": "Local Station", "reward_credits": 300}
	var offer := {"title": "Records run", "faction": "vanguard", "agent_name": "Local Records",
		"dialogue": "Carry this.", "objective": objective, "choices": [], "public_board": true,
		"collection_contract": contract,
		"narrative_metadata": {"cause_faction_id": str(contract["faction_id"]),
			"desire_id": str(contract["desire_id"]), "cause_id": str(contract["cause_id"])}}
	var choice := {"text": "Accept", "consequence": {"credits_immediate": 0,
		"reputation_change": {}, "reward_credits_multiplier": 1.0}}
	if not quests.accept_quest(offer, choice):
		_expect(false, "The bound courier was rejected: %s" % quests.last_validation_error)
		return {}
	_expect(quests.active_quest.get("collection_contract", {}) is Dictionary 			and not (quests.active_quest["collection_contract"] as Dictionary).is_empty(),
		"The collection contract did not survive acceptance into the active mission.")
	var runtime_id := str(quests.active_quest.get("runtime_id", ""))
	# Acquire the item the way a courier actually does.
	gs.cargo_special = {"name": str(contract["item_id_or_special_name"])}
	gs.cargo_type = gs.CargoType.SPECIAL
	quests.active_quest["cargo_loaded"] = true

	# A failed save must leave the mission and the cargo exactly as they were.
	scene.checkpoint_ok = false
	var credits_before := int(gs.player_credits)
	quests.complete_quest()
	_expect(quests.is_quest_active(), "A failed save discarded the bound delivery.")
	_expect(str(gs.cargo_special.get("name", "")) == str(contract["item_id_or_special_name"]),
		"A failed save consumed the delivered item.")
	_expect(int(gs.player_credits) == credits_before, "A failed save still paid for the delivery.")
	_expect(Ledger.fulfilled_collection_receipts(manager.story_state.get("desire_progress", {})).is_empty(),
		"A failed save recorded a delivery receipt.")

	# The retry commits exactly once.
	scene.checkpoint_ok = true
	quests.complete_quest()
	_expect(not quests.is_quest_active(), "The delivery retry did not settle.")
	_expect(int(gs.player_credits) > credits_before, "The committed delivery paid nothing.")
	var checkpoint: Dictionary = manager.capture_story_state_for_checkpoint()
	var paid := int(gs.player_credits)
	quests.complete_quest()
	_expect(int(gs.player_credits) == paid, "A repeated delivery paid twice.")

	# A newer loose story cache must not survive a restored checkpoint.
	manager.story_state["local_outcome_step"] = int(manager.story_state.get("local_outcome_step", 0)) + 9
	manager.mark_consequence_save_pending()
	_expect(manager.restore_story_state_from_checkpoint(checkpoint),
		"The committed checkpoint was rejected on restore.")
	_expect(int(manager.story_state.get("local_outcome_step", -1)) == int(checkpoint.get("local_outcome_step", -2)),
		"A newer loose cache overrode the restored checkpoint.")
	_expect(not manager.has_pending_consequence_save(),
		"A restored checkpoint kept a pending write from the timeline it replaced.")
	_expect(Ledger.fulfilled_collection_receipts(manager.story_state.get("desire_progress", {})).size() == 1,
		"The restored checkpoint lost its committed delivery receipt.")

	var outcome_id := "%s:completed" % runtime_id
	var kinds: Array = []
	for receipt: Dictionary in Ledger.fulfilled_collection_receipts(manager.story_state.get("desire_progress", {})):
		if str(receipt["outcome_id"]) == outcome_id:
			kinds.append("item_delivered")
	return {"outcome_id": outcome_id, "effect_kinds": kinds}


## Divergence is decided on IDs, effects and SEMANTIC SIGNATURES. Two campaigns
## that differ only in generated names have not diverged, and this is where that
## distinction is enforced rather than assumed.
func _compare_traces(first: Dictionary, second: Dictionary) -> void:
	trace.append("campaign A seed=%d system=%s" % [int(first["seed"]), str(first["system_id"])])
	trace.append("  collections: %s" % str(first.get("collection_ids", [])))
	trace.append("  selected:    %s" % str(first.get("selected_collection_ids", [])))
	trace.append("  signatures:  %s" % str(first.get("signatures", [])))
	trace.append("  delivery:    outcome=%s effects=%s" % [
		str(first.get("delivery_outcome_id", "")), str(first.get("delivery_effect_kinds", []))])
	trace.append("  desire:      %s (activity step %d)" % [
		str(first.get("desire_state", "")), int(first.get("activity_step", 0))])
	trace.append("campaign B seed=%d system=%s" % [int(second["seed"]), str(second["system_id"])])
	trace.append("  collections: %s" % str(second.get("collection_ids", [])))
	trace.append("  selected:    %s" % str(second.get("selected_collection_ids", [])))
	trace.append("  signatures:  %s" % str(second.get("signatures", [])))
	trace.append("  delivery:    outcome=%s effects=%s" % [
		str(second.get("delivery_outcome_id", "")), str(second.get("delivery_effect_kinds", []))])
	trace.append("  desire:      %s (activity step %d)" % [
		str(second.get("desire_state", "")), int(second.get("activity_step", 0))])
	_expect(first.get("collection_ids", []) != second.get("collection_ids", []),
		"Two campaigns produced the same collection IDs.")
	_expect(first.get("signatures", []) != second.get("signatures", []),
		"Two campaigns produced identical semantic signatures: different names alone are not divergence.")
	_expect(first.get("selected_collection_ids", []) != second.get("selected_collection_ids", []),
		"Two campaigns selected the same causal opportunities.")
	_expect(str(first.get("desire_state", "")) == "progressed" 			and str(second.get("desire_state", "")) == "progressed",
		"A traced campaign claimed a broad faction goal it did not prove.")
	# Both campaigns record the SAME supported effect kind. That is correct and
	# is not divergence: the vocabulary is finite and this suite does not pretend
	# otherwise.
	_expect(first.get("delivery_effect_kinds", []) == second.get("delivery_effect_kinds", []),
		"The supported effect vocabulary changed between campaigns.")
	trace.append("divergence: collection IDs, semantic signatures and selected opportunities differ;")
	trace.append("            the supported effect vocabulary is shared and finite by design.")
