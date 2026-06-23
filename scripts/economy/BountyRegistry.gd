extends RefCounted

static var _shared = null

var _bounties: Array = []
var _injected_bounties: Array = []  # story-injected; survive set_bounties() calls

const KAELEN_COLOR := Color(0.85, 0.5, 1.0)


static func shared() -> Object:
	if _shared == null:
		_shared = new()
	return _shared


static func reset() -> void:
	_shared = null


func set_bounties(bounties: Array) -> void:
	_bounties = bounties.duplicate(true)


func get_active_bounties() -> Array:
	var all: Array = _bounties + _injected_bounties
	return all.filter(func(b): return b.get("kills_credited", 0) < _cap(b))


# StoryManager: inject a bounty that survives normal set_bounties() refresh.
# bounty dict shape: {faction, system_id, payout_per_kill, cap, kaelen_line}
func inject_story_bounty(bounty: Dictionary) -> void:
	var b: Dictionary = bounty.duplicate(true)
	b["kills_credited"] = 0
	b["story_injected"] = true
	_injected_bounties.append(b)


func clear_injected_bounties() -> void:
	_injected_bounties = []


# Returns the credit payout if this kill earns a bounty, otherwise 0.
# Increments kills_credited. Caller is responsible for paying credits and
# emitting Kaelen chat — keeping GlobalState access out of this class so
# it remains unit-testable.
func check_kill(faction: String, system_id: String) -> int:
	for b in (_bounties + _injected_bounties):
		if b.get("faction", "") != faction:
			continue
		if b.get("system_id", "") != system_id:
			continue
		var cap: int = _cap(b)
		var credited: int = b.get("kills_credited", 0)
		if cap != -1 and credited >= cap:
			continue
		b["kills_credited"] = credited + 1
		return int(b.get("payout_per_kill", 8))
	return 0


# Returns the confirm chat line for a just-landed bounty hit.
func confirm_line(faction: String, payout: int) -> String:
	for b in _bounties:
		if b.get("faction", "") != faction:
			continue
		var remaining: int = _cap(b) - int(b.get("kills_credited", 0))
		var lines: Array = [
			"Tagged. %d SC deposited. Keep it up, Shiny." % payout,
			"Receipt received. %d SC your way." % payout,
			"That's one for the %s tally. %d SC." % [faction.capitalize(), payout],
		]
		var base: String = lines[randi() % lines.size()]
		if _cap(b) != -1 and remaining <= 0:
			base += " That closes the contract."
		return base
	return "Tagged. %d SC deposited." % payout


# Returns the announcement lines for all active bounties (caller emits them).
func announcement_lines() -> Array:
	var active: Array = get_active_bounties()
	if active.is_empty():
		return []
	if active.size() == 1:
		var b = active[0]
		var line: String = b.get("kaelen_line", "")
		if line.is_empty():
			return []
		return [line]
	# Two-faction — combine into one line
	var factions: Array = active.map(func(bx): return bx.get("faction", "?").capitalize())
	var payouts: Array = active.map(func(bx): return str(bx.get("payout_per_kill", 8)) + " SC")
	return ["I've got paper on the %s AND the %s this week — %s and %s a hull, after my cut." % [
		factions[0], factions[1], payouts[0], payouts[1]
	]]


func clear() -> void:
	_bounties = []


# ── private ──────────────────────────────────────────────────────────────────

func _cap(b: Dictionary) -> int:
	return int(b.get("cap", -1))
