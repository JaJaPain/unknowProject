extends Node

const IllegalMiningEnforcementType := preload(
	"res://scripts/systems/IllegalMiningEnforcement.gd"
)
const ILLEGAL_MINING_WITNESS_RADIUS := 220.0

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
	"inventory_slots":    8,
	"ore_bank_max":       1000.0,
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
		"base_power": 55,
		"branches": {
			"rapid": {
				2: { "cost_cr": 200, "cost_ore": 50, "power": 65, "stats": {"weapon_cooldown": 0.6, "weapon_damage": 20} },
				3: { "cost_cr": 400, "cost_ore": 100, "power": 75, "stats": {"weapon_cooldown": 0.45, "weapon_damage": 20} },
				4: { "cost_cr": 800, "cost_ore": 200, "power": 90, "stats": {"weapon_cooldown": 0.35, "weapon_damage": 20} },
				5: { "cost_cr": 1600, "cost_ore": 400, "power": 110, "stats": {"weapon_cooldown": 0.25, "weapon_damage": 20, "has_max_rapid_weapon": true} }
			},
			"heavy": {
				2: { "cost_cr": 200, "cost_ore": 50, "power": 75, "stats": {"weapon_cooldown": 0.8, "weapon_damage": 30} },
				3: { "cost_cr": 400, "cost_ore": 100, "power": 90, "stats": {"weapon_cooldown": 0.9, "weapon_damage": 45} },
				4: { "cost_cr": 800, "cost_ore": 200, "power": 110, "stats": {"weapon_cooldown": 1.0, "weapon_damage": 65} },
				5: { "cost_cr": 1600, "cost_ore": 400, "power": 135, "stats": {"weapon_cooldown": 1.1, "weapon_damage": 90, "has_max_heavy_weapon": true} }
			}
		}
	},
	"engine": {
		"base_power": 85,
		"branches": {
			"speed": {
				2: { "cost_cr": 250, "cost_ore": 0, "power": 105, "stats": {"engine_speed_mult": 1.2, "acceleration_mult": 1.2} },
				3: { "cost_cr": 500, "cost_ore": 50, "power": 125, "stats": {"engine_speed_mult": 1.4, "acceleration_mult": 1.4} },
				4: { "cost_cr": 1000, "cost_ore": 100, "power": 150, "stats": {"engine_speed_mult": 1.6, "acceleration_mult": 1.6} },
				5: { "cost_cr": 2000, "cost_ore": 200, "power": 180, "stats": {"engine_speed_mult": 1.9, "acceleration_mult": 1.9, "has_max_speed_engine": true} }
			},
			"hauler": {
				2: { "cost_cr": 250, "cost_ore": 100, "power": 100, "stats": {"ignore_cargo_mass": true, "engine_speed_mult": 1.0, "acceleration_mult": 1.0} },
				3: { "cost_cr": 500, "cost_ore": 200, "power": 115, "stats": {"ignore_cargo_mass": true, "engine_speed_mult": 1.05, "acceleration_mult": 1.05} },
				4: { "cost_cr": 1000, "cost_ore": 400, "power": 135, "stats": {"ignore_cargo_mass": true, "engine_speed_mult": 1.1, "acceleration_mult": 1.1} },
				5: { "cost_cr": 2000, "cost_ore": 800, "power": 155, "stats": {"ignore_cargo_mass": true, "engine_speed_mult": 1.15, "acceleration_mult": 1.15, "has_max_hauler_engine": true, "hull_armor": -10} }
			}
		}
	},
	"shields": {
		"base_power": 15,
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
		"base_power": 80,
		"branches": {
			"rapid": {
				2: { "cost_cr": 150, "cost_ore": 50, "power": 115, "stats": {"mining_cooldown": 0.8, "mining_laser_yield": 1.0} },
				3: { "cost_cr": 300, "cost_ore": 100, "power": 140, "stats": {"mining_cooldown": 0.6, "mining_laser_yield": 1.0} },
				4: { "cost_cr": 600, "cost_ore": 200, "power": 165, "stats": {"mining_cooldown": 0.4, "mining_laser_yield": 1.0} },
				5: { "cost_cr": 1200, "cost_ore": 400, "power": 195, "stats": {"mining_cooldown": 0.2, "mining_laser_yield": 1.0, "has_max_rapid_mining": true} }
			},
			"deep": {
				2: { "cost_cr": 150, "cost_ore": 100, "power": 115, "stats": {"mining_cooldown": 1.2, "mining_laser_yield": 2.0} },
				3: { "cost_cr": 300, "cost_ore": 200, "power": 140, "stats": {"mining_cooldown": 1.5, "mining_laser_yield": 4.0} },
				4: { "cost_cr": 600, "cost_ore": 400, "power": 165, "stats": {"mining_cooldown": 1.8, "mining_laser_yield": 8.0} },
				5: { "cost_cr": 1200, "cost_ore": 800, "power": 195, "stats": {"mining_cooldown": 2.5, "mining_laser_yield": 15.0, "has_max_deep_mining": true} }
			}
		}
	},
	"cargo": {
		"base_power": 5,
		"branches": {
			"standard": {
				2: { "cost_cr": 100, "cost_ore": 100, "power": 10, "stats": {"cargo_max_m3": 150.0, "ore_bank_max": 3000.0} },
				3: { "cost_cr": 200, "cost_ore": 200, "power": 15, "stats": {"cargo_max_m3": 250.0, "ore_bank_max": 8000.0} },
				4: { "cost_cr": 400, "cost_ore": 400, "power": 20, "stats": {"cargo_max_m3": 400.0, "ore_bank_max": 20000.0} },
				5: { "cost_cr": 800, "cost_ore": 800, "power": 25, "stats": {"cargo_max_m3": 600.0, "ore_bank_max": 50000.0} }
			}
		}
	},
	"storage": {
		"base_power": 5,
		"branches": {
			"standard": {
				2: { "cost_cr": 200, "cost_ore": 100, "power": 8, "stats": {"inventory_slots": 10} },
				3: { "cost_cr": 600, "cost_ore": 300, "power": 12, "stats": {"inventory_slots": 12} },
				4: { "cost_cr": 1800, "cost_ore": 900, "power": 16, "stats": {"inventory_slots": 14} },
				5: { "cost_cr": 5400, "cost_ore": 2700, "power": 20, "stats": {"inventory_slots": 16} },
				6: { "cost_cr": 16000, "cost_ore": 8000, "power": 25, "stats": {"inventory_slots": 18} },
				7: { "cost_cr": 48000, "cost_ore": 24000, "power": 30, "stats": {"inventory_slots": 20} }
			}
		}
	},
	"sensors": {
		"base_power": 10,
		"branches": {
			"standard": {
				2: { "cost_cr": 300, "cost_ore": 80, "power": 20, "stats": {"sensor_tier": 1} },
				3: { "cost_cr": 900, "cost_ore": 240, "power": 35, "stats": {"sensor_tier": 2} }
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
	if faction_name.begins_with("gen_") or faction_name.begins_with("faction.generated."):
		return true
	var definition := GameContentRegistry.shared().faction(faction_name)
	return definition != null and definition.classification == "minor"

static func minor_faction_data(faction_name: String) -> Dictionary:
	if faction_name.begins_with("gen_") or faction_name.begins_with("faction.generated."):
		var generated := _generated_faction_record(faction_name)
		var color := _generated_faction_color(generated, faction_name)
		var ship_style: Dictionary = generated.get("ship_style", {})
		return {
			"color": color,
			"projectile": color.lightened(0.15),
			"model": str(ship_style.get("model", "faction1")),
			"tint": color.darkened(0.18),
			"ship_style": ship_style.duplicate(true),
		}
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
	var generated := _generated_faction_record(faction_id)
	if not generated.is_empty():
		return {
			"name": str(generated.get("display_name", faction_id.capitalize())),
			"descriptor": str(generated.get("descriptor", "Generated Frontier Faction")),
			"abbrev": str(generated.get("abbreviation", faction_id.substr(0, 3).to_upper())),
		}
	return {"name": faction_id.capitalize(), "descriptor": "Unknown", "abbrev": faction_id.substr(0, 3).to_upper()}

static func faction_display_name(faction_id: String, adjective: bool = false) -> String:
	var clean := faction_id.strip_edges()
	if clean.is_empty():
		return "Unknown"
	var definition := GameContentRegistry.shared().faction(clean)
	if definition:
		var display := str(definition.display_name)
		if adjective and clean in ["reavers", "faction.reavers", "wraiths", "faction.wraiths"]:
			return display.trim_suffix("s")
		return display
	var generated := _generated_faction_record(clean)
	if not generated.is_empty():
		return str(generated.get("display_name", _title_faction_key(clean)))
	return _title_faction_key(clean)


static func _title_faction_key(faction_id: String) -> String:
	var clean := faction_id.strip_edges().to_lower()
	if clean.begins_with("faction.generated."):
		clean = clean.trim_prefix("faction.generated.")
	elif clean.begins_with("faction."):
		clean = clean.trim_prefix("faction.")
	if clean.begins_with("gen_"):
		clean = clean.trim_prefix("gen_")
	var parts := clean.replace(".", "_").replace("-", "_").split("_", false)
	var titled: Array[String] = []
	for part in parts:
		if part.is_valid_int():
			continue
		if part.length() <= 1:
			continue
		titled.append(part.substr(0, 1).to_upper() + part.substr(1))
	if titled.is_empty():
		return "Local"
	return " ".join(titled)

# Returns the AtlasTexture for a minor NPC's portrait, sliced from its 2x2
# source image at the cell position stored in MINOR_NPCS.
# Returns null if the name isn't recognized or the image fails to load.
static func get_minor_npc_portrait(npc_name: String) -> AtlasTexture:
	if generated_outpost_npc_data.has(npc_name):
		var generated_data: Dictionary = generated_outpost_npc_data[npc_name]
		return GameContentRegistry.shared().portrait_texture(
			generated_data.get("portrait_id", "")
		)
	var definition := GameContentRegistry.shared().npc_by_name(npc_name)
	if definition == null:
		return null
	return GameContentRegistry.shared().portrait_texture(definition.portrait_id)

static func get_minor_npc_data(npc_name: String) -> Dictionary:
	if generated_outpost_npc_data.has(npc_name):
		return generated_outpost_npc_data[npc_name].duplicate(true)
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
static var generated_outpost_npcs: Dictionary = {}
static var generated_outpost_npc_data: Dictionary = {}
static var npc_line_memory: Dictionary = {}
static var campaign_npc_identity_store = null
static var campaign_agent_memory_store = null

const GENERATED_CONTACT_FIRST_NAMES: Array[String] = [
	"Rook",
	"Vale",
	"Mara",
	"Sable",
	"Juno",
	"Nyx",
	"Orin",
	"Vexa",
	"Tamsin",
	"Corin",
	"Ivara",
	"Ren",
]
const GENERATED_CONTACT_LAST_NAMES: Array[String] = [
	"Kade",
	"Sol",
	"Venn",
	"Dray",
	"Quill",
	"Marl",
	"Rusk",
	"Thane",
	"Voss",
	"Keir",
	"Rook",
	"Calder",
]
const GENERATED_CONTACT_PORTRAITS: Array[String] = [
	"portrait.minor_npc_01.cassen_vane",
	"portrait.minor_npc_01.mariska_vonn",
	"portrait.minor_npc_01.korvin_shaw",
	"portrait.minor_npc_01.hana_quill",
	"portrait.minor_npc_02.oleg_stroud",
	"portrait.minor_npc_02.dasha_invar",
	"portrait.minor_npc_02.alaric_venn",
]
const GENERATED_CONTACT_VOICES: Array[String] = [
	"voice.cassen_vane.v1",
	"voice.mariska_vonn.v1",
	"voice.korvin_shaw.v1",
	"voice.hana_quill.v1",
	"voice.oleg_stroud.v1",
	"voice.dasha_invar.v1",
	"voice.alaric_venn.v1",
]
const GENERATED_CONTACT_LINES: Array[String] = [
	"Local board's thin today, but the trouble is fresh.",
	"New system, old math: fuel, favors, and someone else's mess.",
	"You need a contact out here, you talk to whoever is still breathing.",
	"The gate crews keep secrets. The station crews sell them by the cup.",
	"Don't trust clean paperwork past the frontier gate.",
]
const GENERATED_MECHANIC_LINES: Array[String] = [
	"Your ship is talking in repair bills. I speak that dialect.",
	"Frontier maintenance rule: if it is still smoking, it is still negotiable.",
	"Bring me dents, leaks, and bad decisions. I invoice all three.",
	"I can fix honest damage. Political damage costs extra.",
]
const GENERATED_CONTACT_FACTION_LINES := {
	"reavers": [
		"Reaver work is simple: take the job, take the risk, take payment first.",
		"Keep your beacon cold out there. Reaver crews respect quiet engines.",
		"If you heard screaming on comms, that was negotiation.",
	],
	"obsidian": [
		"Obsidian ledgers remember every debt, even the ones written in vacuum.",
		"The station looks neutral. The accounts under it aren't.",
		"If an Obsidian broker smiles, count your credits twice.",
	],
	"dustborn": [
		"Dustborn routes aren't pretty, but they still pay when the clean lanes fail.",
		"Out here, every filter, seal, and water tank has a story.",
		"Corporate charts call this empty space. Dustborn crews call it home.",
	],
	"wraiths": [
		"Wraiths don't vanish. They just make sure you're looking the wrong way.",
		"If the scope shows nothing, assume the Wraiths got there first.",
		"Some jobs need a signature. Wraith jobs need a rumor.",
	],
	"ironclad": [
		"Ironclad convoys move slow because they know they can survive the argument.",
		"Steel, discipline, and a paid invoice. That's the Ironclad way.",
		"People mock the armor until the first volley hits.",
	],
}
const GENERATED_CONTACT_FACTION_HANDOFF_LINES := {
	"reavers": [
		"Cargo's yours. Reaver rule: lose it and the debt follows you.",
		"Loaded hot and clean. Don't fly it like a tourist.",
	],
	"obsidian": [
		"Transfer logged. Obsidian receipts have long memories.",
		"The part is aboard. The fee cleared before you docked.",
	],
	"dustborn": [
		"Packed it myself. Dustborn seals hold better than station promises.",
		"Part's in your bay. Keep it out of grit and corporate hands.",
	],
	"wraiths": [
		"Package is aboard. If anyone asks, it never existed.",
		"Clean handoff. Wraith clean, meaning nobody saw enough to matter.",
	],
	"ironclad": [
		"Manifest signed, crate secured. Ironclad doesn't do loose ends.",
		"Part's locked down. Bring it back in one piece or bring the reason.",
	],
}

static func get_minor_npcs_at_outpost(outpost_id: String) -> Array:
	if generated_outpost_npcs.has(outpost_id):
		return generated_outpost_npcs[outpost_id].duplicate()
	var result: Array = []
	for npc_name in MINOR_NPCS:
		if MINOR_NPCS[npc_name].get("outpost", "") == outpost_id:
			result.append(npc_name)
	return result

static func assign_generated_outpost_npcs(
	world_id: String,
	seed_value: int,
	faction_weights: Dictionary = {}
) -> Array:
	if generated_outpost_npcs.has(world_id):
		return generated_outpost_npcs[world_id].duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := 2 + (1 if rng.randf() < 0.4 else 0)
	var picked: Array = []
	for index in range(count):
		var faction_name := _pick_generated_contact_faction(faction_weights, rng)
		var npc_name := _generated_contact_name(world_id, rng, index, faction_name)
		picked.append(npc_name)
		var npc_data := _generated_contact_data(
			world_id,
			npc_name,
			rng,
			index,
			faction_name
		)
		generated_outpost_npc_data[npc_name] = _persist_generated_contact_identity(
			npc_name,
			npc_data
		)
	generated_outpost_npcs[world_id] = picked
	return picked.duplicate()

static func assign_generated_station_npcs(
	world_id: String,
	seed_value: int,
	faction_weights: Dictionary = {}
) -> Array:
	if generated_outpost_npcs.has(world_id):
		return generated_outpost_npcs[world_id].duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var picked: Array = []
	var faction_names := _generated_station_contact_faction_keys(faction_weights)
	for faction_name in faction_names:
		var npc_name := _generated_contact_name(
			world_id,
			rng,
			picked.size(),
			faction_name
		)
		picked.append(npc_name)
		var npc_data := _generated_contact_data(
			world_id,
			npc_name,
			rng,
			picked.size(),
			faction_name,
			"Faction contact"
		)
		generated_outpost_npc_data[npc_name] = _persist_generated_contact_identity(
			npc_name,
			npc_data
		)
	var mechanic_name := _generated_contact_name(
		world_id,
		rng,
		picked.size(),
		"",
		"Mechanic"
	)
	picked.append(mechanic_name)
	var mechanic_data := _generated_contact_data(
		world_id,
		mechanic_name,
		rng,
		picked.size(),
		"",
		"Station mechanic"
	)
	generated_outpost_npc_data[mechanic_name] = _persist_generated_contact_identity(
		mechanic_name,
		mechanic_data
	)
	generated_outpost_npcs[world_id] = picked
	return picked.duplicate()

static func _generated_contact_name(
	world_id: String,
	rng: RandomNumberGenerator,
	index: int,
	faction_name: String = "",
	role_prefix: String = ""
) -> String:
	var first := GENERATED_CONTACT_FIRST_NAMES[
		rng.randi() % GENERATED_CONTACT_FIRST_NAMES.size()
	]
	var last := GENERATED_CONTACT_LAST_NAMES[
		rng.randi() % GENERATED_CONTACT_LAST_NAMES.size()
	]
	var faction_display := ""
	if not faction_name.is_empty():
		faction_display = str(faction_info(faction_name).get("name", faction_name.capitalize()))
	var name := "%s %s" % [first, last]
	if not faction_display.is_empty():
		name = "%s %s" % [faction_display, name]
	elif not role_prefix.is_empty():
		name = "%s %s" % [role_prefix, name]
	if generated_outpost_npc_data.has(name):
		name = "%s %s" % [name, world_id.sha256_text().substr(index * 2, 2).to_upper()]
	return name

static func _generated_contact_data(
	world_id: String,
	npc_name: String,
	rng: RandomNumberGenerator,
	index: int,
	faction_name: String = "",
	role: String = "Local contact"
) -> Dictionary:
	var presentation_index := (index + int(rng.randi())) % GENERATED_CONTACT_PORTRAITS.size()
	var portrait_id := GENERATED_CONTACT_PORTRAITS[presentation_index]
	var voice_id := GENERATED_CONTACT_VOICES[presentation_index]
	var contact_lines := GENERATED_CONTACT_LINES.duplicate()
	if GENERATED_CONTACT_FACTION_LINES.has(faction_name):
		contact_lines.append_array(GENERATED_CONTACT_FACTION_LINES[faction_name])
	if role == "Station mechanic":
		contact_lines = GENERATED_MECHANIC_LINES.duplicate()
	var handoff_lines: Array = [
		"Part's in your bay. Around here, that counts as a clean handoff.",
		"You got what you came for. Don't make the route back interesting.",
		"Loaded and logged. Tell the mechanic this one was local trouble, not mine.",
		"There. Frontier parts, frontier warranty: none.",
	]
	if GENERATED_CONTACT_FACTION_HANDOFF_LINES.has(faction_name):
		handoff_lines.append_array(GENERATED_CONTACT_FACTION_HANDOFF_LINES[faction_name])
	var faction_color := Color.WHITE
	if not faction_name.is_empty():
		var fdata := minor_faction_data(faction_name)
		faction_color = fdata.get("color", faction_color)
	var hue := rng.randf()
	return {
		"outpost": world_id,
		"display_name": npc_name,
		"role": role,
		"faction": faction_name,
		"faction_id": _contact_faction_id(faction_name),
		"portrait_id": portrait_id,
		"voice_profile_id": voice_id,
		"personality_tags": _generated_contact_personality_tags(role, faction_name),
		"humor_style": _generated_contact_humor_style(role, faction_name),
		"relationship_state": "neutral",
		"memory_summary": "%s works from %s as a %s." % [
			npc_name,
			world_id,
			role.to_lower(),
		],
		"line_memory_fingerprints": [],
		"lifecycle": {
			"available": true,
			"relocated": false,
			"captured": false,
			"dead": false,
			"protected": false,
		},
		"flavor_color": faction_color if not faction_name.is_empty() else Color.from_hsv(hue, 0.45, 1.0),
		"flavor_lines": contact_lines,
		"pickup_handoff_fallback_lines": handoff_lines,
	}

static func _persist_generated_contact_identity(
	npc_name: String,
	npc_data: Dictionary
) -> Dictionary:
	var enriched := npc_data.duplicate(true)
	enriched["display_name"] = npc_name
	if campaign_npc_identity_store == null:
		return enriched
	if not campaign_npc_identity_store.has_method("ensure_npc_record"):
		return enriched
	var identity_source := {
		"source_key": "%s|%s|%s|%s" % [
			str(npc_data.get("outpost", "")),
			npc_name,
			str(npc_data.get("role", "")),
			str(npc_data.get("faction_id", "")),
		],
		"display_name": npc_name,
		"portrait_id": str(npc_data.get("portrait_id", "")),
		"voice_profile_id": str(npc_data.get("voice_profile_id", "")),
		"faction_id": str(npc_data.get("faction_id", "")),
		"faction_key": str(npc_data.get("faction", "")),
		"job_role": str(npc_data.get("role", "Local contact")),
		"home_system_id": _system_id_from_station_id(str(npc_data.get("outpost", ""))),
		"home_station_id": str(npc_data.get("outpost", "")),
		"personality_tags": npc_data.get("personality_tags", []),
		"humor_style": str(npc_data.get("humor_style", "")),
		"relationship_state": str(npc_data.get("relationship_state", "neutral")),
		"memory_summary": str(npc_data.get("memory_summary", "")),
		"line_memory_fingerprints": npc_data.get("line_memory_fingerprints", []),
		"lifecycle": npc_data.get("lifecycle", {}),
	}
	var ensured: Dictionary = campaign_npc_identity_store.ensure_npc_record(identity_source)
	if not bool(ensured.get("ok", false)):
		push_warning(
			"[GlobalState] Generated NPC identity was not persisted: %s" %
				str(ensured.get("error", "unknown error"))
		)
		return enriched
	var record: Dictionary = ensured.get("npc", {})
	enriched["npc_id"] = str(record.get("id", ""))
	enriched["identity_record"] = record
	return enriched

static func _system_id_from_station_id(station_id: String) -> String:
	var marker := ".station."
	var station_index := station_id.find(marker)
	if station_index > 0:
		return station_id.substr(0, station_index)
	if station_id.begins_with("station."):
		var parts := station_id.split(".")
		if parts.size() >= 3:
			return "%s.%s" % [parts[0], parts[1]]
	return ""

static func _generated_contact_personality_tags(
	role: String,
	faction_name: String
) -> Array:
	var tags: Array = ["frontier", role.to_lower().replace(" ", "_")]
	if not faction_name.is_empty():
		tags.append(faction_name)
	if role == "Station mechanic":
		tags.append("practical")
	else:
		tags.append("deal_minded")
	return tags

static func _generated_contact_humor_style(role: String, faction_name: String) -> String:
	if role == "Station mechanic":
		return "dry repair-bay sarcasm"
	if faction_name.is_empty():
		return "deadpan frontier gossip"
	var generated := _generated_faction_record(faction_name)
	if not generated.is_empty():
		return str(generated.get("humor_style", "dry faction wit"))
	return "dry faction wit"

static func _pick_generated_contact_faction(
	faction_weights: Dictionary,
	rng: RandomNumberGenerator
) -> String:
	var weighted_factions := _generated_contact_faction_keys(faction_weights)
	if weighted_factions.is_empty():
		return ""
	var total := 0.0
	for faction_name in weighted_factions:
		total += maxf(0.0, float(faction_weights.get(faction_name, 0.0)))
	if total <= 0.0:
		return str(weighted_factions[rng.randi() % weighted_factions.size()])
	var roll := rng.randf() * total
	var cumulative := 0.0
	for faction_name in weighted_factions:
		cumulative += maxf(0.0, float(faction_weights.get(faction_name, 0.0)))
		if roll <= cumulative:
			return str(faction_name)
	return str(weighted_factions.back())

static func _generated_contact_faction_keys(faction_weights: Dictionary) -> Array:
	var result: Array = []
	for faction_name in faction_weights.keys():
		if is_minor_faction(str(faction_name)):
			result.append(str(faction_name))
	if result.is_empty():
		for faction_name in MINOR_FACTIONS.keys():
			result.append(str(faction_name))
	return result

static func _generated_station_contact_faction_keys(faction_weights: Dictionary) -> Array:
	var result: Array = []
	for faction_name in faction_weights.keys():
		var clean := str(faction_name).strip_edges()
		if not clean.is_empty():
			result.append(clean)
	if result.is_empty():
		result.append_array(["zenith", "aurelia", "vanguard"])
	return result

static func _contact_faction_id(faction_name: String) -> String:
	if faction_name.is_empty():
		return ""
	var generated := _generated_faction_record(faction_name)
	if not generated.is_empty():
		return str(generated.get("id", ""))
	if faction_name.begins_with("faction."):
		return faction_name
	return "faction.%s" % faction_name

static func resolve_outpost_id(station: Node3D) -> String:
	if station == null:
		return ""
	var world_id = station.get("world_id") if station.get("world_id") else ""
	if typeof(world_id) == TYPE_STRING and generated_outpost_npcs.has(world_id):
		return world_id
	return ""

# Returns the outpost id for a minor NPC, or "" if they aren't outpost-based
# (e.g. the mechanic, who lives at Grease Monkeys).
static func get_minor_npc_outpost(npc_name: String) -> String:
	if generated_outpost_npc_data.has(npc_name):
		return str(generated_outpost_npc_data[npc_name].get("outpost", ""))
	if not MINOR_NPCS.has(npc_name):
		return ""
	return MINOR_NPCS[npc_name].get("outpost", "")

static func get_current_system_outposts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tree := Engine.get_main_loop()
	var state = (
		tree.root.get_node_or_null("GlobalState")
		if tree and tree.root
		else null
	)
	var entities: Array = (
		state.get("active_system_entities")
		if state != null
		else []
	)
	for entity in entities:
		if not is_instance_valid(entity):
			continue
		if not entity is Node3D:
			continue
		if not entity.is_in_group("station"):
			continue
		var raw_station_type: Variant = entity.get("station_type")
		var station_type := str(raw_station_type) if raw_station_type != null else ""
		if station_type.is_empty() or station_type == "<null>":
			station_type = str(entity.get_meta("station_type", ""))
		if station_type != "outpost":
			continue
		var outpost_id := resolve_outpost_id(entity)
		if outpost_id.is_empty():
			var raw_world_id: Variant = entity.get("world_id")
			outpost_id = str(raw_world_id) if raw_world_id != null else ""
		if outpost_id.is_empty() or outpost_id == "<null>":
			outpost_id = str(entity.get_meta("world_id", ""))
		if outpost_id.is_empty():
			continue
		var raw_display_name: Variant = entity.get("display_name")
		var display := str(raw_display_name) if raw_display_name != null else ""
		if display.is_empty() or display == "<null>":
			display = str(entity.get_meta("display_name", ""))
		result.append({
			"id": outpost_id,
			"display": display if not display.is_empty() else outpost_id,
		})
	return result

static func is_current_system_home() -> bool:
	var tree := Engine.get_main_loop()
	var state = (
		tree.root.get_node_or_null("GlobalState")
		if tree and tree.root
		else null
	)
	var sys_id: String = state.get("current_system_id") if state else "start_system"
	return sys_id == "start_system" or sys_id == "system.start"

static func starter_pickup_outposts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for starter_id in PICKUP_OUTPOST_IDS:
		result.append({
			"id": str(starter_id),
			"display": str(PICKUP_OUTPOST_DISPLAY.get(starter_id, starter_id)),
		})
	return result

static func get_current_pickup_outposts() -> Array[Dictionary]:
	var outposts := get_current_system_outposts()
	if outposts.is_empty() and is_current_system_home():
		return starter_pickup_outposts()
	return outposts

static func get_current_system_minor_factions() -> Array[String]:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.current_scene and "system_registry" in tree.current_scene:
		var state = tree.root.get_node_or_null("GlobalState")
		var sys_id: String = state.get("current_system_id") if state else "start_system"
		var registry = tree.current_scene.system_registry
		if registry != null:
			var sys_def = registry.get_system(sys_id)
			if sys_def != null and not sys_def.faction_ids.is_empty():
				var factions: Array[String] = []
				for fid in sys_def.faction_ids:
					var legacy := _legacy_faction_key_for_system_id(
						str(fid),
						sys_def.legacy_id,
						registry
					)
					if is_minor_faction(legacy):
						factions.append(legacy)
				if not factions.is_empty():
					return factions
	var fallback: Array[String] = []
	fallback.assign(MINOR_FACTIONS.keys())
	return fallback


static func get_current_system_factions() -> Array[String]:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.current_scene and "system_registry" in tree.current_scene:
		var state = tree.root.get_node_or_null("GlobalState")
		var sys_id: String = state.get("current_system_id") if state else "start_system"
		var registry = tree.current_scene.system_registry
		if registry != null:
			var sys_def = registry.get_system(sys_id)
			if sys_def != null and not sys_def.faction_ids.is_empty():
				var factions: Array[String] = []
				for fid in sys_def.faction_ids:
					var legacy := _legacy_faction_key_for_system_id(
						str(fid),
						sys_def.legacy_id,
						registry
					)
					if not legacy.is_empty():
						factions.append(legacy)
				if not factions.is_empty():
					return factions
	if is_current_system_home():
		return ["zenith", "aurelia", "vanguard"]
	return get_current_system_minor_factions()

static func _legacy_faction_key_for_system_id(
	faction_id: String,
	system_legacy_id: String,
	registry: Variant
) -> String:
	var config = registry.get_generated_config(system_legacy_id) if registry != null else null
	if config != null:
		for legacy_key in config.faction_id_lookup.keys():
			if str(config.faction_id_lookup[legacy_key]) == faction_id:
				return str(legacy_key)
	if faction_id.begins_with("faction.generated."):
		var generated := _generated_faction_record(faction_id)
		if not generated.is_empty():
			return str(generated.get("legacy_id", faction_id))
		return faction_id
	if faction_id.begins_with("faction."):
		return faction_id.trim_prefix("faction.")
	return faction_id

static func _generated_faction_record(faction_name: String) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return {}
	var game_root := tree.current_scene
	var factions: Array = []
	if game_root.has_method("revealed_generated_factions"):
		factions.append_array(game_root.revealed_generated_factions())
	if game_root.has_method("generated_factions_for_ids") \
			and faction_name.begins_with("faction.generated."):
		factions.append_array(game_root.generated_factions_for_ids([faction_name]))
	for faction in factions:
		if not faction is Dictionary:
			continue
		if str(faction.get("legacy_id", "")) == faction_name \
				or str(faction.get("id", "")) == faction_name:
			return (faction as Dictionary).duplicate(true)
	return {}

static func _generated_faction_color(
	faction_record: Dictionary,
	fallback_key: String
) -> Color:
	var raw_color: Array = faction_record.get("ui_color", [])
	if raw_color.size() == 4:
		return Color(
			float(raw_color[0]),
			float(raw_color[1]),
			float(raw_color[2]),
			float(raw_color[3])
		)
	var hue := float(abs(fallback_key.hash()) % 360) / 360.0
	return Color.from_hsv(hue, 0.62, 0.9)

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
	var line: String = _pick_remembered_npc_flavor_line(npc_name, lines)
	return {
		"npc_name": npc_name,
		"line": line,
		"color": npc.get("flavor_color", Color.WHITE),
		"voice_profile_id": npc.get("voice_profile_id", "voice.neutral.v1"),
	}

static func _pick_remembered_npc_flavor_line(npc_name: String, lines: Array) -> String:
	var clean_lines: Array[String] = []
	for raw_line in lines:
		var clean_line := str(raw_line).strip_edges()
		if not clean_line.is_empty():
			clean_lines.append(clean_line)
	if clean_lines.is_empty():
		return ""
	var memory: Array = npc_line_memory.get(npc_name, []).duplicate()
	if generated_outpost_npc_data.has(npc_name):
		var npc_data: Dictionary = generated_outpost_npc_data[npc_name]
		memory = npc_data.get("line_memory_fingerprints", memory).duplicate()
	var candidates: Array[String] = []
	for line in clean_lines:
		if _npc_line_fingerprint(line) not in memory:
			candidates.append(line)
	if candidates.is_empty():
		memory.clear()
		candidates = clean_lines.duplicate()
	var picked_line := candidates[randi() % candidates.size()]
	var picked_fingerprint := _npc_line_fingerprint(picked_line)
	if picked_fingerprint not in memory:
		memory.append(picked_fingerprint)
	while memory.size() > maxi(1, clean_lines.size()):
		memory.pop_front()
	npc_line_memory[npc_name] = memory.duplicate()
	if generated_outpost_npc_data.has(npc_name):
		generated_outpost_npc_data[npc_name]["line_memory_fingerprints"] = memory.duplicate()
		_remember_generated_npc_line(npc_name, picked_line)
	return picked_line

static func _remember_generated_npc_line(npc_name: String, line: String) -> void:
	if campaign_npc_identity_store == null:
		return
	if not campaign_npc_identity_store.has_method("remember_line"):
		return
	if not generated_outpost_npc_data.has(npc_name):
		return
	var npc_data: Dictionary = generated_outpost_npc_data[npc_name]
	var npc_id := str(npc_data.get("npc_id", ""))
	if npc_id.is_empty():
		return
	var remembered: Dictionary = campaign_npc_identity_store.remember_line(
		npc_id,
		line,
		"outpost_gossip"
	)
	if bool(remembered.get("ok", false)):
		var record: Dictionary = remembered.get("npc", {})
		generated_outpost_npc_data[npc_name]["identity_record"] = record
		generated_outpost_npc_data[npc_name]["line_memory_fingerprints"] = (
			record.get(
				"line_memory_fingerprints",
				generated_outpost_npc_data[npc_name].get(
					"line_memory_fingerprints",
					[]
				)
			)
		)

static func _npc_line_fingerprint(line: String) -> String:
	return line.strip_edges().to_lower().sha256_text().substr(0, 16)

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
	if not MINOR_NPCS.has(npc_name) and not generated_outpost_npc_data.has(npc_name):
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


func add_credits(amount: int) -> void:
	player_credits += amount


func spend_credits(amount: int) -> void:
	player_credits -= amount


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
func accept_special(
	item_name: String,
	description: String,
	source: String,
	destination: String = "",
	metadata: Dictionary = {}
) -> bool:
	if not can_accept_special():
		return false
	cargo_special = {
		"name": item_name,
		"description": description,
		"source": source,
		"destination": destination,
	}
	for key in metadata.keys():
		cargo_special[key] = metadata[key]
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
	var outposts := get_current_pickup_outposts()
	var valid_outposts: Array = []
	for outpost in outposts:
		if outpost is Dictionary \
				and not get_minor_npcs_at_outpost(str(outpost.get("id", ""))).is_empty():
			valid_outposts.append(outpost)
	if valid_outposts.is_empty():
		return { "offer": false }
	var selected: Dictionary = valid_outposts[randi() % valid_outposts.size()]
	var outpost_id: String = str(selected.get("id", ""))
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
		"outpost_display": str(selected.get("display", outpost_id)),
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
var ore_bank_max: float = 1000.0
var power_capacity: float = 300.0

var current_upgrades: Dictionary = {
	"weapons": {"tier": 1, "path": "base"},
	"engine": {"tier": 1, "path": "base"},
	"shields": {"tier": 1, "path": "base"},
	"mining": {"tier": 1, "path": "base"},
	"cargo": {"tier": 1, "path": "base"},
	"storage": {"tier": 1, "path": "base"},
	"sensors": {"tier": 1, "path": "base"},
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
var sensor_tier: int = 0

# Max Tier Drawback Flags
var has_max_rapid_weapon: bool = false
var has_max_heavy_weapon: bool = false
var has_max_speed_engine: bool = false
var has_max_hauler_engine: bool = false
var has_max_bulwark_shield: bool = false
var has_max_deflector_shield: bool = false
var has_max_rapid_mining: bool = false
var has_max_deep_mining: bool = false
var inventory_slots: int = 8

var kaelen_briefing_seen: bool = false
var kaelen_briefing_accepted: bool = false
var kaelen_arrival_systems_seen: Array[String] = []

# ── StoryManager tool slots ───────────────────────────────────────────────────
# Written by StoryManager; read by existing systems. Session-only (not persisted).
var story_world_pressure: Dictionary = {}  # {faction, intensity, system_id, event_type}
var story_quest_hint: Dictionary = {}      # {preferred_system, preferred_type, flavor_tag, expires_after_docks}
var story_loot_plant: Dictionary = {}      # {item_id, consumed_on_pickup: bool}
var story_station_climate: Dictionary = {} # {station_id, text}
var story_forced_anomaly: Dictionary = {}  # {system_id, flavor_type}
var story_planted_npc: Dictionary = {}     # {station_id, npc_id, display_name, portrait_id, line, one_shot}
var story_map_highlight: Dictionary = {}   # {system_id: true, ...} — systems to show Kaelen-intel ring on map

# Unique per-campaign seed mixed into procedural system generation so each
# campaign produces different systems even from the same gate destination IDs.
var campaign_seed: int = 0

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

var bloom_enabled: bool = true:
	set(val):
		bloom_enabled = val
		if not val and bloom_amount > 0.0:
			bloom_amount = 0.0
		elif val and bloom_amount <= 0.0:
			bloom_amount = 1.0
		bloom_changed.emit(val)
		bloom_amount_changed.emit(bloom_amount)
		_save_visual_prefs()

var bloom_amount: float = 1.0:
	set(val):
		bloom_amount = clampf(val, 0.0, 2.0)
		var next_enabled := bloom_amount > 0.01
		if bloom_enabled != next_enabled:
			bloom_enabled = next_enabled
		else:
			bloom_changed.emit(bloom_enabled)
			bloom_amount_changed.emit(bloom_amount)
			_save_visual_prefs()

signal bloom_changed(enabled: bool)
signal bloom_amount_changed(amount: float)

# Reputation system
var reputations: Dictionary = {
	"zenith": 50.0,
	"aurelia": -20.0,
	"vanguard": -20.0,
	"reavers": 0.0,
	"obsidian": 0.0,
	"dustborn": 0.0,
	"wraiths": 0.0,
	"ironclad": 0.0,
}
signal reputation_changed(faction_name: String, new_rep: float)
signal ship_destroyed(faction_name: String)
signal player_kill(faction_name: String)   # fires only when player lands the killing blow
signal entities_changed()
signal system_chatter_received(sender: String, message: String, color: Color)

var faction_kills: Dictionary = {
	"zenith": 0,
	"aurelia": 0,
	"vanguard": 0
}
var illegal_mining_enforcement = IllegalMiningEnforcementType.new()

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
	
	var patrol_route := _pick_mission_target_route(system_root)

	# Use the station as the fallback spawn anchor so targets appear in open
	# space, not on top of the dock where the player accepted the quest.
	var spawn_anchor: Vector3 = player_node.global_position
	var station_node = get_primary_station()
	if station_node and is_instance_valid(station_node):
		spawn_anchor = station_node.global_position
	
	GlobalState.trace("[GlobalState] Spawning %d mission targets for faction: %s at distance from station" % [count, faction_name])
	
	# Spread ships evenly in a ring 550-900m from the station — far enough
	# that the player has to fly out to engage, close enough to feel immediate
	var mission_key := _active_mission_identity_key()
	var start_index := int(
		QuestManager.active_quest.get("target_spawn_sequence", 0)
	)
	QuestManager.active_quest["target_spawn_sequence"] = start_index + count
	for i in range(count):
		var target_pos := spawn_anchor
		if not patrol_route.is_empty():
			target_pos = patrol_route[i % patrol_route.size()]
		var angle = (TAU / max(count, 1)) * i + randf_range(-0.4, 0.4)
		var dist = randf_range(60.0, 140.0) if not patrol_route.is_empty() else randf_range(550.0, 900.0)
		var offset = Vector3(cos(angle), randf_range(-0.05, 0.05), sin(angle)) * dist
		var spawn_pos = target_pos + offset
		
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
		npc.patrol_center = target_pos if not patrol_route.is_empty() else spawn_pos
		if patrol_route.size() >= 2:
			npc.patrol_route = patrol_route
			npc.patrol_route_index = i % patrol_route.size()
	
	# HUD warning + chatter so the arrival feels like an event
	var ui = get_ui_manager()
	if ui and ui.has_method("show_hud_warning"):
		ui.show_hud_warning("CONTRACT ACTIVE: " + str(count) + " " + faction_name.to_upper() + " targets have entered the sector.")
	emit_chatter("SYSTEM", "Sensor sweep: " + str(count) + " " + faction_name.to_upper() + " signatures detected in open space.", Color(0.0, 0.9, 0.9))


func _pick_mission_target_route(system_root: Node3D) -> Array[Vector3]:
	var belt_route := _pick_mission_asteroid_belt_route(system_root)
	if not belt_route.is_empty():
		return belt_route
	return _pick_mission_shipping_lane_route(system_root)


func _pick_mission_asteroid_belt_route(system_root: Node3D) -> Array[Vector3]:
	var belts: Dictionary = {}
	if system_root == null:
		return []
	for node in _mission_route_nodes_in_group(system_root, "asteroid"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var belt_id := str(node.get_meta("belt_id", "")).strip_edges()
		if belt_id == "":
			belt_id = _mission_belt_id_from_name(str(node.name))
		if belt_id == "":
			belt_id = "unmarked"
		if not belts.has(belt_id):
			belts[belt_id] = []
		belts[belt_id].append(_mission_route_position(node as Node3D))
	if belts.is_empty():
		return []
	var best_points: Array = []
	for belt_id in belts.keys():
		var points: Array = belts[belt_id]
		if points.size() > best_points.size():
			best_points = points
	if best_points.is_empty():
		return []
	var center := Vector3.ZERO
	for point: Vector3 in best_points:
		center += point
	center /= float(best_points.size())
	var route: Array[Vector3] = []
	for point: Vector3 in best_points:
		if point.distance_to(center) >= 40.0:
			route.append(point)
	if route.size() >= 2:
		route.sort_custom(func(a: Vector3, b: Vector3) -> bool:
			return atan2(a.z - center.z, a.x - center.x) < atan2(b.z - center.z, b.x - center.x)
		)
		if route.size() > 6:
			var sampled: Array[Vector3] = []
			for i in range(6):
				sampled.append(route[int(round(float(i) * float(route.size() - 1) / 5.0))])
			return sampled
		return route
	return [center]


func _mission_belt_id_from_name(node_name: String) -> String:
	var idx := node_name.find("Asteroid")
	if idx <= 0:
		return ""
	var clean := node_name.substr(0, idx).strip_edges()
	while clean.ends_with("_") or clean.ends_with(" "):
		clean = clean.substr(0, clean.length() - 1)
	return clean


func _pick_mission_shipping_lane_route(system_root: Node3D) -> Array[Vector3]:
	if system_root == null:
		return []
	var stations: Array[Node3D] = []
	for node in _mission_route_nodes_in_group(system_root, "station"):
		if node is Node3D and is_instance_valid(node):
			stations.append(node)
	if stations.size() < 2:
		return []
	var best_a: Node3D = stations[0]
	var best_b: Node3D = stations[1]
	var best_dist := -1.0
	for i in range(stations.size()):
		for j in range(i + 1, stations.size()):
			var dist := _mission_route_position(stations[i]).distance_squared_to(_mission_route_position(stations[j]))
			if dist > best_dist:
				best_dist = dist
				best_a = stations[i]
				best_b = stations[j]
	return [_mission_route_position(best_a), _mission_route_position(best_b)]


func _mission_route_nodes_in_group(root: Node, group_name: String) -> Array:
	var result: Array = []
	if root == null:
		return result
	if root.is_in_group(group_name):
		result.append(root)
	for child in root.get_children():
		result.append_array(_mission_route_nodes_in_group(child, group_name))
	return result


func _mission_route_position(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position


func report_player_mined_asteroid(asteroid: Node3D) -> Dictionary:
	if asteroid == null or not is_instance_valid(asteroid):
		return {}
	var owner_faction := _asteroid_owner_faction(asteroid)
	var belt_id := _asteroid_belt_id(asteroid)
	if not _has_illegal_mining_witness(owner_faction):
		return {
			"accepted": false,
			"dispatch": false,
			"reason": "unwitnessed",
			"faction": owner_faction,
			"belt_id": belt_id,
		}
	var result: Dictionary = illegal_mining_enforcement.report_violation(
		current_system_id,
		belt_id,
		owner_faction,
		Time.get_ticks_msec()
	)
	var faction_label := faction_display_name(owner_faction)
	var belt_label := _belt_display_name(belt_id)
	emit_chatter(
		"MINER",
		"Illegal miner in %s. %s code enforcement requested." % [
			belt_label,
			faction_label,
		],
		Color(1.0, 0.72, 0.25)
	)
	if bool(result.get("dispatch", false)):
		_dispatch_illegal_mining_enforcement(
			result,
			_node3d_position(asteroid)
		)
	return result


func _dispatch_illegal_mining_enforcement(
	report: Dictionary,
	violation_pos: Vector3
) -> void:
	var player_node: Node3D = player
	var system_root: Node3D = get_system_root()
	if player_node == null or not is_instance_valid(player_node) \
			or player_node.get("destroyed") or system_root == null:
		return
	var npc_scene := load("res://scenes/npc_ship.tscn") as PackedScene
	if npc_scene == null:
		push_warning("[GlobalState] Could not load npc_ship.tscn for enforcement response.")
		return
	var faction_name := str(report.get("faction", "neutral"))
	var count: int = max(1, int(report.get("ship_count", 2)))
	for i in range(count):
		var angle := (TAU / float(count)) * float(i) + randf_range(-0.35, 0.35)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * randf_range(160.0, 220.0)
		var npc := npc_scene.instantiate() as Node3D
		npc.faction = faction_name
		npc.is_reinforcement = false
		npc.ship_role = "Interceptor"
		npc.speed = 16.0
		npc.name = "%s_CodeEnforcement_%03d" % [
			faction_display_name(faction_name).replace(" ", ""),
			randi() % 1000,
		]
		runtime_entity_sequence += 1
		npc.persistent_id = "entity.%s.enforcement.%06d" % [
			current_system_id,
			runtime_entity_sequence,
		]
		IllegalMiningEnforcementType.mark_enforcement_ship(
			npc,
			faction_name,
			current_system_id
		)
		system_root.add_child(npc)
		if npc.is_inside_tree():
			npc.global_position = violation_pos + offset
		else:
			npc.position = violation_pos + offset
	var ui: Control = get_ui_manager()
	if ui and ui.has_method("show_hud_warning"):
		ui.show_hud_warning("CODE ENFORCEMENT: Illegal mining response inbound.")
	emit_chatter(
		"SYSTEM",
		"%s enforcement ships are moving to investigate the mining violation." %
			faction_display_name(faction_name),
		Color(0.0, 0.9, 0.9)
	)


func _asteroid_owner_faction(asteroid: Node) -> String:
	for key in ["belt_owner_faction", "owner_faction", "faction"]:
		var value := str(asteroid.get_meta(key, "")).strip_edges()
		if not value.is_empty():
			return value
	var factions := get_current_system_factions()
	if factions.is_empty():
		return "zenith"
	var source := _asteroid_belt_id(asteroid)
	var index: int = abs(hash(source)) % factions.size()
	return factions[index]


func _asteroid_belt_id(asteroid: Node) -> String:
	var explicit := str(asteroid.get_meta("belt_id", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var persistent := str(asteroid.get("persistent_id")).strip_edges()
	if not persistent.is_empty():
		var parts := persistent.split(".")
		if parts.size() >= 4:
			return str(parts[3])
		return persistent
	return str(asteroid.name)


func _belt_display_name(belt_id: String) -> String:
	var clean := belt_id.strip_edges()
	if clean.is_empty():
		return "the belt"
	clean = clean.replace("_", " ").replace("-", " ")
	return clean.capitalize()


func _has_illegal_mining_witness(owner_faction: String) -> bool:
	var player_node := player
	if player_node == null or not is_instance_valid(player_node):
		return false
	for entity in active_system_entities:
		if entity == null or not is_instance_valid(entity):
			continue
		if entity.get("destroyed"):
			continue
		var ship_role := str(entity.get("ship_role"))
		if ship_role == "<null>":
			ship_role = ""
		var is_miner := ship_role == "MiningHauler" \
			or bool(entity.get_meta("is_mining_witness", false))
		if not is_miner:
			continue
		var witness_faction := str(entity.get("faction"))
		if witness_faction == "<null>":
			witness_faction = ""
		if not witness_faction.is_empty() and witness_faction != owner_faction:
			continue
		if _node3d_position(player_node).distance_to(_node3d_position(entity)) \
				<= ILLEGAL_MINING_WITNESS_RADIUS:
			return true
	return false


func _node3d_position(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	if node.is_inside_tree():
		return node.global_position
	return node.position


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
	if not reputations.has(faction_name):
		reputations[faction_name] = 0.0
	reputations[faction_name] = clamp(reputations[faction_name] + amount, -100.0, 100.0)
	reputation_changed.emit(faction_name, reputations[faction_name])

const TRACE_LOG: bool = false

static func trace(msg: String) -> void:
	if TRACE_LOG:
		print(msg)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_inputs()
	_load_visual_prefs()
	CampaignClock.time_changed.connect(_on_campaign_time_for_stores)


const VISUAL_PREFS_PATH := "user://player_preferences.json"

func _load_visual_prefs() -> void:
	if not FileAccess.file_exists(VISUAL_PREFS_PATH):
		return
	var file := FileAccess.open(VISUAL_PREFS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		if parsed.has("bloom_amount"):
			bloom_amount = float(parsed.get("bloom_amount", 1.0))
		else:
			bloom_enabled = bool(parsed.get("bloom_enabled", true))

func _save_visual_prefs() -> void:
	var prefs := {}
	if FileAccess.file_exists(VISUAL_PREFS_PATH):
		var file := FileAccess.open(VISUAL_PREFS_PATH, FileAccess.READ)
		if file:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				prefs = parsed
	prefs["bloom_enabled"] = bloom_enabled
	prefs["bloom_amount"] = bloom_amount
	var file := FileAccess.open(VISUAL_PREFS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(prefs, "\t"))
	file.close()


const StoreRegistryScript = preload("res://scripts/economy/StoreRegistry.gd")

func _on_campaign_time_for_stores(total_minutes: int) -> void:
	StoreRegistryScript.shared().restock_all(total_minutes)

func get_system_root() -> Node3D:
	if active_system_root and is_instance_valid(active_system_root):
		return active_system_root
	return get_tree().current_scene

func get_ui_manager() -> Control:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var scene_root := tree.current_scene
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
	generated_outpost_npcs.clear()
	generated_outpost_npc_data.clear()
	npc_line_memory.clear()
	illegal_mining_enforcement = IllegalMiningEnforcementType.new()
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
		"storage": {"tier": 1, "path": "base"},
		"sensors": {"tier": 1, "path": "base"},
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
	sensor_tier = 0
	
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
	# Reset Kaelen briefing flags so new campaigns show the intro
	kaelen_briefing_seen = false
	kaelen_briefing_accepted = false
	kaelen_arrival_systems_seen.clear()
	story_world_pressure = {}
	story_quest_hint = {}
	story_loot_plant = {}
	story_station_climate = {}
	story_forced_anomaly = {}
	story_planted_npc = {}
	story_map_highlight = {}
	# New seed so procedural systems differ across campaigns
	campaign_seed = randi()
	# Reset reputations
	reputations = {
		"zenith": 50.0,
		"aurelia": -20.0,
		"vanguard": -20.0,
		"reavers": 0.0,
		"obsidian": 0.0,
		"dustborn": 0.0,
		"wraiths": 0.0,
		"ironclad": 0.0,
	}
	# Reset kill tracking
	faction_kills = { "zenith": 0, "aurelia": 0, "vanguard": 0 }
	GlobalState.trace("[GlobalState] State reset for new game.")


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
	inventory_slots = SHIP_BASE_STATS["inventory_slots"]
	ore_bank_max = SHIP_BASE_STATS["ore_bank_max"]
	power_capacity = 300.0
	sensor_tier = 0

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

	# Sync inventory slot capacity and ore bank
	inventory.max_slots = inventory_slots
	player_storage_max = ore_bank_max

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
	if not UPGRADE_TREE.has(sys):
		return false
	var branch_data: Dictionary = UPGRADE_TREE[sys]["branches"]
	var any_branch_has_tier := false
	for b in branch_data.values():
		if b.has(next_tier):
			any_branch_has_tier = true
			break
	if not any_branch_has_tier:
		return false
		
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
	GlobalState.trace("[GlobalState] Upgraded %s to tier %d path %s" % [sys, next_tier, path])
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
	_add_key_action("hard_stop", KEY_SPACE)
	
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


static func remove_repeated_player_address(text: String) -> String:
	var out := text.strip_edges()
	var leading := RegEx.new()
	leading.compile("(?i)^\\s*indy\\s*[,!?:;\\-]+\\s*")
	out = leading.sub(out, "", true).strip_edges()

	var paired := RegEx.new()
	paired.compile("(?i)\\s*,\\s*indy\\s*,\\s*")
	out = paired.sub(out, ", ", true)

	var terminal := RegEx.new()
	terminal.compile("(?i)\\s*,\\s*indy\\s*([.!?])")
	out = terminal.sub(out, "$1", true)

	out = out.strip_edges()
	if out.length() > 0 and out[0] >= "a" and out[0] <= "z":
		out = out[0].to_upper() + out.substr(1)
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
