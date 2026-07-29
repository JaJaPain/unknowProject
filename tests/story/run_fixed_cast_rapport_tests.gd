extends SceneTree

const RapportType := preload("res://scripts/story/FixedCastRapport.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	var initial := RapportType.initialize_after_tutorial(RapportType.default_ledger(), "campaign.alpha")
	_expect(bool(initial.get("initialized_after_tutorial", false)), "Rapport should initialize after tutorial.")
	_expect(JSON.stringify(initial) == JSON.stringify(RapportType.initialize_after_tutorial(initial, "campaign.other")), "Rapport initialization must be one-time and reload-stable.")
	_expect(RapportType.band_for_score(-5) == "irritated" and RapportType.band_for_score(5) == "infatuated", "Rapport scale endpoints are wrong.")
	var hard_paid_battle := RapportType.apply_mission_event(initial, "completed", {"objective": {"type": "KILL_SHIPS", "reward_credits": 350}, "difficulty_band": "dangerous"}, 42)
	_expect(int((hard_paid_battle.get("kaelen", {}) as Dictionary).get("score", 0)) > int((initial.get("kaelen", {}) as Dictionary).get("score", 0)), "Lucrative completed battle should endear Kaelen.")
	_expect(int((hard_paid_battle.get("nova", {}) as Dictionary).get("score", 0)) < int((initial.get("nova", {}) as Dictionary).get("score", 0)), "Grueling completed battle should make Nova less happy with the Captain.")
	var ordinary_battle := RapportType.apply_mission_event(initial, "completed", {"objective": {"type": "KILL_SHIPS", "reward_credits": 350}}, 42)
	_expect(int((ordinary_battle.get("nova", {}) as Dictionary).get("score", 0)) > int((initial.get("nova", {}) as Dictionary).get("score", 0)), "Ordinary completed combat should not be treated as a grueling battle.")
	var optional_attachment_decline := RapportType.apply_mission_event(initial, "declined", {
		"objective_type": "DELIVERY_COURIER",
		"narrative_metadata": {"attachment_beats": [{"character_id": "kaelen", "beat_id": "private_texture"}]},
	}, 43)
	_expect(JSON.stringify(optional_attachment_decline) == JSON.stringify(initial), "Declining an optional attachment opportunity must not lower fixed-cast rapport.")
	var uninitialized := RapportType.apply_mission_event(RapportType.default_ledger(), "completed", {"objective_type": "KILL_SHIPS"}, 1)
	_expect(JSON.stringify(uninitialized) == JSON.stringify(RapportType.default_ledger()), "Pre-tutorial missions must not change rapport.")
	if _failures.is_empty():
		print("[PASS] Fixed-cast rapport tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
