extends Node

# ── FactionRegistry ────────────────────────────────────────────────────────────
# Single source of truth for all faction combat profiles.
# Autoloaded as "FactionRegistry".
#
# Profile fields:
#   display_name    : String  — shown in UI / sensor scan
#   combat_role     : String  — "gunner" | "interceptor" | "tank" | "attrition" | "disruptor"
#   weapon_tier     : int     — drives damage_min/max
#   engine_tier     : int     — drives speed / flee chance
#   powerplant_tier : int     — drives combat_ap
#   hull_tier       : int     — drives max_health
#   shield_tier     : int     — drives shield mitigation
#   intelligence    : float   — 0.0 (random) → 1.0 (optimal planning)
#   weapon_dmg_mult : float   — multiplier applied to incoming WEAPON hits
#   drone_dmg_mult  : float   — multiplier applied to incoming DRONE hits
#   hull_composition: String  — shown in sensor scan ("REINFORCED ALLOY", etc.)

# ── Known factions ─────────────────────────────────────────────────────────────
const KNOWN_PROFILES: Dictionary = {
	"aurelia_interceptor": {
		"display_name": "Aurelia Interceptor",
		"combat_role": "interceptor",
		"weapon_tier": 1, "engine_tier": 2, "powerplant_tier": 1,
		"hull_tier": 1, "shield_tier": 0,
		"intelligence": 0.65,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "LIGHT COMPOSITE FRAME",
	},
	"aurelia_gunner": {
		"display_name": "Aurelia Gunner",
		"combat_role": "gunner",
		"weapon_tier": 2, "engine_tier": 1, "powerplant_tier": 1,
		"hull_tier": 1, "shield_tier": 0,
		"intelligence": 0.60,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "LIGHT COMPOSITE FRAME",
	},
	"aurelia_mining_hauler": {
		"display_name": "Aurelia Mining Hauler",
		"combat_role": "hauler",
		"weapon_tier": 0, "engine_tier": 0, "powerplant_tier": 1,
		"hull_tier": 1, "shield_tier": 0,
		"intelligence": 0.30,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "LIGHT COMPOSITE FRAME",
	},
	"vanguard_gunner": {
		"display_name": "Vanguard Gunner",
		"combat_role": "gunner",
		"weapon_tier": 2, "engine_tier": 1, "powerplant_tier": 2,
		"hull_tier": 2, "shield_tier": 1,
		"intelligence": 0.75,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "REINFORCED ALLOY PLATING",
	},
	"vanguard_interceptor": {
		"display_name": "Vanguard Interceptor",
		"combat_role": "interceptor",
		"weapon_tier": 1, "engine_tier": 2, "powerplant_tier": 2,
		"hull_tier": 1, "shield_tier": 1,
		"intelligence": 0.70,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "REINFORCED ALLOY PLATING",
	},
	"vanguard_mining_hauler": {
		"display_name": "Vanguard Mining Hauler",
		"combat_role": "hauler",
		"weapon_tier": 0, "engine_tier": 0, "powerplant_tier": 2,
		"hull_tier": 2, "shield_tier": 0,
		"intelligence": 0.30,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "REINFORCED ALLOY PLATING",
	},
	"zenith_logistics": {
		"display_name": "Zenith Logistics",
		"combat_role": "hauler",
		"weapon_tier": 0, "engine_tier": 1, "powerplant_tier": 1,
		"hull_tier": 1, "shield_tier": 0,
		"intelligence": 0.25,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "STANDARD HULL PLATING",
	},
	"zenith_mining_hauler": {
		"display_name": "Zenith Mining Hauler",
		"combat_role": "hauler",
		"weapon_tier": 0, "engine_tier": 0, "powerplant_tier": 1,
		"hull_tier": 2, "shield_tier": 0,
		"intelligence": 0.20,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "HEAVY CARGO HULL",
	},
}

