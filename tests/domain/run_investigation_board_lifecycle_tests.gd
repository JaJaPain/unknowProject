extends SceneTree

const Board := preload("res://scripts/domain/InvestigationBoardLifecycle.gd")
const Desire := preload("res://scripts/persistence/GeneratedFactionDesire.gd")
const Store := preload("res://scripts/persistence/StoryStateStore.gd")
const Adapter := preload("res://scripts/domain/MissionAdapter.gd")

class FailedStore extends RefCounted:
	func is_valid() -> bool: return true
	func save_state(_state: Dictionary) -> Dictionary: return {"ok": false}

class World extends Node3D:
	var active_campaign_slot_id := "campaign.test"
	var checkpoint_ok := false
	var captured := {}
	func request_safe_checkpoint(_reason: String, _station: Node) -> bool:
		captured = {"quest": get_node("/root/QuestManager").capture_all_quests(), "story_state": get_node("/root/StoryManager").capture_story_state_for_checkpoint()}
		return checkpoint_ok

class Pilot extends CharacterBody3D:
	var is_docked := true
	var destroyed := false
	func navigation_obstacle_snapshot() -> Array: return []

class Station extends Node3D:
	var world_id := "station.local"
	var display_name := "Local Station"
	func get_world_id() -> String: return world_id

class DockUI extends Control:
	var current_station: Node3D

var failures: Array[String] = []

func _initialize():
	call_deferred("_run")

func _run():
	var context := _context()
	if context["agendas"].size() != 2:
		_expect(false, "Could not build coherent fixture agendas.")
	else:
		_test_publication(context)
		_test_failures(context)
		_test_store_and_manager(context)
		_test_local_context(context)
		_test_board_save_aliases(context)
	if failures.is_empty():
		print("[PASS] Investigation board lifecycle: local causes, publication, persistence, stale drafts and failed commits")
	else:
		for message in failures: push_error("[FAIL] " + message)
	quit(0 if failures.is_empty() else 1)

func _context() -> Dictionary:
	var agendas: Array = []
	var found := {}
	for i in range(6000):
		var desire := Desire.build("investigation_fixture_%d" % i, "local", i)
		if desire["obstacle_binding_id"] != "dispatch_backlog": continue
		var key := ""
		if desire["need"] == "survey data from a drift it cannot reach": key = "survey"
		if desire["need"] == "filed claim evidence" and desire["goal"] == "clear its name on a salvage claim": key = "claims"
		if key.is_empty() or found.has(key): continue
		found[key] = true
		agendas.append({"faction_id": "faction.local." + key, "faction_name": "Local " + key.capitalize(), "desire": desire})
		if found.size() == 2: break
	return {"campaign_id": "campaign.test", "campaign_seed": 89, "system_id": "system.local", "station_id": "station.local",
		"station_display": "Local Station", "post_tutorial_unlocked": true, "reward_budget": 401, "agendas": agendas,
		"world": {"ok": true, "system_id": "system.local", "stations": [{"id": "station.local", "position": Vector3.ZERO}], "hazards": [], "gates": []}}

