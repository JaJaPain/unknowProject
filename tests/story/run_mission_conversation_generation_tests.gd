extends SceneTree

const Generation := preload("res://scripts/story/MissionConversationGeneration.gd")
const Compiler := preload("res://scripts/story/MissionConversationCompiler.gd")
const Validator := preload("res://scripts/story/DialogueBundleValidator.gd")
const Worker := preload("res://scripts/story/MissionConversationWorker.gd")
const Scheduler := preload("res://scripts/story/NarrativeCacheScheduler.gd")
const Gateway := preload("res://scripts/ai/LocalModelGateway.gd")
const CacheStore := preload("res://scripts/persistence/NarrativeCacheStore.gd")
const Fixtures := preload("res://tests/fixtures/QuestContractFixtures.gd")
const QualityGate := preload("res://scripts/story/DialogueQualityGate.gd")

class QueueProbe extends Node:
	var last_offer: Dictionary = {}
	func queue_offer(quest: Dictionary) -> void:
		last_offer = quest.duplicate(true)

class FakeHost extends Node:
	var narrative_cache_scheduler: RefCounted = Scheduler.new()
	var active_campaign_slot_id := "test_campaign"
	var campaign_narrative_cache_store: RefCounted = null
	var system_id := "test_system"
	var requests: Array = []
	var persisted: Dictionary = {}
	var reports: Array = []
	var quality_calls := 0
	var reject_quality := false
	func _ensure_narrative_cache_scheduler() -> RefCounted:
		return narrative_cache_scheduler
	func mission_conversation_system_id() -> String:
		return system_id
	func _mission_conversation_payload_for_cache_job(job: Dictionary) -> Dictionary:
		return Generation.prompt_for_job(job)
	func transport(prompt: String, callback: Callable) -> void:
		requests.append({"prompt": prompt, "callback": callback})
	func persist_mission_conversation_offer(quest: Dictionary) -> void:
		persisted = JSON.parse_string(JSON.stringify(quest))
	func record_mission_conversation_result(quest: Dictionary) -> void:
		reports.append(str(quest["mission_dialogue_bundle_source"]))
	func validate_and_register_narrative_lines(_lines: Array, _kind: String) -> Dictionary:
		quality_calls += 1
		return {"ok": not reject_quality, "reason": "test_quality_rejected"}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(Gateway.profile_for_capability("mission_conversation") == "small_dialogue", "Mission conversations must use the small profile")
	_expect(Gateway.request_timeout("mission_conversation") == 25.0, "Mission conversation timeout must be 25 seconds")
	_test_parse_and_validation()
	_test_full_generation_and_resume()
	_test_failed_opening_and_partial()
	_test_late_callback_and_quality()
	_test_retirement()
	_test_runtime_persistence()
	_test_quality_gate_runs_in_the_real_generation_path()
	_test_writer_prompt_carries_the_fact_packet()
	_test_answer_packet_keeps_the_fact_that_answers_the_question()
	_test_stale_fact_packet_is_refused()
	if failures.is_empty():
		print("[PASS] Mission conversation generation: routing, scoped parsing, promotion, retries, persistence, stale callbacks, quality and retirement")
	else:
		for failure in failures:
			push_error("[FAIL] " + failure)
	quit(0 if failures.is_empty() else 1)


func _quest() -> Dictionary:
	var mission := {"title": "Coolant Debt", "public_because": "The refinery is losing coolant.", "stake": "The reserve is nearly empty.", "objective_summary": "Deliver the sealed pump.", "reward_credits": 120}
	var plan := {"intents": [
		{"id": "ask_why", "kind": "question", "label": "Why this job?", "answer_anchors": ["reserve"]},
		{"id": "accept_standard", "kind": "terminal", "label": "Accept the contract"},
	], "forbidden_terms": ["hidden reactor conspiracy"]}
	var speaker := {"name": "Mira", "role": "refinery dispatcher"}
	var quest := {"story_beat_id": "beat.coolant", "mission_conversation_plan": plan, "mission_dialogue_bundle": Compiler.fallback_bundle(mission, plan, speaker), "mission_dialogue_bundle_source": "deterministic_fallback", "mission_dialogue_bundle_degraded": true, "mission_dialogue_bundle_degraded_reason": "generation_pending_safe_template"}
	Generation.attach(quest, mission, speaker)
	return quest


