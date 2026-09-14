import json
import time
import urllib.request
import os
import datetime

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "gemma4:12b"

from claude_test_production_prompt import PROMPT, REQUIRED_KEYS, evaluate


def call_ollama(prompt, num_predict, temperature, seed, think):
    body = {
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "think": think,
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


def run_variant(label, think, count, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    results = []
    for i in range(1, count + 1):
        seed = int(time.time()) + i * 7
        print(f"[{label}] candidate {i}/{count} (think={think}) ...")
        result, elapsed = call_ollama(PROMPT, 900, 0.55, seed, think)
        raw = result.get("response", "")
        thinking = result.get("thinking", "")
        eval_info = evaluate(raw)
        eval_info["elapsed"] = round(elapsed, 2)
        eval_info["done_reason"] = result.get("done_reason", "")
        eval_info["eval_count"] = result.get("eval_count", None)
        eval_info["had_thinking_field"] = bool(thinking)
        results.append(eval_info)
        fname = os.path.join(out_dir, f"{label}_{i:02d}.json")
        with open(fname, "w", encoding="utf-8") as f:
            f.write(raw)
        if thinking:
            with open(os.path.join(out_dir, f"{label}_{i:02d}_thinking.txt"), "w", encoding="utf-8") as f:
                f.write(thinking)
        print(f"  -> parses={eval_info['parses']} missing={eval_info['missing_keys']} "
              f"done_reason={eval_info['done_reason']} eval_count={eval_info['eval_count']} "
              f"had_thinking_field={eval_info['had_thinking_field']} elapsed={eval_info['elapsed']}s")
    return results


if __name__ == "__main__":
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = os.path.join(
        r"C:\CodingProjects\SpaceGame\OllamaTestStories", f"{stamp}_claude_think_param_check"
    )
    print("=== Testing think=False (suppress reasoning leakage) ===")
    think_false = run_variant("think_false", False, 4, out_dir)

    summary = {"think_false": think_false}
    with open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)
    print(f"\nSaved results to {out_dir}")
