import argparse
import json
import re
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path


OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
MODEL = "gemma4:12b"
OUT_DIR = Path(__file__).resolve().parent


REQUIRED_FIELDS = [
    "campaign_title",
    "campaign_subtitle",
    "campaign_logline",
    "campaign_pitch",
    "campaign_story_summary",
    "tone",
    "opening_status_quo",
    "visible_crisis",
    "hidden_crisis",
    "why_now",
    "player_role",
    "kaelen_public_role",
    "kaelen_secret_angle",
    "main_mystery_question",
    "main_mystery_false_answer",
    "main_mystery_true_answer_hint",
    "long_term_reveal_direction",
    "act_1_name",
    "act_1_goal",
    "act_1_opening_incident",
    "act_1_midpoint_turn",
    "act_1_finale",
    "act_1_player_takeaway",
    "starter_mission_title",
    "starter_mission_reason",
    "starter_enemy_identity",
    "starter_enemy_knows",
    "starter_mission_aftershock",
    "zenith_current_problem",
    "aurelia_current_problem",
    "vanguard_current_problem",
    "faction_conflict_triangle",
    "neutral_space_pressure",
    "recurring_clue_name",
    "recurring_clue_signal",
    "recurring_clue_first_appearance",
    "recurring_clue_escalation",
    "recurring_clue_payoff_hint",
    "rumor_trail_name",
    "rumor_trail_id",
    "rumor_hint_theme",
    "rumor_clue_templates",
    "rumor_discovery_type",
    "rumor_rarity",
    "rumor_payoff",
    "gate_horizon_tease",
    "new_system_reveal_rule",
    "future_pressure_tease",
    "future_ore_or_upgrade_tease",
    "story_regeneration_trigger",
    "kaelen_address_rule",
    "kaelen_never_reveal_rule",
    "humor_rule",
    "fallback",
    "banned_repeats",
    "story_questions_for_future_generation",
]

COMPACT_REQUIRED = [
    "campaign_title",
    "campaign_subtitle",
    "campaign_logline",
    "campaign_pitch",
    "campaign_story_summary",
    "tone",
    "opening",
    "mystery",
    "kaelen",
    "factions",
    "act_1",
    "starter_mission",
    "recurring_clue",
    "rumor_trail",
    "horizon",
    "rules",
    "story_questions_for_future_generation",
]


ALLOWED_DISCOVERY_TYPES = {
    "hidden_discovery",
    "secret_route",
    "rare_upgrade",
    "faction_secret",
    "endgame_easter_egg",
}
ALLOWED_RARITIES = {"local", "uncommon", "rare", "legendary"}
ALLOWED_METRICS = {
    "prepared_systems_remaining",
    "active_story_arcs_remaining",
    "rumor_trails_remaining",
    "major_arc_state",
}
ALLOWED_ACTIONS = {
    "append_story_horizon",
    "append_rumor_trail",
    "append_story_arc",
}