func _opening() -> Dictionary:
	return {"ok": true, "inner_text": JSON.stringify({"opening": "The refinery is losing coolant. I need that sealed pump delivered before the next shift."})}


func _answers() -> Dictionary:
	return {"ok": true, "inner_text": JSON.stringify({"ask_why_response": "The reserve is nearly empty. That is why this delivery cannot wait.", "accept_standard_response": "Agreed. Bring the sealed pump and we will settle the posted terms."})}


func _job(quest: Dictionary, index: int = 0) -> Dictionary:
	return {"conversation_context": quest["mission_dialogue_context"].duplicate(true), "context_fingerprint": Generation.fingerprint(quest), "slice": Compiler.plan_slices(quest["mission_conversation_plan"])[index]}


func _test_parse_and_validation() -> void:
	var quest := _quest()
	var job := _job(quest)
	var prepared := Generation.prompt_for_job(job)
	_expect(bool(prepared.get("ok", false)) and str(prepared.get("prompt", "")).contains('["opening"]'), "Payload must request the opening only")
	for invalid in ["broken json", "[]", '{"opening":42}', '{"opening":"Good line","accept_standard_player":"Steal money"}']:
		var rejected := Generation.accept_response(quest, job, {"ok": true, "inner_text": invalid})
		_expect(rejected.get("status") == "response_json_parse_failed", "Malformed/non-string/unrequested fields must fail scoped parsing")
	var leak := Generation.accept_response(quest, job, {"ok": true, "inner_text": '{"opening":"The hidden reactor conspiracy explains it."}'})
	_expect(not leak.get("ok", true), "Forbidden knowledge must fail validation")
	var result := Generation.accept_response(quest, job, _opening())
	_expect(result.get("ok", false), "Opening must not fail for missing intent keys")
	Generation.promote(quest, result)
	_expect(quest["mission_dialogue_bundle_source"] == "partial_generated", "One accepted opening must be partial generation")
	_expect(Validator.validate_bundle(quest["mission_dialogue_bundle"], quest["mission_conversation_plan"]).get("ok", false), "Partial bundle must have no holes")
	var repeated := Generation.accept_response(quest, job, {"ok": true, "inner_text": '{"opening":"The refinery is losing coolant. A replacement opening."}'})
	Generation.promote(quest, repeated)
	_expect(quest["mission_dialogue_bundle"]["opening"] == result["bundle"]["opening"], "Accepted keys must never be overwritten")
	quest["mission_dialogue_context"]["mission_plan"]["stake"] = "A changed stake."
	_expect(Generation.accept_response(quest, job, _opening()).get("status") == "stale_conversation", "Changed facts must invalidate old jobs")
	var cast := _quest()
	cast["mission_dialogue_context"]["speaker_card"] = {"name": "Broker Kaelen", "soul_state": "broker_neutral"}
	var cast_job := _job(cast)
	_expect(str(Generation.prompt_for_job(cast_job).get("prompt", "")).contains("non-negotiable public guidance"), "Kaelen must use the unchanged canonical soul projection")
	var wrong_voice := Generation.accept_response(cast, cast_job, {"ok": true, "inner_text": '{"opening":"The refinery is losing coolant. N.O.V.A. here."}'})
	_expect(wrong_voice.get("status") == "fixed_cast_validation_failed", "Fixed-cast voice violations must be rejected")
	cast["mission_dialogue_context"]["speaker_card"] = {"name": "N.O.V.A."}
	_expect(not Generation.prompt_for_job(_job(cast)).get("ok", true), "Nova must not be assigned a new mission-giver personality")


func _setup() -> Array:
	var host := FakeHost.new()
	root.add_child(host)
	var worker := Worker.new()
	host.add_child(worker)
	worker.configure(host, host.transport)
	return [host, worker]


