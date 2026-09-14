extends SceneTree

const Probe := preload("res://tools/quality_eval/OllamaProbe.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var probe := Probe.new()
	root.add_child(probe)
	await process_frame
	var result: Dictionary = await probe.generate(
		"mission_conversation",
		"Reply with exactly this JSON: {\"opening\":\"Ready when you are.\"}",
		{"temperature": 0.95, "num_predict": 520, "seed": 12345}
	)
	print("ok=", result.get("ok", false), " elapsed_ms=", result.get("elapsed_ms", 0))
	print("text=", JSON.stringify(str(result.get("text", "")).substr(0, 300)))
	print("eval_count=", result.get("eval_count", 0), " prompt_tokens=", result.get("prompt_eval_count", 0))
	print("error=", result.get("error", ""))
	quit(0)
