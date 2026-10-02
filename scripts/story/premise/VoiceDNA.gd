class_name VoiceDNA
extends RefCounted

## Stable, distinct Kokoro voices for generated people (plan Sections 3.3, 6.3).
##
## A voice is a blend of two base voices plus a speed, derived from the
## person's id; people of one faction share a "family" of base voices, so a
## faction sounds related without everyone sounding the same.
##
## Never sounds like the fixed cast: the base voices Kaelen and N.O.V.A. lead
## with (af_bella, bf_emma) are never used at all. And never close to any named
## character's blend (Jenna, the recurring cast, the agents): see
## RESERVED_MIN_DISTANCE.

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
## Never close to a named character's voice (RESERVED_MIN_DISTANCE): the
## generated cast used to land on blends like Jenna's (playtest 2026-10-02).
static func for_person(entity_id: String, faction_id: String = "", force_female: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("voice|%s" % entity_id)
	var family: Dictionary = FAMILIES[abs(hash("family|%s" % faction_id)) % FAMILIES.size()] if not faction_id.is_empty() else {}
	var female := rng.randi_range(0, 1) == 0
	if force_female >= 0:
		female = force_female == 1
	var pool: Array = (family.get("female", FEMALE) if female else family.get("male", MALE)) if not family.is_empty() else (FEMALE if female else MALE)
	var voice := {}
	for attempt in 24:
		# Stay in the faction's family as long as reasonable, so a faction keeps
		# sounding related; only then look beyond it.
		var from: Array = pool if attempt < 20 else (FEMALE if female else MALE)
		var lead := str(from[rng.randi_range(0, from.size() - 1)])
		var others: Array = (FEMALE if female else MALE).filter(func(v): return v != lead)
		var second := str(others[rng.randi_range(0, others.size() - 1)])
		var weight := snappedf(rng.randf_range(0.55, 0.8), 0.05)
		voice = {
			"provider_voice": "%s[%.2f]+%s[%.2f]" % [lead, weight, second, 1.0 - weight],
			"speed": snappedf(rng.randf_range(0.9, 1.1), 0.02),
		}
		if nearest_reserved_distance(str(voice["provider_voice"])) >= RESERVED_MIN_DISTANCE:
			break
	return voice


## How different two blends must be (L1 distance between their base-voice
## weights: 0 = identical, 2 = nothing in common) from every named voice.
const RESERVED_MIN_DISTANCE := 0.6
const PROVIDER_MAPPINGS_PATH := "res://data/content/voice_provider_kokoro.json"
## Generic profiles that anyone may sound like.
const UNRESERVED_PROFILES := ["voice.neutral.v1"]
static var _reserved: Array = []


## Every named character's blend (the fixed cast, the recurring cast, the
## station agents), from the provider mappings.
static func reserved_blends() -> Array:
	if _reserved.is_empty():
		var text := FileAccess.get_file_as_string(PROVIDER_MAPPINGS_PATH)
		var parsed = JSON.parse_string(text) if not text.is_empty() else null
		var mappings: Dictionary = parsed.get("mappings", {}) if parsed is Dictionary else {}
		for profile in mappings:
			if str(profile) in UNRESERVED_PROFILES:
				continue
			_reserved.append(str((mappings[profile] as Dictionary).get("provider_voice", "")))
	return _reserved


## {base voice: weight} for "a[0.70]+b[0.30]" (a bare name is weight 1).
static func blend_weights(provider_voice: String) -> Dictionary:
	var out := {}
	for part in provider_voice.split("+", false):
		var piece := part.strip_edges()
		var open := piece.find("[")
		if open < 0:
			out[piece] = float(out.get(piece, 0.0)) + 1.0
		else:
			var name := piece.substr(0, open)
			out[name] = float(out.get(name, 0.0)) + float(piece.substr(open + 1, piece.find("]") - open - 1))
	var total := 0.0
	for k in out:
		total += float(out[k])
	if total > 0.0:
		for k in out:
			out[k] = float(out[k]) / total
	return out


static func blend_distance(a: String, b: String) -> float:
	var wa := blend_weights(a)
	var wb := blend_weights(b)
	var d := 0.0
	for k in wa:
		d += absf(float(wa[k]) - float(wb.get(k, 0.0)))
	for k in wb:
		if not wa.has(k):
			d += float(wb[k])
	return d


static func nearest_reserved_distance(provider_voice: String) -> float:
	var best := 2.0
	for reserved in reserved_blends():
		best = minf(best, blend_distance(provider_voice, str(reserved)))
	return best


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
