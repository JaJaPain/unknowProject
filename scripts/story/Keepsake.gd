extends RefCounted

## The Captain's story at the end of a campaign (campaign spine plan, Section 5).
##
## Retiring gives a keepsake; ending the story after the ship is lost gives the
## same record told as a eulogy. Built by code from the records only (N.O.V.A.'s
## journal, the people met, their fates, the Destination log), with authored
## sentence patterns, so every line is true. No model, no speaker: it is the
## record, not N.O.V.A. or Kaelen talking. Text that trips the reserved-topic
## guard is dropped, never shown.
##
## facts: {mode: "retire"|"eulogy", campaign, days, credits, kills,
##   journal: [{minute, system, title, text, ended, deeds}] (newest first, as
##   PremiseDirector.journal() gives it), people: [{entity_id, name, story,
##   system, minute}], fates: {entity_id: [fate]}, hand: name or "",
##   destination: title or "", reached: [{title, season}], lost_in: system name}
## Returns {title, subtitle, chapters: [{heading, paragraphs: [text]}]}.

const ReservedTopicsType := preload("res://scripts/story/ReservedTopics.gd")

const MAX_DEEDS := 14
const MAX_PEOPLE := 10

## What each fate says about the people left behind (RecurringCast fates).
const LEFT_BEHIND := {
	"alive_grateful": "%s, who never forgot that the Captain came through for them.",
	"owes_debt": "%s, who still owes the Captain, and knows it.",
	"alive_grudge": "%s, who still blames the Captain, and says so to anyone who asks.",
	"promoted": "%s, who came out of it with a promotion.",
	"ruined": "%s, who lost nearly everything along the way.",
	"exposed": "%s, whose secrets came out.",
	"fled": "%s, who ran and started over somewhere else.",
	"disappeared": "%s, who dropped out of sight.",
}


static func build(facts: Dictionary) -> Dictionary:
	var eulogy := str(facts.get("mode", "retire")) == "eulogy"
	var campaign := _text(facts.get("campaign", ""), "An unnamed campaign")
	var chapters: Array = []
	chapters.append(_chapter("Who the Captain was" if eulogy else "How it started", _opening(facts, eulogy)))
	var met := _people(facts, eulogy)
	if not met.is_empty():
		chapters.append(_chapter("Who they left behind" if eulogy else "Who they met", met))
	var deeds := _deeds(facts)
	if not deeds.is_empty():
		chapters.append(_chapter("What they did", deeds))
	chapters.append(_chapter("The Destination", _destination(facts)))
	chapters.append(_chapter("How it ended", _ending(facts, eulogy)))
	for chapter in chapters:
		chapter["paragraphs"] = (chapter["paragraphs"] as Array).filter(func(p): return ReservedTopicsType.is_clean(str(p)))
	return {"title": campaign,
		"subtitle": "In memory of the Captain" if eulogy else "The Captain's story",
		"chapters": chapters.filter(func(c): return not (c["paragraphs"] as Array).is_empty())}


static func _chapter(heading: String, paragraphs: Array) -> Dictionary:
	return {"heading": heading, "paragraphs": paragraphs}


static func _text(value, fallback := "") -> String:
	var s := str(value).strip_edges() if value != null else ""
	return s if not s.is_empty() else fallback


static func _oldest_first(facts: Dictionary) -> Array:
	var list: Array = (facts.get("journal", []) as Array).duplicate()
	list.sort_custom(func(a, b): return int(a.get("minute", 0)) < int(b.get("minute", 0)))
	return list


static func _opening(facts: Dictionary, eulogy: bool) -> Array:
	var out: Array = []
	var days := maxi(int(facts.get("days", 1)), 1)
	var span := "one day" if days == 1 else "%d days" % days
	if eulogy:
		out.append("The Captain flew for %s. This is what the record keeps of them." % span)
	else:
		out.append("The Captain flew for %s before setting the ship down for good. This is what the record keeps." % span)
	var first: Array = _oldest_first(facts)
	if not first.is_empty():
		var f: Dictionary = first[0]
		var where := _text(f.get("system", ""))
		out.append("The first story on the record was %s%s." % [_text(f.get("title", ""), "a small job"),
			(", in %s" % where) if not where.is_empty() else ""])
	var credits := int(facts.get("credits", 0))
	var kills := int(facts.get("kills", 0))
	var tally := "They finished with %s credits to their name" % _thousands(credits)
	if kills > 0:
		tally += " and %d %s behind them" % [kills, "fight" if kills == 1 else "fights"]
	out.append(tally + ".")
	return out


static func _thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


