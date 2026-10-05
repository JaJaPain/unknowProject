extends Panel

## The ship inventory screen (Abe, 2026-09-26: bring it to AAA standard).
## Header with credits, slot meter and banked ore; category tabs; a grid of
## item slots (icon, count badge, category colour, empty sockets up to the
## slot limit); a detail pane for the selected item; and a strip showing the
## hold (the ore mix by type, or the special cargo) and the fuel tank.
##
## UIManager owns opening and closing; this only draws and reports:
## `use_requested(item_id)` and `back_requested()`.

signal use_requested(item_id: String)
signal back_requested()

const StoreRegistryScript := preload("res://scripts/economy/StoreRegistry.gd")
const ConsumableEffectsScript := preload("res://scripts/economy/ConsumableEffects.gd")
const OreTypesScript := preload("res://scripts/economy/OreTypes.gd")
const FuelScript := preload("res://scripts/economy/Fuel.gd")

const SLOT_SIZE := 96
## Cells shown on the All tab: owned, empty, then locked (future slots).
const GRID_CELLS := 28
## The older icon sheets print each item's name under its picture; crop it off
## (art stays text-free on screen).
const LABELLED_SHEETS := ["novelty", "tactical", "cargo"]
## Sheets whose cells carry their own frame (trimmed off).
const FRAMED_SHEETS := ["props_supplies", "props_story"]
const GRID_COLUMNS := 7
## A pickup mission's item rides in the cargo hold (GlobalState.cargo_special),
## not the item inventory, so it never showed in the grid and looked missing
## (Abe, playtest 2026-10-05 finding 8). It gets a card of its own, first on
## the All tab, with an icon from the story-props sheet matched on its name.
const MISSION_CARGO_ID := "__mission_cargo__"
const MISSION_COLOR := Color(1.0, 0.82, 0.35)
const STORY_PROPS_SHEET := "res://assets/PropIconsStory.png"
## Name word -> story-props cell [column, row]; first match wins.
const MISSION_ICONS := [
	["crate", Vector2i(4, 1)], ["weapon", Vector2i(4, 1)],
	["wine", Vector2i(1, 2)], ["manifest", Vector2i(1, 0)],
	["pouch", Vector2i(4, 2)], ["package", Vector2i(4, 2)], ["parcel", Vector2i(4, 2)],
	["sample", Vector2i(2, 4)], ["quarantine", Vector2i(2, 4)], ["flask", Vector2i(0, 4)],
	["core", Vector2i(2, 1)], ["ai ", Vector2i(2, 1)],
	["relay", Vector2i(2, 0)], ["chip", Vector2i(2, 0)], ["transponder", Vector2i(2, 0)], ["drive", Vector2i(2, 0)],
	["log", Vector2i(1, 1)], ["slate", Vector2i(4, 4)], ["data", Vector2i(4, 4)], ["chart", Vector2i(2, 3)],
	["tube", Vector2i(0, 0)], ["evidence", Vector2i(0, 0)], ["art", Vector2i(2, 2)],
	["seal", Vector2i(4, 0)], ["ballot", Vector2i(3, 0)], ["idol", Vector2i(0, 1)],
	["reactor", Vector2i(3, 1)], ["seed", Vector2i(1, 4)], ["bell", Vector2i(3, 3)],
	["music", Vector2i(3, 2)], ["warrant", Vector2i(0, 3)], ["collar", Vector2i(1, 3)],
]
## No word matched: a sealed cargo crate (Abe).
const MISSION_ICON_DEFAULT := Vector2i(4, 1)

const BG := Color(0.035, 0.045, 0.06, 0.97)
const PANEL_BG := Color(0.06, 0.075, 0.1, 0.95)
const EDGE := Color(0.22, 0.55, 0.85, 0.85)
const ACCENT := Color(0.4, 0.82, 1.0)
const TEXT := Color(0.9, 0.94, 1.0)
const DIM := Color(0.55, 0.62, 0.7)
const GOLD := Color(1.0, 0.82, 0.35)
const WARN := Color(1.0, 0.55, 0.35)

