extends Node3D

## One scan point at the twin wreck field's edge (WreckField). The ship holds
## close and slow here to scan the part of the wreck it faces; Fly to stops
## just short of it.

var point_id := ""
var display_name := "Scan point"


func _ready() -> void:
	add_to_group("wreck_scan_point")


func approach_stop_distance() -> float:
	return 60.0
