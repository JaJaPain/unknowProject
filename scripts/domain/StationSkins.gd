extends RefCounted

## Which model and finish ("skin") each station in a system wears (Abe,
## 2026-10-04): main stations are the kilometre-scale models, outposts are
## ChatGPT's Kestrel Depot and Crown Haven, and a new system never repeats a
## skin the system before it used. Chosen once, when the system is generated,
## and saved with its SystemConfig (station_skins: main first, then outposts).

const MAIN := [
	"res://assets/stations/cinder_anchorage.glb",
	"res://assets/stations/cinder_foundry_union.glb",
	"res://assets/stations/cinder_polar_research.glb",
	"res://assets/stations/cinder_red_corsair.glb",
	"res://assets/stations/meridian_exchange.glb",
	"res://assets/stations/meridian_blackwake_syndicate.glb",
	"res://assets/stations/meridian_helios_embassy.glb",
	"res://assets/stations/meridian_verdant_exchange.glb",
]
const OUTPOST := [
	"res://assets/outposts/kestrel_depot_industrial.glb",
	"res://assets/outposts/kestrel_depot_pirate.glb",
	"res://assets/outposts/kestrel_depot_research.glb",
	"res://assets/outposts/crown_haven_corporate.glb",
	"res://assets/outposts/crown_haven_merchant.glb",
	"res://assets/outposts/crown_haven_pirate.glb",
]
## The start system's, as placed in scenes/systems/system_start.tscn
## (Greywake, Iron Reach, Kova).
const START := [
	"res://assets/stations/cinder_anchorage.glb",
	"res://assets/outposts/kestrel_depot_industrial.glb",
	"res://assets/outposts/crown_haven_corporate.glb",
]


## The skins a system in `registry` wears: its saved choice, or the start
## system's (the one system that isn't generated).
static func of_system(registry: Object, system_id: String) -> Array:
	if registry != null and registry.has_method("get_generated_config"):
		var config = registry.call("get_generated_config", system_id)
		if config != null:
			return (config.get("station_skins") as Array).duplicate()
	return START.duplicate()


## Choose `config`'s skins once, avoiding the system it's reached from.
static func assign(config: Object, previous_skins: Array) -> void:
	var count: int = maxi(int(config.get("station_count")), 1)
	config.set("station_skins", pick(int(config.get("seed_value")), count - 1, previous_skins))


static func is_outpost_model(path: String) -> bool:
	return OUTPOST.has(path)


## Skins for a system with one main station and `outposts` outposts, none of
## them in `avoid` (the previous system's) while there are others to choose
## from, and no two outposts alike while that's possible.
static func pick(seed_value: int, outposts: int, avoid: Array) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x5717
	var out: Array[String] = [_draw(rng, MAIN, avoid, [])]
	for i in maxi(outposts, 0):
		out.append(_draw(rng, OUTPOST, avoid, out))
	return out


static func _draw(rng: RandomNumberGenerator, pool: Array, avoid: Array, taken: Array) -> String:
	var fresh: Array = pool.filter(func(p): return not avoid.has(p) and not taken.has(p))
	if fresh.is_empty():
		fresh = pool.filter(func(p): return not avoid.has(p))
	if fresh.is_empty():
		fresh = pool
	return str(fresh[rng.randi() % fresh.size()])
