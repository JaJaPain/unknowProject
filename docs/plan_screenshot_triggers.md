# Story Screenshot Triggers — remaining four (mini plan, 2026-07-05)

Finishes the PARTIAL todo item "Automatic story screenshots". Capture core
already exists (`scripts/story/StoryScreenshots.gd`: frame_post_draw-timed,
`<campaign>/screenshots/`, 200 cap, headless-safe). Rollback tag:
`pre-screenshot-triggers`.

All four new triggers land in **StoryManager only** (plus StoryStateStore
defaults) — GameRoot/UIManager already call `on_system_arrived`/`on_docked`,
and CombatManager already emits the kill signal Nova listens to.

1. **First jump to a new system** — in `on_system_arrived(system_id)`:
   story_state `screenshot_systems_seen: []` (capped 64). Empty list =
   campaign-load arrival (campaign_start shot covers it): record, no capture.
   Unseen id afterwards: capture `system_first_visit_<slug>` + record.
2. **First dock at a new station** — in `on_docked(station)`: same pattern,
   `screenshot_stations_seen` keyed by `str(station.name)`; capture
   `station_first_dock`.
3. **Kill cinematic frame** — connect `CombatManager.action_impact(target,
   pos, damage, lethal, blocked, crit)` in `_ready()` (same signal Nova uses,
   same guards). On `lethal` and target != player: the execute-camera framing
   is on screen — capture `kill_cinematic`, rate-limited to once per 10 real
   minutes (session var) so a busy campaign doesn't eat the 200-shot cap.
4. **Boss kill** — same handler: if `target.get("is_boss")`, capture
   `boss_kill` ALWAYS (bypasses the kill rate limit; bosses are rare).

State keys go in BOTH StoryManager default dicts + StoryStateStore
`_default_state()`. Tests: extend `run_story_manager_hook_tests.gd` —
first-visit dedup logic via a pure helper
`_first_visit_and_record(list_key, id) -> bool` so the test never needs a
viewport (capture itself stays headless-no-op).
