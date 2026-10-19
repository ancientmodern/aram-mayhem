"""[ui-feel] League's in-game HUD sound MIX: per-event gain, pitch and low-pass read from the Wwise banks.

extract_game_audio.py / extract_shop_audio.py only collect *which* WAVs an event plays. Wwise additionally stores, on
every sound object and on its parent actor-mixers / containers, a Volume (prop 0), a MakeUpGain (prop 6), a Pitch in
cents (prop 2) and a Low-pass (prop 3). The HUD sources are all mastered near 0 dBFS and the designers pull them
down per event (the skill level-up click is -16 dB, the shop open -6 dB, the item/ability "use" tick -18 dB, the
champion level-up 0 dB ...), so playing every file at its authored level (or at an eyeballed offset) gets the
relative loudness of the HUD wrong. This script resolves each HUD event through the HIRC graph, sums the
Volume + MakeUpGain along the parent chain of every sound and writes the result next to the file list.

Pitch / low-pass events (the "ability not ready" / silence error buzz is the AttackFail source at +840 cents) are
baked into a new WAV (assets/audio/ui/hud/<event>.wav) because the runtime pools cannot filter per voice.

Output  data/audio/hud_sfx.json
  {"events": {Event: {"v": [{"f": res://wav, "g": gain_db, "p": file_peak_db, "len": seconds}], "src": "hud|misc"}}}
Usage   python tools/lol/extract_hud_audio.py
"""
import json
import math
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import extract_game_audio as X  # noqa: E402
from wad import Wad  # noqa: E402

ROOT = X.ROOT
OUT_BAKED = os.path.join(ROOT, "assets", "audio", "ui", "hud")
OUT_JSON = os.path.join(ROOT, "data", "audio", "hud_sfx.json")
UNITS = {"HUD_Global": "hud", "MISC_Gameplay_SFX": "misc"}
MISC_EVENTS = ("Play_sfx_levelup_levelup", "Play_sfx_GoldAquisition_P_cast", "Play_sfx_Death_Self",
               "Play_sfx_Respawn_respawn", "Play_sfx_hud_base_store_item_with_debt")
WANT = ("Play_sfx_hud_base_camera_lock", "Play_sfx_hud_base_camera_unlock")
P_VOLUME, P_PITCH, P_LPF, P_MAKEUP = 0, 2, 3, 6


def find_parent(hirc, p, start):
    me = struct.unpack_from("<I", p, 0)[0]
    for i in range(start, min(len(p) - 4, start + 40)):
        v = struct.unpack_from("<I", p, i)[0]
        if v in hirc and v != me:
            return v, i
    return None, None


def node_params(hirc, oid):
    """-> (parent id, {prop id: float}) of a sound / actor-mixer / container (Wwise bank v145 NodeBaseParams)."""
    t, p, _v = hirc[oid]
    par, pos = find_parent(hirc, p, 21 if t == 2 else 7)
    if par is None:
        return None, {}
    i = pos + 4 + 1          # skip the priority bit-vector byte
    c = p[i]
    i += 1
    if c > 24 or i + 5 * c > len(p):
        return par, {}
    ids = list(p[i:i + c])
    i += c
    vals = [struct.unpack_from("<f", p, i + 4 * k)[0] for k in range(c)]
    return par, dict(zip(ids, vals))


def chain(hirc, oid):
    out, seen = [], set()
    while oid is not None and oid in hirc and oid not in seen:
        seen.add(oid)
        par, props = node_params(hirc, oid)
        out.append(props)
        oid = par
    return out


def leaves(g, oid, depth=0):
    """Sound objects below oid in the order Graph.resolve returns their WEMs."""
    if oid not in g.hirc or depth > 8:
        return []
    t = g.hirc[oid][0]
    if t == X.T_SOUND:
        return [oid]
    if t in X.CONTAINERS:
        out = []
        for c in g.children(oid):
            out += leaves(g, c, depth + 1)
        return out
    return []


def event_leaves(g, name):
    eid = X.fnv1_32(name)
    if eid not in g.hirc:
        return []
    out = []
    _t, p, v = g.hirc[eid]
    for a in g.event_actions(p, v):
        if a not in g.hirc or g.hirc[a][0] != X.T_ACTION:
            continue
        ap = g.hirc[a][1]
        atype, target = struct.unpack_from("<HI", ap, 4)
        if (atype >> 8) in (0x04, 0x05):
            out += leaves(g, target)
    uniq = []
    for s in out:
        src = struct.unpack_from("<I", g.hirc[s][1], 9)[0]
        if src in g.media and (s, src) not in uniq and src not in [u[1] for u in uniq]:
            uniq.append((s, src))
    return uniq


def wav_stats(path):
    x, sr = X.read_wav(path)
    m = x.mean(axis=1) if x.ndim == 2 else x
    peak = float(np.abs(m).max()) if len(m) else 0.0
    return (20 * math.log10(max(peak, 1e-6)), len(m) / sr, m, sr)