static func _people(facts: Dictionary, eulogy: bool) -> Array:
	var fates: Dictionary = facts.get("fates", {})
	var seen := {}
	var out: Array = []
	for p in facts.get("people", []):
		var id := str(p.get("entity_id", ""))
		var name := _text(p.get("name", ""))
		if name.is_empty() or seen.has(id if not id.is_empty() else name):
			continue
		seen[id if not id.is_empty() else name] = true
		var list: Array = fates.get(id, [])
		var fate := str(list[list.size() - 1]) if not list.is_empty() else ""
		if fate == "dead":
			out.append("%s, who did not live to see the end of it." % name)
		elif LEFT_BEHIND.has(fate):
			out.append(LEFT_BEHIND[fate] % name)
		else:
			var where := _text(p.get("system", ""))
			out.append("%s, met in %s." % [name, where] if not where.is_empty() else "%s." % name)
		if out.size() >= MAX_PEOPLE:
			break
	return out


static func _deeds(facts: Dictionary) -> Array:
	var out: Array = []
	for entry in _oldest_first(facts):
		var title := _text(entry.get("title", ""))
		var text := _text(entry.get("text", ""))
		if title.is_empty() and text.is_empty():
			continue
		var where := _text(entry.get("system", ""))
		var head := "%s%s." % [title if not title.is_empty() else "A story", (" (%s)" % where) if not where.is_empty() else ""]
		var line := head + ((" " + text) if not text.is_empty() else "")
		var deeds: Array = entry.get("deeds", [])
		if not deeds.is_empty():
			line += " " + " ".join(deeds.map(func(d): return str(d).strip_edges()))
		if not bool(entry.get("ended", false)):
			line += " It was still unfinished."
		out.append(line)
	# The most recent stories matter most at the end; keep the latest.
	if out.size() > MAX_DEEDS:
		out = out.slice(out.size() - MAX_DEEDS)
	return out


static func _destination(facts: Dictionary) -> Array:
	var out: Array = []
	for r in facts.get("reached", []):
		var title := _text(r.get("title", ""))
		if not title.is_empty():
			out.append("In season %d the Captain reached %s." % [int(r.get("season", 1)), title])
	var now := _text(facts.get("destination", ""))
	if not now.is_empty():
		out.append("The last Destination they chased was %s." % now)
	var hand := _text(facts.get("hand", ""))
	if not hand.is_empty():
		out.append("Behind it all was %s, and the Captain found them out." % hand)
	elif not out.is_empty():
		out.append("Someone was behind it all. The Captain never learned who.")
	if out.is_empty():
		out.append("The Captain never learned where everyone was heading.")
	return out


static func _ending(facts: Dictionary, eulogy: bool) -> Array:
	if not eulogy:
		return ["The Captain retired with the ship intact and the stories told. The lanes go on without them."]
	var where := _text(facts.get("lost_in", ""))
	return ["The ship was lost%s, on the Captain's last flight." % ((" in %s" % where) if not where.is_empty() else ""),
		"The lanes go on without them. The people above remember."]


## Plain text (tests and the reader's copy).
static func to_text(keepsake: Dictionary) -> String:
	var lines: PackedStringArray = [str(keepsake.get("title", "")), str(keepsake.get("subtitle", "")), ""]
	for chapter in keepsake.get("chapters", []):
		lines.append(str(chapter["heading"]).to_upper())
		for p in chapter["paragraphs"]:
			lines.append(str(p))
		lines.append("")
	return "\n".join(lines)


## A standalone page to keep (saved next to the saves, openable in a browser).
static func to_html(keepsake: Dictionary) -> String:
	var body := ""
	for chapter in keepsake.get("chapters", []):
		body += "<h2>%s</h2>\n" % _esc(str(chapter["heading"]))
		for p in chapter["paragraphs"]:
			body += "<p>%s</p>\n" % _esc(str(p))
	return """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>%s</title>
<style>
body{background:#0b0a0d;color:#ddd8cf;font:17px/1.6 Georgia,serif;margin:0;padding:48px 16px}
main{max-width:640px;margin:0 auto}
h1{color:#f0c86a;font-weight:normal;letter-spacing:.04em;margin:0}
.sub{color:#9a948a;margin:4px 0 40px}
h2{color:#e0a957;font-size:14px;letter-spacing:.18em;text-transform:uppercase;margin:36px 0 8px}
p{margin:0 0 12px}
</style></head>
<body><main><h1>%s</h1><div class="sub">%s</div>
%s</main></body></html>
""" % [_esc(str(keepsake.get("title", ""))), _esc(str(keepsake.get("title", ""))), _esc(str(keepsake.get("subtitle", ""))), body]


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


## A file name from the campaign title: letters, digits and dashes.
static func file_name(keepsake: Dictionary, unix_time: int) -> String:
	var slug := ""
	for c in str(keepsake.get("title", "campaign")).to_lower():
		slug += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "-"
	while slug.contains("--"):
		slug = slug.replace("--", "-")
	slug = slug.trim_prefix("-").trim_suffix("-")
	return "%s-%d.html" % [slug if not slug.is_empty() else "campaign", unix_time]
