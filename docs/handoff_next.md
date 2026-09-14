# CONTINUE — SpaceGame kickoff prompt

_Paste the block below into a fresh conversation to continue. Regenerate this
file when priorities shift._

---

CONTINUE — SpaceGame (Godot 4.6.3, GDScript, Windows). Repo:
C:\CodingProjects\SpaceGame   Branch: segment-3/economy-stores-events

Space trading/combat game with a local-LLM living narrative (Ollama:
qwen3:4b small + qwen3:8b large; Kokoro TTS via scripts/tts_server.py).

ORIENT FIRST (don't trust this prompt over the docs — the repo moves fast
across sessions):
- PROJECT_MAP.md — nav index (paths + class/function signatures). Check it
  before grepping.
- docs/whileYouWasSleeping.md — append-only session log, NEWEST AT BOTTOM.
  Read the last few entries; latest is 2026-08-06 (station-welcome/portrait
  timing fix, first-five-minutes affordance pass, tutorial gating).
- docs/bugs.md (> Active) and docs/todo.md — the live trackers.
- CLAUDE.md — project rules.

CONVENTIONS:
- Headless tests ONE at a time, unique --log-file:
  .\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . \
    --script res://tests/<x>.gd --log-file .tmp_godot_user\test_logs\x.log
  "[PASS]" + exit 0 = pass. ObjectDB-leak + compile-order noise AFTER [PASS]
  are known-harmless. A signal-11 crash BEFORE any output = the known Godot
  log-rotation bug, not a real failure.
- Run tests/parse_check_scene_scripts.gd after any autoload-touching edit.
- Commit one small slice at a time; end messages with Co-Authored-By.
  Never destructive git. LEAVE the large addons/godot_ai working-tree churn
  alone — that's the godot-ai MCP plugin auto-updating itself, not our work.
- Diagnostics: GenerationDiagnostics prints to console AND writes
  logs/fallback_summary.txt — check that file after a play session for
  fallback types/reasons.

WHERE WE LEFT OFF (last thread: making conversations sound normal):
Just-landed dialogue-quality fixes (in the tree, NOT yet verified live):
- Kaelen turn-in prompt: removed a verbatim sample sentence the 4b was
  parroting; pinned outcome to the actual task; forbade naming the payer /
  any faction but the contract faction / the anonymous client.
- STARTER MISSION ("Clean and Easy") Kaelen turn-in is now AUTHORED, not
  4b-generated (UIManager._store_authored_tutorial_kaelen_bundle +
  QuestManager.is_intro_tutorial_contract).
- Nova line-bank batch generation converted @@label text -> FLAT JSON
  (qwen3 rejected @@label wholesale live). Nova banks now seed their
  generated categories on campaign load.
- Nova speech budget no longer spent by combat lines (she was going silent
  on docks after a fight).
- Fixed a crash on player death (NPCShip cast a freed GlobalState.player).
Narrative systems Phases 8A/8B/9 are complete and unit-tested (semantic
movement events + ShipBehaviorObserver, Nova campaign line banks, instant
lounge exchange bundles). Deterministic tests pass; live-model runs pending.

NEXT STEPS (do in order, smallest/highest-value first):

1. LIVE-VERIFY the dialogue fixes (a real Ollama run, ~90s after a fresh
   campaign loads so the small model warms + banks seed). Confirm via
   logs/fallback_summary.txt + console:
   - nova_line_bank shows NO seed_batch_failed / all_lines_rejected (the
     JSON-format fix works live).
   - starter-mission Kaelen turn-in reads clean and in-voice (authored),
     never inventing a faction.
   - N.O.V.A. speaks on docking; combat doesn't mute her next dock line.
   If nova_line_bank still fails live, iterate the prompt/parser in
   LLMInterface.request_nova_line_bank_batch / parse_nova_line_bank_batch.

2. FIRST-FIVE-MINUTES bugs (natural continuation of the affordance work;
   all in docs/bugs.md > Active):
   - N.O.V.A. filler word plays during new-campaign loading screen.
   - N.O.V.A. talks during first-dock flow (should defer to Kaelen
     onboarding — gate on the same first-dock story flags).
   - Tutorial overview panel starts collapsed for new players.
   - Agent dialogue sometimes addresses the player as "Indy"/"Shiny"
     wrongly.

3. HIGH still-open bug — Autopilot object avoidance regressed: "Fly to" a
   target on the far side of a planet flies the OPPOSITE direction, then
   stalls with no replan. Multiple prior fixes (June) did NOT hold.
   Re-investigate PlayerShip _route_steer_target planner output +
   _get_autopilot_avoidance for a heading sign-flip and a stall-without-
   replan. Meaty but high-impact.

ALREADY DONE (do not redo): the first-mission KILL_SHIPS target respawn
soft-lock is fixed — QuestManager.plan_missing_kill_ship_target_respawns
exists and is wired into the load path, with a test in
tests/domain/run_mission_state_transition_tests.gd.

DEFERRED (design only, no code yet): 8GB-VRAM shipping target needs a
TEMPORAL model-swap plan — gameplay runs pure small-model; the 8b runs only
behind loading/prep gates (evict small first). Blocker to confirm: two
large_story calls fire mid-campaign (chapter_plan on advance ~GameRoot.gd,
story_horizon ~StoryManager.gd) and must be pushed behind prep gates.

Start by orienting from the docs above, then do step 1.
