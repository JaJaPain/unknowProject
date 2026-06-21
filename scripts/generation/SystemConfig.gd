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

var planet_count_min: int = 2
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
var story_pack: Dictionary = {}


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
	config.planet_count_min = 2
	config.planet_count_max = 3 + rng.randi_range(0, 2)
	config.station_count = 2 + rng.randi_range(0, 1)
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
	var faction_pool := local_factions.duplicate()
	if rng.randf() < 0.35:
		faction_pool.append(major_factions[rng.randi() % major_factions.size()])
	var selected_factions: Array[String] = [primary_faction]
	faction_pool.erase(primary_faction)
	var target_faction_count := 2
	if rng.randf() < 0.45:
		target_faction_count += 1
	if rng.randf() < 0.12:
		target_faction_count += 1
	target_faction_count = mini(target_faction_count, 4)
	while selected_factions.size() < target_faction_count and not faction_pool.is_empty():
		var next_index: int = rng.randi() % faction_pool.size()
		selected_factions.append(str(faction_pool[next_index]))
		faction_pool.remove_at(next_index)
	var raw_weights: Dictionary = {}
	var total_weight := 0.0
	for index in range(selected_factions.size()):
		var faction_name := selected_factions[index]
		var weight := rng.randf_range(1.2, 1.7) if index == 0 else rng.randf_range(0.5, 1.1)
		raw_weights[faction_name] = weight
		total_weight += weight
	for faction_name in selected_factions:
		config.faction_weights[faction_name] = float(raw_weights[faction_name]) / total_weight

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

	config.story_pack = _build_story_pack(config, rng)

	return config


func canonical_faction_id(faction_name: String) -> String:
	return str(faction_id_lookup.get(faction_name, "faction.%s" % faction_name))


func ship_style_for_faction(faction_name: String) -> Dictionary:
	return (
		faction_ship_styles.get(faction_name, {}) as Dictionary
	).duplicate(true)


static func _build_story_pack(
	config: SystemConfig,
	rng: RandomNumberGenerator
) -> Dictionary:
	var faction_names: Array[String] = []
	for faction_name: String in config.faction_weights.keys():
		faction_names.append(_story_faction_display(faction_name))
	if faction_names.is_empty():
		faction_names.append("independent crews")
	var primary_faction := faction_names[0]
	var secondary_faction := faction_names[0]
	if faction_names.size() > 1:
		secondary_faction = faction_names[1]
	var problem_templates: Array[String] = [
		"cargo auctions are being quietly rigged",
		"patrol routes keep changing without anyone admitting who paid",
		"ore claims are overlapping badly enough to require funeral math",
		"station permits are being sold twice and enforced three times",
		"old gate telemetry is making honest navigators very nervous",
	]
	var tension_templates: Array[String] = [
		"%s and %s are arguing over who owns the quiet lanes",
		"%s blames %s for missing haulers nobody wants to list publicly",
		"%s wants order, %s wants leverage, and the docks want hazard pay",
		"%s crews are buying silence while %s crews are buying ammunition",
	]
	var humor_templates: Array[String] = [
		"dry station gossip with jokes that sound like unpaid invoices",
		"slightly dark dock humor about broken promises and worse engines",
		"deadpan frontier jokes where the punchline is usually paperwork",
		"tired professional sarcasm from people pretending this is normal",
	]
	var problem := problem_templates[rng.randi() % problem_templates.size()]
	var tension := tension_templates[rng.randi() % tension_templates.size()] % [
		primary_faction,
		secondary_faction,
	]
	var humor := humor_templates[rng.randi() % humor_templates.size()]
	var nickname := _story_nickname(config.system_name, rng)
	return {
		"system_id": config.system_id,
		"system_name": config.system_name,
		"local_nickname": nickname,
		"station_economy_problem": problem,
		"active_tension": tension,
		"danger_summary": _story_danger_summary(config.difficulty_tier),
		"resource_hook": _story_resource_hook(config.star_type, rng),
		"humor_guidance": humor,
		"local_rumors": [
			"People call this place %s when comms are private. Nobody agrees whether that is affectionate." % nickname,
			"%s, which is why every clean invoice here looks suspicious." % problem.capitalize(),
			"The lounge version is simple: %s. The real version probably has more knives." % tension,
		],
		"mission_seeds": [
			"verify a disputed cargo route",
			"recover proof from a wreck tied to the local tension",
			"move supplies before the station problem gets expensive",
			"thin out raiders taking advantage of the confusion",
		],
		"gate_mystery_hints": [
			"gate logs show a timing mismatch nobody can explain",
			"old nav chatter references a return path that should not exist",
			"someone is paying to keep outbound route scans boring",
		],
		"rumor_clue_slots": [
			"lounge_contact",
			"public_board",
			"kaelen_arrival",
		],
	}


static func _story_faction_display(faction_name: String) -> String:
	var clean := faction_name.strip_edges()
	if clean.begins_with("gen_"):
		clean = clean.trim_prefix("gen_")
	var parts := clean.replace("_", " ").split(" ", false)
	var titled: Array[String] = []
	for part in parts:
		var lower := str(part).to_lower()
		if lower.length() <= 2 and lower.is_valid_int():
			continue
		titled.append(lower.substr(0, 1).to_upper() + lower.substr(1))
	if titled.is_empty():
		return "independent crews"
	return " ".join(titled)


static func _story_nickname(system_name: String, rng: RandomNumberGenerator) -> String:
	var roots := [
		"the Bent Ledger",
		"the Quiet Burn",
		"the Long Toll",
		"the Wrong End",
		"the Cold Receipt",
	]
	if rng.randf() < 0.45:
		return roots[rng.randi() % roots.size()]
	var first_word := system_name.get_slice(" ", 0)
	if first_word.is_empty():
		first_word = "Frontier"
	return "%s's Bad Habit" % first_word


static func _story_danger_summary(tier: int) -> String:
	match tier:
		1:
			return "manageable trouble with enough warning to make bad choices"
		2:
			return "active danger around stations, belts, and disputed routes"
		_:
			return "volatile space where travel plans should include apology money"


static func _story_resource_hook(
	star_type: String,
	rng: RandomNumberGenerator
) -> String:
	var hooks := {
		"yellow": ["stable ore pockets", "cleaner solar charge windows"],
		"blue": ["high-energy dust traces", "volatile sensor ghosts"],
		"orange": ["heat-scored ore seams", "old refinery slag fields"],
		"red": ["cold salvage pockets", "radiation-baked hull fragments"],
		"white": ["bright ice signatures", "overexposed nav anomalies"],
	}
	var options: Array = hooks.get(star_type, ["ordinary ore pockets"])
	return str(options[rng.randi() % options.size()])
