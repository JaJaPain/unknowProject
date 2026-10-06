extends SceneTree

# Playtest 2026-10-06 finding 5: pushing for more is a gamble; standing helps.

const Haggle := preload("res://scripts/domain/Haggle.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var push := {"text": "Double it.", "consequence": {"credits_immediate": 0, "reputation_change": {"zenith": -5},
		"combat_multiplier": 1.7, "reward_credits_multiplier": 1.6, "dialogue_response": "Fine, bumped."}}
	var advance := {"text": "Advance.", "consequence": {"credits_immediate": 40, "reward_credits_multiplier": 1.2}}
	var plain := {"text": "Deal.", "consequence": {"credits_immediate": 0, "reward_credits_multiplier": 1.0}}
	_check(Haggle.is_push(push) and not Haggle.is_push(advance) and not Haggle.is_push(plain), "only the big no-advance raise is a push")
	_check(is_equal_approx(Haggle.odds(0.0), 0.6), "base odds 60%")
	_check(Haggle.odds(100.0) > Haggle.odds(0.0) and Haggle.odds(-100.0) < Haggle.odds(0.0), "standing moves the odds")
	_check(Haggle.odds(100.0) <= Haggle.MAX_ODDS and Haggle.odds(-100.0) >= Haggle.MIN_ODDS, "never a sure thing either way")
	var won: Dictionary = Haggle.resolve(push, 0.0, 0.1, false)
	_check(float(won["consequence"]["reward_credits_multiplier"]) == 1.6 and not won.has("haggle_backfired"), "a good roll keeps the raise")
	var lost: Dictionary = Haggle.resolve(push, 0.0, 0.9, false)
	var c: Dictionary = lost["consequence"]
	_check(float(c["reward_credits_multiplier"]) < 1.0 and float(c["combat_multiplier"]) == 1.0, "a bad roll cuts the pay, no extra danger")
	_check(int((c["reputation_change"] as Dictionary)["zenith"]) == -5, "the reputation hit still lands")
	_check(str(c["dialogue_response"]) in Haggle.AGENT_LINES, "an agent's cocky line")
	_check(str(Haggle.resolve(push, 0.0, 0.9, true)["consequence"]["dialogue_response"]) in Haggle.KAELEN_LINES, "Kaelen's own lines")
	_check(float(push["consequence"]["reward_credits_multiplier"]) == 1.6, "the offer itself is untouched")
	_check(Haggle.resolve(plain, -100.0, 0.99, false) == plain, "not a push: nothing changes")
	_check(Haggle.resolve(push, 100.0, 0.8, false).get("haggle_backfired", false) == false, "high standing turns a 0.8 roll into a win")
	if _failures.is_empty():
		print("[PASS] Haggle")
		quit(0)
		return
	for f in _failures:
		push_error(f)
	print("[FAIL] Haggle: %d" % _failures.size())
	quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_failures.append(msg)