const TABS := [
	["all", "All"],
	["consumable", "Consumables"],
	["material", "Materials"],
	["trade", "Trade"],
	["part", "Parts & Ammo"],
]
## Category -> tab, colour and a readable name.
const CATEGORY := {
	"consumable": {"tab": "consumable", "color": Color(0.35, 0.85, 0.55), "name": "Consumable"},
	"tech_material": {"tab": "material", "color": Color(0.75, 0.5, 1.0), "name": "Tech-grade material"},
	"trade_good": {"tab": "trade", "color": Color(1.0, 0.75, 0.3), "name": "Trade good"},
	"novelty": {"tab": "trade", "color": Color(0.95, 0.55, 0.75), "name": "Novelty"},
	"ship_part": {"tab": "part", "color": Color(0.45, 0.7, 1.0), "name": "Ship part"},
	"ammo": {"tab": "part", "color": Color(0.95, 0.4, 0.35), "name": "Ammunition"},
}

var _tab := "all"
var _selected := ""
var _tab_buttons := {}
var _credits_label: Label
var _slots_label: Label
var _slots_bar: ProgressBar
var _ore_bank_label: Label
var _grid: GridContainer
var _detail: VBoxContainer
var _hold_strip: VBoxContainer
var _icon_cache := {}


func _ready() -> void:
	_build()


## Redraws everything from the live game state.
func refresh() -> void:
	if _grid == null:
		_build()
	var gs := _gs()
	if gs == null:
		return
	var inv = gs.inventory
	_credits_label.text = "%s SC" % _thousands(int(gs.player_credits))
	_slots_label.text = "SLOTS  %d / %d" % [inv.slot_count(), inv.max_slots]
	_slots_bar.max_value = maxf(1.0, float(inv.max_slots))
	_slots_bar.value = inv.slot_count()
	_ore_bank_label.text = "Banked ore  %d / %d m³" % [int(gs.player_storage_ore), int(gs.player_storage_max)]
	for id in _tab_buttons:
		(_tab_buttons[id] as Button).button_pressed = id == _tab
	_fill_grid(gs)
	_fill_detail(gs)
	_fill_hold(gs)


## Subclasses (StoreScreen) retitle the same layout.
func _screen_title() -> String:
	return "SHIP INVENTORY"


func set_tab(tab_id: String) -> void:
	_tab = tab_id
	refresh()


# --- layout --------------------------------------------------------------------

