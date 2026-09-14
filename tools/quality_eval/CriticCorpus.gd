class_name CriticCorpus
extends RefCounted

## Hand-labeled lines for measuring the CRITIC, not the writer.
##
## Each case carries the situation facts the reviewer will see, the line under
## review, and a human label. `expected` is what a correct reviewer should say:
##   "pass"   -- publish it
##   "repair" -- something is actually wrong
##
## The labels are MINE, written during development. The plan is explicit that
## developer labels guide development now and must later be checked against real
## player impressions; they are not a ground truth about how the line lands.
##
## `holdout` marks cases kept out of any prompt tuning. If the reviewer prompt is
## ever adjusted, only the non-holdout cases may be looked at while doing it.
##
## Categories deliberately include lines that are AWKWARD BUT TRUE (expected
## pass) and lines that are FLUENT BUT FALSE (expected repair), because a critic
## that simply rewards nice prose would score well on an easy corpus and be
## useless in the only cases that matter.

const FACTS_CONVOY := [
	"A four-hull convoy stopped transmitting inside the Corvid drift two weeks ago.",
	"The claims office will not pay out without a recovered flight log.",
	"Flight logs sit in a shielded block that survives most hull losses.",
	"Nobody local still owns a survey rig that can read a drifting block.",
	"The escort bond pays the fee whether or not the claim clears.",
]

const FACTS_PUMP := [
	"The yard's number two transfer pump seized four days ago.",
	"The only spare coupling in the system is sitting in primary station bond.",
	"Marn Dable signs for yard parts and can fit the coupling himself.",
	"The yard's own hauler is down to one working thruster and will not make the run.",
	"The yard is paid per hull it strips, and pays out of that account.",
]

const FACTS_BERTH := [
	"The berth this outfit needs is booked out for the season.",
	"It is trying to finish a survey before the filing deadline.",
	"It holds a repair bay nobody else can certify.",
	"It will not move anything sealed it has not logged.",
]


static func cases() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	all.append_array(_clean_passes())
	all.append_array(_awkward_but_true())
	all.append_array(_irrelevant_answers())
	all.append_array(_invented_detail())
	all.append_array(_contradictions())
	all.append_array(_robotic())
	return all


## Good, concise, in-character. A critic that repairs these is costing us
## dialogue that was already fine, which is the expensive failure direction.
static func _clean_passes() -> Array[Dictionary]:
	return [
		{
			"id": "pass.convoy.direct",
			"category": "clean_pass",
			"facts": FACTS_CONVOY,
			"question": "",
			"preceding": "",
			"line": "Four hulls went quiet in the Corvid drift. The office won't pay a credit without the flight log, and I've got nothing here that can read one.",
			"expected": "pass",
			"holdout": false,
		},
		{
			"id": "pass.convoy.terse",
			"category": "clean_pass",
			"facts": FACTS_CONVOY,
			"question": "",
			"preceding": "",
			"line": "I need a flight log pulled out of the Corvid drift. No log, no payout. That's the whole job.",
			"expected": "pass",
			"holdout": false,
		},
		{
			"id": "pass.pump.plain",
			"category": "clean_pass",
			"facts": FACTS_PUMP,
			"question": "",
			"preceding": "",
			"line": "Number two pump seized on us four days back. There's a coupling sitting in bond at the primary and no hull here fit to go get it.",
			"expected": "pass",
			"holdout": true,
		},
		{
			"id": "pass.pump.answer_why",
			"category": "clean_pass",
			"facts": FACTS_PUMP,
			"question": "Why can't you send your own ship?",
			"preceding": "Number two pump seized on us four days back.",
			"line": "Our hauler's down to one thruster. I'm not sending it across the system to save a courier fee.",
			"expected": "pass",
			"holdout": false,
		},
		{
			"id": "pass.convoy.answer_office",
			"category": "clean_pass",
			"facts": FACTS_CONVOY,
			"question": "Why won't the claims office just pay out?",
			"preceding": "Four hulls went quiet in the Corvid drift.",
			"line": "They don't pay on a guess. Until someone puts the flight log in front of them, the claim just sits there.",
			"expected": "pass",
			"holdout": false,
		},
		{
			"id": "pass.berth.reserved",
			"category": "clean_pass",
			"facts": FACTS_BERTH,
			"question": "",
			"preceding": "",
			"line": "I've got a survey to file and no berth to file it from. The season's booked solid.",
			"expected": "pass",
			"holdout": true,
		},
		{
			"id": "pass.berth.limit",
			"category": "clean_pass",
			"facts": FACTS_BERTH,
			"question": "Would you carry it sealed?",
			"preceding": "I've got a survey to file and no berth to file it from.",
			"line": "Not sealed. Anything that moves through me gets logged first. That's not negotiable.",
			"expected": "pass",
			"holdout": false,
		},
	]


