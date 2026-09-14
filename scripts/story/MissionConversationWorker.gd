class_name MissionConversationWorker
extends Node

const Generation := preload("res://scripts/story/MissionConversationGeneration.gd")
const Compiler := preload("res://scripts/story/MissionConversationCompiler.gd")
const FieldContract := preload("res://scripts/story/DialogueFieldContract.gd")

var host: Node
var request_slice: Callable
var _scheduler: RefCounted
var _scope := ""
var _system_id := ""
var _store: RefCounted
var _epoch := 0
var _offers: Dictionary = {}
var _targets: Dictionary = {}


func configure(root_node: Node, transport: Callable) -> void:
	host = root_node
	request_slice = transport
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(timer)
	timer.timeout.connect(pump)
	timer.start()


func queue_offer(quest: Dictionary) -> void:
	if quest.get("mission_dialogue_context", {}).is_empty():
		return
	if bool(quest.get("mission_dialogue_progress", {}).get("retired", false)):
		return
	var scheduler: RefCounted = host.call("_ensure_narrative_cache_scheduler")
	var scope := str(host.get("active_campaign_slot_id"))
	var system_id := str(host.call("mission_conversation_system_id"))
	var cache_store: RefCounted = host.get("campaign_narrative_cache_store")
	if _scheduler != scheduler or _scope != scope or _system_id != system_id or _store != cache_store:
		if _scheduler != null:
			for old_job in _scheduler.jobs():
				if _offers.has(str(old_job.get("slice_of", ""))):
					_scheduler.cancel_job(str(old_job["job_id"]), "conversation_scope_changed")
		_offers.clear()
		_targets.clear()
		_scheduler = scheduler
		_scope = scope
		_system_id = system_id
		_store = cache_store
		_epoch += 1
	var fingerprint := Generation.fingerprint(quest)
	var base_id := "mission_conversation:%s:%s:%s" % [scope, system_id, fingerprint]
	if _offers.has(base_id):
		Generation.copy_generation(_offers[base_id], quest)
		# Keep distinct copies (UI and prefetch callers) synchronized.
		var known := false
		for target in _targets[base_id]:
			known = known or is_same(target, quest)
		if not known:
			_targets[base_id].append(quest)
		return
	_offers[base_id] = quest
	_targets[base_id] = [quest]
	var context: Dictionary = quest["mission_dialogue_context"]
	var base_job := {
		"job_id": base_id, "cache_key": base_id, "kind": "mission_conversation",
		"priority": 0, "campaign_id": scope,
		"system_id": str(host.call("mission_conversation_system_id")),
		"story_beat_id": str(quest.get("story_beat_id", "")),
		"context_fingerprint": fingerprint,
		"conversation_context": context.duplicate(true),
	}
	var queued: Dictionary = scheduler.queue_conversation_slices(base_job, Compiler.plan_slices(context["conversation_plan"]))
	if not bool(queued.get("ok", false)):
		return
	var progress: Dictionary = quest["mission_dialogue_progress"]
	for job in queued["jobs"]:
		var index := str(job["slice_index"])
		if index in progress.get("finished", []):
			scheduler.mark_ready(str(job["job_id"]))
		elif int(progress.get("attempts", {}).get(index, 0)) >= FieldContract.MAX_ATTEMPTS:
			progress["finished"].append(index)
			scheduler.cancel_job(str(job["job_id"]), "attempt_budget_exhausted")


func pump() -> void:
	if _scheduler == null or _scheduler != host.get("narrative_cache_scheduler"):
		return
	if _scheduler.is_paused():
		return
	for job in _scheduler.pending_jobs():
		if str(job.get("kind", "")) == "mission_conversation":
			start_job(job)
			return


func _applicable(job: Dictionary) -> bool:
	if _scheduler != host.get("narrative_cache_scheduler") or _scope != str(host.get("active_campaign_slot_id")):
		return false
	if _store != host.get("campaign_narrative_cache_store"):
		return false
	if str(job.get("system_id", "")) != str(host.call("mission_conversation_system_id")):
		return false
	var live: Dictionary = _scheduler.get_job(str(job.get("job_id", "")))
	if str(live.get("status", "")) not in ["queued", "in_flight"]:
		return false
	var id := str(job.get("slice_of", ""))
	return _offers.has(id) and FieldContract.is_still_applicable(job, Generation.fingerprint(_offers[id]))


