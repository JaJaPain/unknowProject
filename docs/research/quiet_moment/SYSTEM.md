# Quiet-Moment System — how it works and how to add a beat

State as of 2026-08-02. **Twelve beats** built and measured, and **wired into Godot**.
Live end-to-end run: 22/24 served, 0 duplicates, 22/22 distinct openers.
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
| `nova_long_transit` | `clean_long_transit` (already emitted) | 13/16 | 8/10 second-clause |
| `nova_cargo_full` | hold at capacity | 19/20 | 15/20 |
| `nova_rough_arrival` | `rough_arrival` (already emitted) | 12/12 | 7/12 |
| `nova_hard_burn` | `boost_again_quickly` (already emitted) | 15/16 | 12/16 |
| `kaelen_declined` | `quest_declined_details` | 14/14 | 10/14 |
| `nova_returned_same_station` | `returned_to_same_station` (already emitted) | 13/14 | 13/14 |

**`nova_long_transit` carries two rotating devices** (see `beat_transit.py`): DANGLE, where she
offers him a job and leaves the offer standing, and JEALOUSY, where she recounts somebody else's
hands on her in loaded technical detail. The offer/pullback shape is retired — the retraction
always read as rejection.

**Lead-ins.** `nova_post_combat_damaged`, `nova_rough_arrival` and `nova_long_transit` open with
an authored, rotated factual line ("Enemy vessel is destroyed.", "Docked. Barely.") before the
generated reaction. Without it the reaction sounds unwarranted. `fire_probability` throttles
beats on common triggers — `nova_hard_burn` is 0.25.

Selector, single beat in isolation: **12% silence, 2.2 calls/moment, 0 duplicates.**
Selector across **all beats mixed** (the real case): **0% silence, 1.4 calls/moment, 0
duplicates, 17/17 and 15/15 distinct openers per character.** Interleaving improves coverage,
so single-beat silence figures are a pessimistic bound.

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
| `beat_transit.py` | long transit: two rotating devices + runtime adapter |
| `transit_jealous.py` | the jealousy device's vocabulary (mechanics, tools, parts, mishaps) |
| `playthrough.py` | mixed-beat simulation over all beats |
| `render_audio.py`, `session_best.py` | TTS listening passes |

## Adding a beat — the recipe

1. **Find the hook.** Not "what happened" but *what does this moment threaten or flatter in
   her?* A beat with no hook produces flat output no matter how good the prompt — and when the
   author rejects a whole batch, suspect the hook before the prompt. Public-board work went
   through two wrong hooks before landing on class snobbery: it's beneath both of them, and
   they're slumming.
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

**Whenever a character gets a sharp edge, write down who it points at in the same breath.**
Three separate times a new voice axis overshot into contempt aimed at the player — Kaelen's
mercenary streak, N.O.V.A.'s innuendo, N.O.V.A.'s teasing — and every time the fix was an
aim-constraint, never a reduction in intensity.

**Never put a target line or a distinctive frame in the brief.** The model reproduces both.
Describe the technique instead.

## Deterministic checks

Every one of these came from a defect seen in real output, not from theory.

| Check | Catches |
| --- | --- |
| `packet_echo` | hands the packet's own words back to the player |
| `demo_echo` | reproduces a few-shot demo |
| `brief_echo` | quotes the valence/register prose at us |
| `wrong_address` | Kaelen saying "Captain", N.O.V.A. saying "Shiny" |
| `generic_praise` | "you're good at that" — banned in Kaelen's bible |
| `invented_number` | a quantity the packet never supplied |
| `word_echo` | same content word 3+ times in one line |
| `tts_hyphen_compound` | hyphenated compounds Kokoro renders unreliably |
| `tts_all_caps` / `tts_symbol` / `tts_ellipsis` | other unspeakable constructions |
| `lead_in_echo` | the reaction restates the authored opener it follows |
| `double_address` | "Captain" in both the lead-in and the reaction |
| `too_long`, `assumes_captain_gender`, `multiline`, `no_parse` | basics |

