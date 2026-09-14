extends RefCounted

## The campaign direction proposal contract (package 5).
##
## The code supplies a private packet of VERIFIED collection opportunities; the
## writer chooses among them and says why. This module is the gate between those
## two halves, and it is deliberately suspicious of its input: structural
## validity of an ID is not evidence that the claim built on it is true.
##
## What the writer may do: select 1-3 of the supplied collection IDs, cite
## premise facts that were supplied, and declare links that a real dependency
## already supports. What it may not do: invent an ID, invent a fact, invent a
## dependency, promise an effect the game cannot record, or form a cycle.
##
## 1-3 is a CAP, not a quota. A one-collection campaign is a valid proposal.

const Validation := preload("res://scripts/domain/ValidationResult.gd")
const Resolution := preload("res://scripts/story/CampaignResolutionCompiler.gd")
const Outcome := preload("res://scripts/domain/MissionOutcome.gd")

const SCHEMA_VERSION := 1
const MAX_SELECTED := 3
const MAX_PACKET_CANDIDATES := 8
const MAX_DIRECTION_CHARS := 600


## The packet sent to the writer. PRIVATE fields never enter it: no hidden site
## truth, no fixed-cast mystery, no secret. The caller must have already
## filtered unsupported and unreachable candidates.
## `prerequisites` are CODE-DERIVED dependency edges: entries of
## {from_collection_id, to_collection_id, dependency_fact_id} where the item or
## evidence collected by the first is genuinely required by the second. Supply
## none and the writer may declare no links at all -- which is correct, because
## a dependency the code cannot point at is a dependency nobody can verify.
static func build_packet(campaign_id: String, opportunities: Array, premise_facts: Array,
		relationships: Array, prerequisites: Array = []) -> Dictionary:
	var candidates: Array = []
	for raw: Variant in opportunities:
		if candidates.size() >= MAX_PACKET_CANDIDATES:
			break
		if not raw is Dictionary:
			continue
		var opportunity: Dictionary = raw
		var contract: Variant = opportunity.get("contract", {})
		if not contract is Dictionary:
			continue
		var bound: Dictionary = contract
		# The PUBLIC cause text this faction already posts on its board. Without
		# it the writer has only opaque ids to work from, and a live run showed
		# exactly what that produces: two structurally different campaigns
		# described in near-identical generic sentences.
		var raw_agenda: Variant = opportunity.get("agenda", {})
		var agenda: Dictionary = raw_agenda if raw_agenda is Dictionary else {}
		var raw_desire: Variant = agenda.get("desire", {})
		var desire: Dictionary = raw_desire if raw_desire is Dictionary else {}
		candidates.append({
			"faction_name": str(agenda.get("faction_name", opportunity.get("faction_name", ""))),
			"goal": str(desire.get("goal", "")),
			"reason": str(desire.get("need_reason", "")),
			"obstacle": str(desire.get("obstacle", "")),
			"triggering_event": str(desire.get("triggering_event", "")),
			"collection_id": str(bound.get("id", "")),
			"faction_id": str(bound.get("faction_id", "")),
			# Code-side binding, not writer-facing. `writer_view()` strips it.
			"desire_id": str(bound.get("desire_id", "")),
			"system_id": str(bound.get("system_id", "")),
			"need": str(opportunity.get("need", "")),
			"item": str(bound.get("item_id_or_special_name", "")),
			"source_station_id": str(bound.get("source_station_id", "")),
			"destination_station_id": str(bound.get("destination_station_id", "")),
			"recipient_id": str(bound.get("recipient_id", "")),
			"completion_kind": str(bound.get("completion_kind", "")),
			"action": str(bound.get("action", "")),
		})
	var facts: Array = []
	for fact: Variant in premise_facts:
		var fact_id := str(fact).strip_edges()
		if not fact_id.is_empty() and fact_id not in facts:
			facts.append(fact_id)
	var supplied_ids: Dictionary = {}
	for candidate: Dictionary in candidates:
		supplied_ids[str(candidate["collection_id"])] = true
	var edges: Array = []
	for raw: Variant in prerequisites:
		if not raw is Dictionary:
			continue
		var edge: Dictionary = raw
		var from_id := str(edge.get("from_collection_id", ""))
		var to_id := str(edge.get("to_collection_id", ""))
		var fact_id := str(edge.get("dependency_fact_id", ""))
		# A prerequisite is only meaningful between two supplied jobs, and only
		# when it cites a supplied fact.
		if not supplied_ids.has(from_id) or not supplied_ids.has(to_id) or from_id == to_id:
			continue
		if fact_id.is_empty() or fact_id not in facts:
			continue
		edges.append({"from_collection_id": from_id, "to_collection_id": to_id,
			"dependency_fact_id": fact_id})
	return {"campaign_id": campaign_id, "candidates": candidates,
		"premise_fact_ids": facts, "relationships": relationships.duplicate(),
		"prerequisites": edges}


