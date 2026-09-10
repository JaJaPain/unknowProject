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


## Draw the next shape and return it together with the bag state that draw
## produced. The bag is NOT written back here -- the reservation carries it until
## publication, so speculative preparation cannot burn a shape the player never
## saw.
##
## Deliberately one derivation. An earlier version peeked, then re-derived the
## same draw when committing, and the two could disagree -- which offered the
## same shape twice inside a cycle.
static func _draw(state: Dictionary, eligible_shape_ids: Array) -> Dictionary:
	var signature := signature_for(eligible_shape_ids)
	var bags: Dictionary = state.get("bags", {})
	var record: Dictionary = bags.get(signature, {}) if bags.get(signature, {}) is Dictionary else {}
	var pool := _pool(eligible_shape_ids)
	var bag = BagType.from_dict(record.get("bag", {}), pool.size())
	bag.set_rng(_rng_for(state))
	var picked: Dictionary = bag.next(pool)
	if picked.is_empty():
		return {}
	var shape_id := str(picked.get("text", ""))
	# Campaign-wide guard: a changed eligible set must not immediately replay the
	# shape just offered while a different one is available.
	if shape_id == str(state.get("last_shape_id", "")) and pool.size() > 1:
		var alternative: Dictionary = bag.next(pool)
		if not alternative.is_empty():
			shape_id = str(alternative.get("text", ""))
	return {
		"shape_id": shape_id,
		"seed": _seed_for(state, shape_id),
		"signature": signature,
		"bag": bag.to_dict(),
	}


## Write back the bag state the reservation's draw already produced. Committing a
## stored result is what makes publication a single derivation -- re-deriving the
## draw here is what previously offered a shape twice in one cycle.
static func _commit(state: Dictionary, reservation: Dictionary) -> void:
	var signature := str(reservation.get("pending_signature", ""))
	if signature.is_empty():
		return
	var bags: Dictionary = state.get("bags", {})
	var record: Dictionary = bags.get(signature, {}) if bags.get(signature, {}) is Dictionary else {}
	record["bag"] = reservation.get("pending_bag", {})
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
