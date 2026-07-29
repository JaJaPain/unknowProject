extends SceneTree

const ValidatorType := preload("res://scripts/story/QuietMomentLineValidator.gd")
var _failures: Array[String] = []


func _initialize() -> void:
	_expect(
		bool(ValidatorType.validate_line(
			"kaelen", "safe_low_pay_completion",
			"Small payout, clean close. I will not call that exciting, but the credits are real."
		).get("ok", false)),
		"A grounded Kaelen quiet line should pass."
	)
	_expect(
		_has_error(
			ValidatorType.validate_line(
				"kaelen", "safe_low_pay_completion",
				"Safe job, modest payout. Captain and I both got paid. Just another Tuesday for the crew."
			),
			"earth_calendar_reference"
		),
		"Kaelen validator did not reject an Earth-calendar reference."
	)
	_expect(
		_has_error(
			ValidatorType.validate_line(
				"kaelen", "safe_low_pay_completion",
				"Another safe job. Payout's modest. Captain and I both got paid. Next one's on me."
			),
			"invented_future_offer"
		),
		"Kaelen validator did not reject an invented future offer."
	)
	_expect(
		_has_error(
			ValidatorType.validate_line(
				"kaelen", "safe_low_pay_completion",
				"Another safe job. Payout's modest. Captain and I both got paid. No drama."
			),
			"generic_empty_closer"
		),
		"Kaelen validator did not reject an empty generic closer."
	)
	_expect(
		_has_error(
			ValidatorType.validate_line(
				"kaelen", "safe_low_pay_completion",
				"Safe job, modest payout. Captain and I both got paid like we should have. No surprises."
			),
			"generic_empty_closer"
		),
		"Kaelen validator did not reject a generic no-surprises closer."
	)
	_expect(
		_has_error(
			ValidatorType.validate_line(
				"kaelen", "safe_low_pay_completion",
				"Modest payout, clean job. We both get to keep breathing. This is the win."
			),
			"copied_style_reference"
		),
		"Kaelen validator did not reject a copied style-reference run."
	)
	_expect(
		bool(ValidatorType.validate_line(
			"nova", "post_fight_stable_hull",
			"Hull is stable, Captain. Sensors show no pursuit; I would like to keep that trend intact."
		).get("ok", false)),
		"A grounded N.O.V.A. quiet line should pass."
	)
	_expect(
		_has_error(
			ValidatorType.validate_line(
				"nova", "post_fight_stable_hull",
				"Hull stable. No pursuit. You're breathing. No need to check the comms."
			),
			"invented_player_or_comms_condition"
		),
		"N.O.V.A. validator did not reject invented player/comms facts."
	)
	_expect(
		_has_error(
			ValidatorType.validate_line(
				"nova", "post_fight_stable_hull",
				"Hull stable. No pursuit. Let's move."
			),
			"unrequested_directive"
		),
		"N.O.V.A. validator did not reject an unrequested movement directive."
	)
	_expect(
		_has_error(
			ValidatorType.validate_line(
				"nova", "post_fight_stable_hull",
				"Hull stable. No pursuit. Report all systems, Captain."
			),
			"unrequested_directive"
		),
		"N.O.V.A. validator did not reject an unrequested report directive."
	)
	_expect(
		_has_error(
			ValidatorType.validate_line(
				"nova", "post_fight_stable_hull",
				"Hull stable, no pursuit. The ship breathes. You are safe."
			),
			"invented_player_or_comms_condition"
		),
		"N.O.V.A. validator did not reject unprovided safety and alarm-adjacent claims."
	)
	_expect(
		_has_error(
			ValidatorType.validate_line(
				"nova", "post_fight_stable_hull",
				"Hull stable. No pursuit. Just a dull minute earned after the fight."
			),
			"copied_style_reference"
		),
		"N.O.V.A. validator did not reject a copied style-reference run."
	)
	if _failures.is_empty():
		print("[PASS] Quiet moment line validator tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _has_error(result: Dictionary, expected: String) -> bool:
	return (result.get("errors", []) as Array).has(expected)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
