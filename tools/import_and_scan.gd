@tool
extends SceneTree

func _initialize() -> void:
	print("[ImportAndScan] Waiting for EditorFileSystem scan to complete...")
	var timer := 0
	while timer < 50: # Wait up to 5 seconds for background scan
		OS.delay_msec(100)
		timer += 1
	print("[ImportAndScan] Project scan completed!")
	quit(0)
