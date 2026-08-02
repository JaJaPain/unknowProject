extends SceneTree

# Verifies beat loading, prompt assembly, and that code-side rotation
# actually rotates. Rotation is the mechanism the whole design leans on:
# five attempts to make the model vary these by instruction all failed.

const Beats := preload("res://scripts/story/QuietMomentBeats.gd")
const Checks := preload("res://scripts/story/QuietMomentChecks.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_document_loads()
	_test_every_beat_builds()
	_test_rotation_is_without_replacement()
	_test_lead_in_beats()
	_test_transit_rotates_devices()
	_test_authored_text_passes_own_checks()
	if _failures.is_empty():
		print("[PASS] QuietMomentBeats (all cases)")
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		print("[FAIL] QuietMomentBeats: %d case(s)" % _failures.size())
		quit(1)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _test_document_loads() -> void:
	var doc := Beats.load_document()
	if not bool(doc.get("ok", false)):
		_failures.append("document did not load: %s" % doc.get("reason", "?"))
		return
	var ids := Beats.beat_ids()
	if ids.size() < 12:
		_failures.append("expected >=12 beats, got %d" % ids.size())


func _test_every_beat_builds() -> void:
	var rng := _rng(1234)
	for beat_id in Beats.beat_ids():
		var req := Beats.build_request(str(beat_id), rng)
		if not bool(req.get("ok", false)):
			_failures.append("%s: build failed (%s)" % [beat_id, req.get("reason", "?")])
			continue
		var prompt := str(req.get("prompt", ""))
		if prompt.length() < 200:
			_failures.append("%s: prompt suspiciously short (%d)" % [beat_id, prompt.length()])
		# an unfilled placeholder means a template/vocabulary mismatch
		if prompt.contains("{") and prompt.contains("}"):
			var brace := prompt.find("{")
			var snippet := prompt.substr(brace, 24)
			if not snippet.begins_with("{\"line\""):
				_failures.append("%s: unfilled placeholder near '%s'" % [beat_id, snippet])
		if str(req.get("speaker", "")).is_empty():
			_failures.append("%s: no speaker" % beat_id)
		if (req.get("demos", []) as Array).is_empty():
			_failures.append("%s: no demos shown" % beat_id)


func _test_rotation_is_without_replacement() -> void:
	# Sampling WITH replacement repeated one detail 4/10 in research. Over a
	# full cycle every packet must appear exactly once.
	Beats.reset_rotation()
	var rng := _rng(99)
	var beat_id := "kaelen_low_pay_safe"
	var b := Beats.beat(beat_id)
	var total: int = (b.get("packets", []) as Array).size()
	var seen := {}
	for i in total:
		var req := Beats.build_request(beat_id, rng)
		seen[str(req.get("packet", ""))] = true
	if seen.size() != total:
		_failures.append("packet rotation: %d distinct over a %d cycle (expected %d)"
			% [seen.size(), total, total])


func _test_lead_in_beats() -> void:
	var rng := _rng(7)
	for beat_id in ["nova_post_combat_damaged", "nova_rough_arrival", "nova_long_transit"]:
		var req := Beats.build_request(beat_id, rng)
		if str(req.get("lead_in", "")).strip_edges().is_empty():
			_failures.append("%s: expected a lead-in" % beat_id)
	# beats without a pool must not invent one
	var plain := Beats.build_request("kaelen_declined", rng)
	if not str(plain.get("lead_in", "")).is_empty():
		_failures.append("kaelen_declined: unexpected lead-in")


func _test_transit_rotates_devices() -> void:
	# Naming one device made it formulaic (20/20 identical). Both must appear.
	var rng := _rng(4242)
	var saw_jealousy := false
	var saw_dangle := false
	for i in 8:
		var req := Beats.build_request("nova_long_transit", rng)
		var prompt := str(req.get("prompt", ""))
		if prompt.contains("jealous"):
			saw_jealousy = true
		elif prompt.contains("dangles it in front of him"):
			saw_dangle = true
	if not saw_jealousy:
		_failures.append("transit: jealousy device never selected in 8 draws")
	if not saw_dangle:
		_failures.append("transit: dangle device never selected in 8 draws")


func _test_authored_text_passes_own_checks() -> void:
	# Three defects in this project came from text WE wrote, not the model:
	# packets saying "He walked away", a tool list with hyphenated compounds,
	# and lead-ins using planetary-landing words for a station dock.
	for beat_id in Beats.beat_ids():
		var b := Beats.beat(str(beat_id))
		for lead in b.get("lead_in_pool", []):
			var errors: Array = Checks.screen(str(lead), {
				"speaker": str(b.get("speaker", "")),
				"word_cap": 40,
			})
			for tag in errors:
				if str(tag).begins_with("tts_") or tag == "assumes_captain_gender":
					_failures.append("%s lead-in '%s': %s" % [beat_id, lead, tag])