func start_job(job: Dictionary) -> Dictionary:
	var job_id := str(job.get("job_id", ""))
	if not _applicable(job):
		_scheduler.discard_stale_jobs({"story_beat_id": str(job.get("story_beat_id", ""))})
		_scheduler.cancel_job(job_id, "stale_conversation")
		return {"ok": false, "processed": false, "status": "stale_conversation"}
	var started: Dictionary = _scheduler.mark_generation_started(job_id)
	if not bool(started.get("ok", false)):
		return started
	var quest: Dictionary = _offers[job["slice_of"]]
	var progress: Dictionary = quest["mission_dialogue_progress"]
	var index := str(job["slice_index"])
	progress["attempts"][index] = int(progress["attempts"].get(index, 0)) + 1
	_sync_offer(str(job["slice_of"]))
	var prepared: Dictionary = host.call("_mission_conversation_payload_for_cache_job", job)
	if not bool(prepared.get("ok", false)):
		_finish(job, {"ok": false, "reason": prepared.get("status", "prompt_failed")}, _scheduler, _epoch)
		return {"ok": true, "processed": true, "status": "prompt_failed"}
	var request_scheduler := _scheduler
	var request_epoch := _epoch
	request_slice.call(str(prepared["prompt"]), func(response: Dictionary) -> void:
		_finish(job, response, request_scheduler, request_epoch)
	)
	return {"ok": true, "processed": true, "status": "in_flight"}


func _finish(job: Dictionary, response: Dictionary, request_scheduler: RefCounted, request_epoch: int) -> void:
	var job_id := str(job["job_id"])
	if request_epoch != _epoch:
		return  # The same job ID may now belong to a newly restored request.
	# A late callback from a different campaign or replaced scheduler has no
	# authority over this offer, cache, or quality ledger.
	if request_scheduler != _scheduler or not _applicable(job):
		request_scheduler.cancel_job(job_id, "stale_conversation")
		return
	var id := str(job["slice_of"])
	var quest: Dictionary = _offers[id]
	var progress: Dictionary = quest["mission_dialogue_progress"]
	var index := str(job["slice_index"])
	_scheduler.mark_generation_finished(job_id)
	var result := Generation.accept_response(quest, job, response)
	if bool(result.get("ok", false)):
		var quality: Dictionary = host.call("validate_and_register_narrative_lines", result["lines"], "mission_conversation")
		if not bool(quality.get("ok", false)):
			result = {"ok": false, "status": str(quality.get("reason", "quality_rejected"))}
	if bool(result.get("ok", false)):
		Generation.promote(quest, result)
		progress["finished"].append(index)
		_scheduler.mark_validation_finished(job_id)
		_scheduler.mark_ready(job_id, {"source": "generated", "bundle": result["accepted"]})
	else:
		var remaining := FieldContract.MAX_ATTEMPTS - int(progress["attempts"][index])
		_scheduler.mark_validation_failed(job_id, result.get("errors", [result.get("status", "generation_failed")]), 1 if remaining > 0 else 0)
		if remaining <= 0:
			progress["finished"].append(index)
			# Canceled is terminal and releases dependent intent slices. Leaving
			# degraded_required here would strand them behind a failed opening.
			_scheduler.cancel_job(job_id, "slice_exhausted_safe_template_retained")
	_sync_offer(id)
	var slice_count := Compiler.plan_slices(quest["mission_conversation_plan"]).size()
	if progress["finished"].size() == slice_count:
		_report_result(id)


func retire_offer(quest: Dictionary) -> void:
	var id := "mission_conversation:%s:%s:%s" % [_scope, _system_id, Generation.fingerprint(quest)]
	if not _offers.has(id):
		return
	_offers[id]["mission_dialogue_progress"]["retired"] = true
	for job in _scheduler.jobs():
		if str(job.get("slice_of", "")) == id:
			_scheduler.cancel_job(str(job["job_id"]), "offer_resolved")
	_report_result(id)
	Generation.copy_generation(_offers[id], quest)
	_offers.erase(id)
	_targets.erase(id)


func _report_result(id: String) -> void:
	var quest: Dictionary = _offers[id]
	if not bool(quest["mission_dialogue_progress"].get("reported", false)):
		host.call("record_mission_conversation_result", quest)
		quest["mission_dialogue_progress"]["reported"] = true
	_sync_offer(id)


func _sync_offer(id: String) -> void:
	var source: Dictionary = _offers[id]
	for target in _targets[id]:
		if not is_same(source, target):
			Generation.copy_generation(source, target)
	host.call("persist_mission_conversation_offer", source)
