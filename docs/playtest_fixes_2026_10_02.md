# Playtest fixes, 2026-10-02

Abe's playtest of 2026-10-02 found 16 things: 11 to fix, 5 that passed. This
is the plan for the 11, in the order I'd do them (bugs first, then sound,
then polish, then art). Each fix ends with tests passing and a check in
`docs/playtest_todo.md`.

## Passed (no change)

- Number keys pick dialogue options (quests).
- Courier / delivery job completes without crashing.
- Store: icons, credits deducted, item lands in the inventory.
- Job cards are colour-coded; urgent ones amber with a timer.
- No debug or "offline backup" text seen (still watching).

## Fixes

### 1. Autopilot flies through the gas giant and through outposts (bug)

Obstacles are sized from their collision shape plus a small margin (55 m for
stations and outposts); where the visible model is bigger, the route clips
through what the player sees. The start system's hand-built gas giant also
seems to lack the `navigation_clearance_radius` that generated planets get.

- Confirm both, then size obstacles from the visible model's bounds.
- Give the start system's planets proper clearance radii.
- Test: plot routes past a planet and an outpost; fail if any point of the
  path is inside the visible model.

### 2. "SystemContainer [Object]" can be targeted (bug)

The system's own container node shows in the target panel (likely from
clicking a planet, or a miss, picking up its parent). Find the selection path
and stop non-gameplay nodes from becoming targets. Test it.

### 3. T silently ignored; no feedback without a signal

T is dropped without a word near a station, in combat, docked, or with any
"red" ship about, including a contract target anywhere in the system (Abe's
active Reaver contract).

- T always responds. Signal and clear: the tuner opens. Signal but blocked: a
  short on-screen reason ("Too much station noise. Move further out" /
  "Hostiles close"). No signal: a small receiver panel, "Scanning for
  signals..." with a sweep animation for a few seconds, then "Nothing on the
  band."
- Contract targets count as "red nearby" only when they are near, like any
  other hostile.

### 4. Kaelen comments on outpost and board payouts, and not over comms

Her payout "quiet moment" fires for every job, including board and outpost
jobs, held until undock and played as if she were aboard.

- She comments only on jobs she brokered.
- When she does, it comes over comms: comms voice filter and a KAELEN line in
  the feed.
- Her board-job jokes move to N.O.V.A., who is aboard (Abe, 2026-10-02).

### 5. Jenna's voice is the default almost everywhere

The neutral fallback voice (`voice.neutral.v1`, aoede 50 / nova 50) is nearly
Jenna's (aoede 70 / nova 30), and about 25 places fall back to it (board
"Play message", station contacts, flavour lines, lounge, mechanic); plain
aoede is the hard default in 6 more (TTSInterface x3, KokoroSpeechProvider
x2, tts_server.py). The generated-voice builder can pick aoede as a base too.

- Reserve the named cast's voice blends; nothing else may use them or come
  close.
- Give the neutral fallback its own blend that no named character uses; switch
  the six hard aoede defaults to it.
- Board posters speak in their own generated voice (from their faction's
  voice family); neutral only as a last resort.
- Log a warning whenever the neutral fallback is used, so leftovers show up.
- Test: no generated or fallback voice within a set distance of a named one.

### 6. Kaelen speaks too fast on her pre-recorded lines

Since 2026-09-30 the game plays her 93 pre-recorded lines (from 2026-09-10)
instead of synthesising them at her configured speed; the recordings are
matched by words only, so a faster take plays as is.

- Confirm by comparing a recording's length with a fresh render at her speed.
- Re-record those lines at her proper speed (keeps loading fast). Fallback:
  stop using the recordings for her.

### 7. Agent offers: decline goes last, one wording

The decline option sits third ("Decline"), before "Terms / other questions".
Put the way out last on every agent menu, after Terms and flavour options.
Wording: "Not this one." as a dialogue reply, "Decline" only on plain
buttons. Check where "Not this one." actually appears today.

### 8. Collapsible goal card

A small collapse arrow in its corner; collapsed, it is one line ("Shields Mk
II · 65/300 SC"); remembered across sessions. It reopens for a few seconds
when the goal changes or a requirement is met.

### 9. Jenna's maintenance bay matches Kaelen's layout

Bring the maintenance bay (and the other service screens) onto Kaelen's
layout: large portrait left, name and role, dialogue, numbered options, then
the service buttons. Compare the two in code first.

### 10. Gas giant variety

All gas giants use one texture with a tint, so they all look like Jupiter.

- A procedural gas giant shader: bands, swirls and storms from noise, a
  palette per planet from the system seed (pale blue ice giants, cream and
  ochre, rust and violet haze, teal storm worlds), its own band count,
  turbulence and sometimes a storm spot.
- Shader only (Abe, 2026-10-02): no painted maps.

### 11. Reword unclear playtest checks

Rewrite checks that read like the "Not this one." item: say what to do, what
you should see, and what counts as a pass.
