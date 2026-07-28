extends SceneTree

const AttachmentType := preload("res://scripts/story/FixedCastAttachmentLedger.gd")
const StateType := preload("res://scripts/story/FixedCastStateMachine.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	var attachments := AttachmentType.default_ledger()
	var states := StateType.default_ledger()
	_expect(StateType.state_for("kaelen", states) == "broker_neutral", "Kaelen must begin in broker_neutral.")
	_expect(StateType.state_for("nova", states) == "observant", "N.O.V.A. must begin observant.")
	attachments = AttachmentType.advance(attachments, "mission_completed", {"is_intro_tutorial": true}, 1)
	_expect(AttachmentType.has_completed("kaelen", "first_impression", attachments), "Tutorial completion must begin Kaelen's attachment arc.")
	_expect(AttachmentType.has_completed("nova", "first_impression", attachments), "Tutorial completion must begin N.O.V.A.'s attachment arc.")
	var eligible: Array[Dictionary] = AttachmentType.eligible_chapter_beats(attachments)
	_expect(
		eligible.size() == 2
			and str(eligible[0].get("beat_id", "")) == "private_texture"
			and str(eligible[1].get("beat_id", "")) == "private_texture",
		"Chapter attachment eligibility must expose only each character's next unfinished beat."
	)
	attachments = AttachmentType.advance(attachments, "system_arrived", {}, 2)
	attachments = AttachmentType.advance(attachments, "mission_completed", {"reward_credits": 350, "difficulty_band": "dangerous"}, 3)
	_expect(AttachmentType.has_completed("kaelen", "mutual_reliance", attachments), "A profitable completion should advance Kaelen's mutual-reliance beat.")
	_expect(AttachmentType.has_completed("nova", "mutual_reliance", attachments), "A known-dangerous completion should advance N.O.V.A.'s mutual-reliance beat.")
	attachments = AttachmentType.advance(attachments, "mission_completed", {"reward_credits": 150}, 4)
	attachments = AttachmentType.advance(attachments, "system_arrived", {}, 5)
	_expect(AttachmentType.has_completed("nova", "earned_change", attachments), "N.O.V.A.'s earned change must require the recorded prior beats.")
	states = StateType.apply_event(states, "mission_accepted", {"difficulty_band": "dangerous"}, attachments, 6)
	_expect(StateType.state_for("nova", states) == "protective", "Only a known-dangerous accepted mission should select N.O.V.A.'s protective state.")
	states = StateType.apply_event(states, "mission_completed", {"reward_credits": 350}, attachments, 7)
	_expect(StateType.state_for("kaelen", states) == "quietly_relieved", "A completed mission should select Kaelen's restrained completion state.")
	states = StateType.apply_event(states, "system_arrived", {}, attachments, 8)
	_expect(StateType.state_for("nova", states) == "earned_resolve", "N.O.V.A.'s earned-resolve state must be gated by her completed attachment arc.")
	var ordinary := StateType.apply_event(StateType.default_ledger(), "mission_accepted", {"objective_type": "KILL_SHIPS"}, AttachmentType.default_ledger(), 1)
	_expect(StateType.state_for("nova", ordinary) == "observant", "Ordinary combat must not be treated as a known-dangerous mission.")
	if _failures.is_empty():
		print("[PASS] Fixed-cast state and attachment tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
