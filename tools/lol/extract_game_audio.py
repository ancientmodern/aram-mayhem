"""Extract in-game Wwise audio (champion SFX/VO, announcer, map, shared SFX) from the
local League of Legends install into playable WAVs + event maps for the Godot game.

Pipeline: skin/map .bin BankUnits (bank paths + event names) -> .bnk HIRC event graph
(event -> play actions -> containers -> sounds) -> WEM ids -> media from .wpk / bnk DIDX+DATA
-> vgmstream-cli -> numpy (mono, <=32 kHz, trimmed, 16-bit) -> WAV.

Outputs:
  assets/audio/game/champions/<alias>/<event_lower>_<n>.wav
  data/audio/<alias>.json  {"sfx": {Event: [res://...wav, ...]}, "vo": {...}}
  (stretch) assets/audio/game/{announcer,map,shared}/ + data/audio/{announcer,map12,shared}.json

Usage: python tools/lol/extract_game_audio.py [Champion ...] [--extras] [--no-champions]
"""
import argparse
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wad import Wad  # noqa: E402
from binfile import BinFile, BinObject, fnv1a  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
VGM = os.path.join(ROOT, "tools", "vgmstream", "vgmstream-cli.exe")
OUT_AUDIO = os.path.join(ROOT, "assets", "audio", "game")
OUT_DATA = os.path.join(ROOT, "data", "audio")

ROSTER = ["Ahri", "Garen", "Darius", "Yasuo", "MasterYi", "Malphite", "Leona", "Lux", "Jinx",
          "Ezreal", "MissFortune", "Annie", "Sona", "Veigar"]

TARGET_SR = 32000
SFX_CAP = 8
VO_CAP = 6
VO_KEYWORDS = ("attack", "move", "death", "laugh", "taunt", "joke", "encounter", "cast", "spell",
               "kill", "respawn")

H_BANKPATH = fnv1a("bankPath")
H_EVENTS = fnv1a("events")
H_NAME = fnv1a("name")
H_VOICE = fnv1a("voiceOver")


# ----------------------------------------------------------------------------- bins

class BankUnit:
    def __init__(self, name, paths, events, voice):
        self.name, self.paths, self.events, self.voice = name, paths, events, voice

    def __repr__(self):
        return f"<BankUnit {self.name} paths={len(self.paths)} events={len(self.events)}>"


def _walk(v):
    if isinstance(v, BinObject):
        yield v
        for x in v.fields.values():
            yield from _walk(x)
    elif isinstance(v, list):
        for x in v:
            yield from _walk(x)
    elif isinstance(v, dict):
        for x in v.values():
            yield from _walk(x)


def bank_units(bin_bytes):
    """All BankUnit-like objects (have bankPath + events) anywhere in a PROP bin."""
    out = []
    try:
        b = BinFile(bin_bytes)
    except Exception:
        return out
    for o in b.entries.values():
        for obj in _walk(o):
            paths = obj.fields.get(H_BANKPATH)
            if isinstance(paths, list) and paths and all(isinstance(p, str) for p in paths):
                ev = obj.fields.get(H_EVENTS) or []
                ev = [e for e in ev if isinstance(e, str)]
                out.append(BankUnit(obj.fields.get(H_NAME) or "?", paths, ev,
                                    bool(obj.fields.get(H_VOICE))))
    return out


# ----------------------------------------------------------------------------- wwise

def fnv1_32(s):
    h = 0x811C9DC5
    for c in s.lower().encode("utf-8"):
        h = ((h * 0x01000193) & 0xFFFFFFFF) ^ c
    return h


def parse_wpk(data, media):
    if data[:4] != b"r3d2":
        return
    _ver, n = struct.unpack_from("<II", data, 4)
    offs = struct.unpack_from(f"<{n}I", data, 12)
    for o in offs:
        if not o:
            continue
        do, ds, nl = struct.unpack_from("<III", data, o)
        name = data[o + 12:o + 12 + nl * 2].decode("utf-16-le", "replace")
        m = re.match(r"(\d+)", name)
        if m:
            media[int(m.group(1))] = data[do:do + ds]


