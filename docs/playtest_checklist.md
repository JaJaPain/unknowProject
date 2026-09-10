# Playtest Checklist

Ordered by the sequence you will actually hit things: dev-panel setup, then the
tutorial in order, then everything after it. Each item says **what you are
deciding** -- if you finish an item without a decision written down, it did not
count.

**DP** = needs a dev panel adjustment. **DP: none** = just play and watch.

---

## 0. Before you launch (5 minutes, dev panel)

### 0.1 Decide how you want to fly this session
**DP: Sensors tab (new).**

Sensor reveal ships **OFF**. Nothing hides until you turn it on.

- **Leave it off** if this session is about the tutorial and the bug list. You
  will get today's build exactly as it behaves now.
- **Turn it on** if this session is about tuning sensors (item 2.1 below).

**Decide:** off (bug hunt) or on (sensor tuning). Doing both in one session will
muddy the bug reports, because a missing object could be a bug or could be the
reveal working as designed.

---

## 1. The tutorial, in order

### 1.1 New campaign + loading screen
**DP: none.**

Watch/listen from the moment you click new campaign.

- Does N.O.V.A. speak a stray filler word during the loading screen?
  *(bugs.md: "N.O.V.A. filler word plays during new-campaign loading screen")*
- Does the campaign land in an **empty** save slot, or overwrite an existing one?
  *(bugs.md: "New campaign overwrites existing slot")*

**Decide:** are these still happening on this build? If the filler word is gone,
say so -- it may have been fixed incidentally and I should stop carrying it.

### 1.2 First dock
**DP: none.**

The single most bug-dense moment in the game right now. Three separate reports
live here, so go slowly and note the ORDER things happen in.

- Does the station welcome overlay appear at all, and is N.O.V.A.'s portrait
  present? *(First run of a session: no welcome overlay, portrait missing)*
- Does N.O.V.A. talk **over** the dock flow when she should be quiet?
  *(N.O.V.A. talks during first dock flow)*

**Decide:** is the welcome-overlay failure specific to the FIRST run of a
session, as recorded, or does it happen every dock? That distinction is what
tells me whether it is an init-order problem or a state problem, and it is the
one thing I cannot determine without you watching it twice.

### 1.3 The overview panel
**DP: none.**

- Does the overview start **collapsed** for a new player?
  *(Tutorial overview panel starts collapsed for new players)*

**Decide:** should a new player's overview start expanded, or start collapsed
with something drawing the eye to it? This is a teaching decision, not a bug fix
-- a collapsed panel is defensible if the tutorial points at it.

### 1.4 Jenna Kross and the agents
**DP: none.**

- Does Jenna replay her first-meeting intro at a second dock?
  *(Jenna Kross replayed her first-meeting intro)*
- Do agents address you as **"Indy"** or **"Shiny"** instead of your name or
  rank? *(Agent dialogue sometimes addresses player as "Indy" or "Shiny")*
- When you ACCEPT a job, is the confirmation spoken in **Kaelen's voice** rather
  than the agent's? *(Agent accept reply uses Kaelen voice)*

**Decide:** the voice one is a canon violation, so it outranks the others. If you
hear it, note WHICH agent and WHICH job type -- Kaelen's voice belongs to Kaelen
alone, and I need to know if it is one code path or all of them.

---

## 2. After the tutorial

### 2.1 Sensor reveal -- the big one *(new this session)*
**DP: Sensors tab. Toggle ON, then use the four dials.**

This is the only item where I am asking you for **numbers**, not a yes/no. The
defaults came from a plan written without knowledge of this game's scale, and
your object placements sit within a few hundred units, so I expect the defaults
to reveal nearly everything. Treat them as wrong until proven otherwise.

The Sensors tab shows a live **metre readout** under the dials -- watch that, not
the multipliers, because "1.50x" does not tell you what you will see out the
window.

Fly and answer four questions, in this order:

1. **Ordinary ships and wrecks** -- turn the range scale down until contacts stop
   appearing the instant you arrive. Where does a system start to feel like it
   has space in it rather than a list?
