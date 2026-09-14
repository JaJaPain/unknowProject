extends SceneTree

# Branch rules decide payouts and consumable spend, so they are pinned here
# rather than trusted. The capability is pure, so all of this runs without a game.

const CapabilityType := preload(
	"res://scripts/domain/capabilities/InvestigateSignalCapability.gd"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_test_completion_is_never_inferred_from_scanning()
	_test_verification_locked_until_primary()
	_test_certification_pays_on_being_right()
	_test_prerequisites_are_revalidated()
	_test_commands_are_idempotent()
	_test_extraction_commits_then_completes()
	if _failures.is_empty():
		print("[PASS] Investigate signal capability tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _mission(recipe: String, primary_code: String, verify_code: String) -> Dictionary:
	return {
		"type": "INVESTIGATE_SIGNAL",
		"branch_ids": ["report", "certify_match", "certify_mismatch", "preserve",
			"liquidate", "extract", "stabilize", "reconstruct"],
		"investigation": {
			"version": 1,
			"mission_id": "m1",
			"recipe": recipe,
			"phase": "search",
			"scanned_site_ids": [],
			"evidence": [],
			"branch_id": "",
			"outcome_tag": "",
			"investigation_revision": 0,
			"forged": verify_code != primary_code,
			"sites": [
				{"id": "s1", "role": "primary", "code": primary_code, "owner_faction_id": ""},
				{"id": "s2", "role": "verification", "code": verify_code, "owner_faction_id": ""},
			],
		},
	}


func _scan(cap, data: Dictionary, site_id: String, cmd: String = "") -> Dictionary:
	return cap.handle_event(data, "investigation_command", {
		"action": "scan_complete", "site_id": site_id, "command_id": cmd,
	})


func _resolve(cap, data: Dictionary, branch: String, extras: Dictionary = {}) -> Dictionary:
	var payload := {"action": "resolve", "branch_id": branch}
	for k in extras.keys():
		payload[k] = extras[k]
	return cap.handle_event(data, "investigation_command", payload)


# Scanning everything and wandering off must leave the contract OPEN. Inferring
# completion from "both scanned" would hand the player a turn-in they never chose.
func _test_completion_is_never_inferred_from_scanning() -> void:
	var cap = CapabilityType.new()
	var data := _mission("survey_discrepancy", "A", "A")
	_scan(cap, data, "s1")
	_scan(cap, data, "s2")
	_expect(
		not cap.is_completed(data),
		"Both sites scanned must NOT complete the contract."
	)
	_expect(
		str(data["investigation"]["phase"]) == "identified",
		"Phase should be identified after scanning, got %s" % str(data["investigation"]["phase"])
	)
	_resolve(cap, data, "report")
	_expect(cap.is_completed(data), "A terminal choice must complete it.")


# The second site is a mission secret until the first scan marks it.
func _test_verification_locked_until_primary() -> void:
	var cap = CapabilityType.new()
	var data := _mission("survey_discrepancy", "A", "B")
	var early := _scan(cap, data, "s2")
	_expect(
		not bool(early.get("accepted", false)) \
			and str(early.get("reason", "")) == "verification_locked",
		"Scanning the verification site first must be refused, got %s" % str(early)
	)
	var first := _scan(cap, data, "s1")
	_expect(
		bool(first.get("reveals_verification", false)),
		"The primary scan is what marks the second site."
	)
	_expect(bool(_scan(cap, data, "s2").get("accepted", false)), "Now it should scan.")


# Being wrong costs money but still turns in. Being right pays full.
func _test_certification_pays_on_being_right() -> void:
	# Codes match -> certify_match is correct.
	var cap = CapabilityType.new()
	var matching := _mission("survey_discrepancy", "A", "A")
	_scan(cap, matching, "s1")
	_scan(cap, matching, "s2")
	var right := _resolve(cap, matching, "certify_match")
	_expect(
		int(right.get("payout_numerator", 0)) == 1 and int(right.get("payout_denominator", 0)) == 1,
		"Correct certification pays the full budget, got %s/%s" % [
			str(right.get("payout_numerator")), str(right.get("payout_denominator"))
		]
	)
	_expect(str(right.get("outcome_tag", "")) == "verified", "Correct call is 'verified'.")

	var wrong_cap = CapabilityType.new()
	var differing := _mission("survey_discrepancy", "A", "B")
	_scan(wrong_cap, differing, "s1")
	_scan(wrong_cap, differing, "s2")
	var wrong := _resolve(wrong_cap, differing, "certify_match")
	_expect(
		bool(wrong.get("accepted", false)),
		"A wrong call must still be accepted and turn in."
	)
	_expect(
		int(wrong.get("payout_numerator", 0)) == 1 and int(wrong.get("payout_denominator", 0)) == 4,
		"A wrong call pays a quarter, got %s/%s" % [
			str(wrong.get("payout_numerator")), str(wrong.get("payout_denominator"))
		]
	)
	_expect(str(wrong.get("outcome_tag", "")) == "mistaken", "Wrong call is 'mistaken'.")

	# A lure report pays more than an ordinary one: declining to approach IS the
	# decision being sold.
	var lure_cap = CapabilityType.new()
	var lure := _mission("transmitter_lure", "A", "B")
	_scan(lure_cap, lure, "s1")
	var reported := _resolve(lure_cap, lure, "report")
	_expect(
		int(reported.get("payout_numerator", 0)) == 3 \
			and int(reported.get("payout_denominator", 0)) == 4,
		"Lure report pays 3/4, got %s/%s" % [
			str(reported.get("payout_numerator")), str(reported.get("payout_denominator"))
		]
	)
	_expect(str(reported.get("outcome_tag", "")) == "unverified", "A report is 'unverified'.")


# Requirements are checked at EXECUTION, not at button-enable time.
func _test_prerequisites_are_revalidated() -> void:
	var cap = CapabilityType.new()
	var data := _mission("survey_discrepancy", "A", "B")
	var too_early := _resolve(cap, data, "certify_match")
	_expect(
		str(too_early.get("reason", "")) == "missing_scan",
		"Certifying with no scans must be refused, got %s" % str(too_early)
	)
	_scan(cap, data, "s1")
	_expect(
		str(_resolve(cap, data, "certify_match").get("reason", "")) == "missing_scan",
		"Certifying needs BOTH scans."
	)
	# A consumable branch is refused when the item is absent, and 'report'
	# remains available so the contract is never stranded.
	var claims_cap = CapabilityType.new()
	var claims := _mission("competing_claims", "A", "A")
	_scan(claims_cap, claims, "s1")
	var no_item := _resolve(claims_cap, claims, "liquidate")
	_expect(
		str(no_item.get("reason", "")) == "missing_consumable",
		"Liquidate without a drone must be refused, got %s" % str(no_item)
	)
	_expect(
		bool(_resolve(claims_cap, claims, "report").get("accepted", false)),
		"'report' must remain available so a missing item cannot strand the job."
	)
	# With the item, the spend is requested exactly once.
	var ok_cap = CapabilityType.new()
	var ok := _mission("competing_claims", "A", "A")
	_scan(ok_cap, ok, "s1")
	var spent := _resolve(ok_cap, ok, "liquidate", {"has_consumable": true})
	_expect(
		str(spent.get("spend_consumable", "")) == "salvage_drone",
		"Liquidate must request the drone spend."
	)
	_expect(str(spent.get("outcome_tag", "")) == "liquidated", "Tag should be 'liquidated'.")


# A replayed command must return the ORIGINAL result and never double-spend.
func _test_commands_are_idempotent() -> void:
	var cap = CapabilityType.new()
	var data := _mission("competing_claims", "A", "A")
	_scan(cap, data, "s1", "m1:s1:scan")
	var first := cap.handle_event(data, "investigation_command", {
		"action": "resolve", "branch_id": "liquidate",
		"has_consumable": true, "command_id": "m1:resolve",
	})
	var replay := cap.handle_event(data, "investigation_command", {
		"action": "resolve", "branch_id": "liquidate",
		"has_consumable": true, "command_id": "m1:resolve",
	})
	_expect(bool(replay.get("replayed", false)), "A duplicate must be marked replayed.")
	_expect(
		str(replay.get("spend_consumable", "")) == str(first.get("spend_consumable", "")),
		"A replay must return the original result."
	)
	_expect(
		int(data["investigation"]["investigation_revision"]) == 2,
		"A replay must NOT advance the revision, got %d" % int(
			data["investigation"]["investigation_revision"]
		)
	)
	# A stale revision is refused outright.
	var stale = cap.handle_event(data, "investigation_command", {
		"action": "scan_complete", "site_id": "s2", "expected_revision": 0,
	})
	_expect(
		str(stale.get("reason", "")) == "stale_revision",
		"A command built against an old revision must be refused."
	)


# Committing to extraction is not completing it, and there is no way back.
func _test_extraction_commits_then_completes() -> void:
	var cap = CapabilityType.new()
	var data := _mission("transmitter_lure", "A", "B")   # forged
	_scan(cap, data, "s1")
	var commit := _resolve(cap, data, "extract")
	_expect(
		bool(commit.get("awaiting_extraction", false)) and not cap.is_completed(data),
		"Committing to extract must not complete the contract."
	)
	_expect(
		bool(commit.get("spawn_hostile", false)),
		"A forged beacon must request its hostile on commitment."
	)
	_expect(
		str(_resolve(cap, data, "report").get("reason", "")) == "extraction_committed",
		"After committing, the player cannot retreat to a safer branch."
	)
	var done = cap.handle_event(data, "investigation_command", {"action": "extract_complete"})
	_expect(cap.is_completed(data), "Reaching the cache completes it.")
	_expect(
		int(done.get("payout_numerator", 0)) == 3 and int(done.get("payout_denominator", 0)) == 2,
		"Extraction pays 3/2."
	)
	# A genuine beacon spawns nothing.
	var clean_cap = CapabilityType.new()
	var clean := _mission("transmitter_lure", "A", "A")
	_scan(clean_cap, clean, "s1")
	_expect(
		not bool(_resolve(clean_cap, clean, "extract").get("spawn_hostile", true)),
		"A genuine beacon must not spawn a hostile."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