def prompt_variant(name: str) -> str:
    if name.startswith("compact_"):
        compact_base = """You are the large local story model for SpaceGame, a procedural space game.

Create a first campaign story bible. It must contain a real playable story premise, not just rules.

Creative constraints:
- First system factions: Zenith, Aurelia, Vanguard.
- Do not reveal future frontier factions up front.
- Kaelen is the only fixed recurring NPC besides the player.
- Kaelen cannot die, and her full mystery must never be solved.
- Kaelen appears publicly as a broker, fixer, and contract handler. Do not make her publicly a gate scientist, official liaison, commander, prophet, or mechanic.
- Kaelen may privately know more than she admits.
- The player starts as a broke independent pilot, not a chosen one.
- The first mission must be a simple combat tutorial against exactly one Reaver or Reaver-like hostile ship.
- The starter enemy is one hostile ship. Do not write a swarm, fleet, squad, drone cloud, or multi-enemy encounter.
- The story must support mining, salvage, delivery, combat, station services, rumors, and gate exploration.
- Use dry, slightly dark PG-13 frontier humor.
- Use plain ASCII punctuation only.
- Do not default to an ancient signal, ghost signal, prophecy, alien owner, or mysterious pulse. Those are allowed only if they are genuinely the best fit.
- Avoid the phrases "Ghost Signal", "Echoes of the Void", and "mysterious pulse" unless there is no better idea.
- The hidden crisis may be economic, political, criminal, environmental, technological, logistical, or infrastructure-based.
- Starter mission fields must describe story reasons, not tutorial reasons. Do not use the word "tutorial".
- Do not output placeholder text, schema names, percent signs, "s01", "s02", "500 words", or meta instructions inside story fields.
- Copy every JSON key exactly as shown. Do not rename fallback, aurelia_problem, first_appearance, or any other key.
- Do not name future factions in the first bible. Tease future factions by role, rumor, pressure, or unknown origin only.
- Future questions must leave room for other campaigns to become different. Do not force a recurring motif, culprit, technology, prophecy, ancient species, signal, or final explanation.
- Future questions must stay near the playable campaign: contracts, faction leverage, supply routes, gate access, Kaelen's deals, prices, risks, rumors, and player choices.
- Future questions must not ask about the whole universe, central government, creation myths, ancient species, pre-spaceflight relics, or final answers.

Return only the requested JSON object. Do not include a thought, reasoning, notes, markdown, or extra keys.
Write concrete story content for every field.
Use clean, direct English.
Most string values must be one short sentence under 24 words.
campaign_pitch must be 4 short sentences: player situation, faction pressure, immediate job loop, hidden trouble.
campaign_story_summary must be 7 short sentences and include: player role, Kaelen, the starter Reaver incident, faction conflict, recurring clue, hidden crisis, and Act 1 direction.
Do not ramble. Do not repeat words. Do not invent joke placeholders.
story_questions_for_future_generation must be natural open-ended questions beginning with What, Why, How, Who, Where, or Which.
rules.banned_repeats must include "chosen one" and "destiny", plus any repeated phrases this story should avoid.
rules.banned_repeats must be normal phrases, not IDs, schema words, or strings with underscores.

Use exactly this JSON shape:
{
  "campaign_title": "",
  "campaign_subtitle": "",
  "campaign_logline": "",
  "campaign_pitch": "",
  "campaign_story_summary": "",
  "tone": "",
  "opening": {
    "status_quo": "",
    "visible_crisis": "",
    "hidden_crisis": "",
    "why_now": "",
    "player_role": ""
  },
  "mystery": {
    "question": "",
    "false_answer": "",
    "true_answer_hint": "",
    "long_term_reveal_direction": ""
  },
  "kaelen": {
    "public_role": "",
    "secret_angle": "",
    "address_rule": "",
    "never_reveal_rule": ""
  },
  "factions": {
    "zenith_problem": "",
    "aurelia_problem": "",
    "vanguard_problem": "",
    "conflict_triangle": "",
    "neutral_space_pressure": ""
  },
  "act_1": {
    "name": "",
    "goal": "",
    "opening_incident": "",
    "midpoint_turn": "",
    "finale": "",
    "player_takeaway": ""
  },
  "starter_mission": {
    "title": "",
    "reason": "",
    "enemy_identity": "",
    "enemy_knows": "",
    "after_effect": ""
  },
  "recurring_clue": {
    "name": "",
    "signal": "",
    "first_appearance": "",
    "escalation": "",
    "payoff_hint": ""
  },
  "rumor_trail": {
    "name": "",
    "trail_id": "rumor_trail.snake_case_id",
    "hint_theme": "",
    "clue_templates": ["", ""],
    "discovery_type": "hidden_discovery|secret_route|rare_upgrade|faction_secret|endgame_easter_egg",
    "rarity": "local|uncommon|rare|legendary",
    "payoff": ""
  },
  "horizon": {
    "gate_tease": "",
    "new_system_reveal_rule": "",
    "future_pressure_tease": "",
    "future_ore_or_upgrade_tease": "",
    "regeneration_trigger": {
      "id": "snake_case_id",
      "metric": "prepared_systems_remaining|active_story_arcs_remaining|rumor_trails_remaining|major_arc_state",
      "threshold": 0,
      "action": "append_story_horizon|append_rumor_trail|append_story_arc",
      "description": ""
    }
  },
  "rules": {
    "humor_rule": "",
    "fallback": "",
    "banned_repeats": []
  },
  "story_questions_for_future_generation": ["", "", "", "", ""]
}
"""
        compact_endings = {
            "compact_structured": "",
            "compact_json": "",
            "compact_resource": "\nStory flavor: focus on resource scarcity, debt, trade routes, ore claims, and who profits from shortages.",
            "compact_criminal": "\nStory flavor: focus on smuggling, forged contracts, missing cargo, ship theft, and criminal pressure beneath normal commerce.",
            "compact_political": "\nStory flavor: focus on faction leverage, corrupt permits, patrol jurisdiction, station politics, and deniable work.",
            "compact_salvage": "\nStory flavor: focus on wreckage, salvage rights, old manifests, disputed claims, and what dead ships reveal.",
        }
        return compact_base + compact_endings.get(name, "")
    shared = """You are the large local story model for SpaceGame, a procedural space game.

Create the first campaign story bible for a new game. This must be useful to game code, but it must also contain a real campaign premise the player can feel: an opening situation, a visible problem, a hidden problem, early objectives, faction tension, recurring clues, and long-term mystery direction.

Important: do not just write rules. Fill the fields with story content.

Creative constraints:
- The first handcrafted system is anchored by Zenith, Aurelia, and Vanguard.
- Do not reveal future frontier factions to the player up front.
- Kaelen is the only fixed recurring NPC besides the player.
- Kaelen cannot die.
- Kaelen appears publicly as a broker, fixer, and contract handler. Do not make her publicly a gate scientist, official liaison, commander, prophet, or mechanic.
- Kaelen may privately know more about gates, signals, missing ships, or old infrastructure than she admits.
- Kaelen's full mystery must never be completely solved.
- New systems should reveal new factions, conflicts, ores, upgrades, rumors, and ships through gate travel.
- Tone is PG-13 frontier space opera with dry, slightly dark humor.
- The player begins as a broke new pilot with a working ship and very little context.
- The story should support mining, salvage, delivery, combat, station services, rumors, and gate exploration.
- Avoid making the player a chosen one, heir, prophecy figure, or uniquely destined hero.
- The player should matter because they are useful, deniable, independent, persistent, and make choices.
- The starter mission must support a simple first combat tutorial against exactly one Reaver or Reaver-like hostile ship.
- The starter enemy can know one small unsettling clue, but must not dump the whole mystery.
- Use plain ASCII punctuation only. No smart quotes, em dashes, accented characters, or mojibake.
- Keep future reveals flexible. Give direction, not a final answer.

Return only valid JSON. No markdown. No comments.

Fill this object exactly:
{
  "campaign_title": "",
  "campaign_subtitle": "",
  "campaign_logline": "",
  "campaign_pitch": "",
  "campaign_story_summary": "",

  "tone": "",
  "opening_status_quo": "",
  "visible_crisis": "",
  "hidden_crisis": "",
  "why_now": "",
  "player_role": "",
  "kaelen_public_role": "",
  "kaelen_secret_angle": "",

  "main_mystery_question": "",
  "main_mystery_false_answer": "",
  "main_mystery_true_answer_hint": "",
  "long_term_reveal_direction": "",

  "act_1_name": "",
  "act_1_goal": "",
  "act_1_opening_incident": "",
  "act_1_midpoint_turn": "",
  "act_1_finale": "",
  "act_1_player_takeaway": "",

  "starter_mission_title": "",
  "starter_mission_reason": "",
  "starter_enemy_identity": "",
  "starter_enemy_knows": "",
  "starter_mission_aftershock": "",

  "zenith_current_problem": "",
  "aurelia_current_problem": "",
  "vanguard_current_problem": "",
  "faction_conflict_triangle": "",
  "neutral_space_pressure": "",

  "recurring_clue_name": "",
  "recurring_clue_signal": "",
  "recurring_clue_first_appearance": "",
  "recurring_clue_escalation": "",
  "recurring_clue_payoff_hint": "",

  "rumor_trail_name": "",
  "rumor_trail_id": "rumor_trail.snake_case_id",
  "rumor_hint_theme": "",
  "rumor_clue_templates": ["", ""],
  "rumor_discovery_type": "hidden_discovery|secret_route|rare_upgrade|faction_secret|endgame_easter_egg",
  "rumor_rarity": "local|uncommon|rare|legendary",
  "rumor_payoff": "",

  "gate_horizon_tease": "",
  "new_system_reveal_rule": "",
  "future_pressure_tease": "",
  "future_ore_or_upgrade_tease": "",

  "story_regeneration_trigger": {
    "id": "snake_case_id",
    "metric": "prepared_systems_remaining|active_story_arcs_remaining|rumor_trails_remaining|major_arc_state",
    "threshold": 0,
    "action": "append_story_horizon|append_rumor_trail|append_story_arc",
    "description": ""
  },

  "kaelen_address_rule": "",
  "kaelen_never_reveal_rule": "",
  "humor_rule": "",
  "fallback": "",
  "banned_repeats": [],

  "story_questions_for_future_generation": ["", "", "", "", ""]
}

Field guidance:
- campaign_pitch should be 2-4 sentences and read like a real campaign premise, not metadata.
- campaign_story_summary should be 5-7 sentences summarizing Act 1 and the larger mystery direction in readable prose.
- hidden_crisis should be discoverable through clues over time.
- kaelen_secret_angle should suggest why Kaelen is involved without explaining her fully.
- starter_mission_reason must connect the first one-Reaver combat mission to the larger story without making it too important.
- starter_enemy_knows should be small but unsettling.
- faction_conflict_triangle should explain how Zenith, Aurelia, and Vanguard pressure each other.
- recurring_clue fields should describe a flexible clue pattern usable in missions, anomalies, salvage logs, station rumors, or gate travel.
- rumor_trail_id must start with "rumor_trail." and use lower snake_case after that.
- story_questions_for_future_generation should be open-ended questions. They must not force one answer.
- story_questions_for_future_generation must leave room for future stories to become different from this one. They should ask about pressure, consequence, secrets, costs, choices, or contradictions without forcing a specific motif, culprit, technology, prophecy, ancient species, signal, or final explanation.
"""
    endings = {
        "balanced": "\nMake the story feel playable, not literary. Prefer concrete pressures, jobs, rumors, and clues over abstract lore.",
        "mystery_forward": "\nPrioritize a strong mystery engine: the player should repeatedly find small, useful clues that raise better questions.",
        "faction_forward": "\nPrioritize faction tension: each early mission should be able to affect who has leverage without locking the whole plot.",
        "kaelen_forward": "\nPrioritize Kaelen's voice and role: she is useful, funny, guarded, profit-minded, and more informed than she admits.",
    }
    return shared + endings[name]


