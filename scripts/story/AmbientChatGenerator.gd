extends Node

# AmbientChatGenerator — Phase E of the narrative foundation
# (docs/design_narrative_system.md §7). Every 3-5 minutes of open play, two
# background NPCs have a short conversation in system chat. Topic buckets:
# 50% mundane, 30% story-adjacent, 20% overheard intel — the mundane is what
# makes the world feel real; the intel lands harder surrounded by laundry talk.
#
# Privacy: prompts are built ONLY from player-safe story state (active
# tensions, foreshadow, player_knows, pending hooks) plus
# StoryManager.get_ambient_flavor_block(). Director-only fields (hidden
# truths, kaelen_hidden_angle, nova_memory_flicker) are never read here.
#
# Fallback policy: generation failure = silence + a logged diagnostics event,
# never canned filler (see memory: fallbacks are failures).

const BUCKET_MUNDANE := "mundane"
const BUCKET_STORY := "story_adjacent"
const BUCKET_INTEL := "overheard_intel"

# Roll boundaries: [0, 0.5) mundane, [0.5, 0.8) story-adjacent, [0.8, 1) intel.
const STORY_ROLL_MIN := 0.5
const INTEL_ROLL_MIN := 0.8

# Real-time firing window during open play (design doc: every 3-5 minutes).
const FIRE_INTERVAL_MIN_S := 180.0
const FIRE_INTERVAL_MAX_S := 300.0
# Seconds between the lines of one conversation, so it reads like people
# actually talking instead of a wall of text hitting the feed at once.
const LINE_GAP_MIN_S := 2.4
const LINE_GAP_MAX_S := 4.2

# Two muted speaker colors — background radio, visually quieter than mission
# chatter or N.O.V.A.'s blue.
const SPEAKER_COLOR_A := Color(0.72, 0.70, 0.62)
const SPEAKER_COLOR_B := Color(0.62, 0.68, 0.72)

# Archetype pool. A conversation picks two DIFFERENT archetypes and one name
# from each. Roles feed the prompt; names are what the chatter feed shows.
const ARCHETYPES := [
	{"role": "hauler captain", "names": ["Merek", "Odessa", "Bram", "Ciri Vale"]},
	{"role": "dock controller", "names": ["Ivet", "Hollis", "Tam Okoro", "Prewitt"]},
	{"role": "ore prospector", "names": ["Dusty Ren", "Kova", "Halloran", "Bex"]},
	{"role": "tug pilot", "names": ["Skiff", "Marlo", "Junie Task", "Ferro"]},
	{"role": "customs clerk", "names": ["Adler", "Miss Penrose", "Vikram", "Soot"]},
	{"role": "station mechanic", "names": ["Greasy Wynn", "Talia Bolt", "Mott", "Harker"]},
	{"role": "insurance adjuster", "names": ["Mr. Creel", "Nadia Form", "Pell", "Ostrander"]},
	{"role": "cafeteria cook", "names": ["Big Sal", "Ondine", "Chef Rickets", "Mama Vex"]},
]

# Mundane subject pool — deliberately ordinary. The small model supplies the
# jokes; these supply the ordinariness. Retired per chapter like every topic.
const MUNDANE_SUBJECTS := [
	"the new docking fees and whether they're legal",
	"the cafeteria's mystery stew rotation",
	"a laundry cycler that eats one sock per load",
	"whose turn it is to recalibrate the airlock sensor",
	"a mattress that smells faintly of coolant",
	"the vending machine that gives double if you hit it right",
	"filling out insurance form 77-C in triplicate",
	"a cousin who won big on station bingo and won't shut up about it",
	"whether real coffee is worth smuggler prices",
	"the observation deck couple who won't stop slow dancing",
	"a shift supervisor who schedules meetings during meal breaks",
	"the air recycler making a new noise nobody wants to name",
	"gravity plating that flickers in section nine",
	"a pet lizard that got loose in the vents again",
	"union dues going up while the dues collector got a new jacket",
	"the barber who only knows one haircut",
	"expired ration bars that taste better than the fresh ones",
	"a karaoke night that ended in a formal complaint",
	"someone hoarding all the good wrenches",
	"the water tasting like pennies since the last filter swap",
	"a promotion that came with a title and no raise",
	"dock camera footage of someone tripping over their own tether",
	"the price of boots doubling since the last freighter came through",
	"a horoscope printer that only prints bad omens",
]

