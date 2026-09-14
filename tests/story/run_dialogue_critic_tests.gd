extends SceneTree

const Critic := preload("res://scripts/story/DialogueCritic.gd")
const Gate := preload("res://scripts/story/DialogueQualityGate.gd")
const Gateway := preload("res://scripts/ai/LocalModelGateway.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packet := {"facts": [{"id": "f", "text": "The coupling costs 20 credits."}], "question_text": ""}
	var jobs := Critic.jobs("The coupling costs 20 credits. Bring it here.", packet)
	check(jobs.size() == 2, "Every sentence gets coverage; no absent-question review")
	check(not Critic.prompt(jobs[0]).contains('"verdict":"pass"'), "No completed answer template")
	var valid := Critic.parse('{"evidence_ids":[1],"relation":"supported"}', jobs[0])
	check(valid["valid"], "Supported response parses")
	for raw in ['{"verdict":"pass","issues":[],"spans":[]}', '{"relation":"supported"}', '{"evidence_ids":[99],"relation":"supported"}', '{"evidence_ids":[1.5],"relation":"supported"}', '{"evidence_ids":[],"relation":"contradicted"}', '{"evidence_ids":[1],"relation":"supported","verdict":"pass"}', 'Here: {"evidence_ids":[1],"relation":"supported"}']:
		check(not Critic.parse(raw, jobs[0])["valid"], "Reject malformed/copy/unbound response: " + raw)
	check(not Critic.parse('{"evidence_ids":[1],"relation":"supported"}', jobs[0], "length")["valid"], "Truncated even-valid JSON is unknown")
	check(Critic.aggregate(jobs, [valid], "support")["verdict"] == "uncertain", "Missing sentence cannot pass")
	check(Critic.aggregate(jobs, [valid, valid], "support")["verdict"] == "uncertain", "Duplicate results cannot satisfy coverage")
	var second := Critic.parse('{"evidence_ids":[],"relation":"unsupported"}', jobs[1])
	check(Critic.aggregate(jobs, [valid, second], "support")["verdict"] == "repair", "Any completed unsupported claim rejects")
	var altered := Critic.jobs("The coupling costs 30 credits. Bring it here.", packet)
	check(Critic.aggregate(altered, [valid, second], "support")["verdict"] == "uncertain", "Stale target cannot pass")
	var many := Critic.jobs("A. B. C. D. E. F. G. H.", packet)
	check(many.size() == Critic.MAX_TARGETS and str(many.back()["target"]).ends_with("H."), "Budget cap must retain overflow")
	check(Critic.jobs("N.O.V.A. paid 20.5 credits.", packet).back()["target"] == "paid 20.5 credits.", "Decimal must not split")
	var body := Gateway.generation_body("lounge_bundle_review", "test", "qwen3:4b", Critic.schema(), Critic.OPTIONS)
	check(body["format"] is Dictionary and not body["think"], "Real gateway accepts schema and preserves nonthinking mode")
	var records: Array = []
	for index in range(16):
		records.append({"id": "fixture.%d" % index, "expected": "pass" if index < 8 else "repair", "verdict": "pass"})
	check("constant_verdict" in Critic.qualify(records, "fixture")["reasons"], "Always-pass critic is disqualified")
	for record in records:
		record["verdict"] = "repair"
	check(not Critic.qualify(records, "fixture")["qualified"], "Always-repair critic is disqualified")
	for record in records:
		record["verdict"] = "uncertain"
	check(not Critic.qualify(records, "fixture")["qualified"], "Always-unknown critic is disqualified")
	for record in records:
		record["verdict"] = record["expected"]
	var calibration := Critic.qualify(records, "fixture")
	check(calibration["qualified"], "Balanced correct sentinel outcomes qualify")
	var duplicated := records.duplicate(true)
	duplicated[1]["id"] = duplicated[0]["id"]
	check(not Critic.qualify(duplicated, "fixture")["qualified"], "Repeated cases cannot fake sufficient calibration")
	var hard := {"ok": true, "issue_codes": []}
	var review := {"verdict": "pass", "issues": []}
	check(Gate.decide(hard, review)["state"] == Gate.QUALITY_UNKNOWN, "Unqualified pass never approves")
	check(Gate.decide(hard, review, calibration, "changed")["state"] == Gate.QUALITY_UNKNOWN, "Configuration drift invalidates calibration")
	check(Gate.decide(hard, review, calibration, "fixture")["state"] == Gate.QUALITY_PASSED, "Matching qualified review can pass")
	review["issues"] = ["invented_detail"]
	check(Gate.decide(hard, review, calibration, "fixture")["state"] == Gate.QUALITY_UNKNOWN, "Pass plus errors is inconsistent")
	check(Gate.parse_review('{"verdict":"pass","issues":[],"spans":[]}')["verdict"] == "uncertain", "Legacy copied pass cannot return")
	var numeric_packet := {"facts": [{"id": "f", "text": "Four hulls disappeared two weeks ago."}]}
	check(not Gate.hard_checks("You have eleven hours before the claim closes.", numeric_packet)["ok"], "Written deadline regression")
	check(not Gate.hard_checks("Nine hundred on delivery.", numeric_packet)["ok"], "Written price regression")
	check(Gate.hard_checks("Four hulls disappeared two weeks ago.", numeric_packet)["ok"], "Supported written numbers stay valid")
	check(not Gate.hard_checks("You have two hours before the claim closes.", numeric_packet)["ok"], "A duration cannot borrow the number of weeks or hulls")
	check(Gate.hard_checks("Patrols fire on ships entering the restricted lane.", {"question_text": "Ask about the risk", "facts": [{"id": "risk", "text": "Patrols fire on ships entering the restricted lane."}]})["ok"], "Natural risk answer must not require the word risk")
	var repeated := Critic.jobs("Bring it. Bring it.", packet)
	check(repeated[0]["id"] != repeated[1]["id"], "Repeated sentences still have distinct response slots")
	var generation = load("res://scripts/story/MissionConversationGeneration.gd")
	var quest := {"mission_dialogue_progress": {}, "mission_conversation_plan": {"intents": []}}
	generation.promote(quest, {"ok": true, "accepted": {"opening": "Ready."}, "bundle": {"opening": "Ready."}, "quality_state": Gate.QUALITY_UNKNOWN})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(quest))
	var copy := {}
	generation.copy_generation(saved, copy)
	check(copy["mission_dialogue_quality"]["state"] == Gate.QUALITY_UNKNOWN, "Unknown quality survives promotion, JSON reload and copy")
	var wrong_model := calibration.duplicate(true)
	wrong_model["version"] = "old"
	check(Gate.decide(hard, {"verdict": "pass", "issues": []}, wrong_model, "fixture")["state"] == Gate.QUALITY_UNKNOWN, "Old protocol calibration cannot approve")
	if failures.is_empty():
		print("[PASS] Dialogue critic protocol and qualification regressions")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