func _test_publication(context: Dictionary):
	var empty := Board.empty_state(89)
	var prepared := Board.prepare(empty, context)
	_expect(prepared.get("ok", false), "Preparation failed: %s" % prepared)
	if not prepared.get("ok", false): return
	_expect(empty["entries"].is_empty() and empty["selection"]["bags"].is_empty(), "Preparation mutated caller state.")
	_expect(prepared["state"]["selection"]["bags"].is_empty(), "Prefetch retired a shape.")
	var published := Board.publish(prepared["state"], prepared["offer_id"], context)
	_expect(published.get("ok", false), "Publication failed.")
	if not published.get("ok", false): return
	_expect(not published["state"]["selection"]["bags"].is_empty(), "Published shape was not retired.")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(published["state"]))
	var reopened := Board.prepare(restored, context)
	var repeated := Board.publish(reopened["state"], reopened["offer_id"], context)
	_expect(repeated.get("ok", false), "Restored publication failed: %s" % repeated)
	if not repeated.get("ok", false): return
	_expect(repeated["state"] == restored and repeated["posting"] == published["posting"], "Reopen/redraw changed persisted terms or bag.")
	var quest: Dictionary = repeated["posting"]["quest_data"]
	var adapted := Adapter.build_active_state(quest, quest["choices"][0], "mission.runtime.test", "system.local", 10)
	_expect(adapted["validation"].is_valid(), "Published offer fails actual mission adapter: %s" % [adapted["validation"].errors])
	_expect(adapted.get("state", {}).get("narrative_metadata", {}).get("causal_contract", {}) == quest["causal_contract"], "Accepted mission lost causal contract.")
	var reordered := context.duplicate(true)
	reordered["agendas"].reverse()
	_expect(Board.prepare(empty, reordered)["posting"] == prepared["posting"], "Scene/agenda order changed the offer.")
	var retired := Board.release(restored, prepared["offer_id"])
	var next := Board.prepare(retired, context)
	_expect(next.get("ok", false) and next.get("offer_id", "") != prepared["offer_id"], "Next posting repeated the same cause.")
	if next.get("ok", false):
		_expect(next["posting"]["quest_data"]["objective"]["shape_id"] != quest["objective"]["shape_id"], "Alternative shape immediately repeated.")
		var next_pub := Board.publish(next["state"], next["offer_id"], context)
		var all_used := Board.release(next_pub["state"], next["offer_id"])
		_expect(not Board.prepare(all_used, context).get("ok", false), "Exhausted causes invented another posting.")
	var cancelled := Board.release(prepared["state"], prepared["offer_id"])
	_expect(cancelled["entries"].is_empty() and cancelled["selection"]["bags"].is_empty(), "Cancelling unseen draft retired it.")

func _test_failures(context: Dictionary):
	var locked := context.duplicate(true)
	locked["post_tutorial_unlocked"] = false
	_expect(not Board.prepare({}, locked).get("ok", false), "Tutorial offered an investigation.")
	var bad := context.duplicate(true)
	for agenda: Dictionary in bad["agendas"]: agenda["desire"]["need"] = "fuel it can afford"
	_expect(not Board.prepare({}, bad).get("ok", false), "Incoherent need produced an investigation.")
	bad = context.duplicate(true)
	bad["reward_budget"] = 0
	_expect(not Board.prepare({}, bad).get("ok", false), "Missing budget invented a reward.")
	var prepared := Board.prepare({}, context)
	if not prepared.get("ok", false): return
	bad = context.duplicate(true)
	bad["world"]["hazards"] = [{"center": Vector3.ZERO, "radius": 100000.0}]
	_expect(not Board.prepare({}, bad).get("ok", false), "Impossible placement produced an offer.")
	_expect(not Board.publish(prepared["state"], prepared["offer_id"], bad).get("ok", false), "Changed obstacles passed publication.")
	bad = context.duplicate(true)
	bad["agendas"] = []
	_expect(not Board.publish(prepared["state"], prepared["offer_id"], bad).get("ok", false), "Missing cause passed publication.")
	var broken: Dictionary = prepared["state"].duplicate(true)
	broken["entries"][prepared["offer_id"]]["posting"]["quest_data"]["objective"]["investigation"]["sites"][0]["position"] = []
	_expect(not Board.validate(broken).is_valid(), "Corrupt saved site passed board validation.")

func _test_store_and_manager(context: Dictionary):
	var manager: Node = root.get_node("StoryManager")
	var before: Dictionary = manager.story_state.duplicate(true)
	var old_store: Variant = manager._story_state_store
	manager.story_state = Store._default_state()
	manager._story_state_store = FailedStore.new()
	var prepared: Dictionary = manager.prepare_investigation_board_offer(context)
	var rejected: Dictionary = manager.publish_investigation_board_offer(prepared, context)
	_expect(rejected.get("reason", "") == "story_save_failed" and manager.story_state["investigation_board"].is_empty(), "Failed save published or consumed the offer.")
	var path := "res://.tmp_godot_user/investigation_board_%d" % Time.get_ticks_usec()
	var store := Store.open(path)
	_expect(store.is_valid(), "Could not create test story store.")
	manager._story_state_store = store
	var published: Dictionary = manager.publish_investigation_board_offer(prepared, context)
	_expect(published.get("ok", false), "Durable publication failed: %s" % published)
	if published.get("ok", false):
		var reopened := Store.open(path)
		_expect(reopened.is_valid() and reopened.data["investigation_board"] == manager.story_state["investigation_board"], "Real story store did not preserve published posting.")
		var checkpoint: Dictionary = manager.capture_story_state_for_checkpoint()
		manager.story_state = Store._default_state()
		_expect(manager.restore_story_state_from_checkpoint(checkpoint), "Checkpoint refused valid posting.")
		_expect(manager.story_state["investigation_board"] == published["state"], "Checkpoint changed posting ownership or evidence.")
		var corrupt := checkpoint.duplicate(true)
		corrupt["investigation_board"]["entries"][published["offer_id"]]["status"] = "published_twice"
		_expect(not manager.restore_story_state_from_checkpoint(corrupt), "Checkpoint accepted damaged offer state.")
		_expect(manager.story_state["investigation_board"] == published["state"], "Rejected checkpoint replaced current board.")
		var stale: Dictionary = manager.publish_investigation_board_offer(prepared, context)
		_expect(not stale.get("ok", false), "Stale pre-publication draft overwrote newer state.")
	manager.story_state = before
	manager._story_state_store = old_store

