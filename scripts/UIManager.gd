extends Control

const PublicBoardOfferBuilderType := preload(
	"res://scripts/domain/PublicBoardOfferBuilder.gd"
)
const PublicBoardTextGeneratorType := preload(
	"res://scripts/domain/PublicBoardTextGenerator.gd"
)

# UI Nodes created dynamically
var hud_panel: Panel
var time_label: Label
var credits_label: Label
var cargo_label: Label
var cargo_bar: ProgressBar

var target_panel: PanelContainer
var target_label: Label
var target_icon: TextureRect
var target_action_box: HBoxContainer
var target_boost_btn: Button
var target_approach_btn: Button
var target_orbit_btn: Button
var target_action_btn: Button
var icons_sheet = preload("res://assets/icons.png")

var overview_panel: Panel
var overview_list: VBoxContainer
var overview_collapsed: bool = false
var collapse_btn: Button
var overview_title_label: Label
var map_btn: Button
var inventory_hud_btn: Button
var branch_map: BranchMapUI

var dock_panel: Panel
var dock_label: Label
# Background image for the dock panel — shown only when docked at a
# repair_shop station, set to RepairShop.png for thematic flavor.
var dock_background: TextureRect
# Docked-message slot. Lives inside dock_panel between the title and
# the button list. Used to surface flavor lines ("Hear Gossip") and
# quest pickup responses (success/failure) in-context, so the player
# doesn't have to look at the screen edges to see what just happened.
# Hidden when no message is active. Replaces the screen-anchored
# show_npc_dialogue_popup for the dock flow and routes the
# outpost-side pickup messages off the corner show_hud_warning.
var dock_message_slot: PanelContainer
var dock_message_hbox: HBoxContainer
var dock_message_portrait: TextureRect
var dock_message_name: Label
var dock_message_line: Label
var dock_message_tween: Tween
var station_contacts_panel: PanelContainer
var station_contacts_list: VBoxContainer
# ── Mechanic (Jenna Kross) dock intro ───────────────────────────────────────
# Portrait + personalized greeting that pops in the top area of the dock panel
# when the player enters the Grease Monkeys maintenance submenu. Layout:
# portrait on the left, name + greeting chat box on the right. Cached on
# dock so first entry is instant. LLM-driven when available, otherwise picks
# one of 10 canned lines that reference the player's ship and reputation.
# See _cache_mechanic_intro() and _render_mechanic_intro().
var mechanic_intro_panel: PanelContainer
var mechanic_intro_hbox: HBoxContainer
var mechanic_portrait: TextureRect
var mechanic_name_label: Label
var mechanic_line_label: Label
# Cached greeting (string) + its TTS cache state. The cached line sticks
# across undock/redock at the same station (so re-entering maintenance
# shows the same line unless the player clicks "Speak" or rep changes
# meaningfully). Cleared on a fresh dock so the next arrival regenerates.
var _cached_mechanic_line: String = ""
var _cached_mechanic_line_is_fallback: bool = false
var _mechanic_precache_in_flight: bool = false
# Monotonic request id. Bumped every time we fire a new LLM call so
# stale callbacks don't overwrite the latest cache. Stale callbacks
# bail at the top of the lambda.
var _mechanic_request_id: int = 0
# Last line we actually played via TTS. Used to avoid re-playing the
# same line when the player toggles between Services and Maintenance
# submenus (which both call _render_mechanic_intro).
var _last_played_mechanic_line: String = ""

# Mechanic pickup-offer state.
var _mechanic_pickup_offer: Dictionary = {}
var _mechanic_pickup_declined: bool = false
var mechanic_pickup_accept_btn: Button
var mechanic_pickup_decline_btn: Button

# Ore-trade confirm dialog
var ore_trade_popup: PanelContainer
var ore_trade_label: Label
var ore_trade_accept_btn: Button
var ore_trade_decline_btn: Button
var ask_for_part_btn: Button
var deliver_part_btn: Button
const DEBUG_TESTS: bool = false

var sell_btn: Button
var repair_btn: Button
var agent_service_btn: Button
var maintenance_bay_btn: Button
var ship_upgrades_btn: Button
var ship_upgrades_panel: Panel
var su_weapons_btn: Button
var su_cargo_btn: Button
var su_engine_btn: Button
var su_power_btn: Button
var su_shields_btn: Button
var su_mining_btn: Button
var su_ship_sys_vbox: VBoxContainer
var su_ship_sys_lbl: RichTextLabel
var su_ore_bank_lbl: Label
var back_to_services_btn: Button
var test_pickup_btn: Button
var test_deliver_btn: Button
var test_pickup_part_btn: Button
var hear_gossip_btn: Button
var public_board_btn: Button

# Dock submenu state. Every dockable station (main station, outposts)
# shows the same two submenus:
#   "services"     — sell ore, talk to agent, maintenance bay entry
#   "maintenance"  — repair, upgrade cargo, upgrade laser, back to services
# Default is "services" so a fresh dock lands on the station's primary
# offerings. The Grease Monkeys hangar image is shown only in "maintenance".
enum DockSubmenu { SERVICES, MAINTENANCE }
var current_submenu: DockSubmenu = DockSubmenu.SERVICES

var agent_panel: Panel
var agent_name_label: Label
var agent_subtitle_label: Label
var agent_dialogue_label: Label
var agent_choices_container: VBoxContainer
var agent_back_btn: Button

var public_board_panel: Panel
var public_board_list: VBoxContainer
var public_board_back_btn: Button
var public_board_current_offers: Array[Dictionary] = []

var store_panel: Panel
var store_list: VBoxContainer
var store_credits_label: Label
var store_back_btn: Button
var store_btn: Button
var _store_current_id: String = ""
var inventory_panel: Panel
var inventory_list: VBoxContainer
var inventory_summary_label: Label
var inventory_btn: Button
var inventory_return_to_dock: bool = false
var inventory_back_btn: Button

var quest_tracker_panel: PanelContainer
var quest_tracker_title: Label
var quest_tracker_progress: Label
var quest_tracker_logo: TextureRect
var quest_tracker_turn_in_btn: Button
var quest_tracker_secondary_container: VBoxContainer
var quest_tracker_nav_container: HBoxContainer
var quest_tracker_prev_btn: Button
var quest_tracker_next_btn: Button
var quest_tracker_nav_label: Label

# Incoming Comms (reversal hail)
var comms_hail_panel: PanelContainer
var comms_hail_portrait: TextureRect
var comms_hail_message: Label
var comms_hail_choices_container: VBoxContainer

# Systems Comms Chat Window
var chat_window_panel: Panel
var chat_scroll: ScrollContainer
var chat_vbox: VBoxContainer
var max_chat_messages: int = 50
var agent_click_time: float = 0.0

# Preloaded assets
var quest_givers_sheet = preload("res://assets/QuestGivers.png")
var faction_branding_sheet = preload("res://assets/factionBranding.png")
const StoreRegistryScript = preload("res://scripts/economy/StoreRegistry.gd")
const ConsumableEffectsScript = preload("res://scripts/economy/ConsumableEffects.gd")

# Sliced elements inside Agent Panel
var agent_portrait_column: VBoxContainer
var agent_portrait: TextureRect
var agent_client_logo: TextureRect

var pause_panel: Panel
var pause_new_campaign_button: Button
var campaign_panel: Panel
var campaign_slots_vbox: VBoxContainer
var campaign_manual_vbox: VBoxContainer
var campaign_status_label: Label
var campaign_import_button: Button
var campaign_confirm_dialog: ConfirmationDialog
var campaign_load_fade: ColorRect
var campaign_load_in_progress: bool = false
var pending_delete_slot_id: String = ""
var pending_manual_slot_index: int = -1
var pending_manual_name: String = ""
var death_panel: Panel
var context_panel: Panel
var context_action_btn: Button
var context_highlight_target: Node3D = null

var current_station: Node3D = null

var cached_quest_data: Dictionary = {}
var cached_quest_is_fallback: bool = false
var is_waiting_for_agent_board: bool = false

# Per-outpost count of TTS flavor lines we have already pre-cached
# for the player's current session. Used as a quick diagnostic in
# [TRACE] logs and to gate refresh-on-use (no point re-warming lines
# that are already in the cache). Resets implicitly on scene reload.
var _outpost_flavor_precached: Dictionary = {}

# LLM-generated Kaelen handoff line for the currently-cached quest.
# Empty string means "not yet fetched" or "fetch failed — fall back to canned 5".
var cached_unique_intro: String = ""

# Dynamic Kaelen reaction lines — unique per quest, generated on acceptance
var cached_completion_line: String = ""
var cached_abandon_line: String = ""

var loading_panel: Panel
var loading_bar: ProgressBar
var loading_status_label: Label

var is_llm_ready: bool = false
var is_tts_ready: bool = false
var last_llm_attempt: int = 0
var last_tts_attempt: int = 0
var startup_save_loaded: bool = false

# Sorting parameters
var sort_column: String = "distance"
var sort_ascending: bool = true
var btn_name: Button
var btn_dist: Button
var btn_type: Button

# Resize parameters
var is_resizing: bool = false
const RESIZE_BORDER_WIDTH := 6.0
var resize_handle: Control
var drag_start_mouse_x: float = 0.0
var drag_start_anchor_left: float = 0.0
var sort_timer: float = 0.0
const SORT_INTERVAL := 0.2

var target_marker: Control
var marker_active: bool = false
var marker_timer: float = 0.0
var marker_pos_3d: Vector3 = Vector3.ZERO
var selection_marker: Control
var selected_row_style: StyleBoxFlat

func _ready():
	# Configure selected row highlight stylebox
	selected_row_style = StyleBoxFlat.new()
	selected_row_style.bg_color = Color(0.0, 0.35, 0.55, 0.45) # Glowing semi-transparent cyan background
	selected_row_style.border_width_left = 2
	selected_row_style.border_width_top = 2
	selected_row_style.border_width_right = 2
	selected_row_style.border_width_bottom = 2
	selected_row_style.border_color = Color(0.0, 0.85, 1.0, 1.0) # Bright neon cyan border
	selected_row_style.corner_radius_top_left = 4
	selected_row_style.corner_radius_top_right = 4
	selected_row_style.corner_radius_bottom_right = 4
	selected_row_style.corner_radius_bottom_left = 4

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Configure layout
	anchors_preset = Control.PRESET_FULL_RECT
	
	# Connect GlobalState signals
	GlobalState.credits_changed.connect(_on_credits_changed)
	GlobalState.cargo_changed.connect(_on_cargo_changed)
	GlobalState.target_changed.connect(_on_target_changed)
	GlobalState.game_paused.connect(_on_pause_changed)
	GlobalState.entities_changed.connect(refresh_overview)
	CampaignClock.time_changed.connect(_on_campaign_time_changed)
	
	# Connect QuestManager signals
	QuestManager.quest_accepted.connect(_on_quest_accepted)
	QuestManager.quest_progress_updated.connect(_on_quest_progress_updated)
	QuestManager.quest_completed.connect(_on_quest_completed)
	QuestManager.quest_abandoned.connect(_on_quest_abandoned)
	QuestManager.quest_expired.connect(_on_quest_expired)
	QuestManager.comms_reversal_triggered.connect(_on_comms_reversal_triggered)
	
	_create_hud()
	_create_target_panel()
	_create_overview()
	_create_dock_menu()
	_create_ship_upgrades_panel()
	_create_context_menu()
	_create_death_screen()
	_create_pause_menu()
	_create_campaign_load_fade()
	
	# Create target indicator marker
	target_marker = Control.new()
	target_marker.name = "TargetMarker"
	add_child(target_marker)
	target_marker.draw.connect(_on_target_marker_draw)
	target_marker.visible = false
	
	# Create selection indicator marker
	selection_marker = Control.new()
	selection_marker.name = "SelectionMarker"
	add_child(selection_marker)
	selection_marker.draw.connect(_on_selection_marker_draw)
	selection_marker.visible = false
	
	# Initial UI state
	_on_credits_changed(GlobalState.player_credits)
	_on_cargo_changed(GlobalState.cargo)
	_on_campaign_time_changed(CampaignClock.total_minutes)
	_on_target_changed(GlobalState.active_target)
	
	# Initialize startup loading screen to pre-cache the first quest & TTS
	_create_loading_screen()
	GlobalState.paused = true
	if "--baseline-offline" in OS.get_cmdline_user_args():
		call_deferred("_complete_offline_loading_for_tests")
	
	LLMInterface.llm_connection_attempt.connect(_on_llm_connection_attempt)
	LLMInterface.llm_connection_established.connect(_on_llm_connected)
	SpeechService.speech_connection_attempt.connect(_on_tts_connection_attempt)
	SpeechService.speech_connection_established.connect(_on_tts_connected)

	# Autoloads survive reload_current_scene(). On restart the services may
	# already be connected, so their one-time connection signals will not fire
	# again for this new UIManager. Adopt the current state immediately instead
	# of leaving the loading screen stuck at its initial 5%.
	is_llm_ready = LLMInterface.llm_connected
	is_tts_ready = SpeechService.speech_connected
	last_llm_attempt = LLMInterface.connection_attempts
	last_tts_attempt = SpeechService.connection_attempts
	_update_connection_status_display()
	call_deferred("_check_both_services_ready")
	var game_root := get_tree().current_scene
	if game_root and game_root.has_signal("startup_load_completed"):
		game_root.startup_load_completed.connect(_on_startup_load_completed)
		if bool(game_root.get("startup_load_finished")):
			_on_startup_load_completed(bool(game_root.get("startup_save_loaded")))

func _complete_offline_loading_for_tests() -> void:
	if loading_panel and is_instance_valid(loading_panel):
		loading_panel.queue_free()
	GlobalState.paused = false

func _on_startup_load_completed(save_loaded: bool) -> void:
	startup_save_loaded = save_loaded
	if save_loaded:
		refresh_restored_state()
	if Engine.has_meta("open_campaign_manager_after_death"):
		Engine.remove_meta("open_campaign_manager_after_death")
		call_deferred("_open_campaign_manager")

func refresh_restored_state() -> void:
	_on_credits_changed(GlobalState.player_credits)
	_on_cargo_changed(GlobalState.cargo)
	_update_quest_tracker()
	refresh_overview()

func _process(delta):
	if GlobalState.paused: return
	
	# Update overview list item distances
	_update_overview_distances(delta)
	
	# Update target indicator marker
	if marker_active:
		marker_timer -= delta
		if marker_timer <= 0.0:
			marker_active = false
			target_marker.visible = false
		else:
			_update_target_marker_position()
			
	# Update HUD player health and reputations
	_update_hud_health()
	_update_hud_reputations()
			
	# Update selection marker position
	_update_selection_marker_position()
	_update_target_command_feedback()

func _create_hud():
	hud_panel = Panel.new()
	hud_panel.custom_minimum_size = Vector2(350, 160) # Fit credits, cargo, health, and rep components
	hud_panel.position = Vector2(20, 20)
	add_child(hud_panel)
	
	var vbox = VBoxContainer.new()
	vbox.position = Vector2(10, 10)
	vbox.custom_minimum_size = Vector2(330, 140)
	hud_panel.add_child(vbox)

	time_label = Label.new()
	time_label.text = "Time: Day 001 08:00"
	vbox.add_child(time_label)
	
	credits_label = Label.new()
	credits_label.text = "Credits: 50 SC"
	vbox.add_child(credits_label)
	
	cargo_label = Label.new()
	cargo_label.text = "Cargo: 0 / 100 m³"
	vbox.add_child(cargo_label)
	
	cargo_bar = ProgressBar.new()
	cargo_bar.max_value = GlobalState.cargo_max
	cargo_bar.value = 0
	cargo_bar.custom_minimum_size = Vector2(300, 12)
	vbox.add_child(cargo_bar)
	
	var hp_lbl = Label.new()
	hp_lbl.name = "HPLabel"
	hp_lbl.text = "HP: 100 / 100"
	vbox.add_child(hp_lbl)
	
	var hp_bar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.max_value = 100.0
	hp_bar.value = 100.0
	hp_bar.custom_minimum_size = Vector2(300, 12)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.9, 0.4, 1.0) # Green fill by default
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_right = 3
	sb.corner_radius_bottom_left = 3
	hp_bar.add_theme_stylebox_override("fill", sb)
	vbox.add_child(hp_bar)
	
	# Reputation row — 3 separate labels (one per faction) so each can carry
	# its own color and tooltip. Separators are plain labels (mouse_filter
	# ignored) so they don't intercept hover events on the faction labels.
	var rep_hbox = HBoxContainer.new()
	vbox.add_child(rep_hbox)

	var rep_prefix = Label.new()
	rep_prefix.text = "Rep: "
	rep_hbox.add_child(rep_prefix)

	var zen_lbl = Label.new()
	zen_lbl.name = "ZenRepLabel"
	zen_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	rep_hbox.add_child(zen_lbl)

	var sep1 = Label.new()
	sep1.name = "RepSep1"
	sep1.text = " | "
	rep_hbox.add_child(sep1)

	var aur_lbl = Label.new()
	aur_lbl.name = "AurRepLabel"
	aur_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	rep_hbox.add_child(aur_lbl)

	var sep2 = Label.new()
	sep2.name = "RepSep2"
	sep2.text = " | "
	rep_hbox.add_child(sep2)

	var van_lbl = Label.new()
	van_lbl.name = "VanRepLabel"
	van_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	rep_hbox.add_child(van_lbl)
	
	branch_map = BranchMapUI.new()
	branch_map.visible = false
	add_child(branch_map)

	quest_tracker_panel = PanelContainer.new()
	quest_tracker_panel.custom_minimum_size = Vector2(380, 0)
	quest_tracker_panel.position = Vector2(20, 220)
	add_child(quest_tracker_panel)

	var tracker_style = StyleBoxFlat.new()
	tracker_style.bg_color = Color(0.1, 0.1, 0.12, 0.6)
	tracker_style.border_width_left = 1
	tracker_style.border_width_top = 1
	tracker_style.border_width_right = 1
	tracker_style.border_width_bottom = 1
	tracker_style.border_color = Color(0.0, 0.8, 0.8, 0.5)
	tracker_style.corner_radius_top_left = 4
	tracker_style.corner_radius_top_right = 4
	tracker_style.corner_radius_bottom_right = 4
	tracker_style.corner_radius_bottom_left = 4
	tracker_style.content_margin_left = 8
	tracker_style.content_margin_right = 8
	tracker_style.content_margin_top = 8
	tracker_style.content_margin_bottom = 8
	quest_tracker_panel.add_theme_stylebox_override("panel", tracker_style)

	# HBoxContainer: a Container. By default a single-child Container
	# would just take its child's size. We want a horizontal layout
	# with logo on the left and text on the right, so the hbox
	# itself sizes to the union of its children: logo's 48px width
	# + vbox's expanded width. The vbox will expand to fill the
	# remaining horizontal space (after the logo), and will be as
	# tall as the wrapped text needs.
	var tracker_hbox = HBoxContainer.new()
	tracker_hbox.add_theme_constant_override("separation", 8)
	quest_tracker_panel.add_child(tracker_hbox)

	# Faction branding logo on the left of tracker
	quest_tracker_logo = TextureRect.new()
	quest_tracker_logo.custom_minimum_size = Vector2(48, 48)
	quest_tracker_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	quest_tracker_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	quest_tracker_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tracker_hbox.add_child(quest_tracker_logo)

	# VBox: takes the remaining horizontal space (after the logo)
	# and stacks the header, title, and progress label. The
	# progress label is the one that grows vertically when a long
	# pickup line wraps.
	var tracker_vbox = VBoxContainer.new()
	tracker_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tracker_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tracker_hbox.add_child(tracker_vbox)

	quest_tracker_nav_container = HBoxContainer.new()
	quest_tracker_nav_container.add_theme_constant_override("separation", 4)
	tracker_vbox.add_child(quest_tracker_nav_container)

	quest_tracker_prev_btn = Button.new()
	quest_tracker_prev_btn.text = "<"
	quest_tracker_prev_btn.flat = true
	quest_tracker_prev_btn.custom_minimum_size = Vector2(20, 0)
	quest_tracker_prev_btn.add_theme_font_size_override("font_size", 12)
	quest_tracker_prev_btn.add_theme_color_override("font_color", Color(0.0, 0.9, 0.9))
	quest_tracker_prev_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	quest_tracker_prev_btn.pressed.connect(_on_quest_tracker_prev)
	quest_tracker_nav_container.add_child(quest_tracker_prev_btn)

	quest_tracker_nav_label = Label.new()
	quest_tracker_nav_label.text = "ACTIVE CONTRACT"
	quest_tracker_nav_label.add_theme_font_size_override("font_size", 10)
	quest_tracker_nav_label.add_theme_color_override("font_color", Color(0.0, 0.9, 0.9))
	quest_tracker_nav_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_tracker_nav_container.add_child(quest_tracker_nav_label)

	quest_tracker_next_btn = Button.new()
	quest_tracker_next_btn.text = ">"
	quest_tracker_next_btn.flat = true
	quest_tracker_next_btn.custom_minimum_size = Vector2(20, 0)
	quest_tracker_next_btn.add_theme_font_size_override("font_size", 12)
	quest_tracker_next_btn.add_theme_color_override("font_color", Color(0.0, 0.9, 0.9))
	quest_tracker_next_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	quest_tracker_next_btn.pressed.connect(_on_quest_tracker_next)
	quest_tracker_nav_container.add_child(quest_tracker_next_btn)

	quest_tracker_title = Label.new()
	quest_tracker_title.text = "Contract Title"
	quest_tracker_title.add_theme_font_size_override("font_size", 13)
	# Wrap long LLM-generated titles so the panel can grow vertically
	# instead of letting text spill out the right edge.
	quest_tracker_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_tracker_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tracker_vbox.add_child(quest_tracker_title)

	quest_tracker_progress = Label.new()
	quest_tracker_progress.text = "Progress: 0 / 0"
	quest_tracker_progress.add_theme_font_size_override("font_size", 12)
	# This is the line that overflowed in the user's screenshot
	# ("Pickup: Firmware Module — Nav Compute v3.1 from Alaric Venn @
	# Outpost Iron Reach"). With wrap + expand-fill, it breaks into
	# 2-3 lines inside the panel and the panel grows to fit.
	quest_tracker_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_tracker_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tracker_vbox.add_child(quest_tracker_progress)

	quest_tracker_turn_in_btn = Button.new()
	quest_tracker_turn_in_btn.text = "Turn In To Local Agent"
	quest_tracker_turn_in_btn.visible = false
	quest_tracker_turn_in_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quest_tracker_turn_in_btn.pressed.connect(_on_quest_tracker_turn_in_pressed)
	tracker_vbox.add_child(quest_tracker_turn_in_btn)

	quest_tracker_secondary_container = VBoxContainer.new()
	quest_tracker_secondary_container.add_theme_constant_override("separation", 2)
	tracker_vbox.add_child(quest_tracker_secondary_container)

	quest_tracker_panel.visible = false

	_create_comms_hail_panel()

	# Systems Comms Chat Window (positioned at the bottom-left corner using anchors for responsiveness)
	chat_window_panel = Panel.new()
	chat_window_panel.custom_minimum_size = Vector2(400, 200)
	chat_window_panel.anchor_top = 1.0
	chat_window_panel.anchor_bottom = 1.0
	chat_window_panel.offset_left = 20
	chat_window_panel.offset_top = -220
	chat_window_panel.offset_right = 420
	chat_window_panel.offset_bottom = -20
	add_child(chat_window_panel)
	
	var chat_style = StyleBoxFlat.new()
	chat_style.bg_color = Color(0.08, 0.08, 0.1, 0.6) # Translucent dark background
	chat_style.border_width_left = 1
	chat_style.border_width_top = 1
	chat_style.border_width_right = 1
	chat_style.border_width_bottom = 1
	chat_style.border_color = Color(0.0, 0.85, 1.0, 0.35) # Glowing cyan border
	chat_style.corner_radius_top_left = 6
	chat_style.corner_radius_top_right = 6
	chat_style.corner_radius_bottom_right = 6
	chat_style.corner_radius_bottom_left = 6
	chat_window_panel.add_theme_stylebox_override("panel", chat_style)
	
	var chat_layout = VBoxContainer.new()
	chat_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	chat_layout.offset_left = 10
	chat_layout.offset_right = -10
	chat_layout.offset_top = 8
	chat_layout.offset_bottom = -8
	chat_window_panel.add_child(chat_layout)
	
	var chat_header = Label.new()
	chat_header.text = "SYSTEM COMMS RADIO"
	chat_header.add_theme_font_size_override("font_size", 10)
	chat_header.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0, 0.8))
	chat_layout.add_child(chat_header)
	
	chat_scroll = ScrollContainer.new()
	chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_layout.add_child(chat_scroll)
	
	chat_vbox = VBoxContainer.new()
	chat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_scroll.add_child(chat_vbox)
	
	# Connect signal to print system chatter
	GlobalState.system_chatter_received.connect(add_chat_message)

	# NPC flavor lines: chatter to the corner log AND speak the line
	# in the NPC's unique Kokoro voice. System chatter (alerts, sensor
	# sweeps) doesn't go through this path so it stays text-only.
	GlobalState.npc_flavor_spoken.connect(_on_npc_flavor_spoken)
	
	# Initial welcome message
	add_chat_message("SYSTEM", "Radio channels open. Encryption secure.", Color(0.0, 0.9, 0.9))

func _create_target_panel():
	target_panel = PanelContainer.new()
	add_child(target_panel)
	target_panel.anchor_left = 0.35
	target_panel.anchor_right = 0.65
	target_panel.anchor_top = 0.02
	target_panel.anchor_bottom = 0.02
	target_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	target_panel.grow_vertical = Control.GROW_DIRECTION_END
	
	var margin_container = MarginContainer.new()
	target_panel.add_child(margin_container)
	margin_container.add_theme_constant_override("margin_left", 12)
	margin_container.add_theme_constant_override("margin_right", 12)
	margin_container.add_theme_constant_override("margin_top", 8)
	margin_container.add_theme_constant_override("margin_bottom", 8)
	
	var vbox = VBoxContainer.new()
	margin_container.add_child(vbox)
	
	var target_info_box = HBoxContainer.new()
	target_info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(target_info_box)
	
	target_icon = TextureRect.new()
	target_icon.custom_minimum_size = Vector2(40, 40)
	target_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	target_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	target_icon.gui_input.connect(_on_target_icon_gui_input)
	target_icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	target_info_box.add_child(target_icon)
	
	target_label = Label.new()
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	target_label.text = "No Target Selected"
	target_info_box.add_child(target_label)
	
	target_action_box = HBoxContainer.new()
	target_action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(target_action_box)

	target_boost_btn = Button.new()
	target_boost_btn.text = "Boost"
	target_boost_btn.tooltip_text = "25% speed boost for 5 seconds. 60 second cooldown."
	target_boost_btn.pressed.connect(_on_boost_pressed)
	target_action_box.add_child(target_boost_btn)

	target_approach_btn = Button.new()
	target_approach_btn.text = "Fly to"
	target_approach_btn.pressed.connect(func():
		_command_selected_target(
			"JUMP_APPROACH"
				if GlobalState.active_target
					and GlobalState.active_target.is_in_group("jumpgate")
				else "APPROACH"
		)
	)
	target_action_box.add_child(target_approach_btn)
	
	target_orbit_btn = Button.new()
	target_orbit_btn.text = "Orbit"
	target_orbit_btn.pressed.connect(func():
		_command_selected_target("ORBIT")
	)
	target_action_box.add_child(target_orbit_btn)
	
	target_action_btn = Button.new()
	target_action_btn.name = "TargetActionButton"
	target_action_btn.pressed.connect(func():
		var t = GlobalState.active_target
		if t and is_instance_valid(t) and GlobalState.player:
			if t.is_in_group("asteroid"):
				_command_selected_target("MINE")
			elif t.is_in_group("station") or t.has_method("dock_player"):
				_command_selected_target("DOCK")
			elif t.is_in_group("jumpgate"):
				activate_selected_jumpgate()
			else:
				_command_selected_target("ATTACK")
	)
	target_action_box.add_child(target_action_btn)
	
	target_panel.visible = false

func _create_overview():
	map_btn = Button.new()
	map_btn.text = "SYSTEM MAP"
	map_btn.visible = false
	map_btn.anchor_left = 0.78
	map_btn.anchor_right = 0.98
	map_btn.anchor_top = 0.01
	map_btn.anchor_bottom = 0.045
	map_btn.offset_left = 0
	map_btn.offset_right = 0
	map_btn.offset_top = 0
	map_btn.offset_bottom = 0
	map_btn.pressed.connect(_toggle_branch_map)
	add_child(map_btn)

	inventory_hud_btn = Button.new()
	inventory_hud_btn.text = "INVENTORY"
	inventory_hud_btn.visible = true
	inventory_hud_btn.anchor_left = 0.66
	inventory_hud_btn.anchor_right = 0.77
	inventory_hud_btn.anchor_top = 0.01
	inventory_hud_btn.anchor_bottom = 0.045
	inventory_hud_btn.offset_left = 0
	inventory_hud_btn.offset_right = 0
	inventory_hud_btn.offset_top = 0
	inventory_hud_btn.offset_bottom = 0
	inventory_hud_btn.pressed.connect(_on_inventory_pressed)
	add_child(inventory_hud_btn)

	overview_panel = Panel.new()
	add_child(overview_panel)
	overview_panel.anchor_left = 0.78
	overview_panel.anchor_right = 0.98
	overview_panel.anchor_top = 0.05
	overview_panel.anchor_bottom = 0.65
	overview_panel.offset_left = 0
	overview_panel.offset_right = 0
	overview_panel.offset_top = 0
	overview_panel.offset_bottom = 0
	
	var vbox = VBoxContainer.new()
	overview_panel.add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0
	
	# Create a dedicated resize handle on the left edge
	resize_handle = Control.new()
	resize_handle.name = "ResizeHandle"
	overview_panel.add_child(resize_handle)
	resize_handle.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	resize_handle.offset_left = 0
	resize_handle.offset_right = 8
	resize_handle.offset_top = 0
	resize_handle.offset_bottom = 0
	resize_handle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	resize_handle.gui_input.connect(_on_resize_handle_input)
	
	var title_hbox = HBoxContainer.new()
	title_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(title_hbox)
	
	# Spacer for centering title
	var title_spacer = Control.new()
	title_spacer.custom_minimum_size = Vector2(25, 0)
	title_hbox.add_child(title_spacer)
	
	var title = Label.new()
	title.text = "OVERVIEW"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_hbox.add_child(title)
	overview_title_label = title
	
	collapse_btn = Button.new()
	collapse_btn.text = " ▲ "
	collapse_btn.flat = true
	collapse_btn.pressed.connect(func(): set_overview_collapsed(not overview_collapsed))
	title_hbox.add_child(collapse_btn)
	
	# Create Header HBox for sorting
	var header_hbox = HBoxContainer.new()
	header_hbox.custom_minimum_size = Vector2(0, 25)
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header_hbox)
	
	btn_name = Button.new()
	btn_name.text = "Name"
	btn_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_name.pressed.connect(func(): _on_header_clicked("name"))
	header_hbox.add_child(btn_name)
	
	btn_dist = Button.new()
	btn_dist.text = "Distance"
	btn_dist.custom_minimum_size = Vector2(110, 0)
	btn_dist.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_dist.pressed.connect(func(): _on_header_clicked("distance"))
	header_hbox.add_child(btn_dist)
	
	btn_type = Button.new()
	btn_type.text = "Type"
	btn_type.custom_minimum_size = Vector2(160, 0)
	btn_type.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_type.pressed.connect(func(): _on_header_clicked("type"))
	header_hbox.add_child(btn_type)
	
	var header_spacer = Control.new()
	header_spacer.custom_minimum_size = Vector2(8, 0)
	header_hbox.add_child(header_spacer)
	
	_update_header_labels()
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	
	overview_list = VBoxContainer.new()
	overview_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(overview_list)

func _on_header_clicked(column: String):
	if sort_column == column:
		sort_ascending = not sort_ascending
	else:
		sort_column = column
		sort_ascending = true
	_update_header_labels()
	_update_overview_distances()

func _update_header_labels():
	btn_name.text = "Name" + (" ▲" if sort_column == "name" and sort_ascending else " ▼" if sort_column == "name" else "")
	btn_dist.text = "Distance" + (" ▲" if sort_column == "distance" and sort_ascending else " ▼" if sort_column == "distance" else "")
	btn_type.text = "Type" + (" ▲" if sort_column == "type" and sort_ascending else " ▼" if sort_column == "type" else "")

