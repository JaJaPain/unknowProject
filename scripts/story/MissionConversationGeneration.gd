class_name MissionConversationGeneration
extends RefCounted

const Compiler := preload("res://scripts/story/MissionConversationCompiler.gd")
const Validator := preload("res://scripts/story/DialogueBundleValidator.gd")
const Soul := preload("res://scripts/story/FixedCastSoulRegistry.gd")
const FixedCastValidator := preload("res://scripts/story/FixedCastLineValidator.gd")
const FieldContract := preload("res://scripts/story/DialogueFieldContract.gd")
const QualityGate := preload("res://scripts/story/DialogueQualityGate.gd")
const FactPacket := preload("res://scripts/story/DialogueFactPacket.gd")
const CausalContract := preload("res://scripts/domain/QuestCausalContract.gd")


# The context and progress live on the offer, so a cached/saved offer can resume
# without regenerating accepted fields or resetting its two-attempt budget.
static func attach(quest: Dictionary, mission: Dictionary, speaker: Dictionary) -> void:
	quest["mission_dialogue_context"] = {
		"mission_plan": mission.duplicate(true),
		"speaker_card": speaker.duplicate(true),
		"conversation_plan": quest["mission_conversation_plan"].duplicate(true),
	}
	quest["mission_dialogue_progress"] = {"accepted": {}, "attempts": {}, "finished": []}


static func fingerprint(quest: Dictionary) -> String:
	# Godot reads JSON numbers back as floats. Normalize through the same
	# serialization boundary so 120 and a reloaded 120.0 identify the same job.
	var normalized: Variant = JSON.parse_string(JSON.stringify(quest.get("mission_dialogue_context", {})))
	return JSON.stringify(normalized).sha256_text()


static func fixed_cast_id(speaker: Dictionary) -> String:
	var identity := (str(speaker.get("name", "")) + " " + str(speaker.get("voice_profile_id", ""))).to_lower()
	if identity.contains("kaelen"):
		return "kaelen"
	if identity.contains("nova") or identity.contains("n.o.v.a."):
		return "nova"
	return ""


static func prompt_for_job(job: Dictionary) -> Dictionary:
	var context: Dictionary = job.get("conversation_context", {})
	if context.is_empty():
		return {"ok": false, "status": "missing_conversation_context"}
	var speaker: Dictionary = context["speaker_card"]
	var cast_id := fixed_cast_id(speaker)
	var safe_context := ""
	if not cast_id.is_empty():
		# Never substitute an improvised persona for the protected cast. A cast
		# member without an approved mission-offer situation keeps the safe floor.
		safe_context = Soul.prompt_block(cast_id, str(speaker.get("soul_state", "broker_neutral")), "mission_offer")
		if safe_context.is_empty():
			return {"ok": false, "status": "fixed_cast_projection_unavailable"}
	var prompt := Compiler.build_slice_prompt(
		context["mission_plan"], speaker, context["conversation_plan"], job["slice"], safe_context
	)
	# The writer now receives the SAME public fact packet the gate will validate
	# its output against. Previously the packet was built only after generation,
	# so its question-specific grounding never reached the writer at all and the
	# gate was checking prose against facts the writer had not been shown.
	var packets := slice_packets(context, job.get("slice", {}))
	prompt += _packet_guidance(packets)
	prompt += "\nOpening: at most 420 characters. Each answer: at most 220 characters."
	prompt += "\nKeep an exact player-safe reason or stake in the opening or ask_why answer. Preserve required answer anchors exactly."
	if not cast_id.is_empty():
		prompt += "\nAll fixed-cast lines, including the opening, must be at most 220 characters."
	var fingerprints := packet_fingerprints(packets)
	# Record what the writer was actually shown, so the response can be checked
	# against that exact snapshot instead of against whatever the world looks
	# like by the time it comes back.
	job["packet_fingerprints"] = fingerprints
	return {
		"ok": true,
		"prompt": prompt,
		"packet_fingerprints": fingerprints,
	}


## Build one public fact packet per output field of this slice.
##
## PURE and DETERMINISTIC: the writer path and the validation path both call
## this and must derive identical packets. Nothing is passed between them by
## reference, so there is no way for the two to silently diverge; a mismatch
## shows up as a fingerprint difference, which the stale-response guard already
## treats as a reason not to publish.
static func slice_packets(context: Dictionary, slice: Dictionary) -> Dictionary:
	var packets := {}
	var mission_plan: Dictionary = context.get("mission_plan", {})
	var contract: Variant = mission_plan.get("causal_contract", {})
	if not CausalContract.is_present(contract):
		return packets
	var plan: Dictionary = context.get("conversation_plan", {})
	var speaker: Dictionary = context.get("speaker_card", {})
	# The accepted opening, when this slice is answering after one exists. Taken
	# from the plan's own recorded opening rather than a live bundle so the
	# packet stays derivable from immutable inputs.
	var opening := str(mission_plan.get("opening_text", "")).strip_edges()
	for raw_key in Compiler.required_output_keys_for_slice(slice):
		var field := str(raw_key)
		var is_opening := field == "opening"
		packets[field] = FactPacket.build(
			contract,
			speaker,
			"opening" if is_opening else "answer",
			{
				"question_text": _intent_label(plan, field),
				"opening_text": "" if is_opening else opening,
			}
		)
	return packets


