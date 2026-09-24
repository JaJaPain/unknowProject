extends SceneTree

const Writer := preload("res://scripts/story/premise/LineWriter.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var brief := {"speaker": "Dara Holt", "archetype": "union_organiser", "faction": "the Tessin Guild",
		"voice_direction": "Fast, blunt, funny when angry.",
		"situation": "Miners across Vessa say their ore keeps grading lower than it did a year ago.",
		"note": "She wants ore mined by someone with no guild ties graded, so nobody can claim the miners are padding their loads.",
		"task": "mine 20 cubic metres of silicate and deliver it to the assay office"}
	var req := Writer.build_briefing_request(brief)
	_check(str(req["prompt"]).contains("Dara Holt") and str(req["prompt"]).contains("assay office"), "the prompt carries the public facts")
	var private_fact := "She already suspects the reference standard was swapped by the consortium."
	_check(not str(req["prompt"]).contains("reference standard"), "the private fact never enters the prompt")
	var good := JSON.stringify({"line": "I need someone with no guild ties to mine a load and walk it into the assay office. If your ore grades low too, nobody can say we're padding."})
	_check(bool(Writer.check_line(good, brief, private_fact)["ok"]), "a good line passes")
	_check(Writer.check_line(JSON.stringify({"line": "Mine 45 cubic metres for me, pilot, and I will pay you well for it, honest."}), brief)["reason"] == "invented_number", "numbers not in the inputs are refused")
	_check(Writer.check_line(JSON.stringify({"line": "Somebody swapped the reference standard, I know it, so get me that ore graded fast."}), brief, private_fact)["reason"] == "leaked_private_fact", "a private fact leaking into the line is refused")
	_check(Writer.check_line(JSON.stringify({"line": "Hey Shiny, I need a load of ore graded at the assay office, quietly."}), brief)["reason"] == "forbidden_word", "only Kaelen says Shiny")
	_check(Writer.check_line(JSON.stringify({"line": "Too short."}), brief)["reason"] == "length", "too short is refused")
	_check(Writer.check_line(JSON.stringify({"line": "She came from another universe and wants her ore graded at the assay office."}), brief)["reason"] == "reserved_topic", "reserved topics are refused")
	_check(Writer.check_line("nope", brief)["reason"] == "not_json", "garbage is refused")
	_check(bool(Writer.check_line(JSON.stringify({"line": "Grab the ore, walk 'em into the assay office, and don't let the guild clerks hold it up."}), brief)["ok"]), "clipped words like 'em are fine")
	_check(Writer.check_line(JSON.stringify({"line": "Raspy voice cuts through static. 'Get that ore to the assay office before they notice.'"}), brief)["reason"] == "stage_direction", "stage directions are refused")
	_check(Writer.check_line(JSON.stringify({"line": "Get that ore to the assay office. The clock's ticking and I need it graded."}), brief)["reason"] == "stock_phrase", "stock filler is refused")
	if _failures.is_empty():
		print("[PASS] Line writer tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
