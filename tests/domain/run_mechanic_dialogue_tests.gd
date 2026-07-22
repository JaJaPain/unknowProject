extends SceneTree

var UIManagerType: GDScript = null
var _failures: Array[String] = []


func _initialize() -> void:
	UIManagerType = load("res://scripts/UIManager.gd")
	if UIManagerType == null:
		push_error("[FAIL] UIManager.gd did not load.")
		quit(1)
		return
	_test_mechanic_rejects_ui_style_faction_status()
	_test_mechanic_prompt_keeps_faction_status_private()
	if _failures.is_empty():
		print("[PASS] Mechanic dialogue tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_mechanic_rejects_ui_style_faction_status() -> void:
	for line in [
		"Your Wary rep is showing, pilot.",
		"Zenith standing: -30. Try not to make it worse.",
		"Your reputation score is 50 with Aurelia.",
	]:
		_expect(
			UIManagerType._mechanic_line_leaks_faction_standing(line),
			"Mechanic standing guard accepted UI-style faction status: %s" % line
		)
	_expect(
		not UIManagerType._mechanic_line_leaks_faction_standing(
			"Dockhands say you have a talent for making powerful people nervous."
		),
		"Mechanic standing guard rejected natural in-world gossip."
	)


func _test_mechanic_prompt_keeps_faction_status_private() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect mechanic dialogue prompt.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		not source.contains("Worst faction rep tier")
			and not source.contains("Best faction rep tier")
			and source.contains("Private dockside subtext")
			and source.contains("Faction status is private subtext only"),
		"Mechanic prompt still exposes faction reputation labels to player-facing prose."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