def compact_schema() -> dict:
    string = {"type": "string"}
    string_array = {"type": "array", "items": string}
    return {
        "type": "object",
        "additionalProperties": False,
        "required": COMPACT_REQUIRED,
        "properties": {
            "campaign_title": string,
            "campaign_subtitle": string,
            "campaign_logline": string,
            "campaign_pitch": string,
            "campaign_story_summary": string,
            "tone": string,
            "opening": {
                "type": "object",
                "additionalProperties": False,
                "required": ["status_quo", "visible_crisis", "hidden_crisis", "why_now", "player_role"],
                "properties": {
                    "status_quo": string,
                    "visible_crisis": string,
                    "hidden_crisis": string,
                    "why_now": string,
                    "player_role": string,
                },
            },
            "mystery": {
                "type": "object",
                "additionalProperties": False,
                "required": ["question", "false_answer", "true_answer_hint", "long_term_reveal_direction"],
                "properties": {
                    "question": string,
                    "false_answer": string,
                    "true_answer_hint": string,
                    "long_term_reveal_direction": string,
                },
            },
            "kaelen": {
                "type": "object",
                "additionalProperties": False,
                "required": ["public_role", "secret_angle", "address_rule", "never_reveal_rule"],
                "properties": {
                    "public_role": string,
                    "secret_angle": string,
                    "address_rule": string,
                    "never_reveal_rule": string,
                },
            },
            "factions": {
                "type": "object",
                "additionalProperties": False,
                "required": ["zenith_problem", "aurelia_problem", "vanguard_problem", "conflict_triangle", "neutral_space_pressure"],
                "properties": {
                    "zenith_problem": string,
                    "aurelia_problem": string,
                    "vanguard_problem": string,
                    "conflict_triangle": string,
                    "neutral_space_pressure": string,
                },
            },
            "act_1": {
                "type": "object",
                "additionalProperties": False,
                "required": ["name", "goal", "opening_incident", "midpoint_turn", "finale", "player_takeaway"],
                "properties": {
                    "name": string,
                    "goal": string,
                    "opening_incident": string,
                    "midpoint_turn": string,
                    "finale": string,
                    "player_takeaway": string,
                },
            },
            "starter_mission": {
                "type": "object",
                "additionalProperties": False,
                "required": ["title", "reason", "enemy_identity", "enemy_knows", "after_effect"],
                "properties": {
                    "title": string,
                    "reason": string,
                    "enemy_identity": string,
                    "enemy_knows": string,
                    "after_effect": string,
                },
            },
            "recurring_clue": {
                "type": "object",
                "additionalProperties": False,
                "required": ["name", "signal", "first_appearance", "escalation", "payoff_hint"],
                "properties": {
                    "name": string,
                    "signal": string,
                    "first_appearance": string,
                    "escalation": string,
                    "payoff_hint": string,
                },
            },
            "rumor_trail": {
                "type": "object",
                "additionalProperties": False,
                "required": ["name", "trail_id", "hint_theme", "clue_templates", "discovery_type", "rarity", "payoff"],
                "properties": {
                    "name": string,
                    "trail_id": string,
                    "hint_theme": string,
                    "clue_templates": {"type": "array", "items": string, "minItems": 2, "maxItems": 2},
                    "discovery_type": {"type": "string", "enum": sorted(ALLOWED_DISCOVERY_TYPES)},
                    "rarity": {"type": "string", "enum": sorted(ALLOWED_RARITIES)},
                    "payoff": string,
                },
            },
            "horizon": {
                "type": "object",
                "additionalProperties": False,
                "required": ["gate_tease", "new_system_reveal_rule", "future_pressure_tease", "future_ore_or_upgrade_tease", "regeneration_trigger"],
                "properties": {
                    "gate_tease": string,
                    "new_system_reveal_rule": string,
                    "future_pressure_tease": string,
                    "future_ore_or_upgrade_tease": string,
                    "regeneration_trigger": {
                        "type": "object",
                        "additionalProperties": False,
                        "required": ["id", "metric", "threshold", "action", "description"],
                        "properties": {
                            "id": string,
                            "metric": {"type": "string", "enum": sorted(ALLOWED_METRICS)},
                            "threshold": {"type": "integer"},
                            "action": {"type": "string", "enum": sorted(ALLOWED_ACTIONS)},
                            "description": string,
                        },
                    },
                },
            },
            "rules": {
                "type": "object",
                "additionalProperties": False,
                "required": ["humor_rule", "fallback", "banned_repeats"],
                "properties": {
                    "humor_rule": string,
                    "fallback": string,
                    "banned_repeats": string_array,
                },
            },
            "story_questions_for_future_generation": {"type": "array", "items": string, "minItems": 5, "maxItems": 5},
        },
    }


