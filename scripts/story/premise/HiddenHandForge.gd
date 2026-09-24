class_name HiddenHandForge
extends RefCounted

## Forges the main story's confrontation as an ordinary premise card, built
## from the Hidden Hand lock (plan Section 3.7). ArcEngine then runs it like
## any other card: board postings, a comms-reversal fight, a choice, and
## consequences. Its resolution closes the season.
##
## Text is assembled from the lock (identity, truth, showrunner beats), so the
## player meets a story that points back at people and details they have seen.

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const HandType := preload("res://scripts/story/premise/HiddenHand.gd")

const CARD_PREFIX := "premise.hidden_hand.s"


static func card_id_for(season: int) -> String:
	return "%s%d" % [CARD_PREFIX, season]


static func is_forged(card_id: String) -> bool:
	return card_id.begins_with(CARD_PREFIX)


## Returns {card, cast} for the confrontation, or {} if the story isn't locked.
## `witness` is another person the player met (another candidate), who asks for help.
static func forge(state: Dictionary, world: Dictionary) -> Dictionary:
	var story := HandType.main_story(state)
	var lock: Dictionary = story.get("lock", {})
	if str(story.get("stage", "")) != "locked" or lock.is_empty():
		return {}
	var name := str(lock.get("display_name", "someone"))
	var beats_text: Array = lock.get("next_beats", [])
	var truth := str(lock.get("truth", ""))
	var goal := str(story.get("goal_text", "get what they wanted"))
	var season := int(story.get("season", 1))

	# The witness: the next-best candidate, so the person asking is someone the player knows.
	var witness_entity := ""
	var witness_name := "a worried contact"
	for c in HandType.proposal(state):
		if str(c["entity_id"]) != str(lock["entity_id"]):
			witness_entity = str(c["entity_id"])
			witness_name = str(c["display_name"])
			break
	var main: Dictionary = world.get("main_station", {"id": str(world.get("system_id", "")), "display": "the main station"})
	var outposts: Array = world.get("outposts", [])
	var dock: Dictionary = outposts[0] if not outposts.is_empty() else main
	var hostile: Array = world.get("hostile_factions", [])

	var card := {
		"id": card_id_for(season), "schema_version": 1, "title": "The Hidden Hand (season %d)" % season,
		"logline": "The pattern behind this season's trouble finally has a name: %s." % name,
		"scale": "local", "tone": ["tense", "noir"], "themes": ["truth_vs_comfort"],
		"roles": [
			{"id": "culprit", "kind": "person", "archetype": "con_artist", "description": "The person behind it all.", "reuse": "prefer_existing"},
			{"id": "witness", "kind": "person", "archetype": "negotiator", "description": "Someone who pieced part of it together.", "reuse": "prefer_existing"},
			{"id": "culprit_ship", "kind": "ship", "description": "The culprit's ship, and whoever they paid to fly escort."},
			{"id": "evidence_dock", "kind": "place", "description": "Where the last proof is kept."},
		],
		"requirements": {"min_factions": 0},
		"accepts_seeds": [],
		"public_situation": "Whispers keep connecting %s to everything that has gone wrong lately." % name,
		"private_truth": truth,
		"beats": [
			{"n": 1, "function": "reversal",
			 "public_change": str(beats_text[0]) if beats_text.size() > 0 else "A last piece of proof turns up.",
			 "missions": [{"verb": "pickup_special", "requester": "witness", "target": "evidence_dock",
				"reason": "%s has pieced together part of what {role:culprit} has been doing and needs the last proof collected before it disappears." % witness_name,
				"private_fact": "The witness is afraid of being the next thing {role:culprit} buries.",
				"outcome_tags": ["proof_collected", "abandoned"],
				"routes": {"proof_collected": "next", "abandoned": "resolution:hand_slips_away"}}],
			 "player_choice": null},
			{"n": 2, "function": "climax",
			 "public_change": str(beats_text[1]) if beats_text.size() > 1 else "{role:culprit} tries to leave the system.",
			 "missions": [{"verb": "comms_reversal", "requester": "witness", "target": "culprit_ship",
				"reason": "{role:culprit} is running. %s pays for someone to stop the ship before the proof means nothing." % witness_name,
				"private_fact": "Mid-fight, {role:culprit} hails the pilot from their own ship and offers a great deal of money to let them go.",
				"outcome_tags": ["culprit_stopped", "took_the_offer"],
				"routes": {"culprit_stopped": "next", "took_the_offer": "resolution:bought_off"}}],
			 "player_choice": {"when": "after_missions",
				"prompt": "{role:culprit} is caught with the proof in your hold. They wanted to %s. What happens now?" % goal,
				"options": [
					{"id": "expose", "label": "Hand everything to the authorities", "leads_to": "resolution:exposed"},
					{"id": "quiet_deal", "label": "Keep it quiet, and make them owe you", "leads_to": "resolution:quiet_deal"}]}},
		],
		"resolutions": [
			{"id": "exposed", "summary": "The truth comes out. {role:culprit} is finished, and the people they used start picking up the pieces.",
			 "consequences": [{"type": "cast_fate", "target": "culprit", "fate": "imprisoned"},
				{"type": "cast_fate", "target": "witness", "fate": "alive_grateful"},
				{"type": "deed", "tag": "unmasked_the_hidden_hand", "public_summary": "A pilot pulled the thread that brought {role:culprit} down."}],
			 "seeds": ["public_outrage", "power_vacuum"]},
			{"id": "quiet_deal", "summary": "Nobody else ever learns it. {role:culprit} walks away smaller, and owes the pilot for the rest of their life.",
			 "consequences": [{"type": "cast_fate", "target": "culprit", "fate": "owes_debt"},
				{"type": "cast_fate", "target": "witness", "fate": "alive_grudge"},
				{"type": "deed", "tag": "kept_the_hidden_hands_secret", "public_summary": "They say a pilot knows something about {role:culprit} and isn't telling."}],
			 "seeds": ["quiet_cover_up", "debt_owed_to_player"]},
			{"id": "bought_off", "summary": "{role:culprit} pays and leaves. The witness is left holding proof no one will act on.",
			 "consequences": [{"type": "cast_fate", "target": "culprit", "fate": "fled"},
				{"type": "cast_fate", "target": "witness", "fate": "ruined"},
				{"type": "deed", "tag": "took_the_hidden_hands_money", "public_summary": "Word is a pilot let {role:culprit} buy their way out."}],
			 "seeds": ["grudge_against_player", "secret_half_exposed"]},
			{"id": "hand_slips_away", "summary": "The proof goes missing, and {role:culprit} is gone before anyone can ask a second question.",
			 "consequences": [{"type": "cast_fate", "target": "culprit", "fate": "disappeared"},
				{"type": "cast_fate", "target": "witness", "fate": "exposed"}],
			 "seeds": ["secret_half_exposed", "evidence_loose"]},
		],
		"default_resolution": "hand_slips_away",
		"loose_threads": [], "hidden_hand_compat": {"methods": [], "motives": []},
		"law_hooks": [], "radio_hooks": [], "voice_direction": {}, "novelty_tags": ["hidden_hand"],
	}
	var cast := {
		"culprit": {"kind": "person", "entity_id": str(lock["entity_id"]), "display_name": name, "reused": true},
		"witness": {"kind": "person", "entity_id": witness_entity if not witness_entity.is_empty() else "npc.hidden_hand_witness_s%d" % season,
			"display_name": witness_name, "reused": not witness_entity.is_empty()},
		"culprit_ship": {"kind": "ship", "entity_id": "ship.hidden_hand_s%d" % season, "display_name": "%s's ship" % name,
			"faction_key": str(hostile[0]) if not hostile.is_empty() else "reavers"},
		"evidence_dock": {"kind": "place", "entity_id": str(dock.get("id", "")), "display_name": str(dock.get("display", ""))},
	}
	return {"card": card, "cast": cast}
