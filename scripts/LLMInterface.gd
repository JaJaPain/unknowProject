extends Node

const LocalModelGatewayType := preload("res://scripts/ai/LocalModelGateway.gd")
const NarrativeDirectorType := preload("res://scripts/ai/NarrativeDirector.gd")

const OLLAMA_URL = LocalModelGatewayType.OLLAMA_GENERATE_URL
const MODEL_NAME = LocalModelGatewayType.DEFAULT_SMALL_MODEL
const TIMEOUT_SECONDS = LocalModelGatewayType.REQUEST_TIMEOUTS["quest_dialogue"]
const QUEST_CANDIDATE_TARGET_COUNT := 3
# Kaelen intro telemetry is written to user://kaelen_intro_stats.json so
# counters survive game restarts. Read via get_kaelen_intro_stats().
const _KAELEN_STATS_PATH = "user://kaelen_intro_stats.json"

var http_request: HTTPRequest
var active_callback: Callable
var is_waiting: bool = false

# ── Ollama watchdog ───────────────────────────────────────────────────────────
const OLLAMA_HEALTH_URL := "http://127.0.0.1:11434/"
const _OLLAMA_POLL_INTERVAL := 2.0    # seconds between readiness polls
const _OLLAMA_MAX_POLLS    := 15      # 15 × 2s = 30s before giving up
var _ollama_ready:        bool = false
var _ollama_poll_count:   int  = 0
var _ollama_start_pid:    int  = -1   # PID of the process we launched, if any
var _models_warm_started: bool = false  # guard so reconnect doesn't re-warm
var request_start_time: float = 0.0
var last_history_text: String = ""
var active_model_name: String = MODEL_NAME
var active_large_model_name: String = ""
var world_lore_text: String = ""
var campaign_bible_context_text: String = ""
var story_state_context_text: String = ""
var idea_memory_context_text: String = ""
var _known_quest_fingerprints: Dictionary = {}   # fingerprint -> true; rejects exact duplicate candidates
var _pending_fallback_reason: String = ""
var _pending_substitutions: Dictionary = {}
var _quest_candidate_prompt: String = ""
var _quest_candidate_headers: Array[String] = []
var _quest_candidate_context: Dictionary = {}
var _quest_candidate_attempts_started: int = 0
var _quest_candidate_results: Array[Dictionary] = []
var _quest_candidate_requests: Array[HTTPRequest] = []

# ── Kaelen intro telemetry ────────────────────────────────────────────────────
# Persistent counters in user://kaelen_intro_stats.json. Tracks how often the
# speaker-leakage guard fires and how the self-critique retry path is doing
# across game sessions. Read via get_kaelen_intro_stats(), dumped to console
# via print_kaelen_intro_stats(). Use reset_kaelen_intro_stats() to clear.
# Path is in the per-user Godot data dir, so it survives restarts and is
# separate from the quest history file.
var _kaelen_intro_attempts: int = 0              # total LLM calls made
var _kaelen_intro_successes: int = 0             # lines that passed validation
var _kaelen_intro_rejected_first_try: int = 0    # bad line, triggered a retry
var _kaelen_intro_rejected_after_retry: int = 0  # bad line on attempt 1, gave up
var _kaelen_intro_network_failures: int = 0      # HTTP / request init failures
var _kaelen_intro_parse_failures: int = 0        # outer / inner JSON parse fail

signal model_discovered(model_name: String)
signal llm_connection_attempt(attempt: int)
signal llm_connection_established(model_name: String)

var llm_connected: bool = false
var connection_attempts: int = 0

# Politically neutral, profit-driven fallback templates
var fallback_templates = [
	{
		"title": "Silicate Brokerage",
		"faction": "zenith",
		"agent_name": "Broker Kaelen",
		"dialogue": "Alright, Shiny. Zenith needs a shipment of silicate ore to rebuild their station shields. They're paying standard rates, but I negotiated a 15% brokerage cut for us. Bring me 30 m³ of ore, and we split the profit. Go fetch it.",
		"objective": {
			"type": "DELIVER_ORE",
			"amount_required": 30.0,
			"reward_credits": 150
		},
		"choices": [
			{
				"text": "Sounds like easy money. I'll get to mining.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"zenith": 3},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "Excellent, Shiny. Make it quick; time is credits."
				}
			},
			{
				"text": "Fuel isn't free, Kaelen. I need a 40 credits advance.",
				"consequence": {
					"credits_immediate": 40,
					"reputation_change": {"zenith": -2},
					"combat_multiplier": 1.3,
					"reward_credits_multiplier": 1.2,
					"dialogue_response": "Taking a bite out of my margins, Shiny? Fine, credits wired. But I have to route you through a more contested lane to cover my costs. Watch out for Aurelia patrols."
				}
			},
			{
				"text": "150 is garbage. Double the payout or mine it yourself.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"zenith": -5},
					"combat_multiplier": 1.7,
					"reward_credits_multiplier": 1.6,
					"dialogue_response": "Hustling a hustler? I respect the gall, Shiny. Payout is bumped, but expect Aurelia interceptors on your tail. Good luck."
				}
			}
		]
	},
	{
		"title": "Thinning the Patrols",
		"faction": "aurelia",
		"agent_name": "Broker Kaelen",
		"dialogue": "Listen up, Shiny. An Aurelia smuggler contact wants Zenith's patrol ships thinned out to ease their transport runs. They're paying top credits. Go blow up 3 Zenith ships. I don't care about their war, I just care about my finder's fee. What do you say?",
		"objective": {
			"type": "KILL_SHIPS",
			"target_faction": "zenith",
			"count_required": 3,
			"reward_credits": 200
		},
		"choices": [
			{
				"text": "A job's a job. I'll clear them.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"zenith": -4, "aurelia": 4},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "Splendid, Shiny. Keep it clean and don't mention my name."
				}
			},
			{
				"text": "I'll need 50 credits up front for ammunition.",
				"consequence": {
					"credits_immediate": 50,
					"reputation_change": {"zenith": -5, "aurelia": -1},
					"combat_multiplier": 1.3,
					"reward_credits_multiplier": 1.2,
					"dialogue_response": "Fine, here's your advance, Shiny. But don't mess this up; my smuggling client doesn't like loose ends. Expect tougher Zenith escorts."
				}
			},
			{
				"text": "Zenith will put a price on my head. Payout is too low.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"zenith": -8, "aurelia": 2},
					"combat_multiplier": 1.6,
					"reward_credits_multiplier": 1.5,
					"dialogue_response": "Fair point, Shiny. Payout is increased, but Zenith patrol command will send interceptors directly after you once you open fire. Watch your back."
				}
			}
		]
	},
	{
		"title": "Aurelia Ore Run",
		"faction": "aurelia",
		"agent_name": "Broker Kaelen",
		"dialogue": "Aurelia scrap merchants need refined silicate for their hull repairs, Shiny. They pay well, and they don't ask questions. Deliver 20 m³ of ore to my dock. I'll handle the laundering, we both get rich. Simple.",
		"objective": {
			"type": "DELIVER_ORE",
			"amount_required": 20.0,
			"reward_credits": 120
		},
		"choices": [
			{
				"text": "No questions asked. I'll go mine it.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"aurelia": 3},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "Excellent, Shiny. Keep your scanners peeled while mining."
				}
			},
			{
				"text": "I want 30 credits advance to cover dock fees.",
				"consequence": {
					"credits_immediate": 30,
					"reputation_change": {"aurelia": -1},
					"combat_multiplier": 1.3,
					"reward_credits_multiplier": 1.2,
					"dialogue_response": "Greedy, aren't we, Shiny? Done. But Vanguard patrols are sweeping the belts today. Keep your lasers cold."
				}
			},
			{
				"text": "Smuggling is risky. Payout needs a boost.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"aurelia": -3},
					"combat_multiplier": 1.6,
					"reward_credits_multiplier": 1.5,
					"dialogue_response": "Smuggling tax, right, Shiny? Payout is up. But Vanguard security forces will be actively scanning cargo holds in the area. Stay alert."
				}
			}
		]
	},
	{
		"title": "Clearing the Lanes",
		"faction": "vanguard",
		"agent_name": "Broker Kaelen",
		"dialogue": "A Vanguard shipping corp is losing cargo to Aurelia raiders in the belt, Shiny. They've offered a bounty to clear the lane. Eliminate 4 Aurelia ships. They get their trade route back, I get my broker commission, you get paid. Win-win-win.",
		"objective": {
			"type": "KILL_SHIPS",
			"target_faction": "aurelia",
			"count_required": 4,
			"reward_credits": 220
		},
		"choices": [
			{
				"text": "I'll clear the raiders.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"vanguard": 4, "aurelia": -4},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "Good, Shiny. Make sure the lanes are clear."
				}
			},
			{
				"text": "I need 60 credits advance to tune my lasers.",
				"consequence": {
					"credits_immediate": 60,
					"reputation_change": {"vanguard": -2, "aurelia": -5},
					"combat_multiplier": 1.3,
					"reward_credits_multiplier": 1.2,
					"dialogue_response": "Expensive tastes, Shiny. Credits transferred. But the raiders will be hunting in packs now. Be prepared."
				}
			},
			{
				"text": "Vanguard dirty work is premium work. Make it worth it.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"vanguard": -4, "aurelia": -8},
					"combat_multiplier": 1.7,
					"reward_credits_multiplier": 1.6,
					"dialogue_response": "Bold play, Shiny. I'll adjust the contract, but you're going to face Aurelia heavy sentinels out there. Don't get blown to scrap."
				}
			}
		]
	},
	{
		"title": "Reaver Cleanup",
		"faction": "zenith",
		"agent_name": "Broker Kaelen",
		"dialogue": "Reavers have been hitting cargo haulers on the outer belt, Shiny. Zenith wants 3 of them scraped off the lane. Standard bounty work. Clean, quick, and profitable. Get it done.",
		"objective": {
			"type": "KILL_SHIPS",
			"target_faction": "reavers",
			"count_required": 3,
			"reward_credits": 180
		},
		"choices": [
			{
				"text": "Reavers are easy prey. I'll handle it.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"zenith": 3},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "Don't get cocky, Shiny. Reavers fight dirty. But you'll be fine. Probably."
				}
			},
			{
				"text": "I need ammo credits upfront. 40 should cover it.",
				"consequence": {
					"credits_immediate": 40,
					"reputation_change": {"zenith": -1},
					"combat_multiplier": 1.3,
					"reward_credits_multiplier": 1.2,
					"dialogue_response": "Fine, here's your advance, Shiny. The Reavers have been running heavier ships lately. Don't waste my investment."
				}
			},
			{
				"text": "Bounty hunting Reavers is dangerous. Pay up or find another gun.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"zenith": -3},
					"combat_multiplier": 1.6,
					"reward_credits_multiplier": 1.5,
					"dialogue_response": "You drive a hard bargain, Shiny. Contract bumped. But these Reavers are armed to the teeth. Your problem now."
				}
			}
		]
	},
	{
		"title": "Ghost Hunters",
		"faction": "vanguard",
		"agent_name": "Broker Kaelen",
		"dialogue": "Wraith raiders hit a Vanguard supply convoy last cycle, Shiny. Command is furious. They want 2 Wraith ships destroyed as a message. Fast work, decent pay. You in?",
		"objective": {
			"type": "KILL_SHIPS",
			"target_faction": "wraiths",
			"count_required": 2,
			"reward_credits": 200
		},
		"choices": [
			{
				"text": "Wraiths won't know what hit them. Let's go.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"vanguard": 4},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "That's the spirit, Shiny. Wraiths are slippery, so keep your sensors sharp."
				}
			},
			{
				"text": "Wraiths use jammers. I need 50 credits for countermeasures.",
				"consequence": {
					"credits_immediate": 50,
					"reputation_change": {"vanguard": -1},
					"combat_multiplier": 1.3,
					"reward_credits_multiplier": 1.2,
					"dialogue_response": "Smart, Shiny. Here's the advance. Those Wraith ships have been running tougher loadouts. Stay frosty."
				}
			},
			{
				"text": "Hunting ghosts isn't cheap. Double it.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"vanguard": -3},
					"combat_multiplier": 1.7,
					"reward_credits_multiplier": 1.6,
					"dialogue_response": "You've got nerve, Shiny. Payout adjusted. But Wraith command will send their elite interceptors after you. Don't say I didn't warn you."
				}
			}
		]
	},
	{
		"title": "Discreet Transport",
		"faction": "vanguard",
		"agent_name": "Broker Kaelen",
		"dialogue": "Listen carefully, Shiny. Vanguard needs a secure retrieval. Head over to Outpost Iron Reach and find Alaric Venn. He has a Sealed Data Drive. Bring it straight back to me, unopened. The pay is good, but the risk is high.",
		"objective": {
			"type": "PICKUP_SPECIAL",
			"target_outpost": "iron_reach",
			"target_outpost_display": "Outpost Iron Reach",
			"target_npc": "Alaric Venn",
			"part_name": "Sealed Data Drive",
			"destination": "Broker Kaelen",
			"reward_credits": 250
		},
		"choices": [
			{
				"text": "I'll fetch it. Simple enough.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"vanguard": 3},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "Good. Don't scratch it and don't open it."
				}
			},
			{
				"text": "Sounds shady. I want 50 credits up front.",
				"consequence": {
					"credits_immediate": 50,
					"reputation_change": {"vanguard": -1},
					"combat_multiplier": 1.3,
					"reward_credits_multiplier": 1.2,
					"dialogue_response": "You ask too many questions. Fine, take the advance, but keep your head on a swivel."
				}
			},
			{
				"text": "I want a bigger cut for the risk.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {"vanguard": -3},
					"combat_multiplier": 1.7,
					"reward_credits_multiplier": 1.6,
					"dialogue_response": "Greedy. Fine, Vanguard will pay. But don't expect them to be happy about it."
				}
			}
		]
	}
]

const CAMPAIGN_NAME_FALLBACKS: Array[String] = [
	"Cold Meridian",
	"Ember Passage",
	"Far Horizon",
	"Last Light",
	"Silent Dividend",
	"Wayward Star",
	"Iron Pilgrim",
	"Broken Compass",
]


func _sanitize_campaign_name(raw_name: String) -> String:
	var words := PackedStringArray()
	for raw_word in raw_name.strip_edges().split(" ", false):
		var clean_word := ""
		for character in raw_word:
			if character.to_lower() != character.to_upper() \
					or character in ["'", "-"]:
				clean_word += character
		if not clean_word.is_empty():
			words.append(clean_word.capitalize())
		if words.size() == 4:
			break
	if words.size() < 2:
		return ""
	return " ".join(words).substr(0, 48)


func _fallback_campaign_name() -> String:
	return CAMPAIGN_NAME_FALLBACKS[
		randi() % CAMPAIGN_NAME_FALLBACKS.size()
	]

# Random complications to vary prompts
var complications = [
	"A rival broker wants this cargo intercepted to sabotage my client's logistics.",
	"Zenith intelligence believes a double-agent has leaked shipping logs in the area.",
	"Aurelia pirates have set up a localized gravity snare. Expect heavier escorts.",
	"A logistics emergency has pushed resource demands to critical levels."
]

# Radio chatter pre-fetch cache
var chatter_cache = {
	"hostile_taunt": [],
	"death_cry": [],
	"system_alert": [],
	"industrial_banter": [],
	"kaelen_ore_sale": []
}

var generic_banter = {
	"hostile_taunt": [
		"Your shields won't save you, pilot!",
		"Hand over your cargo or prepare to be space dust!",
		"You picked the wrong sector to fly through!",
		"Threat locked. Engaging targets."
	],
	"death_cry": [
		"Engine core breaching! AAAARGH!",
		"Mayday, mayday! Ejection systems offline...",
		"Tell my crew... I almost made it...",
		"No! The reactor... it's going critical!"
	],
	"system_alert": [
		"SYSTEM ALERT: High-energy signatures detected nearby.",
		"SYSTEM ALERT: Localized gravity snare activated. Danger high.",
		"SYSTEM ALERT: Faction reinforcements are entering the grid.",
		"SYSTEM ALERT: Combat warning. Hostile interceptors incoming."
	],
	"industrial_banter": [
		"Scanning scrap pile. Looks like high-yield debris.",
		"Commencing salvage sweep. Keep those lasers focused.",
		"Another ship's misfortune is our bonus margin.",
		"Secure the perimeter, let's scrape this hull clean."
	],
	"kaelen_ore_sale": [
		"Yeah, I can move those for ya. Taking my cut, of course.",
		"I don't want to know where you got those. I don't care either, 'cause I get my cut either way.",
		"Ore's ore, Shiny. I've got a buyer lined up before you even finished docking. My percentage stands.",
		"Not bad haul. I'll fence it through my usual channels — minus my modest commission. And before you ask, no, it's not negotiable.",
		"You dig it up, I sell it off, we both walk away richer. Well, I walk away richer. You walk away less poor.",
	]
}

var active_fetches = {
	"hostile_taunt": false,
	"death_cry": false,
	"system_alert": false,
	"industrial_banter": false,
	"pickup_keywords": false,
	"kaelen_ore_sale": false
}

# Fallback Kaelen lines if LLM is offline or too slow
var fallback_completion_lines = [
	"Credits wired and brokerage fee deducted. Don't get comfortable, Shiny. There's always another contract.",
	"Clean work. My client is satisfied, which means I'm satisfied. Payout transferred.",
	"Done and dusted. That's how you earn a reputation in this sector, Shiny. Credits in your account.",
	"Good. My margins are intact and your account is padded. We both win. Come back soon.",
	"Contract fulfilled. You know, Shiny, you're starting to grow on me. Like a profitable parasite."
]

var fallback_abandon_lines = [
	"Contract dumped? You're costing me credit margins. I don't forget when people waste my time.",
	"Walking away? My client is furious and frankly, so am I. Come back when you've found your nerve.",
	"Abandoned. You know what that costs me in reputation? Considerably more than it costs you.",
	"Fine. I'll find someone else who actually finishes what they start. This goes in your file, Shiny.",
	"Contract voided. My brokerage fee is still owed. Consider that a lesson in commitment."
]

# TODO(llm-content): these Kaelen handoff lines are heavy with "Shiny" and are a
# prime future migration into llm_dialogue_content.json under a `kaelen_handoffs`
# section (see docs/plan_llm_dialogue_content_registry.md). Left in code for this
# slice — Shiny stays Kaelen-only, so this bucket must never be reused by a
# non-Kaelen speaker.
# Per-agent handoff lines Kaelen uses to introduce an upcoming quest giver.
# Used two ways:
#   1. Runtime fallback when the LLM is offline / slow / returns garbage.
#   2. Few-shot examples fed to the LLM when requesting a unique intro,
#      so a small model can pattern-match the voice, structure, and length.
# Keys must match the `agent_name` field on generated quests (Voss / Ryn / Dask / fallback).
var fallback_handoff_lines_by_agent: Dictionary = {
	"Director Voss": [
		"Hey Shiny, good timing. Director Voss from Zenith has been asking for a capable pilot. Sit tight — I'll get him.",
		"Shiny, a word. Zenith's Director Voss has something that needs doing quietly. Let me bring him over.",
		"You're in luck today, Shiny. Director Voss has a contract that actually pays well. Wait here — I'll fetch him.",
		"Zenith's been buzzing my comms all morning, Shiny. Director Voss has a job. Hold on while I get him.",
		"Director Voss wants a word, Shiny. He doesn't like to be kept waiting, so I'll get him now. Try to look competent.",
	],
	"Liaison Ryn": [
		"Shiny — keep it low key. Liaison Ryn from Aurelia has something off the books. Let me get her for you.",
		"Quiet down, Shiny. Aurelia's Ryn has a job that doesn't officially exist. Perfect for someone like you. I'll get her.",
		"Good news, Shiny. Liaison Ryn has work. The kind that pays and asks no questions. Hang on while I fetch her.",
		"Ryn's been waiting, Shiny. Aurelia doesn't like delays. I'll grab her — just act like you know what you're doing.",
		"Shiny, you've got Aurelia's attention. Liaison Ryn has a contract. Stay here, I'll bring her over.",
	],
	"Captain Dask": [
		"Hey Shiny, straighten up. Captain Dask from Vanguard has a mission and he doesn't do small talk. I'll get him.",
		"Shiny — Vanguard's Captain Dask is looking for a pilot with nerve. That might be you. Let me bring him in.",
		"Captain Dask has been waiting, Shiny. Vanguard work, military pace. Hold here while I get him.",
		"Look alive, Shiny. Captain Dask has a contract. He doesn't like excuses, so don't make any. I'll grab him.",
		"Shiny, Vanguard's on the line. Captain Dask has something that needs handling. Wait here — I'll bring him over.",
	],
	"DEFAULT": [
		"Hey Shiny, I've got a contact for you. Wait here while I get them.",
		"Shiny, someone wants a word. Sit tight — I'll grab them.",
		"I've got just the job for you, Shiny. Give me a second to get my contact.",
		"Someone's got work for a pilot of your... flexibility, Shiny. One moment.",
		"Shiny, stay put. I've got a contact who needs a job done. Bringing them over.",
	],
}

func _ready():
	randomize()
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.timeout = TIMEOUT_SECONDS
	http_request.request_completed.connect(_on_request_completed)

	_load_kaelen_intro_stats()
	_load_world_lore()
	if "--baseline-offline" in OS.get_cmdline_user_args():
		print("[LLMInterface] Baseline offline mode: Ollama watchdog disabled.")
		return
	_ollama_ping(func(up: bool):
		if up:
			print("[LLMInterface] Ollama is already running.")
			_ollama_after_up()
		else:
			push_warning("[LLMInterface] Ollama not responding — attempting to start it automatically.")
			_ollama_launch()
	)

# ── Ollama watchdog helpers ───────────────────────────────────────────────────

## Fire a single quick HTTP ping at the Ollama root. Calls callback(true/false).
func _ollama_ping(callback: Callable) -> void:
	var h := HTTPRequest.new()
	add_child(h)
	h.timeout = 3.0
	h.request_completed.connect(func(result, code, _hdrs, _body):
		h.queue_free()
		callback.call(result == HTTPRequest.RESULT_SUCCESS and code == 200)
	)
	var err := h.request(OLLAMA_HEALTH_URL, [], HTTPClient.METHOD_GET)
	if err != OK:
		h.queue_free()
		callback.call(false)

## Returns candidate exe paths in priority order: bundled → LOCALAPPDATA → none.
func _ollama_exe_candidates() -> Array[String]:
	var candidates: Array[String] = []
	# 1. Bundled alongside the game executable (for shipped builds).
	var game_dir := OS.get_executable_path().get_base_dir()
	candidates.append(game_dir.path_join("ollama/ollama.exe"))
	candidates.append(game_dir.path_join("ollama/ollama"))        # Linux / Mac
	# 2. User's standard Windows install location.
	var local_app := OS.get_environment("LOCALAPPDATA")
	if not local_app.is_empty():
		candidates.append(local_app.path_join("Programs/Ollama/ollama.exe"))
	# 3. Common macOS install path.
	candidates.append("/usr/local/bin/ollama")
	return candidates

## Try to launch `ollama serve` as a background process, then poll until ready.
func _ollama_launch() -> void:
	var pid: int = -1
	var launched_from := ""

	# Try bundled and known paths first before falling back to PATH.
	for candidate in _ollama_exe_candidates():
		if FileAccess.file_exists(candidate):
			pid = OS.create_process(candidate, ["serve"])
			if pid > 0:
				launched_from = candidate
				break

	# Fall back to PATH ("ollama" command) in case it's installed system-wide.
	if pid <= 0:
		pid = OS.create_process("ollama", ["serve"])
		if pid > 0:
			launched_from = "ollama (PATH)"

	if pid > 0:
		_ollama_start_pid = pid
		print("[LLMInterface] Launched Ollama from '%s' (PID %d) — polling for readiness..." % [launched_from, pid])
	else:
		push_warning("[LLMInterface] Could not launch Ollama from any known path. Is it installed? Will still poll in case it starts.")

	_ollama_poll_count = 0
	_ollama_poll()

## Poll Ollama every 2s until it answers or we hit the max attempt cap.
func _ollama_poll() -> void:
	_ollama_poll_count += 1
	_ollama_ping(func(up: bool):
		if up:
			print("[LLMInterface] Ollama responded after %d poll(s)." % _ollama_poll_count)
			_ollama_after_up()
			return
		if _ollama_poll_count >= _OLLAMA_MAX_POLLS:
			push_warning("[LLMInterface] CRITICAL: Ollama did not respond after %ds. All LLM features will use canned fallbacks." % int(_OLLAMA_MAX_POLLS * _OLLAMA_POLL_INTERVAL))
			return
		get_tree().create_timer(_OLLAMA_POLL_INTERVAL, true, false, true).timeout.connect(
			func(): _ollama_poll())
	)

## Called once Ollama is confirmed up. Checks that required models are present,
## pulling them if not, then marks the interface ready and starts model discovery.
func _ollama_after_up() -> void:
	_ollama_ready = true
	_ollama_ensure_models([LocalModelGatewayType.DEFAULT_SMALL_MODEL,
		LocalModelGatewayType.DEFAULT_LARGE_MODEL], func():
		_discover_ollama_model()
	)

## Checks /api/tags; for any model in `required` not already present, pulls it.
## Fires `on_done` once all models are confirmed available (or pull succeeded).
func _ollama_ensure_models(required: Array, on_done: Callable) -> void:
	var h := HTTPRequest.new()
	add_child(h)
	h.timeout = 5.0
	h.request_completed.connect(func(result, code, _hdrs, body):
		h.queue_free()
		var installed: Array = []
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var parsed = JSON.parse_string(body.get_string_from_utf8())
			if parsed is Dictionary and parsed.has("models"):
				for m in parsed["models"]:
					installed.append(str(m.get("name", "")))

		# Find which required models are missing.
		var missing: Array = []
		for req in required:
			var found := false
			for inst in installed:
				# Ollama may append ":latest" — treat "model" == "model:latest".
				if inst == req or inst == req + ":latest" or req == inst + ":latest":
					found = true
					break
			if not found:
				missing.append(req)

		if missing.is_empty():
			print("[LLMInterface] All required models present: %s" % str(required))
			on_done.call()
			return

		print("[LLMInterface] Missing models: %s — pulling now (this may take a few minutes on first run)..." % str(missing))
		_ollama_pull_next(missing, 0, on_done)
	)
	var err := h.request(LocalModelGatewayType.OLLAMA_TAGS_URL, [], HTTPClient.METHOD_GET)
	if err != OK:
		h.queue_free()
		push_warning("[LLMInterface] Could not check installed models — proceeding anyway.")
		on_done.call()

