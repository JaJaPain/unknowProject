extends SceneTree

# A deliberately tiny, serial live probe for proposed quiet fixed-cast moments.
# It is not runtime content: it captures one raw candidate per character so we
# can learn the local model's failure modes before designing its validator.

const DEFAULT_ARTIFACT_PATH := "res://logs/quiet_moment_live_probe.json"
const QuietValidatorType := preload("res://scripts/story/QuietMomentLineValidator.gd")
const VoiceBankType := preload("res://scripts/story/FixedCastVoiceBank.gd")
const SoulRegistryType := preload("res://scripts/story/FixedCastSoulRegistry.gd")

var _llm: Node = null
var _rows: Array[Dictionary] = []
var _per_character := 1
var _capability := "kaelen_line"
var _artifact_path := DEFAULT_ARTIFACT_PATH
var _tail_only_mode := true
var _fixtures: Array[Dictionary] = [
	{
		"character_id": "kaelen",
		"label": "safe_low_pay_completion",
		"moment_id": "safe_low_pay_completion",
		"prompt": """Write exactly one optional spoken line for Kaelen after a completed job.
Facts allowed: the job was safe; the payout was modest; the Captain and Kaelen both got paid normally.
Do not invent a payout amount, fee, coffee, drinks, a past job, a new job, a rescue, danger, offscreen consequences, or a secret.
Voice: short or medium, precise, dry broker humor. The line must either make the player smile or ground them in the modest payout. Maximum 28 words.
Do not use Earth-calendar words or mention a crew; neither is a known fact.
End at this completed job; do not mention what happens next or offer anything. Do not reuse a phrase from the references below.
Give the modest payout a dry broker-specific turn; do not close with “no drama”, “all good”, or generic praise.
Return ONLY this JSON object: {"line":"the spoken line"}.""",
	},
	{
		"character_id": "nova",
		"label": "post_fight_stable_hull",
		"moment_id": "post_fight_stable_hull",
		"prompt": """Write exactly one optional spoken line for N.O.V.A. after a difficult fight.
Facts allowed: the fight is over; the hull is stable; sensors show no pursuit.
Do not invent exact damage, numbers, repairs, kills, another threat, a secret, safety, communications, or an order to the Captain.
Voice: clear, compact, observant. The line must either ground the player in a real current condition or earn its space with dry systems humor. Address the player only as Captain. Maximum 28 words.
Do not infer the Captain's physical condition or communications, and do not give an instruction. Do not reuse a phrase from the references below.
End with the current ship condition; do not use “let's”, “we should”, or “move”.
Return ONLY this JSON object: {"line":"the spoken line"}.""",
	},
]


func _initialize() -> void:
	var command_args: Array = OS.get_cmdline_args()
	command_args.append_array(OS.get_cmdline_user_args())
	for arg in command_args:
		if arg.begins_with("--per-character="):
			_per_character = clampi(int(arg.trim_prefix("--per-character=")), 1, 20)
		elif arg == "--large-review":
			_capability = "campaign_bible"
		elif arg == "--raw-full-line":
			_tail_only_mode = false
		elif arg.begins_with("--artifact="):
			_artifact_path = arg.trim_prefix("--artifact=")
	await process_frame
	_llm = get_root().get_node_or_null("LLMInterface")
	if _llm == null:
		push_error("[QuietMomentLiveProbe] LLMInterface autoload is unavailable.")
		quit(1)
		return
	var deadline := Time.get_ticks_msec() + 90000
	while not bool(_llm.get("small_model_verified")) \
			and Time.get_ticks_msec() < deadline:
		await process_frame
	if not bool(_llm.get("small_model_verified")):
		push_error("[QuietMomentLiveProbe] Small model did not become ready.")
		quit(1)
		return
	_run_next()


