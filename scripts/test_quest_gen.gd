extends Node

const ITERATIONS := 20
const DELAY_BETWEEN := 0.5

var _run_count := 0
var _results: Array[Dictionary] = []
var _start_time := 0.0

func _ready() -> void:
	_start_time = Time.get_ticks_msec()
	print("=" .repeat(80))
	print("[TEST] Quest Generation Stress Test — %d iterations" % ITERATIONS)
	print("=" .repeat(80))
	await get_tree().create_timer(2.0).timeout
	_run_next()

func _run_next() -> void:
	if _run_count >= ITERATIONS:
		_print_summary()
		return
	_run_count += 1
	var factions := ["zenith", "aurelia", "vanguard", "neutral"]
	var faction: String = factions[randi() % factions.size()]
	LLMInterface.request_quest_generation(
		faction,
		"",
		500,
		{"zenith": 50.0, "aurelia": -20.0, "vanguard": -20.0},
		_on_quest_result
	)

func _on_quest_result(quest_data: Dictionary, is_fallback: bool) -> void:
	var obj: Dictionary = quest_data.get("objective", {})
	var obj_type: String = obj.get("type", "")
	var agent_name: String = quest_data.get("agent_name", "???")
	var agent_role: String = quest_data.get("agent_role", "MISSING")
	var dialogue: String = quest_data.get("dialogue", "")
	var title: String = quest_data.get("title", "???")
	var faction: String = quest_data.get("faction", "???")

	# --- Build contract details like the player sees ---
	var contract_lines := ""
	match obj_type:
		"KILL_SHIPS":
			contract_lines = "Destroy %d %s ships | Reward: %d SC" % [
				obj.get("count_required", 0),
				str(obj.get(
					"target_faction_display",
					GlobalState.faction_display_name(
						str(obj.get("target_faction", "???")),
						true
					)
				)),
				obj.get("reward_credits", 0)
			]
		"DELIVER_ORE":
			contract_lines = "Deliver %.0f m³ ore | Reward: %d SC" % [
				obj.get("amount_required", 0.0),
				obj.get("reward_credits", 0)
			]
		"PICKUP_SPECIAL":
			contract_lines = "Pick up %s from %s at %s | Reward: %d SC" % [
				obj.get("part_name", "???"),
				obj.get("target_npc", "???"),
				obj.get("target_outpost_display", "???"),
				obj.get("reward_credits", 0)
			]

	# --- Detect issues ---
	var issues: Array[String] = []
	var lower_d := dialogue.to_lower()

	if lower_d.find("george") != -1:
		issues.append("LEFTOVER_GEORGE")
	if lower_d.find("slither") != -1:
		issues.append("LEFTOVER_SLITHERN")
	if obj_type == "KILL_SHIPS":
		if str(obj.get("target_faction", "")).is_empty():
			issues.append("MISSING_TARGET_FACTION")
	elif obj_type == "DELIVER_ORE":
		var has_ore_kw := false
		for kw in ["ore", "deliver", "haul", "cargo", "material", "supply", "m³", "mine", "raw"]:
			if lower_d.find(kw) != -1:
				has_ore_kw = true
				break
		if not has_ore_kw:
			issues.append("NO_ORE_KEYWORDS_IN_DIALOGUE")
	elif obj_type == "PICKUP_SPECIAL":
		var target_npc := str(obj.get("target_npc", ""))
		var target_outpost := str(obj.get("target_outpost_display", ""))
		var part_name := str(obj.get("part_name", ""))
		if target_npc.is_empty():
			issues.append("MISSING_PICKUP_NPC")
		elif not _text_mentions_phrase(lower_d, target_npc):
			issues.append("PICKUP_DIALOGUE_WRONG_NPC")
		if not target_outpost.is_empty() and not _text_mentions_phrase(lower_d, target_outpost):
			issues.append("PICKUP_DIALOGUE_WRONG_OUTPOST")
		if not part_name.is_empty() and not _text_mentions_phrase(lower_d, part_name):
			issues.append("PICKUP_DIALOGUE_WRONG_ITEM")
	if agent_role == "MISSING":
		issues.append("NO_AGENT_ROLE")
	elif agent_name != "Broker Kaelen" and agent_role == "Neutral Fixer & Profit Broker":
		issues.append("WRONG_SUBTITLE")
	if is_fallback:
		issues.append("FALLBACK")

	# Check choice responses for dummy names
	var choices: Array = quest_data.get("choices", [])
	for i in range(choices.size()):
		var c: Dictionary = choices[i] if choices[i] is Dictionary else {}
		var resp: String = str(c.get("consequence", {}).get("dialogue_response", "")).to_lower()
		if resp.find("george") != -1:
			issues.append("CHOICE_%d_GEORGE" % (i + 1))
		if resp.find("slither") != -1:
			issues.append("CHOICE_%d_SLITHERN" % (i + 1))

	var status := "PASS" if issues.is_empty() else "FAIL"
	_results.append({
		"status": status,
		"type": obj_type,
		"agent": agent_name,
		"issues": issues,
		"is_fallback": is_fallback,
	})

	# --- Print like a player would see it ---
	var status_tag := "[PASS]" if status == "PASS" else "[FAIL] <<<  %s" % ", ".join(issues)
	print("\n" + "─" .repeat(80))
	print("  #%d  %s" % [_run_count, status_tag])
	print("─" .repeat(80))
	print("  %s" % agent_name.to_upper())
	print("  %s" % agent_role)
	print("")
	print("  \"%s\"" % dialogue)
	print("")
	print("  --- Contract ---")
	print("  Client: %s  |  Mission: %s" % [faction.to_upper(), title])
	print("  %s" % contract_lines)
	print("")
	for i in range(choices.size()):
		var c: Dictionary = choices[i] if choices[i] is Dictionary else {}
		var choice_text: String = c.get("text", "???")
		var resp: String = str(c.get("consequence", {}).get("dialogue_response", ""))
		print("  [%d] %s" % [i + 1, choice_text])
		if not resp.is_empty():
			print("      → \"%s\"" % resp)
	print("")

	await get_tree().create_timer(DELAY_BETWEEN).timeout
	_run_next()

