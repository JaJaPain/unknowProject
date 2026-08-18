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

const RECENT_MEMORY := 25


func _init(pool_size: int = 0, bag_seed: int = 0) -> void:
	_size = maxi(0, pool_size)
	_seed = bag_seed if bag_seed != 0 else randi()
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
	if size == 0:
		_size = 0
		_cursor = 0
		return
	# A resized pool invalidates the seeded order, so start a fresh cycle. The
	# recent-texts guard below is what stops that from sounding like a repeat.
	_size = size
	_seed = randi()
	_cursor = 0


# Picks the next line from `pool`, or "" when there is nothing to say.
# `pool` is an array of entry dictionaries carrying a "text" key.
func next(pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}
	if _size != pool.size():
		resize(pool.size())
	var order := _order()
	if order.is_empty():
		return {}
	# One full cycle of attempts at most: skip anything in recent memory, but
	# never loop forever when the pool is smaller than that memory.
	var attempts := 0
	var chosen := -1
	while attempts < order.size():
		if _cursor >= order.size():
			_seed = randi()
			_cursor = 0
			order = _order()
		var candidate: int = order[_cursor]
		_cursor += 1
		attempts += 1
		var text := str((pool[candidate] as Dictionary).get("text", "")) \
			if pool[candidate] is Dictionary else str(pool[candidate])
		if _recent.has(text) and pool.size() > _recent.size():
			continue
		chosen = candidate
		break
	if chosen == -1:
		return {}
	var entry = pool[chosen]
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
