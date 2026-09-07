class_name SiteRevealModel
extends RefCounted

## What the overview is allowed to show about an investigation site (plan P2).
##
## PURE: distance and sensor tier in, display state out.
##
## The point is that a site is FOUND, not listed. A fresh system should not hand
## the player a to-do list of every anomaly in it -- that turns exploration into
## errand-running. So a site is invisible until sensors reach it, appears first
## as an unidentified contact, and only earns its real name once scanned.
##
## Once scanned, a site stays visible at ANY range. Hiding something the player
## already found and identified is not mystery, it is losing your notes.

const TIER_RANGES := {
	"basic": 600.0,
	"improved": 900.0,
	"advanced": 1200.0,
}
const DEFAULT_TIER := "basic"

## Distance over which a contact fades in, so it resolves out of the noise
## rather than popping into existence.
const FADE_UNITS := 50.0

const STATE_HIDDEN := "hidden"
const STATE_CONTACT := "contact"
const STATE_IDENTIFIED := "identified"

const CONTACT_LABEL := "Signal contact"


## Sensor range for a tier. An unknown tier falls back to basic rather than to
## zero -- a typo in a ship definition should weaken sensors, not blind them.
static func range_for_tier(tier: String) -> float:
	if TIER_RANGES.has(tier):
		return float(TIER_RANGES[tier])
	return float(TIER_RANGES[DEFAULT_TIER])


## Display state for one site.
## Returns {state, label, alpha, targetable}.
static func reveal_for(
	distance: float,
	tier: String,
	is_scanned: bool,
	site_name: String = ""
) -> Dictionary:
	if is_scanned:
		# Already found: never hide it again, whatever the range.
		return {
			"state": STATE_IDENTIFIED,
			"label": site_name if not site_name.is_empty() else CONTACT_LABEL,
			"alpha": 1.0,
			"targetable": true,
		}
	var sensor_range := range_for_tier(tier)
	if distance > sensor_range:
		return {
			"state": STATE_HIDDEN,
			"label": "",
			"alpha": 0.0,
			"targetable": false,
		}
	# Inside sensor range but not yet scanned: an unidentified contact, fading in
	# over the last stretch of approach.
	var closed := sensor_range - distance
	var alpha := clampf(closed / FADE_UNITS, 0.0, 1.0) if FADE_UNITS > 0.0 else 1.0
	return {
		"state": STATE_CONTACT,
		"label": CONTACT_LABEL,
		"alpha": alpha,
		# Targetable as soon as it is detected, so the player can fly at a faint
		# contact -- chasing a smudge is the good part.
		"targetable": true,
	}