2. **Drop range** (currently 2x detect) -- fly away from a wreck you found. Does
   it hold on the overview long enough that you do not feel you lost it, but
   still eventually let go?
3. **Mission ships** (currently 1.5x) -- take a kill or recovery job. Do you find
   the target without tedium? This dial exists so you are not hunting one hull
   among identical contacts.
4. **Unfound gates** (currently 0.25x) -- **the value I trust least.** An
   undiscovered gate should feel like something you find, not something handed to
   you on arrival. Too low and a new route is invisible and frustrating; too high
   and discovery means nothing.

**Decide:** four numbers, read off the metre readout. Also decide whether reveal
should become the DEFAULT, or stay an option. If it stays off, this whole feature
is inert and I should know that before building more on it.

### 2.2 Cause-aware enemy taunts in a real fight
**DP: none** (provoke a real fight; the Combat Feel tab can spawn an inbound
hostile if you want one quickly).

The taunts were approved by reading and by listening in isolation. They have not
been heard **in a fight**, which is the only place they count.

**Decide:** do the lines fit the fight they fire in? Specifically -- does a
`code_enforcement` fight sound different from an ordinary one? If every fight
sounds the same, the cause-aware bundling is not reaching the player and the
whole system is decoration.

### 2.3 Taunt audio loose ends
**DP: none.**

Three known gaps from when you finished the audio review:

- **`bm_george`** -- you flagged the voice quality. Confirm whether it is bad
  enough to cut. If yes I remove it from the lead pool and the other seven
  voices cover it, no re-bake needed.
- **14 clips under 2 seconds** -- do they land as punchy, or as clipped?
- **`contract_hit` bribe line** -- you have options A/B/C waiting and never
  picked one.

**Decide:** cut `bm_george` or keep him; and pick A, B or C.

### 2.4 Combat verbs that still default silently
**DP: none.**

Two combat actions currently pick for you:

- **Shield reroute** always defaults to the **Front** face (no face picker yet).
- **Boost** always defaults to **"closer to enemy"** (no Evade/Close toggle).

**Decide:** while playing, do these defaults bite you? If Front is right 90% of
the time, the sub-picker is low priority; if you keep wanting a different face,
it moves up. Same for boost -- if you never want to evade, the toggle is wasted
work.

### 2.5 Combat exit state
**DP: none.**

Two reported issues at the END of a fight, so check the moment combat resolves:

- Does the **shield visual persist** after combat ends?
- Is the **mouse cursor lost** when entering combat?

**Decide:** just confirm still-present or fixed.

### 2.6 Flying and autopilot
**DP: none.**

- **Autopilot object avoidance regression** -- the immersion-breaking one.
- **Fishtailing in tight spaces** -- ship wags its tail squeezing past a station
  or between asteroids.

**Decide:** is the fishtail a SEPARATE problem from the avoidance regression, or
the same steering fault seen from a different angle? If they are one bug, I fix
`steer_towards()` once instead of twice.

### 2.7 Quest tracker
**DP: none.**

- Does the **blue box reappear** on a second quest?

**Decide:** still present or fixed.

---

## 3. Not ready to playtest yet -- do NOT go looking for these

Being explicit so you do not waste a session hunting things that are not wired.

- **H1, the two-shape investigation prototype.** The selection, offer, scan-hold
  and reveal logic are all built and tested, but **nothing is mounted to a UI
  yet** -- there is no scan prompt to hold and no resolution screen. You cannot
  play an investigation this build. Item 2.1 is the only part of P2 you can
  actually feel. H1 stays open.
- **H2 (VRAM harness on the 8GB GPU)** and **H3 (qualification hardware)** are
  measurement tasks, not playtests.
- **H4 (voice delivery presets)** and the **Orpheus / cloned-voice trial** are
  audio auditions to run at the desk, not in flight.
- **H5 (three two-hour freshness sessions)** is a release-sign-off activity and
  should wait until there is more new content to be fresh ABOUT.

---

## How to report back

For each item: **still broken / fixed / decided X**. For 2.1, give me the four
numbers off the metre readout. Anything you decide here I will fold into
`docs/todo.md` and `docs/bugs.md`, which stay the source of truth.
