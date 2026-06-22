extends RefCounted

const EFFECTS = {
	"repair_kit": {"type": "heal", "amount": 25.0},
	"shield_cell": {"type": "shield_percent", "amount": 0.5},
	"scanner_probe": {"type": "reveal", "duration_seconds": 60.0},
	"salvage_drone": {"type": "salvage", "total_ore": 40.0},
	"damaged_transponder": {"type": "buff", "stat": "weapon_cooldown", "multiplier": 0.8, "duration_seconds": 60.0},
	"target_painter": {"type": "buff", "stat": "weapon_damage", "multiplier": 1.25, "duration_seconds": 15.0},
	"fuel_booster": {"type": "buff", "stat": "engine_speed", "multiplier": 2.0, "duration_seconds": 15.0},
	"flare_decoy": {"type": "decoy", "duration_seconds": 8.0},
	"emp_charge": {"type": "emp", "duration_seconds": 10.0},
	"antimatter_pod": {"type": "emp", "duration_seconds": 15.0},
}

const SALVAGE_RANGE := 75.0


static func can_use(item_id: String) -> bool:
	return EFFECTS.has(item_id)


static func is_usable_now(item_id: String, player: Node3D, inv, shield_cap: float) -> bool:
	if player == null or not can_use(item_id):
		return false
	if not inv.has_item(item_id):
		return false
	var effect: Dictionary = EFFECTS[item_id]
	match effect.get("type", ""):
		"heal":
			return float(player.get("health")) < float(player.get("max_health"))
		"shield_percent":
			return float(player.get("current_shield")) < shield_cap
		"salvage":
			return salvage_block_reason(player) == ""
		"reveal", "buff", "decoy", "emp":
			return true
	return false


# Returns "" if the salvage drone can be used right now, otherwise a human-readable reason.
static func salvage_block_reason(player: Node3D) -> String:
	if player == null:
		return "No ship."
	if player.get("is_docked"):
		return "Cannot use while docked."
	if player.get("_salvage_active"):
		return "Salvage already in progress."
	var target = GlobalState.active_target
	if target == null or not is_instance_valid(target):
		return "No wreck targeted."
	if not target.is_in_group("wreckage"):
		return "Target is not a wreck."
	if player.global_position.distance_to(target.global_position) >= SALVAGE_RANGE:
		return "Move closer to the wreck."
	if not GlobalState.can_accept_ore():
		return "Ore hold is full."
	if GlobalState.cargo >= GlobalState.cargo_max:
		return "Ore hold is full."
	return ""


static func use(item_id: String, player: Node3D, inv, shield_cap: float) -> bool:
	if not is_usable_now(item_id, player, inv, shield_cap):
		return false
	var effect: Dictionary = EFFECTS[item_id]
	# Salvage is activated by the UI handler directly (needs inventory remove + begin_salvage call).
	# Returning false here prevents the generic use path from double-removing the item.
	if effect.get("type") == "salvage":
		return false
	var applied = _apply_effect(effect, player, shield_cap)
	if applied:
		inv.remove(item_id)
	return applied


static func _apply_effect(effect: Dictionary, player: Node3D, shield_cap: float) -> bool:
	match effect.get("type", ""):
		"heal":
			var hp = float(player.get("health"))
			var max_hp = float(player.get("max_health"))
			player.set("health", minf(hp + float(effect["amount"]), max_hp))
			return true
		"shield_percent":
			var shield = float(player.get("current_shield"))
			var restore = shield_cap * float(effect["amount"])
			player.set("current_shield", minf(shield + restore, shield_cap))
			return true
		"reveal", "buff", "decoy", "emp":
			return true
	return false
