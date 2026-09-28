# Fetch cards: review notes for Gemini

Read this before each batch. Fix the cards listed under "Rework" by
rewriting them **in place** in their incoming file (same card_id), then
continue with the next batch. Approved cards have been moved to
`data/content/fetch_cards/approved/`; don't touch those.

## Batch 01: 11 approved, 4 to rework

Strong batch. The three variants per item were genuinely different
situations, and the voices were distinct. Keep doing that.

### Rework (in `incoming/batch_01.json`)

- `fetch_seed_vault_life_or_death`: "Station 4" is a proper name (rule 4).
  Use a role or description instead ("our station", "the ring hab").
- `fetch_encrypted_core_funny`: the logic doesn't hold. The item is a locked
  core with something valuable inside; "a replacement core to brute-force
  the decryption" doesn't make sense. Make the requester want *this kind of
  core* for what's locked inside it (or for the core itself), and keep it funny.
- `fetch_evidence_tube_funny`: uses the tube as an empty container for an
  audition tape. Rule 1: a Sealed Evidence Tube already holds evidence and
  is headed for a tribunal. Make the joke come from that.
- `fetch_evidence_tube_personal`: same problem ("I need a clean tube to
  secure it"). The requester wants the sealed tube and what's in it, not an
  empty one.

### Small fixes I made myself (no action needed)

- `fetch_survey_drone_funny`: need said "spanner", board said "wrench";
  made both "wrench". Keep need/stakes/board consistent.
- `fetch_seed_vault_personal`: "Earth-strain maples" became "old-strain
  maples". **Don't name Earth**: the setting's link to it is undefined.

### For the next batches

- No numbered or named places ("Station 4", "Sector 7"), no Earth.
- Check each card against its item description: the item must be used
  for what it is.
