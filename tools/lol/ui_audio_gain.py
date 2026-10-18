"""Measure every UI sound under assets/audio/ui (recursive) and write data/audio/ui_gain.json.

League's client UI sounds ship at wildly different raw levels (button hovers peak around -53 dBFS, stingers
around -2 dBFS) because the client mixes them per category. Sfx (src/autoload/sfx.gd) reads this table and
plays each sound at  target_peak_db - measured_peak_db  so every UI cue lands at a deliberate loudness.

Output: {"res://assets/audio/ui/<file>": {"peak": dBFS, "rms": dBFS, "len": seconds}, ...}
Usage: python tools/lol/ui_audio_gain.py
"""
import glob
import json
import os
import subprocess
import tempfile
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
VGM = os.path.join(ROOT, "tools", "vgmstream", "vgmstream-cli.exe")
SRC = os.path.join(ROOT, "assets", "audio", "ui")
OUT = os.path.join(ROOT, "data", "audio", "ui_gain.json")


def measure(path):
    if path.lower().endswith(".wav"):
        src = path
        tmp = None
    else:
        tmp = os.path.join(tempfile.gettempdir(), "ui_gain_tmp.wav")
        r = subprocess.run([VGM, "-i", "-o", tmp, path], capture_output=True)
        if r.returncode != 0:
            return None
        src = tmp
    try:
        with wave.open(src) as w:
            n, ch, sr, sw = w.getnframes(), w.getnchannels(), w.getframerate(), w.getsampwidth()
            raw = w.readframes(n)
    finally:
        if tmp and os.path.exists(tmp):
            os.remove(tmp)
    if sw != 2 or n == 0:
        return None
    d = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    pk = float(np.abs(d).max())
    rms = float(np.sqrt((d * d).mean()))
    db = lambda v: round(20 * np.log10(max(v, 1e-9)), 1)
    return {"peak": db(pk), "rms": db(rms), "len": round(n / sr, 3)}


def main():
    table = {}
    files = sorted(glob.glob(os.path.join(SRC, "**", "*.ogg"), recursive=True)
                   + glob.glob(os.path.join(SRC, "**", "*.wav"), recursive=True))
    for f in files:
        m = measure(f)
        if m is None:
            print("FAIL", f)
            continue
        rel = os.path.relpath(f, ROOT).replace("\\", "/")
        table["res://" + rel] = m
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="\n") as fh:
        json.dump(table, fh, indent=1, sort_keys=True)
        fh.write("\n")
    print(len(table), "sounds ->", OUT)


if __name__ == "__main__":
    main()