def call_ollama(prompt: str, seed: int, timeout: int, use_schema: bool = False) -> dict:
    format_spec = compact_schema() if use_schema else "json"
    payload = {
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "format": format_spec,
        "keep_alive": "30m",
        "options": {
            "temperature": 0.45,
            "num_predict": 2800,
            "seed": seed,
        },
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        OLLAMA_URL,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def parse_response(envelope: dict) -> tuple[dict | None, str]:
    response = str(envelope.get("response", "")).strip()
    if not response:
        return None, "empty_response"
    try:
        return json.loads(response), ""
    except json.JSONDecodeError as exc:
        # Try to recover if the model wrapped JSON in accidental text.
        start = response.find("{")
        end = response.rfind("}")
        if start >= 0 and end > start:
            try:
                return json.loads(response[start:end + 1]), ""
            except json.JSONDecodeError:
                pass
        return None, f"json_parse_failed: {exc}"


def is_ascii_tree(value) -> bool:
    try:
        json.dumps(value, ensure_ascii=False).encode("ascii")
        return True
    except UnicodeEncodeError:
        return False


def nonempty_string(data: dict, field: str) -> bool:
	return isinstance(data.get(field), str) and bool(data[field].strip())


def nested_get(data: dict, path: str, default=""):
    current = data
    for part in path.split("."):
        if not isinstance(current, dict):
            return default
        current = current.get(part, default)
    return current


def normalize_compact_story(data: dict | None) -> dict | None:
    if not isinstance(data, dict):
        return data
    normalized = json.loads(json.dumps(data))
    if "story_questions_for_future_generation" not in normalized:
        for alias in [
            "story_questions_for_future_thought_generation",
            "future_generation_questions",
        ]:
            if alias in normalized:
                normalized["story_questions_for_future_generation"] = normalized.get(alias, [])
                break
    factions = normalized.get("factions")
    if isinstance(factions, dict):
        if "vanguard_problem" not in factions and "v_problem" in factions:
            factions["vanguard_problem"] = factions.get("v_problem", "")
        if "aurelia_problem" not in factions and "aurelia_rule" in factions:
            factions["aurelia_problem"] = factions.get("aurelia_rule", "")
    act_1 = normalized.get("act_1")
    if isinstance(act_1, dict):
        if "opening_incident" not in act_1 and "opening_itement" in act_1:
            act_1["opening_incident"] = act_1.get("opening_itement", "")
    mystery = normalized.get("mystery")
    if isinstance(mystery, dict):
        if "true_answer_hint" not in mystery and "true__hint" in mystery:
            mystery["true_answer_hint"] = mystery.get("true__hint", "")
    starter = normalized.get("starter_mission")
    if isinstance(starter, dict):
        if "after_effect" not in starter and "aftershock" in starter:
            starter["after_effect"] = starter.get("aftershock", "")
        if "after_effect" not in starter and "aftershock_reason" in starter:
            starter["after_effect"] = starter.get("aftershock_reason", "")
    clue = normalized.get("recurring_clue")
    if isinstance(clue, dict):
        if "first_appearance" not in clue and "first__appearance" in clue:
            clue["first_appearance"] = clue.get("first__appearance", "")
    rules = normalized.get("rules")
    if isinstance(rules, dict):
        if "humor_rule" not in rules and "humor__rule" in rules:
            rules["humor_rule"] = rules.get("humor__rule", "")
        if "fallback" not in rules and "fallback_rule" in rules:
            rules["fallback"] = rules.get("fallback_rule", "")
        if "fallback" not in rules and "fall_back_rule" in rules:
            rules["fallback"] = rules.get("fall_back_rule", "")
    trail = normalized.get("rumor_trail")
    if isinstance(trail, dict):
        if trail.get("discovery_type") == "hidden_route":
            trail["discovery_type"] = "secret_route"
    trigger = nested_get(normalized, "horizon.regeneration_trigger", None)
    if isinstance(trigger, dict):
        raw_id = str(trigger.get("id", "")).strip_edges() if hasattr(str, "strip_edges") else str(trigger.get("id", "")).strip()
        clean_id = re.sub(r"[^a-z0-9_]+", "_", raw_id.lower()).strip("_")
        if clean_id:
            trigger["id"] = clean_id
    return normalized


def validate_compact_story(data: dict | None) -> dict:
    data = normalize_compact_story(data)
    errors = []
    warnings = []
    score = 100
    if data is None:
        return {"valid": False, "score": 0, "errors": ["no_json"], "warnings": []}
    for field in COMPACT_REQUIRED:
        if field not in data:
            errors.append(f"missing_field:{field}")
            score -= 5
    if not is_ascii_tree(data):
        errors.append("non_ascii_output")
        score -= 12
    required_nested = [
        "opening.status_quo",
        "opening.visible_crisis",
        "opening.hidden_crisis",
        "opening.why_now",
        "opening.player_role",
        "mystery.question",
        "mystery.false_answer",
        "mystery.true_answer_hint",
        "mystery.long_term_reveal_direction",
        "kaelen.public_role",
        "kaelen.secret_angle",
        "kaelen.address_rule",
        "kaelen.never_reveal_rule",
        "factions.zenith_problem",
        "factions.aurelia_problem",
        "factions.vanguard_problem",
        "factions.conflict_triangle",
        "factions.neutral_space_pressure",
        "act_1.name",
        "act_1.goal",
        "act_1.opening_incident",
        "act_1.midpoint_turn",
        "act_1.finale",
        "act_1.player_takeaway",
        "starter_mission.title",
        "starter_mission.reason",
        "starter_mission.enemy_identity",
        "starter_mission.enemy_knows",
        "starter_mission.after_effect",
        "recurring_clue.name",
        "recurring_clue.signal",
        "recurring_clue.first_appearance",
        "recurring_clue.escalation",
        "recurring_clue.payoff_hint",
        "rumor_trail.name",
        "rumor_trail.trail_id",
        "rumor_trail.hint_theme",
        "rumor_trail.payoff",
        "horizon.gate_tease",
        "horizon.new_system_reveal_rule",
        "horizon.future_pressure_tease",
        "horizon.future_ore_or_upgrade_tease",
        "horizon.regeneration_trigger.id",
        "horizon.regeneration_trigger.description",
        "rules.humor_rule",
        "rules.fallback",
    ]
    for path in required_nested:
        if not str(nested_get(data, path, "")).strip():
            errors.append(f"missing_nested:{path}")
            score -= 4
    blob = json.dumps(data, ensure_ascii=True).lower()
    placeholder_terms = [
        "system_name_",
        "_s01",
        "_s02",
        "_s03",
        "500 words",
        "100%",
        "50%",
        "draft_of",
        "prompt_t",
        "schema",
    ]
    for term in placeholder_terms:
        if term in blob:
            errors.append(f"placeholder_text:{term}")
            score -= 10
            break
    for path in [
        "campaign_title",
        "campaign_logline",
        "campaign_pitch",
        "campaign_story_summary",
        "opening.visible_crisis",
        "opening.hidden_crisis",
        "kaelen.public_role",
        "kaelen.secret_angle",
        "starter_mission.reason",
        "starter_mission.enemy_identity",
        "starter_mission.enemy_knows",
        "rumor_trail.trail_id",
    ]:
        if not str(nested_get(data, path, "")).strip():
            errors.append(f"empty_string:{path}")
            score -= 4
    public_role = str(nested_get(data, "kaelen.public_role", "")).lower()
    if not any(word in public_role for word in ["broker", "fixer", "contract"]):
        errors.append("kaelen_public_role_not_broker_fixer_contract")
        score -= 10
    if any(word in public_role for word in ["liaison", "scientist", "commander", "mechanic", "prophet"]):
        errors.append("kaelen_public_role_drift")
        score -= 10
    starter_blob = " ".join(
        str(nested_get(data, path, "")) for path in [
            "starter_mission.reason",
            "starter_mission.enemy_identity",
            "starter_mission.enemy_knows",
            "starter_mission.after_effect",
        ]
    ).lower()
    if "reaver" not in starter_blob:
        errors.append("starter_mission_missing_reaver")
        score -= 12
    if any(term in starter_blob for term in ["fleet", "squadron", "armada", "multiple ships"]):
        warnings.append("starter_mission_may_be_too_large")
        score -= 4
    if "tutorial" in starter_blob:
        errors.append("starter_mission_uses_tutorial_meta_language")
        score -= 8
    trail_id = str(nested_get(data, "rumor_trail.trail_id", ""))
    if not re.fullmatch(r"rumor_trail\.[a-z0-9_]+", trail_id):
        errors.append("bad_rumor_trail_id_format")
        score -= 8
    clues = nested_get(data, "rumor_trail.clue_templates", [])
    if not isinstance(clues, list) or len(clues) != 2 or not all(str(c).strip() for c in clues):
        errors.append("rumor_clue_templates_not_two_nonempty_items")
        score -= 8
    if nested_get(data, "rumor_trail.discovery_type", "") not in ALLOWED_DISCOVERY_TYPES:
        errors.append("bad_rumor_discovery_type")
        score -= 5
    if nested_get(data, "rumor_trail.rarity", "") not in ALLOWED_RARITIES:
        errors.append("bad_rumor_rarity")
        score -= 5
    trigger = nested_get(data, "horizon.regeneration_trigger", {})
    if not isinstance(trigger, dict):
        errors.append("story_regeneration_trigger_not_object")
        score -= 8
    else:
        if not re.fullmatch(r"[a-z0-9_]+", str(trigger.get("id", ""))):
            errors.append("bad_trigger_id_format")
            score -= 4
        if trigger.get("metric") not in ALLOWED_METRICS:
            errors.append("bad_trigger_metric")
            score -= 5
        if trigger.get("action") not in ALLOWED_ACTIONS:
            errors.append("bad_trigger_action")
            score -= 5
        if not isinstance(trigger.get("threshold"), int):
            warnings.append("trigger_threshold_not_int")
            score -= 2
    questions = data.get("story_questions_for_future_generation")
    if not isinstance(questions, list) or len(questions) != 5:
        errors.append("story_questions_not_five_items")
        score -= 6
    else:
        natural_starters = ("what ", "why ", "how ", "who ", "where ", "which ")
        unnatural = [q for q in questions if not str(q).lower().startswith(natural_starters)]
        if unnatural:
            errors.append("future_questions_not_natural_open_questions")
            score -= 8
        broad_terms = ["whole universe", "scale of the universe", "central government", "creation", "pre-spaceflight", "ancient species", "final answer"]
        if any(any(term in str(q).lower() for term in broad_terms) for q in questions):
            errors.append("future_questions_too_cosmic_or_final")
            score -= 8
        leading = [q for q in questions if str(q).lower().startswith(("is ", "does ", "did ", "will "))]
        if len(leading) >= 3:
            warnings.append("future_questions_may_be_too_yes_no")
            score -= 3
        motif_terms = ["ancient", "signal", "prophecy", "alien", "pre-human", "gate network", "owner"]
        motif_hits = 0
        for q in questions:
            lower_q = str(q).lower()
            if any(term in lower_q for term in motif_terms):
                motif_hits += 1
        if motif_hits >= 3:
            warnings.append("future_questions_may_force_a_story_motif")
            score -= 6
    if len(str(data.get("campaign_pitch", "")).split()) < 35:
        warnings.append("campaign_pitch_feels_thin")
        score -= 4
    if len(str(data.get("campaign_story_summary", "")).split()) < 65:
        warnings.append("campaign_story_summary_feels_thin")
        score -= 4
    hidden = str(nested_get(data, "opening.hidden_crisis", "")).lower()
    if not any(word in hidden for word in ["gate", "route", "trade", "resource", "energy", "fuel", "ore", "alloy", "supply", "infrastructure", "corporate", "faction", "ship", "station", "debt", "map", "claim", "salvage", "mining"]):
        warnings.append("hidden_crisis_may_not_connect_to_playable_systems")
        score -= 4
    future_tease = str(nested_get(data, "horizon.future_pressure_tease", ""))
    if re.search(r"\bcalled\s+the\s+[A-Z]", future_tease) or re.search(r"\b[A-Z][a-z]+\s+[A-Z][a-z]+\b", future_tease):
        errors.append("future_faction_tease_names_future_faction")
        score -= 8
    banned_blob = " ".join(map(str, nested_get(data, "rules.banned_repeats", []))).lower()
    if "chosen one" not in banned_blob or "destiny" not in banned_blob:
        errors.append("banned_repeats_missing_required_anti_chosen_one_terms")
        score -= 6
    if "_" in banned_blob:
        errors.append("banned_repeats_contains_schema_or_id_text")
        score -= 4
    return {
        "valid": not errors,
        "score": max(0, score),
        "errors": errors,
        "warnings": warnings,
    }


def validate_story(data: dict | None) -> dict:
    if isinstance(data, dict) and "opening" in data and "starter_mission" in data:
        return validate_compact_story(data)
    errors = []
    warnings = []
    score = 100
    if data is None:
        return {"valid": False, "score": 0, "errors": ["no_json"], "warnings": []}
    for field in REQUIRED_FIELDS:
        if field not in data:
            errors.append(f"missing_field:{field}")
            score -= 5
    for field in REQUIRED_FIELDS:
        if field in {
            "rumor_clue_templates",
            "story_regeneration_trigger",
            "banned_repeats",
            "story_questions_for_future_generation",
        }:
            continue
        if field in data and not nonempty_string(data, field):
            errors.append(f"empty_string:{field}")
            score -= 4
    if not is_ascii_tree(data):
        errors.append("non_ascii_output")
        score -= 12
    public_role = str(data.get("kaelen_public_role", "")).lower()
    if not any(word in public_role for word in ["broker", "fixer", "contract"]):
        errors.append("kaelen_public_role_not_broker_fixer_contract")
        score -= 10
    if any(word in public_role for word in ["liaison", "scientist", "commander", "mechanic", "prophet"]):
        errors.append("kaelen_public_role_drift")
        score -= 10
    starter_blob = " ".join(
        str(data.get(k, "")) for k in [
            "starter_mission_reason",
            "starter_enemy_identity",
            "starter_enemy_knows",
            "starter_mission_aftershock",
        ]
    ).lower()
    if "reaver" not in starter_blob:
        errors.append("starter_mission_missing_reaver")
        score -= 12
    if any(term in starter_blob for term in ["fleet", "squadron", "armada", "multiple ships"]):
        warnings.append("starter_mission_may_be_too_large")
        score -= 4
    trail_id = str(data.get("rumor_trail_id", ""))
    if not re.fullmatch(r"rumor_trail\.[a-z0-9_]+", trail_id):
        errors.append("bad_rumor_trail_id_format")
        score -= 8
    clues = data.get("rumor_clue_templates")
    if not isinstance(clues, list) or len(clues) != 2 or not all(str(c).strip() for c in clues):
        errors.append("rumor_clue_templates_not_two_nonempty_items")
        score -= 8
    if data.get("rumor_discovery_type") not in ALLOWED_DISCOVERY_TYPES:
        errors.append("bad_rumor_discovery_type")
        score -= 5
    if data.get("rumor_rarity") not in ALLOWED_RARITIES:
        errors.append("bad_rumor_rarity")
        score -= 5
    trigger = data.get("story_regeneration_trigger")
    if not isinstance(trigger, dict):
        errors.append("story_regeneration_trigger_not_object")
        score -= 8
    else:
        if not re.fullmatch(r"[a-z0-9_]+", str(trigger.get("id", ""))):
            errors.append("bad_trigger_id_format")
            score -= 4
        if trigger.get("metric") not in ALLOWED_METRICS:
            errors.append("bad_trigger_metric")
            score -= 5
        if trigger.get("action") not in ALLOWED_ACTIONS:
            errors.append("bad_trigger_action")
            score -= 5
        if not isinstance(trigger.get("threshold"), int):
            warnings.append("trigger_threshold_not_int")
            score -= 2
    questions = data.get("story_questions_for_future_generation")
    if not isinstance(questions, list) or len(questions) != 5:
        errors.append("story_questions_not_five_items")
        score -= 6
    else:
        leading = [q for q in questions if str(q).lower().startswith(("is ", "does ", "did ", "will "))]
        if len(leading) >= 3:
            warnings.append("future_questions_may_be_too_yes_no")
            score -= 3
        motif_terms = [
            "ancient",
            "signal",
            "prophecy",
            "alien",
            "pre-human",
            "gate network",
            "owner",
        ]
        motif_hits = 0
        for q in questions:
            lower_q = str(q).lower()
            if any(term in lower_q for term in motif_terms):
                motif_hits += 1
        if motif_hits >= 3:
            warnings.append("future_questions_may_force_a_story_motif")
            score -= 6
    pitch_len = len(str(data.get("campaign_pitch", "")).split())
    summary_len = len(str(data.get("campaign_story_summary", "")).split())
    if pitch_len < 35:
        warnings.append("campaign_pitch_feels_thin")
        score -= 4
    if summary_len < 65:
        warnings.append("campaign_story_summary_feels_thin")
        score -= 4
    hidden = str(data.get("hidden_crisis", "")).lower()
    if not any(word in hidden for word in ["gate", "route", "trade", "resource", "faction", "ship", "station", "debt", "map", "claim", "salvage"]):
        warnings.append("hidden_crisis_may_not_connect_to_playable_systems")
        score -= 4
    banned_blob = " ".join(map(str, data.get("banned_repeats", []))).lower()
    if "chosen" not in banned_blob and "destiny" not in banned_blob:
        warnings.append("banned_repeats_missing_anti_chosen_one_terms")
        score -= 2
    return {
        "valid": not errors,
        "score": max(0, score),
        "errors": errors,
        "warnings": warnings,
    }


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=True), encoding="utf-8")


