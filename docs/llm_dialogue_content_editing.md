# Editing LLM Dialogue Content

This is the human-facing guide for the planned file:

`data/content/llm_dialogue_content.json`

Use that JSON file to control examples, fallback lines, tone notes, nickname
rules, and prompt requirements without editing GDScript.

---

## Core Rules

- **Kaelen owns `Shiny`.** Do not put `Shiny` in mechanic, faction agent,
  bartender, lounge local, public board, or enemy lines.
- **Use `Indy` sparingly.** If a section allows it, treat it like spice, not
  salt. Most lines should use `you`, `pilot`, or no direct address.
- **Enemy pilots do not know the player.** They should never say `Shiny`,
  `Indy`, or the player name.
- **Mechanic is not Kaelen.** Jenna can be cocky and personal, but should not
  use Kaelen phrases like `stay put`, `sit tight`, `I'll fetch`, or `Shiny`.
- **Examples teach rhythm.** The LLM copies structure and tone from examples,
  so short clean examples are better than long instructions.

---

## Placeholder Rules

Only use placeholders the code knows how to replace.

Common placeholders:

- `{ship}`
- `{part}`
- `{npc}`
- `{outpost}`
- `{ORE_AMOUNT}`
- `{ITEM_NAME}`
- `{TARGET_NPC}`
- `{PICKUP_LOCATION}`
- `{TURN_IN_LOCATION}`
- `{TARGET_FACTION}`
- `{KILL_COUNT}`

Do not invent new placeholders in the JSON unless code has been updated to
replace them.

Good:

```json
"Nice {ship}. I left a {part} with {npc} over at {outpost}. Go get it."
```

Bad:

```json
"Bring me {mystery_widget} before {deadline_mood} expires."
```

---

## How Many Examples

For each bucket, start with 3-8 examples.

Add more examples when:

- The LLM keeps using the same structure too often.
- A character voice feels too thin.
- You want several flavors of the same situation.

Add instructions when:

- The LLM keeps breaking a rule.
- The rule is structural, like “never say Shiny.”

Prefer examples for taste. Prefer instructions for boundaries.

---

## Safe Editing Pattern

1. Change one bucket at a time.
2. Keep lines short.
3. Avoid adding new mission facts not supplied by placeholders.
4. Save the JSON.
5. Run the game and test that specific dialogue path.

If a line sounds wrong, fix the example first before adding more rules.

---

## Voice Ownership

Reserved words/voices:

- `Shiny`: Kaelen only.
- `Bella` / `voice.kaelen.v1` / `af_bella`: Kaelen only.
- `Jenna Kross`: mechanic voice, not Kaelen.

If another NPC sounds like Kaelen, check:

- Did the section include `Shiny`?
- Did the section use Kaelen phrases?
- Did the caller forget to pass the NPC voice profile?
- Did the fallback line come from the wrong section?

---

## What JSON Should Not Control

Do not use the dialogue JSON for:

- Credit payouts
- Ore amounts
- Spawn counts
- Combat stats
- Reputation math
- Item IDs that are not already whitelisted in code
- Quest completion conditions

Those belong in code or typed content registries. The dialogue JSON is for
voice, tone, examples, and safe fallback wording.
