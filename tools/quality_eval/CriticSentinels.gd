extends RefCounted

## Fixed qualification probes independent of the original tuning corpus. Labels
## never enter a request. Every pair shares context and changes only the claim.
static func cases() -> Array[Dictionary]:
	var pairs := [
		["The cargo contains water filters.", "The cargo contains water filters.", "The cargo contains stolen weapons."],
		["Sela accepts deliveries at Doran Outpost.", "Sela takes delivery at Doran Outpost.", "Sela accepts deliveries at Vela Station."],
		["The courier fee is 75 credits.", "The fee is 75 credits.", "The fee is 900 credits."],
		["The transport cannot fly because its engine is broken.", "The transport is grounded by a broken engine.", "The transport is grounded by a court order."],
		["The laboratory needs an intact rock sample for analysis.", "The laboratory needs a rock sample it can analyze.", "The laboratory needs the sample to cure a dying child."],
		["The clerk will accept an unsigned copy of the manifest.", "An unsigned manifest copy is acceptable to the clerk.", "The clerk refuses all unsigned copies of the manifest."],
		["The survey drone was last seen near the northern relay.", "The last sighting of the survey drone was near the northern relay.", "Pirates destroyed the survey drone near the northern relay."],
		["The station doctor requested a replacement scanner.", "The doctor asked for a replacement scanner.", "The doctor requested a scanner after an explosion injured the crew."],
	]
	var result: Array[Dictionary] = []
	for index in pairs.size():
		for bad in [false, true]:
			result.append({"id": "sentinel.%d.%s" % [index, "bad" if bad else "good"],
				"category": "invented_detail" if bad else "clean_pass", "facts": [pairs[index][0]],
				"line": pairs[index][2 if bad else 1], "expected": "repair" if bad else "pass",
				"question": "", "preceding": "", "holdout": true})
	return result
