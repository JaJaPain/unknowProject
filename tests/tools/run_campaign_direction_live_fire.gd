extends SceneTree

## Real-model gate for the campaign director (package 5).
##
## Deliberately separate from the deterministic suites: those stub the writer,
## which proves the control flow and proves nothing about whether qwen3:8b can
## actually produce a compliant proposal. This asks the real model, with a real
## packet built from real generated desires and real bound collection contracts,
## and records every reply for human review.
##
## The question it answers is narrow and specific: does the writer select only
## supplied ids, cite only supplied facts, declare only supported links, and
## stay inside the promise the game can record -- or does it invent?
##
## Run:
##   Godot --headless --path . --script res://tests/tools/run_campaign_direction_live_fire.gd
##       --log-file <path> -- --llm-live-fire --count=5

const ARTIFACT_PATH := "res://logs/campaign_direction_live_fire.json"

const Direction := preload("res://scripts/story/CampaignDirectionContract.gd")
const Resolution := preload("res://scripts/story/CampaignResolutionCompiler.gd")
const Contract := preload("res://scripts/domain/CollectionContract.gd")
const Desire := preload("res://scripts/persistence/GeneratedFactionDesire.gd")

var _llm: Node = null
var _rows: Array[Dictionary] = []
var _run_count := 3
var _seed_base := 4242
var _packet: Dictionary = {}
var _started_msec := 0
var _item_started_msec := 0


