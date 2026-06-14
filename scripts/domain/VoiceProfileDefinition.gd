class_name VoiceProfileDefinition
extends DomainDefinition

const SUPPORTED_SCHEMA_VERSION := 1

var display_name := ""
var language := "en"
var style_tags: Array[String] = []
var fallback_voice_profile_id: StringName


func load_from_dict(data: Dictionary) -> ValidationResult:
	var result := load_common(data, "voice", SUPPORTED_SCHEMA_VERSION)
	display_name = str(data.get("display_name", ""))
	language = str(data.get("language", "en"))
	for tag in data.get("style_tags", []):
		style_tags.append(str(tag))
	var fallback := str(data.get("fallback_voice_profile_id", ""))
	fallback_voice_profile_id = StringName() if fallback.is_empty() else DomainId.canonicalize(fallback)
	if display_name.is_empty():
		result.add_error("missing_display_name", "Voice display_name is required.")
	if not fallback_voice_profile_id.is_empty():
		var fallback_error := DomainId.validation_error(
			fallback_voice_profile_id,
			"voice"
		)
		if not fallback_error.is_empty():
			result.add_error(
				"invalid_reference",
				fallback_error,
				"fallback_voice_profile_id"
			)
	return result
