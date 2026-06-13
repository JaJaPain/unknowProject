extends Node

const OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
const MODEL_NAME = "qwen2.5:1.5b-instruct-q4_K_M"
const TIMEOUT_SECONDS = 15.0
# Kaelen intro telemetry is written to user://kaelen_intro_stats.json so
# counters survive game restarts. Read via get_kaelen_intro_stats().
const _KAELEN_STATS_PATH = "user://kaelen_intro_stats.json"

var http_request: HTTPRequest
var active_callback: Callable
var is_waiting: bool = false
var request_start_time: float = 0.0
var last_history_text: String = ""
var active_model_name: String = MODEL_NAME
var world_lore_text: String = ""

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
	"industrial_banter": []
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
	]
}

var active_fetches = {
	"hostile_taunt": false,
	"death_cry": false,
	"system_alert": false,
	"industrial_banter": false,
	"pickup_keywords": false
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
	_discover_ollama_model()

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
	# Clear chatter caches — new session should generate fresh contextual lines
	for key in chatter_cache:
		chatter_cache[key].clear()
	for key in active_fetches:
		active_fetches[key] = false
	print("[LLMInterface] State reset for new game.")



func _discover_ollama_model():
	connection_attempts += 1
	llm_connection_attempt.emit(connection_attempts)
	print("[TRACE] [LLMInterface] Discovering Ollama models (attempt %d)..." % connection_attempts)
	
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
							
					print("[TRACE] [LLMInterface] Installed Ollama models: ", installed_names)
					
					var chosen_model = ""
					if MODEL_NAME in installed_names:
						chosen_model = MODEL_NAME
					elif "qwen2.5:1.5b-instruct" in installed_names:
						chosen_model = "qwen2.5:1.5b-instruct"
					elif "qwen2.5:1.5b" in installed_names:
						chosen_model = "qwen2.5:1.5b"
					elif "qwen2.5-coder:7b" in installed_names:
						chosen_model = "qwen2.5-coder:7b"
					elif "qwen3:8b" in installed_names:
						chosen_model = "qwen3:8b"
					elif "gemma4:latest" in installed_names:
						chosen_model = "gemma4:latest"
					elif "gemma4:12b" in installed_names:
						chosen_model = "gemma4:12b"
					else:
						for name in installed_names:
							if "qwen" in name:
								chosen_model = name
								break
						if chosen_model == "":
							for name in installed_names:
								if "gemma" in name:
									chosen_model = name
									break
						if chosen_model == "" and installed_names.size() > 0:
							chosen_model = installed_names[0]
							
					if chosen_model != "":
						active_model_name = chosen_model
						print("[TRACE] [LLMInterface] Dynamic Ollama model selection: USING '", active_model_name, "'")
					else:
						print("[LLMInterface] No models found in Ollama tags. Defaulting to: ", active_model_name)
					
					success = true
					
		if success:
			print("[TRACE] [LLMInterface] Ollama connection successfully verified.")
			llm_connected = true
			llm_connection_established.emit(active_model_name)
			model_discovered.emit(active_model_name)
			# Pre-warm ALL chatter caches immediately so static fallback lines
			# are never used during the first combat encounter
			print("[TRACE] [LLMInterface] Pre-warming chatter caches...")
			for chatter_type in chatter_cache.keys():
				fetch_chatter_background(chatter_type)
		else:
			print("[LLMInterface] Connection to Ollama failed (attempt %d). Retrying in 1.5s..." % connection_attempts)
			get_tree().create_timer(1.5).timeout.connect(_discover_ollama_model)
	)
	
	var err = tags_http.request("http://127.0.0.1:11434/api/tags")
	if err != OK:
		tags_http.queue_free()
		print("[LLMInterface] Failed to initiate tags check. Retrying in 1.5s...")
		get_tree().create_timer(1.5).timeout.connect(_discover_ollama_model)