def append_progress(line: str) -> None:
    progress = OUT_DIR / "progress.md"
    with progress.open("a", encoding="utf-8") as f:
        f.write(line.rstrip() + "\n")


def meta_questions_prompt() -> str:
    return """You are designing uniqueness seeds for one procedural SpaceGame campaign.

Do not write the final campaign bible yet.
Create a compact creative brief that will help a second model call write a unique campaign.

Constraints:
- First system factions are Zenith, Aurelia, and Vanguard.
- Kaelen is always a broker/fixer publicly, never a public scientist, commander, prophet, or mechanic.
- The player starts as a broke independent pilot, not a chosen one.
- The first mission is exactly one hostile Reaver or Reaver-like ship.
- Do not force a recurring motif like ancient signal, ghost signal, prophecy, alien owner, or mysterious pulse.
- Leave room for future campaigns to be very different.
- Use plain ASCII.

Return only JSON with this shape:
{
  "creative_lane": "",
  "freshness_rule": "",
  "avoid_motifs": ["", "", "", ""],
  "core_story_questions": ["", "", "", "", ""],
  "starter_mission_questions": ["", "", ""],
  "kaelen_questions": ["", "", ""],
  "faction_questions": ["", "", ""],
  "future_generation_questions": ["", "", "", "", ""]
}

Question rules:
- Every question must begin with What, Why, How, Who, Where, or Which.
- Questions must not imply one fixed answer.
- Questions should ask about pressure, cost, consequence, contradiction, leverage, secrecy, or player choice.
"""


