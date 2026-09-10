# Campaign Story Generation Consensus Brief

This is the current best recommendation after local Ollama testing with `gemma4:12b`.
The purpose of this file is to give another model a clean target to critique, not to preserve every experiment.
Raw runs, prompts, and outputs are saved in this folder.

## What The Game Needs

- The game must not enter the first playable scene without a real generated campaign story.
- The generated story must be more than rules. It needs a playable premise, an opening crisis, hidden pressure, faction tension, recurring clues, and Act 1 direction.
- The first campaign must fit the tutorial: broke independent pilot, Kaelen as broker/fixer, one starter Reaver or Reaver-like hostile ship, then station/agent flow.
- Kaelen must remain mysterious and immortal. Her public role should stay broker, fixer, and contract handler.
- The first system may only use known local factions: Zenith, Aurelia, and Vanguard.
- Future factions, ores, ships, systems, and deeper mysteries should be teased by role or pressure, not named up front.
- Every generated campaign needs room to be different. The prompt must not accidentally force every run into "ancient signal", "ghost signal", prophecy, alien owner, or cosmic pulse.
- The final output must be easy for code to validate and easy to convert into small-LLM context blocks.

## Test Findings

One giant flat schema failed.
Gemma usually produced malformed JSON, truncated content, or rules-only answers.

Ollama structured-output/schema mode failed for this use case.
It caused repetition, truncation, and weaker story content.

A compact JSON shape written directly in the prompt worked better.
It gave the model enough structure without triggering the worst schema-mode behavior.

The best results came from a two-pass process:

1. Pass 1 generates a compact uniqueness brief and open-ended story questions.
2. Pass 2 answers that brief into the final compact campaign story bible.

This reduced generic motifs and made the results feel more like playable campaigns.

## Best Current Example

Best normalized candidate:

`OllamaTestStories/20260701_211618_two_pass_final_check/two_pass_02_story.json`

Title: `Iron Scarcity`

Why it worked:

- The premise is practical and playable: resource scarcity, failing infrastructure, supply-chain sabotage.
- It supports normal gameplay loops: combat, delivery, salvage, mining pressure, rumors, gates, and contract work.
- Kaelen stays in the right role: broker/fixer with hidden interests.
- The starter mission is exactly one Reaver ship.
- The hidden crisis can be revealed gradually through manifests, cargo routes, prices, contracts, and faction pressure.

Weaknesses still to fix:

- Some phrasing was awkward.
- A few JSON keys mutated and needed normalization.
- Future questions were usable but still not strong enough.
- The pitch and summary were still a little thin.

Strong alternate candidate:

`OllamaTestStories/20260701_211332_two_pass_near_field_questions/two_pass_03_story.json`

Title: `Ironbound Reach`

Why it worked:

- It had a distinctive recurring clue: `Void-Stitched Cargo`.
- It framed the story around industrial scarcity instead of cosmic prophecy.
- It gave clear faction pressure and a usable Act 1 loop.

Weaknesses:

- Still had key mutation.
- A few story elements drifted toward familiar "hidden forge" flavor.
- Pitch/summary were still compact.

## Recommended Architecture

Use two LLM calls at campaign creation.

### Pass 1: Campaign Uniqueness Brief

The first call should not write the story bible.
It should create a short creative seed that prevents the second call from falling into the same motifs every time.

Suggested shape:

```json
{
  "creative_lane": "",
  "freshness_rule": "",
  "avoid_motifs": ["", "", "", ""],
  "core_story_questions": ["", "", "", "", ""],
  "starter_mission_questions": ["", "", ""],
  "kaelen_questions": ["", "", ""],
  "faction_questions": ["", "", ""],
  "future_generation_questions": ["", "", "", "", ""]
}
```

Question rules:

- Questions must begin with What, Why, How, Who, Where, or Which.
- Questions must leave room for different answers.
- Questions should ask about pressure, cost, contradiction, leverage, secrecy, consequence, routes, prices, risk, or player choice.
- Questions must not imply a fixed motif or final answer.

