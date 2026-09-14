import json
import time
import urllib.request
import os
import datetime

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "gemma4:12b"

# This is the exact prompt currently built by NarrativeDirector.build_campaign_bible_prompt()
# in the production GDScript (scripts/ai/NarrativeDirector.gd), reproduced here so we can test
# the ACTUAL production prompt/schema against gemma4, not a hypothetical one.
PROMPT = "\n".join([
    "You are the large local story model for a procedural space game.",
    "Create a compact first-horizon campaign bible for one new campaign.",
    "Be concise. This is a startup-critical request; short valid JSON is better than rich prose.",
    "",
    "Hard constraints:",
    "- Keep the handcrafted first system anchored by Zenith, Aurelia, and Vanguard.",
    "- Do not reveal future frontier factions to the player up front.",
    "- Kaelen is the only fixed recurring NPC besides the player.",
    "- Kaelen cannot die and her full mystery must never be completely solved.",
    "- New systems should reveal new factions, conflicts, ores, upgrades, rumors, and ships through gate travel.",
    "- Use dry, slightly dark PG-13 humor. Avoid repeating example jokes or catchphrases.",
    "- Include exactly one rumor trail that can eventually lead to a hidden discovery or endgame easter egg.",
    "- The rumor trail needs exactly two concrete clue templates and a discovery type.",
    "- Include exactly one story horizon regeneration trigger with a metric, threshold, and action.",
    "- If story extends later, append a new horizon. Do not retcon known player choices.",
    "- Keep every string under 140 characters unless the field says otherwise.",
    "",
    "Campaign seed: test-seed-001",
    "",
    "Existing idea memory:",
    "No prior idea memory yet.",
    "",
    "Return only JSON. No markdown. No comments.",
    "Return exactly this object shape:",
    "{",
    "  \"campaign_title\": string,",
    "  \"campaign_logline\": string under 220 chars,",
    "  \"opening_situation\": string under 260 chars,",
    "  \"main_mystery\": string under 220 chars,",
    "  \"act_1_outline\": [three strings under 180 chars each],",
    "  \"long_term_reveal\": string under 220 chars,",
    "  \"tone\": string,",
    "  \"core_pressure\": string,",
    "  \"kaelen_rule\": string,",
    "  \"faction_reveal_rule\": string,",
    "  \"humor_rule\": string,",
    "  \"address_rule\": string,",
    "  \"fallback_rule\": string,",
    "  \"story_horizon_rule\": string,",
    "  \"story_arcs\": [{\"name\": string, \"summary\": string under 180 chars}],",
    "  \"rumor_trails\": [{\"name\": string, \"trail_id\": \"rumor_trail.\" plus snake_case_id, \"clue_count\": 2, \"hint_theme\": string, \"clue_templates\": [two strings], \"discovery_type\": \"hidden_discovery|secret_route|rare_upgrade|faction_secret|endgame_easter_egg\", \"rarity\": \"local|uncommon|rare|legendary\", \"payoff\": string under 180 chars}],",
    "  \"regeneration_triggers\": [{\"id\": snake_case_string, \"metric\": \"prepared_systems_remaining|active_story_arcs_remaining|rumor_trails_remaining|major_arc_state\", \"threshold\": number, \"action\": \"append_story_horizon|append_rumor_trail|append_story_arc\", \"description\": string}],",
    "  \"expansion_rules\": [two strings],",
    "  \"banned_repeats\": [string]",
    "}",
    "Use exactly one story_arcs item, one rumor_trails item, and one regeneration_triggers item.",
])

REQUIRED_KEYS = [
    "campaign_title", "campaign_logline", "opening_situation", "main_mystery",
    "act_1_outline", "long_term_reveal", "tone", "core_pressure", "kaelen_rule",
    "faction_reveal_rule", "humor_rule", "address_rule", "fallback_rule",
    "story_horizon_rule", "story_arcs", "rumor_trails", "regeneration_triggers",
    "expansion_rules", "banned_repeats",
]


def call_ollama(prompt, num_predict, temperature, seed):
    body = {
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "options": {
            "temperature": temperature,
            "num_predict": num_predict,
            "seed": seed,
        },
    }
    req = urllib.request.Request(
        OLLAMA_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    start = time.time()
    with urllib.request.urlopen(req, timeout=300) as resp:
        result = json.loads(resp.read().decode("utf-8"))
    elapsed = time.time() - start
    return result, elapsed


def evaluate(raw_text):
    info = {"parses": False, "missing_keys": [], "truncated_guess": False, "error": None}
    text = raw_text.strip()
    if not text.endswith("}"):
        info["truncated_guess"] = True
    try:
        data = json.loads(text)
        info["parses"] = True
        info["missing_keys"] = [k for k in REQUIRED_KEYS if k not in data]
        info["char_len"] = len(text)
    except Exception as e:
        info["error"] = str(e)
        info["char_len"] = len(text)
    return info


def run_variant(label, num_predict, temperature, count, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    results = []
    for i in range(1, count + 1):
        seed = int(time.time()) + i
        print(f"[{label}] candidate {i}/{count} (num_predict={num_predict}) ...")
        result, elapsed = call_ollama(PROMPT, num_predict, temperature, seed)
        raw = result.get("response", "")
        eval_info = evaluate(raw)
        eval_info["elapsed"] = round(elapsed, 2)
        eval_info["done_reason"] = result.get("done_reason", "")
        eval_info["eval_count"] = result.get("eval_count", None)
        results.append(eval_info)
        fname = os.path.join(out_dir, f"{label}_{i:02d}.json")
        with open(fname, "w", encoding="utf-8") as f:
            f.write(raw)
        print(f"  -> parses={eval_info['parses']} missing={eval_info['missing_keys']} "
              f"done_reason={eval_info['done_reason']} eval_count={eval_info['eval_count']} "
              f"chars={eval_info.get('char_len')} elapsed={eval_info['elapsed']}s")
    return results


if __name__ == "__main__":
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = os.path.join(
        r"C:\CodingProjects\SpaceGame\OllamaTestStories", f"{stamp}_claude_production_prompt_check"
    )
    print("=== Testing PRODUCTION settings: num_predict=900, temperature=0.55 ===")
    prod_results = run_variant("prod_900", 900, 0.55, 3, out_dir)

    print("\n=== Testing HIGHER num_predict=2800, same temperature ===")
    high_results = run_variant("high_2800", 2800, 0.55, 3, out_dir)

    summary = {"prod_900": prod_results, "high_2800": high_results}
    with open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)
    print(f"\nSaved results to {out_dir}")
