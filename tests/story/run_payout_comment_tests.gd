extends SceneTree

## Playtest 2026-10-02: Kaelen commented on every job's payout, including
## outpost and board work she had nothing to do with, and spoke as if aboard
## after we'd undocked. Now: her own jobs only, over comms in flight; board work
## gets N.O.V.A.'s comment instead; anyone else's job passes quietly.
##   Godot --headless --path . --script res://tests/story/run_payout_comment_tests.gd --log-file <path> -- --baseline-offline

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var Root = load("res://scripts/GameRoot.gd")
	_check(Root.quiet_moment_beat_for_payout({"agent_name": "Broker Kaelen", "reward_credits": 120}) == "kaelen_low_pay_safe", "her own small job: her low-pay line")
	_check(Root.quiet_moment_beat_for_payout({"agent_name": "Broker Kaelen", "reward_credits": 450}) == "kaelen_high_pay_dangerous", "her own big job: her high-pay line")
	_check(Root.quiet_moment_beat_for_payout({"agent_name": "Liaison Ryn", "reward_credits": 450}) == "", "an outpost agent's job: no comment from her")
	_check(Root.quiet_moment_beat_for_payout({"agent_name": "Jenna Kross", "reward_credits": 80}) == "", "Jenna's job: no comment from her")
	_check(Root.quiet_moment_beat_for_payout({"agent_name": "Public Board", "public_board": true, "reward_credits": 90}) == "nova_public_board", "board work: N.O.V.A.'s comment")
	var Beats = load("res://scripts/story/QuietMomentBeats.gd")
	_check(str(Beats.beat("nova_public_board").get("speaker", "")) == "nova", "the board beat is N.O.V.A.'s")

	# The speech queue carries the comms flag through to playback.
	var speech: Node = root.get_node("SpeechService")
	speech._ambient_queue.clear()
	speech._sequential_active = true  # busy: the line queues
	speech.play_ambient("Test line over comms.", "voice.kaelen.v1", true, "Broker Kaelen")
	var queued: Dictionary = speech._ambient_queue[-1] if not speech._ambient_queue.is_empty() else {}
	_check(bool(queued.get("comms", false)) and str(queued.get("speaker", "")) == "Broker Kaelen", "a queued comms line keeps its comms flag: %s" % str(queued))
	speech._ambient_queue.clear()
	speech._sequential_active = false
	if _failures.is_empty():
		print("[PASS] Payout comments")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
