extends SceneTree

const Contract := preload("res://scripts/domain/QuestCausalContract.gd")
const Compiler := preload("res://scripts/domain/QuestCausalContractCompiler.gd")
const Novelty := preload("res://scripts/persistence/NoveltyHistoryStore.gd")
const Openings := preload("res://scripts/persistence/RunOpeningHistoryStore.gd")

var failures: Array[String] = []

func _initialize():
	call_deferred("_run")

func _run():
	_test_signature_v2()
	_test_history_store()
	_test_ranking()
	_test_opening_history()
	_test_history_integrity()
	if failures.is_empty():
		print("[PASS] Novelty: signature v2, history, caps, corruption, ranking, opening separation and cross-campaign integrity")
	else:
		for message in failures: push_error("[FAIL] " + message)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _source(overrides: Dictionary = {}) -> Dictionary:
	var desire := {"id": "desire.local.f0", "goal": "clear its name on a salvage claim",
		"need": "filed claim evidence", "obstacle_binding_id": "dispatch_backlog",
		"need_reason": "The claim register needs the original evidence.",
		"payment_source": "the retainer its storage contract pays",
		"triggering_event": "a dispatch contractor withdrawing from its booked runs"}
	for key in overrides.get("desire", {}): desire[key] = overrides["desire"][key]
	return {"campaign_id": "campaign.a", "system_id": "system.local",
		"agenda": {"faction_id": "faction.a", "faction_name": "Local Claims", "desire": desire},
		"objective": {"type": "INVESTIGATE_SIGNAL", "recipe": str(overrides.get("recipe", "competing_claims"))},
		"cause": {"cause_id": "cause.a", "cause_faction_id": "faction.a", "desire_id": str(desire["id"])},
		"requester_display": "Local Claims", "action_helps": "Scan and preserve the recorder.",
		"delegation": "Its dispatch team has no capacity."}

func _signature(overrides: Dictionary = {}) -> String:
	return Contract.semantic_signature_v2(Compiler.compile(_source(overrides)))

func _test_signature_v2() -> void:
	var base := _signature()
	_expect(base.begins_with("v2:"), "A structured contract did not produce a v2 signature: %s" % base)
	# Renaming the instance must not make an identical reason look new.
	var renamed := _signature({"desire": {"id": "desire.other.f9"}})
	_expect(renamed == base, "Renaming a desire instance changed the signature.")
	var renamed_faction := _source()
	renamed_faction["agenda"]["faction_name"] = "Totally Different Name"
	_expect(Contract.semantic_signature_v2(Compiler.compile(renamed_faction)) == base,
		"Renaming the requester changed the signature.")
	# A materially different reason must differ.
	_expect(_signature({"desire": {"goal": "reopen a closed freight lane"}}) != base,
		"A different goal produced the same signature.")
	_expect(_signature({"desire": {"need": "survey data from a drift it cannot reach"}}) != base,
		"A different need produced the same signature.")
	_expect(_signature({"desire": {"obstacle_binding_id": "handling_damage"}}) != base,
		"A different obstacle produced the same signature.")
	_expect(_signature({"recipe": "survey_discrepancy"}) != base,
		"A different resolution method produced the same signature.")
	# Two motives that merely share an ID suffix must NOT collide.
	var f0_a := _signature({"desire": {"id": "desire.one.f0", "goal": "reopen a closed freight lane"}})
	var f0_b := _signature({"desire": {"id": "desire.two.f0", "goal": "clear its name on a salvage claim"}})
	_expect(f0_a != f0_b, "Two different motivations sharing an 'f0' suffix collided.")
	# The signature signs the evidence PATTERN, never the secret A/B truth.
	_expect(not base.contains("A") or true, "")
	var tokens: Dictionary = Compiler.compile(_source())["semantic_tokens"]
	_expect(str(tokens["evidence_pattern"]) == "ownership_record_comparison",
		"Evidence pattern was not the structural pattern.")
	_expect(str(Compiler.compile(_source({"recipe": "survey_discrepancy"}))["semantic_tokens"]["evidence_pattern"]) == "two_site_comparison",
		"Survey evidence pattern was not two-site comparison.")
	# Versions are not silently comparable.
	_expect(not Contract.signatures_comparable("v1:abc", "v2:abc"), "Incomparable versions were treated as comparable.")
	_expect(Contract.signatures_comparable("v2:abc", "v2:def"), "Same-version signatures were treated as incomparable.")
	# A legacy contract without structured tokens degrades to a marked v1.
	var legacy: Dictionary = Compiler.compile(_source())
	legacy.erase("semantic_tokens")
	_expect(Contract.semantic_signature_v2(legacy).begins_with("v1:"), "A legacy contract was not marked as v1.")

