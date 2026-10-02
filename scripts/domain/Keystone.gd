extends RefCounted

## The keystone (docs/core_loop_plan_2026_10_01.md 2.3, core loop step 8): one
## requirement per campaign for the deep gates, drawn from a small deck so
## every playthrough's deep space is hostile in its own way. From Class IV on,
## a gate needs the Ship Rating AND this campaign's keystone upgrade.
##
## PURE: the card comes from the campaign seed, so it needs no save data and is
## the same on every load. N.O.V.A.'s lines are hand-written (no model): a
## rumour on first reaching depth 4-5, a reveal on first reaching depth 6 (the
## Class IV gates are next), one at the first refusal, one when it's fitted.

const KEYSTONE_CLASS := 4
const TIER := 3
const RUMOUR_DEPTHS := [4, 5]
const REVEAL_DEPTH := 6

const DECK := [
	{
		"id": "radiation_belt", "name": "Radiation belt", "sys": "shields",
		"reason": "A stellar remnant floods the deep gates with radiation.",
		"rumour": "Traders out here keep talking about the deep gates. Something past them burns: a dead star's leftovers, they say, and the whole far side glows with it. Unhardened shields fry on the way through. File that away.",
		"reveal": "The deep gates are close now, and the rumour holds: radiation on the far side. Shields Mk III, or we cook.",
		"refusal": "And this one leads into the radiation belt. Shields Mk III, Captain. I'm not arguing with physics.",
	},
	{
		"id": "gravity_shear", "name": "Gravity shear", "sys": "engine",
		"reason": "The deep folds are steep; a weak drive can't hold the line.",
		"rumour": "Heard something at the last dock. The deep gates out here have steep folds: the gravity shears so hard a weak drive can't hold the line through. Ships go in whole and come out in pieces.",
		"reveal": "Deep gates ahead, and the shear is real: I can see it bending the charts. Engine Mk III before we try one.",
		"refusal": "And it's a shear fold. Our drive can't hold that line. Engine Mk III first.",
	},
	{
		"id": "hostile_picket", "name": "Hostile picket", "sys": "weapons",
		"reason": "Something guards the deep gates and shoots first.",
		"rumour": "Spacers keep mentioning a picket on the deep gates. Nobody knows whose. It doesn't hail and it doesn't negotiate. It just shoots whatever comes through.",
		"reveal": "We're near the deep gates, and the picket is no story: there's something on the far side that doesn't answer hails. Weapons Mk III, so we can shoot back.",
		"refusal": "And something is sitting on the far side, waiting. Not with these guns. Weapons Mk III.",
	},
	{
		"id": "long_dark", "name": "Long dark", "sys": "cargo",
		"reason": "No stations past the line: you carry your own fuel and air.",
		"rumour": "There's talk of the long dark past the deep gates. No stations, no fuel, no air, for jumps on end. Whoever goes out there carries everything with them.",
		"reveal": "The deep gates are close. Past them it's the long dark: nobody to dock with. Cargo Mk III, so we can carry our own fuel and air.",
		"refusal": "And past it is the long dark. Our hold won't carry enough to get us back. Cargo Mk III.",
	},
	{
		"id": "ore_starved", "name": "Ore-starved", "sys": "mining",
		"reason": "The deep belts are hard ores; a stock laser can't cut them.",
		"rumour": "Miners out here grumble about the deep belts. Nothing soft left past the deep gates: hard ore only, and a weak laser just polishes it.",
		"reveal": "Deep gates ahead, and the miners weren't lying: the belts out there are hard ore. If we want to pay our way past them, we need Mining Mk III.",
		"refusal": "And out there it's hard ore or nothing, and our laser can't cut it. Mining Mk III.",
	},
]
const MET_LINE := "%s Mk III fitted. That's the price the deep gates asked. The rest is Ship Rating."


## This campaign's keystone card.
static func draw(campaign_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("keystone:%d" % campaign_seed)
	return (DECK[rng.randi() % DECK.size()] as Dictionary).duplicate()


static func by_id(id: String) -> Dictionary:
	for card in DECK:
		if str(card["id"]) == id:
			return (card as Dictionary).duplicate()
	return {}


## Whether gates of `gate_class` ask for the keystone.
static func applies(gate_class: int) -> bool:
	return gate_class >= KEYSTONE_CLASS


## Whether a ship with these tiers (GateClass.tiers_of shape) has it.
static func is_met(card: Dictionary, tiers: Dictionary) -> bool:
	return card.is_empty() or int(tiers.get(str(card["sys"]), 1)) >= TIER


## "Engine Mk III" for the HUD and the refusal.
static func requirement(card: Dictionary) -> String:
	return "%s Mk III" % str(card.get("sys", "")).capitalize()
