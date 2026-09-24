class_name SystemQuirkRunner
extends Node

## Applies the current system's quirks in play (rules in SystemQuirkEffects).
## Owned by GameRoot; `enter_system()` on arrival, `leave_system()` on jump.
## Set `enabled = false` to switch every quirk effect off.
##
## Hazard clocks only run while the pilot is in open space (not docked, not
## paused), so a dock never hides a sweep that lands the moment they undock.

const EffectsType := preload("res://scripts/story/quirks/SystemQuirkEffects.gd")
const FEED_COLOR := Color(0.95, 0.75, 0.4)

var enabled := true
var effects: Dictionary = {}
var _t := 0.0
# Last announced phase per hazard index ("calm"/"warning"/"active" + cycle).
var _last_phase: Dictionary = {}


# The GlobalState autoload, by path (keeps this node loadable in headless tests).
func _gs() -> Node:
	return get_node("/root/GlobalState")


func enter_system(quirks: Array) -> void:
	leave_system()
	if not enabled:
		return
	effects = EffectsType.effects_for(quirks)
	_gs().system_environment = EffectsType.environment_at(effects, 0.0)
	for note in effects.get("notes", []):
		_gs().emit_chatter("NAV", str(note), FEED_COLOR)


func leave_system() -> void:
	effects = {}
	_t = 0.0
	_last_phase = {}
	_gs().system_environment = {}


func _process(delta: float) -> void:
	if not enabled or effects.is_empty() or (effects.get("hazards", []) as Array).is_empty():
		return
	var ship = _gs().player
	if _gs().paused or ship == null or not is_instance_valid(ship) or bool(ship.get("is_docked")) or bool(ship.get("destroyed")):
		return
	_t += delta
	_gs().system_environment = EffectsType.environment_at(effects, _t)
	var hazards: Array = effects["hazards"]
	for i in hazards.size():
		var h: Dictionary = hazards[i]
		var now := EffectsType.phase(h, _t)
		var key := "%s:%d" % [now["state"], now["cycle"]]
		if _last_phase.get(i, "") == key:
			continue
		var was := str(_last_phase.get(i, "calm:0")).split(":")[0]
		_last_phase[i] = key
		_on_phase(h, str(now["state"]), was, ship)


func _on_phase(h: Dictionary, state: String, was: String, ship: Node) -> void:
	var kind := str(h["kind"])
	match state:
		"warning":
			if EffectsType.WARNINGS.has(kind):
				_gs().emit_chatter("NAV", EffectsType.WARNINGS[kind], FEED_COLOR)
		"active":
			if kind == "pulsar_sweep":
				var drain := EffectsType.pulsar_drain(h, float(_gs().shield_capacity), float(ship.get("current_shield")))
				if drain > 0.0:
					ship.set("current_shield", float(ship.get("current_shield")) - drain)
				_flash(Color(0.85, 0.9, 1.0, 0.35))
			elif EffectsType.STARTS.has(kind):
				_gs().emit_chatter("NAV", EffectsType.STARTS[kind], FEED_COLOR)
		"calm":
			if was == "active" and EffectsType.ENDS.has(kind):
				_gs().emit_chatter("NAV", EffectsType.ENDS[kind], FEED_COLOR)


## A brief full-screen wash so a sweep is felt, not just read in the feed.
func _flash(color: Color) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.layer = 90
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	add_child(layer)
	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.0, 0.7)
	tween.tween_callback(layer.queue_free)
