class_name GameContentRegistry
extends RefCounted

const ROOT := "res://data/content/"
static var _shared: GameContentRegistry

var factions: Dictionary = {}
var faction_aliases: Dictionary = {}
var npcs: Dictionary = {}
var npc_names: Dictionary = {}
var voices: Dictionary = {}
var ships: Dictionary = {}
var ship_lookup: Dictionary = {}
var portraits: Dictionary = {}
var provider_voice_mappings: Dictionary = {}
var validation := ValidationResult.new()


static func shared() -> GameContentRegistry:
	if _shared == null:
		_shared = GameContentRegistry.new()
		_shared._load()
	return _shared


func is_valid() -> bool:
	return validation.is_valid()


func faction(value: Variant) -> FactionDefinition:
	var key := str(value)
	var id: StringName = faction_aliases.get(key, DomainId.canonicalize(key))
	return factions.get(id)


func npc_by_name(display_name: String) -> NpcDefinition:
	return npcs.get(npc_names.get(display_name, StringName()))


func portrait(value: Variant) -> PortraitDefinition:
	return portraits.get(DomainId.canonicalize(value))


func portrait_texture(value: Variant) -> AtlasTexture:
	var definition := portrait(value)
	return definition.texture() if definition else null


func ship_path(faction_value: Variant, role: String) -> String:
	var faction_definition := faction(faction_value)
	if faction_definition == null:
		return ""
	var definition: ShipDesignDefinition = ships.get(
		ship_lookup.get("%s|%s" % [faction_definition.id, role], StringName())
	)
	if definition == null:
		return ""
	return definition.asset_path if ResourceLoader.exists(definition.asset_path) else definition.fallback_asset_path


func provider_voice(profile_id: Variant) -> Dictionary:
	return provider_voice_mappings.get(str(DomainId.canonicalize(profile_id)), {}).duplicate(true)


func _load() -> void:
	_load_definitions("factions.json", "factions", FactionDefinition, factions, "_register_faction")
	_load_definitions("voices.json", "voices", VoiceProfileDefinition, voices)
	_load_definitions("npcs.json", "npcs", NpcDefinition, npcs, "_register_npc")
	_load_definitions("ship_designs.json", "ship_designs", ShipDesignDefinition, ships, "_register_ship")
	_load_portraits()
	_load_provider_mappings()
	_cross_validate()


func _load_definitions(
	file_name: String,
	array_key: String,
	type: GDScript,
	output: Dictionary,
	register_method: String = ""
) -> void:
	var parsed := DomainJson.read_object(ROOT + file_name)
	validation.merge(parsed["validation"], file_name)
	if not parsed["validation"].is_valid():
		return
	for index in range(parsed["data"].get(array_key, []).size()):
		var definition = type.new()
		var result: ValidationResult = definition.load_from_dict(parsed["data"][array_key][index])
		validation.merge(result, "%s.%d" % [array_key, index])
		if not result.is_valid():
			continue
		if output.has(definition.id):
			validation.add_error("duplicate_id", "Duplicate content ID '%s'." % definition.id)
			continue
		output[definition.id] = definition
		if not register_method.is_empty():
			call(register_method, definition)


func _register_faction(definition: FactionDefinition) -> void:
	if faction_aliases.has(definition.legacy_id):
		validation.add_error(
			"duplicate_faction_alias",
			"Duplicate faction alias '%s'." % definition.legacy_id
		)
	faction_aliases[definition.legacy_id] = definition.id
	faction_aliases[str(definition.id)] = definition.id


func _register_npc(definition: NpcDefinition) -> void:
	if npc_names.has(definition.display_name):
		validation.add_error(
			"duplicate_npc_name",
			"Duplicate NPC display name '%s'." % definition.display_name
		)
	npc_names[definition.display_name] = definition.id


func _register_ship(definition: ShipDesignDefinition) -> void:
	var lookup_key := "%s|%s" % [definition.faction_id, definition.role]
	if ship_lookup.has(lookup_key):
		validation.add_error(
			"duplicate_ship_role",
			"Duplicate ship design for '%s'." % lookup_key
		)
	ship_lookup[lookup_key] = definition.id


