# Storytelling Architecture Plan — Long-Term "Storytelling Mode"

*Planning document, 2026-07-02. No code changes; design only.*

Goal: every campaign feels unique, authored, and reactive, while hard game rules stay enforced and generation stays reliable on an 8GB-VRAM local Ollama setup (`gemma4:12b` large story, `qwen2.5:3b-instruct-q4_K_M` dialogue).

---

## 1. Current System Assessment

### What the system does today

- **Generation:** `GameRoot.request_campaign_bible_generation()` gates gameplay on a real generated bible (`is_campaign_story_ready()` requires `STATUS_LLM_GENERATED`). While the bible generates, `campaign_bible_priority_active` suppresses small-model calls so Gemma has the box to itself. Large-story requests send `think: false` and `keep_alive: 0` (VRAM discipline); the small model stays warm 30m.
- **Prompt:** `NarrativeDirector.build_campaign_bible_prompt()` is a single-pass prompt with hard constraints (Zenith/Aurelia/Vanguard anchor, no future-faction reveals, Kaelen public mask), a deterministic creative lane picked by hashing the campaign seed across 7 lanes, a hand-written anti-motif block, and idea-memory context from `CampaignIdeaMemoryStore.campaign_bible_prompt_context(32)`.
- **Repair + validation:** `_repaired_generated_campaign_bible()` fixes mechanical drift (key aliases, object→array, rumor-trail ID/clue cleanup, trigger ID cleanup, punctuation junk, vague Kaelen role drift, future-faction payoff leaks). `_validate_campaign_bible_shape()` hard-rejects missing fields and an explicitly wrong public Kaelen role.
- **Consumption:** `CampaignBibleStore.replace_bible()` commits; `StoryManager.seed_story_state_from_bible()` copies the bible spine into living `story_state` (first arc → `active_tensions`, later outline beats + mystery → `player_does_not_know_yet`, clue templates → `pending_hooks`, `kaelen_angle` → `kaelen_hidden_angle`). Chapter advance consumes the bible's reserve; when exhausted, `_request_story_horizon_expansion()` calls Gemma to append (retry once, then a loud, counted procedural fallback).
- **Small-model feed:** `LLMInterface.campaign_bible_context_text` (= `CampaignBibleStore.prompt_context()`) and `story_state_context_text` (= `StoryManager.get_story_context_block()`) are prepended to dialogue/contract/chatter prompts.
- **Memory:** `CampaignIdeaMemoryStore` fingerprints arcs, rumor trails, banned repeats, and style rules (512-idea cap) and feeds them back as "avoid repeating" context.

### Strongest parts (keep these)

1. **The mandatory story gate.** No fake fallback bible can start the game; failures are stored as explicit statuses. This matches the fallbacks-are-failures policy and is the correct spine for everything below.
2. **Repair-then-validate layering.** Mechanical drift is absorbed; semantic violations still reject. The `think: false` fix made this cheap (3/3 valid, ~21s in the patched-prompt run).
3. **Code-authored diversity levers.** Deterministic lanes + static anti-motif block solved motif collapse without a second LLM pass — the test evidence (`claude_critique_and_recommendations.md`) shows this beats a model-authored "uniqueness brief."
4. **Bible-as-reserve, state-as-consumer.** `story_state` consuming outline/arcs/trails with indices, plus append-only horizon expansion that never retcons, is a sound long-term shape.
5. **Two-tier secret handling exists in embryo:** `kaelen_angle` and `player_does_not_know_yet` are excluded from `get_story_context_block()`.

### Fragile parts / shortfalls

1. **Secret leak via `prompt_context()` (the big one).** `CampaignBibleStore.prompt_context()` includes `long_term_reveal`, the full **rumor trail payoff**, and the act-1 outline — and GameRoot pipes that verbatim into `campaign_bible_context_text`, which reaches nearly every small-model prompt. Qwen can (and eventually will) paraphrase the campaign twist into dock gossip in hour one. The kaelen_angle discipline exists, but the *campaign-level* secrets have no equivalent public/private split.
2. **`_update_kaelen_mood()` sends the hidden angle to the small model.** The prompt says "do not repeat it," but the response is stored into `kaelen_current_mood` unchecked — a chatty completion could park a paraphrase of the secret in a field that *is* prompt-safe.
3. **Thin bible.** Exactly one story arc, one rumor trail, one trigger, three act-1 beats. Chapters exhaust the reserve fast, so campaigns lean on horizon expansion (a weaker, less-context call) early. There is no act structure beyond "act 1," no per-faction pressure, no Kaelen hint plan.
4. **No retry-with-errors on bible failure.** A validation failure marks `generation_failed` and stops; `campaign_bible_generation_requested_slots` prevents automatic re-request for the slot. One flaky sample can strand a new campaign at the gate until manual recovery.
5. **Regeneration triggers are decorative.** Only `triggers[0]` is ever used, and its `metric`/`threshold` are never evaluated — hook exhaustion is the real trigger. The schema promises reactivity the runtime doesn't deliver.
6. **Rumor trails have no payoff delivery.** Clue templates become generic `pending_hooks`; `discovery_type`, `rarity`, and `payoff` are never surfaced. The one mandated "hidden discovery / endgame easter egg" trail silently degrades into two ordinary hooks.
7. **Anti-repeat is exact-fingerprint only.** Idea memory dedups by SHA-256 of the summary; "The Zenith Paradox" vs "The Zenith Drift" both pass. No string-similarity check on titles/reveals against prior campaigns (the exact collapse the tests found).
8. **Repairs are silent.** Nothing records *which* repairs fired, so a slow drift in model behavior (e.g., every response needs the Kaelen role rewrite) is invisible in diagnostics.
9. **Lane is not stored.** The creative lane is recomputed from the seed at prompt time but never written into the bible, so the debug panel and idea memory can't reason about lane coverage across campaigns.
10. **Player choice memory is one flat list.** `player_knows` records revealed truths, but nothing records *choices* (who the player sided with, contracts refused, factions angered), so consequences can't compound.

### Where boring/invalid/lore-breaking stories can still slip through

- A generated `opening_situation` that contradicts the fixed tutorial (e.g., implies the player is mid-crisis or owns a fleet) — nothing validates tutorial compatibility or the one-Reaver first combat rule.
- `act_1_outline` beats that name future factions — the payoff leak repair only scans rumor payoffs.
- Same-lane campaigns back to back for players who reroll seeds rapidly (hash can collide on lane), with no memory that lane N was just played.
- A `banned_repeats` list the model half-ignores — it's stored but never enforced against the *same* response that produced it, nor against future titles by similarity.

---

## 2. Long-Term Story Architecture

Evolve from "one bible document" into a **layered narrative director**: a fixed hidden spine (bible), a living public state (story_state), and derived per-consumer context blocks. Everything below is append-only over the current schema — no retcon of existing saves (use `_migrate_legacy_bible()`-style backfill).

### 2.1 Campaign bible (the hidden spine)

Keep it the single source of truth, generated once, extended by horizons. Grow it in these directions:

