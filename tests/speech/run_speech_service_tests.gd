extends SceneTree

const GAMEPLAY_SPEECH_CALLERS := [
	"res://scripts/GameRoot.gd",
	"res://scripts/QuestManager.gd",
	"res://scripts/UIManager.gd",
]

var _failures: Array[String] = []


func _initialize() -> void:
	var service = load("res://scripts/speech/SpeechService.gd").new()
	_expect(
		service.resolve_voice_profile("neutral") == &"voice.kaelen.v1",
		"Legacy neutral speaker did not resolve to Kaelen."
	)
	_expect(
		service.resolve_voice_profile("zenith")
		== &"voice.agent.zenith.v1",
		"Faction voice profile resolution failed."
	)
	_expect(
		service.resolve_voice_profile("Jenna Kross")
		== &"voice.jenna_kross.v1",
		"NPC display-name voice profile resolution failed."
	)
	_expect(
		service.resolve_voice_profile("Director Voss")
		== &"voice.agent.zenith.v1",
		"Named faction-agent voice profile resolution failed."
	)
	_expect(
		service.prepare_text("Shiny, we have work.", "voice.kaelen.v1")
		== "Shiny, we have work.",
		"Kaelen's Shiny rule was not preserved."
	)
	_expect(
		service.prepare_text("Shiny, your ship is ready.", "voice.jenna_kross.v1")
		== "Indy, your ship is ready.",
		"Non-Kaelen Indy rule was not applied."
	)
	_expect(
		service.prepare_text(
			"(quietly) Shiny, proceed. [static]",
			"voice.agent.vanguard.v1"
		) == "Indy, proceed.",
		"Text cleanup and tone guard did not produce one stable line."
	)

	var kaelen_delivery: Dictionary = service.provider.resolve_delivery(
		&"voice.kaelen.v1"
	)
	_expect(
		kaelen_delivery.get("provider_voice", "") == "af_bella",
		"Kaelen provider mapping changed unexpectedly."
	)
	var jenna_delivery: Dictionary = service.provider.resolve_delivery(
		&"voice.jenna_kross.v1"
	)
	_expect(
		str(jenna_delivery.get("provider_voice", "")).begins_with("af_aoede"),
		"Jenna provider mapping should use af_aoede base voice."
	)
	_expect(
		is_equal_approx(float(jenna_delivery.get("speed", 0.0)), 1.0),
		"Jenna provider speed changed unexpectedly."
	)

	var voss_delivery: Dictionary = service.provider.resolve_delivery(
		&"voice.agent.zenith.v1"
	)
	_expect(
		str(voss_delivery.get("provider_voice", "")).begins_with("am_adam"),
		"Zenith agent should use am_adam base voice."
	)
	var cassen_delivery: Dictionary = service.provider.resolve_delivery(
		&"voice.cassen_vane.v1"
	)
	_expect(
		str(cassen_delivery.get("provider_voice", "")).begins_with("am_onyx"),
		"Cassen Vane should use am_onyx base voice."
	)

	for path in GAMEPLAY_SPEECH_CALLERS:
		_check_gameplay_caller(path)

	if _failures.is_empty():
		print("[PASS] Unified speech service tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check_gameplay_caller(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "Could not inspect speech caller '%s'." % path)
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		not source.contains("TTSInterface"),
		"Gameplay caller bypasses SpeechService: %s" % path
	)
	var provider_voice_pattern := RegEx.new()
	provider_voice_pattern.compile("\\b[afm]{2}_[a-z]+\\b")
	_expect(
		provider_voice_pattern.search(source) == null,
		"Gameplay caller contains a provider-specific voice name: %s" % path
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
