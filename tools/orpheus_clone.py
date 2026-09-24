"""Clone a voice with Orpheus (Canopy Labs) from a reference clip and render lines.

Runs in its own environment (D:/CodingProjects/orpheus-env), not the system
Python:

  D:/CodingProjects/orpheus-env/Scripts/python.exe tools/orpheus_clone.py \
      --ref tools/voice_refs/nova_baked.wav --ref-text-file tools/voice_refs/nova_baked.txt \
      --jobs jobs.json

jobs.json: a list of {"text", "out", "seed"?}.

The prompt recipe is the one the first Orpheus trial found to work (see
docs/todo.md, "CLONING WORKS"): the reference as one finished turn (its text,
then its audio codes), then a new turn with the line that ENDS on the
start-of-AI token, so the model continues in audio. Closing that turn normally
gave 0.17 s fragments.

Model: audo/orpheus-3b-0.1-ft (Apache-2.0 mirror of the gated
canopylabs/orpheus-3b-0.1-ft). Audio codec: SNAC 24 kHz.
"""
import argparse
import io
import json
import sys

import numpy
import soundfile as sf

MODEL = "audo/orpheus-3b-0.1-ft"
SNAC_MODEL = "hubertsiuzdak/snac_24khz"
RATE = 24000

START_OF_HUMAN = 128259
END_OF_HUMAN = 128260
START_OF_AI = 128261
END_OF_AI = 128262
START_OF_SPEECH = 128257
END_OF_SPEECH = 128258
END_OF_TEXT = 128009
AUDIO_BASE = 128266
CODEBOOK = 4096

# The tail fix that worked for the cast bake (TestTTS/fix_tails.py): only a
# clip that ends abruptly gets a short fade and some silence.
ABRUPT_TAIL_SECONDS = 0.08
FADE_SECONDS = 0.018
ADDED_SILENCE_SECONDS = 0.14
SILENCE = 0.004


def encode_reference(snac, torch, path):
    data, rate = sf.read(path, dtype="float32")
    if data.ndim > 1:
        data = data.mean(axis=1)
    if rate != RATE:
        raise SystemExit("reference must be %d Hz (got %d)" % (RATE, rate))
    wav = torch.from_numpy(data).unsqueeze(0).unsqueeze(0).to(snac.device if hasattr(snac, "device") else "cuda")
    with torch.inference_mode():
        codes = snac.encode(wav)
    c0, c1, c2 = [c[0].tolist() for c in codes]
    tokens = []
    for i in range(len(c0)):
        tokens += [
            AUDIO_BASE + c0[i],
            AUDIO_BASE + CODEBOOK + c1[2 * i],
            AUDIO_BASE + 2 * CODEBOOK + c2[4 * i],
            AUDIO_BASE + 3 * CODEBOOK + c2[4 * i + 1],
            AUDIO_BASE + 4 * CODEBOOK + c1[2 * i + 1],
            AUDIO_BASE + 5 * CODEBOOK + c2[4 * i + 2],
            AUDIO_BASE + 6 * CODEBOOK + c2[4 * i + 3],
        ]
    return tokens


def decode_audio(snac, torch, tokens):
    codes = [t - AUDIO_BASE for t in tokens if t >= AUDIO_BASE]
    codes = codes[: len(codes) // 7 * 7]
    l0, l1, l2 = [], [], []
    for i in range(0, len(codes), 7):
        f = codes[i:i + 7]
        l0.append(f[0])
        l1 += [f[1] - CODEBOOK, f[4] - 4 * CODEBOOK]
        l2 += [f[2] - 2 * CODEBOOK, f[3] - 3 * CODEBOOK, f[5] - 5 * CODEBOOK, f[6] - 6 * CODEBOOK]
    for layer in (l0, l1, l2):
        if any(c < 0 or c >= CODEBOOK for c in layer):
            raise ValueError("model produced out-of-range audio codes")
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    layers = [torch.tensor(l, dtype=torch.int32, device=dev).unsqueeze(0) for l in (l0, l1, l2)]
    with torch.inference_mode():
        audio = snac.decode(layers)
    return audio.squeeze().float().cpu().numpy()


def tidy(data):
    """Trim leading silence; give an abrupt ending a fade and a little silence."""
    loud = numpy.nonzero(numpy.abs(data) > SILENCE)[0]
    if len(loud) == 0:
        return data
    data = data[max(0, loud[0] - int(0.02 * RATE)):].copy()
    trailing = (len(data) - 1 - numpy.nonzero(numpy.abs(data) > SILENCE)[0][-1]) / RATE
    if trailing < ABRUPT_TAIL_SECONDS:
        fade = int(FADE_SECONDS * RATE)
        data[-fade:] *= numpy.linspace(1.0, 0.0, fade, dtype="float32")
        data = numpy.concatenate([data, numpy.zeros(int(ADDED_SILENCE_SECONDS * RATE), dtype="float32")])
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True)
    ap.add_argument("--ref-text-file", required=True)
    ap.add_argument("--jobs", required=True)
    ap.add_argument("--temperature", type=float, default=0.6)
    ap.add_argument("--top-p", type=float, default=0.95)
    ap.add_argument("--repetition-penalty", type=float, default=1.1)
    args = ap.parse_args()

    import torch
    from snac import SNAC
    from transformers import AutoModelForCausalLM, AutoTokenizer

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    tokenizer = AutoTokenizer.from_pretrained(MODEL)
    model = AutoModelForCausalLM.from_pretrained(MODEL, torch_dtype=torch.bfloat16).to(dev)
    snac = SNAC.from_pretrained(SNAC_MODEL).eval().to(dev)

    ref_text = io.open(args.ref_text_file, encoding="utf-8").read().strip()
    ref_audio = encode_reference(snac, torch, args.ref)
    reference_turn = ([START_OF_HUMAN] + tokenizer(ref_text).input_ids + [END_OF_TEXT, END_OF_HUMAN]
                      + [START_OF_AI, START_OF_SPEECH] + ref_audio + [END_OF_SPEECH, END_OF_AI])

    for job in json.load(io.open(args.jobs, encoding="utf-8")):
        prompt = reference_turn + [START_OF_HUMAN] + tokenizer(job["text"]).input_ids + [END_OF_TEXT, END_OF_HUMAN, START_OF_AI]
        ids = torch.tensor([prompt], device=dev)
        torch.manual_seed(int(job.get("seed", 7)))
        with torch.inference_mode():
            out = model.generate(ids, attention_mask=torch.ones_like(ids), max_new_tokens=int(job.get("max_tokens", 1400)),
                                 do_sample=True, temperature=args.temperature, top_p=args.top_p,
                                 repetition_penalty=args.repetition_penalty, eos_token_id=END_OF_SPEECH)
        new = out[0][len(prompt):].tolist()
        if START_OF_SPEECH in new:
            new = new[new.index(START_OF_SPEECH) + 1:]
        if END_OF_SPEECH in new:
            new = new[:new.index(END_OF_SPEECH)]
        try:
            audio = tidy(decode_audio(snac, torch, new))
        except ValueError as err:
            print("FAILED", job["out"], err)
            continue
        sf.write(job["out"], audio, RATE)
        print("rendered", job["out"], "%.2fs" % (len(audio) / RATE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
