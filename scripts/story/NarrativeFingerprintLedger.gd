class_name NarrativeFingerprintLedger
extends RefCounted

# Campaign-wide text memory for post-tutorial narrative output. Callers own
# whether a rejection is hard or advisory; this class only explains similarity.

const SCHEMA_VERSION := 1
const SHORT_LINE_MAX_WORDS := 12
const SHORT_LINE_NEAR_THRESHOLD := 0.72
const LONG_LINE_NEAR_THRESHOLD := 0.58
const MAX_ENTRIES := 512

const _COMMON_WORDS := {
	"a": true, "an": true, "and": true, "are": true, "at": true, "be": true,
	"but": true, "for": true, "from": true, "has": true, "have": true, "i": true,
	"in": true, "is": true, "it": true, "my": true, "of": true, "on": true,
	"or": true, "that": true, "the": true, "this": true, "to": true, "was": true,
	"we": true, "with": true, "you": true, "your": true,
}

var _entries: Array[Dictionary] = []


func inspect(text: String, kind: String = "") -> Dictionary:
	var normalized := normalize(text)
	if normalized.is_empty():
		return {"ok": false, "reason": "empty_text"}
	var fingerprint := normalized.sha256_text()
	var tokens := distinctive_tokens(normalized)
	var candidate_bigrams := _bigrams(tokens)
	var threshold := _threshold_for(tokens.size())
	for entry in _entries:
		if str(entry.get("fingerprint", "")) == fingerprint:
			return {
				"ok": false, "reason": "exact_duplicate", "fingerprint": fingerprint,
				"matched_entry": entry.duplicate(true), "similarity": 1.0,
			}
		var prior_tokens: Array = entry.get("distinctive_tokens", []) if entry.get("distinctive_tokens", []) is Array else []
		var similarity := _jaccard(candidate_bigrams, _bigrams(prior_tokens))
		if similarity >= threshold:
			return {
				"ok": false, "reason": "near_duplicate", "fingerprint": fingerprint,
				"matched_entry": entry.duplicate(true), "similarity": similarity,
				"threshold": threshold,
			}
	return {"ok": true, "fingerprint": fingerprint, "similarity": 0.0, "threshold": threshold}


func register(text: String, kind: String = "", metadata: Dictionary = {}) -> Dictionary:
	var verdict := inspect(text, kind)
	if not bool(verdict.get("ok", false)):
		return verdict
	var normalized := normalize(text)
	_entries.append({
		"fingerprint": str(verdict.get("fingerprint", "")),
		"normalized": normalized,
		"distinctive_tokens": distinctive_tokens(normalized),
		"kind": kind.strip_edges(),
		"metadata": metadata.duplicate(true),
	})
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	return verdict


func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func to_dict() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "entries": entries()}


func load_dict(data: Dictionary) -> void:
	_entries.clear()
	var raw: Array = data.get("entries", []) if data.get("entries", []) is Array else []
	for entry in raw:
		if not entry is Dictionary:
			continue
		var text := str((entry as Dictionary).get("normalized", ""))
		if text.is_empty():
			continue
		_entries.append((entry as Dictionary).duplicate(true))
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()


static func normalize(text: String) -> String:
	var lower := text.to_lower().strip_edges()
	var clean := ""
	for character in lower:
		if character.unicode_at(0) >= 48 and character.unicode_at(0) <= 57 \
				or character.unicode_at(0) >= 97 and character.unicode_at(0) <= 122:
			clean += character
		else:
			clean += " "
	return " ".join(clean.split(" ", false))


static func distinctive_tokens(normalized_text: String) -> Array[String]:
	var result: Array[String] = []
	for token in normalized_text.split(" ", false):
		if token.length() >= 3 and not _COMMON_WORDS.has(token):
			result.append(token)
	return result


static func _bigrams(tokens: Array) -> Dictionary:
	var result := {}
	if tokens.size() < 2:
		for token in tokens:
			result[str(token)] = true
		return result
	for index in range(tokens.size() - 1):
		result["%s %s" % [str(tokens[index]), str(tokens[index + 1])]] = true
	return result


static func _jaccard(left: Dictionary, right: Dictionary) -> float:
	if left.is_empty() or right.is_empty():
		return 0.0
	var overlap := 0
	for key in left:
		if right.has(key):
			overlap += 1
	return float(overlap) / float(left.size() + right.size() - overlap)


static func _threshold_for(word_count: int) -> float:
	return SHORT_LINE_NEAR_THRESHOLD if word_count <= SHORT_LINE_MAX_WORDS else LONG_LINE_NEAR_THRESHOLD