# ── Pure logic (unit-tested, no scene/network access) ───────────────────────────

static func pick_bucket(roll: float) -> String:
	if roll >= INTEL_ROLL_MIN:
		return BUCKET_INTEL
	if roll >= STORY_ROLL_MIN:
		return BUCKET_STORY
	return BUCKET_MUNDANE


static func topic_id(bucket: String, subject: String) -> String:
	return "ambient:%s:%s" % [bucket, subject.sha256_text().substr(0, 12)]


# Builds the candidate topic list for one bucket from a PLAYER-SAFE story
# snapshot. Reads only: active_tensions, current_foreshadow, player_knows,
# pending_hooks. Never touches director-only fields — that is the whole
# privacy contract of this subsystem.
static func build_topic_candidates(bucket: String, story_state: Dictionary) -> Array:
	var candidates: Array = []
	match bucket:
		BUCKET_STORY:
			for tension in story_state.get("active_tensions", []):
				var t := str(tension).strip_edges()
				if not t.is_empty():
					candidates.append({
						"id": topic_id(BUCKET_STORY, t),
						"bucket": BUCKET_STORY,
						"subject": t,
					})
			var foreshadow := str(story_state.get("current_foreshadow", "")).strip_edges()
			if not foreshadow.is_empty():
				candidates.append({
					"id": topic_id(BUCKET_STORY, foreshadow),
					"bucket": BUCKET_STORY,
					"subject": foreshadow,
				})
			for truth in story_state.get("player_knows", []):
				var k := str(truth).strip_edges()
				if not k.is_empty():
					candidates.append({
						"id": topic_id(BUCKET_STORY, k),
						"bucket": BUCKET_STORY,
						"subject": k,
					})
		BUCKET_INTEL:
			for hook in story_state.get("pending_hooks", []):
				var h := str(hook).strip_edges()
				if not h.is_empty():
					candidates.append({
						"id": topic_id(BUCKET_INTEL, h),
						"bucket": BUCKET_INTEL,
						"subject": h,
					})
		_:
			for subject in MUNDANE_SUBJECTS:
				candidates.append({
					"id": topic_id(BUCKET_MUNDANE, str(subject)),
					"bucket": BUCKET_MUNDANE,
					"subject": str(subject),
				})
	return candidates


# First candidate whose id is not in used_ids, scanning from start_index so
# variety doesn't always favor the front of the pool. Returns {} when the
# bucket is exhausted for this chapter (caller falls back to mundane, and an
# exhausted mundane pool allows reuse rather than going silent — reuse of
# laundry talk is invisible; silence for a whole chapter is not).
static func select_topic(candidates: Array, used_ids: Array, start_index: int = 0) -> Dictionary:
	if candidates.is_empty():
		return {}
	var count := candidates.size()
	for offset in range(count):
		var candidate: Dictionary = candidates[(start_index + offset) % count]
		if str(candidate.get("id", "")) not in used_ids:
			return candidate
	return {}


# Bucket-specific framing so intel reads as an overheard fragment, story-talk
# as locals reacting, and mundane as genuinely mundane.
static func _bucket_instruction(bucket: String) -> String:
	match bucket:
		BUCKET_INTEL:
			return (
				"They are casually discussing a FRAGMENT of something bigger they half-heard. "
				+ "Keep it incomplete: no conclusions, no explanations, at least one detail wrong "
				+ "or disputed between them. They do not know anyone is listening."
			)
		BUCKET_STORY:
			return (
				"They are reacting to this local situation the way working people do — "
				+ "how it affects shifts, prices, routes, or nerves. No briefing-room summary."
			)
		_:
			return (
				"The topic is genuinely mundane. Keep it small and human. The wider troubles "
				+ "of the sector may color a word or two, but the conversation stays about the topic."
			)


