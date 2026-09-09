class_name BakedAudioIndex
extends RefCounted

## Key-building and voice identification for the ENGLISH-ONLY baked audio layers.
##
## PURE: strings in, strings out. It exists as its own module because the code it
## replaces lived in TTSInterface, which depends on autoloads and therefore cannot
## be instantiated in a headless test run -- and this is precisely the logic that
## must not be shipped untested. A mistake here does not crash; it silently serves
## the wrong voice, or silently serves English audio to a translated build.
##
## Nothing here decides whether a clip EXISTS. Missing clips are the normal case
## (newly authored lines, and every line in a non-English build), so lookups are
## expected to miss and the caller falls through to live synthesis.

## Kokoro lead -> the Orpheus voice its lines were baked with. Fixed rather than
## random so a given enemy voice keeps one identity across sessions.
const ORPHEUS_VOICE_FOR_LEAD := {
	"am_onyx": "leo", "am_adam": "dan", "am_fenrir": "zac", "am_liam": "tara",
	"am_puck": "leah", "am_eric": "jess", "am_echo": "mia",
}


## True only when the game is running in English. Baked audio is gated on this:
## serving an English recording for a translated line is worse than serving
## nothing, because the live path would have produced the right words.
static func is_english(locale: String) -> bool:
	return locale.to_lower().begins_with("en")


## Which fixed-cast character a voice belongs to, or "" for anyone else.
## Matches the profile id AND the raw provider voice, because callers reach this
## through several different paths and a miss would cost the clone.
static func cast_character_for_voice(voice_id: String, kaelen_voice_id: String) -> String:
	var v := voice_id.to_lower().strip_edges()
	if v.is_empty():
		return ""
	if v == "voice.kaelen.v1" or v == kaelen_voice_id.to_lower():
		return "kaelen"
	if v == "voice.nova.v1" or v.begins_with("bf_emma"):
		return "nova"
	return ""


## The Kokoro LEAD out of a blend ("am_onyx[0.7]+am_michael[0.3]" -> "am_onyx").
## Returns "" for a non-blend voice, so ordinary speakers skip the taunt layer
## instead of being matched against it.
static func lead_voice_of(voice_id: String) -> String:
	if not voice_id.contains("["):
		return ""
	return voice_id.split("[")[0].strip_edges()


## Orpheus voice for a Kokoro lead, or "" when that lead was never baked.
static func orpheus_voice_for_lead(lead_voice: String) -> String:
	return str(ORPHEUS_VOICE_FOR_LEAD.get(lead_voice, ""))


## Manifest key for a fixed-cast line. Empty when either half is missing, so an
## empty key can never accidentally match a real entry.
static func cast_key(character: String, clean_text: String) -> String:
	if character.strip_edges().is_empty() or clean_text.strip_edges().is_empty():
		return ""
	return "%s|%s" % [character.to_lower(), clean_text]


## Manifest key for a baked taunt, addressed by ORPHEUS voice name.
static func orpheus_key(orpheus_voice: String, clean_text: String) -> String:
	if orpheus_voice.strip_edges().is_empty() or clean_text.strip_edges().is_empty():
		return ""
	return "%s|%s" % [orpheus_voice, clean_text]
