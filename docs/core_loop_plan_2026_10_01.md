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
| VI | 13-15 | Ship Rating 20 | The edge of the known map. Where the first Lodestar lives (Section 4). |
| VII+ | 16+ | by formula (2.3a) | Beyond the charts. |

### 2.2 Ship Rating, not one fixed upgrade per gate

**Ship Rating = the sum of the five systems' tiers** (weapons, engine,
shields, mining, cargo), **where each system counts for at most two tiers
above your weakest system** (Abe, 2026-10-01: one upgrade path alone must not
be able to carry the ship forward). A stock ship is 5.

Example: Shields Mk V with everything else stock rates 3+1+1+1+1 = **7**, not
9. Upgrading cargo to Mk II lifts the cap to Mk IV, and the rating to 9.

The HUD says what's holding the rating back: `Ship Rating 7 · Cargo Mk I is
your weakest system: upgrades above Mk III don't count until it improves.`
The rule needs no table, works for any number of tiers (2.5), and keeps every
system in play for the whole campaign.

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

### 2.3a Never fully upgraded: endless tiers and classes (Abe, 2026-10-01)

The campaign is a never-ending story while the Captain lives, so there is no
top tier and no last gate class:

- **Tiers past Mk V are generated**: each new tier adds a fixed step to its
  branch's stats and costs more (credits, ore or alloys, materials) on a
  steady curve. Mk VI, VII and onward exist as soon as the player can afford
  them.
- **Gate classes continue past VI** by formula (each class needs a little more
  rating than the last, at greater depth), so there is always a next class.
- The breadth rule (2.2) keeps all five systems climbing together.
- The tables in 2.1 and `UPGRADE_TREE` cover the hand-tuned early game; the
  formulas take over after them, tuned with the economy simulation.

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

- **Back is always open; forward always checks** (Abe, 2026-10-01). A gate
  leading to a shallower or equally deep system is always open. A gate
  leading deeper checks the requirement every time, even into a system
  visited before (so a ship whose rating drops, for example by a refund, can
  retreat but must earn its way forward again).
- **Visible before it matters.** A gate shows its class and requirement when
  revealed (star map tooltip, gate label on approach), not only when refused.
- **Refusal teaches.** Trying a gate you can't use opens the same guidance as
  today's walkthrough, but for whichever requirement is missing, with the cost
  breakdown (Section 3.3).
- **No penalty for exploring sideways.** Lateral gates within the same class
  are always open. The ladder only gates going deeper.
- **Old saves.** The rules apply from the save's current position: going back
  is open, going deeper checks.

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

### 3.7 Risk follows reward: the combat cost of mining (Abe, 2026-10-01)

The rarer the ore, the more it costs to take, in a fight. Common ore stays a
calm activity; rare ore and tech-grade materials are contested. This also
gives miners a reason to upgrade weapons and shields, not just fighters.

| What you mine | Combat cost | How it's telegraphed |
|---|---|---|
| **Common ore** (silicate, water ice, ferrite) in open space | None | (calm) |
| **Common ore inside a claim** | The claim's miners call reinforcements | A claim label on the belt; their hail first |
| **Rare ore** (thorium, and the rarer ores deeper out) | One ship comes for you, and for the ore | N.O.V.A. hears it coming, with time to choose |
| **Red rocks** (tech-grade materials) | Sometimes a ship is already there, waiting | Visible on the overview before you get close |

**Claims (common ore).**

- Some belts, or parts of them, are **claimed** by a local faction's mining
  crews (the faction ships that already fly in each system). The overview and
  the belt's label show it: `Ferrite belt · Zenith claim`.
- Start mining inside a claim while their miners are working it and you're
  **hailed first**: "This is a Zenith claim. Move off." That is a 20-second
  grace.
- Keep mining and they **call reinforcements**: one or two escorts arrive
  (fewer and weaker in shallow systems). Leave the claim and nothing happens.
  Trespassing costs standing with that faction; a fight costs more.
