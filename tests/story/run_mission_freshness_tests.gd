extends SceneTree

## Phase 3 exit measurement (vision plan 10): across 10 headless campaigns on
## one machine, how often do story jobs repeat? Each offered job gets a
## signature: verb + reason (the card beat it serves) + complication + turn.
##   - within a campaign, the same full signature should never come back;
##   - from one campaign to the next, few of the same stories should return
##     (the machine history keeps the deck fresh);
##   - no single job shape (verb + complication + turn) should dominate.
## Prints a report; the limits below are the exit criteria.
##   Godot --headless --path . --script res://tests/story/run_mission_freshness_tests.gd --log-file <path> -- --baseline-offline

const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")
const HISTORY_PATH := "user://test_mission_freshness_history.json"

const CAMPAIGNS := 10
const SYSTEMS_PER_CAMPAIGN := 3
## Exit limits.
const MAX_REPEAT_IN_CAMPAIGN := 0.0
const MAX_STORY_OVERLAP := 0.2
const MAX_TOP_SHAPE_SHARE := 0.25

var _failures: Array[String] = []


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HISTORY_PATH))
	var repeats := 0
	var offered := 0
	var shapes := {}
	var twists := {}
	var complications := {}
	var overlaps: Array[float] = []
	var previous_cards := {}
	for c in CAMPAIGNS:
		var result := _campaign(c)
		offered += int(result["offered"])
		repeats += int(result["repeats"])
		for k in result["shapes"]:
			shapes[k] = int(shapes.get(k, 0)) + int(result["shapes"][k])
		for k in result["twists"]:
			twists[k] = int(twists.get(k, 0)) + int(result["twists"][k])
		for k in result["complications"]:
			complications[k] = int(complications.get(k, 0)) + int(result["complications"][k])
		var cards: Dictionary = result["cards"]
		if c > 0 and not cards.is_empty():
			var shared := 0
			for id in cards:
				if previous_cards.has(id):
					shared += 1
			overlaps.append(float(shared) / float(cards.size()))
		previous_cards = cards
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HISTORY_PATH))

	var repeat_rate := float(repeats) / maxf(1.0, float(offered))
	var worst_overlap := 0.0
	var mean_overlap := 0.0
	for o in overlaps:
		worst_overlap = maxf(worst_overlap, o)
		mean_overlap += o
	mean_overlap /= maxf(1.0, float(overlaps.size()))
	var top_shape := ""
	var top_count := 0
	for k in shapes:
		if int(shapes[k]) > top_count:
			top_count = int(shapes[k])
			top_shape = k
	var top_share := float(top_count) / maxf(1.0, float(offered))
	print("[Freshness] %d campaigns x %d systems: %d jobs offered, %d distinct shapes" % [CAMPAIGNS, SYSTEMS_PER_CAMPAIGN, offered, shapes.size()])
	print("[Freshness] repeated full signatures within a campaign: %d (%.1f%%)" % [repeats, repeat_rate * 100.0])
	print("[Freshness] story overlap with the previous campaign: mean %.0f%%, worst %.0f%%" % [mean_overlap * 100.0, worst_overlap * 100.0])
	print("[Freshness] most common shape: %s, %.0f%% of jobs" % [top_shape, top_share * 100.0])
	print("[Freshness] top shapes: %s" % _top(shapes, 6))
	print("[Freshness] twists: %s" % _top(twists, 12))
	print("[Freshness] complications: %s" % _top(complications, 14))

	_check(offered >= CAMPAIGNS * SYSTEMS_PER_CAMPAIGN * 3, "enough jobs to measure (%d)" % offered)
	_check(repeat_rate <= MAX_REPEAT_IN_CAMPAIGN, "a campaign repeats a job signature (%.1f%%)" % (repeat_rate * 100.0))
	_check(worst_overlap <= MAX_STORY_OVERLAP, "stories carry over between campaigns (worst %.0f%%)" % (worst_overlap * 100.0))
	_check(top_share <= MAX_TOP_SHAPE_SHARE, "one job shape dominates: %s at %.0f%%" % [top_shape, top_share * 100.0])
	if _failures.is_empty():
		print("[PASS] Mission freshness")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


