"""Labeled-field campaign-bible generator for gemma4:e4b.

Why this exists: gemma4:e4b writes good story CONTENT (test scores 80-88) but
cannot reliably hold a 25-key nested JSON tree together -- it drops nested keys
(`missing_nested:*`). So we never ask it for JSON structure. Instead the model
answers in flat `@@label` blocks it cannot structurally break, and CODE owns all
the structure: dotted labels -> nested tree, `-` lines -> arrays, enum/number
coercion, validation.

Flow (hybrid, per design 2026-07-02):
  1. One-shot: ask for every field as @@label blocks.
  2. Parse + validate each field independently by label.
  3. Round-2 repair: re-ask ONLY the labels that failed, with the failure reason.
  4. Assemble the exact production campaign-bible shape and write JSON.

Target schema mirrors NarrativeDirector.build_campaign_bible_prompt so the
result drops into parse_campaign_bible_response unchanged.
"""

import json
import time
import urllib.error
import urllib.request

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "gemma4:e4b"

DISCOVERY_TYPES = ["hidden_discovery", "secret_route", "rare_upgrade", "faction_secret", "endgame_easter_egg"]
RARITIES = ["local", "uncommon", "rare", "legendary"]
METRICS = ["prepared_systems_remaining", "active_story_arcs_remaining", "rumor_trails_remaining", "major_arc_state"]
ACTIONS = ["append_story_horizon", "append_rumor_trail", "append_story_arc"]

