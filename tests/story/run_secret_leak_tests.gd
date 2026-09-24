extends SceneTree

## Guards the fixed-cast undercurrent: no text that can reach a language model
## or a player may contain a reserved topic (see ReservedTopics.gd).
##
## Scans every JSON file under data/content (including premise cards), the lore
## and soul documents, and the quoted strings inside game scripts. Identifiers
## and comments in scripts are not scanned: "dimension" in a maths helper is fine.

const ReservedTopicsType := preload("res://scripts/story/ReservedTopics.gd")

const JSON_ROOTS := ["res://data/content"]
const TEXT_FILES := ["res://docs/world_lore.md"]
const TEXT_DIRS := ["res://docs/narrative/character_souls"]
const SCRIPT_ROOTS := ["res://scripts"]
# The pattern list itself, obviously, contains the words.
const SKIP_SCRIPTS := ["res://scripts/story/ReservedTopics.gd"]

var _failures: Array[String] = []
var _scanned := 0


func _initialize() -> void:
	_test_detector()
	for root in JSON_ROOTS:
		_scan_dir(root, ".json", false)
	for path in TEXT_FILES:
		_scan_file(path, false)
	for dir in TEXT_DIRS:
		_scan_dir(dir, ".md", false)
	for root in SCRIPT_ROOTS:
		_scan_dir(root, ".gd", true)

	if _scanned < 20:
		_failures.append("scanned only %d files; the scan roots are probably wrong" % _scanned)
	if _failures.is_empty():
		print("[PASS] Secret leak tests (%d files scanned)" % _scanned)
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_detector() -> void:
	var dirty := [
		"She came from another universe.",
		"We will bring the Captain back.",
		"An android that passes for human.",
		"The clone walked out of the vat.",
		"Shiny died out there.",
	]
	for text in dirty:
		if ReservedTopicsType.is_clean(text):
			_failures.append("detector missed a reserved topic in: %s" % text)
	var clean := [
		"Deliver 40 cubic metres of silicate to the refinery.",
		"The captain docked and the broker paid in full.",
		"A three-dimensional hologram of the station map.",
	]
	# "three-dimensional" contains "dimensional", which the \bdimensions?\b
	# pattern must not match.
	for text in clean:
		if not ReservedTopicsType.is_clean(text):
			_failures.append("detector flagged clean text: %s -> %s" % [text, ReservedTopicsType.find_in(text)])


func _scan_dir(path: String, extension: String, strings_only: bool) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		_failures.append("could not open %s" % path)
		return
	for file_name in dir.get_files():
		if file_name.ends_with(extension):
			_scan_file(path.path_join(file_name), strings_only)
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_scan_dir(path.path_join(sub), extension, strings_only)


func _scan_file(path: String, strings_only: bool) -> void:
	if path in SKIP_SCRIPTS:
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("could not read %s" % path)
		return
	var text := file.get_as_text()
	file.close()
	_scanned += 1
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i]
		# Code that *blocks* reserved topics (guard lists) is marked and allowed.
		if line.contains("reserved-topics: guard"):
			continue
		var haystack := _quoted_strings(line) if strings_only else line
		if haystack.is_empty():
			continue
		for hit in ReservedTopicsType.find_in(haystack):
			_failures.append("%s:%d contains reserved topic '%s'" % [path, i + 1, hit])


static var _quote_regex: RegEx


func _quoted_strings(line: String) -> String:
	if _quote_regex == null:
		_quote_regex = RegEx.new()
		_quote_regex.compile("\"(?:[^\"\\\\]|\\\\.)*\"")
	var parts: PackedStringArray = []
	for found in _quote_regex.search_all(line):
		parts.append(found.get_string())
	return " ".join(parts)
