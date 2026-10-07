extends SceneTree

## Season simulation (docs/campaign_spine_plan_2026_10_05.md, step 1).
## Plays several campaigns in a row, as one player would (one shared card
## history), against the real PremiseDirector with a realistic mix of play:
## story jobs only some of the time, board jobs and mining in between, a jump
## every 30-60 real minutes. Measures, per campaign, in REAL play hours:
## first thread seen, the main story's lock, the confrontation's close; and
## at 10 hours how different the campaigns are from each other.
##
##   Godot --headless --path . --script res://tools/story_sim/run_season_sim.gd --log-file <abs path> -- [--campaigns=6] [--hours=30] [--story-share=0.45]
##
## Time model: the campaign clock moves on events only (GameRoot: a jump is
## 45 in-game minutes, docking 10, undocking 5). A story or board job is a
## dock + undock (15) and ~8-12 real minutes; mining ~15 real minutes and a
## dock (15); a jump ~3 real minutes (45).

const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")
const HandType := preload("res://scripts/story/premise/HiddenHand.gd")
const LodestarType := preload("res://scripts/domain/Lodestar.gd")
const HISTORY_PATH := "user://season_sim_history.json"
const DESTINATION_HISTORY_PATH := "user://season_sim_destination_history.json"

var campaigns := 6
var hours := 30.0
var story_share := 0.45


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--campaigns="):
			campaigns = int(arg.substr(12))
		elif arg.begins_with("--hours="):
			hours = float(arg.substr(8))
		elif arg.begins_with("--story-share="):
			story_share = float(arg.substr(14))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HISTORY_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DESTINATION_HISTORY_PATH))
	LodestarType.history_path = DESTINATION_HISTORY_PATH
	print("[SeasonSim] %d campaigns, up to %.0f h each, story jobs %.0f%% of activities" % [campaigns, hours, story_share * 100.0])
	var results: Array = []
	for c in campaigns:
		results.append(_campaign(c))
	_report(results)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HISTORY_PATH))
	quit(0)


func _world(seed_value: int, system_n: int, rng: RandomNumberGenerator) -> Dictionary:
	var sid := "system.c%d_%d" % [seed_value, system_n]
	return {
		"system_id": sid, "system_display": "System %d-%d" % [seed_value, system_n],
		"system_seed": seed_value * 1000 + system_n, "star_type": ["red", "blue", "yellow", "white"][rng.randi() % 4],
		"post_tutorial": true, "is_first_system": false, "investigation_fallback": true,
		"main_station": {"id": sid, "display": "Main %d" % system_n},
		"outposts": [{"id": "outpost.%d_%d_a" % [seed_value, system_n], "display": "Reach %d" % system_n},
			{"id": "outpost.%d_%d_b" % [seed_value, system_n], "display": "Kova %d" % system_n}],
		"factions": [{"id": "faction.generated.a%d_%d" % [seed_value, system_n], "display_name": "Guild %d" % system_n},
			{"id": "faction.generated.b%d_%d" % [seed_value, system_n], "display_name": "Consortium %d" % system_n},
			{"id": "faction.generated.c%d_%d" % [seed_value, system_n], "display_name": "Collective %d" % system_n}],
		"hostile_factions": ["reavers", "dustborn"], "known_npcs": [],
		"store_items": [{"item_id": "medical_kit", "display_name": "Medical kit", "quantity": 1,
			"station_id": sid, "store_display": "Main", "base_price": 40}],
	}