func _create_dock_menu():
	dock_panel = Panel.new()
	add_child(dock_panel)
	dock_panel.anchor_left = 0.3
	dock_panel.anchor_right = 0.7
	dock_panel.anchor_top = 0.25
	dock_panel.anchor_bottom = 0.75
	dock_panel.offset_left = 0
	dock_panel.offset_right = 0
	dock_panel.offset_top = 0
	dock_panel.offset_bottom = 0

	# Dark panel background so the dock menu is readable over busy space backdrops
	var dock_style = StyleBoxFlat.new()
	dock_style.bg_color = Color(0.08, 0.08, 0.10, 0.92)
	dock_style.border_width_left = 2
	dock_style.border_width_top = 2
	dock_style.border_width_right = 2
	dock_style.border_width_bottom = 2
	dock_style.border_color = Color(0.0, 0.6, 0.6, 1.0)
	dock_style.corner_radius_top_left = 4
	dock_style.corner_radius_top_right = 4
	dock_style.corner_radius_bottom_right = 4
	dock_style.corner_radius_bottom_left = 4
	dock_panel.add_theme_stylebox_override("panel", dock_style)

	# Background image (RepairShop.png) — only shown when docked at a repair_shop.
	# Sized to fill the panel and tinted dark so the foreground buttons stay readable.
	dock_background = TextureRect.new()
	dock_background.name = "DockBackground"
	dock_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	dock_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dock_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	dock_background.modulate = Color(0.35, 0.30, 0.28, 0.65)  # Darken so buttons read on top
	dock_background.visible = false
	dock_background.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block button clicks
	dock_panel.add_child(dock_background)
	# Background is added BEFORE the vbox below, so it naturally renders
	# behind the buttons in draw order. No move_to_front call needed.

	var vbox = VBoxContainer.new()
	dock_panel.add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	dock_label = Label.new()
	dock_label.text = "STATION SERVICES"
	dock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(dock_label)

	# ── Mechanic (Jenna Kross) intro panel ─────────────────────────────────
	# Lives in the dock panel, shown only while the maintenance submenu is
	# active. Portrait (left, sliced from MinorNPC02.png at Jenna's cell) +
	# name + greeting chat box (right) + a small "Speak" button to roll a
	# new line. Visible by default? No — _render_mechanic_intro() shows it
	# only on maintenance submenu, and clears it on services / undock.
	mechanic_intro_panel = PanelContainer.new()
	mechanic_intro_panel.name = "MechanicIntroPanel"
	mechanic_intro_panel.visible = false
	mechanic_intro_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mech_style := StyleBoxFlat.new()
	mech_style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	mech_style.border_width_left = 1
	mech_style.border_width_top = 1
	mech_style.border_width_right = 1
	mech_style.border_width_bottom = 1
	# Warm amber border to match Jenna's flavor_color (GlobalState.MINOR_NPCS).
	mech_style.border_color = Color(1.0, 0.85, 0.4, 0.6)
	mech_style.corner_radius_top_left = 4
	mech_style.corner_radius_top_right = 4
	mech_style.corner_radius_bottom_right = 4
	mech_style.corner_radius_bottom_left = 4
	mech_style.content_margin_left = 8
	mech_style.content_margin_right = 8
	mech_style.content_margin_top = 6
	mech_style.content_margin_bottom = 6
	mechanic_intro_panel.add_theme_stylebox_override("panel", mech_style)
	vbox.add_child(mechanic_intro_panel)

	mechanic_intro_hbox = HBoxContainer.new()
	mechanic_intro_hbox.add_theme_constant_override("separation", 12)
	mechanic_intro_panel.add_child(mechanic_intro_hbox)

	mechanic_portrait = TextureRect.new()
	mechanic_portrait.custom_minimum_size = Vector2(96, 96)
	mechanic_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mechanic_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mechanic_intro_hbox.add_child(mechanic_portrait)

	var mech_text_vbox := VBoxContainer.new()
	mech_text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mech_text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	mechanic_intro_hbox.add_child(mech_text_vbox)

	mechanic_name_label = Label.new()
	mechanic_name_label.text = "JENNA KROSS"
	mechanic_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mechanic_name_label.add_theme_font_size_override("font_size", 14)
	mechanic_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	mechanic_name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	mechanic_name_label.add_theme_constant_override("shadow_outline_size", 2)
	mech_text_vbox.add_child(mechanic_name_label)

	mechanic_line_label = Label.new()
	mechanic_line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mechanic_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	mechanic_line_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mechanic_line_label.add_theme_font_size_override("font_size", 14)
	mechanic_line_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	mechanic_line_label.add_theme_constant_override("shadow_outline_size", 2)
	mech_text_vbox.add_child(mechanic_line_label)

	var offer_btns_hbox := HBoxContainer.new()
	offer_btns_hbox.add_theme_constant_override("separation", 6)
	mech_text_vbox.add_child(offer_btns_hbox)

	mechanic_pickup_accept_btn = Button.new()
	mechanic_pickup_accept_btn.text = "I'll grab it"
	mechanic_pickup_accept_btn.visible = false
	mechanic_pickup_accept_btn.pressed.connect(_on_mechanic_pickup_accept_pressed)
	offer_btns_hbox.add_child(mechanic_pickup_accept_btn)

	mechanic_pickup_decline_btn = Button.new()
	mechanic_pickup_decline_btn.text = "Not now"
	mechanic_pickup_decline_btn.visible = false
	mechanic_pickup_decline_btn.pressed.connect(_on_mechanic_pickup_decline_pressed)
	offer_btns_hbox.add_child(mechanic_pickup_decline_btn)

	# Docked-message slot. Hidden by default; surfaces flavor lines
	# (Hear Gossip) and quest pickup responses inside the dock panel.
	# See show_dock_message() for the display + auto-dismiss logic.
	dock_message_slot = PanelContainer.new()
	dock_message_slot.visible = false
	dock_message_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Subtle style: translucent dark bg, no border. The portrait chip
	# and name label carry the speaker identity color themselves.
	var msg_style := StyleBoxFlat.new()
	msg_style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	msg_style.corner_radius_top_left = 4
	msg_style.corner_radius_top_right = 4
	msg_style.corner_radius_bottom_right = 4
	msg_style.corner_radius_bottom_left = 4
	msg_style.content_margin_left = 8
	msg_style.content_margin_right = 8
	msg_style.content_margin_top = 6
	msg_style.content_margin_bottom = 6
	dock_message_slot.add_theme_stylebox_override("panel", msg_style)
	vbox.add_child(dock_message_slot)

	dock_message_hbox = HBoxContainer.new()
	dock_message_hbox.add_theme_constant_override("separation", 10)
	dock_message_slot.add_child(dock_message_hbox)

	dock_message_portrait = TextureRect.new()
	dock_message_portrait.custom_minimum_size = Vector2(64, 64)
	dock_message_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dock_message_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dock_message_portrait.visible = false  # hidden when message has no portrait
	dock_message_hbox.add_child(dock_message_portrait)

	var msg_text_vbox := VBoxContainer.new()
	msg_text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dock_message_hbox.add_child(msg_text_vbox)

	dock_message_name = Label.new()
	dock_message_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dock_message_name.add_theme_font_size_override("font_size", 14)
	dock_message_name.add_theme_color_override("font_shadow_color", Color.BLACK)
	dock_message_name.add_theme_constant_override("shadow_outline_size", 2)
	# Empty text by default — show_dock_message sets the actual
	# speaker name. If npc_name is empty, we hide the name label.
	msg_text_vbox.add_child(dock_message_name)

	dock_message_line = Label.new()
	dock_message_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dock_message_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	dock_message_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock_message_line.add_theme_font_size_override("font_size", 16)
	dock_message_line.add_theme_color_override("font_shadow_color", Color.BLACK)
	dock_message_line.add_theme_constant_override("shadow_outline_size", 2)
	msg_text_vbox.add_child(dock_message_line)

	station_contacts_panel = PanelContainer.new()
	station_contacts_panel.name = "StationContactsPanel"
	station_contacts_panel.visible = false
	station_contacts_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var contacts_style := StyleBoxFlat.new()
	contacts_style.bg_color = Color(0.04, 0.055, 0.08, 0.82)
	contacts_style.border_width_left = 1
	contacts_style.border_width_top = 1
	contacts_style.border_width_right = 1
	contacts_style.border_width_bottom = 1
	contacts_style.border_color = Color(0.0, 0.65, 0.75, 0.35)
	contacts_style.corner_radius_top_left = 4
	contacts_style.corner_radius_top_right = 4
	contacts_style.corner_radius_bottom_right = 4
	contacts_style.corner_radius_bottom_left = 4
	contacts_style.content_margin_left = 8
	contacts_style.content_margin_right = 8
	contacts_style.content_margin_top = 6
	contacts_style.content_margin_bottom = 6
	station_contacts_panel.add_theme_stylebox_override("panel", contacts_style)
	vbox.add_child(station_contacts_panel)

	station_contacts_list = VBoxContainer.new()
	station_contacts_list.add_theme_constant_override("separation", 4)
	station_contacts_panel.add_child(station_contacts_list)

	ore_trade_popup = PanelContainer.new()
	ore_trade_popup.name = "OreTradePopup"
	ore_trade_popup.visible = false
	ore_trade_popup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var otp_style := StyleBoxFlat.new()
	otp_style.bg_color = Color(0.08, 0.06, 0.04, 0.95)
	otp_style.border_width_left = 1
	otp_style.border_width_top = 1
	otp_style.border_width_right = 1
	otp_style.border_width_bottom = 1
	otp_style.border_color = Color(1.0, 0.7, 0.3, 0.7)
	otp_style.corner_radius_top_left = 4
	otp_style.corner_radius_top_right = 4
	otp_style.corner_radius_bottom_right = 4
	otp_style.corner_radius_bottom_left = 4
	otp_style.content_margin_left = 10
	otp_style.content_margin_right = 10
	otp_style.content_margin_top = 8
	otp_style.content_margin_bottom = 8
	ore_trade_popup.add_theme_stylebox_override("panel", otp_style)
	vbox.add_child(ore_trade_popup)

	var otp_vbox := VBoxContainer.new()
	otp_vbox.add_theme_constant_override("separation", 8)
	ore_trade_popup.add_child(otp_vbox)

	ore_trade_label = Label.new()
	ore_trade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ore_trade_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	ore_trade_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ore_trade_label.add_theme_font_size_override("font_size", 14)
	ore_trade_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	ore_trade_label.add_theme_constant_override("shadow_outline_size", 2)
	otp_vbox.add_child(ore_trade_label)

	var otp_btn_row := HBoxContainer.new()
	otp_btn_row.add_theme_constant_override("separation", 8)
	otp_vbox.add_child(otp_btn_row)

	ore_trade_accept_btn = Button.new()
	ore_trade_accept_btn.text = "Sell Ore, Take the Part"
	ore_trade_accept_btn.pressed.connect(_on_ore_trade_accept_pressed)
	otp_btn_row.add_child(ore_trade_accept_btn)

	ore_trade_decline_btn = Button.new()
	ore_trade_decline_btn.text = "No, Keep My Ore"
	ore_trade_decline_btn.pressed.connect(_on_ore_trade_decline_pressed)
	otp_btn_row.add_child(ore_trade_decline_btn)

	sell_btn = Button.new()
	sell_btn.text = "Sell Ore (1 SC per m³)"
	sell_btn.pressed.connect(_sell_ore)
	vbox.add_child(sell_btn)
	

	repair_btn = Button.new()
	repair_btn.text = "Repair Ship"
	repair_btn.pressed.connect(_repair_ship)
	vbox.add_child(repair_btn)

	# ── Test: outpost pickup quest (DEBUG) ─────────────────────────────────
	# Triggers a random special-cargo pickup: picks a random outpost and a
	# random NPC stationed there, loads a random part into the hold, and
	# marks the mechanic as the destination. Use the "Test: Deliver" button
	# to clear the cargo and complete the test cycle. Rerun by clicking again.
	test_pickup_btn = Button.new()
	test_pickup_btn.text = "Test: Start Pickup Quest"
	test_pickup_btn.pressed.connect(_on_test_pickup_pressed)
	vbox.add_child(test_pickup_btn)

	test_deliver_btn = Button.new()
	test_deliver_btn.text = "Test: Deliver Part"
	test_deliver_btn.pressed.connect(_on_test_deliver_pressed)
	vbox.add_child(test_deliver_btn)

	# Outpost-only: completes the pickup half of the test quest. Shown only
	# at outpost docks (see _render_dock_submenu). Disabled-by-default
	# visibility stays off until the player docks at an outpost.
	test_pickup_part_btn = Button.new()
	test_pickup_part_btn.text = "Test: Pickup Part"
	test_pickup_part_btn.pressed.connect(_on_test_pickup_part_pressed)
	vbox.add_child(test_pickup_part_btn)

	ask_for_part_btn = Button.new()
	ask_for_part_btn.text = "Ask for the Part"
	ask_for_part_btn.visible = false
	ask_for_part_btn.pressed.connect(_on_ask_for_part_pressed)
	vbox.add_child(ask_for_part_btn)

	deliver_part_btn = Button.new()
	deliver_part_btn.text = "Deliver Part"
	deliver_part_btn.visible = false
	deliver_part_btn.pressed.connect(_on_deliver_part_pressed)
	vbox.add_child(deliver_part_btn)

	# Outpost-only: surface a random minor-NPC flavor line. Shown only at
	# outpost docks (see _render_dock_submenu).
	hear_gossip_btn = Button.new()
	hear_gossip_btn.text = "Hear Gossip from the Locals"
	hear_gossip_btn.pressed.connect(_on_hear_gossip_pressed)
	vbox.add_child(hear_gossip_btn)

	agent_service_btn = Button.new()
	agent_service_btn.text = "Talk to Agent"
	agent_service_btn.pressed.connect(_on_talk_to_agent_pressed)
	vbox.add_child(agent_service_btn)

	public_board_btn = Button.new()
	public_board_btn.text = "Public Contract Board"
	public_board_btn.pressed.connect(_on_public_board_pressed)
	vbox.add_child(public_board_btn)

	maintenance_bay_btn = Button.new()
	maintenance_bay_btn.text = "Maintenance Bay (Grease Monkeys)"
	maintenance_bay_btn.pressed.connect(_on_maintenance_bay_pressed)
	vbox.add_child(maintenance_bay_btn)

	store_btn = Button.new()
	store_btn.text = "Station Store"
	store_btn.pressed.connect(_on_store_pressed)
	vbox.add_child(store_btn)

	inventory_btn = Button.new()
	inventory_btn.text = "Inventory"
	inventory_btn.pressed.connect(_on_inventory_pressed)
	vbox.add_child(inventory_btn)

	ship_upgrades_btn = Button.new()
	ship_upgrades_btn.text = "Ship Upgrades (Rusthawk UI)"
	ship_upgrades_btn.pressed.connect(_on_ship_upgrades_pressed)
	vbox.add_child(ship_upgrades_btn)

	back_to_services_btn = Button.new()
	back_to_services_btn.text = "Back to Services"
	back_to_services_btn.pressed.connect(_on_back_to_services_pressed)
	vbox.add_child(back_to_services_btn)

	var undock_btn = Button.new()
	undock_btn.text = "Undock Ship"
	undock_btn.pressed.connect(undock_player)
	vbox.add_child(undock_btn)
	
	dock_panel.visible = false
	
	# Construct Agent Panel
	agent_panel = Panel.new()
	add_child(agent_panel)
	agent_panel.anchor_left = 0.25
	agent_panel.anchor_right = 0.75
	agent_panel.anchor_top = 0.2
	agent_panel.anchor_bottom = 0.8
	agent_panel.offset_left = 0
	agent_panel.offset_right = 0
	agent_panel.offset_top = 0
	agent_panel.offset_bottom = 0
	agent_panel.visible = false
	
	var agent_style = StyleBoxFlat.new()
	agent_style.bg_color = Color(0.12, 0.12, 0.15, 1.0)
	agent_style.border_width_left = 2
	agent_style.border_width_top = 2
	agent_style.border_width_right = 2
	agent_style.border_width_bottom = 2
	agent_style.border_color = Color(0.0, 0.8, 0.8, 1.0)
	agent_style.corner_radius_top_left = 4
	agent_style.corner_radius_top_right = 4
	agent_style.corner_radius_bottom_right = 4
	agent_style.corner_radius_bottom_left = 4
	agent_panel.add_theme_stylebox_override("panel", agent_style)
	
	var agent_hbox = HBoxContainer.new()
	agent_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	agent_hbox.offset_left = 15
	agent_hbox.offset_right = -15
	agent_hbox.offset_top = 15
	agent_hbox.offset_bottom = -15
	agent_panel.add_child(agent_hbox)
	
	# Left Side: Agent Portrait
	var portrait_vbox = VBoxContainer.new()
	agent_portrait_column = portrait_vbox
	portrait_vbox.custom_minimum_size = Vector2(180, 0)
	portrait_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	agent_hbox.add_child(portrait_vbox)
	
	agent_portrait = TextureRect.new()
	agent_portrait.custom_minimum_size = Vector2(180, 180)
	agent_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	agent_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_vbox.add_child(agent_portrait)
	
	var col_spacer = Control.new()
	col_spacer.custom_minimum_size = Vector2(20, 0)
	agent_hbox.add_child(col_spacer)
	
	# Right Side: Text details and choice menus
	var avbox = VBoxContainer.new()
	avbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avbox.alignment = BoxContainer.ALIGNMENT_CENTER
	agent_hbox.add_child(avbox)
	
	# Header Layout containing title, subtitle, and faction branding logo on the right
	var header_hbox = HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avbox.add_child(header_hbox)
	
	var name_vbox = VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(name_vbox)
	
	agent_name_label = Label.new()
	agent_name_label.text = "BROKER KAELEN"
	agent_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	agent_name_label.add_theme_color_override("font_color", Color(0.0, 0.9, 0.9))
	agent_name_label.add_theme_font_size_override("font_size", 18)
	name_vbox.add_child(agent_name_label)
	
	agent_subtitle_label = Label.new()
	agent_subtitle_label.text = "Neutral Fixer & Profit Broker"
	agent_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	agent_subtitle_label.add_theme_font_size_override("font_size", 11)
	agent_subtitle_label.modulate = Color(0.7, 0.7, 0.7)
	name_vbox.add_child(agent_subtitle_label)
	
	agent_client_logo = TextureRect.new()
	agent_client_logo.custom_minimum_size = Vector2(64, 64)
	agent_client_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	agent_client_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	agent_client_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_hbox.add_child(agent_client_logo)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	avbox.add_child(spacer)
	
	var dialogue_scroll = ScrollContainer.new()
	dialogue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	avbox.add_child(dialogue_scroll)
	
	agent_dialogue_label = Label.new()
	agent_dialogue_label.text = "What is your business here, pilot? If it doesn't make credits, it's not my concern."
	agent_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	agent_dialogue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agent_dialogue_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_scroll.add_child(agent_dialogue_label)
	
	agent_choices_container = VBoxContainer.new()
	agent_choices_container.alignment = BoxContainer.ALIGNMENT_CENTER
	avbox.add_child(agent_choices_container)
	
	agent_back_btn = Button.new()
	agent_back_btn.text = "Back to Services"
	agent_back_btn.pressed.connect(_on_agent_back_pressed)
	avbox.add_child(agent_back_btn)

	_create_public_board_panel()
	_create_store_panel()
	_create_inventory_panel()


func _create_store_panel() -> void:
	store_panel = Panel.new()
	add_child(store_panel)
	store_panel.anchor_left = 0.22
	store_panel.anchor_right = 0.78
	store_panel.anchor_top = 0.16
	store_panel.anchor_bottom = 0.84
	store_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.11, 0.98)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.75, 0.4, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	store_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 16
	vbox.offset_bottom = -16
	vbox.add_theme_constant_override("separation", 8)
	store_panel.add_child(vbox)

	var title := Label.new()
	title.text = "STATION STORE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	vbox.add_child(title)

	store_credits_label = Label.new()
	store_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	store_credits_label.add_theme_font_size_override("font_size", 14)
	store_credits_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(store_credits_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	store_list = VBoxContainer.new()
	store_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	store_list.add_theme_constant_override("separation", 6)
	scroll.add_child(store_list)

	store_back_btn = Button.new()
	store_back_btn.text = "Back to Services"
	store_back_btn.pressed.connect(_on_store_back_pressed)
	vbox.add_child(store_back_btn)


func _create_inventory_panel() -> void:
	inventory_panel = Panel.new()
	add_child(inventory_panel)
	inventory_panel.anchor_left = 0.22
	inventory_panel.anchor_right = 0.78
	inventory_panel.anchor_top = 0.16
	inventory_panel.anchor_bottom = 0.84
	inventory_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.11, 0.98)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.65, 0.95, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	inventory_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 16
	vbox.offset_bottom = -16
	vbox.add_theme_constant_override("separation", 8)
	inventory_panel.add_child(vbox)

	var title := Label.new()
	title.text = "SHIP INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 1.0))
	vbox.add_child(title)

	inventory_summary_label = Label.new()
	inventory_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inventory_summary_label.add_theme_font_size_override("font_size", 14)
	inventory_summary_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(inventory_summary_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	inventory_list = VBoxContainer.new()
	inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_list.add_theme_constant_override("separation", 6)
	scroll.add_child(inventory_list)

	inventory_back_btn = Button.new()
	inventory_back_btn.text = "Back to Services"
	inventory_back_btn.pressed.connect(_on_inventory_back_pressed)
	vbox.add_child(inventory_back_btn)


func _create_public_board_panel() -> void:
	public_board_panel = Panel.new()
	add_child(public_board_panel)
	public_board_panel.anchor_left = 0.22
	public_board_panel.anchor_right = 0.78
	public_board_panel.anchor_top = 0.16
	public_board_panel.anchor_bottom = 0.84
	public_board_panel.offset_left = 0
	public_board_panel.offset_right = 0
	public_board_panel.offset_top = 0
	public_board_panel.offset_bottom = 0
	public_board_panel.visible = false

	var board_style := StyleBoxFlat.new()
	board_style.bg_color = Color(0.09, 0.09, 0.11, 0.98)
	board_style.border_width_left = 2
	board_style.border_width_top = 2
	board_style.border_width_right = 2
	board_style.border_width_bottom = 2
	board_style.border_color = Color(0.85, 0.52, 0.18, 0.9)
	board_style.corner_radius_top_left = 4
	board_style.corner_radius_top_right = 4
	board_style.corner_radius_bottom_right = 4
	board_style.corner_radius_bottom_left = 4
	public_board_panel.add_theme_stylebox_override("panel", board_style)

	var board_vbox := VBoxContainer.new()
	board_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_vbox.offset_left = 16
	board_vbox.offset_right = -16
	board_vbox.offset_top = 16
	board_vbox.offset_bottom = -16
	board_vbox.add_theme_constant_override("separation", 10)
	public_board_panel.add_child(board_vbox)

	var title := Label.new()
	title.text = "PUBLIC CONTRACT BOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.32))
	board_vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Local postings. Verified mechanics. Questionable judgment."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.modulate = Color(0.75, 0.75, 0.78)
	board_vbox.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	board_vbox.add_child(scroll)

	public_board_list = VBoxContainer.new()
	public_board_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	public_board_list.add_theme_constant_override("separation", 8)
	scroll.add_child(public_board_list)

	public_board_back_btn = Button.new()
	public_board_back_btn.text = "Back to Services"
	public_board_back_btn.pressed.connect(_on_public_board_back_pressed)
	board_vbox.add_child(public_board_back_btn)


func _render_public_board_offers() -> void:
	public_board_current_offers = PublicBoardOfferBuilderType.build_offers(
		CampaignClock.total_minutes
	)
	for index in range(public_board_current_offers.size()):
		public_board_current_offers[index] = (
			PublicBoardTextGeneratorType.fallback_offer(
				public_board_current_offers[index],
				CampaignClock.total_minutes + index
			)
		)
	_redraw_public_board_offers()
	for index in range(public_board_current_offers.size()):
		if bool(public_board_current_offers[index].get("enabled", false)):
			_request_public_board_text_attempt(
				index,
				public_board_current_offers[index],
				"",
				0
			)


func _redraw_public_board_offers() -> void:
	for child in public_board_list.get_children():
		child.queue_free()
	for index in range(public_board_current_offers.size()):
		_add_public_board_posting(public_board_current_offers[index], index)


func _request_public_board_text_attempt(
	index: int,
	offer: Dictionary,
	critique: String,
	attempt: int
) -> void:
	if attempt >= 2 or not LLMInterface.llm_connected:
		return
	var request := PublicBoardTextGeneratorType.build_generation_request(
		offer,
		critique
	)
	var url: String = LLMInterface.OLLAMA_URL
	var model: String = (
		LLMInterface.active_model_name
		if LLMInterface.active_model_name != "" else "qwen2.5:1.5b"
	)
	var body: Dictionary = {
		"model": model,
		"prompt": str(request.get("prompt", "")),
		"stream": false,
		"format": "json",
		"options": { "temperature": 0.8, "num_predict": 220 },
	}
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 8.0
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body_bytes: PackedByteArray) -> void:
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var raw := body_bytes.get_string_from_utf8()
		var outer = JSON.parse_string(raw)
		if not outer is Dictionary or not outer.has("response"):
			return
		var payload = JSON.parse_string(str(outer["response"]))
		if not payload is Dictionary:
			return
		var applied := PublicBoardTextGeneratorType.apply_payload_to_offer(
			offer,
			payload,
			false
		)
		if bool(applied.get("ok", false)):
			if index < 0 or index >= public_board_current_offers.size():
				return
			if str(public_board_current_offers[index].get("template_id", "")) \
					!= str(offer.get("template_id", "")):
				return
			public_board_current_offers[index] = applied["offer"]
			if public_board_panel and public_board_panel.visible:
				_redraw_public_board_offers()
			return
		if attempt == 0:
			_request_public_board_text_attempt(
				index,
				offer,
				str(applied.get("reason", "invalid generated text")),
				attempt + 1
			)
	)
	var err := http.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if err != OK:
		http.queue_free()


func _add_public_board_posting(posting: Dictionary, index: int) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.055, 0.92)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.42, 0.25, 0.7)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)
	public_board_list.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var title := Label.new()
	title.text = str(posting.get("title", "Untitled Posting"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.38))
	vbox.add_child(title)

	var poster := Label.new()
	poster.text = "Posted by: %s" % str(posting.get("poster", "Anonymous"))
	poster.add_theme_font_size_override("font_size", 11)
	poster.modulate = Color(0.72, 0.72, 0.76)
	vbox.add_child(poster)

	var body := Label.new()
	body.text = str(posting.get("body", "The details are suspiciously missing."))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	var objective := Label.new()
	objective.text = "Verified objective: %s" % str(posting.get("objective", "Pending"))
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	vbox.add_child(objective)

	var payout := Label.new()
	var base_reward := int(posting.get("base_reward", 0))
	var duration_minutes := int(posting.get("duration_minutes", 0))
	var urgent_multiplier := float(posting.get("urgent_multiplier", 1.0))
	var payout_text := "%d SC" % base_reward
	if duration_minutes > 0:
		payout_text = "%d SC urgent payout | %s remaining" % [
			int(round(float(base_reward) * urgent_multiplier)),
			CampaignClock.format_duration(duration_minutes),
		]
	payout.text = "Payout: %s" % payout_text
	payout.add_theme_color_override("font_color", Color(0.65, 1.0, 0.55))
	vbox.add_child(payout)

	var accept := Button.new()
	if _should_show_public_board_turn_in():
		accept.text = "Turn In Active Board Job To Local Agent"
		accept.disabled = false
		accept.pressed.connect(_on_public_board_turn_in_pressed)
	elif QuestManager.is_lane_occupied("BOARD"):
		accept.text = "Board Job Already Active"
		accept.disabled = true
	elif not bool(posting.get("enabled", false)):
		var cooldown_remaining: int = int(posting.get("cooldown_remaining", 0))
		if cooldown_remaining > 0:
			accept.text = "On Cooldown — %s" % CampaignClock.format_duration(cooldown_remaining)
		else:
			accept.text = "Template Coming Soon"
		accept.disabled = true
	else:
		accept.text = "Accept Posting"
		accept.disabled = false
		accept.pressed.connect(func(): _on_public_board_offer_accept(index))
	vbox.add_child(accept)


func _create_context_menu():
	context_panel = Panel.new()
	add_child(context_panel)
	context_panel.custom_minimum_size = Vector2(170, 205)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 1.0) # Solid, non-translucent dark background
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.35, 0.35, 0.45, 1.0) # Solid grey-blue border
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	context_panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	context_panel.add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0

	var action_select = Button.new()
	action_select.text = "Select Target"
	action_select.pressed.connect(func():
		if context_highlight_target \
				and is_instance_valid(context_highlight_target):
			GlobalState.active_target = context_highlight_target
		_close_context_menu()
	)
	vbox.add_child(action_select)
	
	var action_app = Button.new()
	action_app.text = "Fly to"
	action_app.pressed.connect(func():
		_command_context_target(
			"JUMP_APPROACH"
				if context_highlight_target
					and context_highlight_target.is_in_group("jumpgate")
				else "APPROACH"
		)
		_close_context_menu()
	)
	vbox.add_child(action_app)
	
	var action_orb = Button.new()
	action_orb.text = "Orbit"
	action_orb.pressed.connect(func():
		_command_context_target("ORBIT")
		_close_context_menu()
	)
	vbox.add_child(action_orb)
	
	var action_act = Button.new()
	action_act.name = "ActionButton"
	context_action_btn = action_act
	action_act.text = "Mine / Attack"
	action_act.pressed.connect(func():
		var t = context_highlight_target
		if t and is_instance_valid(t) and GlobalState.player:
			if t.is_in_group("asteroid"):
				_command_context_target("MINE")
			elif t.is_in_group("station") or t.has_method("dock_player"):
				_command_context_target("DOCK")
			elif t.is_in_group("jumpgate"):
				GlobalState.active_target = t
				activate_selected_jumpgate()
			else:
				_command_context_target("ATTACK")
		_close_context_menu()
	)
	vbox.add_child(action_act)
	
	var action_close = Button.new()
	action_close.text = "Cancel"
	action_close.pressed.connect(_close_context_menu)
	vbox.add_child(action_close)
	
	context_panel.visible = false

func _create_pause_menu():
	pause_panel = Panel.new()
	add_child(pause_panel)
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_theme_stylebox_override(
		"panel",
		_make_menu_style(Color(0.015, 0.025, 0.045, 0.96), Color(0.0, 0.65, 0.8, 0.3), 0)
	)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(center)
	var shell := PanelContainer.new()
	shell.custom_minimum_size = Vector2(920, 590)
	shell.add_theme_stylebox_override(
		"panel",
		_make_menu_style(Color(0.045, 0.055, 0.085, 0.98), Color(0.0, 0.85, 1.0, 0.55), 26)
	)
	center.add_child(shell)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	shell.add_child(layout)
	var title := Label.new()
	title.text = "FLIGHT OPERATIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	layout.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Game paused"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	layout.add_child(subtitle)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	layout.add_child(columns)
	var actions_card := _make_pause_card("COMMAND")
	actions_card.custom_minimum_size = Vector2(330, 0)
	columns.add_child(actions_card)
	var actions := actions_card.get_child(0) as VBoxContainer
	_add_pause_action(actions, "RESUME FLIGHT", func(): GlobalState.paused = false, true)
	_add_pause_action(actions, "CAMPAIGNS & SAVES", _open_campaign_manager)
	pause_new_campaign_button = _add_pause_action(
		actions,
		"START NEW CAMPAIGN",
		_start_new_campaign
	)
	_refresh_new_campaign_availability()
	_add_pause_action(actions, "QUIT TO DESKTOP", func(): get_tree().quit())

	var controls_card := _make_pause_card("FLIGHT CONTROLS")
	controls_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(controls_card)
	var controls := controls_card.get_child(0) as VBoxContainer
	var control_grid := GridContainer.new()
	control_grid.columns = 2
	control_grid.add_theme_constant_override("h_separation", 22)
	control_grid.add_theme_constant_override("v_separation", 10)
	controls.add_child(control_grid)
	for binding in [
		["SELECT", "Left click"],
		["MOVE", "Double left click"],
		["CAMERA", "Hold right click"],
		["ZOOM", "Mouse wheel"],
		["APPROACH", "Q"],
		["ORBIT", "W"],
		["ACTION", "E"],
		["PAUSE", "Esc"],
	]:
		var command := Label.new()
		command.text = binding[0]
		command.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
		control_grid.add_child(command)
		var key := Label.new()
		key.text = binding[1]
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
		control_grid.add_child(key)

	var audio_title := Label.new()
	audio_title.text = "AUDIO"
	audio_title.add_theme_font_size_override("font_size", 15)
	audio_title.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	controls.add_child(audio_title)
	_add_volume_row(
		controls,
		"Music",
		AudioManager.get_music_volume(),
		AudioManager.set_music_volume
	)
	_add_volume_row(
		controls,
		"Game Sound",
		AudioManager.get_sfx_volume(),
		AudioManager.set_sfx_volume
	)

	pause_panel.visible = false
	_create_campaign_manager()


