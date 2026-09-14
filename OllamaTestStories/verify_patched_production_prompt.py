import datetime
import json
import os
import time
import urllib.request

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "gemma4:12b"

CREATIVE_LANES = [
    (
        "criminal economy",
        "center smuggling, forged manifests, protection rackets, stolen cargo, and who profits when legal trade breaks.",
    ),
    (
        "corporate espionage",
        "center deniable sabotage, leaked patents, dirty audits, black-budget security, and contracts that hide ownership.",
    ),
    (
        "infrastructure collapse",
        "center failing stations, broken relays, unsafe gates, repair scarcity, and factions blaming each other for neglect.",
    ),
    (
        "political succession",
        "center leadership disputes, emergency powers, contested permits, quiet coups, and brokers selling access.",
    ),
    (
        "salvage rights",
        "center wreck claims, disputed manifests, dead ships, insurance fraud, and evidence hidden in recovered parts.",
    ),
    (
        "debt and privatization",
        "center repossession, company towns, privatized security, predatory loans, and survival under owned infrastructure.",
    ),
    (
        "ecological or industrial hazard",
        "center toxic ore, failing life support, unsafe extraction, poisoned habitats, and coverups disguised as accidents.",
    ),
]

REQUIRED_KEYS = [
    "campaign_title",
    "campaign_logline",
    "opening_situation",
    "main_mystery",
    "act_1_outline",
    "long_term_reveal",
    "tone",
    "core_pressure",
    "kaelen_rule",
    "faction_reveal_rule",
    "humor_rule",
    "address_rule",
    "fallback_rule",
    "story_horizon_rule",
    "story_arcs",
    "rumor_trails",
    "regeneration_triggers",
    "expansion_rules",
    "banned_repeats",
]


def creative_lane_for_seed(seed):
    accumulator = 0
    for index, char in enumerate(seed):
        accumulator += ord(char) * (index + 1)
    return CREATIVE_LANES[abs(accumulator) % len(CREATIVE_LANES)]


def build_prompt(seed, idea_memory):
    lane_name, lane_guidance = creative_lane_for_seed(seed)
    return "\n".join(
        [
            "You are the large local story model for a procedural space game.",
            "Create a compact first-horizon campaign bible for one new campaign.",
            "Be concise. This is a startup-critical request; short valid JSON is better than rich prose.",
            "",
            "Hard constraints:",
            "- Keep the handcrafted first system anchored by Zenith, Aurelia, and Vanguard.",
            "- Do not reveal future frontier factions to the player up front.",
            "- Kaelen is the only fixed recurring NPC besides the player.",
            "- Kaelen cannot die and her full mystery must never be completely solved.",
            "- Kaelen must publicly appear as a broker, fixer, or contract handler, not a scavenger, scientist, commander, prophet, mechanic, AI, archive, or failsafe.",
            "- Kaelen's hidden identity can be strange, mundane, human, non-human, technological, or unknown, but the story bible must frame it as hidden director knowledge only.",
            "- New systems should reveal new factions, conflicts, ores, upgrades, rumors, and ships through gate travel.",
            "- Use dry, slightly dark PG-13 humor. Avoid repeating example jokes or catchphrases.",
            "- Include exactly one rumor trail that can eventually lead to a hidden discovery or endgame easter egg.",
            "- The rumor trail needs exactly two concrete clue templates and a discovery type.",
            "- Include exactly one story horizon regeneration trigger with a metric, threshold, and action.",
            "- If story extends later, append a new horizon. Do not retcon known player choices.",
            "- Keep every string under 140 characters unless the field says otherwise.",
            "",
            f"Campaign seed: {seed}",
            f"Creative lane for this campaign: {lane_name}.",
            f"Lane guidance: {lane_guidance}",
            "",
            "Anti-motif guidance:",
            "- Do not use a 'Zenith [single abstract noun]' title pattern.",
            "- Avoid overusing Kaelen-as-AI/archive/failsafe unless it is genuinely the freshest fit for this specific campaign lane.",
            "- Do not use Great Silence, Great Collapse, purge protocol, ancient signal, ghost signal, prophecy, alien owner, mysterious pulse, chosen one, or destiny as the core reveal.",
            "- Prefer campaign-facing secrets the player can chase through jobs: debt, fraud, leverage, sabotage, jurisdiction, inheritance, stolen cargo, repair scarcity, hidden ownership, or carefully buried identity hints.",
            "- Make the reveal fit the chosen creative lane instead of defaulting to cosmic explanation.",
            "",
            "Existing idea memory:",
            idea_memory,
            "",
            "Return only JSON. No markdown. No comments.",
            "Return exactly this object shape:",
            "{",
            '  "campaign_title": string,',
            '  "campaign_logline": string under 220 chars,',
            '  "opening_situation": string under 260 chars,',
            '  "main_mystery": string under 220 chars,',
            '  "act_1_outline": [three strings under 180 chars each],',
            '  "long_term_reveal": string under 220 chars,',
            '  "tone": string,',
            '  "core_pressure": string,',
            '  "kaelen_rule": string that says she is publicly a broker, fixer, or contract handler,',
            '  "faction_reveal_rule": string,',
            '  "humor_rule": string,',
            '  "address_rule": string describing how NPCs address the player,',
            '  "fallback_rule": string describing how to handle missing story data,',
            '  "story_horizon_rule": string,',
            '  "story_arcs": [{"name": string, "summary": string under 180 chars}],',
            '  "rumor_trails": [{"name": string, "trail_id": "rumor_trail." plus snake_case_id, "clue_count": 2, "hint_theme": string, "clue_templates": [two strings], "discovery_type": "hidden_discovery|secret_route|rare_upgrade|faction_secret|endgame_easter_egg", "rarity": "local|uncommon|rare|legendary", "payoff": string under 180 chars}],',
            '  "regeneration_triggers": [{"id": snake_case_string, "metric": "prepared_systems_remaining|active_story_arcs_remaining|rumor_trails_remaining|major_arc_state", "threshold": number, "action": "append_story_horizon|append_rumor_trail|append_story_arc", "description": string}],',
            '  "expansion_rules": [two strings],',
            '  "banned_repeats": [string]',
            "}",
            "Use exactly one story_arcs item, one rumor_trails item, and one regeneration_triggers item.",
        ]
    )


