extends SceneTree

# Parse gate for scripts that aren't reachable from a headless unit suite
# (UIManager is a scene script, not an autoload). --check-only can't be used on
# them: it compiles without a running main loop, so every autoload identifier
# reports as "not found". Loading them from inside a real SceneTree does not.
#
#   Godot --headless --path . --script res://tests/tools/run_parse_check.gd \
#         --log-file <abs>/parse_check.log

const PATHS := [
	"res://scripts/UIManager.gd",
	"res://scripts/ui/CombatPanel.gd",
	"res://scripts/story/IntroCinematic.gd",
	"res://scripts/PlayerShip.gd",
	"res://scripts/story/StoryManager.gd",
	"res://scripts/persistence/StoryStateStore.gd",
	"res://scripts/speech/SpeechService.gd",
	"res://scripts/LLMInterface.gd",
]


func _initialize() -> void:
	var failures: Array[String] = []
	for path in PATHS:
		var script: Resource = load(path)
		if script == null:
			failures.append("%s: failed to load" % path)
			continue
		if script is GDScript and not (script as GDScript).can_instantiate():
			failures.append("%s: loaded but cannot instantiate" % path)
	_test_cast_name_guard(failures)
	if failures.is_empty():
		print("[PASS] parse check (%d scripts) + cast-name guard" % PATHS.size())
		quit(0)
	else:
		for f in failures:
			push_error(f)
		print("[FAIL] parse check: %d case(s)" % failures.size())
		quit(1)


# The collision that actually shipped was "Kaelen Voss" — the broker's given
# name welded onto the Zenith agent's surname. Neither token alone is the whole
# of any cast member's name, which is exactly why a whole-string comparison
# would have let it through.
func _test_cast_name_guard(failures: Array[String]) -> void:
	var llm: GDScript = load("res://scripts/LLMInterface.gd")
	if llm == null:
		failures.append("cast-name guard: LLMInterface failed to load")
		return
	for bad in ["Kaelen Voss", "Caelen Drake", "Jenna Kross", "Director Voss",
			"kaelen voss", "N.O.V.A.", "Mira Kross-Vane"]:
		if not llm.name_collides_with_cast(bad):
			failures.append("cast-name guard: '%s' should collide" % bad)
	for ok in ["Maeve Sterling", "Rorik Flint", "Bel Ashgrove", "Tess Torv",
			"Sloane Mercer"]:
		if llm.name_collides_with_cast(ok):
			failures.append("cast-name guard: '%s' should NOT collide" % ok)
