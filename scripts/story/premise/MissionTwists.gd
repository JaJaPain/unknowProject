extends RefCounted

## Mission Composer, layer 4 (vision plan 4.2): twists. Some story missions
## turn partway through and put a real choice to the captain, and the answer
## becomes story: it settles the arc's outcome and leaves a deed the factions
## hear about.
##
## The first twists ride on the comms-reversal machinery (a hail, a ceasefire,
## a choice panel): on a kill mission the target either offers more than the
## client pays (counter-offer) or powers down and begs (surrender). The kill
## objective becomes TARGET_WITH_COMMS_REVERSAL, which triggers the hail after
## the second-to-last kill.
##
## PURE and seeded per mission, like complications.

const DEFAULT_PATH := "res://data/content/mission_twists.json"
const REVERSAL_OBJECTIVE := "TARGET_WITH_COMMS_REVERSAL"

## Deed tags per resolved twist branch (see FactionDNA.DEED_SIGNALS: "sold"
## reads as profit, "spared" as mercy).
const DEEDS := {
	"accept_bribe": {"tag": "sold_out_contract", "summary": "A pilot took {target}'s money and let them go."},
	"spare": {"tag": "spared_surrendered_target", "summary": "A pilot spared {target} after they surrendered."},
	"deliver": {"tag": "smuggled_undeclared_cargo", "summary": "A pilot ran undeclared cargo for {target} and asked no questions."},
	"finish_lie": {"tag": "covered_for_client", "summary": "A pilot learned what {target} was hiding and finished the job anyway."},
	"expose": {"tag": "exposed_client", "summary": "A pilot walked away from {target}'s job and told everyone why."},
	"race_won": {"tag": "won_the_race", "summary": "A pilot beat a rival to {target}'s job and took the whole fee."},
}

static var _deck: Dictionary = {}


static func deck() -> Dictionary:
	if _deck.is_empty():
		var file := FileAccess.open(DEFAULT_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_deck = parsed
	return _deck


## Whether a card's private fact can be read aloud as "what the client left
## out": a hidden truth about someone, not narration of the pilot (the card
## brief's rule 8; older cards are being rewritten).
static func is_readable_fact(fact: String) -> bool:
	var text := fact.strip_edges()
	if text.length() < 20:
		return false
	var re := RegEx.create_from_string("(?i)\\b(pilot|player|you|your)\\b")
	return re.search(text) == null


## The twist this mission rolls, or {} for none. `has_private_fact`: the
## card mission has a hidden truth the client-lie twist can reveal.
static func roll(verb: String, seed_key: String, has_private_fact: bool = false) -> Dictionary:
	var d := deck()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("twist|" + seed_key)
	if rng.randf() >= float(d.get("chance", 0.35)):
		return {}
	var options: Array = []
	for t in d.get("twists", []):
		if t is Dictionary and verb in (t.get("verbs", []) as Array):
			if bool(t.get("needs_private_fact", false)) and not has_private_fact:
				continue
			options.append(t)
	if options.is_empty():
		return {}
	var twist: Dictionary = (options[rng.randi() % options.size()] as Dictionary).duplicate(true)
	var hails: Array = twist.get("hails", [])
	twist["hail"] = str(hails[rng.randi() % hails.size()]) if not hails.is_empty() else ""
	var cargo: Array = twist.get("true_cargo", [])
	twist["true_cargo_pick"] = str(cargo[rng.randi() % cargo.size()]) if not cargo.is_empty() else ""
	return twist


## Turns a composed offer into its twisted form (returns a new offer).
## `context`: {private_fact, rival_name} for the reveal twists.
static func apply(offer: Dictionary, twist: Dictionary, requester_name: String, target_name: String, context: Dictionary = {}) -> Dictionary:
	if twist.is_empty():
		return offer
	if str(twist.get("kind", "")) in ["wrong_cargo", "reveal"]:
		return _apply_reveal(offer, twist, requester_name, context)
	var out := offer.duplicate(true)
	var objective: Dictionary = out.get("objective", {})
	var reward := int(objective.get("reward_credits", 0))
	var who := requester_name if not requester_name.is_empty() else "your client"
	var target := target_name if not target_name.is_empty() else "the target"
	objective["type"] = REVERSAL_OBJECTIVE
	objective["twist_id"] = str(twist.get("id", ""))
	objective["twist_target_name"] = target
	objective["reversal_kind"] = str(twist.get("kind", "bribe"))
	objective["comms_reversal_line"] = str(twist.get("hail", "")).replace("{requester}", who).replace("{target}", target)
	objective["bribe_amount"] = int(round(reward * float(twist.get("bribe_share", 1.3))))
	objective["spare_amount"] = int(round(reward * float(twist.get("spare_share", 0.6))))
	out["objective"] = objective
	out["twist_id"] = str(twist.get("id", ""))
	return out


## A twist revealed a minute into the flight (QuestManager), whatever the
## job: the courier's crate is not what the manifest says (wrong_cargo), the
## client's hidden truth comes out (client_lie), or a rival pilot is working
## the same contract (rival). The objective itself is unchanged.
static func _apply_reveal(offer: Dictionary, twist: Dictionary, requester_name: String, context: Dictionary) -> Dictionary:
	var out := offer.duplicate(true)
	var objective: Dictionary = out.get("objective", {})
	var item := str(objective.get("item_name", "the cargo"))
	var true_cargo := str(twist.get("true_cargo_pick", "something else"))
	var who := requester_name if not requester_name.is_empty() else "the client"
	var rival := str(context.get("rival_name", "")).strip_edges()
	if rival.is_empty():
		rival = "Another freelancer"
	var fact := str(context.get("private_fact", "")).strip_edges()
	objective["twist_id"] = str(twist.get("id", ""))
	objective["twist_reveal_kind"] = str(twist.get("reveal_kind", "wrong_cargo"))
	objective["twist_true_cargo"] = true_cargo
	objective["twist_rival_name"] = rival
	var reveal := str(twist.get("hail", "")).replace("{item}", item).replace("{true_cargo}", true_cargo)
	objective["twist_reveal"] = reveal.replace("{requester}", who).replace("{rival}", rival).replace("{fact}", fact)
	objective["twist_target_name"] = who
	out["objective"] = objective
	out["twist_id"] = str(twist.get("id", ""))
	return out


## The deed a resolved twist leaves, or {} (finishing the job is just the job).
static func deed_for(branch_id: String, target_name: String) -> Dictionary:
	var d: Dictionary = DEEDS.get(branch_id, {})
	if d.is_empty():
		return {}
	var target := target_name if not target_name.is_empty() else "a marked pilot"
	return {"tag": str(d["tag"]), "public_summary": str(d["summary"]).replace("{target}", target)}