func _build() -> void:
	add_theme_stylebox_override("panel", _box(BG, EDGE, 2, 10))
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 22
	root.offset_right = -22
	root.offset_top = 18
	root.offset_bottom = -18
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	# Header: title on the left, credits and the slot meter on the right.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	root.add_child(header)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var title := _label(_screen_title(), 24, ACCENT)
	titles.add_child(title)
	_ore_bank_label = _label("", 13, DIM)
	titles.add_child(_ore_bank_label)
	var money := VBoxContainer.new()
	money.add_theme_constant_override("separation", 2)
	header.add_child(money)
	_credits_label = _label("", 22, GOLD)
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money.add_child(_credits_label)
	_slots_label = _label("", 12, DIM)
	_slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money.add_child(_slots_label)
	_slots_bar = ProgressBar.new()
	_slots_bar.show_percentage = false
	_slots_bar.custom_minimum_size = Vector2(220, 6)
	_slots_bar.add_theme_stylebox_override("background", _box(Color(0.1, 0.12, 0.16), Color(0, 0, 0, 0), 0, 3))
	_slots_bar.add_theme_stylebox_override("fill", _box(ACCENT, Color(0, 0, 0, 0), 0, 3))
	money.add_child(_slots_bar)

	root.add_child(_rule())

	# Category tabs.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root.add_child(tabs)
	var group := ButtonGroup.new()
	for t in TABS:
		var b := Button.new()
		b.text = str(t[1])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(118, 34)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_stylebox_override("normal", _box(PANEL_BG, Color(0.18, 0.24, 0.32), 1, 6, 8))
		b.add_theme_stylebox_override("hover", _box(Color(0.09, 0.12, 0.17), EDGE, 1, 6, 8))
		b.add_theme_stylebox_override("pressed", _box(Color(0.08, 0.2, 0.3), ACCENT, 1, 6, 8))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", DIM)
		b.add_theme_color_override("font_pressed_color", TEXT)
		b.add_theme_color_override("font_hover_color", TEXT)
		var id := str(t[0])
		b.pressed.connect(func() -> void: set_tab(id))
		tabs.add_child(b)
		_tab_buttons[id] = b

	# Body: the grid on the left, the detail pane on the right.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	var grid_frame := PanelContainer.new()
	grid_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_frame.size_flags_stretch_ratio = 1.6
	grid_frame.add_theme_stylebox_override("panel", _box(PANEL_BG, Color(0.14, 0.2, 0.28), 1, 8, 12))
	body.add_child(grid_frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_frame.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)

	var detail_frame := PanelContainer.new()
	detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_frame.add_theme_stylebox_override("panel", _box(PANEL_BG, Color(0.14, 0.2, 0.28), 1, 8, 16))
	body.add_child(detail_frame)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 10)
	detail_frame.add_child(_detail)

	# Hold strip and the way out.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	root.add_child(bottom)
	var hold_frame := PanelContainer.new()
	hold_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hold_frame.add_theme_stylebox_override("panel", _box(PANEL_BG, Color(0.14, 0.2, 0.28), 1, 8, 10))
	bottom.add_child(hold_frame)
	_hold_strip = VBoxContainer.new()
	_hold_strip.add_theme_constant_override("separation", 6)
	hold_frame.add_child(_hold_strip)
	var back := Button.new()
	back.text = "Close"
	back.custom_minimum_size = Vector2(130, 0)
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 15)
	back.add_theme_stylebox_override("normal", _box(Color(0.08, 0.14, 0.2), EDGE, 1, 8))
	back.add_theme_stylebox_override("hover", _box(Color(0.1, 0.22, 0.32), ACCENT, 1, 8))
	back.add_theme_stylebox_override("pressed", _box(Color(0.1, 0.22, 0.32), ACCENT, 1, 8))
	back.pressed.connect(func() -> void: back_requested.emit())
	bottom.add_child(back)


# --- grid ------------------------------------------------------------------------

func _fill_grid(gs: Node) -> void:
	for c in _grid.get_children():
		c.queue_free()
	var items: Dictionary = gs.inventory.get_all()
	var reg = StoreRegistryScript.shared()
	var ids := []
	for id in items.keys():
		if int(items[id]) <= 0:
			continue
		var def = reg.get_item(str(id))
		if _tab != "all" and _tab_of(def) != _tab:
			continue
		ids.append(str(id))
	ids.sort_custom(func(a, b): return _sort_key(reg.get_item(a), a) < _sort_key(reg.get_item(b), b))
	var mission_cargo: bool = _tab == "all" and gs.cargo_type == gs.CargoType.SPECIAL
	if mission_cargo:
		ids.push_front(MISSION_CARGO_ID)
	if not ids.has(_selected):
		_selected = str(ids[0]) if not ids.is_empty() else ""
	for id in ids:
		if id == MISSION_CARGO_ID:
			_grid.add_child(_mission_slot(gs))
		else:
			_grid.add_child(_slot(id, int(items[id]), reg.get_item(id)))
	if mission_cargo:
		ids.erase(MISSION_CARGO_ID)  # not an inventory slot: the hold carries it
	# The All tab shows every slot: empty ones up to the limit, then locked
	# ones (more slots come with ship upgrades). Other tabs pad out the row.
	if _tab == "all":
		var free := maxi(0, int(gs.inventory.max_slots) - ids.size())
		for i in free:
			_grid.add_child(_empty_socket(false))
		for i in maxi(0, GRID_CELLS - ids.size() - free):
			_grid.add_child(_empty_socket(true))
	else:
		var pad := GRID_COLUMNS - ids.size() % GRID_COLUMNS if ids.size() % GRID_COLUMNS != 0 or ids.is_empty() else 0
		for i in pad:
			_grid.add_child(_empty_socket(false))


