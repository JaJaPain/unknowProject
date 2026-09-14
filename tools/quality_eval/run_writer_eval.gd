extends SceneTree

## Measures the WRITER, not the critic.
##
## The critic is unqualified and stays diagnostic; that is settled. But the
## question "does qwen3:4b produce usable mission dialogue through the real fact
## packet" is independent of it and has never been measured. This runs the REAL
## dispatch path -- real contracts, real packets, real prompt, real deterministic
## hard checks -- and reports what actually comes back.
##
## What this measures: generation success, deterministic hard-check outcomes,
## which checks fire, latency and token counts.
## What this does NOT measure: whether the prose reads well. That is human
## review and remains pending. A line passing the hard checks is grounded and
## well-formed; it is not thereby good.
##
## Flags: --baseline-offline --llm-live-fire (required, they stop unrelated
## startup generation) and optional --seed=NNN.

const Probe := preload("res://tools/quality_eval/OllamaProbe.gd")
const Generation := preload("res://scripts/story/MissionConversationGeneration.gd")
const Compiler := preload("res://scripts/story/MissionConversationCompiler.gd")
const PlanType := preload("res://scripts/story/MissionConversationPlan.gd")
const QualityGate := preload("res://scripts/story/DialogueQualityGate.gd")
const FactPacket := preload("res://scripts/story/DialogueFactPacket.gd")
const ContractType := preload("res://scripts/domain/QuestCausalContract.gd")
const CompilerType := preload("res://scripts/domain/QuestCausalContractCompiler.gd")
const DesireType := preload("res://scripts/persistence/GeneratedFactionDesire.gd")
const Fixtures := preload("res://tests/fixtures/QuestContractFixtures.gd")

const MODEL := "qwen3:4b"
## The game's own mission-conversation settings
## (LLMInterface.request_mission_conversation_slice).
const WRITER_OPTIONS := {"temperature": 0.95, "num_predict": 520}

var _seed := 12345


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		var text := str(argument)
		if text.begins_with("--seed="):
			_seed = int(text.substr("--seed=".length()))

	var probe := Probe.new()
	root.add_child(probe)
	await process_frame

	var cases := _cases()
	print("[writer] %d contracts, model=%s seed=%d" % [cases.size(), MODEL, _seed])

	var records: Array = []
	var latencies: Array[int] = []
	for index in range(cases.size()):
		var case: Dictionary = cases[index]
		var quest := _quest_for(case)
		var slices: Array = Compiler.plan_slices(quest["mission_conversation_plan"])
		for slice_index in range(slices.size()):
			var job := {
				"conversation_context": quest["mission_dialogue_context"].duplicate(true),
				"context_fingerprint": Generation.fingerprint(quest),
				"slice": slices[slice_index],
			}
			var prepared := Generation.prompt_for_job(job)
			if not bool(prepared.get("ok", false)):
				records.append({
					"contract": str(case["id"]),
					"slice": slice_index,
					"outcome": "prompt_failed",
					"status": str(prepared.get("status", "")),
				})
				continue
			var options := WRITER_OPTIONS.duplicate()
			options["seed"] = _seed + index * 10 + slice_index
			var response: Dictionary = await probe.generate(
				"mission_conversation", str(prepared["prompt"]), options
			)
			var elapsed := int(response.get("elapsed_ms", 0))
			latencies.append(elapsed)
			var record := _evaluate(quest, job, response, case)
			record["contract"] = str(case["id"])
			record["slice"] = slice_index
			record["elapsed_ms"] = elapsed
			record["eval_count"] = int(response.get("eval_count", 0))
			record["prompt_tokens"] = int(response.get("prompt_eval_count", 0))
			records.append(record)
			print("[writer] %-34s slice=%d %-22s %dms" % [
				str(case["id"]), slice_index, str(record["outcome"]), elapsed
			])

	var summary := _summarize(records, latencies)
	_write(records, summary)
	_print_summary(summary, records)
	quit(0)