## Pulls models from `list` one at a time starting at `idx`, then fires `on_done`.
func _ollama_pull_next(list: Array, idx: int, on_done: Callable) -> void:
	if idx >= list.size():
		on_done.call()
		return
	var model: String = list[idx]
	print("[LLMInterface] Pulling model '%s'..." % model)
	var h := HTTPRequest.new()
	add_child(h)
	h.timeout = 600.0  # pulls can take a long time on first install
	h.download_chunk_size = 65536
	h.request_completed.connect(func(result, code, _hdrs, _body):
		h.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			print("[LLMInterface] Model '%s' pulled successfully." % model)
		else:
			push_warning("[LLMInterface] Pull of '%s' may have failed (result=%d code=%d) — will try to continue." % [model, result, code])
		_ollama_pull_next(list, idx + 1, on_done)
	)
	var payload := JSON.stringify({"name": model, "stream": false})
	var err := h.request("http://127.0.0.1:11434/api/pull",
		["Content-Type: application/json"], HTTPClient.METHOD_POST, payload)
	if err != OK:
		h.queue_free()
		push_warning("[LLMInterface] Could not send pull request for '%s'." % model)
		_ollama_pull_next(list, idx + 1, on_done)

func _load_world_lore():
	var lore_path = "res://docs/world_lore.md"
	if not FileAccess.file_exists(lore_path):
		print("[LLMInterface] No world lore file found at %s — quests will generate without lore context." % lore_path)
		return
	var file = FileAccess.open(lore_path, FileAccess.READ)
	if file == null:
		print("[LLMInterface] Failed to open world lore file: %s" % lore_path)
		return
	var raw = file.get_as_text()
	file.close()
	
	# Strip HTML comments (the budget guide block) so they don't waste tokens
	var cleaned = ""
	var in_comment = false
	var idx = 0
	while idx < raw.length():
		if not in_comment and idx + 3 < raw.length() and raw.substr(idx, 4) == "<!--":
			in_comment = true
			idx += 4
			continue
		if in_comment and idx + 2 < raw.length() and raw.substr(idx, 3) == "-->":
			in_comment = false
			idx += 3
			continue
		if not in_comment:
			cleaned += raw[idx]
		idx += 1
	
	# Strip markdown formatting (headers, bullets, bold) to save tokens
	var lines = cleaned.split("\n")
	var stripped_lines = []
	for line in lines:
		var s = line.strip_edges()
		if s == "" or s == "---":
			continue
		# Remove markdown header prefixes
		while s.begins_with("#"):
			s = s.substr(1)
		s = s.strip_edges()
		# Remove leading bullet
		if s.begins_with("- "):
			s = s.substr(2)
		# Remove bold markers
		s = s.replace("**", "")
		if s != "":
			stripped_lines.append(s)
	
	world_lore_text = "\n".join(stripped_lines)
	
	# Word count warning
	var word_count = world_lore_text.split(" ", false).size()
	print("[LLMInterface] World lore loaded: %d words (~%d tokens)." % [word_count, int(word_count * 1.4)])
	if word_count > 800:
		print("[LLMInterface] ⚠ WARNING: Lore exceeds 800 words. This WILL cause issues with small models (1.5b-3b). Consider trimming docs/world_lore.md.")
	elif word_count > 500:
		print("[LLMInterface] ⚠ CAUTION: Lore is %d words. May slow down small models (1.5b-3b). Fine for 8b+ models." % word_count)

func reset_for_restart():
	# Clear the active callback FIRST — this is the one that crashes if it fires
	# into a freed UIManager node after reload_current_scene()
	active_callback = Callable()
	is_waiting = false
	# Cancel any in-flight main request so the old response is ignored on arrival
	if http_request and is_instance_valid(http_request):
		http_request.cancel_request()
	for request in _quest_candidate_requests:
		if request and is_instance_valid(request):
			request.cancel_request()
			request.queue_free()
	_quest_candidate_requests.clear()
	_quest_candidate_results.clear()
	_quest_candidate_attempts_started = 0
	# Clear chatter caches — new session should generate fresh contextual lines
	for key in chatter_cache:
		chatter_cache[key].clear()
	for key in active_fetches:
		active_fetches[key] = false
	GlobalState.trace("[LLMInterface] State reset for new game.")



func _discover_ollama_model():
	connection_attempts += 1
	llm_connection_attempt.emit(connection_attempts)
	GlobalState.trace("[TRACE] [LLMInterface] Discovering Ollama models (attempt %d)..." % connection_attempts)
	
	var tags_http = HTTPRequest.new()
	add_child(tags_http)
	tags_http.timeout = 2.0
	tags_http.request_completed.connect(func(result, response_code, headers, body):
		tags_http.queue_free()
		var success = false
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var data = json.get_data()
				if data is Dictionary and data.has("models"):
					var models = data["models"]
					var installed_names = []
					for m in models:
						if m is Dictionary and m.has("name"):
							installed_names.append(m["name"])
							
					GlobalState.trace("[TRACE] [LLMInterface] Installed Ollama models: " + str(installed_names))
					
					var chosen_model: String = LocalModelGatewayType.select_installed_model(
						installed_names,
						"quest_dialogue"
					)
					var chosen_large_model: String = LocalModelGatewayType.select_installed_model(
						installed_names,
						"campaign_bible"
					)
							
					if chosen_model != "":
						active_model_name = chosen_model
						GlobalState.trace("[TRACE] [LLMInterface] Dynamic Ollama model selection: USING '" + active_model_name + "'")
					else:
						print("[LLMInterface] No models found in Ollama tags. Defaulting to: " + active_model_name)
					if chosen_large_model != "":
						active_large_model_name = chosen_large_model
						GlobalState.trace("[TRACE] [LLMInterface] Large-story model profile: USING '" + active_large_model_name + "'")
					
					success = true
					
		if success:
			GlobalState.trace("[TRACE] [LLMInterface] Ollama connection successfully verified.")
			llm_connected = true
			llm_connection_established.emit(active_model_name)
			model_discovered.emit(active_model_name)
			# Force-load the models into VRAM now, before the first dock asks for a
			# line. Cold weight-loading was the dominant session-start fallback cause
			# (timeouts clustered in the first ~50s). Chatter pre-warm is sequenced
			# to run once the small model is actually resident.
			GlobalState.trace("[TRACE] [LLMInterface] Warming models + chatter caches...")
			_ollama_warm_models()
		else:
			print("[LLMInterface] Connection to Ollama failed (attempt %d). Retrying in 1.5s..." % connection_attempts)
			get_tree().create_timer(1.5).timeout.connect(_discover_ollama_model)
	)
	
	var err = tags_http.request(LocalModelGatewayType.OLLAMA_TAGS_URL)
	if err != OK:
		tags_http.queue_free()
		print("[LLMInterface] Failed to initiate tags check. Retrying in 1.5s...")
		get_tree().create_timer(1.5).timeout.connect(_discover_ollama_model)


## Force-load the SMALL dialogue model into memory right after discovery, before
## the first dock asks for a line. Cold weight-loading is the dominant session-start
## fallback cause (see logs/fallback_summary.txt: every startup timeout was the small
## model, clustered in the first ~50s). Once it is resident we kick off chatter
## pre-warm. Guarded so a reconnect does not warm twice.
##
## The large story model is intentionally NOT pre-warmed: its only logged failure
## was a JSON parse (a quality issue, not a cold-load timeout), its callers use long
## 60s timeouts that absorb a cold load, and pinning a 12B in VRAM at startup could
## evict the small model that gameplay needs constantly. keep_alive still keeps it
## resident once it loads on first use.
func _ollama_warm_models() -> void:
	if _models_warm_started:
		return
	_models_warm_started = true
	_warm_single_model(active_model_name, "small", func() -> void:
		for chatter_type in chatter_cache.keys():
			fetch_chatter_background(chatter_type)
	)


## Ask Ollama to load one model into VRAM without generating (empty prompt) and
## keep it resident (keep_alive). Fire-and-forget: on completion it logs a
## model_warmup diagnostics event and calls on_done. A cold 12B load can be slow,
## so the timeout is generous.
func _warm_single_model(model_name: String, label: String, on_done: Callable) -> void:
	if model_name.strip_edges().is_empty():
		on_done.call()
		return
	var started := Time.get_ticks_msec()
	var h := HTTPRequest.new()
	add_child(h)
	h.timeout = 90.0
	h.request_completed.connect(func(result: int, code: int, _hdrs: PackedStringArray, _body: PackedByteArray) -> void:
		h.queue_free()
		var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			print("[LLMInterface] Warmed %s model '%s' in %.1fs." % [label, model_name, elapsed])
			GenerationDiagnostics.record_event(
				"model_warmup", "loaded", "LLMInterface",
				{"model": model_name, "profile": label, "elapsed_seconds": elapsed}
			)
		else:
			push_warning("[LLMInterface] Warm-up of %s model '%s' failed (result=%d code=%d, %.1fs)." % [label, model_name, result, code, elapsed])
			GenerationDiagnostics.record_event(
				"model_warmup", "failed_result_%d_code_%d" % [result, code], "LLMInterface",
				{"model": model_name, "profile": label, "elapsed_seconds": elapsed}
			)
		on_done.call()
	)
	var payload := JSON.stringify({
		"model": model_name,
		"keep_alive": LocalModelGatewayType.MODEL_KEEP_ALIVE,
	})
	var err := h.request(OLLAMA_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, payload)
	if err != OK:
		h.queue_free()
		push_warning("[LLMInterface] Could not start warm-up for %s model '%s'." % [label, model_name])
		on_done.call()


func model_for_capability(capability: String) -> String:
	return LocalModelGatewayType.model_for_capability(
		capability,
		active_model_name,
		active_large_model_name
	)


func request_timeout_for_capability(capability: String) -> float:
	return LocalModelGatewayType.request_timeout(capability)


func ollama_generate_url() -> String:
	return LocalModelGatewayType.OLLAMA_GENERATE_URL


func build_generation_body(
	capability: String,
	prompt: String,
	response_format: String = "json",
	options: Dictionary = {}
) -> Dictionary:
	return LocalModelGatewayType.generation_body(
		capability,
		prompt,
		active_model_name,
		response_format,
		options,
		active_large_model_name
	)


func diagnostics_context_for_capability(capability: String) -> Dictionary:
	return LocalModelGatewayType.diagnostics_context(
		capability,
		model_for_capability(capability)
	)


