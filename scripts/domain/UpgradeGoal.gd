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
## then the next tier of the weakest rated system; the powerplant first when
## that upgrade would draw more power than the ship has.
static func suggest(gs) -> Dictionary:
	var tiers: Dictionary = GateClass.tiers_of(gs.current_upgrades)
	var goal := {}
	if int(tiers["shields"]) < 2:
		goal = next_tier_goal(gs, "shields", true)
	else:
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
	if int(data["cost_ore"]) > 0:
		out.append({"id": "ore", "label": "Ore", "have": int(floor(ore_available(gs))), "need": int(data["cost_ore"]),
			"hint": "Mine any rock, then bank it at a station (Bank for upgrades)."})
	var mats: Dictionary = gs.upgrade_material_cost(str(goal["sys"]), int(goal["tier"]))
	for item in mats:
		out.append({"id": str(item), "label": material_label(str(item)), "have": int(gs.inventory.get_quantity(str(item))),
			"need": int(mats[item]), "hint": "A red rock: target it, fly close, press G to send a survey drone in."})
	var short := power_short(gs, goal)
	if short > 0:
		out.append({"id": "power", "label": "Power", "have": 0, "need": short,
			"hint": "Needs %d MW more than the ship has: upgrade the Powerplant first." % short})
	return out


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
