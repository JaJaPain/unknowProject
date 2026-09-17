extends SceneTree

const Layout = preload("res://scripts/ui/UILayoutManager.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui_script = load("res://scripts/UIManager.gd")
	_expect(ui_script != null and ui_script.can_instantiate(), "UIManager failed to compile.")
	# Exercise viewport sizes, all visibility combinations, and oversized content.
	for viewport in [Vector2(640, 480), Vector2(1280, 720), Vector2(1920, 1080), Vector2(3840, 2160)]:
		for mask in range(1 << Layout.DEFAULT_ORDER.size()):
			var entries: Array = []
			for i in range(Layout.DEFAULT_ORDER.size()):
				if mask & (1 << i):
					entries.append({"id": Layout.DEFAULT_ORDER[i], "size": Vector2(400 + i * 100, 220 + i * 100)})
			for quest_size in [Vector2(380, 160), Vector2(900, 1200)]:
				var placements := Layout.solve_layout(viewport, entries, quest_size)
				var rects: Array[Rect2] = []
				for entry in entries:
					var placed: Dictionary = placements[entry.id]
					rects.append(Rect2(placed.position, entry.size * placed.scale))
					_expect(is_equal_approx(placed.position.x, 20), "Left panel escaped stack.")
				var quest: Dictionary = placements.quest
				var quest_rect := Rect2(quest.position, quest_size * quest.scale)
				_expect(is_equal_approx(quest_rect.end.x, viewport.x - 20), "Mission card not right-aligned.")
				_expect(quest_rect.position.y >= 88, "Mission card intersects top controls.")
				rects.append(quest_rect)
				_check_rects(rects, viewport)
	var host := Control.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panels := {}
	for id in Layout.PANEL_IDS:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(380, 160)
		host.add_child(panel)
		panels[id] = panel
	var manager = Layout.new()
	manager.setup(panels.hud, panels.chat, panels.overview, panels.target, host, panels.quest)
	var combat := Control.new()
	host.add_child(combat)
	combat.position = Vector2(600, 350)
	combat.size = Vector2(600, 600)
	manager.register_panel("combat", combat)
	manager.reset_defaults(false)
	for step in range(4):
		panels.target.visible = step % 2 == 0
		combat.visible = step % 2 == 1
		panels.quest.custom_minimum_size.y = 160 + step * 180
		panels.overview.position = Vector2(20, 20) # Simulate stale overlapping coordinates.
		manager.enforce_layout()
		_expect(combat.position == Vector2(600, 350) and combat.size == Vector2(600, 600) and combat.scale == Vector2.ONE, "HUD layout moved or shrank the combat wheel.")
		var rects: Array[Rect2] = []
		for panel in panels.values():
			if panel.visible:
				rects.append(panel.get_global_rect())
		_check_rects(rects, host.get_viewport_rect().size)
	manager.toggle_edit_mode()
	manager._drag_panel_id = "chat"
	var move := InputEventMouseMotion.new()
	move.position = panels.hud.get_global_rect().get_center()
	manager.handle_input(move)
	_expect(manager._order[0] == "chat", "Dragging must reorder the stack.")
	manager.reset_defaults(false)
	_expect(manager._order == Layout.DEFAULT_ORDER, "New campaign did not restore default order.")
	host.free()
	if failures.is_empty():
		print("[PASS] HUD layout: 128 scenarios, live controls, and independent full-size combat wheel")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check_rects(rects: Array[Rect2], viewport: Vector2) -> void:
	for i in range(rects.size()):
		var rect := rects[i]
		_expect(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= viewport.x + 0.1 and rect.end.y <= viewport.y + 0.1, "Panel left viewport: %s" % rect)
		for j in range(i):
			_expect(not rect.intersects(rects[j]), "Panels overlap: %s / %s" % [rect, rects[j]])


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