func request_quest_generation(agent_faction: String, history_text: String, player_credits: int, player_reps: Dictionary, callback: Callable):
	if is_waiting:
		return
	
	active_callback = callback
	is_waiting = true
	last_history_text = history_text
	request_start_time = Time.get_ticks_msec()
	print("[TRACE] [LLMInterface] request_quest_generation initiated at: %d ms" % request_start_time)
	
	var rand_comp = complications[randi() % complications.size()]
	
	# Pick a faction randomly if "neutral" is passed (neutral = broker picks any client)
	var chosen_faction = agent_faction
	if chosen_faction == "neutral" or chosen_faction == "":
		var factions = ["zenith", "aurelia", "vanguard"]
		chosen_faction = factions[randi() % factions.size()]
	
	# Each faction has a distinct named agent, personality, and player nickname
	var agent_name = "Broker Kaelen"
	var agent_persona = ""
	var player_nickname = "Indy"
	var agent_role = ""
	var example_dialogue = ""
	var example_response_1 = ""
	var example_response_2 = ""
	var example_response_3 = ""
	var example_faction_key = chosen_faction
	
	match chosen_faction:
		"zenith":
			agent_name = "Director Voss"
			agent_role = "Zenith Corporate Acquisitions Director"
			player_nickname = "Indy"
			agent_persona = "You are Director Voss, a cold, calculating Zenith corporate officer. " + \
				"You speak in clipped, efficient sentences. You have no patience for failure and treat the pilot as an interchangeable asset. " + \
				"You refer to the pilot exclusively as 'Indy'. You never use slang or humor. " + \
				"You frame all jobs as 'acquisitions', 'operations', or 'directives'. Zenith's interests are paramount."
			example_dialogue = "Zenith has a resource deficit that requires immediate correction, Indy. Deliver the required silicate tonnage to the station docking bay. Efficiency is non-negotiable."
			example_response_1 = "Confirmed, Indy. Your assignment is logged. Do not deviate from the directive."
			example_response_2 = "An advance against operational expenses. Noted. Your compensation adjustment is processed. Expect elevated patrol resistance on your route."
			example_response_3 = "Bold negotiation. Zenith respects leverage, Indy. Payout is revised upward. However, security escalation protocols are now active in your sector."
		"aurelia":
			agent_name = "Liaison Ryn"
			agent_role = "Aurelia Syndicate Trade Liaison"
			player_nickname = "Indy"
			agent_persona = "You are Liaison Ryn, a smooth-talking, conniving Aurelia syndicate fixer. " + \
				"You are charming but never fully trustworthy. You speak like someone always running an angle. " + \
				"You refer to the pilot exclusively as 'Indy'. You use words like 'clean', 'quiet', 'off the books'. " + \
				"Everything is framed as an opportunity, never a risk."
			example_dialogue = "Aurelia's got a clean job for someone with your skills, Indy. Quiet, low profile. The syndicate needs those hulls cleared before the next shipment window. Easy credits, no records."
			example_response_1 = "Smooth. Indy keeps it clean, that's why I like working with you. Stay off their sensors."
			example_response_2 = "An advance? Smart move, Indy. Credits transferred. The Syndicate routes you through a riskier corridor to offset the cost. Stay quiet out there."
			example_response_3 = "Playing hardball? I respect the hustle, Indy. Payout bumped. But Aurelia's rivals will be watching the sector. Keep your profile low."
		"vanguard":
			agent_name = "Captain Dask"
			agent_role = "Vanguard Military Contract Officer"
			player_nickname = "Indy"
			agent_persona = "You are Captain Dask, a gruff, no-nonsense Vanguard military contract officer. " + \
				"You are direct and have zero tolerance for excuses or negotiation theatre. " + \
				"You refer to the pilot exclusively as 'Indy'. You use military shorthand: 'ROE', 'boots on hull', 'clear the zone'. " + \
				"You respect competence and despise weakness."
			example_dialogue = "Vanguard needs those Aurelia raiders cleared from the shipping lane, Indy. Four contacts, high priority. Take them down and get back to the dock. No theatrics."
			example_response_1 = "Copy that, Indy. ROE is clear: engage and eliminate. Don't make it complicated."
			example_response_2 = "You want an advance, Indy? Fine. But Vanguard doesn't cover operational cowardice. Threat level is escalated. Don't embarrass us."
			example_response_3 = "Renegotiating under fire, Indy. Bold. Payout is adjusted. Don't expect the Vanguard to soften the zone for you."
		_:
			agent_name = "Broker Kaelen"
			agent_role = "Neutral Fixer & Profit Broker"
			player_nickname = "Shiny"
			agent_persona = "You are Broker Kaelen, an independent, politically neutral space broker and fixer. " + \
				"You operate out of a space station and negotiate contracts with all factions for personal profit. " + \
				"You are cynical, sharp, and opportunistic. You call the pilot 'Shiny' — treating them like an unscarred greenhorn who is also your most profitable tool. " + \
				"You always mention your broker's cut and how the deal benefits you personally."
			example_dialogue = "Zenith needs ore, I need my cut, and you need credits, Shiny. Bring me 25 cubic metres and I'll keep my brokerage fee reasonable. Don't dawdle."
			example_response_1 = "Excellent, Shiny. My client is watching the clock, so don't waste my time."
			example_response_2 = "Taking a bite out of my margins, Shiny? Fine. Credits wired. But I'm routing you through a contested lane to cover the difference."
			example_response_3 = "Hustling a hustler? I respect the nerve, Shiny. Payout is bumped. But enemies will be expecting you."
	
	# Pre-decide objective type so example AND instruction always match.
	# The LLM cannot choose — it must use the type we picked.
	var quest_types = ["DELIVER_ORE", "KILL_SHIPS", "PICKUP_SPECIAL"]
	var chosen_type = quest_types[randi() % quest_types.size()]
	
	# Build the matching example block
	var example_obj_block = ""
	var example_title = ""
	var pickup_outpost = ""
	var pickup_outpost_display = ""
	var pickup_npc = ""
	var pickup_item = ""
	
	if chosen_type == "DELIVER_ORE":
		example_title = "Silicate Run"
		example_obj_block = \
			"  \"objective\": {\n" + \
			"    \"type\": \"DELIVER_ORE\",\n" + \
			"    \"amount_required\": 25.0,\n" + \
			"    \"reward_credits\": 160\n" + \
			"  },"
	elif chosen_type == "KILL_SHIPS":
		# KILL_SHIPS — pick a kill target (90% minor factions, 10% major factions)
		var kill_target = ""
		if randf() < 0.9:
			# 90% chance: target a minor faction
			var minor_keys = GlobalState.MINOR_FACTIONS.keys()
			kill_target = minor_keys[randi() % minor_keys.size()]
		else:
			# 10% chance: target a major faction (not the client)
			var major_targets = ["zenith", "aurelia", "vanguard"]
			major_targets.erase(chosen_faction)
			kill_target = major_targets[randi() % major_targets.size()]
		example_title = "Clear the Lane"
		example_obj_block = \
			"  \"objective\": {\n" + \
			"    \"type\": \"KILL_SHIPS\",\n" + \
			"    \"target_faction\": \"" + kill_target + "\",\n" + \
			"    \"count_required\": 3,\n" + \
			"    \"reward_credits\": 200\n" + \
			"  },"
	elif chosen_type == "PICKUP_SPECIAL":
		var outpost_ids = GlobalState.PICKUP_OUTPOST_IDS
		pickup_outpost = outpost_ids[randi() % outpost_ids.size()]
		pickup_outpost_display = GlobalState.PICKUP_OUTPOST_DISPLAY.get(pickup_outpost, pickup_outpost)
		var npcs_at_outpost = GlobalState.get_minor_npcs_at_outpost(pickup_outpost)
		pickup_npc = npcs_at_outpost[randi() % npcs_at_outpost.size()]
		var fetch_items = ["Large Unmarked Crate", "Suspension Pod", "Sealed Data Drive", "Biometric Lockbox", "Hazardous Material Container"]
		pickup_item = fetch_items[randi() % fetch_items.size()]
		
		example_title = "Discreet Courier"
		example_obj_block = \
			"  \"objective\": {\n" + \
			"    \"type\": \"PICKUP_SPECIAL\",\n" + \
			"    \"target_outpost\": \"" + pickup_outpost + "\",\n" + \
			"    \"target_outpost_display\": \"" + pickup_outpost_display + "\",\n" + \
			"    \"target_npc\": \"" + pickup_npc + "\",\n" + \
			"    \"part_name\": \"" + pickup_item + "\",\n" + \
			"    \"destination\": \"" + agent_name + "\",\n" + \
			"    \"reward_credits\": 250\n" + \
			"  },"

	# Also align the agent example dialogue to the chosen type so the LLM
	# sees a consistent story/objective pairing in the example block
	if chosen_type == "KILL_SHIPS":
		match chosen_faction:
			"zenith":
				example_dialogue = "We need the Aurelia raider wing cleared from the transit corridor, " + player_nickname + ". Three contacts, high priority. Don't leave witnesses."
			"aurelia":
				example_dialogue = "There's a Vanguard patrol harassing our supply runners, " + player_nickname + ". Four ships. Remove them quietly and I'll make sure the credits flow."
			"vanguard":
				example_dialogue = "Zenith is probing our flank again, Indy. Four contacts in the sector. Clear the zone before they can report back."
			_:
				example_dialogue = "Got a hostile problem that needs solving, " + player_nickname + ". A handful of ships that need removing. Standard removal contract."
	elif chosen_type == "PICKUP_SPECIAL":
		match chosen_faction:
			"zenith":
				example_dialogue = "Zenith logistics requires a discreet transport, " + player_nickname + ". Proceed to " + pickup_outpost_display + " and retrieve a " + pickup_item + " from " + pickup_npc + ". Do not ask questions about the cargo."
			"aurelia":
				example_dialogue = "I need a quiet runner, " + player_nickname + ". Head over to " + pickup_outpost_display + " and find " + pickup_npc + ". They have a " + pickup_item + " for me. Bring it straight back here, unopened."
			"vanguard":
				example_dialogue = "Vanguard command needs a secure retrieval, " + player_nickname + ". A contact named " + pickup_npc + " at " + pickup_outpost_display + " is holding a " + pickup_item + ". Secure it and return immediately."
			_:
				example_dialogue = "Got a lucrative fetch job, " + player_nickname + ". I need you to go to " + pickup_outpost_display + " and get a " + pickup_item + " from " + pickup_npc + ". Bring it to me intact and you'll get paid."



	# Build minor faction context string for the LLM
	var minor_fac_names = GlobalState.MINOR_FACTIONS.keys()
	var minor_fac_str = ", ".join(minor_fac_names)
	
	var lore_block = ""
	if world_lore_text != "":
		lore_block = "### WORLD LORE:\n" + world_lore_text + "\n\n"
	
	var system_prompt = agent_persona + "\n\n" + \
		lore_block + \
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
		"Generate a unique space quest. You MUST respond strictly in valid JSON format. Do not output notes, markdown, or surrounding text. Only output the raw JSON object:\n" + \
		"{\n" + \
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
		"The faction must be \"" + chosen_faction + "\". The agent_name must be \"" + agent_name + "\". " + \
		"The objective type in your JSON MUST be '" + chosen_type + "' — do NOT use any other objective type. " + \
		("For KILL_SHIPS you MUST include 'target_faction' (must NOT equal '" + chosen_faction + "') and 'count_required' (integer 2–4). " if chosen_type == "KILL_SHIPS" else ("For PICKUP_SPECIAL you MUST include 'target_outpost' (must equal '" + pickup_outpost + "'), 'target_outpost_display' (must equal '" + pickup_outpost_display + "'), 'target_npc' (must equal '" + pickup_npc + "'), 'part_name' (must equal '" + pickup_item + "'), and 'destination' (must equal '" + agent_name + "'). " if chosen_type == "PICKUP_SPECIAL" else "For DELIVER_ORE you MUST include 'amount_required' (float 20–300). ")) + \
		("Your dialogue MUST mention the target NPC (" + pickup_npc + "), the outpost (" + pickup_outpost_display + "), and the exact item name (" + pickup_item + "). " if chosen_type == "PICKUP_SPECIAL" else "Your dialogue MUST state the exact objective number — for kills, mention how many ships; for ore, mention how many m³. ") + \
		"Always call the pilot '" + player_nickname + "' — never use any other nickname. " + \
		"Output only the raw JSON object."
	
	var payload = {
		"model": active_model_name,
		"prompt": system_prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": 0.85,
			"seed": randi()
		}
	}
	
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	
	print("[LLMInterface] Sending request to Ollama for faction: ", chosen_faction, " agent: ", agent_name)
	var err = http_request.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		print("[LLMInterface] HTTP request failed to initiate. Error code: ", err)
		_trigger_fallback()


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	is_waiting = false
	var now = Time.get_ticks_msec()
	var elapsed = (now - request_start_time) / 1000.0
	print("[TRACE] [LLMInterface] HTTP request completed in %.3fs. Result: %d, Response code: %d at %d ms" % [elapsed, result, response_code, now])
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[LLMInterface] HTTP request failed or timed out. Response code: ", response_code)
		_trigger_fallback()
		return
		
	var response_text = body.get_string_from_utf8()
	var json = JSON.new()
	var err = json.parse(response_text)
	if err != OK:
		print("[LLMInterface] Failed to parse Ollama response envelope JSON.")
		_trigger_fallback()
		return
		
	var outer_data = json.get_data()
	if not outer_data is Dictionary or not outer_data.has("response"):
		print("[LLMInterface] Response envelope missing 'response' field.")
		_trigger_fallback()
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
		_trigger_fallback()
		return
		
	var quest_data = inner_json.get_data()
	if not quest_data is Dictionary or not quest_data.has("objective") or not quest_data.has("choices"):
		print("[LLMInterface] Parsed quest data is invalid or missing fields.")
		_trigger_fallback()
		return
		
	print("[LLMInterface] LLM Quest successfully generated: ", quest_data["title"])
	_validate_quest_data(quest_data)
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
	if dialogue_sounds_like_kill and not dialogue_sounds_like_ore and not dialogue_sounds_like_pickup and obj_type == "DELIVER_ORE":
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
	elif dialogue_sounds_like_ore and not dialogue_sounds_like_kill and not dialogue_sounds_like_pickup and obj_type == "KILL_SHIPS":
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
		obj["count_required"] = clampi(count, 2, 4)

		# Validate target_faction is a known faction (minor or major).
		# If the LLM hallucinated an unknown name (e.g. "synths", "outlaws"),
		# the ship would spawn with no model. Remap to a random minor
		# faction so it always renders.
		var tf = obj.get("target_faction", "")
		var known_factions = GlobalState.MINOR_FACTIONS.keys()
		known_factions.append_array(["zenith", "aurelia", "vanguard"])
		if tf == "" or not tf in known_factions:
			var minor_keys = GlobalState.MINOR_FACTIONS.keys()
			var original = tf if tf != "" else "(empty)"
			obj["target_faction"] = minor_keys[randi() % minor_keys.size()]
			print("[LLMInterface] ⚠ VALIDATE: Unknown target_faction '%s' remapped to '%s'." % [original, obj["target_faction"]])
	elif obj_type == "DELIVER_ORE":
		var amount = float(obj.get("amount_required", 25.0))
		obj["amount_required"] = clampf(amount, 20.0, 300.0)
	elif obj_type == "PICKUP_SPECIAL":
		var outpost = obj.get("target_outpost", "")
		var npc = obj.get("target_npc", "")
		var valid_outposts = GlobalState.PICKUP_OUTPOST_IDS
		if outpost not in valid_outposts:
			obj["target_outpost"] = valid_outposts[0]
			obj["target_outpost_display"] = GlobalState.PICKUP_OUTPOST_DISPLAY.get(valid_outposts[0], valid_outposts[0])
			npc = GlobalState.get_minor_npcs_at_outpost(valid_outposts[0])[0]
			obj["target_npc"] = npc
		else:
			var valid_npcs = GlobalState.get_minor_npcs_at_outpost(outpost)
			if npc not in valid_npcs:
				obj["target_npc"] = valid_npcs[0] if valid_npcs.size() > 0 else "Mariska Vonn"
		if not obj.has("part_name"):
			obj["part_name"] = "Suspicious Crate"
		if not obj.has("destination"):
			obj["destination"] = "Main Station"

	# Last line of defense: reconciliation above may pull an out-of-range
	# number from the dialogue, then clamping can make the two disagree again.
	# Patch only the objective number so display text and TTS use the final value.
	_sync_dialogue_to_validated_objective(quest_data, obj_type, obj)

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
			"patrol", "interceptor", "sentinel", "fighter", "bogey", "hull"]
		var kill_verbs = ["destroy", "eliminate", "kill", "clear", "remove", "engage", "take"]
		for i in range(dialogue.length()):
			if dialogue[i] < "1" or dialogue[i] > "9":
				continue
			var after = dialogue.substr(i + 1, 25)
			var before_start = max(0, i - 15)
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
				number_end = i + 1
				break
		replacement = str(int(obj.get("count_required", 3)))

	if number_start == -1:
		return

	var current_number = original_dialogue.substr(number_start, number_end - number_start)
	if current_number == replacement:
		return

	quest_data["dialogue"] = original_dialogue.substr(0, number_start) + replacement + original_dialogue.substr(number_end)
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
		obj["amount_required"] = found_amount
	elif found_amount > 0:
		print("[LLMInterface] ✓ VALIDATE: Ore amount matches — dialogue and JSON both say %.0f m³." % json_amount)
	else:
		print("[LLMInterface] ✓ VALIDATE: No ore amount found in dialogue text. Using JSON value: %.0f m³." % json_amount)

