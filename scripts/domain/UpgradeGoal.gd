extends RefCounted

## The upgrade goal (docs/core_loop_plan_2026_10_01.md 3.3): one upgrade the
## player is working towards, with what it costs and how much they have. Read
## by the HUD goal card and the goal smoke test. The goal itself lives in
## StoryManager.story_state["upgrade_goal"] = {"sys", "path", "tier", "auto"}.
##
## `gs` is GlobalState (passed in so tests can drive a real one).

const GateClass := preload("res://scripts/domain/GateClass.gd")
const GOAL_KEY := "upgrade_goal"


## Whether `goal` names a real, not-yet-fitted tier.
static func is_live(gs, goal: Dictionary) -> bool:
	var sys := str(goal.get("sys", ""))
	var tier := int(goal.get("tier", 0))
	if sys.is_empty() or not gs.UPGRADE_TREE.has(sys):
		return false
	var branches: Dictionary = gs.UPGRADE_TREE[sys]["branches"]
	if not branches.has(str(goal.get("path", ""))) or not (branches[str(goal["path"])] as Dictionary).has(tier):
		return false
	return int(gs.current_upgrades.get(sys, {}).get("tier", 1)) < tier


## The goal for the system's next tier on `path` (or the cheapest branch when
## the system is still base).
static func next_tier_goal(gs, sys: String, auto: bool = false) -> Dictionary:
	if not gs.UPGRADE_TREE.has(sys):
		return {}
	var info: Dictionary = gs.current_upgrades.get(sys, {"tier": 1, "path": "base"})
	var tier := int(info.get("tier", 1)) + 1
	var branches: Dictionary = gs.UPGRADE_TREE[sys]["branches"]
	var path := str(info.get("path", "base"))
	if path == "base" or not branches.has(path):
		path = ""
		var cheapest := 1 << 30
		for b in branches:
			if (branches[b] as Dictionary).has(tier) and int(branches[b][tier]["cost_cr"]) < cheapest:
				cheapest = int(branches[b][tier]["cost_cr"])
				path = str(b)
	if path.is_empty() or not (branches[path] as Dictionary).has(tier):
		return {}
	return {"sys": sys, "path": path, "tier": tier, "auto": auto}


## What to suggest with no goal set: Shields Mk II until Class II is open,
## then (once Class III is open) this campaign's keystone until it's fitted,
## then the next tier of the weakest rated system; the powerplant first when
## that upgrade would draw more power than the ship has.
static func suggest(gs) -> Dictionary:
	var tiers: Dictionary = GateClass.tiers_of(gs.current_upgrades)
	var goal := {}
	var keystone: Dictionary = preload("res://scripts/domain/Keystone.gd").draw(int(gs.campaign_seed) if "campaign_seed" in gs else 0)
	if int(tiers["shields"]) < 2:
		goal = next_tier_goal(gs, "shields", true)
	elif GateClass.ship_rating(tiers) >= GateClass.rating_for_class(preload("res://scripts/domain/Keystone.gd").KEYSTONE_CLASS - 1) \
			and not preload("res://scripts/domain/Keystone.gd").is_met(keystone, tiers):
		# Class III is open, so the deep gates are next: work on the keystone.
		goal = next_tier_goal(gs, str(keystone["sys"]), true)
	if goal.is_empty() and int(tiers["shields"]) >= 2:
		var low := GateClass.weakest_tier(tiers)
		for sys in GateClass.RATED_SYSTEMS:
			if int(tiers[sys]) == low:
				goal = next_tier_goal(gs, sys, true)
				if not goal.is_empty():
					break
	if not goal.is_empty() and power_short(gs, goal) > 0:
		var power_goal := next_tier_goal(gs, "power", true)
		if not power_goal.is_empty():
			return power_goal
	return goal


## Tier data for the goal.
static func tier_data(gs, goal: Dictionary) -> Dictionary:
	return gs.UPGRADE_TREE[str(goal["sys"])]["branches"][str(goal["path"])][int(goal["tier"])]


## Megawatts more than the ship can supply if the goal were fitted (0 = fine).
static func power_short(gs, goal: Dictionary) -> int:
	var sys := str(goal["sys"])
	if sys == "power":
		return 0
	var info: Dictionary = gs.current_upgrades.get(sys, {"tier": 1, "path": "base"})
	var now_power := int(gs.UPGRADE_TREE[sys]["base_power"])
	if int(info.get("tier", 1)) > 1:
		now_power = int(gs.UPGRADE_TREE[sys]["branches"][str(info["path"])][int(info["tier"])].get("power", 0))
	var after := int(gs.get_current_power_draw()) + int(tier_data(gs, goal).get("power", 0)) - now_power
	return maxi(0, after - int(gs.power_capacity))


## Ore the player can pay with: banked plus ore in the hold.
static func ore_available(gs) -> float:
	var ore := float(gs.player_storage_ore)
	if gs.cargo_type == gs.CargoType.ORE:
		ore += float(gs.cargo)
	return ore