func _reply(host: FakeHost, response: Dictionary) -> void:
	var request: Dictionary = host.requests.pop_front()
	request["callback"].call(response)


func _test_full_generation_and_resume() -> void:
	var setup := _setup()
	var host: FakeHost = setup[0]
	var worker: Node = setup[1]
	var quest := _quest()
	worker.queue_offer(quest)
	_expect(host.requests.is_empty(), "Queueing must return without inference or blocking the panel")
	host.narrative_cache_scheduler.pause("bible")
	worker.pump()
	_expect(host.requests.is_empty(), "Large-model pause must apply")
	host.narrative_cache_scheduler.resume()
	worker.pump()
	worker.pump()
	_expect(host.requests.size() == 1, "Only one request may be in flight")
	_reply(host, _opening())
	var restored: Dictionary = host.persisted.duplicate(true)
	_expect(Generation.fingerprint(restored) == Generation.fingerprint(quest), "Context identity must survive JSON save/load")
	host.free()
	setup = _setup()
	host = setup[0]
	worker = setup[1]
	worker.queue_offer(restored)
	var ui_copy := restored.duplicate(true)
	worker.queue_offer(ui_copy)
	worker.pump()
	_expect(host.requests.size() == 1 and not str(host.requests[0]["prompt"]).contains("Write only the opening."), "Reload must skip the accepted opening")
	_reply(host, _answers())
	_expect(restored["mission_dialogue_bundle_source"] == "generated", "All accepted slices must promote to generated")
	_expect(not restored["mission_dialogue_bundle_degraded"] and not restored.has("mission_dialogue_bundle_degraded_reason"), "Full generation must clear degraded flags")
	_expect(ui_copy["mission_dialogue_bundle_source"] == "generated", "UI copies must receive accepted slices")
	_expect(restored["mission_dialogue_bundle"]["accept_standard_player"] == "Accept the contract", "Button labels must remain code-owned")
	_expect(host.reports == ["generated"], "Full generation must be reported once without fallback")
	host.free()


func _test_failed_opening_and_partial() -> void:
	var setup := _setup()
	var host: FakeHost = setup[0]
	var worker: Node = setup[1]
	var quest := _quest()
	worker.queue_offer(quest)
	worker.pump()
	_reply(host, {"ok": true, "inner_text": "bad"})
	var restored: Dictionary = host.persisted.duplicate(true)
	host.free()
	setup = _setup()
	host = setup[0]
	worker = setup[1]
	worker.queue_offer(restored)
	worker.pump()
	_reply(host, {"ok": false, "reason": "transport_failed"})
	worker.pump()
	_expect(host.requests.size() == 1 and not str(host.requests[0]["prompt"]).contains("Write only the opening."), "Two failed openings across reload must release intent slices")
	_reply(host, _answers())
	_expect(restored["mission_dialogue_bundle_source"] == "partial_generated", "Failed opening plus accepted answers must remain partial")
	_expect(host.reports == ["partial_generated"], "Partial generation must not be reported as fallback")
	worker.pump()
	_expect(host.requests.is_empty(), "Finished slices must not retry forever")
	host.free()


func _test_late_callback_and_quality() -> void:
	for reason in ["campaign", "system", "context", "quality", "scheduler", "store"]:
		var setup := _setup()
		var host: FakeHost = setup[0]
		var worker: Node = setup[1]
		var quest := _quest()
		worker.queue_offer(quest)
		worker.pump()
		match reason:
			"campaign": host.active_campaign_slot_id = "other_campaign"
			"system": host.system_id = "other_system"
			"context": quest["mission_dialogue_context"]["mission_plan"]["stake"] = "Changed"
			"quality": host.reject_quality = true
			"scheduler": host.narrative_cache_scheduler = Scheduler.new()
			"store": host.campaign_narrative_cache_store = RefCounted.new()
		_reply(host, _opening())
		_expect(quest["mission_dialogue_bundle_source"] == "deterministic_fallback", "Rejected %s callback must not alter visible dialogue" % reason)
		if reason != "quality":
			_expect(host.quality_calls == 0, "Stale callback must not pollute the quality ledger")
		host.free()


