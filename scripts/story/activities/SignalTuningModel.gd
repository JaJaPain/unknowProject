extends RefCounted

## Signal tuning (activity 1 of the vision plan): the captain turns two knobs,
## frequency and phase, to pull a faint transmission out of static. Frequency
## finds the signal; phase makes it clear. Hold it clear long enough and the
## transmission locks, and what was said is recorded.
##
## PURE and seeded: every function takes a state dictionary and returns a new
## one. The panel draws it; tests drive it with fixed steps.

## How far off (0..1 dial) the frequency may be before the signal is gone, and
## how much phase error blurs it. Phase wraps around.
const FREQ_WINDOW := 0.07
const PHASE_WINDOW := 0.14
## Quality needed to make lock progress, and how long a clean hold takes.
const LOCK_QUALITY := 0.72
const LOCK_SECONDS := 4.0
## Progress leaks away slowly when the signal slips, so a wobble is not a reset.
const LOCK_DECAY_PER_SECOND := 0.12
## The source drifts: a slow wander, faster in an ion storm.
const BASE_DRIFT := 0.012
## Average quality while locking decides clean or partial.
const CLEAN_AVERAGE := 0.86
## Letting N.O.V.A. do it: always partial, never clean.
const ASSIST_CLARITY := 0.55


## A new session. `interference` (1.0 = normal) scales drift and static; an
## ion storm raises it.
static func start(seed_value: int, interference: float = 1.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {
		"seed": seed_value,
		"target_freq": rng.randf_range(0.12, 0.88),
		"target_phase": rng.randf(),
		"drift_phase": rng.randf() * TAU,
		"interference": maxf(0.2, interference),
		"elapsed": 0.0,
		"quality": 0.0,
		"lock": 0.0,
		"quality_sum": 0.0,
		"quality_samples": 0,
		"locked": false,
	}


## Signal quality (0..1) for dial positions against the source.
static func quality(state: Dictionary, freq: float, phase: float) -> float:
	var df := absf(freq - float(state["target_freq"])) / FREQ_WINDOW
	var dp := absf(phase - float(state["target_phase"]))
	dp = minf(dp, 1.0 - dp) / PHASE_WINDOW
	var found := exp(-df * df)
	var clear := 0.35 + 0.65 * exp(-dp * dp)
	# Interference caps how clean it can ever get.
	var ceiling := clampf(1.08 - 0.08 * float(state["interference"]), 0.75, 1.0)
	return clampf(found * clear * ceiling, 0.0, 1.0)


## Advance by `dt` with the dials where the captain has them.
static func step(state: Dictionary, dt: float, freq: float, phase: float) -> Dictionary:
	var s := state.duplicate()
	if bool(s["locked"]):
		return s
	s["elapsed"] = float(s["elapsed"]) + dt
	var t := float(s["elapsed"])
	var wander := BASE_DRIFT * float(s["interference"])
	s["target_freq"] = clampf(float(s["target_freq"]) + sin(t * 0.7 + float(s["drift_phase"])) * wander * dt, 0.05, 0.95)
	s["target_phase"] = fposmod(float(s["target_phase"]) + cos(t * 0.5 + float(s["drift_phase"])) * wander * 1.5 * dt, 1.0)
	var q := quality(s, freq, phase)
	s["quality"] = q
	if q >= LOCK_QUALITY:
		s["lock"] = minf(1.0, float(s["lock"]) + dt / LOCK_SECONDS)
		s["quality_sum"] = float(s["quality_sum"]) + q
		s["quality_samples"] = int(s["quality_samples"]) + 1
	else:
		s["lock"] = maxf(0.0, float(s["lock"]) - LOCK_DECAY_PER_SECOND * dt)
	if float(s["lock"]) >= 1.0:
		s["locked"] = true
	return s


## "clean", "partial" or "failed". Giving up keeps what was heard: past half
## a lock counts as partial.
static func outcome(state: Dictionary) -> String:
	if bool(state["locked"]):
		var samples := maxi(1, int(state["quality_samples"]))
		return "clean" if float(state["quality_sum"]) / samples >= CLEAN_AVERAGE else "partial"
	return "partial" if float(state["lock"]) >= 0.5 else "failed"


## How much of the words come through (0..1) for an outcome.
static func clarity_for(outcome_id: String, state: Dictionary) -> float:
	match outcome_id:
		"clean":
			return 1.0
		"partial":
			return clampf(float(state["lock"]) * 0.8, 0.45, 0.8)
		"assisted":
			return ASSIST_CLARITY
	return 0.0


## The words as heard: at `clarity` below 1, some words are lost to static.
## Deterministic for a seed, so the same attempt reads the same way.
static func garble(text: String, clarity: float, seed_value: int) -> String:
	if clarity >= 1.0:
		return text
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var words := text.split(" ", false)
	var out: PackedStringArray = []
	for w in words:
		out.append(w if rng.randf() < clarity else "…")
	# Runs of lost words read as one gap.
	var joined := " ".join(out)
	while joined.contains("… …"):
		joined = joined.replace("… …", "…")
	return joined