func request_lounge_chatter(
	context: Dictionary,
	fallback_line: String,
	callback: Callable
) -> void:
	var speaker := str(context.get("speaker", "Local Contact")).strip_edges()
	var role := str(context.get("role", "station regular")).strip_edges()
	var mood := str(context.get("mood", "neutral")).strip_edges()
	var station := str(context.get("station", "the station lounge")).strip_edges()
	var system_name := str(context.get("system", "this system")).strip_edges()
	var faction := str(context.get("faction", "independent")).strip_edges()
	var extra := str(context.get("extra", "")).strip_edges()
	var prompt := (
		"You are writing one ambient lounge line for a space trading game.\n"
		+ "Speaker: %s\nRole: %s\nMood: %s\nFaction/affiliation: %s\n"
		+ "Location: %s in %s\nExtra context: %s\n\n"
		+ "Write exactly ONE short in-character line the speaker says to the pilot. "
		+ "It can be useful, atmospheric, teasing, guarded, or even a polite refusal "
		+ "like not being in the mood to talk. Do not narrate. Do not include the "
		+ "speaker name. Keep it under 24 words. Output only valid JSON: "
		+ "{\"line\":\"...\"}"
	) % [speaker, role, mood, faction, station, system_name, extra]

	# Every lounge fallback is logged (no silent canned lines). Reason codes let us
	# see whether these are environment (http/timeout) or quality (parse/shape) fails.
	var fallback_context := {"speaker": speaker, "role": role, "faction": faction, "station": station}
	var report_fallback := func(reason: String) -> void:
		GenerationDiagnostics.record_fallback("lounge_chatter", reason, "LLMInterface", fallback_context)
		callback.call(fallback_line)

	var temp_http := HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability("kaelen_line")
	temp_http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			temp_http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
				report_fallback.call("http_failed_result_%d_code_%d" % [result, response_code])
				return
			var response_text := body.get_string_from_utf8()
			var outer := JSON.new()
			if outer.parse(response_text) != OK:
				report_fallback.call("outer_parse_failed")
				return
			var outer_data = outer.get_data()
			if not outer_data is Dictionary or not outer_data.has("response"):
				report_fallback.call("missing_response_field")
				return
			var inner_json_str := str(outer_data["response"]).strip_edges()
			if inner_json_str.begins_with("```"):
				var end_idx := inner_json_str.find("\n", 3)
				if end_idx != -1:
					inner_json_str = inner_json_str.substr(end_idx + 1)
				if inner_json_str.ends_with("```"):
					inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
				inner_json_str = inner_json_str.strip_edges()
			var inner := JSON.new()
			if inner.parse(inner_json_str) != OK:
				report_fallback.call("inner_parse_failed")
				return
			var data = inner.get_data()
			if not data is Dictionary or not data.has("line"):
				report_fallback.call("missing_line_field")
				return
			var line := str(data["line"]).strip_edges()
			if line.length() < 4 or line.length() > 220:
				report_fallback.call("line_length_rejected")
				return
			callback.call(line)
	)

	var payload := build_generation_body(
		"kaelen_line",
		prompt,
		"json",
		{
			"temperature": 0.88,
			"num_predict": 90,
			"seed": randi(),
		}
	)
	var err := temp_http.request(
		OLLAMA_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		temp_http.queue_free()
		report_fallback.call("request_start_failed")


func request_campaign_bible_generation(
	baseline_bible: Dictionary,
	idea_memory_context: String,
	callback: Callable
) -> void:
	var capability := "campaign_bible"
	var model_name := model_for_capability(capability)
	if OLLAMA_URL.is_empty() or model_name.strip_edges().is_empty():
		GenerationDiagnostics.record_event(
			"campaign_bible",
			"model_unavailable",
			"llm_interface",
			{"model": model_name, "capability": capability}
		)
		callback.call({
			"ok": false,
			"reason": "model_unavailable",
			"model": model_name,
		})
		return
	var prompt := NarrativeDirectorType.build_campaign_bible_prompt(
		baseline_bible,
		idea_memory_context
	)
	var payload := build_generation_body(
		capability,
		prompt,
		"json",
		{
			"temperature": 0.85,
			"num_predict": 1800,
			"seed": randi(),
		}
	)
	var temp_http := HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability(capability)
	var request_id := temp_http.get_instance_id()
	temp_http.request_completed.connect(
		func(
			result: int,
			response_code: int,
			_headers: PackedStringArray,
			body: PackedByteArray
		) -> void:
			_on_campaign_bible_generation_completed(
				result,
				response_code,
				body,
				baseline_bible,
				model_name,
				callback,
				request_id
			)
	)
	var err := temp_http.request(
		OLLAMA_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		temp_http.queue_free()
		GenerationDiagnostics.record_event(
			"campaign_bible",
			"request_start_failed",
			"llm_interface",
			{"model": model_name, "error": err}
		)
		callback.call({
			"ok": false,
			"reason": "request_start_failed",
			"model": model_name,
			"error": err,
		})


func _on_campaign_bible_generation_completed(
	result: int,
	response_code: int,
	body: PackedByteArray,
	baseline_bible: Dictionary,
	model_name: String,
	callback: Callable,
	request_id: int
) -> void:
	var temp_http := instance_from_id(request_id) as HTTPRequest
	if temp_http != null and is_instance_valid(temp_http):
		temp_http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var reason := "http_failed_result_%d_code_%d" % [result, response_code]
		if response_code == 0 or response_code == 404:
			reason = "model_unavailable"
		GenerationDiagnostics.record_event(
			"campaign_bible",
			reason,
			"llm_interface",
			{"model": model_name}
		)
		callback.call({
			"ok": false,
			"reason": reason,
			"model": model_name,
		})
		return
	var parsed := NarrativeDirectorType.parse_campaign_bible_response(
		body.get_string_from_utf8(),
		baseline_bible,
		model_name
	)
	if not bool(parsed.get("ok", false)):
		GenerationDiagnostics.record_event(
			"campaign_bible",
			str(parsed.get("reason", "parse_failed")),
			"llm_interface",
			{"model": model_name}
		)
		parsed["model"] = model_name
		callback.call(parsed)
		return
	GenerationDiagnostics.record_content_source(
		"campaign_bible",
		"llm",
		"llm_interface",
		{"model": model_name, "capability": "campaign_bible"}
	)
	callback.call(parsed)


func _get_type_examples(agent_key: String, mission_type: String) -> Dictionary:
	# Few-shot quest examples now live in data/content/llm_dialogue_content.json
	# (quest_generation.mission_types[TYPE].examples_by_agent). Edit dialogue
	# phrasing there, not here. This wrapper reads the JSON via the content
	# registry and only falls back to the built-in block below if that file is
	# missing/malformed — the prompt must always have at least one example, or
	# the random example picker in request_quest_generation would divide by zero.
	var bundle := LLMDialogueContentRegistry.shared().quest_examples(agent_key, mission_type)
	if not bundle.is_empty() and bundle.get("dialogues", []).size() > 0:
		return bundle
	# The JSON content file is missing/malformed for this bucket — we're about to
	# run on the built-in copy. That is a silent quality regression, so log it.
	GenerationDiagnostics.record_fallback(
		"quest_examples",
		"content_file_missing",
		"LLMInterface",
		{"agent": agent_key, "type": mission_type}
	)
	return _get_type_examples_fallback(agent_key, mission_type)


func _get_type_examples_fallback(agent_key: String, mission_type: String) -> Dictionary:
	# Safety net only — the live/editable copy is the JSON above. Kept verbatim so
	# behavior is unchanged if the content file cannot be loaded.
	# Returns 5 example dialogues + 3 choice responses matched to the mission type.
	# All use dummy names: George (pilot), Slithern (enemy), 3 (kill count),
	# 25 (ore amount), Sable Mercer / Morrow Station / Sealed Data Drive (pickup).
	var d: Dictionary = {}
	match agent_key:
		"zenith":
			match mission_type:
				"KILL_SHIPS":
					d["dialogues"] = [
						"Resource allocation in Sector 7 has become critically inefficient, George. 3 Slithern ships are disrupting our supply corridor. Eliminate them.",
						"Slithern operatives have compromised a logistics node, George. 3 hostiles confirmed. Remove them before throughput drops further.",
						"Unauthorized Slithern vessels detected in our acquisition zone, George. 3 contacts on scope. Purge the interference.",
						"A Slithern raiding cell has established a forward position, George. 3 ships. Dismantle them before they disrupt scheduled operations.",
						"Slithern interdiction is costing Zenith 14% throughput, George. 3 vessels. Resolve this inefficiency permanently.",
					]
					d["response_1"] = "Confirmed, George. Your assignment is logged. Do not deviate from the directive."
					d["response_2"] = "An advance against operational expenses. Noted. Expect elevated patrol resistance on your route, George."
					d["response_3"] = "Bold negotiation, George. Payout is revised upward. Security escalation protocols are now active in your sector."
				"DELIVER_ORE":
					d["dialogues"] = [
						"Zenith requires 25 m³ of ore routed to this station, George. Extraction quotas are non-negotiable. Deliver promptly.",
						"Our fabrication queue is stalled pending raw material, George. 25 m³ of ore. Acquire and deliver without delay.",
						"A resource deficit has been flagged, George. 25 m³ of ore must reach this station before the next cycle closes.",
						"Mining output in the outer ring has underperformed, George. Compensate with 25 m³ of ore delivered here.",
						"Production schedules depend on timely inputs, George. 25 m³ of ore. Secure it and return. No excuses.",
					]
					d["response_1"] = "Acknowledged, George. Delivery window is logged. Do not fall behind schedule."
					d["response_2"] = "An advance for fuel costs. Logged, George. Expect contested mining lanes on approach."
					d["response_3"] = "Revised upward, George. The ore must still arrive on time. Zenith does not pay for delays."
				"PICKUP_SPECIAL":
					d["dialogues"] = [
						"A Sealed Data Drive is waiting at Morrow Station with Sable Mercer, George. Retrieve it and return here. Discretion is mandatory.",
						"Zenith has arranged a retrieval from Sable Mercer at Morrow Station, George. One Sealed Data Drive. Handle it with operational security.",
						"An asset transfer has been staged at Morrow Station, George. Contact Sable Mercer, collect the Sealed Data Drive, deliver it here.",
						"Sable Mercer at Morrow Station is holding a Sealed Data Drive for Zenith, George. Retrieve it before the transfer window expires.",
						"A classified pickup requires your involvement, George. Sable Mercer, Morrow Station, Sealed Data Drive. Return it to this station intact.",
					]
					d["response_1"] = "Logged, George. Maintain operational security throughout the retrieval."
					d["response_2"] = "Advance approved for transit expenses, George. The item must arrive undamaged."
					d["response_3"] = "Payout revised, George. Do not draw attention during the pickup. Zenith values discretion."
		"aurelia":
			match mission_type:
				"KILL_SHIPS":
					d["dialogues"] = [
						"Got a little opportunity, George. 3 Slithern ships rattling cages near our trade lane. Remove them quietly and credits flow.",
						"Slithern crew is making noise near one of my routes, George. 3 ships. Make them disappear — clean, quiet, off the books.",
						"Some Slithern hotheads are scaring off my couriers, George. 3 of them. Clear the lane and nobody has to know.",
						"There's a Slithern problem blocking a very lucrative corridor, George. 3 ships. Handle it discreetly and the payout is yours.",
						"Word is 3 Slithern ships are camping a junction I need open, George. Quiet removal. No witnesses, no paperwork.",
					]
					d["response_1"] = "Smooth, George. That's why I like working with you. Stay off their sensors."
					d["response_2"] = "An advance? Smart move, George. Credits transferred. Riskier corridor to offset the cost."
					d["response_3"] = "Playing hardball? I respect the hustle, George. Payout bumped. But rivals will be watching."
				"DELIVER_ORE":
					d["dialogues"] = [
						"I've got a buyer who needs 25 m³ of ore off the books, George. Deliver it here and my cut stays quiet.",
						"There's a quiet deal on the table, George. 25 m³ of ore, delivered to this station. No manifests, no questions.",
						"A client of mine is short 25 m³ of ore, George. Bring it in clean and the credits are yours. I take my slice.",
						"Opportunity knocking, George. 25 m³ of ore delivered here pays very nicely. I'll handle the paperwork — or lack of it.",
						"Need 25 m³ of ore moved to this dock, George. My buyer is impatient and pays well for discretion.",
					]
					d["response_1"] = "Perfect, George. Deliver it clean and we both walk away richer."
					d["response_2"] = "Advance wired, George. Mining lanes are contested lately — watch your back out there."
					d["response_3"] = "Fine, George, payout bumped. But the ore had better arrive on time. My buyer doesn't do extensions."
				"PICKUP_SPECIAL":
					d["dialogues"] = [
						"Got a quiet job, George. Sable Mercer at Morrow Station has a Sealed Data Drive. Pick it up and bring it back here — no questions asked.",
						"There's a package at Morrow Station, George. Sable Mercer is holding a Sealed Data Drive for me. Fetch it discreetly.",
						"Need a courier I can trust, George. Sable Mercer, Morrow Station, Sealed Data Drive. Bring it here and forget you ever saw it.",
						"A contact of mine — Sable Mercer, Morrow Station — has a Sealed Data Drive that needs moving, George. Clean pickup, clean delivery.",
						"Simple retrieval, George. Sable Mercer at Morrow Station. One Sealed Data Drive. Bring it to me and the credits are yours.",
					]
					d["response_1"] = "Smooth, George. Quick pickup, no complications. That's how I like it."
					d["response_2"] = "Advance wired, George. Don't let Sable Mercer give you the runaround."
					d["response_3"] = "Bumped the payout, George. The drive better be intact when it gets here."
		"vanguard":
			match mission_type:
				"KILL_SHIPS":
					d["dialogues"] = [
						"Slithern hostiles spiking in the outer lanes, George. 3 contacts. Clear the zone before they dig in. No theatrics.",
						"ROE is simple, George. 3 Slithern ships, hostile posture, outer perimeter. Engage and neutralize. Boots on hull if needed.",
						"We've got 3 Slithern vessels breaching the buffer zone, George. Weapons hot. Clear them out before command notices.",
						"Slithern incursion confirmed, George. 3 ships. Vanguard needs that lane secured yesterday. Move.",
						"Intel flagged 3 Slithern raiders staging near our corridor, George. Intercept and destroy. No half-measures.",
					]
					d["response_1"] = "Copy that, George. ROE is clear: engage and eliminate. Don't make it complicated."
					d["response_2"] = "You want an advance, George? Fine. Threat level is escalated. Don't embarrass us."
					d["response_3"] = "Renegotiating under fire, George. Bold. Payout adjusted. Don't expect us to soften the zone."
				"DELIVER_ORE":
					d["dialogues"] = [
						"Vanguard supply chain is running dry, George. 25 m³ of ore, delivered to this station. No delays.",
						"Logistics flagged a deficit, George. We need 25 m³ of ore here before the next rotation. Get it done.",
						"Our forward base needs raw material, George. 25 m³ of ore. Mine it, haul it, deliver it. Standard resupply.",
						"Supply requisition, George. 25 m³ of ore to this station. The fabricators don't run on goodwill.",
						"Material shortfall on the books, George. 25 m³ of ore. Secure a source and bring it back. Clock's ticking.",
					]
					d["response_1"] = "Acknowledged, George. Delivery is expected on schedule. Don't waste time out there."
					d["response_2"] = "Advance approved, George. Mining sectors are contested — stay sharp."
					d["response_3"] = "Payout adjusted, George. The ore still needs to arrive. No excuses."
				"PICKUP_SPECIAL":
					d["dialogues"] = [
						"We have a retrieval op, George. Sable Mercer at Morrow Station is holding a Sealed Data Drive. Secure it and bring it back.",
						"Classified pickup, George. Contact Sable Mercer at Morrow Station. One Sealed Data Drive. Return it to this station. No detours.",
						"Vanguard needs a Sealed Data Drive retrieved from Morrow Station, George. Sable Mercer has it. In and out, no complications.",
						"Asset recovery tasking, George. Sable Mercer, Morrow Station, Sealed Data Drive. Get it here before the window closes.",
						"Field retrieval, George. Sable Mercer is the contact at Morrow Station. One Sealed Data Drive. Standard chain-of-custody applies.",
					]
					d["response_1"] = "Acknowledged, George. Retrieve the item and return without incident."
					d["response_2"] = "Advance cleared, George. Don't let the pickup drag. Time is a factor."
					d["response_3"] = "Payout bumped, George. The drive is priority cargo. Treat it accordingly."
		_:
			match mission_type:
				"KILL_SHIPS":
					d["dialogues"] = [
						"Got a contract that needs muscle, George. 3 Slithern ships making trouble near the station. My cut's already factored in.",
						"Client wants 3 Slithern ships gone, George. Paying well. I've already skimmed my broker's fee off the top.",
						"Slithern crew is disrupting a lane my best clients use, George. 3 ships. Handle it and we both profit.",
						"Three Slithern ships, George. My client wants them scrapped. The payout covers your fuel and my lifestyle.",
						"Picked up a bounty contract, George. 3 Slithern vessels harassing local traffic. My cut's baked in — yours is what's left.",
					]
					d["response_1"] = "Excellent, George. My client is watching the clock, so don't waste my time."
					d["response_2"] = "Taking a bite out of my margins, George? Fine. Credits wired. Contested lane ahead though."
					d["response_3"] = "Hustling a hustler? I respect the nerve, George. Payout bumped. But enemies will be expecting you."
				"DELIVER_ORE":
					d["dialogues"] = [
						"Got a buyer lined up for 25 m³ of ore, George. Deliver it here and I'll make sure we both get paid. My cut's already in the price.",
						"There's a standing order for 25 m³ of ore at this station, George. Easy money — if you can haul it. I take my percentage.",
						"A client needs 25 m³ of ore and they're paying above market, George. Bring it in and my broker's fee handles itself.",
						"Ore run, George. 25 m³ delivered to this dock. Simple job, decent payout, and I skim my usual slice.",
						"I've got a deal that practically prints credits, George. 25 m³ of ore, delivered here. My cut's already factored — yours is the rest.",
					]
					d["response_1"] = "Smart move, George. Deliver it clean and we both walk away happy. My margins depend on you."
					d["response_2"] = "Advance? Fine, George. Credits wired. Mining lanes are rough lately — don't lose my investment out there."
					d["response_3"] = "Pushing for more, George? Payout bumped. But the ore better show up. My reputation rides on delivery."
				"PICKUP_SPECIAL":
					d["dialogues"] = [
						"Got a pickup job, George. Sable Mercer at Morrow Station has a Sealed Data Drive. Bring it to me and I'll handle the rest. My fee's included.",
						"Courier work, George. Sable Mercer at Morrow Station is sitting on a Sealed Data Drive my client wants. Fetch it and the credits flow.",
						"Simple retrieval, George. Morrow Station, contact named Sable Mercer, one Sealed Data Drive. Bring it here — my cut's already baked in.",
						"A client wants a Sealed Data Drive moved from Morrow Station, George. Sable Mercer has it. Quick grab, quick payout, and I take my slice.",
						"Need your legs for this one, George. Sable Mercer, Morrow Station, Sealed Data Drive. Deliver it to me and everybody profits.",
					]
					d["response_1"] = "Perfect, George. Quick and clean — that's how I like my couriers. Don't keep Sable Mercer waiting."
					d["response_2"] = "Advance wired, George. Don't let the pickup get complicated — complications eat into my margins."
					d["response_3"] = "Bumped the payout, George. The drive better arrive in one piece. My client doesn't accept excuses and neither do I."
	return d


func agent_memory_id_for_profile(
	agent_name: String,
	faction: String,
	agent_profile: Dictionary = {}
) -> String:
	var profile_id := str(agent_profile.get("agent_id", "")).strip_edges()
	if not profile_id.is_empty():
		return profile_id
	var clean_faction := str(faction).strip_edges().to_lower()
	if clean_faction.is_empty():
		clean_faction = "neutral"
	return "agent.fixed.%s.%s" % [
		_agent_memory_slug(clean_faction),
		_agent_memory_slug(agent_name),
	]


func _agent_memory_prompt_block(agent_id: String) -> String:
	var context := (
		"No prior contracts with this agent are recorded yet. "
		+ "Treat the relationship as first-contact or strictly professional."
	)
	if GlobalState.campaign_agent_memory_store != null \
			and GlobalState.campaign_agent_memory_store.has_method("prompt_context"):
		context = str(GlobalState.campaign_agent_memory_store.prompt_context(agent_id))
	return "### AGENT MEMORY:\n%s\n\n" % context


func _agent_system_story_pack(agent_profile: Dictionary) -> Dictionary:
	var raw_pack: Variant = agent_profile.get("system_story_pack", {})
	if raw_pack is Dictionary:
		return (raw_pack as Dictionary).duplicate(true)
	return {}


func _system_story_pack_prompt_block(story_pack: Dictionary) -> String:
	if story_pack.is_empty():
		return ""
	var lines: Array[String] = []
	var system_name := str(story_pack.get("system_name", "")).strip_edges()
	var station_problem := str(
		story_pack.get("station_economy_problem", "")
	).strip_edges()
	var active_tension := str(story_pack.get("active_tension", "")).strip_edges()
	var danger_summary := str(story_pack.get("danger_summary", "")).strip_edges()
	var resource_hook := str(story_pack.get("resource_hook", "")).strip_edges()
	var humor_guidance := str(story_pack.get("humor_guidance", "")).strip_edges()
	if not system_name.is_empty():
		lines.append("- System identity: " + system_name)
	if not station_problem.is_empty():
		lines.append("- Local station problem: " + station_problem)
	if not active_tension.is_empty():
		lines.append("- Current faction tension: " + active_tension)
	if not danger_summary.is_empty():
		lines.append("- Current danger: " + danger_summary)
	if not resource_hook.is_empty():
		lines.append("- Resource hook: " + resource_hook)
	var mission_seeds: Array = story_pack.get("mission_seeds", [])
	if not mission_seeds.is_empty():
		var seed_lines: Array[String] = []
		for seed in mission_seeds:
			var seed_text := str(seed).strip_edges()
			if not seed_text.is_empty():
				seed_lines.append(seed_text)
		if not seed_lines.is_empty():
			lines.append("- Local mission seeds: " + "; ".join(seed_lines))
	if not humor_guidance.is_empty():
		lines.append("- Local humor guidance: " + humor_guidance)
	if lines.is_empty():
		return ""
	return (
		"### CURRENT SYSTEM STORY PACK:\n"
		+ "Use this local context to make the contract feel native to this system. "
		+ "Do not invent a different system conflict unless the objective requires it.\n"
		+ "\n".join(lines)
		+ "\n\n"
	)


func _agent_memory_slug(text: String) -> String:
	var lower := text.strip_edges().to_lower()
	var output := ""
	for i in range(lower.length()):
		var ch := lower.substr(i, 1)
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			output += ch
		elif not output.ends_with("_"):
			output += "_"
	output = output.strip_edges().trim_prefix("_").trim_suffix("_")
	if output.is_empty():
		return "unknown"
	return output


func register_quest_fingerprint(source: String) -> void:
	if source.strip_edges().is_empty():
		return
	_known_quest_fingerprints[source.strip_edges().to_lower().sha256_text()] = true

# Load pre-hashed fingerprints directly from saved idea memory on campaign load.
func seed_quest_fingerprints(hashed_fingerprints: Array) -> void:
	for fp in hashed_fingerprints:
		if fp is String and not (fp as String).is_empty():
			_known_quest_fingerprints[fp] = true

func clear_quest_fingerprints() -> void:
	_known_quest_fingerprints.clear()

func _is_quest_fingerprint_known(quest_data: Dictionary) -> bool:
	if _known_quest_fingerprints.is_empty():
		return false
	var objective: Dictionary = quest_data.get("objective", {})
	var source := JSON.stringify({
		"title": str(quest_data.get("title", "")),
		"faction": str(quest_data.get("faction", "")),
		"agent_name": str(quest_data.get("agent_name", "")),
		"dialogue": str(quest_data.get("dialogue", "")),
		"objective": objective,
	})
	return _known_quest_fingerprints.has(source.strip_edges().to_lower().sha256_text())


func request_quest_generation(
	agent_faction: String,
	history_text: String,
	player_credits: int,
	player_reps: Dictionary,
	callback: Callable,
	agent_profile: Dictionary = {}
) -> void:
	if is_waiting:
		return
	
	active_callback = callback
	is_waiting = true
	last_history_text = history_text
	request_start_time = Time.get_ticks_msec()
	GlobalState.trace("[TRACE] [LLMInterface] request_quest_generation initiated at: %d ms" % request_start_time)
	
	var rand_comp = complications[randi() % complications.size()]
	
	# Pick a faction randomly if "neutral" is passed (neutral = broker picks any client)
	var chosen_faction = agent_faction
	if chosen_faction == "neutral" or chosen_faction == "":
		var factions = ["zenith", "aurelia", "vanguard"]
		chosen_faction = factions[randi() % factions.size()]
	
	# Each faction has a distinct named agent, personality, and address style.
	# TODO(llm-content): the nickname/address rules baked into these persona
	# strings (Shiny = Kaelen only, Indy only occasionally for faction agents) are
	# mirrored in llm_dialogue_content.json under `global_rules` and `speakers.*`.
	# Left in code for now because persona wording is interwoven with mechanics;
	# migrate persona text to `speakers.<id>.tone_card` / `.address_rule` in a
	# later slice. Do not let Shiny leak into the non-Kaelen personas here.
	var agent_name = "Broker Kaelen"
	var agent_persona = ""
	var player_nickname = "Indy"
	var agent_role = ""
	var agent_portrait_id := ""
	var agent_voice_profile_id := ""
	var example_faction_key = chosen_faction

	match chosen_faction:
		"zenith":
			agent_name = "Director Voss"
			agent_role = "Zenith Corporate Acquisitions Director"
			player_nickname = "Indy"
			agent_persona = "You are Director Voss, a cold, calculating Zenith corporate officer. " + \
				"You speak in clipped, efficient sentences. You have no patience for failure and treat the pilot as an interchangeable asset. " + \
				"Only occasionally call the pilot 'Indy' — most of the time refer to them as 'you', 'pilot', or 'asset', not by name. You never use slang or humor. " + \
				"You frame all jobs as 'acquisitions', 'operations', or 'directives'. Zenith's interests are paramount."
		"aurelia":
			agent_name = "Liaison Ryn"
			agent_role = "Aurelia Syndicate Trade Liaison"
			player_nickname = "Indy"
			agent_persona = "You are Liaison Ryn, a smooth-talking, conniving Aurelia syndicate fixer. " + \
				"You are charming but never fully trustworthy. You speak like someone always running an angle. " + \
				"Only occasionally call the pilot 'Indy' — most of the time use 'you' or 'pilot', not the pilot's name. You use words like 'clean', 'quiet', 'off the books'. " + \
				"Everything is framed as an opportunity, never a risk."
		"vanguard":
			agent_name = "Captain Dask"
			agent_role = "Vanguard Military Contract Officer"
			player_nickname = "Indy"
			agent_persona = "You are Captain Dask, a gruff, no-nonsense Vanguard military contract officer. " + \
				"You are direct and have zero tolerance for excuses or negotiation theatre. " + \
				"Only occasionally call the pilot 'Indy' — most of the time use 'pilot' or direct orders, not the pilot's name. You use military shorthand: 'ROE', 'boots on hull', 'clear the zone'. " + \
				"You respect competence and despise weakness."
		_:
			agent_name = "Broker Kaelen"
			agent_role = "Neutral Fixer & Profit Broker"
			player_nickname = "Shiny"
			agent_persona = "You are Broker Kaelen, an independent, politically neutral space broker and fixer. " + \
				"You operate out of a space station and negotiate contracts with all factions for personal profit. " + \
				"You are cynical, sharp, and opportunistic. You call the pilot 'Shiny' — treating them like an unscarred greenhorn who is also your most profitable tool. " + \
				"You always mention your broker's cut and how the deal benefits you personally."
	
	if not agent_profile.is_empty():
		var profile_faction_id := str(agent_profile.get("faction_id", "")).strip_edges()
		var profile_faction := str(agent_profile.get("faction", chosen_faction)).strip_edges()
		chosen_faction = (
			profile_faction_id
			if profile_faction.begins_with("gen_") and not profile_faction_id.is_empty()
			else profile_faction
		)
		agent_name = str(agent_profile.get("agent_name", agent_name)).strip_edges()
		if agent_name.is_empty():
			agent_name = "Local Contact"
		agent_role = str(agent_profile.get("agent_role", "Station faction contact")).strip_edges()
		agent_portrait_id = str(agent_profile.get("agent_portrait_id", "")).strip_edges()
		agent_voice_profile_id = str(
			agent_profile.get("agent_voice_profile_id", "")
		).strip_edges()
		player_nickname = "Indy"
		var faction_label := str(
			agent_profile.get("faction_display", profile_faction.capitalize())
		)
		var role_label: String = (
			agent_role if not agent_role.is_empty() else "station contact"
		)
		agent_persona = "You are %s, a %s for %s. " % [
			agent_name,
			role_label,
			faction_label,
		] + \
			"You are stationed in the current system and offer practical local contracts. " + \
			"You speak directly to the pilot, use dry PG-13 frontier humor when it fits, and only use 'Indy' sparingly. Most lines should use 'you' or 'pilot' instead. " + \
			"Do not impersonate Broker Kaelen. Do not claim to be from Zenith, Aurelia, or Vanguard unless that is your faction."

	var agent_memory_id: String = agent_memory_id_for_profile(
		agent_name,
		chosen_faction,
		agent_profile
	)

	# Pre-decide objective type so example AND instruction always match.
	# The LLM cannot choose — it must use the type we picked.
	var quest_types = ["DELIVER_ORE", "KILL_SHIPS", "PICKUP_SPECIAL"]
	var chosen_type = quest_types[randi() % quest_types.size()]

	# story_quest_hint: StoryManager can bias the type. Honour it when set and
	# when the preferred_type is a valid quest type.
	var _hint: Dictionary = GlobalState.story_quest_hint
	var _hint_type: String = str(_hint.get("preferred_type", "")).to_upper()
	if not _hint.is_empty() and _hint_type in quest_types:
		chosen_type = _hint_type
	
	# Build the matching example block
	var example_obj_block = ""
	var example_title = ""
	var pickup_outpost = ""
	var pickup_outpost_display = ""
	var pickup_npc = ""
	var pickup_item = ""
	
	# Pre-roll the actual objective values. The LLM never sees these —
	# it always writes "Slithern" / "George" / 3 / 25 / "Morrow" / etc.
	# We swap them in after generation via _substitute_dummy_names().
	var actual_kill_target := ""
	var actual_kill_count := randi_range(2, 4)
	var actual_ore_amount: float = snapped(randf_range(20.0, 300.0), 5.0)

	if chosen_type == "DELIVER_ORE":
		example_title = "Silicate Run"
		example_obj_block = \
			"  \"objective\": {\n" + \
			"    \"type\": \"DELIVER_ORE\",\n" + \
			"    \"amount_required\": 25.0,\n" + \
			"    \"reward_credits\": 160\n" + \
			"  },"
	elif chosen_type == "KILL_SHIPS":
		if randf() < 0.9:
			var minor_keys = GlobalState.get_current_system_minor_factions()
			actual_kill_target = minor_keys[randi() % minor_keys.size()]
		else:
			var major_targets = ["zenith", "aurelia", "vanguard"]
			major_targets.erase(chosen_faction)
			actual_kill_target = major_targets[randi() % major_targets.size()]
		example_title = "Clear the Lane"
		example_obj_block = \
			"  \"objective\": {\n" + \
			"    \"type\": \"KILL_SHIPS\",\n" + \
			"    \"target_faction\": \"slithern\",\n" + \
			"    \"count_required\": 3,\n" + \
			"    \"reward_credits\": 200\n" + \
			"  },"
	elif chosen_type == "PICKUP_SPECIAL":
		var outposts = GlobalState.get_current_pickup_outposts()
		if outposts.is_empty():
			chosen_type = "DELIVER_ORE"
			example_title = "Ore Run"
			actual_ore_amount = float(randi_range(25, 60))
			example_obj_block = \
				"  \"objective\": {\n" + \
				"    \"type\": \"DELIVER_ORE\",\n" + \
				"    \"amount_required\": 25.0,\n" + \
				"    \"reward_credits\": 160\n" + \
				"  },"
		else:
			var selected_outpost = outposts[randi() % outposts.size()]
			pickup_outpost = selected_outpost.get("id", "")
			pickup_outpost_display = selected_outpost.get("display", pickup_outpost)
			var npcs_at_outpost = GlobalState.get_minor_npcs_at_outpost(pickup_outpost)
			if npcs_at_outpost.is_empty():
				chosen_type = "DELIVER_ORE"
				example_title = "Ore Run"
				actual_ore_amount = float(randi_range(25, 60))
				example_obj_block = \
					"  \"objective\": {\n" + \
					"    \"type\": \"DELIVER_ORE\",\n" + \
					"    \"amount_required\": 25.0,\n" + \
					"    \"reward_credits\": 160\n" + \
					"  },"
			else:
				pickup_npc = npcs_at_outpost[randi() % npcs_at_outpost.size()]
				var fetch_items = ["Large Unmarked Crate", "Suspension Pod", "Sealed Data Drive", "Biometric Lockbox", "Hazardous Material Container"]
				pickup_item = fetch_items[randi() % fetch_items.size()]
				example_title = "Discreet Courier"
				example_obj_block = \
					"  \"objective\": {\n" + \
					"    \"type\": \"PICKUP_SPECIAL\",\n" + \
					"    \"target_outpost\": \"outpost_morrow\",\n" + \
					"    \"target_outpost_display\": \"Morrow Station\",\n" + \
					"    \"target_npc\": \"Sable Mercer\",\n" + \
					"    \"part_name\": \"Sealed Data Drive\",\n" + \
					"    \"destination\": \"" + agent_name + "\",\n" + \
					"    \"reward_credits\": 250\n" + \
					"  },"

	# Stash actuals so _substitute_dummy_names can swap them in later
	_pending_substitutions = {
		"kill_target": actual_kill_target,
		"kill_count": actual_kill_count,
		"ore_amount": actual_ore_amount,
		"nickname": player_nickname,
		"agent_name": agent_name,
		"agent_role": agent_role,
		"agent_portrait_id": agent_portrait_id,
		"agent_voice_profile_id": agent_voice_profile_id,
		"agent_memory_id": agent_memory_id,
		"faction": chosen_faction,
		"pickup_outpost": pickup_outpost,
		"pickup_outpost_display": pickup_outpost_display,
		"pickup_npc": pickup_npc,
		"pickup_item": pickup_item,
	}



	# Build minor faction context string for the LLM
	var minor_fac_names = GlobalState.get_current_system_minor_factions()
	var minor_fac_str = ", ".join(minor_fac_names)
	
	var lore_block = ""
	if world_lore_text != "":
		lore_block = "### WORLD LORE:\n" + world_lore_text + "\n\n"
	var campaign_bible_block = ""
	if campaign_bible_context_text.strip_edges() != "":
		campaign_bible_block = (
			"### CAMPAIGN BIBLE:\n"
			+ campaign_bible_context_text
			+ "\n\n"
		)
	var story_state_block = ""
	if story_state_context_text.strip_edges() != "":
		story_state_block = (
			"### STORY STATE:\n"
			+ story_state_context_text
			+ "\n\n"
		)
	var system_story_pack: Dictionary = _agent_system_story_pack(agent_profile)
	var system_story_block: String = _system_story_pack_prompt_block(system_story_pack)
	var agent_memory_block := _agent_memory_prompt_block(agent_memory_id)
	var idea_memory_block = ""
	if idea_memory_context_text.strip_edges() != "":
		idea_memory_block = (
			"### PRIOR GENERATED IDEAS TO AVOID REPEATING:\n"
			+ idea_memory_context_text
			+ "\n\n"
		)
	
	# Fetch 5 type-matched example dialogues + responses for this agent × mission type
	var agent_key = chosen_faction if chosen_faction in ["zenith", "aurelia", "vanguard"] else "neutral"
	var type_examples = _get_type_examples(agent_key, chosen_type)
	var example_dialogues: Array = type_examples.get("dialogues", [])
	var example_response_1: String = type_examples.get("response_1", "")
	var example_response_2: String = type_examples.get("response_2", "")
	var example_response_3: String = type_examples.get("response_3", "")

	# Pick one dialogue for the JSON structure example, list the rest as additional references.
	# Thin "George" out of about half the examples so substituted output does not
	# train every non-Kaelen speaker to say "Indy" in every line.
	for i in range(example_dialogues.size()):
		if i % 2 == 1:
			example_dialogues[i] = _thin_pilot_name(str(example_dialogues[i]), "George", 0)
	if chosen_faction != "neutral":
		example_response_1 = _thin_pilot_name(example_response_1, "George", 0)
		example_response_2 = _thin_pilot_name(example_response_2, "George", 0)
	var primary_idx = randi() % example_dialogues.size()
	var example_dialogue: String = example_dialogues[primary_idx]
	var extra_examples_block = "### EXAMPLE DIALOGUES FOR THIS MISSION TYPE:\n" + \
		"Write NEW dialogue in this style. Do not copy these — use them only as tone and content references.\n"
	for i in range(example_dialogues.size()):
		if i != primary_idx:
			extra_examples_block += "  " + str(i + 1) + ". \"" + example_dialogues[i] + "\"\n"
	extra_examples_block += "\n"

	# Dummy-name/fact instruction now lives in the content registry
	# (quest_generation.mission_types[TYPE].dummy_constraints). Edit phrasing in
	# data/content/llm_dialogue_content.json. Built-in strings below are only a
	# fallback if that section is missing; they must mirror the JSON exactly.
	var dummy_name_instruction: String = LLMDialogueContentRegistry.shared().quest_dummy_constraints(chosen_type)
	if dummy_name_instruction.strip_edges().is_empty():
		if chosen_type == "KILL_SHIPS":
			dummy_name_instruction = "In your dialogue, always call the enemy 'Slithern'. Only rarely call the pilot 'George' — most lines should use 'you' or 'pilot' and NOT the pilot's name. Always say 3 ships. "
		elif chosen_type == "DELIVER_ORE":
			dummy_name_instruction = "In your dialogue, only rarely call the pilot 'George' — most lines should use 'you' or 'pilot' and NOT the pilot's name. Always say 25 m³ of ore. "
		else:
			dummy_name_instruction = "In your dialogue, only rarely call the pilot 'George' — most lines should use 'you' or 'pilot' and NOT the pilot's name. Always say the pickup is from Sable Mercer at Morrow Station for a Sealed Data Drive. "

	# story_quest_hint destination/flavor bias injected as a soft prompt instruction.
	# Decrement expiry counter here so it ticks once per quest generation, not per dock.
	var story_hint_block: String = ""
	var _active_hint: Dictionary = GlobalState.story_quest_hint
	if not _active_hint.is_empty():
		var _h_system: String = str(_active_hint.get("preferred_system", ""))
		var _h_flavor: String = str(_active_hint.get("flavor_tag", ""))
		if not _h_system.is_empty():
			story_hint_block = "### NARRATIVE CONTEXT:\nThe agent has contacts in the %s region. Lean the mission toward that area if plausible. Flavor: %s.\n\n" % [_h_system, _h_flavor]
		var _remaining: int = int(_active_hint.get("expires_after_docks", 3)) - 1
		if _remaining <= 0:
			GlobalState.story_quest_hint = {}
		else:
			GlobalState.story_quest_hint["expires_after_docks"] = _remaining

	var system_prompt = agent_persona + "\n\n" + \
		lore_block + \
		campaign_bible_block + \
		story_state_block + \
		system_story_block + \
		agent_memory_block + \
		idea_memory_block + \
		story_hint_block + \
		"Minor hostile factions in the sector: " + minor_fac_str + ". These are outlaws with no diplomatic ties — primary targets for elimination contracts.\n\n" + \
		"Current pilot stats:\n" + \
		"- Credits: " + str(player_credits) + " SC\n" + \
		"- Zenith reputation: " + str(player_reps.get("zenith", 50.0)) + "\n" + \
		"- Aurelia reputation: " + str(player_reps.get("aurelia", -20.0)) + "\n" + \
		"- Vanguard reputation: " + str(player_reps.get("vanguard", -20.0)) + "\n\n" + \
		"### COMPLETED MISSION HISTORY:\n" + \
		"Reference past contracts naturally in your dialogue if the list is not empty:\n" + \
		history_text + "\n\n" + \
		"### QUEST COMPLICATION:\n" + \
		rand_comp + "\n\n" + \
		extra_examples_block + \
		"Generate a unique space quest. You MUST respond strictly in valid JSON format. Do not output notes, markdown, or surrounding text. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"campaign_name\": \"Cold Meridian\",\n" + \
		"  \"title\": \"" + example_title + "\",\n" + \
		"  \"faction\": \"" + chosen_faction + "\",\n" + \
		"  \"agent_name\": \"" + agent_name + "\",\n" + \
		"  \"dialogue\": \"" + example_dialogue + "\",\n" + \
		example_obj_block + "\n" + \
		"  \"choices\": [\n" + \
		"    {\n" + \
		"      \"text\": \"I'll take the job.\",\n" + \
		"      \"consequence\": {\n" + \
		"        \"credits_immediate\": 0,\n" + \
		"        \"reputation_change\": {\"" + chosen_faction + "\": 3},\n" + \
		"        \"combat_multiplier\": 1.0,\n" + \
		"        \"reward_credits_multiplier\": 1.0,\n" + \
		"        \"dialogue_response\": \"" + example_response_1 + "\"\n" + \
		"      }\n" + \
		"    },\n" + \
		"    {\n" + \
		"      \"text\": \"I need a credit advance first.\",\n" + \
		"      \"consequence\": {\n" + \
		"        \"credits_immediate\": 40,\n" + \
		"        \"reputation_change\": {\"" + chosen_faction + "\": -2},\n" + \
		"        \"combat_multiplier\": 1.3,\n" + \
		"        \"reward_credits_multiplier\": 1.2,\n" + \
		"        \"dialogue_response\": \"" + example_response_2 + "\"\n" + \
		"      }\n" + \
		"    },\n" + \
		"    {\n" + \
		"      \"text\": \"The payout isn't worth the risk. Increase it.\",\n" + \
		"      \"consequence\": {\n" + \
		"        \"credits_immediate\": 0,\n" + \
		"        \"reputation_change\": {\"" + chosen_faction + "\": -5},\n" + \
		"        \"combat_multiplier\": 1.7,\n" + \
		"        \"reward_credits_multiplier\": 1.6,\n" + \
		"        \"dialogue_response\": \"" + example_response_3 + "\"\n" + \
		"      }\n" + \
		"    }\n" + \
		"  ]\n" + \
		"}\n\n" + \
		"Now generate a COMPLETELY DIFFERENT quest with a unique title and all-new dialogue written in your character's voice. " + \
		"The campaign_name must be an evocative two-to-four-word name for the pilot's larger story, not merely this contract. " + \
		"Do not use the words campaign, save, slot, adventure, or journey in campaign_name. " + \
		"The faction must be \"" + chosen_faction + "\". The agent_name must be \"" + agent_name + "\". " + \
		"The objective type in your JSON MUST be '" + chosen_type + "' — do NOT use any other objective type. " + \
		"Keep the same objective fields as the example above. " + \
		"The dialogue is the agent OFFERING the job to the pilot — the pilot has NOT accepted yet. Speak directly to the pilot in second person. Do not narrate, announce, or talk about the pilot in third person. " + \
		"IMPORTANT: The choices array MUST contain EXACTLY 3 entries — no more, no fewer. " + \
		dummy_name_instruction + \
		"Output only the raw JSON object."
	
	var headers: Array[String] = ["Content-Type: application/json"]
	
	print("[LLMInterface] Sending best-of-%d quest request to Ollama for faction: %s agent: %s" % [
		QUEST_CANDIDATE_TARGET_COUNT,
		chosen_faction,
		agent_name,
	])
	GenerationDiagnostics.record_event(
		"quest_generation",
		"request_started",
		"LLMInterface",
		{
			"model": active_model_name,
			"faction": chosen_faction,
			"agent_name": agent_name,
			"objective_type": chosen_type,
			"system_story_pack_id": str(system_story_pack.get("system_id", "")),
		}
	)
	_start_quest_candidate_batch(
		system_prompt,
		headers,
		{
			"model": active_model_name,
			"faction": chosen_faction,
			"agent_name": agent_name,
			"objective_type": chosen_type,
			"system_story_pack_id": str(system_story_pack.get("system_id", "")),
		}
	)


func _start_quest_candidate_batch(
	prompt: String,
	headers: Array[String],
	context: Dictionary
) -> void:
	for request in _quest_candidate_requests:
		if request and is_instance_valid(request):
			request.cancel_request()
			request.queue_free()
	_quest_candidate_prompt = prompt
	_quest_candidate_headers = headers.duplicate()
	_quest_candidate_context = context.duplicate(true)
	_quest_candidate_attempts_started = 0
	_quest_candidate_results.clear()
	_quest_candidate_requests.clear()
	_start_next_quest_candidate()


func _start_next_quest_candidate() -> void:
	if _quest_candidate_attempts_started >= QUEST_CANDIDATE_TARGET_COUNT:
		_finish_quest_candidate_batch()
		return

	_quest_candidate_attempts_started += 1
	var attempt_number := _quest_candidate_attempts_started
	var temp_http := HTTPRequest.new()
	add_child(temp_http)
	_quest_candidate_requests.append(temp_http)
	temp_http.timeout = request_timeout_for_capability("quest_dialogue")
	var started_msec := Time.get_ticks_msec()
	temp_http.request_completed.connect(
		_on_quest_candidate_completed.bind(
			temp_http.get_instance_id(),
			attempt_number,
			started_msec
		)
	)
	var payload: Dictionary = build_generation_body(
		"quest_dialogue",
		_quest_candidate_prompt,
		"json",
		{
			"temperature": 0.85,
			"seed": randi(),
		}
	)
	var err := temp_http.request(
		OLLAMA_URL,
		_quest_candidate_headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		temp_http.queue_free()
		_quest_candidate_requests.erase(temp_http)
		_quest_candidate_results.append({
			"ok": false,
			"attempt": attempt_number,
			"score": -1000,
			"reason": "http_request_start_failed_%d" % err,
			"elapsed_seconds": 0.0,
		})
		GenerationDiagnostics.record_event(
			"quest_generation",
			"candidate_request_start_failed",
			"LLMInterface",
			_quest_candidate_context.merged({
				"attempt": attempt_number,
				"error_code": err,
			}, true)
		)
		_start_next_quest_candidate()


func _on_quest_candidate_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	request_instance_id: int,
	attempt_number: int,
	started_msec: int
) -> void:
	var temp_http := instance_from_id(request_instance_id) as HTTPRequest
	if temp_http:
		_quest_candidate_requests.erase(temp_http)
		temp_http.queue_free()
	var elapsed := float(Time.get_ticks_msec() - started_msec) / 1000.0
	var candidate := _parse_quest_candidate_response(
		result,
		response_code,
		body,
		attempt_number,
		elapsed
	)
	_quest_candidate_results.append(candidate)
	GenerationDiagnostics.record_event(
		"quest_generation",
		"candidate_scored" if bool(candidate.get("ok", false)) else "candidate_failed",
		"LLMInterface",
		_quest_candidate_context.merged({
			"attempt": attempt_number,
			"score": int(candidate.get("score", -1000)),
			"reason": str(candidate.get("reason", "")),
			"elapsed_seconds": elapsed,
		}, true)
	)
	_start_next_quest_candidate()


func _parse_quest_candidate_response(
	result: int,
	response_code: int,
	body: PackedByteArray,
	attempt_number: int,
	elapsed: float
) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return {
			"ok": false,
			"attempt": attempt_number,
			"score": -1000,
			"reason": "http_failed_result_%d_code_%d" % [result, response_code],
			"elapsed_seconds": elapsed,
		}
	var response_text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(response_text) != OK:
		return {
			"ok": false,
			"attempt": attempt_number,
			"score": -1000,
			"reason": "response_envelope_parse_failed",
			"elapsed_seconds": elapsed,
		}
	var outer_data = json.get_data()
	if not outer_data is Dictionary or not outer_data.has("response"):
		return {
			"ok": false,
			"attempt": attempt_number,
			"score": -1000,
			"reason": "response_envelope_missing_response",
			"elapsed_seconds": elapsed,
		}
	var inner_json_str := str(outer_data["response"]).strip_edges()
	if inner_json_str.begins_with("```"):
		var end_idx := inner_json_str.find("\n", 3)
		if end_idx != -1:
			inner_json_str = inner_json_str.substr(end_idx + 1)
		if inner_json_str.ends_with("```"):
			inner_json_str = inner_json_str.substr(
				0,
				inner_json_str.length() - 3
			)
		inner_json_str = inner_json_str.strip_edges()
	var inner_json := JSON.new()
	if inner_json.parse(inner_json_str) != OK:
		return {
			"ok": false,
			"attempt": attempt_number,
			"score": -1000,
			"reason": "inner_json_parse_failed",
			"elapsed_seconds": elapsed,
		}
	var quest_data = inner_json.get_data()
	if not quest_data is Dictionary \
			or not quest_data.has("objective") \
			or not quest_data.has("choices"):
		return {
			"ok": false,
			"attempt": attempt_number,
			"score": -1000,
			"reason": "quest_schema_missing_fields",
			"elapsed_seconds": elapsed,
		}
	var campaign_name := _sanitize_campaign_name(
		str(quest_data.get("campaign_name", ""))
	)
	quest_data["campaign_name"] = (
		campaign_name
		if not campaign_name.is_empty()
		else _fallback_campaign_name()
	)
	_substitute_dialogue_placeholders(quest_data)
	_validate_quest_data(quest_data)
	var scored := _score_quest_candidate(quest_data)
	return {
		"ok": true,
		"attempt": attempt_number,
		"score": int(scored.get("score", 0)),
		"reason": str(scored.get("reason", "")),
		"elapsed_seconds": elapsed,
		"quest_data": quest_data,
	}


func _score_quest_candidate(quest_data: Dictionary) -> Dictionary:
	var score := 100
	var reasons: Array[String] = []
	var obj: Dictionary = quest_data.get("objective", {})
	var obj_type := str(obj.get("type", ""))
	var dialogue := str(quest_data.get("dialogue", ""))
	var dialogue_lower := dialogue.to_lower()
	if bool(quest_data.get("objective_dialogue_rewritten", false)):
		score -= 30
		reasons.append("rewritten")
	if str(quest_data.get("title", "")).strip_edges().is_empty():
		score -= 10
		reasons.append("missing_title")
	if dialogue.strip_edges().length() < 35:
		score -= 15
		reasons.append("short_dialogue")
	if _dialogue_has_placeholder_artifacts(
		dialogue,
		str(quest_data.get("agent_name", ""))
	):
		score -= 35
		reasons.append("placeholder_artifacts")
	if _dialogue_is_too_vague(dialogue, obj_type):
		score -= 20
		reasons.append("too_vague")
	if obj_type == "PICKUP_SPECIAL":
		if _dialogue_has_pickup_detail_mismatch(dialogue, obj_type, obj):
			score -= 35
			reasons.append("pickup_detail_mismatch")
		elif dialogue_lower.find(str(obj.get("target_npc", "")).to_lower()) != -1:
			score += 5
			reasons.append("exact_pickup_contact")
	elif obj_type == "KILL_SHIPS":
		if dialogue_lower.find(str(obj.get("target_faction", "")).to_lower()) != -1:
			score += 5
			reasons.append("exact_target_faction")
	elif obj_type == "DELIVER_ORE":
		var amount_text := str(int(round(float(obj.get("amount_required", 0.0)))))
		if dialogue_lower.find(amount_text) != -1:
			score += 5
			reasons.append("exact_ore_amount")
	var choices: Array = quest_data.get("choices", [])
	if choices.size() < 3:
		score -= 15
		reasons.append("missing_choices")
	for choice in choices:
		if not choice is Dictionary:
			score -= 10
			reasons.append("bad_choice")
			continue
		var consequence: Dictionary = choice.get("consequence", {})
		var response := str(consequence.get("dialogue_response", ""))
		if response.strip_edges().length() < 8:
			score -= 8
			reasons.append("short_choice_response")
	return {
		"score": score,
		"reason": ", ".join(reasons),
	}


func _finish_quest_candidate_batch() -> void:
	var best_candidate: Dictionary = {}
	var duplicate_skip_count := 0
	for candidate in _quest_candidate_results:
		if not bool(candidate.get("ok", false)):
			continue
		if _is_quest_fingerprint_known(candidate.get("quest_data", {})):
			duplicate_skip_count += 1
			continue
		if best_candidate.is_empty() \
				or int(candidate.get("score", -1000)) > int(best_candidate.get("score", -1000)):
			best_candidate = candidate
	if duplicate_skip_count > 0:
		print("[LLMInterface] Skipped %d exact-duplicate quest candidate(s)." % duplicate_skip_count)
	if best_candidate.is_empty():
		GenerationDiagnostics.record_event(
			"quest_generation",
			"candidate_batch_failed",
			"LLMInterface",
			_quest_candidate_context.merged({
				"candidate_count": _quest_candidate_results.size(),
			}, true)
		)
		_quest_candidate_results.clear()
		_quest_candidate_requests.clear()
		_trigger_fallback_with_reason("candidate_batch_failed")
		return
	var total_elapsed := float(Time.get_ticks_msec() - request_start_time) / 1000.0
	var score := int(best_candidate.get("score", 0))
	var attempt := int(best_candidate.get("attempt", 0))
	GenerationDiagnostics.record_event(
		"quest_generation",
		"candidate_batch_selected",
		"LLMInterface",
		_quest_candidate_context.merged({
			"selected_attempt": attempt,
			"selected_score": score,
			"candidate_count": _quest_candidate_results.size(),
		}, true)
	)
	print(
		"[LLMInterface] Selected quest candidate %d/%d with score %d." %
		[attempt, QUEST_CANDIDATE_TARGET_COUNT, score]
	)
	var quest_data: Dictionary = best_candidate.get("quest_data", {})
	_quest_candidate_results.clear()
	_quest_candidate_requests.clear()
	_finish_quest_with_current_dialogue(quest_data, total_elapsed)


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var now = Time.get_ticks_msec()
	var elapsed = (now - request_start_time) / 1000.0
	GlobalState.trace("[TRACE] [LLMInterface] HTTP request completed in %.3fs. Result: %d, Response code: %d at %d ms" % [elapsed, result, response_code, now])
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[LLMInterface] HTTP request failed or timed out. Response code: ", response_code)
		GenerationDiagnostics.record_event(
			"quest_generation",
			"http_or_timeout_failed",
			"LLMInterface",
			{
				"result": result,
				"response_code": response_code,
				"elapsed_seconds": elapsed,
				"model": active_model_name,
			}
		)
		_trigger_fallback_with_reason(
			"http_failed_result_%d_code_%d" % [result, response_code]
		)
		return
		
	var response_text = body.get_string_from_utf8()
	var json = JSON.new()
	var err = json.parse(response_text)
	if err != OK:
		print("[LLMInterface] Failed to parse Ollama response envelope JSON.")
		GenerationDiagnostics.record_event(
			"quest_generation",
			"response_envelope_parse_failed",
			"LLMInterface",
			{"elapsed_seconds": elapsed, "model": active_model_name}
		)
		_trigger_fallback_with_reason("response_envelope_parse_failed")
		return
		
	var outer_data = json.get_data()
	if not outer_data is Dictionary or not outer_data.has("response"):
		print("[LLMInterface] Response envelope missing 'response' field.")
		GenerationDiagnostics.record_event(
			"quest_generation",
			"response_envelope_missing_response",
			"LLMInterface",
			{"elapsed_seconds": elapsed, "model": active_model_name}
		)
		_trigger_fallback_with_reason("response_envelope_missing_response")
		return
		
	var inner_json_str = outer_data["response"].strip_edges()
	
	# Strip markdown wrappers if LLM returned them despite format constraints
	if inner_json_str.begins_with("```"):
		var end_idx = inner_json_str.find("\n", 3)
		if end_idx != -1:
			inner_json_str = inner_json_str.substr(end_idx + 1)
		if inner_json_str.ends_with("```"):
			inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
		inner_json_str = inner_json_str.strip_edges()

	var inner_json = JSON.new()
	var inner_err = inner_json.parse(inner_json_str)
	if inner_err != OK:
		print("[LLMInterface] Failed to parse inner generated JSON dialogue: ", inner_json_str)
		GenerationDiagnostics.record_event(
			"quest_generation",
			"inner_json_parse_failed",
			"LLMInterface",
			{"elapsed_seconds": elapsed, "model": active_model_name}
		)
		_trigger_fallback_with_reason("inner_json_parse_failed")
		return
		
	var quest_data = inner_json.get_data()
	if not quest_data is Dictionary or not quest_data.has("objective") or not quest_data.has("choices"):
		print("[LLMInterface] Parsed quest data is invalid or missing fields.")
		GenerationDiagnostics.record_event(
			"quest_generation",
			"quest_schema_missing_fields",
			"LLMInterface",
			{"elapsed_seconds": elapsed, "model": active_model_name}
		)
		_trigger_fallback_with_reason("quest_schema_missing_fields")
		return
		
	print("[LLMInterface] LLM Quest successfully generated: ", quest_data["title"])
	var campaign_name := _sanitize_campaign_name(
		str(quest_data.get("campaign_name", ""))
	)
	quest_data["campaign_name"] = (
		campaign_name
		if not campaign_name.is_empty()
		else _fallback_campaign_name()
	)
	_substitute_dialogue_placeholders(quest_data)
	_validate_quest_data(quest_data)
	if quest_data.get("objective_dialogue_rewritten", false):
		print("[LLMInterface] Dialogue was rewritten — requesting retry from LLM with locked objective.")
		_request_dialogue_retry(quest_data, elapsed)
		return
	is_waiting = false
	GenerationDiagnostics.record_content_source(
		"quest_generation",
		"llm",
		"LLMInterface",
		{
			"elapsed_seconds": elapsed,
			"model": active_model_name,
			"title": str(quest_data.get("title", "")),
		}
	)
	if active_callback.is_valid():
		active_callback.call(quest_data, false)


# ── Dummy-Name Substitution ─────────────────────────────────────────────────
# The LLM always writes "George" (pilot), "Slithern" (enemy faction),
# "3" (kill count), "25" (ore amount), and fixed pickup names.
# We swap these for the real pre-rolled values so the dialogue always
# matches the actual contract.

func _substitute_dialogue_placeholders(quest_data: Dictionary) -> void:
	var subs := _pending_substitutions
	if subs.is_empty():
		return
	var obj: Dictionary = quest_data.get("objective", {})
	var obj_type: String = obj.get("type", "")
	var nickname := _nickname_for_agent(str(subs.get("agent_name", "")))
	quest_data["agent_role"] = str(subs.get("agent_role", "Neutral Fixer & Profit Broker"))
	quest_data["agent_portrait_id"] = str(subs.get("agent_portrait_id", ""))
	quest_data["agent_voice_profile_id"] = str(subs.get("agent_voice_profile_id", ""))
	quest_data["agent_memory_id"] = str(subs.get("agent_memory_id", ""))
	quest_data["faction"] = str(
		subs.get("faction", quest_data.get("faction", "neutral"))
	).to_lower().strip_edges()
	quest_data["agent_name"] = str(subs.get("agent_name", quest_data.get("agent_name", "Broker Kaelen")))

	var replacements := {}
	# Swap dummy pilot name for the real nickname
	replacements["George"] = nickname
	replacements["george"] = nickname.to_lower()

	if obj_type == "KILL_SHIPS":
		var real_faction: String = str(subs.get("kill_target", ""))
		var real_count: int = int(subs.get("kill_count", 3))
		replacements["Slithern"] = real_faction.capitalize()
		replacements["slithern"] = real_faction
		replacements["SLITHERN"] = real_faction.to_upper()
		# Common LLM misspellings / inflections of the dummy name
		for variant in ["Slitherns", "slitherns", "Slitheren", "slitheren",
				"Slitherer", "slitherer", "Slitherers", "slitherers"]:
			replacements[variant] = real_faction.capitalize() if variant[0] == "S" else real_faction
		obj["target_faction"] = real_faction
		obj["count_required"] = real_count
	elif obj_type == "DELIVER_ORE":
		var real_amount: float = float(subs.get("ore_amount", 25.0))
		obj["amount_required"] = real_amount
	elif obj_type == "PICKUP_SPECIAL":
		var real_outpost: String = str(subs.get("pickup_outpost", ""))
		var real_outpost_display: String = str(subs.get("pickup_outpost_display", ""))
		var real_npc: String = str(subs.get("pickup_npc", ""))
		var real_item: String = str(subs.get("pickup_item", ""))
		replacements["Morrow Station"] = real_outpost_display
		replacements["morrow station"] = real_outpost_display.to_lower()
		replacements["outpost_morrow"] = real_outpost
		replacements["Sable Mercer"] = real_npc
		replacements["sable mercer"] = real_npc.to_lower()
		replacements["Sealed Data Drive"] = real_item
		replacements["sealed data drive"] = real_item.to_lower()
		obj["target_outpost"] = real_outpost
		obj["target_outpost_display"] = real_outpost_display
		obj["target_npc"] = real_npc
		obj["part_name"] = real_item

	# Title gets the same dummy-name substitution as the dialogue — otherwise the
	# LLM's "Slithern"/"George" leak straight into the mission card title (the
	# slither* regex in _apply_replacements also catches inflected leftovers).
	quest_data["title"] = _apply_replacements(str(quest_data.get("title", "")), replacements)

	quest_data["dialogue"] = _thin_pilot_name(
		_apply_replacements(str(quest_data.get("dialogue", "")), replacements), nickname)

	var choices: Array = quest_data.get("choices", [])
	for choice in choices:
		if choice is Dictionary:
			if choice.has("text"):
				choice["text"] = _apply_replacements(str(choice["text"]), replacements)
			var cons: Dictionary = choice.get("consequence", {})
			if cons.has("dialogue_response"):
				# Opening already addresses the pilot by name; strip it from the
				# follow-up responses so it isn't repeated in every line.
				cons["dialogue_response"] = _thin_pilot_name(
					_apply_replacements(str(cons["dialogue_response"]), replacements), nickname, 0)


func _apply_replacements(text: String, replacements: Dictionary) -> String:
	var result := text
	for placeholder: String in replacements:
		result = result.replace(placeholder, str(replacements[placeholder]))
	# Catch any remaining "slither*" variants the explicit list missed
	if _pending_substitutions.has("kill_target"):
		var real_faction: String = str(_pending_substitutions["kill_target"])
		var regex := RegEx.new()
		regex.compile("(?i)\\bslither\\w*")
		var cleaned := regex.sub(result, real_faction.capitalize(), true)
		if cleaned != result:
			print("[LLMInterface] ⚠ SUBSTITUTE: Regex caught leftover slither-variant in dialogue")
			result = cleaned
	return result


# The local model tends to address the pilot by name in every sentence
# ("Acknowledged, Indy. ... Don't fall behind, Indy."). Keep only the FIRST
# use of the nickname per text field and drop the rest, cleaning up the
# punctuation/spacing left behind so it reads naturally.
func _thin_pilot_name(text: String, nickname: String, keep: int = 1) -> String:
	var name := nickname.strip_edges()
	if name.is_empty() or text.is_empty():
		return text
	var re := RegEx.new()
	# The name as a whole word, plus any commas/spaces hugging it on either side.
	if re.compile("(?i)\\s*,?\\s*\\b" + name + "\\b\\s*,?\\s*") != OK:
		return text
	var matches := re.search_all(text)
	if matches.size() <= keep:
		return text
	# Keep the first `keep` occurrences; remove the rest (back-to-front so
	# offsets stay valid). keep=0 strips the name entirely.
	var result := text
	for i in range(matches.size() - 1, keep - 1, -1):
		var m: RegExMatch = matches[i]
		result = result.substr(0, m.get_start()) + " " + result.substr(m.get_end())
	# Tidy: collapse double spaces and drop spaces before sentence punctuation.
	result = result.replace("  ", " ")
	var punct := RegEx.new()
	if punct.compile("\\s+([,.!?])") == OK:
		result = punct.sub(result, "$1", true)
	result = result.strip_edges()
	# Re-capitalize if removing a leading vocative lowercased the sentence.
	if result.length() > 0:
		var first := result[0]
		if first >= "a" and first <= "z":
			result = first.to_upper() + result.substr(1)
	return result


# ── Dialogue Retry (critique loop) ──────────────────────────────────────────
# When the first LLM attempt produces a dialogue that conflicts with the
# validated objective (wrong faction, wrong count, wrong type), we give the
# LLM one more shot with explicit constraints. If the retry also fails
# validation, we keep the safe fallback dialogue from attempt 1.

func _request_dialogue_retry(quest_data: Dictionary, first_elapsed: float) -> void:
	var obj: Dictionary = quest_data.get("objective", {})
	var obj_type: String = obj.get("type", "")
	var agent_name: String = str(quest_data.get("agent_name", ""))

	var objective_desc := ""
	if obj_type == "KILL_SHIPS":
		objective_desc = "Destroy 3 Slithern ships"
	elif obj_type == "DELIVER_ORE":
		objective_desc = "Deliver 25 m³ of ore"
	elif obj_type == "PICKUP_SPECIAL":
		objective_desc = "Pick up a Sealed Data Drive from Sable Mercer at Morrow Station"

	var retry_prompt := (
		"You are %s. Write a 2-3 sentence mission briefing for this contract.\n\n" % agent_name +
		"Objective: %s\n" % objective_desc +
		"Call the pilot 'George'. Stay in character.\n\n" +
		"Respond with ONLY the dialogue text, no JSON, no quotes, no formatting."
	)

	var payload: Dictionary = build_generation_body(
		"quest_dialogue",
		retry_prompt,
		"",
		{"temperature": 0.7, "num_predict": 200}
	)
	var json_str := JSON.stringify(payload)

	var temp_http := HTTPRequest.new()
	temp_http.timeout = request_timeout_for_capability("quest_dialogue")
	add_child(temp_http)
	var instance_id := temp_http.get_instance_id()

	temp_http.request_completed.connect(
		func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			_on_dialogue_retry_completed(result, response_code, body, quest_data, first_elapsed, instance_id)
	)

	var err := temp_http.request(OLLAMA_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, json_str)
	if err != OK:
		print("[LLMInterface] Dialogue retry HTTP failed to start — using safe fallback.")
		_finish_quest_with_current_dialogue(quest_data, first_elapsed)


func _on_dialogue_retry_completed(
	result: int,
	response_code: int,
	body: PackedByteArray,
	quest_data: Dictionary,
	first_elapsed: float,
	request_instance_id: int
) -> void:
	var temp_http := instance_from_id(request_instance_id) as HTTPRequest
	if temp_http:
		temp_http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[LLMInterface] Dialogue retry HTTP failed — using safe fallback.")
		_finish_quest_with_current_dialogue(quest_data, first_elapsed)
		return

	var response_text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(response_text) != OK:
		print("[LLMInterface] Dialogue retry parse failed — using safe fallback.")
		_finish_quest_with_current_dialogue(quest_data, first_elapsed)
		return

	var outer = json.get_data()
	if not outer is Dictionary or not outer.has("response"):
		print("[LLMInterface] Dialogue retry missing response — using safe fallback.")
		_finish_quest_with_current_dialogue(quest_data, first_elapsed)
		return

	var new_dialogue: String = str(outer["response"]).strip_edges()
	# Strip markdown/quotes wrapping
	if new_dialogue.begins_with("\"") and new_dialogue.ends_with("\""):
		new_dialogue = new_dialogue.substr(1, new_dialogue.length() - 2)

	if new_dialogue.is_empty() or new_dialogue.length() < 20:
		print("[LLMInterface] Dialogue retry too short — using safe fallback.")
		_finish_quest_with_current_dialogue(quest_data, first_elapsed)
		return

	# Substitute placeholders in the retry dialogue
	quest_data["dialogue"] = new_dialogue
	_substitute_dialogue_placeholders(quest_data)
	new_dialogue = str(quest_data.get("dialogue", ""))

	# Test the retry dialogue against validation
	var obj: Dictionary = quest_data.get("objective", {})
	var obj_type: String = obj.get("type", "")

	var type_conflict := _dialogue_conflicts_with_objective(new_dialogue, obj_type)
	var faction_conflict := _dialogue_has_faction_mismatch(new_dialogue, obj_type, obj)

	if type_conflict or faction_conflict:
		print("[LLMInterface] ⚠ RETRY FAILED — type_conflict=%s faction_conflict=%s" % [type_conflict, faction_conflict])
		print("[LLMInterface] ⚠ RETRY DIALOGUE WAS: %s" % new_dialogue)
		GenerationDiagnostics.record_event(
			"quest_generation",
			"dialogue_retry_still_conflicting",
			"LLMInterface",
			{"type_conflict": type_conflict, "faction_conflict": faction_conflict}
		)
		quest_data["dialogue"] = _safe_objective_dialogue(quest_data, obj_type, obj)
		_finish_quest_with_current_dialogue(quest_data, first_elapsed)
		return

	quest_data.erase("objective_dialogue_rewritten")
	_sync_dialogue_to_validated_objective(quest_data, obj_type, obj)
	print("[LLMInterface] ✓ Dialogue retry succeeded — using LLM's second attempt.")
	GenerationDiagnostics.record_event(
		"quest_generation",
		"dialogue_retry_succeeded",
		"LLMInterface",
		{}
	)
	_finish_quest_with_current_dialogue(quest_data, first_elapsed)


func _finish_quest_with_current_dialogue(quest_data: Dictionary, elapsed: float) -> void:
	GenerationDiagnostics.record_content_source(
		"quest_generation",
		"llm",
		"LLMInterface",
		{
			"elapsed_seconds": elapsed,
			"model": active_model_name,
			"title": str(quest_data.get("title", "")),
			"dialogue_retried": quest_data.has("objective_dialogue_rewritten"),
		}
	)
	is_waiting = false
	if active_callback.is_valid():
		active_callback.call(quest_data, false)


# ── Dialogue ↔ Objective Reconciliation ──────────────────────────────────────
# The LLM sometimes writes dialogue that mentions different numbers than
# what it puts in the JSON objective. Since the player reads the dialogue,
# we treat the dialogue as the source of truth and patch the JSON to match.
func _validate_quest_data(quest_data: Dictionary):
	var dialogue = quest_data.get("dialogue", "").to_lower()
	var obj = quest_data.get("objective", {})
	var obj_type = obj.get("type", "")
	
	# ── Step 1: Detect objective type mismatch ────────────────────────────
	# Check if the dialogue describes a different mission type than the JSON
	var dialogue_sounds_like_kill = false
	var dialogue_sounds_like_ore = false
	var dialogue_sounds_like_pickup = false
	
	var kill_keywords = ["destroy", "eliminate", "kill", "take out", "take down",
		"clear", "remove", "neutralize", "engage", "intercept", "wipe out",
		"blow up", "shoot down", "hostile", "raider", "patrol", "contacts"]
	var ore_keywords = ["ore", "silicate", "mine", "mining", "deliver", "cargo",
		"shipment", "haul", "tonnage", "cubic", "m³", "m3"]
	var pickup_keywords = ["retrieve", "fetch", "unopened", "crate", "pod", "lockbox", "container", "drive"]
	
	for kw in kill_keywords:
		if dialogue.find(kw) != -1:
			dialogue_sounds_like_kill = true
			break
	for kw in ore_keywords:
		if dialogue.find(kw) != -1:
			dialogue_sounds_like_ore = true
			break
	for kw in pickup_keywords:
		if dialogue.find(kw) != -1:
			dialogue_sounds_like_pickup = true
			break
	
	# If dialogue clearly describes kills but JSON says ore (or vice versa), fix the type
	if false and dialogue_sounds_like_kill and not dialogue_sounds_like_ore and not dialogue_sounds_like_pickup and obj_type == "DELIVER_ORE":
		print("[LLMInterface] ⚠ VALIDATE: Dialogue describes KILL mission but JSON says DELIVER_ORE. Patching type.")
		obj["type"] = "KILL_SHIPS"
		obj_type = "KILL_SHIPS"
		# Set sensible defaults if missing
		if not obj.has("count_required"):
			obj["count_required"] = 3
		if not obj.has("target_faction"):
			var quest_faction = quest_data.get("faction", "zenith")
			var minor_keys = GlobalState.MINOR_FACTIONS.keys()
			obj["target_faction"] = minor_keys[randi() % minor_keys.size()]
		obj.erase("amount_required")
	elif false and dialogue_sounds_like_ore and not dialogue_sounds_like_kill and not dialogue_sounds_like_pickup and obj_type == "KILL_SHIPS":
		print("[LLMInterface] ⚠ VALIDATE: Dialogue describes ORE mission but JSON says KILL_SHIPS. Patching type.")
		obj["type"] = "DELIVER_ORE"
		obj_type = "DELIVER_ORE"
		if not obj.has("amount_required"):
			obj["amount_required"] = 25.0
		obj.erase("count_required")
		obj.erase("target_faction")
	
	# ── Step 2: Extract numbers from dialogue and reconcile ──────────────
	if obj_type == "KILL_SHIPS":
		_reconcile_kill_count(quest_data, dialogue, obj)
	elif obj_type == "DELIVER_ORE":
		_reconcile_ore_amount(quest_data, dialogue, obj)
	
	# ── Step 3: Clamp to valid ranges ────────────────────────────────────
	if obj_type == "KILL_SHIPS":
		var count = int(obj.get("count_required", 3))
		var clamped_count := clampi(count, 2, 4)
		if count != clamped_count:
			GenerationDiagnostics.record_event(
				"quest_generation",
				"validation_clamped_kill_count",
				"LLMInterface",
				{"from": count, "to": clamped_count}
			)
		obj["count_required"] = clamped_count

		# Validate target_faction is a known faction (minor or major).
		# If the LLM hallucinated an unknown name (e.g. "synths", "outlaws"),
		# the ship would spawn with no model. Remap to a random minor
		# faction so it always renders.
		var tf = obj.get("target_faction", "")
		var known_factions = GlobalState.MINOR_FACTIONS.keys()
		known_factions.append_array(GlobalState.get_current_system_minor_factions())
		known_factions.append_array(["zenith", "aurelia", "vanguard"])
		if tf == "" or not tf in known_factions:
			var minor_keys = GlobalState.get_current_system_minor_factions()
			if minor_keys.is_empty():
				minor_keys = GlobalState.MINOR_FACTIONS.keys()
			var original = tf if tf != "" else "(empty)"
			obj["target_faction"] = minor_keys[randi() % minor_keys.size()]
			GenerationDiagnostics.record_event(
				"quest_generation",
				"validation_remapped_target_faction",
				"LLMInterface",
				{"from": original, "to": obj["target_faction"]}
			)
			print("[LLMInterface] ⚠ VALIDATE: Unknown target_faction '%s' remapped to '%s'." % [original, obj["target_faction"]])
	elif obj_type == "DELIVER_ORE":
		var amount = float(obj.get("amount_required", 25.0))
		var clamped_amount := clampf(amount, 20.0, 300.0)
		if not is_equal_approx(amount, clamped_amount):
			GenerationDiagnostics.record_event(
				"quest_generation",
				"validation_clamped_ore_amount",
				"LLMInterface",
				{"from": amount, "to": clamped_amount}
			)
		obj["amount_required"] = clamped_amount
	elif obj_type == "PICKUP_SPECIAL":
		var outpost = obj.get("target_outpost", "")
		var npc = obj.get("target_npc", "")
		var valid_outposts: Array = []
		for local_outpost in GlobalState.get_current_pickup_outposts():
			if local_outpost is Dictionary:
				valid_outposts.append(str(local_outpost.get("id", "")))
		if valid_outposts.is_empty():
			GenerationDiagnostics.record_event(
				"quest_generation",
				"validation_retyped_pickup_without_local_outpost",
				"LLMInterface",
				{"from": outpost, "system_id": GlobalState.current_system_id}
			)
			obj_type = "DELIVER_ORE"
			quest_data["type"] = "DELIVER_ORE"
			obj.clear()
			obj["type"] = "DELIVER_ORE"
			obj["amount_required"] = 25.0
			obj["reward_credits"] = 160
			_sync_dialogue_to_validated_objective(quest_data, obj_type, obj)
			_finalize_validated_quest_display(quest_data, obj_type, obj)
			return
		if outpost not in valid_outposts:
			var fallback_outpost: String = str(valid_outposts[0])
			var fallback_display := fallback_outpost
			for local_outpost in GlobalState.get_current_pickup_outposts():
				if local_outpost is Dictionary \
						and str(local_outpost.get("id", "")) == fallback_outpost:
					fallback_display = str(local_outpost.get("display", fallback_outpost))
					break
			if GlobalState.PICKUP_OUTPOST_DISPLAY.has(fallback_outpost):
				fallback_display = str(
					GlobalState.PICKUP_OUTPOST_DISPLAY.get(fallback_outpost)
				)
			GenerationDiagnostics.record_event(
				"quest_generation",
				"validation_remapped_pickup_outpost",
				"LLMInterface",
				{"from": outpost, "to": fallback_outpost}
			)
			obj["target_outpost"] = fallback_outpost
			obj["target_outpost_display"] = fallback_display
			var fallback_npcs := GlobalState.get_minor_npcs_at_outpost(fallback_outpost)
			if fallback_npcs.is_empty():
				GenerationDiagnostics.record_event(
					"quest_generation",
					"validation_retyped_pickup_without_local_npc",
					"LLMInterface",
					{"outpost": fallback_outpost, "system_id": GlobalState.current_system_id}
				)
				obj_type = "DELIVER_ORE"
				quest_data["type"] = "DELIVER_ORE"
				obj.clear()
				obj["type"] = "DELIVER_ORE"
				obj["amount_required"] = 25.0
				obj["reward_credits"] = 160
				_sync_dialogue_to_validated_objective(quest_data, obj_type, obj)
				_finalize_validated_quest_display(quest_data, obj_type, obj)
				return
			npc = fallback_npcs[0]
			obj["target_npc"] = npc
		else:
			var valid_npcs = GlobalState.get_minor_npcs_at_outpost(outpost)
			if valid_npcs.is_empty():
				GenerationDiagnostics.record_event(
					"quest_generation",
					"validation_retyped_pickup_without_local_npc",
					"LLMInterface",
					{"outpost": outpost, "system_id": GlobalState.current_system_id}
				)
				obj_type = "DELIVER_ORE"
				quest_data["type"] = "DELIVER_ORE"
				obj.clear()
				obj["type"] = "DELIVER_ORE"
				obj["amount_required"] = 25.0
				obj["reward_credits"] = 160
				_sync_dialogue_to_validated_objective(quest_data, obj_type, obj)
				_finalize_validated_quest_display(quest_data, obj_type, obj)
				return
			if npc not in valid_npcs:
				GenerationDiagnostics.record_event(
					"quest_generation",
					"validation_remapped_pickup_npc",
					"LLMInterface",
					{"from": npc, "outpost": outpost}
				)
				obj["target_npc"] = valid_npcs[0]
		if not obj.has("part_name"):
			obj["part_name"] = "Suspicious Crate"
		if not obj.has("destination"):
			obj["destination"] = "Main Station"

	# Last line of defense: reconciliation above may pull an out-of-range
	# number from the dialogue, then clamping can make the two disagree again.
	# Patch only the objective number so display text and TTS use the final value.
	_sync_dialogue_to_validated_objective(quest_data, obj_type, obj)
	_finalize_validated_quest_display(quest_data, obj_type, obj)


func _finalize_validated_quest_display(
	quest_data: Dictionary,
	obj_type: String,
	obj: Dictionary
) -> void:
	quest_data["objective_summary"] = _objective_summary(obj_type, obj)
	var rewrite_reason := ""
	var raw_dialogue := str(quest_data.get("dialogue", ""))
	var raw_agent := str(quest_data.get("agent_name", ""))
	if _dialogue_conflicts_with_objective(raw_dialogue, obj_type):
		rewrite_reason = "dialogue_conflicts_with_objective"
	elif _dialogue_has_faction_mismatch(raw_dialogue, obj_type, obj):
		rewrite_reason = "faction_mismatch"
	elif _dialogue_has_pickup_detail_mismatch(raw_dialogue, obj_type, obj):
		rewrite_reason = "pickup_detail_mismatch"
	elif _dialogue_has_placeholder_artifacts(raw_dialogue, raw_agent):
		rewrite_reason = "placeholder_artifacts"
	elif _dialogue_is_too_vague(raw_dialogue, obj_type):
		rewrite_reason = "too_vague"
	if not rewrite_reason.is_empty():
		print("[LLMInterface] ⚠ VALIDATE REWRITE REASON: %s" % rewrite_reason)
		print("[LLMInterface] ⚠ VALIDATE ORIGINAL DIALOGUE: %s" % raw_dialogue)
		GenerationDiagnostics.record_event(
			"quest_generation",
			"validation_rewrote_contradictory_dialogue",
			"LLMInterface",
			{"objective_type": obj_type, "reason": rewrite_reason}
		)
		quest_data["dialogue"] = _safe_objective_dialogue(
			quest_data,
			obj_type,
			obj
		)
		quest_data["objective_dialogue_rewritten"] = true
		print(
			"[LLMInterface] ⚠ VALIDATE: Replaced contradictory briefing with verified objective text."
		)


func _objective_summary(obj_type: String, obj: Dictionary) -> String:
	if obj_type == "DELIVER_ORE":
		return "%d m³ Ore" % int(round(float(
			obj.get("amount_required", 20.0)
		)))
	if obj_type == "KILL_SHIPS":
		var target_display := GlobalState.faction_display_name(
			str(obj.get("target_faction", "zenith")),
			true
		)
		obj["target_faction_display"] = target_display
		return "Destroy %d %s ships" % [
			int(obj.get("count_required", 3)),
			target_display,
		]
	if obj_type == "PICKUP_SPECIAL":
		return "Pick up %s from %s at %s" % [
			str(obj.get("part_name", "the package")),
			str(obj.get("target_npc", "the contact")),
			str(obj.get("target_outpost_display", "the outpost")),
		]
	return "Review contract details"


func _safe_objective_dialogue(
	quest_data: Dictionary,
	obj_type: String,
	obj: Dictionary
) -> String:
	var nickname := _nickname_for_agent(str(quest_data.get("agent_name", "")))
	if obj_type == "DELIVER_ORE":
		return (
			"I need a clean ore run, %s. Bring back %d m³ of ore and "
			+ "keep the paperwork boring."
		) % [
			nickname,
			int(round(float(obj.get("amount_required", 20.0)))),
		]
	if obj_type == "KILL_SHIPS":
		var target_display := GlobalState.faction_display_name(
			str(obj.get("target_faction", "zenith")),
			true
		)
		obj["target_faction_display"] = target_display
		return (
			"I need the lane cleared, %s. Destroy %d %s ships and "
			+ "come back in one piece."
		) % [
			nickname,
			int(obj.get("count_required", 3)),
			target_display,
		]
	if obj_type == "PICKUP_SPECIAL":
		return (
			"Quiet retrieval, %s. Pick up %s from %s at %s, then bring it "
			+ "straight back."
		) % [
			nickname,
			str(obj.get("part_name", "the package")),
			str(obj.get("target_npc", "the contact")),
			str(obj.get("target_outpost_display", "the outpost")),
		]
	return str(quest_data.get("dialogue", "Contract details are attached."))


func _dialogue_conflicts_with_objective(
	raw_dialogue: String,
	obj_type: String
) -> bool:
	var dialogue := raw_dialogue.to_lower()
	if dialogue.strip_edges().is_empty():
		return false
	var kill_score := _keyword_score(dialogue, [
		"destroy", "eliminate", "kill", "take out", "take down",
		"clear", "neutralize", "intercept", "wipe out", "blow up",
		"shoot down", "hostile", "raider", "raiders", "patrol",
		"contacts", "bounty"
	])
	var ore_score := _keyword_score(dialogue, [
		"ore", "silicate", "mine", "mining", "deliver", "cargo",
		"shipment", "haul", "tonnage", "cubic", "m³", "m3"
	])
	var pickup_score := _keyword_score(dialogue, [
		"retrieve", "fetch", "pick up", "pickup", "unopened",
		"crate", "pod", "lockbox", "container", "drive", "package"
	])
	if obj_type == "DELIVER_ORE":
		return kill_score >= 2 and ore_score == 0 and pickup_score == 0
	if obj_type == "KILL_SHIPS":
		return ore_score >= 2 and kill_score == 0 and pickup_score == 0
	if obj_type == "PICKUP_SPECIAL":
		return (kill_score >= 2 or ore_score >= 2) and pickup_score == 0
	return false


func _dialogue_has_faction_mismatch(
	raw_dialogue: String,
	obj_type: String,
	obj: Dictionary
) -> bool:
	if obj_type != "KILL_SHIPS":
		return false
	var dialogue := raw_dialogue.to_lower()
	var target := str(obj.get("target_faction", "")).to_lower()
	if target.is_empty():
		return false
	var all_factions: Array[String] = []
	for f in GlobalState.MINOR_FACTIONS.keys():
		all_factions.append(str(f).to_lower())
	for f in ["zenith", "aurelia", "vanguard"]:
		all_factions.append(f)
	var mentioned_wrong := false
	for faction in all_factions:
		if faction == target:
			continue
		if dialogue.find(faction) != -1:
			mentioned_wrong = true
			break
	if mentioned_wrong:
		print(
			"[LLMInterface] ⚠ VALIDATE: Dialogue mentions a faction other than target '%s'. Rewriting." % target
		)
	return mentioned_wrong


func _dialogue_has_pickup_detail_mismatch(
	raw_dialogue: String,
	obj_type: String,
	obj: Dictionary
) -> bool:
	if obj_type != "PICKUP_SPECIAL":
		return false
	var dialogue := raw_dialogue.to_lower()
	if dialogue.strip_edges().is_empty():
		return false
	var target_npc := str(obj.get("target_npc", "")).strip_edges()
	var target_outpost := str(
		obj.get("target_outpost_display", obj.get("target_outpost", ""))
	).strip_edges()
	var part_name := str(obj.get("part_name", "")).strip_edges()
	if not target_npc.is_empty() and not _text_mentions_phrase(dialogue, target_npc):
		print(
			"[LLMInterface] ⚠ VALIDATE: Pickup dialogue does not mention target NPC '%s'. Rewriting." %
			target_npc
		)
		return true
	if not target_outpost.is_empty() and not _text_mentions_phrase(dialogue, target_outpost):
		print(
			"[LLMInterface] ⚠ VALIDATE: Pickup dialogue does not mention target outpost '%s'. Rewriting." %
			target_outpost
		)
		return true
	if not part_name.is_empty() and not _text_mentions_phrase(dialogue, part_name):
		print(
			"[LLMInterface] ⚠ VALIDATE: Pickup dialogue does not mention item '%s'. Rewriting." %
			part_name
		)
		return true
	return false


func _text_mentions_phrase(text_lower: String, phrase: String) -> bool:
	var clean_phrase := phrase.strip_edges().to_lower()
	if clean_phrase.is_empty():
		return true
	if text_lower.find(clean_phrase) != -1:
		return true
	var words := clean_phrase.split(" ", false)
	if words.size() <= 1:
		return false
	var hits := 0
	for word in words:
		if str(word).length() >= 4 and text_lower.find(str(word)) != -1:
			hits += 1
	return hits >= mini(2, words.size())


func _nickname_for_agent(agent_name: String) -> String:
	if agent_name.to_lower().find("kaelen") != -1:
		return "Shiny"
	return "Indy"


func _dialogue_is_too_vague(raw_dialogue: String, obj_type: String) -> bool:
	var dialogue := raw_dialogue.to_lower()
	if obj_type == "KILL_SHIPS":
		var kill_hints := ["destroy", "eliminate", "kill", "clear", "remove",
			"engage", "intercept", "neutralize", "wipe", "ship", "contact",
			"target", "hostile", "raider", "patrol", "fighter"]
		for hint in kill_hints:
			if dialogue.find(hint) != -1:
				return false
		print("[LLMInterface] ⚠ VALIDATE: KILL_SHIPS dialogue has no combat keywords. Rewriting.")
		return true
	elif obj_type == "DELIVER_ORE":
		var ore_hints := ["ore", "silicate", "mine", "mining", "deliver",
			"cargo", "shipment", "haul", "tonnage", "m³", "m3", "cubic"]
		for hint in ore_hints:
			if dialogue.find(hint) != -1:
				return false
		print("[LLMInterface] ⚠ VALIDATE: DELIVER_ORE dialogue has no ore/delivery keywords. Rewriting.")
		return true
	elif obj_type == "PICKUP_SPECIAL":
		var pickup_hints := ["retrieve", "fetch", "pick up", "pickup", "crate",
			"pod", "lockbox", "container", "package", "collect", "grab", "courier",
			"delivery", "handoff", "hand-off", "drive", "item", "cargo",
			"bring back", "waiting for you", "holding", "has a", "get it"]
		# Also count the actual substituted item/npc/outpost names as valid
		var subs := _pending_substitutions
		if not str(subs.get("pickup_item", "")).is_empty():
			pickup_hints.append(str(subs.get("pickup_item", "")).to_lower())
		if not str(subs.get("pickup_npc", "")).is_empty():
			pickup_hints.append(str(subs.get("pickup_npc", "")).to_lower())
		if not str(subs.get("pickup_outpost_display", "")).is_empty():
			pickup_hints.append(str(subs.get("pickup_outpost_display", "")).to_lower())
		for hint in pickup_hints:
			if dialogue.find(hint) != -1:
				return false
		print("[LLMInterface] ⚠ VALIDATE: PICKUP_SPECIAL dialogue has no retrieval keywords. Rewriting.")
		return true
	return false


func _dialogue_has_placeholder_artifacts(raw_dialogue: String, agent_name: String) -> bool:
	var dialogue_lower := raw_dialogue.to_lower()
	if dialogue_lower.find("george") != -1:
		print("[LLMInterface] ⚠ VALIDATE: Dialogue still contains dummy name 'George'. Rewriting.")
		return true
	if dialogue_lower.find("slithern") != -1:
		print("[LLMInterface] ⚠ VALIDATE: Dialogue still contains dummy faction 'Slithern'. Rewriting.")
		return true
	if dialogue_lower.find("sable mercer") != -1 or dialogue_lower.find("morrow station") != -1:
		print("[LLMInterface] ⚠ VALIDATE: Dialogue still contains dummy pickup names. Rewriting.")
		return true
	var agent_lower := agent_name.to_lower().strip_edges()
	if not agent_lower.is_empty() and dialogue_lower.find(agent_lower) != -1:
		print("[LLMInterface] ⚠ VALIDATE: Dialogue contains agent's own name '%s'. Rewriting." % agent_name)
		return true
	return false


func _keyword_score(text: String, keywords: Array) -> int:
	var score := 0
	for keyword in keywords:
		if text.find(str(keyword)) != -1:
			score += 1
	return score

func _sync_dialogue_to_validated_objective(quest_data: Dictionary, obj_type: String, obj: Dictionary):
	var original_dialogue = str(quest_data.get("dialogue", ""))
	if original_dialogue.is_empty():
		return

	var dialogue = original_dialogue.to_lower()
	var number_start = -1
	var number_end = -1
	var replacement = ""

	if obj_type == "DELIVER_ORE":
		var ore_context_words = ["m³", "m3", "cubic", "ore", "silicate", "tonne",
			"metric", "cargo", "shipment", "deliver", "haul"]
		var i = 0
		while i < dialogue.length():
			if dialogue[i] >= "0" and dialogue[i] <= "9":
				var j = i
				var num_str = ""
				while j < dialogue.length() and ((dialogue[j] >= "0" and dialogue[j] <= "9") or dialogue[j] == "."):
					num_str += dialogue[j]
					j += 1
				var num_val = float(num_str)
				if num_val >= 10.0 and num_val <= 500.0:
					var after = dialogue.substr(j, 25)
					for context_word in ore_context_words:
						if after.find(context_word) != -1:
							number_start = i
							number_end = j
							break
				if number_start != -1:
					break
				i = j
			else:
				i += 1
		replacement = str(int(round(float(obj.get("amount_required", 25.0)))))
	elif obj_type == "KILL_SHIPS":
		var ship_words = ["ship", "contact", "target", "vessel", "hostile", "raider",
			"patrol", "interceptor", "sentinel", "fighter", "bogey", "hull",
			"of them", "scraped", "off the lane"]
		var kill_verbs = ["destroy", "eliminate", "kill", "clear", "remove", "engage",
			"take", "wants", "bounty"]
		for i in range(dialogue.length()):
			if dialogue[i] < "1" or dialogue[i] > "9":
				continue
			var digit_end = i + 1
			while digit_end < dialogue.length() \
					and dialogue[digit_end] >= "0" \
					and dialogue[digit_end] <= "9":
				digit_end += 1
			var after = dialogue.substr(digit_end, 35)
			var before_start = max(0, i - 25)
			var before = dialogue.substr(before_start, i - before_start)
			var is_objective_number = false
			for ship_word in ship_words:
				if after.find(ship_word) != -1:
					is_objective_number = true
					break
			if not is_objective_number:
				for kill_verb in kill_verbs:
					if before.find(kill_verb) != -1:
						is_objective_number = true
						break
			if is_objective_number:
				number_start = i
				number_end = digit_end
				break
		if number_start == -1:
			var number_phrases = {
				"a couple": 2,
				"a few": 3,
				"handful": 3,
				"several": 4,
				"two": 2,
				"three": 3,
				"four": 4,
				"five": 5,
				"six": 6,
			}
			for phrase: String in number_phrases:
				var phrase_start = dialogue.find(phrase)
				while phrase_start != -1:
					var phrase_end = phrase_start + phrase.length()
					var after = dialogue.substr(phrase_end, 35)
					var before_start = max(0, phrase_start - 25)
					var before = dialogue.substr(
						before_start,
						phrase_start - before_start
					)
					var is_objective_phrase = false
					for ship_word in ship_words:
						if after.find(ship_word) != -1:
							is_objective_phrase = true
							break
					if not is_objective_phrase:
						for kill_verb in kill_verbs:
							if before.find(kill_verb) != -1:
								is_objective_phrase = true
								break
					if is_objective_phrase:
						number_start = phrase_start
						number_end = phrase_end
						break
					phrase_start = dialogue.find(phrase, phrase_end)
				if number_start != -1:
					break
		replacement = str(int(obj.get("count_required", 3)))

	if number_start == -1:
		return

	var current_number = original_dialogue.substr(number_start, number_end - number_start)
	if current_number == replacement:
		return

	quest_data["dialogue"] = original_dialogue.substr(0, number_start) + replacement + original_dialogue.substr(number_end)
	GenerationDiagnostics.record_event(
		"quest_generation",
		"validation_rewrote_objective_number",
		"LLMInterface",
		{"objective_type": obj_type, "from": current_number, "to": replacement}
	)
	print("[LLMInterface] ⚠ VALIDATE: Final objective changed after validation. Rewrote dialogue number from %s to %s for display and TTS." % [current_number, replacement])

func _reconcile_kill_count(quest_data: Dictionary, dialogue: String, obj: Dictionary):
	# Look for patterns like "3 ships", "kill 4", "destroy 2", "four contacts", etc.
	var json_count = int(obj.get("count_required", 3))
	
	# Number word lookup
	var word_to_num = {
		"two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
		"a couple": 2, "a few": 3, "handful": 3, "several": 4
	}
	
	# Try to find a number near kill-related words
	var found_count = -1
	
	# Pattern: digit followed by ship-related word
	var ship_words = ["ship", "contact", "target", "vessel", "hostile", "raider",
		"patrol", "interceptor", "sentinel", "fighter", "bogey", "hull"]
	
	# Check digit patterns: "3 ships", "destroy 4", etc.
	for i in range(dialogue.length()):
		var c = dialogue[i]
		if c >= "1" and c <= "9":
			var digit = int(c)
			# Check context: is a ship word within 20 chars after this digit?
			var after = dialogue.substr(i + 1, 25).to_lower()
			for sw in ship_words:
				if after.find(sw) != -1:
					found_count = digit
					break
			if found_count != -1:
				break
			# Also check if a kill word is within 15 chars BEFORE this digit
			var before_start = max(0, i - 15)
			var before = dialogue.substr(before_start, i - before_start).to_lower()
			var kill_verbs = ["destroy", "eliminate", "kill", "clear", "remove", "engage", "take"]
			for kv in kill_verbs:
				if before.find(kv) != -1:
					found_count = digit
					break
			if found_count != -1:
				break
	
	# If digit search failed, check word numbers
	if found_count == -1:
		for word in word_to_num:
			var pos = dialogue.find(word)
			if pos != -1:
				# Check if a ship word is nearby
				var context = dialogue.substr(pos, 30)
				for sw in ship_words:
					if context.find(sw) != -1:
						found_count = word_to_num[word]
						break
				if found_count != -1:
					break
	
	if found_count != -1 and found_count != json_count:
		print("[LLMInterface] ⚠ VALIDATE: Dialogue says %d targets but JSON says count_required=%d. Patching JSON to match dialogue." % [found_count, json_count])
		GenerationDiagnostics.record_event(
			"quest_generation",
			"validation_repaired_kill_count_mismatch",
			"LLMInterface",
			{"from": json_count, "to": found_count}
		)
		obj["count_required"] = found_count
	elif found_count != -1:
		print("[LLMInterface] ✓ VALIDATE: Kill count matches — dialogue and JSON both say %d." % json_count)
	else:
		print("[LLMInterface] ✓ VALIDATE: No kill count found in dialogue text. Using JSON value: %d." % json_count)

func _reconcile_ore_amount(quest_data: Dictionary, dialogue: String, obj: Dictionary):
	# Look for patterns like "25 m³", "30 cubic", "deliver 50", "20 tonnes", etc.
	var json_amount = float(obj.get("amount_required", 25.0))
	var found_amount = -1.0
	
	var ore_context_words = ["m³", "m3", "cubic", "ore", "silicate", "tonne",
		"metric", "cargo", "shipment", "deliver", "haul"]
	
	# Search for number patterns followed by ore-related words
	# Match multi-digit numbers like 25, 100, 300
	var i = 0
	while i < dialogue.length():
		var c = dialogue[i]
		if c >= "0" and c <= "9":
			# Collect the full number
			var num_str = ""
			var j = i
			while j < dialogue.length() and ((dialogue[j] >= "0" and dialogue[j] <= "9") or dialogue[j] == "."):
				num_str += dialogue[j]
				j += 1
			var num_val = float(num_str)
			# Only consider values in a plausible ore range (10-500)
			if num_val >= 10.0 and num_val <= 500.0:
				var after = dialogue.substr(j, 25).to_lower()
				for ow in ore_context_words:
					if after.find(ow) != -1:
						found_amount = num_val
						break
			if found_amount > 0:
				break
			i = j
		else:
			i += 1
	
	if found_amount > 0 and absf(found_amount - json_amount) > 1.0:
		print("[LLMInterface] ⚠ VALIDATE: Dialogue says %.0f m³ but JSON says amount_required=%.0f. Patching JSON to match dialogue." % [found_amount, json_amount])
		GenerationDiagnostics.record_event(
			"quest_generation",
			"validation_repaired_ore_amount_mismatch",
			"LLMInterface",
			{"from": json_amount, "to": found_amount}
		)
		obj["amount_required"] = found_amount
	elif found_amount > 0:
		print("[LLMInterface] ✓ VALIDATE: Ore amount matches — dialogue and JSON both say %.0f m³." % json_amount)
	else:
		print("[LLMInterface] ✓ VALIDATE: No ore amount found in dialogue text. Using JSON value: %.0f m³." % json_amount)

func _trigger_fallback_with_reason(reason: String) -> void:
	_pending_fallback_reason = reason
	_trigger_fallback()


func _trigger_fallback():
	is_waiting = false
	var elapsed = (Time.get_ticks_msec() - request_start_time) / 1000.0
	GlobalState.trace("[TRACE] [LLMInterface] Triggering local procedural fallback quest (Ollama elapsed: %.3fs)." % elapsed)
	var reason := _pending_fallback_reason
	_pending_fallback_reason = ""
	if reason.is_empty():
		reason = "manual_or_unspecified"
	GenerationDiagnostics.record_content_source(
		"quest_generation",
		"procedural_fallback",
		"LLMInterface",
		{
			"elapsed_seconds": elapsed,
			"model": active_model_name,
			"fallback_reason": reason,
		}
	)
	GenerationDiagnostics.record_fallback(
		"quest_generation",
		reason,
		"LLMInterface",
		{
			"elapsed_seconds": elapsed,
			"model": active_model_name,
		}
	)
	
	# Try to pick a fallback template that hasn't been completed/abandoned recently
	var available_indices = []
	for i in range(fallback_templates.size()):
		var template = fallback_templates[i]
		if last_history_text == "" or last_history_text.find(template["title"]) == -1:
			available_indices.append(i)
			
	var idx = 0
	if available_indices.size() > 0:
		idx = available_indices[randi() % available_indices.size()]
	else:
		idx = randi() % fallback_templates.size()
		
	var selected_quest = fallback_templates[idx].duplicate(true)
	selected_quest["campaign_name"] = _fallback_campaign_name()
	selected_quest["agent_role"] = str(_pending_substitutions.get("agent_role", "Neutral Fixer & Profit Broker"))
	selected_quest["agent_name"] = str(_pending_substitutions.get("agent_name", selected_quest.get("agent_name", "Broker Kaelen")))
	selected_quest["agent_portrait_id"] = str(_pending_substitutions.get("agent_portrait_id", ""))
	selected_quest["agent_voice_profile_id"] = str(_pending_substitutions.get("agent_voice_profile_id", ""))
	selected_quest["agent_memory_id"] = str(_pending_substitutions.get("agent_memory_id", ""))
	selected_quest["faction"] = str(_pending_substitutions.get("faction", selected_quest.get("faction", "neutral")))
	
	# Randomize values slightly to make it feel procedural
	var type = selected_quest["objective"]["type"]
	if type == "DELIVER_ORE":
		var orig_amt = selected_quest["objective"]["amount_required"]
		selected_quest["objective"]["amount_required"] = snapped(orig_amt * randf_range(0.85, 1.25), 1.0)
	elif type == "KILL_SHIPS":
		var orig_cnt = selected_quest["objective"]["count_required"]
		selected_quest["objective"]["count_required"] = max(2, int(orig_cnt + randi_range(-1, 1)))
	
	var orig_reward = selected_quest["objective"]["reward_credits"]
	selected_quest["objective"]["reward_credits"] = int(orig_reward * randf_range(0.9, 1.2))

	# Fallback objectives are randomized after their canned dialogue is chosen.
	# Keep that dialogue aligned before the UI displays it or TTS speaks it.
	_sync_dialogue_to_validated_objective(selected_quest, type, selected_quest["objective"])
	
	if active_callback.is_valid():
		active_callback.call(selected_quest, true)

func get_chatter_line(type: String, context: Dictionary = {}) -> String:
	if not chatter_cache.has(type):
		return "Static on comms..."
		
	var line = ""
	if chatter_cache[type].size() > 0:
		line = chatter_cache[type].pop_front()
	else:
		var templates = generic_banter.get(type, ["Static on comms..."])
		line = templates[randi() % templates.size()]
		
	# Trigger background pre-fetch if cache is running low and not currently fetching
	if chatter_cache[type].size() < 2 and not active_fetches[type]:
		fetch_chatter_background(type, context)
		
	return line

# Build a context dict from current GlobalState for use in chatter prompts
func _build_chatter_context(extra: Dictionary = {}) -> Dictionary:
	var ctx: Dictionary = {}
	ctx["player_credits"] = GlobalState.player_credits
	ctx["cargo"] = int(GlobalState.cargo)
	ctx["cargo_max"] = int(GlobalState.cargo_max)
	var reps = GlobalState.reputations
	ctx["rep_zenith"]   = int(reps.get("zenith",   50.0))
	ctx["rep_aurelia"]  = int(reps.get("aurelia", -20.0))
	ctx["rep_vanguard"] = int(reps.get("vanguard", -20.0))
	var qm = Engine.get_singleton("QuestManager") if Engine.has_singleton("QuestManager") else null
	if qm == null:
		var tree = Engine.get_main_loop()
		if tree and tree.root:
			qm = tree.root.get_node_or_null("/root/QuestManager")
	if qm and qm.is_quest_active():
		ctx["active_quest_title"] = qm.active_quest.get("title", "")
		ctx["active_quest_type"]  = qm.active_quest.get("objective_type", "")
	for k in extra:
		ctx[k] = extra[k]
	return ctx


func fetch_chatter_background(type: String, context: Dictionary = {}):
	active_fetches[type] = true
	
	# Merge in live GlobalState context
	var ctx = _build_chatter_context(context)
	
	var credits_str  = str(ctx.get("player_credits", 0)) + " SC"
	var cargo_str    = str(ctx.get("cargo", 0)) + "/" + str(ctx.get("cargo_max", 100)) + " m³"
	var rep_str      = "Zenith " + str(ctx.get("rep_zenith", 50)) + \
		", Aurelia " + str(ctx.get("rep_aurelia", -20)) + \
		", Vanguard " + str(ctx.get("rep_vanguard", -20))
	var quest_str    = ctx.get("active_quest_title", "none")
	var attacker_fac = ctx.get("attacker_faction", "unknown")
	var wreck_name   = ctx.get("wreck_name", "")
	var killed_by_player = ctx.get("killed_by_player", false)
	
	var context_block = "\nCurrent game context:\n" + \
		"- Pilot credits: " + credits_str + "\n" + \
		"- Cargo hold: " + cargo_str + "\n" + \
		"- Faction reputations: " + rep_str + "\n" + \
		"- Active contract: " + quest_str + "\n"
	
	# Describe the generation task to Ollama based on type
	var description = ""
	match type:
		"hostile_taunt":
			var faction_hint = ""
			if attacker_fac != "unknown":
				faction_hint = "The attacker is a " + attacker_fac.to_upper() + " pilot. "
			var cargo_hint = ""
			if ctx.get("cargo", 0) > 10:
				cargo_hint = "The target is hauling " + cargo_str + " of cargo — taunt them about it. "
			var rep_hint = ""
			if ctx.get("rep_zenith", 50) < -30:
				rep_hint = "The pilot has burned bridges with Zenith — reference this enmity. "
			elif ctx.get("rep_aurelia", 0) < -30:
				rep_hint = "The pilot is despised by Aurelia — use this in the taunt. "
			var mission_hint = ""
			if quest_str != "none":
				mission_hint = "The target is on a contract called '" + quest_str + "' — mock them for it. "
			description = "3 unique, aggressive radio taunts (under 12 words each) from a " + \
				attacker_fac.to_upper() + " enemy pilot targeting the player ship. " + \
				faction_hint + cargo_hint + rep_hint + mission_hint + \
				"Be creative, threatening, and faction-flavoured. No generic lines."
		"death_cry":
			var ship_hint = ""
			if attacker_fac != "unknown":
				ship_hint = "The dying pilot flew for " + attacker_fac.to_upper() + ". "
			description = "3 unique dramatic death radio transmissions (under 12 words each) from a " + \
				attacker_fac.to_upper() + " pilot as their ship explodes. " + ship_hint + \
				"Include static markers like '[static]' or '...'. Vary tone: some defiant, some fearful, some darkly funny."
		"system_alert":
			description = "3 unique cold robotic system announcements or sector warnings (under 12 words each). " + \
				"Vary the threat type — gravitational, faction, radiation, debris field."
		"industrial_banter":
			var wreck_hint = ""
			if wreck_name != "":
				# Parse faction and ship type out of the node name (e.g. AURELIA_Raider_512_Wreck)
				var upper = wreck_name.to_upper()
				var faction_found = ""
				for f in ["ZENITH", "AURELIA", "VANGUARD"]:
					if f in upper:
						faction_found = f
						break
				var ship_class = ""
				for c in ["PATROL", "RAIDER", "SENTINEL", "INTERCEPTOR", "ELITE"]:
					if c in upper:
						ship_class = c
						break
				if killed_by_player:
					wreck_hint = "The salvager is cutting up a " + faction_found + " " + ship_class + \
						" wreck left by the player pilot. Comment on the battle damage, " + \
						"the hull condition, the pilot who must have done this, or what they can salvage. " + \
						"Be colourful — e.g. 'whoever hit this thing wasn't messing around'. "
				else:
					wreck_hint = "The salvager is approaching a " + faction_found + " " + ship_class + \
						" wreck. Comment on the expected salvage value or the faction's gear quality. "
			description = "3 unique radio chatter lines (under 15 words each) from a scrapper salvage crew. " + \
				wreck_hint + \
				"They are pragmatic, slightly world-weary, always thinking about credits. Avoid clichés."
		"kaelen_ore_sale":
			var ore_amount = str(ctx.get("cargo", 0))
			var credits_earned = str(ctx.get("ore_sale_earnings", 0))
			description = "3 unique Broker Kaelen lines (under 25 words each) reacting to the player selling ore through her. " + \
				"The player just sold " + ore_amount + " m³ of ore for " + credits_earned + " SC. " + \
				"Kaelen is a sharp, sarcastic broker who always takes her cut. She calls the player 'Shiny'. " + \
				"She's amused, transactional, and never sentimental. " + \
				"Example tone:\n" + \
				"  1. \"Yeah, I can move those for ya. Taking my cut, of course.\"\n" + \
				"  2. \"I don't want to know where you got those. I don't care either, 'cause I get my cut either way.\"\n" + \
				"  3. \"Ore's ore, Shiny. I've got a buyer lined up before you even finished docking. My percentage stands.\"\n" + \
				"  4. \"Not bad haul. I'll fence it through my usual channels — minus my modest commission. And before you ask, no, it's not negotiable.\"\n" + \
				"  5. \"You dig it up, I sell it off, we both walk away richer. Well, I walk away richer. You walk away less poor.\"\n" + \
				"Write 3 NEW lines in the same voice. Vary the angle — comment on the ore quality, the buyer, her margins, or the pilot's hustle. Do NOT repeat the examples."

	var system_prompt = "You are writing radio chatter dialogue lines for a space simulation game rated PG-13. " + \
		"Colourful language, mild swearing, dark humour, and sharp insults are encouraged where they fit the character. " + \
		"Do NOT use explicit sexual content or slurs. Everything else is fair game — be creative and unpredictable. " + \
		"Generate " + description + context_block + \
		"You MUST respond strictly in valid JSON format matching this schema exactly. Do not output any notes, markdown codeblock formatting, or surrounding text. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"dialogues\": [\n" + \
		"    \"[Line 1]\",\n" + \
		"    \"[Line 2]\",\n" + \
		"    \"[Line 3]\"\n" + \
		"  ]\n" + \
		"}"
		
	var payload: Dictionary = build_generation_body(
		"background_chatter",
		system_prompt,
		"json",
		{
			"temperature": 0.9,
			"seed": randi()
		}
	)
	
	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability("background_chatter")
	
	temp_http.request_completed.connect(func(result, response_code, headers, body):
		active_fetches[type] = false
		temp_http.queue_free()
		
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			print("[LLMInterface] Background chatter fetch failed for type: ", type, " (unreachable or offline)")
			return
			
		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		var err = json.parse(response_text)
		if err != OK:
			return
			
		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			return
			
		var inner_json_str = outer_data["response"].strip_edges()
		
		# Strip markdown codeblocks
		if inner_json_str.begins_with("```"):
			var end_idx = inner_json_str.find("\n", 3)
			if end_idx != -1:
				inner_json_str = inner_json_str.substr(end_idx + 1)
			if inner_json_str.ends_with("```"):
				inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
			inner_json_str = inner_json_str.strip_edges()
			
		var inner_json = JSON.new()
		var inner_err = inner_json.parse(inner_json_str)
		if inner_err != OK:
			return
			
		var chatter_data = inner_json.get_data()
		if chatter_data is Dictionary and chatter_data.has("dialogues"):
			var dialogues = chatter_data["dialogues"]
			if dialogues is Array:
				for line in dialogues:
					if line is String and line != "":
						chatter_cache[type].append(line.strip_edges())
				print("[LLMInterface] Successfully cached ", dialogues.size(), " lines for background chatter type: ", type)
	)
	
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		active_fetches[type] = false
		temp_http.queue_free()


var fallback_salvager_names = [
	"Maeve Sterling",
	"Rorik Flint",
	"Tess Torv",
	"Garrick Vance",
	"Sloane Mercer",
	"Jaxom Cruz",
	"Kira Thorne",
	"Caelen Drake"
]

var fallback_salvager_backstories = [
	"A veteran miner from the outer rim who spent years scraping ore from derelict structures. Dislikes corporate faction politics.",
	"A rogue salvager who runs a modified engine loop. Specializes in recovering high-grade alloys from deep space wreckages.",
	"A former Vanguard logistics engineer who went independent. Loves the quiet freedom of the deep belts and black market scrap.",
	"An opportunistic scrapper who believes every piece of debris has a story and a price. Always looking for the next big haul.",
	"A cynical belt-miner who survived a Zenith mine collapse. Now works alone, trusting only their sensors and their lasers.",
	"A young, ambitious pilot who bought a salvaged hauler. Eager to make a name and a fortune in the contested border zones."
]

func fetch_salvager_profile(callback: Callable):
	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability("salvager_profile")
	
	temp_http.request_completed.connect(
		_on_salvager_profile_request_completed.bind(
			temp_http.get_instance_id(),
			callback
		),
		CONNECT_ONE_SHOT
	)
	
	var prompt = "Generate a unique sci-fi scrapper/miner pilot name and a short (2-3 sentences) backstory. " + \
		"The pilot operates a salvager ship in the sector. The backstory should detail their origins, their ship name, and their scrapper personality. " + \
		"You MUST respond strictly in valid JSON format matching this schema exactly. Do not output any notes, markdown codeblock formatting, or surrounding text. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"name\": \"[Pilot Name]\",\n" + \
		"  \"backstory\": \"[Backstory Text]\"\n" + \
		"}"
		
	var payload: Dictionary = build_generation_body(
		"salvager_profile",
		prompt,
		"json",
		{
			"temperature": 0.85,
			"seed": randi()
		}
	)
	
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		_trigger_salvager_profile_fallback(
			callback,
			"http_request_start_failed_%d" % err
		)


func _on_salvager_profile_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	request_instance_id: int,
	callback: Callable
) -> void:
	var temp_http := instance_from_id(request_instance_id) as HTTPRequest
	if temp_http != null:
		temp_http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_trigger_salvager_profile_fallback(callback, "http_response_failed")
		return

	var response_text = body.get_string_from_utf8()
	var json = JSON.new()
	var err = json.parse(response_text)
	if err != OK:
		_trigger_salvager_profile_fallback(callback, "response_envelope_parse_failed")
		return

	var outer_data = json.get_data()
	if not outer_data is Dictionary or not outer_data.has("response"):
		_trigger_salvager_profile_fallback(callback, "response_envelope_missing_response")
		return

	var inner_json_str = outer_data["response"].strip_edges()

	if inner_json_str.begins_with("```"):
		var end_idx = inner_json_str.find("\n", 3)
		if end_idx != -1:
			inner_json_str = inner_json_str.substr(end_idx + 1)
		if inner_json_str.ends_with("```"):
			inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
		inner_json_str = inner_json_str.strip_edges()

	var inner_json = JSON.new()
	var inner_err = inner_json.parse(inner_json_str)
	if inner_err != OK:
		_trigger_salvager_profile_fallback(callback, "inner_json_parse_failed")
		return

	var profile_data = inner_json.get_data()
	if profile_data is Dictionary and profile_data.has("name") and profile_data.has("backstory"):
		_call_salvager_profile_callback(callback, profile_data)
	else:
		_trigger_salvager_profile_fallback(callback, "profile_schema_missing_fields")


func _call_salvager_profile_callback(callback: Callable, profile: Dictionary) -> void:
	if callback.is_valid():
		callback.call(profile)


func _record_llm_fallback(
	content_type: String,
	reason: String,
	context: Dictionary = {}
) -> void:
	GenerationDiagnostics.record_fallback(
		content_type,
		reason,
		"LLMInterface",
		context
	)


func request_kaelen_reaction(quest_data: Dictionary, callback: Callable, _attempts_left: int = 1):
	# Build a minimal context summary for Kaelen to react to
	var title = quest_data.get("title", "the contract")
	var faction = quest_data.get("faction", "neutral").capitalize()
	var obj = quest_data.get("objective", {})
	var obj_type = obj.get("type", "")
	var task_desc = ""
	if obj_type == "DELIVER_ORE":
		task_desc = "deliver %s m³ of ore for %s credits" % [str(int(obj.get("amount_required", 20))), str(obj.get("reward_credits", 150))]
	elif obj_type == "KILL_SHIPS":
		task_desc = "destroy %d %s ships for %s credits" % [obj.get("count_required", 3), obj.get("target_faction", "enemy").capitalize(), str(obj.get("reward_credits", 200))]
	else:
		task_desc = "complete the contract"

	var prompt = "You are Broker Kaelen, a cynical, profit-driven, politically neutral space broker. " + \
		"You call the pilot 'Shiny'. You just brokered a contract named '" + title + "' for the " + faction + " faction — the task was to " + task_desc + ". " + \
		"Generate TWO short unique lines of dialogue from Kaelen (under 25 words each): " + \
		"one she says when the pilot successfully completes and hands in the contract (satisfied but still self-interested), " + \
		"and one she says when the pilot abandons mid-contract (annoyed, sharp, but keeps it professional). " + \
		"Reference the specific quest task or faction naturally. Do NOT use generic lines. " + \
		"You MUST respond strictly in valid JSON format. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"completion\": \"[Kaelen's unique completion line]\",\n" + \
		"  \"abandon\": \"[Kaelen's unique abandon line]\"\n" + \
		"}"

	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability("kaelen_line")

	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			print("[LLMInterface] Kaelen reaction fetch failed. Using fallback lines.")
			if _attempts_left > 0:
				print("[LLMInterface] Retrying Kaelen reaction (%d attempts left)." % _attempts_left)
				request_kaelen_reaction(quest_data, callback, _attempts_left - 1)
			else:
				_trigger_kaelen_reaction_fallback(callback, "http_response_failed")
			return

		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(response_text) != OK:
			if _attempts_left > 0:
				request_kaelen_reaction(quest_data, callback, _attempts_left - 1)
			else:
				_trigger_kaelen_reaction_fallback(callback, "response_envelope_parse_failed")
			return

		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			if _attempts_left > 0:
				request_kaelen_reaction(quest_data, callback, _attempts_left - 1)
			else:
				_trigger_kaelen_reaction_fallback(callback, "response_envelope_missing_response")
			return

		var inner_json_str = outer_data["response"].strip_edges()
		if inner_json_str.begins_with("```"):
			var end_idx = inner_json_str.find("\n", 3)
			if end_idx != -1:
				inner_json_str = inner_json_str.substr(end_idx + 1)
			if inner_json_str.ends_with("```"):
				inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
			inner_json_str = inner_json_str.strip_edges()

		var inner_json = JSON.new()
		if inner_json.parse(inner_json_str) != OK:
			if _attempts_left > 0:
				request_kaelen_reaction(quest_data, callback, _attempts_left - 1)
			else:
				_trigger_kaelen_reaction_fallback(callback, "inner_json_parse_failed")
			return

		var reaction_data = inner_json.get_data()
		if reaction_data is Dictionary and reaction_data.has("completion") and reaction_data.has("abandon"):
			var comp_line: String = str(reaction_data["completion"])
			var abn_line: String = str(reaction_data["abandon"])
			if comp_line.contains("[") or abn_line.contains("["):
				if _attempts_left > 0:
					print("[LLMInterface] Kaelen template not filled — retrying (%d attempts left)." % _attempts_left)
					request_kaelen_reaction(quest_data, callback, _attempts_left - 1)
				else:
					_trigger_kaelen_reaction_fallback(callback, "template_placeholder_not_filled")
				return
			print("[LLMInterface] Kaelen reaction lines generated for quest: ", title)
			callback.call(comp_line, abn_line)
		else:
			if _attempts_left > 0:
				request_kaelen_reaction(quest_data, callback, _attempts_left - 1)
			else:
				_trigger_kaelen_reaction_fallback(callback, "reaction_schema_missing_fields")
	)

	var payload: Dictionary = build_generation_body(
		"kaelen_line",
		prompt,
		"json",
		{
			"temperature": 0.9,
			"seed": randi()
		}
	)
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		_trigger_kaelen_reaction_fallback(callback, "http_request_start_failed_%d" % err)

