class_name VoiceDNA
extends RefCounted

## Stable, distinct Kokoro voices for generated people (plan Sections 3.3, 6.3).
##
## A voice is a blend of two base voices plus a speed, derived from the
## person's id; people of one faction share a "family" of base voices, so a
## faction sounds related without everyone sounding the same.
##
## Never sounds like the fixed cast: the base voices Kaelen and N.O.V.A. lead
## with (af_bella, bf_emma) are never used at all.

const FEMALE: Array[String] = ["af_sarah", "af_nicole", "af_aoede", "af_nova", "af_kore"]
const MALE: Array[String] = ["am_adam", "am_liam", "am_michael", "am_onyx", "am_fenrir", "am_puck", "am_eric", "am_echo"]
const FIXED_CAST_VOICES: Array[String] = ["af_bella", "bf_emma"]
## Faction families: which base voices a faction leans on.
const FAMILIES := [
	{"female": ["af_sarah", "af_nicole"], "male": ["am_onyx", "am_fenrir"]},
	{"female": ["af_aoede", "af_kore"], "male": ["am_liam", "am_adam"]},
	{"female": ["af_nova", "af_sarah"], "male": ["am_michael", "am_echo"]},
	{"female": ["af_kore", "af_nicole"], "male": ["am_puck", "am_eric"]},
	{"female": ["af_nicole", "af_aoede"], "male": ["am_fenrir", "am_liam"]},
]


## {provider_voice, speed} for a person. `faction_id` may be "".
## `force_female`: -1 picks by seed; 1 / 0 fix it (to match a portrait).
static func for_person(entity_id: String, faction_id: String = "", force_female: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("voice|%s" % entity_id)
	var family: Dictionary = FAMILIES[abs(hash("family|%s" % faction_id)) % FAMILIES.size()] if not faction_id.is_empty() else {}
	var female := rng.randi_range(0, 1) == 0
	if force_female >= 0:
		female = force_female == 1
	var pool: Array = (family.get("female", FEMALE) if female else family.get("male", MALE)) if not family.is_empty() else (FEMALE if female else MALE)
	var lead := str(pool[rng.randi_range(0, pool.size() - 1)])
	var others: Array = (FEMALE if female else MALE).filter(func(v): return v != lead)
	var second := str(others[rng.randi_range(0, others.size() - 1)])
	var weight := snappedf(rng.randf_range(0.55, 0.8), 0.05)
	return {
		"provider_voice": "%s[%.2f]+%s[%.2f]" % [lead, weight, second, 1.0 - weight],
		"speed": snappedf(rng.randf_range(0.9, 1.1), 0.02),
	}


## A system's radio host.
static func for_radio_host(system_id: String) -> Dictionary:
	return for_person("radio_host|%s" % system_id)


## Adds the voice to the game's registry and returns its profile id, which
## SpeechService.play() accepts. "" when the voice is empty.
static func register(voice: Dictionary) -> String:
	var provider := str(voice.get("provider_voice", ""))
	if provider.is_empty():
		return ""
	var profile_id := profile_id_for(voice)
	GameContentRegistry.shared().provider_voice_mappings[profile_id] = {"provider_voice": provider, "speed": float(voice.get("speed", 1.0))}
	return profile_id


static func profile_id_for(voice: Dictionary) -> String:
	return "voice.generated.%s" % str(abs(hash("%s|%s" % [voice.get("provider_voice", ""), voice.get("speed", 1.0)])))