# Each field is addressable by its label. `kind` drives parsing + validation:
#   text     -> one string, optional `max` char cap
#   text_list-> one item per `-` line, `min`/`max` item counts
#   enum     -> must be one of `choices`
#   int      -> coerced to integer
#   slug     -> snake_case identifier (letters/digits/underscore)
# `guide` is the plain-language ask shown to the model (no JSON, no braces).
FIELDS = [
    {"label": "campaign_title", "kind": "text", "max": 90,
     "guide": "A distinct campaign title. Not a 'Zenith <noun>' pattern. Not similar to generic void/edge/dust titles."},
    {"label": "campaign_logline", "kind": "text", "max": 220,
     "guide": "One-sentence logline of the campaign hook."},
    {"label": "opening_situation", "kind": "text", "max": 260,
     "guide": "The player's opening situation: broke independent pilot, one starter Reaver-class hostile ahead."},
    {"label": "main_mystery", "kind": "text", "max": 220,
     "guide": "The central campaign mystery the player can chase through jobs."},
    {"label": "act_1_outline", "kind": "text_list", "min": 3, "max": 3,
     "guide": "Exactly THREE beats of act 1. One per line, each under 180 chars."},
    {"label": "long_term_reveal", "kind": "text", "max": 220,
     "guide": "The eventual long-term reveal. Fit the lane; avoid cosmic/ancient-signal cliche."},
    {"label": "tone", "kind": "text", "max": 120, "guide": "The campaign tone in a short phrase."},
    {"label": "core_pressure", "kind": "text", "max": 140, "guide": "The core pressure driving the campaign."},
    {"label": "factions.zenith", "kind": "text", "max": 140,
     "guide": "Zenith's one concrete local problem this campaign. Player-facing, not a hidden twist."},
    {"label": "factions.aurelia", "kind": "text", "max": 140, "guide": "Aurelia's one concrete local problem this campaign."},
    {"label": "factions.vanguard", "kind": "text", "max": 140, "guide": "Vanguard's one concrete local problem this campaign."},
    {"label": "kaelen_rule", "kind": "text", "max": 200, "must_contain": ["broker", "fixer", "contract"],
     "guide": "States Kaelen is PUBLICLY a broker, fixer, or contract handler. Public role only. Must use the word broker, fixer, or contract."},
    {"label": "kaelen_angle", "kind": "text", "max": 220,
     "guide": "HIDDEN director-only: what Kaelen secretly knows or did. Never restates her public role. Never shown to player."},
    {"label": "kaelen_hint_plan", "kind": "text_list", "min": 3, "max": 5,
     "guide": "3 to 5 player-safe SURFACE observations that only hint at her secret (odd habits, small inconsistencies). One per line. Never explain the secret."},
    {"label": "kaelen_hint_style", "kind": "text", "max": 120,
     "guide": "How Kaelen deflects this campaign, e.g. deflect-with-jokes, over-precise-details, selective-silence."},
    {"label": "kaelen_never_reveal", "kind": "text", "max": 200,
     "guide": "HIDDEN: one line naming what must stay unresolved even at full trail completion."},
    {"label": "faction_reveal_rule", "kind": "text", "max": 200, "guide": "Rule for how new factions get revealed through gate travel."},
    {"label": "humor_rule", "kind": "text", "max": 200, "guide": "Rule for the dry, slightly dark PG-13 humor."},
    {"label": "address_rule", "kind": "text", "max": 200, "guide": "How NPCs address the player."},
    {"label": "fallback_rule", "kind": "text", "max": 200, "guide": "How to handle missing story data."},
    {"label": "story_horizon_rule", "kind": "text", "max": 200, "guide": "Rule for extending the story with a new horizon later without retconning player choices."},
    {"label": "story_arc.name", "kind": "text", "max": 90, "guide": "Name of the single first story arc."},
    {"label": "story_arc.summary", "kind": "text", "max": 180, "guide": "Summary of that story arc, under 180 chars."},
    {"label": "rumor.name", "kind": "text", "max": 90, "guide": "Name of the single rumor trail."},
    {"label": "rumor.trail_id", "kind": "slug", "prefix": "rumor_trail.",
     "guide": "A snake_case id for the rumor trail (letters, digits, underscores only). No prefix needed; code adds 'rumor_trail.'."},
    {"label": "rumor.hint_theme", "kind": "text", "max": 140, "guide": "The theme tying the rumor trail's clues together."},
    {"label": "rumor.clue_templates", "kind": "text_list", "min": 2, "max": 2,
     "guide": "Exactly TWO concrete clue templates the player could encounter. One per line."},
    {"label": "rumor.discovery_type", "kind": "enum", "choices": DISCOVERY_TYPES,
     "guide": "One of: " + ", ".join(DISCOVERY_TYPES)},
    {"label": "rumor.rarity", "kind": "enum", "choices": RARITIES, "guide": "One of: " + ", ".join(RARITIES)},
    {"label": "rumor.payoff", "kind": "text", "max": 180, "guide": "What the rumor trail eventually pays off into, under 180 chars."},
    {"label": "trigger.id", "kind": "slug", "guide": "A snake_case id for the regeneration trigger (letters, digits, underscores only)."},
    {"label": "trigger.metric", "kind": "enum", "choices": METRICS, "guide": "One of: " + ", ".join(METRICS)},
    {"label": "trigger.threshold", "kind": "int", "guide": "A single integer threshold for the trigger metric."},
    {"label": "trigger.action", "kind": "enum", "choices": ACTIONS, "guide": "One of: " + ", ".join(ACTIONS)},
    {"label": "trigger.description", "kind": "text", "max": 200, "guide": "One line describing what the trigger does."},
    {"label": "expansion_rules", "kind": "text_list", "min": 2, "max": 2,
     "guide": "Exactly TWO rules for how the campaign expands later. One per line."},
    {"label": "banned_repeats", "kind": "text_list", "min": 1, "max": 8,
     "guide": "Phrases/motifs this campaign should never repeat. One per line. Include 'chosen one' and 'destiny'."},
]

FIELDS_BY_LABEL = {f["label"]: f for f in FIELDS}


# ---------------------------------------------------------------------------
# Prompt building
# ---------------------------------------------------------------------------

