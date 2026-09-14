# Plan: LLM Dialogue Content Registry

Goal: move the words we use to steer and constrain the LLM out of scattered
GDScript strings and into one human-editable JSON content file. The game code
should own mechanics and validation; the JSON should own tone, examples,
fallback lines, banned phrases, nickname rules, and small prompt fragments.

This gives designers/editors direct control over what comes out of NPC mouths
without asking an engineer to change phrasing every time.

Second goal: make future model swaps easier. The dialogue content file should
describe *what* the game wants, while a separate model profile describes *how*
to ask the current model for it. If we move from the current Ollama model to a
new local model or hosted model later, we should mostly update a model profile
and a few prompt wrappers, not rewrite every gameplay caller.

---

## Design Rules

1. **One content file, many sections**
   - Suggested path: `data/content/llm_dialogue_content.json`
   - This file is edited by humans.
   - It should be pretty-printed JSON, not packed/minified.

2. **Code still owns mechanics**
   - The JSON may say how a quest should sound.
   - It must not define reward formulas, spawn counts, combat behavior, or
     cargo logic.
   - Any number from JSON that affects gameplay must still be clamped by code.

3. **No raw player nickname pressure by default**
   - Only Kaelen should be encouraged to use `Shiny`.
   - Non-Kaelen speakers should usually use `you`, `pilot`, or no address.
   - `Indy` should be optional/sparse, never required in examples.

4. **Examples are examples, not truth**
   - Examples may contain placeholders.
   - Code replaces placeholders with current mission facts.
   - Code validates that generated output still matches mission facts.

5. **Fallbacks live beside examples**
   - If the LLM fails, the fallback should come from the same section that
     supplied the prompt examples.
   - This keeps generated and fallback tone aligned.

6. **Validation is mandatory**
   - Missing sections should fall back to built-in minimal defaults.
   - Bad JSON should never break the game.
   - Unknown fields are ignored so the file can evolve.

7. **Model-specific behavior is isolated**
   - Do not scatter model names, JSON-mode assumptions, temperature values, or
     retry phrasing through gameplay code.
   - Put model quirks in `data/content/llm_model_profiles.json`.
   - Game systems ask for a task like `quest_generation` or `mechanic_intro`;
     the LLM gateway chooses the current model profile and formatting strategy.

---

## Proposed File Shape

