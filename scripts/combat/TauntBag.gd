class_name TauntBag
extends RefCounted

# True round-robin over a taunt pool: a line cannot play again until every
# other line in its cause has played.
#
# Random picking was the old behaviour and it reads as broken -- with 30 lines
# a random pick repeats within a handful of fights often enough that the player
# concludes there are five lines. A shuffled bag gives the opposite feel: a
# whole pool's worth of fights before anything comes round again, which is what
# makes growing the pool worth doing at all.
#
# PROGRESS PERSISTS ACROSS RESTARTS. Without that, relaunching restarts every
# bag at the top and the player hears the same opening taunts forever.
#
# The shuffle is SEEDED, so the entire bag round-trips as three numbers instead
# of an index-per-line. That matters: the state is saved every time a line is
# drawn, so a crash or an alt-F4 cannot replay lines, and saving must therefore
# stay cheap no matter how big the pool gets.

# Self-reference for the static factory below. A static method cannot call an
# unqualified new(), and referring to the class_name from inside the file that
# declares it fails to compile before the global class list is built.
const SelfType := preload("res://scripts/combat/TauntBag.gd")

var _seed: int = 0
var _cursor: int = 0
var _size: int = 0
# Texts played most recently, kept across a reshuffle so growing the pool
# mid-cycle cannot produce an audible immediate repeat.
var _recent: Array[String] = []
# Set when the pool changed size: the next draw must open a fresh cycle, and
# only next() has the pool needed to choose a good starting order.
var _pending_cycle_start: bool = false

const RECENT_MEMORY := 25

## Optional deterministic source for cycle seeds. Taunts leave this null and keep
## using global randi(), which is what they want -- an enemy line should not be
## reproducible from a save. Mission selection injects one so a campaign can
## restore its cycle exactly rather than reshuffling on load.
var _rng: RandomNumberGenerator = null


func set_rng(rng: RandomNumberGenerator) -> void:
	_rng = rng


func _next_seed() -> int:
	return int(_rng.randi()) if _rng != null else int(randi())


func _init(pool_size: int = 0, bag_seed: int = 0) -> void:
	_size = maxi(0, pool_size)
	_seed = bag_seed if bag_seed != 0 else _next_seed()
	_cursor = 0


# The seeded order for the current cycle. Rebuilt on demand rather than stored,
# since it is a pure function of (seed, size).
func _order() -> Array[int]:
	var order: Array[int] = []
	for i in range(_size):
		order.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	# Fisher-Yates, driven entirely by the seeded stream.
	for i in range(order.size() - 1, 0, -1):
		var j := int(rng.randi() % (i + 1))
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	return order


# Adjusts to a pool that changed size. Growth is the normal case: background
# refills append lines for the rest of the campaign.
func resize(pool_size: int) -> void:
	var size := maxi(0, pool_size)
	if size == _size:
		return
	_size = size
	_cursor = 0
	if size == 0:
		return
	# A resized pool invalidates the seeded order. Defer choosing the new one
	# until next(), which has the pool and can therefore avoid opening on
	# something just heard.
	_pending_cycle_start = true


# Picks the ORDER for a fresh cycle so its opening stretch avoids lines the
# player just heard.
#
# This is where the two guarantees are reconciled. Exhaustiveness is absolute,
# so a new cycle MUST include everything, including what was just played -- the
# only freedom left is where those land. Re-rolling the seed until the opening
# window is clear pushes them deep into the cycle without ever skipping them.
#
# Best-effort by design: with a pool barely larger than the recent list no seed
# can satisfy the window, and one slightly early repeat is much better than
# spinning here or breaking the no-skip invariant.
# Enough tries that a clean opening is found in practice rather than by luck.
# A shuffle of a few hundred ints is trivial and this runs once per cycle, so
# the cost is irrelevant next to handing the player a line they just heard.
const CYCLE_START_ATTEMPTS := 48


func _start_new_cycle(pool: Array) -> void:
	_pending_cycle_start = false
	_cursor = 0
	if _recent.is_empty():
		_seed = _next_seed()
		return
	var window: int = mini(12, maxi(1, int(_size / 2)))
	# Keep the best candidate seen, so a pool too small for a perfectly clean
	# opening still gets the LEAST repetitive one available instead of whatever
	# the final attempt happened to roll.
	var best_seed := 0
	var best_hits := 1 << 30
	for attempt in range(CYCLE_START_ATTEMPTS):
		_seed = _next_seed()
		var order := _order()
		if order.is_empty():
			return
		var hits := 0
		for i in range(mini(window, order.size())):
			if _recent.has(_text_at(pool, order[i])):
				hits += 1
		if hits == 0:
			return
		if hits < best_hits:
			best_hits = hits
			best_seed = _seed
	_seed = best_seed


func _text_at(pool: Array, index: int) -> String:
	if index < 0 or index >= pool.size():
		return ""
	var entry = pool[index]
	return str((entry as Dictionary).get("text", "")) if entry is Dictionary else str(entry)


# Picks the next line from `pool`, or {} when there is nothing to say.
#
# Exhaustiveness is ABSOLUTE here: every draw advances the cursor by exactly
# one, so a cycle always covers the whole pool before wrapping. An earlier
# version SKIPPED entries that were in recent memory, which quietly burned
# cursor positions -- the cycle then hit its end before every line had played,
# reshuffled early, and repeated. Avoiding recent lines is now handled by
# choosing the cycle's ORDER, never by skipping within it.
func next(pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}
	if _size != pool.size():
		resize(pool.size())
	if _pending_cycle_start or _cursor >= _size:
		_start_new_cycle(pool)
	var order := _order()
	if order.is_empty() or _cursor >= order.size():
		return {}
	var index: int = order[_cursor]
	_cursor += 1
	if index < 0 or index >= pool.size():
		return {}
	var entry = pool[index]
	if not entry is Dictionary:
		return {}
	_remember(str((entry as Dictionary).get("text", "")))
	return entry


func _remember(text: String) -> void:
	if text.is_empty():
		return
	_recent.append(text)
	while _recent.size() > RECENT_MEMORY:
		_recent.pop_front()


# Lines left before this bag wraps. Surfaced in diagnostics so a pool too small
# to feel varied is visible rather than merely felt.
func remaining() -> int:
	return maxi(0, _size - _cursor)


# Three numbers plus the short recent-texts guard -- small enough to write on
# every draw, which is what "saved when used" requires.
func to_dict() -> Dictionary:
	return {
		"seed": _seed,
		"cursor": _cursor,
		"size": _size,
		"recent": _recent.duplicate(),
	}


# Restores a persisted bag. A saved cycle whose size no longer matches the pool
# is restarted rather than trusted, since the seeded order would no longer line
# up with the lines on disk -- but the recent-texts guard is kept either way,
# so a size change still cannot replay something just heard.
static func from_dict(data: Dictionary, pool_size: int) -> RefCounted:
	var bag = SelfType.new(pool_size, int(data.get("seed", 0)))
	var recent: Array[String] = []
	for value in (data.get("recent", []) as Array if data.get("recent", []) is Array else []):
		var text := str(value).strip_edges()
		if not text.is_empty():
			recent.append(text)
	while recent.size() > RECENT_MEMORY:
		recent.pop_front()
	bag._recent = recent
	if int(data.get("size", 0)) == pool_size:
		bag._cursor = clampi(int(data.get("cursor", 0)), 0, pool_size)
	return bag
