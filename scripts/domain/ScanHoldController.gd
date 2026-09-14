class_name ScanHoldController
extends RefCounted

## The three-second scan hold (plan P2).
##
## PURE state machine: it is fed distance, speed and combat state each frame and
## returns what the UI should show. No nodes, no globals, so the rules that gate
## evidence are testable without flying a ship.
##
## The hold exists to make scanning a small act of piloting rather than a click:
## hold position, close, and slow. Breaking any condition cancels WITHOUT COST --
## losing progress is the entire penalty, and there is no failure state to
## recover from.
##
## Completion issues a one-shot TOKEN. The capability refuses a scan_complete
## command that does not carry one, so a UI (or a replayed command) cannot assert
## a scan that never happened.

const HOLD_SECONDS := 3.0
const MAX_RANGE := 300.0
const MAX_SPEED := 10.0

const STATE_IDLE := "idle"
const STATE_HOLDING := "holding"
const STATE_BLOCKED := "blocked"
const STATE_COMPLETE := "complete"

var _site_id := ""
var _elapsed := 0.0
var _issued_tokens: Dictionary = {}
var _token_counter := 0


## Feed one frame. Returns {state, progress, reason, token, site_id}.
func update(
	delta: float,
	site_id: String,
	distance: float,
	speed: float,
	in_combat: bool
) -> Dictionary:
	# Switching sites abandons the previous hold rather than carrying progress
	# across, which would let a player bank seconds on an easy site.
	if site_id != _site_id:
		_site_id = site_id
		_elapsed = 0.0
	if site_id.is_empty():
		return _report(STATE_IDLE, "")
	var blocker := _blocking_reason(distance, speed, in_combat)
	if not blocker.is_empty():
		# Cancel WITHOUT cost: progress is lost, nothing else happens.
		_elapsed = 0.0
		return _report(STATE_BLOCKED, blocker)
	_elapsed += maxf(delta, 0.0)
	if _elapsed < HOLD_SECONDS:
		return _report(STATE_HOLDING, "")
	_elapsed = 0.0
	var token := _issue_token(site_id)
	var done := _report(STATE_COMPLETE, "")
	done["token"] = token
	done["progress"] = 1.0
	return done


## Why the hold cannot proceed, or "" when it can.
func _blocking_reason(distance: float, speed: float, in_combat: bool) -> String:
	if in_combat:
		return "in_combat"
	if distance > MAX_RANGE:
		return "out_of_range"
	if speed > MAX_SPEED:
		return "too_fast"
	return ""


func _report(state: String, reason: String) -> Dictionary:
	return {
		"state": state,
		"progress": clampf(_elapsed / HOLD_SECONDS, 0.0, 1.0),
		"reason": reason,
		"site_id": _site_id,
		"token": "",
	}


func _issue_token(site_id: String) -> String:
	_token_counter += 1
	var token := "%s:hold:%d" % [site_id, _token_counter]
	_issued_tokens[token] = site_id
	return token


## Verify and burn a token. One-shot on purpose: a replayed scan_complete must
## not be able to reuse the token from a hold that already paid out.
func consume_token(token: String, site_id: String) -> bool:
	if not _issued_tokens.has(token):
		return false
	if str(_issued_tokens[token]) != site_id:
		return false
	_issued_tokens.erase(token)
	return true


## Progress is deliberately NOT saved. A hold restarts after a load rather than
## resuming, so a save mid-scan cannot be used to bank progress.
func reset() -> void:
	_site_id = ""
	_elapsed = 0.0
