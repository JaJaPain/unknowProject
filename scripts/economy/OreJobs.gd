extends RefCounted

## Ore jobs name their ore, chosen in code (Abe, playtest 2026-10-08
## finding 5): the model writes "ore" and code puts in the type, picked from
## what this system's belts carry. Rarely, a hard job in a deeper system asks
## for an ore the local belts lack and names the nearby system that has it
## (about 1 in HARD_ONE_IN, from depth HARD_MIN_DEPTH, paying HARD_PAY_MULT).

const OreTypesScript := preload("res://scripts/economy/OreTypes.gd")
const HARD_ONE_IN := 6
const HARD_MIN_DEPTH := 3
const HARD_PAY_MULT := 2.0
## Keys never rewritten (ids, names, voices).
const _SKIP_KEY_PARTS := ["id", "faction", "agent_name", "voice", "portrait", "npc", "type", "key", "system", "station"]


## An ore from `mix` (type -> share), weighted by share, the same for the same
## `seed_key`. Water ice only when `allow_ice` (ice and fuel jobs).
static func pick_local(mix: Dictionary, seed_key: String, allow_ice: bool = false) -> String:
	var pool := {}
	var total := 0.0
	for id in mix:
		var ore := OreTypesScript.normalize(str(id))
		if ore == "water_ice" and not allow_ice:
			continue
		var share := float(mix[id])
		if share <= 0.0:
			continue
		pool[ore] = float(pool.get(ore, 0.0)) + share
		total += share
	if total <= 0.0:
		return OreTypesScript.DEFAULT
	var roll := _unit(seed_key) * total
	var keys := pool.keys()
	keys.sort()
	for ore in keys:
		roll -= float(pool[ore])
		if roll < 0.0:
			return str(ore)
	return str(keys[-1])


## Whether this job is one of the rare hard ones.
static func is_hard(seed_key: String, depth: int) -> bool:
	return depth >= HARD_MIN_DEPTH and _unit("hard:" + seed_key) < 1.0 / float(HARD_ONE_IN)