def parse_bnk(data, media, hirc):
    """Fill media {wem_id: bytes} from DIDX/DATA and hirc {obj_id: (type, payload, version)}."""
    pos = 0
    version = 0
    didx = []
    data_pos = None
    while pos + 8 <= len(data):
        tag, sz = struct.unpack_from("<4sI", data, pos)
        body = pos + 8
        if tag == b"BKHD":
            version = struct.unpack_from("<I", data, body)[0]
        elif tag == b"DIDX":
            didx = [struct.unpack_from("<III", data, body + 12 * i) for i in range(sz // 12)]
        elif tag == b"DATA":
            data_pos = body
        elif tag == b"HIRC":
            n = struct.unpack_from("<I", data, body)[0]
            q = body + 4
            for _ in range(n):
                t, s = struct.unpack_from("<BI", data, q)
                payload = data[q + 5:q + 5 + s]
                if len(payload) >= 4:
                    oid = struct.unpack_from("<I", payload)[0]
                    hirc.setdefault(oid, (t, payload, version))
                q += 5 + s
        pos = body + sz
    if data_pos is not None:
        for wid, off, size in didx:
            # streamed/prefetch media from a .wpk (full file) wins over a DIDX prefetch stub
            media.setdefault(wid, data[data_pos + off:data_pos + off + size])


def _read_var(p, i):
    v = 0
    for _ in range(5):
        c = p[i]
        i += 1
        v = (v << 7) | (c & 0x7F)
        if not c & 0x80:
            break
    return v, i


T_SOUND, T_ACTION, T_EVENT, T_MTRACK = 2, 3, 4, 11
CONTAINERS = {5, 6, 7, 9, 10, 12, 13}


class Graph:
    def __init__(self, hirc, media):
        self.hirc = hirc
        self.media = media
        self._kids = {}

    def event_actions(self, payload, version):
        n_body = len(payload) - 4
        cands = []
        if version > 122:
            n, i = _read_var(payload, 4)
            cands.append((n, i))
        cands.append((payload[4], 5))
        if len(payload) >= 8:
            cands.append((struct.unpack_from("<I", payload, 4)[0], 8))
        for n, i in cands:
            if i + 4 * n == len(payload) or (i + 4 * n <= len(payload) and n_body < 64 and n):
                return list(struct.unpack_from(f"<{n}I", payload, i))
        return []

    def children(self, cid):
        if cid in self._kids:
            return self._kids[cid]
        t, p, _v = self.hirc[cid]
        tag = struct.pack("<I", cid)
        best = None
        for i in range(4, len(p) - 7):
            n = struct.unpack_from("<I", p, i)[0]
            if n < 1 or n > 512 or i + 4 + 4 * n > len(p):
                continue
            ids = struct.unpack_from(f"<{n}I", p, i + 4)
            if all(k in self.hirc and k != cid and tag in self.hirc[k][1][4:] for k in ids):
                best = list(ids)
        if best is None:  # empty container (or unparseable): no children
            best = []
        self._kids[cid] = best
        return best

    def resolve(self, oid, seen=None):
        """-> ordered unique WEM ids reachable from a HIRC object through Play actions."""
        seen = set() if seen is None else seen
        if oid in seen or oid not in self.hirc:
            return []
        seen.add(oid)
        t, p, v = self.hirc[oid]
        out = []
        if t == T_EVENT:
            for a in self.event_actions(p, v):
                out += self.resolve(a, seen)
        elif t == T_ACTION:
            atype, target = struct.unpack_from("<HI", p, 4)
            if (atype >> 8) in (0x04, 0x05):  # Play / PlayAndContinue
                out += self.resolve(target, seen)
        elif t == T_SOUND:
            if len(p) >= 13:
                src = struct.unpack_from("<I", p, 9)[0]
                if src in self.media:
                    out.append(src)
        elif t == T_MTRACK:
            # u8 flags, u32 numSources, {u32 plugin, u8 stream, u32 srcId, u32 memSize, u8 bits}
            try:
                n = struct.unpack_from("<I", p, 5)[0]
                for k in range(min(n, 64)):
                    src = struct.unpack_from("<I", p, 9 + 14 * k + 5)[0]
                    if src in self.media:
                        out.append(src)
            except struct.error:
                pass
        elif t in CONTAINERS:
            for c in self.children(oid):
                out += self.resolve(c, seen)
        res = []
        for x in out:
            if x not in res:
                res.append(x)
        return res

    def event_wems(self, name):
        return self.resolve(fnv1_32(name))


def load_graph(wads, paths, log=None):
    media, hirc = {}, {}
    missing = []
    # wpks first so their full streamed media wins over bnk prefetch stubs
    for p in sorted(paths, key=lambda s: not s.lower().endswith(".wpk")):
        d = None
        for w in wads:
            d = w.read(p.lower())
            if d is not None:
                break
        if d is None:
            missing.append(p)
            continue
        if d[:4] == b"r3d2":
            parse_wpk(d, media)
        elif d[:4] == b"BKHD":
            parse_bnk(d, media, hirc)
    if missing and log:
        log(f"    missing banks: {missing}")
    return Graph(hirc, media)


# ----------------------------------------------------------------------------- audio

def read_wav(path):
    with open(path, "rb") as f:
        d = f.read()
    if d[:4] != b"RIFF":
        return None, 0
    pos = 12
    fmt = None
    pcm = None
    while pos + 8 <= len(d):
        tag, sz = struct.unpack_from("<4sI", d, pos)
        if tag == b"fmt ":
            fmt = struct.unpack_from("<HHIIHH", d, pos + 8)
        elif tag == b"data":
            pcm = d[pos + 8:pos + 8 + sz]
        pos += 8 + sz + (sz & 1)
    if fmt is None or pcm is None:
        return None, 0
    ftag, ch, sr, _br, _ba, bits = fmt
    if bits == 16:
        x = np.frombuffer(pcm[:len(pcm) // 2 * 2], dtype="<i2").astype(np.float32) / 32768.0
    elif bits == 32 and ftag in (3, 0xFFFE):
        x = np.frombuffer(pcm[:len(pcm) // 4 * 4], dtype="<f4").astype(np.float32)
    elif bits == 24:
        b = np.frombuffer(pcm[:len(pcm) // 3 * 3], dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        x = ((b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)) << 8 >> 8).astype(np.float32) / 8388608.0
    else:
        return None, 0
    ch = max(ch, 1)
    x = x[:len(x) // ch * ch].reshape(-1, ch)
    return x, sr


_wtables = {}


def resample(x, sr_in, sr_out):
    """Windowed-sinc (Kaiser) polyphase resampler for downsampling; x: 1-D float32."""
    if sr_in <= sr_out or len(x) == 0:
        return x, sr_in
    g = math.gcd(sr_in, sr_out)
    L, M = sr_out // g, sr_in // g  # output step = M/L input samples
    cutoff = 0.5 * (sr_out / sr_in) * 0.95  # cycles per input sample
    zeros = 16
    half = int(math.ceil(zeros / (2 * cutoff)))
    k = np.arange(-half + 1, half + 1)
    key = (L, M)
    if key not in _wtables:
        if L > 4096:  # odd ratio: fall back to an approximate table
            raise ValueError("unsupported ratio")
        frac = np.arange(L) / L
        d = frac[:, None] - k[None, :]
        beta = 8.6
        win = np.i0(beta * np.sqrt(np.clip(1 - (d / half) ** 2, 0, 1))) / np.i0(beta)
        w = 2 * cutoff * np.sinc(2 * cutoff * d) * win
        w /= w.sum(axis=1, keepdims=True)
        _wtables[key] = w.astype(np.float32)
    W = _wtables[key]
    n_out = int(len(x) * L // M)
    xp = np.concatenate([np.zeros(half, np.float32), x.astype(np.float32), np.zeros(half + 1, np.float32)])
    y = np.empty(n_out, np.float32)
    step = 32768
    for s in range(0, n_out, step):
        n = np.arange(s, min(s + step, n_out), dtype=np.int64)
        base = (n * M) // L
        ph = (n * M) % L
        idx = base[:, None] + k[None, :] + half
        y[s:s + len(n)] = np.einsum("ij,ij->i", xp[idx], W[ph])
    return y, sr_out


def process_audio(x, sr):
    """-> (int16 mono, sr) or None if silent."""
    m = x.mean(axis=1) if x.ndim == 2 else x
    m = m.astype(np.float32)
    try:
        m, sr = resample(m, sr, TARGET_SR)
    except ValueError:
        pass
    a = np.abs(m)
    peak = float(a.max()) if len(a) else 0.0
    if peak < 3e-4:
        return None
    thr = max(peak * 0.004, 5e-4)
    above = np.nonzero(a > thr)[0]
    start = max(int(above[0]) - int(0.01 * sr), 0)
    end = min(int(above[-1]) + int(0.06 * sr), len(m))
    trimmed_start, trimmed_end = start > 0, end < len(m)
    m = m[start:end].copy()
    if trimmed_start:
        n = min(int(0.003 * sr), len(m))
        m[:n] *= np.linspace(0, 1, n, dtype=np.float32)
    if trimmed_end:
        n = min(int(0.015 * sr), len(m))
        m[len(m) - n:] *= np.linspace(1, 0, n, dtype=np.float32)
    return (np.clip(m, -1, 1) * 32767).astype("<i2"), sr


def write_wav(path, pcm, sr):
    data = pcm.tobytes()
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16))
        f.write(b"data" + struct.pack("<I", len(data)) + data)


def convert(job):
    """job = (wem_bytes, scratch_base, out_path) -> seconds or None."""
    wem, base, out = job
    src, tmp = base + ".wem", base + ".wav"
    try:
        with open(src, "wb") as f:
            f.write(wem)
        r = subprocess.run([VGM, "-i", "-o", tmp, src], stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, timeout=120)
        if r.returncode != 0 or not os.path.exists(tmp):
            return None
        x, sr = read_wav(tmp)
        if x is None or len(x) == 0:
            return None
        res = process_audio(x, sr)
        if res is None:
            return None
        pcm, sr = res
        os.makedirs(os.path.dirname(out), exist_ok=True)
        write_wav(out, pcm, sr)
        return len(pcm) / sr
    except Exception as ex:  # noqa: BLE001
        print("    convert error", out, ex)
        return None
    finally:
        for p in (src, tmp):
            try:
                os.remove(p)
            except OSError:
                pass


# ----------------------------------------------------------------------------- driver

def res_path(abs_path):
    return "res://" + os.path.relpath(abs_path, ROOT).replace("\\", "/")


class Extractor:
    def __init__(self, scratch, workers=16):
        self.scratch = scratch
        self.pool = ThreadPoolExecutor(workers)
        self.n = 0

    def run_groups(self, groups, out_dir):
        """groups: {section: [(event_name, Graph, cap), ...]} -> ({section: {event: [res...]}}, stats).
        Each WEM is converted once; events sharing a WEM reference the first file."""
        wem_file = {}   # wem id -> abs path
        jobs = []
        plan = {}
        for section, items in groups.items():
            plan[section] = []
            for ev, graph, cap in items:
                wems = graph.event_wems(ev)[:cap]
                if not wems:
                    continue
                files = []
                for i, wid in enumerate(wems):
                    if wid not in wem_file:
                        path = os.path.join(out_dir, f"{ev.lower()}_{i + 1}.wav")
                        wem_file[wid] = path
                        self.n += 1
                        jobs.append((graph.media[wid], os.path.join(self.scratch, f"w{self.n}"), path))
                    files.append(wem_file[wid])
                plan[section].append((ev, files))
        ok = {}
        for job, dur in zip(jobs, self.pool.map(convert, jobs)):
            ok[job[2]] = dur is not None
        result = {}
        n_ev = 0
        for section, items in plan.items():
            result[section] = {}
            for ev, files in items:
                good = [res_path(f) for f in files if ok.get(f)]
                if good:
                    result[section][ev] = good
                    n_ev += 1
        n_files = sum(1 for v in ok.values() if v)
        return result, {"events": n_ev, "files": n_files, "failed": sum(1 for v in ok.values() if not v)}


def dir_size(path):
    t = 0
    for dp, _dn, fn in os.walk(path):
        for f in fn:
            t += os.path.getsize(os.path.join(dp, f))
    return t


def is_vo_keep(ev):
    e = ev.lower()
    return any(k in e for k in VO_KEYWORDS)


def clear_wavs(d):
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.endswith(".wav"):
                os.remove(os.path.join(d, f))


def do_champion(ex, alias):
    lw = alias.lower()
    cw = Wad(f"{GAME}/Champions/{alias}.wad.client")
    wads = [cw]
    vo_path = f"{GAME}/Champions/{alias}.en_US.wad.client"
    if os.path.exists(vo_path):
        wads.append(Wad(vo_path))
    skin = cw.read(f"data/characters/{lw}/skins/skin0.bin")
    units = bank_units(skin) if skin else []
    if not units:  # fall back: any base-skin bank unit in any bin of the champion wad
        for e in cw.entries.values():
            if e.size > 20_000_000:
                continue
            try:
                d = cw.read_entry(e)
            except Exception:
                continue
            if d[:4] in (b"PROP", b"PTCH"):
                units += [u for u in bank_units(d) if "_base_" in u.name.lower()]
    groups = {"sfx": [], "vo": []}
    graphs, seen = {}, set()
    for u in units:
        vo = u.voice or "_vo" in u.name.lower() or any("/vo/" in p.lower() for p in u.paths)
        key = tuple(sorted(p.lower() for p in u.paths))
        if key not in graphs:
            graphs[key] = load_graph(wads, u.paths, log=print)
        g = graphs[key]
        for ev in u.events:
            if not ev.lower().startswith("play") or ev in seen:
                continue
            seen.add(ev)
            if vo:
                if is_vo_keep(ev):
                    groups["vo"].append((ev, g, VO_CAP))
            else:
                groups["sfx"].append((ev, g, SFX_CAP))
    out_dir = os.path.join(OUT_AUDIO, "champions", lw)
    clear_wavs(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    result, st = ex.run_groups(groups, out_dir)
    os.makedirs(OUT_DATA, exist_ok=True)
    with open(os.path.join(OUT_DATA, f"{lw}.json"), "w", encoding="utf-8") as f:
        json.dump(result, f, indent=1)
    cand = {k: len(v) for k, v in groups.items()}
    got = {k: len(v) for k, v in result.items()}
    mb = dir_size(out_dir) / 1e6
    print(f"{alias:12s} units={len(units)} candidates={cand} resolved={got} files={st['files']} "
          f"failed={st['failed']} {mb:.1f} MB")
    for w in wads:
        w.close()
    return {"alias": alias, "candidates": cand, "resolved": got, "files": st["files"],
            "failed": st["failed"], "mb": round(mb, 2)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("champions", nargs="*")
    ap.add_argument("--extras", action="store_true", help="also announcer / map12 / shared")
    ap.add_argument("--no-champions", action="store_true")
    ap.add_argument("--workers", type=int, default=16)
    a = ap.parse_args()
    scratch = tempfile.mkdtemp(prefix="lol_audio_")
    ex = Extractor(scratch, a.workers)
    try:
        summary = []
        if not a.no_champions:
            for alias in (a.champions or ROSTER):
                try:
                    summary.append(do_champion(ex, alias))
                except Exception as e:  # noqa: BLE001
                    import traceback
                    traceback.print_exc()
                    print(f"{alias}: FAILED {e}")
        if a.extras:
            do_extras(ex)
        print(f"total assets/audio/game: {dir_size(OUT_AUDIO) / 1e6:.1f} MB")
    finally:
        ex.pool.shutdown()
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    main()
