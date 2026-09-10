class_name NarrativeRuntimeConfigService
extends Node

## Independent rollout controls for the living-narrative systems.
##
## Keep these disabled by default. Each subsystem is enabled only after its
## phase exit gate has passed, so a problem can be isolated without changing
## the rest of the narrative path.

const FLAG_NAMES := [
	"narrative_metadata_v2",
	"knowledge_ledger_v2",
	"mission_director_v2",
	"conversation_bundle_v2",
	"narrative_cache_v2",
	"nova_bank_v2",
	"lounge_bundle_v2",
]

var _flags: Dictionary = {}


func _ready() -> void:
	reset()


func reset() -> void:
	_flags.clear()
	for flag_name in FLAG_NAMES:
		_flags[flag_name] = false


func is_enabled(flag_name: String) -> bool:
	return bool(_flags.get(flag_name, false))


func set_enabled(flag_name: String, enabled: bool) -> bool:
	if not FLAG_NAMES.has(flag_name):
		push_warning("[NarrativeRuntimeConfig] Unknown flag: %s" % flag_name)
		return false
	_flags[flag_name] = enabled
	return true


func snapshot() -> Dictionary:
	return _flags.duplicate(true)