def validate_meta_brief(data: dict | None) -> dict:
    errors = []
    warnings = []
    score = 100
    if data is None:
        return {"valid": False, "score": 0, "errors": ["no_json"], "warnings": []}
    required = [
        "creative_lane",
        "freshness_rule",
        "avoid_motifs",
        "core_story_questions",
        "starter_mission_questions",
        "kaelen_questions",
        "faction_questions",
        "future_generation_questions",
    ]
    for field in required:
        if field not in data:
            errors.append(f"missing_field:{field}")
            score -= 8
    if not is_ascii_tree(data):
        warnings.append("non_ascii_meta_will_be_escaped")
        score -= 3
    natural_starters = ("what ", "why ", "how ", "who ", "where ", "which ")
    for field in [
        "core_story_questions",
        "starter_mission_questions",
        "kaelen_questions",
        "faction_questions",
        "future_generation_questions",
    ]:
        items = data.get(field, [])
        if not isinstance(items, list) or not items:
            errors.append(f"bad_question_list:{field}")
            score -= 8
            continue
        for q in items:
            if not str(q).lower().startswith(natural_starters):
                errors.append(f"closed_or_meta_question:{field}")
                score -= 3
                break
    motif_blob = " ".join(map(str, data.get("avoid_motifs", []))).lower()
    if "chosen" not in motif_blob and "prophecy" not in motif_blob:
        warnings.append("avoid_motifs_may_be_too_sparse")
        score -= 2
    return {
        "valid": not errors,
        "score": max(0, score),
        "errors": errors,
        "warnings": warnings,
    }