# Shared creative constraints. Kept close to the production prompt so content
# quality matches what NarrativeDirector already gets; only the OUTPUT FORMAT
# section changes (labeled blocks instead of JSON).
CONSTRAINTS = """You are the large local story model for SpaceGame, a procedural space game.
Create a compact first-horizon campaign bible for one new campaign.

Hard constraints:
- Keep the handcrafted first system anchored by Zenith, Aurelia, and Vanguard.
- Do not reveal future frontier factions to the player up front.
- Kaelen is the only fixed recurring NPC besides the player.
- Kaelen cannot die and her full mystery must never be completely solved.
- Kaelen must publicly appear as a broker, fixer, or contract handler, not a scavenger, scientist, commander, prophet, mechanic, AI, archive, or failsafe.
- The player is a broke independent pilot facing exactly one starter Reaver-class hostile. Not a chosen one.
- New systems reveal new factions, conflicts, ores, upgrades, rumors, and ships through gate travel.
- Use dry, slightly dark PG-13 humor. Avoid catchphrases.
- Use plain ASCII punctuation only.

Anti-motif guidance:
- Do not use a 'Zenith <single abstract noun>' title pattern.
- Avoid Kaelen-as-AI/archive/failsafe unless it is genuinely the freshest fit.
- Do not use Great Silence, Great Collapse, purge protocol, ancient signal, ghost signal, prophecy, alien owner, mysterious pulse, chosen one, or destiny as the core reveal.
- Prefer secrets the player can chase through jobs: debt, fraud, leverage, sabotage, jurisdiction, inheritance, stolen cargo, repair scarcity, hidden ownership, buried identity."""

FORMAT_RULES = """OUTPUT FORMAT -- READ CAREFULLY:
Do NOT write JSON. Do NOT use braces, brackets, quotes, or commas as structure.
Answer each field as a block that starts with its label on its own line, prefixed by @@,
then the value on the following line(s). Example:

@@campaign_title
The Hollowed Vein
@@act_1_outline
- First beat here.
- Second beat here.
- Third beat here.

Rules:
- One @@label line per field, exactly as given, spelled exactly.
- For list fields, put ONE item per line, each starting with "- ".
- Do not add labels that were not requested. Do not skip any requested label.
- Plain text values only. No markdown headers, no numbering, no extra commentary."""


def _field_ask(field):
    """One instruction line for a field in the prompt body."""
    tag = {"text_list": " (list, one per line)", "enum": " (pick one)",
           "int": " (a number)", "slug": " (snake_case)"}.get(field["kind"], "")
    return "@@%s%s -- %s" % (field["label"], tag, field["guide"])


def build_oneshot_prompt(seed):
    lines = [CONSTRAINTS, "",
             "Campaign seed: %s" % seed, "",
             "Answer ALL of these fields, each as its own @@label block:", ""]
    lines += [_field_ask(f) for f in FIELDS]
    lines += ["", FORMAT_RULES]
    return "\n".join(lines)


def build_repair_prompt(seed, failed_labels, prior_values):
    """Round-2: re-ask ONLY the failed labels, with the reason each failed."""
    lines = [CONSTRAINTS, "",
             "Campaign seed: %s" % seed, "",
             "A previous pass produced some fields that did not validate.",
             "Re-answer ONLY the fields listed below. Fix exactly the stated problem.", ""]
    for label, reason in failed_labels:
        field = FIELDS_BY_LABEL[label]
        prior = prior_values.get(label)
        prior_note = ""
        if prior is not None:
            shown = ", ".join(prior) if isinstance(prior, list) else str(prior)
            prior_note = "  (previous, rejected: %s)" % shown[:160]
        lines.append("%s\n  PROBLEM: %s%s" % (_field_ask(field), reason, prior_note))
    lines += ["", FORMAT_RULES]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Parsing: @@label blocks -> {label: raw_value}
# ---------------------------------------------------------------------------

