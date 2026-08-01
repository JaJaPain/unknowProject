"""Runtime selection layer.

Every diversity win in this project came from code, not from the prompt. This
is where that belongs at runtime: generate up to N candidates and reject on
properties code can actually measure, then serve the first survivor or stay
silent.

Gates, in order of cost:
  1. structural   -- parse, length, multiline, pronoun assumption
  2. self-repeat  -- opener bigram used recently, or a 5-word run shared with
                     a recently spoken line
  3. tic-repeat   -- the same closing formula twice in a short window

State that must persist in the save: recent openers, recent lines, recent
tics. Without persistence the freshness guarantee dies at the first reload.
"""
import collections, random, re
from qm import gen, parse_json_field, words
from runner import check

CLOSERS = [
    (re.compile(r"let'?s not do (this|that) again", re.I), "lets_not_again"),
    (re.compile(r"don'?t expect (it|that|this)", re.I), "dont_expect"),
    (re.compile(r"don'?t make (a habit|these a habit)", re.I), "no_habit"),
    (re.compile(r"let'?s find (something|work)", re.I), "lets_find"),
    (re.compile(r"\bno complaints\b", re.I), "no_complaints"),
    (re.compile(r"i'?d rather", re.I), "id_rather"),
]


def closer_tag(line):
    for rx, tag in CLOSERS:
        if rx.search(line):
            return tag
    return ""


def shares_run(a, b, n=5):
    aw, bw = words(a), words(b)
    if len(aw) < n or len(bw) < n:
        return False
    bs = " ".join(bw)
    return any(" ".join(aw[i:i + n]) in bs for i in range(len(aw) - n + 1))


class QuietMomentSelector:
    def __init__(self, opener_window=8, line_window=25, tic_window=6):
        self.recent_openers = collections.deque(maxlen=opener_window)
        self.recent_lines = collections.deque(maxlen=line_window)
        self.recent_tics = collections.deque(maxlen=tic_window)

    def reasons(self, line):
        """Why this candidate is unusable. Empty list means serve it."""
        r = check(line, cap=25)
        if r:
            return r
        op = " ".join(words(line)[:2])
        if op in self.recent_openers:
            r.append("opener_repeat")
        for prev in self.recent_lines:
            if shares_run(line, prev):
                r.append("phrase_repeat")
                break
        t = closer_tag(line)
        if t and t in self.recent_tics:
            r.append("closer_repeat")
        return r

    def accept(self, line):
        self.recent_openers.append(" ".join(words(line)[:2]))
        self.recent_lines.append(line)
        t = closer_tag(line)
        if t:
            self.recent_tics.append(t)

    def request(self, mod, packet, rng, model="qwen3:14b", max_calls=4):
        """Returns (line|None, calls, rejected[]) -- None means stay silent."""
        rejected = []
        for attempt in range(max_calls):
            raw, _dt = gen(mod.prompt(packet, rng), model=model,
                           num_predict=200, temperature=0.95, top_p=0.95)
            line = (parse_json_field(raw) or "").strip().strip('“”"')
            why = self.reasons(line)
            if not why:
                self.accept(line)
                return line, attempt + 1, rejected
            rejected.append((line, why))
        return None, max_calls, rejected