func _run_next() -> void:
	if _rows.size() >= _fixtures.size() * _per_character:
		_finish()
		return
	var fixture: Dictionary = _fixtures[_rows.size() % _fixtures.size()].duplicate(true)
	var run_number := _rows.size() / _fixtures.size() + 1
	fixture["run_number"] = run_number
	fixture["label"] = "%s_%02d" % [str(fixture.get("label", "")), run_number]
	var prompt := "%s\n%s" % [
		_tail_prompt(str(fixture.get("character_id", ""))) if _tail_only_mode else str(fixture.get("prompt", "")),
		_style_guidance(
			str(fixture.get("character_id", "")),
			"%s|%02d" % [str(fixture.get("character_id", "")), run_number],
			run_number - 1
		),
	]
	var request := HTTPRequest.new()
	root.add_child(request)
	request.timeout = float(_llm.call("request_timeout_for_capability", _capability))
	request.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			request.queue_free()
			var line := ""
			var transport_error := ""
			if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
				transport_error = "http_result_%d_code_%d" % [result, response_code]
			else:
				var outer := JSON.new()
				if outer.parse(body.get_string_from_utf8()) != OK:
					transport_error = "outer_json_invalid"
				elif outer.get_data() is Dictionary:
					var inner := JSON.new()
					var raw_line := str((outer.get_data() as Dictionary).get("response", "")).strip_edges()
					if inner.parse(raw_line) != OK or not inner.get_data() is Dictionary:
						transport_error = "inner_json_invalid"
					else:
						line = str((inner.get_data() as Dictionary).get("line", "")).strip_edges()
						if line.is_empty():
							transport_error = "inner_line_missing"
				else:
					transport_error = "outer_response_missing"
			var raw_line := line
			var prefix := _verified_prefix(str(fixture.get("character_id", ""))) if _tail_only_mode else ""
			if not prefix.is_empty() and not line.is_empty():
				line = "%s %s" % [prefix, line]
			var row := {
				"character_id": str(fixture.get("character_id", "")),
				"label": str(fixture.get("label", "")),
				"moment_id": str(fixture.get("moment_id", "")),
				"prompt": prompt,
				"raw_line": raw_line,
				"line": line,
				"transport_error": transport_error,
				"validator": QuietValidatorType.validate_line(
					str(fixture.get("character_id", "")),
					str(fixture.get("moment_id", "")),
					line
				),
			}
			_rows.append(row)
			print("[QuietMomentLiveProbe] %s: %s" % [row["character_id"], line])
			if not transport_error.is_empty():
				push_error("[QuietMomentLiveProbe] %s" % transport_error)
			_run_next()
	)
	var payload: Dictionary = _llm.call(
		"build_generation_body",
		_capability,
		prompt,
		"json",
		{"temperature": 0.7, "num_predict": 70, "seed": randi()}
	)
	var error := request.request(
		str(_llm.call("ollama_generate_url")),
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if error != OK:
		request.queue_free()
		_rows.append({"character_id": fixture.get("character_id", ""), "label": fixture.get("label", ""), "transport_error": "request_start_%d" % error})
		_run_next()


func _verified_prefix(character_id: String) -> String:
	if character_id == "kaelen":
		return "Payout cleared at the modest rate."
	if character_id == "nova":
		return "Hull stable; sensors show no pursuit."
	return ""


func _tail_prompt(character_id: String) -> String:
	var prefix := _verified_prefix(character_id)
	if character_id == "kaelen":
		return """Write only a fresh 5-12 word spoken tail for Kaelen. Code will put this verified fact before it: “Payout cleared at the modest rate.”
The tail is commentary only. Do not add any fact, amount, fee, job, client, danger, past/future event, coffee, drink, or instruction. Do not repeat or paraphrase the prefix or references.
Voice: precise dry broker humor. The tail must make the player smile without changing the completed outcome.
Return ONLY this JSON object: {"line":"the tail only"}."""
	return """Write only a fresh 5-12 word spoken tail for N.O.V.A. Code will put this verified fact before it: “Hull stable; sensors show no pursuit.”
The tail is dry systems commentary only. Do not add a condition, number, repair, threat, safety claim, communication, order, past/future event, or instruction. Do not repeat or paraphrase the prefix or references.
Voice: clear, compact, observant. Address the player only as Captain if needed.
Return ONLY this JSON object: {"line":"the tail only"}."""


func _style_guidance(character_id: String, reference_seed: String, combination_index: int) -> String:
	var state_id := "broker_neutral" if character_id == "kaelen" else "observant"
	var soul_block := SoulRegistryType.prompt_block(
		character_id, state_id, "quiet_moment", "neutral"
	)
	var references := VoiceBankType.style_reference_block(
		character_id, "evergreen", "quiet_moment",
		{
			"reference_seed": reference_seed,
			"reference_combination_index": combination_index,
		},
		3
	)
	return "%s\n%s" % [soul_block, references]


func _obvious_flags(character_id: String, line: String) -> Array[String]:
	var flags: Array[String] = []
	var lower := line.to_lower()
	if line.length() > 220:
		flags.append("too_long")
	if lower.contains("saved them") or lower.contains("they are safe now"):
		flags.append("generic_rescue_claim")
	if character_id == "kaelen" and lower.contains("n.o.v.a."):
		flags.append("cross_character_voice")
	if character_id == "nova" and lower.contains("shiny"):
		flags.append("cross_character_address")
	if character_id == "nova" and not lower.contains("hull") \
			and not lower.contains("sensor") and not lower.contains("pursuit"):
		flags.append("missing_grounding_anchor")
	return flags


func _finish() -> void:
	var artifact := {
		"tool": "quiet_moment_live_probe",
		"run_at_unix": Time.get_unix_time_from_system(),
		"rows": _rows,
	}
	var file := FileAccess.open(_artifact_path, FileAccess.WRITE)
	if file == null:
		push_error("[QuietMomentLiveProbe] Could not write %s." % _artifact_path)
		quit(1)
		return
	file.store_string(JSON.stringify(artifact, "\t"))
	file.close()
	var failures := _rows.filter(func(row):
		return not str(row.get("transport_error", "")).is_empty() \
			or not bool((row.get("validator", {}) as Dictionary).get("ok", false))
	)
	if failures.is_empty():
		print("[PASS] Quiet moment live probe")
		quit(0)
	else:
		quit(1)
