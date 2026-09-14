extends MissionCapability

## Investigation contracts (plan P2): the player scans sites, compares evidence,
## and picks one terminal resolution.
##
## PURE. No scene lookups, no node access, no globals -- everything arrives in
## `data` and `event_data` and everything leaves as mutations plus a result
## dictionary of requested side effects. That is what makes the branch rules
## testable without a running game, which matters because these rules decide
## payouts and consumable spend.
##
## Three invariants worth stating, because each protects a player-visible
## failure:
##   1. Completion is NEVER inferred from "both sites scanned". Only a terminal
##      choice, or a completed extraction, sets phase=ready. Scanning everything
##      and wandering off must leave the contract open.
##   2. Commands are idempotent by id. A duplicate resolve returns the original
##      result and never spends a second consumable.
##   3. Prerequisites are revalidated at execution, never trusted from whatever
##      enabled the button.

const PHASE_SEARCH := "search"
const PHASE_IDENTIFIED := "identified"
const PHASE_READY := "ready"
const PHASE_CLOSED := "closed"

const ROLE_PRIMARY := "primary"
const ROLE_VERIFICATION := "verification"

## branch -> [numerator, denominator] against the approved offer budget B.
## Multiplied once, floored, at turn-in. No credits are awarded at the site.
const PAYOUT: Dictionary = {
	"report": [1, 2],
	"certify_match": [1, 1],
	"certify_mismatch": [1, 1],
	"preserve": [1, 1],
	"liquidate": [3, 2],
	"extract": [3, 2],
	"stabilize": [5, 4],
	"reconstruct": [1, 1],
}
## A wrong certification still turns in, at a quarter. Being wrong costs money;
## it does not strand the contract.
const MISTAKEN_PAYOUT: Array[int] = [1, 4]
## The lure pays more for a report because declining to approach is the whole
## decision being offered.
const LURE_REPORT_PAYOUT: Array[int] = [3, 4]

## branch -> which scans must already exist.
const BRANCH_REQUIREMENTS: Dictionary = {
	"report": ["primary"],
	"certify_match": ["primary", "verification"],
	"certify_mismatch": ["primary", "verification"],
	"preserve": ["primary", "verification"],
	"reconstruct": ["primary", "verification"],
	"liquidate": ["primary"],
	"stabilize": ["primary"],
	"extract": ["primary"],
}

## branch -> consumable item id spent exactly once on acceptance.
const BRANCH_CONSUMABLE: Dictionary = {
	"liquidate": "salvage_drone",
	"stabilize": "repair_kit",
}


func capability_id() -> String:
	return "investigate_signal"


func supported_objective_types() -> Array[String]:
	return ["INVESTIGATE_SIGNAL"]


## Ready only. Deliberately NOT "both sites scanned" -- see invariant 1.
func is_completed(data: Dictionary) -> bool:
	return str(_state(data).get("phase", PHASE_SEARCH)) == PHASE_READY


func _state(data: Dictionary) -> Dictionary:
	var raw = data.get("investigation", {})
	return raw if raw is Dictionary else {}


func _scanned(state: Dictionary) -> Array:
	var raw = state.get("scanned_site_ids", [])
	return raw if raw is Array else []


func _site(state: Dictionary, site_id: String) -> Dictionary:
	for raw in (state.get("sites", []) as Array if state.get("sites", []) is Array else []):
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == site_id:
			return raw
	return {}


func _role_scanned(state: Dictionary, role: String) -> bool:
	for site_id in _scanned(state):
		if str(_site(state, str(site_id)).get("role", "")) == role:
			return true
	return false