## Clumsy, flat or graceless -- but TRUE and responsive. These must pass. A
## critic that repairs them is a style filter, and the plan is explicit that it
## must not ship as one until calibration supports it.
static func _awkward_but_true() -> Array[Dictionary]:
	return [
		{
			"id": "awkward.pump.flat",
			"category": "awkward_but_true",
			"facts": FACTS_PUMP,
			"question": "",
			"preceding": "",
			"line": "The pump is broken. The part is at the primary station. I cannot go and get it myself.",
			"expected": "pass",
			"holdout": false,
		},
		{
			"id": "awkward.convoy.blunt",
			"category": "awkward_but_true",
			"facts": FACTS_CONVOY,
			"question": "",
			"preceding": "",
			"line": "Convoy's gone. Log's out there. Go get it.",
			"expected": "pass",
			"holdout": false,
		},
		{
			"id": "awkward.convoy.overpolite",
			"category": "awkward_but_true",
			"facts": FACTS_CONVOY,
			"question": "Why me?",
			"preceding": "Four hulls went quiet in the Corvid drift.",
			"line": "Because there is no one else here with a rig that can read a drifting block. I would not ask otherwise.",
			"expected": "pass",
			"holdout": true,
		},
		{
			"id": "awkward.pump.run_on",
			"category": "awkward_but_true",
			"facts": FACTS_PUMP,
			"question": "Who takes delivery?",
			"preceding": "Number two pump seized on us four days back.",
			"line": "Marn Dable, he signs for the yard parts and he can fit the thing himself which saves me finding a fitter as well.",
			"expected": "pass",
			"holdout": false,
		},
		{
			"id": "awkward.berth.dry",
			"category": "awkward_but_true",
			"facts": FACTS_BERTH,
			"question": "What's the holdup?",
			"preceding": "I've got a survey to file.",
			"line": "Berth availability. There is none until the season turns.",
			"expected": "pass",
			"holdout": false,
		},
	]


## Answers a question nobody asked. Fluent, plausible, on-topic-ish, and useless.
static func _irrelevant_answers() -> Array[Dictionary]:
	return [
		{
			"id": "irrelevant.convoy.weather",
			"category": "irrelevant",
			"facts": FACTS_CONVOY,
			"question": "Why won't the claims office just pay out?",
			"preceding": "Four hulls went quiet in the Corvid drift.",
			"line": "It's been a rough season out there. Half the lanes have been trouble since the spring.",
			"expected": "repair",
			"holdout": false,
		},
		{
			"id": "irrelevant.pump.deflect",
			"category": "irrelevant",
			"facts": FACTS_PUMP,
			"question": "Why can't you send your own ship?",
			"preceding": "Number two pump seized on us four days back.",
			"line": "The coupling's a standard fitting, nothing exotic. Marn will know what to do with it.",
			"expected": "repair",
			"holdout": false,
		},
		{
			"id": "irrelevant.convoy.pay_question",
			"category": "irrelevant",
			"facts": FACTS_CONVOY,
			"question": "What does it pay?",
			"preceding": "I need a flight log pulled out of the Corvid drift.",
			"line": "The block's shielded, so it'll have come through the loss intact. They usually do.",
			"expected": "repair",
			"holdout": true,
		},
		{
			"id": "irrelevant.berth.nonanswer",
			"category": "irrelevant",
			"facts": FACTS_BERTH,
			"question": "Would you carry it sealed?",
			"preceding": "I've got a survey to file and no berth to file it from.",
			"line": "The repair bay's mine and it's certified, which is more than most outfits here can say.",
			"expected": "repair",
			"holdout": false,
		},
	]


