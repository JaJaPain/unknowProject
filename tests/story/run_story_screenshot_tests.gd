extends SceneTree

var ShotsType: GDScript = null

var _failures: Array[String] = []


func _initialize() -> void:
	ShotsType = load("res://scripts/story/StoryScreenshots.gd")
	if ShotsType == null or not ShotsType.can_instantiate():
		push_error("[FAIL] StoryScreenshots.gd did not compile — suite cannot run.")
		quit(1)
		return
	_test_path_and_tag_sanitizing()
	_test_headless_capture_is_safe()

	if _failures.is_empty():
		print("[PASS] Story screenshot tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_path_and_tag_sanitizing() -> void:
	var path: String = ShotsType.shot_path("user://campaigns/campaign.test/", "Chapter 3: The Fall", 1783169999)
	_expect(
		path == "user://campaigns/campaign.test/screenshots/1783169999_chapter_3_the_fall.png",
		"shot_path formatting wrong: %s" % path
	)
	_expect(
		str(ShotsType._sanitize_tag("  ")) == "moment",
		"Empty tag should sanitize to 'moment'."
	)
	_expect(
		str(ShotsType._sanitize_tag("hook-resolved.v2")) == "hook_resolved_v2",
		"Tag separators should normalize to underscores."
	)


func _test_headless_capture_is_safe() -> void:
	# Both entry points must be silent no-ops without a rendered frame or with
	# an empty campaign path — never a crash, never a stray file in res://.
	ShotsType.capture_deferred("", "ignored")
	ShotsType.capture_deferred("res://.tmp_godot_user/shot_test_campaign", "headless_probe")
	ShotsType._capture_now("res://.tmp_godot_user/shot_test_campaign", "headless_probe_direct")
	_expect(true, "")  # reaching here without a crash is the assertion


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
