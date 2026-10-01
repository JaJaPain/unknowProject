extends PanelContainer

## The upgrade goal card (docs/core_loop_plan_2026_10_01.md 3.3): the one
## upgrade the player is working towards, always on screen, with a bar for
## each thing it costs, where to get what's missing, and the Ship Rating it
## brings. Gold when it's all there. With no goal set it shows a suggestion.

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const Goal := preload("res://scripts/domain/UpgradeGoal.gd")

var _tag: Label
var _title: Label
var _rating: Label
var _rows_box: VBoxContainer
var _hint: Label
var _poll := 0.0
var _last_sig := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(300, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_tag = Label.new()
	HudStyle.style_label(_tag, 11, HudStyle.DIM)
	box.add_child(_tag)
	_title = Label.new()
	HudStyle.style_label(_title, 16, HudStyle.TEXT)
	box.add_child(_title)
	_rating = Label.new()
	HudStyle.style_label(_rating, 12, HudStyle.ACCENT)
	box.add_child(_rating)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 3)
	box.add_child(_rows_box)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 280
	HudStyle.style_label(_hint, 12, HudStyle.WARN)
	box.add_child(_hint)
	refresh()


func _process(delta: float) -> void:
	_poll += delta
	if _poll >= 0.5:
		_poll = 0.0
		refresh()


## The goal to show: the player's own if still live, else a suggestion (kept
## in story_state as auto so it stays put until fitted or replaced).
static func current_goal() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var story: Node = tree.root.get_node_or_null("StoryManager") if tree != null else null
	var gs: Node = tree.root.get_node_or_null("GlobalState") if tree != null else null
	if story == null or gs == null:
		return {}
	var goal: Dictionary = story.story_state.get(Goal.GOAL_KEY, {})
	if Goal.is_live(gs, goal):
		return goal
	goal = Goal.suggest(gs)
	story.story_state[Goal.GOAL_KEY] = goal
	return goal


## The player picks a goal on the upgrade screen.
static func set_goal(sys: String, path: String, tier: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var story: Node = tree.root.get_node_or_null("StoryManager") if tree != null else null
	if story != null:
		story.story_state[Goal.GOAL_KEY] = {"sys": sys, "path": path, "tier": tier, "auto": false}


func refresh() -> void:
	var gs := get_node_or_null("/root/GlobalState")
	var goal := current_goal()
	if gs == null or goal.is_empty():
		visible = false
		return
	var rows: Array = Goal.rows(gs, goal)
	var ready: bool = Goal.is_ready(gs, goal)
	var sig := JSON.stringify([goal, rows, ready])
	if sig == _last_sig and visible:
		return
	_last_sig = sig
	visible = true
	_tag.text = ("SUGGESTED GOAL" if bool(goal.get("auto", false)) else "YOUR GOAL") + ("  ·  READY" if ready else "")
	_tag.add_theme_color_override("font_color", HudStyle.GOLD if ready else HudStyle.DIM)
	_title.text = Goal.title(goal)
	var change: Array = Goal.rating_change(gs, goal)
	_rating.text = "Ship Rating %d → %d" % [int(change[0]), int(change[1])] if int(change[1]) > int(change[0]) else "Support system (no rating change)"
	add_theme_stylebox_override("panel", HudStyle.box(HudStyle.PANEL_BG, HudStyle.GOLD if ready else HudStyle.EDGE, 2 if ready else 1, 8, 12))
	for child in _rows_box.get_children():
		child.queue_free()
	var first_short := ""
	for row in rows:
		var have := int(row["have"])
		var need := maxi(1, int(row["need"]))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.text = str(row["label"])
		name_label.custom_minimum_size.x = 96
		HudStyle.style_label(name_label, 12, HudStyle.TEXT)
		line.add_child(name_label)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.value = clampf(float(have) / float(need), 0.0, 1.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var done := have >= int(row["need"]) and str(row["id"]) != "power"
		HudStyle.style_bar(bar, HudStyle.GOOD if done else (HudStyle.DANGER if str(row["id"]) == "power" else HudStyle.ACCENT), 7)
		line.add_child(bar)
		var amount := Label.new()
		amount.text = "%d / %d" % [mini(have, int(row["need"])), int(row["need"])] if str(row["id"]) != "power" else "+%d MW" % int(row["need"])
		amount.custom_minimum_size.x = 76
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		HudStyle.style_label(amount, 12, HudStyle.GOOD if done else HudStyle.TEXT)
		line.add_child(amount)
		_rows_box.add_child(line)
		if not done and first_short.is_empty():
			first_short = str(row["hint"])
	if ready:
		_hint.text = "Ready: dock at a station and fit it."
		_hint.add_theme_color_override("font_color", HudStyle.GOLD)
	else:
		_hint.text = first_short
		_hint.add_theme_color_override("font_color", HudStyle.WARN)
