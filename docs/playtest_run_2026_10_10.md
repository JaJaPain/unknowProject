# Playtest run, one sitting (2026-10-10)

One route through a fresh campaign: the tutorial, three jobs in the start
system, an upgrade, the gate, a second system, (upgrade if needed) and a
third system. Each check is placed where it happens on that route, so you
can tick them in order. Newest changes are marked **NEW**.

The full list stays in `docs/playtest_todo.md`; I'll tick items off there
from this run afterwards. Things this route can't reach are listed at the
end.

How to note a finding: just tell me as usual ("playtest rules"), and say the
step number.

---

## 0. Before you start (2 min)

- [x] 0.1 Delete the old saves (title screen, or the campaigns folder) so
      this is a fresh campaign.
- [x] 0.2 Ollama and the voice server running as usual.

## 1. Title screen and loading (5 min)

- [x] 1.1 **Title screen.** The campaign list sits left of centre; the
      empty slots say NEW CAMPAIGN IN THIS SLOT.
- [x] 1.2 **Begin animates into loading.** Press Begin: it animates into the
      loading screen, no jump cut.
- [x] 1.3 **Loading feels alive.** Tips change about every 14 seconds;
      the status moves through "Loading the story..." and doesn't stall at
      35% or 92%.
- [x] 1.4 **NEW Campaign title.** Note the campaign's title (on the loading
      screen or later in SYSTEMS > CAMPAIGNS & SAVES). It should not reuse a
      word from your recent campaigns (no more "ledger").

## 2. The opening (3 min)

- [x] 2.1 **Broken-gate opening.** A torn energy tunnel with shattered ring
      plates streaming past, lightning, violent lurches; no grey slab, no
      rainbow noise. A soft dark vignette at the edges, no mouse cursor.
- [x] 2.2 **No early controls.** Right-drag, clicks, Q/W/E, I, M do nothing
      until "Hold RIGHT MOUSE and drag to look around" shows.
- [x] 2.3 **Exit tumble.** Thrown out tumbling (two turns of roll), settling
      as the system comes into view; the intro drones start orbiting right
      away; no tunnel lines play once you're out.

## 3. The tutorial at Greywake (15 min)

Docking and undocking happen many times today: check these the first time,
then just watch they stay right.

- [x] 3.1 **Tutorial station on top.** Greywake sits at the top of the
      overview (not red); the arrow finds it without scrolling.
- [x] 3.2 **NEW Dock request.** Click Dock: a SYSTEM line "Dock request
      submitted to GREYWAKE..." and, a moment later, Dock Control's reply as
      text only (no voice). Clicking Dock again on the way in doesn't repeat it.
- [x] 3.3 **Docking.** The beam hum is clearly audible; a click when the beam
      takes hold; the overview disappears on the beam; N.O.V.A.'s portrait
      sits on the chat box while she talks. Hold right mouse on the way in:
      the mouse still works in the dock menu.
- [x] 3.4 **N.O.V.A. talks.** She speaks on this first dock.
- [x] 3.5 **Kaelen's starter job** reads in-world (no "fallback", "chapter",
      "packet"); she doesn't call you by part of a faction name.
- [x] 3.6 **Repair choice.** Try to leave damaged without repairing: her
      warning talks about leaving ("you're about to..."), never as if you'd
      already launched. (Then repair or not, your call.)
