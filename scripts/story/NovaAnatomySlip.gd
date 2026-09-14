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

const PARTS := {
	"larynx": "vocal processor",
	"throat": "intake trunk",
	"lungs": "air scrubbers",
	"ribs": "frame spars",
	"ribcage": "frame spars",
	"spine": "keel",
	"backbone": "keel",
	"sternum": "keel plate",
	"waist": "midsection coupling",
	"hips": "gimbal mounts",
	"knees": "landing gear",
	"ankles": "landing struts",
	"jaw": "docking clamp",
	"teeth": "grapple hooks",
	"veins": "coolant lines",
	"nerves": "sensor net",
	"eyes": "optical array",
	"ears": "audio pickups",
	"hair": "antenna array",
	"fingers": "manipulators",
	"elbows": "articulation joints",
	"wrists": "articulation joints",
	"neck": "dorsal spine housing",
	"shoulders": "dorsal mounts",
}

const TEMPLATES := [
	"Or at least my %s.",
	"My %s, technically.",
	"Well. My %s.",
]

# She has already corrected herself; a second correction reads as a stutter.
const ALREADY_CORRECTED := ["or at least", "i mean", "figure of speech", "well, not"]

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
	var tail := template % machine
	var separator := " "
	var last := clean.strip_edges()
	if not last.is_empty() and not ".!?".contains(last.right(1)):
		separator = ". "
	return "%s%s%s" % [clean.strip_edges(), separator, tail]


# Only HER body. "you could feel it in your bones" is the Captain's, and
# correcting that would be nonsense.
static func _find_own_part(low: String) -> String:
	for part in PARTS:
		if low.contains("my %s" % part):
			return str(part)
	return ""


func reset() -> void:
	_recent.clear()


func to_save_dict() -> Dictionary:
	return {"recent_corrections": _recent.duplicate()}


func load_from_dict(data: Dictionary) -> void:
	_recent.clear()
	for entry in data.get("recent_corrections", []):
		_recent.append(str(entry))
