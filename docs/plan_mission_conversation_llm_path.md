# Plan — Build the LLM mission-conversation path

**Written:** 2026-09-10, at the end of a session, for a fresh window to execute.
**Goal:** every fact needed is in this file. Do not re-derive; verify and build.

---

## 1. The finding this exists to fix

Mission dialogue is permanently in its deterministic fallback, and the game has
been correctly reporting that the whole time.

`StoryAgentOfferBuilder._attach_mission_conversation` (`scripts/story/StoryAgentOfferBuilder.gd:105`)
builds every mission conversation with `MissionConversationCompiler.fallback_bundle()`
and then sets, **unconditionally**:

```gdscript
quest["mission_dialogue_bundle_source"] = "deterministic_fallback"
quest["mission_dialogue_bundle_degraded"] = true
quest["mission_dialogue_bundle_degraded_reason"] = "template_safe_emergency_composer"
```

plus a `record_fallback` diagnostic on every mission.

**Verified facts (re-check these first, they are the plan's foundation):**

| Claim | How it was verified |
|---|---|
| `build_prompt()` has **0** external call sites | grep for `CompilerType.build_prompt` / `MissionConversationCompilerType.build_prompt` outside the compiler |
| `parse_bundle()` has **0** external call sites | same method |
| No `mission_conversation` job kind is dispatched | `GameRoot._narrative_cache_payload_for_job` (`GameRoot.gd:4884`) has no such case |
| No `mission_conversation` job kind is gated ready | the `_can_process_*` match near `GameRoot.gd:4486` has no such case |
| `fallback_bundle()` has 2 external call sites | `StoryAgentOfferBuilder.gd:134`, `DialogueBundleValidator.gd:83` |

So the LLM path is **dormant, not broken**. The plan builder, compiler, bundle
validator and causal-visibility check are all live and all exercised — by the
fallback. That is why this survived unnoticed: everything looks healthy except
the one step that was never wired.

---

## 2. What already exists and must be reused

Do not rebuild any of these. They are live, tested, and correct.

| Piece | Path | State |
|---|---|---|
| Prompt builder | `MissionConversationCompiler.build_prompt()` | written, unused |
| Response parser | `MissionConversationCompiler.parse_bundle()` | written, unused |
| Slice planner | `MissionConversationCompiler.plan_slices()` | **built 2026-09-10 (P4-3), tested** |
| Slice prompt | `MissionConversationCompiler.build_slice_prompt()` | built 2026-09-10, tested |
| Slice merge | `MissionConversationCompiler.merge_slice()` | built, never overwrites accepted keys |
| Repair scoping | `MissionConversationCompiler.missing_keys()` | built, tested |
| Slice queueing | `NarrativeCacheScheduler.queue_conversation_slices()` | **built 2026-09-10 (P4-4), tested** |
| Dependency gate | `NarrativeCacheScheduler.dependencies_met()` / `waiting_jobs()` | built, tested |
| Bundle validation | `DialogueBundleValidator.validate_bundle()` | live |
| Causal visibility | `MissionConversationCompiler.validate_causal_visibility()` | live, 1 call site |
| Field contract | `scripts/story/DialogueFieldContract.gd` | built 2026-09-10 (P4-1) |
| Outcome projection | `scripts/story/OutcomeReactionProjector.gd` | built 2026-09-10 (P4-2) |

**Existing tests that must stay green throughout:**

- `tests/story/run_conversation_slicing_tests.gd`
- `tests/story/run_scheduler_slice_tests.gd`
- `tests/story/run_dialogue_field_contract_tests.gd`
- `tests/story/run_outcome_reaction_projector_tests.gd`
- `tests/parse_check_scene_scripts.gd` (334 scripts, 0 failed as of this writing)

---

## 3. The seams to change

Exact locations, found and confirmed on 2026-09-10.

| # | File / symbol | Line (approx) | Change |
|---|---|---|---|
| A | `scripts/ai/LocalModelGateway.gd` `CAPABILITY_PROFILES` | 50 | add `"mission_conversation": "small_dialogue"` |
| B | `scripts/ai/LocalModelGateway.gd` `REQUEST_TIMEOUTS` | 86 | add `"mission_conversation": 25.0` (match `lounge_bundle`) |
| C | `scripts/LLMInterface.gd` | near 1670 | add `request_mission_conversation_slice(prompt, callback)` wrapping `_request_small_inner_text` |
| D | `scripts/GameRoot.gd` `_can_process_*` match | ~4486 | add `"mission_conversation":` → `true` |
| E | `scripts/GameRoot.gd` `_narrative_cache_payload_for_job` | 4884 | add `"mission_conversation":` → new payload builder |
| F | `scripts/GameRoot.gd` (new func) | — | `_mission_conversation_payload_for_cache_job(job)` |
| G | `scripts/story/StoryAgentOfferBuilder.gd` `_attach_mission_conversation` | 105–155 | make the degraded flags CONDITIONAL; queue slices instead of accepting the template silently |

**The model to copy is `"current_station_agent_offer_bundle"`.** It is the closest
live analogue: gated at `GameRoot.gd:4490`, dispatched at `GameRoot.gd:4888`, and
implemented by `_station_agent_offer_payload_for_cache_job` (`GameRoot.gd:4986`).
Read that function end to end before writing F — it shows the required shape,
including the `{"ok": false, "status": "..."}` early-return convention.

---

## 4. Target behaviour

1. A mission offer is built as today, and the **template bundle is kept** as the
   guaranteed floor. Nothing ships without a usable conversation.
2. Slices are queued via `queue_conversation_slices()`: opening first at the
   caller's priority, intent slices one band lower, depending on the opening.
3. Each slice is generated with `build_slice_prompt()`, parsed, and validated.
4. Accepted slices are merged with `merge_slice()`, which never overwrites an
   already-accepted key.
5. When every required key is present and `validate_bundle()` plus
   `validate_causal_visibility()` pass on the assembled result, the quest's
   bundle is replaced and the degraded flags are **cleared**.
6. If any slice fails twice, the template text for that field stays. The
   conversation is then **partly generated**, which is a real improvement over
   wholly templated and must be recorded as such rather than as a failure.

**The floor is the point.** The template path is what makes this safe to build:
at no stage can the player get a conversation with a hole in it.

---

## 5. Slices, in execution order

Each is independently committable and leaves the game working. Stop anywhere.

### S1 — Register the capability (30 min, zero runtime risk)

**Files:** `scripts/ai/LocalModelGateway.gd`

Add `mission_conversation` to `CAPABILITY_PROFILES` (→ `small_dialogue`) and to
`REQUEST_TIMEOUTS` (→ `25.0`).

**Why 4B and not the large model:** the campaign-bible bug (`docs/bugs.md`) shows
the 12B starving small-model dialogue at session start. Mission conversations are
frequent and player-visible; they must not queue behind the large model. This
matches the plan's own P4 row: *"New registered capability `dialogue_field` uses 4B."*

**Test:** new `tests/story/run_mission_conversation_capability_tests.gd` asserting
the capability resolves to the small profile and has a non-zero timeout. Pin the
PROFILE by literal, not by reading the constant back (that is a tautology — it
already bit once, see the P4-3 note in the replayability plan).

**Verify:** parse check green.

---

### S2 — LLM request wrapper (30 min, zero runtime risk until called)

**Files:** `scripts/LLMInterface.gd` (near line 1670, beside `request_lounge_exchange_bundle`)

```gdscript
func request_mission_conversation_slice(prompt: String, callback: Callable) -> void:
    _request_small_inner_text("mission_conversation", prompt, callback)
```

Copy the option shape from `request_lounge_exchange_bundle` — it is the closest
sibling (flat JSON, several string fields).

**Verify:** parse check green. Nothing calls it yet.

---

### S3 — Payload builder, generating ONE slice (2–3 h, the real work)

**Files:** `scripts/GameRoot.gd`

Add `_mission_conversation_payload_for_cache_job(job)`, modelled on
`_station_agent_offer_payload_for_cache_job` (`GameRoot.gd:4986`).

It must:
1. Recover the mission plan, speaker card and conversation plan from the job.
   **Open question — resolve first:** the job needs these. Either carry them on
   the job at queue time (simplest, but they must survive a save/load round trip)
   or re-derive from `quest` by id. Decide before writing code; do not do both.
2. Build the prompt with `build_slice_prompt(mission_plan, speaker_card,
   conversation_plan, job["slice"], safe_context)`.
3. Request generation through S2's wrapper.
4. Parse with `parse_bundle()`; on parse failure return
   `{"ok": false, "status": "response_json_parse_failed"}` — the same status
   string the campaign-bible bug already uses, so the diagnostics stay comparable.
5. Validate the slice's keys only. A slice must not be judged against keys it was
   never asked for.

Then wire D and E so the job kind is gated and dispatched.

**Test:** extend the slicing tests with a fake payload path. Do NOT try to test
the live LLM call headlessly — assert the prompt built, the keys requested, and
the handling of a malformed response.

**Verify:** run the game, accept a mission, confirm one slice is requested and
the conversation still works whichever way that slice goes.

---

### S4 — Assemble and promote (1–2 h)

**Files:** `scripts/GameRoot.gd`, `scripts/story/StoryAgentOfferBuilder.gd`

1. Accumulate accepted slices with `merge_slice()`.
2. When `missing_keys()` is empty, run `validate_bundle()` and
   `validate_causal_visibility()` on the assembled bundle.
3. On success replace `quest["mission_dialogue_bundle"]`, set
   `mission_dialogue_bundle_source = "generated"`, and CLEAR the degraded flags.
4. Change seam G so the degraded flags are set only when the template is actually
   what shipped.

**This is the slice that closes the bug.** Until step 4, every conversation still
reports degraded even when generated.

**Test:** a headless test that feeds known-good slice text through merge →
validate → promote and asserts the flags flip. That path is pure and should not
need a running game.

---

### S5 — Partial generation is a distinct outcome (1 h)

Record three states, not two:

| `mission_dialogue_bundle_source` | Meaning |
|---|---|
| `generated` | every field generated and validated |
| `partial_generated` | some fields generated, some template |
| `deterministic_fallback` | wholly template — the current permanent state |

`partial_generated` must NOT count as a fallback in diagnostics. Recording a
mostly-generated conversation as a failure is how a real improvement gets
mistaken for a regression, and it would make the fallback ledger useless for
judging whether this work succeeded.

---

### S6 — Live verification (needs Abe)

Not a code slice. Accept several missions and confirm:

- conversations still appear, always
- `record_fallback` volume for `mission_conversation_bundle` drops
- no visible latency at the offer moment (the opening is P0 and must not block
  the agent panel opening)

---

## 6. Risks, and what to do about each

| Risk | Why it matters here | Mitigation |
|---|---|---|
| **Latency at the offer moment** | The agent panel opens immediately today because the template is synchronous. A generated opening is not. | Never block the panel. Show the template, swap in generated text when ready, or accept template-only for that view. **Decide this before S3** — it is the difference between a snappy game and a stuttering one. |
| **Large-model contention** | Already an open bug: the 12B starves small-model calls at session start. | S1 puts this on the 4B. If offers are made during bible generation, the scheduler's existing pause gate applies. |
| **Save/load of in-flight slices** | A queued slice whose quest is reloaded may reference a mission that no longer exists. | `DialogueFieldContract.is_still_applicable()` and the scheduler's `discard_stale_jobs()` both exist for this. Use them; do not invent a third mechanism. |
| **A generated line that passes validation but is wrong in character** | The validator checks structure and knowledge, not voice. | `FixedCastLineValidator` and the quality gate (fixed 2026-09-10) apply. Expect to listen to a few in play. |
| **Silently making things worse** | The template path currently never fails. Any generated path can. | S5's three-state source field is what makes a regression visible. Do not skip it. |

**Rollback:** every slice is additive except G. If anything misbehaves, reverting
G alone restores today's behaviour exactly — the template bundle is still built
and still attached at every stage.

---

## 7. Decisions needed before writing code

Answer these first; each changes the shape of S3/S4.

1. **Does the offer wait for the opening, or show template text and swap?**
   Recommendation: **show template, swap when ready.** Never make the player wait
   on a model to open a panel.
2. **How does the job carry its mission plan** — on the job, or re-derived by
   mission id? Pick one. Carrying it is simpler but must survive save/load.
3. **Is a partly-generated conversation acceptable to ship**, or is it
   all-or-nothing? The plan above assumes partial is good and worth recording as
   its own state.

---

## 8. Estimate

| Slice | Estimate |
|---|---|
| S1 capability | 30 min |
| S2 request wrapper | 30 min |
| S3 payload + dispatch | 2–3 h |
| S4 assemble + promote | 1–2 h |
| S5 partial-state accounting | 1 h |
| S6 live verification | Abe, ~30 min in game |

**Total: roughly 5–7 hours of build**, which fits a fresh window with room for
the live verification at the end. S1+S2 are near-free and can be done first to
build momentum; S3 is where the real thinking is.

---

## 9. What "done" looks like

- Accepting a mission produces a conversation whose `mission_dialogue_bundle_source`
  reads `generated` or `partial_generated` rather than `deterministic_fallback`.
- `record_fallback` volume for `mission_conversation_bundle` drops sharply.
- The agent panel opens as fast as it does today.
- `docs/bugs.md` entry "Mission dialogue is permanently in the deterministic
  fallback" can be closed with evidence, not assumption.
