extends SceneTree

# Checks candidate taunt lines against the REAL runtime validators, so authoring
# feedback matches what the game would actually accept rather than someone's
# recollection of the rules.
#
# Reads res://logs/taunt_candidates.json: {"cause": "...", "lines": ["..."]}

const CauseType := preload("res://scripts/combat/TauntCause.gd")
const INPUT_PATH := "res://logs/taunt_candidates.json"


func _initialize() -> void:
	await process_frame
	var llm: Node = get_root().get_node_or_null("LLMInterface")
	if llm == null:
		push_error("[Check] LLMInterface unavailable.")
		quit(1)
		return
	if not FileAccess.file_exists(INPUT_PATH):
		push_error("[Check] %s not found." % INPUT_PATH)
		quit(1)
		return
	var file := FileAccess.open(INPUT_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("[Check] input is not an object.")
		quit(1)
		return
	var cause := str((parsed as Dictionary).get("cause", "")).strip_edges()
	var lines: Array = (parsed as Dictionary).get("lines", [])
	var failures := 0
	for raw in lines:
		var text := str(raw)
		var reason := str(llm.validate_taunt_line(text))
		var role := str(llm.taunt_role_confusion(text, cause)) if llm.has_method("taunt_role_confusion") else ""
		var words := text.split(" ", false).size()
		var verdict := "OK"
		if not reason.is_empty():
			verdict = "REJECT(%s)" % reason
			failures += 1
		elif not role.is_empty():
			verdict = "REJECT(%s)" % role
			failures += 1
		elif words > 18:
			verdict = "OK but long"
		print("%-16s %2d words  %3d chars  | %s" % [verdict, words, text.length(), text])
	print("[Check] %d line(s), %d rejected." % [lines.size(), failures])
	quit(0 if failures == 0 else 1)