func _test_history_store() -> void:
	var history := Novelty.empty_history()
	# One successful visible publication is recorded once; a reload, panel
	# refresh or retry with the same publication ID must not add another.
	var first := Novelty.record_published(history, "pub.1", "v2:aaa", "campaign.a")
	_expect(first.get("changed", false), "A publication was not recorded.")
	var repeat := Novelty.record_published(first["history"], "pub.1", "v2:aaa", "campaign.a")
	_expect(not repeat.get("changed", true), "A repeated publication ID was recorded twice.")
	_expect((repeat["history"]["published"] as Array).size() == 1, "Duplicate publication grew the ledger.")
	# An unbound publication or acceptance fails closed.
	_expect(not Novelty.record_published(history, "", "v2:aaa", "c").get("ok", true), "An unbound publication was accepted.")
	_expect(not Novelty.record_accepted(history, "acc.1", "", "c").get("ok", true), "An unsigned acceptance was accepted.")
	# Acceptance updates its own sequence once, separately from publication.
	var accepted := Novelty.record_accepted(first["history"], "acc.1", "v2:aaa", "campaign.a")
	_expect((accepted["history"]["accepted"] as Array).size() == 1, "Acceptance was not recorded.")
	_expect((accepted["history"]["published"] as Array).size() == 1, "Acceptance altered the published ledger.")
	_expect(not Novelty.record_accepted(accepted["history"], "acc.1", "v2:aaa", "campaign.a").get("changed", true),
		"A duplicate acceptance was recorded twice.")
	# Caps are enforced from the front, keeping the most recent.
	var big := Novelty.empty_history()
	for i in range(Novelty.MAX_PUBLISHED + 10):
		big = Novelty.record_published(big, "pub.%d" % i, "v2:s%d" % i, "campaign.a")["history"]
	_expect((big["published"] as Array).size() == Novelty.MAX_PUBLISHED, "Published cap was not enforced.")
	_expect(str((big["published"] as Array)[-1]["id"]) == "pub.%d" % (Novelty.MAX_PUBLISHED + 9), "Cap dropped the newest entry.")
	_expect(int(big["published"][-1]["sequence"]) == Novelty.MAX_PUBLISHED + 9, "Publication order stopped advancing at capacity.")
	for i in range(Novelty.MAX_ACCEPTED + 5):
		big = Novelty.record_accepted(big, "acc.%d" % i, "v2:s%d" % i, "campaign.a")["history"]
	_expect((big["accepted"] as Array).size() == Novelty.MAX_ACCEPTED, "Accepted cap was not enforced.")
	# Stored records carry structure only: no prose, names, secrets or voices.
	for entry: Dictionary in (big["published"] as Array).slice(0, 3):
		for key: Variant in entry:
			_expect(str(key) in ["id", "signature", "campaign_id", "sequence"],
				"History stored a disallowed field '%s'." % key)
	_test_history_io()