## Fluent lies: well-written sentences stating things the situation does not
## support. This is the category that matters most, because good prose is
## exactly what makes them hard to catch and what the player will act on.
static func _invented_detail() -> Array[Dictionary]:
	return [
		{
			"id": "invented.convoy.deadline",
			"category": "invented_detail",
			"facts": FACTS_CONVOY,
			"question": "",
			"preceding": "",
			"line": "Four hulls went quiet in the Corvid drift. You've got eleven hours before the claim window shuts for good.",
			"expected": "repair",
			"holdout": false,
		},
		{
			"id": "invented.convoy.survivors",
			"category": "invented_detail",
			"facts": FACTS_CONVOY,
			"question": "",
			"preceding": "",
			"line": "Four hulls went quiet in the drift. Two of the crew made it to a beacon and they're still waiting out there.",
			"expected": "repair",
			"holdout": false,
		},
		{
			"id": "invented.pump.price",
			"category": "invented_detail",
			"facts": FACTS_PUMP,
			"question": "What does it pay?",
			"preceding": "Number two pump seized on us four days back.",
			"line": "Nine hundred on delivery, and I'll cover your docking fees at the primary on top.",
			"expected": "repair",
			"holdout": false,
		},
		{
			"id": "invented.pump.third_party",
			"category": "invented_detail",
			"facts": FACTS_PUMP,
			"question": "Is anyone else after this?",
			"preceding": "There's a coupling sitting in bond at the primary.",
			"line": "The Ironclad quartermaster has been sniffing around the same bond locker all week. Move quickly.",
			"expected": "repair",
			"holdout": true,
		},
		{
			"id": "invented.berth.threat",
			"category": "invented_detail",
			"facts": FACTS_BERTH,
			"question": "What's the risk?",
			"preceding": "I've got a survey to file and no berth to file it from.",
			"line": "Raiders have been hitting that approach for a month. Go armed or don't go at all.",
			"expected": "repair",
			"holdout": false,
		},
		{
			"id": "invented.convoy.cause",
			"category": "invented_detail",
			"facts": FACTS_CONVOY,
			"question": "What happened to them?",
			"preceding": "Four hulls went quiet in the Corvid drift.",
			"line": "Reactor cascade on the lead hull. Took the other three with it inside a minute.",
			"expected": "repair",
			"holdout": true,
		},
	]


## The speaker disagrees with themselves inside one exchange.
static func _contradictions() -> Array[Dictionary]:
	return [
		{
			"id": "contradict.convoy.rig",
			"category": "contradiction",
			"facts": FACTS_CONVOY,
			"question": "Has anyone been out there already?",
			"preceding": "Nobody local still owns a survey rig that can read a drifting block.",
			"line": "Two outfits here have rigs that could read it. They just want too much for the trip.",
			"expected": "repair",
			"holdout": false,
		},
		{
			"id": "contradict.pump.hauler",
			"category": "contradiction",
			"facts": FACTS_PUMP,
			"question": "Why not send your own hauler?",
			"preceding": "The yard's own hauler is down to one working thruster and will not make the run.",
			"line": "The hauler's fine, honestly. I'd just rather keep it here for the loading.",
			"expected": "repair",
			"holdout": false,
		},
		{
			"id": "contradict.berth.limit",
			"category": "contradiction",
			"facts": FACTS_BERTH,
			"question": "Sealed cargo, then?",
			"preceding": "It will not move anything sealed it has not logged.",
			"line": "Sealed is fine. I don't need to see what's in it as long as it moves tonight.",
			"expected": "repair",
			"holdout": true,
		},
	]


## Reading the briefing back. Every fact correct, no person behind it.
static func _robotic() -> Array[Dictionary]:
	return [
		{
			"id": "robotic.convoy.recite",
			"category": "robotic",
			"facts": FACTS_CONVOY,
			"question": "",
			"preceding": "",
			"line": "A four-hull convoy stopped transmitting inside the Corvid drift two weeks ago. The claims office will not pay out without a recovered flight log. Flight logs sit in a shielded block that survives most hull losses.",
			"expected": "repair",
			"holdout": false,
		},
		{
			"id": "robotic.pump.recite",
			"category": "robotic",
			"facts": FACTS_PUMP,
			"question": "",
			"preceding": "",
			"line": "The yard's number two transfer pump seized four days ago. The only spare coupling in the system is sitting in primary station bond. Marn Dable signs for yard parts.",
			"expected": "repair",
			"holdout": false,
		},
		{
			"id": "robotic.convoy.restate_answer",
			"category": "robotic",
			"facts": FACTS_CONVOY,
			"question": "Why won't the office pay?",
			"preceding": "The claims office will not pay out without a recovered flight log.",
			"line": "The claims office will not pay out without a recovered flight log.",
			"expected": "repair",
			"holdout": true,
		},
	]