func _make_menu_style(
	background: Color,
	border: Color,
	margin: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style


func _make_pause_card(title_text: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(
		"panel",
		_make_menu_style(Color(0.025, 0.035, 0.06, 0.95), Color(0.0, 0.65, 0.8, 0.3), 20)
	)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	card.add_child(content)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	content.add_child(title)
	return card


func _add_pause_action(
	parent: VBoxContainer,
	label: String,
	action: Callable,
	primary: bool = false
) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 48)
	if primary:
		button.add_theme_color_override("font_color", Color(0.7, 1.0, 1.0))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _add_volume_row(
	parent: VBoxContainer,
	label_text: String,
	initial_value: float,
	setter: Callable
) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value := Label.new()
	value.text = "%d%%" % int(initial_value * 100.0)
	value.custom_minimum_size = Vector2(50, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	slider.value_changed.connect(func(next_value: float) -> void:
		setter.call(next_value)
		value.text = "%d%%" % int(next_value * 100.0)
	)


func _create_campaign_manager() -> void:
	campaign_panel = Panel.new()
	campaign_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	campaign_panel.add_theme_stylebox_override(
		"panel",
		_make_menu_style(Color(0.015, 0.025, 0.045, 0.98), Color(0.0, 0.65, 0.8, 0.3), 0)
	)
	add_child(campaign_panel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	campaign_panel.add_child(center)
	var shell := PanelContainer.new()
	shell.custom_minimum_size = Vector2(1120, 680)
	shell.add_theme_stylebox_override(
		"panel",
		_make_menu_style(Color(0.045, 0.055, 0.085, 0.99), Color(0.0, 0.85, 1.0, 0.55), 24)
	)
	center.add_child(shell)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	shell.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "CAMPAIGNS & CHECKPOINTS"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(120, 40)
	back.pressed.connect(_close_campaign_manager)
	header.add_child(back)
	campaign_status_label = Label.new()
	campaign_status_label.text = ""
	campaign_status_label.add_theme_color_override(
		"font_color",
		Color(0.75, 0.82, 0.9)
	)
	layout.add_child(campaign_status_label)
	campaign_import_button = Button.new()
	campaign_import_button.name = "LegacySaveImportButton"
	campaign_import_button.text = "IMPORT VERSION-2 SAVE"
	campaign_import_button.custom_minimum_size = Vector2(250, 40)
	campaign_import_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	campaign_import_button.pressed.connect(_on_legacy_save_import)
	layout.add_child(campaign_import_button)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	var slots_card := _make_pause_card("CAMPAIGNS - SEPARATE PLAYTHROUGHS")
	slots_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(slots_card)
	campaign_slots_vbox = slots_card.get_child(0) as VBoxContainer
	var manual_card := _make_pause_card("SAVES FOR SELECTED CAMPAIGN")
	manual_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(manual_card)
	campaign_manual_vbox = manual_card.get_child(0) as VBoxContainer

	campaign_confirm_dialog = ConfirmationDialog.new()
	campaign_confirm_dialog.title = "Confirm Campaign Action"
	campaign_confirm_dialog.confirmed.connect(_on_campaign_action_confirmed)
	add_child(campaign_confirm_dialog)
	campaign_panel.visible = false


func _create_campaign_load_fade() -> void:
	campaign_load_fade = ColorRect.new()
	campaign_load_fade.name = "CampaignLoadFade"
	campaign_load_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	campaign_load_fade.color = Color.BLACK
	campaign_load_fade.modulate.a = 0.0
	campaign_load_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	campaign_load_fade.visible = false
	add_child(campaign_load_fade)
	move_child(campaign_load_fade, get_child_count() - 1)


func _open_campaign_manager() -> void:
	GlobalState.paused = true
	pause_panel.visible = false
	campaign_panel.visible = true
	_refresh_campaign_manager()


func _close_campaign_manager() -> void:
	campaign_panel.visible = false
	pause_panel.visible = true


func _refresh_campaign_manager() -> void:
	_refresh_new_campaign_availability()
	_clear_container(campaign_slots_vbox, 1)
	_clear_container(campaign_manual_vbox, 1)
	var game_root := get_tree().current_scene
	if game_root == null or not game_root.has_method("get_campaign_ui_state"):
		campaign_status_label.text = "Campaign controls are unavailable."
		return
	var state: Dictionary = game_root.get_campaign_ui_state()
	if not bool(state.get("ok", false)):
		campaign_status_label.text = str(state.get("error", "Campaign storage is unavailable."))
		return
	var selected_slot_id := str(state.get("selected_slot_id", ""))
	var selected_campaign_name := ""
	var legacy_import: Dictionary = state.get("legacy_import", {})
	campaign_import_button.visible = (
		bool(legacy_import.get("available", false))
		or legacy_import.get("block_code", "") == "slots_full"
	)
	campaign_import_button.disabled = not bool(
		legacy_import.get("available", false)
	)
	campaign_import_button.tooltip_text = str(
		legacy_import.get("message", "")
	)
	campaign_status_label.text = (
		"Selected: %s" % selected_slot_id.replace("_", " ").to_upper()
		if not selected_slot_id.is_empty()
		else "No campaign selected"
	)
	for slot in state.get("slots", []):
		_add_campaign_slot_row(slot, selected_slot_id)
		if str(slot.get("slot_id", "")) == selected_slot_id:
			selected_campaign_name = str(
				slot.get("display_name", "Campaign")
			)
	var manual: Array = state.get("manual", [])
	if selected_slot_id.is_empty():
		var empty_message := Label.new()
		empty_message.text = "Select or create a campaign to manage checkpoints."
		empty_message.autowrap_mode = TextServer.AUTOWRAP_WORD
		campaign_manual_vbox.add_child(empty_message)
	else:
		var help := Label.new()
		help.text = (
			"Continue Point updates automatically at safe places. "
			+ "Backup Copies only change when you replace them."
		)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD
		help.add_theme_color_override(
			"font_color",
			Color(0.72, 0.8, 0.9)
		)
		campaign_manual_vbox.add_child(help)
		_add_autosave_checkpoint_row(
			state.get("autosave", {}),
			selected_slot_id,
			selected_campaign_name
		)
		for slot_index in range(2):
			var entry: Dictionary = (
				manual[slot_index]
				if slot_index < manual.size()
				else {
					"slot_index": slot_index,
					"occupied": false,
				}
			)
			_add_manual_checkpoint_row(entry, selected_campaign_name)


func _add_autosave_checkpoint_row(
	entry: Dictionary,
	selected_slot_id: String,
	campaign_name: String
) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		_make_menu_style(
			Color(0.025, 0.035, 0.06, 0.9),
			Color(0.0, 0.75, 0.85, 0.35),
			12
		)
	)
	campaign_manual_vbox.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var title := Label.new()
	title.text = (
		"\"%s\"  %s" % [
			campaign_name,
			_format_save_timestamp(
				int(entry.get("created_at_unix", 0))
			),
		]
		if bool(entry.get("available", false))
		else "CONTINUE POINT"
	)
	title.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	column.add_child(title)
	var details := Label.new()
	if bool(entry.get("available", false)):
		var location: Dictionary = entry.get("safe_location", {})
		details.text = "Latest safe arrival: %s" % str(
			location.get("type", "safe point")
		).replace("_", " ").capitalize()
	else:
		details.text = "Updates automatically at a station or jumpgate."
	details.add_theme_color_override("font_color", Color(0.7, 0.78, 0.86))
	column.add_child(details)
	var load_button := Button.new()
	load_button.text = "LOAD CONTINUE POINT"
	load_button.disabled = not bool(entry.get("available", false))
	load_button.pressed.connect(
		_on_campaign_continue.bind(selected_slot_id)
	)
	column.add_child(load_button)


func _on_legacy_save_import() -> void:
	var game_root := get_tree().current_scene
	var result: Dictionary = game_root.import_legacy_save()
	campaign_status_label.text = (
		str(result.get("message", "Prototype save imported."))
		if bool(result.get("ok", false))
		else str(
			result.get(
				"error",
				"Import failed. The original save and campaigns were preserved."
			)
		)
	)
	_refresh_campaign_manager()


func _clear_container(
	container: VBoxContainer,
	keep_children: int
) -> void:
	if container == null:
		return
	while container.get_child_count() > keep_children:
		var child := container.get_child(keep_children)
		container.remove_child(child)
		child.queue_free()


func _add_campaign_slot_row(
	slot: Dictionary,
	selected_slot_id: String
) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		_make_menu_style(Color(0.025, 0.035, 0.06, 0.9), Color(0.0, 0.55, 0.7, 0.25), 12)
	)
	campaign_slots_vbox.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var slot_id := str(slot.get("slot_id", ""))
	var occupied := bool(slot.get("occupied", false))
	var heading := Label.new()
	heading.text = "%s%s" % [
		slot_id.replace("slot_0", "SLOT "),
		"  • ACTIVE" if slot_id == selected_slot_id else "",
	]
	heading.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	column.add_child(heading)
	if occupied:
		var campaign_name := Label.new()
		campaign_name.text = str(slot.get("display_name", "Campaign"))
		campaign_name.add_theme_font_size_override("font_size", 20)
		column.add_child(campaign_name)
	var detail := Label.new()
	if occupied:
		var summary: Dictionary = slot.get("checkpoint_summary", {})
		detail.text = "%s  |  %s" % [
			str(summary.get("system_id", "Unknown system")),
			str(summary.get("source_reason", "checkpoint")).replace("_", " "),
		]
	else:
		detail.text = "Empty campaign slot"
	detail.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	column.add_child(detail)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	if occupied:
		var continue_button := Button.new()
		continue_button.text = "CONTINUE"
		continue_button.pressed.connect(
			_on_campaign_continue.bind(slot_id)
		)
		actions.add_child(continue_button)
		var delete_button := Button.new()
		delete_button.text = "DELETE"
		delete_button.pressed.connect(
			_request_campaign_delete.bind(slot_id)
		)
		actions.add_child(delete_button)
	else:
		var available := Label.new()
		available.text = "Available for the next new campaign"
		available.add_theme_color_override(
			"font_color",
			Color(0.65, 0.72, 0.82)
		)
		actions.add_child(available)


func _add_manual_checkpoint_row(
	entry: Dictionary,
	campaign_name: String
) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		_make_menu_style(Color(0.025, 0.035, 0.06, 0.9), Color(0.0, 0.55, 0.7, 0.25), 12)
	)
	campaign_manual_vbox.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var slot_index := int(entry.get("slot_index", 0))
	var occupied := bool(entry.get("occupied", false))
	var title := Label.new()
	title.text = (
		"\"%s\"  %s" % [
			campaign_name,
			_format_save_timestamp(
				int(entry.get("created_at_unix", 0))
			),
		]
		if occupied
		else "BACKUP COPY %d - EMPTY" % (slot_index + 1)
	)
	title.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	column.add_child(title)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	var save_button := Button.new()
	save_button.text = (
		"REPLACE WITH CONTINUE POINT"
		if occupied
		else "COPY CONTINUE POINT HERE"
	)
	save_button.pressed.connect(
		_on_manual_save.bind(slot_index, campaign_name, occupied)
	)
	actions.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "LOAD COPY"
	load_button.disabled = not occupied
	load_button.pressed.connect(_on_manual_load.bind(slot_index))
	actions.add_child(load_button)


func _format_save_timestamp(unix_time: int) -> String:
	if unix_time <= 0:
		return ""
	var date_time := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(date_time.get("year", 0)),
		int(date_time.get("month", 0)),
		int(date_time.get("day", 0)),
		int(date_time.get("hour", 0)),
		int(date_time.get("minute", 0)),
	]


func _on_campaign_create(
	slot_id: String
) -> void:
	var game_root := get_tree().current_scene
	var result: Dictionary = game_root.create_campaign_in_slot(
		slot_id,
		"Pending Campaign"
	)
	campaign_status_label.text = (
		"Campaign created. Its opening story will name it."
		if bool(result.get("ok", false))
		else str(result.get("error", "Campaign creation failed."))
	)
	_refresh_campaign_manager()


func _on_campaign_continue(slot_id: String) -> void:
	if campaign_load_in_progress:
		return
	campaign_load_in_progress = true
	campaign_status_label.text = "Loading campaign..."
	await _fade_campaign_load(1.0)
	var game_root := get_tree().current_scene
	var result: Dictionary = await game_root.select_and_load_campaign(slot_id)
	if bool(result.get("ok", false)):
		campaign_panel.visible = false
		pause_panel.visible = false
		GlobalState.paused = false
		await get_tree().process_frame
		await _fade_campaign_load(0.0)
		campaign_load_in_progress = false
		return
	campaign_status_label.text = (
		str(result.get("error", "Campaign loading failed."))
	)
	await _fade_campaign_load(0.0)
	campaign_load_in_progress = false
	_refresh_campaign_manager()


func _fade_campaign_load(target_alpha: float) -> void:
	if campaign_load_fade == null:
		return
	campaign_load_fade.visible = true
	move_child(campaign_load_fade, get_child_count() - 1)
	var duration := (
		0.01
		if DisplayServer.get_name() == "headless"
		else 0.35
	)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		campaign_load_fade,
		"modulate:a",
		target_alpha,
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN if target_alpha > 0.0 else Tween.EASE_OUT
	)
	await tween.finished
	if target_alpha <= 0.0:
		campaign_load_fade.visible = false


func _on_campaign_rename(
	slot_id: String,
	name_edit: LineEdit
) -> void:
	var game_root := get_tree().current_scene
	var result: Dictionary = game_root.rename_campaign_slot(
		slot_id,
		name_edit.text
	)
	campaign_status_label.text = (
		"Campaign renamed."
		if bool(result.get("ok", false))
		else str(result.get("error", "Campaign rename failed."))
	)
	_refresh_campaign_manager()


func _request_campaign_delete(slot_id: String) -> void:
	pending_delete_slot_id = slot_id
	pending_manual_slot_index = -1
	var game_root := get_tree().current_scene
	var deleting_active := game_root != null \
		and str(game_root.get("active_campaign_slot_id")) == slot_id
	campaign_confirm_dialog.dialog_text = (
		(
			"Delete the campaign you are currently playing? "
			+ "This ends the current session and deletes all of its saves. "
			+ "This cannot be undone."
		)
		if deleting_active
		else (
			"Delete this campaign and all of its checkpoints? "
			+ "This cannot be undone."
		)
	)
	campaign_confirm_dialog.popup_centered()


func _on_manual_save(
	slot_index: int,
	campaign_name: String,
	occupied: bool
) -> void:
	if occupied:
		pending_delete_slot_id = ""
		pending_manual_slot_index = slot_index
		pending_manual_name = campaign_name
		campaign_confirm_dialog.dialog_text = (
			"Replace Backup Copy %d with the current Continue Point?" %
				(slot_index + 1)
		)
		campaign_confirm_dialog.popup_centered()
		return
	_commit_manual_save(slot_index, campaign_name, false)


func _commit_manual_save(
	slot_index: int,
	display_name: String,
	overwrite: bool
) -> void:
	var game_root := get_tree().current_scene
	var result: Dictionary = game_root.request_manual_checkpoint(
		slot_index,
		display_name,
		overwrite
	)
	campaign_status_label.text = (
		"Continue Point copied to the backup."
		if bool(result.get("ok", false))
		else str(result.get("error", "Backup copy failed."))
	)
	_refresh_campaign_manager()


func _on_manual_rename(
	slot_index: int,
	name_edit: LineEdit
) -> void:
	var game_root := get_tree().current_scene
	var result: Dictionary = game_root.rename_manual_checkpoint(
		slot_index,
		name_edit.text
	)
	campaign_status_label.text = (
		"Backup copy renamed."
		if bool(result.get("ok", false))
		else str(result.get("error", "Backup rename failed."))
	)
	_refresh_campaign_manager()


func _on_manual_load(slot_index: int) -> void:
	var game_root := get_tree().current_scene
	var loaded: bool = await game_root.load_manual_checkpoint(slot_index)
	campaign_status_label.text = (
		"Backup copy loaded."
		if loaded
		else "Backup copy could not be loaded."
	)
	_refresh_campaign_manager()


func _on_campaign_action_confirmed() -> void:
	var game_root := get_tree().current_scene
	if not pending_delete_slot_id.is_empty():
		var deleted_slot_id := pending_delete_slot_id
		var deleting_active := game_root != null \
			and str(game_root.get("active_campaign_slot_id")) \
				== deleted_slot_id
		if deleting_active:
			await _fade_campaign_load(1.0)
		var result: Dictionary = game_root.delete_campaign_slot(
			deleted_slot_id
		)
		if bool(result.get("ok", false)) \
				and bool(result.get("deleted_active_campaign", false)):
			pending_delete_slot_id = ""
			pending_manual_slot_index = -1
			pending_manual_name = ""
			game_root.call(
				"reset_after_active_campaign_deleted",
				deleted_slot_id
			)
			return
		campaign_status_label.text = (
			"Campaign deleted."
			if bool(result.get("ok", false))
			else str(result.get("error", "Campaign deletion failed."))
		)
		if deleting_active:
			await _fade_campaign_load(0.0)
	elif pending_manual_slot_index >= 0:
		_commit_manual_save(
			pending_manual_slot_index,
			pending_manual_name,
			true
		)
	pending_delete_slot_id = ""
	pending_manual_slot_index = -1
	pending_manual_name = ""
	_refresh_campaign_manager()

func _create_death_screen():
	death_panel = Panel.new()
	add_child(death_panel)
	death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_panel.offset_left = 0
	death_panel.offset_right = 0
	death_panel.offset_top = 0
	death_panel.offset_bottom = 0
	
	death_panel.add_theme_stylebox_override(
		"panel",
		_make_menu_style(
			Color(0.01, 0.015, 0.03, 0.96),
			Color(0.8, 0.12, 0.18, 0.35),
			0
		)
	)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_panel.add_child(center)
	var shell := PanelContainer.new()
	shell.custom_minimum_size = Vector2(480, 390)
	shell.add_theme_stylebox_override(
		"panel",
		_make_menu_style(
			Color(0.045, 0.035, 0.055, 0.99),
			Color(0.9, 0.18, 0.22, 0.65),
			34
		)
	)
	center.add_child(shell)
	var vbox := VBoxContainer.new()
	shell.add_child(vbox)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	
	var msg = Label.new()
	msg.text = "SHIP DESTROYED"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 36)
	msg.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	vbox.add_child(msg)
	
	var sub = Label.new()
	sub.text = "Your ship has been reduced to wreckage."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(sub)
	
	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(btn_spacer)
	
	var restart_btn = Button.new()
	restart_btn.name = "LoadLastSaveButton"
	restart_btn.text = "Load Last Save"
	restart_btn.custom_minimum_size = Vector2(220, 42)
	restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_btn.pressed.connect(_load_last_save_after_death)

	vbox.add_child(restart_btn)
	
	var gap = Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(gap)

	var new_campaign_btn = Button.new()
	new_campaign_btn.name = "StartNewCampaignButton"
	new_campaign_btn.text = "Start New Campaign"
	new_campaign_btn.custom_minimum_size = Vector2(220, 42)
	new_campaign_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	new_campaign_btn.pressed.connect(_start_new_campaign_after_death)
	var game_root := get_tree().current_scene
	if game_root and game_root.has_method("can_start_new_campaign"):
		new_campaign_btn.disabled = not bool(
			game_root.call("can_start_new_campaign")
		)
		if new_campaign_btn.disabled:
			new_campaign_btn.tooltip_text = (
				"Delete a campaign before starting another."
			)
	vbox.add_child(new_campaign_btn)

	var quit_gap = Control.new()
	quit_gap.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(quit_gap)
	
	var quit_btn = Button.new()
	quit_btn.name = "QuitAfterDeathButton"
	quit_btn.text = "Quit Game"
	quit_btn.custom_minimum_size = Vector2(220, 0)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_btn)
	
	death_panel.visible = false


func _load_last_save_after_death() -> void:
	var game_root := get_tree().current_scene
	if game_root \
			and game_root.has_method(
				"restore_latest_campaign_checkpoint_after_death"
			) \
			and bool(
				game_root.call(
					"restore_latest_campaign_checkpoint_after_death"
				)
			):
		return
	show_hud_warning("No living campaign checkpoint is available.")


func _start_new_campaign_after_death() -> void:
	_start_new_campaign()


func _start_new_campaign() -> void:
	var game_root := get_tree().current_scene
	if game_root and game_root.has_method("start_new_campaign_after_death"):
		game_root.call("start_new_campaign_after_death")


func _refresh_new_campaign_availability() -> void:
	if pause_new_campaign_button == null:
		return
	var game_root := get_tree().current_scene
	var available := game_root != null \
		and game_root.has_method("can_start_new_campaign") \
		and bool(game_root.call("can_start_new_campaign"))
	pause_new_campaign_button.disabled = not available
	pause_new_campaign_button.tooltip_text = (
		""
		if available
		else "Delete a campaign before starting another."
	)


func _restart_game():
	var game_root := get_tree().current_scene
	if game_root and game_root.has_method("delete_savegame"):
		game_root.delete_savegame()
	# Reset all autoload state BEFORE reloading — prevents dangling callbacks
	# (e.g. LLMInterface firing into a freed UIManager) from crashing the new session
	LLMInterface.reset_for_restart()
	QuestManager.reset_for_restart()
	GlobalState.reset_for_restart()
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("pause_game"):
		if loading_panel and is_instance_valid(loading_panel):
			return
		if branch_map and branch_map.visible:
			branch_map._close()
			_auto_select_route_gate()
			return
		if campaign_panel and campaign_panel.visible:
			_close_campaign_manager()
			return
		GlobalState.paused = not GlobalState.paused


# Overview list population
func update_overview_list(entities: Array):
	# Clear old list
	for child in overview_list.get_children():
		child.queue_free()
		
	var filtered_entities = entities
	if overview_collapsed:
		filtered_entities = []
		var active = GlobalState.active_target
		if active and is_instance_valid(active) and active in entities:
			filtered_entities.append(active)
		
	for entity in filtered_entities:
		if entity and is_instance_valid(entity) and entity != GlobalState.player \
				and not _is_hidden_gate(entity):
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(0, 30)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(func(): GlobalState.active_target = entity)
			btn.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
					btn.accept_event()
					show_context_menu(entity)
			)
			overview_list.add_child(btn)
			
			# HBox inside the button for spreadsheet column layout
			var hbox = HBoxContainer.new()
			btn.add_child(hbox)
			hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
			hbox.offset_left = 0
			hbox.offset_right = 0
			hbox.offset_top = 0
			hbox.offset_bottom = 0
			hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			var name_lbl = Label.new()
			var label_text = entity.get("display_name") if entity.get("display_name") else entity.name
			name_lbl.text = "  " + label_text # Add a little padding space
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			name_lbl.clip_text = true
			hbox.add_child(name_lbl)
			
			var dist_lbl = Label.new()
			dist_lbl.text = "  0m"
			dist_lbl.custom_minimum_size = Vector2(110, 0)
			dist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			dist_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(dist_lbl)
			
			var type_lbl = Label.new()
			var type_str = "Celestial"
			if entity.is_in_group("asteroid"):
				type_str = "Asteroid"
			elif entity.is_in_group("jumpgate"):
				var gate_state: String = entity.get("knowledge_state") if entity.get("knowledge_state") else "known"
				match gate_state:
					"hidden": type_str = "Unknown Gate"
					"blocked": type_str = "Locked Gate"
					"damaged": type_str = "Damaged Gate"
					_: type_str = "Jumpgate"
			elif entity.is_in_group("station"):
				# Outposts show as "Outpost" so the player can tell them apart
				# from the main system space station. station_type defaults to
				# "full_service" on Station.gd, so unspecified stations stay as
				# "Space Station".
				var stype = entity.get("station_type") if entity.get("station_type") else "full_service"
				if stype == "outpost":
					type_str = "Outpost"
				else:
					type_str = "Space Station"
			elif entity.is_in_group("ship"):
				var ship_name_upper = entity.name.to_upper()
				var faction_str = entity.get("faction")
				var faction_upper = faction_str.to_upper() if faction_str else ""
				# Derive ship class from its name — already contains Patrol/Raider/Sentinel etc.
				if "PATROL" in ship_name_upper:
					type_str = faction_upper.capitalize() + " Patrol"
				elif "RAIDER" in ship_name_upper:
					type_str = faction_upper.capitalize() + " Raider"
				elif "SENTINEL" in ship_name_upper:
					type_str = faction_upper.capitalize() + " Sentinel"
				elif "HAULER" in ship_name_upper or "SALVAGER" in ship_name_upper:
					type_str = "Independent Hauler"
				elif "INTERCEPTOR" in ship_name_upper:
					type_str = faction_upper.capitalize() + " Interceptor"
				elif "GUNSHIP" in ship_name_upper:
					type_str = faction_upper.capitalize() + " Gunship"
				else:
					type_str = faction_upper.capitalize() + " Combat Vessel"
			elif entity.is_in_group("wreckage"):
				type_str = "Wreckage"
			
			type_lbl.text = "  " + type_str
			type_lbl.custom_minimum_size = Vector2(160, 0)
			type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			type_lbl.clip_text = true
			hbox.add_child(type_lbl)
			
			# Row text colour by entity class
			# Green = dockable (Space Station / Outpost and future dockables)
			# Blue  = celestial bodies (planets, gas giants, etc.)
			var row_color: Color
			if type_str == "Space Station" or type_str == "Outpost":
				row_color = Color(0.25, 0.95, 0.45)   # Bright docking green
			elif type_str == "Jumpgate":
				var next_hop: String = branch_map.get_next_hop_legacy_id() if branch_map else ""
				var gate_dest: String = entity.get("destination_system_id") if entity.get("destination_system_id") else ""
				if next_hop != "" and gate_dest == next_hop:
					row_color = Color(0.2, 1.0, 0.4)
				else:
					row_color = Color(0.2, 0.85, 1.0)
			elif type_str == "Celestial":
				row_color = Color(0.35, 0.65, 1.0)    # Soft celestial blue
			else:
				row_color = Color(1.0, 1.0, 1.0)      # Default white for ships, wreckage etc.
			if row_color != Color(1.0, 1.0, 1.0):
				name_lbl.add_theme_color_override("font_color", row_color)
				dist_lbl.add_theme_color_override("font_color", row_color)
				type_lbl.add_theme_color_override("font_color", row_color)
			
			# Meta parameters for sorting and updating
			btn.set_meta("entity_ref", entity)
			btn.set_meta("entity_name", entity.name)
			btn.set_meta("type_str", type_str)
			btn.set_meta("distance_val", 0.0) # Updated dynamically in _update_overview_distances
			btn.set_meta("dist_label_ref", dist_lbl)
			btn.set_meta("name_label_ref", name_lbl)


func _update_overview_distances(delta: float = 999.0):
	if not GlobalState.player or not is_instance_valid(GlobalState.player): return
	var p_pos = GlobalState.player.global_position
	
	# Check if any NPC ship is targeting the player
	var player_targeted = false
	for entity in GlobalState.active_system_entities:
		if entity and is_instance_valid(entity) and not entity.get("destroyed"):
			if entity.is_in_group("ship") and entity.get("target") == GlobalState.player:
				player_targeted = true
				break
				
	if player_targeted and overview_collapsed:
		set_overview_collapsed(false)
		
	# Update all distances first
	for btn in overview_list.get_children():
		if btn is Button:
			var entity = btn.get_meta("entity_ref")
			if entity and is_instance_valid(entity):
				var dist = p_pos.distance_to(entity.global_position)
				btn.set_meta("distance_val", dist)
				var dist_lbl = btn.get_meta("dist_label_ref")
				if is_instance_valid(dist_lbl):
					dist_lbl.text = "  " + str(int(dist)) + "m"
				
				# Update label color if attacking player
				var name_lbl = btn.get_meta("name_label_ref")
				if is_instance_valid(name_lbl):
					if entity.is_in_group("ship") and entity.get("target") == GlobalState.player:
						name_lbl.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
					else:
						name_lbl.remove_theme_color_override("font_color")
						
				# Highlight selected object in overview spreadsheet
				if GlobalState.active_target == entity:
					btn.self_modulate = Color(1.0, 1.0, 1.0, 1.0) # Reset modulate to avoid tint conflicts
					btn.add_theme_stylebox_override("normal", selected_row_style)
					btn.add_theme_stylebox_override("hover", selected_row_style)
					btn.add_theme_stylebox_override("pressed", selected_row_style)
					btn.add_theme_stylebox_override("focus", selected_row_style)
				else:
					btn.self_modulate = Color(1.0, 1.0, 1.0, 1.0)
					btn.remove_theme_stylebox_override("normal")
					btn.remove_theme_stylebox_override("hover")
					btn.remove_theme_stylebox_override("pressed")
					btn.remove_theme_stylebox_override("focus")
			else:
				btn.queue_free()
				
	# Periodically sort the children list to prevent layout thrashing
	sort_timer += delta
	if sort_timer >= SORT_INTERVAL:
		sort_timer = 0.0
		_sort_overview_list()

func _sort_overview_list():
	var children = overview_list.get_children()
	children.sort_custom(func(a, b):
		if sort_column == "name":
			var name_a = a.get_meta("entity_name").to_lower()
			var name_b = b.get_meta("entity_name").to_lower()
			if name_a != name_b:
				return name_a < name_b if sort_ascending else name_a > name_b
			return a.get_instance_id() < b.get_instance_id()
		elif sort_column == "type":
			var type_a = a.get_meta("type_str").to_lower()
			var type_b = b.get_meta("type_str").to_lower()
			if type_a != type_b:
				return type_a < type_b if sort_ascending else type_a > type_b
			# Tie breaker: sort by name, then instance ID
			var name_a = a.get_meta("entity_name").to_lower()
			var name_b = b.get_meta("entity_name").to_lower()
			if name_a != name_b:
				return name_a < name_b
			return a.get_instance_id() < b.get_instance_id()
		else: # distance
			var dist_a = a.get_meta("distance_val")
			var dist_b = b.get_meta("distance_val")
			if abs(dist_a - dist_b) > 0.001:
				return dist_a < dist_b if sort_ascending else dist_a > dist_b
			# Tie breaker: sort by name, then instance ID
			var name_a = a.get_meta("entity_name").to_lower()
			var name_b = b.get_meta("entity_name").to_lower()
			if name_a != name_b:
				return name_a < name_b
			return a.get_instance_id() < b.get_instance_id()
	)
	
	# Apply sorted order
	for i in range(children.size()):
		overview_list.move_child(children[i], i)

# Target signal callbacks
func _on_target_changed(new_target: Node3D):
	if new_target and is_instance_valid(new_target):
		target_panel.visible = true
		var type_str = "Object"
		var icon_index = 0 # Default to ship icon
		
		if new_target.is_in_group("asteroid"):
			type_str = "Asteroid"
			icon_index = 1
		elif new_target.is_in_group("station"):
			type_str = "Station"
			icon_index = 2
		elif new_target.is_in_group("jumpgate"):
			var gate_state: String = new_target.get("knowledge_state") if new_target.get("knowledge_state") else "known"
			match gate_state:
				"hidden": type_str = "Unknown Gate — Scan Required"
				"blocked": type_str = "Locked Gate — Access Denied"
				"damaged": type_str = "Damaged Gate — Repair Required"
				_: type_str = "Jumpgate to " + str(new_target.get("destination_display_name"))
			icon_index = 3
		elif new_target.is_in_group("ship"):
			type_str = "Hostile NPCShip"
			icon_index = 0
		elif new_target.is_in_group("wreckage"):
			type_str = "Wreckage"
			icon_index = 4
		elif new_target.is_in_group("celestial"):
			type_str = "Planet"
			icon_index = 3
			
		var target_name = new_target.get("display_name") if new_target.get("display_name") else new_target.name
		target_label.text = target_name + " [" + type_str + "]"
		
		# Set target icon
		if target_icon and icons_sheet:
			var atlas = AtlasTexture.new()
			atlas.atlas = icons_sheet
			
			var col = icon_index % 4
			var row = icon_index / 4
			atlas.region = Rect2(col * 384, row * 512, 384, 512)
			target_icon.texture = atlas
			target_icon.visible = true
			
		if target_action_btn:
			if new_target.is_in_group("asteroid"):
				target_action_btn.text = "Mine Asteroid"
				target_action_btn.visible = true
			elif new_target.is_in_group("station"):
				target_action_btn.text = "Dock at Station"
				target_action_btn.visible = true
			elif new_target.is_in_group("jumpgate"):
				target_action_btn.text = _gate_action_label(new_target)
				target_action_btn.visible = true
			elif new_target.is_in_group("ship"):
				target_action_btn.text = "Attack Hostile"
				target_action_btn.visible = true
			else:
				target_action_btn.visible = false
	else:
		target_panel.visible = false
		target_label.text = "No Target Selected"
		if target_icon:
			target_icon.visible = false
		
	_update_target_command_feedback()
	if overview_collapsed:
		refresh_overview()

func _on_target_icon_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		accept_event()
		var t = GlobalState.active_target
		if t and is_instance_valid(t):
			show_context_menu(t)

func _on_credits_changed(new_credits: int):
	if credits_label:
		credits_label.text = "Credits: " + str(new_credits) + " SC"


func _on_campaign_time_changed(_total_minutes: int) -> void:
	if time_label:
		time_label.text = "Time: %s" % CampaignClock.formatted_datetime()
	if QuestManager.is_active_quest_timed():
		_update_quest_tracker()

func _on_cargo_changed(new_cargo: float):
	if cargo_label and cargo_bar:
		cargo_label.text = "Cargo: " + GlobalState.cargo_display_text()
		cargo_bar.max_value = GlobalState.cargo_max
		# Bar visual: ore fill when carrying ore, "full" when carrying a
		# special item (so the player sees something is loaded), 0 when empty.
		match GlobalState.cargo_type:
			GlobalState.CargoType.ORE:
				cargo_bar.value = new_cargo
			GlobalState.CargoType.SPECIAL:
				cargo_bar.value = GlobalState.cargo_max
			_:
				cargo_bar.value = 0.0

		# Play audio warning when ore cargo reaches max capacity
		if GlobalState.cargo_type == GlobalState.CargoType.ORE and new_cargo >= GlobalState.cargo_max:
			AudioManager.play_cargo_full()

		_update_quest_tracker()

func _on_pause_changed(is_paused: bool):
	if pause_panel:
		if is_paused and loading_panel and is_instance_valid(loading_panel):
			pause_panel.visible = false
		else:
			pause_panel.visible = is_paused
			if is_paused:
				move_child(pause_panel, -1)
	if not is_paused and campaign_panel:
		campaign_panel.visible = false

# Station services methods
func toggle_dock_menu(
	station: Node3D,
	create_checkpoint: bool = true
):
	current_station = station
	if dock_panel.visible or agent_panel.visible \
			or (public_board_panel and public_board_panel.visible) \
			or (store_panel and store_panel.visible) \
			or (inventory_panel and inventory_panel.visible):
		SpeechService.stop()
		dock_panel.visible = false
		agent_panel.visible = false
		if public_board_panel:
			public_board_panel.visible = false
		if store_panel:
			store_panel.visible = false
		if inventory_panel:
			inventory_panel.visible = false
		if GlobalState.player:
			GlobalState.player.is_docked = false
	else:
		dock_panel.visible = true
		# Collapse overview while docked — station UI takes priority
		set_overview_collapsed(true)

		# Every dock opens on the SERVICES submenu. The maintenance bay is a
		# second submenu the player enters via the Maintenance Bay button.
		current_submenu = DockSubmenu.SERVICES

		# Dock label uses the station's display_name when available, falling
		# back to a generic header per station type.
		var stype = station.get("station_type") if station else "full_service"
		var is_outpost = (stype == "outpost")
		var sname = station.get("display_name") if station and station.get("display_name") else ""
		if is_outpost:
			dock_label.text = sname if sname != "" else "OUTPOST SERVICES"
		else:
			dock_label.text = sname if sname != "" else "STATION SERVICES"

		_render_dock_submenu()

		if GlobalState.player:
			GlobalState.player.is_docked = true
			GlobalState.player.velocity = Vector3.ZERO
		var game_root := get_tree().current_scene
		if create_checkpoint \
				and game_root \
				and game_root.has_method("request_safe_checkpoint"):
			game_root.call_deferred(
				"request_safe_checkpoint",
				"dock",
				station
			)

		# Pre-cache quests when at a non-outpost station (main station today;
		# outposts are still visual-only and don't talk to Kaelen).
		if not is_outpost and not QuestManager.is_lane_occupied("AGENT") and cached_quest_data.is_empty():
			print("[TRACE] [UIManager] Player docked. Pre-caching agent quest in the background.")
			_request_background_agent_quest()

		# Pre-cache this outpost's NPC flavor lines for TTS so the
		# first Hear Gossip click plays instantly in each NPC's
		# unique voice. Background — does not block the dock UI.
		# Refresh-on-use (when a line is played from cache-miss
		# path) re-warms the remaining lines for that NPC.
		var docked_outpost_id_for_precache: String = OUTPOST_NODE_TO_ID.get(station.name, "") if station else ""
		if docked_outpost_id_for_precache == "" and station:
			docked_outpost_id_for_precache = GlobalState.resolve_outpost_id(station)
		if is_outpost and docked_outpost_id_for_precache != "":
			var outpost_id: String = docked_outpost_id_for_precache
			var prev_count: int = int(_outpost_flavor_precached.get(outpost_id, 0))
			print("[TRACE] [UIManager] Pre-caching TTS for outpost '", outpost_id, "' flavor lines (", prev_count, " pre-warmed this session).")
			var flavor_lines: Array = GlobalState.get_outpost_flavor_tts_lines(outpost_id)
			for entry in flavor_lines:
				# Pass clean_text + per-NPC voice + speed. cache_dialogue_audio
				# will dedupe via the "<voice>|<text>" cache key, so
				# the dock-time pre-cache and the refresh-on-use
				# paths both no-op on already-cached lines.
				SpeechService.cache(entry["line"], entry["voice_profile_id"])
			_outpost_flavor_precached[outpost_id] = prev_count + flavor_lines.size()

		# Pre-cache Jenna's (mechanic) personalized greeting when the player
		# docks at the main station (Grease Monkeys). Runs in the background;
		# by the time the player clicks "Maintenance Bay" the chat box has
		# text. Falls back to a canned line if the LLM is slow / offline.
		if not is_outpost:
			_cache_mechanic_intro()


