class_name ReservedTopics
extends RefCounted

## Topics reserved for the fixed cast's undercurrent (director-only; see
## docs/fresh_eyes_vision_plan_2026_09_23.md Section 5). Nothing the game sends
## to a language model, and nothing a generated character says, may touch them.
##
## One list, used by: the secret-leak test (static text), the premise-card
## validators (Python tool and, later, the in-game port), and runtime checks
## on generated lines. Keep tools/premise_cards/validate_premise_cards.py in
## step with this file.
##
## The patterns name surface words only. They deliberately say nothing about
## why these topics are reserved.

const PATTERNS: Array[String] = [
	"\\bdimensions?\\b",
	"\\bparallel (universe|universes|world|worlds|reality|realities)\\b",
	"\\b(other|another) (universe|reality)\\b",
	"\\bandroids?\\b",
	"\\bsynthetic (body|bodies|human|humans)\\b",
	"\\b(proxy|remote) (body|bodies)\\b",
	"\\bconsciousness (transfer|upload)\\w*",
	"\\bupload(ed|ing)? (a |their |his |her )?(mind|consciousness)\\b",
	"\\bresurrect\\w*",
	"\\bback from the dead\\b",
	"\\bbrought back to life\\b",
	"\\bbring (you|the captain|the player|shiny) back\\b",
	"\\b(captain|shiny|the player) (died|is dead)\\b",
	"\\bclon(e|es|ed|ing)\\b",
	"\\btime[- ](travel|loop)\\w*",
]

static var _compiled: Array[RegEx] = []


static func _regexes() -> Array[RegEx]:
	if _compiled.is_empty():
		for pattern in PATTERNS:
			var regex := RegEx.new()
			# (?i) makes every pattern case-insensitive.
			regex.compile("(?i)" + pattern)
			_compiled.append(regex)
	return _compiled


## Returns the reserved phrases found in `text` (lower-cased, unique).
static func find_in(text: String) -> Array[String]:
	var hits: Array[String] = []
	for regex in _regexes():
		for found in regex.search_all(text):
			var phrase := found.get_string().to_lower()
			if not hits.has(phrase):
				hits.append(phrase)
	return hits


static func is_clean(text: String) -> bool:
	return find_in(text).is_empty()