func _trigger_fallback():
	var elapsed = (Time.get_ticks_msec() - request_start_time) / 1000.0
	print("[TRACE] [LLMInterface] Triggering local procedural fallback quest (Ollama elapsed: %.3fs)." % elapsed)
	
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
		
	var payload = {
		"model": active_model_name,
		"prompt": system_prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": 0.9,
			"seed": randi()
		}
	}
	
	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = 12.0 # Give background request plenty of time
	
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
	temp_http.timeout = 10.0
	
	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()
		
		# If request fails or times out, trigger fallback
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			_trigger_salvager_profile_fallback(callback)
			return
			
		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		var err = json.parse(response_text)
		if err != OK:
			_trigger_salvager_profile_fallback(callback)
			return
			
		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			_trigger_salvager_profile_fallback(callback)
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
			_trigger_salvager_profile_fallback(callback)
			return
			
		var profile_data = inner_json.get_data()
		if profile_data is Dictionary and profile_data.has("name") and profile_data.has("backstory"):
			callback.call(profile_data)
		else:
			_trigger_salvager_profile_fallback(callback)
	)
	
	var prompt = "Generate a unique sci-fi scrapper/miner pilot name and a short (2-3 sentences) backstory. " + \
		"The pilot operates a salvager ship in the sector. The backstory should detail their origins, their ship name, and their scrapper personality. " + \
		"You MUST respond strictly in valid JSON format matching this schema exactly. Do not output any notes, markdown codeblock formatting, or surrounding text. Only output the raw JSON object:\n" + \
		"{\n" + \
		"  \"name\": \"[Pilot Name]\",\n" + \
		"  \"backstory\": \"[Backstory Text]\"\n" + \
		"}"
		
	var payload = {
		"model": active_model_name,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": 0.85,
			"seed": randi()
		}
	}
	
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		_trigger_salvager_profile_fallback(callback)