func _slot(item_id: String, quantity: int, def) -> Control:
	var colour := _category_color(def)
	var selected := item_id == _selected
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.focus_mode = Control.FOCUS_NONE
	slot.tooltip_text = def.display_name if def != null else item_id.capitalize()
	var base := Color(0.07, 0.09, 0.12)
	slot.add_theme_stylebox_override("normal", _box(base, colour.darkened(0.35) if not selected else colour, 2 if not selected else 3, 8))
	slot.add_theme_stylebox_override("hover", _box(base.lightened(0.06), colour, 2, 8))
	slot.add_theme_stylebox_override("pressed", _box(base.lightened(0.06), colour, 3, 8))
	slot.pressed.connect(func() -> void:
		_selected = item_id
		refresh())
	var icon := TextureRect.new()
	icon.texture = _icon(def)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 8
	icon.offset_top = 8
	icon.offset_right = -8
	icon.offset_bottom = -8
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)
	if icon.texture == null:
		var initials := _label(_initials(def, item_id), 22, colour)
		initials.set_anchors_preset(Control.PRESET_FULL_RECT)
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initials.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(initials)
	# Category stripe along the bottom.
	var stripe := ColorRect.new()
	stripe.color = colour
	stripe.anchor_left = 0.0
	stripe.anchor_right = 1.0
	stripe.anchor_top = 1.0
	stripe.anchor_bottom = 1.0
	stripe.offset_left = 10
	stripe.offset_right = -10
	stripe.offset_top = -5
	stripe.offset_bottom = -3
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(stripe)
	if quantity > 1:
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", _box(Color(0.02, 0.03, 0.05, 0.9), colour.darkened(0.2), 1, 6, 3))
		badge.anchor_left = 1.0
		badge.anchor_right = 1.0
		badge.anchor_top = 0.0
		badge.anchor_bottom = 0.0
		badge.offset_left = -34
		badge.offset_right = -4
		badge.offset_top = 4
		badge.offset_bottom = 24
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var count := _label("x%d" % quantity, 12, TEXT)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_child(count)
		slot.add_child(badge)
	if item_id in FuelScript.NO_JUMP_ITEMS:
		var warn := _label("!", 14, WARN)
		warn.position = Vector2(8, 4)
		warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(warn)
	return slot


func _mission_slot(gs: Node) -> Control:
	var selected := _selected == MISSION_CARGO_ID
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.focus_mode = Control.FOCUS_NONE
	slot.tooltip_text = "%s (mission cargo)" % str(gs.cargo_special.get("name", "Mission cargo"))
	var base := Color(0.1, 0.085, 0.05)
	slot.add_theme_stylebox_override("normal", _box(base, MISSION_COLOR.darkened(0.25) if not selected else MISSION_COLOR, 2 if not selected else 3, 8))
	slot.add_theme_stylebox_override("hover", _box(base.lightened(0.06), MISSION_COLOR, 2, 8))
	slot.add_theme_stylebox_override("pressed", _box(base.lightened(0.06), MISSION_COLOR, 3, 8))
	slot.pressed.connect(func() -> void:
		_selected = MISSION_CARGO_ID
		refresh())
	var icon := TextureRect.new()
	icon.texture = _mission_icon(str(gs.cargo_special.get("name", "")))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 8
	icon.offset_top = 8
	icon.offset_right = -8
	icon.offset_bottom = -8
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)
	var tag := _label("MISSION", 10, MISSION_COLOR)
	tag.position = Vector2(8, 4)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(tag)
	return slot