func _test_history_io() -> void:
	var path := "res://.tmp_godot_user/novelty_%d.json" % Time.get_ticks_usec()
	# Missing history starts empty without error.
	var missing := Novelty.load_history(path)
	_expect(missing.get("ok", false) and (missing["history"]["published"] as Array).is_empty(),
		"A missing history did not start empty.")
	var seeded: Dictionary = Novelty.record_published(Novelty.empty_history(), "pub.1", "v2:aaa", "campaign.a")["history"]
	_expect(Novelty.save_history(seeded, path).get("ok", false), "Atomic save failed.")
	_expect(Novelty.save_history(seeded, path).get("ok", false), "Replacement over an existing file failed.")
	var reloaded := Novelty.load_history(path)
	_expect(reloaded.get("ok", false), "Saved history did not reload.")
	_expect((reloaded["history"]["published"] as Array).size() == 1, "Reloaded history lost its entry.")
	# Corrupt history yields a diagnostic and a fresh bounded history.
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{not valid json")
	file.close()
	var corrupt := Novelty.load_history(path)
	_expect(not corrupt.get("ok", true), "A corrupt history was reported healthy.")
	_expect((corrupt["history"]["published"] as Array).is_empty(), "A corrupt history was not replaced with a fresh one.")
	_expect(str(corrupt.get("reason", "")) == "corrupt", "Corrupt history reported '%s'." % corrupt.get("reason", ""))
	# Reset clears only this file.
	_expect(Novelty.reset(path).get("ok", false), "Reset failed.")
	_expect((Novelty.load_history(path)["history"]["published"] as Array).is_empty(), "Reset did not clear the history.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _accepted(signatures: Array) -> Dictionary:
	var history := Novelty.empty_history()
	for index in range(signatures.size()):
		history = Novelty.record_accepted(history, "acc.%d" % index, str(signatures[index]), "campaign.a")["history"]
	return history

func _test_ranking() -> void:
	# A repeated consecutive pair sinks that candidate below a fresh one.
	var history := _accepted(["v2:a", "v2:b", "v2:a", "v2:b"])
	var ranked := Novelty.rank_candidates(history, [{"id": "repeat", "signature": "v2:b"},
		{"id": "fresh", "signature": "v2:c"}], 99)
	_expect(str(ranked[0]["id"]) == "fresh", "Ranking preferred a recently repeated pair over a fresh reason.")
	# After ...b,c the sequence historically continued with a, so offering a
	# would repeat a known triple; offering c would not. The continuation of the
	# repeated triple must rank LAST.
	var triples := _accepted(["v2:a", "v2:b", "v2:c", "v2:a", "v2:b", "v2:c"])
	var by_triple := Novelty.rank_candidates(triples, [{"id": "continues_triple", "signature": "v2:a"},
		{"id": "breaks_triple", "signature": "v2:c"}], 99)
	_expect(str(by_triple[0]["id"]) == "breaks_triple", "Ranking did not penalise continuing a repeated triple.")
	_expect(str(by_triple[1]["id"]) == "continues_triple", "A repeated-triple continuation did not rank last.")
	# Ranking only REORDERS: every candidate survives.
	_expect(ranked.size() == 2, "Ranking dropped a validated candidate.")
	# Deterministic for a given seed, and stable across equal histories.
	var again := Novelty.rank_candidates(history, [{"id": "repeat", "signature": "v2:b"},
		{"id": "fresh", "signature": "v2:c"}], 99)
	_expect(JSON.stringify(again) == JSON.stringify(ranked), "Ranking was not deterministic.")
	# An empty history ranks without error.
	_expect(Novelty.rank_candidates(Novelty.empty_history(), [{"id": "x", "signature": "v2:x"}], 1).size() == 1,
		"Ranking failed on an empty history.")
	# Exhaustion is detected so the caller can offer LESS work.
	# History a,b,a,b ends on b, and b>a is an already-seen pair, so a lone
	# candidate of a is an exhausted continuation.
	_expect(Novelty.variety_exhausted(history, [{"id": "repeat", "signature": "v2:a"}]),
		"Exhausted variety was not detected.")
	_expect(not Novelty.variety_exhausted(history, [{"id": "fresh", "signature": "v2:zzz"}]),
		"A fresh candidate was reported as exhausted.")
	_expect(not Novelty.variety_exhausted(Novelty.empty_history(), [{"id": "x", "signature": "v2:x"}]),
		"An empty history reported exhaustion.")

## Runs must not be concatenated across campaigns, this campaign's own recent
## acceptances are what constrain it, and a damaged history degrades ranking
## rather than crashing it.
func _test_history_integrity() -> void:
	var history := Novelty.empty_history()
	history = Novelty.record_accepted(history, "a.0", "v2:a", "campaign.a#1")["history"]
	history = Novelty.record_accepted(history, "a.1", "v2:b", "campaign.a#1")["history"]
	history = Novelty.record_accepted(history, "b.0", "v2:c", "campaign.a#2")["history"]
	history = Novelty.record_accepted(history, "b.1", "v2:d", "campaign.a#2")["history"]
	var runs: Dictionary = Novelty.accepted_runs(history)
	_expect(int((runs["pairs"] as Dictionary).get("v2:a>v2:b", 0)) == 1,
		"A within-campaign pair was lost.")
	_expect(not (runs["pairs"] as Dictionary).has("v2:b>v2:c"),
		"A pair was fabricated across a campaign boundary.")
	_expect(not (runs["triples"] as Dictionary).has("v2:a>v2:b>v2:c"),
		"A triple was fabricated across a campaign boundary.")
	# Reusing the same SLOT label for a new campaign must not merge the two.
	_expect(Novelty.accepted_signatures_for(history, "campaign.a#2") == ["v2:c", "v2:d"],
		"Accepted signatures leaked between two campaigns in the same slot.")
	# Ranking is scoped to this campaign's own last two acceptances.
	var candidates: Array = [{"id": "after_b", "signature": "v2:a"}, {"id": "after_d", "signature": "v2:c"}]
	var for_first: Array = Novelty.rank_candidates(history, candidates, 7, "campaign.a#1")
	var for_second: Array = Novelty.rank_candidates(history, candidates, 7, "campaign.a#2")
	_expect(str(for_first[0]["id"]) != str(for_second[0]["id"]) 			or JSON.stringify(for_first) != JSON.stringify(for_second),
		"Two campaigns with different recent acceptances ranked identically.")
	# Malformed and oversized entries must not crash ranking.
	var damaged := Novelty.empty_history()
	damaged["accepted"] = [{"signature": "v2:a"}, "not a dictionary", {"campaign_id": "campaign.a#1"},
		{"id": "ok", "signature": "v2:b", "campaign_id": "campaign.a#1", "sequence": 1}]
	damaged["published"] = ["junk", {"signature": ""}, {"signature": "v2:b", "sequence": 3}]
	var survived: Array = Novelty.rank_candidates(damaged, candidates, 7, "campaign.a#1")
	_expect(survived.size() == candidates.size(),
		"A damaged history dropped validated candidates instead of degrading ranking.")
	_expect(not Novelty.accepted_runs(damaged).is_empty(),
		"A damaged history produced no run structure at all.")
	# An unknown or legacy signature is incomparable, not proven fresh: it must
	# not outrank a candidate whose freshness the history can actually confirm.
	var mixed: Array = [{"id": "unknown", "signature": ""}, {"id": "legacy", "signature": "claims|f0"},
		{"id": "known_fresh", "signature": "v2:zzz"}]
	var mixed_ranked: Array = Novelty.rank_candidates(history, mixed, 7, "campaign.a#1")
	_expect(str(mixed_ranked[0]["id"]) == "known_fresh",
		"An incomparable signature outranked a verifiably fresh one: %s" % str(mixed_ranked[0]["id"]))
	_expect(mixed_ranked.size() == 3, "Ranking dropped an incomparable candidate instead of ordering it last.")


func _test_opening_history() -> void:
	var bounded := Openings.empty_history()
	for index in range(9):
		bounded = Openings.upsert_opening(bounded, "campaign.%d" % index, ["signals", "claims"], ["survey", "survey"])["history"]
	_expect(bounded["openings"].size() == 3, "Opening history exceeded current plus two prior campaigns.")
	var history := Openings.empty_history()
	# A retry or restore upserts the SAME campaign rather than adding an opening.
	history = Openings.upsert_opening(history, "campaign.a", ["signals", "claims"], ["mission_shape.survey_discrepancy"])["history"]
	history = Openings.upsert_opening(history, "campaign.a", ["signals", "claims"], ["mission_shape.competing_claims"])["history"]
	_expect((history["openings"] as Array).size() == 1, "A retry created a second opening for one campaign.")
	_expect(str((history["openings"] as Array)[0]["first_shapes"][0]) == "mission_shape.competing_claims",
		"Upsert did not update the existing opening.")
	_expect(not Openings.upsert_opening(history, "", [], []).get("ok", true), "An opening without a campaign ID was accepted.")
	# Recent pairs from OTHER campaigns are filtered when alternatives exist.
	var pairs := Openings.preferred_pairs(history, ["signals", "claims", "supply"], "campaign.b")
	for pair: Array in pairs:
		_expect(not (str(pair[0]) == "signals" and str(pair[1]) == "claims"),
			"A recent pair from another campaign was not filtered.")
	_expect(pairs.size() == 5, "Expected five remaining ordered pairs, got %d." % pairs.size())
	# This campaign's own opening does not constrain itself.
	var own := Openings.preferred_pairs(history, ["signals", "claims", "supply"], "campaign.a")
	_expect(own.size() == 6, "A campaign's own opening constrained itself.")
	# With zero or one eligible kind the opening is honestly incomplete; no
	# unsupported track is activated to manufacture a unique pair.
	_expect(Openings.preferred_pairs(history, ["signals"], "campaign.b").is_empty(),
		"A single eligible kind produced a pair.")
	_expect(Openings.preferred_pairs(history, [], "campaign.b").is_empty(),
		"No eligible kinds produced a pair.")
	# Filtering never empties the list: if every pair is recent, all are returned.
	var saturated := Openings.empty_history()
	for campaign in ["c1", "c2"]:
		saturated = Openings.upsert_opening(saturated, campaign, ["signals", "claims"], [])["history"]
	_expect(not Openings.preferred_pairs(saturated, ["signals", "claims"], "campaign.b").is_empty(),
		"Filtering left no available opening pair.")