def call_ollama(prompt, seed):
    body = {
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "keep_alive": "30m",
        "think": False,
        "options": {
            "temperature": 0.95,
            "num_predict": 900,
            "seed": seed,
        },
    }
    req = urllib.request.Request(
        OLLAMA_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    start = time.time()
    with urllib.request.urlopen(req, timeout=180) as response:
        envelope = json.loads(response.read().decode("utf-8"))
    return envelope, round(time.time() - start, 2)


def evaluate(response_text):
    try:
        parsed = json.loads(response_text)
    except Exception as exc:
        return {"valid": False, "error": str(exc), "missing_keys": REQUIRED_KEYS}
    missing = [key for key in REQUIRED_KEYS if key not in parsed]
    return {
        "valid": not missing,
        "missing_keys": missing,
        "title": parsed.get("campaign_title", ""),
        "long_term_reveal": parsed.get("long_term_reveal", ""),
    }


def main():
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = os.path.join(
        r"C:\CodingProjects\SpaceGame\OllamaTestStories",
        f"{stamp}_patched_production_prompt",
    )
    os.makedirs(out_dir, exist_ok=True)
    idea_memory = "No prior generated ideas recorded yet."
    summaries = []
    for index in range(3):
        campaign_seed = f"patched-prod-{index + 1:02d}"
        prompt = build_prompt(campaign_seed, idea_memory)
        request_seed = int(time.time()) + index * 101
        print(f"candidate {index + 1}/3 seed={campaign_seed}")
        envelope, elapsed = call_ollama(prompt, request_seed)
        response_text = envelope.get("response", "")
        evaluation = evaluate(response_text)
        evaluation["elapsed_seconds"] = elapsed
        evaluation["done_reason"] = envelope.get("done_reason", "")
        evaluation["eval_count"] = envelope.get("eval_count", 0)
        summaries.append(evaluation)
        with open(os.path.join(out_dir, f"candidate_{index + 1:02d}_prompt.txt"), "w", encoding="utf-8") as file:
            file.write(prompt)
        with open(os.path.join(out_dir, f"candidate_{index + 1:02d}_envelope.json"), "w", encoding="utf-8") as file:
            json.dump(envelope, file, indent=2)
        with open(os.path.join(out_dir, f"candidate_{index + 1:02d}_story.json"), "w", encoding="utf-8") as file:
            file.write(response_text)
        print(
            f"  valid={evaluation['valid']} missing={evaluation['missing_keys']} "
            f"title={evaluation.get('title', '')!r} elapsed={elapsed}s"
        )
    with open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8") as file:
        json.dump(summaries, file, indent=2)
    print(f"saved {out_dir}")


if __name__ == "__main__":
    main()