static func build_prompt(
	topic: Dictionary,
	speaker_a: Dictionary,
	speaker_b: Dictionary,
	flavor_block: String
) -> String:
	var bucket := str(topic.get("bucket", BUCKET_MUNDANE))
	var flavor_section := ""
	if not flavor_block.strip_edges().is_empty():
		flavor_section = (
			"Campaign flavor (background mood only — never quote it, never summarize it):\n"
			+ flavor_block.strip_edges() + "\n\n"
		)
	return "\n".join([
		"You are writing overheard background radio chatter for a space trading game, PG-13,",
		"dry and slightly dark humor welcome. Two station locals are talking on an open channel.",
		"",
		"Speaker A: %s, a %s." % [str(speaker_a.get("name", "A")), str(speaker_a.get("role", "local"))],
		"Speaker B: %s, a %s." % [str(speaker_b.get("name", "B")), str(speaker_b.get("role", "local"))],
		"",
		"Topic: %s" % str(topic.get("subject", "")),
		_bucket_instruction(bucket),
		"",
		flavor_section
		+ "Rules:",
		"- Write 2 to 4 lines TOTAL, alternating speakers, starting with A.",
		"- Each line under 22 words. Spoken, casual, specific — no narration, no stage directions.",
		"- They never mention the player, 'a pilot listening', or anything meta.",
		"- No new lore inventions: no new faction names, no new station names, no history dumps.",
		"- Never start a line with the speaker's own name or role — the radio already tags who is speaking.",
		"",
		# FLAT json, exactly four string keys. Live-fired 2026-07-04 on qwen3:4b:
		# nested arrays-of-objects get corrupted on the second element (3/3 runs),
		# and freeform text makes the model narrate its planning instead of
		# writing lines (6/6 runs, even with think:false). A flat object under
		# format:"json" is the one envelope it holds reliably — same lesson as
		# the campaign bible's flat @@labels. Code owns all structure.
		"Return only JSON with exactly these four string keys and nothing else:",
		"{\"a1\": \"A's first line\", \"b1\": \"B's reply\", \"a2\": \"A again, or empty\", \"b2\": \"B again, or empty\"}",
		"a1 and b1 are required. Set a2 and/or b2 to \"\" for a shorter exchange.",
	])


# Parses the model's FLAT json ({"a1": ..., "b1": ..., "a2": ..., "b2": ...})
# into [{speaker: "a"|"b", text: String}] in conversation order. Key case and
# stray whitespace are tolerated; empty/short optional slots are skipped. Hard
# requirements: 2-4 usable lines and BOTH speakers present (one voice is a
# monologue, not a conversation — reject, skip the beat). Structure is owned
# entirely here; nesting was proven unreliable (see build_prompt note).
static func parse_chat_lines(
	inner_json_text: String,
	name_a: String = "",
	name_b: String = ""
) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(inner_json_text.strip_edges()) != OK:
		return {"ok": false, "reason": "inner_parse_failed"}
	var data: Variant = parser.get_data()
	if not data is Dictionary:
		return {"ok": false, "reason": "not_an_object"}
	# Normalize keys once so "A1"/" a1 " still land.
	var normalized := {}
	for key in (data as Dictionary).keys():
		normalized[str(key).strip_edges().to_lower()] = (data as Dictionary)[key]
	var lines: Array = []
	var saw_a := false
	var saw_b := false
	for slot in ["a1", "b1", "a2", "b2"]:
		var text := str(normalized.get(slot, "")).strip_edges()
		text = text.trim_prefix("\"").trim_suffix("\"").strip_edges()
		var speaker := str(slot).substr(0, 1)
		# Despite the prompt rule, the model sometimes self-tags ("Ivet: ...").
		# The feed already shows the sender, so strip a leading own-name/label
		# prefix rather than shipping a doubled name.
		var own_name := name_a if speaker == "a" else name_b
		text = _strip_speaker_prefix(text, own_name, speaker)
		if text.length() < 4 or text.length() > 170:
			continue
		if speaker == "a":
			saw_a = true
		else:
			saw_b = true
		lines.append({"speaker": speaker, "text": text})
	if lines.size() < 2:
		return {"ok": false, "reason": "too_few_lines"}
	if not (saw_a and saw_b):
		return {"ok": false, "reason": "single_voice"}
	return {"ok": true, "lines": lines}


