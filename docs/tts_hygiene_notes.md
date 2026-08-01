# TTS Hygiene Notes
_Audit date: 2026-06-21 — covers TTSInterface.gd, GlobalState.gd, LLMInterface.gd_

---

## 1. Words and Faction Names TTS Mispronounces or Spells Out

### Already handled by `normalize_tts_pronunciation()` (TTSInterface.gd:306)
The normalizer lowercases any all-caps word ≥ 3 letters (e.g. `ZENITH` → `Zenith`).
**Exemption list** (reads as letters, intentionally): `AI`, `HP`, `LLM`, `NPC`, `PG`, `ROE`, `SC`, `TTS`, `UI`.

### Known problem cases not yet covered

| Raw text seen in UI / dialogue | What TTS hears | What it sounds like | Fix needed |
|---|---|---|---|
| `INDY Miner` | `INDY Miner` | "Eye-En-Dee-Why Miner" | `INDY` is < threshold — but it's 4 letters, all caps, not in exemption list. Should be added as a special case: spoken as "Indy". |
| `gen_latch_parish_02` | unchanged | "jen underscore latch…" | Raw generated ID leaking into spoken text. Should never reach TTS — needs upstream display-name guard (see §3). |
| `faction.generated.*` | unchanged | "faction dot generated dot…" | Same — raw ID leak. |
| `Indy` (repeated address) | `Indy, …, Indy` | Double address after acceptance | `remove_repeated_player_address()` exists and strips leading/terminal "Indy" — but it may not be called on all LLM response paths. See §3. |
| `Kova Station` | fine | fine | OK — two-word title case, Kokoro handles it. |
| `Iron Reach` | fine | fine | OK. |
| `SC` (credits) | "Es-See" | intended | In exemption list. |
| Faction name `Reaver` | fine | fine | OK — single common word. |
| Generated faction display names (e.g. `The Latch Parish`) | usually fine | depends on word | Multi-word Title Case reads OK. Single weird nouns may get odd stress. No fix needed until playtest flags one. |

### `INDY` fix — add to exemption list
`INDY` is 4 letters, all-caps, not in the exemption list so the normalizer currently
lowercases it to `Indy`. That's actually the **correct** spoken output — Kokoro reads
"Indy" naturally. **No change needed** — the normalizer already handles it correctly
for the `INDY Miner` string. Verified: `core.length() < 3` guard only skips 1-2 char
words; `INDY` (4 chars) gets lowercased to `Indy`. ✓

---

## 2. Display-Text vs Spoken-Text Cleanup Plan

### Current architecture
- **Display text** — shown in UI as-is (can use ALL CAPS for emphasis, raw faction IDs
  sometimes leak through in generated content).
- **Spoken text pipeline:**
  1. `SpeechService.cache(text, voice_id)` / `play_dialogue_audio(text, voice_id)`
  2. `GlobalState.apply_tone_guard()` — replaces "Shiny" → "Indy" for non-Kaelen voices
  3. `TTSInterface.normalize_tts_pronunciation()` — lowercases all-caps words ≥ 3 chars
     (with exemptions)
  4. Kokoro TTS synthesizes audio

### What works well
- ALL CAPS faction names (`ZENITH`, `VANGUARD`, `AURELIA`) get correctly lowercased by
  the normalizer before Kokoro hears them.
- `Shiny` → `Indy` tone guard works correctly and is word-boundary aware.
- `remove_repeated_player_address()` strips leading/terminal "Indy" address patterns.

### Gaps
1. **Raw generated IDs** — if a generated faction ID (`gen_latch_parish_02`,
   `faction.generated.xyz`) ever reaches the TTS pipeline, the normalizer won't help
   because these aren't all-caps. The fix is upstream: always resolve to
   `display_name` before passing to `SpeechService`. This is a generation/data concern,
   not a TTS concern.
2. **`remove_repeated_player_address()` call coverage** — this function exists in
   GlobalState but is not called from all LLM dialogue paths. Should be audited to
   confirm it runs on: agent briefing lines, Kaelen intro/handoff, choice dialogue
   responses, and NPC flavor lines.
3. **Station names with unusual words** — e.g. "Cold Meridian" is fine, but a
   generated station name like "Xeth Gate Outpost" might stress oddly. No fix yet;
   flag when playtest encounters one.

### Safe normalization rule set (proposed)
Keep UI display text completely unchanged. Before any text reaches `SpeechService`:
- Resolve generated faction IDs to their `display_name` (Title Case).
- Resolve raw station IDs to their display name.
- Strip all-caps prefixes like `GEN_`, `FACTION.`, `SYSTEM.`.
- Preserve intentional acronyms (`SC`, `AI`, `HP`) — the exemption list handles these.
- Do NOT pre-process Kaelen's lines — her voice path bypasses tone guard intentionally.

---

## 3. "Indy" Repeated Address Audit

### Mechanism
`remove_repeated_player_address()` in GlobalState.gd:2303 strips:
- Leading `Indy, …` / `Indy! …` / `Indy: …`
- Mid-sentence `, Indy,` paired commas
- Terminal `, Indy.` / `, Indy!` / `, Indy?`

### Where it's called
Needs code audit to confirm coverage. The function exists; call sites need verification:

