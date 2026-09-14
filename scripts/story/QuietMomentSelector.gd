class_name QuietMomentSelector
extends RefCounted

# Runtime gating for quiet-moment lines: recency tracking, retry, silence.
#
# Recency is tracked PER CHARACTER, not per beat. A character repeating
# herself across two different beats is just as obvious to the player as
# repeating within one, and single-beat tracking misses it entirely.
#
# This state MUST persist in the save. Without it the freshness guarantee
# resets on every reload, which is the whole point of the feature.
#
# Measured with these windows: 0 duplicates over a 30-line playthrough,
# 0-12% silence, ~1.4 model calls per moment.

const Checks := preload("res://scripts/story/QuietMomentChecks.gd")

const OPENER_WINDOW := 6
const LINE_WINDOW := 30
const CLOSER_WINDOW := 6

# Closing formulas that collapsed a run at some point during research.
const CLOSERS := {
	"lets_not_again": ["let's not do this again", "lets not do that again"],
	"dont_expect": ["don't expect it", "don't expect that", "don't expect this"],
	"no_habit": ["make a habit", "make these a habit"],
	"lets_find": ["let's find something", "let's find work"],
	"no_complaints": ["no complaints"],
	"id_rather": ["i'd rather"],
}

var recent_openers: Array[String] = []
var recent_lines: Array[String] = []
var recent_closers: Array[String] = []


static func closer_tag(line: String) -> String:
	var low := Checks.normalize(line).to_lower()
	for tag in CLOSERS:
		for phrase in CLOSERS[tag]:
			if low.contains(str(phrase)):
				return str(tag)
	return ""


static func opener_of(line: String) -> String:
	var w := Checks.words_of(line)
	if w.size() < 2:
		return " ".join(w)
	return "%s %s" % [w[0], w[1]]


# Why this candidate cannot be spoken. Empty means serve it.
func reasons(line: String, context: Dictionary) -> Array[String]:
	var errors := Checks.screen(line, context)
	if not errors.is_empty():
		return errors

	var opener := opener_of(line)
	if recent_openers.has(opener):
		errors.append("opener_repeat")
	for previous in recent_lines:
		if Checks.shares_run(line, previous, 5):
			errors.append("phrase_repeat")
			break
	var tag := closer_tag(line)
	if not tag.is_empty() and recent_closers.has(tag):
		errors.append("closer_repeat")
	return errors


func accept(line: String) -> void:
	_push(recent_openers, opener_of(line), OPENER_WINDOW)
	_push(recent_lines, line, LINE_WINDOW)
	var tag := closer_tag(line)
	if not tag.is_empty():
		_push(recent_closers, tag, CLOSER_WINDOW)


# The last accepted line was rewritten after acceptance (the anatomy
# correction appends to it), so recency must track what was actually spoken.
func replace_last_line(line: String) -> void:
	if recent_lines.is_empty():
		return
	recent_lines[recent_lines.size() - 1] = line


func _push(target: Array[String], value: String, window: int) -> void:
	target.append(value)
	while target.size() > window:
		target.remove_at(0)


# --- persistence -----------------------------------------------------------

func to_save_dict() -> Dictionary:
	return {
		"recent_openers": recent_openers.duplicate(),
		"recent_lines": recent_lines.duplicate(),
		"recent_closers": recent_closers.duplicate(),
	}


func load_from_dict(data: Dictionary) -> void:
	recent_openers = _string_array(data.get("recent_openers", []))
	recent_lines = _string_array(data.get("recent_lines", []))
	recent_closers = _string_array(data.get("recent_closers", []))


func clear() -> void:
	recent_openers.clear()
	recent_lines.clear()
	recent_closers.clear()


static func _string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for entry in raw:
			out.append(str(entry))
	return out
