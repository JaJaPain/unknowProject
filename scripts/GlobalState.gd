extends Node

# ── Ship Upgrade Caps ─────────────────────────────────────────────────────────
# Per-ship-class hard caps for every upgradeable stat. The current values are
# the starter-ship (INDYMiner) caps. If you add a heavier hauler ship class
# later, give it a different caps table.
#
# "max_level" is computed from cap vs base — change the cap and the upgrade
# list auto-extends. The maintenance bay UI reads these to render level text
# and disable buttons when maxed.
const SHIP_BASE_STATS = {
	"cargo_max_m3":       100.0,
	"mining_laser_yield": 1.0,
	"mining_cooldown":    1.0,
	"weapon_damage":      20.0,
	"weapon_cooldown":    0.75,
	"shield_capacity":    0.0,
	"shield_regen_delay": 60.0,
	"shield_regen_rate":  0.0,
	"engine_speed_mult":  1.0,
	"acceleration_mult":  1.0,
	"ignore_cargo_mass":  false,
	"hull_armor":         0.0,
	"max_health":         100.0,
}
const UPGRADE_TREE = {
	"weapons": {
		"base_power": 50,
		"branches": {
			"rapid": {
				2: { "cost_cr": 200, "cost_ore": 50, "power": 60, "stats": {"weapon_cooldown": 0.6, "weapon_damage": 20} },
				3: { "cost_cr": 400, "cost_ore": 100, "power": 70, "stats": {"weapon_cooldown": 0.45, "weapon_damage": 20} },
				4: { "cost_cr": 800, "cost_ore": 200, "power": 80, "stats": {"weapon_cooldown": 0.35, "weapon_damage": 20} },
				5: { "cost_cr": 1600, "cost_ore": 400, "power": 100, "stats": {"weapon_cooldown": 0.25, "weapon_damage": 20, "has_max_rapid_weapon": true} }
			},
			"heavy": {
				2: { "cost_cr": 200, "cost_ore": 50, "power": 60, "stats": {"weapon_cooldown": 0.8, "weapon_damage": 30} },
				3: { "cost_cr": 400, "cost_ore": 100, "power": 70, "stats": {"weapon_cooldown": 0.9, "weapon_damage": 45} },
				4: { "cost_cr": 800, "cost_ore": 200, "power": 80, "stats": {"weapon_cooldown": 1.0, "weapon_damage": 65} },
				5: { "cost_cr": 1600, "cost_ore": 400, "power": 100, "stats": {"weapon_cooldown": 1.1, "weapon_damage": 90, "has_max_heavy_weapon": true} }
			}
		}
	},
	"engine": {
		"base_power": 100,
		"branches": {
			"speed": {
				2: { "cost_cr": 250, "cost_ore": 0, "power": 110, "stats": {"engine_speed_mult": 1.2, "acceleration_mult": 1.2} },
				3: { "cost_cr": 500, "cost_ore": 50, "power": 120, "stats": {"engine_speed_mult": 1.4, "acceleration_mult": 1.4} },
				4: { "cost_cr": 1000, "cost_ore": 100, "power": 140, "stats": {"engine_speed_mult": 1.6, "acceleration_mult": 1.6} },
				5: { "cost_cr": 2000, "cost_ore": 200, "power": 160, "stats": {"engine_speed_mult": 1.9, "acceleration_mult": 1.9, "has_max_speed_engine": true} }
			},
			"hauler": {
				2: { "cost_cr": 250, "cost_ore": 100, "power": 110, "stats": {"ignore_cargo_mass": true, "engine_speed_mult": 1.0, "acceleration_mult": 1.0} },
				3: { "cost_cr": 500, "cost_ore": 200, "power": 120, "stats": {"ignore_cargo_mass": true, "engine_speed_mult": 1.05, "acceleration_mult": 1.05} },
				4: { "cost_cr": 1000, "cost_ore": 400, "power": 140, "stats": {"ignore_cargo_mass": true, "engine_speed_mult": 1.1, "acceleration_mult": 1.1} },
				5: { "cost_cr": 2000, "cost_ore": 800, "power": 160, "stats": {"ignore_cargo_mass": true, "engine_speed_mult": 1.15, "acceleration_mult": 1.15, "has_max_hauler_engine": true, "hull_armor": -10} }
			}
		}
	},
	"shields": {
		"base_power": 50,
		"branches": {
			"bulwark": {
				2: { "cost_cr": 300, "cost_ore": 100, "power": 60, "stats": {"shield_capacity": 50, "shield_regen_rate": 2.0, "shield_regen_delay": 15.0} },
				3: { "cost_cr": 600, "cost_ore": 200, "power": 80, "stats": {"shield_capacity": 100, "shield_regen_rate": 3.0, "shield_regen_delay": 15.0} },
				4: { "cost_cr": 1200, "cost_ore": 400, "power": 100, "stats": {"shield_capacity": 150, "shield_regen_rate": 4.0, "shield_regen_delay": 15.0} },
				5: { "cost_cr": 2400, "cost_ore": 800, "power": 130, "stats": {"shield_capacity": 250, "shield_regen_rate": 5.0, "shield_regen_delay": 15.0, "has_max_bulwark_shield": true} }
			},
			"deflector": {
				2: { "cost_cr": 300, "cost_ore": 50, "power": 60, "stats": {"shield_capacity": 20, "shield_regen_rate": 10.0, "shield_regen_delay": 5.0} },
				3: { "cost_cr": 600, "cost_ore": 100, "power": 80, "stats": {"shield_capacity": 30, "shield_regen_rate": 15.0, "shield_regen_delay": 4.0} },
				4: { "cost_cr": 1200, "cost_ore": 200, "power": 100, "stats": {"shield_capacity": 40, "shield_regen_rate": 20.0, "shield_regen_delay": 3.0} },
				5: { "cost_cr": 2400, "cost_ore": 400, "power": 130, "stats": {"shield_capacity": 60, "shield_regen_rate": 30.0, "shield_regen_delay": 2.0, "has_max_deflector_shield": true} }
			}
		}
	},
	"mining": {
		"base_power": 100,
		"branches": {
			"rapid": {
				2: { "cost_cr": 150, "cost_ore": 50, "power": 120, "stats": {"mining_cooldown": 0.8, "mining_laser_yield": 1.0} },
				3: { "cost_cr": 300, "cost_ore": 100, "power": 140, "stats": {"mining_cooldown": 0.6, "mining_laser_yield": 1.0} },
				4: { "cost_cr": 600, "cost_ore": 200, "power": 160, "stats": {"mining_cooldown": 0.4, "mining_laser_yield": 1.0} },
				5: { "cost_cr": 1200, "cost_ore": 400, "power": 180, "stats": {"mining_cooldown": 0.2, "mining_laser_yield": 1.0, "has_max_rapid_mining": true} }
			},
			"deep": {
				2: { "cost_cr": 150, "cost_ore": 100, "power": 120, "stats": {"mining_cooldown": 1.2, "mining_laser_yield": 2.0} },
				3: { "cost_cr": 300, "cost_ore": 200, "power": 140, "stats": {"mining_cooldown": 1.5, "mining_laser_yield": 4.0} },
				4: { "cost_cr": 600, "cost_ore": 400, "power": 160, "stats": {"mining_cooldown": 1.8, "mining_laser_yield": 8.0} },
				5: { "cost_cr": 1200, "cost_ore": 800, "power": 180, "stats": {"mining_cooldown": 2.5, "mining_laser_yield": 15.0, "has_max_deep_mining": true} }
			}
		}
	},
	"cargo": {
		"base_power": 0,
		"branches": {
			"standard": {
				2: { "cost_cr": 100, "cost_ore": 100, "power": 0, "stats": {"cargo_max_m3": 150.0} },
				3: { "cost_cr": 200, "cost_ore": 200, "power": 0, "stats": {"cargo_max_m3": 250.0} },
				4: { "cost_cr": 400, "cost_ore": 400, "power": 0, "stats": {"cargo_max_m3": 400.0} },
				5: { "cost_cr": 800, "cost_ore": 800, "power": 0, "stats": {"cargo_max_m3": 600.0} }
			}
		}
	},
	"power": {
		"base_power": 0,
		"branches": {
			"standard": {
				2: { "cost_cr": 500, "cost_ore": 200, "power": 0, "capacity": 350 },
				3: { "cost_cr": 1000, "cost_ore": 400, "power": 0, "capacity": 420 },
				4: { "cost_cr": 2000, "cost_ore": 800, "power": 0, "capacity": 500 },
				5: { "cost_cr": 4000, "cost_ore": 1600, "power": 0, "capacity": 650 }
			}
		}
	}
}

