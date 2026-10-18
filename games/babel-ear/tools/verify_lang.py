#!/usr/bin/env python3
"""Dev-only QA for Babel Ear clips: spoken-language ID with Whisper.

We can't listen to 300 clips, so every cut clip (cache WAV, 16 kHz mono) goes
through faster-whisper's language detector. A clip is accepted when the
expected language is among Whisper's top-3 guesses with p >= 0.15 and no other
language beats it by a wide margin. Esperanto is not a Whisper language: those
clips are accepted unless Whisper is confident (p >= 0.6) they are English
(a leftover LibriVox intro/outro). Results go to tools/lang_check.json, which
`curate.py build` honours.

Needs a throwaway venv (never shipped):
    uv venv $TMPDIR/babel-work/wvenv && uv pip install --python ... faster-whisper
    $TMPDIR/babel-work/wvenv/bin/python tools/verify_lang.py [model]
"""

import json
import os
import pathlib
import sys

from faster_whisper import WhisperModel
import wave

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = pathlib.Path(os.environ.get("BABEL_CACHE") or
                     (pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "babel-cache"))
NOT_IN_WHISPER = {"eo"}


def main():
    model = WhisperModel(sys.argv[1] if len(sys.argv) > 1 else "small", device="cpu", compute_type="int8")
    out_path = ROOT / "tools" / "lang_check.json"
    results = json.loads(out_path.read_text()) if out_path.exists() else {}
    cands = json.loads((ROOT / "tools" / "candidates.json").read_text())
    for c in cands:
        cid, exp = c["id"], c["lang"]
        wav = CACHE / "clips" / f"{cid}.wav"
        if cid in results or not wav.exists():
            continue
        with wave.open(str(wav)) as w:  # cache WAVs are 16 kHz mono s16
            audio = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
        _, _, probs = model.detect_language(audio)
        top = sorted(probs, key=lambda x: -x[1])[:3]
        p_exp = dict(probs).get(exp, 0.0)
        if exp in NOT_IN_WHISPER:
            accept = not (top[0][0] == "en" and top[0][1] >= 0.6)
        else:
            accept = p_exp >= 0.15 and exp in [t[0] for t in top] and top[0][1] - p_exp < 0.6
        results[cid] = {"accept": accept, "expected": exp, "p_expected": round(p_exp, 3),
                        "top": [[t[0], round(t[1], 3)] for t in top]}
        print(f"{cid}: {'ok ' if accept else 'REJ'} p={p_exp:.2f} top={results[cid]['top']}", flush=True)
        out_path.write_text(json.dumps(results, indent=1, sort_keys=True))
    acc = sum(1 for r in results.values() if r["accept"])
    print(f"verify: {acc}/{len(results)} accepted")


if __name__ == "__main__":
    main()
