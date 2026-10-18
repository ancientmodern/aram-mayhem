"""Minimal reader for League 'PROP'/'PTCH' property bins (.bin), version 1..3.

Produces plain Python values:
  object  -> BinObject(class_hash, path_hash, fields: dict[name_hash] -> (type, value))
  embed / pointer -> BinStruct(class_hash, fields)  (pointer with class 0 -> None)
  list/list2 -> list, map -> dict, option -> value or None
  hash/link -> int (u32 FNV1a), file -> int (u64 xxh64 path hash), string -> str
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field


def fnv1a32(s: str) -> int:
    """Bin class/field/entry/hash names: FNV-1a 32-bit of the lower-cased ASCII string."""
    h = 0x811C9DC5
    for c in s.lower().encode("utf-8"):
        h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF
    return h


# Current (non-legacy) type ids
T = dict(NONE=0, BOOL=1, I8=2, U8=3, I16=4, U16=5, I32=6, U32=7, I64=8, U64=9, F32=10,
         VEC2=11, VEC3=12, VEC4=13, MTX44=14, RGBA=15, STRING=16, HASH=17, FILE=18,
         LIST=0x80, LIST2=0x81, POINTER=0x82, EMBED=0x83, LINK=0x84, OPTION=0x85, MAP=0x86, FLAG=0x87)
TYPE_NAMES = {v: k.lower() for k, v in T.items()}

_FIXED = {  # type -> struct format for fixed-size primitives
    1: "<?", 2: "<b", 3: "<B", 4: "<h", 5: "<H", 6: "<i", 7: "<I", 8: "<q", 9: "<Q", 10: "<f",
    11: "<2f", 12: "<3f", 13: "<4f", 14: "<16f", 15: "<4B", 17: "<I", 18: "<Q", 0x84: "<I", 0x87: "<B",
}


class InvalidType(Exception):
    pass


@dataclass(slots=True)
class BinStruct:
    class_hash: int
    fields: dict = field(default_factory=dict)   # name_hash -> (type, value)

    def get(self, name: str | int, default=None):
        h = fnv1a32(name) if isinstance(name, str) else name
        v = self.fields.get(h)
        return default if v is None else v[1]


@dataclass(slots=True)
class BinObject(BinStruct):
    path_hash: int = 0


class _Reader:
    def __init__(self, data: bytes, legacy: bool):
        self.d = data
        self.p = 0
        self.legacy = legacy

    def u8(self):
        v = self.d[self.p]; self.p += 1; return v

    def unpack(self, fmt):
        v = struct.unpack_from(fmt, self.d, self.p)
        self.p += struct.calcsize(fmt)
        return v

    def typ(self):
        t = self.u8()
        if self.legacy:  # files written before 'file' (18) was inserted
            if 18 <= t < 0x80:
                t = (t - 18) | 0x80
            if t >= 0x81:
                t += 1
        if t not in TYPE_NAMES:
            raise InvalidType(t)
        return t

    def value(self, t):
        if t in _FIXED:
            v = self.unpack(_FIXED[t])
            return v[0] if len(v) == 1 else v
        if t == 0:
            return None
        if t == 16:
            (n,) = self.unpack("<H")
            s = self.d[self.p:self.p + n].decode("utf-8", "replace"); self.p += n
            return s
        if t in (0x80, 0x81):
            et = self.typ()
            (size, count) = self.unpack("<II")
            return [self.value(et) for _ in range(count)]
        if t in (0x82, 0x83):
            (ch,) = self.unpack("<I")
            if ch == 0:
                return None
            (size, n) = self.unpack("<IH")
            s = BinStruct(ch)
            for _ in range(n):
                nh, ft, fv = self.field()
                s.fields[nh] = (ft, fv)
            return s
        if t == 0x85:
            et = self.typ()
            some = self.u8()
            return self.value(et) if some else None
        if t == 0x86:
            kt = self.typ(); vt = self.typ()
            (size, count) = self.unpack("<II")
            out = {}
            for _ in range(count):
                k = self.value(kt)
                out[k if not isinstance(k, list) else tuple(k)] = self.value(vt)
            return out
        raise InvalidType(t)

    def field(self):
        (nh,) = self.unpack("<I")
        t = self.typ()
        return nh, t, self.value(t)


@dataclass
class BinFile:
    is_patch: bool
    version: int
    dependencies: list
    objects: dict          # path_hash -> BinObject
    legacy_types: bool


def read_bin(data: bytes) -> BinFile:
    p = 0
    is_patch = data[:4] == b"PTCH"
    if is_patch:
        p = 12        # 'PTCH', u32 version(1), u32 unknown
    if data[p:p + 4] != b"PROP":
        raise ValueError("not a PROP bin")
    (version,) = struct.unpack_from("<I", data, p + 4)
    p += 8
    deps = []
    if version >= 2:
        (n,) = struct.unpack_from("<I", data, p); p += 4
        for _ in range(n):
            (l,) = struct.unpack_from("<H", data, p); p += 2
            deps.append(data[p:p + l].decode()); p += l
    (count,) = struct.unpack_from("<I", data, p); p += 4
    classes = struct.unpack_from(f"<{count}I", data, p); p += 4 * count
    for legacy in (False, True):
        r = _Reader(data, legacy)
        r.p = p
        objs = {}
        try:
            for ch in classes:
                (size, path_hash, n) = r.unpack("<IIH")
                o = BinObject(ch, {}, path_hash)
                for _ in range(n):
                    nh, ft, fv = r.field()
                    o.fields[nh] = (ft, fv)
                objs[path_hash] = o
            return BinFile(is_patch, version, deps, objs, legacy)
        except (InvalidType, struct.error, IndexError):
            continue
    raise ValueError("failed to parse bin")


def walk(value, path=()):
    """Yield (path, type, value) for every leaf, descending into structs/lists/maps."""
    if isinstance(value, BinStruct):
        for nh, (t, v) in value.fields.items():
            yield path + (nh,), t, v
            yield from walk(v, path + (nh,))
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from walk(v, path + (i,))
    elif isinstance(value, dict):
        for k, v in value.items():
            yield from walk(v, path + (k,))
