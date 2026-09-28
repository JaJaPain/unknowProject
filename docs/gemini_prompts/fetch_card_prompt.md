# Fetch-Mission Cards: brief for Gemini

You are writing **fetch-mission cards** for a space trading and combat game.
A fetch mission is a public-board job: *someone needs an item as soon as
possible, because of a reason, and something happens if it doesn't arrive.*
The player finds or buys the item and flies it to them.

## How to work

- Work **5 items at a time** (one batch, below).
- For each batch, write **3 separate lists of 5 cards**, one list per
  variant, each card for one of that batch's 5 items:
  - **List A: `life_or_death`**: real danger, lives or livelihoods on the line.
  - **List B: `funny`**: absurd, petty, or comic stakes, played straight.
  - **List C: `personal`**: quiet, human stakes (a promise, a grudge, a
    reunion, a reputation, a debt).
- That is 15 cards per batch: every item gets one card of each variant.
- Save each batch as **one JSON file**:
  `data/content/fetch_cards/incoming/batch_NN.json` (NN = 01, 02, ...).
- Stop after each batch so it can be checked.

## Card format

```json
{
  "batch": 1,
  "cards": [
    {
      "card_id": "fetch_<item_id>_<variant>",
      "item_id": "<exactly as listed>",
      "variant": "life_or_death | funny | personal",
      "requester": "a role, never a proper name (e.g. 'a hab medic', 'a debt-ridden bar owner')",
      "need": "why they need it now (one sentence)",
      "stakes": "what happens if it doesn't arrive (one sentence)",
      "board_text": "the job as the player reads it on the board, 2-3 sentences, in the requester's own voice",
      "urgency": "hours | days"
    }
  ]
}
```

## Rules

1. Use the item for what its description says it is. Don't change what it does.
2. Every card must be different: no repeated requesters, reasons or
   sentence patterns inside a batch or across batches. No stock phrases
   pasted between cards.
3. The three variants for one item must be three genuinely different
   situations, not the same story in three tones.
4. No proper names of people, ships, stations, factions or systems. Roles only.
5. Everything is original. Nothing from EVE Online, Star Wars, Star Trek,
   The Expanse, Firefly or any other existing setting: no borrowed items,
   terms, groups or places.
6. Rare items (these all are) are hard to find. The requester can say they've
   looked everywhere nearby, but don't say where the item is; the game adds
   that hint.
7. No rewards or credit amounts; the game sets those.
8. **Reserved topics: never use these as a premise, a twist, a thread or a
   background detail:** parallel universes or other dimensions; bringing the
   dead back to life; people who secretly died; androids, robots or synthetic
   bodies passing as human; remote-controlled or proxy bodies; consciousness
   transfer or uploading; time travel or time loops; self-aware or sentient
   machines and AIs (a thinking computer as a character, a requester, a
   worshipped mind, or a question of whether a machine is alive). Plain
   automation is fine: automated freighters, cranes, turrets, ship computers
   doing their jobs. Also reserved: clones or copies of people; the dead
   communicating with the living (ghosts, hauntings, messages from a dead
   person, even if later explained away); and a person represented or
   operated through a stand-in (a hologram of a person, a puppet, an actor
   behind a projection, or a ship or body flown by remote control).
9. Valid JSON only, UTF-8, no comments.

## The items (rarity 3.5 and up), in batches

Format: `item_id | name | rarity | what it is`

### Batch 01
- `survey_drone` | Piloted Survey Drone | 3.5 | A drone you fly yourself into an asteroid's cracks or a wreck to find what's inside.
- `encrypted_core` | Encrypted Data Core | 3.5 | Locked tight. Valuable inside.
- `seed_vault` | Hydroponic Seed Vault | 3.5 | Next season's crops, sealed against vacuum.
- `evidence_tube` | Sealed Evidence Tube | 3.5 | Tamper tape on both ends. Someone wants this in front of a tribunal.
- `gate_idol` | Gate-Cult Idol | 3.5 | A small shrine to the jump gates, worn smooth by hands.

### Batch 02
- `burned_serial_crate` | Weapon Crate, Serials Burned | 3.5 | Whatever's inside, nobody wants it traced.
- `music_box` | Heirloom Music Box | 3.5 | It still plays. Barely.
- `ships_bell` | Derelict Ship's Bell | 3.5 | Salvaged from a wreck. Crews used to ring these for the dead.
- `dead_drop_cache` | Dead-Drop Cache | 3.5 | A small box made to be hidden and found by one person.
- `thermal_lattice` | Thermal Lattice | 4 | Heat-shedding crystal lattice for parts that sit beside a power plant.

### Batch 03
- `rad_quartz` | Rad-Quartz | 4 | Radiation-hardening quartz for shields, sensors and mining optics.
- `cryo_ferrite` | Cryo-Ferrite | 4 | A metal that keeps its shape from deep cold to full sun; used in holds and frames.
- `antimatter_pod` | Anti-Matter Containment Pod | 4 | Handle with extreme prejudice.
- `stasis_pod` | Portable Stasis Pod | 4 | Keeps something, or someone, exactly as it was (suspended animation, not revival).
- `ballot_cache` | Sealed Ballot Cache | 4 | Votes, locked and counted. For now.

### Batch 04
- `reactor_seed` | Unlicensed Reactor Seed | 4 | The start of a reactor nobody signed off on.
- `wine_crate` | Vintage Wine Crate | 4 | Grown on a world that isn't there any more.
- `diplomatic_pouch` | Diplomatic Pouch | 4 | Sealed, stamped, and not yours to open.
- `star_chart` | Cracked Star Chart | 4 | An old route map, split down the middle. Someone has the other half.
- `targeting_core` | Stolen Targeting Core | 4 | Military grade. The owners will want it back.

### Batch 05
- `biohazard_flask` | Biohazard Flask | 4 | Do not drop. Do not open. Do not ask.
- `quarantine_case` | Quarantine Sample Case | 4 | Samples from a sealed station. Handle with gloves.
- `seal_of_office` | Seal of Office | 4.5 | Whoever holds it gives the orders. In theory.
- `artwork_tube` | Artwork Tube | 4.5 | A rolled canvas someone would kill to hang.
- `terraform_seed` | Terraforming Seed Canister | 4.5 | Microbes that turn dead rock into soil, given a century.

### Batch 06 (2 items; 6 cards)
- `resonant_crystal` | Resonant Crystal | 5 | A crystal that rings when struck, grown only in the deepest, most fragile fields.
- `ancient_slate` | Ancient Data Slate | 5 | Older than the jump gates, if the dating is right. (Keep its contents mundane: records, maps, accounts. Nobody speaks through it.)
