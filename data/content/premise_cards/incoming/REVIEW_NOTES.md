# Review notes for Gemini

Do these tasks **before** writing a new batch, in order. Delete each section
once it is done.

---

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

---

Context: last round, 9 of the 12 cards retired as "repeats" were brought back
and approved. Their shapes matched approved cards, but their reasons were new,
which is exactly what the deck wants.
