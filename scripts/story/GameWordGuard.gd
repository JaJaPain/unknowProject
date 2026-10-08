extends RefCounted

## Words that only make sense to a game designer, never in a line a character
## says or a rumour on the radio (Abe, playtest 2026-10-08 finding 7: a
## lounge rumour quoted "Player finds a dead ship..." from a planning note).
## Whole words, case-insensitive.

const WORDS := ["player", "players", "npc", "npcs", "quest", "quests", "questline",
	"playthrough", "gameplay", "cutscene", "hostile-class", "reaver-class"]


## The first game word in `text`, or "".
static func game_word(text: String) -> String:
	var lower := " " + text.to_lower() + " "
	for w in WORDS:
		var at := lower.find(w)
		while at >= 0:
			var before := lower[at - 1]
			var after := lower[at + w.length()] if at + w.length() < lower.length() else " "
			if not _letter(before) and not _letter(after):
				return w
			at = lower.find(w, at + 1)
	return ""


static func is_clean(text: String) -> bool:
	return game_word(text).is_empty()


static func _letter(c: String) -> bool:
	return c >= "a" and c <= "z"