## The card's rows: [{"id", "label", "have", "need", "hint"}], in order
## credits, ore, each material, then power when it's short.
static func rows(gs, goal: Dictionary) -> Array:
	var data := tier_data(gs, goal)
	var out: Array = []
	out.append({"id": "credits", "label": "Credits", "have": int(gs.player_credits), "need": int(data["cost_cr"]),
		"hint": "Take a job from a station board, or sell ore."})
	# Ore by type, climbing with the tier (playtest 2026-10-08 finding 1).
	var ore_cost: Dictionary = gs.split_upgrade_ore(int(data["cost_ore"]), int(goal["tier"]))
	for ore in ore_cost:
		out.append({"id": "ore:%s" % ore, "label": OreTypesScript.display(str(ore)), "have": int(floor(float(gs.ore_on_hand(str(ore))))),
			"need": int(ore_cost[ore]), "hint": ORE_WHERE.get(str(ore), "Mine it, then bank it at a station (Bank for upgrades).")})
	var mats: Dictionary = gs.upgrade_material_cost(str(goal["sys"]), int(goal["tier"]))
	for item in mats:
		out.append({"id": str(item), "label": material_label(str(item)), "have": int(gs.inventory.get_quantity(str(item))),
			"need": int(mats[item]), "hint": "A red rock: target it, fly close, press G to send a survey drone in."})
	var short := power_short(gs, goal)
	if short > 0:
		out.append({"id": "power", "label": "Power", "have": 0, "need": short,
			"hint": "Needs %d MW more than the ship has: upgrade the Powerplant first." % short})
	return out


## Where each ore is found, for its row (scan rocks with C to see them).
const ORE_WHERE := {
	"silicate": "Silicate: the common grey rock, in every field. Scan with C to see what a field holds.",
	"ferrite": "Ferrite: dark iron rock, from the first systems out. Scan with C to find it.",
	"cuprite": "Cuprite: green-veined rock, rarer, more of it in deeper systems. Scan with C to find it.",
	"thorium": "Thorium: glowing yellow rock, only three or more gates from home. Scan with C to find it.",
}
const OreTypesScript := preload("res://scripts/economy/OreTypes.gd")


## What each material is and where it comes from, for its row's tooltip.
const MATERIAL_HOW := {
	"thermal_lattice": "Thermal lattice: a heat-tolerant tech-grade weave, for weapons, engines and power.",
	"rad_quartz": "Rad-quartz: a radiation-hardened crystal, for shields, sensors and mining gear.",
	"cryo_ferrite": "Cryo ferrite: a cold-stable iron, for cargo and storage.",
	"resonant_crystal": "Resonant crystal: the rare top-tier material. It sometimes turns up from a clean drone run with the ore nearly whole.",
}
const DRONE_HOW := "Red rocks (tech-grade seams) each hold one of the three tech materials. Target a red rock, fly close, press G and fly the survey drone to a seam. A clean run brings home two. Survey drones are sold at station stores."


## The hover text for a goal card row: what it is, how to get it, and how
## far along you are (Abe, playtest 2026-10-03 finding 12).
static func row_tooltip(row: Dictionary) -> String:
	var id := str(row.get("id", ""))
	var have := int(row.get("have", 0))
	var need := int(row.get("need", 0))
	if id != "power" and have >= need:
		return "Done."
	match id:
		"credits":
			return "Credits: %d of %d.\nTake a job from a station board or from Kaelen, sell ore, or sell survey data from new systems." % [have, need]
		"ore":
			return "Ore: %d of %d banked." % [have, need]
		"power":
			return "Fitting this draws %d MW more than your powerplant gives.\nUpgrade the Powerplant first (you can set it as your goal on the upgrade screen)." % need
	if id.begins_with("ore:"):
		var ore_id := id.trim_prefix("ore:")
		return "%s: %d of %d banked or in the hold.\n%s Banked ore is kept for upgrades; ore in your hold can still be sold." % [
			OreTypesScript.display(ore_id), have, need, str(ORE_WHERE.get(ore_id, ""))]
	var what := str(MATERIAL_HOW.get(id, "%s: a tech-grade material." % material_label(id)))
	return "%s\n%d of %d.\n%s" % [what, have, need, DRONE_HOW]


static func material_label(item: String) -> String:
	return preload("res://scripts/story/activities/DroneMazeActivity.gd").material_name(item)


## Every row covered: dock and fit it.
static func is_ready(gs, goal: Dictionary) -> bool:
	for row in rows(gs, goal):
		if int(row["have"]) < int(row["need"]) or str(row["id"]) == "power":
			return false
	return true


## "Shields Mk II (Bulwark)".
static func title(goal: Dictionary) -> String:
	var sys := str(goal["sys"])
	var name := "Powerplant" if sys == "power" else sys.capitalize()
	var roman: String = GateClass.class_name_of(int(goal["tier"]))
	return "%s Mk %s (%s)" % [name, roman, str(goal["path"]).capitalize()]


## Ship Rating now and after the goal is fitted.
static func rating_change(gs, goal: Dictionary) -> Array:
	var tiers: Dictionary = GateClass.tiers_of(gs.current_upgrades)
	var before := GateClass.ship_rating(tiers)
	if tiers.has(str(goal["sys"])):
		tiers[str(goal["sys"])] = int(goal["tier"])
	return [before, GateClass.ship_rating(tiers)]
