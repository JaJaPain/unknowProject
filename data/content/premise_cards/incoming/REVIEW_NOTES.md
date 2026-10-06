# Review notes for Gemini

Do these tasks **before** writing a new batch, in order. Delete each section
once it is done.

---

## 0. New brief section: "Where players read your words" (Section 5)

Players now read `public_situation`, resolution `summary` and loose thread
`detail` on screen, on their own, long after the story. Read that section
before writing; the validator now warns on summaries over 220 characters,
summaries that read like notes, and thread details outside 50-170 characters
or that mention the pilot. Also new there: lean loose threads toward the four
thin methods (`debt_leverage`, `cornering_a_market`, `impersonation`,
`slow_infiltration`) where a story honestly allows it. Delete this section
once read.

## 1. New field: `core_why` (read Section 5 and "the why test" in Section 7)

Every card now needs `core_why: {"motive": ..., "secret": ...}`: the specific
reason the story exists. Similar shapes may repeat across the deck; the reason
must not. The validator requires it on new cards, and the deck report lists
every secret already used.

## 2. One-time task: backfill `core_why` for the approved deck

**Do not edit anything in `approved/`.** Instead:
1. Read every card in `data/content/premise_cards/approved/`.
2. Write `data/content/premise_cards/core_why_backfill.json`: one JSON object
   mapping each card id to `{"motive": ..., "secret": ...}`, for all approved
   cards. Use each card's `private_truth` to find its real reason.
3. Make each `secret` specific to that card. If two cards really do share the
   same underlying reason, give them the same secret; don't disguise it. That
   tells the reviewer where the deck repeats itself.
4. Check your file from disk: valid JSON, one entry per approved card.

## 3. premise.the_fractured_vow (batch_27)
- Add its `core_why`.
- Beat 3's comms_reversal: the offer comes from the collector "from the station", not from aboard the target ship. Make the offer come from someone aboard the ship the pilot is attacking.

## 4. One-time task: rewrite private facts that narrate the pilot

Read rule 8 in Section 3 again: a `private_fact` is **a hidden truth about a
person in the story, in the present tense**. The game can now reveal it
mid-job, read aloud by the ship's companion ("Here's what they left out:
..."), so it must make sense on its own and never narrate what the pilot
does, finds or must decide. The validator now warns on these.

**Do not edit anything in `approved/`.** Instead write
`data/content/premise_cards/private_fact_rewrites.json`: a JSON array of
`{"card": <id>, "beat": <n>, "mission": <index in that beat>, "private_fact": <new text>}`,
one entry for each fact below. Keep each story's meaning; say what the
requester or someone they cover for is hiding, at least 45 characters.
`python tools/premise_cards/apply_private_fact_rewrites.py --check` must
report 0 problems before you hand it back.

