extends Node
## Serialised, priority-ordered queue for anything that wants exclusive player
## attention: combat encounters, story beats, ambient events, future UI popups,
## faction notifications, tutorial overlays — all go through here.
##
## Usage (any system):
##
##   var id := PlayerInteractionQueue.enqueue(
##       PlayerInteractionQueue.Priority.COMBAT,
##       func(done: Callable): _start_my_fight(done),
##       "NPCShip:Vanguard_7"
##   )
##   # When your interaction finishes, call the `done` callable the queue passed in.
##   # That releases the slot and advances the queue.
##   PlayerInteractionQueue.cancel(id)  # if the intent is no longer relevant
##
## The callback signature is:  func(done: Callable) -> void
## Call done.call() when your interaction is complete.

# ── Priority tiers ─────────────────────────────────────────────────────────────
# Lower number = higher priority. Add new tiers here as needed.
enum Priority {
	COMBAT  = 0,   # Live ship attack — absolute precedence
	STORY   = 1,   # Story beats, Kaelen lines, narrative triggers
	AMBIENT = 2,   # Spawns, scans, non-critical world events
	UI      = 3,   # Popups, notifications, faction pings (future)
}

# ── Signals ───────────────────────────────────────────────────────────────────
signal intent_started(intent_id: String, priority: int, source: String)
signal intent_completed(intent_id: String)
signal queue_drained()

# ── Config ────────────────────────────────────────────────────────────────────
## Wall-clock ms to block after combat ends. No NPC can re-engage during this
## window, giving Story a guaranteed slot and the player a breather.
const COMBAT_COOLDOWN_MS  := 3000
## How often the tick checks whether the next intent can run.
const TICK_INTERVAL_SEC   := 0.25

# ── Internal state ────────────────────────────────────────────────────────────
var _queue: Array[Dictionary]  = []   # sorted by priority then enqueue time
var _active_id:       String   = ""   # id of the currently running intent
var _active_priority: int      = -1   # priority of the running intent
var _cooldown_until:  int      = 0    # ticks_msec() when combat buffer expires
var _tick_timer:      Timer

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_tick_timer = Timer.new()
	_tick_timer.name        = "IQTick"
	_tick_timer.wait_time   = TICK_INTERVAL_SEC
	_tick_timer.autostart   = true
	_tick_timer.one_shot    = false
	_tick_timer.timeout.connect(_tick)
	add_child(_tick_timer)

# ── Public API ────────────────────────────────────────────────────────────────

## Register an interaction intent. Returns the unique intent id.
## callback signature: func(done: Callable) -> void
## Call done.call() inside your callback when the interaction is finished.
func enqueue(
	priority: Priority,
	callback: Callable,
	source:   String = ""
) -> String:
	var id := "%s_%d_%d" % [Priority.keys()[priority], Time.get_ticks_msec(), randi()]
	var entry := {
		"id":          id,
		"priority":    int(priority),
		"callback":    callback,
		"source":      source,
		"enqueued_at": Time.get_ticks_msec(),
	}
	_queue.append(entry)
	_sort_queue()
	_log("enqueued [%s] from '%s' (queue size: %d)" % [_priority_name(priority), source, _queue.size()])
	return id

## Remove a pending intent before it runs (e.g. the NPC that wanted to fight
## was destroyed before the slot opened). No-op if the id is not in the queue.
func cancel(id: String) -> void:
	var before := _queue.size()
	_queue = _queue.filter(func(e: Dictionary) -> bool: return e["id"] != id)
	if _queue.size() < before:
		_log("cancelled intent '%s'" % id)

## True if an intent is actively running OR intents are waiting.
func is_busy() -> bool:
	return not _active_id.is_empty() or not _queue.is_empty()

## True while combat is live or the post-combat buffer has not elapsed.
## Story and lower-priority systems poll this before acting.
func in_combat_window() -> bool:
	return CombatManager.state != CombatManager.State.IDLE \
		or Time.get_ticks_msec() < _cooldown_until

## Remaining ms in the post-combat cooldown (0 when clear).
func cooldown_remaining_ms() -> int:
	return maxi(0, _cooldown_until - Time.get_ticks_msec())

# ── Called by CombatManager when a fight ends ─────────────────────────────────
## Starts the post-combat buffer. CombatManager calls this from end_combat().
func notify_combat_ended() -> void:
	_cooldown_until = Time.get_ticks_msec() + COMBAT_COOLDOWN_MS
	_log("combat ended — %dms buffer started" % COMBAT_COOLDOWN_MS)
	# If a COMBAT intent was the active one, complete it now.
	if _active_priority == int(Priority.COMBAT):
		_complete_active()

# ── Internal ──────────────────────────────────────────────────────────────────

func _tick() -> void:
	if _queue.is_empty() or not _active_id.is_empty():
		return
	var next: Dictionary = _queue[0]
	if not _can_run(next["priority"]):
		return
	_queue.pop_front()
	_active_id       = next["id"]
	_active_priority = next["priority"]
	_log("starting [%s] from '%s'" % [_priority_name(next["priority"]), next["source"]])
	intent_started.emit(_active_id, _active_priority, next["source"])
	# Pass a `done` callable into the callback so the intent controls when it
	# releases the slot — works for both sync and async interactions.
	var done := func() -> void: _complete_active()
	next["callback"].call(done)

func _complete_active() -> void:
	if _active_id.is_empty():
		return
	_log("completed '%s'" % _active_id)
	var finished_id := _active_id
	_active_id       = ""
	_active_priority = -1
	intent_completed.emit(finished_id)
	if _queue.is_empty():
		queue_drained.emit()

func _can_run(priority: int) -> bool:
	match priority:
		int(Priority.COMBAT):
			# NPC-initiated fights must respect the post-combat breather.
			# Player-initiated attacks call CombatManager directly, so they are
			# still allowed to start immediately when the player chooses to engage.
			return CombatManager.state == CombatManager.State.IDLE \
				and Time.get_ticks_msec() >= _cooldown_until
		int(Priority.STORY), int(Priority.AMBIENT), int(Priority.UI):
			# All non-combat intents wait until combat is fully over + buffer elapsed.
			return not in_combat_window()
		_:
			return true

func _sort_queue() -> void:
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["priority"] != b["priority"]:
			return a["priority"] < b["priority"]
		return a["enqueued_at"] < b["enqueued_at"]
	)

func _priority_name(p: int) -> String:
	var keys := Priority.keys()
	for k in keys:
		if Priority[k] == p:
			return k
	return "UNKNOWN(%d)" % p

func _log(msg: String) -> void:
	GlobalState.trace("[TRACE] [InteractionQueue] " + msg)
