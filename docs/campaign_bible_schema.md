# Campaign Bible — Enforced JSON Schema (v1, 2026-07-04 revision)

The Campaign Bible is the single source of narrative truth for one campaign.
It is generated once per playthrough by the large story model (labeled @@block
protocol — see `NarrativeDirector._CAMPAIGN_BIBLE_LABEL_FIELDS`), assembled and
validated entirely in code, and stored at `<campaign>/campaign_bible.json` by
`CampaignBibleStore`. Every downstream system (StoryManager, LLMInterface,
UIManager lounge/chatter) pulls from it — never from its own invented context.

## Structural contract

```jsonc
{
  // ── Document identity (code-owned, never model-authored) ──
  "schema_version": 1,
  "document_type": "campaign_bible",
  "campaign_id": "campaign.xxxx",
  "campaign_seed": "...",
  "source": "llm_generated",            // procedural_bootstrap | llm_generated | llm_unavailable | generation_failed
  "generation_status": "llm_generated",
  "source_model": "...",
  "generation_note": "...",
  "last_generation_error": "",

  // ── Deterministic variety axes (code-derived from seed, stored for debug/rotation) ──
  "creative_lane": "salvage rights",     // one of NarrativeDirector.CREATIVE_LANES
  "opening_type": "inherited-a-problem", // OPENING_TYPES, salt 101
  "mystery_shape": "whodunit",           // MYSTERY_SHAPES, salt 211
  "pressure_type": "debt-clock",         // PRESSURE_TYPES, salt 331

  // ── Campaign spine (model-authored, PLAYER-SAFE unless marked DIRECTOR-ONLY) ──
  "campaign_title": "...",
  "campaign_logline": "...",
  "opening_situation": "...",            // must stay tutorial-compatible: broke pilot, one starter Reaver
  "main_mystery": "...",                 // DIRECTOR-ONLY (seeded into player_does_not_know_yet)
  "act_1_outline": ["beat 1", "beat 2", "beat 3"],  // DIRECTOR-ONLY reserve; consumed per chapter
  "long_term_reveal": "...",             // DIRECTOR-ONLY
  "tone": "...",
  "core_pressure": "...",

  // ── Anchor faction texture (player-safe world texture, not twists) ──
  "factions": {
    "zenith": "one concrete local problem this campaign",
    "aurelia": "...",
    "vanguard": "..."
  },

  // ── Fixed cast: Kaelen (plot-protected) ──
  "kaelen_rule": "public role — MUST contain broker/fixer/contract",   // validated
  "kaelen_angle": "...",                 // DIRECTOR-ONLY hidden angle
  "kaelen_hint_plan": ["surface hint 1", "..."],  // DIRECTOR-ONLY until delivered
  "kaelen_hint_style": "...",            // player-safe delivery style
  "kaelen_never_reveal": "...",          // DIRECTOR-ONLY: stays unresolved forever

  // ── Fixed cast: N.O.V.A. (plot-protected) — NEW this revision ──
  "nova_quirk": "one campaign-specific habit/fixation for the ship AI",  // player-safe
  "nova_memory_flicker": "...",          // DIRECTOR-ONLY: one corrupted fragment of her
                                         // wiped past that obliquely ties into main_mystery.
                                         // Surfaces only as glitch-flavored hints, never stated.

  // ── World rules ──
  "faction_reveal_rule": "...",
  "humor_rule": "...",                   // dry/dark PG-13 humor contract
  "address_rule": "...",
  "fallback_rule": "...",
  "story_horizon_rule": "...",

  // ── Extensible reserves (append-only via horizon expansion; never retconned) ──
  "story_arcs": [{"name": "...", "summary": "..."}],
  "rumor_trails": [{
    "name": "...", "trail_id": "rumor_trail.snake_case",
    "clue_count": 2, "hint_theme": "...",
    "clue_templates": ["...", "..."],
    "discovery_type": "hidden_discovery|secret_route|rare_upgrade|faction_secret|endgame_easter_egg",
    "rarity": "local|uncommon|rare|legendary",
    "payoff": "..."                      // DIRECTOR-ONLY
  }],
  "regeneration_triggers": [{
    "id": "snake_case", "metric": "prepared_systems_remaining|active_story_arcs_remaining|rumor_trails_remaining|major_arc_state",
    "threshold": 0, "action": "append_story_horizon|append_rumor_trail|append_story_arc",
    "description": "..."
  }],
  "expansion_rules": ["...", "..."],
  "banned_repeats": ["chosen one", "destiny", "..."]   // always force-includes those two
}
```

## Privacy tiers (leak containment)

| Tier | Fields | Who sees it |
|---|---|---|
| Player-safe | title, logline, opening_situation, tone, core_pressure, factions triad, kaelen_rule, kaelen_hint_style, **nova_quirk**, humor/address/faction-reveal rules | `CampaignBibleStore.public_prompt_context()` → every small-model prompt |
| Director-only | main_mystery, long_term_reveal, act_1_outline, kaelen_angle, kaelen_hint_plan (undelivered), kaelen_never_reveal, **nova_memory_flicker**, rumor payoffs/hint themes, horizon machinery | `director_context()` — debug tooling + large-model calls only |

The public projection is an **allowlist**: a new field is private until it is
explicitly added to `public_prompt_context()`. StoryManager mirrors the same
split (`player_does_not_know_yet`, `kaelen_hidden_angle`, `kaelen_hidden_hints`,
`nova_memory_flicker` are never emitted by `get_story_context_block()`).

## Plot-armor contract (Kaelen + N.O.V.A.)

Both are structural cast and can never be killed, deleted, or permanently
removed by any generated permutation. Enforced in three layers:

1. **Prompt constraints** — hard-constraint lines in the bible prompt.
2. **Generation validation** — `NarrativeDirector._validate_plot_armor()` scans
   every text field of a generated bible (and horizon expansions) for
   kill/death/removal phrasing about either character; a hit is a validation
   error that feeds the correction-retry loop.
3. **Runtime guard** — `StoryQuestManager.begin_quest()` rejects any quest def
   whose kill objective or spawn `persistent_id` targets protected cast
   (`PLOT_PROTECTED_IDS`), logging via GenerationDiagnostics.

## Top-down flow (who pulls what)

```
CampaignBibleStore (disk truth)
  ├─ StoryManager.seed_story_state_from_bible()   → living story_state (chapter,
  │    tensions, hooks, faction_pressure, kaelen/nova hidden fields)
  │    └─ get_story_context_block()   → LLMInterface.story_state_context_text
  │    └─ get_ambient_flavor_block()  → compact player-safe block for chatter/lounge
  ├─ public_prompt_context()          → LLMInterface.campaign_bible_context_text
  ├─ QuestManager / quest gen prompt  → BIBLE + STORY STATE + "because" blocks
  ├─ UIManager lounge/contact topics  → story-state-anchored templates + rumor trails
  └─ Nova autoload                    → nova_quirk (campaign flavor for her line pools)
```

## Wipe contract (new campaign / restart)

`GameRoot` transitions must leave zero stale narrative state:
`StoryManager.clear_story_state()` (includes nova fields),
`LLMInterface.clear_quest_fingerprints()` + `reset_for_restart()` (chatter
caches, context texts), `Nova.reset_for_restart()` (line-picker memory,
campaign quirk), handoff pools replaced on next system arrival.