# Render the current submenu's button set. Called on dock AND when the
# player clicks between Services and Maintenance. The Grease Monkeys
# hangar image shows only while the maintenance submenu is active.
func _render_dock_submenu() -> void:
	# Clear any active docked message so a flavor line from the
	# previous submenu doesn't bleed into the new one.
	clear_dock_message()
	if ore_trade_popup and is_instance_valid(ore_trade_popup):
		ore_trade_popup.visible = false
	# Outposts are remote stations with no sell/agent/maintenance. Only the
	# dock actions that make sense there (test pickup, hear gossip) plus
	# undock should appear in the services submenu.
	var is_outpost: bool = current_station != null \
		and is_instance_valid(current_station) \
		and current_station.get("station_type") == "outpost"

	if current_submenu == DockSubmenu.MAINTENANCE:
		dock_label.text = "GREASE MONKEYS — MAINTENANCE BAY"
		# Maintenance submenu: hide services + entry button, show repair +
		# upgrades + back button. The hangar background stays on.
		sell_btn.visible = false
		agent_service_btn.visible = false
		public_board_btn.visible = false
		maintenance_bay_btn.visible = false
		inventory_btn.visible = false
		ship_upgrades_btn.visible = true
		repair_btn.visible = true
		test_pickup_btn.visible = DEBUG_TESTS
		test_deliver_btn.visible = DEBUG_TESTS
		test_pickup_part_btn.visible = false
		hear_gossip_btn.visible = false
		ask_for_part_btn.visible = false
		_render_station_contacts(false)
		
		var station_quest: Dictionary = QuestManager.get_pickup_special_data()
		var can_deliver: bool = not station_quest.is_empty() and station_quest.get("picked_up", false)
		deliver_part_btn.visible = can_deliver
		
		back_to_services_btn.visible = true
		if dock_background:
			if dock_background.texture == null:
				dock_background.texture = load("res://assets/RepairShop.png")
			dock_background.visible = true
		# Mechanic intro panel: portrait + personalized greeting for the
		# current visit. Hidden at outposts (no mechanic) and on services
		# submenu (gossip slot takes that space). _render_mechanic_intro
		# pulls from cache if the LLM has returned, else picks a fallback
		# immediately so the chat box is never empty.
		if not is_outpost:
			_render_mechanic_intro()
		else:
			if mechanic_intro_panel and is_instance_valid(mechanic_intro_panel):
				mechanic_intro_panel.visible = false
	else:
		# Services submenu (default): at a full-service station, show
		# sell/agent/maintenance entry. At an outpost, show only the
		# outpost-specific actions (test pickup, hear gossip when added)
		# and hide the rest.
		sell_btn.visible = not is_outpost
		agent_service_btn.visible = not is_outpost
		public_board_btn.visible = not is_outpost
		maintenance_bay_btn.visible = not is_outpost
		inventory_btn.visible = true
		ship_upgrades_btn.visible = false
		repair_btn.visible = false
		test_pickup_btn.visible = false
		test_deliver_btn.visible = false
		deliver_part_btn.visible = false
		
		var show_ask_btn: bool = false
		var station_quest_svc: Dictionary = QuestManager.get_pickup_special_data()
		if is_outpost and not station_quest_svc.is_empty() \
				and not station_quest_svc.get("picked_up", false):
			var docked_outpost_id_for_btn: String = OUTPOST_NODE_TO_ID.get(current_station.name, "") if current_station else ""
			if docked_outpost_id_for_btn == "" and current_station:
				docked_outpost_id_for_btn = GlobalState.resolve_outpost_id(current_station)
			if docked_outpost_id_for_btn != "" and docked_outpost_id_for_btn == station_quest_svc.get("target_outpost", ""):
				show_ask_btn = true
		ask_for_part_btn.visible = show_ask_btn
		
		if show_ask_btn:
			var part_name: String = str(QuestManager.active_quest.get("part_name", "the part"))
			var npc_name: String = str(QuestManager.active_quest.get("target_npc", "the contact"))
			ask_for_part_btn.disabled = false
			if GlobalState.cargo_type == GlobalState.CargoType.ORE and GlobalState.cargo > 0.0:
				var rate: float = GlobalState.buyback_price_per_m3()
				var payout: int = int(round(GlobalState.cargo * rate))
				ask_for_part_btn.text = "Trade Ore for %s (%d m³ → %d SC)" % [part_name, int(GlobalState.cargo), payout]
			else:
				ask_for_part_btn.text = "Ask %s for %s" % [npc_name, part_name]
		
		test_pickup_part_btn.visible = DEBUG_TESTS and is_outpost
		hear_gossip_btn.visible = is_outpost
		back_to_services_btn.visible = false
		_render_station_contacts(true)
		if dock_background:
			dock_background.visible = false
		# Mechanic intro belongs only on the maintenance submenu. On
		# services the dock_message_slot (gossip / quest responses)
		# takes that space — keep them mutually exclusive.
		if mechanic_intro_panel and is_instance_valid(mechanic_intro_panel):
			mechanic_intro_panel.visible = false

	_update_repair_button()


func _render_station_contacts(should_show: bool) -> void:
	if station_contacts_panel == null or station_contacts_list == null:
		return
	for child in station_contacts_list.get_children():
		child.queue_free()
	if not should_show:
		station_contacts_panel.visible = false
		return
	var station_id := _current_station_contact_id()
	if station_id.is_empty():
		station_contacts_panel.visible = false
		return
	var contacts: Array = GlobalState.get_minor_npcs_at_outpost(station_id)
	if contacts.is_empty():
		station_contacts_panel.visible = false
		return
	station_contacts_panel.visible = true
	var title := Label.new()
	title.text = "Station Contacts"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
	station_contacts_list.add_child(title)
	for npc_name in contacts:
		var npc_data := GlobalState.get_minor_npc_data(str(npc_name))
		var role := str(npc_data.get("role", "Local contact"))
		var faction := str(npc_data.get("faction", ""))
		var faction_label := ""
		if not faction.is_empty():
			faction_label = " - %s" % str(
				GlobalState.faction_info(faction).get("name", faction.capitalize())
			)
		var btn := Button.new()
		btn.text = "%s  [%s%s]" % [str(npc_name), role, faction_label]
		btn.tooltip_text = "Hear what this station contact has to say."
		btn.pressed.connect(_on_station_contact_pressed.bind(str(npc_name)))
		station_contacts_list.add_child(btn)


func _current_station_contact_id() -> String:
	if current_station == null or not is_instance_valid(current_station):
		return ""
	var station_id: String = OUTPOST_NODE_TO_ID.get(current_station.name, "")
	if station_id.is_empty():
		station_id = GlobalState.resolve_outpost_id(current_station)
	if station_id.is_empty():
		var raw_world_id: Variant = current_station.get("world_id")
		station_id = str(raw_world_id) if raw_world_id != null else ""
	if station_id.is_empty() or station_id == "<null>":
		station_id = str(current_station.get_meta("world_id", ""))
	return station_id


func _on_station_contact_pressed(npc_name: String) -> void:
	var npc_data := GlobalState.get_minor_npc_data(npc_name)
	if npc_data.is_empty():
		show_hud_warning("That contact is unavailable.")
		return
	var lines: Array = npc_data.get("flavor_lines", [])
	if lines.is_empty():
		show_hud_warning("%s has nothing to say right now." % npc_name)
		return
	var line := str(lines[randi() % lines.size()])
	var color: Color = npc_data.get("flavor_color", Color.WHITE)
	var portrait: Texture2D = GlobalState.get_minor_npc_portrait(npc_name)
	show_dock_message(line, npc_name, color, portrait)
	GlobalState.emit_npc_flavor({
		"npc_name": npc_name,
		"line": line,
		"color": color,
		"voice_profile_id": str(npc_data.get("voice_profile_id", "voice.neutral.v1")),
	})


func _request_background_agent_quest() -> void:
	var profile := _current_station_agent_profile()
	if profile.is_empty():
		QuestManager.request_new_quest("neutral", _on_background_quest_generated)
		return
	var profile_faction := str(profile.get("faction", ""))
	var profile_faction_id := str(profile.get("faction_id", ""))
	var faction_arg := (
		profile_faction_id
		if profile_faction.begins_with("gen_") and not profile_faction_id.is_empty()
		else profile_faction
	)
	QuestManager.request_new_quest(
		faction_arg if not faction_arg.is_empty() else "neutral",
		_on_background_quest_generated,
		profile
	)


func _current_station_agent_profile() -> Dictionary:
	var station_id := _current_station_contact_id()
	if station_id.is_empty():
		return {}
	var contacts: Array = GlobalState.get_minor_npcs_at_outpost(station_id)
	for npc_name in contacts:
		var npc_data := GlobalState.get_minor_npc_data(str(npc_name))
		if str(npc_data.get("role", "")) != "Faction contact":
			continue
		var faction := str(npc_data.get("faction", ""))
		var faction_id := str(npc_data.get("faction_id", ""))
		if faction.is_empty() and faction_id.is_empty():
			continue
		var faction_info := GlobalState.faction_info(
			faction if not faction.is_empty() else faction_id
		)
		var faction_display := str(
			faction_info.get("name", faction.capitalize())
		)
		return {
			"agent_name": str(npc_name),
			"agent_role": "%s Station Contact" % faction_display,
			"faction": faction,
			"faction_id": faction_id,
			"faction_display": faction_display,
		}
	return {}


func _on_maintenance_bay_pressed() -> void:
	SpeechService.stop()
	current_submenu = DockSubmenu.MAINTENANCE
	_render_dock_submenu()


func _on_back_to_services_pressed() -> void:
	SpeechService.stop()
	current_submenu = DockSubmenu.SERVICES
	_render_dock_submenu()


func _on_public_board_pressed() -> void:
	SpeechService.stop()
	_render_public_board_offers()
	dock_panel.visible = false
	agent_panel.visible = false
	if store_panel:
		store_panel.visible = false
	if inventory_panel:
		inventory_panel.visible = false
	public_board_panel.visible = true


func _on_public_board_back_pressed() -> void:
	public_board_panel.visible = false
	dock_panel.visible = true
	_render_dock_submenu()


func _on_store_pressed() -> void:
	SpeechService.stop()
	agent_panel.visible = false
	if public_board_panel:
		public_board_panel.visible = false
	if inventory_panel:
		inventory_panel.visible = false
	var station_id := GlobalState.current_system_id
	var reg = StoreRegistryScript.shared()
	var stores = reg.get_stores_for_station(station_id)
	if stores.is_empty():
		stores = reg.get_stores_for_station("haven")
	if stores.is_empty():
		return
	_store_current_id = stores[0].store_id
	_render_store_items()
	dock_panel.visible = false
	store_panel.visible = true


func _on_store_back_pressed() -> void:
	store_panel.visible = false
	dock_panel.visible = true
	_render_dock_submenu()


func _on_inventory_pressed() -> void:
	SpeechService.stop()
	if inventory_panel and inventory_panel.visible:
		inventory_panel.visible = false
		if inventory_return_to_dock:
			dock_panel.visible = true
			_render_dock_submenu()
		inventory_return_to_dock = false
		return
	inventory_return_to_dock = dock_panel != null and dock_panel.visible
	agent_panel.visible = false
	if public_board_panel:
		public_board_panel.visible = false
	if store_panel:
		store_panel.visible = false
	_render_inventory_items()
	dock_panel.visible = false
	inventory_panel.visible = true


func _on_inventory_back_pressed() -> void:
	inventory_panel.visible = false
	if inventory_return_to_dock:
		dock_panel.visible = true
		_render_dock_submenu()
	inventory_return_to_dock = false


func _render_inventory_items() -> void:
	for child in inventory_list.get_children():
		child.queue_free()
	inventory_summary_label.text = "Credits: %d SC    Banked Ore: %.1f / %.1f m3" % [
		GlobalState.player_credits,
		GlobalState.player_storage_ore,
		GlobalState.player_storage_max,
	]
	inventory_list.add_child(_build_inventory_section_label("Cargo Hold"))
	inventory_list.add_child(_build_inventory_cargo_row())
	var items: Dictionary = GlobalState.inventory.get_all()
	inventory_list.add_child(_build_inventory_section_label("Owned Items"))
	if items.is_empty():
		var empty := Label.new()
		empty.text = "No stored items yet."
		empty.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
		inventory_list.add_child(empty)
		return
	var keys := items.keys()
	keys.sort()
	var reg = StoreRegistryScript.shared()
	for item_id in keys:
		var quantity := int(items[item_id])
		if quantity <= 0:
			continue
		var item_def = reg.get_item(str(item_id))
		inventory_list.add_child(_build_inventory_item_row(str(item_id), quantity, item_def))


func _build_inventory_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.35, 0.8, 1.0))
	return label


func _build_inventory_cargo_row() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = GlobalState.cargo_display_text()
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	box.add_child(title)
	if GlobalState.cargo_type == GlobalState.CargoType.SPECIAL:
		var detail := Label.new()
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.text = "%s -> %s\n%s" % [
			str(GlobalState.cargo_special.get("source", "Unknown source")),
			str(GlobalState.cargo_special.get("destination", "Unknown destination")),
			str(GlobalState.cargo_special.get("description", "")),
		]
		detail.add_theme_font_size_override("font_size", 12)
		detail.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))
		box.add_child(detail)
	return box


func _build_inventory_item_row(item_id: String, quantity: int, item_def) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var title := Label.new()
	var display_name := item_id.capitalize()
	var category := "item"
	var description := ""
	if item_def != null:
		display_name = item_def.display_name
		category = item_def.category
		description = item_def.description
	title.text = "%s x%d  [%s]" % [display_name, quantity, category]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	header.add_child(title)
	if ConsumableEffectsScript.can_use(item_id):
		var use_btn := Button.new()
		use_btn.text = "Use"
		use_btn.custom_minimum_size.x = 64
		use_btn.disabled = not ConsumableEffectsScript.is_usable_now(
			item_id,
			GlobalState.player,
			GlobalState.inventory,
			GlobalState.shield_capacity
		)
		use_btn.pressed.connect(_on_inventory_use_pressed.bind(item_id))
		header.add_child(use_btn)
	box.add_child(header)
	if not description.strip_edges().is_empty():
		var detail := Label.new()
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.text = description
		detail.add_theme_font_size_override("font_size", 12)
		detail.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))
		box.add_child(detail)
	return box


func _on_inventory_use_pressed(item_id: String) -> void:
	if GlobalState.player == null:
		show_hud_warning("No ship available for item use.")
		return
	if not ConsumableEffectsScript.use(
		item_id,
		GlobalState.player,
		GlobalState.inventory,
		GlobalState.shield_capacity
	):
		show_hud_warning("Cannot use that item right now.")
		return
	_update_hud_health()
	_render_inventory_items()


func _render_store_items() -> void:
	for child in store_list.get_children():
		child.queue_free()
	store_credits_label.text = "Credits: %d SC" % GlobalState.player_credits
	var reg = StoreRegistryScript.shared()
	var store = reg.get_store(_store_current_id)
	if store == null:
		return
	var rep_tier := _get_reputation_tier()
	for item_id in store.get_catalog_ids():
		var item_def = store.get_item_def(item_id)
		if item_def == null:
			continue
		var price: int = store.get_price(item_id, rep_tier)
		var stock: int = store.get_stock(item_id)
		var owned: int = GlobalState.inventory.get_quantity(item_id)
		var row := _build_store_row(item_id, item_def, price, stock, owned)
		store_list.add_child(row)


func _get_reputation_tier() -> String:
	var rep: float = GlobalState.reputations.get(
		GlobalState.current_system_id,
		GlobalState.reputations.get("zenith", 50.0)
	)
	if rep >= 80.0:
		return "allied"
	elif rep >= 65.0:
		return "trusted"
	elif rep >= 50.0:
		return "friendly"
	elif rep >= 35.0:
		return "cordial"
	elif rep >= 20.0:
		return "neutral"
	elif rep >= 5.0:
		return "wary"
	elif rep >= -10.0:
		return "unfriendly"
	elif rep >= -30.0:
		return "hostile"
	return "sworn enemy"


func _build_store_row(item_id: String, item_def, price: int, stock: int, owned: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = item_def.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 14)
	row.add_child(name_label)

	var stock_label := Label.new()
	stock_label.text = "x%d" % stock
	stock_label.add_theme_font_size_override("font_size", 13)
	stock_label.custom_minimum_size.x = 40
	if stock == 0:
		stock_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	row.add_child(stock_label)

	var price_label := Label.new()
	price_label.text = "%d SC" % price
	price_label.add_theme_font_size_override("font_size", 13)
	price_label.custom_minimum_size.x = 60
	if stock == 0:
		price_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	elif price > GlobalState.player_credits:
		price_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		price_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	row.add_child(price_label)

	var owned_label := Label.new()
	owned_label.text = "(%d)" % owned if owned > 0 else ""
	owned_label.add_theme_font_size_override("font_size", 12)
	owned_label.custom_minimum_size.x = 30
	owned_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	row.add_child(owned_label)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size.x = 50
	buy_btn.disabled = stock == 0 or price > GlobalState.player_credits
	buy_btn.pressed.connect(_on_store_buy.bind(item_id))
	row.add_child(buy_btn)

	return row


func _on_store_buy(item_id: String) -> void:
	var reg = StoreRegistryScript.shared()
	var store = reg.get_store(_store_current_id)
	if store == null:
		return
	var rep_tier := _get_reputation_tier()
	var price: int = store.get_price(item_id, rep_tier)
	if price > GlobalState.player_credits:
		return
	if not store.purchase(item_id):
		return
	GlobalState.player_credits -= price
	GlobalState.inventory.add(item_id)
	_render_store_items()


func _on_public_board_offer_accept(index: int) -> void:
	if index < 0 or index >= public_board_current_offers.size():
		return
	if QuestManager.is_lane_occupied("BOARD"):
		_render_public_board_offers()
		return
	var offer := public_board_current_offers[index]
	var quest_data: Dictionary = offer.get("quest_data", {})
	var choices: Array = quest_data.get("choices", [])
	if quest_data.is_empty() or choices.is_empty():
		return
	if not QuestManager.accept_quest(quest_data, choices[0]):
		GlobalState.emit_chatter(
			"SYSTEM WARNING",
			"Public posting failed verification. It has been removed from consideration.",
			Color(1.0, 0.45, 0.35)
		)
		_render_public_board_offers()
		return
	if quest_data.get("objective", {}).get("type", "") == "PICKUP_SPECIAL":
		var objective: Dictionary = quest_data["objective"]
		_request_outpost_pickup_handoff_attempt(
			str(objective.get("target_npc", "the contact")),
			str(objective.get("part_name", "the part")),
			str(objective.get("target_outpost_display", "the outpost")),
			str(quest_data.get("agent_name", "Public Board")),
			"",
			0
		)
	public_board_panel.visible = false
	agent_panel.visible = true
	agent_name_label.text = "PUBLIC BOARD"
	agent_subtitle_label.text = "Local Contracts & Bounties"
	_show_agent_portrait(false)
	agent_dialogue_label.text = (
		"Posting accepted.\n\n"
		+ str(
			quest_data.get(
				"dialogue",
				quest_data.get("objective_summary", "Objective verified.")
			)
		)
	)
	for child in agent_choices_container.get_children():
		child.queue_free()
	var launch_btn := Button.new()
	launch_btn.text = "Undock & Begin Mission"
	launch_btn.pressed.connect(undock_player)
	agent_choices_container.add_child(launch_btn)
	agent_back_btn.visible = true


func _should_show_public_board_turn_in() -> bool:
	if not QuestManager.is_lane_occupied("BOARD"):
		return false
	if not current_station or not is_instance_valid(current_station):
		return false
	var board_mission = QuestManager.get_mission_collection().get_by_lane(
		MissionInstance.SourceLane.BOARD
	)
	if board_mission == null:
		return false
	var cap = MissionCapabilityRegistry.get_for_type(
		str(board_mission.data.get("objective_type", ""))
	)
	return cap != null and cap.is_completed(board_mission.data)


func _on_public_board_turn_in_pressed() -> void:
	if not _should_show_public_board_turn_in():
		return
	var board_mission = QuestManager.get_mission_collection().get_by_lane(
		MissionInstance.SourceLane.BOARD
	)
	if board_mission:
		QuestManager.get_mission_collection().focus(board_mission.runtime_id)
	public_board_panel.visible = false
	dock_panel.visible = false
	agent_panel.visible = true
	_on_agent_complete_pressed()


# ── Mechanic (Jenna Kross) dock greeting ───────────────────────────────────
# When the player docks at the main station (Grease Monkeys), we pre-cache
# a personalized greeting for Jenna so the first time the player enters the
# maintenance submenu the chat box has text ready. Tries the LLM first
# (qwen2.5:1.5b — small but cheap), falls back to one of 10 canned lines
# selected by ship class + reputation tier. The LLM prompt is engineered
# to keep her voice: cocky, observant, knows things about the pilot she
# shouldn't know yet — like a good mechanic should.

# Player's ship class as it appears in dialogue. Today there's only one
# starter chassis (the INDY Miner, see GlobalState.SHIP_BASE_STATS), but
# future variants should plug in here so the line can name the chassis
# directly. Keep these short and punchy — they show up inside the chat box.
const PLAYER_SHIP_NAME = "INDY Miner"

# 10 canned lines. Each is a complete, in-character greeting Jenna would
# give at the maintenance bay. References ship class and/or reputation
# tier. Always a little too personal — implies she already knows things
# about the pilot. Used:
#   1. As offline fallback when the LLM is unreachable.
#   2. As few-shot examples fed to the LLM (see request_mechanic_intro)
#      so the generated line matches voice, length, and structure.
# Picked deterministically by reputation tier + ship state so a returning
# player gets a line that feels like "she remembers you" without a second
# of LLM latency on cold start.
const FALLBACK_MECHANIC_GREETINGS: Array = [
	"INDY Miner, right? Heard your thruster's been screaming bloody murder for three sectors. Drop her on the rack — I'll work my magic.",
	"Cute ship. Zenith's not going to be happy you scratched the paint, but don't worry, I don't snitch. What hurts first?",
	"INDY Miner. Of course. You Aurelia contracts or Vanguard contracts? I can tell from the scorch marks. Sit down, I've got you.",
	"Oh good, the pilot Vanguard put on a watchlist. Don't worry, Indy — Grease Monkeys is neutral ground. Mostly. What's broken?",
	"You flew that thing here on three engine cycles? Respect. And stupidity. Park it, I'll patch the frame before I judge the rest of you.",
	"INDY Miner hull, unlisted cargo, Zenith is friendly, Vanguard is pissed. Yeah, I read the registry. I read everything. What do you need?",
	"Your ship's prettier than your rep sheet, and that's not a compliment. Cute INDY though. Bring her around, I'll fix what Aurelia's goons dented.",
	"Heard you picked a fight with a Reaver in an INDY Miner and walked away. I'm calling bullshit, but I'm also curious. Pop the hood.",
	"You know, when INDY Miner pilots start showing up at my bay, it's usually because they're one bad landing from exploding. Which one are you?",
	"Yeah, yeah — famous pilot, dangerous reputation, pristine INDY Miner. Sit down before I charge you for standing in my workspace, Indy.",
	"That {ship} looks like it could use some love. But first, I need a favor. Head to {outpost} and get {part} from {npc} for me.",
	"Before we look at the {ship}, I'm short a {part}. Grab it from {npc} at {outpost} and I'll make it worth your while.",
	"Nice {ship}. You want it fixed? Do me a solid. I left a {part} with {npc} over at {outpost}. Go get it."
]

# Returns the tier name for the player's WORST faction reputation.
# Jenna greases palms across the sector, so she's heard about the player
# from at least one of them. Worst-tier ("sworn enemy" / "hostile") makes
# for the cheekiest lines.
func _worst_reputation_tier() -> String:
	var worst_tier: String = "neutral"
	var worst_val: float = 0.0
	for faction in GlobalState.reputations:
		var rep: float = float(GlobalState.reputations[faction])
		if rep < worst_val:
			worst_val = rep
			worst_tier = GlobalState.reputation_tier(rep)
	return worst_tier

# Returns the tier name for the player's BEST faction reputation.
# "allied" / "trusted" lines imply Jenna's heard good things from
# corporate / military channels.
func _best_reputation_tier() -> String:
	var best_tier: String = "neutral"
	var best_val: float = 0.0
	for faction in GlobalState.reputations:
		var rep: float = float(GlobalState.reputations[faction])
		if rep > best_val:
			best_val = rep
			best_tier = GlobalState.reputation_tier(rep)
	return best_tier

# Pre-cache a personalized Jenna greeting when the player docks at
# Grease Monkeys. Kicks off the LLM call in the background; if it
# returns in time, we use it, otherwise the canned array covers us.
# Idempotent: only triggers once per dock. Clears the prior cached line
# so the next render shows the new one.
func _cache_mechanic_intro() -> void:
	# Don't bail if a request is in flight — the Speak button legitimately
	# wants to interrupt and fire a new one. The request id guards
	# against stale callbacks overwriting the new one.
	_mechanic_precache_in_flight = true
	_mechanic_request_id += 1
	var my_request_id: int = _mechanic_request_id
	_cached_mechanic_line = ""
	_cached_mechanic_line_is_fallback = false

	_mechanic_pickup_offer = GlobalState.roll_pickup_offer()
	_mechanic_pickup_declined = false

	# Build context for the LLM. Keep it small — the 1.5b model chews
	# tokens fast, and we want the line back in <2s. We feed the model
	# the exact same canned lines as few-shot examples so the generated
	# output matches voice, length, and structure.
	var worst_tier: String = _worst_reputation_tier()
	var best_tier: String = _best_reputation_tier()
	var ship: String = PLAYER_SHIP_NAME
	var credits: int = GlobalState.player_credits
	
	var active_quest: Dictionary = QuestManager.get_pickup_special_data()

	# If LLM is reachable, try the real call. LLMInterface is the same
	# path used for Kaelen handoffs, so we know it works end-to-end.
	# (request_mechanic_intro is added below as a thin wrapper so the
	# prompt stays local to this feature rather than spamming LLMInterface.)
	_request_mechanic_intro(ship, worst_tier, best_tier, credits, _mechanic_pickup_offer, active_quest, func(line: String, is_fallback: bool) -> void:
		# Stale-callback guard: only the latest request wins. If a newer
		# Speak click already fired (request_id > mine), bail without
		# touching the cache or playing anything.
		if my_request_id != _mechanic_request_id:
			print("[TRACE] [UIManager] Stale mechanic greeting callback (id=", my_request_id, " vs ", _mechanic_request_id, "). Dropping.")
			return
		_cached_mechanic_line = line
		_cached_mechanic_line_is_fallback = is_fallback
		_mechanic_precache_in_flight = false
		print("[TRACE] [UIManager] Mechanic greeting cached. fallback=", is_fallback, " len=", line.length(), " offer=", _mechanic_pickup_offer.get("offer", false))
		# Pre-cache the TTS so the line is instant when the player enters
		# maintenance. Uses Jenna's stable voice profile for consistency with
		# her other flavor lines. Skipped on fallback (already in cache or
		# too short to be worth caching).
		if not is_fallback and line.strip_edges() != "":
			SpeechService.cache(line, "voice.jenna_kross.v1")
		# If the player is already inside the maintenance submenu, refresh
		# the chat box immediately (otherwise the cached line waits for
		# next entry). _render_mechanic_intro will auto-play if the line
		# is new.
		if current_submenu == DockSubmenu.MAINTENANCE:
			_render_mechanic_intro()
	)

# Thin wrapper around the LLM. Falls back to a tier-weighted canned line
# if the model is offline / slow / returns garbage. The prompt is built
# locally so this feature stays self-contained.
func _request_mechanic_intro(ship: String, worst_tier: String, best_tier: String, credits: int, offer: Dictionary, active_quest: Dictionary, callback: Callable) -> void:
	if LLMInterface.active_model_name == "":
		var fb: String = _pick_fallback_mechanic_greeting(ship, worst_tier, best_tier, offer, active_quest)
		callback.call(fb, true)
		return
	
	var prompt: String = _build_mechanic_intro_prompt(ship, worst_tier, best_tier, credits, offer, active_quest)
	_request_mechanic_intro_attempt(prompt, ship, worst_tier, best_tier, offer, active_quest, callback, "", 0)

# Builds the system prompt for the mechanic intro. Appends the pickup offer
# instructions if an offer is active.
func _build_mechanic_intro_prompt(ship: String, worst_tier: String, best_tier: String, credits: int, offer: Dictionary, active_quest: Dictionary) -> String:
	var examples: Array = [
		FALLBACK_MECHANIC_GREETINGS[0],
		FALLBACK_MECHANIC_GREETINGS[4],
		FALLBACK_MECHANIC_GREETINGS[7],
	]
	# If an offer is rolling, use the offer templates (indices 10-12) instead
	if offer.get("offer", false):
		examples = [
			FALLBACK_MECHANIC_GREETINGS[10],
			FALLBACK_MECHANIC_GREETINGS[11],
			FALLBACK_MECHANIC_GREETINGS[12],
		]
	var examples_block: String = ""
	for ex in examples:
		examples_block += "- \"" + ex + "\"\n"
	
	var prompt: String = (
		"You ARE Jenna Kross, a grease-monkey mechanic at the main station dock. "
		+ "You are NOT Broker Kaelen, NOT an agent, NOT a quest-giver. You fix ships for a living.\n\n"
		+ "FACT PACKET (use these exact strings):\n"
		+ "- Ship: \"" + ship + "\"\n"
		+ "- Worst faction rep tier: \"" + worst_tier + "\"\n"
		+ "- Best faction rep tier: \"" + best_tier + "\"\n"
		+ "- Credits: " + str(credits) + "\n"
	)
	
	var reqs: String = ""
	if active_quest.has("part_name"):
		var part_name: String = active_quest.get("part_name", "the part")
		var target_outpost: String = active_quest.get("target_outpost_display", "an outpost")
		var has_part: bool = active_quest.get("picked_up", false)
		
		prompt += (
			"- Part we are talking about: \"" + part_name + "\"\n"
			+ "- Player has picked it up: " + ("Yes" if has_part else "No") + "\n\n"
		)
		
		if not has_part:
			reqs = (
				"1. 2-3 sentences, max 250 chars.\n"
				+ "2. You MUST mention the ship name \"" + ship + "\" literally (or a short form like \"that crate\").\n"
				+ "3. You MUST ask the player why they don't have \"" + part_name + "\" yet, or tell them to hurry up and go to \"" + target_outpost + "\".\n"
			)
		else:
			reqs = (
				"1. 2-3 sentences, max 250 chars.\n"
				+ "2. You MUST mention the ship name \"" + ship + "\" literally (or a short form like \"that crate\").\n"
				+ "3. You MUST acknowledge they brought \"" + part_name + "\" and tell them to hand it over or drop it.\n"
			)
	elif offer.get("offer", false):
		var target_npc: String = offer.get("npc_name", "someone")
		var target_outpost: String = offer.get("outpost_display", "an outpost")
		var part_name: String = offer.get("part_name", "a part")
		prompt += (
			"- Part needed: \"" + part_name + "\"\n"
			+ "- Contact: \"" + target_npc + "\"\n"
			+ "- Location: \"" + target_outpost + "\"\n\n"
		)
		reqs = (
			"1. 2-3 sentences, max 300 chars.\n"
			+ "2. You MUST mention the ship name \"" + ship + "\" literally (or a short form like \"that crate\").\n"
			+ "3. You MUST ask the player to go to \"" + target_outpost + "\" to pick up \"" + part_name + "\" from \"" + target_npc + "\".\n"
		)
	else:
		prompt += "\n"
		reqs = (
			"1. 1-2 sentences, max 200 chars.\n"
			+ "2. You MUST mention the ship name \"" + ship + "\" literally (or a short form like \"that crate\").\n"
			+ "3. You MUST reference the rep tier \"" + worst_tier + "\" OR \"" + best_tier + "\" OR the credit count. Pick one.\n"
		)
		
	prompt += (
		"Here are 3 of YOUR OWN (Jenna's) past greetings, in your exact voice:\n"
		+ examples_block + "\n"
		+ "Write ONE NEW greeting. HARD REQUIREMENTS:\n"
		+ reqs
		+ "4. Cocky mechanic voice — second person (\"you\"), observational, a little too personal.\n"
		+ "5. NO phrases like \"your best friend\", \"stay put\", \"sit tight\", \"wait here\", \"I'll fetch\", \"hold on\", \"Shiny\". Those are KAELEN's phrases, not yours. Call the pilot \"Indy\" or just \"you\" — NEVER \"Shiny\".\n"
		+ "6. NO hashtags, NO emojis, NO quotes around the line.\n\n"
		+ "Output ONLY valid JSON: {\"line\": \"<your greeting>\"}"
	)
	return prompt

