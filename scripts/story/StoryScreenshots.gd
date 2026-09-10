class_name StoryScreenshots
extends RefCounted

# Silent narrative-moment screenshots (docs/design_narrative_system.md: the
# campaign-closure PDF embeds them alongside the prose). No UI, no sound —
# capture a clean frame and move on. Saved beside the campaign's other
# documents so the future PDF generator finds them with the save:
#   <campaign_path>/screenshots/<unix>_<tag>.png
#
# Callers fire-and-forget via capture_deferred(); the actual GPU readback runs
# at end of frame so we never grab a half-drawn viewport. Headless runs (tests)
# and missing viewports are safe no-ops.

const SUBDIR := "screenshots"
# Hard cap per campaign — a very long campaign should not quietly eat the disk.
# Oldest-moment coverage matters more than newest here (the PDF wants the whole
# arc), so past the cap we simply stop capturing rather than rotate.
const MAX_SHOTS_PER_CAMPAIGN := 200


static func shot_path(campaign_path: String, tag: String, unix_time: int) -> String:
	var clean_tag := _sanitize_tag(tag)
	return "%s/%s/%d_%s.png" % [campaign_path.trim_suffix("/"), SUBDIR, unix_time, clean_tag]


static func _sanitize_tag(tag: String) -> String:
	var out := ""
	for ch in tag.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			out += ch
		elif ch == " " or ch == "-" or ch == ".":
			out += "_"
	return out if not out.is_empty() else "moment"


# Fire-and-forget: schedules the capture for end of the current frame.
static func capture_deferred(campaign_path: String, tag: String) -> void:
	if campaign_path.strip_edges().is_empty():
		return
	# Headless (tests, CI): nothing is ever drawn, and a frame_post_draw
	# connection that never fires dangles into shutdown — skip entirely.
	if DisplayServer.get_name() == "headless":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	# RenderingServer.frame_post_draw fires after the frame is fully rendered —
	# the one moment a viewport grab is guaranteed complete.
	RenderingServer.frame_post_draw.connect(
		func() -> void: _capture_now(campaign_path, tag),
		CONNECT_ONE_SHOT
	)


static func _capture_now(campaign_path: String, tag: String) -> void:
	# Same headless guard as capture_deferred (defense in depth for direct
	# calls): the dummy rasterizer errors on texture reads.
	if DisplayServer.get_name() == "headless":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	# The root Window IS the viewport — root.get_viewport() would ask for its
	# PARENT viewport, which is null.
	var viewport := tree.root as Viewport
	if viewport == null:
		return
	var texture := viewport.get_texture()
	if texture == null:
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		return  # headless / not yet rendered — silent no-op
	var dir_path := "%s/%s" % [campaign_path.trim_suffix("/"), SUBDIR]
	var abs_dir := ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var count := 0
	dir.list_dir_begin()
	while not dir.get_next().is_empty():
		count += 1
	dir.list_dir_end()
	if count >= MAX_SHOTS_PER_CAMPAIGN:
		return
	var path := shot_path(campaign_path, tag, int(Time.get_unix_time_from_system()))
	var err := image.save_png(path)
	if err != OK:
		push_warning("[StoryScreenshots] save failed (%d): %s" % [err, path])
		return
	print("[StoryScreenshots] captured %s" % path)
