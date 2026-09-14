# Patched Production Prompt Status

Current implementation status:

- Large-story Ollama requests now send `think: false`.
- Campaign bible generation uses a single production call with deterministic creative lanes.
- The prompt discourages overused motifs, but Kaelen's hidden identity is intentionally open-ended.
- Only Kaelen's public-facing role is constrained: broker, fixer, or contract handler.
- A repair pass now runs before validation for safe campaign-bible drift.

Safe repairs currently include:

- Known key aliases.
- Single-object values where arrays are expected.
- Rumor trail ID cleanup.
- Minimum clue counts.
- Regeneration trigger ID cleanup.
- Common curly/encoded punctuation cleanup.
- Vague Kaelen role drift into the public broker/fixer mask.
- Named future-faction payoff leaks changed into unnamed outside-power hints.

Hard validation still rejects:

- Missing required story fields.
- Wrong array shapes after repair.
- Explicit wrong public Kaelen roles, such as publicly mechanic, scientist, commander, prophet, AI, archive, or failsafe.

Live verification:

- Output folder: `OllamaTestStories/20260701_223050_patched_production_prompt`
- Result: 3/3 structurally valid.
- Missing keys: none.
- Runtime: about 21 seconds each.
- Titles: `The Scavenger's Ledger`, `The Yield of Zenith`, `The Silted Vein`.

Important design note:

Kaelen can secretly be anything the story wants her to be. The player should only see hints, never a full explanation. The code should enforce her public mask and secrecy, not forbid possible hidden truths.
