extends RefCounted

## The ores a belt can hold (vision plan, Phase 4). Silicate is the common
## ore every system has; the others are what premise cards ask for by name.
## Prices are multiples of silicate's (1 SC per m³ at a station). Tints stay
## clear of red, which marks tech-grade seams.
##
## PURE: GlobalState keeps the hold's and storage's mix by type; Asteroid
## reads the tint; SystemProfile decides which ores a system's belts carry.

const DEFAULT := "silicate"

const TYPES := {
	"silicate": {"display": "Silicate", "price": 1.0, "tint": Color(1.0, 1.0, 1.0), "glow": 0.0},
	"water_ice": {"display": "Water ice", "price": 1.3, "tint": Color(0.72, 0.88, 1.0), "glow": 0.0},
	"ferrite": {"display": "Ferrite", "price": 1.6, "tint": Color(0.52, 0.56, 0.64), "glow": 0.0},
	"cuprite": {"display": "Cuprite", "price": 2.2, "tint": Color(0.45, 0.78, 0.62), "glow": 0.0},
	"thorium": {"display": "Thorium", "price": 4.0, "tint": Color(0.86, 0.92, 0.42), "glow": 0.35},
}


static func is_known(ore_type: String) -> bool:
	return TYPES.has(ore_type)


## A known ore id, or silicate.
static func normalize(ore_type: String) -> String:
	var id := ore_type.strip_edges().to_lower().replace(" ", "_")
	return id if TYPES.has(id) else DEFAULT


static func display(ore_type: String) -> String:
	return str(TYPES[normalize(ore_type)]["display"])


static func price(ore_type: String) -> float:
	return float(TYPES[normalize(ore_type)]["price"])


static func tint(ore_type: String) -> Color:
	return TYPES[normalize(ore_type)]["tint"]


static func glow(ore_type: String) -> float:
	return float(TYPES[normalize(ore_type)]["glow"])


## A mix reconciled against the true total: unknown types become silicate,
## ore the mix does not account for is silicate (old saves, code that sets the
## total directly), and a mix larger than the total shrinks evenly.
static func reconcile(mix: Dictionary, total: float) -> Dictionary:
	var out := {}
	var sum := 0.0
	for key in mix:
		var amount := maxf(0.0, float(mix[key]))
		if amount <= 0.0:
			continue
		var id := normalize(str(key))
		out[id] = float(out.get(id, 0.0)) + amount
		sum += amount
	total = maxf(0.0, total)
	if total <= 0.0:
		return {}
	if sum > total + 0.001:
		var scale := total / sum
		for id in out:
			out[id] = float(out[id]) * scale
	elif sum < total - 0.001:
		out[DEFAULT] = float(out.get(DEFAULT, 0.0)) + (total - sum)
	return out


## Takes `amount` out of `mix` (reconciled, total `total`). With `ore_type`,
## only that type; otherwise evenly across types. Returns [new_mix, removed].
static func take(mix: Dictionary, total: float, amount: float, ore_type: String = "") -> Array:
	var m := reconcile(mix, total)
	amount = maxf(0.0, amount)
	if not ore_type.is_empty():
		var id := normalize(ore_type)
		var have := float(m.get(id, 0.0))
		var removed := minf(have, amount)
		if have - removed <= 0.0001:
			m.erase(id)
		else:
			m[id] = have - removed
		return [m, removed]
	var all := 0.0
	for id in m:
		all += float(m[id])
	if all <= 0.0:
		return [{}, 0.0]
	var share := minf(1.0, amount / all)
	var left := {}
	for id in m:
		var remaining := float(m[id]) * (1.0 - share)
		if remaining > 0.0001:
			left[id] = remaining
	return [left, minf(amount, all)]


## What a mix sells for at `rate` SC per m³ of silicate.
static func value(mix: Dictionary, rate: float = 1.0) -> int:
	var total := 0.0
	for id in mix:
		total += float(mix[id]) * price(str(id)) * rate
	return int(round(total))


## Short description for the HUD: the main type, and how many others.
static func summary(mix: Dictionary) -> String:
	var ids := mix.keys()
	if ids.is_empty():
		return ""
	ids.sort_custom(func(a, b): return float(mix[a]) > float(mix[b]))
	if ids.size() == 1:
		return display(str(ids[0]))
	return "%s +%d" % [display(str(ids[0])), ids.size() - 1]
