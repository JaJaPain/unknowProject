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


## Icons (assets/OreIcons.png, ChatGPT 2026-09-28): a 3x2 sheet of 512px
## cells, silicate / water ice / ferrite, cuprite / thorium / hydrogen fuel.
## The inset drops each cell's painted frame.
const ICON_SHEET := "res://assets/OreIcons.png"
const ICON_ORDER := ["silicate", "water_ice", "ferrite", "cuprite", "thorium", "fuel"]
const ICON_CELL := 512
const ICON_INSET := 44


## The icon for an ore type, or "fuel"; null if unknown or the sheet is missing.
static func icon(ore_type: String) -> Texture2D:
	var idx := ICON_ORDER.find(ore_type)
	if idx < 0 or not ResourceLoader.exists(ICON_SHEET):
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = load(ICON_SHEET)
	atlas.region = Rect2((idx % 3) * ICON_CELL + ICON_INSET, floori(idx / 3.0) * ICON_CELL + ICON_INSET,
		ICON_CELL - ICON_INSET * 2, ICON_CELL - ICON_INSET * 2)
	return atlas


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


## Ore this system's belts don't carry sells for more here (Abe, 2026-10-02):
## hauling it in from where it's mined is a trade run. Silicate is everywhere.
const IMPORT_PREMIUM := 1.5


## Whether `ore_type` fetches the import premium in a system with `local_mix`
## (its belts, type -> share). An empty local mix means unknown: no premium.
static func is_imported(ore_type: String, local_mix: Dictionary) -> bool:
	var id := normalize(ore_type)
	if local_mix.is_empty() or id == "silicate":
		return false
	return float(local_mix.get(id, 0.0)) <= 0.0


## What a mix sells for at `rate` SC per m³ of silicate; in a system whose
## belts are `local_mix`, ores it doesn't have earn IMPORT_PREMIUM.
static func value(mix: Dictionary, rate: float = 1.0, local_mix: Dictionary = {}) -> int:
	var total := 0.0
	for id in mix:
		var premium := IMPORT_PREMIUM if is_imported(str(id), local_mix) else 1.0
		total += float(mix[id]) * price(str(id)) * rate * premium
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


## Upgrades ask for ore by type, climbing with the tier (Abe, playtest
## 2026-10-08 finding 1): tier 2 silicate; 3 silicate and ferrite; 4 ferrite
## and cuprite; 5 cuprite and thorium. Water ice stays for fuel. Each tier's
## cost_ore total is split by these shares.
const UPGRADE_ORE_LADDER := {
	2: [["silicate", 1.0]],
	3: [["silicate", 0.6], ["ferrite", 0.4]],
	4: [["ferrite", 0.5], ["cuprite", 0.5]],
	5: [["cuprite", 0.5], ["thorium", 0.5]],
}


## {ore type: m³} for a tier's `cost_ore`, whole numbers adding up to it.
static func split_upgrade_ore(cost_ore: int, tier: int) -> Dictionary:
	var out := {}
	if cost_ore <= 0:
		return out
	var shares: Array = UPGRADE_ORE_LADDER.get(clampi(tier, 2, 5), UPGRADE_ORE_LADDER[2])
	var given := 0
	for i in shares.size():
		var ore := str(shares[i][0])
		var amount := cost_ore - given if i == shares.size() - 1 else int(round(float(cost_ore) * float(shares[i][1])))
		if amount > 0:
			out[ore] = amount
			given += amount
	return out