func handle_event(data: Dictionary, event: String, event_data: Dictionary) -> Dictionary:
	if event != "investigation_command":
		return {}
	var state := _state(data)
	if state.is_empty():
		return {"accepted": false, "reason": "no_investigation_state"}

	# Idempotency first, before any validation. A command that already applied
	# must return its original outcome even if the world has since changed --
	# re-validating a replayed command could reject it and lose the result.
	var command_id := str(event_data.get("command_id", "")).strip_edges()
	var applied: Dictionary = state.get("applied_commands", {}) \
		if state.get("applied_commands", {}) is Dictionary else {}
	if not command_id.is_empty() and applied.has(command_id):
		var previous: Dictionary = applied[command_id]
		previous = previous.duplicate(true)
		previous["replayed"] = true
		return previous

	# Revision guard: a stale UI must not act on a state it no longer sees.
	var expected := int(event_data.get("expected_revision", -1))
	var current := int(state.get("investigation_revision", 0))
	if expected >= 0 and expected != current:
		return {"accepted": false, "reason": "stale_revision", "expected": current}

	var action := str(event_data.get("action", ""))
	var result: Dictionary = {}
	match action:
		"scan_complete":
			result = _apply_scan(state, event_data)
		"resolve":
			result = _apply_resolve(data, state, event_data)
		"extract_complete":
			result = _apply_extract_complete(state)
		_:
			result = {"accepted": false, "reason": "unknown_action"}

	if bool(result.get("accepted", false)):
		state["investigation_revision"] = current + 1
		if not command_id.is_empty():
			applied[command_id] = result.duplicate(true)
			state["applied_commands"] = applied
	data["investigation"] = state
	return result


## A completed scan records evidence. It never completes the contract, and it
## never decides anything -- the values it copies were generated in code when the
## offer was made.
func _apply_scan(state: Dictionary, event_data: Dictionary) -> Dictionary:
	if str(state.get("phase", PHASE_SEARCH)) in [PHASE_READY, PHASE_CLOSED]:
		return {"accepted": false, "reason": "already_resolved"}
	var site_id := str(event_data.get("site_id", ""))
	var site := _site(state, site_id)
	if site.is_empty():
		return {"accepted": false, "reason": "unknown_site"}
	var scanned := _scanned(state)
	if scanned.has(site_id):
		return {"accepted": true, "reason": "already_scanned", "progress_changed": false}
	# The verification site stays hidden and unscannable until the primary is
	# done, even if the player stumbles across it first.
	if str(site.get("role", "")) == ROLE_VERIFICATION and not _role_scanned(state, ROLE_PRIMARY):
		return {"accepted": false, "reason": "verification_locked"}

	scanned.append(site_id)
	state["scanned_site_ids"] = scanned
	site["reveal_state"] = "identified"
	var evidence: Array = state.get("evidence", []) if state.get("evidence", []) is Array else []
	evidence.append({
		"id": "%s.evidence.%s" % [
			str(state.get("mission_id", "mission")), str(site.get("role", "site"))
		],
		"site_id": site_id,
		"observed_code": str(site.get("code", "")),
		"observed_owner_id": str(site.get("owner_faction_id", "")),
		"observed_minute": int(event_data.get("minute", 0)),
	})
	state["evidence"] = evidence
	if str(state.get("phase", PHASE_SEARCH)) == PHASE_SEARCH:
		state["phase"] = PHASE_IDENTIFIED
	return {
		"accepted": true,
		"progress_changed": true,
		"role": str(site.get("role", "")),
		# The first scan is what marks the second site, so the UI needs to know.
		"reveals_verification": str(site.get("role", "")) == ROLE_PRIMARY,
	}


## The terminal choice. Validates prerequisites here rather than trusting the
## button that produced the command, then fixes the payout and outcome.
func _apply_resolve(data: Dictionary, state: Dictionary, event_data: Dictionary) -> Dictionary:
	var phase := str(state.get("phase", PHASE_SEARCH))
	if phase in [PHASE_READY, PHASE_CLOSED]:
		return {"accepted": false, "reason": "already_resolved"}
	var branch := str(event_data.get("branch_id", ""))
	var allowed: Array = data.get("branch_ids", []) if data.get("branch_ids", []) is Array else []
	if not allowed.is_empty() and not allowed.has(branch):
		return {"accepted": false, "reason": "branch_not_offered"}
	if not BRANCH_REQUIREMENTS.has(branch):
		return {"accepted": false, "reason": "unknown_branch"}
	# Once extraction is committed its hostile may already exist, so the player
	# cannot quietly switch to a safer branch and keep the danger behind them.
	var committed := str(state.get("branch_id", ""))
	if committed == "extract" and branch != "extract":
		return {"accepted": false, "reason": "extraction_committed"}
	for role in (BRANCH_REQUIREMENTS[branch] as Array):
		if not _role_scanned(state, str(role)):
			return {"accepted": false, "reason": "missing_scan", "needs_role": str(role)}

	var result := {"accepted": true, "progress_changed": true, "branch_id": branch}
	var consumable := str(BRANCH_CONSUMABLE.get(branch, ""))
	if not consumable.is_empty():
		if not bool(event_data.get("has_consumable", false)):
			return {"accepted": false, "reason": "missing_consumable", "item": consumable}
		# Spend is requested once, here, and the idempotency record above is what
		# stops a replayed command spending a second one.
		result["spend_consumable"] = consumable
		state["consumable_spent"] = true

	state["branch_id"] = branch
	if branch == "extract":
		# Committing to extraction is not completing it: the run out to the cache
		# still has to happen, and a forged beacon spawns its hostile on the way.
		state["phase"] = PHASE_IDENTIFIED
		result["awaiting_extraction"] = true
		result["spawn_hostile"] = bool(state.get("forged", false))
		return result

	var payout := _payout_for(state, branch, event_data)
	state["payout_numerator"] = payout[0]
	state["payout_denominator"] = payout[1]
	state["outcome_tag"] = _outcome_tag(state, branch, payout)
	state["phase"] = PHASE_READY
	result["payout_numerator"] = payout[0]
	result["payout_denominator"] = payout[1]
	result["outcome_tag"] = str(state["outcome_tag"])
	result["ready_to_turn_in"] = true
	return result


