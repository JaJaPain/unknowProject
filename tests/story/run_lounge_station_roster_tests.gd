extends SceneTree

class StationFixture extends Node3D:
	var display_name := "Test Station"
	var station_type := "outpost"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gs := root.get_node("GlobalState")
	var script := GDScript.new()
	script.source_code = 'extends "res://scripts/UIManager.gd"\nvar shown: Array = []\nvar prepared: Array = []\nfunc _ready() -> void:\n\tpass\nfunc _current_station_contact_id() -> String:\n\treturn str(current_station.get_meta("contact_id", ""))\nfunc _station_contact_id_for_node(station: Node3D) -> String:\n\treturn str(station.get_meta("contact_id", ""))\nfunc _lounge_bartender_card(_id: String) -> Dictionary:\n\treturn {"kind": "bartender", "name": "Bartender"}\nfunc _lounge_npc_card(npc_name: String, _data: Dictionary) -> Dictionary:\n\treturn {"kind": "npc", "name": npc_name}\nfunc _lounge_kaelen_card() -> Dictionary:\n\treturn {"kind": "kaelen", "name": "Broker Kaelen"}\nfunc _station_contact_has_intel(_name: String, _data: Dictionary) -> bool:\n\treturn false\nfunc _add_lounge_contact_card(_slot: int, card: Dictionary) -> void:\n\tshown.append(card)\nfunc _prepare_lounge_exchange_bundle(card: Dictionary) -> void:\n\tprepared.append(card)\nfunc _roll_lounge_approach(_cards: Array) -> void:\n\tpass\nfunc _roll_lounge_stranger(_cards: Array) -> void:\n\tpass\n'
	var compiled := script.reload()
	if compiled != OK or not script.can_instantiate():
		push_error("[FAIL] Lounge roster UI probe did not compile")
		quit(1)
		return
	var ui: Node = script.new()
	ui.station_contacts_panel = PanelContainer.new()
	ui.station_contacts_list = Control.new()
	ui.add_child(ui.station_contacts_panel)
	ui.add_child(ui.station_contacts_list)
	var system := Node3D.new()
	root.add_child(system)
	var home := StationFixture.new()
	home.name = "Station"
	home.station_type = "main"
	home.set_meta("contact_id", "main")
	system.add_child(home)
	var kova := StationFixture.new()
	kova.set_meta("contact_id", "kova")
	system.add_child(kova)
	var iron := StationFixture.new()
	iron.set_meta("contact_id", "iron_reach")
	system.add_child(iron)
	gs.active_system_root = system
	gs.current_system_id = "start_system"
	gs.story_planted_npc = {}
	gs.generated_outpost_npcs.clear()
	for station in [kova, iron]:
		ui.current_station = station
		ui.shown.clear()
		ui.call("_render_station_contacts", true)
		var residents: Array = gs.get_minor_npcs_at_outpost(str(station.get_meta("contact_id")))
		_expect(ui.call("_current_station_has_contacts"), "Resident-only lounge must remain accessible with no active rumors")
		_expect(ui.shown.size() == 4, "Lounge must render four card slots")
		for index in range(1, 4):
			var card: Dictionary = ui.shown[index]
			_expect(card.get("kind", "") == "npc" and card.get("name", "") in residents, "All three contact slots must contain this outpost's own residents")
		_expect(not ui.call("_kaelen_lounge_available"), "Kaelen must not be physically present at an outpost")
	# The same roster rule must apply before docking, even while current_station
	# still points to the main station from the preceding visit.
	ui.current_station = home
	var local_voices: Array[String] = []
	for station in [kova, iron]:
		var resident_voices: Array[String] = []
		for npc_name in gs.get_minor_npcs_at_outpost(str(station.get_meta("contact_id"))):
			resident_voices.append(str(gs.get_minor_npc_data(npc_name).get("voice_profile_id", "")))
		var voice: String = ui.call("_dock_clearance_voice_for_station", station)
		_expect(not voice.is_empty() and voice in resident_voices, "Dock clearance must use the target station's resident even while current_station is home")
		_expect(voice not in ["voice.neutral.v1", "voice.jenna_kross.v1", "voice.nova.v1"] and not gs.is_kaelen_voice(voice), "Local dock must not borrow main cast or neutral mechanic blend")
		local_voices.append(voice)
	_expect(local_voices[0] != local_voices[1], "Kova and Iron Reach dock voices must be distinct")
	kova.set_meta("contact_id", "station.start.kova")
	_expect(ui.call("_dock_clearance_voice_for_station", kova) == local_voices[0], "Canonical station ID must resolve the same local dock voice")
	kova.set_meta("contact_id", "kova")
	ui.prepared.clear()
	ui.call("_prepare_lounge_bundles_for_station", kova)
	for card in ui.prepared:
		_expect(card.get("kind", "") != "agent" and card.get("kind", "") != "kaelen", "Kova prefetch must not prepare main-station agents")
	_expect(ui.prepared.size() == 4, "Kova prefetch must prepare bartender plus its three locals")
	ui.shown.clear()
	ui.call("_render_station_contacts", true)
	_expect(ui.shown[1].get("kind") == "agent" and ui.shown[2].get("kind") == "agent", "Main station must retain its faction representatives")
	_expect(ui.shown[3].get("kind") == "kaelen", "Main station must retain Kaelen")
	# Generated systems use their stored station roster through the same path.
	gs.generated_outpost_npcs["kova"] = ["Local Test Contact"]
	gs.generated_outpost_npc_data["Local Test Contact"] = {"role": "Dock worker", "outpost": "kova"}
	ui.current_station = kova
	ui.shown.clear()
	ui.call("_render_station_contacts", true)
	_expect(ui.shown[1].get("name") == "Local Test Contact", "Persisted/generated local roster must take precedence over tutorial residents")
	_expect(ui.shown[2].is_empty() and ui.shown[3].is_empty(), "Empty local slots must not be filled with foreign agents")
	gs.generated_outpost_npc_data["Local Test Contact"] = {"role": "Station mechanic", "outpost": "kova", "voice_profile_id": "voice.hana_quill.v1"}
	_expect(ui.call("_dock_clearance_voice_for_station", kova) == "voice.hana_quill.v1", "Generated station's mechanic must supply dock voice")
	gs.generated_outpost_npc_data["Local Test Contact"]["voice_profile_id"] = "voice.nova.v1"
	var fallback: String = ui.call("_dock_clearance_voice_for_station", kova)
	_expect(fallback in gs.GENERATED_CONTACT_VOICES, "Invalid reserved resident voice must fall back to a local profile")
	_expect(ui.call("_dock_clearance_voice_for_station", kova) == fallback, "Fallback dock voice must be stable across visits")
	gs.generated_outpost_npcs.clear()
	gs.generated_outpost_npc_data.erase("Local Test Contact")
	gs.active_system_root = null
	ui.free()
	system.free()
	if failures.is_empty():
		print("[PASS] Lounge station rosters and local dock voices: Kova, Iron Reach, canonical IDs, prefetch, generated locals and reserved-voice fallback")
	else:
		for failure in failures:
			push_error("[FAIL] " + failure)
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
