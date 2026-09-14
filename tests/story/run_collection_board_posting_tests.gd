extends SceneTree

## Package 3, the last leg: a bound collection actually reaching the player.
##
## This drives the LIVE path — StoryManager compiling opportunities from the
## real world capture, the real posting builder, the real ordinary
## posting-ownership machinery, the real board presenter, and the real
## QuestManager acceptance and settlement — rather than asserting that a helper
## returns a dictionary. A generated offer that nobody can accept is not a
## feature, so acceptance and settlement are part of the claim.

const Store := preload("res://scripts/persistence/StoryStateStore.gd")
const Ledger := preload("res://scripts/story/DesireProgressLedger.gd")
const Desire := preload("res://scripts/persistence/GeneratedFactionDesire.gd")
const Contract := preload("res://scripts/domain/CollectionContract.gd")

class World extends Node3D:
	var active_campaign_slot_id := "campaign.collection"
	var checkpoint_ok := true
	var reasons: Array = []
	func request_safe_checkpoint(reason: String, _station: Node) -> bool:
		reasons.append(reason)
		return checkpoint_ok

class Pilot extends CharacterBody3D:
	var is_docked := true
	var destroyed := false
	func navigation_obstacle_snapshot() -> Array: return []

## A real generated outpost: it carries the station_type and world_id the
## outpost registry reads, so the live recipient-station check runs for real
## rather than being satisfied by a stub.
class Station extends Node3D:
	var world_id := "station.local"
	var display_name := "Local Station"
	var station_type := "outpost"
	func get_world_id() -> String: return world_id

var failures: Array[String] = []
var scene: World
var station: Station
var origin: Station
var ui: Control
var manager: Node
var quests: Node
var gs: Node
var board_script

func _initialize():
	call_deferred("_run")

func _run():
	_install()
	_test_posting_reaches_the_board()
	_test_acceptance_and_settlement()
	_test_withheld_when_the_recipient_leaves()
	_test_live_direction_eligibility()
	_test_live_repair_budget()
	_test_live_pending_fallback()
	_teardown()
	if failures.is_empty():
		print("[PASS] Collection board postings: generated from bound needs, published once, accepted, delivered and recorded; live direction eligibility, repair budget and pending fallback")
	else:
		for message in failures: push_error("[FAIL] " + message)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)


## A generated faction whose need is one of the eight supported delivery edges.
func _agendas() -> Array:
	for index in range(8000):
		var desire := Desire.build("collection_fixture_%d" % index, "local", index)
		if not Contract.is_supported_need(str(desire.get("need", ""))):
			continue
		if str(desire.get("need", "")) == "replacement assemblies":
			continue  # store-purchasable; this fixture is about the courier edge
		return [{"faction_id": "faction.local.records", "faction_name": "Local Records",
			"desire": desire}]
	return []


func _install() -> void:
	gs = root.get_node("GlobalState")
	manager = root.get_node("StoryManager")
	quests = root.get_node("QuestManager")
	var agendas := _agendas()
	if agendas.is_empty():
		_expect(false, "Could not generate a faction with a supported delivery need.")
		return
	board_script = load("res://scripts/domain/PublicBoardOfferBuilder.gd")
	var config = load("res://scripts/generation/SystemConfig.gd").new()
	config.story_pack = {"faction_agendas": agendas}
	board_script.story_config_override_for_tests = config

	scene = World.new()
	scene.name = "GameRoot"
	root.add_child(scene)
	current_scene = scene
	station = Station.new()
	station.world_id = "station.local"
	station.display_name = "Local Station"
	scene.add_child(station)
	station.add_to_group("station")
	origin = Station.new()
	origin.world_id = "station.origin"
	origin.display_name = "Origin Depot"
	origin.position = Vector3(900.0, 0.0, 0.0)
	scene.add_child(origin)
	origin.add_to_group("station")

	var canvas := CanvasLayer.new()
	canvas.name = "CanvasLayer"
	scene.add_child(canvas)
	var script := GDScript.new()
	script.source_code = 'extends "res://scripts/UIManager.gd"