## One campaign: arrive, take postings, answer decisions, move on.
func _campaign(index: int) -> Dictionary:
	var d = DirectorType.new()
	d.history_path = HISTORY_PATH
	d.use_showrunner = false
	d.reset_for_new_campaign(5000 + index * 37)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + index
	var now := 0
	var seen := {}
	var out := {"offered": 0, "repeats": 0, "shapes": {}, "twists": {}, "complications": {}, "cards": {}}
	for s in SYSTEMS_PER_CAMPAIGN:
		var w := _world(index * 10 + s + 1)
		d.ensure_arcs(w, now)
		var shown := {}
		for _round in 25:
			now += 90
			for decision in d.pending_decisions():
				var options: Array = decision["options"]
				d.apply_decision(str(decision["arc_id"]), str(options[rng.randi_range(0, options.size() - 1)]["id"]), now)
			var postings: Array = d.board_postings(w, now)
			if postings.is_empty():
				break
			for posting in postings:
				var q: Dictionary = posting["quest_data"]
				var beat := str(q.get("story_beat_id", ""))
				if shown.has(beat):
					continue
				shown[beat] = true
				var verb := str((q.get("objective", {}) as Dictionary).get("type", ""))
				# This world has no scan sites, so investigations come as a
				# stand-in pickup of the readings; count them as investigations.
				if str((q.get("objective", {}) as Dictionary).get("part_name", "")) == "Survey readings":
					verb = "INVESTIGATE"
				var comp := str(q.get("complication_id", "-"))
				var twist := str(q.get("twist_id", "-"))
				if comp.is_empty():
					comp = "-"
				if twist.is_empty():
					twist = "-"
				var reason := beat.get_slice(":", 0) + ":" + beat.get_slice(":", 1) if beat.contains(":") else beat
				var signature := "%s|%s|%s|%s" % [verb, reason, comp, twist]
				if seen.has(signature):
					out["repeats"] += 1
				seen[signature] = true
				out["offered"] += 1
				var shape := "%s|%s|%s" % [verb, comp, twist]
				out["shapes"][shape] = int(out["shapes"].get(shape, 0)) + 1
				out["twists"][twist] = int(out["twists"].get(twist, 0)) + 1
				out["complications"][comp] = int(out["complications"].get(comp, 0)) + 1
				out["cards"][str(q.get("premise_card_id", ""))] = true
			var take: Dictionary = postings[rng.randi_range(0, postings.size() - 1)]["quest_data"]
			var terminal := "completed" if rng.randi_range(0, 4) > 0 else "abandoned"
			d.on_mission_terminal(take.duplicate(true), terminal, now)
	d.free()
	return out


func _world(system_n: int) -> Dictionary:
	return {
		"system_id": "system.gen_%d" % system_n, "system_display": "System %d" % system_n,
		"system_seed": 3000 + system_n * 13, "star_type": ["red", "blue", "yellow", "white"][system_n % 4],
		"post_tutorial": true, "is_first_system": false, "investigation_fallback": true,
		"main_station": {"id": "system.gen_%d" % system_n, "display": "Main %d" % system_n},
		"outposts": [{"id": "outpost.%d_a" % system_n, "display": "Reach %d" % system_n},
			{"id": "outpost.%d_b" % system_n, "display": "Kova %d" % system_n}],
		"factions": [{"id": "faction.generated.a%d" % system_n, "display_name": "Guild %d" % system_n},
			{"id": "faction.generated.b%d" % system_n, "display_name": "Consortium %d" % system_n},
			{"id": "faction.generated.c%d" % system_n, "display_name": "Collective %d" % system_n}],
		"hostile_factions": ["reavers", "dustborn"], "known_npcs": [],
		"store_items": [{"item_id": "medical_kit", "display_name": "Medical kit", "quantity": 1,
			"station_id": "system.gen_%d" % system_n, "store_display": "Main", "base_price": 40}],
	}


func _top(counts: Dictionary, n: int) -> String:
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	var parts: Array[String] = []
	for i in mini(n, keys.size()):
		parts.append("%s=%d" % [keys[i], counts[keys[i]]])
	return ", ".join(parts)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
