extends RefCounted

## N.O.V.A. remarks on about half the jobs you take (Abe, playtest 2026-10-05
## finding 7): the pay against the risk, the thing you're carrying, where it's
## going, who's paying. She notices what you're doing.
##
## The line is made when the CARD is made, from authored templates filled with
## that card's own details, and rides on it (`nova_remark`) into the accepted
## mission: no model call, nothing to wait for. MissionRemarkRunner says it
## halfway to the mission's place, never at the station.
##
## Hunt contracts keep their own reaction (Nova.prepare_mission_hunt_reaction).

const CHANCE := 0.5
## Pay against what you've been taking lately (needs a few jobs to judge).
const PAY_LOW := 0.6
const PAY_HIGH := 1.7
const PAY_HISTORY := 6
const PAY_MIN_SAMPLES := 3
const HUNT_TYPES := ["KILL_SHIPS", "RECOVER_COMBAT_DROP", "TARGET_WITH_COMMS_REVERSAL"]

## Lines: pay_low and pay_high approved by Abe 2026-10-05; the rest are
## drafts awaiting review. {pay} {item} {amount} {dest}
## {client}: a line is only used when the card has every detail it names.
const LINES := {
	"pay_low": [
		"{pay} credits for this. I ran the numbers, Captain. The numbers laughed at me.",
		"For {pay} credits I hope {client} at least says thank you. Out loud. Twice.",
		"Our hull plating costs more per square metre than this whole job.",
		"{pay} credits. Somewhere a pirate is being paid better to shoot at us.",
	],
	"pay_high": [
		"{pay} credits? Nobody pays that well unless something is wrong. Please tell me you read the small print?",
		"That's generous of {client}. Generous makes me nervous.",
		"Good money. I'll be watching the sensors twice as hard, though.",
	],
	"pickup": [
		"The {item}, and we're not to look inside. My favourite kind of job, said nobody.",
		"If the {item} starts beeping, Captain, I'm venting it. I want that on record.",
		"I've been thinking about the {item}. Mostly about why it needed us and not the post.",
	],
	"courier": [
		"{item} for {dest}. I checked the manifest. It's very confident about what's in there.",
		"Delivery to {dest}. Honest work. Mostly. Sometimes.",
		"I've done the maths on the {item}: it's worth more to someone than the job pays us.",
		"The {item} has been very quiet back there. I like cargo that's quiet.",
	],
	"purchase": [
		"We're the shopping run now. Nobody gave us a list for snacks.",
		"Buying {item} for someone else. I'd like a receipt, a thank-you, and a cut.",
		"Shopping for {dest}. I hope they're paying for the fuel as well.",
		"Somebody at {dest} is about to be very glad to see us. Or the {item}. Mostly the {item}.",
	],
	"ore": [
		"{amount} cubic metres of ore. You do know I can see you smiling at the rocks?",
		"Ore run. Keep the drill steady and I'll keep the complaints to myself. Most of them.",
	],
	"investigate": [
		"A signal nobody else wanted to check. Nobody, Captain. Think about that.",
		"Investigating strange signals. In my experience they investigate back.",
	],
	"halfway": [
		"Halfway there. Still no explosions. I'm almost disappointed.",
		"Halfway. For the record, I'd have taken the other job.",
		"We're halfway, Captain. This is the part where I pretend I'm not counting.",
	],
}

## The pay of the last few jobs you accepted (this session).
static var _recent_pay: Array = []
## Per pool, the lines not yet used this round: every line is used once
## before any repeats ("different so it's not the same thing said all the
## time", Abe).
static var _bags: Dictionary = {}


## Gives `card` its remark (or decides it has none). Safe to call again: the
## roll is made once per card.
static func attach(card: Dictionary) -> Dictionary:
	if card.has("nova_remark_rolled"):
		return card
	card["nova_remark_rolled"] = true
	var kind := _type(card)
	if kind in HUNT_TYPES or kind.is_empty():
		return card
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if rng.randf() >= CHANCE:
		return card
	var line := _make(card, kind, rng)
	if not line.is_empty():
		card["nova_remark"] = line
	return card


## A job was accepted: remember its pay, for judging the next cards.
static func note_accepted(quest: Dictionary) -> void:
	var pay := _pay(quest)
	if pay <= 0.0:
		return
	_recent_pay.append(pay)
	while _recent_pay.size() > PAY_HISTORY:
		_recent_pay.pop_front()