# ── Minor Faction Registry ────────────────────────────────────────────────────
# Data-driven: adding a new minor faction = one dict entry. No match arms needed.
# model: "faction1" | "faction2" | "aurelia" — which GLB to use
# tint: Color applied to hull meshes to visually distinguish from major factions
const MINOR_FACTIONS = {
	"reavers":  { "color": Color(0.9, 0.1, 0.15),  "projectile": Color(0.9, 0.15, 0.15), "model": "faction1", "tint": Color(0.85, 0.1, 0.1) },
	"obsidian": { "color": Color(0.5, 0.15, 0.8),   "projectile": Color(0.6, 0.2, 0.9),  "model": "faction1", "tint": Color(0.45, 0.1, 0.7) },
	"dustborn": { "color": Color(0.85, 0.65, 0.2),  "projectile": Color(0.9, 0.6, 0.1),  "model": "faction2", "tint": Color(0.8, 0.6, 0.15) },
	"wraiths":  { "color": Color(0.3, 0.9, 0.3),    "projectile": Color(0.3, 0.85, 0.3), "model": "faction2", "tint": Color(0.2, 0.75, 0.2) },
	"ironclad": { "color": Color(0.6, 0.6, 0.65),   "projectile": Color(0.8, 0.8, 0.85), "model": "aurelia",  "tint": Color(0.5, 0.5, 0.55) },
}

# ── Minor NPCs (quest givers, station contacts) ──────────────────────────────
# 8 portrait slots across 2 source images. Each source image is a 2x2 grid:
#   ┌───────────┬───────────┐
#   │ top_left  │ top_right │
#   ├───────────┼───────────┤
#   │ bot_left  │ bot_right │
#   └───────────┴───────────┘
# Left column = male, right column = female. Bottom-right of NPC02 is the
# Grease Monkeys mechanic (Jenna Kross).
# Keys are display names — the same string the LLM quest-gen puts in
# `agent_name`. Lookup by name returns image path + cell position.
# 8 portrait slots across 2 source images. Each source image is a 2x2 grid:
#   MinorNPC01.png: top-left=Cassen, top-right=Mariska, bottom-left=Korvin, bottom-right=Hana
#   MinorNPC02.png: top-left=Oleg,   top-right=Dasha,   bottom-left=Alaric, bottom-right=Jenna
# Each NPC has a `voice_id` (Kokoro voice) and `voice_speed` (slight modifier
# 0.85-1.10) for unique TTS voices — see skills/skill_using_tts_in_spacegame.md.
const MINOR_NPCS = {
	"Cassen Vane":   { "image": "res://assets/MinorNPC01.png", "position": "top_left",     "vibe": "grizzled mercenary, scars and salt-and-pepper hair", "outpost": "kova",       "voice_id": "am_onyx",   "voice_speed": 0.92, "flavor_color": Color(1.0, 0.6, 0.55), "flavor_lines": [
		"Kova's got no rules, Shiny. Just people with guns and people without.",
		"Vanguard patrols hit Sector 7 hard last week. Someone's paying them to.",
		"Aurelia tried to recruit me once. I declined. Politely. With a knife.",
	], "pickup_handoff_fallback_lines": [
		"Got your part. Try not to break it before you bring it back.",
		"There. The mechanic's paying through Kova, I expect the same courtesy. Don't scratch it.",
		"Part's yours. Anything happens to it on the way back, that's between you and your insurance.",
		"Hand-off clean. Don't tell me where you're taking it, don't tell me why, and we're square.",
		"There you go. The mechanic's credit cleared this morning, so I expect you to do the same.",
	] },
	"Mariska Vonn":  { "image": "res://assets/MinorNPC01.png", "position": "top_right",    "vibe": "young blonde corporate fixer, white-and-gold outfit", "outpost": "iron_reach", "voice_id": "af_nicole", "voice_speed": 1.05, "flavor_color": Color(0.55, 0.85, 1.0), "flavor_lines": [
		"Zenith's been running the numbers on you, Shiny. Try not to disappoint the spreadsheet.",
		"Iron Reach's market is... complicated. Keep your credits close and your questions closer.",
		"Aurelia's been sniffing our freight lanes again. Don't ask what they're moving.",
	], "pickup_handoff_fallback_lines": [
		"There's the part. Receipts on delivery, no exceptions. Tell Jenna I said hi.",
		"All yours, Indy. Don't make me file a claim when it shows up scratched.",
		"Part's in your bay. Contract's signed, courier's gone, my liability ends here.",
		"There. Iron Reach is nothing if not punctual. Try to return the favor.",
		"Invoice, manifest, release code. All yours. Next time, route the requisition through procurement.",
	] },
	"Korvin Shaw":   { "image": "res://assets/MinorNPC01.png", "position": "bottom_left",  "vibe": "military veteran, mohawk and full plate armor", "outpost": "kova",       "voice_id": "am_michael", "voice_speed": 0.95, "flavor_color": Color(0.9, 0.85, 0.5), "flavor_lines": [
		"Vanguard trained me to follow orders. Kova taught me which orders to break.",
		"The frontier doesn't need heroes. It needs survivors.",
		"Zenith, Aurelia, Vanguard — pick your side, Shiny. Or pick none and die quietly.",
	], "pickup_handoff_fallback_lines": [
		"Hand-off in three, two — there. Don't drop it, don't lose it, don't ask where I got it.",
		"Part's in your bay. Combat pilot to combat mechanic. Try not to die on the way back.",
		"All accounted for. Whatever you do with it from here is your war, not mine.",
		"There. Now move — Kova's not a safe place to loiter, and you're not a safe person to loiter near.",
		"Part's loaded. Clean transfer, no witnesses. We were never here.",
	] },
	"Hana Quill":    { "image": "res://assets/MinorNPC01.png", "position": "bottom_right", "vibe": "tech analyst, glasses and dark teal jacket", "outpost": "iron_reach", "voice_id": "af_kore",   "voice_speed": 1.0,  "flavor_color": Color(0.5, 0.95, 0.9), "flavor_lines": [
		"Vanguard's nav buoys are drifting. Either sloppy or probing. Neither's comforting.",
		"Aurelia's encrypted traffic spiked 40% last cycle. Something's moving.",
		"Need a firmware update? I can help. Need a favor? That costs more.",
	], "pickup_handoff_fallback_lines": [
		"That's the firmware module. Fresh off the courier. Don't let it near magnetic fields.",
		"All calibrated and signed off. Try not to brick it before Jenna sees it.",
		"Part's clean, signed, and serialized. If you ask me where it came from, I'll have to lie.",
		"There. Diagnostic pass complete, zero defects. Don't make me a liar.",
		"Loaded. Telemetry's good. Now please don't crash it — I'm tired of writing incident reports.",
	] },
	"Oleg Stroud":   { "image": "res://assets/MinorNPC02.png", "position": "top_left",     "vibe": "syndicate accountant, bald with a monocle", "outpost": "iron_reach", "voice_id": "am_fenrir", "voice_speed": 0.88, "flavor_color": Color(0.6, 1.0, 0.6), "flavor_lines": [
		"Books don't lie, Shiny. The credits tell the whole story.",
		"I keep the ledgers for half the brokers in this sector. Don't ask which half.",
		"You want a receipt? That'll be extra. Aurelia taught me that.",
	], "pickup_handoff_fallback_lines": [
		"Invoice cleared, part released to your bay. Jenna's paying the freight; you're paying me in goodwill.",
		"Here. I've logged the serial. When it breaks, it breaks on your ledger, not mine.",
		"Release code's in your inbox. Auditable, traceable, and exactly as boring as you want it.",
		"There. Debit cleared, credit posted, part released. Try not to make me explain this to an auditor.",
		"All accounted for. The books balance, the part's yours, and we both pretend this never happened.",
	] },
	"Dasha Invar":   { "image": "res://assets/MinorNPC02.png", "position": "top_right",    "vibe": "edgy mercenary, undercut and blue leather", "outpost": "kova",       "voice_id": "af_nova",   "voice_speed": 1.08, "flavor_color": Color(1.0, 0.55, 0.7), "flavor_lines": [
		"Don't stare, Shiny. The tattoos have stories and none of them are short.",
		"Kova's where the contracts go when everywhere else gets too hot.",
		"You look like trouble. Good. Trouble pays well.",
	], "pickup_handoff_fallback_lines": [
		"Part's in your bay. Try not to get jumped on the way back — Kova's not safe for a shiny crate.",
		"Took me all morning to find a clean one. Don't let the mechanic's people screw it up.",
		"There. Don't ask where I sourced it, don't ask who I paid off, and don't you dare scratch it.",
		"Hand-off done. The tattoos have more history than this part, and I trust both about the same.",
		"All yours, sharp edges and all. Try not to bleed on the upholstery.",
	] },
	"Alaric Venn":   { "image": "res://assets/MinorNPC02.png", "position": "bottom_left",  "vibe": "corporate strategist, slicked hair and goatee", "outpost": "iron_reach", "voice_id": "am_liam",   "voice_speed": 0.98, "flavor_color": Color(0.7, 0.75, 1.0), "flavor_lines": [
		"Iron Reach runs clean. Mostly. Don't dig into the manifest logs.",
		"Zenith and Vanguard keep circling each other. We take notes and bill both sides.",
		"You ever wonder who really runs this sector? Follow the supply contracts.",
	], "pickup_handoff_fallback_lines": [
		"Part's logged, manifests signed, and the courier's gone. Iron Reach keeps its paperwork tidy.",
		"There. Tell Jenna the next time, route the requisition through me. Less overhead.",
		"Released to your account, line item 4471. The board's already amortized it across the quarter.",
		"Loaded. The next time Iron Reach does this for you, the rate goes up. Precedent.",
		"All yours. Try to keep it out of the news — corporate logistics gets enough bad press as it is.",
	] },
	"Jenna Kross":   { "image": "res://assets/MinorNPC02.png", "position": "bottom_right", "vibe": "mechanic with red hair, goggles, and tattoos", "role": "Grease Monkeys mechanic", "voice_id": "af_aoede", "voice_speed": 1.0, "flavor_color": Color(1.0, 0.85, 0.4), "flavor_lines": [
		"If it flies, I can fix it. If it doesn't fly, I can make it fly. Hand me the part.",
		"Your thruster's running hot. I can hear it from here. Pay me now or pay me later.",
		"The INDY Miner — classic chassis. Easy to work on, hard to keep running.",
	], "pickup_handoff_fallback_lines": [
		# Jenna is the mechanic, not a pickup NPC — but if a quest ever
		# routes to her (e.g. a return-trip handoff), she has lines.
		"Hand me the part. I already know what's wrong with it.",
		"Park it. I can hear the bearing whining from here.",
		"Indy Miner? Of course. Hand it over, I'll work my magic.",
	] },
}