def parse_blocks(text):
    """Split model output into {label: [raw lines]}. Ignores unknown labels and
    any preamble before the first @@. Tolerant of '@@ label' spacing."""
    blocks = {}
    current = None
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if stripped.startswith("@@"):
            label = stripped[2:].strip()
            # Model sometimes echoes the guide after the label ("label -- ...").
            label = label.split(" ")[0].split("\t")[0].strip()
            current = label
            blocks[current] = []
            continue
        if current is not None:
            blocks[current].append(line)
    return blocks


def _coerce(field, lines):
    """Turn a block's raw lines into a typed Python value per the field kind.
    Returns (value, error_or_None)."""
    kind = field["kind"]
    joined = "\n".join(lines).strip()

    if kind in ("text", "enum", "slug", "int"):
        # Collapse to a single logical value; drop stray blank lines.
        value = " ".join(l.strip() for l in lines if l.strip()).strip()
        if not value:
            return None, "empty"
        if kind == "text":
            # Char caps are SOFT and handled in a separate condense phase (see
            # condense_overlong) -- NOT here. _coerce stays pure/offline: never
            # a network call, never a length failure. Repair rounds are reserved
            # for structure the model can actually fix on re-ask.
            if field.get("must_contain") and not any(
                kw in value.lower() for kw in field["must_contain"]):
                return value, "must mention one of: %s" % ", ".join(field["must_contain"])
            return value, None
        if kind == "enum":
            token = value.strip().strip(".").lower()
            if token not in field["choices"]:
                return value, "must be one of: %s" % ", ".join(field["choices"])
            return token, None
        if kind == "slug":
            slug = _slugify(value)
            # Strip a prefix the model may have already included (dotted or
            # flattened to underscore by slugify) so assembly can add it once.
            if field.get("prefix"):
                pslug = _slugify(field["prefix"])  # "rumor_trail." -> "rumor_trail"
                if slug == pslug:
                    slug = ""
                elif slug.startswith(pslug + "_"):
                    slug = slug[len(pslug) + 1:]
            if not slug:
                return None, "not a usable snake_case id"
            return slug, None
        if kind == "int":
            num = _extract_int(value)
            if num is None:
                return value, "not an integer"
            return num, None

    if kind == "text_list":
        items = []
        for l in lines:
            s = l.strip()
            if not s:
                continue
            if s.startswith("- "):
                s = s[2:].strip()
            elif s.startswith("-"):
                s = s[1:].strip()
            if s:
                items.append(s)
        if not items and joined:
            items = [joined]
        lo, hi = field.get("min", 1), field.get("max", 99)
        if len(items) < lo:
            return items, "need at least %d items, got %d" % (lo, len(items))
        if len(items) > hi:
            items = items[:hi]  # trim overflow rather than fail
        return items, None

    return joined, None


def _truncate_words(value, limit):
    """Trim to <= limit chars at a word boundary, keeping terminal punctuation."""
    if len(value) <= limit:
        return value
    cut = value[:limit]
    sp = cut.rfind(" ")
    if sp > limit * 0.5:
        cut = cut[:sp]
    return cut.rstrip(" ,;:-") + "."


def _slugify(value):
    out = []
    for ch in value.strip().lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in " -_." and (out and out[-1] != "_"):
            out.append("_")
    return "".join(out).strip("_")


def _extract_int(value):
    digits = ""
    for ch in value:
        if ch.isdigit() or (ch == "-" and not digits):
            digits += ch
        elif digits:
            break
    try:
        return int(digits)
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# Validation: which labels are missing/invalid?  -> [(label, reason)]
# ---------------------------------------------------------------------------

def validate(blocks):
    """Returns (values, failures). values maps label->typed value for everything
    that validated; failures is [(label, reason)] for round-2 repair."""
    values = {}
    failures = []
    for field in FIELDS:
        label = field["label"]
        if label not in blocks:
            failures.append((label, "missing -- no @@%s block" % label))
            continue
        value, err = _coerce(field, blocks[label])
        if err:
            failures.append((label, err))
            if value is not None:
                values[label] = value  # keep partial for the prior-note
            continue
        values[label] = value
    return values, failures


