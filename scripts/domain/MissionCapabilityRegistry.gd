class_name MissionCapabilityRegistry
extends RefCounted

static var _capabilities: Dictionary = {}
static var _initialized := false


static func _ensure_defaults() -> void:
	if _initialized:
		return
	_initialized = true
	register(load("res://scripts/domain/capabilities/KillShipsCapability.gd").new())
	register(load("res://scripts/domain/capabilities/DeliverOreCapability.gd").new())
	register(load("res://scripts/domain/capabilities/PickupSpecialCapability.gd").new())
	register(load("res://scripts/domain/capabilities/DeliveryCourierCapability.gd").new())
	register(load("res://scripts/domain/capabilities/PurchaseDeliveryCapability.gd").new())
	register(load("res://scripts/domain/capabilities/RecoverCombatDropCapability.gd").new())
	register(load("res://scripts/domain/capabilities/CommsReversalCapability.gd").new())


static func register(capability: MissionCapability) -> void:
	for obj_type in capability.supported_objective_types():
		_capabilities[obj_type] = capability


static func get_for_type(objective_type: String) -> MissionCapability:
	_ensure_defaults()
	return _capabilities.get(objective_type, null)


static func has_type(objective_type: String) -> bool:
	_ensure_defaults()
	return _capabilities.has(objective_type)


static func reset() -> void:
	_capabilities.clear()
	_initialized = false