func _expect(condition: bool, message: String):
	if not condition: failures.append(message)

func _test_local_context(context: Dictionary):
	var manager: Node = root.get_node("StoryManager")
	var gs: Node = root.get_node("GlobalState")
	var old_story: Dictionary = manager.story_state.duplicate(true)
	var old_store: Variant = manager._story_state_store
	manager._story_state_store = Store.open("res://.tmp_godot_user/investigation_accept_%d" % Time.get_ticks_usec())
	var old_player: Variant = gs.player
	var old_system: String = gs.current_system_id
	var old_scene: Node = current_scene
	var board = load("res://scripts/domain/PublicBoardOfferBuilder.gd")
	var old_config: Variant = board.story_config_override_for_tests
	var config = load("res://scripts/generation/SystemConfig.gd").new()
	config.story_pack = {"faction_agendas": context["agendas"]}
	board.story_config_override_for_tests = config
	var scene := World.new()
	scene.name = "GameRoot"
	root.add_child(scene)
	current_scene = scene
	var station := Station.new()
	scene.add_child(station)
	station.add_to_group("station")
	var canvas := CanvasLayer.new()
	canvas.name = "CanvasLayer"
	scene.add_child(canvas)
	var script := GDScript.new()
	script.source_code = 'extends "res://scripts/UIManager.gd"\nvar writer_requests: Array = []\nfunc _ready(): pass\nfunc _process(_delta): pass\nfunc _request_public_board_text_attempt(_index, offer, _critique, _attempt): writer_requests.append(offer)\nfunc _show_agent_portrait(_visible): pass\n'
	_expect(script.reload() == OK, "Board presenter probe did not compile.")
	var ui: Control = script.new()
	ui.name = "UIManager"
	ui.current_station = station
	canvas.add_child(ui)
	ui.public_board_panel = Panel.new()
	ui.add_child(ui.public_board_panel)
	ui.public_board_list = VBoxContainer.new()
	ui.public_board_panel.add_child(ui.public_board_list)
	ui.public_board_panel.hide()
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
	manager.story_state = Store._default_state()
	_expect(not manager.prepare_local_investigation_board_offer(station).get("ok", false), "Local entry point bypassed tutorial state.")
	manager.story_state["first_contract_handed_in"] = true
	ui._render_public_board_offers()
	_expect(manager.story_state["investigation_board"].is_empty(), "Hidden board retired an unseen investigation.")
	ui.public_board_panel.show()
	ui._render_public_board_offers()
	var investigation_index := -1
	for index in range(ui.public_board_current_offers.size()):
		if ui.public_board_current_offers[index].get("investigation_posting", false): investigation_index = index
	_expect(investigation_index >= 0, "Visible board did not present its investigation.")
	for request: Dictionary in ui.writer_requests:
		_expect(not request.get("investigation_posting", false), "Investigation truth entered generic board writer.")
	var prepared: Dictionary = manager.prepare_local_investigation_board_offer(station)
	_expect(prepared.get("ok", false), "Local world/config could not prepare offer: %s" % prepared)
	if prepared.get("ok", false):
		_expect(prepared["posting"]["base_reward"] == manager.INVESTIGATION_BOARD_BUDGET, "Local context did not use approved game budget.")
		_expect(prepared["posting"]["body"].contains("Local Station"), "Local station display name was lost.")
		var published: Dictionary = manager.publish_local_investigation_board_offer(prepared, station)
		_expect(published.get("ok", false), "Local posting failed publication.")
		if published.get("ok", false):
			var quests: Node = root.get_node("QuestManager")
			var before: Dictionary = manager.story_state.duplicate(true)
			var events: Array = []
			var listener := func(): events.append("accepted")
			quests.quest_accepted.connect(listener)
			var rejected: Dictionary = manager.accept_local_investigation_board_offer(published["offer_id"], station)
			_expect(rejected.get("reason", "") == "checkpoint_failed", "Failed checkpoint did not reject acceptance.")
			_expect(not quests.is_lane_occupied("BOARD") and manager.story_state == before and events.is_empty(), "Failed acceptance leaked mission, retirement or acceptance event.")
			scene.checkpoint_ok = true
			if investigation_index >= 0: ui._on_public_board_offer_accept(investigation_index)
			_expect(quests.is_lane_occupied("BOARD") and events.size() == 1, "Presenter acceptance failed or emitted duplicate events.")
			_expect(scene.captured["quest"].size() == 1 and scene.captured["story_state"]["investigation_board"]["entries"][published["offer_id"]]["status"] == "retired", "Checkpoint did not capture mission and retired posting together.")
			_expect(not manager.accept_local_investigation_board_offer(published["offer_id"], station).get("ok", false), "Duplicate acceptance created another job.")
			quests.quest_accepted.disconnect(listener)
			var first_recipe: String = quests.active_quest.get("recipe", "")
			_finish_board_job(quests, gs, pilot, ui, station)
			var next_index := -1
			for index in range(ui.public_board_current_offers.size()):
				if ui.public_board_current_offers[index].get("investigation_posting", false): next_index = index
			_expect(next_index >= 0, "Other supported local cause never reached visible board.")
			if next_index >= 0:
				ui._on_public_board_offer_accept(next_index)
				_expect(quests.is_lane_occupied("BOARD") and str(quests.active_quest.get("recipe", "")) != first_recipe, "Second board recipe could not be accepted.")
				if quests.is_lane_occupied("BOARD"): _finish_board_job(quests, gs, pilot, ui, station)
			quests.restore_active_quest({})
	station.remove_from_group("station")
	_expect(not manager.prepare_local_investigation_board_offer(station).get("ok", false), "Unregistered local station prepared a job.")
	manager.story_state = old_story
	manager._story_state_store = old_store
	gs.player = old_player
	gs.current_system_id = old_system
	board.story_config_override_for_tests = old_config
	current_scene = old_scene
	scene.free()

