class_name LineWriter
extends RefCounted

## Turns a premise card's director note into spoken lines (plan Section 4.1:
## "the LLM never invents structure; it writes only the lines").
##
## Code builds a narrow prompt from PUBLIC facts only (the mission's private
## fact never enters it), the small model writes 1-3 sentences in the
## character's voice, and code checks the result before anyone hears it.
## Anything that fails falls back to the director note on the board (never
## voiced as dialogue).

const GatewayType := preload("res://scripts/ai/LocalModelGateway.gd")
const ReservedType := preload("res://scripts/story/ReservedTopics.gd")
const CastingType := preload("res://scripts/story/premise/PremiseCasting.gd")

const MIN_CHARS := 40
const MAX_CHARS := 420
const SCHEMA := {"type": "object", "properties": {"line": {"type": "string"}}, "required": ["line"]}
## Only Kaelen calls the pilot this; generated people never do.
const FORBIDDEN_WORDS := ["shiny"]
## Movie-trailer filler the small model reaches for; a line with one is rewritten.
const STOCK_PHRASES := ["clock is ticking", "clock's ticking", "don't look back", "no room for mistakes", "running out of time",
	"just do it", "that's all", "you're the only one", "trust me", "no questions asked"]


## `brief` = {speaker, archetype, voice_direction, faction, situation, note, task, history?}
##   history: RecurringCast.history_note() for a returning face ("" = first meeting)
##   note: the card's director note (the mission reason), placeholders filled
##   task: plain description of what the pilot would do ("courier a sealed case to Iron Reach")
static func build_briefing_request(brief: Dictionary, model: String = "") -> Dictionary:
	var lines: PackedStringArray = []
	lines.append("You write one short spoken line for a character in a grounded, working-class space game.")
	lines.append("Speaker: %s, a %s%s." % [brief.get("speaker", "a contact"), str(brief.get("archetype", "contact")).replace("_", " "),
		(" with %s" % brief["faction"]) if not str(brief.get("faction", "")).is_empty() else ""])
	if not str(brief.get("voice_direction", "")).is_empty():
		lines.append("How they talk: %s" % brief["voice_direction"])
	lines.append("What everyone knows: %s" % brief.get("situation", ""))
	lines.append("What they need from the pilot (director's note, third person): %s" % brief.get("note", ""))
	lines.append("The job: %s" % brief.get("task", ""))
	if not str(brief.get("history", "")).is_empty():
		lines.append("History with the pilot: %s Bring it up briefly, in your own words, the way this person would." % brief["history"])
	lines.append("")
	lines.append("Write what %s says to the pilot over comms, in first person, 1-3 sentences, under 60 words." % brief.get("speaker", "they"))
	lines.append("Say what they need and why this pilot; keep something back if the note says they won't say why. Use no numbers or names that are not above. No stage directions, no quotation marks.")
	lines.append("Sound like a tired working person, not a movie: no stock lines like 'the clock is ticking', 'don't look back' or 'no room for mistakes'. Don't invent places, groups or history.")
	return {
		"model": model if not model.is_empty() else GatewayType.DEFAULT_SMALL_MODEL, "prompt": "\n".join(lines), "format": SCHEMA,
		"stream": false, "think": false, "keep_alive": GatewayType.MODEL_KEEP_ALIVE,
		"options": {"num_ctx": GatewayType.SMALL_NUM_CTX, "temperature": 0.8},
	}


