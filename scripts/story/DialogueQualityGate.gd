class_name DialogueQualityGate
extends RefCounted

## Sits ALONGSIDE DialogueBundleValidator, not in place of it. The existing
## validator proves a line is well-formed, correctly anchored and free of
## forbidden facts. None of that establishes that it sounds like a person, that
## it answers what was asked, or that it agrees with what the speaker already
## said. That is this gate's job.
##
## Two halves, deliberately separate:
##   hard_checks()  -- deterministic, always run, cheap, never needs a model.
##   review_*()     -- a constrained second opinion from the SAME small model.
##                     Imperfect by construction: the model can miss its own
##                     mistakes. Treated as a filter, never as approval.
##
## Nothing here is human review, and nothing here may relax protected-cast rules
## to improve a general style score.

const ContractType := preload("res://scripts/domain/QuestCausalContract.gd")
const DialogueCritic := preload("res://scripts/story/DialogueCritic.gd")

## Recorded separately from generated/partial/fallback provenance, because a
## valid template is not natural generated dialogue and a critic's pass is not
## human approval.
const QUALITY_PENDING := "quality_pending"
const QUALITY_PASSED := "quality_passed"
const QUALITY_REJECTED := "quality_rejected"
const QUALITY_UNKNOWN := "quality_unknown"

const VERDICT_PASS := "pass"
const VERDICT_REPAIR := "repair"
const VERDICT_UNCERTAIN := "uncertain"
const VERDICTS := [VERDICT_PASS, VERDICT_REPAIR, VERDICT_UNCERTAIN]

## Issue codes. Stable strings so diagnostics can be counted across runs.
const ISSUE_PRIVATE_LEAK := "private_fact_leaked"
const ISSUE_UNSUPPORTED_NUMBER := "unsupported_number"
const ISSUE_UNSUPPORTED_URGENCY := "unsupported_urgency"
const ISSUE_ENCODING_ARTIFACT := "encoding_artifact"
const ISSUE_CONTRADICTS_OPENING := "contradicts_opening"
const ISSUE_REPEATS_OPENING := "repeats_opening"
const ISSUE_DOES_NOT_ANSWER := "does_not_answer_question"
const ISSUE_MISSING_REQUIRED_FACT := "missing_required_fact"
const ISSUE_REUSED_RECENT_PHRASE := "reused_recent_phrase"
const ISSUE_ROBOTIC_RESTATEMENT := "robotic_restatement"
const ISSUE_EMPTY := "empty_text"

## One draft, one review, at most one targeted rewrite, one final review.
## Shared with the worker's existing attempt accounting rather than nested
## inside it -- a retry loop inside a retry loop is how a local model hangs.
const MAX_DRAFTS := 1
const MAX_REWRITES := 1
const MAX_REVIEWS := 2


## Deterministic checks. These run on EVERY candidate regardless of whether the
## reviewer is available, and they stay in the runtime path even if the critic
## is later moved offline.
static func hard_checks(
	text: String,
	packet: Dictionary,
	contract_source: Variant = {}
) -> Dictionary:
	var issues: Array[Dictionary] = []
	var clean := str(text).strip_edges()
	if clean.is_empty():
		return _report([{"code": ISSUE_EMPTY, "field": "text", "span": ""}])
	var contract: Dictionary = ContractType.normalize(contract_source)
	_check_private_leak(clean, contract, issues)
	_check_numbers(clean, packet, contract, issues)
	_check_urgency(clean, contract, issues)
	_check_encoding_artifacts(clean, issues)
	_check_against_opening(clean, packet, issues)
	_check_required_facts(clean, packet, issues)
	_check_recent_phrases(clean, packet, issues)
	return _report(issues)


## Lexical overlap is a diagnostic hint, not proof of an irrelevant or robotic
## line. Keep these visible for evaluation without rejecting plain paraphrases.
static func advisory_checks(text: String, packet: Dictionary) -> Dictionary:
	var issues: Array[Dictionary] = []
	_check_answers_question(text, packet, issues)
	_check_restatement(text, packet, issues)
	return _report(issues)


static func _report(issues: Array) -> Dictionary:
	var codes: Array[String] = []
	for issue in issues:
		var code := str((issue as Dictionary).get("code", ""))
		if code not in codes:
			codes.append(code)
	return {"ok": issues.is_empty(), "issues": issues, "issue_codes": codes}