func _mission_icon(item_name: String) -> Texture2D:
	var lower := item_name.to_lower() + " "
	var cell := MISSION_ICON_DEFAULT
	for pair in MISSION_ICONS:
		if lower.contains(str(pair[0])):
			cell = pair[1]
			break
	var key := "mission|%d|%d" % [cell.x, cell.y]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var sheet := load(STORY_PROPS_SHEET) as Texture2D
	var tex: Texture2D = null
	if sheet != null:
		var w := sheet.get_width() / 5.0
		var h := sheet.get_height() / 5.0
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(cell.x * w, cell.y * h, w, h).grow(-w * 0.07)
		tex = atlas
	_icon_cache[key] = tex
	return tex


func _fill_mission_detail(gs: Node) -> void:
	var special: Dictionary = gs.cargo_special
	var art := PanelContainer.new()
	art.custom_minimum_size = Vector2(0, 230)
	art.add_theme_stylebox_override("panel", _box(Color(0.06, 0.05, 0.03), MISSION_COLOR.darkened(0.3), 1, 10, 10))
	var big := TextureRect.new()
	big.texture = _mission_icon(str(special.get("name", "")))
	big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big.custom_minimum_size = Vector2(0, 206)
	art.add_child(big)
	_detail.add_child(art)
	var name_label := _label(str(special.get("name", "Mission cargo")), 20, TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(name_label)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.add_child(_chip("Mission cargo", MISSION_COLOR))
	chips.add_child(_chip("In the hold", DIM))
	_detail.add_child(chips)
	var desc_text := str(special.get("description", "")).strip_edges()
	if not desc_text.is_empty():
		var desc := _label(desc_text, 13, Color(0.74, 0.8, 0.87))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(desc)
	var note := _label("Can't be sold or dropped. Hand it over to finish the job.", 12, DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(note)


func _empty_socket(locked: bool) -> Control:
	var socket := Panel.new()
	socket.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	if locked:
		socket.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.045, 0.8), Color(0.08, 0.1, 0.13), 1, 8))
		socket.tooltip_text = "More slots come with ship upgrades."
		# A small padlock, drawn: body and shackle.
		var body := ColorRect.new()
		body.color = Color(0.16, 0.2, 0.26)
		body.size = Vector2(16, 12)
		body.position = Vector2(SLOT_SIZE / 2.0 - 8, SLOT_SIZE / 2.0 - 2)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		socket.add_child(body)
		var shackle := Panel.new()
		shackle.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0), Color(0.16, 0.2, 0.26), 2, 6))
		shackle.size = Vector2(12, 12)
		shackle.position = Vector2(SLOT_SIZE / 2.0 - 6, SLOT_SIZE / 2.0 - 11)
		shackle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		socket.add_child(shackle)
	else:
		socket.add_theme_stylebox_override("panel", _box(Color(0.05, 0.065, 0.09, 0.85), Color(0.13, 0.18, 0.25), 1, 8))
	return socket


# --- detail ----------------------------------------------------------------------