## Checks the model's line against the brief. `private_fact` is used only to
## catch leaks; it was never in the prompt. Returns {ok, reason, line}.
static func check_line(response_text: String, brief: Dictionary, private_fact: String = "") -> Dictionary:
	var json := JSON.new()
	if json.parse(response_text) != OK or not json.data is Dictionary:
		return {"ok": false, "reason": "not_json", "line": ""}
	var line := str((json.data as Dictionary).get("line", "")).strip_edges().trim_prefix("\"").trim_suffix("\"").strip_edges()
	if line.length() < MIN_CHARS or line.length() > MAX_CHARS:
		return {"ok": false, "reason": "length", "line": ""}
	if line.contains("{") or line.contains("}"):
		return {"ok": false, "reason": "placeholder", "line": ""}
	if not ReservedType.is_clean(line):
		return {"ok": false, "reason": "reserved_topic", "line": ""}
	# Quoted speech or narration ("Raspy voice cuts in. 'Listen...'"); a
	# leading apostrophe is fine only as a clipped word ('em, 'cause).
	var quoted := RegEx.new()
	quoted.compile("(^|\\s)'(?!em\\b|cause\\b|round\\b|til\\b)")
	if line.contains("\"") or line.contains("*") or line.contains("(") or quoted.search(line) != null:
		return {"ok": false, "reason": "stage_direction", "line": ""}
	var lower := line.to_lower().replace("’", "'")
	for word in FORBIDDEN_WORDS:
		if lower.contains(word):
			return {"ok": false, "reason": "forbidden_word", "line": ""}
	for phrase in STOCK_PHRASES:
		if lower.contains(phrase):
			return {"ok": false, "reason": "stock_phrase", "line": ""}
	var inputs := "%s %s %s %s %s %s" % [brief.get("speaker", ""), brief.get("situation", ""), brief.get("note", ""), brief.get("task", ""), brief.get("faction", ""), brief.get("history", "")]
	var inputs_lower := inputs.to_lower()
	var digits := RegEx.new()
	digits.compile("\\d+")
	for found in digits.search_all(line):
		if not inputs.contains(found.get_string()):
			return {"ok": false, "reason": "invented_number", "line": ""}
	var words := RegEx.new()
	words.compile("[a-zA-Z]{7,}")
	for found in words.search_all(private_fact):
		var w := found.get_string().to_lower()
		if lower.contains(w) and not inputs_lower.contains(w):
			return {"ok": false, "reason": "leaked_private_fact", "line": ""}
	return {"ok": true, "reason": "", "line": line}


## The brief for a composed premise offer (PremiseMissionComposer.compose).
static func brief_for_offer(offer: Dictionary, card: Dictionary, cast: Dictionary, world: Dictionary) -> Dictionary:
	var role := str(offer.get("premise_requester_role", ""))
	var faction_name := ""
	var faction_id := str(offer.get("faction", ""))
	for key in cast.keys():
		var entity: Dictionary = cast[key]
		if str(entity.get("entity_id", "")) == faction_id and not faction_id.is_empty():
			faction_name = str(entity.get("display_name", ""))
	return {
		"speaker": str(offer.get("agent_name", "A contact")),
		"archetype": str(offer.get("agent_role", "contact")),
		"faction": faction_name,
		"voice_direction": str((card.get("voice_direction", {}) as Dictionary).get(role, "")) if card.get("voice_direction") is Dictionary else "",
		"situation": CastingType.fill_text(str(card.get("public_situation", "")), cast, world),
		"note": str(offer.get("dialogue", "")),
		"task": task_text(offer.get("objective", {})),
	}


## A plain description of what the pilot would do, from a live objective.
static func task_text(objective: Dictionary) -> String:
	match str(objective.get("type", "")):
		"KILL_SHIPS":
			return "destroy %d of the target's ships" % int(objective.get("count_required", 3))
		"TARGET_WITH_COMMS_REVERSAL":
			return "hail a target ship and talk it down, or finish it"
		"RECOVER_COMBAT_DROP":
			return "take %s off hostile ships and bring it to %s" % [objective.get("item_name", "the cargo"), objective.get("turn_in_location", "the station")]
		"DELIVER_ORE":
			var ore_name := "ore"
			if not str(objective.get("ore_type", "")).is_empty():
				ore_name = preload("res://scripts/economy/OreTypes.gd").display(str(objective["ore_type"])).to_lower()
			return "mine %d units of %s and deliver them" % [int(objective.get("amount_required", 20)), ore_name]
		"DELIVERY_COURIER":
			return "carry %s from %s to %s" % [objective.get("item_name", "a package"), objective.get("origin_display", "here"), objective.get("destination_display", "the station")]
		"PURCHASE_DELIVERY":
			return "buy %s at %s and bring it to %s" % [objective.get("item_name", "supplies"), objective.get("store_display", "the store"), objective.get("destination_display", "the station")]
		"PICKUP_SPECIAL":
			return "collect %s at %s and bring it to %s" % [objective.get("part_name", "a package"), objective.get("target_outpost_display", "the outpost"), objective.get("destination", "the station")]
		"INVESTIGATE_SIGNAL":
			return "go look at %s and report what you find" % objective.get("site_display", "the site")
	return "a job"


static func response_text(body: String) -> String:
	var json := JSON.new()
	if json.parse(body) != OK or not json.data is Dictionary:
		return ""
	return str((json.data as Dictionary).get("response", ""))
