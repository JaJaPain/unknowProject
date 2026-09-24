class_name Showrunner
extends RefCounted

## The Showrunner pass (plan Section 3.7): a larger model reads the campaign's
## evidence and explains how it connects.
##
## Code proposes, the model chooses and explains, code checks:
##   1. HiddenHand.proposal() gives the top 3 candidates.
##   2. The model picks one BY ID and writes the hidden truth, one sentence per
##      thread it can explain, and the next three beats. Schema-constrained JSON.
##   3. parse_response() checks every id, the thread coverage, lengths and the
##      reserved topics; any failure means HiddenHand.lock_by_code() instead.
##
## Nothing about the fixed cast is ever in this prompt.

const HandType := preload("res://scripts/story/premise/HiddenHand.gd")
const CastingType := preload("res://scripts/story/premise/PremiseCasting.gd")
const ReservedType := preload("res://scripts/story/ReservedTopics.gd")

const MODEL := "qwen3:8b"
# The prompt is ~700 tokens and the answer ~300; 4k keeps the whole model on a
# small GPU (16k spilled to CPU on a 12GB card with other work loaded: ~8 tok/s).
const NUM_CTX := 4096
const TRUTH_MIN := 60
const TRUTH_MAX := 600

const SCHEMA := {
	"type": "object",
	"properties": {
		"candidate_id": {"type": "string"},
		"truth": {"type": "string"},
		"links": {"type": "array", "items": {"type": "object", "properties": {
			"thread_id": {"type": "string"}, "explanation": {"type": "string"}},
			"required": ["thread_id", "explanation"]}},
		"next_beats": {"type": "array", "items": {"type": "string"}},
	},
	"required": ["candidate_id", "truth", "links", "next_beats"],
}


## Builds the Ollama /api/generate body. `names` = {system_id: display} for text.
static func build_request(state: Dictionary, library, names: Dictionary = {}) -> Dictionary:
	var story := HandType.main_story(state)
	var candidates := HandType.proposal(state)
	var lines: PackedStringArray = []
	lines.append("You are the showrunner of a grounded, working-class space story. A hidden person has been quietly shaping events.")
	lines.append("What is known about them: their motive is %s; their method is %s; their goal is to %s." % [
		str(story.get("motive", "")).replace("_", " "), str(story.get("method", "")).replace("_", " "), str(story.get("goal_text", ""))])
	lines.append("")
	lines.append("CANDIDATES (choose exactly one by id; prefer whoever the evidence points to most, unless another choice explains the details better):")
	for c in candidates:
		var appearances: PackedStringArray = []
		for arc_id in c["arcs"]:
			var a: Dictionary = state["arcs"].get(arc_id, {})
			var card: Dictionary = library.get_card(str(a.get("card_id", "")))
			var world := {"system_display": str(names.get(str(a.get("system_id", "")), "a nearby system"))}
			appearances.append(CastingType.fill_text(str(card.get("logline", "")), a.get("cast", {}), world))
		lines.append("- id: %s | name: %s | stories: %d | details they could explain: %d | appeared in: %s" % [
			c["entity_id"], c["display_name"], (c["arcs"] as Array).size(),
			(c["traces"] as Array).size() + (c["decoys"] as Array).size(), " / ".join(appearances)])
	lines.append("")
	lines.append("ODD DETAILS THE PILOT NOTICED (explain at least three, by thread_id):")
	for t in HandType.seen_threads(state):
		var a: Dictionary = state["arcs"].get(str(t["arc_id"]), {})
		var world := {"system_display": str(names.get(str(a.get("system_id", "")), "a nearby system"))}
		var pin := " (the pilot thinks this matters)" if bool(t.get("pinned", false)) else ""
		lines.append("- %s: %s%s" % [t["id"], CastingType.fill_text(str(t["detail"]), a.get("cast", {}), world), pin])
	lines.append("")
	var seen_ids := HandType.seen_threads(state).map(func(t): return str(t["id"]))
	lines.append("Write: the hidden truth in 2-3 plain sentences naming the person you chose; then a link for AT LEAST THREE DIFFERENT details, each thread_id used once (valid ids: %s), with one short sentence on how it connects; then three short next story beats that bring the truth to light." % ", ".join(seen_ids))
	lines.append("Rules: use only the people and details above; invent no new names; no galaxy-scale stakes; keep it grounded and specific.")
	return {
		"model": MODEL,
		"prompt": "\n".join(lines),
		"format": SCHEMA,
		"stream": false,
		"think": false,
		"keep_alive": 0,
		"options": {"num_ctx": NUM_CTX, "temperature": 0.7},
	}


## Parses and checks the model's JSON. Returns {ok, reason, choice} where
## choice is ready for HiddenHand.lock(): {entity_id, truth, links, next_beats, source}.
static func parse_response(response_text: String, state: Dictionary) -> Dictionary:
	var json := JSON.new()
	if json.parse(response_text) != OK or not json.data is Dictionary:
		return {"ok": false, "reason": "not_json", "choice": {}}
	var data: Dictionary = json.data
	var chosen := _match_candidate(str(data.get("candidate_id", "")), HandType.proposal(state))
	if chosen.is_empty():
		return {"ok": false, "reason": "unknown_candidate", "choice": {}}
	var truth := str(data.get("truth", "")).strip_edges()
	if truth.length() < TRUTH_MIN or truth.length() > TRUTH_MAX:
		return {"ok": false, "reason": "truth_length", "choice": {}}
	var seen_ids := HandType.seen_threads(state).map(func(t): return str(t["id"]))
	var links := {}
	for link in data.get("links", []):
		if link is Dictionary and str(link.get("thread_id", "")) in seen_ids:
			var text := str(link.get("explanation", "")).strip_edges()
			if not text.is_empty():
				links[str(link["thread_id"])] = text
	if links.size() < HandType.LOCK_MIN_TRACES:
		return {"ok": false, "reason": "explains_too_little", "choice": {}}
	var beats: Array = []
	for b in data.get("next_beats", []):
		if not str(b).strip_edges().is_empty():
			beats.append(str(b).strip_edges())
	var all_text := truth + " " + " ".join(links.values()) + " " + " ".join(beats)
	if not ReservedType.is_clean(all_text):
		return {"ok": false, "reason": "reserved_topic", "choice": {}}
	return {"ok": true, "reason": "", "choice": {"entity_id": chosen, "truth": truth, "links": links,
		"next_beats": beats.slice(0, 3), "source": "showrunner"}}


## Small models copy the prompt's "id | name" layout, or give the name alone.
## Accept a proposed id found anywhere in the answer, or an exact display name;
## anything else is not a candidate.
static func _match_candidate(answer: String, proposal: Array) -> String:
	var clean := answer.strip_edges()
	for c in proposal:
		if clean == str(c["entity_id"]):
			return str(c["entity_id"])
	for part in clean.split("|"):
		for c in proposal:
			if part.strip_edges() == str(c["entity_id"]) or part.strip_edges().to_lower() == str(c["display_name"]).to_lower():
				return str(c["entity_id"])
	return ""


## Extracts the model's text from an Ollama /api/generate reply body.
static func response_text(body: String) -> String:
	var json := JSON.new()
	if json.parse(body) != OK or not json.data is Dictionary:
		return ""
	return str((json.data as Dictionary).get("response", ""))