- **Never trapped for fuel:** in every system, the water ice nearest each
  station is unclaimed open space. The fuel loop's "never stranded" rule
  outranks claims.

**Rare ore: the claim jumper.**

- Mining rare ore puts out a signature. After a short delay, **one ship**
  comes for you and the ore (a raider, a rival prospector, a local enforcer,
  depending on the system's factions).
- N.O.V.A. warns with time to act: "Someone's picked up the thorium. One
  ship, inbound, about forty seconds." The player can keep cutting, leave
  with what they have, or set up for the fight.
- The attacker is **one ship, scaled to the system's depth, not to the
  player**, so upgrades make these fights easier, which is the point of
  upgrading.
- Beating it pays: its hold has some of the same ore, a bounty, and the
  existing rare chance of an intact survey drone.

**Red rocks: the guard.**

- A red rock may have a ship **already parked beside it**, waiting. It shows
  on the overview from a distance, and N.O.V.A. calls it out when the rock is
  targeted: "There's a ship sitting on that rock. It hasn't moved. It's
  waiting."
- The guard engages when you come within range of the rock. Players can scout
  first, pick a different rock, or come back stronger.
- Guard chance scales with depth (about 30% in Class I-II systems, rising to
  about 70% deep). **The campaign's first red rock (the tutorial rung) is
  never guarded**: one new thing at a time.

**Fairness rules.**

- Every combat cost is telegraphed before it starts (a label, a hail, a
  warning), and there's always a way to back out.
- One attacker at a time for rare ore and red rocks; only claims escalate,
  and only if the player stays.
- **Late game: mining rights.** In later systems, a claim owner sells the
  rights to some mid-grade minerals in its claims (Abe), so grinding ore for
  the big upgrades doesn't mean a fight every trip. Rare ore and red rocks are
  never for sale.
- No combat cost appears before the first upgrade is fitted (the first
  ~30 minutes are for learning the loop).
- The economy simulation (3.6) counts the fight time and the repair bills,
  so rung times include the risk.

### 3.8 End game: alloys (direction, Abe 2026-10-01; designed later)

Past the mid tiers, upgrades stop taking raw ore and need **alloys**: made by
combining different ores at a **dedicated facility** (a foundry), not at
every station.

- **Recipes combine ores** (for example a common base ore, a rarer ore and a
  tech-grade material in set ratios), so the player has to gather a mix, which
  sends them to different belts, depths and claims.
- **Foundries are rare places** (one in some deep systems, or at a Lodestar),
  so reaching one is itself a goal on the map.
- **Where it slots in:** Mk IV-V tiers, and the post-rating-25 seasons
  (decision 7), replace their raw-ore cost with alloys.
- Not part of bites 1-12. It gets its own short plan once the ladder and the
  goal card have been played.

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
tiers). The ladder and the pull start again, one level up, with no end
(2.3a).

### 4.6 The second push: N.O.V.A. and Kaelen want you further out (Abe, 2026-10-01)

The push forward comes in **two parts**:

1. **The Lodestar** (4.1): the *explained* pull. A mystery the player chooses
   to chase.
2. **The undercurrent**: the *unexplained* one. N.O.V.A. and Kaelen both keep
   nudging the Captain deeper, constantly and lightly, for reasons that are
   never given.

The reason belongs to the fixed-cast canon, which is director-only: it is not
written here, never goes into a prompt, and never appears in player-visible
text. This section covers only what the player sees and hears.

**N.O.V.A.**

- Uneasy when the ship lingers in systems shallower than the deepest it has
  reached: "We've been here a while. I don't like standing still." Calmer, even
  curious, the deeper they go, though she still hates the gates themselves.
- When a new gate class opens: a line that sounds a little like relief.
- If the Captain asks why (in a conversation that touches it), she deflects
  or doesn't know herself. She never explains, and **she never gives orders**
  (her register forbids it): the nudge is a feeling she voices, not an
  instruction.

**Kaelen**

- Her leads always point deeper. She is quicker and cheaper with gate reveals
  that go outward, and pays more for survey data from the deep.