var writer_requests: Array = []
func _ready(): pass
func _process(_delta): pass
func _request_public_board_text_attempt(_index, offer, _critique, _attempt): writer_requests.append(offer)
func _show_agent_portrait(_visible): pass
'
	_expect(script.reload() == OK, "Collection board probe did not compile.")
	ui = script.new()
	ui.name = "UIManager"
	ui.current_station = station
	canvas.add_child(ui)
	ui.public_board_panel = Panel.new()
	ui.add_child(ui.public_board_panel)
	ui.public_board_list = VBoxContainer.new()
	ui.public_board_panel.add_child(ui.public_board_list)
	for field in ["agent_panel", "dock_panel"]:
		ui.set(field, Panel.new())
		ui.add_child(ui.get(field))
	for field in ["agent_name_label", "agent_subtitle_label", "agent_dialogue_label"]:
		ui.set(field, Label.new())
		ui.agent_panel.add_child(ui.get(field))
	ui.agent_choices_container = VBoxContainer.new()
	ui.agent_panel.add_child(ui.agent_choices_container)
	ui.agent_back_btn = Button.new()
	ui.agent_panel.add_child(ui.agent_back_btn)

	var pilot := Pilot.new()
	scene.add_child(pilot)
	gs.player = pilot
	gs.current_system_id = "system.local"
	# Both stations are live entities, so they appear in the outpost registry the
	# plausibility validator consults when the mission is revalidated.
	var entities: Array[Node3D] = [station, origin]
	gs.active_system_entities = entities
	# A generated local contact really stands at the posting station.
	gs.generated_outpost_npcs["station.local"] = ["Mara Vance"]
	gs.generated_outpost_npc_data["Mara Vance"] = {"name": "Mara Vance",
		"outpost": "station.local", "role": "records clerk", "delivery_role": "clerk",
		"faction": "neutral"}
	manager.story_state = Store._default_state()
	manager.story_state["first_contract_handed_in"] = true
	manager._story_state_store = Store.open("res://.tmp_godot_user/collection_board_%d" % Time.get_ticks_usec())

func _teardown() -> void:
	if board_script != null:
		board_script.story_config_override_for_tests = null
	var empty_entities: Array[Node3D] = []
	gs.active_system_entities = empty_entities
	gs.generated_outpost_npcs.erase("station.local")
	gs.generated_outpost_npc_data.erase("Mara Vance")
	current_scene = null
	if is_instance_valid(scene): scene.queue_free()


func _collection_index() -> int:
	for index in range(ui.public_board_current_offers.size()):
		if bool(ui.public_board_current_offers[index].get("collection_posting", false)):
			return index
	return -1


## A bound local need reaches the visible board as a real posting, with a
## persisted identity, and reopening the board neither duplicates it nor
## reallocates its publication ID.
func _test_posting_reaches_the_board() -> void:
	if scene == null: return
	ui.public_board_panel.hide()
	ui._render_public_board_offers()
	_expect(_collection_index() < 0,
		"A hidden board published a collection posting nobody could see.")
	ui.public_board_panel.show()
	ui._render_public_board_offers()
	var index := _collection_index()
	_expect(index >= 0, "A bound local need never reached the visible board.")
	if index < 0: return
	var posting: Dictionary = ui.public_board_current_offers[index]
	_expect(not str(posting.get("publication_id", "")).is_empty(),
		"The collection posting was shown without a persisted publication ID.")
	_expect(not str(posting.get("collection_id", "")).is_empty(),
		"The collection posting did not cite its collection.")
	var quest: Dictionary = posting["quest_data"]
	_expect(quest.get("collection_contract", {}) is Dictionary 			and not (quest["collection_contract"] as Dictionary).is_empty(),
		"The published posting lost its collection contract.")
	_expect(str(quest["delivery_recipient_name"]) == "Mara Vance",
		"The posting did not name the generated local contact.")
	_expect(str(posting["body"]).contains("Mara Vance") 			and str(posting["body"]).contains("Origin Depot"),
		"The posting body lost its real origin or recipient: %s" % str(posting["body"]))
	# Generated prose never touches a collection posting.
	for request: Dictionary in ui.writer_requests:
		_expect(not bool(request.get("collection_posting", false)),
			"A collection posting was sent to the generic board writer.")
	# Reopening reuses the same identity and does not duplicate the posting.
	var publication_id := str(posting["publication_id"])
	ui._render_public_board_offers()
	var reopened_index := _collection_index()
	_expect(reopened_index >= 0, "Reopening the board dropped the collection posting.")
	var collection_count := 0
	for offer: Dictionary in ui.public_board_current_offers:
		if bool(offer.get("collection_posting", false)):
			collection_count += 1
	_expect(collection_count == 1, "Reopening the board duplicated the collection posting.")
	if reopened_index >= 0:
		_expect(str(ui.public_board_current_offers[reopened_index]["publication_id"]) == publication_id,
			"Reopening the board reallocated the publication ID.")
	# A collection posting is neutral activity: no relief, no modified payout.
	_expect(not bool(posting.get("pressure_relief", false)),
		"A collection posting claimed pressure relief no track rule supports.")
	_expect(int(posting["base_reward"]) == manager.COLLECTION_POSTING_REWARD,
		"A collection posting did not pay on the ordinary courier scale.")


