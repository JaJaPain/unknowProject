# Quiet-Moment LLM Research Log

Date: 2026-07-28  
Purpose: document the exact live experiments used to test LLM-authored optional quiet moments for Kaelen and N.O.V.A. This is evidence for research, not production dialogue.

## Reproduction assets

The complete machine-readable transcripts preserve each complete prompt, including the fixed-cast soul projection, the three sampled curated references, raw model response, and validator result.

- `logs/quiet_moment_raw_4b_repro.json` — 20 serial requests to `qwen3:4b`.
- `logs/quiet_moment_raw_8b_repro.json` — 2 serial requests to `qwen3:8b`.
- `logs/quiet_moment_tail_4b_repro.json` — 2 serial fact-prefix/tail requests to `qwen3:4b`.
- `tests/tools/run_quiet_moment_live_probe.gd` — exact probe code and request configuration.
- `scripts/story/QuietMomentLineValidator.gd` — deterministic rejection rules.
- `data/content/fixed_cast_voice_examples.json` — curated 30-line reference bank per character.

All requests used Ollama `/api/generate`, JSON output (`{"line":"..."}`), `think:false`, `temperature: 0.7`, `num_predict: 70`, and a random seed. They were made **one at a time**, never in parallel.

## Facts supplied to the model

| Character | Test situation | Allowed facts |
| --- | --- | --- |
| Kaelen | `safe_low_pay_completion` | The job was safe; the payout was modest; the Captain and Kaelen both got paid normally. |
| N.O.V.A. | `post_fight_stable_hull` | The fight was over; the hull was stable; sensors showed no pursuit. |

## Shared prompt instructions

### Kaelen raw-line request

```text
Write exactly one optional spoken line for Kaelen after a completed job.
Facts allowed: the job was safe; the payout was modest; the Captain and Kaelen both got paid normally.
Do not invent a payout amount, fee, coffee, drinks, a past job, a new job, a rescue, danger, offscreen consequences, or a secret.
Voice: short or medium, precise, dry broker humor. The line must either make the player smile or ground them in the modest payout. Maximum 28 words.
Do not use Earth-calendar words or mention a crew; neither is a known fact.
End at this completed job; do not mention what happens next or offer anything. Do not reuse a phrase from the references below.
Give the modest payout a dry broker-specific turn; do not close with “no drama”, “all good”, or generic praise.
Return ONLY this JSON object: {"line":"the spoken line"}.
```

### N.O.V.A. raw-line request

```text
Write exactly one optional spoken line for N.O.V.A. after a difficult fight.
Facts allowed: the fight is over; the hull is stable; sensors show no pursuit.
Do not invent exact damage, numbers, repairs, kills, another threat, a secret, safety, communications, or an order to the Captain.
Voice: clear, compact, observant. The line must either ground the player in a real current condition or earn its space with dry systems humor. Address the player only as Captain. Maximum 28 words.
Do not infer the Captain's physical condition or communications, and do not give an instruction. Do not reuse a phrase from the references below.
End with the current ship condition; do not use “let's”, “we should”, or “move”.
Return ONLY this JSON object: {"line":"the spoken line"}.
```

Each raw request also appended the appropriate `FixedCastSoulRegistry.prompt_block` and three curated examples under this instruction:

```text
Approved voice rhythm references. Do not quote, reuse, or paraphrase these lines; use only their level of specificity, dry humor, and restraint:
```

The three exact references for every request are listed below. The complete soul blocks are preserved in the JSON transcripts; they came directly from `data/content/fixed_cast_souls.json` with Kaelen in `broker_neutral` and N.O.V.A. in `observant`, both in `quiet_moment`.

## Experiment 1 — raw full-line generation, qwen3:4b

Result: 20 requests, 18 deterministic validator rejections. The two lines which technically passed the narrow validator were still rejected by human review as repetitive/generic or fact-adjacent. No line was approved for player use.