func _campaign(index: int) -> Dictionary:
	var seed_value := 5000 + index * 37
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var d = DirectorType.new()
	d.history_path = HISTORY_PATH
	d.use_showrunner = false
	d.reset_for_new_campaign(seed_value)
	# One player's campaigns in a row: the first Destination avoids recent ones.
	var first_destination := str(LodestarType.draw_for_new_campaign(seed_value).get("id", ""))
	d.lodestar_id = first_destination
	var out := {"index": index, "seed": seed_value, "lodestar": first_destination,
		"first_thread_h": -1.0, "lock_h": -1.0, "close_h": -1.0, "systems": 0, "story_jobs": 0, "other": 0,
		"cards_10h": [], "at_10h": {}, "locked_systems": -1}
	var real_min := 0.0
	var game_min := 0
	var system_n := 0
	var closed := []
	d.season_closed.connect(func(season, res): closed.append(res))
	var limit := hours * 60.0
	# Reaching the Lodestar: the economy sim puts Class VI at ~17 h for an
	# efficient captain; a player, somewhere in 17-22 h.
	var lodestar_at := rng.randf_range(17.0, 22.0) * 60.0
	var at_lodestar_since := -1.0
	while real_min < limit and closed.is_empty():
		system_n += 1
		out["systems"] = system_n
		var w := _world(seed_value, system_n, rng)
		if real_min >= lodestar_at:
			w["at_lodestar"] = true
			if at_lodestar_since < 0.0:
				at_lodestar_since = real_min
				out["lodestar_h"] = real_min / 60.0
		real_min += 3.0
		game_min += 45
		d.ensure_arcs(w, game_min)
		var stay := rng.randf_range(30.0, 60.0) if not bool(w.get("at_lodestar", false)) else 600.0
		var left := stay
		while left > 0.0 and real_min < limit and closed.is_empty():
			for decision in d.pending_decisions():
				var options: Array = decision["options"]
				d.apply_decision(str(decision["arc_id"]), str(options[rng.randi_range(0, options.size() - 1)]["id"]), game_min)
				real_min += 1.0
			var postings: Array = d.board_postings(w, game_min)
			var spent := 0.0
			if not postings.is_empty() and rng.randf() < story_share:
				# Once revealed, N.O.V.A. points at the main story and it leads the
				# board: a player mostly follows it.
				var pick: Dictionary = postings[rng.randi_range(0, postings.size() - 1)]
				var main_arc := str(HandType.main_story(d.state).get("confrontation_arc_id", ""))
				if not main_arc.is_empty() and str(postings[0].get("arc_id", "")) == main_arc and rng.randf() < 0.7:
					pick = postings[0]
				var quest: Dictionary = pick["quest_data"].duplicate(true)
				# A bribe only exists on combat jobs (a twisted kill job's
				# counter-offer); elsewhere it read as abandoning the job.
				var combat := str(quest["objective"].get("type", "")) in ["KILL_SHIPS", "TARGET_WITH_COMMS_REVERSAL", "RECOVER_COMBAT_DROP"]
				quest["objective"]["branch_id"] = "accept_bribe" if combat and rng.randf() < 0.25 else "finish_kill"
				var terminal := "completed" if rng.randf() < 0.9 else "abandoned"
				spent = rng.randf_range(8.0, 12.0)
				game_min += 15
				d.on_mission_terminal(quest, terminal, game_min)
				out["story_jobs"] = int(out["story_jobs"]) + 1
			else:
				spent = rng.randf_range(10.0, 15.0)
				game_min += 15
				out["other"] = int(out["other"]) + 1
			real_min += spent
			left -= spent
			d.tick(game_min)
			_note(out, d, real_min)
			if real_min >= 600.0 and (out["at_10h"] as Dictionary).is_empty():
				out["at_10h"] = _snapshot(d)
				out["cards_10h"] = _cards(d)
				out["blocked_10h"] = _lock_blockers(d)
			if real_min >= 720.0 and not out.has("blocked_12h"):
				out["blocked_12h"] = _lock_blockers(d)
	if (out["at_10h"] as Dictionary).is_empty():
		out["at_10h"] = _snapshot(d)
		out["cards_10h"] = _cards(d)
	if out["lock_h"] >= 0.0:
		out["locked_systems"] = int(out.get("_lock_sys", -1))
	out["closed_by"] = str(closed[0]) if not closed.is_empty() else ""
	var conf := str(HandType.main_story(d.state).get("confrontation_arc_id", ""))
	out["conf_ledger"] = (d.state.get("ledger", []) as Array).filter(func(l): return not conf.is_empty() and str(l).begins_with(conf)).slice(-8)
	out["final"] = _snapshot(d)
	out["blocked"] = _lock_blockers(d)
	d.free()
	return out


func _note(out: Dictionary, d, real_min: float) -> void:
	var story := HandType.main_story(d.state)
	if float(out["first_thread_h"]) < 0.0 and not HandType.seen_threads(d.state).is_empty():
		out["first_thread_h"] = real_min / 60.0
	var stage := str(story.get("stage", ""))
	if float(out["lock_h"]) < 0.0 and stage in ["locked", "revealed", "closed"]:
		out["lock_h"] = real_min / 60.0
		out["_lock_sys"] = int(out["systems"])
	if float(out["close_h"]) < 0.0 and (stage == "closed" or int(story.get("season", 1)) > 1):
		out["close_h"] = real_min / 60.0


func _snapshot(d) -> Dictionary:
	var story := HandType.main_story(d.state)
	var lock: Dictionary = story.get("lock", {})
	return {
		"stage": str(story.get("stage", "")),
		"motive": str(story.get("motive", "")),
		"method": str(story.get("method", "")),
		"goal": str(story.get("goal_id", "")),
		"hand": str(lock.get("display_name", "")),
		"threads_seen": HandType.seen_threads(d.state).size(),
		"traces_seen": HandType.seen_trace_count(d.state),
		"arcs": (d.state.get("arcs", {}) as Dictionary).size(),
		"resolved": (d.state.get("arcs", {}) as Dictionary).values().filter(func(a): return str(a.get("status", "")) == "resolved").size(),
		"ledger": (d.state.get("ledger", []) as Array).size(),
	}