# ── Station Safe Zones ────────────────────────────────────────────────────────
# NPCs won't initiate attacks on the player within safe zones if rep is above threshold.
# Minor factions ignore safe zones — they're outlaws.
const SAFE_ZONES = [
	{ "position": Vector3(0, 0, 180), "radius": 250.0 },  # Main Station
]
const SAFE_ZONE_REP_THRESHOLD = -40.0

static func is_minor_faction(faction_name: String) -> bool:
	var definition := GameContentRegistry.shared().faction(faction_name)
	return definition != null and definition.classification == "minor"

static func minor_faction_data(faction_name: String) -> Dictionary:
	var definition := GameContentRegistry.shared().faction(faction_name)
	if definition == null or definition.classification != "minor":
		return {}
	return {
		"color": definition.ui_color,
		"projectile": definition.projectile_color,
		"model": definition.ship_family,
		"tint": definition.hull_tint,
	}

static func is_in_safe_zone(world_pos: Vector3) -> bool:
	for zone in SAFE_ZONES:
		if world_pos.distance_to(zone["position"]) <= zone["radius"]:
			return true
	return false

# Convert a numeric reputation value to a semantic tier label.
# 1.5b models understand semantic labels far better than raw numbers
# in the same token budget — they skip the "what does -50 mean" step.
# 9 tiers, symmetric around 0, with boundaries at 0 / ±25 / ±50 / ±75:
#   -100..-75   sworn enemy
#    -74..-50   hostile
#    -49..-25   unfriendly
#    -24..-1    wary
#         0     neutral
#      1..24    cordial
#     25..49    friendly
#     50..74    trusted
#     75..100   allied
static func reputation_tier(rep: float) -> String:
	if rep <= -75.0: return "sworn enemy"
	elif rep <= -50.0: return "hostile"
	elif rep <= -25.0: return "unfriendly"
	elif rep < 0.0: return "wary"
	elif rep == 0.0: return "neutral"
	elif rep <= 25.0: return "cordial"
	elif rep <= 50.0: return "friendly"
	elif rep <= 75.0: return "trusted"
	else: return "allied"

# Returns a UI color for the given reputation value, mapped to a
# red → amber → neutral → green gradient. Pairs with reputation_tier()
# so the tier label and the color always agree (same boundary values).
# Tier colors:
#   sworn enemy: deep red       Color(0.80, 0.10, 0.10)
#   hostile:     red            Color(1.00, 0.20, 0.20)
#   unfriendly:  orange-red     Color(1.00, 0.50, 0.20)
#   wary:        amber          Color(1.00, 0.80, 0.30)
#   neutral:     light gray     Color(0.80, 0.80, 0.80)
#   cordial:     yellow-green   Color(0.70, 1.00, 0.40)
#   friendly:    light green    Color(0.40, 0.90, 0.30)
#   trusted:     green          Color(0.20, 0.80, 0.20)
#   allied:      bright green   Color(0.10, 1.00, 0.40)
static func reputation_color(rep: float) -> Color:
	if rep <= -75.0: return Color(0.80, 0.10, 0.10)
	elif rep <= -50.0: return Color(1.00, 0.20, 0.20)
	elif rep <= -25.0: return Color(1.00, 0.50, 0.20)
	elif rep < 0.0: return Color(1.00, 0.80, 0.30)
	elif rep == 0.0: return Color(0.80, 0.80, 0.80)
	elif rep <= 25.0: return Color(0.70, 1.00, 0.40)
	elif rep <= 50.0: return Color(0.40, 0.90, 0.30)
	elif rep <= 75.0: return Color(0.20, 0.80, 0.20)
	else: return Color(0.10, 1.00, 0.40)

# Returns the display info for a major faction.
# Used to build the HUD rep tooltips ("Zenith (Corporate) — trusted (50)").
# Returns a dict with: name (full display name), descriptor (e.g. "Corporate"),
# abbrev (3-letter HUD abbreviation).
static func faction_info(faction_id: String) -> Dictionary:
	var definition := GameContentRegistry.shared().faction(faction_id)
	if definition:
		return {
			"name": definition.display_name,
			"descriptor": definition.descriptor,
			"abbrev": definition.abbreviation,
		}
	return {"name": faction_id.capitalize(), "descriptor": "Unknown", "abbrev": faction_id.substr(0, 3).to_upper()}

# Returns the AtlasTexture for a minor NPC's portrait, sliced from its 2x2
# source image at the cell position stored in MINOR_NPCS.
# Returns null if the name isn't recognized or the image fails to load.
static func get_minor_npc_portrait(npc_name: String) -> AtlasTexture:
	var definition := GameContentRegistry.shared().npc_by_name(npc_name)
	if definition == null:
		return null
	return GameContentRegistry.shared().portrait_texture(definition.portrait_id)