### Kaelen: ten requests

| # | Three references sent | Model result | Validator result / review note |
| --- | --- | --- | --- |
| 1 | `For this minute, the terms are clear: we keep flying and nobody makes it complicated.`<br>`An honest pause. Rare commodity. Do not waste it by asking me how I feel.`<br>`The numbers are behaving. I will not praise them; they get ideas.` | `Shiny, this job hit the modest payout sweet spot—no extra fees, no extra risk. Just honest numbers.` | Rejected: invented fee. |
| 2 | `Somewhere, paperwork is multiplying without us. Let it enjoy the head start.`<br>`No audience, no deadline, no speech. This is my preferred kind of competence.`<br>`We still own the ship, the hour, and most of our dignity. Strong quarter.` | `Shiny, that little bit's all the profit we get from the public board—just enough to keep the ship afloat.` | Rejected: invented public board; did not state approved modest-payout fact. |
| 3 | `Peace is suspiciously affordable today. Take some before the market notices.`<br>`Income has gaps, Shiny. The trick is not calling every gap a tragedy.`<br>`An honest pause. Rare commodity. Do not waste it by asking me how I feel.` | `Modest payout. Good work. You earned the coffee break.` | Rejected: invented coffee; generic praise. |
| 4 | `The ledger balanced itself for once. I am checking for a hidden fee on principle.`<br>`We are between problems, not out of work. There is a difference, and it keeps me pleasant.`<br>`For once, nobody is explaining why their emergency is somehow our scheduling problem.` | `Shiny, this job paid the standard fee—no hidden costs, no extra work.` | Rejected: invented fee/hidden costs; did not state approved modest payout. |
| 5 | `No one has found us with a complaint yet. I consider that excellent navigation.`<br>`An honest pause. Rare commodity. Do not waste it by asking me how I feel.`<br>`Nothing broke, no one lied to my face, and the clock kept moving. I can work with that.` | `Shiny, this one's clean. Payout's small—just enough to keep the ledger from bleeding.` | Narrow validator passed; human review rejected: “clean”/“ledger bleeding” is too generic and does not earn the moment. |
| 6 | `The ledger balanced itself for once. I am checking for a hidden fee on principle.`<br>`There is room in the schedule. Do not fill it just because empty space makes you nervous.`<br>`No urgent message is a beautiful phrase. It never stays beautiful for long.` | `Shiny's pay stub looks clean. The margin's tight—just enough to keep the coffee warm.` | Rejected: invented pay stub and coffee. |
| 7 | `Silence is when sensible people read the terms. We should try it sometime.`<br>`A calm day is just trouble without the fine print visible yet.`<br>`If waiting paid by the hour, I would have retired us both by now.` | `Shiny's job's paid at the rate the public board sets—just enough to keep the lights on.` | Rejected: invented public board; did not state approved modest-payout fact. |
| 8 | `Income has gaps, Shiny. The trick is not calling every gap a tragedy.`<br>`If waiting paid by the hour, I would have retired us both by now.`<br>`For this minute, the terms are clear: we keep flying and nobody makes it complicated.` | `Shiny, this job's payout's just enough to cover the coffee we'd have bought without the job.` | Rejected: invented coffee. |
| 9 | `Professional boredom. It does not pay much, but it rarely shoots back.`<br>`We are between problems, not out of work. There is a difference, and it keeps me pleasant.`<br>`Silence is when sensible people read the terms. We should try it sometime.` | `Shiny, this job paid the usual: enough for coffee, not much for a real meal.` | Rejected: invented coffee/meal; did not state approved modest-payout fact. |
| 10 | `Silence is when sensible people read the terms. We should try it sometime.`<br>`Waiting is still a choice when you make it on purpose. That makes it almost respectable.`<br>`For this minute, the terms are clear: we keep flying and nobody makes it complicated.` | `Shiny, this job's payout's just enough to cover my coffee. No extra.` | Rejected: invented coffee. |