func _trigger_kaelen_reaction_fallback(
	callback: Callable,
	reason: String = "unspecified"
) -> void:
	var context: Dictionary = diagnostics_context_for_capability("kaelen_line")
	GenerationDiagnostics.record_content_source(
		"kaelen_reaction",
		"static_fallback",
		"LLMInterface",
		context.merged({"fallback_reason": reason}, true)
	)
	_record_llm_fallback("kaelen_reaction", reason, context)
	var comp: String = fallback_completion_lines[randi() % fallback_completion_lines.size()]
	var abn: String = fallback_abandon_lines[randi() % fallback_abandon_lines.size()]
	callback.call(comp, abn)


# Returns the 5 example handoff lines for a given agent name, or the DEFAULT
# fallback set if the agent isn't in the map. Used both as few-shot examples
# for the LLM prompt and as the runtime fallback when the LLM is unavailable.
func get_handoff_examples_for_agent(agent_name: String) -> Array:
	if fallback_handoff_lines_by_agent.has(agent_name):
		return fallback_handoff_lines_by_agent[agent_name]
	return fallback_handoff_lines_by_agent["DEFAULT"]


# Returns in-memory counters for the Kaelen intro LLM call. Useful for
# debugging how often the speaker-leakage guard fires and how the
# self-critique retry path is doing. Reset by calling reset_kaelen_intro_stats().
func get_kaelen_intro_stats() -> Dictionary:
	return {
		"attempts": _kaelen_intro_attempts,
		"successes": _kaelen_intro_successes,
		"rejected_first_try": _kaelen_intro_rejected_first_try,
		"rejected_after_retry": _kaelen_intro_rejected_after_retry,
		"network_failures": _kaelen_intro_network_failures,
		"parse_failures": _kaelen_intro_parse_failures,
	}

