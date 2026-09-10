extends SceneTree

# Slices only pay off if the scheduler respects their order. An intent answer
# generated before its opening is answering a conversation that has not started,
# and a dependency that blocks forever is worse than no dependency at all.

const SchedulerType := preload("res://scripts/story/NarrativeCacheScheduler.gd")
const CompilerType := preload("res://scripts/story/MissionConversationCompiler.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var probe = SchedulerType.new()
	if probe == null or not probe.has_method("queue_conversation_slices"):
		push_error("[FAIL] NarrativeCacheScheduler is missing slice support.")
		quit(1)
		return
	_test_slices_queue_as_separate_jobs()
	_test_opening_outranks_its_own_answers()
	_test_intent_slices_wait_for_the_opening()
	_test_a_failed_opening_does_not_block_forever()
	_test_waiting_is_distinguishable_from_stalled()
	if _failures.is_empty():
		print("[PASS] Scheduler slice tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _plan(intent_count: int) -> Dictionary:
	var intents: Array = []
	for i in range(intent_count):
		intents.append({"id": "intent_%d" % i, "kind": "question", "label": "Ask %d" % i})
	return {"intents": intents}


func _base() -> Dictionary:
	return {
		"job_id": "mission_7_convo",
		"cache_key": "convo:mission_7",
		"kind": "mission_conversation",
		"priority": SchedulerType.PRIORITY_P0,
	}


func _queue(intent_count: int) -> Array:
	var scheduler = SchedulerType.new()
	var slices: Array = CompilerType.plan_slices(_plan(intent_count))
	var result: Dictionary = scheduler.queue_conversation_slices(_base(), slices)
	return [scheduler, result]


func _test_slices_queue_as_separate_jobs() -> void:
	var pair: Array = _queue(3)
	var scheduler = pair[0]
	var result: Dictionary = pair[1]
	_expect(bool(result.get("ok", false)), "Queueing slices should succeed.")
	# 3 intents at 2 per slice = 1 opening + 2 intent slices.
	_expect(
		int(result.get("slice_count", 0)) == 3,
		"3 intents should queue 3 slice jobs, got %d" % int(result.get("slice_count", 0))
	)
	# Distinct cache keys, or the scheduler would dedupe them into one job and
	# the whole point would be lost.
	var keys := {}
	for job in scheduler.jobs():
		keys[str(job.get("cache_key", ""))] = true
	_expect(keys.size() == 3, "Each slice needs its own cache key, got %d distinct" % keys.size())


func _test_opening_outranks_its_own_answers() -> void:
	var pair: Array = _queue(2)
	var scheduler = pair[0]
	var first: Dictionary = scheduler.next_job()
	_expect(
		str((first.get("slice", {}) as Dictionary).get("kind", "")) == "opening",
		"The opening must be handed out first -- it is what the player sees."
	)
	for job in scheduler.jobs():
		var slice: Dictionary = job.get("slice", {})
		if str(slice.get("kind", "")) != "opening":
			_expect(
				int(job.get("priority", 0)) > SchedulerType.PRIORITY_P0,
				"An intent slice must not outrank the opening."
			)


func _test_intent_slices_wait_for_the_opening() -> void:
	var pair: Array = _queue(2)
	var scheduler = pair[0]
	# Only the opening is pending; the intent slice is waiting on it.
	var pending: Array = scheduler.pending_jobs()
	_expect(pending.size() == 1, "Only the opening should be pending initially, got %d" % pending.size())
	_expect(
		str((pending[0].get("slice", {}) as Dictionary).get("kind", "")) == "opening",
		"The one pending job should be the opening."
	)
	# Once the opening is ready the answers become available.
	var opening_id := str(pending[0].get("job_id", ""))
	scheduler.mark_generation_started(opening_id)
	scheduler.mark_generation_finished(opening_id)
	scheduler.mark_validation_finished(opening_id)
	scheduler.mark_ready(opening_id, {"opening": "You again."})
	_expect(
		not scheduler.pending_jobs().is_empty(),
		"After the opening is ready its answers must become available."
	)


func _test_a_failed_opening_does_not_block_forever() -> void:
	# Blocking on a failed dependency would turn one bad opening into a silent
	# conversation, which is worse than an opening-less answer.
	var pair: Array = _queue(2)
	var scheduler = pair[0]
	var opening_id := str(scheduler.pending_jobs()[0].get("job_id", ""))
	scheduler.cancel_job(opening_id, "test_failure")
	_expect(
		not scheduler.pending_jobs().is_empty(),
		"A canceled opening must release its dependants rather than stranding them."
	)


func _test_waiting_is_distinguishable_from_stalled() -> void:
	# A queue that looks empty for no visible reason is how a scheduler bug hides.
	var pair: Array = _queue(4)
	var scheduler = pair[0]
	var waiting: Array = scheduler.waiting_jobs()
	_expect(not waiting.is_empty(), "Blocked slices should be reported as waiting.")
	for job in waiting:
		_expect(
			str((job.get("slice", {}) as Dictionary).get("kind", "")) != "opening",
			"The opening depends on nothing and must never be waiting."
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