# ── Unknown faction progression ────────────────────────────────────────────────
# Ordered list. Generated systems pull entries by danger_level index.
# 4 factions per band; same damage/HP budget per band, different roles/biases.
# weapon_dmg_mult < 1.0 = resistant to main weapons; drone_dmg_mult > 1.0 = drone-vulnerable.
const UNKNOWN_FACTIONS: Array = [
	# ── Band 1 (danger levels 1–4) — systems 2–5 ─────────────────────────────
	{
		"id": "rift_collective", "display_name": "Rift Collective",
		"combat_role": "gunner",
		"weapon_tier": 1, "engine_tier": 1, "powerplant_tier": 1,
		"hull_tier": 1, "shield_tier": 0, "intelligence": 0.55,
		"weapon_dmg_mult": 0.5, "drone_dmg_mult": 1.6,
		"hull_composition": "DENSE PLATE ALLOY",
	},
	{
		"id": "hollow_syndicate", "display_name": "Hollow Syndicate",
		"combat_role": "interceptor",
		"weapon_tier": 1, "engine_tier": 2, "powerplant_tier": 1,
		"hull_tier": 1, "shield_tier": 0, "intelligence": 0.60,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "LIGHT COMPOSITE FRAME",
	},
	{
		"id": "pale_march", "display_name": "Pale March",
		"combat_role": "tank",
		"weapon_tier": 1, "engine_tier": 0, "powerplant_tier": 1,
		"hull_tier": 2, "shield_tier": 0, "intelligence": 0.50,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 0.4,
		"hull_composition": "DRONE-HARDENED MESH",
	},
	{
		"id": "cinder_wake", "display_name": "Cinder Wake",
		"combat_role": "attrition",
		"weapon_tier": 1, "engine_tier": 1, "powerplant_tier": 2,
		"hull_tier": 1, "shield_tier": 0, "intelligence": 0.65,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "STANDARD HULL PLATING",
	},
	# ── Band 2 (danger levels 5–8) — systems 6–9 ─────────────────────────────
	{
		"id": "eclipse_legion", "display_name": "Eclipse Legion",
		"combat_role": "gunner",
		"weapon_tier": 2, "engine_tier": 2, "powerplant_tier": 2,
		"hull_tier": 2, "shield_tier": 1, "intelligence": 0.70,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "REINFORCED ALLOY PLATING",
	},
	{
		"id": "obsidian_pact", "display_name": "Obsidian Pact",
		"combat_role": "tank",
		"weapon_tier": 2, "engine_tier": 1, "powerplant_tier": 2,
		"hull_tier": 2, "shield_tier": 2, "intelligence": 0.65,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 0.25,
		"hull_composition": "ENERGY SHIELDING TIER 2",
	},
	{
		"id": "ashen_drift", "display_name": "Ashen Drift",
		"combat_role": "interceptor",
		"weapon_tier": 2, "engine_tier": 3, "powerplant_tier": 2,
		"hull_tier": 1, "shield_tier": 0, "intelligence": 0.75,
		"weapon_dmg_mult": 0.6, "drone_dmg_mult": 1.4,
		"hull_composition": "DENSE PLATE ALLOY",
	},
	{
		"id": "iron_chorus", "display_name": "Iron Chorus",
		"combat_role": "attrition",
		"weapon_tier": 2, "engine_tier": 1, "powerplant_tier": 3,
		"hull_tier": 2, "shield_tier": 1, "intelligence": 0.70,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "REINFORCED ALLOY PLATING",
	},
	# ── Band 3 (danger levels 9–12) — systems 10–13 ──────────────────────────
	{
		"id": "void_covenant", "display_name": "Void Covenant",
		"combat_role": "gunner",
		"weapon_tier": 3, "engine_tier": 2, "powerplant_tier": 3,
		"hull_tier": 3, "shield_tier": 2, "intelligence": 0.80,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "VOID-TEMPERED PLATING",
	},
	{
		"id": "shatter_bloc", "display_name": "Shatter Bloc",
		"combat_role": "gunner",
		"weapon_tier": 4, "engine_tier": 1, "powerplant_tier": 3,
		"hull_tier": 2, "shield_tier": 1, "intelligence": 0.75,
		"weapon_dmg_mult": 0.5, "drone_dmg_mult": 1.8,
		"hull_composition": "DENSE PLATE ALLOY — TIER 3",
	},
	{
		"id": "null_meridian", "display_name": "Null Meridian",
		"combat_role": "disruptor",
		"weapon_tier": 2, "engine_tier": 2, "powerplant_tier": 3,
		"hull_tier": 2, "shield_tier": 3, "intelligence": 0.85,
		"weapon_dmg_mult": 1.4, "drone_dmg_mult": 0.2,
		"hull_composition": "ENERGY SHIELDING TIER 3",
	},
	{
		"id": "fracture_syndicate", "display_name": "Fracture Syndicate",
		"combat_role": "interceptor",
		"weapon_tier": 3, "engine_tier": 3, "powerplant_tier": 3,
		"hull_tier": 2, "shield_tier": 1, "intelligence": 0.80,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "LIGHT COMPOSITE FRAME — TIER 3",
	},
	# ── Band 4 (danger levels 13+) — late-game / story systems ───────────────
	{
		"id": "silent_dominion", "display_name": "Silent Dominion",
		"combat_role": "tank",
		"weapon_tier": 4, "engine_tier": 2, "powerplant_tier": 4,
		"hull_tier": 4, "shield_tier": 3, "intelligence": 0.90,
		"weapon_dmg_mult": 0.4, "drone_dmg_mult": 0.4,
		"hull_composition": "UNKNOWN COMPOSITE — SENSORS DEGRADED",
	},
	{
		"id": "apex_remnant", "display_name": "Apex Remnant",
		"combat_role": "gunner",
		"weapon_tier": 4, "engine_tier": 3, "powerplant_tier": 4,
		"hull_tier": 3, "shield_tier": 2, "intelligence": 0.95,
		"weapon_dmg_mult": 1.0, "drone_dmg_mult": 1.0,
		"hull_composition": "UNKNOWN COMPOSITE — SENSORS DEGRADED",
	},
]

