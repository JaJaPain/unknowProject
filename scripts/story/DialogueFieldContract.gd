class_name DialogueFieldContract
extends RefCounted

## One validated dialogue FIELD request and its prepared result (plan P4).
##
## PURE: dictionaries in, dictionaries out. No nodes, no autoloads, no LLM calls.
## The point of a field is that it is the SMALLEST unit worth preparing: one
## speaker, one purpose, one knowledge slice. Today a single failed response
## discards a whole bundle including the parts that were fine, and every bark
## carries the entire world with it. A field can fail alone and be repaired
## alone.
##
## Two shapes live here:
##   DialogueFieldRequest  -- what we intend to prepare (safe to persist)
##   PreparedDialogueField -- what came back and survived validation
##
## Both are versioned. A stored request whose version we no longer understand is
## discarded rather than guessed at: preparing the wrong line is worse than
## preparing none, because the wrong one is spoken with full confidence.

const VERSION := 1

## What a field is FOR. Determines the length budget, because an opening line and
## a one-word availability check are not the same kind of utterance.
const PURPOSES := ["opening", "answer", "return", "availability", "outcome", "callback"]

## Generous purposes get more room; everything else is meant to be short.
const ROOMY_PURPOSES := ["opening", "answer"]
const MAX_WORDS_ROOMY := 36
const MAX_WORDS_TIGHT := 28
const MAX_CHARS_ROOMY := 240
const MAX_CHARS_TIGHT := 180

## A request covers one speaker and one knowledge slice. More than two fields is
## a bundle again, which is the thing this replaces.
const MAX_FIELDS := 2
## At most two memories. The old packet builder copied every tension, hook and
## history entry into each bark, which is most of the wasted inference.
const MAX_MEMORIES := 2

## Lifecycle of a prepared field. "reserved" exists so a line can be claimed for
## an interaction that has not happened yet without another consumer taking it.
const STATUSES := ["prepared", "reserved", "delivered", "retired", "failed"]
## Two attempts, then the field is failed rather than retried forever. An
## unbounded repair loop is how a local model turns one bad line into a hang.
const MAX_ATTEMPTS := 2


## Word budget for a purpose.
static func max_words_for(purpose: String) -> int:
	return MAX_WORDS_ROOMY if purpose in ROOMY_PURPOSES else MAX_WORDS_TIGHT


## Character budget for a purpose. Chars as well as words because a model can
## satisfy a word count with very long words and still overflow a panel.
static func max_chars_for(purpose: String) -> int:
	return MAX_CHARS_ROOMY if purpose in ROOMY_PURPOSES else MAX_CHARS_TIGHT


## Build a request with the budgets filled in from the purpose, so no caller has
## to remember them and no two callers can disagree.
static func make_request(
	owner_id: String,
	speaker_id: String,
	purpose: String,
	field_ids: Array,
	options: Dictionary = {}
) -> Dictionary:
	var clean_fields: Array[String] = []
	for f in field_ids:
		var s := str(f).strip_edges()
		if not s.is_empty() and s not in clean_fields:
			clean_fields.append(s)
	var memories: Array[String] = []
	for m in options.get("memory_ids", []):
		var ms := str(m).strip_edges()
		if not ms.is_empty() and ms not in memories:
			memories.append(ms)
	return {
		"version": VERSION,
		"owner_id": owner_id.strip_edges(),
		"speaker_id": speaker_id.strip_edges(),
		"voice_profile_id": str(options.get("voice_profile_id", "")).strip_edges(),
		"field_ids": clean_fields,
		"purpose": purpose.strip_edges(),
		"fact_ids": options.get("fact_ids", []),
		"facts": options.get("facts", []),
		"memory_ids": memories,
		"required_anchor_groups": options.get("required_anchor_groups", []),
		"context_fingerprint": str(options.get("context_fingerprint", "")).strip_edges(),
		"eligibility": options.get("eligibility", {}),
		"soul_version": str(options.get("soul_version", "")),
		"rapport_band": str(options.get("rapport_band", "")),
		"situation": str(options.get("situation", "")),
		"delivery_preset": str(options.get("delivery_preset", "")),
		"max_words_per_field": max_words_for(purpose),
		"max_chars_per_field": max_chars_for(purpose),
	}


