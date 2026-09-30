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
		_used_count += 1
		_save()
		return generated_name(_used_count)
	var name_str: String = _names[_used_count]
	_used_count += 1
	_save()
	return name_str


func peek_next() -> String:
	if _used_count >= _names.size():
		return generated_name(_used_count + 1)
	return _names[_used_count]


const _ROOTS_A := ["Kes", "Vor", "Ash", "Tal", "Myr", "Or", "Sel", "Bren", "Cal", "Iv", "Nox", "Teth",
	"Quar", "Hal", "Dun", "Pyr", "Zar", "Mor", "Eld", "Ruk", "Sab", "Ven", "Thal", "Cor"]
const _ROOTS_B := ["ra", "en", "is", "ath", "ora", "une", "ek", "ion", "ari", "os", "eth", "ain", "ux", "ide"]
const _SUFFIXES := ["", "", "", " Reach", " Drift", " Hollow", " Verge", " Deep", " Crossing", " Expanse", " Shoal", " Rise"]


## A stable, real-sounding name for the nth system once the list runs out
## (the old "Uncharted System 28" placeholder showed in play, Abe 2026-09-28).
static func generated_name(n: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("campaign_system_name|%d" % n)
	var root: String = _ROOTS_A[rng.randi() % _ROOTS_A.size()] + _ROOTS_B[rng.randi() % _ROOTS_B.size()]
	return root + _SUFFIXES[rng.randi() % _SUFFIXES.size()]


func remaining() -> int:
	return max(0, _names.size() - _used_count)


func set_names(names: Array[String]) -> void:
	_names = names
	_used_count = 0
	_save()


static func reset() -> void:
	if FileAccess.file_exists(NAMES_PATH):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(NAMES_PATH)
		)


func _save() -> void:
	var file := FileAccess.open(NAMES_PATH, FileAccess.WRITE)
	if file:
		var data := {
			"names": _names,
			"used_count": _used_count,
		}
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