## Characters that will be READ ALOUD as a glitch.
##
## Found in the first real writer run: an accepted line contained a U+FFFD
## replacement character mid-sentence ("tied up<?>no impound order"). The same
## class was recorded during the taunt work, where a curly apostrophe arrived as
## a bare "?" and would have been spoken. A line that looks nearly fine on screen
## can still be unusable through TTS, so this is a hard check rather than a
## cosmetic one.
static func _check_encoding_artifacts(text: String, issues: Array[Dictionary]) -> void:
	for artifact in [
		char(0xFFFD),  # replacement character: something was already lost
		"&amp;",
		"&quot;",
		"&#39;",
		"&apos;",
		"%su00" % char(92),  # an escape sequence that was never decoded
	]:
		if text.contains(artifact):
			issues.append({
				"code": ISSUE_ENCODING_ARTIFACT,
				"field": "text",
				"span": artifact,
			})
			return


## Time pressure the contract does not record.
##
## Found by the first real writer measurement, not by reasoning about the code:
## qwen3:4b appended "before it's too late" to jobs with no deadline and no
## urgency fact, in several independent generations. That is an invented stake --
## the same family as an invented number, and the player acts on it the same way.
##
## Deliberately narrow. It fires only on explicit deadline language, never on a
## speaker merely sounding impatient: being annoyed is characterisation, whereas
## "before the window shuts" is a claim about the world.
static func _check_urgency(
	text: String,
	contract: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var binding: Dictionary = contract.get("objective_binding", {}) 		if contract.get("objective_binding", {}) is Dictionary else {}
	if int(binding.get("deadline_minutes", 0)) > 0:
		return
	if not (contract.get("urgency_fact_ids", []) as Array).is_empty():
		return
	var lower := text.to_lower()
	for phrase in [
		"before it's too late",
		"before its too late",
		"before it is too late",
		"running out of time",
		"out of time",
		"before the window",
		"window closes",
		"window shuts",
		"before the deadline",
		"no time left",
		"clock is ticking",
	]:
		if lower.contains(phrase):
			issues.append({
				"code": ISSUE_UNSUPPORTED_URGENCY,
				"field": "text",
				"span": phrase,
			})
			return


## A private fact was never put in the prompt, so its appearance means the model
## reconstructed it or the packet builder was bypassed. Either is serious.
static func _check_private_leak(
	text: String,
	contract: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var lower := text.to_lower()
	for fact_id in ContractType.private_facts(contract).keys():
		var secret := ContractType.fact_text(contract, str(fact_id))
		if secret.is_empty():
			continue
		var distinctive := _distinctive_words(secret)
		if distinctive.size() < 3:
			continue
		var hits := 0
		for word in distinctive:
			if lower.contains(word):
				hits += 1
		if float(hits) / float(distinctive.size()) >= 0.7:
			issues.append({
				"code": ISSUE_PRIVATE_LEAK,
				"field": "text",
				"span": str(fact_id),
			})


## Numbers are the easiest thing for a small model to invent and the most
## damaging, because the player will act on them. Any figure in the line must
## appear in a supplied fact or in the objective binding.
static func _check_numbers(
	text: String,
	packet: Dictionary,
	contract: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var supported := _supported_numbers(packet, contract)
	for number in _numbers_in(text):
		if number not in supported:
			issues.append({
				"code": ISSUE_UNSUPPORTED_NUMBER,
				"field": "text",
				"span": number,
			})
	var sources := ""
	for fact in packet.get("facts", []):
		if fact is Dictionary:
			sources += " " + str(fact.get("text", ""))
	var binding: Dictionary = contract.get("objective_binding", {})
	if int(binding.get("deadline_minutes", 0)) > 0:
		sources += " %d minutes" % int(binding["deadline_minutes"])
	for claim in _time_claims(text):
		if claim not in _time_claims(sources):
			issues.append({"code": ISSUE_UNSUPPORTED_NUMBER, "field": "text", "span": "unsupported duration %s minutes" % claim})


static func _time_claims(text: String) -> Array[int]:
	var regex := RegEx.new()
	regex.compile("\\b([0-9]+)\\s+(minutes?|hours?|days?|weeks?)\\b")
	var values: Array[int] = []
	for entry in regex.search_all(_numeric_text(text)):
		var unit := entry.get_string(2)
		var factor := 1
		if unit.begins_with("hour"):
			factor = 60
		elif unit.begins_with("day"):
			factor = 1440
		elif unit.begins_with("week"):
			factor = 10080
		values.append(int(entry.get_string(1)) * factor)
	return values


static func _supported_numbers(packet: Dictionary, contract: Dictionary) -> Array[String]:
	var supported: Array[String] = []
	for raw_fact in (packet.get("facts", []) as Array):
		if not (raw_fact is Dictionary):
			continue
		for number in _numbers_in(str((raw_fact as Dictionary).get("text", ""))):
			if number not in supported:
				supported.append(number)
	var binding: Dictionary = contract.get("objective_binding", {}) \
		if contract.get("objective_binding", {}) is Dictionary else {}
	for key in ["quantity", "reward_credits", "deadline_minutes"]:
		if not binding.has(key):
			continue
		var value := str(binding[key])
		# 280.0 and 280 are the same number to a reader.
		if value.ends_with(".0"):
			value = value.substr(0, value.length() - 2)
		if value not in supported and value != "0":
			supported.append(value)
	return supported


## Spoken and digit-form quantities are both claims the player can act on.
static func _numbers_in(text: String) -> Array[String]:
	text = _numeric_text(text)
	var numbers: Array[String] = []
	var current := ""
	for index in range(text.length()):
		var character := text[index]
		if character.is_valid_int() or (character == "." and not current.is_empty()):
			current += character
			continue
		if not current.is_empty():
			var value := current.trim_suffix(".")
			if not value.is_empty() and value not in numbers:
				numbers.append(value)
			current = ""
	if not current.is_empty():
		var tail := current.trim_suffix(".")
		if not tail.is_empty() and tail not in numbers:
			numbers.append(tail)
	return numbers


## Normalize spoken numbers before checking them. The old digits-only scan
## silently accepted "eleven hours" and "nine hundred on delivery".
static func _numeric_text(text: String) -> String:
	var values := {"zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90}
	var words := text.to_lower().replace("-", " ").split(" ", false)
	var output: Array[String] = []
	var value := 0
	var active := false
	for index in words.size():
		var word := str(words[index])
		var clean := word.trim_suffix(".").trim_suffix(",").trim_suffix(";").trim_suffix(":")
		# "no one" and "any one" are pronouns, not numeric claims.
		var pronoun := clean == "one" and index > 0 and words[index - 1] in ["no", "any"]
		if values.has(clean) and not pronoun:
			value += int(values[clean])
			active = true
		elif clean in ["hundred", "thousand"] and active:
			value *= 100 if clean == "hundred" else 1000
		else:
			if active:
				output.append(str(value))
				active = false
				value = 0
			output.append(word)
		if active and clean != word:
			output.append(str(value))
			active = false
			value = 0
	if active:
		output.append(str(value))
	return " ".join(output)


## An answer that restates the opening is the most common way a generated
## conversation reads as a machine. Near-identical text is a repeat; a directly
## negated claim is a contradiction.
static func _check_against_opening(
	text: String,
	packet: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var opening := str(packet.get("preceding_line", "")).strip_edges()
	if opening.is_empty():
		return
	var overlap := _overlap_ratio(text, opening)
	if overlap >= 0.75:
		issues.append({"code": ISSUE_REPEATS_OPENING, "field": "text", "span": text.substr(0, 60)})
	for contradiction in _contradictions(text, opening):
		issues.append({
			"code": ISSUE_CONTRADICTS_OPENING,
			"field": "text",
			"span": contradiction,
		})


## Deliberately narrow: only flags a claim the speaker already made being
## directly negated. Broader disagreement is the reviewer's territory, because
## code guessing at meaning produces false rejections.
static func _contradictions(text: String, opening: String) -> Array[String]:
	var found: Array[String] = []
	var lower := text.to_lower()
	var opening_lower := opening.to_lower()
	# One negation can be undone by several different assertions, so each
	# negative carries every positive that would contradict it.
	var pairs := [
		["nobody", ["somebody", "someone", "everybody", "everyone"]],
		["no one", ["someone", "somebody", "everyone", "everybody"]],
		["nothing", ["something"]],
		["never", ["already", "always"]],
		["cannot", ["can"]],
		["will not", ["will"]],
		["is not", ["is"]],
	]
	for pair in pairs:
		var negative := str(pair[0])
		if not opening_lower.contains(negative):
			continue
		# Find the subject the opening negated and see if the answer asserts it.
		var subject := _word_after(opening_lower, negative)
		if subject.is_empty():
			continue
		for raw_positive in (pair[1] as Array):
			var assertion := "%s %s" % [str(raw_positive), subject]
			if lower.contains(assertion) and assertion not in found:
				found.append(assertion)
	return found


static func _word_after(text: String, phrase: String) -> String:
	var index := text.find(phrase)
	if index < 0:
		return ""
	var rest := text.substr(index + phrase.length()).strip_edges()
	var words := rest.split(" ", false)
	if words.is_empty():
		return ""
	return str(words[0]).trim_suffix(".").trim_suffix(",")


## "Does this answer the question they actually asked?" A question with a clear
## subject that the answer never touches is an irrelevant answer, which is one
## of the failures Abe named directly.
static func _check_answers_question(
	text: String,
	packet: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var question := str(packet.get("question_text", "")).strip_edges()
	if question.is_empty():
		return
	var subjects := _distinctive_words(question)
	if subjects.is_empty():
		return
	var lower := text.to_lower()
	for subject in subjects:
		if lower.contains(subject):
			return
		# Accept a simple morphological neighbour rather than demanding the
		# exact token; natural paraphrase is the goal, not keyword matching.
		if subject.length() > 5 and lower.contains(subject.substr(0, subject.length() - 1)):
			return
	issues.append({
		"code": ISSUE_DOES_NOT_ANSWER,
		"field": "text",
		"span": ", ".join(subjects),
	})


## A required fact must actually be STATED, not merely claimed. Keyword overlap
## is a weak proxy and is treated as one: this only fires when essentially none
## of the fact's substance is present.
static func _check_required_facts(
	text: String,
	packet: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var required: Array = packet.get("required_fact_ids", [])
	if required.is_empty():
		return
	var lower := text.to_lower()
	for raw_id in required:
		var fact_id := str(raw_id)
		var fact_text := _packet_fact_text(packet, fact_id)
		if fact_text.is_empty():
			continue
		var distinctive := _distinctive_words(fact_text)
		if distinctive.is_empty():
			continue
		var hits := 0
		for word in distinctive:
			if lower.contains(word):
				hits += 1
		if float(hits) / float(distinctive.size()) < 0.25:
			issues.append({
				"code": ISSUE_MISSING_REQUIRED_FACT,
				"field": "text",
				"span": fact_id,
			})


static func _packet_fact_text(packet: Dictionary, fact_id: String) -> String:
	for raw_fact in (packet.get("facts", []) as Array):
		if not (raw_fact is Dictionary):
			continue
		if str((raw_fact as Dictionary).get("id", "")) == fact_id:
			return str((raw_fact as Dictionary).get("text", ""))
	return ""


## The habitual opening. A speaker who begins every job the same way stops
## reading as a person, however good the individual line is.
static func _check_recent_phrases(
	text: String,
	packet: Dictionary,
	issues: Array[Dictionary]
) -> void:
	for raw_phrase in (packet.get("recent_phrases", []) as Array):
		var phrase := str(raw_phrase).strip_edges()
		if phrase.length() < 8:
			continue
		if _overlap_ratio(text, phrase) >= 0.8:
			issues.append({
				"code": ISSUE_REUSED_RECENT_PHRASE,
				"field": "text",
				"span": phrase,
			})


## Reading the briefing back. Catches the shape where the line is a near-verbatim
## concatenation of the supplied facts rather than something a person would say.
static func _check_restatement(
	text: String,
	packet: Dictionary,
	issues: Array[Dictionary]
) -> void:
	var facts: Array = packet.get("facts", [])
	if facts.size() < 2:
		return
	var matched := 0
	for raw_fact in facts:
		if not (raw_fact is Dictionary):
			continue
		var fact_text := str((raw_fact as Dictionary).get("text", ""))
		if fact_text.is_empty():
			continue
		if _overlap_ratio(text, fact_text) >= 0.85:
			matched += 1
	if matched >= 2:
		issues.append({
			"code": ISSUE_ROBOTIC_RESTATEMENT,
			"field": "text",
			"span": "%d supplied facts restated near-verbatim" % matched,
		})


## Fraction of `reference`'s distinctive words present in `text`.
static func _overlap_ratio(text: String, reference: String) -> float:
	var reference_words := _distinctive_words(reference)
	if reference_words.is_empty():
		return 0.0
	var lower := text.to_lower()
	var hits := 0
	for word in reference_words:
		if lower.contains(word):
			hits += 1
	return float(hits) / float(reference_words.size())


static func _distinctive_words(text: String) -> Array[String]:
	var stop_words := [
		"the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "at", "for",
		"with", "is", "are", "was", "were", "be", "been", "it", "its", "that",
		"this", "they", "them", "their", "there", "has", "have", "had", "not",
		"will", "can", "cannot", "from", "into", "out", "up", "down", "own",
		"what", "why", "how", "who", "when", "does", "do", "did", "you", "your",
		"about", "just", "then", "than", "some", "any", "all", "get", "got",
	]
	var words: Array[String] = []
	for raw_word in text.to_lower().split(" ", false):
		var word := str(raw_word).strip_edges()
		for punctuation in [".", ",", ";", ":", "'s", "\"", "'", "!", "?", ")", "("]:
			word = word.trim_suffix(punctuation).trim_prefix(punctuation)
		if word.length() < 4 or word in stop_words or word in words:
			continue
		words.append(word)
	return words


## Build the reviewer request. Deliberately a FRESH context: the reviewer sees
## the proposed text and the small PUBLIC packet, nothing else. It is told
## explicitly that the text is data, so a line containing instruction-shaped
## words cannot steer the review.
##
## The reviewer returns a verdict and issue codes. It never writes replacement
## facts and never approves a mechanical change -- those belong to code.
static func review_prompt(text: String, packet: Dictionary) -> String:
	# Compatibility only. New callers execute every DialogueCritic job.
	var jobs := DialogueCritic.jobs(text, packet)
	if jobs.is_empty():
		return ""
	var job := jobs[0].duplicate(true)
	job["target"] = text
	return DialogueCritic.prompt(job)


static func parse_review(_raw_text: String) -> Dictionary:
	# The old unbound pass/repair protocol cannot establish which facts or text
	# were reviewed. Never promote its cached/example output as approval.
	return _uncertain("legacy_review_protocol")

static func _uncertain(reason: String) -> Dictionary:
	return {"ok": true, "verdict": VERDICT_UNCERTAIN, "issues": [], "reason": reason}


## Combine hard checks and an optional review into one publication decision.
##
## `review` may be empty when no model is available -- that is `quality_unknown`,
## which is explicitly NOT `quality_passed`. Hard failures always reject
## regardless of what the reviewer said.
static func decide(hard: Dictionary, review: Dictionary = {}, calibration: Dictionary = {}, fingerprint: String = "") -> Dictionary:
	if not bool(hard.get("ok", false)):
		return {
			"state": QUALITY_REJECTED,
			"publishable": false,
			"issue_codes": hard.get("issue_codes", []),
			"source": "hard_checks",
		}
	if review.is_empty():
		# No critic ran. The line passed every check the game can make on its
		# own, so it is publishable -- but it is not recorded as reviewed.
		return {
			"state": QUALITY_UNKNOWN,
			"publishable": true,
			"issue_codes": [],
			"source": "hard_checks_only",
		}
	# A result is trusted only with an independently supplied calibration for
	# this exact model/prompt/schema/options configuration, never a model claim.
	if not bool(calibration.get("qualified", false)) or fingerprint.is_empty() \
			or str(calibration.get("fingerprint", "")) != fingerprint \
			or str(calibration.get("version", "")) != DialogueCritic.VERSION:
		return {"state": QUALITY_UNKNOWN, "publishable": true,
			"issue_codes": [], "source": "critic_unqualified"}
	if str(review.get("verdict", "")) == VERDICT_PASS and not review.get("issues", []).is_empty():
		return {"state": QUALITY_UNKNOWN, "publishable": true,
			"issue_codes": [], "source": "inconsistent_review"}
	match str(review.get("verdict", VERDICT_UNCERTAIN)):
		VERDICT_PASS:
			return {
				"state": QUALITY_PASSED,
				"publishable": true,
				"issue_codes": [],
				"source": "reviewed",
			}
		VERDICT_REPAIR:
			return {
				"state": QUALITY_REJECTED,
				"publishable": false,
				"issue_codes": review.get("issues", []),
				"source": "reviewed",
			}
		_:
			# The critic is imperfect and an uncertain verdict is not evidence of
			# a fault. The line already passed every hard check, so it publishes
			# while being recorded as unreviewed rather than approved.
			return {
				"state": QUALITY_UNKNOWN,
				"publishable": true,
				"issue_codes": review.get("issues", []),
				"source": "review_uncertain",
			}


## Whether another attempt is affordable, given the worker's existing attempt
## count. Keeps the budget in ONE place so it cannot be reset by reopening a
## panel or reloading a save.
static func rewrite_allowed(attempts_used: int) -> bool:
	return attempts_used < (MAX_DRAFTS + MAX_REWRITES)
