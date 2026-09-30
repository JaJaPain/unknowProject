extends "res://scripts/ui/InventoryScreen.gd"

## The station store on the inventory screen's layout (Abe: bring the docked
## screens up to the inventory's standard): the same grid, detail pane, header
## and hold strip, so buying and owning look alike. UIManager fills `rows`
## (price, stock, what the captain owns, the sell offer) and handles the trades.

signal buy_requested(item_id: String)
signal sell_requested(item_id: String)

## [{item_id, price, stock, owned, can_sell, sell_price}]
var rows: Array = []


func _screen_title() -> String:
	return "STATION STORE"


func _row(item_id: String) -> Dictionary:
	for r in rows:
		if str(r.get("item_id", "")) == item_id:
			return r
	return {}


func _fill_grid(_gs: Node) -> void:
	for c in _grid.get_children():
		c.queue_free()
	var reg = StoreRegistryScript.shared()
	var ids := []
	for r in rows:
		var id := str(r.get("item_id", ""))
		if _tab != "all" and _tab_of(reg.get_item(id)) != _tab:
			continue
		ids.append(id)
	if not ids.has(_selected):
		_selected = str(ids[0]) if not ids.is_empty() else ""
	for id in ids:
		_grid.add_child(_slot(id, int(_row(id).get("stock", 0)), reg.get_item(id)))
	var pad := GRID_COLUMNS - ids.size() % GRID_COLUMNS if ids.size() % GRID_COLUMNS != 0 or ids.is_empty() else 0
	for i in pad:
		_grid.add_child(_empty_socket(false))


func _fill_detail(gs: Node) -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _selected.is_empty():
		var none := _label("Nothing on the shelves here.", 14, DIM)
		_detail.add_child(none)
		return
	var reg = StoreRegistryScript.shared()
	var def = reg.get_item(_selected)
	var row := _row(_selected)
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
	var stock := int(row.get("stock", 0))
	var owned := int(row.get("owned", 0))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.add_child(_chip(_category_name(def), colour))
	chips.add_child(_chip("In stock %d" % stock if stock > 0 else "Sold out", DIM if stock > 0 else WARN))
	if owned > 0:
		chips.add_child(_chip("You have %d" % owned, ACCENT))
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
	var id := _selected
	var price := int(row.get("price", 0))
	var credits := int(gs.player_credits) if gs != null else 0
	var tech := def != null and str(def.category) == "tech_material"
	if not tech:
		var buy := _trade_button("BUY   %s SC" % _thousands(price), Color(0.1, 0.24, 0.34), ACCENT)
		buy.disabled = stock <= 0 or price > credits
		buy.pressed.connect(func() -> void: buy_requested.emit(id))
		_detail.add_child(buy)
		if price > credits and stock > 0:
			var short := _label("Not enough credits.", 12, DIM)
			short.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_detail.add_child(short)
	if bool(row.get("can_sell", false)):
		var sell := _trade_button("SELL   %s SC" % _thousands(int(row.get("sell_price", 0))), Color(0.26, 0.2, 0.08), GOLD)
		sell.pressed.connect(func() -> void: sell_requested.emit(id))
		_detail.add_child(sell)


func _trade_button(text: String, bg: Color, edge: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("normal", _box(bg, edge.darkened(0.2), 1, 8))
	b.add_theme_stylebox_override("hover", _box(bg.lightened(0.08), edge, 1, 8))
	b.add_theme_stylebox_override("pressed", _box(bg.lightened(0.08), edge, 1, 8))
	b.add_theme_stylebox_override("disabled", _box(Color(0.08, 0.1, 0.12), Color(0.2, 0.25, 0.3), 1, 8))
	return b