## Extraction completes only when the player actually reaches the cache.
func _apply_extract_complete(state: Dictionary) -> Dictionary:
	if str(state.get("branch_id", "")) != "extract":
		return {"accepted": false, "reason": "extraction_not_committed"}
	if str(state.get("phase", "")) == PHASE_READY:
		return {"accepted": false, "reason": "already_resolved"}
	var payout: Array = PAYOUT["extract"]
	state["payout_numerator"] = payout[0]
	state["payout_denominator"] = payout[1]
	state["outcome_tag"] = "extracted"
	state["phase"] = PHASE_READY
	return {
		"accepted": true,
		"progress_changed": true,
		"payout_numerator": payout[0],
		"payout_denominator": payout[1],
		"outcome_tag": "extracted",
		"ready_to_turn_in": true,
	}


## Truth was fixed in code when the offer was made; this only compares against it.
func _payout_for(state: Dictionary, branch: String, event_data: Dictionary) -> Array:
	if branch == "report":
		if str(state.get("recipe", "")) == "transmitter_lure":
			return LURE_REPORT_PAYOUT
		return PAYOUT["report"]
	if branch in ["certify_match", "certify_mismatch"]:
		return PAYOUT[branch] if _certification_correct(state, branch) else MISTAKEN_PAYOUT
	return PAYOUT.get(branch, [1, 1])


func _certification_correct(state: Dictionary, branch: String) -> bool:
	var primary := ""
	var verification := ""
	for raw in (state.get("sites", []) as Array if state.get("sites", []) is Array else []):
		if not raw is Dictionary:
			continue
		var site: Dictionary = raw
		if str(site.get("role", "")) == ROLE_PRIMARY:
			primary = str(site.get("code", ""))
		elif str(site.get("role", "")) == ROLE_VERIFICATION:
			verification = str(site.get("code", ""))
	var codes_match := primary == verification
	return codes_match if branch == "certify_match" else not codes_match


## Keeps "a verified lure report" distinguishable from "an unverified report":
## the tag records WHAT was decided, and `verified` separately records whether
## both sites were actually scanned.
func _outcome_tag(state: Dictionary, branch: String, payout: Array) -> String:
	match branch:
		"report":
			return "unverified"
		"certify_match", "certify_mismatch":
			return "verified" if payout != MISTAKEN_PAYOUT else "mistaken"
		"preserve", "stabilize":
			return "preserved"
		"liquidate":
			return "liquidated"
		"reconstruct":
			return "copied"
	return ""


func format_tracker_text(data: Dictionary) -> String:
	var state := _state(data)
	match str(state.get("phase", PHASE_SEARCH)):
		PHASE_SEARCH:
			return "Locate the signal source."
		PHASE_IDENTIFIED:
			if str(state.get("branch_id", "")) == "extract":
				return "Approach the cache and extract."
			if _role_scanned(state, ROLE_VERIFICATION):
				return "Evidence gathered — choose how to resolve."
			return "Scanned. A second contact has been marked."
		PHASE_READY:
			return "Resolved — return to the station."
	return "Investigation closed."