Plus recency gates for openers, phrases and closers. **That state is per CHARACTER, not per
beat**, and must persist in the save — a character repeating herself across two different beats
is just as obvious to the player.

Two bugs in the checks themselves, worth not repeating:
- models emit **U+2019** apostrophes, so ASCII regexes silently miss them — normalise first;
- combining case-sensitive alternatives under one `re.I` made `[A-Z]{2,}` match any two letters
  and flag **55/55** good lines.

## Shipped in Godot

| File | Role |
| --- | --- |
| `data/content/quiet_moment_beats.json` | the beats, generated by `export_beats.py` |
| `scripts/story/QuietMomentChecks.gd` | deterministic screening |
| `scripts/story/QuietMomentBeats.gd` | loading, rotation, prompt assembly |
| `scripts/story/QuietMomentSelector.gd` | recency + persistence |
| `scripts/story/NovaAnatomySlip.gd` | the code-enforced body-word correction |
| `scripts/story/QuietMomentDirector.gd` | cooldown, probability, retry, silence |
| `tests/story/run_quiet_moment_*_tests.gd` | four headless suites |
| `tests/tools/run_quiet_moment_live.gd` | live serial soak across all beats |

`quiet_moment` is registered in `LocalModelGateway` (small_dialogue, 20s) and requested via
`LLMInterface.request_quiet_moment` at **temperature 0.9 / top_p 0.95** — the exact configuration
the research measured. 0.95 was tried live and produced noticeably more erratic lines from an
identical prompt.

Silences are recorded through `GenerationDiagnostics` with their reasons.

## Integration work still to do

1. **Connect the triggers.** The director exposes `try_fire(beat_id)`; nothing calls it yet.
   `ShipBehaviorObserver` already emits `clean_long_transit`, `rough_arrival`,
   `boost_again_quickly` and `returned_to_same_station` with context; `QuestManager` emits the
   completion/decline/abandon signals.
2. **Persist through the save.** `QuietMomentDirector.to_save_dict()` / `load_from_dict()` exist
   but are not called by the save system yet. **Without this the freshness guarantee resets on
   every reload**, which is the whole point of the feature.
3. **Call `reset_for_new_campaign()`** on new-campaign start, or the first hour sounds like a
   continuation of the previous playthrough.
4. **Arbitration.** Quiet moments compete with lounge chatter and mission dialogue.
   `PlayerInteractionQueue` looks like the right owner. The director has its own 180s cooldown
   but does not know about other speakers.
5. **Never during combat.** The fixed-cast bible separates `combat` from `quiet_moment`.
5. **VRAM.** `qwen3:14b` is 9.3GB on a 16GB card, alongside the renderer. Measure under load
   before committing; `qwen3:4b` is the fallback at noticeably blander voice.
6. **Named servicers from game state.** The jealousy device names a mechanic ("Mrs. Kross").
   `transit_jealous.MECHANICS` is a placeholder — draw from the current or last visited system so
   the jealousy names someone the player actually met. That is what makes it *this* campaign
   rather than flavour text.
7. **A real pause needs separate TTS calls.** Kokoro does not audibly honour a spaced `". . ."`;
   the author confirmed by ear. If a beat ever wants a beat of silence, it has to be two
   utterances with a gap inserted between them.
8. **Bible updates** the research implies: allow Kaelen's "steer toward better work"
   (`quiet_moment.must_not` currently forbids it), gate `public_board_money_rule` to public-board
   moments, and drop `receipts` from her favored motifs.

## Deliberately excluded

**Gate transit** and **cold boot** are strong beats but collide with the scripted amnesia
flashback and pre-rendered opening audio in `docs/todo.md`. A generated line contradicting
authored story is the one failure a player would actually notice. Hand-write those.
