class_name NarrativeQualityGate
extends RefCounted

const FingerprintLedgerType := preload("res://scripts/story/NarrativeFingerprintLedger.gd")

# Pure, explainable first-pass gate. New checks join here instead of being
# scattered through UI delivery code.
static func validate_line(
	text: String,
	ledger: RefCounted,
	kind: String = "",
	allowed_aliases: Array = [],
	forbidden_tokens: Array = []
) -> Dictionary:
	var clean := text.strip_edges()
	if clean.is_empty():
		return _fail("empty_text")
	if ledger == null or not ledger.has_method("inspect"):
		return _fail("missing_fingerprint_ledger")
	var duplicate: Dictionary = ledger.call("inspect", clean, kind)
	if not bool(duplicate.get("ok", false)):
		return _fail(str(duplicate.get("reason", "duplicate")), duplicate)
	var lower := clean.to_lower()
	for raw in forbidden_tokens:
		var token := str(raw).strip_edges().to_lower()
		if not token.is_empty() and lower.contains(token):
			return _fail("forbidden_token:%s" % token)
	# Proper noun checks are intentionally conservative: known aliases are always
	# allowed, and unknown capitalized words are reported for review rather than
	# hard-rejected until the player-knowledge catalog owns every alias.
	var unknown_terms := _unknown_capitalized_terms(clean, allowed_aliases)
	var warnings: Array[String] = []
	for term in unknown_terms:
		warnings.append("unexplained_reference:%s" % term)
	return {
		"ok": true,
		"reason": "",
		"warnings": warnings,
		"fingerprint": str(duplicate.get("fingerprint", "")),
	}


static func _unknown_capitalized_terms(text: String, allowed_aliases: Array) -> Array[String]:
	var allowed := {}
	for alias in allowed_aliases:
		allowed[str(alias).to_lower()] = true
	# Sentence-leading ordinary words match the deliberately simple proper-noun
	# heuristic below. They are not entities and should never drown the useful
	# review warnings.
	for ordinary_word in [
		"a", "an", "and", "as", "at", "but", "for", "from", "he", "her",
		"here", "i", "if", "in", "it", "my", "no", "of", "on", "our", "she",
		"that", "the", "their", "there", "these", "they", "this", "those",
		"to", "we", "well", "with", "yes", "you", "your",
	]:
		allowed[ordinary_word] = true
	var regex := RegEx.new()
	regex.compile("\\b[A-Z][a-z]{2,}\\b")
	var result: Array[String] = []
	for hit in regex.search_all(text):
		var term := hit.get_string()
		if term.to_lower() not in allowed and term not in result:
			result.append(term)
	return result


static func _fail(reason: String, detail: Dictionary = {}) -> Dictionary:
	return {"ok": false, "reason": reason, "warnings": [], "detail": detail.duplicate(true)}