static func get_minor_npc_data(npc_name: String) -> Dictionary:
	if not MINOR_NPCS.has(npc_name):
		return {}
	var data: Dictionary = MINOR_NPCS[npc_name].duplicate(true)
	var definition := GameContentRegistry.shared().npc_by_name(npc_name)
	if definition:
		data["portrait_id"] = str(definition.portrait_id)
		data["voice_profile_id"] = str(definition.voice_profile_id)
		data["flavor_color"] = definition.presentation_color
	return data

# Returns the list of minor NPC names stationed at a given outpost id
# (e.g. "iron_reach", "kova"). Returns an empty array if no NPCs are
# assigned. The mechanic (Jenna Kross) is excluded — she's at Grease Monkeys.
static func get_minor_npcs_at_outpost(outpost_id: String) -> Array:
	var result: Array = []
	for npc_name in MINOR_NPCS:
		if MINOR_NPCS[npc_name].get("outpost", "") == outpost_id:
			result.append(npc_name)
	return result

# Returns the outpost id for a minor NPC, or "" if they aren't outpost-based
# (e.g. the mechanic, who lives at Grease Monkeys).
static func get_minor_npc_outpost(npc_name: String) -> String:
	if not MINOR_NPCS.has(npc_name):
		return ""
	return MINOR_NPCS[npc_name].get("outpost", "")

# Returns a random minor NPC name. Used for picking a quest-board contact
# at an outpost when the player asks "who's hiring?"
static func random_minor_npc_name() -> String:
	var keys: Array = MINOR_NPCS.keys()
	return keys[randi() % keys.size()]

# Returns a random flavor line from a random NPC stationed at the given
# outpost, along with the NPC's name, chat-color, and TTS voice data.
# Drives the "Hear Gossip" button at outpost docks — each click rotates to
# a different NPC and a different line, so the player can keep clicking
# for variety. Returns an empty dict if the outpost has no NPCs assigned.
# Returned shape:
#   { "npc_name": String, "line": String, "color": Color,
#     "voice_id": String, "voice_speed": float }
# `voice_id` is a Kokoro voice name (e.g. "am_onyx", "af_nicole"). The
# default fallback is "af_bella" if an NPC has no voice data assigned.
# `voice_speed` is a 0.85-1.10 modifier that subtly differentiates
# voices that share an underlying voice family.
static func get_random_npc_flavor_line(outpost_id: String) -> Dictionary:
	var npcs: Array = get_minor_npcs_at_outpost(outpost_id)
	if npcs.is_empty():
		return {}
	var npc_name: String = npcs[randi() % npcs.size()]
	var npc: Dictionary = get_minor_npc_data(npc_name)
	var lines: Array = npc.get("flavor_lines", [])
	if lines.is_empty():
		return {}
	var line: String = lines[randi() % lines.size()]
	return {
		"npc_name": npc_name,
		"line": line,
		"color": npc.get("flavor_color", Color.WHITE),
		"voice_profile_id": npc.get("voice_profile_id", "voice.neutral.v1"),
	}

# Returns the full set of (npc_name, line) pairs for every NPC at the
# given outpost, across all NPCs and all flavor lines. Used by the
# dock-time pre-cache so the first Hear Gossip click plays instantly
# in each NPC's unique voice. Returns an empty array if the outpost
# has no NPCs. Each entry is a Dictionary with the same shape as
# get_random_npc_flavor_line plus a redundant `outpost_id` for
# downstream logging.
static func get_outpost_flavor_tts_lines(outpost_id: String) -> Array:
	var result: Array = []
	var npcs: Array = get_minor_npcs_at_outpost(outpost_id)
	for npc_name in npcs:
		var npc: Dictionary = get_minor_npc_data(npc_name)
		var lines: Array = npc.get("flavor_lines", [])
		var voice_profile_id: String = npc.get(
			"voice_profile_id",
			"voice.neutral.v1"
		)
		for line in lines:
			result.append({
				"npc_name": npc_name,
				"line": line,
				"color": npc.get("flavor_color", Color.WHITE),
				"voice_profile_id": voice_profile_id,
				"outpost_id": outpost_id,
			})
	return result

# Returns the remaining flavor lines for one NPC (excluding the line that
# was just played). Used by the "refresh-on-use" pre-cache: when a player
# hears a line and the cache miss path runs, we want the *next* click to
# hit cache, so we re-warm the NPC's other lines in the background.
# If `just_played` is empty or not in the list, returns every line.
static func get_other_flavor_lines_for_npc(npc_name: String, just_played: String) -> Array:
	if not MINOR_NPCS.has(npc_name):
		return []
	var npc: Dictionary = get_minor_npc_data(npc_name)
	var lines: Array = npc.get("flavor_lines", [])
	var result: Array = []
	for line in lines:
		if line == just_played:
			continue
		result.append({
			"npc_name": npc_name,
			"line": line,
			"color": npc.get("flavor_color", Color.WHITE),
			"voice_profile_id": npc.get(
				"voice_profile_id",
				"voice.neutral.v1"
			),
		})
	return result

signal target_changed(new_target: Node3D)
signal cargo_changed(new_cargo: float)
signal credits_changed(new_credits: int)
signal game_paused(paused: bool)

# Ship-upgrade signals. Emitted when a stat changes (via an upgrade) so
# the maintenance bay UI can refresh its display.
signal ship_stat_changed(stat_name: String, new_value: float)

# Player stats
var player_credits: int = 50:
	set(val):
		player_credits = val
		credits_changed.emit(player_credits)

const PlayerInventoryScript = preload("res://scripts/economy/PlayerInventory.gd")
var inventory = PlayerInventoryScript.new()

var _cargo_normalizing: bool = false
var cargo: float = 0.0:
	set(val):
		cargo = clamp(val, 0.0, cargo_max)
		if not _cargo_normalizing:
			cargo_changed.emit(cargo)

# ── Cargo type system ──────────────────────────────────────────────────────
# The cargo hold is mutually exclusive: it holds EITHER ore (tracked by
# `cargo: float` in m³) OR a single special item (tracked by
# `cargo_special: Dictionary`), never both. This lets the mechanic and
# major agents hand the player a "pickup mission" part while still
# preserving ore as the standard minable resource.
#   EMPTY   — hold is empty, can accept either ore or a special item
#   ORE     — carrying ore (no special); player can keep mining
#   SPECIAL — carrying a single non-ore item; mining laser refuses to fire
enum CargoType { EMPTY, ORE, SPECIAL }

# What kind of cargo is currently in the hold.
var cargo_type: int = CargoType.EMPTY

# Special-cargo metadata. Empty dict when cargo_type != SPECIAL.
# Keys:
#   "name"        — short display string (e.g. "Replacement Plasma Coupler")
#   "description" — longer text for tooltips / chatter
#   "source"      — where the player picked it up (e.g. "Outpost Iron Reach")
#   "destination" — where it needs to be delivered (e.g. "Grease Monkeys")
var cargo_special: Dictionary = {}

# Active test pickup-quest state. Empty dict when no test quest is active.
# Used by the Grease Monkeys maintenance-bay debug buttons. Keys:
#   "outpost_id"     — "iron_reach" or "kova"
#   "outpost_display"— e.g. "Outpost Iron Reach"
#   "npc_name"       — which minor NPC at that outpost
#   "part_name"      — what to pick up
#   "picked_up"      — false until the player clicks Pickup at the outpost,
#                     then true (and the part is loaded into cargo_special)
var test_quest: Dictionary = {}

func normalize_cargo_state() -> void:
	_cargo_normalizing = true
	if cargo_type == CargoType.ORE and cargo <= 0.0:
		cargo = 0.0
		cargo_type = CargoType.EMPTY
		cargo_special = {}
	elif cargo_type == CargoType.SPECIAL and cargo_special.is_empty():
		cargo = 0.0
		cargo_type = CargoType.EMPTY
	elif cargo_type != CargoType.SPECIAL and not cargo_special.is_empty():
		cargo_special = {}
	_cargo_normalizing = false