func _load_portraits() -> void:
	var parsed := DomainJson.read_object(ROOT + "portrait_sheets.json")
	validation.merge(parsed["validation"], "portrait_sheets")
	if not parsed["validation"].is_valid():
		return
	for sheet in parsed["data"].get("sheets", []):
		_register_portrait_sheet(sheet)
	for import_path in parsed["data"].get("imports", []):
		var imported := DomainJson.read_object(str(import_path))
		validation.merge(imported["validation"], "portrait_import")
		for sheet in imported["data"].get("sheets", []):
			var converted := {
				"id": "portrait_sheet.%s" % str(sheet.get("sheet", "")).to_lower(),
				"source_path": "res://assets/Portraits/%s" % sheet.get("source_file", ""),
				"portraits": [],
			}
			for item in sheet.get("portraits", []):
				converted["portraits"].append({
					"id": "portrait.%s.%02d" % [str(sheet.get("sheet", "")).to_lower(), int(item.get("index", 0))],
					"bounds": item.get("bounds", {}),
					"tags": item.get("tags", []) + [item.get("gender", ""), item.get("age_group", "")],
				})
			_register_portrait_sheet(converted)


func _register_portrait_sheet(sheet: Dictionary) -> void:
	var sheet_id := DomainId.canonicalize(sheet.get("id", ""))
	var source_path := str(sheet.get("source_path", ""))
	var sheet_error := DomainId.validation_error(sheet_id, "portrait_sheet")
	if not sheet_error.is_empty():
		validation.add_error("invalid_portrait_sheet_id", sheet_error, "id")
		return
	if not ResourceLoader.exists(source_path):
		validation.add_error("portrait_sheet_missing", "Portrait sheet not found.", source_path)
		return
	for item in sheet.get("portraits", []):
		var definition := PortraitDefinition.new()
		var result := definition.load_from_dict(item, sheet_id, source_path)
		validation.merge(result, str(sheet_id))
		if result.is_valid():
			if portraits.has(definition.id):
				validation.add_error("duplicate_portrait", "Duplicate portrait '%s'." % definition.id)
			else:
				portraits[definition.id] = definition


func _load_provider_mappings() -> void:
	var parsed := DomainJson.read_object(ROOT + "voice_provider_kokoro.json")
	validation.merge(parsed["validation"], "voice_provider")
	if not parsed["validation"].is_valid():
		return
	var mappings: Variant = parsed["data"].get("mappings", {})
	if not mappings is Dictionary:
		validation.add_error(
			"invalid_voice_mappings",
			"Provider voice mappings must be a dictionary.",
			"voice_provider.mappings"
		)
		return
	provider_voice_mappings = mappings.duplicate(true)


func _cross_validate() -> void:
	for definition: FactionDefinition in factions.values():
		if not definition.agent_npc_id.is_empty() and not npcs.has(definition.agent_npc_id):
			validation.add_error("unknown_agent", "Faction '%s' references unknown agent." % definition.id)
		if not definition.agent_portrait_id.is_empty() and not portraits.has(definition.agent_portrait_id):
			validation.add_error("unknown_agent_portrait", "Faction '%s' references unknown portrait." % definition.id)
		if not definition.voice_profile_id.is_empty() and not voices.has(definition.voice_profile_id):
			validation.add_error("unknown_faction_voice", "Faction '%s' references unknown voice." % definition.id)
	for definition: NpcDefinition in npcs.values():
		if not portraits.has(definition.portrait_id):
			validation.add_error("unknown_portrait", "NPC '%s' references unknown portrait." % definition.id)
		if not voices.has(definition.voice_profile_id):
			validation.add_error("unknown_voice", "NPC '%s' references unknown voice." % definition.id)
		if not definition.faction_id.is_empty() and not factions.has(definition.faction_id):
			validation.add_error("unknown_faction", "NPC '%s' references unknown faction." % definition.id)
	for definition: ShipDesignDefinition in ships.values():
		if not definition.faction_id.is_empty() and not factions.has(definition.faction_id):
			validation.add_error("unknown_ship_faction", "Ship '%s' references unknown faction." % definition.id)
	for definition: VoiceProfileDefinition in voices.values():
		if (
			not definition.fallback_voice_profile_id.is_empty()
			and not voices.has(definition.fallback_voice_profile_id)
		):
			validation.add_error("unknown_voice_fallback", "Voice '%s' references unknown fallback." % definition.id)
	for profile_id in provider_voice_mappings:
		if not voices.has(DomainId.canonicalize(profile_id)):
			validation.add_error("unknown_voice_mapping", "Provider mapping references unknown voice '%s'." % profile_id)
		var mapping: Variant = provider_voice_mappings[profile_id]
		if not mapping is Dictionary or str(mapping.get("provider_voice", "")).is_empty():
			validation.add_error(
				"invalid_voice_mapping",
				"Provider mapping '%s' must declare provider_voice." % profile_id
			)
