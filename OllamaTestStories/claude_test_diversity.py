import json
import time
import urllib.request
import os
import datetime

from claude_test_production_prompt import PROMPT, evaluate

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "gemma4:12b"

DIVERSITY_PROMPT = PROMPT.replace(
    "Campaign seed: test-seed-001",
    "Campaign seed: test-seed-001\n\n"
    "Avoid motifs already overused in prior test runs: ancient/dead civilization archives, "
    "sentient AI failsafes hiding inside Kaelen, purge protocols, 'Great Silence' or 'Great Collapse' "
    "naming, and any title starting with 'The Zenith'. Choose a genuinely different creative lane: "
    "e.g. criminal economy, corporate espionage, ecological/environmental crisis, political succession, "
    "cult/religious movement, or engineering sabotage. Kaelen's secret must be mundane (a personal or "
    "criminal secret), not a sci-fi twist about her true nature."
)


def call_ollama(prompt, temperature, seed):
    body = {
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "think": False,
        "options": {"temperature": temperature, "num_predict": 900, "seed": seed},
    }
    req = urllib.request.Request(
        OLLAMA_URL, data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    start = time.time()
    with urllib.request.urlopen(req, timeout=300) as resp:
        result = json.loads(resp.read().decode("utf-8"))
    return result, time.time() - start


def run(label, prompt, temperature, count, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for i in range(1, count + 1):
        seed = int(time.time()) + i * 13
        result, elapsed = call_ollama(prompt, temperature, seed)
        raw = result.get("response", "")
        info = evaluate(raw)
        fname = os.path.join(out_dir, f"{label}_{i:02d}.json")
        with open(fname, "w", encoding="utf-8") as f:
            f.write(raw)
        print(f"[{label}] {i}: parses={info['parses']} missing={info['missing_keys']} elapsed={elapsed:.1f}s")


if __name__ == "__main__":
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = os.path.join(r"C:\CodingProjects\SpaceGame\OllamaTestStories", f"{stamp}_claude_diversity_check")
    print("=== same prompt, temp=0.95, think=False, no anti-motif guidance ===")
    run("hot_no_guidance", PROMPT, 0.95, 3, out_dir)
    print("=== same prompt + explicit avoid-motifs guidance, temp=0.95, think=False ===")
    run("hot_with_guidance", DIVERSITY_PROMPT, 0.95, 3, out_dir)
    print(f"\nSaved to {out_dir}")
