extends RefCounted

const ResultType := preload("res://scripts/domain/ValidationResult.gd")
const BRANCHES := {
	"survey_discrepancy": ["report", "certify_match", "certify_mismatch"],
	"competing_claims": ["report", "preserve", "liquidate"],
}
const COPY_FIELDS := ["shape_id", "recipe", "branch_ids", "mission_site_ids", "turn_in_station_id", "investigation"]

static func validate(data: Dictionary) -> RefCounted:
	var result := ResultType.new()
	var raw: Variant = data.get("investigation", {})
	if not raw is Dictionary or raw.is_empty():
		result.add_error("invalid_investigation", "Investigation state is missing.", "investigation")
		return result
	var state: Dictionary = raw
	var recipe := str(data.get("recipe", ""))
	if not BRANCHES.has(recipe) or str(state.get("recipe", "")) != recipe:
		result.add_error("unsupported_investigation_recipe", "This investigation recipe has no runtime handler.", "recipe")
		return result
	for key in ["shape_id", "turn_in_station_id"]:
		if str(data.get(key, "")).is_empty():
			result.add_error("missing_investigation_binding", "Missing %s." % key, key)
	if int(state.get("version", 0)) != 1 or str(state.get("mission_id", "")).is_empty():
		result.add_error("invalid_investigation_version", "Invalid investigation identity/version.", "investigation")
	var offered: Variant = data.get("branch_ids", [])
	if not offered is Array or offered.is_empty():
		result.add_error("missing_investigation_branches", "A resolution path is required.", "branch_ids")
		return result
	var seen_branches := {}
	for branch in offered:
		if branch not in BRANCHES[recipe] or seen_branches.has(branch):
			result.add_error("invalid_investigation_branch", "Unsupported or duplicate branch.", "branch_ids")
		seen_branches[branch] = true
	# No consumable may be the only way out of an accepted contract.
	if "report" not in offered:
		result.add_error("missing_report_path", "The no-cost report path is required.", "branch_ids")
	var sites: Variant = state.get("sites", [])
	if not sites is Array or sites.size() != 2:
		result.add_error("invalid_investigation_sites", "Exactly two saved sites are required.", "sites")
		return result
	var ids := {}
	var roles := {}
	for site in sites:
		if not site is Dictionary:
			result.add_error("invalid_investigation_site", "Invalid site record.", "sites")
			continue
		var id := str(site.get("id", ""))
		var role := str(site.get("role", ""))
		if id.is_empty() or ids.has(id) or role not in ["primary", "verification"] or roles.has(role) or not _position(site.get("position")) or str(site.get("system_id", "")).is_empty():
			result.add_error("invalid_investigation_site", "Invalid site identity, role, system or position.", "sites")
		ids[id] = site
		roles[role] = id
		if data.has("system_id") and str(site.get("system_id", "")) != str(data["system_id"]):
			result.add_error("wrong_investigation_system", "Site is outside the mission system.", "sites")
		if recipe == "survey_discrepancy" and str(site.get("code", "")) not in ["A", "B"]:
			result.add_error("invalid_evidence_code", "Missing comparison code.", "sites")
		if recipe == "competing_claims" and role == "verification" and str(site.get("owner_faction_id", "")).is_empty():
			result.add_error("missing_claim_owner", "Recorder ownership must be bound before publication.", "sites")
	var site_ids: Variant = data.get("mission_site_ids", [])
	if not site_ids is Array or site_ids.size() != 2 or site_ids[0] == site_ids[1]:
		result.add_error("invalid_site_binding", "Site references must match saved sites.", "mission_site_ids")
	else:
		for id in site_ids:
			if not ids.has(id):
				result.add_error("invalid_site_binding", "Unknown site reference.", "mission_site_ids")
	if not result.is_valid():
		return result
	var center: Variant = state.get("search_center", [])
	var radius := float(state.get("search_radius", 0.0))
	if not _position(center) or not is_finite(radius) or radius <= 0.0:
		result.add_error("invalid_search_region", "Investigation needs a finite search region.", "search_center")
		return result
	var primary_position: Array = ids[roles["primary"]]["position"]
	if Vector3(center[0], center[1], center[2]).distance_to(Vector3(primary_position[0], primary_position[1], primary_position[2])) > radius:
		result.add_error("site_outside_search_region", "The primary site must be inside its advertised search region.", "search_center")
	var scanned: Variant = state.get("scanned_site_ids", [])
	var evidence: Variant = state.get("evidence", [])
	if not scanned is Array or not evidence is Array:
		result.add_error("invalid_evidence", "Evidence must be an array.", "evidence")
		return result
	var unique := {}
	for id in scanned:
		if not ids.has(id) or unique.has(id):
			result.add_error("invalid_evidence", "Duplicate or unknown scanned site.", "scanned_site_ids")
		unique[id] = true
	if scanned.has(roles.get("verification", "")) and not scanned.has(roles.get("primary", "")):
		result.add_error("invalid_evidence_order", "Verification needs the primary scan.", "scanned_site_ids")
	var evidence_ids := {}
	for entry in evidence:
		if not entry is Dictionary or not ids.has(entry.get("site_id", "")):
			result.add_error("invalid_evidence", "Evidence references an unknown site.", "evidence")
			continue
		var id := str(entry["site_id"])
		if not scanned.has(id) or evidence_ids.has(id) or str(entry.get("observed_code", "")) != str(ids[id].get("code", "")) or str(entry.get("observed_owner_id", "")) != str(ids[id].get("owner_faction_id", "")):
			result.add_error("invalid_evidence", "Evidence disagrees with saved truth.", "evidence")
		evidence_ids[id] = true
	if evidence_ids.size() != unique.size():
		result.add_error("missing_scan_evidence", "A completed scan must carry its evidence.", "evidence")
	# Frozen pressure terms: a branch payout snapshot may only name offered
	# branches and may never be negative. Absent means ordinary fractions apply.
	var payouts: Variant = state.get("branch_payouts", {})
	if not payouts is Dictionary:
		result.add_error("invalid_branch_payouts", "Frozen branch payouts must be an object.", "investigation")
	else:
		for branch: Variant in (payouts as Dictionary):
			if str(branch) not in offered:
				result.add_error("unoffered_branch_payout", "A frozen payout names a branch this contract does not offer.", "investigation")
			var amount: Variant = (payouts as Dictionary)[branch]
			if not (amount is int or amount is float) or float(amount) < 0.0 or not is_equal_approx(float(amount), floorf(float(amount))):
				result.add_error("invalid_branch_payout", "A frozen branch payout must be a non-negative integer.", "investigation")
	var phase := str(state.get("phase", ""))
	var chosen := str(state.get("branch_id", ""))
	if phase not in ["search", "identified", "ready", "closed"] or int(state.get("investigation_revision", -1)) < 0 or not state.get("applied_commands", {}) is Dictionary:
		result.add_error("invalid_investigation_progress", "Invalid investigation progress.", "investigation")
	if phase in ["ready", "closed"]:
		if chosen not in offered or scanned.is_empty() or (chosen in ["preserve", "certify_match", "certify_mismatch"] and scanned.size() != 2):
			result.add_error("invalid_investigation_resolution", "Resolution lacks its offered branch or evidence.", "investigation")
		else:
			var fraction := [1, 1]
			var tag := "preserved"
			match chosen:
				"report":
					fraction = [1, 2]
					tag = "unverified"
				"liquidate":
					fraction = [3, 2]
					tag = "liquidated"
				"certify_match", "certify_mismatch":
					var matches: bool = str(ids[roles["primary"]].get("code", "")) == str(ids[roles["verification"]].get("code", ""))
					var correct: bool = matches if chosen == "certify_match" else not matches
					fraction = [1, 1] if correct else [1, 4]
					tag = "verified" if correct else "mistaken"
			if int(state.get("payout_numerator", 0)) != fraction[0] or int(state.get("payout_denominator", 0)) != fraction[1] or str(state.get("outcome_tag", "")) != tag or bool(state.get("consumable_spent", false)) != (chosen == "liquidate"):
				result.add_error("invalid_investigation_result", "Saved payout/outcome disagrees with the chosen action.", "investigation")
	elif not chosen.is_empty() or (phase == "search" and not scanned.is_empty()) or (phase == "identified" and scanned.is_empty()):
		result.add_error("invalid_investigation_progress", "Phase disagrees with evidence/decision.", "investigation")
	return result

static func _position(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)):
			return false
	return true