# ── Runtime overrides (tuning tool writes here) ────────────────────────────────
# Keys match profile keys. Values are partial dicts merged on top of the const.
var _overrides: Dictionary = {}

func _ready() -> void:
	_load_overrides()

func _load_overrides() -> void:
	var path := "user://faction_tuning.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_overrides = parsed
		print("[FactionRegistry] Loaded %d tuning overrides." % _overrides.size())

func save_overrides() -> void:
	var f := FileAccess.open("user://faction_tuning.json", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_overrides, "\t"))
	f.close()
	print("[FactionRegistry] Tuning overrides saved.")

func set_override(profile_key: String, field: String, value: Variant) -> void:
	if not _overrides.has(profile_key):
		_overrides[profile_key] = {}
	_overrides[profile_key][field] = value

func clear_overrides() -> void:
	_overrides.clear()
	var path := "user://faction_tuning.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

# ── Public API ─────────────────────────────────────────────────────────────────

## Returns the merged profile dict for a known faction key.
## Applies any runtime tuning overrides on top.
func get_profile(key: String) -> Dictionary:
	var base: Dictionary = KNOWN_PROFILES.get(key, {})
	if base.is_empty():
		push_warning("[FactionRegistry] Unknown profile key: %s" % key)
		return {}
	var result := base.duplicate()
	if _overrides.has(key):
		for k in _overrides[key]:
			result[k] = _overrides[key][k]
	return result

## Returns the unknown faction profile for a given danger level (1-based).
## danger_level 1–4 → Band 1, 5–8 → Band 2, etc.
## Cycles within the band using system_index for variety.
func get_faction_for_danger_level(danger_level: int, system_index: int = 0) -> Dictionary:
	danger_level = max(1, danger_level)
	var band_idx: int = (danger_level - 1) / 4          # which band (0, 1, 2, 3)
	var band_start: int = band_idx * 4                   # first entry in band
	var band_size: int = min(4, UNKNOWN_FACTIONS.size() - band_start)
	if band_size <= 0:
		band_start = UNKNOWN_FACTIONS.size() - 4
		band_size  = 4
	var pick: int = band_start + (system_index % band_size)
	var base: Dictionary = UNKNOWN_FACTIONS[pick].duplicate()
	var key: String = base.get("id", "unknown")
	if _overrides.has(key):
		for k in _overrides[key]:
			base[k] = _overrides[key][k]
	return base

## Stat derivation helpers — same formulas used by NPCShip.apply_faction_profile().
static func derive_damage_min(weapon_tier: int) -> float:
	return (weapon_tier + 1) * 3.5

static func derive_damage_max(weapon_tier: int) -> float:
	return (weapon_tier + 1) * 5.0

static func derive_combat_ap(powerplant_tier: int) -> int:
	return 3 + powerplant_tier

static func derive_max_health(hull_tier: int) -> float:
	return 30.0 * pow(1.6, hull_tier)