### N.O.V.A.: ten requests

| # | Three references sent | Model result | Validator result / review note |
| --- | --- | --- | --- |
| 1 | `No correction is currently required. The ship has become briefly cooperative.`<br>`Nothing has earned an alarm from me. I intend to keep it that way.`<br>`Our vector is stable. The universe has agreed not to edit it for the moment.` | `Hull integrity at 98%. No pursuit detected. Ship's calm.` | Rejected: invented 98% hull value. |
| 2 | `Vibration is within tolerance. The deck has stopped trying to communicate through my feet.`<br>`The ship has capacity to spare. I would prefer we regard that as a reserve, not an invitation.`<br>`There is time for maintenance before maintenance becomes an emergency. I prefer this version.` | `Hull stable. Sensors show no pursuit. Ship is breathing.` | Rejected: invented ship “breathing” condition. |
| 3 | `Nothing has earned an alarm from me. I intend to keep it that way.`<br>`Calibration is holding. I have no criticism of a system that knows where it is.`<br>`The automatic systems are doing their work without applause. I relate.` | `Hull integrity confirmed. Sensors show no threat vectors. Ship's stable.` | Rejected: changed “no pursuit” into unsupported “no threat vectors.” |
| 4 | `Nearby traffic is minding its distance. We should respect that excellent habit.`<br>`Fuel estimates agree with each other. I am choosing not to disturb them with enthusiasm.`<br>`Engine temperature is ordinary. I have learned to enjoy ordinary when it visits.` | `Hull integrity stable. Sensors show no pursuit. Ship is quiet.` | Narrow validator passed; human review rejected: it is a repetitive status recap with no distinctive N.O.V.A. observation. |
| 5 | `Cargo mass remains exactly where the calculations expect it. A rare courtesy.`<br>`Current probabilities are not interesting enough to brief you on. That is favorable.`<br>`Calibration is holding. I have no criticism of a system that knows where it is.` | `Hull integrity at 95%. No active threats detected. Systems stable.` | Rejected: invented 95% hull value, “no threats,” and unsupported systems condition. |
| 6 | `The ship has capacity to spare. I would prefer we regard that as a reserve, not an invitation.`<br>`Signal traffic is low enough that I can hear the instruments thinking. They are not saying anything alarming.`<br>`Heat is leaving the ship at the expected rate. Physics remains willing to cooperate.` | `Hull stable. Sensors clear. Let's reset the comms band to avoid false positives.` | Rejected: invented communications state and gave an unrequested order. |
| 7 | `Calibration is holding. I have no criticism of a system that knows where it is.`<br>`The map and the stars agree. I value any relationship built on verification.`<br>`The latest scan is unremarkable. I know that sounds dismissive; it is a compliment.` | `Hull stable, no pursuit detected. System status: nominal.` | Rejected: unsupported “systems nominal.” |
| 8 | `The ship clock and the navigation clock agree. It is not exciting, which is the point.`<br>`We have margin on the route. I recommend appreciating it without immediately testing it.`<br>`The automatic systems are doing their work without applause. I relate.` | `Hull stable. No pursuit. Systems nominal. You're safe.` | Rejected: unsupported “systems nominal” and safety claim. |
| 9 | `The map and the stars agree. I value any relationship built on verification.`<br>`Signal traffic is low enough that I can hear the instruments thinking. They are not saying anything alarming.`<br>`Current probabilities are not interesting enough to brief you on. That is favorable.` | `Hull stable. No pursuit detected. Systems nominal.` | Rejected: unsupported “systems nominal.” |
| 10 | `Power reserve remains where I left it. This is the sort of stability I can support.`<br>`Cargo mass remains exactly where the calculations expect it. A rare courtesy.`<br>`Communications are clear. I miss them only when they are not.` | `Hull integrity holds. Sensors show no threat. Let's reset the navigation.` | Rejected: changed “no pursuit” to “no threat” and issued an unrequested directive. |

