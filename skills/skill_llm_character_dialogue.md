# Skill: LLM Character Dialogue (quiet moments, beats, in-voice lines)

## Overview

This skill is how SpaceGame gets a **local 14B model** to write in-character dialogue that is
safe to speak aloud — no invented facts, no repetition across a campaign, and an actual voice
rather than filler.

It exists because the first attempt failed so completely that abandoning generation for a
hand-written list of canned lines looked like the only option. **That conclusion was wrong**,
and the reasons it was wrong are worth writing down, because every one of them looked like a
model limitation and none of them were.

- **Research log with every experiment, positive and negative:** `docs/research/quiet_moment/ITERATIONS.md`
- **Working system + integration notes:** `docs/research/quiet_moment/SYSTEM.md`
- **Model:** `qwen3:14b` via Ollama, ~3.0s/line, 9.3GB
- **Result:** 12 beats, ~90% usable, 0 duplicates over a 30-line playthrough, 0–12% silence

---

## The one principle

> **Code owns everything code can own. The model owns voice, and nothing else.**

Every diversity, consistency and truthfulness win in this project came from moving a decision
out of the prompt and into code. Every attempt to fix those same problems by instructing the
model failed — not once, but consistently enough that it became a rule.

Concretely, code owns: which facts exist, how those facts are worded, which examples are shown,
which detail she mentions, which device she uses, whether the line is spoken at all, and every
repetition check. The model is asked for one thing — *say this, in her voice* — and nothing else.

---

## Why the first attempt failed

The original prompt looked reasonable. It supplied a fact packet, banned known failure modes,
and included curated example lines. It produced **0 usable lines out of 10**, with the model
inventing coffee, fees, hull percentages and "systems nominal".

Three causes, none of them the model's fault:

### 1. The examples demonstrated the wrong task

The prompt showed 3 curated lines as "voice references" — but all of them were *unanchored idle
observations*, while the request was *take these facts and fold them into a line*. The model saw
three demonstrations of task A and an instruction for task B.

**Fix:** few-shot examples must demonstrate the **transform**, not the register. Each demo is a
`facts → line` pair, drawn from a **different** moment than the one being generated, so copying
a demo is useless and detectable.

**This single change took the beat from 0/10 to 11/12 fact-clean.** It is the highest-leverage
fix in the entire project.

### 2. The ban list manufactured the failures

The prompt said *"do not invent a payout amount, fee, coffee, drinks…"* — and the model produced
coffee in 5/10 lines. Deleting the ban list entirely: **0/16**.

**Fix:** never name a forbidden thing in the prompt. Every concrete noun in a ban list is a
suggestion. Bans belong in the validator, which the model never sees.

### 3. The prompt contained the "invention"

The character bible was injected wholesale, including a rule about the broker's fee on
public-board work. The log then recorded "invented a fee" as a model failure **five times**. The
model was obeying the prompt.

**Fix:** project only the parts of a bible that apply to *this* moment. Audit the assembled
prompt before blaming output.

---

## The checklist that actually matters

Work through these in order when a beat is producing bad output. They are ordered by how often
they turn out to be the real cause.

| # | Check | Symptom |
| --- | --- | --- |
| 1 | **Is there a hook?** | Output is flat, safe and forgettable |
| 2 | **Do the demos show the transform?** | Invented facts; copied examples |
| 3 | **Does anything in the prompt name the thing you're seeing?** | The exact banned word appears |
| 4 | **Do the demos match the register you want?** | Output sounds written, not spoken |
| 5 | **Is the moment's valence stated?** | She approves of something she should resent |
| 6 | **Is the aim of any sharp edge stated?** | Contempt lands on the player |
| 7 | **Is anything repeating?** | Fix in code, never in the prompt |

---

## 1. The hook — the most common cause of flat output

A beat needs more than a trigger. It needs a reason this moment *matters to her*.

Ask: **what does this moment threaten or flatter in the character?** Not "what happened".

Worked examples from this project:

| Beat | Wrong hook (flat) | Right hook (landed) |
| --- | --- | --- |
| Public-board job | "she earns a thin cut" | **it's beneath both of them; they're slumming** |
| Safe low-pay job | "the pay is small" | **it doesn't move them anywhere** |
| Post-combat | "the ship survived" | **her paintwork is ruined and she's vain** |
| Long transit | "she's bored" | **she has him to herself and wants him bothered** |

The public-board beat went through **two wrong hooks** before landing. With the wrong hook it
produced *"Board work. Thin cut. No complaints."* in 14/16 lines and 4/16 distinct openers. With
the right one it produced *"They posted the rate, stuck it on the wall, and waited for someone
desperate enough to take it. That's not work. That's a handout."*

**When a reviewer rejects a whole batch, suspect the hook before the prompt.** A beat with no
hook cannot be rescued by better wording.