### Pass 2: Campaign Story Bible

The second call receives the uniqueness brief and writes the final story bible.
It should return only JSON.

Suggested shape:

```json
{
  "campaign_title": "",
  "campaign_subtitle": "",
  "campaign_logline": "",
  "campaign_pitch": "",
  "campaign_story_summary": "",
  "tone": "",
  "opening": {
    "status_quo": "",
    "visible_crisis": "",
    "hidden_crisis": "",
    "why_now": "",
    "player_role": ""
  },
  "mystery": {
    "question": "",
    "false_answer": "",
    "true_answer_hint": "",
    "long_term_reveal_direction": ""
  },
  "kaelen": {
    "public_role": "",
    "secret_angle": "",
    "address_rule": "",
    "never_reveal_rule": ""
  },
  "factions": {
    "zenith_problem": "",
    "aurelia_problem": "",
    "vanguard_problem": "",
    "conflict_triangle": "",
    "neutral_space_pressure": ""
  },
  "act_1": {
    "name": "",
    "goal": "",
    "opening_incident": "",
    "midpoint_turn": "",
    "finale": "",
    "player_takeaway": ""
  },
  "starter_mission": {
    "title": "",
    "reason": "",
    "enemy_identity": "",
    "enemy_knows": "",
    "after_effect": ""
  },
  "recurring_clue": {
    "name": "",
    "signal": "",
    "first_appearance": "",
    "escalation": "",
    "payoff_hint": ""
  },
  "rumor_trail": {
    "name": "",
    "trail_id": "rumor_trail.snake_case_id",
    "hint_theme": "",
    "clue_templates": ["", ""],
    "discovery_type": "hidden_discovery|secret_route|rare_upgrade|faction_secret|endgame_easter_egg",
    "rarity": "local|uncommon|rare|legendary",
    "payoff": ""
  },
  "horizon": {
    "gate_tease": "",
    "new_system_reveal_rule": "",
    "future_pressure_tease": "",
    "future_ore_or_upgrade_tease": "",
    "regeneration_trigger": {
      "id": "snake_case_id",
      "metric": "prepared_systems_remaining|active_story_arcs_remaining|rumor_trails_remaining|major_arc_state",
      "threshold": 0,
      "action": "append_story_horizon|append_rumor_trail|append_story_arc",
      "description": ""
    }
  },
  "rules": {
    "humor_rule": "",
    "fallback": "",
    "banned_repeats": []
  },
  "story_questions_for_future_generation": ["", "", "", "", ""]
}
```

## Prompt Direction

The prompts should say:

- Create a real playable story premise, not just rules.
- Use clean, direct English.
- Keep most fields short.
- Make `campaign_pitch` four short sentences: player situation, faction pressure, immediate job loop, hidden trouble.
- Make `campaign_story_summary` seven short sentences and include player role, Kaelen, starter Reaver incident, faction conflict, recurring clue, hidden crisis, and Act 1 direction.
- Do not include `thought`, notes, markdown, commentary, or extra keys.
- Copy every JSON key exactly.
- The first mission must be one hostile Reaver or Reaver-like ship.
- Do not write a swarm, fleet, squad, drone cloud, or multi-enemy starter encounter.
- Future questions must stay near playable campaign material: contracts, faction leverage, routes, gate access, Kaelen's deals, prices, risks, rumors, and player choices.

## Small-LLM Context Blocks

The final story bible should be stored raw, but the game should also derive small-LLM prompt blocks from it.
This keeps contract, chatter, rumor, and dialogue generation focused.

Suggested derived blocks:

- `public_campaign_summary`: safe facts NPCs can mention.
- `hidden_director_notes`: hidden crisis, true answer hint, Kaelen secret angle, long-term reveal direction.
- `kaelen_context`: what Kaelen publicly knows, what she may hint at, what she must not reveal.
- `current_act_context`: Act 1 goal, opening incident, midpoint turn, finale direction.
- `starter_mission_context`: title, reason, enemy identity, after-effect.
- `faction_pressure_context`: Zenith/Aurelia/Vanguard problems and conflict triangle.
- `clue_and_rumor_context`: recurring clue, rumor trail, clue templates, payoff hints.
- `do_not_reveal`: future factions, Kaelen truth, true culprit, final answers.
- `style_rules`: tone, humor rule, banned repeats, fallback phrase.

