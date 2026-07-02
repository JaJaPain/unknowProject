# Claude's Independent Review + Test Results

Reviewed: `consensus_brief_story_generation.md`, `progress.md`, `gemma4_insights.md`.
Then ran my own Ollama tests against `gemma4:12b`, targeting the **actual production prompt**
(`NarrativeDirector.build_campaign_bible_prompt`, as currently modified on this branch) rather than
the standalone test harness. All raw outputs are saved alongside this file in timestamped
`claude_*` folders. Scripts: `claude_test_production_prompt.py`, `claude_test_think_param.py`,
`claude_test_diversity.py`.

## Headline finding: this is not primarily a schema/truncation problem — it's a thinking-model leakage bug

`gemma4:12b` is a **reasoning/"thinking" model** (`ollama show` reports `"capabilities":["completion","tools","thinking","vision"]`).
Ollama's `/api/generate` has a `think` request parameter specifically for this. Production code
never sets it.

I ran the exact production prompt + exact production options (`temperature=0.55, num_predict=900,
format="json"`, no `think` key) three times:

- Candidate 1: model emitted **only** `{"thought": "..."}` as the entire response, then stopped (`done_reason=stop`, 64 tokens). Zero of the 19 required keys present.
- Candidate 2: missing `expansion_rules`, `banned_repeats`.
- Candidate 3: missing `rumor_trails` (mutated to `rumor__trails`).

