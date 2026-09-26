extends RefCounted

## The shared look for the game's panels (set by the inventory screen, Abe
## 2026-09-26: "update the rest of the UI to these standards"): dark
## blue-black glass, thin blue edges, rounded corners, a cool accent, gold for
## money, red for danger. Everything here only styles; nothing moves.

const BG := Color(0.035, 0.045, 0.06, 0.9)
const PANEL_BG := Color(0.06, 0.075, 0.1, 0.92)
const EDGE := Color(0.22, 0.55, 0.85, 0.75)
const EDGE_SOFT := Color(0.14, 0.2, 0.28, 0.9)
const ACCENT := Color(0.4, 0.82, 1.0)
const TEXT := Color(0.9, 0.94, 1.0)
const DIM := Color(0.55, 0.62, 0.7)
const GOLD := Color(1.0, 0.82, 0.35)
const DANGER := Color(1.0, 0.32, 0.3)
const GOOD := Color(0.35, 0.85, 0.55)
const WARN := Color(1.0, 0.7, 0.25)


static func box(bg: Color, border: Color, width: int = 1, radius: int = 8, pad: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	if pad > 0:
		s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


## The standard floating HUD panel.
static func panel() -> StyleBoxFlat:
	var s := box(BG, EDGE, 1, 10, 10)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s


static func style_panel(control: Control) -> void:
	if control == null:
		return
	control.add_theme_stylebox_override("panel", panel())


static func style_label(label: Label, size: int, colour: Color) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)


## A slim meter: a dark track and a coloured fill, no percentage text.
static func style_bar(bar: ProgressBar, fill: Color, height: int = 8) -> void:
	if bar == null:
		return
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	bar.add_theme_stylebox_override("background", box(Color(0.1, 0.12, 0.16, 0.95), Color(0, 0, 0, 0), 0, 4))
	bar.add_theme_stylebox_override("fill", box(fill, Color(0, 0, 0, 0), 0, 4))


## A HUD button: dark glass, blue edge on hover, bright when pressed.
static func style_button(button: BaseButton, font_size: int = 13, accent: Color = ACCENT) -> void:
	if button == null:
		return
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", box(PANEL_BG, EDGE_SOFT, 1, 6, 6))
	button.add_theme_stylebox_override("hover", box(Color(0.09, 0.13, 0.18, 0.95), accent, 1, 6, 6))
	button.add_theme_stylebox_override("pressed", box(Color(0.08, 0.2, 0.3, 0.95), accent, 1, 6, 6))
	button.add_theme_stylebox_override("disabled", box(Color(0.05, 0.06, 0.08, 0.8), Color(0.12, 0.15, 0.2), 1, 6, 6))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if button is Button:
		(button as Button).add_theme_font_size_override("font_size", font_size)
		(button as Button).add_theme_color_override("font_color", TEXT)
		(button as Button).add_theme_color_override("font_hover_color", Color.WHITE)
		(button as Button).add_theme_color_override("font_pressed_color", Color.WHITE)
		(button as Button).add_theme_color_override("font_disabled_color", Color(0.4, 0.45, 0.5))


## A flat list row (overview): invisible until hovered.
static func style_row(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", box(Color(0.1, 0.16, 0.24, 0.7), Color(0, 0, 0, 0), 0, 4))
	button.add_theme_stylebox_override("pressed", box(Color(0.1, 0.2, 0.3, 0.8), Color(0, 0, 0, 0), 0, 4))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## The selected row: a lit bar with the accent edge.
static func selected_row() -> StyleBoxFlat:
	return box(Color(0.08, 0.22, 0.34, 0.85), ACCENT, 1, 4)


## A flat header button (column titles, small toggles).
static func style_flat(button: Button, colour: Color = DIM, size: int = 12) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", colour)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", ACCENT)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## A thin divider line.
static func rule(colour: Color = Color(0.2, 0.45, 0.7, 0.4), height: int = 1) -> ColorRect:
	var line := ColorRect.new()
	line.color = colour
	line.custom_minimum_size = Vector2(0, height)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
