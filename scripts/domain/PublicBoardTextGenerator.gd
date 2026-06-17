class_name PublicBoardTextGenerator
extends RefCounted


static func build_generation_request(
	offer: Dictionary,
	critique: String = ""
) -> Dictionary:
	var template := MissionTemplateRegistry.get_template(
		str(offer.get("template_id", ""))
	)
	if template == null:
		return {"template_id": "", "prompt": "", "format": "json", "required_placeholders": [], "fields": []}
	return MissionTextGenerator.build_generation_request(template, offer, critique)


static func fallback_payload(offer: Dictionary, salt: int = 0) -> Dictionary:
	var template := MissionTemplateRegistry.get_template(
		str(offer.get("template_id", ""))
	)
	if template == null:
		return {}
	return MissionTextGenerator.fallback_payload(template, offer, salt)


static func apply_payload_to_offer(
	offer: Dictionary,
	payload: Dictionary,
	is_fallback: bool
) -> Dictionary:
	var template := MissionTemplateRegistry.get_template(
		str(offer.get("template_id", ""))
	)
	if template == null:
		return {"ok": false, "reason": "unknown template", "offer": offer.duplicate(true)}
	return MissionTextGenerator.apply_payload_to_offer(template, offer, payload, is_fallback)


static func validate_payload(offer: Dictionary, payload: Dictionary) -> Dictionary:
	var template := MissionTemplateRegistry.get_template(
		str(offer.get("template_id", ""))
	)
	if template == null:
		return {"ok": false, "reason": "unknown template"}
	return MissionTextGenerator.validate_payload(template, offer, payload)


static func fallback_offer(offer: Dictionary, salt: int = 0) -> Dictionary:
	var template := MissionTemplateRegistry.get_template(
		str(offer.get("template_id", ""))
	)
	if template == null:
		return offer
	return MissionTextGenerator.fallback_offer(template, offer, salt)