def bake(src_path, dst_path, pitch_cents, lpf):
    """Pitch (resampling, like Wwise: speed and pitch change together) + a gentle low-pass, 16-bit mono."""
    _pk, _ln, m, sr = wav_stats(src_path)
    m = m.astype(np.float64)
    if lpf > 0:
        fc = 20000.0 * (0.005 ** (lpf / 100.0))      # Wwise LPF 0..100 ~ 20 kHz .. 100 Hz (exponential)
        fc = min(fc, sr * 0.45)
        n = len(m)
        spec = np.fft.rfft(m)
        f = np.fft.rfftfreq(n, 1.0 / sr)
        spec *= 1.0 / np.sqrt(1.0 + (f / fc) ** 4)    # 2nd-order Butterworth magnitude
        m = np.fft.irfft(spec, n)
    if pitch_cents != 0:
        k = 2.0 ** (pitch_cents / 1200.0)
        if k > 1.0:                                   # keep content below the new Nyquist before shifting up
            n = len(m)
            spec = np.fft.rfft(m)
            f = np.fft.rfftfreq(n, 1.0 / sr)
            spec[f > sr * 0.5 / k * 0.95] = 0
            m = np.fft.irfft(spec, n)
        n_out = int(len(m) / k)
        m = np.interp(np.arange(n_out) * k, np.arange(len(m)), m)
    pk = float(np.abs(m).max())
    if pk > 0.999:
        m = m * (0.999 / pk)
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    X.write_wav(dst_path, (np.clip(m, -1, 1) * 32767).astype("<i2"), sr)


def res_of(abs_path):
    return "res://" + os.path.relpath(abs_path, ROOT).replace("\\", "/")


def abs_of(res):
    return os.path.join(ROOT, res.replace("res://", "").replace("/", os.sep))


def main():
    m12 = Wad(f"{X.GAME}/Maps/Shipping/Map12.wad.client")
    units = {}
    for u in X.bank_units(m12.read("data/maps/shipping/map12/map12.bin")):
        if u.name not in units or len(u.events) > len(units[u.name].events):
            units[u.name] = u
    wads = [Wad(f"{X.GAME}/Maps/Shipping/Common.wad.client"), m12]
    # event -> res:// WAVs in leaf order, from the two earlier extractions
    files = {}
    shared = json.load(open(os.path.join(ROOT, "data", "audio", "shared.json"), encoding="utf-8")).get("sfx", {})
    files.update(shared)
    shop = json.load(open(os.path.join(ROOT, "data", "audio", "shop.json"), encoding="utf-8")).get("events", {})
    for k, v in shop.items():
        files[k] = v
    events = {}
    skipped = []
    for uname, tag in UNITS.items():
        u = units[uname]
        g = X.load_graph(wads, sorted(set(u.paths), key=str.lower), log=print)
        for ev in u.events:
            low = ev.lower()
            if tag == "hud":
                if not low.startswith("play") or any(k in low for k in ("scn7", "spectator", "hol_",
                                                                      "emotes", "intromode", "srp_")):
                    continue
            elif ev not in MISC_EVENTS:
                continue
            lv = event_leaves(g, ev)
            flist = files.get(ev, [])
            if not lv:
                continue
            if not flist and ev in WANT:     # not extracted by the earlier passes: decode the WEMs here
                import tempfile
                scratch = tempfile.mkdtemp(prefix="lol_hudaudio_")
                flist = []
                for n, (_sid, src) in enumerate(lv):
                    out = os.path.join(OUT_BAKED, "%s_%d.wav" % (ev.lower(), n + 1))
                    if X.convert((g.media[src], os.path.join(scratch, "w%d" % n), out)) is not None:
                        flist.append(res_of(out))
                lv = lv[:len(flist)]
            if len(lv) != len(flist):
                skipped.append((ev, len(lv), len(flist)))
                continue
            voices = []
            for (sid, _src), f in zip(lv, flist):
                ch = chain(g.hirc, sid)
                gain = sum(p.get(P_VOLUME, 0.0) + p.get(P_MAKEUP, 0.0) for p in ch)
                pitch = sum(p.get(P_PITCH, 0.0) for p in ch)
                lpf = max(p.get(P_LPF, 0.0) for p in ch)
                path = f
                if abs(pitch) >= 1.0 or lpf >= 1.0:
                    path = "res://assets/audio/ui/hud/%s.wav" % low
                    if len(lv) > 1:
                        path = path.replace(".wav", "_%d.wav" % (len(voices) + 1))
                    bake(abs_of(f), abs_of(path), pitch, lpf)
                pk, ln, _m, _sr = wav_stats(abs_of(path))
                voices.append({"f": path, "g": round(gain, 1), "p": round(pk, 1), "len": round(ln, 2)})
            events[ev] = {"v": voices, "src": tag}
    out = {"_doc": "League HUD mix: g = Wwise Volume+MakeUpGain (dB) summed over the parent chain; p = peak of the file (dBFS)",
           "events": dict(sorted(events.items()))}
    with open(OUT_JSON, "w", encoding="utf-8", newline="\n") as fo:
        json.dump(out, fo, indent=1)
        fo.write("\n")
    print("events", len(events), "skipped", skipped)


if __name__ == "__main__":
    main()