- `premise.forged_valor` beat 2 mission 0 (investigate_signal): "The pilot must choose whether to certify the true reactor failure, or falsify the report to say it was combat damage as the association claims."
- `premise.the_abandoned_colony` beat 1 mission 0 (investigate_signal): "The pilot discovers the survivor sitting calmly at a desk in the center of the ruins."
- `premise.the_black_hole_tithe` beat 1 mission 0 (investigate_signal): "The pilot's ship will suffer minor hull stress just getting close enough to scan."
- `premise.the_broken_oath` beat 2 mission 0 (investigate_signal): "The pilot finds the guard desperately trying to jump out of the system."
- `premise.the_censored_history` beat 1 mission 0 (investigate_signal): "The pilot discovers the historian desperately trying to bring the ancient satellite's power grid online."
- `premise.the_collapsing_mine` beat 2 mission 0 (investigate_signal): "The pilot's deep scan reveals the rock's core is fracturing and will collapse in less than a day."
- `premise.the_defector_bounty` beat 1 mission 0 (investigate_signal): "The pilot discovers the defector hiding in a shielded cargo container."
- `premise.the_doomed_affair` beat 2 mission 0 (investigate_signal): "The pilot's scan accidentally pings the hideout, alerting the mercenaries to their location."
- `premise.the_double_agent` beat 1 mission 1 (pickup_special): "The pilot has to bypass three layers of lethal biometric security to get the drive."
- `premise.the_dying_star_archive` beat 2 mission 0 (pickup_special): "The pilot's ship will suffer intense heat damage during the extraction."
- `premise.the_empty_casket` beat 1 mission 0 (investigate_signal): "The pilot's scan reveals the casket contains nothing but bags of sand."
- `premise.the_fake_news_drone` beat 2 mission 0 (investigate_signal): "The pilot discovers the reporter is controlling the drone from the station's cafeteria."
- `premise.the_hermit_hoard` beat 1 mission 0 (pickup_special): "The pilot discovers the mug is sitting right next to the glowing colonial reactor."
- `premise.the_manufactured_hero` beat 2 mission 0 (pickup_special): "The pilot has to dodge automated pyrotechnics to reach the script."
- `premise.the_mutiny_in_the_dark` beat 1 mission 0 (investigate_signal): "The pilot discovers the freighter is actively venting oxygen to conserve power."
- `premise.the_mutiny_in_the_dark` beat 2 mission 0 (delivery_courier): "The pilot realizes the captain is planning to sell the crew to slavers."
- `premise.the_pacifist_mercenary` beat 1 mission 0 (pickup_special): "The hero insists the pilot must not harm the protege under any circumstances."
- `premise.the_phantom_fleet` beat 1 mission 0 (purchase_delivery): "The pilot realizes the colony is completely unarmed."
- `premise.the_phantom_fleet` beat 2 mission 0 (investigate_signal): "The pilot must fake the scan results to hide the fact that the heavy cruisers produce zero heat."
- `premise.the_phantom_manifest` beat 2 mission 0 (investigate_signal): "The pilot must get dangerously close to the auditor to do this."
- `premise.the_runaway_bride` beat 1 mission 0 (purchase_delivery): "The pilot realizes the tags are military-grade target painters."
- `premise.the_runaway_bride` beat 2 mission 0 (investigate_signal): "The pilot finds the bride hiding inside a massive hollow ice sculpture."
- `premise.the_smear_campaign` beat 2 mission 0 (delivery_courier): "The pilot realizes the backup drive contains the exact same fabricated data."
- `premise.the_space_madness` beat 2 mission 0 (investigate_signal): "The pilot realizes the engineer is suffering from severe nitrogen narcosis."
- `premise.the_stolen_bloodline` beat 3 mission 0 (delivery_courier): "The pilot now holds the drive and knows exactly what it contains."
- `premise.the_stolen_thesis` beat 3 mission 0 (delivery_courier): "If the pilot does this, the journalist will become famous but the pilot will make no money."
- `premise.the_stowaway_assassin` beat 1 mission 0 (purchase_delivery): "The pilot realizes the killer is systematically murdering anyone who gets in their way."
- `premise.the_stowaway_assassin` beat 2 mission 0 (investigate_signal): "The pilot must fake the scan results to throw the killer off the scent."
- `premise.the_toxic_spill` beat 2 mission 0 (investigate_signal): "The pilot's scan reveals the mold is highly corrosive and spreading fast."
- `premise.the_whistleblower_cache` beat 1 mission 0 (investigate_signal): "The pilot realizes the fixer's gunship is waiting directly above the vault."
- `premise.the_whistleblower_cache` beat 2 mission 0 (delivery_courier): "The pilot discovers the leaker is trapped inside the vault."

## 5. One-time task: name the culprit on approved investigations

`investigate_signal` missions may now name a `culprit` (Section 5, beats):
the role whose wrongdoing the evidence exposes. When the pilot turns it up,
the game gives them leverage over that role. In the same file, add entries
`{"card": <id>, "beat": <n>, "mission": <index>, "culprit": <role id>}` for
approved investigations whose evidence really does expose a person or
faction role in that card. Skip the ones where it exposes nobody; that is
fine. The `--check` run validates the role ids.

---

Context: last round, 9 of the 12 cards retired as "repeats" were brought back
and approved. Their shapes matched approved cards, but their reasons were new,
which is exactly what the deck wants.