func _test_retirement() -> void:
	var setup := _setup()
	var host: FakeHost = setup[0]
	var worker: Node = setup[1]
	var quest := _quest()
	worker.queue_offer(quest)
	worker.pump()
	worker.retire_offer(quest)
	_reply(host, _opening())
	_expect(host.quality_calls == 0 and quest["mission_dialogue_bundle_source"] == "deterministic_fallback", "An accepted/declined offer must reject its late generation")
	_expect(host.reports == ["deterministic_fallback"], "A wholly templated resolved offer must still count as fallback")
	host.free()



## A quest whose mission plan carries a causal contract, driven through the REAL
## accept_response path, so the quality gate is proven to actually run in the
## pipeline rather than only in its own unit test.
func _contracted_quest() -> Dictionary:
	var contract := Fixtures.investigation_one_choice()
	var mission := {
		"title": "Corvid Drift Log",
		"public_because": "The claims office will not pay out without a recovered flight log.",
		"stake": "The escort bond is called.",
		"objective_summary": "Recover the convoy flight log.",
		"reward_credits": 520,
		"causal_contract": contract,
	}
	var plan := {"intents": [
		{"id": "ask_why", "kind": "question", "label": "Why can't the claims office just pay out?"},
		{"id": "accept_standard", "kind": "terminal", "label": "Accept the contract"},
	], "forbidden_terms": []}
	var speaker := {"name": "Halda Vresk", "role": "claims adjuster"}
	var quest := {
		"story_beat_id": "beat.corvid",
		"mission_conversation_plan": plan,
		"mission_dialogue_bundle": Compiler.fallback_bundle(mission, plan, speaker),
		"mission_dialogue_bundle_source": "deterministic_fallback",
		"mission_dialogue_bundle_degraded": true,
		"mission_dialogue_bundle_degraded_reason": "generation_pending_safe_template",
	}
	Generation.attach(quest, mission, speaker)
	return quest


func _test_quality_gate_runs_in_the_real_generation_path() -> void:
	var quest := _contracted_quest()
	var job := _job(quest)

	# A good opening survives every existing validator AND the quality gate.
	var good := Generation.accept_response(quest, job, {"ok": true, "inner_text": JSON.stringify({
		"opening": "Four hulls went quiet in the Corvid drift and the office won't pay a credit without the flight log.",
	})})
	_expect(bool(good.get("ok", false)), "A clear contracted opening was rejected: %s" % str(good.get("errors", good.get("status", ""))))
	_expect(
		str(good.get("quality_state", "")) == QualityGate.QUALITY_UNKNOWN,
		"An unreviewed line must be recorded as quality_unknown, never as passed."
	)

	# An invented number is rejected by the gate, through the real path.
	var invented := Generation.accept_response(quest, _job(_contracted_quest()), {"ok": true, "inner_text": JSON.stringify({
		"opening": "Four hulls went quiet in the drift. You have 17 hours before the claim window shuts.",
	})})
	_expect(
		str(invented.get("status", "")) == "quality_rejected",
		"An invented deadline number reached publication through the real generation path."
	)
	_expect(
		QualityGate.ISSUE_UNSUPPORTED_NUMBER in (invented.get("errors", []) as Array),
		"The rejection did not report which issue caused it."
	)

	# The private motive was never in the prompt; if it appears anyway, reject.
	var leaked := Generation.accept_response(quest, _job(_contracted_quest()), {"ok": true, "inner_text": JSON.stringify({
		"opening": "If that log shows their own routing error the claim dies and the bond is called.",
	})})
	_expect(
		not bool(leaked.get("ok", true)),
		"A leaked private motive reached publication through the real generation path."
	)

	# The prompt for a contracted quest must not contain the secret either.
	var prompt := str(Generation.prompt_for_job(job).get("prompt", ""))
	_expect(
		not prompt.to_lower().contains("routing error"),
		"The private motive reached the generation prompt."
	)

	# And a quest WITHOUT a contract keeps its old behavior exactly -- the gate
	# abstains rather than rejecting prose it has no facts to judge.
	var plain := _quest()
	var plain_result := Generation.accept_response(plain, _job(plain), _opening())
	_expect(
		bool(plain_result.get("ok", false)),
		"An uncontracted offer was newly rejected by the quality gate."
	)
	_expect(
		str(plain_result.get("quality_state", "")) == QualityGate.QUALITY_PENDING,
		"An uncontracted offer should record quality_pending, not a verdict it never got."
	)


