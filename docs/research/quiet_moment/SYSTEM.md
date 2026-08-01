# Quiet-Moment System — how it works and how to add a beat

State as of 2026-08-01. Nine beats built and measured; **nothing wired into Godot yet.**
Research log with every positive and negative outcome: `ITERATIONS.md`.

## Shape

```
game event ──► fact packet (code owns, rotated)
                   │
              beat definition  (who / register / valence / demos)
                   │
              qwen3:14b  ~3.0s
                   │
              deterministic checks ──► reject ──► retry (up to 5) ──► silence
                   │
              anatomy correction (N.O.V.A. only, code-appended)
                   │
              line ──► TTS
```

**Code owns everything it can.** That is the single biggest lesson: every diversity or
consistency win came from code, and every attempt to fix those by instructing the model failed.
The model supplies voice; code supplies variety, truth, and structure.

## Current beats

| Beat | Trigger | Clean | Distinct openers |
| --- | --- | --- | --- |
| `kaelen_low_pay_safe` | `quest_completed` + `lower_payout` + `low_risk` | 18/20 | 15/20 |
| `kaelen_high_pay_dangerous` | `quest_completed` + `high_payout` + `known_tough` | 19/20 | — |
| `kaelen_public_board` | `quest_completed` + `public_board` | 20/20 | — |
| `kaelen_abandoned` | `quest_abandoned_details` | 11/12 | 12/12 |
| `nova_post_combat_damaged` | `combat_ended(true)` + low `hull_fraction` | 20/20 | 18/20 |
| `nova_repair_done` | repair/dock completion | 20/20 | 15/20 |
| `nova_long_transit` | `clean_long_transit` (already emitted) | 19/20 | 13/20 |
| `nova_cargo_full` | hold at capacity | 19/20 | 15/20 |
| `nova_rough_arrival` | `rough_arrival` (already emitted) | 12/12 | 7/12 |

Selector on a 24-firing playthrough: **12% silence, 2.2 calls/moment, 0 duplicates.**

## Files

| File | Role |
| --- | --- |
| `beat.py` | beat definition + shared character voice blocks |
| `beats_kaelen.py`, `beats_nova.py` | the beats themselves (data) |
| `demo_pool_v9.py`, `nova_demos.py` | few-shot demo pools, sampled per request |
| `packets.py` | example fact-packet set |
| `selector.py` | runtime gating, retry, recency state |
| `runner.py` | deterministic checks + batch measurement |
| `diagnose.py` | local zero-cost diagnosis of a batch |
| `anatomy.py` | N.O.V.A.'s code-enforced body-word correction |
| `approved.py` | author-approved lines + rejected-with-reason |
| `render_audio.py`, `session_best.py` | TTS listening passes |

## Adding a beat — the recipe

1. **Find the hook.** Not "what happened" but *what does this moment threaten or flatter in
   her?* A beat with no hook produces flat output no matter how good the prompt. Public-board
   work was dead until the hook became "nobody negotiated, which makes her redundant".
2. **Write 12 fact packets.** Same facts, varied **vocabulary and grammar**. Do not let them all
   start the same way — the model mirrors the packet's opening construction.
3. **Write the valence paragraph.** What this means to her, what she must not claim, and *who
   did what* if more than one party is involved. Without it the model borrows valence from
   whichever demo it happened to see.
4. **Run 20** through `runner.py`.
5. **Run `diagnose.py`** on the output. It names the fault and the fix, locally and free.
6. **Apply the named fix and re-run.** Two rounds is typical.

Do **not** try to fix opener repetition, tics, or duplication in the prompt. That is the
selector's job and the prompt cannot beat it.

## Deterministic checks

`packet_echo` · `demo_echo` · `wrong_address` · `generic_praise` (Kaelen) · `invented_number` ·
`too_long` · `assumes_captain_gender` · `multiline` — plus recency gates for openers, phrases
and closers, whose state must persist in the save.

## Integration work still to do

1. **Wire the selector into Godot** with persisted recency state. Freshness dies at the first
   reload without it.
2. **Firing policy.** `ShipBehaviorObserver` already uses a 180s semantic cooldown; quiet
   moments now compete with lounge chatter and mission dialogue. Needs an owner —
   `PlayerInteractionQueue` looks right.
3. **Never during combat.** The fixed-cast bible separates `combat` from `quiet_moment`.
4. **`GenerationDiagnostics`** should log every silence and every rejection reason, per the
   project rule that fallbacks are failures to drive to root cause.
5. **VRAM.** `qwen3:14b` is 9.3GB on a 16GB card, alongside the renderer. Measure under load
   before committing; `qwen3:4b` is the fallback at noticeably blander voice.
6. **Bible updates** the research implies: allow Kaelen's "steer toward better work"
   (`quiet_moment.must_not` currently forbids it), gate `public_board_money_rule` to public-board
   moments, and drop `receipts` from her favored motifs.

## Deliberately excluded

**Gate transit** and **cold boot** are strong beats but collide with the scripted amnesia
flashback and pre-rendered opening audio in `docs/todo.md`. A generated line contradicting
authored story is the one failure a player would actually notice. Hand-write those.
