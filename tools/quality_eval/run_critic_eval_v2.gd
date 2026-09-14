extends SceneTree

const Probe := preload("res://tools/quality_eval/OllamaProbe.gd")
const Corpus := preload("res://tools/quality_eval/CriticCorpus.gd")
const Critic := preload("res://scripts/story/DialogueCritic.gd")
const Gate := preload("res://scripts/story/DialogueQualityGate.gd")
const Sentinels := preload("res://tools/quality_eval/CriticSentinels.gd")


func _initialize() -> void:
	if "--baseline-offline" not in OS.get_cmdline_user_args() or "--llm-live-fire" not in OS.get_cmdline_user_args():
		push_error("Pass --baseline-offline --llm-live-fire to disable game background generation/refill during critic measurement. The probe still calls Ollama directly.")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	var probe := Probe.new()
	root.add_child(probe)
	await process_frame
	var args := OS.get_cmdline_user_args()
	var tuning := "--tuning-only" in args
	var sentinels := "--sentinels" in args
	var model := "qwen3:4b"
	var seed_value := 12345
	for arg in args:
		if arg.begins_with("--model="):
			model = arg.trim_prefix("--model=")
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
	var records: Array = []
	var support_records: Array = []
	var support_with_numbers: Array = []
	var relevance_records: Array = []
	var raw_unique := {}
	var output := "res://logs/quality_eval/critic_v2_%s_%d_%d.json" % ["sentinels" if sentinels else ("tuning" if tuning else "all"), seed_value, Time.get_unix_time_from_system()]
	DirAccess.make_dir_recursive_absolute("res://logs/quality_eval")
	# Identity is captured from Ollama, not hard-coded in the summary.
	var identity: Dictionary = await probe.model_identity(model)
	var configuration := {"protocol": Critic.VERSION, "model": model, "identity": identity,
		"seed": seed_value, "options": Critic.OPTIONS, "prompt_hash": FileAccess.get_file_as_string("res://scripts/story/DialogueCritic.gd").sha256_text(),
		"gateway_hash": FileAccess.get_file_as_string("res://scripts/ai/LocalModelGateway.gd").sha256_text()}
	var fingerprint := JSON.stringify(configuration).sha256_text() if not identity.is_empty() else ""
	for case in (Sentinels.cases() if sentinels else Corpus.cases()):
		if tuning and not sentinels and bool(case.get("holdout", false)):
			continue
		var facts: Array = []
		for fact in case.get("facts", []):
			facts.append({"id": "fact.%d" % facts.size(), "text": fact})
		var packet := {"facts": facts, "question_text": case.get("question", ""), "preceding_line": case.get("preceding", "")}
		var jobs := Critic.jobs(str(case["line"]), packet)
		var replies: Array[Dictionary] = []
		var calls: Array = []
		for job in jobs:
			var response: Dictionary = await probe.generate_review(job, model, seed_value)
			var raw := str(response.get("text", ""))
			raw_unique[raw] = true
			var parsed := Critic.parse(raw, job, str(response.get("done_reason", "")))
			if not bool(response.get("ok", false)):
				parsed["valid"] = false
				parsed["relation"] = "uncertain"
			replies.append(parsed)
			calls.append({"job": job, "response": response, "parsed": parsed})
		var support := Critic.aggregate(jobs, replies, "support")
		var relevance := Critic.aggregate(jobs, replies, "relevance")
		var category := str(case["category"])
		var hard := Gate.hard_checks(str(case["line"]), packet)
		# Separate dimensions: a robotic truthful sentence is not a factual lie.
		if category in ["clean_pass", "awkward_but_true", "invented_detail", "contradiction"]:
			support_records.append({"id": case["id"], "expected": case["expected"], "verdict": support["verdict"], "holdout": case["holdout"]})
			support_with_numbers.append({"id": case["id"], "expected": case["expected"], "verdict": "repair" if Gate.ISSUE_UNSUPPORTED_NUMBER in hard["issue_codes"] else support["verdict"], "holdout": case["holdout"]})
		if category == "irrelevant" or (category in ["clean_pass", "awkward_but_true"] and not str(case.get("question", "")).is_empty()):
			relevance_records.append({"id": case["id"], "expected": case["expected"], "verdict": relevance["verdict"], "holdout": case["holdout"]})
		records.append({"case": case, "calls": calls, "support": support, "relevance": relevance,
			"hard_checks": hard, "advisory_checks": Gate.advisory_checks(str(case["line"]), packet), "style": "not_evaluated"})
		print("[critic v2] %s support=%s relevance=%s" % [case["id"], support["verdict"], relevance["verdict"]])
		_write(output, {"configuration": configuration, "fingerprint": fingerprint, "records": records, "complete": false})
	var support_health := Critic.qualify(support_records, fingerprint)
	var relevance_health := Critic.qualify(relevance_records, fingerprint)
	var report := {"configuration": configuration, "fingerprint": fingerprint, "records": records, "complete": true,
		"support_health": support_health, "relevance_health": relevance_health, "unique_raw_responses": raw_unique.size(),
		"support_records": support_records, "relevance_records": relevance_records,
		"support_with_numbers": support_with_numbers,
		"runtime_qualified": false, "note": "Diagnostic evaluation only. A tuning run cannot authorize runtime enforcement. Style is not evaluated."}
	_write(output, report)
	print("[critic v2] support health: ", support_health)
	print("[critic v2] relevance health: ", relevance_health)
	print("[critic v2] report: ", output)
	# Automated callers cannot mistake a failed qualification run for a pass.
	quit(0 if support_health["qualified"] and (sentinels or relevance_health["qualified"]) and not tuning else 2)


func _write(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write critic measurement: %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify(payload, "  "))