```json
{
  "schema_version": 1,
  "global_rules": {
    "kaelen_only_words": ["Shiny"],
    "non_kaelen_address_guidance": "Do not use the pilot's name or callsign. Use 'you' or 'pilot' only when a direct address is needed.",
    "banned_non_kaelen_phrases": ["Shiny", "my best friend", "stay put", "sit tight", "I'll fetch"],
    "allowed_rare_non_kaelen_addresses": ["Indy"],
    "max_rare_address_uses": 1
  },
  "speakers": {
    "kaelen": {
      "voice_profile_id": "voice.kaelen.v1",
      "address_rule": "Calls the player Shiny. This belongs only to Kaelen.",
      "tone_card": "Cynical, profit-minded broker. Wry, sharp, never sentimental unless the subtext says otherwise."
    },
    "mechanic": {
      "voice_profile_id": "voice.jenna_kross.v1",
      "address_rule": "Usually says you. May say Indy rarely. Never says Shiny.",
      "tone_card": "Cocky mechanic. Observant, practical, a little too personal, but not Kaelen."
    },
    "faction_agent": {
      "address_rule": "Does not know the pilot's private nickname. Use you, pilot, asset, courier, or no address.",
      "tone_card": "Faction-specific professional contact. Never imitates Kaelen."
    },
    "lounge_local": {
      "address_rule": "Casual station contact. Avoid player names unless a story fact explicitly allows it.",
      "tone_card": "Local, grounded, useful even when casual."
    }
  },
  "quest_generation": {
    "mission_types": {
      "KILL_SHIPS": {
        "dummy_constraints": "Use Slithern as the dummy enemy. Use George at most once, usually use you or pilot. Always say 3 ships.",
        "examples": [
          {
            "dialogue": "Slithern raiders are testing the lane. Clear 3 ships and report back.",
            "response_1": "Good. Keep it clean.",
            "response_2": "Advance approved. Do not waste it.",
            "response_3": "Payout revised. Expect resistance."
          }
        ],
        "fallbacks": []
      },
      "DELIVER_ORE": {
        "dummy_constraints": "Use George at most once, usually use you or pilot. Always say 25 m3 of ore.",
        "examples": [],
        "fallbacks": []
      },
      "PICKUP_SPECIAL": {
        "dummy_constraints": "Use Sable Mercer, Morrow Station, and Sealed Data Drive as dummy pickup facts. Use George at most once.",
        "examples": [],
        "fallbacks": []
      }
    }
  },
  "mechanic": {
    "prompt_requirements": [
      "Write one short greeting.",
      "Second person voice.",
      "Never use Shiny.",
      "Use Indy only rarely.",
      "No hashtags, emojis, or quotation marks around the line."
    ],
    "examples": {
      "normal": [
        "Your ship is making a noise that costs money. Lucky for both of us, I like money."
      ],
      "pickup_offer": [
        "Nice {ship}. You want it fixed? Do me a solid. I left a {part} with {npc} over at {outpost}. Go get it."
      ],
      "active_pickup_missing_part": [
        "Where's my {part}? Don't tell me you got lost."
      ],
      "active_pickup_has_part": [
        "You actually got the {part}. Drop it on the bench before you break it."
      ]
    },
    "fallback_thanks": [
      "Got the {part}. It's a miracle you didn't explode on the way back. Take your money and get out of my bay."
    ]
  },
  "lounge": {
    "prompt_requirements": [
      "Use current StoryManager context by default.",
      "Even casual lines should reveal something about the station, system, faction tension, reputation, or nearby opportunity.",
      "Pure throwaway jokes are rare."
    ],
    "fallback_lines": {
      "bartender": [
        "Keep your voice low and your tab honest."
      ],
      "empty_contact": [
        "No contact."
      ]
    }
  },
  "kaelen_handoffs": {
    "requirements": [
      "Kaelen speaks in first person.",
      "Kaelen talks to Shiny about the agent.",
      "Do not use Shiny more than once across a generated batch."
    ],
    "fallbacks_by_faction": {
      "zenith": [],
      "aurelia": [],
      "vanguard": [],
      "neutral": []
    }
  },
  "public_board": {
    "kaelen_turn_in_style": "Kaelen is mildly disgusted that the player took public-board work, but still pays out.",
    "fallback_variants_by_template": {}
  },
  "combat_taunts": {
    "global_requirements": [
      "Enemy pilots do not know the player's name.",
      "Enemy pilots never say Shiny or Indy.",
      "Kaelen combat lines may say Shiny."
    ],
    "fallback_lines": {}
  }
}
```

---

## Model Profiles

Add a second file:

`data/content/llm_model_profiles.json`

This file describes how each supported model wants to be prompted.

```json
{
  "schema_version": 1,
  "active_profile": "ollama_qwen_small",
  "profiles": {
    "ollama_qwen_small": {
      "provider": "ollama",
      "model": "qwen2.5:3b-instruct-q4_K_M",
      "endpoint": "http://127.0.0.1:11434/api/generate",
      "supports_json_mode": true,
      "json_mode_field": "format",
      "json_mode_value": "json",
      "temperature_by_task": {
        "quest_generation": 0.75,
        "mechanic_intro": 0.8,
        "lounge_dialogue": 0.85,
        "combat_taunts": 0.9,
        "public_board_text": 0.7
      },
      "prompt_wrapper": {
        "system_prefix": "",
        "instruction_prefix": "",
        "json_suffix": "Return ONLY valid JSON. No markdown. No commentary."
      },
      "retry_style": {
        "critique_prefix": "SELF-CRITIQUE: previous output failed because",
        "repair_instruction": "Fix only the failure. Preserve the required facts."
      }
    },
    "future_model_profile": {
      "provider": "ollama",
      "model": "replace-me",
      "supports_json_mode": false,
      "prompt_wrapper": {
        "system_prefix": "You are a strict game dialogue generator.",
        "json_suffix": "Output a single JSON object and nothing else."
      }
    }
  }
}
```

This lets us adapt when a new model:

