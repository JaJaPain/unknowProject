extends SceneTree

# Dev tool, not a test: prints one real ambient-chat prompt per bucket to
# stdout (between BEGIN/END markers) so a shell can live-fire them against
# Ollama with the exact production request shape. Keeps prompt-tuning honest —
# what we probe is what the game sends (AmbientChatGenerator.build_prompt).

var GenType: GDScript = null


func _initialize() -> void:
	GenType = load("res://scripts/story/AmbientChatGenerator.gd")
	if GenType == null or not GenType.can_instantiate():
		push_error("AmbientChatGenerator.gd did not compile.")
		quit(1)
		return
	var story_state := {
		"active_tensions": ["Dock strikes are spreading past the inner ring."],
		"current_foreshadow": "Every third manifest out of Kova reads a day early.",
		"player_knows": [],
		"pending_hooks": ["A crate stenciled VALE keeps moving between berths."],
	}
	var flavor := "\n".join([
		"Campaign tone: dry, wary, blue-collar",
		"What everyone is worried about: the refinery running while nobody can afford the truth",
		"Humor register: gallows humor about paperwork and repair bills",
	])
	var pair_a := {"name": "Ivet", "role": "dock controller"}
	var pair_b := {"name": "Skiff", "role": "tug pilot"}
	var topics := [
		{"id": "t1", "bucket": GenType.BUCKET_MUNDANE, "subject": "the vending machine that gives double if you hit it right"},
		{"id": "t2", "bucket": GenType.BUCKET_STORY, "subject": "Dock strikes are spreading past the inner ring."},
		{"id": "t3", "bucket": GenType.BUCKET_INTEL, "subject": "A crate stenciled VALE keeps moving between berths."},
	]
	# story_state unused directly here (subjects inlined above) but kept as the
	# reference for where each subject would come from in production.
	var _unused := story_state
	for topic in topics:
		print("===BEGIN %s===" % str(topic["bucket"]))
		print(GenType.build_prompt(topic, pair_a, pair_b, flavor))
		print("===END %s===" % str(topic["bucket"]))
	quit(0)