## Validate a request before it costs an inference call. Returns
## {ok: bool, reason: String}. Reasons are specific so a rejection can be acted
## on rather than merely counted.
static func validate_request(request: Dictionary) -> Dictionary:
	if int(request.get("version", 0)) != VERSION:
		return _fail("unsupported_version")
	for key in ["owner_id", "speaker_id"]:
		if str(request.get(key, "")).strip_edges().is_empty():
			return _fail("missing_%s" % key)
	var purpose := str(request.get("purpose", ""))
	if purpose not in PURPOSES:
		return _fail("unknown_purpose:%s" % purpose)
	var fields: Array = request.get("field_ids", [])
	if fields.is_empty():
		return _fail("no_fields")
	if fields.size() > MAX_FIELDS:
		return _fail("too_many_fields:%d" % fields.size())
	if request.get("memory_ids", []).size() > MAX_MEMORIES:
		return _fail("too_many_memories:%d" % request.get("memory_ids", []).size())
	# A request without a fingerprint cannot be invalidated when the world moves
	# on, so it would be served forever as a stale line.
	if str(request.get("context_fingerprint", "")).strip_edges().is_empty():
		return _fail("missing_context_fingerprint")
	# Every fact referenced must actually be supplied. A model asked to speak
	# about a fact it was never given will invent one, confidently.
	var supplied := {}
	for fact in request.get("facts", []):
		if fact is Dictionary:
			supplied[str((fact as Dictionary).get("id", ""))] = true
	for fact_id in request.get("fact_ids", []):
		if not supplied.has(str(fact_id)):
			return _fail("fact_not_supplied:%s" % str(fact_id))
	return {"ok": true, "reason": ""}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## Stable identity for one accepted line. Hashing the OWNER, FIELD, FINGERPRINT
## and TEXT together means the same words prepared for a different situation are
## a different line -- which is what lets consumption and retirement records be
## trusted later.
static func line_id_for(
	owner_id: String, field_id: String, context_fingerprint: String, text: String
) -> String:
	return ("%s|%s|%s|%s" % [owner_id, field_id, context_fingerprint, text]).sha256_text().substr(0, 24)


## Wrap an accepted line as a PreparedDialogueField.
static func make_prepared(
	request: Dictionary, field_id: String, display_text: String, options: Dictionary = {}
) -> Dictionary:
	var text := display_text.strip_edges()
	var fingerprint := str(request.get("context_fingerprint", ""))
	var owner := str(request.get("owner_id", ""))
	return {
		"version": VERSION,
		"owner_id": owner,
		"speaker_id": str(request.get("speaker_id", "")),
		"field_id": field_id.strip_edges(),
		"display_text": text,
		"fact_ids": request.get("fact_ids", []),
		"context_fingerprint": fingerprint,
		"eligibility": request.get("eligibility", {}),
		"delivery_preset": str(request.get("delivery_preset", "")),
		"source": str(options.get("source", "generated")),
		"status": str(options.get("status", "prepared")),
		"attempt_count": int(options.get("attempt_count", 1)),
		"generator_model_digest": str(options.get("generator_model_digest", "")),
		"compiler_version": int(options.get("compiler_version", VERSION)),
		"validator_version": int(options.get("validator_version", VERSION)),
		"line_id": line_id_for(owner, field_id, fingerprint, text),
	}


## Validate a prepared field AGAINST the request that asked for it. Checking the
## pair rather than the field alone is the point: a line can be perfectly well
## formed and still answer a question nobody asked.
static func validate_prepared(prepared: Dictionary, request: Dictionary) -> Dictionary:
	if int(prepared.get("version", 0)) != VERSION:
		return _fail("unsupported_version")
	var text := str(prepared.get("display_text", "")).strip_edges()
	if text.is_empty():
		return _fail("empty_text")
	var field_id := str(prepared.get("field_id", ""))
	if field_id not in request.get("field_ids", []):
		return _fail("field_not_requested:%s" % field_id)
	if str(prepared.get("owner_id", "")) != str(request.get("owner_id", "")):
		return _fail("owner_mismatch")
	if str(prepared.get("speaker_id", "")) != str(request.get("speaker_id", "")):
		return _fail("speaker_mismatch")
	# A fingerprint mismatch means the world changed after this was requested.
	# Serving it would be a stale line delivered with confidence.
	if str(prepared.get("context_fingerprint", "")) != str(request.get("context_fingerprint", "")):
		return _fail("stale_context")
	if str(prepared.get("status", "")) not in STATUSES:
		return _fail("unknown_status:%s" % str(prepared.get("status", "")))
	var attempts := int(prepared.get("attempt_count", 0))
	if attempts < 1 or attempts > MAX_ATTEMPTS:
		return _fail("attempt_count_out_of_range:%d" % attempts)
	var word_count := text.split(" ", false).size()
	if word_count > int(request.get("max_words_per_field", MAX_WORDS_TIGHT)):
		return _fail("too_many_words:%d" % word_count)
	if text.length() > int(request.get("max_chars_per_field", MAX_CHARS_TIGHT)):
		return _fail("too_many_chars:%d" % text.length())
	return {"ok": true, "reason": ""}


## True when a prepared field can still be spoken for the CURRENT world state.
## Separate from validation: a field can be valid and no longer applicable.
static func is_still_applicable(prepared: Dictionary, current_fingerprint: String) -> bool:
	if str(prepared.get("status", "")) in ["retired", "failed", "delivered"]:
		return false
	return str(prepared.get("context_fingerprint", "")) == current_fingerprint.strip_edges()