- needs stronger JSON instructions,
- does not support Ollama JSON mode,
- wants shorter prompts,
- needs examples before rules instead of rules before examples,
- performs better with lower temperature,
- needs different retry wording,
- uses a different provider endpoint.

The active model can change without changing every caller.

---

## Prompt Task Boundary

Introduce a small task layer between gameplay code and the provider:

```gdscript
LLMTaskRunner.request("quest_generation", {
  "speaker_id": "faction_agent",
  "objective_type": chosen_type,
  "facts": facts,
  "story_context": story_context,
}, callback)
```

The task runner should:

1. Load dialogue content from `LLMDialogueContentRegistry`.
2. Load model settings from `LLMModelProfileRegistry`.
3. Build the prompt from task parts.
4. Send it through the selected provider.
5. Parse output.
6. Validate against the task schema.
7. Retry using the model profile's retry style.
8. Fall back to the relevant dialogue-content fallback bucket.

Gameplay systems should not care whether the model is Qwen, Gemma, Mistral, or
something hosted later.

---

## Output Schemas

Every LLM task should have a named output schema in code. The JSON content file
can describe examples and tone, but code owns schema validation.

Recommended task schemas:

- `quest_generation`
  - `title`
  - `dialogue`
  - `choices`
  - objective data already validated by current mission logic
- `mechanic_intro`
  - `line`
- `lounge_dialogue`
  - `line`
  - optional `reply_options`
  - optional `rumor_hook`
- `kaelen_handoff`
  - `lines`
- `combat_taunts`
  - fixed key/value line map
- `anomaly_event`
  - `name`
  - `description`
  - `approach_lines`
  - `actions`

This gives model migration a hard safety net: even if the new model is chatty
or weird, bad output gets rejected before it touches gameplay.

---

## Provider Adapter Boundary

Long-term shape:

```text
Gameplay System
  -> LLMTaskRunner
    -> LLMDialogueContentRegistry
    -> LLMModelProfileRegistry
    -> LLMProviderAdapter
      -> Ollama / future provider
```

Suggested adapter methods:

```gdscript
func generate(task_id: String, prompt: String, profile: Dictionary, callback: Callable) -> void
func supports_json_mode(profile: Dictionary) -> bool
func build_request_body(prompt: String, profile: Dictionary, task_settings: Dictionary) -> Dictionary
func extract_text_response(response_body: Variant, profile: Dictionary) -> String
```

Start with one adapter for Ollama. If we ever move to another model provider,
we add another adapter instead of rewriting dialogue systems.

---

## Loader

Create a small registry class:

`scripts/registry/LLMDialogueContentRegistry.gd`

Responsibilities:

- Load `res://data/content/llm_dialogue_content.json`.
- Validate `schema_version`.
- Return safe defaults if the file is missing or malformed.
- Provide typed helper methods so game code does not dig through raw JSON.

Suggested helpers:

```gdscript
static func shared() -> LLMDialogueContentRegistry
func speaker_tone(speaker_id: String) -> String
func speaker_address_rule(speaker_id: String) -> String
func global_non_kaelen_rules() -> Dictionary
func quest_examples(objective_type: String) -> Array
func quest_dummy_constraints(objective_type: String) -> String
func mechanic_examples(bucket: String) -> Array[String]
func mechanic_requirements() -> Array[String]
func lounge_requirements() -> Array[String]
func kaelen_handoff_requirements() -> Array[String]
func public_board_template_variants(template_id: String) -> Array
```

Keep it boring. This is a content accessor, not a generator.

Create a companion model profile registry:

`scripts/registry/LLMModelProfileRegistry.gd`

Suggested helpers:

```gdscript
static func shared() -> LLMModelProfileRegistry
func active_profile() -> Dictionary
func task_temperature(task_id: String) -> float
func prompt_wrapper() -> Dictionary
func retry_style() -> Dictionary
func supports_json_mode() -> bool
```

This registry is also boring. It does not know game story. It only knows model
configuration.

---

## Migration Order

### Step 1: Add Registry + JSON

- Add `data/content/llm_dialogue_content.json`.
- Add `data/content/llm_model_profiles.json`.
- Add `LLMDialogueContentRegistry.gd`.
- Add `LLMModelProfileRegistry.gd`.
- Add a small test that loads the file and checks required top-level keys.
- No behavior change yet.