## Offer -> source acquisition -> local recipient -> settlement -> reload, on the
## real acceptance and terminal paths.
func _test_acceptance_and_settlement() -> void:
	if scene == null: return
	ui.public_board_panel.show()
	ui._render_public_board_offers()
	var index := _collection_index()
	if index < 0:
		_expect(false, "No collection posting to accept.")
		return
	var posting: Dictionary = ui.public_board_current_offers[index]
	var contract: Dictionary = posting["quest_data"]["collection_contract"]
	var offer_id := str(posting.get("offer_id", ""))
	scene.checkpoint_ok = true
	scene.reasons.clear()
	ui._on_public_board_offer_accept(index)
	_expect(quests.is_quest_active(), "The generated collection posting could not be accepted.")
	if not quests.is_quest_active(): return
	var runtime_id := str(quests.active_quest.get("runtime_id", ""))
	# The contract survived acceptance onto the active mission.
	var active: Variant = quests.active_quest.get("collection_contract", {})
	_expect(active is Dictionary and str((active as Dictionary).get("id", "")) == str(contract["id"]),
		"The collection contract did not survive acceptance onto the active mission.")
	# Acceptance bound the posting to the real runtime mission.
	var entries: Dictionary = manager.story_state.get("investigation_board", {}).get("entries", {})
	var entry: Dictionary = entries.get(offer_id, {}) if entries.get(offer_id, {}) is Dictionary else {}
	_expect(str(entry.get("runtime_mission_id", "")) == runtime_id,
		"Acceptance did not record the real runtime mission ID on its posting.")
	_expect(str(entry.get("status", "")) == "retired",
		"An accepted collection posting stayed on the board.")

	# Source acquisition: the courier consignment is issued at the origin.
	_expect(str(gs.cargo_special.get("name", "")) == str(contract["item_id_or_special_name"]),
		"Accepting the courier did not put its consignment in the hold.")

	# A failed save leaves the job retryable with its cargo intact.
	scene.checkpoint_ok = false
	var credits_before := int(gs.player_credits)
	quests.complete_quest()
	_expect(quests.is_quest_active(), "A failed save discarded the collection job.")
	_expect(str(gs.cargo_special.get("name", "")) == str(contract["item_id_or_special_name"]),
		"A failed save consumed the consignment.")
	_expect(int(gs.player_credits) == credits_before, "A failed save still paid for the delivery.")
	_expect(Ledger.fulfilled_collection_receipts(
		manager.story_state.get("desire_progress", {})).is_empty(),
		"A failed save recorded a delivery receipt.")

	# The retry commits exactly once.
	scene.checkpoint_ok = true
	quests.complete_quest()
	_expect(not quests.is_quest_active(), "The retry did not settle the collection job.")
	_expect(int(gs.player_credits) > credits_before, "The committed delivery paid nothing.")
	_expect("mission_settled" in scene.reasons, "The delivery did not use a real settlement checkpoint.")
	var paid := int(gs.player_credits)
	quests.complete_quest()
	_expect(int(gs.player_credits) == paid, "A repeated delivery paid twice.")

	# The recorded fact is the delivery, with the person who actually took it.
	var receipts: Array = Ledger.fulfilled_collection_receipts(
		manager.story_state.get("desire_progress", {}))
	_expect(receipts.size() == 1, "Expected one delivery receipt, got %d." % receipts.size())
	if receipts.size() == 1:
		var receipt: Dictionary = receipts[0]
		_expect(str(receipt["collection_id"]) == str(contract["id"]), "The receipt cited the wrong collection.")
		_expect(str(receipt["recipient_id"]) == str(contract["recipient_id"]),
			"The receipt recorded the wrong recipient.")
		_expect(str(receipt["destination_station_id"]) == str(contract["destination_station_id"]),
			"The receipt recorded the wrong destination.")
		_expect(str(receipt["outcome_id"]) == "%s:completed" % runtime_id,
			"The receipt lost its source outcome.")
	# The delivery proves the delivery, not the faction's broad goal.
	var progress: Dictionary = manager.story_state.get("desire_progress", {})
	_expect(not Ledger.is_satisfied(progress, str(contract["system_id"]),
		str(contract["faction_id"]), str(contract["desire_id"])),
		"A delivered document satisfied the faction's legal goal.")
	# Save and reload: the committed receipt survives its own checkpoint.
	var checkpoint: Dictionary = manager.capture_story_state_for_checkpoint()
	manager.story_state["desire_progress"] = {}
	_expect(manager.restore_story_state_from_checkpoint(checkpoint),
		"The committed checkpoint was rejected on restore.")
	_expect(Ledger.fulfilled_collection_receipts(
		manager.story_state.get("desire_progress", {})).size() == 1,
		"The restored checkpoint lost its delivery receipt.")
	# The fulfilled collection retires its own cause, so it is never reposted.
	_expect(str(contract["cause_id"]) in Ledger.retired_cause_ids(
		manager.story_state.get("desire_progress", {})),
		"A fulfilled collection did not retire its cause.")
	ui._render_public_board_offers()
	_expect(_collection_index() < 0,
		"A fulfilled collection was reposted to the board as fresh work.")