## The redacted packet that actually goes to the model. Internal binding IDs a
## writer has no use for are stripped; hidden site truth and fixed-cast mysteries
## were never in the packet to begin with.
static func writer_view(packet: Dictionary) -> Dictionary:
	var view := packet.duplicate(true)
	var candidates: Array = []
	for raw: Variant in (view.get("candidates", []) as Array if view.get("candidates", []) is Array else []):
		if not raw is Dictionary:
			continue
		var candidate: Dictionary = (raw as Dictionary).duplicate(true)
		candidate.erase("desire_id")
		candidates.append(candidate)
	view["candidates"] = candidates
	return view


## Validate one director proposal against the packet it was given.
##
## Returns {ok, proposal} or {ok: false, reason}. Every refusal names one thing
## so a repair attempt has something to act on.
static func validate_proposal(proposal: Variant, packet: Dictionary) -> Dictionary:
	if not proposal is Dictionary:
		return _reject("proposal_not_an_object")
	var value: Dictionary = proposal
	if int(value.get("version", 0)) != SCHEMA_VERSION:
		return _reject("unsupported_direction_version")
	for field in ["premise_fact_ids", "selected_collection_ids", "links"]:
		if not value.get(field) is Array:
			return _reject("invalid_direction_list:%s" % field)
	var direction := str(value.get("public_direction", "")).strip_edges()
	if direction.is_empty():
		return _reject("empty_public_direction")
	if direction.length() > MAX_DIRECTION_CHARS:
		return _reject("public_direction_too_long")
	var leaked := _leaked_identifier(direction)
	if not leaked.is_empty():
		# Player-facing text, so an internal identifier in it is a defect the
		# code can catch. A live run put "station.hub" in front of the player.
		return _reject("identifier_in_public_direction:%s" % leaked)
	var supplied_facts: Array = packet.get("premise_fact_ids", []) if packet.get("premise_fact_ids", []) is Array else []
	var premise: Array = []
	for raw: Variant in value["premise_fact_ids"]:
		var fact_id := str(raw).strip_edges()
		if fact_id.is_empty():
			return _reject("empty_premise_fact_reference")
		if fact_id not in supplied_facts:
			# A fact that was not supplied is invented, whatever it looks like.
			return _reject("unknown_premise_fact:%s" % fact_id)
		if fact_id not in premise:
			premise.append(fact_id)
	if premise.is_empty():
		return _reject("no_premise_reference")
	var supplied: Dictionary = {}
	for raw: Variant in (packet.get("candidates", []) as Array if packet.get("candidates", []) is Array else []):
		if raw is Dictionary:
			supplied[str((raw as Dictionary).get("collection_id", ""))] = raw
	var selected: Array = []
	for raw: Variant in value["selected_collection_ids"]:
		var collection_id := str(raw).strip_edges()
		if collection_id.is_empty() or not supplied.has(collection_id):
			return _reject("unknown_collection_selection:%s" % collection_id)
		if collection_id in selected:
			return _reject("duplicate_collection_selection:%s" % collection_id)
		selected.append(collection_id)
	if selected.is_empty():
		return _reject("no_collection_selected")
	if selected.size() > MAX_SELECTED:
		return _reject("too_many_collections_selected")
	var prerequisites: Array = packet.get("prerequisites", []) if packet.get("prerequisites", []) is Array else []
	var links := _validated_links(value["links"], selected, prerequisites)
	if not bool(links.get("ok", false)):
		return links
	return {"ok": true, "proposal": {
		"version": SCHEMA_VERSION,
		"premise_fact_ids": premise,
		"selected_collection_ids": selected,
		"links": links["links"],
		"public_direction": direction,
	}}


## Internal ID prefixes that must never reach the player. Checked on the one
## string in this schema that is shown to them.
const IDENTIFIER_PREFIXES := ["station.", "npc.", "collection.", "fact.", "faction.",
	"desire.", "cause.", "mission.", "system.", "publication.", "resolution."]