# Returns true if the hold can accept more ore (empty, or already ore with
# room left). Returns false if a special item is loaded.
func can_accept_ore() -> bool:
	normalize_cargo_state()
	return cargo_type == CargoType.EMPTY or cargo_type == CargoType.ORE

# Returns true if the hold can accept a special cargo item. Only valid
# when the hold is empty — can't swap out ore for a part.
func can_accept_special() -> bool:
	normalize_cargo_state()
	return cargo_type == CargoType.EMPTY

# Add ore to the hold. Returns the amount actually added (capped at
# cargo_max). Returns 0 if the hold can't accept ore (i.e. a special
# item is loaded).
func add_ore(amount: float) -> float:
	if not can_accept_ore():
		return 0.0
	var available = cargo_max - cargo
	var added = min(amount, available)
	if added <= 0.0:
		return 0.0
	cargo += added
	cargo_type = CargoType.ORE
	cargo_changed.emit(cargo)
	return added

# Accept a special cargo item. Only valid when the hold is empty.
# Returns true if accepted, false if the hold wasn't empty.
func accept_special(item_name: String, description: String, source: String, destination: String = "") -> bool:
	if not can_accept_special():
		return false
	cargo_special = {
		"name": item_name,
		"description": description,
		"source": source,
		"destination": destination,
	}
	cargo_type = CargoType.SPECIAL
	cargo_changed.emit(cargo)
	return true

# Remove a specific amount of ore. Returns the amount actually removed.
# If ore drops to 0, the hold auto-returns to EMPTY. Does nothing if the
# hold is carrying a special item.
func remove_ore(amount: float) -> float:
	if cargo_type != CargoType.ORE:
		return 0.0
	var removed = min(amount, cargo)
	removed = max(0.0, removed)
	cargo -= removed
	if cargo <= 0.0:
		clear_cargo()
	else:
		cargo_changed.emit(cargo)
	return removed

# Reset the hold to EMPTY. Used after quest delivery, sell-ore, and when
# the player jettisons or delivers a special item.
func clear_cargo() -> void:
	cargo = 0.0
	cargo_special = {}
	cargo_type = CargoType.EMPTY
	cargo_changed.emit(cargo)


# ── Mechanic pickup-quest offer ───────────────────────────────────────────────
# When the player docks at Grease Monkeys, the mechanic's LLM intro has a
# chance to roll into a pickup offer: she asks the player to fetch a part
# from a named NPC at a named outpost. The roll happens once per dock and
# locks for the rest of the visit so submenu swaps don't re-roll it.
#
# 0.5 = 50% for testing. Drop to 0.05 (or less) once the LLM is reliable
# and the part flow is balanced. Lives on GlobalState so the LLM prompt
# and the quest-build can read the same number.
const MECHANIC_PICKUP_OFFER_CHANCE: float = 0.5

# The two outposts the mechanic can send the player to. Matches the
# OUTPOST_NODE_TO_ID keys in UIManager (the scene node names live there
# in world labels; this is the lowercase id form the quest data uses).
const PICKUP_OUTPOST_IDS: Array = ["iron_reach", "kova"]
const PICKUP_OUTPOST_DISPLAY: Dictionary = {
	"iron_reach": "Outpost Iron Reach",
	"kova":      "Outpost Kova",
}

# Parts the mechanic might need. Keep variety high so LLM lines don't all
# sound the same. The fallback lines mention the part by name so the
# player knows what they're carrying.
const PICKUP_PART_NAMES: Array = [
	"Plasma Coupler Mk II",
	"Hydraulic Sealant Cartridge",
	"Firmware Module — Nav Compute v3.1",
	"Quantum Drive Bypass Coil",
	"Shield Capacitor Array",
	"Sensor Calibration Kit",
	"Antimatter Injector Valve",
	"Thrust Vectoring Servo",
]

# What the mechanic pays on successful delivery. Single source of truth —
# the live offer path AND the test buttons read this.
const PICKUP_REWARD_CREDITS: int = 200

# Returns a pickup-offer roll. The offer is a single (outpost, npc, part)
# tuple shared by the LLM prompt and the quest-build so they can't drift.
# Returns {offer: false} on the negative side of the chance roll. Caller
# is responsible for the per-dock lock (this is a single call — not stateful).
static func roll_pickup_offer() -> Dictionary:
	if randf() > MECHANIC_PICKUP_OFFER_CHANCE:
		return { "offer": false }
	var outpost_id: String = PICKUP_OUTPOST_IDS[randi() % PICKUP_OUTPOST_IDS.size()]
	var npcs: Array = get_minor_npcs_at_outpost(outpost_id)
	if npcs.is_empty():
		# Defensive: the outposts always have NPCs today, but if that
		# ever changes we want a clean negative result, not a crash.
		push_warning("[GlobalState] roll_pickup_offer: outpost '%s' has no NPCs." % outpost_id)
		return { "offer": false }
	var npc_name: String = npcs[randi() % npcs.size()]
	var part_name: String = PICKUP_PART_NAMES[randi() % PICKUP_PART_NAMES.size()]
	return {
		"offer": true,
		"outpost_id": outpost_id,
		"outpost_display": PICKUP_OUTPOST_DISPLAY.get(outpost_id, outpost_id),
		"npc_name": npc_name,
		"part_name": part_name,
		"reward_credits": PICKUP_REWARD_CREDITS,
	}


# ── Outpost ore buyback ───────────────────────────────────────────────────────
# The cargo is mutually exclusive (ore XOR special). If the player has
# ore in the hold when they try to pick up the part at the outpost, the
# target NPC offers to buy the ore at a slight premium to free the bay.
# This is the only place in the game ore sells for more than 1 SC/m³.

# Buyback rate per m³, keyed on the player's BEST reputation tier across
# all factions. Same brackets as the spec: 2.0 for wary/below, 2.5 for
# neutral-friendly, 3.0 for trusted/allied. Reads `reputations` (a live
# var, not const) so it reflects the player's current standing.
func buyback_price_per_m3() -> float:
	# Walk all faction reps, take the best tier label, map to price.
	var best_label: String = "neutral"
	var best_value: float = 0.0
	for faction in reputations.keys():
		var rep: float = float(reputations.get(faction, 0.0))
		if rep > best_value:
			best_value = rep
			best_label = reputation_tier(rep)
	match best_label:
		"trusted", "allied":
			return 3.0
		"neutral", "cordial", "friendly":
			return 2.5
		_:
			# sworn enemy, hostile, unfriendly, wary
			return 2.0

# Sell all ore currently in the hold at the buyback rate. Returns the
# credits paid. Caller is responsible for showing the popup. Plays the
# same sell-ore sfx as the main station for audio consistency.
#
# Returns 0 if the hold is empty or carrying a special item — by the
# time this is called, the caller has already gated on cargo_type==ORE.
func buyback_ore_at_outpost() -> int:
	if cargo_type != CargoType.ORE or cargo <= 0.0:
		return 0
	var rate: float = buyback_price_per_m3()
	var paid: int = int(round(cargo * rate))
	player_credits += paid
	clear_cargo()
	return paid

# Returns a short display string for the HUD: "EMPTY", "ORE: 15 / 30 m³",
# or "SPECIAL: Replacement Plasma Coupler".
func cargo_display_text() -> String:
	normalize_cargo_state()
	match cargo_type:
		CargoType.EMPTY:
			return "EMPTY"
		CargoType.ORE:
			return "ORE: %d / %d m³" % [int(cargo), int(cargo_max)]
		CargoType.SPECIAL:
			return "SPECIAL: " + cargo_special.get("name", "(unnamed)")
	return ""

var player_storage_ore: float = 0.0
var player_storage_max: float = 1000.0
var power_capacity: float = 300.0