func _finish_board_job(quests: Node, gs: Node, pilot: CharacterBody3D, ui: Control, station: Node3D):
	var mission_id: String = quests.active_quest["runtime_id"]
	var objective: Dictionary = quests.active_quest.duplicate(true)
	pilot.is_docked = false
	for site: Dictionary in objective["investigation"]["sites"]:
		var p: Array = site["position"]
		pilot.global_position = Vector3(p[0], p[1], p[2])
		pilot.velocity = Vector3.ZERO
		quests.reconcile_investigation_sites()
		_expect(quests.begin_investigation_scan(mission_id, site["id"]).get("ok", false), "Published job would not scan at its saved site.")
		for frame in range(31): quests._physics_process(0.1)
	var branch := "preserve"
	if objective["recipe"] == "survey_discrepancy":
		branch = "certify_match" if objective["investigation"]["sites"][0]["code"] == objective["investigation"]["sites"][1]["code"] else "certify_mismatch"
	else:
		_expect("liquidate" not in objective["branch_ids"], "Claims client offered unfunded destruction branch.")
	var resolved: Dictionary = quests.dispatch_investigation_command({"mission_id": mission_id, "site_id": objective["investigation"]["sites"][1]["id"], "action": "resolve", "branch_id": branch, "expected_revision": quests.active_quest["investigation"]["investigation_revision"]})
	_expect(resolved.get("ok", false), "Published job cannot resolve after its scans.")
	pilot.is_docked = true
	ui.current_station = null
	_expect(not ui._should_show_public_board_turn_in(), "Missing station offered settlement.")
	ui.current_station = station
	_expect(ui._should_show_public_board_turn_in(), "Assigned station did not offer investigation settlement.")
	_expect(ui._quest_tracker_turn_in_target(quests.active_quest) == station, "Mission route sent investigation to the wrong station.")
	ui.public_board_panel.show()
	var credits: int = gs.player_credits
	ui._on_public_board_turn_in_pressed()
	_expect(not quests.is_lane_occupied("BOARD") and gs.player_credits == credits + 400, "Local investigation settlement failed or paid incorrect reward.")
	ui._on_public_board_turn_in_pressed()
	_expect(gs.player_credits == credits + 400, "Repeated settlement paid twice.")

