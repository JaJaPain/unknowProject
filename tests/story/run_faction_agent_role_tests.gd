extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var llm = root.get_node("LLMInterface")
	var reported := "A client needs 25 m³ of ore delivered off the books, you. Clean hands and it's yours — I take my cut."
	_expect(llm._dialogue_has_broker_role_leak(reported, "Liaison Ryn"), "Reported broker leak was missed.")
	_expect(not llm._dialogue_has_broker_role_leak(reported, "Broker Kaelen"), "Kaelen must retain her broker role.")
	_expect(not llm._dialogue_has_broker_role_leak("Aurelia needs ore for our reserves. Bring it here, quietly.", "Liaison Ryn"), "Ryn's legitimate discreet tone was rejected.")
	var objective := {"type": "DELIVER_ORE", "amount_required": 25.0}
	var quest := {"agent_name": "Liaison Ryn", "dialogue": reported, "objective": objective}
	llm._finalize_validated_quest_display(quest, "DELIVER_ORE", objective)
	_expect(quest.get("objective_dialogue_rewritten", false), "Role leak did not enter verified fallback.")
	_expect(str(quest.dialogue).contains("25"), "Fallback lost ore quantity.")
	_expect(not llm._dialogue_has_broker_role_leak(quest.dialogue, "Liaison Ryn"), "Fallback still claims a broker role.")
	for kind in ["DELIVER_ORE", "KILL_SHIPS", "PICKUP_SPECIAL"]:
		for source in [llm._get_type_examples("aurelia", kind), llm._get_type_examples_fallback("aurelia", kind), llm._get_type_examples("faction_agent", kind)]:
			var lines: Array = source.dialogues.duplicate()
			for key in ["response_1", "response_2", "response_3"]:
				lines.append(source[key])
			for line in lines:
				_expect(not llm._dialogue_has_broker_role_leak(line, "Faction Contact"), "Faction example teaches brokerage: " + str(line))
	if failures.is_empty():
		print("[PASS] Faction agent role tests")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