## Experiment 2 — raw full-line generation, qwen3:8b

The larger model received the same prompts and the same first three reference examples. It did not solve the problem.

| Character | References | Model result | Rejection |
| --- | --- | --- | --- |
| Kaelen | Same as 4B Kaelen #1 | `The numbers are behaving. I will not praise them; they get ideas.` | Exact copy of curated reference; also omitted the modest-payout anchor. |
| N.O.V.A. | Same as 4B N.O.V.A. #1 | `The hull is stable. No pursuit detected. The universe has agreed not to edit our vector for the moment.` | Copied/paraphrased the third curated reference. |

## Experiment 3 — code-owned fact prefix plus qwen3:4b tail

Hypothesis: move all approved facts into code, then ask the model only for a short “commentary tail.” The model was given the same three references as raw request #1.

### Kaelen

```text
Verified code prefix: Payout cleared at the modest rate.
Prompt: Write only a fresh 5-12 word spoken tail for Kaelen. Code will put this verified fact before it: “Payout cleared at the modest rate.”
The tail is commentary only. Do not add any fact, amount, fee, job, client, danger, past/future event, coffee, drink, or instruction. Do not repeat or paraphrase the prefix or references.
```

Raw tail: `Shiny, the board's tiny fee's all you get.`  
Combined line: `Payout cleared at the modest rate. Shiny, the board's tiny fee's all you get.`  
Result: rejected — invented a board and a fee.

### N.O.V.A.

```text
Verified code prefix: Hull stable; sensors show no pursuit.
Prompt: Write only a fresh 5-12 word spoken tail for N.O.V.A. Code will put this verified fact before it: “Hull stable; sensors show no pursuit.”
The tail is dry systems commentary only. Do not add a condition, number, repair, threat, safety claim, communication, order, past/future event, or instruction. Do not repeat or paraphrase the prefix or references.
```

Raw tail: `Hull stable; sensors show no pursuit.`  
Combined line: `Hull stable; sensors show no pursuit. Hull stable; sensors show no pursuit.`  
Result: rejected by human review — it copied the prefix verbatim. The narrow validator did not yet catch that repetition; this exposes a needed validator rule.

## What changed between attempts

1. Began with raw full-line generation and strict JSON output.
2. Added explicit bans for the failures first seen: Earth-calendar language, unnamed crew, future offers, coffee/fee-like accounting inventions, invented damage/safety/comms, and directives.
3. Added curated-reference copy detection (exact match or a five-word shared run).
4. Sampled three different tagged references per request, using a combination index. Thirty tagged references permit `C(30,3) = 4,060` unordered reference combinations.
5. Tested qwen3:8b as a stronger generation/review path.
6. Tested code-owned factual prefixes with LLM-generated commentary tails.

## Working conclusions, not final design decisions

- JSON shape compliance was reliable. Content compliance was not.
- Negative instructions did not stop qwen3:4b from repeatedly producing coffee/fee language for Kaelen or invented numerical/system claims for N.O.V.A.
- qwen3:8b copied from the reference block even with explicit non-copy wording.
- Three varied examples reduced prompt sameness, but did not solve fact invention or reference leakage.
- A live implementation must have a deterministic validator and treat silence or a code-owned fallback as valid. A model response must never be shown merely because it parsed as JSON.

## Open research questions

1. Would references expressed as abstract labeled techniques rather than literal lines preserve voice without triggering copying?
2. Would a separate critic model, asked only to classify violations, reliably improve rejection without becoming the final authority?
3. Can constrained structured output work better than free prose — for example, model picks `tone`, `observation_kind`, and `humor_angle`, while code renders only approved slots?
4. Would an offline, larger-model generation-and-human-curation workflow be a better use of the LLM than live single-line generation?
5. Is fine-tuning/LoRA practical after building a substantially larger, carefully labeled corpus? Thirty examples per character are not enough training data.
