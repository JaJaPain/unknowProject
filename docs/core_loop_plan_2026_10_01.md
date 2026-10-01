# Core Loop Plan: Progression Gates, the Upgrade Economy and the Pull Outward (2026-10-01)

Abe's brief: make the player engage with ship upgrades by making them a
requirement for gate travel the further out they go; guide them into it
(mine, bank the ore, pay for the upgrade); and give a constant push to explore,
new for each campaign. These are core features, so the numbers and rules below
are meant to be checked, tuned and then held to.

---

## 0. The loop in one picture

A AAA loop is several loops nested inside each other, each one feeding the next:

| Loop | Length | What the player does | What it pays into |
|---|---|---|---|
| **Moment** | 30 s | Fly, mine a rock, fight a turn, dock | Ore, credits, hull damage |
| **Run** | 5-10 min | A job, a mining trip, a drone dive, chasing a rumour | A full hold, a payout, a tech-grade material, a story thread |
| **Rung** | 30-45 min | Save up for and fit the upgrade the next gate class needs | Access to the next band of systems |
| **Season** | 3-6 h | Follow the campaign's **Lodestar** (Section 4) out to the edge of the map | The main story's reveal, a new Lodestar |

The rule that makes it work: **every loop always shows the player the next
step of the loop above it.** While mining (Moment), the HUD shows how much ore
the next upgrade still needs (Rung). While upgrading (Rung), the star map shows
which systems that unlocks and which way the Lodestar lies (Season). The player
never has to wonder what they are working towards.

---

## 1. What exists today, and the gaps

**Already built (keep):**

- **Upgrades** (`GlobalState.UPGRADE_TREE`): weapons, engine, shields, mining,
  cargo; two branches each; tiers 2-5. Cost = credits + ore (hold, then the
  station ore bank) + a tech-grade material (`UPGRADE_MATERIALS`:
  thermal lattice for weapons/engine, rad-quartz for shields/mining,
  cryo-ferrite for cargo) + resonant crystals at Mk IV/V. Materials come only
  from drone dives into red rocks.
- **Ore bank** (`deposit_ore`, `player_storage_ore`): one account, reachable
  at stations, capacity raised by cargo upgrades.
- **One gate rule** (`GateRatingGuide`): after the first two jumps, unvisited
  systems need Shields Mk II, with N.O.V.A. walking the player through the
  material step. Returning to a visited system is always allowed.
- **Endless frontier** (`GateDiscoveryManager`): gates go unknown → rumoured →
  revealed (Kaelen sells reveals); destinations are generated on demand.
  `PremiseWorldSnapshot._system_depth` gives each system its gate depth from
  the start, already used for jump fuel cost.
- **Story per campaign**: premise cards, the Hidden Hand, loose ends board,
  anomaly rumours with search areas, system quirks (planned/partly built).

**Gaps this plan closes:**

1. **One rung, no ladder.** After Shields Mk II nothing else is ever
   required. Weapons, engine, mining and cargo upgrades are optional, so many
   players will never touch them.
2. **The walkthrough stops at the material.** It doesn't teach credits, ore,
   banking, or the upgrade screen itself; the player has to find those alone.
3. **Requirements are discovered by bumping into them.** A gate only says it is
   blocked when the player tries it. Nothing shows the requirement in advance,
   so the player can't plan a run around it.
4. **Nothing pulls outward.** Deeper systems aren't richer, more dangerous or
   more interesting in a way the player can see before going, and nothing
   specific is waiting out there.
5. **No progress display.** No HUD goal shows "the next thing, and how far
   along I am".

---

## 2. Pillar A: the gate ladder (the Rung loop)

### 2.1 Gate classes by depth

Every gate gets a **class** from the depth of the system it leads to (the
existing `_system_depth`). Deeper gates are older, more damaged and harsher on
a ship: that is the in-world reason, and N.O.V.A. (who hates gates) explains
each class the first time.

| Class | Destination depth | Needs | In-world reason (N.O.V.A.) |
|---|---|---|---|
| I | 0-2 | nothing | Local gates, well kept. |
| II | 3-4 | Ship Rating 6 **and Shields Mk II** | The transit field strips unhardened shields. (Today's rule, kept as the tutorial rung.) |
| III | 5-6 | Ship Rating 8 | Older rings, rough folds; a stock ship shakes apart. |
| IV | 7-9 | Ship Rating 11 + this campaign's **keystone** (2.3) | Deep gates; every campaign's deep space is hostile in its own way. |
| V | 10-12 | Ship Rating 15 | Half-dead gates. |
| VI | 13+ | Ship Rating 20 | The edge. Where the Lodestar lives (Section 4). |

### 2.2 Ship Rating, not one fixed upgrade per gate

**Ship Rating = the sum of the five systems' tiers** (weapons, engine,
shields, mining, cargo). A stock ship is 5; fully upgraded is 25.

