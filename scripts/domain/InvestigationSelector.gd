class_name InvestigationSelector
extends RefCounted

## Chooses which investigation shape a campaign offers next (plan P2).
##
## PURE and persistable: all state lives in a dictionary the caller stores under
## `story_state.investigation_selection`, so a checkpoint restores the cycle
## exactly rather than reshuffling and re-offering something just seen.
##
## Three rules, each protecting a way "fresh" quietly stops being fresh:
##   1. Eligibility filters BEFORE a pool is formed. Skipping ineligible draws
##      inside a cycle silently breaks the no-repeat guarantee the bag provides.
##   2. A shape is retired when it is SHOWN, not when it is accepted. A declined
##      offer the player already read is not new content.
##   3. `last_shape_id` is campaign-wide, so a change in the eligible set cannot
##      immediately replay the shape just offered while another one exists.
##
## What it deliberately does NOT promise: no repetition across different
## eligibility sets. A pool that changes shape is a different cycle.
##
## The cycle is stored EXPLICITLY as `remaining_shape_ids` + `cycle_index` per
## pool signature. A legacy seed/cursor bag is migrated once by replaying a copy
## against the same sorted pool, so an outstanding reservation and the saved bag
## are both left untouched by the conversion.

const BagType := preload("res://scripts/combat/TauntBag.gd")

const STATE_VERSION := 1


static func empty_state(campaign_seed: int = 0) -> Dictionary:
	return {
		"version": STATE_VERSION,
		"campaign_seed": campaign_seed,
		"bags": {},
		"last_shape_id": "",
		"outstanding_offers": [],
	}


## A stable key for one eligible set. Two different sets get two different bags,
## which is why no-repeat is only promised within a set.
static func signature_for(eligible_shape_ids: Array) -> String:
	var ids: Array[String] = []
	for id in eligible_shape_ids:
		ids.append(str(id))
	ids.sort()
	return "|".join(ids)


## Reserve a shape without consuming it. Preparation done ahead of display holds
## its seed but must not advance the bag -- otherwise speculative prefetch would
## burn shapes the player never saw.
static func reserve(state: Dictionary, eligible_shape_ids: Array, offer_id: String) -> Dictionary:
	var existing := _outstanding(state, offer_id)
	if not existing.is_empty():
		return existing
	if eligible_shape_ids.is_empty():
		return {}
	var drawn := _draw(state, eligible_shape_ids)
	if drawn.is_empty():
		return {}
	var reservation := {
		"offer_id": offer_id,
		"shape_id": str(drawn["shape_id"]),
		"seed": int(drawn["seed"]),
		"published": false,
		# Carried, not applied: committing this is what publication means.
		"pending_signature": str(drawn["signature"]),
		"pending_bag": drawn["bag"],
		"pending_remaining_shape_ids": (drawn["remaining_shape_ids"] as Array).duplicate(),
		"pending_cycle_index": int(drawn["cycle_index"]),
	}
	var outstanding: Array = state.get("outstanding_offers", [])
	outstanding.append(reservation)
	state["outstanding_offers"] = outstanding
	return reservation


## Consume the reservation because the offer is actually being SHOWN. Repeated
## panel opens return the same offer rather than drawing again.
static func publish(state: Dictionary, eligible_shape_ids: Array, offer_id: String) -> Dictionary:
	var existing := _outstanding(state, offer_id)
	if not existing.is_empty() and bool(existing.get("published", false)):
		return existing
	if existing.is_empty():
		existing = reserve(state, eligible_shape_ids, offer_id)
		if existing.is_empty():
			return {}
	_commit(state, existing)
	existing["published"] = true
	state["last_shape_id"] = str(existing["shape_id"])
	_replace_outstanding(state, existing)
	return existing


## Drop a finished or declined offer. The shape stays retired either way.
static func release(state: Dictionary, offer_id: String) -> void:
	var kept: Array = []
	for raw in (state.get("outstanding_offers", []) as Array):
		if raw is Dictionary and str((raw as Dictionary).get("offer_id", "")) != offer_id:
			kept.append(raw)
	state["outstanding_offers"] = kept


static func _outstanding(state: Dictionary, offer_id: String) -> Dictionary:
	for raw in (state.get("outstanding_offers", []) as Array):
		if raw is Dictionary and str((raw as Dictionary).get("offer_id", "")) == offer_id:
			return raw
	return {}


static func _replace_outstanding(state: Dictionary, updated: Dictionary) -> void:
	var out: Array = []
	for raw in (state.get("outstanding_offers", []) as Array):
		if raw is Dictionary \
				and str((raw as Dictionary).get("offer_id", "")) == str(updated["offer_id"]):
			out.append(updated)
		else:
			out.append(raw)
	state["outstanding_offers"] = out


## The shape IDs this cycle has not consumed yet, plus the cycle they belong to.
## READ ONLY: migration replays a COPY of the saved bag and commits nothing.
static func _remaining_for(state: Dictionary, record: Dictionary, pool_ids: Array) -> Dictionary:
	var cycle_index := maxi(0, int(record.get("cycle_index", 0)))
	var remaining: Array = []
	var raw: Variant = record.get("remaining_shape_ids", null)
	if raw is Array:
		for id: Variant in (raw as Array):
			if str(id) in pool_ids and str(id) not in remaining:
				remaining.append(str(id))
	else:
		remaining = _migrate_remaining(record, pool_ids)
	if remaining.is_empty():
		# An exhausted (or exhausted-on-migration) cycle opens the next complete
		# one. Every shape in the pool is back in play, none is skipped.
		cycle_index += 1
		remaining = _cycle_order(state, pool_ids, cycle_index)
	return {"remaining": remaining, "cycle_index": cycle_index}


