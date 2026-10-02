extends SceneTree

const DNA := preload("res://scripts/story/premise/VoiceDNA.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var blends := {}
	var faction_leads := {}
	for i in 600:
		var faction := "faction.generated.f%d" % (i % 6)
		var v := DNA.for_person("npc.person_%d" % i, faction)
		var provider := str(v["provider_voice"])
		_check(v == DNA.for_person("npc.person_%d" % i, faction), "voices must be stable per person")
		for fixed in DNA.FIXED_CAST_VOICES:
			_check(not provider.contains(fixed), "generated voice uses a fixed-cast base voice: %s" % provider)
		_check(provider.count("[") == 2 and provider.contains("+"), "a blend of two voices: %s" % provider)
		_check(float(v["speed"]) >= 0.9 and float(v["speed"]) <= 1.1, "speed in range")
		# Never close to a named character (playtest 2026-10-02: Jenna's voice
		# turned up all over the place).
		_check(DNA.nearest_reserved_distance(provider) >= DNA.RESERVED_MIN_DISTANCE, "generated voice %s is too close to a named character" % provider)
		blends[provider] = true
		var lead := provider.split("[")[0]
		var leads: Dictionary = faction_leads.get(faction, {})
		leads[lead] = true
		faction_leads[faction] = leads
	_check(blends.size() > 250, "600 people should get many distinct voices, got %d" % blends.size())
	for faction in faction_leads.keys():
		_check((faction_leads[faction] as Dictionary).size() <= 4, "a faction should lean on a small family of lead voices: %s" % str(faction_leads[faction].keys()))
	_check(DNA.for_radio_host("system.a") != DNA.for_radio_host("system.b"), "different systems get different hosts")
	# The blend maths.
	_check(is_equal_approx(DNA.blend_distance("af_aoede[0.7]+af_nova[0.3]", "af_aoede[0.7]+af_nova[0.3]"), 0.0), "identical blends: distance 0")
	_check(is_equal_approx(DNA.blend_distance("af_aoede[0.7]+af_nova[0.3]", "af_aoede[0.5]+af_nova[0.5]"), 0.4), "the old neutral was only 0.4 from Jenna")
	_check(is_equal_approx(DNA.blend_distance("af_aoede", "af_kore"), 2.0), "nothing in common: distance 2")
	# The reserved list is the named cast, not the generic fallback; and the
	# fallback itself is clear of all of them.
	var reserved: Array = DNA.reserved_blends()
	_check(reserved.has("af_aoede[0.7]+af_nova[0.3]") and reserved.has("af_bella"), "Jenna and Kaelen are reserved")
	var mappings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DNA.PROVIDER_MAPPINGS_PATH))["mappings"]
	var neutral := str(mappings["voice.neutral.v1"]["provider_voice"])
	_check(not reserved.has(neutral), "the neutral voice isn't reserved")
	_check(DNA.nearest_reserved_distance(neutral) >= DNA.RESERVED_MIN_DISTANCE, "the neutral voice %s is clear of every named one (%.2f)" % [neutral, DNA.nearest_reserved_distance(neutral)])
	# Hard-coded defaults in the speech code use the neutral blend, not Jenna's base voice.
	for path in ["res://scripts/TTSInterface.gd", "res://scripts/speech/KokoroSpeechProvider.gd", "res://scripts/tts_server.py"]:
		_check(not FileAccess.get_file_as_string(path).contains("\"af_aoede\""), "%s has no bare af_aoede default" % path)
	if _failures.is_empty():
		print("[PASS] Voice DNA tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
