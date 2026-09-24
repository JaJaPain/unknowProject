class_name FactionDNA
extends RefCounted

## Faction DNA (plan Section 3.3): what makes a generated faction FELT, not
## just named. Derived from the faction id alone (deterministic; nothing new
## is saved), so any system can rebuild it.
##
##   axes:      order (+) vs freedom (-), profit (+) vs duty (-),
##              mercy (+) vs force (-), each -1..1
##   language:  a phoneme set their people and ships are named from
##   doctrine:  how they fight (for combat AI and taunts later)
##   silhouette + wear: ship design language (for ShipAssembler, visual pass)
##
## `judge_deed()` is how this faction reads something the pilot did: the same
## deed is brave to one faction and a crime to another (plan Section 3.4).

const LANGUAGES := {
	"clipped": {"onsets": ["K", "T", "D", "Br", "Kr", "St", "V"], "vowels": ["a", "o", "e", "u"], "codas": ["k", "t", "rk", "st", "d", "x", ""],
		"ship_words": ["Anvil", "Bulwark", "Rivet", "Ration", "Quota", "Bastion", "Clamp", "Warrant"]},
	"flowing": {"onsets": ["L", "M", "N", "S", "El", "Ay", "Th"], "vowels": ["ae", "ia", "e", "i", "ai", "o"], "codas": ["l", "n", "s", "th", "", ""],
		"ship_words": ["Solace", "Tide", "Hymn", "Lantern", "Veil", "Meridian", "Grace", "Current"]},
	"guttural": {"onsets": ["Gr", "Gh", "Hr", "Kh", "Dr", "Ur", "Og"], "vowels": ["u", "o", "a", "au"], "codas": ["g", "gh", "rn", "m", "k", "r"],
		"ship_words": ["Maw", "Grudge", "Tusk", "Hammer", "Scar", "Boulder", "Furnace", "Howl"]},
	"sibilant": {"onsets": ["S", "Sh", "Z", "Ss", "Ch", "Is", "Xe"], "vowels": ["i", "e", "ee", "a"], "codas": ["s", "sh", "z", "ss", "n", ""],
		"ship_words": ["Whisper", "Needle", "Cipher", "Silk", "Shade", "Stiletto", "Rumour", "Hush"]},
	"bright": {"onsets": ["P", "B", "J", "Fl", "T", "C", "M"], "vowels": ["i", "a", "e", "o"], "codas": ["p", "n", "ll", "m", "", "ck", "sy"],
		"ship_words": ["Jubilee", "Penny", "Spark", "Ticket", "Kite", "Bargain", "Fiddle", "Postcard"]},
	"ceremonial": {"onsets": ["Ae", "Ol", "Ver", "Cal", "Ser", "Om", "Ev"], "vowels": ["a", "e", "io", "u", "ae"], "codas": ["n", "m", "r", "th", "l", "us"],
		"ship_words": ["Covenant", "Reliquary", "Vigil", "Litany", "Chalice", "Oath", "Canticle", "Pilgrim"]},
}
const DOCTRINES := ["swarm", "heavy_line", "drone_screen", "ambush", "honour_duel", "hit_and_run"]
const SILHOUETTES := ["long", "spiky", "boxy", "asymmetric", "flat", "bulbous"]
const WEAR := ["pristine", "patched", "scorched", "salvaged"]

## Deed verbs -> what they say about the pilot, on the same axes.
const DEED_SIGNALS := {
	"saved": {"mercy": 1.0}, "rescued": {"mercy": 1.0}, "protected": {"mercy": 0.6, "order": 0.3},
	"secured": {"order": 0.8}, "stopped": {"order": 0.7}, "sealed": {"order": 0.6}, "enforced": {"order": 1.0},
	"broke": {"order": -0.9}, "smuggled": {"order": -0.8, "profit": 0.4}, "stole": {"order": -0.7, "profit": 0.7},
	"freed": {"order": -0.6, "mercy": 0.6}, "sabotaged": {"order": -0.7, "mercy": -0.3},
	"killed": {"mercy": -1.0}, "destroyed": {"mercy": -0.8}, "staged": {"mercy": -0.6, "order": -0.4}, "assassination": {"mercy": -1.0},
	"exposed": {"order": 0.4, "profit": -0.4}, "bought": {"profit": 0.8}, "sold": {"profit": 0.9}, "won": {"profit": 0.5},
	"spared": {"mercy": 1.0}, "spread": {"order": -0.3}, "cheated": {"profit": 0.6, "mercy": -0.4},
	"helped": {"mercy": 0.6}, "defended": {"mercy": 0.6, "order": 0.4}, "restored": {"mercy": 0.5, "order": 0.3},
	"covered": {"mercy": 0.4, "order": -0.3}, "erased": {"mercy": 0.5, "profit": -0.6},
	"betrayed": {"mercy": -0.6}, "avenged": {"mercy": -0.6}, "sank": {"mercy": -0.8}, "murdered": {"mercy": -1.0},
	"caught": {"order": 0.8}, "busted": {"order": 0.8}, "certified": {"order": 0.5}, "recovered": {"order": 0.4}, "found": {"order": 0.3},
	"bypassed": {"order": -0.6}, "breached": {"order": -0.6}, "repealed": {"order": -0.5}, "beat": {"order": -0.5},
	"burned": {"order": -0.4}, "buried": {"order": -0.3, "profit": 0.3}, "robbed": {"order": -0.8, "profit": 0.7},
	"broadcast": {"order": -0.4, "profit": -0.3}, "published": {"order": -0.3, "profit": -0.3},
	"collected": {"profit": 0.7}, "opened": {"profit": 0.4},
}


