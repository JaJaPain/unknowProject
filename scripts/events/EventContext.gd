extends RefCounted

var campaign_time: int = 0
var current_system_id: String = ""
var just_arrived: bool = false
var player_credits: int = 0
var reputations: Dictionary = {}
var active_mission_risk_tags: Array[String] = []
var event_history: Array[Dictionary] = []
var system_registry = null


func to_dict() -> Dictionary:
	return {
		"campaign_time": campaign_time,
		"current_system_id": current_system_id,
		"just_arrived": just_arrived,
		"player_credits": player_credits,
		"reputations": reputations.duplicate(),
		"active_mission_risk_tags": active_mission_risk_tags.duplicate(),
		"event_history": event_history.duplicate(true),
	}


static func from_dict(data: Dictionary):
	var ctx = new()
	ctx.campaign_time = int(data.get("campaign_time", 0))
	ctx.current_system_id = str(data.get("current_system_id", ""))
	ctx.just_arrived = bool(data.get("just_arrived", false))
	ctx.player_credits = int(data.get("player_credits", 0))
	ctx.reputations = data.get("reputations", {})
	ctx.active_mission_risk_tags = []
	for tag in data.get("active_mission_risk_tags", []):
		ctx.active_mission_risk_tags.append(str(tag))
	ctx.event_history = data.get("event_history", [])
	return ctx