- After an upgrade is fitted: "Good. Now go." Back in a shallow system for too
  long: "You don't belong back here, Shiny."
- Never says why. Changes the subject like a broker closing a deal.

**Rules**

- **Authored lines only**, no model generation, so nothing about the reason
  can leak through a prompt. Abe reviews every line against the canon before
  it ships.
- **Light and rate-limited**: at most one nudge from each of them per system
  visit, more often only when the player has been sitting shallow for a long
  time. It must read as character, not as a quest marker.
- **They never contradict each other**, and neither is ever shown the other's
  nudges in dialogue: the player is the only one who notices both are doing it.
- The nudges are a hint tier of the undercurrent (vision doc Section 5.4):
  they add to the mystery, they never resolve it.

---

## 5. What changes from campaign to campaign

| Layer | Drawn per campaign | Effect on the loop |
|---|---|---|
| Lodestar | 1 of the deck | What the long pull is about; where bearings hide |
| Undercurrent nudge | (constant) | N.O.V.A. and Kaelen keep pushing outward, never saying why |
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
| 6b | Mining risk (3.7): claims with hail and reinforcements, rare-ore claim jumper, red-rock guards; ice near stations always unclaimed; none before the first upgrade | Unit tests per rule; a `--mining-risk-smoke-test` that triggers each one |
| 7 | `--economy-sim` automated captain + first tuning pass against 3.6 | Prints minutes per rung |
| 8 | Keystone deck, draw, Class IV rule, early hints | Unit tests per keystone |
| 9 | Lodestar deck (JSON, 6 cards), draw, star map wedge | Unit tests; map snapshot |
| 10 | Bearings in activities (receiver, drone recorder, anomaly, investigation, Kaelen lead), Lodestar log tab | Per-activity tests |
| | **Stop and show: the Lodestar wedge and first two bearings** | |
| 11 | Short pulls: map teasers, survey data sale, firsts | Jump smoke |
| 11b | Undercurrent nudge (4.6): authored N.O.V.A. and Kaelen pools, triggers (lingering shallow, class opened, upgrade fitted), rate limits, Kaelen's deeper-lead pricing. **Abe reviews the lines against the canon first.** | Unit tests for triggers and limits |
| 12 | First Lodestar arrival set piece + season rollover | Smoke on a debug-jumped save |

Bites 1-5 are the foundation (one rung, taught well) and should land first;
the Lodestar (8-12) builds on a ladder that already works.

---

## 7. Decisions for Abe

1. **Ship Rating?** **ANSWERED (Abe, 2026-10-01): yes**, with the rule that one upgrade path alone can't carry the ship forward (2.2: a system counts up to two tiers above the weakest).
2. **Strict gates, or risky passage?** **ANSWERED (Abe, 2026-10-01): strict**, for now.
3. **The Lodestar deck.** Approve the six above, swap any, or write your own. (Abe, 2026-10-01: the push forward is two parts, the Lodestar plus N.O.V.A. and Kaelen's unexplained nudge, 4.6. Deck still to approve.)
   Each must also be checked against the fixed-cast canon before it ships.
4. **Refunds.** **ANSWERED (Abe, 2026-10-01):** the ship can always fly back, but going deeper again needs the requirement met (2.4).
5. **Rare-ore attacker: every time, or a chance?** **ANSWERED (Abe, 2026-10-01): yes as recommended**: every time for rare ore, after a delay long enough to fill part of a hold; a low chance for uncommon cuprite.
6. **Claims: buy mining rights?** **ANSWERED (Abe, 2026-10-01): yes, late game**: in later systems, the rights to some **mid-grade** minerals can be bought from the claim owner, to cut the annoyance of mining for the larger upgrades. Not for rare ore or red rocks.
7. **End game.** **ANSWERED (Abe, 2026-10-01):** never fully upgraded; tiers and gate classes continue procedurally, a never-ending story (2.3a). And: end-game progression needs **alloys** made by combining different ores, not raw ore, made at a dedicated facility. See 3.8.