func request_kaelen_reaction(quest_data: Dictionary, callback: Callable):
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
	temp_http.timeout = 12.0

	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			print("[LLMInterface] Kaelen reaction fetch failed. Using fallback lines.")
			_trigger_kaelen_reaction_fallback(callback)
			return

		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(response_text) != OK:
			_trigger_kaelen_reaction_fallback(callback)
			return

		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			_trigger_kaelen_reaction_fallback(callback)
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
			_trigger_kaelen_reaction_fallback(callback)
			return

		var reaction_data = inner_json.get_data()
		if reaction_data is Dictionary and reaction_data.has("completion") and reaction_data.has("abandon"):
			print("[LLMInterface] Kaelen reaction lines generated for quest: ", title)
			callback.call(reaction_data["completion"], reaction_data["abandon"])
		else:
			_trigger_kaelen_reaction_fallback(callback)
	)

	var payload = {
		"model": active_model_name,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": 0.9,
			"seed": randi()
		}
	}
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		_trigger_kaelen_reaction_fallback(callback)

func _trigger_kaelen_reaction_fallback(callback: Callable):
	var comp = fallback_completion_lines[randi() % fallback_completion_lines.size()]
	var abn = fallback_abandon_lines[randi() % fallback_abandon_lines.size()]
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
func _build_kaelen_intro_prompt(agent_name: String, faction: String, title: String, examples_block: String, history_clause: String, reputation_clause: String, correction_suffix: String) -> String:
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

	# First attempt. If the response fails the speaker-leakage guard, we
	# retry ONCE with a correction suffix that tells the model what it did
	# wrong. After that, we hard-fall-back to canned (caller picks from
	# fallback_handoff_lines_by_agent).
	_kaelen_intro_request_attempt(agent_name, title, faction, examples_block, history_clause, reputation_clause, "", 0, callback)


