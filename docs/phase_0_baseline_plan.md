# Phase 0: Preserve The Prototype

## Purpose

Create a known-good, recoverable baseline before changing the game's campaign
architecture. Phase 0 does not add procedural campaign systems. It proves that
the current prototype is preserved, testable, documented, and safely backed up.

## Repository Target

- GitHub repository: `https://github.com/JaJaPain/unknowProject.git`
- Working branch: `codex/jumpgate-system`
- Previous remote at the start of Phase 0:
  `https://github.com/JaJaPain/SPGMBeta.git`

Changing the remote must not rewrite local history or mix unrelated working
changes into a commit.

## Checkpoint 1: Repository Setup And Jump-Gate Stabilization

Scope:

- Point `origin` at the new GitHub repository.
- Confirm the current branch and recent jump-gate commits.
- Run headless import and parse checks.
- Run startup long enough to catch immediate runtime failures.
- Run the automated two-way gate and save-state smoke test.
- Run the automated docking smoke test.
- Record any failures before changing gameplay code.
- Complete the remaining hands-on jump-gate gameplay checklist.

Completion criteria:

- The new remote is configured.
- Both automated smoke-test paths pass.
- Godot imports, parses, and starts without a new error.
- The player can manually travel in both directions and retain expected state.
- Any unresolved problem is recorded with reproduction steps.

## Checkpoint 2: Recoverable Git Baseline

Scope:

- Separate unrelated working changes by file and purpose.
- Commit completed fixes independently.
- Commit planning documents independently.
- Tag the final verified baseline.
- Push the branch and baseline tag to the new repository.
- Confirm the remote branch contains the expected commits.

Proposed tag:

`prototype-baseline-v1`

Completion criteria:

- Working changes are either committed intentionally or documented as active
  work.
- No commit contains unrelated files.
- The branch and tag exist on GitHub.
- A fresh clone can identify the correct Godot project and required external
  assets.

## Checkpoint 3: Full Gameplay Regression Pass

Test areas:

- New game and restart.
- Pause and unpause.
- Manual flight, targeting, approach, and docking.
- Mining, cargo capacity, ore sale, and station storage.
- Combat, damage, shields, destruction, and restart.
- Faction hostility, reputation changes, and safe zones.
- Quest generation fallback, acceptance, progress, completion, and abandonment.
- Special pickup mission flow.
- Upgrade purchase, power limits, stat application, and persistence.
- Outbound jump, return jump, arrival cooldown, and transition controls.
- Automatic save after docking or gate arrival, startup load, and restored state.
- Confirm that no player-facing manual save or save-slot UI currently exists.
- LLM unavailable behavior.
- TTS unavailable behavior.

Output:

- A dated test matrix with pass, fail, blocked, and notes.
- Reproduction steps for every failure.

Completion criteria:

- Every test area has an explicit result.
- Critical data-loss, progression-blocking, and crash defects are fixed or
  declared blockers.

## Checkpoint 4: Defect And Performance Baseline

Record:

- Known gameplay defects and severity.
- Godot startup time.
- First-system loading time.
- Gate transition loading time.
- Process system-RAM use.
- GPU VRAM use in representative gameplay.
- Frame rate in the station area, asteroid fields, and combat.
- LLM response latency and fallback rate.
- TTS first-response and cache-hit latency.
- Current save-file size.
- Current installed project size excluding development-only caches.

Test target:

- A representative 8 GB VRAM GPU.

Completion criteria:

- Measurements include hardware, settings, scene, method, and date.
- Later architectural work can be compared against this baseline.

## Checkpoint 5: Repeatable Baseline Checks

Add one documented verification entry point that can run:

- Godot import.
- Script and scene parse/startup check.
- Two-way gate smoke test.
- Save-state smoke test.
- Docking smoke test.
- Static checks such as `git diff --check`.

The command must:

- Return a failing exit code when any check fails.
- Keep test save files isolated or remove them after completion.
- Produce a concise summary.
- Avoid requiring the LLM or TTS services for core gameplay checks.

Completion criteria:

- One command runs the baseline suite.
- The suite passes twice consecutively from a clean checkout.
- The command and expected output are documented.

## Execution Rule

Implement and verify one checkpoint at a time. Do not begin the next checkpoint
until the current checkpoint has a recorded result and a recoverable Git
checkpoint.

## Checkpoint 1 Status

Date: 2026-06-13

Automated results:

- `git diff --check`: PASS
- Godot headless import: PASS
- Headless startup: PASS
- Two-way gate smoke test: PASS
- Save-state smoke test: PASS
- Docking smoke test: PASS
- Restart smoke test: PASS

Environment note:

- Automated Godot runs redirect `APPDATA` and `LOCALAPPDATA` to the project's
  `.tmp_godot_test` directory because the execution sandbox cannot write to the
  normal Windows profile.

Known non-blocking issue:

- Headless shutdown may report leaked `ObjectDB` instances and resources when
  background LLM or TTS requests are still active. Core smoke-test assertions
  pass before shutdown. Track cleanup separately during baseline hardening.
- The current save implementation is an internal single-file autosave prototype.
  There is no player-facing manual save, load menu, or save-slot selection.

Resolved during Checkpoint 1:

- Restart previously left the new loading screen at 5%. The LLM and TTS
  autoloads survived scene reload in a connected state, but the replacement
  `UIManager` waited for connection signals that would not fire a second time.
  The new UI now adopts current service state immediately after subscribing.
- Added `--restart-smoke-test` to verify initial loading, the actual Restart Game
  path, warm-service adoption, fresh quest generation, TTS preparation, and
  loading-screen completion.

Still required to complete Checkpoint 1:

- None.

Repository setup result:

- `origin`: `https://github.com/JaJaPain/unknowProject.git`
- Branch: `codex/jumpgate-system`
- Remote change confirmed on 2026-06-13.

Hands-on result:

- Restart Game completed successfully in the normal game window.
- Restart returned the player to the beginning with fresh gameplay state.

Checkpoint 1 result: COMPLETE

## Checkpoint 3 Status

Date: 2026-06-13

Result: COMPLETE

- Every gameplay regression area has an explicit result.
- Core flight, docking, mining, economy, combat, missions, services, upgrades,
  gate travel, autosave, startup restoration, LLM fallback, and TTS failure
  behavior passed automated or hands-on verification.
- Defects found during the pass were fixed and recorded in
  `phase_0_gameplay_regression_2026-06-13.md`.
- Remaining headless LLM/TTS shutdown warnings are documented as non-blocking
  cleanup work for the defect and performance baseline.