static func _leaked_identifier(text: String) -> String:
	var lowered := text.to_lower()
	for prefix: String in IDENTIFIER_PREFIXES:
		var at := lowered.find(prefix)
		while at != -1:
			# A sentence ending in "the station." is prose; an identifier has a
			# word character straight after the dot.
			var next_index := at + prefix.length()
			if next_index < lowered.length():
				var following := lowered[next_index]
				if following.is_valid_identifier() or following in "0123456789_":
					return text.substr(at, mini(40, text.length() - at))
			at = lowered.find(prefix, at + 1)
	return ""


## A link says "the item collected by A is required by B".
##
## It is accepted ONLY when the packet supplied that exact prerequisite edge.
## Checking merely that the cited fact exists is not enough: a live run showed
## the writer declaring a dependency in every single proposal, reusing one
## generic backlog fact, for jobs that have no prerequisite relationship at all.
## A structurally valid citation is not evidence of a real dependency, and the
## code is the only party that can know whether one exists.
static func _validated_links(raw_links: Array, selected: Array, prerequisites: Array) -> Dictionary:
	var allowed: Dictionary = {}
	for raw: Variant in prerequisites:
		if raw is Dictionary:
			var edge: Dictionary = raw
			allowed["%s>%s>%s" % [str(edge.get("from_collection_id", "")),
				str(edge.get("to_collection_id", "")),
				str(edge.get("dependency_fact_id", ""))]] = true
	var links: Array = []
	var edges: Dictionary = {}
	for raw: Variant in raw_links:
		if not raw is Dictionary:
			return _reject("invalid_link_entry")
		var link: Dictionary = raw
		var from_id := str(link.get("from_collection_id", "")).strip_edges()
		var to_id := str(link.get("to_collection_id", "")).strip_edges()
		var fact_id := str(link.get("dependency_fact_id", "")).strip_edges()
		if from_id not in selected or to_id not in selected:
			return _reject("link_references_unselected_collection")
		if from_id == to_id:
			return _reject("self_link")
		if not allowed.has("%s>%s>%s" % [from_id, to_id, fact_id]):
			# The code never established this dependency, so nobody can verify it.
			return _reject("unsupported_link_dependency")
		var key := "%s>%s" % [from_id, to_id]
		if edges.has(key):
			return _reject("duplicate_link")
		edges[key] = true
		links.append({"from_collection_id": from_id, "to_collection_id": to_id,
			"dependency_fact_id": fact_id})
	if _has_cycle(links, selected):
		return _reject("cyclic_links")
	return {"ok": true, "links": links}


static func _has_cycle(links: Array, selected: Array) -> bool:
	var outgoing: Dictionary = {}
	for id: Variant in selected:
		outgoing[str(id)] = []
	for link: Dictionary in links:
		(outgoing[str(link["from_collection_id"])] as Array).append(str(link["to_collection_id"]))
	var visiting: Dictionary = {}
	var done: Dictionary = {}
	for id: Variant in selected:
		if _visit(str(id), outgoing, visiting, done):
			return true
	return false