var current_upgrades: Dictionary = {
	"weapons": {"tier": 1, "path": "base"},
	"engine": {"tier": 1, "path": "base"},
	"shields": {"tier": 1, "path": "base"},
	"mining": {"tier": 1, "path": "base"},
	"cargo": {"tier": 1, "path": "base"},
	"power": {"tier": 1, "path": "base"}
}

# Upgradeable ship stats — defaults sourced from SHIP_BASE_STATS so the
var cargo_max: float = SHIP_BASE_STATS["cargo_max_m3"]
var mining_yield: float = SHIP_BASE_STATS["mining_laser_yield"]
var mining_cooldown: float = SHIP_BASE_STATS["mining_cooldown"]
var weapon_damage: float = SHIP_BASE_STATS["weapon_damage"]
var weapon_cooldown: float = SHIP_BASE_STATS["weapon_cooldown"]
var shield_capacity: float = SHIP_BASE_STATS["shield_capacity"]
var shield_regen_delay: float = SHIP_BASE_STATS["shield_regen_delay"]
var shield_regen_rate: float = SHIP_BASE_STATS["shield_regen_rate"]
var engine_speed_mult: float = SHIP_BASE_STATS["engine_speed_mult"]
var acceleration_mult: float = SHIP_BASE_STATS["acceleration_mult"]
var ignore_cargo_mass: bool = SHIP_BASE_STATS["ignore_cargo_mass"]
var hull_armor: float = SHIP_BASE_STATS["hull_armor"]
var player_max_health: float = SHIP_BASE_STATS["max_health"]

# Max Tier Drawback Flags
var has_max_rapid_weapon: bool = false
var has_max_heavy_weapon: bool = false
var has_max_speed_engine: bool = false
var has_max_hauler_engine: bool = false
var has_max_bulwark_shield: bool = false
var has_max_deflector_shield: bool = false
var has_max_rapid_mining: bool = false
var has_max_deep_mining: bool = false

# Non-upgradeable baseline
var damage: float = weapon_damage # Legacy support until swapped
var laser_range: float = 80.0
var destroyed_ships_pool: int = 0
var runtime_entity_sequence: int = 0

# Game references
var player: Node3D = null
var active_system_root: Node3D = null
var current_system_id: String = "start_system"
var active_target: Node3D = null:
	set(val):
		active_target = val
		target_changed.emit(active_target)

var active_system_entities: Array[Node3D] = []
var paused: bool = false:
	set(val):
		paused = val
		game_paused.emit(paused)

# Reputation system
var reputations: Dictionary = {
	"zenith": 50.0,
	"aurelia": -20.0,
	"vanguard": -20.0
}
signal reputation_changed(faction_name: String, new_rep: float)
signal ship_destroyed(faction_name: String)
signal entities_changed()
signal system_chatter_received(sender: String, message: String, color: Color)

var faction_kills: Dictionary = {
	"zenith": 0,
	"aurelia": 0,
	"vanguard": 0
}

func record_kill(faction_name: String):
	# Track kills for ANY faction — including LLM-generated custom ones
	var kill_count := int(faction_kills.get(faction_name, 0)) + 1
	faction_kills[faction_name] = kill_count
	# NOTE: ship_destroyed signal is now emitted by NPCShip.die() itself,
	# not here, so NPC-on-NPC kills also count toward quest progress.
	# Only call in reinforcements for the three main factions (they have matching ship scenes)
	if faction_name in ["zenith", "aurelia", "vanguard"] and kill_count % 3 == 0:
		spawn_reinforcement(faction_name)

func spawn_reinforcement(faction_name: String):
	var player_node = player
	if not player_node or not is_instance_valid(player_node) or player_node.get("destroyed"):
		return
		
	# Find a random position around the player (e.g., 85m away)
	var angle = randf() * TAU
	var spawn_dist = 85.0
	var offset = Vector3(cos(angle), 0, sin(angle)) * spawn_dist
	var spawn_pos = player_node.global_position + offset
	
	# Load the NPC ship scene
	var npc_scene = load("res://scenes/npc_ship.tscn")
	if npc_scene:
		var npc = npc_scene.instantiate()
		npc.faction = faction_name
		npc.is_reinforcement = true
		npc.ship_role = "Gunner"
		npc.speed = 11.0
		npc.name = faction_name.to_upper() + "_EliteReinforcement_" + str(randi() % 1000)
		runtime_entity_sequence += 1
		npc.persistent_id = "entity.%s.reinforcement.%06d" % [
			current_system_id,
			runtime_entity_sequence,
		]
		
		var system_root = get_system_root()
		if system_root:
			system_root.add_child(npc)
			npc.global_position = spawn_pos
			
			# Trigger warning on HUD
			var ui = get_ui_manager()
			if ui and ui.has_method("show_hud_warning"):
				ui.show_hud_warning("WARNING: " + faction_name.to_upper() + " Elite Reinforcement has entered the area!")
			
			# Trigger system alert in chatter
			var alert = LLMInterface.get_chatter_line("system_alert")
			emit_chatter("SYSTEM", alert, Color(0.0, 0.9, 0.9))

func spawn_mission_targets(faction_name: String, count: int):
	var player_node = player
	if not player_node or not is_instance_valid(player_node) or player_node.get("destroyed"):
		return
	
	var system_root = get_system_root()
	if not system_root:
		return
	
	var npc_scene = load("res://scenes/npc_ship.tscn")
	if not npc_scene:
		print("[GlobalState] ERROR: Could not load npc_ship.tscn for mission targets.")
		return
	
	# Use the station as the spawn anchor so targets appear in open space,
	# not on top of the dock where the player accepted the quest
	var spawn_anchor: Vector3 = player_node.global_position
	var station_node = get_primary_station()
	if station_node and is_instance_valid(station_node):
		spawn_anchor = station_node.global_position
	
	print("[GlobalState] Spawning ", count, " mission targets for faction: ", faction_name, " at distance from station")
	
	# Spread ships evenly in a ring 550-900m from the station — far enough
	# that the player has to fly out to engage, close enough to feel immediate
	var mission_key := _active_mission_identity_key()
	var start_index := int(
		QuestManager.active_quest.get("target_spawn_sequence", 0)
	)
	QuestManager.active_quest["target_spawn_sequence"] = start_index + count
	for i in range(count):
		var angle = (TAU / count) * i + randf_range(-0.4, 0.4)
		var dist = randf_range(550.0, 900.0)
		var offset = Vector3(cos(angle), randf_range(-0.05, 0.05), sin(angle)) * dist
		var spawn_pos = spawn_anchor + offset
		
		var npc = npc_scene.instantiate()
		npc.faction = faction_name
		npc.is_reinforcement = false
		npc.ship_role = ["Gunner", "Interceptor"].pick_random()
		npc.name = faction_name.to_upper() + "_MissionTarget_" + str(randi() % 1000)
		# Mark as a quest target so QuestManager can count survivors and
		# decide when to spawn replacements after NPC kills.
		npc.set_meta("is_quest_target", true)
		npc.persistent_id = "entity.mission.%s.%06d" % [
			mission_key,
			start_index + i,
		]
		npc.add_to_group("persistent_entity")
		system_root.add_child(npc)
		npc.global_position = spawn_pos
	
	# HUD warning + chatter so the arrival feels like an event
	var ui = get_ui_manager()
	if ui and ui.has_method("show_hud_warning"):
		ui.show_hud_warning("CONTRACT ACTIVE: " + str(count) + " " + faction_name.to_upper() + " targets have entered the sector.")
	emit_chatter("SYSTEM", "Sensor sweep: " + str(count) + " " + faction_name.to_upper() + " signatures detected in open space.", Color(0.0, 0.9, 0.9))

func _active_mission_identity_key() -> String:
	var runtime_id := str(QuestManager.active_quest.get("runtime_id", ""))
	if not runtime_id.is_empty():
		return runtime_id.sha256_text().substr(0, 12)
	var legacy_source := "%s|%s|%s" % [
		QuestManager.active_quest.get("title", "legacy"),
		QuestManager.active_quest.get("system_id", current_system_id),
		QuestManager.active_quest.get("faction", "neutral"),
	]
	return legacy_source.sha256_text().substr(0, 12)




