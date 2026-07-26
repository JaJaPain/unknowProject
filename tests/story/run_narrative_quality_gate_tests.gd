extends SceneTree

const GateType := preload("res://scripts/story/NarrativeQualityGate.gd")
const LedgerType := preload("res://scripts/story/NarrativeFingerprintLedger.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	var ledger = LedgerType.new()
	ledger.register("The relay went dark before the gate cleared.", "lounge")
	_expect(str(GateType.validate_line("The relay went dark before the gate cleared.", ledger, "lounge").get("reason", "")) == "exact_duplicate", "Exact duplicate must retain its explanatory reason.")
	_expect(str(GateType.validate_line("The convoy is late.", ledger, "lounge", [], ["convoy"]).get("reason", "")) == "forbidden_token:convoy", "Forbidden token must be a hard failure.")
	var reviewed: Dictionary = GateType.validate_line("Mara says the relay is still dark.", ledger, "lounge", ["Mara", "relay"])
	_expect(bool(reviewed.get("ok", false)) and (reviewed.get("warnings", []) as Array).is_empty(), "Allowed alias should not be unexplained reference.")
	var unexplained: Dictionary = GateType.validate_line("Vantrel says the relay is still dark.", ledger, "lounge", ["relay"])
	_expect(
		bool(unexplained.get("ok", false))
			and (unexplained.get("warnings", []) as Array).has("unexplained_reference:Vantrel"),
		"Unknown proper name should remain an explainable review warning."
	)
	var ordinary_start: Dictionary = GateType.validate_line("The relay is still dark.", ledger, "lounge", ["relay"])
	_expect(
		(ordinary_start.get("warnings", []) as Array).is_empty(),
		"Sentence-leading ordinary words should not be flagged as unexplained names."
	)
	_test_quality_ledger_debug_view_wiring()
	if _failures.is_empty():
		print("[PASS] Narrative quality gate tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_quality_ledger_debug_view_wiring() -> void:
	var panel_file := FileAccess.open("res://scripts/ui/DevPanel.gd", FileAccess.READ)
	var root_file := FileAccess.open("res://scripts/GameRoot.gd", FileAccess.READ)
	_expect(panel_file != null and root_file != null, "Could not inspect quality-ledger debug wiring.")
	if panel_file == null or root_file == null:
		return
	var panel_source := panel_file.get_as_text()
	var root_source := root_file.get_as_text()
	panel_file.close()
	root_file.close()
	_expect(
		panel_source.contains("Campaign Narrative Quality Ledger")
			and panel_source.contains("quality_ledger_summary")
			and root_source.contains("func _dev_format_narrative_quality_ledger")
			and root_source.contains("quality_ledger_summary")
			and root_source.contains("Recent quality rejections")
			and root_source.contains("fallback_reason"),
		"DevPanel does not expose the campaign quality-ledger inspection view."
	)
	_expect(
		root_source.contains("quality_warning"),
		"Accepted quality warnings are not retained for designer inspection."
	)
