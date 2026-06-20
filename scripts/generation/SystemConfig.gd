class_name SystemConfig
extends RefCounted

var system_name: String = "Uncharted System"
var system_id: String = ""
var legacy_id: String = ""
var seed_value: int = 0

var star_type: String = "yellow"
var star_color: Color = Color(1.0, 0.95, 0.85)
var star_energy: float = 3.0
var star_light_energy: float = 1.2

var ambient_color: Color = Color(0.15, 0.18, 0.25)
var ambient_energy: float = 0.4

var planet_count_min: int = 1
var planet_count_max: int = 4
var station_count: int = 2
var difficulty_tier: int = 1
var difficulty_multiplier: float = 1.0

var faction_weights: Dictionary = {}
var faction_id_lookup: Dictionary = {}
var faction_ship_styles: Dictionary = {}
var npc_patrol_count: int = 6
var npc_minor_chance: float = 0.15
var npc_minor_max: int = 2

var outbound_gate_count: int = 1

var starfield_seed: float = 0.0
var starfield_tint: Color = Color(0.9, 0.92, 1.0)

var nebula_seed: int = 0
var nebula_colors: Array[Color] = []
var nebula_brightness: float = 0.5
var nebula_layer_count: int = 3


static func from_seed(
	name: String,
	id: String,
	seed_val: int,
	frontier_factions: Array = []
) -> SystemConfig:
	var config := SystemConfig.new()
	config.system_name = name
	config.system_id = id
	config.legacy_id = id.replace(".", "_")
	config.seed_value = seed_val

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var star_types := ["yellow", "blue", "orange", "red", "white"]
	var star_idx := rng.randi() % star_types.size()
	config.star_type = star_types[star_idx]

	match config.star_type:
		"yellow":
			config.star_color = Color(1.0, 0.92, 0.7)
			config.star_energy = 3.0
			config.star_light_energy = 1.2
			config.ambient_color = Color(0.15, 0.17, 0.22)
		"blue":
			config.star_color = Color(0.75, 0.85, 1.0)
			config.star_energy = 3.5
			config.star_light_energy = 1.45
			config.ambient_color = Color(0.12, 0.16, 0.3)
		"orange":
			config.star_color = Color(1.0, 0.7, 0.4)
			config.star_energy = 2.8
			config.star_light_energy = 1.1
			config.ambient_color = Color(0.18, 0.14, 0.1)
		"red":
			config.star_color = Color(1.0, 0.4, 0.3)
			config.star_energy = 2.2
			config.star_light_energy = 0.9
			config.ambient_color = Color(0.2, 0.1, 0.1)
		"white":
			config.star_color = Color(0.95, 0.97, 1.0)
			config.star_energy = 4.0
			config.star_light_energy = 1.6
			config.ambient_color = Color(0.18, 0.2, 0.25)

	config.ambient_energy = 0.35 + rng.randf_range(0.0, 0.15)
	config.planet_count_min = 1
	config.planet_count_max = 2 + rng.randi_range(0, 2)
	config.station_count = 1 + rng.randi_range(0, 2)
	config.difficulty_tier = 1 + rng.randi_range(0, 2)

	match config.difficulty_tier:
		1: config.difficulty_multiplier = 1.0
		2: config.difficulty_multiplier = 1.15
		3: config.difficulty_multiplier = 1.30
	config.npc_patrol_count = 5 + config.difficulty_tier

	var local_factions: Array[String] = []
	for faction in frontier_factions:
		if not faction is Dictionary:
			continue
		var legacy_id := str(faction.get("legacy_id", "")).strip_edges()
		var faction_id := str(faction.get("id", "")).strip_edges()
		if legacy_id.is_empty() or faction_id.is_empty():
			continue
		local_factions.append(legacy_id)
		config.faction_id_lookup[legacy_id] = faction_id
		if faction.get("ship_style", {}) is Dictionary:
			config.faction_ship_styles[legacy_id] = (
				faction.get("ship_style", {}) as Dictionary
			).duplicate(true)
	if local_factions.size() < 2:
		local_factions = [
		"reavers",
		"obsidian",
		"dustborn",
		"wraiths",
		"ironclad",
		]
		config.faction_id_lookup.clear()
		config.faction_ship_styles.clear()
	for faction_name in local_factions:
		if not config.faction_id_lookup.has(faction_name):
			config.faction_id_lookup[faction_name] = "faction.%s" % faction_name
	var major_factions: Array[String] = ["zenith", "aurelia", "vanguard"]
	for faction_name in major_factions:
		config.faction_id_lookup[faction_name] = "faction.%s" % faction_name
	var primary_idx: int = rng.randi() % local_factions.size()
	var primary_faction: String = local_factions[primary_idx]
	var has_second: bool = rng.randf() < 0.6
	if has_second:
		var second_pool := local_factions.duplicate()
		if rng.randf() < 0.35:
			second_pool.append(major_factions[rng.randi() % major_factions.size()])
		second_pool.erase(primary_faction)
		var second_faction: String = second_pool[rng.randi() % second_pool.size()]
		var split: float = rng.randf_range(0.55, 0.75)
		config.faction_weights[primary_faction] = split
		config.faction_weights[second_faction] = 1.0 - split
	else:
		config.faction_weights[primary_faction] = 1.0

	config.outbound_gate_count = 1 + (1 if rng.randf() < 0.4 else 0)

	config.starfield_seed = float(seed_val % 10000)
	config.starfield_tint = config.star_color.lerp(Color(0.9, 0.92, 1.0), 0.7)

	config.nebula_seed = (seed_val * 7 + 3491) % 10000
	config.nebula_brightness = rng.randf_range(0.3, 0.6)
	config.nebula_layer_count = rng.randi_range(1, 2)

	var base_hue := rng.randf()
	var c1 := Color.from_hsv(fmod(base_hue, 1.0), rng.randf_range(0.4, 0.7), rng.randf_range(0.5, 0.8))
	var c2 := Color.from_hsv(fmod(base_hue + rng.randf_range(0.08, 0.2), 1.0), rng.randf_range(0.3, 0.6), rng.randf_range(0.4, 0.9))
	config.nebula_colors = [c1, c2] as Array[Color]

	var sun_angle := rng.randf_range(0.0, TAU)
	var _sun_dir := Vector3(cos(sun_angle), rng.randf_range(0.25, 0.5), sin(sun_angle)).normalized()

	return config


func canonical_faction_id(faction_name: String) -> String:
	return str(faction_id_lookup.get(faction_name, "faction.%s" % faction_name))


func ship_style_for_faction(faction_name: String) -> Dictionary:
	return (
		faction_ship_styles.get(faction_name, {}) as Dictionary
	).duplicate(true)
