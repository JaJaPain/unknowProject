class_name OllamaProbe
extends Node

## Minimal synchronous-ish transport for the offline evaluation harness.
##
## Deliberately reuses LocalModelGateway.generation_body() rather than building
## its own request, so what this measures is what the GAME sends. If the two ever
## drift, the measurement stops being about the game and quietly becomes about
## the harness.

const GatewayType := preload("res://scripts/ai/LocalModelGateway.gd")
const DialogueCritic := preload("res://scripts/story/DialogueCritic.gd")

var _http: HTTPRequest
var _pending := false
var _result: Dictionary = {}


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 120.0
	add_child(_http)
	_http.request_completed.connect(_on_completed)


## Returns {ok, text, elapsed_ms, eval_count, prompt_eval_count, error}.
## Blocking by design: the harness is a batch tool, not gameplay.
func generate(capability: String, prompt: String, options: Dictionary) -> Dictionary:
	var body := GatewayType.generation_body(
		capability, prompt, "qwen3:4b", "json", options
	)
	return await _post(body)


## Same call without JSON mode, for measuring prose the game asks for as prose.
func generate_text(capability: String, prompt: String, options: Dictionary) -> Dictionary:
	var body := GatewayType.generation_body(
		capability, prompt, "qwen3:4b", "", options
	)
	return await _post(body)


func generate_review(job: Dictionary, model: String = "qwen3:4b", seed_value: int = 12345) -> Dictionary:
	var options := DialogueCritic.OPTIONS.duplicate()
	options["seed"] = seed_value
	var body := GatewayType.generation_body("lounge_bundle_review", DialogueCritic.prompt(job), model, DialogueCritic.schema(str(job["kind"])), options)
	var response := await _post(body)
	if bool(response.get("ok", false)) and str(response.get("model", "")) != str(body["model"]):
		response["ok"] = false
		response["error"] = "review_model_mismatch"
	response["request"] = body
	return response


func _post(body: Dictionary) -> Dictionary:
	_pending = true
	_result = {}
	var started := Time.get_ticks_msec()
	var err := _http.request(
		GatewayType.OLLAMA_GENERATE_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if err != OK:
		_pending = false
		return {"ok": false, "error": "request_failed:%d" % err, "elapsed_ms": 0}
	while _pending:
		await get_tree().process_frame
	var elapsed := Time.get_ticks_msec() - started
	_result["elapsed_ms"] = elapsed
	return _result


func _on_completed(
	result_code: int,
	response_code: int,
	_headers: PackedStringArray,
	response_body: PackedByteArray
) -> void:
	if result_code != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_result = {"ok": false, "error": "http_%d" % response_code}
		_pending = false
		return
	var parsed: Variant = JSON.parse_string(response_body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_result = {"ok": false, "error": "envelope_not_json"}
		_pending = false
		return
	var envelope: Dictionary = parsed
	_result = {
		"ok": true,
		"model": str(envelope.get("model", "")),
		"text": str(envelope.get("response", "")),
		"eval_count": int(envelope.get("eval_count", 0)),
		"prompt_eval_count": int(envelope.get("prompt_eval_count", 0)),
		"done_reason": str(envelope.get("done_reason", "")),
		"error": "",
	}
	_pending = false


## Peak resident size of the loaded models, from Ollama's own accounting. This is
## the model footprint only -- it is NOT the whole-process figure the 8GB target
## refers to, and must not be reported as if it were.
func model_footprint() -> Dictionary:
	return await _get_json("http://127.0.0.1:11434/api/ps")


func model_identity(model: String) -> Dictionary:
	var tags := await _get_json("http://127.0.0.1:11434/api/tags")
	for entry in tags.get("models", []):
		if str(entry.get("name", "")) == model:
			return entry.duplicate(true)
	return {}


func _get_json(url: String) -> Dictionary:
	var probe := HTTPRequest.new()
	probe.timeout = 15.0
	add_child(probe)
	var done := [false]
	var payload := [{}]
	probe.request_completed.connect(
		func(_r: int, code: int, _h: PackedStringArray, b: PackedByteArray) -> void:
			if code == 200:
				var parsed: Variant = JSON.parse_string(b.get_string_from_utf8())
				if parsed is Dictionary:
					payload[0] = parsed
			done[0] = true
	)
	if probe.request(url) != OK:
		probe.queue_free()
		return {}
	while not done[0]:
		await get_tree().process_frame
	probe.queue_free()
	return payload[0]
