class_name ShipGenerator
extends RefCounted

const BLENDER_PATH := "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe"
const GENERATOR_DIR := "res://tools/ship_generator"
const OUTPUT_DIR := "res://assets/ships/generated"

const SHIP_CLASSES := ["fighter", "hauler"]

const FACTION_TEXTURES := {
	"zenith": "NavyBlueMetal.png",
	"aurelia": "ForestGreenMetal.png",
	"vanguard": "RedMetal.png",
	"": "metal.png",
}

const FACTION_EMBLEMS := {
	"zenith": "ZenithBadge.png",
	"aurelia": "AurelliaBadge.png",
	"vanguard": "VanguardBadge.png",
	"": "none",
}

const METALLIC_RANGE := Vector2(0.7, 0.95)


static func generate(seed_str: String, ship_class: String = "", faction: String = "") -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_str.hash()

	if ship_class.is_empty():
		ship_class = SHIP_CLASSES[rng.randi() % SHIP_CLASSES.size()]

	var texture: String = FACTION_TEXTURES.get(faction, "metal.png")
	var emblem: String = FACTION_EMBLEMS.get(faction, "none")
	var metallic: float = rng.randf_range(METALLIC_RANGE.x, METALLIC_RANGE.y)

	var output_path: String = ProjectSettings.globalize_path(OUTPUT_DIR) + "/" + seed_str + ".glb"
	var script_path: String = ProjectSettings.globalize_path(GENERATOR_DIR) + "/generate_single.py"

	if FileAccess.file_exists(OUTPUT_DIR + "/" + seed_str + ".glb"):
		return OUTPUT_DIR + "/" + seed_str + ".glb"

	var args: PackedStringArray = PackedStringArray([
		"--background",
		"--python", script_path,
		"--",
		"--seed", seed_str,
		"--class", ship_class,
		"--texture", texture,
		"--emblem", emblem,
		"--normal", "hull_normal.png",
		"--metallic", str(metallic),
		"--output", output_path,
	])

	var max_attempts := 10
	for attempt in range(max_attempts):
		var current_seed: String = seed_str if attempt == 0 else "%s_%d" % [seed_str, randi()]
		var current_args: PackedStringArray = args.duplicate()
		if attempt > 0:
			current_args[current_args.find(seed_str)] = current_seed

		var exit_code: int = OS.execute(BLENDER_PATH, current_args)
		if exit_code == 0 and FileAccess.file_exists(output_path):
			return OUTPUT_DIR + "/" + seed_str + ".glb"

		if exit_code == 1:
			push_warning("[ShipGenerator] Ship '%s' rejected (missing hardpoints/thrusters), attempt %d/%d." % [current_seed, attempt + 1, max_attempts])
		else:
			push_warning("[ShipGenerator] Blender exited with code %d for seed '%s'." % [exit_code, current_seed])
			break

	push_warning("[ShipGenerator] Failed to generate valid ship for seed '%s' after %d attempts." % [seed_str, max_attempts])
	return ""


static func generate_for_system(system_seed: int, ship_index: int, faction: String = "") -> String:
	var seed_str: String = "ship_%d_%d" % [system_seed, ship_index]
	return generate(seed_str, "", faction)