static func packet_fingerprints(packets: Dictionary) -> Dictionary:
	var fingerprints := {}
	for field in packets.keys():
		fingerprints[str(field)] = FactPacket.fingerprint(packets[field])
	return fingerprints


## Render the packets as writer guidance. One block per field, so an answer is
## told which question it is answering and which facts it may use for THAT
## question rather than inheriting the opening's selection.
static func _packet_guidance(packets: Dictionary) -> String:
	if packets.is_empty():
		return ""
	var blocks: Array[String] = []
	var fields: Array = packets.keys()
	fields.sort()
	for field in fields:
		var packet: Dictionary = packets[field]
		var header := "--- %s ---" % str(field)
		blocks.append("%s\n%s" % [header, FactPacket.prompt_block(packet)])
	return "\n\n" + "\n\n".join(blocks)


# Validate only requested fields, then validate their proposed combination with
# the safe floor. An invalid candidate cannot poison already accepted prose.
static func accept_response(quest: Dictionary, job: Dictionary, response: Dictionary) -> Dictionary:
	if not FieldContract.is_still_applicable(job, fingerprint(quest)):
		return {"ok": false, "status": "stale_conversation"}
	if not bool(response.get("ok", false)):
		return {"ok": false, "status": str(response.get("reason", "generation_failed"))}
	var context: Dictionary = job["conversation_context"]
	var plan: Dictionary = context["conversation_plan"]
	var speaker: Dictionary = context["speaker_card"]
	var parsed := Compiler.parse_bundle(str(response.get("inner_text", "")), plan, job["slice"])
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "status": "response_json_parse_failed", "errors": [parsed.get("reason", "")]}
	var slice_bundle: Dictionary = parsed["bundle"]
	var validation := Validator.validate_bundle(slice_bundle, plan, speaker, job["slice"])
	if not bool(validation.get("ok", false)):
		return {"ok": false, "status": "slice_validation_failed", "errors": validation["errors"]}
	var cast_id := fixed_cast_id(speaker)
	if not cast_id.is_empty():
		for line in slice_bundle.values():
			var cast_check := FixedCastValidator.validate_line(
				cast_id, str(speaker.get("soul_state", "broker_neutral")), "mission_offer", str(line)
			)
			if not bool(cast_check.get("ok", false)):
				return {"ok": false, "status": "fixed_cast_validation_failed", "errors": cast_check["errors"]}
	var progress: Dictionary = quest["mission_dialogue_progress"]
	var accepted := Compiler.merge_slice(progress.get("accepted", {}), slice_bundle)
	var assembled := Compiler.fallback_bundle(context["mission_plan"], plan, speaker)
	assembled.merge(accepted, true)
	validation = Validator.validate_bundle(assembled, plan, speaker)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "status": "assembled_validation_failed", "errors": validation["errors"]}
	var causal := Compiler.validate_causal_visibility(assembled, context["mission_plan"], plan)
	if not bool(causal.get("ok", false)):
		return {"ok": false, "status": str(causal.get("reason", "causal_visibility_missing"))}
	# Structural validity is not naturalness. The quality gate runs on top of the
	# existing validators, never instead of them, and only when the offer carries
	# a causal contract to judge the prose against.
	var quality := _quality_check_slice(
		context, plan, job.get("slice", {}), slice_bundle, assembled,
		job.get("packet_fingerprints", null)
	)
	if not bool(quality.get("ok", false)):
		return {
			"ok": false,
			"status": str(quality.get("status", "quality_rejected")),
			"errors": quality.get("errors", []),
		}
	return {
		"ok": true,
		"accepted": accepted,
		"bundle": assembled,
		"lines": slice_bundle.values(),
		"quality_state": str(quality.get("quality_state", QualityGate.QUALITY_UNKNOWN)),
		"quality_reason": str(quality.get("reason", "")),
		"packet_fingerprints": job.get("packet_fingerprints", {}),
	}


