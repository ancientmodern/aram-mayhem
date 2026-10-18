"""ANM decoding: r3d2anmd (v3 legacy, v4, v5) and r3d2canm (compressed, v1-3).

Two compressed-curve evaluators are provided:
  * CompressedAnm.evaluate_ltk(t): faithful port of LeagueToolkit's hot-frame/jump-cache evaluator
  * CompressedAnm.curves() + sample_curve(): simple per-curve keyframe lists + Catmull-Rom sampling
They are cross-checked in probe_e_anm.py.
"""
from __future__ import annotations

import math
import struct
from dataclasses import dataclass

SQRT2 = 1.41421356237
INV_SQRT2 = 0.70710678118


def decompress_quat(v0: int, v1: int, v2: int):
    """48-bit 'smallest three' quaternion (3 x u16 little-endian) -> (x, y, z, w)."""
    bits = v0 | (v1 << 16) | (v2 << 32)
    max_index = (bits >> 45) & 3
    a = ((bits >> 30) & 0x7FFF) / 32767.0 * SQRT2 - INV_SQRT2
    b = ((bits >> 15) & 0x7FFF) / 32767.0 * SQRT2 - INV_SQRT2
    c = (bits & 0x7FFF) / 32767.0 * SQRT2 - INV_SQRT2
    d = math.sqrt(max(0.0, 1.0 - (a * a + b * b + c * c)))
    if max_index == 0:
        return (d, a, b, c)
    if max_index == 1:
        return (a, d, b, c)
    if max_index == 2:
        return (a, b, d, c)
    return (a, b, c, d)


def decompress_vec3(v, vmin, vmax):
    return tuple(vmin[i] + (vmax[i] - vmin[i]) * (v[i] / 65535.0) for i in range(3))


def qnorm(q):
    n = math.sqrt(sum(x * x for x in q)) or 1.0
    return tuple(x / n for x in q)


def catmull_weights(amount, ease_in, ease_out):
    """LeagueToolkit CurveSampler.CreateCatmullRomWeights (tau = ease_in / ease_out)."""
    t = amount
    m0 = (((2.0 - t) * t) - 1.0) * (t * ease_in)
    m1 = ((((2.0 - ease_out) * t) + (ease_out - 3.0)) * (t * t)) + 1.0
    m2 = ((((3.0 - ease_in * 2.0) + ((ease_in - 2.0) * t)) * t) + ease_in) * t
    m3 = ((t - 1.0) * t) * (t * ease_out)
    return m0, m1, m2, m3


def catmull(t, ti, to, p0, p1, p2, p3, is_quat=False):
    m0, m1, m2, m3 = catmull_weights(t, ti, to)
    r = tuple(m0 * p0[i] + m1 * p1[i] + m2 * p2[i] + m3 * p3[i] for i in range(len(p1)))
    return qnorm(r) if is_quat else r


EPS = 0.000001


def keyframe_weights(time, t0, t1, t2, t3):
    """Non-uniform ('parametrized') Catmull-Rom: amount + tangent scales from neighbour spacing."""
    td = t2 - t1
    amount = (time - t1) / (td + EPS)
    scale_in = td / (t2 - t0 + EPS)
    scale_out = td / (t3 - t1 + EPS)
    return amount, scale_in, scale_out


# ============================================================================ uncompressed
@dataclass
class UncompressedAnm:
    version: int
    fps: float
    frame_count: int
    duration: float
    tracks: dict        # joint_hash -> list of (rot(x,y,z,w), trans, scale) per frame
    asset_name: str = ""

    def sample(self, frame: int):
        return {h: fr[min(frame, self.frame_count - 1)] for h, fr in self.tracks.items()}