func reset_kaelen_intro_stats() -> void:
	_kaelen_intro_attempts = 0
	_kaelen_intro_successes = 0
	_kaelen_intro_rejected_first_try = 0
	_kaelen_intro_rejected_after_retry = 0
	_kaelen_intro_network_failures = 0
	_kaelen_intro_parse_failures = 0
	_save_kaelen_intro_stats()


# Load kaelen intro stats from the per-user JSON file. Called once in _ready.
# If the file is missing or corrupted, the counters stay at zero.
func _load_kaelen_intro_stats() -> void:
	if not FileAccess.file_exists(_KAELEN_STATS_PATH):
		return
	var f = FileAccess.open(_KAELEN_STATS_PATH, FileAccess.READ)
	if f == null:
		return
	var raw = f.get_as_text()
	f.close()
	var json = JSON.new()
	if json.parse(raw) != OK:
		return
	var data = json.get_data()
	if not data is Dictionary:
		return
	_kaelen_intro_attempts = int(data.get("attempts", 0))
	_kaelen_intro_successes = int(data.get("successes", 0))
	_kaelen_intro_rejected_first_try = int(data.get("rejected_first_try", 0))
	_kaelen_intro_rejected_after_retry = int(data.get("rejected_after_retry", 0))
	_kaelen_intro_network_failures = int(data.get("network_failures", 0))
	_kaelen_intro_parse_failures = int(data.get("parse_failures", 0))


