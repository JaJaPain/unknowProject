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
		== "Pilot, your ship is ready.",
		"Non-Kaelen Shiny cleanup was not applied."
	)
	_expect(
		service.prepare_text(
			"(quietly) Shiny, proceed. [static]",
			"voice.agent.vanguard.v1"
		) == "Pilot, proceed.",
		"Text cleanup and tone guard did not produce one stable line."
	)
	var follow_up: String = service.prepare_followup_text(
		"Indy, make it quick; the dock crew is already betting against you.",
		"voice.agent.vanguard.v1"
	)
	_expect(
		follow_up == "Make it quick; the dock crew is already betting against you.",
		"Follow-up address cleanup did not remove repeated Indy vocative."
	)
	_expect(
		service.normalize_tts_pronunciation(
			"Destroy 3 DUSTBORN ships for ZENITH."
		) == "Destroy 3 Dustborn ships for Zenith.",
		"TTS pronunciation cleanup did not title-case all-caps names."
	)
	_expect(
		service.normalize_tts_pronunciation(
			"Keep ROE, TTS, and SC readable."
		) == "Keep ROE, TTS, and SC readable.",
		"TTS pronunciation cleanup should preserve known acronyms."
	)
	var filler: Dictionary = service.latency_filler_clip_request(
		"Broker Kaelen",
		"voice.kaelen.v1",
		"tts_cache",
		0.8,
		false,
		2
	)
	_expect(
		bool(filler.get("ok", false))
			and str(filler.get("word", "")) == "well"
			and str(filler.get("source", "")) == "prerecorded_latency_filler"
			and not bool(filler.get("semantic_content", true))
			and not bool(filler.get("may_replace_required_text", true))
			and not bool(filler.get("advances_state", true))
			and not bool(filler.get("reveals_facts", true))
			and not bool(filler.get("counts_as_generated_line", true)),
		"Kaelen latency filler request did not preserve the non-semantic safety contract."
	)
	var nova_filler: Dictionary = service.latency_filler_clip_request(
		"N.O.V.A.",
		"voice.nova.v1",
		"llm_generation",
		1.0,
		false,
		3
	)
	_expect(
		bool(nova_filler.get("ok", false))
			and str(nova_filler.get("word", "")) == "ahh"
			and str(nova_filler.get("voice_profile_id", "")) == "voice.nova.v1",
		"N.O.V.A. latency filler request was not accepted for a short LLM wait."
	)
	for rejected in [
		service.latency_filler_clip_request(
			"Jenna Kross",
			"voice.jenna_kross.v1",
			"tts_cache",
			0.8,
			false
		),
		service.latency_filler_clip_request(
			"Broker Kaelen",
			"voice.kaelen.v1",
			"dialogue",
			0.8,
			false
		),
		service.latency_filler_clip_request(
			"Broker Kaelen",
			"voice.kaelen.v1",
			"tts_cache",
			0.8,
			true
		),
		service.latency_filler_clip_request(
			"Broker Kaelen",
			"voice.kaelen.v1",
			"tts_cache",
			5.0,
			false
		),
	]:
		_expect(
			not bool(rejected.get("ok", true))
				and not bool(rejected.get("may_replace_required_text", true))
				and not bool(rejected.get("counts_as_generated_line", true)),
			"Latency filler rejection did not preserve safety flags."
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
