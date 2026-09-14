# Quest Generation Test Results
_Audit date: 2026-06-21_
_Harness: `scenes/test_quest_gen.tscn` (`scripts/test_quest_gen.gd`), 20 iterations_
_Model: Ollama `qwen2.5:3b-instruct-q4_K_M`, best-of-3 candidate selection_

This is a notes-only pass per the `ClaudeWork.md` queue item
("Re-run the quest-gen test scene manually and save only the summary plus the
worst 3 examples"). **No generation code was changed.**

---

## 0. Harness bug found and fixed (blocking)

The test was **completely non-functional** before this run. A scope error in
`_print_summary()` — `for issue in sorted_issues:` sat outside the `if not
issue_counts.is_empty():` block where `sorted_issues` was declared — failed the
whole script parse:

```
SCRIPT ERROR: Parse Error: Identifier "sorted_issues" not declared in the current scope.
   at: GDScript::reload (res://scripts/test_quest_gen.gd:190)
ERROR: Failed to load script "res://scripts/test_quest_gen.gd" with error "Parse error".
```

Because the script never compiled, zero iterations ran — anyone invoking this
test previously got only LLM boot logs and no results. Fixed by indenting the
issue-print loop into the `if` block. The numbers below are from the fixed run.

---

## 1. Summary

```
SUMMARY — 20 runs in 214.2s
PASS: 20  |  FAIL: 0  |  FALLBACK: 0

By type:
  KILL_SHIPS       7 generated, 0 failed
  DELIVER_ORE      4 generated, 0 failed
  PICKUP_SPECIAL   9 generated, 0 failed
```

- **20/20 passed** the harness's automated checks (leftover-name detection,
  objective/dialogue consistency, agent-role/subtitle correctness, choice
  dummy-name detection).
- **Zero fallbacks** — every quest came from the live model, none from the
  static templates.
- ~10.7s per quest on average (best-of-3 = 3 model calls each).

---

## 2. Representative examples (no failures, so these are typical output)

### KILL_SHIPS — Aurelia (run #4)
> **LIAISON RYN** — Aurelia Syndicate Trade Liaison
> "Obsidian crew is making noise near one of my routes, Indy. 3 ships. Make them disappear — clean, quiet, off the books."
> Contract: Destroy 3 Obsidian ships | 200 SC
> [3] *The payout isn't worth the risk. Increase it.* → "Playing hardball? I respect the hustle, Indy. Payout bumped. But rivals will be watching."

### DELIVER_ORE — Zenith (run #1)
> **DIRECTOR VOSS** — Zenith Corporate Acquisitions Director
> "Our fabrication queue is stalled pending raw material, Indy. 25 m³ of ore. Acquire and deliver without delay."
> Contract: Deliver 25 m³ ore | 160 SC
> [2] *I need a credit advance first.* → "An advance for fuel costs. Logged, Indy. Expect contested mining lanes on approach."

### PICKUP_SPECIAL — Vanguard (run #2)
> **CAPTAIN DASK** — Vanguard Military Contract Officer
> "We have a retrieval op, Indy. Oleg Stroud at Outpost Iron Reach is holding a Suspension Pod. Secure it and bring it back."
> Contract: Pick up Suspension Pod from Oleg Stroud at Outpost Iron Reach | 250 SC
> [1] *I'll take the job.* → "Acknowledged, Indy. Retrieve the item and return without incident."

Voice separation across factions is good: Voss is clipped/corporate, Ryn is
slick/grey-market, Dask is military-terse. NPC names, outpost names, and item
names all flow correctly into the dialogue.

---

## 3. Observations (quality, not failures — for a later targeted pass)

1. **Heavy player-name ("Indy") repetition.** Nearly every opening line *and*
   every one of the three choice responses addresses the player as "Indy" — often
   2–3 times within a single quest. It passes the checks but reads unnaturally
   dense. This matches the earlier `ClaudeWork.md` note about repeated "Indy"
   usage after acceptance lines; still present.
2. **Low variety in fixed slots.** Outpost names were only "Iron Reach" and
   "Kova"; DELIVER_ORE was always exactly "25 m³ / 160 SC"; KILL_SHIPS was always
   "3 ships / 200 SC"; PICKUP was always "250 SC". Titles repeated ("Silicate
   Run" ×3, "Clear the Lane" ×3). Reward/quantity rolls may be too narrow.
3. **Choice-response item references stay generic.** PICKUP choice responses say
   "the drive is priority cargo" even when the item is a "Suspension Pod" — the
   harness only validates the *main* dialogue against the item/NPC, not the
   choice responses, so this isn't caught.

None of the above are bugs; they are tone/variety polish for whoever owns the
generation prompts. Logged here, not acted on.