static func _visit(node: String, outgoing: Dictionary, visiting: Dictionary, done: Dictionary) -> bool:
	if done.has(node):
		return false
	if visiting.has(node):
		return true
	visiting[node] = true
	for next: Variant in (outgoing.get(node, []) as Array):
		if _visit(str(next), outgoing, visiting, done):
			return true
	visiting.erase(node)
	done[node] = true
	return false


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## Compile an ACCEPTED proposal into a frozen v2 resolution plan.
##
## One success alternative ANDs the selected collections. The public goal is the
## completion of those specific collections and nothing more: no unimplemented
## legal or political outcome is promised, and the factions' broader unresolved
## goals are carried in the summary rather than claimed as achieved.
##
## No partial or failure alternative is manufactured. No implemented loss effect
## currently justifies one, and one supported success is an acceptable plan.
static func compile_plan(proposal: Dictionary, packet: Dictionary, plan_id: String) -> Dictionary:
	var supplied: Dictionary = {}
	for raw: Variant in (packet.get("candidates", []) as Array if packet.get("candidates", []) is Array else []):
		if raw is Dictionary:
			supplied[str((raw as Dictionary).get("collection_id", ""))] = raw
	var interests: Array = []
	var predicates: Array = []
	for collection_id: Variant in (proposal.get("selected_collection_ids", []) as Array):
		var candidate: Dictionary = supplied.get(str(collection_id), {})
		if candidate.is_empty():
			return {"ok": false, "reason": "unknown_collection_selection:%s" % str(collection_id)}
		interests.append({
			"id": "interest.%s" % str(collection_id).replace("collection.", ""),
			"collection_id": str(collection_id),
			"system_id": str(candidate.get("system_id", "")),
			"faction_id": str(candidate.get("faction_id", "")),
			"desire_id": str(candidate.get("desire_id", candidate.get("collection_id", ""))),
			"station_id": str(candidate.get("destination_station_id", "")),
			"recipient_id": str(candidate.get("recipient_id", "")),
			"completion_kind": str(candidate.get("completion_kind", "")),
			"supported_effect_ids": [_effect_for_completion(str(candidate.get("completion_kind", "")))],
		})
		predicates.append({"kind": Resolution.KIND_COLLECTION, "collection_id": str(collection_id)})
	var plan := {
		"version": Resolution.PLAN_VERSION_V2,
		"id": plan_id,
		"status": Resolution.STATUS_PENDING,
		"premise_fact_ids": (proposal.get("premise_fact_ids", []) as Array).duplicate(),
		"interests": interests,
		"alternatives": [{
			"id": "alt.success",
			"result": Resolution.RESULT_SUCCESS,
			"all_of": predicates,
			"public_fact_ids": (proposal.get("premise_fact_ids", []) as Array).duplicate(),
		}],
		"public_direction": str(proposal.get("public_direction", "")),
		"links": (proposal.get("links", []) as Array).duplicate(),
	}
	var structural := Resolution.validate(plan)
	if not structural.is_valid():
		return {"ok": false, "reason": str(structural.errors[0].get("code", "invalid_resolution_plan"))}
	return {"ok": true, "plan": plan}


static func _effect_for_completion(completion_kind: String) -> String:
	match completion_kind:
		Outcome.EFFECT_ITEM_DELIVERED: return Outcome.EFFECT_ITEM_DELIVERED
		Outcome.EFFECT_VERIFIED_SURVEY: return Outcome.EFFECT_VERIFIED_SURVEY
		Outcome.EFFECT_RECORDER_PRESERVED: return Outcome.EFFECT_RECORDER_PRESERVED
	return ""


## ---------------------------------------------------------------------------
## The writer request.
##
## The prompt is assembled here rather than in LLMInterface so it can be tested
## without a network, and so the rule "only supplied IDs and facts exist" is
## stated in the same file that enforces it.
## ---------------------------------------------------------------------------