## Contracts to write dialogue for. The three vertical examples plus generated
## ones, so this measures real compiler output and not only hand-written facts.
func _cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = [
		{"id": "fixture.courier_one_path", "contract": Fixtures.courier_one_path()},
		{"id": "fixture.investigation_one_choice", "contract": Fixtures.investigation_one_choice()},
	]
	for index in range(6):
		var desire := DesireType.build("writer_eval_%d" % index, "we%d" % index, 0)
		var need := str(desire["need"])
		var objective := {
			"type": "DELIVERY_COURIER",
			"item_name": DesireType.item_for_need(need, str(desire["id"])),
			"destination_display": "Blacklist Yard",
			"destination_station_id": "outpost.blacklist_yard",
			"reward_credits": 180 + index * 20,
		}
		var contract := CompilerType.compile({
			"campaign_id": "campaign.writer_eval",
			"system_id": "system.writer_eval",
			"objective": objective,
			"cause": {
				"cause_faction_id": "faction.generated.we.f%d" % index,
				"desire_id": str(desire["id"]),
				"cause_id": "cause.writer_eval.%d" % index,
			},
			"agenda": {
				"faction_id": "faction.generated.we.f%d" % index,
				"faction_name": ["Kessel Freight Compact", "Ossuary Salvage Lease",
					"Halberd Claims Office", "Tarn Courier Union",
					"Verge Security Lease", "Bight Pilgrim Fleet"][index],
				"desire": desire,
				"relationships": [],
			},
			"requester_display": ["Kessel Freight Compact", "Ossuary Salvage Lease",
				"Halberd Claims Office", "Tarn Courier Union",
				"Verge Security Lease", "Bight Pilgrim Fleet"][index],
			"recipient": {
				"id": "npc.marn_dable", "name": "Marn Dable",
				"role": "quartermaster", "station_id": "outpost.blacklist_yard",
			},
			"reward_source": "They pay out of %s." % str(desire["payment_source"]),
		})
		if ContractType.is_present(contract):
			cases.append({"id": "generated.%d" % index, "contract": contract})
	return cases


## Build the quest exactly as the offer builder would, so the writer sees the
## production prompt rather than a harness approximation.
func _quest_for(case: Dictionary) -> Dictionary:
	var contract: Dictionary = case["contract"]
	var objective: Dictionary = contract.get("objective_binding", {})
	var mission := {
		"title": "Evaluation Job",
		"objective_type": str(objective.get("type", "")),
		"objective_summary": "Deliver the listed cargo.",
		"reward_credits": int(objective.get("reward_credits", 0)),
		"public_because": ContractType.fact_text(contract, "fact.need"),
		"stake": ContractType.fact_text(contract, "fact.stake"),
		"cause_id": str(contract.get("triggering_event_id", "")),
		"causal_contract": contract,
	}
	var plan := PlanType.build_plan(mission, [], {"respect": 0}, {
		"can_accept": true, "can_decline": true,
	})
	var speaker := {
		"name": "Local Contact",
		"role": "faction representative",
		"voice_guidance": "direct, businesslike, does not oversell",
	}
	var quest := {
		"story_beat_id": "beat.writer_eval",
		"mission_conversation_plan": plan,
		"mission_dialogue_bundle": Compiler.fallback_bundle(mission, plan, speaker),
		"mission_dialogue_bundle_source": "deterministic_fallback",
		"mission_dialogue_bundle_degraded": true,
	}
	Generation.attach(quest, mission, speaker)
	return quest


## Run the response through the REAL acceptance path, so what is measured is what
## the game would actually publish.
func _evaluate(
	quest: Dictionary,
	job: Dictionary,
	response: Dictionary,
	case: Dictionary
) -> Dictionary:
	if not bool(response.get("ok", false)):
		return {"outcome": "transport_failed", "status": str(response.get("error", ""))}
	var raw := str(response.get("text", ""))
	var result := Generation.accept_response(
		quest, job, {"ok": true, "inner_text": raw}
	)
	if bool(result.get("ok", false)):
		var lines: Array = []
		for value in (result.get("lines", []) as Array):
			lines.append(str(value))
		return {
			"outcome": "accepted",
			"quality_state": str(result.get("quality_state", "")),
			"lines": lines,
			"raw": raw.substr(0, 600),
		}
	# Separate WHY it failed: a parse failure, an existing validator, or the
	# quality gate. Collapsing them would hide which layer is actually biting.
	var status := str(result.get("status", "unknown"))
	var outcome := "rejected_other"
	if status == "response_json_parse_failed":
		outcome = "rejected_parse"
	elif status == "quality_rejected":
		outcome = "rejected_quality_gate"
	elif status.ends_with("validation_failed"):
		outcome = "rejected_existing_validator"
	elif status == "stale_fact_packet":
		outcome = "rejected_stale_packet"
	return {
		"outcome": outcome,
		"status": status,
		"errors": result.get("errors", []),
		"raw": raw.substr(0, 600),
	}


