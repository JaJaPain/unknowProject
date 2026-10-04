extends SceneTree

## Station skins (Abe, 2026-10-04): mains and outposts wear ChatGPT's models,
## and a new system never repeats a skin of the system before it.
##   Godot --headless --path . --script res://tests/domain/run_station_skins_tests.gd --log-file <path>

const Skins := preload("res://scripts/domain/StationSkins.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	for path in Skins.MAIN + Skins.OUTPOST:
		_check(ResourceLoader.exists(path), "model exists: %s" % path)
	var previous: Array = Skins.START.duplicate()
	for seed_value in range(1, 200):
		var outposts := seed_value % 3
		var skins := Skins.pick(seed_value * 7919, outposts, previous)
		_check(skins.size() == outposts + 1, "one main plus %d outposts" % outposts)
		_check(Skins.MAIN.has(skins[0]), "the main station wears a main model")
		for i in range(1, skins.size()):
			_check(Skins.OUTPOST.has(skins[i]), "outposts wear outpost models")
		for skin in skins:
			_check(not previous.has(skin), "never the previous system's skin: %s" % skin)
		var distinct := {}
		for skin in skins:
			distinct[skin] = true
		_check(distinct.size() == skins.size(), "no two stations alike in one system: %s" % str(skins))
		previous = skins
	_check(Skins.pick(42, 2, []) == Skins.pick(42, 2, []), "the same seed picks the same skins")
	# Saved with the system.
	var config := SystemConfig.new()
	config.seed_value = 5
	config.station_count = 3
	Skins.assign(config, Skins.START)
	var reloaded := SystemConfig.from_dict(config.to_dict())
	_check(reloaded.station_skins == config.station_skins and config.station_skins.size() == 3, "skins survive a save: %s" % str(reloaded.station_skins))
	_check(Skins.of_system(null, "start_system") == Skins.START, "the start system's skins")
	var scene_text := FileAccess.get_file_as_string("res://scenes/systems/system_start.tscn")
	for skin in Skins.START:
		_check(scene_text.contains(skin), "the start scene wears %s" % skin)
	if _failures.is_empty():
		print("[PASS] Station skins")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
