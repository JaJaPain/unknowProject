class_name UndercurrentDirector
extends Node

## Decides the fixed cast's rarest moments (plan Section 5). Code-owned, no
## language model, no logging. Director-only: see
## docs/fresh_eyes_vision_plan_2026_09_23.md Section 5 before changing anything.
##
## The death line: on a very rare eligible death, the screen goes black and a
## baked line plays before the ordinary death screen.
##   - never before MIN_PLAY_SECONDS of total play on this machine,
##   - never before MIN_PRIOR_DEATHS earlier deaths,
##   - DEATH_LINE_CHANCE per eligible death,
##   - a random line among the approved ones not yet heard,
##   - each line at most once per machine (more variants need Abe's approval),
##   - COOLDOWN_PLAY_SECONDS of play between any two undercurrent moments.

const LedgerType := preload("res://scripts/story/undercurrent/EchoLedgerStore.gd")
const LINES_PATH := "res://data/content/undercurrent_lines.json"

const MIN_PLAY_SECONDS := 5.0 * 3600.0
const MIN_PRIOR_DEATHS := 5
## Abe (2026-09-24): "very low, like 5-8 percent", then one line at random.
const DEATH_LINE_CHANCE := 0.06
const COOLDOWN_PLAY_SECONDS := 20.0 * 3600.0
const SAVE_EVERY_SECONDS := 60.0

var ledger_path := LedgerType.DEFAULT_PATH
var ledger: Dictionary = LedgerType.empty()
var rng := RandomNumberGenerator.new()
var _lines: Array = []
var _pending_moment: Dictionary = {}
var _unsaved_seconds := 0.0
var counting_play_time := true


func _init() -> void:
	rng.randomize()


func _ready() -> void:
	ledger = LedgerType.load_ledger(ledger_path)
	_lines = _load_lines()


func _process(delta: float) -> void:
	if not counting_play_time or get_tree().paused:
		return
	ledger["play_seconds"] = float(ledger["play_seconds"]) + delta
	_unsaved_seconds += delta
	if _unsaved_seconds >= SAVE_EVERY_SECONDS:
		_unsaved_seconds = 0.0
		LedgerType.save_ledger(ledger, ledger_path)


func _exit_tree() -> void:
	LedgerType.save_ledger(ledger, ledger_path)


## Called for every player death. Returns true if the death line should play.
## The moment is then collected once by consume_death_moment().
func on_player_death() -> bool:
	var prior := int(ledger.get("deaths", 0))
	ledger["deaths"] = prior + 1
	var line := _eligible_death_line(prior)
	if not line.is_empty() and rng.randf() < DEATH_LINE_CHANCE:
		var shown: Dictionary = ledger.get("lines_shown", {})
		shown[str(line["id"])] = int(shown.get(str(line["id"]), 0)) + 1
		ledger["lines_shown"] = shown
		ledger["last_shown_play_seconds"] = float(ledger["play_seconds"])
		_pending_moment = {"id": str(line["id"]), "audio": str(line.get("audio", "")), "text": str(line.get("text", ""))}
	LedgerType.save_ledger(ledger, ledger_path)
	return not _pending_moment.is_empty()


## The pending moment (or {}), cleared on read.
func consume_death_moment() -> Dictionary:
	var moment := _pending_moment
	_pending_moment = {}
	return moment


func _eligible_death_line(prior_deaths: int) -> Dictionary:
	var played := float(ledger.get("play_seconds", 0.0))
	if played < MIN_PLAY_SECONDS or prior_deaths < MIN_PRIOR_DEATHS:
		return {}
	var last := float(ledger.get("last_shown_play_seconds", -1.0))
	if last >= 0.0 and played - last < COOLDOWN_PLAY_SECONDS:
		return {}
	var fresh: Array = []
	for line in _lines:
		if str(line.get("kind", "")) != "death_line" or not bool(line.get("approved_by_abe", false)):
			continue
		if int((ledger.get("lines_shown", {}) as Dictionary).get(str(line["id"]), 0)) > 0:
			continue
		fresh.append(line)
	return fresh[rng.randi_range(0, fresh.size() - 1)] if not fresh.is_empty() else {}


func _load_lines() -> Array:
	if not FileAccess.file_exists(LINES_PATH):
		return []
	var file := FileAccess.open(LINES_PATH, FileAccess.READ)
	var json := JSON.new()
	var ok := json.parse(file.get_as_text()) == OK
	file.close()
	if not ok or not json.data is Dictionary:
		return []
	return (json.data as Dictionary).get("lines", [])


## Loads a baked line's audio: the imported resource if the editor has
## imported it, otherwise straight from the .ogg file.
static func load_line_audio(res_path: String) -> AudioStream:
	if res_path.is_empty():
		return null
	if ResourceLoader.exists(res_path):
		var stream = load(res_path)
		if stream is AudioStream:
			return stream
	var absolute := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(absolute):
		return AudioStreamOggVorbis.load_from_file(absolute)
	return null