Corollary: **a fact packet with no material forces the model onto its one salient fact.** A
post-combat packet saying "hull stable, Captain unhurt" produced *"you're still breathing"* in
9/20 lines, because survival was the only thing there. Adding *damage* to the packet gave her
something to be theatrical about and the beat came alive.

---

## 2. The demos are the spec

Everything about a demo transfers to the output. This is the most reliable lever in the system,
and the most common source of accidental problems.

| Demo property | What it sets | Measured |
| --- | --- | --- |
| The task they demonstrate | Whether facts get invented | 0/10 → 11/12 |
| Length | Output length | 23–27 word demos → over-cap output; ≤20 → 0/20 over |
| Register | Whether it sounds spoken | zero contractions in demos → stiff, written output |
| **Valence** | Whether she approves or resents | a demo praising a good payout leaked approval onto a bad one |
| Sentence pattern | Structural monotony | one demo's "X, which I like" hinge appeared in 4/10 outputs |

Practical rules:

- **Demos ≤ 20 words** if you want output under 25.
- **Write them spoken**, with contractions. If a demo sounds composed, output will too.
- **Tag each demo with a shape** (fact-first, address-first, question, single-sentence) and
  sample across shapes so structure varies.
- **Drop the demo nearest to the current moment** (`avoid_facts`). A demo that resembles the
  request gets templated instead of transferred.
- **Never let a demo line reach the player.** `demo_echo` catches 5-word runs.

---

## 3. Rotate everything, in code

The model has strong attractors. It will pick the same opener, the same detail, the same
retraction, every time — and **no prompt instruction has ever beaten this.** Five separate
attempts failed.

What rotation fixed, measured:

| Rotate | Problem | Result |
| --- | --- | --- |
| Packet **vocabulary** | every line opened "Modest pay" | 1/10 → 10/10 distinct openers |
| Packet **grammar** | 7/10 packets began "The job…" → 9/20 outputs did | 10/20 → 12/20 |
| **Demo selection** | one demo's pattern dominated | pattern leak 4/10 → 0/20 |
| **The detail she mentions** | "my struts are loose" 5/20 | 0/20 |
| **The device she uses** | naming one retraction → 20/20 identical | 1/20 |

Two traps:

- **`rng.choice` is not rotation.** Sampling with replacement repeated one detail 4/10 in a
  single run. Use a shuffled bag, drawn without replacement.
- **Naming one way to perform a move makes it formulaic.** List several; the model picks among
  them. "She retracts because it's automated" → 20/20 automation retractions. Listing five ways
  → 1/20.

---

## 4. State the valence, and state the aim

Two short paragraphs that prevent two whole classes of failure.

**Valence** — what this moment means to her, and what she must not claim. Without it, the model
borrows valence from whichever demo it happened to see. Adding one paragraph took axis inversion,
false novelty claims and out-of-character behaviour all to **0/20** in a single run.

**Aim** — who a sharp edge points at. This is the failure that recurred most:

| Character | New axis | Overshoot | Fix |
| --- | --- | --- | --- |
| Kaelen | mercenary | contempt at the player | complaint aims at the job/rate |
| N.O.V.A. | bawdy | innuendo at the player | innuendo aims at the mechanic |
| N.O.V.A. | teasing | "pretending to be useful" | never implies he's useless |
| N.O.V.A. | put-upon | grudges, score-keeping | it's a performance, not a grievance |

**Give a character a sharp edge and it will land on the player unless you say where it goes.**
Every fix was an aim-constraint — never a reduction in intensity.

Note the last row: **volume, target and sincerity are three separate dials.** "Loud" is not
"bitter". She can complain at any volume provided it's a performance.

Also state **who did what** when more than one party is involved. On a repair beat the demos
showed the Captain doing repairs, so lines credited him with work the yard crew did. Naming the
agents in the valence took it to 0/20.

---

## 5. Validation: a safety net, never a quality gate

**A deterministic validator cannot judge whether a line is good.** This was measured, not
assumed: a corpus-derived allow-list caught **11/11** real failures and false-rejected **30/30**
legitimate novel lines. The difference between *"The ledger balanced itself for once"* (fine) and
*"The board's fee is tiny"* (not fine) is semantic, not lexical.

So validation exists to stop **unsafe** or **repetitive** lines, and quality comes from the hook,
the demos and the model. Do not tune the validator hoping quality improves.

Every check in `runner.py` came from an observed defect:

| Check | Catches |
| --- | --- |
| `packet_echo` | hands the packet's own words back |
| `demo_echo` | reproduces a few-shot demo |
| `brief_echo` | quotes the prompt's own prose |
| `lead_in_echo` | restates the authored opener it follows |
| `wrong_address` / `double_address` | wrong character's address term; "Captain" twice |
| `generic_praise` | banned in Kaelen's bible |
| `invented_number` | a quantity the packet never supplied |
| `word_echo` | same content word 3+ times in one line |
| `belittles_captain` / `demands_apology` / `inverts_affection` | N.O.V.A. drifting cold |
| `tts_*` | constructions the TTS renders unreliably |

