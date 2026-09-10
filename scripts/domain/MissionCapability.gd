class_name MissionCapability
extends RefCounted


func capability_id() -> String:
	return ""


func supported_objective_types() -> Array[String]:
	return []


func is_completed(data: Dictionary) -> bool:
	return false


func handle_event(data: Dictionary, event: String, event_data: Dictionary) -> Dictionary:
	return {}


func format_tracker_text(data: Dictionary) -> String:
	return ""


func on_complete(data: Dictionary) -> Dictionary:
	return {}


func on_cleanup(data: Dictionary) -> Dictionary:
	return {}


func faction_display(data: Dictionary, fallback_key: String = "hostile") -> String:
	var explicit := str(data.get("target_faction_display", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	return _display_faction_key(str(data.get("target_faction", fallback_key)))


func _display_faction_key(faction_key: String) -> String:
	var clean := faction_key.strip_edges().to_lower()
	match clean:
		"zenith", "faction.zenith":
			return "Zenith"
		"aurelia", "faction.aurelia":
			return "Aurelia"
		"vanguard", "faction.vanguard":
			return "Vanguard"
		"reavers", "faction.reavers":
			return "Reavers"
		"obsidian", "faction.obsidian":
			return "Obsidian"
		"dustborn", "faction.dustborn":
			return "Dustborn"
		"wraiths", "faction.wraiths":
			return "Wraiths"
		"ironclad", "faction.ironclad":
			return "Ironclad"
	if clean.begins_with("faction.generated."):
		clean = clean.trim_prefix("faction.generated.")
	elif clean.begins_with("faction."):
		clean = clean.trim_prefix("faction.")
	if clean.begins_with("gen_"):
		clean = clean.trim_prefix("gen_")
	var words := clean.replace(".", "_").replace("-", "_").split("_", false)
	var titled: Array[String] = []
	for word in words:
		if word.is_valid_int() or word.length() <= 1:
			continue
		titled.append(word.substr(0, 1).to_upper() + word.substr(1))
	if titled.is_empty():
		return "Local"
	return " ".join(titled)