| Dialogue path | Called? | Notes |
|---|---|---|
| Agent briefing lines (quest `dialogue` field) | ❓ | Check LLMInterface quest generation post-processing |
| Kaelen intro/handoff unique line | ❓ | Should be skipped for Kaelen (she uses "Shiny") |
| Choice dialogue responses (`consequence.dialogue_response`) | ❓ | Check quest acceptance flow |
| NPC flavor lines (minor NPCs) | ❓ | These are pre-written, not LLM-generated, lower risk |
| Mechanic intro lines | ❓ | Pre-written, but some end with "Indy" (e.g. line 4590) — that's intentional |

### Pre-written lines with intentional "Indy"
These are fine — they are deliberate callouts, not repeated addresses:
- `UIManager.gd:4590` — `"…sit down before I charge you for standing in my workspace, Indy."` ✓
- `GlobalState.gd:185` — `"All yours, Indy. Don't make me file a claim…"` ✓

### What to watch for in playtests
- Agent lines that open **and** close with "Indy" (e.g. "Indy, the job is simple…
  don't blow it, Indy.")
- Choice response lines that start with "Indy" immediately after the player already
  heard "Indy" in the briefing.

---

## 4. Generated Faction Names — Pronunciation Notes

### Current generated faction name format
Generated factions resolve to a `display_name` from the campaign bible (Title Case,
multi-word). Examples seen: `The Latch Parish`, `Cold Meridian Consortium`.

### Kokoro pronunciation behavior (observed)
Kokoro (TTS engine) handles Title Case multi-word names well as long as:
- Words are common English dictionary words.
- No unusual consonant clusters or non-English phonetics.

### Potentially awkward patterns to watch for
| Pattern | Example | Risk | Recommendation |
|---|---|---|---|
| Uncommon nouns | `The Flux Wardens` | Low — "Flux" OK | None |
| Invented proper nouns | `Xeth`, `Kova` | Medium — stress unknown | Test in playtest; add pronunciation alias if wrong |
| Station name as faction suffix | `Iron Reach Syndicate` | Low | Fine |
| Hyphenated names | `Cross-Gate Authority` | Medium — Kokoro may pause at hyphen | Prefer space-separated |
| All-caps abbreviation in name | `The IRM Collective` | Handled — normalizer lowercases to `Irm` | Flag if `IRM` should be spelled out |

### Existing proper nouns — pronunciation status
| Name | Reads as | Notes |
|---|---|---|
| `Kaelen` | "Kay-len" | Kokoro reads naturally ✓ |
| `Kova` | "Ko-va" | Natural ✓ |
| `Vanguard` | Natural | ✓ |
| `Zenith` | Natural | ✓ |
| `Aurelia` | "Aw-reel-ee-a" | Natural ✓ |
| `Reaver` | Natural | ✓ |
| `Cassen Vane` | "Kass-en Vane" | Natural ✓ |
| `Mariska Vonn` | "Ma-ris-ka Von" | Natural ✓ |
| `Alaric Venn` | "Al-ar-ik Ven" | Natural ✓ |
| `Oleg Stroud` | Natural | ✓ |
| `Dasha Invar` | "Dash-a In-var" | Natural ✓ |
| `Jenna Kross` | Natural | ✓ |
| `Hana Quill` | Natural | ✓ |
| `Korvin Shaw` | "Kor-vin Shaw" | Natural ✓ |

### Voice mapping by gender/vibe (for generated portrait pairing)
| Voice ID | Kokoro voice | Reads as | Vibe |
|---|---|---|---|
| `am_onyx` | Cassen Vane | Male | Deep, grizzled |
| `af_nicole` | Mariska Vonn | Female | Crisp, corporate |
| `am_michael` | Korvin Shaw / Vanguard NPCs | Male | Steady, military |
| `af_kore` | Hana Quill | Female | Clear, analytical |
| `am_fenrir` | Oleg Stroud | Male | Measured, deliberate |
| `af_nova` | Dasha Invar | Female | Edgy, fast |
| `am_liam` | Alaric Venn | Male | Smooth, corporate |
| `af_aoede` | Jenna Kross | Female | Warm, casual |
| `af_bella` | **Kaelen only** — reserved | Female | Warm, playful broker |
| `af_sarah` | Aurelia faction NPCs | Female | Professional |
| `am_adam` | Zenith faction NPCs | Male | Authoritative |

**Rule:** Never use `af_bella` in generated NPC voice blends — it is Kaelen's exclusive
voice. See memory: `feedback_voice_blends.md`.

---

## 4. Hyphenated compounds — suspected, 2026-08-02

Author reported an unclear word in a generated Kaelen line rendered through Kokoro:

> "You bailed mid-job. That's what I'm charging for."

`bailed` is common and unlikely to be the problem; **`mid-job` is the suspect**. Hyphenated
compounds have no reliable spoken form — Kokoro may run them together, insert a pause, or
stress the wrong half.

Generated dialogue is now screened for this before it can reach TTS
(`docs/research/quiet_moment/runner.py`, `TTS_RISK`), alongside all-caps tokens, symbols
(`/ & % @ # * _ ~`) and ellipses. Applied to the 55-line listening set it flagged exactly one
line — the one the author could not parse.

**Not yet confirmed by ear.** If a hyphen-free re-render of the same beat is clear, that
confirms it and the rule should move into `normalize_tts_pronunciation()` so it protects all
spoken paths, not just quiet moments.
