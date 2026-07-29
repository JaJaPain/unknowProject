# Quiet-Moment LLM — Resume Here

Paused: 2026-07-29, PC going in for repair.
Full analysis: `docs/quiet_moment_llm_findings.md` (**read §11 first — it supersedes §1**).
This file is the working state: what's settled, what's open, and the exact next step.

---

## Where we landed

**Live LLM generation works.** The original conclusion in the research log — that the model
invents facts and cannot be trusted — was wrong. The cause was the prompt, in three parts:

1. The soul block fed Kaelen the public-board fee rule, then the log called the result invention.
2. The ban lists ("do not mention coffee") primed the exact words they banned.
3. The 30 curated examples demonstrate *unanchored idle observations*, not the
   *fact-packet → line* transform actually being requested.

Fixing #3 alone took Kaelen from **0/10** fact-clean (original log) to **11/12** on qwen3:4b.

## Current best configuration

| Piece | Setting |
| --- | --- |
| Model | `qwen3.6:35b-a3b` (MoE, ~3B active — 3.0s warm, 24GB resident) |
| Prompt builder | `fewshot5.py` — V5, "warm-mercenary" Kaelen |
| Fact packets | Rotated wording, 10 variants, code-owned (`fewshot4.PACKETS`) |
| Options | `temperature 0.9`, `top_p 0.95`, `num_predict 200`, `format "json"`, `think false` |
| Result | 10/10 distinct openers, ~6/10 shippable by author review |

Run it: `cd docs/research/quiet_moment && python -c "from fewshot5 import prompt,PACKETS; ..."`
(see the inline snippets in the session, or `batch.py` for the resumable runner).

## Model comparison (few-shot demonstrating the correct task)

| Model | Kaelen fact-clean | N.O.V.A. fact-clean | Warm latency | Voice |
| --- | --- | --- | --- | --- |
| `qwen3:4b` | 11/12 | 9/12 | 2.6s | clean but bland, recites facts |
| `qwen3:8b` | 4/8 | 5/8 | 3.2s | collapses to "I find it…" |
| `qwen3.6:35b-a3b` | 7/8 | 7/8 | 3.0s | **publishable** |

## The four levers that got us here

1. **Rotate the code-owned fact-packet wording** — openers went 1/10 → 10/10 distinct. Biggest
   single win, costs nothing, no model involvement. "modest" dominated every opener purely
   because code said "modest" every time.
2. **Demos are the spec.** V1 demos recited the fact in full → outputs did too. V2 capped the
   fact at 7 words → fixed recitation but collapsed every opener to "Modest pay". V3 varied
   demo *shape* → fixed shape, not the opener attractor (that needed lever 1).