func _initialize() -> void:
	_started_msec = Time.get_ticks_msec()
	await process_frame
	_llm = get_root().get_node_or_null("LLMInterface")
	if _llm == null:
		push_error("[DirectionLiveFire] LLMInterface autoload is unavailable.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			_run_count = clampi(int(arg.trim_prefix("--count=")), 1, 20)
		elif arg.begins_with("--seed="):
			_seed_base = int(arg.trim_prefix("--seed="))
	while not bool(_llm.get("small_model_verified")):
		await process_frame
	_packet = _build_packet()
	if (_packet.get("candidates", []) as Array).is_empty():
		push_error("[DirectionLiveFire] Could not bind any collection opportunity for the packet.")
		quit(1)
		return
	print("[DirectionLiveFire] model=%s candidates=%d facts=%d runs=%d" % [
		str(_llm.call("model_for_capability", "campaign_direction")),
		(_packet["candidates"] as Array).size(),
		(_packet["premise_fact_ids"] as Array).size(),
		_run_count])
	print("[DirectionLiveFire] --- prompt sent to the writer ---")
	print(Direction.build_prompt(Direction.writer_view(_packet), ""))
	print("[DirectionLiveFire] --- end prompt ---")
	_run_next("")


## A packet built the way the game builds one: real generated desires, real
## bound collection contracts, real premise fact ids.
func _build_packet() -> Dictionary:
	var opportunities: Array = []
	var seen_needs: Dictionary = {}
	for index in range(12000):
		if opportunities.size() >= 4:
			break
		var desire := Desire.build("live_fire_%d" % index, "local", _seed_base + index)
		var need := str(desire.get("need", ""))
		if not Contract.is_supported_need(need) or seen_needs.has(need):
			continue
		var slot := opportunities.size()
		var source := {
			"campaign_id": "campaign.livefire",
			"system_id": "system.tarrow" if slot % 2 == 0 else "system.keldane",
			"faction_id": "faction.local.%d" % slot,
			"desire_id": str(desire.get("id", "desire.local.%d" % slot)),
			"cause_id": "cause.local.%d" % slot,
			"obstacle_binding_id": str(desire.get("obstacle_binding_id", "")),
			"need": need,
		}
		var item := Desire.item_for_need(need, str(desire.get("id", "")))
		if item.is_empty():
			continue
		var bindings := {
			"action": "courier",
			"item_id_or_special_name": item,
			"quantity": 1,
			"source_station_id": "station.depot.%d" % slot,
			"source_supplies": true,
			"store_catalogue": false,
			"destination_station_id": "station.hub",
			"destination_registered": true,
			"recipient_id": "npc.hub.contact.%d" % slot,
			"recipient_is_generated_local": true,
		}
		var built := Contract.compile(source, bindings)
		if not bool(built.get("ok", false)):
			continue
		seen_needs[need] = true
		opportunities.append({"contract": built["contract"], "need": need,
			"faction_name": "Local Account %d" % slot,
			"agenda": {"faction_id": str(source["faction_id"]),
				"faction_name": "Local Account %d" % slot, "desire": desire}})
	var facts: Array = ["fact.tarrow.dispatch_backlog", "fact.tarrow.registry_dispute",
		"fact.keldane.carrier_liquidation"]
	return Direction.build_packet("campaign.livefire", opportunities, facts, [])


func _run_next(correction_note: String) -> void:
	if _rows.size() >= _run_count:
		_finish()
		return
	_item_started_msec = Time.get_ticks_msec()
	_llm.call("request_campaign_direction", Direction.writer_view(_packet), correction_note,
		func(result: Dictionary) -> void:
			_on_reply(result, correction_note)
	)


## Record one reply in full: what came back, whether the CONTRACT accepted it,
## and if not, exactly which rule it broke.
func _on_reply(result: Dictionary, correction_note: String) -> void:
	var elapsed := Time.get_ticks_msec() - _item_started_msec
	var row := {
		"run": _rows.size() + 1,
		"elapsed_ms": elapsed,
		"was_repair": not correction_note.is_empty(),
		"correction_note": correction_note,
		"transport_ok": bool(result.get("ok", false)),
		"transport_reason": str(result.get("reason", "")),
	}
	if not bool(result.get("ok", false)):
		row["outcome"] = "transport_or_parse_failed"
		_rows.append(row)
		print("[DirectionLiveFire] run %d: FAILED (%s) in %dms" % [
			row["run"], row["transport_reason"], elapsed])
		_run_next("")
		return
	var proposal: Dictionary = result.get("proposal", {})
	row["proposal"] = proposal.duplicate(true)
	var validated: Dictionary = Direction.validate_proposal(proposal, _packet)
	row["validated"] = bool(validated.get("ok", false))
	if not bool(validated.get("ok", false)):
		row["outcome"] = "rejected"
		row["rejection"] = str(validated.get("reason", ""))
		_rows.append(row)
		print("[DirectionLiveFire] run %d: REJECTED %s in %dms" % [
			row["run"], row["rejection"], elapsed])
		# Exercise the repair budget for real on the first rejection of a run.
		_run_next(str(validated.get("reason", "")) if correction_note.is_empty() else "")
		return
	var accepted: Dictionary = validated["proposal"]
	row["selected_collection_ids"] = (accepted["selected_collection_ids"] as Array).duplicate()
	row["premise_fact_ids"] = (accepted["premise_fact_ids"] as Array).duplicate()
	row["links"] = (accepted["links"] as Array).duplicate()
	row["public_direction"] = str(accepted["public_direction"])
	var compiled := Direction.compile_plan(accepted, _packet, "resolution.livefire.%d" % row["run"])
	row["compiled"] = bool(compiled.get("ok", false))
	if not bool(compiled.get("ok", false)):
		row["outcome"] = "uncompilable"
		row["rejection"] = str(compiled.get("reason", ""))
		_rows.append(row)
		print("[DirectionLiveFire] run %d: UNCOMPILABLE %s" % [row["run"], row["rejection"]])
		_run_next("")
		return
	var bound := Resolution.bind(compiled["plan"], _bind_context())
	row["bound"] = bool(bound.get("ok", false))
	row["bind_reason"] = str(bound.get("reason", ""))
	if bool(bound.get("ok", false)):
		row["plan_status"] = str((bound["plan"] as Dictionary).get("status", ""))
		row["plan_frozen"] = bool((bound["plan"] as Dictionary).get("frozen", false))
	row["outcome"] = "accepted" if bool(bound.get("ok", false)) else "unbound"
	_rows.append(row)
	print("[DirectionLiveFire] run %d: %s in %dms -- %d job(s), %d link(s): %s" % [
		row["run"], str(row["outcome"]).to_upper(), elapsed,
		(row["selected_collection_ids"] as Array).size(),
		(row["links"] as Array).size(), str(row["public_direction"])])
	_run_next("")


func _bind_context() -> Dictionary:
	var desires: Array = []
	var systems: Array = []
	var collection_ids: Array = []
	for raw: Variant in (_packet["candidates"] as Array):
		var candidate: Dictionary = raw
		desires.append({"system_id": str(candidate["system_id"]),
			"faction_id": str(candidate["faction_id"]), "desire_id": str(candidate["desire_id"])})
		if str(candidate["system_id"]) not in systems:
			systems.append(str(candidate["system_id"]))
		collection_ids.append(str(candidate["collection_id"]))
	return {"desires": desires, "system_ids": systems, "station_ids": ["station.hub"],
		"known_fact_ids": (_packet["premise_fact_ids"] as Array).duplicate(),
		"effect_ids": [], "collection_ids": collection_ids}


func _finish() -> void:
	var accepted := 0
	var rejected := 0
	var failed := 0
	var invented_ids := 0
	var invented_facts := 0
	var reasons: Dictionary = {}
	for row: Dictionary in _rows:
		match str(row.get("outcome", "")):
			"accepted": accepted += 1
			"transport_or_parse_failed": failed += 1
			_: rejected += 1
		var reason := str(row.get("rejection", row.get("transport_reason", "")))
		if not reason.is_empty():
			reasons[reason] = int(reasons.get(reason, 0)) + 1
			if reason.begins_with("unknown_collection_selection"):
				invented_ids += 1
			elif reason.begins_with("unknown_premise_fact"):
				invented_facts += 1
	var elapsed := Time.get_ticks_msec() - _started_msec
	var artifact := {
		"model": str(_llm.call("model_for_capability", "campaign_direction")),
		"runs": _rows.size(),
		"accepted": accepted,
		"rejected": rejected,
		"transport_failed": failed,
		"invented_collection_ids": invented_ids,
		"invented_premise_facts": invented_facts,
		"rejection_reasons": reasons,
		"total_ms": elapsed,
		"packet": _packet,
		"rows": _rows,
	}
	var file := FileAccess.open(ARTIFACT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(artifact, "  "))
		file.close()
	print("")
	print("[DirectionLiveFire] ============ SUMMARY ============")
	print("[DirectionLiveFire] model:                 %s" % artifact["model"])
	print("[DirectionLiveFire] runs:                  %d" % _rows.size())
	print("[DirectionLiveFire] accepted and bound:    %d" % accepted)
	print("[DirectionLiveFire] rejected by contract:  %d" % rejected)
	print("[DirectionLiveFire] transport/parse fails: %d" % failed)
	print("[DirectionLiveFire] invented collection ids: %d" % invented_ids)
	print("[DirectionLiveFire] invented premise facts:  %d" % invented_facts)
	for reason: String in reasons:
		print("[DirectionLiveFire]   reason %s x%d" % [reason, int(reasons[reason])])
	print("[DirectionLiveFire] total: %.1fs" % (float(elapsed) / 1000.0))
	print("[DirectionLiveFire] artifact: %s" % ARTIFACT_PATH)
	print("[DirectionLiveFire] NOTE: acceptance here means the proposal was")
	print("[DirectionLiveFire] STRUCTURALLY supported. Whether the sentence reads")
	print("[DirectionLiveFire] well is a human judgement this tool cannot make.")
	quit(0)