### Step 2: Move Quest Generation Examples

First target: `scripts/LLMInterface.gd`.

Move:
- mission type examples
- dummy name instructions
- speaker address rules
- broad tone cards where practical

Do not change validation logic.

The request builder should become:

```gdscript
var content := LLMDialogueContentRegistry.shared()
var examples := content.quest_examples(chosen_type)
var dummy_instruction := content.quest_dummy_constraints(chosen_type)
```

### Step 3: Move Mechanic Prompt/Fallbacks

Target: `scripts/UIManager.gd`.

Move:
- mechanic greeting examples
- pickup offer examples
- mechanic fallback greeting/thanks lines
- banned mechanic phrasing requirements

Keep the code responsible for replacing `{ship}`, `{part}`, `{npc}`, and
`{outpost}`.

### Step 4: Move Lounge Prompt/Fallbacks

Target: `scripts/UIManager.gd`.

Move:
- lounge card prompt requirements
- bartender fallback lines
- generic local contact fallback lines
- empty-slot text, if desired

This sets up the next feature: story-aware lounge rumor leads.

### Step 5: Move Public Board Fallback Text

Target: `scripts/domain/MissionTemplateRegistry.gd`.

This can either:
- keep template mechanics in code and load only text variants from JSON, or
- move full template text blocks to JSON later.

Recommendation: move only fallback text first. Do not move mission template
structure yet.

### Step 6: Move Combat Taunt Prompt Rules

Target: `scripts/LLMInterface.gd`.

Move:
- enemy does not know player name rule
- Kaelen may say Shiny rule
- fallback line buckets

This is lower risk after the registry is proven.

---

## Guardrail Layer

Keep these in code, even after the content move:

- `GlobalState.apply_tone_guard()`
- `GlobalState.remove_repeated_player_address()`
- Quest fact validation in `LLMInterface`
- Public-board placeholder validation
- Voice profile routing in `SpeechService`
- Any clamp on credits, ore, ship counts, rep, item grants, or hostile spawns

The JSON reduces bad prompting. The guardrails catch bad output.

---

## Human Editing Rules

Put these comments in the top of a companion doc, because JSON cannot have
comments:

- Use placeholders exactly as written: `{ship}`, `{part}`, `{npc}`,
  `{outpost}`, `{ORE_AMOUNT}`, etc.
- Do not add new placeholders unless code supports them.
- Do not put `Shiny` in non-Kaelen sections.
- Avoid `Indy` unless the section explicitly says it is allowed.
- Keep examples short. The model copies rhythm more than intent.
- Add 3-8 examples per bucket before adding more prompt instructions.

Suggested companion file:

`docs/llm_dialogue_content_editing.md`

---

## Testing Checklist

Add or update tests for:

- JSON loads and required keys exist.
- Non-Kaelen `Shiny` still becomes `Pilot`.
- Legacy `neutral` still resolves to Kaelen/Bella.
- Quest generation prompt can build with JSON examples.
- Mechanic prompt can build with JSON examples.
- Missing JSON section falls back cleanly.
- Bad JSON file does not crash game startup.

Useful existing tests:

- `tests/speech/run_speech_service_tests.gd`
- `tests/domain/run_mission_contract_tests.gd`
- `tests/domain/run_public_board_validation_tests.gd`
- `tests/parse_check.gd`

---

## Good First Claude Implementation Slice

Best small slice:

1. Add `llm_dialogue_content.json` with global rules, speaker rules, and the
   three quest mission-type example buckets.
2. Add `llm_model_profiles.json` with the current Ollama profile.
3. Add `LLMDialogueContentRegistry.gd` and `LLMModelProfileRegistry.gd`.
4. Change only `LLMInterface.request_quest_generation()` to read examples and
   dummy constraints from the registry.
5. Keep request sending through the existing `LLMInterface.build_generation_body()`
   for now, but have it read temperature/json-mode defaults from the active
   model profile where practical.
6. Leave mechanic/lounge/public-board/combat for later commits.
7. Run parse, mission contract, public board validation, and speech tests.

That gives us control over the highest-impact LLM output first without
touching every dialogue system at once.
