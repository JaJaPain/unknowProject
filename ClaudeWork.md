# Claude Work Queue

Low-risk work for Claude while Codex continues the main procedural story and
game-loop path. These tasks should be useful whether or not they are completed,
and they should not block or overlap with current Codex work.

## Guardrails

- Do not edit procedural story generation, campaign bible, story-pack
  persistence, generated-system save/load, event scheduler behavior, or mission
  generation logic unless Abe explicitly redirects you.
- Do not change quest objective schemas, inventory transaction rules, gate
  unlock rules, or generated faction identity rules.
- Keep each task small and independently commit-ready.
- If a task uncovers a bug in core systems, document it instead of refactoring
  around it.
- Prefer visual polish, UI clarity, metadata, tests, and documentation.

## Visual Effects And Space Feel

- [ ] Review the current nebula/starfield visuals in generated systems and make
  a short note of any clipping, overpowering brightness, or samey-looking
  palettes. Avoid changing generation logic unless the fix is purely visual.
- [ ] Add or tune subtle ambient variation for clear-space systems so systems
  without nebulae still feel intentionally distinct.
- [ ] Check player boost/thruster visuals and list any missing polish: exhaust
  scale, color, cooldown feedback, heat glow, or camera shake. Implement only
  small effect-only changes.
- [ ] Add a simple visual pass checklist for combat feedback: projectile hit,
  shield hit, hull hit, ship death, asteroid hit, cargo pickup, and repair use.
- [ ] Look for any obvious visual effects that remain after an object dies or
  changes scene, similar to the old dead-ship thruster glow issue.

## UI Polish

- [x] Audit dock/service buttons for consistent labels, capitalization, spacing,
  and disabled-state messages.
- [x] Check Station Lounge layout at common resolutions and note any overlap,
  clipping, or awkward spacing. Safe fixes are okay; deeper Lounge feature work
  should stay parked.
- [x] Review inventory UI labels and empty states so the player understands
  consumables, cargo, and special items without being docked.
- [ ] Add controller-focus notes for station services, inventory, system map,
  and Lounge screens: which control should be selected first, next, and back.
- [x] Check selected-target panel action buttons for obvious active/queued
  feedback gaps. Do not change navigation behavior; visual state only.

## Audio And TTS Hygiene

- [x] Build a small list of words/faction names that TTS mispronounces or spells
  out, such as all-caps faction labels.
- [x] Propose a display-text versus spoken-text cleanup plan so UI can keep
  faction emphasis while TTS receives natural casing.
- [x] Audit recent mission dialogue screenshots/logs for repeated "Indy" usage
  after acceptance lines and document any remaining bad examples.
- [x] Check whether generated faction names need pronunciation hints or simple
  spoken-name aliases.

## Assets And Metadata

- [x] Verify Kaelen mood sprite metadata still matches the intended grid labels,
  especially the board-turn-in/WTF expression.
- [x] Add a short asset naming guide for portraits, badges, generated faction
  images, ship parts, and mood sheets.
- [x] Review newly added NPC portraits for missing metadata, duplicate names, or
  confusing folder placement.
- [x] Review badge assets for obvious duplicates or unreadable tiny icons.
- [x] Make a simple "asset ready checklist" for generated factions: portrait
  pool, badge, voice style, ship style, faction color, and name source.

## Documentation Cleanup

- [x] Add a short "How to test generated systems visually" checklist to docs.
- [x] Add a short "Known harmless warnings" note for LF/CRLF Git warnings and
  other noisy but non-blocking editor output.
- [x] Review `docs/whileYouWasSleeping.md` and move any durable lessons into the
  main plan or a permanent notes file, then leave the temporary file alone.
- [x] Find outdated fallback examples in docs and mark them as old examples so
  they do not keep being reused as desired tone.

## Test And Diagnostics Cleanup

- [ ] Investigate the local headless Godot startup crash separately from gameplay
  changes. Capture exact command, crash text, and whether it happens with a tiny
  no-op script.
- [ ] Add a note describing which tests are safest to run after visual-only
  changes.
- [ ] Look for tests that rely on old fixed agent names in generated systems and
  list them for later cleanup instead of changing mission logic.
- [ ] Review diagnostics output for repeated noisy messages that hide real
  fallback or generation failures.

## Gate Travel Visual Upgrade

- [ ] Implement the EVE Online–style stargate jump transition from
  `GateTravelUpgrade.md`. Four-phase sequence: portal charge, warp snap-in,
  warp corridor tunnel shader, and exit shockwave ripple. Upgrade
  `jump_transition_fx.tscn` node structure, add polar-swirl tunnel shader,
  screen-space distortion shader, star streak particles, and rewrite
  `JumpTransitionFX.gd` with camera FOV tweening and shake. Must be fully
  encapsulated — no changes to GameRoot, save/load, or player controls.