static func _make(card: Dictionary, kind: String, rng: RandomNumberGenerator) -> String:
	var details := _details(card)
	var order: Array[String] = []
	# Pay first, when it stands out: her favourite subject.
	var pay := _pay(card)
	if _recent_pay.size() >= PAY_MIN_SAMPLES and pay > 0.0:
		var avg := 0.0
		for p in _recent_pay:
			avg += float(p)
		avg /= float(_recent_pay.size())
		if pay < avg * PAY_LOW:
			order.append("pay_low")
		elif pay > avg * PAY_HIGH:
			order.append("pay_high")
	match kind:
		"PICKUP_SPECIAL": order.append("pickup")
		"DELIVERY_COURIER": order.append("courier")
		"PURCHASE_DELIVERY": order.append("purchase")
		"DELIVER_ORE": order.append("ore")
		"INVESTIGATE_SIGNAL": order.append("investigate")
	# Now and then she just notes the halfway mark instead.
	if order.is_empty() or rng.randf() < 0.2:
		order.append("halfway")
	for pool_name in order:
		var line := _draw(pool_name, details)
		if not line.is_empty():
			return line
	return ""


## The next unused line of `pool_name` this card can fill.
static func _draw(pool_name: String, details: Dictionary) -> String:
	var pool: Array = LINES[pool_name]
	var bag: Array = _bags.get(pool_name, [])
	# Twice at most: what's left in the bag, then (if none of that fits this
	# card, e.g. it wants a client the board doesn't name) a fresh bag.
	for attempt in 2:
		if bag.is_empty() or attempt == 1:
			bag = range(pool.size())
			bag.shuffle()
		for i in range(bag.size()):
			var filled := _fill(str(pool[bag[i]]), details)
			if not filled.is_empty():
				bag.remove_at(i)
				_bags[pool_name] = bag
				return filled
	_bags[pool_name] = bag
	return ""


## Fills a template; "" if the card lacks a detail it names.
static func _fill(template: String, details: Dictionary) -> String:
	var out := template
	for key in ["pay", "item", "amount", "dest", "client"]:
		var tag := "{%s}" % key
		if not out.contains(tag):
			continue
		var value := str(details.get(key, "")).strip_edges()
		if value.is_empty():
			return ""
		out = out.replace(tag, value)
	return out


static func _details(card: Dictionary) -> Dictionary:
	var d := {}
	var pay := _pay(card)
	if pay > 0.0:
		d["pay"] = _thousands(int(round(pay)))
	for key in ["part_name", "item_name"]:
		var item := _text(card, key)
		if not item.is_empty():
			d["item"] = item
			break
	var amount := ""
	for key in ["quantity", "quantity_required", "amount_required"]:
		amount = _text(card, key)
		if not amount.is_empty():
			break
	if not amount.is_empty() and float(amount) > 0.0:
		d["amount"] = str(int(round(float(amount))))
	for key in ["destination_display", "destination_station_display"]:
		var dest := _text(card, key)
		if not dest.is_empty():
			d["dest"] = _title_case(dest)
			break
	var client := str(card.get("agent_name", "")).strip_edges()
	if not client.is_empty() and client != "Public Board":
		d["client"] = preload("res://scripts/domain/QuestNextStep.gd").person_name(client)
	return d


static func _type(card: Dictionary) -> String:
	var t := str(card.get("objective_type", ""))
	if t.is_empty():
		var objective = card.get("objective", {})
		if objective is Dictionary:
			t = str(objective.get("type", objective.get("objective_type", "")))
	return t


## A card keeps its details either flat (an accepted mission) or under
## "objective" (a card on offer).
static func _field(card: Dictionary, key: String):
	if card.has(key):
		return card[key]
	var objective = card.get("objective", {})
	if objective is Dictionary and objective.has(key):
		return objective[key]
	return null


## A detail as text, "" when the card doesn't have it (str(null) is "<null>").
static func _text(card: Dictionary, key: String) -> String:
	var v = _field(card, key)
	return "" if v == null else str(v).strip_edges()


## "MYRION WATCH" -> "Myrion Watch": station names are stored in capitals.
static func _title_case(s: String) -> String:
	if s != s.to_upper():
		return s
	var words: Array = []
	for w in s.to_lower().split(" ", false):
		words.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(words)


static func _pay(card: Dictionary) -> float:
	var pay = _field(card, "reward_credits")
	return float(pay) if pay != null else 0.0


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
