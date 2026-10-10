extends SceneTree

## Mechanics' written lines (playtest 2026-10-10 findings 3 and 4): a damaged
## hull gets a line from its band, a generated greeting can't invent a crash,
## parts runs are favours and their hand-ins exist.

const Lines := preload("res://scripts/story/MechanicLines.gd")

var _failures: Array = []


func _initialize() -> void:
	var count := 0
	for band in Lines.HULL_BANDS:
		count += (band[1] as Array).size()
	_check(count == 32, "all 32 approved hull lines are in (%d)" % count)
	_check(Lines.HULL_BANDS[0][1].has(Lines.hull_line(0.10)), "10% hull draws from the 1-25 band")
	_check(Lines.HULL_BANDS[1][1].has(Lines.hull_line(0.40)), "40% hull draws from the 26-50 band")
	_check(Lines.HULL_BANDS[2][1].has(Lines.hull_line(0.75)), "75% hull draws from the 51-75 band")
	_check(Lines.HULL_BANDS[3][1].has(Lines.hull_line(0.80)), "80% hull draws from the 76-85 band")
	_check(Lines.HULL_BANDS[4][1].has(Lines.hull_line(0.97)), "97% hull draws from the 86-99 band")
	_check(Lines.hull_line(1.0) == "", "a full hull has no band line")

	var playtest := "Miner's engine's been sputtering since last week, saw you crash-land near the ore fields. Money's tight, but I'll get you back on track before the next hail."
	_check(Lines.invented_detail(playtest, true) != "", "the playtest's made-up crash is rejected")
	_check(Lines.invented_detail("Not a scratch on that INDY Miner, but I can see the dents from here.", true) != "", "damage on a spotless hull is rejected")
	_check(Lines.invented_detail("That INDY Miner is spotless and you're 400 credits from a shield upgrade. Spend it here.", true) == "", "a line built from the facts passes")

	var offer := Lines.offer_line("Coolant Pump", "Mara Vey", "Dustline Outpost")
	_check(offer.contains("Coolant Pump") and offer.contains("Mara Vey") and offer.contains("Dustline Outpost"), "an offer names the part, holder and outpost")
	_check(not offer.contains("{"), "no placeholders left")
	_check(Lines.OFFERS.size() == 7 and Lines.HANDINS.size() == 7, "seven offers and seven hand-ins")
	_check(Lines.handin_line() != "", "a hand-in line")
	_check(is_equal_approx(Lines.FAVOUR_DISCOUNT, 0.25), "the favour is a quarter off")
	for id in Lines.PERSONALITIES.keys():
		var p: Dictionary = Lines.PERSONALITIES[id]
		_check((p["bands"] as Array).size() == Lines.HULL_BANDS.size(), "%s has a set for every band" % id)
		_check(Lines.PERSONALITIES[id]["bands"][2].has(Lines.hull_line(0.6, null, id)), "%s speaks its own 51-75 line" % id)
	var male := Lines.personality_for("station.a", 0, true)
	var female := Lines.personality_for("station.a", 1, true)
	_check(str(Lines.PERSONALITIES[male]["gender"]) == "m", "a male mechanic gets a male personality")
	_check(str(Lines.PERSONALITIES[female]["gender"]) == "f", "a female mechanic gets a female personality")
	_check(Lines.personality_for("station.a", 0, true) == male, "the same station keeps its personality")
	var seen := {}
	for i in 20:
		seen[Lines.personality_for("station.%d" % i, -1, true)] = true
	_check(seen.size() == Lines.PERSONALITIES.size(), "stations spread over every personality (%d)" % seen.size())
	if _failures.is_empty():
		print("[PASS] Mechanic lines")
		quit(0)
	else:
		for f in _failures:
			push_error("[FAIL] " + str(f))
		quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
