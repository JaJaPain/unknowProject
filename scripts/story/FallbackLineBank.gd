class_name FallbackLineBank
extends RefCounted

const DEFAULT_TARGET_SIZE := 20


static func create_bank(
	speaker_key: String,
	line_kind: String,
	fallback_lines: Array,
	target_size: int = DEFAULT_TARGET_SIZE
) -> Dictionary:
	var clean_speaker := speaker_key.strip_edges()
	var clean_kind := line_kind.strip_edges()
	var clean_target: int = max(1, target_size)
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	var index := 0
	for raw_line in fallback_lines:
		var text := str(raw_line).strip_edges()
		var entry_kind := clean_kind
		if raw_line is Dictionary:
			var line: Dictionary = raw_line
			text = str(line.get("text", "")).strip_edges()
			entry_kind = str(line.get("kind", clean_kind)).strip_edges()
			if entry_kind.is_empty():
				entry_kind = clean_kind
		if text.is_empty() or seen.has(text):
			continue
		seen[text] = true
		entries.append(_entry(clean_speaker, entry_kind, text, "fallback", index))
		index += 1
		if entries.size() >= clean_target:
			break
	return {
		"speaker_key": clean_speaker,
		"line_kind": clean_kind,
		"target_size": clean_target,
		"entries": entries,
		"fallback_uses": 0,
		"generated_replacements": 0,
	}


static func available_count(bank: Dictionary) -> int:
	var count := 0
	for entry in _entries(bank):
		if not bool(entry.get("used", false)):
			count += 1
	return count


static func fallback_use_count(bank: Dictionary) -> int:
	return int(bank.get("fallback_uses", 0))


static func generated_replacement_count(bank: Dictionary) -> int:
	return int(bank.get("generated_replacements", 0))


static func consume(bank: Dictionary, preferred_kind: String = "") -> Dictionary:
	var next_bank := bank.duplicate(true)
	var entries := _entries(next_bank)
	var index := _first_available_index(entries, preferred_kind.strip_edges())
	if index < 0:
		return {
			"ok": false,
			"bank": next_bank,
			"line": {},
			"status": "fallback_bank_empty",
		}
	var entry: Dictionary = entries[index]
	entry["used"] = true
	entry["used_at_unix"] = int(Time.get_unix_time_from_system())
	entry["use_count"] = int(entry.get("use_count", 0)) + 1
	entries[index] = entry
	next_bank["entries"] = entries
	if str(entry.get("source", "")) == "fallback":
		next_bank["fallback_uses"] = int(next_bank.get("fallback_uses", 0)) + 1
	return {
		"ok": true,
		"bank": next_bank,
		"line": entry.duplicate(true),
	}


static func replace_used_with_generated(
	bank: Dictionary,
	generated_lines: Array,
	source_id: String = "llm"
) -> Dictionary:
	var next_bank := bank.duplicate(true)
	var entries := _entries(next_bank)
	var target_size: int = max(1, int(next_bank.get("target_size", DEFAULT_TARGET_SIZE)))
	var replacements := 0
	var seen := _text_seen(entries)
	var used_indexes: Array[int] = []
	for i in range(entries.size()):
		if bool(entries[i].get("used", false)):
			used_indexes.append(i)
	var generated_index := 0
	for raw_line in generated_lines:
		var text := str(raw_line).strip_edges()
		if text.is_empty() or seen.has(text):
			continue
		seen[text] = true
		var clean_source_id := source_id.strip_edges()
		if clean_source_id.is_empty():
			clean_source_id = "llm"
		var next_entry := _entry(
			str(next_bank.get("speaker_key", "")),
			str(next_bank.get("line_kind", "")),
			text,
			clean_source_id,
			entries.size() + generated_index
		)
		next_entry["is_fallback"] = false
		if not used_indexes.is_empty():
			var replace_index: int = used_indexes.pop_front()
			next_entry["slot_replaced"] = str(entries[replace_index].get("line_id", ""))
			entries[replace_index] = next_entry
		elif entries.size() < target_size:
			entries.append(next_entry)
		else:
			continue
		replacements += 1
		generated_index += 1
	next_bank["entries"] = entries
	next_bank["generated_replacements"] = int(
		next_bank.get("generated_replacements", 0)
	) + replacements
	return {
		"ok": true,
		"bank": next_bank,
		"replacements": replacements,
	}


static func _entry(
	speaker_key: String,
	line_kind: String,
	text: String,
	source: String,
	index: int
) -> Dictionary:
	var clean_source: String = source.strip_edges()
	if clean_source.is_empty():
		clean_source = "fallback"
	return {
		"line_id": "%s.%s.%03d.%s" % [
			speaker_key.strip_edges(),
			line_kind.strip_edges(),
			max(0, index),
			text.sha256_text().substr(0, 8),
		],
		"speaker_key": speaker_key.strip_edges(),
		"kind": line_kind.strip_edges(),
		"text": text.strip_edges(),
		"text_fingerprint": text.sha256_text(),
		"source": clean_source,
		"is_fallback": clean_source == "fallback",
		"used": false,
		"use_count": 0,
	}


static func _entries(bank: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_entries: Array = bank.get("entries", []) \
		if bank.get("entries", []) is Array else []
	for raw_entry in raw_entries:
		if raw_entry is Dictionary:
			result.append((raw_entry as Dictionary).duplicate(true))
	return result


static func _first_available_index(entries: Array[Dictionary], preferred_kind: String) -> int:
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		if bool(entry.get("used", false)):
			continue
		if not preferred_kind.is_empty() and str(entry.get("kind", "")) != preferred_kind:
			continue
		return i
	if preferred_kind.is_empty():
		return -1
	for i in range(entries.size()):
		if not bool(entries[i].get("used", false)):
			return i
	return -1


static func _text_seen(entries: Array[Dictionary]) -> Dictionary:
	var seen: Dictionary = {}
	for entry in entries:
		var text := str(entry.get("text", "")).strip_edges()
		if not text.is_empty():
			seen[text] = true
	return seen