3. **Voice axis matters more than any constraint.** V1–V3 produced a zen broker ("I prefer the
   quiet / boring is profit"). Author rejected: Kaelen is mercenary and candid about her own
   cut. V4 encoded risk↔pay and overshot into contempt at the Captain. **V5** aims the complaint
   at the job/rate/client, keeps warmth in half a line. That single change moved shippable
   output from ~2/10 to ~6/10.
4. **Diversity is code's job, not the prompt's.** Prompt-side "vary the shape" instructions could
   not beat a strong attractor; one line of packet rotation did.

## Author voice direction (from the session — this is canon now)

Kaelen on the risk↔pay axis, in the author's own words:

> "I know this job is more dangerous, but I get paid a whole lot more for you doing it."
> "I know this job is way safer, but I don't make shit from it, so don't make these a habit."

Plus the correction that followed: **"she isn't cold, just wants her money."** The money
complaint is aimed at the job, the rate, or the client — never at the Captain. She never calls
them lucky, careless, or a waste of her time.

Best outputs matching that direction (V5, unedited):

> *"Clean delivery. Low fee. I'm glad you're safe, but next time, pick jobs that pay more."*
> *"Nobody bled. The fee was insulting. We do these when we're bored, not for profit."*
> *"It closed quiet. That's good. The fee landed on the low end, which is poor accounting."*
> *"…what it costs to keep you alive against these peanuts."*

Known remaining drift in V5: corporate-memo register (*"ensure our labor matches the
remuneration"*), occasional sententiousness (*"Safety is cheap labor"*), and one reversion to
zen-broker with no money complaint at all.

---

## Next step (agreed, not yet done)

Run **Kaelen 11–20 on V5** for a firmer read than 10 samples, and/or add a sixth demo that
shows her *refusing* the corporate-memo register, since that is the most frequent remaining
drift.

Then repeat the whole V4→V5 voice-axis exercise for **N.O.V.A.**, which has not been re-specced
at all — she is still on the V1 demos and her outputs drift sentimental
(*"I find this peace preferable…"*) rather than dry-systems.

## Open decisions for the author

1. **The "steer" question.** V5 lines like *"next time, pick jobs that pay more"* are the nudge
   you asked for, but `fixed_cast_souls.json → kaelen.situation_rules.quiet_moment.must_not`
   currently forbids referencing future work, and the validator enforces it. If the nudge is
   canon, the bible needs updating. **This blocks finalizing the validator.**
2. **VRAM.** `qwen3.6:35b-a3b` is 24GB resident with `keep_alive: "30m"`, alongside the game's
   renderer. Unknown headroom. Fallbacks: short `keep_alive` with generation confined to
   loading/dock screens, or `qwen3:4b` with better demos and blander voice.
3. **Sample sizes are 8–12 per arm.** Fact-cleanliness deltas are large enough to trust
   (0/10 → 11/12). Voice judgments are ~10 lines each and partly mine. Worth 30 per character
   before freezing.
4. Settled during the session: **"today"/"tonight" are fine** — the Earth-calendar ban should not
   catch them.

## Corrections to the findings doc still to apply

- **§2.1 softening.** I recommended deleting `public_board_money_rule` from the soul block. Given
  the mercenary voice direction, that rule is *characterful* — she should complain about her thin
  fee. Correct advice: **gate it to public-board moments**, do not delete it.
- §11's revised recommendation predates the V4/V5 voice work; the demo corpus described there is
  now `fewshot5.py`, not `fewshot.py`.

---

## Files here

| File | What it is |
| --- | --- |
| `qm.py` | Core harness — replicates `LocalModelGateway.generation_body()` exactly |
| `fewshot.py` | V1 demos — first correct fact-packet → line transform |
| `fewshot2.py` / `fewshot3.py` | V2 word-cap, V3 varied-shape (both superseded) |
| `fewshot4.py` | V4 mercenary — **too cold**, kept as the negative result |
| `fewshot5.py` | **V5 — current best.** Warm-mercenary Kaelen + rotated packets |
| `score.py`, `lex2.py` | Validators, incl. the allow-list proof (11/11 catch, 30/30 false-reject) |
| `fragments.py` | Curated-assembly experiment (architecture A) |
| `offline.py` | Offline batch authoring probe |
| `live_tail.py` | Fact-free tail probe — the 0/30 N.O.V.A. negative result |
| `batch.py` | Resumable batch runner, banks to `batch_35b.json` |
| `v*_kaelen.json`, `batch_35b.json` | Raw outputs from every run |

## Gotchas that cost time — don't rediscover these

- **In Ollama `format:"json"`, any `Label:` in the prompt becomes a JSON key.** Demos written as
  `FACTS:` / `LINE:` returned `{"facts": […]}` and 10/12 requests looked like parse failures.
  Write demos as prose with no colon-labels. Do **not** combine `format:"json"` with the `@@label`
  flat-block technique used in `OllamaTestStories/labeled_bible.py`.
- `num_predict: 70` truncates pretty-printed JSON around a 28-word line → silent empty rows that
  look like model failures. Use 160–200.
- `QuietMomentLineValidator._contains_any()` uses substring matching: `"fee"` matches **"feel"**,
  `"use "` matches **"because "**, `"ready"` matches **"already"**. It flags 26 of the project's
  own 30 curated Kaelen lines.
- Run Godot tests serially with a unique `--log-file` (project rule).
