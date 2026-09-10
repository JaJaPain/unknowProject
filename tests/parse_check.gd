extends SceneTree
# Minimal headless parse checker — loads autoloads then quits immediately.
# Run after each implementation step to catch parser/compile errors early.
func _init() -> void:
	quit(0)