## A number in [0, 1) that's the same for the same key and well spread for
## similar keys (a string's hash alone barely changes between "job 1" and
## "job 2").
static func _unit(key: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	return rng.randf()


## The rarest ore from `wanted_order` that `local` lacks (share under 3%), or "".
static func missing_rare(local: Dictionary, wanted_order: Array = ["thorium", "cuprite", "ferrite"]) -> String:
	for ore in wanted_order:
		if float(local.get(ore, 0.0)) < 0.03:
			return str(ore)
	return ""


## `text` with the ore words made `ore` ("bring ore" -> "bring ferrite";
## "Silicate Run" -> "Ferrite Run"; "silicate ore" -> "ferrite ore").
static func rewrite(text: String, ore: String) -> String:
	var name := OreTypesScript.display(ore)
	var out := text
	for other in OreTypesScript.TYPES:
		if str(other) == ore:
			continue
		var other_name := OreTypesScript.display(str(other))
		out = _replace_word(out, other_name, name)
	# A bare "ore", unless it follows the type's own name ("ferrite ore").
	var lower_name := name.to_lower()
	var result := ""
	var i := 0
	while i < out.length():
		var hit := out.substr(i, 3)
		var word_start := i == 0 or not _is_letter(out[i - 1])
		var word_end := i + 3 >= out.length() or not _is_letter(out[i + 3])
		if hit.to_lower() == "ore" and word_start and word_end:
			var before := out.substr(0, i).strip_edges(false, true).to_lower()
			if before.ends_with(lower_name):
				result += hit
			elif hit == "ORE":
				result += name.to_upper()
			elif hit[0] == "O":
				result += name
			else:
				result += lower_name
			i += 3
			continue
		result += out[i]
		i += 1
	return result


## Every text field of a job rewritten for `ore` (ids, names and voices left alone).
static func rewrite_job(value, ore: String, key: String = ""):
	if value is String:
		return rewrite(value, ore) if not _skip(key) else value
	if value is Dictionary:
		var d := {}
		for k in value:
			d[k] = rewrite_job(value[k], ore, str(k))
		return d
	if value is Array:
		return (value as Array).map(func(v): return rewrite_job(v, ore, key))
	return value


static func _skip(key: String) -> bool:
	var k := key.to_lower()
	for part in _SKIP_KEY_PARTS:
		if k.contains(part):
			return true
	return false


static func _replace_word(text: String, word: String, with: String) -> String:
	var out := ""
	var lower := text.to_lower()
	var target := word.to_lower()
	var i := 0
	while i < text.length():
		if lower.substr(i, target.length()) == target \
				and (i == 0 or not _is_letter(text[i - 1])) \
				and (i + target.length() >= text.length() or not _is_letter(text[i + target.length()])):
			var src := text.substr(i, target.length())
			out += with.to_upper() if src == src.to_upper() and src != src.to_lower() else (with if src[0] == src[0].to_upper() else with.to_lower())
			i += target.length()
			continue
		out += text[i]
		i += 1
	return out


static func _is_letter(c: String) -> bool:
	var l := c.to_lower()
	return l >= "a" and l <= "z"


# --- Runtime ------------------------------------------------------------------

## Gives a DELIVER_ORE job its ore (in code), rewrites its text and, for a
## rare hard job, sends it to a nearby system. Other jobs come back unchanged.
## `seed_key`: something stable for this job (its title and agent).
static func assign(quest: Dictionary, seed_key: String = "") -> Dictionary:
	var objective: Dictionary = quest.get("objective", {}) if quest.get("objective", {}) is Dictionary else {}
	if str(objective.get("type", quest.get("objective_type", ""))) != "DELIVER_ORE":
		return quest
	var given := str(objective.get("ore_type", "")).strip_edges().to_lower()
	if given == "fuel" or given == "water_ice":
		return quest
	var gs := _global_state()
	# No running game (tests, the season sim): left as it is.
	if gs == null:
		return quest
	var local: Dictionary = gs.get("system_ore_mix") if gs.get("system_ore_mix") is Dictionary else {"silicate": 1.0}
	if seed_key.is_empty():
		seed_key = "%s|%s|%s" % [str(quest.get("title", "")), str(quest.get("agent_name", "")), str(gs.get("current_system_id"))]
	var out := quest.duplicate(true)
	var obj: Dictionary = out["objective"]
	var ore := ""
	var source: Dictionary = {}
	# A card's own ore stays if the belts here carry it.
	if not given.is_empty() and OreTypesScript.is_known(given) and float(local.get(given, 0.0)) >= 0.03:
		ore = given
	var depth := _depth_here()
	var wants_far := (not given.is_empty() and OreTypesScript.is_known(given) and ore.is_empty()) or is_hard(seed_key, depth)
	if ore.is_empty() and wants_far:
		var far := given if not given.is_empty() and OreTypesScript.is_known(given) else missing_rare(local)
		if not far.is_empty():
			source = _nearby_system_with(far)
			if not source.is_empty():
				ore = far
	if ore.is_empty():
		ore = pick_local(local, seed_key)
	obj["ore_type"] = ore
	out = rewrite_job(out, ore)
	obj = out["objective"]
	obj["ore_type"] = ore
	if not source.is_empty():
		obj["ore_source_system_id"] = str(source["id"])
		obj["ore_source_system_display"] = str(source["display"])
		obj["reward_credits"] = int(round(float(obj.get("reward_credits", 0)) * HARD_PAY_MULT))
		var where := " The belts here don't carry %s: mine it in %s." % [OreTypesScript.display(ore).to_lower(), str(source["display"])]
		out["dialogue"] = str(out.get("dialogue", "")) + where
		if out.has("text"):
			out["text"] = str(out["text"]) + where
	out["objective"] = obj
	return out


static func _global_state() -> Node:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root.get_node_or_null("GlobalState") if loop is SceneTree else null


static func _depth_here() -> int:
	var gs := _global_state()
	if gs == null:
		return 0
	return int(preload("res://scripts/story/premise/PremiseWorldSnapshot.gd")._system_depth(str(gs.get("current_system_id"))))


## A system one gate away whose belts carry `ore`: {id, display}, or {}.
static func _nearby_system_with(ore: String) -> Dictionary:
	var gs := _global_state()
	var loop := Engine.get_main_loop()
	var scene = (loop as SceneTree).current_scene if loop is SceneTree else null
	var registry = scene.get("system_registry") if scene != null else null
	if gs == null or registry == null or not registry.has_method("get_system"):
		return {}
	var here_def = registry.get_system(gs.get("current_system_id"))
	if here_def == null:
		return {}
	var Profile := preload("res://scripts/story/premise/SystemProfile.gd")
	var Snapshot := preload("res://scripts/story/premise/PremiseWorldSnapshot.gd")
	for gate in here_def.gates:
		var dest := str(registry.resolve_system_id(gate.destination_system_id))
		var config = registry.get_generated_config(dest) if registry.has_method("get_generated_config") else null
		if config == null:
			continue
		var mix: Dictionary = Profile.generate(dest, int(config.seed_value), str(config.star_type), false, Snapshot._system_depth(dest)).get("ores", {})
		if float(mix.get(ore, 0.0)) >= 0.03:
			return {"id": dest, "display": str(config.system_name)}
	return {}
