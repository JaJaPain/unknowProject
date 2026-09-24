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
		blends[provider] = true
		var lead := provider.split("[")[0]
		var leads: Dictionary = faction_leads.get(faction, {})
		leads[lead] = true
		faction_leads[faction] = leads
	_check(blends.size() > 250, "600 people should get many distinct voices, got %d" % blends.size())
	for faction in faction_leads.keys():
		_check((faction_leads[faction] as Dictionary).size() <= 4, "a faction should lean on a small family of lead voices: %s" % str(faction_leads[faction].keys()))
	_check(DNA.for_radio_host("system.a") != DNA.for_radio_host("system.b"), "different systems get different hosts")
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