# Recursive attempt handler for the mechanic intro. Evaluates the LLM's
# response against _is_valid_mechanic_line. If it fails, appends the
# rejection reason as a self-critique suffix and tries again (up to a limit).
func _request_mechanic_intro_attempt(base_prompt: String, ship: String, worst_tier: String, best_tier: String, offer: Dictionary, active_quest: Dictionary, callback: Callable, critique_suffix: String, attempt: int) -> void:
	if attempt >= 2:
		print("[TRACE] [UIManager] Mechanic LLM failed all attempts. Falling back.")
		GenerationDiagnostics.record_fallback(
			"mechanic_intro",
			"max_attempts_reached",
			"UIManager",
			{"attempt": attempt}
		)
		callback.call(_pick_fallback_mechanic_greeting(ship, worst_tier, best_tier, offer, active_quest), true)
		return
		
	var url: String = LLMInterface.OLLAMA_URL
	var model: String = LLMInterface.active_model_name if LLMInterface.active_model_name != "" else "qwen2.5:1.5b"
	var prompt_to_send: String = base_prompt
	if critique_suffix != "":
		prompt_to_send += "\n\n" + critique_suffix
		
	var body: Dictionary = {
		"model": model,
		"prompt": prompt_to_send,
		"stream": false,
		"format": "json",
		"options": { "temperature": 0.85, "num_predict": 250 },
	}
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 8.0
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body_bytes: PackedByteArray) -> void:
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			GenerationDiagnostics.record_fallback(
				"mechanic_intro",
				"http_failed_result_%d_code_%d" % [result, code],
				"UIManager",
				{"attempt": attempt}
			)
			var fb = _pick_fallback_mechanic_greeting(ship, worst_tier, best_tier, offer, active_quest)
			callback.call(fb, true)
			return
			
		var raw: String = body_bytes.get_string_from_utf8()
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary and parsed.has("response"):
			var inner_str: String = str(parsed["response"])
			var inner = JSON.parse_string(inner_str)
			if inner is Dictionary and inner.has("line"):
				var line: String = str(inner["line"]).strip_edges()
				if line != "":
					var is_valid: bool = _is_valid_mechanic_line(line, ship, worst_tier, best_tier, offer, active_quest)
					if is_valid:
						print("[TRACE] [UIManager] Mechanic LLM line accepted on attempt ", attempt, ": \"", line.left(80), "...\"")
						callback.call(line, false)
						return
					else:
						var reason: String = _explain_mechanic_line_rejection(line, ship, worst_tier, best_tier, offer, active_quest)
						print("[TRACE] [UIManager] Mechanic LLM line REJECTED on attempt ", attempt, ": ", reason, " (", line, ")")
						var new_suffix: String = "SELF-CRITIQUE — your previous attempt was rejected. Reason: " + reason
						_request_mechanic_intro_attempt(base_prompt, ship, worst_tier, best_tier, offer, active_quest, callback, new_suffix, attempt + 1)
						return
		
		# Fallback on parse error
		GenerationDiagnostics.record_fallback(
			"mechanic_intro",
			"parse_or_schema_failed",
			"UIManager",
			{"attempt": attempt}
		)
		var fb = _pick_fallback_mechanic_greeting(ship, worst_tier, best_tier, offer, active_quest)
		callback.call(fb, true)
	)
	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

# Validation rules for Jenna's generated line.
func _is_valid_mechanic_line(line: String, ship: String, worst_tier: String, best_tier: String, offer: Dictionary, active_quest: Dictionary) -> bool:
	return _explain_mechanic_line_rejection(line, ship, worst_tier, best_tier, offer, active_quest) == ""

# Returns the reason why a mechanic line failed validation, or "" if it passes.
func _explain_mechanic_line_rejection(line: String, ship: String, worst_tier: String, best_tier: String, offer: Dictionary, active_quest: Dictionary) -> String:
	var lower: String = line.to_lower()
	var ship_l: String = ship.to_lower()
	var ship_short: String = ship_l.split(" ")[0]
	if not (lower.contains(ship_l) or lower.contains(ship_short) or lower.contains("that crate") or lower.contains("your crate") or lower.contains("your ship") or lower.contains("your rig")):
		return "Failed to mention the ship name or refer to the ship."
	
	if active_quest.has("part_name"):
		var part_name: String = active_quest.get("part_name", "").to_lower()
		var part_words = part_name.split(" ")
		var has_part = false
		for w in part_words:
			if w.length() > 3 and lower.contains(w):
				has_part = true
				break
		if not has_part and not lower.contains(part_name):
			return "Failed to mention the required part ('" + part_name + "')."
	elif offer.get("offer", false):
		var target_npc: String = offer.get("npc_name", "").to_lower()
		var target_outpost: String = offer.get("outpost_display", "").to_lower()
		var part_name: String = offer.get("part_name", "").to_lower()
		
		# Allow partial matches for part names since LLM might truncate them
		var part_words = part_name.split(" ")
		var has_part = false
		for w in part_words:
			if w.length() > 3 and lower.contains(w):
				has_part = true
				break
		if not has_part and not lower.contains(part_name):
			return "Failed to mention the required part ('" + part_name + "')."
			
		var npc_words = target_npc.split(" ")
		if not lower.contains(target_npc) and not lower.contains(npc_words[0]):
			return "Failed to mention the contact ('" + target_npc + "')."
	else:
		var rep_words: Array = ["reputation", "rep sheet", "rep", "watchlist", "hostile", "trusted", "allied", "friendly", "cordial", "enemy", "scorch", "wanted", "marked", "neutral"]
		var has_rep: bool = false
		for w in rep_words:
			if lower.contains(w):
				has_rep = true
				break
		var has_credits: bool = lower.contains("credit") or lower.contains("sc") or lower.contains("wallet") or lower.contains("broke") or lower.contains("rich")
		if not has_rep:
			if worst_tier != "neutral" and lower.contains(worst_tier):
				has_rep = true
			elif best_tier != "neutral" and lower.contains(best_tier):
				has_rep = true
		if not (has_rep or has_credits):
			return "Failed to reference reputation tier or credit count."
			
	var kaelen_tells: Array = ["best friend", "stay put", "sit tight", "wait here", "i'll fetch", "i'll grab", "hold on", "hold here", "stay here", "shiny"]
	for tell in kaelen_tells:
		if lower.contains(tell):
			return "Contains forbidden Kaelen phrase: '" + tell + "'."
			
	if line.length() < 25 or line.length() > 400:
		return "Length out of bounds."
		
	return ""

# Pick a canned line.
func _pick_fallback_mechanic_greeting(ship: String, worst_tier: String, best_tier: String, offer: Dictionary, active_quest: Dictionary) -> String:
	if active_quest.has("part_name"):
		var part = active_quest.get("part_name", "the part")
		var has_part = active_quest.get("picked_up", false)
		if not has_part:
			return "Where's my %s? Don't tell me you got lost, Indy." % part
		else:
			return "You actually got the %s. Drop it on the bench before you break it." % part

	var salt: int = randi() % 10
	var idx: int = (worst_tier.length() + best_tier.length() + salt) % 10
	var line: String = FALLBACK_MECHANIC_GREETINGS[idx]
	if offer.get("offer", false):
		# Indices 10-12 are the pickup offer fallbacks
		idx = 10 + (salt % 3)
		line = FALLBACK_MECHANIC_GREETINGS[idx]
		line = line.replace("{part}", offer.get("part_name", "the part"))
		line = line.replace("{npc}", offer.get("npc_name", "the contact"))
		line = line.replace("{outpost}", offer.get("outpost_display", "the outpost"))
	return line.replace("{ship}", ship)

func _render_mechanic_intro() -> void:
	if not mechanic_intro_panel or not is_instance_valid(mechanic_intro_panel):
		return
	var portrait_tex: Texture2D = GlobalState.get_minor_npc_portrait("Jenna Kross")
	if portrait_tex:
		mechanic_portrait.texture = portrait_tex
		
	var line: String = _cached_mechanic_line
	var line_changed: bool = false
	if line.strip_edges() == "":
		var active_quest: Dictionary = QuestManager.get_pickup_special_data()
		line = _pick_fallback_mechanic_greeting(PLAYER_SHIP_NAME, _worst_reputation_tier(), _best_reputation_tier(), _mechanic_pickup_offer, active_quest)
		_cached_mechanic_line = line
		_cached_mechanic_line_is_fallback = true
		
	if line != _last_played_mechanic_line:
		line_changed = true
		_last_played_mechanic_line = line
		
	mechanic_line_label.text = line
	mechanic_intro_panel.visible = true
	
	# Show/hide accept/decline buttons if an offer is active
	var show_offer_btns = false
	if _mechanic_pickup_offer.get("offer", false) and not _mechanic_pickup_declined and not QuestManager.is_lane_occupied("STATION"):
		show_offer_btns = true
	if mechanic_pickup_accept_btn and is_instance_valid(mechanic_pickup_accept_btn):
		mechanic_pickup_accept_btn.visible = show_offer_btns
	if mechanic_pickup_decline_btn and is_instance_valid(mechanic_pickup_decline_btn):
		mechanic_pickup_decline_btn.visible = show_offer_btns
		
	if line_changed:
		var display_line: String = SpeechService.prepare_text(
			line,
			"voice.jenna_kross.v1"
		)
		if display_line != line:
			mechanic_line_label.text = display_line
		SpeechService.play(line, "voice.jenna_kross.v1")


# ── Test quest: outpost pickup (DEBUG) ──────────────────────────────────────
# Rerunnable debug feature. The Start button at Grease Monkeys builds a
# PICKUP_SPECIAL quest and hands it to QuestManager.accept_quest. The
# player then flies to the assigned outpost, docks, and clicks
# "Test: Pickup Part" (handler in the dock UI) to mark the part picked up
# and load it into cargo. Return to Grease Monkeys and click
# "Test: Deliver Part" to clear cargo and complete the quest.

const TEST_OUTPOST_IDS = ["iron_reach", "kova"]
const TEST_OUTPOST_DISPLAY = {
	"iron_reach": "Outpost Iron Reach",
	"kova":      "Outpost Kova",
}
# Outpost scene node name → outpost id. The scene nodes are named after their
# in-world labels (IronReachOutpost, KovaStation), not the lowercase ids the
# quest data uses. This map bridges the two for the outpost-only buttons.
const OUTPOST_NODE_TO_ID = {
	"IronReachOutpost": "iron_reach",
	"KovaStation":      "kova",
}
const TEST_PART_NAMES = [
	"Plasma Coupler Mk II",
	"Hydraulic Sealant Cartridge",
	"Firmware Module — Nav Compute v3.1",
	"Quantum Drive Bypass Coil",
	"Shield Capacitor Array",
	"Sensor Calibration Kit",
	"Antimatter Injector Valve",
	"Thrust Vectoring Servo",
]
const TEST_PICKUP_REWARD = 200  # credits awarded on "deliver" for test runs

func _on_test_pickup_pressed() -> void:
	# 1) Random outpost
	var outpost_id: String = TEST_OUTPOST_IDS[randi() % TEST_OUTPOST_IDS.size()]
	var outpost_display: String = TEST_OUTPOST_DISPLAY[outpost_id]

	# 2) Random NPC stationed at that outpost
	var npcs: Array = GlobalState.get_minor_npcs_at_outpost(outpost_id)
	if npcs.is_empty():
		push_warning("[TEST] No NPCs assigned to outpost " + outpost_id)
		return
	var npc_name: String = npcs[randi() % npcs.size()]

	# 3) Random part
	var part_name: String = TEST_PART_NAMES[randi() % TEST_PART_NAMES.size()]

	# 4) Clean slate — any prior ore or special cargo is dropped so the
	#    rerun produces predictable state.
	GlobalState.clear_cargo()
	show_hud_warning("Test: starting pickup quest for '%s' from %s @ %s" % [part_name, npc_name, outpost_display])

	# 5) Build a PICKUP_SPECIAL quest dict and hand it to QuestManager.
	#    Cargo is NOT loaded here — it loads when the player actually picks
	#    the part up at the outpost (mark_pickup_complete from the dock UI).
	var quest_data: Dictionary = {
		"title": "Test: %s Pickup" % part_name,
		"faction": "neutral",
		"agent_name": "Jenna Kross",
		"dialogue": "Test debug quest. Pick up the part at %s and bring it back to Grease Monkeys." % outpost_display,
		"objective": {
			"type": "PICKUP_SPECIAL",
			"target_outpost": outpost_id,
			"target_outpost_display": outpost_display,
			"target_npc": npc_name,
			"part_name": part_name,
			"destination": "Grease Monkeys",
			"reward_credits": TEST_PICKUP_REWARD,
		},
	}
	# Minimal selected_choice — no immediate credits / rep changes / multipliers.
	var selected_choice: Dictionary = {
		"text": "I'll take it.",
		"consequence": {},
	}
	QuestManager.accept_quest(quest_data, selected_choice)
	show_hud_warning("Quest active. Fly to %s, dock, and click 'Test: Pickup Part'." % outpost_display)
	print("[TEST] Pickup quest accepted: '%s' from %s @ %s" % [part_name, npc_name, outpost_display])

func _on_test_deliver_pressed() -> void:
	if not QuestManager.is_quest_active():
		show_hud_warning("No active quest to deliver.")
		return
	if not QuestManager.is_quest_completed():
		show_hud_warning("You haven't picked up the part yet. Dock at the assigned outpost and click 'Test: Pickup Part'.")
		return
	# Snapshot the part name for the success message before complete_quest clears cargo
	var part_name: String = QuestManager.active_quest.get("part_name", "(unknown)")
	QuestManager.complete_quest()
	show_hud_warning("Delivered '%s' to Grease Monkeys. +%d SC." % [part_name, TEST_PICKUP_REWARD])

const FALLBACK_MECHANIC_THANKS: Array = [
	"Thanks for the {part}. I'd say you're my favorite courier, but my dog brings me things faster. Here's your creds.",
	"Got the {part}. It's a miracle you didn't explode on the way back. Take your money and get out of my bay.",
	"Not bad, Indy. Next time try not to scuff the casing. Credits are in your account.",
	"I'll take that {part}. You're almost useful when you're not getting shot at. Don't spend the payout all in one place.",
]

func _on_deliver_part_pressed() -> void:
	if not QuestManager.is_quest_active() or not QuestManager.is_quest_completed():
		return
	var part_name: String = QuestManager.active_quest.get("part_name", "(unknown)")
	var reward: int = QuestManager.active_quest.get("reward_credits", 0)
	QuestManager.complete_quest()
	
	var salt: int = randi() % FALLBACK_MECHANIC_THANKS.size()
	var line: String = FALLBACK_MECHANIC_THANKS[salt].replace("{part}", part_name)
	
	SpeechService.play(line, "voice.jenna_kross.v1")
	var portrait_tex: Texture2D = GlobalState.get_minor_npc_portrait("Jenna Kross")
	show_dock_message(line, "Jenna Kross", Color(1.0, 0.85, 0.4), portrait_tex)
	_render_dock_submenu()


# Outpost-side pickup button. Validates the active quest, the current
# station, and the target outpost before calling QuestManager.mark_pickup_complete.
func _on_test_pickup_part_pressed() -> void:
	var station_quest_pickup: Dictionary = QuestManager.get_pickup_special_data()
	if station_quest_pickup.is_empty() \
			or station_quest_pickup.get("picked_up", false):
		show_dock_message("No active pickup quest here. Start one at Grease Monkeys first.", "", Color(1.0, 0.45, 0.45))
		return

	# Map the docked outpost's node name to its id, then compare against the
	# quest's target outpost. Refuses the pickup if the player is at the wrong station.
	if not current_station or not is_instance_valid(current_station):
		show_dock_message("No station docked.", "", Color(1.0, 0.45, 0.45))
		return
	var docked_outpost_id: String = OUTPOST_NODE_TO_ID.get(current_station.name, "")
	if docked_outpost_id == "":
		show_dock_message("Pickup can only happen at an outpost dock.", "", Color(1.0, 0.45, 0.45))
		return
	var quest_outpost_id: String = QuestManager.active_quest.get("target_outpost", "")
	if docked_outpost_id != quest_outpost_id:
		show_dock_message(("Wrong outpost. The quest wants the part picked up at %s." % \
			QuestManager.active_quest.get("target_outpost_display", quest_outpost_id)), "", Color(1.0, 0.45, 0.45))
		return

	var picked_part: String = QuestManager.active_quest.get("part_name", "the part")
	var picked_npc: String = QuestManager.active_quest.get("target_npc", "the contact")
	var success: bool = QuestManager.mark_pickup_complete()
	if success:
		# Success: use the NPC's flavor color so the message feels
		# attached to the contact who just handed over the part. Pull
		# portrait so the slot gets the NPC's face too.
		var npc_color: Color = Color(0.85, 0.85, 0.85)
		var npc_portrait: Texture2D = null
		var npc_data := GlobalState.get_minor_npc_data(picked_npc)
		if not npc_data.is_empty():
			npc_color = npc_data.get("flavor_color", npc_color)
			npc_portrait = GlobalState.get_minor_npc_portrait(picked_npc)
		show_dock_message("Picked up '%s' from %s. Deliver to Grease Monkeys." % [picked_part, picked_npc], picked_npc, npc_color, npc_portrait)
	else:
		push_warning("[TEST] mark_pickup_complete returned false at outpost dock")


# Outpost flavor button. Consumes GlobalState.get_random_npc_flavor_line for
# the currently-docked outpost, shows the line in a portrait+name popup
# tinted with the NPC's own color, appends it to the corner chatter feed
# (persistent), and speaks the line in the NPC's unique Kokoro voice via
# the npc_flavor_spoken signal. Re-rolling picks a different NPC/line.
# Refresh-on-use: after the line plays, the NPC's other flavor lines are
# pre-cached in the background so the next click hits cache.
func _on_hear_gossip_pressed() -> void:
	if not current_station or not is_instance_valid(current_station):
		show_hud_warning("No station docked.")
		return
	var outpost_id: String = OUTPOST_NODE_TO_ID.get(current_station.name, "")
	if outpost_id == "":
		outpost_id = GlobalState.resolve_outpost_id(current_station)
	if outpost_id == "":
		show_hud_warning("No one to chat with at this dock.")
		return

	var flavor: Dictionary = GlobalState.get_random_npc_flavor_line(outpost_id)
	if flavor.is_empty():
		show_hud_warning("It's quiet. Nobody's around to talk to.")
		return

	var npc_name: String = flavor.get("npc_name", "Local")
	var line: String = flavor.get("line", "")
	var color: Color = flavor.get("color", Color.WHITE)
	var portrait: Texture2D = GlobalState.get_minor_npc_portrait(npc_name)

	# Surface the line inside the dock panel itself (portrait + name
	# in flavor color + the line). The slot holds for 7.0s + 1.5s
	# fade — longer than the old show_npc_dialogue_popup because the
	# player is staring at the dock menu and there's no rush. The
	# line is also appended to the corner chatter feed by
	# emit_npc_flavor so the player can re-read it.
	show_dock_message(line, npc_name, color, portrait)
	GlobalState.emit_npc_flavor(flavor)

	# Refresh-on-use: queue the NPC's other flavor lines for background
	# TTS pre-cache. By the time the player clicks Hear Gossip again
	# (or the same NPC speaks an ambient line), the next line is
	# likely cached and plays instantly.
	var other_lines: Array = GlobalState.get_other_flavor_lines_for_npc(npc_name, line)
	for entry in other_lines:
		SpeechService.cache(entry["line"], entry["voice_profile_id"])


# Signal handler for GlobalState.npc_flavor_spoken. Speaks the line in
# the NPC's unique Kokoro voice. Connection established in
# _create_chat_window_panel alongside the system_chatter_received
# connection.
func _on_npc_flavor_spoken(flavor: Dictionary) -> void:
	if flavor.is_empty():
		return
	var line: String = flavor.get("line", "")
	if line == "":
		return
	var voice_profile_id: String = flavor.get("voice_profile_id", "voice.neutral.v1")
	SpeechService.play(line, voice_profile_id)


func undock_player():
	var station_before_undock := current_station
	var game_root := get_tree().current_scene
	if game_root and game_root.has_method("request_safe_checkpoint"):
		if not game_root.request_safe_checkpoint(
			"undock",
			station_before_undock
		):
			push_warning(
				"[UIManager] Pre-undock safe checkpoint was not created."
			)
	dock_panel.visible = false
	if ship_upgrades_panel and is_instance_valid(ship_upgrades_panel):
		ship_upgrades_panel.visible = false
	agent_panel.visible = false
	if public_board_panel:
		public_board_panel.visible = false
	if store_panel:
		store_panel.visible = false
	if inventory_panel:
		inventory_panel.visible = false
	current_station = null
	# Reset submenu so the next dock opens on services, not maintenance
	current_submenu = DockSubmenu.SERVICES
	# Restore full overview when heading back into space
	set_overview_collapsed(false)
	# Clear any docked-message slot content so the next dock starts fresh.
	clear_dock_message()
	# Hide the mechanic intro panel and clear the cached greeting so the
	# next dock regenerates a fresh line (player rep may have changed).
	if mechanic_intro_panel and is_instance_valid(mechanic_intro_panel):
		mechanic_intro_panel.visible = false
	_cached_mechanic_line = ""
	_cached_mechanic_line_is_fallback = false
	_mechanic_precache_in_flight = false
	_mechanic_request_id += 1  # Invalidate any in-flight LLM callback
	_last_played_mechanic_line = ""

	# Clear the pickup offer state so the next dock re-rolls. Hides the
	# accept/decline buttons if they were visible from this visit.
	_mechanic_pickup_offer = {}
	_mechanic_pickup_declined = false
	if mechanic_pickup_accept_btn and is_instance_valid(mechanic_pickup_accept_btn):
		mechanic_pickup_accept_btn.visible = false
	if mechanic_pickup_decline_btn and is_instance_valid(mechanic_pickup_decline_btn):
		mechanic_pickup_decline_btn.visible = false
	# Hide the ore-trade confirm popup in case it was visible.
	if ore_trade_popup and is_instance_valid(ore_trade_popup):
		ore_trade_popup.visible = false
	# Hide the live "Ask for the part" button in case it was visible.
	if ask_for_part_btn and is_instance_valid(ask_for_part_btn):
		ask_for_part_btn.visible = false
	
	# Stop voice dialogue audio if playing
	SpeechService.stop()
	
	
	# Give player a slight push away from station
	if GlobalState.player:
		GlobalState.player.global_position += Vector3(0, 0, -15.0)
		GlobalState.player.is_docked = false
		GlobalState.player.nav_mode = "MANUAL"

func _sell_ore():
	if GlobalState.cargo_type == GlobalState.CargoType.ORE and GlobalState.cargo > 0.0:
		var earnings = int(GlobalState.cargo)
		GlobalState.player_credits += earnings
		GlobalState.clear_cargo()
		_update_repair_button()
		AudioManager.play_sell_ore()



func show_context_menu(
	entity: Node3D,
	screen_position: Variant = null
):
	if not entity or not is_instance_valid(entity): return
	context_highlight_target = entity
	context_panel.visible = true
	selection_marker.queue_redraw()
	
	var mouse_pos := (
		screen_position as Vector2
		if screen_position is Vector2
		else get_global_mouse_position()
	)
	var viewport_size = get_viewport().get_visible_rect().size
	var menu_size = context_panel.size
	if menu_size == Vector2.ZERO:
		menu_size = context_panel.custom_minimum_size
		
	var max_x = viewport_size.x - menu_size.x
	var max_y = viewport_size.y - menu_size.y
	mouse_pos.x = clamp(mouse_pos.x, 0.0, max_x)
	mouse_pos.y = clamp(mouse_pos.y, 0.0, max_y)
	
	context_panel.global_position = mouse_pos
	
	# Adjust dynamic button text based on selection type
	if context_action_btn:
		if entity.is_in_group("asteroid"):
			context_action_btn.text = "Mine Asteroid"
			context_action_btn.visible = true
		elif entity.is_in_group("station"):
			context_action_btn.text = "Dock at Station"
			context_action_btn.visible = true
		elif entity.is_in_group("jumpgate"):
			context_action_btn.text = _gate_action_label(entity)
			context_action_btn.visible = true
		elif entity.is_in_group("ship"):
			context_action_btn.text = "Attack Hostile"
			context_action_btn.visible = true
		else:
			context_action_btn.visible = false


func _close_context_menu() -> void:
	if context_panel:
		context_panel.visible = false
	context_highlight_target = null
	if selection_marker:
		selection_marker.queue_redraw()


func _command_selected_target(mode: String) -> bool:
	var target := GlobalState.active_target
	if target == null or not is_instance_valid(target) \
			or GlobalState.player == null \
			or not is_instance_valid(GlobalState.player):
		return false
	if not GlobalState.player.has_method("begin_target_navigation") \
			or not bool(
				GlobalState.player.call("begin_target_navigation", mode)
			):
		show_hud_warning("Navigation command was not accepted.")
		return false
	show_target_marker(target.global_position)
	_update_target_command_feedback()
	return true


func _on_boost_pressed() -> void:
	if GlobalState.player == null or not is_instance_valid(GlobalState.player):
		return
	if not GlobalState.player.has_method("activate_boost") \
			or not bool(GlobalState.player.call("activate_boost")):
		show_hud_warning("Boost drive is cooling down.")
		return
	show_hud_info("Boost engaged. Thrusters running hot.")
	_update_hud_health()
	_update_target_command_feedback()


func _update_target_command_feedback() -> void:
	_update_boost_button()
	if target_approach_btn == null or target_orbit_btn == null or target_action_btn == null:
		return
	var active_mode := ""
	if GlobalState.player != null and is_instance_valid(GlobalState.player):
		active_mode = str(GlobalState.player.get("nav_mode"))
	_set_command_button_active(
		target_approach_btn,
		active_mode in ["APPROACH", "APPROACH_1K", "JUMP_APPROACH"]
	)
	_set_command_button_active(target_orbit_btn, active_mode == "ORBIT")
	_set_command_button_active(
		target_action_btn,
		active_mode in ["MINE", "ATTACK", "DOCK"]
	)


func _set_command_button_active(button: Button, active: bool) -> void:
	if button == null:
		return
	if not active:
		button.self_modulate = Color.WHITE
		return
	var pulse := 0.65 + sin(Time.get_ticks_msec() * 0.01) * 0.25
	button.self_modulate = Color(0.2, 0.9, 1.0, 0.75 + pulse * 0.25)


func _update_boost_button() -> void:
	if target_boost_btn == null:
		return
	if GlobalState.player == null or not is_instance_valid(GlobalState.player):
		target_boost_btn.disabled = true
		target_boost_btn.text = "Boost"
		return
	var active := 0.0
	var cooldown := 0.0
	if GlobalState.player.has_method("boost_active_remaining"):
		active = float(GlobalState.player.call("boost_active_remaining"))
	if GlobalState.player.has_method("boost_cooldown_remaining"):
		cooldown = float(GlobalState.player.call("boost_cooldown_remaining"))
	if active > 0.0:
		target_boost_btn.disabled = true
		target_boost_btn.text = "Boost %.0fs" % ceilf(active)
		target_boost_btn.self_modulate = Color(0.25, 0.85, 1.0, 1.0)
	elif cooldown > 0.0:
		target_boost_btn.disabled = true
		target_boost_btn.text = "Boost %.0fs" % ceilf(cooldown)
		target_boost_btn.self_modulate = Color(0.7, 0.7, 0.7, 1.0)
	else:
		target_boost_btn.disabled = false
		target_boost_btn.text = "Boost"
		target_boost_btn.self_modulate = Color.WHITE


func _command_context_target(mode: String) -> bool:
	if context_highlight_target == null \
			or not is_instance_valid(context_highlight_target):
		return false
	GlobalState.active_target = context_highlight_target
	return _command_selected_target(mode)

func activate_selected_jumpgate() -> void:
	var gate := GlobalState.active_target
	if not gate or not is_instance_valid(gate) or not gate.is_in_group("jumpgate"):
		show_hud_warning("No jumpgate selected.")
		return

	var gate_state: String = gate.get("knowledge_state") if gate.get("knowledge_state") else "known"

	if gate_state == "hidden":
		_attempt_gate_scan(gate)
		return
	if gate_state == "damaged":
		_attempt_gate_repair(gate)
		return
	if gate_state == "blocked":
		_attempt_gate_unlock(gate)
		return

	var game_root := get_tree().current_scene
	if not game_root or not game_root.has_method("get_jump_block_reason"):
		show_hud_warning("Jump control is unavailable.")
		return
	var block_reason: String = game_root.get_jump_block_reason(gate)
	if block_reason != "":
		show_hud_warning(block_reason)
		return
	var destination := str(gate.get("destination_display_name"))
	show_hud_info("Jump sequence initiated: " + destination)
	if not gate.call("request_jump"):
		show_hud_warning("Jump request was not accepted.")

func show_death_screen():
	death_panel.visible = true

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			is_resizing = false

func _on_resize_handle_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_resizing = true
			drag_start_mouse_x = get_viewport().get_mouse_position().x
			drag_start_anchor_left = overview_panel.anchor_left
		else:
			is_resizing = false
	elif event is InputEventMouseMotion and is_resizing:
		var mouse_x = get_viewport().get_mouse_position().x
		var delta_x = mouse_x - drag_start_mouse_x
		var viewport_w = get_viewport().get_visible_rect().size.x
		if viewport_w > 0:
			var target_anchor_left = drag_start_anchor_left + (delta_x / viewport_w)
			
			# Keep width between 250px and 800px
			var right_pixel = overview_panel.anchor_right * viewport_w
			var min_left_pixel = right_pixel - 800.0
			var max_left_pixel = right_pixel - 250.0
			
			var target_left_pixel = target_anchor_left * viewport_w
			target_left_pixel = clamp(target_left_pixel, min_left_pixel, max_left_pixel)
			
			overview_panel.anchor_left = target_left_pixel / viewport_w

func show_target_marker(pos: Vector3):
	# Don't pop the small crosshair while docked — dock UI owns the screen.
	if GlobalState.player and GlobalState.player.get("is_docked"):
		return
	marker_pos_3d = pos
	marker_active = true
	marker_timer = 2.0 # Keep visible for 2 seconds to orient the player
	if target_marker:
		target_marker.visible = true
		target_marker.queue_redraw()

func _update_target_marker_position():
	if not target_marker: return
	# Same suppression as the selection ring: while docked, keep the
	# small crosshair hidden and let the dock UI own the screen.
	if GlobalState.player and GlobalState.player.get("is_docked"):
		marker_active = false
		target_marker.visible = false
		return
	if not GlobalState.player or not is_instance_valid(GlobalState.player):
		marker_active = false
		target_marker.visible = false
		return
		
	var cam = GlobalState.player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if not cam or not is_instance_valid(cam): return
	
	var pos_3d = marker_pos_3d
	var screen_pos = cam.unproject_position(pos_3d)
	var is_behind = cam.is_position_behind(pos_3d)
	
	var viewport_size = get_viewport().get_visible_rect().size
	var margin = 35.0
	
	if is_behind:
		# Mirror coordinates to point to the actual offscreen direction
		var center = viewport_size / 2.0
		var dir = (screen_pos - center).normalized()
		if dir.length() < 0.1:
			dir = Vector2.DOWN
		screen_pos = center - dir * (center.length() - margin)
		
	# Clamp marker position to screen bounds
	screen_pos.x = clamp(screen_pos.x, margin, viewport_size.x - margin)
	screen_pos.y = clamp(screen_pos.y, margin, viewport_size.y - margin)
	
	target_marker.global_position = screen_pos
	target_marker.queue_redraw()

func _on_target_marker_draw():
	if not marker_active: return
	# Draw futuristic green HUD target bracket
	target_marker.draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color.GREEN, 2.5, true)
	target_marker.draw_circle(Vector2.ZERO, 3.0, Color.GREEN)
	target_marker.draw_line(Vector2(-22, 0), Vector2(-16, 0), Color.GREEN, 2.0)
	target_marker.draw_line(Vector2(16, 0), Vector2(22, 0), Color.GREEN, 2.0)
	target_marker.draw_line(Vector2(0, -22), Vector2(0, -16), Color.GREEN, 2.0)
	target_marker.draw_line(Vector2(0, 16), Vector2(0, 22), Color.GREEN, 2.0)

func _update_selection_marker_position():
	if not selection_marker: return
	# Suppress the green target ring while docked at a station/outpost —
	# the dock menu takes the screen, and a frozen reticle looks broken.
	# We bail BEFORE doing any work so the marker keeps its last-drawn
	# position if it was already hidden, and is forced hidden if it was
	# visible. The moment is_docked flips false on undock, the normal
	# path below re-shows and re-positions the marker on the next frame.
	if GlobalState.player and GlobalState.player.get("is_docked"):
		selection_marker.visible = false
		return
	var target = (
		context_highlight_target
		if context_panel != null
			and context_panel.visible
			and context_highlight_target != null
			and is_instance_valid(context_highlight_target)
		else GlobalState.active_target
	)
	if not target or not is_instance_valid(target) or target.get("destroyed"):
		selection_marker.visible = false
		return
		
	if not GlobalState.player or not is_instance_valid(GlobalState.player):
		selection_marker.visible = false
		return
		
	var cam = GlobalState.player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if not cam or not is_instance_valid(cam):
		selection_marker.visible = false
		return
		
	var is_behind = cam.is_position_behind(target.global_position)
	if is_behind:
		selection_marker.visible = false
		return
		
	var screen_pos = cam.unproject_position(target.global_position)
	selection_marker.global_position = screen_pos
	selection_marker.visible = true
	selection_marker.queue_redraw()

func _on_selection_marker_draw():
	var target = (
		context_highlight_target
		if context_panel != null
			and context_panel.visible
			and context_highlight_target != null
			and is_instance_valid(context_highlight_target)
		else GlobalState.active_target
	)
	if not target or not is_instance_valid(target) or target.get("destroyed"):
		return
		
	if not GlobalState.player or not is_instance_valid(GlobalState.player):
		return
		
	var cam = GlobalState.player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if not cam or not is_instance_valid(cam):
		return
		
	var radius_3d = 5.0
	if target.is_in_group("asteroid"):
		radius_3d = 5.0 * target.scale.x
	elif target.name == "GasGiant":
		radius_3d = 600.0
	elif target.name == "RockyPlanet":
		radius_3d = 250.0
	elif target.is_in_group("jumpgate"):
		radius_3d = 58.0
	elif target.is_in_group("celestial"):
		var shape_node := target.find_child("CollisionShape3D", true, false) as CollisionShape3D
		if shape_node and shape_node.shape is SphereShape3D:
			radius_3d = shape_node.shape.radius * target.scale.x
	elif target.is_in_group("station"):
		radius_3d = 22.0 * target.scale.x
	elif target.is_in_group("ship"):
		radius_3d = 4.0
	elif target.is_in_group("wreckage"):
		radius_3d = 4.0 * target.scale.x
		
	var screen_center = Vector2.ZERO
	var edge_pos_3d = target.global_position + cam.global_transform.basis.x * radius_3d
	var edge_pos_2d = cam.unproject_position(edge_pos_3d)
	var screen_pos = cam.unproject_position(target.global_position)
	
	var screen_radius = screen_pos.distance_to(edge_pos_2d)
	screen_radius = max(screen_radius, 22.0)
	screen_radius = screen_radius * 1.08 + 4.0
	
	# The marker represents physical line of sight, while autopilot separately
	# enforces a wider navigation lane outside planets and asteroid rings.
	var blocked := false
	if GlobalState.player.has_method("is_target_physically_visible"):
		blocked = not bool(
			GlobalState.player.call("is_target_physically_visible", target)
		)
			
	var context_highlight := context_panel != null \
		and context_panel.visible \
		and context_highlight_target == target
	var marker_color := (
		Color(0.15, 0.85, 1.0, 1.0)
		if context_highlight
		else (
			Color(0.55, 0.55, 0.55, 0.75)
			if blocked
			else Color(0.0, 1.0, 0.0, 0.75)
		)
	)
	var marker_width := 3.5 if context_highlight else 1.5
	
	# Draw target brackets around the object
	selection_marker.draw_arc(
		screen_center,
		screen_radius,
		0.0,
		TAU,
		64,
		marker_color,
		marker_width,
		true
	)
	
	# Add ticks/notches
	var tick_len = 6.0
	var angles = [0.0, PI/2.0, PI, 3.0*PI/2.0]
	for angle in angles:
		var dir = Vector2(cos(angle), sin(angle))
		var start = dir * screen_radius
		var end = dir * (screen_radius + tick_len)
		selection_marker.draw_line(start, end, marker_color, 2.0, true)