# Persist the current counters to disk. Called on every increment so a crash
# doesn't lose the data. Failure to write is logged but never fatal — this
# is debug telemetry, not gameplay state.
func _save_kaelen_intro_stats() -> void:
	var data = {
		"attempts": _kaelen_intro_attempts,
		"successes": _kaelen_intro_successes,
		"rejected_first_try": _kaelen_intro_rejected_first_try,
		"rejected_after_retry": _kaelen_intro_rejected_after_retry,
		"network_failures": _kaelen_intro_network_failures,
		"parse_failures": _kaelen_intro_parse_failures,
		"last_updated_unix": int(Time.get_unix_time_from_system()),
	}
	var f = FileAccess.open(_KAELEN_STATS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[LLMInterface] Could not write kaelen intro stats to %s" % _KAELEN_STATS_PATH)
		return
	f.store_string(JSON.stringify(data))
	f.close()


# Print the kaelen intro stats to the console. Useful to call from the
# Godot output panel after a play session to see how the speaker-leakage
# guard and self-critique retry are behaving.
func print_kaelen_intro_stats() -> void:
	var s = get_kaelen_intro_stats()
	print("[LLMInterface] Kaelen intro stats:")
	print("  attempts:                 ", s["attempts"])
	print("  successes:                ", s["successes"])
	print("  rejected_first_try:       ", s["rejected_first_try"], "  (lines that triggered a self-critique retry)")
	print("  rejected_after_retry:     ", s["rejected_after_retry"], "  (lines that fell back to canned after retry)")
	print("  network_failures:         ", s["network_failures"])
	print("  parse_failures:           ", s["parse_failures"])
	if s["attempts"] > 0:
		var success_rate = 100.0 * float(s["successes"]) / float(s["attempts"])
		print("  success_rate:             %.1f%%" % success_rate)
		var retry_save_rate = 0.0
		var retries_attempted = s["rejected_first_try"] + s["rejected_after_retry"]
		if retries_attempted > 0:
			retry_save_rate = 100.0 * float(s["rejected_first_try"] - s["rejected_after_retry"]) / float(retries_attempted)
		print("  retry_save_rate:          %.1f%% (of retries that produced an OK line)" % retry_save_rate)


# Dump the stats on quit. Godot calls _notification(NOTIFICATION_WM_CLOSE_REQUEST)
# when the user closes the window, and NOTIFICATION_PREDELETE before the
# autoload is freed. We save on both so the file is always current.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		print_kaelen_intro_stats()
		_save_kaelen_intro_stats()


# Build the prompt for the unique Kaelen handoff LLM call.
# `correction_suffix` is non-empty only on the self-critique retry — it tells
# the model what it did wrong on the previous attempt so it can course-correct.
func _build_kaelen_intro_prompt(
	agent_name: String,
	faction: String,
	title: String,
	examples_block: String,
	history_clause: String,
	reputation_clause: String,
	local_tone_clause: String,
	story_clause: String,
	correction_suffix: String
) -> String:
	return "You are Broker Kaelen. You are the speaker. " + agent_name + " is the OTHER person — the client you are about to bring in. The pilot is 'Shiny'.\n\n" + \
		"SPEAKER RULE (most important — read carefully):\n" + \
		"  - YOU are Kaelen. First person. You are talking TO the pilot ('Shiny') about " + agent_name + ".\n" + \
		"  - You are NOT " + agent_name + ". " + agent_name + " is silent in this line. " + agent_name + " is the one you're introducing.\n" + \
		"  - NEVER put words in " + agent_name + "'s mouth. If a line you write could be spoken by " + agent_name + " (e.g. 'I'm looking for a pilot...', 'I have a contract...', 'I need...'), DELETE IT and start over.\n" + \
		"  - Kaelen's lines always frame the OTHER person as the actor ('Director Voss has work', 'Captain Dask is waiting', 'Liaison Ryn has a job').\n\n" + \
		"Here are 5 example handoff lines from me (Kaelen), one per typical situation:\n" + examples_block + \
		"\n" + \
		"YOUR TASK: Write ONE NEW handoff line that follows the EXACT same voice, structure, and length as the examples above. Rules:\n" + \
		"  - First-person as Kaelen. NEVER about Kaelen in the third person.\n" + \
		"  - Mention " + agent_name + " by name (third person — the client you're handing off to).\n" + \
		"  - Address 'Shiny' directly OR start with action framing (see examples).\n" + \
		"  - Under 25 words. One sentence. No line breaks.\n" + \
		"  - Tone: dry, transactional, faintly condescending, but professional. No poetry, no metaphors, no invented nouns.\n" + \
		"  - Do NOT copy any example verbatim. Write a genuinely new line.\n" + \
		"  - Do NOT invent factions, places, ships, jobs, or details not present in the pilot's history, the examples, or the reputation data.\n" + \
		history_clause + "\n" + \
		reputation_clause + "\n" + \
		local_tone_clause + "\n" + \
		story_clause + \
		correction_suffix + "\n" + \
		"You MUST respond strictly in valid JSON format. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"intro\": \"[Kaelen's new handoff line]\"\n" + \
		"}"


# Validate a generated handoff line against the speaker-leakage rules.
# Returns "" if the line is OK, or a short reason string if it should be
# rejected. The reason string doubles as the correction_suffix on the retry.
func _check_kaelen_intro_speaker(line: String, agent_name: String) -> String:
	var lower = line.to_lower()
	var has_shiny = lower.find("shiny") != -1 or lower.find("contractor") != -1 or lower.find("merc") != -1 or lower.find("ghost") != -1
	var agent_lower = agent_name.to_lower()
	# Does the line open with the agent's name (with optional punctuation)?
	var opens_with_agent = lower.begins_with(agent_lower + "?") or lower.begins_with(agent_lower + ".") or lower.begins_with(agent_lower + " ") or lower.begins_with(agent_lower + ",")
	# If the line opens with the agent AND the agent then speaks first-person,
	# that's the leak we saw in production.
	var agent_speaks_first_person = false
	var after_name_pos = lower.find(agent_lower)
	if after_name_pos != -1 and after_name_pos < 8:
		var tail = lower.substr(after_name_pos + agent_lower.length(), 12)
		if tail.begins_with("? i ") or tail.begins_with(". i ") or tail.begins_with(", i ") or tail.begins_with("? i'") or tail.begins_with(". i'"):
			agent_speaks_first_person = true
	if opens_with_agent and agent_speaks_first_person:
		return "Your previous line had " + agent_name + " speaking as themselves (\"" + line + "\"). Try again, Kaelen only. Mention " + agent_name + " in the THIRD person — they should be silent in your line."
	# No Shiny-address AND no agent-name reference — model went off the rails.
	if not has_shiny and not opens_with_agent:
		return "Your previous line was missing both 'Shiny' and any mention of " + agent_name + ". Try again, Kaelen only, with one or both anchors present."
	# First-person without pilot-address is the agent speaking as themselves.
	var has_first_person = lower.begins_with("i am ") or lower.begins_with("i'm ") or lower.find(" i have ") != -1 or lower.find(" i need ") != -1 or lower.find(" i'm looking") != -1
	if has_first_person and not has_shiny:
		return "Your previous line used first-person speech without addressing 'Shiny' (\"" + line + "\"). Kaelen always talks TO Shiny, not about herself. Try again."
	return ""  # OK


func _kaelen_local_tone_clause(quest_data: Dictionary) -> String:
	var raw_pack: Variant = quest_data.get("system_story_pack", {})
	if not raw_pack is Dictionary:
		return ""
	var story_pack := raw_pack as Dictionary
	var humor_guidance := str(story_pack.get("humor_guidance", "")).strip_edges()
	var tension := str(story_pack.get("active_tension", "")).strip_edges()
	var nickname := str(story_pack.get("local_nickname", "")).strip_edges()
	if humor_guidance.is_empty() and tension.is_empty() and nickname.is_empty():
		return ""
	var parts: Array[String] = []
	if not nickname.is_empty():
		parts.append("System nickname: " + nickname)
	if not tension.is_empty():
		parts.append("Local tension: " + tension)
	if not humor_guidance.is_empty():
		parts.append("Local humor guidance: " + humor_guidance)
	return (
		"Local system tone for Kaelen's handoff: "
		+ "; ".join(parts)
		+ ". Use this only for flavor; do not add extra lore or mission facts."
	)


# Generate a unique Kaelen handoff line that introduces the upcoming quest giver.
# `agent_history_text` is a short filtered list of this pilot's prior contracts
# with the given quest giver, so the intro can naturally call back to it.
# If history is empty, Kaelen plays a neutral first-time-intro.
# Returns a single short line (<= 25 words) to the callback.
func request_kaelen_intro(quest_data: Dictionary, agent_history_text: String, player_reps: Dictionary, callback: Callable):
	var title = quest_data.get("title", "the contract")
	var faction = quest_data.get("faction", "neutral").capitalize()
	var agent_name = quest_data.get("agent_name", "Broker Kaelen")

	# Build the few-shot examples block. Numbered for clarity so the model
	# doesn't try to interpret them as instructions.
	var examples = get_handoff_examples_for_agent(agent_name)
	var examples_block = ""
	for i in range(examples.size()):
		examples_block += "  %d. \"%s\"\n" % [i + 1, examples[i]]

	# Build the history clause — distinguishes "no track record" from "long history"
	var history_clause: String
	if agent_history_text.strip_edges() == "":
		history_clause = "The pilot has not worked with " + agent_name + " before — write a NEUTRAL first-intro in the same tone as the examples. Do NOT invent prior jobs."
	else:
		history_clause = "Here is the pilot's prior history with " + agent_name + ":\n" + agent_history_text + \
			"\nYou may reference ONE item from this history in a short clause (reliability, payment disputes, a specific past job). Do NOT recap the whole list. Do NOT invent history not listed above."

	# Build the reputation clause — gives Kaelen awareness of the pilot's
	# political situation so she can color her tone about the upcoming agent
	# AND give broader relationship advice (e.g. "you've made a lot of enemies,
	# could use a few more friends with Vanguard"). Each faction shows a
	# numeric rep plus a semantic tier label — 1.5b models pattern-match on
	# the labels far better than on the raw numbers alone.
	# 9 tiers: sworn enemy / hostile / unfriendly / wary | neutral | cordial / friendly / trusted / allied.
	var reputation_clause = "Pilot's current faction standing (number + tier label):\n" + \
		"- Zenith: " + str(int(player_reps.get("zenith", 0))) + " (" + GlobalState.reputation_tier(player_reps.get("zenith", 0)) + ")\n" + \
		"- Aurelia: " + str(int(player_reps.get("aurelia", 0))) + " (" + GlobalState.reputation_tier(player_reps.get("aurelia", 0)) + ")\n" + \
		"- Vanguard: " + str(int(player_reps.get("vanguard", 0))) + " (" + GlobalState.reputation_tier(player_reps.get("vanguard", 0)) + ")\n\n" + \
		"Kaelen may use this to:\n" + \
		"  - Color her tone about the upcoming agent — the tier label is the anchor. Negative tiers (wary → sworn enemy) get a colder, sharper register; positive tiers (cordial → allied) get a warmer, more respectful register. Match the register to the tier, do not invent a tone the label doesn't justify.\n" + \
		"  - Comment on the pilot's broader social position — e.g. note that the pilot has made a lot of enemies and could use a few more friends with a particular faction, warn about a hostile faction, or contrast the pilot's friendly vs hostile relationships.\n\n" + \
		"Kaelen is a broker — she has opinions on the pilot's political situation. Do NOT invent tiers or numbers not listed above."

	# Draw from pre-generated pool first — instant, no LLM call.
	if is_instance_valid(StoryManager):
		var pooled_line: String = StoryManager.draw_kaelen_handoff(agent_name)
		if pooled_line != "":
			print("[LLMInterface] Kaelen handoff: served from pool for %s" % agent_name)
			callback.call(pooled_line)
			return

	var local_tone_clause := _kaelen_local_tone_clause(quest_data)

	var story_clause := ""
	if story_state_context_text.strip_edges() != "":
		story_clause = (
			"Narrative context (do NOT quote or expose this directly — let it color tone and urgency only):\n"
			+ story_state_context_text + "\n"
		)

	# First attempt. If the response fails the speaker-leakage guard, we
	# retry ONCE with a correction suffix that tells the model what it did
	# wrong. After that, we hard-fall-back to canned (caller picks from
	# fallback_handoff_lines_by_agent).
	_kaelen_intro_request_attempt(agent_name, title, faction, examples_block, history_clause, reputation_clause, local_tone_clause, story_clause, "", 0, callback)


# Internal: make one LLM call for the handoff intro. `attempt` is 0 on the
# first try, 1 on the self-critique retry. Total cap is 2 attempts — beyond
# that the caller falls back to a canned line.
func _kaelen_intro_request_attempt(agent_name: String, title: String, faction: String, examples_block: String, history_clause: String, reputation_clause: String, local_tone_clause: String, story_clause: String, correction_suffix: String, attempt: int, original_callback: Callable):
	var prompt = _build_kaelen_intro_prompt(agent_name, faction, title, examples_block, history_clause, reputation_clause, local_tone_clause, story_clause, correction_suffix)

	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability("kaelen_line")

	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			_kaelen_intro_network_failures += 1
			_save_kaelen_intro_stats()
			print("[LLMInterface] Kaelen intro fetch failed (network). Caller should fall back.")
			_trigger_kaelen_intro_fallback(
				original_callback,
				"http_response_failed",
				agent_name,
				title,
				faction
			)
			return

		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(response_text) != OK:
			_kaelen_intro_parse_failures += 1
			_save_kaelen_intro_stats()
			print("[LLMInterface] Kaelen intro fetch failed (outer JSON parse). Caller should fall back.")
			_trigger_kaelen_intro_fallback(
				original_callback,
				"response_envelope_parse_failed",
				agent_name,
				title,
				faction
			)
			return

		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			_kaelen_intro_parse_failures += 1
			_save_kaelen_intro_stats()
			_trigger_kaelen_intro_fallback(
				original_callback,
				"response_envelope_missing_response",
				agent_name,
				title,
				faction
			)
			return

		var inner_json_str = outer_data["response"].strip_edges()
		if inner_json_str.begins_with("```"):
			var end_idx = inner_json_str.find("\n", 3)
			if end_idx != -1:
				inner_json_str = inner_json_str.substr(end_idx + 1)
			if inner_json_str.ends_with("```"):
				inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
			inner_json_str = inner_json_str.strip_edges()

		var inner_json = JSON.new()
		if inner_json.parse(inner_json_str) != OK:
			_kaelen_intro_parse_failures += 1
			_save_kaelen_intro_stats()
			print("[LLMInterface] Kaelen intro fetch failed (inner JSON parse). Caller should fall back.")
			_trigger_kaelen_intro_fallback(
				original_callback,
				"inner_json_parse_failed",
				agent_name,
				title,
				faction
			)
			return

		var intro_data = inner_json.get_data()
		if not (intro_data is Dictionary and intro_data.has("intro") and intro_data["intro"] is String):
			_kaelen_intro_parse_failures += 1
			_save_kaelen_intro_stats()
			_trigger_kaelen_intro_fallback(
				original_callback,
				"intro_schema_missing_line",
				agent_name,
				title,
				faction
			)
			return

		var line: String = intro_data["intro"].strip_edges()
		if line == "":
			_trigger_kaelen_intro_fallback(
				original_callback,
				"empty_intro_line",
				agent_name,
				title,
				faction
			)
			return

		# ── Speaker-leakage guard ──────────────────────────────────────────
		# Defense in depth against the LLM slipping into the wrong voice
		# (e.g. producing a line where Captain Dask is the speaker instead
		# of Kaelen). The prompt asks the model to stay as Kaelen, but a
		# small model (1.5b) sometimes pattern-matches the *content* of
		# the few-shot examples rather than the *speaker*. We catch the
		# common failure shapes here. If the line fails, we retry ONCE
		# with a self-critique suffix (capped at attempt=1) so the model
		# can see what it did wrong and try again.
		var rejection_reason = _check_kaelen_intro_speaker(line, agent_name)
		if rejection_reason != "":
			print("[LLMInterface] ⚠ Kaelen intro attempt ", attempt, " REJECTED: ", rejection_reason, " Line was: \"", line, "\"")
			if attempt >= 1:
				# Already retried once. Give up — caller falls back to canned.
				_kaelen_intro_rejected_after_retry += 1
				_save_kaelen_intro_stats()
				print("[LLMInterface] Kaelen intro: giving up after retry. Caller should fall back.")
				_trigger_kaelen_intro_fallback(
					original_callback,
					"speaker_guard_rejected_after_retry",
					agent_name,
					title,
					faction
				)
				return
			_kaelen_intro_rejected_first_try += 1
			# Build a correction suffix from the rejection reason and retry.
			var new_suffix = "SELF-CRITIQUE — your previous attempt was rejected. Reason: " + rejection_reason
			print("[LLMInterface] Kaelen intro: retrying with self-critique correction...")
			_kaelen_intro_request_attempt(agent_name, title, faction, examples_block, history_clause, reputation_clause, local_tone_clause, story_clause, new_suffix, attempt + 1, original_callback)
			return

		_kaelen_intro_successes += 1
		_save_kaelen_intro_stats()
		print("[LLMInterface] Kaelen unique intro generated for: ", agent_name, " (", title, "): ", line)
		original_callback.call(line)
	)

	_kaelen_intro_attempts += 1
	var payload: Dictionary = build_generation_body(
		"kaelen_line",
		prompt,
		"json",
		{
			"temperature": 0.9,
			"seed": randi()
		}
	)
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		_kaelen_intro_network_failures += 1
		_save_kaelen_intro_stats()
		print("[LLMInterface] Kaelen intro fetch failed (request init). Caller should fall back.")
		_trigger_kaelen_intro_fallback(
			original_callback,
			"http_request_start_failed_%d" % err,
			agent_name,
			title,
			faction
		)