func _test_board_save_aliases(context: Dictionary):
	var local := context.duplicate(true)
	local["system_id"] = "start_system"
	local["world"]["system_id"] = "start_system"
	var prepared := Board.prepare({}, local)
	if not prepared.get("ok", false):
		_expect(false, "Alias fixture could not prepare posting.")
		return
	var published := Board.publish(prepared["state"], prepared["offer_id"], local)
	var registry = load("res://scripts/registry/SystemRegistry.gd").load_default()
	var migrator = load("res://scripts/persistence/SaveMigrator.gd")
	var story := Store._default_state()
	story["investigation_board"] = published["state"]
	var quest: Dictionary = published["posting"]["quest_data"]
	var adapted := Adapter.build_active_state(quest, quest["choices"][0], "mission.runtime.alias", "start_system", 0)
	_expect(adapted["validation"].is_valid(), "Alias fixture active mission is invalid.")
	var encoded: Dictionary = migrator.prepare_for_save({"current_system_id": "start_system", "player": {"health": 100.0, "position": [1, 2, 3]}, "global": {}, "quest": [adapted["state"]], "systems": {}, "story_state": story}, registry)
	_expect(encoded.get("ok", false), "Posting canonical encoding failed: %s" % encoded.get("error", ""))
	if not encoded.get("ok", false): return
	var entry: Dictionary = encoded["data"]["story_state"]["investigation_board"]["entries"][published["offer_id"]]
	_expect(entry["posting"]["quest_data"]["objective"]["system_id"] == str(registry.resolve_system_id("start_system")), "Posting did not encode canonical system.")
	var decoded: Dictionary = migrator.decode_for_runtime(JSON.parse_string(JSON.stringify(encoded["data"])), registry)
	_expect(decoded.get("ok", false), "Posting runtime decoding failed.")
	if not decoded.get("ok", false): return
	var restored: Dictionary = decoded["data"]["story_state"]["investigation_board"]
	_expect(restored == published["state"], "Save conversion changed posting ownership, truth, cause or bag.")
	var reopened := Board.prepare(restored, local)
	_expect(reopened.get("offer_id", "") == published["offer_id"], "Alias roundtrip rerolled visible posting.")
	_expect(Board.publish(restored, published["offer_id"], local).get("ok", false), "Restored posting cannot be republished at its station.")
	var path := "res://.tmp_godot_user/investigation_checkpoint_%d" % Time.get_ticks_usec()
	var slots = load("res://scripts/persistence/CampaignSlotRegistry.gd").open(path)
	var created: Dictionary = slots.create_campaign("slot_01", "Investigation checkpoint fixture", "investigation-save", encoded["data"], registry)
	_expect(created.get("ok", false), "Real investigation checkpoint bootstrap failed: %s" % created.get("error", ""))
	if not created.get("ok", false): return
	var store = load("res://scripts/persistence/CampaignCheckpointStore.gd").open(path + "/slot_01")
	var captured: Dictionary = store.capture_autosave(encoded["data"], {"type": "docked", "system_id": "system.start", "station_id": "station.start.main"}, "investigation_accepted")
	_expect(captured.get("ok", false), "Real checkpoint rejected investigation coordinates: %s" % captured.get("error", ""))
	if not captured.get("ok", false): return
	var bundle: Dictionary = store.load_active_bundle()
	var checkpoint: Dictionary = bundle.get("checkpoint", {}).get("state", {})
	_expect(not checkpoint.get("player", {}).has("position"), "Checkpoint retained tactical ship position.")
	_expect(checkpoint.get("quest", [])[0]["investigation"] == encoded["data"]["quest"][0]["investigation"], "Checkpoint erased active investigation site locations.")
	_expect(checkpoint.get("story_state", {}).get("investigation_board", {}) == encoded["data"]["story_state"]["investigation_board"], "Checkpoint erased published posting locations.")