Plus recency gates for openers, phrases and closers. **Recency is per CHARACTER, not per beat** —
a character repeating herself across two different beats is just as obvious to the player. That
state must persist in the save.

### An LLM critic does not work here

Tested: ask the model to pick best/worst from 5 candidates. It was right ~3/6, and its failure
mode is systematic — **it prefers bland over concrete.** It marked *"the payout felt like a
rounding error"* (a good broker joke) as the worst of its set. Usable as a *rejector* of obvious
problems, never as a *selector* of quality.

### Bugs in the checks themselves, all real

- Models emit **U+2019** apostrophes; ASCII regexes silently miss them. Normalise first.
- Combining case-sensitive alternatives under one `re.I` made `[A-Z]{2,}` match any two letters
  and flag **55/55 good lines**.
- Including "one" as a number word false-flagged 9/20 lines ("this **one** paid small").
- **Writing a regex through a shell heredoc turns `\b` into a literal backspace (0x08).** This
  happened three times, silently disabling checks while `grep` showed correct source. The tell is
  `\x08` in `repr(pattern)`. Write regexes with an editor.

### Authored text must pass the same checks

Three separate defects came from text *I* wrote, not the model: packets saying "He walked away"
leaked a gender assumption; a tool list contained hyphenated compounds that trip the TTS screen;
and lead-ins used planetary-landing vocabulary for a station dock. **Packets, lead-ins and
vocabulary lists are prompt content.** Lint them.

---

## 6. What transfers between characters, and what doesn't

Tested by applying the whole method cold to a second character.

**Transfers completely — the engineering.** N.O.V.A. hit 20/20 structurally clean on attempt 1,
where Kaelen took eleven iterations. The diagnostic tool ran on the new character with zero
changes. Every mechanical lesson above applied without rediscovery.

**Does not transfer at all — the voice.** It took four separate corrections from the author, and
the decisive ones were things no amount of iteration would have produced:

- *"the ship is her body"* — she says "my intakes", "my plating"
- *"lewd, but it could be taken at face value"* — every phrase must have an innocent literal
  reading, which is what makes it deniable
- *"think of it like trying to make the player jealous"* — which turned out to be a whole
  device, not a tone
- *"she isn't cold, just wants her money"* (Kaelen) — the difference between mercenary and cruel

**Budget accordingly.** Mechanical setup for a new beat is now near-free. Finding the hook and
getting the voice right is authorship, and it needs a human with taste and a few rounds of
listening. That is the irreducible cost, and it is small — roughly four notes per character, each
applying to every beat that character will ever have.

---

## 7. Cost control: diagnose locally

Most of the expensive iteration was not generating — it was working out *which input* caused a
pattern. Nearly every diagnosis had one shape:

> The output mirrors a measurable property of the demos or packets. Measure it in both, and the
> divergence names the fix.

That is arithmetic. `docs/research/quiet_moment/diagnose.py` encodes it — **no LLM, no API, runs
local** — and reports the fault plus the suggested fix. Validated against historical batches, it
independently found the demo-register problem, opener mirroring *with its packet cause*, emergent
tics with no hardcoded regex, and valence inversion.

**Per-new-beat loop, no reasoning model required:**

```
write fact packets  →  run 20 samples  →  python diagnose.py  →  apply named fix  →  repeat once
```

Rule discovery is expensive and one-time. Rule application is free and local.

---

## 8. Speaking, not reading

These lines are heard, not read. A construction that reads fine and renders badly is still a
defect.

- **Hyphenated compounds** have no reliable spoken form in Kokoro. "mid-job" was the one word an
  author couldn't parse in a 55-line listening test — and the screen flagged exactly that line.
- **Kokoro does not honour a spaced `". . ."` as a pause.** Confirmed by ear. A real pause needs
  two TTS calls with silence inserted between them.
- **Render and listen before trusting a text-level judgement.** In this project the text-level
  accept/reject decisions did hold up in audio — but that was verified, not assumed.
- `render_audio.py` pulls voice IDs from `data/content/voice_provider_kokoro.json` so listening
  tests can't drift from what ships.

---

## Quick reference: adding a beat

1. **Find the hook** — what this moment threatens or flatters in her.
2. **Write ~12 fact packets** — same facts, varied vocabulary *and* grammar.
3. **Write the valence paragraph** — what it means to her, what she must not claim, who did what.
4. **Add a lead-in pool** if the reaction would sound unwarranted without context.
5. **Run 20**, then `diagnose.py`, then apply the named fix and re-run.
6. **Set `fire_probability`** if the trigger is common. A good line on too frequent a trigger
   still wears out.
7. **Listen to it** before calling it done.

Never fix repetition, tics or duplication in the prompt. That is the selector's job.
