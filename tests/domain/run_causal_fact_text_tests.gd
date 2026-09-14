extends SceneTree

## Pins the fact TEXT a compiled contract produces.
##
## Every bug this suite covers was found by printing real compiled facts from the
## real board builder and reading them. None was visible in the code, and all
## four would have been spoken to the player: a raw faction hash, a faction
## obstructing itself, two broken sentences and one false causal claim.

const CompilerType := preload("res://scripts/domain/QuestCausalContractCompiler.gd")
const ContractType := preload("res://scripts/domain/QuestCausalContract.gd")
const DesireType := preload("res://scripts/persistence/GeneratedFactionDesire.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_no_raw_identifiers_in_player_facing_facts()
	_test_a_faction_never_obstructs_itself()
	_test_fact_sentences_are_well_formed()
	_test_ore_does_not_claim_to_satisfy_an_immaterial_need()
	_test_intents_only_name_verbs_that_can_serve_the_need()
	_test_unbound_cargo_does_not_claim_to_be_the_need()
	_test_delegation_cites_the_real_obstacle()
	_test_no_unchecked_superlatives()
	_test_compiler_preserves_goal_need_explanation()

	if _failures.is_empty():
		print("[PASS] Causal fact text tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_compiler_preserves_goal_need_explanation() -> void:
	for index in range(30):
		var desire := DesireType.build("explanation_%d" % index, "scope", 0)
		var contract := _compile({"agenda": {"faction_id": "faction.generated.abc.f0", "desire": desire}})
		var text := ContractType.fact_text(contract, "fact.need")
		_expect(text.contains(str(desire["need_reason"])), "Compiler lost the explanation joining goal and need: %s" % text)
		_expect(text.contains(str(desire["need"])) and text.contains(str(desire["goal"])), "Compiler lost the bound goal or need.")


func _compile(overrides: Dictionary = {}) -> Dictionary:
	var desire := DesireType.build("fact_text_seed", "scope0", 0)
	var source := {
		"campaign_id": "campaign.facts",
		"system_id": "system.facts",
		"objective": {"type": "RECOVER_COMBAT_DROP", "reward_credits": 200, "target_faction": "gen_3753748b9ca0_f1"},
		"cause": {
			"cause_faction_id": "faction.generated.abc.f0",
			"desire_id": str(desire["id"]),
			"cause_id": "cause.facts.recovery",
		},
		"agenda": {
			"faction_id": "faction.generated.abc.f0",
			"faction_name": "Kessel Freight Compact",
			"desire": desire,
			"relationships": [],
		},
		"requester_display": "Kessel Freight Compact",
	}
	source.merge(overrides, true)
	return CompilerType.compile(source)


func _public_texts(contract: Dictionary) -> Array[String]:
	var texts: Array[String] = []
	for fact_id in (ContractType.public_facts(contract) as Dictionary).keys():
		texts.append(ContractType.fact_text(contract, str(fact_id)))
	return texts


## A generated faction key is a hash. It must never be spoken.
func _test_no_raw_identifiers_in_player_facing_facts() -> void:
	for seed_index in range(25):
		var desire := DesireType.build("ident_%d" % seed_index, "s%d" % seed_index, 0)
		var contract := _compile({
			"agenda": {
				"faction_id": "faction.generated.abc.f0",
				"faction_name": "Kessel Freight Compact",
				"desire": desire,
				"relationships": [],
			},
		})
		if not ContractType.is_present(contract):
			continue
		for text in _public_texts(contract):
			var lower := text.to_lower()
			for marker in ["gen_", "faction.generated.", "desire.", "cause.", "event.", "npc.", "_f0", "_f1"]:
				_expect(
					not lower.contains(marker),
					"A raw identifier '%s' reached a player-facing fact: %s" % [marker, text]
				)


func _test_a_faction_never_obstructs_itself() -> void:
	var contract := _compile({"target_faction_display": "Kessel Freight Compact"})
	var helps := ContractType.fact_text(contract, "fact.action_helps")
	_expect(
		not helps.is_empty(),
		"The recovery objective produced no action justification at all."
	)
	_expect(
		helps.count("Kessel Freight Compact") <= 1,
		"A faction was named as the thing standing between itself and its own goal: %s" % helps
	)
	# With a genuine third party it IS named.
	var rival := _compile({"target_faction_display": "Ossuary Salvage Lease"})
	_expect(
		ContractType.fact_text(rival, "fact.action_helps").contains("Ossuary Salvage Lease"),
		"A real obstructing party was not named."
	)


## Catches the two sentences that came out mangled: a stake that read
## "is trying to nobody local will take the run", and a limit that began
## lowercase in the middle of its own sentence.
func _test_fact_sentences_are_well_formed() -> void:
	for seed_index in range(25):
		var desire := DesireType.build("gram_%d" % seed_index, "g%d" % seed_index, 0)
		var contract := _compile({
			"agenda": {
				"faction_id": "faction.generated.abc.f0",
				"faction_name": "Kessel Freight Compact",
				"desire": desire,
				"relationships": [],
			},
		})
		if not ContractType.is_present(contract):
			continue
		for text in _public_texts(contract):
			_expect(
				not text.strip_edges().is_empty(),
				"A recorded fact had no text at all."
			)
			var first := text.substr(0, 1)
			_expect(
				first == first.to_upper(),
				"A fact sentence began lowercase: %s" % text
			)
			_expect(
				text.strip_edges().ends_with("."),
				"A fact sentence did not end in a full stop: %s" % text
			)
			_expect(
				not text.contains("  ") and not text.contains(" ."),
				"A fact sentence had mangled spacing: %s" % text
			)
			# The specific broken join, pinned by shape rather than by wording.
			_expect(
				not text.contains("is trying to nobody")
					and not text.contains("unless a ")
					and not text.contains("to the berth"),
				"A fact sentence glued two clauses into nonsense: %s" % text
			)


## Hauling ore does not produce survey data. Stating that it does is a false
## causal claim, and the fact packet would present it to the model as truth.
func _test_ore_does_not_claim_to_satisfy_an_immaterial_need() -> void:
	var desire := DesireType.build("ore_seed", "o0", 0)
	var contract := _compile({
		"objective": {"type": "DELIVER_ORE", "amount_required": 45.0, "reward_credits": 135},
		"agenda": {
			"faction_id": "faction.generated.abc.f0",
			"faction_name": "Kessel Freight Compact",
			"desire": desire,
			"relationships": [],
		},
	})
	var helps := ContractType.fact_text(contract, "fact.action_helps")
	if helps.is_empty():
		return
	_expect(
		not helps.contains("needs to cover"),
		"The ore job claimed the ore directly satisfies the need: %s" % helps
	)
	_expect(
		helps.contains("pay for") or helps.contains("selling"),
		"The ore job did not explain the ore as funding the need: %s" % helps
	)


## A need must only imply verbs that could actually serve it.
func _test_intents_only_name_verbs_that_can_serve_the_need() -> void:
	var impossible := {
		"survey data from a drift it cannot reach": ["ore"],
		"a witness who will go on record": ["combat", "ore"],
		"a clean ore assay": ["combat"],
		"medical stock for its own crew": ["combat"],
	}
	for need in impossible.keys():
		if not DesireType.INTENTS_BY_NEED.has(need):
			continue
		var intents: Array = DesireType.INTENTS_BY_NEED[need]
		for banned in (impossible[need] as Array):
			_expect(
				str(banned) not in intents,
				"Need '%s' implies '%s', which cannot serve it." % [str(need), str(banned)]
			)



## The failure the integration review named: the compiler asserting a causal
## link it never proved. An arbitrary crate must NOT be described as the thing
## the requester is short of -- once that enters the contract it IS the record,
## and no downstream critic can catch it.
func _test_unbound_cargo_does_not_claim_to_be_the_need() -> void:
	var desire := DesireType.build("bind_seed", "b0", 0)
	var need := str(desire["need"])
	var bound_item := DesireType.item_for_need(need, str(desire["id"]))
	_expect(
		not bound_item.is_empty(),
		"No cargo binding exists for need '%s'." % need
	)

	# An item that genuinely satisfies the need earns the strong claim.
	var bound := _compile({
		"objective": {
			"type": "DELIVERY_COURIER",
			"item_name": bound_item,
			"destination_display": "Blacklist Yard",
			"reward_credits": 200,
		},
		"agenda": {
			"faction_id": "faction.generated.abc.f0",
			"faction_name": "Kessel Freight Compact",
			"desire": desire,
			"relationships": [],
		},
	})
	var bound_text := ContractType.fact_text(bound, "fact.action_helps")
	_expect(
		bound_text.contains("short of"),
		"Cargo that IS the need did not earn the supported claim: %s" % bound_text
	)

	# An arbitrary crate must not.
	var unbound := _compile({
		"objective": {
			"type": "DELIVERY_COURIER",
			"item_name": "Quiet Little Black Box",
			"destination_display": "Blacklist Yard",
			"reward_credits": 200,
		},
		"agenda": {
			"faction_id": "faction.generated.abc.f0",
			"faction_name": "Kessel Freight Compact",
			"desire": desire,
			"relationships": [],
		},
	})
	var unbound_text := ContractType.fact_text(unbound, "fact.action_helps")
	_expect(
		not unbound_text.is_empty(),
		"An unbound courier job recorded no action justification at all."
	)
	_expect(
		not unbound_text.contains("short of"),
		"An arbitrary crate was claimed to be the thing they lack: %s" % unbound_text
	)
	_expect(
		not unbound_text.contains(need),
		"An unbound crate was linked to the recorded need anyway: %s" % unbound_text
	)


## Delegation was invented from the objective type alone ("no free hull"). It
## must come from the faction's own recorded obstacle, or be absent.
func _test_delegation_cites_the_real_obstacle() -> void:
	for seed_index in range(15):
		var desire := DesireType.build("deleg_%d" % seed_index, "d%d" % seed_index, 0)
		var contract := _compile({
			"agenda": {
				"faction_id": "faction.generated.abc.f0",
				"faction_name": "Kessel Freight Compact",
				"desire": desire,
				"relationships": [],
			},
		})
		if not ContractType.is_present(contract):
			continue
		var delegation := ContractType.fact_text(contract, "fact.delegation")
		if delegation.is_empty():
			continue
		# The invented stock phrases must be gone.
		for invented in ["no hull free", "nobody local has a hull free", "no armed hull of their own"]:
			_expect(
				not delegation.contains(invented),
				"Delegation still invents a reason from mission type: %s" % delegation
			)
		# ...and what it says must be the obstacle actually on record.
		var obstacle := str(desire["obstacle"]).strip_edges().trim_suffix(".")
		var obstacle_tail := obstacle.substr(1)
		_expect(
			delegation.contains(obstacle_tail),
			"Delegation did not cite the recorded obstacle.\n  said: %s\n  obstacle: %s" % [
				delegation, obstacle
			]
		)


## Superlatives assert that alternatives were checked. Nothing checks them.
func _test_no_unchecked_superlatives() -> void:
	var banned := ["the only way", "the only record", "only solution", "no other way"]
	for seed_index in range(20):
		var desire := DesireType.build("sup_%d" % seed_index, "s%d" % seed_index, 0)
		for objective in [
			{"type": "PURCHASE_DELIVERY", "item_name": "Coolant Bypass Cap", "store_display": "Grease Monkeys", "reward_credits": 150},
			{"type": "INVESTIGATE_SIGNAL", "site_display": "Corvid Drift", "reward_credits": 400},
			{"type": "DELIVER_ORE", "amount_required": 45.0, "reward_credits": 135},
		]:
			var contract := _compile({
				"objective": objective,
				"agenda": {
					"faction_id": "faction.generated.abc.f0",
					"faction_name": "Kessel Freight Compact",
					"desire": desire,
					"relationships": [],
				},
			})
			if not ContractType.is_present(contract):
				continue
			for text in _public_texts(contract):
				for phrase in banned:
					_expect(
						not text.to_lower().contains(phrase),
						"An unchecked superlative reached a fact: %s" % text
					)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