def answer_prompt_from_meta(meta: dict) -> str:
    return (
        prompt_variant("compact_json")
        + "\n\nCampaign uniqueness brief from pass 1:\n"
        + json.dumps(meta, indent=2, ensure_ascii=True)
        + "\n\nUse the brief to make this campaign specific. Answer the questions through the fields, but do not copy the questions as answers."
        + "\nDo not include the pass-1 brief in the output. Return only the final campaign JSON."
        + "\nThe first characters of your response must be {\"campaign_title\"."
        + "\nDo not include a thought key, notes, commentary, or reasoning."
    )


def run_two_pass_batch(round_name: str, count: int, timeout: int) -> None:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    round_dir = OUT_DIR / f"{timestamp}_{round_name}"
    round_dir.mkdir(parents=True, exist_ok=True)
    append_progress(f"\n## {timestamp} {round_name} two_pass")
    append_progress(f"- Model: `{MODEL}`")
    append_progress(f"- Candidates: {count}")
    summaries = []
    seed_base = int(time.time()) % 1000000
    meta_prompt = meta_questions_prompt()
    (round_dir / "prompt_meta_questions.txt").write_text(meta_prompt, encoding="utf-8")
    for index in range(count):
        name = f"two_pass_{index + 1:02d}"
        seed = seed_base + index * 31
        started = time.time()
        try:
            meta_envelope = call_ollama(meta_prompt, seed, timeout)
            meta_data, meta_parse_error = parse_response(meta_envelope)
            meta_validation = validate_meta_brief(meta_data)
            if meta_parse_error:
                meta_validation["errors"].append(meta_parse_error)
                meta_validation["valid"] = False
                meta_validation["score"] = 0
            write_json(round_dir / f"{name}_meta_envelope.json", meta_envelope)
            if meta_data is not None:
                write_json(round_dir / f"{name}_meta.json", meta_data)
            write_json(round_dir / f"{name}_meta_validation.json", meta_validation)
            if not meta_validation["valid"] or meta_data is None:
                elapsed = round(time.time() - started, 2)
                summary = {
                    "name": name,
                    "variant": "two_pass",
                    "seed": seed,
                    "elapsed_seconds": elapsed,
                    "valid": False,
                    "score": 0,
                    "title": "",
                    "logline": "",
                    "errors": ["meta_failed"] + meta_validation["errors"],
                    "warnings": meta_validation["warnings"],
                }
                summaries.append(summary)
                append_progress(f"- {name}: meta failed, elapsed={elapsed}s")
                continue
            final_prompt = answer_prompt_from_meta(meta_data)
            (round_dir / f"{name}_final_prompt.txt").write_text(final_prompt, encoding="utf-8")
            final_envelope = call_ollama(final_prompt, seed + 7, timeout)
            final_data, final_parse_error = parse_response(final_envelope)
            validation = validate_story(final_data)
            if final_parse_error:
                validation["errors"].append(final_parse_error)
                validation["valid"] = False
                validation["score"] = 0
            elapsed = round(time.time() - started, 2)
            write_json(round_dir / f"{name}_envelope.json", final_envelope)
            if final_data is not None:
                write_json(round_dir / f"{name}_story.json", final_data)
            write_json(round_dir / f"{name}_validation.json", validation)
            summary = {
                "name": name,
                "variant": "two_pass",
                "seed": seed,
                "elapsed_seconds": elapsed,
                "valid": validation["valid"],
                "score": validation["score"],
                "title": "" if final_data is None else final_data.get("campaign_title", ""),
                "logline": "" if final_data is None else final_data.get("campaign_logline", ""),
                "errors": validation["errors"],
                "warnings": validation["warnings"],
            }
            summaries.append(summary)
            append_progress(
                "- {name}: score={score}, valid={valid}, elapsed={elapsed}s, title={title}".format(
                    name=summary["name"],
                    score=summary["score"],
                    valid=summary["valid"],
                    elapsed=summary["elapsed_seconds"],
                    title=summary["title"],
                )
            )
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            elapsed = round(time.time() - started, 2)
            summary = {
                "name": name,
                "variant": "two_pass",
                "seed": seed,
                "elapsed_seconds": elapsed,
                "valid": False,
                "score": 0,
                "title": "",
                "logline": "",
                "errors": [f"request_failed:{exc}"],
                "warnings": [],
            }
            summaries.append(summary)
            write_json(round_dir / f"{name}_validation.json", summary)
            append_progress(f"- {name}: request failed, elapsed={elapsed}s")
    write_json(round_dir / "summary.json", summaries)
    best = sorted(summaries, key=lambda item: item["score"], reverse=True)[:3]
    append_progress("- Best candidates:")
    for item in best:
        append_progress(
            "  - {name}: score={score}, valid={valid}, title={title}".format(
                name=item["name"],
                score=item["score"],
                valid=item["valid"],
                title=item["title"],
            )
        )
    print(json.dumps({"round_dir": str(round_dir), "best": best}, indent=2))