func _update_hud_health():
	if not hud_panel: return
	var p = GlobalState.player
	var hp_label = hud_panel.find_child("HPLabel", true, false) as Label
	var hp_bar = hud_panel.find_child("HPBar", true, false) as ProgressBar
	
	if p and is_instance_valid(p):
		var hp = p.get("health")
		var max_hp = p.get("max_health")
		if hp != null and max_hp != null:
			if hp_label:
				hp_label.text = "HP: " + str(int(hp)) + " / " + str(int(max_hp))
			if hp_bar:
				hp_bar.max_value = max_hp
				hp_bar.value = hp
				
				# Dynamically style health bar color matching drone state!
				var fill_style = hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if fill_style:
					var hp_pct = hp / max_hp
					if hp_pct <= 0.3:
						fill_style.bg_color = Color(0.9, 0.2, 0.2, 1.0) # Red
					elif hp_pct <= 0.6:
						fill_style.bg_color = Color(0.9, 0.8, 0.2, 1.0) # Yellow
					else:
						fill_style.bg_color = Color(0.2, 0.9, 0.4, 1.0) # Green

func _update_hud_reputations():
	if not hud_panel: return
	var sys_factions: Array[String] = _get_current_system_faction_ids()
	var show_all: bool = sys_factions.is_empty()

	var zen_vis: bool = show_all or "zenith" in sys_factions
	var aur_vis: bool = show_all or "aurelia" in sys_factions
	var van_vis: bool = show_all or "vanguard" in sys_factions

	_update_faction_rep_label("ZenRepLabel", "zenith")
	_update_faction_rep_label("AurRepLabel", "aurelia")
	_update_faction_rep_label("VanRepLabel", "vanguard")

	_set_rep_label_visible("ZenRepLabel", zen_vis)
	_set_rep_label_visible("AurRepLabel", aur_vis)
	_set_rep_label_visible("VanRepLabel", van_vis)

	var sep1 := hud_panel.find_child("RepSep1", true, false) as Label
	var sep2 := hud_panel.find_child("RepSep2", true, false) as Label
	if sep1:
		sep1.visible = zen_vis and (aur_vis or van_vis)
	if sep2:
		sep2.visible = aur_vis and van_vis

# Updates one faction's HUD rep label: text (abbrev + value), color (tier
# gradient), and tooltip (full name + descriptor + current tier + value).
func _update_faction_rep_label(label_name: String, faction_id: String):
	var lbl = hud_panel.find_child(label_name, true, false) as Label
	if not lbl: return

	var rep_value = int(GlobalState.reputations.get(faction_id, 0.0))
	var info = GlobalState.faction_info(faction_id)
	var tier = GlobalState.reputation_tier(rep_value)
	var color = GlobalState.reputation_color(rep_value)

	# Display: "ZEN 50"
	lbl.text = "%s %d" % [info.abbrev, rep_value]
	# Color: tier gradient (red → gray → green)
	lbl.add_theme_color_override("font_color", color)
	# Tooltip: full name + descriptor + current feeling + numeric value
	lbl.tooltip_text = "%s (%s) — %s (%d)" % [info.name, info.descriptor, tier, rep_value]


func _set_rep_label_visible(label_name: String, vis: bool) -> void:
	var lbl := hud_panel.find_child(label_name, true, false) as Label
	if lbl:
		lbl.visible = vis


func _get_current_system_faction_ids() -> Array[String]:
	var result: Array[String] = []
	var registry: Variant = _get_system_registry()
	if registry == null:
		return result
	var sys_id: String = GlobalState.current_system_id
	for sys_def in registry.get_all_systems():
		if sys_def.legacy_id == sys_id or str(sys_def.id) == sys_id:
			for fid in sys_def.faction_ids:
				result.append(str(fid).get_slice(".", 1))
			break
	return result


func _exit_tree() -> void:
	if GlobalState.entities_changed.is_connected(refresh_overview):
		GlobalState.entities_changed.disconnect(refresh_overview)


func _domain_id_for_current_system() -> String:
	var registry: Variant = _get_system_registry()
	if registry == null:
		return ""
	for sys_def in registry.get_all_systems():
		if sys_def.legacy_id == GlobalState.current_system_id:
			return str(sys_def.id)
	return ""


func _get_current_system_display_name() -> String:
	var registry: Variant = _get_system_registry()
	if registry == null:
		return ""
	var sys_id = GlobalState.current_system_id
	for sys_def in registry.get_all_systems():
		if sys_def.legacy_id == sys_id or str(sys_def.id) == sys_id:
			return sys_def.display_name
	return ""


func _get_system_registry() -> Variant:
	var game_root := get_tree().current_scene
	if game_root == null or not "system_registry" in game_root:
		return null
	var registry: Variant = game_root.get("system_registry")
	if registry == null or not registry.has_method("get_all_systems"):
		return null
	return registry


func refresh_overview():
	var entities: Array = []
	var system_root := GlobalState.get_system_root()
	var scene_tree := get_tree()
	if not system_root or not scene_tree:
		return

	if overview_title_label:
		var sys_name := _get_current_system_display_name()
		overview_title_label.text = sys_name + "  OVERVIEW" if sys_name != "" else "OVERVIEW"

	if branch_map and not branch_map.planned_route.is_empty():
		var dest_id: String = branch_map.planned_route[-1]
		var dest_data: Dictionary = branch_map.system_nodes.get(dest_id, {})
		if dest_data.get("legacy_id", "") == GlobalState.current_system_id:
			branch_map.clear_route()
			show_hud_info("Destination reached.", Color(0.2, 1.0, 0.6))
		else:
			branch_map.planned_route = branch_map._bfs_path(
				_domain_id_for_current_system(), branch_map.planned_route[-1]
			)
			var jumps_left: int = branch_map.planned_route.size() - 1
			if jumps_left > 0:
				var dest_name: String = branch_map.system_nodes.get(dest_id, {}).get("display_name", "destination")
				show_hud_info("%d jump%s remaining to %s." % [jumps_left, "" if jumps_left == 1 else "s", dest_name], Color(0.2, 0.9, 1.0))
			call_deferred("_auto_select_route_gate")

	if map_btn:
		var registry: Variant = _get_system_registry()
		if registry != null:
			map_btn.visible = registry.get_all_systems().size() > 1
		else:
			map_btn.visible = false
	
	# Add ALL stations (main + outposts) by group — never hardcode node names
	for node in scene_tree.get_nodes_in_group("station"):
		if is_instance_valid(node) and system_root.is_ancestor_of(node):
			entities.append(node)
	for node in scene_tree.get_nodes_in_group("celestial"):
		if is_instance_valid(node) and system_root.is_ancestor_of(node):
			entities.append(node)

	
	# Add Asteroids
	for node in scene_tree.get_nodes_in_group("asteroid"):
		if system_root.is_ancestor_of(node):
			entities.append(node)
		
	# Add NPC Ships
	for node in scene_tree.get_nodes_in_group("ship"):
		if node != GlobalState.player and is_instance_valid(node) and system_root.is_ancestor_of(node) and not node.get("destroyed"):
			entities.append(node)
			
	# Add Wreckage
	for node in scene_tree.get_nodes_in_group("wreckage"):
		if is_instance_valid(node) and system_root.is_ancestor_of(node):
			entities.append(node)
	for node in scene_tree.get_nodes_in_group("jumpgate"):
		if is_instance_valid(node) and system_root.is_ancestor_of(node):
			entities.append(node)
			
	update_overview_list(entities)

func _auto_select_route_gate() -> void:
	if not branch_map or branch_map.planned_route.size() < 2:
		return
	var next_legacy: String = branch_map.get_next_hop_legacy_id()
	if next_legacy.is_empty():
		return
	var scene_tree := get_tree()
	if not scene_tree:
		return
	for gate in scene_tree.get_nodes_in_group("jumpgate"):
		var gate_dest: String = gate.get("destination_system_id") if gate.get("destination_system_id") else ""
		if gate_dest == next_legacy:
			GlobalState.active_target = gate
			return


func _toggle_branch_map() -> void:
	if branch_map:
		branch_map.visible = not branch_map.visible
		if branch_map.visible:
			move_child(branch_map, get_child_count() - 1)
			branch_map.refresh()
			get_tree().paused = true
		else:
			get_tree().paused = false
			_auto_select_route_gate()


func _is_hidden_gate(entity: Node) -> bool:
	if not entity.is_in_group("jumpgate"):
		return false
	var gate_state: String = entity.get("knowledge_state") if entity.get("knowledge_state") else "known"
	return gate_state in ["unknown", "rumored"]


func _gate_action_label(gate: Node) -> String:
	var gate_state: String = gate.get("knowledge_state") if gate.get("knowledge_state") else "known"
	match gate_state:
		"hidden": return "Scan Gate"
		"blocked": return "Locked"
		"damaged": return "Repair Gate"
	return "Initiate Jump"


func _attempt_gate_scan(gate: Node) -> void:
	var gate_id: String = gate.get("world_id") if gate.get("world_id") else ""
	if gate_id.is_empty():
		show_hud_warning("Cannot identify gate.")
		return
	var action := GateDiscoveryAction.new()
	action.action_type = GateDiscoveryAction.ActionType.SCAN
	action.gate_id = gate_id
	var result := GateDiscovery.advance_gate_state(gate_id, action)
	if result.get("ok", false):
		show_hud_info("Gate scanned — status revealed.", Color(0.2, 0.9, 0.6))
	else:
		show_hud_warning(str(result.get("error", "Scan failed.")))


func _attempt_gate_repair(gate: Node) -> void:
	var gate_id: String = gate.get("world_id") if gate.get("world_id") else ""
	if gate_id.is_empty():
		show_hud_warning("Cannot identify gate.")
		return
	var action := GateDiscoveryAction.new()
	action.action_type = GateDiscoveryAction.ActionType.REPAIR
	action.gate_id = gate_id
	action.credit_cost = 50
	action.ore_cost = 30
	if not action.can_player_afford():
		show_hud_warning("Repair requires 50 SC + 30 ore.")
		return
	var result := GateDiscovery.advance_gate_state(gate_id, action)
	if result.get("ok", false):
		show_hud_info("Gate repaired — route is now active!", Color(0.2, 0.9, 0.6))
	else:
		show_hud_warning(str(result.get("error", "Repair failed.")))


func _attempt_gate_unlock(gate: Node) -> void:
	var gate_id: String = gate.get("world_id") if gate.get("world_id") else ""
	if gate_id.is_empty():
		show_hud_warning("Cannot identify gate.")
		return
	var action := GateDiscoveryAction.new()
	action.action_type = GateDiscoveryAction.ActionType.UNLOCK
	action.gate_id = gate_id
	if not action.meets_prerequisites():
		show_hud_warning("Prerequisites not met: " + action.get_prerequisite_text())
		return
	var result := GateDiscovery.advance_gate_state(gate_id, action)
	if result.get("ok", false):
		show_hud_info("Gate unlocked — route is now active!", Color(0.2, 0.9, 0.6))
	else:
		show_hud_warning(str(result.get("error", "Unlock failed.")))


func show_hud_warning(text: String):
	var warning_label = Label.new()
	warning_label.text = text
	warning_label.modulate = Color(1.0, 0.2, 0.2)
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	warning_label.add_theme_font_size_override("font_size", 22)
	warning_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	warning_label.add_theme_constant_override("shadow_outline_size", 4)
	
	warning_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	warning_label.offset_left = -300
	warning_label.offset_right = 300
	warning_label.offset_top = 100
	warning_label.offset_bottom = 150
	
	add_child(warning_label)
	
	var tween = create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(warning_label, "modulate:a", 0.0, 1.5)
	tween.tween_callback(warning_label.queue_free)

# Soft counterpart to show_hud_warning. Same shape and position, but the
# label is tinted with the caller's color (default cyan) instead of red,
# so it reads as neutral information / flavor dialogue rather than an
# error state. Use for quest progress, gossip lines, lore drops, etc.
# Reserve show_hud_warning for actual failures the player needs to react to.
func show_hud_info(text: String, tint: Color = Color(0.0, 0.85, 1.0)):
	var info_label = Label.new()
	info_label.text = text
	info_label.modulate = tint
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	info_label.add_theme_font_size_override("font_size", 22)
	info_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	info_label.add_theme_constant_override("shadow_outline_size", 4)
	
	info_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	info_label.offset_left = -300
	info_label.offset_right = 300
	info_label.offset_top = 100
	info_label.offset_bottom = 150
	
	add_child(info_label)
	
	var tween = create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(info_label, "modulate:a", 0.0, 1.5)
	tween.tween_callback(info_label.queue_free)

# Soft NPC dialogue popup. Used for flavor chatter ("Hear Gossip",
# ambient chatter lines) — enriches the show_hud_info flash with a
# small portrait thumbnail, the speaker's name in their flavor color,
# and the line beneath. Auto-dismisses after 4.0s hold + 1.5s fade
# (longer hold than show_hud_info because there's more to read).
# Centered horizontally, ~96px below the top edge — visually similar
# to show_hud_info so the player doesn't have to learn a new layout.
# `portrait` is a Texture2D (typically an AtlasTexture from
# GlobalState.get_minor_npc_portrait). Pass null to skip the portrait
# box (e.g. for a generic system message that needs a name only).
func show_npc_dialogue_popup(text: String, npc_name: String, color: Color, portrait: Texture2D = null) -> void:
	# Translucent dark panel for definition. Drops a small
	# background that the centered text can sit on so the line
	# stays readable against busy starfield backgrounds.
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.75)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(color.r, color.g, color.b, 0.85)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	# Center-top, 600px wide max. Height grows with content.
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = 60
	panel.offset_bottom = 60
	panel.custom_minimum_size = Vector2(600, 0)
	add_child(panel)

	# HBox: portrait (96px) + 12px spacer + VBox(name, line)
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 0
	hbox.offset_right = 0
	hbox.offset_top = 0
	hbox.offset_bottom = 0
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	if portrait:
		var portrait_rect := TextureRect.new()
		portrait_rect.custom_minimum_size = Vector2(64, 64)
		portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait_rect.texture = portrait
		# Subtle 1px border in the NPC color so the chip feels tied
		# to the speaker.
		var portrait_border := StyleBoxFlat.new()
		portrait_border.bg_color = Color(0, 0, 0, 0)
		portrait_border.border_width_left = 1
		portrait_border.border_width_top = 1
		portrait_border.border_width_right = 1
		portrait_border.border_width_bottom = 1
		portrait_border.border_color = Color(color.r, color.g, color.b, 0.6)
		portrait_rect.add_theme_stylebox_override("normal", portrait_border)
		hbox.add_child(portrait_rect)

	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(text_vbox)

	var name_label := Label.new()
	name_label.text = npc_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_outline_size", 3)
	text_vbox.add_child(name_label)

	var line_label := Label.new()
	line_label.text = text
	line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	line_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_label.add_theme_font_size_override("font_size", 18)
	line_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	line_label.add_theme_constant_override("shadow_outline_size", 3)
	text_vbox.add_child(line_label)

	# Tween: 4.0s hold then 1.5s fade. Slightly longer than
	# show_hud_info (2.5s) because the player has more to read.
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(panel, "modulate:a", 0.0, 1.5)
	tween.tween_callback(panel.queue_free)

# Show a message inside the dock panel (between title and buttons).
# Used for "Hear Gossip" flavor lines and quest pickup responses —
# anything contextual to the dock that the player should see without
# looking at the screen edges or the corner HUD flash. Holds for
# ~7.0s (longer than show_npc_dialogue_popup's 4.0s because the
# player is staring at the dock menu anyway) then fades 1.5s and
# hides the slot. Rapid repeated calls replace the prior message:
# the active tween is killed and the slot re-populated.
#
# Pass npc_name="" + portrait=null for a generic system-style
# message (e.g. pickup success/failure) — the speaker row collapses
# and the line takes the full width.
func show_dock_message(text: String, npc_name: String = "", color: Color = Color(0.85, 0.85, 0.85), portrait: Texture2D = null) -> void:
	if not dock_message_slot or not is_instance_valid(dock_message_slot):
		return
	# Cancel any in-flight fade so a fresh message resets the timer.
	if dock_message_tween and dock_message_tween.is_valid():
		dock_message_tween.kill()
	dock_message_slot.modulate.a = 1.0

	# Tone guard for the on-screen text. The TTS path runs the same
	# rewrite inside play_dialogue_audio, so this keeps the on-screen
	# line and the spoken line in sync. Kaelen never reaches
	# show_dock_message (her lines go through agent_dialogue_label),
	# but the guard is a no-op for her voice anyway.
	# No voice_id is available here, so derive from npc_name via
	# GlobalState's minor-NPC registry. Falls back to neutral (i.e.
	# guard runs) if unknown.
	var display_voice: String = "voice.neutral.v1"
	if npc_name != "":
		var npc_data := GlobalState.get_minor_npc_data(npc_name)
		if not npc_data.is_empty():
			display_voice = str(
				npc_data.get(
					"voice_profile_id",
					"voice.neutral.v1"
				)
			)
	text = GlobalState.apply_tone_guard(text, display_voice)

	# Configure content.
	dock_message_line.text = text
	dock_message_line.modulate = color
	if npc_name != "":
		dock_message_name.text = npc_name
		dock_message_name.modulate = color
		dock_message_name.visible = true
	else:
		dock_message_name.visible = false
	if portrait:
		dock_message_portrait.texture = portrait
		# Subtle 1px border in the speaker color so the chip feels
		# tied to the speaker (matches the show_npc_dialogue_popup
		# chip styling).
		var portrait_border := StyleBoxFlat.new()
		portrait_border.bg_color = Color(0, 0, 0, 0)
		portrait_border.border_width_left = 1
		portrait_border.border_width_top = 1
		portrait_border.border_width_right = 1
		portrait_border.border_width_bottom = 1
		portrait_border.border_color = Color(color.r, color.g, color.b, 0.7)
		dock_message_portrait.add_theme_stylebox_override("normal", portrait_border)
		dock_message_portrait.visible = true
	else:
		dock_message_portrait.texture = null
		dock_message_portrait.visible = false

	dock_message_slot.visible = true

	# 7.0s hold + 1.5s fade. Long enough to read comfortably while
	# the player is docked, short enough that a stale message won't
	# linger after they tab away or undock quickly.
	dock_message_tween = create_tween()
	dock_message_tween.tween_interval(7.0)
	dock_message_tween.tween_property(dock_message_slot, "modulate:a", 0.0, 1.5)
	dock_message_tween.tween_callback(func() -> void:
		if is_instance_valid(dock_message_slot):
			dock_message_slot.visible = false
			dock_message_slot.modulate.a = 1.0
	)

# Clear the docked-message slot immediately. Called on submenu change
# and undock so an old flavor line or pickup response doesn't leak
# into a different context.
func clear_dock_message() -> void:
	if not dock_message_slot or not is_instance_valid(dock_message_slot):
		return
	if dock_message_tween and dock_message_tween.is_valid():
		dock_message_tween.kill()
	dock_message_slot.visible = false
	dock_message_slot.modulate.a = 1.0
	dock_message_line.text = ""
	dock_message_name.text = ""
	dock_message_name.visible = false
	dock_message_portrait.texture = null
	dock_message_portrait.visible = false

func _update_repair_button():
	if not repair_btn: return
	var p = GlobalState.player
	if not p or not is_instance_valid(p) or p.get("destroyed"):
		repair_btn.text = "Repair Ship (No ship detected)"
		repair_btn.disabled = true
		return
		
	var hp = p.get("health")
	var max_hp = p.get("max_health")
	var missing_hp = max_hp - hp
	
	if missing_hp <= 0.001:
		repair_btn.text = "Repair Ship (Fully Repaired)"
		repair_btn.disabled = true
	else:
		var cost_per_hp = 2.0
		var total_cost = int(missing_hp * cost_per_hp)
		
		if GlobalState.player_credits >= total_cost:
			repair_btn.text = "Repair Ship (Full Heal: %d HP) - %d SC" % [int(missing_hp), total_cost]
			repair_btn.disabled = false
		else:
			# Player cannot afford full heal
			var affordable_hp = int(GlobalState.player_credits / cost_per_hp)
			if affordable_hp > 0:
				repair_btn.text = "Repair Ship (Partial Heal: %d HP) - %d SC" % [affordable_hp, GlobalState.player_credits]
				repair_btn.disabled = false
			else:
				repair_btn.text = "Repair Ship (Insufficient Credits) - Need %d SC" % [total_cost]
				repair_btn.disabled = true

func _repair_ship():
	var p = GlobalState.player
	if not p or not is_instance_valid(p) or p.get("destroyed"):
		return
		
	var hp = p.get("health")
	var max_hp = p.get("max_health")
	var missing_hp = max_hp - hp
	
	if missing_hp <= 0.001:
		return
		
	var cost_per_hp = 2.0
	var total_cost = int(missing_hp * cost_per_hp)
	
	var repaired = false
	if GlobalState.player_credits >= total_cost:
		# Full repair
		GlobalState.player_credits -= total_cost
		p.set("health", max_hp)
		repaired = true
	else:
		# Partial repair
		var affordable_hp = int(GlobalState.player_credits / cost_per_hp)
		if affordable_hp > 0:
			var cost_paid = int(affordable_hp * cost_per_hp)
			GlobalState.player_credits -= cost_paid
			p.set("health", hp + affordable_hp)
			repaired = true
			
	if repaired:
		AudioManager.play_repair()
			
	# Update HUD and button state
	_update_hud_health()
	_update_repair_button()

func set_overview_collapsed(collapsed: bool):
	if overview_collapsed == collapsed: return
	overview_collapsed = collapsed
	
	if collapse_btn:
		collapse_btn.text = " ▼ " if overview_collapsed else " ▲ "
		
	if overview_collapsed:
		overview_panel.anchor_bottom = 0.18
	else:
		overview_panel.anchor_bottom = 0.65
		
	refresh_overview()

# Agent dialogue screen & Quest tracker HUD interactions
func _on_talk_to_agent_pressed():
	SpeechService.start_interaction("Talk to Agent")
	dock_panel.visible = false
	if inventory_panel:
		inventory_panel.visible = false
	if store_panel:
		store_panel.visible = false
	if public_board_panel:
		public_board_panel.visible = false
	agent_panel.visible = true

	# Clear previous choice buttons
	for child in agent_choices_container.get_children():
		child.queue_free()

	if not GlobalState.kaelen_briefing_seen:
		_show_kaelen_first_briefing()
		return

	if GlobalState.kaelen_briefing_seen and not GlobalState.kaelen_briefing_accepted:
		_show_kaelen_return_briefing()
		return

	if QuestManager.is_lane_occupied("AGENT"):
		var agent_mission = QuestManager.get_mission_collection().get_by_lane(
			MissionInstance.SourceLane.AGENT
		)
		QuestManager.get_mission_collection().focus(agent_mission.runtime_id)
		var q: Dictionary = agent_mission.data if agent_mission else {}
		var shown_agent_name := str(q.get("agent_name", "Broker Kaelen"))
		if bool(q.get("public_board", false)):
			shown_agent_name = "Broker Kaelen"
		agent_name_label.text = shown_agent_name.to_upper()
		agent_subtitle_label.text = str(q.get("agent_role", "Neutral Fixer & Profit Broker"))

		# Update portrait and client logo
		_update_agent_portrait(
			q.get("faction", "neutral"),
			shown_agent_name
		)
		
		var type_str := "Deliver Resources"
		if q["objective_type"] == "KILL_SHIPS":
			type_str = "Clear Hostiles"
		elif q["objective_type"] == "RECOVER_COMBAT_DROP":
			type_str = "Recover Data"
		var active_header := "Active Contract: "
		if bool(q.get("public_board", false)):
			active_header = "Public Board Job: "
		agent_dialogue_label.text = active_header + q["title"] + " (" + type_str + ")\n\n" + \
			"Briefing: " + q["dialogue"] + "\n\n" + \
			"Response choice accepted: '" + q["choice_text_selected"] + "'\n"
		if bool(q.get("public_board", false)):
			agent_dialogue_label.text += (
				"Local handler note: Kaelen can close the payout, but she did not post this mess."
			)
		else:
			agent_dialogue_label.text += "Agent feedback: '" + q["agent_response"] + "'"
			
		agent_back_btn.visible = true
		
		# Create Complete button (enabled if objectives met)
		var comp_btn = Button.new()
		if bool(q.get("public_board", false)):
			comp_btn.text = "Turn In Board Job To Local Agent"
		else:
			comp_btn.text = "Hand In Contract"
		comp_btn.disabled = not QuestManager.is_quest_completed()
		comp_btn.pressed.connect(_on_agent_complete_pressed)
		agent_choices_container.add_child(comp_btn)
		
		# Partial shipment button — ore quests only, when player has cargo but isn't done yet
		if q["objective_type"] == "DELIVER_ORE" and GlobalState.cargo_type == GlobalState.CargoType.ORE and GlobalState.cargo > 0.5 and not QuestManager.is_quest_completed():
			var banked = q.get("partial_delivered", 0.0)
			var remaining = q["amount_required"] - banked
			var deliverable = min(GlobalState.cargo, remaining)
			var partial_btn = Button.new()
			partial_btn.text = "Drop Off Partial Shipment (%.0f m³)" % deliverable
			partial_btn.pressed.connect(func(): _on_partial_delivery_pressed(deliverable))
			agent_choices_container.add_child(partial_btn)
		
		# Create Abandon button
		var abn_btn = Button.new()
		abn_btn.text = "Abandon Contract"
		abn_btn.pressed.connect(_on_agent_abandon_pressed)
		agent_choices_container.add_child(abn_btn)

	else:
		_refresh_agent_quest_board()

func _show_kaelen_first_briefing() -> void:
	agent_name_label.text = "BROKER KAELEN"
	agent_subtitle_label.text = "Neutral Fixer & Profit Broker"
	_update_agent_portrait("neutral")
	agent_back_btn.visible = true

	var briefing_lines: Array[String] = [
		"Well, well. Fresh hull, no record, and that desperate look pilots get when they realize fuel costs money. Sit down, Shiny.",
		"Name's Kaelen. I'm a broker. I connect people who need things done with people dumb enough to do them. That's you, by the way. I take a modest cut. Don't look at me like that. Modest by my standards.",
		"Here's how this works. Factions out here, Zenith, Aurelia, Vanguard, they all need grunt work handled. Deliveries, salvage, the occasional aggressive negotiation. They post contracts through me, I find a pilot, everybody gets paid. Simple.",
		"Now, that mining laser bolted to your ship. Technically, pulling ore without a faction permit is, let's call it frowned upon. Heavily. With fines. And guns.",
		"But permits cost more than your ship is worth, and I happen to know a few buyers who don't ask where the rocks came from. You mine it, I move it, we split the difference. Just don't get caught lingering in someone's claim. Faction patrols out here shoot first, file paperwork never.",
		"So, I've actually got someone who needs something handled right now. Interested?",
	]
	agent_dialogue_label.text = "\n\n".join(briefing_lines)
	SpeechService.play_sequential(briefing_lines, "voice.kaelen.v1")

	for child in agent_choices_container.get_children():
		child.queue_free()

	var accept_btn := Button.new()
	accept_btn.text = "Let's hear it."
	accept_btn.pressed.connect(func():
		SpeechService.stop()
		GlobalState.kaelen_briefing_seen = true
		GlobalState.kaelen_briefing_accepted = true
		for child in agent_choices_container.get_children():
			child.queue_free()
		_refresh_agent_quest_board()
	)
	agent_choices_container.add_child(accept_btn)

	var decline_btn := Button.new()
	decline_btn.text = "Not right now. I need to get my bearings first."
	decline_btn.pressed.connect(func():
		SpeechService.stop()
		GlobalState.kaelen_briefing_seen = true
		_on_agent_back_pressed()
	)
	agent_choices_container.add_child(decline_btn)


func _show_kaelen_return_briefing() -> void:
	agent_name_label.text = "BROKER KAELEN"
	agent_subtitle_label.text = "Neutral Fixer & Profit Broker"
	_update_agent_portrait("neutral")
	agent_back_btn.visible = true

	var line := (
		"Oh good, you're back. Got the sightseeing out of your system? " +
		"Good. Because credits don't earn themselves, — well, mine do, " +
		"but that's because, well I have you. Are you ready to make us some money?"
	)
	agent_dialogue_label.text = line
	SpeechService.play(line, "voice.kaelen.v1")

	for child in agent_choices_container.get_children():
		child.queue_free()

	var accept_btn := Button.new()
	accept_btn.text = "Yeah, let's do this."
	accept_btn.pressed.connect(func():
		GlobalState.kaelen_briefing_accepted = true
		for child in agent_choices_container.get_children():
			child.queue_free()
		_refresh_agent_quest_board()
	)
	agent_choices_container.add_child(accept_btn)

	var decline_btn := Button.new()
	decline_btn.text = "Still not ready."
	decline_btn.pressed.connect(func():
		_on_agent_back_pressed()
	)
	agent_choices_container.add_child(decline_btn)


func _refresh_agent_quest_board():
	agent_name_label.text = "BROKER KAELEN"
	agent_subtitle_label.text = "Neutral Fixer & Profit Broker"
	_update_agent_portrait("neutral")

	if not cached_quest_data.is_empty():
		# We already have a pre-cached quest! Show it immediately
		print("[TRACE] [UIManager] Pre-cached quest found. Loading board instantly.")
		_on_quest_generated_received(cached_quest_data, cached_quest_is_fallback)
	else:
		# Still loading or not started yet
		print("[TRACE] [UIManager] No pre-cached quest ready. Waiting for background generator...")
		agent_dialogue_label.text = "Broker Kaelen is checking client contract requests..."
		agent_back_btn.visible = false
		is_waiting_for_agent_board = true
		
		# If the background generator hasn't started yet, trigger it now.
		if not LLMInterface.is_waiting:
			_request_background_agent_quest()

func _on_background_quest_generated(quest_data: Dictionary, is_fallback: bool):
	cached_quest_data = quest_data
	cached_quest_is_fallback = is_fallback
	cached_unique_intro = ""  # Reset for new quest — old intro no longer applies
	print("[TRACE] [UIManager] Background quest generated. Faction: ", quest_data.get("faction", "neutral"), " is_fallback: ", is_fallback)
	
	if not quest_data.is_empty():
		var game_root := get_tree().current_scene
		if game_root and game_root.has_method(
			"apply_opening_campaign_name"
		):
			game_root.apply_opening_campaign_name(
				str(quest_data.get("campaign_name", "Far Horizon"))
			)
		if game_root and game_root.has_method("remember_generated_quest_idea"):
			game_root.remember_generated_quest_idea(quest_data, is_fallback)
		# Pre-cache main briefing TTS
		var dialogue = quest_data.get("dialogue", "")
		if dialogue != "":
			SpeechService.cache(dialogue, quest_data.get("faction", "neutral"))
			
		# Pre-cache choice response TTS
		var choices = quest_data.get("choices", [])
		for choice in choices:
			var response = choice.get("consequence", {}).get("dialogue_response", "")
			if response != "":
				SpeechService.cache(response, quest_data.get("faction", "neutral"))
		
		# Fire-and-forget LLM call for Kaelen's unique handoff intro. Runs in
		# the background while the player is still docking / loading. If it
		# doesn't return in time, _on_quest_generated_received falls back to
		# the canned 5-line array per agent. Skip in fallback mode — there's
		# no LLM to talk to.
		if not is_fallback:
			var agent_name = quest_data.get("agent_name", "Broker Kaelen")
			var faction = quest_data.get("faction", "neutral")
			var agent_history = QuestManager.filter_history_for_agent(agent_name, faction)
			LLMInterface.request_kaelen_intro(quest_data, agent_history, GlobalState.reputations, func(unique_line: String):
				if unique_line.strip_edges() == "":
					print("[TRACE] [UIManager] No unique intro available — will fall back to canned handoff.")
					cached_unique_intro = ""
					return
				cached_unique_intro = unique_line
				print("[TRACE] [UIManager] Cached unique Kaelen intro: ", unique_line.left(60), "...")
				# Pre-cache the TTS so playback is instant when the handoff fires
				SpeechService.cache(unique_line, "voice.kaelen.v1")
			)
				
	# Only push to agent board UI if the player is actually waiting for it
	# AND no quest is currently active (avoid replacing UI mid-mission)
	if is_waiting_for_agent_board and not QuestManager.is_lane_occupied("AGENT"):
		is_waiting_for_agent_board = false
		_on_quest_generated_received(cached_quest_data, cached_quest_is_fallback)
		
	# If loading panel is still visible, wait for TTS cache completion
	if loading_panel and is_instance_valid(loading_panel):
		SpeechService.cache_queue_completed.connect(_on_tts_cache_completed)
		if SpeechService.active_cache_requests <= 0:
			_on_tts_cache_completed()
		else:
			loading_bar.value = 80.0
			loading_status_label.text = "Pre-caching synthesized broker voice lines..."