Then I raised `num_predict` to 2800 (over 3x the test harness's own value) to test the "context
window / truncation" theory from `gemma4_insights.md`. **It didn't fix it** — 2 of 3 candidates
still had missing keys, and `done_reason` was `stop` in every single trial across both settings,
never `length`. The model is choosing to close the JSON object early — it is not running out of
token budget. Throwing more `num_predict` at this bug is a dead end.

I then set `"think": false` on the same production prompt/options (`num_predict=900,
temperature=0.55`) and ran it 4 times: **4/4 clean, complete JSON, zero missing keys, zero key
mutations, ~20s each.** This is a clean, reproducible fix, not a lucky sample.

## Why this matters beyond campaign_bible

`LocalModelGateway.generation_body()` never emits a `think` field at all — it only ever sends
`model`, `prompt`, `stream`, `keep_alive`, `options`, `format`. Every capability routed to
`large_story` profile (`campaign_bible`, `system_names`, `faction_batch`, `system_story_pack`,
`story_horizon`) uses `gemma4:12b`/`gemma4:latest` and is exposed to the same failure mode. The
`small_dialogue` profile (`qwen2.5:*`) is not affected — those models don't report a `thinking`
capability in `ollama show`, so this is specifically a large-story-model problem.

**Recommendation:** add `"think": false` to `LocalModelGateway.generation_body()` for any
capability whose resolved model has thinking capability (or, simplest: always send `think: false`
for the `large_story` profile — dialogue/taunt/chatter calls on qwen already don't need it, and it's
a no-op for models that don't support it). This is a one-line-ish fix, not an architecture change,
and it should be tried before any two-pass rewrite lands, since it may remove most of the reported
JSON/truncation/key-mutation pain by itself.

## Second finding: fixing the bug exposes a real, separate motif-collapse problem

With `think: false` fixed, JSON reliability stopped being the bottleneck — so I looked at whether
the *content* still had the diversity problem the consensus brief warned about ("must not
accidentally force every run into ancient signal / ghost signal / prophecy / alien owner"). It
does, badly:

4 clean runs at `temperature=0.55` (production default), titles: **"The Zenith Paradox"** (x2),
"The Zenith Drift", "The Zenith Silence". All four `long_term_reveal` fields independently landed
on the same twist: Kaelen is secretly a non-human AI/consciousness/failsafe left over from a dead
civilization ("Great Silence"/"Great Collapse"/"purge"). This is a converged local optimum in the
model's weights for this exact prompt shape, not noise.

I then tried raising temperature alone (`0.95`, still `think: false`, no other prompt changes) to
see if that was enough — it was not: "Echoes of Zenith", "The Zenith Drift", "The Zenith Veil", and
2 of 3 still gave the Kaelen-is-an-AI-fragment reveal. Temperature is not the lever.

Finally I added one paragraph of **explicit anti-motif + creative-lane guidance directly in the
single-pass prompt** (no second LLM call): name the specific overused motifs to avoid, name the
banned title pattern, and offer concrete alternate lanes (criminal economy, corporate espionage,
ecological crisis, political succession, sabotage), plus an instruction that Kaelen's secret must
be mundane, not a sci-fi twist. Result, 3/3 at `temperature=0.95`: **"The Sovereign Debt"** (a
privatization scheme), **"The Orbital Scarcity"** (Kaelen fenced a crate of stolen wine),
**"The Ledger of Broken Bonds"** (Kaelen is a hiding auditor who stole a ledger out of spite). Three
distinct titles, three distinct genres, zero repeated reveal, still fully valid JSON, still under
25s.

**This is the important part:** diversity was solved with one extra paragraph in a single call, not
a second LLM round-trip. The consensus brief's two-pass architecture was largely built to solve two
problems at once — JSON reliability and motif diversity — using one mechanism (a Pass 1 "uniqueness
brief" call). My tests suggest these are two separate problems with two separate, cheaper fixes:
`think: false` for reliability, and a **code-authored** (not model-authored) anti-motif block for
diversity. A model-generated Pass 1 brief is itself unreliable (the project's own
`notes_two_pass_findings.md` and `progress.md` show "meta failed" on 3 of the two-pass runs) — so
generating the anti-motif list with a second LLM call adds a second unreliable step to route around
a problem a static/code-curated list already solves.

## Recommended architecture (revised from the consensus brief)

1. **Single LLM call, not two**, for the campaign bible — but with two additions to the prompt:
   - `think: false` in the request body (fixes structural reliability).
   - A code-generated (not model-generated) anti-motif block: a curated, hand-written list of
     motifs/titles/reveals to ban (seeded with what I found above — "Zenith [X]" titles, Kaelen as
     secret AI/archive/failsafe, "Great Silence/Collapse", purge protocols), plus a short menu of
     creative lanes to rotate through. `CampaignIdeaMemoryStore` already accumulates
     `banned_repeats` across campaigns and already feeds `campaign_bible_prompt_context()` into the
     prompt — this infrastructure exists today, it's just not seeded with a starter list, and
     nothing rotates the creative lane. That's a small, deterministic code change, not a new LLM
     pass.
2. Keep normalization for harmless key mutations (the codebase already does this for
   `rumor_trails`/`regeneration_triggers`; the consensus brief's mutation list, e.g. `v_problem` →
   `vanguard_problem`, is still worth keeping as a safety net even after `think: false`, since
   mutation dropped to near-zero in my tests but wasn't literally zero across all sampling).
3. Add one retry: if validation fails, retry once with the same prompt plus the specific validation
   errors appended (this pattern already exists elsewhere in the codebase for Kaelen intro
   self-critique retries — reuse it here instead of inventing a new retry mechanism).
4. Do not fall back to a fake campaign bible on repeated failure — the current bootstrap-placeholder
   behavior in `CampaignBibleStore._default_bible()` (explicitly labeled "pending", blocks
   `is_campaign_story_ready()`) is correct and matches the project's fallback-is-failure policy. Keep
   it, just make it much less likely to be needed by fixing `think`.
5. Only reach for a genuine two-pass design if, after `think: false` + code-authored anti-motif
   guidance, you still see motif collapse in practice — I did not find evidence that's necessary.

## Answers to the 10 open questions in the consensus brief

1. **Two-pass vs. three-pass:** Neither is clearly needed yet. Single-pass with `think: false` +
   code-authored anti-motif guidance solved both problems I could reproduce. Revisit if real
   playtesting shows motif collapse the static list doesn't cover.
2. **Nested schema vs. flatten vs. store both:** The current production prompt is already flattened
   (no nested `opening`/`mystery`/`kaelen`/`factions` objects like the original consensus-brief
   schema) — that's good and should stay; flattening measurably helped in the original harness runs
   too (compact_json variants scored much higher than the nested schema). Store the single bible;
   don't add a second nested representation, it's not carrying its weight if one call now works.
3. **Future-generation questions in Pass 1, Pass 2, or both:** Moot if you drop Pass 1. Keep
   `story_questions_for_future_generation`/`expansion_rules` as fields in the single bible, seeded
   by rules in the prompt (as now), not generated by a separate meta-call.
4. **Normalize mutations vs. retry on any mutation:** Normalize known-harmless mutations, then
   validate strictly, then retry once if still invalid — matches the brief's own recommendation, and
   my tests show mutation frequency is low but not exactly zero, so normalization is still worth the
   safety net.
5. **How much hidden crisis should small LLMs see:** Only via the derived `hidden_director_notes`
   context block already proposed in the brief — never hand the raw bible's `long_term_reveal`/
   `mystery` fields to the small dialogue models directly, since a leak there is much more visible to
   the player than a leak in code.
6. **Starter mission generated vs. fixed + flavor injection:** Fixed in code, flavor from the bible.
   `gemma4_insights.md` already caught a real bug here — the model interpreted "the first mission
   must be exactly one starter Reaver ship" as the *player* piloting a Reaver, not fighting one. That
   ambiguity is a sign the mission mechanics shouldn't be left to the model's judgment at all; keep
   the encounter fixed in code (one hostile Reaver-class ship) and only pull flavor text
   (`starter_mission.reason`, `enemy_knows`, `after_effect`) from the bible.
7. **Missing fields for mining/salvage/delivery/combat/rumors/stations/gates:** The current flattened
   production schema is thinner than the original consensus-brief nested schema — it dropped
   `factions` (per-faction problems), `kaelen` (secret angle / never-reveal rule), and
   `starter_mission` as first-class fields, folding them into free-text rules instead. Given
   `LLMInterface`/`StoryManager` clearly want per-faction pressure for faction-flavored generation
   later (`faction_batch` capability exists), I'd add back a compact `factions: {zenith, aurelia,
   vanguard}` triad of one-line problem strings — that's cheap (3 short strings) and unlocks faction-
   flavored contract/chatter generation without another LLM call.
8. **Variety vs. bias toward scarcity/logistics:** Confirmed bias exists but it's fixable at the
   prompt level (see finding above) rather than being an inherent model limitation. The specific bias
   observed was less "resource scarcity" and more "Kaelen is secretly not human" — worth banning that
   reveal specifically, not just steering away from scarcity/logistics as the brief assumed.
9. **`campaign_story_summary` length:** The flattened production schema replaced this with
   `act_1_outline` (3 short beats) instead of one long summary field — that's a reasonable trade and
   produced coherent output in my tests; I wouldn't add a long-prose field back in the same call,
   since the two_pass tests in `progress.md` show summary quality was the weakest part of every
   variant tried (best case score 92, and pitch/summary richness was flagged as a "remaining
   concern" on both of the two best candidates).
10. **Minimum quality bar before game start:** Structural bar (all required keys present, snake_case
    IDs valid, enum fields valid, Kaelen role correct, starter mission constraint honored) should
    gate hard, as the brief says. For narrative-quality bar, I'd add one more automatable check: the
    generated `campaign_title` and `long_term_reveal` must not match any of the last N
    (`CampaignIdeaMemoryStore`-tracked) titles/reveals by simple string-similarity — cheap, catches
    exactly the collapse I found, and doesn't require another model call to judge itself.

## Concrete next steps, in order

1. Add `"think": false` to `LocalModelGateway.generation_body()` (or at minimum to the
   `campaign_bible` request in `LLMInterface.request_campaign_bible_generation()`, then extend to
   `system_names`/`faction_batch`/`system_story_pack`/`story_horizon` once confirmed). Cheapest,
   highest-confidence fix available — 4/4 clean in my tests vs. 1/3 and 1/3 in the two current
   settings tried.
2. Add a static, hand-written anti-motif + creative-lane block to
   `NarrativeDirector.build_campaign_bible_prompt()`, seeded with the motifs found above. Wire
   `CampaignIdeaMemoryStore`'s existing `banned_repeats` accumulation to append to this list over
   real play sessions so it keeps improving without code changes.
3. Re-run a batch (10+) of full production-path generations with both fixes in and score them the
   way `generate_story_candidates.py` already does, to get a real pass-rate number instead of my
   small sample.
4. Only then decide whether any second LLM pass is still earning its latency cost.
5. Consider lowering `campaign_bible` timeout back down from 600s toward something like 30-45s once
   `think: false` is in — a clean run took ~20s in every one of my tests; 600s was likely raised to
   paper over a stall this fix removes.