## Run the deterministic half of the quality gate over each line this slice
## produced. The constrained model review is NOT called here: this runs on the
## response path, and an extra inference call inside it would put model work on a
## path the player is waiting behind. Review is scheduled by the worker's budget.
##
## Without a causal contract there are no grounded facts to check a line against,
## so the gate abstains and the existing validators remain the whole story.
static func _quality_check_slice(
	context: Dictionary,
	plan: Dictionary,
	slice: Dictionary,
	slice_bundle: Dictionary,
	assembled: Dictionary,
	dispatched_fingerprints: Variant = null
) -> Dictionary:
	var mission_plan: Dictionary = context.get("mission_plan", {})
	var contract: Variant = mission_plan.get("causal_contract", {})
	if not CausalContract.is_present(contract):
		# No contract means no grounded facts to judge against. Say so
		# explicitly rather than implying a review was scheduled and pending.
		return {"ok": true, "quality_state": QualityGate.QUALITY_PENDING, "reason": "no_causal_grounding"}
	if plan.is_empty():
		return {"ok": true, "quality_state": QualityGate.QUALITY_PENDING, "reason": "no_conversation_plan"}
	# Re-derive the SAME packets the writer was given, from the same immutable
	# context, rather than rebuilding them with different options.
	var packets: Dictionary = slice_packets(context, slice)
	# If the facts moved between dispatch and response, the writer was grounded
	# in something that is no longer true. That is a stale slice, not a bad line:
	# discard it without spending an attempt on a rewrite that cannot help.
	var dispatched: Variant = dispatched_fingerprints
	if dispatched is Dictionary and not (dispatched as Dictionary).is_empty():
		var current := packet_fingerprints(packets)
		for field in (dispatched as Dictionary).keys():
			if str((dispatched as Dictionary)[field]) != str(current.get(field, "")):
				return {
					"ok": false,
					"status": "stale_fact_packet",
					"errors": ["packet_fingerprint_changed:%s" % str(field)],
					"quality_state": QualityGate.QUALITY_UNKNOWN,
				}
	var opening := str(assembled.get("opening", "")).strip_edges()
	for key in slice_bundle.keys():
		var field := str(key)
		var text := str(slice_bundle[key]).strip_edges()
		if text.is_empty():
			continue
		if not packets.has(field):
			# The response carried a field this slice never requested. Scoped
			# parsing already refuses those; treat it as ungrounded rather than
			# inventing a packet to judge it against.
			continue
		var packet: Dictionary = packets[field]
		# An answer must agree with the opening actually assembled so far. The
		# packet's own preceding_line comes from immutable plan state; the live
		# opening is supplied to the CHECK only, so it cannot shift the
		# fingerprint the writer was dispatched with.
		var check_packet: Dictionary = packet.duplicate(true)
		if field != "opening":
			check_packet["preceding_line"] = opening
		var report := QualityGate.hard_checks(text, check_packet, contract)
		var decision := QualityGate.decide(report, {})
		if not bool(decision.get("publishable", false)):
			return {
				"ok": false,
				"status": "quality_rejected",
				"errors": decision.get("issue_codes", []),
				"quality_state": QualityGate.QUALITY_REJECTED,
			}
	return {"ok": true, "quality_state": QualityGate.QUALITY_UNKNOWN}


## The player-facing question a given answer key belongs to, so the gate can tell
## whether the answer addresses what was actually asked.
static func _intent_label(plan: Dictionary, field: String) -> String:
	if not field.ends_with("_response"):
		return ""
	var intent_id := field.substr(0, field.length() - "_response".length())
	for raw_intent in (plan.get("intents", []) as Array):
		if not (raw_intent is Dictionary):
			continue
		var intent: Dictionary = raw_intent
		if str(intent.get("id", "")) == intent_id:
			return str(intent.get("label", ""))
	return ""


static func promote(quest: Dictionary, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	quest["mission_dialogue_progress"]["accepted"] = result["accepted"].duplicate(true)
	quest["mission_dialogue_bundle"] = result["bundle"].duplicate(true)
	# Record WHICH packet this verdict was about, not merely that a verdict
	# happened. A later per-field asynchronous review has to be able to tell
	# whether its result still applies to the facts currently on the offer.
	var quality_record := {
		"state": str(result.get("quality_state", QualityGate.QUALITY_UNKNOWN)),
		"critic_version": QualityGate.DialogueCritic.VERSION,
		"packet_version": FactPacket.PACKET_VERSION,
	}
	var reason := str(result.get("quality_reason", "")).strip_edges()
	if not reason.is_empty():
		quality_record["reason"] = reason
	var fingerprints: Variant = result.get("packet_fingerprints", {})
	if fingerprints is Dictionary and not (fingerprints as Dictionary).is_empty():
		quality_record["packet_fingerprints"] = (fingerprints as Dictionary).duplicate(true)
	quest["mission_dialogue_quality"] = quality_record
	var complete := Compiler.missing_keys(result["accepted"], quest["mission_conversation_plan"]).is_empty()
	quest["mission_dialogue_bundle_source"] = "generated" if complete else "partial_generated"
	quest["mission_dialogue_bundle_degraded"] = not complete
	if complete:
		quest.erase("mission_dialogue_bundle_degraded_reason")
	else:
		quest["mission_dialogue_bundle_degraded_reason"] = "some_fields_use_safe_template"


static func copy_generation(source: Dictionary, target: Dictionary) -> void:
	for key in ["mission_dialogue_bundle", "mission_dialogue_progress", "mission_dialogue_bundle_source", "mission_dialogue_bundle_degraded", "mission_dialogue_quality"]:
		var value: Variant = source.get(key)
		target[key] = value.duplicate(true) if value is Dictionary else value
	if source.has("mission_dialogue_bundle_degraded_reason"):
		target["mission_dialogue_bundle_degraded_reason"] = source["mission_dialogue_bundle_degraded_reason"]
	else:
		target.erase("mission_dialogue_bundle_degraded_reason")