Why a rating rather than "Class III needs Engine Mk III":

- **Choice.** A fighter, a miner and a hauler all climb the ladder, each by
  upgrading what they enjoy. Every upgrade counts towards the next gate, so no
  upgrade is ever "optional and ignored".
- **One number to show.** The HUD shows `Ship Rating 7 · next gate class 8`.
  The star map shows each gate's class. The player can plan.
- **Tunable in one table.** Class thresholds live in one constant.

The fixed requirements are kept small and meaningful: Shields Mk II at Class
II (the authored tutorial rung that teaches the whole system once) and one
keystone per campaign at Class IV.

### 2.3 The keystone: one requirement drawn per campaign

At campaign start, draw one **keystone** for Class IV gates from a small deck.
It comes from that campaign's deep space, so it differs between playthroughs
and gives the deep systems an identity before the player gets there:

| Keystone | Needs | Deep-space reason |
|---|---|---|
| Radiation belt | Shields Mk III | A stellar remnant floods the deep gates. |
| Gravity shear | Engine Mk III | The folds are steep; a weak drive can't hold the line. |
| Hostile picket | Weapons Mk III | Something guards the deep gates and shoots first. |
| Long dark | Cargo Mk III | No stations past the line: you carry your own fuel and air. |
| Ore-starved | Mining Mk III | The deep belts are hard ores; a stock laser can't cut them. |

N.O.V.A. hints at the keystone early (a rumour at depth 4-5, a line when the
first Class IV gate is revealed), so it never arrives as a surprise wall.

### 2.4 Rules that keep it fair

- **Never stranded.** Gates back to visited systems are always open (as now).
  Every system always has at least one gate the player can currently use, or
  one class away.
- **Visible before it matters.** A gate shows its class and requirement when
  revealed (star map tooltip, gate label on approach), not only when refused.
- **Refusal teaches.** Trying a gate you can't use opens the same guidance as
  today's walkthrough, but for whichever requirement is missing, with the cost
  breakdown (Section 3.3).
- **No penalty for exploring sideways.** Lateral gates within the same class
  are always open. The ladder only gates going deeper.
- **Old saves.** Campaigns that already passed Class II keep all visited
  systems open; the ladder applies from their current depth.

---

## 3. Pillar B: paying for it (mine, bank, upgrade)

### 3.1 The three things an upgrade costs, and where each comes from

| Cost | Comes from | Player decision it creates |
|---|---|---|
| **Credits** | Jobs, selling ore, selling recordings and survey data | Take risky well-paid work, or safe cheap work? |
| **Ore** | Mining (laser), into the hold, then **banked** at a station | **Sell it or bank it?** Selling pays now; banking pays for the ship. |
| **Tech-grade material** | Drone dives into red rocks (and rare salvage) | Spend an expensive drone on this rock? |

This is already the cost structure in `UPGRADE_TREE` / `UPGRADE_MATERIALS`; the
plan makes each part visible and taught rather than changing it.

### 3.2 Banking ore: make it a real choice, not a hidden button

- At the station trade panel, ore gets two buttons side by side:
  **Sell (N credits)** and **Bank for upgrades (ore bank: X / max)**. The
  label shows what each choice is worth right now.