# Internal: make one LLM call for the handoff intro. `attempt` is 0 on the
# first try, 1 on the self-critique retry. Total cap is 2 attempts — beyond
# that the caller falls back to a canned line.
func _kaelen_intro_request_attempt(agent_name: String, title: String, faction: String, examples_block: String, history_clause: String, reputation_clause: String, correction_suffix: String, attempt: int, original_callback: Callable):
	var prompt = _build_kaelen_intro_prompt(agent_name, faction, title, examples_block, history_clause, reputation_clause, correction_suffix)

	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = 8.0  # Tighter than quest gen — intro must be quick

	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			_kaelen_intro_network_failures += 1
			_save_kaelen_intro_stats()
			print("[LLMInterface] Kaelen intro fetch failed (network). Caller should fall back.")
			original_callback.call("")
			return

		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(response_text) != OK:
			_kaelen_intro_parse_failures += 1
			_save_kaelen_intro_stats()
			print("[LLMInterface] Kaelen intro fetch failed (outer JSON parse). Caller should fall back.")
			original_callback.call("")
			return

		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			_kaelen_intro_parse_failures += 1
			_save_kaelen_intro_stats()
			original_callback.call("")
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
			original_callback.call("")
			return

		var intro_data = inner_json.get_data()
		if not (intro_data is Dictionary and intro_data.has("intro") and intro_data["intro"] is String):
			_kaelen_intro_parse_failures += 1
			_save_kaelen_intro_stats()
			original_callback.call("")
			return

		var line: String = intro_data["intro"].strip_edges()
		if line == "":
			original_callback.call("")
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
				original_callback.call("")
				return
			_kaelen_intro_rejected_first_try += 1
			# Build a correction suffix from the rejection reason and retry.
			var new_suffix = "SELF-CRITIQUE — your previous attempt was rejected. Reason: " + rejection_reason
			print("[LLMInterface] Kaelen intro: retrying with self-critique correction...")
			_kaelen_intro_request_attempt(agent_name, title, faction, examples_block, history_clause, reputation_clause, new_suffix, attempt + 1, original_callback)
			return

		_kaelen_intro_successes += 1
		_save_kaelen_intro_stats()
		print("[LLMInterface] Kaelen unique intro generated for: ", agent_name, " (", title, "): ", line)
		original_callback.call(line)
	)

	_kaelen_intro_attempts += 1
	var payload = {
		"model": active_model_name,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": 0.9,
			"seed": randi()
		}
	}
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		_kaelen_intro_network_failures += 1
		_save_kaelen_intro_stats()
		print("[LLMInterface] Kaelen intro fetch failed (request init). Caller should fall back.")
		original_callback.call("")

func _trigger_salvager_profile_fallback(callback: Callable):
	var rand_name = fallback_salvager_names[randi() % fallback_salvager_names.size()]
	var rand_backstory = fallback_salvager_backstories[randi() % fallback_salvager_backstories.size()]
	var profile = {
		"name": rand_name,
		"backstory": rand_backstory
	}
	callback.call(profile)

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
	temp_http.timeout = 10.0

	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])
			return

		var response_text = body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(response_text) != OK:
			callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])
			return

		var outer_data = json.get_data()
		if not outer_data is Dictionary or not outer_data.has("response"):
			callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])
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
			callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])
			return

		var data = inner_json.get_data()
		if data is Dictionary and data.has("line") and data["line"] is String and data["line"].length() > 3:
			callback.call(data["line"])
		else:
			callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])
	)

	var payload = {
		"model": active_model_name,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": 0.92,
			"seed": randi()
		}
	}
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var err = temp_http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		callback.call(fallback_partial_delivery_lines[randi() % fallback_partial_delivery_lines.size()])
