extends RefCounted

const EFFECTS = {
	"repair_kit": {"type": "heal", "amount": 25.0},
	"shield_cell": {"type": "shield_percent", "amount": 0.5},
	"scanner_probe": {"type": "reveal", "duration_seconds": 60.0},
}


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
		"reveal":
			return true
	return false


static func use(item_id: String, player: Node3D, inv, shield_cap: float) -> bool:
	if not is_usable_now(item_id, player, inv, shield_cap):
		return false
	var effect: Dictionary = EFFECTS[item_id]
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
		"reveal":
			return true
	return false