- When an **upgrade goal** is set (3.3) and the bank is short of it, **Bank**
  is the highlighted default, and N.O.V.A. says so the first time ("Keep the
  ore. The mechanic takes it as payment.").
- The ore bank is one account, usable at any station (as now). Cargo upgrades
  raise its capacity (as now), which gives cargo upgrades a second purpose.

### 3.3 The upgrade goal: one thing to work towards, always on screen

The single most important new piece of UI.

- The player **sets a goal** from the upgrade screen (`Set as goal` on any
  tier). If they haven't set one, the game sets the cheapest upgrade that
  reaches the next gate class, and says so.
- A small **HUD goal card** shows the goal and three progress bars:
  credits `640 / 900`, ore `120 / 200`, material `rad-quartz 1 / 2`, plus
  the gate it opens (`→ Class III gates`).
- Each bar says where to get the rest when hovered or empty: "Mine any ore,
  bank it at a station", "A red rock: target it, press G".
- When every bar is full, the card turns gold: **"Ready: dock and fit it"**.
  Docking opens the upgrade screen on that item.

This one card connects the Moment loop (mining, jobs) to the Rung loop
(the next gate) at all times.

### 3.4 The first upgrade, fully guided (extends today's walkthrough)

Today's Shields Mk II walkthrough covers the material only. It becomes a
complete first lesson, each step triggered by the game state, so it can't be
skipped past or done out of order:

1. **Refused at the first Class II gate.** N.O.V.A. explains the requirement,
   sets Shields Mk II as the goal (the HUD card appears), and gives the first
   survey drone as an advance (as now).
2. **Credits and ore.** If either bar is short, she points at the cheapest
   way: "We're short on ore. Any rock will do; bank it next time we dock."
3. **Material.** The red rock and drone steps (as now, plus the new drone-bay
   prompt).
4. **Banking.** First dock with ore aboard while the goal is short: the Bank
   button is highlighted and she explains it once.
5. **Fitting.** Goal ready: docking opens the mechanic on Shields Mk II.
6. **Done.** She grumbles, the gate opens, and the wiki gets "Upgrades and gate
   classes".

Later rungs get **no** walkthrough, only the goal card and one N.O.V.A. line
per new gate class. The first rung teaches; the rest trust the player.

### 3.5 Deeper is richer (the economic pull)

Upgrades must pay for themselves, or the ladder feels like a toll:

- **Ore value rises with depth.** Belts in deeper systems carry rarer, more
  valuable ores (the per-system ore list already exists; weight it by depth).
- **Red rocks are more common deeper** (from ~1% of a field at depth 0 to ~3%
  at depth 10+), so tech-grade materials, the bottleneck, get easier as you
  climb. This keeps later tiers (2-4-8 materials) reachable.
- **Jobs pay more deeper** (board pay scales with depth), and danger rises
  with them (enemy tier scales with depth), so weapons and shields upgrades
  feel necessary, not just required.

### 3.6 Time targets, and how we check them

Targets for a player doing a normal mix of jobs and mining:

| Rung | Target play time to afford it |
|---|---|
| Class II (Shields Mk II, rating 6) | 20-30 min from campaign start |
| Class III (rating 8) | +30-40 min |
| Class IV (rating 11 + keystone) | +45-60 min |
| Class V (rating 15) | +60-75 min |
| Class VI (rating 20) | +75-90 min |

We don't guess these. A headless **economy simulation smoke test**
(`--economy-sim`) plays an automated captain (mine the nearest belt, take the
best-paying board job, bank vs sell by the goal rule, buy the goal upgrade)
and prints the simulated minutes to each rung. Tuning the tables happens
against that report and then against Abe's playtests.

---

## 4. Pillar C: the pull outward (the Season loop)

### 4.1 The Lodestar: one thing out there, new each campaign

At campaign start the game draws a **Lodestar** from an authored deck: one
specific place at the edge of the map (a Class VI system, depth 13+) that this
campaign is about reaching. The player doesn't learn what it is at the start;
they learn **that it exists and roughly which way**, and every gate class they
climb brings them a step closer and tells them more.

A Lodestar card defines:

- **What it is** (for the director) and the **first hint** (for the player).
- **Five bearings**: what the player learns at each gate class, as a short
  authored line plus N.O.V.A.'s reaction.
- **Where bearings can be found**: which activities may carry one (receiver
  recordings, drone flight recorders, anomalies, investigation results,
  Kaelen's leads). This is what ties every activity to the long goal.
- **The arrival**: a hand-made set piece in the Lodestar system that resolves
  this season, and which loose ends it connects to.

Deck (first six, all original):

| Lodestar | First hint | What's there |
|---|---|---|
| The Lighthouse | A distress beacon on a loop, older than any gate charts | A station that has been broadcasting for two hundred years, and who is still keeping it running |
| The Silent Fleet | Ships reported missing all head the same way | Where the fleet went, and why they stopped transmitting |
| The Humming Gate | Gate techs whisper about a ring that still works perfectly | An intact ancient gate, and who wants control of it |
| The Cartographer's Chart | A dead surveyor's chart with one system circled | What the surveyor found, and who erased it from the registry |
| The Garden | Ice haulers swear there's a green world past the dark | A living world where none should be |
| The Wreck Field | Salvagers' rumours of a battle nobody remembers | Whose war it was, and what they were guarding |

Each draw is checked against the campaign's premise and Hidden Hand so the
Lodestar and the main story can share threads (a bearing can also be a loose
end). **The fixed-cast secret stays out of every Lodestar** (director-only, as
the vision doc sets out); the deck is reviewed against that before shipping.

### 4.2 Bearings: how the pull gets sharper

- The **star map** shows the Lodestar as a faint wedge at the edge of the
  known map. Each bearing narrows the wedge, until the last one marks the
  system itself.
- One bearing becomes **available per gate class** reached. It is placed in
  an activity in a system of that class: the player meets it through play
  they were already doing, not through a fetch quest.
- N.O.V.A. reacts to every bearing, and the wiki-style **Lodestar log** (a
  tab on the loose ends board) keeps what has been learned.
- Bearings can't be missed for good: if the player passes one by, it comes
  back as a rumour or one of Kaelen's leads in the next system of that class.

### 4.3 Short-range pulls: a reason to try every next gate

The Lodestar is the long pull. Each new system also needs a small one:

- **A teaser on the map.** When a gate is revealed, the star map shows one
  true thing about its system before you go: its richest ore, its quirk, or
  "a strong signal". (Built from data the generator already has.)
- **Survey data pays.** The first visit to a system, and each anomaly scanned
  there, gives **survey data** that Kaelen buys. Exploring is income, not
  only cost.
- **Firsts.** The first time the player sees a new kind of system (nebula,
  dead system, dying star), N.O.V.A. reacts and the wiki adds it.

### 4.4 Three horizons, always visible

At any moment the player can see:

1. **Now**: the current job or lead (quest tracker, top right, as today).
2. **Next**: the upgrade goal and the gate class it opens (the HUD goal card).
3. **Far**: the Lodestar wedge on the star map and its last bearing.

If any of these three is empty, the game fills it: no job → N.O.V.A. points at
the board or a rumour; no goal → the cheapest next-class upgrade is suggested;
the Lodestar is always there.

### 4.5 After the Lodestar (open-ended campaigns)

Campaigns are open-ended (Abe, 2026-09-23). Reaching the Lodestar resolves the
season: the Showrunner's season-end pass picks the leftover threads, and a new
Lodestar is drawn further out (depth 20+, with Class VII+ gates and Mk V
tiers). The ladder and the pull start again, one level up.

---

## 5. What changes from campaign to campaign

| Layer | Drawn per campaign | Effect on the loop |
|---|---|---|
| Lodestar | 1 of the deck | What the long pull is about; where bearings hide |
| Keystone | 1 of 5 | Which upgrade deep space demands (Class IV) |
| Premise + Hidden Hand | (exists) | The main story the bearings and loose ends weave into |
| Galaxy | (exists, generated) | Which ores, quirks and factions each depth holds |

Same ladder, same rules, different reasons to climb and a different place at
the top.

---

## 6. Build order

Each bite ends with tests passing and a playtest check in
`docs/playtest_todo.md`. **Stop-and-show** points are where Abe should play
before the next bite.

| # | Bite | Tests |
|---|---|---|
| 1 | Gate class table + Ship Rating; `GateRatingGuide` becomes depth-based (Class II keeps Shields Mk II); old saves keep visited systems | Unit tests: class per depth, block reasons, never-stranded rule |
| 2 | Class shown before it matters: star map tooltip, gate label on approach, HUD `Ship Rating N · next class M` | Jump smoke checks labels |
| 3 | **Upgrade goal**: model, HUD goal card with three bars and "where to get it", `Set as goal`, auto-goal | New `--goal-smoke-test` |
| | **Stop and show: the goal card** | |
| 4 | Ore: **Sell / Bank** side by side, Bank highlighted when the goal is short | Services smoke |
| 5 | First rung fully guided (steps 1-6 in 3.4) + wiki "Upgrades and gate classes" | Walkthrough unit tests; first-session smoke extended |
| | **Stop and show: the whole first rung, from refusal to fitted** | |
| 6 | Depth scaling: ore value, red-rock share, board pay, enemy tier | Economy smoke |
| 7 | `--economy-sim` automated captain + first tuning pass against 3.6 | Prints minutes per rung |
| 8 | Keystone deck, draw, Class IV rule, early hints | Unit tests per keystone |
| 9 | Lodestar deck (JSON, 6 cards), draw, star map wedge | Unit tests; map snapshot |
| 10 | Bearings in activities (receiver, drone recorder, anomaly, investigation, Kaelen lead), Lodestar log tab | Per-activity tests |
| | **Stop and show: the Lodestar wedge and first two bearings** | |
| 11 | Short pulls: map teasers, survey data sale, firsts | Jump smoke |
| 12 | First Lodestar arrival set piece + season rollover | Smoke on a debug-jumped save |

Bites 1-5 are the foundation (one rung, taught well) and should land first;
the Lodestar (8-12) builds on a ladder that already works.

---

## 7. Decisions for Abe

1. **Ship Rating (sum of tiers) instead of one specific upgrade per gate?**
   Recommended: yes, plus the Class II tutorial requirement and the keystone.
2. **Strict gates, or risky passage?** Option: an under-rated ship may force a
   gate and arrive with heavy hull damage. Recommended: strict (clearer, and
   the ladder stays meaningful); revisit later as an upgrade or a story beat.
3. **The Lodestar deck.** Approve the six above, swap any, or write your own.
   Each must also be checked against the fixed-cast canon before it ships.
4. **Refunds.** Refunding an upgrade can drop the rating below the current
   class. Recommended: allowed; it only blocks going deeper, never coming
   back.
5. **After rating 25.** Fully upgraded ships still need a reason to climb in
   later seasons. Options: Mk VI tiers per season, or rare modules from
   Lodestar arrivals. Not needed until bite 12.