- [x] 3.7 **NEW Undocking, one click.** Dock Control speaks as the beam
      carries you out; HUD orders are refused ("Dock Control has the
      ship..."); the overview is visible but not clickable; there is NO click
      as the push starts and ONE click when the beam lets go, with "Clear of
      the safety zone. Controls are yours." Opening the inventory during the
      push doesn't bring the dock screen back.
- [x] 3.8 **Starter target line.** Right after undocking, only the tutorial
      line ("I am not sure I am happy about being used to blow someone
      up...") and it starts straight away. No receiver offer during the
      tutorial (T does nothing).
- [x] 3.9 **The fight.** Shots are glowing bolts; your hull hits flash the
      screen edges red; unshielded hits leave scorch marks; target panel shows
      the enemy's hull bar; below a third of its hull it sparks and cracks;
      the enemy calls out over two or three turns; the camera re-orbits each
      turn; no freeze if it vanishes.
- [x] 3.10 **After the fight.** N.O.V.A.'s line matches what happened ("no
      scratch" vs "dented but fine"); the victory sting ducks the music and
      the music comes back as it fades. Wiki gains Combat basics and Evasion.
- [x] 3.11 **Hand in at Kaelen.** Contract pays; music after the payment
      sting comes back without a gap.

## 4. Three jobs in the start system (40 min)

Pick them so you get **one ore job, one pickup, and one of anything else**
(a kill job is fine). Kaelen's route out unlocks after 3 contracts.

### 4a. Between jobs, on the station

- [x] 4.1 **Goal card.** Top right: "SUGGESTED GOAL · Shields Mk II" with
      bars. **NEW** the ore row is named **Silicate** (not "Ore") and its
      tooltip says where to find it.
- [x] 4.2 **The board.** COMBAT tag on kill/drop jobs, not on pickups.
      **NEW** ore jobs name their ore ("35 m3 Ferrite"/"Silicate"), and the
      job text says the same ore, never just "ore".
- [x] 4.3 **Kaelen's desk.** Ask for work: **NEW** no job identical to one
      you just did (same item, same place, same pay). Push for more pay once:
      sometimes it works, sometimes a cocky line and lower pay.
- [x] 4.4 **NEW Rumours.** Visit the lounge a couple of times: no
      "[Soft Warning - Story]" or other "[Title - Source]" tags, and nobody
      says "player", "NPC" or "quest".
- [x] 4.5 **Idle tour (once).** Docked, hands off for 1m30s: the screen
      fades into a slow tour round the station that swings to watch a
      freighter land (smoothly, no flip). Touch anything: straight back.

### 4b. The ore job

- [ ] 4.6 **Fly to a belt.** Fly-to bends round planets and stations, no
      U-turns; stops outside stations and orbits.
- [ ] 4.7 **NEW Scan Composition.** Far from any rock: no Scan button and C
      does nothing. Within 400 m of a rock: the button appears, C pings, the
      bubble grows, the feed lists the ores, the overview names scanned rocks.
- [ ] 4.8 **Mine the job's ore.** Scanning finds it in this system's belts.
      Mine a couple of minutes: N.O.V.A. makes one dry remark about the rocks.
- [ ] 4.9 **Drone bay taught.** Target a rock and fly close: N.O.V.A.
      explains the drones once; "[G] LAUNCH SURVEY DRONE · N aboard". The
      inventory shows a locked RESERVE card (x2).
- [ ] 4.10 **Lasers off.** While mining, press Dock: the lasers stop.
- [ ] 4.11 **NEW Turn it in, then look at the buttons.** Hand in the ore
      job, then go to Sell/Bank: "Sell Ore (N m³...)" and "Bank N m³" show
      what's really left in the hold, not the amount before the hand-in.
      Kaelen never says "Zero ore?".
- [ ] 4.12 **Sell or Bank.** With ore left: Bank is gold with a ★ while the
      goal needs ore; bank it and the goal card's Silicate bar fills.

### 4c. The pickup

- [ ] 4.13 **Where, not who.** The board and tracker name the outpost and
      say someone in its lounge has it.
- [ ] 4.14 **NEW No Kaelen at outposts.** In the outpost's lounge: no Broker
      Kaelen card and no faction agents, only locals.
- [ ] 4.15 **The hunt.** Ask around: wrong people deflect, one names who has
      it, the holder hands it over on the third ask (a drink counts). With
      ore still in the hold, nobody asks you to sell it first.
- [ ] 4.16 **On the way back.** The HUD shows "... m³ + <item>"; N.O.V.A.
      may say something about the job partway home (never at the station).
- [ ] 4.17 **Outposts.** Docking at both outposts (Iron Reach and Kova)
      never clips the structure; freighters use other berths, not yours.

### 4d. Out flying, any time in this section

- [ ] 4.18 **Receiver.** After the tutorial, 30 s of calm flight 1 km+ from
      any station: N.O.V.A. explains the receiver once, a pulsing "[T] TUNE
      RECEIVER" prompt and a SYSTEM line. It hides near stations and with
      hostiles around. Try one: the timer bar drains; a payout banner at the
      end.
- [ ] 4.19 **No job, she helps.** Between jobs, fly ~2.5 min with no job:
      N.O.V.A. suggests something (not again for ~10 min).
- [ ] 4.20 **The comet.** About 5 minutes into the session, a faint comet
      crosses high in the sky.
- [ ] 4.21 **F12.** Take a screenshot (flash + click + SYSTEM line); Esc >
      GALLERY shows it.
- [ ] 4.22 **N.O.V.A. DATABASE** (systems menu): Kaelen, the job givers and
      the pickup holder are there with a line each.

## 5. The first upgrade: Shields Mk II (20 min)

Not strictly needed for the next two gates, but it's the best test of the
new ore costs. Do it here or in system 2.

- [ ] 5.1 **The first red rock.** The DRONE BAY hint says Rad-Quartz. The
      dive is a small rock with two seams close by; it uses the RESERVE
      drones first.
- [ ] 5.2 **Dive controls.** Mouse turns, A/D slide, W/S forward/back; the
      controls box and the haul list ("Rad-Quartz seam 624 nk", shrinking as
      you close in); "E extract" near a seam; the cursor comes back after.
- [ ] 5.3 **Clean dive brings home two;** N.O.V.A. says we got lucky.
- [ ] 5.4 **NEW Upgrade screen.** Maintenance Bay > Ship Upgrades: your ship
      is shown; each option's cost reads like "Cost: 200 CR, 50 Silicate"
      (and Mk III would read "Silicate, Ferrite"); "Set as goal" works.
- [ ] 5.5 **Fit it.** With everything aboard the card turns gold, READY;
      fit it at the mechanic. The rating line updates at once.
- [ ] 5.6 **Kaelen over comms.** Undock after fitting: within a second or two
      Kaelen comes over comms (filtered voice).

## 6. Kaelen's route and the gate (5 min)

- [ ] 6.1 **Route offer.** After 3 contracts, "Ask about new routes" appears
      at Kaelen's desk; buy the route. (Not before 3 contracts.)
- [ ] 6.2 **Target the gate.** Its tag says the class and "· open".
- [ ] 6.3 **Jump.** Wiki gains "Jump gates".

## 7. The second system (25 min)

- [ ] 7.1 **New look.** Its station and outposts wear different models from
      the start system; 2-3 fuller asteroid fields; maybe a faint nebula.
- [ ] 7.2 **Survey and firsts.** A blue SURVEY line says the system is
      charted; if it has a nebula, ion storm, dying star... N.O.V.A. remarks
      on it once.
- [ ] 7.3 **The Destination's first hint.** Undocked and calm: a gold line
      with the Destination's name and rumour, N.O.V.A. reacts ("I've marked
      the rough direction on the star map"); a little later she explains
      "This destination is like a lodestar...". Star map (M): a gold wedge.
      Wiki: "The Lodestar".
- [ ] 7.4 **Star map hover.** Hover systems: each says something ("Scans:
      ...", gate class, green/red).
- [ ] 7.5 **Rumours point to an area** within ~20 s of arriving.
- [ ] 7.6 **NEW Dock request** says this station's name.
- [ ] 7.7 **Kaelen here** has jobs the first time. After dealing with her
      here and undocking: N.O.V.A.: "Why is Kaelen at this station too?..."
      (once).
- [ ] 7.8 **NEW Ore jobs here** name an ore this system's belts carry
      (scan to check), and it can differ from the start system's.
- [ ] 7.9 **Do one job here**, any kind. After your first upgrade, about
      half of pickups get a Reaver Hijacker on your tail on the way back.
- [ ] 7.10 **Finds.** If an anomaly shows on the overview: it's a surprise
      until you're near. A "Distress Beacon" is a whole dead ship seen from
      ~3 km; Fly to stops outside its hull; drones can dive it.
- [ ] 7.11 **Mining risk (after the upgrade).** Asteroids show their ore on
      the overview; mining next to a faction's hauler gets a claim hail.

## 8. The third system and the wreck field (25 min)

- [ ] 8.1 **Gate to system 3.** If it refuses, the refusal says why and the
      goal card switches to what's needed; upgrade and come back.
- [ ] 8.2 **NEW Hard ore job (if one shows).** In deeper systems, about 1 in
      6 ore jobs asks for an ore these belts lack and names the nearby system
      to mine it in, for double pay. (May not show this early; fine.)
- [ ] 8.3 **NEW Wreck field (dev shortcut).** It normally needs five
      systems visited, so: Numpad 7 > Story tab > **Start the Wreck Field
      Here**. N.O.V.A.: "Two transponders out past the edge..."; "Twin
      wrecks" on the overview.
- [ ] 8.4 **Flying out.** Fly to it: it stops outside a faint green bubble.
      First sight: "Two of them. Broken clean in half...".
- [ ] 8.5 **The radiation.** Nudge inside the bubble: N.O.V.A. warns once, a
      red WARNING line, the hull ticks down. Back out.
- [ ] 8.6 **The scans.** Four cyan scan points round the edge (on the
      overview). Hold still near one for 3 s: "Scanning the bow section...",
      then a WRECK line saying what it found. The first two also give a gold
      "In the logs: ..." line, and N.O.V.A. says she's keeping it.
- [ ] 8.7 **The fourth scan** pays salvage (banner) or a Destination bearing;
      N.O.V.A.: "That's everything the wreck will tell us...". The scanned
      points dim.
- [ ] 8.8 **Dive the hulls** from the bubble's edge with a drone (G): a wreck
      dive listing Salvage.

## 9. Wrap-up (5 min)

- [ ] 9.1 **Retire screen, don't confirm.** SYSTEMS > CAMPAIGNS & SAVES > the
      red END THIS CAMPAIGN area > RETIRE THE CAPTAIN...: its own screen with
      days / stories / credits; letting go of the hold button cancels.
      (Only confirm if you want to see the keepsake.)
- [ ] 9.2 **Campaign title** (from 1.4): still a fresh one.
- [ ] 9.3 Tell me "ending playtest now": I'll check N.O.V.A.'s quiet-moment
      log, tick everything you passed in `docs/playtest_todo.md`, and fix
      what you found.

---

## Not in this run (needs a long campaign or its own test)

- Main story timing (reveal at hours 8-12), losing the proof, the season
  climax, reaching a Destination and its model (the smoke test
  `--lodestar-smoke-test --lodestar-snapshot` pictures them all).
- Class III gates, the keystone rumour and reveal, deeper bearings.
- Death and the eulogy (die on purpose in a later run).
- Imported ore premium, Kaelen's one-job ledger, N.O.V.A. getting restless.
