extends SceneTree

## Core loop step 11c (Abe, 2026-10-02): once per campaign, a few jumps out,
## one deeper gate Kaelen can't buy open. She has one job, and only that job,
## until it's done; she never says what it's for. Then the gate's route is for
## sale at her usual price, with a half-hint, once.
##   Godot --headless --path . --script res://tests/story/run_kaelen_locked_gate_tests.gd --log-file <path>

const Locked := preload("res://scripts/story/KaelenLockedGate.gd")
const ReservedTopics := preload("res://scripts/story/ReservedTopics.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var story := {"first_contract_handed_in": false}
	_check(not Locked.maybe_lock(story, "gate.x", 5), "never during the tutorial")
	story["first_contract_handed_in"] = true
	_check(not Locked.maybe_lock(story, "gate.x", 2), "not before three jumps out")
	_check(Locked.maybe_lock(story, "gate.x", 3) and Locked.stage(story) == "needed", "three jumps out: one gate is locked")
	_check(not Locked.maybe_lock(story, "gate.y", 6), "only once per campaign")
	_check(Locked.blocks_other_offers(story), "while it waits, she has no other work")
	_check(Locked.is_withheld(story, "gate.x") and not Locked.is_withheld(story, "gate.y"), "only that gate is off the market")

	var job: Dictionary = Locked.offer(story)
	_check(bool(job[Locked.QUEST_FLAG]) and str(job["agent_name"]) == "Broker Kaelen", "the job is hers and marked")
	_check(str(job["handoff"]) == Locked.FIRST_HANDOFF and str(job["dialogue"]) == Locked.FIRST_BRIEFING, "first offer: the full pitch")
	# Offered again and again (Abe): fresh lines, never the same twice running.
	var last := ""
	var seen_handoffs := {}
	for i in 12:
		var again: Dictionary = Locked.offer(story)
		_check(str(again["handoff"]) != last and str(again["handoff"]) in Locked.REPEAT_HANDOFFS, "repeat %d: a different intro" % i)
		_check(str(again["dialogue"]) in Locked.REPEAT_BRIEFINGS, "repeat %d: a shorter briefing" % i)
		last = str(again["handoff"])
		seen_handoffs[last] = true
	_check(seen_handoffs.size() == Locked.REPEAT_HANDOFFS.size(), "every repeat intro gets used")
	var obj: Dictionary = job["objective"]
	_check(str(obj["type"]) == "RECOVER_COMBAT_DROP" and float(obj["drop_chance"]) == 1.0, "a recovery that always drops")
	# She never says what it's for (and nothing touches the canon).
	var texts: Array = [Locked.FIRST_BRIEFING, Locked.FIRST_HANDOFF]
	texts.append_array(Locked.REPEAT_HANDOFFS)
	texts.append_array(Locked.REPEAT_BRIEFINGS)
	for c in job["choices"]:
		texts.append(str(c["text"]))
		texts.append(str(c["consequence"]["dialogue_response"]))
	for text in texts:
		_check(not text.to_lower().contains("gate") and not text.to_lower().contains("lane"), "the job never mentions the gate: %s" % text)
		_check(ReservedTopics.is_clean(text), "clean: %s" % text)
	for hint in Locked.HINTS:
		_check(ReservedTopics.is_clean(str(hint)) and not str(hint).to_lower().contains("desperate"), "her hint stays a hint: %s" % hint)

	_check(not Locked.on_quest_completed(story, {"title": "Some other job"}), "another job changes nothing")
	_check(Locked.on_gate_sold(story, "gate.x", 0).is_empty(), "no hint before the ledger is in")
	_check(Locked.on_quest_completed(story, job) and Locked.stage(story) == "done", "the ledger handed in: done")
	_check(not Locked.blocks_other_offers(story) and not Locked.is_withheld(story, "gate.x"), "her other work and that gate's route are back")
	_check(Locked.on_gate_sold(story, "gate.y", 0).is_empty(), "another gate gets no hint")
	_check(Locked.on_gate_sold(story, "gate.x", 1) in Locked.HINTS, "buying that gate: her half-hint")
	_check(Locked.on_gate_sold(story, "gate.x", 1).is_empty() and Locked.stage(story) == "sold", "once")
	# Wiring.
	var ui := FileAccess.get_file_as_string("res://scripts/UIManager.gd")
	_check(ui.contains("_maybe_offer_kaelen_locked_gate_job()") and ui.contains("is_withheld("), "her board offers the job and withholds the gate")
	_check(FileAccess.get_file_as_string("res://scripts/GameRoot.gd").contains("KaelenLockedGate.gd\").on_quest_completed"), "handing it in unlocks the sale")
	if _failures.is_empty():
		print("[PASS] Kaelen's locked gate")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