def run_batch(round_name: str, variants: list[str], per_variant: int, timeout: int) -> None:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    round_dir = OUT_DIR / f"{timestamp}_{round_name}"
    round_dir.mkdir(parents=True, exist_ok=True)
    append_progress(f"\n## {timestamp} {round_name}")
    append_progress(f"- Model: `{MODEL}`")
    append_progress(f"- Variants: {', '.join(variants)}")
    append_progress(f"- Candidates per variant: {per_variant}")

    summaries = []
    seed_base = int(time.time()) % 1000000
    for variant in variants:
        prompt = prompt_variant(variant)
        (round_dir / f"prompt_{variant}.txt").write_text(prompt, encoding="utf-8")
        for index in range(per_variant):
            seed = seed_base + len(summaries) * 17 + index
            name = f"{variant}_{index + 1:02d}"
            started = time.time()
            try:
                envelope = call_ollama(
                    prompt,
                    seed,
                    timeout,
                    use_schema=variant == "compact_structured",
                )
                elapsed = round(time.time() - started, 2)
                data, parse_error = parse_response(envelope)
                validation = validate_story(data)
                if parse_error:
                    validation["errors"].append(parse_error)
                    validation["valid"] = False
                    validation["score"] = 0
                write_json(round_dir / f"{name}_envelope.json", envelope)
                if data is not None:
                    write_json(round_dir / f"{name}_story.json", data)
                write_json(round_dir / f"{name}_validation.json", validation)
                summary = {
                    "name": name,
                    "variant": variant,
                    "seed": seed,
                    "elapsed_seconds": elapsed,
                    "valid": validation["valid"],
                    "score": validation["score"],
                    "title": "" if data is None else data.get("campaign_title", ""),
                    "logline": "" if data is None else data.get("campaign_logline", ""),
                    "errors": validation["errors"],
                    "warnings": validation["warnings"],
                }
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
                elapsed = round(time.time() - started, 2)
                summary = {
                    "name": name,
                    "variant": variant,
                    "seed": seed,
                    "elapsed_seconds": elapsed,
                    "valid": False,
                    "score": 0,
                    "title": "",
                    "logline": "",
                    "errors": [f"request_failed:{exc}"],
                    "warnings": [],
                }
                write_json(round_dir / f"{name}_validation.json", summary)
            summaries.append(summary)
            append_progress(
                "- {name}: score={score}, valid={valid}, elapsed={elapsed}s, title={title}".format(
                    name=summary["name"],
                    score=summary["score"],
                    valid=summary["valid"],
                    elapsed=summary["elapsed_seconds"],
                    title=summary["title"],
                )
            )
    write_json(round_dir / "summary.json", summaries)
    best = sorted(summaries, key=lambda item: item["score"], reverse=True)[:3]
    append_progress("- Best candidates:")
    for item in best:
        append_progress(
            "  - {name}: score={score}, valid={valid}, title={title}".format(
                name=item["name"],
                score=item["score"],
                valid=item["valid"],
                title=item["title"],
            )
        )
    print(json.dumps({"round_dir": str(round_dir), "best": best}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--round", default="round")
    parser.add_argument("--variants", nargs="+", default=["balanced", "mystery_forward"])
    parser.add_argument("--per-variant", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--two-pass", action="store_true")
    args = parser.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    if args.two_pass:
        run_two_pass_batch(args.round, args.per_variant, args.timeout)
    else:
        run_batch(args.round, args.variants, args.per_variant, args.timeout)


if __name__ == "__main__":
    main()