func _on_quest_generated_received(quest_data: Dictionary, is_fallback: bool):
	var now = Time.get_ticks_msec()
	var elapsed_str = ""
	if SpeechService.last_interaction_time > 0.0:
		elapsed_str = " (Elapsed since '%s': %.3fs)" % [SpeechService.last_interaction_name, (now - SpeechService.last_interaction_time) / 1000.0]
	print("[TRACE] [UIManager] _on_quest_generated_received called%s is_fallback: %s" % [elapsed_str, str(is_fallback)])
	
	agent_back_btn.visible = true
	
	for child in agent_choices_container.get_children():
		child.queue_free()
		
	if quest_data.is_empty():
		agent_dialogue_label.text = "No contracts available right now. Check back later."
		return
	
	# ── Step 1: Kaelen introduces the quest giver ─────────────────────────────
	var agent_name = quest_data.get("agent_name", "Broker Kaelen")
	var faction    = quest_data.get("faction", "neutral")
	
	# Per-agent handoff line variations. These are sourced from LLMInterface
	# so the LLM prompt and the runtime fallback stay in sync — same lines
	# serve as few-shot examples for the model and as the offline fallback.
	var handoff_lines: Array = LLMInterface.get_handoff_examples_for_agent(agent_name)
	
	var handoff_line: String
	if cached_unique_intro.strip_edges() != "":
		# LLM successfully generated a unique handoff — use it
		handoff_line = cached_unique_intro
		print("[TRACE] [UIManager] Using unique LLM-generated handoff for: ", agent_name)
	else:
		# No unique intro ready (LLM offline, slow, or this is a fallback quest)
		# — fall back to one of the canned 5 lines for this agent.
		handoff_line = handoff_lines[randi() % handoff_lines.size()]
		print("[TRACE] [UIManager] Using canned handoff fallback for: ", agent_name)
	
	# Flash incoming call notification in the chat bar
	add_chat_message("COMMS", "Incoming voice transmission...", Color(0.0, 0.9, 0.9))

	# Show Kaelen with her handoff intro first
	agent_name_label.text = "BROKER KAELEN"
	agent_subtitle_label.text = "Neutral Fixer & Profit Broker"
	_update_agent_portrait("neutral")
	agent_dialogue_label.text = handoff_line
	agent_back_btn.visible = true

	# Play Kaelen's intro line in her voice
	SpeechService.play(handoff_line, "voice.kaelen.v1")
	
	# Add a "Bring them in" button that transitions to the actual quest giver
	var bring_in_btn = Button.new()
	bring_in_btn.text = "[ Bring them in ]"
	bring_in_btn.pressed.connect(func():
		# Clear the handoff button
		for child in agent_choices_container.get_children():
			child.queue_free()
		# Transition to the actual quest giver
		_show_quest_briefing(quest_data, is_fallback)
	)
	agent_choices_container.add_child(bring_in_btn)

	if GateDiscovery:
		GateDiscovery.seed_kaelen_gate_rumor_if_ready()
	if GateDiscovery and GateDiscovery.is_kaelen_gate_eligible():
		var revealable := GateDiscovery.get_revealable_gates()
		if not revealable.is_empty():
			var gate_id: String = revealable[0]
			var cost: int = GateDiscovery.get_kaelen_reveal_cost(gate_id)
			var intel_btn := Button.new()
			intel_btn.text = "[ Ask about new routes — %d SC ]" % cost
			intel_btn.pressed.connect(func():
				_kaelen_gate_reveal(gate_id, cost)
			)
			agent_choices_container.add_child(intel_btn)


func _add_kaelen_gate_intel_button() -> void:
	if GateDiscovery:
		GateDiscovery.seed_kaelen_gate_rumor_if_ready()
	if not GateDiscovery or not GateDiscovery.is_kaelen_gate_eligible():
		return
	var revealable := GateDiscovery.get_revealable_gates()
	if revealable.is_empty():
		return
	var gate_id: String = revealable[0]
	var cost: int = GateDiscovery.get_kaelen_reveal_cost(gate_id)
	var intel_btn := Button.new()
	intel_btn.text = "[ Ask about new routes - %d SC ]" % cost
	intel_btn.pressed.connect(func():
		_kaelen_gate_reveal(gate_id, cost)
	)
	agent_choices_container.add_child(intel_btn)


func _kaelen_gate_reveal(gate_id: String, cost: int) -> void:
	var result := GateDiscovery.kaelen_reveal(gate_id, cost)
	if result.get("ok", false):
		agent_dialogue_label.text = (
			"\"I've got a contact who owes me — they mapped a route "
			+ "nobody else has charted. It's yours now. Gate coordinates uploaded to your nav system.\""
		)
		SpeechService.play(agent_dialogue_label.text, "voice.kaelen.v1")
		show_hud_info("New route unlocked — check your map.", Color(0.2, 0.9, 0.6))
		for child in agent_choices_container.get_children():
			child.queue_free()
		var back_btn := Button.new()
		back_btn.text = "[ Thanks, Kaelen ]"
		back_btn.pressed.connect(func():
			agent_panel.visible = false
			dock_panel.visible = true
		)
		agent_choices_container.add_child(back_btn)
	else:
		show_hud_warning(str(result.get("error", "Kaelen can't help with that right now.")))


func _show_quest_briefing(quest_data: Dictionary, is_fallback: bool):
	# ── Step 2: The quest giver delivers their briefing ───────────────────────
	var raw_dialogue = quest_data.get("dialogue", "")
	var display_dialogue = SpeechService.clean_dialogue_text(raw_dialogue)
	var note = " [Offline Backup]" if is_fallback else ""
	
	agent_name_label.text = quest_data.get("agent_name", "Broker Kaelen").to_upper()
	agent_subtitle_label.text = str(quest_data.get("agent_role", "Neutral Fixer & Profit Broker"))
	var agent_name := str(quest_data.get("agent_name", "Broker Kaelen"))
	_update_agent_portrait(
		quest_data.get("faction", "neutral"),
		agent_name
	)
	agent_dialogue_label.text = display_dialogue + note
	
	# Play the quest giver's briefing voice
	SpeechService.play_for_npc(
		quest_data.get("dialogue", ""),
		agent_name
	)
	
	# Append contract details block
	var f_client = quest_data.get("faction", "neutral").to_upper()
	var obj = quest_data.get("objective", {})
	var obj_type = obj.get("type", "UNKNOWN")
	var amt_info = ""
	if obj_type == "DELIVER_ORE":
		amt_info = str(int(obj.get("amount_required", 20))) + " m³ Ore"
	elif obj_type == "KILL_SHIPS":
		var target_fac = obj.get("target_faction", "zenith").to_upper()
		amt_info = "Destroy " + str(obj.get("count_required", 3)) + " " + target_fac + " ships"
	elif obj_type == "PICKUP_SPECIAL":
		amt_info = "Pick up " + str(obj.get("part_name", "the package"))
	elif obj_type == "RECOVER_COMBAT_DROP":
		amt_info = "Recover %s from %s wreckage" % [
			str(obj.get("item_name", "the data pack")),
			str(obj.get("target_faction", "hostile")).to_upper(),
		]
	var validated_summary := str(quest_data.get("objective_summary", ""))
	if not validated_summary.is_empty():
		amt_info = validated_summary
		
	agent_dialogue_label.text += "\n\n--- Contract Details ---\n" + \
		"Client: " + f_client + "\n" + \
		"Objective: " + amt_info + "\n" + \
		"Base Reward: " + str(obj.get("reward_credits", 150)) + " SC"
	
	# Add player choice buttons
	var choices = quest_data.get("choices", [])
	for choice in choices:
		var choice_btn = Button.new()
		choice_btn.text = choice.get("text", "Accept Option")
		choice_btn.pressed.connect(func(): _on_choice_selected(quest_data, choice))
		agent_choices_container.add_child(choice_btn)



func _on_choice_selected(quest_data: Dictionary, choice: Dictionary):
	SpeechService.start_interaction("Select Choice: " + choice.get("text", ""))
	
	cached_quest_data = {}
	cached_quest_is_fallback = false
	is_waiting_for_agent_board = false
	
	# Clear choices container
	for child in agent_choices_container.get_children():
		child.queue_free()
		
	# Accept quest
	if not QuestManager.accept_quest(quest_data, choice):
		print("[UIManager] ⚠ QUEST REJECTED — reason: %s" % QuestManager.last_validation_error)
		print("[UIManager] ⚠ QUEST DATA: %s" % JSON.stringify(quest_data))
		agent_dialogue_label.text = (
			"Contract data failed verification. Kaelen has rejected the offer."
		)
		SpeechService.play(
			"That contract is broken, Shiny. I'm not putting your name on it.",
			"voice.kaelen.v1"
		)
		var return_btn := Button.new()
		return_btn.text = "Back to Services"
		return_btn.pressed.connect(_on_agent_back_pressed)
		agent_choices_container.add_child(return_btn)
		return
	
	if quest_data.get("objective", {}).get("type", "") == "PICKUP_SPECIAL":
		var npc_name = quest_data["objective"].get("target_npc", "unknown")
		var part_name = quest_data["objective"].get("part_name", "the part")
		var outpost_display = quest_data["objective"].get("target_outpost_display", "the outpost")
		var client_name = quest_data.get("agent_name", "the client")
		_request_outpost_pickup_handoff_attempt(npc_name, part_name, outpost_display, client_name, "", 0)
	
	var consequence = choice.get("consequence", {})
	var raw_response = consequence.get("dialogue_response", "")
	var response_voice_ref = quest_data.get(
		"agent_name",
		quest_data.get("faction", "neutral")
	)
	var response_profile := SpeechService.resolve_voice_profile(response_voice_ref)
	var clean_response = SpeechService.prepare_followup_text(
		raw_response,
		response_profile
	)
	# Safety net: if cleaning stripped everything (entire string was stage direction), use a fallback
	if clean_response.length() < 5:
		clean_response = LLMInterface.fallback_completion_lines[randi() % LLMInterface.fallback_completion_lines.size()]
		print("[TRACE] [UIManager] dialogue_response was empty after cleaning, using fallback.")
	agent_dialogue_label.text = clean_response
	
	# Play choice response voice audio (TTS also cleans internally)
	SpeechService.play(clean_response, response_profile)
	
	agent_back_btn.visible = false
	
	# Create undock confirmation button
	var launch_btn = Button.new()
	launch_btn.text = "Undock & Begin Mission"
	launch_btn.pressed.connect(undock_player)
	agent_choices_container.add_child(launch_btn)
	
	# Start pre-caching the NEXT quest immediately in the background
	print("[TRACE] [UIManager] Quest accepted. Starting pre-caching of the next contract.")
	_request_background_agent_quest()
	
	# Generate unique Kaelen completion/abandon lines for THIS quest in the background
	cached_completion_line = ""
	cached_abandon_line = ""
	print("[TRACE] [UIManager] Requesting unique Kaelen reaction lines for: ", quest_data.get("title", "quest"))
	LLMInterface.request_kaelen_reaction(quest_data, func(comp_line: String, abn_line: String):
		cached_completion_line = comp_line
		cached_abandon_line = abn_line
		print("[TRACE] [UIManager] Kaelen reactions ready. Caching TTS...")
		# Pre-cache both in the background using neutral (Kaelen's) voice
		SpeechService.cache(comp_line, "voice.kaelen.v1")
		SpeechService.cache(abn_line, "voice.kaelen.v1")
	)

func _on_agent_back_pressed():
	# Stop voice dialogue audio
	SpeechService.stop()
	agent_panel.visible = false
	dock_panel.visible = true

func _on_agent_complete_pressed():
	SpeechService.start_interaction("Complete Contract")
	
	is_waiting_for_agent_board = false
	var completed_quest: Dictionary = QuestManager.active_quest.duplicate(true)
	
	for child in agent_choices_container.get_children():
		child.queue_free()
	
	QuestManager.complete_quest()
	
	# Switch to Kaelen's portrait — she's the one paying out, not the quest giver
	agent_name_label.text = "BROKER KAELEN"
	agent_subtitle_label.text = "Neutral Fixer & Profit Broker"
	_update_agent_portrait("neutral")
	
	# Use the pre-generated contextual line, fall back to a random one if not ready
	var completion_text = cached_completion_line
	if bool(completed_quest.get("public_board", false)):
		completion_text = str(
			completed_quest.get("public_board_turn_in_line", "")
		)
	if completion_text == "":
		completion_text = LLMInterface.fallback_completion_lines[randi() % LLMInterface.fallback_completion_lines.size()]
		print("[TRACE] [UIManager] Kaelen completion line not ready, using random fallback.")
	cached_completion_line = ""
	cached_abandon_line = ""
	
	agent_dialogue_label.text = completion_text
	SpeechService.play(completion_text, "voice.kaelen.v1")
	agent_back_btn.visible = true
	_add_kaelen_gate_intel_button()
	
	# If for some reason the cache is empty, request one now
	if cached_quest_data.is_empty() and not LLMInterface.is_waiting:
		print("[TRACE] [UIManager] Cache empty on complete. Pre-caching next quest.")
		_request_background_agent_quest()

func _on_agent_abandon_pressed():
	SpeechService.start_interaction("Abandon Contract")
	
	is_waiting_for_agent_board = false
	
	for child in agent_choices_container.get_children():
		child.queue_free()
	
	QuestManager.abandon_quest()
	
	# Switch to Kaelen's portrait — she's the one chewing you out, not the quest giver
	agent_name_label.text = "BROKER KAELEN"
	agent_subtitle_label.text = "Neutral Fixer & Profit Broker"
	_update_agent_portrait("neutral")
	
	# Use the pre-generated contextual line, fall back to a random one if not ready
	var abandon_text = cached_abandon_line
	if abandon_text == "":
		abandon_text = LLMInterface.fallback_abandon_lines[randi() % LLMInterface.fallback_abandon_lines.size()]
		print("[TRACE] [UIManager] Kaelen abandon line not ready, using random fallback.")
	cached_completion_line = ""
	cached_abandon_line = ""
	
	agent_dialogue_label.text = abandon_text
	SpeechService.play(abandon_text, "voice.kaelen.v1")
	agent_back_btn.visible = true
	
	# If for some reason the cache is empty, request one now
	if cached_quest_data.is_empty() and not LLMInterface.is_waiting:
		print("[TRACE] [UIManager] Cache empty on abandon. Pre-caching next quest.")
		_request_background_agent_quest()

func _on_partial_delivery_pressed(deliverable: float):
	SpeechService.start_interaction("Partial Delivery")
	
	# Clear buttons immediately to prevent double-tap
	for child in agent_choices_container.get_children():
		child.queue_free()
	
	# Bank the ore via QuestManager (deducts cargo, adds to partial_delivered)
	var q = QuestManager.active_quest
	var actually_delivered = QuestManager.deliver_partial(deliverable)
	if actually_delivered <= 0.0:
		_on_talk_to_agent_pressed()
		return
	
	var total_banked = q.get("partial_delivered", 0.0)
	var required = q.get("amount_required", 1.0)
	var quest_title = q.get("title", "the contract")
	
	# Switch to Kaelen portrait while fetching her reaction
	agent_name_label.text = "BROKER KAELEN"
	agent_subtitle_label.text = "Neutral Fixer & Profit Broker"
	_update_agent_portrait("neutral")
	agent_dialogue_label.text = "Logging your shipment... stand by."
	agent_back_btn.visible = false
	
	# Request unique Kaelen reaction from LLM
	LLMInterface.request_partial_delivery_line(
		quest_title, actually_delivered, total_banked, required,
		func(line: String):
			var clean = SpeechService.clean_dialogue_text(line)
			agent_dialogue_label.text = clean
			SpeechService.play(clean, "voice.kaelen.v1")
			
			# Add back button so player can undock or check contract
			var back_btn = Button.new()
			back_btn.text = "Back to Services"
			back_btn.pressed.connect(func():
				SpeechService.stop()
				agent_panel.visible = false
				dock_panel.visible = true
			)
			agent_choices_container.add_child(back_btn)
			agent_back_btn.visible = true
	)



func _on_quest_accepted():
	_update_quest_tracker()

func _on_quest_progress_updated():
	_update_quest_tracker()

func _on_quest_completed():
	_update_quest_tracker()

func _on_quest_abandoned():
	_update_quest_tracker()

func _on_quest_expired(title: String) -> void:
	_update_quest_tracker()
	GlobalState.emit_chatter(
		"SYSTEM",
		"Contract expired: %s." % title,
		Color(1.0, 0.55, 0.25)
	)

func _update_quest_tracker():
	if not QuestManager.is_quest_active():
		quest_tracker_panel.visible = false
		if quest_tracker_turn_in_btn:
			quest_tracker_turn_in_btn.visible = false
		return

	quest_tracker_panel.visible = true
	var q = QuestManager.active_quest
	quest_tracker_title.text = q.get("title", "Contract")

	_update_quest_tracker_nav(q)
	_update_quest_tracker_logo(q.get("faction", "neutral"))

	var _cap = MissionCapabilityRegistry.get_for_type(q.get("objective_type", ""))
	if _cap:
		quest_tracker_progress.text = _cap.format_tracker_text(q)
	else:
		quest_tracker_progress.text = q.get("objective_type", "Unknown")
	if QuestManager.is_active_quest_timed():
		var remaining := QuestManager.get_active_quest_remaining_minutes()
		var urgency := "URGENT" if q.get("is_urgent", false) else "TIMED"
		var payout := QuestManager.active_quest_payout()
		quest_tracker_progress.text += "\n%s: %s remaining | Payout: %d SC" % [
			urgency,
			CampaignClock.format_duration(remaining),
			payout,
		]
	_update_quest_tracker_turn_in_button(q)
	_update_quest_tracker_secondary_missions()


func _update_quest_tracker_nav(q: Dictionary) -> void:
	var collection = QuestManager.get_mission_collection()
	var all_active = collection.get_all_active()
	var count := all_active.size()
	var show_arrows := count > 1
	if quest_tracker_prev_btn:
		quest_tracker_prev_btn.visible = show_arrows
	if quest_tracker_next_btn:
		quest_tracker_next_btn.visible = show_arrows
	if quest_tracker_nav_label:
		if count <= 1:
			var lane_label := "ACTIVE CONTRACT"
			if bool(q.get("public_board", false)):
				lane_label = "BOARD JOB"
			elif bool(q.get("station_errand", false)):
				lane_label = "STATION ERRAND"
			quest_tracker_nav_label.text = lane_label
		else:
			var focused = collection.get_focused()
			var idx := 0
			for i in range(all_active.size()):
				if focused and all_active[i].runtime_id == focused.runtime_id:
					idx = i
					break
			var lane_tag := "CONTRACT"
			if bool(q.get("public_board", false)):
				lane_tag = "BOARD"
			elif bool(q.get("station_errand", false)):
				lane_tag = "ERRAND"
			quest_tracker_nav_label.text = "%s  (%d/%d)" % [lane_tag, idx + 1, count]


func _on_quest_tracker_prev() -> void:
	var collection = QuestManager.get_mission_collection()
	var all_active = collection.get_all_active()
	if all_active.size() <= 1:
		return
	var focused = collection.get_focused()
	var idx := 0
	for i in range(all_active.size()):
		if focused and all_active[i].runtime_id == focused.runtime_id:
			idx = i
			break
	var prev_idx := (idx - 1) % all_active.size()
	collection.focus(all_active[prev_idx].runtime_id)
	_update_quest_tracker()


func _on_quest_tracker_next() -> void:
	var collection = QuestManager.get_mission_collection()
	var all_active = collection.get_all_active()
	if all_active.size() <= 1:
		return
	var focused = collection.get_focused()
	var idx := 0
	for i in range(all_active.size()):
		if focused and all_active[i].runtime_id == focused.runtime_id:
			idx = i
			break
	var next_idx := (idx + 1) % all_active.size()
	collection.focus(all_active[next_idx].runtime_id)
	_update_quest_tracker()


func _update_quest_tracker_turn_in_button(q: Dictionary) -> void:
	if not quest_tracker_turn_in_btn:
		return
	var is_public_board := bool(q.get("public_board", false))
	var is_ready := QuestManager.is_quest_completed()
	quest_tracker_turn_in_btn.visible = is_public_board and is_ready
	if not quest_tracker_turn_in_btn.visible:
		return
	if current_station and is_instance_valid(current_station):
		quest_tracker_turn_in_btn.text = "Turn In To Local Agent"
		quest_tracker_turn_in_btn.disabled = false
	else:
		quest_tracker_turn_in_btn.text = "Dock To Turn In"
		quest_tracker_turn_in_btn.disabled = true


func _update_quest_tracker_secondary_missions() -> void:
	if not quest_tracker_secondary_container:
		return
	for child in quest_tracker_secondary_container.get_children():
		child.queue_free()
	var collection = QuestManager.get_mission_collection()
	var all_active = collection.get_all_active()
	if all_active.size() <= 1:
		return
	var focused = collection.get_focused()
	var focused_id: String = focused.runtime_id if focused else ""

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	quest_tracker_secondary_container.add_child(sep)

	var header := Label.new()
	header.text = "%d OTHER MISSION%s  (click to switch)" % [
		all_active.size() - 1,
		"S" if all_active.size() > 2 else "",
	]
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(0.5, 0.7, 0.7))
	quest_tracker_secondary_container.add_child(header)

	for m in all_active:
		if m.runtime_id == focused_id:
			continue
		var lane_color := Color(0.0, 0.85, 0.85)
		var lane_tag := "CONTRACT"
		match m.source_lane:
			MissionInstance.SourceLane.BOARD:
				lane_color = Color(0.2, 0.8, 0.4)
				lane_tag = "BOARD"
			MissionInstance.SourceLane.STATION:
				lane_color = Color(0.9, 0.7, 0.2)
				lane_tag = "ERRAND"

		var row := PanelContainer.new()
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color(0.08, 0.12, 0.14, 0.9)
		row_style.border_width_left = 3
		row_style.border_color = lane_color
		row_style.content_margin_left = 8
		row_style.content_margin_right = 6
		row_style.content_margin_top = 4
		row_style.content_margin_bottom = 4
		row_style.corner_radius_top_left = 2
		row_style.corner_radius_bottom_left = 2
		row.add_theme_stylebox_override("panel", row_style)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 1)
		row.add_child(vbox)

		var tag_label := Label.new()
		tag_label.text = lane_tag
		tag_label.add_theme_font_size_override("font_size", 9)
		tag_label.add_theme_color_override("font_color", lane_color)
		vbox.add_child(tag_label)

		var cap = MissionCapabilityRegistry.get_for_type(m.data.get("objective_type", ""))
		var title_text: String = str(m.data.get("title", "Mission"))
		if cap and cap.is_completed(m.data):
			title_text += "  [READY]"
		var title_label := Label.new()
		title_label.text = title_text
		title_label.add_theme_font_size_override("font_size", 12)
		title_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.9))
		title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(title_label)

		if cap:
			var progress_label := Label.new()
			progress_label.text = cap.format_tracker_text(m.data)
			progress_label.add_theme_font_size_override("font_size", 10)
			progress_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.7))
			progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vbox.add_child(progress_label)

		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		click_btn.anchor_right = 1.0
		click_btn.anchor_bottom = 1.0
		click_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		click_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color(lane_color.r, lane_color.g, lane_color.b, 0.1)
		click_btn.add_theme_stylebox_override("hover", hover_style)
		var rid: String = m.runtime_id
		click_btn.pressed.connect(func():
			QuestManager.get_mission_collection().focus(rid)
			_update_quest_tracker()
		)
		row.add_child(click_btn)

		quest_tracker_secondary_container.add_child(row)


func _on_quest_tracker_turn_in_pressed() -> void:
	if not _should_show_public_board_turn_in():
		return
	if not current_station or not is_instance_valid(current_station):
		show_hud_warning("Dock at a local station to turn in this board job.")
		return
	var board_mission = QuestManager.get_mission_collection().get_by_lane(
		MissionInstance.SourceLane.BOARD
	)
	if board_mission:
		QuestManager.get_mission_collection().focus(board_mission.runtime_id)
	dock_panel.visible = false
	agent_panel.visible = true
	_on_agent_complete_pressed()


func _update_quest_tracker_logo(faction: String):
	if quest_tracker_logo and faction_branding_sheet:
		var atlas = AtlasTexture.new()
		atlas.atlas = faction_branding_sheet
		
		var col = 0
		var show_logo = true
		match faction.to_lower():
			"zenith": col = 0
			"aurelia": col = 1
			"vanguard": col = 2
			_: show_logo = false
			
		if show_logo:
			atlas.region = Rect2(col * 512, 0, 512, 512)
			quest_tracker_logo.texture = atlas
			quest_tracker_logo.visible = true
		else:
			quest_tracker_logo.visible = false

func _create_comms_hail_panel() -> void:
	comms_hail_panel = PanelContainer.new()
	comms_hail_panel.anchor_left = 0.2
	comms_hail_panel.anchor_right = 0.8
	comms_hail_panel.anchor_top = 0.25
	comms_hail_panel.anchor_bottom = 0.25
	comms_hail_panel.grow_vertical = Control.GROW_DIRECTION_END
	comms_hail_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(comms_hail_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.02, 0.02, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.35, 0.15, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	comms_hail_panel.add_theme_stylebox_override("panel", style)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 8)
	comms_hail_panel.add_child(outer_vbox)

	var header := Label.new()
	header.text = "INCOMING TRANSMISSION"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	outer_vbox.add_child(header)

	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 12)
	outer_vbox.add_child(content_hbox)

	comms_hail_portrait = TextureRect.new()
	comms_hail_portrait.custom_minimum_size = Vector2(64, 64)
	comms_hail_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	comms_hail_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	comms_hail_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content_hbox.add_child(comms_hail_portrait)

	comms_hail_message = Label.new()
	comms_hail_message.text = ""
	comms_hail_message.add_theme_font_size_override("font_size", 13)
	comms_hail_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	comms_hail_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(comms_hail_message)

	comms_hail_choices_container = VBoxContainer.new()
	comms_hail_choices_container.add_theme_constant_override("separation", 4)
	outer_vbox.add_child(comms_hail_choices_container)

	comms_hail_panel.visible = false


func _on_comms_reversal_triggered(mission_data: Dictionary) -> void:
	var faction: String = str(mission_data.get("target_faction", ""))
	add_chat_message(
		"COMMS",
		"Incoming voice transmission...",
		Color(1.0, 0.4, 0.2)
	)
	var timer := get_tree().create_timer(1.0)
	var data_copy := mission_data.duplicate(true)
	timer.timeout.connect(func(): _show_comms_hail(data_copy))


func _show_comms_hail(mission_data: Dictionary) -> void:
	var faction: String = str(mission_data.get("target_faction", ""))
	var comms_line: String = str(mission_data.get("comms_reversal_line", ""))
	if comms_line.is_empty():
		comms_line = _fallback_comms_line(faction)

	comms_hail_message.text = comms_line

	var portrait_tex: Texture2D = null
	var faction_def = GameContentRegistry.shared().faction(faction)
	if faction_def and not faction_def.agent_portrait_id.is_empty():
		portrait_tex = GameContentRegistry.shared().portrait_texture(faction_def.agent_portrait_id)
	if portrait_tex:
		comms_hail_portrait.texture = portrait_tex
		comms_hail_portrait.visible = true
	else:
		comms_hail_portrait.visible = false

	for child in comms_hail_choices_container.get_children():
		child.queue_free()

	var bribe: int = int(mission_data.get("bribe_amount", 0))
	var choices := [
		{"id": "finish_kill", "text": "Finish the job.", "color": Color(1.0, 0.4, 0.3)},
		{"id": "accept_bribe", "text": "Take the deal. (+%d SC)" % bribe, "color": Color(0.3, 0.9, 0.4)},
		{"id": "walk_away", "text": "Walk away. No payout.", "color": Color(0.6, 0.6, 0.6)},
	]
	for choice in choices:
		var btn := Button.new()
		btn.text = str(choice["text"])
		btn.add_theme_color_override("font_color", choice["color"])
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		var branch_id: String = str(choice["id"])
		btn.pressed.connect(func():
			_resolve_comms_hail(branch_id)
		)
		comms_hail_choices_container.add_child(btn)

	comms_hail_panel.visible = true

	SpeechService.play(comms_line, faction)


func _resolve_comms_hail(branch_id: String) -> void:
	comms_hail_panel.visible = false
	SpeechService.stop()
	QuestManager.resolve_comms_branch(branch_id)

	var result_msg := ""
	match branch_id:
		"finish_kill":
			result_msg = "Transmission rejected. Target re-engaged."
		"accept_bribe":
			result_msg = "Deal accepted. Target departing the area."
		"walk_away":
			result_msg = "Contract voided. Target departing the area."
	add_chat_message("COMMS", result_msg, Color(1.0, 0.55, 0.25))


const COMMS_REVERSAL_FALLBACKS: Array[String] = [
	"Wait! Before you pull that trigger — I'm not what they told you. That posting was a setup. I have information worth more than whatever they're paying you. Let me make you a counter-offer.",
	"Hold fire! You've been lied to, pilot. The person who posted that contract? They're the criminal here. I was investigating them. I can pay you more than they offered — and you'd be on the right side of this.",
	"Stop! I surrender! Look, I know how this looks, but that contract is a fraud. The poster used you to do their dirty work. I'll pay you to walk away. Better deal than blood money.",
	"Cease fire! Listen — I'm carrying evidence that would embarrass the person who hired you. That's why they want me dead. Name your price. Whatever they're paying, I can beat it, and you don't have to live with this.",
]


func _fallback_comms_line(faction: String) -> String:
	return COMMS_REVERSAL_FALLBACKS[randi() % COMMS_REVERSAL_FALLBACKS.size()]


func _update_agent_portrait(faction: String, npc_name: String = ""):
	if agent_portrait:
		_show_agent_portrait(true)
		var portrait_id := "portrait.quest_givers.kaelen"
		var generated_portrait := GlobalState.get_minor_npc_portrait(npc_name)
		var npc_definition := GameContentRegistry.shared().npc_by_name(npc_name)
		var faction_definition := GameContentRegistry.shared().faction(faction)
		if generated_portrait != null:
			agent_portrait.texture = generated_portrait
		elif npc_definition != null:
			portrait_id = str(npc_definition.portrait_id)
			agent_portrait.texture = GameContentRegistry.shared().portrait_texture(
				portrait_id
			)
		elif faction_definition and not faction_definition.agent_portrait_id.is_empty():
			portrait_id = str(faction_definition.agent_portrait_id)
			agent_portrait.texture = GameContentRegistry.shared().portrait_texture(
				portrait_id
			)
		else:
			agent_portrait.texture = GameContentRegistry.shared().portrait_texture(
				portrait_id
			)
		
	if agent_client_logo and faction_branding_sheet:
		var atlas = AtlasTexture.new()
		atlas.atlas = faction_branding_sheet
		
		var col = 0
		var show_logo = true
		match faction.to_lower():
			"zenith": col = 0
			"aurelia": col = 1
			"vanguard": col = 2
			_: show_logo = false
			
		if show_logo:
			atlas.region = Rect2(col * 512, 0, 512, 512)
			agent_client_logo.texture = atlas
			agent_client_logo.visible = true
		else:
			agent_client_logo.visible = false


func _show_agent_portrait(should_show: bool) -> void:
	if agent_portrait_column:
		agent_portrait_column.visible = should_show
	if not agent_portrait:
		return
	agent_portrait.visible = should_show
	if not should_show:
		agent_portrait.texture = null

func add_chat_message(sender: String, message: String, sender_color: Color):
	if not chat_vbox:
		return
		
	var msg_label = RichTextLabel.new()
	msg_label.bbcode_enabled = true
	msg_label.fit_content = true
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_label.add_theme_font_size_override("normal_font_size", 12)
	
	var color_hex = sender_color.to_html(false)
	msg_label.text = "[color=#%s][b]%s:[/b][/color] %s" % [color_hex, sender, message]
	
	chat_vbox.add_child(msg_label)
	
	while chat_vbox.get_child_count() > max_chat_messages:
		var first = chat_vbox.get_child(0)
		first.queue_free()
		chat_vbox.remove_child(first)
		
	await get_tree().process_frame
	if chat_scroll:
		chat_scroll.scroll_vertical = int(chat_vbox.size.y)

# ── Mechanic Pickup Button Handlers ──────────────────────────────────────────

func _on_mechanic_pickup_accept_pressed() -> void:
	if not _mechanic_pickup_offer.get("offer", false):
		return
	var part_name = _mechanic_pickup_offer["part_name"]
	var npc_name = _mechanic_pickup_offer["npc_name"]
	var outpost_id = _mechanic_pickup_offer["outpost_id"]
	var outpost_display = _mechanic_pickup_offer["outpost_display"]
	var reward = _mechanic_pickup_offer["reward_credits"]
	
	var quest_data: Dictionary = {
		"title": "Parts Run: %s" % part_name,
		"faction": "neutral",
		"agent_name": "Jenna Kross",
		"station_errand": true,
		"dialogue": "Head to %s and pick up the %s from %s. Bring it back here." % [outpost_display, part_name, npc_name],
		"objective": {
			"type": "PICKUP_SPECIAL",
			"target_outpost": outpost_id,
			"target_outpost_display": outpost_display,
			"target_npc": npc_name,
			"part_name": part_name,
			"destination": "Grease Monkeys",
			"reward_credits": reward,
		},
	}
	var selected_choice: Dictionary = {
		"text": "I'll take it.",
		"consequence": {},
	}
	QuestManager.accept_quest(quest_data, selected_choice)
	
	_mechanic_pickup_declined = false
	if mechanic_pickup_accept_btn and is_instance_valid(mechanic_pickup_accept_btn):
		mechanic_pickup_accept_btn.visible = false
	if mechanic_pickup_decline_btn and is_instance_valid(mechanic_pickup_decline_btn):
		mechanic_pickup_decline_btn.visible = false
		
	# Kick off the LLM call to generate the outpost contact's handoff line.
	# The line is cached on the quest dict via QuestManager.set_pickup_handoff.
	_request_outpost_pickup_handoff_attempt(npc_name, part_name, outpost_display, "Jenna Kross", "", 0)

func _on_mechanic_pickup_decline_pressed() -> void:
	_mechanic_pickup_declined = true
	if mechanic_pickup_accept_btn and is_instance_valid(mechanic_pickup_accept_btn):
		mechanic_pickup_accept_btn.visible = false
	if mechanic_pickup_decline_btn and is_instance_valid(mechanic_pickup_decline_btn):
		mechanic_pickup_decline_btn.visible = false

# ── Outpost Pickup Button Handlers ───────────────────────────────────────────