func _summarize(records: Array, latencies: Array[int]) -> Dictionary:
	var outcomes := {}
	var issue_codes := {}
	var quality_states := {}
	var eval_total := 0
	var prompt_total := 0
	for raw_record in records:
		var record: Dictionary = raw_record
		var outcome := str(record.get("outcome", "unknown"))
		outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
		for code in (record.get("errors", []) as Array):
			var text := str(code)
			issue_codes[text] = int(issue_codes.get(text, 0)) + 1
		var state := str(record.get("quality_state", ""))
		if not state.is_empty():
			quality_states[state] = int(quality_states.get(state, 0)) + 1
		eval_total += int(record.get("eval_count", 0))
		prompt_total += int(record.get("prompt_tokens", 0))
	var sorted_latencies := latencies.duplicate()
	sorted_latencies.sort()
	return {
		"model": MODEL,
		"writer_options": WRITER_OPTIONS,
		"seed": _seed,
		"slice_count": records.size(),
		"outcomes": outcomes,
		"issue_codes": issue_codes,
		"quality_states": quality_states,
		"tokens": {"generated": eval_total, "prompt": prompt_total},
		"latency_ms": {
			"p50": _percentile(sorted_latencies, 0.50),
			"p95": _percentile(sorted_latencies, 0.95),
			"max": sorted_latencies[sorted_latencies.size() - 1] if not sorted_latencies.is_empty() else 0,
		},
	}


func _percentile(sorted_values: Array[int], fraction: float) -> int:
	if sorted_values.is_empty():
		return 0
	var index := int(floor(fraction * float(sorted_values.size() - 1)))
	return sorted_values[clampi(index, 0, sorted_values.size() - 1)]


func _write(records: Array, summary: Dictionary) -> void:
	var path := "res://logs/quality_eval/writer_eval_%d_%d.json" % [
		_seed, int(Time.get_unix_time_from_system())
	]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[writer] could not write %s" % path)
		return
	file.store_string(JSON.stringify({
		"generated_at": Time.get_datetime_string_from_system(),
		"summary": summary,
		"records": records,
	}, "  "))
	file.close()
	print("[writer] wrote ", path)


func _print_summary(summary: Dictionary, records: Array) -> void:
	print("")
	print("=== WRITER EVALUATION (model=%s seed=%d n=%d slices) ===" % [
		str(summary["model"]), int(summary["seed"]), int(summary["slice_count"])
	])
	var outcomes: Dictionary = summary["outcomes"]
	var keys: Array = outcomes.keys()
	keys.sort()
	for key in keys:
		print("  %-28s %d" % [str(key), int(outcomes[key])])
	if not (summary["issue_codes"] as Dictionary).is_empty():
		print("")
		print("--- rejection reasons ---")
		var codes: Dictionary = summary["issue_codes"]
		for code in codes.keys():
			print("  %-34s %d" % [str(code), int(codes[code])])
	if not (summary["quality_states"] as Dictionary).is_empty():
		print("")
		print("--- recorded quality provenance ---")
		var states: Dictionary = summary["quality_states"]
		for state in states.keys():
			print("  %-28s %d" % [str(state), int(states[state])])
	var latency: Dictionary = summary["latency_ms"]
	print("")
	print("latency p50=%dms p95=%dms max=%dms" % [
		int(latency["p50"]), int(latency["p95"]), int(latency["max"])
	])
	var tokens: Dictionary = summary["tokens"]
	print("tokens generated=%d prompt=%d" % [
		int(tokens["generated"]), int(tokens["prompt"])
	])
	print("")
	print("--- sample accepted lines (NOT a quality judgement) ---")
	var shown := 0
	for raw_record in records:
		var record: Dictionary = raw_record
		if str(record.get("outcome", "")) != "accepted" or shown >= 6:
			continue
		for line in (record.get("lines", []) as Array):
			print("  [%s] %s" % [str(record.get("contract", "")), str(line)])
		shown += 1