- **`factions` triad:** one-line *problem* strings for Zenith, Aurelia, Vanguard (per the critique doc's answer #7). Cheap (3 short strings), unlocks faction-flavored contracts/chatter without extra calls.
- **`acts`:** replace the lone `act_1_outline` with an array of acts, each `{name, theme, beats[3], escalation, exit_condition}`. Only Act 1 needs full beats at generation time; Acts 2/3 can be `theme + escalation` sketches that a horizon call fleshes out when Act 1 nears its exit. This keeps the startup call small while giving campaigns a real shape (setup → pressure → consequence).
- **`kaelen_hint_plan`:** see §5.
- **`creative_lane`:** store the lane name/guidance used, for debug and cross-campaign lane rotation.
- **`public_summary`:** a model-written 2-3 sentence *player-safe* synopsis (no reveal, no payoffs) — becomes the root of the public context block instead of leaking the real fields.

### 2.2 Act structure & story arcs

- StoryManager's `chapter` counter stays, but chapters map into acts: an act exits when its beats are consumed *and* its `exit_condition` metric is met (e.g., "player has visited a second system", "one faction pressure ≥ hostile").
- Arcs get a lifecycle: `dormant → active → resolving → resolved/abandoned`, persisted in story_state. `active_tensions` becomes a *projection* of active arcs rather than a free string list, so an arc can be referenced by id from contracts, rumors, and the debug panel.

### 2.3 Rumor trails (make the payoff real)

- Persist per-trail progress in story_state: `{trail_id, clues_delivered[], state: unstarted|in_progress|payoff_ready|paid_off}`.
- Clue delivery stays through the existing channels (lounge rumors, dock chatter, contract flavor) but stamps the trail id, so hearing clue 2 requires having heard clue 1.
- When all clues are delivered, the trail's `discovery_type` maps to a concrete game hook: `secret_route` → a hidden gate/POI flag, `rare_upgrade` → a special vendor item, `endgame_easter_egg` → a flagged anomaly, `faction_secret` → a story beat + reputation event. This connects to the planned anomaly-data-core delivery system.
- `rarity` gates how often clues surface (legendary trails drip slowly across systems).

### 2.4 Faction pressure

- Add `faction_pressure` to story_state: per-faction scalar (-3..+3) plus a one-line "current posture" string derived from the bible's faction problems + player actions (kills, contracts completed/refused, cargo seized).
- Pressure feeds: contract mix (hostile faction offers fewer/riskier jobs), chatter tone, encounter spawn flavor, and eventually the Segment-4 difficulty scaling need (generated systems want NPC pressure anyway).

### 2.5 Gate travel story expansion

- Gate arrival is the canonical "reveal" moment (matches `faction_reveal_rule`). On first arrival in a new system, a `system_story_pack` large-story call (already a capability) generates that system's local situation *constrained by* the bible: which arc escalates here, which trail drops a clue here, which frontier faction (from `ensure_generated_frontier_factions`) steps onstage.
- Because it's a transition moment, the large model can load (`keep_alive: 0` still fine) behind the jump effect — natural loading screen.

### 2.6 Recurring clues & player choice memory

- Add `player_choices` to story_state: append-only list of `{choice_id, description, faction_deltas, timestamp}` recorded at decision points (contract accepted/refused/betrayed, trail payoff spent vs. sold, faction sided with).
- Horizon-expansion prompts get a compact digest of choices ("player has twice sided with Aurelia; refused all Vanguard combat work") so appended story reacts to who the player has been, not just what remains.

### 2.7 Procedural contracts that reflect the story

- Contract generation already receives the story blocks; make it *causal*: each generated contract stamps `because` (from `get_current_because()`), optional `story_hook_ref` (exists today), optional `trail_id`, and `faction_pressure_snapshot`. Completing them feeds back into pressure and trail progress — the loop that makes the world feel like it noticed.

### 2.8 Small-model context blocks & debug visibility

Covered in §6 and §8 respectively — the architectural rule is: **small models only ever see derived, player-safe projections; the raw bible is director-only.**

---

## 3. Making Every Game Feel Unique

Variety comes from **deterministic code-side rotation + memory-driven bans**, not from asking the model to "be creative" (the tests proved temperature alone does nothing).

### 3.1 Rotating creative lanes, done properly

- Keep the 7 lanes; add 3-5 more over time (relief/aid logistics, labor dispute, media/propaganda war, quarantine/plague scare, cult-of-personality commerce). Each lane should imply different *player pressure* (see 3.5).
- **Rotate against history, not just seed hash:** record the lane in the bible and in idea memory (`category: "style_rule"`, tag `creative_lane`). At prompt build, exclude the last 2-3 used lanes before hashing the seed into the remainder. Same seed still → same lane (determinism preserved per-seed), but consecutive campaigns can't repeat a lane.
- Optionally add a **lane modifier** axis rotated independently (scale: personal ↔ system-wide; texture: paperwork ↔ violence; clock: slow rot ↔ imminent deadline). 10 lanes × 3 modifiers ≈ 30 distinct feels before any model sampling.

### 3.2 Avoiding repeated titles / reveals / motifs

- **Similarity gate (code, no LLM):** on parse, compare `campaign_title` and `long_term_reveal` against the last N stored in idea memory using normalized token overlap (strip stopwords, compare word sets; flag ≥ ~60% overlap or shared distinctive bigram like "Zenith X"). Failing similarity = *risky* → retry with the offending title quoted in the prompt ("Do not title it X or anything similar").
- Keep growing the static anti-motif paragraph from real observed collapses; it's the cheapest lever and already proved out (Zenith-noun titles, Kaelen-as-AI, Great Silence/Collapse).
- Feed the model's own `banned_repeats` back through idea memory (already wired) — but also *enforce* them: a title/reveal that matches a banned repeat is a validation warning → retry.

### 3.3 Campaign idea memory (extend, don't rebuild)

- Add categories: `campaign_title`, `reveal`, `creative_lane`, `kaelen_hint_style`, `opening_type`. Store one entry per campaign for each at bible-accept time (extend `remember_campaign_bible()`).
- Add a `query_recent(category, n)` helper so the similarity gate and lane rotation read structured history instead of parsing summaries.

### 3.4 Faction conflict templates & story modes

- The lane already implies a mode (economic / political / criminal / ecological / salvage). Add a small code-side table mapping lane → which of the three anchor factions is *stressed*, *opportunist*, and *bystander* this campaign, rotated per seed. The prompt states these roles; the bible's `factions` triad fills in the specifics. Result: even two criminal-economy campaigns differ in who's dirty.

### 3.5 Different kinds of mysteries & player pressure

Ask the prompt to pick (or rotate code-side) one **mystery shape** — whodunit (known crime, unknown actor), whatisit (known actor, unknown scheme), whereisit (missing thing/person), whyisit (known event, hidden motive) — and one **pressure type** — debt clock, reputation squeeze, scarcity, protection dependency, legal jeopardy. Store both as bible fields so contracts and chatter can reference them consistently.

### 3.6 Different Act 1 openings

Rotate an `opening_type` enum: broke-and-hungry (current default), inherited-a-problem, owed-a-favor, witnessed-something, wrong-place-wrong-time, small-win-gone-sour. All must remain tutorial-compatible (player broke, one starter hostile Reaver, first mission simple) — the opening changes *why* the tutorial mission matters, never *what it mechanically is*.

### 3.7 Different gate-horizon teases & rumor payoffs

- Each campaign picks a **horizon flavor** for what gates hint at: industrial frontier, lawless margin, quarantined region, corporate blackout zone, salvage graveyard. Stored in the bible; `system_story_pack` calls must honor it.
- Rotate rumor-trail payoff *kind* against idea memory so consecutive campaigns don't both end in, say, `rare_upgrade`.

### 3.8 Different Kaelen hint styles

Rotate a `kaelen_hint_style` (see §5.4): deflecting-with-jokes, over-precise-details, selective silence, contradictory small-talk, too-good-information. Stored in the bible, surfaced only as *style guidance* to the small model — never the content of her secret.

---

## 4. Keeping Rules In Place — Validation & Repair Tiers

Three explicit tiers, each with a diagnostics trail. Every repair that fires should be recorded (`GenerationDiagnostics.record_event("campaign_bible", "repair_applied", ...)` with the repair name) so drift is visible.

### Tier 1 — Safe mechanical repairs (apply silently, log always)

Current set stays: key aliases; single object → array; string → single-item array; rumor trail id/`clue_count`/`discovery_type`/`rarity` normalization; trigger id/metric/action/threshold defaults; mojibake/punctuation cleanup; padding short clue lists with neutral clue text; wrapping a *vague* Kaelen role into the broker mask; rewriting rumor payoffs that literally say "hidden/future faction".

Add:
- Trimming over-length strings at sentence boundaries (140/180/220-char fields).
- Coercing numeric strings to numbers for `threshold`/`clue_count`.
- Dropping unknown extra keys (record them — they're a model-drift signal).

**Rule of thumb:** a safe repair never invents story content and never changes meaning — it only fixes *shape*.

### Tier 2 — Risky repairs → retry instead

These change meaning, so don't repair — **retry once with the specific validation errors appended to the prompt** (the Kaelen-intro self-critique retry pattern already in the codebase):

- Kaelen's public role is explicitly wrong (mechanic/scientist/commander/prophet/AI/archive/failsafe) — today this hard-fails with no retry; it should retry first.
- Title/reveal fails the similarity gate or matches a banned repeat.
- Act-1 beats or opening_situation name a future faction or contradict tutorial constraints (more than one hostile, player not broke, player mid-crisis).
- `kaelen_angle` merely restates the public role (empty secret) — currently silently replaced with a canned line by `_repair_kaelen_angle()`; a canned secret is a fallback by another name. Retry; only use the canned line if the retry also fails, and log it as a fallback.
- Missing whole optional-ish sections (e.g., arcs present but all summaries empty).

Retry prompt addition: quote the exact failing field + reason + a one-line correction instruction. One retry, maybe two for the startup-critical bible; after that, Tier 3.

### Tier 3 — Hard failures → block game start (bible) or count-and-fallback (expansion)

- Response envelope/JSON unparseable after retries.
- Required fields still missing/empty after repair + retries.
- Kaelen public role still wrong after retry.
- Campaign-id/schema mismatch on commit.

For the campaign bible these keep the existing behavior: `mark_generation_failed`, gate stays closed, Ollama-recovery UI path. **Improve:** allow automatic re-request on next launch/slot activation (clear `campaign_bible_generation_requested_slots` on failure) so one bad sample doesn't permanently strand a campaign behind a manual button.

For horizon expansion, keep retry-once → loud counted procedural fallback (existing `_use_story_horizon_expansion_fallback`), since mid-game must not stall.

### Specific examples

| Input problem | Tier | Action |
|---|---|---|
| `"rumor__trails"` key | 1 | alias → `rumor_trails` |
| `story_arcs` is an object | 1 | wrap in array |
| payoff says "reveals the hidden faction Krellax" | 1 | rewrite to unnamed outside power (named-leak variant of existing repair) |
| title "The Zenith Paradox", last campaign was "Zenith Drift" | 2 | retry with anti-title instruction |
| `kaelen_rule`: "publicly a scientist" | 2 → 3 | retry; still wrong → block |
| opening says player commands a mercenary wing | 2 | retry citing tutorial constraint |
| `{"thought": "..."}` only | 3 (should no longer occur with `think:false`) | parse fail → retry → block |

---

## 5. Kaelen System

Design principle: **the code enforces the mask and the secrecy; the story supplies the secret.** Kaelen's hidden truth can be anything; it is never fully solved; publicly she is only ever broker / fixer / contract handler.

### 5.1 Bible fields for Kaelen

- `kaelen_rule` (exists) — public mask statement. Player-safe.
- `kaelen_angle` (exists) — director-only: what she secretly knows/did *this campaign*.
- `kaelen_hint_plan` (new, director-only) — 3-5 escalating hint fragments derived from the angle, each a *player-safe surface observation* ("she pays dock fees for a hauler she never mentions"), ordered mild → unsettling. These are what the player can actually encounter; the angle itself never leaves the director layer.
- `kaelen_hint_style` (new, player-safe as *style*) — how she deflects this campaign (§3.8).
- `kaelen_never_reveal` (new, director-only) — one line naming what must stay unresolved even at full trail completion, so horizon expansions know where the line is.

### 5.2 What the player can know vs. what only the director knows

- Player-visible: mask, mood, hint style, any hint fragments already *delivered* (once delivered they move to `player_knows`), and her observable behavior in quests.
- Director-only, forever: `kaelen_angle`, undelivered hint fragments, `kaelen_never_reveal`, and any horizon-expansion notes about her. Full truth is never generated as a resolvable fact — the angle is deliberately a *fragment* ("what she knows or did"), not an identity dossier, and validation should reject an angle that reads like a complete explanation ("Kaelen is actually …" → risky-repair retry asking for something more partial).

### 5.3 What the small model can see

Only the **Kaelen-safe block** (§6): public mask, current mood (2-4 words), hint style, delivered hints. Two current gaps to close:

1. Replace the direct-angle mood prompt in `StoryManager._update_kaelen_mood()`: derive mood from *hint plan stage + arc state* instead of sending the raw angle to qwen. If the angle must inform mood, do it in the *large-model* horizon/system-pack call (which is already director-privileged) and store only the mood word.
2. Add an output guard wherever a secret was in-prompt: reject/regenerate the response if it shares distinctive tokens with the secret text (cheap word-overlap check), and log a leak event.

### 5.4 Feeling different across campaigns without breaking the role

The variation axes are all *around* the fixed mask: hint style (§3.8), mood arc (guarded → cryptic → almost-candid → withdrawn, paced by act), what she jokes about (lane-appropriate humor), which faction she quietly favors (one bible line, hints only), and how her hints escalate (hint plan content). Rotate hint style + favored faction against idea memory. Her voice (af_bella) and public function never change — that constancy against shifting undertones *is* the character.

### 5.5 Preventing accidental lore leaks

- Never place `kaelen_angle`, hint-plan remainder, or `kaelen_never_reveal` in any string that reaches `campaign_bible_context_text`, `story_state_context_text`, or any small-model prompt (today only `get_story_context_block()` honors this; `prompt_context()` must too — §6).
- Hint delivery is code-driven: StoryManager picks the next undelivered fragment at a pacing gate (chapter advance, trail progress) and hands the small model *that fragment only*, as text to paraphrase in-character.
- Leak tests in §9 make this a regression-proof invariant rather than a convention.

---

## 6. Small LLM Context Strategy — Derived Context Blocks

Replace the two monolithic strings (`campaign_bible_context_text`, `story_state_context_text`) with a **ContextBlockBuilder** (new class) that derives named, per-consumer blocks from bible + story_state. Rule: blocks are built from *player-safe projections*; secrets exist only in the director layer. Each block is short (a few lines) so small-model prompts stay lean.

| Block | Contents | Consumers |
|---|---|---|
| **public_campaign** | `public_summary`, tone, humor rule, address rule, current act name/theme | all small-model calls (replaces today's `prompt_context()` — drops `long_term_reveal`, payoffs, outline) |
| **current_act** | act theme, active arc one-liners (`active_tensions`), current `because` | quest/contract generation, agent handoffs |
| **faction_pressure** | per-faction posture line + pressure sign | contracts, chatter, taunts, agent lines |
| **kaelen_safe** | mask, mood, hint style, delivered hints only | `kaelen_line`, intro/quest handoffs |
| **rumor_clue** | the *single* next clue/hint fragment to deliver, its trail title, delivery voice | lounge rumors, dock gossip, station contacts |
| **do_not_reveal** | short imperative list: "never mention: future faction names, campaign twist, Kaelen's private business…" (generic phrasing — never quote the secrets themselves) | appended to every small-model call |
| **contract_generation** | current_act + faction_pressure + `because` + hook ref + economy nouns (lane-appropriate cargo/crime words) | contract/mission generation |
| **combat_chatter** | tone, faction posture of the enemy, one active tension | taunts, combat barks |
| **station_gossip** | rumor_clue or foreshadow + station/faction display names | gossip, background chatter, public boards |
| **hidden_director_notes** | `kaelen_angle`, undelivered hints, reveal, payoffs, `player_does_not_know_yet` | **large-model calls only** (horizon expansion, system_story_pack) + debug panel |

Implementation notes:

- `LLMInterface` keeps one cached string per block, refreshed by the same events that refresh context today (`_push_context_to_llm()`, `_refresh_llm_campaign_bible_context()`); each request site picks blocks by capability instead of always prepending both monoliths. `CAPABILITY_PROFILES` in `LocalModelGateway` is the natural place to also map capability → block set.
- The **do_not_reveal** list is generic by design: telling qwen "don't mention X" *by naming X* is itself a leak vector; the list names *categories*, and the real secrets simply never enter the prompt.
- `hidden_director_notes` going to Gemma is acceptable: large-story calls are director-privileged, transition-timed, and their outputs pass repair/validation before anything reaches the player.

---

## 7. Feature Roadmap

### Immediate next steps (this week; low risk, high leverage)

1. **Stop the public-context leak.** ✅ **DONE (2026-07-02).** Added `CampaignBibleStore.public_prompt_context()` — an allowlist projection (title, logline, opening, tone, core pressure, Kaelen public rule, faction-reveal/humor/address rules) that excludes `main_mystery`, `long_term_reveal`, `act_1_outline`, `story_arcs` summaries, rumor-trail payoffs/hint themes, and horizon machinery. New bible fields default to private. `prompt_context()` kept as the full view; `director_context()` added as its clearly-named alias for debug + large-model use. `GameRoot._refresh_llm_campaign_bible_context()` and the DevPanel snapshot now feed the public block; the DevPanel "Prompt Block" label notes it's player-safe (the raw-JSON box above still shows secrets). Leak test added in `run_campaign_bible_store_tests.gd` (`_test_public_prompt_context_excludes_secrets`), passing.
   *Note vs. original scope:* also treated `main_mystery` as director-only — it's seeded into `player_does_not_know_yet`, so it was leaking too. *Files touched:* `CampaignBibleStore.gd`, `GameRoot.gd`, `DevPanel.gd`, `tests/persistence/run_campaign_bible_store_tests.gd`.
2. **Fix `_update_kaelen_mood()` leak vector** (§5.3): ✅ **DONE (2026-07-02).** Added `StoryManager.mood_leaks_secret()` — rejects any candidate mood sharing a distinctive (long, non-stopword) token with the hidden angle, or too long to be a real 2-4 word mood. On a block, keeps the prior mood and records a `kaelen_mood`/`leak_blocked` diagnostics event. Pure static helper + unit tests in `run_story_manager_hook_tests.gd`. *Chose the output-guard option, not full re-derivation:* deriving mood from hint-plan stage/arc state (the cleaner fix) needs the Kaelen hint plan, which is plan item #12 — so this is the net until then. *Files touched:* `StoryManager.gd`, `tests/story/run_story_manager_hook_tests.gd`.
3. **Retry-with-errors for the bible** + clear the requested-slot guard on failure. ✅ **DONE (2026-07-02).** Two layers: (a) `LLMInterface` retries once (`CAMPAIGN_BIBLE_MAX_ATTEMPTS = 2`) when a 200 response fails to parse/validate, appending the specific errors via new `NarrativeDirector.validation_correction_notes()` + a `correction_notes` param on `build_campaign_bible_prompt`; priority stays active across the retry, HTTP/connection failures still return immediately with their own recovery, and a `validation_retry` diagnostics event is recorded. (b) `GameRoot._on_campaign_bible_generation_result` erases `campaign_bible_generation_requested_slots[active_campaign_slot_id]` on failure so a later activation/relaunch re-requests. No double-request race — `campaign_bible_generation_in_flight` stays true across the internal retry (single callback). *Tests:* correction-notes formatter + retry-prompt injection in `run_narrative_director_tests.gd`. *Files touched:* `NarrativeDirector.gd`, `LLMInterface.gd`, `GameRoot.gd`, `tests/ai/run_narrative_director_tests.gd`.
4. **Repair telemetry.** ✅ **DONE (2026-07-02).** Repair functions accumulate the name of each repair that actually fired into an optional array; `parse_campaign_bible_response` surfaces it as `result.repairs`, and `LLMInterface` logs a `repairs_applied` diagnostics event when non-empty. Pure functions stayed testable — telemetry lives at the boundary, not inside the static repair helpers. Records `key_alias:*`, `object_to_array:*`, `string_to_array:*`, `kaelen_public_role_masked`, `kaelen_angle_defaulted`, `rumor_payoff_faction_leak_masked`. Tests in `run_narrative_director_tests.gd`. *Files:* `NarrativeDirector.gd`, `LLMInterface.gd`.
5. **Store `creative_lane` in the bible** and surface it in DevPanel. ✅ **DONE (2026-07-02).** `_normalized_campaign_bible` records the seed-derived lane as an optional `creative_lane` field; DevPanel status line + raw JSON show it. Test added. *Files:* `NarrativeDirector.gd`, `GameRoot.gd`.

### Near-term (next couple of weeks)

6. **Title/reveal similarity gate** (§3.2) with retry. ✅ **DONE (2026-07-02).** Landed in three pieces: (a) pure `NarrativeDirector.is_text_too_similar()`/`text_similarity()` — distinctive-word Jaccard ≥ 0.6 OR shared distinctive first word (catches "Zenith X" collapse); (b) `CampaignIdeaMemoryStore` now stores `campaign_title`/`reveal` per campaign and exposes `query_recent(category, n)`; (c) `GameRoot` passes recent titles/reveals as `motif_history` into generation, and `LLMInterface` retries once on a near-duplicate (via `motif_collision_note`) but **accepts** a collision on the final attempt rather than blocking game start. Diagnostics: `motif_retry`, `motif_collision_accepted`. Tests across all three files. *Note:* banned-repeat enforcement (the model's own `banned_repeats` list) deferred — the similarity gate against real history is the higher-value half. *Files:* `NarrativeDirector.gd`, `CampaignIdeaMemoryStore.gd`, `LLMInterface.gd`, `GameRoot.gd`.
7. **Faction triad in the bible** + `faction_pressure` state + block. ✅ **DONE (2026-07-02).** *Part A:* bible carries `factions: {zenith, aurelia, vanguard}` one-line problems (player-safe); prompt asks for it, `_repair_factions` guarantees the triad (accepts per-faction object form, fills placeholders, logs telemetry), `CampaignBibleStore` defaults + optional migration backfill (no forced regeneration), lenient Dictionary validation, and both context views surface the problems. *Part B:* `seed_story_state_from_bible` seeds `faction_pressure` per anchor (neutral scalar + posture from the problem); `get_story_context_block` appends a player-safe "Faction pressure" line (neutral/rising/easing sign); `adjust_faction_pressure(faction, delta)` is the clamped −3..3 write path for later gameplay. Tests across NarrativeDirector, bible store, and seed suites. *Deferred:* gameplay actually *writing* pressure (kills/contracts/seizures) — that lands with the loops that consume it. *Files:* `NarrativeDirector.gd`, `CampaignBibleStore.gd`, `StoryManager.gd`, `StoryStateStore.gd`.
8. **Lane rotation against history + opening_type/mystery-shape/pressure-type rotation** (§3.1/3.5/3.6). ✅ **DONE (2026-07-02).** *Part A:* three salted per-seed axes (`OPENING_TYPES`, `MYSTERY_SHAPES`, `PRESSURE_TYPES`) injected as prompt guidance (with a tutorial-safety guard) and stored as `opening_type`/`mystery_shape`/`pressure_type`. *Part B:* `_creative_lane_for_seed` takes excluded lane names and picks from the remaining pool; `GameRoot` passes the last 2 lanes (`query_recent`) as a transient `baseline["_recent_lanes"]` that both the prompt builder and normalizer honor (normalizer strips it before saving); `creative_lane` now recorded in idea memory so history exists. No LLMInterface signature changes. Tests in `run_narrative_director_tests.gd`. *Files:* `NarrativeDirector.gd`, `CampaignIdeaMemoryStore.gd`, `GameRoot.gd`.
9. **ContextBlockBuilder** (§6) replacing the monoliths, capability→block map. *Files:* new `scripts/ai/ContextBlockBuilder.gd`, `LLMInterface.gd`, `LocalModelGateway.gd`. *Risk:* medium (touches many prompt sites — migrate one capability at a time, contracts first). *Test:* per-block leak tests (§9). *Feel:* chatter/contracts reference the act and factions specifically instead of generic space talk.

### Medium-term systems

10. **Rumor trail progress + payoff delivery** (§2.3), wiring `discovery_type` to real hooks (anomaly/data-core system is the natural first payoff). *Files:* `StoryManager.gd`, new `RumorTrailState` in story state store, quest/anomaly systems. *Risk:* medium-high (crosses into gameplay systems). *Test:* clue ordering, payoff fires exactly once, save/load persistence. *Feel:* chasing a rumor across three stations and finding something real is the "alive" moment.
11. **Acts array + act exit conditions** (§2.2) with horizon calls fleshing out the next act sketch. *Files:* `NarrativeDirector.gd`, `CampaignBibleStore.gd`, `StoryManager.gd`. *Risk:* medium (pacing bugs). *Test:* simulated hook-resolution runs advance acts sanely; no empty-slate chapters. *Feel:* campaigns escalate instead of drifting.
12. **Kaelen hint plan + paced delivery + hint-style rotation** (§5). ✅ **DONE (2026-07-02).** *Part A:* bible carries `kaelen_hint_plan` (director-only surface observations), `kaelen_hint_style` (player-safe), `kaelen_never_reveal` (director-only), with prompt constraint, `_repair_kaelen_hints`, normalize copy, and leak-safety by allowlist (store leak test extended). *Part B1:* `seed_story_state_from_bible` seeds `kaelen_hidden_hints` (excluded from the context block) + `kaelen_hint_style`; `deliver_next_kaelen_hint()` pops hints in order into the player-safe delivered list. *Part B2:* `_update_kaelen_mood` rewritten to derive mood from delivery stage + style — **the angle is no longer sent to the small model at all**, which fully closes the item-#2 leak vector (the `mood_leaks_secret` guard stays as belt-and-suspenders). *Deferred:* hint-style *rotation against idea memory*, and wiring `deliver_next_kaelen_hint()` into an actual delivery gate (chapter advance / trail progress) — the mechanism is ready. *Files:* `NarrativeDirector.gd`, `StoryManager.gd`, `StoryStateStore.gd`.
13. **Player choice memory + choice-aware horizon prompts** (§2.6). ✅ **DONE (2026-07-02).** `record_player_choice(id, description, faction_deltas)` appends a bounded (64) `player_choices` log and applies deltas through the #7 pressure write path (a choice both remembers itself and shifts the world); `player_choice_digest()` folds recent choices into the horizon-expansion prompt so appended story reacts to who the player has been. Tests added. *Deferred:* gameplay call sites that actually record choices (contract sided-with/refused, cargo fenced) — the API + digest + horizon wiring are ready for them. *Files:* `StoryManager.gd`, `StoryStateStore.gd`.
14. **Real regeneration-trigger evaluation** — compute the metrics, honor all triggers, not just `triggers[0]`. ✅ **DONE (2026-07-02).** `_select_regeneration_trigger` picks the first trigger whose live metric is at/under its threshold (falls back to the first valid trigger, `{}` if none); `_regeneration_metric_value` computes `active_story_arcs_remaining` / `rumor_trails_remaining` / `prepared_systems_remaining` from bible reserve minus consumed index (`major_arc_state` reports 0 until a numeric arc model exists). Wired into `_request_story_horizon_expansion` so the appended content type matches what actually ran out. Tests added. *Files:* `StoryManager.gd`.

### Long-term dream features

15. **System story packs on gate travel** (§2.5) — per-system mini-bibles constrained by the campaign bible; frontier factions step onstage with generated agendas tied to arcs. (Pairs with the Segment-4 playtest need for NPC ships/variety.)
16. **Consequence engine:** faction pressure thresholds trigger authored-shape events (embargo, bounty on player, station lockdown) with generated flavor.
17. **Cross-campaign meta-memory:** idea memory already spans campaigns; add a "previous pilots" conceit — rumors occasionally reference *your last campaign's* resolved story as in-world history.
18. **Kaelen long game:** hint fragments that only pay off two campaigns later (bounded by `kaelen_never_reveal` — the truth still never lands).

---

## 8. Debugging & Designer Tools (DevPanel Story tab)

The Story Debug tab already shows: status, "Overarching Story Gemma Wrote", input prompt, raw bible JSON, bible prompt block, live story-state block, bridge status, force-dock-rumor button, Ollama recovery, and full story state (marked DEBUG ONLY with `kaelen_hidden_angle`). Extend it into a **Story Director console**, grouped into sub-sections (collapsible, read-only unless marked):

**Generation:**
- Raw LLM prompt *and* raw response for the last bible/horizon call (persist the last raw response alongside the bible for post-hoc debugging).
- Repaired response diff-summary: list of repair names that fired (from the new telemetry).
- Validation errors from the last failed attempt + retry count.
- Creative lane, opening type, mystery shape, pressure type chosen this campaign.

**Context (what the models actually see):**
- One expandable box per derived block (§6), labeled with its consumers — replaces the single "Campaign Bible Prompt Block" box.
- Hidden director notes box, clearly marked, showing `kaelen_angle`, undelivered hints, reveal, payoffs.
- A "leak scan" indicator: run the §9 leak check live over all public blocks; green/red.

**Live story state:**
- Current act + chapter, arc list with lifecycle states, consumed-index gauges (outline/arcs/trails reserve remaining → when the next horizon call will fire).
- Active rumor trails with clue checkboxes (delivered/pending) and payoff type.
- Faction pressure meters (three sliders — *writable* in dev builds for live tuning, per the live-tuning-debug-panel preference).
- Kaelen: mood, hint style, hint plan with delivered/pending flags.
- Idea memory summary: totals by category, last 10 titles/reveals, current banned repeats.
- Regeneration/fallback counters (`regeneration_fallback_count`, leak events, repair counts).

**Contracts:**
- Last N generated contracts with their `because`, hook ref, trail id, and accepted/rejected reason (needs contract-gen to log candidates, not just winners).

**Actions (dev-only buttons):** force chapter advance; force horizon expansion; force next Kaelen hint; regenerate bible (with confirmation — destructive); replay last prompt against Ollama and show the fresh response side-by-side.

---

## 9. Testing Strategy

Follow the existing headless-test pattern (`tests/ai/run_narrative_director_tests.gd`, one at a time, unique `--log-file`). All tests below are offline — fixtures, not live Ollama — except the explicitly-marked live smoke tests.

1. **Bible validation:** golden valid fixture passes; per-field deletion fails with the right error code; enum violations (discovery_type/rarity/metric/action) fail.
2. **Repair behavior:** fixture per repair (aliases, object→array, id cleanup, punctuation, payoff-leak rewrite) → repaired output byte-expected *and* telemetry records the repair name. Negative: meaning-changing drift is *not* silently repaired.
3. **Kaelen public/private separation:** for a fully-populated bible + story state, assert `kaelen_angle` / undelivered hints / `kaelen_never_reveal` strings never appear in any public block, `get_story_context_block()`, or any assembled small-model prompt (walk every capability's block set).
4. **Future-faction leak prevention:** generated frontier faction names must not appear in public blocks or clue text before their system is revealed.
5. **Motif repetition:** similarity gate unit tests ("The Zenith Paradox" vs "Zenith Drift" → flagged; genuinely distinct titles pass); lane rotation never repeats within window; banned-repeat enforcement flags matches.
6. **Small-model context safety:** ContextBlockBuilder snapshot tests — each block contains only its whitelisted fields (schema-driven, so a new bible field defaults to *private* until whitelisted).
7. **Mandatory story gate:** `is_campaign_story_ready()` false for every non-`llm_generated` status; scene entry blocked; failure statuses re-queue generation on next activation.
8. **VRAM/keep-alive:** `generation_body()` asserts `keep_alive: 0` + `think: false` for every large_story capability and 30m for small; timeout table sanity (and revisit the 600s bible timeout — clean runs are ~21s; something like 60-90s with the new retry is more honest).
9. **Contract relevance:** generated-contract path stamps `because`/hook ref; contract prompt contains current act + faction posture; completing a stamped contract resolves the right hook (exists partially — extend).
10. **Horizon expansion:** all three actions parse/normalize; retry-once then counted fallback; expansion never mutates existing arcs/trails (append-only invariant).
11. **Live smoke (manual, one at a time):** scripted batch of 10 real bible generations scoring pass-rate, distinct-title count, lane distribution — the `OllamaTestStories` harness pattern, promoted to a repeatable checklist before releases.

---

## 10. Specific Recommendations (practical list)

### Schema changes (bible, `DOCUMENT_VERSION` bump + backfill migration)
- Add: `public_summary`, `creative_lane`, `opening_type`, `mystery_shape`, `pressure_type`, `horizon_flavor`, `factions: {zenith, aurelia, vanguard}` problem lines, `kaelen_hint_plan[]`, `kaelen_hint_style`, `kaelen_never_reveal`.
- Later: `acts[]` superseding `act_1_outline` (keep the old field, migrate it into `acts[0]`).
- Story state: `faction_pressure`, `rumor_trail_progress[]`, `player_choices[]`, `kaelen_hints_delivered[]`.

### New files/classes
- `scripts/ai/ContextBlockBuilder.gd` — derives all §6 blocks; the only place public projections are assembled.
- `tests/ai/run_context_block_leak_tests.gd` — the §9.3/9.6 invariants.
- (Later) `scripts/story/RumorTrailTracker.gd` if trail logic outgrows StoryManager.

### Additions to existing files
- `CampaignBibleStore.gd`: `public_prompt_context()` / `director_context()` split; migration backfill for new fields.
- `NarrativeDirector.gd`: repair telemetry; similarity gate; retry-with-errors prompt builder; lane-rotation-aware `_creative_lane_for_seed`; new schema fields in prompt + validation.
- `LLMInterface.gd`: bible retry loop; capability→block wiring; leak-guard on any response whose prompt contained a secret.
- `StoryManager.gd`: mood derivation without raw angle; hint-plan pacing; real trigger metric evaluation; choice recording.
- `GameRoot.gd`: feed public block only; clear requested-slot guard on failure.
- `DevPanel.gd`: §8 console sections.

### Validation rules to add
- Kaelen-role violation → retry before hard fail; canned `kaelen_angle` counts as a logged fallback, not a silent repair.
- Title/reveal similarity + banned-repeat enforcement (retry tier).
- Tutorial-compatibility scan of `opening_situation`/act-1 beats (no future factions, single starter hostile, player broke).
- `kaelen_angle` must not read as a complete identity explanation.

### Debug panel additions (top 5 first)
Repair/retry telemetry; per-block context viewers with leak-scan indicator; reserve gauges + fallback counters; Kaelen hint state; last-N contracts with because/acceptance reasons.

### Tests to write first
Leak tests (§9.3), gate tests (§9.7), keep-alive/think assertions (§9.8), similarity-gate units (§9.5), repair-telemetry fixtures (§9.2).

### Open design questions for you
1. **Act count & campaign length:** is a campaign 3 acts and "done" (rolling into a new campaign), or endless with acts as waves? Current code is endless-refill; acts imply an arc with an end.
2. **Payoff weight:** should a `legendary` rumor payoff be allowed to change the sandbox permanently (new gate, unique ship module), or stay cosmetic/economic? Determines how much validation payoffs need.
3. **Choice granularity:** record only faction-visible choices, or also quiet ones (smuggling, salvage ethics)? More granularity = richer callbacks but noisier prompts.
4. **How dark can lanes get?** Quarantine/plague and labor-dispute lanes read heavier than heist lanes — keep the PG-13 dry-humor register everywhere, or let some campaigns be tonally heavier?
5. **Cross-campaign canon:** is the "previous pilots" meta-memory conceit (17) desirable, or should campaigns be hermetically separate worlds?
6. **Bible regeneration UX:** if a player hates their campaign premise, do they get a "reroll story" button (cheap now that generation is ~21s), and does rerolling burn the lane/title into idea memory as banned?
7. **Timeout policy:** drop the 600s bible timeout to ~60-90s with retries, or keep the generous ceiling for slower machines? (Recommend: 90s × 2 retries, configurable.)

---

## 11. Proposed Game Loops (ordered by value-for-time, best ROI first)

Ten loops that add content while plugging into the living story system. Each is designed so the *story director supplies the why* (tensions, lanes, faction pressure, trails) and *existing gameplay systems supply the how* — no loop should feel bolted on. Ordering weighs player-facing value against implementation time, favoring loops that reuse systems that already exist (StoryQuestManager pipeline, contract generation, combat, economy-stores-events work on the current branch).

### Loop 1 — Story-Driven Market Events ("the economy notices the plot")

**The loop:** dock → notice a price spike/shortage on the station board with a one-line story reason → plan a route to exploit it (buy low where the story says surplus, sell high where it says squeeze) → the event decays or escalates based on the arc that caused it → profits fund the next ship goal.

- **Story integration:** every economy event is stamped with an `active_tension`/arc id and a `because` line generated by the small model from the **current_act + faction_pressure** blocks ("Vanguard requisitions have tripled hull-plate prices — someone's expecting trouble"). When the arc resolves, its events unwind — visible proof the world reacted.
- **Systems touched:** the economy/stores/events work already on this branch, `StoryManager` (arc → event mapping), contract flavor text. Mostly data + one mapping table.
- **Why first:** cheapest possible "living world" win — it converts work already in flight into story reactivity, touches no combat/AI, and every trader run becomes narrative. Small LLM cost: one flavor line per event.
- **Feel target:** the player reads a price board and can *infer the plot from the numbers*.

### Loop 2 — Named Bounty Ladder ("someone is behind these raids")

**The loop:** faction agent or Kaelen posts a bounty on a *named* pirate/saboteur generated from the current arc → hunt them via 1-2 location hints (rumor channels) → turn-based fight against a lightly-kitted variant → payout + faction pressure shift → a *bigger* name replaces them, climbing toward the arc's mid-boss.

- **Story integration:** names, motives, and taunts come from **contract_generation + combat_chatter** blocks; the ladder's top name is seeded from the bible's arc summary (a lieutenant of whoever the campaign's pressure points at). Killing ladder targets advances arc state and can deliver a rumor-trail clue as loot.
- **Systems touched:** `StoryQuestManager.begin_quest()` (the debug Reaver quest is literally this loop's skeleton — `_fire_debug_story_quest` proves the pipeline: spawn tagged ship, kill objective, reward, Kaelen voice hook), combat spawn tables, small-model name/taunt generation.
- **Why second:** the full pipeline already exists as a debug path; content cost is a generator + ladder state. Directly feeds the planned single-mega-boss → squads combat roadmap.
- **Feel target:** "I've been hunting this guy for an hour and his taunts reference the cargo I stole."

### Loop 3 — Rumor Trail Investigation ("follow the thread")

**The loop:** overhear a clue in a lounge (existing channel) → the clue names a *place or activity*, not a waypoint ("manifests at Halvorsen Dock don't add up") → go there and do a small verifying action (dock + talk, scan a wreck, buy a record) → next clue unlocks → final clue converts to a payoff: hidden POI, secret route, rare vendor item, or faction secret that shifts pressure.

- **Story integration:** this is §2.3 made into gameplay — the bible's mandated rumor trail becomes the campaign's optional detective spine, and horizon expansion appends fresh trails. Delivery uses the **rumor_clue** block; payoffs route through `discovery_type`.
- **Systems touched:** `StoryManager` trail-progress state (planned), lounge/dock rumor channels (exist), one payoff hook per discovery type (start with just two: `secret_route` and `rare_upgrade`).
- **Why third:** medium cost (progress tracking + payoff wiring) but it's the loop that makes the mystery *playable* rather than ambient — the single biggest "authored feel" payoff in the plan. Ordered after 1-2 only because they reuse more existing code.
- **Feel target:** the player keeps a mental case file and detours mid-haul because a bartender said something that clicked.

### Loop 4 — Salvage Claims & Wreck Forensics ("dead ships tell stories")

**The loop:** combat kills, story events, and arc escalations leave persistent wreck sites → the player salvages parts (income) but occasionally pulls *evidence*: a manifest, a black box, a marked crate → choose: sell it (credits, no questions), hand it to a faction agent (pressure shift + payout), or bring it to Kaelen (rumor-trail clue or hint fragment).

- **Story integration:** evidence items are generated from the **hidden_director_notes**-driven large-model pass at system-pack time (so evidence *actually points at the real plot*), surfaced through the salvage lane. The three-way fencing choice is the cleanest `player_choices` recorder in the game.
- **Systems touched:** salvage mechanics (exist — `salvager_profile` capability, salvage announcements), a small evidence-item table, agent/Kaelen turn-in dialogs (existing conversation UI).
- **Why fourth:** salvage already works; this adds a decision layer + story hook to an existing activity. Cost is mostly the turn-in flows. Also the natural home of the salvage-rights creative lane.
- **Feel target:** every battlefield is a potential lead; the player hesitates before fencing a black box.

### Loop 5 — Contraband Runs & Inspection Pressure ("profitable, until it isn't")

**The loop:** criminal-economy contacts (via Kaelen or shady lounge NPCs) offer high-margin cargo that is illegal *in specific factions' space* → plan a route around patrols or risk inspection at gates/docks → inspections are a quick stakes moment (comply/bribe/run) → success builds a smuggler reputation that unlocks bigger runs; failure costs cargo, fines, and faction pressure.

- **Story integration:** *what counts as contraband is campaign-specific*, derived from the lane and faction problems (in a quarantine campaign it's medical goods; in a debt campaign it's un-repossessed parts). Inspection frequency scales with that faction's pressure — the story literally tightens the checkpoints.
- **Systems touched:** cargo system (exists), a new inspection encounter (dialog + roll, no new combat needed initially), route planner tie-in later, faction pressure.
- **Why fifth:** needs one genuinely new mechanic (inspections), but it creates the game's core risk/reward dial and gives criminal-lane campaigns their signature activity. Medium cost, high texture.
- **Feel target:** sweating a gate queue with a hold full of something you shouldn't have.

### Loop 6 — Anomaly Survey & Data-Core Delivery ("the frontier pays curiosity")

**The loop:** systems (especially generated frontier ones) contain scannable anomalies → surveying yields a *named data core* (already a planned feature) → the core is special cargo with a story-assigned buyer: a faction agent, a station scientist NPC, or Kaelen → delivery pays out and, for rare cores, opens a follow-up beat (a coordinates lead, a trail clue, a one-off quest).

- **Story integration:** core names and what-they-imply come from the system story pack; `endgame_easter_egg` / `hidden_discovery` trail payoffs can *materialize as* anomalies, unifying two systems. Frontier systems get their "reason to explore" (Segment-4 playtest gap).
- **Systems touched:** anomaly spawning (exists — anomaly_event capability), special-cargo delivery flow (planned in memory), small-model buyer dialog.
- **Why sixth:** already on the roadmap in memory notes; this formalizes it as a repeatable loop and chains it to trails. Cost is the special-cargo flow.
- **Feel target:** spotting an anomaly ping off the flight path and deciding the detour is worth it.

### Loop 7 — Faction Pressure Flashpoints ("the cold war gets hot")

**The loop:** faction pressure (from §2.4) crossing thresholds fires *flashpoint events* with authored shapes and generated flavor: an embargo (a station stops trading with a faction), a lockdown (docking checks everywhere), a bounty posted *on the player*, a corridor turning hostile → the player either exploits the disruption (prices, smuggling demand spike — feeds Loops 1 and 5) or works de-escalation contracts to release the pressure → resolution shifts pressure back and pays reputation.

- **Story integration:** flashpoints are the *consequences* engine (§7 item 16) — pressure the player themselves built through contracts, kills, and fencing choices comes back as world state. Every flashpoint is stamped with the arc and choices that caused it, and the small model narrates that lineage in chatter.
- **Systems touched:** faction pressure state (prerequisite), an event table with 4-5 flashpoint shapes, hooks into economy events, spawn tables, and docking flow.
- **Why seventh:** depends on Loop 1 + the pressure system existing, but multiplies both once they do. This is where player choice memory becomes *visible*.
- **Feel target:** "Vanguard put a bounty on me because of that convoy job" — and the player knows exactly which job.

### Loop 8 — Station Regulars ("a bar where somebody knows your name")

**The loop:** each station hosts 2-3 persistent, named lounge NPCs (generated once per campaign, stored) → talking costs nothing but time; regulars remember past conversations and player deeds (choice digest) → relationship tiers unlock: better rumor quality (earlier trail clues), small discounts, occasional exclusive jobs → regulars are also Kaelen-hint carriers ("she was here before you, you know").

- **Story integration:** regulars are the delivery mechanism for **station_gossip** and **rumor_clue** blocks with continuity — the same voice develops a thread across visits instead of anonymous one-shots. Their opinions shift with faction pressure, making them a readable barometer. Phase E (ambient NPC dialogue) from the narrative-foundation survey lands here.
- **Systems touched:** a per-station NPC store (new but small), existing conversation UI, small-model dialog with an NPC-memory context line, choice digest.
- **Why eighth:** pure content/dialog systems — no combat or economy risk — but needs NPC persistence and enough memory plumbing that it lands mid-list. Big warmth-per-token payoff once in.
- **Feel target:** docking somewhere *because* you want to hear what Vess has heard, not because the cargo says so.

### Loop 9 — Distress Calls & Convoy Escort ("the war comes to you")

**The loop:** while flying, story-flavored distress pings arrive (a hauler under Reaver attack, a disabled miner, a faction patrol outnumbered) → responding drops the player into a rescue/escort encounter using the turn-based combat system → outcomes ripple: saved crews become grateful contacts (feeds Loop 8), saved cargo stabilizes a market event (Loop 1), ignoring calls is itself a recorded choice → escort *contracts* become a plannable job type once the reactive version works.

- **Story integration:** who is in distress and who attacked them comes from active tensions and pressure — during a flashpoint, distress frequency rises along the contested corridor. A rescued NPC occasionally hands over evidence (Loop 4) or a clue.
- **Systems touched:** an interruption/encounter spawner tied to travel (new), combat AI for protect-the-target objectives (new behavior — the hard part), the interaction queue (exists) for pacing.
- **Why ninth:** high immersion but the escort-AI and mid-flight encounter framing are genuinely new work with tuning risk (autopilot avoidance interactions). Do it after combat's enemy-kit work lands.
- **Feel target:** the space between stations stops being empty transit.

### Loop 10 — Rare Parts Hunt & Kitbash Progression ("the ship is the trophy cabinet")

**The loop:** signature ship parts (from the kitbash catalog) exist only as loot: bounty-ladder tops (Loop 2), legendary trail payoffs (Loop 3), deep-frontier anomalies (Loop 6), flashpoint auctions (Loop 7) → each rare part is *named and storied* by the system pack ("the coil off the ship that ran the Halvorsen blockade") → installing visibly changes the kitbashed ship and stats → the wishlist of parts becomes the player's long-term itinerary across all other loops.

- **Story integration:** parts carry provenance lines generated at drop time from the arc that produced them — the ship becomes a physical log of the campaign. Drone fitment going parametric (planned) makes swaps meaningful.
- **Systems touched:** kitbash catalog (exists, Vanguard wired), loot/provenance metadata, upgrade UI, drop tables in four other loops.
- **Why tenth:** it's the *meta*-loop — its value scales with how many of Loops 2/3/6/7 exist, so building it last maximizes payoff. Individually it's mostly data + UI, but premature without its feeder loops.
- **Feel target:** a docked stranger asks where you got that engine, and there's a story.

### Priority summary

| # | Loop | Builds on | New systems needed | Cost | Story payoff |
|---|------|-----------|--------------------|------|--------------|
| 1 | Story-driven market events | economy branch (in flight), arcs | event↔arc mapping | S | world reacts to plot |
| 2 | Named bounty ladder | StoryQuestManager, combat | ladder state, name gen | S-M | arcs get faces |
| 3 | Rumor trail investigation | rumor channels, trails | trail progress + payoffs | M | mystery becomes playable |
| 4 | Salvage claims & forensics | salvage, conversations | evidence items, turn-ins | M | choices with fingerprints |
| 5 | Contraband & inspections | cargo, factions | inspection encounter | M | campaign-specific risk dial |
| 6 | Anomaly survey & data cores | anomalies, planned feature | special-cargo flow | M | frontier worth exploring |
| 7 | Faction flashpoints | Loops 1+5, pressure system | flashpoint event table | M-L | consequences made visible |
| 8 | Station regulars | conversation UI, gossip | per-station NPC store | M-L | continuity and warmth |
| 9 | Distress calls & escort | combat, interaction queue | escort AI, travel spawner | L | space feels inhabited |
| 10 | Rare parts hunt | kitbash, Loops 2/3/6/7 | provenance loot metadata | M (after feeders) | the ship tells the story |

Shared design rules for all ten: every loop consumes at least one derived context block (§6) rather than raw bible data; every loop writes at least one thing back (pressure delta, choice record, trail progress, idea-memory entry) so the director can react; and every generated flavor string is stamped with its arc/because for debug traceability (§8).





*End of plan. Sources: `NarrativeDirector.gd`, `LocalModelGateway.gd`, `LLMInterface.gd` (grep), `CampaignBibleStore.gd`, `CampaignIdeaMemoryStore.gd`, `StoryManager.gd`, `GameRoot.gd` (story-gate region), `DevPanel.gd` (grep), `OllamaTestStories/claude_critique_and_recommendations.md`, `patched_production_prompt_status.md`, `20260701_223050_patched_production_prompt/summary.json`.*








