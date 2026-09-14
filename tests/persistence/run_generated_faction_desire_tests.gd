extends SceneTree

const DesireType := preload("res://scripts/persistence/GeneratedFactionDesire.gd")
const StoreType := preload("res://scripts/persistence/CampaignGeneratedFactionStore.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_desire_dimensions_have_compatible_variety()
	_test_joint_coherence_and_corrupt_bindings()
	_test_desire_is_deterministic_for_a_seed()
	_test_intents_follow_the_need_not_the_goal()
	_test_relationships_are_not_all_hostile()
	_test_relationships_are_asymmetric_and_reasoned()
	_test_no_forced_hostility_and_work_still_exists()
	_test_relationship_targets_stay_local()
	_test_cross_seed_variety()

	if _failures.is_empty():
		print("[PASS] Generated faction desire tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


## The failure being replaced: goal, need and mission intents arrived as one of
## four locked sets, so a system had four possible stories.
func _test_desire_dimensions_have_compatible_variety() -> void:
	var goals_per_need := {}
	for seed_index in range(60):
		var desire := DesireType.build("seed_%d" % seed_index, "scope%d" % seed_index, 0)
		var need := str(desire["need"])
		if not goals_per_need.has(need):
			goals_per_need[need] = []
		var goal := str(desire["goal"])
		if goal not in goals_per_need[need]:
			goals_per_need[need].append(goal)
	var multi := 0
	for need in goals_per_need.keys():
		if (goals_per_need[need] as Array).size() > 1:
			multi += 1
	_expect(
		multi >= 3,
		"Goal and need still travel together: only %d needs saw more than one goal." % multi
	)
	# Every dimension must actually be populated, not silently empty.
	var sample := DesireType.build("sample", "scope", 0)
	for field in [
		"goal", "success_condition", "need", "obstacle", "triggering_event",
		"triggering_event_id", "controls", "payment_source", "limit",
		"change_condition", "private_motive", "stake",
		"need_reason",
	]:
		_expect(
			not str(sample.get(field, "")).strip_edges().is_empty(),
			"Desire field '%s' was empty." % field
		)
	_expect(
		not (sample.get("mission_intents", []) as Array).is_empty(),
		"Desire produced no mission intents."
	)


func _test_joint_coherence_and_corrupt_bindings() -> void:
	var all_goals := {}
	for seed_index in range(1000):
		var desire := DesireType.build("coherence_%d" % seed_index, "scope", seed_index % 4)
		all_goals[str(desire["goal"])] = true
		_expect(bool(DesireType.check_coherence(desire)["ok"]), "Incoherent generated desire: %s" % str(desire))
		if str(desire["goal"]) == "prove a rival's manifest is fiction":
			_expect(desire["need"] in ["sealed manifests from the last shipment", "a witness who will go on record", "filed claim evidence"], "Manifest dispute acquired an unrelated need.")
		_expect(not str(desire["obstacle"]).contains("credit is frozen"), "Payment promises contradict a frozen account.")
		_expect(not str(desire["obstacle"]).contains("records burned"), "Irrecoverable records were offered as recoverable cargo.")
		_expect(DesireType.binds_item_to_need(str(desire["need"]), DesireType.item_for_need(str(desire["need"]))), "Compatible need has no concrete cargo binding.")
	_expect(all_goals.size() == DesireType.GOALS.size(), "Coherence rules silently removed a goal.")
	var original := DesireType.build("coherent", "scope", 0)
	var corrupt := original.duplicate(true)
	corrupt["goal"] = "prove a rival's manifest is fiction"
	corrupt["need"] = "fuel it can afford"
	_expect(not bool(DesireType.check_coherence(corrupt)["ok"]), "The measured fuel/manifest contradiction passed.")
	for field in ["triggering_event", "change_condition", "controls", "payment_source", "success_condition", "need_reason"]:
		corrupt = original.duplicate(true)
		corrupt[field] = "unrelated invented fact"
		_expect(not bool(DesireType.check_coherence(corrupt)["ok"]), "Broken %s binding passed." % field)
	var legacy := original.duplicate(true)
	var future := original.duplicate(true)
	future["generation_version"] = 999
	_expect(bool(DesireType.check_coherence(future)["checked"]) and not bool(DesireType.check_coherence(future)["ok"]), "Unknown version bypassed publication as legacy.")
	legacy.erase("generation_version")
	var before := JSON.stringify(legacy)
	_expect(not bool(DesireType.check_coherence(legacy)["checked"]), "Legacy facts were certified by new rules.")
	_expect(JSON.stringify(legacy) == before, "Coherence checking mutated a saved desire.")
	# Exercise the store's load normalization, not just a JSON copy. An older
	# incoherent record is still historical truth; do not silently reroll it.
	legacy["goal"] = "prove a rival's manifest is fiction"
	legacy["need"] = "fuel it can afford"
	var faction: Dictionary = StoreType.generate_system_factions("saved", "system.saved", 2)[0]
	faction["desire"] = legacy
	var loaded := StoreType._normalize_faction(JSON.parse_string(JSON.stringify(faction)), "saved", 0)
	_expect(loaded["desire"] == JSON.parse_string(JSON.stringify(legacy)), "Store normalization rewrote an old desire.")


## Revisiting a system must return the same interests, not reroll them.
func _test_desire_is_deterministic_for_a_seed() -> void:
	var first := DesireType.build("campaign_a|system_b", "scope1", 2)
	var second := DesireType.build("campaign_a|system_b", "scope1", 2)
	_expect(
		JSON.stringify(first) == JSON.stringify(second),
		"The same seed produced two different desires; a revisit would reroll the system."
	)
	var different := DesireType.build("campaign_a|system_c", "scope2", 2)
	_expect(
		JSON.stringify(first) != JSON.stringify(different),
		"Two different systems produced an identical desire."
	)


## The work the player is asked to do should follow from the thing that is
## missing, not from a template index the goal happened to share.
func _test_intents_follow_the_need_not_the_goal() -> void:
	for need in DesireType.INTENTS_BY_NEED.keys():
		var intents: Array = DesireType.INTENTS_BY_NEED[need]
		_expect(
			not intents.is_empty(),
			"Need '%s' implies no gameplay verb at all." % str(need)
		)
	var seen_intent_sets := {}
	for seed_index in range(40):
		var desire := DesireType.build("v%d" % seed_index, "s%d" % seed_index, 0)
		seen_intent_sets[str(desire["mission_intents"])] = true
	_expect(
		seen_intent_sets.size() >= 4,
		"Only %d distinct intent sets across 40 seeds." % seen_intent_sets.size()
	)


## Abe's direction and the plan are both explicit: not every faction should be
## hostile. Cooperation, dependency and indifference are legitimate outcomes.
func _test_relationships_are_not_all_hostile() -> void:
	var kind_counts := {}
	var systems := 0
	for seed_index in range(40):
		var factions := StoreType.generate_system_factions(
			"campaign_%d" % seed_index, "system_%d" % seed_index, 3
		)
		systems += 1
		for faction in factions:
			for relationship in ((faction as Dictionary).get("relationships", []) as Array):
				var kind := str((relationship as Dictionary).get("kind", "unknown"))
				kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
	for expected in ["dependency", "cooperation", "indifference"]:
		_expect(
			int(kind_counts.get(expected, 0)) > 0,
			"No '%s' relationship appeared across %d systems; everyone is hostile again." % [
				expected, systems
			]
		)
	var total := 0
	for kind in kind_counts.keys():
		total += int(kind_counts[kind])
	var hostile := int(kind_counts.get("friction", 0)) + int(kind_counts.get("rivalry", 0))
	_expect(
		total > 0 and float(hostile) / float(total) < 0.6,
		"Hostile relationships are %d of %d, which is the forced-rivalry pattern again." % [
			hostile, total
		]
	)


## How A sees B is drawn separately from how B sees A, so one side can depend on
## a party that is indifferent to it.
func _test_relationships_are_asymmetric_and_reasoned() -> void:
	var asymmetric_found := false
	for seed_index in range(30):
		var factions := StoreType.generate_system_factions(
			"asym_%d" % seed_index, "system_asym_%d" % seed_index, 3
		)
		for faction in factions:
			for relationship in ((faction as Dictionary).get("relationships", []) as Array):
				var entry: Dictionary = relationship
				# Every opinion must cite something, not just carry a number.
				_expect(
					not str(entry.get("reason", "")).strip_edges().is_empty(),
					"A relationship carried a standing with no stated reason."
				)
				_expect(
					entry.has("kind") and not str(entry["kind"]).is_empty(),
					"A relationship recorded no kind."
				)
				var mirror := _relationship_between(factions, str(entry["faction_id"]), str((faction as Dictionary)["id"]))
				if mirror.is_empty():
					continue
				if str(mirror.get("kind", "")) != str(entry.get("kind", "")):
					asymmetric_found = true
	_expect(
		asymmetric_found,
		"No asymmetric opinion appeared across 30 systems; relations are still mirrored."
	)


## Superseded 2026-09-12. This used to require EVERY system to contain at least
## one adversarial pair. The plan now says a system can have work because of
## scarcity, an accident or a dependency, with nobody hostile at all -- forcing
## hostility made every system read the same way.
##
## What a system DOES still owe us is a reason for the work to exist: every
## faction needs an obstacle and a triggering event, whatever its neighbours
## think of it.
func _test_no_forced_hostility_and_work_still_exists() -> void:
	var peaceful_systems := 0
	for seed_index in range(60):
		var factions := StoreType.generate_system_factions(
			"peace_%d" % seed_index, "system_peace_%d" % seed_index, 2 + (seed_index % 3)
		)
		var adversarial := false
		for faction in factions:
			var desire: Dictionary = (faction as Dictionary).get("desire", {})
			# The real engine of work, present regardless of relationships.
			_expect(
				not str(desire.get("obstacle", "")).strip_edges().is_empty(),
				"A faction had no obstacle, so nothing would need doing."
			)
			_expect(
				not str(desire.get("triggering_event", "")).strip_edges().is_empty(),
				"A faction had a problem with no cause."
			)
			_expect(
				not str(desire.get("need", "")).strip_edges().is_empty(),
				"A faction needed nothing, so no job could follow from it."
			)
			for relationship in ((faction as Dictionary).get("relationships", []) as Array):
				if int((relationship as Dictionary).get("standing", 0)) <= -15:
					adversarial = true
		if not adversarial:
			peaceful_systems += 1
	# The point of removing the rule: peaceful systems must actually occur now.
	_expect(
		peaceful_systems > 0,
		"No system out of 60 was free of hostility; the forced-rivalry rule is still in effect."
	)


## A relationship may only point at a faction that exists in this system.
func _test_relationship_targets_stay_local() -> void:
	for seed_index in range(20):
		var factions := StoreType.generate_system_factions(
			"local_%d" % seed_index, "system_local_%d" % seed_index, 4
		)
		var local_ids: Array[String] = []
		for faction in factions:
			local_ids.append(str((faction as Dictionary)["id"]))
		for faction in factions:
			var own_id := str((faction as Dictionary)["id"])
			for relationship in ((faction as Dictionary).get("relationships", []) as Array):
				var target := str((relationship as Dictionary).get("faction_id", ""))
				_expect(target in local_ids, "A relationship pointed outside the system: %s" % target)
				_expect(target != own_id, "A faction recorded a relationship with itself.")


## Honest measurement, not a uniqueness promise: count how many DISTINCT causal
## situations 40 seeds actually produce. Reported as a threshold well below the
## theoretical maximum so the test fails on a regression, not on luck.
func _test_cross_seed_variety() -> void:
	var signatures := {}
	for seed_index in range(40):
		var factions := StoreType.generate_system_factions(
			"variety_%d" % seed_index, "system_variety_%d" % seed_index, 2
		)
		for faction in factions:
			var desire: Dictionary = (faction as Dictionary).get("desire", {})
			# Name-free: the situation, not the outfit that happens to be in it.
			signatures["%s|%s|%s" % [
				str(desire.get("goal", "")),
				str(desire.get("need", "")),
				str(desire.get("obstacle", "")),
			]] = true
	_expect(
		signatures.size() >= 60,
		"Only %d distinct goal/need/obstacle situations from 80 generated factions." % signatures.size()
	)


func _relationship_between(factions: Array, from_id: String, to_id: String) -> Dictionary:
	for faction in factions:
		if str((faction as Dictionary).get("id", "")) != from_id:
			continue
		for relationship in ((faction as Dictionary).get("relationships", []) as Array):
			if str((relationship as Dictionary).get("faction_id", "")) == to_id:
				return relationship
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