func emit_chatter(sender: String, message: String, color: Color):
	system_chatter_received.emit(sender, message, color)

# Emits an NPC flavor line to the corner chatter panel AND a dedicated
# `npc_flavor_spoken` signal that carries the TTS routing data (voice
# ID + speed). UIManager listens on `npc_flavor_spoken` to fire TTS
# playback — system chatter (alerts, sensor sweeps) goes through
# `emit_chatter` and stays text-only. Use this for any line that should
# be spoken in the NPC's unique voice.
# Expected flavor shape: { "npc_name", "line", "color", "voice_id", "voice_speed" }
# (matches get_random_npc_flavor_line and get_outpost_flavor_tts_lines).
signal npc_flavor_spoken(flavor: Dictionary)
func emit_npc_flavor(flavor: Dictionary) -> void:
	if flavor.is_empty():
		return
	var sender: String = flavor.get("npc_name", "Local")
	var voice_profile_id: String = str(
		flavor.get("voice_profile_id", "voice.neutral.v1")
	)
	var line: String = apply_tone_guard(str(flavor.get("line", "")), voice_profile_id)
	var color: Color = flavor.get("color", Color.WHITE)
	system_chatter_received.emit(sender, line, color)
	var spoken_flavor := flavor.duplicate(true)
	spoken_flavor["line"] = line
	spoken_flavor["voice_profile_id"] = voice_profile_id
	npc_flavor_spoken.emit(spoken_flavor)

func adjust_reputation(faction_name: String, amount: float):
	if reputations.has(faction_name):
		reputations[faction_name] = clamp(reputations[faction_name] + amount, -100.0, 100.0)
		reputation_changed.emit(faction_name, reputations[faction_name])

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_inputs()
	CampaignClock.time_changed.connect(_on_campaign_time_for_stores)


const StoreRegistryScript = preload("res://scripts/economy/StoreRegistry.gd")

func _on_campaign_time_for_stores(total_minutes: int) -> void:
	StoreRegistryScript.shared().restock_all(total_minutes)

func get_system_root() -> Node3D:
	if active_system_root and is_instance_valid(active_system_root):
		return active_system_root
	return get_tree().current_scene

func get_ui_manager() -> Control:
	var scene_root := get_tree().current_scene
	if not scene_root:
		return null
	return scene_root.get_node_or_null("CanvasLayer/UIManager") as Control

func get_primary_station() -> Node3D:
	var system_root := get_system_root()
	if not system_root:
		return null
	for node in get_tree().get_nodes_in_group("primary_station"):
		if node is Node3D and system_root.is_ancestor_of(node):
			return node as Node3D
	return system_root.get_node_or_null("Station") as Node3D

# Called before reload_current_scene() to avoid dangling references into the freed scene.
func reset_for_restart():
	# Null out all node references first
	player = null
	active_system_root = null
	current_system_id = "start_system"
	active_system_entities.clear()
	# Directly set paused to avoid emitting game_paused into freed UIManager
	paused = false
	# Silently clear active_target without emitting target_changed
	active_target = null
	# Reset gameplay stats
	player_credits = 50
	inventory = PlayerInventoryScript.new()
	cargo = 0.0
	cargo_special = {}
	cargo_type = CargoType.EMPTY
	cargo_max = SHIP_BASE_STATS["cargo_max_m3"]
	player_storage_ore = 0.0
	current_upgrades = {
		"weapons": {"tier": 1, "path": "base"},
		"engine": {"tier": 1, "path": "base"},
		"shields": {"tier": 1, "path": "base"},
		"mining": {"tier": 1, "path": "base"},
		"cargo": {"tier": 1, "path": "base"},
		"power": {"tier": 1, "path": "base"}
	}
	apply_upgrade_stats()
	mining_yield = SHIP_BASE_STATS["mining_laser_yield"]
	mining_cooldown = SHIP_BASE_STATS["mining_cooldown"]
	weapon_damage = SHIP_BASE_STATS["weapon_damage"]
	weapon_cooldown = SHIP_BASE_STATS["weapon_cooldown"]
	shield_capacity = SHIP_BASE_STATS["shield_capacity"]
	shield_regen_delay = SHIP_BASE_STATS["shield_regen_delay"]
	shield_regen_rate = SHIP_BASE_STATS["shield_regen_rate"]
	engine_speed_mult = SHIP_BASE_STATS["engine_speed_mult"]
	acceleration_mult = SHIP_BASE_STATS["acceleration_mult"]
	ignore_cargo_mass = SHIP_BASE_STATS["ignore_cargo_mass"]
	hull_armor = SHIP_BASE_STATS["hull_armor"]
	player_max_health = SHIP_BASE_STATS["max_health"]
	
	has_max_rapid_weapon = false
	has_max_heavy_weapon = false
	has_max_speed_engine = false
	has_max_hauler_engine = false
	has_max_bulwark_shield = false
	has_max_deflector_shield = false
	has_max_rapid_mining = false
	has_max_deep_mining = false
	
	damage = weapon_damage
	laser_range = 80.0
	destroyed_ships_pool = 0
	runtime_entity_sequence = 0
	# Reset reputations
	reputations = { "zenith": 50.0, "aurelia": -20.0, "vanguard": -20.0 }
	# Reset kill tracking
	faction_kills = { "zenith": 0, "aurelia": 0, "vanguard": 0 }
	print("[GlobalState] State reset for new game.")


# ── Ship Upgrade Logic ────────────────────────────────────────────────────────

func apply_upgrade_stats():
	# Reset stats to base first
	cargo_max = SHIP_BASE_STATS["cargo_max_m3"]
	mining_yield = SHIP_BASE_STATS["mining_laser_yield"]
	mining_cooldown = SHIP_BASE_STATS["mining_cooldown"]
	weapon_damage = SHIP_BASE_STATS["weapon_damage"]
	weapon_cooldown = SHIP_BASE_STATS["weapon_cooldown"]
	shield_capacity = SHIP_BASE_STATS["shield_capacity"]
	shield_regen_delay = SHIP_BASE_STATS["shield_regen_delay"]
	shield_regen_rate = SHIP_BASE_STATS["shield_regen_rate"]
	engine_speed_mult = SHIP_BASE_STATS["engine_speed_mult"]
	acceleration_mult = SHIP_BASE_STATS["acceleration_mult"]
	ignore_cargo_mass = SHIP_BASE_STATS["ignore_cargo_mass"]
	hull_armor = SHIP_BASE_STATS["hull_armor"]
	player_max_health = SHIP_BASE_STATS["max_health"]
	power_capacity = 300.0

	has_max_rapid_weapon = false
	has_max_heavy_weapon = false
	has_max_speed_engine = false
	has_max_hauler_engine = false
	has_max_bulwark_shield = false
	has_max_deflector_shield = false
	has_max_rapid_mining = false
	has_max_deep_mining = false

	# Apply tier data
	for sys in current_upgrades.keys():
		var info = current_upgrades[sys]
		var tier = info["tier"]
		if tier > 1:
			var path = info["path"]
			if UPGRADE_TREE.has(sys) and UPGRADE_TREE[sys]["branches"].has(path):
				var tier_data = UPGRADE_TREE[sys]["branches"][path][tier]
				if tier_data.has("capacity"):
					power_capacity = float(tier_data["capacity"])
				if tier_data.has("stats"):
					for stat_key in tier_data["stats"].keys():
						set(stat_key, tier_data["stats"][stat_key])

	# Update player health bounds
	if player and is_instance_valid(player):
		var p_max = player.get("max_health")
		if player.get("health") >= p_max - 0.01:
			player.set("max_health", player_max_health)
			player.set("health", player_max_health)
		else:
			player.set("max_health", player_max_health)
			player.set("health", min(player.get("health"), player_max_health))

