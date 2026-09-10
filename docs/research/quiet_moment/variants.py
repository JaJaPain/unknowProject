"""Ablation variants. Each returns (prompt, picks)."""
from prompts import SOUL, REFS, BASE_TASK, ref_block, KAELEN_SOUL, NOVA_SOUL

# ---- soul with the public-board/fee sentence removed (Kaelen only) ---------
KAELEN_SOUL_NOBOARD = "\n".join(
    l for l in KAELEN_SOUL.splitlines() if not l.startswith("- Public-board money:")
)
SOUL_NOBOARD = {"kaelen": KAELEN_SOUL_NOBOARD, "nova": NOVA_SOUL}


# ---- V1: positive-only task (no ban list, no negation priming) -------------
POS_TASK = {
    "kaelen": """Kaelen says one optional line to the Captain in the pause after a job finished.
Two things are true, and they are the only things you know:
1. The job was safe.
2. The payout was modest.
Write her line in two short sentences.
Sentence one: say fact 2 in her own words, as a broker would put it.
Sentence two: her dry opinion about that. It introduces no new object, person, place, or event — only her attitude to what sentence one already said.
Voice: precise, dry, controlled, faintly amused; a broker's profit humour. She may call the Captain "Shiny". 28 words maximum.
Return ONLY this JSON object: {"line":"the spoken line"}.""",
    "nova": """N.O.V.A. says one optional line to her Captain in the pause after a fight ended.
Three things are true, and they are the only things you know:
1. The fight is over.
2. The hull is stable.
3. Sensors show no pursuit.
Write her line in two short sentences.
Sentence one: say fact 2 or fact 3 in her own words, as a ship's AI would put it.
Sentence two: her dry observation about that. It introduces no new system, reading, number, person, place, or event — only her attitude to what sentence one already said.
Voice: clear, compact, observant; humour lands as a systems remark. She calls the Captain "Captain". 28 words maximum.
Return ONLY this JSON object: {"line":"the spoken line"}.""",
}


def v1_positive(ch, rng):
    rb, picks = ref_block(ch, rng)
    return POS_TASK[ch] + "\n" + SOUL_NOBOARD[ch] + "\n" + rb, picks


def v1a_positive_oldsoul(ch, rng):
    rb, picks = ref_block(ch, rng)
    return POS_TASK[ch] + "\n" + SOUL[ch] + "\n" + rb, picks


def v1b_positive_norefs(ch, rng):
    return POS_TASK[ch] + "\n" + SOUL_NOBOARD[ch] + "\n", []


def v2_baseline_norefs(ch, rng):
    return BASE_TASK[ch] + "\n" + SOUL[ch] + "\n", []


def v3_baseline_noboard(ch, rng):
    rb, picks = ref_block(ch, rng)
    return BASE_TASK[ch] + "\n" + SOUL_NOBOARD[ch] + "\n" + rb, picks