def read_uncompressed(d: bytes) -> UncompressedAnm:
    magic, version = struct.unpack_from("<8sI", d, 0)
    assert magic == b"r3d2anmd"
    if version in (4, 5):
        (res_size, fmt_token, ver2, flags, track_count, frame_count, frame_dur) = struct.unpack_from("<IIIIiif", d, 12)
        (jh_off, asset_off, time_off, vec_off, quat_off, frames_off) = struct.unpack_from("<6i", d, 40)
        # all offsets are relative to byte 12 (just after magic+version)
        B = 12
        fps = 1.0 / frame_dur
        if version == 5:
            nj = (frames_off - jh_off) // 4
            jh = struct.unpack_from(f"<{nj}I", d, B + jh_off)
            nv = (quat_off - vec_off) // 12
            vecs = [struct.unpack_from("<3f", d, B + vec_off + 12 * i) for i in range(nv)]
            nq = (jh_off - quat_off) // 6
            quats = [qnorm(decompress_quat(*struct.unpack_from("<3H", d, B + quat_off + 6 * i))) for i in range(nq)]
            tracks = {h: [] for h in jh}
            p = B + frames_off
            for f in range(frame_count):
                for t in range(track_count):
                    ti, si, ri = struct.unpack_from("<3H", d, p); p += 6
                    tracks[jh[t]].append((quats[ri], vecs[ti], vecs[si]))
        else:  # v4: joint hash stored inside each frame record, full float quats
            nv = (quat_off - vec_off) // 12
            vecs = [struct.unpack_from("<3f", d, B + vec_off + 12 * i) for i in range(nv)]
            nq = (frames_off - quat_off) // 16
            quats = [qnorm(struct.unpack_from("<4f", d, B + quat_off + 16 * i)) for i in range(nq)]
            tracks = {}
            p = B + frames_off
            for f in range(frame_count):
                for t in range(track_count):
                    h, ti, si, ri, _pad = struct.unpack_from("<I4H", d, p); p += 12
                    tracks.setdefault(h, []).append((quats[ri], vecs[ti], vecs[si]))
        return UncompressedAnm(version, fps, frame_count, frame_count * frame_dur, tracks)
    if version == 3:  # legacy: named tracks, one float quat + translation per frame, no scale
        from lolmesh import elf_hash
        skel_id, track_count, frame_count, fps = struct.unpack_from("<Iiii", d, 12)
        p = 28
        tracks = {}
        for _ in range(track_count):
            name = d[p:p + 32].split(b"\0", 1)[0].decode("ascii", "replace")
            p += 36  # name[32] + flags u32
            fr = []
            for _f in range(frame_count):
                q = struct.unpack_from("<4f", d, p); t = struct.unpack_from("<3f", d, p + 16); p += 28
                fr.append((q, t, (1.0, 1.0, 1.0)))
            tracks[elf_hash(name)] = fr
        return UncompressedAnm(3, float(fps), frame_count, frame_count / fps, tracks)
    raise ValueError(f"unsupported r3d2anmd version {version}")