# Removes a leading self-tag from a spoken line. Live-fired variants seen:
# "Ivet: ...", "Ivet - ...", "Ivet, dock controller: '...'", truncated "Sk: ...",
# bare "a: ...". Strategy: if a ":" or "-" separator appears early, and the
# label before it relates to the speaker's OWN name (either is a prefix of the
# other) or the slot letter, drop label+separator. Addressing the OTHER speaker
# ("Skiff, you seeing this?") has no early separator and passes untouched.
# Finally unwraps a fully quote-wrapped line.
static func _strip_speaker_prefix(text: String, own_name: String, slot_letter: String) -> String:
	var out := text.strip_edges()
	var sep := -1
	for i in range(mini(out.length(), 28)):
		if out[i] == ":" or (out[i] == "-" and i > 0 and out[i - 1] == " "):
			sep = i
			break
	if sep > 0:
		var label := out.substr(0, sep).strip_edges().to_lower()
		label = label.lstrip("*\"'").rstrip("*\"'").strip_edges()
		var lower_name := own_name.strip_edges().to_lower()
		var matches_own := false
		if label == slot_letter:
			matches_own = true
		elif not lower_name.is_empty() and label.length() >= 2:
			matches_own = label.begins_with(lower_name) or lower_name.begins_with(label)
		if matches_own:
			out = out.substr(sep + 1).strip_edges()
	# Unwrap a line the model quoted wholesale.
	for quote in ["'", "\""]:
		if out.length() >= 2 and out.begins_with(quote) and out.ends_with(quote):
			out = out.substr(1, out.length() - 2).strip_edges()
	return out


# ── Runtime (autoload) ───────────────────────────────────────────────────────────

var _in_combat := false
var _seconds_until_fire := 0.0
var _generation_in_flight := false
var _delivery_serial := 0  # bumps on reset so stale staggered lines cancel


func _ready() -> void:
	_seconds_until_fire = _roll_interval()
	if is_instance_valid(CombatManager):
		if CombatManager.has_signal("combat_started"):
			CombatManager.combat_started.connect(func(_enemy = null) -> void: _in_combat = true)
		if CombatManager.has_signal("combat_ended"):
			CombatManager.combat_ended.connect(func(_won = false) -> void: _in_combat = false)


func _process(delta: float) -> void:
	_seconds_until_fire -= delta
	if _seconds_until_fire > 0.0:
		return
	# Due. Only actually fire in open play; otherwise check again shortly —
	# the beat waits for the player instead of silently skipping the window.
	if not _can_fire_now():
		_seconds_until_fire = 10.0
		return
	_seconds_until_fire = _roll_interval()
	_fire_conversation()


func reset_for_restart() -> void:
	_in_combat = false
	_generation_in_flight = false
	_delivery_serial += 1  # cancels any staggered lines still pending
	_seconds_until_fire = _roll_interval()


func _roll_interval() -> float:
	return randf_range(FIRE_INTERVAL_MIN_S, FIRE_INTERVAL_MAX_S)


# Open play = player exists, alive, flying free (not docked), not in combat,
# small model verified, and a campaign is actually seeded (no ambient chatter
# over the main menu or the tutorial's first seconds).
func _can_fire_now() -> bool:
	if _generation_in_flight or _in_combat:
		return false
	var p = GlobalState.player
	if p == null or not is_instance_valid(p):
		return false
	if bool(p.get("destroyed")) or bool(p.get("is_docked")):
		return false
	if not is_instance_valid(LLMInterface) or not bool(LLMInterface.get("small_model_verified")):
		return false
	if not is_instance_valid(StoryManager) \
			or not bool(StoryManager.story_state.get("bible_seeded", false)):
		return false
	return true


# DevPanel hook: force a conversation immediately, bypassing the timer (but
# not the gating — you still need to be in open play). Returns a status line.
func debug_fire_now() -> String:
	if not _can_fire_now():
		return "ambient chat: gated (docked/combat/no model/no campaign?)"
	_fire_conversation()
	return "ambient chat: fired"


func _pick_speaker_pair() -> Array:
	var first_idx := randi() % ARCHETYPES.size()
	var second_idx := (first_idx + 1 + (randi() % (ARCHETYPES.size() - 1))) % ARCHETYPES.size()
	var out: Array = []
	for idx in [first_idx, second_idx]:
		var archetype: Dictionary = ARCHETYPES[idx]
		var names: Array = archetype.get("names", ["Local"])
		out.append({
			"role": str(archetype.get("role", "local")),
			"name": str(names[randi() % names.size()]),
		})
	return out