func _fill_detail(gs: Node) -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _selected == MISSION_CARGO_ID and gs.cargo_type == gs.CargoType.SPECIAL:
		_fill_mission_detail(gs)
		return
	if _selected.is_empty() or _selected == MISSION_CARGO_ID:
		var none := _label("No items here yet.\nBuy them at a station store, or find them in wrecks.", 14, DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(none)
		return
	var reg = StoreRegistryScript.shared()
	var def = reg.get_item(_selected)
	var quantity: int = int(gs.inventory.get_quantity(_selected))
	var colour := _category_color(def)
	var art := PanelContainer.new()
	art.custom_minimum_size = Vector2(0, 230)
	art.add_theme_stylebox_override("panel", _box(Color(0.03, 0.04, 0.06), colour.darkened(0.3), 1, 10, 10))
	var big := TextureRect.new()
	big.texture = _icon(def)
	big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big.custom_minimum_size = Vector2(0, 206)
	art.add_child(big)
	_detail.add_child(art)
	var name_label := _label(def.display_name if def != null else _selected.capitalize(), 20, TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(name_label)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.add_child(_chip(_category_name(def), colour))
	var stack_max: int = def.stack_max if def != null else 0
	chips.add_child(_chip("x%d%s" % [quantity, "/%d" % stack_max if stack_max > 1 else ""], DIM))
	if def != null and def.base_price > 0:
		chips.add_child(_chip("%s SC" % _thousands(def.base_price), GOLD))
	_detail.add_child(chips)
	if def != null and not def.description.strip_edges().is_empty():
		var desc := _label(def.description, 13, Color(0.74, 0.8, 0.87))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(desc)
	if _selected in FuelScript.NO_JUMP_ITEMS:
		var warn := _label("Cannot pass a jump gate. Use or sell it in this system.", 13, WARN)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(warn)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(spacer)
	if ConsumableEffectsScript.can_use(_selected):
		var use := Button.new()
		use.text = "USE"
		use.custom_minimum_size = Vector2(0, 40)
		use.focus_mode = Control.FOCUS_NONE
		use.add_theme_font_size_override("font_size", 16)
		use.add_theme_stylebox_override("normal", _box(Color(0.1, 0.3, 0.2), Color(0.35, 0.85, 0.55), 1, 8))
		use.add_theme_stylebox_override("hover", _box(Color(0.14, 0.4, 0.26), Color(0.5, 1.0, 0.7), 1, 8))
		use.add_theme_stylebox_override("pressed", _box(Color(0.14, 0.4, 0.26), Color(0.5, 1.0, 0.7), 1, 8))
		use.add_theme_stylebox_override("disabled", _box(Color(0.08, 0.1, 0.12), Color(0.2, 0.25, 0.3), 1, 8))
		use.disabled = not ConsumableEffectsScript.is_usable_now(_selected, gs.player, gs.inventory, gs.shield_capacity)
		var id := _selected
		use.pressed.connect(func() -> void: use_requested.emit(id))
		_detail.add_child(use)
		if use.disabled:
			var why := _label("Can't be used right now.", 12, DIM)
			why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_detail.add_child(why)


# --- hold strip ------------------------------------------------------------------

func _fill_hold(gs: Node) -> void:
	for c in _hold_strip.get_children():
		c.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_hold_strip.add_child(row)
	row.add_child(_label("CARGO HOLD", 12, DIM))
	var summary := _label("", 13, TEXT)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(summary)
	var fuel_icon := _ore_icon("fuel", 22)
	if fuel_icon != null:
		row.add_child(fuel_icon)
	var fuel_text := _label("FUEL  %d / %d" % [int(gs.fuel), int(FuelScript.TANK_MAX)], 13, ACCENT if not gs.is_fuel_empty() else WARN)
	row.add_child(fuel_text)
	if gs.cargo_type == gs.CargoType.SPECIAL:
		summary.text = "%s  (%s → %s)" % [str(gs.cargo_special.get("name", "Special cargo")), str(gs.cargo_special.get("source", "?")), str(gs.cargo_special.get("destination", "?"))]
		return
	var mix: Dictionary = gs.cargo_ore_mix()
	if mix.is_empty():
		summary.text = "Empty, %d m³ free" % int(gs.cargo_max)
		summary.add_theme_color_override("font_color", DIM)
	else:
		summary.text = "%d / %d m³ of ore" % [int(gs.cargo), int(gs.cargo_max)]
	# The hold as a bar, each ore in its own colour.
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_constant_override("separation", 1)
	_hold_strip.add_child(bar)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	var ids := mix.keys()
	ids.sort_custom(func(a, b): return float(mix[a]) > float(mix[b]))
	for id in ids:
		var seg := ColorRect.new()
		var c := _ore_color(str(id))
		seg.color = c
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = maxf(0.01, float(mix[id]))
		bar.add_child(seg)
		var entry := HBoxContainer.new()
		entry.add_theme_constant_override("separation", 5)
		var icon := _ore_icon(str(id), 26)
		entry.add_child(icon if icon != null else _label("■", 12, c))
		entry.add_child(_label("%s %d" % [OreTypesScript.display(str(id)), int(round(float(mix[id])))], 12, c))
		legend.add_child(entry)
	var free: float = maxf(0.0, float(gs.cargo_max) - float(gs.cargo))
	if free > 0.0:
		var empty := ColorRect.new()
		empty.color = Color(0.1, 0.12, 0.16)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.size_flags_stretch_ratio = free
		bar.add_child(empty)
	if not ids.is_empty():
		_hold_strip.add_child(legend)


# --- helpers ---------------------------------------------------------------------

func _gs() -> Node:
	return get_tree().root.get_node_or_null("GlobalState") if is_inside_tree() else null


func _tab_of(def) -> String:
	if def == null:
		return "trade"
	return str((CATEGORY.get(def.category, {}) as Dictionary).get("tab", "trade"))


func _category_color(def) -> Color:
	if def == null:
		return DIM
	return (CATEGORY.get(def.category, {}) as Dictionary).get("color", DIM)


func _category_name(def) -> String:
	if def == null:
		return "Item"
	return str((CATEGORY.get(def.category, {}) as Dictionary).get("name", def.category.capitalize()))


func _sort_key(def, id: String) -> String:
	var order := ["consumable", "ammo", "ship_part", "tech_material", "trade_good", "novelty"]
	var cat: String = def.category if def != null else "zz"
	var rank := order.find(cat)
	return "%02d|%s" % [rank if rank >= 0 else 99, (def.display_name if def != null else id)]


func _ore_icon(ore_id: String, px: int) -> TextureRect:
	var tex := OreTypesScript.icon(ore_id)
	if tex == null:
		return null
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size = Vector2(px, px)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _ore_color(ore_id: String) -> Color:
	# Silicate's tint is white; show it as rock grey.
	if ore_id == "silicate":
		return Color(0.55, 0.57, 0.6)
	return OreTypesScript.tint(ore_id)


func _icon(def) -> Texture2D:
	if def == null or def.icon_sheet.is_empty():
		return null
	var key := "%s|%d|%d" % [def.icon_sheet, def.icon_cell.x, def.icon_cell.y]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var path: String = StoreRegistryScript.shared().get_icon_sheet_path(def.icon_sheet)
	var sheet: Texture2D = load(path) as Texture2D if not path.is_empty() else null
	var tex: Texture2D = null
	if sheet != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		var w := sheet.get_width() / 5.0
		var h := sheet.get_height() / 5.0
		var cell := Rect2(def.icon_cell.x * w, def.icon_cell.y * h, w, h)
		if def.icon_sheet in LABELLED_SHEETS:
			cell = Rect2(cell.position.x + w * 0.12, cell.position.y + h * 0.05, w * 0.76, h * 0.72)
		elif def.icon_sheet in FRAMED_SHEETS:
			# These draw their own frame around each item; the slot has one.
			cell = cell.grow(-w * 0.07)
		atlas.region = cell
		tex = atlas
	_icon_cache[key] = tex
	return tex


func _initials(def, id: String) -> String:
	var name: String = def.display_name if def != null else id.capitalize()
	var out := ""
	for word in name.split(" ", false):
		out += word.substr(0, 1).to_upper()
		if out.length() >= 2:
			break
	return out


func _chip(text: String, colour: Color) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _box(Color(colour.r, colour.g, colour.b, 0.12), Color(colour.r, colour.g, colour.b, 0.6), 1, 10, 4))
	var label := _label(text, 12, colour.lightened(0.2))
	chip.add_child(label)
	return chip


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _rule() -> Control:
	var line := ColorRect.new()
	line.color = Color(0.2, 0.45, 0.7, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	return line


func _box(bg: Color, border: Color, width: int, radius: int, pad: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	if pad > 0:
		s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
