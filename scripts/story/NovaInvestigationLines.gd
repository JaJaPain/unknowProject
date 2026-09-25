extends RefCounted

## What N.O.V.A. says while the captain works an investigation (Abe,
## 2026-09-24): after each scan she puts the decision to the captain, and she
## reacts when they commit, extract or file. Hand-written stock lines, no model.
##
## She only knows what the scans observed. Before the registry is checked she
## cannot tell a genuine beacon from a forged one, so neither can her lines.

const DECISION := {
	"survey_discrepancy": {
		"one": [
			"First reading's logged. We can file it now for half, or fly to the second site and compare. What do you want to do, Captain?",
			"One code in hand. Half pay if we stop here. Want to go check the other one?",
		],
		"both": [
			"Both codes are in. Do they match, Captain? Certify it and I'll sign my name next to yours.",
			"That's everything we can see. Match or mismatch? Your call. I'll file whichever you choose.",
		],
	},
	"competing_claims": {
		"one": [
			"The recorder's there, but not whose it is. File what we have, or go find the owner?",
			"We know where it is, not who owns it. Report now, or keep digging?",
		],
		"both": [
			"We know whose it is now. Preserve the records for the client, or strip the hardware? The second one pays better, and it's ugly.",
			"Ownership's confirmed. Keep the records intact, or salvage the machine? Salvage burns the evidence. Just so you know.",
		],
	},
	"transmitter_lure": {
		"one": [
			"The beacon says there's a cache out there. I can check it against the registry first, or we commit and go get it. Do you want to commit?",
			"A cache, just sitting there, calling to anyone. Commit now, or let me verify it first?",
		],
		"match": [
			"Registry agrees. The beacon's genuine. Do you want to commit to the cache?",
			"Codes match. It's real, as far as I can tell. Shall we commit?",
		],
		"mismatch": [
			"The codes don't match. Someone forged that beacon. We can still commit to the cache. I'd rather we filed the report.",
			"It's a fake, Captain. Whoever built it is waiting to see who bites. Commit anyway, or report it?",
		],
	},
	"unstable_archive": {
		"one": [
			"It's coming apart as we watch. A repair kit would hold it. Or we find the backup and rebuild. What do you want to do?",
			"That archive won't last. Patch it with a kit, go after the backup, or just report it?",
		],
		"both": [
			"Backup's aboard. I can rebuild a copy, or we patch the original with a kit. Your call.",
			"We have the fragments. Reconstruct, stabilize, or file it? I'm ready for any of them.",
		],
	},
}
const COMMITTED: Array[String] = [
	"Committed. Setting course for the cache. Hold still when we get there.",
	"Alright. We're going in. Stay slow near the cache and I'll do the rest.",
]
const COMMITTED_AMBUSH: Array[String] = [
	"Committed. And there are contacts at the cache. They were waiting for whoever took the bait.",
	"Hostiles on the cache, Captain. It was bait. We're committed now, so let's make it count.",
]
const EXTRACTED: Array[String] = [
	"Cache is aboard. Let's not stay.",
	"Got it. Now can we leave before something else notices?",
]
const FILED: Array[String] = [
	"Filed. Let's go get paid.",
	"Done. Dock at the station and they'll pay out.",
]


## The question after a scan. `codes_match` is only read once both sites are
## scanned (it comes from observed evidence, never the saved truth).
static func decision(recipe: String, verification_scanned: bool, codes_match: bool, pick: int) -> String:
	var pools: Dictionary = DECISION.get(recipe, DECISION["survey_discrepancy"])
	var key := "one"
	if verification_scanned:
		key = ("match" if codes_match else "mismatch") if recipe == "transmitter_lure" else "both"
	return _pick(pools[key], pick)


static func committed(ambush: bool, pick: int) -> String:
	return _pick(COMMITTED_AMBUSH if ambush else COMMITTED, pick)


static func extracted(pick: int) -> String:
	return _pick(EXTRACTED, pick)


static func filed(pick: int) -> String:
	return _pick(FILED, pick)


static func _pick(pool: Array, pick: int) -> String:
	return str(pool[posmod(pick, pool.size())])
