extends SceneTree

# Phase 8B refill trigger: consuming a cached line bank down to the
# threshold queues a low-priority refill job, and processing that job
# tops the bank back up without ever re-offering a retired line.

const BankType := preload("res://scripts/story/FallbackLineBank.gd")

const REQUESTER := "prefetch:current_system_nova:test_refill_system"
const CACHE_KEY := "prefetch.test.nova_refill"

var _failures: Array[String] = []


func _initialize() -> void:
	_test_low_bank_triggers_refill_and_tops_up()
	_test_nova_bank_seed_wiring()

	if _failures.is_empty():
		print("[PASS] Line bank refill tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _refill_jobs(scheduler: RefCounted) -> Array:
	var result: Array = []
	for job in scheduler.jobs():
		if str((job as Dictionary).get("kind", "")) == "line_bank_low_refill":
			result.append(job)
	return result


func _test_low_bank_triggers_refill_and_tops_up() -> void:
	var game_root_script: GDScript = load("res://scripts/GameRoot.gd")
	if game_root_script == null or not game_root_script.can_instantiate():
		_failures.append("GameRoot.gd did not compile.")
		return
	var gr: Node = game_root_script.new()
	var scheduler: RefCounted = gr._ensure_narrative_cache_scheduler()

	# Seed a small ready nova bank (5 lines, target 5).
	var bank := BankType.create_bank("nova", "system_arrival", [
		"Test line one.",
		"Test line two.",
		"Test line three.",
		"Test line four.",
		"Test line five.",
	], 5)
	var payload := {
		"content_type": "story_line_bank",
		"source": "fallback_bank",
		"cache_key": CACHE_KEY,
		"requester_id": REQUESTER,
		"speaker_key": "nova",
		"speaker_name": "N.O.V.A.",
		"voice_profile_id": "voice.nova.v1",
		"line_bank": (bank.get("entries", []) as Array).duplicate(true),
		"fallback_bank": bank,
		"fallback_target_size": 5,
		"fallback_available_count": BankType.available_count(bank),
	}
	var restored: Dictionary = scheduler.restore_ready_job({
		"job_id": "job.test.nova_refill",
		"cache_key": CACHE_KEY,
		"kind": "current_system_nova_bundle",
		"requester_id": REQUESTER,
	}, payload)
	_expect(
		bool(restored.get("ok", false)),
		"Could not seed the ready nova bank."
	)

	# 5 -> 4 remaining: above the threshold, nothing queued.
	var first: Dictionary = gr.consume_cached_narrative_line_bank(
		REQUESTER, "system_arrival"
	)
	_expect(not first.is_empty(), "First consume returned no payload.")
	var first_text := str(
		(first.get("consumed_line", {}) as Dictionary).get("text", "")
	)
	_expect(
		_refill_jobs(scheduler).is_empty(),
		"Refill queued too early with 4 lines remaining."
	)

	# 4 -> 3 remaining: at the threshold, exactly one refill job queues.
	var second: Dictionary = gr.consume_cached_narrative_line_bank(
		REQUESTER, "system_arrival"
	)
	var second_text := str(
		(second.get("consumed_line", {}) as Dictionary).get("text", "")
	)
	_expect(
		int(second.get("fallback_available_count", -1)) == 3,
		"Second consume did not leave 3 available lines."
	)
	var refills := _refill_jobs(scheduler)
	_expect(
		refills.size() == 1,
		"Exactly one refill job should queue at 3 remaining, got %d."
			% refills.size()
	)
	if refills.size() != 1:
		gr.free()
		return
	var refill_job: Dictionary = refills[0]
	_expect(
		str(refill_job.get("target_requester_id", "")) == REQUESTER
			and str(refill_job.get("speaker_key", "")) == "nova",
		"Refill job does not target the low bank."
	)

	# A third consume while the refill is queued dedupes, not duplicates.
	gr.consume_cached_narrative_line_bank(REQUESTER, "system_arrival")
	_expect(
		_refill_jobs(scheduler).size() == 1,
		"Repeat consume duplicated the refill job."
	)

	# Run the degraded template floor directly (the live worker dispatches an
	# async LLM batch first, which a headless test cannot await): used slots
	# refill from the nova template and the delivered lines never come back.
	var refilled: Dictionary = gr._template_line_bank_refill(
		refill_job, REQUESTER, "nova"
	)
	_expect(
		bool(refilled.get("ok", false)),
		"Template refill failed: %s" % str(refilled.get("status", ""))
	)
	var after: Dictionary = gr.ready_cached_narrative_line_bank(REQUESTER)
	_expect(
		int(after.get("fallback_available_count", -1)) == 5,
		"Refill did not top the bank back up to 5 available, got %d."
			% int(after.get("fallback_available_count", -1))
	)
	var texts: Array = []
	for raw_entry in (after.get("line_bank", []) as Array):
		texts.append(str((raw_entry as Dictionary).get("text", "")))
	_expect(
		not texts.has(first_text) and not texts.has(second_text),
		"A retired line came back after the refill."
	)
	gr.free()

	# The live worker dispatches the LLM batch for nova banks and only falls
	# to the template floor on failure, logged as degraded content.
	var game_root_file := FileAccess.open(
		"res://scripts/GameRoot.gd", FileAccess.READ
	)
	_expect(game_root_file != null, "Could not inspect refill dispatch wiring.")
	if game_root_file == null:
		return
	var source := game_root_file.get_as_text()
	_expect(
		source.contains("request_nova_line_bank_batch")
			and source.contains("func _on_nova_line_bank_batch_completed")
			and source.contains("\"template_refill_used\"")
			and source.contains("func _nova_refill_batch_fields")
			and source.contains("func _nova_line_bank_generation_context"),
		"Refill worker does not dispatch batch generation with a logged template floor."
	)


# Phase 8B seeding: a fresh N.O.V.A. bank populates its movement/combat
# categories so those beats stop drawing stock. Field sets must be valid
# batches (<=10 labels, no protected categories), the bank must have
# headroom for the appended lines, the ready hook must dispatch, and the
# per-bank guard must prevent double-seeding.
func _test_nova_bank_seed_wiring() -> void:
	var game_root_script: GDScript = load("res://scripts/GameRoot.gd")
	if game_root_script == null or not game_root_script.can_instantiate():
		_failures.append("GameRoot.gd did not compile.")
		return
	var gr: Node = game_root_script.new()
	var llm: GDScript = load("res://scripts/LLMInterface.gd")

	# Both seed batches must expand into valid, non-empty, capped label sets.
	for fields in [gr._nova_refill_batch_fields(), gr._nova_seed_combat_batch_fields()]:
		var labels: Array = llm.nova_line_bank_labels(fields)
		_expect(
			not labels.is_empty() and labels.size() <= 10,
			"Seed batch produced an invalid label count: %d" % labels.size()
		)

	# Combat seed must cover the categories that fell to stock in the log.
	var combat_categories: Array = []
	for field in gr._nova_seed_combat_batch_fields():
		combat_categories.append(str((field as Dictionary).get("category", "")))
	for expected in [
		"combat_victory_clean",
		"combat_victory_battered",
		"hull_critical",
		"welcome_back",
		"docked",
	]:
		_expect(
			combat_categories.has(expected),
			"Combat seed batch is missing category: %s" % expected
		)

	# The nova bank target size must exceed the arrival template so appended
	# generated lines have room.
	_expect(
		int(gr.NOVA_LINE_BANK_TARGET_SIZE) > int(BankType.DEFAULT_TARGET_SIZE),
		"Nova bank has no headroom for seeded category lines."
	)

	# The per-bank guard blocks a second seed of the same requester.
	gr._nova_bank_seed_requests["prefetch:current_system_nova:x"] = true
	gr._seed_nova_line_bank("prefetch:current_system_nova:x")
	_expect(
		gr._nova_bank_seed_requests.size() == 1,
		"Seed guard did not prevent a duplicate seed."
	)
	gr.free()

	# The ready path dispatches the seed for both nova bundle job kinds.
	var file := FileAccess.open("res://scripts/GameRoot.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect seed ready-hook.")
	if file == null:
		return
	var source := file.get_as_text()
	var process_start := source.find("func _process_narrative_cache_job")
	var process_end := source.find("\nfunc ", process_start + 10)
	var process_body := source.substr(process_start, process_end - process_start)
	_expect(
		process_body.contains("_seed_nova_line_bank")
			and process_body.contains("new_campaign_nova_bank")
			and process_body.contains("current_system_nova_bundle"),
		"Ready path does not seed the nova bank for its bundle job kinds."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
