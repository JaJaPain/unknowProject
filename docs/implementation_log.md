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

- Next: activities (signal tuning, drone micro-mining maze) for Abe to test; Phase 1 generation windows. Waiting on Abe: which F5 Nova takes (pace) and which death lines to approve. Faction DNA visual genes and recurring-cast scars wait for the visual pass. UI-heavy work (pin board, activities) after, for Abe to test in the windowed game.
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

- 2026-09-24: Undercurrent death line. `data/content/undercurrent_lines.json` (Abe's line, approved_by_abe), `tools/bake_undercurrent_audio.py` (Kokoro, N.O.V.A.'s blend `voice.nova.v1`; baked `assets/audio/undercurrent/death_line_01.ogg`, 3.2s; **.ogg is git-ignored project-wide, so run the bake tool on any new machine**), `EchoLedgerStore.gd` (user://echo_ledger.json: play seconds, deaths, lines shown), `UndercurrentDirector.gd` (>=5h play, >=5 prior deaths, 1.5% per eligible death [changed to 6% + random line on 2026-09-24, see below], once per machine per line, 20h cooldown), GameRoot `record_player_death` -> director; UIManager `show_death_screen` plays black screen + line + 2s before the panel. Measured 1.49% of 20,000 eligible deaths. No subtitle setting exists yet: when added, show the text with NO speaker label.

- 2026-09-24: System radio + travelling deeds. `RadioBroadcaster.gd` (headlines from live arcs' radio_hooks, deeds from other systems as rumours after 240 campaign minutes naming their origin, local deeds as talk, state/law news from arc consequences, main-story threads with surface 'radio' air here and count as seen) + director `next_radio_item` (each item once per visit) + GameRoot 120s timer -> comms feed 'SYSTEM RADIO'. Voicing (host voice + comms filter, pre-rendered in generation windows) comes with the voice pipeline.

- 2026-09-24: Voice DNA (`VoiceDNA.gd`): stable two-voice Kokoro blends per generated person, faction voice families, never af_bella/bf_emma; `register()` returns a `voice.generated.*` profile id that SpeechService plays.
- 2026-09-24: Line writer (`LineWriter.gd`, commit 4ff41d9). Takes public facts only (the private fact is used only for leak checks), writes one comms line, and code rejects: reserved topics, "shiny", invented numbers, leaked private-fact words, stage directions/quoted narration, stock filler ("clock's ticking", "just do it", ...). Director: `prepare_lines` on system arrival queues this system's offers; one request at a time; paused while the Showrunner runs; one retry, then the director note stands; lines saved in arc state (`written_lines`), pruned when the arc resolves; audio pre-cached through SpeechService. Board: written line replaces the note, plus a "Play message" button. **Live comparison (8 real card missions):** qwen3:4b passed 6-7/8 at ~2-5s each; qwen3:8b passed 3/8 and was no better (first calls stalled because 4b was still resident, 30m keep-alive, while another process held ~7GB). Decision: lines use 4b. **8GB lesson:** only one model fits at a time, so the generation-window scheduler must unload the small model before any 8b call.
- 2026-09-24: Comms voice (commit f33084b). `TTSInterface` builds a "Comms" bus (band-pass 1.7kHz + light overdrive) that feeds the Voice bus; `SpeechService.play_on_comms` routes exactly one line there. The board's "Play message" and the system radio use it; each system's host has a VoiceDNA voice and reads radio items only in quiet moments (no other speech, no interaction, no combat window). `tests/story/run_comms_bus_tests.gd`; the suite passes `-- --baseline-offline` to every test. Untested by ear: Abe should listen in the windowed game and say if the filter is too harsh.
- 2026-09-24: Model scheduling (commit e02e5c5): the director unloads the small model before the Showrunner's 8b request. Known gap: a line request already in flight can still finish first; harmless (it completes before the unload).
- 2026-09-24: Recurring cast (commit 5059351). `RecurringCast.gd` derives each person's history from arcs + fates (no new save data): attitude from their last ending (bitter/warm/mixed/gone), candidates (met, alive, free, not busy in any live arc, shown or not), weighted casting (grudges and debts come back 3x), and a public `history_note` for the line writer. **Bugs the campaign test caught:** (1) two arcs starting on the same arrival could cast the same person (busy now counts unshown live arcs); (2) the Hidden Hand confrontation could cast someone dead, jailed, or starring in another live story. Now the dead and jailed are never suspects, the lock waits while the prime suspect's other story runs, and the Showrunner's shortlist holds only free people. The director simulation still locks at system 5. 12-system simulation: 36 returning faces, no double casting. Live: qwen3:4b uses warm history well ("You got my last two runs right") but muddled a grudge, so the grudge phrase was sharpened. Scars (visible ship damage) wait for the visual pass.
- 2026-09-24: Faction DNA (commit 0e27cbe). `FactionDNA.gd` derived from the faction id: axes (order/profit/mercy), one of 6 naming languages (clipped "Stad Brod", flowing "Silae Lain", guttural "Draum Khugraur", sibilant, bright, ceremonial), doctrine, silhouette, wear. Casting names people and ships in their faction's language (faction role sharing a word, else the card's first faction). Radio: a local faction's take on each deed via `judge_deed` (verbs in the tag -> axes); all 96 deck deed tags understood; shrugs go unsaid. Existing per-faction fields in `CampaignGeneratedFactionStore` (ideology text, humour, voice_style, badge, colours) were left as they are; DNA adds what was missing without a save change.
- 2026-09-24: Stray Gemini files in the repo root deleted (Abe's go-ahead).
- 2026-09-24: System quirks in play (commit 7ed8511). `scripts/story/quirks/SystemQuirkEffects.gd` (pure rules) + `SystemQuirkRunner.gd` (GameRoot child): pulsar sweep every 90 s (8 s NAV warning, screen wash, 15% shield drain, never hull); ion storm 40 s windows every 150 s (shield recharge x0.4); nebula (hostiles notice the player at 70% range); relay dark zone (no system radio). Effects via `GlobalState.system_environment` / `environment_value()` (defaults = unchanged play); clocks run only undocked; tutorial plain; `enabled` switch. Other quirks (dense_debris, dying_star, black_hole_proximity, dead_system, gravity_tides) still only shape card choice.
- 2026-09-24: Death-line drafts (commit c3bbebb): 4 N.O.V.A., 2 Kaelen blaming N.O.V.A. (Abe's idea), 1 exchange with Abe's "Shut up, Kaelen." reply. Per Abe, an exchange bakes into ONE clip (`parts` in the JSON; the bake tool joins voices with a 0.35 s gap). Test guards that drafts never play.
- 2026-09-24: Subtitles (commit 8102d66). `SpeechService.subtitle` signal -> `scripts/ui/SubtitleOverlay.gd` (layer 129). Fixed cast named; comms lines named by caller; unset voices unnamed (they fall back to Kaelen's voice, so never label by resolved profile). Death moment unnamed. Settings > Audio > Subtitles, saved in `user://player_preferences.json`, default ON; the intro's caption follows it. Known overlap: dialogue windows that already print a line will also caption it; the toggle covers players who dislike that.
- 2026-09-24: Pin board (commit ec3a176). `scripts/ui/PinBoardPanel.gd` opens from a "Loose ends (N noticed, M pinned)" button on the contract board (hidden until a thread is noticed). Notes show place and campaign day; Pin/Unpin feeds HiddenHand scoring. No hints until stage revealed/closed, then "Connected: ..." or "A dead end." and the hand's name. Undock closes it (it had to join toggle_dock_menu's open-screen check, or undocking would have ignored it).
- 2026-09-24: F5-TTS voice clones (commits d1a7524, 7be2e38). Abe's old pipeline: F5-TTS cloned from Kokoro-made samples. Env at `D:/CodingProjects/f5-tts-env` (py3.10, torch 2.4.1+cu124, f5-tts; weights from Hugging Face on first run). `tools/voice_refs/` (nova_calm, nova_urgent, kaelen refs + transcripts, clones.json, README), `tools/f5_render.py`. Bake tool routes voice.nova.v1 through F5 (per-line `clone_ref` override). Kaelen stays Kokoro (Abe likes it). F5 Nova renders faster than Kokoro (follows the urgent reference); a 0.85-speed take was sent for comparison. About 10-15 s per line, mostly model load.
- 2026-09-24: Death-line rules (Abe): 6% per eligible death (his "5-8 percent"), then a random line among the approved ones not yet heard (was 1.5% in file order). Measured 5.88% of 20,000. Other gates unchanged (5 h play, 5 prior deaths, 20 h cooldown, each line once per machine).
- 2026-09-24: N.O.V.A. F5 voice rebuilt from Abe's zip (the old machine's TestTTS pipeline): original `bf_emma` reference, F5 defaults, `fix_tails`. My earlier tuning (extra time, retries, Whisper checks, remade references) made it worse and was removed. F5 takes vary per render, so lines are chosen by ear from several takes and installed with `bake_undercurrent_audio.py --take`; since `.ogg` is git-ignored and a take cannot be re-rendered, installed F5 takes must be force-added to git. "Kaelen" is respelled "Kaylen" in the spoken form only (F5 guessed it wrong in some takes); a final "!" makes F5 lift the last word, so line 01 speaks with a full stop. Draft 04 dropped (Abe).

## Decisions made along the way

- Card missions carry their identity in the existing `narrative_metadata` fields `story_thread_id` (arc instance) and `story_beat_id` (card:beat:mission), so no mission-schema change is needed.
- Engine code is built as pure domain classes first (headless-testable), then wired into the game.
- Use `PROJECT_MAP.md` to find signatures before opening big files (Abe's reminder).

## Open questions for Abe

- Death-line drafts 02-08 in `data/content/undercurrent_lines.json` (preview clips: `python tools/bake_undercurrent_audio.py --preview` -> `.tmp_godot_user/undercurrent_previews/`). To approve one, set `approved_by_abe: true` (or tell Claude which ones), then run the bake tool. 07 is Abe's Kaelen -> N.O.V.A. exchange baked as one clip.
- Listen to the comms filter and the pulsar screen wash in the windowed game; say if either is too strong.

## Image needs (collected for the final ChatGPT JSON)

(none yet)
