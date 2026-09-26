extends RefCounted

## Mission Composer, layer 3 (vision plan 4.1): complications. About half of
## the story missions get one, drawn from a small data deck and filtered by
## the mission's verb and the system's quirks. Every complication changes how
## the job plays (a deadline, money up front, one more ship, a bigger load,
## raiders on the way, standing instead of pay),
## not only what it says; its line joins the briefing.
##
## PURE and seeded: the same mission in the same campaign always rolls the
## same complication, so a reload never rerolls the job.

const DEFAULT_PATH := "res://data/content/mission_complications.json"

static var _deck: Dictionary = {}


static func deck() -> Dictionary:
	if _deck.is_empty():
		var file := FileAccess.open(DEFAULT_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_deck = parsed
	return _deck


## The complication this mission rolls, or {} for none. `quirks` are the
## system's quirk ids.
static func roll(verb: String, quirks: Array, seed_key: String) -> Dictionary:
	var d := deck()
	var chance := float(d.get("chance", 0.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("complication|" + seed_key)
	if rng.randf() >= chance:
		return {}
	var options: Array = []
	for c in d.get("complications", []):
		if not c is Dictionary or verb not in (c.get("verbs", []) as Array):
			continue
		var needs := str(c.get("requires_quirk", ""))
		if not needs.is_empty() and needs not in quirks:
			continue
		options.append(c)
	if options.is_empty():
		return {}
	# A complication tied to this system's quirk usually wins when it applies:
	# it is what makes the job feel like it belongs here (but not always, or
	# every job in a nebula would be the same ambush).
	if rng.randf() < float(d.get("quirk_wins", 0.6)):
		for c in options:
			if not str(c.get("requires_quirk", "")).is_empty():
				return c
	return options[rng.randi() % options.size()]


## Applies `complication` to a composed offer (returns a new offer).
static func apply(offer: Dictionary, complication: Dictionary, requester_name: String) -> Dictionary:
	if complication.is_empty():
		return offer
	var out := offer.duplicate(true)
	var objective: Dictionary = out.get("objective", {})
	var effect: Dictionary = complication.get("effect", {})
	var reward := int(objective.get("reward_credits", 0))
	var extra := ""
	if effect.has("reward_multiplier"):
		reward = int(round(reward * float(effect["reward_multiplier"])))
	if effect.has("extra_kills"):
		objective["count_required"] = int(objective.get("count_required", 1)) + int(effect["extra_kills"])
	if effect.has("ore_multiplier"):
		objective["amount_required"] = snappedf(float(objective.get("amount_required", 0.0)) * float(effect["ore_multiplier"]), 1.0)
	if effect.has("advance_share"):
		var advance := int(round(reward * float(effect["advance_share"])))
		reward = int(round(reward * float(effect.get("remaining_multiplier", 1.0))))
		extra = str(advance)
		var choices: Array = out.get("choices", [])
		for choice in choices:
			if choice is Dictionary and (choice as Dictionary).has("consequence"):
				choice["consequence"]["credits_immediate"] = advance
		out["choices"] = choices
	if effect.has("ambush_count"):
		# QuestManager jumps the captain that far into the flight.
		objective["ambush_count"] = int(effect["ambush_count"])
		objective["ambush_after_seconds"] = float(effect.get("ambush_after_seconds", 50.0))
	if effect.has("standing_on_accept"):
		var faction := str(out.get("faction", ""))
		if not faction.is_empty() and faction != "neutral":
			for choice in out.get("choices", []):
				if choice is Dictionary and (choice as Dictionary).has("consequence"):
					var rep: Dictionary = (choice["consequence"] as Dictionary).get("reputation_change", {})
					rep[faction] = float(rep.get(faction, 0.0)) + float(effect["standing_on_accept"])
					choice["consequence"]["reputation_change"] = rep
	objective["reward_credits"] = reward
	out["objective"] = objective
	if effect.has("deadline_minutes"):
		out["timing"] = {"timed": true, "duration_minutes": int(effect["deadline_minutes"]), "urgent": true,
			"urgent_reward_multiplier": float(effect.get("urgent_reward_multiplier", 1.0)), "expiration_policy": "expire"}
	var hours := int(round(float(effect.get("deadline_minutes", 0)) / 60.0))
	var text := str(complication.get("text", "")).replace("{requester}", requester_name if not requester_name.is_empty() else "The client") \
		.replace("{hours}", str(hours)).replace("{extra}", extra)
	out["complication_id"] = str(complication.get("id", ""))
	out["complication_text"] = text
	out["dialogue"] = (str(out.get("dialogue", "")) + " " + text).strip_edges()
	return out
