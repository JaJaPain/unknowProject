class_name KaelenInteractionKinds
extends RefCounted

const AGENT_HANDOFF := "agent_handoff"
const OFFER_COMMENT := "offer_comment"
const ACCEPTANCE_AFTERTHOUGHT := "acceptance_afterthought"
const OBJECTIVE_COMPLETE_PENDING_TURN_IN := "objective_complete_pending_turn_in"
const TURN_IN_CLEAN := "turn_in_clean"
const TURN_IN_ROUGH := "turn_in_rough"
const TURN_IN_LATE := "turn_in_late"
const PARTIAL_DELIVERY := "partial_delivery"
const ABANDON := "abandon"
const DECLINE := "decline"
const CHAPTER_COMMENT := "chapter_comment"
const FIRST_SYSTEM_ARRIVAL := "first_system_arrival"

const ALL: Array[String] = [
	AGENT_HANDOFF,
	OFFER_COMMENT,
	ACCEPTANCE_AFTERTHOUGHT,
	OBJECTIVE_COMPLETE_PENDING_TURN_IN,
	TURN_IN_CLEAN,
	TURN_IN_ROUGH,
	TURN_IN_LATE,
	PARTIAL_DELIVERY,
	ABANDON,
	DECLINE,
	CHAPTER_COMMENT,
	FIRST_SYSTEM_ARRIVAL,
]

const TURN_IN_KINDS: Array[String] = [
	OBJECTIVE_COMPLETE_PENDING_TURN_IN,
	TURN_IN_CLEAN,
	TURN_IN_ROUGH,
	TURN_IN_LATE,
	PARTIAL_DELIVERY,
	ABANDON,
	DECLINE,
]

const SAFE_AFTER_COMPLETION_REVEAL_KINDS: Array[String] = [
	OBJECTIVE_COMPLETE_PENDING_TURN_IN,
	TURN_IN_CLEAN,
	TURN_IN_ROUGH,
	TURN_IN_LATE,
	PARTIAL_DELIVERY,
]


static func all() -> Array[String]:
	return ALL.duplicate()


static func is_valid(kind: String) -> bool:
	return kind.strip_edges() in ALL


static func is_turn_in(kind: String) -> bool:
	return kind.strip_edges() in TURN_IN_KINDS


static func allows_safe_after_completion_reveal(kind: String) -> bool:
	return kind.strip_edges() in SAFE_AFTER_COMPLETION_REVEAL_KINDS
