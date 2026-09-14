extends SceneTree

## Package 5: the writer chooses among VERIFIED opportunities and says why.
## Every case here asks the same question: is a structurally valid claim being
## mistaken for a true one?

const Direction := preload("res://scripts/story/CampaignDirectionContract.gd")
const Resolution := preload("res://scripts/story/CampaignResolutionCompiler.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_test_packet()
	_test_accepted_proposal()
	_test_rejections()
	_test_links()
	_test_compiled_plan()
	_test_prompt()
	_test_response_parsing()
	if failures.is_empty():
		print("[PASS] Campaign direction: private packet, bounded selection, supported links, a frozen v2 plan, the writer prompt and reply parsing")
		quit(0)
		return
	for message in failures: push_error("[FAIL] " + message)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _opportunity(suffix: String) -> Dictionary:
	return {"need": "sealed manifests from the last shipment", "faction_name": "Local Records",
		"contract": {"version": 1, "id": "collection.%s" % suffix, "campaign_id": "campaign.test",
			"system_id": "system.local", "faction_id": "faction.%s" % suffix,
			"desire_id": "desire.%s" % suffix, "cause_id": "cause.%s" % suffix,
			"need_binding_id": "carrier_cancelled", "item_id_or_special_name": "Sealed Manifest Bundle",
			"quantity": 1, "source_station_id": "station.origin",
			"destination_station_id": "station.local", "recipient_id": "npc.local.clerk",
			"action": "courier", "completion_kind": "item_delivered"}}

func _packet(count: int = 3) -> Dictionary:
	var opportunities: Array = []
	for index in range(count):
		opportunities.append(_opportunity("c%d" % index))
	return Direction.build_packet("campaign.test", opportunities,
		["fact.local.backlog", "fact.local.records", "fact.local.dispute"], [])


## The same packet plus the ONE prerequisite the code actually established.
func _packet_with_prerequisite(count: int = 3) -> Dictionary:
	var opportunities: Array = []
	for index in range(count):
		opportunities.append(_opportunity("c%d" % index))
	return Direction.build_packet("campaign.test", opportunities,
		["fact.local.backlog", "fact.local.records", "fact.local.dispute"], [],
		[{"from_collection_id": "collection.c0", "to_collection_id": "collection.c1",
			"dependency_fact_id": "fact.local.records"}])

func _proposal(overrides: Dictionary = {}) -> Dictionary:
	var value := {"version": 1, "premise_fact_ids": ["fact.local.backlog"],
		"selected_collection_ids": ["collection.c0", "collection.c1"],
		"links": [], "public_direction": "Recover the shipment records the registry never received."}
	for key in overrides: value[key] = overrides[key]
	return value


## The packet is capped, and the view the writer sees carries no internal
## binding IDs.
func _test_packet() -> void:
	var opportunities: Array = []
	for index in range(12):
		opportunities.append(_opportunity("c%d" % index))
	var packet := Direction.build_packet("campaign.test", opportunities, ["fact.a", "fact.a"], [])
	_expect((packet["candidates"] as Array).size() == Direction.MAX_PACKET_CANDIDATES,
		"The director packet was not capped at %d candidates." % Direction.MAX_PACKET_CANDIDATES)
	_expect((packet["premise_fact_ids"] as Array).size() == 1,
		"The packet repeated a premise fact.")
	var candidate: Dictionary = packet["candidates"][0]
	_expect(candidate.has("desire_id"), "The code-side packet lost its desire binding.")
	var view := Direction.writer_view(packet)
	_expect(not (view["candidates"][0] as Dictionary).has("desire_id"),
		"An internal binding ID was sent to the writer.")
	for field: String in ["collection_id", "system_id", "destination_station_id",
			"recipient_id", "completion_kind"]:
		_expect((view["candidates"][0] as Dictionary).has(field),
			"The writer view dropped a field it needs: %s" % field)


func _test_accepted_proposal() -> void:
	var packet := _packet()
	var accepted := Direction.validate_proposal(_proposal(), packet)
	if not bool(accepted.get("ok", false)):
		_expect(false, "A well-formed proposal was refused: %s" % str(accepted.get("reason", "")))
		return
	var proposal: Dictionary = accepted["proposal"]
	_expect((proposal["selected_collection_ids"] as Array).size() == 2,
		"The accepted proposal lost a selection.")
	# One collection is a valid campaign: the cap is not a quota.
	var single := Direction.validate_proposal(_proposal({"selected_collection_ids": ["collection.c0"]}), packet)
	_expect(bool(single.get("ok", false)),
		"A one-collection campaign was refused: %s" % str(single.get("reason", "")))


## Nothing unsupported gets through: not an invented ID, not an invented fact,
## not an oversized selection, not an empty claim.
func _test_rejections() -> void:
	var packet := _packet()
	var cases := {
		"proposal_not_an_object": "not a dictionary",
		"unsupported_direction_version": _proposal({"version": 2}),
		"empty_public_direction": _proposal({"public_direction": "   "}),
		"no_premise_reference": _proposal({"premise_fact_ids": []}),
		"no_collection_selected": _proposal({"selected_collection_ids": []}),
	}
	for expected: String in cases:
		var result := Direction.validate_proposal(cases[expected], packet)
		_expect(not bool(result.get("ok", true)), "An invalid proposal was accepted: %s" % expected)
		_expect(str(result.get("reason", "")).begins_with(expected),
			"Wrong refusal: expected %s, got %s" % [expected, str(result.get("reason", ""))])
	# Four supplied collections are still too many to select.
	var wide_packet := _packet(4)
	var too_many := Direction.validate_proposal(_proposal({"selected_collection_ids":
		["collection.c0", "collection.c1", "collection.c2", "collection.c3"]}), wide_packet)
	_expect(str(too_many.get("reason", "")) == "too_many_collections_selected",
		"More than %d collections were selected: %s" % [Direction.MAX_SELECTED, str(too_many.get("reason", ""))])
	# An ID that looks right but was never supplied is invented.
	var unknown := Direction.validate_proposal(
		_proposal({"selected_collection_ids": ["collection.nonexistent"]}), packet)
	_expect(str(unknown.get("reason", "")).begins_with("unknown_collection_selection"),
		"A collection ID the packet never supplied was accepted.")
	var invented_fact := Direction.validate_proposal(
		_proposal({"premise_fact_ids": ["fact.that.sounds.real"]}), packet)
	_expect(str(invented_fact.get("reason", "")).begins_with("unknown_premise_fact"),
		"An invented premise fact was accepted.")
	var duplicated := Direction.validate_proposal(
		_proposal({"selected_collection_ids": ["collection.c0", "collection.c0"]}), packet)
	_expect(str(duplicated.get("reason", "")).begins_with("duplicate_collection_selection"),
		"The same collection was selected twice.")
	# A live run put "station.hub" in front of the player. Player-facing text
	# carrying an internal identifier is a defect the code can catch.
	for leak: String in ["Take it to station.hub before the backlog worsens.",
			"The registry at faction.local.records is waiting.",
			"Deliver collection.abc123 to the clerk.",
			"Hand it to npc.hub.contact.0 on arrival."]:
		var leaked := Direction.validate_proposal(_proposal({"public_direction": leak}), packet)
		_expect(str(leaked.get("reason", "")).begins_with("identifier_in_public_direction"),
			"An internal identifier reached player-facing text: %s" % leak)
	# Ordinary prose that merely ends a sentence on one of those words is fine.
	for clean: String in ["The records never reached the station. Get them there.",
			"Two accounts need the same clerk, and neither can spare a hull."]:
		_expect(bool(Direction.validate_proposal(
			_proposal({"public_direction": clean}), packet).get("ok", false)),
			"Ordinary prose was refused as an identifier leak: %s" % clean)
	var long_direction := "x".repeat(Direction.MAX_DIRECTION_CHARS + 1)
	_expect(str(Direction.validate_proposal(
		_proposal({"public_direction": long_direction}), packet).get("reason", "")) == "public_direction_too_long",
		"An unbounded public direction was accepted.")


## A link must be supported by a real dependency, and links must not form a
## cycle. Links are never forced when none exists.
func _test_links() -> void:
	var packet := _packet_with_prerequisite()
	var good := _proposal({"links": [{"from_collection_id": "collection.c0",
		"to_collection_id": "collection.c1", "dependency_fact_id": "fact.local.records"}]})
	var accepted := Direction.validate_proposal(good, packet)
	_expect(bool(accepted.get("ok", false)),
		"A supported link was refused: %s" % str(accepted.get("reason", "")))
	# No links at all is fine.
	_expect(bool(Direction.validate_proposal(_proposal({"links": []}), packet).get("ok", false)),
		"A proposal with no links was refused.")
	# A packet that establishes NO prerequisite accepts NO link, however
	# plausible the citation looks. A live run showed the writer declaring a
	# dependency in every proposal for jobs that have none.
	_expect(str(Direction.validate_proposal(good, _packet()).get("reason", ""))
			== "unsupported_link_dependency",
		"A link was accepted for a dependency the code never established.")
	# The right pair citing the WRONG fact is still not that dependency.
	var wrong_fact := _proposal({"links": [{"from_collection_id": "collection.c0",
		"to_collection_id": "collection.c1", "dependency_fact_id": "fact.local.backlog"}]})
	_expect(str(Direction.validate_proposal(wrong_fact, packet).get("reason", ""))
			== "unsupported_link_dependency",
		"A prerequisite was accepted under a fact that does not establish it.")
	# A real prerequisite does not license its reverse.
	var reversed_link := _proposal({"links": [{"from_collection_id": "collection.c1",
		"to_collection_id": "collection.c0", "dependency_fact_id": "fact.local.records"}]})
	_expect(str(Direction.validate_proposal(reversed_link, packet).get("reason", ""))
			== "unsupported_link_dependency",
		"A prerequisite was accepted in the direction it does not run.")
	var cases := {
		"unsupported_link_dependency": [{"from_collection_id": "collection.c0",
			"to_collection_id": "collection.c1", "dependency_fact_id": "fact.invented"}],
		# duplicate_link and cyclic_links need REAL prerequisites behind them, so
		# the refusal being tested is the shape rule and not the support rule.
		"link_references_unselected_collection": [{"from_collection_id": "collection.c0",
			"to_collection_id": "collection.c2", "dependency_fact_id": "fact.local.records"}],
		"self_link": [{"from_collection_id": "collection.c0",
			"to_collection_id": "collection.c0", "dependency_fact_id": "fact.local.records"}],
		"duplicate_link": [
			{"from_collection_id": "collection.c0", "to_collection_id": "collection.c1",
				"dependency_fact_id": "fact.local.records"},
			{"from_collection_id": "collection.c0", "to_collection_id": "collection.c1",
				"dependency_fact_id": "fact.local.dispute"}],
		"cyclic_links": [
			{"from_collection_id": "collection.c0", "to_collection_id": "collection.c1",
				"dependency_fact_id": "fact.local.records"},
			{"from_collection_id": "collection.c1", "to_collection_id": "collection.c0",
				"dependency_fact_id": "fact.local.dispute"}],
		"invalid_link_entry": ["a string"],
	}
	for expected: String in cases:
		var result := Direction.validate_proposal(_proposal({"links": cases[expected]}), _link_packet(expected))
		_expect(not bool(result.get("ok", true)), "An unsupported link was accepted: %s" % expected)
		_expect(str(result.get("reason", "")) == expected,
			"Wrong link refusal: expected %s, got %s" % [expected, str(result.get("reason", ""))])


## A packet carrying exactly the prerequisites each link case needs, so a shape
## refusal (duplicate, cycle, self-link) is not masked by the support rule.
func _link_packet(case_name: String) -> Dictionary:
	var opportunities: Array = []
	for index in range(3):
		opportunities.append(_opportunity("c%d" % index))
	var facts: Array = ["fact.local.backlog", "fact.local.records", "fact.local.dispute"]
	var prerequisites: Array = [
		{"from_collection_id": "collection.c0", "to_collection_id": "collection.c1",
			"dependency_fact_id": "fact.local.records"},
		{"from_collection_id": "collection.c0", "to_collection_id": "collection.c1",
			"dependency_fact_id": "fact.local.dispute"},
		{"from_collection_id": "collection.c1", "to_collection_id": "collection.c0",
			"dependency_fact_id": "fact.local.dispute"},
		{"from_collection_id": "collection.c0", "to_collection_id": "collection.c2",
			"dependency_fact_id": "fact.local.records"},
	]
	if case_name == "unsupported_link_dependency":
		prerequisites = []
	return Direction.build_packet("campaign.test", opportunities, facts, [], prerequisites)


## The compiled plan is a frozen v2 plan whose public goal is the completion of
## THOSE collections, and nothing broader.
func _test_compiled_plan() -> void:
	var packet := _packet()
	var accepted := Direction.validate_proposal(_proposal(), packet)
	if not bool(accepted.get("ok", false)):
		_expect(false, "Could not build a proposal to compile.")
		return
	var compiled := Direction.compile_plan(accepted["proposal"], packet, "resolution.direction.1")
	if not bool(compiled.get("ok", false)):
		_expect(false, "A valid proposal did not compile: %s" % str(compiled.get("reason", "")))
		return
	var plan: Dictionary = compiled["plan"]
	_expect(int(plan["version"]) == Resolution.PLAN_VERSION_V2, "The compiled plan was not v2.")
	_expect(Resolution.validate(plan).is_valid(),
		"The compiled plan failed resolution validation: %s" % Resolution.validate(plan).summary())
	_expect((plan["alternatives"] as Array).size() == 1,
		"A partial or failure alternative was manufactured with no implemented loss effect.")
	var alternative: Dictionary = plan["alternatives"][0]
	_expect(str(alternative["result"]) == "success", "The single alternative was not a success.")
	_expect((alternative["all_of"] as Array).size() == 2,
		"The success condition did not AND every selected collection.")
	for predicate: Dictionary in alternative["all_of"]:
		_expect(str(predicate["kind"]) == "collection_satisfied",
			"The compiled plan used a predicate other than collection_satisfied.")
	for interest: Dictionary in plan["interests"]:
		_expect(str(interest["completion_kind"]) == "item_delivered",
			"An interest claimed a completion kind the collection does not support.")
		_expect(str(interest["recipient_id"]) == "npc.local.clerk",
			"An interest lost the recipient who must actually take delivery.")
		_expect(str(interest["desire_id"]).begins_with("desire."),
			"An interest lost its desire binding: %s" % str(interest["desire_id"]))
	_expect(str(plan["public_direction"]) == str(accepted["proposal"]["public_direction"]),
		"The compiled plan lost the writer's public direction.")
	# It binds and activates against a real campaign.
	var bound := Resolution.bind(plan, {
		"desires": [{"system_id": "system.local", "faction_id": "faction.c0", "desire_id": "desire.c0"},
			{"system_id": "system.local", "faction_id": "faction.c1", "desire_id": "desire.c1"}],
		"system_ids": ["system.local"], "station_ids": ["station.local"],
		"known_fact_ids": [], "effect_ids": [],
		"collection_ids": ["collection.c0", "collection.c1"]})
	_expect(bool(bound.get("ok", false)) and str(bound["plan"]["status"]) == "active",
		"The compiled plan did not activate against its own campaign: %s" % str(bound.get("reason", "")))
	if bool(bound.get("ok", false)):
		_expect(bool(bound["plan"].get("frozen", false)), "An active direction plan was not frozen.")
	# A selection the packet cannot back never compiles.
	var stray: Dictionary = (accepted["proposal"] as Dictionary).duplicate(true)
	stray["selected_collection_ids"] = ["collection.absent"]
	_expect(not bool(Direction.compile_plan(stray, packet, "resolution.bad").get("ok", true)),
		"A plan compiled around a collection the packet never supplied.")


## ---------------------------------------------------------------------------
## The live writer request: prompt, parsing and the repair budget.
## ---------------------------------------------------------------------------

## The prompt carries only what the packet supplied, states the schema in PROSE
## (format:"json" turns a labelled prompt line into a JSON key), and names the
## exact rejection reason on a repair.
func _test_prompt() -> void:
	var packet := _packet()
	var prompt: String = Direction.build_prompt(Direction.writer_view(packet), "")
	for candidate: Dictionary in packet["candidates"]:
		_expect(prompt.contains(str(candidate["collection_id"])),
			"The prompt omitted a supplied job id.")
	for fact_id: Variant in packet["premise_fact_ids"]:
		_expect(prompt.contains(str(fact_id)), "The prompt omitted a supplied fact.")
	_expect(not prompt.contains("desire."),
		"The prompt leaked an internal desire binding to the writer.")
	# The schema is described, never demonstrated as a labelled block: under
	# format:"json" a "Label:" line in the prompt becomes a key in the answer.
	for label: String in ["version:", "premise_fact_ids:", "selected_collection_ids:",
			"links:", "public_direction:"]:
		_expect(not prompt.contains(label),
			"The prompt used a labelled block that format:\"json\" would turn into a key: %s" % label)
	_expect(prompt.contains("selected_collection_ids"),
		"The prompt never names the field the writer must fill.")
	# The overreach the posting layer refuses is refused here too.
	_expect(prompt.to_lower().contains("clears a name") 			and prompt.to_lower().contains("transfers a lease"),
		"The prompt did not forbid claiming effects the game cannot record.")
	var repaired: String = Direction.build_prompt(Direction.writer_view(packet),
		"unknown_premise_fact:fact.invented")
	_expect(repaired.contains("unknown_premise_fact:fact.invented"),
		"A repair prompt did not name the reason the first answer was rejected.")
	_expect(not prompt.contains("previous answer was rejected"),
		"A first-attempt prompt claimed a previous answer was rejected.")


## Parsing is shape only. What the claims MEAN is validate_proposal's job.
func _test_response_parsing() -> void:
	var packet := _packet()
	var ids: Array = []
	for candidate: Dictionary in packet["candidates"]:
		ids.append(str(candidate["collection_id"]))
	var good := {"version": 1, "premise_fact_ids": ["fact.local.backlog"],
		"selected_collection_ids": [ids[0]], "links": [],
		"public_direction": "Get the records back."}
	var parsed := Direction.parse_response(JSON.stringify(good))
	_expect(bool(parsed.get("ok", false)), "A well-formed reply did not parse: %s" % str(parsed.get("reason", "")))
	_expect(bool(Direction.validate_proposal(parsed.get("proposal", {}), packet).get("ok", false)),
		"A parsed reply did not survive validation.")
	# A small model wrapping the answer in one key is unwrapped exactly once.
	var wrapped := Direction.parse_response(JSON.stringify({"proposal": good}))
	_expect(bool(wrapped.get("ok", false)), "A single-key wrapper was not unwrapped.")
	_expect(bool(Direction.validate_proposal(wrapped.get("proposal", {}), packet).get("ok", false)),
		"An unwrapped reply did not survive validation.")
	# A missing version is filled rather than failed on a formality.
	var no_version := good.duplicate(true)
	no_version.erase("version")
	var filled := Direction.parse_response(JSON.stringify(no_version))
	_expect(bool(filled.get("ok", false)) 			and int((filled["proposal"] as Dictionary)["version"]) == Direction.SCHEMA_VERSION,
		"A reply with no version field was not filled in.")
	# Junk is refused with a reason, not a crash.
	for bad: String in ["", "   ", "not json at all", "[1, 2, 3]", "\"a string\""]:
		var refused := Direction.parse_response(bad)
		_expect(not bool(refused.get("ok", true)), "Junk parsed as a proposal: %s" % bad)
		_expect(not str(refused.get("reason", "")).is_empty(),
			"An unparseable reply gave no reason: %s" % bad)