# ---------------------------------------------------------------------------
# Assembly: {label: value} -> exact NarrativeDirector campaign-bible shape
# ---------------------------------------------------------------------------

def assemble_bible(v):
    """Build the production nested shape explicitly. All structure lives here in
    code; the model never wrote a brace. Missing labels fall back to "" / [] so
    assembly never throws (validation already flagged them upstream)."""
    def g(label, default=""):
        return v.get(label, default)

    trail_id = g("rumor.trail_id")
    if trail_id and not str(trail_id).startswith("rumor_trail."):
        trail_id = "rumor_trail." + str(trail_id)

    # Guarantee the two hard-required banned phrases regardless of what the model
    # returned -- code owns structure, so we don't hope the model remembered.
    banned = list(g("banned_repeats", []))
    lowered = {str(b).strip().lower() for b in banned}
    for required in ("chosen one", "destiny"):
        if required not in lowered:
            banned.append(required)

    return {
        "campaign_title": g("campaign_title"),
        "campaign_logline": g("campaign_logline"),
        "opening_situation": g("opening_situation"),
        "main_mystery": g("main_mystery"),
        "act_1_outline": g("act_1_outline", []),
        "long_term_reveal": g("long_term_reveal"),
        "tone": g("tone"),
        "core_pressure": g("core_pressure"),
        "factions": {
            "zenith": g("factions.zenith"),
            "aurelia": g("factions.aurelia"),
            "vanguard": g("factions.vanguard"),
        },
        "kaelen_rule": g("kaelen_rule"),
        "kaelen_angle": g("kaelen_angle"),
        "kaelen_hint_plan": g("kaelen_hint_plan", []),
        "kaelen_hint_style": g("kaelen_hint_style"),
        "kaelen_never_reveal": g("kaelen_never_reveal"),
        "faction_reveal_rule": g("faction_reveal_rule"),
        "humor_rule": g("humor_rule"),
        "address_rule": g("address_rule"),
        "fallback_rule": g("fallback_rule"),
        "story_horizon_rule": g("story_horizon_rule"),
        "story_arcs": [{
            "name": g("story_arc.name"),
            "summary": g("story_arc.summary"),
        }],
        "rumor_trails": [{
            "name": g("rumor.name"),
            "trail_id": trail_id,
            "clue_count": 2,
            "hint_theme": g("rumor.hint_theme"),
            "clue_templates": g("rumor.clue_templates", []),
            "discovery_type": g("rumor.discovery_type"),
            "rarity": g("rumor.rarity"),
            "payoff": g("rumor.payoff"),
        }],
        "regeneration_triggers": [{
            "id": g("trigger.id"),
            "metric": g("trigger.metric"),
            "threshold": g("trigger.threshold", 0),
            "action": g("trigger.action"),
            "description": g("trigger.description"),
        }],
        "expansion_rules": g("expansion_rules", []),
        "banned_repeats": banned,
    }


# ---------------------------------------------------------------------------
# Ollama call + driver
# ---------------------------------------------------------------------------

