class_name IllegalMiningEnforcement
extends RefCounted

const HEAT_DURATION_MSEC := 300000
const MAX_ACTIVE_RESPONSE_GROUPS := 1
const RESPONSE_SHIP_COUNT := 2
const BASE_FINE_CREDITS := 250

var response_groups: Dictionary = {}
var outstanding_fines: Dictionary = {}


func report_violation(
	system_id: String,
	belt_id: String,
	owner_faction: String,
	now_msec: int
) -> Dictionary:
	clear_expired(now_msec)
	var key := _key(system_id, owner_faction)
	var previous_fine := int(outstanding_fines.get(key, 0))
	outstanding_fines[key] = previous_fine + BASE_FINE_CREDITS

	if response_groups.has(key):
		var active_group: Dictionary = response_groups[key]
		active_group["expires_at_msec"] = now_msec + HEAT_DURATION_MSEC
		response_groups[key] = active_group
		return {
			"accepted": true,
			"dispatch": false,
			"reason": "already_active",
			"faction": owner_faction,
			"belt_id": belt_id,
			"active_groups": active_response_count(system_id, owner_faction),
			"fine_credits": int(outstanding_fines[key]),
			"expires_at_msec": int(active_group["expires_at_msec"]),
		}

	if active_response_count(system_id, owner_faction) >= MAX_ACTIVE_RESPONSE_GROUPS:
		return {
			"accepted": true,
			"dispatch": false,
			"reason": "response_cap",
			"faction": owner_faction,
			"belt_id": belt_id,
			"active_groups": active_response_count(system_id, owner_faction),
			"fine_credits": int(outstanding_fines[key]),
			"expires_at_msec": 0,
		}

	var group := {
		"system_id": system_id,
		"belt_id": belt_id,
		"faction": owner_faction,
		"reported_at_msec": now_msec,
		"expires_at_msec": now_msec + HEAT_DURATION_MSEC,
		"ship_count": RESPONSE_SHIP_COUNT,
	}
	response_groups[key] = group
	return {
		"accepted": true,
		"dispatch": true,
		"reason": "new_response",
		"faction": owner_faction,
		"belt_id": belt_id,
		"active_groups": active_response_count(system_id, owner_faction),
		"fine_credits": int(outstanding_fines[key]),
		"ship_count": RESPONSE_SHIP_COUNT,
		"expires_at_msec": int(group["expires_at_msec"]),
	}


func clear_expired(now_msec: int) -> int:
	var removed := 0
	for key in response_groups.keys():
		var group: Dictionary = response_groups[key]
		if now_msec >= int(group.get("expires_at_msec", 0)):
			response_groups.erase(key)
			removed += 1
	return removed


func active_response_count(system_id: String, owner_faction: String = "") -> int:
	var count := 0
	for group in response_groups.values():
		var data: Dictionary = group
		if str(data.get("system_id", "")) != system_id:
			continue
		if not owner_faction.is_empty() \
				and str(data.get("faction", "")) != owner_faction:
			continue
		count += 1
	return count


func is_heat_active(system_id: String, owner_faction: String) -> bool:
	return response_groups.has(_key(system_id, owner_faction))


func fine_due(system_id: String, owner_faction: String) -> int:
	return int(outstanding_fines.get(_key(system_id, owner_faction), 0))


func pay_fine(system_id: String, owner_faction: String, credits_available: int) -> Dictionary:
	var key := _key(system_id, owner_faction)
	var due := int(outstanding_fines.get(key, 0))
	if due <= 0:
		return {
			"paid": true,
			"amount_paid": 0,
			"remaining_due": 0,
			"heat_cleared": false,
		}
	if credits_available < due:
		return {
			"paid": false,
			"amount_paid": 0,
			"remaining_due": due,
			"heat_cleared": response_groups.has(key),
		}
	outstanding_fines.erase(key)
	var had_heat := response_groups.has(key)
	response_groups.erase(key)
	return {
		"paid": true,
		"amount_paid": due,
		"remaining_due": 0,
		"heat_cleared": had_heat,
	}


static func mark_enforcement_ship(ship: Node, owner_faction: String, system_id: String) -> void:
	if ship == null:
		return
	ship.set_meta("is_code_enforcement", true)
	ship.set_meta("enforcement_faction", owner_faction)
	ship.set_meta("enforcement_system_id", system_id)


static func is_enforcement_ship(ship: Node) -> bool:
	return ship != null and bool(ship.get_meta("is_code_enforcement", false))


func _key(system_id: String, owner_faction: String) -> String:
	return "%s|%s" % [system_id, owner_faction]