## Ollama is called with format:"json". A prompt line shaped like `Label:` turns
## into a JSON key in that mode, so the demonstration below is written as prose
## and the schema is described in words, never as a labelled block.
static func build_prompt(writer_view: Dictionary, correction_note: String = "") -> String:
	var lines: Array = []
	lines.append("You are the campaign director for a space trading and combat game.")
	lines.append("")
	lines.append("Below is every job the world can actually support right now. You may")
	lines.append("only use these. Inventing an id, a fact, a location or a person is a")
	lines.append("failure, not creativity.")
	lines.append("")
	lines.append("Available jobs:")
	for raw: Variant in (writer_view.get("candidates", []) as Array if writer_view.get("candidates", []) is Array else []):
		if not raw is Dictionary:
			continue
		var candidate: Dictionary = raw
		# The id is the FIRST token on the line and nothing precedes it. An
		# earlier version wrote "- id <id>." and the writer dutifully copied
		# "id <id>" as the identifier, which failed every time.
		var who := str(candidate.get("faction_name", ""))
		if who.is_empty():
			who = str(candidate.get("faction_id", ""))
		var detail := "- %s = %s needs %s" % [str(candidate.get("collection_id", "")), who,
			str(candidate.get("need", ""))]
		if not str(candidate.get("goal", "")).is_empty():
			detail += ", to %s" % str(candidate.get("goal", ""))
		detail += "."
		for extra: String in ["reason", "triggering_event", "obstacle"]:
			var text := str(candidate.get(extra, "")).strip_edges()
			if text.is_empty():
				continue
			if extra == "obstacle":
				detail += " It cannot do this itself because %s." % text
			elif extra == "triggering_event":
				detail += " This began with %s." % text
			else:
				detail += " %s" % text
		lines.append(detail)
	lines.append("")
	lines.append("Known public facts you may cite:")
	for fact_id: Variant in (writer_view.get("premise_fact_ids", []) as Array if writer_view.get("premise_fact_ids", []) is Array else []):
		lines.append("- %s" % str(fact_id))
	lines.append("")
	lines.append("A job id is the text before the equals sign, such as")
	lines.append("collection.0123abcd. Copy it exactly. Do not add a prefix, a label or")
	lines.append("the word id.")
	lines.append("")
	lines.append("Choose one to three of those job ids that together make one campaign")
	lines.append("worth doing.")
	lines.append("")
	lines.append("Then write one or two sentences saying WHY this matters to the people")
	lines.append("asking. Use THEIR specific situations, in your own words -- what each")
	lines.append("one is trying to do and what went wrong for them. Do not list the")
	lines.append("cargo and do not restate the tasks; the player can already read those.")
	lines.append("Avoid generic filler about backlogs, pressure or keeping things")
	lines.append("running: say what is actually happening to these particular people.")
	lines.append("")
	lines.append("Write it the way a person would say it out loud. Use no identifiers:")
	lines.append("no station.something, no npc.something, no collection.something, no")
	lines.append("fact.something. Name places and people in plain words or not at all.")
	lines.append("")
	var prerequisites: Array = writer_view.get("prerequisites", []) 		if writer_view.get("prerequisites", []) is Array else []
	if prerequisites.is_empty():
		# Saying this plainly matters: without it the writer declared a
		# dependency in every proposal, for jobs that have none.
		lines.append("These jobs have no known dependencies on each other. Leave the")
		lines.append("links list empty. Do not invent a dependency; one that is not")
		lines.append("listed here does not exist.")
	else:
		lines.append("These are the only dependencies that exist. You may declare any of")
		lines.append("them, exactly as written, and nothing else:")
		for raw: Variant in prerequisites:
			if not raw is Dictionary:
				continue
			var edge: Dictionary = raw
			lines.append("- %s must be collected before %s, because of %s." % [
				str(edge.get("from_collection_id", "")), str(edge.get("to_collection_id", "")),
				str(edge.get("dependency_fact_id", ""))])
		lines.append("Declare only the ones that apply to the jobs you chose. Leave the")
		lines.append("links list empty if none do.")
	lines.append("")
	lines.append("Do not promise that the campaign clears a name, transfers a lease,")
	lines.append("settles a debt, wins a contract or reopens a route. The game records")
	lines.append("that things were delivered. It records nothing else.")
	lines.append("")
	lines.append(_schema_description())
	if not correction_note.strip_edges().is_empty():
		lines.append("")
		lines.append("Your previous answer was rejected because %s. Fix exactly that."
			% correction_note.strip_edges())
	return "
".join(lines)


## Described in prose for the same reason: under format:"json" a labelled block
## in the prompt becomes a key in the answer.
static func _schema_description() -> String:
	var parts: Array = []
	parts.append("Reply with one JSON object and nothing else. It has a version field")
	parts.append("set to the number 1, a premise_fact_ids array holding the ids of the")
	parts.append("facts you cited, a selected_collection_ids array holding one to three")
	parts.append("of the job ids above, a links array, and a public_direction string")
	parts.append("holding your sentences. Each entry in links is an object with")
	parts.append("from_collection_id, to_collection_id and dependency_fact_id. Leave")
	parts.append("links empty when no listed fact establishes a dependency.")
	return " ".join(parts)


## Parse one model reply into a proposal. Returns {ok, proposal} or
## {ok: false, reason}. Shape only: `validate_proposal` decides whether the
## claims it makes are supported.
static func parse_response(inner_text: String) -> Dictionary:
	var text := inner_text.strip_edges()
	if text.is_empty():
		return _reject("empty_response")
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _reject("response_not_an_object")
	var value: Dictionary = parsed
	# Small models sometimes wrap the answer in a single key. Unwrap exactly one
	# level, and only when the inner value is itself the object we asked for.
	if not value.has("selected_collection_ids") and value.size() == 1:
		var only: Variant = value.values()[0]
		if only is Dictionary and (only as Dictionary).has("selected_collection_ids"):
			value = only
	if not value.has("version"):
		# The schema pins version 1; a reply that omits it is still checked
		# against everything else rather than rejected on a formality.
		value["version"] = SCHEMA_VERSION
	return {"ok": true, "proposal": value}
