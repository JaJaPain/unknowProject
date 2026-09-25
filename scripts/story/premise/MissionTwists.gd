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


## The twist this mission rolls, or {} for none.
static func roll(verb: String, seed_key: String) -> Dictionary:
	var d := deck()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("twist|" + seed_key)
	if rng.randf() >= float(d.get("chance", 0.35)):
		return {}
	var options: Array = []
	for t in d.get("twists", []):
		if t is Dictionary and verb in (t.get("verbs", []) as Array):
			options.append(t)
	if options.is_empty():
		return {}
	var twist: Dictionary = (options[rng.randi() % options.size()] as Dictionary).duplicate(true)
	var hails: Array = twist.get("hails", [])
	twist["hail"] = str(hails[rng.randi() % hails.size()]) if not hails.is_empty() else ""
	return twist


## Turns a composed kill offer into its twisted form (returns a new offer).
static func apply(offer: Dictionary, twist: Dictionary, requester_name: String, target_name: String) -> Dictionary:
	if twist.is_empty():
		return offer
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


## The deed a resolved twist leaves, or {} (finishing the job is just the job).
static func deed_for(branch_id: String, target_name: String) -> Dictionary:
	var d: Dictionary = DEEDS.get(branch_id, {})
	if d.is_empty():
		return {}
	var target := target_name if not target_name.is_empty() else "a marked pilot"
	return {"tag": str(d["tag"]), "public_summary": str(d["summary"]).replace("{target}", target)}
