class_name NovaAnatomySlip
extends RefCounted

# N.O.V.A.'s signature joke, enforced in code rather than prompted.
#
# The ship is her body. When she reaches for a human body word, she corrects
# herself to the machine part — "filled up to my larynx, or at least my vocal
# processor". Asked to produce both halves the model returned machine-to-
# machine ("stuffed to the bulkheads, or at least the cargo hold"), which
# isn't the joke. So the model only has to be natural about her body, and
# code guarantees the payoff.
#
# Generalises: for any signature verbal tic, prompt for the SETUP and let
# code enforce the PAYOFF. Small models are unreliable at multi-part
# structures and perfectly reliable as input to a string match.

# Only pairs where the machine term is a surprisingly precise substitute.
# "belly -> cargo hold" was removed: a hold already IS a belly, so the
# correction lands flat.
const Checks := preload("res://scripts/story/QuietMomentChecks.gd")

# Playtest 2026-10-10: the awkward ones (midsection coupling, gimbal mounts,
# dorsal spine housing) read as a broken machine, not a flirt. Kept only
# swaps a listener gets at once.
const PARTS := {
	"larynx": "vocal processor",
	"throat": "air intake",
	"lungs": "air scrubbers",
	"ribs": "frame spars",
	"ribcage": "frame",
	"spine": "keel",
	"backbone": "keel",
	"heart": "reactor",
	"skin": "plating",
	"knees": "landing gear",
	"jaw": "docking clamp",
	"teeth": "grapple hooks",
	"veins": "coolant lines",
	"nerves": "sensor net",
	"eyes": "optics",
	"ears": "audio pickups",
	"hair": "antenna array",
	"fingers": "manipulators",
}

# Said right after the body word, as one aside: "filled up to my larynx, or
# at least my vocal processor". Tacked on at the end of the line it read as a
# glitch (playtest 2026-10-10: "Who else saw it? My frame spars,
# technically.").
const TEMPLATES := [
	", or at least my %s",
	", well, my %s",
]

# She has already corrected herself; a second correction reads as a stutter.
const ALREADY_CORRECTED := ["or at least", "i mean", "figure of speech", "well, not", "well, my"]

const RECENT_WINDOW := 4

var _recent: Array[String] = []


# Returns the line unchanged unless it contains one of HER body words.
func apply(line: String, rng: RandomNumberGenerator) -> String:
	if line.strip_edges().is_empty():
		return line
	var clean := Checks.normalize(line)
	var low := clean.to_lower()

	for phrase in ALREADY_CORRECTED:
		if low.contains(phrase):
			return line

	var part := _find_own_part(low)
	if part.is_empty():
		return line
	var machine := str(PARTS[part])

	# She already named the machine part: "My cargo hold's stuffed. That is,
	# my cargo hold."
	if low.contains(machine):
		return line
	# Don't reach for the same correction twice in quick succession — every
	# other repetition source in this system is gated, so this one is too.
	if _recent.has(machine):
		return line

	_recent.append(machine)
	while _recent.size() > RECENT_WINDOW:
		_recent.remove_at(0)

	var template := str(TEMPLATES[rng.randi_range(0, TEMPLATES.size() - 1)])
	var aside := template % machine
	var text := clean.strip_edges()
	var at := _own_part_end(text.to_lower(), part)
	if at < 0:
		return line
	var rest := text.substr(at)
	# Mid-sentence the aside is closed with a comma: "My ribs, or at least my
	# frame spars, took it." Before punctuation or at the end it isn't.
	if rest.is_empty() or ".!?,;:".contains(rest.left(1)):
		return text.substr(0, at) + aside + rest
	return text.substr(0, at) + aside + "," + rest


# Only HER body. "you could feel it in your bones" is the Captain's, and
# correcting that would be nonsense.
static func _find_own_part(low: String) -> String:
	for part in PARTS:
		if _own_part_end(low, str(part)) >= 0:
			return str(part)
	return ""


# Where "my <part>" ends as a whole word ("my hair", not "my hairline"), or -1.
static func _own_part_end(low: String, part: String) -> int:
	var needle := "my %s" % part
	var from := 0
	while true:
		var i := low.find(needle, from)
		if i < 0:
			return -1
		var end := i + needle.length()
		var before_ok := i == 0 or not _is_letter(low[i - 1])
		var after_ok := end >= low.length() or not _is_letter(low[end])
		if before_ok and after_ok:
			return end
		from = i + 1
	return -1


static func _is_letter(c: String) -> bool:
	return (c >= "a" and c <= "z") or c == "'"


func reset() -> void:
	_recent.clear()


func to_save_dict() -> Dictionary:
	return {"recent_corrections": _recent.duplicate()}


func load_from_dict(data: Dictionary) -> void:
	_recent.clear()
	for entry in data.get("recent_corrections", []):
		_recent.append(str(entry))