This can be a third deterministic code step instead of another LLM call.
If another LLM pass is used, it should only transform the bible into context blocks, not invent new story.

## Validation And Normalization

Validation should happen before the first scene loads.
No valid generated campaign story means no gameplay start.

Required validation:

- JSON parses cleanly.
- Required fields exist.
- Kaelen public role is broker/fixer/contract handler, not scientist/commander/prophet/mechanic.
- Player is not a chosen one.
- Starter mission is exactly one hostile Reaver or Reaver-like ship.
- No future faction names are revealed.
- `trail_id` and trigger IDs are snake_case-style.
- Enum fields match known values.
- Future questions are open-ended and do not force a motif.
- No placeholders, schema names, percent signs, or meta instructions in story fields.
- Banned repeats include `chosen one` and `destiny`.

Normalization should repair harmless key mutations before rejecting:

- `v_problem` -> `vanguard_problem`
- `aurelia_rule` -> `aurelia_problem`
- `opening_itement` -> `opening_incident`
- `true__hint` -> `true_answer_hint`
- `aftershock` / `aftershock_reason` -> `after_effect`
- `first__appearance` -> `first_appearance`
- `humor__rule` -> `humor_rule`
- `fallback_rule` / `fall_back_rule` -> `fallback`
- `hidden_route` -> `secret_route`
- `story_questions_for_future_thought_generation` -> `story_questions_for_future_generation`
- `future_generation_questions` -> `story_questions_for_future_generation`
- Trigger IDs with invalid punctuation should be converted to underscores.

Question for consensus:
Should normalization be accepted in production, or should any key mutation force a retry?
My current recommendation is: normalize harmless known mutations, then validate strictly.

## Retry Policy

Recommended loading flow:

1. Generate Pass 1 uniqueness brief.
2. Validate Pass 1.
3. If Pass 1 fails, retry Pass 1 once.
4. Generate Pass 2 final story bible.
5. Normalize known harmless mutations.
6. Validate Pass 2.
7. If Pass 2 fails, retry Pass 2 once using the same uniqueness brief plus validation errors.
8. If it still fails, stay on the loading screen and show the debug reason.
9. Do not fall back to a fake campaign bible.

This matches the design goal: at game start, waiting is acceptable; entering without a story is not.

## Open Questions For Claude

Please critique these directly:

1. Is two-pass generation enough, or should we add a third pass to derive small-LLM context blocks?
2. Should the final game store the nested schema as-is, flatten it into the current `CampaignBibleStore`, or store both?
3. Should future-generation questions be created in Pass 1, Pass 2, or both?
4. Should production normalize harmless key mutations, or retry whenever a key mutates?
5. How much of the hidden crisis should small LLMs see when generating normal contracts and chatter?
6. Should the starter mission content be generated by the bible, or should the code keep the mission fixed and only inject story flavor?
7. Are any fields missing for a procedural space game that must support mining, salvage, delivery, combat, rumors, station services, and gates?
8. Does the schema create enough variety, or does it still bias too hard toward resource scarcity and logistics?
9. Should `campaign_story_summary` be longer, or should rich prose be generated later from compact fields?
10. What should be the minimum acceptable quality bar before the game can start?

## Current Recommendation

Use two-pass generation for campaign creation.
Store both the pass-1 uniqueness brief and pass-2 story bible.
Normalize known harmless key mutations.
Validate strictly.
Derive small-LLM context blocks from the final bible.
Block the loading screen if no valid generated story exists.

This gives us the best balance found so far: enough freedom for unique stories, enough structure for game code, and enough validation to avoid starting a campaign with a hollow rules document.