## A binding that goes stale withholds the posting instead of publishing it
## against a person who is no longer there.
func _test_withheld_when_the_recipient_leaves() -> void:
	if scene == null: return
	# Reset the campaign so the cause is fresh again, then remove the contact.
	manager.story_state = Store._default_state()
	manager.story_state["first_contract_handed_in"] = true
	gs.generated_outpost_npcs["station.local"] = []
	ui.public_board_panel.show()
	ui._render_public_board_offers()
	_expect(_collection_index() < 0,
		"A posting was published to a station with no generated contact to receive it.")
	var compiled: Dictionary = manager.collection_opportunities(station)
	_expect((compiled.get("opportunities", []) as Array).is_empty(),
		"An opportunity bound a recipient who is not there.")
	var named := false
	for entry: Dictionary in compiled.get("withheld", []):
		if str(entry.get("reason", "")) == "no_local_recipient":
			named = true
			_expect(not str(entry.get("missing_binding", "")).is_empty(),
				"A withheld edge did not name its missing binding.")
	_expect(named, "The missing recipient was not reported as the reason.")
	# Put the contact back and the edge returns.
	gs.generated_outpost_npcs["station.local"] = ["Mara Vance"]
	ui._render_public_board_offers()
	_expect(_collection_index() >= 0,
		"Restoring the local contact did not bring the bound edge back.")


## ---------------------------------------------------------------------------
## Package 5 live path: the same packet, validation and repair budget, driven
## through the real async control flow with the writer stubbed out.
## ---------------------------------------------------------------------------

## Public facts the direction may cite. The schema requires at least one, so a
## campaign with none cannot author a direction at all.
func _seed_known_facts() -> void:
	for fact_id: String in ["fact.local.backlog", "fact.local.registry"]:
		manager.story_state["knowledge_states"][fact_id] = {"state": "known",
			"source": "collection_board_fixture", "at_minute": 0, "confidence": "direct"}


func _valid_direction(view: Dictionary) -> Dictionary:
	var ids: Array = []
	for candidate: Dictionary in view["candidates"]:
		ids.append(str(candidate["collection_id"]))
	var facts: Array = view["premise_fact_ids"]
	return {"version": 1, "premise_fact_ids": [str(facts[0])] if not facts.is_empty() else [],
		"selected_collection_ids": [str(ids[0])], "links": [],
		"public_direction": "Get the shipment records back to the registry."}


## A new campaign authors a direction; a legacy save never enters the path.
func _test_live_direction_eligibility() -> void:
	if scene == null: return
	manager.story_state = Store._default_state()
	manager.story_state["first_contract_handed_in"] = true
	_seed_known_facts()
	# No eligibility marker: this is a legacy campaign.
	var attempts := {"count": 0}
	manager.direction_requester_override_for_tests = func(view: Dictionary, _note: String, done: Callable) -> void:
		attempts["count"] += 1
		done.call({"ok": true, "proposal": _valid_direction(view)})
	_expect(not manager.maybe_author_campaign_direction_live(station),
		"A legacy campaign entered the direction-authoring path.")
	_expect(int(attempts["count"]) == 0, "A legacy campaign called the writer.")
	# A campaign generated after directions existed is eligible.
	manager.story_state["campaign_direction_eligible"] = true
	_expect(manager.maybe_author_campaign_direction_live(station),
		"An eligible new campaign did not ask for a direction.")
	_expect(int(attempts["count"]) == 1, "The eligible campaign did not call the writer exactly once.")
	var plan: Dictionary = manager.story_state.get("resolution_plan", {})
	_expect(int(plan.get("version", 0)) == 2 and str(plan.get("status", "")) == "active",
		"The authored direction did not become an active v2 plan: %s" % str(plan.get("status", "")))
	var provenance: Dictionary = manager.story_state.get("campaign_direction_provenance", {})
	_expect(int(provenance.get("attempt", 0)) == 1, "Provenance recorded the wrong attempt.")
	_expect(not str(provenance.get("public_direction", "")).is_empty(),
		"Provenance lost the writer's public direction.")
	# An existing plot is never replaced.
	_expect(not manager.maybe_author_campaign_direction_live(station),
		"A second board visit re-authored a campaign that already has a direction.")
	_expect(int(attempts["count"]) == 1, "A board visit called the writer again.")
	manager.direction_requester_override_for_tests = Callable()


