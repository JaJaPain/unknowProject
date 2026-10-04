extends PanelContainer

## Distances and speeds as the player reads them (WorldScale).
const _WS := preload("res://scripts/domain/WorldScale.gd")

var manager: Node
var ui: Control
var mission_id := ""
var rows: VBoxContainer
var status: Label
var _signature := ""
var _elapsed := 0.0
## N.O.V.A.'s current question, shown above the choices while they are open.
var _nova_question := ""
const NovaLines := preload("res://scripts/story/NovaInvestigationLines.gd")

func setup(owner_ui: Control, quest_manager: Node) -> void:
	ui = owner_ui
	manager = quest_manager
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -280
	offset_right = 280
	offset_top = -270
	offset_bottom = 270
	custom_minimum_size = Vector2(560, 540)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.065, 0.09, 0.98)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 420
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 7)
	scroll.add_child(rows)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status)
	var close := Button.new()
	close.text = "Close investigation"
	close.pressed.connect(func(): manager.cancel_investigation_scan(); hide())
	layout.add_child(close)
	manager.investigation_scan_updated.connect(_scan_status)
	hide()

func open_mission(id: String) -> void:
	load("res://scripts/ui/Wiki.gd").unlock("investigations")
	if id != mission_id:
		_nova_question = ""
	mission_id = id
	_signature = ""
	status.text = "Hold within %s, below %s, for three seconds. Combat interrupts scanning." % [_WS.label(300.0), _WS.speed_label(10.0)]
	show()
	_refresh()

func _process(delta: float) -> void:
	if not visible: return
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0.0
		_refresh()

func _refresh() -> void:
	if is_instance_valid(GlobalState.player) and bool(GlobalState.player.get("is_docked")):
		manager.cancel_investigation_scan()
		hide()
		return
	var view: Dictionary = manager.investigation_panel_view(mission_id)
	if view.is_empty():
		hide()
		return
	var signature := JSON.stringify(view)
	if signature == _signature: return
	_signature = signature
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	_label(str(view["title"]))
	if not _nova_question.is_empty() and not view["branches"].is_empty():
		_label("N.O.V.A.: " + _nova_question)
	if view["phase"] in ["ready", "closed"]:
		_label("Finding filed. Dock at the assigned station to collect payment.")
	elif not str(view.get("extract_site_id", "")).is_empty():
		_label("Committed. Fly to the cache and hold within %s, below %s, to extract it." % [_WS.label(300.0), _WS.speed_label(10.0)])
		var cache_id := str(view["extract_site_id"])
		_button("Extract the cache", "", func():
			var report: Dictionary = manager.begin_investigation_scan(mission_id, cache_id)
			status.text = "Extracting…" if bool(report.get("ok", false)) else _reason(str(report.get("reason", "Unavailable"))))
	elif view["recipe"] == "survey_discrepancy":
		_label("Certification pays the full reward if correct, or 25% if incorrect. You may file an unverified report for 50%.")
	elif view["recipe"] == "transmitter_lure":
		_label("A beacon advertises a cache. Check its code against the registry if you want to know whether it is genuine. Extraction pays 150%; a report pays 75% and keeps you clear of it.")
	elif view["recipe"] == "unstable_archive":
		_label("The archive is failing. A repair kit holds it in place for 125%. Recovering the backup lets you reconstruct a copy for the full reward, or file a report for 50%.")
	else:
		_label("Preserve the verified records for the full reward, or file an unverified report for 50%.")
	for site: Dictionary in view["sites"]:
		var id := str(site["site_id"])
		_button("Set course: " + str(site["label"]), "", func():
			var target: Node3D = manager.investigation_site_target(mission_id, id)
			if target == null: return
			GlobalState.active_target = target
			ui._command_selected_target("APPROACH"))
		if id != "search" and not bool(site["scanned"]):
			_button("Scan " + str(site["label"]), str(site["scan_reason"]), func():
				var report: Dictionary = manager.begin_investigation_scan(mission_id, id)
				status.text = "Scanning…" if bool(report.get("ok", false)) else _reason(str(report.get("reason", "Unavailable"))))
	_label("Recorded evidence")
	if view["evidence"].is_empty(): _label("No scans recorded.")
	for line: String in view["evidence"]: _label(line)
	for branch: Dictionary in view["branches"]:
		var id := str(branch["id"])
		var site_id := str(view["resolve_site_id"])
		var revision := int(view["revision"])
		_button(str(branch["label"]), str(branch["reason"]), func():
			var report: Dictionary = manager.dispatch_investigation_command({"mission_id": mission_id, "site_id": site_id, "action": "resolve", "branch_id": id, "expected_revision": revision})
			var filed := "Committed. Fly to the cache." if bool(report.get("awaiting_extraction", false)) else "Finding filed. Return for payment."
			status.text = filed if bool(report.get("ok", false)) else _reason(str(report.get("reason", "Unavailable")))
			if bool(report.get("ok", false)) and not bool(report.get("replayed", false)):
				_nova_question = ""
				if bool(report.get("awaiting_extraction", false)):
					var ambush := bool(report.get("spawn_hostile", false))
					_nova_say(NovaLines.committed(ambush, randi()), "ambush" if ambush else "nav")
				else:
					_nova_say(NovaLines.filed(randi()), "companion")
			_signature = ""
			_refresh())

func _scan_status(report: Dictionary) -> void:
	if not visible or str(report.get("mission_id", "")) != mission_id: return
	if report.get("state", "") == "holding":
		status.text = "Scanning: %d%%" % int(float(report.get("progress", 0.0)) * 100)
	elif bool(report.get("ok", false)):
		status.text = "Scan recorded. Review the evidence."
		if str(report.get("outcome_tag", "")) == "extracted":
			status.text = "Cache extracted. Return for payment."
			_nova_say(NovaLines.extracted(randi()), "companion")
		else:
			_ask_decision()
	else:
		status.text = _reason(str(report.get("reason", "Scan interrupted")))

## After a scan, she asks what to do with what it found.
func _ask_decision() -> void:
	var view: Dictionary = manager.investigation_panel_view(mission_id)
	if view.is_empty() or view["branches"].is_empty():
		return
	_nova_question = NovaLines.decision(str(view["recipe"]), bool(view.get("verification_scanned", false)), bool(view.get("codes_match", false)), randi())
	_nova_say(_nova_question, "mystery")
	_signature = ""
	_refresh()


func _nova_say(text: String, event: String) -> void:
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		nova.ask_captain(text, event)


func _button(text: String, reason: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.disabled = not reason.is_empty()
	button.tooltip_text = _reason(reason)
	button.pressed.connect(action)
	rows.add_child(button)
	if not reason.is_empty(): _label(_reason(reason))

func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 500
	rows.add_child(label)

static func _reason(reason: String) -> String:
	return str({"out_of_range": "Approach within %s" % _WS.label(300.0), "too_fast": "Slow below %s" % _WS.speed_label(10.0), "in_combat": "Scanning is unavailable during combat", "ship_unavailable": "Undock before scanning", "stale_revision": "The investigation changed; review the updated evidence"}.get(reason, reason))
