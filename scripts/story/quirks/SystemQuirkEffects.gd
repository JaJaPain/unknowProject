class_name SystemQuirkEffects
extends RefCounted

## What a system's quirks DO in play (plan Phase 4: pulsar, nebula, ion storm,
## relay dark zone for the slice). Pure: SystemQuirkRunner applies the result.
##
## Everything is gentle on purpose: a quirk changes how a system plays, it
## never kills the pilot by itself. Pulsar sweeps only drain shields; ion
## storms only slow the shield recharge; the nebula shortens how far anyone
## sees anyone; the dark zone silences the system radio.
##
## Environment keys (read by the game through GlobalState.environment_value):
##   shield_regen_mult      steady multiplier on shield recharge
##   player_detection_mult  how far hostile ships notice the player (x 130 m)
##   radio                  false = no system radio broadcasts

const SLICE_QUIRKS: Array[String] = ["pulsar", "nebula", "ion_storm", "relay_dark_zone"]

const NEBULA_DETECTION_MULT := 0.7
const PULSAR := {"kind": "pulsar_sweep", "period_s": 90.0, "warning_s": 8.0, "duration_s": 2.0, "shield_damage_frac": 0.15}
const ION_STORM := {"kind": "ion_storm", "period_s": 150.0, "warning_s": 10.0, "duration_s": 40.0, "shield_regen_mult": 0.4, "signal_interference_mult": 3.0}

const ARRIVAL_NOTES := {
	"pulsar": "A pulsar sweeps this system on a regular beat. Each pass drains shields.",
	"nebula": "Dense nebula here. Sensors are short-ranged, for everyone.",
	"ion_storm": "Ion storms roll through this system. Shields recharge slowly while one is overhead.",
	"relay_dark_zone": "The relay network is dark here. No system radio.",
}
const WARNINGS := {
	"pulsar_sweep": "Pulsar sweep incoming. Shields will take the hit.",
	"ion_storm": "Ion storm front approaching.",
}
const STARTS := {"ion_storm": "Ion storm overhead. Shield recharge is down."}
const ENDS := {"ion_storm": "Ion storm has passed."}


## {environment: {...}, hazards: [...], notes: [...]} for a list of quirks.
static func effects_for(quirks: Array) -> Dictionary:
	# signal_interference: how hard signal tuning is (1.0 normal; see
	# SignalTuningModel). A nebula muddies it; an ion storm overhead wrecks it.
	var env := {"shield_regen_mult": 1.0, "player_detection_mult": 1.0, "radio": true, "signal_interference": 1.0}
	var hazards: Array = []
	var notes: Array = []
	for q in quirks:
		var quirk := str(q)
		if not quirk in SLICE_QUIRKS:
			continue
		notes.append(ARRIVAL_NOTES[quirk])
		match quirk:
			"nebula":
				env["player_detection_mult"] = NEBULA_DETECTION_MULT
				env["signal_interference"] = 1.5
			"relay_dark_zone":
				env["radio"] = false
			"pulsar":
				hazards.append(PULSAR.duplicate())
			"ion_storm":
				hazards.append(ION_STORM.duplicate())
	return {"environment": env, "hazards": hazards, "notes": notes}


## Where a hazard is in its cycle after `t` seconds in the system:
## {state: "calm" | "warning" | "active", cycle: int}. The first cycle starts
## calm for a full period, so nothing happens the moment the pilot arrives.
static func phase(hazard: Dictionary, t: float) -> Dictionary:
	var period := float(hazard["period_s"])
	var cycle := int(floor(t / period))
	var into := fmod(t, period)
	var active_from := period - float(hazard["duration_s"])
	var warn_from := active_from - float(hazard["warning_s"])
	if into >= active_from:
		return {"state": "active", "cycle": cycle}
	if into >= warn_from:
		return {"state": "warning", "cycle": cycle}
	return {"state": "calm", "cycle": cycle}


## Shield drained by one pulsar pass (never more than the shield holds, so
## the hull is never touched).
static func pulsar_drain(hazard: Dictionary, shield_capacity: float, current_shield: float) -> float:
	return minf(maxf(current_shield, 0.0), shield_capacity * float(hazard.get("shield_damage_frac", 0.0)))


## The environment right now: the steady values plus any active storm.
static func environment_at(effects: Dictionary, t: float) -> Dictionary:
	var env: Dictionary = (effects.get("environment", {}) as Dictionary).duplicate()
	for h in effects.get("hazards", []):
		if str(h["kind"]) == "ion_storm" and str(phase(h, t)["state"]) == "active":
			env["shield_regen_mult"] = float(env.get("shield_regen_mult", 1.0)) * float(h["shield_regen_mult"])
			env["signal_interference"] = float(env.get("signal_interference", 1.0)) * float(h.get("signal_interference_mult", 1.0))
	return env
