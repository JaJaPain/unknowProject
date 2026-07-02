extends SceneTree

const StoryManagerType := preload("res://scripts/story/StoryManager.gd")

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
	_test_resolve_hooks_removes_only_matching_hook()
	_test_last_hook_resolution_refills_from_act_1_outline_reserve()
	_test_lounge_rumor_ranking_unaffected_by_dock_roll_wiring()
	_test_force_dock_rumor_fires_and_dedups()
	_test_mood_leak_guard()
	_test_agent_cooldown_allows_three_in_a_row()

	if _failures.is_empty():
		print("[PASS] Story manager hook tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _fresh_manager() -> Node:
	var manager := StoryManagerType.new()
	root.add_child(manager)
	return manager


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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