func _trigger_kaelen_intro_fallback(
	callback: Callable,
	reason: String,
	agent_name: String,
	title: String,
	faction: String
) -> void:
	_record_llm_fallback(
		"kaelen_handoff_intro",
		reason,
		{
			"agent_name": agent_name,
			"title": title,
			"faction": faction,
		}
	)
	if callback.is_valid():
		callback.call("")


func _trigger_salvager_profile_fallback(
	callback: Callable,
	reason: String = "unspecified"
) -> void:
	_record_llm_fallback("salvager_profile", reason)
	var rand_name: String = fallback_salvager_names[randi() % fallback_salvager_names.size()]
	var rand_backstory: String = fallback_salvager_backstories[randi() % fallback_salvager_backstories.size()]
	var profile = {
		"name": rand_name,
		"backstory": rand_backstory
	}
	_call_salvager_profile_callback(callback, profile)

# Fallback lines for when Kaelen acknowledges a partial ore drop-off
var fallback_partial_delivery_lines = [
	"I'll set this aside for you, Shiny. But don't get comfortable — my client wants the rest, and they're not patient people.",
	"Noted. I'll log it against your contract. You've still got a haul to finish, so stop wasting time chatting with me.",
	"Banking what you've got. Get the rest of that ore before my client starts asking questions I can't answer.",
	"Partial logged. My client is going to ask when the shipment is complete, and 'almost' isn't a number they recognise.",
	"Fine, I'll hold it. But I'm not a warehouse, Shiny — get out there and finish the run.",
]

# Generate a unique Kaelen line for a partial ore delivery.
# delivered_amount: m³ just dropped off now. total_banked: cumulative m³ banked so far. total_required: full contract amount.
func request_partial_delivery_line(quest_title: String, delivered_amount: float, total_banked: float, total_required: float, callback: Callable):
	var remaining = max(0.0, total_required - total_banked)
	var pct = int(clamp(total_banked / total_required * 100.0, 0.0, 99.0))

	var prompt = "You are Broker Kaelen, a cynical profit-driven space broker. You call the pilot 'Shiny'. " + \
		"The pilot just dropped off %.0f m³ of ore as a partial shipment for the contract '%s'. " % [delivered_amount, quest_title] + \
		"They have now delivered %.0f / %.0f m³ total (%d%% done). They still owe %.0f m³ more. " % [total_banked, total_required, pct, remaining] + \
		"Generate ONE short line of dialogue from Kaelen (under 25 words) reacting to this. " + \
		"She should: acknowledge she's holding it for them, mention the remaining amount or urgency, and be characteristically impatient or wry. " + \
		"Reference the specific numbers. PG-13 tone — she can be sharp. Do NOT use generic lines. " + \
		"You MUST respond strictly in valid JSON format. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"line\": \"[Kaelen's unique partial delivery line]\"\n" + \
		"}"

	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability("partial_delivery_line")

	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			_trigger_partial_delivery_fallback(callback, "http_response_failed")
			return

		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(response_text) != OK:
			_trigger_partial_delivery_fallback(callback, "response_envelope_parse_failed")
			return

		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			_trigger_partial_delivery_fallback(callback, "response_envelope_missing_response")
			return

		var inner_json_str = outer_data["response"].strip_edges()
		if inner_json_str.begins_with("```"):
			var end_idx = inner_json_str.find("\n", 3)
			if end_idx != -1:
				inner_json_str = inner_json_str.substr(end_idx + 1)
			if inner_json_str.ends_with("```"):
				inner_json_str = inner_json_str.substr(0, inner_json_str.length() - 3)
			inner_json_str = inner_json_str.strip_edges()

		var inner_json = JSON.new()
		if inner_json.parse(inner_json_str) != OK:
			_trigger_partial_delivery_fallback(callback, "inner_json_parse_failed")
			return

		var data = inner_json.get_data()
		if data is Dictionary and data.has("line") and data["line"] is String and data["line"].length() > 3:
			callback.call(data["line"])
		else:
			_trigger_partial_delivery_fallback(callback, "partial_delivery_schema_missing_line")
	)

	var payload: Dictionary = build_generation_body(
		"partial_delivery_line",
		prompt,
		"json",
		{
			"temperature": 0.92,
			"seed": randi()
		}
	)
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		_trigger_partial_delivery_fallback(
			callback,
			"http_request_start_failed_%d" % err
		)


func _trigger_partial_delivery_fallback(
	callback: Callable,
	reason: String = "unspecified"
) -> void:
	_record_llm_fallback("partial_delivery_line", reason)
	if callback.is_valid():
		callback.call(
			fallback_partial_delivery_lines[
				randi() % fallback_partial_delivery_lines.size()
			]
		)


func generate_campaign_system_names(count: int, callback: Callable):
	if OLLAMA_URL.is_empty() or model_for_capability("system_names").is_empty():
		callback.call([])
		return
	var prompt := (
		"Generate %d unique star system names for a space exploration game. "
		+ "Each name should feel like a real place — evocative, varied, 1-3 words. "
		+ "Mix styles: some mythological, some geographic, some industrial. "
		+ "Return a JSON object with a single key \"names\" containing an array of strings. "
		+ "No numbering, no duplicates."
	) % count
	var payload: Dictionary = build_generation_body(
		"system_names",
		prompt,
		"json",
		{
			"temperature": 1.0,
			"seed": randi()
		}
	)
	var temp_http := HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability("system_names")
	temp_http.request_completed.connect(
		func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
			temp_http.queue_free()
			if code != 200:
				callback.call([])
				return
			var parsed = JSON.parse_string(body.get_string_from_utf8())
			if parsed is Dictionary:
				var response_text: String = str(parsed.get("response", ""))
				var inner = JSON.parse_string(response_text)
				if inner is Dictionary and inner.has("names") and inner["names"] is Array:
					var names: Array[String] = []
					for n in inner["names"]:
						var s := str(n).strip_edges()
						if not s.is_empty() and s.length() <= 30:
							names.append(s)
					if names.size() >= count / 2:
						callback.call(names)
						return
			callback.call([])
	)
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var name_err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if name_err != OK:
		temp_http.queue_free()
		callback.call([])


# ── Kaelen Bounty Brief ───────────────────────────────────────────────────────

