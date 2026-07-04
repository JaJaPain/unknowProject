extends SceneTree
# Compile check for the big scene-attached scripts no headless suite loads
# (UIManager/GameRoot are not autoloads, so parse_check.gd never touches them).
# Runtime load(), not preload — autoloads must be registered first or these
# fail spuriously (see run_story_state_bible_seed_tests harness note).

const _SCRIPTS := [
	"res://scripts/UIManager.gd",
	"res://scripts/GameRoot.gd",
	"res://scripts/ai/NarrativeDirector.gd",
	"res://scripts/ai/Nova.gd",
	"res://scripts/story/StoryQuestManager.gd",
]


func _initialize() -> void:
	var failed := false
	for path in _SCRIPTS:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			push_error("[FAIL] %s did not compile." % path)
			failed = true
	if failed:
		quit(1)
		return
	print("[PASS] Scene script parse check")
	quit(0)