func _fire_conversation() -> void:
	var used: Array = StoryManager.story_state.get("ambient_used_topics", []) \
		if StoryManager.story_state.get("ambient_used_topics", []) is Array else []
	var bucket := pick_bucket(randf())
	var candidates := build_topic_candidates(bucket, StoryManager.story_state)
	var topic := select_topic(candidates, used, randi() % maxi(1, candidates.size()))
	if topic.is_empty() and bucket != BUCKET_MUNDANE:
		# Story/intel reserve exhausted this chapter — mundane always has depth.
		bucket = BUCKET_MUNDANE
		candidates = build_topic_candidates(bucket, StoryManager.story_state)
		topic = select_topic(candidates, used, randi() % maxi(1, candidates.size()))
	if topic.is_empty():
		# Whole mundane pool used this chapter: allow reuse rather than silence.
		topic = candidates[randi() % candidates.size()]
	var pair := _pick_speaker_pair()
	var flavor := ""
	if StoryManager.has_method("get_ambient_flavor_block"):
		flavor = StoryManager.get_ambient_flavor_block()
	var prompt := build_prompt(topic, pair[0], pair[1], flavor)
	_generation_in_flight = true
	LLMInterface.request_ambient_chat(
		prompt,
		func(result: Dictionary) -> void:
			_generation_in_flight = false
			if not bool(result.get("ok", false)):
				GenerationDiagnostics.record_fallback(
					"ambient_chat",
					str(result.get("reason", "unknown")),
					"AmbientChatGenerator",
					{"bucket": str(topic.get("bucket", "")), "topic": str(topic.get("subject", "")).left(60)}
				)
				return  # silence, never canned filler
			var parsed := parse_chat_lines(
				str(result.get("inner_text", "")),
				str(pair[0].get("name", "")),
				str(pair[1].get("name", ""))
			)
			if not bool(parsed.get("ok", false)):
				GenerationDiagnostics.record_fallback(
					"ambient_chat",
					str(parsed.get("reason", "shape_rejected")),
					"AmbientChatGenerator",
					{"bucket": str(topic.get("bucket", ""))}
				)
				return
			if StoryManager.has_method("record_ambient_topic_used"):
				StoryManager.record_ambient_topic_used(str(topic.get("id", "")))
			GenerationDiagnostics.record_content_source(
				"ambient_chat", "llm", "AmbientChatGenerator",
				{"bucket": str(topic.get("bucket", "")), "lines": (parsed["lines"] as Array).size()}
			)
			_deliver_lines(parsed["lines"], pair)
	)


# Emits the conversation with human pacing. Cancels cleanly if a restart bumps
# the serial or the player docks / enters combat mid-conversation — trailing
# lines just stop, which reads as the channel drifting out of range.
func _deliver_lines(lines: Array, pair: Array) -> void:
	var serial := _delivery_serial
	var delay := 0.0
	for line in lines:
		var speaker_key := str((line as Dictionary).get("speaker", "a"))
		var speaker: Dictionary = pair[0] if speaker_key == "a" else pair[1]
		var text := str((line as Dictionary).get("text", ""))
		var sender := str(speaker.get("name", "Local"))
		var color := SPEAKER_COLOR_A if speaker_key == "a" else SPEAKER_COLOR_B
		if delay <= 0.0:
			_emit_line(sender, text, color)
		else:
			get_tree().create_timer(delay).timeout.connect(
				func() -> void:
					if serial != _delivery_serial:
						return
					if _in_combat:
						return
					var p = GlobalState.player
					if p == null or not is_instance_valid(p) or bool(p.get("is_docked")):
						return
					_emit_line(sender, text, color)
			)
		delay += randf_range(LINE_GAP_MIN_S, LINE_GAP_MAX_S)


func _emit_line(sender: String, text: String, color: Color) -> void:
	if is_instance_valid(GlobalState) and GlobalState.has_method("emit_chatter"):
		GlobalState.emit_chatter(sender, text, color)
