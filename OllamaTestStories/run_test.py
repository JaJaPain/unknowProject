import urllib.request
import urllib.error
import json
import time
import os

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "gemma4:12b"

PASS_1_PROMPT = """You are a narrative designer for a space game. Your task is to generate a Campaign Uniqueness Brief for a new procedural campaign.
The game is about a broke independent pilot. Kaelen is the mysterious broker/fixer. The local factions are Zenith, Aurelia, and Vanguard.
The first mission must be exactly one starter Reaver ship.

Generate a JSON object with the following shape. Do NOT include markdown, commentary, or extra keys. Just the JSON.

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
- Must begin with What, Why, How, Who, Where, or Which.
- Must leave room for different answers.
- Ask about pressure, cost, contradiction, leverage, secrecy, consequence, routes, prices, risk, or player choice.
- Do not imply a fixed motif or final answer.
"""

def generate(prompt):
    data = {
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "format": "json"
    }
    req = urllib.request.Request(OLLAMA_URL, data=json.dumps(data).encode('utf-8'), headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read().decode('utf-8'))
            return result.get('response', '')
    except Exception as e:
        print(f"Error: {e}")
        return None

if __name__ == "__main__":
    print("Running Pass 1...")
    start = time.time()
    pass1_res = generate(PASS_1_PROMPT)
    print(f"Pass 1 finished in {time.time()-start:.2f}s")
    
    if pass1_res:
        print("Pass 1 Output:")
        print(pass1_res)
        
        # Now run pass 2 based on pass 1
        PASS_2_PROMPT = f"""You are a narrative designer for a space game. Using the following Uniqueness Brief, generate the final Campaign Story Bible.
        
Uniqueness Brief:
{pass1_res}

Generate a JSON object exactly matching this shape. Do not include markdown, commentary, or extra keys. Just the JSON.
{{
  "campaign_title": "",
  "campaign_subtitle": "",
  "campaign_logline": "",
  "campaign_pitch": "",
  "campaign_story_summary": "",
  "tone": "",
  "opening": {{
    "status_quo": "",
    "visible_crisis": "",
    "hidden_crisis": "",
    "why_now": "",
    "player_role": ""
  }},
  "mystery": {{
    "question": "",
    "false_answer": "",
    "true_answer_hint": "",
    "long_term_reveal_direction": ""
  }},
  "kaelen": {{
    "public_role": "",
    "secret_angle": "",
    "address_rule": "",
    "never_reveal_rule": ""
  }},
  "factions": {{
    "zenith_problem": "",
    "aurelia_problem": "",
    "vanguard_problem": "",
    "conflict_triangle": "",
    "neutral_space_pressure": ""
  }},
  "act_1": {{
    "name": "",
    "goal": "",
    "opening_incident": "",
    "midpoint_turn": "",
    "finale": "",
    "player_takeaway": ""
  }},
  "starter_mission": {{
    "title": "",
    "reason": "",
    "enemy_identity": "",
    "enemy_knows": "",
    "after_effect": ""
  }},
  "recurring_clue": {{
    "name": "",
    "signal": "",
    "first_appearance": "",
    "escalation": "",
    "payoff_hint": ""
  }},
  "rumor_trail": {{
    "name": "",
    "trail_id": "rumor_trail.snake_case_id",
    "hint_theme": "",
    "clue_templates": ["", ""],
    "discovery_type": "hidden_discovery|secret_route|rare_upgrade|faction_secret|endgame_easter_egg",
    "rarity": "local|uncommon|rare|legendary",
    "payoff": ""
  }},
  "horizon": {{
    "gate_tease": "",
    "new_system_reveal_rule": "",
    "future_pressure_tease": "",
    "future_ore_or_upgrade_tease": "",
    "regeneration_trigger": {{
      "id": "snake_case_id",
      "metric": "prepared_systems_remaining|active_story_arcs_remaining|rumor_trails_remaining|major_arc_state",
      "threshold": 0,
      "action": "append_story_horizon|append_rumor_trail|append_story_arc",
      "description": ""
    }}
  }},
  "rules": {{
    "humor_rule": "",
    "fallback": "",
    "banned_repeats": []
  }},
  "story_questions_for_future_generation": ["", "", "", "", ""]
}}
"""
        print("Running Pass 2...")
        start2 = time.time()
        pass2_res = generate(PASS_2_PROMPT)
        print(f"Pass 2 finished in {time.time()-start2:.2f}s")
        if pass2_res:
            print("Pass 2 Output:")
            print(pass2_res)
            
            output_dir = r"C:\CodingProjects\SpaceGame\OllamaTestStories\gemma4_test_run"
            os.makedirs(output_dir, exist_ok=True)
            with open(os.path.join(output_dir, "pass1.json"), "w") as f:
                f.write(pass1_res)
            with open(os.path.join(output_dir, "pass2.json"), "w") as f:
                f.write(pass2_res)
            print(f"Saved to {output_dir}")