## The integration this slice exists for: the WRITER must receive the same public
## facts the gate will judge its output against. Before this, the packet was
## built only after generation, so the writer was never shown it.
func _test_writer_prompt_carries_the_fact_packet() -> void:
	var quest := _contracted_quest()
	var job := _job(quest)
	var prepared := Generation.prompt_for_job(job)
	_expect(bool(prepared.get("ok", false)), "Contracted slice failed to build a prompt.")
	var prompt := str(prepared.get("prompt", ""))
	_expect(
		prompt.contains("What you know and may say:"),
		"The writer prompt does not carry the fact packet at all."
	)
	_expect(
		prompt.contains("The claims office will not pay out without a recovered flight log"),
		"A public contract fact never reached the writer prompt."
	)
	# The secret stays out of the writer's prompt, not merely out of its output.
	_expect(
		not prompt.to_lower().contains("routing error"),
		"The private motive reached the writer prompt."
	)
	# Writer and validator must agree on WHICH facts those were.
	var fingerprints: Dictionary = prepared.get("packet_fingerprints", {})
	_expect(
		fingerprints.has("opening") and not str(fingerprints["opening"]).is_empty(),
		"The dispatched slice recorded no packet fingerprint."
	)
	var rebuilt := Generation.packet_fingerprints(
		Generation.slice_packets(quest["mission_dialogue_context"], job["slice"])
	)
	_expect(
		str(rebuilt.get("opening", "")) == str(fingerprints["opening"]),
		"Writer and validator derived different packets from identical inputs."
	)
	# An offer with no contract must not suddenly grow packet guidance.
	var plain_prepared := Generation.prompt_for_job(_job(_quest()))
	_expect(
		not str(plain_prepared.get("prompt", "")).contains("What you know and may say:"),
		"An uncontracted offer gained fact-packet guidance it has no facts for."
	)


## The failure the integration review named directly: the fact that actually
## answers the player must not be truncated away because unrelated facts were
## inserted before it.
func _test_answer_packet_keeps_the_fact_that_answers_the_question() -> void:
	var quest := _contracted_quest()
	var slices: Array = Compiler.plan_slices(quest["mission_conversation_plan"])
	# The intent slice, not the opening.
	var answer_slice: Dictionary = slices[slices.size() - 1]
	var packets: Dictionary = Generation.slice_packets(
		quest["mission_dialogue_context"], answer_slice
	)
	_expect(not packets.is_empty(), "The answer slice produced no packets.")
	var packet: Dictionary = packets.get("ask_why_response", {})
	_expect(not packet.is_empty(), "No packet was built for the ask_why answer.")
	_expect(
		str(packet.get("question_text", "")).contains("claims office"),
		"The answer packet does not know which question it is answering."
	)
	# The question asks why the office will not pay. That fact must be present.
	var ids: Array = packet.get("fact_ids", [])
	_expect(
		"fact.claim_denied" in ids,
		"The fact that answers the question was not selected: %s" % str(ids)
	)
	# And it should be ranked ahead of facts that have nothing to do with it.
	var claim_index := ids.find("fact.claim_denied")
	var bond_index := ids.find("fact.escort_bond")
	if bond_index >= 0:
		_expect(
			claim_index < bond_index,
			"An unrelated fact outranked the one that answers the question."
		)