func get_current_power_draw() -> float:
	var total = 0.0
	for sys in current_upgrades.keys():
		if sys == "power": continue
		
		var info = current_upgrades[sys]
		var tier = info["tier"]
		if tier == 1:
			if UPGRADE_TREE.has(sys):
				total += UPGRADE_TREE[sys]["base_power"]
		else:
			var path = info["path"]
			if UPGRADE_TREE.has(sys) and UPGRADE_TREE[sys]["branches"].has(path):
				total += UPGRADE_TREE[sys]["branches"][path][tier]["power"]
	return total

func purchase_upgrade(sys: String, path: String) -> bool:
	var info = current_upgrades[sys]
	var next_tier = info["tier"] + 1
	if next_tier > 5:
		return false # Maxed
		
	# If branching at tier 2
	if info["tier"] == 1:
		pass # Any path is valid
	else:
		if info["path"] != path:
			# Trying to switch paths? Must use refund_upgrade explicitly.
			return false 
			
	if not UPGRADE_TREE[sys]["branches"].has(path):
		return false
	if not UPGRADE_TREE[sys]["branches"][path].has(next_tier):
		return false
		
	var data = UPGRADE_TREE[sys]["branches"][path][next_tier]
	var cost_cr = data["cost_cr"]
	var cost_ore = data["cost_ore"]
	var next_power = data.get("power", 0)
	
	var current_power = UPGRADE_TREE[sys]["base_power"]
	if info["tier"] > 1:
		current_power = UPGRADE_TREE[sys]["branches"][info["path"]][info["tier"]].get("power", 0)
		
	var power_diff = next_power - current_power
	if sys != "power" and get_current_power_draw() + power_diff > power_capacity:
		return false # Insufficient power
		
	if player_credits < cost_cr:
		return false
		
	# Check combined ore from cargo + storage
	var total_ore = 0.0
	if cargo_type == CargoType.ORE:
		total_ore += cargo
	total_ore += player_storage_ore
	
	if total_ore < cost_ore:
		return false
		
	# Deduct
	player_credits -= cost_cr
	var remaining_ore_cost = cost_ore
	if cargo_type == CargoType.ORE:
		if cargo >= remaining_ore_cost:
			cargo -= remaining_ore_cost
			remaining_ore_cost = 0
		else:
			remaining_ore_cost -= cargo
			cargo = 0.0
		normalize_cargo_state()
	
	player_storage_ore -= remaining_ore_cost
	
	current_upgrades[sys] = {"tier": next_tier, "path": path}
	apply_upgrade_stats()
	print("[GlobalState] Upgraded %s to tier %d path %s" % [sys, next_tier, path])
	return true

func refund_upgrade(sys: String):
	var info = current_upgrades[sys]
	if info["tier"] <= 1:
		return
		
	var path = info["path"]
	var tier = info["tier"]
	
	var total_cr_refund = 0
	var total_ore_refund = 0
	
	for t in range(2, tier + 1):
		var data = UPGRADE_TREE[sys]["branches"][path][t]
		total_cr_refund += int(data["cost_cr"] * 0.5)
		total_ore_refund += int(data["cost_ore"] * 0.5)
		
	player_credits += total_cr_refund
	player_storage_ore += total_ore_refund
	if player_storage_ore > player_storage_max:
		player_storage_ore = player_storage_max
		
	current_upgrades[sys] = {"tier": 1, "path": "base"}
	apply_upgrade_stats()

func deposit_ore(amount: float) -> bool:
	if cargo_type != CargoType.ORE or cargo < amount:
		return false
	if player_storage_ore + amount > player_storage_max:
		return false
		
	cargo -= amount
	player_storage_ore += amount
	if cargo <= 0.0:
		clear_cargo()
	return true



func _setup_inputs():
	# Define EVE-like override autopilot keys
	_add_key_action("override_approach", KEY_Q)
	_add_key_action("override_orbit", KEY_W)
	_add_key_action("override_action", KEY_E)
	_add_key_action("pause_game", KEY_ESCAPE)
	_add_key_action("action_jump", KEY_J)
	
	# Define mouse zoom actions
	_add_mouse_action("zoom_in", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse_action("zoom_out", MOUSE_BUTTON_WHEEL_DOWN)

func _add_key_action(action_name: String, keycode: int):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var event = InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action_name, event)

func _add_mouse_action(action_name: String, button_index: int):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var event = InputEventMouseButton.new()
		event.button_index = button_index
		InputMap.action_add_event(action_name, event)

# ── Dialogue Tone Guard ──────────────────────────────────────────────────────
# "Shiny" is Broker Kaelen's vocative for the player pilot. She uses it
# every line. Every other speaker in the game should NOT use it — it
# leaks her voice onto Jenna, minor NPCs, future quest givers, and
# anything else routed through the dialogue pipeline.
#
# This is a pure function — no state, no side effects. Safe to call from
# any thread or signal handler. SpeechService routes its text through
# here, and any UI code that displays dialogue should too, so the
# on-screen text and the spoken audio stay in sync.
#
# Kaelen's voice after faction resolution is "af_bella" — that's how
# the call path identifies her. Anyone else gets the substitution.
const KAELEN_VOICE_PROFILE_ID: String = "voice.kaelen.v1"
const KAELEN_VOICE_ID: String = "af_bella"

# Substitutions for non-Kaelen speakers. Keyed on the source token
# (case-insensitive, word-boundary aware). Each entry's "to" is tried
# in order — first match wins. Add more rules here as more voice-leak
# bugs show up.
const TONE_REPLACEMENTS: Array = [
	# "Shiny" → "Indy" (preserves the call-out feel; matches the
	# player's ship class name, so it reads as "Indy pilot").
	{ "from": "shiny", "to": ["indy"] },
]

# Returns true if the resolved voice_id is Kaelen's. Cheap pointer
# check against KAELEN_VOICE_ID. Keep in sync with TTSInterface's
# get_voice_for_faction("neutral") — if you add a new broker voice
# for Kaelen, update both.
static func is_kaelen_voice(voice_id: String) -> bool:
	return voice_id in [KAELEN_VOICE_PROFILE_ID, KAELEN_VOICE_ID]

# Apply all TONE_REPLACEMENTS rules to `text` for a non-Kaelen speaker.
# Case-insensitive on the source token, but the replacement preserves
# the original casing style of the source (Title Case → "Indy", lower →
# "indy", upper → "INDY"). Word-boundary aware so we don't replace
# "Shiny" inside "Shinyman" or "Mishiny". Pure function.
static func apply_tone_guard(text: String, voice_id: String) -> String:
	# Kaelen keeps her own voice untouched.
	if is_kaelen_voice(voice_id):
		return text
	var out: String = text
	for rule in TONE_REPLACEMENTS:
		var from_token: String = rule["from"]
		var to_options: Array = rule["to"]
		# Build a word-boundary regex. (?i) for case-insensitive.
		# \b on either side keeps it from matching mid-word. We then
		# reconstruct the replacement in the original casing style.
		var regex := RegEx.new()
		regex.compile("(?i)\\b" + from_token + "\\b")
		var matches := regex.search_all(out)
		if matches.is_empty():
			continue
		# Replace from the back so earlier indices stay valid.
		for i in range(matches.size() - 1, -1, -1):
			var m: RegExMatch = matches[i]
			var original: String = m.get_string()
			# Pick the first option as the canonical replacement, then
			# match the original's casing style: ALL CAPS → upper,
			# Title Case → capitalized, else lower. Keeps the line
			# reading naturally in either case.
			var canonical: String = str(to_options[0])
			var replacement: String = _match_tone_casing(canonical, original)
			out = out.substr(0, m.get_start()) + replacement + out.substr(m.get_end())
	return out

# Internal: rebuild `replacement` in the casing style of `original`.
# "SHINY" → "INDY", "Shiny" → "Indy", "shiny" → "indy". Falls back to
# the canonical lowercase if the original's style doesn't match any
# recognized pattern.
static func _match_tone_casing(canonical: String, original: String) -> String:
	if original.length() == 0:
		return canonical
	if original == original.to_upper() and original != original.to_lower():
		return canonical.to_upper()
	if original[0] >= "A" and original[0] <= "Z":
		return canonical.capitalize()
	return canonical
