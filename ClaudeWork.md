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

- [ ] Audit dock/service buttons for consistent labels, capitalization, spacing,
  and disabled-state messages.
- [ ] Check Station Lounge layout at common resolutions and note any overlap,
  clipping, or awkward spacing. Safe fixes are okay; deeper Lounge feature work
  should stay parked.
- [ ] Review inventory UI labels and empty states so the player understands
  consumables, cargo, and special items without being docked.
- [ ] Add controller-focus notes for station services, inventory, system map,
  and Lounge screens: which control should be selected first, next, and back.
- [ ] Check selected-target panel action buttons for obvious active/queued
  feedback gaps. Do not change navigation behavior; visual state only.

## Audio And TTS Hygiene

- [ ] Build a small list of words/faction names that TTS mispronounces or spells
  out, such as all-caps faction labels.
- [ ] Propose a display-text versus spoken-text cleanup plan so UI can keep
  faction emphasis while TTS receives natural casing.
- [ ] Audit recent mission dialogue screenshots/logs for repeated "Indy" usage
  after acceptance lines and document any remaining bad examples.
- [ ] Check whether generated faction names need pronunciation hints or simple
  spoken-name aliases.

## Assets And Metadata

- [ ] Verify Kaelen mood sprite metadata still matches the intended grid labels,
  especially the board-turn-in/WTF expression.
- [ ] Add a short asset naming guide for portraits, badges, generated faction
  images, ship parts, and mood sheets.
- [ ] Review newly added NPC portraits for missing metadata, duplicate names, or
  confusing folder placement.
- [ ] Review badge assets for obvious duplicates or unreadable tiny icons.
- [ ] Make a simple "asset ready checklist" for generated factions: portrait
  pool, badge, voice style, ship style, faction color, and name source.

## Documentation Cleanup

- [ ] Add a short "How to test generated systems visually" checklist to docs.
- [ ] Add a short "Known harmless warnings" note for LF/CRLF Git warnings and
  other noisy but non-blocking editor output.
- [ ] Review `docs/whileYouWasSleeping.md` and move any durable lessons into the
  main plan or a permanent notes file, then leave the temporary file alone.
- [ ] Find outdated fallback examples in docs and mark them as old examples so
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

## Parking Lot

- [ ] Sketch possible light social-sim affordances for the Station Lounge, but
  keep it as design notes only.
- [ ] Sketch possible boss-like discovery visual treatments and encounter
  staging without touching gate or mission code.
- [ ] Sketch possible store presentation polish for future purchase-from-store
  missions without adding the mission type yet.
