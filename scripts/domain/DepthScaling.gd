extends RefCounted

## Deeper is richer, and harder (docs/core_loop_plan_2026_10_01.md 3.5, core
## loop step 6). Every number that grows with a system's gate depth lives
## here, so the upgrade ladder pays for itself and the economy simulation
## (step 7) has one place to tune. Ore value already scales with depth in
## SystemProfile (rare-ore shares, thorium from depth 3).

## Red rocks (tech-grade seams), per thousand rocks: about 1% near the start,
## rising to 3% from depth 10, so the materials the later tiers need in
## quantity get easier to find as the player climbs.
const TECH_SEAM_PERMILLE_BASE := 10
const TECH_SEAM_PERMILLE_PER_DEPTH := 2.5
const TECH_SEAM_PERMILLE_FROM_DEPTH := 2
const TECH_SEAM_PERMILLE_MAX := 30
## Board pay: double the authored figures everywhere (economy sim, 2026-10-02:
## income was ~1 SC/s and the ladder ran 3-6x too slow; Abe left the call to
## Claude for the first pass), then +15% per depth.
const BOARD_PAY_BASE := 2.0
const PAY_PER_DEPTH := 0.15
## Enemy hull and damage: +8% per depth, on top of a system's own tier.
const THREAT_PER_DEPTH := 0.08


static func tech_seam_permille(depth: int) -> int:
	var extra := maxf(0.0, float(depth - TECH_SEAM_PERMILLE_FROM_DEPTH)) * TECH_SEAM_PERMILLE_PER_DEPTH
	return mini(TECH_SEAM_PERMILLE_MAX, TECH_SEAM_PERMILLE_BASE + int(round(extra)))


static func pay_factor(depth: int) -> float:
	return BOARD_PAY_BASE * (1.0 + PAY_PER_DEPTH * float(maxi(depth, 0)))


static func threat_factor(depth: int) -> float:
	return 1.0 + THREAT_PER_DEPTH * float(maxi(depth, 0))


## Depth of a system from the start (0 when unknown).
static func depth_of(system_id: String) -> int:
	if system_id.is_empty():
		return 0
	return maxi(0, int(preload("res://scripts/story/premise/PremiseWorldSnapshot.gd")._system_depth(system_id)))


## Depth of the system the ship is in.
static func current_depth() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("GlobalState") if tree != null else null
	return depth_of(str(gs.current_system_id)) if gs != null else 0