static func for_faction(faction_id: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("faction_dna|%s" % faction_id)
	var languages := LANGUAGES.keys()
	languages.sort()
	return {
		"axes": {"order": snappedf(rng.randf_range(-1.0, 1.0), 0.05), "profit": snappedf(rng.randf_range(-1.0, 1.0), 0.05),
			"mercy": snappedf(rng.randf_range(-1.0, 1.0), 0.05)},
		"language": str(languages[rng.randi_range(0, languages.size() - 1)]),
		"doctrine": DOCTRINES[rng.randi_range(0, DOCTRINES.size() - 1)],
		"silhouette": SILHOUETTES[rng.randi_range(0, SILHOUETTES.size() - 1)],
		"wear": WEAR[rng.randi_range(0, WEAR.size() - 1)],
	}


## A person named in the faction's language: "Krostad Vek", "Aelian Serth".
static func person_name(dna: Dictionary, rng: RandomNumberGenerator) -> String:
	var lang: Dictionary = LANGUAGES.get(str(dna.get("language", "")), LANGUAGES["clipped"])
	var given := _word(lang, rng, rng.randi_range(1, 2))
	var family := _word(lang, rng, rng.randi_range(1, 2))
	return "%s %s" % [given, family]


## A ship named the way this faction names ships: "the Grudge of Hrakum".
static func ship_name(dna: Dictionary, rng: RandomNumberGenerator) -> String:
	var lang: Dictionary = LANGUAGES.get(str(dna.get("language", "")), LANGUAGES["clipped"])
	var word := _pick(rng, lang["ship_words"])
	if rng.randi_range(0, 1) == 0:
		return "the %s" % word
	return "the %s of %s" % [word, _word(lang, rng, 2)]


## How this faction reads a deed tag: "admire", "approve", "shrug",
## "disapprove" or "condemn". Tags are free-form card vocabulary; verbs in the
## tag carry the meaning.
static func judge_deed(dna: Dictionary, deed_tag: String) -> String:
	var sig := deed_signal(deed_tag)
	if sig.is_empty():
		return "shrug"
	var axes: Dictionary = dna.get("axes", {})
	var score := 0.0
	for axis in sig.keys():
		score += float(sig[axis]) * float(axes.get(axis, 0.0))
	if score >= 0.6:
		return "admire"
	if score >= 0.2:
		return "approve"
	if score <= -0.6:
		return "condemn"
	if score <= -0.2:
		return "disapprove"
	return "shrug"


## The combined axis signal of a deed tag's verbs ({} when none are known).
static func deed_signal(deed_tag: String) -> Dictionary:
	var out := {}
	for part in deed_tag.to_lower().split("_"):
		var s: Dictionary = DEED_SIGNALS.get(part, {})
		for axis in s.keys():
			out[axis] = clampf(float(out.get(axis, 0.0)) + float(s[axis]), -1.0, 1.0)
	return out


static func _word(lang: Dictionary, rng: RandomNumberGenerator, syllables: int) -> String:
	var w := ""
	for i in syllables:
		w += _pick(rng, lang["onsets"]).to_lower() if i > 0 else _pick(rng, lang["onsets"])
		w += _pick(rng, lang["vowels"])
	w += _pick(rng, lang["codas"])
	# No tripled letters ("Xeee") and no three vowels in a row ("Oluolaem" is fine, "Aeio" isn't).
	var tidy := RegEx.new()
	tidy.compile("(.)\\1\\1+")
	w = tidy.sub(w, "$1$1", true)
	tidy.compile("([aeiou]{2})[aeiou]+")
	return tidy.sub(w, "$1", true)


static func _pick(rng: RandomNumberGenerator, options: Array) -> String:
	return str(options[rng.randi_range(0, options.size() - 1)])
