class_name CampaignSystemNames
extends RefCounted

const NAMES_PATH := "user://campaign_systems.json"

const FALLBACK_NAMES: Array[String] = [
	"Ashenveil Reach",
	"Brighthollow",
	"Caldera Deep",
	"Driftmark Expanse",
	"Ember's Wake",
	"Forge Point",
	"Grimshaw Corridor",
	"Hollowstar",
	"Ironveil",
	"Kestrel Run",
	"Lantern's End",
	"Meridian Crossing",
	"Nightfall Basin",
	"Obsidian Drift",
	"Pinnacle",
]

var _names: Array[String] = []
var _used_count: int = 0


static func load_or_create() -> CampaignSystemNames:
	var instance := CampaignSystemNames.new()
	if FileAccess.file_exists(NAMES_PATH):
		var file := FileAccess.open(NAMES_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				var raw_names = parsed.get("names", [])
				for n in raw_names:
					instance._names.append(str(n))
				instance._used_count = int(parsed.get("used_count", 0))
				return instance
	instance._names = FALLBACK_NAMES.duplicate()
	instance._used_count = 0
	return instance


func next_name() -> String:
	if _used_count >= _names.size():
		return "Uncharted System %d" % (_used_count + 1)
	var name_str: String = _names[_used_count]
	_used_count += 1
	_save()
	return name_str


func peek_next() -> String:
	if _used_count >= _names.size():
		return "Uncharted System %d" % (_used_count + 1)
	return _names[_used_count]


func remaining() -> int:
	return max(0, _names.size() - _used_count)


func set_names(names: Array[String]) -> void:
	_names = names
	_used_count = 0
	_save()


func _save() -> void:
	var file := FileAccess.open(NAMES_PATH, FileAccess.WRITE)
	if file:
		var data := {
			"names": _names,
			"used_count": _used_count,
		}
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