func _print_summary() -> void:
	var elapsed := (Time.get_ticks_msec() - _start_time) / 1000.0
	var pass_count := 0
	var fail_count := 0
	var fallback_count := 0
	var type_counts := {"KILL_SHIPS": 0, "DELIVER_ORE": 0, "PICKUP_SPECIAL": 0}
	var type_fails := {"KILL_SHIPS": 0, "DELIVER_ORE": 0, "PICKUP_SPECIAL": 0}
	var issue_counts := {}

	for r in _results:
		if r["status"] == "PASS":
			pass_count += 1
		else:
			fail_count += 1
		if r["is_fallback"]:
			fallback_count += 1
		var t: String = r["type"]
		if type_counts.has(t):
			type_counts[t] += 1
		if r["status"] == "FAIL" and type_fails.has(t):
			type_fails[t] += 1
		for issue in r["issues"]:
			issue_counts[issue] = issue_counts.get(issue, 0) + 1

	print("\n" + "=" .repeat(80))
	print("  SUMMARY — %d runs in %.1fs" % [_results.size(), elapsed])
	print("=" .repeat(80))
	print("  PASS: %d  |  FAIL: %d  |  FALLBACK: %d" % [pass_count, fail_count, fallback_count])
	print("")
	print("  By type:")
	for t in type_counts:
		print("    %-16s %d generated, %d failed" % [t, type_counts[t], type_fails[t]])
	if not issue_counts.is_empty():
		print("")
		print("  Issues:")
		var sorted_issues := issue_counts.keys()
		sorted_issues.sort()
	for issue in sorted_issues:
		print("    %-30s %d" % [issue, issue_counts[issue]])
	print("=" .repeat(80))


func _text_mentions_phrase(text_lower: String, phrase: String) -> bool:
	var clean_phrase := phrase.strip_edges().to_lower()
	if clean_phrase.is_empty():
		return true
	if text_lower.find(clean_phrase) != -1:
		return true
	var words := clean_phrase.split(" ", false)
	if words.size() <= 1:
		return false
	var hits := 0
	for word in words:
		if str(word).length() >= 4 and text_lower.find(str(word)) != -1:
			hits += 1
	return hits >= mini(2, words.size())
