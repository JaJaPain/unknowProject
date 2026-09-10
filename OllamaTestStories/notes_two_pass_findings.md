# Two-pass findings

Best direction so far: Ironbound Reach from 20260701_211332_two_pass_near_field_questions/two_pass_03_story.json.

Why it works:
- Specific industrial scarcity premise.
- Player remains a broke independent pilot.
- Kaelen stays broker/fixer.
- Starter mission is one Reaver-like vessel.
- Recurring clue is cargo/manifests, not an ancient signal.
- Future questions mostly stay near contracts, factions, Kaelen, and trade choices.

Harness lesson:
- One giant flat prompt breaks JSON.
- Ollama schema mode caused repetition/truncation.
- Compact JSON shape written directly into the prompt is better.
- Two-pass meta questions improve uniqueness and motif control.
- Final game should normalize harmless key mutations like v_problem, true__hint, opening_itement, humor__rule, fall_back_rule, and dotted trigger IDs.

## 2026-07-01 Two-pass conclusion

Best validated candidates after normalizing harmless key mutations:

1. `20260701_211618_two_pass_final_check/two_pass_02_story.json`
   - Title: Iron Scarcity
   - Score after normalization: 92
   - Strengths: strong resource-scarcity premise, one Reaver starter mission, Kaelen as broker/fixer, hidden crisis tied to supply-chain sabotage.
   - Remaining concerns: pitch/summary could be richer, future questions are usable but still slightly awkward.

2. `20260701_211332_two_pass_near_field_questions/two_pass_03_story.json`
   - Title: Ironbound Reach
   - Score after normalization: 88
   - Strengths: distinctive `Void-Stitched Cargo` clue, industrial scarcity, strong faction pressure, good playable Act 1 loop.
   - Remaining concerns: one key mutation (`true__hint`) and slightly thin pitch/summary.

Design conclusion:
- Two-pass generation is better than one-pass.
- Pass 1 should generate a uniqueness brief and open questions.
- Pass 2 should fill a compact nested JSON shape from that brief.
- The game should normalize harmless key mutations before validation.
- Avoid Ollama structured-output schema mode for this model; it caused truncation/repetition.
- Avoid giant flat schemas; they break JSON and create generic answers.

Recommended game implementation:
- Store both the meta brief and final story bible for debugging.
- Run pass 1 and pass 2 at campaign creation.
- If final validation fails, retry pass 2 once with the same meta brief and a stricter repair prompt.
- If it still fails, stay on loading screen with the validation errors in debug.
