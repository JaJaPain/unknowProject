extends SceneTree

const Slip := preload("res://scripts/story/NovaAnatomySlip.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	var s := Slip.new()
	# a body word of HERS gets the correction appended
	var out := s.apply("My ribs are aching from it.", rng)
	if not out.to_lower().contains("frame spars"):
		_failures.append("no correction appended: %s" % out)

	# the Captain's body is not hers to correct
	s.reset()
	out = s.apply("You could feel it in your bones.", rng)
	if out != "You could feel it in your bones.":
		_failures.append("rewrote the Captain's body: %s" % out)

	# already self-corrected: don't stack a second one
	s.reset()
	out = s.apply("Stuffed to my ribs. Or at least the frame spars.", rng)
	if out.to_lower().count("frame spars") > 1:
		_failures.append("stacked a second correction: %s" % out)

	# machine term already present reads as a stutter
	s.reset()
	out = s.apply("My keel took it fine, and so did my spine.", rng)
	if out.to_lower().count("keel") > 1:
		_failures.append("stuttered: %s" % out)

	# same correction must not repeat back to back
	s.reset()
	var first := s.apply("My ribs are sore.", rng)
	var second := s.apply("My ribs ache again.", rng)
	if second.to_lower().contains("frame spars"):
		_failures.append("repeated the same correction: %s" % second)
	if not first.to_lower().contains("frame spars"):
		_failures.append("first correction missing: %s" % first)

	# the aside follows the word it corrects (playtest 2026-10-10)
	s.reset()
	out = s.apply("My ribs are clean. The paint's chipped where they hit.", rng)
	if not (out.begins_with("My ribs, or at least my frame spars, are clean.") or out.begins_with("My ribs, well, my frame spars, are clean.")):
		_failures.append("aside not right after the word: %s" % out)
	s.reset()
	out = s.apply("That load has me filled up to my larynx.", rng)
	if not (out == "That load has me filled up to my larynx, or at least my vocal processor." or out == "That load has me filled up to my larynx, well, my vocal processor."):
		_failures.append("aside at the end of a sentence: %s" % out)
	s.reset()
	out = s.apply("Somebody brushed my hairline.", rng)
	if out != "Somebody brushed my hairline.":
		_failures.append("matched inside a longer word: %s" % out)

	# no body word at all: untouched
	s.reset()
	out = s.apply("Every bay is packed and the doors are shut.", rng)
	if out != "Every bay is packed and the doors are shut.":
		_failures.append("modified a line with no body word: %s" % out)

	# persistence
	s.reset()
	s.apply("My throat is dry.", rng)
	var reloaded := Slip.new()
	reloaded.load_from_dict(s.to_save_dict())
	out = reloaded.apply("My throat is still dry.", rng)
	if out.to_lower().contains("air intake"):
		_failures.append("recency did not survive save/load: %s" % out)

	if _failures.is_empty():
		print("[PASS] NovaAnatomySlip (all cases)")
		quit(0)
		return
	for f in _failures:
		push_error(f)
	print("[FAIL] NovaAnatomySlip: %d case(s)" % _failures.size())
	quit(1)