func fetch_bounty_brief(
	system_id: String,
	factions: Array,
	callback: Callable,
	_attempts_left: int = 1
) -> void:
	var day_number: int = int(GlobalState.get("day_number")) if GlobalState.get("day_number") != null else 1
	var rep_lines: Array = []
	for f in factions:
		var rep: int = int(GlobalState.reputations.get(f, 0))
		rep_lines.append("%s (rep %d)" % [f, rep])
	var factions_str := ", ".join(rep_lines)

	var prompt := (
		"You are Broker Kaelen, a cynical space broker. Today is day %d. "
		+ "The player is operating in system '%s'. "
		+ "Minor factions active in this system: %s. "
		+ "Pick 1–2 of these factions to place standing bounties on. "
		+ "For each bounty write one short sentence in Kaelen's voice explaining WHY she wants them hit (personal, mercenary, never moral). "
		+ "Suggest a payout between 7 and 15 SC per kill (after your cut) and a cap between 3 and 10 kills. "
		+ "Respond ONLY in valid JSON:\n"
		+ "{\n"
		+ "  \"bounties\": [\n"
		+ "    { \"faction\": \"<faction_id>\", \"payout\": <int>, \"cap\": <int>, \"kaelen_line\": \"<one sentence>\" }\n"
		+ "  ]\n"
		+ "}"
	) % [day_number, system_id, factions_str]

	var temp_http := HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability("kaelen_line")

	temp_http.request_completed.connect(func(result, response_code, _headers, body):
		temp_http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			if _attempts_left > 0:
				fetch_bounty_brief(system_id, factions, callback, _attempts_left - 1)
			else:
				_trigger_bounty_brief_fallback(factions, callback, "http_failed")
			return

		var outer_json := JSON.new()
		if outer_json.parse(body.get_string_from_utf8()) != OK:
			if _attempts_left > 0:
				fetch_bounty_brief(system_id, factions, callback, _attempts_left - 1)
			else:
				_trigger_bounty_brief_fallback(factions, callback, "envelope_parse_failed")
			return
		var outer_data = outer_json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			if _attempts_left > 0:
				fetch_bounty_brief(system_id, factions, callback, _attempts_left - 1)
			else:
				_trigger_bounty_brief_fallback(factions, callback, "envelope_missing_response")
			return

		var inner_str: String = str(outer_data["response"]).strip_edges()
		if inner_str.begins_with("```"):
			var end_idx := inner_str.find("\n", 3)
			if end_idx != -1:
				inner_str = inner_str.substr(end_idx + 1)
			if inner_str.ends_with("```"):
				inner_str = inner_str.substr(0, inner_str.length() - 3)
			inner_str = inner_str.strip_edges()

		var inner_json := JSON.new()
		if inner_json.parse(inner_str) != OK:
			if _attempts_left > 0:
				fetch_bounty_brief(system_id, factions, callback, _attempts_left - 1)
			else:
				_trigger_bounty_brief_fallback(factions, callback, "inner_parse_failed")
			return
		var inner_data = inner_json.get_data()
		if not inner_data is Dictionary or not inner_data.has("bounties") or not inner_data["bounties"] is Array:
			if _attempts_left > 0:
				fetch_bounty_brief(system_id, factions, callback, _attempts_left - 1)
			else:
				_trigger_bounty_brief_fallback(factions, callback, "inner_schema_failed")
			return

		var bounties: Array = []
		var known_factions: Array = GlobalState.MINOR_FACTIONS.keys()
		for entry in inner_data["bounties"]:
			if not entry is Dictionary:
				continue
			var f: String = str(entry.get("faction", "")).strip_edges()
			if f not in known_factions:
				continue
			var payout: int = clampi(int(entry.get("payout", 8)), 5, 20)
			var cap: int = clampi(int(entry.get("cap", 5)), 1, 15)
			var line: String = str(entry.get("kaelen_line", "")).strip_edges()
			if line.contains("[") or line.is_empty():
				line = "I've got my reasons. %d SC a hull, after my cut." % payout
			bounties.append({
				"faction": f,
				"system_id": system_id,
				"payout_per_kill": payout,
				"cap": cap,
				"kills_credited": 0,
				"kaelen_line": line,
			})
		if bounties.is_empty():
			_trigger_bounty_brief_fallback(factions, callback, "no_valid_bounties")
			return
		callback.call(bounties)
	)

	var payload := build_generation_body(
		"kaelen_line",
		prompt,
		"json",
		{ "temperature": 0.9, "seed": randi() }
	)
	var headers := ["Content-Type: application/json"]
	var err := temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		temp_http.queue_free()
		_trigger_bounty_brief_fallback(factions, callback, "request_start_failed_%d" % err)


func _trigger_bounty_brief_fallback(factions: Array, callback: Callable, reason: String) -> void:
	print("[LLMInterface] Bounty brief fallback: ", reason)
	if factions.is_empty():
		callback.call([])
		return
	var f: String = factions[randi() % factions.size()]
	var faction_label: String = f.capitalize()
	var fallback_lines := [
		"The %s hit a shipment I had a stake in. I want receipts." % faction_label,
		"Old business with the %s. Nothing you need to know, just act on it." % faction_label,
		"Client wants %s hulls. Don't ask who. Eight SC a kill, after my finder's fee." % faction_label,
		"The %s are running interference on a deal I'm closing. I'd like that to stop." % faction_label,
	]
	var line: String = fallback_lines[randi() % fallback_lines.size()]
	callback.call([{
		"faction": f,
		"system_id": GlobalState.current_system_id,
		"payout_per_kill": 8,
		"cap": 5,
		"kills_credited": 0,
		"kaelen_line": line,
	}])


# ── Combat taunt generation ───────────────────────────────────────────────────
# Called once at the start of each combat encounter. Returns a Dictionary with
# 11 pre-generated lines covering every taunt event in the fight. Falls back
# to hardcoded lines if the LLM is unavailable.
#
# callback signature: func(taunts: Dictionary) -> void
# Keys: npc_open, npc_player_fled_success, npc_player_fled_fail,
#       npc_low_health, player_low_health, npc_dying,
#       npc_brace, npc_shield_angle, npc_reposition, npc_enemy_fled,
#       kaelen_open, kaelen_player_fled, kaelen_player_low_health,
#       kaelen_winning, kaelen_kill_confirm

const COMBAT_TAUNT_FALLBACKS := {
	"npc_open":               "You picked the wrong ship, you scrap-brained idiot.",
	"npc_jab_1":              "That all you've got, you pathetic scrap-rat?",
	"npc_jab_2":              "I've fought asteroids with more spine than you.",
	"npc_jab_3":              "Still breathing, scumbag? Let's fix that.",
	"npc_player_fled_success":"Run, coward. I'll hunt you down.",
	"npc_player_fled_fail":   "Nowhere to run now, moron.",
	"npc_low_health":         "Lucky shot. Won't happen twice, idiot.",
	"player_low_health":      "You're falling apart, you worthless junk-heap.",
	"npc_dying":              "...didn't see that coming.",
	"npc_brace":              "You'll break your fists on me.",
	"npc_shield_angle":       "Angles up. Good luck.",
	"npc_reposition":         "Try keeping up, scrap-rat.",
	"npc_enemy_fled":         "I'm out. Tell somebody impressive I almost cared.",
	"npc_boss_phase_2":       "Still standing? Fine. Now I get serious.",
	"npc_boss_phase_3":       "You want to see what I'm really capable of?",
	"kaelen_open":            "Shiny, you have company. Try not to die — I'm owed money.",
	"kaelen_player_fled":     "Smart. Heroics don't pay the docking fees.",
	"kaelen_player_low_health": "Shiny, you look terrible on my sensors right now.",
	"kaelen_winning":         "Wrap it up — salvage fees are yours if you're fast.",
	"kaelen_kill_confirm":    "One less headache. Logging the kill now.",
}

func request_combat_taunts(npc_faction: String, npc_archetype: String, callback: Callable, _attempt: int = 0) -> void:
	var faction_cap := npc_faction.capitalize()
	var arch_cap   := npc_archetype.capitalize()

	var prompt := """You are writing combat banter for a gritty space combat game. Generate exactly 20 short lines of dialogue — punchy, under 18 words each. Do NOT use placeholder brackets.

There are TWO speakers. Write each line for the correct one:

1) THE ENEMY PILOT — every key starting with "npc_". A hostile %s %s who has NEVER met the player and does NOT know their name. They are a furious stranger trash-talking whoever just attacked them. Use crude, contemptuous insults aimed at the player ("scrap-rat", "you absolute idiot", "listen here, you piece of garbage", "scumbag", "moron"). Mild profanity is fine. NEVER use any name or nickname — they have no idea who the player is. Pure hostility and threats, zero familiarity.

2) KAELEN — every key starting with "kaelen_". The player's cynical, money-minded broker watching the fight over comms. Kaelen KNOWS the player and calls them "Shiny". Dry, sardonic, keep Kaelen's lines clean (PG-13). Kaelen never insults the player crudely — that's the enemy's job.

Tone examples (do not reuse — match the energy):
- enemy: "You call that a weapon? My recycling drone hits harder, idiot."
- enemy: "Hold still and die quiet, scrap-rat."
- enemy fleeing: "I'm out of here. Tell your crew I said sorry about the mess."
- kaelen: "Shiny, don't get sentimental. Just get paid."

Return ONLY valid JSON, no markdown fences:
{
  "npc_open": "...",
  "npc_jab_1": "...",
  "npc_jab_2": "...",
  "npc_jab_3": "...",
  "npc_player_fled_success": "...",
  "npc_player_fled_fail": "...",
  "npc_low_health": "...",
  "player_low_health": "...",
  "npc_dying": "...",
  "npc_brace": "...",
  "npc_shield_angle": "...",
  "npc_reposition": "...",
  "npc_enemy_fled": "...",
  "npc_boss_phase_2": "...",
  "npc_boss_phase_3": "...",
  "kaelen_open": "...",
  "kaelen_player_fled": "...",
  "kaelen_player_low_health": "...",
  "kaelen_winning": "...",
  "kaelen_kill_confirm": "..."
}""" % [faction_cap, arch_cap]

	var temp_http := HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability("kaelen_line")

	temp_http.request_completed.connect(func(result, response_code, _headers, body):
		temp_http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			if _attempt == 0:
				push_warning("[TAUNT FALLBACK RISK] combat taunts HTTP failed (result=%d code=%d) for %s %s — retrying in 3s" % [result, response_code, faction_cap, arch_cap])
				get_tree().create_timer(3.0, true, false, true).timeout.connect(
					func(): request_combat_taunts(npc_faction, npc_archetype, callback, 1))
				return
			_log_combat_taunt_fallback("http_failed", faction_cap, arch_cap,
				{"result": result, "response_code": response_code})
			callback.call(COMBAT_TAUNT_FALLBACKS.duplicate())
			return

		var response_text: String = body.get_string_from_utf8()
		var outer_json := JSON.new()
		if outer_json.parse(response_text) != OK:
			_log_combat_taunt_fallback("outer_json_parse_failed", faction_cap, arch_cap,
				{"raw_length": response_text.length()})
			callback.call(COMBAT_TAUNT_FALLBACKS.duplicate())
			return

		var outer_data = outer_json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			_log_combat_taunt_fallback("missing_response_key", faction_cap, arch_cap, {})
			callback.call(COMBAT_TAUNT_FALLBACKS.duplicate())
			return

		var inner_str: String = outer_data["response"].strip_edges()
		if inner_str.begins_with("```"):
			var end_idx := inner_str.find("\n", 3)
			if end_idx != -1:
				inner_str = inner_str.substr(end_idx + 1)
			if inner_str.ends_with("```"):
				inner_str = inner_str.substr(0, inner_str.length() - 3)
			inner_str = inner_str.strip_edges()

		var inner_json := JSON.new()
		if inner_json.parse(inner_str) != OK:
			_log_combat_taunt_fallback("inner_json_parse_failed", faction_cap, arch_cap,
				{"snippet": inner_str.substr(0, 80)})
			callback.call(COMBAT_TAUNT_FALLBACKS.duplicate())
			return

		var data = inner_json.get_data()
		if not data is Dictionary:
			_log_combat_taunt_fallback("response_not_dict", faction_cap, arch_cap, {})
			callback.call(COMBAT_TAUNT_FALLBACKS.duplicate())
			return

		# Merge into fallback dict — only override keys where LLM produced a real line.
		var result_dict := COMBAT_TAUNT_FALLBACKS.duplicate()
		var llm_count := 0
		for key in result_dict.keys():
			if data.has(key) and str(data[key]).length() > 0 and not str(data[key]).contains("["):
				result_dict[key] = str(data[key])
				llm_count += 1
		# Warn if the LLM barely filled anything — partial fallback still happened.
		if llm_count < result_dict.size() / 2:
			push_warning("[TAUNT FALLBACK] combat taunts partial: only %d/%d keys filled for %s %s" % [
				llm_count, result_dict.size(), faction_cap, arch_cap])
		print("[LLMInterface] Combat taunts: %d/%d lines filled for %s %s" % [
			llm_count, result_dict.size(), faction_cap, arch_cap])
		callback.call(result_dict)
	)

	var payload: Dictionary = build_generation_body(
		"kaelen_line",
		prompt,
		"json",
		{"temperature": 0.95, "seed": randi()}
	)
	var err := temp_http.request(OLLAMA_URL, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		temp_http.queue_free()
		if _attempt == 0:
			push_warning("[TAUNT FALLBACK RISK] combat taunts request() error=%d for %s %s — retrying in 3s" % [err, faction_cap, arch_cap])
			get_tree().create_timer(3.0, true, false, true).timeout.connect(
				func(): request_combat_taunts(npc_faction, npc_archetype, callback, 1))
			return
		_log_combat_taunt_fallback("request_error", faction_cap, arch_cap, {"err": err})
		callback.call(COMBAT_TAUNT_FALLBACKS.duplicate())

func _log_combat_taunt_fallback(reason: String, faction: String, archetype: String, ctx: Dictionary) -> void:
	var msg := "[TAUNT FALLBACK] combat taunts fell back to canned lines — reason: %s | %s %s" % [reason, faction, archetype]
	push_warning(msg)
	print(msg)
	var diag_node = get_tree().root.get_node_or_null("GenerationDiagnostics")
	if diag_node:
		diag_node.record_fallback("combat_taunts", reason, "LLMInterface",
			ctx.merged({"reason": reason, "faction": faction, "archetype": archetype}, true))

## Request a batch of generic combat taunts (not faction-specific) for the
## general opening-taunt pool. Returns {"rage":[...], "reason":[...], "humor":[...]}.
## Retries once before giving up; logs with push_warning on failure.
func request_general_taunts(callback: Callable, _attempt: int = 0) -> void:
	var prompt := """You are writing combat banter for a gritty space game. Generate exactly 12 short combat one-liners. Under 15 words each. No placeholder brackets. No names.

Three categories:
- "rage" (6 lines): enemy is furious the player shot first — pure hostility and threats ("you absolute idiot", "you're dead", "wrong move").
- "reason" (3 lines): enemy is the aggressor, contemptuous and confident they'll win.
- "humor" (3 lines): absurd comedic insults with the same angry delivery — the contrast is the joke.

All lines are from a hostile enemy pilot to an anonymous stranger. Mild profanity fine. Never use names.

Return ONLY valid JSON, no markdown:
{"rage": ["...", "...", "...", "...", "...", "..."], "reason": ["...", "...", "..."], "humor": ["...", "...", "..."]}"""

	var temp_http := HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability("kaelen_line")

	temp_http.request_completed.connect(func(result, response_code, _headers, body):
		temp_http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			if _attempt == 0:
				push_warning("[TAUNT FALLBACK RISK] general taunts HTTP failed (result=%d code=%d) — retrying in 3s" % [result, response_code])
				get_tree().create_timer(3.0, true, false, true).timeout.connect(
					func(): request_general_taunts(callback, 1))
				return
			var msg := "[TAUNT FALLBACK] general taunts failed after retry — HTTP result=%d code=%d. Canned pool only." % [result, response_code]
			push_warning(msg)
			print(msg)
			callback.call({})
			return
		var response_text: String = body.get_string_from_utf8()
		var outer_json := JSON.new()
		if outer_json.parse(response_text) != OK:
			var msg := "[TAUNT FALLBACK] general taunts outer JSON parse failed. Canned pool only."
			push_warning(msg)
			print(msg)
			callback.call({})
			return
		var outer_data = outer_json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			var msg := "[TAUNT FALLBACK] general taunts missing 'response' key. Canned pool only."
			push_warning(msg)
			print(msg)
			callback.call({})
			return
		var inner_str: String = outer_data["response"].strip_edges()
		if inner_str.begins_with("```"):
			var end_idx := inner_str.find("\n", 3)
			if end_idx != -1:
				inner_str = inner_str.substr(end_idx + 1)
			if inner_str.ends_with("```"):
				inner_str = inner_str.substr(0, inner_str.length() - 3)
			inner_str = inner_str.strip_edges()
		var inner_json := JSON.new()
		if inner_json.parse(inner_str) != OK:
			var msg := "[TAUNT FALLBACK] general taunts inner JSON parse failed. Canned pool only."
			push_warning(msg)
			print(msg)
			callback.call({})
			return
		var data = inner_json.get_data()
		if not data is Dictionary:
			var msg := "[TAUNT FALLBACK] general taunts response not a dict. Canned pool only."
			push_warning(msg)
			print(msg)
			callback.call({})
			return
		# Validate each array — strip anything with brackets (placeholders).
		var out := {"rage": [], "reason": [], "humor": []}
		for cat in out.keys():
			if data.has(cat) and data[cat] is Array:
				for line in data[cat]:
					var s := str(line).strip_edges()
					if s.length() > 4 and not s.contains("["):
						out[cat].append(s)
		var total: int = out["rage"].size() + out["reason"].size() + out["humor"].size()
		if total == 0:
			var msg := "[TAUNT FALLBACK] general taunts returned 0 valid lines. Canned pool only."
			push_warning(msg)
			print(msg)
			callback.call({})
			return
		print("[LLMInterface] General taunts: %d rage, %d reason, %d humor" % [
			out["rage"].size(), out["reason"].size(), out["humor"].size()])
		callback.call(out)
	)
	var payload := build_generation_body("kaelen_line", prompt, "json",
		{"temperature": 1.0, "seed": randi()})
	var err2 := temp_http.request(OLLAMA_URL, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err2 != OK:
		temp_http.queue_free()
		if _attempt == 0:
			push_warning("[TAUNT FALLBACK RISK] general taunts request() error=%d — retrying in 3s" % err2)
			get_tree().create_timer(3.0, true, false, true).timeout.connect(
				func(): request_general_taunts(callback, 1))
			return
		var msg := "[TAUNT FALLBACK] general taunts failed after retry — request error=%d. Canned pool only." % err2
		push_warning(msg)
		print(msg)
		callback.call({})


# ── Kaelen handoff batch generation (Gemma4) ─────────────────────────────────
# Asks the large model for 16 Kaelen intro lines for one agent.
# Returns Array[String] to callback — empty array on failure.
func request_kaelen_handoff_batch(
	agent_name: String,
	agent_role: String,
	faction: String,
	story_context: String,
	count: int,
	callback: Callable
) -> void:
	var story_block := ""
	if story_context.strip_edges() != "":
		story_block = (
			"\nStory context (color Kaelen's tone — do NOT quote or expose directly):\n"
			+ story_context + "\n"
		)
	var prompt := (
		"You are writing for Broker Kaelen — a dry, transactional, faintly condescending space broker.\n"
		+ "She is about to introduce %s (%s, %s faction) to the pilot \"Shiny\".\n" % [agent_name, agent_role, faction]
		+ story_block
		+ "\nWrite %d SHORT handoff lines (under 25 words each) in Kaelen's voice.\n" % count
		+ "Rules:\n"
		+ "- First person as Kaelen. She is talking TO Shiny about %s.\n" % agent_name
		+ "- %s is silent. Never put words in their mouth.\n" % agent_name
		+ "- Mention %s by name in every line (third person).\n" % agent_name
		+ "- Vary the angle: some urgent, some dry, some with a hint of the story tension.\n"
		+ "- No line should repeat another. No numbering.\n"
		+ "- Do NOT use the word 'Shiny' more than once across all lines.\n\n"
		+ "Respond ONLY with a valid JSON array of %d strings:\n" % count
		+ "[\"line one\", \"line two\", ...]"
	)

	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 60.0

	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				push_warning("[LLMInterface] Handoff batch HTTP error result=%d code=%d" % [result, code])
				callback.call([])
				return
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
			if parsed == null or not parsed is Dictionary:
				push_warning("[LLMInterface] Handoff batch: non-dict response")
				callback.call([])
				return
			var raw_text: String = str((parsed as Dictionary).get("response", "")).strip_edges()
			# Extract the JSON array from the response text.
			var start := raw_text.find("[")
			var end := raw_text.rfind("]")
			if start == -1 or end == -1 or end <= start:
				push_warning("[LLMInterface] Handoff batch: no JSON array found in response")
				callback.call([])
				return
			var arr_text := raw_text.substr(start, end - start + 1)
			var arr: Variant = JSON.parse_string(arr_text)
			if arr == null or not arr is Array:
				push_warning("[LLMInterface] Handoff batch: JSON array parse failed")
				callback.call([])
				return
			var lines: Array[String] = []
			for item in (arr as Array):
				var s := str(item).strip_edges()
				if s != "":
					lines.append(s)
			print("[LLMInterface] Handoff batch: got %d lines for %s" % [lines.size(), agent_name])
			callback.call(lines)
	)

	var large_model: String = active_large_model_name if active_large_model_name != "" else LocalModelGateway.DEFAULT_LARGE_MODEL
	var payload := JSON.stringify({
		"model": large_model,
		"prompt": prompt,
		"stream": false,
		"options": {"num_predict": 800, "temperature": 0.85},
	})
	var err := http.request(
		LocalModelGateway.OLLAMA_GENERATE_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		payload
	)
	if err != OK:
		http.queue_free()
		push_warning("[LLMInterface] Handoff batch: request() failed err=%d" % err)
		callback.call([])


func fetch_anomaly_event(
	system_id: String,
	fallback_data: Dictionary,
	callback: Callable,
	_attempts_left: int = 1
) -> void:
	var local_factions: Array = GlobalState.get_current_system_minor_factions()
	if local_factions.is_empty():
		local_factions = GlobalState.MINOR_FACTIONS.keys()
	var faction_labels: Array = []
	for f in local_factions:
		if f is Dictionary:
			faction_labels.append(str(f.get("id", f.get("faction", ""))))
		else:
			faction_labels.append(str(f))
	var prompt := (
		"You design one small space anomaly event for SpaceGame. "
		+ "Current system: %s. Local minor factions: %s. "
		+ "Fallback seed event: %s. "
		+ "Write a fresh event using ONLY this action toolkit: "
		+ "emit_chat, grant_ore, grant_credits, grant_item, grant_data_core, spawn_hostiles, damage_player. "
		+ "Caps: grant_ore 0-30, grant_credits 0-150, grant_item one known item, "
		+ "grant_data_core payout_credits 40-250, spawn_hostiles count 1-3, damage_player 0-20. "
		+ "Use short chat lines. Do not invent UI, quests, shops, docking, choices, or new mechanics. "
		+ "Respond ONLY as valid JSON with keys name, description, flavor_type, approach_lines, actions."
	) % [system_id, ", ".join(faction_labels), JSON.stringify(fallback_data)]
	var temp_http := HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = request_timeout_for_capability("background_chatter")
	temp_http.request_completed.connect(func(result, response_code, _headers, body):
		temp_http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			if _attempts_left > 0:
				fetch_anomaly_event(system_id, fallback_data, callback, _attempts_left - 1)
			else:
				callback.call({})
			return
		var generated := _parse_anomaly_event_response(body.get_string_from_utf8())
		if generated.is_empty():
			if _attempts_left > 0:
				fetch_anomaly_event(system_id, fallback_data, callback, _attempts_left - 1)
			else:
				callback.call({})
			return
		callback.call(generated)
	)
	var payload := build_generation_body(
		"background_chatter",
		prompt,
		"json",
		{"temperature": 0.95, "seed": randi()}
	)
	var err := temp_http.request(
		OLLAMA_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		temp_http.queue_free()
		callback.call({})


func _parse_anomaly_event_response(response_text: String) -> Dictionary:
	var outer_json := JSON.new()
	if outer_json.parse(response_text) != OK:
		return {}
	var outer_data = outer_json.get_data()
	if not outer_data is Dictionary or not outer_data.has("response"):
		return {}
	var inner_str: String = str(outer_data["response"]).strip_edges()
	if inner_str.begins_with("```"):
		var end_idx := inner_str.find("\n", 3)
		if end_idx != -1:
			inner_str = inner_str.substr(end_idx + 1)
		if inner_str.ends_with("```"):
			inner_str = inner_str.substr(0, inner_str.length() - 3)
		inner_str = inner_str.strip_edges()
	var inner_json := JSON.new()
	if inner_json.parse(inner_str) != OK:
		return {}
	var data = inner_json.get_data()
	if not data is Dictionary:
		return {}
	return _sanitize_anomaly_event(data)


func _sanitize_anomaly_event(data: Dictionary) -> Dictionary:
	var name := str(data.get("name", "")).strip_edges()
	if name.is_empty() or name.contains("["):
		return {}
	var flavor := str(data.get("flavor_type", "unknown")).strip_edges().to_lower()
	if flavor not in ["military", "civilian", "pirate", "scientific", "unknown"]:
		flavor = "unknown"
	var approach_lines: Array = []
	if data.get("approach_lines", []) is Array:
		for line in data["approach_lines"]:
			var text := str(line).strip_edges()
			if not text.is_empty() and not text.contains("["):
				approach_lines.append(text.left(160))
			if approach_lines.size() >= 3:
				break
	var actions := _sanitize_anomaly_actions(data.get("actions", []))
	if actions.is_empty():
		return {}
	return {
		"name": name.left(60),
		"description": str(data.get("description", "")).strip_edges().left(180),
		"flavor_type": flavor,
		"approach_lines": approach_lines,
		"actions": actions,
	}


func _sanitize_anomaly_actions(raw_actions: Variant) -> Array:
	if not raw_actions is Array:
		return []
	var valid_items := [
		"repair_kit", "shield_cell", "scanner_probe", "salvage_drone",
		"flare_decoy", "fuel_booster", "emp_charge", "target_painter",
		"data_chip", "kinetic_ammo", "thermal_ammo", "explosive_ammo",
		"energy_ammo", "damaged_transponder", "encrypted_core",
		"antimatter_pod",
	]
	var valid_factions: Array = GlobalState.MINOR_FACTIONS.keys()
	var output: Array = []
	for raw in raw_actions:
		if not raw is Dictionary:
			continue
		var t := str(raw.get("type", "")).strip_edges()
		var action: Dictionary = {}
		match t:
			"emit_chat":
				var lines: Array = []
				if raw.get("lines", []) is Array:
					for line in raw["lines"]:
						var text := str(line).strip_edges()
						if not text.is_empty() and not text.contains("["):
							lines.append(text.left(180))
						if lines.size() >= 3:
							break
				if lines.is_empty():
					continue
				action = {
					"type": "emit_chat",
					"sender": str(raw.get("sender", "Unknown Signal")).strip_edges().left(40),
					"lines": lines,
					"delay": clampf(float(raw.get("delay", 0.0)), 0.0, 8.0),
				}
			"grant_ore":
				action = {
					"type": "grant_ore",
					"amount": clampf(float(raw.get("amount", 10.0)), 0.0, 30.0),
				}
			"grant_credits":
				action = {
					"type": "grant_credits",
					"amount": clampi(int(raw.get("amount", 20)), 0, 150),
				}
			"grant_item":
				var item_id := str(raw.get("item_id", ""))
				if item_id not in valid_items:
					continue
				action = {"type": "grant_item", "item_id": item_id}
			"grant_data_core":
				action = {
					"type": "grant_data_core",
					"name": str(raw.get("name", "Encrypted Anomaly Core")).strip_edges().left(60),
					"description": str(raw.get("description", "Recovered anomaly data core.")).strip_edges().left(180),
					"payout_credits": clampi(int(raw.get("payout_credits", 120)), 40, 250),
				}
			"spawn_hostiles":
				var faction := str(raw.get("faction", "reavers"))
				if faction not in valid_factions:
					faction = "reavers"
				action = {
					"type": "spawn_hostiles",
					"faction": faction,
					"count": clampi(int(raw.get("count", 1)), 1, 3),
					"delay": clampf(float(raw.get("delay", 2.0)), 0.0, 12.0),
					"spawn_chat": str(raw.get("spawn_chat", "")).strip_edges().left(120),
				}
			"damage_player":
				action = {
					"type": "damage_player",
					"amount": clampf(float(raw.get("amount", 5.0)), 0.0, 20.0),
				}
			_:
				continue
		output.append(action)
		if output.size() >= 5:
			break
	return output
