# Implementation Log: Vision Slice

**Branch:** `claude/vision-slice` (created 2026-09-24 from `codex/tts-dialogue-hud-fixes`)
**Plan:** `docs/fresh_eyes_vision_plan_2026_09_23.md`
**Owner:** Claude, with free rein from Abe (2026-09-24).

> **Resume here.** A new session reads this file first. The "Now" section says
> exactly what is in progress. Every step below is small, saved to disk as it
> goes, and committed in batches (larger changes are committed immediately).

## Ground rules (from Abe, 2026-09-24)

- Small bites; save to disk very often; commit frequently (batches of small changes, larger ones immediately). Never push unless asked.
- Nobody else edits the repo while this work runs.
- Allowed tools: headless Godot (one test at a time, unique `--log-file`), Ollama, Kokoro TTS, Blender MCP (port 9876). The windowed game is **not** on the list: ask before launching it.
- Old systems are disabled behind flags, not deleted.
- Anything touching the fixed-cast secret goes to Abe for sign-off before it's voiced. The secret never enters a prompt.
- Build my own drone-maze activity (Abe's version stays on his other machine).
- At the end: a JSON file listing every image needed, plus a prompt that makes ChatGPT loop through it and save each image.

## Now

- 2b.5 remaining: pin-board UI for threads (InvestigationPanel), voiced reveal. Then next phase (see plan list).

## Plan of small bites (vertical slice)

1. [x] 0.1 Secret-leak test + shared `ReservedTopics` list.
2. [x] 2.1 `PremiseCardLibrary`: load approved cards from `res://data/content/premise_cards/approved/`, index, light runtime checks. Test.
3. [x] 2.2 `PremiseCardHistoryStore`: per-machine `user://` usage history (cycles, recency). Test.
4. [x] 2.3 `PremiseCardSelector`: filter by situation (quirks, states, factions, seeds, scale, used-in-campaign) and rank by history. Test.
5. [x] 2.3b `SystemProfile`: seeded quirks (0-2) and starting states per generated system; states also change when arcs resolve. Test.
6. [x] 2.4 `ArcState` / `ArcEngine`: live arcs, role casting, beat progression from mission outcomes, resolutions → consequences + seeds. Test with scripted outcomes.
7. [x] 2.5 `PremiseMissionComposer`: card beat mission → existing offer dict, tagged with `story_thread_id` / `story_beat_id`. Test with a fake world snapshot.
8. [x] 2.6 Persistence: arc state in the campaign save.
9. [x] 2.7 Live wiring: arc offers reach the player; QuestManager signals advance arcs.
10. [ ] 2b Main story: 2b.1 HiddenHand data + thread seeding; 2b.2 candidate scoring + code lock; 2b.3 Showrunner LLM pass (Ollama) + validation; 2b.4 reveal + confrontation + season rollover; 2b.5 presentation (threads in briefings, reveal message).
11. [ ] Then Phase 1 (generation windows), Phase 3 extras, activities, fixed-cast work.

## Done

- 2026-09-24: Branch created; vision plan, card brief, card tools and 120 approved cards committed (`38bf096`).
- 2026-09-24: 0.1 `scripts/story/ReservedTopics.gd` (one shared reserved-topic list) and `tests/story/run_secret_leak_tests.gd` (scans all `data/content` JSON, lore/soul docs, and quoted strings in scripts; 362 files; PASS). Fixed one real hit: `the_mutiny_in_the_dark` said "The captain is dead. Or is he?" (Captain is the player's title). Guard lists that *block* reserved words are marked `# reserved-topics: guard`.

- 2026-09-24: 2.1 `scripts/story/premise/PremiseCardLibrary.gd` + test (all 120 approved cards load; bad cards are skipped with a reason, never fatal).
- 2026-09-24: 2.2 `scripts/story/premise/PremiseCardHistoryStore.gd` + test (per-machine `user://premise_card_history.json`; fresh first, then oldest, recent window 30, new cycle at 90%; atomic save; corrupt file = quiet fresh start).

- 2026-09-24: 2.3 `scripts/story/premise/PremiseCardSelector.gd` + test. Hard filters (quirks/states/factions/scale/campaign exclusion); order = machine freshness, then fit (seeds x3, hidden-hand method x2, preferred quirk, theme), then oldest/seeded shuffle. **Finding:** only 75/120 cards fit a plain system; 37 need a quirk the game doesn't generate yet (dead_system 10, dying_star 8, relay_dark_zone 8, gravity_tides 6, ion_storm 2, pulsar/nebula/black_hole 1 each) and 8 need a state (quarantine 3, shortage 2, strike/mourning/power_vacuum 1). Hence step 2.3b.

- 2026-09-24: 2.3b `scripts/story/premise/SystemProfile.gd` + test. Deterministic from system id + seed + star type; tutorial system plain; 0/1/2 quirks at 40/45/15%; star bias (red -> dying_star, white -> pulsar, blue -> ion_storm/nebula); starting states from quirks plus a 45% random one; `apply_changes` for resolution consequences.

- 2026-09-24: 2.4a `scripts/story/premise/ArcEngine.gd` + `docs/arc_engine_design.md` + test. One saveable state dict; start/offers/decisions/outcomes/choices/resolve; game outcome -> card tag mapping (failure tags, comms-reversal offer vs fight, multi-tag findings); consequences land on cast entities, system states/laws/prices, deeds, seeds, ledger. **Stress test: all 120 cards x 6 random playthroughs always resolve.**

- 2026-09-24: 2.4b `PremiseCasting.gd` + `NameForge.gd` + test. Pure over a `world` snapshot (main station, outposts, factions, hostile faction keys, known NPCs). Places distinct in first-use order; factions distinct; `prefer_existing` reuses known NPCs; ships inherit the faction whose role shares a word (else a hostile key); objects -> item names; `fill_text` resolves `{role:x}`, `{system}`, `{player}`. Test: every approved card casts fully with zero unfilled placeholders.

- 2026-09-24: 2.5 `PremiseMissionComposer.gd` + test. Card mission -> standard offer dict (same shape as StoryAgentOfferBuilder), identity in `story_thread_id`/`story_beat_id`, rewards/counts by scale and beat, purchase uses store stock (courier fallback). **All 335 non-investigation missions in the deck validate through MissionAdapter.build_active_state.** 101 investigate missions return `premise_needs_completion` for the live adapter (InvestigationOfferBuilder needs live site placement).

- 2026-09-24: 2.6 `PremiseDirector.gd` (Node, owned by GameRoot later) + campaign-simulation test (4 systems, board -> missions -> decisions, save/reload, ignored arcs settle). Saves as a checkpoint runtime-state section so arcs roll back on reload (same path as `quiet_moments`: GameRoot `_capture_prepared_runtime_state` + `_apply_save_data`). Interim: `investigation_fallback` turns card investigations into a 'collect the survey readings' pickup; the arc still asks for the finding.
- Live facts found: outposts `GlobalState.get_current_pickup_outposts()`, hostile keys `get_current_system_minor_factions()`, generated factions `PublicBoardOfferBuilder._current_system_config().story_pack.faction_agendas`, tutorial done `StoryManager.story_state.first_contract_handed_in`, deliveries need `GlobalState.get_delivery_recipient(station)` non-empty. Board accept path: `UIManager._on_public_board_offer_accept` -> `QuestManager.accept_quest(quest_data, choices[0])` (BOARD lane).

- 2026-09-24: 2.7a `PremiseWorldSnapshot.gd` (the only premise file that reads the live game; docks filtered to those with a delivery recipient).
- 2026-09-24: 2.7b GameRoot wiring: `premise_director` node (init next to quiet moments), reset on new campaign, lazy campaign-seed sync, ensure arcs on system arrival (deferred), QuestManager completed/abandoned/expired -> director, `premise_arcs` checkpoint section (old saves start with none), public helpers `premise_board_postings()`, `premise_pending_decisions()`, `premise_apply_decision()`. Scene-script parse check: 415 scripts, 0 failed.

- 2026-09-24: 2.7c UIManager: premise postings appended to the public board after collection postings and excluded from the board text generator; when the board opens, a pending arc decision is shown first in the agent panel (one button per option; answering returns to the board). Director fills `{role:x}`/`{system}` in decision text. `tests/story/run_premise_suite.sh` runs all 9 premise tests in sequence (all PASS). Existing board/mission/lifecycle/collection tests still PASS. Scene-script parse check 415/0.
- **Gotcha:** Python on Windows writes CRLF by default; Godot rejects `\` line continuations followed by CRLF. Always write with `newline='
'` (or binary). Heredoc-embedded `
` can also land as a literal backslash-n; prefer the Edit tool for GDScript edits.

- 2026-09-24: Spawn safety: generated factions carry `spawn_key` (legacy key from `SystemConfig.faction_id_lookup` present in `faction_weights`); card ships fly under the owner's spawn key or a hostile system faction. Composer test asserts every combat target is spawnable.
- Order chosen after the slice review: logic-heavy, headless-testable work first (Hidden Hand, deeds, recurring cast, undercurrent logic, radio text); UI-heavy work (activities, visuals) later with Abe testing, since the windowed game isn't available to me.

- 2026-09-24: 2b.1-2b.2 `HiddenHand.gd` + tests: season draw (motive/method/goal) weighted toward methods with >=5 deck threads (deck coverage is thin for cornering_a_market 1, debt_leverage 3, slow_infiltration 3; deck report now shows it); trace/decoy seeding; seen/pinned; candidate scoring; draft at 3 seen; lock at 6 seen + 3 traces + 3 candidates; lock refuses strangers/thin links; code fallback.
- 2026-09-24: 2b.3 `Showrunner.gd` + offline test + `tests/story/run_showrunner_live.gd` (manual, needs Ollama). Live qwen3:8b: first run duplicated a link (correctly rejected), after prompt fix it locked (chose a less-evidenced candidate), then it wrote `npc.recurring|Oren Vask` (copied the prompt layout) -> parser now accepts an id with a name attached or an exact display name. num_ctx 4096. **Speed not measurable today:** another process held ~7GB and 88% of the RTX 3060 (12GB); saw 3.8-8 tok/s and 45s loads. Measure properly in the 8GB pass.

- 2026-09-24: 2b.4 `HiddenHandForge.gd` + test (confrontation forged as a synthetic premise card from the lock; passes runtime card checks; all four endings reachable; offers validate). Director integration: season begins with first arcs; selector gets the hand's method; new arcs seed threads; one thread surfaces when a story is shown and one per completed job; draft identity is offered first for prefer_existing roles (recurring cast); lock -> background Showrunner (HTTPRequest, keep_alive 0) with code fallback -> forged confrontation arc; its resolution closes the season; next arrival starts season 2; forged cards persist in the save (`synthetic_cards`). Lock gate now also needs evidence from >= 4 systems: simulation locks at system 5 (target 4-6). GameRoot announces lock/season end in the comms feed. Suite: 12/12 PASS.

## Decisions made along the way

- Card missions carry their identity in the existing `narrative_metadata` fields `story_thread_id` (arc instance) and `story_beat_id` (card:beat:mission), so no mission-schema change is needed.
- Engine code is built as pure domain classes first (headless-testable), then wired into the game.
- Use `PROJECT_MAP.md` to find signatures before opening big files (Abe's reminder).

## Open questions for Abe

(none yet)

## Image needs (collected for the final ChatGPT JSON)

(none yet)