## Parking Lot

- [ ] Sketch possible light social-sim affordances for the Station Lounge, but
  keep it as design notes only.
- [ ] Sketch possible boss-like discovery visual treatments and encounter
  staging without touching gate or mission code.
- [ ] Sketch possible store presentation polish for future purchase-from-store
  missions without adding the mission type yet.

## Next Cooldown Batch

These are fresh low-conflict tasks for the next Claude pass. They should not
touch the main mission generator, campaign bible, gate flow, story-pack logic, or
generated-system persistence.

### Presentation And UI Clarity

- [ ] Add a small visual QA note for generated faction contact screens: portrait
  fit, badge size, role subtitle, button spacing, and whether the portrait/voice
  pairing feels plausible.
- [ ] Audit generated faction names in quest UI and map UI for raw IDs such as
  `GEN_LATCH_PARISH_02` or `FACTION.GENERATED.*`. Document exact screens where
  player-facing display names still need cleanup.
- [ ] Review contract detail panels for overly technical labels and write a
  short before/after copy pass. Do not change mission schema or objective data.
- [ ] Check the selected-target UI at 720p, 1080p, and ultrawide for action
  button crowding, active-state readability, and boost-button placement.
- [ ] Add simple controller-focus notes for any new Station Lounge screens that
  were added after the original controller checklist.

### Audio And Spoken Text

- [ ] Build a spoken-text cleanup sample list from recent playtests: all-caps
  faction names, raw generated IDs, weird station names, and repeated player
  name usage.
- [ ] Document a safe TTS normalization rule set: keep UI text unchanged, but
  speak display names in title case, strip raw prefixes, and preserve acronyms
  only when they are meant to be spelled.
- [ ] Review Kokoro voice mappings and note which existing voices read as male,
  female, or ambiguous so generated portrait/voice pairing can expand beyond the
  old fixed NPC pool later.
- [ ] Create a small pronunciation-notes doc for generated faction names,
  station names, ores, and common mission items.

### Visual Effects And Atmosphere

- [ ] Review nebula visibility in three newly generated systems and record
  whether each system feels distinct, too bright, too empty, or visually noisy.
- [ ] Check asteroid fields after the rock-model pass for scale readability,
  mining-laser contact accuracy, and any cases where bobbing looks unnatural.
- [ ] Add a polish note for faction-owned asteroid belts: possible warning buoy,
  patrol beacon, permit sign, or subtle scanner ring visuals. Notes only.
- [ ] Review boost visuals from cockpit/player-view distance and list what still
  needs feedback: burst start, active trail, cooldown, heat hint, or failure
  state.

### Asset And Metadata Hygiene

- [ ] Verify imported portrait metadata can support future generated NPCs:
  gender tag, age group, role vibe, and any portraits that should be excluded
  from story use.
- [ ] Make a short list of portrait IDs that look like strong faction contacts,
  mechanics, smugglers, miners, soldiers, medics, and lounge locals.
- [ ] Check badge readability at the size used in quest screens and map panels.
  Flag badges that blur into a blob at UI scale.
- [ ] Add a note for generated ship badge placement: minimum readable size,
  contrast, and avoiding mirrored/rotated placement that looks accidental.

### Documentation And Handoff

- [ ] Summarize the latest visual/polish changes from `docs/whileYouWasSleeping.md`
  into durable docs if they are still only in the changelog.
- [ ] Add a "new campaign smoke test" checklist: Kaelen intro, first gate timer,
  generated system arrival, local contacts, public board, station map, inventory,
  and one completed mission.
- [ ] Add a "do not use raw IDs in player text" guideline to the relevant docs,
  with examples of raw generated IDs versus display names.
- [ ] Keep a running list of screenshots that show broken or awkward generated
  content so Codex can turn them into targeted code fixes later.

### Diagnostics And Safe Bug Hunts

- [ ] Look for warnings that mention missing portraits, missing voice mappings,
  fallback dialogue, or raw generated IDs. Capture exact log lines and the screen
  the player was on.
- [ ] Re-run the quest-gen test scene manually and save only the summary plus
  the worst 3 examples. Do not edit generation code from this task.
- [ ] Check whether old generated campaign saves carry stale NPC presentation
  data after fixes. Document expected behavior for old saves versus new
  campaigns.
- [ ] Make a small list of error messages that should be more player-friendly if
  they ever appear during a normal playtest.