## Why the main story hasn't locked (empty when it has).
func _lock_blockers(d) -> String:
	var s: Dictionary = d.state
	var story := HandType.main_story(s)
	if str(story.get("stage", "")) != "hidden":
		return ""
	var why: Array = ["visits %d" % int(s.get("visits", 0))]
	if HandType.seen_threads(s).size() < HandType.LOCK_MIN_SEEN:
		why.append("threads %d<%d" % [HandType.seen_threads(s).size(), HandType.LOCK_MIN_SEEN])
	if HandType.seen_trace_count(s) < HandType.lock_min_traces(s):
		why.append("traces %d<%d" % [HandType.seen_trace_count(s), HandType.lock_min_traces(s)])
	if HandType.proposal(s).size() < HandType.LOCK_MIN_CANDIDATES:
		why.append("candidates %d<%d" % [HandType.proposal(s).size(), HandType.LOCK_MIN_CANDIDATES])
	if HandType.evidence_systems(s) < HandType.lock_min_systems(s):
		why.append("systems %d<%d" % [HandType.evidence_systems(s), HandType.lock_min_systems(s)])
	if HandType._prime_suspect_busy(s):
		var top: Dictionary = HandType.candidates(s)[0]
		why.append("prime suspect %s busy (in %d stories)" % [top["display_name"], (top["arcs"] as Array).size()])
	return ", ".join(why)


func _cards(d) -> Array:
	var out: Array = []
	for a in (d.state.get("arcs", {}) as Dictionary).values():
		var id := str(a.get("card_id", ""))
		if not id.is_empty() and not id.begins_with("premise.hidden_hand") and not out.has(id):
			out.append(id)
	return out


func _report(results: Array) -> void:
	print("")
	print("[SeasonSim] per campaign (real play hours):")
	for r in results:
		var f: Dictionary = r["final"]
		var t: Dictionary = r["at_10h"]
		print("  #%d lodestar=%s | first thread %s | lock %s | reached Lodestar %s | close %s | systems %d | story jobs %d, other %d" % [
			r["index"], r["lodestar"], _h(r["first_thread_h"]), _h(r["lock_h"]), _h(r.get("lodestar_h", -1.0)), _h(r["close_h"]), r["systems"], r["story_jobs"], r["other"]])
		print("      hand: %s / %s / %s -> %s (stage %s) | at 10 h: %d arcs (%d resolved), %d threads seen (%d real traces), %d cards" % [
			f["motive"], f["method"], f["goal"], f["hand"] if not str(f["hand"]).is_empty() else "(not locked)", f["stage"],
			t["arcs"], t["resolved"], t["threads_seen"], t["traces_seen"], (r["cards_10h"] as Array).size()])
		if not str(r.get("closed_by", "")).is_empty():
			print("      season closed by: %s" % r["closed_by"])
			for l in r.get("conf_ledger", []):
				print("        %s" % str(l).left(150))
		for k in ["blocked_10h", "blocked_12h"]:
			if not str(r.get(k, "")).is_empty():
				print("      %s: %s" % [k, r[k]])
		if not str(r.get("blocked", "")).is_empty():
			print("      not locked because: %s" % r["blocked"])
	# Uniqueness at 10 hours: how much two campaigns' stories overlap.
	var overlaps: Array = []
	var same_goal := 0
	var same_lodestar := 0
	var pairs := 0
	for i in results.size():
		for j in range(i + 1, results.size()):
			pairs += 1
			var a: Array = results[i]["cards_10h"]
			var b: Array = results[j]["cards_10h"]
			var inter := a.filter(func(x): return b.has(x)).size()
			var uni := a.size() + b.size() - inter
			overlaps.append(float(inter) / maxf(1.0, float(uni)))
			if str(results[i]["final"]["goal"]) == str(results[j]["final"]["goal"]):
				same_goal += 1
			if str(results[i]["lodestar"]) == str(results[j]["lodestar"]):
				same_lodestar += 1
	var avg := 0.0
	var worst := 0.0
	for o in overlaps:
		avg += float(o)
		worst = maxf(worst, float(o))
	avg /= maxf(1.0, float(overlaps.size()))
	print("")
	print("[SeasonSim] uniqueness at 10 h over %d pairs: stories shared avg %.0f%% (worst pair %.0f%%); same Hidden Hand goal %d pairs; same Lodestar %d pairs" % [
		pairs, avg * 100.0, worst * 100.0, same_goal, same_lodestar])
	var locks := results.filter(func(r): return float(r["lock_h"]) >= 0.0)
	var closes := results.filter(func(r): return float(r["close_h"]) >= 0.0)
	print("[SeasonSim] main story locked in %d of %d campaigns, closed in %d" % [locks.size(), results.size(), closes.size()])
	if not locks.is_empty():
		var lh: Array = locks.map(func(r): return float(r["lock_h"]))
		lh.sort()
		print("[SeasonSim] lock at %.1f-%.1f h (median %.1f)" % [lh[0], lh[-1], lh[lh.size() / 2]])
	if not closes.is_empty():
		var ch: Array = closes.map(func(r): return float(r["close_h"]))
		ch.sort()
		print("[SeasonSim] close at %.1f-%.1f h (median %.1f)" % [ch[0], ch[-1], ch[ch.size() / 2]])


static func _h(v) -> String:
	return "never" if float(v) < 0.0 else "%.1f h" % float(v)
