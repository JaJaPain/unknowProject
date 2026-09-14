# Compatible faction desires — 2026-09-12

## Implemented

Continued from Claude's latest `claude_handoff_to_codex_2026_09_12.md`, which
supersedes the older prompt's list of already-completed A–C wiring. This slice
addresses the recorded fuel/manifest failure in the generated source facts.

New `GeneratedDesireConstraints.gd` supplies 32 supported goal/need edges across
the existing 12 goals. Each edge records an explanation of how the need serves
the goal. Six transport impediments each bind their event and possible remedy;
four commercial resource records bind holdings to a matching payment source.
Five additional needs have concrete cargo and mission-intent mappings, including
food stock, recruitment documents and supply/lease agreements.

`GeneratedFactionDesire.build()` draws within these compatible sets and stores
generation version 2 and binding IDs. It no longer combines arbitrary events,
obstacles, payments and remedies. Limits are selected from compatible general
business policies; the private motive avoids asserting an unrelated accident,
double sale or fraudulent claim.

The compiler puts the goal/need explanation into `fact.need`, so the writer can
express the link rather than infer it. Board publication checks versioned desire
bindings and withholds corrupt drafts with issue codes. Unknown generator
versions cannot masquerade as old compatible records.

Unversioned saved desires are explicitly unchecked and remain unchanged. This is
not a migration that rerolls visited systems. Existing accepted jobs never enter
the board publication filter. Kaelen/N.O.V.A. guidance, canon, voices and banks
were not edited.

## Verification

Sixteen regression suites passed sequentially with unique logs, covering:

- 1,000 generated desires, all goals, item bindings and concrete negative cases;
- corrupt goal/need, event/remedy, success and holdings/payment bindings;
- actual board publication rejecting corrupt generated causes;
- compiler preservation of the explicit goal/need explanation;
- store normalization preserving an old contradictory desire without rewriting it;
- causal contracts/lifecycle, writer packets and generation;
- tutorial return, delivery recipient/route, local lounge/docking identities;
- generated NPC routes, outcome callbacks and fixed-cast soul protections;
- critic protocol/qualification guards.

Whole-project compilation: 362 scripts, zero failures. The usual headless
certificate-store, stats-write and some shutdown resource warnings remain.

The existing variety threshold was retained. The initial four impediments gave
58 distinct goal/need/obstacle combinations in the 80-faction variety sample;
the six-impediment catalog passes the existing minimum of 60. This is finite
combinatorial variety, not proof of unique campaigns or natural dialogue.

A board integration fixture previously relied on a random seed supplying a
recovery job in an empty world. It now specifies a coherent evidence/recovery
scenario explicitly, so compatible delivery-only draws do not invalidate what
that test is actually checking. No production availability check was weakened.

## Real writer measurement and remaining work

Ran the existing production-path writer harness with seed 67890, unchanged writer
settings and both isolation flags. Raw report:
`logs/quality_eval/writer_eval_67890_1789256554.json`.

24 slices: 11 accepted, 7 rejected by existing validators, 4 other rejections,
1 parse rejection and 1 quality-gate rejection. All 11 accepted slices retain
`quality_unknown`. Latency p50 675 ms, p95 1081 ms, max 1330 ms on this machine.
This is not a held-out evaluation or an 8GB memory qualification. Changed source
facts and a different seed prevent a controlled before/after quality comparison.

Reading the actual output still finds defects: an accepted witness briefing
claims "the only way" without support; another reply changes a cargo handover
into finding someone to witness loading. Matching source facts is necessary but
does not make a writer reliable. No critic prompt, acceptance threshold, protected
character validator or anchor rule was relaxed to raise the score.

Phase D is not wholly finished. The compatibility catalog does not bind every
mission objective to real holdings, stock, money or people; old relationship
generation still asserts dependencies/shared competition without proving the
underlying trade link. Recovery/combat and ore-funding reasons need real action
bindings. Those are distinct from the fixed joint desire draw.

Next: finish executable action/effect binding while integrating the first two
investigation shapes (Phase E/P2). Claude's branch controller carries a selection
but does not execute its effects; an empty eligibility snapshot still permits
selection. Do not present that as a completed gameplay loop. Then implement the
deduplicated P3 reducer, campaign resolutions, exposure history and remaining
writer/hardware evaluation. Human review remains deferred and semantic criticism
remains diagnostic. The main plan is still in progress.
