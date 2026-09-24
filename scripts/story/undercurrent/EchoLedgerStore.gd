class_name EchoLedgerStore
extends RefCounted

## Per-machine memory for the fixed cast's undercurrent (plan Section 5.5).
## Lives in user://, outside every campaign slot, so it survives campaign
## deletion. Counters and flags only: no story text.
##
## Director-only. Nothing here is ever shown, logged to the chronicle, or sent
## to a language model.

const VERSION := 1
const DEFAULT_PATH := "user://echo_ledger.json"


static func empty() -> Dictionary:
	return {"version": VERSION, "play_seconds": 0.0, "deaths": 0, "lines_shown": {}, "last_shown_play_seconds": -1.0}


static func load_ledger(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return empty()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return empty()
	var json := JSON.new()
	var ok := json.parse(file.get_as_text()) == OK
	file.close()
	if not ok or not json.data is Dictionary or int((json.data as Dictionary).get("version", 0)) != VERSION:
		return empty()
	var ledger: Dictionary = json.data
	for key in empty().keys():
		if not ledger.has(key):
			ledger[key] = empty()[key]
	return ledger


static func save_ledger(ledger: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var temp := "%s.tmp" % path
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(ledger))
	file.close()
	var dir := DirAccess.open(path.get_base_dir())
	return dir != null and dir.rename(temp.get_file(), path.get_file()) == OK