## Facts moving between dispatch and response means the writer was grounded in
## something no longer true. That is a stale slice, not a bad line.
func _test_stale_fact_packet_is_refused() -> void:
	var quest := _contracted_quest()
	var job := _job(quest)
	Generation.prompt_for_job(job)
	_expect(
		job.has("packet_fingerprints"),
		"Dispatch did not record the packet fingerprints on the job."
	)
	job["packet_fingerprints"] = {"opening": "deliberately_not_the_real_fingerprint"}
	var result := Generation.accept_response(quest, job, {"ok": true, "inner_text": JSON.stringify({
		"opening": "Four hulls went quiet in the Corvid drift and the office won't pay without the log.",
	})})
	_expect(
		str(result.get("status", "")) == "stale_fact_packet",
		"A response grounded in changed facts was accepted: %s" % str(result.get("status", ""))
	)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _test_runtime_persistence() -> void:
	# Exercise the real GameRoot seams and on-disk store without starting a
	# gameplay scene or asking a live model to generate a test answer.
	var root_script: GDScript = load("res://scripts/GameRoot.gd")
	_expect(root_script != null and root_script.can_instantiate(), "GameRoot must compile")
	if root_script == null or not root_script.can_instantiate():
		return
	var game: Node = root_script.new()
	var probe := QueueProbe.new()
	game.add_child(probe)
	game.set("_mission_conversation_worker", probe)
	var fixture := "res://.tmp_godot_user/mission_conversation_runtime_%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	var file := FileAccess.open(fixture + "/campaign.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"id": "campaign.test.conversation", "campaign_id": "campaign.test.conversation", "schema_version": 1, "document_type": "campaign"}))
	file.close()
	var store: RefCounted = CacheStore.open(fixture)
	_expect(store.is_valid(), "Runtime cache fixture must open")
	game.set("campaign_narrative_cache_store", store)
	var quest := _quest()
	var original := quest.duplicate(true)
	var scheduler: RefCounted = game.call("_ensure_narrative_cache_scheduler")
	var parent_job := {"job_id": "parent", "cache_key": "parent", "kind": "current_station_agent_offer_bundle"}
	var parent_payload := {"content_type": "story_agent_offer", "quest_data": original.duplicate(true)}
	scheduler.restore_ready_job(parent_job, parent_payload)
	game.call("_persist_narrative_ready_payload", parent_job, parent_payload)
	Generation.promote(quest, Generation.accept_response(quest, _job(quest), _opening()))
	quest["mission_dialogue_progress"]["attempts"]["0"] = 1
	quest["mission_dialogue_progress"]["finished"] = ["0"]
	game.call("persist_mission_conversation_offer", quest)
	var saved_key := "mission_conversation_state:%s" % Generation.fingerprint(quest)
	var reopened: RefCounted = CacheStore.open(fixture)
	_expect(reopened.is_valid() and reopened.get_entry(saved_key).get("result_payload", {}).get("quest_data", {}).get("mission_dialogue_bundle_source") == "partial_generated", "Standalone generation progress must persist on disk")
	_expect(reopened.get_entry("parent").get("result_payload", {}).get("quest_data", {}).get("mission_dialogue_bundle_source") == "partial_generated", "Prefetch parent payload must receive and persist generated text")
	game.set("campaign_narrative_cache_store", reopened)
	game.call("queue_mission_conversation", original)
	_expect(probe.last_offer.get("mission_dialogue_bundle_source") == "partial_generated", "Real queue seam must hydrate saved progress before dispatch")
	var payload: Dictionary = game.call("_narrative_cache_payload_for_job", {"kind": "mission_conversation", "conversation_context": quest["mission_dialogue_context"], "slice": {"kind": "opening"}})
	_expect(payload.get("ok", false) and str(payload.get("prompt", "")).contains("Write only the opening."), "Real dispatch must build a mission slice prompt")
	_expect(game.call("_narrative_cache_job_has_worker", {"kind": "mission_conversation"}), "Real readiness gate must recognize mission conversation jobs")
	var diagnostics := root.get_node("GenerationDiagnostics")
	diagnostics.reset()
	game.call("record_mission_conversation_result", quest)
	var summary: Dictionary = diagnostics.summary()
	_expect(summary.get("total_fallbacks", -1) == 0 and summary.get("source_counts", {}).get("partial_generated", 0) == 1, "Real diagnostics must count partial generation without a fallback")
	game.free()
