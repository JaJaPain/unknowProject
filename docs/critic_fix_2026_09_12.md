# Critic correction and verification — 2026-09-12

## What is fixed

The old completed-answer prompt and the ability to treat its unbound `pass` JSON
as approval are removed. The legacy parser now returns `legacy_review_protocol`
uncertain; it cannot approve cached/example output. Its replacement is the shared
`DialogueCritic` protocol used by the maintained evaluation entry point.

The replacement selects sentence targets in code, retains all target text under a
six-target budget, separates factual support from question relevance, and validates
the complete response schema. It rejects legacy responses, extra fields, malformed
types, invalid evidence IDs, truncation, duplicate/missing responses and stale target
IDs. It has no completed pass example. No question means no relevance model call.

`DialogueQualityGate.decide()` will not trust a semantic verdict without an
independently supplied qualification matching the protocol version and exact
configuration fingerprint. Unqualified passes AND repairs stay `quality_unknown`.
Constant-pass, constant-repair, constant-unknown, insufficient or duplicate samples,
false passes and excessive false rejections disqualify a critic. This closes the
silent approval failure; it does not claim every model error is impossible.

Additional corrections:

- Written-out numbers are checked, including the brief's “eleven hours” and
  “nine hundred on delivery.” Duration checks cannot borrow a count of hulls or
  weeks as evidence for hours. This remains a bounded English numeric check, not
  a general semantic proof of quantities or financial terms.
- Word-overlap relevance and briefing-restatement are advisory, not hard vetoes.
  A valid risk explanation need not contain the word “risk.”
- Unknown quality metadata survives promotion, copying and MissionAdapter saves.
- Gateway supports actual JSON schemas; evaluator stores full requests/responses,
  actual model identity/digest, seeds, options and protocol/gateway fingerprints.
- Evaluation never overwrites the original baseline; reports have unique names.
- Failed qualification returns a nonzero process status. Missing identity cannot
  qualify. Truncated or wrong-model responses cannot count as reviews.

## Remaining model limitations

The 4B semantic reviewer is still NOT accurate enough to enforce. It is diagnostic
only. The production mission worker still does not schedule this critic, and no
qualification file has been installed as a runtime approval authority. Existing
hard checks and mission mechanics continue to operate; unknown is not human approval.

On the original 28-case corpus, raw factual review accepted all 12 good cases but
missed 4 of 9 false/contradictory cases. Relevance caught all 4 irrelevant answers
but falsely rejected 2 of 6 relevant ones. Style was deliberately not evaluated;
the 3 robotic cases must not be counted as factual mistakes or as style successes.
The numeric guard separately catches the invented deadline and price. Raw semantic
results are reported separately so code corrections cannot hide model weakness.

A fresh balanced 16-case factual sentinel set was run at seeds 12345 and 67890.
Both accepted 8/8 good lines but missed 4/8 bad lines. Both failed qualification.
The model no longer returns a constant verdict, but discrimination alone is not
enough to qualify. No thresholds were weakened to make these runs green.

The original 8 holdout cases have now been evaluated once with the frozen v2
prompt. Do not claim they remain unexposed for subsequent tuning. Add a fresh
holdout before final calibration of any future revision.

No larger runtime model, protected character/personality change, voice change or
new player-testing requirement was introduced. No 8GB or in-game latency claim.

## Verification

Seven suites pass: critic protocol/qualification, dialogue quality gate, mission
conversation generation, causal contract, narrative metadata, mission transitions
and public board validation. Full compilation: 357 scripts, zero failures.

Regression coverage includes the old exact copied JSON; constant and inverse
constant reviewers; invalid/truncated evidence; missing/duplicate/stale target
coverage; full overflow coverage; configuration drift; duplicate calibration cases;
written deadlines/prices; mismatched duration roles; legitimate paraphrases; and
quality-state JSON reload/copy. Existing generation tests also cover retries,
retirement, stale callbacks and persistence. Normal headless certificate/stat-write
and shutdown warnings remain.

Recorded real inference runs under `logs/quality_eval/`:

- `critic_v2_tuning_12345_1789227893.json`
- `critic_v2_all_12345_1789228134.json`
- `critic_v2_sentinels_12345_1789228191.json`
- `critic_v2_sentinels_67890_1789228339.json`

These record their own exact tested configuration. Later hardening edits change
the fingerprint and invalidate reuse of an older calibration. They are measurement
reports, not runtime qualification certificates.

Run the maintained harness:

```powershell
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/quality_eval/run_critic_eval.gd --log-file C:/CodingProjects/SpaceGame/.tmp_godot_user/test_logs/critic_next_run.log -- --baseline-offline --llm-live-fire --tuning-only
```

Use `--sentinels` instead of `--tuning-only` for the balanced sentinel suite; add
`--seed=67890` for a second seed. Omit both for the original full corpus. Optional
`--model=...` records the requested model and checks the returned identity. Keep all
runs sequential and use unique logs. Both isolation flags are required: they stop
watchdog/TTS discovery and combat refill without blocking the probe's own requests.
Early measurements before the refill flag was required did trigger ambient refill;
no taunt-bank file was manually edited or reverted by this fix.

Next implementation steps are in `claude_handoff_after_critic_fix.md`. Do not block
the whole game plan on making an unqualified general-purpose critic authoritative.
