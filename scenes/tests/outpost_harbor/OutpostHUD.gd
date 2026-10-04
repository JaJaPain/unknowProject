extends Control

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
var status: Label
var details: Label
var dock_button: Button
var undock_button: Button
var select_buttons: Array[Button] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = HudStyle.make_theme()
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(440, 0)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "OUTPOST HARBOR / TEST SCENE"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	var note := Label.new()
	note.text = "Generated system • isolated docking sandbox"
	column.add_child(note)
	for index in 2:
		var button := Button.new()
		button.text = ["1 · Kestrel Depot", "2 · Crown Haven"][index]
		button.pressed.connect(func() -> void: get_tree().current_scene.stage_player(index))
		column.add_child(button)
		select_buttons.append(button)
	dock_button = Button.new()
	dock_button.text = "Dock player ship [D]"
	dock_button.pressed.connect(func() -> void: get_tree().current_scene.request_dock())
	column.add_child(dock_button)
	undock_button = Button.new()
	undock_button.text = "Release clamps / undock [U]"
	undock_button.pressed.connect(func() -> void: get_tree().current_scene.undock_player())
	column.add_child(undock_button)
	var view := Button.new()
	view.text = "Station overview / ship camera [V]"
	view.pressed.connect(func() -> void: get_tree().current_scene.toggle_view())
	column.add_child(view)
	var paint := Button.new()
	paint.text = "Cycle paint sets [P]"
	paint.pressed.connect(func() -> void: get_tree().current_scene.cycle_finish())
	column.add_child(paint)
	status = Label.new()
	status.text = "Preparing harbor…"
	column.add_child(status)
	details = Label.new()
	column.add_child(details)
	var help := Label.new()
	help.text = "1 / 2: stage at a station's approach lane\nD: approach + tractor capture   U: depart\nV: overview camera   RMB drag: orbit ship\nP: cycle finishes   Wheel: zoom   Esc: exit test"
	help.add_theme_font_size_override("font_size", 16)
	column.add_child(help)

func show_hud_warning(message: String) -> void:
	status.text = message

func _process(_delta: float) -> void:
	var harbor := get_tree().current_scene
	if harbor == null or harbor.stations.is_empty():
		return
	var ship = harbor.player
	dock_button.disabled = harbor.busy or ship.is_docked
	undock_button.disabled = harbor.busy or not ship.is_docked
	for button in select_buttons:
		button.disabled = harbor.busy or ship.is_docked
	var station = harbor.stations[harbor.selected]
	var alongside := 0
	for visitor in station.reservations.values():
		if visitor != harbor.player and bool(visitor.get_meta("harbor_docked", false)):
			alongside += 1
	details.text = "%s\n4 berths • %d friendly ships alongside\nTotal traffic dockings: %d" % [station.display_name, alongside, harbor.traffic_dock_count]
