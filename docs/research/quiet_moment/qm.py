"""Quiet-moment prompt research harness.

Mirrors LocalModelGateway.generation_body(): /api/generate, stream false,
format json, think false, num_ctx 8192, keep_alive 30m. Serial requests only.
"""
import json, random, re, time, urllib.request

URL = "http://localhost:11434/api/generate"
BANK = json.load(open(r"C:\CodingProjects\SpaceGame\data\content\fixed_cast_voice_examples.json", encoding="utf-8"))
QUIET = [e for e in BANK["examples"] if e["situation"] == "quiet_moment"]
KAELEN_REFS = [e["line"] for e in QUIET if e["character_id"] == "kaelen"]
NOVA_REFS = [e["line"] for e in QUIET if e["character_id"] == "nova"]


def gen(prompt, model="qwen3:4b", fmt="json", temperature=0.7, num_predict=70,
        seed=None, top_p=None, top_k=None, min_p=None, think=False, extra=None):
    opts = {"temperature": temperature, "num_predict": num_predict,
            "seed": seed if seed is not None else random.randint(1, 2**31),
            "num_ctx": 8192}
    if top_p is not None: opts["top_p"] = top_p
    if top_k is not None: opts["top_k"] = top_k
    if min_p is not None: opts["min_p"] = min_p
    if extra: opts.update(extra)
    body = {"model": model, "prompt": prompt, "stream": False, "options": opts,
            "keep_alive": "30m", "think": think}
    if fmt:
        body["format"] = fmt
    t0 = time.time()
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r:
        out = json.load(r)
    return out.get("response", ""), time.time() - t0


def parse_json_field(raw, field="line"):
    try:
        d = json.loads(raw)
    except Exception:
        return None
    if not isinstance(d, dict):
        return None
    v = d.get(field)
    return v.strip() if isinstance(v, str) else None


# ---------------------------------------------------------------- validation
WORD = re.compile(r"[a-z0-9%']+")


def words(s):
    return WORD.findall(s.lower())


def has_any(line, terms):
    """Word-boundary containment (fixes the substring bugs in the .gd validator)."""
    w = set(words(line))
    txt = " " + " ".join(words(line)) + " "
    for t in terms:
        t = t.lower().strip()
        if " " in t:
            if (" " + t + " ") in txt:
                return t
        elif t in w:
            return t
    return None


def shares_run(a, b, n=5):
    aw, bw = words(a), words(b)
    if len(aw) < n or len(bw) < n:
        return False
    bs = " ".join(bw)
    return any(" ".join(aw[i:i + n]) in bs for i in range(len(aw) - n + 1))


def copied(line, refs, n=5):
    la = " ".join(words(line))
    for r in refs:
        if la == " ".join(words(r)) or shares_run(line, r, n):
            return r
    return None
