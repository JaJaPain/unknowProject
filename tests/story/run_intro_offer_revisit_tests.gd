extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var story := root.get_node("StoryManager")
	var global := root.get_node("GlobalState")
	var quests := root.get_node("QuestManager")
	var saved_story: Dictionary = story.story_state.duplicate(true)
	var saved_seen: bool = global.kaelen_briefing_seen
	var saved_accepted: bool = global.kaelen_briefing_accepted
	# Run the actual board-routing method, replacing only presentation so this
	# regression needs neither a window, speech server nor generated mission.
	var script := GDScript.new()
	script.source_code = 'extends "res://scripts/UIManager.gd"\nvar intro_offers := 0\nfunc _show_kaelen_intro_quest_offer() -> void:\n\tintro_offers += 1\n'
	var compiled := script.reload()
	_expect(compiled == OK and script.can_instantiate(), "UI routing probe must compile")
	if compiled != OK or not script.can_instantiate():
		quit(1)
		return
	var ui: Node = script.new()
	quests.active_quest = {}
	story.story_state["first_contract_handed_in"] = false
	story.story_state["intro_agent_visited"] = true
	global.kaelen_briefing_seen = true
	for accepted in [false, true]:
		global.kaelen_briefing_accepted = accepted
		for delivered in [false, true]:
			story.story_state["intro_quest_delivered"] = delivered
			# Include a stale ordinary offer: it must not displace the tutorial.
			ui.cached_quest_data = {"title": "Later generated work"}
			var before: int = ui.intro_offers
			ui.call("_refresh_agent_quest_board")
			_expect(ui.intro_offers == before + 1, "Declining, revisiting, or old accepted flags must still offer the unfinished tutorial")
			_expect(not story.story_state["first_contract_handed_in"], "Reopening must not release completion gates")
	# An active tutorial must go to progress/hand-in, never a duplicate offer.
	quests.active_quest = {"runtime_id": "mission.test.intro", "title": "Clean and Easy", "is_intro_tutorial": true, "objective_type": "KILL_SHIPS"}
	_expect(not ui.call("_should_offer_starter_contract"), "An active tutorial must not be offered twice")
	quests.active_quest = {}
	_expect(ui.call("_should_offer_starter_contract"), "Abandonment must make the unfinished tutorial available again")
	# Save/load the exact flags left by the old bypass, without rewriting them.
	story.story_state = JSON.parse_string(JSON.stringify(story.story_state))
	_expect(ui.call("_should_offer_starter_contract"), "Reload must not turn acceptance/visit flags into completion")
	story.story_state["first_contract_handed_in"] = true
	_expect(not ui.call("_should_offer_starter_contract"), "Completed campaigns must proceed to normal work")
	var source := FileAccess.get_file_as_string("res://scripts/UIManager.gd")
	var return_start := source.find("func _show_kaelen_return_briefing")
	var offer_start := source.find("func _show_kaelen_intro_quest_offer")
	var return_code := source.substr(return_start, offer_start - return_start)
	_expect(not return_code.contains("kaelen_briefing_accepted = true"), "Agreeing to hear the offer must not mark its acceptance")
	var callback_start := source.find("take_btn.pressed.connect", offer_start)
	var accepted_flag := source.find("kaelen_briefing_accepted = true", callback_start)
	var accept_guard := source.find("if not QuestManager.accept_quest", callback_start)
	var failure_return := source.find("\n\t\t\treturn", accept_guard)
	_expect(accept_guard > callback_start and failure_return > accept_guard and failure_return < accepted_flag, "Failed acceptance must leave tutorial flags and offer intact")
	ui.free()
	story.story_state = saved_story
	global.kaelen_briefing_seen = saved_seen
	global.kaelen_briefing_accepted = saved_accepted
	if failures.is_empty():
		print("[PASS] Intro offer revisit: decline, stale cache, legacy flags, active contract, abandonment, reload, completion and failed acceptance")
	else:
		for failure in failures:
			push_error("[FAIL] " + failure)
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
