class_name NameForge
extends RefCounted

## Seeded names for people and ships cast into premise-card arcs.
##
## A placeholder for Faction DNA naming (plan Section 3.3): once factions carry
## their own phoneme sets, callers pass those in and names start sounding like
## the faction they belong to. Until then, a neutral frontier palette.

const FIRST_SYLLABLES := ["Ka", "Vel", "Or", "Ish", "Dar", "Mi", "Tor", "Sa", "Re", "Ul", "Ane", "Bry", "Co", "Ez", "Fen", "Ha", "Jo", "Lio", "Ny", "Pe", "Ro", "Tam", "Wen", "Ya"]
const FIRST_ENDINGS := ["ra", "n", "ssa", "k", "lo", "ne", "vi", "ric", "ta", "el", "mo", "ya", "dric", "sha", "ro", ""]
const FAMILY_PARTS := ["Ander", "Brask", "Corr", "Dahl", "Everett", "Fane", "Gorin", "Holt", "Iver", "Jarr", "Kessel", "Lund", "Marr", "Novak", "Orsk", "Pryce", "Quill", "Rask", "Sabel", "Tannor", "Ulric", "Vance", "Wyle", "Yarrow"]
const FAMILY_ENDINGS := ["", "", "son", "sdottir", "ov", "ek", "e", "ley", "man", "is"]
const SHIP_ADJECTIVES := ["Stubborn", "Patient", "Quiet", "Iron", "Late", "Honest", "Second", "Lucky", "Grey", "Last", "Crooked", "Far", "Steady", "Borrowed", "Hollow", "Bright"]
const SHIP_NOUNS := ["Margin", "Mercy", "Ledger", "Anchor", "Promise", "Harvest", "Wake", "Debt", "Signal", "Tithe", "Lantern", "Ballast", "Errand", "Omen", "Compass", "Wager"]


static func person_name(rng: RandomNumberGenerator) -> String:
	var first := _pick(rng, FIRST_SYLLABLES) + _pick(rng, FIRST_ENDINGS)
	var family := _pick(rng, FAMILY_PARTS) + _pick(rng, FAMILY_ENDINGS)
	return "%s %s" % [first, family]


static func ship_name(rng: RandomNumberGenerator) -> String:
	return "the %s %s" % [_pick(rng, SHIP_ADJECTIVES), _pick(rng, SHIP_NOUNS)]


static func _pick(rng: RandomNumberGenerator, options: Array) -> String:
	return str(options[rng.randi_range(0, options.size() - 1)])
