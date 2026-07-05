extends SceneTree

# Runtime load, not const preload: preloading fires before autoloads register,
# so these autoload-referencing scripts would cache a failed compile and the
# suite would "pass" with zero assertions (see run_story_state_bible_seed_tests).
var StoryManagerType: GDScript = null
var StoryQuestManagerType: GDScript = null

var _failures: Array[String] = []


# Minimal stand-in for CampaignBibleStore — only the surface
# StoryManager's refill logic actually touches (is_valid/data/replace_bible).
class FakeBibleStore extends RefCounted:
	var data: Dictionary = {}
	func is_valid() -> bool:
		return true
	func replace_bible(next_data: Dictionary) -> Dictionary:
		data = next_data.duplicate(true)
		return {"ok": true}


func _initialize() -> void:
	StoryManagerType = load("res://scripts/story/StoryManager.gd")
	StoryQuestManagerType = load("res://scripts/story/StoryQuestManager.gd")
	if StoryManagerType == null or not StoryManagerType.can_instantiate() \
			or StoryQuestManagerType == null or not StoryQuestManagerType.can_instantiate():
		push_error("[FAIL] Story scripts did not compile — suite cannot run.")
		quit(1)
		return
	_test_resolve_hooks_removes_only_matching_hook()
	_test_last_hook_resolution_refills_from_act_1_outline_reserve()
	_test_lounge_rumor_ranking_unaffected_by_dock_roll_wiring()
	_test_force_dock_rumor_fires_and_dedups()
	_test_mood_leak_guard()
	_test_agent_cooldown_allows_three_in_a_row()
	_test_player_choice_recording_and_digest()
	_test_regeneration_trigger_selection()
	_test_story_quest_plot_armor_guard()
	_test_screenshot_first_visit_tracking()

	if _failures.is_empty():
		print("[PASS] Story manager hook tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _fresh_manager() -> Node:
	var manager: Node = StoryManagerType.new()
	root.add_child(manager)
	return manager


# Screenshot triggers: _first_visit_and_record fires exactly once per id,
# dedups, and caps the seen-list. (Capture itself is headless-no-op; this is
# the logic that decides WHEN it would fire.)
func _test_screenshot_first_visit_tracking() -> void:
	var manager := _fresh_manager()
	_expect(
		manager._first_visit_and_record("screenshot_systems_seen", "system.kova"),
		"First visit to a new system should report true."
	)
	_expect(
		not manager._first_visit_and_record("screenshot_systems_seen", "system.kova"),
		"Second visit to the same system should report false."
	)
	_expect(
		manager._first_visit_and_record("screenshot_systems_seen", "system.meridian"),
		"A different system should still report true."
	)
	_expect(
		not manager._first_visit_and_record("screenshot_stations_seen", ""),
		"Empty ids should never count as a first visit."
	)
	# Cap: 70 inserts leaves at most 64 remembered.
	for i in range(70):
		manager._first_visit_and_record("screenshot_stations_seen", "station_%d" % i)
	_expect(
		(manager.story_state.get("screenshot_stations_seen", []) as Array).size() <= 64,
		"Seen-station list should cap at 64 entries."
	)
	manager.queue_free()


# Layer 3 of the plot-armor contract: no quest def may make Kaelen or N.O.V.A.
# a kill target or a destroyable spawn, whatever upstream generation said.
func _test_story_quest_plot_armor_guard() -> void:
	var kill_kaelen := {
		"id": "bad_quest_1",
		"objective": {"type": "kill_tagged_ship", "target_persistent_id": "story.kaelen.ship"},
	}
	_expect(
		not StoryQuestManagerType.quest_violates_plot_armor(kill_kaelen).is_empty(),
		"A kill objective targeting Kaelen was not rejected."
	)
	var spawn_nova := {
		"id": "bad_quest_2",
		"objective": {"type": "kill_tagged_ship", "target_persistent_id": "story.raider.7"},
		"spawns": [{"type": "ship", "faction": "reavers", "persistent_id": "story.nova.decoy"}],
	}
	_expect(
		not StoryQuestManagerType.quest_violates_plot_armor(spawn_nova).is_empty(),
		"A destroyable ship spawn carrying N.O.V.A.'s identity was not rejected."
	)
	var clean_quest := {
		"id": "good_quest",
		"objective": {"type": "kill_tagged_ship", "target_persistent_id": "story.reaver.leader"},
		"spawns": [{"type": "ship", "faction": "reavers", "persistent_id": "story.reaver.leader"}],
		"hook": {"type": "kaelen_voice", "text": "Kaelen has work: clear the Reaver leader."},
	}
	_expect(
		StoryQuestManagerType.quest_violates_plot_armor(clean_quest).is_empty(),
		"A legitimate Reaver kill quest (with Kaelen as the voice hook) was wrongly rejected."
	)


func _test_resolve_hooks_removes_only_matching_hook() -> void:
	var manager := _fresh_manager()
	var hook_a := "The first open thread."
	var hook_b := "The second open thread."
	manager.story_state["pending_hooks"] = [hook_a, hook_b]
	var ref_a := "hook:%s" % hook_a.sha256_text().substr(0, 12)

	manager._resolve_hooks_for_quest({"story_hook_ref": ref_a})

	var remaining: Array = manager.story_state.get("pending_hooks", [])
	_expect(remaining.size() == 1 and remaining.has(hook_b), "Resolving hook_a should leave only hook_b.")
	manager.queue_free()


func _test_last_hook_resolution_refills_from_act_1_outline_reserve() -> void:
	var manager := _fresh_manager()
	var fake_store := FakeBibleStore.new()
	fake_store.data = {
		"act_1_outline": ["Consumed at seed.", "Reserve beat to consume on refill."],
		"story_arcs": [],
		"rumor_trails": [],
		"core_pressure": "fallback pressure",
	}
	manager._campaign_bible_store = fake_store
	manager.story_state["act_1_outline_consumed_index"] = 1
	var only_hook := "The last open thread."
	manager.story_state["pending_hooks"] = [only_hook]
	var starting_chapter := int(manager.story_state.get("chapter", 1))

	var ref := "hook:%s" % only_hook.sha256_text().substr(0, 12)
	manager._resolve_hooks_for_quest({"story_hook_ref": ref})

	_expect(
		int(manager.story_state.get("chapter", 1)) == starting_chapter + 1,
		"Resolving the last hook with an unused act_1_outline beat available should advance the chapter."
	)
	_expect(
		(manager.story_state.get("pending_hooks", []) as Array).has("Reserve beat to consume on refill."),
		"Chapter refill did not seed pending_hooks from the reserved act_1_outline beat."
	)
	_expect(
		not (manager.story_state.get("pending_hooks", []) as Array).is_empty(),
		"Chapter advanced with an empty pending_hooks slate — refill-not-finish was violated."
	)
	manager.queue_free()


func _test_lounge_rumor_ranking_unaffected_by_dock_roll_wiring() -> void:
	var manager := _fresh_manager()
	manager.story_state["pending_hooks"] = ["A hook."]
	manager.story_state["current_foreshadow"] = "A foreshadow."
	manager.story_state["active_tensions"] = ["A tension."]
	var rumor: Dictionary = manager.get_lounge_rumor({})
	_expect(
		str(rumor.get("id", "")).begins_with("hook:"),
		"get_lounge_rumor() should still rank pending_hooks (weight 4) above foreshadow/tensions."
	)
	manager.queue_free()


func _test_force_dock_rumor_fires_and_dedups() -> void:
	var manager := _fresh_manager()
	manager.story_state["pending_hooks"] = ["A dock rumor hook."]
	var hinted_before: Array = manager.story_state.get("hinted_lounge_rumors", [])
	manager._maybe_fire_dock_rumor(null, true)
	var hinted_after: Array = manager.story_state.get("hinted_lounge_rumors", [])
	_expect(
		hinted_after.size() == hinted_before.size() + 1,
		"_maybe_fire_dock_rumor(force=true) with a pending hook should record a heard rumor."
	)
	manager.queue_free()


# Guards mood_leaks_secret(): a mood echoing distinctive words from Kaelen's
# hidden angle, or run long enough to be explaining it, must be rejected; a
# genuine short mood with no overlap must pass.
func _test_mood_leak_guard() -> void:
	var angle := "Kaelen forged the convoy manifests to bury a stolen ledger."

	# Direct echo of a distinctive angle word (ledger) — leak.
	_expect(
		StoryManagerType.mood_leaks_secret("hiding the ledger", angle),
		"Mood echoing a distinctive angle word (ledger) should be flagged as a leak."
	)
	# Another distinctive overlap (forged / manifests).
	_expect(
		StoryManagerType.mood_leaks_secret("worried about the forged manifests", angle),
		"Mood echoing forged/manifests should be flagged as a leak."
	)
	# A whole sentence paraphrasing the angle — too long to be a mood.
	_expect(
		StoryManagerType.mood_leaks_secret(
			"she secretly altered the shipping records to hide what she took",
			angle
		),
		"An over-long explaining mood should be flagged even without exact overlap."
	)
	# Genuine safe moods — no overlap, short. Must pass.
	_expect(
		not StoryManagerType.mood_leaks_secret("guarded and terse", angle),
		"A safe short mood with no angle overlap was wrongly flagged."
	)
	_expect(
		not StoryManagerType.mood_leaks_secret("unusually generous", angle),
		"A safe short mood with no angle overlap was wrongly flagged."
	)
	# Stopwords shared between mood and angle must not trigger a false leak.
	_expect(
		not StoryManagerType.mood_leaks_secret("evasive and tense", angle),
		"Shared stopwords should not count as a secret leak."
	)


# The player should be able to take AGENT_CONTRACTS_BEFORE_COOLDOWN contracts
# back-to-back before a cooldown hits; abandoning applies the cooldown at once.
func _test_agent_cooldown_allows_three_in_a_row() -> void:
	var manager := _fresh_manager()
	# First two completions stay available (no cooldown yet).
	var first: Dictionary = manager.start_agent_contract_cooldown("contract_resolved")
	_expect(
		bool(first.get("available", false)),
		"First completed contract should not trigger a cooldown."
	)
	var second: Dictionary = manager.start_agent_contract_cooldown("contract_resolved")
	_expect(
		bool(second.get("available", false)),
		"Second completed contract should not trigger a cooldown."
	)
	# The third crosses the threshold — cooldown applies.
	var third: Dictionary = manager.start_agent_contract_cooldown("contract_resolved")
	_expect(
		not bool(third.get("available", true)),
		"Third completed contract should trigger the cooldown."
	)
	_expect(
		int(manager.story_state.get("agent_contracts_since_cooldown", -1)) == 0,
		"Streak counter should reset to 0 after the cooldown applies."
	)
	manager.queue_free()

	# Abandoning applies the cooldown immediately, without a streak.
	var abandon_manager := _fresh_manager()
	var abandoned: Dictionary = abandon_manager.start_agent_contract_cooldown("contract_abandoned")
	_expect(
		not bool(abandoned.get("available", true)),
		"Abandoning a contract should apply the cooldown immediately."
	)
	abandon_manager.queue_free()


# record_player_choice logs the choice, feeds the digest, and shifts faction
# pressure via the deltas; the digest reflects recent choices.
func _test_player_choice_recording_and_digest() -> void:
	var manager := _fresh_manager()
	# Seed a faction_pressure entry so a delta has somewhere to land.
	manager.story_state["faction_pressure"] = {"vanguard": {"pressure": 0, "posture": "stable"}}

	manager.record_player_choice("sided_aurelia_1", "Ran cargo for Aurelia against Vanguard.", {"vanguard": -2})
	manager.record_player_choice("refused_vanguard_1", "Refused a Vanguard escort contract.", {})

	var choices: Array = manager.story_state.get("player_choices", [])
	_expect(choices.size() == 2, "Both player choices should be recorded.")
	_expect(
		int(manager.story_state.get("faction_pressure", {}).get("vanguard", {}).get("pressure", 0)) == -2,
		"record_player_choice did not apply the faction delta through the pressure write path."
	)

	var digest: String = manager.player_choice_digest()
	_expect(
		digest.contains("Ran cargo for Aurelia") and digest.contains("Refused a Vanguard escort"),
		"player_choice_digest did not include the recent choices. Got: %s" % digest
	)

	# Empty id + empty description is a no-op.
	manager.record_player_choice("", "", {})
	_expect(
		(manager.story_state.get("player_choices", []) as Array).size() == 2,
		"An empty choice should not be recorded."
	)
	manager.queue_free()


# _select_regeneration_trigger honors metric/threshold across all triggers, not
# just triggers[0], and _regeneration_metric_value reads live reserve counts.
func _test_regeneration_trigger_selection() -> void:
	var manager := _fresh_manager()
	var bible := {
		"story_arcs": [{"name": "A", "summary": "s"}],   # 1 arc
		"rumor_trails": [{"name": "R"}],                  # 1 trail
		"act_1_outline": ["b0", "b1", "b2"],              # 3 beats
		"regeneration_triggers": [
			{"id": "arcs", "metric": "active_story_arcs_remaining", "threshold": 0, "action": "append_story_arc"},
			{"id": "rumors", "metric": "rumor_trails_remaining", "threshold": 0, "action": "append_rumor_trail"},
			{"id": "horizon", "metric": "prepared_systems_remaining", "threshold": 2, "action": "append_story_horizon"},
		],
	}
	# Nothing consumed: arcs_remaining=1(>0), rumors_remaining=1(>0),
	# prepared=3(>2) -> none at threshold except... 3<=2 false. So falls back to
	# the first valid trigger.
	manager.story_state["story_arcs_consumed_index"] = 0
	manager.story_state["rumor_trails_consumed_index"] = 0
	manager.story_state["act_1_outline_consumed_index"] = 0
	_expect(
		str(manager._select_regeneration_trigger(bible).get("id", "")) == "arcs",
		"With no metric under threshold, selection should fall back to the first trigger."
	)
	# Consume the arc only: arcs_remaining=0 <= 0 -> the arcs trigger matches first.
	manager.story_state["story_arcs_consumed_index"] = 1
	_expect(
		str(manager._select_regeneration_trigger(bible).get("id", "")) == "arcs",
		"Exhausted arcs should select the active_story_arcs_remaining trigger."
	)
	# Metric value reads the live reserve.
	_expect(
		manager._regeneration_metric_value("prepared_systems_remaining", bible) == 3,
		"prepared_systems_remaining should equal the unconsumed act_1_outline count."
	)
	manager.story_state["rumor_trails_consumed_index"] = 1
	_expect(
		manager._regeneration_metric_value("rumor_trails_remaining", bible) == 0,
		"rumor_trails_remaining should drop to 0 once consumed."
	)
	manager.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
