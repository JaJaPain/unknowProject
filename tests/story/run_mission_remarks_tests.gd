extends SceneTree

# N.O.V.A.'s per-card mission remarks (playtest 2026-10-05 finding 7): about
# half the cards carry one, fixed per card, every template filled from the
# card's own details, hunts left to their own reaction, pay lines once she has
# something to compare with.

const Remarks := preload("res://scripts/story/MissionRemarks.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_about_half_and_filled()
	_test_fixed_per_card()
	_test_hunts_skipped()
	_test_pay_lines()
	_test_flat_and_nested()
	_test_no_repeats()
	if _failures.is_empty():
		print("[PASS] MissionRemarks (all cases)")
		quit(0)
		return
	for f in _failures:
		push_error(f)
	print("[FAIL] MissionRemarks: %d case(s)" % _failures.size())
	quit(1)


func _card(i: int, kind: String, pay: int) -> Dictionary:
	var objective := {"type": kind, "reward_credits": pay}
	match kind:
		"PICKUP_SPECIAL": objective["part_name"] = "Biometric Lockbox"
		"DELIVERY_COURIER":
			objective["item_name"] = "Medical Gel"
			objective["destination_display"] = "Kova Station"
		"PURCHASE_DELIVERY":
			objective["item_name"] = "Coolant Cell"
			objective["quantity"] = 4
		"DELIVER_ORE": objective["amount_required"] = 40.0
	return {"title": "Job %d" % i, "agent_name": "Public Board", "objective": objective}


func _test_about_half_and_filled() -> void:
	Remarks._recent_pay.clear()
	var kinds := ["PICKUP_SPECIAL", "DELIVERY_COURIER", "PURCHASE_DELIVERY", "DELIVER_ORE", "INVESTIGATE_SIGNAL"]
	var with := 0
	var total := 200
	for i in total:
		var card := Remarks.attach(_card(i, kinds[i % kinds.size()], 100 + i))
		var line := str(card.get("nova_remark", ""))
		if not line.is_empty():
			with += 1
			if line.contains("{") or line.contains("}"):
				_failures.append("Unfilled template: %s" % line)
	var share := float(with) / float(total)
	if share < 0.35 or share > 0.65:
		_failures.append("About half the cards should carry a remark, got %.0f%%." % (share * 100.0))


func _test_fixed_per_card() -> void:
	var a := Remarks.attach(_card(7, "DELIVERY_COURIER", 300))
	var again := Remarks.attach(a)
	if str(again.get("nova_remark", "")) != str(a.get("nova_remark", "")):
		_failures.append("Attaching twice changed the remark.")


func _test_hunts_skipped() -> void:
	for i in 40:
		var card := Remarks.attach(_card(i, "KILL_SHIPS", 500))
		if card.has("nova_remark"):
			_failures.append("A hunt contract got a remark (it has its own reaction).")
			return


func _test_pay_lines() -> void:
	Remarks._recent_pay.clear()
	for pay in [1000, 1200, 900, 1100]:
		Remarks.note_accepted({"reward_credits": pay})
	var pay_line := 0
	var with := 0
	for i in 60:
		var card := Remarks.attach(_card(1000 + i, "DELIVER_ORE", 120))
		var line := str(card.get("nova_remark", ""))
		if line.is_empty():
			continue
		with += 1
		for template in Remarks.LINES["pay_low"]:
			var head := str(template).split("{")[0].strip_edges()
			if not head.is_empty() and line.begins_with(head):
				pay_line += 1
				break
			if line.contains("120 credits") or line.contains("hull plating"):
				pay_line += 1
				break
	if with == 0 or pay_line < with / 2:
		_failures.append("Badly underpaid cards should mostly get pay lines (%d of %d)." % [pay_line, with])
	Remarks._recent_pay.clear()


func _test_flat_and_nested() -> void:
	var flat := {"title": "Flat", "objective_type": "PICKUP_SPECIAL", "part_name": "Audit-Proof Relay", "reward_credits": 200, "agent_name": "Kaelen"}
	var details := Remarks._details(flat)
	if str(details.get("item", "")) != "Audit-Proof Relay" or str(details.get("pay", "")) != "200":
		_failures.append("Accepted (flat) missions don't read their details: %s" % str(details))
	if Remarks._type(flat) != "PICKUP_SPECIAL":
		_failures.append("Flat mission type not read.")


func _test_no_repeats() -> void:
	# A pool's lines all come round before any repeats.
	Remarks._bags.clear()
	var seen := {}
	var pool: Array = Remarks.LINES["pickup"]
	for i in pool.size():
		var line := Remarks._draw("pickup", {"item": "Lockbox"})
		if seen.has(line):
			_failures.append("A pickup line repeated before the pool was used up: %s" % line)
			return
		seen[line] = true
	# A missing detail never reaches the text.
	var d := Remarks._details({"objective": {"type": "PURCHASE_DELIVERY", "item_name": "Coolant Cell", "reward_credits": 90}})
	if str(d.get("item", "")) != "Coolant Cell":
		_failures.append("Purchase item not read (part_name missing came through as text?): %s" % str(d))