func _on_ask_for_part_pressed() -> void:
	var station_quest_ask: Dictionary = QuestManager.get_pickup_special_data()
	if station_quest_ask.is_empty():
		show_dock_message(
			"No active pickup job is waiting here.",
			"",
			Color(1.0, 0.45, 0.45)
		)
		return
	if station_quest_ask.get("picked_up", false):
		show_dock_message(
			"You already have the part. Take it back to Grease Monkeys.",
			"",
			Color(0.85, 0.85, 0.85)
		)
		return
	if not current_station or not is_instance_valid(current_station):
		show_dock_message("No station docked.", "", Color(1.0, 0.45, 0.45))
		return
	var docked_outpost_id: String = OUTPOST_NODE_TO_ID.get(current_station.name, "")
	if docked_outpost_id == "":
		docked_outpost_id = GlobalState.resolve_outpost_id(current_station)
	if docked_outpost_id == "":
		show_dock_message(
			"That contact is at an outpost, not this dock.",
			"",
			Color(1.0, 0.45, 0.45)
		)
		return
	var quest_outpost_id: String = str(QuestManager.active_quest.get("target_outpost", ""))
	if docked_outpost_id != quest_outpost_id:
		show_dock_message(
			"Wrong outpost. This pickup is waiting at %s." % str(
				QuestManager.active_quest.get(
					"target_outpost_display",
					quest_outpost_id
				)
			),
			"",
			Color(1.0, 0.45, 0.45)
		)
		return
	if GlobalState.cargo_type == GlobalState.CargoType.ORE and GlobalState.cargo > 0.0:
		_show_ore_trade_popup()
	else:
		_complete_pickup_with_handoff()

func _show_ore_trade_popup() -> void:
	if not ore_trade_popup or not is_instance_valid(ore_trade_popup):
		return
	var ore_amount: int = int(GlobalState.cargo)
	var rate: float = GlobalState.buyback_price_per_m3()
	var payout: int = int(round(GlobalState.cargo * rate))
	var picked_part: String = str(QuestManager.active_quest.get("part_name", "the part"))
	var picked_npc: String = str(QuestManager.active_quest.get("target_npc", "the contact"))
	ore_trade_label.text = "Your hold's full of %d m³ of ore. %s will buy it at %s SC/m³ = %d SC to clear the bay for the part. Take the deal?" % [ore_amount, picked_npc, _format_rate(rate), payout]
	ore_trade_popup.visible = true

func _format_rate(rate: float) -> String:
	if fposmod(rate, 1.0) == 0.0:
		return str(int(rate))
	return "%.1f" % rate

func _on_ore_trade_accept_pressed() -> void:
	if ore_trade_popup and is_instance_valid(ore_trade_popup):
		ore_trade_popup.visible = false
	if GlobalState.cargo_type != GlobalState.CargoType.ORE or GlobalState.cargo <= 0.0:
		show_dock_message("Hold's empty now. Go ahead and ask for the part.", "", Color(0.85, 0.85, 0.85))
		return
	var ore_amount: int = int(GlobalState.cargo)
	var rate: float = GlobalState.buyback_price_per_m3()
	var paid: int = GlobalState.buyback_ore_at_outpost()
	if paid <= 0:
		push_warning("[UIManager] _on_ore_trade_accept_pressed: buyback returned 0")
		return
	AudioManager.play_sell_ore()
	show_dock_message("Sold %d m³ of ore at %s SC/m³ = %d SC. Hold cleared." % [ore_amount, _format_rate(rate), paid], "", Color(0.7, 1.0, 0.5))
	_complete_pickup_with_handoff()

func _on_ore_trade_decline_pressed() -> void:
	if ore_trade_popup and is_instance_valid(ore_trade_popup):
		ore_trade_popup.visible = false
	show_dock_message("Kept the ore. Come back when the hold's clear.", "", Color(0.85, 0.85, 0.85))

func _complete_pickup_with_handoff() -> void:
	if not QuestManager.is_quest_active():
		return
	var picked_part: String = str(QuestManager.active_quest.get("part_name", "the part"))
	var picked_npc: String = str(QuestManager.active_quest.get("target_npc", "the contact"))
	
	var line = QuestManager.active_quest.get("pickup_handoff_line", "")
	var client_name: String = str(QuestManager.active_quest.get("agent_name", "Jenna Kross"))
	
	# Patch to override the old legacy fallback if it got cached before the update
	var old_fallback: String = "Jenna sent you? Alright, here's the %s. Tell her we're even." % picked_part
	if line == "" or line == old_fallback:
		var salt: int = randi() % FALLBACK_OUTPOST_HANDOFF.size()
		line = FALLBACK_OUTPOST_HANDOFF[salt].replace("{part}", picked_part).replace("{client}", client_name)
		
	var npc_color: Color = Color(0.85, 0.85, 0.85)
	var npc_portrait: Texture2D = null
	var picked_npc_data := GlobalState.get_minor_npc_data(picked_npc)
	if not picked_npc_data.is_empty():
		npc_color = picked_npc_data.get("flavor_color", npc_color)
		npc_portrait = GlobalState.get_minor_npc_portrait(picked_npc)
		
	if line != "":
		pass # Audio is handled by emit_npc_flavor below
		
	var success: bool = QuestManager.mark_pickup_complete()
	if success:
		_render_dock_submenu()
		var display_line = line if line != "" else "Picked up '%s' from %s. Deliver to Grease Monkeys." % [picked_part, picked_npc]
		show_dock_message(display_line, picked_npc, npc_color, npc_portrait)
		
		var flavor_dict: Dictionary = {
			"npc_name": picked_npc,
			"line": display_line,
			"color": npc_color,
			"voice_profile_id": QuestManager.active_quest.get(
				"pickup_handoff_voice_profile_id",
				"voice.neutral.v1"
			),
		}
		if not picked_npc_data.is_empty():
			flavor_dict["voice_profile_id"] = picked_npc_data.get(
				"voice_profile_id",
				flavor_dict["voice_profile_id"]
			)
		GlobalState.emit_npc_flavor(flavor_dict)
	else:
		show_dock_message(
			"Couldn't load the part. Clear your cargo hold and try again.",
			"",
			Color(1.0, 0.45, 0.45)
		)
		push_warning("[UIManager] _complete_pickup_with_handoff: mark_pickup_complete returned false")

const FALLBACK_OUTPOST_HANDOFF: Array = [
	"Tell {client} they owe me for this {part}, but not like last time. I still can't get that stain out of my carpet. They know what I mean.",
	"Here's the {part}. Remind {client} that their tab here is longer than a freighter, and this isn't a charity.",
	"Take the {part}. And tell {client} if they send another one of their 'favorite couriers' smelling like engine grease, I'm charging double.",
	"Got the {part} right here. You let {client} know they're lucky I don't hold a grudge about the plasma scorch on my docking bay.",
	"Handing over the {part}. Make sure {client} knows this favors market is getting awfully one-sided.",
]

# ── Outpost Handoff LLM Logic ───────────────────────────────────────────────

func _request_outpost_pickup_handoff_attempt(npc_name: String, part_name: String, outpost_display: String, client_name: String, critique_suffix: String, attempt: int) -> void:
	if attempt >= 2:
		_apply_pickup_handoff_fallback(
			npc_name,
			part_name,
			client_name,
			"max_attempts_reached"
		)
		return
		
	var examples_block: String = ""
	for i in range(3):
		var ex: String = FALLBACK_OUTPOST_HANDOFF[i].replace("{part}", part_name).replace("{client}", client_name)
		examples_block += "- \"" + ex + "\"\n"
		
	var base_prompt: String = (
		"You are " + npc_name + ", working at " + outpost_display + ". "
		+ "The player has arrived to pick up a part for " + client_name + ". "
		+ "Write a short line (1-2 sentences) handing over the part.\n\n"
		+ "Here are some examples of the snarky, colorful tone you should use when talking about " + client_name + ":\n"
		+ examples_block + "\n"
		+ "HARD REQUIREMENTS:\n"
		+ "1. Mention the part name: \"" + part_name + "\"\n"
		+ "2. Mention " + client_name + ".\n"
		+ "3. Output valid JSON: {\"line\": \"<your line>\"}"
	)
	var prompt_to_send: String = base_prompt
	if critique_suffix != "":
		prompt_to_send += "\n\n" + critique_suffix
		
	var url: String = LLMInterface.OLLAMA_URL
	var model: String = LLMInterface.active_model_name if LLMInterface.active_model_name != "" else "qwen2.5:1.5b"
	var body: Dictionary = {
		"model": model,
		"prompt": prompt_to_send,
		"stream": false,
		"format": "json",
		"options": { "temperature": 0.85, "num_predict": 150 },
	}
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 8.0
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body_bytes: PackedByteArray) -> void:
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_apply_pickup_handoff_fallback(
				npc_name,
				part_name,
				client_name,
				"http_failed_result_%d_code_%d" % [result, code]
			)
			return
			
		var raw: String = body_bytes.get_string_from_utf8()
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary and parsed.has("response"):
			var inner_str: String = str(parsed["response"])
			var inner = JSON.parse_string(inner_str)
			if inner is Dictionary and inner.has("line"):
				var line: String = str(inner["line"]).strip_edges()
				if line != "":
					var is_valid: bool = _is_valid_outpost_handoff_line(line, part_name, client_name)
					if is_valid:
						var voice_profile_id := "voice.neutral.v1"
						var npc_data := GlobalState.get_minor_npc_data(npc_name)
						if not npc_data.is_empty():
							voice_profile_id = npc_data.get(
								"voice_profile_id",
								voice_profile_id
							)
						QuestManager.set_pickup_handoff(
							line,
							voice_profile_id,
							false,
							npc_name
						)
						SpeechService.cache(line, voice_profile_id)
						return
					else:
						var reason: String = _explain_outpost_handoff_rejection(line, part_name, client_name)
						var new_suffix: String = "SELF-CRITIQUE — your previous attempt was rejected. Reason: " + reason
						_request_outpost_pickup_handoff_attempt(npc_name, part_name, outpost_display, client_name, new_suffix, attempt + 1)
						return
		_apply_pickup_handoff_fallback(
			npc_name,
			part_name,
			client_name,
			"parse_or_schema_failed"
		)
	)
	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _is_valid_outpost_handoff_line(line: String, part_name: String, client_name: String) -> bool:
	return _explain_outpost_handoff_rejection(line, part_name, client_name) == ""

func _explain_outpost_handoff_rejection(line: String, part_name: String, client_name: String) -> String:
	var lower: String = line.to_lower()
	var client_first_name = client_name.split(" ")[0].to_lower()
	if not lower.contains(client_first_name):
		return "Failed to mention " + client_name + "."
	
	var part_words = part_name.to_lower().split(" ")
	var has_part = false
	for w in part_words:
		if w.length() > 3 and lower.contains(w):
			has_part = true
			break
	if not has_part and not lower.contains(part_name.to_lower()):
		return "Failed to mention the required part."
	return ""

func _apply_pickup_handoff_fallback(
	npc_name: String,
	part_name: String,
	client_name: String,
	reason: String = "unspecified"
) -> void:
	GenerationDiagnostics.record_fallback(
		"outpost_pickup_handoff",
		reason,
		"UIManager",
		{
			"npc_name": npc_name,
			"part_name": part_name,
			"client_name": client_name,
		}
	)
	var salt: int = randi() % FALLBACK_OUTPOST_HANDOFF.size()
	var line: String = FALLBACK_OUTPOST_HANDOFF[salt].replace("{part}", part_name).replace("{client}", client_name)
	
	var voice_profile_id := "voice.neutral.v1"
	var npc_data := GlobalState.get_minor_npc_data(npc_name)
	if not npc_data.is_empty():
		voice_profile_id = npc_data.get("voice_profile_id", voice_profile_id)
	QuestManager.set_pickup_handoff(
		line,
		voice_profile_id,
		true,
		npc_name
	)

func _create_loading_screen():
	loading_panel = Panel.new()
	loading_panel.name = "LoadingScreen"
	loading_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(loading_panel)
	
	# Frosted cyber-dark style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.06, 0.98) # Dark deep space blue-black
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.0, 0.85, 1.0, 0.4) # Neon cyan border accent
	loading_panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(500, 250)
	loading_panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "SPACE GRID INTRUSION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0)) # Neon cyan
	vbox.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Syncing Neural Broker Uplink..."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(subtitle)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)
	
	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size = Vector2(450, 16)
	loading_bar.max_value = 100.0
	loading_bar.value = 5.0
	vbox.add_child(loading_bar)
	
	loading_status_label = Label.new()
	loading_status_label.text = "Initializing core connection to local LLM..."
	loading_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_status_label.add_theme_font_size_override("font_size", 11)
	loading_status_label.modulate = Color(0.0, 0.8, 0.8)
	vbox.add_child(loading_status_label)

func _on_llm_connection_attempt(attempt: int):
	last_llm_attempt = attempt
	_update_connection_status_display()

func _on_llm_connected(model_name: String):
	is_llm_ready = true
	_update_connection_status_display()
	_check_both_services_ready()

func _on_tts_connection_attempt(attempt: int):
	last_tts_attempt = attempt
	_update_connection_status_display()

func _on_tts_connected():
	is_tts_ready = true
	_update_connection_status_display()
	_check_both_services_ready()

func _update_connection_status_display():
	if not loading_status_label or not is_instance_valid(loading_status_label):
		return
		
	var llm_status = ""
	if is_llm_ready:
		llm_status = "LLM: Connected"
	else:
		llm_status = "LLM: Connecting... (Attempt %d)" % last_llm_attempt
		
	var tts_status = ""
	if is_tts_ready:
		tts_status = "TTS: Connected"
	else:
		tts_status = "TTS: Connecting... (Attempt %d)" % last_tts_attempt
		
	loading_status_label.text = "%s | %s" % [llm_status, tts_status]
	
	# Initial progress bar increments
	var progress = 5.0
	if is_llm_ready: progress += 10.0
	if is_tts_ready: progress += 10.0
	loading_bar.value = progress

func _check_both_services_ready():
	if is_llm_ready and is_tts_ready:
		print("[TRACE] [UIManager] Both services connected! Starting first quest generation.")
		loading_bar.value = 35.0
		loading_status_label.text = "Syncing Neural Broker Uplink: Generating first contract briefing..."
		
		# Disconnect signals to avoid multiple calls if reconnection happens later
		if LLMInterface.llm_connection_attempt.is_connected(_on_llm_connection_attempt):
			LLMInterface.llm_connection_attempt.disconnect(_on_llm_connection_attempt)
		if LLMInterface.llm_connection_established.is_connected(_on_llm_connected):
			LLMInterface.llm_connection_established.disconnect(_on_llm_connected)
		if SpeechService.speech_connection_attempt.is_connected(_on_tts_connection_attempt):
			SpeechService.speech_connection_attempt.disconnect(_on_tts_connection_attempt)
		if SpeechService.speech_connection_established.is_connected(_on_tts_connected):
			SpeechService.speech_connection_established.disconnect(_on_tts_connected)
			
		_request_background_agent_quest()

func _on_tts_cache_completed():
	# Disconnect to prevent double trigger on future cache events
	if SpeechService.cache_queue_completed.is_connected(_on_tts_cache_completed):
		SpeechService.cache_queue_completed.disconnect(_on_tts_cache_completed)
		
	print("[TRACE] [UIManager] Loading Screen: TTS caching fully completed!")
	loading_bar.value = 100.0
	loading_status_label.text = "Uplink fully secured. System Ready."
	
	var tween = create_tween()
	tween.tween_interval(0.8) # Show 100% briefly
	tween.tween_property(loading_panel, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func():
		loading_panel.queue_free()
		GlobalState.paused = false # Resume gameplay!
		print("[TRACE] [UIManager] Loading Screen completed. Game started!")
		# Trigger Kaelen's intro popup 1s after loading — safely AFTER the overlay is gone
		if not startup_save_loaded:
			get_tree().create_timer(1.0).timeout.connect(func():
				show_kaelen_intro()
			)
	)


# ─────────────────────────────────────────────────────────────────────────────
# KAELEN INTRO POPUP
# Called once after the loading screen fades on first entry into the game world.
# ─────────────────────────────────────────────────────────────────────────────

func show_kaelen_intro():
	# Kaelen's greeting variations — picked randomly each session
	var intro_lines = [
		"Hey, Shiny. Fresh hull, empty wallet — you've got that new-pilot smell. Dock up at the station if you want to change that. I've got contracts that pay.",
		"Well, well. Another Shiny shows up in my sector. You look lost. Head to the station — I've got work for anyone with a functioning ship and a low survival instinct.",
		"Shiny. Eyes up. That station on your sensors? That's your new favourite place. Dock in, talk to me, and maybe you won't be flying wreckage by the end of the week.",
		"New to the system? Good. Inexperienced pilots take the risky jobs nobody else wants. Dock at the station, Shiny. I'll make it worth your while — mostly.",
		"I don't do charity, Shiny, but I do do introductions. Station's nearby. Dock up, sit down, and let me explain how this sector works before it kills you.",
		"You've picked an interesting time to show up, Shiny. Lots of factions, lots of credits to be made — if you know who to talk to. That's me. Station. Now.",
	]
	
	var line = intro_lines[randi() % intro_lines.size()]
	
	# ── Dim overlay behind the popup ──────────────────────────────────────────
	var overlay = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	# ── Main popup panel (matches agent_panel aesthetic) ──────────────────────
	var popup = Panel.new()
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.custom_minimum_size = Vector2(680, 260)
	popup.offset_left   = -340
	popup.offset_right  =  340
	popup.offset_top    = -130
	popup.offset_bottom =  130
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 1.0)
	style.border_width_left   = 2
	style.border_width_top    = 2
	style.border_width_right  = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.0, 0.8, 0.8, 1.0)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left  = 6
	popup.add_theme_stylebox_override("panel", style)
	add_child(popup)
	
	# ── Layout ───────────────────────────────────────────────────────────────
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left   = 16
	hbox.offset_right  = -16
	hbox.offset_top    = 16
	hbox.offset_bottom = -16
	popup.add_child(hbox)
	
	# Portrait column
	var portrait_vbox = VBoxContainer.new()
	portrait_vbox.custom_minimum_size = Vector2(160, 0)
	portrait_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(portrait_vbox)
	
	var portrait_rect = TextureRect.new()
	portrait_rect.custom_minimum_size = Vector2(160, 160)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Load Kaelen's portrait slice (neutral = index 3, row 1 col 1)
	portrait_rect.texture = GameContentRegistry.shared().portrait_texture(
		"portrait.quest_givers.kaelen"
	)
	portrait_vbox.add_child(portrait_rect)
	
	# Spacer
	var gap = Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	hbox.add_child(gap)
	
	# Text column
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = "BROKER KAELEN"
	name_lbl.add_theme_color_override("font_color", Color(0.0, 0.9, 0.9))
	name_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_lbl)
	
	var sub_lbl = Label.new()
	sub_lbl.text = "Neutral Fixer & Profit Broker"
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(sub_lbl)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	var dialogue_lbl = Label.new()
	dialogue_lbl.text = line
	dialogue_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	dialogue_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(dialogue_lbl)
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer2)
	
	var dismiss_btn = Button.new()
	dismiss_btn.text = "Got it. Heading to the station."
	dismiss_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	vbox.add_child(dismiss_btn)
	
	# ── Fade in ───────────────────────────────────────────────────────────────
	popup.modulate.a = 0.0
	overlay.modulate.a = 0.0
	var fade_in = create_tween()
	fade_in.tween_property(overlay, "modulate:a", 1.0, 0.4)
	fade_in.parallel().tween_property(popup, "modulate:a", 1.0, 0.4)
	
	# ── Dismiss handler ───────────────────────────────────────────────────────
	var _dismiss = func():
		var fade_out = create_tween()
		fade_out.tween_property(popup, "modulate:a", 0.0, 0.35)
		fade_out.parallel().tween_property(overlay, "modulate:a", 0.0, 0.35)
		fade_out.tween_callback(func():
			popup.queue_free()
			overlay.queue_free()
		)
	dismiss_btn.pressed.connect(_dismiss)
	
	# ── Play Kaelen's voice ───────────────────────────────────────────────────
	SpeechService.play(line, "voice.kaelen.v1")
	print("[UIManager] Kaelen intro shown: ", line.left(60), "...")

func _style_action_button(btn: Button):
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.3, 0.6, 1.0, 0.8)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	btn.add_theme_stylebox_override("normal", sb)
	
	var sb_hover = sb.duplicate()
	sb_hover.bg_color = Color(0.2, 0.2, 0.3, 0.9)
	sb_hover.border_color = Color(0.5, 0.8, 1.0, 1.0)
	btn.add_theme_stylebox_override("hover", sb_hover)
	
	var sb_pressed = sb.duplicate()
	sb_pressed.bg_color = Color(0.1, 0.3, 0.6, 0.9)
	btn.add_theme_stylebox_override("pressed", sb_pressed)

# ── Ship Upgrades UI ────────────────────────────────────────────────────────
func _create_ship_upgrades_panel() -> void:
	ship_upgrades_panel = Panel.new()
	ship_upgrades_panel.name = "ShipUpgradesPanel"
	ship_upgrades_panel.visible = false
	ship_upgrades_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.02, 0.98) # Very dark background
	ship_upgrades_panel.add_theme_stylebox_override("panel", style)
	add_child(ship_upgrades_panel)
	
	# Background image
	var bg = TextureRect.new()
	bg.texture = load("res://assets/UI_Background.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ship_upgrades_panel.add_child(bg)
	
	# Central Ship Image (Dynamically composited)
	var ship_image = TextureRect.new()
	ship_image.texture = load("res://assets/INDYMiner_render_side.png")
	ship_image.set_anchors_preset(Control.PRESET_CENTER)
	ship_image.custom_minimum_size = Vector2(1100, 650)
	ship_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ship_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ship_image.position = -ship_image.custom_minimum_size / 2
	ship_upgrades_panel.add_child(ship_image)
	
	# Close button
	var close_btn = Button.new()
	close_btn.text = "Return"
	_style_action_button(close_btn)
	close_btn.position = Vector2(60, 40)
	close_btn.pressed.connect(func():
		ship_upgrades_panel.visible = false
		dock_panel.visible = true
	)
	ship_upgrades_panel.add_child(close_btn)
	
	# Slots (approximated positions relative to center)
	# Since it's a fullscreen UI, we'll place an invisible Control at center
	var center = Control.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	ship_upgrades_panel.add_child(center)
	
	# Helper to create invisible but clickable slot areas
	var _create_slot = func(text: String, pos: Vector2, size: Vector2, cb: Callable):
		var btn = Button.new()
		btn.text = text
		btn.position = pos - size/2
		btn.custom_minimum_size = size
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.65)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(1.0, 0.6, 0.2, 0.8) # Orange border
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_right = 4
		sb.corner_radius_bottom_left = 4
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.pressed.connect(cb)
		center.add_child(btn)
		return btn
	
	su_weapons_btn = _create_slot.call("WEAPONS\nPulse Laser Mk II\n25 Yield", Vector2(-420, 20), Vector2(220, 100), func(): _on_su_slot_pressed("weapons"))
	su_cargo_btn = _create_slot.call("CARGOHOLD\nStandard Bay\n0 / 100 SCU", Vector2(0, 40), Vector2(250, 100), func(): _on_su_slot_pressed("cargo"))
	su_engine_btn = _create_slot.call("ENGINE\nNova Thrusters\n120 m/s", Vector2(420, 20), Vector2(220, 100), func(): _on_su_slot_pressed("engine"))
	su_power_btn = _create_slot.call("POWERPLANT\nFusion Core\n500 MW", Vector2(-250, 240), Vector2(220, 100), func(): _on_su_slot_pressed("power"))
	su_shields_btn = _create_slot.call("SHIELDS\nAegis Deflector\n1200 HP", Vector2(0, -220), Vector2(220, 100), func(): _on_su_slot_pressed("shields"))
	su_mining_btn = _create_slot.call("MINING LASER\nIndustrial Beam\n1.0 Yield", Vector2(250, 240), Vector2(220, 100), func(): _on_su_slot_pressed("mining"))

	# Side panels
	var left_panel = VBoxContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_left = 60
	left_panel.offset_right = 310
	left_panel.offset_top = 100
	left_panel.offset_bottom = -60
	left_panel.add_theme_constant_override("separation", 60)
	ship_upgrades_panel.add_child(left_panel)
	
	var right_panel = VBoxContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_left = -310
	right_panel.offset_right = -60
	right_panel.offset_top = 100
	right_panel.offset_bottom = -60
	ship_upgrades_panel.add_child(right_panel)
	
	var _create_info_box = func(parent: Control, title: String, body: String):
		var vbox = VBoxContainer.new()
		vbox.custom_minimum_size = Vector2(250, 0)
		var t_lbl = Label.new()
		t_lbl.text = title
		t_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
		vbox.add_child(t_lbl)
		var b_lbl = Label.new()
		b_lbl.text = body
		b_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		vbox.add_child(b_lbl)
		parent.add_child(vbox)
		return b_lbl
		
	var su_sys_status = _create_info_box.call(left_panel, "SYSTEM STATUS", "")
	su_sys_status.name = "SysStatusLabel"
	
	var storage_vbox = VBoxContainer.new()
	storage_vbox.custom_minimum_size = Vector2(250, 0)
	var st_lbl = Label.new()
	st_lbl.text = "PLAYER STORAGE"
	st_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	storage_vbox.add_child(st_lbl)
	su_ore_bank_lbl = Label.new()
	storage_vbox.add_child(su_ore_bank_lbl)
	var dep_btn = Button.new()
	dep_btn.text = "Deposit Ore from Ship"
	dep_btn.tooltip_text = "Store your raw ore securely here. Banked ore is saved to your account and can be used later to fabricate ship upgrades."
	_style_action_button(dep_btn)
	dep_btn.pressed.connect(func():
		if GlobalState.deposit_ore(GlobalState.cargo):
			_refresh_upgrade_ui()
	)
	storage_vbox.add_child(dep_btn)
	left_panel.add_child(storage_vbox)

	su_ship_sys_vbox = VBoxContainer.new()
	su_ship_sys_vbox.custom_minimum_size = Vector2(250, 0)
	var t_lbl2 = Label.new()
	t_lbl2.text = "SHIP SYSTEMS"
	t_lbl2.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	su_ship_sys_vbox.add_child(t_lbl2)
	su_ship_sys_lbl = RichTextLabel.new()
	su_ship_sys_lbl.bbcode_enabled = true
	su_ship_sys_lbl.fit_content = true
	su_ship_sys_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	su_ship_sys_lbl.text = "\n\nSelect a system to view details.\n"
	su_ship_sys_lbl.add_theme_color_override("default_color", Color(0.8, 0.8, 0.8))
	su_ship_sys_vbox.add_child(su_ship_sys_lbl)
	right_panel.add_child(su_ship_sys_vbox)

func _on_ship_upgrades_pressed() -> void:
	dock_panel.visible = false
	ship_upgrades_panel.visible = true
	_refresh_upgrade_ui()

func _refresh_upgrade_ui():
	su_cargo_btn.text = "CARGOHOLD\nTier %d\n%d / %d SCU" % [GlobalState.current_upgrades["cargo"]["tier"], GlobalState.cargo, GlobalState.cargo_max]
	su_weapons_btn.text = "WEAPONS\nTier %d %s" % [GlobalState.current_upgrades["weapons"]["tier"], GlobalState.current_upgrades["weapons"]["path"].capitalize()]
	su_engine_btn.text = "ENGINE\nTier %d %s" % [GlobalState.current_upgrades["engine"]["tier"], GlobalState.current_upgrades["engine"]["path"].capitalize()]
	su_power_btn.text = "POWERPLANT\nTier %d\nCapacity: %d MW" % [GlobalState.current_upgrades["power"]["tier"], GlobalState.power_capacity]
	su_shields_btn.text = "SHIELDS\nTier %d %s" % [GlobalState.current_upgrades["shields"]["tier"], GlobalState.current_upgrades["shields"]["path"].capitalize()]
	su_mining_btn.text = "MINING LASER\nTier %d %s" % [GlobalState.current_upgrades["mining"]["tier"], GlobalState.current_upgrades["mining"]["path"].capitalize()]
	
	su_ore_bank_lbl.text = "Banked Ore: %.1f / %.1f\nCredits: %d\nPower Draw: %d / %d MW" % [GlobalState.player_storage_ore, GlobalState.player_storage_max, GlobalState.player_credits, GlobalState.get_current_power_draw(), GlobalState.power_capacity]
	
	# Try to find SysStatusLabel safely
	var status_node = ship_upgrades_panel.find_child("SysStatusLabel", true, false)
	if status_node and status_node is Label:
		status_node.text = "POWER: %d / %d MW\nCARGO: %d / %d" % [GlobalState.get_current_power_draw(), GlobalState.power_capacity, GlobalState.cargo, GlobalState.cargo_max]

func _on_su_slot_pressed(slot: String) -> void:
	var info = GlobalState.current_upgrades[slot]
	var current_tier = info["tier"]
	var current_path = info["path"]
	var is_max = current_tier >= 5
	
	for child in su_ship_sys_vbox.get_children():
		if child != su_ship_sys_vbox.get_child(0) and child != su_ship_sys_lbl:
			child.queue_free()
			
	if current_tier == 1:
		su_ship_sys_lbl.text = "%s - Tier 1 Base\n\nAvailable Upgrades:\n" % slot.to_upper()
		for path in GlobalState.UPGRADE_TREE[slot]["branches"].keys():
			var data = GlobalState.UPGRADE_TREE[slot]["branches"][path][2]
			var btn = Button.new()
			_style_action_button(btn)
			var pwr = data.get("power", 0)
			var cost_c = data["cost_cr"]
			var cost_o = data["cost_ore"]
			btn.text = "Install %s Mk II\nCost: %d CR, %d Ore\nDraw: %d MW" % [path.capitalize(), cost_c, cost_o, pwr]
			btn.pressed.connect(func(): _attempt_upgrade(slot, path))
			su_ship_sys_vbox.add_child(btn)
	else:
		su_ship_sys_lbl.text = "%s - Tier %d %s\n" % [slot.to_upper(), current_tier, current_path.capitalize()]
		if is_max:
			su_ship_sys_lbl.text += "\nMAXIMUM TIER REACHED."
		else:
			var next_tier = current_tier + 1
			var data = GlobalState.UPGRADE_TREE[slot]["branches"][current_path][next_tier]
			var btn = Button.new()
			_style_action_button(btn)
			var pwr = data.get("power", 0)
			btn.text = "Upgrade to Mk %d\nCost: %d CR, %d Ore\nDraw: %d MW" % [next_tier, data["cost_cr"], data["cost_ore"], pwr]
			btn.pressed.connect(func(): _attempt_upgrade(slot, current_path))
			su_ship_sys_vbox.add_child(btn)
			
		var ref_btn = Button.new()
		ref_btn.text = "Refund & Reset Path (50% Back)"
		_style_action_button(ref_btn)
		ref_btn.pressed.connect(func():
			GlobalState.refund_upgrade(slot)
			_on_su_slot_pressed(slot)
			_refresh_upgrade_ui()
		)
		su_ship_sys_vbox.add_child(ref_btn)
var _insufficient_credits_lines: Array = [
	"You're going to need a whole lot more credits for that purchase. Come back when you're not broke.",
	"I don't run a charity here, Indy. Get some more credits and we'll talk.",
	"Your account is looking a little light for that tier of hardware.",
	"If you want the good stuff, you gotta pay for it. Check your credit balance.",
	"Sorry, but I can't install that on good faith alone. Credits upfront."
]

var _insufficient_ore_lines: Array = [
	"I can't install it without the ore for the printer. Get mining.",
	"The fabrication printer is hungry. Bring me more raw ore if you want this.",
	"We're short on the raw materials for this upgrade. Go crack some rocks.",
	"You want me to build that out of thin air? I need more ore in the hopper.",
	"My printer needs more ore to lay down that schematic. Go fill your hold."
]

var _insufficient_power_lines: Array = [
	"Even if I wanted to install that, you ain't got the power to run it in that bird. I won't waste my time on something you can't even use.",
	"Your powerplant would choke trying to spool that up. Upgrade your reactor first.",
	"I'm not installing that just to watch your ship go dark when you flip the switch. Not enough power.",
	"You're drawing too much juice already. Get a better powerplant before adding more toys.",
	"That system needs more megawatts than your jalopy can put out. Upgrade the powerplant."
]

var _credit_idx: int = 0
var _ore_idx: int = 0
var _power_idx: int = 0

func _attempt_upgrade(slot: String, path: String):
	# Calculate failure reason beforehand if any
	var info = GlobalState.current_upgrades[slot]
	var next_tier = info["tier"] + 1
	var data = GlobalState.UPGRADE_TREE[slot]["branches"][path][next_tier]
	var cost_cr = data["cost_cr"]
	var cost_ore = data["cost_ore"]
	var next_power = data.get("power", 0)
	var current_power = GlobalState.UPGRADE_TREE[slot]["base_power"]
	if info["tier"] > 1:
		current_power = GlobalState.UPGRADE_TREE[slot]["branches"][info["path"]][info["tier"]].get("power", 0)
	var power_diff = next_power - current_power
	
	var reason = ""
	var available_ore := GlobalState.player_storage_ore
	if GlobalState.cargo_type == GlobalState.CargoType.ORE:
		available_ore += GlobalState.cargo
	if slot != "power" and GlobalState.get_current_power_draw() + power_diff > GlobalState.power_capacity:
		reason = "power"
	elif GlobalState.player_credits < cost_cr:
		reason = "credits"
	elif available_ore < cost_ore:
		reason = "ore"
		
	if reason != "":
		var line = ""
		if reason == "power":
			line = _insufficient_power_lines[_power_idx]
			_power_idx = (_power_idx + 1) % _insufficient_power_lines.size()
		elif reason == "credits":
			line = _insufficient_credits_lines[_credit_idx]
			_credit_idx = (_credit_idx + 1) % _insufficient_credits_lines.size()
		elif reason == "ore":
			line = _insufficient_ore_lines[_ore_idx]
			_ore_idx = (_ore_idx + 1) % _insufficient_ore_lines.size()
		# Replace generic red text with Jenna's dialogue
		su_ship_sys_lbl.text += "\n\n[color=#FF7777]\"%s\"[/color]" % line
		SpeechService.play(line, "voice.jenna_kross.v1")
		return

	if GlobalState.purchase_upgrade(slot, path):
		_on_su_slot_pressed(slot)
		_refresh_upgrade_ui()
	else:
		su_ship_sys_lbl.text += "\n[color=red]UPGRADE FAILED[/color]"
