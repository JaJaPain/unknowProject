class_name ShipGenerator
extends RefCounted

const BLENDER_PATH := "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe"
const GENERATOR_DIR := "res://tools/ship_generator"
const SHIPS_SUBDIR := "ships"

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

static var active_campaign_path: String = ""


static func output_dir() -> String:
	if active_campaign_path.is_empty():
		return "user://ships"
	return active_campaign_path + "/" + SHIPS_SUBDIR


static func generate(
	seed_str: String,
	ship_class: String = "",
	faction: String = "",
	faction_style: Dictionary = {}
) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_str.hash()

	if ship_class.is_empty():
		ship_class = SHIP_CLASSES[rng.randi() % SHIP_CLASSES.size()]

	var texture: String = str(
		faction_style.get("texture", FACTION_TEXTURES.get(faction, "metal.png"))
	)
	var emblem: String = str(
		faction_style.get("emblem", FACTION_EMBLEMS.get(faction, "none"))
	)
	var metallic_min := float(faction_style.get("metallic_min", METALLIC_RANGE.x))
	var metallic_max := float(faction_style.get("metallic_max", METALLIC_RANGE.y))
	var metallic: float = rng.randf_range(
		minf(metallic_min, metallic_max),
		maxf(metallic_min, metallic_max)
	)

	var dir := output_dir()
	_ensure_dir(dir)
	var output_path: String = globalized_path(seed_str)
	var script_path: String = ProjectSettings.globalize_path(GENERATOR_DIR) + "/generate_single.py"

	if FileAccess.file_exists(dir + "/" + seed_str + ".glb"):
		return dir + "/" + seed_str + ".glb"

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
			return dir + "/" + seed_str + ".glb"

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


static func globalized_path(seed_str: String) -> String:
	return ProjectSettings.globalize_path(output_dir() + "/" + seed_str + ".glb")


static func has_cached(seed_str: String) -> bool:
	return FileAccess.file_exists(output_dir() + "/" + seed_str + ".glb")


static func load_runtime(seed_str: String) -> Node3D:
	var abs_path := globalized_path(seed_str)
	if not FileAccess.file_exists(abs_path):
		return null
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var err := gltf_doc.append_from_file(abs_path, gltf_state)
	if err != OK:
		push_warning("[ShipGenerator] GLTF load failed for '%s': %d" % [seed_str, err])
		return null
	var scene := gltf_doc.generate_scene(gltf_state)
	if scene == null:
		push_warning("[ShipGenerator] GLTF scene generation failed for '%s'." % seed_str)
	return scene


static func _ensure_dir(dir_path: String) -> void:
	var global := ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(global):
		DirAccess.make_dir_recursive_absolute(global)