## One proposal plus at most one repair. The repair carries the exact reason.
func _test_live_repair_budget() -> void:
	if scene == null: return
	manager.story_state = Store._default_state()
	manager.story_state["first_contract_handed_in"] = true
	_seed_known_facts()
	manager.story_state["campaign_direction_eligible"] = true
	var notes: Array = []
	manager.direction_requester_override_for_tests = func(view: Dictionary, note: String, done: Callable) -> void:
		notes.append(note)
		if notes.size() == 1:
			# An invented fact: structurally valid, entirely unsupported.
			var bad := _valid_direction(view)
			bad["premise_fact_ids"] = ["fact.that.was.never.supplied"]
			done.call({"ok": true, "proposal": bad})
			return
		done.call({"ok": true, "proposal": _valid_direction(view)})
	_expect(manager.maybe_author_campaign_direction_live(station),
		"An eligible campaign did not ask for a direction.")
	_expect(notes.size() == 2, "The repair budget used %d attempts, not two." % notes.size())
	if notes.size() == 2:
		_expect(str(notes[0]).is_empty(), "The first attempt carried a correction note.")
		_expect(str(notes[1]).begins_with("unknown_premise_fact"),
			"The repair did not name the reason the first answer was rejected: %s" % str(notes[1]))
	_expect(int(manager.story_state.get("resolution_plan", {}).get("version", 0)) == 2,
		"The repaired proposal did not become a plan.")
	_expect(int(manager.story_state.get("campaign_direction_provenance", {}).get("attempt", 0)) == 2,
		"Provenance did not record that the plan came from the repair attempt.")
	manager.direction_requester_override_for_tests = Callable()


## Nothing static stands in for a direction the writer could not produce, and
## the campaign stays playable.
func _test_live_pending_fallback() -> void:
	if scene == null: return
	manager.story_state = Store._default_state()
	manager.story_state["first_contract_handed_in"] = true
	_seed_known_facts()
	manager.story_state["campaign_direction_eligible"] = true
	var calls := {"count": 0}
	manager.direction_requester_override_for_tests = func(_view: Dictionary, _note: String, done: Callable) -> void:
		calls["count"] += 1
		done.call({"ok": false, "reason": "http_failed_result_1_code_0"})
	_expect(manager.maybe_author_campaign_direction_live(station),
		"An eligible campaign did not ask for a direction.")
	_expect(int(calls["count"]) == 2, "A failing writer was retried %d times, not twice." % int(calls["count"]))
	_expect(manager.story_state.get("resolution_plan", {}).is_empty(),
		"A failed direction still produced a plan.")
	_expect(str(manager.campaign_direction_pending_reason()) == "http_failed_result_1_code_0",
		"The pending record did not keep the real failure reason: %s" % manager.campaign_direction_pending_reason())
	# Still authorable later, and ordinary board work is unaffected.
	_expect(manager.may_author_campaign_direction(),
		"A failed direction locked the campaign out of trying again.")
	ui.public_board_panel.show()
	ui._render_public_board_offers()
	_expect(_collection_index() >= 0,
		"A campaign with no direction lost its ordinary collection postings.")
	# With no public fact to cite, the schema makes a valid answer impossible.
	# Refusing before the call is what stops the repair budget being burned on a
	# request that could never have succeeded.
	manager.story_state = Store._default_state()
	manager.story_state["first_contract_handed_in"] = true
	manager.story_state["campaign_direction_eligible"] = true
	calls["count"] = 0
	_expect(not manager.maybe_author_campaign_direction_live(station),
		"A campaign with no public premise facts still called the writer.")
	_expect(int(calls["count"]) == 0, "The writer was called with nothing it could cite.")
	var refused: Dictionary = manager._open_campaign_direction(station)
	_expect(str(refused.get("reason", "")) == "no_public_premise_facts",
		"The missing-facts refusal did not name itself: %s" % str(refused.get("reason", "")))
	manager.direction_requester_override_for_tests = Callable()