def ollama_generate(prompt):
    """Plain-text generation. No format=json -- we WANT free text, code parses it.
    think=false per the gemma4 chain-of-thought-leak finding."""
    data = {"model": MODEL, "prompt": prompt, "stream": False, "think": False,
            "options": {"temperature": 0.6}}
    req = urllib.request.Request(
        OLLAMA_URL, data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8")).get("response", "")


def condense_text(text, limit):
    """Ask gemma to compress THIS exact sentence under `limit` chars. This works
    where the generic repair round fails: handing the model the text to shorten
    is a constrained rewrite task, not an open regeneration (tested 2026-07-02,
    247->108 in one pass). Returns the rewritten text, stripped of stray quotes."""
    prompt = (
        "Rewrite the following sentence so it is UNDER %d characters total.\n"
        "Keep the same meaning and the concrete details. Use plain ASCII.\n"
        "Do not add commentary or quotation marks.\n"
        "Return ONLY the rewritten sentence on one line.\n\n"
        "SENTENCE:\n%s" % (limit, text)
    )
    out = ollama_generate(prompt).strip()
    # Take the first non-empty line; drop wrapping quotes the model sometimes adds.
    for line in out.splitlines():
        line = line.strip().strip('"').strip("'").strip()
        if line:
            return line
    return out.strip()


def condense_overlong(values, verbose=True):
    """Length phase: for each over-cap text field, condense it (one focused
    pass); if the model still overshoots, code-truncate as a hard safety net so
    length can never fail. Runs after structure repair, before assembly."""
    def log(*a):
        if verbose:
            print(*a)
    for field in FIELDS:
        if field["kind"] != "text" or not field.get("max"):
            continue
        label = field["label"]
        value = values.get(label)
        if not isinstance(value, str) or len(value) <= field["max"]:
            continue
        log("== condense %s: %d > %d ==" % (label, len(value), field["max"]))
        shorter = condense_text(value, field["max"])
        # Keep the required keyword if condensing dropped it; else accept.
        keeps_kw = (not field.get("must_contain")
                    or any(kw in shorter.lower() for kw in field["must_contain"]))
        if shorter and keeps_kw and len(shorter) < len(value):
            value = shorter
        if len(value) > field["max"]:
            value = _truncate_words(value, field["max"])  # safety net
        log("   -> %d chars" % len(value))
        values[label] = value
    return values


def generate_bible(seed, max_repair_rounds=2, verbose=True):
    def log(*a):
        if verbose:
            print(*a)

    log("== one-shot (seed %s) ==" % seed)
    t0 = time.time()
    text = ollama_generate(build_oneshot_prompt(seed))
    log("  %.1fs, %d chars" % (time.time() - t0, len(text)))
    blocks = parse_blocks(text)
    values, failures = validate(blocks)
    log("  %d/%d fields valid" % (len(FIELDS) - len(failures), len(FIELDS)))

    round_no = 0
    while failures and round_no < max_repair_rounds:
        round_no += 1
        log("== repair round %d: %d field(s) ==" % (round_no, len(failures)))
        for lbl, reason in failures:
            log("   - %s: %s" % (lbl, reason))
        t0 = time.time()
        rtext = ollama_generate(build_repair_prompt(seed, failures, values))
        log("  %.1fs" % (time.time() - t0))
        rblocks = parse_blocks(rtext)
        # Only accept the labels we asked to repair; re-coerce and merge.
        still = []
        for label, _reason in failures:
            field = FIELDS_BY_LABEL[label]
            if label not in rblocks:
                still.append((label, "missing -- no @@%s block" % label))
                continue
            value, err = _coerce(field, rblocks[label])
            if err:
                still.append((label, err))
                if value is not None:
                    values[label] = value
                continue
            values[label] = value
        failures = still

    # Length phase runs last: structure is settled, now fit any over-cap text.
    condense_overlong(values, verbose=verbose)

    bible = assemble_bible(values)
    return bible, failures


def main():
    import os
    import sys
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else int(time.time()) % 1000000
    bible, failures = generate_bible(seed)
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "labeled_runs")
    os.makedirs(out_dir, exist_ok=True)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    path = os.path.join(out_dir, "bible_%s_seed%s.json" % (stamp, seed))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(bible, f, indent=2, ensure_ascii=False)
    print("\nwrote %s" % path)
    if failures:
        print("UNRESOLVED after repair (%d):" % len(failures))
        for lbl, reason in failures:
            print("  - %s: %s" % (lbl, reason))
    else:
        print("all %d fields validated." % len(FIELDS))


if __name__ == "__main__":
    main()