# ============================================================================ compressed
@dataclass
class CompressedAnm:
    version: int
    flags: int
    joint_count: int
    frame_count: int
    jump_cache_count: int
    duration: float
    fps: float
    error_metrics: tuple
    t_min: tuple
    t_max: tuple
    s_min: tuple
    s_max: tuple
    joint_hashes: list
    frames: list            # (time u16, joint_id, type 0=rot 1=trans 2=scale, (v0,v1,v2))
    jump_caches: bytes

    @property
    def parametrized(self):
        return bool(self.flags & 4)   # UseKeyframeParametrization

    def decode_value(self, typ, v):
        if typ == 0:
            return decompress_quat(*v)
        if typ == 1:
            return decompress_vec3(v, self.t_min, self.t_max)
        return decompress_vec3(v, self.s_min, self.s_max)

    # ---------------------------------------------------------------- simple approach
    def curves(self, align_quats: bool = True):
        """{(joint_index, type): [(time_u16, value), ...]} in stream order (= increasing time).
        Rotation keys are sign-aligned sequentially (q[i] = -q[i] if dot(q[i], q[i-1]) < 0)."""
        out = {}
        for (tm, j, typ, v) in self.frames:
            val = self.decode_value(typ, v)
            lst = out.setdefault((j, typ), [])
            if typ == 0 and align_quats and lst and sum(a * b for a, b in zip(val, lst[-1][1])) < 0:
                val = tuple(-x for x in val)
            lst.append((tm, val))
        return out

    def sample_curve(self, keys, t_u16, is_quat):
        """Catmull-Rom through key list at compressed time t (0..65535)."""
        n = len(keys)
        if n == 1:
            return keys[0][1]
        # find segment i with keys[i].t <= t < keys[i+1].t
        i = 0
        lo, hi = 0, n - 1
        while lo < hi:  # last index with time <= t
            mid = (lo + hi + 1) // 2
            if keys[mid][0] <= t_u16:
                lo = mid
            else:
                hi = mid - 1
        i = min(lo, n - 2)
        k0 = keys[max(i - 1, 0)]; k1 = keys[i]; k2 = keys[i + 1]; k3 = keys[min(i + 2, n - 1)]
        p0, p1, p2, p3 = k0[1], k1[1], k2[1], k3[1]
        if is_quat:  # shortest path relative to P0 (P1..P3; LTK only aligns P1, P2 - see spec)
            p1 = p1 if sum(a * b for a, b in zip(p1, p0)) >= 0 else tuple(-x for x in p1)
            p2 = p2 if sum(a * b for a, b in zip(p2, p0)) >= 0 else tuple(-x for x in p2)
            p3 = p3 if sum(a * b for a, b in zip(p3, p0)) >= 0 else tuple(-x for x in p3)
        if self.parametrized:
            amount, si, so = keyframe_weights(t_u16, k0[0], k1[0], k2[0], k3[0])
        else:
            td = k2[0] - k1[0]
            amount, si, so = ((t_u16 - k1[0]) / td if td else 0.0), 0.5, 0.5
        return catmull(amount, si, so, p0, p1, p2, p3, is_quat)

    def evaluate(self, time):
        """Recommended evaluator: {joint_hash: (rotation xyzw, translation, scale)} at time (seconds)."""
        if not hasattr(self, "_curves"):
            self._curves = self.curves()
        ct = int(min(max(time, 0.0), self.duration) / self.duration * 65535)
        return {h: tuple(self.sample_curve(self._curves[(j, typ)], ct, typ == 0) for typ in range(3))
                for j, h in enumerate(self.joint_hashes)}

    # ---------------------------------------------------------------- faithful LTK port
    def _init_hot(self, t):
        jc = min(int(self.jump_cache_count * (t / self.duration)), self.jump_cache_count - 1)
        u16 = self.frame_count < 0x10001
        size = (24 if u16 else 48) * self.joint_count
        base = jc * size
        fmt = "<12H" if u16 else "<12I"
        step = 24 if u16 else 48
        self._cursor = 0
        self._hot = []
        for j in range(self.joint_count):
            keys = struct.unpack_from(fmt, self.jump_caches, base + j * step)
            curves = []
            for typ in range(3):  # rotation, translation, scale keys (4 each)
                hf = []
                for k in keys[typ * 4: typ * 4 + 4]:
                    tm, _jid, _ty, v = self.frames[k]
                    self._cursor = max(self._cursor, k)
                    hf.append([tm, self.decode_value(typ, v)])
                if typ == 0:
                    for i in (1, 2):
                        if sum(a * b for a, b in zip(hf[i][1], hf[0][1])) < 0:
                            hf[i][1] = tuple(-x for x in hf[i][1])
                curves.append(hf)
            self._hot.append(curves)
        self._cursor += 1

    def evaluate_ltk(self, time):
        time = min(max(time, 0.0), self.duration)
        ct = int(time / self.duration * 65535)
        last = getattr(self, "_last", -1.0)
        if last < 0 or last > time or (time - last) > self.duration / self.jump_cache_count:
            self._init_hot(time)
        while self._cursor < len(self.frames):
            tm, j, typ, v = self.frames[self._cursor]
            hf = self._hot[j][typ]
            if ct < hf[2][0]:
                break
            new = [tm, self.decode_value(typ, v)]
            hf[:] = [hf[1], hf[2], hf[3], new]          # shift window, append new key as P3
            if typ == 0:
                for i in (1, 2):
                    if sum(a * b for a, b in zip(hf[i][1], hf[0][1])) < 0:
                        hf[i][1] = tuple(-x for x in hf[i][1])
            self._cursor += 1
        self._last = time
        pose = {}
        for j, h in enumerate(self.joint_hashes):
            res = []
            for typ in range(3):
                (t0, p0), (t1, p1), (t2, p2), (t3, p3) = self._hot[j][typ]
                if self.parametrized:
                    amount, si, so = keyframe_weights(ct, t0, t1, t2, t3)
                else:
                    amount, si, so = (ct - t1) / (t2 - t1) if t2 != t1 else 0.0, 0.5, 0.5
                res.append(catmull(amount, si, so, p0, p1, p2, p3, typ == 0))
            pose[h] = tuple(res)  # (rotation, translation, scale)
        return pose


def read_compressed(d: bytes) -> CompressedAnm:
    magic, version = struct.unpack_from("<8sI", d, 0)
    assert magic == b"r3d2canm" and version in (1, 2, 3)
    (res_size, fmt_token, flags, jcount, fcount, jccount, duration, fps) = struct.unpack_from("<IIIiiiff", d, 12)
    em = struct.unpack_from("<6f", d, 44)      # (margin, discontinuity) x rotation, translation, scale
    t_min = struct.unpack_from("<3f", d, 68); t_max = struct.unpack_from("<3f", d, 80)
    s_min = struct.unpack_from("<3f", d, 92); s_max = struct.unpack_from("<3f", d, 104)
    frames_off, jc_off, jh_off = struct.unpack_from("<3i", d, 116)
    B = 12  # offsets relative to byte 12
    jh = list(struct.unpack_from(f"<{jcount}I", d, B + jh_off))
    frames = []
    p = B + frames_off
    for _ in range(fcount):
        tm, jt, v0, v1, v2 = struct.unpack_from("<5H", d, p); p += 10
        frames.append((tm, jt & 0x3FFF, jt >> 14, (v0, v1, v2)))
    step = 24 if fcount < 0x10001 else 48
    jc = d[B + jc_off: B + jc_off + step * jcount * jccount]
    return CompressedAnm(version, flags, jcount, fcount, jccount, duration, fps, em,
                         t_min, t_max, s_min, s_max, jh, frames, jc)


def read_anm(d: bytes):
    if d[:8] == b"r3d2canm":
        return read_compressed(d)
    if d[:8] == b"r3d2anmd":
        return read_uncompressed(d)
    raise ValueError("not an ANM")
