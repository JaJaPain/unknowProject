extends RefCounted

## Campaign titles across ALL campaigns, kept outside the save slots so it
## survives deleting saves (Abe, 2026-10-07: titles kept repeating, several
## with "ledger"; the old guard lived in each slot's idea memory and started
## empty every new campaign). The large model is shown recent titles and the
## words they overuse before it writes a bible, and a title that reuses a main
## word from a recent one is sent back once more (NarrativeDirector).
##
## Newest last: [{title, reveal, lane}]. "" path turns it off (tests, smoke).

static var path := "user://campaign_title_history.json"
const KEEP := 40
## How many recent titles the model sees and is checked against.
const RECENT := 12
## A word in this many recent titles is banned outright.
const OVERUSED_AT := 2
const _STOP := {"the": true, "of": true, "a": true, "an": true, "and": true, "in": true, "to": true,
	"for": true, "on": true, "at": true, "by": true, "with": true, "from": true, "into": true}


static func entries() -> Array:
	if path.is_empty() or not FileAccess.file_exists(path):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Array else []


## The last `n` values of `key` ("title", "reveal" or "lane"), newest first.
static func recent(key: String, n: int = RECENT) -> Array:
	var out: Array = []
	var all := entries()
	for i in range(all.size() - 1, -1, -1):
		var v := str((all[i] as Dictionary).get(key, "")).strip_edges()
		if not v.is_empty():
			out.append(v)
		if out.size() >= n:
			break
	return out


static func record(title: String, reveal: String = "", lane: String = "") -> void:
	if path.is_empty() or title.strip_edges().is_empty():
		return
	var all := entries()
	all.append({"title": title.strip_edges(), "reveal": reveal.strip_edges(), "lane": lane})
	if all.size() > KEEP:
		all = all.slice(all.size() - KEEP)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all, "\t"))


## The main words of a title (lowercase, 4+ letters, no small words).
static func words(title: String) -> Array:
	var out: Array = []
	var token := ""
	for c in (title.to_lower() + " "):
		if (c >= "a" and c <= "z") or c == "'":
			token += c
			continue
		token = token.trim_suffix("'s").replace("'", "")
		if token.length() >= 4 and not _STOP.has(token) and not out.has(token):
			out.append(token)
		token = ""
	return out


## Words used in OVERUSED_AT or more of `titles`.
static func overused(titles: Array) -> Array:
	var counts := {}
	for t in titles:
		for w in words(str(t)):
			counts[w] = int(counts.get(w, 0)) + 1
	var out: Array = []
	for w in counts.keys():
		if int(counts[w]) >= OVERUSED_AT:
			out.append(w)
	out.sort()
	return out


## The main word `title` shares with any of `titles`, or "".
static func shared_word(title: String, titles: Array) -> String:
	var mine := words(title)
	for t in titles:
		for w in words(str(t)):
			if mine.has(w):
				return w
	return ""


## The prompt block: recent titles and banned words ("" with no history).
static func avoid_text(titles: Array) -> String:
	if titles.is_empty():
		return ""
	var lines := ["Recent campaigns were titled: %s." % "; ".join(titles.map(func(t): return "\"%s\"" % t)),
		"Give this campaign a title that shares no main word with any of them."]
	var banned := overused(titles)
	if not banned.is_empty():
		lines.append("These words are overused; never use them in the title: %s." % ", ".join(banned))
	return " ".join(lines)