## One-time conversion of a legacy seed/cursor bag into an explicit suffix.
## Replays a COPY against the same sorted pool; the saved bag is never advanced.
static func _migrate_remaining(record: Dictionary, pool_ids: Array) -> Array:
	var saved: Dictionary = record.get("bag", {}) if record.get("bag", {}) is Dictionary else {}
	if saved.is_empty():
		return pool_ids.duplicate()
	var copy = BagType.from_dict(saved.duplicate(true), pool_ids.size())
	var order: Array = copy._order()
	var cursor: int = clampi(int(copy._cursor), 0, pool_ids.size())
	var remaining: Array = []
	for i in range(cursor, order.size()):
		var index := int(order[i])
		if index >= 0 and index < pool_ids.size():
			var id := str(pool_ids[index])
			if id not in remaining:
				remaining.append(id)
	return remaining


## Deterministic order for a fresh cycle, from the campaign seed and the cycle
## number alone, so a restored campaign opens the same cycle it would have.
static func _cycle_order(state: Dictionary, pool_ids: Array, cycle_index: int) -> Array:
	var order: Array = pool_ids.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(state.get("campaign_seed", 0)) ^ 0x1D3F) + cycle_index
	for i in range(order.size() - 1, 0, -1):
		var j := int(rng.randi() % (i + 1))
		var tmp: Variant = order[i]
		order[i] = order[j]
		order[j] = tmp
	return order


## Choose the next shape WITHOUT consuming it.
##
## `preference_order` is the caller's ranking of the same shapes (the novelty
## ranker's order in practice). The remaining set of the cycle is authoritative
## about WHICH shapes are still available; the ranking decides which of those to
## take. A shape excluded for repeating `last_shape_id` stays in the remaining
## set -- exclusion never burns an entry.
static func _draw(state: Dictionary, eligible_shape_ids: Array) -> Dictionary:
	var signature := signature_for(eligible_shape_ids)
	var pool_ids: Array = []
	for entry: Dictionary in _pool(eligible_shape_ids):
		pool_ids.append(str(entry["id"]))
	if pool_ids.is_empty():
		return {}
	var bags: Dictionary = state.get("bags", {})
	var record: Dictionary = bags.get(signature, {}) if bags.get(signature, {}) is Dictionary else {}
	var cycle := _remaining_for(state, record, pool_ids)
	var remaining: Array = cycle["remaining"]
	if remaining.is_empty():
		return {}
	var preference: Array = []
	for id: Variant in eligible_shape_ids:
		if str(id) in remaining and str(id) not in preference:
			preference.append(str(id))
	for id: Variant in remaining:
		if str(id) not in preference:
			preference.append(str(id))
	var last := str(state.get("last_shape_id", ""))
	var shape_id := ""
	for id: Variant in preference:
		if str(id) != last:
			shape_id = str(id)
			break
	if shape_id.is_empty():
		# Only the just-offered shape is left in this cycle: take it rather than
		# stall, since another remaining shape is what the exclusion requires.
		shape_id = str(preference[0])
	var next_remaining: Array = []
	for id: Variant in remaining:
		if str(id) != shape_id:
			next_remaining.append(str(id))
	return {
		"shape_id": shape_id,
		"seed": _seed_for(state, shape_id),
		"signature": signature,
		"bag": record.get("bag", {}) if record.get("bag", {}) is Dictionary else {},
		"remaining_shape_ids": next_remaining,
		"cycle_index": int(cycle["cycle_index"]),
	}


## Write back exactly what the reservation's draw decided. Committing a stored
## result is what makes publication a single derivation -- re-deriving it here is
## what previously offered a shape twice in one cycle.
static func _commit(state: Dictionary, reservation: Dictionary) -> void:
	var signature := str(reservation.get("pending_signature", ""))
	if signature.is_empty():
		return
	var bags: Dictionary = state.get("bags", {})
	var record: Dictionary = bags.get(signature, {}) if bags.get(signature, {}) is Dictionary else {}
	record["bag"] = reservation.get("pending_bag", {})
	record["remaining_shape_ids"] = (reservation.get("pending_remaining_shape_ids", []) as Array).duplicate()
	record["cycle_index"] = maxi(0, int(reservation.get("pending_cycle_index", 0)))
	bags[signature] = record
	state["bags"] = bags


static func _pool(eligible_shape_ids: Array) -> Array:
	var ids: Array[String] = []
	for id in eligible_shape_ids:
		ids.append(str(id))
	ids.sort()   # stable ordering, so a restored cycle means the same thing
	var pool: Array = []
	for id in ids:
		pool.append({"id": id, "text": id})
	return pool


static func _rng_for(state: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(state.get("campaign_seed", 0)) ^ 0x1D3F
	return rng


## A per-offer seed derived from the campaign seed and the shape, so mission
## truth is reproducible from persisted state alone.
static func _seed_for(state: Dictionary, shape_id: String) -> int:
	var base := int(state.get("campaign_seed", 0))
	var drawn := int(state.get("draw_counter", 0)) + 1
	state["draw_counter"] = drawn
	return abs(hash("%d:%s:%d" % [base, shape_id, drawn])) & 0x7FFFFFFF
