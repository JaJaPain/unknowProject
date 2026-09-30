extends RefCounted

## Keeps generated stories from recasting the fixed cast (Abe, 2026-09-28: a
## campaign bible made Kaelen the player's creditor and harasser, and an agent
## repeated it). Kaelen is the player's broker and N.O.V.A. their ship; a story
## may give them angles and secrets, but never make them the player's creditor,
## tormentor, threat or enemy. Debts and threats belong to invented NPCs.
##
## Checked sentence by sentence: a sentence fails when it names a fixed-cast
## member (or belongs to a beat bound to one) and uses a hostile-role word.

const NAMES := ["kaelen", "nova", "n.o.v.a"]
const ENTITY_IDS := ["npc.kaelen", "ai.nova"]
const HOSTILE := [
	"debt", "owe", "owes", "owed", "creditor", "repay", "pay back", "payback", "unpaid",
	"harass", "harassment", "threat", "threaten", "threatens", "threats", "extort",
	"blackmail", "coerce", "hunts", "hunting you", "enemy", "villain", "betray",
	"won't let go", "collector", "demand payment", "demands payment",
]


## The offending sentences in `text`, or [] if it is clean. With
## `bound_to_cast`, the text belongs to a beat bound to a fixed-cast member, so a
## hostile word counts even when no name appears ("her continued harassment").
static func offending_sentences(text: String, bound_to_cast: bool = false) -> Array[String]:
	var found: Array[String] = []
	for raw in text.replace("!", ".").replace("?", ".").replace(";", ".").split("."):
		var sentence := raw.strip_edges()
		var lower := sentence.to_lower()
		if lower.is_empty():
			continue
		if not bound_to_cast and not _names_cast(lower):
			continue
		for word in HOSTILE:
			if _has_word(lower, word):
				found.append(sentence)
				break
	return found


## Offending sentences across a list of values (strings, arrays, dictionaries).
static func scan(values: Array, bound_to_cast: bool = false) -> Array[String]:
	var found: Array[String] = []
	for value in values:
		if value is String:
			found.append_array(offending_sentences(value, bound_to_cast))
		elif value is Array:
			found.append_array(scan(value, bound_to_cast))
		elif value is Dictionary:
			found.append_array(scan((value as Dictionary).values(), bound_to_cast))
	return found


static func is_cast_entity(entity_id: String) -> bool:
	return entity_id in ENTITY_IDS


## A Kaelen line that calls her "Kaelen" is her talking about herself in the
## third person ("You owe Kaelen a favor").
static func kaelen_third_person(line: String) -> bool:
	return _has_word(line.to_lower(), "kaelen")


static func _names_cast(lower: String) -> bool:
	for name in NAMES:
		if _has_word(lower, name):
			return true
	return false


static func _has_word(lower: String, word: String) -> bool:
	var regex := RegEx.new()
	regex.compile("(^|[^a-z])" + word.replace(".", "\\.") + "('s)?([^a-z]|$)")
	return regex.search(lower) != null
